#!/bin/sh
set -eu

############################################################
# clone-vm-storage-only.sh
# Clone all VM disks into an existing diskless/compatible VM.
############################################################

# setup ARGS...
# Call: setup "$@"
# Initializes user-adjustable defaults and parses arguments.
setup() {
    PROJECT_VERSION="3.7.1"; SCRIPT_VERSION="3.7.1"
    DRYRUN=0; PREFLIGHT=0; QUIET=0; OUTPUT_FORMAT=text; YES=0
    _CVSO_SOURCE_ACTIVATED=0; _CVSO_SOURCE_VG=""; _CVSO_SOURCE_LV=""; CVSO_STAGE_DIR=""; CVSO_STAGE_FILE=""
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
    need_commands qm pvesm lvs lvchange qemu-img cp cmp stat readlink awk sed grep sort mktemp blockdev date comm head find

    require_qemu_vm "$SRC_VM"
    require_qemu_vm "$DST_VM"
    [ "$(guest_status "$DST_VM" qemu)" = stopped ] ||
        refuse "Destination VM must be stopped."
    if [ "$(guest_status "$SRC_VM" qemu)" != stopped ] && [ "$HOT" -eq 0 ]; then
        refuse "Source VM must be stopped unless --hot is explicitly accepted."
    fi

    CVSO_CFG="/etc/pve/qemu-server/${DST_VM}.conf"
    qemu_config_has_snapshots "$CVSO_CFG" &&
        refuse "Destination VM contains snapshot sections; direct config-only unused-reference cleanup is refused."

    CVSO_PLAN="$(mktemp "${TMPDIR:-/tmp}/lt-clone-storage-plan.XXXXXX")"
    CVSO_NEW="$(mktemp "${TMPDIR:-/tmp}/lt-clone-storage-new.XXXXXX")"
    CVSO_VERIFY_ACTIVATIONS="$(mktemp "${TMPDIR:-/tmp}/lt-clone-verify-activations.XXXXXX")"
    : > "$CVSO_PLAN"; : > "$CVSO_NEW"; : > "$CVSO_VERIFY_ACTIVATIONS"
    CVSO_COMPLETE=0
    CVSO_MUTATION_STARTED=0
    CVSO_BACKUP=""

    trap 'cvso_cleanup "$?"' 0
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM

    for CVSO_SLOT in $(qm config "$SRC_VM" | awk -F: '/^(ide|sata|scsi|virtio)[0-9]+:/ {print $1}'); do
        valid_disk_slot "$CVSO_SLOT" || refuse "Unexpected source disk slot: $CVSO_SLOT"
        ! qm config "$DST_VM" | grep -qE "^${CVSO_SLOT}:" ||
            refuse "Destination slot $CVSO_SLOT is occupied."
        CVSO_VALUE="$(disk_value "$SRC_VM" "$CVSO_SLOT")"
        CVSO_VOLID="${CVSO_VALUE%%,*}"
        case "$CVSO_VOLID" in *:*) : ;; *) continue ;; esac
        CVSO_PATH="$(resolve_volid_path "$CVSO_VOLID" || :)"
        [ -n "$CVSO_PATH" ] || refuse "Cannot resolve $CVSO_VOLID."
        CVSO_TARGET_STORAGE="$STORAGE"
        [ -n "$CVSO_TARGET_STORAGE" ] || CVSO_TARGET_STORAGE="${CVSO_VOLID%%:*}"
        pvesm status 2>/dev/null | awk -v s="$CVSO_TARGET_STORAGE" '$1==s{f=1}END{exit !f}' ||
            refuse "Storage unavailable: $CVSO_TARGET_STORAGE"
        printf '%s|%s|%s|%s|%s\n' \
            "$CVSO_SLOT" "$CVSO_VOLID" "$CVSO_PATH" "$CVSO_TARGET_STORAGE" "$CVSO_VALUE" >> "$CVSO_PLAN"
    done

    CVSO_COUNT="$(awk 'END{print NR+0}' "$CVSO_PLAN")"
    [ "$CVSO_COUNT" -gt 0 ] || refuse "No source disks were found."
    info "Disks to clone: $CVSO_COUNT"
    if [ "$(guest_status "$SRC_VM" qemu)" != stopped ]; then
        warn "Hot source copy requested; the source is not quiesced and exact post-copy equality cannot be proven while it may continue changing."
    fi
    [ "$PREFLIGHT" -eq 0 ] || {
        CVSO_COMPLETE=1
        return 0
    }

    journal_begin clone-vm-storage-only
    journal_note source_vm "$SRC_VM"
    journal_note destination_vm "$DST_VM"
    journal_note disk_count "$CVSO_COUNT"

    CVSO_BACKUP="/root/${DST_VM}.conf.before-storage-clone.$(date +%Y%m%d-%H%M%S)"
    if [ "$DRYRUN" -eq 1 ]; then
        print_command cp "$CVSO_CFG" "$CVSO_BACKUP"
        while IFS='|' read -r CVSO_SLOT CVSO_VOLID CVSO_PATH CVSO_TARGET_STORAGE CVSO_VALUE; do
            printf '[DRYRUN] qemu-img convert source %s to an invocation-owned temporary raw staging image\n' "$CVSO_VOLID"
            printf '[DRYRUN] qm importdisk %s <temporary-raw-stage> %s\n' "$DST_VM" "$CVSO_TARGET_STORAGE"
            printf '[DRYRUN VERIFY] compare imported guest-visible bytes with the immutable raw staging image\n'
            printf '[DRYRUN] attach imported volume to %s preserving source disk options; remove generated unusedN reference config-only\n' "$CVSO_SLOT"
        done < "$CVSO_PLAN"
        CVSO_COMPLETE=1
        return 0
    fi

    cp "$CVSO_CFG" "$CVSO_BACKUP"
    CVSO_MUTATION_STARTED=1

    while IFS='|' read -r CVSO_SLOT CVSO_VOLID CVSO_PATH CVSO_TARGET_STORAGE CVSO_VALUE; do
        CVSO_BEFORE="$(mktemp "${TMPDIR:-/tmp}/lt-unused-before.XXXXXX")"
        CVSO_AFTER="$(mktemp "${TMPDIR:-/tmp}/lt-unused-after.XXXXXX")"
        grep -E '^unused[0-9]+:' "$CVSO_CFG" | sort > "$CVSO_BEFORE" || :

        cvso_acquire_source_device "$CVSO_PATH" ||
            verification_failure "Could not make source disk readable: $CVSO_VOLID"

        CVSO_STAGE_DIR="$(mktemp -d "${TMPDIR:-/var/tmp}/lt-clone-storage.XXXXXX")" ||
            verification_failure "Could not create an owned temporary staging directory."
        chmod 700 "$CVSO_STAGE_DIR" ||
            verification_failure "Could not secure temporary staging directory."
        CVSO_STAGE_FILE="$CVSO_STAGE_DIR/source.raw"

        info "Creating temporary raw staging image for $CVSO_SLOT..."
        if [ -b "$CVSO_PATH" ]; then
            qemu-img convert -p -f raw -O raw -S 4k "$CVSO_PATH" "$CVSO_STAGE_FILE" ||
                verification_failure "Could not stage source block device for import: $CVSO_VOLID"
        else
            qemu-img convert -p -O raw -S 4k "$CVSO_PATH" "$CVSO_STAGE_FILE" ||
                verification_failure "Could not stage source image for import: $CVSO_VOLID"
        fi
        [ -f "$CVSO_STAGE_FILE" ] ||
            verification_failure "Raw staging image was not created."
        CVSO_STAGE_SIZE="$(stat -Lc '%s' "$CVSO_STAGE_FILE" 2>/dev/null || :)"
        [ -n "$CVSO_STAGE_SIZE" ] && [ "$CVSO_STAGE_SIZE" -gt 0 ] ||
            verification_failure "Could not determine raw staging image size."

        # The source is no longer needed once the immutable staging image is
        # complete. Restore any activation-skip LV before importing.
        cvso_release_source_device ||
            verification_failure "Could not restore source LV to its original inactive state."

        qm importdisk "$DST_VM" "$CVSO_STAGE_FILE" "$CVSO_TARGET_STORAGE" ||
            verification_failure "qm importdisk failed for staged source $CVSO_VOLID"

        grep -E '^unused[0-9]+:' "$CVSO_CFG" | sort > "$CVSO_AFTER" || :
        CVSO_LINE="$(comm -13 "$CVSO_BEFORE" "$CVSO_AFTER" | head -n1)"
        rm -f "$CVSO_BEFORE" "$CVSO_AFTER"
        [ -n "$CVSO_LINE" ] ||
            verification_failure "Import succeeded but its new unusedN reference could not be identified."

        CVSO_UNUSED="${CVSO_LINE%%:*}"
        valid_unused_slot "$CVSO_UNUSED" ||
            verification_failure "Import produced an unexpected unused reference key: $CVSO_UNUSED"
        CVSO_IMPORTED="$(printf '%s\n' "$CVSO_LINE" |
            sed 's/^[^:]*:[[:space:]]*//;s/,.*//')"
        CVSO_IMPORTED_PATH="$(resolve_volid_path "$CVSO_IMPORTED" || :)"
        [ -n "$CVSO_IMPORTED_PATH" ] ||
            verification_failure "Imported volume cannot be resolved: $CVSO_IMPORTED"

        CVSO_IMPORTED_UUID="$(volid_lv_uuid "$CVSO_IMPORTED" 2>/dev/null || :)"
        CVSO_IMPORTED_CANON="$(readlink -f "$CVSO_IMPORTED_PATH" 2>/dev/null || :)"
        CVSO_IMPORTED_FILEID=""
        [ -n "$CVSO_IMPORTED_UUID" ] ||
            CVSO_IMPORTED_FILEID="$(stat -Lc '%d:%i' "$CVSO_IMPORTED_PATH" 2>/dev/null || :)"
        [ -n "$CVSO_IMPORTED_UUID" ] || [ -n "$CVSO_IMPORTED_FILEID" ] ||
            verification_failure "Could not capture physical identity of imported volume $CVSO_IMPORTED."
        printf '%s|%s|%s|%s\n' \
            "$CVSO_IMPORTED" "$CVSO_IMPORTED_UUID" "$CVSO_IMPORTED_CANON" "$CVSO_IMPORTED_FILEID" >> "$CVSO_NEW"

        prepare_readable_path "$CVSO_IMPORTED_PATH" "$CVSO_VERIFY_ACTIVATIONS" ||
            verification_failure "Imported volume could not be made readable for verification."
        if [ -b "$READABLE_PATH" ]; then
            cmp -n "$CVSO_STAGE_SIZE" "$CVSO_STAGE_FILE" "$READABLE_PATH" ||
                verification_failure "Imported disk bytes differ from the immutable raw staging image: $CVSO_SLOT"
        else
            qemu-img compare -f raw "$CVSO_STAGE_FILE" "$READABLE_PATH" >/dev/null ||
                verification_failure "Imported disk guest-visible bytes differ from the immutable raw staging image: $CVSO_SLOT"
        fi
        restore_tracked_activations "$CVSO_VERIFY_ACTIVATIONS"
        : > "$CVSO_VERIFY_ACTIVATIONS"

        cvso_remove_stage ||
            verification_failure "Could not remove temporary raw staging data after verified import."

        CVSO_NEW_VALUE="$CVSO_IMPORTED${CVSO_VALUE#"$CVSO_VOLID"}"
        qm set "$DST_VM" "--$CVSO_SLOT" "$CVSO_NEW_VALUE" ||
            verification_failure "Could not attach imported disk at $CVSO_SLOT."

        CVSO_TMP="$(mktemp "${TMPDIR:-/tmp}/lt-clone-cfg.XXXXXX")"
        awk -v slot="$CVSO_UNUSED" -F: '$1 != slot {print}' "$CVSO_CFG" > "$CVSO_TMP" ||
            verification_failure "Could not prepare config-only unused-reference cleanup."
        cat "$CVSO_TMP" > "$CVSO_CFG" ||
            verification_failure "Could not remove generated unused reference from destination config."
        rm -f "$CVSO_TMP"

        [ "$(disk_volid "$DST_VM" "$CVSO_SLOT")" = "$CVSO_IMPORTED" ] ||
            verification_failure "Destination slot verification failed: $CVSO_SLOT"
        qm config "$DST_VM" >/dev/null 2>&1 ||
            verification_failure "Destination VM config no longer parses after $CVSO_SLOT."
    done < "$CVSO_PLAN"

    CVSO_COMPLETE=1
    journal_note backup "$CVSO_BACKUP"
    if [ "$HOT" -eq 0 ]; then
        ok "Cloned, import-byte-verified and attached $CVSO_COUNT disk(s) while preserving source slot/options."
    else
        ok "Cloned, import-byte-verified and attached $CVSO_COUNT disk(s) from the explicitly non-quiesced hot source."
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
clone-vm-storage-only.sh $SCRIPT_VERSION (project $PROJECT_VERSION)

