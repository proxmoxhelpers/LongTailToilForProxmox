# `mount-vm-disk.sh`

[Back to helper list](../README.md) · [View script](../mount-vm-disk.sh) · [Raw usage](./mount-vm-disk.sh.usage)

## Purpose

Resolve a VM disk slot to its LVM device and mount the filesystems beneath a chosen mount root.

## Usage

Run the built-in help without performing the operation:

```sh
./mount-vm-disk.sh --help
```

The current built-in help is:

```text
Usage: mount-vm-disk.sh <vmid> <disk-slot> [mount-root] [--ro|--rw] [dryrun]
Dry-run:
  Add dryrun or --dryrun anywhere on the command line.
  Read-only preflight checks still run, but modifying commands are printed
  instead of executed and mutation-dependent verification is simulated.
```

The same output is stored verbatim in [`mount-vm-disk.sh.usage`](./mount-vm-disk.sh.usage).

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/mount-vm-disk.sh" -O "mount-vm-disk.sh" && chmod +x "mount-vm-disk.sh"
```

## Examples

```sh
./mount-vm-disk.sh 123 scsi0 /mnt/vm123 --ro
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
mount-vm-disk.sh 3.5.1 (project 3.5.1)
```

This page documents the helper as shipped in project **v3.5.1**.
