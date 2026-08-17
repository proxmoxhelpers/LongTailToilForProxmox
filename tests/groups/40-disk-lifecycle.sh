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
    prepare_move_fixture
    run_case "attach-existing-lvm-to-vm.sh" test_attach_existing
    run_case "detach-disk-from-vm.sh" test_detach_disk
    run_case "delete-disk-from-vm.sh" test_delete_disk
    run_case "cleanup-unused-disks.sh" test_cleanup_unused
    run_case "move-disk-to-vm.sh forms + hot/pause/stop/restart" test_move_disk_to_vm
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
    printf '%s\n' "Exercises attach, detach, delete, unused cleanup, and cross-VM LVM reference moves."
    printf '%s\n' "The move test covers full-path + VM/disk forms and hot, pause, stop, restart source-state modes."
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

# prepare_move_fixture
# Creates two disposable VMs and four LVM disks owned by the source VM.
prepare_move_fixture() {
    MOVE_SRC_VM="$(create_test_vm move-src)"
    MOVE_DST_VM="$(create_test_vm move-dst)"
    MOVE_LV0_NAME="vm-${MOVE_SRC_VM}-disk-0"; MOVE_LV0="$(create_thin_lv "$TEST_VG_A" "$MOVE_LV0_NAME" 16M)"
    MOVE_LV1_NAME="vm-${MOVE_SRC_VM}-disk-1"; MOVE_LV1="$(create_thin_lv "$TEST_VG_A" "$MOVE_LV1_NAME" 16M)"
    MOVE_LV2_NAME="vm-${MOVE_SRC_VM}-disk-2"; MOVE_LV2="$(create_thin_lv "$TEST_VG_A" "$MOVE_LV2_NAME" 16M)"
    MOVE_LV3_NAME="vm-${MOVE_SRC_VM}-disk-3"; MOVE_LV3="$(create_thin_lv "$TEST_VG_A" "$MOVE_LV3_NAME" 16M)"
    attach_test_lv "$MOVE_SRC_VM" "$TEST_STORAGE_A" "$MOVE_LV0_NAME" scsi0
    attach_test_lv "$MOVE_SRC_VM" "$TEST_STORAGE_A" "$MOVE_LV1_NAME" scsi1
    attach_test_lv "$MOVE_SRC_VM" "$TEST_STORAGE_A" "$MOVE_LV2_NAME" scsi2
    attach_test_lv "$MOVE_SRC_VM" "$TEST_STORAGE_A" "$MOVE_LV3_NAME" scsi3
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

# test_move_disk_to_vm
# Exercises both CLI forms and every source-state mode on test-owned VMs.
test_move_disk_to_vm() {
    qm start "$MOVE_SRC_VM" >/dev/null
    [ "$(qm status "$MOVE_SRC_VM" | awk '{print $2}')" = "running" ]

    # Full-LV-path form, default hot-swap: source must remain running.
    run_dryrun_unchanged "move-disk-to-vm-hot-path" move-disk-to-vm.sh "$MOVE_LV0" "$MOVE_DST_VM"
    project_cmd move-disk-to-vm.sh "$MOVE_LV0" "$MOVE_DST_VM"
    [ "$(qm status "$MOVE_SRC_VM" | awk '{print $2}')" = "running" ]
    qm config "$MOVE_DST_VM" | grep -F "$TEST_STORAGE_A:$MOVE_LV0_NAME" >/dev/null
    ! qm config "$MOVE_SRC_VM" | grep -F "$TEST_STORAGE_A:$MOVE_LV0_NAME" >/dev/null

    # VMID + backing disk number, pause mode: source is resumed afterward.
    run_dryrun_unchanged "move-disk-to-vm-pause" move-disk-to-vm.sh pause "$MOVE_SRC_VM" 1 "$MOVE_DST_VM"
    project_cmd move-disk-to-vm.sh "$MOVE_SRC_VM" 1 "$MOVE_DST_VM" pause
    [ "$(qm status "$MOVE_SRC_VM" | awk '{print $2}')" = "running" ]
    qm config "$MOVE_DST_VM" | grep -F "$TEST_STORAGE_A:$MOVE_LV1_NAME" >/dev/null

    # stop mode: source is stopped before detach and remains stopped.
    run_dryrun_unchanged "move-disk-to-vm-stop" move-disk-to-vm.sh "$MOVE_SRC_VM" 2 "$MOVE_DST_VM" stop
    project_cmd move-disk-to-vm.sh stop "$MOVE_SRC_VM" 2 "$MOVE_DST_VM"
    [ "$(qm status "$MOVE_SRC_VM" | awk '{print $2}')" = "stopped" ]
    qm config "$MOVE_DST_VM" | grep -F "$TEST_STORAGE_A:$MOVE_LV2_NAME" >/dev/null

    # restart mode: only a VM that was running is started again afterward.
    qm start "$MOVE_SRC_VM" >/dev/null
    [ "$(qm status "$MOVE_SRC_VM" | awk '{print $2}')" = "running" ]
    run_dryrun_unchanged "move-disk-to-vm-restart" move-disk-to-vm.sh "$MOVE_SRC_VM" 3 "$MOVE_DST_VM" restart
    project_cmd move-disk-to-vm.sh "$MOVE_SRC_VM" 3 restart "$MOVE_DST_VM"
    [ "$(qm status "$MOVE_SRC_VM" | awk '{print $2}')" = "running" ]
    qm config "$MOVE_DST_VM" | grep -F "$TEST_STORAGE_A:$MOVE_LV3_NAME" >/dev/null

    assert_lv_exists "$MOVE_LV0"
    assert_lv_exists "$MOVE_LV1"
    assert_lv_exists "$MOVE_LV2"
    assert_lv_exists "$MOVE_LV3"
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
