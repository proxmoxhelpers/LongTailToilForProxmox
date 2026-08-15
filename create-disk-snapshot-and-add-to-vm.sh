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
    CREATED=0; ATTACHED=0; COMPLETE=0
    parse_arguments "$@"
    check_elevation
}

main() {
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    need_commands lvs lvcreate lvremove qm pvesm readlink awk grep sed sort tail mktemp
    validate_source
    validate_destination_vm
    select_storage
    select_disk_name
    SCSI_DEVICE="$(first_free_scsi "$DEST_VMID")" || die "No free SCSI disk slot is available on VM $DEST_VMID."
    TARGET_STATUS="$(qm status "$DEST_VMID" 2>/dev/null | awk '{print $2}' || :)"
    print_plan
    trap cleanup_on_exit 0
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    create_snapshot
    verify_storage_mapping
    attach_snapshot
    verify_result
    COMPLETE=1
}

end() {
    print_banner "Snapshot created and attached successfully"
    printf 'Source:          %s\n' "$SOURCE_PATH"
    printf 'Snapshot:        %s\n' "$NEW_LV_PATH"
    printf 'Proxmox volume:  %s\n' "$NEW_VOLID"
    printf 'Destination VM:  %s\n' "$DEST_VMID"
    printf 'Attached as:     %s\n' "$SCSI_DEVICE"
    printf 'VM status:       %s\n\n' "${TARGET_STATUS:-unknown}"
    dryrun_summary
}

############################################################
# COMMAND LINE
############################################################

usage() {
    cat <<EOF
create-disk-snapshot-and-add-to-vm.sh $SCRIPT_VERSION (project $PROJECT_VERSION)

USAGE
  create-disk-snapshot-and-add-to-vm.sh <source-lv-path> <destination-vmid> [dryrun]

DESCRIPTION
  Creates an LVM-thin snapshot named vm-DESTVMID-disk-N, chooses the first
  free SCSI slot independently, and attaches the snapshot to a QEMU VM.

EXAMPLE
  create-disk-snapshot-and-add-to-vm.sh /dev/thinvg/vm-132-disk-1 115

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
            *) pa_count=$((pa_count + 1)); case "$pa_count" in 1) SOURCE="$1" ;; 2) DEST_VMID="$1" ;; *) usage >&2; exit 2 ;; esac ;;
        esac
        shift
    done
    [ "$pa_count" -eq 2 ] || { usage >&2; exit 2; }
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
    SOURCE_ATTR="$(lvs --noheadings -o lv_attr "$SOURCE" 2>/dev/null | trim)"
    [ -n "$SOURCE_PATH" ] && [ -n "$SOURCE_VG" ] && [ -n "$SOURCE_LV" ] || die "Could not resolve source LV metadata."
    if [ -z "$SOURCE_POOL" ]; then
        printf 'Source:        %s\nLV attributes: %s\n' "$SOURCE_PATH" "$SOURCE_ATTR"
        die "Source is not an LVM-thin volume."
    fi
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

# select_storage
#
# Description:
#   Finds the unique Proxmox lvmthin storage matching SOURCE_VG/SOURCE_POOL
#   and accepting image content.
#
# Usage:
#   select_storage
#
# Arguments:
#   Uses SOURCE_VG and SOURCE_POOL.
#
# Output:
#   Sets STORAGE_ID.
#
# Returns:
#   0 only for an unambiguous mapping.
############################################################
select_storage() {
    [ -f /etc/pve/storage.cfg ] || die "Proxmox storage configuration not found: /etc/pve/storage.cfg"
    ss_matches="$(awk -v wanted_vg="$SOURCE_VG" -v wanted_pool="$SOURCE_POOL" '
        function flush() {
            if (type == "lvmthin" && vg == wanted_vg && pool == wanted_pool &&
                (content == "" || content ~ /(^|,)images(,|$)/)) print id
        }
        /^[^ \t][^:]*:[ \t]*/ {flush(); split($1,h,":"); type=h[1]; id=$2; vg=""; pool=""; content=""; next}
        $1=="vgname" {vg=$2; next}
        $1=="thinpool" {pool=$2; next}
        $1=="content" {content=$2; next}
        END {flush()}
    ' /etc/pve/storage.cfg)"
    ss_count="$(printf '%s\n' "$ss_matches" | awk 'NF {n++} END {print n+0}')"
    case "$ss_count" in
        0) printf 'Source VG:   %s\nSource pool: %s\n' "$SOURCE_VG" "$SOURCE_POOL"; die "Could not find a matching Proxmox lvmthin storage." ;;
        1) STORAGE_ID="$(printf '%s\n' "$ss_matches" | awk 'NF {print; exit}')" ;;
        *) printf 'Multiple matching Proxmox storages:\n%s\n' "$ss_matches" >&2; die "Storage mapping is ambiguous." ;;
    esac
}

