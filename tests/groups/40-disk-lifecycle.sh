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
    PROJECT_VERSION="3.4.7"
    TEST_SUITE_VERSION="2.8.5"
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
    run_case "attach-existing-lvm-to-vm.sh explicit slot" test_attach_existing
    run_case "attach-existing-lvm-to-vm.sh shared-volume refusal" test_attach_shared_refusal
    run_case "detach-disk-from-vm.sh" test_detach_disk
    run_case "detach-disk-from-vm.sh running-VM refusal" test_detach_running_refusal
    run_case "delete-disk-from-vm.sh unusedN path" test_delete_disk
    run_case "attach default slot + delete active disk" test_attach_default_and_delete_active
    run_case "cleanup-unused-disks.sh explicit selection + --all" test_cleanup_unused
    run_case "shared-volume delete/cleanup refusal" test_shared_volume_refusal
    run_case "move-disk-to-vm.sh full-path hot mode" test_move_hot
    run_case "move-disk-to-vm.sh numeric pause mode" test_move_pause
    run_case "move-disk-to-vm.sh pause refuses unsafe sole-SCSI topology" test_move_pause_sole_scsi_refusal
    run_case "move-disk-to-vm.sh numeric stop mode" test_move_stop
    run_case "move-disk-to-vm.sh explicit-slot restart mode" test_move_restart
    run_case "move-disk-to-vm.sh base/template numeric selector real move" test_move_base_selector
    run_case "move-disk-to-vm.sh ambiguous disk-N refusal + explicit-slot resolution" test_move_selector_ambiguity
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
    printf '%s\n' "Each case creates its own disposable VM/LV fixture so one failed case cannot invalidate later coverage."
    printf '%s\n' "Exercises explicit/default attach, shared-attach refusal, stopped/running detach behavior, active/unused delete, explicit/all unused cleanup, and shared-reference refusal."
    printf '%s\n' "Independent move cases cover full-path, numeric and explicit-slot forms; hot/pause/stop/restart; base/template sources; and ambiguous disk-N refusal."
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
    tae_vm="$(create_test_vm attach-explicit)"
    tae_name="vm-${tae_vm}-disk-10"
    tae_lv="$(create_thin_lv "$TEST_VG_A" "$tae_name" 16M)"
    run_dryrun_unchanged "attach-existing" attach-existing-lvm-to-vm.sh "$tae_lv" "$tae_vm" scsi2
    project_cmd attach-existing-lvm-to-vm.sh "$tae_lv" "$tae_vm" scsi2
    qm config "$tae_vm" | grep -F "scsi2: $TEST_STORAGE_A:$tae_name" >/dev/null
}

test_attach_shared_refusal() {
    tasr_a="$(create_test_vm attach-shared-a)"
    tasr_b="$(create_test_vm attach-shared-b)"
    tasr_name="vm-${tasr_a}-disk-0"
    tasr_lv="$(create_thin_lv "$TEST_VG_A" "$tasr_name" 16M)"
    attach_test_lv "$tasr_a" "$TEST_STORAGE_A" "$tasr_name" scsi0
    run_expect_fail_unchanged "attach-shared-refusal" attach-existing-lvm-to-vm.sh "$tasr_lv" "$tasr_b" scsi0
    ! qm config "$tasr_b" | grep -F "$TEST_STORAGE_A:$tasr_name" >/dev/null
}

test_detach_disk() {
    tdd_vm="$(create_test_vm detach)"
    tdd_name="vm-${tdd_vm}-disk-0"
    tdd_lv="$(create_thin_lv "$TEST_VG_A" "$tdd_name" 16M)"
    attach_test_lv "$tdd_vm" "$TEST_STORAGE_A" "$tdd_name" scsi0
    run_dryrun_unchanged "detach-disk" detach-disk-from-vm.sh "$tdd_vm" scsi0
    project_cmd detach-disk-from-vm.sh "$tdd_vm" scsi0
    ! qm config "$tdd_vm" | grep -q '^scsi0:'
    tdd_unused="$(qm config "$tdd_vm" | awk -F': ' -v v="$TEST_STORAGE_A:$tdd_name" '$1 ~ /^unused[0-9]+$/ && index($2,v)==1 {print $1; exit}')"
    [ -n "$tdd_unused" ]
    assert_lv_exists "$TEST_VG_A/$tdd_name"
}

test_detach_running_refusal() {
    tdrr_vm="$(create_test_vm detach-running)"
    tdrr_name="vm-${tdrr_vm}-disk-0"
    tdrr_lv="$(create_thin_lv "$TEST_VG_A" "$tdrr_name" 16M)"
    attach_test_lv "$tdrr_vm" "$TEST_STORAGE_A" "$tdrr_name" scsi0
    qm start "$tdrr_vm" >/dev/null
    [ "$(qm status "$tdrr_vm" | awk '{print $2}')" = "running" ]
    run_expect_fail_unchanged "detach-running-refusal" detach-disk-from-vm.sh "$tdrr_vm" scsi0
    [ "$(qm status "$tdrr_vm" | awk '{print $2}')" = "running" ]
    qm stop "$tdrr_vm" >/dev/null
}

