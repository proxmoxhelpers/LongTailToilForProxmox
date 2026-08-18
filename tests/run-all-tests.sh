#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/test-common.sh"

############################################################
# SETUP / MAIN / END
############################################################

setup() {
    define_colours
    PROJECT_VERSION="3.5.1"
    TEST_SUITE_VERSION="2.9.1"
    ALL_RUN="false"
    ALL_VERBOSE="false"
    parse_arguments "$@"
    [ "$ALL_RUN" = "false" ] || check_elevation
}

main() {
    [ "$ALL_RUN" = "true" ] || { print_plan; return 0; }
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    run_all_groups
}

end() {
    [ "$ALL_RUN" = "true" ] || return 0
    print_banner "All-groups result"
    printf '%sGroups passed%s : %s%s%s\n' "$CYAN" "$RESET" "$GREEN" "$ALL_PASS" "$RESET"
    printf '%sGroups failed%s : %s%s%s\n' "$CYAN" "$RESET" "$RED" "$ALL_FAIL" "$RESET"
    [ "$ALL_FAIL" -eq 0 ]
}

############################################################
# COMMAND LINE
############################################################

usage() {
    cat <<EOF
$(basename "$0") — Proxmox LVM Tools complete integration test launcher

USAGE
  $(basename "$0") [--run] [--verbose]

OPTIONS
  --run
      Execute every test group. Without --run, print the plan only.

  --verbose
      Ask every group to print passing test logs.

  -h, --help
      Show this help.

SAFETY
  Each mutating group builds its own uniquely named loopback sandbox and
  removes it before the next group. The all-groups launcher intentionally
  does not provide --keep so a full run cannot leave many sandboxes behind.
EOF
}

parse_arguments() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --run) ALL_RUN="true"; shift ;;
            --verbose) ALL_VERBOSE="true"; shift ;;
            -h|--help) usage; exit 0 ;;
            *) die "Unknown test option: $1" ;;
        esac
    done
}

############################################################
# TEST PLAN
############################################################

print_plan() {
    print_banner "Complete Proxmox LVM Tools test plan"
    printf '%s\n' "No integration test has been executed. Re-run with --run."
    printf '%s\n' "Groups:"
    for rag_group in "$SCRIPT_DIR"/groups/*.sh; do printf '  %s\n' "$(basename "$rag_group")"; done
    printf '\n%s\n' "Every mutating group:"
    printf '%s\n' "  1. captures protected pre-existing state"
    printf '%s\n' "  2. creates only uniquely named loopback-backed fixtures"
    printf '%s\n' "  3. proves each command dry-run leaves test state unchanged"
    printf '%s\n' "  4. performs the real operation only on disposable fixtures"
    printf '%s\n' "  5. verifies postconditions"
    printf '%s\n' "  6. ownership-checks cleanup"
    printf '%s\n' "  7. compares protected state before/after and logs anomalies"
}

############################################################
# GROUP EXECUTION
############################################################

run_all_groups() {
    ALL_PASS=0
    ALL_FAIL=0
    for rag_group in "$SCRIPT_DIR"/groups/*.sh; do
        print_banner "Running $(basename "$rag_group")"
        if [ "$ALL_VERBOSE" = "true" ]; then
            if "$rag_group" --run --verbose; then ALL_PASS=$((ALL_PASS + 1)); else ALL_FAIL=$((ALL_FAIL + 1)); fi
        else
            if "$rag_group" --run; then ALL_PASS=$((ALL_PASS + 1)); else ALL_FAIL=$((ALL_FAIL + 1)); fi
        fi
    done
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