# select_disk_name
# Chooses a disk number above the current maximum, skipping config/LVM collisions.
select_disk_name() {
    sdn_highest="$(printf '%s\n' "$TARGET_QM_CONFIG" | grep -oE "vm-${DEST_VMID}-disk-[0-9]+" | sed -E 's/.*-disk-([0-9]+)$/\1/' | sort -n | tail -n1 || :)"
    if [ -n "$sdn_highest" ]; then DISK_NUMBER=$((sdn_highest + 1)); else DISK_NUMBER=0; fi
    while :; do
        NEW_LV_NAME="vm-${DEST_VMID}-disk-${DISK_NUMBER}"
        NEW_LV_PATH="/dev/${SOURCE_VG}/${NEW_LV_NAME}"
        NEW_VOLID="${STORAGE_ID}:${NEW_LV_NAME}"
        sdn_config=0; sdn_lvm=0
        printf '%s\n' "$TARGET_QM_CONFIG" | grep -qF "$NEW_LV_NAME" && sdn_config=1 || :
        lvs "${SOURCE_VG}/${NEW_LV_NAME}" >/dev/null 2>&1 && sdn_lvm=1 || :
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
    print_banner "Create linked disk snapshot and attach to VM"
    printf 'Source LV:             %s\n' "$SOURCE_PATH"
    printf 'Source VG:             %s\n' "$SOURCE_VG"
    printf 'Thin pool:             %s\n' "$SOURCE_POOL"
    printf 'Proxmox storage:       %s\n' "$STORAGE_ID"
    printf 'Destination VM:        %s\n' "$DEST_VMID"
    printf 'Destination VM status: %s\n' "${TARGET_STATUS:-unknown}"
    printf 'New snapshot LV:       %s\n' "$NEW_LV_PATH"
    printf 'Proxmox volume ID:     %s\n' "$NEW_VOLID"
    printf 'Attach as:             %s\n\n' "$SCSI_DEVICE"
}

# create_snapshot
# Creates the LVM-thin snapshot and verifies its origin/pool metadata.
create_snapshot() {
    info "Creating LVM-thin snapshot..."
    if dryrun_enabled; then dryrun_cmd lvcreate --snapshot --name "$NEW_LV_NAME" "${SOURCE_VG}/${SOURCE_LV}"
    else run_lvm_filtered lvcreate --snapshot --name "$NEW_LV_NAME" "${SOURCE_VG}/${SOURCE_LV}"; fi
    CREATED=1
    if dryrun_enabled; then
        NEW_REAL="$NEW_LV_PATH"; NEW_ORIGIN="$SOURCE_LV"; NEW_POOL="$SOURCE_POOL"
        dryrun_verify "Snapshot LV would exist with expected origin and thin pool"
    else
        lvs "${SOURCE_VG}/${NEW_LV_NAME}" >/dev/null 2>&1 || die "lvcreate returned successfully, but the snapshot cannot be found."
        NEW_REAL="$(lvs --noheadings -o lv_path "${SOURCE_VG}/${NEW_LV_NAME}" 2>/dev/null | trim)"
        NEW_ORIGIN="$(lvs --noheadings -o origin "${SOURCE_VG}/${NEW_LV_NAME}" 2>/dev/null | trim)"
        NEW_POOL="$(lvs --noheadings -o pool_lv "${SOURCE_VG}/${NEW_LV_NAME}" 2>/dev/null | trim)"
    fi
    [ "$NEW_ORIGIN" = "$SOURCE_LV" ] && [ "$NEW_POOL" = "$SOURCE_POOL" ] || die "Snapshot origin/thin-pool verification failed."
}

