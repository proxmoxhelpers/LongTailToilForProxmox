#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
TEST_ROOT="$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(CDPATH= cd "$TEST_ROOT/.." && pwd)"
. "$TEST_ROOT/lib/test-common.sh"

setup() {
    define_colours
    PROJECT_VERSION="3.7.1"; TEST_SUITE_VERSION="3.1.1"; TEST_GROUP="qol-inspection"
    test_reset_counters
    test_parse_arguments "$@"
    [ "$TEST_RUN" = "false" ] || check_elevation
}

main() {
    [ "$TEST_RUN" = "true" ] || { print_plan; return 0; }
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    require_proxmox_environment
    for CMD in partx blkid sha256sum mkfs.ext4; do require_command "$CMD"; done
    test_prepare_run
    create_storage_sandbox
    prepare_fixture
    run_case "verify-vm-storage-consistency.sh clean fixture" test_consistency
    run_case "show-vm-storage-map.sh text/JSON" test_storage_map
    run_case "compare-vm-disks.sh same disk" test_compare
    run_case "verify-vm-disk-content.sh ext4 disk" test_disk_content
    run_case "show-thin-snapshot-tree.sh disposable VG" test_thin_tree
    run_case "find-shared-vm-volumes.sh read-only inventory" test_shared_inventory
    run_case "find-unreferenced-managed-volumes.sh finds fixture" test_unreferenced
    run_case "audit-vm-boot-config.sh valid boot order" test_boot_audit
    run_case "show-vm-filesystem-layout.sh ext4 disk" test_fs_layout
    run_case "find-vm-root-filesystem.sh candidates" test_root_candidates
    run_case "show-last-operation.sh explicit journal" test_operation_journal
}

end() {
    [ "$TEST_RUN" = "true" ] || return 0
    [ "${APP_ELEVATED:-false}" = "true" ] || return 0
    test_finish_run
}

print_plan() {
    print_banner "v3.6 QoL inspection tests"
    printf '%s\n' "Creates one stopped VM and test-owned LVM-thin volumes."
    printf '%s\n' "Runs every new read-only consistency/topology/content helper against disposable state."
}

prepare_fixture() {
    QI_VM="$(create_test_vm "qol-inspect")"
    QI_LV_NAME="vm-${QI_VM}-disk-0"
    QI_LV="$(create_thin_lv "$TEST_VG_A" "$QI_LV_NAME" 64M)"
    mkfs.ext4 -F "$QI_LV" >/dev/null 2>&1
    attach_test_lv "$QI_VM" "$TEST_STORAGE_A" "$QI_LV_NAME" scsi0
    qm set "$QI_VM" --boot order=scsi0 >/dev/null
    QI_ORPHAN="vm-${QI_VM}-disk-77"
    create_thin_lv "$TEST_VG_A" "$QI_ORPHAN" 16M >/dev/null
}

test_consistency() { project_cmd verify-vm-storage-consistency.sh "$QI_VM" >/dev/null; }
test_storage_map() {
    project_cmd show-vm-storage-map.sh "$QI_VM" >"$TEST_DATA_DIR/storage-map.txt"
    project_cmd show-vm-storage-map.sh "$QI_VM" --json >"$TEST_DATA_DIR/storage-map.json"
    grep -F "$QI_LV_NAME" "$TEST_DATA_DIR/storage-map.txt" >/dev/null
}
test_compare() { project_cmd compare-vm-disks.sh "$QI_VM:scsi0" "$QI_VM:scsi0" --full >/dev/null; }
test_disk_content() { project_cmd verify-vm-disk-content.sh "$QI_VM:scsi0" >/dev/null; }
test_thin_tree() { project_cmd show-thin-snapshot-tree.sh --vg "$TEST_VG_A" >"$TEST_DATA_DIR/thin-tree.txt"; grep -F "$QI_LV_NAME" "$TEST_DATA_DIR/thin-tree.txt" >/dev/null; }
test_shared_inventory() { project_cmd find-shared-vm-volumes.sh --tsv >"$TEST_DATA_DIR/shared.tsv"; }
test_unreferenced() { project_cmd find-unreferenced-managed-volumes.sh --vg "$TEST_VG_A" >"$TEST_DATA_DIR/unreferenced.txt"; grep -F "$QI_ORPHAN" "$TEST_DATA_DIR/unreferenced.txt" >/dev/null; }
test_boot_audit() { project_cmd audit-vm-boot-config.sh "$QI_VM" >/dev/null; }
test_fs_layout() { project_cmd show-vm-filesystem-layout.sh "$QI_VM" >"$TEST_DATA_DIR/fs-layout.txt"; grep -F "ext4" "$TEST_DATA_DIR/fs-layout.txt" >/dev/null; }
test_root_candidates() { project_cmd find-vm-root-filesystem.sh "$QI_VM" >"$TEST_DATA_DIR/root-candidates.txt"; grep -F "ext4" "$TEST_DATA_DIR/root-candidates.txt" >/dev/null; }
test_operation_journal() {
    toj_dir="$TEST_DATA_DIR/journals"; mkdir -p "$toj_dir"
    printf '%s\n' "operation=qol-inspection" >"$toj_dir/demo.journal"
    ln -s demo.journal "$toj_dir/latest"
    LONGTAILTOIL_JOURNAL_DIR="$toj_dir" project_cmd show-last-operation.sh demo >"$TEST_DATA_DIR/journal.txt"
    grep -F "operation=qol-inspection" "$TEST_DATA_DIR/journal.txt" >/dev/null
}

setup "$@"
main "$@"
end
