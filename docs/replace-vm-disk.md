# `replace-vm-disk.sh`

[Back to helper list](../README.md) · [View script](../replace-vm-disk.sh) · [Raw usage](./replace-vm-disk.sh.usage)

## Purpose

Replace a VM disk slot with an existing replacement LVM volume while retaining the slot's disk options.

## Usage

Run the built-in help without performing the operation:

```sh
./replace-vm-disk.sh --help
```

The current built-in help is:

```text
Usage: replace-vm-disk.sh <vmid> <disk-slot> <replacement-lv-path> [dryrun]
Dry-run:
  Add dryrun or --dryrun anywhere on the command line.
  Read-only preflight checks still run, but modifying commands are printed
  instead of executed and mutation-dependent verification is simulated.
```

The same output is stored verbatim in [`replace-vm-disk.sh.usage`](./replace-vm-disk.sh.usage).

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/replace-vm-disk.sh" -O "replace-vm-disk.sh" && chmod +x "replace-vm-disk.sh"
```

## Examples

```sh
./replace-vm-disk.sh 123 scsi0 /dev/pve/vm-123-disk-9 dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
replace-vm-disk.sh 3.5.1 (project 3.5.1)
```

This page documents the helper as shipped in project **v3.5.1**.
