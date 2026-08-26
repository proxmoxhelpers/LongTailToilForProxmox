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
    TEST_GROUP="static-cli"
    test_reset_counters
    test_parse_arguments "$@"
}

main() {
    [ "$TEST_RUN" = "true" ] || { print_plan; return 0; }
    for CMD in sh grep find awk sed cmp mktemp; do require_command "$CMD"; done
    prepare_static_run
    run_case "POSIX sh syntax for all project commands and libraries" test_all_script_syntax
    run_case "All project entry points use /bin/sh" test_all_shebangs
    run_case "Every project command is standalone" test_all_standalone
    run_case "No prohibited Bash language constructs" test_no_bashisms
    run_case "No set -e unsafe short-circuit die guards" test_no_short_circuit_die
    run_case "Overwrite helpers use UUID-safe rollback" test_overwrite_uuid_safe_rollback
    run_case "Overwrite helpers support empty destination disk numbers" test_overwrite_empty_target_contract
    run_case "Create helpers expose device selectors and boot keyword" test_create_device_boot_contract
    run_case "Managed volume naming supports vm and base families" test_managed_volume_family_contract
    run_case "Inspection helpers expose numbering and filesystem contracts" test_inspection_helper_contract
    run_case "Active numbering detects gaps/duplicates and ignores unused archives" test_numbering_sequence_contract
    run_case "Partition table intent is compared by compatible filesystem family" test_partition_format_contract
    run_case "Managed disk-number selectors reject configured ambiguity" test_managed_selector_ambiguity_contract
    run_case "Test cleanup refuses unowned VM storage references" test_cleanup_storage_ownership_contract
    run_case "Dry-run snapshots include VM state and LV content samples" test_dryrun_snapshot_strength_contract
    run_case "Regular LVM copy path never uses sparse writes" test_regular_copy_non_sparse_contract
    run_case "Negative/refusal helper proves state is unchanged" test_refusal_helper_contract
    run_case "Every public command has an integration reference" test_integration_reference_contract
    run_case "Every mutating command has a dry-run immutability case" test_mutating_dryrun_coverage_contract
    run_case "README script/doc/usage links and test matrix cover every public command" test_public_documentation_coverage_contract
    run_case "Every .usage snapshot exactly matches live --help" test_usage_snapshot_contract
    run_case "LXC cleanup uses exact identity and owned-storage guards" test_ct_cleanup_safety_contract
    run_case "Protected baseline includes guest runtime and firewall state" test_protected_runtime_contract
    run_case "Cleanup fails closed between guest/storage/VG layers" test_layered_cleanup_contract
    run_case "Move-to-VM removes unused references config-only" test_move_to_vm_unused_cleanup_contract
    run_case "Partition probing avoids mutually exclusive partx modes" test_partx_mode_contract
    run_case "Integration groups do not depend on undefined trim" test_no_test_trim_contract
    run_case "delete-lvm cancellation returns failure" test_delete_cancel_contract
    run_case "Disk-bus changes sanitize incompatible iothread" test_bus_iothread_contract
    run_case "Emergency cleanup compares protected state" test_emergency_compare_contract
    run_case "Create helpers size managed sources from LVM metadata" test_create_source_size_contract
    run_case "Copy helpers preserve inactive source-LV activation state" test_inactive_source_copy_contract
    run_case "Network fixture setup does not pre-run the API under test" test_network_fixture_separation_contract
    run_case "Network fixture provisions owned rootfs storage before CT creation" test_network_fixture_owned_storage_contract
    run_case "Pause detach preflight rejects unsafe SCSI controller topology" test_pause_detach_preflight_contract
    run_case "Integration LVM-thin storages support LXC rootfs fixtures" test_lxc_rootfs_storage_contract
    run_case "Public helpers define setup/main/end/usage first" test_lifecycle_first_contract
    run_case "Every public helper performs elevation detection in setup" test_elevation_lifecycle_contract
    run_case "Embedded companion payloads exactly match their source commands" test_embedded_companion_sync_contract
    run_case "Documented import/name-fix safety contracts are enforced in code" test_documented_semantics_contract
    run_case "Integration evidence captures version/environment provenance" test_evidence_provenance_contract
    run_case "Elevation detection is silent when already elevated" test_silent_elevation_contract
    run_case "Every public function has a descriptive comment block" test_function_comment_documentation_contract
    run_case "Every --help exposes versioned usage, description and common options" test_help_content_contract
    run_case "All documented help aliases work for every public command" test_help_alias_contract
    run_case "Incomplete required arguments print usage before exiting" test_incomplete_argument_usage_contract
    run_case "Single/all VM mount commands share one implementation engine" test_vm_mount_engine_sync_contract
    run_case "Every parser option is documented in --help" test_parser_option_help_contract
    run_case "Per-helper docs embed exact live help and integration coverage" test_helper_documentation_sync_contract
    run_case "v3.6 whole-VM archives are self-contained and checksum-verified" test_vm_archive_contract
    run_case "Remote restore verifies the transferred archive before execution" test_remote_archive_contract
    run_case "Safe bulk dispatcher never uses eval" test_for_each_no_eval_contract
    run_case "New regular-LV copy helpers never use sparse writes" test_v36_regular_copy_contract
    run_case "v3.6 growth primitives are grow-only and filesystem growth is separate" test_v36_growth_contract
    run_case "v3.6 repair/flatten workflows retain UUID and activation rollback contracts" test_v36_workflow_rollback_contract
    run_case "New v3.6 helper runtime is synchronized and physical-identity aware" test_v362_new_runtime_identity_contract
    run_case "New copy/conversion failure cleanup restores activation and owns destination by UUID" test_v362_copy_failure_cleanup_contract
    run_case "Filesystem mount pair cleans up only invocation-owned resources" test_v362_mount_ownership_contract
    run_case "Direct config editors use strict slots, snapshot refusal and rollback" test_v362_direct_config_transaction_contract
    run_case "Filesystem growth verifies exact mounted device and remains filesystem-only" test_v362_growth_exactness_contract
    run_case "Journals and remote restore use unpredictable ownership-safe paths and whole-archive hashes" test_v362_journal_remote_safety_contract
    run_case "Disk-option verification ignores Proxmox option ordering without changing backing volume" test_v371_disk_option_semantic_contract
    run_case "Storage-only clone stages block devices through regular raw images and verifies import bytes" test_v371_clone_staging_contract
    run_case "Exact VM restore permits regenerated vmgenid and archive checksums verify from archive root" test_v371_archive_exactness_contract
    run_case "Remote transfer dry-run performs no SSH and preflight does not add host keys" test_v371_remote_dryrun_contract
    run_case "Common options may precede --version for all commands" test_common_option_version_ordering
    run_case "Argument-taking functions document call syntax" test_function_call_documentation_contract
    run_case "--version for all project commands" test_all_versions
    run_case "--help for all project commands" test_all_help
    run_case "dryrun before --version for all commands" test_all_dryrun_prefix
    run_case "dryrun after --version for all commands" test_all_dryrun_suffix
    run_case "Required v3 style documents are present" test_style_documents
    run_case "dryrun_summary succeeds in normal mode" test_dryrun_summary_status
    run_case "dryrun_cmd never executes a mutation" test_dryrun_nonmutation
    run_case "LVM stderr filter preserves errors and exit status" test_lvm_filter_contract
    run_case "No-reference lookup is a successful empty result" test_empty_reference_status
    run_case "Storage baseline ignores set-member order" test_storage_canonicalization
    run_case "Test runner stops a case at the first failed command" test_runner_strictness
}

end() {
    [ "$TEST_RUN" = "true" ] || return 0
    finish_static_run
}


############################################################
# STATIC HARNESS LIFECYCLE
############################################################

# prepare_static_run
#
# Description:
#   Creates only a local temporary result directory. Static/CLI validation must
#   not depend on Proxmox, LVM, root privileges or integration fixtures.
#
# Usage:
#   prepare_static_run
#
# Arguments:
#   None.
#
# Output:
#   Sets TEST_RESULT_DIR and TEST_DATA_DIR.
#
# Returns:
#   0 on success.
############################################################
prepare_static_run() {
    TEST_RESULT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/proxmox-lvm-tools-v3-static.XXXXXX")"
    TEST_RUN_ID="$(basename "$TEST_RESULT_DIR")"
    TEST_DATA_DIR="$TEST_RESULT_DIR/data"
    mkdir -p "$TEST_DATA_DIR"
    capture_test_provenance
}

# finish_static_run
# Prints the static group counters and removes its temporary evidence directory.
finish_static_run() {
    print_banner "Test group result"
    printf '%sPassed%s    : %s%s%s\n' "$CYAN" "$RESET" "$GREEN" "$TEST_PASS" "$RESET"
    printf '%sFailed%s    : %s%s%s\n' "$CYAN" "$RESET" "$RED" "$TEST_FAIL" "$RESET"
    printf '%sSkipped%s   : %s%s%s\n' "$CYAN" "$RESET" "$YELLOW" "$TEST_SKIP" "$RESET"
    printf '%sAnomalies%s : %s%s%s\n' "$CYAN" "$RESET" "$YELLOW" "$TEST_ANOMALY" "$RESET"
    printf '%sLogs%s      : %s%s%s\n' "$CYAN" "$RESET" "$BLUE" "$TEST_RESULT_DIR" "$RESET"
    write_test_summary
    [ "$TEST_FAIL" -eq 0 ] || return 1
    return 0
}

############################################################
# TEST PLAN
############################################################

print_plan() {
    print_banner "Static / CLI tests"
    printf '%s\n' "No test has been executed. Re-run with --run to:"
    printf '%s\n' "  - parse all 81 v3 commands and canonical maintenance libraries with /bin/sh"
    printf '%s\n' "  - prove each top-level command runs help/version when copied completely alone"
    printf '%s\n' "  - require /bin/sh entry-point shebangs and reject known Bash-only constructs"
    printf '%s\n' "  - test --version and --help without root/Proxmox preflight"
    printf '%s\n' "  - test dryrun keyword parsing before and after --version"
    printf '%s\n' "  - verify the v3 style-guide documents are packaged"
    printf '%s\n' "  - verify shared helper and test-runner regression contracts"
    printf '%s\n' "  - verify vm-VMID-disk-N and base-VMID-disk-N managed-volume support"
    printf '%s\n' "  - verify cleanup refuses unowned storage references on disposable VMs"
    printf '%s\n' "  - verify dry-run/refusal snapshots include runtime state and LV byte samples"
    printf '%s\n' "  - enforce non-sparse writes for regular-LV copy destinations"
}

############################################################
# TEST CASES
############################################################

