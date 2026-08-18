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
    TEST_GROUP="copy-snapshot"
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
    prepare_copy_fixture
    run_case "create-disk-snapshot-and-add-to-vm.sh" test_create_snapshot_add
    run_case "create-disk-copy-and-add-to-vm.sh" test_create_copy_add
    run_case "create-disk-copy-and-overwrite-disk-on-vm.sh preserve + same disk number" test_create_copy_overwrite
    run_case "create-disk-copy-and-overwrite-disk-on-vm.sh delete + same disk number" test_create_copy_overwrite_delete
    run_case "create-disk-snapshot-and-overwrite-disk-on-vm.sh preserve + same disk number" test_create_snapshot_overwrite
    run_case "create-disk-snapshot-and-overwrite-disk-on-vm.sh delete + same disk number" test_create_snapshot_overwrite_delete
    run_case "create-disk-copy-and-overwrite-disk-on-vm.sh empty target creates requested disk number" test_create_copy_overwrite_empty
    run_case "create-disk-snapshot-and-overwrite-disk-on-vm.sh empty target creates requested disk number" test_create_snapshot_overwrite_empty
    run_case "copy-disk-between-vms.sh" test_copy_between_vms
    run_case "snapshot-disk-between-vms.sh" test_snapshot_between_vms
    run_case "clone-single-vm-disk.sh" test_clone_single_disk
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
    print_banner "Copy / snapshot tests"
    printf '%s\n' "Creates stopped source/destination VMs and a 32 MiB thin source disk."
    printf '%s\n' "Tests source-by-slot, exact/bare-bus destinations, boot-order promotion, copies/snapshots, overwrite/archive/delete behavior, and empty-target creation."
    printf '%s\n' "All resulting volumes remain in disposable test storages and are removed during ownership-checked cleanup."
}

############################################################
# FIXTURE
############################################################

prepare_copy_fixture() {
    COPY_SRC_VM="$(create_test_vm copy-src)"
    COPY_DST_VM="$(create_test_vm copy-dst)"
    COPY_SRC_LV_NAME="vm-${COPY_SRC_VM}-disk-0"
    COPY_SRC_LV="$(create_thin_lv "$TEST_VG_A" "$COPY_SRC_LV_NAME" 32M)"
    write_test_pattern "$COPY_SRC_LV" "copy-snapshot-source"
    attach_test_lv "$COPY_SRC_VM" "$TEST_STORAGE_A" "$COPY_SRC_LV_NAME" scsi0

    COPY_OVERWRITE_VM="$(create_test_vm copy-overwrite)"
    COPY_OVERWRITE_OLD_NAME="vm-${COPY_OVERWRITE_VM}-disk-0"
    COPY_OVERWRITE_OLD_LV="$(create_thin_lv "$TEST_VG_B" "$COPY_OVERWRITE_OLD_NAME" 32M)"
    write_test_pattern "$COPY_OVERWRITE_OLD_LV" "copy-overwrite-old"
    attach_test_lv "$COPY_OVERWRITE_VM" "$TEST_STORAGE_B" "$COPY_OVERWRITE_OLD_NAME" scsi0

    SNAP_OVERWRITE_VM="$(create_test_vm snapshot-overwrite)"
    SNAP_OVERWRITE_OLD_NAME="vm-${SNAP_OVERWRITE_VM}-disk-0"
    SNAP_OVERWRITE_OLD_LV="$(create_thin_lv "$TEST_VG_B" "$SNAP_OVERWRITE_OLD_NAME" 32M)"
    write_test_pattern "$SNAP_OVERWRITE_OLD_LV" "snapshot-overwrite-old"
    attach_test_lv "$SNAP_OVERWRITE_VM" "$TEST_STORAGE_B" "$SNAP_OVERWRITE_OLD_NAME" scsi0


    COPY_OVERWRITE_DELETE_VM="$(create_test_vm copy-overwrite-delete)"
    COPY_OVERWRITE_DELETE_OLD_NAME="vm-${COPY_OVERWRITE_DELETE_VM}-disk-0"
    COPY_OVERWRITE_DELETE_OLD_LV="$(create_thin_lv "$TEST_VG_B" "$COPY_OVERWRITE_DELETE_OLD_NAME" 32M)"
    write_test_pattern "$COPY_OVERWRITE_DELETE_OLD_LV" "copy-overwrite-delete-old"
    attach_test_lv "$COPY_OVERWRITE_DELETE_VM" "$TEST_STORAGE_B" "$COPY_OVERWRITE_DELETE_OLD_NAME" scsi0

    SNAP_OVERWRITE_DELETE_VM="$(create_test_vm snapshot-overwrite-delete)"
    SNAP_OVERWRITE_DELETE_OLD_NAME="vm-${SNAP_OVERWRITE_DELETE_VM}-disk-0"
    SNAP_OVERWRITE_DELETE_OLD_LV="$(create_thin_lv "$TEST_VG_B" "$SNAP_OVERWRITE_DELETE_OLD_NAME" 32M)"
    write_test_pattern "$SNAP_OVERWRITE_DELETE_OLD_LV" "snapshot-overwrite-delete-old"
    attach_test_lv "$SNAP_OVERWRITE_DELETE_VM" "$TEST_STORAGE_B" "$SNAP_OVERWRITE_DELETE_OLD_NAME" scsi0

    COPY_EMPTY_VM="$(create_test_vm copy-empty-target)"
    SNAP_EMPTY_VM="$(create_test_vm snapshot-empty-target)"
}

