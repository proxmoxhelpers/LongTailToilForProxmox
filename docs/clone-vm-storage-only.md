# `clone-vm-storage-only.sh`

[Back to helper list](../README.md) · [View script](../clone-vm-storage-only.sh) · [Raw usage](./clone-vm-storage-only.sh.usage)

## Purpose

Copies every active source disk into an existing destination QEMU VM while preserving source device slots and disk options. The destination must be stopped and snapshot-free; the source must be stopped unless `--hot` is explicitly accepted. Each source is converted to an invocation-owned temporary raw staging image before `qm importdisk`, because Proxmox rejects an LVM block device as an import-file argument. Imported guest-visible bytes are verified against the immutable staging image before attachment. Inactive source LVs are restored immediately after staging, temporary data is removed on all exit paths, and abnormal exits restore the destination config and remove only imported storage whose recorded physical identity is still proven unreferenced.

## Usage and live help

The built-in help is available without performing the operation:

```sh
./clone-vm-storage-only.sh --help
```

<!-- BEGIN LIVE HELP -->
```text
clone-vm-storage-only.sh 3.7.1 (project 3.7.1)

USAGE
  clone-vm-storage-only.sh <source-VMID> <destination-VMID> [--storage STORAGE] [--hot] [dryrun|--preflight]

DESCRIPTION
  Copies every active source disk into an existing destination QEMU VM, keeping
  the same device slots and disk options. The destination must be stopped and
  snapshot-free because generated unusedN entries are removed config-only.

  The source must also be stopped unless --hot explicitly accepts a
  non-quiesced copy. Each source is first converted to an invocation-owned
  temporary raw staging image, because qm importdisk requires a regular image
  file rather than an LVM block device. The imported guest-visible bytes are
  verified against that immutable staging image before attachment.

  In --hot mode the source may change while the staging image is created, so
  exact source post-copy equality is intentionally not claimed. Temporary
  staging data is removed on success and failure; set TMPDIR to a filesystem
  with sufficient temporary capacity for the largest source disk.

  Any abnormal exit after the first import restores the destination config from
  its backup. Imported storage is cleaned only when its recorded physical
  identity still matches and no guest physically references it.

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

The same output is stored verbatim in [`clone-vm-storage-only.sh.usage`](./clone-vm-storage-only.sh.usage) and is checked byte-for-byte by the static suite.

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
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/clone-vm-storage-only.sh" -O "clone-vm-storage-only.sh" && chmod +x "clone-vm-storage-only.sh"
```

## Source documentation

The script is standalone. Function comment blocks follow the project POSIX style guide; every argument-taking function documents its call syntax with `Call:` or the sanctioned full-form `Usage:` field.

## Version

```text
clone-vm-storage-only.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.

## Related project guidance

See the [POSIX shell style guide](./POSIX-SHELL-STYLE-GUIDE-v3.md), [Proxmox scripting lessons learned](./PROXMOX-SHELL-SCRIPTING-LESSONS-LEARNED.md), and [testing documentation](./testing/README.md).
