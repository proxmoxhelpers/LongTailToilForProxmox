# `list-vm-disks.sh`

[Back to helper list](../README.md) · [View script](../list-vm-disks.sh) · [Raw usage](./list-vm-disks.sh.usage)

## Purpose

List a QEMU VM's configured disks, resolved storage paths and available LVM metadata.

## Usage

Run the built-in help without performing the operation:

```sh
./list-vm-disks.sh --help
```

The current built-in help is:

```text
list-vm-disks.sh 3.0.0 (project 3.4.7)

USAGE
  list-vm-disks.sh <vmid> [dryrun]

DESCRIPTION
  Lists storage-backed disks configured on a local QEMU VM, including
  resolved paths and LVM metadata where available.

Dry-run:
  Add dryrun or --dryrun anywhere on the command line.
  Read-only preflight checks still run, but modifying commands are printed
  instead of executed and mutation-dependent verification is simulated.
```

The same output is stored verbatim in [`list-vm-disks.sh.usage`](./list-vm-disks.sh.usage).

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/list-vm-disks.sh" -O "list-vm-disks.sh" && chmod +x "list-vm-disks.sh"
```

## Examples

```sh
./list-vm-disks.sh 123
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
list-vm-disks.sh 3.0.0 (project 3.4.7)
```

This page documents the helper as shipped in project **v3.4.7**.
