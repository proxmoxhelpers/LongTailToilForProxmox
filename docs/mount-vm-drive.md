# `mount-vm-drive.sh`

[Back to helper list](../README.md) · [View script](../mount-vm-drive.sh) · [Raw usage](./mount-vm-drive.sh.usage)

## Purpose

Mount and classify recognizable filesystems from one exact active disk slot of a stopped QEMU VM using the same ownership-tracked engine as `mount-all-vm-drives.sh`.

## Usage and live help

The built-in help is available without performing the operation. The equivalent
help aliases are `-h`, `-?`, `/h`, `/?`, and `--help`.

```sh
./mount-vm-drive.sh --help
```

<!-- BEGIN LIVE HELP -->
```text
mount-vm-drive.sh 3.7.1 (project 3.7.1)

USAGE
  mount-vm-drive.sh <VMID> <disk-slot> [mount-root] [--ro|--rw] [dryrun|--preflight]

DESCRIPTION
  Mounts recognizable filesystems from one exact active disk slot of a stopped
  QEMU VM beneath <mount-root>/<slot>/. The default mount root is
  $PWD/vm-<VMID>. Read-only is the default. The command resolves the Proxmox
  volume to its local block backing, temporarily activates an inactive LVM LV
  with activation-skip preserved when needed, refuses pre-existing mapper
  ownership, verifies every exact mounted source, records only resources owned
  by this invocation, and rolls back partial failures.

  Mounted filesystems are classified as likely Linux root, Windows root, EFI,
  or recovery filesystems when recognizable. The strongest Linux-root candidate
  is reported. Use unmount-all-vm-drives.sh with the same VMID and mount root
  to remove the invocation-owned mounts, mappings, and temporary activations.

ARGUMENTS
  VMID         Numeric local QEMU VM ID. The VM must be stopped.
  disk-slot    Exact ideN, sataN, scsiN, or virtioN active disk slot.
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

The same output is stored verbatim in [`mount-vm-drive.sh.usage`](./mount-vm-drive.sh.usage) and is checked byte-for-byte by the static suite.

## Safety and behavior

- Help/version parsing occurs before elevation or Proxmox/LVM preflight.
- Dry-run uses the exact one-line project contract shown in the live help.
- Direct and partitioned VM-disk mounts, Linux-root role detection, exact mounted-source verification, dry-run immutability, and paired owned cleanup.
- Running VMs, invalid/unconfigured slots, non-block backing, pre-existing mapper ownership, unsafe mount roots, and partial workflows are refused or rolled back.

## Test coverage

- Integration group: `30-mount.sh`
- Positive / real coverage: Direct and partitioned VM-disk mounts, Linux-root role detection, exact mounted-source verification, dry-run immutability, and paired owned cleanup.
- Negative / variant coverage: Running VMs, invalid/unconfigured slots, non-block backing, pre-existing mapper ownership, unsafe mount roots, and partial workflows are refused or rolled back.

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/mount-vm-drive.sh" -O "mount-vm-drive.sh" && chmod +x "mount-vm-drive.sh"
```

## Source documentation

The script is standalone and POSIX `/bin/sh`. Public lifecycle/functions follow
the project style guide. `mount-vm-drive.sh` and `mount-all-vm-drives.sh` are
kept source-identical except for their hard-coded `MOUNT_SCOPE` assignment.

## Version

```text
mount-vm-drive.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.

## Related project guidance

See the [POSIX shell style guide](./POSIX-SHELL-STYLE-GUIDE-v3.md), [Proxmox scripting lessons learned](./PROXMOX-SHELL-SCRIPTING-LESSONS-LEARNED.md), and [testing documentation](../tests/README.md).
