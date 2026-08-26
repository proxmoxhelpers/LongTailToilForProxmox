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
    MODE="hot"; MODE_ARG=""
    ARG_COUNT=0; ARG1=""; ARG2=""; ARG3=""; ARG4=""
    SOURCE_FORM=""; SOURCE_INPUT=""; SOURCE_VM_INPUT=""; SOURCE_SELECTOR=""
    SOURCE_VM=""; SOURCE_SLOT=""; SOURCE_ACTIVE=0; SOURCE_STATUS=""
    DEST_FORM=""; DEST_INPUT=""; DEST_VM_INPUT=""; DEST_SELECTOR=""
    BOOT_REQUESTED=0; BOOT_ORDER_APPLIED=0
    CREATED=0; OLD_DETACHED=0; OLD_ARCHIVED=0; REPLACEMENT_FINALIZED=0; NEW_ATTACHED=0; COMPLETE=0; PAUSED_BY_US=0; STOPPED_BY_US=0; DELETE_OLD=0; OLD_DELETED=0; OLD_UNUSED_KEY=""; NEW_UUID=""; ROLLBACK_FAILED=0; DEST_EXISTS=1
    define_colours
    parse_arguments "$@"
    check_elevation
}

# main [ARGS...]
# Call: main "$@"
# Performs preflight and the command's primary operation.
main() {
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    need_commands lvs lvcreate lvrename lvremove qm pvesm blockdev readlink awk grep sed sort tail find mktemp cat
    m_saved_mode="$MODE"; MODE="hot"; resolve_source; MODE="$m_saved_mode"
    [ -n "$SOURCE_POOL" ] || { printf 'Source: %s\nLV attributes: %s\n' "$SOURCE_PATH" "$SOURCE_ATTR"; die "Source is not an LVM-thin volume."; }
    resolve_destination
    [ "$SOURCE_UUID" != "$DEST_OLD_UUID" ] || die "Source and destination refer to the same logical volume."
    validate_pause_detach_capability
    select_storage
    select_new_disk_name
    print_plan
    install_transaction_traps
    create_snapshot
    verify_storage_mapping
    apply_destination_state
    replace_destination_disk
    set_destination_boot_first "$DEST_VM" "$DEST_SLOT"
    restore_destination_state
    delete_archived_disk
    verify_result
    COMPLETE=1
    trap - 0 HUP INT TERM
}

# end
# Call: end
# Prints/finalizes the command result and performs normal completion cleanup.
end() {
    if [ "$DEST_EXISTS" -eq 1 ]; then print_banner "Destination disk overwritten with linked snapshot"
    else print_banner "Destination disk created with linked snapshot"; fi
    printf 'Source:          %s\n' "$SOURCE_PATH"
    printf 'Destination VM:  %s\n' "$DEST_VM"
    printf 'Destination slot: %s\n' "$DEST_SLOT"
    printf 'Disk number:     disk-%s\n' "$DEST_DISK_NUMBER"
    printf 'Snapshot:        %s\n' "$FINAL_VOLID"
    if [ "$DEST_EXISTS" -eq 1 ]; then
        if [ "$DELETE_OLD" -eq 1 ]; then printf 'Old volume:      %s (deleted after successful replacement)\n' "$DEST_OLD_VOLID"
        else printf 'Old volume:      %s -> %s (preserved as unusedN)\n' "$DEST_OLD_VOLID" "$ARCHIVE_VOLID"; fi
    else
        printf 'Old volume:      none\n'
    fi
    printf 'State mode:      %s\n\n' "$MODE"
    dryrun_summary
}

# usage
# Call: usage
# Prints command-line usage and exits only when the caller chooses to exit.
usage() {
    cat <<EOF
$(basename "$0") $SCRIPT_VERSION (project $PROJECT_VERSION)

USAGE
  $(basename "$0") <source-lv-path> <destination-lv-path> [hot|pause|stop|restart] [delete] [boot] [dryrun]
  $(basename "$0") <source-lv-path> <dest-vmid> <dest-N|dest-disk-N|dest-slot|dest-bus> [hot|pause|stop|restart] [delete] [boot] [dryrun]
  $(basename "$0") <source-vmid> <N|source-disk-N|source-slot|unusedN> <destination-lv-path> [hot|pause|stop|restart] [delete] [boot] [dryrun]
  $(basename "$0") <source-vmid> <N|source-disk-N|source-slot|unusedN> <dest-vmid> <dest-N|dest-disk-N|dest-slot|dest-bus> [hot|pause|stop|restart] [delete] [boot] [dryrun]

DESCRIPTION
  Creates an LVM-thin snapshot from the source and places it on the requested destination
  VM. Existing destination disks are replaced transactionally; empty exact/bus
  destinations create a new disk.

SOURCE SELECTORS
  <source-lv-path>      Full LVM path.
  <source-vmid> N|disk-N  Resolve a managed vm-/base- backing volume.
  <source-vmid> sata0   Resolve an exact configured QEMU disk slot.
  <source-vmid> unusedN Resolve an exact detached/unused storage-backed disk reference.
  Source slots such as sata0, ide2, scsi4, and virtio0 must already exist.

DESTINATION SELECTORS
  <destination-lv-path>
               Must resolve to an LVM LV attached as exactly one active disk
               on exactly one QEMU VM. Zero or multiple active QEMU references
               are refused; unusedN-only references do not select a destination.
  N or disk-N  Target that backing disk number. If absent, create it on first free SCSI.
  sata0        Use exactly sata0; replace it if occupied, create there if empty.
  ide2         Use exactly ide2.
  scsi4        Use exactly scsi4.
  virtio0      Use exactly virtio0.
  sata         Use the first free SATA slot and choose a free backing disk number.
  ide          Use the first free IDE slot and choose a free backing disk number.
  scsi         Use the first free SCSI slot and choose a free backing disk number.
  virtio       Use the first free VirtIO slot and choose a free backing disk number.

DESTINATION VM STATE
  default/hot  Replace/add without pausing or stopping the destination VM.
  pause        Pause a running destination VM during replacement, then resume.
               For SCSI targets, pause requires a shared controller with another
               active SCSI disk. virtio-scsi-single and last-SCSI-controller
               removal are refused before mutation because Proxmox rejects that
               hot-unplug while the VM is suspended.
  stop         Stop a running destination VM and leave it stopped.
  restart      Stop a running destination VM, change the disk, then start it.

OPTIONAL KEYWORDS
  delete       Permanently remove the displaced old disk after successful verification.
               Has no effect when the selected destination slot/disk was empty.
  boot         Make the actual destination slot first in the VM boot order.
  dryrun       Perform real read-only preflight and print mutations without executing them.

  hot, pause, stop, restart, delete, boot, dryrun and --dryrun may appear anywhere.

EXAMPLES
  $(basename "$0") 123 sata0 456 sata0 boot dryrun
  $(basename "$0") 123 disk-0 456 virtio delete restart boot dryrun
  $(basename "$0") /dev/pve/vm-123-disk-0 456 scsi4 pause dryrun
  $(basename "$0") /dev/pve/vm-123-disk-0 /dev/pve/vm-456-disk-1 delete dryrun

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
# SOURCE RESOLUTION / STATE
############################################################

# set_state_mode MODE
# Selects at most one of hot/pause/stop/restart; hot is the default.
# Call: set_state_mode MODE
set_state_mode() {
    ssm_new="$1"
    if [ -n "${MODE_ARG:-}" ] && [ "$MODE_ARG" != "$ssm_new" ]; then die "Choose only one of pause, stop, or restart."; fi
    MODE="$ssm_new"; MODE_ARG="$ssm_new"
}

# normalize_disk_number VALUE
# Prints N for N or disk-N; exits nonzero for another token.
normalize_disk_number() (
    ndn_value="$1"
    case "$ndn_value" in
        disk-[0-9]*) ndn_value="${ndn_value#disk-}" ;;
        [0-9]*) ;;
        *) exit 1 ;;
    esac
    case "$ndn_value" in ''|*[!0-9]*) exit 1 ;; esac
    printf '%s\n' "$ndn_value"
)

# disk_slot_limit BUS
# Prints the highest supported Proxmox QEMU disk index for a bus.
# Call: disk_slot_limit BUS
disk_slot_limit() {
    case "$1" in
        ide) printf '%s\n' 3 ;;
        sata) printf '%s\n' 5 ;;
        scsi) printf '%s\n' 30 ;;
        virtio) printf '%s\n' 15 ;;
        *) return 1 ;;
    esac
}

# valid_disk_slot SLOT
# Returns success only for a supported ideN/sataN/scsiN/virtioN slot.
valid_disk_slot() (
    vds_slot="$1"
    case "$vds_slot" in
        ide*) vds_bus="ide"; vds_num="${vds_slot#ide}" ;;
        sata*) vds_bus="sata"; vds_num="${vds_slot#sata}" ;;
        scsi*) vds_bus="scsi"; vds_num="${vds_slot#scsi}" ;;
        virtio*) vds_bus="virtio"; vds_num="${vds_slot#virtio}" ;;
        *) exit 1 ;;
    esac
    case "$vds_num" in ''|*[!0-9]*) exit 1 ;; esac
    vds_max="$(disk_slot_limit "$vds_bus")" || exit 1
    [ "$vds_num" -le "$vds_max" ]
)

