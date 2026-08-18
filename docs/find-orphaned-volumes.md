# `find-orphaned-volumes.sh`

[Back to helper list](../README.md) · [View script](../find-orphaned-volumes.sh) · [Raw usage](./find-orphaned-volumes.sh.usage)

## Purpose

Find unreferenced Proxmox-managed `vm-VMID-disk-N` and `base-VMID-disk-N` LVM volumes.

## Usage

Run the built-in help without performing the operation:

```sh
./find-orphaned-volumes.sh --help
```

The current built-in help is:

```text
Usage: find-orphaned-volumes.sh [volume-group] [dryrun]
Dry-run:
  Add dryrun or --dryrun anywhere on the command line.
  Read-only preflight checks still run, but modifying commands are printed
  instead of executed and mutation-dependent verification is simulated.
```

The same output is stored verbatim in [`find-orphaned-volumes.sh.usage`](./find-orphaned-volumes.sh.usage).

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/find-orphaned-volumes.sh" -O "find-orphaned-volumes.sh" && chmod +x "find-orphaned-volumes.sh"
```

## Examples

```sh
./find-orphaned-volumes.sh pve
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
find-orphaned-volumes.sh 3.5.1 (project 3.5.1)
```

This page documents the helper as shipped in project **v3.5.1**.