# Verifies that every project entry point and shared shell library parses in sh.
test_all_script_syntax() {
    tas_count=0
    for tas_script in "$PROJECT_ROOT"/*.sh; do sh -n "$tas_script"; tas_count=$((tas_count + 1)); done
    [ "$tas_count" -eq 81 ] || { printf 'Expected 81 project commands, found %s.\n' "$tas_count" >&2; return 1; }
    for tas_lib in "$PROJECT_ROOT"/lib/*.sh; do sh -n "$tas_lib"; done
}

# Verifies that every public helper has no runtime dependency on lib/ or another
# project script and that help/version still work after copying only that file.
test_all_standalone() {
    tas_root="$TEST_DATA_DIR/standalone"
    mkdir -p "$tas_root"
    for tas_script in "$PROJECT_ROOT"/*.sh; do
        tas_name="$(basename "$tas_script")"
        tas_dir="$tas_root/${tas_name%.sh}"
        mkdir -p "$tas_dir"
        cp "$tas_script" "$tas_dir/$tas_name"
        chmod +x "$tas_dir/$tas_name"

        if grep -nE '^[[:space:]]*\.[[:space:]].*(lib/common\.sh|lib/dryrun\.sh)' "$tas_dir/$tas_name" >/dev/null 2>&1; then
            printf '%s still sources an external project library.\n' "$tas_name" >&2
            return 1
        fi
        if grep -nF 'SCRIPT_DIR' "$tas_dir/$tas_name" >/dev/null 2>&1; then
            printf '%s still depends on its repository directory.\n' "$tas_name" >&2
            return 1
        fi
        if grep -nF 'exec_project_script' "$tas_dir/$tas_name" >/dev/null 2>&1; then
            printf '%s still uses the external companion-script dispatcher.\n' "$tas_name" >&2
            return 1
        fi

        (cd "$tas_dir" && /bin/sh "./$tas_name" --help >/dev/null)
        tas_version="$(cd "$tas_dir" && /bin/sh "./$tas_name" --version)"
        printf '%s\n' "$tas_version" | grep -F "(project $PROJECT_VERSION)" >/dev/null || return 1
    done
}

# Verifies every executable project command declares the intended interpreter.
test_all_shebangs() {
    for tas_script in "$PROJECT_ROOT"/*.sh; do
        [ "$(sed -n '1p' "$tas_script")" = '#!/bin/sh' ] || { printf 'Non-POSIX shebang: %s\n' "$tas_script" >&2; return 1; }
    done
}

# Scans executable shell source for constructs intentionally forbidden by the
# v3 POSIX style guide. The patterns are restricted to shell-shaped forms so
# regex character classes and explanatory prose do not become false positives.
test_no_bashisms() {
    tnb_file="$TEST_DATA_DIR/bashism-hits.txt"
    : > "$tnb_file"
    for tnb_script in "$PROJECT_ROOT"/*.sh "$PROJECT_ROOT"/lib/*.sh; do
        # Declaration/source keywords are prohibited when used as commands.
        grep -nE '^[[:space:]]*(local|declare|typeset|source)[[:space:]]+' "$tnb_script" 2>/dev/null | sed "s#^#$tnb_script:#" >> "$tnb_file" || :
        # Common [[ forms at command position.
        grep -nE '^[[:space:]]*(if[[:space:]]+)?\[\[[[:space:]]' "$tnb_script" 2>/dev/null | sed "s#^#$tnb_script:#" >> "$tnb_file" || :
        # Bash array readers/arithmetic-for at command position.
        grep -nE '^[[:space:]]*(mapfile|readarray)[[:space:]]+' "$tnb_script" 2>/dev/null | sed "s#^#$tnb_script:#" >> "$tnb_file" || :
        grep -nE '^[[:space:]]*for[[:space:]]*\(\(' "$tnb_script" 2>/dev/null | sed "s#^#$tnb_script:#" >> "$tnb_file" || :
        # Tokens with no legitimate use in the v3 shell source.
        for tnb_token in 'BASH_SOURCE' '<<<' '[@]'; do
            grep -nF "$tnb_token" "$tnb_script" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*#' | sed "s#^#$tnb_script:#" >> "$tnb_file" || :
        done
        awk -v file="$tnb_script" '
            /^[[:space:]]*#/ {next}
            {
                pos=index($0, "$\047")
                if (pos > 0) {
                    prev=(pos == 1 ? "" : substr($0,pos-1,1))
                    if (pos == 1 || prev ~ /[= \t;]/) print file ":" NR ": ANSI-C quoted string: " $0
                }
            }
        ' "$tnb_script" >> "$tnb_file"
        # Process substitution begins with <( or >( in shell code. Restrict to
        # lines where the token is not part of prose/comments.
        grep -nE '(^|[=[:space:]])[<>]\(' "$tnb_script" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*#' | sed "s#^#$tnb_script:#" >> "$tnb_file" || :
    done
    if [ -s "$tnb_file" ]; then cat "$tnb_file" >&2; return 1; fi
}

# Regression test for the v3.0.0 Proxmox failures: a successful negative
# probe written as "probe && die" can make the containing function return 1
# and trip set -e when the probe is its last command. v3.0.1 forbids that form.
test_no_short_circuit_die() {
    tnsc_file="$TEST_DATA_DIR/short-circuit-die-hits.txt"
    : > "$tnsc_file"
    for tnsc_script in "$PROJECT_ROOT"/*.sh "$PROJECT_ROOT"/lib/*.sh; do
        grep -nF '&& die ' "$tnsc_script" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*#' | sed "s#^#$tnsc_script:#" >> "$tnsc_file" || :
    done
    if [ -s "$tnsc_file" ]; then cat "$tnsc_file" >&2; return 1; fi
}


# Regression test: overwrite transactions must not delete unusedN during
# rollback and must verify replacements by LV UUID after renames.
test_overwrite_uuid_safe_rollback() {
    tous_snapshot="$PROJECT_ROOT/create-disk-snapshot-and-overwrite-disk-on-vm.sh"
    tous_copy="$PROJECT_ROOT/create-disk-copy-and-overwrite-disk-on-vm.sh"
    for tous_script in "$tous_snapshot" "$tous_copy"; do
        grep -F 'NEW_UUID=' "$tous_script" >/dev/null || return 1
        grep -F 'lv_name_by_uuid()' "$tous_script" >/dev/null || return 1
        grep -F 'remove_unused_reference_only()' "$tous_script" >/dev/null || return 1
        grep -F 'ROLLBACK_FAILED' "$tous_script" >/dev/null || return 1
        grep -F 'vsm_uuid="$(lvs --noheadings -o lv_uuid' "$tous_script" >/dev/null || return 1
        if grep -F 'qm set "$DEST_VM" --delete "$OLD_UNUSED_KEY"' "$tous_script" >/dev/null 2>&1; then
            printf '%s still deletes unusedN through qm in overwrite transaction code.\n' "$tous_script" >&2
            return 1
        fi
    done
}

# Verifies the two overwrite helpers have an explicit add-new-disk path when
# DEST_VMID disk-N names no active destination disk.
test_overwrite_empty_target_contract() {
    toet_snapshot="$PROJECT_ROOT/create-disk-snapshot-and-overwrite-disk-on-vm.sh"
    toet_copy="$PROJECT_ROOT/create-disk-copy-and-overwrite-disk-on-vm.sh"
    for toet_script in "$toet_snapshot" "$toet_copy"; do
        grep -F 'DEST_EXISTS=0' "$toet_script" >/dev/null || return 1
        grep -F 'create new disk (nothing to overwrite)' "$toet_script" >/dev/null || return 1
        grep -F 'first_free_scsi "$DEST_VM"' "$toet_script" >/dev/null || return 1
        grep -F 'there was no displaced destination disk to delete' "$toet_script" >/dev/null || return 1
        grep -F 'already exists.' "$toet_script" >/dev/null || return 1
        /bin/sh "$toet_script" --help | grep -F 'exactly one active disk' >/dev/null || {
            printf '%s does not document destination-LV active-reference semantics.\n' "$(basename "$toet_script")" >&2
            return 1
        }
    done

    grep -F 'test_create_copy_overwrite_empty' "$PROJECT_ROOT/tests/groups/50-copy-snapshot.sh" >/dev/null || return 1
    grep -F 'test_create_snapshot_overwrite_empty' "$PROJECT_ROOT/tests/groups/50-copy-snapshot.sh" >/dev/null || return 1
}


# Verifies the public create-helper CLI advertises source slots, destination
# slot/bus selection and the optional boot-order mutation.
test_create_device_boot_contract() {
    for tcdbc_name in \
        create-disk-copy-and-add-to-vm.sh \
        create-disk-snapshot-and-add-to-vm.sh \
        create-disk-copy-and-overwrite-disk-on-vm.sh \
        create-disk-snapshot-and-overwrite-disk-on-vm.sh; do
        tcdbc_help="$(/bin/sh "$PROJECT_ROOT/$tcdbc_name" --help)"
        printf '%s\n' "$tcdbc_help" | grep -F 'dest-slot|dest-bus' >/dev/null || { printf '%s does not document destination slot/bus selectors.\n' "$tcdbc_name" >&2; return 1; }
        printf '%s\n' "$tcdbc_help" | grep -F 'source-slot' >/dev/null || { printf '%s does not document source slot selectors.\n' "$tcdbc_name" >&2; return 1; }
        printf '%s\n' "$tcdbc_help" | grep -F 'unusedN' >/dev/null || { printf '%s does not document unusedN source selectors.\n' "$tcdbc_name" >&2; return 1; }
        printf '%s\n' "$tcdbc_help" | grep -F 'N|source-disk-N' >/dev/null || { printf '%s does not document bare numeric source disk selectors.\n' "$tcdbc_name" >&2; return 1; }
        printf '%s\n' "$tcdbc_help" | grep -F 'N or disk-N' >/dev/null || { printf '%s does not document bare numeric destination disk selectors.\n' "$tcdbc_name" >&2; return 1; }
        printf '%s\n' "$tcdbc_help" | grep -F 'boot' >/dev/null || { printf '%s does not document the boot keyword.\n' "$tcdbc_name" >&2; return 1; }
        grep -F 'first_free_bus_slot()' "$PROJECT_ROOT/$tcdbc_name" >/dev/null || return 1
        grep -F 'set_destination_boot_first()' "$PROJECT_ROOT/$tcdbc_name" >/dev/null || return 1
    done
    return 0
}

# Verifies every command family that interprets Proxmox-managed LVM names knows
# both vm-VMID-disk-N and base-VMID-disk-N where that distinction is material.
test_managed_volume_family_contract() {
    tmvfc_change="$PROJECT_ROOT/change-vmid-of-vm.sh"
    tmvfc_renumber="$PROJECT_ROOT/renumber-vm-disks.sh"
    tmvfc_fix="$PROJECT_ROOT/fix-vm-volume-names.sh"
    tmvfc_orphan="$PROJECT_ROOT/find-orphaned-volumes.sh"
    tmvfc_recover="$PROJECT_ROOT/recover-vm-from-volumes.sh"
    tmvfc_move="$PROJECT_ROOT/move-disk-to-vm.sh"

    grep -F ':(vm|base)-${OLD_ID}-' "$tmvfc_change" >/dev/null || return 1
    grep -F 'bvp_foreign=' "$tmvfc_change" >/dev/null || return 1

    grep -F ':(vm|base)-[0-9]+-disk-[0-9]+' "$tmvfc_renumber" >/dev/null || return 1
    grep -F 'brp_new="${brp_namespace}-disk-${brp_i}"' "$tmvfc_renumber" >/dev/null || return 1
    grep -F 'Refusing to renumber a shared volume' "$tmvfc_renumber" >/dev/null || return 1

    grep -F '/^(scsi|sata|virtio|ide|unused|efidisk|tpmstate)[0-9]+$/' "$tmvfc_fix" >/dev/null || return 1
    grep -F 'Corrected destination LV already exists' "$tmvfc_fix" >/dev/null || return 1
    grep -F 'Leaving unmanaged LVM volume name unchanged' "$tmvfc_fix" >/dev/null || return 1
    grep -F 'bfp_family="base"' "$tmvfc_fix" >/dev/null || return 1
    grep -F 'bfp_family="vm"' "$tmvfc_fix" >/dev/null || return 1

    grep -F "'^(vm|base)-[0-9]+-disk-[0-9]+$'" "$tmvfc_orphan" >/dev/null || return 1
    grep -F '"^(vm|base)-"id"-disk-[0-9]+$"' "$tmvfc_recover" >/dev/null || return 1
    grep -F 'v ~ "^(vm|base)-[0-9]+-disk-" n "$"' "$tmvfc_move" >/dev/null || return 1

    for tmvfc_name in \
        create-disk-copy-and-add-to-vm.sh \
        create-disk-snapshot-and-add-to-vm.sh \
        create-disk-copy-and-overwrite-disk-on-vm.sh \
        create-disk-snapshot-and-overwrite-disk-on-vm.sh; do
        tmvfc_script="$PROJECT_ROOT/$tmvfc_name"
        grep -F 'v ~ "^(vm|base)-[0-9]+-disk-" n "$"' "$tmvfc_script" >/dev/null || return 1
        grep -F 'DEST_PREFIX="base"' "$tmvfc_script" >/dev/null || return 1
    done
    return 0
}

# Verifies the two v3.4 inspection helpers expose their intended read-only contracts.
test_inspection_helper_contract() {
    tih_number="$PROJECT_ROOT/verify-vm-disk-numbering.sh"
    tih_fs="$PROJECT_ROOT/list-all-vm-lvm-filesystems.sh"
    [ -f "$tih_number" ] && [ -f "$tih_fs" ] || return 1

    grep -F 'VMID MISMATCH' "$tih_number" >/dev/null || return 1
    grep -F 'ACTIVE STARTS AT disk-' "$tih_number" >/dev/null || return 1
    grep -F 'GAP AT disk-' "$tih_number" >/dev/null || return 1
    grep -F 'DUPLICATE disk-' "$tih_number" >/dev/null || return 1
    grep -F '$4 !~ /^unused[0-9]+$/' "$tih_number" >/dev/null || return 1
    grep -F 'base-*-disk-*' "$tih_number" >/dev/null || return 1

    grep -F 'TABLE_HINT' "$tih_fs" >/dev/null || return 1
    grep -F 'CONTENT_FORMAT' "$tih_fs" >/dev/null || return 1
    grep -F 'MISMATCH: table says' "$tih_fs" >/dev/null || return 1
    grep -F 'blkid -p -o value -s TYPE -O' "$tih_fs" >/dev/null || return 1
    grep -F 'partx --show --noheadings -o NR,START,SECTORS,TYPE' "$tih_fs" >/dev/null || return 1
    grep -F 'Microsoft reserved|none' "$tih_fs" >/dev/null || return 1
    grep -F 'Solaris /usr / ZFS|zfs' "$tih_fs" >/dev/null || return 1

    if grep -nE '^[[:space:]]*(kpartx|mount)[[:space:]]' "$tih_fs" >/dev/null 2>&1; then
        printf '%s performs a state-changing mapping/mount operation.\n' "$(basename "$tih_fs")" >&2
        return 1
    fi
    return 0
}

# Exercises active numbering analysis without Proxmox/LVM.
test_numbering_sequence_contract() (
    tnsc_lib="$TEST_DATA_DIR/verify-numbering-functions.sh"
    sed '/^# START$/,$d' "$PROJECT_ROOT/verify-vm-disk-numbering.sh" > "$tnsc_lib"
    . "$tnsc_lib"

    REFS_FILE="$TEST_DATA_DIR/numbering-refs.txt"
    cat > "$REFS_FILE" <<'EOF'
100|QEMU|test|scsi0|test:a|u1|/dev/x/a|vm-100-disk-5|vm|100|5
100|QEMU|test|scsi1|test:b|u2|/dev/x/b|base-100-disk-5|base|100|5
100|QEMU|test|scsi2|test:c|u3|/dev/x/c|vm-100-disk-7|vm|100|7
100|QEMU|test|unused0|test:d|u4|/dev/x/d|vm-100-disk-901|vm|100|901
EOF
    [ "$(active_numbering_status 100)" = "ACTIVE STARTS AT disk-5; DUPLICATE disk-5; GAP AT disk-6" ]
)

# Exercises representative GPT/MBR table intent against content signatures.
test_partition_format_contract() (
    tpfc_lib="$TEST_DATA_DIR/filesystem-functions.sh"
    sed '/^# START$/,$d' "$PROJECT_ROOT/list-all-vm-lvm-filesystems.sh" > "$tpfc_lib"
    . "$tpfc_lib"

    [ "$(table_type_info 0FC63DAF-8483-4772-8E79-3D69D8477DE4)" = "Linux filesystem|linuxfs" ]
    [ "$(table_type_info EBD0A0A2-B9E5-4433-87C0-68B6B72699C7)" = "Microsoft basic data|microsoft" ]
    [ "$(table_type_info E3C9E316-0B5C-4DB8-817D-F92DF00215AE)" = "Microsoft reserved|none" ]
    table_content_match linuxfs ext4
    table_content_match linuxfs btrfs
    table_content_match linuxfs crypto_LUKS
    table_content_match microsoft ntfs
    table_content_match fat vfat
    if table_content_match microsoft ext4; then return 1; fi
    if table_content_match fat btrfs; then return 1; fi
)

# Prevents exact-current-VMID precedence from hiding a second configured disk-N.
test_managed_selector_ambiguity_contract() {
    for tmsa_name in \
        move-disk-to-vm.sh \
        create-disk-copy-and-add-to-vm.sh \
        create-disk-snapshot-and-add-to-vm.sh \
        create-disk-copy-and-overwrite-disk-on-vm.sh \
        create-disk-snapshot-and-overwrite-disk-on-vm.sh; do
        tmsa_script="$PROJECT_ROOT/$tmsa_name"
        grep -F 'v ~ "^(vm|base)-[0-9]+-disk-" n "$"' "$tmsa_script" >/dev/null || return 1
        if grep -F 'v == "vm-" id "-disk-" n' "$tmsa_script" >/dev/null 2>&1; then
            printf '%s still gives exact embedded VMID precedence over configured disk-N ambiguity.\n' "$tmsa_name" >&2
            return 1
        fi
    done
    return 0
}

# Prevents command inventory drift between the public tree, README and matrix.
test_public_documentation_coverage_contract() {
    tpdc_readme="$PROJECT_ROOT/README.md"
    tpdc_matrix="$TEST_ROOT/TEST-MATRIX.md"
    tpdc_count=0

    for tpdc_script in "$PROJECT_ROOT"/*.sh; do
        tpdc_name="$(basename "$tpdc_script")"
        tpdc_stem="${tpdc_name%.sh}"
        tpdc_doc="$PROJECT_ROOT/docs/${tpdc_stem}.md"
        tpdc_usage="$PROJECT_ROOT/docs/${tpdc_name}.usage"
        tpdc_count=$((tpdc_count + 1))

        tpdc_heading="#### [\`$tpdc_name\`]($tpdc_name) · [doc](docs/${tpdc_stem}.md) · [usage](docs/${tpdc_name}.usage)"
        [ "$(grep -Fc "$tpdc_heading" "$tpdc_readme")" -eq 1 ] || {
            printf 'README must contain exactly one linked script/doc/usage heading for %s.\n' "$tpdc_name" >&2
            return 1
        }

        [ -f "$tpdc_doc" ] || {
            printf 'Missing per-helper documentation page: %s\n' "$tpdc_doc" >&2
            return 1
        }
        [ -f "$tpdc_usage" ] || {
            printf 'Missing per-helper usage snapshot: %s\n' "$tpdc_usage" >&2
            return 1
        }

        grep -F "# \`$tpdc_name\`" "$tpdc_doc" >/dev/null || {
            printf 'Documentation page title does not match helper %s.\n' "$tpdc_name" >&2
            return 1
        }
        grep -F "./$tpdc_name --help" "$tpdc_doc" >/dev/null || {
            printf 'Documentation page does not show callable --help for %s.\n' "$tpdc_name" >&2
            return 1
        }
        grep -F "[Raw usage](./${tpdc_name}.usage)" "$tpdc_doc" >/dev/null || {
            printf 'Documentation page does not link raw usage snapshot for %s.\n' "$tpdc_name" >&2
            return 1
        }

        tpdc_wget="wget -q \"https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/$tpdc_name\" -O \"$tpdc_name\" && chmod +x \"$tpdc_name\""
        [ "$(grep -Fc "$tpdc_wget" "$tpdc_readme")" -eq 1 ] || {
            printf 'README must contain exactly one standalone wget+chmod line for %s.\n' "$tpdc_name" >&2
            return 1
        }

        [ "$(grep -Fc "\`$tpdc_name\`" "$tpdc_matrix")" -eq 1 ] || {
            printf 'TEST-MATRIX.md must contain exactly one command row for %s.\n' "$tpdc_name" >&2
            return 1
        }
    done

    [ "$tpdc_count" -eq 81 ] || {
        printf 'Expected 81 public commands, found %s.\n' "$tpdc_count" >&2
        return 1
    }
}

# Verifies shipped usage snapshots are exact executable help output.
test_usage_snapshot_contract() {
    tusc_tmp="$TEST_DATA_DIR/live-help.txt"
    for tusc_script in "$PROJECT_ROOT"/*.sh; do
        tusc_name="$(basename "$tusc_script")"
        tusc_usage="$PROJECT_ROOT/docs/${tusc_name}.usage"
        sh "$tusc_script" --help >"$tusc_tmp" 2>&1 || {
            printf '%s --help returned non-zero while validating usage snapshot.\n' "$tusc_name" >&2
            return 1
        }
        cmp -s "$tusc_tmp" "$tusc_usage" || {
            printf 'Usage snapshot differs from live --help: %s\n' "$tusc_name" >&2
            return 1
        }
    done
    rm -f "$tusc_tmp"
    return 0
}

# Ensures cleanup cannot purge a named test VM unless every storage-backed
# reference still resolves through a test-owned storage mapping.
test_cleanup_storage_ownership_contract() {
    tcso_lib="$PROJECT_ROOT/tests/lib/test-common.sh"
    grep -F 'vm_references_only_test_storage()' "$tcso_lib" >/dev/null || return 1
    grep -F 'test_storage_mapping_owned()' "$tcso_lib" >/dev/null || return 1
    grep -F 'Refusing to destroy VM $ctv_id because one or more storage references are not provably test-owned.' "$tcso_lib" >/dev/null || return 1

    tcso_cleanup="$(awk '/^cleanup_test_vms\(\)/,/^}/' "$tcso_lib")"
    printf '%s\n' "$tcso_cleanup" | grep -F 'vm_references_only_test_storage "$ctv_id"' >/dev/null || return 1
    printf '%s\n' "$tcso_cleanup" | grep -F 'qm destroy "$ctv_id" --purge 1' >/dev/null || return 1

    tcso_guard_line="$(printf '%s\n' "$tcso_cleanup" | grep -nF 'vm_references_only_test_storage "$ctv_id"' | cut -d: -f1)"
    tcso_destroy_line="$(printf '%s\n' "$tcso_cleanup" | grep -nF 'qm destroy "$ctv_id" --purge 1' | cut -d: -f1)"
    [ -n "$tcso_guard_line" ] && [ -n "$tcso_destroy_line" ] && [ "$tcso_guard_line" -lt "$tcso_destroy_line" ]
}

# Ensures the state snapshots used by every real dry-run include runtime state,
# sampled LV bytes and full test-data file hashes.
test_dryrun_snapshot_strength_contract() {
    tdss_lib="$PROJECT_ROOT/tests/lib/test-common.sh"
    tdss_body="$(awk '/^snapshot_test_owned_state\(\)/,/^)/' "$tdss_lib")"
    printf '%s\n' "$tdss_body" | grep -F '[LV-SAMPLES]' >/dev/null || return 1
    printf '%s\n' "$tdss_body" | grep -F 'sample_lv_content "$stos_lv"' >/dev/null || return 1
    printf '%s\n' "$tdss_body" | grep -F 'STATUS:%s:%s' >/dev/null || return 1
    printf '%s\n' "$tdss_body" | grep -F 'sha256sum "$stos_path"' >/dev/null || return 1
    grep -F 'TEST_BACKUP_BASELINE=' "$tdss_lib" >/dev/null || return 1
    grep -F 'backup_was_preexisting "$ctb_path"' "$tdss_lib" >/dev/null || return 1
}

# The critical copy rule: thin destinations may use conv=sparse; regular
# destinations must issue a full write without sparse skipping.
test_regular_copy_non_sparse_contract() (
    trcn_lib="$TEST_DATA_DIR/copy-lvm-functions.sh"
    sed '/^# START$/,$d' "$PROJECT_ROOT/copy-lvm.sh" > "$trcn_lib"
    . "$trcn_lib"

    SOURCE_PATH="/dev/test/source"
    DEST_PATH="/dev/test/destination"
    dryrun_cmd() { printf '%s\n' "$*"; }
    info() { :; }
    ok() { :; }

    DEST_MODE="regular"
    trcn_regular="$(copy_data)"
    printf '%s\n' "$trcn_regular" | grep -F 'conv=fsync' >/dev/null || return 1
    if printf '%s\n' "$trcn_regular" | grep -F 'conv=sparse' >/dev/null; then return 1; fi

    DEST_MODE="thin"
    trcn_thin="$(copy_data)"
    printf '%s\n' "$trcn_thin" | grep -F 'conv=sparse,fsync' >/dev/null || return 1
)

# Verifies the reusable negative-path helper requires failure and compares
# snapshots on both sides instead of accepting a failed command as sufficient.
test_refusal_helper_contract() {
    trhc_lib="$PROJECT_ROOT/tests/lib/test-common.sh"
    trhc_body="$(awk '/^run_expect_fail_unchanged\(\)/,/^}/' "$trhc_lib")"
    printf '%s\n' "$trhc_body" | grep -F 'snapshot_test_owned_state "$refu_before"' >/dev/null || return 1
    printf '%s\n' "$trhc_body" | grep -F 'if project_cmd "$refu_script"' >/dev/null || return 1
    printf '%s\n' "$trhc_body" | grep -F 'snapshot_test_owned_state "$refu_after"' >/dev/null || return 1
    printf '%s\n' "$trhc_body" | grep -F 'cmp -s "$refu_before" "$refu_after"' >/dev/null || return 1
}

# Ensures no public command can silently fall out of the real integration suite.
test_integration_reference_contract() {
    tirc_blob="$TEST_DATA_DIR/integration-groups.txt"
    cat "$PROJECT_ROOT"/tests/groups/[1-9][0-9]-*.sh > "$tirc_blob"
    for tirc_script in "$PROJECT_ROOT"/*.sh; do
        tirc_name="$(basename "$tirc_script")"
        grep -F "$tirc_name" "$tirc_blob" >/dev/null || {
            printf 'No non-static integration-group reference found for %s.\n' "$tirc_name" >&2
            return 1
        }
    done
}

# Read-only inventory commands do not need mutation dry-runs. Every other
# public command must be exercised through the exact-state dry-run helper.
test_mutating_dryrun_coverage_contract() {
    tmdc_blob="$TEST_DATA_DIR/integration-groups.txt"
    cat "$PROJECT_ROOT"/tests/groups/[1-9][0-9]-*.sh > "$tmdc_blob"
    for tmdc_script in "$PROJECT_ROOT"/*.sh; do
        tmdc_name="$(basename "$tmdc_script")"
        case "$tmdc_name" in
            audit-vm-storage.sh|find-orphaned-volumes.sh|find-volume-owner.sh|list-all-vm-lvm-filesystems.sh|list-all-vm-lvm.sh|list-vm-disks.sh|verify-vm-disk-numbering.sh|verify-vm-storage-consistency.sh|show-vm-storage-map.sh|compare-vm-disks.sh|verify-vm-disk-content.sh|show-thin-snapshot-tree.sh|find-shared-vm-volumes.sh|find-unreferenced-managed-volumes.sh|audit-vm-boot-config.sh|show-vm-filesystem-layout.sh|find-vm-root-filesystem.sh|show-last-operation.sh|plan-vm-storage-move.sh)
                continue
                ;;
        esac
        tmdc_pattern="$(printf '%s' "$tmdc_name" | sed 's/[.[\*^$()+?{|]/\\&/g')"
        grep -E "run_dryrun_unchanged.*${tmdc_pattern}" "$tmdc_blob" >/dev/null || {
            printf 'Mutating command has no run_dryrun_unchanged integration case: %s\n' "$tmdc_name" >&2
            return 1
        }
    done
}

test_ct_cleanup_safety_contract() {
    tcsc_common="$PROJECT_ROOT/tests/lib/test-common.sh"
    grep -F 'cleanup_test_cts()' "$tcsc_common" >/dev/null || return 1
    grep -F 'ctc_actual="$(pct config "$ctc_id"' "$tcsc_common" >/dev/null || return 1
    grep -F 'ct_references_only_test_storage "$ctc_id"' "$tcsc_common" >/dev/null || return 1
    grep -F 'pct destroy "$ctc_id" --purge 1' "$tcsc_common" >/dev/null || return 1
    tcsc_guard="$(grep -nF 'ct_references_only_test_storage "$ctc_id"' "$tcsc_common" | head -n1 | cut -d: -f1)"
    tcsc_destroy="$(grep -nF 'pct destroy "$ctc_id" --purge 1' "$tcsc_common" | head -n1 | cut -d: -f1)"
    [ "$tcsc_guard" -lt "$tcsc_destroy" ]
}

test_protected_runtime_contract() {
    tprc_common="$PROJECT_ROOT/tests/lib/test-common.sh"
    grep -F '"${cps_prefix}.guest-status"' "$tprc_common" >/dev/null || return 1
    grep -F '"${cps_prefix}.firewall"' "$tprc_common" >/dev/null || return 1
    grep -F 'guest-status firewall' "$tprc_common" >/dev/null || return 1
    grep -F 'qm status "$cps_id"' "$tprc_common" >/dev/null || return 1
    grep -F 'pct status "$cps_id"' "$tprc_common" >/dev/null || return 1
}

test_layered_cleanup_contract() {
    tlcc_common="$PROJECT_ROOT/tests/lib/test-common.sh"
    grep -F 'owned_guest_configs_remain' "$tlcc_common" >/dev/null || return 1
    grep -F 'refusing storage/VG cleanup' "$tlcc_common" >/dev/null || return 1
    grep -F 'owned_storage_entries_remain' "$tlcc_common" >/dev/null || return 1
    grep -F 'refusing VG/loop cleanup' "$tlcc_common" >/dev/null || return 1
    grep -F 'owned_vgs_or_loops_remain' "$tlcc_common" >/dev/null || return 1
    grep -F 'retaining sandbox evidence' "$tlcc_common" >/dev/null || return 1
}

# Prevents move-disk-to-vm from freeing a moved LV while clearing source unusedN.
test_move_to_vm_unused_cleanup_contract() {
    tmuc_script="$PROJECT_ROOT/move-disk-to-vm.sh"
    grep -F 'remove_source_unused_reference_only' "$tmuc_script" >/dev/null || return 1
    grep -F 'without deleting storage' "$tmuc_script" >/dev/null || return 1
    if grep -E 'qm set "\$SOURCE_VM" --delete "\$SOURCE_UNUSED"|qm set "\$SOURCE_VM" --delete "\$rsu_slot"' "$tmuc_script" >/dev/null 2>&1; then
        printf 'move-disk-to-vm.sh still deletes source unusedN through qm.\n' >&2
        return 1
    fi
}

# util-linux partx treats --show and --raw as mutually exclusive modes.
test_partx_mode_contract() {
    if grep -R -n -- 'partx --show --raw' "$PROJECT_ROOT"/*.sh "$TEST_ROOT"/groups/[1-9][0-9]-*.sh >/dev/null 2>&1; then
        printf 'Found invalid partx --show --raw combination.\n' >&2
        return 1
    fi
    grep -F 'partx --show --noheadings -o NR,START,SECTORS,TYPE' "$PROJECT_ROOT/list-all-vm-lvm-filesystems.sh" >/dev/null || return 1
}

# Test groups must stay self-contained and not call the project-internal trim helper.
test_no_test_trim_contract() {
    if grep -R -nE '\|[[:space:]]*trim([[:space:]]|\)|$)' "$TEST_ROOT"/groups/*.sh >/dev/null 2>&1; then
        printf 'An integration group calls undefined trim.\n' >&2
        return 1
    fi
}

# A wrong destructive confirmation is a refusal, not successful completion.
test_delete_cancel_contract() {
    tdc_script="$PROJECT_ROOT/delete-lvm.sh"
    grep -F 'Cancelled.' "$tdc_script" >/dev/null || return 1
    grep -F 'exit 1' "$tdc_script" >/dev/null || return 1
}

# SATA/IDE cannot carry the iothread option accepted by SCSI/virtio disks.
test_bus_iothread_contract() {
    tbic_script="$PROJECT_ROOT/change-disk-bus.sh"
    grep -F 'sanitize_destination_value' "$tbic_script" >/dev/null || return 1
    grep -F "sed 's/,iothread=[^,]*//g'" "$tbic_script" >/dev/null || return 1
    grep -F 'does not accept it' "$tbic_script" >/dev/null || return 1
}

