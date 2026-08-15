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
    need_commands qm pvesm awk
    validate_delete
    detach_if_needed
    delete_volume
    verify_delete
}

end() { dryrun_summary; }

############################################################
# COMMAND LINE
############################################################

usage() { printf 'Usage: %s <vmid> <disk-slot|unusedN> [dryrun]\n' "$(basename "$0")"; dryrun_help; }

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
# VALIDATION / PRE-FLIGHT
############################################################

# validate_delete
#
# Description:
#   Resolves the selected VM disk, records its storage and backing path,
#   and refuses deletion when another guest references the same volume.
#
# Usage:
#   validate_delete
#
# Arguments:
#   Uses VMID and SLOT.
#
# Output:
#   Sets VOLID, STORAGE_ID, VOLUME_PATH and CONFIG.
#
# Returns:
#   0 on successful preflight; exits on unsafe conditions.
############################################################
validate_delete() {
    require_qemu_vm "$VMID"; require_guest_stopped "$VMID"
    VOLID="$(disk_volid "$VMID" "$SLOT" || :)"; [ -n "$VOLID" ] || die "No storage volume found at $SLOT."
    STORAGE_ID="${VOLID%%:*}"
    VOLUME_PATH="$(pvesm path "$VOLID" 2>/dev/null || :)"; [ -n "$VOLUME_PATH" ] || die "Cannot resolve backing path for $VOLID."
    CONFIG="/etc/pve/qemu-server/${VMID}.conf"
    vd_others="$(other_volume_references "$VOLID" "$CONFIG")"
    [ -z "$vd_others" ] || { printf '%s\n' "$vd_others"; die "Volume is referenced by another guest."; }
}

############################################################
# HIGH LEVEL TASKS
############################################################

# detach_if_needed
# Converts an attached disk slot into its unusedN entry before deletion.
detach_if_needed() {
    case "$SLOT" in unused[0-9]*) return 0 ;; esac
    dryrun_cmd qm set "$VMID" --delete "$SLOT"
    if dryrun_enabled; then SLOT="unusedN"; dryrun_verify "Disk would be detached and preserved as an unusedN entry"
    else
        SLOT="$(qm config "$VMID" | awk -F': ' -v v="$VOLID" '$1 ~ /^unused[0-9]+$/ && index($2,v)==1 {print $1; exit}')"
        [ -n "$SLOT" ] || die "Disk detached, but its unusedN entry could not be identified. Volume left intact."
    fi
}

# delete_volume
# Removes the unused config reference and frees the Proxmox storage volume.
delete_volume() {
    info "Deleting $VOLID..."
    dryrun_cmd qm set "$VMID" --delete "$SLOT"
    dryrun_cmd pvesm free "$VOLID"
}

# verify_delete
# Verifies storage listing and the pre-resolved backing path independently.
verify_delete() {
    if dryrun_enabled; then
        dryrun_verify "$VOLID would be absent from storage $STORAGE_ID and its backing path would no longer exist"
        ok "Deleted $VOLID."
        return 0
    fi
    vd_list="$(pvesm list "$STORAGE_ID" --vmid "$VMID" 2>/dev/null)" || die "Unable to verify storage contents after deleting $VOLID."
    if printf '%s\n' "$vd_list" | awk -v vol="$VOLID" '$1 == vol { found=1 } END { exit(found ? 0 : 1) }'; then die "Volume is still listed by storage $STORAGE_ID after deletion: $VOLID"; fi
    [ ! -e "$VOLUME_PATH" ] && [ ! -L "$VOLUME_PATH" ] || die "Backing path still exists after deletion: $VOLUME_PATH"
    ok "Deleted $VOLID."
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
