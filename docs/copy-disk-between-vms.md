# `copy-disk-between-vms.sh`

[Back to helper list](../README.md) · [View script](../copy-disk-between-vms.sh) · [Raw usage](./copy-disk-between-vms.sh.usage)

## Purpose

Copy one QEMU VM disk to another VM as an independent verified volume.

## Usage

Run the built-in help without performing the operation:

```sh
./copy-disk-between-vms.sh --help
```

The current built-in help is:

```text
Usage: copy-disk-between-vms.sh <source-vmid> <source-slot> <destination-vmid> [destination-vg] [dryrun]
Dry-run:
  Add dryrun or --dryrun anywhere on the command line.
  Read-only preflight checks still run, but modifying commands are printed
  instead of executed and mutation-dependent verification is simulated.
```

The same output is stored verbatim in [`copy-disk-between-vms.sh.usage`](./copy-disk-between-vms.sh.usage).

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/copy-disk-between-vms.sh" -O "copy-disk-between-vms.sh" && chmod +x "copy-disk-between-vms.sh"
```

## Examples

```sh
./copy-disk-between-vms.sh 123 scsi0 456 fastvg dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
copy-disk-between-vms.sh 3.5.1 (project 3.5.1)
```

This page documents the helper as shipped in project **v3.5.1**.
