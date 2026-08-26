#!/bin/sh
set -eu
SCRIPT_DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
TEST_ROOT="$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(CDPATH= cd "$TEST_ROOT/.." && pwd)"
. "$TEST_ROOT/lib/test-common.sh"

setup() {
    define_colours
    PROJECT_VERSION="3.7.1"; TEST_SUITE_VERSION="3.1.1"; TEST_GROUP="qol-workflows"
    test_reset_counters; test_parse_arguments "$@"
    [ "$TEST_RUN" = "false" ] || check_elevation
}
main() {
    [ "$TEST_RUN" = "true" ] || { print_plan; return 0; }
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    require_proxmox_environment
    for CMD in dd cmp tar mkfs.ext4 qemu-img findmnt mount umount; do require_command "$CMD"; done
    test_prepare_run; create_storage_sandbox
    run_case "plan-vm-storage-move.sh reports source/destination" test_plan_move
    run_case "migrate-vm-storage-layout.sh stopped VM move" test_migrate_layout
    run_case "clone-vm-storage-only.sh copies active source disks" test_clone_storage
    run_case "clone-vm-storage-only.sh restores inactive base source activation" test_clone_storage_inactive_base
    run_case "rebuild-vm-from-existing-disks.sh explicit apply" test_rebuild
    run_case "mount-all-vm-drives.sh + unmount-all-vm-drives.sh lifecycle" test_mount_all_lifecycle
    run_case "export-vm-filesystem.sh read-only archive" test_export_fs
    run_case "for-each-vm.sh constrained dry-run dispatcher" test_for_each
}
end() {
    [ "$TEST_RUN" = "true" ] || return 0
    [ "${APP_ELEVATED:-false}" = "true" ] || return 0
    test_finish_run
}
print_plan() {
    print_banner "v3.6 higher-level workflow tests"
    printf '%s\n' "Exercises storage planning/migration, storage-only cloning, disk-based rebuild, filesystem export and safe bulk dispatch."
    printf '%s\n' "All objects are stopped and test-owned; mount-all exercises a real mount/unmount lifecycle plus dry-run immutability."
}
make_vm_disk() {
    mvd_role="$1"; mvd_storage="$2"; mvd_vg="$3"; mvd_num="${4:-0}"
    mvd_vm="$(create_test_vm "$mvd_role")"
    mvd_name="vm-${mvd_vm}-disk-${mvd_num}"
    mvd_path="$(create_thin_lv "$mvd_vg" "$mvd_name" 32M)"
    write_test_pattern "$mvd_path" "$mvd_role"
    attach_test_lv "$mvd_vm" "$mvd_storage" "$mvd_name" scsi0
    printf '%s|%s|%s\n' "$mvd_vm" "$mvd_name" "$mvd_path"
}
test_plan_move() {
    tpm_rec="$(make_vm_disk "plan-move" "$TEST_STORAGE_A" "$TEST_VG_A" 0)"
    tpm_vm="${tpm_rec%%|*}"
    project_cmd plan-vm-storage-move.sh "$tpm_vm" "$TEST_STORAGE_B" >"$TEST_DATA_DIR/plan-move.txt"
    grep -F "$TEST_STORAGE_B" "$TEST_DATA_DIR/plan-move.txt" >/dev/null
}
test_migrate_layout() {
    tml_rec="$(make_vm_disk "migrate-layout" "$TEST_STORAGE_A" "$TEST_VG_A" 0)"
    tml_vm="${tml_rec%%|*}"; tml_rest="${tml_rec#*|}"; tml_name="${tml_rest%%|*}"
    run_dryrun_unchanged "migrate-vm-storage-layout" migrate-vm-storage-layout.sh "$tml_vm" "$TEST_STORAGE_B"
    project_cmd migrate-vm-storage-layout.sh "$tml_vm" "$TEST_STORAGE_B"
    qm config "$tml_vm" | sed -n 's/^scsi0:[[:space:]]*//p' | grep -F "$TEST_STORAGE_B:" >/dev/null
}
test_clone_storage() {
    tcs_src_rec="$(make_vm_disk "clone-storage-src" "$TEST_STORAGE_A" "$TEST_VG_A" 0)"
    tcs_src="${tcs_src_rec%%|*}"; tcs_dst="$(create_test_vm "clone-storage-dst")"
    run_dryrun_unchanged "clone-vm-storage-only" clone-vm-storage-only.sh "$tcs_src" "$tcs_dst" --storage "$TEST_STORAGE_B"
    project_cmd clone-vm-storage-only.sh "$tcs_src" "$tcs_dst" --storage "$TEST_STORAGE_B"
    tcs_src_path="$(pvesm path "$(qm config "$tcs_src" | sed -n 's/^scsi0:[[:space:]]*//p' | cut -d, -f1)")"
    tcs_dst_vol="$(qm config "$tcs_dst" | sed -n 's/^scsi0:[[:space:]]*//p' | cut -d, -f1)"
    tcs_dst_path="$(pvesm path "$tcs_dst_vol")"
    cmp "$tcs_src_path" "$tcs_dst_path"
}
test_clone_storage_inactive_base() {
    tcsi_src="$(create_test_vm "clone-storage-inactive-src")"
    tcsi_dst="$(create_test_vm "clone-storage-inactive-dst")"
    tcsi_name="base-${tcsi_src}-disk-0"
    tcsi_path="$(create_thin_lv "$TEST_VG_A" "$tcsi_name" 32M)"
    write_test_pattern "$tcsi_path" "clone-storage-inactive"
    attach_test_lv "$tcsi_src" "$TEST_STORAGE_A" "$tcsi_name" scsi0
    lvchange -an "$TEST_VG_A/$tcsi_name"
    [ ! -b "$tcsi_path" ] || return 1

    run_dryrun_unchanged "clone-vm-storage-only inactive base" clone-vm-storage-only.sh "$tcsi_src" "$tcsi_dst" --storage "$TEST_STORAGE_B"
    [ ! -b "$tcsi_path" ] || return 1
    project_cmd clone-vm-storage-only.sh "$tcsi_src" "$tcsi_dst" --storage "$TEST_STORAGE_B"
    [ ! -b "$tcsi_path" ] || return 1

    tcsi_dst_vol="$(qm config "$tcsi_dst" | sed -n 's/^scsi0:[[:space:]]*//p' | cut -d, -f1)"
    tcsi_dst_path="$(pvesm path "$tcsi_dst_vol")"
    lvchange -ay -K "$TEST_VG_A/$tcsi_name"
    cmp "$tcsi_path" "$tcsi_dst_path"
    lvchange -an "$TEST_VG_A/$tcsi_name"
}