############################################################
# TEST CASES
############################################################

test_create_snapshot_add() {
    run_dryrun_unchanged "create-snapshot-add" create-disk-snapshot-and-add-to-vm.sh "$COPY_SRC_VM" scsi0 "$COPY_DST_VM" sata boot
    project_cmd create-disk-snapshot-and-add-to-vm.sh "$COPY_SRC_VM" scsi0 "$COPY_DST_VM" sata boot
    tcsa_volid="$(qm config "$COPY_DST_VM" | sed -n 's/^sata0:[[:space:]]*//p' | head -n1 | cut -d, -f1)"
    [ -n "$tcsa_volid" ]
    lvs --noheadings -o origin "$(pvesm path "$tcsa_volid")" 2>/dev/null | grep -F "$COPY_SRC_LV_NAME" >/dev/null
    qm config "$COPY_DST_VM" | grep -qE '^boot:.*order=sata0([;,]|$)'
}

test_create_copy_add() {
    run_dryrun_unchanged "create-copy-add" create-disk-copy-and-add-to-vm.sh "$COPY_SRC_VM" scsi0 "$COPY_DST_VM" virtio0 "$TEST_VG_B" boot
    project_cmd create-disk-copy-and-add-to-vm.sh "$COPY_SRC_VM" scsi0 "$COPY_DST_VM" virtio0 "$TEST_VG_B" boot
    tcca_volid="$(qm config "$COPY_DST_VM" | sed -n 's/^virtio0:[[:space:]]*//p' | head -n1 | cut -d, -f1)"
    case "$tcca_volid" in "$TEST_STORAGE_B":vm-"${COPY_DST_VM}"-disk-*) ;; *) return 1 ;; esac
    cmp -n 33554432 "$COPY_SRC_LV" "$(pvesm path "$tcca_volid")"
    qm config "$COPY_DST_VM" | grep -qE '^boot:.*order=virtio0([;,]|$)'
}

