# `convert-thin-to-regular-lv.sh`

[Back to helper list](../README.md) · [View script](../convert-thin-to-regular-lv.sh) · [Raw usage](./convert-thin-to-regular-lv.sh.usage)

## Purpose

Creates and byte-verifies an independent regular LV. The dd path never uses sparse writes, so untouched regular-LV extents are never assumed to read zero. Source is never deleted or converted in place.

## Usage and live help

The built-in help is available without performing the operation:

```sh
./convert-thin-to-regular-lv.sh --help
```

<!-- BEGIN LIVE HELP -->
```text
convert-thin-to-regular-lv.sh 3.7.1 (project 3.7.1)

USAGE
  convert-thin-to-regular-lv.sh <source-LV> <destination-VG> [new-LV-name] [dryrun|--preflight]

DESCRIPTION
  Creates and byte-verifies an independent regular LV. The dd path never uses
  sparse writes, so untouched regular-LV extents are never assumed to read zero.
  Source is never deleted or converted in place.

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

The same output is stored verbatim in [`convert-thin-to-regular-lv.sh.usage`](./convert-thin-to-regular-lv.sh.usage) and is checked byte-for-byte by the static suite.

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
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/convert-thin-to-regular-lv.sh" -O "convert-thin-to-regular-lv.sh" && chmod +x "convert-thin-to-regular-lv.sh"
```

## Source documentation

The script is standalone. Function comment blocks follow the project POSIX style guide; every argument-taking function documents its call syntax with `Call:` or the sanctioned full-form `Usage:` field.

## Version

```text
convert-thin-to-regular-lv.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.

## Related project guidance

See the [POSIX shell style guide](./POSIX-SHELL-STYLE-GUIDE-v3.md), [Proxmox scripting lessons learned](./PROXMOX-SHELL-SCRIPTING-LESSONS-LEARNED.md), and [testing documentation](./testing/README.md).
