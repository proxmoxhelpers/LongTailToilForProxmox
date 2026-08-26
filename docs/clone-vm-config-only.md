# `clone-vm-config-only.sh`

[Back to helper list](../README.md) · [View script](../clone-vm-config-only.sh) · [Raw usage](./clone-vm-config-only.sh.usage)

## Purpose

Create a diskless, identity-sanitized QEMU configuration clone at a new VMID: omit disk/unused/EFI/TPM storage references and identity fields, then recreate NICs so Proxmox generates fresh MAC addresses while preserving other NIC settings.

## Usage

Run the built-in help without performing the operation:

```sh
./clone-vm-config-only.sh --help
```

The current built-in help is:

<!-- BEGIN LIVE HELP -->
```text
clone-vm-config-only.sh 3.7.1 (project 3.7.1)

USAGE
  clone-vm-config-only.sh <source-vmid> <new-vmid> [new-name] [dryrun]

DESCRIPTION
  Creates a diskless, identity-sanitized QEMU configuration clone.

  Storage-backed disks, unusedN entries, EFI/TPM storage references, lock,
  vmgenid and smbios1 identity fields are omitted. NIC definitions are
  recreated so Proxmox generates fresh MAC addresses while preserving the
  non-MAC NIC settings. An optional new VM name may be supplied.

NOTES
  No disk contents are copied. Review the resulting CPU, memory, firmware,
  machine and network settings before adding storage or starting the clone.

HELP
  -h, -?, /h, /?, --help  Show this help and exit.
  --version                Show script and project versions and exit.

DRY-RUN
  Forms: dryrun, --dryrun.
  Dry-run: no system changes are made; modifying commands are printed instead of executed.
```
<!-- END LIVE HELP -->

The same output is stored verbatim in [`clone-vm-config-only.sh.usage`](./clone-vm-config-only.sh.usage).

## Test coverage

- Integration reference: `80-vm-config.sh`
- The static suite verifies this helper's POSIX syntax, standalone help/version
  behavior, help aliases, documented parser options, live-help snapshot, and
  documentation synchronization.
- See [`tests/TEST-MATRIX.md`](../tests/TEST-MATRIX.md) for real/negative coverage.

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/clone-vm-config-only.sh" -O "clone-vm-config-only.sh" && chmod +x "clone-vm-config-only.sh"
```

## Examples

```sh
./clone-vm-config-only.sh 123 456 web-copy dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
clone-vm-config-only.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.
