# `import-disk-and-attach.sh`

[Back to helper list](../README.md) · [View script](../import-disk-and-attach.sh) · [Raw usage](./import-disk-and-attach.sh.usage)

## Purpose

Import a disk image into Proxmox storage and attach it to a stopped QEMU VM at the first free SCSI slot or an explicitly requested empty `scsi0..scsi30` slot.

## Usage

Run the built-in help without performing the operation:

```sh
./import-disk-and-attach.sh --help
```

The current built-in help is:

<!-- BEGIN LIVE HELP -->
```text
import-disk-and-attach.sh 3.7.1 (project 3.7.1)

USAGE
  import-disk-and-attach.sh <image-file> <vmid> <destination-storage> [scsiN] [dryrun]

DESCRIPTION
  Imports a disk image into Proxmox storage and attaches the newly imported
  volume to a stopped QEMU VM.

DESTINATION SLOT
  omitted  Use the first free SCSI slot.
  scsiN    Use exactly scsi0..scsi30; the slot must be empty.

SAFETY
  The VM must be stopped. Explicit non-SCSI or out-of-range slots are refused
  during preflight, before qm importdisk creates storage.

HELP
  -h, -?, /h, /?, --help  Show this help and exit.
  --version                Show script and project versions and exit.

DRY-RUN
  Forms: dryrun, --dryrun.
  Dry-run: no system changes are made; modifying commands are printed instead of executed.
```
<!-- END LIVE HELP -->

The same output is stored verbatim in [`import-disk-and-attach.sh.usage`](./import-disk-and-attach.sh.usage).

## Test coverage

- Integration reference: `70-storage-io.sh`
- The static suite verifies this helper's POSIX syntax, standalone help/version
  behavior, help aliases, documented parser options, live-help snapshot, and
  documentation synchronization.
- See [`tests/TEST-MATRIX.md`](../tests/TEST-MATRIX.md) for real/negative coverage.

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/import-disk-and-attach.sh" -O "import-disk-and-attach.sh" && chmod +x "import-disk-and-attach.sh"
```

## Examples

```sh
./import-disk-and-attach.sh ./server.raw 123 local-lvm scsi1 dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
import-disk-and-attach.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.
