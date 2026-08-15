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
    need_commands qm pvesm lvs
    resolve_source
    if [ -n "$DEST_VG" ]; then exec_project_script "$SCRIPT_DIR/create-disk-copy-and-add-to-vm.sh" "$PATH_SRC" "$DST_VM" "$DEST_VG"
    else exec_project_script "$SCRIPT_DIR/create-disk-copy-and-add-to-vm.sh" "$PATH_SRC" "$DST_VM"; fi
}

end() { :; }

############################################################
# COMMAND LINE
############################################################

usage() { printf 'Usage: %s <source-vmid> <source-slot> <destination-vmid> [destination-vg] [dryrun]\n' "$(basename "$0")"; dryrun_help; }

parse_arguments() {
    pa_count=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            dryrun|--dryrun) enable_dryrun ;;
            -h|--help) usage; exit 0 ;;
            --version) printf '%s %s (project %s)\n' "$(basename "$0")" "$SCRIPT_VERSION" "$PROJECT_VERSION"; exit 0 ;;
            *) pa_count=$((pa_count + 1)); case "$pa_count" in 1) SRC_VM="$1" ;; 2) SLOT="$1" ;; 3) DST_VM="$1" ;; 4) DEST_VG="$1" ;; *) usage >&2; exit 2 ;; esac ;;
        esac
        shift
    done
    [ "$pa_count" -ge 3 ] && [ "$pa_count" -le 4 ] || { usage >&2; exit 2; }
}

# resolve_source
# Resolves the requested source VM slot to an LVM-backed device path for the copy helper.
resolve_source() {
    require_qemu_vm "$SRC_VM"; require_qemu_vm "$DST_VM"
    cbv_volid="$(disk_volid "$SRC_VM" "$SLOT" || :)"; [ -n "$cbv_volid" ] || die "No disk volume found at $SLOT."
    PATH_SRC="$(resolve_volid_path "$cbv_volid" || :)"; [ -n "$PATH_SRC" ] || die "Cannot resolve $cbv_volid."
    lvs "$PATH_SRC" >/dev/null 2>&1 || die "Source disk is not LVM-backed: $PATH_SRC"
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
