# `list-all-vm-lvm.sh`

[Back to helper list](../README.md) · [View script](../list-all-vm-lvm.sh) · [Raw usage](./list-all-vm-lvm.sh.usage)

## Purpose

List every LVM volume referenced by QEMU/LXC guests grouped under its VMID, then show all remaining LVM volumes.

## Usage

Run the built-in help without performing the operation:

```sh
./list-all-vm-lvm.sh --help
```

The current built-in help is:

<!-- BEGIN LIVE HELP -->
```text
list-all-vm-lvm.sh 3.7.1 (project 3.7.1)

USAGE
  list-all-vm-lvm.sh [dryrun]

DESCRIPTION
  Lists every LVM logical volume referenced by Proxmox QEMU/LXC guests,
  grouped under the guest VMID, followed by all remaining LVM volumes.

  "Remaining" includes normal host/system LVs and orphaned VM-style LVs
  that are not referenced by any visible Proxmox guest configuration.

HELP
  -h, -?, /h, /?, --help  Show this help and exit.
  --version                Show script and project versions and exit.

DRY-RUN
  Forms: dryrun, --dryrun.
  Dry-run: no system changes are made; modifying commands are printed instead of executed.
```
<!-- END LIVE HELP -->

The same output is stored verbatim in [`list-all-vm-lvm.sh.usage`](./list-all-vm-lvm.sh.usage).

## Test coverage

- Integration reference: `10-inspection.sh`
- The static suite verifies this helper's POSIX syntax, standalone help/version
  behavior, help aliases, documented parser options, live-help snapshot, and
  documentation synchronization.
- See [`tests/TEST-MATRIX.md`](../tests/TEST-MATRIX.md) for real/negative coverage.

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/list-all-vm-lvm.sh" -O "list-all-vm-lvm.sh" && chmod +x "list-all-vm-lvm.sh"
```

## Examples

```sh
./list-all-vm-lvm.sh
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
list-all-vm-lvm.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.
