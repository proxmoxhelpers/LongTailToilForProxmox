# Test System Design Guide

This document captures the general lessons learned while building and iterating the Proxmox LVM Tools integration suite.

The goal is not merely to produce tests that return green. The goal is to build a test system that can safely exercise real system tools, detect unintended side effects, distinguish test-harness defects from product defects, and leave useful evidence when anything goes wrong.

The principles here are reusable for storage tools, hypervisor utilities, system administration scripts, deployment tools, and other software that modifies operating-system state.

---

## 1. What a good system test must prove

A convincing system test should prove more than:

```text
the program exited with status 0
```

For a mutating system tool, a useful integration test should normally establish all of the following:

```text
1. pre-flight discovery works against the real system;
2. dry-run mode does not modify state;
3. the real command reaches the intended underlying system tools;
4. the requested state transition actually occurs;
5. important postconditions are verified independently;
6. unrelated protected state remains unchanged;
7. cleanup removes only test-owned objects;
8. the environment returns to its baseline after cleanup.
```

A test that merely checks printed command lines is a command-construction test, not an integration test.

A test that calls the real tools but never verifies the resulting state is an execution test, but still not a complete integration test.

---

## 2. Separate three kinds of testing

A robust test system should distinguish:

### 2.1 Static / parser tests

Examples:

```text
shell syntax
--help
--version
argument parsing
style checks
coverage-matrix checks
known regression helpers
```

These are fast and safe.

### 2.2 Dry-run behavior tests

These prove that:

```text
the same pre-flight logic executes;
the intended mutation is printed;
the command reports simulated postconditions;
the real system does not change.
```

Dry-run tests are safety tests.

They are not substitutes for real integration tests.

### 2.3 Real integration tests

These execute the actual mutation against disposable resources.

Examples:

```text
lvcreate
lvrename
lvremove
qm set
qm move_disk
pvesm free
mount
umount
qemu-img convert
```

The resulting system state must then be verified.

---

## 3. Default to plan-only

A potentially destructive integration launcher should do nothing when invoked without an explicit execution option.

Preferred:

```sh
./tests/run-all-tests.sh
```

prints the test plan.

Real execution requires:

```sh
./tests/run-all-tests.sh --run
```

This makes accidental invocation harmless and lets the operator review the intended scope before mutation begins.

Do not make a dangerous test suite start merely because it was executed.

---

## 4. Build an isolated namespace

Every test run should have a unique namespace.

Useful ingredients include:

```text
timestamp
process ID
checksum-derived token
random token
```

Example conceptual namespace:

```text
TEST_RUN_ID=lvm-20260815015039-3038286
TEST_VG_A=plvtA47920001
TEST_VG_B=plvtB47920001
TEST_STORAGE_A=plvt-a-47920001
TEST_VM=930896
```

All resources created by the test should be traceable to the run.

The namespace is not merely for collision avoidance. It is part of the cleanup proof.

---

## 5. Prefer synthetic resources over production resources

The safest integration fixture is one that can be created from scratch.

For storage tests, a strong pattern is:

```text
sparse file
  ↓
loop device
  ↓
LVM PV
  ↓
test VG
  ↓
thin pool / regular LV
  ↓
temporary Proxmox storage
  ↓
disposable stopped VM
```

This gives the test a real block device and real LVM behavior without selecting an existing disk.

The same principle generalizes:

```text
temporary directory instead of real application data;
local test service instead of production endpoint;
synthetic config instead of modifying the operator's config;
disposable VM instead of a production VM.
```

---

## 6. Small fixtures are safer and faster

Use the smallest resource that still exercises the real behavior.

Examples from the Proxmox suite:

```text
16–64 MiB logical volumes
small raw images
128 MiB test VMs
sparse 1 GiB loopback backing files
```

Small fixtures reduce:

```text
copy time;
cleanup time;
storage pressure;
failure exposure;
operator anxiety;
test feedback time.
```

Do not use production-sized resources merely to make the test feel realistic.

---

## 7. Pre-flight before fixture creation

Before creating a resource, verify that the intended identifier is unused.

Examples:

```text
VG does not exist;
storage ID does not exist;
VMID is unused cluster-wide;
destination LV does not exist;
mount target is unused.
```

Never rely on a generated name being unique without checking.

Collision handling should fail safely and generate another candidate when appropriate.

---

## 8. Record ownership, do not infer it later

A cleanup routine should not ask:

> Does this object look like one of ours?

It should ask:

> Can I prove this is the exact object created by this run?

Record ownership as objects are created.

Examples:

```text
VMID | expected VM name
storage ID | expected VG
VG | expected PV | expected loop device | expected backing file
```

Before deletion, re-read the current object and compare it with the recorded identity.

If identity changed, cleanup should refuse.

---

## 9. Use an ownership marker for the sandbox

The filesystem sandbox should contain a marker created by the harness itself.

Example:

```text
/var/tmp/.../TEST_RUN/.owner
```

with a fixed magic value such as:

```text
PROXMOX_LVM_TOOLS_TEST_SANDBOX_V1
```