# first_free_bus_slot VMID BUS
# Prints the first unused slot on ide/sata/scsi/virtio within Proxmox limits.
first_free_bus_slot() (
    ffbs_vm="$1"; ffbs_bus="$2"
    ffbs_max="$(disk_slot_limit "$ffbs_bus")" || exit 1
    ffbs_cfg="$(qm config "$ffbs_vm")"; ffbs_i=0
    while [ "$ffbs_i" -le "$ffbs_max" ]; do
        printf '%s\n' "$ffbs_cfg" | grep -qE "^${ffbs_bus}${ffbs_i}:" || { printf '%s%s\n' "$ffbs_bus" "$ffbs_i"; exit 0; }
        ffbs_i=$((ffbs_i + 1))
    done
    exit 1
)

# destination_selector_kind SELECTOR
# Prints disk, slot, or bus for supported destination selector syntax.
destination_selector_kind() (
    dsk_value="$1"
    if normalize_disk_number "$dsk_value" >/dev/null 2>&1; then printf '%s\n' disk; exit 0; fi
    case "$dsk_value" in ide|sata|scsi|virtio) printf '%s\n' bus; exit 0 ;; esac
    valid_disk_slot "$dsk_value" || exit 1
    printf '%s\n' slot
)

# resolve_vm_disk_slot VMID SELECTOR
#
# Description:
#   Resolves an explicit QEMU slot or backing disk number to exactly one
#   configured storage-backed disk slot.
#
# Usage:
#   resolve_vm_disk_slot VMID SELECTOR
#
# Arguments:
#   SELECTOR may be N, disk-N, scsiN, sataN, virtioN, ideN or unusedN.
#
# Output:
#   Prints the matching slot.
#
# Returns:
#   0 for one match, nonzero via die for absent/ambiguous selectors.
############################################################
resolve_vm_disk_slot() {
    rvds_vm="$1"; rvds_selector="$2"
    case "$rvds_selector" in
        scsi[0-9]*|sata[0-9]*|virtio[0-9]*|ide[0-9]*)
            valid_disk_slot "$rvds_selector" || die "Unsupported QEMU disk slot: $rvds_selector"
            rvds_value="$(disk_value "$rvds_vm" "$rvds_selector")"
            [ -n "$rvds_value" ] || die "VM $rvds_vm has no disk at $rvds_selector."
            printf '%s\n' "$rvds_selector"
            return 0
            ;;
        unused[0-9]*)
            rvds_value="$(disk_value "$rvds_vm" "$rvds_selector")"
            [ -n "$rvds_value" ] || die "VM $rvds_vm has no disk at $rvds_selector."
            printf '%s\n' "$rvds_selector"
            return 0
            ;;
    esac

    rvds_num="$(normalize_disk_number "$rvds_selector" 2>/dev/null || :)"
    [ -n "$rvds_num" ] || die "Disk selector must be N, disk-N, or an exact QEMU disk slot."

    rvds_slots="$(qm config "$rvds_vm" | awk -F': ' -v n="$rvds_num" '
        $1 ~ /^(scsi|sata|virtio|ide|unused)[0-9]+$/ {
            split($2,a,","); v=a[1]; sub(/^[^:]+:/,"",v)
            if (v ~ "^(vm|base)-[0-9]+-disk-" n "$") print $1
        }')"
    rvds_count="$(printf '%s\n' "$rvds_slots" | awk 'NF {n++} END {print n+0}')"

    [ "$rvds_count" -gt 0 ] || die "VM $rvds_vm has no configured vm/base backing volume with disk number $rvds_num."
    [ "$rvds_count" -eq 1 ] || { printf '%s\n' "$rvds_slots" >&2; die "Disk number $rvds_num matches multiple VM slots; use an explicit source slot."; }
    printf '%s\n' "$rvds_slots" | awk 'NF {print; exit}'
}

# discover_source_owner
#
# Description:
#   Discovers the unique active local QEMU VM slot referring to SOURCE_PATH by
#   LV UUID. An unreferenced source is valid in hot mode. A non-hot state mode
#   requires one unambiguous active source VM.
#
# Usage:
#   discover_source_owner
#
# Arguments:
#   Uses SOURCE_PATH and SOURCE_UUID.
#
# Output:
#   Sets SOURCE_VM, SOURCE_SLOT, SOURCE_ACTIVE and SOURCE_STATUS.
#
# Returns:
#   0 for a usable source.
############################################################
discover_source_owner() {
    dso_refs="$(guest_volume_references | while IFS='|' read -r dso_cfg dso_slot dso_volid; do
        case "$dso_cfg" in */qemu-server/*) ;; *) continue ;; esac
        case "$dso_slot" in unused*) continue ;; esac
        dso_path="$(pvesm path "$dso_volid" 2>/dev/null || :)"
        [ -n "$dso_path" ] || continue
        lvs "$dso_path" >/dev/null 2>&1 || continue
        dso_uuid="$(lvs --noheadings -o lv_uuid "$dso_path" 2>/dev/null | trim)"
        [ "$dso_uuid" = "$SOURCE_UUID" ] || continue
        dso_id="${dso_cfg##*/}"; dso_id="${dso_id%.conf}"
        printf '%s|%s\n' "$dso_id" "$dso_slot"
    done | sort -u)"
    dso_count="$(printf '%s\n' "$dso_refs" | awk 'NF {n++} END {print n+0}')"
    SOURCE_VM=""; SOURCE_SLOT=""; SOURCE_ACTIVE=0; SOURCE_STATUS=""
    if [ "$dso_count" -eq 1 ]; then
        SOURCE_VM="${dso_refs%%|*}"; SOURCE_SLOT="${dso_refs#*|}"
        if [ -f "/etc/pve/qemu-server/${SOURCE_VM}.conf" ]; then
            SOURCE_ACTIVE=1
            SOURCE_STATUS="$(qm status "$SOURCE_VM" 2>/dev/null | awk '{print $2}' || :)"
        else
            SOURCE_VM=""; SOURCE_SLOT=""; SOURCE_ACTIVE=0
        fi
    elif [ "$dso_count" -gt 1 ]; then
        if [ "$MODE" != "hot" ]; then printf '%s\n' "$dso_refs" >&2; die "Source LV is actively referenced by multiple QEMU disks; cannot apply one VM state mode safely."; fi
        warn "Source LV has multiple active QEMU references; hot mode will not change guest state."
    elif [ "$MODE" != "hot" ]; then
        die "$MODE was requested, but the source LV is not attached to one active local QEMU VM."
    fi
}

# resolve_source
# Resolves either a full LV path or VMID + disk selector to SOURCE_* metadata.
# Call: resolve_source ARG1 [ARG2]
resolve_source() {
    if [ "$SOURCE_FORM" = "path" ]; then
        assert_lv_exists "$SOURCE_INPUT"
        SOURCE_PATH="$(canonical_lv_path "$SOURCE_INPUT")"
        SOURCE_UUID="$(lvs --noheadings -o lv_uuid "$SOURCE_PATH" 2>/dev/null | trim)"
        [ -n "$SOURCE_UUID" ] || die "Could not determine LV UUID for $SOURCE_PATH."
        discover_source_owner
    else
        SOURCE_VM="$SOURCE_VM_INPUT"
        require_qemu_vm "$SOURCE_VM"
        SOURCE_SLOT="$(resolve_vm_disk_slot "$SOURCE_VM" "$SOURCE_SELECTOR")"
        SOURCE_VALUE="$(disk_value "$SOURCE_VM" "$SOURCE_SLOT")"
        [ -n "$SOURCE_VALUE" ] || die "VM $SOURCE_VM has no disk at $SOURCE_SLOT."
        case "$SOURCE_VALUE" in *,media=cdrom*) die "Refusing CD-ROM/cloud media as a source disk." ;; esac
        SOURCE_VOLID="${SOURCE_VALUE%%,*}"
        SOURCE_INPUT_PATH="$(pvesm path "$SOURCE_VOLID" 2>/dev/null || :)"
        [ -n "$SOURCE_INPUT_PATH" ] || die "Could not resolve $SOURCE_VOLID."
        assert_lv_exists "$SOURCE_INPUT_PATH"
        SOURCE_PATH="$(canonical_lv_path "$SOURCE_INPUT_PATH")"
        SOURCE_UUID="$(lvs --noheadings -o lv_uuid "$SOURCE_PATH" 2>/dev/null | trim)"
        case "$SOURCE_SLOT" in unused*) SOURCE_ACTIVE=0; SOURCE_STATUS="" ;; *)
            SOURCE_ACTIVE=1
            SOURCE_STATUS="$(qm status "$SOURCE_VM" 2>/dev/null | awk '{print $2}' || :)"
            ;;
        esac
        if [ "$MODE" != "hot" ] && [ "$SOURCE_ACTIVE" -eq 0 ]; then die "$MODE was requested, but $SOURCE_SLOT is not an active VM disk."; fi
    fi
    SOURCE_VG="$(lvs --noheadings -o vg_name "$SOURCE_PATH" 2>/dev/null | trim)"
    SOURCE_LV="$(lvs --noheadings -o lv_name "$SOURCE_PATH" 2>/dev/null | trim)"
    SOURCE_POOL="$(lvs --noheadings -o pool_lv "$SOURCE_PATH" 2>/dev/null | trim)"
    SOURCE_ATTR="$(lvs --noheadings -o lv_attr "$SOURCE_PATH" 2>/dev/null | trim)"
    SOURCE_SIZE_BYTES="$(lvs --noheadings --units b --nosuffix -o lv_size "$SOURCE_PATH" 2>/dev/null | awk 'NF {printf "%.0f\n", $1; exit}' || :)"
    [ -n "$SOURCE_VG" ] && [ -n "$SOURCE_LV" ] || die "Could not resolve source LVM metadata."
    case "$SOURCE_SIZE_BYTES" in ''|*[!0-9]*) die "Could not determine source LV size." ;; esac
}

