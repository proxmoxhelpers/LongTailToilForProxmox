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
    PROJECT_VERSION="3.4.4"; SCRIPT_VERSION="3.4.1"
    PLAN_FILE=""; RENAMED_FILE=""; COMPLETED=0
    CONFIG_CONTENT_CHANGED=0; CONFIG_MOVED=0; FIREWALL_MOVED=0
    parse_arguments "$@"
    check_elevation
}

main() {
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    install_temp_cleanup
    need_commands qm pct pvesm lvs lvrename find grep sort uniq readlink mktemp sed cp mv awk cut
    validate_environment
    locate_guest
    print_header
    preflight_destination
    preflight_guest_state
    build_volume_plan
    preflight_firewall
    print_preflight_complete
    stop_guest
    create_backup
    install_rollback
    rename_volumes
    rewrite_guest_config
    rename_guest_config
    rename_firewall
    verify_result
    COMPLETED=1
    trap - 0 HUP INT TERM
}

end() {
    print_banner "VMID changed successfully"
    printf 'Type:              %s\n' "$TYPE_NAME"
    printf 'Old VMID:          %s\n' "$OLD_ID"
    printf 'New VMID:          %s\n' "$NEW_ID"
    printf 'New configuration: %s\n' "$NEW_CONFIG"
    printf 'Status:            %s\n' "$NEW_STATUS"
    printf 'Backup:            %s\n\n' "$BACKUP_DIR"
    printf 'The guest has intentionally been left STOPPED.\n\n'
    printf 'IMPORTANT: review and update anything outside the guest config\n'
    printf 'that explicitly references the old VMID %s, including:\n\n' "$OLD_ID"
    printf '  - Backup jobs\n  - ACLs / permissions\n  - HA configuration\n  - Replication jobs\n  - Pools\n'
    printf '  - Hooks, scripts, monitoring, or other cluster automation\n\n'
    printf 'These objects are NOT rewritten automatically by this script.\n\n'
    dryrun_summary
    cleanup_plan_files
}

############################################################
# COMMAND LINE
############################################################

usage() {
    cat <<EOF
change-vmid-of-vm.sh $SCRIPT_VERSION (project $PROJECT_VERSION)

USAGE
  change-vmid-of-vm.sh <old-vmid> <new-vmid> [dryrun]

DESCRIPTION
  Changes the VMID of a local QEMU VM or LXC container when all referenced
  vm-OLDID-* / base-OLDID-* storage volumes are LVM/LVM-thin and can be renamed in place.

  Preflight checks destination VMID availability, locks, snapshots, volume
  ownership and name collisions before mutation. The guest is left stopped.

EXAMPLE
  change-vmid-of-vm.sh 123 456

NOTES
  HA, replication, ACLs, backup jobs, pools, hooks and external automation are
  not rewritten automatically and must be reviewed after a successful change.

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
            *) pa_count=$((pa_count + 1)); case "$pa_count" in 1) OLD_ID="$1" ;; 2) NEW_ID="$1" ;; *) usage >&2; exit 2 ;; esac ;;
        esac
        shift
    done
    [ "$pa_count" -eq 2 ] || { usage >&2; exit 2; }
}

############################################################
# VALIDATION / PRE-FLIGHT
############################################################

# validate_environment
# Validates VMID syntax and the basic Proxmox configuration environment before guest discovery.
validate_environment() {
    case "$OLD_ID" in ''|*[!0-9]*) die "Old VMID must be numeric." ;; esac
    case "$NEW_ID" in ''|*[!0-9]*) die "New VMID must be numeric." ;; esac
    [ "$OLD_ID" != "$NEW_ID" ] || die "Old VMID and new VMID are identical."
    [ "$OLD_ID" -gt 0 ] || die "Invalid source VMID."
    [ "$NEW_ID" -gt 0 ] || die "Invalid destination VMID."
    [ -d /etc/pve ] || die "/etc/pve does not exist. This does not appear to be a Proxmox host."
}

