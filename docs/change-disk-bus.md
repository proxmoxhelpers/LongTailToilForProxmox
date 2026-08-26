# `change-disk-bus.sh`

[Back to helper list](../README.md) · [View script](../change-disk-bus.sh) · [Raw usage](./change-disk-bus.sh.usage)

## Purpose

Move a stopped QEMU VM disk configuration from one bus/slot to another without moving its backing volume, defaulting an omitted destination to the first free SCSI slot and preserving destination-compatible options; incompatible `iothread` is removed with a warning for SATA/IDE.

## Usage

Run the built-in help without performing the operation:

```sh
./change-disk-bus.sh --help
```

The current built-in help is:

<!-- BEGIN LIVE HELP -->
```text
change-disk-bus.sh 3.7.1 (project 3.7.1)

USAGE
  change-disk-bus.sh <vmid> <source-slot> [destination-slot|scsi|virtio|sata|ide] [dryrun]

DESCRIPTION
  Moves an existing QEMU disk configuration entry to another disk bus/slot
  without moving its backing volume. The VM must be stopped.

DESTINATION
  omitted  Use the first free SCSI slot.
  scsi     Use the first free SCSI slot.
  virtio   Use the first free VirtIO slot.
  sata     Use the first free SATA slot.
  ide      Use the first free IDE slot.
  BUSN     Use that exact empty slot, for example sata0 or virtio2.

NOTES
  Disk options are preserved when compatible. iothread is removed when moving
  to SATA or IDE because those buses do not accept it. The VM config is backed
  up and the exact rewritten value is verified.

HELP
  -h, -?, /h, /?, --help  Show this help and exit.
  --version                Show script and project versions and exit.

DRY-RUN
  Forms: dryrun, --dryrun.
  Dry-run: no system changes are made; modifying commands are printed instead of executed.
```
<!-- END LIVE HELP -->

The same output is stored verbatim in [`change-disk-bus.sh.usage`](./change-disk-bus.sh.usage).

## Test coverage

- Integration reference: `60-disk-config.sh`
- The static suite verifies this helper's POSIX syntax, standalone help/version
  behavior, help aliases, documented parser options, live-help snapshot, and
  documentation synchronization.
- See [`tests/TEST-MATRIX.md`](../tests/TEST-MATRIX.md) for real/negative coverage.

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/change-disk-bus.sh" -O "change-disk-bus.sh" && chmod +x "change-disk-bus.sh"
```

## Examples

```sh
./change-disk-bus.sh 123 scsi1 sata0 dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
change-disk-bus.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.