# apply_source_state
# Applies pause/stop/restart preparation to the source VM when requested.
# Call: apply_source_state ARG1 [ARG2]
apply_source_state() {
    [ "$SOURCE_ACTIVE" -eq 1 ] || return 0
    case "$MODE" in
        hot) info "Source VM state: ${SOURCE_STATUS:-unknown}; hot mode leaves it unchanged." ;;
        pause)
            if [ "$SOURCE_STATUS" = "running" ]; then
                info "Pausing source VM $SOURCE_VM..."
                dryrun_cmd qm suspend "$SOURCE_VM"
                PAUSED_BY_US=1
            else info "Source VM $SOURCE_VM is ${SOURCE_STATUS:-unknown}; no pause is required."; fi
            ;;
        stop|restart)
            if [ "$SOURCE_STATUS" != "stopped" ]; then
                info "Stopping source VM $SOURCE_VM..."
                dryrun_cmd qm stop "$SOURCE_VM"
                STOPPED_BY_US=1
                if ! dryrun_enabled; then [ "$(qm status "$SOURCE_VM" | awk '{print $2}')" = "stopped" ] || die "Source VM $SOURCE_VM did not stop."; fi
            else info "Source VM $SOURCE_VM is already stopped."; fi
            ;;
    esac
}

# restore_source_state
# Resumes/restarts only a source VM whose state this invocation changed.
restore_source_state() {
    if [ "$MODE" = "pause" ] && [ "$PAUSED_BY_US" -eq 1 ]; then
        info "Resuming source VM $SOURCE_VM..."
        dryrun_cmd qm resume "$SOURCE_VM" || { warn "Could not resume source VM $SOURCE_VM."; return 1; }
        PAUSED_BY_US=0
    elif [ "$MODE" = "restart" ] && [ "$STOPPED_BY_US" -eq 1 ]; then
        info "Starting source VM $SOURCE_VM..."
        dryrun_cmd qm start "$SOURCE_VM" || { warn "Could not restart source VM $SOURCE_VM."; return 1; }
        STOPPED_BY_US=0
    fi
    return 0
}


############################################################
# DESTINATION RESOLUTION / STATE
############################################################

# resolve_destination
# Resolves either full LV path or VMID + disk selector to one active QEMU slot.
# select_free_destination_disk_number VG
# Selects the next free managed disk number and uses the destination family.
# Call: select_free_destination_disk_number VG
select_free_destination_disk_number() {
    sfddn_vg="$1"
    sfddn_highest="$(printf '%s\n' "$DEST_CONFIG" | grep -oE "(vm|base)-[0-9]+-disk-[0-9]+" | sed -E 's/.*-disk-([0-9]+)$/\1/' | sort -n | tail -n1 || :)"
    if [ -n "$sfddn_highest" ]; then sfddn_num=$((sfddn_highest + 1)); else sfddn_num=0; fi
    while :; do
        sfddn_name="${DEST_PREFIX}-${DEST_VM}-disk-${sfddn_num}"
        sfddn_busy=0
        printf '%s\n' "$DEST_CONFIG" | grep -qE "(vm|base)-[0-9]+-disk-${sfddn_num}([,[:space:]]|$)" && sfddn_busy=1 || :
        lvs "${sfddn_vg}/${sfddn_name}" >/dev/null 2>&1 && sfddn_busy=1 || :
        [ "$sfddn_busy" -eq 0 ] && break
        sfddn_num=$((sfddn_num + 1))
    done
    DEST_DISK_NUMBER="$sfddn_num"
    DEST_OLD_LV="$sfddn_name"
}

# Call: resolve_destination ARG1 [ARG2]
resolve_destination() {
    DEST_EXISTS=1
    DEST_PREFIX="vm"

    if [ "$DEST_FORM" = "path" ]; then
        assert_lv_exists "$DEST_INPUT"
        DEST_OLD_PATH="$(canonical_lv_path "$DEST_INPUT")"
        DEST_OLD_UUID="$(lvs --noheadings -o lv_uuid "$DEST_OLD_PATH" 2>/dev/null | trim)"
        [ -n "$DEST_OLD_UUID" ] || die "Could not determine destination LV UUID."
        rd_refs="$(guest_volume_references | while IFS='|' read -r rd_cfg rd_slot rd_volid; do
            case "$rd_cfg" in */qemu-server/*) ;; *) continue ;; esac
            case "$rd_slot" in unused*) continue ;; esac
            rd_path="$(pvesm path "$rd_volid" 2>/dev/null || :)"
            [ -n "$rd_path" ] || continue
            lvs "$rd_path" >/dev/null 2>&1 || continue
            rd_uuid="$(lvs --noheadings -o lv_uuid "$rd_path" 2>/dev/null | trim)"
            [ "$rd_uuid" = "$DEST_OLD_UUID" ] || continue
            rd_id="${rd_cfg##*/}"; rd_id="${rd_id%.conf}"
            printf '%s|%s|%s\n' "$rd_id" "$rd_slot" "$rd_volid"
        done | sort -u)"
        rd_count="$(printf '%s\n' "$rd_refs" | awk 'NF {n++} END {print n+0}')"
        [ "$rd_count" -gt 0 ] || die "Destination LV is not attached as an active disk to a QEMU VM."
        [ "$rd_count" -eq 1 ] || { printf '%s\n' "$rd_refs" >&2; die "Destination LV has multiple active QEMU references."; }
        DEST_VM="${rd_refs%%|*}"; rd_rest="${rd_refs#*|}"; DEST_SLOT="${rd_rest%%|*}"; DEST_OLD_VOLID="${rd_rest#*|}"
        require_qemu_vm "$DEST_VM"
        DEST_CONFIG="$(qm config "$DEST_VM")"
        if printf '%s\n' "$DEST_CONFIG" | grep -qE '^template:[[:space:]]*1([[:space:]]|$)'; then DEST_PREFIX="base"; fi
    else
        DEST_VM="$DEST_VM_INPUT"
        require_qemu_vm "$DEST_VM"
        DEST_CONFIG="$(qm config "$DEST_VM")"
        if printf '%s\n' "$DEST_CONFIG" | grep -qE '^template:[[:space:]]*1([[:space:]]|$)'; then DEST_PREFIX="base"; fi

        if rd_kind="$(destination_selector_kind "$DEST_SELECTOR" 2>/dev/null)"; then :
        else die "Destination selector must be N, disk-N, an exact QEMU disk slot, or ide/sata/scsi/virtio."; fi

        case "$rd_kind" in
            bus)
                DEST_SLOT="$(first_free_bus_slot "$DEST_VM" "$DEST_SELECTOR")" || die "VM $DEST_VM has no free $DEST_SELECTOR disk slot."
                DEST_EXISTS=0
                ;;
            slot)
                valid_disk_slot "$DEST_SELECTOR" || die "Unsupported destination disk slot: $DEST_SELECTOR"
                DEST_SLOT="$DEST_SELECTOR"
                rd_value="$(disk_value "$DEST_VM" "$DEST_SLOT" 2>/dev/null || :)"
                if [ -z "$rd_value" ]; then DEST_EXISTS=0; fi
                ;;
            disk)
                rd_num="$(normalize_disk_number "$DEST_SELECTOR")"
                DEST_DISK_NUMBER="$rd_num"
                rd_slots="$(printf '%s\n' "$DEST_CONFIG" | awk -F': ' -v n="$rd_num" '
                    $1 ~ /^(scsi|sata|virtio|ide|unused)[0-9]+$/ {
                        split($2,a,","); v=a[1]; sub(/^[^:]+:/,"",v)
                        if (v ~ "^(vm|base)-[0-9]+-disk-" n "$") print $1
                    }')"
                rd_count="$(printf '%s\n' "$rd_slots" | awk 'NF {n++} END {print n+0}')"
                if [ "$rd_count" -gt 1 ]; then
                    printf '%s\n' "$rd_slots" >&2
                    die "Disk number $rd_num matches multiple destination VM slots; use an explicit destination slot."
                fi
                if [ "$rd_count" -eq 0 ]; then
                    DEST_EXISTS=0
                    DEST_SLOT="$(first_free_scsi "$DEST_VM")" || die "VM $DEST_VM has no free SCSI slot for the new disk."
                else
                    [ "$rd_count" -eq 1 ] || { printf '%s\n' "$rd_slots" >&2; die "Disk number $rd_num matches multiple destination VM slots."; }
                    DEST_SLOT="$(printf '%s\n' "$rd_slots" | awk 'NF {print; exit}')"
                fi
                ;;
        esac
    fi

    if printf '%s\n' "$DEST_CONFIG" | grep -qE '^lock:[[:space:]]*'; then die "Destination VM $DEST_VM is locked; resolve the lock first."; fi
    DEST_STATUS="$(qm status "$DEST_VM" 2>/dev/null | awk '{print $2}' || :)"

    if [ "$DEST_EXISTS" -eq 0 ]; then
        DEST_OPTIONS=""
        DEST_OLD_VALUE=""
        DEST_OLD_VOLID=""
        DEST_OLD_PATH=""
        DEST_OLD_UUID=""
        DEST_OLD_STORAGE_ID=""
        DEST_VG="$SOURCE_VG"
        DEST_OLD_POOL="$SOURCE_POOL"
        if [ -z "${DEST_DISK_NUMBER:-}" ]; then select_free_destination_disk_number "$DEST_VG"
        else DEST_OLD_LV="${DEST_PREFIX}-${DEST_VM}-disk-${DEST_DISK_NUMBER}"; fi
        return 0
    fi

    DEST_OLD_VALUE="$(disk_value "$DEST_VM" "$DEST_SLOT")"
    [ -n "$DEST_OLD_VALUE" ] || die "Destination slot $DEST_SLOT disappeared during preflight."
    case "$DEST_OLD_VALUE" in *,media=cdrom*) die "Refusing to overwrite CD-ROM/cloud media."; esac

    if [ "$DEST_FORM" = "vm" ]; then
        DEST_OLD_VOLID="${DEST_OLD_VALUE%%,*}"
        rd_path="$(pvesm path "$DEST_OLD_VOLID" 2>/dev/null || :)"
        [ -n "$rd_path" ] || die "Could not resolve destination volume $DEST_OLD_VOLID."
        assert_lv_exists "$rd_path"
        DEST_OLD_PATH="$(canonical_lv_path "$rd_path")"
        DEST_OLD_UUID="$(lvs --noheadings -o lv_uuid "$DEST_OLD_PATH" 2>/dev/null | trim)"
    fi

    [ "${DEST_OLD_VALUE%%,*}" = "$DEST_OLD_VOLID" ] || die "Destination slot changed during preflight."
    DEST_OPTIONS="$(printf '%s\n' "$DEST_OLD_VALUE" | awk -F',' '{out=""; for(i=2;i<=NF;i++) if($i !~ /^size=/) out=out "," $i; print out}')"
    DEST_VG="$(lvs --noheadings -o vg_name "$DEST_OLD_PATH" 2>/dev/null | trim)"
    DEST_OLD_LV="$(lvs --noheadings -o lv_name "$DEST_OLD_PATH" 2>/dev/null | trim)"
    DEST_OLD_POOL="$(lvs --noheadings -o pool_lv "$DEST_OLD_PATH" 2>/dev/null | trim)"
    [ -n "$DEST_VG" ] && [ -n "$DEST_OLD_LV" ] || die "Destination disk is not LVM-backed."
    DEST_OLD_STORAGE_ID="${DEST_OLD_VOLID%%:*}"
    case "$DEST_OLD_LV" in
        vm-*-disk-*) DEST_PREFIX="vm" ;;
        base-*-disk-*) DEST_PREFIX="base" ;;
        *) die "Destination LV must use a managed vm-VMID-disk-N or base-VMID-disk-N naming scheme." ;;
    esac
    DEST_DISK_NUMBER="${DEST_OLD_LV##*-disk-}"
    case "$DEST_DISK_NUMBER" in ''|*[!0-9]*) die "Could not determine destination disk number from $DEST_OLD_LV." ;; esac
}


