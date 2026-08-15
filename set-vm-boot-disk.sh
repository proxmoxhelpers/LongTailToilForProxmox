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
    PROJECT_VERSION="3.0.1"; SCRIPT_VERSION="3.0.1"
    parse_arguments "$@"
    check_elevation
}

main() {
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    need_commands qm sed awk
    require_qemu_vm "$VMID"
    [ -n "$(disk_value "$VMID" "$SLOT")" ] || die "Disk slot does not exist: $SLOT"
    build_boot_order
    apply_boot_order
}

end() { dryrun_summary; }

############################################################
# COMMAND LINE
############################################################

usage() { printf 'Usage: %s <vmid> <disk-slot> [dryrun]\n' "$(basename "$0")"; dryrun_help; }

parse_arguments() {
    pa_count=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            dryrun|--dryrun) enable_dryrun ;;
            -h|--help) usage; exit 0 ;;
            --version) printf '%s %s (project %s)\n' "$(basename "$0")" "$SCRIPT_VERSION" "$PROJECT_VERSION"; exit 0 ;;
            *) pa_count=$((pa_count + 1)); case "$pa_count" in 1) VMID="$1" ;; 2) SLOT="$1" ;; *) usage >&2; exit 2 ;; esac ;;
        esac
        shift
    done
    [ "$pa_count" -eq 2 ] || { usage >&2; exit 2; }
}

############################################################
# HIGH LEVEL TASKS
############################################################

# build_boot_order
# Moves SLOT to the front while preserving the remaining configured order.
build_boot_order() {
    bo_boot="$(qm config "$VMID" | sed -n 's/^boot:[[:space:]]*//p' | head -n1)"
    bo_order="$(printf '%s\n' "$bo_boot" | sed -n 's/.*order=\([^,]*\).*/\1/p')"
    NEW="$SLOT"
    bo_old_ifs="$IFS"; IFS=';'; set -- $bo_order; IFS="$bo_old_ifs"
    for bo_item in "$@"; do
        if [ -n "$bo_item" ] && [ "$bo_item" != "$SLOT" ]; then NEW="${NEW};${bo_item}"; fi
    done
    return 0
}

# apply_boot_order
# Applies and verifies the computed boot order.
apply_boot_order() {
    dryrun_cmd qm set "$VMID" --boot "order=$NEW"
    if dryrun_enabled; then dryrun_verify "VM $VMID boot order would start with $SLOT"
    else qm config "$VMID" | grep -qE "^boot:.*order=${SLOT}([;,]|$)" || die "Boot-order verification failed."; fi
    ok "Boot order now starts with $SLOT: $NEW"
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
