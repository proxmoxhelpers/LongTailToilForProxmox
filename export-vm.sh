#!/bin/sh
set -eu

############################################################
# export-vm.sh
# Creates a single self-contained, integrity-verifiable Proxmox guest archive.
############################################################

# setup ARGS...
# Call: setup "$@"
# Initializes user-adjustable defaults and parses arguments.
setup() {
    PROJECT_VERSION="3.7.1"; SCRIPT_VERSION="3.7.1"
    DRYRUN=0; PREFLIGHT=0; QUIET=0; OUTPUT_FORMAT=text; YES=0
    :
    preparse_common_options "$@"
    define_colours
    parse_arguments "$@"
    check_elevation
}

# main ARGS...
# Call: main "$@"
# Performs preflight and the requested operation.
main() {
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    need_commands vzdump tar sha256sum awk sed grep sort find mktemp cp mv ln rm hostname date pvesm blockdev lvs lvchange
    EVM_KIND="$(guest_kind "$VMID")" || refuse "Guest $VMID does not exist."
    EVM_CFG="$(guest_config_path "$VMID")"
    evm_assert_self_contained "$EVM_CFG" "$EVM_KIND"
    evm_validate_storage_resolution "$EVM_CFG" "$EVM_KIND"
    [ ! -e "$OUT" ] || [ "$FORCE" -eq 1 ] || refuse "Output already exists; use --force: $OUT"
    if [ -e "$OUT" ] && [ ! -f "$OUT" ]; then refuse "Output exists but is not a regular file: $OUT"; fi
    case "$OUT" in
      */*) EVM_OUT_DIR="${OUT%/*}"; [ -n "$EVM_OUT_DIR" ] || EVM_OUT_DIR="/" ;;
      *) EVM_OUT_DIR="." ;;
    esac
    [ -d "$EVM_OUT_DIR" ] && [ -w "$EVM_OUT_DIR" ] || refuse "Output directory does not exist or is not writable: $EVM_OUT_DIR"
    EVM_STATUS="$(guest_status "$VMID" "$EVM_KIND")"; EVM_ORIGINAL_STATUS="$EVM_STATUS"; EVM_STOPPED_BY_US=0
    if [ "$EVM_STATUS" != stopped ] && [ "$STOP_FOR_EXPORT" -eq 0 ]; then refuse "Guest must be stopped for an exact archive; pass --stop for a graceful temporary stop."; fi

    info "Exact guest archive: $EVM_KIND $VMID -> $OUT"
    info "Content hashing: $( [ "$CONTENT_HASH" -eq 1 ] && printf full || printf skipped )"
    if [ "$PREFLIGHT" -eq 1 ]; then
        evm_validate_storage_resolution "$EVM_CFG" "$EVM_KIND"
        return 0
    fi
    if [ "$DRYRUN" -eq 1 ]; then
        if [ "$EVM_STATUS" != stopped ]; then
          if [ "$EVM_KIND" = qemu ]; then print_command qm shutdown "$VMID" --timeout 60; else print_command pct shutdown "$VMID" --timeout 60; fi
        fi
        printf '[DRYRUN] capture exact config, firewall, storage map%s and guest-scoped external metadata\n' "$( [ "$CONTENT_HASH" -eq 1 ] && printf ' with full virtual-disk SHA-256' || printf '' )"
        print_command vzdump "$VMID" --dumpdir '<temporary>/ltvm/payload' --mode stop --compress zstd --remove 0
        printf '[DRYRUN] write manifest/checksums/self-contained restore.sh and tar -> %s\n' "$OUT"
        if [ "$EVM_STATUS" != stopped ] && [ "$LEAVE_STOPPED" -eq 0 ]; then
          if [ "$EVM_KIND" = qemu ]; then print_command qm start "$VMID"; else print_command pct start "$VMID"; fi
        fi
        return 0
    fi

    EVM_STAGE=""; EVM_OUTPUT_TMP=""; EVM_COMPLETE=0
    trap 'evm_cleanup "$?"' 0
    trap 'evm_cleanup 129' HUP
    trap 'evm_cleanup 130' INT
    trap 'evm_cleanup 143' TERM
    EVM_OUTPUT_TMP="$(mktemp "${OUT}.partial.XXXXXX")"

    if [ "$EVM_STATUS" != stopped ]; then
        info "Gracefully stopping guest $VMID for a stable export..."
        if [ "$EVM_KIND" = qemu ]; then qm shutdown "$VMID" --timeout 60 || refuse "Guest did not shut down gracefully; exact export refuses to force-stop it."
        else pct shutdown "$VMID" --timeout 60 || refuse "Container did not shut down gracefully."; fi
        [ "$(guest_status "$VMID" "$EVM_KIND")" = stopped ] || refuse "Guest did not reach stopped state."
        EVM_STOPPED_BY_US=1
    fi

    EVM_STAGE="$(mktemp -d "${TMPDIR:-/var/tmp}/ltvm-export-${VMID}.XXXXXX")"
    mkdir -p "$EVM_STAGE/ltvm/payload"
    cp "$EVM_CFG" "$EVM_STAGE/ltvm/config.conf"
    if [ -f "/etc/pve/firewall/${VMID}.fw" ]; then cp "/etc/pve/firewall/${VMID}.fw" "$EVM_STAGE/ltvm/firewall.fw"; EVM_FIREWALL=1; else EVM_FIREWALL=0; fi
    evm_capture_external_metadata "$VMID" "$EVM_STAGE/ltvm/external-metadata.txt"
    evm_write_restore_script "$EVM_STAGE/ltvm/restore.sh"
    evm_write_storage_map "$EVM_CFG" "$EVM_KIND" "$EVM_STAGE/ltvm/storage-map.tsv"

    info "Creating native Proxmox backup payload..."
    vzdump "$VMID" --dumpdir "$EVM_STAGE/ltvm/payload" --mode stop --compress zstd --remove 0
    EVM_PAYLOAD="$(find "$EVM_STAGE/ltvm/payload" -maxdepth 1 -type f -name "vzdump-${EVM_KIND}-${VMID}-*" ! -name '*.log' | head -n1)"
    [ -n "$EVM_PAYLOAD" ] || verification_failure "vzdump completed but no payload archive was found."
    EVM_PAYLOAD_COUNT="$(find "$EVM_STAGE/ltvm/payload" -maxdepth 1 -type f -name "vzdump-${EVM_KIND}-${VMID}-*" ! -name '*.log' | awk 'END{print NR+0}')"
    [ "$EVM_PAYLOAD_COUNT" -eq 1 ] || verification_failure "Expected exactly one vzdump payload, found $EVM_PAYLOAD_COUNT."
    EVM_PAYLOAD_BASE="$(basename "$EVM_PAYLOAD")"
    EVM_SOURCE_NODE="$(hostname)"
    EVM_NAME="$(sed -n 's/^name:[[:space:]]*//p' "$EVM_CFG" | head -n1)"
    {
        printf 'format\tlongtailtoil-vm-export\n'
        printf 'format_version\t1\n'
        printf 'project_version\t%s\n' "$PROJECT_VERSION"
        printf 'vmid\t%s\n' "$VMID"
        printf 'kind\t%s\n' "$EVM_KIND"
        printf 'name\t%s\n' "$EVM_NAME"
        printf 'source_node\t%s\n' "$EVM_SOURCE_NODE"
        printf 'source_status\t%s\n' "$EVM_ORIGINAL_STATUS"
        printf 'created_utc\t%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        printf 'payload_rel\tltvm/payload/%s\n' "$EVM_PAYLOAD_BASE"
        printf 'firewall_present\t%s\n' "$EVM_FIREWALL"
        printf 'content_hashes\t%s\n' "$CONTENT_HASH"
        printf 'identity_scope\tguest-config+backed-up-storage+guest-firewall\n'
    } > "$EVM_STAGE/ltvm/manifest.tsv"

    (
      cd "$EVM_STAGE"
      : > ltvm/checksums.sha256
      find ltvm -type f ! -path 'ltvm/checksums.sha256' -print | sort |
        while IFS= read -r EVM_FILE; do sha256sum "$EVM_FILE"; done > ltvm/checksums.sha256
    )
    journal_begin export-vm
    journal_note vmid "$VMID"; journal_note archive "$OUT"
    tar -cf "$EVM_OUTPUT_TMP" -C "$EVM_STAGE" ltvm
    tar -tf "$EVM_OUTPUT_TMP" | grep -Fx 'ltvm/manifest.tsv' >/dev/null || verification_failure "Outer archive validation failed."
    EVM_ARCHIVE_HASH="$(sha256sum "$EVM_OUTPUT_TMP" | awk '{print $1}')"
    if [ "$FORCE" -eq 1 ]; then
        mv -Tf "$EVM_OUTPUT_TMP" "$OUT" ||
            verification_failure "Could not atomically replace output archive."
        EVM_OUTPUT_TMP=""
    else
        ln "$EVM_OUTPUT_TMP" "$OUT" ||
            verification_failure "Output path appeared before archive commit; refusing to overwrite it."
        rm -f "$EVM_OUTPUT_TMP"
        EVM_OUTPUT_TMP=""
    fi
    journal_note archive_sha256 "$EVM_ARCHIVE_HASH"
    EVM_COMPLETE=1
    printf 'Archive SHA-256: %s\n' "$EVM_ARCHIVE_HASH"
    ok "Portable VM archive created atomically: $OUT"
    if [ "$EVM_STOPPED_BY_US" -eq 1 ] && [ "$LEAVE_STOPPED" -eq 0 ]; then
        info "Restoring original running state..."
        if [ "$EVM_KIND" = qemu ]; then qm start "$VMID"; else pct start "$VMID"; fi
        EVM_STOPPED_BY_US=0
    fi
}

