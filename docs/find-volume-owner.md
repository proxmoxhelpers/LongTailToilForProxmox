# `find-volume-owner.sh`

[Back to helper list](../README.md) · [View script](../find-volume-owner.sh) · [Raw usage](./find-volume-owner.sh.usage)

## Purpose

Find which local guest configuration references a specific LVM path or Proxmox volume ID.

## Usage

Run the built-in help without performing the operation:

```sh
./find-volume-owner.sh --help
```

The current built-in help is:

```text
Usage: find-volume-owner.sh <full-lv-path|storage:volume> [dryrun]
Dry-run:
  Add dryrun or --dryrun anywhere on the command line.
  Read-only preflight checks still run, but modifying commands are printed
  instead of executed and mutation-dependent verification is simulated.
```

The same output is stored verbatim in [`find-volume-owner.sh.usage`](./find-volume-owner.sh.usage).

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/find-volume-owner.sh" -O "find-volume-owner.sh" && chmod +x "find-volume-owner.sh"
```

## Examples

```sh
./find-volume-owner.sh /dev/pve/vm-123-disk-0
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
find-volume-owner.sh 3.0.0 (project 3.4.7)
```

This page documents the helper as shipped in project **v3.4.7**.
