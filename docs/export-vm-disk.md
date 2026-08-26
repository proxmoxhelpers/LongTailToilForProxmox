# `export-vm-disk.sh`

[Back to helper list](../README.md) · [View script](../export-vm-disk.sh) · [Raw usage](./export-vm-disk.sh.usage)

## Purpose

Export a stopped QEMU VM disk to raw or qcow2 with `qemu-img`; when format is omitted, `.qcow2` selects qcow2 and all other output filenames default to raw.

## Usage

Run the built-in help without performing the operation:

```sh
./export-vm-disk.sh --help
```

The current built-in help is:

<!-- BEGIN LIVE HELP -->
```text
export-vm-disk.sh 3.7.1 (project 3.7.1)

USAGE
  export-vm-disk.sh <vmid> <disk-slot> <output-file> [raw|qcow2] [dryrun]

DESCRIPTION
  Exports a storage-backed QEMU VM disk through qemu-img convert.

FORMAT
  Explicit raw or qcow2 selects that output format.
  If omitted, a .qcow2 output filename selects qcow2; every other filename
  defaults to raw.

SAFETY
  The VM must be stopped. The output path must not already exist.

HELP
  -h, -?, /h, /?, --help  Show this help and exit.
  --version                Show script and project versions and exit.

DRY-RUN
  Forms: dryrun, --dryrun.
  Dry-run: no system changes are made; modifying commands are printed instead of executed.
```
<!-- END LIVE HELP -->

The same output is stored verbatim in [`export-vm-disk.sh.usage`](./export-vm-disk.sh.usage).

## Test coverage

- Integration reference: `70-storage-io.sh`
- The static suite verifies this helper's POSIX syntax, standalone help/version
  behavior, help aliases, documented parser options, live-help snapshot, and
  documentation synchronization.
- See [`tests/TEST-MATRIX.md`](../tests/TEST-MATRIX.md) for real/negative coverage.

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/export-vm-disk.sh" -O "export-vm-disk.sh" && chmod +x "export-vm-disk.sh"
```

## Examples

```sh
./export-vm-disk.sh 123 scsi0 ./vm-123-scsi0.qcow2 qcow2 dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
export-vm-disk.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.
