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
    PROJECT_VERSION="3.5.1"; SCRIPT_VERSION="3.5.1"
    MODE="hot"; MODE_ARG=""; ARG1=""; ARG2=""; ARG3=""; ARG_COUNT=0
    REFS_FILE=""; SOURCE_VM=""; SOURCE_SLOT=""; SOURCE_VALUE=""; SOURCE_VOLID=""; SOURCE_ACTIVE=0
    SOURCE_STATUS=""; SOURCE_UNUSED=""; DEST_SLOT=""; DEST_TOUCHED=0; DEST_ATTACHED=0; SOURCE_DETACHED=0
    PAUSED_BY_US=0; STOPPED_BY_US=0; STATE_RESTORED=0; TRANSFER_COMPLETE=0
    define_colours
    parse_arguments "$@"
    check_elevation
}

# main [ARGS...]
# Call: main "$@"
# Performs preflight and the command's primary operation.
main() {
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    need_commands qm pvesm lvs find awk sed grep sort readlink dmsetup findmnt mktemp
    resolve_destination
    resolve_source
    validate_source_references
    validate_source_guest_config
    validate_source_usage
    validate_pause_detach_capability
    DEST_SLOT="$(first_free_scsi "$DEST_VM")" || die "Destination VM $DEST_VM has no free SCSI slot."
    print_transfer_plan
    install_transfer_traps
    apply_source_state
    transfer_volume
    restore_source_state
    verify_transfer
    TRANSFER_COMPLETE=1
    remove_temp_files
    trap - 0 HUP INT TERM
}

# end
# Call: end
# Prints/finalizes the command result and performs normal completion cleanup.
end() {
    ok "Moved $LV to VM $DEST_VM as $DEST_SLOT."
    if [ -n "$SOURCE_VM" ]; then info "Source VM: $SOURCE_VM ($SOURCE_SLOT removed)"; fi
    case "$MODE" in
        pause) [ "$PAUSED_BY_US" -eq 1 ] && info "Source VM resumed after the move." || : ;;
        stop) [ "$STOPPED_BY_US" -eq 1 ] && info "Source VM remains stopped." || : ;;
        restart) [ "$STOPPED_BY_US" -eq 1 ] && info "Source VM restarted after the move." || : ;;
    esac
    dryrun_summary
}

