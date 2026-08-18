# `list-all-vm-lvm-filesystems.sh`

[Back to helper list](../README.md) · [View script](../list-all-vm-lvm-filesystems.sh) · [Raw usage](./list-all-vm-lvm-filesystems.sh.usage)

## Purpose

List every guest and remaining LVM disk with read-only `partx` partition metadata beside the filesystem/container signature detected directly from the partition bytes, using format-specific colors, broad compatibility rules, and red notes for definite table/content mismatches.

## Usage

Run the built-in help without performing the operation:

```sh
./list-all-vm-lvm-filesystems.sh --help
```

The current built-in help is:

```text
list-all-vm-lvm-filesystems.sh 1.1.0 (project 3.4.7)

USAGE
  list-all-vm-lvm-filesystems.sh [dryrun]

DESCRIPTION
  Lists every LVM volume referenced by Proxmox QEMU/LXC guests, grouped under
  its VMID, then inspects the partition table and the actual content of each
  partition without mounting it or creating partition mappings.

  TABLE_HINT and CONTENT_FORMAT are intentionally separate:

    TABLE_HINT      is derived from the GPT/MBR partition type.
    CONTENT_FORMAT  is detected directly from bytes inside that partition.

  Partition tables do not generally store an exact filesystem format. Generic
  types such as Linux filesystem and Microsoft basic data are therefore shown
  as LINUX-FS or MS-DATA. A red MISMATCH note is printed only when the table
  type provides a meaningful expectation and the detected content violates it.

  LVs with no partition table are probed as a whole-device filesystem.

COLOURS
  NTFS / BitLocker       bright magenta
  FAT / exFAT            bright cyan
  ext2 / ext3 / ext4     bright green
  Btrfs                  bright blue
  XFS                    bright yellow
  swap                   bright red
  LVM / LUKS / RAID      distinct terminal colours
  ZFS                    cyan
  other / unknown        bright white
  mismatch notes         red

SAFETY
  Read-only. Uses partx --show and blkid offset probing only. It does not mount,
  write, run fsck, create partition mappings, or modify device-mapper state.

Dry-run:
  Add dryrun or --dryrun anywhere on the command line.
  Read-only preflight checks still run, but modifying commands are printed
  instead of executed and mutation-dependent verification is simulated.
```

The same output is stored verbatim in [`list-all-vm-lvm-filesystems.sh.usage`](./list-all-vm-lvm-filesystems.sh.usage).

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/list-all-vm-lvm-filesystems.sh" -O "list-all-vm-lvm-filesystems.sh" && chmod +x "list-all-vm-lvm-filesystems.sh"
```

## Examples

```sh
./list-all-vm-lvm-filesystems.sh
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
list-all-vm-lvm-filesystems.sh 1.1.0 (project 3.4.7)
```

This page documents the helper as shipped in project **v3.4.7**.
