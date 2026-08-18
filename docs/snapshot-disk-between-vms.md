# `snapshot-disk-between-vms.sh`

[Back to helper list](../README.md) · [View script](../snapshot-disk-between-vms.sh) · [Raw usage](./snapshot-disk-between-vms.sh.usage)

## Purpose

Create an LVM-thin snapshot of one VM disk and attach that linked snapshot to another VM.

## Usage

Run the built-in help without performing the operation:

```sh
./snapshot-disk-between-vms.sh --help
```

The current built-in help is:

```text
Usage: snapshot-disk-between-vms.sh <source-vmid> <source-slot> <destination-vmid> [dryrun]
Dry-run:
  Add dryrun or --dryrun anywhere on the command line.
  Read-only preflight checks still run, but modifying commands are printed
  instead of executed and mutation-dependent verification is simulated.
```

The same output is stored verbatim in [`snapshot-disk-between-vms.sh.usage`](./snapshot-disk-between-vms.sh.usage).

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/snapshot-disk-between-vms.sh" -O "snapshot-disk-between-vms.sh" && chmod +x "snapshot-disk-between-vms.sh"
```

## Examples

```sh
./snapshot-disk-between-vms.sh 123 scsi0 456 dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
snapshot-disk-between-vms.sh 3.3.1 (project 3.4.7)
```

This page documents the helper as shipped in project **v3.4.7**.