# validate_pause_detach_capability
# Refuses pause-mode SCSI replacement topologies that Proxmox cannot safely
# hot-unplug while the VM is suspended.
# Call: validate_pause_detach_capability ARG1
validate_pause_detach_capability() {
    [ "$MODE" = "pause" ] || return 0
    [ "$DEST_EXISTS" -eq 1 ] || return 0
    case "$DEST_STATUS" in running|paused) ;; *) return 0 ;; esac
    case "$DEST_SLOT" in scsi[0-9]*) ;; *) return 0 ;; esac

    vpdc_scsihw="$(printf '%s\n' "$DEST_CONFIG" | sed -n 's/^scsihw:[[:space:]]*//p' | head -n1)"
    if [ "$vpdc_scsihw" = "virtio-scsi-single" ]; then
        die "pause mode cannot safely replace $DEST_SLOT on VM $DEST_VM while using virtio-scsi-single; Proxmox hot-unplugs the per-disk controller and rejects it while suspended. Use hot, stop, or restart."
    fi

    vpdc_count="$(printf '%s\n' "$DEST_CONFIG" | awk -F': ' '$1 ~ /^scsi[0-9]+$/ {n++} END {print n+0}')"
    if [ "$vpdc_count" -le 1 ]; then
        die "pause mode cannot safely replace the only active SCSI disk on VM $DEST_VM while suspended; Proxmox attempts to remove the SCSI controller. Use hot, stop, or restart, or keep another SCSI disk on the shared controller."
    fi
}

# apply_destination_state
# Applies the requested hot/pause/stop/restart policy to the VM losing a disk.
# Call: apply_destination_state ARG1 [ARG2]
apply_destination_state() {
    case "$MODE" in
        hot) info "Destination VM state: ${DEST_STATUS:-unknown}; hot-swap mode leaves it unchanged." ;;
        pause)
            if [ "$DEST_STATUS" = "running" ]; then
                info "Pausing destination VM $DEST_VM before replacing $DEST_SLOT..."
                dryrun_cmd qm suspend "$DEST_VM"
                PAUSED_BY_US=1
            else info "Destination VM $DEST_VM is ${DEST_STATUS:-unknown}; no pause is required."; fi
            ;;
        stop|restart)
            if [ "$DEST_STATUS" != "stopped" ]; then
                info "Stopping destination VM $DEST_VM before replacing $DEST_SLOT..."
                dryrun_cmd qm stop "$DEST_VM"
                STOPPED_BY_US=1
                if ! dryrun_enabled; then [ "$(qm status "$DEST_VM" | awk '{print $2}')" = "stopped" ] || die "Destination VM $DEST_VM did not stop."; fi
            else info "Destination VM $DEST_VM is already stopped."; fi
            ;;
    esac
}

# restore_destination_state
# Resumes/restarts only a destination VM whose state this invocation changed.
restore_destination_state() {
    if [ "$MODE" = "pause" ] && [ "$PAUSED_BY_US" -eq 1 ]; then
        info "Resuming destination VM $DEST_VM..."
        dryrun_cmd qm resume "$DEST_VM" || { warn "Could not resume destination VM $DEST_VM."; return 1; }
        PAUSED_BY_US=0
    elif [ "$MODE" = "restart" ] && [ "$STOPPED_BY_US" -eq 1 ]; then
        info "Starting destination VM $DEST_VM..."
        dryrun_cmd qm start "$DEST_VM" || { warn "Could not restart destination VM $DEST_VM."; return 1; }
        STOPPED_BY_US=0
    fi
    return 0
}

# old_unused_key
# Prints the unusedN key currently preserving the displaced destination volume.
# Call: old_unused_key ARG1 [ARG2]
old_unused_key() {
    ouk_volid="${1:-$DEST_OLD_VOLID}"
    qm config "$DEST_VM" 2>/dev/null | awk -F': ' -v vol="$ouk_volid" '
        $1 ~ /^unused[0-9]+$/ {split($2,a,","); if(a[1]==vol) print $1}
    ' | head -n1
}

# lv_name_by_uuid VG UUID
# Prints the current LV name for an exact LV UUID in one VG.
# Call: lv_name_by_uuid VG UUID
lv_name_by_uuid() {
    lnbu_vg="$1"; lnbu_uuid="$2"
    lvs --noheadings -o vg_name,lv_name,lv_uuid 2>/dev/null | awk -v vg="$lnbu_vg" -v uuid="$lnbu_uuid" '
        $1 == vg && $3 == uuid {print $2; exit}
    '
}

# rewrite_unused_reference KEY EXPECTED_VOLID NEW_VOLID
# Rewrites only an unusedN config reference, without invoking qm --delete and
# therefore without triggering Proxmox storage deletion semantics.
# Call: rewrite_unused_reference KEY EXPECTED_VOLID NEW_VOLID
rewrite_unused_reference() {
    rur_key="$1"; rur_expected="$2"; rur_new="$3"
    rur_config="/etc/pve/qemu-server/${DEST_VM}.conf"
    [ -f "$rur_config" ] || return 1

    if dryrun_enabled; then
        dryrun_print_shell "rewrite ${rur_key}: ${rur_expected} -> ${rur_new} in $rur_config without deleting storage"
        return 0
    fi

    rur_tmp="$(mktemp)" || return 1
    if ! awk -v key="$rur_key" -v expected="$rur_expected" -v replacement="$rur_new" '
        BEGIN {prefix=key ": "; found=0; bad=0}
        index($0,prefix)==1 {
            rest=substr($0,length(prefix)+1)
            comma=index(rest,",")
            if (comma) {vol=substr(rest,1,comma-1); suffix=substr(rest,comma)}
            else {vol=rest; suffix=""}
            if (vol != expected) {bad=1; print; next}
            print prefix replacement suffix
            found=1
            next
        }
        {print}
        END {
            if (bad) exit 42
            if (!found) exit 43
        }
    ' "$rur_config" > "$rur_tmp"; then
        rm -f "$rur_tmp"
        return 1
    fi
    if ! cat "$rur_tmp" > "$rur_config"; then rm -f "$rur_tmp"; return 1; fi
    rm -f "$rur_tmp"
    [ "$(disk_volid "$DEST_VM" "$rur_key" 2>/dev/null || :)" = "$rur_new" ]
}

