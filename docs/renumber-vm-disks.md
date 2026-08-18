# `renumber-vm-disks.sh`

[Back to helper list](../README.md) · [View script](../renumber-vm-disks.sh) · [Raw usage](./renumber-vm-disks.sh.usage)

## Purpose

Renumber configured managed LVs into contiguous sequences per prefix + embedded-VMID namespace (for example `vm-199-*` separately from stale `base-100-*`), preserving those namespaces, updating the VM configuration, and refusing volumes referenced by another guest.

## Usage

Run the built-in help without performing the operation:

```sh
./renumber-vm-disks.sh --help
```

The current built-in help is:

```text
Usage: renumber-vm-disks.sh <vmid> [dryrun]
Renumber configured vm-ID-disk-N / base-ID-disk-N namespaces without changing prefix or embedded ID.
Dry-run:
  Add dryrun or --dryrun anywhere on the command line.
  Read-only preflight checks still run, but modifying commands are printed
  instead of executed and mutation-dependent verification is simulated.
```

The same output is stored verbatim in [`renumber-vm-disks.sh.usage`](./renumber-vm-disks.sh.usage).

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/renumber-vm-disks.sh" -O "renumber-vm-disks.sh" && chmod +x "renumber-vm-disks.sh"
```

## Examples

```sh
./renumber-vm-disks.sh 123 dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
renumber-vm-disks.sh 3.5.1 (project 3.5.1)
```

This page documents the helper as shipped in project **v3.5.1**.
