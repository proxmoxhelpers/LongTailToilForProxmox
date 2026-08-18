# `detach-disk-from-vm.sh`

[Back to helper list](../README.md) · [View script](../detach-disk-from-vm.sh) · [Raw usage](./detach-disk-from-vm.sh.usage)

## Purpose

Detach a VM disk slot while preserving the backing volume as an `unusedN` entry.

## Usage

Run the built-in help without performing the operation:

```sh
./detach-disk-from-vm.sh --help
```

The current built-in help is:

```text
Usage: detach-disk-from-vm.sh <vmid> <disk-slot> [dryrun]
Dry-run:
  Add dryrun or --dryrun anywhere on the command line.
  Read-only preflight checks still run, but modifying commands are printed
  instead of executed and mutation-dependent verification is simulated.
```

The same output is stored verbatim in [`detach-disk-from-vm.sh.usage`](./detach-disk-from-vm.sh.usage).

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/detach-disk-from-vm.sh" -O "detach-disk-from-vm.sh" && chmod +x "detach-disk-from-vm.sh"
```

## Examples

```sh
./detach-disk-from-vm.sh 123 scsi2 dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
detach-disk-from-vm.sh 3.0.0 (project 3.4.7)
```

This page documents the helper as shipped in project **v3.4.7**.