# Setup-time failures must still capture the protected after-state.
test_emergency_compare_contract() {
    tecc_lib="$TEST_ROOT/lib/test-common.sh"
    tecc_body="$(sed -n '/^test_emergency_cleanup()/,/^}/p' "$tecc_lib")"
    printf '%s\n' "$tecc_body" | grep -F 'test_cleanup_sandbox' >/dev/null || return 1
    printf '%s\n' "$tecc_body" | grep -F 'compare_protected_state' >/dev/null || return 1
}

# Template/base LVs can be valid managed LVs even when blockdev size probing is
# unsuitable. All four create helpers must use LVM metadata for source size.
test_create_source_size_contract() {
    for tcssc_name in \
        create-disk-copy-and-add-to-vm.sh \
        create-disk-snapshot-and-add-to-vm.sh \
        create-disk-copy-and-overwrite-disk-on-vm.sh \
        create-disk-snapshot-and-overwrite-disk-on-vm.sh; do
        tcssc_script="$PROJECT_ROOT/$tcssc_name"
        grep -F 'lvs --noheadings --units b --nosuffix -o lv_size "$SOURCE_PATH"' "$tcssc_script" >/dev/null || {
            printf '%s does not size source LVs from LVM metadata.\n' "$tcssc_name" >&2
            return 1
        }
        if grep -F 'SOURCE_SIZE_BYTES="$(blockdev --getsize64 "$SOURCE_PATH"' "$tcssc_script" >/dev/null 2>&1; then
            printf '%s still uses blockdev for managed source LV sizing.\n' "$tcssc_name" >&2
            return 1
        fi
    done
    return 0
}

