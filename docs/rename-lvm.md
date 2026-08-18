# `rename-lvm.sh`

[Back to helper list](../README.md) · [View script](../rename-lvm.sh) · [Raw usage](./rename-lvm.sh.usage)

## Purpose

Rename an LVM logical volume after validating its source and destination names.

## Usage

Run the built-in help without performing the operation:

```sh
./rename-lvm.sh --help
```

The current built-in help is:

```text
rename-lvm.sh 3.0.1 (project 3.4.7)

USAGE
  rename-lvm.sh <source-lv-path> <new-name> [dryrun]
  rename-lvm.sh <volume-group> <old-name> <new-name> [dryrun]

EXAMPLES
  rename-lvm.sh /dev/thinvg/vm-123-disk-1 vm-123-disk-1-old
  rename-lvm.sh thinvg vm-123-disk-1 vm-123-disk-1-old

Dry-run:
  Add dryrun or --dryrun anywhere on the command line.
  Read-only preflight checks still run, but modifying commands are printed
  instead of executed and mutation-dependent verification is simulated.
```

The same output is stored verbatim in [`rename-lvm.sh.usage`](./rename-lvm.sh.usage).

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/rename-lvm.sh" -O "rename-lvm.sh" && chmod +x "rename-lvm.sh"
```

## Examples

```sh
./rename-lvm.sh /dev/pve/vm-123-disk-0 vm-123-disk-0-old dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
rename-lvm.sh 3.0.1 (project 3.4.7)
```

This page documents the helper as shipped in project **v3.4.7**.
