# `rebuild-vm-from-existing-disks.sh`

[Back to helper list](../README.md) · [View script](../rebuild-vm-from-existing-disks.sh) · [Raw usage](./rebuild-vm-from-existing-disks.sh.usage)

## Purpose

Discovers exactly named, unreferenced vm-VMID-disk-N/base-VMID-disk-N LVs, proves a unique Proxmox storage mapping by LV UUID, rejects duplicate disk-N candidates, and proposes a minimal recovery VM ordered by backing disk number. It is plan-only unless --apply is used. Hardware that cannot be inferred safely (NICs, exact machine/CPU/firmware) is not guessed beyond the explicit defaults/options. If apply fails after the new VM config is created, only that new config is eligible for cleanup and no recovered storage volume is freed.

## Usage and live help

The built-in help is available without performing the operation:

```sh
./rebuild-vm-from-existing-disks.sh --help
```

<!-- BEGIN LIVE HELP -->
```text
rebuild-vm-from-existing-disks.sh 3.7.1 (project 3.7.1)

USAGE
  rebuild-vm-from-existing-disks.sh <VMID> [--name NAME] [--memory MiB] [--cores N] [--ovmf] [--apply] [dryrun|--preflight]

DESCRIPTION
  Discovers exactly named, unreferenced vm-VMID-disk-N/base-VMID-disk-N LVs,
  proves a unique Proxmox storage mapping by LV UUID, rejects duplicate disk-N
  candidates, and proposes a minimal recovery VM ordered by backing disk number.
  It is plan-only unless --apply is used.

  Hardware that cannot be inferred safely (NICs, exact machine/CPU/firmware)
  is not guessed beyond the explicit defaults/options. If apply fails after the
  new VM config is created, only that new config is eligible for cleanup and no
  recovered storage volume is freed.

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

The same output is stored verbatim in [`rebuild-vm-from-existing-disks.sh.usage`](./rebuild-vm-from-existing-disks.sh.usage) and is checked byte-for-byte by the static suite.

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
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/rebuild-vm-from-existing-disks.sh" -O "rebuild-vm-from-existing-disks.sh" && chmod +x "rebuild-vm-from-existing-disks.sh"
```

## Source documentation

The script is standalone. Function comment blocks follow the project POSIX style guide; every argument-taking function documents its call syntax with `Call:` or the sanctioned full-form `Usage:` field.

## Version

```text
rebuild-vm-from-existing-disks.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.

## Related project guidance

See the [POSIX shell style guide](./POSIX-SHELL-STYLE-GUIDE-v3.md), [Proxmox scripting lessons learned](./PROXMOX-SHELL-SCRIPTING-LESSONS-LEARNED.md), and [testing documentation](./testing/README.md).
