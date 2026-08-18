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
    PROJECT_VERSION="3.2.2"
    TEST_SUITE_VERSION="2.2.2"
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
    run_case "move-disk-to-storage.sh" test_move_disk_storage
    run_case "bulk-change-vm-storage.sh" test_bulk_change_storage
    run_case "import-disk-and-attach.sh" test_import_disk
    run_case "export-vm-disk.sh" test_export_disk
    run_case "change-vm-storage-prefix.sh" test_change_storage_prefix
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
    printf '%s\n' "Tests individual and bulk storage moves, image import/export, then a temporary alias-storage prefix rewrite."
    printf '%s\n' "The alias maps only to the test VG; no production storage ID is changed."
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
    attach_test_lv "$cvwda_vm" "$TEST_STORAGE_A" "$cvwda_name" scsi0
    printf '%s\n' "$cvwda_vm"
}

############################################################
# TEST CASES
############################################################

test_move_disk_storage() {
    tmds_vm="$(create_vm_with_disk_a move-storage)"
    run_dryrun_unchanged "move-disk-storage" move-disk-to-storage.sh "$tmds_vm" scsi0 "$TEST_STORAGE_B"
    project_cmd move-disk-to-storage.sh "$tmds_vm" scsi0 "$TEST_STORAGE_B"
    qm config "$tmds_vm" | grep -F "scsi0: $TEST_STORAGE_B:" >/dev/null
}

test_bulk_change_storage() {
    tbcs_vm="$(create_vm_with_disk_a bulk-storage)"
    run_dryrun_unchanged "bulk-change-storage" bulk-change-vm-storage.sh "$TEST_STORAGE_A" "$TEST_STORAGE_B" "$tbcs_vm"
    project_cmd bulk-change-vm-storage.sh "$TEST_STORAGE_A" "$TEST_STORAGE_B" "$tbcs_vm"
    qm config "$tbcs_vm" | grep -F "scsi0: $TEST_STORAGE_B:" >/dev/null
}

test_import_disk() {
    tid_vm="$(create_test_vm import)"
    tid_image="$TEST_DATA_DIR/import-source.raw"
    qemu-img create -f raw "$tid_image" 16M >/dev/null
    run_dryrun_unchanged "import-disk" import-disk-and-attach.sh "$tid_image" "$tid_vm" "$TEST_STORAGE_A" scsi0
    project_cmd import-disk-and-attach.sh "$tid_image" "$tid_vm" "$TEST_STORAGE_A" scsi0
    qm config "$tid_vm" | grep -F "scsi0: $TEST_STORAGE_A:" >/dev/null
}

test_export_disk() {
    ted_vm="$(create_vm_with_disk_a export)"
    ted_out="$TEST_DATA_DIR/exported.qcow2"
    rm -f "$ted_out"
    run_dryrun_unchanged "export-disk" export-vm-disk.sh "$ted_vm" scsi0 "$ted_out" qcow2
    [ ! -e "$ted_out" ] || { printf 'Dry-run unexpectedly created export output.\n' >&2; return 1; }
    project_cmd export-vm-disk.sh "$ted_vm" scsi0 "$ted_out" qcow2
    assert_file_exists "$ted_out"
    qemu-img info "$ted_out" >/dev/null
}

test_change_storage_prefix() {
    tcsp_vm="$(create_vm_with_disk_a storage-prefix)"
    add_storage_alias
    run_dryrun_unchanged "change-storage-prefix" change-vm-storage-prefix.sh "$TEST_STORAGE_A" "$TEST_STORAGE_ALIAS"
    project_cmd change-vm-storage-prefix.sh "$TEST_STORAGE_A" "$TEST_STORAGE_ALIAS"
    qm config "$tcsp_vm" | grep -F "$TEST_STORAGE_ALIAS:" >/dev/null
    ! qm config "$tcsp_vm" | grep -F "$TEST_STORAGE_A:" >/dev/null
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
