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
    PROJECT_VERSION="3.1.0"
    TEST_SUITE_VERSION="2.1.0"
    TEST_GROUP="inspection"
    test_reset_counters
    test_parse_arguments "$@"
    [ "$TEST_RUN" = "false" ] || check_elevation
}

main() {
    [ "$TEST_RUN" = "true" ] || { print_plan; return 0; }
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    require_proxmox_environment
    test_prepare_run
    create_storage_sandbox
    prepare_inspection_fixture
    run_case "list-vm-disks.sh" test_list_vm_disks
    run_case "list-all-vm-lvm.sh" test_list_all_vm_lvm
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
    printf '%s\n' "Disposable fixture: two loopback VGs, one stopped VM, one attached LV and one orphan LV."
    printf '%s\n' "Commands: list-vm-disks, list-all-vm-lvm, find-volume-owner, find-orphaned-volumes, audit-vm-storage."
    printf '%s\n' "All four commands are read-only; no production guest or production LV is referenced."
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
    INSPECT_ORPHAN_ID="$(allocate_free_vmid)"
    INSPECT_ORPHAN_NAME="vm-${INSPECT_ORPHAN_ID}-disk-0"
    INSPECT_ORPHAN_LV="$(create_thin_lv "$TEST_VG_A" "$INSPECT_ORPHAN_NAME" 16M)"
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
    assert_contains "$tal_out" "Remaining LVM volumes"
    assert_contains "$tal_out" "$INSPECT_ORPHAN_LV"
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
