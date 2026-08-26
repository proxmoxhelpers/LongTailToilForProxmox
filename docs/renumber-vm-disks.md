# `renumber-vm-disks.sh`

[Back to helper list](../README.md) · [View script](../renumber-vm-disks.sh) · [Raw usage](./renumber-vm-disks.sh.usage)

## Purpose

On a stopped, snapshot-free QEMU VM, renumber configured managed LVs into contiguous sequences per prefix + embedded-VMID namespace, preserving those namespaces, updating the VM configuration, and refusing shared volumes or destination collisions.

## Usage

Run the built-in help without performing the operation:

```sh
./renumber-vm-disks.sh --help
```

The current built-in help is:

<!-- BEGIN LIVE HELP -->
```text
renumber-vm-disks.sh 3.7.1 (project 3.7.1)

USAGE
  renumber-vm-disks.sh <vmid> [dryrun]

DESCRIPTION
  Renumbers configured vm-ID-disk-N / base-ID-disk-N namespaces contiguously
  while preserving each namespace prefix and embedded VMID.

SAFETY
  The QEMU VM must be stopped. VM snapshot/config sections are refused; remove
  snapshots first. Shared managed volumes and destination collisions are also
  refused before any rename.

HELP
  -h, -?, /h, /?, --help  Show this help and exit.
  --version                Show script and project versions and exit.

DRY-RUN
  Forms: dryrun, --dryrun.
  Dry-run: no system changes are made; modifying commands are printed instead of executed.
```
<!-- END LIVE HELP -->

The same output is stored verbatim in [`renumber-vm-disks.sh.usage`](./renumber-vm-disks.sh.usage).

## Test coverage

- Integration reference: `60-disk-config.sh`
- The static suite verifies this helper's POSIX syntax, standalone help/version
  behavior, help aliases, documented parser options, live-help snapshot, and
  documentation synchronization.
- See [`tests/TEST-MATRIX.md`](../tests/TEST-MATRIX.md) for real/negative coverage.

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/renumber-vm-disks.sh" -O "renumber-vm-disks.sh" && chmod +x "renumber-vm-disks.sh"
```

## Examples

```sh
./renumber-vm-disks.sh 123 dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
renumber-vm-disks.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.
