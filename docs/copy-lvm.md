# `copy-lvm.sh`

[Back to helper list](../README.md) · [View script](../copy-lvm.sh) · [Raw usage](./copy-lvm.sh.usage)

## Purpose

Create and byte-verify an independent copy of an LVM/LVM-thin logical volume.

## Usage

Run the built-in help without performing the operation:

```sh
./copy-lvm.sh --help
```

The current built-in help is:

```text
copy-lvm.sh 3.4.7 (project 3.4.7)

USAGE
  copy-lvm.sh <source-lv-path> <destination-lv-path> [dryrun]

DESCRIPTION
  Creates a fully independent block-level copy. Both arguments are full LVM
  device paths. The destination must use /dev/<volume-group>/<new-lv-name>.

DESTINATION ALLOCATION
  same VG + thin source     use the source thin pool
  one thin pool in dest VG use that thin pool
  no thin pool in dest VG  create a regular LV
  multiple thin pools      refuse as ambiguous

SOURCE ACTIVATION
  If the source LV exists in LVM metadata but is inactive (for example a
  template/base LV), it is temporarily activated for the block copy and then
  restored to inactive. The helper does not change the LV permission.

EXAMPLES
  copy-lvm.sh /dev/thinvg/vm-123-disk-1 /dev/thinvg/vm-123-disk-1-copy
  copy-lvm.sh /dev/thinvg/vm-123-disk-1 /dev/fastvg/vm-123-disk-1

Dry-run:
  Add dryrun or --dryrun anywhere on the command line.
  Read-only preflight checks still run, but modifying commands are printed
  instead of executed and mutation-dependent verification is simulated.
```

The same output is stored verbatim in [`copy-lvm.sh.usage`](./copy-lvm.sh.usage).

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/copy-lvm.sh" -O "copy-lvm.sh" && chmod +x "copy-lvm.sh"
```

## Examples

```sh
./copy-lvm.sh /dev/pve/vm-123-disk-0 /dev/fastvg/vm-123-disk-0-copy dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
copy-lvm.sh 3.4.7 (project 3.4.7)
```

This page documents the helper as shipped in project **v3.4.7**.
