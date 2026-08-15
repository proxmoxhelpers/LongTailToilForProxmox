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
    VMIDS=""
    parse_arguments "$@"
    check_elevation
}

main() {
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    need_commands qm pvesm awk
    [ "$SRC" != "$DST" ] || die "Source and destination storage are identical."
    pvesm status --storage "$DST" >/dev/null 2>&1 || die "Destination storage unavailable: $DST"
    move_all
}

end() { dryrun_summary; }

############################################################
# COMMAND LINE
############################################################

usage() { printf 'Usage: %s <source-storage> <destination-storage> <vmid>... [dryrun]\n' "$(basename "$0")"; dryrun_help; }

parse_arguments() {
    pa_count=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            dryrun|--dryrun) enable_dryrun ;;
            -h|--help) usage; exit 0 ;;
            --version) printf '%s %s (project %s)\n' "$(basename "$0")" "$SCRIPT_VERSION" "$PROJECT_VERSION"; exit 0 ;;
            *)
                pa_count=$((pa_count + 1))
                case "$pa_count" in 1) SRC="$1" ;; 2) DST="$1" ;; *) VMIDS="${VMIDS}${VMIDS:+ }$1" ;; esac
                ;;
        esac
        shift
    done
    [ "$pa_count" -ge 3 ] || { usage >&2; exit 2; }
}

# move_all
# Moves every non-CDROM VM disk on SRC to DST for each requested VMID.
move_all() {
    for ma_id in $VMIDS; do
        require_qemu_vm "$ma_id"
        ma_slots="$(qm config "$ma_id" | awk -F': ' -v s="$SRC:" '$1 ~ /^(scsi|sata|virtio|ide)[0-9]+$/ && index($2,s)==1 && $2 !~ /media=cdrom/ {print $1}')"
        if [ -z "$ma_slots" ]; then info "VM $ma_id: no disks on $SRC."; continue; fi
        printf '%s\n' "$ma_slots" | while IFS= read -r ma_slot; do
            [ -n "$ma_slot" ] || continue
            info "VM $ma_id: moving $ma_slot -> $DST"
            dryrun_cmd qm move_disk "$ma_id" "$ma_slot" "$DST" --delete 1
        done
    done
    ok "Bulk storage move complete."
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
