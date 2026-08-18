# `cleanup-unused-disks.sh`

[Back to helper list](../README.md) · [View script](../cleanup-unused-disks.sh) · [Raw usage](./cleanup-unused-disks.sh.usage)

## Purpose

List or delete selected/all `unusedN` disks from a QEMU VM with shared-reference checks.

## Usage

Run the built-in help without performing the operation:

```sh
./cleanup-unused-disks.sh --help
```

The current built-in help is:

```text
Usage: cleanup-unused-disks.sh <vmid> [unusedN ... | --all] [dryrun]
Dry-run:
  Add dryrun or --dryrun anywhere on the command line.
  Read-only preflight checks still run, but modifying commands are printed
  instead of executed and mutation-dependent verification is simulated.
```

The same output is stored verbatim in [`cleanup-unused-disks.sh.usage`](./cleanup-unused-disks.sh.usage).

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/cleanup-unused-disks.sh" -O "cleanup-unused-disks.sh" && chmod +x "cleanup-unused-disks.sh"
```

## Examples

```sh
./cleanup-unused-disks.sh 123 --all dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
cleanup-unused-disks.sh 3.0.0 (project 3.4.7)
```

This page documents the helper as shipped in project **v3.4.7**.