# usage
# Call: usage
# Prints command-line usage and exits only when the caller chooses to exit.
usage() {
    cat <<EOF
$(basename "$0") $SCRIPT_VERSION (project $PROJECT_VERSION)

USAGE
  $(basename "$0") <full-lv-path> <destination-vmid> [pause|stop|restart] [dryrun]
  $(basename "$0") <source-vmid> <disk-number|slot> <destination-vmid> [pause|stop|restart] [dryrun]

DESCRIPTION
  Moves an existing LVM-backed QEMU disk reference to another QEMU VM without
  copying or renaming the LV. The destination uses its first free SCSI slot.

  The numeric disk form selects a managed backing volume vm-SOURCE-disk-N or base-SOURCE-disk-N; stale embedded IDs are accepted only when the disk number is otherwise unambiguous.
  An explicit source slot such as scsi0, sata1, virtio2, or unused0 is also
  accepted.

SOURCE VM STATE
  default   Hot-swap. Do not stop or pause the source VM.
  pause     Suspend a running source VM before detach, then resume it.
            For SCSI disks, pause requires a shared controller with another
            active SCSI disk; virtio-scsi-single and last-disk controller
            removal are refused before mutation because Proxmox cannot safely
            hot-unplug those controllers while the VM is suspended.
  stop      Stop a running source VM before detach and leave it stopped.
  restart   Stop a running source VM before detach, then start it again.

  pause, stop, restart, dryrun and --dryrun may appear anywhere. Only one of
  pause/stop/restart may be selected. A VM that was already stopped is never
  started automatically.

EXAMPLES
  $(basename "$0") /dev/pve/vm-123-disk-0 456 dryrun
  $(basename "$0") 123 0 456 pause dryrun
  $(basename "$0") restart 123 scsi0 456

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
Dry-run:
  Add dryrun or --dryrun anywhere on the command line.
  Read-only preflight checks still run, but modifying commands are printed
  instead of executed and mutation-dependent verification is simulated.
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

# set_transfer_mode MODE
# Accepts one state-control mode and rejects conflicting mode keywords.
# Call: set_transfer_mode MODE
set_transfer_mode() {
    stm_new="$1"
    if [ -n "$MODE_ARG" ] && [ "$MODE_ARG" != "$stm_new" ]; then die "Choose only one of pause, stop, or restart."; fi
    MODE="$stm_new"; MODE_ARG="$stm_new"
}

# Call: parse_arguments ARG1
parse_arguments() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            dryrun|--dryrun) enable_dryrun ;;
            pause|stop|restart) set_transfer_mode "$1" ;;
            -h|--help) usage; exit 0 ;;
            --version) printf '%s %s (project %s)\n' "$(basename "$0")" "$SCRIPT_VERSION" "$PROJECT_VERSION"; exit 0 ;;
            *)
                ARG_COUNT=$((ARG_COUNT + 1))
                case "$ARG_COUNT" in 1) ARG1="$1" ;; 2) ARG2="$1" ;; 3) ARG3="$1" ;; *) usage >&2; exit 2 ;; esac
                ;;
        esac
        shift
    done

    if [ "$ARG_COUNT" -eq 2 ]; then
        case "$ARG1" in /*) SOURCE_FORM="path" ;; *) die "Two-argument form requires a full absolute LVM path followed by destination VMID." ;; esac
        DEST_VM="$ARG2"
    elif [ "$ARG_COUNT" -eq 3 ]; then
        SOURCE_FORM="vm"; SOURCE_VM="$ARG1"; DISK_SELECTOR="$ARG2"; DEST_VM="$ARG3"
    else
        usage >&2; exit 2
    fi
}

############################################################
# VALIDATION / PRE-FLIGHT
############################################################

# resolve_destination
# Validates the destination VM without imposing any stopped/running requirement.
resolve_destination() {
    require_qemu_vm "$DEST_VM"
    rd_cfg="$(qm config "$DEST_VM")"
    if printf '%s\n' "$rd_cfg" | grep -qE '^lock:[[:space:]]*'; then die "Destination VM $DEST_VM is locked; resolve the lock before moving a disk."; fi
}

# resolve_source
# Resolves either supported CLI form to one LVM LV, Proxmox volume ID and,
# when attached, a unique source VM/slot.
resolve_source() {
    if [ "$SOURCE_FORM" = "path" ]; then resolve_source_by_path
    else resolve_source_by_vm; fi
    [ -z "$SOURCE_VM" ] || [ "$SOURCE_VM" != "$DEST_VM" ] || die "Source and destination VM are the same."
    case "$SOURCE_VALUE" in *,media=cdrom*) die "Refusing to move a CD-ROM/cloud media entry as a VM disk." ;; esac
}

# resolve_source_by_path
# Resolves a full LV path and discovers its unique Proxmox guest reference.
resolve_source_by_path() {
    assert_lv_exists "$ARG1"
    LV="$(canonical_lv_path "$ARG1")"; [ -n "$LV" ] || die "Could not resolve LVM path: $ARG1"
    LV_UUID="$(lvs --noheadings -o lv_uuid "$LV" 2>/dev/null | trim)"
    [ -n "$LV_UUID" ] || die "Could not determine LV UUID for $LV."
    collect_lv_references

    rsbp_count="$(awk 'NF {n++} END {print n+0}' "$REFS_FILE")"
    if [ "$rsbp_count" -eq 0 ]; then
        SOURCE_VM=""; SOURCE_SLOT=""; SOURCE_ACTIVE=0
        SOURCE_VOLID="$(volid_for_lv "$LV")"; SOURCE_VALUE="$SOURCE_VOLID"
        return 0
    fi
    [ "$rsbp_count" -eq 1 ] || { cat "$REFS_FILE" >&2; die "$LV is referenced by multiple guest entries; refusing to move it."; }

    IFS='|' read -r rsbp_cfg SOURCE_SLOT SOURCE_VOLID < "$REFS_FILE"
    rsbp_id="${rsbp_cfg##*/}"; rsbp_id="${rsbp_id%.conf}"
    case "$rsbp_cfg" in */qemu-server/*) ;; *) die "$LV is referenced by a non-QEMU guest; this command moves QEMU VM disks only." ;; esac
    [ -f "/etc/pve/qemu-server/${rsbp_id}.conf" ] || die "The source reference belongs to VM $rsbp_id on another node; run the move on that node."
    SOURCE_VM="$rsbp_id"
    case "$SOURCE_SLOT" in scsi[0-9]*|sata[0-9]*|virtio[0-9]*|ide[0-9]*|unused[0-9]*) ;; *) die "Unsupported source slot: $SOURCE_SLOT" ;; esac
    SOURCE_VALUE="$(disk_value "$SOURCE_VM" "$SOURCE_SLOT")"; [ -n "$SOURCE_VALUE" ] || die "Could not read $SOURCE_SLOT from VM $SOURCE_VM."
    case "$SOURCE_SLOT" in unused*) SOURCE_ACTIVE=0 ;; *) SOURCE_ACTIVE=1 ;; esac
}

# resolve_source_by_vm
# Resolves a numeric managed-volume disk-N selector (vm/base) or explicit QEMU disk slot.
# Call: resolve_source_by_vm ARG1 [ARG2]
resolve_source_by_vm() {
    require_qemu_vm "$SOURCE_VM"
    case "$DISK_SELECTOR" in
        scsi[0-9]*|sata[0-9]*|virtio[0-9]*|ide[0-9]*|unused[0-9]*) SOURCE_SLOT="$DISK_SELECTOR" ;;
        ''|*[!0-9]*) die "Disk selector must be a numeric backing-disk number or a QEMU disk slot." ;;
        *)
            rsbv_slots="$(qm config "$SOURCE_VM" | awk -F': ' -v n="$DISK_SELECTOR" '
                $1 ~ /^(scsi|sata|virtio|ide|unused)[0-9]+$/ {
                    split($2,a,","); v=a[1]; sub(/^[^:]+:/,"",v)
                    if (v ~ "^(vm|base)-[0-9]+-disk-" n "$") print $1
                }')"
            rsbv_count="$(printf '%s\n' "$rsbv_slots" | awk 'NF {n++} END {print n+0}')"
            [ "$rsbv_count" -gt 0 ] || die "VM $SOURCE_VM has no configured vm/base backing volume with disk number $DISK_SELECTOR."
            [ "$rsbv_count" -eq 1 ] || { printf '%s\n' "$rsbv_slots" >&2; die "Disk number $DISK_SELECTOR matches multiple VM slots; use an explicit source slot."; }
            SOURCE_SLOT="$(printf '%s\n' "$rsbv_slots" | awk 'NF {print; exit}')"
            ;;
    esac

    SOURCE_VALUE="$(disk_value "$SOURCE_VM" "$SOURCE_SLOT")"; [ -n "$SOURCE_VALUE" ] || die "VM $SOURCE_VM has no disk at $SOURCE_SLOT."
    SOURCE_VOLID="${SOURCE_VALUE%%,*}"
    case "$SOURCE_VOLID" in *:*) ;; *) die "$SOURCE_SLOT does not contain a storage-backed volume." ;; esac
    rsbv_path="$(pvesm path "$SOURCE_VOLID" 2>/dev/null || :)"; [ -n "$rsbv_path" ] || die "Could not resolve $SOURCE_VOLID."
    assert_lv_exists "$rsbv_path"
    LV="$(canonical_lv_path "$rsbv_path")"; LV_UUID="$(lvs --noheadings -o lv_uuid "$LV" 2>/dev/null | trim)"
    [ -n "$LV_UUID" ] || die "Could not determine LV UUID for $LV."
    case "$SOURCE_SLOT" in unused*) SOURCE_ACTIVE=0 ;; *) SOURCE_ACTIVE=1 ;; esac
    collect_lv_references
}

# collect_lv_references
#
# Description:
#   Finds every Proxmox guest config entry whose resolved LVM UUID equals
#   LV_UUID. UUID comparison handles storage aliases and /dev path aliases.
#
# Usage:
#   collect_lv_references
#
# Arguments:
#   Uses LV_UUID.
#
# Output:
#   REFS_FILE columns: config|slot|volid
#
# Returns:
#   0 after cluster-visible guest configs are inspected.
############################################################
collect_lv_references() {
    [ -n "$REFS_FILE" ] || REFS_FILE="$(mktemp)" || die "Unable to create volume-reference list."
    : > "$REFS_FILE"
    all_guest_configs | while IFS= read -r clr_cfg; do
        config_volume_references "$clr_cfg" | while IFS='|' read -r clr_slot clr_volid; do
            clr_path="$(pvesm path "$clr_volid" 2>/dev/null || :)"
            [ -n "$clr_path" ] || continue
            lvs "$clr_path" >/dev/null 2>&1 || continue
            clr_uuid="$(lvs --noheadings -o lv_uuid "$clr_path" 2>/dev/null | trim)"
            [ "$clr_uuid" = "$LV_UUID" ] || continue
            printf '%s|%s|%s\n' "$clr_cfg" "$clr_slot" "$clr_volid"
        done
    done | sort -u > "$REFS_FILE"
    return 0
}

# validate_source_references
# Requires the VM-form source to be the LV's one and only Proxmox reference.
validate_source_references() {
    [ "$SOURCE_FORM" = "vm" ] || return 0
    vsr_count="$(awk 'NF {n++} END {print n+0}' "$REFS_FILE")"
    [ "$vsr_count" -eq 1 ] || { cat "$REFS_FILE" >&2; die "$LV has $vsr_count Proxmox references; exactly one source reference is required."; }
    IFS='|' read -r vsr_cfg vsr_slot vsr_volid < "$REFS_FILE"
    vsr_id="${vsr_cfg##*/}"; vsr_id="${vsr_id%.conf}"
    case "$vsr_cfg" in */qemu-server/*) ;; *) die "$LV is also owned by a non-QEMU guest."; ;; esac
    [ "$vsr_id" = "$SOURCE_VM" ] && [ "$vsr_slot" = "$SOURCE_SLOT" ] || die "Resolved volume ownership does not match VM $SOURCE_VM $SOURCE_SLOT."
}

# validate_source_guest_config
# Rejects source locks/snapshot sections and warns when the removed slot is in boot order.
validate_source_guest_config() {
    [ -n "$SOURCE_VM" ] || return 0
    vsgc_cfg="/etc/pve/qemu-server/${SOURCE_VM}.conf"
    if grep -qE '^lock:[[:space:]]*' "$vsgc_cfg"; then die "Source VM $SOURCE_VM is locked; resolve the lock before moving a disk."; fi
    if grep -qE '^\[[^]]+\]$' "$vsgc_cfg"; then die "Source VM $SOURCE_VM has snapshot/config sections; remove snapshots before moving a disk."; fi
    if [ "$SOURCE_ACTIVE" -eq 1 ] && qm config "$SOURCE_VM" | sed -n 's/^boot:[[:space:]]*//p' | grep -F "$SOURCE_SLOT" >/dev/null 2>&1; then
        warn "Source boot order references $SOURCE_SLOT; review the source VM boot order after moving this disk."
    fi
    return 0
}