Cleanup should refuse recursive removal when the marker is missing or unexpected.

A directory path alone is not sufficient proof of ownership.

---

## 10. Cleanup should be narrow and conservative

Good cleanup:

```text
umount exact recorded mount
qm destroy exact recorded test VM after name verification
pvesm remove exact recorded storage after VG verification
vgremove exact recorded VG after PV verification
losetup -d exact recorded loop
rm -rf exact sandbox only after marker verification
```

Bad cleanup:

```text
rm -rf /var/tmp/plvt*
lvremove -y testvg/*
qm destroy every VMID above 900000
pvesm remove every storage beginning with test-
```

Pattern-based bulk cleanup is dangerous.

---

## 11. Refusal is safer than heroic cleanup

If cleanup cannot prove ownership, it should stop and leave the object for manual inspection.

A leaked disposable test object is inconvenient.

Deleting the wrong production object is catastrophic.

The cleanup hierarchy should therefore be:

```text
prove ownership
    ↓
clean
```

not:

```text
looks probably safe
    ↓
clean aggressively
```

---

## 12. Capture protected state before mutation

A system test should record the pre-existing state that must not change.

Examples:

```text
VG identities
PV mappings
LV identities
guest configurations
storage definitions
mount state
network definitions
```

The baseline should be captured before the sandbox exists.

After cleanup, capture it again and compare.

This catches side effects the individual test assertions may not anticipate.

---

## 13. Compare semantics, not serialization

One of the most important lessons from the Proxmox test runs was that byte-for-byte configuration comparison can produce false anomalies.

For example, Proxmox legitimately rewrote:

```text
content rootdir,images
```

as:

```text
content images,rootdir
```

The meaning did not change.

A useful protected-state comparator should canonicalize the data according to its semantics.

For set-valued fields:

```text
content images,rootdir
```

can be represented as:

```text
content|images
content|rootdir
```

and sorted.

The principle is:

> Normalize irrelevant representation differences while preserving every semantically meaningful difference.

Do not normalize so aggressively that real changes disappear.

---

## 14. Use independent postcondition checks

Do not verify an operation only by reusing the same abstraction that performed it.

A useful example was volume deletion.

The initial test assumed:

```sh
pvesm path "$VOLID"
```

failing would prove deletion.

But `pvesm path` can synthesize the expected path even after the backing LV is gone.

The stronger verification was:

```text
exact volume ID absent from storage listing;
previously resolved backing path absent;
LV absent from LVM metadata.
```

Whenever possible, verify through a different observation path.

---

## 15. Resolve identity, not merely names

Names can be ambiguous across namespaces.

Examples:

```text
same LV name in different VGs;
same vm-N-disk-M name on different storage;
different /dev aliases for the same device.
```

Tests should compare canonical identity where practical:

```text
canonical block-device path;
VG + LV;
storage ID + volume ID;
major/minor device identity.
```

This avoids both false positives and false ownership matches.

---

## 16. Dry-run must prove non-mutation

A dry-run test should not merely inspect the output.

Use:

```text
snapshot test-owned state before;
run command with dryrun;
snapshot test-owned state after;
compare exactly.
```

If the snapshots differ, the dry-run failed its contract even if the output says:

```text
[DRYRUN] No modifying command was executed.
```

Trust state, not messages.

---

## 17. Run the real operation after the dry-run

The ideal sequence for a mutating case is:

```text
prepare fixture
capture test-owned state
run dryrun
prove no change
run real operation
verify requested postcondition
```

This simultaneously tests:

```text
planning;
dry-run safety;
real integration;
verification logic.
```

---

## 18. Test the harness itself

A system-test harness is software and needs regression tests.

The Proxmox suite found several harness defects:

```text
set -e disabled by invoking test functions directly in an if condition;
raw config hashing treated harmless reorderings as anomalies;
a test stub referenced an unset positional parameter.
```

Useful harness self-tests include:

```text
a failed command must fail the test case immediately;
semantic canonicalization must normalize known harmless differences;
dry-run snapshots must detect modifications;
empty valid results must remain successful;
all commands must appear in the coverage matrix.
```

---

## 19. Beware shell error-handling context

Shell test runners can accidentally suppress failures.

In Bash and POSIX-like shells, `set -e` behavior changes in conditions such as:

```sh
if function_call; then
    ...
fi
```

A function executed in such a context may continue after a failed internal command.

A safer test runner executes each case in an isolated strict subshell and captures that subshell's exit status.

The lesson is broader:

> Never assume strict mode behaves identically in every syntactic context.

Test the test runner's failure semantics.

---

## 20. Empty output can still be success

Functions such as:

```text
find other references
find dependent snapshots
find matching optional objects
```

may legitimately return no lines.

Do not conflate:

```text
empty result
```

with:

```text
operation failed
```

Define the function contract explicitly.

A common good convention is:

```text
return 0 + empty stdout = successful lookup, no matches
nonzero = lookup itself failed
```

---

## 21. The last command controls function status

