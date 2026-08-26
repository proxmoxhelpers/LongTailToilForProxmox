#!/bin/sh
set -eu

############################################################
# LIFECYCLE
#
# setup/main/end are intentionally defined first so the public flow and
# user-adjustable defaults are visible before implementation helpers.
############################################################

# setup [ARGS...]
# Call: setup "$@"
# Initializes defaults, parses arguments, and performs non-mutating setup.
setup() {
    PROJECT_VERSION="3.7.1"; SCRIPT_VERSION="3.7.1"
    ALL_LVS_FILE=""; REFS_FILE=""; PARTS_FILE=""
    define_colours
    define_format_colours
    parse_arguments "$@"
    check_elevation
}

# main [ARGS...]
# Call: main "$@"
# Performs preflight and the command's primary operation.
main() {
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    need_commands lvs pvesm find awk sed grep sort mktemp partx blkid blockdev tr
    build_lvm_catalog
    collect_guest_lvm_references
    print_guest_filesystems
    print_remaining_filesystems
}

# end
# Call: end
# Prints/finalizes the command result and performs normal completion cleanup.
end() { cleanup_files; }

# usage
# Call: usage
# Prints command-line usage and exits only when the caller chooses to exit.
usage() {
    cat <<EOF
$(basename "$0") $SCRIPT_VERSION (project $PROJECT_VERSION)

USAGE
  $(basename "$0") [dryrun]

DESCRIPTION
  Lists every LVM volume referenced by Proxmox QEMU/LXC guests, grouped under
  its VMID, then inspects the partition table and the actual content of each
  partition without mounting it or creating partition mappings.

  TABLE_HINT and CONTENT_FORMAT are intentionally separate:

    TABLE_HINT      is derived from the GPT/MBR partition type.
    CONTENT_FORMAT  is detected directly from bytes inside that partition.

  Partition tables do not generally store an exact filesystem format. Generic
  types such as Linux filesystem and Microsoft basic data are therefore shown
  as LINUX-FS or MS-DATA. A red MISMATCH note is printed only when the table
  type provides a meaningful expectation and the detected content violates it.

  LVs with no partition table are probed as a whole-device filesystem.

COLOURS
  NTFS / BitLocker       bright magenta
  FAT / exFAT            bright cyan
  ext2 / ext3 / ext4     bright green
  Btrfs                  bright blue
  XFS                    bright yellow
  swap                   bright red
  LVM / LUKS / RAID      distinct terminal colours
  ZFS                    cyan
  other / unknown        bright white
  mismatch notes         red

SAFETY
  Read-only. Uses partx --show and blkid offset probing only. It does not mount,
  write, run fsck, create partition mappings, or modify device-mapper state.

EOF
    dryrun_help
}

############################################################
# EMBEDDED SHARED RUNTIME
#
# This command is intentionally self-contained. The common and
# dry-run helpers are embedded so this single file can be copied
# anywhere and run without the repository's lib/ directory.
############################################################

# This file is sourced by executable project commands.

############################################################
# COLOURS / OUTPUT
############################################################

# define_colours
# Enables terminal colours when stdout is a terminal and NO_COLOR is unset.
define_colours() {
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
        ESC="$(printf '\033')"; C_RESET="${ESC}[0m"; C_RED="${ESC}[31m"; C_GREEN="${ESC}[32m"; C_YELLOW="${ESC}[33m"; C_BLUE="${ESC}[34m"; C_CYAN="${ESC}[36m"; C_BOLD="${ESC}[1m"
    else
        C_RESET=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_CYAN=""; C_BOLD=""
    fi
}

