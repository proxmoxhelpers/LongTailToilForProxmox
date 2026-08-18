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
    run_case "change-disk-bus.sh exact slot + option preservation" test_change_disk_bus
    run_case "change-disk-bus.sh first-free bare bus" test_change_disk_bus_first_free
    run_case "change-disk-bus.sh omitted destination defaults to first-free SCSI" test_change_disk_bus_default
    run_case "change-disk-bus.sh occupied destination refusal" test_change_disk_bus_refusal
    run_case "swap-vm-disks.sh" test_swap_vm_disks
    run_case "set-vm-boot-disk.sh preserves remaining order" test_set_vm_boot_disk
    run_case "set-vm-boot-disk.sh invalid slot refusal" test_set_vm_boot_refusal
    run_case "replace-vm-disk.sh preserves options + old disk" test_replace_vm_disk
    run_case "replace-vm-disk.sh shared replacement refusal" test_replace_shared_refusal
    run_case "renumber-vm-disks.sh mixed vm/base namespaces" test_renumber_vm_disks
    run_case "renumber-vm-disks.sh shared-volume refusal" test_renumber_shared_refusal
    run_case "renumber-vm-disks.sh base/template volumes" test_renumber_base_disks
    run_case "fix-vm-volume-names.sh" test_fix_vm_volume_names
    run_case "fix-vm-volume-names.sh corrected-name collision refusal" test_fix_name_collision
    run_case "fix-vm-volume-names.sh base/template volumes" test_fix_base_volume_names
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
    printf '%s\n' "Exercises exact/bare-bus changes, option preservation, swaps, boot-order preservation, replacement, vm/base renumbering and name repair."
    printf '%s\n' "Negative cases prove occupied-slot, invalid-boot, shared-volume and corrected-name-collision refusals leave all test-owned state unchanged."
    printf '%s\n' "Config backups created by the tools are identified by test VMID and removed only when they were not present before this run."
}

############################################################
# FIXTURES
############################################################

prepare_primary_config_fixture() {
    ppcf_role="${1:-disk-config}"
    CONFIG_VM="$(create_test_vm "$ppcf_role")"
    CONFIG_LV0_NAME="vm-${CONFIG_VM}-disk-0"
    CONFIG_LV1_NAME="vm-${CONFIG_VM}-disk-1"
    CONFIG_LV2_NAME="vm-${CONFIG_VM}-disk-2"
    CONFIG_LV0="$(create_thin_lv "$TEST_VG_A" "$CONFIG_LV0_NAME" 16M)"
    CONFIG_LV1="$(create_thin_lv "$TEST_VG_A" "$CONFIG_LV1_NAME" 16M)"
    CONFIG_LV2="$(create_thin_lv "$TEST_VG_A" "$CONFIG_LV2_NAME" 16M)"
    qm set "$CONFIG_VM" --scsi0 "$TEST_STORAGE_A:$CONFIG_LV0_NAME,cache=writeback,discard=on" >/dev/null
    qm set "$CONFIG_VM" --scsi1 "$TEST_STORAGE_A:$CONFIG_LV1_NAME,cache=none,iothread=1" >/dev/null
    qm set "$CONFIG_VM" --scsi2 "$TEST_STORAGE_A:$CONFIG_LV2_NAME" >/dev/null
}

############################################################
# TEST CASES
############################################################

test_change_disk_bus() {
    prepare_primary_config_fixture "bus-exact"
    tcdb_before="$(qm config "$CONFIG_VM" | sed -n 's/^scsi1:[[:space:]]*//p')"
    [ -n "$tcdb_before" ] || return 1
    run_dryrun_unchanged "change-disk-bus" change-disk-bus.sh "$CONFIG_VM" scsi1 sata0
    project_cmd change-disk-bus.sh "$CONFIG_VM" scsi1 sata0
    tcdb_after="$(qm config "$CONFIG_VM" | sed -n 's/^sata0:[[:space:]]*//p')"
    tcdb_expected="$(printf '%s\n' "$tcdb_before" | sed 's/,iothread=[^,]*//g')"
    [ "$tcdb_after" = "$tcdb_expected" ]
    ! printf '%s\n' "$tcdb_after" | grep -F ',iothread=' >/dev/null
    ! qm config "$CONFIG_VM" | grep -q '^scsi1:'
}

test_change_disk_bus_first_free() {
    prepare_primary_config_fixture "bus-first-free"
    tcdbf_before="$(qm config "$CONFIG_VM" | sed -n 's/^scsi2:[[:space:]]*//p')"
    [ -n "$tcdbf_before" ] || return 1
    run_dryrun_unchanged "change-disk-bus-first-free" change-disk-bus.sh "$CONFIG_VM" scsi2 virtio
    project_cmd change-disk-bus.sh "$CONFIG_VM" scsi2 virtio
    [ "$(qm config "$CONFIG_VM" | sed -n 's/^virtio0:[[:space:]]*//p')" = "$tcdbf_before" ]
    ! qm config "$CONFIG_VM" | grep -q '^scsi2:'
}