USAGE
  clone-vm-storage-only.sh <source-VMID> <destination-VMID> [--storage STORAGE] [--hot] [dryrun|--preflight]

DESCRIPTION
  Copies every active source disk into an existing destination QEMU VM, keeping
  the same device slots and disk options. The destination must be stopped and
  snapshot-free because generated unusedN entries are removed config-only.

  The source must also be stopped unless --hot explicitly accepts a
  non-quiesced copy. Each source is first converted to an invocation-owned
  temporary raw staging image, because qm importdisk requires a regular image
  file rather than an LVM block device. The imported guest-visible bytes are
  verified against that immutable staging image before attachment.

  In --hot mode the source may change while the staging image is created, so
  exact source post-copy equality is intentionally not claimed. Temporary
  staging data is removed on success and failure; set TMPDIR to a filesystem
  with sufficient temporary capacity for the largest source disk.

  Any abnormal exit after the first import restores the destination config from
  its backup. Imported storage is cleaned only when its recorded physical
  identity still matches and no guest physically references it.
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

# cvso_acquire_source_device PATH
# Call: cvso_acquire_source_device PATH
# Makes an inactive LVM source readable for the copy. Activation-skip is
# overridden only for this temporary read window; regular files are unchanged.
cvso_acquire_source_device() {
    cvso_acquire_source_device_path="$1"
    _CVSO_SOURCE_ACTIVATED=0; _CVSO_SOURCE_VG=""; _CVSO_SOURCE_LV=""
    [ -b "$cvso_acquire_source_device_path" ] && return 0
    [ -f "$cvso_acquire_source_device_path" ] && return 0
    _CVSO_SOURCE_VG="$(lvs --noheadings -o vg_name "$cvso_acquire_source_device_path" 2>/dev/null | awk 'NF{$1=$1;print;exit}')" || return 1
    _CVSO_SOURCE_LV="$(lvs --noheadings -o lv_name "$cvso_acquire_source_device_path" 2>/dev/null | awk 'NF{$1=$1;print;exit}')" || return 1
    [ -n "$_CVSO_SOURCE_VG" ] && [ -n "$_CVSO_SOURCE_LV" ] || return 1
    info "Source LV is inactive; temporarily activating it for the storage copy..."
    lvchange -ay -K "$_CVSO_SOURCE_VG/$_CVSO_SOURCE_LV" || return 1
    _CVSO_SOURCE_ACTIVATED=1
    [ -b "$cvso_acquire_source_device_path" ] || {
        cvso_release_source_device >/dev/null 2>&1 || :
        return 1
    }
}