# validate_source_usage
# Refuses host mounts and, when no active source VM legitimately owns the LV,
# refuses any remaining device-mapper open count.
# Call: validate_source_usage ARG1 [ARG2]
validate_source_usage() {
    vsu_real="$(readlink -f "$LV")"
    if findmnt -rn -S "$LV" >/dev/null 2>&1 || findmnt -rn -S "$vsu_real" >/dev/null 2>&1; then die "The LV is mounted on the host: $LV"; fi

    if [ "$SOURCE_ACTIVE" -eq 1 ]; then
        SOURCE_STATUS="$(qm status "$SOURCE_VM" 2>/dev/null | awk '{print $2}')"
        case "$SOURCE_STATUS" in running|stopped|paused) ;; *) die "Could not determine a safe source VM state: ${SOURCE_STATUS:-unknown}" ;; esac
        if [ "$SOURCE_STATUS" = "stopped" ]; then assert_lv_idle "$LV"; fi
    else
        SOURCE_STATUS=""
        assert_lv_idle "$LV"
        [ -z "$SOURCE_VM" ] || info "Source reference is $SOURCE_SLOT on VM $SOURCE_VM; it is already unused/inactive."
        if [ -z "$SOURCE_VM" ] && [ "$MODE" != "hot" ]; then die "$MODE requires a source VM that is actively losing a disk."; fi
    fi
}