# Ensures block-copy helpers can read an inactive template/base LV even when
# LVM marks it activation-skip, without leaving it active afterward or
# changing its read-only permission.
test_inactive_source_copy_contract() {
    for tisc_name in copy-lvm.sh create-disk-copy-and-add-to-vm.sh create-disk-copy-and-overwrite-disk-on-vm.sh; do
        tisc_script="$PROJECT_ROOT/$tisc_name"
        grep -F 'SOURCE_ACTIVATED_BY_US=0' "$tisc_script" >/dev/null || return 1
        grep -F 'ensure_source_device()' "$tisc_script" >/dev/null || return 1
        grep -F 'release_source_device()' "$tisc_script" >/dev/null || return 1
        grep -F 'lvchange -ay -K "${SOURCE_VG}/${SOURCE_LV}"' "$tisc_script" >/dev/null || return 1
        grep -F 'lvchange -an "${SOURCE_VG}/${SOURCE_LV}"' "$tisc_script" >/dev/null || return 1
        grep -F '[ -b "$SOURCE_PATH" ] && return 0' "$tisc_script" >/dev/null || return 1
    done

    grep -F 'lvs --noheadings --units b --nosuffix -o lv_size "$SOURCE_PATH"' "$PROJECT_ROOT/copy-lvm.sh" >/dev/null || return 1
    if grep -F 'blockdev --getsize64 "$SOURCE_PATH"' "$PROJECT_ROOT/copy-lvm.sh" >/dev/null 2>&1; then
        printf 'copy-lvm.sh still requires an active source block device to determine LV size.\n' >&2
        return 1
    fi

    # Activation must not change LV permission metadata.
    if grep -E 'lvchange[[:space:]].*(-p|--permission)' "$PROJECT_ROOT/copy-lvm.sh" "$PROJECT_ROOT/create-disk-copy-and-add-to-vm.sh" "$PROJECT_ROOT/create-disk-copy-and-overwrite-disk-on-vm.sh" >/dev/null 2>&1; then
        printf 'Inactive-source activation must not alter LV permission metadata.\n' >&2
        return 1
    fi
    return 0
}

# Fixture setup should establish stopped synthetic NIC configs without calling
# the same qm/pct network mutation API that bulk-change-vm-network.sh is meant
# to exercise. Otherwise a fixture failure can abort the group before a case.
test_network_fixture_separation_contract() {
    tnfs_group="$TEST_ROOT/groups/90-network.sh"
    tnfs_body="$(awk '/^prepare_network_fixture\(\)/,/^}/' "$tnfs_group")"

    if printf '%s\n' "$tnfs_body" | grep -E '(^|[[:space:]])(qm|pct)[[:space:]]+set([[:space:]]|$)' >/dev/null 2>&1; then
        printf 'Network fixture setup must not pre-run qm/pct set for the NIC operation under test.\n' >&2
        return 1
    fi

    printf '%s\n' "$tnfs_body" | grep -F '/etc/pve/qemu-server/${NET_VM1}.conf' >/dev/null || return 1
    printf '%s\n' "$tnfs_body" | grep -F '/etc/pve/lxc/${NET_CT}.conf' >/dev/null || return 1
    printf '%s\n' "$tnfs_body" | grep -F 'qm config "$NET_VM1"' >/dev/null || return 1
    printf '%s\n' "$tnfs_body" | grep -F 'pct config "$NET_CT"' >/dev/null || return 1
    return 0
}

