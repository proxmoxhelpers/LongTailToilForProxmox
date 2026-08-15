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
    MOUNT_ROOT=""; MODE="--ro"; KPARTX_STATUS=0
    parse_arguments "$@"
    check_elevation
}

main() {
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    install_dependencies
    validate_device
    prepare_mount_root
    print_configuration
    create_partition_mappings
    mount_discovered_filesystems
    print_mount_summary
}

end() { dryrun_summary; }

############################################################
# COMMAND LINE
############################################################

usage() {
    cat <<EOF
mount-vm-drives.sh $SCRIPT_VERSION (project $PROJECT_VERSION)

USAGE
  mount-vm-drives.sh <lvm-volume-path> [mount-root] [--ro|--rw] [dryrun]

DESCRIPTION
  Exposes and mounts recognizable filesystems from an LVM-backed VM disk.
  Partitioned media is mapped through kpartx; a filesystem directly on the LV
  is mounted as part1. Read-only is the default.

EXAMPLES
  mount-vm-drives.sh /dev/thinvg/vm-123-disk-1
  mount-vm-drives.sh /dev/thinvg/vm-123-disk-1 /mnt/vm123
  mount-vm-drives.sh /dev/thinvg/vm-123-disk-1 --rw

EOF
    dryrun_help
}

parse_arguments() {
    pa_count=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            dryrun|--dryrun) enable_dryrun ;;
            --ro|--rw) MODE="$1" ;;
            -h|--help) usage; exit 0 ;;
            --version) printf '%s %s (project %s)\n' "$(basename "$0")" "$SCRIPT_VERSION" "$PROJECT_VERSION"; exit 0 ;;
            -*) die "Unknown option: $1" ;;
            *) pa_count=$((pa_count + 1)); case "$pa_count" in 1) DEVICE="$1" ;; 2) MOUNT_ROOT="$1" ;; *) die "Multiple mount directories specified." ;; esac ;;
        esac
        shift
    done
    [ "$pa_count" -ge 1 ] && [ "$pa_count" -le 2 ] || { usage >&2; exit 2; }
}

############################################################
# DEPENDENCIES
############################################################

# install_dependencies
#
# Description:
#   Installs only missing kpartx/util-linux dependencies. Dry-run prints package
#   mutations but still requires the read-only tools to exist for preflight.
#
# Usage:
#   install_dependencies
#
# Arguments:
#   None.
#
# Output:
#   May install kpartx/util-linux.
#
# Returns:
#   0 when required commands are available.
############################################################
install_dependencies() {
    id_need_kpartx=false; id_need_util=false
    command -v kpartx >/dev/null 2>&1 || id_need_kpartx=true
    command -v blkid >/dev/null 2>&1 || id_need_util=true
    command -v findmnt >/dev/null 2>&1 || id_need_util=true
    command -v mountpoint >/dev/null 2>&1 || id_need_util=true
    if [ "$id_need_kpartx" = true ] || [ "$id_need_util" = true ]; then
        need_commands apt-get
        id_packages=""
        [ "$id_need_kpartx" = false ] || id_packages="kpartx"
        [ "$id_need_util" = false ] || id_packages="${id_packages}${id_packages:+ }util-linux"
        info "Installing required package(s): $id_packages"
        export DEBIAN_FRONTEND=noninteractive
        dryrun_cmd apt-get update
        # Package names contain no whitespace beyond deliberate separation.
        # shellcheck-style splitting is intentional for apt package operands.
        if dryrun_enabled; then dryrun_print_shell "apt-get install -y $id_packages"
        else apt-get install -y $id_packages; fi
    fi
    if dryrun_enabled; then
        for id_cmd in kpartx blkid findmnt mountpoint; do command -v "$id_cmd" >/dev/null 2>&1 || die "Dry-run preflight requires $id_cmd to already be installed."; done
    fi
    need_commands kpartx blkid findmnt mountpoint mount readlink find awk lsblk
}

############################################################
# VALIDATION / PRE-FLIGHT
############################################################

# validate_device
# Validates the requested block device and resolves canonical path/default mount settings.
validate_device() {
    [ -b "$DEVICE" ] || die "Not a block device: $DEVICE"
    DEVICE_REAL="$(readlink -f "$DEVICE")"
    [ -n "$MOUNT_ROOT" ] || MOUNT_ROOT="$PWD/$(basename "$DEVICE")"
    case "$MODE" in --ro) MOUNT_OPTIONS="ro" ;; --rw) MOUNT_OPTIONS="rw" ;; esac
}

