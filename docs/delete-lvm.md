# `delete-lvm.sh`

[Back to helper list](../README.md) · [View script](../delete-lvm.sh) · [Raw usage](./delete-lvm.sh.usage)

## Purpose

Delete an LVM logical volume with exact `DELETE` confirmation and post-delete verification; cancellation exits non-zero for automation-safe refusal handling.

## Usage

Run the built-in help without performing the operation:

```sh
./delete-lvm.sh --help
```

The current built-in help is:

```text
delete-lvm.sh 3.5.1 (project 3.5.1)

USAGE
  delete-lvm.sh <lvm-volume-path> [dryrun]

EXAMPLE
  delete-lvm.sh /dev/thinvg/vm-123-disk-1-copy

LIST VOLUMES
  lvs --noheadings -o lv_path | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'

Dry-run:
  Add dryrun or --dryrun anywhere on the command line.
  Read-only preflight checks still run, but modifying commands are printed
  instead of executed and mutation-dependent verification is simulated.
```

The same output is stored verbatim in [`delete-lvm.sh.usage`](./delete-lvm.sh.usage).

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/delete-lvm.sh" -O "delete-lvm.sh" && chmod +x "delete-lvm.sh"
```

## Examples

```sh
./delete-lvm.sh /dev/pve/vm-123-disk-0-old dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
delete-lvm.sh 3.5.1 (project 3.5.1)
```

This page documents the helper as shipped in project **v3.5.1**.
