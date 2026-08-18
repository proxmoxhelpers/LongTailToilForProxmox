# `change-vmid-of-vm.sh`

[Back to helper list](../README.md) · [View script](../change-vmid-of-vm.sh) · [Raw usage](./change-vmid-of-vm.sh.usage)

## Purpose

Change the VMID of a stopped local QEMU VM or LXC container on LVM/LVM-thin, renaming both `vm-OLDID-*` and template `base-OLDID-*` volumes while preserving their family, with preflight checks, backup, verification and rollback.

## Usage

Run the built-in help without performing the operation:

```sh
./change-vmid-of-vm.sh --help
```

The current built-in help is:

```text
change-vmid-of-vm.sh 3.4.1 (project 3.4.7)

USAGE
  change-vmid-of-vm.sh <old-vmid> <new-vmid> [dryrun]

DESCRIPTION
  Changes the VMID of a local QEMU VM or LXC container when all referenced
  vm-OLDID-* / base-OLDID-* storage volumes are LVM/LVM-thin and can be renamed in place.

  Preflight checks destination VMID availability, locks, snapshots, volume
  ownership and name collisions before mutation. The guest is left stopped.

EXAMPLE
  change-vmid-of-vm.sh 123 456

NOTES
  HA, replication, ACLs, backup jobs, pools, hooks and external automation are
  not rewritten automatically and must be reviewed after a successful change.

Dry-run:
  Add dryrun or --dryrun anywhere on the command line.
  Read-only preflight checks still run, but modifying commands are printed
  instead of executed and mutation-dependent verification is simulated.
```

The same output is stored verbatim in [`change-vmid-of-vm.sh.usage`](./change-vmid-of-vm.sh.usage).

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/change-vmid-of-vm.sh" -O "change-vmid-of-vm.sh" && chmod +x "change-vmid-of-vm.sh"
```

## Examples

```sh
./change-vmid-of-vm.sh 123 456 dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
change-vmid-of-vm.sh 3.4.1 (project 3.4.7)
```

This page documents the helper as shipped in project **v3.4.7**.
