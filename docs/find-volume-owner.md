# `find-volume-owner.sh`

[Back to helper list](../README.md) · [View script](../find-volume-owner.sh) · [Raw usage](./find-volume-owner.sh.usage)

## Purpose

Find which local guest configuration references a specific LVM path or Proxmox volume ID.

## Usage

Run the built-in help without performing the operation:

```sh
./find-volume-owner.sh --help
```

The current built-in help is:

<!-- BEGIN LIVE HELP -->
```text
find-volume-owner.sh 3.7.1 (project 3.7.1)

USAGE
  find-volume-owner.sh <full-lv-path|storage:volume> [dryrun]

DESCRIPTION
  Finds local QEMU or LXC guest configuration references to one LVM path or
  Proxmox storage:volume identifier and reports the referencing guest/slot
  information.

EXAMPLES
  find-volume-owner.sh /dev/pve/vm-123-disk-0

HELP
  -h, -?, /h, /?, --help  Show this help and exit.
  --version                Show script and project versions and exit.

DRY-RUN
  Forms: dryrun, --dryrun.
  Dry-run: no system changes are made; modifying commands are printed instead of executed.
```
<!-- END LIVE HELP -->

The same output is stored verbatim in [`find-volume-owner.sh.usage`](./find-volume-owner.sh.usage).

## Test coverage

- Integration reference: `10-inspection.sh`
- The static suite verifies this helper's POSIX syntax, standalone help/version
  behavior, help aliases, documented parser options, live-help snapshot, and
  documentation synchronization.
- See [`tests/TEST-MATRIX.md`](../tests/TEST-MATRIX.md) for real/negative coverage.

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/find-volume-owner.sh" -O "find-volume-owner.sh" && chmod +x "find-volume-owner.sh"
```

## Examples

```sh
./find-volume-owner.sh /dev/pve/vm-123-disk-0
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
find-volume-owner.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.