# Call: print_banner ARG1
print_banner() { printf '\n%s%s============================================================\n%s\n============================================================%s\n' "$C_BOLD" "$C_CYAN" "$1" "$C_RESET"; }
# Call: info [ARG...]
info() { printf '%s%s%s\n' "$C_CYAN" "$*" "$C_RESET"; }
# Call: ok [ARG...]
ok() { printf '%s[OK]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
# Call: warn [ARG...]
warn() { printf '%sWARNING:%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
# Call: die [ARG...]
die() { printf '%sERROR:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

# usage_error TEXT...
# Call: usage_error [TEXT...]
# Prints a command-line error followed by the complete public usage and exits 2.
usage_error() {
    printf '%sUSAGE ERROR:%s %s\n\n' "$C_RED" "$C_RESET" "$*" >&2
    usage >&2
    exit 2
}
# Call: section [ARG...]
section() { printf '\n%s%s%s\n' "$C_BOLD$C_CYAN" "$*" "$C_RESET"; }

# trim
# Removes leading and trailing POSIX whitespace from stdin.
trim() { sed 's/^[[:space:]]*//;s/[[:space:]]*$//'; }

############################################################
# PRIVILEGE / DEPENDENCIES
############################################################

# check_elevation
# Call: check_elevation
# Sets APP_ELEVATED silently. Elevation is reported only when it is required.
check_elevation() {
    if [ "$(id -u)" -eq 0 ]; then APP_ELEVATED="true"
    else APP_ELEVATED="false"; fi
    export APP_ELEVATED
}

# self_elevate ARGS...
# Re-executes the current script through sudo while preserving all arguments.
# Call: self_elevate ARGS...
self_elevate() {
    command -v sudo >/dev/null 2>&1 || die "Root privileges are required and sudo is unavailable."
    warn "Re-running with root privileges..."
    exec sudo -- /bin/sh "$0" "$@"
}

# require_command COMMAND
# Exits when COMMAND is unavailable.
# Call: require_command COMMAND
require_command() { command -v "$1" >/dev/null 2>&1 || die "Required command is missing: $1"; }

# need_commands COMMAND...
# Requires every named command.
# Call: need_commands COMMAND...
need_commands() { for nc_cmd in "$@"; do require_command "$nc_cmd"; done; }

############################################################
# TEMPORARY RESOURCE HELPERS
############################################################

# register_temp_file PATH
# Registers a process-owned temporary file for best-effort removal on exit.
# Call: register_temp_file PATH
register_temp_file() {
    rtf_path="$1"; [ -n "$rtf_path" ] || return 0
    TEMP_FILES="${TEMP_FILES:-}${TEMP_FILES:+
}${rtf_path}"
}

# cleanup_registered_temps
#
# Description:
#   Removes only paths explicitly registered by the current script and preserves
#   the original process exit status. Intended for non-transactional temp files;
#   storage/config rollback uses script-specific transaction handlers instead.
#
# Usage:
#   Installed by install_temp_cleanup as the POSIX exit trap.
#
# Arguments:
#   None.
#
# Output:
#   Removes registered temporary files.
#
# Returns:
#   Re-emits the original nonzero status when one exists.
############################################################
cleanup_registered_temps() {
    crt_status=$?
    trap - 0 HUP INT TERM
    if [ -n "${TEMP_FILES:-}" ]; then
        printf '%s\n' "$TEMP_FILES" | while IFS= read -r crt_path; do [ -z "$crt_path" ] || rm -f -- "$crt_path"; done
    fi
    TEMP_FILES=""
    [ "$crt_status" -eq 0 ] || exit "$crt_status"
    return 0
}

# install_temp_cleanup
# Installs one exit cleanup path and converts signals into ordinary exit status.
install_temp_cleanup() {
    TEMP_FILES="${TEMP_FILES:-}"
    trap cleanup_registered_temps 0
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
}

############################################################
# GUEST HELPERS
############################################################

# require_qemu_vm VMID
# Validates a local QEMU VM and rejects LXC IDs explicitly.
# Call: require_qemu_vm VMID
require_qemu_vm() {
    rqv_id="$1"
    case "$rqv_id" in ''|*[!0-9]*) die "VMID must be numeric: $rqv_id" ;; esac
    if [ ! -f "/etc/pve/qemu-server/${rqv_id}.conf" ]; then
        [ ! -f "/etc/pve/lxc/${rqv_id}.conf" ] || die "VMID $rqv_id is an LXC container; this command requires a QEMU VM."
        die "QEMU VM $rqv_id does not exist on this node."
    fi
    qm config "$rqv_id" >/dev/null 2>&1 || die "Proxmox cannot read VM $rqv_id."
}

# require_guest_stopped VMID [qemu|lxc]
# Requires the requested guest to be stopped.
# Call: require_guest_stopped VMID [qemu|lxc]
require_guest_stopped() {
    rgs_id="$1"; rgs_kind="${2:-qemu}"
    if [ "$rgs_kind" = "qemu" ]; then rgs_status="$(qm status "$rgs_id" 2>/dev/null | awk '{print $2}')"
    else rgs_status="$(pct status "$rgs_id" 2>/dev/null | awk '{print $2}')"; fi
    [ "$rgs_status" = "stopped" ] || die "Guest $rgs_id must be stopped (current status: ${rgs_status:-unknown})."
}

# first_free_scsi VMID
# Prints the first unused scsi0..scsi30 slot.
first_free_scsi() (
    ffs_id="$1"; ffs_cfg="$(qm config "$ffs_id")"; ffs_i=0
    while [ "$ffs_i" -le 30 ]; do
        printf '%s\n' "$ffs_cfg" | grep -qE "^scsi${ffs_i}:" || { printf 'scsi%s\n' "$ffs_i"; exit 0; }
        ffs_i=$((ffs_i + 1))
    done
    exit 1
)

# first_free_unused VMID
# Prints the first unused unused0..unused255 key.
first_free_unused() (
    ffu_id="$1"; ffu_cfg="$(qm config "$ffu_id")"; ffu_i=0
    while [ "$ffu_i" -le 255 ]; do
        printf '%s\n' "$ffu_cfg" | grep -qE "^unused${ffu_i}:" || { printf 'unused%s\n' "$ffu_i"; exit 0; }
        ffu_i=$((ffu_i + 1))
    done
    exit 1
)

# disk_value VMID SLOT
# Prints the complete value configured at a VM disk slot.
# Call: disk_value VMID SLOT
disk_value() { qm config "$1" | sed -n "s/^${2}:[[:space:]]*//p" | head -n1; }

# disk_volid VMID SLOT
# Prints only the storage:volume identifier from a disk slot.
disk_volid() (
    dv_value="$(disk_value "$1" "$2")"
    [ -n "$dv_value" ] || exit 1
    dv_value="${dv_value%%,*}"
    case "$dv_value" in *:*) printf '%s\n' "$dv_value" ;; *) exit 1 ;; esac
)

