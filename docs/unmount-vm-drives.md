# `unmount-vm-drives.sh`

[Back to helper list](../README.md) · [View script](../unmount-vm-drives.sh) · [Raw usage](./unmount-vm-drives.sh.usage)

## Purpose

Unmount filesystems belonging to an LVM-backed VM disk and safely remove its mapper/empty mount directories.

## Usage

Run the built-in help without performing the operation:

```sh
./unmount-vm-drives.sh --help
```

The current built-in help is:

```text
unmount-vm-drives.sh 3.0.1 (project 3.4.7)

USAGE
  unmount-vm-drives.sh <lvm-volume-path> [dryrun]

EXAMPLE
  unmount-vm-drives.sh /dev/thinvg/vm-123-disk-1

Dry-run:
  Add dryrun or --dryrun anywhere on the command line.
  Read-only preflight checks still run, but modifying commands are printed
  instead of executed and mutation-dependent verification is simulated.
```

The same output is stored verbatim in [`unmount-vm-drives.sh.usage`](./unmount-vm-drives.sh.usage).

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/unmount-vm-drives.sh" -O "unmount-vm-drives.sh" && chmod +x "unmount-vm-drives.sh"
```

## Examples

```sh
./unmount-vm-drives.sh /dev/pve/vm-123-disk-0
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
unmount-vm-drives.sh 3.0.1 (project 3.4.7)
```

This page documents the helper as shipped in project **v3.4.7**.
