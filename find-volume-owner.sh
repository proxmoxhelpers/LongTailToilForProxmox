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
}

main() {
    need_commands pvesm lvs readlink awk
    resolve_target
    find_owners
}

end() { dryrun_summary; }

############################################################
# COMMAND LINE
############################################################

usage() { printf 'Usage: %s <full-lv-path|storage:volume> [dryrun]\n' "$(basename "$0")"; dryrun_help; }

parse_arguments() {
    pa_count=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            dryrun|--dryrun) enable_dryrun ;;
            -h|--help) usage; exit 0 ;;
            --version) printf '%s %s (project %s)\n' "$(basename "$0")" "$SCRIPT_VERSION" "$PROJECT_VERSION"; exit 0 ;;
            *) pa_count=$((pa_count + 1)); [ "$pa_count" -eq 1 ] && INPUT="$1" || { usage >&2; exit 2; } ;;
        esac
        shift
    done
    [ "$pa_count" -eq 1 ] || { usage >&2; exit 2; }
}

############################################################
# HIGH LEVEL TASKS
############################################################

# resolve_target
# Resolves INPUT to one canonical block-device identity.
resolve_target() {
    case "$INPUT" in
        /dev/*) assert_lv_exists "$INPUT"; TARGET_PATH="$(canonical_lv_path "$INPUT")" ;;
        *) TARGET_PATH="$(pvesm path "$INPUT" 2>/dev/null || :)"; [ -n "$TARGET_PATH" ] || die "Proxmox cannot resolve volume ID: $INPUT" ;;
    esac
    TARGET_REAL="$(readlink -f "$TARGET_PATH" 2>/dev/null || :)"
    [ -n "$TARGET_REAL" ] || die "Could not resolve the underlying device for: $INPUT"
}

# find_owners
# Resolves every configured volume and prints references to TARGET_REAL.
find_owners() {
    FOUND=0
    gvr_file="$(mktemp)" || die "Unable to create temporary reference file."
    trap 'rm -f "$gvr_file"' 0 HUP INT TERM
    guest_volume_references > "$gvr_file"
    while IFS='|' read -r fo_cfg fo_slot fo_volid; do
        [ -n "$fo_volid" ] || continue
        fo_path="$(pvesm path "$fo_volid" 2>/dev/null || :)"; [ -n "$fo_path" ] || continue
        fo_real="$(readlink -f "$fo_path" 2>/dev/null || :)"
        [ "$fo_real" = "$TARGET_REAL" ] || continue
        FOUND=1
        printf '%s: %s: %s -> %s\n' "$fo_cfg" "$fo_slot" "$fo_volid" "$fo_path"
    done < "$gvr_file"
    [ "$FOUND" -eq 1 ] || warn "No VM/CT configuration references $INPUT."
    rm -f "$gvr_file"; trap - 0 HUP INT TERM
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
