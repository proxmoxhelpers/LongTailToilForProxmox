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
    PROJECT_VERSION="3.4.4"
    TEST_SUITE_VERSION="2.8.2"
    TEST_GROUP="storage-io"
    test_reset_counters
    test_parse_arguments "$@"
    [ "$TEST_RUN" = "false" ] || check_elevation
}

main() {
    [ "$TEST_RUN" = "true" ] || { print_plan; return 0; }
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    require_proxmox_environment
    for CMD in qemu-img; do require_command "$CMD"; done
    test_prepare_run
    create_storage_sandbox
    run_case "move-disk-to-storage.sh preserves bytes/options" test_move_disk_storage
    run_case "bulk-change-vm-storage.sh multi-VM byte preservation" test_bulk_change_storage
    run_case "import-disk-and-attach.sh explicit + default slots" test_import_disk
    run_case "export-vm-disk.sh qcow2 + inferred raw with byte verification" test_export_disk
    run_case "change-vm-storage-prefix.sh preserves volume/options" test_change_storage_prefix
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
    print_banner "Storage move / import / export tests"
    printf '%s\n' "Uses two disposable Proxmox LVM-thin storage IDs backed by loop files."
    printf '%s\n' "Tests individual/multi-VM storage moves with byte and option preservation, explicit/default-slot import, qcow2/raw export, and storage-prefix rewriting."
    printf '%s\n' "Every source image/LV carries a disposable data pattern and moves/exports are compared against it; the alias maps only to the test VG."
}

############################################################
# FIXTURE HELPERS
############################################################

create_vm_with_disk_a() {
    cvwda_role="$1"
    cvwda_vm="$(create_test_vm "$cvwda_role")"
    cvwda_name="vm-${cvwda_vm}-disk-0"
    cvwda_lv="$(create_thin_lv "$TEST_VG_A" "$cvwda_name" 32M)"
    write_test_pattern "$cvwda_lv" "$cvwda_role"
    qm set "$cvwda_vm" --scsi0 "$TEST_STORAGE_A:$cvwda_name,cache=writeback,discard=on" >/dev/null
    printf '%s\n' "$cvwda_vm"
}

slot_volid() {
    sv_vm="$1"; sv_slot="$2"
    qm config "$sv_vm" | awk -F': ' -v slot="$sv_slot" '$1==slot {split($2,a,","); print a[1]; exit}'
}

hash_first_32m() {
    dd if="$1" bs=1M count=32 status=none | sha256sum | awk '{print $1}'
}

############################################################
# TEST CASES
############################################################

test_move_disk_storage() {
    tmds_vm="$(create_vm_with_disk_a move-storage)"
    tmds_before_value="$(qm config "$tmds_vm" | sed -n 's/^scsi0:[[:space:]]*//p')"
    tmds_before_volid="${tmds_before_value%%,*}"
    tmds_before_suffix="${tmds_before_value#"$tmds_before_volid"}"
    tmds_old_path="$(pvesm path "$tmds_before_volid")"
    tmds_hash="$(hash_first_32m "$tmds_old_path")"

    run_dryrun_unchanged "move-disk-storage" move-disk-to-storage.sh "$tmds_vm" scsi0 "$TEST_STORAGE_B"
    project_cmd move-disk-to-storage.sh "$tmds_vm" scsi0 "$TEST_STORAGE_B"

    tmds_after_value="$(qm config "$tmds_vm" | sed -n 's/^scsi0:[[:space:]]*//p')"
    tmds_after_volid="${tmds_after_value%%,*}"
    tmds_after_suffix="${tmds_after_value#"$tmds_after_volid"}"
    [ "${tmds_after_volid%%:*}" = "$TEST_STORAGE_B" ]
    [ "$tmds_after_suffix" = "$tmds_before_suffix" ]
    tmds_new_path="$(pvesm path "$tmds_after_volid")"
    [ "$(hash_first_32m "$tmds_new_path")" = "$tmds_hash" ]
    ! lvs "$tmds_old_path" >/dev/null 2>&1
}

test_bulk_change_storage() {
    tbcs_vm1="$(create_vm_with_disk_a bulk-storage-a)"
    tbcs_vm2="$(create_vm_with_disk_a bulk-storage-b)"
    tbcs_old1="$(slot_volid "$tbcs_vm1" scsi0)"; tbcs_old2="$(slot_volid "$tbcs_vm2" scsi0)"
    tbcs_path1="$(pvesm path "$tbcs_old1")"; tbcs_path2="$(pvesm path "$tbcs_old2")"
    tbcs_hash1="$(hash_first_32m "$tbcs_path1")"; tbcs_hash2="$(hash_first_32m "$tbcs_path2")"

    run_dryrun_unchanged "bulk-change-storage" bulk-change-vm-storage.sh "$TEST_STORAGE_A" "$TEST_STORAGE_B" "$tbcs_vm1" "$tbcs_vm2"
    project_cmd bulk-change-vm-storage.sh "$TEST_STORAGE_A" "$TEST_STORAGE_B" "$tbcs_vm1" "$tbcs_vm2"

    tbcs_new1="$(slot_volid "$tbcs_vm1" scsi0)"; tbcs_new2="$(slot_volid "$tbcs_vm2" scsi0)"
    [ "${tbcs_new1%%:*}" = "$TEST_STORAGE_B" ] && [ "${tbcs_new2%%:*}" = "$TEST_STORAGE_B" ]
    [ "$(hash_first_32m "$(pvesm path "$tbcs_new1")")" = "$tbcs_hash1" ]
    [ "$(hash_first_32m "$(pvesm path "$tbcs_new2")")" = "$tbcs_hash2" ]
    ! lvs "$tbcs_path1" >/dev/null 2>&1
    ! lvs "$tbcs_path2" >/dev/null 2>&1
}