# validate_pause_detach_capability
# Refuses a pause-mode SCSI detach topology that Proxmox cannot safely hot-unplug
# while the VM is suspended (per-disk virtio-scsi-single controllers or the last
# disk on a shared SCSI controller).
# Call: validate_pause_detach_capability ARG1
validate_pause_detach_capability() {
    [ "$MODE" = "pause" ] || return 0
    [ "$SOURCE_ACTIVE" -eq 1 ] || return 0
    case "$SOURCE_STATUS" in running|paused) ;; *) return 0 ;; esac
    case "$SOURCE_SLOT" in scsi[0-9]*) ;; *) return 0 ;; esac

    vpdc_cfg="$(qm config "$SOURCE_VM")"
    vpdc_scsihw="$(printf '%s\n' "$vpdc_cfg" | sed -n 's/^scsihw:[[:space:]]*//p' | head -n1)"
    if [ "$vpdc_scsihw" = "virtio-scsi-single" ]; then
        die "pause mode cannot safely detach $SOURCE_SLOT from VM $SOURCE_VM while using virtio-scsi-single; Proxmox hot-unplugs the per-disk controller and rejects it while suspended. Use hot, stop, or restart."
    fi

    vpdc_count="$(printf '%s\n' "$vpdc_cfg" | awk -F': ' '$1 ~ /^scsi[0-9]+$/ {n++} END {print n+0}')"
    if [ "$vpdc_count" -le 1 ]; then
        die "pause mode cannot safely detach the only active SCSI disk from VM $SOURCE_VM while suspended; Proxmox attempts to remove the SCSI controller. Use hot, stop, or restart, or keep another SCSI disk on the shared controller."
    fi
}

