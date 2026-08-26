# `find-orphaned-volumes.sh`

[Back to helper list](../README.md) · [View script](../find-orphaned-volumes.sh) · [Raw usage](./find-orphaned-volumes.sh.usage)

## Purpose

Find unreferenced Proxmox-managed `vm-VMID-disk-N` and `base-VMID-disk-N` LVM volumes.

## Usage

Run the built-in help without performing the operation:

```sh
./find-orphaned-volumes.sh --help
```

The current built-in help is:

<!-- BEGIN LIVE HELP -->
```text
find-orphaned-volumes.sh 3.7.1 (project 3.7.1)

USAGE
  find-orphaned-volumes.sh [volume-group] [dryrun]

DESCRIPTION
  Lists Proxmox-managed vm-VMID-disk-N and base-VMID-disk-N LVM volumes that
  are not referenced by any local QEMU or LXC guest configuration. An optional
  volume group limits the search.

EXAMPLES
  find-orphaned-volumes.sh pve

HELP
  -h, -?, /h, /?, --help  Show this help and exit.
  --version                Show script and project versions and exit.

DRY-RUN
  Forms: dryrun, --dryrun.
  Dry-run: no system changes are made; modifying commands are printed instead of executed.
```
<!-- END LIVE HELP -->

The same output is stored verbatim in [`find-orphaned-volumes.sh.usage`](./find-orphaned-volumes.sh.usage).

## Test coverage

- Integration reference: `10-inspection.sh`
- The static suite verifies this helper's POSIX syntax, standalone help/version
  behavior, help aliases, documented parser options, live-help snapshot, and
  documentation synchronization.
- See [`tests/TEST-MATRIX.md`](../tests/TEST-MATRIX.md) for real/negative coverage.

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/find-orphaned-volumes.sh" -O "find-orphaned-volumes.sh" && chmod +x "find-orphaned-volumes.sh"
```

## Examples

```sh
./find-orphaned-volumes.sh pve
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
find-orphaned-volumes.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.