# end
# Call: end
# Finalizes output and dry-run/preflight status.
end() {
    finish_common
}

# usage
# Call: usage
# Prints the public command-line interface.
usage() {
    cat <<EOF
export-vm.sh $SCRIPT_VERSION (project $PROJECT_VERSION)

USAGE
  export-vm.sh <VMID> <output.ltvm> [--stop] [--leave-stopped] [--force]
               [--no-content-hash] [dryrun|--preflight]

DESCRIPTION
  Creates one self-contained LongTail VM archive containing:
    - a native compressed vzdump payload
    - the exact guest config and guest firewall file
    - storage topology and, by default, full guest-visible SHA-256 disk hashes
    - guest-related ACL/HA/replication lines as a non-replayed audit record
    - checksums and an embedded standalone restore program

EXACTNESS / PORTABILITY
  The default exact mode refuses locked guests, snapshots, unusedN disks,
  backup=0 disks, external ISO media, LXC bind mounts and explicit
  host-resource config that
  cannot be recreated from the archive alone. Generated cloud-init media is
  restored from its archived configuration and is marked generated rather than
  byte-hashed. "Exact" means persistent guest configuration, backed-up guest
  storage content, and guest firewall identity. QEMU vmgenid is intentionally
  allowed to regenerate during restore and is excluded from exact config
  comparison. Exactness does not mean preserving physical LV UUID/extents/
  device-mapper identity or the guest's live RAM state.
  Cluster-wide ACL/HA/pool/replication policy is not automatically replayed on
  another cluster because doing so would mutate objects outside the guest;
  relevant lines are carried as an audit record.

STATE
  The guest must be stopped. --stop permits a graceful temporary shutdown and
  the original running state is restored after a successful/failed export unless
  --leave-stopped is requested. No force-stop is performed.
EOF
    cat <<'LONGTAIL_COMMON_OPTIONS_EOF'

COMMON OPTIONS
  -h, -?, /h, /?, --help  Show this help and exit.
  --version               Show script and project versions and exit.
  dryrun, --dryrun,
  --plan                  Enable dry-run/plan mode.
  --preflight             Run the same non-mutating preflight/plan path.
  --no-color              Disable ANSI colour output.
  --quiet                 Reduce non-essential LongTail output where supported.

  Common options may appear anywhere on the command line.
  Dry-run: no system changes are made; modifying commands are printed instead of executed.
LONGTAIL_COMMON_OPTIONS_EOF
}


############################################################
# COMMON RUNTIME
############################################################

# preparse_common_options ARGS...
# Call: preparse_common_options "$@"
# Applies output-only options before colours are initialized.
preparse_common_options() {
    preparse_common_options_arg=""
    for preparse_common_options_arg in "$@"; do
        case "$preparse_common_options_arg" in
            --no-color) NO_COLOR=1; export NO_COLOR ;;
            --quiet) QUIET=1 ;;
        esac
    done
}

# define_colours
# Call: define_colours
# Enables colours only on an interactive stdout and when NO_COLOR is unset.
define_colours() {
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
        define_colours_esc="$(printf '\033')"
        C_RESET="${define_colours_esc}[0m"; C_RED="${define_colours_esc}[31m"
        C_GREEN="${define_colours_esc}[32m"; C_YELLOW="${define_colours_esc}[33m"
        C_BLUE="${define_colours_esc}[34m"; C_CYAN="${define_colours_esc}[36m"
        C_BOLD="${define_colours_esc}[1m"
    else
        C_RESET=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_CYAN=""; C_BOLD=""
    fi
}

# info TEXT...
# Call: info [TEXT...]
# Prints an informational message unless quiet output suppresses it.
info() { [ "${QUIET:-0}" -eq 1 ] || printf '%s%s%s\n' "$C_CYAN" "$*" "$C_RESET"; }

# ok TEXT...
# Call: ok [TEXT...]
# Prints a successful-result message.
ok() { [ "${QUIET:-0}" -eq 1 ] || printf '%s[OK]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }

# warn TEXT...
# Call: warn [TEXT...]
# Prints a warning without terminating the command.
warn() { printf '%sWARNING:%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }

# die TEXT...
# Call: die [TEXT...]
# Runtime failure: exit 1.
die() { printf '%sERROR:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

# usage_error TEXT...
# Call: usage_error [TEXT...]
# Command-line usage failure: exit 2.
usage_error() {
    printf '%sUSAGE ERROR:%s %s\n\n' "$C_RED" "$C_RESET" "$*" >&2
    usage >&2
    exit 2
}

# refuse TEXT...
# Call: refuse [TEXT...]
# Safety refusal: exit 3.
refuse() { printf '%sREFUSED:%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; exit 3; }

# verification_failure TEXT...
# Call: verification_failure [TEXT...]
# Postcondition/audit verification failure: exit 4.
verification_failure() { printf '%sVERIFY:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 4; }

# need_commands COMMAND...
# Call: need_commands COMMAND...
# Fails before mutation when any required external command is unavailable.
need_commands() {
    need_commands_cmd=""
    for need_commands_cmd in "$@"; do command -v "$need_commands_cmd" >/dev/null 2>&1 || die "Required command is missing: $need_commands_cmd"; done
}

# check_elevation
# Call: check_elevation
# Sets APP_ELEVATED silently.
check_elevation() {
    if [ "$(id -u)" -eq 0 ]; then APP_ELEVATED="true"; else APP_ELEVATED="false"; fi
    export APP_ELEVATED
}

# self_elevate ARGS...
# Call: self_elevate "$@"
# Re-executes the current helper through sudo when root privileges are required.
self_elevate() {
    command -v sudo >/dev/null 2>&1 || die "Root privileges are required and sudo is unavailable."
    warn "Re-running with root privileges..."
    exec sudo -- /bin/sh "$0" "$@"
}

# shell_quote VALUE
# Call: shell_quote VALUE
# Prints one POSIX-shell-safe representation for display only.
shell_quote() {
    shell_quote_value="$1"
    case "$shell_quote_value" in
        *[!A-Za-z0-9_./:@%+=,-]*|'') printf "'"; printf '%s' "$shell_quote_value" | sed "s/'/'\\\\''/g"; printf "'" ;;
        *) printf '%s' "$shell_quote_value" ;;
    esac
}

# single_line_value VALUE
# Call: single_line_value VALUE
# Returns success only when a value contains no CR/LF config-line separators.
single_line_value() {
    single_line_value_cr="$(printf '\r')"
    case "$1" in
        *'
'*|*"$single_line_value_cr"*) return 1 ;;
        *) return 0 ;;
    esac
}

# print_command COMMAND...
# Call: print_command COMMAND...
# Renders one command in a shell-readable form for dry-run/plan output.
print_command() {
    print_command_first=1
    if [ "${DRYRUN:-0}" -eq 1 ]; then printf '%s[DRYRUN]%s ' "$C_YELLOW" "$C_RESET"; fi
    for print_command_arg in "$@"; do
        [ "$print_command_first" -eq 1 ] || printf ' '
        shell_quote "$print_command_arg"
        print_command_first=0
    done
    printf '\n'
}

# run_mutation COMMAND...
# Call: run_mutation COMMAND...
# Executes a modifying command normally or prints it without execution in dry-run mode.
run_mutation() {
    if [ "${DRYRUN:-0}" -eq 1 ]; then print_command "$@"; return 0; fi
    "$@"
}

# dryrun_cmd COMMAND...
# Call: dryrun_cmd COMMAND...
# Compatibility wrapper for new helpers that need the common DRYRUN flag.
dryrun_cmd() {
    if [ "${DRYRUN:-0}" -eq 1 ]; then print_command "$@"; return 0; fi
    "$@"
}

# dryrun_verify TEXT...
# Call: dryrun_verify TEXT...
# Prints an explicit simulated-verification marker in dry-run mode.
dryrun_verify() {
    if [ "${DRYRUN:-0}" -eq 1 ]; then
        printf '[DRYRUN VERIFY] %s (simulated success)\n' "$*"
    fi
}

# require_qemu_vm VMID
# Call: require_qemu_vm VMID
# Verifies that the requested local QEMU VM exists and its configuration is readable.
require_qemu_vm() {
    require_qemu_vm_vmid="$1"
    case "$require_qemu_vm_vmid" in ''|*[!0-9]*) usage_error "VMID must be numeric: $require_qemu_vm_vmid" ;; esac
    [ -f "/etc/pve/qemu-server/${require_qemu_vm_vmid}.conf" ] || refuse "QEMU VM $require_qemu_vm_vmid does not exist on this node."
    qm config "$require_qemu_vm_vmid" >/dev/null 2>&1 || die "Proxmox cannot read VM $require_qemu_vm_vmid."
}

# guest_kind VMID
# Call: guest_kind VMID
# Prints qemu or lxc.
guest_kind() {
    guest_kind_vmid="$1"
    if [ -f "/etc/pve/qemu-server/${guest_kind_vmid}.conf" ]; then printf '%s\n' qemu
    elif [ -f "/etc/pve/lxc/${guest_kind_vmid}.conf" ]; then printf '%s\n' lxc
    else return 1; fi
}

# guest_config_path VMID
# Call: guest_config_path VMID
# Prints the local QEMU or LXC configuration path for one guest.
guest_config_path() {
    guest_config_path_vmid="$1"
    guest_config_path_kind="$(guest_kind "$guest_config_path_vmid")" || return 1
    if [ "$guest_config_path_kind" = qemu ]; then printf '/etc/pve/qemu-server/%s.conf\n' "$guest_config_path_vmid"
    else printf '/etc/pve/lxc/%s.conf\n' "$guest_config_path_vmid"; fi
}

# guest_status VMID KIND
# Call: guest_status VMID KIND
# Prints the normalized runtime status for a QEMU VM or LXC container.
guest_status() {
    guest_status_vmid="$1"; guest_status_kind="$2"
    if [ "$guest_status_kind" = qemu ]; then qm status "$guest_status_vmid" 2>/dev/null | awk '{print $2}'
    else pct status "$guest_status_vmid" 2>/dev/null | awk '{print $2}'; fi
}

# disk_value VMID SLOT
# Call: disk_value VMID SLOT
# Prints the complete configured value for one QEMU disk/device slot.
disk_value() { qm config "$1" | sed -n "s/^${2}:[[:space:]]*//p" | head -n1; }

# disk_volid VMID SLOT
# Call: disk_volid VMID SLOT
# Prints only the storage:volume identifier from one configured disk slot.
disk_volid() {
    disk_volid_value="$(disk_value "$1" "$2")"
    [ -n "$disk_volid_value" ] || return 1
    disk_volid_value="${disk_volid_value%%,*}"
    case "$disk_volid_value" in *:*) printf '%s\n' "$disk_volid_value" ;; *) return 1 ;; esac
}