Another shell lesson was that a helper ending with a false predicate can accidentally make successful work return failure.

Example anti-pattern:

```sh
dryrun_enabled && dryrun_summary
```

If dry-run is disabled, the final command returns nonzero.

If that is the last statement in a function, the function returns nonzero too.

Prefer explicit success:

```sh
if dryrun_enabled; then dryrun_summary; fi
return 0
```

System-test suites should contain regression tests for helpers whose status matters.

---

## 22. Convert every discovered defect into a regression test

When a real run discovers a defect:

```text
1. preserve the evidence;
2. identify the root cause;
3. fix the command or harness;
4. add a regression test reproducing the cause;
5. rerun the full relevant group;
6. rerun the complete suite when practical.
```

This is how the test system becomes progressively more trustworthy.

---

## 23. Distinguish command failures from harness failures

A failed test does not automatically mean the command under test is wrong.

Possible causes include:

```text
product defect;
test assertion defect;
fixture defect;
cleanup defect;
baseline comparator defect;
environment race;
unsupported environment;
test runner error.
```

The harness should preserve enough evidence to determine which category applies.

---

## 24. Keep per-case logs

Every test case should write its complete stdout/stderr to a unique log.

For passing cases:

```text
show only in verbose mode
```

For failing cases:

```text
print immediately
preserve on disk
```

This keeps normal output readable while retaining full evidence.

---

## 25. Preserve run-level evidence

A useful result directory contains:

```text
per-case logs
baseline snapshots
after snapshots
dry-run before/after snapshots
anomaly diffs
run ID
test version
project version
```

Do not delete the evidence merely because fixture cleanup succeeded.

---

## 26. Make anomalies conservative failures

If protected state changes unexpectedly, the group should fail even when every functional assertion passed.

This avoids:

```text
"all tests passed"
```

while the host was accidentally modified.

False-positive anomaly detectors should be fixed by improving semantic comparison, not by ignoring anomaly failures.

---

## 27. Skip rather than improvise

If a safe fixture cannot be constructed, use:

```text
SKIP
```

Examples:

```text
no Linux bridge exists;
optional filesystem tool missing;
required storage feature unavailable.
```

Do not substitute a production object merely to avoid a skipped test.

---

## 28. Keep group fixtures independent

Groups should create and remove their own sandboxes.

Benefits:

```text
one failed group does not poison every later group;
cleanup scope stays small;
logs are easier to interpret;
rerunning one area is easy;
parallelization may become possible later.
```

Within a group, avoid hidden dependencies between test cases unless the sequence is itself the thing being tested.

---

## 29. Use a coverage matrix

Maintain an explicit mapping:

```text
command
test group
dry-run coverage
real integration coverage
major branches covered
known branches not covered
```

This prevents a green suite from giving a false impression that every tool is exercised.

---

## 30. Green does not mean universal correctness

A clean full integration run proves:

```text
the tested workflows worked on the tested environment.
```

It does not prove every possible branch.

Document important untested dimensions such as:

```text
HA
replication
multi-node races
active guests
LXC-specific branches
unusual storage plugins
failure injection
rollback after partial mutation
different filesystems
different partition tables
regular LVM vs thin LVM combinations
```

The right conclusion is:

> integration-validated for the covered matrix

not:

> impossible to fail anywhere.

---

## 31. Recommended lifecycle for a new system-test suite

```text
Phase 1 — static checks
Phase 2 — plan-only launcher
Phase 3 — isolated fixture creation
Phase 4 — dry-run non-mutation checks
Phase 5 — real happy-path integration
Phase 6 — protected-state baseline comparison
Phase 7 — regression tests for discovered issues
Phase 8 — negative/refusal-path tests
Phase 9 — controlled failure injection
Phase 10 — multi-environment coverage
```

Do not begin with failure injection before the happy path and cleanup model are trustworthy.

---

## 32. Acceptance checklist

A system-test harness is ready for destructive integration use when:

- [ ] default invocation performs no mutation;
- [ ] execution requires an explicit option;
- [ ] every resource uses a unique run namespace;
- [ ] fixtures avoid production storage/data;
- [ ] ownership is recorded at creation time;
- [ ] cleanup re-verifies ownership;
- [ ] cleanup refuses uncertain objects;
- [ ] protected baseline is captured before fixture creation;
- [ ] semantic normalization is documented;
- [ ] dry-run non-mutation is state-verified;
- [ ] real operations are executed after dry-run;
- [ ] postconditions are independently verified;
- [ ] per-case logs are preserved;
- [ ] anomaly diffs are preserved;
- [ ] the harness has regression tests for its own failure semantics;
- [ ] coverage is documented;
- [ ] skipped scenarios are explicit;
- [ ] limitations are documented.

---

## 33. Guiding principle

A safe system-test suite should be designed under the assumption that both the application **and the test harness** may contain bugs.

Therefore:

> Isolate aggressively, prove ownership before cleanup, verify state rather than trusting output, compare semantics rather than formatting, and preserve enough evidence to explain every failure.