# locate_guest
# Resolves the source ID to exactly one local QEMU VM or LXC configuration.
locate_guest() {
    QEMU_CONFIG="/etc/pve/qemu-server/${OLD_ID}.conf"; LXC_CONFIG="/etc/pve/lxc/${OLD_ID}.conf"
    if [ -f "$QEMU_CONFIG" ] && [ -f "$LXC_CONFIG" ]; then
        die "Both a VM and CT exist with VMID $OLD_ID. This should not happen."
    elif [ -f "$QEMU_CONFIG" ]; then
        TYPE="qemu"; TYPE_NAME="QEMU VM"; CONFIG="$QEMU_CONFIG"; CONFIG_DIR="/etc/pve/qemu-server"; GUEST_CMD="qm"
    elif [ -f "$LXC_CONFIG" ]; then
        TYPE="lxc"; TYPE_NAME="LXC container"; CONFIG="$LXC_CONFIG"; CONFIG_DIR="/etc/pve/lxc"; GUEST_CMD="pct"
    else
        printf 'No local VM or CT with VMID %s was found.\n\n' "$OLD_ID" >&2
        printf 'If the guest exists on another cluster node, run this script on the node that owns its configuration.\n' >&2
        exit 1
    fi
    NEW_CONFIG="${CONFIG_DIR}/${NEW_ID}.conf"
}

# print_header
# Prints the resolved VMID-change operation before preflight begins.
print_header() {
    print_banner "Change Proxmox VMID"
    printf 'Type:          %s\n' "$TYPE_NAME"
    printf 'Current VMID:  %s\n' "$OLD_ID"
    printf 'New VMID:      %s\n' "$NEW_ID"
    printf 'Configuration: %s\n\nRunning pre-flight checks...\n\n' "$CONFIG"
}

# preflight_destination
# Proves the destination VMID and destination config path are unused cluster-wide.
preflight_destination() {
    pd_configs="$(find /etc/pve/nodes \( -path "*/qemu-server/${NEW_ID}.conf" -o -path "*/lxc/${NEW_ID}.conf" \) -type f -print 2>/dev/null)"
    if [ -n "$pd_configs" ]; then
        printf 'Destination VMID %s is already in use:\n%s\n' "$NEW_ID" "$pd_configs" >&2
        die "Destination VMID is not available."
    fi
    [ ! -e "$NEW_CONFIG" ] || die "Destination configuration already exists: $NEW_CONFIG"
    ok "Destination VMID $NEW_ID is available."
}

# preflight_guest_state
# Rejects locks/snapshot sections and reports HA/replication references that require later manual review.
preflight_guest_state() {
    if grep -qE '^[[:space:]]*lock:[[:space:]]*' "$CONFIG"; then
        printf '\nGuest configuration contains a lock:\n' >&2
        grep -E '^[[:space:]]*lock:[[:space:]]*' "$CONFIG" >&2
        die "Remove/resolve the Proxmox lock before changing the VMID."
    fi
    ok "Guest is not locked."

    pgs_snapshots="$(grep -E '^\[[^]]+\]$' "$CONFIG" 2>/dev/null | grep -v '^\[PENDING\]$' || :)"
    if [ -n "$pgs_snapshots" ]; then
        printf '\nSnapshot/config sections found:\n%s\n' "$(printf '%s\n' "$pgs_snapshots" | sed 's/^/  /')" >&2
        die "Remove guest snapshots before changing the VMID."
    fi
    ok "No snapshot sections detected."

    if [ -f /etc/pve/ha/resources.cfg ] && grep -qE "^[[:space:]]*(vm|ct):${OLD_ID}([[:space:]]|$)" /etc/pve/ha/resources.cfg; then warn "VMID $OLD_ID appears to be referenced by Proxmox HA."; fi
    if [ -f /etc/pve/replication.cfg ] && grep -qE "(^|[^0-9])${OLD_ID}([:-]|[[:space:]])" /etc/pve/replication.cfg; then warn "VMID $OLD_ID may be referenced by replication configuration."; fi
}