############################################################
# STATE CONTROL
############################################################

# apply_source_state
#
# Description:
#   Applies optional source-VM pause/stop/restart preparation. Default hot mode
#   intentionally leaves a running source VM running.
#
# Usage:
#   apply_source_state
#
# Arguments:
#   Uses MODE, SOURCE_ACTIVE and SOURCE_STATUS.
#
# Output:
#   May suspend or stop SOURCE_VM unless dry-run mode is active.
#
# Returns:
#   0 after required state preparation is verified/simulated.
############################################################
apply_source_state() {
    [ "$SOURCE_ACTIVE" -eq 1 ] || return 0
    case "$MODE" in
        hot)
            info "Source VM state: $SOURCE_STATUS; hot-swap mode leaves it unchanged."
            ;;
        pause)
            if [ "$SOURCE_STATUS" = "running" ]; then
                info "Pausing source VM $SOURCE_VM before disk removal..."
                dryrun_cmd qm suspend "$SOURCE_VM"
                PAUSED_BY_US=1
                if dryrun_enabled; then dryrun_verify "VM $SOURCE_VM would be paused before detach"; fi
            else
                info "Source VM $SOURCE_VM is $SOURCE_STATUS; no pause is required."
            fi
            ;;
        stop|restart)
            if [ "$SOURCE_STATUS" != "stopped" ]; then
                info "Stopping source VM $SOURCE_VM before disk removal..."
                dryrun_cmd qm stop "$SOURCE_VM"
                STOPPED_BY_US=1
                if dryrun_enabled; then dryrun_verify "VM $SOURCE_VM would be stopped before detach"
                else [ "$(qm status "$SOURCE_VM" | awk '{print $2}')" = "stopped" ] || die "Source VM did not stop."; fi
            else
                info "Source VM $SOURCE_VM is already stopped."
            fi
            ;;
    esac
}

