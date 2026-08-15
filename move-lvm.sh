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
    MOVE_ACTION="moved"
    parse_arguments "$@"
    check_elevation
}

main() {
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    need_commands lvs vgs lvrename lvremove dmsetup findmnt readlink awk grep sed
    validate_source_and_destination
    assert_not_mounted "$SOURCE_PATH" || die "Unmount the source LV before moving it."
    assert_not_in_use "$SOURCE_PATH"
    print_move_plan
    if [ "$SOURCE_VG" = "$DEST_VG" ]; then rename_in_place
    else move_across_vgs; fi
}

end() {
    if [ "$MOVE_ACTION" = "renamed" ]; then print_banner "LVM volume renamed successfully"
    else print_banner "LVM volume moved successfully"; fi
    printf 'Old path: %s\n' "$SOURCE_PATH"
    printf 'New path: %s\n\n' "$DEST_PATH"
    dryrun_summary
}

############################################################
# COMMAND LINE
############################################################

usage() {
    cat <<EOF
move-lvm.sh $SCRIPT_VERSION (project $PROJECT_VERSION)

USAGE
  move-lvm.sh <source-lv-path> <destination-lv-path> [dryrun]

DESCRIPTION
  Same-VG moves use lvrename in place. Cross-VG moves create and verify an
  independent copy first, then remove the source only after verification.

EXAMPLES
  move-lvm.sh /dev/thinvg/vm-123-disk-1 /dev/thinvg/vm-123-disk-1-old
  move-lvm.sh /dev/thinvg/vm-123-disk-1 /dev/fastvg/vm-123-disk-1

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
            *) pa_count=$((pa_count + 1)); case "$pa_count" in 1) SOURCE="$1" ;; 2) DESTINATION="$1" ;; *) usage >&2; exit 2 ;; esac ;;
        esac
        shift
    done
    [ "$pa_count" -eq 2 ] || { usage >&2; exit 2; }
}

############################################################
# VALIDATION / PRE-FLIGHT
############################################################

