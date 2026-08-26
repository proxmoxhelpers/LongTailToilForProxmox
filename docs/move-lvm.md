# `move-lvm.sh`

[Back to helper list](../README.md) · [View script](../move-lvm.sh) · [Raw usage](./move-lvm.sh.usage)

## Purpose

Rename an LV in place within a VG, or copy-verify-delete it safely when moving across VGs.

## Usage

Run the built-in help without performing the operation:

```sh
./move-lvm.sh --help
```

The current built-in help is:

<!-- BEGIN LIVE HELP -->
```text
move-lvm.sh 3.7.1 (project 3.7.1)

USAGE
  move-lvm.sh <source-lv-path> <destination-lv-path> [dryrun]

DESCRIPTION
  Same-VG moves use lvrename in place. Cross-VG moves create and verify an
  independent copy first, then remove the source only after verification.
  An inactive cross-VG source LV is temporarily activated only for the copy
  and restored before the verified source is removed.

EXAMPLES
  move-lvm.sh /dev/thinvg/vm-123-disk-1 /dev/thinvg/vm-123-disk-1-old
  move-lvm.sh /dev/thinvg/vm-123-disk-1 /dev/fastvg/vm-123-disk-1

HELP
  -h, -?, /h, /?, --help  Show this help and exit.
  --version                Show script and project versions and exit.

DRY-RUN
  Forms: dryrun, --dryrun.
  Dry-run: no system changes are made; modifying commands are printed instead of executed.
```
<!-- END LIVE HELP -->

The same output is stored verbatim in [`move-lvm.sh.usage`](./move-lvm.sh.usage).

## Test coverage

- Integration reference: `20-lvm.sh`
- The static suite verifies this helper's POSIX syntax, standalone help/version
  behavior, help aliases, documented parser options, live-help snapshot, and
  documentation synchronization.
- See [`tests/TEST-MATRIX.md`](../tests/TEST-MATRIX.md) for real/negative coverage.

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/move-lvm.sh" -O "move-lvm.sh" && chmod +x "move-lvm.sh"
```

## Examples

```sh
./move-lvm.sh /dev/pve/vm-123-disk-0 /dev/fastvg/vm-123-disk-0 dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
move-lvm.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.
