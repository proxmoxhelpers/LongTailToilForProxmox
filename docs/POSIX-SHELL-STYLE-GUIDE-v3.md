# POSIX Shell Programming Style Guide — Proxmox LVM Tools v3

This guide defines the coding style for the future v3 rewrite of Proxmox LVM Tools.

The goals are to make every script easy to scan, internally documented, compact without becoming cryptic, conservative around destructive operations, and understandable independently even when common helpers are shared.

This guide defines style only. v3 scripts should be rewritten and tested individually rather than generated as one untested bulk conversion.

## 1. Language and interpreter

Target POSIX shell by default:

```sh
#!/bin/sh
set -eu
```

Use POSIX shell syntax whenever reasonably possible. The programs may still depend on Proxmox/Linux utilities such as `qm`, `pct`, `pvesm`, `lvs`, `lvcreate`, `lvrename`, `lvremove`, `kpartx`, `findmnt`, `lsblk`, `blkid`, `qemu-img`, and `mktemp`.

Do not silently introduce Bash syntax. The following are not permitted in a POSIX script:

```text
[[ ... ]]
arrays / mapfile / readarray
process substitution <(...)
here strings <<<
source
local / declare / typeset
$'...'
&>
(( expression )) as a command
```

If a script genuinely becomes unreasonable or unsafe in POSIX shell, a Bash exception may be considered during that script's individual review. The exception must be intentional and documented.

## 2. Compact syntax

Prefer compact code where a complete operation is easy to understand as one logical statement.

Preferred:

```sh
[ "$(id -u)" -eq 0 ] || die "This script must be run as root."
SOURCE_POOL="$(lvs --noheadings -o pool_lv "$SOURCE" 2>/dev/null | trim)"
for CMD in lvs lvcreate lvremove qm pvesm readlink awk grep sed; do require_command "$CMD"; done
```

Do not wrap commands with trailing backslashes merely to satisfy a line-length rule. There is no 80-column rule.

Multiline form is appropriate for here-documents, substantial `case`/`if`/loop bodies, large `awk` programs, generated content, and data tables.

> Keep one logical operation on one line when doing so improves readability. Break structure, not syntax.

## 3. Standard file scaffold

Every executable script follows this high-level structure:

```sh
#!/bin/sh
set -eu

############################################################
# SETUP / MAIN / END
############################################################

setup() {
    define_colours
    # Configuration
    PROJECT_VERSION="3.x.x"
    SCRIPT_VERSION="..."
    # Setup
    parse_arguments "$@"
}

main() {
    high_level_operation
}

end() {
    print_success "Completed."
}

############################################################
# COMMAND LINE
############################################################

...

############################################################
# HIGH LEVEL TASKS
############################################################

...

############################################################
# GENERAL HELPERS
############################################################

...

############################################################
# START
############################################################

setup "$@"
main "$@"
end
```

Operational logic should live in functions. Top-level code should be limited to safe constants required before functions, script-directory/library setup when necessary, and the final lifecycle calls.

## 4. Meaning of setup, main, and end

`setup()` performs one-time preparation: colours, versions/defaults, argument parsing, environment detection, and elevation detection when required. It must not perform privileged mutations before the elevation gate.

`main()` expresses the operation in high-level steps. Someone reading only `main()` should understand the procedure:

```sh
main() {
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    install_dependencies
    validate_environment
    validate_source
    validate_destination
    print_plan
    stop_guest
    create_destination
    copy_data
    verify_copy
    update_configuration
    verify_result
}
```

`end()` performs normal completion work: summaries, success messages, result paths, and follow-up reminders. Do not use it as a second `main()`.

## 5. Privilege detection and self-elevation

POSIX variable names cannot contain dots, so conceptual `app.elevated` becomes:

```sh
APP_ELEVATED
```

Its values are exactly `true` or `false`.

For root-requiring scripts:

