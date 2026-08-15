# Shell Test Harness Implementation Guide

This document focuses on implementing a safe shell-based integration-test harness.

It complements the higher-level Test System Design Guide by concentrating on shell control flow, result handling, logging, dry-run proof, fixture lifecycle, and failure semantics.

The examples target POSIX `/bin/sh` where practical.

---

## 1. Harness lifecycle

A group launcher should have a clear lifecycle:

```sh
setup "$@"
main "$@"
end
```

Conceptually:

```text
setup
    parse arguments
    define colours
    determine run mode
    detect elevation

main
    plan-only return, or
    elevate
    validate prerequisites
    capture baseline
    create fixture
    run cases

end
    cleanup
    compare baseline
    print summary
```

This makes failure boundaries obvious.

---

## 2. Plan-only by default

Use:

```text
TEST_RUN=false
```

unless `--run` is explicitly supplied.

The plan path must not:

```text
create directories;
create loop devices;
touch LVM;
register Proxmox storage;
create VMs.
```

It should only print what would be tested.

---

## 3. Elevate once

If the group requires root:

```text
detect elevation in setup;
self-elevate at the beginning of main;
preserve "$@" exactly.
```

Do not scatter `sudo` throughout fixture functions.

This makes the permission model easier to reason about and test.

---

## 4. Every test case runs in isolation

A test runner should execute each test function in a fresh strict subshell.

Conceptually:

```sh
(
    set -eu
    test_case
)
```

Capture its status outside the subshell.

This prevents:

```text
variable leakage;
trap leakage;
current-directory leakage;
set-option leakage;
failed commands being masked by caller syntax.
```

---

## 5. Do not call strict test functions directly in `if`

A subtle shell behavior learned during the Proxmox suite:

```sh
if test_function; then
    ...
fi
```

can alter `set -e` behavior inside `test_function`.

A failed command may not abort the function as expected.

Instead:

```text
run the case in its own strict subshell;
capture that subprocess status;
then update PASS/FAIL counters.
```

The test suite should include a regression test proving that a deliberate failed command stops the case before a later statement.

---

## 6. Keep the first real failure

A failed test log should show the command failure that caused the case to stop, not a later assertion produced after continuing.

This is one reason strict case subshells matter.

The failure report should answer:

```text
What was the first failing operation?
What did it print?
What fixture was active?
What state remains?
```

---

## 7. Return-code contracts must be explicit

Helpers should define whether empty output is success.

Example:

```text
find_other_references
```

A useful contract is:

```text
0 + lines     = lookup succeeded, matches found
0 + no lines  = lookup succeeded, no matches
nonzero       = lookup itself failed
```

Do not use a nonzero result merely because `grep` found nothing unless “nothing” is actually an error.

---

## 8. End successful helpers explicitly

Avoid accidental final-status bugs.

Risky:

```sh
dryrun_enabled && dryrun_summary
```

Safer:

```sh
if dryrun_enabled; then dryrun_summary; fi
return 0
```

The final command executed in a shell function determines its status unless an explicit `return` is used.

This is especially important under `set -e`.

---

## 9. Keep diagnostics off captured stdout

Functions whose stdout is data should emit informational text to stderr or not emit it at all.

For example:

```sh
path="$(resolve_volume "$volid")"
```

requires `resolve_volume` stdout to contain only the path.

Colour banners inside such a function will corrupt the data channel.

---

## 10. Use per-case logs

For every case:

```text
create deterministic log filename from case name;
redirect stdout and stderr into it;
print log automatically on failure;
print it on success only in --verbose mode.
```

This balances readability with complete evidence.

---

## 11. Sanitize log filenames

Case descriptions may contain:

```text
spaces
slashes
colons
```

Translate unsafe filename characters into a small safe set.

Do not use raw test descriptions as paths.

---

## 12. Maintain counters

At minimum:

```text
PASS
FAIL
SKIP
ANOMALY
```

An anomaly is not the same as a failed functional assertion.

Keeping it separate makes triage clearer while still allowing the group to fail overall.

---

## 13. SKIP is a first-class result

A skipped test should state why.

Examples:

```text
SKIP: no Linux bridge detected
SKIP: optional qemu-img feature unavailable
```

Do not silently omit cases.

Do not count unsupported prerequisites as PASS.

---

## 14. Dry-run state snapshots

Before dry-run, capture test-owned state.

Useful categories:

```text
test LVs
test VM configs
test storage stanzas
test files
test mounts
```

After dry-run, capture exactly the same representation and compare.

If different:

```text
write diff;
fail case;
do not proceed to real mutation for that case.
```

---

## 15. Snapshot only stable semantics

The dry-run state snapshot should avoid volatile information such as:

```text
timestamps;
device-mapper numeric IDs;
command-duration counters;
kernel transient ordering.
```

Otherwise a no-op dry-run may appear to mutate state.

Capture identifiers and configuration semantics instead.

---

## 16. Separate protected state from test-owned state

There are two distinct comparisons:

### Test-owned state

Used around dry-run:

```text
before dryrun == after dryrun
```

### Protected pre-existing state

Used around the entire sandbox:

```text
baseline before sandbox == after cleanup
```

Do not mix them.

---

## 17. Fixture setup should fail before mutation when possible

Before `pvcreate`:

```text
prove loop belongs to test backing file.
```

Before `vgcreate`:

```text
prove VG name unused.
```

Before `qm create`:

```text
prove VMID unused.
```

The more errors caught before mutation, the easier cleanup becomes.

