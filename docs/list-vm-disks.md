# `list-vm-disks.sh`

[Back to helper list](../README.md) · [View script](../list-vm-disks.sh) · [Raw usage](./list-vm-disks.sh.usage)

## Purpose

List a QEMU VM's configured disks, resolved storage paths and available LVM metadata.

## Usage

Run the built-in help without performing the operation:

```sh
./list-vm-disks.sh --help
```

The current built-in help is:

<!-- BEGIN LIVE HELP -->
```text
list-vm-disks.sh 3.7.1 (project 3.7.1)

USAGE
  list-vm-disks.sh <vmid> [dryrun]

DESCRIPTION
  Lists storage-backed disks configured on a local QEMU VM, including
  resolved paths and LVM metadata where available.

HELP
  -h, -?, /h, /?, --help  Show this help and exit.
  --version                Show script and project versions and exit.

DRY-RUN
  Forms: dryrun, --dryrun.
  Dry-run: no system changes are made; modifying commands are printed instead of executed.
```
<!-- END LIVE HELP -->

The same output is stored verbatim in [`list-vm-disks.sh.usage`](./list-vm-disks.sh.usage).

## Test coverage

- Integration reference: `10-inspection.sh`
- The static suite verifies this helper's POSIX syntax, standalone help/version
  behavior, help aliases, documented parser options, live-help snapshot, and
  documentation synchronization.
- See [`tests/TEST-MATRIX.md`](../tests/TEST-MATRIX.md) for real/negative coverage.

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/list-vm-disks.sh" -O "list-vm-disks.sh" && chmod +x "list-vm-disks.sh"
```

## Examples

```sh
./list-vm-disks.sh 123
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
list-vm-disks.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.
