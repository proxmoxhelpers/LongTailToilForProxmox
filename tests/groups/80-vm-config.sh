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
    PROJECT_VERSION="3.7.1"
    TEST_SUITE_VERSION="3.1.1"
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
    run_case "change-vmid-of-vm.sh QEMU vm-* volumes" test_change_vmid
    run_case "change-vmid-of-vm.sh base/template volumes" test_change_vmid_base
    run_case "change-vmid-of-vm.sh LXC rootfs" test_change_vmid_lxc
    run_case "change-vmid-of-vm.sh destination collision refusal" test_change_vmid_destination_refusal
    run_case "change-vmid-of-vm.sh snapshot refusal" test_change_vmid_snapshot_refusal
    run_case "change-vmid-of-vm.sh shared-volume refusal" test_change_vmid_shared_refusal
    run_case "clone-vm-config-only.sh strips storage references" test_clone_config_only
    run_case "recover-vm-from-volumes.sh vm-* volumes" test_recover_vm
    run_case "recover-vm-from-volumes.sh base volumes" test_recover_base
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
    printf '%s\n' "Tests QEMU/template/LXC VMID changes, vm/base recovery and diskless config cloning."
    printf '%s\n' "Negative VMID cases cover occupied destination IDs, snapshots and shared volumes; each must fail with exact test-owned state unchanged."
    printf '%s\n' "All IDs are dynamically selected from an unused high range; cleanup validates exact VM names/CT hostnames and test-owned storage references before purge."
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
    write_test_pattern "$tcv_lv" "change-vmid"
    tcv_uuid="$(lvs --noheadings -o lv_uuid "$tcv_lv" | tr -d '[:space:]')"
    attach_test_lv "$tcv_old" "$TEST_STORAGE_A" "$tcv_lv_name" scsi0
    qm start "$tcv_old" >/dev/null
    [ "$(qm status "$tcv_old" | awk '{print $2}')" = "running" ]
    run_dryrun_unchanged "change-vmid" change-vmid-of-vm.sh "$tcv_old" "$tcv_new"
    [ "$(qm status "$tcv_old" | awk '{print $2}')" = "running" ]
    project_cmd change-vmid-of-vm.sh "$tcv_old" "$tcv_new"
    [ ! -f "/etc/pve/qemu-server/${tcv_old}.conf" ]
    [ -f "/etc/pve/qemu-server/${tcv_new}.conf" ]
    assert_lv_exists "$TEST_VG_A/vm-${tcv_new}-disk-0"
    assert_lv_absent "$TEST_VG_A/vm-${tcv_old}-disk-0"
    [ "$(lvs --noheadings -o lv_uuid "$TEST_VG_A/vm-${tcv_new}-disk-0" | tr -d '[:space:]')" = "$tcv_uuid" ]
    qm config "$tcv_new" | grep -F "$TEST_STORAGE_A:vm-${tcv_new}-disk-0" >/dev/null
    [ "$(qm status "$tcv_new" | awk '{print $2}')" = "stopped" ]
}

test_change_vmid_base() {
    tcvb_old="$(create_test_vm vmid-base-src)"
    tcvb_name="plvt-${TEST_TOKEN}-vmid-base-src"
    tcvb_new="$(allocate_free_vmid)"
    register_owned_vm "$tcvb_new" "$tcvb_name"

    tcvb_seed="vm-${tcvb_old}-disk-0"
    create_thin_lv "$TEST_VG_A" "$tcvb_seed" 16M >/dev/null
    attach_test_lv "$tcvb_old" "$TEST_STORAGE_A" "$tcvb_seed" scsi0
    qm template "$tcvb_old" >/dev/null
    assert_lv_exists "$TEST_VG_A/base-${tcvb_old}-disk-0"

    run_dryrun_unchanged "change-vmid-base" change-vmid-of-vm.sh "$tcvb_old" "$tcvb_new"
    project_cmd change-vmid-of-vm.sh "$tcvb_old" "$tcvb_new"

    [ ! -f "/etc/pve/qemu-server/${tcvb_old}.conf" ]
    [ -f "/etc/pve/qemu-server/${tcvb_new}.conf" ]
    assert_lv_exists "$TEST_VG_A/base-${tcvb_new}-disk-0"
    assert_lv_absent "$TEST_VG_A/base-${tcvb_old}-disk-0"
    qm config "$tcvb_new" | grep -F "$TEST_STORAGE_A:base-${tcvb_new}-disk-0" >/dev/null
}

