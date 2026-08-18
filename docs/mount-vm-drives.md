# `mount-vm-drives.sh`

[Back to helper list](../README.md) · [View script](../mount-vm-drives.sh) · [Raw usage](./mount-vm-drives.sh.usage)

## Purpose

Mount recognizable filesystems from an LVM-backed VM disk, using `kpartx` for partitions and read-only mode by default.

## Usage

Run the built-in help without performing the operation:

```sh
./mount-vm-drives.sh --help
```

The current built-in help is:

```text
mount-vm-drives.sh 3.0.0 (project 3.4.7)

USAGE
  mount-vm-drives.sh <lvm-volume-path> [mount-root] [--ro|--rw] [dryrun]

DESCRIPTION
  Exposes and mounts recognizable filesystems from an LVM-backed VM disk.
  Partitioned media is mapped through kpartx; a filesystem directly on the LV
  is mounted as part1. Read-only is the default.

EXAMPLES
  mount-vm-drives.sh /dev/thinvg/vm-123-disk-1
  mount-vm-drives.sh /dev/thinvg/vm-123-disk-1 /mnt/vm123
  mount-vm-drives.sh /dev/thinvg/vm-123-disk-1 --rw

Dry-run:
  Add dryrun or --dryrun anywhere on the command line.
  Read-only preflight checks still run, but modifying commands are printed
  instead of executed and mutation-dependent verification is simulated.
```

The same output is stored verbatim in [`mount-vm-drives.sh.usage`](./mount-vm-drives.sh.usage).

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/mount-vm-drives.sh" -O "mount-vm-drives.sh" && chmod +x "mount-vm-drives.sh"
```

## Examples

```sh
./mount-vm-drives.sh /dev/pve/vm-123-disk-0 /mnt/vm123 --ro
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
mount-vm-drives.sh 3.0.0 (project 3.4.7)
```

This page documents the helper as shipped in project **v3.4.7**.