# prepare_mount_root
# Creates and canonicalizes the requested mount root without overwriting content.
prepare_mount_root() {
    dryrun_cmd mkdir -p "$MOUNT_ROOT"
    if dryrun_enabled; then MOUNT_ROOT="$(readlink -m "$MOUNT_ROOT")"
    else MOUNT_ROOT="$(readlink -f "$MOUNT_ROOT")"; fi
}

############################################################
# FILESYSTEM HELPERS
############################################################

get_maps() { kpartx -l "$DEVICE" 2>/dev/null | awk '{print $1}'; }

# get_part_num
# Extracts a trailing kpartx partition number from a mapper name.
get_part_num() (
    gpn_map="$1"
    gpn_num="$(printf '%s\n' "$gpn_map" | sed -n 's/.*p\([0-9][0-9]*\)$/\1/p')"
    [ -n "$gpn_num" ] && printf '%s\n' "$gpn_num" || printf '%s\n' "$gpn_map"
)

filesystem_type() { blkid -o value -s TYPE "$1" 2>/dev/null || :; }
partition_table_type() { blkid -o value -s PTTYPE "$1" 2>/dev/null || :; }
filesystem_label() { blkid -o value -s LABEL "$1" 2>/dev/null || :; }
filesystem_uuid() { blkid -o value -s UUID "$1" 2>/dev/null || :; }