# remove_unused_reference_only KEY EXPECTED_VOLID
# Removes only the config line. It deliberately does not use qm --delete,
# because deleting an unusedN entry may also free its backing storage volume.
# Call: remove_unused_reference_only KEY EXPECTED_VOLID
remove_unused_reference_only() {
    ruro_key="$1"; ruro_expected="$2"
    ruro_config="/etc/pve/qemu-server/${DEST_VM}.conf"
    ruro_current="$(disk_volid "$DEST_VM" "$ruro_key" 2>/dev/null || :)"
    [ -n "$ruro_current" ] || return 0
    [ "$ruro_current" = "$ruro_expected" ] || return 1

    if dryrun_enabled; then
        dryrun_print_shell "remove config-only ${ruro_key}: ${ruro_expected} from $ruro_config without deleting storage"
        return 0
    fi

    ruro_tmp="$(mktemp)" || return 1
    if ! awk -v key="$ruro_key" 'index($0,key ": ") != 1 {print}' "$ruro_config" > "$ruro_tmp"; then
        rm -f "$ruro_tmp"
        return 1
    fi
    if ! cat "$ruro_tmp" > "$ruro_config"; then rm -f "$ruro_tmp"; return 1; fi
    rm -f "$ruro_tmp"
    [ -z "$(disk_value "$DEST_VM" "$ruro_key" 2>/dev/null || :)" ]
}

# add_unused_reference_only KEY VOLID
# Adds back one unusedN config reference after a failed explicit LV deletion.
# Call: add_unused_reference_only KEY VOLID
add_unused_reference_only() {
    auro_key="$1"; auro_volid="$2"
    auro_config="/etc/pve/qemu-server/${DEST_VM}.conf"
    [ -z "$(disk_value "$DEST_VM" "$auro_key" 2>/dev/null || :)" ] || return 1

    if dryrun_enabled; then
        dryrun_print_shell "add config-only ${auro_key}: ${auro_volid} to $auro_config"
        return 0
    fi

    auro_tmp="$(mktemp)" || return 1
    cat "$auro_config" > "$auro_tmp" || { rm -f "$auro_tmp"; return 1; }
    printf '%s: %s\n' "$auro_key" "$auro_volid" >> "$auro_tmp" || { rm -f "$auro_tmp"; return 1; }
    if ! cat "$auro_tmp" > "$auro_config"; then rm -f "$auro_tmp"; return 1; fi
    rm -f "$auro_tmp"
    [ "$(disk_volid "$DEST_VM" "$auro_key" 2>/dev/null || :)" = "$auro_volid" ]
}

# rollback_old_disk
# Restores the original destination disk by LV UUID. It never deletes unusedN
# through qm, so an attempted rollback cannot free the disk it is restoring.
rollback_old_disk() {
    [ "$OLD_DETACHED" -eq 1 ] || return 0
    [ "$NEW_ATTACHED" -eq 0 ] || { ROLLBACK_FAILED=1; return 1; }

    warn "Attempting to restore original destination disk $DEST_OLD_VOLID at $DEST_SLOT."

    if [ "$REPLACEMENT_FINALIZED" -eq 1 ] && [ "$NEW_VG" = "$DEST_VG" ]; then
        rod_new_name="$(lv_name_by_uuid "$NEW_VG" "$NEW_UUID")"
        if [ -z "$rod_new_name" ]; then
            warn "Could not locate replacement LV by UUID during rollback."
            ROLLBACK_FAILED=1
            return 1
        fi
        if [ "$rod_new_name" != "$TEMP_LV_NAME" ]; then
            [ "$rod_new_name" = "$FINAL_LV_NAME" ] || {
                warn "Replacement LV has an unexpected name during rollback: $rod_new_name"
                ROLLBACK_FAILED=1
                return 1
            }
            if ! dryrun_cmd lvrename "$NEW_VG" "$rod_new_name" "$TEMP_LV_NAME"; then
                warn "Could not move the replacement LV out of the original disk number for rollback."
                ROLLBACK_FAILED=1
                return 1
            fi
        fi
        NEW_LV_NAME="$TEMP_LV_NAME"; NEW_LV_PATH="$TEMP_LV_PATH"; NEW_VOLID="$TEMP_VOLID"; REPLACEMENT_FINALIZED=0
    fi

    rod_old_name="$(lv_name_by_uuid "$DEST_VG" "$DEST_OLD_UUID")"
    if dryrun_enabled; then rod_old_name="${rod_old_name:-$ARCHIVE_LV_NAME}"; fi
    if [ -z "$rod_old_name" ]; then
        warn "Original destination LV UUID $DEST_OLD_UUID cannot be found; automatic rollback is stopping without deleting the replacement."
        ROLLBACK_FAILED=1
        return 1
    fi

    if [ "$rod_old_name" != "$DEST_OLD_LV" ]; then
        if ! dryrun_cmd lvrename "$DEST_VG" "$rod_old_name" "$DEST_OLD_LV"; then
            warn "Could not rename original destination LV $rod_old_name back to $DEST_OLD_LV."
            ROLLBACK_FAILED=1
            return 1
        fi
    fi
    OLD_ARCHIVED=0

    if [ -z "$OLD_UNUSED_KEY" ]; then
        OLD_UNUSED_KEY="$(old_unused_key "$ARCHIVE_VOLID")"
        [ -n "$OLD_UNUSED_KEY" ] || OLD_UNUSED_KEY="$(old_unused_key "$DEST_OLD_VOLID")"
    fi

    if [ -n "$OLD_UNUSED_KEY" ]; then
        rod_unused_volid="$(disk_volid "$DEST_VM" "$OLD_UNUSED_KEY" 2>/dev/null || :)"
        case "$rod_unused_volid" in
            "$ARCHIVE_VOLID") ;;
            "$DEST_OLD_VOLID")
                if ! rewrite_unused_reference "$OLD_UNUSED_KEY" "$DEST_OLD_VOLID" "$ARCHIVE_VOLID"; then
                    warn "Could not make the unused reference storage-neutral for rollback."
                    ROLLBACK_FAILED=1
                    return 1
                fi
                ;;
            "")
                OLD_UNUSED_KEY=""
                ;;
            *)
                warn "$OLD_UNUSED_KEY changed unexpectedly during rollback; refusing to overwrite it."
                ROLLBACK_FAILED=1
                return 1
                ;;
        esac
    fi

    if ! dryrun_cmd qm set "$DEST_VM" "--${DEST_SLOT}" "$DEST_OLD_VALUE"; then
        if [ -n "$OLD_UNUSED_KEY" ] && [ "$(disk_volid "$DEST_VM" "$OLD_UNUSED_KEY" 2>/dev/null || :)" = "$ARCHIVE_VOLID" ]; then
            rewrite_unused_reference "$OLD_UNUSED_KEY" "$ARCHIVE_VOLID" "$DEST_OLD_VOLID" || warn "Could not restore the unused reference to $DEST_OLD_VOLID."
        fi
        warn "Could not restore original destination disk automatically; original LV was left intact."
        ROLLBACK_FAILED=1
        return 1
    fi

    if [ -n "$OLD_UNUSED_KEY" ] && [ "$(disk_volid "$DEST_VM" "$OLD_UNUSED_KEY" 2>/dev/null || :)" = "$ARCHIVE_VOLID" ]; then
        if ! remove_unused_reference_only "$OLD_UNUSED_KEY" "$ARCHIVE_VOLID"; then
            warn "Original disk was reattached, but stale $OLD_UNUSED_KEY could not be removed safely."
            ROLLBACK_FAILED=1
            return 1
        fi
    fi

    [ "$(disk_volid "$DEST_VM" "$DEST_SLOT" 2>/dev/null || :)" = "$DEST_OLD_VOLID" ] || {
        warn "Rollback attach verification failed; original LV was left intact."
        ROLLBACK_FAILED=1
        return 1
    }

    OLD_DETACHED=0
    ROLLBACK_FAILED=0
    return 0
}

