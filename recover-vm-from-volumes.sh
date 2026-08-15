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
    VG=""; RECOVERY_FILE=""
    parse_arguments "$@"
    check_elevation
}

main() {
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    install_temp_cleanup
    need_commands qm lvs pvesm find awk sort mktemp
    validate_vmid
    build_recovery_plan
    create_recovered_vm
    verify_recovered_vm
}

end() {
    [ -z "$RECOVERY_FILE" ] || rm -f "$RECOVERY_FILE"
    dryrun_summary
}

############################################################
# COMMAND LINE
############################################################

usage() { printf 'Usage: %s <vmid> [volume-group] [dryrun]\n' "$(basename "$0")"; dryrun_help; }

parse_arguments() {
    pa_count=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            dryrun|--dryrun) enable_dryrun ;;
            -h|--help) usage; exit 0 ;;
            --version) printf '%s %s (project %s)\n' "$(basename "$0")" "$SCRIPT_VERSION" "$PROJECT_VERSION"; exit 0 ;;
            *) pa_count=$((pa_count + 1)); case "$pa_count" in 1) VMID="$1" ;; 2) VG="$1" ;; *) usage >&2; exit 2 ;; esac ;;
        esac
        shift
    done
    [ "$pa_count" -ge 1 ] && [ "$pa_count" -le 2 ] || { usage >&2; exit 2; }
}

############################################################
# VALIDATION / PRE-FLIGHT
############################################################

# validate_vmid
# Validates the requested recovery VMID and proves it is unused cluster-wide.
validate_vmid() {
    case "$VMID" in ''|*[!0-9]*) die "VMID must be numeric." ;; esac
    if find /etc/pve/nodes -type f \( -path "*/qemu-server/${VMID}.conf" -o -path "*/lxc/${VMID}.conf" \) -print -quit 2>/dev/null | grep -q .; then die "VMID $VMID already exists."; fi
    return 0
}

# build_recovery_plan
#
# Description:
#   Finds vm-VMID-disk-N LVs, resolves each to one unambiguous Proxmox volume
#   ID, and refuses any disk already referenced by a guest.
#
# Usage:
#   build_recovery_plan
#
# Arguments:
#   Uses VMID and optional VG.
#
# Output:
#   RECOVERY_FILE contains one ordered Proxmox volume ID per line.
#
# Returns:
#   0 when at least one recoverable disk exists.
############################################################
build_recovery_plan() {
    RECOVERY_FILE="$(mktemp)" || die "Unable to create recovery plan."
    register_temp_file "$RECOVERY_FILE"
    brp_lvs="$(mktemp)" || die "Unable to create LVM discovery file."
    register_temp_file "$brp_lvs"
    register_temp_file "${brp_lvs}.sorted"
    if [ -n "$VG" ]; then lvs --noheadings --separator '|' -o lv_path,lv_name "$VG" > "$brp_lvs"
    else lvs --noheadings --separator '|' -o lv_path,lv_name > "$brp_lvs"; fi
    awk -F'|' -v id="$VMID" '{gsub(/^ +| +$/,"",$1);gsub(/^ +| +$/,"",$2); if ($2 ~ "^vm-"id"-disk-[0-9]+$") {n=$2; sub(/^.*-disk-/,"",n); print n "|" $1}}' "$brp_lvs" | sort -t'|' -k1,1n > "${brp_lvs}.sorted"
    rm -f "$brp_lvs"
    [ -s "${brp_lvs}.sorted" ] || { rm -f "${brp_lvs}.sorted"; die "No LVs named vm-${VMID}-disk-N were found${VG:+ in VG $VG}."; }
    while IFS='|' read -r brp_num brp_path; do
        brp_volid="$(volid_for_lv "$brp_path")"
        brp_refs="$(other_volume_references "$brp_volid")"
        [ -z "$brp_refs" ] || { printf '%s\n' "$brp_refs"; rm -f "${brp_lvs}.sorted"; die "$brp_volid is already referenced by another guest."; }
        printf '%s\n' "$brp_volid" >> "$RECOVERY_FILE"
    done < "${brp_lvs}.sorted"
    rm -f "${brp_lvs}.sorted"
}

############################################################
# HIGH LEVEL TASKS
############################################################

# create_recovered_vm
# Creates the recovery VM, attaches planned disks in order and sets the first disk as boot target.
create_recovered_vm() {
    dryrun_cmd qm create "$VMID" --name "recovered-${VMID}" --memory 2048 --cores 2 --scsihw virtio-scsi-single
    crv_i=0
    while IFS= read -r crv_volid; do
        dryrun_cmd qm set "$VMID" "--scsi${crv_i}" "$crv_volid"
        crv_i=$((crv_i + 1))
    done < "$RECOVERY_FILE"
    dryrun_cmd qm set "$VMID" --boot "order=scsi0"
    RECOVERED_COUNT="$crv_i"
}

# verify_recovered_vm
# Validates that Proxmox can parse the recovered VM configuration.
verify_recovered_vm() {
    if dryrun_enabled; then dryrun_verify "Recovered VM configuration would be readable"
    else qm config "$VMID" >/dev/null || die "Recovered configuration failed validation."; fi
    ok "Created VM $VMID with $RECOVERED_COUNT recovered disk(s). Review CPU, memory, firmware, machine type, NICs, and boot settings before starting."
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
