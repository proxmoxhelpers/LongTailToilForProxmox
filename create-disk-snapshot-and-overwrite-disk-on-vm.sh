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
        scsi[0-9]*|sata[0-9]*|virtio[0-9]*|ide[0-9]*|unused[0-9]*)
            rvds_value="$(disk_value "$rvds_vm" "$rvds_selector")"
            [ -n "$rvds_value" ] || die "VM $rvds_vm has no disk at $rvds_selector."
            printf '%s\n' "$rvds_selector"
            return 0
            ;;
    esac
    rvds_num="$(normalize_disk_number "$rvds_selector" 2>/dev/null || :)"
    [ -n "$rvds_num" ] || die "Disk selector must be N, disk-N, or an explicit QEMU disk slot."
    rvds_name="vm-${rvds_vm}-disk-${rvds_num}"
    rvds_slots="$(qm config "$rvds_vm" | awk -F': ' -v name="$rvds_name" '
        $1 ~ /^(scsi|sata|virtio|ide|unused)[0-9]+$/ {
            split($2,a,","); v=a[1]; sub(/^[^:]+:/,"",v)
            if (v == name) print $1
        }')"
    rvds_count="$(printf '%s\n' "$rvds_slots" | awk 'NF {n++} END {print n+0}')"
    [ "$rvds_count" -gt 0 ] || die "VM $rvds_vm has no configured backing volume named $rvds_name."
    [ "$rvds_count" -eq 1 ] || { printf '%s\n' "$rvds_slots" >&2; die "$rvds_name matches multiple VM slots."; }
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
    SOURCE_SIZE_BYTES="$(blockdev --getsize64 "$SOURCE_PATH" 2>/dev/null || :)"
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


############################################################
# DESTINATION RESOLUTION / STATE
############################################################

# resolve_destination
# Resolves either full LV path or VMID + disk selector to one active QEMU slot.
resolve_destination() {
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
    else
        DEST_VM="$DEST_VM_INPUT"
        require_qemu_vm "$DEST_VM"
        DEST_SLOT="$(resolve_vm_disk_slot "$DEST_VM" "$DEST_SELECTOR")"
        case "$DEST_SLOT" in unused*) die "Overwrite destination must be an active disk slot, not $DEST_SLOT." ;; esac
        DEST_OLD_VALUE="$(disk_value "$DEST_VM" "$DEST_SLOT")"
        [ -n "$DEST_OLD_VALUE" ] || die "VM $DEST_VM has no disk at $DEST_SLOT."
        DEST_OLD_VOLID="${DEST_OLD_VALUE%%,*}"
        rd_path="$(pvesm path "$DEST_OLD_VOLID" 2>/dev/null || :)"
        [ -n "$rd_path" ] || die "Could not resolve destination volume $DEST_OLD_VOLID."
        assert_lv_exists "$rd_path"
        DEST_OLD_PATH="$(canonical_lv_path "$rd_path")"
        DEST_OLD_UUID="$(lvs --noheadings -o lv_uuid "$DEST_OLD_PATH" 2>/dev/null | trim)"
    fi

    DEST_CONFIG="$(qm config "$DEST_VM")"
    if printf '%s\n' "$DEST_CONFIG" | grep -qE '^lock:[[:space:]]*'; then die "Destination VM $DEST_VM is locked; resolve the lock first."; fi
    DEST_OLD_VALUE="$(disk_value "$DEST_VM" "$DEST_SLOT")"
    [ -n "$DEST_OLD_VALUE" ] || die "Destination slot $DEST_SLOT disappeared during preflight."
    case "$DEST_OLD_VALUE" in *,media=cdrom*) die "Refusing to overwrite CD-ROM/cloud media."; esac
    [ "${DEST_OLD_VALUE%%,*}" = "$DEST_OLD_VOLID" ] || die "Destination slot changed during preflight."
    DEST_OPTIONS="$(printf '%s\n' "$DEST_OLD_VALUE" | awk -F',' '{out=""; for(i=2;i<=NF;i++) if($i !~ /^size=/) out=out "," $i; print out}')"
    DEST_STATUS="$(qm status "$DEST_VM" 2>/dev/null | awk '{print $2}' || :)"
    DEST_VG="$(lvs --noheadings -o vg_name "$DEST_OLD_PATH" 2>/dev/null | trim)"
    DEST_OLD_LV="$(lvs --noheadings -o lv_name "$DEST_OLD_PATH" 2>/dev/null | trim)"
    DEST_OLD_POOL="$(lvs --noheadings -o pool_lv "$DEST_OLD_PATH" 2>/dev/null | trim)"
    [ -n "$DEST_VG" ] && [ -n "$DEST_OLD_LV" ] || die "Destination disk is not LVM-backed."
}

