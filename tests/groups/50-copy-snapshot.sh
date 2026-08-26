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
    run_case "create-disk-snapshot-and-add-to-vm.sh hot + first-free bus + boot preservation" test_create_snapshot_add
    run_case "create-disk-copy-and-add-to-vm.sh hot + exact slot + boot preservation" test_create_copy_add
    run_case "create add helpers pause/stop/restart source-state modes" test_create_add_state_modes
    run_case "create add helpers refuse occupied exact destination slot" test_create_add_occupied_slot_refusal
    run_case "all four create helpers refuse ambiguous source disk-N" test_create_source_ambiguity_refusal
    run_case "overwrite helpers pause refuse unsafe sole-SCSI topology" test_overwrite_pause_sole_scsi_refusal
    run_case "copy overwrite rollback restores state after injected mid-transaction failure" test_copy_overwrite_injected_rollback
    run_case "snapshot overwrite rollback restores state after injected mid-transaction failure" test_snapshot_overwrite_injected_rollback
    run_case "create-disk-snapshot-and-add-to-vm.sh base/template naming" test_create_base_snapshot_add
    run_case "create-disk-copy-and-add-to-vm.sh base/template naming" test_create_base_copy_add
    run_case "create-disk-copy-and-overwrite-disk-on-vm.sh inactive base source" test_create_base_copy_overwrite_source
    run_case "create-disk-snapshot-and-overwrite-disk-on-vm.sh base/template naming" test_create_base_snapshot_overwrite
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
    printf '%s\n' "Creates only disposable source/destination VMs and 16-32 MiB loopback-backed thin disks; selected state-mode cases briefly run test VMs."
    printf '%s\n' "Covers vm/base sources, path/disk/slot selectors, occupied/exact/first-free destinations, boot-order preservation, hot/pause/stop/restart, copy/snapshot, overwrite/archive/delete, archive-number collision, empty targets and ambiguity refusal."
    printf '%s\n' "All resulting volumes remain in disposable test storages and are removed during ownership-checked cleanup."
}

############################################################
# FIXTURE
############################################################

