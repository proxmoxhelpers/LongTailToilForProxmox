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
    DEST_VG=""
    parse_arguments "$@"
    check_elevation
}

main() {
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    if [ -n "$DEST_VG" ]; then exec_project_script "$SCRIPT_DIR/copy-disk-between-vms.sh" "$VMID" "$SLOT" "$VMID" "$DEST_VG"
    else exec_project_script "$SCRIPT_DIR/copy-disk-between-vms.sh" "$VMID" "$SLOT" "$VMID"; fi
}

end() { :; }

############################################################
# COMMAND LINE
############################################################

usage() { printf 'Usage: %s <vmid> <disk-slot> [destination-vg] [dryrun]\n' "$(basename "$0")"; dryrun_help; }

parse_arguments() {
    pa_count=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            dryrun|--dryrun) enable_dryrun ;;
            -h|--help) usage; exit 0 ;;
            --version) printf '%s %s (project %s)\n' "$(basename "$0")" "$SCRIPT_VERSION" "$PROJECT_VERSION"; exit 0 ;;
            *) pa_count=$((pa_count + 1)); case "$pa_count" in 1) VMID="$1" ;; 2) SLOT="$1" ;; 3) DEST_VG="$1" ;; *) usage >&2; exit 2 ;; esac ;;
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