# controller. Ensure move/overwrite helpers refuse that topology before mutation.
# The network group uses a real disposable LXC rootfs, so it must provision
# and register its loopback LVM-thin storage before creating the CT fixture.
test_network_fixture_owned_storage_contract() {
    tnfosc_group="$TEST_ROOT/groups/90-network.sh"
    tnfosc_main="$(awk '/^main\(\)/,/^}/' "$tnfosc_group")"
    tnfosc_fixture="$(awk '/^prepare_network_fixture\(\)/,/^}/' "$tnfosc_group")"

    printf '%s\n' "$tnfosc_main" | grep -F 'create_storage_sandbox' >/dev/null || return 1
    printf '%s\n' "$tnfosc_main" | grep -F 'prepare_network_fixture' >/dev/null || return 1
    tnfosc_storage_line="$(printf '%s\n' "$tnfosc_main" | grep -nF 'create_storage_sandbox' | head -n1 | cut -d: -f1)"
    tnfosc_fixture_line="$(printf '%s\n' "$tnfosc_main" | grep -nF 'prepare_network_fixture' | head -n1 | cut -d: -f1)"
    [ "$tnfosc_storage_line" -lt "$tnfosc_fixture_line" ] || return 1

    printf '%s\n' "$tnfosc_fixture" | grep -F 'test_storage_mapping_owned "$TEST_STORAGE_A"' >/dev/null || return 1
    printf '%s\n' "$tnfosc_fixture" | grep -F 'attach_test_ct_lv "$NET_CT" "$TEST_STORAGE_A"' >/dev/null || return 1
    return 0
}

test_pause_detach_preflight_contract() {
    for tpdpc_name in \
        move-disk-to-vm.sh \
        create-disk-copy-and-overwrite-disk-on-vm.sh \
        create-disk-snapshot-and-overwrite-disk-on-vm.sh; do
        tpdpc_script="$PROJECT_ROOT/$tpdpc_name"
        grep -F 'validate_pause_detach_capability()' "$tpdpc_script" >/dev/null || return 1
        grep -F 'virtio-scsi-single' "$tpdpc_script" >/dev/null || return 1
        grep -F 'only active SCSI disk' "$tpdpc_script" >/dev/null || return 1
    done
    return 0
}

# LXC network tests require a rootfs-capable disposable storage. The test-owned
# LVM-thin sandboxes must advertise rootdir in addition to images.
test_lxc_rootfs_storage_contract() {
    tlrsc_lib="$TEST_ROOT/lib/test-common.sh"
    [ "$(grep -Fc -- '--content images,rootdir' "$tlrsc_lib")" -ge 2 ] || {
        printf 'Disposable lvmthin test storages do not advertise rootdir content.\n' >&2
        return 1
    }
    grep -F 'attach_test_ct_lv "$NET_CT" "$TEST_STORAGE_A" "$NET_CT_ROOT_NAME" rootfs 16M' "$TEST_ROOT/groups/90-network.sh" >/dev/null || return 1
    grep -F 'pct config "$NET_CT"' "$TEST_ROOT/groups/90-network.sh" >/dev/null || return 1
    grep -F 'ug_cmd=pct' "$PROJECT_ROOT/bulk-change-vm-network.sh" >/dev/null || return 1
    grep -F 'dryrun_cmd "$ug_cmd" set "$ug_id" "--$NIC" "$ug_value"' "$PROJECT_ROOT/bulk-change-vm-network.sh" >/dev/null || {
        printf 'bulk-change-vm-network.sh no longer exercises qm/pct set for NIC updates.\n' >&2
        return 1
    }
    return 0
}