# validate_source_and_destination
# Resolves source/destination LV identities and rejects all destination collisions before mutation.
validate_source_and_destination() {
    case "$SOURCE" in /*) ;; *) die "Source must be a full absolute LVM device path." ;; esac
    case "$DESTINATION" in /dev/*/*) ;; *) die "Destination must use the form /dev/<volume-group>/<lv-name>." ;; esac
    lvs "$SOURCE" >/dev/null 2>&1 || die "Source is not an LVM logical volume: $SOURCE"

    SOURCE_PATH="$(lvs --noheadings -o lv_path "$SOURCE" 2>/dev/null | trim)"
    SOURCE_VG="$(lvs --noheadings -o vg_name "$SOURCE" 2>/dev/null | trim)"
    SOURCE_LV="$(lvs --noheadings -o lv_name "$SOURCE" 2>/dev/null | trim)"
    SOURCE_REAL="$(readlink -f "$SOURCE_PATH")"

    vsd_rel="${DESTINATION#/dev/}"; DEST_VG="${vsd_rel%%/*}"; DEST_LV="${vsd_rel#*/}"
    case "$DEST_VG:$DEST_LV" in :*|*:|*:*/*) die "Destination must use the form /dev/<volume-group>/<lv-name>." ;; esac
    DEST_PATH="/dev/${DEST_VG}/${DEST_LV}"

    [ -n "$SOURCE_PATH" ] && [ -n "$SOURCE_VG" ] && [ -n "$SOURCE_LV" ] || die "Could not resolve the source LV."
    vgs "$DEST_VG" >/dev/null 2>&1 || die "Destination volume group does not exist: $DEST_VG"
    if [ "$SOURCE_VG" = "$DEST_VG" ] && [ "$SOURCE_LV" = "$DEST_LV" ]; then die "Source and destination refer to the same logical volume."; fi
    if lvs "${DEST_VG}/${DEST_LV}" >/dev/null 2>&1; then die "Destination logical volume already exists: $DEST_PATH"; fi
    [ ! -e "$DEST_PATH" ] || die "Destination path already exists: $DEST_PATH"
}

# assert_not_mounted LV
# Refuses direct source mounts and mounted kpartx children.
assert_not_mounted() (
    anm_path="$1"; anm_real="$(readlink -f "$anm_path")"
    if findmnt -rn -S "$anm_path" >/dev/null 2>&1 || findmnt -rn -S "$anm_real" >/dev/null 2>&1; then
        warn "Source LV is mounted:"
        findmnt -S "$anm_path" 2>/dev/null || :
        findmnt -S "$anm_real" 2>/dev/null || :
        exit 1
    fi
    command -v kpartx >/dev/null 2>&1 || exit 0
    anm_maps="$(kpartx -l "$anm_path" 2>/dev/null || :)"
    [ -n "$anm_maps" ] || exit 0
    printf '%s\n' "$anm_maps" | while IFS=' ' read -r anm_map anm_rest; do
        [ -n "$anm_map" ] || continue
        anm_node="/dev/mapper/$anm_map"
        if findmnt -rn -S "$anm_node" >/dev/null 2>&1; then
            warn "A partition belonging to the source LV is mounted: $anm_node"
            findmnt -S "$anm_node" 2>/dev/null || :
            exit 1
        fi
    done
)

# assert_not_in_use LV
# Refuses a nonzero device-mapper open count.
assert_not_in_use() {
    ani_real="$(readlink -f "$1")"
    ani_open="$(dmsetup info -c --noheadings -o open "$ani_real" 2>/dev/null | tr -d '[:space:]' || :)"
    case "$ani_open" in ''|*[!0-9]*) return 0 ;; esac
    [ "$ani_open" -eq 0 ] || die "Source LV is open/in use (device-mapper open count: $ani_open). Stop any VM/CT or process using it first."
}

# validate_no_dependents
# Refuses cross-VG deletion when source is an origin for dependent LVs.
validate_no_dependents() {
    vnd_dependents="$(lvs --noheadings -o lv_name,origin "$SOURCE_VG" 2>/dev/null | awk -v origin="$SOURCE_LV" '$2 == origin {print $1}')"
    if [ -n "$vnd_dependents" ]; then
        warn "The source LV is an origin for other LVs/snapshots:"
        printf '%s\n' "$vnd_dependents" | sed 's/^/  /' >&2
        die "Refusing a cross-VG move because deleting the source origin could affect dependent snapshots."
    fi
}

############################################################
# HIGH LEVEL TASKS
############################################################

# print_move_plan
# Prints the exact source and destination paths before the move transaction.
print_move_plan() {
    print_banner "Move LVM volume"
    printf 'Source:      %s\n' "$SOURCE_PATH"
    printf 'Destination: %s\n\n' "$DEST_PATH"
}

# rename_in_place
# Performs and verifies a same-VG LV rename without copying data.
rename_in_place() {
    MOVE_ACTION="renamed"
    info "Same volume group detected; renaming the LV in place..."
    dryrun_cmd lvrename "$SOURCE_VG" "$SOURCE_LV" "$DEST_LV"
    if dryrun_enabled; then dryrun_verify "New LV name would exist and old LV name would be absent"
    else
        lvs "${DEST_VG}/${DEST_LV}" >/dev/null 2>&1 || die "lvrename completed, but the destination LV cannot be found."
        if lvs "${SOURCE_VG}/${SOURCE_LV}" >/dev/null 2>&1; then die "Old LV name still exists after rename."; fi
    fi
}

# move_across_vgs
#
# Description:
#   Delegates the verified independent copy to copy-lvm.sh, checks both source
#   and destination after that transaction, then removes the source.
#
# Usage:
#   move_across_vgs
#
# Arguments:
#   Uses resolved source/destination state.
#
# Output:
#   Destination survives any source-removal failure.
#
# Returns:
#   0 only after source removal is verified.
############################################################
move_across_vgs() {
    validate_no_dependents
    mav_copy="$SCRIPT_DIR/copy-lvm.sh"; [ -f "$mav_copy" ] || die "Required companion script not found: $mav_copy"
    info "Different volume groups detected; creating and verifying an independent copy first..."
    if dryrun_enabled; then /bin/sh "$mav_copy" "$SOURCE_PATH" "$DEST_PATH" dryrun
    else /bin/sh "$mav_copy" "$SOURCE_PATH" "$DEST_PATH"; fi

    if dryrun_enabled; then
        dryrun_verify "Destination copy would exist while source remains present"
    else
        lvs "${DEST_VG}/${DEST_LV}" >/dev/null 2>&1 || die "Destination LV is missing after copy."
        lvs "${SOURCE_VG}/${SOURCE_LV}" >/dev/null 2>&1 || die "Source LV disappeared unexpectedly before removal."
    fi

    info "Verified copy exists. Removing source LV..."
    if ! dryrun_cmd lvremove -y "$SOURCE_PATH"; then
        warn "The destination copy has been preserved at $DEST_PATH."
        die "Could not remove the source LV."
    fi
    if dryrun_enabled; then dryrun_verify "Source LV would be removed after verified copy"
    elif lvs "${SOURCE_VG}/${SOURCE_LV}" >/dev/null 2>&1; then
        warn "The destination copy has been preserved at $DEST_PATH."
        die "Source LV still exists after lvremove."
    fi
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
