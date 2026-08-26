#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
TEST_ROOT="$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(CDPATH= cd "$TEST_ROOT/.." && pwd)"
. "$TEST_ROOT/lib/test-common.sh"

############################################################
# SETUP / MAIN / END
############################################################

setup() {
    define_colours
    PROJECT_VERSION="3.7.1"
    TEST_SUITE_VERSION="3.1.1"
    TEST_GROUP="inspection"
    test_reset_counters
    test_parse_arguments "$@"
    [ "$TEST_RUN" = "false" ] || check_elevation
}

main() {
    [ "$TEST_RUN" = "true" ] || { print_plan; return 0; }
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    require_proxmox_environment
    for CMD in sfdisk partx blkid blockdev mkfs.ext4 truncate dd; do require_command "$CMD"; done
    test_prepare_run
    create_storage_sandbox
    prepare_inspection_fixture
    run_case "list-vm-disks.sh" test_list_vm_disks
    run_case "list-all-vm-lvm.sh" test_list_all_vm_lvm
    run_case "verify-vm-disk-numbering.sh" test_verify_vm_disk_numbering
    run_case "list-all-vm-lvm-filesystems.sh" test_list_all_vm_lvm_filesystems
    run_case "find-volume-owner.sh" test_find_volume_owner
    run_case "find-orphaned-volumes.sh" test_find_orphaned_volumes
    run_case "audit-vm-storage.sh" test_audit_vm_storage
}

end() {
    [ "$TEST_RUN" = "true" ] || return 0
    [ "${APP_ELEVATED:-false}" = "true" ] || return 0
    test_finish_run
}

############################################################
# TEST PLAN
############################################################

print_plan() {
    print_banner "Inspection / audit tests"
    printf '%s\n' "Disposable fixture: loopback LVM-thin storage, a stopped VM, a template/base LV, and vm/base orphan LVs."
    printf '%s\n' "Commands: list-vm-disks, list-all-vm-lvm, verify-vm-disk-numbering, list-all-vm-lvm-filesystems, find-volume-owner, find-orphaned-volumes, audit-vm-storage."
    printf '%s\n' "All inspection commands are read-only; no production guest or production LV is referenced."
}

############################################################
# FIXTURE
############################################################