# verify_storage_mapping
# Verifies the Proxmox volume ID resolves to the exact newly created LV.
verify_storage_mapping() {
    if dryrun_enabled; then PVE_PATH="$NEW_LV_PATH"; dryrun_verify "Proxmox storage $STORAGE_ID would resolve $NEW_VOLID"
    else PVE_PATH="$(pvesm path "$NEW_VOLID" 2>/dev/null || :)"; fi
    [ -n "$PVE_PATH" ] || die "Proxmox storage could not resolve the new snapshot."
    [ "$(readlink -f "$PVE_PATH")" = "$(readlink -f "$NEW_REAL")" ] || die "Proxmox storage mapping does not point to the new LV."
}

# attach_snapshot
# Attaches the verified snapshot volume ID to the selected destination VM slot.
attach_snapshot() {
    info "Attaching $NEW_VOLID to VM $DEST_VMID as $SCSI_DEVICE..."
    if ! dryrun_cmd qm set "$DEST_VMID" "--${SCSI_DEVICE}" "$NEW_VOLID"; then
        if qm config "$DEST_VMID" 2>/dev/null | grep -qF "$NEW_VOLID"; then
            ATTACHED=1
            warn "qm reported failure, but the VM config references $NEW_VOLID; the snapshot was not removed."
        fi
        die "Could not attach the snapshot to VM $DEST_VMID."
    fi
    ATTACHED=1
}

# verify_result
# Checks the important transaction postconditions and preserves attached objects on verification failure.
verify_result() {
    if dryrun_enabled; then
        dryrun_verify "Snapshot LV would exist"
        dryrun_verify "VM $DEST_VMID would reference $NEW_VOLID at $SCSI_DEVICE"
        dryrun_verify "Proxmox would resolve $NEW_VOLID"
        dryrun_verify "Snapshot origin would remain $SOURCE_LV"
        return 0
    fi

    vr_failed=0; vr_config="$(qm config "$DEST_VMID")"
    vr_origin="$(lvs --noheadings -o origin "${SOURCE_VG}/${NEW_LV_NAME}" 2>/dev/null | trim)"
    lvs "${SOURCE_VG}/${NEW_LV_NAME}" >/dev/null 2>&1 || { warn "Snapshot LV is missing."; vr_failed=1; }
    printf '%s\n' "$vr_config" | grep -qE "^${SCSI_DEVICE}:.*${NEW_VOLID}([,[:space:]]|$)" || { warn "Expected disk attachment was not found."; vr_failed=1; }
    pvesm path "$NEW_VOLID" >/dev/null 2>&1 || { warn "Proxmox cannot resolve $NEW_VOLID."; vr_failed=1; }
    [ "$vr_origin" = "$SOURCE_LV" ] || { warn "Unexpected snapshot origin: ${vr_origin:-unknown}"; vr_failed=1; }
    [ "$vr_failed" -eq 0 ] || die "Verification failed. The volume may already be attached, so it was not removed."
}

############################################################
# ERROR HANDLING / CLEANUP
############################################################

# cleanup_on_exit
# Removes only a newly created unattached object after an incomplete transaction.
cleanup_on_exit() {
    coe_status=$?
    trap - 0 HUP INT TERM
    if dryrun_enabled || [ "$CREATED" -eq 0 ] || [ "$ATTACHED" -eq 1 ] || [ "$COMPLETE" -eq 1 ]; then
        [ "$coe_status" -eq 0 ] || exit "$coe_status"
        return 0
    fi
    if qm config "$DEST_VMID" 2>/dev/null | grep -qF "$NEW_VOLID"; then
        warn "VM configuration references $NEW_VOLID; refusing automatic snapshot removal."
        [ "$coe_status" -eq 0 ] || exit "$coe_status"
        return 0
    fi
    warn "Removing incomplete/unattached snapshot: $NEW_LV_PATH"
    set +e
    lvremove -y "${SOURCE_VG}/${NEW_LV_NAME}" >/dev/null 2>&1 || warn "Could not remove $NEW_LV_PATH automatically."
    set -e
    [ "$coe_status" -eq 0 ] || exit "$coe_status"
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
