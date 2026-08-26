# `recover-vm-from-volumes.sh`

[Back to helper list](../README.md) · [View script](../recover-vm-from-volumes.sh) · [Raw usage](./recover-vm-from-volumes.sh.usage)

## Purpose

Recreate a basic QEMU VM configuration from existing `vm-VMID-disk-N` and/or `base-VMID-disk-N` LVM volumes.

## Usage

Run the built-in help without performing the operation:

```sh
./recover-vm-from-volumes.sh --help
```

The current built-in help is:

<!-- BEGIN LIVE HELP -->
```text
recover-vm-from-volumes.sh 3.7.1 (project 3.7.1)

USAGE
  recover-vm-from-volumes.sh <vmid> [volume-group] [dryrun]

DESCRIPTION
  Creates a basic QEMU VM configuration from existing managed vm-VMID-disk-N
  or base-VMID-disk-N LVM volumes. An optional volume group limits discovery;
  CPU, memory, firmware, NICs, and boot settings must be reviewed before
  starting the VM.

EXAMPLES
  recover-vm-from-volumes.sh 123 pve

HELP
  -h, -?, /h, /?, --help  Show this help and exit.
  --version                Show script and project versions and exit.

DRY-RUN
  Forms: dryrun, --dryrun.
  Dry-run: no system changes are made; modifying commands are printed instead of executed.
```
<!-- END LIVE HELP -->

The same output is stored verbatim in [`recover-vm-from-volumes.sh.usage`](./recover-vm-from-volumes.sh.usage).

## Test coverage

- Integration reference: `80-vm-config.sh`
- The static suite verifies this helper's POSIX syntax, standalone help/version
  behavior, help aliases, documented parser options, live-help snapshot, and
  documentation synchronization.
- See [`tests/TEST-MATRIX.md`](../tests/TEST-MATRIX.md) for real/negative coverage.

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/recover-vm-from-volumes.sh" -O "recover-vm-from-volumes.sh" && chmod +x "recover-vm-from-volumes.sh"
```

## Examples

```sh
./recover-vm-from-volumes.sh 456 pve dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
recover-vm-from-volumes.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.