# Call: select_storage ARG1 [ARG2]
select_storage() {
    [ -f /etc/pve/storage.cfg ] || die "Proxmox storage configuration not found: /etc/pve/storage.cfg"
    ss_matches="$(awk -v wanted_vg="$SOURCE_VG" -v wanted_pool="$SOURCE_POOL" '
        function flush() {
            if (type == "lvmthin" && vg == wanted_vg && pool == wanted_pool &&
                (content == "" || content ~ /(^|,)images(,|$)/)) print id
        }
        /^[^ \t][^:]*:[ \t]*/ {flush(); split($1,h,":"); type=h[1]; id=$2; vg=""; pool=""; content=""; next}
        $1=="vgname" {vg=$2; next}
        $1=="thinpool" {pool=$2; next}
        $1=="content" {content=$2; next}
        END {flush()}
    ' /etc/pve/storage.cfg)"
    ss_count="$(printf '%s\n' "$ss_matches" | awk 'NF {n++} END {print n+0}')"
    case "$ss_count" in
        0) printf 'Source VG:   %s\nSource pool: %s\n' "$SOURCE_VG" "$SOURCE_POOL"; die "Could not find a matching Proxmox lvmthin storage." ;;
        1) STORAGE_ID="$(printf '%s\n' "$ss_matches" | awk 'NF {print; exit}')" ;;
        *) printf 'Multiple matching Proxmox storages:\n%s\n' "$ss_matches" >&2; die "Storage mapping is ambiguous." ;;
    esac
}

# create_snapshot
# Creates the staged linked snapshot and records its stable UUID before any destination mutation.
create_snapshot() {
    info "Creating LVM-thin snapshot..."
    if dryrun_enabled; then dryrun_cmd lvcreate --snapshot --name "$NEW_LV_NAME" "${SOURCE_VG}/${SOURCE_LV}"
    else run_lvm_filtered lvcreate --snapshot --name "$NEW_LV_NAME" "${SOURCE_VG}/${SOURCE_LV}"; fi
    CREATED=1
    if dryrun_enabled; then
        NEW_REAL="$NEW_LV_PATH"; NEW_ORIGIN="$SOURCE_LV"; NEW_POOL="$SOURCE_POOL"; NEW_UUID="dryrun-new-snapshot"
        dryrun_verify "Snapshot LV would exist with expected origin, thin pool, and stable LV UUID"
    else
        lvs "${SOURCE_VG}/${NEW_LV_NAME}" >/dev/null 2>&1 || die "lvcreate returned successfully, but the snapshot cannot be found."
        NEW_REAL="$(lvs --noheadings -o lv_path "${SOURCE_VG}/${NEW_LV_NAME}" 2>/dev/null | trim)"
        NEW_ORIGIN="$(lvs --noheadings -o origin "${SOURCE_VG}/${NEW_LV_NAME}" 2>/dev/null | trim)"
        NEW_POOL="$(lvs --noheadings -o pool_lv "${SOURCE_VG}/${NEW_LV_NAME}" 2>/dev/null | trim)"
        NEW_UUID="$(lvs --noheadings -o lv_uuid "${SOURCE_VG}/${NEW_LV_NAME}" 2>/dev/null | trim)"
        [ -n "$NEW_UUID" ] || die "Could not record the new snapshot LV UUID."
    fi
    [ "$NEW_ORIGIN" = "$SOURCE_LV" ] && [ "$NEW_POOL" = "$SOURCE_POOL" ] || die "Snapshot origin/thin-pool verification failed."
}

# verify_storage_mapping
# Proves the staged Proxmox volume ID resolves to the newly created snapshot LV UUID.
verify_storage_mapping() {
    if dryrun_enabled; then
        PVE_PATH="$NEW_LV_PATH"
        dryrun_verify "Proxmox storage $STORAGE_ID would resolve $NEW_VOLID to replacement LV UUID $NEW_UUID"
        return 0
    fi

    PVE_PATH="$(pvesm path "$NEW_VOLID" 2>/dev/null || :)"
    [ -n "$PVE_PATH" ] || die "Proxmox storage could not resolve the new snapshot."
    vsm_uuid="$(lvs --noheadings -o lv_uuid "$PVE_PATH" 2>/dev/null | trim || :)"
    [ -n "$vsm_uuid" ] || die "Proxmox resolved $NEW_VOLID, but the resolved path is not an identifiable LVM LV."
    [ "$vsm_uuid" = "$NEW_UUID" ] || {
        printf 'Expected LV UUID: %s\nResolved LV UUID: %s\nResolved path:    %s\n' "$NEW_UUID" "$vsm_uuid" "$PVE_PATH" >&2
        die "Proxmox storage mapping resolves to a different LV."
    }
    NEW_REAL="$PVE_PATH"
}


# set_destination_boot_first VMID SLOT
#
# Description:
#   Moves SLOT to the front of the Proxmox boot order when the boot keyword
#   was requested, preserving the remaining explicit order.
#
# Usage:
#   set_destination_boot_first VMID SLOT
############################################################
set_destination_boot_first() {
    [ "$BOOT_REQUESTED" -eq 1 ] || return 0
    sdbf_vm="$1"; sdbf_slot="$2"
    sdbf_boot="$(qm config "$sdbf_vm" | sed -n 's/^boot:[[:space:]]*//p' | head -n1)"
    sdbf_order="$(printf '%s\n' "$sdbf_boot" | sed -n 's/.*order=\([^,]*\).*/\1/p')"
    sdbf_new="$sdbf_slot"
    sdbf_old_ifs="$IFS"; IFS=';'; set -- $sdbf_order; IFS="$sdbf_old_ifs"
    for sdbf_item in "$@"; do
        if [ -n "$sdbf_item" ] && [ "$sdbf_item" != "$sdbf_slot" ]; then sdbf_new="${sdbf_new};${sdbf_item}"; fi
    done
    info "Making $sdbf_slot the first boot device on VM $sdbf_vm..."
    dryrun_cmd qm set "$sdbf_vm" --boot "order=$sdbf_new"
    if dryrun_enabled; then
        dryrun_verify "VM $sdbf_vm boot order would start with $sdbf_slot"
    else
        qm config "$sdbf_vm" | grep -qE "^boot:.*order=${sdbf_slot}([;,]|$)" || die "Boot-order verification failed."
    fi
    BOOT_ORDER_APPLIED=1
}

# verify_destination_boot_first VMID SLOT
# Verifies the boot keyword postcondition.
# Call: verify_destination_boot_first VMID SLOT
verify_destination_boot_first() {
    [ "$BOOT_REQUESTED" -eq 1 ] || return 0
    if dryrun_enabled; then dryrun_verify "VM $1 boot order would start with $2"; return 0; fi
    qm config "$1" | grep -qE "^boot:.*order=${2}([;,]|$)" || die "Requested boot slot is not first in the boot order."
}

############################################################
# COMMAND LINE
############################################################