test_create_copy_overwrite() {
    tcow_old_volid="$TEST_STORAGE_B:$COPY_OVERWRITE_OLD_NAME"
    tcow_old_uuid="$(lvs --noheadings -o lv_uuid "$COPY_OVERWRITE_OLD_LV" | trim)"
    tcow_archive_name="vm-${COPY_OVERWRITE_VM}-disk-901"
    tcow_archive_volid="$TEST_STORAGE_B:$tcow_archive_name"
    tcow_archive_path="/dev/${TEST_VG_B}/${tcow_archive_name}"

    run_dryrun_unchanged "create-copy-overwrite" create-disk-copy-and-overwrite-disk-on-vm.sh "$COPY_SRC_VM" scsi0 "$COPY_OVERWRITE_VM" scsi0 pause boot
    project_cmd create-disk-copy-and-overwrite-disk-on-vm.sh "$COPY_SRC_VM" scsi0 "$COPY_OVERWRITE_VM" scsi0 boot

    tcow_new_volid="$(qm config "$COPY_OVERWRITE_VM" | sed -n 's/^scsi0:[[:space:]]*//p' | head -n1 | cut -d, -f1)"
    [ "$tcow_new_volid" = "$tcow_old_volid" ]
    tcow_new_path="$(pvesm path "$tcow_new_volid")"
    tcow_new_uuid="$(lvs --noheadings -o lv_uuid "$tcow_new_path" | trim)"
    [ "$tcow_new_uuid" != "$tcow_old_uuid" ]
    cmp -n 33554432 "$COPY_SRC_LV" "$tcow_new_path"

    [ "$(lvs --noheadings -o lv_uuid "$tcow_archive_path" | trim)" = "$tcow_old_uuid" ]
    qm config "$COPY_OVERWRITE_VM" | grep -E "^unused[0-9]+: ${tcow_archive_volid}([,[:space:]]|$)" >/dev/null
    qm config "$COPY_OVERWRITE_VM" | grep -qE '^boot:.*order=scsi0([;,]|$)'
}

test_create_snapshot_overwrite() {
    tsow_old_uuid="$(lvs --noheadings -o lv_uuid "$SNAP_OVERWRITE_OLD_LV" | trim)"
    tsow_final_name="$SNAP_OVERWRITE_OLD_NAME"
    tsow_final_volid="$TEST_STORAGE_A:$tsow_final_name"
    tsow_archive_name="vm-${SNAP_OVERWRITE_VM}-disk-901"
    tsow_archive_volid="$TEST_STORAGE_B:$tsow_archive_name"
    tsow_archive_path="/dev/${TEST_VG_B}/${tsow_archive_name}"

    run_dryrun_unchanged "create-snapshot-overwrite" create-disk-snapshot-and-overwrite-disk-on-vm.sh "$COPY_SRC_VM" scsi0 "$SNAP_OVERWRITE_VM" scsi0 restart boot
    project_cmd create-disk-snapshot-and-overwrite-disk-on-vm.sh "$COPY_SRC_VM" scsi0 "$SNAP_OVERWRITE_VM" scsi0 boot

    tsow_new_volid="$(qm config "$SNAP_OVERWRITE_VM" | sed -n 's/^scsi0:[[:space:]]*//p' | head -n1 | cut -d, -f1)"
    [ "$tsow_new_volid" = "$tsow_final_volid" ]
    tsow_new_path="$(pvesm path "$tsow_new_volid")"
    tsow_origin="$(lvs --noheadings -o origin "$tsow_new_path" | trim)"
    [ "$tsow_origin" = "$COPY_SRC_LV_NAME" ]

    [ "$(lvs --noheadings -o lv_uuid "$tsow_archive_path" | trim)" = "$tsow_old_uuid" ]
    qm config "$SNAP_OVERWRITE_VM" | grep -E "^unused[0-9]+: ${tsow_archive_volid}([,[:space:]]|$)" >/dev/null
    qm config "$SNAP_OVERWRITE_VM" | grep -qE '^boot:.*order=scsi0([;,]|$)'
}

