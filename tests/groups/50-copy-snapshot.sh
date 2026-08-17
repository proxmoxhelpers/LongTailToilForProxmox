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
    PROJECT_VERSION="3.2.0"
    TEST_SUITE_VERSION="2.2.0"
    TEST_GROUP="copy-snapshot"
    test_reset_counters
    test_parse_arguments "$@"
    [ "$TEST_RUN" = "false" ] || check_elevation
}

main() {
    [ "$TEST_RUN" = "true" ] || { print_plan; return 0; }
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    require_proxmox_environment
    for CMD in dd cmp; do require_command "$CMD"; done
    test_prepare_run
    create_storage_sandbox
    prepare_copy_fixture
    run_case "create-disk-snapshot-and-add-to-vm.sh" test_create_snapshot_add
    run_case "create-disk-copy-and-add-to-vm.sh" test_create_copy_add
    run_case "create-disk-copy-and-overwrite-disk-on-vm.sh" test_create_copy_overwrite
    run_case "create-disk-snapshot-and-overwrite-disk-on-vm.sh" test_create_snapshot_overwrite
    run_case "copy-disk-between-vms.sh" test_copy_between_vms
    run_case "snapshot-disk-between-vms.sh" test_snapshot_between_vms
    run_case "clone-single-vm-disk.sh" test_clone_single_disk
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
    print_banner "Copy / snapshot tests"
    printf '%s\n' "Creates stopped source/destination VMs and a 32 MiB thin source disk."
    printf '%s\n' "Tests same-pool snapshots, independent copies, and copy/snapshot overwrite with old-disk preservation."
    printf '%s\n' "All resulting volumes remain in disposable test storages and are removed during ownership-checked cleanup."
}

############################################################
# FIXTURE
############################################################

prepare_copy_fixture() {
    COPY_SRC_VM="$(create_test_vm copy-src)"
    COPY_DST_VM="$(create_test_vm copy-dst)"
    COPY_SRC_LV_NAME="vm-${COPY_SRC_VM}-disk-0"
    COPY_SRC_LV="$(create_thin_lv "$TEST_VG_A" "$COPY_SRC_LV_NAME" 32M)"
    write_test_pattern "$COPY_SRC_LV" "copy-snapshot-source"
    attach_test_lv "$COPY_SRC_VM" "$TEST_STORAGE_A" "$COPY_SRC_LV_NAME" scsi0

    COPY_OVERWRITE_VM="$(create_test_vm copy-overwrite)"
    COPY_OVERWRITE_OLD_NAME="vm-${COPY_OVERWRITE_VM}-disk-0"
    COPY_OVERWRITE_OLD_LV="$(create_thin_lv "$TEST_VG_B" "$COPY_OVERWRITE_OLD_NAME" 32M)"
    write_test_pattern "$COPY_OVERWRITE_OLD_LV" "copy-overwrite-old"
    attach_test_lv "$COPY_OVERWRITE_VM" "$TEST_STORAGE_B" "$COPY_OVERWRITE_OLD_NAME" scsi0

    SNAP_OVERWRITE_VM="$(create_test_vm snapshot-overwrite)"
    SNAP_OVERWRITE_OLD_NAME="vm-${SNAP_OVERWRITE_VM}-disk-0"
    SNAP_OVERWRITE_OLD_LV="$(create_thin_lv "$TEST_VG_B" "$SNAP_OVERWRITE_OLD_NAME" 32M)"
    write_test_pattern "$SNAP_OVERWRITE_OLD_LV" "snapshot-overwrite-old"
    attach_test_lv "$SNAP_OVERWRITE_VM" "$TEST_STORAGE_B" "$SNAP_OVERWRITE_OLD_NAME" scsi0
}

############################################################
# TEST CASES
############################################################

test_create_snapshot_add() {
    tcsa_before="$(qm config "$COPY_DST_VM" | grep -c '^scsi' || :)"
    run_dryrun_unchanged "create-snapshot-add" create-disk-snapshot-and-add-to-vm.sh "$COPY_SRC_LV" "$COPY_DST_VM"
    project_cmd create-disk-snapshot-and-add-to-vm.sh "$COPY_SRC_LV" "$COPY_DST_VM"
    tcsa_after="$(qm config "$COPY_DST_VM" | grep -c '^scsi' || :)"
    [ "$tcsa_after" -gt "$tcsa_before" ]
    lvs --noheadings -o origin "$TEST_VG_A" 2>/dev/null | grep -F "$COPY_SRC_LV_NAME" >/dev/null
}