# Verifies normal version output without exercising command preflight.
test_lifecycle_first_contract() {
    for tlfc_script in "$PROJECT_ROOT"/*.sh; do
        tlfc_names="$(awk '/^[A-Za-z_][A-Za-z0-9_]*\(\) \{/ {print $1}' "$tlfc_script" | sed 's/()//' | head -n4 | tr '\n' ' ')"
        [ "$tlfc_names" = "setup main end usage " ] || {
            printf '%s lifecycle begins with: %s\n' "$(basename "$tlfc_script")" "$tlfc_names" >&2
            return 1
        }
        tlfc_setup="$(awk '/^setup\(\) \{/,/^}/' "$tlfc_script")"
        tlfc_project_line="$(printf '%s\n' "$tlfc_setup" | grep -n 'PROJECT_VERSION=' | head -n1 | cut -d: -f1)"
        tlfc_colour_line="$(printf '%s\n' "$tlfc_setup" | grep -n 'define_colours' | head -n1 | cut -d: -f1)"
        [ -n "$tlfc_project_line" ] || return 1
        [ -z "$tlfc_colour_line" ] || [ "$tlfc_project_line" -lt "$tlfc_colour_line" ] || {
            printf '%s does not initialize defaults/state before setup helper calls.\n' "$(basename "$tlfc_script")" >&2
            return 1
        }
    done
}

# Every public helper now promises a root/elevation gate in its documentation.
# Detection belongs in setup so main begins with the standard self-elevation gate.
test_elevation_lifecycle_contract() {
    for telc_script in "$PROJECT_ROOT"/*.sh; do
        telc_name="$(basename "$telc_script")"
        telc_setup="$(awk '/^setup\(\) \{/,/^}/' "$telc_script")"
        telc_main="$(awk '/^main\(\) \{/,/^}/' "$telc_script")"
        printf '%s\n' "$telc_setup" | grep -F 'check_elevation' >/dev/null || {
            printf '%s does not detect elevation in setup().\n' "$telc_name" >&2
            return 1
        }
        printf '%s\n' "$telc_main" | grep -F '[ "$APP_ELEVATED" = "true" ] || self_elevate "$@"' >/dev/null || {
            printf '%s does not self-elevate at the main() privilege boundary.\n' "$telc_name" >&2
            return 1
        }
    done
}

# assert_embedded_payload HOST MARKER SOURCE
# Extracts one direct heredoc payload and compares it byte-for-byte to SOURCE.
# Call: assert_embedded_payload HOST MARKER SOURCE
assert_embedded_payload() {
    aep_host="$1"; aep_marker="$2"; aep_source="$3"
    aep_tmp="$TEST_DATA_DIR/embedded-$(basename "$aep_host")-$(basename "$aep_source").txt"
    awk -v marker="$aep_marker" '
        $0 == marker { if (inside) exit; next }
        index($0, marker) { inside=1; next }
        inside { print }
    ' "$aep_host" > "$aep_tmp"
    cmp -s "$aep_tmp" "$aep_source" || {
        printf 'Embedded payload in %s differs from %s.\n' "$aep_host" "$aep_source" >&2
        return 1
    }
}

test_embedded_companion_sync_contract() {
    assert_embedded_payload "$PROJECT_ROOT/copy-disk-between-vms.sh" "__PROXMOX_LONGTAIL_EMBEDDED_CREATE_DISK_COPY_AND_ADD_TO_VM__" "$PROJECT_ROOT/create-disk-copy-and-add-to-vm.sh"
    assert_embedded_payload "$PROJECT_ROOT/snapshot-disk-between-vms.sh" "__PROXMOX_LONGTAIL_EMBEDDED_CREATE_DISK_SNAPSHOT_AND_ADD_TO_VM__" "$PROJECT_ROOT/create-disk-snapshot-and-add-to-vm.sh"
    assert_embedded_payload "$PROJECT_ROOT/move-lvm.sh" "__PROXMOX_LONGTAIL_EMBEDDED_COPY_LVM__" "$PROJECT_ROOT/copy-lvm.sh"
    assert_embedded_payload "$PROJECT_ROOT/clone-single-vm-disk.sh" "__PROXMOX_LONGTAIL_EMBEDDED_COPY_DISK_BETWEEN_VMS__" "$PROJECT_ROOT/copy-disk-between-vms.sh"
}

# Locks the two documentation-driven behavior corrections into the source:
# explicit import slots are SCSI-only and name repair never converts custom LVs.
test_documented_semantics_contract() {
    tdsc_import="$PROJECT_ROOT/import-disk-and-attach.sh"
    tdsc_fix="$PROJECT_ROOT/fix-vm-volume-names.sh"
    tdsc_mount="$PROJECT_ROOT/mount-vm-drive.sh"

    grep -F 'Explicit slot must be scsi0..scsi30' "$tdsc_import" >/dev/null || return 1
    grep -F 'case "$vi_slot_num" in 0|[1-9]|[12][0-9]|30)' "$tdsc_import" >/dev/null || return 1

    grep -F "grep -qE '^(vm|base)-[0-9]+-disk-[0-9]+$'" "$tdsc_fix" >/dev/null || return 1
    grep -F 'Leaving unmanaged LVM volume name unchanged' "$tdsc_fix" >/dev/null || return 1
    if grep -F 'VM_IS_TEMPLATE' "$tdsc_fix" >/dev/null 2>&1; then
        printf 'fix-vm-volume-names.sh still contains the old unmanaged-name family fallback.\n' >&2
        return 1
    fi

    grep -F 'Most likely Linux root:' "$tdsc_mount" >/dev/null || return 1
    grep -F 'mvd_classify_best_score' "$tdsc_mount" >/dev/null || return 1
}

# Future real-host evidence must identify the tested source and runtime environment.
test_evidence_provenance_contract() {
    tepc_lib="$TEST_ROOT/lib/test-common.sh"
    grep -F 'capture_test_provenance()' "$tepc_lib" >/dev/null || return 1
    grep -F 'environment.txt' "$tepc_lib" >/dev/null || return 1
    grep -F 'versions.txt' "$tepc_lib" >/dev/null || return 1
    grep -F 'project-sha256.txt' "$tepc_lib" >/dev/null || return 1
    grep -F 'fixture-manifest.txt' "$tepc_lib" >/dev/null || return 1
    grep -F 'summary.txt' "$tepc_lib" >/dev/null || return 1
}

test_silent_elevation_contract() {
    if grep -R -E 'Elevation:.*running[[:space:]]+as[[:space:]]+root' "$PROJECT_ROOT"/*.sh "$PROJECT_ROOT/lib" "$TEST_ROOT/lib" >/dev/null 2>&1; then
        printf 'Routine root-success elevation output is still present.\n' >&2
        return 1
    fi
    grep -F 'APP_ELEVATED="true"' "$PROJECT_ROOT/lib/common.sh" >/dev/null || return 1
}

test_function_call_documentation_contract() {
    tfcdc_tmp="$TEST_DATA_DIR/function-call-docs.awk"
    cat > "$tfcdc_tmp" <<'AWK'
function finish() {
    if (fn != "" && hasarg && !hasdoc) {
        print file ": function " fn " accepts arguments but has no Call/Usage comment" > "/dev/stderr"
        bad=1
    }
    fn=""; hasarg=0; hasdoc=0
}
BEGIN { fn=""; comments="" }
/^#/ {
    if (fn=="") comments=comments "\n" $0
}
/^[A-Za-z_][A-Za-z0-9_]*\(\) \{/ {
    finish()
    fn=$1
    sub(/\(\).*/,"",fn)
    hasdoc=(comments ~ /# Call:/ || comments ~ /# Usage:/)
    comments=""
    if ($0 ~ /\$[1-9]/ || $0 ~ /\$[@*]/) hasarg=1
    if ($0 ~ /}[[:space:]]*$/) finish()
    next
}
fn != "" {
    if ($0 ~ /\$[1-9]/ || $0 ~ /\$[@*]/) hasarg=1
    if ($0 ~ /^}[[:space:]]*$/) finish()
    next
}
$0 !~ /^[[:space:]]*$/ && $0 !~ /^#/ { comments="" }
END { finish(); exit bad }
AWK
    for tfcdc_script in "$PROJECT_ROOT"/*.sh; do
        sed "/__PROXMOX_LONGTAIL_EMBEDDED_/q" "$tfcdc_script" | awk -v file="$tfcdc_script" -f "$tfcdc_tmp" || return 1
    done
    return 0
}

test_all_versions() {
    for tav_script in "$PROJECT_ROOT"/*.sh; do
        tav_output="$(sh "$tav_script" --version)"
        printf '%s\n' "$tav_output" | grep -F "(project $PROJECT_VERSION)" >/dev/null || { printf 'Unexpected version output from %s: %s\n' "$tav_script" "$tav_output" >&2; return 1; }
    done
}

# Help must remain usable before privilege/environment checks.
test_all_help() {
    for tah_script in "$PROJECT_ROOT"/*.sh; do
        tah_output="$(sh "$tah_script" --help)" || {
            printf '%s --help returned non-zero.\n' "$(basename "$tah_script")" >&2
            return 1
        }
        printf '%s\n' "$tah_output" | grep -Ei '^[[:space:]]*usage([[:space:]]|:|$)' >/dev/null || {
            printf '%s --help does not expose a Usage section/line.\n' "$(basename "$tah_script")" >&2
            return 1
        }
    done
}

test_all_dryrun_prefix() {
    for tad_script in "$PROJECT_ROOT"/*.sh; do sh "$tad_script" dryrun --version >/dev/null; done
}

test_all_dryrun_suffix() {
    for tad_script in "$PROJECT_ROOT"/*.sh; do sh "$tad_script" --version dryrun >/dev/null; done
}

test_style_documents() {
    [ -f "$PROJECT_ROOT/docs/POSIX-SHELL-STYLE-GUIDE-v3.md" ] || return 1
    [ -f "$PROJECT_ROOT/docs/STYLE-PROFILES-AND-EXCEPTIONS.md" ] || return 1
    [ -f "$PROJECT_ROOT/docs/PROXMOX-SHELL-SCRIPTING-LESSONS-LEARNED.md" ] || return 1
    [ -f "$PROJECT_ROOT/docs/testing/TEST-SYSTEM-DESIGN-GUIDE.md" ] || return 1
    [ -f "$PROJECT_ROOT/docs/testing/PROXMOX-TEST-HARNESS-BEST-PRACTICES.md" ] || return 1
    [ -f "$PROJECT_ROOT/docs/testing/POSIX-SHELL-TEST-HARNESS-BEST-PRACTICES.md" ] || return 1
    [ -f "$PROJECT_ROOT/docs/testing/DESTRUCTIVE-SYSTEM-TEST-SAFETY-CHECKLIST.md" ] || return 1

    grep -F '## 54. Distinguish config-reference removal from resource deletion' "$PROJECT_ROOT/docs/POSIX-SHELL-STYLE-GUIDE-v3.md" >/dev/null || return 1
    grep -F '## 60. Guest state semantics must include device topology' "$PROJECT_ROOT/docs/POSIX-SHELL-STYLE-GUIDE-v3.md" >/dev/null || return 1
    grep -F '## 64. Help and usage are stable public interfaces' "$PROJECT_ROOT/docs/POSIX-SHELL-STYLE-GUIDE-v3.md" >/dev/null || return 1
}

# Regression test: dryrun_summary must not make a successful normal-mode
# command return nonzero simply because dry-run is disabled.
test_dryrun_summary_status() {
    sh -c 'set -eu; . "$1/lib/dryrun.sh"; DRY_RUN=0; dryrun_summary' _ "$PROJECT_ROOT"
}

# Proves the shared dry-run executor prints a mutation and returns simulated
# success without allowing that command to run.
test_dryrun_nonmutation() {
    tdn_path="$TEST_DATA_DIR/dryrun-must-not-exist"
    sh -c '
        set -eu
        . "$1/lib/dryrun.sh"
        C_YELLOW=""; C_RESET=""
        DRY_RUN=1
        dryrun_cmd touch "$2"
        [ ! -e "$2" ]
    ' _ "$PROJECT_ROOT" "$tdn_path"
}

# Proves the POSIX temp-file stderr wrapper removes only the known thin-pool
# advisory, replays unrelated stderr, and returns the wrapped command status.
test_lvm_filter_contract() {
    tlf_err="$TEST_DATA_DIR/lvm-filter.stderr"
    set +e
    sh -c '
        set -eu
        . "$1/lib/common.sh"
        run_lvm_filtered sh -c '"'"'printf "%s\n" "WARNING: You have not turned on protection against thin pools running out of space." >&2; printf "%s\n" "REAL-LVM-ERROR" >&2; exit 7'"'"'
    ' _ "$PROJECT_ROOT" 2>"$tlf_err"
    tlf_status=$?
    set -e
    [ "$tlf_status" -eq 7 ] || { printf 'Expected wrapped status 7, got %s.\n' "$tlf_status" >&2; return 1; }
    grep -F "REAL-LVM-ERROR" "$tlf_err" >/dev/null
    ! grep -F "You have not turned on protection" "$tlf_err" >/dev/null
}

# Regression test: an empty other_volume_references result is normal data.
test_empty_reference_status() {
    ters_cfg="$TEST_DATA_DIR/no-reference.conf"
    printf '%s\n' 'name: no-reference-test' > "$ters_cfg"
    sh -c 'set -eu; . "$1/lib/common.sh"; TEST_CONFIG="$2"; all_guest_configs() { printf "%s\n" "$TEST_CONFIG"; }; result="$(other_volume_references definitely-not-present)"; [ -z "$result" ]' _ "$PROJECT_ROOT" "$ters_cfg"
}

# Regression test: Proxmox may rewrite set-valued storage options in a
# different order after add/remove operations without changing semantics.
test_storage_canonicalization() {
    tsc_a="$TEST_DATA_DIR/storage-order-a.cfg"
    tsc_b="$TEST_DATA_DIR/storage-order-b.cfg"
    cat > "$tsc_a" <<EOF
dir: local
    path /var/lib/vz
    content iso,backup,vztmpl
    nodes node-a,node-b

lvmthin: local-lvm
    vgname pve
    thinpool data
    content rootdir,images
EOF
    cat > "$tsc_b" <<EOF
dir: local
    path /var/lib/vz
    content vztmpl,iso,backup
    nodes node-b,node-a

lvmthin: local-lvm
    vgname pve
    thinpool data
    content images,rootdir
EOF
    canonicalize_storage_config "$tsc_a" > "$TEST_DATA_DIR/storage-order-a.canonical"
    canonicalize_storage_config "$tsc_b" > "$TEST_DATA_DIR/storage-order-b.canonical"
    cmp "$TEST_DATA_DIR/storage-order-a.canonical" "$TEST_DATA_DIR/storage-order-b.canonical"
}

# Regression test: each case runs in its own strict subshell so the first
# failed command stops that case and later statements cannot mask it.
test_runner_strictness() {
    trsl_dir="$TEST_DATA_DIR/runner-strictness"
    mkdir -p "$trsl_dir"
    sh -c '
        set -eu
        . "$1/tests/lib/test-common.sh"
        define_colours
        TEST_RESULT_DIR="$2"
        TEST_VERBOSE=false
        test_reset_counters
        failing_case() { printf "before\\n"; false; printf "after\\n"; }
        run_case "inner failure" failing_case >"$TEST_RESULT_DIR/runner-output.log" 2>&1
        [ "$TEST_PASS" -eq 0 ]
        [ "$TEST_FAIL" -eq 1 ]
        grep -F "before" "$TEST_RESULT_DIR/inner-failure.log" >/dev/null
        ! grep -F "after" "$TEST_RESULT_DIR/inner-failure.log" >/dev/null
    ' _ "$PROJECT_ROOT" "$trsl_dir"
}

# test_function_comment_documentation_contract
# Verifies that each public top-level function has a function-named header and
# at least one descriptive comment line in its immediately preceding block.
test_function_comment_documentation_contract() {
    tfcdc_tmp="$TEST_DATA_DIR/function-docs.awk"
    cat > "$tfcdc_tmp" <<'AWK'
function descriptive(block, name, a, n, i, v) {
    n=split(block, a, "\n")
    for (i=1; i<=n; i++) {
        v=a[i]
        sub(/^#[[:space:]]*/, "", v)
        if (v == "" || v ~ /^#+$/) continue
        if (v ~ ("^" name "([[:space:]]|$)")) continue
        if (v ~ /^(Call|Usage):/) continue
        if (v ~ /^[A-Z0-9 _\/-]+$/) continue
        return 1
    }
    return 0
}
function finish() {
    if (fn != "") {
        if (!hasheader) {
            print file ": function " fn " has no function-named comment header" > "/dev/stderr"
            bad=1
        }
        if (!hasdesc) {
            print file ": function " fn " has no descriptive comment line" > "/dev/stderr"
            bad=1
        }
    }
    fn=""; closer=""; hasheader=0; hasdesc=0
}
function begins_function(line) {
    return line ~ /^[A-Za-z_][A-Za-z0-9_]*\(\)[[:space:]]*[\{\(]/
}
BEGIN { fn=""; comments=""; bad=0 }
fn == "" && begins_function($0) {
    finish()
    fn=$1
    sub(/\(\).*/, "", fn)
    closer=($0 ~ /\(\)[[:space:]]*\(/ ? ")" : "}")
    hasheader=(comments ~ ("(^|\n)# " fn "([[:space:]]|$)"))
    hasdesc=descriptive(comments, fn)
    comments=""
    if ((closer == "}" && $0 ~ /}[[:space:]]*$/) ||
        (closer == ")" && $0 ~ /\)[[:space:]]*$/)) finish()
    next
}
fn != "" {
    if ((closer == "}" && $0 ~ /^}[[:space:]]*$/) ||
        (closer == ")" && $0 ~ /^\)[[:space:]]*$/)) finish()
    next
}
fn == "" && /^#/ { comments=comments "\n" $0; next }
fn == "" && /^[[:space:]]*$/ { next }
fn == "" { comments="" }
END { finish(); exit bad }
AWK
    for tfcdc_name in activate-vm-lvs.sh add-vm-disk-reference-only.sh audit-vm-boot-config.sh clone-vm-storage-only.sh compare-vm-disks.sh convert-lv-to-thin.sh convert-thin-to-regular-lv.sh copy-vm-disk-options.sh copy-vm-disk-to-regular-lv.sh copy-vm-disk-to-thin-lv.sh deactivate-vm-lvs.sh export-vm-filesystem.sh export-vm.sh extend-lvm.sh find-shared-vm-volumes.sh find-unreferenced-managed-volumes.sh find-vm-root-filesystem.sh flatten-vm-disk.sh for-each-vm.sh grow-vm-filesystem.sh import-vm.sh migrate-vm-storage-layout.sh mount-all-vm-drives.sh mount-vm-drive.sh normalize-vm-disk-options.sh plan-vm-storage-move.sh rebuild-vm-from-existing-disks.sh remove-vm-disk-reference-only.sh rename-unused-disk-reference.sh renumber-vm-device-slots.sh repair-vm-storage-consistency.sh resize-vm-disk.sh send-vm-export-and-restore.sh show-last-operation.sh show-thin-snapshot-tree.sh show-vm-filesystem-layout.sh show-vm-storage-map.sh sort-vm-disk-slots.sh unmount-all-vm-drives.sh verify-vm-disk-content.sh verify-vm-storage-consistency.sh; do
        tfcdc_script="$PROJECT_ROOT/$tfcdc_name"
        sed "/__PROXMOX_LONGTAIL_EMBEDDED_/q" "$tfcdc_script" |
            awk -v file="$tfcdc_script" -f "$tfcdc_tmp" || return 1
    done
    return 0
}

