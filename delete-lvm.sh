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
    PROJECT_VERSION="3.0.1"; SCRIPT_VERSION="3.0.1"
    parse_arguments "$@"
    check_elevation
}

main() {
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    ensure_lvm_tools
    validate_volume
    print_volume
    confirm_delete
    delete_volume
}

end() { dryrun_summary; }

############################################################
# COMMAND LINE
############################################################

usage() {
    cat <<EOF
delete-lvm.sh $SCRIPT_VERSION (project $PROJECT_VERSION)

USAGE
  delete-lvm.sh <lvm-volume-path> [dryrun]

EXAMPLE
  delete-lvm.sh /dev/thinvg/vm-123-disk-1-copy

LIST VOLUMES
  lvs --noheadings -o lv_path | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'

EOF
    dryrun_help
}

parse_arguments() {
    pa_count=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            dryrun|--dryrun) enable_dryrun ;;
            -h|--help) usage; exit 0 ;;
            --version) printf '%s %s (project %s)\n' "$(basename "$0")" "$SCRIPT_VERSION" "$PROJECT_VERSION"; exit 0 ;;
            *) pa_count=$((pa_count + 1)); [ "$pa_count" -eq 1 ] && DEVICE="$1" || { usage >&2; exit 2; } ;;
        esac
        shift
    done
    [ "$pa_count" -eq 1 ] || { usage >&2; exit 2; }
}

############################################################
# DEPENDENCIES
############################################################

# ensure_lvm_tools
# Installs lvm2 only when the required LVM commands are unavailable.
ensure_lvm_tools() {
    command -v lvs >/dev/null 2>&1 && command -v lvremove >/dev/null 2>&1 && return 0
    need_commands apt-get
    warn "LVM tools are not installed; installing lvm2."
    export DEBIAN_FRONTEND=noninteractive
    dryrun_cmd apt-get update
    dryrun_cmd apt-get install -y lvm2
    if dryrun_enabled; then die "LVM tools are required for read-only preflight; install lvm2 before using dryrun on this host."; fi
    need_commands lvs lvremove
}

############################################################
# VALIDATION / PRE-FLIGHT
############################################################

# validate_volume
# Resolves LV metadata and refuses a directly mounted logical volume.
validate_volume() {
    lvs "$DEVICE" >/dev/null 2>&1 || die "Not an LVM logical volume: $DEVICE"
    LV_PATH="$(lvs --noheadings -o lv_path "$DEVICE" | trim)"
    LV_NAME="$(lvs --noheadings -o lv_name "$DEVICE" | trim)"
    VG_NAME="$(lvs --noheadings -o vg_name "$DEVICE" | trim)"
    LV_SIZE="$(lvs --noheadings -o lv_size "$DEVICE" | trim)"
    POOL_NAME="$(lvs --noheadings -o pool_lv "$DEVICE" | trim)"
    ORIGIN="$(lvs --noheadings -o origin "$DEVICE" | trim)"
    LV_ATTR="$(lvs --noheadings -o lv_attr "$DEVICE" | trim)"

    if command -v findmnt >/dev/null 2>&1; then
        vv_real="$(readlink -f "$LV_PATH")"
        if findmnt -rn -S "$LV_PATH" >/dev/null 2>&1 || findmnt -rn -S "$vv_real" >/dev/null 2>&1; then
            warn "Logical volume is currently mounted:"
            findmnt -S "$LV_PATH" 2>/dev/null || :
            findmnt -S "$vv_real" 2>/dev/null || :
            die "Unmount it before deleting it."
        fi
    fi
}

############################################################
# HIGH LEVEL TASKS
############################################################

# print_volume
# Prints the exact LV metadata and destructive-operation warning before confirmation.
print_volume() {
    printf '\nLogical volume to delete:\n\n'
    printf '  Path:         %s\n' "$LV_PATH"
    printf '  Volume group: %s\n' "$VG_NAME"
    printf '  LV name:      %s\n' "$LV_NAME"
    printf '  Size:         %s\n' "$LV_SIZE"
    printf '  Attributes:   %s\n' "$LV_ATTR"
    [ -z "$POOL_NAME" ] || printf '  Thin pool:    %s\n' "$POOL_NAME"
    if [ -n "$ORIGIN" ]; then printf '  Origin:       %s\n\n  This LV is a snapshot / linked copy.\n' "$ORIGIN"; fi
    printf '\n'
    warn "This will permanently delete:"
    printf '\n    %s\n\n  This operation cannot be undone.\n\n' "$LV_PATH"
}

# confirm_delete
# Requires the exact DELETE token, or simulates that confirmation during dry-run.
confirm_delete() {
    if dryrun_enabled; then CONFIRM="DELETE"; dryrun_print_shell "confirmation: Type DELETE to confirm  # simulated"
    else printf 'Type DELETE to confirm: '; IFS= read -r CONFIRM || CONFIRM=""; fi
    if [ "$CONFIRM" != "DELETE" ]; then printf '\nCancelled.\n'; exit 0; fi
}

# delete_volume
# Deletes the selected LV and verifies it no longer exists.
delete_volume() {
    printf '\n'; info "Deleting logical volume..."; printf '\n'
    dryrun_cmd lvremove -y "$LV_PATH"
    if dryrun_enabled; then dryrun_verify "$LV_PATH would no longer exist"
    else
        if lvs "$VG_NAME/$LV_NAME" >/dev/null 2>&1; then die "Logical volume still exists after lvremove: $LV_PATH"; fi
    fi
    printf '\n--------------------------------------------------\n'
    ok "Logical volume deleted successfully"
    printf '%s\n\nDeleted: %s\n\n' '--------------------------------------------------' "$LV_PATH"
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