prepare_copy_fixture() {
    COPY_SRC_VM="$(create_test_vm copy-src)"
    COPY_DST_VM="$(create_test_vm copy-dst)"
    COPY_DST_SEED_NAME="vm-${COPY_DST_VM}-disk-99"
    COPY_DST_SEED_LV="$(create_thin_lv "$TEST_VG_A" "$COPY_DST_SEED_NAME" 16M)"
    attach_test_lv "$COPY_DST_VM" "$TEST_STORAGE_A" "$COPY_DST_SEED_NAME" sata0
    qm set "$COPY_DST_VM" --boot "order=sata0" >/dev/null

    COPY_ADD_DST_VM="$(create_test_vm copy-add-dst)"
    COPY_ADD_DST_SEED_NAME="vm-${COPY_ADD_DST_VM}-disk-99"
    COPY_ADD_DST_SEED_LV="$(create_thin_lv "$TEST_VG_A" "$COPY_ADD_DST_SEED_NAME" 16M)"
    attach_test_lv "$COPY_ADD_DST_VM" "$TEST_STORAGE_A" "$COPY_ADD_DST_SEED_NAME" sata0
    qm set "$COPY_ADD_DST_VM" --boot "order=sata0" >/dev/null

    COPY_STATE_DST_VM="$(create_test_vm copy-state-dst)"

    COPY_SRC_LV_NAME="vm-${COPY_SRC_VM}-disk-0"
    COPY_SRC_LV="$(create_thin_lv "$TEST_VG_A" "$COPY_SRC_LV_NAME" 32M)"
    write_test_pattern "$COPY_SRC_LV" "copy-snapshot-source"
    attach_test_lv "$COPY_SRC_VM" "$TEST_STORAGE_A" "$COPY_SRC_LV_NAME" scsi0

    COPY_OVERWRITE_VM="$(create_test_vm copy-overwrite)"
    qm set "$COPY_OVERWRITE_VM" --scsihw virtio-scsi-pci >/dev/null
    COPY_OVERWRITE_OLD_NAME="vm-${COPY_OVERWRITE_VM}-disk-0"
    COPY_OVERWRITE_OLD_LV="$(create_thin_lv "$TEST_VG_B" "$COPY_OVERWRITE_OLD_NAME" 32M)"
    write_test_pattern "$COPY_OVERWRITE_OLD_LV" "copy-overwrite-old"
    attach_test_lv "$COPY_OVERWRITE_VM" "$TEST_STORAGE_B" "$COPY_OVERWRITE_OLD_NAME" scsi0
    COPY_OVERWRITE_KEEPER_NAME="vm-${COPY_OVERWRITE_VM}-disk-98"
    COPY_OVERWRITE_KEEPER_LV="$(create_thin_lv "$TEST_VG_B" "$COPY_OVERWRITE_KEEPER_NAME" 16M)"
    attach_test_lv "$COPY_OVERWRITE_VM" "$TEST_STORAGE_B" "$COPY_OVERWRITE_KEEPER_NAME" scsi1
    COPY_OVERWRITE_OCCUPIED_ARCHIVE_NAME="vm-${COPY_OVERWRITE_VM}-disk-901"
    COPY_OVERWRITE_OCCUPIED_ARCHIVE_LV="$(create_thin_lv "$TEST_VG_B" "$COPY_OVERWRITE_OCCUPIED_ARCHIVE_NAME" 16M)"
    COPY_OVERWRITE_OCCUPIED_ARCHIVE_UUID="$(lvs --noheadings -o lv_uuid "$COPY_OVERWRITE_OCCUPIED_ARCHIVE_LV" | awk '{$1=$1;print}')"

    SNAP_OVERWRITE_VM="$(create_test_vm snapshot-overwrite)"
    SNAP_OVERWRITE_OLD_NAME="vm-${SNAP_OVERWRITE_VM}-disk-0"
    SNAP_OVERWRITE_OLD_LV="$(create_thin_lv "$TEST_VG_B" "$SNAP_OVERWRITE_OLD_NAME" 32M)"
    write_test_pattern "$SNAP_OVERWRITE_OLD_LV" "snapshot-overwrite-old"
    attach_test_lv "$SNAP_OVERWRITE_VM" "$TEST_STORAGE_B" "$SNAP_OVERWRITE_OLD_NAME" scsi0
    SNAP_OVERWRITE_OCCUPIED_ARCHIVE_NAME="vm-${SNAP_OVERWRITE_VM}-disk-901"
    SNAP_OVERWRITE_OCCUPIED_ARCHIVE_LV="$(create_thin_lv "$TEST_VG_B" "$SNAP_OVERWRITE_OCCUPIED_ARCHIVE_NAME" 16M)"
    SNAP_OVERWRITE_OCCUPIED_ARCHIVE_UUID="$(lvs --noheadings -o lv_uuid "$SNAP_OVERWRITE_OCCUPIED_ARCHIVE_LV" | awk '{$1=$1;print}')"


    COPY_OVERWRITE_DELETE_VM="$(create_test_vm copy-overwrite-delete)"
    COPY_OVERWRITE_DELETE_OLD_NAME="vm-${COPY_OVERWRITE_DELETE_VM}-disk-0"
    COPY_OVERWRITE_DELETE_OLD_LV="$(create_thin_lv "$TEST_VG_B" "$COPY_OVERWRITE_DELETE_OLD_NAME" 32M)"
    write_test_pattern "$COPY_OVERWRITE_DELETE_OLD_LV" "copy-overwrite-delete-old"
    attach_test_lv "$COPY_OVERWRITE_DELETE_VM" "$TEST_STORAGE_B" "$COPY_OVERWRITE_DELETE_OLD_NAME" scsi0

    SNAP_OVERWRITE_DELETE_VM="$(create_test_vm snapshot-overwrite-delete)"
    qm set "$SNAP_OVERWRITE_DELETE_VM" --scsihw virtio-scsi-pci >/dev/null
    SNAP_OVERWRITE_DELETE_OLD_NAME="vm-${SNAP_OVERWRITE_DELETE_VM}-disk-0"
    SNAP_OVERWRITE_DELETE_OLD_LV="$(create_thin_lv "$TEST_VG_B" "$SNAP_OVERWRITE_DELETE_OLD_NAME" 32M)"
    write_test_pattern "$SNAP_OVERWRITE_DELETE_OLD_LV" "snapshot-overwrite-delete-old"
    attach_test_lv "$SNAP_OVERWRITE_DELETE_VM" "$TEST_STORAGE_B" "$SNAP_OVERWRITE_DELETE_OLD_NAME" scsi0
    SNAP_OVERWRITE_DELETE_KEEPER_NAME="vm-${SNAP_OVERWRITE_DELETE_VM}-disk-98"
    SNAP_OVERWRITE_DELETE_KEEPER_LV="$(create_thin_lv "$TEST_VG_B" "$SNAP_OVERWRITE_DELETE_KEEPER_NAME" 16M)"
    attach_test_lv "$SNAP_OVERWRITE_DELETE_VM" "$TEST_STORAGE_B" "$SNAP_OVERWRITE_DELETE_KEEPER_NAME" scsi1

    COPY_EMPTY_VM="$(create_test_vm copy-empty-target)"
    SNAP_EMPTY_VM="$(create_test_vm snapshot-empty-target)"

    BASE_SRC_VM="$(create_test_vm base-copy-src)"
    BASE_SRC_SEED="vm-${BASE_SRC_VM}-disk-0"
    BASE_SRC_SEED_LV="$(create_thin_lv "$TEST_VG_A" "$BASE_SRC_SEED" 32M)"
    write_test_pattern "$BASE_SRC_SEED_LV" "base-copy-source"
    attach_test_lv "$BASE_SRC_VM" "$TEST_STORAGE_A" "$BASE_SRC_SEED" scsi0
    qm template "$BASE_SRC_VM" >/dev/null
    BASE_SRC_NAME="base-${BASE_SRC_VM}-disk-0"
    BASE_SRC_LV="/dev/${TEST_VG_A}/${BASE_SRC_NAME}"
    assert_lv_exists "$TEST_VG_A/$BASE_SRC_NAME"
    lvchange -an "$TEST_VG_A/$BASE_SRC_NAME" >/dev/null || die "Could not make the disposable base source inactive."
    [ ! -b "$BASE_SRC_LV" ] || die "Disposable base source is still active; inactive-source coverage would be invalid."

    BASE_DST_VM="$(create_test_vm base-copy-dst)"
    BASE_DST_SEED="vm-${BASE_DST_VM}-disk-0"
    create_thin_lv "$TEST_VG_A" "$BASE_DST_SEED" 16M >/dev/null
    attach_test_lv "$BASE_DST_VM" "$TEST_STORAGE_A" "$BASE_DST_SEED" scsi0
    qm template "$BASE_DST_VM" >/dev/null
    assert_lv_exists "$TEST_VG_A/base-${BASE_DST_VM}-disk-0"

    BASE_COPY_DST_VM="$(create_test_vm base-copy-independent-dst)"
    BASE_COPY_DST_SEED="vm-${BASE_COPY_DST_VM}-disk-0"
    create_thin_lv "$TEST_VG_A" "$BASE_COPY_DST_SEED" 16M >/dev/null
    attach_test_lv "$BASE_COPY_DST_VM" "$TEST_STORAGE_A" "$BASE_COPY_DST_SEED" scsi0
    qm template "$BASE_COPY_DST_VM" >/dev/null
    assert_lv_exists "$TEST_VG_A/base-${BASE_COPY_DST_VM}-disk-0"

    BASE_COPY_OVERWRITE_VM="$(create_test_vm base-copy-overwrite)"
    BASE_COPY_OVERWRITE_OLD_NAME="vm-${BASE_COPY_OVERWRITE_VM}-disk-0"
    BASE_COPY_OVERWRITE_OLD_LV="$(create_thin_lv "$TEST_VG_B" "$BASE_COPY_OVERWRITE_OLD_NAME" 32M)"
    write_test_pattern "$BASE_COPY_OVERWRITE_OLD_LV" "base-copy-overwrite-old"
    attach_test_lv "$BASE_COPY_OVERWRITE_VM" "$TEST_STORAGE_B" "$BASE_COPY_OVERWRITE_OLD_NAME" scsi0

    BASE_OVERWRITE_VM="$(create_test_vm base-overwrite)"
    BASE_OVERWRITE_SEED="vm-${BASE_OVERWRITE_VM}-disk-0"
    create_thin_lv "$TEST_VG_B" "$BASE_OVERWRITE_SEED" 32M >/dev/null
    attach_test_lv "$BASE_OVERWRITE_VM" "$TEST_STORAGE_B" "$BASE_OVERWRITE_SEED" scsi0
    qm template "$BASE_OVERWRITE_VM" >/dev/null
    assert_lv_exists "$TEST_VG_B/base-${BASE_OVERWRITE_VM}-disk-0"
}

