# `recover-vm-from-volumes.sh`

[Back to helper list](../README.md) · [View script](../recover-vm-from-volumes.sh) · [Raw usage](./recover-vm-from-volumes.sh.usage)

## Purpose

Recreate a basic QEMU VM configuration from existing `vm-VMID-disk-N` and/or `base-VMID-disk-N` LVM volumes.

## Usage

Run the built-in help without performing the operation:

```sh
./recover-vm-from-volumes.sh --help
```

The current built-in help is:

```text
Usage: recover-vm-from-volumes.sh <vmid> [volume-group] [dryrun]
Dry-run:
  Add dryrun or --dryrun anywhere on the command line.
  Read-only preflight checks still run, but modifying commands are printed
  instead of executed and mutation-dependent verification is simulated.
```

The same output is stored verbatim in [`recover-vm-from-volumes.sh.usage`](./recover-vm-from-volumes.sh.usage).

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/recover-vm-from-volumes.sh" -O "recover-vm-from-volumes.sh" && chmod +x "recover-vm-from-volumes.sh"
```

## Examples

```sh
./recover-vm-from-volumes.sh 456 pve dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
recover-vm-from-volumes.sh 3.5.1 (project 3.5.1)
```

This page documents the helper as shipped in project **v3.5.1**.
