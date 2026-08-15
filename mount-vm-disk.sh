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
    MOUNT_ROOT=""; MODE=""
    parse_arguments "$@"
    check_elevation
}

main() {
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    need_commands qm pvesm lvs
    require_qemu_vm "$VMID"
    mvd_volid="$(disk_volid "$VMID" "$SLOT" || :)"; [ -n "$mvd_volid" ] || die "No disk volume found at $SLOT."
    mvd_path="$(pvesm path "$mvd_volid" 2>/dev/null || :)"; [ -n "$mvd_path" ] || die "Cannot resolve $mvd_volid."
    lvs "$mvd_path" >/dev/null 2>&1 || die "Disk is not LVM-backed: $mvd_path"
    if [ -n "$MOUNT_ROOT" ] && [ -n "$MODE" ]; then exec_project_script "$SCRIPT_DIR/mount-vm-drives.sh" "$mvd_path" "$MOUNT_ROOT" "$MODE"
    elif [ -n "$MOUNT_ROOT" ]; then exec_project_script "$SCRIPT_DIR/mount-vm-drives.sh" "$mvd_path" "$MOUNT_ROOT"
    elif [ -n "$MODE" ]; then exec_project_script "$SCRIPT_DIR/mount-vm-drives.sh" "$mvd_path" "$MODE"
    else exec_project_script "$SCRIPT_DIR/mount-vm-drives.sh" "$mvd_path"; fi
}

end() { :; }

############################################################
# COMMAND LINE
############################################################

usage() { printf 'Usage: %s <vmid> <disk-slot> [mount-root] [--ro|--rw] [dryrun]\n' "$(basename "$0")"; dryrun_help; }

parse_arguments() {
    pa_count=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            dryrun|--dryrun) enable_dryrun ;;
            --ro|--rw) [ -z "$MODE" ] || die "Multiple mount modes supplied."; MODE="$1" ;;
            -h|--help) usage; exit 0 ;;
            --version) printf '%s %s (project %s)\n' "$(basename "$0")" "$SCRIPT_VERSION" "$PROJECT_VERSION"; exit 0 ;;
            *) pa_count=$((pa_count + 1)); case "$pa_count" in 1) VMID="$1" ;; 2) SLOT="$1" ;; 3) MOUNT_ROOT="$1" ;; *) usage >&2; exit 2 ;; esac ;;
        esac
        shift
    done
    [ "$pa_count" -ge 2 ] && [ "$pa_count" -le 3 ] || { usage >&2; exit 2; }
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
