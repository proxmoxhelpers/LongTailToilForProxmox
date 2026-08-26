# `flatten-vm-disk.sh`

[Back to helper list](../README.md) · [View script](../flatten-vm-disk.sh) · [Raw usage](./flatten-vm-disk.sh.usage)

## Purpose

Replaces an LVM-thin snapshot/clone disk with an independent thin copy in the same pool. The VM must be stopped and its config must not contain snapshots. The original linked volume is preserved as an unusedN entry. New content and the new LV identity are verified before the slot is changed. If a later step fails, the original slot is restored and only the UUID-proven incomplete LV created by this invocation is eligible for cleanup.

## Usage and live help

The built-in help is available without performing the operation:

```sh
./flatten-vm-disk.sh --help
```

<!-- BEGIN LIVE HELP -->
```text
flatten-vm-disk.sh 3.7.1 (project 3.7.1)

USAGE
  flatten-vm-disk.sh <VMID> <slot> [dryrun|--preflight]

DESCRIPTION
  Replaces an LVM-thin snapshot/clone disk with an independent thin copy in the
  same pool. The VM must be stopped and its config must not contain snapshots.
  The original linked volume is preserved as an unusedN entry. New content and
  the new LV identity are verified before the slot is changed. If a later step
  fails, the original slot is restored and only the UUID-proven incomplete LV
  created by this invocation is eligible for cleanup.

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

The same output is stored verbatim in [`flatten-vm-disk.sh.usage`](./flatten-vm-disk.sh.usage) and is checked byte-for-byte by the static suite.

## Safety and behavior

- `--help` and `--version` are handled before privilege/environment gates.
- `dryrun`, `--dryrun`, `--plan`, and `--preflight` use the non-mutating plan path; read-only helpers remain read-only.
- `--no-color` disables ANSI output and `--quiet` reduces non-essential LongTail output where supported.
- Ambiguous guest, slot, storage, or LVM identities are refused rather than guessed.
- For mutating helpers, preflight is completed before the first mutation and postconditions are verified after the operation.
- Integration safety/variant coverage: Safety/refusal and postcondition coverage appropriate to the helper; storage identity is verified independently.

## Test coverage

- Integration group: [`65-qol-disk-config.sh`](../tests/groups/65-qol-disk-config.sh)
- Positive / real coverage: Dry-run immutability plus disposable Proxmox/LVM fixture coverage for the helper's primary workflow.
- Negative / variant coverage: Safety/refusal and postcondition coverage appropriate to the helper; storage identity is verified independently.

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/flatten-vm-disk.sh" -O "flatten-vm-disk.sh" && chmod +x "flatten-vm-disk.sh"
```

## Source documentation

The script is standalone. Function comment blocks follow the project POSIX style guide; every argument-taking function documents its call syntax with `Call:` or the sanctioned full-form `Usage:` field.

## Version

```text
flatten-vm-disk.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.

## Related project guidance

See the [POSIX shell style guide](./POSIX-SHELL-STYLE-GUIDE-v3.md), [Proxmox scripting lessons learned](./PROXMOX-SHELL-SCRIPTING-LESSONS-LEARNED.md), and [testing documentation](./testing/README.md).
