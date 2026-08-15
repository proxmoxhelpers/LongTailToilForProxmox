# Style Profiles, Exceptions, and Utilitarian Forms

The POSIX Shell Programming Style Guide defines the **default style**, not a mechanical requirement to apply every rule to every construct.

The goal is code that is easy to scan, internally documented, compact without becoming cryptic, easy to audit, and consistent across the project.

A rule may be relaxed when following it would make a specific piece of code less readable, less efficient, or artificially verbose. Exceptions should not be ad hoc: functions and code sections should fit one of the sanctioned profiles below.

> Relax ceremony before relaxing clarity, safety, or predictability.

## 1. Default profile — standard function

Use for substantive validation, LVM operations, Proxmox config changes, storage resolution, mounting, copying, verification, rollback, destructive operations, and other non-obvious behavior.

Use the full function documentation block. When uncertain, use this profile.

## 2. Compact helper profile

Tiny helpers may use reduced documentation.

```sh
# trim
# Removes leading and trailing whitespace from stdin.
trim() { sed 's/^[[:space:]]*//;s/[[:space:]]*$//'; }

# require_command COMMAND
# Exits if COMMAND is unavailable.
require_command() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }
```

Use only when the helper has one narrow, obvious purpose and no hidden side effects.

## 3. Trivial wrapper profile

A function that only gives a meaningful name to one command may be extremely compact:

```sh
# stop_vm VMID
stop_vm() { qm stop "$1"; }

# get_vm_status VMID
get_vm_status() { qm status "$1" 2>/dev/null | awk '{ print $2 }'; }
```

The wrapper is justified by readability of the caller, not by eliminating duplicate code.

## 4. Predicate profile

Simple Boolean functions may be almost self-documenting:

```sh
is_lvm_volume() { lvs "$1" >/dev/null 2>&1; }
```

Contract:

```text
0 = true
nonzero = false
```

Predicate names should begin with `is_`, `has_`, or `can_` where appropriate.

## 5. Stub / no-op profile

Intentional stubs and lifecycle no-ops may be minimal:

```sh
end() { :; }
```

or:

```sh
# Hook reserved for future cleanup.
cleanup_optional_state() { :; }
```

Use `:` rather than an empty body.

## 6. Adapter profile

Functions that only adapt one interface to another may remain compact:

```sh
# mount_vm_disk VMID SLOT [mount arguments...]
mount_vm_disk() {
    mvd_path="$(resolve_vm_disk_path "$1" "$2")"
    shift 2
    exec "$SCRIPT_DIR/mount-vm-drives.sh" "$mvd_path" "$@"
}
```

If an adapter gains policy, complex validation, mutation, or fallback behavior, it becomes a standard function.

## 7. Hot-path / performance profile

Performance-sensitive code may relax normal decomposition and formatting rules when extra processes, subshells, pipelines, or function calls materially hurt performance.

Typical cases:

- loops over thousands of LVs;
- large Proxmox config scans;
- filesystem scans;
- repeated external command invocation;
- streaming transformations.

This profile permits combined `awk`, fewer helper calls, fewer subshells/command substitutions, longer functions, and denser loop bodies.

It may not weaken validation, quoting, destructive checks, rollback, or final verification.

## 8. Parser / transformer profile

Text parsers may naturally be denser than business logic.

Examples include `awk` parsers, `sed` transformations, config scanners, volume-name extraction, and `storage.cfg` parsing.

The shell wrapper should explain the parser contract. Internal parser lines only need comments when their logic is unusual.

## 9. Generated-content profile

Functions that primarily emit configuration or scripts may use large here-documents:

```sh
create_config() {
    cat > "$CONFIG" <<EOF
...
EOF
}
```

Normal shell formatting rules do not apply inside generated content.

## 10. Transaction profile

Dangerous multi-step operations should generally be **more explicit**, not more compact.

Examples include VMID changes, cross-VG moves, disk replacement, interdependent LV renames, disk deletion, and direct Proxmox config rewrites.