test_delete_disk() {
    tdel_vm="$(create_test_vm delete-unused)"
    tdel_name="vm-${tdel_vm}-disk-0"
    tdel_lv="$(create_thin_lv "$TEST_VG_A" "$tdel_name" 16M)"
    attach_test_lv "$tdel_vm" "$TEST_STORAGE_A" "$tdel_name" scsi0
    qm set "$tdel_vm" --delete scsi0 >/dev/null
    tdel_unused="$(qm config "$tdel_vm" | awk -F': ' -v v="$TEST_STORAGE_A:$tdel_name" '$1 ~ /^unused[0-9]+$/ && index($2,v)==1 {print $1; exit}')"
    [ -n "$tdel_unused" ] || return 1
    run_dryrun_unchanged "delete-disk" delete-disk-from-vm.sh "$tdel_vm" "$tdel_unused"
    project_cmd delete-disk-from-vm.sh "$tdel_vm" "$tdel_unused"
    assert_lv_absent "$TEST_VG_A/$tdel_name"
}

test_attach_default_and_delete_active() {
    tada_vm="$(create_test_vm attach-default-delete-active)"
    tada_name="vm-${tada_vm}-disk-12"
    tada_lv="$(create_thin_lv "$TEST_VG_A" "$tada_name" 16M)"
    run_dryrun_unchanged "attach-existing-default-slot" attach-existing-lvm-to-vm.sh "$tada_lv" "$tada_vm"
    project_cmd attach-existing-lvm-to-vm.sh "$tada_lv" "$tada_vm"
    qm config "$tada_vm" | grep -F "scsi0: $TEST_STORAGE_A:$tada_name" >/dev/null

    run_dryrun_unchanged "delete-active-disk" delete-disk-from-vm.sh "$tada_vm" scsi0
    project_cmd delete-disk-from-vm.sh "$tada_vm" scsi0
    assert_lv_absent "$TEST_VG_A/$tada_name"
    ! qm config "$tada_vm" | grep -F "$TEST_STORAGE_A:$tada_name" >/dev/null
}

test_cleanup_unused() {
    tcu_vm="$(create_test_vm cleanup-unused)"
    tcu_name1="vm-${tcu_vm}-disk-11"
    tcu_name2="vm-${tcu_vm}-disk-13"
    tcu_lv1="$(create_thin_lv "$TEST_VG_A" "$tcu_name1" 16M)"
    tcu_lv2="$(create_thin_lv "$TEST_VG_A" "$tcu_name2" 16M)"

    attach_test_lv "$tcu_vm" "$TEST_STORAGE_A" "$tcu_name1" scsi0
    qm set "$tcu_vm" --delete scsi0 >/dev/null
    attach_test_lv "$tcu_vm" "$TEST_STORAGE_A" "$tcu_name2" scsi0
    qm set "$tcu_vm" --delete scsi0 >/dev/null

    tcu_key1="$(qm config "$tcu_vm" | awk -F': ' -v v="$TEST_STORAGE_A:$tcu_name1" '$1 ~ /^unused[0-9]+$/ && index($2,v)==1 {print $1; exit}')"
    tcu_key2="$(qm config "$tcu_vm" | awk -F': ' -v v="$TEST_STORAGE_A:$tcu_name2" '$1 ~ /^unused[0-9]+$/ && index($2,v)==1 {print $1; exit}')"
    [ -n "$tcu_key1" ] && [ -n "$tcu_key2" ]

    run_dryrun_unchanged "cleanup-unused-explicit" cleanup-unused-disks.sh "$tcu_vm" "$tcu_key1"
    project_cmd cleanup-unused-disks.sh "$tcu_vm" "$tcu_key1"
    assert_lv_absent "$TEST_VG_A/$tcu_name1"
    assert_lv_exists "$TEST_VG_A/$tcu_name2"

    run_dryrun_unchanged "cleanup-unused-all" cleanup-unused-disks.sh "$tcu_vm" --all
    project_cmd cleanup-unused-disks.sh "$tcu_vm" --all
    assert_lv_absent "$TEST_VG_A/$tcu_name2"
    ! qm config "$tcu_vm" | grep -E '^unused[0-9]+:' >/dev/null
}