1. `setup()` calls `check_elevation`.
2. `check_elevation` sets and exports `APP_ELEVATED`.
3. The elevation state is printed.
4. `main()` checks `APP_ELEVATED` before privileged work.
5. If necessary, the script re-executes itself through `sudo`.
6. Original CLI arguments are preserved with `"$@"`.

Reference:

```sh
############################################################
# check_elevation
#
# Description:
#   Detects whether the script is currently running as root.
#
# Usage:
#   check_elevation
#
# Arguments:
#   None.
#
# Output:
#   Sets and exports APP_ELEVATED to true or false.
#   Prints the detected elevation state.
#
# Returns:
#   0 always.
############################################################
check_elevation() {
    if [ "$(id -u)" -eq 0 ]; then APP_ELEVATED="true"; print_success "Elevation: running as root."
    else APP_ELEVATED="false"; print_warning "Elevation: not running as root."; fi
    export APP_ELEVATED
}

############################################################
# self_elevate
#
# Description:
#   Re-executes the current script as root while preserving all
#   original command-line arguments.
#
# Usage:
#   self_elevate "$@"
#
# Arguments:
#   $@  Original script command-line arguments.
#
# Output:
#   Replaces the current process with an elevated copy.
#
# Returns:
#   Does not return on success.
############################################################
self_elevate() {
    command -v sudo >/dev/null 2>&1 || die "Root privileges are required and sudo is unavailable."
    print_warning "Re-running with root privileges..."
    exec sudo -- /bin/sh "$0" "$@"
}
```

Elevate once rather than prefixing every command with `sudo`.

Scripts that do not require root should not carry unused self-elevation machinery.

## 6. Command-line processing

Every executable supports `-h`, `--help`, and `--version`, and those must work without root.

Argument parsing occurs before the privilege gate.

For simple positional programs:

```sh
parse_arguments() {
    [ "$#" -eq 2 ] || { usage; exit 2; }
    SOURCE="$1"
    DESTINATION="$2"
}
```

For options, use `case`. Do not use `eval` for parsing.

## 7. Usage text

Every script has `usage()` and should include, where applicable:

```text
NAME / VERSION
USAGE
DESCRIPTION
ARGUMENTS
OPTIONS
EXAMPLES
NOTES
```

Usage errors exit `2`; runtime failures normally exit `1`.

## 8. Section organization

Use banners such as:

```sh
############################################################
# VALIDATION / PRE-FLIGHT
############################################################
```

Typical order:

```text
SETUP / MAIN / END
COMMAND LINE
PRIVILEGE
DEPENDENCIES
VALIDATION / PRE-FLIGHT
HIGH LEVEL TASKS
DOMAIN-SPECIFIC OPERATIONS
VERIFICATION
RESULTS / DIAGNOSTICS
GENERAL HELPERS
START
```

Do not create empty sections.

## 9. Function documentation

Every non-trivial function gets a documentation block immediately before it:

```sh
############################################################
# resolve_volume_path
#
# Description:
#   Resolves a Proxmox storage volume ID to its underlying path.
#
# Usage:
#   resolve_volume_path STORAGE_VOLUME
#
# Arguments:
#   $1  Proxmox storage volume ID.
#
# Output:
#   stdout  Resolved path on success.
#
# Returns:
#   0  Volume was resolved.
#   1  Volume could not be resolved.
############################################################
resolve_volume_path() (
    rvp_volume="$1"
    pvesm path "$rvp_volume" 2>/dev/null
)
```

Required fields are Description, Usage, Arguments, Output, and Returns. Sanctioned relaxed forms are defined in the companion style-profiles document.

## 10. Function spacing

Use exactly one blank line between top-level function definitions. Avoid decorative blank lines inside functions. Comments should explain intent, risk, or invariants.

## 11. Function names

Use lower snake case and verb-first names. Predicates normally begin `is_`, `has_`, or `can_`. Requirement functions begin `require_`. Mutating functions should name the mutation clearly.

## 12. Variable naming