# resolve_volid_path VOLID
# Call: resolve_volid_path VOLID
# Resolves a Proxmox storage volume identifier to its canonical backing path.
resolve_volid_path() { pvesm path "$1" 2>/dev/null | head -n1; }

# lvm_identity PATH
# Call: lvm_identity PATH
# Prints VG|LV|UUID|SIZE|POOL|ORIGIN|ATTR.
lvm_identity() {
    lvm_identity_path="$1"
    lvs --noheadings --separator '|' -o vg_name,lv_name,lv_uuid,lv_size,pool_lv,origin,lv_attr "$lvm_identity_path" 2>/dev/null |
        head -n1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/[[:space:]]*|[[:space:]]*/|/g'
}

# prepare_readable_path PATH TRACK_FILE
# Call: prepare_readable_path PATH TRACK_FILE
# Sets READABLE_PATH. If PATH is an inactive LVM LV, temporarily activates it
# with -K and records VG|LV|UUID for later restoration. Dry-run/preflight never
# changes activation state and returns status 2 when activation would be needed.
prepare_readable_path() {
    prepare_readable_path_input="$1"; prepare_readable_path_track="$2"
    prepare_readable_path_identity="$(lvm_identity "$prepare_readable_path_input" || :)"
    if [ -z "$prepare_readable_path_identity" ]; then
        [ -b "$prepare_readable_path_input" ] || return 1
        READABLE_PATH="$prepare_readable_path_input"
        export READABLE_PATH
        return 0
    fi
    prepare_readable_path_vg="$(printf '%s\n' "$prepare_readable_path_identity" | cut -d'|' -f1)"
    prepare_readable_path_lv="$(printf '%s\n' "$prepare_readable_path_identity" | cut -d'|' -f2)"
    prepare_readable_path_uuid="$(printf '%s\n' "$prepare_readable_path_identity" | cut -d'|' -f3)"
    prepare_readable_path_attr="$(printf '%s\n' "$prepare_readable_path_identity" | cut -d'|' -f7)"
    READABLE_PATH="/dev/$prepare_readable_path_vg/$prepare_readable_path_lv"
    export READABLE_PATH
    case "$prepare_readable_path_attr" in
        ????a*) [ -b "$READABLE_PATH" ] || return 1; return 0 ;;
    esac
    if [ "${DRYRUN:-0}" -eq 1 ] || [ "${PREFLIGHT:-0}" -eq 1 ]; then return 2; fi
    run_lvm_filtered lvchange -ay -K "$prepare_readable_path_vg/$prepare_readable_path_lv" ||
        return 1
    [ -b "$READABLE_PATH" ] || return 1
    if [ -n "$prepare_readable_path_track" ]; then
        if ! grep -qF "|$prepare_readable_path_uuid" "$prepare_readable_path_track" 2>/dev/null; then
            printf '%s|%s|%s\n' "$prepare_readable_path_vg" "$prepare_readable_path_lv" "$prepare_readable_path_uuid" >> "$prepare_readable_path_track"
        fi
    fi
    return 0
}

# restore_tracked_activations TRACK_FILE
# Call: restore_tracked_activations TRACK_FILE
# Restores only exact UUIDs temporarily activated by prepare_readable_path.
restore_tracked_activations() {
    restore_tracked_activations_file="$1"
    [ -f "$restore_tracked_activations_file" ] || return 0
    awk '{line[NR]=$0} END{for(i=NR;i>=1;i--)print line[i]}' "$restore_tracked_activations_file" |
    while IFS='|' read -r restore_tracked_vg restore_tracked_lv restore_tracked_uuid; do
        [ -n "$restore_tracked_vg" ] || continue
        restore_tracked_now="$(lvs --noheadings -o lv_uuid "$restore_tracked_vg/$restore_tracked_lv" 2>/dev/null | awk '{$1=$1;print;exit}')"
        [ "$restore_tracked_now" = "$restore_tracked_uuid" ] || continue
        run_lvm_filtered lvchange -an "$restore_tracked_vg/$restore_tracked_lv" >/dev/null 2>&1 ||
            warn "Could not restore temporary activation: $restore_tracked_vg/$restore_tracked_lv"
    done
}

# all_guest_configs
# Call: all_guest_configs
# Lists local QEMU and LXC guest configuration files used for ownership/reference checks.
all_guest_configs() {
    find /etc/pve/nodes -type f \( -path '*/qemu-server/*.conf' -o -path '*/lxc/*.conf' \) -print 2>/dev/null | sort
}

# config_volids CONFIG
# Call: config_volids CONFIG
# Prints exact Proxmox volume identifiers from active, unused, EFI, TPM and LXC storage keys.
config_volids() {
    awk -F': ' '
        $1 ~ /^(ide|sata|scsi|virtio|unused|efidisk|tpmstate)[0-9]+$/ ||
        $1 == "rootfs" || $1 ~ /^mp[0-9]+$/ {
            split($2,a,",")
            if (a[1] ~ /^[^:]+:.+/) print a[1]
        }
    ' "$1"
}

# volid_lv_uuid VOLID
# Call: volid_lv_uuid VOLID
# Resolves a Proxmox volume identifier and prints its LVM UUID when LVM-backed.
volid_lv_uuid() {
    volid_lv_uuid_path="$(resolve_volid_path "$1" || :)"
    [ -n "$volid_lv_uuid_path" ] || return 1
    volid_lv_uuid_identity="$(lvm_identity "$volid_lv_uuid_path" || :)"
    [ -n "$volid_lv_uuid_identity" ] || return 1
    printf '%s\n' "$volid_lv_uuid_identity" | cut -d'|' -f3
}

# volid_reference_count VOLID
# Call: volid_reference_count VOLID
# Counts exact storage references by physical LV UUID when possible. This catches
# storage aliases that use different Proxmox volume IDs for the same LVM object.
# Non-LVM references fall back to exact Proxmox volume-ID equality.
volid_reference_count() {
    volid_reference_count_target="$1"
    volid_reference_count_uuid="$(volid_lv_uuid "$volid_reference_count_target" || :)"
    volid_reference_count_count=0
    for volid_reference_count_cfg in $(all_guest_configs); do
        for volid_reference_count_ref in $(config_volids "$volid_reference_count_cfg"); do
            if [ -n "$volid_reference_count_uuid" ]; then
                volid_reference_count_ref_uuid="$(volid_lv_uuid "$volid_reference_count_ref" || :)"
                [ -n "$volid_reference_count_ref_uuid" ] || continue
                [ "$volid_reference_count_ref_uuid" = "$volid_reference_count_uuid" ] || continue
            else
                [ "$volid_reference_count_ref" = "$volid_reference_count_target" ] || continue
            fi
            volid_reference_count_count=$((volid_reference_count_count + 1))
        done
    done
    printf '%s\n' "$volid_reference_count_count"
}

