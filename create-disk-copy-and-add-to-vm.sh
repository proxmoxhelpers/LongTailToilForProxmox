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
    REQUESTED_DEST_VG=""
    CREATED=0; ATTACHED=0; COMPLETE=0
    parse_arguments "$@"
    check_elevation
}

main() {
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    need_commands lvs vgs lvcreate lvremove qm pvesm blockdev readlink awk grep sed dd cmp sort tail mktemp
    validate_source
    validate_destination_vm
    select_destination_storage
    select_disk_name
    SCSI_DEVICE="$(first_free_scsi "$DEST_VMID")" || die "No free SCSI disk slot is available on VM $DEST_VMID."
    TARGET_STATUS="$(qm status "$DEST_VMID" 2>/dev/null | awk '{print $2}' || :)"
    print_plan
    trap cleanup_on_exit 0
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    create_destination
    verify_storage_mapping
    copy_data
    verify_copy
    attach_copy
    verify_result
    COMPLETE=1
}

end() {
    print_banner "Disk copied and attached successfully"
    printf 'Source:           %s\n' "$SOURCE_PATH"
    printf 'Copy:             %s\n' "$NEW_LV_PATH"
    printf 'Proxmox volume:   %s\n' "$NEW_VOLID"
    printf 'Destination VM:   %s\n' "$DEST_VMID"
    printf 'Attached as:      %s\n' "$SCSI_DEVICE"
    printf 'Destination VG:   %s\n' "$DEST_VG"
    printf 'Storage:          %s\n\n' "$STORAGE_ID"
    dryrun_summary
}

############################################################
# COMMAND LINE
############################################################

usage() {
    cat <<EOF
create-disk-copy-and-add-to-vm.sh $SCRIPT_VERSION (project $PROJECT_VERSION)

USAGE
  create-disk-copy-and-add-to-vm.sh <source-lv-path> <destination-vmid> [destination-vg] [dryrun]

DESCRIPTION
  Creates a full independent block-level copy named vm-DESTVMID-disk-N and
  attaches it to a QEMU VM. If destination-vg is omitted, the source VG is
  used. Destination Proxmox LVM/LVM-thin storage must be unambiguous.

EXAMPLES
  create-disk-copy-and-add-to-vm.sh /dev/thinvg/vm-132-disk-1 115
  create-disk-copy-and-add-to-vm.sh /dev/thinvg/vm-132-disk-1 115 fastvg

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
            *) pa_count=$((pa_count + 1)); case "$pa_count" in 1) SOURCE="$1" ;; 2) DEST_VMID="$1" ;; 3) REQUESTED_DEST_VG="$1" ;; *) usage >&2; exit 2 ;; esac ;;
        esac
        shift
    done
    [ "$pa_count" -ge 2 ] && [ "$pa_count" -le 3 ] || { usage >&2; exit 2; }
}

############################################################
# VALIDATION / PRE-FLIGHT
############################################################

# validate_source
# Resolves and validates source LV metadata required by the planned operation.
validate_source() {
    case "$DEST_VMID" in ''|*[!0-9]*) die "Destination VMID must be numeric." ;; esac
    lvs "$SOURCE" >/dev/null 2>&1 || die "Source is not an LVM logical volume: $SOURCE"
    SOURCE_PATH="$(lvs --noheadings -o lv_path "$SOURCE" 2>/dev/null | trim)"
    SOURCE_VG="$(lvs --noheadings -o vg_name "$SOURCE" 2>/dev/null | trim)"
    SOURCE_LV="$(lvs --noheadings -o lv_name "$SOURCE" 2>/dev/null | trim)"
    SOURCE_POOL="$(lvs --noheadings -o pool_lv "$SOURCE" 2>/dev/null | trim)"
    SOURCE_SIZE_BYTES="$(blockdev --getsize64 "$SOURCE_PATH")"
    [ -n "$SOURCE_PATH" ] && [ -n "$SOURCE_VG" ] && [ -n "$SOURCE_LV" ] || die "Could not resolve source LV metadata."
    case "$SOURCE_SIZE_BYTES" in ''|*[!0-9]*) die "Could not determine source LV size." ;; esac
    [ "$SOURCE_SIZE_BYTES" -gt 0 ] || die "Could not determine source LV size."
    DEST_VG="${REQUESTED_DEST_VG:-$SOURCE_VG}"
    vgs "$DEST_VG" >/dev/null 2>&1 || die "Destination volume group does not exist: $DEST_VG"
}

