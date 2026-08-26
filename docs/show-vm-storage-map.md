# `show-vm-storage-map.sh`

[Back to helper list](../README.md) · [View script](../show-vm-storage-map.sh) · [Raw usage](./show-vm-storage-map.sh.usage)

## Purpose

Shows slot -> Proxmox volume -> resolved path -> LVM UUID/size/pool/origin for one QEMU VM or LXC container. The command is read-only.

## Usage and live help

The built-in help is available without performing the operation:

```sh
./show-vm-storage-map.sh --help
```

<!-- BEGIN LIVE HELP -->
```text
show-vm-storage-map.sh 3.7.1 (project 3.7.1)

USAGE
  show-vm-storage-map.sh <VMID> [--json|--tsv] [--quiet] [--no-color]

DESCRIPTION
  Shows slot -> Proxmox volume -> resolved path -> LVM UUID/size/pool/origin
  for one QEMU VM or LXC container. The command is read-only.

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

The same output is stored verbatim in [`show-vm-storage-map.sh.usage`](./show-vm-storage-map.sh.usage) and is checked byte-for-byte by the static suite.

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
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/show-vm-storage-map.sh" -O "show-vm-storage-map.sh" && chmod +x "show-vm-storage-map.sh"
```

## Source documentation

The script is standalone. Function comment blocks follow the project POSIX style guide; every argument-taking function documents its call syntax with `Call:` or the sanctioned full-form `Usage:` field.

## Version

```text
show-vm-storage-map.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.

## Related project guidance

See the [POSIX shell style guide](./POSIX-SHELL-STYLE-GUIDE-v3.md), [Proxmox scripting lessons learned](./PROXMOX-SHELL-SCRIPTING-LESSONS-LEARNED.md), and [testing documentation](./testing/README.md).