prepare_inspection_fixture() {
    INSPECT_VM="$(create_test_vm inspect)"
    INSPECT_LV_NAME="vm-${INSPECT_VM}-disk-0"
    INSPECT_LV="$(create_thin_lv "$TEST_VG_A" "$INSPECT_LV_NAME" 32M)"
    write_test_pattern "$INSPECT_LV" "inspection-attached"
    attach_test_lv "$INSPECT_VM" "$TEST_STORAGE_A" "$INSPECT_LV_NAME" scsi0
    INSPECT_BASE_VM="$(create_test_vm inspect-base)"
    INSPECT_BASE_SEED="vm-${INSPECT_BASE_VM}-disk-0"
    create_thin_lv "$TEST_VG_A" "$INSPECT_BASE_SEED" 16M >/dev/null
    attach_test_lv "$INSPECT_BASE_VM" "$TEST_STORAGE_A" "$INSPECT_BASE_SEED" scsi0
    qm template "$INSPECT_BASE_VM" >/dev/null
    INSPECT_BASE_NAME="base-${INSPECT_BASE_VM}-disk-0"
    INSPECT_BASE_LV="/dev/${TEST_VG_A}/${INSPECT_BASE_NAME}"
    assert_lv_exists "$TEST_VG_A/$INSPECT_BASE_NAME"

    INSPECT_ORPHAN_ID="$(allocate_free_vmid)"
    INSPECT_ORPHAN_NAME="vm-${INSPECT_ORPHAN_ID}-disk-0"
    INSPECT_ORPHAN_LV="$(create_thin_lv "$TEST_VG_A" "$INSPECT_ORPHAN_NAME" 16M)"

    INSPECT_BASE_ORPHAN_ID="$(allocate_free_vmid)"
    INSPECT_BASE_ORPHAN_NAME="base-${INSPECT_BASE_ORPHAN_ID}-disk-0"
    INSPECT_BASE_ORPHAN_LV="$(create_thin_lv "$TEST_VG_A" "$INSPECT_BASE_ORPHAN_NAME" 16M)"

    # Deliberately inconsistent managed name: current VMID references another
    # embedded VMID and starts at disk-5, exercising both numbering warnings.
    INSPECT_NUMBER_VM="$(create_test_vm inspect-numbering)"
    INSPECT_NUMBER_STALE_ID="$(allocate_free_vmid)"
    INSPECT_NUMBER_NAME="vm-${INSPECT_NUMBER_STALE_ID}-disk-5"
    INSPECT_NUMBER_LV="$(create_thin_lv "$TEST_VG_A" "$INSPECT_NUMBER_NAME" 16M)"
    INSPECT_NUMBER_GAP_NAME="vm-${INSPECT_NUMBER_VM}-disk-7"
    INSPECT_NUMBER_GAP_LV="$(create_thin_lv "$TEST_VG_A" "$INSPECT_NUMBER_GAP_NAME" 16M)"
    INSPECT_NUMBER_DUP_NAME="base-${INSPECT_NUMBER_STALE_ID}-disk-7"
    INSPECT_NUMBER_DUP_LV="$(create_thin_lv "$TEST_VG_A" "$INSPECT_NUMBER_DUP_NAME" 16M)"
    INSPECT_NUMBER_ARCHIVE_NAME="vm-${INSPECT_NUMBER_VM}-disk-901"
    INSPECT_NUMBER_ARCHIVE_LV="$(create_thin_lv "$TEST_VG_A" "$INSPECT_NUMBER_ARCHIVE_NAME" 16M)"
    attach_test_lv "$INSPECT_NUMBER_VM" "$TEST_STORAGE_A" "$INSPECT_NUMBER_NAME" scsi0
    attach_test_lv "$INSPECT_NUMBER_VM" "$TEST_STORAGE_A" "$INSPECT_NUMBER_GAP_NAME" scsi1
    attach_test_lv "$INSPECT_NUMBER_VM" "$TEST_STORAGE_A" "$INSPECT_NUMBER_DUP_NAME" scsi2
    attach_test_lv "$INSPECT_NUMBER_VM" "$TEST_STORAGE_A" "$INSPECT_NUMBER_ARCHIVE_NAME" scsi3
    qm set "$INSPECT_NUMBER_VM" --delete scsi3 >/dev/null

    # Read-only filesystem inventory fixture. A GPT Linux-filesystem partition
    # starts at 1 MiB and contains a real ext4 image written only to test-owned LV.
    INSPECT_FS_VM="$(create_test_vm inspect-fs)"
    INSPECT_FS_NAME="vm-${INSPECT_FS_VM}-disk-0"
    INSPECT_FS_LV="$(create_thin_lv "$TEST_VG_A" "$INSPECT_FS_NAME" 96M)"
    printf '%s\n' \
        'label: gpt' \
        'size=24M,type=0FC63DAF-8483-4772-8E79-3D69D8477DE4' \
        'size=24M,type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7' | sfdisk "$INSPECT_FS_LV" >/dev/null 2>&1
    INSPECT_FS_IMAGE="$TEST_DATA_DIR/inspect-ext4.img"
    truncate -s 8M "$INSPECT_FS_IMAGE"
    mkfs.ext4 -F -q "$INSPECT_FS_IMAGE"
    INSPECT_FS_SECTOR="$(blockdev --getss "$INSPECT_FS_LV")"
    INSPECT_FS_P1="$(partx --show --noheadings -o NR,START "$INSPECT_FS_LV" | awk '$1==1 {print $2; exit}')"
    INSPECT_FS_P2="$(partx --show --noheadings -o NR,START "$INSPECT_FS_LV" | awk '$1==2 {print $2; exit}')"
    [ -n "$INSPECT_FS_P1" ] && [ -n "$INSPECT_FS_P2" ] || die "Could not determine disposable partition offsets."
    dd if="$INSPECT_FS_IMAGE" of="$INSPECT_FS_LV" bs="$INSPECT_FS_SECTOR" seek="$INSPECT_FS_P1" conv=notrunc,fsync 2>/dev/null
    dd if="$INSPECT_FS_IMAGE" of="$INSPECT_FS_LV" bs="$INSPECT_FS_SECTOR" seek="$INSPECT_FS_P2" conv=notrunc,fsync 2>/dev/null
    attach_test_lv "$INSPECT_FS_VM" "$TEST_STORAGE_A" "$INSPECT_FS_NAME" scsi0
}

