#!/bin/sh
set -eu
SCRIPT_DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
TEST_ROOT="$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(CDPATH= cd "$TEST_ROOT/.." && pwd)"
. "$TEST_ROOT/lib/test-common.sh"

setup() {
    define_colours
    PROJECT_VERSION="3.7.1"; TEST_SUITE_VERSION="3.1.1"; TEST_GROUP="qol-disk-config"
    test_reset_counters; test_parse_arguments "$@"
    [ "$TEST_RUN" = "false" ] || check_elevation
}
main() {
    [ "$TEST_RUN" = "true" ] || { print_plan; return 0; }
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    require_proxmox_environment
    for CMD in dd cmp lvcreate lvrename; do require_command "$CMD"; done
    test_prepare_run; create_storage_sandbox; add_storage_alias
    run_case "repair-vm-storage-consistency.sh exact stale-VMID repair" test_repair
    run_case "resize-vm-disk.sh grow-only disk resize" test_resize
    run_case "remove/add config-only disk reference primitives" test_reference_primitives
    run_case "rename-unused-disk-reference.sh same-LV alias rewrite" test_rename_unused
    run_case "copy-vm-disk-options.sh preserves destination backing volume" test_copy_options
    run_case "normalize-vm-disk-options.sh conservative no-op/cleanup path" test_normalize_options
    run_case "renumber-vm-device-slots.sh compacts device positions" test_renumber_slots
    run_case "sort-vm-disk-slots.sh orders slots by managed disk number" test_sort_slots
    run_case "flatten-vm-disk.sh severs thin origin while preserving old disk" test_flatten
}
end() {
    [ "$TEST_RUN" = "true" ] || return 0
    [ "${APP_ELEVATED:-false}" = "true" ] || return 0
    test_finish_run
}
print_plan() {
    print_banner "v3.6 VM disk-config/recovery tests"
    printf '%s\n' "Every mutating helper runs through exact-state dryrun proof before its disposable real case."
    printf '%s\n' "Config-only helpers verify that backing LVs remain present; flatten keeps its linked source."
}

