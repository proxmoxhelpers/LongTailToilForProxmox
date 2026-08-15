#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/common.sh"
. "$SCRIPT_DIR/lib/dryrun.sh"

############################################################
# SETUP / MAIN / END
############################################################

setup() {
    define_colours
    PROJECT_VERSION="3.0.1"; SCRIPT_VERSION="3.0.0"
    TARGET_MODE="list"; TARGET_FILE=""; TARGET_ARGS=""; ALL_UNUSED_FILE=""
    parse_arguments "$@"
    check_elevation
}

main() {
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    install_temp_cleanup
    need_commands qm pvesm mktemp
    require_qemu_vm "$VMID"
    collect_unused
    [ "$TARGET_MODE" = "list" ] && { list_unused; return 0; }
    require_guest_stopped "$VMID"
    build_targets
    delete_targets
}

end() {
    [ -z "${ALL_UNUSED_FILE:-}" ] || rm -f "$ALL_UNUSED_FILE"
    [ -z "${TARGET_FILE:-}" ] || rm -f "$TARGET_FILE"
    dryrun_summary
}

############################################################
# COMMAND LINE
############################################################

usage() { printf 'Usage: %s <vmid> [unusedN ... | --all] [dryrun]\n' "$(basename "$0")"; dryrun_help; }

parse_arguments() {
    pa_count=0; pa_seen_vmid=false
    while [ "$#" -gt 0 ]; do
        case "$1" in
            dryrun|--dryrun) enable_dryrun ;;
            -h|--help) usage; exit 0 ;;
            --version) printf '%s %s (project %s)\n' "$(basename "$0")" "$SCRIPT_VERSION" "$PROJECT_VERSION"; exit 0 ;;
            *)
                if [ "$pa_seen_vmid" = false ]; then VMID="$1"; pa_seen_vmid=true
                else TARGET_ARGS="${TARGET_ARGS}${TARGET_ARGS:+
}$1"; TARGET_MODE="explicit"; fi
                ;;
        esac
        shift
    done
    [ "$pa_seen_vmid" = true ] || { usage >&2; exit 2; }
}

############################################################
# HIGH LEVEL TASKS
############################################################

# collect_unused
# Collects the VM's current unusedN keys into a temporary list.
collect_unused() {
    ALL_UNUSED_FILE="$(mktemp)" || die "Unable to create unused-disk list."
    register_temp_file "$ALL_UNUSED_FILE"
    qm config "$VMID" | awk -F: '$1 ~ /^unused[0-9]+$/ {print $1}' > "$ALL_UNUSED_FILE"
}

# list_unused
# Prints each currently configured unusedN entry without modifying the VM.
list_unused() {
    if [ ! -s "$ALL_UNUSED_FILE" ]; then info "VM $VMID has no unused disks."; return 0; fi
    while IFS= read -r lu_key; do printf '%s: %s\n' "$lu_key" "$(disk_value "$VMID" "$lu_key")"; done < "$ALL_UNUSED_FILE"
}

# build_targets
# Builds the exact unusedN deletion list from explicit keys or --all.
build_targets() {
    TARGET_FILE="$(mktemp)" || die "Unable to create target list."
    register_temp_file "$TARGET_FILE"
    if printf '%s\n' "$TARGET_ARGS" | grep -Fx -- '--all' >/dev/null 2>&1; then
        [ "$(printf '%s\n' "$TARGET_ARGS" | awk 'NF {n++} END {print n+0}')" -eq 1 ] || die "--all cannot be combined with explicit unusedN keys."
        cat "$ALL_UNUSED_FILE" > "$TARGET_FILE"
    else
        printf '%s\n' "$TARGET_ARGS" > "$TARGET_FILE"
    fi
    [ -s "$TARGET_FILE" ] || { info "Nothing to delete."; return 0; }
}

# delete_targets
# Validates and deletes each selected unused disk while refusing shared-volume references.
delete_targets() {
    [ -s "$TARGET_FILE" ] || return 0
    dt_config="/etc/pve/qemu-server/${VMID}.conf"
    while IFS= read -r dt_key; do
        case "$dt_key" in unused[0-9]*) ;; *) die "Invalid unused disk key: $dt_key" ;; esac
        dt_volid="$(disk_volid "$VMID" "$dt_key" || :)"; [ -n "$dt_volid" ] || die "$dt_key does not exist."
        dt_others="$(other_volume_references "$dt_volid" "$dt_config")"
        [ -z "$dt_others" ] || { printf '%s\n' "$dt_others"; die "$dt_volid is referenced by another guest."; }
        info "Deleting $dt_key -> $dt_volid"
        dryrun_cmd pvesm free "$dt_volid"
        dryrun_cmd qm set "$VMID" --delete "$dt_key"
        ok "Deleted $dt_key."
        if dryrun_enabled; then dryrun_verify "$dt_key would be removed from VM $VMID"; fi
    done < "$TARGET_FILE"
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
