# `delete-disk-from-vm.sh`

[Back to helper list](../README.md) · [View script](../delete-disk-from-vm.sh) · [Raw usage](./delete-disk-from-vm.sh.usage)

## Purpose

On a stopped QEMU VM, permanently delete a disk or `unusedN` volume from both the guest configuration and backing Proxmox storage, refusing shared volumes.

## Usage

Run the built-in help without performing the operation:

```sh
./delete-disk-from-vm.sh --help
```

The current built-in help is:

<!-- BEGIN LIVE HELP -->
```text
delete-disk-from-vm.sh 3.7.1 (project 3.7.1)

USAGE
  delete-disk-from-vm.sh <vmid> <disk-slot|unusedN> [dryrun]

DESCRIPTION
  Permanently deletes the backing storage volume referenced by an active disk
  slot or unusedN entry on a QEMU VM.

SAFETY
  The VM must be stopped. Active disks are detached first. Deletion is refused
  when the volume is referenced by another guest.

HELP
  -h, -?, /h, /?, --help  Show this help and exit.
  --version                Show script and project versions and exit.

DRY-RUN
  Forms: dryrun, --dryrun.
  Dry-run: no system changes are made; modifying commands are printed instead of executed.
```
<!-- END LIVE HELP -->

The same output is stored verbatim in [`delete-disk-from-vm.sh.usage`](./delete-disk-from-vm.sh.usage).

## Test coverage

- Integration reference: `40-disk-lifecycle.sh`
- The static suite verifies this helper's POSIX syntax, standalone help/version
  behavior, help aliases, documented parser options, live-help snapshot, and
  documentation synchronization.
- See [`tests/TEST-MATRIX.md`](../tests/TEST-MATRIX.md) for real/negative coverage.

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/delete-disk-from-vm.sh" -O "delete-disk-from-vm.sh" && chmod +x "delete-disk-from-vm.sh"
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
delete-disk-from-vm.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.
