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
    SLOT=""
    parse_arguments "$@"
    check_elevation
}

main() {
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    install_temp_cleanup
    need_commands qm pvesm mktemp
    validate_import
    import_disk
    attach_imported_disk
}

end() {
    [ -z "${BEFORE_FILE:-}" ] || rm -f "$BEFORE_FILE"
    [ -z "${AFTER_FILE:-}" ] || rm -f "$AFTER_FILE"
    dryrun_summary
}

############################################################
# COMMAND LINE
############################################################

usage() { printf 'Usage: %s <image-file> <vmid> <destination-storage> [scsiN] [dryrun]\n' "$(basename "$0")"; dryrun_help; }

parse_arguments() {
    pa_count=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            dryrun|--dryrun) enable_dryrun ;;
            -h|--help) usage; exit 0 ;;
            --version) printf '%s %s (project %s)\n' "$(basename "$0")" "$SCRIPT_VERSION" "$PROJECT_VERSION"; exit 0 ;;
            *) pa_count=$((pa_count + 1)); case "$pa_count" in 1) IMAGE="$1" ;; 2) VMID="$1" ;; 3) STORAGE="$1" ;; 4) SLOT="$1" ;; *) usage >&2; exit 2 ;; esac ;;
        esac
        shift
    done
    [ "$pa_count" -ge 3 ] && [ "$pa_count" -le 4 ] || { usage >&2; exit 2; }
}

############################################################
# VALIDATION / PRE-FLIGHT
############################################################

# validate_import
# Validates input image, destination VM/storage/slot and records the pre-import unused-disk state.
validate_import() {
    [ -f "$IMAGE" ] || die "Image file does not exist: $IMAGE"
    require_qemu_vm "$VMID"; require_guest_stopped "$VMID"
    pvesm status --storage "$STORAGE" >/dev/null 2>&1 || die "Storage unavailable: $STORAGE"
    [ -n "$SLOT" ] || SLOT="$(first_free_scsi "$VMID")"
    [ -z "$(disk_value "$VMID" "$SLOT")" ] || die "$SLOT is already occupied."
    BEFORE_FILE="$(mktemp)" || die "Unable to create import state file."
    register_temp_file "$BEFORE_FILE"
    qm config "$VMID" | awk -F: '$1 ~ /^unused[0-9]+$/ {print $1 ":" $2}' > "$BEFORE_FILE"
}

############################################################
# HIGH LEVEL TASKS
############################################################

# import_disk
# Invokes qm importdisk after all import preflight has completed.
import_disk() {
    info "Importing $IMAGE into $STORAGE..."
    dryrun_cmd qm importdisk "$VMID" "$IMAGE" "$STORAGE"
}

# attach_imported_disk
#
# Description:
#   Identifies the newly-created unusedN entry, attaches that volume at the
#   requested SCSI slot, and removes the duplicate unusedN config reference.
#
# Usage:
#   attach_imported_disk
#
# Arguments:
#   Uses VMID, STORAGE, SLOT and BEFORE_FILE.
#
# Output:
#   Sets VOLID and UKEY.
#
# Returns:
#   0 after verified attachment; exits on ambiguity or verification failure.
############################################################
attach_imported_disk() {
    if dryrun_enabled; then
        UKEY="unusedN"; VOLID="${STORAGE}:<imported-volume>"
        dryrun_print_shell "qm set $(shell_quote "$VMID") --$(shell_quote "$SLOT") <volume-created-by-qm-importdisk>"
        dryrun_print_shell "qm set $(shell_quote "$VMID") --delete <unusedN-created-by-qm-importdisk>"
        dryrun_verify "Imported volume would be attached to $SLOT"
        ok "Imported and attached $VOLID as $SLOT."
        return 0
    fi

    AFTER_FILE="$(mktemp)" || die "Unable to create post-import state file."
    register_temp_file "$AFTER_FILE"
    qm config "$VMID" | awk -F: '$1 ~ /^unused[0-9]+$/ {print $1 ":" $2}' > "$AFTER_FILE"
    ai_new="$(
        while IFS= read -r ai_line; do
            grep -Fx "$ai_line" "$BEFORE_FILE" >/dev/null 2>&1 || printf '%s\n' "$ai_line"
        done < "$AFTER_FILE" | tail -n1
    )"
    [ -n "$ai_new" ] || die "Import finished but the new unused disk could not be identified."
    UKEY="${ai_new%%:*}"
    VOLID="$(disk_volid "$VMID" "$UKEY" || :)"; [ -n "$VOLID" ] || die "Could not resolve imported volume."
    qm set "$VMID" "--$SLOT" "$VOLID"
    [ "$(disk_volid "$VMID" "$SLOT")" = "$VOLID" ] || die "Attach verification failed."
    if qm config "$VMID" | grep -qE "^${UKEY}:"; then qm set "$VMID" --delete "$UKEY"; fi
    ok "Imported and attached $VOLID as $SLOT."
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