test_create_copy_add() {
    tcca_before="$(qm config "$COPY_DST_VM" | grep -c '^scsi' || :)"
    run_dryrun_unchanged "create-copy-add" create-disk-copy-and-add-to-vm.sh "$COPY_SRC_LV" "$COPY_DST_VM" "$TEST_VG_B"
    project_cmd create-disk-copy-and-add-to-vm.sh "$COPY_SRC_LV" "$COPY_DST_VM" "$TEST_VG_B"
    tcca_after="$(qm config "$COPY_DST_VM" | grep -c '^scsi' || :)"
    [ "$tcca_after" -gt "$tcca_before" ]
    qm config "$COPY_DST_VM" | grep -F "$TEST_STORAGE_B:vm-${COPY_DST_VM}-disk-" >/dev/null
}

test_create_copy_overwrite() {
    tcow_old_volid="$TEST_STORAGE_B:$COPY_OVERWRITE_OLD_NAME"
    run_dryrun_unchanged "create-copy-overwrite" create-disk-copy-and-overwrite-disk-on-vm.sh "$COPY_SRC_VM" disk-0 "$COPY_OVERWRITE_VM" disk-0 pause
    project_cmd create-disk-copy-and-overwrite-disk-on-vm.sh "$COPY_SRC_VM" disk-0 "$COPY_OVERWRITE_VM" disk-0

    tcow_new_volid="$(qm config "$COPY_OVERWRITE_VM" | sed -n 's/^scsi0:[[:space:]]*//p' | head -n1 | cut -d, -f1)"
    [ "$tcow_new_volid" != "$tcow_old_volid" ]
    tcow_new_path="$(pvesm path "$tcow_new_volid")"
    cmp -n 33554432 "$COPY_SRC_LV" "$tcow_new_path"
    qm config "$COPY_OVERWRITE_VM" | grep -E "^unused[0-9]+: ${tcow_old_volid}([,[:space:]]|$)" >/dev/null
}

test_create_snapshot_overwrite() {
    tsow_old_volid="$TEST_STORAGE_B:$SNAP_OVERWRITE_OLD_NAME"
    run_dryrun_unchanged "create-snapshot-overwrite" create-disk-snapshot-and-overwrite-disk-on-vm.sh "$COPY_SRC_LV" "$SNAP_OVERWRITE_OLD_LV" restart
    project_cmd create-disk-snapshot-and-overwrite-disk-on-vm.sh "$COPY_SRC_LV" "$SNAP_OVERWRITE_OLD_LV"

    tsow_new_volid="$(qm config "$SNAP_OVERWRITE_VM" | sed -n 's/^scsi0:[[:space:]]*//p' | head -n1 | cut -d, -f1)"
    [ "$tsow_new_volid" != "$tsow_old_volid" ]
    tsow_new_path="$(pvesm path "$tsow_new_volid")"
    tsow_origin="$(lvs --noheadings -o origin "$tsow_new_path" | trim)"
    [ "$tsow_origin" = "$COPY_SRC_LV_NAME" ]
    qm config "$SNAP_OVERWRITE_VM" | grep -E "^unused[0-9]+: ${tsow_old_volid}([,[:space:]]|$)" >/dev/null
}

test_copy_between_vms() {
    tcbv_before="$(qm config "$COPY_DST_VM" | grep -c '^scsi' || :)"
    run_dryrun_unchanged "copy-between-vms" copy-disk-between-vms.sh "$COPY_SRC_VM" scsi0 "$COPY_DST_VM" "$TEST_VG_B"
    project_cmd copy-disk-between-vms.sh "$COPY_SRC_VM" scsi0 "$COPY_DST_VM" "$TEST_VG_B"
    tcbv_after="$(qm config "$COPY_DST_VM" | grep -c '^scsi' || :)"
    [ "$tcbv_after" -gt "$tcbv_before" ]
}

test_snapshot_between_vms() {
    tsbv_before="$(qm config "$COPY_DST_VM" | grep -c '^scsi' || :)"
    run_dryrun_unchanged "snapshot-between-vms" snapshot-disk-between-vms.sh "$COPY_SRC_VM" scsi0 "$COPY_DST_VM"
    project_cmd snapshot-disk-between-vms.sh "$COPY_SRC_VM" scsi0 "$COPY_DST_VM"
    tsbv_after="$(qm config "$COPY_DST_VM" | grep -c '^scsi' || :)"
    [ "$tsbv_after" -gt "$tsbv_before" ]
}

test_clone_single_disk() {
    tcsd_before="$(qm config "$COPY_SRC_VM" | grep -c '^scsi' || :)"
    run_dryrun_unchanged "clone-single-disk" clone-single-vm-disk.sh "$COPY_SRC_VM" scsi0 "$TEST_VG_B"
    project_cmd clone-single-vm-disk.sh "$COPY_SRC_VM" scsi0 "$TEST_VG_B"
    tcsd_after="$(qm config "$COPY_SRC_VM" | grep -c '^scsi' || :)"
    [ "$tcsd_after" -gt "$tcsd_before" ]
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
