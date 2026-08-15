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
    CREATED=0; COMPLETE=0
    parse_arguments "$@"
    check_elevation
}

main() {
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    need_commands lvs vgs lvcreate lvremove blockdev dmsetup findmnt readlink awk grep sed dd cmp mktemp
    validate_source_and_destination
    assert_not_mounted "$SOURCE_PATH" || die "Unmount the source LV before copying it."
    assert_not_in_use "$SOURCE_PATH"
    select_destination_allocation
    print_copy_plan
    trap cleanup_on_exit 0
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    create_destination
    copy_data
    verify_copy
    COMPLETE=1
}

end() {
    print_banner "LVM copy created successfully"
    printf 'Source:      %s\n' "$SOURCE_PATH"
    printf 'Destination: %s\n\n' "$DEST_PATH"
    dryrun_summary
}

############################################################
# COMMAND LINE
############################################################

usage() {
    cat <<EOF
copy-lvm.sh $SCRIPT_VERSION (project $PROJECT_VERSION)

USAGE
  copy-lvm.sh <source-lv-path> <destination-lv-path> [dryrun]

DESCRIPTION
  Creates a fully independent block-level copy. Both arguments are full LVM
  device paths. The destination must use /dev/<volume-group>/<new-lv-name>.

DESTINATION ALLOCATION
  same VG + thin source     use the source thin pool
  one thin pool in dest VG use that thin pool
  no thin pool in dest VG  create a regular LV
  multiple thin pools      refuse as ambiguous

EXAMPLES
  copy-lvm.sh /dev/thinvg/vm-123-disk-1 /dev/thinvg/vm-123-disk-1-copy
  copy-lvm.sh /dev/thinvg/vm-123-disk-1 /dev/fastvg/vm-123-disk-1

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
#
# Description:
#   Resolves source LVM metadata, parses the destination /dev/VG/LV path and
#   checks every collision before any destination object is created.
#
# Usage:
#   validate_source_and_destination
#
# Arguments:
#   Uses SOURCE and DESTINATION.
#
# Output:
#   Sets SOURCE_*, DEST_VG, DEST_LV and DEST_PATH.
#
# Returns:
#   0 when the copy can safely proceed.
############################################################
validate_source_and_destination() {
    case "$SOURCE" in /*) ;; *) die "Source must be a full absolute LVM device path." ;; esac
    case "$DESTINATION" in /dev/*/*) ;; *) die "Destination must use the form /dev/<volume-group>/<lv-name>." ;; esac

    lvs "$SOURCE" >/dev/null 2>&1 || die "Source is not an LVM logical volume: $SOURCE"
    SOURCE_PATH="$(lvs --noheadings -o lv_path "$SOURCE" 2>/dev/null | trim)"
    SOURCE_VG="$(lvs --noheadings -o vg_name "$SOURCE" 2>/dev/null | trim)"
    SOURCE_LV="$(lvs --noheadings -o lv_name "$SOURCE" 2>/dev/null | trim)"
    SOURCE_POOL="$(lvs --noheadings -o pool_lv "$SOURCE" 2>/dev/null | trim)"
    SOURCE_SIZE_BYTES="$(blockdev --getsize64 "$SOURCE_PATH")"
    SOURCE_REAL="$(readlink -f "$SOURCE_PATH")"

    vsd_rel="${DESTINATION#/dev/}"; DEST_VG="${vsd_rel%%/*}"; DEST_LV="${vsd_rel#*/}"
    case "$DEST_VG:$DEST_LV" in :*|*:|*:*/*) die "Destination must use the form /dev/<volume-group>/<lv-name>." ;; esac
    DEST_PATH="/dev/${DEST_VG}/${DEST_LV}"

    [ -n "$SOURCE_PATH" ] && [ -n "$SOURCE_VG" ] && [ -n "$SOURCE_LV" ] || die "Could not resolve the source LV."
    case "$SOURCE_SIZE_BYTES" in ''|*[!0-9]*) die "Could not determine source LV size." ;; esac
    [ "$SOURCE_SIZE_BYTES" -gt 0 ] || die "Could not determine source LV size."
    vgs "$DEST_VG" >/dev/null 2>&1 || die "Destination volume group does not exist: $DEST_VG"
    if [ "$SOURCE_VG" = "$DEST_VG" ] && [ "$SOURCE_LV" = "$DEST_LV" ]; then die "Source and destination refer to the same logical volume."; fi
    if lvs "${DEST_VG}/${DEST_LV}" >/dev/null 2>&1; then die "Destination logical volume already exists: $DEST_PATH"; fi
    [ ! -e "$DEST_PATH" ] || die "Destination path already exists: $DEST_PATH"
}

# assert_not_mounted LV
#
# Description:
#   Refuses direct mounts and mounted kpartx child mappings belonging to LV.
#
# Usage:
#   assert_not_mounted LV
#
# Arguments:
#   $1  Source LV path.
#
# Output:
#   Prints the conflicting mount when found.
#
# Returns:
#   0 when no mount is found; 1 otherwise.
############################################################
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
# Refuses a source with a nonzero device-mapper open count.
assert_not_in_use() {
    ani_real="$(readlink -f "$1")"
    ani_open="$(dmsetup info -c --noheadings -o open "$ani_real" 2>/dev/null | tr -d '[:space:]' || :)"
    case "$ani_open" in ''|*[!0-9]*) return 0 ;; esac
    [ "$ani_open" -eq 0 ] || die "Source LV is open/in use (device-mapper open count: $ani_open). Stop any VM/CT or process using it first."
}

# select_destination_allocation
# Selects regular/thin destination allocation and refuses multiple thin pools.
select_destination_allocation() {
    DEST_MODE="regular"; DEST_POOL=""
    if [ "$DEST_VG" = "$SOURCE_VG" ] && [ -n "$SOURCE_POOL" ]; then
        DEST_MODE="thin"; DEST_POOL="$SOURCE_POOL"; return 0
    fi
    sda_pools="$(lvs --noheadings -o lv_name,lv_attr "$DEST_VG" 2>/dev/null | awk '$2 ~ /^t/ {print $1}')"
    sda_count="$(printf '%s\n' "$sda_pools" | awk 'NF {n++} END {print n+0}')"
    case "$sda_count" in
        0) DEST_MODE="regular" ;;
        1) DEST_MODE="thin"; DEST_POOL="$(printf '%s\n' "$sda_pools" | awk 'NF {print; exit}')" ;;
        *) warn "Destination VG $DEST_VG contains multiple thin pools:"; printf '%s\n' "$sda_pools" | sed 's/^/  /' >&2; die "Destination is ambiguous; a /dev/VG/LV path does not identify which thin pool to use." ;;
    esac
}

############################################################
# HIGH LEVEL TASKS
############################################################

# print_copy_plan
# Prints resolved copy allocation, paths and source-stability requirements before mutation.
print_copy_plan() {
    print_banner "Copy LVM volume"
    printf 'Source:           %s\n' "$SOURCE_PATH"
    printf 'Destination:      %s\n' "$DEST_PATH"
    printf 'Size:             %s bytes\n' "$SOURCE_SIZE_BYTES"
    printf 'Destination VG:   %s\n' "$DEST_VG"
    printf 'Allocation:       %s\n' "$DEST_MODE"
    [ "$DEST_MODE" != "thin" ] || printf 'Thin pool:        %s\n' "$DEST_POOL"
    printf '\n'
    warn "The source must remain unchanged while the copy and verification run."
}

# create_destination
# Creates the planned LV and verifies its capacity.
create_destination() {
    info "Creating destination LV..."
    if [ "$DEST_MODE" = "thin" ]; then
        if dryrun_enabled; then dryrun_cmd lvcreate -V "${SOURCE_SIZE_BYTES}B" -T "${DEST_VG}/${DEST_POOL}" -n "$DEST_LV"
        else run_lvm_filtered lvcreate -V "${SOURCE_SIZE_BYTES}B" -T "${DEST_VG}/${DEST_POOL}" -n "$DEST_LV"; fi
    else
        if dryrun_enabled; then dryrun_cmd lvcreate -L "${SOURCE_SIZE_BYTES}B" -n "$DEST_LV" "$DEST_VG"
        else run_lvm_filtered lvcreate -L "${SOURCE_SIZE_BYTES}B" -n "$DEST_LV" "$DEST_VG"; fi
    fi
    CREATED=1
    if dryrun_enabled; then
        DEST_SIZE_BYTES="$SOURCE_SIZE_BYTES"; dryrun_verify "Destination LV would exist with sufficient size"
    else
        lvs "${DEST_VG}/${DEST_LV}" >/dev/null 2>&1 || die "lvcreate returned successfully, but the destination LV cannot be found."
        DEST_SIZE_BYTES="$(blockdev --getsize64 "$DEST_PATH")"
        [ "$DEST_SIZE_BYTES" -ge "$SOURCE_SIZE_BYTES" ] || die "Destination LV is smaller than the source."
    fi
}

# copy_data
# Copies source blocks using sparse writes only for newly created thin destinations.
copy_data() {
    info "Copying data..."
    if [ "$DEST_MODE" = "thin" ]; then dryrun_cmd dd if="$SOURCE_PATH" of="$DEST_PATH" bs=4M iflag=fullblock conv=sparse,fsync status=progress
    else dryrun_cmd dd if="$SOURCE_PATH" of="$DEST_PATH" bs=4M iflag=fullblock conv=fsync status=progress; fi
    ok "Copy completed."
}

# verify_copy
# Performs byte-for-byte comparison of the complete source-size range.
verify_copy() {
    info "Verifying copied data..."
    if dryrun_enabled; then dryrun_verify "cmp would verify $SOURCE_SIZE_BYTES bytes"
    elif ! cmp -n "$SOURCE_SIZE_BYTES" "$SOURCE_PATH" "$DEST_PATH"; then die "Block verification failed; the destination copy does not match the source."; fi
    ok "Verification passed."
}

############################################################
# ERROR HANDLING / CLEANUP
############################################################

# cleanup_on_exit
#
# Description:
#   Removes only an incomplete destination LV created by this invocation.
#   A completed verified copy is never removed.
#
# Usage:
#   Installed as the process exit/signal trap.
#
# Arguments:
#   None.
#
# Output:
#   May remove DEST_VG/DEST_LV after a failed partial transaction.
#
# Returns:
#   Preserves normal completion; signal paths exit nonzero.
############################################################
cleanup_on_exit() {
    coe_status=$?
    trap - 0 HUP INT TERM
    if dryrun_enabled || [ "$CREATED" -eq 0 ] || [ "$COMPLETE" -eq 1 ]; then
        [ "$coe_status" -eq 0 ] || exit "$coe_status"
        return 0
    fi
    warn "Removing incomplete destination LV: $DEST_PATH"
    set +e
    lvremove -y "${DEST_VG}/${DEST_LV}" >/dev/null 2>&1 || warn "Could not remove $DEST_PATH automatically."
    set -e
    [ "$coe_status" -eq 0 ] || exit "$coe_status"
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