# apply_destination_state
# Applies the requested hot/pause/stop/restart policy to the VM losing a disk.
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
old_unused_key() {
    qm config "$DEST_VM" 2>/dev/null | awk -F': ' -v vol="$DEST_OLD_VOLID" '
        $1 ~ /^unused[0-9]+$/ {split($2,a,","); if(a[1]==vol) print $1}
    ' | head -n1
}

# rollback_old_disk
# Attempts to restore the exact original destination slot/value after attach failure.
rollback_old_disk() {
    [ "$OLD_DETACHED" -eq 1 ] || return 0
    [ "$NEW_ATTACHED" -eq 0 ] || return 1
    warn "Attempting to restore original destination disk $DEST_OLD_VOLID at $DEST_SLOT."
    if ! dryrun_cmd qm set "$DEST_VM" "--${DEST_SLOT}" "$DEST_OLD_VALUE"; then warn "Could not restore original destination disk automatically."; return 1; fi
    if ! dryrun_enabled; then
        rod_unused="$(old_unused_key)"
        [ -z "$rod_unused" ] || qm set "$DEST_VM" --delete "$rod_unused" >/dev/null 2>&1 || :
    fi
    OLD_DETACHED=0
    return 0
}

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

create_snapshot() {
    info "Creating LVM-thin snapshot..."
    if dryrun_enabled; then dryrun_cmd lvcreate --snapshot --name "$NEW_LV_NAME" "${SOURCE_VG}/${SOURCE_LV}"
    else run_lvm_filtered lvcreate --snapshot --name "$NEW_LV_NAME" "${SOURCE_VG}/${SOURCE_LV}"; fi
    CREATED=1
    if dryrun_enabled; then
        NEW_REAL="$NEW_LV_PATH"; NEW_ORIGIN="$SOURCE_LV"; NEW_POOL="$SOURCE_POOL"
        dryrun_verify "Snapshot LV would exist with expected origin and thin pool"
    else
        lvs "${SOURCE_VG}/${NEW_LV_NAME}" >/dev/null 2>&1 || die "lvcreate returned successfully, but the snapshot cannot be found."
        NEW_REAL="$(lvs --noheadings -o lv_path "${SOURCE_VG}/${NEW_LV_NAME}" 2>/dev/null | trim)"
        NEW_ORIGIN="$(lvs --noheadings -o origin "${SOURCE_VG}/${NEW_LV_NAME}" 2>/dev/null | trim)"
        NEW_POOL="$(lvs --noheadings -o pool_lv "${SOURCE_VG}/${NEW_LV_NAME}" 2>/dev/null | trim)"
    fi
    [ "$NEW_ORIGIN" = "$SOURCE_LV" ] && [ "$NEW_POOL" = "$SOURCE_POOL" ] || die "Snapshot origin/thin-pool verification failed."
}

verify_storage_mapping() {
    if dryrun_enabled; then PVE_PATH="$NEW_LV_PATH"; dryrun_verify "Proxmox storage $STORAGE_ID would resolve $NEW_VOLID"
    else PVE_PATH="$(pvesm path "$NEW_VOLID" 2>/dev/null || :)"; fi
    [ -n "$PVE_PATH" ] || die "Proxmox storage could not resolve the new snapshot."
    [ "$(readlink -f "$PVE_PATH")" = "$(readlink -f "$NEW_REAL")" ] || die "Proxmox storage mapping does not point to the new LV."
}


############################################################
# SETUP / MAIN / END
############################################################

setup() {
    define_colours
    PROJECT_VERSION="3.2.0"; SCRIPT_VERSION="3.2.0"
    MODE="hot"; MODE_ARG=""
    ARG_COUNT=0; ARG1=""; ARG2=""; ARG3=""; ARG4=""
    SOURCE_FORM=""; SOURCE_INPUT=""; SOURCE_VM_INPUT=""; SOURCE_SELECTOR=""
    SOURCE_VM=""; SOURCE_SLOT=""; SOURCE_ACTIVE=0; SOURCE_STATUS=""
    DEST_FORM=""; DEST_INPUT=""; DEST_VM_INPUT=""; DEST_SELECTOR=""
    CREATED=0; OLD_DETACHED=0; NEW_ATTACHED=0; COMPLETE=0; PAUSED_BY_US=0; STOPPED_BY_US=0
    parse_arguments "$@"
    check_elevation
}