test_repair() {
    tr_vm="$(create_test_vm "repair")"; tr_foreign=$((tr_vm + 50000))
    tr_old="vm-${tr_foreign}-disk-0"; tr_new="vm-${tr_vm}-disk-0"
    create_thin_lv "$TEST_VG_A" "$tr_old" 16M >/dev/null
    attach_test_lv "$tr_vm" "$TEST_STORAGE_A" "$tr_old" scsi0
    run_dryrun_unchanged "repair-storage-consistency" repair-vm-storage-consistency.sh "$tr_vm" --apply
    project_cmd repair-vm-storage-consistency.sh "$tr_vm" --apply
    assert_lv_absent "$TEST_VG_A/$tr_old"; assert_lv_exists "$TEST_VG_A/$tr_new"
    qm config "$tr_vm" | grep -F "$TEST_STORAGE_A:$tr_new" >/dev/null
}
test_resize() {
    trz_vm="$(create_test_vm "resize")"; trz_name="vm-${trz_vm}-disk-0"
    trz_lv="$(create_thin_lv "$TEST_VG_A" "$trz_name" 32M)"; attach_test_lv "$trz_vm" "$TEST_STORAGE_A" "$trz_name" scsi0
    trz_before="$(blockdev --getsize64 "$trz_lv")"
    run_dryrun_unchanged "resize-vm-disk" resize-vm-disk.sh "$trz_vm" scsi0 +8M
    project_cmd resize-vm-disk.sh "$trz_vm" scsi0 +8M
    [ "$(blockdev --getsize64 "$trz_lv")" -gt "$trz_before" ]
}
test_reference_primitives() {
    trp_vm="$(create_test_vm "refs")"; trp_name="vm-${trp_vm}-disk-0"
    create_thin_lv "$TEST_VG_A" "$trp_name" 16M >/dev/null
    attach_test_lv "$trp_vm" "$TEST_STORAGE_A" "$trp_name" scsi0
    qm set "$trp_vm" --delete scsi0 >/dev/null
    trp_unused="$(qm config "$trp_vm" | awk -F: '/^unused[0-9]+:/ {print $1; exit}')"
    [ -n "$trp_unused" ]
    run_dryrun_unchanged "remove-vm-disk-reference-only" remove-vm-disk-reference-only.sh "$trp_vm" "$trp_unused"
    project_cmd remove-vm-disk-reference-only.sh "$trp_vm" "$trp_unused"
    assert_lv_exists "$TEST_VG_A/$trp_name"
    run_dryrun_unchanged "add-vm-disk-reference-only" add-vm-disk-reference-only.sh "$trp_vm" scsi0 "$TEST_STORAGE_A:$trp_name"
    project_cmd add-vm-disk-reference-only.sh "$trp_vm" scsi0 "$TEST_STORAGE_A:$trp_name"
    qm config "$trp_vm" | grep -F "scsi0: $TEST_STORAGE_A:$trp_name" >/dev/null
}
test_rename_unused() {
    tru_vm="$(create_test_vm "unused-alias")"; tru_name="vm-${tru_vm}-disk-0"
    create_thin_lv "$TEST_VG_A" "$tru_name" 16M >/dev/null
    attach_test_lv "$tru_vm" "$TEST_STORAGE_A" "$tru_name" scsi0
    qm set "$tru_vm" --delete scsi0 >/dev/null
    tru_unused="$(qm config "$tru_vm" | awk -F: '/^unused[0-9]+:/ {print $1; exit}')"
    run_dryrun_unchanged "rename-unused-disk-reference" rename-unused-disk-reference.sh "$tru_vm" "$tru_unused" "$TEST_STORAGE_ALIAS:$tru_name"
    project_cmd rename-unused-disk-reference.sh "$tru_vm" "$tru_unused" "$TEST_STORAGE_ALIAS:$tru_name"
    qm config "$tru_vm" | grep -F "$TEST_STORAGE_ALIAS:$tru_name" >/dev/null
    assert_lv_exists "$TEST_VG_A/$tru_name"
}
test_copy_options() {
    tco_src="$(create_test_vm "options-src")"; tco_dst="$(create_test_vm "options-dst")"
    tco_sname="vm-${tco_src}-disk-0"; tco_dname="vm-${tco_dst}-disk-0"
    create_thin_lv "$TEST_VG_A" "$tco_sname" 16M >/dev/null; create_thin_lv "$TEST_VG_A" "$tco_dname" 16M >/dev/null
    qm set "$tco_src" --scsi0 "$TEST_STORAGE_A:$tco_sname,cache=writeback,discard=on" >/dev/null
    attach_test_lv "$tco_dst" "$TEST_STORAGE_A" "$tco_dname" scsi0
    run_dryrun_unchanged "copy-vm-disk-options" copy-vm-disk-options.sh "$tco_src" scsi0 "$tco_dst" scsi0
    project_cmd copy-vm-disk-options.sh "$tco_src" scsi0 "$tco_dst" scsi0
    tco_value="$(qm config "$tco_dst" | sed -n 's/^scsi0:[[:space:]]*//p')"
    [ "${tco_value%%,*}" = "$TEST_STORAGE_A:$tco_dname" ]
    printf '%s\n' "$tco_value" | grep -F "cache=writeback" >/dev/null
    printf '%s\n' "$tco_value" | grep -F "discard=on" >/dev/null
}
test_normalize_options() {
    tno_vm="$(create_test_vm "normalize")"; tno_name="vm-${tno_vm}-disk-0"
    create_thin_lv "$TEST_VG_A" "$tno_name" 16M >/dev/null; attach_test_lv "$tno_vm" "$TEST_STORAGE_A" "$tno_name" scsi0
    run_dryrun_unchanged "normalize-vm-disk-options" normalize-vm-disk-options.sh "$tno_vm" scsi0
    project_cmd normalize-vm-disk-options.sh "$tno_vm" scsi0
}
test_renumber_slots() {
    trs_vm="$(create_test_vm "renumber-slots")"
    trs_a="vm-${trs_vm}-disk-3"; trs_b="vm-${trs_vm}-disk-7"
    create_thin_lv "$TEST_VG_A" "$trs_a" 16M >/dev/null; create_thin_lv "$TEST_VG_A" "$trs_b" 16M >/dev/null
    attach_test_lv "$trs_vm" "$TEST_STORAGE_A" "$trs_a" scsi2; attach_test_lv "$trs_vm" "$TEST_STORAGE_A" "$trs_b" scsi4
    run_dryrun_unchanged "renumber-vm-device-slots" renumber-vm-device-slots.sh "$trs_vm" --bus scsi
    project_cmd renumber-vm-device-slots.sh "$trs_vm" --bus scsi
    qm config "$trs_vm" | grep -F "scsi0:" >/dev/null; qm config "$trs_vm" | grep -F "scsi1:" >/dev/null
}
test_sort_slots() {
    tss_vm="$(create_test_vm "sort-slots")"
    tss_hi="vm-${tss_vm}-disk-7"; tss_lo="vm-${tss_vm}-disk-3"
    create_thin_lv "$TEST_VG_A" "$tss_hi" 16M >/dev/null; create_thin_lv "$TEST_VG_A" "$tss_lo" 16M >/dev/null
    attach_test_lv "$tss_vm" "$TEST_STORAGE_A" "$tss_hi" scsi0; attach_test_lv "$tss_vm" "$TEST_STORAGE_A" "$tss_lo" scsi1
    run_dryrun_unchanged "sort-vm-disk-slots" sort-vm-disk-slots.sh "$tss_vm" --bus scsi
    project_cmd sort-vm-disk-slots.sh "$tss_vm" --bus scsi
    qm config "$tss_vm" | sed -n 's/^scsi0:[[:space:]]*//p' | grep -F "$tss_lo" >/dev/null
}
test_flatten() {
    tf_vm="$(create_test_vm "flatten")"; tf_origin="vm-${tf_vm}-disk-0"; tf_child="vm-${tf_vm}-disk-1"
    tf_origin_path="$(create_thin_lv "$TEST_VG_A" "$tf_origin" 32M)"; write_test_pattern "$tf_origin_path" flatten-origin
    lvcreate --snapshot --name "$tf_child" "$TEST_VG_A/$tf_origin" >/dev/null 2>&1
    attach_test_lv "$tf_vm" "$TEST_STORAGE_A" "$tf_child" scsi0
    run_dryrun_unchanged "flatten-vm-disk" flatten-vm-disk.sh "$tf_vm" scsi0
    project_cmd flatten-vm-disk.sh "$tf_vm" scsi0
    tf_new_vol="$(qm config "$tf_vm" | sed -n 's/^scsi0:[[:space:]]*//p' | cut -d, -f1)"
    tf_new_path="$(pvesm path "$tf_new_vol")"
    [ -z "$(lvs --noheadings -o origin "$tf_new_path" | tr -d ' ')" ]
    assert_lv_exists "$TEST_VG_A/$tf_child"
}

setup "$@"; main "$@"; end
