#!/bin/sh
set -eu

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

print_banner() { printf '\n%s%s============================================================\n%s\n============================================================%s\n' "$C_BOLD" "$C_CYAN" "$1" "$C_RESET"; }
info() { printf '%s%s%s\n' "$C_CYAN" "$*" "$C_RESET"; }
ok() { printf '%s[OK]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%sWARNING:%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die() { printf '%sERROR:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }
section() { printf '\n%s%s%s\n' "$C_BOLD$C_CYAN" "$*" "$C_RESET"; }

# trim
# Removes leading and trailing POSIX whitespace from stdin.
trim() { sed 's/^[[:space:]]*//;s/[[:space:]]*$//'; }

############################################################
# PRIVILEGE / DEPENDENCIES
############################################################

# check_elevation
# Sets APP_ELEVATED to true or false and reports the current privilege state.
check_elevation() {
    if [ "$(id -u)" -eq 0 ]; then APP_ELEVATED="true"; ok "Elevation: running as root."
    else APP_ELEVATED="false"; warn "Elevation: not running as root."; fi
    export APP_ELEVATED
}

# self_elevate ARGS...
# Re-executes the current script through sudo while preserving all arguments.
self_elevate() {
    command -v sudo >/dev/null 2>&1 || die "Root privileges are required and sudo is unavailable."
    warn "Re-running with root privileges..."
    exec sudo -- /bin/sh "$0" "$@"
}

# require_command COMMAND
# Exits when COMMAND is unavailable.
require_command() { command -v "$1" >/dev/null 2>&1 || die "Required command is missing: $1"; }

# need_commands COMMAND...
# Requires every named command.
need_commands() { for nc_cmd in "$@"; do require_command "$nc_cmd"; done; }

############################################################
# TEMPORARY RESOURCE HELPERS
############################################################

# register_temp_file PATH
# Registers a process-owned temporary file for best-effort removal on exit.
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
resolve_volid_path() { pvesm path "$1" 2>/dev/null; }

# canonical_lv_path LV
# Prints the canonical LVM lv_path reported by LVM metadata.
canonical_lv_path() { lvs --noheadings -o lv_path "$1" 2>/dev/null | trim; }

# assert_lv_exists LV
# Exits unless LV exists.
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
dryrun_print_command() {
    printf '%s[DRYRUN]%s' "${C_YELLOW:-}" "${C_RESET:-}"
    for dpc_arg in "$@"; do printf ' '; shell_quote "$dpc_arg"; done
    printf '\n'
}

# dryrun_print_shell TEXT...
# Prints a descriptive shell operation that may include placeholders.
dryrun_print_shell() { printf '%s[DRYRUN]%s %s\n' "${C_YELLOW:-}" "${C_RESET:-}" "$*"; }

# dryrun_cmd COMMAND...
# Executes COMMAND normally or prints it and returns simulated success.
dryrun_cmd() {
    if dryrun_enabled; then dryrun_print_command "$@"; return 0; fi
    "$@"
}

# dryrun_verify DESCRIPTION
# Prints a simulated verification result during dry-run mode.
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
# SETUP / MAIN / END
############################################################

setup() {
    define_colours
    PROJECT_VERSION="3.4.4"; SCRIPT_VERSION="3.3.1"
    DEST_VG=""
    parse_arguments "$@"
    check_elevation
}

main() {
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    need_commands qm pvesm lvs
    resolve_source
    if [ -n "$DEST_VG" ]; then run_embedded_create_disk_copy_and_add_to_vm "$PATH_SRC" "$DST_VM" "$DEST_VG"
    else run_embedded_create_disk_copy_and_add_to_vm "$PATH_SRC" "$DST_VM"; fi
}

end() { :; }

############################################################
# COMMAND LINE
############################################################

usage() { printf 'Usage: %s <source-vmid> <source-slot> <destination-vmid> [destination-vg] [dryrun]\n' "$(basename "$0")"; dryrun_help; }

