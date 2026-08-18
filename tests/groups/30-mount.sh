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
    PROJECT_VERSION="3.3.0"
    TEST_SUITE_VERSION="2.4.0"
    TEST_GROUP="mount"
    test_reset_counters
    test_parse_arguments "$@"
    [ "$TEST_RUN" = "false" ] || check_elevation
}

main() {
    [ "$TEST_RUN" = "true" ] || { print_plan; return 0; }
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    require_proxmox_environment
    for CMD in mkfs.ext4 mount umount kpartx blkid; do require_command "$CMD"; done
    test_prepare_run
    create_storage_sandbox
    prepare_mount_fixture
    run_case "mount-vm-drives.sh" test_mount_vm_drives
    run_case "unmount-vm-drives.sh" test_unmount_vm_drives
    run_case "mount-vm-disk.sh" test_mount_vm_disk
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
    printf '%s\n' "Creates one 64 MiB ext4 filesystem inside a disposable thin LV."
    printf '%s\n' "The filesystem contains synthetic /etc and /usr directories so root detection is testable."
    printf '%s\n' "Tests direct LV mount/unmount, VM-slot resolution, and Linux-root detection."
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
}

test_unmount_vm_drives() {
    tuv_root="$TEST_DATA_DIR/direct-mount"
    mountpoint -q "$tuv_root/part1" || { printf 'Expected fixture mount is not active.\n' >&2; return 1; }
    run_dryrun_unchanged "unmount-vm-drives" unmount-vm-drives.sh "$MOUNT_LV"
    mountpoint -q "$tuv_root/part1" || { printf 'Dry-run unexpectedly unmounted the filesystem.\n' >&2; return 1; }
    project_cmd unmount-vm-drives.sh "$MOUNT_LV"
    ! mountpoint -q "$tuv_root/part1"
}

test_mount_vm_disk() {
    tmvd_root="$TEST_DATA_DIR/vm-disk-mount"
    run_dryrun_unchanged "mount-vm-disk" mount-vm-disk.sh "$MOUNT_VM" scsi0 "$tmvd_root" --ro
    project_cmd mount-vm-disk.sh "$MOUNT_VM" scsi0 "$tmvd_root" --ro
    mountpoint -q "$tmvd_root/part1"
    [ -f "$tmvd_root/part1/etc/os-release" ]
    project_cmd unmount-vm-drives.sh "$MOUNT_LV"
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