---

## 18. Record resources immediately after creation

As soon as a mutating fixture step succeeds, append its identity to the ownership registry.

For example:

```text
vgcreate succeeded
    ↓
record VG ownership immediately
```

Do not wait until the whole fixture has been created.

If the next step fails, cleanup still knows about the object already created.

---

## 19. Cleanup should be idempotent

A cleanup function may be called:

```text
after success;
after failure;
from a signal trap;
after partial fixture creation.
```

Therefore each step should tolerate:

```text
object already absent;
previous step already cleaned it.
```

But idempotent does not mean permissive: ownership still must be proved before deletion.

---

## 20. Trap carefully

A top-level integration group may trap:

```text
0
HUP
INT
TERM
```

On trap:

```text
save original status;
disable traps;
run ownership-safe cleanup unless --keep;
exit with original status.
```

Avoid recursive trap invocation.

---

## 21. `--keep` should be narrowly scoped

Keeping a failed sandbox can be valuable for diagnosis.

But:

```text
allow --keep only on individual groups;
do not offer it on the all-groups launcher.
```

Otherwise one full run may leave many large sandboxes and storage definitions.

When keeping a sandbox, print:

```text
path;
run ID;
ownership marker;
manual cleanup warning.
```

---

## 22. All-groups launcher should isolate groups

Run group scripts as separate processes.

Benefits:

```text
group traps cannot affect launcher;
group variables cannot leak;
one group's shell options cannot alter another;
each group owns its lifecycle.
```

Continue to later groups even when one group fails, then return nonzero at the end.

This provides a complete failure picture in one run.

---

## 23. Coverage reconciliation

The static group should compare:

```text
set of executable project commands
```

with:

```text
set listed in TEST-MATRIX.md
```

Fail when a command is missing from coverage documentation.

A growing project should not silently outgrow its suite.

---

## 24. Regression tests for harness defects

When the harness itself fails, add a regression case.

Examples learned during the Proxmox work:

```text
strict runner stops at first failed command;
empty reference lookup returns success;
dryrun_summary returns success in normal mode;
storage set-order canonicalization compares equal;
dryrun keyword works before and after normal options.
```

These tests are cheap and prevent rediscovery.

---

## 25. Avoid process-substitution surprises in regression tests

Background process substitution can hide errors from the parent shell.

A regression test should prefer simple foreground execution when validating return status.

If process substitution is unavoidable, inspect its behavior explicitly.

Do not let a background diagnostic be mistaken for a passing test.

---

## 26. Quote original CLI arguments

When self-elevating or forwarding to child commands:

```sh
"$@"
```

must be preserved exactly.

Do not rebuild the command line from `$*`.

This matters even more in a test harness because paths often contain temporary namespaces and future cases may include spaces or punctuation.

---

## 27. Dry-run propagation

If project commands call other project commands, dry-run mode must propagate.

The harness should include nested-wrapper cases so it can prove:

```text
parent dryrun
    ↓
child dryrun
    ↓
grandchild dryrun
```

without an inner command accidentally performing a mutation.

---

## 28. Keep shell-escaped dry-run output

Printed mutation commands should be shell-escaped enough to audit unambiguously.

The point is not necessarily to make the transcript executable.

The point is to distinguish:

```text
one argument containing spaces
```

from:

```text
several separate arguments.
```

For POSIX v3, use a dedicated POSIX-safe quoting helper.

---

## 29. Test assertions should verify one thing clearly

Good:

```text
expected LV exists
old LV absent
VM slot contains exact volid
export file is readable by qemu-img
```

Weak:

```text
command output contains "success"
```

Avoid assertions that merely repeat the application's own success message.

---

## 30. Prefer metadata checks over timing

Do not use arbitrary sleeps as the main verification mechanism.

Prefer polling a deterministic state when asynchronous behavior must settle.

For most Proxmox/LVM CLI operations used in this suite, the command's return generally means the metadata transaction has completed.

---

## 31. Failure output should include fixture identity

A failed case should make it easy to locate the disposable objects.

Useful context:

```text
TEST_RUN_ID
VMID
VG
storage ID
sandbox path
result directory
```

This matters when cleanup refuses because ownership changed.

---

## 32. Keep result directories after cleanup

Fixture cleanup and evidence cleanup are separate concerns.

Remove disposable infrastructure, but retain:

```text
logs
state snapshots
diffs
findings
```

under a persistent result root.

---

## 33. Harness acceptance checklist

- [ ] launcher is plan-only by default;
- [ ] `--run` is explicit;
- [ ] root elevation preserves CLI arguments;
- [ ] each case executes in a fresh strict subshell;
- [ ] first failure stops the case;
- [ ] valid empty results return success;
- [ ] helper success status is explicit;
- [ ] case stdout/stderr is logged;
- [ ] PASS/FAIL/SKIP/ANOMALY are separate counters;
- [ ] dry-run state is compared;
- [ ] fixture ownership is recorded immediately;
- [ ] cleanup is idempotent and ownership-checked;
- [ ] traps preserve original status;
- [ ] all-groups runner isolates groups;
- [ ] coverage matrix is reconciled;
- [ ] known harness defects have regression tests.

---

## 34. Guiding principle

A shell integration harness should be easier to reason about than the software it tests.

If the harness uses clever control flow, ambiguous return conventions, broad cleanup patterns, or hidden state, it becomes another source of system risk.

Prefer explicit lifecycle, explicit ownership, explicit result status, and explicit evidence.