# validate_destination_vm
# Validates the local destination QEMU VM, config readability and lock state.
validate_destination_vm() {
    TARGET_CONFIG="/etc/pve/qemu-server/${DEST_VMID}.conf"
    if [ ! -f "$TARGET_CONFIG" ]; then
        [ ! -f "/etc/pve/lxc/${DEST_VMID}.conf" ] || die "VMID $DEST_VMID is an LXC container; this script attaches disks to QEMU VMs only."
        die "Destination QEMU VM $DEST_VMID does not exist on this node."
    fi
    qm config "$DEST_VMID" >/dev/null 2>&1 || die "Proxmox could not read configuration for VM $DEST_VMID."
    TARGET_QM_CONFIG="$(qm config "$DEST_VMID")"
    if printf '%s\n' "$TARGET_QM_CONFIG" | grep -qE '^lock:[[:space:]]*'; then
        printf '%s\n' "$TARGET_QM_CONFIG" | grep -E '^lock:[[:space:]]*' | sed 's/^/  /'
        die "Resolve the VM lock before attaching a disk."
    fi
}

# select_destination_storage
#
# Description:
#   Finds Proxmox lvm/lvmthin image storages in DEST_VG. Same-VG thin copies
#   prefer the exact source thin pool; otherwise exactly one storage is required.
#
# Usage:
#   select_destination_storage
#
# Arguments:
#   Uses DEST_VG, SOURCE_VG and SOURCE_POOL.
#
# Output:
#   Sets DEST_STORAGE_TYPE, STORAGE_ID and DEST_POOL.
#
# Returns:
#   0 only for an unambiguous storage mapping.
############################################################
select_destination_storage() {
    [ -f /etc/pve/storage.cfg ] || die "Proxmox storage configuration not found: /etc/pve/storage.cfg"
    sds_matches="$(awk -v wanted_vg="$DEST_VG" '
        function flush() {
            if ((type=="lvm" || type=="lvmthin") && vg==wanted_vg &&
                (content=="" || content ~ /(^|,)images(,|$)/)) print type "|" id "|" pool
        }
        /^[^ \t][^:]*:[ \t]*/ {flush(); split($1,h,":"); type=h[1]; id=$2; vg=""; pool=""; content=""; next}
        $1=="vgname" {vg=$2; next}
        $1=="thinpool" {pool=$2; next}
        $1=="content" {content=$2; next}
        END {flush()}
    ' /etc/pve/storage.cfg)"
    sds_count="$(printf '%s\n' "$sds_matches" | awk 'NF {n++} END {print n+0}')"
    [ "$sds_count" -gt 0 ] || die "No Proxmox lvm/lvmthin image storage is configured for destination VG $DEST_VG."

    SELECTED_STORAGE=""
    if [ "$DEST_VG" = "$SOURCE_VG" ] && [ -n "$SOURCE_POOL" ]; then
        sds_same="$(printf '%s\n' "$sds_matches" | awk -F'|' -v p="$SOURCE_POOL" '$1=="lvmthin" && $3==p')"
        sds_same_count="$(printf '%s\n' "$sds_same" | awk 'NF {n++} END {print n+0}')"
        [ "$sds_same_count" -ne 1 ] || SELECTED_STORAGE="$(printf '%s\n' "$sds_same" | awk 'NF {print; exit}')"
    fi
    [ -n "$SELECTED_STORAGE" ] || [ "$sds_count" -ne 1 ] || SELECTED_STORAGE="$(printf '%s\n' "$sds_matches" | awk 'NF {print; exit}')"

    if [ -z "$SELECTED_STORAGE" ]; then
        warn "Multiple Proxmox image storages use destination VG $DEST_VG:"
        printf '%s\n' "$sds_matches" | while IFS='|' read -r sds_type sds_id sds_pool; do
            [ -n "$sds_type" ] || continue
            if [ -n "$sds_pool" ]; then printf '  %-8s %-20s thinpool=%s\n' "$sds_type" "$sds_id" "$sds_pool" >&2
            else printf '  %-8s %-20s\n' "$sds_type" "$sds_id" >&2; fi
        done
        die "Destination storage is ambiguous. Specify a VG with exactly one applicable storage."
    fi

    DEST_STORAGE_TYPE="${SELECTED_STORAGE%%|*}"
    sds_rest="${SELECTED_STORAGE#*|}"
    STORAGE_ID="${sds_rest%%|*}"
    DEST_POOL="${sds_rest#*|}"
    [ "$DEST_STORAGE_TYPE" != "lvmthin" ] || [ -n "$DEST_POOL" ] || die "Storage $STORAGE_ID is lvmthin but has no thinpool configured."
}

