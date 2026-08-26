# `cleanup-unused-disks.sh`

[Back to helper list](../README.md) · [View script](../cleanup-unused-disks.sh) · [Raw usage](./cleanup-unused-disks.sh.usage)

## Purpose

List `unusedN` disks on a QEMU VM, or—when the VM is stopped—delete selected/all unused disks with shared-reference checks.

## Usage

Run the built-in help without performing the operation:

```sh
./cleanup-unused-disks.sh --help
```

The current built-in help is:

<!-- BEGIN LIVE HELP -->
```text
cleanup-unused-disks.sh 3.7.1 (project 3.7.1)

USAGE
  cleanup-unused-disks.sh <vmid> [unusedN ... | --all] [dryrun]

DESCRIPTION
  With no unusedN/--all selector, lists the VM's unused disk references.
  With explicit unusedN keys or --all, permanently deletes the selected
  backing volumes and removes their unusedN references.

SAFETY
  Listing is read-only and does not require the VM to be stopped.
  Deletion requires the QEMU VM to be stopped and refuses shared volumes.

HELP
  -h, -?, /h, /?, --help  Show this help and exit.
  --version                Show script and project versions and exit.

DRY-RUN
  Forms: dryrun, --dryrun.
  Dry-run: no system changes are made; modifying commands are printed instead of executed.
```
<!-- END LIVE HELP -->

The same output is stored verbatim in [`cleanup-unused-disks.sh.usage`](./cleanup-unused-disks.sh.usage).

## Test coverage

- Integration reference: `40-disk-lifecycle.sh`
- The static suite verifies this helper's POSIX syntax, standalone help/version
  behavior, help aliases, documented parser options, live-help snapshot, and
  documentation synchronization.
- See [`tests/TEST-MATRIX.md`](../tests/TEST-MATRIX.md) for real/negative coverage.

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/cleanup-unused-disks.sh" -O "cleanup-unused-disks.sh" && chmod +x "cleanup-unused-disks.sh"
```

## Examples

```sh
./cleanup-unused-disks.sh 123 --all dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
cleanup-unused-disks.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.