test_change_vmid_lxc() {
    tcvl_old="$(create_test_ct vmid-lxc-src)"
    tcvl_hostname="plvt-${TEST_TOKEN}-vmid-lxc-src"
    tcvl_new="$(allocate_free_vmid)"
    register_owned_ct "$tcvl_new" "$tcvl_hostname"
    tcvl_lv_name="vm-${tcvl_old}-disk-0"
    tcvl_lv="$(create_thin_lv "$TEST_VG_A" "$tcvl_lv_name" 16M)"
    tcvl_uuid="$(lvs --noheadings -o lv_uuid "$tcvl_lv" | tr -d '[:space:]')"
    attach_test_ct_lv "$tcvl_old" "$TEST_STORAGE_A" "$tcvl_lv_name" rootfs 16M

    run_dryrun_unchanged "change-vmid-lxc" change-vmid-of-vm.sh "$tcvl_old" "$tcvl_new"
    project_cmd change-vmid-of-vm.sh "$tcvl_old" "$tcvl_new"

    [ ! -f "/etc/pve/lxc/${tcvl_old}.conf" ]
    [ -f "/etc/pve/lxc/${tcvl_new}.conf" ]
    assert_lv_exists "$TEST_VG_A/vm-${tcvl_new}-disk-0"
    assert_lv_absent "$TEST_VG_A/vm-${tcvl_old}-disk-0"
    [ "$(lvs --noheadings -o lv_uuid "$TEST_VG_A/vm-${tcvl_new}-disk-0" | tr -d '[:space:]')" = "$tcvl_uuid" ]
    pct config "$tcvl_new" | grep -F "$TEST_STORAGE_A:vm-${tcvl_new}-disk-0" >/dev/null
}

test_change_vmid_destination_refusal() {
    tcvd_src="$(create_test_vm vmid-collision-src)"
    tcvd_dst="$(create_test_vm vmid-collision-dst)"
    tcvd_name="vm-${tcvd_src}-disk-0"
    create_thin_lv "$TEST_VG_A" "$tcvd_name" 16M >/dev/null
    attach_test_lv "$tcvd_src" "$TEST_STORAGE_A" "$tcvd_name" scsi0
    run_expect_fail_unchanged "change-vmid-destination-collision" change-vmid-of-vm.sh "$tcvd_src" "$tcvd_dst"
    [ -f "/etc/pve/qemu-server/${tcvd_src}.conf" ] && [ -f "/etc/pve/qemu-server/${tcvd_dst}.conf" ]
    assert_lv_exists "$TEST_VG_A/$tcvd_name"
}

test_change_vmid_snapshot_refusal() {
    tcvs_vm="$(create_test_vm vmid-snapshot)"
    tcvs_new="$(allocate_free_vmid)"
    tcvs_name="vm-${tcvs_vm}-disk-0"
    create_thin_lv "$TEST_VG_A" "$tcvs_name" 16M >/dev/null
    attach_test_lv "$tcvs_vm" "$TEST_STORAGE_A" "$tcvs_name" scsi0
    qm snapshot "$tcvs_vm" plvt-test-snapshot >/dev/null
    run_expect_fail_unchanged "change-vmid-snapshot-refusal" change-vmid-of-vm.sh "$tcvs_vm" "$tcvs_new"
    [ -f "/etc/pve/qemu-server/${tcvs_vm}.conf" ]
}