# build_volume_plan
#
# Description:
#   Resolves every vm-OLDID-* and base-OLDID-* reference to LVM metadata,
#   validates destination collisions/shared references, preserves the volume
#   family, and records the complete rename plan
#   before any mutation.
#
# Usage:
#   build_volume_plan
#
# Arguments:
#   Uses OLD_ID, NEW_ID and CONFIG.
#
# Output:
#   PLAN_FILE columns:
#     old-volid|old-path|vg|old-lv|new-lv|new-volid
#
# Returns:
#   0 after complete preflight.
############################################################
build_volume_plan() {
    PLAN_FILE="$(mktemp)" || die "Unable to create VMID volume plan."
    register_temp_file "$PLAN_FILE"
    bvp_volids="$(mktemp)" || die "Unable to create volume-reference list."
    register_temp_file "$bvp_volids"
    grep -oE "[A-Za-z0-9_.-]+:(vm|base)-${OLD_ID}-[A-Za-z0-9_.+-]+" "$CONFIG" | sort -u > "$bvp_volids" || :
    bvp_foreign="$(grep -oE "[A-Za-z0-9_.-]+:(vm|base)-[0-9]+-[A-Za-z0-9_.+-]+" "$CONFIG" | grep -vE ":(vm|base)-${OLD_ID}-" | sort -u || :)"

    printf '\nReferenced volumes:\n\n'
    if [ -s "$bvp_volids" ]; then sed 's/^/  /' "$bvp_volids"; else printf '  No vm-%s-* or base-%s-* storage volumes found.\n' "$OLD_ID" "$OLD_ID"; fi
    printf '\n'
    if [ -n "$bvp_foreign" ]; then
        warn "Configured vm/base volume names with a different embedded VMID will be left unchanged:"
        printf '%s\n' "$bvp_foreign" | sed 's/^/       /'
        warn "Use fix-vm-volume-names.sh separately if you want those backing names normalized to the guest VMID."
        printf '\n'
    fi

    while IFS= read -r bvp_old_volid; do
        [ -n "$bvp_old_volid" ] || continue
        bvp_storage="${bvp_old_volid%%:*}"; bvp_old_volume="${bvp_old_volid#*:}"
        case "$bvp_old_volume" in
            vm-"${OLD_ID}"-*) bvp_family="vm"; bvp_suffix="${bvp_old_volume#vm-${OLD_ID}-}" ;;
            base-"${OLD_ID}"-*) bvp_family="base"; bvp_suffix="${bvp_old_volume#base-${OLD_ID}-}" ;;
            *) rm -f "$bvp_volids"; die "Unexpected managed-volume name: $bvp_old_volume" ;;
        esac
        bvp_new_volume="${bvp_family}-${NEW_ID}-${bvp_suffix}"; bvp_new_volid="${bvp_storage}:${bvp_new_volume}"
        bvp_old_path="$(pvesm path "$bvp_old_volid" 2>/dev/null || :)"; [ -n "$bvp_old_path" ] || { rm -f "$bvp_volids"; die "Could not resolve Proxmox volume: $bvp_old_volid"; }

        bvp_lvm="$(lvs --noheadings --separator '|' -o vg_name,lv_name "$bvp_old_path" 2>/dev/null | head -n1 || :)"
        if [ -z "$bvp_lvm" ]; then
            printf 'Unsupported volume:\n  Proxmox ID: %s\n  Path:       %s\n' "$bvp_old_volid" "$bvp_old_path" >&2
            rm -f "$bvp_volids"; die "The volume is not LVM/LVM-thin. No changes have been made."
        fi
        bvp_vg="$(printf '%s' "$bvp_lvm" | cut -d'|' -f1 | trim)"
        bvp_actual="$(printf '%s' "$bvp_lvm" | cut -d'|' -f2 | trim)"
        [ -n "$bvp_vg" ] && [ -n "$bvp_actual" ] || { rm -f "$bvp_volids"; die "Could not determine LVM metadata for $bvp_old_volid"; }
        if [ "$bvp_actual" != "$bvp_old_volume" ]; then
            rm -f "$bvp_volids"
            die "Volume naming mismatch for $bvp_old_volid: actual LV is $bvp_actual; refusing to guess."
        fi
        lvs "${bvp_vg}/${bvp_new_volume}" >/dev/null 2>&1 && { rm -f "$bvp_volids"; die "Destination volume already exists: /dev/${bvp_vg}/${bvp_new_volume}"; }

        bvp_refs="$(other_volume_references "$bvp_old_volid" "$CONFIG")"
        [ -z "$bvp_refs" ] || { printf '%s\n' "$bvp_refs" >&2; rm -f "$bvp_volids"; die "Refusing to rename a shared volume: $bvp_old_volid"; }

        printf '%s|%s|%s|%s|%s|%s\n' "$bvp_old_volid" "$bvp_old_path" "$bvp_vg" "$bvp_actual" "$bvp_new_volume" "$bvp_new_volid" >> "$PLAN_FILE"
        ok "$bvp_old_volid"
        printf '     -> %s\n' "$bvp_new_volid"
    done < "$bvp_volids"
    rm -f "$bvp_volids"

    bvp_duplicates="$(cut -d'|' -f6 "$PLAN_FILE" | sort | uniq -d || :)"
    [ -z "$bvp_duplicates" ] || { printf '%s\n' "$bvp_duplicates" >&2; die "Multiple source volumes map to the same destination."; }
}