# all_guest_configs
# Prints all QEMU/LXC guest configuration paths visible cluster-wide.
all_guest_configs() { find /etc/pve/nodes -type f \( -path '*/qemu-server/*.conf' -o -path '*/lxc/*.conf' \) -print 2>/dev/null; }

# guest_volume_references
# Prints config|slot|storage:volume for configured guest volumes.
# Call: guest_volume_references ARG1 [ARG2]
guest_volume_references() {
    all_guest_configs | while IFS= read -r gvr_cfg; do
        awk -F': ' -v cfg="$gvr_cfg" '
            $1 ~ /^(scsi|sata|virtio|ide|unused|efidisk|tpmstate)[0-9]+$/ || $1 == "rootfs" || $1 ~ /^mp[0-9]+$/ {
                split($2, a, ",")
                if (a[1] ~ /^[^:]+:.+/) print cfg "|" $1 "|" a[1]
            }
        ' "$gvr_cfg"
    done
    return 0
}

# config_volume_references CONFIG
# Prints slot|storage:volume for one guest configuration.
# Call: config_volume_references CONFIG
config_volume_references() {
    awk -F': ' '
        $1 ~ /^(scsi|sata|virtio|ide|unused|efidisk|tpmstate)[0-9]+$/ || $1 == "rootfs" || $1 ~ /^mp[0-9]+$/ {
            split($2, a, ",")
            if (a[1] ~ /^[^:]+:.+/) print $1 "|" a[1]
        }
    ' "$1"
    return 0
}

# other_volume_references VOLID [EXCLUDED_CONFIG]
# Prints configurations other than EXCLUDED_CONFIG that reference VOLID.
# A successful lookup with no matches returns status 0 and empty stdout.
other_volume_references() (
    ovr_needle="$1"; ovr_exclude="${2:-}"; ovr_exclude_real=""
    [ -z "$ovr_exclude" ] || ovr_exclude_real="$(readlink -f "$ovr_exclude" 2>/dev/null || printf '%s' "$ovr_exclude")"
    all_guest_configs | while IFS= read -r ovr_file; do
        if [ -n "$ovr_exclude_real" ]; then
            ovr_real="$(readlink -f "$ovr_file" 2>/dev/null || printf '%s' "$ovr_file")"
            [ "$ovr_real" != "$ovr_exclude_real" ] || continue
        fi
        if grep -F "$ovr_needle" "$ovr_file" >/dev/null 2>&1; then printf '%s\n' "$ovr_file"; fi
    done
    exit 0
)

############################################################
# LVM / STORAGE HELPERS
############################################################

# resolve_volid_path VOLID
# Resolves a Proxmox volume ID to its path.
# Call: resolve_volid_path VOLID
resolve_volid_path() { pvesm path "$1" 2>/dev/null; }

# canonical_lv_path LV
# Prints the canonical LVM lv_path reported by LVM metadata.
# Call: canonical_lv_path LV
canonical_lv_path() { lvs --noheadings -o lv_path "$1" 2>/dev/null | trim; }

# assert_lv_exists LV
# Exits unless LV exists.
# Call: assert_lv_exists LV
assert_lv_exists() { lvs "$1" >/dev/null 2>&1 || die "Logical volume does not exist: $1"; }

# assert_lv_idle LV
# Refuses an LV that is mounted or has a nonzero device-mapper open count.
assert_lv_idle() (
    ali_path="$1"; ali_real="$(readlink -f "$ali_path")"
    if findmnt -rn -S "$ali_path" >/dev/null 2>&1 || findmnt -rn -S "$ali_real" >/dev/null 2>&1; then die "Logical volume is mounted: $ali_path"; fi
    ali_open="$(dmsetup info -c --noheadings -o open "$ali_real" 2>/dev/null | tr -d '[:space:]' || :)"
    case "$ali_open" in ''|*[!0-9]*) exit 0 ;; esac
    [ "$ali_open" -eq 0 ] || die "Logical volume is open/in use (device-mapper open count $ali_open): $ali_path"
)

