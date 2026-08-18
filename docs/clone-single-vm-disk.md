# `clone-single-vm-disk.sh`

[Back to helper list](../README.md) · [View script](../clone-single-vm-disk.sh) · [Raw usage](./clone-single-vm-disk.sh.usage)

## Purpose

Clone one disk of a QEMU VM and attach the independent copy back to that VM.

## Usage

Run the built-in help without performing the operation:

```sh
./clone-single-vm-disk.sh --help
```

The current built-in help is:

```text
Usage: clone-single-vm-disk.sh <vmid> <disk-slot> [destination-vg] [dryrun]
Dry-run:
  Add dryrun or --dryrun anywhere on the command line.
  Read-only preflight checks still run, but modifying commands are printed
  instead of executed and mutation-dependent verification is simulated.
```

The same output is stored verbatim in [`clone-single-vm-disk.sh.usage`](./clone-single-vm-disk.sh.usage).

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/clone-single-vm-disk.sh" -O "clone-single-vm-disk.sh" && chmod +x "clone-single-vm-disk.sh"
```

## Examples

```sh
./clone-single-vm-disk.sh 123 scsi0 fastvg dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
clone-single-vm-disk.sh 3.5.1 (project 3.5.1)
```

This page documents the helper as shipped in project **v3.5.1**.
