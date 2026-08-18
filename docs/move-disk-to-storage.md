# `move-disk-to-storage.sh`

[Back to helper list](../README.md) · [View script](../move-disk-to-storage.sh) · [Raw usage](./move-disk-to-storage.sh.usage)

## Purpose

Move one QEMU VM disk to another configured Proxmox storage using `qm move_disk`.

## Usage

Run the built-in help without performing the operation:

```sh
./move-disk-to-storage.sh --help
```

The current built-in help is:

```text
Usage: move-disk-to-storage.sh <vmid> <disk-slot> <destination-storage> [dryrun]
Dry-run:
  Add dryrun or --dryrun anywhere on the command line.
  Read-only preflight checks still run, but modifying commands are printed
  instead of executed and mutation-dependent verification is simulated.
```

The same output is stored verbatim in [`move-disk-to-storage.sh.usage`](./move-disk-to-storage.sh.usage).

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/move-disk-to-storage.sh" -O "move-disk-to-storage.sh" && chmod +x "move-disk-to-storage.sh"
```

## Examples

```sh
./move-disk-to-storage.sh 123 scsi0 fast-lvm dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
move-disk-to-storage.sh 3.5.1 (project 3.5.1)
```

This page documents the helper as shipped in project **v3.5.1**.
