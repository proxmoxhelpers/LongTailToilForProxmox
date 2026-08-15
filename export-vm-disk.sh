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
    FORMAT=""
    parse_arguments "$@"
    check_elevation
}

main() {
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    need_commands qm pvesm qemu-img
    validate_export
    export_disk
}

end() { dryrun_summary; }

############################################################
# COMMAND LINE
############################################################

usage() { printf 'Usage: %s <vmid> <disk-slot> <output-file> [raw|qcow2] [dryrun]\n' "$(basename "$0")"; dryrun_help; }

parse_arguments() {
    pa_count=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            dryrun|--dryrun) enable_dryrun ;;
            -h|--help) usage; exit 0 ;;
            --version) printf '%s %s (project %s)\n' "$(basename "$0")" "$SCRIPT_VERSION" "$PROJECT_VERSION"; exit 0 ;;
            *) pa_count=$((pa_count + 1)); case "$pa_count" in 1) VMID="$1" ;; 2) SLOT="$1" ;; 3) OUT="$1" ;; 4) FORMAT="$1" ;; *) usage >&2; exit 2 ;; esac ;;
        esac
        shift
    done
    [ "$pa_count" -ge 3 ] && [ "$pa_count" -le 4 ] || { usage >&2; exit 2; }
}

# validate_export
# Validates the VM/slot/output format and resolves the backing volume before export.
validate_export() {
    require_qemu_vm "$VMID"; require_guest_stopped "$VMID"
    [ ! -e "$OUT" ] || die "Output already exists: $OUT"
    VOLID="$(disk_volid "$VMID" "$SLOT" || :)"; [ -n "$VOLID" ] || die "No disk volume found at $SLOT."
    SRC="$(resolve_volid_path "$VOLID" || :)"; [ -n "$SRC" ] || die "Cannot resolve $VOLID."
    if [ -z "$FORMAT" ]; then case "$OUT" in *.qcow2) FORMAT=qcow2 ;; *) FORMAT=raw ;; esac; fi
    case "$FORMAT" in raw|qcow2) ;; *) die "Format must be raw or qcow2." ;; esac
}

# export_disk
# Runs qemu-img conversion and validates the resulting image.
export_disk() {
    info "Exporting $VOLID -> $OUT ($FORMAT)..."
    dryrun_cmd qemu-img convert -p -O "$FORMAT" "$SRC" "$OUT"
    if dryrun_enabled; then dryrun_verify "Output image $OUT would be created and readable"
    else qemu-img info "$OUT" >/dev/null || die "Export verification failed."; fi
    ok "Exported $OUT."
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