############################################################
# TEST CASES
############################################################

assert_test_lv_inactive() {
    atli_lv="$1"
    atli_attr="$(lvs --noheadings -o lv_attr "$atli_lv" 2>/dev/null | awk '{$1=$1;print}')"
    case "$atli_attr" in ????a*) printf 'Expected LV to be inactive, but lv_attr is %s: %s\n' "$atli_attr" "$atli_lv" >&2; return 1 ;; esac
    atli_path="$(lvs --noheadings -o lv_path "$atli_lv" 2>/dev/null | awk '{$1=$1;print}')"
    [ -n "$atli_path" ] || return 1
    [ ! -b "$atli_path" ]
}

compare_inactive_test_lv() (
    citl_lv="$1"; citl_dst="$2"; citl_bytes="$3"
    citl_path="$(lvs --noheadings -o lv_path "$citl_lv" 2>/dev/null | awk '{$1=$1;print}')"
    [ -n "$citl_path" ] || exit 1
    trap 'lvchange -an "$citl_lv" >/dev/null 2>&1 || :' 0 HUP INT TERM
    lvchange -ay -K "$citl_lv" >/dev/null
    cmp -n "$citl_bytes" "$citl_path" "$citl_dst"
)

test_create_snapshot_add() {
    qm start "$COPY_SRC_VM" >/dev/null
    [ "$(qm status "$COPY_SRC_VM" | awk '{print $2}')" = "running" ]

    run_dryrun_unchanged "create-snapshot-add" create-disk-snapshot-and-add-to-vm.sh hot "$COPY_SRC_VM" scsi0 "$COPY_DST_VM" sata boot
    project_cmd create-disk-snapshot-and-add-to-vm.sh "$COPY_SRC_VM" scsi0 "$COPY_DST_VM" sata boot hot
    [ "$(qm status "$COPY_SRC_VM" | awk '{print $2}')" = "running" ]

    tcsa_volid="$(qm config "$COPY_DST_VM" | sed -n 's/^sata1:[[:space:]]*//p' | head -n1 | cut -d, -f1)"
    [ -n "$tcsa_volid" ]
    lvs --noheadings -o origin "$(pvesm path "$tcsa_volid")" 2>/dev/null | grep -F "$COPY_SRC_LV_NAME" >/dev/null
    qm config "$COPY_DST_VM" | grep -qE '^boot:.*order=sata1;sata0([;,]|$)'
}

test_create_copy_add() {
    if [ "$(qm status "$COPY_SRC_VM" | awk '{print $2}')" != "running" ]; then qm start "$COPY_SRC_VM" >/dev/null; fi
    run_dryrun_unchanged "create-copy-add" create-disk-copy-and-add-to-vm.sh "$COPY_SRC_VM" scsi0 "$COPY_ADD_DST_VM" virtio0 "$TEST_VG_B" boot
    project_cmd create-disk-copy-and-add-to-vm.sh "$COPY_SRC_VM" scsi0 "$COPY_ADD_DST_VM" virtio0 "$TEST_VG_B" boot
    [ "$(qm status "$COPY_SRC_VM" | awk '{print $2}')" = "running" ]

    tcca_volid="$(qm config "$COPY_ADD_DST_VM" | sed -n 's/^virtio0:[[:space:]]*//p' | head -n1 | cut -d, -f1)"
    case "$tcca_volid" in "$TEST_STORAGE_B":vm-"${COPY_ADD_DST_VM}"-disk-*) ;; *) return 1 ;; esac
    cmp -n 33554432 "$COPY_SRC_LV" "$(pvesm path "$tcca_volid")"
    qm config "$COPY_ADD_DST_VM" | grep -qE '^boot:.*order=virtio0;sata0([;,]|$)'
}

test_create_add_state_modes() {
    if [ "$(qm status "$COPY_SRC_VM" | awk '{print $2}')" != "running" ]; then qm start "$COPY_SRC_VM" >/dev/null; fi

    run_dryrun_unchanged "create-snapshot-add-pause" create-disk-snapshot-and-add-to-vm.sh pause "$COPY_SRC_LV" "$COPY_STATE_DST_VM" ide
    project_cmd create-disk-snapshot-and-add-to-vm.sh "$COPY_SRC_LV" "$COPY_STATE_DST_VM" ide pause
    [ "$(qm status "$COPY_SRC_VM" | awk '{print $2}')" = "running" ]
    tsa_pause_volid="$(qm config "$COPY_STATE_DST_VM" | sed -n 's/^ide0:[[:space:]]*//p' | head -n1 | cut -d, -f1)"
    [ "$(lvs --noheadings -o origin "$(pvesm path "$tsa_pause_volid")" | awk '{$1=$1;print}')" = "$COPY_SRC_LV_NAME" ]

    run_dryrun_unchanged "create-copy-add-stop" create-disk-copy-and-add-to-vm.sh stop "$COPY_SRC_VM" disk-0 "$COPY_STATE_DST_VM" sata "$TEST_VG_B"
    project_cmd create-disk-copy-and-add-to-vm.sh "$COPY_SRC_VM" disk-0 "$COPY_STATE_DST_VM" sata "$TEST_VG_B" stop
    [ "$(qm status "$COPY_SRC_VM" | awk '{print $2}')" = "stopped" ]

    qm start "$COPY_SRC_VM" >/dev/null
    [ "$(qm status "$COPY_SRC_VM" | awk '{print $2}')" = "running" ]
    run_dryrun_unchanged "create-copy-add-restart" create-disk-copy-and-add-to-vm.sh restart "$COPY_SRC_VM" scsi0 "$COPY_STATE_DST_VM" virtio "$TEST_VG_B"
    project_cmd create-disk-copy-and-add-to-vm.sh "$COPY_SRC_VM" scsi0 "$COPY_STATE_DST_VM" virtio "$TEST_VG_B" restart
    [ "$(qm status "$COPY_SRC_VM" | awk '{print $2}')" = "running" ]
}