test_rebuild() {
    trb_id="$(allocate_free_vmid)" || return 1
    trb_name="plvt-${TEST_TOKEN}-rebuilt"
    trb_lv="vm-${trb_id}-disk-0"
    trb_path="$(create_thin_lv "$TEST_VG_A" "$trb_lv" 16M)"; write_test_pattern "$trb_path" rebuild
    run_dryrun_unchanged "rebuild-vm-from-existing-disks" rebuild-vm-from-existing-disks.sh "$trb_id" --name "$trb_name" --apply
    project_cmd rebuild-vm-from-existing-disks.sh "$trb_id" --name "$trb_name" --apply
    register_owned_vm "$trb_id" "$trb_name"
    qm config "$trb_id" | grep -F "$TEST_STORAGE_A:$trb_lv" >/dev/null
}
test_mount_all_lifecycle() {
    tma_vm="$(create_test_vm "mount-all")"; tma_name="vm-${tma_vm}-disk-0"
    tma_lv="$(create_thin_lv "$TEST_VG_A" "$tma_name" 32M)"; mkfs.ext4 -F "$tma_lv" >/dev/null 2>&1
    attach_test_lv "$tma_vm" "$TEST_STORAGE_A" "$tma_name" scsi0
    tma_root="$TEST_DATA_DIR/mount-all"
    run_dryrun_unchanged "mount-all-vm-drives" mount-all-vm-drives.sh "$tma_vm" "$tma_root"
    project_cmd mount-all-vm-drives.sh "$tma_vm" "$tma_root"
    findmnt -rn -M "$tma_root/scsi0/whole" >/dev/null 2>&1
    run_dryrun_unchanged "unmount-all-vm-drives" unmount-all-vm-drives.sh "$tma_vm" "$tma_root"
    project_cmd unmount-all-vm-drives.sh "$tma_vm" "$tma_root"
    ! findmnt -rn -M "$tma_root/scsi0/whole" >/dev/null 2>&1
}
test_export_fs() {
    tef_vm="$(create_test_vm "export-fs")"; tef_name="vm-${tef_vm}-disk-0"
    tef_seed="$TEST_DATA_DIR/export-seed"; mkdir -p "$tef_seed"; printf '%s\n' "longtailtoil-export-test" >"$tef_seed/marker.txt"
    tef_lv="$(create_thin_lv "$TEST_VG_A" "$tef_name" 32M)"
    mkfs.ext4 -F -d "$tef_seed" "$tef_lv" >/dev/null 2>&1
    attach_test_lv "$tef_vm" "$TEST_STORAGE_A" "$tef_name" scsi0
    tef_out="$TEST_DATA_DIR/filesystem.tar"
    run_dryrun_unchanged "export-vm-filesystem" export-vm-filesystem.sh "$tef_vm" scsi0 "$tef_out"
    project_cmd export-vm-filesystem.sh "$tef_vm" scsi0 "$tef_out"
    tar -tf "$tef_out" | grep -E '(^|/)marker\.txt$' >/dev/null
}
test_for_each() {
    tfe_vm="$(create_test_vm "foreach")"
    run_dryrun_unchanged "for-each-vm" for-each-vm.sh --range "${tfe_vm}-${tfe_vm}" --type qemu -- /bin/true '{}'
}

setup "$@"; main "$@"; end
