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
    PROJECT_VERSION="3.2.0"; SCRIPT_VERSION="3.0.1"
    MOVE_ACTION="moved"
    parse_arguments "$@"
    check_elevation
}

main() {
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    need_commands lvs vgs lvrename lvremove dmsetup findmnt readlink awk grep sed
    validate_source_and_destination
    assert_not_mounted "$SOURCE_PATH" || die "Unmount the source LV before moving it."
    assert_not_in_use "$SOURCE_PATH"
    print_move_plan
    if [ "$SOURCE_VG" = "$DEST_VG" ]; then rename_in_place
    else move_across_vgs; fi
}

end() {
    if [ "$MOVE_ACTION" = "renamed" ]; then print_banner "LVM volume renamed successfully"
    else print_banner "LVM volume moved successfully"; fi
    printf 'Old path: %s\n' "$SOURCE_PATH"
    printf 'New path: %s\n\n' "$DEST_PATH"
    dryrun_summary
}

############################################################
# COMMAND LINE
############################################################

usage() {
    cat <<EOF
move-lvm.sh $SCRIPT_VERSION (project $PROJECT_VERSION)

USAGE
  move-lvm.sh <source-lv-path> <destination-lv-path> [dryrun]

DESCRIPTION
  Same-VG moves use lvrename in place. Cross-VG moves create and verify an
  independent copy first, then remove the source only after verification.

EXAMPLES
  move-lvm.sh /dev/thinvg/vm-123-disk-1 /dev/thinvg/vm-123-disk-1-old
  move-lvm.sh /dev/thinvg/vm-123-disk-1 /dev/fastvg/vm-123-disk-1

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
# Resolves source/destination LV identities and rejects all destination collisions before mutation.
validate_source_and_destination() {
    case "$SOURCE" in /*) ;; *) die "Source must be a full absolute LVM device path." ;; esac
    case "$DESTINATION" in /dev/*/*) ;; *) die "Destination must use the form /dev/<volume-group>/<lv-name>." ;; esac
    lvs "$SOURCE" >/dev/null 2>&1 || die "Source is not an LVM logical volume: $SOURCE"

    SOURCE_PATH="$(lvs --noheadings -o lv_path "$SOURCE" 2>/dev/null | trim)"
    SOURCE_VG="$(lvs --noheadings -o vg_name "$SOURCE" 2>/dev/null | trim)"
    SOURCE_LV="$(lvs --noheadings -o lv_name "$SOURCE" 2>/dev/null | trim)"
    SOURCE_REAL="$(readlink -f "$SOURCE_PATH")"

    vsd_rel="${DESTINATION#/dev/}"; DEST_VG="${vsd_rel%%/*}"; DEST_LV="${vsd_rel#*/}"
    case "$DEST_VG:$DEST_LV" in :*|*:|*:*/*) die "Destination must use the form /dev/<volume-group>/<lv-name>." ;; esac
    DEST_PATH="/dev/${DEST_VG}/${DEST_LV}"

    [ -n "$SOURCE_PATH" ] && [ -n "$SOURCE_VG" ] && [ -n "$SOURCE_LV" ] || die "Could not resolve the source LV."
    vgs "$DEST_VG" >/dev/null 2>&1 || die "Destination volume group does not exist: $DEST_VG"
    if [ "$SOURCE_VG" = "$DEST_VG" ] && [ "$SOURCE_LV" = "$DEST_LV" ]; then die "Source and destination refer to the same logical volume."; fi
    if lvs "${DEST_VG}/${DEST_LV}" >/dev/null 2>&1; then die "Destination logical volume already exists: $DEST_PATH"; fi
    [ ! -e "$DEST_PATH" ] || die "Destination path already exists: $DEST_PATH"
}

# assert_not_mounted LV
# Refuses direct source mounts and mounted kpartx children.
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
# Refuses a nonzero device-mapper open count.
assert_not_in_use() {
    ani_real="$(readlink -f "$1")"
    ani_open="$(dmsetup info -c --noheadings -o open "$ani_real" 2>/dev/null | tr -d '[:space:]' || :)"
    case "$ani_open" in ''|*[!0-9]*) return 0 ;; esac
    [ "$ani_open" -eq 0 ] || die "Source LV is open/in use (device-mapper open count: $ani_open). Stop any VM/CT or process using it first."
}

# validate_no_dependents
# Refuses cross-VG deletion when source is an origin for dependent LVs.
validate_no_dependents() {
    vnd_dependents="$(lvs --noheadings -o lv_name,origin "$SOURCE_VG" 2>/dev/null | awk -v origin="$SOURCE_LV" '$2 == origin {print $1}')"
    if [ -n "$vnd_dependents" ]; then
        warn "The source LV is an origin for other LVs/snapshots:"
        printf '%s\n' "$vnd_dependents" | sed 's/^/  /' >&2
        die "Refusing a cross-VG move because deleting the source origin could affect dependent snapshots."
    fi
}

############################################################
# HIGH LEVEL TASKS
############################################################

# print_move_plan
# Prints the exact source and destination paths before the move transaction.
print_move_plan() {
    print_banner "Move LVM volume"
    printf 'Source:      %s\n' "$SOURCE_PATH"
    printf 'Destination: %s\n\n' "$DEST_PATH"
}

# rename_in_place
# Performs and verifies a same-VG LV rename without copying data.
rename_in_place() {
    MOVE_ACTION="renamed"
    info "Same volume group detected; renaming the LV in place..."
    dryrun_cmd lvrename "$SOURCE_VG" "$SOURCE_LV" "$DEST_LV"
    if dryrun_enabled; then dryrun_verify "New LV name would exist and old LV name would be absent"
    else
        lvs "${DEST_VG}/${DEST_LV}" >/dev/null 2>&1 || die "lvrename completed, but the destination LV cannot be found."
        if lvs "${SOURCE_VG}/${SOURCE_LV}" >/dev/null 2>&1; then die "Old LV name still exists after rename."; fi
    fi
}

# move_across_vgs
#
# Description:
#   Runs the embedded verified independent-copy implementation, checks both source
#   and destination after that transaction, then removes the source.
#
# Usage:
#   move_across_vgs
#
# Arguments:
#   Uses resolved source/destination state.
#
# Output:
#   Destination survives any source-removal failure.
#
# Returns:
#   0 only after source removal is verified.
############################################################
move_across_vgs() {
    validate_no_dependents
    info "Different volume groups detected; creating and verifying an independent copy first..."
    if dryrun_enabled; then run_embedded_copy_lvm "$SOURCE_PATH" "$DEST_PATH" dryrun
    else run_embedded_copy_lvm "$SOURCE_PATH" "$DEST_PATH"; fi

    if dryrun_enabled; then
        dryrun_verify "Destination copy would exist while source remains present"
    else
        lvs "${DEST_VG}/${DEST_LV}" >/dev/null 2>&1 || die "Destination LV is missing after copy."
        lvs "${SOURCE_VG}/${SOURCE_LV}" >/dev/null 2>&1 || die "Source LV disappeared unexpectedly before removal."
    fi

    info "Verified copy exists. Removing source LV..."
    if ! dryrun_cmd lvremove -y "$SOURCE_PATH"; then
        warn "The destination copy has been preserved at $DEST_PATH."
        die "Could not remove the source LV."
    fi
    if dryrun_enabled; then dryrun_verify "Source LV would be removed after verified copy"
    elif lvs "${SOURCE_VG}/${SOURCE_LV}" >/dev/null 2>&1; then
        warn "The destination copy has been preserved at $DEST_PATH."
        die "Source LV still exists after lvremove."
    fi
}

############################################################
# EMBEDDED COMPANION IMPLEMENTATIONS
############################################################

# run_embedded_copy_lvm
# Executes the bundled copy-lvm.sh implementation without requiring a companion file.
run_embedded_copy_lvm() {
    /bin/sh -s -- "$@" <<'__PROXMOX_LONGTAIL_EMBEDDED_COPY_LVM__'
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
    PROJECT_VERSION="3.2.0"; SCRIPT_VERSION="3.0.1"
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
__PROXMOX_LONGTAIL_EMBEDDED_COPY_LVM__
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
