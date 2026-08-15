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
    TEST_GROUP="disk-config"
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
    prepare_primary_config_fixture
    run_case "change-disk-bus.sh" test_change_disk_bus
    run_case "swap-vm-disks.sh" test_swap_vm_disks
    run_case "set-vm-boot-disk.sh" test_set_vm_boot_disk
    run_case "replace-vm-disk.sh" test_replace_vm_disk
    run_case "renumber-vm-disks.sh" test_renumber_vm_disks
    run_case "fix-vm-volume-names.sh" test_fix_vm_volume_names
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
    print_banner "VM disk configuration tests"
    printf '%s\n' "Uses only stopped disposable VMs and loopback-backed test disks."
    printf '%s\n' "Exercises bus changes, slot swapping, boot order, replacement, renumbering and volume-name repair."
    printf '%s\n' "Config backups created by the tools are identified by test VMID and removed during cleanup."
}

############################################################
# FIXTURES
############################################################

prepare_primary_config_fixture() {
    CONFIG_VM="$(create_test_vm disk-config)"
    CONFIG_LV0_NAME="vm-${CONFIG_VM}-disk-0"
    CONFIG_LV1_NAME="vm-${CONFIG_VM}-disk-1"
    CONFIG_LV0="$(create_thin_lv "$TEST_VG_A" "$CONFIG_LV0_NAME" 16M)"
    CONFIG_LV1="$(create_thin_lv "$TEST_VG_A" "$CONFIG_LV1_NAME" 16M)"
    attach_test_lv "$CONFIG_VM" "$TEST_STORAGE_A" "$CONFIG_LV0_NAME" scsi0
    attach_test_lv "$CONFIG_VM" "$TEST_STORAGE_A" "$CONFIG_LV1_NAME" scsi1
}

############################################################
# TEST CASES
############################################################

test_change_disk_bus() {
    run_dryrun_unchanged "change-disk-bus" change-disk-bus.sh "$CONFIG_VM" scsi1 sata0
    project_cmd change-disk-bus.sh "$CONFIG_VM" scsi1 sata0
    qm config "$CONFIG_VM" | grep -q '^sata0:'
    ! qm config "$CONFIG_VM" | grep -q '^scsi1:'
}

test_swap_vm_disks() {
    tsvd_scsi_before="$(qm config "$CONFIG_VM" | sed -n 's/^scsi0:[[:space:]]*//p')"
    tsvd_sata_before="$(qm config "$CONFIG_VM" | sed -n 's/^sata0:[[:space:]]*//p')"
    [ -n "$tsvd_scsi_before" ] && [ -n "$tsvd_sata_before" ] || return 1
    run_dryrun_unchanged "swap-vm-disks" swap-vm-disks.sh "$CONFIG_VM" scsi0 sata0
    project_cmd swap-vm-disks.sh "$CONFIG_VM" scsi0 sata0
    [ "$(qm config "$CONFIG_VM" | sed -n 's/^scsi0:[[:space:]]*//p')" = "$tsvd_sata_before" ]
    [ "$(qm config "$CONFIG_VM" | sed -n 's/^sata0:[[:space:]]*//p')" = "$tsvd_scsi_before" ]
}

test_set_vm_boot_disk() {
    run_dryrun_unchanged "set-vm-boot-disk" set-vm-boot-disk.sh "$CONFIG_VM" scsi0
    project_cmd set-vm-boot-disk.sh "$CONFIG_VM" scsi0
    qm config "$CONFIG_VM" | grep -E '^boot:.*order=scsi0([;,]|$)' >/dev/null
}

test_replace_vm_disk() {
    trvd_name="vm-${CONFIG_VM}-disk-9"
    trvd_lv="$(create_thin_lv "$TEST_VG_A" "$trvd_name" 16M)"
    run_dryrun_unchanged "replace-vm-disk" replace-vm-disk.sh "$CONFIG_VM" scsi0 "$trvd_lv"
    project_cmd replace-vm-disk.sh "$CONFIG_VM" scsi0 "$trvd_lv"
    qm config "$CONFIG_VM" | grep -F "scsi0: $TEST_STORAGE_A:$trvd_name" >/dev/null
}

test_renumber_vm_disks() {
    trn_vm="$(create_test_vm renumber)"
    trn_name3="vm-${trn_vm}-disk-3"
    trn_name7="vm-${trn_vm}-disk-7"
    create_thin_lv "$TEST_VG_A" "$trn_name3" 16M >/dev/null
    create_thin_lv "$TEST_VG_A" "$trn_name7" 16M >/dev/null
    attach_test_lv "$trn_vm" "$TEST_STORAGE_A" "$trn_name3" scsi0
    attach_test_lv "$trn_vm" "$TEST_STORAGE_A" "$trn_name7" scsi1
    run_dryrun_unchanged "renumber-vm-disks" renumber-vm-disks.sh "$trn_vm"
    project_cmd renumber-vm-disks.sh "$trn_vm"
    assert_lv_exists "$TEST_VG_A/vm-${trn_vm}-disk-0"
    assert_lv_exists "$TEST_VG_A/vm-${trn_vm}-disk-1"
    assert_lv_absent "$TEST_VG_A/$trn_name3"
    assert_lv_absent "$TEST_VG_A/$trn_name7"
}

test_fix_vm_volume_names() {
    tfvn_vm="$(create_test_vm fix-names)"
    tfvn_foreign="$(allocate_free_vmid)"
    tfvn_old="vm-${tfvn_foreign}-disk-0"
    create_thin_lv "$TEST_VG_A" "$tfvn_old" 16M >/dev/null
    attach_test_lv "$tfvn_vm" "$TEST_STORAGE_A" "$tfvn_old" scsi0
    run_dryrun_unchanged "fix-vm-volume-names" fix-vm-volume-names.sh "$tfvn_vm"
    project_cmd fix-vm-volume-names.sh "$tfvn_vm"
    assert_lv_absent "$TEST_VG_A/$tfvn_old"
    qm config "$tfvn_vm" | grep -F "$TEST_STORAGE_A:vm-${tfvn_vm}-disk-" >/dev/null
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
