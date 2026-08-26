#!/bin/sh
set -eu

############################################################
# VM drive filesystem mount engine
# One exact slot or all active slots, selected by MOUNT_SCOPE.
############################################################

# setup ARGS...
# Call: setup "$@"
# Initializes user-adjustable defaults and parses arguments.
setup() {
    PROJECT_VERSION="3.7.1"; SCRIPT_VERSION="3.7.1"
    DRYRUN=0; PREFLIGHT=0; QUIET=0; OUTPUT_FORMAT=text; YES=0
    MOUNT_SCOPE="single"
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
    need_commands qm pvesm lvs lvchange partx blkid kpartx mount umount findmnt mkdir rmdir readlink ls awk sed grep sort mktemp cp rm cut
    require_qemu_vm "$VMID"
    [ "$(guest_status "$VMID" qemu)" = "stopped" ] ||
        refuse "VM $VMID must be stopped before host-side filesystem mounting."

    case "$ROOT" in
        /*) : ;;
        *) usage_error "Mount root must be an absolute path." ;;
    esac
    [ "$ROOT" != "/" ] || refuse "Refusing to use / as a mount root."
    single_line_value "$ROOT" || usage_error "Mount root must be a single line."
    case "$ROOT" in *'|'*) usage_error "Mount root must not contain |." ;; esac
    [ "$MODE" = "ro" ] || warn "Read-write mode can modify guest filesystems; use only on intentionally offline data."

    MVD_SLOTS="$(mvd_selected_slots)"
    [ -n "$MVD_SLOTS" ] || refuse "VM $VMID has no active disk slots."
    if [ "$MOUNT_SCOPE" = "single" ]; then
        MVD_SELECTED_VOLID="$(disk_volid "$VMID" "$SLOT" || :)"
        [ -n "$MVD_SELECTED_VOLID" ] || refuse "VM $VMID has no active disk at $SLOT."
    fi

    MVFS_STATE="$ROOT/.longtailtoil-mounts-${VMID}.state"
    [ ! -L "$ROOT" ] || refuse "Mount root must not be a symbolic link: $ROOT"
    if [ -e "$MVFS_STATE" ] || [ -L "$MVFS_STATE" ]; then
        refuse "An ownership state file already exists for this VM/root; unmount it first: $MVFS_STATE"
    fi

    MVFS_COUNT=0
    if [ "$PREFLIGHT" -eq 1 ] || [ "$DRYRUN" -eq 1 ]; then
        info "Mount root: $ROOT"
        for MVFS_SLOT in $MVD_SLOTS; do
            MVFS_VOLID="$(disk_volid "$VMID" "$MVFS_SLOT" || :)"
            [ -n "$MVFS_VOLID" ] || refuse "No active volume exists at $MVFS_SLOT."
            MVFS_PATH="$(resolve_volid_path "$MVFS_VOLID" || :)"
            [ -n "$MVFS_PATH" ] || refuse "Cannot resolve $MVFS_SLOT ($MVFS_VOLID) to a local path."
            MVFS_ID="$(lvm_identity "$MVFS_PATH" || :)"
            if [ -n "$MVFS_ID" ] && [ ! -b "$MVFS_PATH" ]; then
                MVFS_VG="$(printf '%s\n' "$MVFS_ID" | cut -d'|' -f1)"
                MVFS_LV="$(printf '%s\n' "$MVFS_ID" | cut -d'|' -f2)"
                print_command lvchange -ay -K "$MVFS_VG/$MVFS_LV"
                warn "$MVFS_SLOT is inactive; filesystem discovery is deferred because dry-run/preflight never activates it."
                continue
            fi
            [ -b "$MVFS_PATH" ] || refuse "$MVFS_SLOT does not resolve to a local block device: $MVFS_PATH"

            MVFS_PARTS="$(partx --show --noheadings -o NR "$MVFS_PATH" 2>/dev/null | awk 'NF{print $1}')"
            if [ -z "$MVFS_PARTS" ]; then
                MVFS_FS="$(blkid -p -o value -s TYPE "$MVFS_PATH" 2>/dev/null || :)"
                [ -n "$MVFS_FS" ] || continue
                MVFS_DIR="$ROOT/$MVFS_SLOT/whole"
                print_command mkdir -p "$MVFS_DIR"
                print_command mount -o "$MODE" "$MVFS_PATH" "$MVFS_DIR"
                MVFS_COUNT=$((MVFS_COUNT + 1))
            else
                MVFS_MAPS="$(kpartx -l "$MVFS_PATH" 2>/dev/null | awk '{print $1}')"
                [ -n "$MVFS_MAPS" ] || refuse "Could not derive partition mapper names for $MVFS_SLOT."
                print_command kpartx -av "$MVFS_PATH"
                for MVFS_MAP in $MVFS_MAPS; do
                    MVFS_PART="$(printf '%s\n' "$MVFS_MAP" | sed -n 's/.*p\([0-9][0-9]*\)$/\1/p')"
                    [ -n "$MVFS_PART" ] || continue
                    MVFS_DIR="$ROOT/$MVFS_SLOT/part$MVFS_PART"
                    print_command mkdir -p "$MVFS_DIR"
                    printf '[DRYRUN] mount recognizable filesystem from /dev/mapper/%s at %s in %s mode\n' "$MVFS_MAP" "$MVFS_DIR" "$MODE"
                    MVFS_COUNT=$((MVFS_COUNT + 1))
                done
            fi
        done
        ok "Planned up to $MVFS_COUNT recognizable filesystem mount(s) beneath $ROOT."
        dryrun_verify "Filesystem-role detection would inspect only the planned invocation-owned mount targets"
        return 0
    fi

    MVFS_ROOT_CREATED=0
    if [ ! -e "$ROOT" ]; then
        mkdir -p "$ROOT"
        MVFS_ROOT_CREATED=1
    fi
    [ -d "$ROOT" ] || refuse "Mount root is not a directory: $ROOT"
    MVFS_ROOT_OWNER="$(ls -nd "$ROOT" 2>/dev/null | awk '{print $3}')"
    [ "$MVFS_ROOT_OWNER" = "0" ] || refuse "Mount root must be owned by root: $ROOT"

    MVFS_OWNED="$(mktemp "${TMPDIR:-/var/tmp}/lt-mount-owned.XXXXXX")"
    MVFS_ACTIVATIONS="$(mktemp "${TMPDIR:-/var/tmp}/lt-mount-activations.XXXXXX")"
    : > "$MVFS_ACTIVATIONS"
    {
        printf 'VMID|%s\n' "$VMID"
        printf 'ROOT|%s\n' "$ROOT"
        printf 'ROOT_CREATED|%s\n' "$MVFS_ROOT_CREATED"
        printf 'SCOPE|%s|%s\n' "$MOUNT_SCOPE" "${SLOT:-}"
    } > "$MVFS_OWNED"
    MVFS_COMPLETE=0
    trap 'mvfs_cleanup "$?"' 0
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM

    for MVFS_SLOT in $MVD_SLOTS; do
        MVFS_VOLID="$(disk_volid "$VMID" "$MVFS_SLOT" || :)"
        [ -n "$MVFS_VOLID" ] || refuse "No active volume exists at $MVFS_SLOT."
        MVFS_RAW_PATH="$(resolve_volid_path "$MVFS_VOLID" || :)"
        [ -n "$MVFS_RAW_PATH" ] || refuse "Cannot resolve $MVFS_SLOT ($MVFS_VOLID)."

        if prepare_readable_path "$MVFS_RAW_PATH" "$MVFS_ACTIVATIONS"; then
            MVFS_PATH="$READABLE_PATH"
        else
            refuse "Cannot make $MVFS_SLOT backing volume readable without losing ownership certainty."
        fi
        [ -b "$MVFS_PATH" ] || refuse "$MVFS_SLOT does not resolve to a local block device: $MVFS_PATH"

        MVFS_CANON_PATH="$(readlink -f "$MVFS_PATH" 2>/dev/null || :)"
        [ -n "$MVFS_CANON_PATH" ] || refuse "Cannot canonicalize source path: $MVFS_PATH"
        MVFS_PARTS="$(partx --show --noheadings -o NR "$MVFS_PATH" 2>/dev/null | awk 'NF{print $1}')"

        if [ -z "$MVFS_PARTS" ]; then
            MVFS_FS="$(blkid -p -o value -s TYPE "$MVFS_PATH" 2>/dev/null || :)"
            [ -n "$MVFS_FS" ] || { warn "$MVFS_SLOT has no recognizable direct filesystem."; continue; }
            MVFS_DIR="$ROOT/$MVFS_SLOT/whole"
            mvfs_prepare_target "$MVFS_DIR"
            mount -o "$MODE" "$MVFS_PATH" "$MVFS_DIR"
            mvfs_verify_mount "$MVFS_PATH" "$MVFS_DIR"
            printf 'MOUNT|%s|%s\n' "$MVFS_CANON_PATH" "$MVFS_DIR" >> "$MVFS_OWNED"
            MVFS_COUNT=$((MVFS_COUNT + 1))
            info "$MVFS_SLOT whole ($MVFS_FS) -> $MVFS_DIR"
            continue
        fi

        MVFS_MAPS="$(kpartx -l "$MVFS_PATH" 2>/dev/null | awk '{print $1}')"
        [ -n "$MVFS_MAPS" ] || refuse "Could not derive partition mapper names for $MVFS_SLOT."
        for MVFS_MAP in $MVFS_MAPS; do
            [ ! -e "/dev/mapper/$MVFS_MAP" ] && [ ! -L "/dev/mapper/$MVFS_MAP" ] ||
                refuse "Mapper already exists before this invocation; ownership is ambiguous: /dev/mapper/$MVFS_MAP"
        done
        kpartx -av "$MVFS_PATH"
        printf 'MAPPER|%s\n' "$MVFS_CANON_PATH" >> "$MVFS_OWNED"

        for MVFS_MAP in $MVFS_MAPS; do
            MVFS_DEV="/dev/mapper/$MVFS_MAP"
            [ -b "$MVFS_DEV" ] || verification_failure "Expected mapper device did not appear: $MVFS_DEV"
            MVFS_FS="$(blkid -p -o value -s TYPE "$MVFS_DEV" 2>/dev/null || :)"
            [ -n "$MVFS_FS" ] || continue
            MVFS_PART="$(printf '%s\n' "$MVFS_MAP" | sed -n 's/.*p\([0-9][0-9]*\)$/\1/p')"
            [ -n "$MVFS_PART" ] || continue
            MVFS_DIR="$ROOT/$MVFS_SLOT/part$MVFS_PART"
            mvfs_prepare_target "$MVFS_DIR"
            mount -o "$MODE" "$MVFS_DEV" "$MVFS_DIR"
            mvfs_verify_mount "$MVFS_DEV" "$MVFS_DIR"
            MVFS_CANON_DEV="$(readlink -f "$MVFS_DEV" 2>/dev/null || :)"
            [ -n "$MVFS_CANON_DEV" ] || verification_failure "Cannot canonicalize mapper device: $MVFS_DEV"
            printf 'MOUNT|%s|%s\n' "$MVFS_CANON_DEV" "$MVFS_DIR" >> "$MVFS_OWNED"
            MVFS_COUNT=$((MVFS_COUNT + 1))
            info "$MVFS_SLOT part$MVFS_PART ($MVFS_FS) -> $MVFS_DIR"
        done
    done

    [ "$MVFS_COUNT" -gt 0 ] || refuse "No recognizable filesystems were mounted from the selected disk set."

    while IFS='|' read -r MVFS_AVG MVFS_ALV MVFS_AUUID; do
        [ -n "$MVFS_AVG" ] || continue
        printf 'ACTIVATE|%s|%s|%s\n' "$MVFS_AVG" "$MVFS_ALV" "$MVFS_AUUID" >> "$MVFS_OWNED"
    done < "$MVFS_ACTIVATIONS"

    mvd_classify_owned_mounts "$MVFS_OWNED"

    cp "$MVFS_OWNED" "$MVFS_STATE"
    chmod 600 "$MVFS_STATE"
    MVFS_COMPLETE=1
    trap - 0 HUP INT TERM
    rm -f "$MVFS_OWNED" "$MVFS_ACTIVATIONS"
    ok "Mounted $MVFS_COUNT recognizable filesystem(s) beneath $ROOT."
    info "Ownership state: $MVFS_STATE"
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
    if [ "$MOUNT_SCOPE" = "single" ]; then
        cat <<EOF
mount-vm-drive.sh $SCRIPT_VERSION (project $PROJECT_VERSION)

USAGE
  mount-vm-drive.sh <VMID> <disk-slot> [mount-root] [--ro|--rw] [dryrun|--preflight]

DESCRIPTION
  Mounts recognizable filesystems from one exact active disk slot of a stopped
  QEMU VM beneath <mount-root>/<slot>/. The default mount root is
  \$PWD/vm-<VMID>. Read-only is the default. The command resolves the Proxmox
  volume to its local block backing, temporarily activates an inactive LVM LV
  with activation-skip preserved when needed, refuses pre-existing mapper
  ownership, verifies every exact mounted source, records only resources owned
  by this invocation, and rolls back partial failures.

  Mounted filesystems are classified as likely Linux root, Windows root, EFI,
  or recovery filesystems when recognizable. The strongest Linux-root candidate
  is reported. Use unmount-all-vm-drives.sh with the same VMID and mount root
  to remove the invocation-owned mounts, mappings, and temporary activations.

ARGUMENTS
  VMID         Numeric local QEMU VM ID. The VM must be stopped.
  disk-slot    Exact ideN, sataN, scsiN, or virtioN active disk slot.
  mount-root   Absolute destination root. Default: \$PWD/vm-<VMID>.

OPTIONS
  --ro         Mount filesystems read-only (default).
  --rw         Mount filesystems read-write.
EOF
    else
        cat <<EOF
mount-all-vm-drives.sh $SCRIPT_VERSION (project $PROJECT_VERSION)

USAGE
  mount-all-vm-drives.sh <VMID> [mount-root] [--ro|--rw] [dryrun|--preflight]

DESCRIPTION
  Mounts recognizable filesystems from every active block-backed disk of a
  stopped QEMU VM beneath <mount-root>/<slot>/. The default mount root is
  \$PWD/vm-<VMID>. Read-only is the default. Each disk uses the same resolver,
  activation, partition mapping, exact mount verification, ownership tracking,
  filesystem-role classification, and rollback logic as mount-vm-drive.sh.

  Pre-existing mapper ownership is refused. Partial failures are rolled back.
  The strongest Linux-root candidate across all mounted filesystems is reported.
  Use unmount-all-vm-drives.sh with the same VMID and mount root for cleanup.

ARGUMENTS
  VMID         Numeric local QEMU VM ID. The VM must be stopped.
  mount-root   Absolute destination root. Default: \$PWD/vm-<VMID>.

OPTIONS
  --ro         Mount filesystems read-only (default).
  --rw         Mount filesystems read-write.
EOF
    fi
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
    VMID=""; SLOT=""; ROOT=""; MODE=ro
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h|-\?|/h|/\?|--help) usage; exit 0 ;;
            --version) printf '%s %s (project %s)\n' "$(basename "$0")" "$SCRIPT_VERSION" "$PROJECT_VERSION"; exit 0 ;;
            dryrun|--dryrun|--plan) DRYRUN=1; shift ;;
            --preflight) PREFLIGHT=1; DRYRUN=1; shift ;;
            --no-color) NO_COLOR=1; export NO_COLOR; shift ;;
            --quiet) QUIET=1; shift ;;
            --ro) MODE=ro; shift ;;
            --rw) MODE=rw; shift ;;
            --*) usage_error "Unknown option: $1" ;;
            *)
                if [ "$MOUNT_SCOPE" = "single" ]; then
                    if [ -z "$VMID" ]; then VMID="$1"
                    elif [ -z "$SLOT" ]; then SLOT="$1"
                    elif [ -z "$ROOT" ]; then ROOT="$1"
                    else usage_error "Too many positional arguments."
                    fi
                else
                    if [ -z "$VMID" ]; then VMID="$1"
                    elif [ -z "$ROOT" ]; then ROOT="$1"
                    else usage_error "Too many positional arguments."
                    fi
                fi
                shift
                ;;
        esac
    done

    [ -n "$VMID" ] || usage_error "VMID is required."
    case "$VMID" in *[!0-9]*) usage_error "VMID must be numeric." ;; esac

    if [ "$MOUNT_SCOPE" = "single" ]; then
        [ -n "$SLOT" ] || usage_error "An exact disk slot is required."
        valid_disk_slot "$SLOT" || usage_error "Disk slot must be an exact ideN, sataN, scsiN, or virtioN slot within Proxmox limits."
    fi

    if [ -z "$ROOT" ]; then ROOT="$PWD/vm-$VMID"; fi
}



# mvd_selected_slots
# Call: mvd_selected_slots
# Prints the exact slot requested by mount-vm-drive.sh or every active disk slot
# for mount-all-vm-drives.sh. The output is consumed only after VM validation.
mvd_selected_slots() {
    if [ "$MOUNT_SCOPE" = "single" ]; then
        printf '%s\n' "$SLOT"
        return 0
    fi
    qm config "$VMID" | awk -F: '/^(ide|sata|scsi|virtio)[0-9]+:/ {print $1}' | sort
}

# mvd_classify_owned_mounts STATE_FILE
# Call: mvd_classify_owned_mounts "$MVFS_OWNED"
# Classifies invocation-owned mounted filesystems and reports the strongest
# Linux-root candidate without changing mounted data.
mvd_classify_owned_mounts() {
    mvd_classify_file="$1"
    section_title_printed=0
    mvd_classify_found=0
    mvd_classify_best=""
    mvd_classify_best_score=-1

    while IFS='|' read -r mvd_classify_kind mvd_classify_source mvd_classify_target; do
        [ "$mvd_classify_kind" = "MOUNT" ] || continue
        [ -d "$mvd_classify_target" ] || continue
        [ "$(findmnt -rn -M "$mvd_classify_target" -o TARGET 2>/dev/null || :)" = "$mvd_classify_target" ] || continue

        if [ "$section_title_printed" -eq 0 ]; then
            info "Likely filesystem roles:"
            section_title_printed=1
        fi

        mvd_classify_role=""
        mvd_classify_score=0

        if [ -d "$mvd_classify_target/Windows/System32" ]; then
            mvd_classify_role="Windows root"
        fi

        if [ -d "$mvd_classify_target/etc" ] &&
           { [ -d "$mvd_classify_target/usr" ] || [ -d "$mvd_classify_target/bin" ]; }; then
            mvd_classify_role="${mvd_classify_role:+$mvd_classify_role, }Linux root"
            mvd_classify_score=50
            [ ! -f "$mvd_classify_target/etc/os-release" ] || mvd_classify_score=$((mvd_classify_score + 20))
            [ ! -f "$mvd_classify_target/usr/lib/os-release" ] || mvd_classify_score=$((mvd_classify_score + 15))
            [ ! -e "$mvd_classify_target/bin/sh" ] || mvd_classify_score=$((mvd_classify_score + 10))
            [ ! -d "$mvd_classify_target/var" ] || mvd_classify_score=$((mvd_classify_score + 5))
            [ ! -d "$mvd_classify_target/home" ] || mvd_classify_score=$((mvd_classify_score + 2))
            if [ "$mvd_classify_score" -gt "$mvd_classify_best_score" ]; then
                mvd_classify_best_score="$mvd_classify_score"
                mvd_classify_best="$mvd_classify_target"
            fi
        fi

        [ ! -d "$mvd_classify_target/EFI" ] ||
            mvd_classify_role="${mvd_classify_role:+$mvd_classify_role, }EFI system"
        if [ -d "$mvd_classify_target/Recovery" ] ||
           [ -d "$mvd_classify_target/Recovery/WindowsRE" ]; then
            mvd_classify_role="${mvd_classify_role:+$mvd_classify_role, }Recovery"
        fi

        if [ -n "$mvd_classify_role" ]; then
            printf '  %-48s %s\n' "$mvd_classify_target" "$mvd_classify_role"
            mvd_classify_found=1
        fi
    done < "$mvd_classify_file"

    if [ "$mvd_classify_found" -eq 0 ]; then
        warn "No recognizable filesystem role was confidently identified; all owned mount points remain available beneath $ROOT."
    fi
    if [ -n "$mvd_classify_best" ]; then
        printf '\nMost likely Linux root: %s\n' "$mvd_classify_best"
    else
        warn "No Linux root filesystem was confidently identified."
    fi
}

# mvfs_prepare_target TARGET
# Creates a mount target only when it is not already mounted and contains no data.
# Call: mvfs_prepare_target TARGET
# Call: mvfs_prepare_target TARGET
# Verifies an exact target is unmounted/empty and records only directories this
# invocation creates so cleanup never removes a pre-existing mount-root tree.
mvfs_prepare_target() {
    mvfs_prepare_target_target="$1"
    ! findmnt -rn -M "$mvfs_prepare_target_target" >/dev/null 2>&1 ||
        refuse "Target is already mounted: $mvfs_prepare_target_target"

    mvfs_prepare_target_parent="${mvfs_prepare_target_target%/*}"
    [ ! -L "$mvfs_prepare_target_parent" ] ||
        refuse "Target parent must not be a symlink: $mvfs_prepare_target_parent"
    [ ! -L "$mvfs_prepare_target_target" ] ||
        refuse "Mount target must not be a symlink: $mvfs_prepare_target_target"
    if [ ! -d "$mvfs_prepare_target_parent" ]; then
        mkdir "$mvfs_prepare_target_parent"
        printf 'DIR|%s\n' "$mvfs_prepare_target_parent" >> "$MVFS_OWNED"
    fi

    if [ -d "$mvfs_prepare_target_target" ]; then
        [ -z "$(find "$mvfs_prepare_target_target" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ] ||
            refuse "Target directory is not empty: $mvfs_prepare_target_target"
    else
        mkdir "$mvfs_prepare_target_target"
        printf 'DIR|%s\n' "$mvfs_prepare_target_target" >> "$MVFS_OWNED"
    fi
}

# mvfs_verify_mount SOURCE TARGET
# Proves TARGET is an exact mountpoint backed by the canonical selected SOURCE.
# Call: mvfs_verify_mount SOURCE TARGET
mvfs_verify_mount() {
    mvfs_verify_mount_source="$1"; mvfs_verify_mount_target="$2"
    mvfs_verify_mount_actual="$(findmnt -rn -M "$mvfs_verify_mount_target" -o SOURCE 2>/dev/null | head -n1 || :)"
    [ -n "$mvfs_verify_mount_actual" ] || verification_failure "Expected mountpoint is absent: $mvfs_verify_mount_target"
    mvfs_verify_mount_expected_canon="$(readlink -f "$mvfs_verify_mount_source" 2>/dev/null || :)"
    mvfs_verify_mount_actual_canon="$(readlink -f "$mvfs_verify_mount_actual" 2>/dev/null || :)"
    [ -n "$mvfs_verify_mount_expected_canon" ] &&
        [ "$mvfs_verify_mount_actual_canon" = "$mvfs_verify_mount_expected_canon" ] ||
        verification_failure "Mounted source does not match selected device at $mvfs_verify_mount_target"
}

# mvfs_cleanup STATUS
# Rolls back only mounts and mapper devices recorded as created by this invocation.
# Call: mvfs_cleanup STATUS
mvfs_cleanup() {
    mvfs_cleanup_status="$1"
    trap - 0 HUP INT TERM
    if [ "${MVFS_COMPLETE:-0}" -ne 1 ] && [ -f "${MVFS_OWNED:-}" ]; then
        warn "Mount workflow did not complete; rolling back invocation-owned resources."
        awk -F'|' '$1=="MOUNT"{line[NR]=$0} END{for(i=NR;i>=1;i--)if(line[i]!="")print line[i]}' "$MVFS_OWNED" |
        while IFS='|' read -r mvfs_cleanup_kind mvfs_cleanup_source mvfs_cleanup_target; do
            [ "$mvfs_cleanup_kind" = "MOUNT" ] || continue
            mvfs_cleanup_actual="$(findmnt -rn -M "$mvfs_cleanup_target" -o SOURCE 2>/dev/null | head -n1 || :)"
            if [ -n "$mvfs_cleanup_actual" ] && [ "$(readlink -f "$mvfs_cleanup_actual" 2>/dev/null || :)" = "$mvfs_cleanup_source" ]; then
                umount "$mvfs_cleanup_target" >/dev/null 2>&1 || warn "Could not roll back mount: $mvfs_cleanup_target"
            fi
        done
        awk -F'|' '$1=="MAPPER"{line[NR]=$0} END{for(i=NR;i>=1;i--)if(line[i]!="")print line[i]}' "$MVFS_OWNED" |
        while IFS='|' read -r mvfs_cleanup_kind mvfs_cleanup_source; do
            [ "$mvfs_cleanup_kind" = "MAPPER" ] || continue
            kpartx -d "$mvfs_cleanup_source" >/dev/null 2>&1 || warn "Could not roll back partition mappings: $mvfs_cleanup_source"
        done
        restore_tracked_activations "${MVFS_ACTIVATIONS:-}"
    fi
    if [ -f "${MVFS_OWNED:-}" ]; then
        awk -F'|' '$1=="DIR"{line[NR]=$0} END{for(i=NR;i>=1;i--)if(line[i]!="")print line[i]}' "$MVFS_OWNED" |
        while IFS='|' read -r mvfs_cleanup_kind mvfs_cleanup_dir; do
            [ "$mvfs_cleanup_kind" = "DIR" ] || continue
            rmdir "$mvfs_cleanup_dir" 2>/dev/null || :
        done
    fi
    rm -f "${MVFS_OWNED:-}" "${MVFS_ACTIVATIONS:-}" 2>/dev/null || :
    if [ "${MVFS_ROOT_CREATED:-0}" -eq 1 ]; then
        rmdir "$ROOT" 2>/dev/null || :
    fi
    [ "$mvfs_cleanup_status" -eq 0 ] || exit "$mvfs_cleanup_status"
    return 0
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
