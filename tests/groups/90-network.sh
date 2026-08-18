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
    TEST_GROUP="network"
    test_reset_counters
    test_parse_arguments "$@"
    [ "$TEST_RUN" = "false" ] || check_elevation
}

main() {
    [ "$TEST_RUN" = "true" ] || { print_plan; return 0; }
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    require_proxmox_environment
    require_command ip
    test_prepare_run
    NETWORK_BRIDGE="$(find_test_bridge || :)"
    if [ -z "$NETWORK_BRIDGE" ]; then skip_case "bulk-change-vm-network.sh — no existing Linux bridge was detected"; return 0; fi
    prepare_network_fixture
    run_case "bulk-change-vm-network.sh QEMU+LXC options/model preservation" test_bulk_network
    run_case "bulk-change-vm-network.sh tag removal/firewall update" test_bulk_network_remove_tag
    run_case "bulk-change-vm-network.sh missing-guest refusal before mutation" test_bulk_network_refusal
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
    print_banner "Bulk VM network tests"
    printf '%s\n' "Creates two stopped diskless QEMU VMs plus one config-only stopped CT and uses an already-existing Linux bridge."
    printf '%s\n' "No bridge is created or modified. The real cases exercise bridge, VLAN tag, firewall and QEMU model changes while preserving MAC/other NIC options."
    printf '%s\n' "A missing-guest negative case is placed first in the target list so refusal is proven before any mutation."
}

############################################################
# FIXTURE
############################################################

find_test_bridge() {
    ip -o link show type bridge 2>/dev/null | awk -F': ' '
        {
            split($2,a,"@")
            name=a[1]
            if (first=="") first=name
            if (name ~ /^vmbr[0-9]*$/) { print name; found=1; exit }
        }
        END { if (!found && first!="") print first }
    '
}

prepare_network_fixture() {
    NET_VM1="$(create_test_vm net-a)" || die "Could not create first disposable network-test VM."
    NET_VM2="$(create_test_vm net-b)" || die "Could not create second disposable network-test VM."
    NET_CT="$(create_test_ct net-ct)" || die "Could not create disposable network-test CT config."

    NET_CT_ROOT_NAME="vm-${NET_CT}-disk-0"
    create_thin_lv "$TEST_VG_A" "$NET_CT_ROOT_NAME" 16M >/dev/null || die "Could not create disposable CT rootfs LV."
    attach_test_ct_lv "$NET_CT" "$TEST_STORAGE_A" "$NET_CT_ROOT_NAME" rootfs 16M
    pct config "$NET_CT" >/dev/null 2>&1 || die "Disposable CT rootfs fixture is not valid."

    # Seed NIC configuration directly in stopped disposable configs. Fixture
    # setup must not pre-test the same qm/pct network mutation API under test.
    printf 'net0: virtio=02:00:00:00:00:11,bridge=%s,queues=2\n' "$NETWORK_BRIDGE" >> "/etc/pve/qemu-server/${NET_VM1}.conf"
    printf 'net0: virtio=02:00:00:00:00:12,bridge=%s,queues=4\n' "$NETWORK_BRIDGE" >> "/etc/pve/qemu-server/${NET_VM2}.conf"
    printf 'net0: name=eth0,bridge=%s,hwaddr=02:00:00:00:00:13,type=veth\n' "$NETWORK_BRIDGE" >> "/etc/pve/lxc/${NET_CT}.conf"

    qm config "$NET_VM1" >/dev/null 2>&1 || die "First disposable QEMU network fixture is not valid."
    qm config "$NET_VM2" >/dev/null 2>&1 || die "Second disposable QEMU network fixture is not valid."
    pct config "$NET_CT" >/dev/null 2>&1 || die "Disposable LXC network fixture is not valid."

    NET_MISSING="$(allocate_free_vmid)" || die "Could not allocate missing-guest test ID."
}

############################################################
# TEST CASES
############################################################

test_bulk_network() {
    run_dryrun_unchanged "bulk-network-options" bulk-change-vm-network.sh net0 "$NETWORK_BRIDGE" --tag 123 --firewall 1 --model e1000 "$NET_VM1" "$NET_VM2" "$NET_CT"
    project_cmd bulk-change-vm-network.sh net0 "$NETWORK_BRIDGE" --tag 123 --firewall 1 --model e1000 "$NET_VM1" "$NET_VM2" "$NET_CT"

    tbn_v1="$(qm config "$NET_VM1" | sed -n 's/^net0:[[:space:]]*//p')"
    tbn_v2="$(qm config "$NET_VM2" | sed -n 's/^net0:[[:space:]]*//p')"
    tbn_ct="$(pct config "$NET_CT" | sed -n 's/^net0:[[:space:]]*//p')"
    printf '%s\n' "$tbn_v1" | grep -F 'e1000=02:00:00:00:00:11' >/dev/null
    printf '%s\n' "$tbn_v1" | grep -F 'queues=2' >/dev/null
    printf '%s\n' "$tbn_v2" | grep -F 'e1000=02:00:00:00:00:12' >/dev/null
    printf '%s\n' "$tbn_v2" | grep -F 'queues=4' >/dev/null
    for tbn_value in "$tbn_v1" "$tbn_v2" "$tbn_ct"; do
        printf '%s\n' "$tbn_value" | grep -F "bridge=$NETWORK_BRIDGE" >/dev/null
        printf '%s\n' "$tbn_value" | grep -F 'tag=123' >/dev/null
        printf '%s\n' "$tbn_value" | grep -F 'firewall=1' >/dev/null
    done
    printf '%s\n' "$tbn_ct" | grep -F 'name=eth0' >/dev/null
    printf '%s\n' "$tbn_ct" | grep -F 'hwaddr=02:00:00:00:00:13' >/dev/null
    ! printf '%s\n' "$tbn_ct" | grep -E '(^|,)e1000=' >/dev/null
}

test_bulk_network_remove_tag() {
    run_dryrun_unchanged "bulk-network-remove-tag" bulk-change-vm-network.sh net0 "$NETWORK_BRIDGE" --tag none --firewall 0 "$NET_VM1" "$NET_VM2" "$NET_CT"
    project_cmd bulk-change-vm-network.sh net0 "$NETWORK_BRIDGE" --tag none --firewall 0 "$NET_VM1" "$NET_VM2" "$NET_CT"
    for tbnr_id in "$NET_VM1" "$NET_VM2"; do
        tbnr_value="$(qm config "$tbnr_id" | sed -n 's/^net0:[[:space:]]*//p')"
        ! printf '%s\n' "$tbnr_value" | grep -E '(^|,)tag=' >/dev/null
        printf '%s\n' "$tbnr_value" | grep -F 'firewall=0' >/dev/null
        printf '%s\n' "$tbnr_value" | grep -E '^e1000=02:00:00:00:00:(11|12)' >/dev/null
    done
    tbnr_ct="$(pct config "$NET_CT" | sed -n 's/^net0:[[:space:]]*//p')"
    ! printf '%s\n' "$tbnr_ct" | grep -E '(^|,)tag=' >/dev/null
    printf '%s\n' "$tbnr_ct" | grep -F 'firewall=0' >/dev/null
}

test_bulk_network_refusal() {
    run_expect_fail_unchanged "bulk-network-missing-first" bulk-change-vm-network.sh net0 "$NETWORK_BRIDGE" "$NET_MISSING" "$NET_VM1"
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
