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
    need_commands qm lvs pvesm
    validate_replacement
    replace_disk
}

end() { dryrun_summary; }

############################################################
# COMMAND LINE
############################################################

usage() { printf 'Usage: %s <vmid> <disk-slot> <replacement-lv-path> [dryrun]\n' "$(basename "$0")"; dryrun_help; }

parse_arguments() {
    pa_count=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            dryrun|--dryrun) enable_dryrun ;;
            -h|--help) usage; exit 0 ;;
            --version) printf '%s %s (project %s)\n' "$(basename "$0")" "$SCRIPT_VERSION" "$PROJECT_VERSION"; exit 0 ;;
            *) pa_count=$((pa_count + 1)); case "$pa_count" in 1) VMID="$1" ;; 2) SLOT="$1" ;; 3) NEW_LV="$1" ;; *) usage >&2; exit 2 ;; esac ;;
        esac
        shift
    done
    [ "$pa_count" -eq 3 ] || { usage >&2; exit 2; }
}

############################################################
# VALIDATION / PRE-FLIGHT
############################################################

# validate_replacement
# Resolves current/replacement volumes, preserves disk options and rejects a shared replacement LV.
validate_replacement() {
    require_qemu_vm "$VMID"; require_guest_stopped "$VMID"
    OLD_VALUE="$(disk_value "$VMID" "$SLOT")"; [ -n "$OLD_VALUE" ] || die "No disk exists at $SLOT."
    OLD_VOLID="${OLD_VALUE%%,*}"; SUFFIX="${OLD_VALUE#"$OLD_VOLID"}"
    assert_lv_exists "$NEW_LV"; NEW_LV="$(canonical_lv_path "$NEW_LV")"; NEW_VOLID="$(volid_for_lv "$NEW_LV")"
    [ -z "$(other_volume_references "$NEW_VOLID")" ] || die "Replacement volume is already referenced by another guest."
}

############################################################
# HIGH LEVEL TASKS
############################################################

# replace_disk
# Detaches the old slot, attaches the replacement, and attempts restoration if attachment fails.
replace_disk() {
    info "Replacing $SLOT: $OLD_VOLID -> $NEW_VOLID"
    dryrun_cmd qm set "$VMID" --delete "$SLOT"
    if ! dryrun_cmd qm set "$VMID" "--$SLOT" "${NEW_VOLID}${SUFFIX}"; then
        warn "Replacement attach failed; attempting to restore original disk."
        dryrun_cmd qm set "$VMID" "--$SLOT" "$OLD_VALUE" || :
        die "Replacement failed."
    fi
    if dryrun_enabled; then dryrun_verify "$SLOT would reference $NEW_VOLID"
    else [ "$(disk_volid "$VMID" "$SLOT")" = "$NEW_VOLID" ] || die "Replacement verification failed."; fi
    ok "Replaced $SLOT. Old disk remains detached/unused if Proxmox created an unusedN entry."
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
