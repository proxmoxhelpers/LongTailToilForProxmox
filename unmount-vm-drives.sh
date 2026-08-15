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
    CLEANUP_ROOTS_FILE=""; UNMOUNT_FAILED=0; MAPS=""
    parse_arguments "$@"
    check_elevation
}

main() {
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    install_temp_cleanup
    install_dependencies
    validate_device
    CLEANUP_ROOTS_FILE="$(mktemp)" || die "Unable to create cleanup-root list."
    register_temp_file "$CLEANUP_ROOTS_FILE"
    print_configuration
    collect_maps
    unmount_all_sources
    verify_unmounted
    remove_mappings
    remove_cleanup_roots
}

end() {
    [ -z "$CLEANUP_ROOTS_FILE" ] || rm -f "$CLEANUP_ROOTS_FILE"
    printf '\nDone.\n'
    dryrun_summary
}

############################################################
# COMMAND LINE
############################################################

usage() {
    cat <<EOF
unmount-vm-drives.sh $SCRIPT_VERSION (project $PROJECT_VERSION)

USAGE
  unmount-vm-drives.sh <lvm-volume-path> [dryrun]

EXAMPLE
  unmount-vm-drives.sh /dev/thinvg/vm-123-disk-1

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

# install_dependencies
# Installs only missing mount/unmount dependencies and verifies the required command set.
install_dependencies() {
    id_need_kpartx=false; id_need_util=false
    command -v kpartx >/dev/null 2>&1 || id_need_kpartx=true
    command -v findmnt >/dev/null 2>&1 || id_need_util=true
    if [ "$id_need_kpartx" = true ] || [ "$id_need_util" = true ]; then
        need_commands apt-get
        id_packages=""
        [ "$id_need_kpartx" = false ] || id_packages="kpartx"
        [ "$id_need_util" = false ] || id_packages="${id_packages}${id_packages:+ }util-linux"
        info "Installing required package(s): $id_packages"
        export DEBIAN_FRONTEND=noninteractive
        dryrun_cmd apt-get update
        if dryrun_enabled; then dryrun_print_shell "apt-get install -y $id_packages"
        else apt-get install -y $id_packages; fi
    fi
    if dryrun_enabled; then
        command -v kpartx >/dev/null 2>&1 || die "Dry-run preflight requires kpartx to already be installed."
        command -v findmnt >/dev/null 2>&1 || die "Dry-run preflight requires findmnt to already be installed."
    fi
    need_commands kpartx findmnt readlink find mktemp awk
}

############################################################
# VALIDATION / PRE-FLIGHT
############################################################

# validate_device
# Validates the requested block device and resolves canonical path/default mount settings.
validate_device() {
    [ -b "$DEVICE" ] || die "Not a block device: $DEVICE"
    DEVICE_REAL="$(readlink -f "$DEVICE")"
}

# print_configuration
# Prints the resolved device/mount configuration before filesystem operations.
print_configuration() {
    printf 'LVM volume:      %s\n' "$DEVICE"
    printf 'Resolved device: %s\n\n' "$DEVICE_REAL"
}

############################################################
# MOUNT / CLEANUP HELPERS
############################################################

get_maps() { kpartx -l "$DEVICE" 2>/dev/null | awk '{print $1}'; }

# add_cleanup_root TARGET
# Records a unique parent only for project-generated partN mount directories.
add_cleanup_root() {
    acr_target="$1"; acr_base="$(basename "$acr_target")"
    printf '%s\n' "$acr_base" | grep -qE '^part[0-9]+$' || return 0
    acr_parent="$(dirname "$acr_target")"
    grep -Fx "$acr_parent" "$CLEANUP_ROOTS_FILE" >/dev/null 2>&1 || printf '%s\n' "$acr_parent" >> "$CLEANUP_ROOTS_FILE"
}

# remove_folder_if_empty TARGET
# Removes only an empty mount directory and lists contents otherwise.
remove_folder_if_empty() {
    rfe_target="$1"; [ -d "$rfe_target" ] || return 0
    if [ -n "$(find "$rfe_target" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
        printf '  Folder NOT removed because it contains files: %s\n\n  Contents:\n' "$rfe_target"
        find "$rfe_target" -mindepth 1 -maxdepth 1 -printf '    %f\n' 2>/dev/null || :
        return 0
    fi
    if dryrun_cmd rmdir "$rfe_target"; then
        printf '  Removed empty folder: %s\n' "$rfe_target"
        if dryrun_enabled; then dryrun_verify "$rfe_target would be removed only if empty"; fi
    else
        printf '  Folder was not removed: %s\n' "$rfe_target"
    fi
}

# unmount_source SOURCE
#
# Description:
#   Finds every mount using SOURCE, unmounts each exact target, records eligible
#   parent roots, and removes only now-empty partN directories.
#
# Usage:
#   unmount_source SOURCE
#
# Arguments:
#   $1 source device or alias.
#
# Output:
#   May set UNMOUNT_FAILED=1.
#
# Returns:
#   0; individual failures are accumulated for transaction-level refusal.
############################################################
unmount_source() {
    us_source="$1"; us_targets="$(mktemp)" || die "Unable to create mount-target list."
    register_temp_file "$us_targets"
    findmnt -rn -S "$us_source" -o TARGET 2>/dev/null > "$us_targets" || :
    while IFS= read -r us_target; do
        [ -n "$us_target" ] || continue
        printf 'Source: %s\nMounted at: %s\n\n' "$us_source" "$us_target"
        add_cleanup_root "$us_target"
        if ! dryrun_cmd umount "$us_target"; then
            warn "Failed to unmount: $us_target"
            UNMOUNT_FAILED=1
            continue
        fi
        ok "Unmounted successfully."
        if dryrun_enabled; then dryrun_verify "$us_target would no longer be mounted"; fi
        remove_folder_if_empty "$us_target"
        printf '\n'
    done < "$us_targets"
    rm -f "$us_targets"
}

############################################################
# HIGH LEVEL TASKS
############################################################

# collect_maps
# Discovers current kpartx mappings for the selected LV.
collect_maps() {
    MAPS="$(get_maps || :)"
    cm_count="$(printf '%s\n' "$MAPS" | awk 'NF {n++} END {print n+0}')"
    if [ "$cm_count" -gt 0 ]; then printf 'Found %s partition mapping(s).\n\n' "$cm_count"; fi
}

# unmount_all_sources
# Unmounts mapper children in reverse order and the raw LV aliases, accumulating any failures.
unmount_all_sources() {
    uas_reverse="$(printf '%s\n' "$MAPS" | awk 'NF {a[++n]=$0} END {for(i=n;i>=1;i--) print a[i]}')"
    for uas_map in $uas_reverse; do unmount_source "/dev/mapper/$uas_map"; done
    unmount_source "$DEVICE_REAL"
    [ "$DEVICE_REAL" = "$DEVICE" ] || unmount_source "$DEVICE"
    if [ "$UNMOUNT_FAILED" -ne 0 ]; then
        printf 'One or more filesystems could not be unmounted.\nkpartx mappings and parent folders are being left in place.\n' >&2
        exit 1
    fi
}

# verify_unmounted
# Requires all selected mounts absent before mapper teardown.
verify_unmounted() {
    if dryrun_enabled; then dryrun_verify "All selected partition/LV mounts would be absent before mapper cleanup"; return 0; fi
    for vu_map in $MAPS; do
        vu_node="/dev/mapper/$vu_map"
        if findmnt -rn -S "$vu_node" >/dev/null 2>&1; then die "$vu_node is still mounted; refusing to continue cleanup."; fi
    done
    if findmnt -rn -S "$DEVICE_REAL" >/dev/null 2>&1; then die "$DEVICE_REAL is still mounted."; fi
    return 0
}

# remove_mappings
# Removes kpartx mappings only after unmount verification succeeds.
remove_mappings() {
    [ -n "$MAPS" ] || return 0
    info "Removing partition device mappings..."
    printf '\n'
    dryrun_cmd kpartx -dv "$DEVICE"
    command -v udevadm >/dev/null 2>&1 && udevadm settle || :
}

# remove_cleanup_roots
# Removes only empty recorded mount roots after all child mounts are gone.
remove_cleanup_roots() {
    [ -s "$CLEANUP_ROOTS_FILE" ] || return 0
    printf '\nCleaning up empty mount-root folders...\n\n'
    while IFS= read -r rcr_root; do
        [ -d "$rcr_root" ] || continue
        if [ -n "$(find "$rcr_root" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
            printf 'Mount root NOT removed because it contains files: %s\n\nContents:\n' "$rcr_root"
            find "$rcr_root" -mindepth 1 -maxdepth 1 -printf '  %f\n' 2>/dev/null || :
            printf '\n'
            continue
        fi
        if dryrun_cmd rmdir "$rcr_root"; then
            printf 'Removed empty mount root: %s\n' "$rcr_root"
            if dryrun_enabled; then dryrun_verify "$rcr_root would be removed only if empty"; fi
        else
            printf 'Could not remove mount root: %s\n' "$rcr_root"
        fi
    done < "$CLEANUP_ROOTS_FILE"
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