main() {
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    need_commands lvs lvcreate lvremove qm pvesm blockdev readlink awk grep sed sort tail find
    ro_saved_mode="$MODE"; MODE="hot"; resolve_source; MODE="$ro_saved_mode"
    [ -n "$SOURCE_POOL" ] || { printf 'Source: %s\nLV attributes: %s\n' "$SOURCE_PATH" "$SOURCE_ATTR"; die "Source is not an LVM-thin volume."; }
    resolve_destination
    [ "$SOURCE_UUID" != "$DEST_OLD_UUID" ] || die "Source and destination refer to the same logical volume."
    select_storage
    select_new_disk_name
    print_plan
    install_transaction_traps
    create_snapshot
    verify_storage_mapping
    apply_destination_state
    replace_destination_disk
    restore_destination_state
    verify_result
    COMPLETE=1
    trap - 0 HUP INT TERM
}

end() {
    print_banner "Destination disk overwritten with linked snapshot"
    printf 'Source:          %s\n' "$SOURCE_PATH"
    printf 'Destination VM:  %s\n' "$DEST_VM"
    printf 'Replaced slot:   %s\n' "$DEST_SLOT"
    printf 'Old volume:      %s (preserved as unusedN)\n' "$DEST_OLD_VOLID"
    printf 'Snapshot:        %s\n' "$NEW_VOLID"
    printf 'State mode:      %s\n\n' "$MODE"
    dryrun_summary
}

############################################################
# COMMAND LINE
############################################################

usage() {
    cat <<EOF
$(basename "$0") $SCRIPT_VERSION (project $PROJECT_VERSION)

USAGE
  $(basename "$0") <source-lv-path> <destination-lv-path> [hot|pause|stop|restart] [dryrun]
  $(basename "$0") <source-lv-path> <dest-vmid> <dest-disk-N|slot> [hot|pause|stop|restart] [dryrun]
  $(basename "$0") <source-vmid> <source-disk-N|slot> <destination-lv-path> [hot|pause|stop|restart] [dryrun]
  $(basename "$0") <source-vmid> <source-disk-N|slot> <dest-vmid> <dest-disk-N|slot> [hot|pause|stop|restart] [dryrun]

DESCRIPTION
  Creates an LVM-thin snapshot of the source and replaces the destination VM
  disk slot with that linked snapshot.

  The displaced destination volume is NOT deleted. Proxmox preserves it as
  unusedN so the previous disk remains recoverable.

DESTINATION VM STATE
  default   Hot-swap: replace the disk without pausing/stopping the VM.
  pause     Pause a running destination VM before replacing the disk, then resume.
  stop      Stop a running destination VM before replacement and leave it stopped.
  restart   Stop a running destination VM, replace the disk, then start it.

  The state keyword applies to the destination VM because it is the VM losing
  the existing disk. The source VM is not automatically quiesced.

EXAMPLES
  $(basename "$0") /dev/pve/vm-123-disk-0 456 disk-1 dryrun
  $(basename "$0") 123 disk-0 456 disk-1 pause dryrun
  $(basename "$0") /dev/pve/vm-123-disk-0 /dev/pve/vm-456-disk-1 restart dryrun

EOF
    dryrun_help
}

parse_arguments() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            dryrun|--dryrun) enable_dryrun ;;
            hot|pause|stop|restart) set_state_mode "$1" ;;
            -h|--help) usage; exit 0 ;;
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

# select_new_disk_name
# Chooses a collision-free vm-DESTVMID-disk-N snapshot name in SOURCE_VG.
select_new_disk_name() {
    snd_highest="$(printf '%s\n' "$DEST_CONFIG" | grep -oE "vm-${DEST_VM}-disk-[0-9]+" | sed -E 's/.*-disk-([0-9]+)$/\1/' | sort -n | tail -n1 || :)"
    if [ -n "$snd_highest" ]; then NEW_DISK_NUMBER=$((snd_highest + 1)); else NEW_DISK_NUMBER=0; fi
    while :; do
        NEW_LV_NAME="vm-${DEST_VM}-disk-${NEW_DISK_NUMBER}"
        NEW_LV_PATH="/dev/${SOURCE_VG}/${NEW_LV_NAME}"
        NEW_VOLID="${STORAGE_ID}:${NEW_LV_NAME}"
        snd_busy=0
        printf '%s\n' "$DEST_CONFIG" | grep -qF "$NEW_LV_NAME" && snd_busy=1 || :
        lvs "${SOURCE_VG}/${NEW_LV_NAME}" >/dev/null 2>&1 && snd_busy=1 || :
        [ "$snd_busy" -eq 0 ] && break
        NEW_DISK_NUMBER=$((NEW_DISK_NUMBER + 1))
    done
}

############################################################
# HIGH LEVEL TASKS
############################################################

