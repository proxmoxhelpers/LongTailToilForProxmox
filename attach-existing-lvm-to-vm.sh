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
    SLOT=""
    parse_arguments "$@"
    check_elevation
}

main() {
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    need_commands lvs qm pvesm findmnt readlink dmsetup
    validate_attach
    attach_volume
}

end() { dryrun_summary; }

############################################################
# COMMAND LINE
############################################################

usage() { printf 'Usage: %s <full-lv-path> <vmid> [scsiN] [dryrun]\n' "$(basename "$0")"; dryrun_help; }

parse_arguments() {
    pa_count=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            dryrun|--dryrun) enable_dryrun ;;
            -h|--help) usage; exit 0 ;;
            --version) printf '%s %s (project %s)\n' "$(basename "$0")" "$SCRIPT_VERSION" "$PROJECT_VERSION"; exit 0 ;;
            *) pa_count=$((pa_count + 1)); case "$pa_count" in 1) LV="$1" ;; 2) VMID="$1" ;; 3) SLOT="$1" ;; *) usage >&2; exit 2 ;; esac ;;
        esac
        shift
    done
    [ "$pa_count" -ge 2 ] && [ "$pa_count" -le 3 ] || { usage >&2; exit 2; }
}

############################################################
# VALIDATION / PRE-FLIGHT
############################################################

# validate_attach
# Resolves the LV, verifies exclusive ownership and selects a free SCSI slot.
validate_attach() {
    assert_lv_exists "$LV"; require_qemu_vm "$VMID"
    LV="$(canonical_lv_path "$LV")"; assert_lv_idle "$LV"
    VOLID="$(volid_for_lv "$LV")"
    [ -z "$(other_volume_references "$VOLID")" ] || die "Volume is already referenced by another guest."
    [ -n "$SLOT" ] || SLOT="$(first_free_scsi "$VMID")"
    case "$SLOT" in
        scsi[0-9]|scsi1[0-9]|scsi2[0-9]|scsi30) ;;
        *) die "Slot must be scsi0..scsi30." ;;
    esac
    [ -z "$(disk_value "$VMID" "$SLOT")" ] || die "$SLOT is already occupied."
    info "LV: $LV"; info "VM: $VMID"; info "Attach: $SLOT -> $VOLID"
}

############################################################
# HIGH LEVEL TASKS
############################################################

# attach_volume
# Attaches the resolved Proxmox volume and verifies the exact slot reference.
attach_volume() {
    dryrun_cmd qm set "$VMID" "--$SLOT" "$VOLID"
    if dryrun_enabled; then dryrun_verify "VM $VMID would reference $VOLID at $SLOT"
    else [ "$(disk_volid "$VMID" "$SLOT")" = "$VOLID" ] || die "Attachment verification failed."; fi
    ok "Attached $VOLID to VM $VMID as $SLOT."
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
