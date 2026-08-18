# `verify-vm-disk-numbering.sh`

[Back to helper list](../README.md) · [View script](../verify-vm-disk-numbering.sh) · [Raw usage](./verify-vm-disk-numbering.sh.usage)

## Purpose

Verify all guest LVM disk numbering, highlighting embedded VMID mismatches in red and active numbering that starts above `disk-0`, contains gaps, or contains duplicate `disk-N` values in yellow; `unusedN` archive entries are shown but excluded from sequence checks.

## Usage

Run the built-in help without performing the operation:

```sh
./verify-vm-disk-numbering.sh --help
```

The current built-in help is:

```text
verify-vm-disk-numbering.sh 3.5.1 (project 3.5.1)

USAGE
  verify-vm-disk-numbering.sh [dryrun]

DESCRIPTION
  Lists every LVM volume referenced by Proxmox QEMU/LXC guests and verifies
  managed Proxmox disk numbering.

  Red rows identify managed LVs whose embedded VMID does not match the guest
  that references them, for example VM 199 -> base-100-disk-1.

  Yellow guest headings identify ACTIVE managed LVM disk-number problems:
  numbering that does not start at disk-0, gaps in the sequence, or duplicate
  disk-N values. unusedN entries are listed but do not participate in the
  active numbering sequence.

  Both vm-VMID-disk-N and base-VMID-disk-N are recognized. All LVs not
  referenced by a visible guest are listed at the end.

COLOURS
  green   numbering looks consistent
  yellow  active managed disk numbering does not start at 0
  red     an LV embeds a different VMID than the guest that references it
  cyan    informational / unmanaged LVM reference

Dry-run:
  Add dryrun or --dryrun anywhere on the command line.
  Read-only preflight checks still run, but modifying commands are printed
  instead of executed and mutation-dependent verification is simulated.
```

The same output is stored verbatim in [`verify-vm-disk-numbering.sh.usage`](./verify-vm-disk-numbering.sh.usage).

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/verify-vm-disk-numbering.sh" -O "verify-vm-disk-numbering.sh" && chmod +x "verify-vm-disk-numbering.sh"
```

## Examples

```sh
./verify-vm-disk-numbering.sh
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
verify-vm-disk-numbering.sh 3.5.1 (project 3.5.1)
```

This page documents the helper as shipped in project **v3.5.1**.
