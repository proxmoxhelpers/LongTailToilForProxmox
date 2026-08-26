#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
TEST_ROOT="$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(CDPATH= cd "$TEST_ROOT/.." && pwd)"
. "$TEST_ROOT/lib/test-common.sh"

############################################################
# SETUP / MAIN / END
############################################################

setup() {
    define_colours
    PROJECT_VERSION="3.7.1"
    TEST_SUITE_VERSION="3.1.1"
    TEST_GROUP="mount"
    test_reset_counters
    test_parse_arguments "$@"
    [ "$TEST_RUN" = "false" ] || check_elevation
}

main() {
    [ "$TEST_RUN" = "true" ] || { print_plan; return 0; }
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    require_proxmox_environment
    for CMD in mkfs.ext4 mount umount kpartx blkid sfdisk partx truncate dd dmsetup; do require_command "$CMD"; done
    test_prepare_run
    create_storage_sandbox
    prepare_mount_fixture
    run_case "mount-lvm-drives.sh direct read-only" test_mount_lvm_drives
    run_case "unmount-lvm-drives.sh direct filesystem" test_unmount_lvm_drives
    run_case "mount-lvm-drives.sh read-write on disposable LV" test_mount_lvm_drives_rw
    run_case "mount-vm-drive.sh direct filesystem + root-role detection" test_mount_vm_drive
    run_case "mount-vm-drive.sh partitioned disk via kpartx" test_mount_vm_drive_partitioned
    run_case "mount-all-vm-drives.sh + unmount-all-vm-drives.sh all-disk lifecycle" test_mount_all_vm_drives
}

end() {
    [ "$TEST_RUN" = "true" ] || return 0
    [ "${APP_ELEVATED:-false}" = "true" ] || return 0
    test_finish_run
}

############################################################
# TEST PLAN
############################################################

print_plan() {
    print_banner "Mount / filesystem tests"
    printf '%s\n' "Creates a direct ext4 LV plus a GPT-partitioned ext4 LV, both inside disposable thin storage."
    printf '%s\n' "Synthetic /etc and /usr content makes Linux-root detection testable without using a real guest disk."
    printf '%s\n' "Covers read-only default behavior, explicit read-write mode, direct-LV mounting, kpartx partition mapping/unmapping, VM-slot resolution and root detection."
}

############################################################
# FIXTURE
############################################################

