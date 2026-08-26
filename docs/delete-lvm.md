# `delete-lvm.sh`

[Back to helper list](../README.md) · [View script](../delete-lvm.sh) · [Raw usage](./delete-lvm.sh.usage)

## Purpose

Delete an LVM logical volume with exact `DELETE` confirmation and post-delete verification; cancellation exits non-zero for automation-safe refusal handling.

## Usage

Run the built-in help without performing the operation:

```sh
./delete-lvm.sh --help
```

The current built-in help is:

<!-- BEGIN LIVE HELP -->
```text
delete-lvm.sh 3.7.1 (project 3.7.1)

USAGE
  delete-lvm.sh <lvm-volume-path> [dryrun]

DESCRIPTION
  Deletes one exact LVM logical volume after showing its metadata and
  requiring the literal DELETE confirmation. Dry-run simulates confirmation
  and deletion; cancellation returns failure.

EXAMPLES
  delete-lvm.sh /dev/pve/vm-123-disk-0-old

HELP
  -h, -?, /h, /?, --help  Show this help and exit.
  --version                Show script and project versions and exit.

DRY-RUN
  Forms: dryrun, --dryrun.
  Dry-run: no system changes are made; modifying commands are printed instead of executed.
```
<!-- END LIVE HELP -->

The same output is stored verbatim in [`delete-lvm.sh.usage`](./delete-lvm.sh.usage).

## Test coverage

- Integration reference: `20-lvm.sh`
- The static suite verifies this helper's POSIX syntax, standalone help/version
  behavior, help aliases, documented parser options, live-help snapshot, and
  documentation synchronization.
- See [`tests/TEST-MATRIX.md`](../tests/TEST-MATRIX.md) for real/negative coverage.

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/delete-lvm.sh" -O "delete-lvm.sh" && chmod +x "delete-lvm.sh"
```

## Examples

```sh
./delete-lvm.sh /dev/pve/vm-123-disk-0-old dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
delete-lvm.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.