test_create_add_occupied_slot_refusal() {
    run_expect_fail_unchanged "snapshot-add-occupied-sata0" create-disk-snapshot-and-add-to-vm.sh "$COPY_SRC_VM" scsi0 "$COPY_DST_VM" sata0
    run_expect_fail_unchanged "copy-add-occupied-sata0" create-disk-copy-and-add-to-vm.sh "$COPY_SRC_VM" scsi0 "$COPY_DST_VM" sata0 "$TEST_VG_B"
}

test_create_source_ambiguity_refusal() {
    tcsar_src="$(create_test_vm create-ambiguous-src)"
    tcsar_dst="$(create_test_vm create-ambiguous-dst)"
    tcsar_foreign="$(allocate_free_vmid)"
    tcsar_vm_name="vm-${tcsar_src}-disk-0"
    tcsar_base_name="base-${tcsar_foreign}-disk-0"
    create_thin_lv "$TEST_VG_A" "$tcsar_vm_name" 16M >/dev/null
    create_thin_lv "$TEST_VG_A" "$tcsar_base_name" 16M >/dev/null
    attach_test_lv "$tcsar_src" "$TEST_STORAGE_A" "$tcsar_vm_name" scsi0
    attach_test_lv "$tcsar_src" "$TEST_STORAGE_A" "$tcsar_base_name" scsi1

    run_expect_fail_unchanged "copy-add-ambiguous-source" create-disk-copy-and-add-to-vm.sh "$tcsar_src" disk-0 "$tcsar_dst" scsi0 "$TEST_VG_B"
    run_expect_fail_unchanged "snapshot-add-ambiguous-source" create-disk-snapshot-and-add-to-vm.sh "$tcsar_src" disk-0 "$tcsar_dst" scsi0
    run_expect_fail_unchanged "copy-overwrite-ambiguous-source" create-disk-copy-and-overwrite-disk-on-vm.sh "$tcsar_src" disk-0 "$tcsar_dst" scsi0
    run_expect_fail_unchanged "snapshot-overwrite-ambiguous-source" create-disk-snapshot-and-overwrite-disk-on-vm.sh "$tcsar_src" disk-0 "$tcsar_dst" scsi0
}

test_overwrite_pause_sole_scsi_refusal() {
    tops_copy_vm="$(create_test_vm overwrite-pause-sole-copy)"
    tops_copy_name="vm-${tops_copy_vm}-disk-0"
    tops_copy_lv="$(create_thin_lv "$TEST_VG_B" "$tops_copy_name" 16M)"
    attach_test_lv "$tops_copy_vm" "$TEST_STORAGE_B" "$tops_copy_name" scsi0
    qm start "$tops_copy_vm" >/dev/null
    run_expect_fail_unchanged "copy-overwrite-pause-sole-scsi" create-disk-copy-and-overwrite-disk-on-vm.sh "$COPY_SRC_VM" scsi0 "$tops_copy_vm" scsi0 pause
    qm config "$tops_copy_vm" | grep -F "scsi0: $TEST_STORAGE_B:$tops_copy_name" >/dev/null
    assert_lv_exists "$tops_copy_lv"
    qm stop "$tops_copy_vm" >/dev/null

    tops_snap_vm="$(create_test_vm overwrite-pause-sole-snapshot)"
    tops_snap_name="vm-${tops_snap_vm}-disk-0"
    tops_snap_lv="$(create_thin_lv "$TEST_VG_B" "$tops_snap_name" 16M)"
    attach_test_lv "$tops_snap_vm" "$TEST_STORAGE_B" "$tops_snap_name" scsi0
    qm start "$tops_snap_vm" >/dev/null
    run_expect_fail_unchanged "snapshot-overwrite-pause-sole-scsi" create-disk-snapshot-and-overwrite-disk-on-vm.sh "$COPY_SRC_VM" scsi0 "$tops_snap_vm" scsi0 pause
    qm config "$tops_snap_vm" | grep -F "scsi0: $TEST_STORAGE_B:$tops_snap_name" >/dev/null
    assert_lv_exists "$tops_snap_lv"
    qm stop "$tops_snap_vm" >/dev/null
}


# make_failure_injected_helper <source-script> <destination-script> <attach-info-line>
#
# Creates a test-only standalone copy that aborts immediately before the
# replacement attach step. At that point the old disk has been detached and
# archived and the staged replacement has already taken the final disk number.
make_failure_injected_helper() {
    mfih_source="$1"
    mfih_destination="$2"
    mfih_attach_line="$3"

    awk -v marker="$mfih_attach_line" '
        $0 == marker {
            print "    die \"TEST-INJECTED: abort before replacement attachment\""
        }
        { print }
    ' "$PROJECT_ROOT/$mfih_source" > "$mfih_destination"
    grep -F 'TEST-INJECTED: abort before replacement attachment' "$mfih_destination" >/dev/null ||
        die "Could not construct failure-injected helper: $mfih_source"
}

