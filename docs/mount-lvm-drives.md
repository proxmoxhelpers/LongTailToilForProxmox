# `mount-lvm-drives.sh`

[Back to helper list](../README.md) · [View script](../mount-lvm-drives.sh) · [Raw usage](./mount-lvm-drives.sh.usage)

## Purpose

Mount recognizable filesystems directly from one LVM block volume, using `kpartx` for partitioned media and read-only mode by default.

## Usage and live help

The built-in help is available without performing the operation. The equivalent
help aliases are `-h`, `-?`, `/h`, `/?`, and `--help`.

```sh
./mount-lvm-drives.sh --help
```

<!-- BEGIN LIVE HELP -->
```text
mount-lvm-drives.sh 3.7.1 (project 3.7.1)

USAGE
  mount-lvm-drives.sh <lvm-volume-path> [mount-root] [--ro|--rw] [dryrun]

DESCRIPTION
  Exposes and mounts recognizable filesystems from an LVM block volume.
  Partitioned media is mapped through kpartx; a filesystem directly on the LV
  is mounted as part1. Read-only is the default.

EXAMPLES
  mount-lvm-drives.sh /dev/thinvg/vm-123-disk-1
  mount-lvm-drives.sh /dev/thinvg/vm-123-disk-1 /mnt/vm123
  mount-lvm-drives.sh /dev/thinvg/vm-123-disk-1 --rw

HELP
  -h, -?, /h, /?, --help  Show this help and exit.
  --version                Show script and project versions and exit.

DRY-RUN
  Forms: dryrun, --dryrun.
  Dry-run: no system changes are made; modifying commands are printed instead of executed.
```
<!-- END LIVE HELP -->

The same output is stored verbatim in [`mount-lvm-drives.sh.usage`](./mount-lvm-drives.sh.usage) and is checked byte-for-byte by the static suite.

## Safety and behavior

- Help/version parsing occurs before elevation or Proxmox/LVM preflight.
- Dry-run uses the exact one-line project contract shown in the live help.
- Direct ext4-on-LV read-only mount, disposable read-write mount with persistence verification, and dry-run immutability.
- Partition mapping and low-level cleanup remain restricted to the selected LVM volume.

## Test coverage

- Integration group: `30-mount.sh`
- Positive / real coverage: Direct ext4-on-LV read-only mount, disposable read-write mount with persistence verification, and dry-run immutability.
- Negative / variant coverage: Partition mapping and low-level cleanup remain restricted to the selected LVM volume.

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/mount-lvm-drives.sh" -O "mount-lvm-drives.sh" && chmod +x "mount-lvm-drives.sh"
```

## Source documentation

The script is standalone and POSIX `/bin/sh`. Public lifecycle/functions follow
the project style guide. `mount-vm-drive.sh` and `mount-all-vm-drives.sh` are
kept source-identical except for their hard-coded `MOUNT_SCOPE` assignment.

## Version

```text
mount-lvm-drives.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.

## Related project guidance

See the [POSIX shell style guide](./POSIX-SHELL-STYLE-GUIDE-v3.md), [Proxmox scripting lessons learned](./PROXMOX-SHELL-SCRIPTING-LESSONS-LEARNED.md), and [testing documentation](../tests/README.md).
