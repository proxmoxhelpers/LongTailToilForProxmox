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
    PLAN_FILE=""
    parse_arguments "$@"
    check_elevation
}

main() {
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    install_temp_cleanup
    need_commands qm pvesm lvs lvrename cp sed grep awk sort mktemp
    validate_vm
    build_renumber_plan
    [ "$CHANGES" -gt 0 ] || { ok "Disk volume names are already contiguous."; return 0; }
    validate_destinations
    apply_renumber_plan
    verify_renumber
}

end() {
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

# validate_vm
# Validates stopped VM state and rejects snapshot/config sections before renumbering.
validate_vm() {
    require_qemu_vm "$VMID"; require_guest_stopped "$VMID"
    CONFIG="/etc/pve/qemu-server/${VMID}.conf"
    if grep -qE '^\[[^]]+\]$' "$CONFIG"; then die "VM snapshots/config sections detected; remove snapshots first."; fi
    return 0
}

# build_renumber_plan
#
# Description:
#   Resolves every vm-VMID-disk-N reference into an immutable transaction
#   plan. The plan replaces Bash arrays and is fully built before mutation.
#
# Usage:
#   build_renumber_plan
#
# Arguments:
#   Uses VMID and CONFIG.
#
# Output:
#   PLAN_FILE columns:
#     index|volid|path|vg|old-lv|new-lv|storage-id|temporary-lv
#   Sets CHANGES.
#
# Returns:
#   0 when a plan exists or no matching volumes exist.
############################################################
build_renumber_plan() {
    PLAN_FILE="$(mktemp)" || die "Unable to create renumber plan."
    register_temp_file "$PLAN_FILE"
    brp_volids="$(mktemp)" || die "Unable to create volume list."
    register_temp_file "$brp_volids"
    grep -oE "[A-Za-z0-9_.-]+:vm-${VMID}-disk-[0-9]+" "$CONFIG" |
        awk '{n=$0; sub(/^.*-disk-/,"",n); print n "|" $0}' |
        sort -t'|' -k1,1n -k2,2 -u |
        cut -d'|' -f2- > "$brp_volids"
    if [ ! -s "$brp_volids" ]; then rm -f "$brp_volids"; CHANGES=0; info "No vm-${VMID}-disk-N volumes found."; return 0; fi

    brp_i=0; CHANGES=0
    while IFS= read -r brp_volid; do
        brp_path="$(pvesm path "$brp_volid" 2>/dev/null || :)"; [ -n "$brp_path" ] || { rm -f "$brp_volids"; die "Cannot resolve $brp_volid."; }
        lvs "$brp_path" >/dev/null 2>&1 || { rm -f "$brp_volids"; die "$brp_volid is not LVM-backed."; }
        brp_vg="$(lvs --noheadings -o vg_name "$brp_path" | trim)"
        brp_old="$(lvs --noheadings -o lv_name "$brp_path" | trim)"
        brp_new="vm-${VMID}-disk-${brp_i}"
        brp_storage="${brp_volid%%:*}"
        brp_temp="vm-${VMID}-renumber-temp-$$-${brp_i}"
        printf '%s|%s|%s|%s|%s|%s|%s|%s\n' "$brp_i" "$brp_volid" "$brp_path" "$brp_vg" "$brp_old" "$brp_new" "$brp_storage" "$brp_temp" >> "$PLAN_FILE"
        [ "$brp_old" = "$brp_new" ] || CHANGES=$((CHANGES + 1))
        brp_i=$((brp_i + 1))
    done < "$brp_volids"
    rm -f "$brp_volids"
}

# validate_destinations
# Allows an occupied target only when that LV is itself a source in PLAN_FILE.
validate_destinations() {
    while IFS='|' read -r vd_i vd_volid vd_path vd_vg vd_old vd_new vd_storage vd_temp; do
        [ "$vd_old" = "$vd_new" ] && continue
        if lvs "$vd_vg/$vd_new" >/dev/null 2>&1; then
            awk -F'|' -v vg="$vd_vg" -v name="$vd_new" '$4==vg && $5==name {found=1} END {exit(found ? 0 : 1)}' "$PLAN_FILE" ||
                die "Destination LV already exists: /dev/${vd_vg}/${vd_new}"
        fi
        if lvs "$vd_vg/$vd_temp" >/dev/null 2>&1; then die "Temporary LV collision: /dev/${vd_vg}/${vd_temp}"; fi
    done < "$PLAN_FILE"
    return 0
}

############################################################
# TRANSACTION
############################################################

# apply_renumber_plan
#
# Description:
#   Performs two-phase LV renames through unique temporary names, then rewrites
#   config references from the same immutable plan.
#
# Usage:
#   apply_renumber_plan
#
# Arguments:
#   Uses PLAN_FILE and CONFIG.
#
# Output:
#   Renamed LVs and updated VM configuration unless dry-run mode is active.
#
# Returns:
#   0 when all transaction commands complete.
############################################################
apply_renumber_plan() {
    BACKUP="/root/${VMID}.conf.before-renumber.$(date +%Y%m%d-%H%M%S)"
    dryrun_cmd cp "$CONFIG" "$BACKUP"
    info "Config backup: $BACKUP"

    while IFS='|' read -r ar_i ar_volid ar_path ar_vg ar_old ar_new ar_storage ar_temp; do
        [ "$ar_old" = "$ar_new" ] || dryrun_cmd lvrename "$ar_vg" "$ar_old" "$ar_temp"
    done < "$PLAN_FILE"

    while IFS='|' read -r ar_i ar_volid ar_path ar_vg ar_old ar_new ar_storage ar_temp; do
        [ "$ar_old" = "$ar_new" ] || dryrun_cmd lvrename "$ar_vg" "$ar_temp" "$ar_new"
    done < "$PLAN_FILE"

    while IFS='|' read -r ar_i ar_volid ar_path ar_vg ar_old ar_new ar_storage ar_temp; do
        [ "$ar_old" = "$ar_new" ] && continue
        ar_old_volid="${ar_storage}:${ar_old}"; ar_new_volid="${ar_storage}:${ar_new}"
        dryrun_cmd sed -i "s#${ar_old_volid}#${ar_new_volid}#g" "$CONFIG"
    done < "$PLAN_FILE"
}

# verify_renumber
# Validates the resulting VM configuration after all planned renames/substitutions.
verify_renumber() {
    if dryrun_enabled; then dryrun_verify "VM $VMID configuration would parse with contiguous volume names"
    else qm config "$VMID" >/dev/null || die "Proxmox cannot parse the updated config. Backup: $BACKUP"; fi
    ok "Renumbered $CHANGES volume(s). VM remains stopped."
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