test_copy_overwrite_injected_rollback() {
    tcoir_vm="$(create_test_vm overwrite-copy-rollback)"
    tcoir_old_name="vm-${tcoir_vm}-disk-0"
    tcoir_old_lv="$(create_thin_lv "$TEST_VG_B" "$tcoir_old_name" 32M)"
    write_test_pattern "$tcoir_old_lv" "copy-overwrite-rollback-old"
    attach_test_lv "$tcoir_vm" "$TEST_STORAGE_B" "$tcoir_old_name" scsi0
    tcoir_old_uuid="$(lvs --noheadings -o lv_uuid "$tcoir_old_lv" | awk '{$1=$1;print}')"

    tcoir_script="$TEST_DATA_DIR/injected-copy-overwrite.sh"
    make_failure_injected_helper \
        create-disk-copy-and-overwrite-disk-on-vm.sh \
        "$tcoir_script" \
        '    info "Attaching replacement $NEW_VOLID at $DEST_SLOT..."'

    run_script_expect_fail_unchanged \
        "copy-overwrite-rollback-injected" \
        "$tcoir_script" \
        "$COPY_SRC_VM" scsi0 "$tcoir_vm" scsi0

    grep -F 'TEST-INJECTED: abort before replacement attachment' \
        "$TEST_RESULT_DIR/refusal-output-copy-overwrite-rollback-injected.log" >/dev/null
    [ "$(lvs --noheadings -o lv_uuid "$tcoir_old_lv" | awk '{$1=$1;print}')" = "$tcoir_old_uuid" ]
    qm config "$tcoir_vm" | grep -F "scsi0: $TEST_STORAGE_B:$tcoir_old_name" >/dev/null
    ! qm config "$tcoir_vm" | grep -E '^unused[0-9]+:' >/dev/null
}

test_snapshot_overwrite_injected_rollback() {
    tsoir_vm="$(create_test_vm overwrite-snapshot-rollback)"
    tsoir_old_name="vm-${tsoir_vm}-disk-0"
    tsoir_old_lv="$(create_thin_lv "$TEST_VG_B" "$tsoir_old_name" 32M)"
    write_test_pattern "$tsoir_old_lv" "snapshot-overwrite-rollback-old"
    attach_test_lv "$tsoir_vm" "$TEST_STORAGE_B" "$tsoir_old_name" scsi0
    tsoir_old_uuid="$(lvs --noheadings -o lv_uuid "$tsoir_old_lv" | awk '{$1=$1;print}')"

    tsoir_script="$TEST_DATA_DIR/injected-snapshot-overwrite.sh"
    make_failure_injected_helper \
        create-disk-snapshot-and-overwrite-disk-on-vm.sh \
        "$tsoir_script" \
        '    info "Attaching snapshot $NEW_VOLID at $DEST_SLOT..."'

    run_script_expect_fail_unchanged \
        "snapshot-overwrite-rollback-injected" \
        "$tsoir_script" \
        "$COPY_SRC_VM" scsi0 "$tsoir_vm" scsi0

    grep -F 'TEST-INJECTED: abort before replacement attachment' \
        "$TEST_RESULT_DIR/refusal-output-snapshot-overwrite-rollback-injected.log" >/dev/null
    [ "$(lvs --noheadings -o lv_uuid "$tsoir_old_lv" | awk '{$1=$1;print}')" = "$tsoir_old_uuid" ]
    qm config "$tsoir_vm" | grep -F "scsi0: $TEST_STORAGE_B:$tsoir_old_name" >/dev/null
    ! qm config "$tsoir_vm" | grep -E '^unused[0-9]+:' >/dev/null
}

test_create_base_snapshot_add() {
    tcbsa_name="base-${BASE_DST_VM}-disk-1"
    run_dryrun_unchanged "create-base-snapshot-add" create-disk-snapshot-and-add-to-vm.sh "$BASE_SRC_VM" disk-0 "$BASE_DST_VM" scsi1
    project_cmd create-disk-snapshot-and-add-to-vm.sh "$BASE_SRC_VM" disk-0 "$BASE_DST_VM" scsi1

    tcbsa_volid="$(qm config "$BASE_DST_VM" | sed -n 's/^scsi1:[[:space:]]*//p' | head -n1 | cut -d, -f1)"
    [ "$tcbsa_volid" = "$TEST_STORAGE_A:$tcbsa_name" ]
    assert_lv_exists "$TEST_VG_A/$tcbsa_name"
    [ "$(lvs --noheadings -o origin "/dev/${TEST_VG_A}/${tcbsa_name}" | awk '{$1=$1;print}')" = "$BASE_SRC_NAME" ]
}

test_create_base_copy_add() {
    tcbca_name="base-${BASE_COPY_DST_VM}-disk-1"
    run_dryrun_unchanged "create-base-copy-add" create-disk-copy-and-add-to-vm.sh "$BASE_SRC_VM" disk-0 "$BASE_COPY_DST_VM" virtio0 "$TEST_VG_B"
    project_cmd create-disk-copy-and-add-to-vm.sh "$BASE_SRC_VM" disk-0 "$BASE_COPY_DST_VM" virtio0 "$TEST_VG_B"

    tcbca_volid="$(qm config "$BASE_COPY_DST_VM" | sed -n 's/^virtio0:[[:space:]]*//p' | head -n1 | cut -d, -f1)"
    [ "$tcbca_volid" = "$TEST_STORAGE_B:$tcbca_name" ]
    assert_lv_exists "$TEST_VG_B/$tcbca_name"
    assert_test_lv_inactive "$TEST_VG_A/$BASE_SRC_NAME"
    compare_inactive_test_lv "$TEST_VG_A/$BASE_SRC_NAME" "/dev/${TEST_VG_B}/${tcbca_name}" 33554432
    assert_test_lv_inactive "$TEST_VG_A/$BASE_SRC_NAME"
}

