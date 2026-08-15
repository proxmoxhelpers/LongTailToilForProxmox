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
    CANDIDATE_FILE=""; PLAN_FILE=""
    parse_arguments "$@"
    check_elevation
}

main() {
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    install_temp_cleanup
    need_commands qm pvesm lvs lvrename cp sed grep sort mktemp
    require_qemu_vm "$VMID"; require_guest_stopped "$VMID"
    CONFIG="/etc/pve/qemu-server/${VMID}.conf"
    collect_candidates
    build_fix_plan
    [ "$FIX_COUNT" -gt 0 ] || { ok "All LVM-backed VM volumes already use vm-${VMID}-disk-N names."; return 0; }
    apply_fix_plan
    verify_fix
}

end() {
    [ -z "$CANDIDATE_FILE" ] || rm -f "$CANDIDATE_FILE"
    [ -z "$PLAN_FILE" ] || rm -f "$PLAN_FILE"
    dryrun_summary
}

############################################################
# COMMAND LINE
############################################################

usage() { printf 'Usage: %s <vmid> [dryrun]\n' "$(basename "$0")"; dryrun_help; }

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
# VALIDATION / PRE-FLIGHT
############################################################

# collect_candidates
# Collects unique storage volume IDs from relevant VM disk/unused slots.
collect_candidates() {
    CANDIDATE_FILE="$(mktemp)" || die "Unable to create candidate list."
    register_temp_file "$CANDIDATE_FILE"
    qm config "$VMID" | awk -F': ' '$1 ~ /^(scsi|sata|virtio|ide|unused)[0-9]+$/ {split($2,a,","); if (a[1] ~ /:/) print a[1]}' | sort -u > "$CANDIDATE_FILE"
}

# build_fix_plan
#
# Description:
#   Plans all mismatched LVM-backed volume renames before mutation and chooses
#   destination vm-VMID-disk-N names that do not collide in the VG.
#
# Usage:
#   build_fix_plan
#
# Arguments:
#   Uses VMID, CONFIG and CANDIDATE_FILE.
#
# Output:
#   PLAN_FILE columns: old-volid|new-volid|vg|old-lv|new-lv
#   Sets FIX_COUNT.
#
# Returns:
#   0 after complete preflight.
############################################################
build_fix_plan() {
    PLAN_FILE="$(mktemp)" || die "Unable to create volume-name plan."
    register_temp_file "$PLAN_FILE"
    bf_max=-1
    while IFS= read -r bf_volid; do
        bf_name="${bf_volid#*:}"
        if printf '%s\n' "$bf_name" | grep -qE "^vm-${VMID}-disk-[0-9]+$"; then
            bf_num="${bf_name##*-disk-}"
            [ "$bf_num" -le "$bf_max" ] || bf_max="$bf_num"
        fi
    done < "$CANDIDATE_FILE"
    bf_next=$((bf_max + 1)); FIX_COUNT=0

    while IFS= read -r bf_volid; do
        [ -n "$bf_volid" ] || continue
        bf_name="${bf_volid#*:}"
        printf '%s\n' "$bf_name" | grep -qE "^vm-${VMID}-disk-[0-9]+$" && continue
        bf_path="$(pvesm path "$bf_volid" 2>/dev/null || :)"; [ -n "$bf_path" ] || continue
        lvs "$bf_path" >/dev/null 2>&1 || { warn "Skipping non-LVM volume $bf_volid"; continue; }
        bf_refs="$(other_volume_references "$bf_volid" "$CONFIG")"
        [ -z "$bf_refs" ] || { printf '%s\n' "$bf_refs"; die "$bf_volid is referenced by another guest."; }
        bf_vg="$(lvs --noheadings -o vg_name "$bf_path" | trim)"
        bf_old="$(lvs --noheadings -o lv_name "$bf_path" | trim)"
        while lvs "$bf_vg/vm-${VMID}-disk-${bf_next}" >/dev/null 2>&1; do bf_next=$((bf_next + 1)); done
        bf_new="vm-${VMID}-disk-${bf_next}"; bf_next=$((bf_next + 1))
        bf_new_volid="${bf_volid%%:*}:$bf_new"
        printf '%s|%s|%s|%s|%s\n' "$bf_volid" "$bf_new_volid" "$bf_vg" "$bf_old" "$bf_new" >> "$PLAN_FILE"
        FIX_COUNT=$((FIX_COUNT + 1))
    done < "$CANDIDATE_FILE"
}

############################################################
# TRANSACTION
############################################################

# apply_fix_plan
# Applies the prevalidated LV renames and matching config substitutions from PLAN_FILE.
apply_fix_plan() {
    BACKUP="/root/${VMID}.conf.before-volume-name-fix.$(date +%Y%m%d-%H%M%S)"
    dryrun_cmd cp "$CONFIG" "$BACKUP"
    while IFS='|' read -r af_old_volid af_new_volid af_vg af_old af_new; do
        info "$af_old_volid -> $af_new_volid"
        dryrun_cmd lvrename "$af_vg" "$af_old" "$af_new"
        dryrun_cmd sed -i "s#${af_old_volid}#${af_new_volid}#g" "$CONFIG"
    done < "$PLAN_FILE"
}

# verify_fix
# Validates the rewritten VM config after all planned name repairs.
verify_fix() {
    if dryrun_enabled; then dryrun_verify "VM $VMID configuration and renamed volumes would be consistent"
    else qm config "$VMID" >/dev/null || die "Config verification failed. Backup: $BACKUP"; fi
    ok "Renamed $FIX_COUNT volume(s). Backup: $BACKUP"
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