# select_disk_name
# Chooses a VM disk number above the current maximum and skips orphaned LV collisions.
select_disk_name() {
    sdn_highest="$(printf '%s\n' "$TARGET_QM_CONFIG" | grep -oE "vm-${DEST_VMID}-disk-[0-9]+" | sed -E 's/.*-disk-([0-9]+)$/\1/' | sort -n | tail -n1 || :)"
    if [ -n "$sdn_highest" ]; then DISK_NUMBER=$((sdn_highest + 1)); else DISK_NUMBER=0; fi
    while :; do
        NEW_LV_NAME="vm-${DEST_VMID}-disk-${DISK_NUMBER}"
        NEW_LV_PATH="/dev/${DEST_VG}/${NEW_LV_NAME}"
        NEW_VOLID="${STORAGE_ID}:${NEW_LV_NAME}"
        sdn_config=0; sdn_lvm=0
        printf '%s\n' "$TARGET_QM_CONFIG" | grep -qF "$NEW_LV_NAME" && sdn_config=1 || :
        lvs "${DEST_VG}/${NEW_LV_NAME}" >/dev/null 2>&1 && sdn_lvm=1 || :
        [ "$sdn_config" -eq 0 ] && [ "$sdn_lvm" -eq 0 ] && break
        warn "Disk number $DISK_NUMBER is unavailable."
        [ "$sdn_config" -eq 0 ] || warn "  VM configuration references $NEW_LV_NAME"
        [ "$sdn_lvm" -eq 0 ] || warn "  LVM volume already exists: $NEW_LV_PATH"
        DISK_NUMBER=$((DISK_NUMBER + 1))
    done
}

############################################################
# TRANSACTION
############################################################

# print_plan
# Prints the fully resolved transaction plan before the first mutation.
print_plan() {
    print_banner "Create independent disk copy and attach to VM"
    printf 'Source LV:             %s\n' "$SOURCE_PATH"
    printf 'Source VG:             %s\n' "$SOURCE_VG"
    printf 'Source size:           %s bytes\n' "$SOURCE_SIZE_BYTES"
    printf 'Destination VG:        %s\n' "$DEST_VG"
    printf 'Destination storage:   %s (%s)\n' "$STORAGE_ID" "$DEST_STORAGE_TYPE"
    [ "$DEST_STORAGE_TYPE" != "lvmthin" ] || printf 'Destination thin pool: %s\n' "$DEST_POOL"
    printf 'Destination VM:        %s\n' "$DEST_VMID"
    printf 'Destination VM status: %s\n' "${TARGET_STATUS:-unknown}"
    printf 'New LV:                %s\n' "$NEW_LV_PATH"
    printf 'Proxmox volume ID:     %s\n' "$NEW_VOLID"
    printf 'Attach as:             %s\n\n' "$SCSI_DEVICE"
    warn "The source must remain consistent while the copy is running."
    warn "If it belongs to a running VM, shut down or quiesce that VM first."
}

# create_destination
# Creates the planned destination LV and verifies that its usable size is sufficient.
create_destination() {
    info "Creating destination LV..."
    if [ "$DEST_STORAGE_TYPE" = "lvmthin" ]; then
        if dryrun_enabled; then dryrun_cmd lvcreate -V "${SOURCE_SIZE_BYTES}B" -T "${DEST_VG}/${DEST_POOL}" -n "$NEW_LV_NAME"
        else run_lvm_filtered lvcreate -V "${SOURCE_SIZE_BYTES}B" -T "${DEST_VG}/${DEST_POOL}" -n "$NEW_LV_NAME"; fi
    else
        if dryrun_enabled; then dryrun_cmd lvcreate -L "${SOURCE_SIZE_BYTES}B" -n "$NEW_LV_NAME" "$DEST_VG"
        else run_lvm_filtered lvcreate -L "${SOURCE_SIZE_BYTES}B" -n "$NEW_LV_NAME" "$DEST_VG"; fi
    fi
    CREATED=1
    if dryrun_enabled; then
        DEST_SIZE_BYTES="$SOURCE_SIZE_BYTES"; dryrun_verify "Destination LV would exist with sufficient size"
    else
        lvs "${DEST_VG}/${NEW_LV_NAME}" >/dev/null 2>&1 || die "lvcreate returned successfully, but the destination LV cannot be found."
        DEST_SIZE_BYTES="$(blockdev --getsize64 "$NEW_LV_PATH")"
        [ "$DEST_SIZE_BYTES" -ge "$SOURCE_SIZE_BYTES" ] || die "Destination LV is smaller than the source."
    fi
}

# verify_storage_mapping
# Verifies the Proxmox volume ID resolves to the exact newly created LV.
verify_storage_mapping() {
    if dryrun_enabled; then PVE_PATH="$NEW_LV_PATH"; dryrun_verify "Proxmox storage $STORAGE_ID would resolve $NEW_VOLID"
    else PVE_PATH="$(pvesm path "$NEW_VOLID" 2>/dev/null || :)"; [ -n "$PVE_PATH" ] || die "Proxmox storage $STORAGE_ID cannot resolve $NEW_VOLID."; fi
    if ! dryrun_enabled; then [ "$(readlink -f "$PVE_PATH")" = "$(readlink -f "$NEW_LV_PATH")" ] || die "Proxmox storage mapping does not point to the newly created LV."; fi
}