test_change_disk_bus_default() {
    prepare_primary_config_fixture "bus-default"
    tcdbd_name="vm-${CONFIG_VM}-disk-8"
    tcdbd_lv="$(create_thin_lv "$TEST_VG_A" "$tcdbd_name" 16M)"
    qm set "$CONFIG_VM" --scsi3 "$TEST_STORAGE_A:$tcdbd_name,cache=writeback" >/dev/null
    tcdbd_before="$(qm config "$CONFIG_VM" | sed -n 's/^scsi3:[[:space:]]*//p')"
    run_dryrun_unchanged "change-disk-bus-default-scsi" change-disk-bus.sh "$CONFIG_VM" scsi3
    project_cmd change-disk-bus.sh "$CONFIG_VM" scsi3
    [ "$(qm config "$CONFIG_VM" | sed -n 's/^scsi4:[[:space:]]*//p')" = "$tcdbd_before" ]
    ! qm config "$CONFIG_VM" | grep -q '^scsi3:'
}

test_change_disk_bus_refusal() {
    prepare_primary_config_fixture "bus-refusal"
    run_expect_fail_unchanged "change-disk-bus-occupied" change-disk-bus.sh "$CONFIG_VM" scsi0 scsi1
}

test_swap_vm_disks() {
    prepare_primary_config_fixture "swap"
    tsvd_scsi0_before="$(qm config "$CONFIG_VM" | sed -n 's/^scsi0:[[:space:]]*//p')"
    tsvd_scsi1_before="$(qm config "$CONFIG_VM" | sed -n 's/^scsi1:[[:space:]]*//p')"
    [ -n "$tsvd_scsi0_before" ] && [ -n "$tsvd_scsi1_before" ] || return 1
    run_dryrun_unchanged "swap-vm-disks" swap-vm-disks.sh "$CONFIG_VM" scsi0 scsi1
    project_cmd swap-vm-disks.sh "$CONFIG_VM" scsi0 scsi1
    [ "$(qm config "$CONFIG_VM" | sed -n 's/^scsi0:[[:space:]]*//p')" = "$tsvd_scsi1_before" ]
    [ "$(qm config "$CONFIG_VM" | sed -n 's/^scsi1:[[:space:]]*//p')" = "$tsvd_scsi0_before" ]
}

test_set_vm_boot_disk() {
    prepare_primary_config_fixture "boot"
    qm set "$CONFIG_VM" --boot "order=scsi1;scsi2;scsi0" >/dev/null
    run_dryrun_unchanged "set-vm-boot-disk" set-vm-boot-disk.sh "$CONFIG_VM" scsi0
    project_cmd set-vm-boot-disk.sh "$CONFIG_VM" scsi0
    tsvb_order="$(qm config "$CONFIG_VM" | sed -n 's/^boot:[[:space:]]*order=\([^,]*\).*/\1/p')"
    [ "$tsvb_order" = "scsi0;scsi1;scsi2" ]
}

test_set_vm_boot_refusal() {
    prepare_primary_config_fixture "boot-refusal"
    run_expect_fail_unchanged "set-vm-boot-invalid" set-vm-boot-disk.sh "$CONFIG_VM" scsi9
}

test_replace_vm_disk() {
    prepare_primary_config_fixture "replace"
    trvd_name="vm-${CONFIG_VM}-disk-9"
    trvd_lv="$(create_thin_lv "$TEST_VG_A" "$trvd_name" 16M)"
    trvd_old_value="$(qm config "$CONFIG_VM" | sed -n 's/^scsi0:[[:space:]]*//p')"
    trvd_old_volid="${trvd_old_value%%,*}"
    trvd_suffix="${trvd_old_value#"$trvd_old_volid"}"
    run_dryrun_unchanged "replace-vm-disk" replace-vm-disk.sh "$CONFIG_VM" scsi0 "$trvd_lv"
    project_cmd replace-vm-disk.sh "$CONFIG_VM" scsi0 "$trvd_lv"
    trvd_new_value="$(qm config "$CONFIG_VM" | sed -n 's/^scsi0:[[:space:]]*//p')"
    [ "$trvd_new_value" = "$TEST_STORAGE_A:$trvd_name$trvd_suffix" ]
    qm config "$CONFIG_VM" | awk -F': ' -v old="$trvd_old_volid" '$1 ~ /^unused[0-9]+$/ {split($2,a,","); if(a[1]==old) found=1} END {exit(found ? 0 : 1)}'
}

