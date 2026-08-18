# `delete-disk-from-vm.sh`

[Back to helper list](../README.md) · [View script](../delete-disk-from-vm.sh) · [Raw usage](./delete-disk-from-vm.sh.usage)

## Purpose

Delete a VM disk or `unusedN` volume from both the guest configuration and backing Proxmox storage.

## Usage

Run the built-in help without performing the operation:

```sh
./delete-disk-from-vm.sh --help
```

The current built-in help is:

```text
Usage: delete-disk-from-vm.sh <vmid> <disk-slot|unusedN> [dryrun]
Dry-run:
  Add dryrun or --dryrun anywhere on the command line.
  Read-only preflight checks still run, but modifying commands are printed
  instead of executed and mutation-dependent verification is simulated.
```

The same output is stored verbatim in [`delete-disk-from-vm.sh.usage`](./delete-disk-from-vm.sh.usage).

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/delete-disk-from-vm.sh" -O "delete-disk-from-vm.sh" && chmod +x "delete-disk-from-vm.sh"
```

## Examples

```sh
./delete-disk-from-vm.sh 123 unused0 dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
delete-disk-from-vm.sh 3.0.0 (project 3.4.7)
```

This page documents the helper as shipped in project **v3.4.7**.
