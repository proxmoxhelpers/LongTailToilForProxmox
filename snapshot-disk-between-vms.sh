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
    check_elevation
}

main() {
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    need_commands qm pvesm lvs
    require_qemu_vm "$SRC_VM"; require_qemu_vm "$DST_VM"
    sbv_volid="$(disk_volid "$SRC_VM" "$SLOT" || :)"; [ -n "$sbv_volid" ] || die "No disk volume found at $SLOT."
    sbv_path="$(resolve_volid_path "$sbv_volid" || :)"; [ -n "$sbv_path" ] || die "Cannot resolve $sbv_volid."
    lvs "$sbv_path" >/dev/null 2>&1 || die "Source disk is not LVM-backed: $sbv_path"
    exec_project_script "$SCRIPT_DIR/create-disk-snapshot-and-add-to-vm.sh" "$sbv_path" "$DST_VM"
}

end() { :; }

############################################################
# COMMAND LINE
############################################################

usage() { printf 'Usage: %s <source-vmid> <source-slot> <destination-vmid> [dryrun]\n' "$(basename "$0")"; dryrun_help; }

parse_arguments() {
    pa_count=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            dryrun|--dryrun) enable_dryrun ;;
            -h|--help) usage; exit 0 ;;
            --version) printf '%s %s (project %s)\n' "$(basename "$0")" "$SCRIPT_VERSION" "$PROJECT_VERSION"; exit 0 ;;
            *) pa_count=$((pa_count + 1)); case "$pa_count" in 1) SRC_VM="$1" ;; 2) SLOT="$1" ;; 3) DST_VM="$1" ;; *) usage >&2; exit 2 ;; esac ;;
        esac
        shift
    done
    [ "$pa_count" -eq 3 ] || { usage >&2; exit 2; }
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