# preflight_firewall
# Checks the optional firewall-config rename for a destination collision.
preflight_firewall() {
    OLD_FIREWALL="/etc/pve/firewall/${OLD_ID}.fw"; NEW_FIREWALL="/etc/pve/firewall/${NEW_ID}.fw"
    if [ -e "$OLD_FIREWALL" ] && [ -e "$NEW_FIREWALL" ]; then die "Destination firewall file already exists: $NEW_FIREWALL"; fi
    if [ -e "$OLD_FIREWALL" ]; then
        printf '\n'; ok "Firewall configuration will also be renamed: $OLD_FIREWALL"; printf '     -> %s\n' "$NEW_FIREWALL"
    fi
}

# print_preflight_complete
# Marks the boundary after all non-mutating checks and before guest shutdown/mutation.
print_preflight_complete() {
    print_banner "All pre-flight checks passed"
    printf 'Nothing has been renamed yet.\n\n'
}

############################################################
# GUEST STATE / BACKUP
############################################################

get_status() { "$GUEST_CMD" status "$OLD_ID" 2>/dev/null | awk '{print $2}'; }

# stop_guest
# Stops the source guest gracefully when possible and verifies stopped state before mutation.
stop_guest() {
    STATUS="$(get_status || :)"
    printf 'Current guest status: %s\n\n' "${STATUS:-unknown}"
    if [ "$STATUS" != "stopped" ]; then
        printf 'Guest is running.\nRequesting graceful shutdown...\n\n'
        dryrun_cmd "$GUEST_CMD" shutdown "$OLD_ID" --timeout 60 || :
        if dryrun_enabled; then STATUS="stopped"; dryrun_verify "Guest $OLD_ID would be stopped before VMID changes"
        else STATUS="$(get_status || :)"; fi
        if [ "$STATUS" != "stopped" ]; then
            printf '\nGuest did not stop gracefully.\nForcing stop...\n\n'
            dryrun_cmd "$GUEST_CMD" stop "$OLD_ID"
        fi
    fi
    if dryrun_enabled; then STATUS="stopped"; else STATUS="$(get_status || :)"; fi
    [ "$STATUS" = "stopped" ] || die "Guest is still not stopped."
    ok "Guest is stopped."; printf '\n'
}

