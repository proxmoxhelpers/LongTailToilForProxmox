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
    need_commands qm pvesm
    validate_move
    move_disk
}

end() { dryrun_summary; }

############################################################
# COMMAND LINE
############################################################

usage() { printf 'Usage: %s <vmid> <disk-slot> <destination-storage> [dryrun]\n' "$(basename "$0")"; dryrun_help; }

parse_arguments() {
    pa_count=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            dryrun|--dryrun) enable_dryrun ;;
            -h|--help) usage; exit 0 ;;
            --version) printf '%s %s (project %s)\n' "$(basename "$0")" "$SCRIPT_VERSION" "$PROJECT_VERSION"; exit 0 ;;
            *) pa_count=$((pa_count + 1)); case "$pa_count" in 1) VMID="$1" ;; 2) SLOT="$1" ;; 3) DEST="$1" ;; *) usage >&2; exit 2 ;; esac ;;
        esac
        shift
    done
    [ "$pa_count" -eq 3 ] || { usage >&2; exit 2; }
}

############################################################
# VALIDATION / PRE-FLIGHT
############################################################

# validate_move
# Validates the VM disk source and destination Proxmox storage before invoking qm move_disk.
validate_move() {
    require_qemu_vm "$VMID"
    OLD="$(disk_volid "$VMID" "$SLOT" || :)"; [ -n "$OLD" ] || die "No disk volume found at $SLOT."
    pvesm status --storage "$DEST" >/dev/null 2>&1 || die "Destination storage does not exist or is unavailable: $DEST"
    [ "${OLD%%:*}" != "$DEST" ] || die "Disk is already on storage $DEST."
}

############################################################
# HIGH LEVEL TASKS
############################################################

# move_disk
# Moves one VM disk through qm and verifies that its slot now belongs to the destination storage.
move_disk() {
    info "Moving VM $VMID $SLOT from $OLD to storage $DEST..."
    dryrun_cmd qm move_disk "$VMID" "$SLOT" "$DEST" --delete 1
    if dryrun_enabled; then NEW="${DEST}:<new-volume>"; dryrun_verify "$SLOT would move to storage $DEST"
    else
        NEW="$(disk_volid "$VMID" "$SLOT" || :)"
        [ -n "$NEW" ] && [ "${NEW%%:*}" = "$DEST" ] || die "Move verification failed."
    fi
    ok "$SLOT is now $NEW."
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
