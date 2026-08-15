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
    ARG1=""; ARG2=""; ARG3=""
    parse_arguments "$@"
    check_elevation
}

main() {
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    need_commands lvs lvrename findmnt readlink
    resolve_arguments
    validate_rename
    check_mounts
    perform_rename
}

end() { dryrun_summary; }

############################################################
# COMMAND LINE
############################################################

usage() {
    cat <<EOF
rename-lvm.sh $SCRIPT_VERSION (project $PROJECT_VERSION)

USAGE
  rename-lvm.sh <source-lv-path> <new-name> [dryrun]
  rename-lvm.sh <volume-group> <old-name> <new-name> [dryrun]

EXAMPLES
  rename-lvm.sh /dev/thinvg/vm-123-disk-1 vm-123-disk-1-old
  rename-lvm.sh thinvg vm-123-disk-1 vm-123-disk-1-old

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
            *) pa_count=$((pa_count + 1)); case "$pa_count" in 1) ARG1="$1" ;; 2) ARG2="$1" ;; 3) ARG3="$1" ;; *) usage >&2; exit 2 ;; esac ;;
        esac
        shift
    done
    [ "$pa_count" -eq 2 ] || [ "$pa_count" -eq 3 ] || { usage >&2; exit 2; }
    ARG_COUNT="$pa_count"
}

############################################################
# VALIDATION / PRE-FLIGHT
############################################################

# resolve_arguments
# Normalizes the supported rename CLI forms into VG/old-name/new-name state.
resolve_arguments() {
    if [ "$ARG_COUNT" -eq 2 ]; then
        SOURCE="$ARG1"; NEW_NAME="$ARG2"
        lvs "$SOURCE" >/dev/null 2>&1 || die "Logical volume does not exist: $SOURCE"
        VG_NAME="$(lvs --noheadings -o vg_name "$SOURCE" 2>/dev/null | trim)"
        OLD_NAME="$(lvs --noheadings -o lv_name "$SOURCE" 2>/dev/null | trim)"
    else
        VG_NAME="$ARG1"; OLD_NAME="$ARG2"; NEW_NAME="$ARG3"; SOURCE="$VG_NAME/$OLD_NAME"
        lvs "$SOURCE" >/dev/null 2>&1 || die "Logical volume does not exist: /dev/$VG_NAME/$OLD_NAME"
    fi
}

# validate_rename
# Validates LV identity, new-name syntax and destination collision state.
validate_rename() {
    [ -n "$VG_NAME" ] || die "Could not determine volume group."
    [ -n "$OLD_NAME" ] || die "Could not determine old LV name."
    [ -n "$NEW_NAME" ] || die "New LV name cannot be empty."
    case "$NEW_NAME" in */*) die "New name must be an LV name only, not a path." ;; esac
    [ "$OLD_NAME" != "$NEW_NAME" ] || die "Old and new LV names are identical."
    OLD_PATH="$(lvs --noheadings -o lv_path "$VG_NAME/$OLD_NAME" 2>/dev/null | trim)"
    [ -n "$OLD_PATH" ] || die "Could not determine LV path."
    REAL_SOURCE="$(readlink -f "$OLD_PATH")"; NEW_PATH="/dev/$VG_NAME/$NEW_NAME"
    if lvs "$VG_NAME/$NEW_NAME" >/dev/null 2>&1; then die "Destination logical volume already exists: $NEW_PATH"; fi
    return 0
}

# check_mounts
# Refuses the LV or any kpartx child partition that is currently mounted.
check_mounts() {
    if findmnt -rn -S "$OLD_PATH" >/dev/null 2>&1 || findmnt -rn -S "$REAL_SOURCE" >/dev/null 2>&1; then
        warn "Logical volume is mounted:"
        findmnt -S "$OLD_PATH" 2>/dev/null || :
        findmnt -S "$REAL_SOURCE" 2>/dev/null || :
        die "Unmount the volume before renaming it."
    fi
    command -v kpartx >/dev/null 2>&1 || return 0
    cm_maps="$(kpartx -l "$OLD_PATH" 2>/dev/null | awk '{print $1}' || :)"
    for cm_map in $cm_maps; do
        cm_node="/dev/mapper/$cm_map"
        if findmnt -rn -S "$cm_node" >/dev/null 2>&1; then
            warn "Partition belonging to the LV is mounted: $cm_node"
            findmnt -S "$cm_node" 2>/dev/null || :
            die "Unmount the volume before renaming it."
        fi
    done
}

############################################################
# HIGH LEVEL TASKS
############################################################

# perform_rename
# Executes lvrename and verifies the new LV path.
perform_rename() {
    printf 'Volume group: %s\nCurrent LV: %s\nNew LV: %s\n\n' "$VG_NAME" "$OLD_PATH" "$NEW_PATH"
    dryrun_cmd lvrename "$VG_NAME" "$OLD_NAME" "$NEW_NAME"
    if dryrun_enabled; then FINAL_PATH="$NEW_PATH"; dryrun_verify "New LV name would exist"
    else
        lvs "$VG_NAME/$NEW_NAME" >/dev/null 2>&1 || die "lvrename completed, but the new LV could not be found."
        FINAL_PATH="$(lvs --noheadings -o lv_path "$VG_NAME/$NEW_NAME" 2>/dev/null | trim)"
    fi
    printf '\n'; ok "Renamed successfully:"
    printf '\n  %s\n    ->\n  %s\n' "$OLD_PATH" "$FINAL_PATH"
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
