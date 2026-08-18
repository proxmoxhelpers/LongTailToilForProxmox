# `bulk-change-vm-storage.sh`

[Back to helper list](../README.md) · [View script](../bulk-change-vm-storage.sh) · [Raw usage](./bulk-change-vm-storage.sh.usage)

## Purpose

Move matching VM disks from one Proxmox storage ID to another across multiple VMIDs.

## Usage

Run the built-in help without performing the operation:

```sh
./bulk-change-vm-storage.sh --help
```

The current built-in help is:

```text
Usage: bulk-change-vm-storage.sh <source-storage> <destination-storage> <vmid>... [dryrun]
Dry-run:
  Add dryrun or --dryrun anywhere on the command line.
  Read-only preflight checks still run, but modifying commands are printed
  instead of executed and mutation-dependent verification is simulated.
```

The same output is stored verbatim in [`bulk-change-vm-storage.sh.usage`](./bulk-change-vm-storage.sh.usage).

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/bulk-change-vm-storage.sh" -O "bulk-change-vm-storage.sh" && chmod +x "bulk-change-vm-storage.sh"
```

## Examples

```sh
./bulk-change-vm-storage.sh local-lvm fast-lvm 123 124 125 dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
bulk-change-vm-storage.sh 3.5.1 (project 3.5.1)
```

This page documents the helper as shipped in project **v3.5.1**.
