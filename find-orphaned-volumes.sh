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
    VG=""
    parse_arguments "$@"
}

main() {
    need_commands lvs pvesm readlink awk sort mktemp
    build_reference_index
    list_orphans
}

end() { dryrun_summary; }

############################################################
# COMMAND LINE
############################################################

usage() { printf 'Usage: %s [volume-group] [dryrun]\n' "$(basename "$0")"; dryrun_help; }

parse_arguments() {
    pa_count=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            dryrun|--dryrun) enable_dryrun ;;
            -h|--help) usage; exit 0 ;;
            --version) printf '%s %s (project %s)\n' "$(basename "$0")" "$SCRIPT_VERSION" "$PROJECT_VERSION"; exit 0 ;;
            *) pa_count=$((pa_count + 1)); [ "$pa_count" -eq 1 ] && VG="$1" || { usage >&2; exit 2; } ;;
        esac
        shift
    done
}

############################################################
# HIGH LEVEL TASKS
############################################################

# build_reference_index
#
# Description:
#   Resolves configured Proxmox volumes once and records canonical block
#   device paths. This avoids name-only ownership matches across storages.
#
# Usage:
#   build_reference_index
#
# Arguments:
#   None.
#
# Output:
#   Sets REFERENCE_FILE to a temporary file containing canonical paths.
#
# Returns:
#   0 on success.
############################################################
build_reference_index() {
    REFERENCE_FILE="$(mktemp)" || die "Unable to create reference index."
    trap 'rm -f "$REFERENCE_FILE"' 0 HUP INT TERM
    guest_volume_references | while IFS='|' read -r bri_cfg bri_slot bri_volid; do
        [ -n "$bri_volid" ] || continue
        bri_path="$(pvesm path "$bri_volid" 2>/dev/null || :)"; [ -n "$bri_path" ] || continue
        bri_real="$(readlink -f "$bri_path" 2>/dev/null || :)"; [ -n "$bri_real" ] || continue
        printf '%s\n' "$bri_real"
    done | sort -u > "$REFERENCE_FILE"
}

# list_orphans
# Lists vm-N-disk-M LVs whose canonical path is absent from the reference index.
list_orphans() {
    printf '%-36s %-12s %s\n' LV_PATH SIZE STATUS
    if [ -n "$VG" ]; then lvs --noheadings --separator '|' -o lv_path,lv_name,lv_size "$VG"
    else lvs --noheadings --separator '|' -o lv_path,lv_name,lv_size; fi |
    while IFS='|' read -r lo_path lo_name lo_size; do
        lo_path="$(printf '%s' "$lo_path" | trim)"; lo_name="$(printf '%s' "$lo_name" | trim)"; lo_size="$(printf '%s' "$lo_size" | trim)"
        printf '%s\n' "$lo_name" | grep -qE '^vm-[0-9]+-disk-[0-9]+$' || continue
        lo_real="$(readlink -f "$lo_path" 2>/dev/null || :)"; [ -n "$lo_real" ] || continue
        grep -Fx "$lo_real" "$REFERENCE_FILE" >/dev/null 2>&1 || printf '%-36s %-12s %s\n' "$lo_path" "$lo_size" ORPHAN
    done
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
