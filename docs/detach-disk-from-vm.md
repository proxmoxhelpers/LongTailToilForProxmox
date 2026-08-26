# `detach-disk-from-vm.sh`

[Back to helper list](../README.md) · [View script](../detach-disk-from-vm.sh) · [Raw usage](./detach-disk-from-vm.sh.usage)

## Purpose

Detach a disk slot from a stopped QEMU VM while preserving the backing volume as an `unusedN` entry.

## Usage

Run the built-in help without performing the operation:

```sh
./detach-disk-from-vm.sh --help
```

The current built-in help is:

<!-- BEGIN LIVE HELP -->
```text
detach-disk-from-vm.sh 3.7.1 (project 3.7.1)

USAGE
  detach-disk-from-vm.sh <vmid> <disk-slot> [dryrun]

DESCRIPTION
  Detaches an active disk slot from a QEMU VM without deleting its backing
  volume. Proxmox preserves the detached volume as an unusedN reference.

SAFETY
  The VM must be stopped.

HELP
  -h, -?, /h, /?, --help  Show this help and exit.
  --version                Show script and project versions and exit.

DRY-RUN
  Forms: dryrun, --dryrun.
  Dry-run: no system changes are made; modifying commands are printed instead of executed.
```
<!-- END LIVE HELP -->

The same output is stored verbatim in [`detach-disk-from-vm.sh.usage`](./detach-disk-from-vm.sh.usage).

## Test coverage

- Integration reference: `40-disk-lifecycle.sh`
- The static suite verifies this helper's POSIX syntax, standalone help/version
  behavior, help aliases, documented parser options, live-help snapshot, and
  documentation synchronization.
- See [`tests/TEST-MATRIX.md`](../tests/TEST-MATRIX.md) for real/negative coverage.

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/detach-disk-from-vm.sh" -O "detach-disk-from-vm.sh" && chmod +x "detach-disk-from-vm.sh"
```

## Examples

```sh
./detach-disk-from-vm.sh 123 scsi2 dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
detach-disk-from-vm.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.