parse_arguments() {
    pa_count=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            dryrun|--dryrun) enable_dryrun ;;
            -h|--help) usage; exit 0 ;;
            --version) printf '%s %s (project %s)\n' "$(basename "$0")" "$SCRIPT_VERSION" "$PROJECT_VERSION"; exit 0 ;;
            *) pa_count=$((pa_count + 1)); case "$pa_count" in 1) SRC_VM="$1" ;; 2) SLOT="$1" ;; 3) DST_VM="$1" ;; 4) DEST_VG="$1" ;; *) usage >&2; exit 2 ;; esac ;;
        esac
        shift
    done
    [ "$pa_count" -ge 3 ] && [ "$pa_count" -le 4 ] || { usage >&2; exit 2; }
}

# resolve_source
# Resolves the requested source VM slot to an LVM-backed device path for the copy helper.
resolve_source() {
    require_qemu_vm "$SRC_VM"; require_qemu_vm "$DST_VM"
    cbv_volid="$(disk_volid "$SRC_VM" "$SLOT" || :)"; [ -n "$cbv_volid" ] || die "No disk volume found at $SLOT."
    PATH_SRC="$(resolve_volid_path "$cbv_volid" || :)"; [ -n "$PATH_SRC" ] || die "Cannot resolve $cbv_volid."
    lvs "$PATH_SRC" >/dev/null 2>&1 || die "Source disk is not LVM-backed: $PATH_SRC"
}

############################################################
# EMBEDDED COMPANION IMPLEMENTATIONS
############################################################

