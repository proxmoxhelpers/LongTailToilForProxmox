# `mount-all-vm-drives.sh`

[Back to helper list](../README.md) · [View script](../mount-all-vm-drives.sh) · [Raw usage](./mount-all-vm-drives.sh.usage)

## Purpose

Mount and classify recognizable filesystems from all active block-backed disks of a stopped QEMU VM with the same mount engine used by `mount-vm-drive.sh`.

## Usage and live help

The built-in help is available without performing the operation. The equivalent
help aliases are `-h`, `-?`, `/h`, `/?`, and `--help`.

```sh
./mount-all-vm-drives.sh --help
```

<!-- BEGIN LIVE HELP -->
```text
mount-all-vm-drives.sh 3.7.1 (project 3.7.1)

USAGE
  mount-all-vm-drives.sh <VMID> [mount-root] [--ro|--rw] [dryrun|--preflight]

DESCRIPTION
  Mounts recognizable filesystems from every active block-backed disk of a
  stopped QEMU VM beneath <mount-root>/<slot>/. The default mount root is
  $PWD/vm-<VMID>. Read-only is the default. Each disk uses the same resolver,
  activation, partition mapping, exact mount verification, ownership tracking,
  filesystem-role classification, and rollback logic as mount-vm-drive.sh.

  Pre-existing mapper ownership is refused. Partial failures are rolled back.
  The strongest Linux-root candidate across all mounted filesystems is reported.
  Use unmount-all-vm-drives.sh with the same VMID and mount root for cleanup.

ARGUMENTS
  VMID         Numeric local QEMU VM ID. The VM must be stopped.
  mount-root   Absolute destination root. Default: $PWD/vm-<VMID>.

OPTIONS
  --ro         Mount filesystems read-only (default).
  --rw         Mount filesystems read-write.

COMMON OPTIONS
  -h, -?, /h, /?, --help  Show this help and exit.
  --version               Show script and project versions and exit.
  dryrun, --dryrun,
  --plan                  Enable dry-run/plan mode.
  --preflight             Run the same non-mutating preflight/plan path.
  --no-color              Disable ANSI colour output.
  --quiet                 Reduce non-essential LongTail output where supported.

  Common options may appear anywhere on the command line.
  Dry-run: no system changes are made; modifying commands are printed instead of executed.
```
<!-- END LIVE HELP -->

The same output is stored verbatim in [`mount-all-vm-drives.sh.usage`](./mount-all-vm-drives.sh.usage) and is checked byte-for-byte by the static suite.

## Safety and behavior

- Help/version parsing occurs before elevation or Proxmox/LVM preflight.
- Dry-run uses the exact one-line project contract shown in the live help.
- Whole-VM direct and partitioned disk mounting, strongest Linux-root reporting, ownership-state creation, dry-run immutability, and paired cleanup.
- Running VMs, non-block backing, pre-existing mapper ownership, unsafe roots, and partial failures are refused or rolled back without selecting unrelated resources.

## Test coverage

- Integration group: 30-mount.sh` and `85-qol-workflows.sh
- Positive / real coverage: Whole-VM direct and partitioned disk mounting, strongest Linux-root reporting, ownership-state creation, dry-run immutability, and paired cleanup.
- Negative / variant coverage: Running VMs, non-block backing, pre-existing mapper ownership, unsafe roots, and partial failures are refused or rolled back without selecting unrelated resources.

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/mount-all-vm-drives.sh" -O "mount-all-vm-drives.sh" && chmod +x "mount-all-vm-drives.sh"
```

## Source documentation

The script is standalone and POSIX `/bin/sh`. Public lifecycle/functions follow
the project style guide. `mount-vm-drive.sh` and `mount-all-vm-drives.sh` are
kept source-identical except for their hard-coded `MOUNT_SCOPE` assignment.

## Version

```text
mount-all-vm-drives.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.

## Related project guidance

See the [POSIX shell style guide](./POSIX-SHELL-STYLE-GUIDE-v3.md), [Proxmox scripting lessons learned](./PROXMOX-SHELL-SCRIPTING-LESSONS-LEARNED.md), and [testing documentation](../tests/README.md).
