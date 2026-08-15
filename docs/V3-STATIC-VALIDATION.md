# v3.0.0 Static Migration Validation

Date: **2026-08-15**

This document records what was validated in the v3 build environment before packaging.

It deliberately distinguishes static/migration validation from the real Proxmox integration validation that must still be performed on a Proxmox node.

## Behavioral reference

The v3 rewrite is based on the clean v2.2.2 integration baseline:

```text
10/10 groups passed
45/45 individual integration cases passed
0 failed
0 skipped
0 protected-state anomalies
```

That run executed real Proxmox/LVM/filesystem mutations against disposable fixtures and returned protected host state to baseline.

## v3 local static result

The v3 static group completed:

```text
Passed    : 14
Failed    : 0
Skipped   : 0
Anomalies : 0
```

## Project inventory

```text
Executable project commands : 36
Shared project libraries     : 2
Test shell files             : 12
Coverage matrix              : 36/36 commands
```

## Shell target

Every executable project command begins with:

```sh
#!/bin/sh
set -eu
```

On the build host `/bin/sh` resolves to `dash`.

All 36 commands, both shared libraries, and all test launchers/libraries passed:

```sh
/bin/sh -n
```

## Style/language checks

Validated:

- all 36 commands contain `setup()`, `main()`, and `end()`;
- all 36 commands declare project/script version 3.0.0;
- all entry points use `#!/bin/sh`;
- no trailing-backslash command continuations remain;
- the v3 static source scan finds no prohibited Bash declaration/source/array/process-substitution/here-string/arithmetic-loop constructs;
- no Bash exception is currently required;
- non-trivial transaction/planning/rollback functions carry full documentation blocks;
- obvious phase helpers use the sanctioned compact documentation profile.

A broad secondary text-regex audit was also performed. Its apparent hits were inspected and were representation false positives such as:

```text
${VAR:-default}       POSIX parameter default expansion
awk: value == other  awk language, not shell syntax
awk: function f()    awk language, not shell function syntax
```

They are not Bash dependencies.

## Privilege model

Exactly four read-only commands omit elevation machinery:

```text
audit-vm-storage.sh
find-orphaned-volumes.sh
find-volume-owner.sh
list-vm-disks.sh
```

Every mutating command:

```text
parses CLI first
detects elevation in setup()
checks APP_ELEVATED at the start of main()
self-elevates once through sudo when required
preserves "$@" exactly
```

Help/version therefore remain available without elevation.

## CLI validation

For every one of the 36 commands, the following completed successfully without Proxmox preflight:

```text
--version
--help
dryrun --version
--version dryrun
```

Every version path reports:

```text
(project 3.0.0)
```

## Shared-library regressions

The static suite explicitly proved:

### Dry-run summary status

`dryrun_summary` succeeds in normal mode and therefore cannot make an otherwise successful command fail simply because dry-run is disabled.

### Dry-run mutation suppression

A real `touch` mutation was passed to `dryrun_cmd`.

The command was printed and returned simulated success, but the file did not appear.

### LVM warning filter

A synthetic wrapped command wrote:

```text
one known thin-pool advisory
one unrelated error
```

and exited with status `7`.

`run_lvm_filtered`:

```text
removed the known advisory
preserved the unrelated error
returned status 7
```

This validates the new POSIX temp-file implementation used instead of Bash process substitution.

### Empty reference lookup

A successful `other_volume_references` lookup with no matches returns status 0 and empty stdout under `/bin/sh`.

### Storage canonicalization

Two synthetic Proxmox `storage.cfg` files with reordered `content`/`nodes` members canonicalized identically.

### Test runner strictness

A deliberately failing test command stopped its isolated test case before a later statement could mask the failure.

## Test launcher validation

All ten group launchers completed their default plan-only invocation without creating integration fixtures.

The top-level launcher also completed plan-only mode and enumerated all ten groups.

## Temporary-resource handling

The v3 rewrite adds POSIX exit cleanup for process-owned temporary plan/state files.

Safety-sensitive storage/config transactions keep dedicated transaction handlers instead:

```text
copy-lvm
create-disk-copy-and-add-to-vm
create-disk-snapshot-and-add-to-vm
change-vmid-of-vm
```

Signal handlers convert HUP/INT/TERM into an ordinary nonzero exit so the single exit cleanup/rollback path runs once.

## What this validation does NOT prove

The build environment is not a Proxmox VE node.

Therefore this document does **not** claim that the rewritten v3 commands have already demonstrated real interaction with:

```text
qm
pct
pvesm
LVM/device-mapper
kpartx
mount/umount
qemu-img
pmxcfs
```

The v2.2.2 implementation demonstrated those interactions. The v3 rewrite must now reproduce that result.

## Required promotion test

On a Proxmox node:

```sh
./tests/run-all-tests.sh --run --verbose
```

The v3 rewrite should not replace v2.2.2 as the integration-validated baseline until the run finishes with:

```text
all 10 groups passed
all individual cases passed (or only explicitly justified skips)
0 protected-state anomalies
dry-run before/after snapshots unchanged
```

Attach/preserve the result archive if any case fails.

## Promotion principle

```text
v2.2.2
  = known-good real-system behavioral reference

v3.0.0 before Proxmox run
  = POSIX rewrite candidate with clean static/migration validation

v3.0.0 after a fully green Proxmox run
  = integration-validated POSIX implementation
```