test_import_disk() {
    tid_vm="$(create_test_vm import-explicit)"
    tid_image="$TEST_DATA_DIR/import-source.raw"
    qemu-img create -f raw "$tid_image" 16M >/dev/null
    printf 'IMPORT-PATTERN-A\n' | dd of="$tid_image" bs=4096 conv=notrunc,fsync 2>/dev/null
    printf 'IMPORT-PATTERN-B\n' | dd of="$tid_image" bs=4096 seek=2048 conv=notrunc,fsync 2>/dev/null

    run_dryrun_unchanged "import-disk-explicit" import-disk-and-attach.sh "$tid_image" "$tid_vm" "$TEST_STORAGE_A" scsi2
    project_cmd import-disk-and-attach.sh "$tid_image" "$tid_vm" "$TEST_STORAGE_A" scsi2
    tid_volid="$(slot_volid "$tid_vm" scsi2)"; [ "${tid_volid%%:*}" = "$TEST_STORAGE_A" ]
    cmp -n 16777216 "$tid_image" "$(pvesm path "$tid_volid")"

    tid_default_vm="$(create_test_vm import-default)"
    run_dryrun_unchanged "import-disk-default-slot" import-disk-and-attach.sh "$tid_image" "$tid_default_vm" "$TEST_STORAGE_A"
    project_cmd import-disk-and-attach.sh "$tid_image" "$tid_default_vm" "$TEST_STORAGE_A"
    tid_default_volid="$(slot_volid "$tid_default_vm" scsi0)"; [ "${tid_default_volid%%:*}" = "$TEST_STORAGE_A" ]
    cmp -n 16777216 "$tid_image" "$(pvesm path "$tid_default_volid")"
}

test_export_disk() {
    ted_vm="$(create_vm_with_disk_a export)"
    ted_src_volid="$(slot_volid "$ted_vm" scsi0)"
    ted_src="$(pvesm path "$ted_src_volid")"

    ted_qcow="$TEST_DATA_DIR/exported.qcow2"
    run_dryrun_unchanged "export-disk-qcow2" export-vm-disk.sh "$ted_vm" scsi0 "$ted_qcow" qcow2
    [ ! -e "$ted_qcow" ] || { printf 'Dry-run unexpectedly created qcow2 output.\n' >&2; return 1; }
    project_cmd export-vm-disk.sh "$ted_vm" scsi0 "$ted_qcow" qcow2
    assert_file_exists "$ted_qcow"
    qemu-img info --output=json "$ted_qcow" | grep -Eq '"format"[[:space:]]*:[[:space:]]*"qcow2"' || { printf 'Exported qcow2 did not report qcow2 format.\n' >&2; return 1; }
    qemu-img compare -f raw -F qcow2 "$ted_src" "$ted_qcow" >/dev/null || { printf 'Exported qcow2 logical contents differ from source LV.\n' >&2; return 1; }

    ted_raw="$TEST_DATA_DIR/exported.raw"
    run_dryrun_unchanged "export-disk-default-raw" export-vm-disk.sh "$ted_vm" scsi0 "$ted_raw"
    [ ! -e "$ted_raw" ] || { printf 'Dry-run unexpectedly created raw output.\n' >&2; return 1; }
    project_cmd export-vm-disk.sh "$ted_vm" scsi0 "$ted_raw"
    qemu-img info --output=json "$ted_raw" | grep -Eq '"format"[[:space:]]*:[[:space:]]*"raw"' || { printf 'Exported raw image did not report raw format.\n' >&2; return 1; }
    cmp -n 33554432 "$ted_src" "$ted_raw" || { printf 'Exported raw bytes differ from source LV.\n' >&2; return 1; }
}

test_change_storage_prefix() {
    tcsp_vm="$(create_vm_with_disk_a storage-prefix)"
    tcsp_before="$(qm config "$tcsp_vm" | sed -n 's/^scsi0:[[:space:]]*//p')"
    tcsp_tail="${tcsp_before#*:}"
    add_storage_alias
    run_dryrun_unchanged "change-storage-prefix" change-vm-storage-prefix.sh "$TEST_STORAGE_A" "$TEST_STORAGE_ALIAS"
    project_cmd change-vm-storage-prefix.sh "$TEST_STORAGE_A" "$TEST_STORAGE_ALIAS"
    tcsp_after="$(qm config "$tcsp_vm" | sed -n 's/^scsi0:[[:space:]]*//p')"
    [ "$tcsp_after" = "$TEST_STORAGE_ALIAS:$tcsp_tail" ]
    while IFS='|' read -r tcsp_id tcsp_name; do
        [ -f "/etc/pve/qemu-server/${tcsp_id}.conf" ] || continue
        ! grep -F "$TEST_STORAGE_A:" "/etc/pve/qemu-server/${tcsp_id}.conf" >/dev/null
    done < "$TEST_VM_OWNED"
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
