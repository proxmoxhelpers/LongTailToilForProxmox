# `swap-vm-disks.sh`

[Back to helper list](../README.md) · [View script](../swap-vm-disks.sh) · [Raw usage](./swap-vm-disks.sh.usage)

## Purpose

On a stopped QEMU VM, swap the complete configuration values of two existing disk slots after backing up the VM configuration.

## Usage

Run the built-in help without performing the operation:

```sh
./swap-vm-disks.sh --help
```

The current built-in help is:

<!-- BEGIN LIVE HELP -->
```text
swap-vm-disks.sh 3.7.1 (project 3.7.1)

USAGE
  swap-vm-disks.sh <vmid> <slot-a> <slot-b> [dryrun]

DESCRIPTION
  Swaps the complete configuration values of two existing QEMU disk slots.

SAFETY
  The VM must be stopped. Both slots must already exist. The VM config is
  backed up before the atomic rewrite and verified afterward.

HELP
  -h, -?, /h, /?, --help  Show this help and exit.
  --version                Show script and project versions and exit.

DRY-RUN
  Forms: dryrun, --dryrun.
  Dry-run: no system changes are made; modifying commands are printed instead of executed.
```
<!-- END LIVE HELP -->

The same output is stored verbatim in [`swap-vm-disks.sh.usage`](./swap-vm-disks.sh.usage).

## Test coverage

- Integration reference: `60-disk-config.sh`
- The static suite verifies this helper's POSIX syntax, standalone help/version
  behavior, help aliases, documented parser options, live-help snapshot, and
  documentation synchronization.
- See [`tests/TEST-MATRIX.md`](../tests/TEST-MATRIX.md) for real/negative coverage.

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/swap-vm-disks.sh" -O "swap-vm-disks.sh" && chmod +x "swap-vm-disks.sh"
```

## Examples

```sh
./swap-vm-disks.sh 123 scsi0 scsi1 dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
swap-vm-disks.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.
