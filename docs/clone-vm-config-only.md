# `clone-vm-config-only.sh`

[Back to helper list](../README.md) · [View script](../clone-vm-config-only.sh) · [Raw usage](./clone-vm-config-only.sh.usage)

## Purpose

Clone a QEMU VM configuration to a new VMID without copying its disks.

## Usage

Run the built-in help without performing the operation:

```sh
./clone-vm-config-only.sh --help
```

The current built-in help is:

```text
Usage: clone-vm-config-only.sh <source-vmid> <new-vmid> [new-name] [dryrun]
Dry-run:
  Add dryrun or --dryrun anywhere on the command line.
  Read-only preflight checks still run, but modifying commands are printed
  instead of executed and mutation-dependent verification is simulated.
```

The same output is stored verbatim in [`clone-vm-config-only.sh.usage`](./clone-vm-config-only.sh.usage).

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/clone-vm-config-only.sh" -O "clone-vm-config-only.sh" && chmod +x "clone-vm-config-only.sh"
```

## Examples

```sh
./clone-vm-config-only.sh 123 456 web-copy dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
clone-vm-config-only.sh 3.0.1 (project 3.4.7)
```

This page documents the helper as shipped in project **v3.4.7**.
