# `change-vm-storage-prefix.sh`

[Back to helper list](../README.md) · [View script](../change-vm-storage-prefix.sh) · [Raw usage](./change-vm-storage-prefix.sh.usage)

## Purpose

Rewrite an old Proxmox storage ID to a new storage ID in stopped local QEMU/LXC guest configurations only when both IDs resolve every affected volume to the same underlying path; this is an alias/reference rewrite, not a data migration.

## Usage

Run the built-in help without performing the operation:

```sh
./change-vm-storage-prefix.sh --help
```

The current built-in help is:

<!-- BEGIN LIVE HELP -->
```text
change-vm-storage-prefix.sh 3.7.1 (project 3.7.1)

USAGE
  change-vm-storage-prefix.sh <old-storage-id> <new-storage-id> [dryrun]

DESCRIPTION
  Rewrites local QEMU/LXC guest configuration references from one Proxmox
  storage ID to another storage ID that resolves to the same backing volumes.

SAFETY
  This is a storage-ID/alias rewrite, not a data migration.
  Every affected guest must be stopped.
  The new storage must already exist.
  For every affected volume, old and new volume IDs must resolve to the same
  canonical underlying path before any configuration is changed.
  A backup of each affected guest config is created before rewriting.

HELP
  -h, -?, /h, /?, --help  Show this help and exit.
  --version                Show script and project versions and exit.

DRY-RUN
  Forms: dryrun, --dryrun.
  Dry-run: no system changes are made; modifying commands are printed instead of executed.
```
<!-- END LIVE HELP -->

The same output is stored verbatim in [`change-vm-storage-prefix.sh.usage`](./change-vm-storage-prefix.sh.usage).

## Test coverage

- Integration reference: `70-storage-io.sh`
- The static suite verifies this helper's POSIX syntax, standalone help/version
  behavior, help aliases, documented parser options, live-help snapshot, and
  documentation synchronization.
- See [`tests/TEST-MATRIX.md`](../tests/TEST-MATRIX.md) for real/negative coverage.

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/change-vm-storage-prefix.sh" -O "change-vm-storage-prefix.sh" && chmod +x "change-vm-storage-prefix.sh"
```

## Examples

```sh
./change-vm-storage-prefix.sh old-lvm new-lvm dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
change-vm-storage-prefix.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.