# Call: parse_arguments ARG1
parse_arguments() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            dryrun|--dryrun) enable_dryrun ;;
            hot|pause|stop|restart) set_state_mode "$1" ;;
            delete) DELETE_OLD=1 ;;
            boot) BOOT_REQUESTED=1 ;;
            -h|-\?|/h|/\?|--help) usage; exit 0 ;;
            --version) printf '%s %s (project %s)\n' "$(basename "$0")" "$SCRIPT_VERSION" "$PROJECT_VERSION"; exit 0 ;;
            *)
                ARG_COUNT=$((ARG_COUNT + 1))
                case "$ARG_COUNT" in 1) ARG1="$1" ;; 2) ARG2="$1" ;; 3) ARG3="$1" ;; 4) ARG4="$1" ;; *) usage >&2; exit 2 ;; esac
                ;;
        esac
        shift
    done

    case "$ARG1" in
        /*)
            SOURCE_FORM="path"; SOURCE_INPUT="$ARG1"
            case "$ARG2" in
                /*) [ "$ARG_COUNT" -eq 2 ] || { usage >&2; exit 2; }; DEST_FORM="path"; DEST_INPUT="$ARG2" ;;
                *) [ "$ARG_COUNT" -eq 3 ] || { usage >&2; exit 2; }; DEST_FORM="vm"; DEST_VM_INPUT="$ARG2"; DEST_SELECTOR="$ARG3" ;;
            esac
            ;;
        *)
            [ "$ARG_COUNT" -ge 3 ] || { usage >&2; exit 2; }
            SOURCE_FORM="vm"; SOURCE_VM_INPUT="$ARG1"; SOURCE_SELECTOR="$ARG2"
            case "$ARG3" in
                /*) [ "$ARG_COUNT" -eq 3 ] || { usage >&2; exit 2; }; DEST_FORM="path"; DEST_INPUT="$ARG3" ;;
                *) [ "$ARG_COUNT" -eq 4 ] || { usage >&2; exit 2; }; DEST_FORM="vm"; DEST_VM_INPUT="$ARG3"; DEST_SELECTOR="$ARG4" ;;
            esac
            ;;
    esac
}

############################################################
# VALIDATION / PRE-FLIGHT
############################################################

# select_archive_name
# Reserves PREFIX-DESTVMID-disk-901 or the next free number for the displaced disk.
select_archive_name() {
    san_number=901
    while :; do
        ARCHIVE_LV_NAME="${DEST_PREFIX}-${DEST_VM}-disk-${san_number}"
        ARCHIVE_LV_PATH="/dev/${DEST_VG}/${ARCHIVE_LV_NAME}"
        ARCHIVE_VOLID="${DEST_OLD_STORAGE_ID}:${ARCHIVE_LV_NAME}"
        san_busy=0
        lvs "${DEST_VG}/${ARCHIVE_LV_NAME}" >/dev/null 2>&1 && san_busy=1 || :
        guest_volume_references | grep -F "|${ARCHIVE_VOLID}" >/dev/null 2>&1 && san_busy=1 || :
        [ "$san_busy" -eq 0 ] && break
        san_number=$((san_number + 1))
    done
    ARCHIVE_DISK_NUMBER="$san_number"
}

# select_new_disk_name
# Chooses a collision-free PREFIX-DESTVMID-disk-N snapshot name in SOURCE_VG.
select_new_disk_name() {
    NEW_VG="$SOURCE_VG"
    FINAL_LV_NAME="${DEST_PREFIX}-${DEST_VM}-disk-${DEST_DISK_NUMBER}"
    FINAL_LV_PATH="/dev/${NEW_VG}/${FINAL_LV_NAME}"
    FINAL_VOLID="${STORAGE_ID}:${FINAL_LV_NAME}"

    sndn_existing_uuid="$(lvs --noheadings -o lv_uuid "${NEW_VG}/${FINAL_LV_NAME}" 2>/dev/null | trim || :)"
    if [ "$DEST_EXISTS" -eq 1 ]; then
        [ -z "$sndn_existing_uuid" ] || [ "$sndn_existing_uuid" = "$DEST_OLD_UUID" ] || die "Replacement name already exists on another LV: ${NEW_VG}/${FINAL_LV_NAME}"
    else
        [ -z "$sndn_existing_uuid" ] || die "Cannot create disk-$DEST_DISK_NUMBER: ${NEW_VG}/${FINAL_LV_NAME} already exists."
        if guest_volume_references | grep -F "|$FINAL_VOLID" >/dev/null 2>&1; then die "Cannot create disk-$DEST_DISK_NUMBER: $FINAL_VOLID is already referenced by a guest configuration."; fi
    fi

    sndn_highest="$(printf '%s\n' "$DEST_CONFIG" | grep -oE "(vm|base)-[0-9]+-disk-[0-9]+" | sed -E 's/.*-disk-([0-9]+)$/\1/' | sort -n | tail -n1 || :)"
    if [ -n "$sndn_highest" ]; then TEMP_DISK_NUMBER=$((sndn_highest + 1)); else TEMP_DISK_NUMBER=0; fi
    while :; do
        TEMP_LV_NAME="${DEST_PREFIX}-${DEST_VM}-disk-${TEMP_DISK_NUMBER}"
        [ "$TEMP_LV_NAME" = "$FINAL_LV_NAME" ] && { TEMP_DISK_NUMBER=$((TEMP_DISK_NUMBER + 1)); continue; }
        TEMP_LV_PATH="/dev/${NEW_VG}/${TEMP_LV_NAME}"
        TEMP_VOLID="${STORAGE_ID}:${TEMP_LV_NAME}"
        sndn_busy=0
        printf '%s\n' "$DEST_CONFIG" | grep -qF "$TEMP_LV_NAME" && sndn_busy=1 || :
        lvs "${NEW_VG}/${TEMP_LV_NAME}" >/dev/null 2>&1 && sndn_busy=1 || :
        guest_volume_references | grep -F "|${TEMP_VOLID}" >/dev/null 2>&1 && sndn_busy=1 || :
        [ "$sndn_busy" -eq 0 ] && break
        TEMP_DISK_NUMBER=$((TEMP_DISK_NUMBER + 1))
    done

    NEW_LV_NAME="$TEMP_LV_NAME"; NEW_LV_PATH="$TEMP_LV_PATH"; NEW_VOLID="$TEMP_VOLID"
    if [ "$DEST_EXISTS" -eq 1 ]; then select_archive_name
    else ARCHIVE_LV_NAME=""; ARCHIVE_LV_PATH=""; ARCHIVE_VOLID=""; ARCHIVE_DISK_NUMBER=""; fi
}

############################################################
# HIGH LEVEL TASKS
############################################################

# print_plan
# Summarizes the staged/final snapshot, displaced-disk policy, destination state mode and boot intent before mutation.
print_plan() {
    print_banner "Overwrite/add VM disk with linked snapshot"
    printf 'Source LV:              %s\n' "$SOURCE_PATH"
    [ -z "$SOURCE_VM" ] || printf 'Source VM:              %s%s\n' "$SOURCE_VM" "${SOURCE_SLOT:+ ($SOURCE_SLOT)}"
    printf 'Source thin pool:       %s/%s\n' "$SOURCE_VG" "$SOURCE_POOL"
    printf 'Snapshot storage:       %s\n' "$STORAGE_ID"
    printf 'Destination VM:         %s\n' "$DEST_VM"
    printf 'Destination VM status:  %s\n' "${DEST_STATUS:-unknown}"
    printf 'Destination state mode: %s\n' "$MODE"
    printf 'Destination slot:       %s\n' "$DEST_SLOT"
    printf 'Target disk number:     disk-%s\n' "$DEST_DISK_NUMBER"
    printf 'Managed-volume family:  %s\n' "$DEST_PREFIX"

    if [ "$DEST_EXISTS" -eq 1 ]; then
        printf 'Old volume:             %s\n' "$DEST_OLD_VOLID"
        printf 'Old disk archive:       %s\n' "$ARCHIVE_VOLID"
        printf 'Operation:               replace existing disk\n'
    else
        printf 'Old volume:             none\n'
        printf 'Operation:               create new disk (nothing to overwrite)\n'
    fi

    printf 'Staged snapshot:        %s\n' "$TEMP_VOLID"
    printf 'Final snapshot:         %s\n' "$FINAL_VOLID"
    printf 'First boot device:      %s\n\n' "$([ "$BOOT_REQUESTED" -eq 1 ] && printf '%s' "$DEST_SLOT" || printf '%s' unchanged)"

    if [ "$DEST_EXISTS" -eq 1 ]; then
        if [ "$DELETE_OLD" -eq 1 ]; then warn "delete requested: the archived old disk will be permanently removed only after the replacement is attached and verified."
        else warn "The displaced destination volume will be renamed to disk-$ARCHIVE_DISK_NUMBER and preserved as unusedN."; fi
    elif [ "$DELETE_OLD" -eq 1 ]; then
        info "delete requested, but there is no existing destination disk to delete."
    fi
}

# replace_destination_disk
# Detaches the old disk into unusedN, then attaches the snapshot at the exact slot.
replace_destination_disk() {
    if [ "$DEST_EXISTS" -eq 0 ]; then
        rdd_now="$(disk_value "$DEST_VM" "$DEST_SLOT" 2>/dev/null || :)"
        [ -z "$rdd_now" ] || die "Destination slot $DEST_SLOT became occupied after preflight; refusing to attach the new disk."

        info "No existing disk uses disk-$DEST_DISK_NUMBER; creating it as a new destination disk."
        info "Renaming staged snapshot to disk-$DEST_DISK_NUMBER..."
        if dryrun_enabled; then dryrun_cmd lvrename "$NEW_VG" "$TEMP_LV_NAME" "$FINAL_LV_NAME"
        else run_lvm_filtered lvrename "$NEW_VG" "$TEMP_LV_NAME" "$FINAL_LV_NAME"; fi
        REPLACEMENT_FINALIZED=1
        NEW_LV_NAME="$FINAL_LV_NAME"; NEW_LV_PATH="$FINAL_LV_PATH"; NEW_VOLID="$FINAL_VOLID"

        if ! dryrun_enabled; then
            rdd_final_uuid="$(lvs --noheadings -o lv_uuid "${NEW_VG}/${FINAL_LV_NAME}" 2>/dev/null | trim || :)"
            [ "$rdd_final_uuid" = "$NEW_UUID" ] || die "New snapshot UUID changed or final rename did not land on the intended LV."
        fi

        verify_storage_mapping

        info "Attaching snapshot $NEW_VOLID at $DEST_SLOT..."
        if ! dryrun_cmd qm set "$DEST_VM" "--${DEST_SLOT}" "$NEW_VOLID"; then
            if ! dryrun_enabled && qm config "$DEST_VM" 2>/dev/null | grep -qF "$NEW_VOLID"; then NEW_ATTACHED=1; fi
            die "Could not attach the new snapshot disk."
        fi
        NEW_ATTACHED=1
        return 0
    fi

    rdd_now="$(disk_value "$DEST_VM" "$DEST_SLOT")"
    [ "$rdd_now" = "$DEST_OLD_VALUE" ] || die "Destination slot changed after preflight; refusing to replace it."

    info "Detaching $DEST_OLD_VOLID from $DEST_VM/$DEST_SLOT..."
    dryrun_cmd qm set "$DEST_VM" --delete "$DEST_SLOT"
    OLD_DETACHED=1

    if dryrun_enabled; then OLD_UNUSED_KEY="$(first_free_unused "$DEST_VM")"
    else
        OLD_UNUSED_KEY="$(old_unused_key "$DEST_OLD_VOLID")"
        [ -n "$OLD_UNUSED_KEY" ] || { rollback_old_disk || :; die "Proxmox did not preserve the displaced disk as unusedN."; }
    fi

    info "Renaming displaced disk to $ARCHIVE_LV_NAME..."
    if dryrun_enabled; then dryrun_cmd lvrename "$DEST_VG" "$DEST_OLD_LV" "$ARCHIVE_LV_NAME"
    else run_lvm_filtered lvrename "$DEST_VG" "$DEST_OLD_LV" "$ARCHIVE_LV_NAME"; fi
    OLD_ARCHIVED=1

    info "Updating $OLD_UNUSED_KEY to the archived volume name without invoking storage deletion..."
    if ! rewrite_unused_reference "$OLD_UNUSED_KEY" "$DEST_OLD_VOLID" "$ARCHIVE_VOLID"; then
        rollback_old_disk || :
        die "Could not update $OLD_UNUSED_KEY to $ARCHIVE_VOLID safely."
    fi

    if ! dryrun_enabled; then
        [ -n "$(old_unused_key "$ARCHIVE_VOLID")" ] || { rollback_old_disk || :; die "Archived disk is not preserved as unusedN."; }
        [ "$(lv_name_by_uuid "$DEST_VG" "$DEST_OLD_UUID")" = "$ARCHIVE_LV_NAME" ] || { rollback_old_disk || :; die "Archived destination LV UUID is not at the expected archive name."; }
    else
        dryrun_verify "$DEST_OLD_VOLID would be preserved as $ARCHIVE_VOLID at $OLD_UNUSED_KEY"
    fi

    info "Renaming staged snapshot to the original disk number disk-$DEST_DISK_NUMBER..."
    if dryrun_enabled; then dryrun_cmd lvrename "$NEW_VG" "$TEMP_LV_NAME" "$FINAL_LV_NAME"
    else run_lvm_filtered lvrename "$NEW_VG" "$TEMP_LV_NAME" "$FINAL_LV_NAME"; fi
    REPLACEMENT_FINALIZED=1
    NEW_LV_NAME="$FINAL_LV_NAME"; NEW_LV_PATH="$FINAL_LV_PATH"; NEW_VOLID="$FINAL_VOLID"
    if ! dryrun_enabled; then
        rdd_final_uuid="$(lvs --noheadings -o lv_uuid "${NEW_VG}/${FINAL_LV_NAME}" 2>/dev/null | trim || :)"
        [ "$rdd_final_uuid" = "$NEW_UUID" ] || { rollback_old_disk || :; die "Replacement LV UUID changed or final rename did not land on the intended LV."; }
    fi

    verify_storage_mapping

    info "Attaching snapshot $NEW_VOLID at $DEST_SLOT..."
    if ! dryrun_cmd qm set "$DEST_VM" "--${DEST_SLOT}" "${NEW_VOLID}${DEST_OPTIONS}"; then
        if ! dryrun_enabled && qm config "$DEST_VM" 2>/dev/null | grep -qF "$NEW_VOLID"; then NEW_ATTACHED=1
        else rollback_old_disk || :; fi
        die "Could not attach snapshot replacement."
    fi
    NEW_ATTACHED=1
}

# delete_archived_disk
# Deletes the displaced archived LV only after the replacement snapshot is attached and verified, when requested.
delete_archived_disk() {
    [ "$DELETE_OLD" -eq 1 ] || return 0
    if [ "$DEST_EXISTS" -eq 0 ]; then
        info "delete requested, but there was no displaced destination disk to delete."
        return 0
    fi

    info "Deleting displaced archived disk $ARCHIVE_VOLID..."

    if dryrun_enabled; then
        remove_unused_reference_only "$OLD_UNUSED_KEY" "$ARCHIVE_VOLID"
        dryrun_cmd lvremove -y "$ARCHIVE_LV_PATH"
        dryrun_verify "$ARCHIVE_VOLID would be permanently deleted after the replacement is verified"
        OLD_ARCHIVED=0
        OLD_DELETED=1
        return 0
    fi

    [ -n "$(old_unused_key "$ARCHIVE_VOLID")" ] || die "Refusing delete: archived disk is no longer the expected unused volume."
    [ "$(lv_name_by_uuid "$DEST_VG" "$DEST_OLD_UUID")" = "$ARCHIVE_LV_NAME" ] || die "Refusing delete: archived LV UUID no longer matches the displaced destination disk."

    if ! remove_unused_reference_only "$OLD_UNUSED_KEY" "$ARCHIVE_VOLID"; then
        die "Could not remove the archived unusedN config reference safely."
    fi

    if ! run_lvm_filtered lvremove -y "$ARCHIVE_LV_PATH"; then
        warn "Could not delete archived LV; restoring its unusedN config reference."
        add_unused_reference_only "$OLD_UNUSED_KEY" "$ARCHIVE_VOLID" || warn "Could not restore $OLD_UNUSED_KEY automatically."
        die "Failed to delete $ARCHIVE_VOLID."
    fi

    if [ -n "$(lv_name_by_uuid "$DEST_VG" "$DEST_OLD_UUID")" ]; then
        warn "lvremove returned successfully, but the displaced LV UUID still exists; restoring an unused reference if possible."
        add_unused_reference_only "$OLD_UNUSED_KEY" "$ARCHIVE_VOLID" || :
        die "Archived destination LV still exists after deletion."
    fi

    OLD_ARCHIVED=0
    OLD_DELETED=1
}

# verify_result
# Verifies final disk identity, snapshot origin, archived/deleted old-disk state, guest state, and boot order.
verify_result() {
    if dryrun_enabled; then
        if [ "$DEST_EXISTS" -eq 1 ]; then
            dryrun_verify "$DEST_SLOT would reference $FINAL_VOLID using the original disk number disk-$DEST_DISK_NUMBER"
            if [ "$DELETE_OLD" -eq 1 ]; then dryrun_verify "$ARCHIVE_VOLID would be deleted"
            else dryrun_verify "$ARCHIVE_VOLID would remain preserved as unusedN"; fi
        else
            dryrun_verify "$DEST_SLOT would reference newly created $FINAL_VOLID as disk-$DEST_DISK_NUMBER"
        fi
        dryrun_verify "Snapshot origin would remain $SOURCE_LV"
        dryrun_verify "Destination VM state would match requested $MODE behavior"
        return 0
    fi

    [ "$(disk_volid "$DEST_VM" "$DEST_SLOT")" = "$FINAL_VOLID" ] || die "Destination slot verification failed."
    [ "$NEW_LV_NAME" = "${DEST_PREFIX}-${DEST_VM}-disk-${DEST_DISK_NUMBER}" ] || die "Result did not retain the requested destination managed-volume name."

    if [ "$DEST_EXISTS" -eq 1 ]; then
        if [ "$DELETE_OLD" -eq 1 ]; then
            [ "$OLD_DELETED" -eq 1 ] || die "Delete was requested, but the displaced disk was not deleted."
            [ -z "$(old_unused_key "$ARCHIVE_VOLID")" ] || die "Deleted archived disk still has an unused reference."
        else
            [ -n "$(old_unused_key "$ARCHIVE_VOLID")" ] || die "Archived destination volume is not preserved as unusedN."
            lvs "${DEST_VG}/${ARCHIVE_LV_NAME}" >/dev/null 2>&1 || die "Archived destination LV is missing."
        fi
    fi

    vr_origin="$(lvs --noheadings -o origin "${NEW_VG}/${NEW_LV_NAME}" | trim)"
    [ "$vr_origin" = "$SOURCE_LV" ] || die "Snapshot origin verification failed."
    verify_destination_boot_first "$DEST_VM" "$DEST_SLOT"
}

############################################################
# ERROR HANDLING / CLEANUP
############################################################

install_transaction_traps() {
    trap cleanup_on_exit 0
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
}

# cleanup_on_exit
# Transaction trap: invokes UUID-safe rollback and restores destination guest state after failure.
cleanup_on_exit() {
    coe_status=$?
    trap - 0 HUP INT TERM
    set +e

    if [ "$NEW_ATTACHED" -eq 0 ] && [ "$OLD_DETACHED" -eq 1 ] && [ "$ROLLBACK_FAILED" -eq 0 ]; then
        rollback_old_disk || :
    fi

    if [ "$MODE" = "pause" ] && [ "$PAUSED_BY_US" -eq 1 ] && [ -n "$DEST_VM" ]; then
        if dryrun_enabled; then dryrun_cmd qm resume "$DEST_VM"; else qm resume "$DEST_VM" >/dev/null 2>&1; fi
        PAUSED_BY_US=0
    elif [ "$MODE" = "restart" ] && [ "$STOPPED_BY_US" -eq 1 ] && [ -n "$DEST_VM" ]; then
        if dryrun_enabled; then dryrun_cmd qm start "$DEST_VM"; else qm start "$DEST_VM" >/dev/null 2>&1; fi
        STOPPED_BY_US=0
    fi

    if ! dryrun_enabled && [ "$CREATED" -eq 1 ] && [ "$NEW_ATTACHED" -eq 0 ] && [ "$COMPLETE" -eq 0 ] && [ "$ROLLBACK_FAILED" -eq 0 ]; then
        if ! guest_volume_references | grep -F "|$NEW_VOLID" >/dev/null 2>&1; then
            warn "Removing unattached replacement snapshot: $NEW_LV_PATH"
            lvremove -y "${NEW_VG}/${NEW_LV_NAME}" >/dev/null 2>&1 || warn "Could not remove $NEW_LV_PATH automatically."
        fi
    elif ! dryrun_enabled && [ "$ROLLBACK_FAILED" -eq 1 ]; then
        warn "Rollback was incomplete. No remaining replacement LV will be auto-deleted; inspect LV UUIDs and VM config before making further changes."
    fi

    set -e
    [ "$coe_status" -eq 0 ] || exit "$coe_status"
    return 0
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
