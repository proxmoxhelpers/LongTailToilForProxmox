# `change-disk-bus.sh`

[Back to helper list](../README.md) · [View script](../change-disk-bus.sh) · [Raw usage](./change-disk-bus.sh.usage)

## Purpose

Move a VM disk configuration from one bus/slot to another while preserving destination-compatible disk options; incompatible `iothread` is removed with a warning when moving to SATA/IDE.

## Usage

Run the built-in help without performing the operation:

```sh
./change-disk-bus.sh --help
```

The current built-in help is:

```text
Usage: change-disk-bus.sh <vmid> <source-slot> [destination-slot|scsi|virtio|sata|ide] [dryrun]
Dry-run:
  Add dryrun or --dryrun anywhere on the command line.
  Read-only preflight checks still run, but modifying commands are printed
  instead of executed and mutation-dependent verification is simulated.
```

The same output is stored verbatim in [`change-disk-bus.sh.usage`](./change-disk-bus.sh.usage).

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/change-disk-bus.sh" -O "change-disk-bus.sh" && chmod +x "change-disk-bus.sh"
```

## Examples

```sh
./change-disk-bus.sh 123 scsi1 sata0 dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
change-disk-bus.sh 3.0.0 (project 3.4.7)
```

This page documents the helper as shipped in project **v3.4.7**.
