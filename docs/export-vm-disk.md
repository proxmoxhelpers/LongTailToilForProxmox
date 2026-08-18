# `export-vm-disk.sh`

[Back to helper list](../README.md) · [View script](../export-vm-disk.sh) · [Raw usage](./export-vm-disk.sh.usage)

## Purpose

Export a QEMU VM disk to a raw or qcow2 image using `qemu-img`.

## Usage

Run the built-in help without performing the operation:

```sh
./export-vm-disk.sh --help
```

The current built-in help is:

```text
Usage: export-vm-disk.sh <vmid> <disk-slot> <output-file> [raw|qcow2] [dryrun]
Dry-run:
  Add dryrun or --dryrun anywhere on the command line.
  Read-only preflight checks still run, but modifying commands are printed
  instead of executed and mutation-dependent verification is simulated.
```

The same output is stored verbatim in [`export-vm-disk.sh.usage`](./export-vm-disk.sh.usage).

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/export-vm-disk.sh" -O "export-vm-disk.sh" && chmod +x "export-vm-disk.sh"
```

## Examples

```sh
./export-vm-disk.sh 123 scsi0 ./vm-123-scsi0.qcow2 qcow2 dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
export-vm-disk.sh 3.0.0 (project 3.4.7)
```

This page documents the helper as shipped in project **v3.4.7**.
