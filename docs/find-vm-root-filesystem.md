# `find-vm-root-filesystem.sh`

[Back to helper list](../README.md) · [View script](../find-vm-root-filesystem.sh) · [Raw usage](./find-vm-root-filesystem.sh.usage)

## Purpose

Finds Linux-filesystem signature candidates across a VM's disks without mounting them. It reports slot/partition/offset/size but does not claim which candidate actually contains /. Normal mode may temporarily activate inactive LVM disks with -K and restores them; dry-run/preflight never activates them.

## Usage and live help

The built-in help is available without performing the operation:

```sh
./find-vm-root-filesystem.sh --help
```

<!-- BEGIN LIVE HELP -->
```text
find-vm-root-filesystem.sh 3.7.1 (project 3.7.1)

USAGE
  find-vm-root-filesystem.sh <VMID>

DESCRIPTION
  Finds Linux-filesystem signature candidates across a VM's disks without
  mounting them. It reports slot/partition/offset/size but does not claim which
  candidate actually contains /. Normal mode may temporarily activate inactive
  LVM disks with -K and restores them; dry-run/preflight never activates them.

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

The same output is stored verbatim in [`find-vm-root-filesystem.sh.usage`](./find-vm-root-filesystem.sh.usage) and is checked byte-for-byte by the static suite.

## Safety and behavior

- `--help` and `--version` are handled before privilege/environment gates.
- `dryrun`, `--dryrun`, `--plan`, and `--preflight` use the non-mutating plan path; read-only helpers remain read-only.
- `--no-color` disables ANSI output and `--quiet` reduces non-essential LongTail output where supported.
- Ambiguous guest, slot, storage, or LVM identities are refused rather than guessed.
- For mutating helpers, preflight is completed before the first mutation and postconditions are verified after the operation.
- Integration safety/variant coverage: No mutation path; findings and selector/refusal behavior are checked where applicable.

## Test coverage

- Integration group: [`15-qol-inspection.sh`](../tests/groups/15-qol-inspection.sh)
- Positive / real coverage: Read-only execution against disposable guest/LVM fixtures.
- Negative / variant coverage: No mutation path; findings and selector/refusal behavior are checked where applicable.

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/find-vm-root-filesystem.sh" -O "find-vm-root-filesystem.sh" && chmod +x "find-vm-root-filesystem.sh"
```

## Source documentation

The script is standalone. Function comment blocks follow the project POSIX style guide; every argument-taking function documents its call syntax with `Call:` or the sanctioned full-form `Usage:` field.

## Version

```text
find-vm-root-filesystem.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.

## Related project guidance

See the [POSIX shell style guide](./POSIX-SHELL-STYLE-GUIDE-v3.md), [Proxmox scripting lessons learned](./PROXMOX-SHELL-SCRIPTING-LESSONS-LEARNED.md), and [testing documentation](./testing/README.md).