test_change_vmid_shared_refusal() {
    tcvsh_src="$(create_test_vm vmid-shared-src)"
    tcvsh_other="$(create_test_vm vmid-shared-other)"
    tcvsh_new="$(allocate_free_vmid)"
    tcvsh_name="vm-${tcvsh_src}-disk-0"
    create_thin_lv "$TEST_VG_A" "$tcvsh_name" 16M >/dev/null
    attach_test_lv "$tcvsh_src" "$TEST_STORAGE_A" "$tcvsh_name" scsi0
    printf 'scsi0: %s:%s\n' "$TEST_STORAGE_A" "$tcvsh_name" >> "/etc/pve/qemu-server/${tcvsh_other}.conf"

    run_expect_fail_unchanged "change-vmid-shared-refusal" change-vmid-of-vm.sh "$tcvsh_src" "$tcvsh_new"
    [ -f "/etc/pve/qemu-server/${tcvsh_src}.conf" ]
    assert_lv_exists "$TEST_VG_A/$tcvsh_name"

    sed -i '/^scsi0: /d' "/etc/pve/qemu-server/${tcvsh_other}.conf"
}

test_clone_config_only() {
    tcco_src="$(create_test_vm clone-src)"
    tcco_lv_name="vm-${tcco_src}-disk-0"
    create_thin_lv "$TEST_VG_A" "$tcco_lv_name" 16M >/dev/null
    attach_test_lv "$tcco_src" "$TEST_STORAGE_A" "$tcco_lv_name" scsi0
    qm set "$tcco_src" --description "plvt clone config marker" >/dev/null
    tcco_dst="$(allocate_free_vmid)"
    tcco_name="plvt-${TEST_TOKEN}-clone-dst"
    register_owned_vm "$tcco_dst" "$tcco_name"
    run_dryrun_unchanged "clone-config-only" clone-vm-config-only.sh "$tcco_src" "$tcco_dst" "$tcco_name"
    project_cmd clone-vm-config-only.sh "$tcco_src" "$tcco_dst" "$tcco_name"
    [ -f "/etc/pve/qemu-server/${tcco_dst}.conf" ]
    [ "$(qm config "$tcco_dst" | sed -n 's/^name:[[:space:]]*//p')" = "$tcco_name" ]
    qm config "$tcco_dst" | grep -F 'description: plvt clone config marker' >/dev/null
    ! qm config "$tcco_dst" | grep -E '^(scsi|sata|virtio|ide|unused|efidisk|tpmstate)[0-9]+:' >/dev/null
}

test_recover_vm() {
    trv_id="$(allocate_free_vmid)"
    trv_name0="vm-${trv_id}-disk-0"
    trv_name2="vm-${trv_id}-disk-2"
    create_thin_lv "$TEST_VG_A" "$trv_name0" 16M >/dev/null
    create_thin_lv "$TEST_VG_A" "$trv_name2" 16M >/dev/null
    register_owned_vm "$trv_id" "recovered-${trv_id}"
    run_dryrun_unchanged "recover-vm" recover-vm-from-volumes.sh "$trv_id" "$TEST_VG_A"
    project_cmd recover-vm-from-volumes.sh "$trv_id" "$TEST_VG_A"
    [ -f "/etc/pve/qemu-server/${trv_id}.conf" ]
    qm config "$trv_id" | grep -F "$TEST_STORAGE_A:$trv_name0" >/dev/null
    qm config "$trv_id" | grep -F "$TEST_STORAGE_A:$trv_name2" >/dev/null
    [ "$(qm status "$trv_id" | awk '{print $2}')" = "stopped" ]
}

test_recover_base() {
    trvb_id="$(allocate_free_vmid)"
    trvb_name="base-${trvb_id}-disk-0"
    create_thin_lv "$TEST_VG_A" "$trvb_name" 16M >/dev/null
    register_owned_vm "$trvb_id" "recovered-${trvb_id}"

    run_dryrun_unchanged "recover-base-auto-vg" recover-vm-from-volumes.sh "$trvb_id"
    project_cmd recover-vm-from-volumes.sh "$trvb_id"

    [ -f "/etc/pve/qemu-server/${trvb_id}.conf" ]
    qm config "$trvb_id" | grep -F "$TEST_STORAGE_A:$trvb_name" >/dev/null
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