prepare_mount_fixture() {
    MOUNT_VM="$(create_test_vm mount)"
    MOUNT_LV_NAME="vm-${MOUNT_VM}-disk-0"
    MOUNT_LV="$(create_thin_lv "$TEST_VG_A" "$MOUNT_LV_NAME" 64M)"
    mkfs.ext4 -F -q "$MOUNT_LV"
    mkdir -p "$TEST_DATA_DIR/seed"
    mount "$MOUNT_LV" "$TEST_DATA_DIR/seed"
    mkdir -p "$TEST_DATA_DIR/seed/etc" "$TEST_DATA_DIR/seed/usr"
    printf '%s\n' "proxmox-lvm-tools test filesystem" > "$TEST_DATA_DIR/seed/etc/os-release"
    sync
    umount "$TEST_DATA_DIR/seed"
    rmdir "$TEST_DATA_DIR/seed"
    attach_test_lv "$MOUNT_VM" "$TEST_STORAGE_A" "$MOUNT_LV_NAME" scsi0

    MOUNT_PART_LV_NAME="vm-${MOUNT_VM}-disk-1"
    MOUNT_PART_LV="$(create_thin_lv "$TEST_VG_A" "$MOUNT_PART_LV_NAME" 96M)"
    printf '%s\n' 'label: gpt' 'size=64M,type=0FC63DAF-8483-4772-8E79-3D69D8477DE4' | sfdisk "$MOUNT_PART_LV" >/dev/null 2>&1
    MOUNT_PART_IMAGE="$TEST_DATA_DIR/partition-root.img"
    truncate -s 48M "$MOUNT_PART_IMAGE"
    mkfs.ext4 -F -q "$MOUNT_PART_IMAGE"
    mkdir -p "$TEST_DATA_DIR/partition-seed"
    mount -o loop "$MOUNT_PART_IMAGE" "$TEST_DATA_DIR/partition-seed"
    mkdir -p "$TEST_DATA_DIR/partition-seed/etc" "$TEST_DATA_DIR/partition-seed/usr"
    printf '%s\n' "partitioned proxmox-lvm-tools test filesystem" > "$TEST_DATA_DIR/partition-seed/etc/os-release"
    sync
    umount "$TEST_DATA_DIR/partition-seed"
    rmdir "$TEST_DATA_DIR/partition-seed"
    MOUNT_PART_SECTOR="$(blockdev --getss "$MOUNT_PART_LV")"
    MOUNT_PART_START="$(partx --show --noheadings -o NR,START "$MOUNT_PART_LV" | awk '$1==1 {print $2; exit}')"
    [ -n "$MOUNT_PART_START" ] || die "Could not determine test partition offset."
    dd if="$MOUNT_PART_IMAGE" of="$MOUNT_PART_LV" bs="$MOUNT_PART_SECTOR" seek="$MOUNT_PART_START" conv=notrunc,fsync 2>/dev/null
    MOUNT_PART_MAP="$(kpartx -l "$MOUNT_PART_LV" | awk 'NR==1 {print $1}')"
    [ -n "$MOUNT_PART_MAP" ] || die "Could not predict kpartx map name for disposable partitioned LV."
    attach_test_lv "$MOUNT_VM" "$TEST_STORAGE_A" "$MOUNT_PART_LV_NAME" scsi1
}

############################################################
# TEST CASES
############################################################

test_mount_lvm_drives() {
    tmld_root="$TEST_DATA_DIR/direct-mount"
    run_dryrun_unchanged "mount-lvm-drives" mount-lvm-drives.sh "$MOUNT_LV" "$tmld_root" --ro
    project_cmd mount-lvm-drives.sh "$MOUNT_LV" "$tmld_root" --ro
    mountpoint -q "$tmld_root/part1"
    [ -f "$tmld_root/part1/etc/os-release" ]
    project_cmd unmount-lvm-drives.sh "$MOUNT_LV"
    ! mountpoint -q "$tmld_root/part1"
}

test_unmount_lvm_drives() {
    tuld_root="$TEST_DATA_DIR/unmount-fixture"
    mkdir -p "$tuld_root"
    mount -o ro "$MOUNT_LV" "$tuld_root"
    mountpoint -q "$tuld_root" || return 1
    run_dryrun_unchanged "unmount-lvm-drives" unmount-lvm-drives.sh "$MOUNT_LV"
    mountpoint -q "$tuld_root" || {
        printf 'Dry-run unexpectedly unmounted the filesystem.\n' >&2
        return 1
    }
    project_cmd unmount-lvm-drives.sh "$MOUNT_LV"
    ! mountpoint -q "$tuld_root"
}

test_mount_lvm_drives_rw() {
    tmlrw_root="$TEST_DATA_DIR/direct-rw"
    run_dryrun_unchanged "mount-lvm-drives-rw" mount-lvm-drives.sh "$MOUNT_LV" "$tmlrw_root" --rw
    project_cmd mount-lvm-drives.sh "$MOUNT_LV" "$tmlrw_root" --rw
    mountpoint -q "$tmlrw_root/part1"
    printf '%s\n' "rw-test-${TEST_TOKEN}" > "$tmlrw_root/part1/rw-test.txt"
    sync
    project_cmd unmount-lvm-drives.sh "$MOUNT_LV"
    ! mountpoint -q "$tmlrw_root/part1"

    tmlrw_verify="$TEST_DATA_DIR/direct-rw-verify"
    project_cmd mount-lvm-drives.sh "$MOUNT_LV" "$tmlrw_verify" --ro
    grep -Fx "rw-test-${TEST_TOKEN}" "$tmlrw_verify/part1/rw-test.txt" >/dev/null
    project_cmd unmount-lvm-drives.sh "$MOUNT_LV"
}