# restore_source_state
# Resumes/starts only state that this invocation changed; stop mode stays stopped.
# Call: restore_source_state ARG1 [ARG2]
restore_source_state() {
    if [ "$MODE" = "pause" ] && [ "$PAUSED_BY_US" -eq 1 ]; then
        info "Resuming source VM $SOURCE_VM..."
        if ! dryrun_cmd qm resume "$SOURCE_VM"; then warn "Could not resume source VM $SOURCE_VM."; return 1; fi
        if dryrun_enabled; then dryrun_verify "VM $SOURCE_VM would resume after the move"; fi
    elif [ "$MODE" = "restart" ] && [ "$STOPPED_BY_US" -eq 1 ]; then
        info "Starting source VM $SOURCE_VM..."
        if ! dryrun_cmd qm start "$SOURCE_VM"; then warn "Could not restart source VM $SOURCE_VM."; return 1; fi
        if dryrun_enabled; then dryrun_verify "VM $SOURCE_VM would restart after the move"
        elif [ "$(qm status "$SOURCE_VM" | awk '{print $2}')" != "running" ]; then warn "Source VM $SOURCE_VM did not return to running state."; return 1; fi
    fi
    STATE_RESTORED=1
    return 0
}

############################################################
# TRANSFER
############################################################

print_transfer_plan() {
    print_banner "Move disk to VM"
    printf 'LVM volume:       %s\n' "$LV"
    printf 'Proxmox volume:   %s\n' "$SOURCE_VOLID"
    if [ -n "$SOURCE_VM" ]; then printf 'Source VM:        %s\nSource slot:      %s\n' "$SOURCE_VM" "$SOURCE_SLOT"
    else printf 'Source VM:        %s\n' "(unattached LV)"; fi
    printf 'Destination VM:   %s\nDestination slot: %s\nMode:             %s\n\n' "$DEST_VM" "$DEST_SLOT" "$MODE"
}

# transfer_volume
#
# Description:
#   For an active source, detaches first so two running VMs never receive the
#   same writable disk. For an already-unused source reference, attaches the
#   destination first because the source is not actively using the LV.
#
# Usage:
#   transfer_volume
#
# Arguments:
#   Uses resolved source/destination state.
#
# Output:
#   Mutates QEMU configuration unless dry-run mode is active.
#
# Returns:
#   0 only after destination attachment and source-reference cleanup.
############################################################
transfer_volume() {
    if [ -z "$SOURCE_VM" ]; then
        collect_lv_references
        [ ! -s "$REFS_FILE" ] || { cat "$REFS_FILE" >&2; die "The LV gained a guest reference after preflight; refusing to attach it."; }
        attach_destination
        return 0
    fi

    [ "$(disk_value "$SOURCE_VM" "$SOURCE_SLOT")" = "$SOURCE_VALUE" ] || die "Source slot changed after preflight: VM $SOURCE_VM $SOURCE_SLOT"

    if [ "$SOURCE_ACTIVE" -eq 0 ]; then
        attach_destination
        remove_source_unused "$SOURCE_SLOT"
        return 0
    fi

    tv_planned_unused="$(first_free_unused "$SOURCE_VM")" || die "No free unusedN slot is available on source VM $SOURCE_VM."
    info "Detaching $SOURCE_SLOT from VM $SOURCE_VM..."
    if ! dryrun_cmd qm set "$SOURCE_VM" --delete "$SOURCE_SLOT"; then
        if ! dryrun_enabled && [ "$(disk_volid "$SOURCE_VM" "$SOURCE_SLOT" 2>/dev/null || :)" != "$SOURCE_VOLID" ]; then
            SOURCE_DETACHED=1
            SOURCE_UNUSED="$(qm config "$SOURCE_VM" | awk -F': ' -v v="$SOURCE_VOLID" '$1 ~ /^unused[0-9]+$/ {split($2,a,","); if(a[1]==v) {print $1; exit}}')"
        fi
        die "Source detach failed."
    fi
    SOURCE_DETACHED=1

    if dryrun_enabled; then
        SOURCE_UNUSED="$tv_planned_unused"
        dryrun_verify "$SOURCE_SLOT would be detached from VM $SOURCE_VM"
        dryrun_verify "$SOURCE_VOLID would be preserved as $SOURCE_UNUSED"
    else
        [ -z "$(disk_value "$SOURCE_VM" "$SOURCE_SLOT")" ] || die "$SOURCE_SLOT still exists after detach."
        SOURCE_UNUSED="$(qm config "$SOURCE_VM" | awk -F': ' -v v="$SOURCE_VOLID" '$1 ~ /^unused[0-9]+$/ {split($2,a,","); if(a[1]==v) {print $1; exit}}')"
        if [ -z "$SOURCE_UNUSED" ]; then warn "Detach did not create an unusedN reference; the LV itself still exists and will be preserved."; fi
    fi

    attach_destination
    [ -z "$SOURCE_UNUSED" ] || remove_source_unused "$SOURCE_UNUSED"
}

