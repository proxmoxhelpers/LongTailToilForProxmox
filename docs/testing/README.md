# Test-System Engineering Documentation

These documents capture the engineering practices developed while building, debugging, and validating the Proxmox LVM Tools integration suite.

They are intended to be reusable for future v3 work and for other system-administration projects where tests must exercise real operating-system tools without endangering existing data.

## Documents

### [Test System Design Guide](TEST-SYSTEM-DESIGN-GUIDE.md)

General architecture and safety principles:

- plan-only defaults;
- synthetic fixtures;
- unique namespaces;
- ownership proofs;
- dry-run non-mutation testing;
- real integration execution;
- semantic protected-state comparison;
- independent postcondition verification;
- conservative cleanup;
- harness self-testing.

Start here when designing a new system-test suite.

### [Proxmox Disposable Integration Lab Guide](PROXMOX-DISPOSABLE-INTEGRATION-LAB-GUIDE.md)

Proxmox-specific fixture architecture:

- sparse files and loop devices;
- disposable PV/VG/thin-pool stacks;
- temporary `lvmthin` storage IDs;
- dynamically allocated high VMIDs;
- stopped synthetic VMs;
- mount/import/export fixtures;
- Proxmox storage canonicalization;
- layered verification;
- ownership-safe cleanup.

Use this when constructing new Proxmox integration groups.

### [Shell Test Harness Implementation Guide](SHELL-TEST-HARNESS-IMPLEMENTATION-GUIDE.md)

Implementation patterns for the shell harness:

- `setup` / `main` / `end`;
- explicit `--run`;
- one-time elevation;
- strict per-case subshells;
- first-failure capture;
- return-code contracts;
- dry-run snapshots;
- traps and cleanup;
- PASS/FAIL/SKIP/ANOMALY accounting;
- regression tests for harness behavior.

Use this while writing or reviewing test launchers.

### [Test Evidence, Triage, and Regression Guide](TEST-EVIDENCE-TRIAGE-AND-REGRESSION-GUIDE.md)

How to investigate integration results:

- preserve evidence;
- classify failures;
- inspect anomaly diffs;
- distinguish command bugs from harness bugs;
- validate assumptions about system tools;
- reduce failures to minimal reproductions;
- convert root causes into regression tests;
- maintain run-findings documents;
- state release validation precisely.

Use this after a test run produces a failure or unexpected warning.

## Lessons that motivated these guides

The first three complete Proxmox runs exposed several classes of issue that a less careful suite could easily have missed:

```text
successful operations returning failure because a helper's final predicate was false;
set -e being weakened by the test runner's conditional context;
empty search results being mistaken for errors;
LVM-warning filtering leaking a file descriptor;
multi-disk renumbering collapsing entries because of an incorrect sort key;
pvesm path being mistaken for an existence check;
raw storage.cfg comparison flagging harmless list reordering;
test stubs emitting hidden background errors;
successful commands being distinguished from successful-looking dry-run output.
```

The final v2.2.2 run then demonstrated:

```text
10/10 groups passed;
45/45 individual cases passed;
0 anomalies;
dry-run state remained unchanged;
real Proxmox/LVM/filesystem operations succeeded;
protected pre-existing state returned to baseline.
```

These guides preserve the reasoning behind the mechanisms that made that result trustworthy.

## Relationship to the v3 style guide

The shell implementation examples should be read alongside:

- [`../POSIX-SHELL-STYLE-GUIDE-v3.md`](../POSIX-SHELL-STYLE-GUIDE-v3.md)
- [`../STYLE-PROFILES-AND-EXCEPTIONS.md`](../STYLE-PROFILES-AND-EXCEPTIONS.md)

The style guide defines how future POSIX shell should look. These testing guides define how its behavior should be proven.
