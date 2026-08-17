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
    TEST_GROUP="vm-config"
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
    run_case "change-vmid-of-vm.sh" test_change_vmid
    run_case "clone-vm-config-only.sh" test_clone_config_only
    run_case "recover-vm-from-volumes.sh" test_recover_vm
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
    print_banner "VM configuration / recovery tests"
    printf '%s\n' "Tests VMID change, diskless config cloning and recovery from an orphaned test LV."
    printf '%s\n' "All VMIDs are dynamically selected from an unused high range and all VMs remain stopped."
    printf '%s\n' "Cleanup validates the expected test VM name before any qm destroy."
}

############################################################
# TEST CASES
############################################################

test_change_vmid() {
    tcv_old="$(create_test_vm vmid-src)"
    tcv_name="plvt-${TEST_TOKEN}-vmid-src"
    tcv_new="$(allocate_free_vmid)"
    register_owned_vm "$tcv_new" "$tcv_name"
    tcv_lv_name="vm-${tcv_old}-disk-0"
    tcv_lv="$(create_thin_lv "$TEST_VG_A" "$tcv_lv_name" 16M)"
    attach_test_lv "$tcv_old" "$TEST_STORAGE_A" "$tcv_lv_name" scsi0
    run_dryrun_unchanged "change-vmid" change-vmid-of-vm.sh "$tcv_old" "$tcv_new"
    project_cmd change-vmid-of-vm.sh "$tcv_old" "$tcv_new"
    [ ! -f "/etc/pve/qemu-server/${tcv_old}.conf" ]
    [ -f "/etc/pve/qemu-server/${tcv_new}.conf" ]
    assert_lv_exists "$TEST_VG_A/vm-${tcv_new}-disk-0"
    assert_lv_absent "$TEST_VG_A/vm-${tcv_old}-disk-0"
}

test_clone_config_only() {
    tcco_src="$(create_test_vm clone-src)"
    tcco_lv_name="vm-${tcco_src}-disk-0"
    create_thin_lv "$TEST_VG_A" "$tcco_lv_name" 16M >/dev/null
    attach_test_lv "$tcco_src" "$TEST_STORAGE_A" "$tcco_lv_name" scsi0
    tcco_dst="$(allocate_free_vmid)"
    tcco_name="plvt-${TEST_TOKEN}-clone-dst"
    register_owned_vm "$tcco_dst" "$tcco_name"
    run_dryrun_unchanged "clone-config-only" clone-vm-config-only.sh "$tcco_src" "$tcco_dst" "$tcco_name"
    project_cmd clone-vm-config-only.sh "$tcco_src" "$tcco_dst" "$tcco_name"
    [ -f "/etc/pve/qemu-server/${tcco_dst}.conf" ]
    ! qm config "$tcco_dst" | grep -E '^(scsi|sata|virtio|ide|unused|efidisk|tpmstate)[0-9]+:' >/dev/null
}

test_recover_vm() {
    trv_id="$(allocate_free_vmid)"
    trv_name="vm-${trv_id}-disk-0"
    create_thin_lv "$TEST_VG_A" "$trv_name" 16M >/dev/null
    register_owned_vm "$trv_id" "recovered-${trv_id}"
    run_dryrun_unchanged "recover-vm" recover-vm-from-volumes.sh "$trv_id" "$TEST_VG_A"
    project_cmd recover-vm-from-volumes.sh "$trv_id" "$TEST_VG_A"
    [ -f "/etc/pve/qemu-server/${trv_id}.conf" ]
    qm config "$trv_id" | grep -F "$TEST_STORAGE_A:$trv_name" >/dev/null
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