# attach_destination
# Attaches SOURCE_VALUE to the first free destination SCSI slot and verifies it.
attach_destination() {
    [ -z "$(disk_value "$DEST_VM" "$DEST_SLOT")" ] || die "Destination slot became occupied after preflight: VM $DEST_VM $DEST_SLOT"
    info "Attaching $SOURCE_VOLID to VM $DEST_VM as $DEST_SLOT..."
    if ! dryrun_cmd qm set "$DEST_VM" "--$DEST_SLOT" "$SOURCE_VALUE"; then
        if ! dryrun_enabled && [ "$(disk_volid "$DEST_VM" "$DEST_SLOT" 2>/dev/null || :)" = "$SOURCE_VOLID" ]; then DEST_TOUCHED=1; fi
        die "Destination attachment failed."
    fi

    if dryrun_enabled; then
        DEST_ATTACHED=1
        dryrun_verify "VM $DEST_VM would reference $SOURCE_VOLID at $DEST_SLOT"
    else
        DEST_TOUCHED=1
        [ "$(disk_volid "$DEST_VM" "$DEST_SLOT" 2>/dev/null || :)" = "$SOURCE_VOLID" ] || die "Destination attachment verification failed."
        DEST_ATTACHED=1
    fi
}

# remove_source_unused_reference_only SLOT EXPECTED_VOLID
# Removes only the unusedN config line. It deliberately does not use
# qm set --delete because Proxmox may free the backing volume.
# Call: remove_source_unused_reference_only SLOT EXPECTED_VOLID
remove_source_unused_reference_only() {
    rsuro_slot="$1"; rsuro_expected="$2"
    rsuro_config="/etc/pve/qemu-server/${SOURCE_VM}.conf"
    [ -f "$rsuro_config" ] || return 1
    rsuro_current="$(disk_volid "$SOURCE_VM" "$rsuro_slot" 2>/dev/null || :)"
    [ -n "$rsuro_current" ] || return 0
    [ "$rsuro_current" = "$rsuro_expected" ] || return 1

    if dryrun_enabled; then
        dryrun_print_shell "remove config-only ${rsuro_slot}: ${rsuro_expected} from $rsuro_config without deleting storage"
        return 0
    fi

    rsuro_tmp="$(mktemp)" || return 1
    if ! awk -v key="$rsuro_slot" -v expected="$rsuro_expected" '
        BEGIN {prefix=key ": "; found=0; bad=0}
        index($0,prefix)==1 {
            rest=substr($0,length(prefix)+1)
            comma=index(rest,",")
            if (comma) vol=substr(rest,1,comma-1); else vol=rest
            if (vol != expected) {bad=1; print; next}
            found=1
            next
        }
        {print}
        END {
            if (bad) exit 42
            if (!found) exit 43
        }
    ' "$rsuro_config" > "$rsuro_tmp"; then
        rm -f "$rsuro_tmp"
        return 1
    fi
    if ! cat "$rsuro_tmp" > "$rsuro_config"; then rm -f "$rsuro_tmp"; return 1; fi
    rm -f "$rsuro_tmp"
    [ -z "$(disk_value "$SOURCE_VM" "$rsuro_slot" 2>/dev/null || :)" ] || return 1
    assert_lv_exists "$LV"
}

# remove_source_unused SLOT
# Removes only the source config's unusedN reference; it never frees the LV.
# Call: remove_source_unused SLOT
remove_source_unused() {
    rsu_slot="$1"; [ -n "$rsu_slot" ] || return 0
    info "Removing source config reference $SOURCE_VM $rsu_slot (LV is preserved)..."
    remove_source_unused_reference_only "$rsu_slot" "$SOURCE_VOLID" || die "Could not remove source unused reference without touching storage: $rsu_slot"
    if dryrun_enabled; then dryrun_verify "$rsu_slot would be removed from VM $SOURCE_VM without freeing $SOURCE_VOLID"; fi
}