Transaction code may intentionally use explicit intermediate variables, separate verification steps, longer functions, phase comments, and rollback bookkeeping.

Do not compress transactions into clever command chains.

## 11. Lifecycle profile

`setup`, `main`, and `end` do not require documentation blocks because their roles are defined globally by the style guide.

Very obvious phase functions called directly from `main()` may use a short description when their contract is clear.

## 12. Error-handler and trap profile

Cleanup, rollback, signal, and trap handlers may break normal function conventions when necessary to preserve exit status or remain safe under failure.

Correct failure handling takes precedence over compact style.

## 13. Library-private helper profile

Small, stable primitives in `lib/common.sh` may use compact documentation.

Public or complex library functions still use full documentation.

```text
primitive helper       -> compact documentation
shared policy function -> full documentation
```

## 14. Deliberate inline implementation

Not every repeated-looking operation needs a function.

Keep code inline when it is used once, extraction would create a vague helper, the inline form is immediately understandable, or moving it elsewhere would force needless navigation.

## 15. Performance before abstraction

Do not introduce process-heavy abstractions merely for aesthetic consistency.

In shell, external commands, subshells, pipelines, command substitutions, and repeated `qm`/`pvesm`/`lvs` calls are relatively expensive.

Collect information once and reuse it when practical. Prefer one `lvs` query returning several fields over many separate queries when the data belongs together.

## 16. Exception hierarchy

When relaxing a rule, use this order:

1. Safety must remain unchanged.
2. Correctness must remain unchanged.
3. The operation must remain auditable.
4. Intent must remain obvious.
5. Consistency should be preserved where useful.
6. Ceremony may then be reduced.

It is acceptable to relax documentation ceremony, variable-prefix ceremony, function extraction, section ceremony, or formatting when those add noise.

It is not acceptable to relax pre-flight checks, quoting, collision checks, mount/open checks, rollback where required, post-operation verification, or destructive-action boundaries merely to make code shorter.

## 17. Exception visibility

Ordinary use of a sanctioned profile does not require an explanatory comment.

For genuinely unusual deviations, add a short engineering-reason comment:

```sh
# Keep this as one awk process; this runs once per LV across potentially thousands of volumes.
awk '...' "$INPUT"
```

## 18. Avoid style-lawyering

Do not:

- create meaningless helper functions;
- add verbose doc blocks around self-evident one-line helpers;
- introduce subshells solely for naming purity;
- split fast parsers into many subprocesses;
- add empty sections;
- add comments that restate obvious syntax;
- force every function into identical shape;
- reject clear code merely because it looks different.

Consistency should reduce cognitive load, not increase it.

## 19. Choosing a function profile

```text
Does it mutate important state or implement policy?
    -> Standard or Transaction profile

Is it a complex parser or text transformer?
    -> Parser / Transformer profile

Is it performance-sensitive?
    -> Hot-path profile

Is it only adapting one interface to another?
    -> Adapter profile

Is it a boolean test?
    -> Predicate profile

Is it a tiny reusable primitive?
    -> Compact Helper profile

Is it intentionally empty?
    -> Stub / No-op profile

Is it primarily emitting structured content?
    -> Generated-content profile

Otherwise:
    -> Standard profile
```

## 20. Acceptance principle

The v3 review should not ask:

> Did this script obey every formatting rule mechanically?

It should ask:

> Is every deviation from the default style clearly one of the sanctioned forms, and does the result remain compact, understandable, safe, and internally documented?

The project should have a recognizable structural language without forcing every piece of code into the same shape.

> Tight where code is simple, explicit where operations are dangerous, dense where performance demands it, and documented wherever understanding would otherwise require reverse-engineering.


## Dry-run behavior is not a style exception

Dry-run safety is part of command semantics, not optional formatting ceremony. A sanctioned compact/performance/parser profile may change how dry-run is implemented internally, but it may not weaken the rule that modifying operations are printed rather than executed and mutation-dependent verification is explicitly simulated.
