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
    PROJECT_VERSION="3.2.0"
    TEST_SUITE_VERSION="2.2.0"
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
    printf '%s\n' "  - parse all 40 v3 commands and canonical maintenance libraries with /bin/sh"
    printf '%s\n' "  - prove each top-level command runs help/version when copied completely alone"
    printf '%s\n' "  - require /bin/sh entry-point shebangs and reject known Bash-only constructs"
    printf '%s\n' "  - test --version and --help without root/Proxmox preflight"
    printf '%s\n' "  - test dryrun keyword parsing before and after --version"
    printf '%s\n' "  - verify the v3 style-guide documents are packaged"
    printf '%s\n' "  - verify shared helper and test-runner regression contracts"
}

############################################################
# TEST CASES
############################################################

# Verifies that every project entry point and shared shell library parses in sh.
test_all_script_syntax() {
    tas_count=0
    for tas_script in "$PROJECT_ROOT"/*.sh; do sh -n "$tas_script"; tas_count=$((tas_count + 1)); done
    [ "$tas_count" -eq 40 ] || { printf 'Expected 40 project commands, found %s.\n' "$tas_count" >&2; return 1; }
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
        printf '%s\n' "$tas_version" | grep -F "(project 3.2.0)" >/dev/null || return 1
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

# Verifies normal version output without exercising command preflight.
test_all_versions() {
    for tav_script in "$PROJECT_ROOT"/*.sh; do
        tav_output="$(sh "$tav_script" --version)"
        printf '%s\n' "$tav_output" | grep -F "(project 3.2.0)" >/dev/null || { printf 'Unexpected version output from %s: %s\n' "$tav_script" "$tav_output" >&2; return 1; }
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
