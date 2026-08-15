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
    need_commands qm
    require_qemu_vm "$VMID"; require_guest_stopped "$VMID"
    detach_disk
}

end() { dryrun_summary; }

############################################################
# COMMAND LINE
############################################################

usage() { printf 'Usage: %s <vmid> <disk-slot> [dryrun]\n' "$(basename "$0")"; dryrun_help; }

parse_arguments() {
    pa_count=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            dryrun|--dryrun) enable_dryrun ;;
            -h|--help) usage; exit 0 ;;
            --version) printf '%s %s (project %s)\n' "$(basename "$0")" "$SCRIPT_VERSION" "$PROJECT_VERSION"; exit 0 ;;
            *) pa_count=$((pa_count + 1)); case "$pa_count" in 1) VMID="$1" ;; 2) SLOT="$1" ;; *) usage >&2; exit 2 ;; esac ;;
        esac
        shift
    done
    [ "$pa_count" -eq 2 ] || { usage >&2; exit 2; }
}

############################################################
# HIGH LEVEL TASKS
############################################################

# detach_disk
# Removes SLOT from the active VM config while preserving its volume as unusedN.
detach_disk() {
    VOLID="$(disk_volid "$VMID" "$SLOT" || :)"; [ -n "$VOLID" ] || die "No Proxmox volume found at $SLOT."
    info "Detaching $SLOT ($VOLID) from VM $VMID..."
    dryrun_cmd qm set "$VMID" --delete "$SLOT"
    if dryrun_enabled; then
        dryrun_verify "$SLOT would be detached"; UNUSED="unusedN"
    else
        [ -z "$(disk_value "$VMID" "$SLOT")" ] || die "$SLOT still exists after detach."
        UNUSED="$(qm config "$VMID" | awk -F': ' -v v="$VOLID" '$1 ~ /^unused[0-9]+$/ && index($2,v)==1 {print $1; exit}')"
    fi
    if [ -n "$UNUSED" ]; then ok "Detached. Volume preserved as $UNUSED: $VOLID"
    else warn "Detached, but no unusedN entry was found. Underlying volume was not explicitly deleted by this script."; fi
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
