#!/bin/sh
set -eu
SCRIPT_DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
TEST_ROOT="$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(CDPATH= cd "$TEST_ROOT/.." && pwd)"
. "$TEST_ROOT/lib/test-common.sh"

setup() {
    define_colours
    PROJECT_VERSION="3.7.1"; TEST_SUITE_VERSION="3.1.1"; TEST_GROUP="qol-lvm"
    test_reset_counters; test_parse_arguments "$@"
    [ "$TEST_RUN" = "false" ] || check_elevation
}
main() {
    [ "$TEST_RUN" = "true" ] || { print_plan; return 0; }
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    require_proxmox_environment
    for CMD in dd cmp mkfs.ext4 resize2fs lvextend lvcreate lvchange; do require_command "$CMD"; done
    test_prepare_run; create_storage_sandbox; create_regular_vg_sandbox; prepare_fixture
    run_case "extend-lvm.sh grow-only primitive" test_extend
    run_case "grow-vm-filesystem.sh whole-device ext4" test_grow_fs
    run_case "convert-lv-to-thin.sh independent copy" test_regular_to_thin
    run_case "convert-thin-to-regular-lv.sh full-write copy" test_thin_to_regular
    run_case "copy-vm-disk-to-regular-lv.sh byte-identical copy" test_vm_to_regular
    run_case "copy-vm-disk-to-thin-lv.sh byte-identical copy" test_vm_to_thin
    run_case "convert-lv-to-thin.sh inactive source activation is restored" test_regular_to_thin_inactive
    run_case "convert-thin-to-regular-lv.sh inactive source activation is restored" test_thin_to_regular_inactive
    run_case "copy-vm-disk-to-regular-lv.sh inactive source activation is restored" test_vm_to_regular_inactive
    run_case "copy-vm-disk-to-thin-lv.sh inactive source activation is restored" test_vm_to_thin_inactive
    run_case "activate-vm-lvs.sh / deactivate-vm-lvs.sh state preservation" test_activation
}
end() {
    [ "$TEST_RUN" = "true" ] || return 0
    [ "${APP_ELEVATED:-false}" = "true" ] || return 0
    test_finish_run
}
print_plan() {
    print_banner "v3.6 LVM/growth/conversion tests"
    printf '%s\n' "Uses disposable thin and regular VGs. Copy results are byte-compared."
    printf '%s\n' "Regular destinations are checked through the public helpers' non-sparse paths."
}
prepare_fixture() {
    QL_VM="$(create_test_vm "qol-lvm")"
    QL_SRC_NAME="vm-${QL_VM}-disk-0"
    QL_SRC="$(create_thin_lv "$TEST_VG_A" "$QL_SRC_NAME" 32M)"
    write_test_pattern "$QL_SRC" "qol-lvm-source"
    attach_test_lv "$QL_VM" "$TEST_STORAGE_A" "$QL_SRC_NAME" scsi0
}
test_extend() {
    tel_name="qol-extend-${TEST_TOKEN}"; tel_lv="$(create_thin_lv "$TEST_VG_A" "$tel_name" 16M)"
    run_dryrun_unchanged "extend-lvm" extend-lvm.sh "$tel_lv" +8M
    tel_before="$(blockdev --getsize64 "$tel_lv")"
    project_cmd extend-lvm.sh "$tel_lv" +8M
    tel_after="$(blockdev --getsize64 "$tel_lv")"
    [ "$tel_after" -gt "$tel_before" ]
}
test_grow_fs() {
    tgf_name="qol-fs-${TEST_TOKEN}"; tgf_lv="$(create_thin_lv "$TEST_VG_A" "$tgf_name" 32M)"
    mkfs.ext4 -F "$tgf_lv" >/dev/null 2>&1
    lvextend -L +16M "$tgf_lv" >/dev/null
    run_dryrun_unchanged "grow-vm-filesystem" grow-vm-filesystem.sh "$tgf_lv"
    project_cmd grow-vm-filesystem.sh "$tgf_lv"
    e2fsck -fn "$tgf_lv" >/dev/null 2>&1 || [ "$?" -le 1 ]
}
test_regular_to_thin() {
    trt_src_name="qol-reg-src-${TEST_TOKEN}"
    lvcreate -L 16M -n "$trt_src_name" "$TEST_VG_REGULAR" >/dev/null
    trt_src="/dev/$TEST_VG_REGULAR/$trt_src_name"; write_test_pattern "$trt_src" regular-to-thin
    trt_dst_name="qol-thin-copy-${TEST_TOKEN}"
    run_dryrun_unchanged "convert-lv-to-thin" convert-lv-to-thin.sh "$trt_src" "$TEST_VG_B" "$trt_dst_name" --pool "$TEST_POOL"
    project_cmd convert-lv-to-thin.sh "$trt_src" "$TEST_VG_B" "$trt_dst_name" --pool "$TEST_POOL"
    cmp "$trt_src" "/dev/$TEST_VG_B/$trt_dst_name"
}
test_thin_to_regular() {
    ttr_name="qol-reg-copy-${TEST_TOKEN}"
    run_dryrun_unchanged "convert-thin-to-regular" convert-thin-to-regular-lv.sh "$QL_SRC" "$TEST_VG_REGULAR" "$ttr_name"
    project_cmd convert-thin-to-regular-lv.sh "$QL_SRC" "$TEST_VG_REGULAR" "$ttr_name"
    cmp "$QL_SRC" "/dev/$TEST_VG_REGULAR/$ttr_name"
}
test_vm_to_regular() {
    tvrr_name="qol-vm-reg-${TEST_TOKEN}"
    run_dryrun_unchanged "copy-vm-disk-to-regular" copy-vm-disk-to-regular-lv.sh "$QL_VM" scsi0 "$TEST_VG_REGULAR" "$tvrr_name"
    project_cmd copy-vm-disk-to-regular-lv.sh "$QL_VM" scsi0 "$TEST_VG_REGULAR" "$tvrr_name"
    cmp "$QL_SRC" "/dev/$TEST_VG_REGULAR/$tvrr_name"
}
test_vm_to_thin() {
    tvtt_name="qol-vm-thin-${TEST_TOKEN}"
    run_dryrun_unchanged "copy-vm-disk-to-thin" copy-vm-disk-to-thin-lv.sh "$QL_VM" scsi0 "$TEST_VG_B" "$tvtt_name" --pool "$TEST_POOL"
    project_cmd copy-vm-disk-to-thin-lv.sh "$QL_VM" scsi0 "$TEST_VG_B" "$tvtt_name" --pool "$TEST_POOL"
    cmp "$QL_SRC" "/dev/$TEST_VG_B/$tvtt_name"
}
test_regular_to_thin_inactive() {
    trti_src_name="qol-reg-inactive-${TEST_TOKEN}"
    lvcreate -L 16M -n "$trti_src_name" "$TEST_VG_REGULAR" >/dev/null
    trti_src="/dev/$TEST_VG_REGULAR/$trti_src_name"; write_test_pattern "$trti_src" regular-inactive
    lvchange -an "$TEST_VG_REGULAR/$trti_src_name" >/dev/null
    trti_dst_name="qol-thin-inactive-${TEST_TOKEN}"
    project_cmd convert-lv-to-thin.sh "$trti_src" "$TEST_VG_B" "$trti_dst_name" --pool "$TEST_POOL"
    [ ! -b "$trti_src" ]
    lvchange -ay "$TEST_VG_REGULAR/$trti_src_name" >/dev/null
    cmp "$trti_src" "/dev/$TEST_VG_B/$trti_dst_name"
}
test_thin_to_regular_inactive() {
    lvchange -an "$TEST_VG_A/$QL_SRC_NAME" >/dev/null
    ttri_name="qol-reg-from-inactive-${TEST_TOKEN}"
    project_cmd convert-thin-to-regular-lv.sh "$QL_SRC" "$TEST_VG_REGULAR" "$ttri_name"
    [ ! -b "$QL_SRC" ]
    lvchange -ay -K "$TEST_VG_A/$QL_SRC_NAME" >/dev/null
    cmp "$QL_SRC" "/dev/$TEST_VG_REGULAR/$ttri_name"
}
test_vm_to_regular_inactive() {
    lvchange -an "$TEST_VG_A/$QL_SRC_NAME" >/dev/null
    tvrri_name="qol-vm-reg-inactive-${TEST_TOKEN}"
    project_cmd copy-vm-disk-to-regular-lv.sh "$QL_VM" scsi0 "$TEST_VG_REGULAR" "$tvrri_name"
    [ ! -b "$QL_SRC" ]
    lvchange -ay -K "$TEST_VG_A/$QL_SRC_NAME" >/dev/null
    cmp "$QL_SRC" "/dev/$TEST_VG_REGULAR/$tvrri_name"
}
test_vm_to_thin_inactive() {
    lvchange -an "$TEST_VG_A/$QL_SRC_NAME" >/dev/null
    tvtti_name="qol-vm-thin-inactive-${TEST_TOKEN}"
    project_cmd copy-vm-disk-to-thin-lv.sh "$QL_VM" scsi0 "$TEST_VG_B" "$tvtti_name" --pool "$TEST_POOL"
    [ ! -b "$QL_SRC" ]
    lvchange -ay -K "$TEST_VG_A/$QL_SRC_NAME" >/dev/null
    cmp "$QL_SRC" "/dev/$TEST_VG_B/$tvtti_name"
}

test_activation() {
    run_dryrun_unchanged "deactivate-vm-lvs" deactivate-vm-lvs.sh "$QL_VM"
    project_cmd deactivate-vm-lvs.sh "$QL_VM"
    [ ! -b "$QL_SRC" ]
    run_dryrun_unchanged "activate-vm-lvs" activate-vm-lvs.sh "$QL_VM"
    project_cmd activate-vm-lvs.sh "$QL_VM"
    [ -b "$QL_SRC" ]
}

setup "$@"; main "$@"; end
