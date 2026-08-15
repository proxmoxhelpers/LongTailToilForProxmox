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
    PROJECT_VERSION="3.0.1"
    TEST_SUITE_VERSION="2.0.1"
    TEST_GROUP="disk-lifecycle"
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
    prepare_lifecycle_fixture
    run_case "attach-existing-lvm-to-vm.sh" test_attach_existing
    run_case "detach-disk-from-vm.sh" test_detach_disk
    run_case "delete-disk-from-vm.sh" test_delete_disk
    run_case "cleanup-unused-disks.sh" test_cleanup_unused
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
    print_banner "VM disk lifecycle tests"
    printf '%s\n' "Creates one stopped disposable VM and test-only LVs."
    printf '%s\n' "Exercises attach, detach-to-unused, explicit disk deletion, and unused-disk cleanup."
    printf '%s\n' "Each mutating command is dry-run checked before its real test-owned mutation."
}

############################################################
# FIXTURE
############################################################

prepare_lifecycle_fixture() {
    LIFECYCLE_VM="$(create_test_vm lifecycle)"
    ATTACH_LV_NAME="vm-${LIFECYCLE_VM}-disk-10"
    ATTACH_LV="$(create_thin_lv "$TEST_VG_A" "$ATTACH_LV_NAME" 16M)"
}

############################################################
# TEST CASES
############################################################

test_attach_existing() {
    run_dryrun_unchanged "attach-existing" attach-existing-lvm-to-vm.sh "$ATTACH_LV" "$LIFECYCLE_VM" scsi0
    project_cmd attach-existing-lvm-to-vm.sh "$ATTACH_LV" "$LIFECYCLE_VM" scsi0
    qm config "$LIFECYCLE_VM" | grep -F "scsi0: $TEST_STORAGE_A:$ATTACH_LV_NAME" >/dev/null
}

test_detach_disk() {
    qm config "$LIFECYCLE_VM" | grep -q '^scsi0:' || { printf 'scsi0 is not attached from the previous case.\n' >&2; return 1; }
    run_dryrun_unchanged "detach-disk" detach-disk-from-vm.sh "$LIFECYCLE_VM" scsi0
    project_cmd detach-disk-from-vm.sh "$LIFECYCLE_VM" scsi0
    ! qm config "$LIFECYCLE_VM" | grep -q '^scsi0:'
    tdd_unused="$(qm config "$LIFECYCLE_VM" | awk -F': ' -v v="$TEST_STORAGE_A:$ATTACH_LV_NAME" '$1 ~ /^unused[0-9]+$/ && index($2,v)==1 {print $1; exit}')"
    [ -n "$tdd_unused" ]
}

test_delete_disk() {
    tdd_unused="$(qm config "$LIFECYCLE_VM" | awk -F': ' -v v="$TEST_STORAGE_A:$ATTACH_LV_NAME" '$1 ~ /^unused[0-9]+$/ && index($2,v)==1 {print $1; exit}')"
    [ -n "$tdd_unused" ] || { printf 'No detached unused slot is available.\n' >&2; return 1; }
    run_dryrun_unchanged "delete-disk" delete-disk-from-vm.sh "$LIFECYCLE_VM" "$tdd_unused"
    project_cmd delete-disk-from-vm.sh "$LIFECYCLE_VM" "$tdd_unused"
    assert_lv_absent "$TEST_VG_A/$ATTACH_LV_NAME"
}

test_cleanup_unused() {
    tcu_name="vm-${LIFECYCLE_VM}-disk-11"
    tcu_lv="$(create_thin_lv "$TEST_VG_A" "$tcu_name" 16M)"
    project_cmd attach-existing-lvm-to-vm.sh "$tcu_lv" "$LIFECYCLE_VM" scsi0
    project_cmd detach-disk-from-vm.sh "$LIFECYCLE_VM" scsi0
    qm config "$LIFECYCLE_VM" | grep -F "$TEST_STORAGE_A:$tcu_name" >/dev/null
    run_dryrun_unchanged "cleanup-unused" cleanup-unused-disks.sh "$LIFECYCLE_VM" --all
    project_cmd cleanup-unused-disks.sh "$LIFECYCLE_VM" --all
    assert_lv_absent "$TEST_VG_A/$tcu_name"
    ! qm config "$LIFECYCLE_VM" | grep -F "$TEST_STORAGE_A:$tcu_name" >/dev/null
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
