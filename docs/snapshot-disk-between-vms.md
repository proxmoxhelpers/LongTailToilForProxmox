# `snapshot-disk-between-vms.sh`

[Back to helper list](../README.md) · [View script](../snapshot-disk-between-vms.sh) · [Raw usage](./snapshot-disk-between-vms.sh.usage)

## Purpose

Create an LVM-thin snapshot of one VM disk and attach that linked snapshot to another VM.

## Usage

Run the built-in help without performing the operation:

```sh
./snapshot-disk-between-vms.sh --help
```

The current built-in help is:

<!-- BEGIN LIVE HELP -->
```text
snapshot-disk-between-vms.sh 3.7.1 (project 3.7.1)

USAGE
  snapshot-disk-between-vms.sh <source-vmid> <source-slot> <destination-vmid> [dryrun]

DESCRIPTION
  Creates a linked LVM-thin snapshot of one active source VM disk and attaches
  that snapshot to another QEMU VM after validating source storage and
  destination slot availability.

EXAMPLES
  snapshot-disk-between-vms.sh 123 scsi0 456

HELP
  -h, -?, /h, /?, --help  Show this help and exit.
  --version                Show script and project versions and exit.

DRY-RUN
  Forms: dryrun, --dryrun.
  Dry-run: no system changes are made; modifying commands are printed instead of executed.
```
<!-- END LIVE HELP -->

The same output is stored verbatim in [`snapshot-disk-between-vms.sh.usage`](./snapshot-disk-between-vms.sh.usage).

## Test coverage

- Integration reference: `50-copy-snapshot.sh`
- The static suite verifies this helper's POSIX syntax, standalone help/version
  behavior, help aliases, documented parser options, live-help snapshot, and
  documentation synchronization.
- See [`tests/TEST-MATRIX.md`](../tests/TEST-MATRIX.md) for real/negative coverage.

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/snapshot-disk-between-vms.sh" -O "snapshot-disk-between-vms.sh" && chmod +x "snapshot-disk-between-vms.sh"
```

## Examples

```sh
./snapshot-disk-between-vms.sh 123 scsi0 456 dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
snapshot-disk-between-vms.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.
