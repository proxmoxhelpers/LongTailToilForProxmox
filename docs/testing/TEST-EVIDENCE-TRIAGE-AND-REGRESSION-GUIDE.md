# Test Evidence, Triage, and Regression Guide

A system-test suite is only as useful as its failure evidence.

This document describes how to capture, classify, investigate, and convert failures into durable regression coverage.

It is based on the iterative Proxmox LVM Tools test runs in which several apparent product failures were ultimately traced to harness behavior, semantic comparison issues, or invalid verification assumptions.

---

## 1. Preserve evidence before changing code

When a full run fails, do not immediately patch the first suspicious line.

Preserve:

```text
console output;
per-case logs;
baseline snapshots;
after snapshots;
dry-run before/after snapshots;
anomaly diffs;
project version;
test-suite version;
host/environment notes.
```

The first question is:

> What actually happened?

not:

> What change makes the test green?

---

## 2. Classify every failure

Useful categories are:

```text
A. product/command bug
B. test assertion bug
C. fixture/setup bug
D. cleanup bug
E. baseline/comparator bug
F. test-runner/control-flow bug
G. environment/prerequisite issue
H. concurrent external change
I. unsupported scenario
```

Record the category after investigation.

This prevents the project from accumulating fixes that merely hide test defects.

---

## 3. Start with the first failing operation

A reliable case runner should stop at the first failed command.

Read:

```text
the first nonzero operation;
its stdout/stderr;
the state immediately before it;
the fixture identifiers.
```

Later assertion failures are often secondary symptoms.

---

## 4. Compare console output with persistent logs

Verbose console output is useful, but persistent logs are authoritative for detailed review.

Check whether:

```text
the console omitted non-verbose passing details;
stderr appeared in an unexpected place;
a process-substitution/background error was not reflected in case status.
```

The Proxmox suite found an `$2: unbound variable` diagnostic this way even though the containing regression case passed.

---

## 5. Treat anomaly diffs as evidence, not verdicts

A protected-state diff means:

```text
the before/after representations differ.
```

It does not automatically mean:

```text
the application corrupted state.
```

Investigate whether the difference is:

```text
semantic;
serialization-only;
ordering-only;
timestamp-only;
concurrent external activity.
```

Then improve the comparator without masking meaningful changes.

---

## 6. Canonicalization should be narrowly justified

When ignoring a representation difference, document why it is semantically irrelevant.

Example:

```text
Proxmox content images,rootdir
```

and:

```text
Proxmox content rootdir,images
```

represent the same set.

Therefore splitting and sorting `content` members is justified.

By contrast, normalizing all whitespace and sorting every config line could accidentally hide meaningful structure.

---

## 7. Verify assumptions about underlying tools

A test can reveal that an assumed command contract is wrong.

Important example:

```text
pvesm path VOLID
```

was assumed to prove existence.

Real integration showed that it may synthesize a path after deletion.

The correct response is not to weaken the test.

The correct response is to replace the invalid assumption with stronger verification:

```text
storage listing;
backing path existence;
LVM metadata.
```

---

## 8. Distinguish output from state

A command printing:

```text
success
```

does not prove success.

A command returning `0` does not necessarily prove the intended state exists.

A test should ask the system independently.

Examples:

```text
qm config
pvesm list
lvs
findmnt
mountpoint
qemu-img info
cmp
filesystem path checks
```

---

## 9. Look for shell-status bugs

System administration scripts often fail because successful work ends with an unintended nonzero status.

Typical patterns:

```sh
predicate && optional_action
grep ...
test ...
```

as the final command in a function.

If the predicate is false in a normal successful situation, the function may return failure.

Check helper return contracts whenever:

```text
the operation visibly completed;
the script nevertheless exits nonzero.
```

---

## 10. Look for context-dependent `set -e`

If a test seems to ignore a failed command and continue, inspect how the test function is invoked.

Calling a function in:

```sh
if function; then
```

or other conditional contexts can change errexit behavior.

The fix belongs in the harness control flow, not in every individual test function.

---

## 11. Reproduce the smallest failing case

Once the failure category is understood, reduce it.

Examples:

```text
one LV rather than full VM workflow;
two synthetic storage.cfg files rather than full Proxmox setup;
one helper sourced in a shell rather than the entire command;
one empty-reference fixture rather than many guest configs.
```

A small reproduction is easier to turn into a regression test.

---

## 12. Add regression coverage before forgetting the bug

Every discovered root cause should become a stable regression test when practical.

The Proxmox suite added cases for:

```text
dryrun_summary returning success outside dry-run;
empty-reference lookup being a successful empty result;
strict test runner stopping on the first failure;
storage set-member order canonicalizing identically.
```

A regression test should target the root cause, not merely the original symptom.

---

## 13. Keep run findings as versioned documents

For important integration milestones, write a short findings document containing:

```text
tested version;
headline result;
failure summary;
root causes;
code/harness corrections;
what passed;
what remains untested.
```

This creates a technical history explaining why unusual checks exist.

It is especially useful before a major rewrite.

---

## 14. Use previous green releases as behavioral baselines

Once a full integration suite passes cleanly:

```text
freeze that release;
keep its result evidence;
treat it as the behavioral reference.
```

For a rewrite:

```text
old implementation passes group
new implementation passes same group
compare observable behavior
```

This is stronger than rewriting from specification alone.

---

## 15. Do not erase useful failure logs

