# `unmount-lvm-drives.sh`

[Back to helper list](../README.md) · [View script](../unmount-lvm-drives.sh) · [Raw usage](./unmount-lvm-drives.sh.usage)

## Purpose

Unmount filesystems sourced from one LVM volume or its `kpartx` partition mappings, then remove only the selected mappings after verifying those sources are no longer mounted.

## Usage and live help

The built-in help is available without performing the operation. The equivalent
help aliases are `-h`, `-?`, `/h`, `/?`, and `--help`.

```sh
./unmount-lvm-drives.sh --help
```

<!-- BEGIN LIVE HELP -->
```text
unmount-lvm-drives.sh 3.7.1 (project 3.7.1)

USAGE
  unmount-lvm-drives.sh <lvm-volume-path> [dryrun]

DESCRIPTION
  Unmounts filesystems whose source is the selected LVM volume or its kpartx
  partition mappings, then removes those mappings only after verifying the
  selected sources are no longer mounted. Empty mount directories created by
  the matching low-level mount workflow are removed when safe.

EXAMPLES
  unmount-lvm-drives.sh /dev/pve/vm-123-disk-0

HELP
  -h, -?, /h, /?, --help  Show this help and exit.
  --version                Show script and project versions and exit.

DRY-RUN
  Forms: dryrun, --dryrun.
  Dry-run: no system changes are made; modifying commands are printed instead of executed.
```
<!-- END LIVE HELP -->

The same output is stored verbatim in [`unmount-lvm-drives.sh.usage`](./unmount-lvm-drives.sh.usage) and is checked byte-for-byte by the static suite.

## Safety and behavior

- Help/version parsing occurs before elevation or Proxmox/LVM preflight.
- Dry-run uses the exact one-line project contract shown in the live help.
- Dry-run proves the selected mount remains; real unmount removes direct-LV mounts and mapper-backed mounts.
- Mapper cleanup stops when a selected source cannot be unmounted; unrelated mount roots are not recursively selected.

## Test coverage

- Integration group: `30-mount.sh`
- Positive / real coverage: Dry-run proves the selected mount remains; real unmount removes direct-LV mounts and mapper-backed mounts.
- Negative / variant coverage: Mapper cleanup stops when a selected source cannot be unmounted; unrelated mount roots are not recursively selected.

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/unmount-lvm-drives.sh" -O "unmount-lvm-drives.sh" && chmod +x "unmount-lvm-drives.sh"
```

## Source documentation

The script is standalone and POSIX `/bin/sh`. Public lifecycle/functions follow
the project style guide. `mount-vm-drive.sh` and `mount-all-vm-drives.sh` are
kept source-identical except for their hard-coded `MOUNT_SCOPE` assignment.

## Version

```text
unmount-lvm-drives.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.

## Related project guidance

See the [POSIX shell style guide](./POSIX-SHELL-STYLE-GUIDE-v3.md), [Proxmox scripting lessons learned](./PROXMOX-SHELL-SCRIPTING-LESSONS-LEARNED.md), and [testing documentation](../tests/README.md).