# cvso_release_source_device
# Call: cvso_release_source_device
# Restores a source LV activated by cvso_acquire_source_device to inactive.
cvso_release_source_device() {
    [ "${_CVSO_SOURCE_ACTIVATED:-0}" -eq 1 ] || return 0
    cvso_release_source_device_vg="$_CVSO_SOURCE_VG"
    cvso_release_source_device_lv="$_CVSO_SOURCE_LV"
    if lvchange -an "$cvso_release_source_device_vg/$cvso_release_source_device_lv"; then
        _CVSO_SOURCE_ACTIVATED=0; _CVSO_SOURCE_VG=""; _CVSO_SOURCE_LV=""
        return 0
    fi
    return 1
}


# cvso_remove_stage
# Call: cvso_remove_stage
# Removes only the mktemp-owned raw staging file/directory created by this
# invocation. The directory is removed only when empty.
cvso_remove_stage() {
    if [ -n "${CVSO_STAGE_FILE:-}" ] && [ -f "$CVSO_STAGE_FILE" ]; then
        rm -f -- "$CVSO_STAGE_FILE" || return 1
    fi
    CVSO_STAGE_FILE=""
    if [ -n "${CVSO_STAGE_DIR:-}" ] && [ -d "$CVSO_STAGE_DIR" ]; then
        rmdir -- "$CVSO_STAGE_DIR" || return 1
    fi
    CVSO_STAGE_DIR=""
    return 0
}