# storage_for_lv LV
# Prints storage_id|storage_type for matching Proxmox LVM/LVM-thin storages.
storage_for_lv() (
    sfl_path="$1"
    sfl_vg="$(lvs --noheadings -o vg_name "$sfl_path" 2>/dev/null | trim)"
    sfl_pool="$(lvs --noheadings -o pool_lv "$sfl_path" 2>/dev/null | trim)"
    [ -n "$sfl_vg" ] || exit 1
    awk -v vg="$sfl_vg" -v pool="$sfl_pool" '
      function flush() {
        if (id == "") return
        if (type=="lvmthin" && sv==vg && sp==pool && (content=="" || content ~ /(^|,)images(,|$)/)) print id "|" type
        if (type=="lvm" && pool=="" && sv==vg && (content=="" || content ~ /(^|,)images(,|$)/)) print id "|" type
      }
      /^[^ \t][^:]*:[ \t]*/ { flush(); split($1,a,":"); type=a[1]; id=$2; sv=""; sp=""; content=""; next }
      $1=="vgname" { sv=$2; next }
      $1=="thinpool" { sp=$2; next }
      $1=="content" { content=$2; next }
      END { flush() }
    ' /etc/pve/storage.cfg 2>/dev/null
)

# unique_storage_for_lv LV
# Prints the unique storage_id|storage_type mapping and refuses ambiguity.
unique_storage_for_lv() (
    usfl_path="$1"
    usfl_matches="$(storage_for_lv "$usfl_path" || :)"
    [ -n "$usfl_matches" ] || die "No Proxmox LVM/LVM-thin storage maps to $usfl_path."
    usfl_count="$(printf '%s\n' "$usfl_matches" | awk 'NF {n++} END {print n+0}')"
    if [ "$usfl_count" -ne 1 ]; then printf '%s\n' "$usfl_matches" >&2; die "Multiple Proxmox storages map to $usfl_path; refusing to guess."; fi
    printf '%s\n' "$usfl_matches"
)

# volid_for_lv LV
# Prints the Proxmox storage:volume ID for an LVM logical volume.
volid_for_lv() (
    vfl_path="$1"; vfl_lv="$(lvs --noheadings -o lv_name "$vfl_path" 2>/dev/null | trim)"
    vfl_map="$(unique_storage_for_lv "$vfl_path")"; vfl_sid="${vfl_map%%|*}"
    printf '%s:%s\n' "$vfl_sid" "$vfl_lv"
)

# lvm_thin_warning_filter
# Removes only the three recurring thin-pool advisory warnings.
lvm_thin_warning_filter() {
    grep -vE -e 'WARNING: Sum of all thin volume sizes .* exceeds the size of thin pool' -e 'WARNING: You have not turned on protection against thin pools running out of space\.' -e 'WARNING: Set activation/thin_pool_autoextend_threshold below 100 to trigger automatic extension of thin pools before they get full\.' >&2 || :
}

# run_lvm_filtered COMMAND...
# Runs an LVM command while preserving its status and filtering only known
# thin-pool advisory warnings from stderr.
run_lvm_filtered() (
    rlf_err="$(mktemp)" || exit 1
    trap 'rm -f "$rlf_err"' 0 HUP INT TERM
    set +e
    "$@" 2>"$rlf_err"
    rlf_rc=$?
    set -e
    lvm_thin_warning_filter < "$rlf_err"
    exit "$rlf_rc"
)

DRY_RUN="${DRY_RUN:-0}"
export DRY_RUN

# dryrun_enabled
# Returns true when dry-run mode is active.
dryrun_enabled() { [ "${DRY_RUN:-0}" = "1" ]; }

# enable_dryrun
# Enables dry-run mode for this process and child project scripts.
enable_dryrun() { DRY_RUN=1; export DRY_RUN; }

# is_dryrun_arg ARG
# Recognizes the two accepted dry-run keyword forms.
# Call: is_dryrun_arg ARG
is_dryrun_arg() { case "$1" in dryrun|--dryrun) return 0 ;; *) return 1 ;; esac; }

# dryrun_help
# Prints the common dry-run CLI documentation.
dryrun_help() {
    cat <<'EOF'
HELP
  -h, -?, /h, /?, --help  Show this help and exit.
  --version                Show script and project versions and exit.

DRY-RUN
  Forms: dryrun, --dryrun.
  Dry-run: no system changes are made; modifying commands are printed instead of executed.
EOF
}

# shell_quote ARG
# Prints one shell-readable representation for diagnostic command output.
# Call: shell_quote ARG
shell_quote() {
    sq_arg="$1"
    case "$sq_arg" in
        '') printf "''" ;;
        *[!A-Za-z0-9_./:@%+=,-]*)
            sq_escaped="$(printf '%s' "$sq_arg" | sed "s/'/'\\\\''/g")"
            printf "'%s'" "$sq_escaped"
            ;;
        *) printf '%s' "$sq_arg" ;;
    esac
}

# dryrun_print_command COMMAND...
# Prints a shell-escaped command line without executing it.
# Call: dryrun_print_command COMMAND...
dryrun_print_command() {
    printf '%s[DRYRUN]%s' "${C_YELLOW:-}" "${C_RESET:-}"
    for dpc_arg in "$@"; do printf ' '; shell_quote "$dpc_arg"; done
    printf '\n'
}