# create_backup
# Creates timestamped guest/firewall backups outside /etc/pve before the transaction.
create_backup() {
    TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
    BACKUP_DIR="/root/change-vmid-backup-${OLD_ID}-to-${NEW_ID}-${TIMESTAMP}"
    dryrun_cmd mkdir -p "$BACKUP_DIR"
    dryrun_cmd cp "$CONFIG" "$BACKUP_DIR/${OLD_ID}.conf"
    if [ -e "$OLD_FIREWALL" ]; then dryrun_cmd cp "$OLD_FIREWALL" "$BACKUP_DIR/${OLD_ID}.fw"; fi
    printf 'Configuration backup: %s\n\n' "$BACKUP_DIR"
}

############################################################
# TRANSACTION / ROLLBACK
############################################################

# install_rollback
# Creates the append-only LV rename journal and installs POSIX exit/signal rollback traps.
install_rollback() {
    RENAMED_FILE="$(mktemp)" || die "Unable to create rollback journal."
    register_temp_file "$RENAMED_FILE"
    trap rollback_on_exit 0
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
}

# rollback_on_exit
#
# Description:
#   Restores config/firewall paths and reverses only LV renames recorded as
#   successfully completed in RENAMED_FILE. This is the POSIX replacement for
#   the v2 Bash ERR trap and array rollback.
#
# Usage:
#   Installed as the process exit trap during mutation.
#
# Arguments:
#   None.
#
# Output:
#   Attempts rollback when COMPLETED is still 0.
#
# Returns:
#   Re-exits with the original failure status.
############################################################
rollback_on_exit() {
    roe_status=$?
    trap - 0 HUP INT TERM
    [ "$COMPLETED" -eq 0 ] || { [ "$roe_status" -eq 0 ] || exit "$roe_status"; return 0; }
    if dryrun_enabled; then
        warn "Dry-run encountered an error; no rollback actions are necessary because no mutation was executed."
        cleanup_plan_files
        [ "$roe_status" -eq 0 ] || exit "$roe_status"
        return 0
    fi

    printf '\n'; print_banner "An error occurred - attempting rollback"
    set +e
    if [ "$CONFIG_MOVED" -eq 1 ] && [ -e "$NEW_CONFIG" ]; then mv "$NEW_CONFIG" "$CONFIG"; CONFIG_MOVED=0; fi
    if [ "$CONFIG_CONTENT_CHANGED" -eq 1 ] && [ -e "$CONFIG" ]; then cat "$BACKUP_DIR/${OLD_ID}.conf" > "$CONFIG"; fi
    if [ "$FIREWALL_MOVED" -eq 1 ] && [ -e "$NEW_FIREWALL" ]; then mv "$NEW_FIREWALL" "$OLD_FIREWALL"; fi

    if [ -n "$RENAMED_FILE" ] && [ -s "$RENAMED_FILE" ]; then
        roe_reverse="$(awk -F'|' '{line[NR]=$0} END {for(i=NR;i>=1;i--) print line[i]}' "$RENAMED_FILE")"
        printf '%s\n' "$roe_reverse" | while IFS='|' read -r roe_vg roe_old roe_new; do
            [ -n "$roe_vg" ] || continue
            printf 'Restoring LV: %s/%s\n  -> %s/%s\n' "$roe_vg" "$roe_new" "$roe_vg" "$roe_old"
            lvrename "$roe_vg" "$roe_new" "$roe_old" || warn "Rollback could not restore $roe_vg/$roe_old"
        done
    fi
    set -e
    printf '\nRollback attempted.\nBackup remains at: %s\n\n' "$BACKUP_DIR"
    cleanup_plan_files
    [ "$roe_status" -eq 0 ] || exit "$roe_status"
}

