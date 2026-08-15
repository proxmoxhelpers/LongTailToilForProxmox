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
    PROJECT_VERSION="3.0.1"
    TEST_SUITE_VERSION="2.0.1"
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
    run_case "copy-lvm.sh dry-run + independent copy" test_copy_lvm
    run_case "move-lvm.sh dry-run + cross-VG move" test_move_lvm
    run_case "rename-lvm.sh dry-run + rename" test_rename_lvm
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
    printf '%s\n' "Real operations: copy, cross-VG move, rename and explicitly confirmed delete."
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
    run_dryrun_unchanged "move-lvm" move-lvm.sh "$tml_src" "$tml_dst"
    project_cmd move-lvm.sh "$tml_src" "$tml_dst"
    assert_lv_absent "$TEST_VG_A/$tml_name"
    assert_lv_exists "$TEST_VG_B/$tml_name"
}

test_rename_lvm() {
    trl_old="plvt-rename-old-${TEST_TOKEN}"
    trl_new="plvt-rename-new-${TEST_TOKEN}"
    trl_src="$(create_thin_lv "$TEST_VG_A" "$trl_old" 16M)"
    run_dryrun_unchanged "rename-lvm" rename-lvm.sh "$trl_src" "$trl_new"
    project_cmd rename-lvm.sh "$trl_src" "$trl_new"
    assert_lv_absent "$TEST_VG_A/$trl_old"
    assert_lv_exists "$TEST_VG_A/$trl_new"
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
