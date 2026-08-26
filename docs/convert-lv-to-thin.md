# `convert-lv-to-thin.sh`

[Back to helper list](../README.md) · [View script](../convert-lv-to-thin.sh) · [Raw usage](./convert-lv-to-thin.sh.usage)

## Purpose

Creates a new independent thin LV, copies all source bytes using sparse writes only because the destination is thin, and verifies with cmp. Source is never deleted or converted in place.

## Usage and live help

The built-in help is available without performing the operation:

```sh
./convert-lv-to-thin.sh --help
```

<!-- BEGIN LIVE HELP -->
```text
convert-lv-to-thin.sh 3.7.1 (project 3.7.1)

USAGE
  convert-lv-to-thin.sh <source-LV> <destination-VG> [new-LV-name] [--pool POOL] [dryrun|--preflight]

DESCRIPTION
  Creates a new independent thin LV, copies all source bytes using sparse writes
  only because the destination is thin, and verifies with cmp. Source is never
  deleted or converted in place.

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

The same output is stored verbatim in [`convert-lv-to-thin.sh.usage`](./convert-lv-to-thin.sh.usage) and is checked byte-for-byte by the static suite.

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
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/convert-lv-to-thin.sh" -O "convert-lv-to-thin.sh" && chmod +x "convert-lv-to-thin.sh"
```

## Source documentation

The script is standalone. Function comment blocks follow the project POSIX style guide; every argument-taking function documents its call syntax with `Call:` or the sanctioned full-form `Usage:` field.

## Version

```text
convert-lv-to-thin.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.

## Related project guidance

See the [POSIX shell style guide](./POSIX-SHELL-STYLE-GUIDE-v3.md), [Proxmox scripting lessons learned](./PROXMOX-SHELL-SCRIPTING-LESSONS-LEARNED.md), and [testing documentation](./testing/README.md).