test_create_base_copy_overwrite_source() {
    tcbcos_old_uuid="$(lvs --noheadings -o lv_uuid "$BASE_COPY_OVERWRITE_OLD_LV" | awk '{$1=$1;print}')"
    tcbcos_final_name="vm-${BASE_COPY_OVERWRITE_VM}-disk-0"
    tcbcos_archive_name="vm-${BASE_COPY_OVERWRITE_VM}-disk-901"

    assert_test_lv_inactive "$TEST_VG_A/$BASE_SRC_NAME"
    run_dryrun_unchanged "create-base-copy-overwrite-source" create-disk-copy-and-overwrite-disk-on-vm.sh "$BASE_SRC_VM" disk-0 "$BASE_COPY_OVERWRITE_VM" disk-0
    assert_test_lv_inactive "$TEST_VG_A/$BASE_SRC_NAME"

    project_cmd create-disk-copy-and-overwrite-disk-on-vm.sh "$BASE_SRC_VM" disk-0 "$BASE_COPY_OVERWRITE_VM" disk-0
    assert_test_lv_inactive "$TEST_VG_A/$BASE_SRC_NAME"

    [ "$(qm config "$BASE_COPY_OVERWRITE_VM" | sed -n 's/^scsi0:[[:space:]]*//p' | head -n1 | cut -d, -f1)" = "$TEST_STORAGE_B:$tcbcos_final_name" ]
    assert_lv_exists "$TEST_VG_B/$tcbcos_final_name"
    assert_lv_exists "$TEST_VG_B/$tcbcos_archive_name"
    [ "$(lvs --noheadings -o lv_uuid "/dev/${TEST_VG_B}/${tcbcos_archive_name}" | awk '{$1=$1;print}')" = "$tcbcos_old_uuid" ]
    compare_inactive_test_lv "$TEST_VG_A/$BASE_SRC_NAME" "/dev/${TEST_VG_B}/${tcbcos_final_name}" 33554432
    assert_test_lv_inactive "$TEST_VG_A/$BASE_SRC_NAME"
}

test_create_base_snapshot_overwrite() {
    tcbso_old_name="base-${BASE_OVERWRITE_VM}-disk-0"
    tcbso_old_uuid="$(lvs --noheadings -o lv_uuid "/dev/${TEST_VG_B}/${tcbso_old_name}" | awk '{$1=$1;print}')"
    tcbso_final_volid="$TEST_STORAGE_A:$tcbso_old_name"
    tcbso_archive_name="base-${BASE_OVERWRITE_VM}-disk-901"
    tcbso_archive_volid="$TEST_STORAGE_B:$tcbso_archive_name"

    run_dryrun_unchanged "create-base-snapshot-overwrite" create-disk-snapshot-and-overwrite-disk-on-vm.sh "$BASE_SRC_VM" disk-0 "$BASE_OVERWRITE_VM" disk-0
    project_cmd create-disk-snapshot-and-overwrite-disk-on-vm.sh "$BASE_SRC_VM" disk-0 "$BASE_OVERWRITE_VM" disk-0
    [ "$(qm status "$BASE_OVERWRITE_VM" | awk '{print $2}')" = "stopped" ]

    [ "$(qm config "$BASE_OVERWRITE_VM" | sed -n 's/^scsi0:[[:space:]]*//p' | head -n1 | cut -d, -f1)" = "$tcbso_final_volid" ]
    assert_lv_exists "$TEST_VG_A/$tcbso_old_name"
    [ "$(lvs --noheadings -o origin "/dev/${TEST_VG_A}/${tcbso_old_name}" | awk '{$1=$1;print}')" = "$BASE_SRC_NAME" ]
    [ "$(lvs --noheadings -o lv_uuid "/dev/${TEST_VG_B}/${tcbso_archive_name}" | awk '{$1=$1;print}')" = "$tcbso_old_uuid" ]
    qm config "$BASE_OVERWRITE_VM" | grep -E "^unused[0-9]+: ${tcbso_archive_volid}([,[:space:]]|$)" >/dev/null
}

test_create_copy_overwrite() {
    tcow_old_volid="$TEST_STORAGE_B:$COPY_OVERWRITE_OLD_NAME"
    tcow_old_uuid="$(lvs --noheadings -o lv_uuid "$COPY_OVERWRITE_OLD_LV" | awk '{$1=$1;print}')"
    tcow_archive_name="vm-${COPY_OVERWRITE_VM}-disk-902"
    tcow_archive_volid="$TEST_STORAGE_B:$tcow_archive_name"
    tcow_archive_path="/dev/${TEST_VG_B}/${tcow_archive_name}"

    qm start "$COPY_OVERWRITE_VM" >/dev/null
    [ "$(qm status "$COPY_OVERWRITE_VM" | awk '{print $2}')" = "running" ]
    run_dryrun_unchanged "create-copy-overwrite" create-disk-copy-and-overwrite-disk-on-vm.sh "$COPY_SRC_VM" scsi0 "$COPY_OVERWRITE_VM" scsi0 pause boot
    project_cmd create-disk-copy-and-overwrite-disk-on-vm.sh "$COPY_SRC_VM" scsi0 "$COPY_OVERWRITE_VM" scsi0 pause boot
    [ "$(qm status "$COPY_OVERWRITE_VM" | awk '{print $2}')" = "running" ]

    tcow_new_volid="$(qm config "$COPY_OVERWRITE_VM" | sed -n 's/^scsi0:[[:space:]]*//p' | head -n1 | cut -d, -f1)"
    [ "$tcow_new_volid" = "$tcow_old_volid" ]
    tcow_new_path="$(pvesm path "$tcow_new_volid")"
    tcow_new_uuid="$(lvs --noheadings -o lv_uuid "$tcow_new_path" | awk '{$1=$1;print}')"
    [ "$tcow_new_uuid" != "$tcow_old_uuid" ]
    cmp -n 33554432 "$COPY_SRC_LV" "$tcow_new_path"

    [ "$(lvs --noheadings -o lv_uuid "$tcow_archive_path" | awk '{$1=$1;print}')" = "$tcow_old_uuid" ]
    [ "$(lvs --noheadings -o lv_uuid "$COPY_OVERWRITE_OCCUPIED_ARCHIVE_LV" | awk '{$1=$1;print}')" = "$COPY_OVERWRITE_OCCUPIED_ARCHIVE_UUID" ]
    qm config "$COPY_OVERWRITE_VM" | grep -E "^unused[0-9]+: ${tcow_archive_volid}([,[:space:]]|$)" >/dev/null
    qm config "$COPY_OVERWRITE_VM" | grep -F "scsi1: $TEST_STORAGE_B:$COPY_OVERWRITE_KEEPER_NAME" >/dev/null
    assert_lv_exists "$COPY_OVERWRITE_KEEPER_LV"
    qm config "$COPY_OVERWRITE_VM" | grep -qE '^boot:.*order=scsi0([;,]|$)'
}