test_create_copy_overwrite_delete() {
    tcod_old_uuid="$(lvs --noheadings -o lv_uuid "$COPY_OVERWRITE_DELETE_OLD_LV" | trim)"
    tcod_final_volid="$TEST_STORAGE_B:$COPY_OVERWRITE_DELETE_OLD_NAME"
    tcod_archive_name="vm-${COPY_OVERWRITE_DELETE_VM}-disk-901"
    tcod_archive_path="/dev/${TEST_VG_B}/${tcod_archive_name}"

    run_dryrun_unchanged "create-copy-overwrite-delete" create-disk-copy-and-overwrite-disk-on-vm.sh delete "$COPY_SRC_VM" disk-0 "$COPY_OVERWRITE_DELETE_VM" disk-0 stop
    project_cmd create-disk-copy-and-overwrite-disk-on-vm.sh "$COPY_SRC_VM" disk-0 "$COPY_OVERWRITE_DELETE_VM" disk-0 delete

    tcod_new_volid="$(qm config "$COPY_OVERWRITE_DELETE_VM" | sed -n 's/^scsi0:[[:space:]]*//p' | head -n1 | cut -d, -f1)"
    [ "$tcod_new_volid" = "$tcod_final_volid" ]
    cmp -n 33554432 "$COPY_SRC_LV" "$(pvesm path "$tcod_new_volid")"
    lvs "$tcod_archive_path" >/dev/null 2>&1 && return 1
    lvs --noheadings -o lv_uuid 2>/dev/null | grep -F "$tcod_old_uuid" >/dev/null && return 1
    ! qm config "$COPY_OVERWRITE_DELETE_VM" | grep -F "$tcod_archive_name" >/dev/null
}

test_create_snapshot_overwrite_delete() {
    tsod_old_uuid="$(lvs --noheadings -o lv_uuid "$SNAP_OVERWRITE_DELETE_OLD_LV" | trim)"
    tsod_final_name="$SNAP_OVERWRITE_DELETE_OLD_NAME"
    tsod_final_volid="$TEST_STORAGE_A:$tsod_final_name"
    tsod_archive_name="vm-${SNAP_OVERWRITE_DELETE_VM}-disk-901"
    tsod_archive_path="/dev/${TEST_VG_B}/${tsod_archive_name}"

    run_dryrun_unchanged "create-snapshot-overwrite-delete" create-disk-snapshot-and-overwrite-disk-on-vm.sh delete "$COPY_SRC_LV" "$SNAP_OVERWRITE_DELETE_OLD_LV" pause
    project_cmd create-disk-snapshot-and-overwrite-disk-on-vm.sh "$COPY_SRC_LV" "$SNAP_OVERWRITE_DELETE_OLD_LV" delete

    tsod_new_volid="$(qm config "$SNAP_OVERWRITE_DELETE_VM" | sed -n 's/^scsi0:[[:space:]]*//p' | head -n1 | cut -d, -f1)"
    [ "$tsod_new_volid" = "$tsod_final_volid" ]
    tsod_new_path="$(pvesm path "$tsod_new_volid")"
    [ "$(lvs --noheadings -o origin "$tsod_new_path" | trim)" = "$COPY_SRC_LV_NAME" ]
    lvs "$tsod_archive_path" >/dev/null 2>&1 && return 1
    lvs --noheadings -o lv_uuid 2>/dev/null | grep -F "$tsod_old_uuid" >/dev/null && return 1
    ! qm config "$SNAP_OVERWRITE_DELETE_VM" | grep -F "$tsod_archive_name" >/dev/null
}

test_create_copy_overwrite_empty() {
    tcoe_final_name="vm-${COPY_EMPTY_VM}-disk-0"
    tcoe_final_volid="$TEST_STORAGE_A:$tcoe_final_name"
    tcoe_final_path="/dev/${TEST_VG_A}/${tcoe_final_name}"

    run_dryrun_unchanged "create-copy-overwrite-empty" create-disk-copy-and-overwrite-disk-on-vm.sh delete "$COPY_SRC_VM" scsi0 "$COPY_EMPTY_VM" virtio boot
    project_cmd create-disk-copy-and-overwrite-disk-on-vm.sh "$COPY_SRC_VM" scsi0 "$COPY_EMPTY_VM" virtio delete boot

    [ "$(qm config "$COPY_EMPTY_VM" | sed -n 's/^virtio0:[[:space:]]*//p' | head -n1 | cut -d, -f1)" = "$tcoe_final_volid" ]
    lvs "$tcoe_final_path" >/dev/null 2>&1
    cmp -n 33554432 "$COPY_SRC_LV" "$tcoe_final_path"
    qm config "$COPY_EMPTY_VM" | grep -qE '^boot:.*order=virtio0([;,]|$)'
    ! qm config "$COPY_EMPTY_VM" | grep -E '^unused[0-9]+:' >/dev/null
    ! lvs "${TEST_VG_A}/vm-${COPY_EMPTY_VM}-disk-901" >/dev/null 2>&1
}

