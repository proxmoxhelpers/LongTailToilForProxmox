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
    PROJECT_VERSION="3.3.0"
    TEST_SUITE_VERSION="2.4.0"
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
    run_case "bulk-change-vm-network.sh" test_bulk_network
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
    printf '%s\n' "Creates two stopped, diskless test VMs and uses an already-existing Linux bridge."
    printf '%s\n' "No bridge is created or modified. If no bridge exists, the test is explicitly skipped."
    printf '%s\n' "The test changes only the net0 definitions of the two disposable VMs."
}

############################################################
# FIXTURE
############################################################

find_test_bridge() {
    ip -o link show type bridge 2>/dev/null | awk -F': ' '{split($2,a,"@"); print a[1]; exit}'
}

prepare_network_fixture() {
    NET_VM1="$(create_test_vm net-a)"
    NET_VM2="$(create_test_vm net-b)"
    qm set "$NET_VM1" --net0 "virtio=02:00:00:00:00:11,bridge=$NETWORK_BRIDGE" >/dev/null
    qm set "$NET_VM2" --net0 "virtio=02:00:00:00:00:12,bridge=$NETWORK_BRIDGE" >/dev/null
}

############################################################
# TEST CASES
############################################################

test_bulk_network() {
    run_dryrun_unchanged "bulk-network" bulk-change-vm-network.sh net0 "$NETWORK_BRIDGE" --firewall 1 "$NET_VM1" "$NET_VM2"
    project_cmd bulk-change-vm-network.sh net0 "$NETWORK_BRIDGE" --firewall 1 "$NET_VM1" "$NET_VM2"
    qm config "$NET_VM1" | grep -E '^net0:.*firewall=1' >/dev/null
    qm config "$NET_VM2" | grep -E '^net0:.*firewall=1' >/dev/null
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
