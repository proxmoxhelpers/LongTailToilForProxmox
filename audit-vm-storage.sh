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
    parse_arguments "$@"
}

main() {
    need_commands pvesm readlink awk paste mktemp
    locate_config
    audit_storage
}

end() { dryrun_summary; }

############################################################
# COMMAND LINE
############################################################

usage() { printf 'Usage: %s <vmid> [dryrun]\n' "$(basename "$0")"; dryrun_help; }

parse_arguments() {
    pa_count=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            dryrun|--dryrun) enable_dryrun ;;
            -h|--help) usage; exit 0 ;;
            --version) printf '%s %s (project %s)\n' "$(basename "$0")" "$SCRIPT_VERSION" "$PROJECT_VERSION"; exit 0 ;;
            *) pa_count=$((pa_count + 1)); [ "$pa_count" -eq 1 ] && VMID="$1" || { usage >&2; exit 2; } ;;
        esac
        shift
    done
    [ "$pa_count" -eq 1 ] || { usage >&2; exit 2; }
}

############################################################
# HIGH LEVEL TASKS
############################################################

# locate_config
# Resolves VMID to one local QEMU/LXC configuration file.
locate_config() {
    CONFIG=""
    [ ! -f "/etc/pve/qemu-server/${VMID}.conf" ] || CONFIG="/etc/pve/qemu-server/${VMID}.conf"
    [ -n "$CONFIG" ] || [ ! -f "/etc/pve/lxc/${VMID}.conf" ] || CONFIG="/etc/pve/lxc/${VMID}.conf"
    [ -n "$CONFIG" ] || die "No local VM/CT config found for VMID $VMID."
}

# audit_storage
# Verifies every configured storage volume resolves and is not shared.
audit_storage() {
    as_refs="$(mktemp)" || die "Unable to create audit reference file."
    trap 'rm -f "$as_refs"' 0 HUP INT TERM
    config_volume_references "$CONFIG" > "$as_refs"
    FAILED=0; COUNT=0
    printf '%-10s %-40s %-7s %-40s %s\n' SLOT VOLUME STATUS PATH OTHER_REFS
    while IFS='|' read -r as_slot as_volid; do
        [ -n "$as_volid" ] || continue
        COUNT=$((COUNT + 1))
        as_path="$(pvesm path "$as_volid" 2>/dev/null || :)"
        if [ -z "$as_path" ]; then
            printf '%-10s %-40s %-7s %-40s %s\n' "$as_slot" "$as_volid" FAIL - -
            FAILED=1
            continue
        fi
        as_other="$(other_volume_references "$as_volid" "$CONFIG" | paste -sd, -)"
        printf '%-10s %-40s %-7s %-40s %s\n' "$as_slot" "$as_volid" OK "$as_path" "${as_other:--}"
        if [ -n "$as_other" ]; then warn "$as_volid is referenced by another guest."; FAILED=1; fi
    done < "$as_refs"
    rm -f "$as_refs"; trap - 0 HUP INT TERM
    [ "$COUNT" -gt 0 ] || info "No storage-backed guest volumes are configured."
    [ "$FAILED" -eq 0 ] && ok "Storage audit passed." || die "Storage audit found problems."
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
