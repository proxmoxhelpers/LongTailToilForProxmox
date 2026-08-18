# `list-all-vm-lvm.sh`

[Back to helper list](../README.md) · [View script](../list-all-vm-lvm.sh) · [Raw usage](./list-all-vm-lvm.sh.usage)

## Purpose

List every LVM volume referenced by QEMU/LXC guests grouped under its VMID, then show all remaining LVM volumes.

## Usage

Run the built-in help without performing the operation:

```sh
./list-all-vm-lvm.sh --help
```

The current built-in help is:

```text
list-all-vm-lvm.sh 1.0.0 (project 3.4.7)

USAGE
  list-all-vm-lvm.sh [dryrun]

DESCRIPTION
  Lists every LVM logical volume referenced by Proxmox QEMU/LXC guests,
  grouped under the guest VMID, followed by all remaining LVM volumes.

  "Remaining" includes normal host/system LVs and orphaned VM-style LVs
  that are not referenced by any visible Proxmox guest configuration.

Dry-run:
  Add dryrun or --dryrun anywhere on the command line.
  Read-only preflight checks still run, but modifying commands are printed
  instead of executed and mutation-dependent verification is simulated.
```

The same output is stored verbatim in [`list-all-vm-lvm.sh.usage`](./list-all-vm-lvm.sh.usage).

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/list-all-vm-lvm.sh" -O "list-all-vm-lvm.sh" && chmod +x "list-all-vm-lvm.sh"
```

## Examples

```sh
./list-all-vm-lvm.sh
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
list-all-vm-lvm.sh 1.0.0 (project 3.4.7)
```

This page documents the helper as shipped in project **v3.4.7**.