Persistent state uses uppercase snake case. Framework state uses `APP_`.

POSIX shell has no standard `local`. Prefer subshell functions where private scope helps. Function-private variables use a short function-derived prefix. Caller-visible output variables are uppercase and documented.

## 13. Subshell functions as local scope

Prefer:

```sh
calculate_value() (
    cv_input="$1"
    cv_result="..."
    printf '%s\n' "$cv_result"
)
```

when state need not survive the function. Use `{ ...; }` functions when parent-shell mutation is intentional.

## 14. Return values and function output

Return status means success/failure. Data normally goes to stdout; diagnostics go to stderr. Functions used in command substitution must not contaminate stdout with banners or informational messages.

## 15. Early returns

Use ordinary `return` and guard clauses where they improve clarity. Do not force an artificial single-exit pattern. Mutation functions still need transactional safety.

## 16. Conditions

Use POSIX `[ ... ]`, never `[[ ... ]]`. Avoid `test -a` and `test -o`; use shell `&&`/`||`. Use `case` for patterns.

## 17. Short if statements

Keep short conditions compact:

```sh
[ -n "$SOURCE" ] || die "Source is required."
```

Use multiline `if` for substantial bodies.

## 18. Loops

Short loops stay compact:

```sh
for CMD in qm pvesm lvs awk sed grep; do require_command "$CMD"; done
```

Do not use Bash arrays. When values may contain whitespace/newlines, use a safe line-oriented or temporary-file representation.

## 19. Quoting

Quote parameter expansions by default. Always use `"$@"` when forwarding arguments. Never use `$*` for exact argument preservation. Use `IFS= read -r`.

## 20. `printf` instead of `echo`

Prefer `printf` for program output. Static `echo` is not forbidden, but v3 should generally use `printf`.

## 21. Command substitution

Use `$(...)`, never backticks. Keep short substitutions on one line. Use `|| :` only when failure is genuinely expected and handled.

## 22. Strict mode

Use:

```sh
set -eu
```

Do not use `pipefail`; it is not POSIX. Do not rely on `set -e` alone for critical error handling. Use `"${VARIABLE:-}"` for legitimately optional variables.

## 23. Pipelines

Without `pipefail`, do not make correctness depend on failure detection in an earlier pipeline stage. Run critical intermediate commands separately when necessary.

## 24. Temporary files

Use `mktemp`. Clean up temporary resources. For non-trivial scripts use a cleanup trap; POSIX trap condition `0` is preferred over non-POSIX `EXIT`. Never use predictable `/tmp` names.

## 25. Comments

Comments explain why, safety assumptions, invariants, unusual Proxmox behavior, and non-obvious implementation choices. Do not narrate obvious syntax or keep dead code commented out.

## 26. Colour output

Use a consistent palette:

```text
cyan    headings / informational labels
blue    values / paths
green   success
yellow  warnings
red     errors
bold    important headings
```

Enable colours only when stdout is a terminal and respect `NO_COLOR`. Keep escape sequences inside colour helpers.

## 27. Dependency checks

Use a common `require_command`. When automatically installing packages, detect all missing packages first, report them together, elevate first, install them together where practical, and verify afterward. Do not run `apt-get update` when nothing needs installation.

## 28. Standalone-runtime policy

Every published top-level helper must be independently runnable after copying only that one `.sh` file. It must not require `lib/`, another project script, or its original repository directory at runtime.

The repository may keep canonical shared source under `lib/` for maintenance and generation, but release helpers embed that POSIX runtime directly. Wrapper helpers must likewise embed any companion implementation they require.

Never use `source`; canonical maintenance code remains POSIX shell. Script-specific business logic remains in the executable, while generated embedded shared-runtime sections are treated as generated content for style purposes.

## 29. High-level flow before implementation details

The script should be understandable from `setup()`, `main()`, and `end()` before reading helper bodies.

## 30. Pre-flight before mutation

