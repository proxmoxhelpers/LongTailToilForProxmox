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
    define_colours
    parse_arguments "$@"
    check_elevation
}

# main [ARGS...]
# Call: main "$@"
# Performs preflight and the command's primary operation.
main() {
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    need_commands qm
    require_qemu_vm "$VMID"; require_guest_stopped "$VMID"
    detach_disk
}

# end
# Call: end
# Prints/finalizes the command result and performs normal completion cleanup.
end() { dryrun_summary; }

# usage
# Call: usage
# Prints command-line usage and exits only when the caller chooses to exit.
usage() {
    cat <<EOF
$(basename "$0") $SCRIPT_VERSION (project $PROJECT_VERSION)

USAGE
  $(basename "$0") <vmid> <disk-slot> [dryrun]

DESCRIPTION
  Detaches an active disk slot from a QEMU VM without deleting its backing
  volume. Proxmox preserves the detached volume as an unusedN reference.

SAFETY
  The VM must be stopped.

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
    pa_count=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            dryrun|--dryrun) enable_dryrun ;;
            -h|-\?|/h|/\?|--help) usage; exit 0 ;;
            --version) printf '%s %s (project %s)\n' "$(basename "$0")" "$SCRIPT_VERSION" "$PROJECT_VERSION"; exit 0 ;;
            *) pa_count=$((pa_count + 1)); case "$pa_count" in 1) VMID="$1" ;; 2) SLOT="$1" ;; *) usage >&2; exit 2 ;; esac ;;
        esac
        shift
    done
    [ "$pa_count" -eq 2 ] || { usage >&2; exit 2; }
}

############################################################
# HIGH LEVEL TASKS
############################################################

# detach_disk
# Removes SLOT from the active VM config while preserving its volume as unusedN.
# Call: detach_disk ARG1 [ARG2]
detach_disk() {
    VOLID="$(disk_volid "$VMID" "$SLOT" || :)"; [ -n "$VOLID" ] || die "No Proxmox volume found at $SLOT."
    info "Detaching $SLOT ($VOLID) from VM $VMID..."
    dryrun_cmd qm set "$VMID" --delete "$SLOT"
    if dryrun_enabled; then
        dryrun_verify "$SLOT would be detached"; UNUSED="unusedN"
    else
        [ -z "$(disk_value "$VMID" "$SLOT")" ] || die "$SLOT still exists after detach."
        UNUSED="$(qm config "$VMID" | awk -F': ' -v v="$VOLID" '$1 ~ /^unused[0-9]+$/ && index($2,v)==1 {print $1; exit}')"
    fi
    if [ -n "$UNUSED" ]; then ok "Detached. Volume preserved as $UNUSED: $VOLID"
    else warn "Detached, but no unusedN entry was found. Underlying volume was not explicitly deleted by this script."; fi
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
