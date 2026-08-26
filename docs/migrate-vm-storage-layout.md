# `migrate-vm-storage-layout.sh`

[Back to helper list](../README.md) · [View script](../migrate-vm-storage-layout.sh) · [Raw usage](./migrate-vm-storage-layout.sh.usage)

## Purpose

Migrates one or all active disks of a stopped, snapshot-free QEMU VM using qm move_disk. SLOT, when supplied, must be an exact QEMU disk slot. Each successful move is verified to use the destination storage. If execution is interrupted or a later move/verification fails, selected disks that reached the destination are best-effort moved back in reverse order to their recorded recorded original storages. A rollback can create a different physical LV identity even though Proxmox copies the disk content back, so any rollback warning requires operator inspection before retrying.

## Usage and live help

The built-in help is available without performing the operation:

```sh
./migrate-vm-storage-layout.sh --help
```

<!-- BEGIN LIVE HELP -->
```text
migrate-vm-storage-layout.sh 3.7.1 (project 3.7.1)

USAGE
  migrate-vm-storage-layout.sh <VMID> <destination-storage> [--slot SLOT] [dryrun|--preflight]

DESCRIPTION
  Migrates one or all active disks of a stopped, snapshot-free QEMU VM using
  qm move_disk. SLOT, when supplied, must be an exact QEMU disk slot. Each
  successful move is verified to use the destination storage. If execution is
  interrupted or a later move/verification fails, selected disks that reached
  the destination are best-effort moved back in reverse order to their recorded
  recorded original storages. A rollback can create a different physical LV identity even
  though Proxmox copies the disk content back, so any rollback warning requires
  operator inspection before retrying.

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

The same output is stored verbatim in [`migrate-vm-storage-layout.sh.usage`](./migrate-vm-storage-layout.sh.usage) and is checked byte-for-byte by the static suite.

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
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/migrate-vm-storage-layout.sh" -O "migrate-vm-storage-layout.sh" && chmod +x "migrate-vm-storage-layout.sh"
```

## Source documentation

The script is standalone. Function comment blocks follow the project POSIX style guide; every argument-taking function documents its call syntax with `Call:` or the sanctioned full-form `Usage:` field.

## Version

```text
migrate-vm-storage-layout.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.

## Related project guidance

See the [POSIX shell style guide](./POSIX-SHELL-STYLE-GUIDE-v3.md), [Proxmox scripting lessons learned](./PROXMOX-SHELL-SCRIPTING-LESSONS-LEARNED.md), and [testing documentation](./testing/README.md).