Perform all reasonable checks before changing anything: source/destination existence and type, VMID state, guest locks/snapshots, storage mapping, volume collisions, free slots, shared references, HA/replication blockers, mount/open state, and destination capacity where practical.

Only then mutate.

## 31. Prefer reversible operations

Prefer rename over copy+delete where valid. Prefer snapshots for COW semantics. Cross-storage moves use copy + verify + delete. Never delete a source before destination verification.

## 32. Destructive operations

Verify the exact target, mount/open state, shared references, and caller intent before deletion. Use narrow deletion operations. Mount-point cleanup uses `rmdir`, never broad `rm -rf`.

## 33. Guest state

Storage/config mutation must explicitly define whether a guest may be running. Verify stopped state where required. Maintenance scripts should normally leave guests stopped unless restart is part of the contract.

## 34. Proxmox CLI before direct config editing

Prefer supported Proxmox commands where practical. Direct config editing requires a stopped guest where appropriate, a timestamped backup, the smallest possible edit, Proxmox parse validation, and post-edit reference verification.

## 35. Rollback

Plan rollback before the first mutation in multi-step operations. Rollback may restore configs, rename LVs back, restore firewall filenames, or remove newly created unattached volumes. Do not claim rollback succeeded unless its steps were checked.

## 36. Verification

Explicitly verify important postconditions: LV existence/nonexistence, VM config references, `pvesm` resolution, copy equality, mount removal, mapper cleanup, and config parsing.

## 37. LVM-thin warning suppression

Do not suppress all LVM stderr. Filter only known repetitive thin-pool advisory warnings. Other warnings and errors stay visible.

## 38. Full device paths

Prefer full LV paths at CLI boundaries:

```text
/dev/thinvg/vm-123-disk-0
```

Derive VG, LV, pool, canonical path, and Proxmox storage internally.

## 39. Canonical path handling

Remember `/dev/VG/LV` and `/dev/mapper/...` can identify the same device. Resolve canonical paths where appropriate and prefer metadata over guessing names.

## 40. Storage ambiguity

Never guess when multiple Proxmox storage definitions could match. Print candidates and stop before mutation.

## 41. Copy consistency

A changing source can yield an inconsistent block copy. Either require the source guest stopped, explicitly document crash consistency, or implement quiescing.

## 42. Sparse copying

Use sparse copying only where unwritten regions are guaranteed to read as zero, such as a newly created thin LV. Do not sparse-copy into regular LVs where skipped blocks could expose stale data.

## 43. Configuration backups

Direct Proxmox config edits use timestamped backups outside `/etc/pve`.

## 44. Manual follow-up warnings

When external references cannot safely be updated automatically, say so. VMID changes should remind the user to review backup jobs, ACLs, HA, replication, pools, hooks, monitoring, automation, external scripts, and other cluster references.

## 45. Output layout

Keep summaries compact. Do not place an empty line between every label/value pair. Use blank lines between conceptual groups.

## 46. User prompts

Avoid unnecessary prompts. Destructive tools may require explicit confirmation. Automated rollback should not pause for confirmation.

## 47. Error messages

Errors should explain what failed, which object was involved, and what to do next when practical. Avoid generic `ERROR: Failed.` messages.

## 48. Readability over cleverness

Do not use obscure shell tricks merely to reduce line count. Compact does not mean cryptic. Safety checks may be longer when that improves auditability.

## 49. Repetition versus abstraction

Abstract repeated logic when it improves readability or auditing. Good candidates include colour handling, elevation, dependency checks, LVM path resolution, Proxmox storage mapping, free-slot discovery, ownership checks, and warning filtering.

## 50. Reference privileged-script scaffold

```sh
#!/bin/sh
set -eu

############################################################
# SETUP / MAIN / END
############################################################

setup() {
    define_colours
    # Configuration
    PROJECT_VERSION="3.x.x"
    SCRIPT_VERSION="..."
    # Setup
    parse_arguments "$@"
    check_elevation
}

main() {
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    install_dependencies
    validate_environment
    validate_source
    validate_destination
    print_configuration
    perform_operation
    verify_result
}

end() {
    print_success "Operation completed successfully."
    print_results
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
```