test_replace_shared_refusal() {
    prepare_primary_config_fixture "replace-shared"
    trsr_other="$(create_test_vm replace-shared-other)"
    trsr_name="vm-${trsr_other}-disk-0"
    trsr_lv="$(create_thin_lv "$TEST_VG_A" "$trsr_name" 16M)"
    attach_test_lv "$trsr_other" "$TEST_STORAGE_A" "$trsr_name" scsi0
    run_expect_fail_unchanged "replace-shared-refusal" replace-vm-disk.sh "$CONFIG_VM" scsi0 "$trsr_lv"
    qm config "$trsr_other" | grep -F "$TEST_STORAGE_A:$trsr_name" >/dev/null
}

test_renumber_vm_disks() {
    trn_vm="$(create_test_vm renumber)"
    trn_name3="vm-${trn_vm}-disk-3"
    trn_name7="vm-${trn_vm}-disk-7"
    trn_base_id="$(allocate_free_vmid)"
    trn_base4="base-${trn_base_id}-disk-4"
    trn_base9="base-${trn_base_id}-disk-9"
    create_thin_lv "$TEST_VG_A" "$trn_name3" 16M >/dev/null
    create_thin_lv "$TEST_VG_A" "$trn_name7" 16M >/dev/null
    create_thin_lv "$TEST_VG_A" "$trn_base4" 16M >/dev/null
    create_thin_lv "$TEST_VG_A" "$trn_base9" 16M >/dev/null
    attach_test_lv "$trn_vm" "$TEST_STORAGE_A" "$trn_name3" scsi0
    attach_test_lv "$trn_vm" "$TEST_STORAGE_A" "$trn_name7" scsi1
    attach_test_lv "$trn_vm" "$TEST_STORAGE_A" "$trn_base4" scsi2
    attach_test_lv "$trn_vm" "$TEST_STORAGE_A" "$trn_base9" scsi3

    run_dryrun_unchanged "renumber-vm-disks" renumber-vm-disks.sh "$trn_vm"
    project_cmd renumber-vm-disks.sh "$trn_vm"

    assert_lv_exists "$TEST_VG_A/vm-${trn_vm}-disk-0"
    assert_lv_exists "$TEST_VG_A/vm-${trn_vm}-disk-1"
    assert_lv_exists "$TEST_VG_A/base-${trn_base_id}-disk-0"
    assert_lv_exists "$TEST_VG_A/base-${trn_base_id}-disk-1"
    assert_lv_absent "$TEST_VG_A/$trn_name3"
    assert_lv_absent "$TEST_VG_A/$trn_name7"
    assert_lv_absent "$TEST_VG_A/$trn_base4"
    assert_lv_absent "$TEST_VG_A/$trn_base9"
}

test_renumber_shared_refusal() {
    trs_a="$(create_test_vm renumber-shared-a)"
    trs_b="$(create_test_vm renumber-shared-b)"
    trs_name="vm-${trs_a}-disk-5"
    create_thin_lv "$TEST_VG_A" "$trs_name" 16M >/dev/null
    attach_test_lv "$trs_a" "$TEST_STORAGE_A" "$trs_name" scsi0
    printf 'scsi0: %s:%s\n' "$TEST_STORAGE_A" "$trs_name" >> "/etc/pve/qemu-server/${trs_b}.conf"

    run_expect_fail_unchanged "renumber-shared-refusal" renumber-vm-disks.sh "$trs_a"
    assert_lv_exists "$TEST_VG_A/$trs_name"

    sed -i '/^scsi0: /d' "/etc/pve/qemu-server/${trs_b}.conf"
    project_cmd renumber-vm-disks.sh "$trs_a"
    assert_lv_exists "$TEST_VG_A/vm-${trs_a}-disk-0"
}

test_renumber_base_disks() {
    trb_vm="$(create_test_vm renumber-base)"
    trb_name3="vm-${trb_vm}-disk-3"
    trb_name7="vm-${trb_vm}-disk-7"
    create_thin_lv "$TEST_VG_A" "$trb_name3" 16M >/dev/null
    create_thin_lv "$TEST_VG_A" "$trb_name7" 16M >/dev/null
    attach_test_lv "$trb_vm" "$TEST_STORAGE_A" "$trb_name3" scsi0
    attach_test_lv "$trb_vm" "$TEST_STORAGE_A" "$trb_name7" scsi1
    qm template "$trb_vm" >/dev/null
    assert_lv_exists "$TEST_VG_A/base-${trb_vm}-disk-3"
    assert_lv_exists "$TEST_VG_A/base-${trb_vm}-disk-7"

    run_dryrun_unchanged "renumber-base-disks" renumber-vm-disks.sh "$trb_vm"
    project_cmd renumber-vm-disks.sh "$trb_vm"

    assert_lv_exists "$TEST_VG_A/base-${trb_vm}-disk-0"
    assert_lv_exists "$TEST_VG_A/base-${trb_vm}-disk-1"
    assert_lv_absent "$TEST_VG_A/base-${trb_vm}-disk-3"
    assert_lv_absent "$TEST_VG_A/base-${trb_vm}-disk-7"
    qm config "$trb_vm" | grep -F "$TEST_STORAGE_A:base-${trb_vm}-disk-0" >/dev/null
    qm config "$trb_vm" | grep -F "$TEST_STORAGE_A:base-${trb_vm}-disk-1" >/dev/null
}