A result directory should remain after cleanup.

The host state can return to baseline while evidence remains under:

```text
/var/tmp/...test-results/RUN-ID/
```

Storage is cheap compared with losing the reason a dangerous test failed.

Implement explicit retention/rotation later if necessary.

---

## 16. Suggested result-directory layout

```text
RUN-ID/
├── baseline.vgs
├── baseline.pvs
├── baseline.lvs
├── baseline.storage
├── baseline.guests
├── after.vgs
├── after.pvs
├── after.lvs
├── after.storage
├── after.guests
├── dryrun-before-CASE
├── dryrun-after-CASE
├── CASE.log
└── anomaly-*.diff
```

Optional additions:

```text
environment.txt
versions.txt
summary.txt
fixture-manifest.txt
```

---

## 17. Record environment metadata

For reproducibility, a future enhancement should record:

```text
Proxmox VE version
kernel version
LVM version
qemu-server version
pve-storage version
hostname/node
cluster membership
filesystem tools
test project version
test-suite version
```

Avoid secrets and unnecessary configuration content.

---

## 18. Triage workflow

A useful repeatable process is:

```text
1. read all-groups summary;
2. identify failed groups;
3. inspect failed case logs;
4. inspect anomaly diffs separately;
5. determine first real failure;
6. classify failure category;
7. reproduce minimally;
8. fix root cause;
9. add regression test;
10. run affected group;
11. run full suite;
12. update findings.
```

---

## 19. When to rerun only one group

After a local fix, run the smallest relevant group first.

Examples:

```sh
./tests/groups/20-lvm.sh --run --verbose
./tests/groups/40-disk-lifecycle.sh --run --verbose
```

This gives fast feedback.

After the group passes, run the complete suite before declaring the release validated.

---

## 20. When a full-suite pass is meaningful

A full pass is especially meaningful when all of these are true:

```text
every group returned success;
every individual case passed or explicitly skipped;
all anomalies are zero;
dry-run before/after snapshots match;
cleanup returned protected state to baseline;
no hidden error diagnostics remain in logs.
```

The Proxmox v2.2.2 run satisfied these conditions for the covered matrix.

---

## 21. Search passing logs for suspicious diagnostics

Even when every case passes, scan logs for:

```text
ERROR:
FAIL:
unbound variable
command not found
leaked file descriptor
traceback
segmentation fault
unexpected WARNING
```

A warning can reveal a latent test defect before it becomes a failure.

---

## 22. Separate expected warnings from unexpected warnings

Some tests intentionally exercise warning paths.

Document expected warnings.

Examples:

```text
destructive DELETE confirmation warning;
dry-run cannot inspect a filesystem that was intentionally not mounted.
```

Unexpected warnings should be investigated even when the case passes.

---

## 23. Prefer findings over silent fixes

When a full integration run discovers nontrivial defects, document them.

A future maintainer encountering code such as:

```text
semantic storage canonicalization
independent deletion verification
strict case subshells
```

should be able to learn why those mechanisms exist.

---

## 24. Track coverage gaps separately from failures

A green suite may still have important untested areas.

Maintain a section for:

```text
not covered yet
```

rather than treating them as implicit PASS.

Examples:

```text
live guests;
LXC;
Ceph;
ZFS;
HA;
replication;
rollback fault injection.
```

---

## 25. Failure injection comes after stable happy paths

Do not begin by randomly killing storage commands.

First prove:

```text
fixture creation;
normal mutation;
verification;
cleanup;
baseline restoration.
```

Then add controlled failure points such as:

```text
fail after destination LV creation;
fail after data copy;
fail after config backup;
fail after first rename;
fail before source deletion.
```

Each failure-injection test should verify rollback or safe partial-state behavior.

---

## 26. Good regression tests are narrow and deterministic

A regression test should fail for one clear reason.

Avoid reproducing a helper bug by running a ten-step VM transaction if a five-line synthetic fixture can demonstrate it.

Integration regression and unit-like regression both belong in the system-test project.

---

## 27. Findings template

```text
# Integration Run Findings — DATE

Target tested:
Test-suite version:

## Summary
- groups
- cases
- failures
- anomalies

## Finding 1
Observed evidence:
Root cause:
Fix:
Regression coverage:

## Finding 2
...

## Confirmed passing areas

## Remaining untested areas

## Next-run expectations
```

---

## 28. Release-validation statement

A careful release note should say:

> All commands in the documented test matrix completed at least one real end-to-end integration path on the tested Proxmox environment, with dry-run non-mutation checks, postcondition verification, ownership-safe cleanup, and zero protected-state anomalies.

It should not say:

> Every possible configuration is guaranteed to work.

Precision builds trust.

---

## 29. Triage checklist

- [ ] preserve result archive before changing code;
- [ ] identify first real failing operation;
- [ ] inspect anomaly diffs separately;
- [ ] classify product vs harness vs environment;
- [ ] verify assumptions about underlying command behavior;
- [ ] reduce to minimal reproduction;
- [ ] add regression coverage;
- [ ] rerun affected group;
- [ ] rerun full suite;
- [ ] scan passing logs for hidden diagnostics;
- [ ] update findings and coverage gaps.

---

## 30. Guiding principle

A mature test system does not merely tell you whether something failed.

It gives enough evidence to determine **what failed, why it failed, whether anything unrelated changed, and how to prevent the same class of mistake from returning**.
