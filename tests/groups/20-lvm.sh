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
    PROJECT_VERSION="3.4.4"
    TEST_SUITE_VERSION="2.8.2"
    TEST_GROUP="lvm"
    test_reset_counters
    test_parse_arguments "$@"
    [ "$TEST_RUN" = "false" ] || check_elevation
}

main() {
    [ "$TEST_RUN" = "true" ] || { print_plan; return 0; }
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    require_proxmox_environment
    for CMD in dd cmp; do require_command "$CMD"; done
    test_prepare_run
    create_storage_sandbox
    create_regular_vg_sandbox
    run_case "copy-lvm.sh dry-run + thin independent copy" test_copy_lvm
    run_case "copy-lvm.sh regular destination uses full writes" test_copy_lvm_regular
    run_case "move-lvm.sh dry-run + cross-VG move" test_move_lvm
    run_case "move-lvm.sh same-VG rename branch" test_move_lvm_same_vg
    run_case "rename-lvm.sh path form" test_rename_lvm
    run_case "rename-lvm.sh VG/old/new form" test_rename_lvm_three_arg
    run_case "delete-lvm.sh refuses wrong confirmation without mutation" test_delete_lvm_wrong_confirmation
    run_case "delete-lvm.sh dry-run + confirmed delete" test_delete_lvm
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
    print_banner "Raw LVM tests"
    printf '%s\n' "Each case creates its own small thin LV inside disposable loopback VGs."
    printf '%s\n' "Every mutating command is first run with dryrun and compared against a state snapshot."
    printf '%s\n' "Real operations cover thin and regular copy allocation, same-VG rename, cross-VG move, both rename CLI forms, and confirmed delete."
    printf '%s\n' "A wrong delete confirmation is required to fail with exact test-owned state unchanged."
}

############################################################
# TEST CASES
############################################################

test_copy_lvm() {
    tcl_name="plvt-copy-${TEST_TOKEN}"
    tcl_src="$(create_thin_lv "$TEST_VG_A" "$tcl_name" 32M)"
    tcl_dst="/dev/$TEST_VG_B/$tcl_name"
    write_test_pattern "$tcl_src" "copy-lvm"
    run_dryrun_unchanged "copy-lvm" copy-lvm.sh "$tcl_src" "$tcl_dst"
    project_cmd copy-lvm.sh "$tcl_src" "$tcl_dst"
    assert_lv_exists "$TEST_VG_A/$tcl_name"
    assert_lv_exists "$TEST_VG_B/$tcl_name"
    cmp "$tcl_src" "$tcl_dst"
}

test_move_lvm() {
    tml_name="plvt-move-${TEST_TOKEN}"
    tml_src="$(create_thin_lv "$TEST_VG_A" "$tml_name" 32M)"
    tml_dst="/dev/$TEST_VG_B/$tml_name"
    write_test_pattern "$tml_src" "move-lvm"
    tml_hash="$(sha256sum "$tml_src" | awk '{print $1}')"
    run_dryrun_unchanged "move-lvm" move-lvm.sh "$tml_src" "$tml_dst"
    project_cmd move-lvm.sh "$tml_src" "$tml_dst"
    assert_lv_absent "$TEST_VG_A/$tml_name"
    assert_lv_exists "$TEST_VG_B/$tml_name"
    [ "$(sha256sum "$tml_dst" | awk '{print $1}')" = "$tml_hash" ]
}

test_rename_lvm() {
    trl_old="plvt-rename-old-${TEST_TOKEN}"
    trl_new="plvt-rename-new-${TEST_TOKEN}"
    trl_src="$(create_thin_lv "$TEST_VG_A" "$trl_old" 16M)"
    trl_uuid="$(lvs --noheadings -o lv_uuid "$trl_src" | awk '{$1=$1;print}')"
    run_dryrun_unchanged "rename-lvm" rename-lvm.sh "$trl_src" "$trl_new"
    project_cmd rename-lvm.sh "$trl_src" "$trl_new"
    assert_lv_absent "$TEST_VG_A/$trl_old"
    assert_lv_exists "$TEST_VG_A/$trl_new"
    [ "$(lvs --noheadings -o lv_uuid "/dev/${TEST_VG_A}/${trl_new}" | awk '{$1=$1;print}')" = "$trl_uuid" ]
}