# dryrun_print_shell TEXT...
# Prints a descriptive shell operation that may include placeholders.
# Call: dryrun_print_shell TEXT...
dryrun_print_shell() { printf '%s[DRYRUN]%s %s\n' "${C_YELLOW:-}" "${C_RESET:-}" "$*"; }

# dryrun_cmd COMMAND...
# Executes COMMAND normally or prints it and returns simulated success.
# Call: dryrun_cmd COMMAND...
dryrun_cmd() {
    if dryrun_enabled; then dryrun_print_command "$@"; return 0; fi
    "$@"
}

# dryrun_verify DESCRIPTION
# Prints a simulated verification result during dry-run mode.
# Call: dryrun_verify DESCRIPTION
dryrun_verify() {
    if dryrun_enabled; then printf '%s[DRYRUN VERIFY]%s %s (simulated success)\n' "${C_CYAN:-}" "${C_RESET:-}" "$*"; return 0; fi
    return 1
}

# dryrun_summary
# Prints the standard dry-run completion statement and always succeeds.
dryrun_summary() {
    if dryrun_enabled; then printf '%s[DRYRUN]%s No modifying command was executed.\n' "${C_GREEN:-}" "${C_RESET:-}"; fi
    return 0
}



############################################################
# COMMAND LINE
############################################################

# Call: parse_arguments ARG1
parse_arguments() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            dryrun|--dryrun) enable_dryrun ;;
            -h|-\?|/h|/\?|--help) usage; exit 0 ;;
            --version) printf '%s %s (project %s)\n' "$(basename "$0")" "$SCRIPT_VERSION" "$PROJECT_VERSION"; exit 0 ;;
            *) usage >&2; exit 2 ;;
        esac
        shift
    done
}

############################################################
# COLOUR / FORMAT HELPERS
############################################################

define_format_colours() {
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
        dfc_esc="$(printf '\033')"
        F_NTFS="${dfc_esc}[95m"
        F_FAT="${dfc_esc}[96m"
        F_EXT="${dfc_esc}[92m"
        F_BTRFS="${dfc_esc}[94m"
        F_XFS="${dfc_esc}[93m"
        F_SWAP="${dfc_esc}[91m"
        F_LVM="${dfc_esc}[35m"
        F_LUKS="${dfc_esc}[33m"
        F_RAID="${dfc_esc}[34m"
        F_ZFS="${dfc_esc}[36m"
        F_OTHER="${dfc_esc}[97m"
    else
        F_NTFS=""; F_FAT=""; F_EXT=""; F_BTRFS=""; F_XFS=""; F_SWAP=""
        F_LVM=""; F_LUKS=""; F_RAID=""; F_ZFS=""; F_OTHER=""
    fi
}

# Call: fs_colour ARG1
fs_colour() {
    fc_fs="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    case "$fc_fs" in
        ntfs|bitlocker) printf '%s' "$F_NTFS" ;;
        vfat|fat|fat12|fat16|fat32|msdos|exfat) printf '%s' "$F_FAT" ;;
        ext2|ext3|ext4) printf '%s' "$F_EXT" ;;
        btrfs) printf '%s' "$F_BTRFS" ;;
        xfs) printf '%s' "$F_XFS" ;;
        swap) printf '%s' "$F_SWAP" ;;
        lvm2_member) printf '%s' "$F_LVM" ;;
        crypto_luks|luks) printf '%s' "$F_LUKS" ;;
        linux_raid_member) printf '%s' "$F_RAID" ;;
        zfs_member|zfs) printf '%s' "$F_ZFS" ;;
        *) printf '%s' "$F_OTHER" ;;
    esac
}

# Call: class_colour ARG1
class_colour() {
    cc_class="$1"
    case "$cc_class" in
        microsoft) printf '%s' "$F_NTFS" ;;
        fat) printf '%s' "$F_FAT" ;;
        linuxfs) printf '%s' "$F_EXT" ;;
        swap) printf '%s' "$F_SWAP" ;;
        lvm) printf '%s' "$F_LVM" ;;
        luks) printf '%s' "$F_LUKS" ;;
        raid) printf '%s' "$F_RAID" ;;
        zfs) printf '%s' "$F_ZFS" ;;
        *) printf '%s' "$F_OTHER" ;;
    esac
}

# Call: human_bytes ARG1
human_bytes() {
    awk -v hb="$1" 'BEGIN {
        split("B KiB MiB GiB TiB PiB", u, " "); i=1
        while (hb >= 1024 && i < 6) { hb/=1024; i++ }
        if (i==1) printf "%.0f %s", hb, u[i]; else printf "%.1f %s", hb, u[i]
    }'
}

############################################################
# PARTITION TABLE INTERPRETATION
############################################################

