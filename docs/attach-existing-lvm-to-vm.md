# `attach-existing-lvm-to-vm.sh`

[Back to helper list](../README.md) · [View script](../attach-existing-lvm-to-vm.sh) · [Raw usage](./attach-existing-lvm-to-vm.sh.usage)

## Purpose

Attach an existing LVM volume to a QEMU VM as a SCSI disk without copying it.

## Usage

Run the built-in help without performing the operation:

```sh
./attach-existing-lvm-to-vm.sh --help
```

The current built-in help is:

```text
Usage: attach-existing-lvm-to-vm.sh <full-lv-path> <vmid> [scsiN] [dryrun]
Dry-run:
  Add dryrun or --dryrun anywhere on the command line.
  Read-only preflight checks still run, but modifying commands are printed
  instead of executed and mutation-dependent verification is simulated.
```

The same output is stored verbatim in [`attach-existing-lvm-to-vm.sh.usage`](./attach-existing-lvm-to-vm.sh.usage).

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/attach-existing-lvm-to-vm.sh" -O "attach-existing-lvm-to-vm.sh" && chmod +x "attach-existing-lvm-to-vm.sh"
```

## Examples

```sh
./attach-existing-lvm-to-vm.sh /dev/pve/vm-123-disk-2 123 scsi2 dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
attach-existing-lvm-to-vm.sh 3.0.0 (project 3.4.7)
```

This page documents the helper as shipped in project **v3.4.7**.
