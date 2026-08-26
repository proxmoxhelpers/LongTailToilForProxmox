# `change-vmid-of-vm.sh`

[Back to helper list](../README.md) · [View script](../change-vmid-of-vm.sh) · [Raw usage](./change-vmid-of-vm.sh.usage)

## Purpose

Change the VMID of a local QEMU VM or LXC container on LVM/LVM-thin, stopping a running guest first, renaming both `vm-OLDID-*` and template `base-OLDID-*` volumes while preserving their family, and intentionally leaving the renamed guest stopped after preflight, backup, verification and rollback protection.

## Usage

Run the built-in help without performing the operation:

```sh
./change-vmid-of-vm.sh --help
```

The current built-in help is:

<!-- BEGIN LIVE HELP -->
```text
change-vmid-of-vm.sh 3.7.1 (project 3.7.1)

USAGE
  change-vmid-of-vm.sh <old-vmid> <new-vmid> [dryrun]

DESCRIPTION
  Changes the VMID of a local QEMU VM or LXC container when all referenced
  vm-OLDID-* / base-OLDID-* storage volumes are LVM/LVM-thin and can be renamed in place.

  Preflight checks destination VMID availability, locks, snapshots, volume
  ownership and name collisions before mutation. A running guest is asked to
  shut down gracefully and is force-stopped only if necessary. The renamed
  guest is intentionally left stopped.

EXAMPLE
  change-vmid-of-vm.sh 123 456

NOTES
  HA, replication, ACLs, backup jobs, pools, hooks and external automation are
  not rewritten automatically and must be reviewed after a successful change.

HELP
  -h, -?, /h, /?, --help  Show this help and exit.
  --version                Show script and project versions and exit.

DRY-RUN
  Forms: dryrun, --dryrun.
  Dry-run: no system changes are made; modifying commands are printed instead of executed.
```
<!-- END LIVE HELP -->

The same output is stored verbatim in [`change-vmid-of-vm.sh.usage`](./change-vmid-of-vm.sh.usage).

## Test coverage

- Integration reference: `80-vm-config.sh`
- The static suite verifies this helper's POSIX syntax, standalone help/version
  behavior, help aliases, documented parser options, live-help snapshot, and
  documentation synchronization.
- See [`tests/TEST-MATRIX.md`](../tests/TEST-MATRIX.md) for real/negative coverage.

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/change-vmid-of-vm.sh" -O "change-vmid-of-vm.sh" && chmod +x "change-vmid-of-vm.sh"
```

## Examples

```sh
./change-vmid-of-vm.sh 123 456 dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
change-vmid-of-vm.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.