# table_type_info RAW_TYPE
# Prints friendly-label|compatibility-class.
table_type_info() (
    tti_raw="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    case "$tti_raw" in
        0x01|01|0x04|04|0x06|06|0x0e|0e) printf '%s\n' "FAT16|fat" ;;
        0x0b|0b|0x0c|0c) printf '%s\n' "FAT32|fat" ;;
        0x07|07) printf '%s\n' "Microsoft data|microsoft" ;;
        0x05|05|0x0f|0f|0x85|85) printf '%s\n' "Extended partition|none" ;;
        0x82|82) printf '%s\n' "Linux swap|swap" ;;
        0x83|83) printf '%s\n' "Linux filesystem|linuxfs" ;;
        0x8e|8e) printf '%s\n' "Linux LVM|lvm" ;;
        0xfd|fd) printf '%s\n' "Linux RAID|raid" ;;
        0xef|ef) printf '%s\n' "EFI System|fat" ;;
        0xaf|af) printf '%s\n' "Apple HFS/HFS+|hfs" ;;
        0xa5|a5) printf '%s\n' "FreeBSD|unknown" ;;

        c12a7328-f81f-11d2-ba4b-00a0c93ec93b) printf '%s\n' "EFI System|fat" ;;
        ebd0a0a2-b9e5-4433-87c0-68b6b72699c7) printf '%s\n' "Microsoft basic data|microsoft" ;;
        de94bba4-06d1-4d40-a16a-bfd50179d6ac) printf '%s\n' "Windows recovery|microsoft" ;;
        e3c9e316-0b5c-4db8-817d-f92df00215ae) printf '%s\n' "Microsoft reserved|none" ;;
        0fc63daf-8483-4772-8e79-3d69d8477de4) printf '%s\n' "Linux filesystem|linuxfs" ;;
        0657fd6d-a4ab-43c4-84e5-0933c84b4f4f) printf '%s\n' "Linux swap|swap" ;;
        e6d6d379-f507-44c2-a23c-238f2a3df928) printf '%s\n' "Linux LVM|lvm" ;;
        a19d880f-05fc-4d3b-a006-743f0f84911e) printf '%s\n' "Linux RAID|raid" ;;
        933ac7e1-2eb4-4f13-b844-0e14e2aef915) printf '%s\n' "Linux /home|linuxfs" ;;
        3b8f8425-20e0-4f3b-907f-1a25a76f98e8) printf '%s\n' "Linux /srv|linuxfs" ;;
        44479540-f297-41b2-9af7-d131d5f0458a) printf '%s\n' "Linux root x86|linuxfs" ;;
        4f68bce3-e8cd-4db1-96e7-fbcaf984b709) printf '%s\n' "Linux root x86-64|linuxfs" ;;
        69dad710-2ce4-4e3c-b16c-21a1d49abed3) printf '%s\n' "Linux root ARM|linuxfs" ;;
        b921b045-1df0-41c3-af44-4c6f280d3fae) printf '%s\n' "Linux root ARM64|linuxfs" ;;
        21686148-6449-6e6f-744e-656564454649) printf '%s\n' "BIOS boot|none" ;;
        48465300-0000-11aa-aa11-00306543ecac) printf '%s\n' "Apple HFS/HFS+|hfs" ;;
        7c3457ef-0000-11aa-aa11-00306543ecac) printf '%s\n' "Apple APFS|apfs" ;;
        6a898cc3-1dd2-11b2-99a6-080020736631) printf '%s\n' "Solaris /usr / ZFS|zfs" ;;
        "") printf '%s\n' "Unknown|unknown" ;;
        *) printf '%s|unknown\n' "$1" ;;
    esac
)

# Call: content_class ARG1
content_class() {
    cc_fs="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    case "$cc_fs" in
        vfat|fat|fat12|fat16|fat32|msdos) printf '%s\n' "fat" ;;
        ntfs|exfat|bitlocker) printf '%s\n' "microsoft" ;;
        ext2|ext3|ext4|btrfs|xfs|f2fs|reiserfs|reiser4|jfs|nilfs2|bcachefs|ocfs2|gfs2|erofs|squashfs) printf '%s\n' "linuxfs" ;;
        swap) printf '%s\n' "swap" ;;
        lvm2_member) printf '%s\n' "lvm" ;;
        crypto_luks) printf '%s\n' "luks" ;;
        linux_raid_member) printf '%s\n' "raid" ;;
        zfs_member|zfs) printf '%s\n' "zfs" ;;
        hfs|hfsplus) printf '%s\n' "hfs" ;;
        apfs) printf '%s\n' "apfs" ;;
        "") printf '%s\n' "none" ;;
        *) printf '%s\n' "other" ;;
    esac
}

# table_content_match TABLE_CLASS CONTENT_FS
# Unknown partition types are deliberately non-strict.
# Call: table_content_match TABLE_CLASS CONTENT_FS
table_content_match() {
    tcm_table="$1"; tcm_fs="$2"; tcm_content="$(content_class "$tcm_fs")"
    case "$tcm_table" in
        unknown) return 0 ;;
        none) [ "$tcm_content" = "none" ] ;;
        fat) [ "$tcm_content" = "fat" ] ;;
        microsoft) [ "$tcm_content" = "microsoft" ] || [ "$tcm_content" = "fat" ] ;;
        linuxfs) [ "$tcm_content" = "linuxfs" ] || [ "$tcm_content" = "luks" ] ;;
        swap|lvm|raid|zfs|hfs|apfs) [ "$tcm_content" = "$tcm_table" ] ;;
        *) return 0 ;;
    esac
}