############################################################
# TEST CASES
############################################################

test_list_vm_disks() {
    tlvd_out="$TEST_DATA_DIR/list-vm-disks.txt"
    project_cmd list-vm-disks.sh "$INSPECT_VM" > "$tlvd_out"
    assert_contains "$tlvd_out" "$TEST_STORAGE_A:$INSPECT_LV_NAME"
}

test_list_all_vm_lvm() {
    tal_out="$TEST_DATA_DIR/list-all-vm-lvm.txt"
    project_cmd list-all-vm-lvm.sh > "$tal_out"
    assert_contains "$tal_out" "VM $INSPECT_VM"
    assert_contains "$tal_out" "$INSPECT_LV"
    assert_contains "$tal_out" "VM $INSPECT_BASE_VM"
    assert_contains "$tal_out" "$INSPECT_BASE_LV"
    assert_contains "$tal_out" "Remaining LVM volumes"
    assert_contains "$tal_out" "$INSPECT_ORPHAN_LV"
    assert_contains "$tal_out" "$INSPECT_BASE_ORPHAN_LV"
}

test_verify_vm_disk_numbering() {
    tvdn_out="$TEST_DATA_DIR/verify-vm-disk-numbering.txt"
    project_cmd verify-vm-disk-numbering.sh > "$tvdn_out"
    assert_contains "$tvdn_out" "VM $INSPECT_NUMBER_VM"
    assert_contains "$tvdn_out" "$INSPECT_NUMBER_LV"
    assert_contains "$tvdn_out" "VMID MISMATCH"
    assert_contains "$tvdn_out" "ACTIVE STARTS AT disk-5"
    assert_contains "$tvdn_out" "GAP AT disk-6"
    assert_contains "$tvdn_out" "DUPLICATE disk-7"
    ! grep -F "GAP AT disk-8" "$tvdn_out" >/dev/null
    assert_contains "$tvdn_out" "$INSPECT_NUMBER_ARCHIVE_LV"
}

test_list_all_vm_lvm_filesystems() {
    tlaf_out="$TEST_DATA_DIR/list-all-vm-lvm-filesystems.txt"
    project_cmd list-all-vm-lvm-filesystems.sh > "$tlaf_out"
    assert_contains "$tlaf_out" "VM $INSPECT_FS_VM"
    assert_contains "$tlaf_out" "$INSPECT_FS_LV"
    assert_contains "$tlaf_out" "Partition table: gpt"
    assert_contains "$tlaf_out" "TABLE_HINT"
    assert_contains "$tlaf_out" "CONTENT_FORMAT"
    assert_contains "$tlaf_out" "Linux filesystem"
    assert_contains "$tlaf_out" "Microsoft basic data"
    assert_contains "$tlaf_out" "ext4"
    assert_contains "$tlaf_out" "MISMATCH: table says Microsoft basic data; content is ext4"
    assert_contains "$tlaf_out" "Remaining LVM volumes"
    assert_contains "$tlaf_out" "$INSPECT_ORPHAN_LV"
}

test_find_volume_owner() {
    tfvo_out="$TEST_DATA_DIR/find-volume-owner.txt"
    project_cmd find-volume-owner.sh "$INSPECT_LV" > "$tfvo_out"
    assert_contains "$tfvo_out" "${INSPECT_VM}.conf"
}

test_find_orphaned_volumes() {
    tfov_out="$TEST_DATA_DIR/find-orphaned.txt"
    project_cmd find-orphaned-volumes.sh "$TEST_VG_A" > "$tfov_out"
    assert_contains "$tfov_out" "$INSPECT_ORPHAN_NAME"
    assert_contains "$tfov_out" "$INSPECT_BASE_ORPHAN_NAME"
}

test_audit_vm_storage() {
    project_cmd audit-vm-storage.sh "$INSPECT_VM"
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
