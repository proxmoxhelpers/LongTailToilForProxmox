# POSIX Shell Programming Style Guide — Proxmox LVM Tools v3

This guide defines the coding style for the v3-era Proxmox LongTail Toil shell helpers and their continued maintenance.

The goals are to make every script easy to scan, internally documented, compact without becoming cryptic, conservative around destructive operations, and understandable independently even when common helpers are shared.

This guide defines style and maintenance conventions. Material behavior changes should still be reviewed and tested per helper rather than introduced as an unvalidated bulk conversion.

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

Every public executable should make the lifecycle visible immediately. Except for the shebang, `set -eu`, and banner/documentation comments, `setup()` should be the first function whenever practical.

Preferred structure:

```sh
#!/bin/sh
set -eu

############################################################
# LIFECYCLE
############################################################

# setup [ARGS...]
# Call: setup "$@"
setup() {
    # User-modifiable defaults / command defaults first.
    MODE="hot"
    TARGET_BUS="scsi"

    # Version and script state.
    PROJECT_VERSION="3.x.x"
    SCRIPT_VERSION="..."

    define_colours
    parse_arguments "$@"
    check_elevation
}

# main [ARGS...]
# Call: main "$@"
main() {
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    validate_environment
    perform_operation
    verify_result
}

# end
# Call: end
end() {
    print_success "Completed."
}

# usage
# Call: usage
usage() {
    ...
}

############################################################
# IMPLEMENTATION HELPERS
############################################################

...

############################################################
# START
############################################################

setup "$@"
main "$@"
end
```

`usage()` should preferably be the function immediately after `end()`.

Do not put implementation helper functions before the lifecycle merely because `setup()` calls them. POSIX shell parses all function definitions before the final lifecycle invocation, so helpers may be defined later.

Top-level executable code should be limited to the final lifecycle calls. A rare, justified exception is a safe interpreter directive such as:

```sh
set -eu
```

or a truly necessary constant/documentation banner that must exist before function definitions.

## 4. Meaning of setup, main, and end

`setup()` performs one-time preparation: defaults, versions/state initialization, colours, argument parsing, environment detection, and elevation detection when required.

User-modifiable defaults and command defaults belong at the **top of `setup()`**, before helper calls. This makes the operator-adjustable behavior visible without searching through implementation code.

`setup()` must not perform privileged mutations before the elevation gate.

`main()` expresses the operation in high-level steps. Someone reading only `main()` should understand the procedure:

```sh
main() {
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
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

`end()` performs normal completion work: summaries, result paths, cleanup and follow-up reminders. Do not use it as a second `main()`.

The lifecycle order near the top of the file is:

```text
setup
main
end
usage
```

unless a specific script has a strong reason to deviate.

## 5. Privilege detection and self-elevation

POSIX variable names cannot contain dots, so conceptual `app.elevated` becomes:

```sh
APP_ELEVATED
```

Its values are exactly `true` or `false`.

For root-requiring scripts:

1. `setup()` calls `check_elevation`.
2. `check_elevation` silently sets and exports `APP_ELEVATED`.
3. `main()` checks `APP_ELEVATED` before privileged work.
4. If elevation is required and missing, the script reports that fact and re-executes itself through `sudo` when appropriate.
5. Original CLI arguments are preserved with `"$@"`.

Do **not** print routine success chatter such as:

```text
[OK] Elevation: running as root.
```

Being already elevated is not an event that needs reporting. Mention elevation only when the script is not elevated and the requested operation requires elevation.

Reference:

```sh
# check_elevation
# Call: check_elevation
# Sets APP_ELEVATED silently.
check_elevation() {
    if [ "$(id -u)" -eq 0 ]; then APP_ELEVATED="true"
    else APP_ELEVATED="false"; fi
    export APP_ELEVATED
}