# test_help_content_contract
# Verifies the complete common public interface advertised by every helper.
test_help_content_contract() {
    thcc_dry='Dry-run: no system changes are made; modifying commands are printed instead of executed.'
    for thcc_script in "$PROJECT_ROOT"/*.sh; do
        thcc_name="$(basename "$thcc_script")"
        thcc_output="$(NO_COLOR=1 sh "$thcc_script" --help)" || return 1
        thcc_first="$(printf '%s\n' "$thcc_output" | sed -n '1p')"
        printf '%s\n' "$thcc_first" | grep -F "$thcc_name " >/dev/null || {
            printf '%s help does not identify the script on the first line.\n' "$thcc_name" >&2
            return 1
        }
        printf '%s\n' "$thcc_first" | grep -F "(project $PROJECT_VERSION)" >/dev/null || {
            printf '%s help does not identify project %s.\n' "$thcc_name" "$PROJECT_VERSION" >&2
            return 1
        }
        for thcc_heading in USAGE DESCRIPTION; do
            printf '%s\n' "$thcc_output" | grep -Fx "$thcc_heading" >/dev/null || {
                printf '%s help is missing %s.\n' "$thcc_name" "$thcc_heading" >&2
                return 1
            }
        done
        for thcc_token in '-h' '-?' '/h' '/?' '--help' '--version' 'dryrun' '--dryrun'; do
            printf '%s\n' "$thcc_output" | grep -F -- "$thcc_token" >/dev/null || {
                printf '%s help does not document %s.\n' "$thcc_name" "$thcc_token" >&2
                return 1
            }
        done
        [ "$(printf '%s\n' "$thcc_output" | grep -F "$thcc_dry" | wc -l | awk '{$1=$1;print}')" -eq 1 ] || {
            printf '%s help must contain the standard one-line dry-run explanation exactly once.\n' "$thcc_name" >&2
            return 1
        }
    done
    return 0
}

# test_parser_option_help_contract
# Verifies every literal long option accepted by parse_arguments is named in
# that helper's live help, preventing command-specific CLI drift.
# Verifies every supported help spelling returns the complete public help before
# elevation or command-specific preflight.
test_help_alias_contract() {
    for thac_script in "$PROJECT_ROOT"/*.sh; do
        for thac_alias in -h '-?' /h '/?' --help; do
            thac_output="$(NO_COLOR=1 sh "$thac_script" "$thac_alias" 2>&1)" || {
                printf '%s rejected help alias %s.\n' "$(basename "$thac_script")" "$thac_alias" >&2
                return 1
            }
            printf '%s\n' "$thac_output" | grep -Fx USAGE >/dev/null || {
                printf '%s help alias %s did not print usage.\n' "$(basename "$thac_script")" "$thac_alias" >&2
                return 1
            }
        done
    done
}

# Verifies commands whose public USAGE contains a required positional argument
# print the usage block when called with no positional arguments.
test_incomplete_argument_usage_contract() {
    tiauc_help="$TEST_DATA_DIR/incomplete-help.txt"
    tiauc_output="$TEST_DATA_DIR/incomplete-output.txt"
    for tiauc_script in "$PROJECT_ROOT"/*.sh; do
        sh "$tiauc_script" --help > "$tiauc_help" 2>&1 || return 1
        awk '
            $0=="USAGE" {inside=1; next}
            inside && /^[A-Z][A-Z -]*$/ {exit}
            inside {print}
        ' "$tiauc_help" | grep -E '<[^>]+>' >/dev/null 2>&1 || continue

        if sh "$tiauc_script" > "$tiauc_output" 2>&1; then
            printf '%s unexpectedly accepted an incomplete empty invocation.\n' "$(basename "$tiauc_script")" >&2
            return 1
        fi
        grep -Fx USAGE "$tiauc_output" >/dev/null || {
            printf '%s did not print usage for incomplete required arguments.\n' "$(basename "$tiauc_script")" >&2
            return 1
        }
    done
}

# The single-drive and all-drive VM mount helpers intentionally use exactly the
# same implementation. Only the hard-coded MOUNT_SCOPE assignment may differ.
test_vm_mount_engine_sync_contract() {
    tvmes_single="$TEST_DATA_DIR/mount-single-normalized.sh"
    sed 's/MOUNT_SCOPE="single"/MOUNT_SCOPE="all"/' "$PROJECT_ROOT/mount-vm-drive.sh" > "$tvmes_single"
    cmp -s "$tvmes_single" "$PROJECT_ROOT/mount-all-vm-drives.sh" || {
        printf 'mount-vm-drive.sh and mount-all-vm-drives.sh drifted beyond MOUNT_SCOPE.\n' >&2
        return 1
    }
    grep -F 'mvd_classify_owned_mounts' "$PROJECT_ROOT/mount-vm-drive.sh" >/dev/null || return 1
    grep -F 'mvfs_verify_mount' "$PROJECT_ROOT/mount-vm-drive.sh" >/dev/null || return 1
    grep -F 'VM $VMID must be stopped before host-side filesystem mounting.' "$PROJECT_ROOT/mount-vm-drive.sh" >/dev/null || return 1
    grep -F 'unmount-all-vm-drives.sh' "$PROJECT_ROOT/mount-vm-drive.sh" >/dev/null || return 1
}

test_parser_option_help_contract() {
    tpohc_source="$TEST_DATA_DIR/parse-arguments.txt"
    tpohc_options="$TEST_DATA_DIR/parse-options.txt"
    for tpohc_script in "$PROJECT_ROOT"/*.sh; do
        tpohc_name="$(basename "$tpohc_script")"
        awk '
            /^parse_arguments\(\)[[:space:]]*\{/ {inside=1}
            inside {print}
            inside && /^}[[:space:]]*$/ {exit}
        ' "$tpohc_script" > "$tpohc_source"
        grep -oE -- '--[A-Za-z0-9][A-Za-z0-9-]*' "$tpohc_source" 2>/dev/null |
            sort -u > "$tpohc_options" || :
        tpohc_help="$(NO_COLOR=1 sh "$tpohc_script" --help)" || return 1
        while IFS= read -r tpohc_option; do
            [ -n "$tpohc_option" ] || continue
            printf '%s\n' "$tpohc_help" | grep -F -- "$tpohc_option" >/dev/null || {
                printf '%s accepts %s but does not document it in --help.\n' "$tpohc_name" "$tpohc_option" >&2
                return 1
            }
        done < "$tpohc_options"
    done
    return 0
}

# test_helper_documentation_sync_contract
# Verifies each per-helper page embeds the exact live-help snapshot and names
# the integration group/coverage that exercises that public command.
test_helper_documentation_sync_contract() {
    thdsc_extract="$TEST_DATA_DIR/helper-doc-help.txt"
    for thdsc_script in "$PROJECT_ROOT"/*.sh; do
        thdsc_name="$(basename "$thdsc_script")"
        thdsc_stem="${thdsc_name%.sh}"
        thdsc_doc="$PROJECT_ROOT/docs/$thdsc_stem.md"
        thdsc_usage="$PROJECT_ROOT/docs/$thdsc_name.usage"
        [ -f "$thdsc_doc" ] && [ -f "$thdsc_usage" ] || {
            printf 'Missing helper documentation for %s.\n' "$thdsc_name" >&2
            return 1
        }
        awk '
            $0 == "<!-- BEGIN LIVE HELP -->" {inside=1; next}
            $0 == "<!-- END LIVE HELP -->" {exit}
            inside && $0 == "```text" {next}
            inside && $0 == "```" {next}
            inside {print}
        ' "$thdsc_doc" > "$thdsc_extract"
        cmp -s "$thdsc_extract" "$thdsc_usage" || {
            printf '%s documentation does not embed its exact .usage snapshot.\n' "$thdsc_name" >&2
            return 1
        }
        grep -Fx '## Purpose' "$thdsc_doc" >/dev/null || return 1
        grep -Fx '## Test coverage' "$thdsc_doc" >/dev/null || return 1
        grep -F "project **v$PROJECT_VERSION**" "$thdsc_doc" >/dev/null || return 1
        grep -F "\`$thdsc_name\`" "$PROJECT_ROOT/tests/TEST-MATRIX.md" >/dev/null || {
            printf '%s has no test-matrix row.\n' "$thdsc_name" >&2
            return 1
        }
    done
    return 0
}
test_all_versions() {
    for tav_script in "$PROJECT_ROOT"/*.sh; do
        tav_output="$(sh "$tav_script" --version)"
        printf '%s\n' "$tav_output" | grep -F "(project $PROJECT_VERSION)" >/dev/null || { printf 'Unexpected version output from %s: %s\n' "$tav_script" "$tav_output" >&2; return 1; }
    done
}

# Help must remain usable before privilege/environment checks.
test_all_help() {
    for tah_script in "$PROJECT_ROOT"/*.sh; do
        tah_output="$(sh "$tah_script" --help)" || {
            printf '%s --help returned non-zero.\n' "$(basename "$tah_script")" >&2
            return 1
        }
        printf '%s\n' "$tah_output" | grep -Ei '^[[:space:]]*usage([[:space:]]|:|$)' >/dev/null || {
            printf '%s --help does not expose a Usage section/line.\n' "$(basename "$tah_script")" >&2
            return 1
        }
    done
}

test_all_dryrun_prefix() {
    for tad_script in "$PROJECT_ROOT"/*.sh; do sh "$tad_script" dryrun --version >/dev/null; done
}

test_all_dryrun_suffix() {
    for tad_script in "$PROJECT_ROOT"/*.sh; do sh "$tad_script" --version dryrun >/dev/null; done
}

test_vm_archive_contract() {
    tvac_export="$PROJECT_ROOT/export-vm.sh"
    tvac_import="$PROJECT_ROOT/import-vm.sh"
    for tvac_text in 'vzdump' 'ltvm/restore.sh' 'ltvm/checksums.sha256' 'sha256sum' 'unusedN' 'backup=0'; do
        grep -F "$tvac_text" "$tvac_export" >/dev/null || return 1
    done
    grep -F 'sha256sum -c' "$tvac_export" >/dev/null || return 1
    grep -F 'ltvm/restore.sh' "$tvac_import" >/dev/null || return 1
    grep -F -- '--no-content-verify' "$tvac_import" >/dev/null || return 1
    grep -F 'duplicate member paths' "$tvac_import" >/dev/null || return 1
    grep -F 'symlink, hardlink, device, FIFO' "$tvac_import" >/dev/null || return 1
    grep -F 'Every regular archive member must be covered exactly once by checksums.' "$tvac_import" >/dev/null || return 1
    grep -F 'every regular archive member must be covered exactly once by checksums' "$tvac_export" >/dev/null || return 1
}

test_remote_archive_contract() {
    trac="$PROJECT_ROOT/send-vm-export-and-restore.sh"
    grep -F 'scp' "$trac" >/dev/null || return 1
    grep -F 'ssh' "$trac" >/dev/null || return 1
    grep -F 'sha256sum' "$trac" >/dev/null || return 1
    grep -F 'restore.sh' "$trac" >/dev/null || return 1
    grep -F 'Remote archive SHA-256 does not match' "$trac" >/dev/null || return 1
}

test_for_each_no_eval_contract() {
    tfne="$PROJECT_ROOT/for-each-vm.sh"
    ! grep -E '(^|[[:space:]])eval([[:space:]]|$)' "$tfne" >/dev/null
}

test_v36_regular_copy_contract() {
    for tvrc in convert-thin-to-regular-lv.sh copy-vm-disk-to-regular-lv.sh; do
        tvrc_file="$PROJECT_ROOT/$tvrc"
        ! grep -F 'conv=sparse' "$tvrc_file" >/dev/null || return 1
        grep -F 'conv=fsync' "$tvrc_file" >/dev/null || return 1
    done
}

test_v36_growth_contract() {
    tvgc_resize="$PROJECT_ROOT/resize-vm-disk.sh"
    tvgc_extend="$PROJECT_ROOT/extend-lvm.sh"
    tvgc_fs="$PROJECT_ROOT/grow-vm-filesystem.sh"
    grep -F 'qm resize' "$tvgc_resize" >/dev/null || return 1
    grep -F 'lvextend' "$tvgc_extend" >/dev/null || return 1
    grep -F 'resize2fs' "$tvgc_fs" >/dev/null || return 1
    grep -F 'xfs_growfs' "$tvgc_fs" >/dev/null || return 1
    ! grep -E 'lvreduce|resize2fs[[:space:]]+-M|xfs.*shrink' "$tvgc_resize" "$tvgc_extend" "$tvgc_fs" >/dev/null
}

test_v36_workflow_rollback_contract() {
    tvwr_repair="$PROJECT_ROOT/repair-vm-storage-consistency.sh"
    for tvwr_text in 'RVSC_UUID' 'rvsc_lv_name_by_uuid()' 'rvsc_rollback()' 'ROLLBACK FAILED' 'volid_reference_count'; do
        grep -F "$tvwr_text" "$tvwr_repair" >/dev/null || return 1
    done
    tvwr_flatten="$PROJECT_ROOT/flatten-vm-disk.sh"
    grep -F 'FVD_SOURCE_WAS_INACTIVE' "$tvwr_flatten" >/dev/null || return 1
    grep -F 'lvchange -ay -K' "$tvwr_flatten" >/dev/null || return 1
    grep -F 'fvd_cleanup "$?"' "$tvwr_flatten" >/dev/null || return 1
    return 0
}

# test_common_option_version_ordering
# Proves the documented common presentation/plan options are accepted before
# --version by every public helper without crossing mutation/elevation gates.
test_common_option_version_ordering() {
    for tcovo_script in "$PROJECT_ROOT"/*.sh; do
        grep -F 'preparse_common_options()' "$tcovo_script" >/dev/null 2>&1 || continue
        for tcovo_option in --plan --preflight --no-color --quiet; do
            sh "$tcovo_script" "$tcovo_option" --version >/dev/null || {
                printf '%s rejects %s before --version.\n' "$(basename "$tcovo_script")" "$tcovo_option" >&2
                return 1
            }
        done
    done
    return 0
}


# test_v362_new_runtime_identity_contract
# Verifies the 40 newly integrated standalone helpers carry one synchronized
# common runtime and use physical LVM identity for reference decisions.
test_v362_new_runtime_identity_contract() {
    tvnri_ref="$TEST_DATA_DIR/v362-common-runtime.ref"
    tvnri_tmp="$TEST_DATA_DIR/v362-common-runtime.tmp"
    tvnri_first=true
    for tvnri_name in activate-vm-lvs.sh add-vm-disk-reference-only.sh audit-vm-boot-config.sh clone-vm-storage-only.sh compare-vm-disks.sh convert-lv-to-thin.sh convert-thin-to-regular-lv.sh copy-vm-disk-options.sh copy-vm-disk-to-regular-lv.sh copy-vm-disk-to-thin-lv.sh deactivate-vm-lvs.sh export-vm-filesystem.sh export-vm.sh extend-lvm.sh find-shared-vm-volumes.sh find-unreferenced-managed-volumes.sh find-vm-root-filesystem.sh flatten-vm-disk.sh for-each-vm.sh grow-vm-filesystem.sh import-vm.sh migrate-vm-storage-layout.sh mount-all-vm-drives.sh mount-vm-drive.sh normalize-vm-disk-options.sh plan-vm-storage-move.sh rebuild-vm-from-existing-disks.sh remove-vm-disk-reference-only.sh rename-unused-disk-reference.sh renumber-vm-device-slots.sh repair-vm-storage-consistency.sh resize-vm-disk.sh send-vm-export-and-restore.sh show-last-operation.sh show-thin-snapshot-tree.sh show-vm-filesystem-layout.sh show-vm-storage-map.sh sort-vm-disk-slots.sh unmount-all-vm-drives.sh verify-vm-disk-content.sh verify-vm-storage-consistency.sh; do
        awk '
            /^preparse_common_options\(\)[[:space:]]*\{/ {inside=1}
            /^############################################################$/ && inside && nextline {exit}
            inside {print}
            inside && /^############################################################$/ {nextline=1; next}
            nextline && /^# ARGUMENT PARSING$/ {exit}
            nextline {nextline=0}
        ' "$PROJECT_ROOT/$tvnri_name" > "$tvnri_tmp"
        if [ "$tvnri_first" = true ]; then
            cp "$tvnri_tmp" "$tvnri_ref"
            tvnri_first=false
        else
            cmp -s "$tvnri_ref" "$tvnri_tmp" || {
                printf 'New helper common runtime drifted: %s\n' "$tvnri_name" >&2
                return 1
            }
        fi
    done
    grep -F 'volid_lv_uuid()' "$PROJECT_ROOT/activate-vm-lvs.sh" >/dev/null || return 1
    grep -F 'lv_uuid_reference_count()' "$PROJECT_ROOT/activate-vm-lvs.sh" >/dev/null || return 1
    grep -F 'run_lvm_filtered()' "$PROJECT_ROOT/activate-vm-lvs.sh" >/dev/null || return 1
}

# test_v362_copy_failure_cleanup_contract
# Proves the four new independent-copy/conversion helpers restore temporary
# source activation before failure cleanup and bind destination cleanup to UUID.
test_v362_copy_failure_cleanup_contract() {
    for tvcfc_name in convert-lv-to-thin.sh convert-thin-to-regular-lv.sh copy-vm-disk-to-regular-lv.sh copy-vm-disk-to-thin-lv.sh; do
        tvcfc_file="$PROJECT_ROOT/$tvcfc_name"
        grep -F 'Restore source activation state before doing anything that may fail.' "$tvcfc_file" >/dev/null || return 1
        grep -F 'created by this invocation. Name reuse never authorizes deletion.' "$tvcfc_file" >/dev/null || return 1
        grep -F 'DEST_UUID' "$tvcfc_file" >/dev/null || return 1
        grep -F 'lvchange -an' "$tvcfc_file" >/dev/null || return 1
    done
}

# test_v362_mount_ownership_contract
# Verifies the mount pair records invocation ownership, validates exact source
# identity before unmount, and does not recursively unmount arbitrary children.
test_v362_mount_ownership_contract() {
    tvmoc_mount="$PROJECT_ROOT/mount-all-vm-drives.sh"
    tvmoc_single="$PROJECT_ROOT/mount-vm-drive.sh"
    tvmoc_unmount="$PROJECT_ROOT/unmount-all-vm-drives.sh"
    grep -F '.longtailtoil-mounts-' "$tvmoc_mount" >/dev/null || return 1
    grep -F '.longtailtoil-mounts-' "$tvmoc_single" >/dev/null || return 1
    grep -F 'ROOT_CREATED' "$tvmoc_mount" >/dev/null || return 1
    grep -F 'DIR|' "$tvmoc_mount" >/dev/null || return 1
    grep -F 'Mounted source does not match selected device' "$tvmoc_mount" >/dev/null || return 1
    grep -F '.longtailtoil-mounts-' "$tvmoc_unmount" >/dev/null || return 1
    grep -F 'Recorded mount source changed' "$tvmoc_unmount" >/dev/null || return 1
    ! grep -E 'find[[:space:]].*(-mount|-xdev).*(umount|unmount)' "$tvmoc_unmount" >/dev/null || return 1
}

# test_v362_direct_config_transaction_contract
# Ensures reference-only and direct config editors use strict slot/snapshot
# preflight plus a backup/rollback boundary before direct config writes.
test_v362_direct_config_transaction_contract() {
    for tvdct_name in add-vm-disk-reference-only.sh remove-vm-disk-reference-only.sh rename-unused-disk-reference.sh renumber-vm-device-slots.sh sort-vm-disk-slots.sh; do
        tvdct_file="$PROJECT_ROOT/$tvdct_name"
        grep -F 'qemu_config_has_snapshots' "$tvdct_file" >/dev/null || return 1
        grep -E 'valid_(disk|unused|qemu_storage)_slot' "$tvdct_file" >/dev/null || return 1
        grep -F 'backup' "$tvdct_file" >/dev/null || return 1
        grep -E 'rollback|restore' "$tvdct_file" >/dev/null || return 1
    done
}

# test_v362_growth_exactness_contract
# Keeps block growth and filesystem growth separate and requires exact XFS
# mountpoint/source verification before online growth.
test_v362_growth_exactness_contract() {
    tvge="$PROJECT_ROOT/grow-vm-filesystem.sh"
    grep -F 'findmnt -rn -M' "$tvge" >/dev/null || return 1
    grep -F 'xfs_growfs' "$tvge" >/dev/null || return 1
    grep -F 'resize2fs' "$tvge" >/dev/null || return 1
    grep -F 'lv_uuid_reference_count' "$tvge" >/dev/null || return 1
    ! grep -F 'lvextend' "$tvge" >/dev/null || return 1
    ! grep -F 'qm resize' "$tvge" >/dev/null || return 1
}

# test_v362_journal_remote_safety_contract
# Verifies new journals are unpredictable/root-owned and the remote restore
# reserves an absent destination then hashes the complete transferred archive.
test_v362_journal_remote_safety_contract() {
    tvjrs="$PROJECT_ROOT/send-vm-export-and-restore.sh"
    tvjre="$PROJECT_ROOT/export-vm.sh"
    grep -F 'mktemp' "$PROJECT_ROOT/show-last-operation.sh" "$tvjre" >/dev/null || return 1
    grep -F 'root-owned' "$PROJECT_ROOT/show-last-operation.sh" >/dev/null || return 1
    grep -F 'set -C' "$tvjrs" >/dev/null || return 1
    grep -F 'Remote archive SHA-256 does not match' "$tvjrs" >/dev/null || return 1
    grep -F 'sha256sum' "$tvjrs" >/dev/null || return 1
}


# test_v371_disk_option_semantic_contract
# Proves copy-vm-disk-options verifies exact backing identity while comparing
# comma-separated Proxmox option tokens independent of canonical field order.
test_v371_disk_option_semantic_contract() {
    tvdoc="$PROJECT_ROOT/copy-vm-disk-options.sh"
    grep -F 'cvdo_canonical_value()' "$tvdoc" >/dev/null || return 1
    grep -F 'cvdo_values_equivalent()' "$tvdoc" >/dev/null || return 1
    grep -F 'LC_ALL=C sort' "$tvdoc" >/dev/null || return 1
    grep -F 'CVDO_ACTUAL="$(disk_value "$DST_VM" "$DST_SLOT")"' "$tvdoc" >/dev/null || return 1
    grep -F 'cvdo_values_equivalent "$CVDO_NEW" "$CVDO_ACTUAL"' "$tvdoc" >/dev/null || return 1
}

# test_v371_clone_staging_contract
# Proves clone-vm-storage-only never passes a source block path directly to
# qm importdisk and restores temporary source activation before import.
test_v371_clone_staging_contract() {
    tvcsc="$PROJECT_ROOT/clone-vm-storage-only.sh"
    grep -F 'qemu-img convert -p -f raw -O raw -S 4k "$CVSO_PATH" "$CVSO_STAGE_FILE"' "$tvcsc" >/dev/null || return 1
    grep -F 'qm importdisk "$DST_VM" "$CVSO_STAGE_FILE" "$CVSO_TARGET_STORAGE"' "$tvcsc" >/dev/null || return 1
    ! grep -F 'qm importdisk "$DST_VM" "$CVSO_PATH" "$CVSO_TARGET_STORAGE"' "$tvcsc" >/dev/null || return 1
    grep -F 'cvso_release_source_device ||' "$tvcsc" >/dev/null || return 1
    grep -F 'cmp -n "$CVSO_STAGE_SIZE" "$CVSO_STAGE_FILE" "$READABLE_PATH"' "$tvcsc" >/dev/null || return 1
    grep -F 'cvso_remove_stage' "$tvcsc" >/dev/null || return 1
}

# test_v371_archive_exactness_contract
# Proves exact QEMU restore treats vmgenid as Proxmox-regenerated identity,
# while checksum validation is executed from the archive root.
test_v371_archive_exactness_contract() {
    tvaec="$PROJECT_ROOT/export-vm.sh"
    tvaet="$PROJECT_ROOT/tests/groups/95-vm-archive.sh"
    grep -F '/^vmgenid:[[:space:]]/ {next}' "$tvaec" >/dev/null || return 1
    grep -F 'restored QEMU config is missing the regenerated vmgenid' "$tvaec" >/dev/null || return 1
    grep -F 'cd "$vae_tmp" && sha256sum -c ltvm/checksums.sha256' "$tvaet" >/dev/null || return 1
    grep -F '!/^vmgenid:[[:space:]]/' "$tvaet" >/dev/null || return 1
}

# test_v371_remote_dryrun_contract
# Proves the dry-run branch returns before remote preflight/SSH and that real
# preflight refuses to persist an unknown SSH host key.
test_v371_remote_dryrun_contract() {
    tvrd="$PROJECT_ROOT/send-vm-export-and-restore.sh"
    tvrd_dry="$(grep -nF 'if [ "$DRYRUN" -eq 1 ]; then' "$tvrd" | head -n1 | cut -d: -f1)"
    tvrd_pre="$(grep -nF 'if ! sver_remote_preflight 1; then' "$tvrd" | head -n1 | cut -d: -f1)"
    [ -n "$tvrd_dry" ] && [ -n "$tvrd_pre" ] || return 1
    [ "$tvrd_dry" -lt "$tvrd_pre" ] || return 1
    grep -F 'ssh -o StrictHostKeyChecking=yes "$DEST" "$SVER_REMOTE_CHECK"' "$tvrd" >/dev/null || return 1
}


############################################################
# START
############################################################

setup "$@"
main "$@"
end
