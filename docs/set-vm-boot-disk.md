# `set-vm-boot-disk.sh`

[Back to helper list](../README.md) · [View script](../set-vm-boot-disk.sh) · [Raw usage](./set-vm-boot-disk.sh.usage)

## Purpose

Put a selected VM disk slot first in the QEMU boot order.

## Usage

Run the built-in help without performing the operation:

```sh
./set-vm-boot-disk.sh --help
```

The current built-in help is:

```text
Usage: set-vm-boot-disk.sh <vmid> <disk-slot> [dryrun]
Dry-run:
  Add dryrun or --dryrun anywhere on the command line.
  Read-only preflight checks still run, but modifying commands are printed
  instead of executed and mutation-dependent verification is simulated.
```

The same output is stored verbatim in [`set-vm-boot-disk.sh.usage`](./set-vm-boot-disk.sh.usage).

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/set-vm-boot-disk.sh" -O "set-vm-boot-disk.sh" && chmod +x "set-vm-boot-disk.sh"
```

## Examples

```sh
./set-vm-boot-disk.sh 123 scsi0 dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
set-vm-boot-disk.sh 3.5.1 (project 3.5.1)
```

This page documents the helper as shipped in project **v3.5.1**.