# verify_transfer
# Verifies destination ownership and absence of the moved volume from source config.
verify_transfer() {
    if dryrun_enabled; then
        dryrun_verify "Destination VM $DEST_VM would own the moved disk reference"
        [ -z "$SOURCE_VM" ] || dryrun_verify "Source VM $SOURCE_VM would no longer reference $SOURCE_VOLID"
        return 0
    fi

    [ "$(disk_volid "$DEST_VM" "$DEST_SLOT" 2>/dev/null || :)" = "$SOURCE_VOLID" ] || die "Destination no longer references the moved volume."
    if [ -n "$SOURCE_VM" ] && qm config "$SOURCE_VM" | grep -F "$SOURCE_VOLID" >/dev/null 2>&1; then die "Source VM still references $SOURCE_VOLID after the move."; fi
    assert_lv_exists "$LV"
}

############################################################
# ROLLBACK / ERROR HANDLING
############################################################

install_transfer_traps() {
    trap transfer_on_exit 0
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
}

# rollback_source_attachment
#
# Description:
#   If an active source disk was detached and destination attachment never
#   touched the destination config, restores the original source slot/value.
#   The backing LV is never deleted by rollback.
#
# Usage:
#   Called only from transfer_on_exit.
#
# Arguments:
#   Uses transaction globals.
#
# Output:
#   Best-effort source config restoration.
#
# Returns:
#   0 on restored/not-needed; 1 when exact restoration fails.
############################################################
rollback_source_attachment() {
    [ "$SOURCE_DETACHED" -eq 1 ] || return 0
    [ "$DEST_TOUCHED" -eq 0 ] || return 0
    warn "Destination was not attached; attempting to restore $SOURCE_VM $SOURCE_SLOT."

    set +e
    rsa_cleanup=0
    if [ -n "$SOURCE_UNUSED" ] && [ -n "$(disk_value "$SOURCE_VM" "$SOURCE_UNUSED" 2>/dev/null)" ]; then
        remove_source_unused_reference_only "$SOURCE_UNUSED" "$SOURCE_VOLID" >/dev/null 2>&1 || rsa_cleanup=1
    fi
    if [ "$rsa_cleanup" -eq 0 ]; then qm set "$SOURCE_VM" "--$SOURCE_SLOT" "$SOURCE_VALUE" >/dev/null 2>&1; rsa_status=$?
    else rsa_status=1
    fi
    set -e

    if [ "$rsa_status" -eq 0 ] && [ "$(disk_volid "$SOURCE_VM" "$SOURCE_SLOT" 2>/dev/null || :)" = "$SOURCE_VOLID" ]; then
        ok "Source disk reference restored."
        SOURCE_DETACHED=0
        return 0
    fi
    warn "Automatic source restoration failed. The LV remains at $LV; keep the source VM stopped/paused and repair its config manually."
    return 1
}

# transfer_on_exit
# Preserves a safe source runtime state around failed/partial transactions.
transfer_on_exit() {
    toe_status=$?
    trap - 0 HUP INT TERM
    [ "$TRANSFER_COMPLETE" -eq 1 ] && { remove_temp_files; [ "$toe_status" -eq 0 ] || exit "$toe_status"; return 0; }

    toe_rollback=0
    if ! dryrun_enabled; then
        if rollback_source_attachment; then toe_rollback=1; fi
    else
        toe_rollback=1
    fi

    if [ "$STATE_RESTORED" -eq 0 ]; then
        if [ "$DEST_TOUCHED" -eq 1 ] || [ "$SOURCE_DETACHED" -eq 0 ] || [ "$toe_rollback" -eq 1 ]; then
            set +e
            restore_source_state
            set -e
        else
            warn "Source VM state was intentionally not restored because its disk reference could not be recovered."
        fi
    fi

    remove_temp_files
    [ "$toe_status" -eq 0 ] || exit "$toe_status"
    return 0
}

# remove_temp_files
# Removes process-owned reference catalogs only.
remove_temp_files() {
    [ -z "$REFS_FILE" ] || rm -f "$REFS_FILE"
    REFS_FILE=""
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
