# `audit-vm-storage.sh`

[Back to helper list](../README.md) · [View script](../audit-vm-storage.sh) · [Raw usage](./audit-vm-storage.sh.usage)

## Purpose

Audit a VM's storage references for missing paths, bad mappings and unexpected references.

## Usage

Run the built-in help without performing the operation:

```sh
./audit-vm-storage.sh --help
```

The current built-in help is:

```text
Usage: audit-vm-storage.sh <vmid> [dryrun]
Dry-run:
  Add dryrun or --dryrun anywhere on the command line.
  Read-only preflight checks still run, but modifying commands are printed
  instead of executed and mutation-dependent verification is simulated.
```

The same output is stored verbatim in [`audit-vm-storage.sh.usage`](./audit-vm-storage.sh.usage).

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/audit-vm-storage.sh" -O "audit-vm-storage.sh" && chmod +x "audit-vm-storage.sh"
```

## Examples

```sh
./audit-vm-storage.sh 123
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
audit-vm-storage.sh 3.0.0 (project 3.4.7)
```

This page documents the helper as shipped in project **v3.4.7**.