test_create_snapshot_overwrite_empty() {
    tsoe_final_name="vm-${SNAP_EMPTY_VM}-disk-0"
    tsoe_final_volid="$TEST_STORAGE_A:$tsoe_final_name"
    tsoe_final_path="/dev/${TEST_VG_A}/${tsoe_final_name}"

    run_dryrun_unchanged "create-snapshot-overwrite-empty" create-disk-snapshot-and-overwrite-disk-on-vm.sh delete "$COPY_SRC_VM" scsi0 "$SNAP_EMPTY_VM" sata boot
    project_cmd create-disk-snapshot-and-overwrite-disk-on-vm.sh "$COPY_SRC_VM" scsi0 "$SNAP_EMPTY_VM" sata delete boot

    [ "$(qm config "$SNAP_EMPTY_VM" | sed -n 's/^sata0:[[:space:]]*//p' | head -n1 | cut -d, -f1)" = "$tsoe_final_volid" ]
    lvs "$tsoe_final_path" >/dev/null 2>&1
    [ "$(lvs --noheadings -o origin "$tsoe_final_path" | trim)" = "$COPY_SRC_LV_NAME" ]
    qm config "$SNAP_EMPTY_VM" | grep -qE '^boot:.*order=sata0([;,]|$)'
    ! qm config "$SNAP_EMPTY_VM" | grep -E '^unused[0-9]+:' >/dev/null
    ! lvs "${TEST_VG_A}/vm-${SNAP_EMPTY_VM}-disk-901" >/dev/null 2>&1
}

test_copy_between_vms() {
    tcbv_before="$(qm config "$COPY_DST_VM" | grep -c '^scsi' || :)"
    run_dryrun_unchanged "copy-between-vms" copy-disk-between-vms.sh "$COPY_SRC_VM" scsi0 "$COPY_DST_VM" "$TEST_VG_B"
    project_cmd copy-disk-between-vms.sh "$COPY_SRC_VM" scsi0 "$COPY_DST_VM" "$TEST_VG_B"
    tcbv_after="$(qm config "$COPY_DST_VM" | grep -c '^scsi' || :)"
    [ "$tcbv_after" -gt "$tcbv_before" ]
}

test_snapshot_between_vms() {
    tsbv_before="$(qm config "$COPY_DST_VM" | grep -c '^scsi' || :)"
    run_dryrun_unchanged "snapshot-between-vms" snapshot-disk-between-vms.sh "$COPY_SRC_VM" scsi0 "$COPY_DST_VM"
    project_cmd snapshot-disk-between-vms.sh "$COPY_SRC_VM" scsi0 "$COPY_DST_VM"
    tsbv_after="$(qm config "$COPY_DST_VM" | grep -c '^scsi' || :)"
    [ "$tsbv_after" -gt "$tsbv_before" ]
}

test_clone_single_disk() {
    tcsd_before="$(qm config "$COPY_SRC_VM" | grep -c '^scsi' || :)"
    run_dryrun_unchanged "clone-single-disk" clone-single-vm-disk.sh "$COPY_SRC_VM" scsi0 "$TEST_VG_B"
    project_cmd clone-single-vm-disk.sh "$COPY_SRC_VM" scsi0 "$TEST_VG_B"
    tcsd_after="$(qm config "$COPY_SRC_VM" | grep -c '^scsi' || :)"
    [ "$tcsd_after" -gt "$tcsd_before" ]
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
