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

```text
move-lvm.sh 3.4.7 (project 3.4.7)

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

Dry-run:
  Add dryrun or --dryrun anywhere on the command line.
  Read-only preflight checks still run, but modifying commands are printed
  instead of executed and mutation-dependent verification is simulated.
```

The same output is stored verbatim in [`move-lvm.sh.usage`](./move-lvm.sh.usage).

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/move-lvm.sh" -O "move-lvm.sh" && chmod +x "move-lvm.sh"
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
move-lvm.sh 3.4.7 (project 3.4.7)
```

This page documents the helper as shipped in project **v3.4.7**.