# rename_volumes
# Renames each planned LVM volume and journals every completed rename for rollback.
rename_volumes() {
    [ -s "$PLAN_FILE" ] || return 0
    print_banner "Renaming LVM volumes"
    while IFS='|' read -r rv_old_volid rv_old_path rv_vg rv_old rv_new rv_new_volid; do
        printf '%s/%s\n  -> %s/%s\n' "$rv_vg" "$rv_old" "$rv_vg" "$rv_new"
        dryrun_cmd lvrename "$rv_vg" "$rv_old" "$rv_new"
        printf '%s|%s|%s\n' "$rv_vg" "$rv_old" "$rv_new" >> "$RENAMED_FILE"
        printf '\n'
    done < "$PLAN_FILE"
}

# rewrite_guest_config
# Rewrites vm-OLDID- and base-OLDID- references in the source guest configuration.
rewrite_guest_config() {
    print_banner "Updating guest configuration"
    if dryrun_enabled; then
        dryrun_print_shell "mktemp  # temporary rewritten guest config"
        dryrun_print_shell "sed -e s/vm-${OLD_ID}-/vm-${NEW_ID}-/g -e s/base-${OLD_ID}-/base-${NEW_ID}-/g $(shell_quote "$CONFIG") > <temporary-config>"
        dryrun_print_shell "cat <temporary-config> > $(shell_quote "$CONFIG")"
        dryrun_print_shell "rm -f <temporary-config>"
    else
        rgc_tmp="$(mktemp)" || die "Unable to create temporary guest config."
        sed -e "s/vm-${OLD_ID}-/vm-${NEW_ID}-/g" -e "s/base-${OLD_ID}-/base-${NEW_ID}-/g" "$CONFIG" > "$rgc_tmp"
        cat "$rgc_tmp" > "$CONFIG"
        rm -f "$rgc_tmp"
    fi
    CONFIG_CONTENT_CHANGED=1
    ok "Volume references updated."
}

# rename_guest_config
# Renames the guest configuration file from OLD_ID.conf to NEW_ID.conf.
rename_guest_config() {
    printf '\nRenaming configuration: %s\n  -> %s\n\n' "$CONFIG" "$NEW_CONFIG"
    dryrun_cmd mv "$CONFIG" "$NEW_CONFIG"
    CONFIG_MOVED=1
    ok "Guest configuration renamed."
}

# rename_firewall
# Renames the optional per-VM firewall configuration when one exists.
rename_firewall() {
    [ -e "$OLD_FIREWALL" ] || return 0
    printf '\nRenaming firewall configuration: %s\n  -> %s\n' "$OLD_FIREWALL" "$NEW_FIREWALL"
    dryrun_cmd mv "$OLD_FIREWALL" "$NEW_FIREWALL"
    FIREWALL_MOVED=1
    ok "Firewall configuration renamed."
}

############################################################
# VERIFICATION
############################################################

