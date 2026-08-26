# `copy-vm-disk-to-thin-lv.sh`

[Back to helper list](../README.md) · [View script](../copy-vm-disk-to-thin-lv.sh) · [Raw usage](./copy-vm-disk-to-thin-lv.sh.usage)

## Purpose

Creates an independent thin-LV copy of a VM disk and byte-verifies it. Sparse writes are used only because the destination is explicitly thin. The source VM must be stopped unless --allow-running explicitly accepts an inconsistent live-copy risk.

## Usage and live help

The built-in help is available without performing the operation:

```sh
./copy-vm-disk-to-thin-lv.sh --help
```

<!-- BEGIN LIVE HELP -->
```text
copy-vm-disk-to-thin-lv.sh 3.7.1 (project 3.7.1)

USAGE
  copy-vm-disk-to-thin-lv.sh <VMID> <slot> <destination-VG> [new-LV-name] [--pool POOL] [--allow-running] [dryrun|--preflight]

DESCRIPTION
  Creates an independent thin-LV copy of a VM disk and byte-verifies it.
  Sparse writes are used only because the destination is explicitly thin.
  The source VM must be stopped unless --allow-running explicitly accepts an inconsistent live-copy risk.

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

The same output is stored verbatim in [`copy-vm-disk-to-thin-lv.sh.usage`](./copy-vm-disk-to-thin-lv.sh.usage) and is checked byte-for-byte by the static suite.

## Safety and behavior

- `--help` and `--version` are handled before privilege/environment gates.
- `dryrun`, `--dryrun`, `--plan`, and `--preflight` use the non-mutating plan path; read-only helpers remain read-only.
- `--no-color` disables ANSI output and `--quiet` reduces non-essential LongTail output where supported.
- Ambiguous guest, slot, storage, or LVM identities are refused rather than guessed.
- For mutating helpers, preflight is completed before the first mutation and postconditions are verified after the operation.
- Integration safety/variant coverage: Safety/refusal and postcondition coverage appropriate to the helper; storage identity is verified independently.

## Test coverage

- Integration group: [`25-qol-lvm.sh`](../tests/groups/25-qol-lvm.sh)
- Positive / real coverage: Dry-run immutability plus disposable Proxmox/LVM fixture coverage for the helper's primary workflow.
- Negative / variant coverage: Safety/refusal and postcondition coverage appropriate to the helper; storage identity is verified independently.

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/copy-vm-disk-to-thin-lv.sh" -O "copy-vm-disk-to-thin-lv.sh" && chmod +x "copy-vm-disk-to-thin-lv.sh"
```

## Source documentation

The script is standalone. Function comment blocks follow the project POSIX style guide; every argument-taking function documents its call syntax with `Call:` or the sanctioned full-form `Usage:` field.

## Version

```text
copy-vm-disk-to-thin-lv.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.

## Related project guidance

See the [POSIX shell style guide](./POSIX-SHELL-STYLE-GUIDE-v3.md), [Proxmox scripting lessons learned](./PROXMOX-SHELL-SCRIPTING-LESSONS-LEARNED.md), and [testing documentation](./testing/README.md).