test_copy_lvm_regular() {
    tclr_name="plvt-copy-regular-${TEST_TOKEN}"
    tclr_src_name="plvt-copy-regular-src-${TEST_TOKEN}"
    tclr_src="$(create_thin_lv "$TEST_VG_A" "$tclr_src_name" 32M)"
    tclr_dst="/dev/${TEST_VG_REGULAR}/${tclr_name}"
    write_test_pattern "$tclr_src" "copy-lvm-regular"

    tclr_out="$TEST_RESULT_DIR/copy-lvm-regular.log"
    run_dryrun_unchanged "copy-lvm-regular" copy-lvm.sh "$tclr_src" "$tclr_dst"
    project_cmd copy-lvm.sh "$tclr_src" "$tclr_dst" >"$tclr_out" 2>&1

    assert_lv_exists "$TEST_VG_REGULAR/$tclr_name"
    [ -z "$(lvs --noheadings -o pool_lv "$tclr_dst" | awk '{$1=$1;print}')" ]
    cmp "$tclr_src" "$tclr_dst"
}

test_move_lvm_same_vg() {
    tmls_old="plvt-move-same-old-${TEST_TOKEN}"
    tmls_new="plvt-move-same-new-${TEST_TOKEN}"
    tmls_src="$(create_thin_lv "$TEST_VG_A" "$tmls_old" 16M)"
    tmls_uuid="$(lvs --noheadings -o lv_uuid "$tmls_src" | awk '{$1=$1;print}')"
    run_dryrun_unchanged "move-lvm-same-vg" move-lvm.sh "$tmls_src" "/dev/${TEST_VG_A}/${tmls_new}"
    project_cmd move-lvm.sh "$tmls_src" "/dev/${TEST_VG_A}/${tmls_new}"
    assert_lv_absent "$TEST_VG_A/$tmls_old"
    assert_lv_exists "$TEST_VG_A/$tmls_new"
    [ "$(lvs --noheadings -o lv_uuid "/dev/${TEST_VG_A}/${tmls_new}" | awk '{$1=$1;print}')" = "$tmls_uuid" ]
}

test_rename_lvm_three_arg() {
    trl3_old="plvt-rename3-old-${TEST_TOKEN}"
    trl3_new="plvt-rename3-new-${TEST_TOKEN}"
    trl3_src="$(create_thin_lv "$TEST_VG_A" "$trl3_old" 16M)"
    trl3_uuid="$(lvs --noheadings -o lv_uuid "$trl3_src" | awk '{$1=$1;print}')"
    run_dryrun_unchanged "rename-lvm-three-arg" rename-lvm.sh "$TEST_VG_A" "$trl3_old" "$trl3_new"
    project_cmd rename-lvm.sh "$TEST_VG_A" "$trl3_old" "$trl3_new"
    assert_lv_absent "$TEST_VG_A/$trl3_old"
    assert_lv_exists "$TEST_VG_A/$trl3_new"
    [ "$(lvs --noheadings -o lv_uuid "/dev/${TEST_VG_A}/${trl3_new}" | awk '{$1=$1;print}')" = "$trl3_uuid" ]
}

test_delete_lvm_wrong_confirmation() {
    tdlw_name="plvt-delete-refuse-${TEST_TOKEN}"
    tdlw_src="$(create_thin_lv "$TEST_VG_A" "$tdlw_name" 16M)"
    tdlw_before="$TEST_RESULT_DIR/delete-refuse-before"
    tdlw_after="$TEST_RESULT_DIR/delete-refuse-after"
    snapshot_test_owned_state "$tdlw_before"
    if printf 'NO\n' | project_cmd delete-lvm.sh "$tdlw_src" >"$TEST_RESULT_DIR/delete-refuse-output.log" 2>&1; then
        printf 'delete-lvm unexpectedly accepted an invalid confirmation.\n' >&2
        return 1
    fi
    snapshot_test_owned_state "$tdlw_after"
    cmp -s "$tdlw_before" "$tdlw_after" || { diff -u "$tdlw_before" "$tdlw_after" || :; return 1; }
    assert_lv_exists "$TEST_VG_A/$tdlw_name"
}

test_delete_lvm() {
    tdl_name="plvt-delete-${TEST_TOKEN}"
    tdl_src="$(create_thin_lv "$TEST_VG_A" "$tdl_name" 16M)"
    run_dryrun_unchanged "delete-lvm" delete-lvm.sh "$tdl_src"
    printf 'DELETE\n' | project_cmd delete-lvm.sh "$tdl_src"
    assert_lv_absent "$TEST_VG_A/$tdl_name"
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
