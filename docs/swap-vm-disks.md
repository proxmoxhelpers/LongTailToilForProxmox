# `swap-vm-disks.sh`

[Back to helper list](../README.md) · [View script](../swap-vm-disks.sh) · [Raw usage](./swap-vm-disks.sh.usage)

## Purpose

Swap the complete configuration values of two VM disk slots.

## Usage

Run the built-in help without performing the operation:

```sh
./swap-vm-disks.sh --help
```

The current built-in help is:

```text
Usage: swap-vm-disks.sh <vmid> <slot-a> <slot-b> [dryrun]
Dry-run:
  Add dryrun or --dryrun anywhere on the command line.
  Read-only preflight checks still run, but modifying commands are printed
  instead of executed and mutation-dependent verification is simulated.
```

The same output is stored verbatim in [`swap-vm-disks.sh.usage`](./swap-vm-disks.sh.usage).

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/swap-vm-disks.sh" -O "swap-vm-disks.sh" && chmod +x "swap-vm-disks.sh"
```

## Examples

```sh
./swap-vm-disks.sh 123 scsi0 scsi1 dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
swap-vm-disks.sh 3.5.1 (project 3.5.1)
```

This page documents the helper as shipped in project **v3.5.1**.