print_plan() {
    print_banner "Overwrite VM disk with linked snapshot"
    printf 'Source LV:              %s\n' "$SOURCE_PATH"
    [ -z "$SOURCE_VM" ] || printf 'Source VM:              %s%s\n' "$SOURCE_VM" "${SOURCE_SLOT:+ ($SOURCE_SLOT)}"
    printf 'Source thin pool:       %s/%s\n' "$SOURCE_VG" "$SOURCE_POOL"
    printf 'Snapshot storage:       %s\n' "$STORAGE_ID"
    printf 'Destination VM:         %s\n' "$DEST_VM"
    printf 'Destination VM status:  %s\n' "${DEST_STATUS:-unknown}"
    printf 'Destination state mode: %s\n' "$MODE"
    printf 'Replace slot:           %s\n' "$DEST_SLOT"
    printf 'Old volume:             %s\n' "$DEST_OLD_VOLID"
    printf 'New snapshot:           %s\n\n' "$NEW_VOLID"
    warn "The displaced destination volume will be preserved as unusedN."
}

# replace_destination_disk
# Detaches the old disk into unusedN, then attaches the snapshot at the exact slot.
replace_destination_disk() {
    rdd_now="$(disk_value "$DEST_VM" "$DEST_SLOT")"
    [ "$rdd_now" = "$DEST_OLD_VALUE" ] || die "Destination slot changed after preflight; refusing to replace it."

    info "Detaching $DEST_OLD_VOLID from $DEST_VM/$DEST_SLOT..."
    dryrun_cmd qm set "$DEST_VM" --delete "$DEST_SLOT"
    OLD_DETACHED=1

    if dryrun_enabled; then dryrun_verify "$DEST_OLD_VOLID would be preserved as unusedN"
    else
        rdd_unused="$(old_unused_key)"
        [ -n "$rdd_unused" ] || { rollback_old_disk || :; die "Proxmox did not preserve the displaced disk as unusedN."; }
    fi

    info "Attaching snapshot $NEW_VOLID at $DEST_SLOT..."
    if ! dryrun_cmd qm set "$DEST_VM" "--${DEST_SLOT}" "${NEW_VOLID}${DEST_OPTIONS}"; then
        if ! dryrun_enabled && qm config "$DEST_VM" 2>/dev/null | grep -qF "$NEW_VOLID"; then NEW_ATTACHED=1
        else rollback_old_disk || :; fi
        die "Could not attach snapshot replacement."
    fi
    NEW_ATTACHED=1
}

verify_result() {
    if dryrun_enabled; then
        dryrun_verify "$DEST_SLOT would reference $NEW_VOLID"
        dryrun_verify "$DEST_OLD_VOLID would remain preserved as unusedN"
        dryrun_verify "Snapshot origin would remain $SOURCE_LV"
        dryrun_verify "Destination VM state would match requested $MODE behavior"
        return 0
    fi
    [ "$(disk_volid "$DEST_VM" "$DEST_SLOT")" = "$NEW_VOLID" ] || die "Replacement slot verification failed."
    [ -n "$(old_unused_key)" ] || die "Displaced destination volume is not preserved as unusedN."
    vr_origin="$(lvs --noheadings -o origin "${SOURCE_VG}/${NEW_LV_NAME}" | trim)"
    [ "$vr_origin" = "$SOURCE_LV" ] || die "Snapshot origin verification failed."
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

    if [ "$NEW_ATTACHED" -eq 0 ] && [ "$OLD_DETACHED" -eq 1 ]; then rollback_old_disk || :; fi

    if [ "$MODE" = "pause" ] && [ "$PAUSED_BY_US" -eq 1 ] && [ -n "$DEST_VM" ]; then
        if dryrun_enabled; then dryrun_cmd qm resume "$DEST_VM"; else qm resume "$DEST_VM" >/dev/null 2>&1; fi
        PAUSED_BY_US=0
    elif [ "$MODE" = "restart" ] && [ "$STOPPED_BY_US" -eq 1 ] && [ -n "$DEST_VM" ]; then
        if dryrun_enabled; then dryrun_cmd qm start "$DEST_VM"; else qm start "$DEST_VM" >/dev/null 2>&1; fi
        STOPPED_BY_US=0
    fi

    if ! dryrun_enabled && [ "$CREATED" -eq 1 ] && [ "$NEW_ATTACHED" -eq 0 ] && [ "$COMPLETE" -eq 0 ]; then
        if ! guest_volume_references | grep -F "|$NEW_VOLID" >/dev/null 2>&1; then
            warn "Removing unattached replacement snapshot: $NEW_LV_PATH"
            lvremove -y "${SOURCE_VG}/${NEW_LV_NAME}" >/dev/null 2>&1 || warn "Could not remove $NEW_LV_PATH automatically."
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
