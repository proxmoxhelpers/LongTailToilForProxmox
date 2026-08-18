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
    PROJECT_VERSION="3.4.7"
    TEST_SUITE_VERSION="2.8.5"
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
    run_case "mount-vm-drives.sh direct read-only" test_mount_vm_drives
    run_case "unmount-vm-drives.sh direct filesystem" test_unmount_vm_drives
    run_case "mount-vm-drives.sh read-write on disposable LV" test_mount_vm_drives_rw
    run_case "mount-vm-disk.sh direct filesystem" test_mount_vm_disk
    run_case "mount-vm-disk.sh partitioned disk via kpartx" test_mount_vm_disk_partitioned
    run_case "mount-vm-root.sh" test_mount_vm_root
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

test_mount_vm_drives() {
    tmvd_root="$TEST_DATA_DIR/direct-mount"
    run_dryrun_unchanged "mount-vm-drives" mount-vm-drives.sh "$MOUNT_LV" "$tmvd_root" --ro
    project_cmd mount-vm-drives.sh "$MOUNT_LV" "$tmvd_root" --ro
    mountpoint -q "$tmvd_root/part1"
    [ -f "$tmvd_root/part1/etc/os-release" ]
    project_cmd unmount-vm-drives.sh "$MOUNT_LV"
    ! mountpoint -q "$tmvd_root/part1"
}

test_unmount_vm_drives() {
    tuv_root="$TEST_DATA_DIR/unmount-fixture"
    mkdir -p "$tuv_root"
    mount -o ro "$MOUNT_LV" "$tuv_root"
    mountpoint -q "$tuv_root" || return 1
    run_dryrun_unchanged "unmount-vm-drives" unmount-vm-drives.sh "$MOUNT_LV"
    mountpoint -q "$tuv_root" || { printf 'Dry-run unexpectedly unmounted the filesystem.\n' >&2; return 1; }
    project_cmd unmount-vm-drives.sh "$MOUNT_LV"
    ! mountpoint -q "$tuv_root"
}

test_mount_vm_drives_rw() {
    tmvrw_root="$TEST_DATA_DIR/direct-rw"
    run_dryrun_unchanged "mount-vm-drives-rw" mount-vm-drives.sh "$MOUNT_LV" "$tmvrw_root" --rw
    project_cmd mount-vm-drives.sh "$MOUNT_LV" "$tmvrw_root" --rw
    mountpoint -q "$tmvrw_root/part1"
    printf '%s\n' "rw-test-${TEST_TOKEN}" > "$tmvrw_root/part1/rw-test.txt"
    sync
    project_cmd unmount-vm-drives.sh "$MOUNT_LV"
    ! mountpoint -q "$tmvrw_root/part1"

    tmvrw_verify="$TEST_DATA_DIR/direct-rw-verify"
    project_cmd mount-vm-drives.sh "$MOUNT_LV" "$tmvrw_verify" --ro
    grep -Fx "rw-test-${TEST_TOKEN}" "$tmvrw_verify/part1/rw-test.txt" >/dev/null
    project_cmd unmount-vm-drives.sh "$MOUNT_LV"
}

test_mount_vm_disk() {
    tmvd_root="$TEST_DATA_DIR/vm-disk-mount"
    run_dryrun_unchanged "mount-vm-disk" mount-vm-disk.sh "$MOUNT_VM" scsi0 "$tmvd_root" --ro
    project_cmd mount-vm-disk.sh "$MOUNT_VM" scsi0 "$tmvd_root" --ro
    mountpoint -q "$tmvd_root/part1"
    [ -f "$tmvd_root/part1/etc/os-release" ]
    project_cmd unmount-vm-drives.sh "$MOUNT_LV"
}

test_mount_vm_disk_partitioned() {
    tmvp_root="$TEST_DATA_DIR/partitioned-mount"
    run_dryrun_unchanged "mount-vm-disk-partitioned" mount-vm-disk.sh "$MOUNT_VM" scsi1 "$tmvp_root" --ro
    project_cmd mount-vm-disk.sh "$MOUNT_VM" scsi1 "$tmvp_root" --ro
    mountpoint -q "$tmvp_root/part1"
    grep -F "partitioned proxmox-lvm-tools" "$tmvp_root/part1/etc/os-release" >/dev/null
    [ -e "/dev/mapper/$MOUNT_PART_MAP" ]
    project_cmd unmount-vm-drives.sh "$MOUNT_PART_LV"
    ! mountpoint -q "$tmvp_root/part1"
    [ ! -e "/dev/mapper/$MOUNT_PART_MAP" ]
}

test_mount_vm_root() {
    tmvr_root="$TEST_DATA_DIR/vm-root-mount"
    tmvr_out="$TEST_RESULT_DIR/mount-vm-root-output.txt"
    run_dryrun_unchanged "mount-vm-root" mount-vm-root.sh "$MOUNT_VM" scsi0 "$tmvr_root" --ro
    project_cmd mount-vm-root.sh "$MOUNT_VM" scsi0 "$tmvr_root" --ro > "$tmvr_out"
    mountpoint -q "$tmvr_root/part1"
    grep -F "Linux root" "$tmvr_out" >/dev/null
    project_cmd unmount-vm-drives.sh "$MOUNT_LV"
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
