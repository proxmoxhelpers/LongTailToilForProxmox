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
    PROJECT_VERSION="3.4.2"; SCRIPT_VERSION="1.1.0"
    ALL_LVS_FILE=""; REFS_FILE=""
    parse_arguments "$@"
}

main() {
    need_commands lvs pvesm find awk sed grep sort mktemp cp
    build_lvm_catalog
    collect_guest_lvm_references
    print_verification
    print_remaining_lvs
}

end() { cleanup_files; }

############################################################
# COMMAND LINE
############################################################

usage() {
    cat <<EOF
$(basename "$0") $SCRIPT_VERSION (project $PROJECT_VERSION)

USAGE
  $(basename "$0") [dryrun]

DESCRIPTION
  Lists every LVM volume referenced by Proxmox QEMU/LXC guests and verifies
  managed Proxmox disk numbering.

  Red rows identify managed LVs whose embedded VMID does not match the guest
  that references them, for example VM 199 -> base-100-disk-1.

  Yellow guest headings identify ACTIVE managed LVM disk-number problems:
  numbering that does not start at disk-0, gaps in the sequence, or duplicate
  disk-N values. unusedN entries are listed but do not participate in the
  active numbering sequence.

  Both vm-VMID-disk-N and base-VMID-disk-N are recognized. All LVs not
  referenced by a visible guest are listed at the end.

COLOURS
  green   numbering looks consistent
  yellow  active managed disk numbering does not start at 0
  red     an LV embeds a different VMID than the guest that references it
  cyan    informational / unmanaged LVM reference

EOF
    dryrun_help
}

parse_arguments() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            dryrun|--dryrun) enable_dryrun ;;
            -h|--help) usage; exit 0 ;;
            --version) printf '%s %s (project %s)\n' "$(basename "$0")" "$SCRIPT_VERSION" "$PROJECT_VERSION"; exit 0 ;;
            *) usage >&2; exit 2 ;;
        esac
        shift
    done
}

############################################################
# DISCOVERY
############################################################

# managed_name_fields LV_NAME
# Prints family|embedded-vmid|disk-number for vm-/base- managed names.
managed_name_fields() (
    mnf_name="$1"
    case "$mnf_name" in
        vm-*-disk-*|base-*-disk-*) ;;
        *) exit 1 ;;
    esac
    mnf_family="${mnf_name%%-*}"
    mnf_prefix="${mnf_name%-disk-*}"
    mnf_vmid="${mnf_prefix#*-}"
    mnf_disk="${mnf_name##*-disk-}"
    case "$mnf_vmid" in ''|*[!0-9]*) exit 1 ;; esac
    case "$mnf_disk" in ''|*[!0-9]*) exit 1 ;; esac
    printf '%s|%s|%s\n' "$mnf_family" "$mnf_vmid" "$mnf_disk"
)

build_lvm_catalog() {
    install_temp_cleanup
    ALL_LVS_FILE="$(mktemp)" || die "Unable to create LVM catalog."; register_temp_file "$ALL_LVS_FILE"
    REFS_FILE="$(mktemp)" || die "Unable to create guest-reference catalog."; register_temp_file "$REFS_FILE"

    lvs --noheadings --separator '|' -o lv_uuid,lv_path,vg_name,lv_name,lv_size,pool_lv,origin 2>/dev/null |
        awk -F'|' '{
            for (i=1; i<=7; i++) gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i)
            if ($1 != "" && $2 != "") print $1 "|" $2 "|" $3 "|" $4 "|" $5 "|" $6 "|" $7
        }' | sort -t'|' -k3,3 -k4,4 > "$ALL_LVS_FILE"
}