# lv_uuid_reference_count UUID
# Call: lv_uuid_reference_count UUID
# Counts all guest-storage references that resolve to one exact LVM UUID.
lv_uuid_reference_count() {
    lv_uuid_reference_count_uuid="$1"
    lv_uuid_reference_count_count=0
    for lv_uuid_reference_count_cfg in $(all_guest_configs); do
        for lv_uuid_reference_count_ref in $(config_volids "$lv_uuid_reference_count_cfg"); do
            lv_uuid_reference_count_ref_uuid="$(volid_lv_uuid "$lv_uuid_reference_count_ref" || :)"
            [ -n "$lv_uuid_reference_count_ref_uuid" ] || continue
            [ "$lv_uuid_reference_count_ref_uuid" = "$lv_uuid_reference_count_uuid" ] || continue
            lv_uuid_reference_count_count=$((lv_uuid_reference_count_count + 1))
        done
    done
    printf '%s\n' "$lv_uuid_reference_count_count"
}

# volid_reference_lines VOLID
# Call: volid_reference_lines VOLID
# Prints config|slot|volid for references to the same physical LV identity.
volid_reference_lines() {
    volid_reference_lines_target="$1"
    volid_reference_lines_uuid="$(volid_lv_uuid "$volid_reference_lines_target" || :)"
    for volid_reference_lines_cfg in $(all_guest_configs); do
        awk -F': ' '
            $1 ~ /^(ide|sata|scsi|virtio|unused|efidisk|tpmstate)[0-9]+$/ ||
            $1 == "rootfs" || $1 ~ /^mp[0-9]+$/ {
                split($2,a,",")
                if (a[1] ~ /^[^:]+:.+/) print $1 "|" a[1]
            }
        ' "$volid_reference_lines_cfg" |
        while IFS='|' read -r volid_reference_lines_slot volid_reference_lines_ref; do
            [ -n "$volid_reference_lines_ref" ] || continue
            if [ -n "$volid_reference_lines_uuid" ]; then
                volid_reference_lines_ref_uuid="$(volid_lv_uuid "$volid_reference_lines_ref" || :)"
                [ "$volid_reference_lines_ref_uuid" = "$volid_reference_lines_uuid" ] || continue
            else
                [ "$volid_reference_lines_ref" = "$volid_reference_lines_target" ] || continue
            fi
            printf '%s|%s|%s\n' "$volid_reference_lines_cfg" "$volid_reference_lines_slot" "$volid_reference_lines_ref"
        done
    done
}

# lvm_thin_warning_filter
# Call: lvm_thin_warning_filter
# Filters only known LVM-thin advisory warnings while preserving real errors.
lvm_thin_warning_filter() {
    grep -vE \
        -e 'WARNING: Sum of all thin volume sizes .* exceeds the size of thin pool' \
        -e 'WARNING: You have not turned on protection against thin pools running out of space\.' \
        -e 'WARNING: Set activation/thin_pool_autoextend_threshold below 100 to trigger automatic extension of thin pools before they get full\.' >&2 || :
}

# run_lvm_filtered COMMAND...
# Call: run_lvm_filtered COMMAND...
# Runs an LVM command, filters only known advisory warnings, and preserves status.
run_lvm_filtered() (
    run_lvm_filtered_err="$(mktemp)" || exit 1
    trap 'rm -f "$run_lvm_filtered_err"' 0 HUP INT TERM
    set +e
    "$@" 2>"$run_lvm_filtered_err"
    run_lvm_filtered_rc=$?
    set -e
    lvm_thin_warning_filter < "$run_lvm_filtered_err"
    exit "$run_lvm_filtered_rc"
)

# first_free_scsi VMID
# Call: first_free_scsi VMID
# Prints the first unused QEMU SCSI slot within the supported Proxmox range.
first_free_scsi() {
    first_free_scsi_vmid="$1"; first_free_scsi_i=0; first_free_scsi_cfg="$(qm config "$first_free_scsi_vmid")"
    while [ "$first_free_scsi_i" -le 30 ]; do
        if ! printf '%s\n' "$first_free_scsi_cfg" | grep -qE "^scsi${first_free_scsi_i}:"; then printf 'scsi%s\n' "$first_free_scsi_i"; return 0; fi
        first_free_scsi_i=$((first_free_scsi_i + 1))
    done
    return 1
}

# disk_slot_limit BUS
# Call: disk_slot_limit BUS
# Prints the highest supported Proxmox disk index for one QEMU disk bus.
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
# Call: valid_disk_slot SLOT
# Accepts only an exact ideN/sataN/scsiN/virtioN key within Proxmox limits.
valid_disk_slot() {
    valid_disk_slot_value="$1"
    case "$valid_disk_slot_value" in
        ide*) valid_disk_slot_bus="ide"; valid_disk_slot_num="${valid_disk_slot_value#ide}" ;;
        sata*) valid_disk_slot_bus="sata"; valid_disk_slot_num="${valid_disk_slot_value#sata}" ;;
        scsi*) valid_disk_slot_bus="scsi"; valid_disk_slot_num="${valid_disk_slot_value#scsi}" ;;
        virtio*) valid_disk_slot_bus="virtio"; valid_disk_slot_num="${valid_disk_slot_value#virtio}" ;;
        *) return 1 ;;
    esac
    case "$valid_disk_slot_num" in ''|*[!0-9]*) return 1 ;; esac
    valid_disk_slot_max="$(disk_slot_limit "$valid_disk_slot_bus")" || return 1
    [ "$valid_disk_slot_num" -le "$valid_disk_slot_max" ]
}

# valid_unused_slot SLOT
# Call: valid_unused_slot SLOT
# Accepts only exact unused0..unused255 config keys.
valid_unused_slot() {
    valid_unused_slot_value="$1"
    case "$valid_unused_slot_value" in
        unused*) valid_unused_slot_num="${valid_unused_slot_value#unused}" ;;
        *) return 1 ;;
    esac
    case "$valid_unused_slot_num" in ''|*[!0-9]*) return 1 ;; esac
    [ "$valid_unused_slot_num" -le 255 ]
}

# valid_lvm_component NAME
# Call: valid_lvm_component NAME
# Accepts a single VG/LV/pool name component safe to pass as one LVM operand.
valid_lvm_component() {
    case "$1" in
        ''|-*|*[!A-Za-z0-9+_.-]*) return 1 ;;
        *) return 0 ;;
    esac
}

# qemu_config_has_snapshots CONFIG
# Call: qemu_config_has_snapshots CONFIG
# Returns success when a QEMU config contains snapshot/section headers.
qemu_config_has_snapshots() {
    grep -qE '^\[' "$1"
}

# valid_qemu_storage_slot SLOT
# Call: valid_qemu_storage_slot SLOT
# Accepts ordinary disk slots, unusedN, efidisk0, or tpmstate0 exactly.
valid_qemu_storage_slot() {
    valid_qemu_storage_slot_value="$1"
    if valid_disk_slot "$valid_qemu_storage_slot_value"; then return 0; fi
    if valid_unused_slot "$valid_qemu_storage_slot_value"; then return 0; fi
    case "$valid_qemu_storage_slot_value" in efidisk0|tpmstate0) return 0 ;; *) return 1 ;; esac
}

# json_escape VALUE
# Call: json_escape VALUE
# Escapes a scalar for safe inclusion in the project JSON output format.
json_escape() {
    json_escape_value="$1"
    printf '%s' "$json_escape_value" | awk 'BEGIN{ORS=""} {gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); gsub(/\t/,"\\t"); gsub(/\r/,"\\r"); if (NR>1) printf "\\n"; printf "%s",$0}'
}

# make_temp_dir PREFIX
# Call: make_temp_dir PREFIX
# Creates and prints a unique transaction-owned temporary directory.
make_temp_dir() {
    make_temp_dir_prefix="$1"
    mktemp -d "${TMPDIR:-/var/tmp}/${make_temp_dir_prefix}.XXXXXX"
}

# journal_safe_value VALUE
# Call: journal_safe_value VALUE
# Converts journal values to a single line so values cannot inject journal keys.
journal_safe_value() {
    printf '%s' "$1" | tr '\r\n' '  '
}

