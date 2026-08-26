# `audit-vm-storage.sh`

[Back to helper list](../README.md) · [View script](../audit-vm-storage.sh) · [Raw usage](./audit-vm-storage.sh.usage)

## Purpose

Audit a local QEMU VM or LXC container's storage-backed references for missing paths, bad mappings and unexpected cross-guest references.

## Usage

Run the built-in help without performing the operation:

```sh
./audit-vm-storage.sh --help
```

The current built-in help is:

<!-- BEGIN LIVE HELP -->
```text
audit-vm-storage.sh 3.7.1 (project 3.7.1)

USAGE
  audit-vm-storage.sh <vmid> [dryrun]

DESCRIPTION
  Audits storage-backed references for a local QEMU VM or LXC container.
  Every referenced volume must resolve through Proxmox storage, and a volume
  referenced by another guest is reported as a failed audit.

SAFETY
  Read-only. The command elevates before inspecting host/cluster storage state.

HELP
  -h, -?, /h, /?, --help  Show this help and exit.
  --version                Show script and project versions and exit.

DRY-RUN
  Forms: dryrun, --dryrun.
  Dry-run: no system changes are made; modifying commands are printed instead of executed.
```
<!-- END LIVE HELP -->

The same output is stored verbatim in [`audit-vm-storage.sh.usage`](./audit-vm-storage.sh.usage).

## Test coverage

- Integration reference: `10-inspection.sh`
- The static suite verifies this helper's POSIX syntax, standalone help/version
  behavior, help aliases, documented parser options, live-help snapshot, and
  documentation synchronization.
- See [`tests/TEST-MATRIX.md`](../tests/TEST-MATRIX.md) for real/negative coverage.

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/audit-vm-storage.sh" -O "audit-vm-storage.sh" && chmod +x "audit-vm-storage.sh"
```

## Examples

```sh
./audit-vm-storage.sh 123
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
audit-vm-storage.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.
