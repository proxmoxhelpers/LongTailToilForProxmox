# v3.0.0 POSIX Shell Migration Notes

## Purpose

Version 3 is a full rewrite of the shell-language layer of Proxmox LVM Tools.

The objective was not to redesign the validated behavior. The objective was to preserve the v2.2.2 safety/behavioral contract while applying the project's POSIX shell style guide and its sanctioned relaxed profiles.

The clean v2.2.2 Proxmox integration run is the behavioral reference.

## Migration result

All **36 executable commands** now use:

```sh
#!/bin/sh
set -eu
```

No command requires a Bash exception.

The two shared libraries are also POSIX `/bin/sh`.

The v3 static acceptance gate checks:

```text
/bin/sh syntax
/bin/sh shebangs
prohibited Bash constructs
all --help paths
all --version paths
dryrun keyword placement
shared helper return contracts
semantic storage-config canonicalization
strict test-runner failure semantics
```

## Bash constructs removed

The v2 implementation used Bash features where convenient. The v3 rewrite removes them rather than hiding them behind `/bin/sh`.

Examples:

| v2 mechanism | v3 mechanism |
|---|---|
| `[[ ... ]]` | POSIX `[ ... ]`, `case`, or explicit `grep` |
| Bash arrays | newline-delimited immutable plan files |
| `mapfile` / `readarray` | `while IFS= read -r` over plan files |
| `local` | subshell functions or prefixed variables |
| process substitution | temporary files / ordinary pipelines |
| here strings | `printf '%s\n' ... | command` |
| `BASH_SOURCE` | startup-time `SCRIPT_DIR` from `$0` |
| `source` | POSIX dot (`.`) |
| `for ((...))` | POSIX counter/`while` loops |
| Bash `ERR` rollback | POSIX exit trap + append-only transaction journal |
| `%q`-style Bash quoting | POSIX diagnostic `shell_quote` helper |

## Lifecycle style

Every executable exposes the program flow at the top:

```sh
setup() {
    ...
}

main() {
    ...
}

end() {
    ...
}
```

The only top-level operational calls are at the bottom:

```sh
setup "$@"
main "$@"
end
```

`setup()` owns configuration, CLI parsing and elevation detection.

`main()` reads as the high-level operation.

`end()` owns normal summaries/final dry-run reporting.

## Function profiles

The rewrite follows both:

- `POSIX-SHELL-STYLE-GUIDE-v3.md`
- `STYLE-PROFILES-AND-EXCEPTIONS.md`

Safety-sensitive parsers, ownership checks, transaction plans and rollback handlers use full documentation blocks.

Obvious high-level phases and tiny helpers use sanctioned compact comments instead of repetitive boilerplate.

Performance-sensitive discovery avoids unnecessary subprocess multiplication where practical.

## Dry-run rewrite

Dry-run mode is now implemented entirely in POSIX shell.

The contract is unchanged:

```text
dryrun / --dryrun accepted anywhere
read-only preflight remains real
mutations are printed, not executed
mutation-dependent verification is simulated
nested project scripts inherit dry-run
normal mode helpers return real command status
```

The quoting helper is diagnostic and shell-readable without Bash `%q`.

## LVM warning filtering

The v2.2.x integration work already showed why Bash process substitution was undesirable for filtered `lvcreate` stderr: it could leak a descriptor into LVM.

v3 uses:

```text
mktemp stderr file
run command
capture true status
filter only three known advisories
replay every other warning/error
return original status
```

No process substitution is used.

## Transaction plan files

Bash arrays in complex operations have been replaced with immutable temporary plan files.

Examples:

### `renumber-vm-disks.sh`

Plan columns:

```text
index|volid|path|vg|old-lv|new-lv|storage-id|temporary-lv
```

The complete plan and collision checks are finished before the first rename.

Renames then happen in two phases through unique temporary names.

### `fix-vm-volume-names.sh`

Plan columns:

```text
old-volid|new-volid|vg|old-lv|new-lv
```

Every shared-reference/collision check completes before mutation.

### `change-vmid-of-vm.sh`

Plan columns:

```text
old-volid|old-path|vg|old-lv|new-lv|new-volid
```

A separate append-only journal records only successfully completed LV renames:

```text
vg|old-lv|new-lv
```

If the mutation fails before completion, the journal is replayed in reverse order.

This is both POSIX-compatible and easier to audit than implicit array state.

## Copy safety preserved

`copy-lvm.sh` and `create-disk-copy-and-add-to-vm.sh` retain the tested allocation/copy distinction:

Thin destination:

```sh
dd ... conv=sparse,fsync
```

Regular destination:

```sh
dd ... conv=fsync
```

Sparse copying is deliberately not used for regular LVs because skipped zero blocks could expose stale physical data.

Copies are byte-verified with `cmp` before success/source deletion.

## Mount safety preserved

The mount rewrite retains the important tested rules:

```text
mountpoint -q for exact mount-point occupancy
kpartx for partition mappings
direct-filesystem fallback only when no partition table exists
read-only default
skip swap/LVM2_member/LUKS
refuse non-empty mount directories
rmdir-only cleanup of project mount directories
no recursive mount-directory deletion
```

Dry-run uses read-only partition discovery and does not create mapper devices merely to inspect them.

## Shared identity semantics

Where names are insufficient, v3 compares canonical device identity.

Examples include:

```text
find-volume-owner
find-orphaned-volumes
Proxmox storage mapping verification
LV aliases
```

`pvesm path` is treated as a resolver, not as an existence predicate. Deletion verification uses storage listings and backing-object existence.

## Privilege model

Mutating commands detect elevation after argument parsing and self-elevate once at the start of `main()`.

Help/version therefore remain usable without root.

Read-only commands omit elevation code entirely.

## Integration-test migration

The integration harness itself remains POSIX shell.

Test suite version 2.0.0 changes the static group to:

```text
use sh -n rather than bash -n
require /bin/sh entry points
reject known Bash-only constructs
test all help/version paths locally
retain the v2 regression tests
```

The real Proxmox groups retain the same disposable loopback-backed fixture model and the same 36-command coverage matrix.

## Validation boundary

The v3 rewrite has been statically validated in the build environment.

It has **not yet been declared Proxmox-integration validated** merely because the v2 implementation passed.

The correct promotion process is:

```text
v2.2.2 = known-good behavioral reference
v3.0.0 = POSIX rewrite candidate
run v3 full integration suite on Proxmox
require every group/case green and anomalies=0
then promote v3 as integration-validated
```

Run:

```sh
./tests/run-all-tests.sh --run --verbose
```

## No intentional behavioral removals

No project command was dropped.

The command count remains **36**.

No major safety feature was intentionally weakened to obtain POSIX compatibility.

Where POSIX required more explicit machinery—most notably arrays and rollback—the rewrite uses plan/journal files rather than reducing verification or transaction safety.


## Static validation record

See [`V3-STATIC-VALIDATION.md`](V3-STATIC-VALIDATION.md) for the exact pre-package acceptance evidence and validation boundary.
