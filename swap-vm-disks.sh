#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/common.sh"
. "$SCRIPT_DIR/lib/dryrun.sh"

############################################################
# SETUP / MAIN / END
############################################################

setup() {
    define_colours
    PROJECT_VERSION="3.0.1"; SCRIPT_VERSION="3.0.0"
    parse_arguments "$@"
    check_elevation
}

main() {
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    install_temp_cleanup
    need_commands qm cp awk mktemp
    require_qemu_vm "$VMID"; require_guest_stopped "$VMID"
    prepare_swap
    perform_swap
}

end() { dryrun_summary; }

############################################################
# COMMAND LINE
############################################################

usage() { printf 'Usage: %s <vmid> <slot-a> <slot-b> [dryrun]\n' "$(basename "$0")"; dryrun_help; }

parse_arguments() {
    pa_count=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            dryrun|--dryrun) enable_dryrun ;;
            -h|--help) usage; exit 0 ;;
            --version) printf '%s %s (project %s)\n' "$(basename "$0")" "$SCRIPT_VERSION" "$PROJECT_VERSION"; exit 0 ;;
            *) pa_count=$((pa_count + 1)); case "$pa_count" in 1) VMID="$1" ;; 2) A="$1" ;; 3) B="$1" ;; *) usage >&2; exit 2 ;; esac ;;
        esac
        shift
    done
    [ "$pa_count" -eq 3 ] || { usage >&2; exit 2; }
}

# prepare_swap
# Captures both slot values and computes the timestamped config backup path.
prepare_swap() {
    VA="$(disk_value "$VMID" "$A")"; VB="$(disk_value "$VMID" "$B")"
    [ -n "$VA" ] && [ -n "$VB" ] || die "Both slots must exist."
    CONFIG="/etc/pve/qemu-server/${VMID}.conf"; BACKUP="/root/${VMID}.conf.before-swap.$(date +%Y%m%d-%H%M%S)"
}

# perform_swap
#
# Description:
#   Swaps two disk-slot keys in the VM config using a temporary file, then
#   verifies exact slot values and restores the backup on verification failure.
#
# Usage:
#   perform_swap
#
# Arguments:
#   Uses A, B, VA, VB, CONFIG and BACKUP.
#
# Output:
#   Updates the VM configuration unless dry-run mode is active.
#
# Returns:
#   0 after verified swap.
############################################################
perform_swap() {
    if dryrun_enabled; then
        dryrun_cmd cp "$CONFIG" "$BACKUP"
        dryrun_print_shell "awk <swap $A and $B> $(shell_quote "$CONFIG") > <temporary-file>"
        dryrun_print_shell "cat <temporary-file> > $(shell_quote "$CONFIG")"
        dryrun_print_shell "rm -f <temporary-file>"
        dryrun_verify "$A and $B would be swapped"
    else
        ps_tmp="$(mktemp)" || die "Unable to create temporary config."
        register_temp_file "$ps_tmp"
        cp "$CONFIG" "$BACKUP"
        awk -v a="$A" -v b="$B" 'index($0,a":")==1 {sub("^"a":",b":"); print; next} index($0,b":")==1 {sub("^"b":",a":"); print; next} {print}' "$CONFIG" > "$ps_tmp"
        cat "$ps_tmp" > "$CONFIG"; rm -f "$ps_tmp"
        if [ "$(disk_value "$VMID" "$A")" != "$VB" ] || [ "$(disk_value "$VMID" "$B")" != "$VA" ]; then cp "$BACKUP" "$CONFIG"; die "Swap verification failed; config restored."; fi
    fi
    ok "Swapped $A and $B. Backup: $BACKUP"
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