# journal_begin OPERATION
# Call: journal_begin OPERATION
# Creates a root-owned, mode-0700 journal root and an unpredictable journal file.
journal_begin() {
    journal_begin_operation="$1"
    [ "${DRYRUN:-0}" -eq 0 ] || return 0
    OPERATION_ROOT="${LONGTAILTOIL_JOURNAL_DIR:-/var/tmp/longtailtoil-operations}"
    if [ -L "$OPERATION_ROOT" ]; then
        refuse "Journal root must not be a symbolic link: $OPERATION_ROOT"
    fi
    if [ ! -e "$OPERATION_ROOT" ]; then
        (umask 077; mkdir "$OPERATION_ROOT") || die "Could not create journal root: $OPERATION_ROOT"
    fi
    [ -d "$OPERATION_ROOT" ] || refuse "Journal root is not a directory: $OPERATION_ROOT"
    journal_begin_owner="$(ls -nd "$OPERATION_ROOT" 2>/dev/null | awk '{print $3}')"
    [ "$journal_begin_owner" = "0" ] || refuse "Journal root must be owned by root: $OPERATION_ROOT"
    chmod 700 "$OPERATION_ROOT" || die "Could not secure journal root: $OPERATION_ROOT"
    OPERATION_FILE="$(mktemp "$OPERATION_ROOT/.operation.XXXXXXXX.journal")" ||
        die "Could not create operation journal."
    chmod 600 "$OPERATION_FILE" || die "Could not secure operation journal."
    OPERATION_ID="$(basename "$OPERATION_FILE" .journal)"
    {
        printf 'operation_id=%s\n' "$(journal_safe_value "$OPERATION_ID")"
        printf 'operation=%s\n' "$(journal_safe_value "$journal_begin_operation")"
        printf 'script=%s\n' "$(journal_safe_value "$(basename "$0")")"
        printf 'project_version=%s\n' "$(journal_safe_value "$PROJECT_VERSION")"
        printf 'started=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    } > "$OPERATION_FILE"
    ln -sfn "$(basename "$OPERATION_FILE")" "$OPERATION_ROOT/latest"
}

# journal_note KEY VALUE
# Call: journal_note KEY VALUE
# Appends one sanitized key/value event to the active operation journal.
journal_note() {
    journal_note_key="$1"; journal_note_value="$2"
    [ "${DRYRUN:-0}" -eq 0 ] || return 0
    [ -n "${OPERATION_FILE:-}" ] || return 0
    case "$journal_note_key" in ''|*[!A-Za-z0-9_.-]*) refuse "Invalid journal key: $journal_note_key" ;; esac
    printf '%s=%s\n' "$journal_note_key" "$(journal_safe_value "$journal_note_value")" >> "$OPERATION_FILE"
}

# finish_common
# Call: finish_common
# Prints the standard dry-run/preflight completion summary without changing command status.
finish_common() {
    if [ "${PREFLIGHT:-0}" -eq 1 ]; then ok "Preflight completed; no mutation was executed."
    elif [ "${DRYRUN:-0}" -eq 1 ]; then [ "${QUIET:-0}" -eq 1 ] || printf '[DRYRUN] No modifying command was executed.\n'
    fi
}


############################################################
# ARGUMENT PARSING
############################################################

# parse_arguments ARGS...
# Call: parse_arguments "$@"
# Parses common options and command-specific positional arguments into script state.
parse_arguments() {
    VMID=""; OUT=""; STOP_FOR_EXPORT=0; LEAVE_STOPPED=0; FORCE=0; CONTENT_HASH=1
    while [ "$#" -gt 0 ]; do
     case "$1" in
      -h|-\?|/h|/\?|--help) usage; exit 0 ;;
      --version) printf '%s %s (project %s)\n' "$(basename "$0")" "$SCRIPT_VERSION" "$PROJECT_VERSION"; exit 0 ;;
      dryrun|--dryrun|--plan) DRYRUN=1; shift ;;
      --preflight) PREFLIGHT=1; DRYRUN=1; shift ;;
      --no-color) NO_COLOR=1; export NO_COLOR; shift ;;
      --quiet) QUIET=1; shift ;;
      --stop) STOP_FOR_EXPORT=1; shift ;;
      --leave-stopped) LEAVE_STOPPED=1; shift ;;
      --force) FORCE=1; shift ;;
      --no-content-hash) CONTENT_HASH=0; shift ;;
      --*) usage_error "Unknown option: $1" ;;
      *) if [ -z "$VMID" ]; then VMID="$1"; elif [ -z "$OUT" ]; then OUT="$1"; else usage_error "Too many arguments."; fi; shift ;;
     esac
    done
    [ -n "$VMID" ] && [ -n "$OUT" ] || usage_error "VMID and output .ltvm path are required."
    case "$VMID" in *[!0-9]*|"") usage_error "VMID must be numeric." ;; esac
    single_line_value "$OUT" || usage_error "Output path must not contain a newline."
}

############################################################
# EXPORT VALIDATION / PACKAGING
############################################################

# evm_assert_self_contained CONFIG KIND
# Call: evm_assert_self_contained CONFIG KIND
# Refuses guest state that native vzdump cannot reproduce entirely from archive.
evm_assert_self_contained() {
    evm_assert_self_contained_cfg="$1"; evm_assert_self_contained_kind="$2"
    ! grep -qE '^\[' "$evm_assert_self_contained_cfg" || refuse "Guest snapshots are present; exact single-file export does not silently drop snapshot history."
    ! grep -qE '^lock:[[:space:]]' "$evm_assert_self_contained_cfg" || refuse "Guest is locked; exact export refuses to operate across another Proxmox transaction."
    ! grep -qE '^unused[0-9]+:' "$evm_assert_self_contained_cfg" || refuse "unusedN volumes are present; exact export refuses because native vzdump does not guarantee their data is included."
    ! grep -qE '^(hostpci|usb|parallel|virtiofs|hookscript|args|rng)[0-9]*:' "$evm_assert_self_contained_cfg" || refuse "Guest references host/external resources that cannot be recreated from the archive alone."
    if [ "$evm_assert_self_contained_kind" = qemu ]; then
        ! grep -qE '^cicustom:' "$evm_assert_self_contained_cfg" || refuse "cicustom references external snippets that are not embedded by native VM backup."
        if grep -qE '^serial[0-9]+:' "$evm_assert_self_contained_cfg"; then
            while IFS= read -r evm_assert_self_contained_serial; do
                case "${evm_assert_self_contained_serial#*: }" in socket) : ;; *) refuse "Serial device uses an external host resource: $evm_assert_self_contained_serial" ;; esac
            done <<EOF
$(grep -E '^serial[0-9]+:' "$evm_assert_self_contained_cfg" || :)
EOF
        fi
        while IFS= read -r evm_assert_self_contained_line; do
            [ -n "$evm_assert_self_contained_line" ] || continue
            printf '%s\n' "$evm_assert_self_contained_line" | grep -qE ',backup=0(,|$)' && refuse "A configured disk has backup=0 and would be omitted by vzdump."
            if printf '%s\n' "$evm_assert_self_contained_line" | grep -qE ',media=cdrom(,|$)'; then
                evm_assert_self_contained_value="${evm_assert_self_contained_line#*: }"; evm_assert_self_contained_volid="${evm_assert_self_contained_value%%,*}"
                case "$evm_assert_self_contained_volid" in none|*:cloudinit) : ;; *) refuse "External CD/DVD media is attached: $evm_assert_self_contained_volid" ;; esac
            fi
        done <<EOF
$(grep -E '^(ide|sata|scsi|virtio|efidisk|tpmstate)[0-9]+:' "$evm_assert_self_contained_cfg" || :)
EOF
    else
        ! grep -qE '^(lxc\.mount|lxc\.hook|dev[0-9]+:)' "$evm_assert_self_contained_cfg" || refuse "Container config contains host-mounted/device resources that cannot be recreated from the archive alone."
        while IFS= read -r evm_assert_self_contained_line; do
            [ -n "$evm_assert_self_contained_line" ] || continue
            printf '%s\n' "$evm_assert_self_contained_line" | grep -qE ',backup=0(,|$)' && refuse "An LXC mount has backup=0."
            evm_assert_self_contained_value="${evm_assert_self_contained_line#*: }"; evm_assert_self_contained_source="${evm_assert_self_contained_value%%,*}"
            case "$evm_assert_self_contained_source" in /*) refuse "LXC bind mount is external to the guest backup: $evm_assert_self_contained_source" ;; esac
        done <<EOF
$(grep -E '^(rootfs|mp[0-9]+):' "$evm_assert_self_contained_cfg" || :)
EOF
    fi
}

# evm_validate_storage_resolution CONFIG KIND
# Call: evm_validate_storage_resolution CONFIG KIND
# Verifies that every archived storage reference resolves to the intended local storage identity.
evm_validate_storage_resolution() {
    evm_validate_storage_resolution_cfg="$1"; evm_validate_storage_resolution_kind="$2"
    while IFS= read -r evm_validate_storage_resolution_volid; do
        [ -n "$evm_validate_storage_resolution_volid" ] || continue
        case "$evm_validate_storage_resolution_volid" in none|*:cloudinit) continue ;; esac
        resolve_volid_path "$evm_validate_storage_resolution_volid" >/dev/null 2>&1 || refuse "Cannot resolve guest storage volume: $evm_validate_storage_resolution_volid"
    done <<EOF
$(awk '/^(ide|sata|scsi|virtio|efidisk|tpmstate)[0-9]+: |^rootfs: |^mp[0-9]+: / {line=$0; sub(/^[^:]+:[[:space:]]*/,"",line); split(line,a,","); if(a[1]~/:/)print a[1]}' "$evm_validate_storage_resolution_cfg")
EOF
}