test_create_snapshot_overwrite() {
    tsow_old_uuid="$(lvs --noheadings -o lv_uuid "$SNAP_OVERWRITE_OLD_LV" | awk '{$1=$1;print}')"
    tsow_final_name="$SNAP_OVERWRITE_OLD_NAME"
    tsow_final_volid="$TEST_STORAGE_A:$tsow_final_name"
    tsow_archive_name="vm-${SNAP_OVERWRITE_VM}-disk-902"
    tsow_archive_volid="$TEST_STORAGE_B:$tsow_archive_name"
    tsow_archive_path="/dev/${TEST_VG_B}/${tsow_archive_name}"

    qm start "$SNAP_OVERWRITE_VM" >/dev/null
    [ "$(qm status "$SNAP_OVERWRITE_VM" | awk '{print $2}')" = "running" ]
    run_dryrun_unchanged "create-snapshot-overwrite" create-disk-snapshot-and-overwrite-disk-on-vm.sh "$COPY_SRC_VM" scsi0 "$SNAP_OVERWRITE_VM" scsi0 restart boot
    project_cmd create-disk-snapshot-and-overwrite-disk-on-vm.sh "$COPY_SRC_VM" scsi0 "$SNAP_OVERWRITE_VM" scsi0 restart boot
    [ "$(qm status "$SNAP_OVERWRITE_VM" | awk '{print $2}')" = "running" ]

    tsow_new_volid="$(qm config "$SNAP_OVERWRITE_VM" | sed -n 's/^scsi0:[[:space:]]*//p' | head -n1 | cut -d, -f1)"
    [ "$tsow_new_volid" = "$tsow_final_volid" ]
    tsow_new_path="$(pvesm path "$tsow_new_volid")"
    tsow_origin="$(lvs --noheadings -o origin "$tsow_new_path" | awk '{$1=$1;print}')"
    [ "$tsow_origin" = "$COPY_SRC_LV_NAME" ]

    [ "$(lvs --noheadings -o lv_uuid "$tsow_archive_path" | awk '{$1=$1;print}')" = "$tsow_old_uuid" ]
    [ "$(lvs --noheadings -o lv_uuid "$SNAP_OVERWRITE_OCCUPIED_ARCHIVE_LV" | awk '{$1=$1;print}')" = "$SNAP_OVERWRITE_OCCUPIED_ARCHIVE_UUID" ]
    qm config "$SNAP_OVERWRITE_VM" | grep -E "^unused[0-9]+: ${tsow_archive_volid}([,[:space:]]|$)" >/dev/null
    qm config "$SNAP_OVERWRITE_VM" | grep -qE '^boot:.*order=scsi0([;,]|$)'
}

test_create_copy_overwrite_delete() {
    tcod_old_uuid="$(lvs --noheadings -o lv_uuid "$COPY_OVERWRITE_DELETE_OLD_LV" | awk '{$1=$1;print}')"
    tcod_final_volid="$TEST_STORAGE_B:$COPY_OVERWRITE_DELETE_OLD_NAME"
    tcod_archive_name="vm-${COPY_OVERWRITE_DELETE_VM}-disk-901"
    tcod_archive_path="/dev/${TEST_VG_B}/${tcod_archive_name}"

    qm start "$COPY_OVERWRITE_DELETE_VM" >/dev/null
    run_dryrun_unchanged "create-copy-overwrite-delete" create-disk-copy-and-overwrite-disk-on-vm.sh delete "$COPY_SRC_VM" disk-0 "$COPY_OVERWRITE_DELETE_VM" disk-0 stop
    project_cmd create-disk-copy-and-overwrite-disk-on-vm.sh "$COPY_SRC_VM" disk-0 "$COPY_OVERWRITE_DELETE_VM" disk-0 delete stop
    [ "$(qm status "$COPY_OVERWRITE_DELETE_VM" | awk '{print $2}')" = "stopped" ]

    tcod_new_volid="$(qm config "$COPY_OVERWRITE_DELETE_VM" | sed -n 's/^scsi0:[[:space:]]*//p' | head -n1 | cut -d, -f1)"
    [ "$tcod_new_volid" = "$tcod_final_volid" ]
    cmp -n 33554432 "$COPY_SRC_LV" "$(pvesm path "$tcod_new_volid")"
    lvs "$tcod_archive_path" >/dev/null 2>&1 && return 1
    lvs --noheadings -o lv_uuid 2>/dev/null | grep -F "$tcod_old_uuid" >/dev/null && return 1
    ! qm config "$COPY_OVERWRITE_DELETE_VM" | grep -F "$tcod_archive_name" >/dev/null
}

