# `mount-vm-root.sh`

[Back to helper list](../README.md) · [View script](../mount-vm-root.sh) · [Raw usage](./mount-vm-root.sh.usage)

## Purpose

Mount a VM disk and identify the filesystem that most likely contains the guest's Linux root.

## Usage

Run the built-in help without performing the operation:

```sh
./mount-vm-root.sh --help
```

The current built-in help is:

```text
Usage: mount-vm-root.sh <vmid> <disk-slot> [mount-root] [--ro|--rw] [dryrun]
Dry-run:
  Add dryrun or --dryrun anywhere on the command line.
  Read-only preflight checks still run, but modifying commands are printed
  instead of executed and mutation-dependent verification is simulated.
```

The same output is stored verbatim in [`mount-vm-root.sh.usage`](./mount-vm-root.sh.usage).

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/mount-vm-root.sh" -O "mount-vm-root.sh" && chmod +x "mount-vm-root.sh"
```

## Examples

```sh
./mount-vm-root.sh 123 scsi0 /mnt/vm123 --ro
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
mount-vm-root.sh 3.0.0 (project 3.4.7)
```

This page documents the helper as shipped in project **v3.4.7**.
