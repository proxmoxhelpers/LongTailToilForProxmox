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
    need_commands qm pvesm lvs
    require_qemu_vm "$VMID"
    list_disks
}

end() { :; }

############################################################
# COMMAND LINE
############################################################

usage() {
    cat <<EOF
$(basename "$0") $SCRIPT_VERSION (project $PROJECT_VERSION)

USAGE
  $(basename "$0") <vmid> [dryrun]

DESCRIPTION
  Lists storage-backed disks configured on a local QEMU VM, including
  resolved paths and LVM metadata where available.

EOF
    dryrun_help
}

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

# list_disks
# Prints configured VM disks and LVM metadata when the volume is LVM-backed.
list_disks() {
    printf '%-10s %-34s %-34s %-12s %-16s %s\n' SLOT VOLUME PATH SIZE POOL ORIGIN
    qm config "$VMID" | while IFS=':' read -r ld_key ld_rest; do
        case "$ld_key" in scsi[0-9]*|sata[0-9]*|virtio[0-9]*|ide[0-9]*|unused[0-9]*) ;; *) continue ;; esac
        ld_rest="$(printf '%s' "$ld_rest" | trim)"; ld_vol="${ld_rest%%,*}"
        case "$ld_vol" in *:*) ;; *) continue ;; esac
        ld_path="$(pvesm path "$ld_vol" 2>/dev/null || :)"; ld_size="-"; ld_pool="-"; ld_origin="-"
        if [ -n "$ld_path" ] && lvs "$ld_path" >/dev/null 2>&1; then
            ld_size="$(lvs --noheadings -o lv_size "$ld_path" | trim)"
            ld_pool="$(lvs --noheadings -o pool_lv "$ld_path" | trim)"; [ -n "$ld_pool" ] || ld_pool="-"
            ld_origin="$(lvs --noheadings -o origin "$ld_path" | trim)"; [ -n "$ld_origin" ] || ld_origin="-"
        fi
        printf '%-10s %-34s %-34s %-12s %-16s %s\n' "$ld_key" "$ld_vol" "${ld_path:--}" "$ld_size" "$ld_pool" "$ld_origin"
    done
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
