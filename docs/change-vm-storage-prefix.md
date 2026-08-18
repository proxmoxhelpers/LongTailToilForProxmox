# `change-vm-storage-prefix.sh`

[Back to helper list](../README.md) · [View script](../change-vm-storage-prefix.sh) · [Raw usage](./change-vm-storage-prefix.sh.usage)

## Purpose

Rewrite an old Proxmox storage ID prefix to a new storage ID in affected local guest configurations.

## Usage

Run the built-in help without performing the operation:

```sh
./change-vm-storage-prefix.sh --help
```

The current built-in help is:

```text
Usage: change-vm-storage-prefix.sh <old-storage-id> <new-storage-id> [dryrun]
Dry-run:
  Add dryrun or --dryrun anywhere on the command line.
  Read-only preflight checks still run, but modifying commands are printed
  instead of executed and mutation-dependent verification is simulated.
```

The same output is stored verbatim in [`change-vm-storage-prefix.sh.usage`](./change-vm-storage-prefix.sh.usage).

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/change-vm-storage-prefix.sh" -O "change-vm-storage-prefix.sh" && chmod +x "change-vm-storage-prefix.sh"
```

## Examples

```sh
./change-vm-storage-prefix.sh old-lvm new-lvm dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
change-vm-storage-prefix.sh 3.0.0 (project 3.4.7)
```

This page documents the helper as shipped in project **v3.4.7**.
