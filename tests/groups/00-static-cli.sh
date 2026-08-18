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
    PROJECT_VERSION="3.4.2"
    TEST_SUITE_VERSION="2.8.0"
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
    run_case "README and test matrix cover every public command exactly once" test_public_documentation_coverage_contract
    run_case "LXC cleanup uses exact identity and owned-storage guards" test_ct_cleanup_safety_contract
    run_case "Protected baseline includes guest runtime and firewall state" test_protected_runtime_contract
    run_case "Cleanup fails closed between guest/storage/VG layers" test_layered_cleanup_contract
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
    TEST_DATA_DIR="$TEST_RESULT_DIR/data"
    mkdir -p "$TEST_DATA_DIR"
}

# finish_static_run
# Prints the static group counters and removes its temporary evidence directory.
finish_static_run() {
    print_banner "Test group result"
    printf '%sPassed%s    : %s%s%s\n' "$CYAN" "$RESET" "$GREEN" "$TEST_PASS" "$RESET"
    printf '%sFailed%s    : %s%s%s\n' "$CYAN" "$RESET" "$RED" "$TEST_FAIL" "$RESET"
    printf '%sSkipped%s   : %s%s%s\n' "$CYAN" "$RESET" "$YELLOW" "$TEST_SKIP" "$RESET"
    printf '%sAnomalies%s : %s%s%s\n' "$CYAN" "$RESET" "$YELLOW" "$TEST_ANOMALY" "$RESET"
    [ "$TEST_FAIL" -eq 0 ] || { printf '%sLogs%s      : %s%s%s\n' "$CYAN" "$RESET" "$BLUE" "$TEST_RESULT_DIR" "$RESET"; return 1; }
    rm -rf "$TEST_RESULT_DIR"
    return 0
}

############################################################
# TEST PLAN
############################################################

print_plan() {
    print_banner "Static / CLI tests"
    printf '%s\n' "No test has been executed. Re-run with --run to:"
    printf '%s\n' "  - parse all 42 v3 commands and canonical maintenance libraries with /bin/sh"
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
    [ "$tas_count" -eq 42 ] || { printf 'Expected 42 project commands, found %s.\n' "$tas_count" >&2; return 1; }
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
    grep -F 'base-${VMID}-disk-' "$tmvfc_fix" >/dev/null || return 1

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
    grep -F 'partx --show --raw --noheadings -o NR,START,SECTORS,TYPE' "$tih_fs" >/dev/null || return 1
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
        tpdc_count=$((tpdc_count + 1))

        [ "$(grep -Fc "#### \`$tpdc_name\`" "$tpdc_readme")" -eq 1 ] || {
            printf 'README must contain exactly one helper heading for %s.\n' "$tpdc_name" >&2
            return 1
        }

        tpdc_wget="wget -q \"https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/$tpdc_name\" -O \"$tpdc_name\" && chmod +x \"$tpdc_name\""
        [ "$(grep -Fc "$tpdc_wget" "$tpdc_readme")" -eq 1 ] || {
            printf 'README must contain exactly one standalone wget+chmod line for %s.\n' "$tpdc_name" >&2
            return 1
        }

        [ "$(grep -Fc "\`$tpdc_name\`" "$tpdc_matrix")" -eq 1 ] || {
            printf 'TEST-MATRIX.md must contain exactly one command row for %s.\n' "$tpdc_name" >&2
            return 1
        }
    done

    [ "$tpdc_count" -eq 42 ] || {
        printf 'Expected 42 public commands, found %s.\n' "$tpdc_count" >&2
        return 1
    }
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
            audit-vm-storage.sh|find-orphaned-volumes.sh|find-volume-owner.sh|list-all-vm-lvm-filesystems.sh|list-all-vm-lvm.sh|list-vm-disks.sh|verify-vm-disk-numbering.sh)
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

# Verifies normal version output without exercising command preflight.
test_all_versions() {
    for tav_script in "$PROJECT_ROOT"/*.sh; do
        tav_output="$(sh "$tav_script" --version)"
        printf '%s\n' "$tav_output" | grep -F "(project $PROJECT_VERSION)" >/dev/null || { printf 'Unexpected version output from %s: %s\n' "$tav_script" "$tav_output" >&2; return 1; }
    done
}

# Help must remain usable before privilege/environment checks.
test_all_help() {
    for tah_script in "$PROJECT_ROOT"/*.sh; do sh "$tah_script" --help >/dev/null; done
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
    [ -f "$PROJECT_ROOT/docs/testing/TEST-SYSTEM-DESIGN-GUIDE.md" ] || return 1
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

############################################################
# START
############################################################

setup "$@"
main "$@"
end
