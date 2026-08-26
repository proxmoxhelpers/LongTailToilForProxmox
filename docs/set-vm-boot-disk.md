# `set-vm-boot-disk.sh`

[Back to helper list](../README.md) · [View script](../set-vm-boot-disk.sh) · [Raw usage](./set-vm-boot-disk.sh.usage)

## Purpose

Put a selected VM disk slot first in the QEMU boot order.

## Usage

Run the built-in help without performing the operation:

```sh
./set-vm-boot-disk.sh --help
```

The current built-in help is:

<!-- BEGIN LIVE HELP -->
```text
set-vm-boot-disk.sh 3.7.1 (project 3.7.1)

USAGE
  set-vm-boot-disk.sh <vmid> <disk-slot> [dryrun]

DESCRIPTION
  Makes an existing QEMU disk slot the first boot device while preserving the
  relative order of the remaining configured boot devices.

EXAMPLES
  set-vm-boot-disk.sh 123 scsi0

HELP
  -h, -?, /h, /?, --help  Show this help and exit.
  --version                Show script and project versions and exit.

DRY-RUN
  Forms: dryrun, --dryrun.
  Dry-run: no system changes are made; modifying commands are printed instead of executed.
```
<!-- END LIVE HELP -->

The same output is stored verbatim in [`set-vm-boot-disk.sh.usage`](./set-vm-boot-disk.sh.usage).

## Test coverage

- Integration reference: `60-disk-config.sh`
- The static suite verifies this helper's POSIX syntax, standalone help/version
  behavior, help aliases, documented parser options, live-help snapshot, and
  documentation synchronization.
- See [`tests/TEST-MATRIX.md`](../tests/TEST-MATRIX.md) for real/negative coverage.

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/set-vm-boot-disk.sh" -O "set-vm-boot-disk.sh" && chmod +x "set-vm-boot-disk.sh"
```

## Examples

```sh
./set-vm-boot-disk.sh 123 scsi0 dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
set-vm-boot-disk.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.