# verify_result
#
# Description:
#   Verifies configuration identity, stopped state, rewritten references,
#   every LV rename and Proxmox volume resolution. Verification failures after
#   the completed identity transition are preserved for manual inspection.
#
# Usage:
#   verify_result
#
# Arguments:
#   Uses transaction state and PLAN_FILE.
#
# Output:
#   Sets NEW_STATUS.
#
# Returns:
#   0 on complete health verification; exits nonzero without rollback when the
#   transition completed but a health check fails.
############################################################
verify_result() {
    print_banner "Verifying result"
    vr_failed=0
    if dryrun_enabled; then
        NEW_STATUS="stopped"
        dryrun_verify "Old configuration $CONFIG would no longer exist"
        dryrun_verify "New configuration $NEW_CONFIG would exist"
        dryrun_verify "Proxmox would read VMID $NEW_ID"
        dryrun_verify "VMID $NEW_ID would remain stopped"
        dryrun_verify "No vm-${OLD_ID}- or base-${OLD_ID}- volume references would remain in the new configuration"
        while IFS='|' read -r vr_old_volid vr_old_path vr_vg vr_old vr_new vr_new_volid; do
            [ -n "$vr_old_volid" ] || continue
            dryrun_verify "LV ${vr_vg}/${vr_new} would exist and ${vr_vg}/${vr_old} would be absent"
            dryrun_verify "Proxmox would resolve $vr_new_volid"
        done < "$PLAN_FILE"
        [ "$FIREWALL_MOVED" -eq 0 ] || dryrun_verify "Firewall configuration would be renamed to $NEW_FIREWALL"
        return 0
    fi

    if [ -e "$CONFIG" ]; then warn "Old configuration still exists: $CONFIG"; vr_failed=1; else ok "Old configuration no longer exists."; fi
    if [ ! -f "$NEW_CONFIG" ]; then warn "New configuration does not exist: $NEW_CONFIG"; vr_failed=1; else ok "New configuration exists."; fi
    if "$GUEST_CMD" config "$NEW_ID" >/dev/null 2>&1; then ok "Proxmox can read VMID $NEW_ID."; else warn "Proxmox cannot read VMID $NEW_ID."; vr_failed=1; fi

    NEW_STATUS="$("$GUEST_CMD" status "$NEW_ID" 2>/dev/null | awk '{print $2}' || :)"
    if [ "$NEW_STATUS" = "stopped" ]; then ok "New VMID is stopped."; else warn "Unexpected new VMID status: ${NEW_STATUS:-unknown}"; vr_failed=1; fi

    if grep -qE "(vm|base)-${OLD_ID}-" "$NEW_CONFIG"; then
        warn "Old vm-${OLD_ID}- or base-${OLD_ID}- volume references remain:"
        grep -E "(vm|base)-${OLD_ID}-" "$NEW_CONFIG" | sed 's/^/       /' >&2
        vr_failed=1
    else
        ok "No old managed-volume names remain in configuration."
    fi

    while IFS='|' read -r vr_old_volid vr_old_path vr_vg vr_old vr_new vr_new_volid; do
        [ -n "$vr_old_volid" ] || continue
        if lvs "${vr_vg}/${vr_new}" >/dev/null 2>&1; then ok "LV exists: ${vr_vg}/${vr_new}"; else warn "New LV missing: ${vr_vg}/${vr_new}"; vr_failed=1; fi
        if lvs "${vr_vg}/${vr_old}" >/dev/null 2>&1; then warn "Old LV still exists: ${vr_vg}/${vr_old}"; vr_failed=1; fi
        if vr_path="$(pvesm path "$vr_new_volid" 2>/dev/null)"; then ok "Proxmox resolves $vr_new_volid"; printf '     -> %s\n' "$vr_path"
        else warn "Proxmox cannot resolve: $vr_new_volid"; vr_failed=1; fi
    done < "$PLAN_FILE"

    if [ "$FIREWALL_MOVED" -eq 1 ]; then
        if [ -f "$NEW_FIREWALL" ] && [ ! -e "$OLD_FIREWALL" ]; then ok "Firewall configuration renamed."
        else warn "Firewall configuration rename is inconsistent."; vr_failed=1; fi
    fi

    if [ "$vr_failed" -ne 0 ]; then
        COMPLETED=1
        trap - 0 HUP INT TERM
        print_banner "VERIFICATION FAILED"
        printf 'The VMID change completed, but one or more health checks failed.\n\nBackup: %s\n\nInspect the guest before starting it.\n' "$BACKUP_DIR" >&2
        cleanup_plan_files
        exit 1
    fi
}

############################################################
# GENERAL HELPERS
############################################################

# cleanup_plan_files
# Removes only temporary planning/journal files created by the current process.
cleanup_plan_files() {
    [ -z "$PLAN_FILE" ] || rm -f "$PLAN_FILE"
    [ -z "$RENAMED_FILE" ] || rm -f "$RENAMED_FILE"
    PLAN_FILE=""; RENAMED_FILE=""
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