# cvso_cleanup STATUS
# Call: cvso_cleanup STATUS
# Restores temporary source activation and removes local plan state.
# cvso_cleanup STATUS
# Restores any temporary source activation first. On an incomplete real clone,
# restores the exact destination config backup and then frees only imported
# volumes whose recorded physical identity still matches and which have no
# remaining physical Proxmox references.
cvso_cleanup() {
    cvso_cleanup_status="$1"
    trap - 0 HUP INT TERM

    if ! cvso_release_source_device; then
        warn "Cleanup could not deactivate temporarily activated source LV: ${_CVSO_SOURCE_VG:-?}/${_CVSO_SOURCE_LV:-?}"
        [ "$cvso_cleanup_status" -ne 0 ] || cvso_cleanup_status=4
    fi
    if [ -f "${CVSO_VERIFY_ACTIVATIONS:-}" ]; then
        restore_tracked_activations "$CVSO_VERIFY_ACTIVATIONS" || :
    fi
    if ! cvso_remove_stage; then
        warn "Could not remove temporary raw staging file/directory."
        [ "$cvso_cleanup_status" -ne 0 ] || cvso_cleanup_status=4
    fi

    if [ "${CVSO_COMPLETE:-0}" -ne 1 ] &&
       [ "${CVSO_MUTATION_STARTED:-0}" -eq 1 ] &&
       [ "${DRYRUN:-0}" -eq 0 ]; then
        if [ -f "${CVSO_BACKUP:-}" ] && [ -f "${CVSO_CFG:-}" ]; then
            cat "$CVSO_BACKUP" > "$CVSO_CFG" ||
                warn "Could not restore destination configuration backup."
        fi

        if [ -f "${CVSO_NEW:-}" ]; then
            while IFS='|' read -r cvso_c_volid cvso_c_uuid cvso_c_path cvso_c_fileid; do
                [ -n "$cvso_c_volid" ] || continue
                [ "$(volid_reference_count "$cvso_c_volid")" -eq 0 ] || {
                    warn "Imported volume is still referenced; preserving $cvso_c_volid."
                    continue
                }
                cvso_c_now="$(resolve_volid_path "$cvso_c_volid" 2>/dev/null || :)"
                [ -n "$cvso_c_now" ] || continue
                cvso_c_safe=0
                if [ -n "$cvso_c_uuid" ]; then
                    [ "$(volid_lv_uuid "$cvso_c_volid" 2>/dev/null || :)" = "$cvso_c_uuid" ] &&
                        cvso_c_safe=1
                elif [ -n "$cvso_c_fileid" ]; then
                    cvso_c_nowcanon="$(readlink -f "$cvso_c_now" 2>/dev/null || :)"
                    cvso_c_nowid="$(stat -Lc '%d:%i' "$cvso_c_now" 2>/dev/null || :)"
                    [ "$cvso_c_nowcanon" = "$cvso_c_path" ] &&
                    [ "$cvso_c_nowid" = "$cvso_c_fileid" ] &&
                        cvso_c_safe=1
                fi
                if [ "$cvso_c_safe" -eq 1 ]; then
                    pvesm free "$cvso_c_volid" >/dev/null 2>&1 ||
                        warn "Could not remove unattached imported volume: $cvso_c_volid"
                else
                    warn "Imported volume identity cannot be proven unchanged; preserving $cvso_c_volid."
                fi
            done < "$CVSO_NEW"
        fi
    fi

    rm -f "${CVSO_PLAN:-}" "${CVSO_NEW:-}" "${CVSO_VERIFY_ACTIVATIONS:-}"
    [ "$cvso_cleanup_status" -eq 0 ] || exit "$cvso_cleanup_status"
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
    SRC_VM=""; DST_VM=""; STORAGE=""; HOT=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h|-\?|/h|/\?|--help) usage; exit 0 ;;
            --version) printf '%s %s (project %s)\n' "$(basename "$0")" "$SCRIPT_VERSION" "$PROJECT_VERSION"; exit 0 ;;
            dryrun|--dryrun|--plan) DRYRUN=1; shift ;;
            --preflight) PREFLIGHT=1; DRYRUN=1; shift ;;
            --no-color) NO_COLOR=1; export NO_COLOR; shift ;;
            --quiet) QUIET=1; shift ;;
            --storage)
                [ "$#" -ge 2 ] || usage_error "--storage requires an ID."
                STORAGE="$2"; shift 2
                ;;
            --hot) HOT=1; shift ;;
            --*) usage_error "Unknown option: $1" ;;
            *)
                if [ -z "$SRC_VM" ]; then
                    SRC_VM="$1"
                elif [ -z "$DST_VM" ]; then
                    DST_VM="$1"
                else
                    usage_error "Too many arguments."
                fi
                shift
                ;;
        esac
    done
    [ -n "$SRC_VM" ] && [ -n "$DST_VM" ] || usage_error "Source and destination VMIDs are required."
    case "$SRC_VM:$DST_VM" in *[!0-9:]*|:*|*:) usage_error "Source and destination VMIDs must be numeric." ;; esac
    [ "$SRC_VM" != "$DST_VM" ] || refuse "Source and destination VMIDs must differ."
    if [ -n "$STORAGE" ]; then
        single_line_value "$STORAGE" || usage_error "Storage ID must be a single-line value."
        case "$STORAGE" in *[!A-Za-z0-9._-]*) usage_error "Invalid Proxmox storage ID: $STORAGE" ;; esac
    fi
}



############################################################
# START
############################################################

setup "$@"
main "$@"
end