# mount_filesystem NODE TARGET DESCRIPTION
#
# Description:
#   Classifies one block device, skips unsafe/non-filesystem types, verifies the
#   exact mount point is unused and empty, then mounts it with MOUNT_OPTIONS.
#
# Usage:
#   mount_filesystem NODE TARGET DESCRIPTION
#
# Arguments:
#   $1 block device, $2 mount directory, $3 display description.
#
# Output:
#   Creates TARGET and mounts NODE unless dry-run mode is active.
#
# Returns:
#   0 on mount/skip success; 1 on unsafe target or mount failure.
############################################################
mount_filesystem() {
    mf_node="$1"; mf_target="$2"; mf_description="$3"
    mf_type="$(filesystem_type "$mf_node")"; mf_label="$(filesystem_label "$mf_node")"; mf_uuid="$(filesystem_uuid "$mf_node")"
    if dryrun_enabled && [ ! -b "$mf_node" ]; then case "$mf_node" in /dev/mapper/*) mf_type="<detected-after-kpartx>" ;; esac; fi

    printf '%s\n' "$mf_description"
    printf '  Device: %s\n' "$mf_node"
    printf '  Type:   %s\n' "${mf_type:-unknown}"
    [ -z "$mf_label" ] || printf '  Label:  %s\n' "$mf_label"
    [ -z "$mf_uuid" ] || printf '  UUID:   %s\n' "$mf_uuid"

    case "$mf_type" in
        swap) printf '  Action: skipping swap\n\n'; return 0 ;;
        LVM2_member) printf '  Action: skipping LVM physical volume\n\n'; return 0 ;;
        crypto_LUKS) printf '  Action: skipping encrypted LUKS volume\n\n'; return 0 ;;
        '') printf '  Action: no recognizable filesystem\n\n'; return 0 ;;
    esac

    if mountpoint -q "$mf_target" 2>/dev/null; then
        mf_existing="$(findmnt -rn -M "$mf_target" -o SOURCE 2>/dev/null || :)"
        printf '  Mount point is already in use: %s\n  Existing source: %s\n\n' "$mf_target" "${mf_existing:-unknown}"
        return 0
    fi

    if [ ! -d "$mf_target" ]; then printf '  Creating folder: %s\n' "$mf_target"; dryrun_cmd mkdir -p "$mf_target"; fi
    if [ -d "$mf_target" ] && [ -n "$(find "$mf_target" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
        printf '  ERROR: Mount folder is not empty: %s\n  Refusing to mount over existing files.\n' "$mf_target" >&2
        return 1
    fi

    printf '  Mounting: %s\n' "$mf_target"
    if dryrun_cmd mount -o "$MOUNT_OPTIONS" "$mf_node" "$mf_target"; then
        ok "  Mounted successfully."
        if dryrun_enabled; then dryrun_verify "$mf_node would be mounted at $mf_target"; fi
    else
        printf '  ERROR: Failed to mount %s\n' "$mf_node" >&2
        rmdir "$mf_target" 2>/dev/null || :
        return 1
    fi
    printf '\n'
    return 0
}

############################################################
# HIGH LEVEL TASKS
############################################################

# print_configuration
# Prints the resolved device/mount configuration before filesystem operations.
print_configuration() {
    printf 'LVM volume:      %s\n' "$DEVICE"
    printf 'Resolved device: %s\n' "$DEVICE_REAL"
    printf 'Mount root:      %s\n' "$MOUNT_ROOT"
    printf 'Mode:            %s\n\n' "$MOUNT_OPTIONS"
}

# create_partition_mappings
# Creates kpartx mappings in real mode or performs read-only mapping discovery in dry-run mode.
create_partition_mappings() {
    printf 'Creating partition device mappings...\n\n'
    if dryrun_enabled; then
        dryrun_cmd kpartx -av "$DEVICE"; KPARTX_OUTPUT=""; KPARTX_STATUS=0
    else
        set +e
        KPARTX_OUTPUT="$(kpartx -av "$DEVICE" 2>&1)"
        KPARTX_STATUS=$?
        set -e
    fi
    [ -z "$KPARTX_OUTPUT" ] || printf '%s\n' "$KPARTX_OUTPUT"
    command -v udevadm >/dev/null 2>&1 && udevadm settle || :
    MAPS="$(get_maps || :)"
}

# mount_discovered_filesystems
# Mounts mapped partitions, or safely falls back to a directly formatted LV when no partition table exists.
mount_discovered_filesystems() {
    mdf_count="$(printf '%s\n' "$MAPS" | awk 'NF {n++} END {print n+0}')"
    if [ "$mdf_count" -gt 0 ]; then
        printf '\nFound %s partition(s).\n\n' "$mdf_count"
        for mdf_map in $MAPS; do
            mdf_node="/dev/mapper/$mdf_map"; mdf_num="$(get_part_num "$mdf_map")"; mdf_target="$MOUNT_ROOT/part${mdf_num}"
            if [ ! -b "$mdf_node" ] && ! dryrun_enabled; then
                printf 'Partition %s\n  ERROR: Device does not exist: %s\n\n' "$mdf_num" "$mdf_node" >&2
                continue
            fi
            mount_filesystem "$mdf_node" "$mdf_target" "Partition $mdf_num"
        done
        return 0
    fi

    printf '\nNo partition mappings found.\nChecking whether the filesystem is directly on the LV...\n\n'
    mdf_raw_type="$(filesystem_type "$DEVICE")"; mdf_pttype="$(partition_table_type "$DEVICE")"
    if [ -n "$mdf_pttype" ]; then
        printf 'A partition table was detected: %s\n\nBut kpartx did not create any partition mappings.\nFor safety, the LV will NOT be mounted as a raw filesystem.\n\nDiagnostic information:\n' "$mdf_pttype"
        blkid "$DEVICE" 2>/dev/null || :
        printf '\n'; lsblk -f "$DEVICE" 2>/dev/null || :
        exit 1
    fi
    if [ -n "$mdf_raw_type" ]; then
        case "$mdf_raw_type" in
            swap|LVM2_member|crypto_LUKS) printf 'The LV contains: %s\n\nThis is not a directly mountable filesystem.\n' "$mdf_raw_type"; exit 1 ;;
        esac
        printf 'Detected filesystem directly on the LVM volume: %s\n\nTreating the whole LV as part1.\n\n' "$mdf_raw_type"
        mount_filesystem "$DEVICE" "$MOUNT_ROOT/part1" "Filesystem directly on LV"
        return 0
    fi

    printf 'No partition table and no recognizable filesystem were found.\n\nDiagnostic information:\n'
    blkid "$DEVICE" 2>/dev/null || :
    printf '\n'; lsblk -f "$DEVICE" 2>/dev/null || :
    [ "$KPARTX_STATUS" -eq 0 ] || printf '\nkpartx exited with status: %s\n' "$KPARTX_STATUS"
    dryrun_cmd rmdir "$MOUNT_ROOT" 2>/dev/null || :
    exit 1
}

# print_mount_summary
# Prints mounts belonging to the current mount root and the dry-run verification summary.
print_mount_summary() {
    printf '\n--------------------------------------------------\nMount summary\n--------------------------------------------------\n\n'
    findmnt -rn -o SOURCE,TARGET | while IFS=' ' read -r pms_source pms_target; do
        case "$pms_target" in "$MOUNT_ROOT"|"$MOUNT_ROOT"/*) printf '%-50s %s\n' "$pms_source" "$pms_target" ;; esac
    done
    printf '\nMount root: %s\n\n' "$MOUNT_ROOT"
    if dryrun_enabled; then dryrun_verify "Planned mount points would appear under $MOUNT_ROOT"; fi
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