# self_elevate ARGS...
# Call: self_elevate "$@"
# Re-executes the script with root privileges when required.
self_elevate() {
    command -v sudo >/dev/null 2>&1 || die "Root privileges are required and sudo is unavailable."
    warn "Root privileges are required; re-running with sudo..."
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

Every public script has `usage()` and should include, where applicable:

```text
NAME / VERSION
USAGE
DESCRIPTION
ARGUMENTS
OPTIONS
EXAMPLES
NOTES
```

`usage()` should preferably appear immediately after `end()` near the top of the script.

`--help` must work without root and without requiring the target VM/storage/LV to exist.

Usage errors exit `2`; runtime failures normally exit `1`.

When the repository ships a `.usage` snapshot, it should be generated from live `--help` output and tested byte-for-byte so documentation cannot drift.

## 8. Section organization

Use banners such as:

```sh
############################################################
# VALIDATION / PRE-FLIGHT
############################################################
```

Preferred order:

```text
LIFECYCLE
  setup
  main
  end
  usage

EMBEDDED / SHARED RUNTIME
COMMAND LINE PARSING HELPERS
PRIVILEGE / DEPENDENCIES
VALIDATION / PRE-FLIGHT
HIGH LEVEL TASKS
DOMAIN-SPECIFIC OPERATIONS
VERIFICATION
RESULTS / DIAGNOSTICS
GENERAL HELPERS
START
```

The lifecycle is intentionally above implementation helpers. Do not move it down merely to satisfy declaration-before-use habits from other languages.

Do not create empty sections.

## 9. Function documentation

Every non-trivial function gets a documentation block immediately before it.

A function that accepts call arguments must include its call syntax in that block. Either the full form:

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

or a sanctioned compact form:

```sh
# resolve_volume_path STORAGE_VOLUME
# Call: resolve_volume_path STORAGE_VOLUME
# Prints the resolved path or returns non-zero.
resolve_volume_path() (
    rvp_volume="$1"
    pvesm path "$rvp_volume" 2>/dev/null
)
```

is acceptable.

Do not make a reader reverse-engineer `$1`, `$2`, or `"$@"` to learn how an internal helper is called.

Required fields for the full form are Description, Usage, Arguments, Output, and Returns. Sanctioned relaxed forms are defined in the companion style-profiles document.

## 10. Function spacing

Use exactly one blank line between top-level function definitions. Avoid decorative blank lines inside functions. Comments should explain intent, risk, or invariants.

## 11. Function names

Use lower snake case and verb-first names. Predicates normally begin `is_`, `has_`, or `can_`. Requirement functions begin `require_`. Mutating functions should name the mutation clearly.

## 12. Variable naming

Script-wide persistent state uses uppercase snake case. Framework state uses `APP_`.

POSIX shell has no standard `local`. Function scratch variables therefore use a **function-derived lowercase prefix** so accidental global leakage is recognizable and collisions are unlikely.

The prefix may be the full function name or a consistent abbreviation/initialism:

```sh
require_qemu_vm() {
    rqv_id="$1"
}

set_destination_boot_first() {
    sdbf_vm="$1"
    sdbf_slot="$2"
}
```

Do not mix unrelated prefixes inside one function.

### Function-persistent state

A variable deliberately intended to retain function-specific state after the function returns, until the next call to that function, uses a leading underscore before the function prefix:

```text
_fn_cached_value
_RQV_CachedValue
```

Capitalization is optional, but naming must be consistent within the function's scope.

Do not use the underscore convention merely because POSIX shell happens to leak ordinary scratch variables globally. Scratch variables are still considered private and must not be consumed after return.

### Pseudoarrays and pseudoobjects

POSIX shell does not support array syntax and does not permit literal variable names containing `[` `]` or `.`. Therefore notation such as:

```text
fn_myarray[X]
fn_myarray.lbound
fn_myarray.ubound
fn_myarray.count
fn_myobject.property
```

is a **conceptual naming model**, not literal POSIX assignment syntax.

When a pseudoarray is genuinely needed, its documented model uses:

```text
fn_myarray[X]       element X
fn_myarray.lbound   lower bound, implicitly 0 unless stated otherwise
fn_myarray.ubound   highest valid index
fn_myarray.count    element count
```

When a pseudoobject is useful, document fields as:

```text
fn_myobject.property
```

In executable POSIX shell, prefer representations that preserve the same structure safely:

```text
newline-delimited files
pipe-delimited records
function-prefixed scalar variables
subshell output
```

For example, a conceptual:

```text
plan[0].old
plan[0].new
plan.count
```

may be stored as one record per line in a temporary plan file rather than encoded into dynamically named shell variables.

Where the implementation language actually provides real arrays or objects, prefer those language-native types over pseudoarrays/pseudoobjects. For this project's POSIX `/bin/sh` helpers, there are no standard language-native arrays.

Caller-visible output variables remain uppercase and must be documented.

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


## 52. Exit-status contracts are part of the interface

Every public operation must define what success and failure mean.

Examples:

```text
requested mutation completed       -> 0
read-only lookup found no matches  -> 0 when "none" is valid data
user cancelled destructive action  -> non-zero
preflight refused unsafe state      -> non-zero
verification failed                 -> non-zero
rollback only partially succeeded   -> non-zero
```

Do not print "Cancelled", "Skipped", or "Failed" and then accidentally return 0 because the last command happened to succeed.

For helper functions, do not let an incidental final command silently define the function's return contract.

## 53. Avoid `set -e` short-circuit guard traps

Under `set -e`, do not write a negative-existence guard as:

```sh
lvs "$TARGET" >/dev/null 2>&1 && die "Target already exists."
```

A false left-hand command can escape as the function status depending on shell context.

Prefer an explicit conditional:

```sh
if lvs "$TARGET" >/dev/null 2>&1; then die "Target already exists."; fi
```

The same rule applies to other "command succeeded, therefore fail" guards.

Functions that intentionally accept empty/no-match results should explicitly return 0 after collecting them.

## 54. Distinguish config-reference removal from resource deletion

With Proxmox, a CLI option that removes a config key can also free its backing resource.

Do not assume:

```sh
qm set "$VMID" --delete unused0
```

is equivalent to "remove only this line from the VM config".

Before using any Proxmox deletion primitive, document whether it can:

```text
remove a config reference;
free storage;
destroy a snapshot;
detach a runtime device;
or perform more than one of these.
```

If a transaction must preserve the backing LV, use a proven config-only update path and independently verify the LV still exists by UUID.

## 55. Use durable identity across renames

Names and paths are mutable labels.

Before `lvrename`, capture:

```sh
LV_UUID="$(lvs --noheadings -o lv_uuid "$LV" | trim)"
```

After rename, verify the object by UUID rather than comparing against a stale old path.

For multi-step rename transactions, track:

```text
original name
temporary name
final name
LV UUID
```

Do not use a pre-rename path as the durable identity of the object.

## 56. Rollback primitives must be conservative

Rollback is not permission to use broader operations than the forward path.

A rollback sequence must not delete a config key using a primitive that can free the very LV being restored.

Before the first mutation, define:

```text
what constitutes a committed result;
what objects are recoverable before commit;
which identities prove those objects;
which operations can restore them without deletion side effects.
```

If rollback cannot prove an object's identity, stop and preserve recoverable state rather than guessing.

## 57. Treat slots, volume IDs, LV paths and UUIDs as different value classes

Do not blur:

```text
scsi0
local-lvm:vm-123-disk-0
/dev/pve/vm-123-disk-0
vm-123-disk-0
<LV UUID>
```

Give variables names that reveal the class:

```text
SOURCE_SLOT
SOURCE_VOLID
SOURCE_PATH
SOURCE_LV_NAME
SOURCE_LV_UUID
```

Convert explicitly at boundaries. This reduces accidental comparison of a storage ID with a path or a pre-rename path with a post-rename object.

## 58. Use authoritative metadata from the owning subsystem

Ask LVM for LVM metadata.

For example, use `lvs -o lv_size` to determine an LV's configured size rather than assuming `blockdev --getsize64` is valid for every template/base activation state.

Use `blockdev` for block-device interface properties when an active device interface is what matters.

Likewise:

```text
qm/pct config -> configured guest state
pvesm path    -> Proxmox storage resolution
lvs           -> LV identity/size/pool/origin
findmnt       -> mount truth
dmsetup       -> device-mapper open state
```

Prefer the subsystem's own metadata over inference from names.

Existence in LVM metadata does not guarantee an active block-device node. When a helper must perform block I/O against an inactive LV:

```text
1. record that the LV was originally inactive;
2. activate it with `lvchange -ay`;
3. verify the block device exists;
4. perform and verify the I/O;
5. deactivate it with `lvchange -an`;
6. make cleanup restore inactivity after any intermediate failure.
```

Never deactivate a source that was already active before the helper ran, and do not change LV permission metadata merely to obtain a device node.

## 59. Device-bus changes require option compatibility

Disk options are not universally valid across:

```text
scsi
virtio
sata
ide
```

When moving a configured disk value to another bus:

1. parse the existing options;
2. preserve compatible options;
3. remove or transform incompatible options;
4. warn about any option that is dropped;
5. validate the resulting config with Proxmox.

For example, `iothread=1` may be valid on SCSI/VirtIO but invalid on SATA/IDE.

Do not mechanically copy a full option string between buses.

## 60. Guest state semantics must include device topology

`running`, `paused`, and `stopped` are not enough to determine whether a hot-unplug is safe.

For SCSI operations also consider:

```text
controller model;
whether the target disk is the only disk on that controller;
whether removing the disk causes controller removal;
whether Proxmox supports that runtime transition.
```

A paused VM can still reject disk removal because the operation implies hot-unplugging `scsihw0` or `virtioscsi0`.

Refuse unsupported topologies before mutation and recommend `stop`/`restart` rather than bypassing Proxmox runtime state with direct config editing.

## 61. Direct config editing is not a live-device substitute

Direct `/etc/pve` editing is acceptable only for narrowly understood config-only changes where the supported CLI would have unwanted side effects and runtime state is not being bypassed.

Never edit a running/paused guest config to simulate successful hot-unplug when QEMU may still have the device open.

When direct editing is justified:

```text
make a backup;
edit the smallest exact key/value;
validate config parsing;
verify the intended storage object separately;
verify no runtime ownership assumption was violated.
```

## 62. External utility option combinations require target-host testing

Shell syntax can be valid while a utility invocation is invalid.

Example discovered during integration testing:

```sh
partx --show --raw ...
```

was rejected because those modes were mutually exclusive on the target host.

Use the smallest option set needed and add a regression test for every target-host incompatibility discovered.

Do not infer utility compatibility from shell parsing alone.

## 63. Separate partition intent from content format

Partition-table metadata and actual filesystem/container signatures are independent facts.

Report separately:

```text
TABLE_HINT
CONTENT_FORMAT
```

A broad table type such as "Linux filesystem" can legitimately contain ext4, Btrfs, XFS, or LUKS. A definite incompatible relationship should be called out rather than collapsed into one field.

Read-only inspection should avoid mounts/mappers where offset probing can answer the question safely.

## 64. Help and usage are stable public interfaces

Every public helper must support:

```sh
./helper.sh --help
./helper.sh --version
```

before privilege checks and operational preflight.

`--help` must:

```text
return 0;
contain a Usage section/line;
describe required selectors/keywords;
state destructive/state behavior that materially affects use;
work on a non-Proxmox/non-root documentation host.
```

If usage snapshots are shipped, generate them from live `--help` output and test them for exact equality.

## 65. Keep test-only dependencies explicit

Integration groups must not accidentally depend on helper functions that happen to exist in project scripts but are not loaded by the test harness.

If a test uses:

```text
trim
assert_lv_exists
create_test_vm
```

that function must be defined by the sourced test library or implemented locally.

Static coverage should reject known undefined convenience helpers.

## 66. Test harness cleanup is production-grade destructive code

Cleanup code follows the same style rules as product code:

```text
exact identity before deletion;
narrow ownership proof;
dependency-ordered teardown;
no broad wildcard deletion;
explicit refusal on uncertainty;
post-cleanup verification.
```

A trap path must still capture protected after-state and compare it to the baseline.

Do not optimize cleanup for "always empty afterward". Optimize it for "never delete an unproven object".


## 67. v3 rewrite acceptance checklist

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
- [ ] Success, cancellation, refusal and verification-failure exit statuses are explicit.
- [ ] No `cmd && die` / equivalent `set -e` guard trap remains.
- [ ] Config-reference deletion is distinguished from backing-resource deletion.
- [ ] LV UUID is used as durable identity across renames where needed.
- [ ] Rollback does not use a more destructive primitive than the forward path.
- [ ] Slot, volume ID, LV path/name and LV UUID variables are not conflated.
- [ ] Metadata comes from the authoritative subsystem when practical.
- [ ] Temporary LV activation preserves the original active/inactive state and does not alter LV permission metadata.
- [ ] Cross-bus disk option compatibility is validated.
- [ ] Pause/hotplug behavior preflights controller topology.
- [ ] Direct config edits never bypass a failed live-device transition.
- [ ] External utility option combinations have real target-host coverage when safety-relevant.
- [ ] `--help` works before root/environment preflight and returns 0 with a Usage section.
- [ ] `setup()`, `main()`, `end()`, then `usage()` appear at the top unless a documented exception applies.
- [ ] User-modifiable/default values are initialized at the top of `setup()`.
- [ ] Routine root success output is suppressed; elevation is reported only when required and missing.
- [ ] Every argument-taking function documents its call syntax.
- [ ] Function scratch variables use one function-derived prefix consistently.
- [ ] Function-persistent private state uses a leading underscore before the function prefix.
- [ ] POSIX pseudoarray/pseudoobject notation is conceptual only; executable storage uses POSIX-safe representations.
- [ ] Any shipped usage snapshot matches live `--help`.
- [ ] Test/cleanup code uses only explicitly available helpers and fail-closed ownership checks.

## 68. Guiding principle

The v3 style should be readable at three levels:

1. glance at `main()` and understand the operation;
2. read headings and function documentation and understand safety/data flow;
3. inspect function bodies and see compact POSIX shell implementing exactly what was promised.

> Explicit structure, compact statements, documented intent, conservative mutation, and verifiable results.