# copy_data
# Copies source blocks using sparse writes only for newly created thin destinations.
copy_data() {
    info "Copying data..."
    if [ "$DEST_STORAGE_TYPE" = "lvmthin" ]; then dryrun_cmd dd if="$SOURCE_PATH" of="$NEW_LV_PATH" bs=4M iflag=fullblock conv=sparse,fsync status=progress
    else dryrun_cmd dd if="$SOURCE_PATH" of="$NEW_LV_PATH" bs=4M iflag=fullblock conv=fsync status=progress; fi
    ok "Copy completed."
}

# verify_copy
# Performs byte-for-byte comparison of the complete source-size range.
verify_copy() {
    info "Verifying copied data..."
    if dryrun_enabled; then dryrun_verify "cmp would verify $SOURCE_SIZE_BYTES bytes"
    elif ! cmp -n "$SOURCE_SIZE_BYTES" "$SOURCE_PATH" "$NEW_LV_PATH"; then die "Block verification failed; the destination copy does not match the source."; fi
    ok "Verification passed."
}

# attach_copy
# Attaches the verified independent copy to the selected destination VM slot.
attach_copy() {
    info "Attaching $NEW_VOLID to VM $DEST_VMID as $SCSI_DEVICE..."
    if ! dryrun_cmd qm set "$DEST_VMID" "--${SCSI_DEVICE}" "$NEW_VOLID"; then
        if qm config "$DEST_VMID" 2>/dev/null | grep -qF "$NEW_VOLID"; then ATTACHED=1; fi
        die "Could not attach the copied disk to VM $DEST_VMID."
    fi
    ATTACHED=1
}

# verify_result
# Checks the important transaction postconditions and preserves attached objects on verification failure.
verify_result() {
    if dryrun_enabled; then
        dryrun_verify "Destination LV would exist"
        dryrun_verify "VM $DEST_VMID would reference $NEW_VOLID at $SCSI_DEVICE"
        dryrun_verify "Proxmox would resolve the copied volume correctly"
        return 0
    fi
    vr_failed=0; vr_config="$(qm config "$DEST_VMID")"
    if lvs "${DEST_VG}/${NEW_LV_NAME}" >/dev/null 2>&1; then ok "Destination LV exists."; else warn "Destination LV is missing."; vr_failed=1; fi
    if printf '%s\n' "$vr_config" | grep -qE "^${SCSI_DEVICE}:.*${NEW_VOLID}([,[:space:]]|$)"; then ok "VM configuration contains $SCSI_DEVICE: $NEW_VOLID"; else warn "Expected disk attachment is missing from the VM configuration."; vr_failed=1; fi
    vr_pve_path="$(pvesm path "$NEW_VOLID" 2>/dev/null || :)"
    if [ -n "$vr_pve_path" ] && [ "$(readlink -f "$vr_pve_path")" = "$(readlink -f "$NEW_LV_PATH")" ]; then ok "Proxmox resolves the copied volume correctly."; else warn "Proxmox does not resolve the copied volume correctly."; vr_failed=1; fi
    if [ "$vr_failed" -ne 0 ]; then
        warn "The copied disk may already be attached. It has intentionally not been removed."
        die "Final verification failed."
    fi
}

############################################################
# ERROR HANDLING / CLEANUP
############################################################

# cleanup_on_exit
#
# Description:
#   Removes only an incomplete/unattached destination LV. Once the VM config
#   references the new volume, the LV is deliberately preserved for inspection.
#
# Usage:
#   Installed as the process exit/signal trap.
#
# Arguments:
#   None.
#
# Output:
#   May remove the newly-created destination LV.
#
# Returns:
#   Preserves the original failure status.
############################################################
cleanup_on_exit() {
    coe_status=$?
    trap - 0 HUP INT TERM
    if dryrun_enabled || [ "$CREATED" -eq 0 ] || [ "$ATTACHED" -eq 1 ] || [ "$COMPLETE" -eq 1 ]; then
        [ "$coe_status" -eq 0 ] || exit "$coe_status"
        return 0
    fi
    if qm config "$DEST_VMID" 2>/dev/null | grep -qF "$NEW_VOLID"; then
        warn "VM configuration references $NEW_VOLID; the LV will not be removed automatically."
        [ "$coe_status" -eq 0 ] || exit "$coe_status"
        return 0
    fi
    warn "Removing incomplete/unattached destination LV: $NEW_LV_PATH"
    set +e
    lvremove -y "${DEST_VG}/${NEW_LV_NAME}" >/dev/null 2>&1 || warn "Could not remove $NEW_LV_PATH automatically."
    set -e
    [ "$coe_status" -eq 0 ] || exit "$coe_status"
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