############################################################
# DISCOVERY
############################################################

# Call: build_lvm_catalog ARG1 [ARG2] [ARG3] [ARG4] [ARG5] [ARG6] [ARG7]
build_lvm_catalog() {
    install_temp_cleanup
    ALL_LVS_FILE="$(mktemp)" || die "Unable to create LVM catalog."; register_temp_file "$ALL_LVS_FILE"
    REFS_FILE="$(mktemp)" || die "Unable to create guest-reference catalog."; register_temp_file "$REFS_FILE"
    PARTS_FILE="$(mktemp)" || die "Unable to create partition scratch file."; register_temp_file "$PARTS_FILE"

    lvs --noheadings --separator '|' -o lv_uuid,lv_path,vg_name,lv_name,lv_size,pool_lv,origin 2>/dev/null |
        awk -F'|' '{
            for (i=1; i<=7; i++) gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i)
            if ($1 != "" && $2 != "") print $1 "|" $2 "|" $3 "|" $4 "|" $5 "|" $6 "|" $7
        }' | sort -t'|' -k3,3 -k4,4 > "$ALL_LVS_FILE"
}

# collect_guest_lvm_references
# REFS_FILE columns: vmid|type|name|slot|volid|uuid|path|size
# Call: collect_guest_lvm_references ARG1 [ARG2] [ARG3] [ARG4] [ARG5]
collect_guest_lvm_references() {
    : > "$REFS_FILE"
    all_guest_configs | while IFS= read -r cglr_cfg; do
        [ -n "$cglr_cfg" ] || continue
        cglr_id="${cglr_cfg##*/}"; cglr_id="${cglr_id%.conf}"
        case "$cglr_id" in ''|*[!0-9]*) continue ;; esac

        case "$cglr_cfg" in
            */lxc/*) cglr_type="LXC"; cglr_name="$(awk -F': ' '$1=="hostname" {print $2; exit}' "$cglr_cfg")" ;;
            *) cglr_type="QEMU"; cglr_name="$(awk -F': ' '$1=="name" {print $2; exit}' "$cglr_cfg")" ;;
        esac
        [ -n "$cglr_name" ] || cglr_name="-"

        config_volume_references "$cglr_cfg" | while IFS='|' read -r cglr_slot cglr_volid; do
            [ -n "$cglr_volid" ] || continue
            cglr_path="$(pvesm path "$cglr_volid" 2>/dev/null || :)"
            [ -n "$cglr_path" ] || continue
            lvs "$cglr_path" >/dev/null 2>&1 || continue
            cglr_uuid="$(lvs --noheadings -o lv_uuid "$cglr_path" 2>/dev/null | trim)"
            [ -n "$cglr_uuid" ] || continue
            cglr_row="$(awk -F'|' -v u="$cglr_uuid" '$1==u {print $2 "|" $5; exit}' "$ALL_LVS_FILE")"
            [ -n "$cglr_row" ] || continue
            cglr_catalog_path="${cglr_row%%|*}"; cglr_size="${cglr_row#*|}"
            printf '%s|%s|%s|%s|%s|%s|%s|%s\n' \
                "$cglr_id" "$cglr_type" "$cglr_name" "$cglr_slot" "$cglr_volid" "$cglr_uuid" "$cglr_catalog_path" "$cglr_size"
        done
    done | sort -t'|' -k1,1n -k4,4 -u > "$REFS_FILE"
    return 0
}

############################################################
# CONTENT PROBING
############################################################

# Call: probe_partition_fs ARG1 [ARG2] [ARG3]
probe_partition_fs() {
    ppf_path="$1"; ppf_offset="$2"; ppf_size="$3"
    blkid -p -o value -s TYPE -O "$ppf_offset" -S "$ppf_size" "$ppf_path" 2>/dev/null || :
}

# Call: probe_whole_fs ARG1
probe_whole_fs() {
    blkid -p -o value -s TYPE "$1" 2>/dev/null || :
}

# Call: print_partition_row ARG1 [ARG2] [ARG3] [ARG4] [ARG5]
print_partition_row() {
    ppr_part="$1"; ppr_start="$2"; ppr_bytes="$3"; ppr_rawtype="$4"; ppr_fs="$5"
    ppr_info="$(table_type_info "$ppr_rawtype")"
    ppr_label="${ppr_info%%|*}"; ppr_class="${ppr_info#*|}"
    [ -n "$ppr_fs" ] || ppr_fs="(none)"

    if [ "$ppr_fs" != "(none)" ] && table_content_match "$ppr_class" "$ppr_fs"; then
        ppr_table_colour="$(fs_colour "$ppr_fs")"
        ppr_note=""
    elif [ "$ppr_fs" = "(none)" ] && table_content_match "$ppr_class" ""; then
        ppr_table_colour="$(class_colour "$ppr_class")"
        ppr_note=""
    else
        ppr_table_colour="$(class_colour "$ppr_class")"
        ppr_note="MISMATCH: table says $ppr_label; content is $ppr_fs"
    fi
    ppr_fs_colour="$(fs_colour "$ppr_fs")"
    ppr_human="$(human_bytes "$ppr_bytes")"

    printf '    %-7s %-11s %-11s ' "$ppr_part" "$ppr_start" "$ppr_human"
    printf '%s%-24s%s ' "$ppr_table_colour" "$ppr_label" "$C_RESET"
    printf '%s%-18s%s' "$ppr_fs_colour" "$ppr_fs" "$C_RESET"
    if [ -n "$ppr_note" ]; then printf '  %s%s%s' "$C_RED$C_BOLD" "$ppr_note" "$C_RESET"; fi
    printf '\n'
}

# Call: inspect_disk ARG1 [ARG2]
inspect_disk() {
    id_path="$1"; id_size="$2"
    id_pttype="$(blkid -p -o value -s PTTYPE "$id_path" 2>/dev/null || :)"
    [ -n "$id_pttype" ] || id_pttype="none"

    : > "$PARTS_FILE"
    partx --show --noheadings -o NR,START,SECTORS,TYPE "$id_path" > "$PARTS_FILE" 2>/dev/null || :

    printf '    Partition table: %s\n' "$id_pttype"
    printf '    %-7s %-11s %-11s %-24s %-18s %s\n' PART START SIZE TABLE_HINT CONTENT_FORMAT NOTE

    if [ ! -s "$PARTS_FILE" ]; then
        id_fs="$(probe_whole_fs "$id_path")"; [ -n "$id_fs" ] || id_fs="(none)"
        id_colour="$(fs_colour "$id_fs")"
        printf '    %-7s %-11s %-11s %-24s ' whole - "$id_size" "(whole disk)"
        printf '%s%-18s%s\n' "$id_colour" "$id_fs" "$C_RESET"
        return 0
    fi

    id_sector="$(blockdev --getss "$id_path" 2>/dev/null || :)"
    case "$id_sector" in ''|*[!0-9]*) id_sector=512 ;; esac

    while read -r id_nr id_start id_sectors id_type; do
        [ -n "$id_nr" ] || continue
        case "$id_start:$id_sectors" in *[!0-9:]*|:*|*:) continue ;; esac
        id_offset=$((id_start * id_sector))
        id_bytes=$((id_sectors * id_sector))
        id_fs="$(probe_partition_fs "$id_path" "$id_offset" "$id_bytes")"
        print_partition_row "part$id_nr" "$id_start" "$id_bytes" "$id_type" "$id_fs"
    done < "$PARTS_FILE"
    return 0
}

############################################################
# RESULTS
############################################################

print_guest_filesystems() {
    section "VM / CT LVM partition and filesystem inventory"
    if [ ! -s "$REFS_FILE" ]; then printf '%s\n' "(none)"; return 0; fi

    pgf_last=""
    while IFS='|' read -r pgf_id pgf_type pgf_name pgf_slot pgf_volid pgf_uuid pgf_path pgf_size; do
        if [ "$pgf_id" != "$pgf_last" ]; then
            [ -z "$pgf_last" ] || printf '\n'
            printf '%sVM %s%s  %s(%s) %s%s\n' "$C_BOLD$C_CYAN" "$pgf_id" "$C_RESET" "$C_CYAN" "$pgf_type" "$pgf_name" "$C_RESET"
            pgf_last="$pgf_id"
        fi
        printf '\n  %s%-10s%s %-40s %s\n' "$C_BOLD" "$pgf_slot" "$C_RESET" "$pgf_path" "$pgf_size"
        inspect_disk "$pgf_path" "$pgf_size"
    done < "$REFS_FILE"
    return 0
}

# Call: print_remaining_filesystems ARG1 [ARG2] [ARG3] [ARG4] [ARG5] [ARG6]
print_remaining_filesystems() {
    section "Remaining LVM volumes"
    prf_count=0
    while IFS='|' read -r prf_uuid prf_path prf_vg prf_lv prf_size prf_pool prf_origin; do
        if awk -F'|' -v u="$prf_uuid" '$6==u {found=1; exit} END {exit(found ? 0 : 1)}' "$REFS_FILE"; then continue; fi
        printf '\n  %s%-40s%s %s\n' "$C_CYAN" "$prf_path" "$C_RESET" "$prf_size"
        inspect_disk "$prf_path" "$prf_size"
        prf_count=$((prf_count + 1))
    done < "$ALL_LVS_FILE"
    [ "$prf_count" -gt 0 ] || printf '%s\n' "(none)"
    return 0
}

############################################################
# GENERAL HELPERS
############################################################

cleanup_files() {
    [ -z "$ALL_LVS_FILE" ] || rm -f "$ALL_LVS_FILE"
    [ -z "$REFS_FILE" ] || rm -f "$REFS_FILE"
    [ -z "$PARTS_FILE" ] || rm -f "$PARTS_FILE"
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