# collect_guest_lvm_references
# REFS_FILE columns:
# vmid|type|name|slot|volid|uuid|path|lvname|family|embedded-vmid|disk-number
collect_guest_lvm_references() {
    : > "$REFS_FILE"
    all_guest_configs | while IFS= read -r cgr_cfg; do
        [ -n "$cgr_cfg" ] || continue
        cgr_id="${cgr_cfg##*/}"; cgr_id="${cgr_id%.conf}"
        case "$cgr_id" in ''|*[!0-9]*) continue ;; esac

        case "$cgr_cfg" in
            */lxc/*) cgr_type="LXC"; cgr_name="$(awk -F': ' '$1=="hostname" {print $2; exit}' "$cgr_cfg")" ;;
            *) cgr_type="QEMU"; cgr_name="$(awk -F': ' '$1=="name" {print $2; exit}' "$cgr_cfg")" ;;
        esac
        [ -n "$cgr_name" ] || cgr_name="-"

        config_volume_references "$cgr_cfg" | while IFS='|' read -r cgr_slot cgr_volid; do
            [ -n "$cgr_volid" ] || continue
            cgr_path="$(pvesm path "$cgr_volid" 2>/dev/null || :)"
            [ -n "$cgr_path" ] || continue
            lvs "$cgr_path" >/dev/null 2>&1 || continue
            cgr_uuid="$(lvs --noheadings -o lv_uuid "$cgr_path" 2>/dev/null | trim)"
            [ -n "$cgr_uuid" ] || continue
            cgr_row="$(awk -F'|' -v u="$cgr_uuid" '$1==u {print $2 "|" $4; exit}' "$ALL_LVS_FILE")"
            [ -n "$cgr_row" ] || continue
            cgr_catalog_path="${cgr_row%%|*}"
            cgr_lvname="${cgr_row#*|}"
            cgr_family="-"; cgr_embedded="-"; cgr_disk="-"
            if cgr_managed="$(managed_name_fields "$cgr_lvname" 2>/dev/null)"; then
                cgr_family="${cgr_managed%%|*}"
                cgr_rest="${cgr_managed#*|}"
                cgr_embedded="${cgr_rest%%|*}"
                cgr_disk="${cgr_rest#*|}"
            fi
            printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
                "$cgr_id" "$cgr_type" "$cgr_name" "$cgr_slot" "$cgr_volid" "$cgr_uuid" \
                "$cgr_catalog_path" "$cgr_lvname" "$cgr_family" "$cgr_embedded" "$cgr_disk"
        done
    done | sort -t'|' -k1,1n -k4,4 -u > "$REFS_FILE"
    return 0
}

############################################################
# RESULTS
############################################################

active_numbering_status() (
    ans_id="$1"
    awk -F'|' -v id="$ans_id" '
        $1==id && $4 !~ /^unused[0-9]+$/ && $11 ~ /^[0-9]+$/ {print $11}
    ' "$REFS_FILE" | sort -n |
        awk '
            function add_note(s) {
                if (note == "") note=s
                else note=note "; " s
            }
            BEGIN { have=0; expected=0; prev=-1; lastdup=-1 }
            {
                n=$1+0
                if (!have) {
                    have=1
                    if (n != 0) add_note("ACTIVE STARTS AT disk-" n)
                    expected=n+1
                    prev=n
                    next
                }
                if (n == prev) {
                    if (lastdup != n) {
                        add_note("DUPLICATE disk-" n)
                        lastdup=n
                    }
                    next
                }
                if (n > expected) add_note("GAP AT disk-" expected)
                expected=n+1
                prev=n
            }
            END {
                if (!have) print "NO ACTIVE MANAGED DISK-N"
                else if (note == "") print "OK"
                else print note
            }
        '
)

# guest_numbering_state VMID
# Prints mismatch-count|active-min-disk|active-managed-count.
guest_numbering_state() {
    gns_id="$1"
    awk -F'|' -v id="$gns_id" '
        $1==id {
            if ($10 != "-" && $10 != id) mismatch++
            if ($4 !~ /^unused[0-9]+$/ && $11 ~ /^[0-9]+$/) {
                if (!have || ($11+0) < min) min=$11+0
                have=1
                active++
            }
        }
        END {
            if (!have) min="-"
            printf "%d|%s|%d\n", mismatch+0, min, active+0
        }
    ' "$REFS_FILE"
}

print_verification() {
    section "VM / CT LVM disk-number verification"
    if [ ! -s "$REFS_FILE" ]; then printf '%s\n' "(none)"; return 0; fi

    awk -F'|' '{print $1}' "$REFS_FILE" | sort -un | while IFS= read -r pv_id; do
        [ -n "$pv_id" ] || continue
        pv_first="$(awk -F'|' -v id="$pv_id" '$1==id {print $2 "|" $3; exit}' "$REFS_FILE")"
        pv_type="${pv_first%%|*}"; pv_name="${pv_first#*|}"
        pv_state="$(guest_numbering_state "$pv_id")"
        pv_mismatch="${pv_state%%|*}"; pv_rest="${pv_state#*|}"; pv_min="${pv_rest%%|*}"; pv_active="${pv_rest#*|}"
        pv_sequence="$(active_numbering_status "$pv_id")"

        pv_head_color="$C_GREEN"; pv_notes="OK"
        if [ "$pv_mismatch" -gt 0 ]; then
            pv_head_color="$C_RED"; pv_notes="VMID MISMATCH"
            case "$pv_sequence" in OK|"NO ACTIVE MANAGED DISK-N") ;; *) pv_notes="$pv_notes; $pv_sequence" ;; esac
        elif [ "$pv_sequence" = "NO ACTIVE MANAGED DISK-N" ]; then
            pv_head_color="$C_CYAN"; pv_notes="$pv_sequence"
        elif [ "$pv_sequence" != "OK" ]; then
            pv_head_color="$C_YELLOW"; pv_notes="$pv_sequence"
        fi

        printf '\n%s%sVM %s%s  %s(%s) %s%s  [%s%s%s]\n' \
            "$C_BOLD" "$pv_head_color" "$pv_id" "$C_RESET" "$C_CYAN" "$pv_type" "$pv_name" "$C_RESET" \
            "$pv_head_color" "$pv_notes" "$C_RESET"
        printf '  %-10s %-40s %-7s %-9s %-8s %s\n' SLOT LVM_PATH FAMILY LV_VMID DISK STATUS

        awk -F'|' -v id="$pv_id" '$1==id' "$REFS_FILE" | while IFS='|' read -r \
            pr_id pr_type pr_name pr_slot pr_volid pr_uuid pr_path pr_lvname pr_family pr_embedded pr_disk; do

            pr_color="$C_CYAN"; pr_status="UNMANAGED"
            if [ "$pr_embedded" != "-" ]; then
                if [ "$pr_embedded" != "$pv_id" ]; then
                    pr_color="$C_RED"; pr_status="VMID != $pv_id"
                elif [ "$pr_slot" != "${pr_slot#unused}" ]; then
                    pr_color="$C_CYAN"; pr_status="UNUSED"
                elif [ "$pv_sequence" != "OK" ]; then
                    pr_color="$C_YELLOW"; pr_status="NUMBERING"
                else
                    pr_color="$C_GREEN"; pr_status="OK"
                fi
            fi
            printf '  %-10s %s%-40s%s %-7s %-9s %-8s %s%s%s\n' \
                "$pr_slot" "$pr_color" "$pr_path" "$C_RESET" "$pr_family" "$pr_embedded" "$pr_disk" \
                "$pr_color" "$pr_status" "$C_RESET"
        done
    done
    return 0
}

print_remaining_lvs() {
    section "Remaining LVM volumes"
    printf '%-40s %-12s %-16s %-16s %s\n' LVM_PATH SIZE POOL ORIGIN STATUS
    prl_count=0
    while IFS='|' read -r prl_uuid prl_path prl_vg prl_lv prl_size prl_pool prl_origin; do
        if awk -F'|' -v u="$prl_uuid" '$6==u {found=1; exit} END {exit(found ? 0 : 1)}' "$REFS_FILE"; then continue; fi
        [ -n "$prl_pool" ] || prl_pool="-"; [ -n "$prl_origin" ] || prl_origin="-"
        prl_color="$C_CYAN"; prl_status="UNREFERENCED"
        if managed_name_fields "$prl_lv" >/dev/null 2>&1; then prl_color="$C_YELLOW"; prl_status="UNREFERENCED MANAGED"; fi
        printf '%s%-40s%s %-12s %-16s %-16s %s%s%s\n' \
            "$prl_color" "$prl_path" "$C_RESET" "$prl_size" "$prl_pool" "$prl_origin" "$prl_color" "$prl_status" "$C_RESET"
        prl_count=$((prl_count + 1))
    done < "$ALL_LVS_FILE"
    [ "$prl_count" -gt 0 ] || printf '%s\n' "(none)"
    return 0
}

############################################################
# GENERAL HELPERS
############################################################

cleanup_files() {
    [ -z "$ALL_LVS_FILE" ] || rm -f "$ALL_LVS_FILE"
    [ -z "$REFS_FILE" ] || rm -f "$REFS_FILE"
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
