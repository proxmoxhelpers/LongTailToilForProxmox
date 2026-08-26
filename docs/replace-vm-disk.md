# `replace-vm-disk.sh`

[Back to helper list](../README.md) · [View script](../replace-vm-disk.sh) · [Raw usage](./replace-vm-disk.sh.usage)

## Purpose

On a stopped QEMU VM, replace a disk slot with an existing unshared LVM volume while retaining the slot's compatible disk options and preserving the displaced disk as `unusedN`.

## Usage

Run the built-in help without performing the operation:

```sh
./replace-vm-disk.sh --help
```

The current built-in help is:

<!-- BEGIN LIVE HELP -->
```text
replace-vm-disk.sh 3.7.1 (project 3.7.1)

USAGE
  replace-vm-disk.sh <vmid> <disk-slot> <replacement-lv-path> [dryrun]

DESCRIPTION
  Replaces one configured QEMU disk with an existing LVM-backed replacement
  while preserving the original slot's disk options.

SAFETY
  The VM must be stopped. The replacement LV must resolve through a unique
  Proxmox storage mapping and must not already be referenced by another guest.
  The displaced old disk is preserved as an unusedN reference.

HELP
  -h, -?, /h, /?, --help  Show this help and exit.
  --version                Show script and project versions and exit.

DRY-RUN
  Forms: dryrun, --dryrun.
  Dry-run: no system changes are made; modifying commands are printed instead of executed.
```
<!-- END LIVE HELP -->

The same output is stored verbatim in [`replace-vm-disk.sh.usage`](./replace-vm-disk.sh.usage).

## Test coverage

- Integration reference: `60-disk-config.sh`
- The static suite verifies this helper's POSIX syntax, standalone help/version
  behavior, help aliases, documented parser options, live-help snapshot, and
  documentation synchronization.
- See [`tests/TEST-MATRIX.md`](../tests/TEST-MATRIX.md) for real/negative coverage.

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/replace-vm-disk.sh" -O "replace-vm-disk.sh" && chmod +x "replace-vm-disk.sh"
```

## Examples

```sh
./replace-vm-disk.sh 123 scsi0 /dev/pve/vm-123-disk-9 dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
replace-vm-disk.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.