test_mount_vm_drive() {
    tmvd_root="$TEST_DATA_DIR/vm-drive-mount"
    tmvd_out="$TEST_RESULT_DIR/mount-vm-drive-output.txt"
    run_dryrun_unchanged "mount-vm-drive" mount-vm-drive.sh "$MOUNT_VM" scsi0 "$tmvd_root" --ro
    project_cmd mount-vm-drive.sh "$MOUNT_VM" scsi0 "$tmvd_root" --ro > "$tmvd_out"
    mountpoint -q "$tmvd_root/scsi0/whole"
    [ -f "$tmvd_root/scsi0/whole/etc/os-release" ]
    grep -F "Linux root" "$tmvd_out" >/dev/null
    grep -F "Most likely Linux root:" "$tmvd_out" >/dev/null
    [ -f "$tmvd_root/.longtailtoil-mounts-${MOUNT_VM}.state" ]
    run_dryrun_unchanged "unmount-all-vm-drives-single" unmount-all-vm-drives.sh "$MOUNT_VM" "$tmvd_root"
    mountpoint -q "$tmvd_root/scsi0/whole"
    project_cmd unmount-all-vm-drives.sh "$MOUNT_VM" "$tmvd_root"
    ! mountpoint -q "$tmvd_root/scsi0/whole"
    [ ! -e "$tmvd_root/.longtailtoil-mounts-${MOUNT_VM}.state" ]
}

test_mount_vm_drive_partitioned() {
    tmvdp_root="$TEST_DATA_DIR/partitioned-mount"
    run_dryrun_unchanged "mount-vm-drive-partitioned" mount-vm-drive.sh "$MOUNT_VM" scsi1 "$tmvdp_root" --ro
    project_cmd mount-vm-drive.sh "$MOUNT_VM" scsi1 "$tmvdp_root" --ro
    mountpoint -q "$tmvdp_root/scsi1/part1"
    grep -F "partitioned proxmox-lvm-tools" "$tmvdp_root/scsi1/part1/etc/os-release" >/dev/null
    [ -e "/dev/mapper/$MOUNT_PART_MAP" ]
    project_cmd unmount-all-vm-drives.sh "$MOUNT_VM" "$tmvdp_root"
    ! mountpoint -q "$tmvdp_root/scsi1/part1"
    [ ! -e "/dev/mapper/$MOUNT_PART_MAP" ]
}

test_mount_all_vm_drives() {
    tmavd_root="$TEST_DATA_DIR/all-drives-mount"
    tmavd_out="$TEST_RESULT_DIR/mount-all-vm-drives-output.txt"
    run_dryrun_unchanged "mount-all-vm-drives" mount-all-vm-drives.sh "$MOUNT_VM" "$tmavd_root" --ro
    project_cmd mount-all-vm-drives.sh "$MOUNT_VM" "$tmavd_root" --ro > "$tmavd_out"
    mountpoint -q "$tmavd_root/scsi0/whole"
    mountpoint -q "$tmavd_root/scsi1/part1"
    grep -F "Most likely Linux root:" "$tmavd_out" >/dev/null
    [ -f "$tmavd_root/.longtailtoil-mounts-${MOUNT_VM}.state" ]
    run_dryrun_unchanged "unmount-all-vm-drives" unmount-all-vm-drives.sh "$MOUNT_VM" "$tmavd_root"
    mountpoint -q "$tmavd_root/scsi0/whole"
    project_cmd unmount-all-vm-drives.sh "$MOUNT_VM" "$tmavd_root"
    ! mountpoint -q "$tmavd_root/scsi0/whole"
    ! mountpoint -q "$tmavd_root/scsi1/part1"
    [ ! -e "$tmavd_root/.longtailtoil-mounts-${MOUNT_VM}.state" ]
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