test_shared_volume_refusal() {
    tsvr_a="$(create_test_vm shared-a)"
    tsvr_b="$(create_test_vm shared-b)"
    tsvr_name="vm-${tsvr_a}-disk-0"
    tsvr_lv="$(create_thin_lv "$TEST_VG_A" "$tsvr_name" 16M)"
    attach_test_lv "$tsvr_a" "$TEST_STORAGE_A" "$tsvr_name" scsi0
    project_cmd detach-disk-from-vm.sh "$tsvr_a" scsi0
    tsvr_key="$(qm config "$tsvr_a" | awk -F': ' -v v="$TEST_STORAGE_A:$tsvr_name" '$1 ~ /^unused[0-9]+$/ && index($2,v)==1 {print $1; exit}')"
    [ -n "$tsvr_key" ]

    # Deliberately add a second test-owned reference without invoking a delete
    # side effect during cleanup of this negative fixture.
    printf 'scsi0: %s:%s
' "$TEST_STORAGE_A" "$tsvr_name" >> "/etc/pve/qemu-server/${tsvr_b}.conf"
    run_expect_fail_unchanged "delete-shared-unused" delete-disk-from-vm.sh "$tsvr_a" "$tsvr_key"
    run_expect_fail_unchanged "cleanup-shared-unused" cleanup-unused-disks.sh "$tsvr_a" --all
    assert_lv_exists "$TEST_VG_A/$tsvr_name"

    # Remove only the synthetic second config reference, then clean the first.
    sed -i '/^scsi0: /d' "/etc/pve/qemu-server/${tsvr_b}.conf"
    project_cmd cleanup-unused-disks.sh "$tsvr_a" --all
    assert_lv_absent "$TEST_VG_A/$tsvr_name"
}

# test_move_disk_to_vm
# Exercises both CLI forms and every source-state mode on test-owned VMs.
prepare_one_move() {
    pom_role="$1"; pom_disk="$2"
    MOVE_CASE_SRC="$(create_test_vm "${pom_role}-src")"
    MOVE_CASE_DST="$(create_test_vm "${pom_role}-dst")"
    MOVE_CASE_NAME="vm-${MOVE_CASE_SRC}-disk-${pom_disk}"
    MOVE_CASE_LV="$(create_thin_lv "$TEST_VG_A" "$MOVE_CASE_NAME" 16M)"
    attach_test_lv "$MOVE_CASE_SRC" "$TEST_STORAGE_A" "$MOVE_CASE_NAME" scsi0
}

test_move_hot() {
    prepare_one_move move-hot 0
    qm start "$MOVE_CASE_SRC" >/dev/null
    run_dryrun_unchanged "move-disk-to-vm-hot-path" move-disk-to-vm.sh "$MOVE_CASE_LV" "$MOVE_CASE_DST"
    project_cmd move-disk-to-vm.sh "$MOVE_CASE_LV" "$MOVE_CASE_DST"
    [ "$(qm status "$MOVE_CASE_SRC" | awk '{print $2}')" = "running" ]
    qm config "$MOVE_CASE_DST" | grep -F "$TEST_STORAGE_A:$MOVE_CASE_NAME" >/dev/null
    ! qm config "$MOVE_CASE_SRC" | grep -F "$TEST_STORAGE_A:$MOVE_CASE_NAME" >/dev/null
    assert_lv_exists "$MOVE_CASE_LV"
}

test_move_pause() {
    prepare_one_move move-pause 1
    qm set "$MOVE_CASE_SRC" --scsihw virtio-scsi-pci >/dev/null
    tmp_keeper_name="vm-${MOVE_CASE_SRC}-disk-99"
    tmp_keeper_lv="$(create_thin_lv "$TEST_VG_A" "$tmp_keeper_name" 16M)"
    attach_test_lv "$MOVE_CASE_SRC" "$TEST_STORAGE_A" "$tmp_keeper_name" scsi1
    qm start "$MOVE_CASE_SRC" >/dev/null
    run_dryrun_unchanged "move-disk-to-vm-pause" move-disk-to-vm.sh pause "$MOVE_CASE_SRC" 1 "$MOVE_CASE_DST"
    project_cmd move-disk-to-vm.sh "$MOVE_CASE_SRC" 1 "$MOVE_CASE_DST" pause
    [ "$(qm status "$MOVE_CASE_SRC" | awk '{print $2}')" = "running" ]
    qm config "$MOVE_CASE_DST" | grep -F "$TEST_STORAGE_A:$MOVE_CASE_NAME" >/dev/null
    qm config "$MOVE_CASE_SRC" | grep -F "scsi1: $TEST_STORAGE_A:$tmp_keeper_name" >/dev/null
    assert_lv_exists "$tmp_keeper_lv"
}

