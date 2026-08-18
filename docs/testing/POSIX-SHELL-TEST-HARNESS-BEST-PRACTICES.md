# POSIX Shell Test Harness Best Practices

This guide focuses on the shell-engineering side of a safe integration harness.

## 1. Use `/bin/sh` deliberately

Start with:

```sh
#!/bin/sh
set -eu
```

and avoid accidental Bash syntax.

Run every harness and helper through:

```sh
/bin/sh -n
```

as a static gate.

## 2. Do not rely on `set -e` to express test intent

`set -e` has context-sensitive behavior around:

```text
if
while
until
!
&&
||
functions invoked as conditions
```

Write explicit result handling for the operation under test.

Bad:

```sh
test_case && pass
```

Better:

```sh
set +e
test_case >"$LOG" 2>&1
status=$?
set -e
if [ "$status" -eq 0 ]; then
    pass
else
    fail
fi
```

## 3. Preserve the first failure

A test body should stop at the first failed assertion. Later commands can obscure the real cause or mutate a partially failed fixture.

Use a case runner that captures:

```text
case name
first failing command/status
stdout/stderr log
fixture identity
```

## 4. Empty output and failure are different states

A helper such as "find references" can legitimately return no lines.

Do not encode "empty result" as a failed function unless absence is truly an error.

## 5. End helpers with explicit status when appropriate

Under `set -e`, the last command in a function can accidentally become the function's contract.

If the function means "best-effort collect zero or more lines", make that clear:

```sh
collect_optional_data() {
    ...
    return 0
}
```

## 6. Keep diagnostics off captured data streams

If a function's stdout is machine-readable, warnings belong on stderr.

This avoids corrupting:

```sh
value="$(function)"
```

with human diagnostics.

## 7. Quote captured command arguments in logs

A dry-run renderer should make spaces and special characters unambiguous. In POSIX shell, do not depend on Bash `%q`.

Use a dedicated shell-quote helper.

## 8. Test `--help` and `--version` before environment prerequisites

CLI metadata should be callable without:

```text
root
Proxmox
LVM
existing VMIDs
```

This makes documentation generation and CI possible on non-Proxmox systems.

## 9. Treat usage text as testable output

For each public helper, test:

```text
--help exits 0
Usage line/section exists
usage snapshot matches expected documentation
```

If separate `.usage` files are shipped, compare them byte-for-byte with live `--help`.

## 10. Do not use undefined convenience helpers in test groups

A real test run failed because a group piped through:

```sh
trim
```

without sourcing a definition.

Harness groups should use only:

```text
POSIX built-ins
declared test-library helpers
explicitly required external commands
```

Static tests should detect references to unavailable project-only helpers.

## 11. Make prerequisite checks explicit

Before fixture creation:

```sh
for CMD in qm pct pvesm lvs lvcreate ...; do
    require_command "$CMD"
done
```

Do not discover a missing tool halfway through a destructive case.

## 12. Avoid brittle parsing when tools expose structured columns

Prefer:

```sh
partx --show --noheadings -o NR,START,SECTORS,TYPE
```

over parsing human-formatted prose.

But integration-test the exact option combination on the target platform.

## 13. Return-code expectations must be documented per test

A cancellation test expects non-zero.

A read-only lookup returning no matches may expect zero.

A negative/refusal test expects non-zero **and** unchanged state.

Do not infer all of these from one generic `assert_command_failed` helper unless its semantics are explicit.

## 14. Snapshot semantics, not timestamps

Avoid assertions like:

```text
file mtime changed
operation took at least N seconds
```

when the actual contract is:

```text
config changed from A to B
LV UUID stayed the same
bytes stayed the same
VM ended stopped
```

## 15. Keep fixture setup and case mutation separate

A group should establish a valid fixture before registering/running cases.

If setup fails, no case should be marked failed as though the helper had run.

Report setup failure distinctly.

## 16. Test cleanup helpers independently

Cleanup code is destructive code.

Write static or synthetic self-tests that prove:

```text
wrong identity -> refuse
unowned storage reference -> refuse
remaining guest -> block VG cleanup
pre-existing backup path -> preserve
```

## 17. Keep trap handlers minimal and deterministic

A signal/exit trap should call one well-defined emergency cleanup path.

Avoid complex control flow inside the trap itself.

The emergency path should be idempotent because it may run after partial setup.

## 18. Preserve result directories

Logs are more valuable than a perfectly empty `/tmp`.

Remove test resources, but retain:

```text
case logs
summary
baseline
after-state
diffs
run metadata
```

under a stable results directory.

## 19. Static coverage should reconcile public inventory

CI should fail when:

```text
a new public helper has no integration reference
a mutating helper has no dry-run immutability case
README lacks the helper
docs lack the helper
usage snapshot lacks the helper
test matrix lacks the helper
```

## Do not pre-run the API under test during fixture setup

If the product test is meant to evaluate a specific mutating API path, fixture setup should not depend on that same path when a safe independent fixture mechanism exists.

Bad test boundary:

```text
fixture setup -> pct set net0 ...
test case     -> project helper -> pct set net0 ...
```

If the first `pct set` fails, the helper was never tested.

Prefer:

```text
fixture setup -> seed stopped synthetic config directly
fixture check -> qm/pct config parses successfully
test case     -> project helper -> first qm/pct set mutation
```

This does not mean direct configuration editing is preferred for production helpers. It is a controlled test-fixture technique used on uniquely owned, stopped disposable guests to isolate the behavior under test.

## 20. Recommended shell harness checklist

- [ ] `/bin/sh -n` passes.
- [ ] No Bash-only constructs.
- [ ] Test runner captures first failure.
- [ ] Expected failures are handled explicitly.
- [ ] Empty successful results remain success.
- [ ] Diagnostics do not contaminate captured stdout.
- [ ] Every external prerequisite is checked.
- [ ] Fixture setup and case execution are distinct.
- [ ] Dry-run/refusal snapshots compare real state.
- [ ] Trap cleanup is idempotent.
- [ ] Cleanup helpers have their own regression tests.
- [ ] Help/version/usage are CI-testable without root.
- [ ] Public command inventory reconciles with docs/tests.

> A shell harness should be easier to reason about than the scripts it is testing.