test_fix_vm_volume_names() {
    tfvn_vm="$(create_test_vm fix-names)"
    tfvn_foreign="$(allocate_free_vmid)"
    tfvn_old="vm-${tfvn_foreign}-disk-0"
    tfvn_base_old="base-${tfvn_foreign}-disk-1"
    create_thin_lv "$TEST_VG_A" "$tfvn_old" 16M >/dev/null
    create_thin_lv "$TEST_VG_A" "$tfvn_base_old" 4M >/dev/null
    attach_test_lv "$tfvn_vm" "$TEST_STORAGE_A" "$tfvn_old" scsi0
    attach_test_lv "$tfvn_vm" "$TEST_STORAGE_A" "$tfvn_base_old" scsi1

    run_dryrun_unchanged "fix-vm-volume-names" fix-vm-volume-names.sh "$tfvn_vm"
    project_cmd fix-vm-volume-names.sh "$tfvn_vm"

    assert_lv_absent "$TEST_VG_A/$tfvn_old"
    assert_lv_absent "$TEST_VG_A/$tfvn_base_old"
    assert_lv_exists "$TEST_VG_A/vm-${tfvn_vm}-disk-0"
    assert_lv_exists "$TEST_VG_A/base-${tfvn_vm}-disk-1"
    qm config "$tfvn_vm" | grep -F "$TEST_STORAGE_A:vm-${tfvn_vm}-disk-0" >/dev/null
    qm config "$tfvn_vm" | grep -F "$TEST_STORAGE_A:base-${tfvn_vm}-disk-1" >/dev/null
}

test_fix_name_collision() {
    tfnc_vm="$(create_test_vm fix-collision)"
    tfnc_foreign="$(allocate_free_vmid)"
    tfnc_old="vm-${tfnc_foreign}-disk-0"
    tfnc_target="vm-${tfnc_vm}-disk-0"
    create_thin_lv "$TEST_VG_A" "$tfnc_old" 16M >/dev/null
    create_thin_lv "$TEST_VG_A" "$tfnc_target" 16M >/dev/null
    attach_test_lv "$tfnc_vm" "$TEST_STORAGE_A" "$tfnc_old" scsi0

    run_expect_fail_unchanged "fix-name-collision" fix-vm-volume-names.sh "$tfnc_vm"
    assert_lv_exists "$TEST_VG_A/$tfnc_old"
    assert_lv_exists "$TEST_VG_A/$tfnc_target"
}

test_fix_base_volume_names() {
    tfvb_vm="$(create_test_vm fix-base-names)"
    tfvb_seed="vm-${tfvb_vm}-disk-0"
    create_thin_lv "$TEST_VG_A" "$tfvb_seed" 16M >/dev/null
    attach_test_lv "$tfvb_vm" "$TEST_STORAGE_A" "$tfvb_seed" scsi0
    qm template "$tfvb_vm" >/dev/null

    tfvb_foreign="$(allocate_free_vmid)"
    tfvb_old="base-${tfvb_foreign}-disk-0"
    lvrename "$TEST_VG_A" "base-${tfvb_vm}-disk-0" "$tfvb_old" >/dev/null
    sed -i "s#${TEST_STORAGE_A}:base-${tfvb_vm}-disk-0#${TEST_STORAGE_A}:${tfvb_old}#g" "/etc/pve/qemu-server/${tfvb_vm}.conf"

    run_dryrun_unchanged "fix-base-volume-names" fix-vm-volume-names.sh "$tfvb_vm"
    project_cmd fix-vm-volume-names.sh "$tfvb_vm"

    assert_lv_exists "$TEST_VG_A/base-${tfvb_vm}-disk-0"
    assert_lv_absent "$TEST_VG_A/$tfvb_old"
    qm config "$tfvb_vm" | grep -F "$TEST_STORAGE_A:base-${tfvb_vm}-disk-0" >/dev/null
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