# evm_hash_virtual_content PATH
# Call: evm_hash_virtual_content PATH
# Hashes guest-visible raw bytes. Regular image files are converted to a
# temporary raw file first so qcow2/container layout does not affect identity.
evm_hash_virtual_content() {
    evm_hash_virtual_content_path="$1"; evm_hash_virtual_content_activated=0
    if [ ! -b "$evm_hash_virtual_content_path" ] && [ ! -f "$evm_hash_virtual_content_path" ]; then
        evm_hash_virtual_content_id="$(lvm_identity "$evm_hash_virtual_content_path")" || return 1
        evm_hash_virtual_content_vg="$(printf '%s\n' "$evm_hash_virtual_content_id" | cut -d'|' -f1)"
        evm_hash_virtual_content_lv="$(printf '%s\n' "$evm_hash_virtual_content_id" | cut -d'|' -f2)"
        evm_hash_virtual_content_path="/dev/$evm_hash_virtual_content_vg/$evm_hash_virtual_content_lv"
        info "Temporarily activating inactive LV for content hashing: $evm_hash_virtual_content_vg/$evm_hash_virtual_content_lv"
        run_lvm_filtered lvchange -ay -K "$evm_hash_virtual_content_vg/$evm_hash_virtual_content_lv" || return 1
        evm_hash_virtual_content_activated=1
        [ -b "$evm_hash_virtual_content_path" ] || { run_lvm_filtered lvchange -an "$evm_hash_virtual_content_vg/$evm_hash_virtual_content_lv" >/dev/null 2>&1 || :; return 1; }
    fi
    if [ -b "$evm_hash_virtual_content_path" ]; then
        if evm_hash_virtual_content_hash="$(sha256sum "$evm_hash_virtual_content_path" | awk '{print $1}')"; then evm_hash_virtual_content_status=0; else evm_hash_virtual_content_status=$?; fi
        if [ "$evm_hash_virtual_content_activated" -eq 1 ]; then
            run_lvm_filtered lvchange -an "$evm_hash_virtual_content_vg/$evm_hash_virtual_content_lv" || { warn "Could not restore hashed LV to inactive state."; return 1; }
        fi
        [ "$evm_hash_virtual_content_status" -eq 0 ] || return "$evm_hash_virtual_content_status"
        printf '%s\n' "$evm_hash_virtual_content_hash"
        return 0
    fi
    if [ -f "$evm_hash_virtual_content_path" ]; then
        need_commands qemu-img
        evm_hash_virtual_content_tmp="$(mktemp "${TMPDIR:-/var/tmp}/ltvm-hash-raw.XXXXXX")"
        if qemu-img convert -q -O raw "$evm_hash_virtual_content_path" "$evm_hash_virtual_content_tmp" &&
           evm_hash_virtual_content_hash="$(sha256sum "$evm_hash_virtual_content_tmp" | awk '{print $1}')"; then
            evm_hash_virtual_content_status=0
        else evm_hash_virtual_content_status=$?; fi
        rm -f "$evm_hash_virtual_content_tmp"
        [ "$evm_hash_virtual_content_status" -eq 0 ] || return "$evm_hash_virtual_content_status"
        printf '%s\n' "$evm_hash_virtual_content_hash"
        return 0
    fi
    return 1
}

# evm_virtual_size PATH
# Call: evm_virtual_size PATH
# Prints the guest-visible virtual size of one archived/restored disk.
evm_virtual_size() {
    evm_virtual_size_path="$1"
    if [ -b "$evm_virtual_size_path" ]; then blockdev --getsize64 "$evm_virtual_size_path"; return 0; fi
    if [ -f "$evm_virtual_size_path" ]; then
        need_commands qemu-img
        qemu-img info --output=json "$evm_virtual_size_path" | sed -n 's/.*"virtual-size":[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -n1
        return 0
    fi
    if evm_virtual_size_id="$(lvm_identity "$evm_virtual_size_path")"; then
        evm_virtual_size_vg="$(printf '%s\n' "$evm_virtual_size_id" | cut -d'|' -f1)"
        evm_virtual_size_lv="$(printf '%s\n' "$evm_virtual_size_id" | cut -d'|' -f2)"
        lvs --noheadings --units b --nosuffix -o lv_size "$evm_virtual_size_vg/$evm_virtual_size_lv" 2>/dev/null | awk 'NF {printf "%.0f\n", $1; exit}'
        return 0
    fi
    printf '%s\n' 0
}

# evm_write_storage_map CONFIG KIND OUTPUT
# Call: evm_write_storage_map CONFIG KIND OUTPUT
# Writes the archive storage map used to verify exact restore placement.
evm_write_storage_map() {
    evm_write_storage_map_cfg="$1"; evm_write_storage_map_kind="$2"; evm_write_storage_map_out="$3"
    printf 'slot\tvolid\tstorage\tsize\tsha256\thash_mode\n' > "$evm_write_storage_map_out"
    if [ "$evm_write_storage_map_kind" = qemu ]; then
        while IFS='|' read -r evm_write_storage_map_slot evm_write_storage_map_value; do
            [ -n "$evm_write_storage_map_slot" ] || continue
            evm_write_storage_map_volid="${evm_write_storage_map_value%%,*}"
            case "$evm_write_storage_map_volid" in none|*:cloudinit) printf '%s\t%s\t%s\t0\tSKIP\tgenerated\n' "$evm_write_storage_map_slot" "$evm_write_storage_map_volid" "${evm_write_storage_map_volid%%:*}"; continue ;; *:*) : ;; *) continue ;; esac
            evm_write_storage_map_path="$(resolve_volid_path "$evm_write_storage_map_volid")" || refuse "Cannot resolve $evm_write_storage_map_volid"
            evm_write_storage_map_size="$(evm_virtual_size "$evm_write_storage_map_path")"
            if [ "$CONTENT_HASH" -eq 1 ]; then
                info "Hashing guest-visible content: $evm_write_storage_map_slot"
                evm_write_storage_map_hash="$(evm_hash_virtual_content "$evm_write_storage_map_path")" || refuse "Cannot hash $evm_write_storage_map_volid"
                evm_write_storage_map_mode=full
            else evm_write_storage_map_hash=SKIP; evm_write_storage_map_mode=disabled; fi
            printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$evm_write_storage_map_slot" "$evm_write_storage_map_volid" "${evm_write_storage_map_volid%%:*}" "$evm_write_storage_map_size" "$evm_write_storage_map_hash" "$evm_write_storage_map_mode" >> "$evm_write_storage_map_out"
        done <<EOF
$(awk -F': ' '/^(ide|sata|scsi|virtio|efidisk|tpmstate)[0-9]+:/ {print $1 "|" $2}' "$evm_write_storage_map_cfg")
EOF
    else
        while IFS='|' read -r evm_write_storage_map_slot evm_write_storage_map_value; do
            [ -n "$evm_write_storage_map_slot" ] || continue
            evm_write_storage_map_volid="${evm_write_storage_map_value%%,*}"; case "$evm_write_storage_map_volid" in *:*) : ;; *) continue ;; esac
            printf '%s\t%s\t%s\t0\tSKIP\tvzdump-filesystem\n' "$evm_write_storage_map_slot" "$evm_write_storage_map_volid" "${evm_write_storage_map_volid%%:*}" >> "$evm_write_storage_map_out"
        done <<EOF
$(awk -F': ' '/^rootfs:|^mp[0-9]+:/ {print $1 "|" $2}' "$evm_write_storage_map_cfg")
EOF
    fi
}

# evm_capture_external_metadata VMID OUTPUT
# Call: evm_capture_external_metadata VMID OUTPUT
# Captures guest-related cluster metadata as an audit record only.
evm_capture_external_metadata() {
    evm_capture_external_metadata_vmid="$1"; evm_capture_external_metadata_out="$2"
    {
      printf '# Guest-scoped external metadata audit record for VMID %s\n' "$evm_capture_external_metadata_vmid"
      if command -v pveum >/dev/null 2>&1; then printf '\n## ACL\n'; pveum acl list 2>/dev/null | grep -F "/vms/$evm_capture_external_metadata_vmid" || :; fi
      if command -v ha-manager >/dev/null 2>&1; then printf '\n## HA\n'; ha-manager config 2>/dev/null | grep -E "(vm|ct):${evm_capture_external_metadata_vmid}([^0-9]|$)" || :; fi
      if command -v pvesr >/dev/null 2>&1; then printf '\n## Replication\n'; pvesr list 2>/dev/null | grep -E "(^|[[:space:]])${evm_capture_external_metadata_vmid}([^0-9]|$)" || :; fi
    } > "$evm_capture_external_metadata_out"
}

