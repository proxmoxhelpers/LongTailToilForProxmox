# `attach-existing-lvm-to-vm.sh`

[Back to helper list](../README.md) · [View script](../attach-existing-lvm-to-vm.sh) · [Raw usage](./attach-existing-lvm-to-vm.sh.usage)

## Purpose

Attach an existing LVM volume to a QEMU VM as a SCSI disk without copying it.

## Usage

Run the built-in help without performing the operation:

```sh
./attach-existing-lvm-to-vm.sh --help
```

The current built-in help is:

<!-- BEGIN LIVE HELP -->
```text
attach-existing-lvm-to-vm.sh 3.7.1 (project 3.7.1)

USAGE
  attach-existing-lvm-to-vm.sh <full-lv-path> <vmid> [scsiN] [dryrun]

DESCRIPTION
  Attaches an existing LVM logical volume to a local QEMU VM as a SCSI disk
  without copying the volume. The optional scsiN selects the exact destination
  slot; when omitted the first free SCSI slot is used.

EXAMPLES
  attach-existing-lvm-to-vm.sh /dev/pve/vm-123-disk-2 123 scsi2

HELP
  -h, -?, /h, /?, --help  Show this help and exit.
  --version                Show script and project versions and exit.

DRY-RUN
  Forms: dryrun, --dryrun.
  Dry-run: no system changes are made; modifying commands are printed instead of executed.
```
<!-- END LIVE HELP -->

The same output is stored verbatim in [`attach-existing-lvm-to-vm.sh.usage`](./attach-existing-lvm-to-vm.sh.usage).

## Test coverage

- Integration reference: `40-disk-lifecycle.sh`
- The static suite verifies this helper's POSIX syntax, standalone help/version
  behavior, help aliases, documented parser options, live-help snapshot, and
  documentation synchronization.
- See [`tests/TEST-MATRIX.md`](../tests/TEST-MATRIX.md) for real/negative coverage.

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/attach-existing-lvm-to-vm.sh" -O "attach-existing-lvm-to-vm.sh" && chmod +x "attach-existing-lvm-to-vm.sh"
```

## Examples

```sh
./attach-existing-lvm-to-vm.sh /dev/pve/vm-123-disk-2 123 scsi2 dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
attach-existing-lvm-to-vm.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.
