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
    DEST="scsi"
    parse_arguments "$@"
    check_elevation
}

main() {
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    need_commands qm cp sed grep
    require_qemu_vm "$VMID"; require_guest_stopped "$VMID"
    select_destination
    change_bus
}

end() { dryrun_summary; }

############################################################
# COMMAND LINE
############################################################

usage() { printf 'Usage: %s <vmid> <source-slot> [destination-slot|scsi|virtio|sata|ide] [dryrun]\n' "$(basename "$0")"; dryrun_help; }

parse_arguments() {
    pa_count=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            dryrun|--dryrun) enable_dryrun ;;
            -h|--help) usage; exit 0 ;;
            --version) printf '%s %s (project %s)\n' "$(basename "$0")" "$SCRIPT_VERSION" "$PROJECT_VERSION"; exit 0 ;;
            *) pa_count=$((pa_count + 1)); case "$pa_count" in 1) VMID="$1" ;; 2) SRC="$1" ;; 3) DEST="$1" ;; *) usage >&2; exit 2 ;; esac ;;
        esac
        shift
    done
    [ "$pa_count" -ge 2 ] && [ "$pa_count" -le 3 ] || { usage >&2; exit 2; }
}

############################################################
# VALIDATION / PRE-FLIGHT
############################################################

# select_destination
# Resolves a bare bus name to its first free slot and verifies no collision.
select_destination() {
    VALUE="$(disk_value "$VMID" "$SRC")"; [ -n "$VALUE" ] || die "Source slot does not exist: $SRC"
    case "$DEST" in
        scsi|virtio|sata|ide)
            sd_bus="$DEST"; sd_cfg="$(qm config "$VMID")"; DEST=""
            case "$sd_bus" in scsi) sd_max=30 ;; virtio) sd_max=15 ;; sata) sd_max=5 ;; ide) sd_max=3 ;; esac
            sd_i=0
            while [ "$sd_i" -le "$sd_max" ]; do
                printf '%s\n' "$sd_cfg" | grep -qE "^${sd_bus}${sd_i}:" || { DEST="${sd_bus}${sd_i}"; break; }
                sd_i=$((sd_i + 1))
            done
            ;;
    esac
    printf '%s\n' "$DEST" | grep -qE '^(scsi|virtio|sata|ide)[0-9]+$' || die "Could not determine a valid destination slot."
    [ -z "$(disk_value "$VMID" "$DEST")" ] || die "Destination slot is occupied: $DEST"
    CONFIG="/etc/pve/qemu-server/${VMID}.conf"; BACKUP="/root/${VMID}.conf.before-bus-change.$(date +%Y%m%d-%H%M%S)"
}

############################################################
# HIGH LEVEL TASKS
############################################################

# change_bus
# Backs up the VM config, rewrites the disk-slot key, and verifies the exact value at the new slot.
change_bus() {
    dryrun_cmd cp "$CONFIG" "$BACKUP"
    dryrun_cmd sed -i "s/^${SRC}:/${DEST}:/" "$CONFIG"
    if dryrun_enabled; then
        dryrun_verify "$SRC would move to $DEST with its existing disk options"
    else
        if [ "$(disk_value "$VMID" "$DEST")" != "$VALUE" ] || [ -n "$(disk_value "$VMID" "$SRC")" ]; then
            cp "$BACKUP" "$CONFIG"; die "Verification failed; config restored."
        fi
    fi
    ok "Changed $SRC -> $DEST. Backup: $BACKUP"
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