# evm_write_restore_script PATH
# Call: evm_write_restore_script PATH
# Writes the self-contained restore program embedded into every .ltvm archive.
evm_write_restore_script() {
    evm_write_restore_script_path="$1"
    cat > "$evm_write_restore_script_path" <<'__PROXMOX_LONGTAIL_EMBEDDED_RESTORE__'
#!/bin/sh
set -eu

archive="${1:-}"
[ -n "$archive" ] || { printf 'USAGE: restore.sh <archive.ltvm> [--vmid ID] [--storage STORAGE] [--start] [--no-content-verify] [--dryrun]\n' >&2; exit 2; }
shift
target_override=""; storage_override=""; start_guest=0; verify_content=1; dryrun=0; quiet=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --vmid) [ "$#" -ge 2 ] || { printf 'ERROR: --vmid requires a value\n' >&2; exit 2; }; target_override="$2"; shift 2 ;;
        --storage) [ "$#" -ge 2 ] || { printf 'ERROR: --storage requires a value\n' >&2; exit 2; }; storage_override="$2"; shift 2 ;;
        --start) start_guest=1; shift ;;
        --no-content-verify) verify_content=0; shift ;;
        dryrun|--dryrun|--plan|--preflight) dryrun=1; shift ;;
        --quiet) quiet=1; shift ;;
        *) printf 'ERROR: unknown restore option: %s\n' "$1" >&2; exit 2 ;;
    esac
done

# Call: die MESSAGE...
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
# Call: refuse MESSAGE...
refuse() { printf 'REFUSED: %s\n' "$*" >&2; exit 3; }
# Call: verify_fail MESSAGE...
verify_fail() { printf 'VERIFY: %s\n' "$*" >&2; exit 4; }
# Call: say TEXT...
say() { [ "$quiet" -eq 1 ] || printf '%s\n' "$*"; }
# Call: need COMMAND
need() { command -v "$1" >/dev/null 2>&1 || die "required command is missing: $1"; }
[ "$(id -u)" -eq 0 ] || refuse "restore must run as root"
for cmd in tar sha256sum awk sed grep sort uniq mktemp pvesm date mkdir chmod stat ln basename rm cp cmp diff head; do need "$cmd"; done
[ -f "$archive" ] || refuse "archive not found: $archive"
case "$archive" in *'
'*) refuse "archive path must not contain a newline" ;; esac
[ -z "$target_override" ] || case "$target_override" in *[!0-9]*|'') refuse "target VMID override must be numeric" ;; esac
if [ -n "$storage_override" ]; then
    printf '%s\n' "$storage_override" | grep -Eq '^[A-Za-z0-9._-]+$' ||
        refuse "storage override contains unsafe characters"
fi

# Reject traversal, duplicates and non-regular object types before extraction.
listing="$(tar -tf "$archive" 2>/dev/null)" || refuse "archive is not a readable tar container"
printf '%s\n' "$listing" | awk '
    /^\// {bad=1}
    /(^|\/)\.\.($|\/)/ {bad=1}
    $0 !~ /^ltvm(\/|$)/ {bad=1}
    $0 !~ /^[A-Za-z0-9._\/-]+$/ {bad=1}
    END {exit bad}
' || refuse "archive contains an unsafe path"
[ -z "$(printf '%s\n' "$listing" | sort | uniq -d)" ] || refuse "archive contains duplicate member paths"
types="$(tar -tvf "$archive" 2>/dev/null)" || refuse "archive member metadata cannot be read"
printf '%s\n' "$types" | awk 'NF && substr($1,1,1)!="-" && substr($1,1,1)!="d"{bad=1} END{exit bad}' ||
    refuse "archive contains a symlink, hardlink, device, FIFO, or other non-regular member"
for required in ltvm/manifest.tsv ltvm/config.conf ltvm/storage-map.tsv ltvm/checksums.sha256 ltvm/restore.sh; do
    count="$(printf '%s\n' "$listing" | grep -Fxc "$required" || :)"
    [ "$count" -eq 1 ] || refuse "archive must contain exactly one $required"
done

# Validate checksum syntax and each covered member before extracting anything.
checksums="$(tar -xOf "$archive" ltvm/checksums.sha256 2>/dev/null)" || refuse "archive checksum list cannot be read"
[ -n "$checksums" ] || refuse "archive checksum list is empty"
printf '%s\n' "$checksums" | grep -Eq '^[[:xdigit:]]{64}  ltvm/[A-Za-z0-9._/-]+$' || refuse "archive checksum list has invalid syntax"
[ "$(printf '%s\n' "$checksums" | awk '$2=="ltvm/restore.sh"{n++} END{print n+0}')" -eq 1 ] || refuse "restore.sh is not covered exactly once by checksums"
printf '%s\n' "$checksums" | while IFS= read -r checksum_line; do
    expected="${checksum_line%% *}"
    member="${checksum_line#*  }"
    printf '%s\n' "$expected" | grep -Eq '^[0-9a-f]{64}$' || exit 8
    printf '%s\n' "$member" | grep -Eq '^ltvm/[A-Za-z0-9._/-]+$' || exit 8
    case "$member" in ltvm/*) : ;; *) exit 8 ;; esac
    case "$member" in *'/../'*|../*|*/..|..|/*) exit 8 ;; esac
    [ "$(printf '%s\n' "$listing" | grep -Fxc "$member" || :)" -eq 1 ] || exit 8
    actual="$(tar -xOf "$archive" "$member" 2>/dev/null | sha256sum | awk '{print $1}')"
    [ "$actual" = "$expected" ] || exit 9
done || refuse "archive checksum paths or content verification failed"
printf '%s\n' "$listing" | while IFS= read -r member; do
    case "$member" in */|ltvm/checksums.sha256) continue ;; esac
    printf '%s\n' "$checksums" | awk -v m="$member" '$2==m{n++} END{exit !(n==1)}' || exit 10
done || refuse "every regular archive member must be covered exactly once by checksums"

tmp="$(mktemp -d "${TMPDIR:-/var/tmp}/ltvm-restore.XXXXXX")"
# Call: cleanup
cleanup() { status=$?; trap - 0 HUP INT TERM; rm -rf "$tmp"; [ "$status" -eq 0 ] || exit "$status"; }
trap cleanup 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
tar -xf "$archive" -C "$tmp"
(cd "$tmp" && sha256sum -c ltvm/checksums.sha256 >/dev/null) || refuse "archive checksum verification failed"

