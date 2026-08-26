# `rename-lvm.sh`

[Back to helper list](../README.md) · [View script](../rename-lvm.sh) · [Raw usage](./rename-lvm.sh.usage)

## Purpose

Rename an LVM logical volume after validating its source and destination names.

## Usage

Run the built-in help without performing the operation:

```sh
./rename-lvm.sh --help
```

The current built-in help is:

<!-- BEGIN LIVE HELP -->
```text
rename-lvm.sh 3.7.1 (project 3.7.1)

USAGE
  rename-lvm.sh <source-lv-path> <new-name> [dryrun]
  rename-lvm.sh <volume-group> <old-name> <new-name> [dryrun]

DESCRIPTION
  Renames one LVM logical volume after validating the source, destination
  component, and destination collision state. Both full-path and explicit
  VG/old/new forms are supported.

EXAMPLES
  rename-lvm.sh /dev/pve/vm-123-disk-1 vm-123-disk-1-old
  rename-lvm.sh pve vm-123-disk-1 vm-123-disk-1-old

HELP
  -h, -?, /h, /?, --help  Show this help and exit.
  --version                Show script and project versions and exit.

DRY-RUN
  Forms: dryrun, --dryrun.
  Dry-run: no system changes are made; modifying commands are printed instead of executed.
```
<!-- END LIVE HELP -->

The same output is stored verbatim in [`rename-lvm.sh.usage`](./rename-lvm.sh.usage).

## Test coverage

- Integration reference: `20-lvm.sh`
- The static suite verifies this helper's POSIX syntax, standalone help/version
  behavior, help aliases, documented parser options, live-help snapshot, and
  documentation synchronization.
- See [`tests/TEST-MATRIX.md`](../tests/TEST-MATRIX.md) for real/negative coverage.

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/rename-lvm.sh" -O "rename-lvm.sh" && chmod +x "rename-lvm.sh"
```

## Examples

```sh
./rename-lvm.sh /dev/pve/vm-123-disk-0 vm-123-disk-0-old dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
rename-lvm.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.
