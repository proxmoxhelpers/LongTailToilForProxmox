# `bulk-change-vm-storage.sh`

[Back to helper list](../README.md) · [View script](../bulk-change-vm-storage.sh) · [Raw usage](./bulk-change-vm-storage.sh.usage)

## Purpose

Move matching VM disks from one Proxmox storage ID to another across multiple VMIDs.

## Usage

Run the built-in help without performing the operation:

```sh
./bulk-change-vm-storage.sh --help
```

The current built-in help is:

<!-- BEGIN LIVE HELP -->
```text
bulk-change-vm-storage.sh 3.7.1 (project 3.7.1)

USAGE
  bulk-change-vm-storage.sh <source-storage> <destination-storage> <vmid>... [dryrun]

DESCRIPTION
  Moves every matching active QEMU disk on the listed VMIDs from one
  configured Proxmox storage ID to another using Proxmox storage migration. At
  least one VMID is required.

EXAMPLES
  bulk-change-vm-storage.sh local-lvm fast-lvm 101 102

HELP
  -h, -?, /h, /?, --help  Show this help and exit.
  --version                Show script and project versions and exit.

DRY-RUN
  Forms: dryrun, --dryrun.
  Dry-run: no system changes are made; modifying commands are printed instead of executed.
```
<!-- END LIVE HELP -->

The same output is stored verbatim in [`bulk-change-vm-storage.sh.usage`](./bulk-change-vm-storage.sh.usage).

## Test coverage

- Integration reference: `70-storage-io.sh`
- The static suite verifies this helper's POSIX syntax, standalone help/version
  behavior, help aliases, documented parser options, live-help snapshot, and
  documentation synchronization.
- See [`tests/TEST-MATRIX.md`](../tests/TEST-MATRIX.md) for real/negative coverage.

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/bulk-change-vm-storage.sh" -O "bulk-change-vm-storage.sh" && chmod +x "bulk-change-vm-storage.sh"
```

## Examples

```sh
./bulk-change-vm-storage.sh local-lvm fast-lvm 123 124 125 dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
bulk-change-vm-storage.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.