manifest="$tmp/ltvm/manifest.tsv"
# Call: manifest_get KEY
manifest_get() { awk -F'\t' -v k="$1" '$1==k {sub(/^[^\t]*\t/,""); print; exit}' "$manifest"; }
format="$(manifest_get format)"; format_version="$(manifest_get format_version)"
[ "$format" = "longtailtoil-vm-export" ] && [ "$format_version" = "1" ] || refuse "unsupported archive format/version"
source_vmid="$(manifest_get vmid)"; kind="$(manifest_get kind)"; payload_rel="$(manifest_get payload_rel)"
case "$source_vmid" in ''|*[!0-9]*) refuse "archive VMID is invalid" ;; esac
case "$kind" in qemu|lxc) : ;; *) refuse "archive guest kind is invalid: $kind" ;; esac
case "$payload_rel" in ltvm/payload/*) : ;; *) refuse "unsafe payload path in manifest" ;; esac
payload="$tmp/$payload_rel"; [ -f "$payload" ] || refuse "payload is missing: $payload_rel"

target="$source_vmid"; [ -z "$target_override" ] || target="$target_override"
case "$target" in ''|*[!0-9]*) refuse "target VMID must be numeric" ;; esac
[ ! -e "/etc/pve/qemu-server/${target}.conf" ] && [ ! -e "/etc/pve/lxc/${target}.conf" ] || refuse "target VMID $target already exists"

exact=1
[ "$target" = "$source_vmid" ] || exact=0
[ -z "$storage_override" ] || exact=0
if [ "$exact" -eq 1 ]; then
    awk -F'\t' 'NR>1 && $3!="" {print $3}' "$tmp/ltvm/storage-map.tsv" | sort -u | while IFS= read -r st; do
        [ -n "$st" ] || continue
        pvesm status 2>/dev/null | awk -v s="$st" '$1==s {f=1} END{exit !f}' || exit 7
    done || refuse "one or more original Proxmox storage IDs are unavailable; use --storage for a relocated restore"
else
    say "NOTE: target VMID/storage override requested; this is a relocated restore, not exact storage/config identity."
fi

operation_root="${LONGTAILTOIL_JOURNAL_DIR:-/var/tmp/longtailtoil-operations}"
operation_id=""
operation_file=""
if [ "$dryrun" -eq 0 ]; then
    [ ! -L "$operation_root" ] || refuse "operation journal root must not be a symlink"
    if [ ! -e "$operation_root" ]; then
        mkdir -m 700 "$operation_root" || refuse "cannot create operation journal root"
    fi
    [ -d "$operation_root" ] && [ ! -L "$operation_root" ] ||
        refuse "operation journal root is not a regular directory"
    [ "$(stat -Lc '%u' "$operation_root" 2>/dev/null || :)" = "0" ] ||
        refuse "operation journal root is not root-owned"
    chmod 700 "$operation_root" || refuse "cannot secure operation journal root"
    operation_file="$(mktemp "$operation_root/import-vm.XXXXXX.journal")" ||
        refuse "cannot create operation journal"
    chmod 600 "$operation_file" || refuse "cannot secure operation journal"
    operation_id="$(basename "$operation_file" .journal)"
    {
        printf 'operation_id=%s\n' "$operation_id"
        printf 'operation=import-vm\n'
        printf 'archive=%s\n' "$archive"
        printf 'source_vmid=%s\n' "$source_vmid"
        printf 'target_vmid=%s\n' "$target"
        printf 'exact=%s\n' "$exact"
    } > "$operation_file"
    ln -sfn "$(basename "$operation_file")" "$operation_root/latest"
fi

say "Archive verified: $archive"
say "Guest: $kind $source_vmid -> $target"
if [ "$dryrun" -eq 1 ]; then
    if [ "$kind" = qemu ]; then
        if [ -n "$storage_override" ]; then printf '[DRYRUN] qmrestore %s %s --storage %s\n' "$payload_rel" "$target" "$storage_override"
        else printf '[DRYRUN] qmrestore %s %s\n' "$payload_rel" "$target"; fi
    else
        if [ -n "$storage_override" ]; then printf '[DRYRUN] pct restore %s %s --storage %s\n' "$target" "$payload_rel" "$storage_override"
        else printf '[DRYRUN] pct restore %s %s\n' "$target" "$payload_rel"; fi
    fi
    printf '[DRYRUN] verify restored config%s and content hashes; restore firewall if present\n' "$( [ "$exact" -eq 1 ] && printf ' exactly' || printf '' )"
    [ "$start_guest" -eq 0 ] || printf '[DRYRUN] start restored guest\n'
    exit 0
fi

if [ "$kind" = qemu ]; then
    need qm; need qmrestore
    if [ -n "$storage_override" ]; then qmrestore "$payload" "$target" --storage "$storage_override"
    else qmrestore "$payload" "$target"; fi
    restored_cfg="/etc/pve/qemu-server/${target}.conf"
else
    need pct
    if [ -n "$storage_override" ]; then pct restore "$target" "$payload" --storage "$storage_override"
    else pct restore "$target" "$payload"; fi
    restored_cfg="/etc/pve/lxc/${target}.conf"
fi
[ -f "$restored_cfg" ] || verify_fail "restore command returned but guest config is missing"

# Restore the guest-scoped firewall file. Cluster-wide ACL/HA/pool/replication
# metadata is intentionally archived only as an audit record, never replayed.
if [ -f "$tmp/ltvm/firewall.fw" ]; then
    mkdir -p /etc/pve/firewall
    cp "$tmp/ltvm/firewall.fw" "/etc/pve/firewall/${target}.fw"
    cmp "$tmp/ltvm/firewall.fw" "/etc/pve/firewall/${target}.fw" >/dev/null 2>&1 ||
        verify_fail "restored guest firewall file differs from archive"
fi

# Call: canonical_config FILE
canonical_config() {
    awk '
      /^[[:space:]]*$/ {next}
      /^#/ {next}
      /^lock:[[:space:]]/ {next}
      /^vmgenid:[[:space:]]/ {next}
      {print}
    ' "$1" | sort
}
if [ "$exact" -eq 1 ]; then
    # Proxmox intentionally regenerates QEMU vmgenid on restore. It is a
    # hypervisor generation marker, not persistent guest configuration that
    # should be forced back to the archived value.
    if [ "$kind" = qemu ] && grep -q '^vmgenid:[[:space:]]' "$tmp/ltvm/config.conf"; then
        restored_vmgenid="$(sed -n 's/^vmgenid:[[:space:]]*//p' "$restored_cfg" | head -n1)"
        [ -n "$restored_vmgenid" ] ||
            verify_fail "restored QEMU config is missing the regenerated vmgenid"
    fi
    canonical_config "$tmp/ltvm/config.conf" > "$tmp/source.canonical"
    canonical_config "$restored_cfg" > "$tmp/restored.canonical"
    if ! cmp "$tmp/source.canonical" "$tmp/restored.canonical" >/dev/null 2>&1; then
        diff_path="/var/tmp/ltvm-config-diff-${target}-${operation_id}.txt"
        diff -u "$tmp/source.canonical" "$tmp/restored.canonical" > "$diff_path" 2>/dev/null || :
        printf 'config_diff=%s\n' "$diff_path" >> "$operation_file"
        verify_fail "restored VM config differs from archived config; guest left stopped; diff: $diff_path"
    fi
fi

# Call: hash_virtual_content PATH
hash_virtual_content() {
    hv_path="$1"; hv_tmp=""; hv_activated=0
    if [ ! -b "$hv_path" ] && [ ! -f "$hv_path" ]; then
        need lvs; need lvchange
        hv_vg="$(lvs --noheadings -o vg_name "$hv_path" 2>/dev/null | awk 'NF{$1=$1;print;exit}')" || return 1
        hv_lv="$(lvs --noheadings -o lv_name "$hv_path" 2>/dev/null | awk 'NF{$1=$1;print;exit}')" || return 1
        [ -n "$hv_vg" ] && [ -n "$hv_lv" ] || return 1
        hv_path="/dev/$hv_vg/$hv_lv"
        say "Temporarily activating inactive restored LV for content verification: $hv_vg/$hv_lv"
        lvchange -ay -K "$hv_vg/$hv_lv" || return 1
        hv_activated=1
        [ -b "$hv_path" ] || { lvchange -an "$hv_vg/$hv_lv" >/dev/null 2>&1 || :; return 1; }
    fi
    if [ -b "$hv_path" ]; then
        if hv_hash="$(sha256sum "$hv_path" | awk '{print $1}')"; then hv_status=0; else hv_status=$?; fi
        if [ "$hv_activated" -eq 1 ]; then lvchange -an "$hv_vg/$hv_lv" || return 1; fi
        [ "$hv_status" -eq 0 ] || return "$hv_status"
        printf '%s\n' "$hv_hash"
        return 0
    fi
    if [ -f "$hv_path" ]; then
        need qemu-img
        hv_tmp="$(mktemp "${TMPDIR:-/var/tmp}/ltvm-hash-raw.XXXXXX")"
        if qemu-img convert -q -O raw "$hv_path" "$hv_tmp" &&
           hv_hash="$(sha256sum "$hv_tmp" | awk '{print $1}')"; then hv_status=0; else hv_status=$?; fi
        rm -f "$hv_tmp"
        [ "$hv_status" -eq 0 ] || return "$hv_status"
        printf '%s\n' "$hv_hash"
        return 0
    fi
    return 1
}

if [ "$verify_content" -eq 1 ] && [ "$kind" = qemu ]; then
    while IFS="$(printf '\t')" read -r slot archived_volid storage size expected_hash hash_mode; do
        [ "$slot" = "slot" ] && continue
        [ -n "$slot" ] || continue
        [ "$expected_hash" != "SKIP" ] || continue
        value="$(qm config "$target" | sed -n "s/^${slot}:[[:space:]]*//p" | head -n1)"
        [ -n "$value" ] || verify_fail "restored slot is missing: $slot"
        volid="${value%%,*}"
        path="$(pvesm path "$volid" 2>/dev/null | head -n1)" || verify_fail "cannot resolve restored $slot volume"
        actual_hash="$(hash_virtual_content "$path")" || verify_fail "cannot hash restored $slot content"
        [ "$actual_hash" = "$expected_hash" ] || verify_fail "content hash mismatch on $slot; guest left stopped"
        say "Verified content hash: $slot"
    done < "$tmp/ltvm/storage-map.tsv"
fi

printf 'verified=1\n' >> "$operation_file"
if [ "$start_guest" -eq 1 ]; then
    if [ "$kind" = qemu ]; then qm start "$target"; else pct start "$target"; fi
    printf 'started=1\n' >> "$operation_file"
else
    say "Restored guest intentionally remains stopped. Use --start only when it is safe to bring it online."
fi
say "Restore verified successfully."
__PROXMOX_LONGTAIL_EMBEDDED_RESTORE__
    chmod 755 "$evm_write_restore_script_path"
}

# evm_cleanup STATUS
# Call: evm_cleanup STATUS
evm_cleanup() {
    evm_cleanup_status="$1"; trap - 0 HUP INT TERM
    rm -rf "${EVM_STAGE:-}" 2>/dev/null || :
    [ -z "${EVM_OUTPUT_TMP:-}" ] || rm -f "$EVM_OUTPUT_TMP" 2>/dev/null || :
    if [ "${EVM_STOPPED_BY_US:-0}" -eq 1 ] && [ "${LEAVE_STOPPED:-0}" -eq 0 ]; then
        warn "Export did not finish while guest was temporarily stopped; attempting to restore its original running state."
        if [ "${EVM_KIND:-qemu}" = qemu ]; then qm start "$VMID" >/dev/null 2>&1 || warn "Could not restart VM $VMID."
        else pct start "$VMID" >/dev/null 2>&1 || warn "Could not restart CT $VMID."; fi
    fi
    [ "$evm_cleanup_status" -eq 0 ] || exit "$evm_cleanup_status"
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