test_move_pause_sole_scsi_refusal() {
    tmps_src="$(create_test_vm move-pause-sole-src)"
    tmps_dst="$(create_test_vm move-pause-sole-dst)"
    tmps_name="vm-${tmps_src}-disk-0"
    tmps_lv="$(create_thin_lv "$TEST_VG_A" "$tmps_name" 16M)"
    attach_test_lv "$tmps_src" "$TEST_STORAGE_A" "$tmps_name" scsi0
    qm start "$tmps_src" >/dev/null
    [ "$(qm status "$tmps_src" | awk '{print $2}')" = "running" ]
    run_expect_fail_unchanged "move-pause-sole-scsi" move-disk-to-vm.sh pause "$tmps_src" 0 "$tmps_dst"
    qm config "$tmps_src" | grep -F "scsi0: $TEST_STORAGE_A:$tmps_name" >/dev/null
    assert_lv_exists "$tmps_lv"
    qm stop "$tmps_src" >/dev/null
}

test_move_stop() {
    prepare_one_move move-stop 2
    qm start "$MOVE_CASE_SRC" >/dev/null
    run_dryrun_unchanged "move-disk-to-vm-stop" move-disk-to-vm.sh "$MOVE_CASE_SRC" 2 "$MOVE_CASE_DST" stop
    project_cmd move-disk-to-vm.sh stop "$MOVE_CASE_SRC" 2 "$MOVE_CASE_DST"
    [ "$(qm status "$MOVE_CASE_SRC" | awk '{print $2}')" = "stopped" ]
    qm config "$MOVE_CASE_DST" | grep -F "$TEST_STORAGE_A:$MOVE_CASE_NAME" >/dev/null
}

test_move_restart() {
    prepare_one_move move-restart 3
    qm start "$MOVE_CASE_SRC" >/dev/null
    run_dryrun_unchanged "move-disk-to-vm-restart" move-disk-to-vm.sh "$MOVE_CASE_SRC" scsi0 "$MOVE_CASE_DST" restart
    project_cmd move-disk-to-vm.sh restart "$MOVE_CASE_SRC" scsi0 "$MOVE_CASE_DST"
    [ "$(qm status "$MOVE_CASE_SRC" | awk '{print $2}')" = "running" ]
    qm config "$MOVE_CASE_DST" | grep -F "$TEST_STORAGE_A:$MOVE_CASE_NAME" >/dev/null
}

test_move_base_selector() {
    tmbs_src="$(create_test_vm move-base-src)"
    tmbs_dst="$(create_test_vm move-base-dst)"
    tmbs_seed="vm-${tmbs_src}-disk-0"
    create_thin_lv "$TEST_VG_A" "$tmbs_seed" 16M >/dev/null
    attach_test_lv "$tmbs_src" "$TEST_STORAGE_A" "$tmbs_seed" scsi0
    qm template "$tmbs_src" >/dev/null
    assert_lv_exists "$TEST_VG_A/base-${tmbs_src}-disk-0"

    run_dryrun_unchanged "move-base-selector" move-disk-to-vm.sh "$tmbs_src" 0 "$tmbs_dst"
    project_cmd move-disk-to-vm.sh "$tmbs_src" 0 "$tmbs_dst"
    qm config "$tmbs_dst" | grep -F "$TEST_STORAGE_A:base-${tmbs_src}-disk-0" >/dev/null
    ! qm config "$tmbs_src" | grep -F "$TEST_STORAGE_A:base-${tmbs_src}-disk-0" >/dev/null
    assert_lv_exists "$TEST_VG_A/base-${tmbs_src}-disk-0"
}

test_move_selector_ambiguity() {
    tmsa_src="$(create_test_vm move-ambiguous-src)"
    tmsa_dst="$(create_test_vm move-ambiguous-dst)"
    tmsa_foreign="$(allocate_free_vmid)"
    tmsa_vm_name="vm-${tmsa_src}-disk-0"
    tmsa_base_name="base-${tmsa_foreign}-disk-0"
    create_thin_lv "$TEST_VG_A" "$tmsa_vm_name" 16M >/dev/null
    create_thin_lv "$TEST_VG_A" "$tmsa_base_name" 16M >/dev/null
    attach_test_lv "$tmsa_src" "$TEST_STORAGE_A" "$tmsa_vm_name" scsi0
    attach_test_lv "$tmsa_src" "$TEST_STORAGE_A" "$tmsa_base_name" scsi1

    run_expect_fail_unchanged "move-ambiguous-disk-number" move-disk-to-vm.sh "$tmsa_src" 0 "$tmsa_dst"

    run_dryrun_unchanged "move-explicit-slot-after-ambiguity" move-disk-to-vm.sh "$tmsa_src" scsi0 "$tmsa_dst"
    project_cmd move-disk-to-vm.sh "$tmsa_src" scsi0 "$tmsa_dst"
    qm config "$tmsa_dst" | grep -F "$TEST_STORAGE_A:$tmsa_vm_name" >/dev/null
    qm config "$tmsa_src" | grep -F "$TEST_STORAGE_A:$tmsa_base_name" >/dev/null
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