test_create_snapshot_overwrite_delete() {
    tsod_old_uuid="$(lvs --noheadings -o lv_uuid "$SNAP_OVERWRITE_DELETE_OLD_LV" | awk '{$1=$1;print}')"
    tsod_final_name="$SNAP_OVERWRITE_DELETE_OLD_NAME"
    tsod_final_volid="$TEST_STORAGE_A:$tsod_final_name"
    tsod_archive_name="vm-${SNAP_OVERWRITE_DELETE_VM}-disk-901"
    tsod_archive_path="/dev/${TEST_VG_B}/${tsod_archive_name}"

    qm start "$SNAP_OVERWRITE_DELETE_VM" >/dev/null
    run_dryrun_unchanged "create-snapshot-overwrite-delete" create-disk-snapshot-and-overwrite-disk-on-vm.sh delete "$COPY_SRC_LV" "$SNAP_OVERWRITE_DELETE_OLD_LV" pause
    project_cmd create-disk-snapshot-and-overwrite-disk-on-vm.sh "$COPY_SRC_LV" "$SNAP_OVERWRITE_DELETE_OLD_LV" delete pause
    [ "$(qm status "$SNAP_OVERWRITE_DELETE_VM" | awk '{print $2}')" = "running" ]

    tsod_new_volid="$(qm config "$SNAP_OVERWRITE_DELETE_VM" | sed -n 's/^scsi0:[[:space:]]*//p' | head -n1 | cut -d, -f1)"
    [ "$tsod_new_volid" = "$tsod_final_volid" ]
    tsod_new_path="$(pvesm path "$tsod_new_volid")"
    [ "$(lvs --noheadings -o origin "$tsod_new_path" | awk '{$1=$1;print}')" = "$COPY_SRC_LV_NAME" ]
    lvs "$tsod_archive_path" >/dev/null 2>&1 && return 1
    lvs --noheadings -o lv_uuid 2>/dev/null | grep -F "$tsod_old_uuid" >/dev/null && return 1
    ! qm config "$SNAP_OVERWRITE_DELETE_VM" | grep -F "$tsod_archive_name" >/dev/null
    qm config "$SNAP_OVERWRITE_DELETE_VM" | grep -F "scsi1: $TEST_STORAGE_B:$SNAP_OVERWRITE_DELETE_KEEPER_NAME" >/dev/null
    assert_lv_exists "$SNAP_OVERWRITE_DELETE_KEEPER_LV"
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
    [ "$(lvs --noheadings -o origin "$tsoe_final_path" | awk '{$1=$1;print}')" = "$COPY_SRC_LV_NAME" ]
    qm config "$SNAP_EMPTY_VM" | grep -qE '^boot:.*order=sata0([;,]|$)'
    ! qm config "$SNAP_EMPTY_VM" | grep -E '^unused[0-9]+:' >/dev/null
    ! lvs "${TEST_VG_A}/vm-${SNAP_EMPTY_VM}-disk-901" >/dev/null 2>&1
}

test_copy_between_vms() {
    tcbv_before="$TEST_DATA_DIR/copy-between-before.txt"
    tcbv_after="$TEST_DATA_DIR/copy-between-after.txt"
    qm config "$COPY_DST_VM" | awk -F': ' '$1 ~ /^(scsi|sata|virtio|ide)[0-9]+$/ {split($2,a,","); print a[1]}' | sort -u > "$tcbv_before"

    run_dryrun_unchanged "copy-between-vms" copy-disk-between-vms.sh "$COPY_SRC_VM" scsi0 "$COPY_DST_VM" "$TEST_VG_B"
    project_cmd copy-disk-between-vms.sh "$COPY_SRC_VM" scsi0 "$COPY_DST_VM" "$TEST_VG_B"

    qm config "$COPY_DST_VM" | awk -F': ' '$1 ~ /^(scsi|sata|virtio|ide)[0-9]+$/ {split($2,a,","); print a[1]}' | sort -u > "$tcbv_after"
    tcbv_new="$(grep -Fvx -f "$tcbv_before" "$tcbv_after" || :)"
    [ "$(printf '%s
' "$tcbv_new" | awk 'NF {n++} END {print n+0}')" -eq 1 ]
    case "$tcbv_new" in "$TEST_STORAGE_B":*) ;; *) return 1 ;; esac
    tcbv_path="$(pvesm path "$tcbv_new")"
    [ -z "$(lvs --noheadings -o origin "$tcbv_path" | awk '{$1=$1;print}')" ]
    cmp -n 33554432 "$COPY_SRC_LV" "$tcbv_path"
}

test_snapshot_between_vms() {
    tsbv_before="$TEST_DATA_DIR/snapshot-between-before.txt"
    tsbv_after="$TEST_DATA_DIR/snapshot-between-after.txt"
    qm config "$COPY_DST_VM" | awk -F': ' '$1 ~ /^(scsi|sata|virtio|ide)[0-9]+$/ {split($2,a,","); print a[1]}' | sort -u > "$tsbv_before"

    run_dryrun_unchanged "snapshot-between-vms" snapshot-disk-between-vms.sh "$COPY_SRC_VM" scsi0 "$COPY_DST_VM"
    project_cmd snapshot-disk-between-vms.sh "$COPY_SRC_VM" scsi0 "$COPY_DST_VM"

    qm config "$COPY_DST_VM" | awk -F': ' '$1 ~ /^(scsi|sata|virtio|ide)[0-9]+$/ {split($2,a,","); print a[1]}' | sort -u > "$tsbv_after"
    tsbv_new="$(grep -Fvx -f "$tsbv_before" "$tsbv_after" || :)"
    [ "$(printf '%s
' "$tsbv_new" | awk 'NF {n++} END {print n+0}')" -eq 1 ]
    tsbv_path="$(pvesm path "$tsbv_new")"
    [ "$(lvs --noheadings -o origin "$tsbv_path" | awk '{$1=$1;print}')" = "$COPY_SRC_LV_NAME" ]
}

test_clone_single_disk() {
    tcsd_before="$TEST_DATA_DIR/clone-single-before.txt"
    tcsd_after="$TEST_DATA_DIR/clone-single-after.txt"
    qm config "$COPY_SRC_VM" | awk -F': ' '$1 ~ /^(scsi|sata|virtio|ide)[0-9]+$/ {split($2,a,","); print a[1]}' | sort -u > "$tcsd_before"

    run_dryrun_unchanged "clone-single-disk" clone-single-vm-disk.sh "$COPY_SRC_VM" scsi0 "$TEST_VG_B"
    project_cmd clone-single-vm-disk.sh "$COPY_SRC_VM" scsi0 "$TEST_VG_B"

    qm config "$COPY_SRC_VM" | awk -F': ' '$1 ~ /^(scsi|sata|virtio|ide)[0-9]+$/ {split($2,a,","); print a[1]}' | sort -u > "$tcsd_after"
    tcsd_new="$(grep -Fvx -f "$tcsd_before" "$tcsd_after" || :)"
    [ "$(printf '%s
' "$tcsd_new" | awk 'NF {n++} END {print n+0}')" -eq 1 ]
    case "$tcsd_new" in "$TEST_STORAGE_B":*) ;; *) return 1 ;; esac
    tcsd_path="$(pvesm path "$tcsd_new")"
    [ -z "$(lvs --noheadings -o origin "$tcsd_path" | awk '{$1=$1;print}')" ]
    cmp -n 33554432 "$COPY_SRC_LV" "$tcsd_path"
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
