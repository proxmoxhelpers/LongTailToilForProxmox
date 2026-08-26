# `fix-vm-volume-names.sh`

[Back to helper list](../README.md) · [View script](../fix-vm-volume-names.sh) · [Raw usage](./fix-vm-volume-names.sh.usage)

## Purpose

On a stopped QEMU VM, repairs already-managed `vm-*`/`base-*` backing LV names whose embedded VMID does not match the referencing guest, preserving family and the original `disk-N`. Only configured managed-name references are repair candidates; unrelated custom/unmanaged LVs are never scanned or renamed. Shared volumes and exact corrected-name collisions are refused.

## Usage

Run the built-in help without performing the operation:

```sh
./fix-vm-volume-names.sh --help
```

The current built-in help is:

<!-- BEGIN LIVE HELP -->
```text
fix-vm-volume-names.sh 3.7.1 (project 3.7.1)

USAGE
  fix-vm-volume-names.sh <vmid> [dryrun]

DESCRIPTION
  Corrects LVM-backed managed names whose embedded VMID does not match the
  referencing QEMU VM, preserving vm-/base- family and the original disk-N.

  Normal disks, unusedN, efidiskN and tpmstateN references are inspected.
  Only configured vm-/base-...-disk-N names are repair candidates. Unrelated
  custom/unmanaged LVs are never scanned or renamed.

SAFETY
  The VM must be stopped. Shared volumes and exact corrected-name collisions
  are refused before mutation.

HELP
  -h, -?, /h, /?, --help  Show this help and exit.
  --version                Show script and project versions and exit.

DRY-RUN
  Forms: dryrun, --dryrun.
  Dry-run: no system changes are made; modifying commands are printed instead of executed.
```
<!-- END LIVE HELP -->

The same output is stored verbatim in [`fix-vm-volume-names.sh.usage`](./fix-vm-volume-names.sh.usage).

## Test coverage

- Integration reference: `60-disk-config.sh`
- The static suite verifies this helper's POSIX syntax, standalone help/version
  behavior, help aliases, documented parser options, live-help snapshot, and
  documentation synchronization.
- See [`tests/TEST-MATRIX.md`](../tests/TEST-MATRIX.md) for real/negative coverage.

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/fix-vm-volume-names.sh" -O "fix-vm-volume-names.sh" && chmod +x "fix-vm-volume-names.sh"
```

## Examples

```sh
./fix-vm-volume-names.sh 123 dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
fix-vm-volume-names.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.