# run_embedded_create_disk_copy_and_add_to_vm
# Executes the bundled create-disk-copy-and-add-to-vm.sh implementation without requiring a companion file.
run_embedded_create_disk_copy_and_add_to_vm() {
    /bin/sh -s -- "$@" <<'__PROXMOX_LONGTAIL_EMBEDDED_CREATE_DISK_COPY_AND_ADD_TO_VM__'
#!/bin/sh
set -eu

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

print_banner() { printf '\n%s%s============================================================\n%s\n============================================================%s\n' "$C_BOLD" "$C_CYAN" "$1" "$C_RESET"; }
info() { printf '%s%s%s\n' "$C_CYAN" "$*" "$C_RESET"; }
ok() { printf '%s[OK]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%sWARNING:%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die() { printf '%sERROR:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }
section() { printf '\n%s%s%s\n' "$C_BOLD$C_CYAN" "$*" "$C_RESET"; }

# trim
# Removes leading and trailing POSIX whitespace from stdin.
trim() { sed 's/^[[:space:]]*//;s/[[:space:]]*$//'; }

############################################################
# PRIVILEGE / DEPENDENCIES
############################################################

# check_elevation
# Sets APP_ELEVATED to true or false and reports the current privilege state.
check_elevation() {
    if [ "$(id -u)" -eq 0 ]; then APP_ELEVATED="true"; ok "Elevation: running as root."
    else APP_ELEVATED="false"; warn "Elevation: not running as root."; fi
    export APP_ELEVATED
}

# self_elevate ARGS...
# Re-executes the current script through sudo while preserving all arguments.
self_elevate() {
    command -v sudo >/dev/null 2>&1 || die "Root privileges are required and sudo is unavailable."
    warn "Re-running with root privileges..."
    exec sudo -- /bin/sh "$0" "$@"
}

# require_command COMMAND
# Exits when COMMAND is unavailable.
require_command() { command -v "$1" >/dev/null 2>&1 || die "Required command is missing: $1"; }

# need_commands COMMAND...
# Requires every named command.
need_commands() { for nc_cmd in "$@"; do require_command "$nc_cmd"; done; }

############################################################
# TEMPORARY RESOURCE HELPERS
############################################################

# register_temp_file PATH
# Registers a process-owned temporary file for best-effort removal on exit.
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
resolve_volid_path() { pvesm path "$1" 2>/dev/null; }

# canonical_lv_path LV
# Prints the canonical LVM lv_path reported by LVM metadata.
canonical_lv_path() { lvs --noheadings -o lv_path "$1" 2>/dev/null | trim; }

# assert_lv_exists LV
# Exits unless LV exists.
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
dryrun_print_command() {
    printf '%s[DRYRUN]%s' "${C_YELLOW:-}" "${C_RESET:-}"
    for dpc_arg in "$@"; do printf ' '; shell_quote "$dpc_arg"; done
    printf '\n'
}

# dryrun_print_shell TEXT...
# Prints a descriptive shell operation that may include placeholders.
dryrun_print_shell() { printf '%s[DRYRUN]%s %s\n' "${C_YELLOW:-}" "${C_RESET:-}" "$*"; }

# dryrun_cmd COMMAND...
# Executes COMMAND normally or prints it and returns simulated success.
dryrun_cmd() {
    if dryrun_enabled; then dryrun_print_command "$@"; return 0; fi
    "$@"
}

# dryrun_verify DESCRIPTION
# Prints a simulated verification result during dry-run mode.
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

select_destination_storage() {
    [ -f /etc/pve/storage.cfg ] || die "Proxmox storage configuration not found: /etc/pve/storage.cfg"
    sds_matches="$(awk -v wanted_vg="$DEST_VG" '
        function flush() {
            if ((type=="lvm" || type=="lvmthin") && vg==wanted_vg &&
                (content=="" || content ~ /(^|,)images(,|$)/)) print type "|" id "|" pool
        }
        /^[^ \t][^:]*:[ \t]*/ {flush(); split($1,h,":"); type=h[1]; id=$2; vg=""; pool=""; content=""; next}
        $1=="vgname" {vg=$2; next}
        $1=="thinpool" {pool=$2; next}
        $1=="content" {content=$2; next}
        END {flush()}
    ' /etc/pve/storage.cfg)"
    sds_count="$(printf '%s\n' "$sds_matches" | awk 'NF {n++} END {print n+0}')"
    [ "$sds_count" -gt 0 ] || die "No Proxmox lvm/lvmthin image storage is configured for destination VG $DEST_VG."

    SELECTED_STORAGE=""
    if [ "$DEST_VG" = "$SOURCE_VG" ] && [ -n "$SOURCE_POOL" ]; then
        sds_same="$(printf '%s\n' "$sds_matches" | awk -F'|' -v p="$SOURCE_POOL" '$1=="lvmthin" && $3==p')"
        sds_same_count="$(printf '%s\n' "$sds_same" | awk 'NF {n++} END {print n+0}')"
        [ "$sds_same_count" -ne 1 ] || SELECTED_STORAGE="$(printf '%s\n' "$sds_same" | awk 'NF {print; exit}')"
    fi
    [ -n "$SELECTED_STORAGE" ] || [ "$sds_count" -ne 1 ] || SELECTED_STORAGE="$(printf '%s\n' "$sds_matches" | awk 'NF {print; exit}')"

    if [ -z "$SELECTED_STORAGE" ]; then
        warn "Multiple Proxmox image storages use destination VG $DEST_VG:"
        printf '%s\n' "$sds_matches" | while IFS='|' read -r sds_type sds_id sds_pool; do
            [ -n "$sds_type" ] || continue
            if [ -n "$sds_pool" ]; then printf '  %-8s %-20s thinpool=%s\n' "$sds_type" "$sds_id" "$sds_pool" >&2
            else printf '  %-8s %-20s\n' "$sds_type" "$sds_id" >&2; fi
        done
        die "Destination storage is ambiguous. Specify a VG with exactly one applicable storage."
    fi

    DEST_STORAGE_TYPE="${SELECTED_STORAGE%%|*}"
    sds_rest="${SELECTED_STORAGE#*|}"
    STORAGE_ID="${sds_rest%%|*}"
    DEST_POOL="${sds_rest#*|}"
    [ "$DEST_STORAGE_TYPE" != "lvmthin" ] || [ -n "$DEST_POOL" ] || die "Storage $STORAGE_ID is lvmthin but has no thinpool configured."
}

create_destination() {
    info "Creating destination LV..."
    if [ "$DEST_STORAGE_TYPE" = "lvmthin" ]; then
        if dryrun_enabled; then dryrun_cmd lvcreate -V "${SOURCE_SIZE_BYTES}B" -T "${DEST_VG}/${DEST_POOL}" -n "$NEW_LV_NAME"
        else run_lvm_filtered lvcreate -V "${SOURCE_SIZE_BYTES}B" -T "${DEST_VG}/${DEST_POOL}" -n "$NEW_LV_NAME"; fi
    else
        if dryrun_enabled; then dryrun_cmd lvcreate -L "${SOURCE_SIZE_BYTES}B" -n "$NEW_LV_NAME" "$DEST_VG"
        else run_lvm_filtered lvcreate -L "${SOURCE_SIZE_BYTES}B" -n "$NEW_LV_NAME" "$DEST_VG"; fi
    fi
    CREATED=1
    if dryrun_enabled; then
        DEST_SIZE_BYTES="$SOURCE_SIZE_BYTES"; dryrun_verify "Destination LV would exist with sufficient size"
    else
        lvs "${DEST_VG}/${NEW_LV_NAME}" >/dev/null 2>&1 || die "lvcreate returned successfully, but the destination LV cannot be found."
        DEST_SIZE_BYTES="$(blockdev --getsize64 "$NEW_LV_PATH")"
        [ "$DEST_SIZE_BYTES" -ge "$SOURCE_SIZE_BYTES" ] || die "Destination LV is smaller than the source."
    fi
}

verify_storage_mapping() {
    if dryrun_enabled; then PVE_PATH="$NEW_LV_PATH"; dryrun_verify "Proxmox storage $STORAGE_ID would resolve $NEW_VOLID"
    else PVE_PATH="$(pvesm path "$NEW_VOLID" 2>/dev/null || :)"; [ -n "$PVE_PATH" ] || die "Proxmox storage $STORAGE_ID cannot resolve $NEW_VOLID."; fi
    if ! dryrun_enabled; then [ "$(readlink -f "$PVE_PATH")" = "$(readlink -f "$NEW_LV_PATH")" ] || die "Proxmox storage mapping does not point to the newly created LV."; fi
}

copy_data() {
    info "Copying data..."
    if [ "$DEST_STORAGE_TYPE" = "lvmthin" ]; then dryrun_cmd dd if="$SOURCE_PATH" of="$NEW_LV_PATH" bs=4M iflag=fullblock conv=sparse,fsync status=progress
    else dryrun_cmd dd if="$SOURCE_PATH" of="$NEW_LV_PATH" bs=4M iflag=fullblock conv=fsync status=progress; fi
    ok "Copy completed."
}

verify_copy() {
    info "Verifying copied data..."
    if dryrun_enabled; then dryrun_verify "cmp would verify $SOURCE_SIZE_BYTES bytes"
    elif ! cmp -n "$SOURCE_SIZE_BYTES" "$SOURCE_PATH" "$NEW_LV_PATH"; then die "Block verification failed; the destination copy does not match the source."; fi
    ok "Verification passed."
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
verify_destination_boot_first() {
    [ "$BOOT_REQUESTED" -eq 1 ] || return 0
    if dryrun_enabled; then dryrun_verify "VM $1 boot order would start with $2"; return 0; fi
    qm config "$1" | grep -qE "^boot:.*order=${2}([;,]|$)" || die "Requested boot slot is not first in the boot order."
}

############################################################
# SETUP / MAIN / END
############################################################

setup() {
    define_colours
    PROJECT_VERSION="3.4.4"; SCRIPT_VERSION="3.4.4"
    MODE="hot"; MODE_ARG=""
    ARG_COUNT=0; ARG1=""; ARG2=""; ARG3=""; ARG4=""; ARG5=""
    SOURCE_FORM=""; SOURCE_INPUT=""; SOURCE_VM_INPUT=""; SOURCE_SELECTOR=""
    SOURCE_VM=""; SOURCE_SLOT=""; SOURCE_ACTIVE=0; SOURCE_STATUS=""
    REQUESTED_DEST_DISK=""; REQUESTED_DEST_SLOT_SELECTOR=""; REQUESTED_DEST_VG=""
    BOOT_REQUESTED=0; BOOT_ORDER_APPLIED=0
    CREATED=0; ATTACHED=0; COMPLETE=0; PAUSED_BY_US=0; STOPPED_BY_US=0
    parse_arguments "$@"
    check_elevation
}

main() {
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    need_commands lvs vgs lvcreate lvremove qm pvesm blockdev readlink awk grep sed dd cmp sort tail find
    resolve_source
    validate_destination_vm
    resolve_destination_attachment
    DEST_VG="${REQUESTED_DEST_VG:-$SOURCE_VG}"
    vgs "$DEST_VG" >/dev/null 2>&1 || die "Destination volume group does not exist: $DEST_VG"
    select_destination_storage
    select_disk_name
    TARGET_STATUS="$(qm status "$DEST_VMID" 2>/dev/null | awk '{print $2}' || :)"
    print_plan
    install_transaction_traps
    apply_source_state
    create_destination
    verify_storage_mapping
    copy_data
    verify_copy
    attach_copy
    set_destination_boot_first "$DEST_VMID" "$SCSI_DEVICE"
    restore_source_state
    verify_result
    COMPLETE=1
    trap - 0 HUP INT TERM
}

end() {
    print_banner "Disk copied and attached successfully"
    printf 'Source:           %s\n' "$SOURCE_PATH"
    [ -z "$SOURCE_VM" ] || printf 'Source VM:        %s%s\n' "$SOURCE_VM" "${SOURCE_SLOT:+ ($SOURCE_SLOT)}"
    printf 'Copy:             %s\n' "$NEW_LV_PATH"
    printf 'Proxmox volume:   %s\n' "$NEW_VOLID"
    printf 'Destination VM:   %s\n' "$DEST_VMID"
    printf 'Attached as:      %s\n' "$SCSI_DEVICE"
    printf 'Backing disk:     disk-%s\n' "$DISK_NUMBER"
    printf 'State mode:       %s\n\n' "$MODE"
    dryrun_summary
}

############################################################
# COMMAND LINE
############################################################

usage() {
    cat <<EOF
$(basename "$0") $SCRIPT_VERSION (project $PROJECT_VERSION)

USAGE
  $(basename "$0") <source-lv-path> <dest-vmid> [dest-disk-N|dest-slot|dest-bus] [dest-vg] [hot|pause|stop|restart] [boot] [dryrun]
  $(basename "$0") <source-vmid> <source-disk-N|source-slot> <dest-vmid> [dest-disk-N|dest-slot|dest-bus] [dest-vg] [hot|pause|stop|restart] [boot] [dryrun]

DESCRIPTION
  Creates a full independent copy of an LVM-backed source disk and attaches it
  to a destination QEMU VM.

SOURCE SELECTORS
  <source-lv-path>      Full LVM path such as /dev/pve/vm-123-disk-0 or /dev/pve/base-123-disk-0.
  <source-vmid> disk-N  Resolve a vm-*/base-* managed backing volume by disk number.
  <source-vmid> sata0   Resolve an exact configured QEMU disk slot.
  Exact source slots must already exist and must be storage-backed disks.

DESTINATION SELECTORS
  omitted      Attach to the first free SCSI slot; choose the next free disk-N.
  disk-N       Use that backing disk number; attach to the first free SCSI slot.
  sata0        Attach specifically at sata0; choose the next free backing disk-N.
  ide2         Attach specifically at ide2.
  scsi4        Attach specifically at scsi4.
  virtio0      Attach specifically at virtio0.
  sata         Attach to the first free SATA slot.
  ide          Attach to the first free IDE slot.
  scsi         Attach to the first free SCSI slot.
  virtio       Attach to the first free VirtIO slot.

  Exact destination slots must be empty. Use an overwrite helper when the
  selected slot is already occupied.

SOURCE VM STATE
  default/hot  Do not pause or stop the source VM.
  pause        Pause a running source VM while the copy is created and verified.
  stop         Stop a running source VM and leave it stopped.
  restart      Stop a running source VM, create/verify/attach the copy, then start it.

OPTIONAL KEYWORDS
  boot         Make the actual destination slot the first device in VM boot order.
  dryrun       Perform real read-only preflight and print mutations without executing them.

  hot, pause, stop, restart, boot, dryrun and --dryrun may appear anywhere.

BACKWARD COMPATIBILITY
  In the full-path form, a non-selector third positional value is still treated
  as destination-vg, matching the previous interface.

EXAMPLES
  $(basename "$0") /dev/pve/vm-123-disk-0 456 sata boot dryrun
  $(basename "$0") 123 sata0 456 virtio0 restart boot dryrun
  $(basename "$0") 123 disk-0 456 disk-3 fastvg pause dryrun
  $(basename "$0") /dev/pve/vm-123-disk-0 456 fastvg dryrun

EOF
    dryrun_help
}

parse_arguments() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            dryrun|--dryrun) enable_dryrun ;;
            hot|pause|stop|restart) set_state_mode "$1" ;;
            boot) BOOT_REQUESTED=1 ;;
            -h|--help) usage; exit 0 ;;
            --version) printf '%s %s (project %s)\n' "$(basename "$0")" "$SCRIPT_VERSION" "$PROJECT_VERSION"; exit 0 ;;
            *)
                ARG_COUNT=$((ARG_COUNT + 1))
                case "$ARG_COUNT" in
                    1) ARG1="$1" ;; 2) ARG2="$1" ;; 3) ARG3="$1" ;; 4) ARG4="$1" ;; 5) ARG5="$1" ;;
                    *) usage >&2; exit 2 ;;
                esac
                ;;
        esac
        shift
    done

    case "$ARG1" in
        /*)
            [ "$ARG_COUNT" -ge 2 ] && [ "$ARG_COUNT" -le 4 ] || { usage >&2; exit 2; }
            SOURCE_FORM="path"; SOURCE_INPUT="$ARG1"; DEST_VMID="$ARG2"
            if [ "$ARG_COUNT" -ge 3 ]; then
                if ! assign_destination_selector "$ARG3"; then
                    case "$ARG3" in ide*|sata*|scsi*|virtio*) die "Invalid destination slot/bus selector: $ARG3" ;; esac
                    REQUESTED_DEST_VG="$ARG3"
                fi
            fi
            if [ "$ARG_COUNT" -eq 4 ]; then
                [ -n "$REQUESTED_DEST_DISK$REQUESTED_DEST_SLOT_SELECTOR" ] || die "When four positional arguments are used, the third must be a destination selector and the fourth destination-vg."
                REQUESTED_DEST_VG="$ARG4"
            fi
            ;;
        *)
            [ "$ARG_COUNT" -ge 3 ] && [ "$ARG_COUNT" -le 5 ] || { usage >&2; exit 2; }
            SOURCE_FORM="vm"; SOURCE_VM_INPUT="$ARG1"; SOURCE_SELECTOR="$ARG2"; DEST_VMID="$ARG3"
            if [ "$ARG_COUNT" -ge 4 ]; then
                if ! assign_destination_selector "$ARG4"; then
                    case "$ARG4" in ide*|sata*|scsi*|virtio*) die "Invalid destination slot/bus selector: $ARG4" ;; esac
                    REQUESTED_DEST_VG="$ARG4"
                fi
            fi
            if [ "$ARG_COUNT" -eq 5 ]; then
                [ -n "$REQUESTED_DEST_DISK$REQUESTED_DEST_SLOT_SELECTOR" ] || die "When five positional arguments are used, the fourth must be a destination selector and the fifth destination-vg."
                REQUESTED_DEST_VG="$ARG5"
            fi
            ;;
    esac
}

############################################################
# VALIDATION / PRE-FLIGHT
############################################################


# assign_destination_selector SELECTOR
# Classifies and stores a backing disk number, exact slot, or destination bus.
assign_destination_selector() {
    ads_value="$1"
    if ! ads_kind="$(destination_selector_kind "$ads_value" 2>/dev/null)"; then return 1; fi
    case "$ads_kind" in
        disk) REQUESTED_DEST_DISK="$(normalize_disk_number "$ads_value")" ;;
        slot|bus) REQUESTED_DEST_SLOT_SELECTOR="$ads_value" ;;
        *) return 1 ;;
    esac
    return 0
}

# resolve_destination_attachment
# Resolves the requested exact/bus destination selector to a currently free slot.
resolve_destination_attachment() {
    if [ -z "$REQUESTED_DEST_SLOT_SELECTOR" ]; then
        SCSI_DEVICE="$(first_free_scsi "$DEST_VMID")" || die "No free SCSI disk slot is available on VM $DEST_VMID."
        return 0
    fi

    case "$REQUESTED_DEST_SLOT_SELECTOR" in
        ide|sata|scsi|virtio)
            SCSI_DEVICE="$(first_free_bus_slot "$DEST_VMID" "$REQUESTED_DEST_SLOT_SELECTOR")" || die "No free $REQUESTED_DEST_SLOT_SELECTOR disk slot is available on VM $DEST_VMID."
            ;;
        *)
            valid_disk_slot "$REQUESTED_DEST_SLOT_SELECTOR" || die "Unsupported destination disk slot: $REQUESTED_DEST_SLOT_SELECTOR"
            SCSI_DEVICE="$REQUESTED_DEST_SLOT_SELECTOR"
            rda_value="$(disk_value "$DEST_VMID" "$SCSI_DEVICE" 2>/dev/null || :)"
            [ -z "$rda_value" ] || die "Destination slot $SCSI_DEVICE is already occupied; use an overwrite helper to replace it."
            ;;
    esac
}

validate_destination_vm() {
    require_qemu_vm "$DEST_VMID"
    TARGET_CONFIG="/etc/pve/qemu-server/${DEST_VMID}.conf"
    TARGET_QM_CONFIG="$(qm config "$DEST_VMID")"
    if printf '%s\n' "$TARGET_QM_CONFIG" | grep -qE '^lock:[[:space:]]*'; then die "Destination VM $DEST_VMID is locked; resolve the lock first."; fi
    DEST_PREFIX="vm"
    if printf '%s\n' "$TARGET_QM_CONFIG" | grep -qE '^template:[[:space:]]*1([[:space:]]|$)'; then DEST_PREFIX="base"; fi
}

# select_disk_name
# Chooses the requested backing disk number, or the next collision-free number.
# Templates receive base-DEST-disk-N names; normal VMs receive vm-DEST-disk-N.
select_disk_name() {
    if [ -n "$REQUESTED_DEST_DISK" ]; then
        DISK_NUMBER="$REQUESTED_DEST_DISK"
        NEW_LV_NAME="${DEST_PREFIX}-${DEST_VMID}-disk-${DISK_NUMBER}"
        NEW_LV_PATH="/dev/${DEST_VG}/${NEW_LV_NAME}"
        NEW_VOLID="${STORAGE_ID}:${NEW_LV_NAME}"
        if printf '%s\n' "$TARGET_QM_CONFIG" | grep -qE "(vm|base)-[0-9]+-disk-${DISK_NUMBER}([,[:space:]]|$)"; then die "Destination VM already has a managed backing volume with disk number $DISK_NUMBER."; fi
        if lvs "${DEST_VG}/${NEW_LV_NAME}" >/dev/null 2>&1; then die "Destination LV already exists: $NEW_LV_PATH"; fi
        return 0
    fi

    sdn_highest="$(printf '%s\n' "$TARGET_QM_CONFIG" | grep -oE "(vm|base)-[0-9]+-disk-[0-9]+" | sed -E 's/.*-disk-([0-9]+)$/\1/' | sort -n | tail -n1 || :)"
    if [ -n "$sdn_highest" ]; then DISK_NUMBER=$((sdn_highest + 1)); else DISK_NUMBER=0; fi
    while :; do
        NEW_LV_NAME="${DEST_PREFIX}-${DEST_VMID}-disk-${DISK_NUMBER}"
        NEW_LV_PATH="/dev/${DEST_VG}/${NEW_LV_NAME}"
        NEW_VOLID="${STORAGE_ID}:${NEW_LV_NAME}"
        sdn_busy=0
        printf '%s\n' "$TARGET_QM_CONFIG" | grep -qE "(vm|base)-[0-9]+-disk-${DISK_NUMBER}([,[:space:]]|$)" && sdn_busy=1 || :
        lvs "${DEST_VG}/${NEW_LV_NAME}" >/dev/null 2>&1 && sdn_busy=1 || :
        [ "$sdn_busy" -eq 0 ] && break
        DISK_NUMBER=$((DISK_NUMBER + 1))
    done
}

############################################################
# HIGH LEVEL TASKS
############################################################

print_plan() {
    print_banner "Create independent disk copy and attach to VM"
    printf 'Source LV:             %s\n' "$SOURCE_PATH"
    [ -z "$SOURCE_VM" ] || printf 'Source VM:             %s%s\n' "$SOURCE_VM" "${SOURCE_SLOT:+ ($SOURCE_SLOT)}"
    printf 'Source state mode:     %s\n' "$MODE"
    printf 'Source size:           %s bytes\n' "$SOURCE_SIZE_BYTES"
    printf 'Destination VG:        %s\n' "$DEST_VG"
    printf 'Destination storage:   %s (%s)\n' "$STORAGE_ID" "$DEST_STORAGE_TYPE"
    [ "$DEST_STORAGE_TYPE" != "lvmthin" ] || printf 'Destination thin pool: %s\n' "$DEST_POOL"
    printf 'Destination VM:        %s\n' "$DEST_VMID"
    printf 'Destination VM status: %s\n' "${TARGET_STATUS:-unknown}"
    printf 'New LV:                %s\n' "$NEW_LV_PATH"
    printf 'Backing disk number:   disk-%s\n' "$DISK_NUMBER"
    printf 'Attach as:             %s\n' "$SCSI_DEVICE"
    printf 'First boot device:     %s\n\n' "$([ "$BOOT_REQUESTED" -eq 1 ] && printf '%s' "$SCSI_DEVICE" || printf '%s' unchanged)"
    [ "$MODE" != "hot" ] || warn "Hot mode does not quiesce the source VM; the source can change while the copy runs."
}

attach_copy() {
    ac_now="$(disk_value "$DEST_VMID" "$SCSI_DEVICE" 2>/dev/null || :)"
    [ -z "$ac_now" ] || die "Destination slot $SCSI_DEVICE became occupied after preflight; refusing to attach the copied disk."
    info "Attaching $NEW_VOLID to VM $DEST_VMID as $SCSI_DEVICE..."
    if ! dryrun_cmd qm set "$DEST_VMID" "--${SCSI_DEVICE}" "$NEW_VOLID"; then
        if qm config "$DEST_VMID" 2>/dev/null | grep -qF "$NEW_VOLID"; then ATTACHED=1; fi
        die "Could not attach the copied disk to VM $DEST_VMID."
    fi
    ATTACHED=1
}

verify_result() {
    if dryrun_enabled; then
        dryrun_verify "Destination LV would exist"
        dryrun_verify "VM $DEST_VMID would reference $NEW_VOLID at $SCSI_DEVICE"
        dryrun_verify "Source guest state would match the requested $MODE mode"
        verify_destination_boot_first "$DEST_VMID" "$SCSI_DEVICE"
        return 0
    fi
    lvs "${DEST_VG}/${NEW_LV_NAME}" >/dev/null 2>&1 || die "Destination LV is missing."
    vr_config="$(qm config "$DEST_VMID")"
    printf '%s\n' "$vr_config" | grep -qE "^${SCSI_DEVICE}:.*${NEW_VOLID}([,[:space:]]|$)" || die "Expected destination attachment is missing."
    verify_destination_boot_first "$DEST_VMID" "$SCSI_DEVICE"
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

cleanup_on_exit() {
    coe_status=$?
    trap - 0 HUP INT TERM
    set +e

    if [ "$MODE" = "pause" ] && [ "$PAUSED_BY_US" -eq 1 ] && [ -n "$SOURCE_VM" ]; then
        if dryrun_enabled; then dryrun_cmd qm resume "$SOURCE_VM"; else qm resume "$SOURCE_VM" >/dev/null 2>&1; fi
        PAUSED_BY_US=0
    elif [ "$MODE" = "restart" ] && [ "$STOPPED_BY_US" -eq 1 ] && [ -n "$SOURCE_VM" ]; then
        if dryrun_enabled; then dryrun_cmd qm start "$SOURCE_VM"; else qm start "$SOURCE_VM" >/dev/null 2>&1; fi
        STOPPED_BY_US=0
    fi

    if ! dryrun_enabled && [ "$CREATED" -eq 1 ] && [ "$ATTACHED" -eq 0 ] && [ "$COMPLETE" -eq 0 ]; then
        if ! guest_volume_references | grep -F "|$NEW_VOLID" >/dev/null 2>&1; then
            warn "Removing incomplete/unattached destination LV: $NEW_LV_PATH"
            lvremove -y "${DEST_VG}/${NEW_LV_NAME}" >/dev/null 2>&1 || warn "Could not remove $NEW_LV_PATH automatically."
        fi
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
__PROXMOX_LONGTAIL_EMBEDDED_CREATE_DISK_COPY_AND_ADD_TO_VM__
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
