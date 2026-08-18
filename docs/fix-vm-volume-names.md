# `fix-vm-volume-names.sh`

[Back to helper list](../README.md) · [View script](../fix-vm-volume-names.sh) · [Raw usage](./fix-vm-volume-names.sh.usage)

## Purpose

Repair managed backing LV names whose embedded VMID does not match the referencing guest, including normal disks, `unusedN`, EFI and TPM state volumes; preserve `vm-` vs `base-` and the original `disk-N`, and refuse an exact corrected-name collision instead of silently choosing another number.

## Usage

Run the built-in help without performing the operation:

```sh
./fix-vm-volume-names.sh --help
```

The current built-in help is:

```text
Usage: fix-vm-volume-names.sh <vmid> [dryrun]
Correct mismatched vm-ID-disk-N / base-ID-disk-N backing names while preserving family and disk-N.
Includes normal disks, unusedN, efidiskN and tpmstateN references. Exact managed-name collisions are refused.
Dry-run:
  Add dryrun or --dryrun anywhere on the command line.
  Read-only preflight checks still run, but modifying commands are printed
  instead of executed and mutation-dependent verification is simulated.
```

The same output is stored verbatim in [`fix-vm-volume-names.sh.usage`](./fix-vm-volume-names.sh.usage).

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/fix-vm-volume-names.sh" -O "fix-vm-volume-names.sh" && chmod +x "fix-vm-volume-names.sh"
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
fix-vm-volume-names.sh 3.5.1 (project 3.5.1)
```

This page documents the helper as shipped in project **v3.5.1**.
