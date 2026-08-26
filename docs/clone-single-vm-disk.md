# `clone-single-vm-disk.sh`

[Back to helper list](../README.md) · [View script](../clone-single-vm-disk.sh) · [Raw usage](./clone-single-vm-disk.sh.usage)

## Purpose

Clone one disk of a QEMU VM and attach the independent copy back to that VM.

## Usage

Run the built-in help without performing the operation:

```sh
./clone-single-vm-disk.sh --help
```

The current built-in help is:

<!-- BEGIN LIVE HELP -->
```text
clone-single-vm-disk.sh 3.7.1 (project 3.7.1)

USAGE
  clone-single-vm-disk.sh <vmid> <disk-slot> [destination-vg] [dryrun]

DESCRIPTION
  Creates an independent verified copy of one active QEMU disk and attaches
  the copy back to the same VM. The source is selected by an exact disk slot;
  destination-vg is optional.

EXAMPLES
  clone-single-vm-disk.sh 123 scsi0 pve

HELP
  -h, -?, /h, /?, --help  Show this help and exit.
  --version                Show script and project versions and exit.

DRY-RUN
  Forms: dryrun, --dryrun.
  Dry-run: no system changes are made; modifying commands are printed instead of executed.
```
<!-- END LIVE HELP -->

The same output is stored verbatim in [`clone-single-vm-disk.sh.usage`](./clone-single-vm-disk.sh.usage).

## Test coverage

- Integration reference: `50-copy-snapshot.sh`
- The static suite verifies this helper's POSIX syntax, standalone help/version
  behavior, help aliases, documented parser options, live-help snapshot, and
  documentation synchronization.
- See [`tests/TEST-MATRIX.md`](../tests/TEST-MATRIX.md) for real/negative coverage.

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/clone-single-vm-disk.sh" -O "clone-single-vm-disk.sh" && chmod +x "clone-single-vm-disk.sh"
```

## Examples

```sh
./clone-single-vm-disk.sh 123 scsi0 fastvg dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
clone-single-vm-disk.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.