## 51. Reference non-privileged scaffold

```sh
#!/bin/sh
set -eu

############################################################
# SETUP / MAIN / END
############################################################

setup() {
    define_colours
    PROJECT_VERSION="3.x.x"
    SCRIPT_VERSION="..."
    parse_arguments "$@"
    validate_environment
}

main() {
    collect_information
    print_results
}

end() {
    :
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
```

No self-elevation machinery when root is not required.


## Dry-run mode standard

Mutating v3 commands must accept `dryrun` and `--dryrun` as reserved common options.

Dry-run is a simulation mode, not a validation bypass:

- argument parsing and read-only preflight still run normally;
- real safety failures still fail;
- every command that would mutate host state is printed instead of executed;
- the simulated mutation returns success to the calling control flow;
- verification that depends on the simulated mutation is explicitly labeled as simulated rather than querying unchanged host state;
- nested project commands inherit dry-run mode;
- no temporary file, backup, mount point, mapper, LV, VM config, package, or other persistent/transient mutation should be created solely to implement dry-run;
- a final message must state that no modifying command was executed.

The POSIX v3 implementation must not rely on Bash `printf %q`; it should use a POSIX-safe command-rendering helper.


## 52. v3 rewrite acceptance checklist

A script is not ready for v3 until all applicable items pass:

- [ ] Uses `#!/bin/sh`.
- [ ] Passes `sh -n`.
- [ ] Contains no accidental Bash syntax.
- [ ] Uses `set -eu`.
- [ ] Has `setup`, `main`, and `end`.
- [ ] High-level behavior is understandable from `main()`.
- [ ] Short logical statements are compact.
- [ ] No trailing-backslash wrapping merely for line length.
- [ ] Supports `--help`.
- [ ] Supports `--version`.
- [ ] Root-requiring scripts detect elevation in `setup()`.
- [ ] Root-requiring scripts self-elevate at the start of `main()`.
- [ ] Original CLI arguments survive self-elevation via `"$@"`.
- [ ] Non-root scripts omit unnecessary self-elevation code.
- [ ] Every non-trivial function has an appropriate documentation form.
- [ ] Function names use lower snake case.
- [ ] Persistent globals use uppercase snake case.
- [ ] Function-private state is isolated or prefixed.
- [ ] No non-POSIX `local`.
- [ ] Expansions are quoted unless splitting is intentional.
- [ ] `printf` is preferred over `echo`.
- [ ] Foreseeable pre-flight checks occur before mutation.
- [ ] Destructive actions validate the exact target.
- [ ] Guest-state requirements are explicit.
- [ ] Proxmox CLI is preferred over direct config editing where practical.
- [ ] Direct config edits are backed up and verified.
- [ ] Multi-step mutations have rollback where practical.
- [ ] Critical postconditions are explicitly verified.
- [ ] LVM warnings are selectively filtered rather than hiding stderr.
- [ ] Storage ambiguity causes a safe refusal.
- [ ] Mount cleanup uses `rmdir`, not recursive deletion.
- [ ] Copy operations never delete the source before successful verification.
- [ ] Output is colourized only on a terminal and respects `NO_COLOR`.
- [ ] Warnings/errors go to stderr where appropriate.
- [ ] Final output clearly states what changed.
- [ ] Required manual follow-up is explicitly listed.
- [ ] The script is tested independently before being admitted to v3.

## 53. Guiding principle

The v3 style should be readable at three levels:

1. glance at `main()` and understand the operation;
2. read headings and function documentation and understand safety/data flow;
3. inspect function bodies and see compact POSIX shell implementing exactly what was promised.

> Explicit structure, compact statements, documented intent, conservative mutation, and verifiable results.
