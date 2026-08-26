# `export-vm-filesystem.sh`

[Back to helper list](../README.md) · [View script](../export-vm-filesystem.sh) · [Raw usage](./export-vm-filesystem.sh.usage)

## Purpose

Exports one filesystem from a stopped QEMU VM through a private host mount. Partitioned disks require an explicit partition number. ext3/4 use noload and XFS uses norecovery so the read-only mount cannot replay guest recovery data. Mapper ownership and exact mount source are verified; output is staged and atomically committed only after a complete archive is created; without --force an output path that appears concurrently is never overwritten. An inactive LVM disk may be temporarily activated in normal mode and is restored on every exit path; dry-run/preflight never activates it. Temporary mounts/mappings are removed on every exit path.

## Usage and live help

The built-in help is available without performing the operation:

```sh
./export-vm-filesystem.sh --help
```

<!-- BEGIN LIVE HELP -->
```text
export-vm-filesystem.sh 3.7.1 (project 3.7.1)

USAGE
  export-vm-filesystem.sh <VMID> <slot> <output.tar[.gz|.zst]> [--partition N] [--force] [dryrun|--preflight]

DESCRIPTION
  Exports one filesystem from a stopped QEMU VM through a private host mount.
  Partitioned disks require an explicit partition number. ext3/4 use noload and
  XFS uses norecovery so the read-only mount cannot replay guest recovery data.
  Mapper ownership and exact mount source are verified; output is staged and
  atomically committed only after a complete archive is created; without --force an
  output path that appears concurrently is never overwritten. An inactive LVM
  disk may be temporarily activated in normal mode and is restored on every
  exit path; dry-run/preflight never activates it. Temporary mounts/mappings
  are removed on every exit path.

COMMON OPTIONS
  -h, -?, /h, /?, --help  Show this help and exit.
  --version               Show script and project versions and exit.
  dryrun, --dryrun,
  --plan                  Enable dry-run/plan mode.
  --preflight             Run the same non-mutating preflight/plan path.
  --no-color              Disable ANSI colour output.
  --quiet                 Reduce non-essential LongTail output where supported.

  Common options may appear anywhere on the command line.
  Dry-run: no system changes are made; modifying commands are printed instead of executed.
```
<!-- END LIVE HELP -->

The same output is stored verbatim in [`export-vm-filesystem.sh.usage`](./export-vm-filesystem.sh.usage) and is checked byte-for-byte by the static suite.

## Safety and behavior

- `--help` and `--version` are handled before privilege/environment gates.
- `dryrun`, `--dryrun`, `--plan`, and `--preflight` use the non-mutating plan path; read-only helpers remain read-only.
- `--no-color` disables ANSI output and `--quiet` reduces non-essential LongTail output where supported.
- Ambiguous guest, slot, storage, or LVM identities are refused rather than guessed.
- For mutating helpers, preflight is completed before the first mutation and postconditions are verified after the operation.
- Integration safety/variant coverage: Safety/refusal and postcondition coverage appropriate to the helper; storage identity is verified independently.

## Test coverage

- Integration group: [`85-qol-workflows.sh`](../tests/groups/85-qol-workflows.sh)
- Positive / real coverage: Dry-run immutability plus disposable Proxmox/LVM fixture coverage for the helper's primary workflow.
- Negative / variant coverage: Safety/refusal and postcondition coverage appropriate to the helper; storage identity is verified independently.

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/export-vm-filesystem.sh" -O "export-vm-filesystem.sh" && chmod +x "export-vm-filesystem.sh"
```

## Source documentation

The script is standalone. Function comment blocks follow the project POSIX style guide; every argument-taking function documents its call syntax with `Call:` or the sanctioned full-form `Usage:` field.

## Version

```text
export-vm-filesystem.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.

## Related project guidance

See the [POSIX shell style guide](./POSIX-SHELL-STYLE-GUIDE-v3.md), [Proxmox scripting lessons learned](./PROXMOX-SHELL-SCRIPTING-LESSONS-LEARNED.md), and [testing documentation](./testing/README.md).
