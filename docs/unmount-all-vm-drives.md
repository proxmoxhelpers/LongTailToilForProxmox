# `unmount-all-vm-drives.sh`

[Back to helper list](../README.md) · [View script](../unmount-all-vm-drives.sh) · [Raw usage](./unmount-all-vm-drives.sh.usage)

## Purpose

Safely remove only the mounts, mapper devices, temporary LVM activations, and empty directories recorded by `mount-vm-drive.sh` or `mount-all-vm-drives.sh`.

## Usage and live help

The built-in help is available without performing the operation. The equivalent
help aliases are `-h`, `-?`, `/h`, `/?`, and `--help`.

```sh
./unmount-all-vm-drives.sh --help
```

<!-- BEGIN LIVE HELP -->
```text
unmount-all-vm-drives.sh 3.7.1 (project 3.7.1)

USAGE
  unmount-all-vm-drives.sh <VMID> [mount-root] [dryrun|--preflight]

DESCRIPTION
  Safely removes the invocation-owned filesystems, partition mappings, temporary
  LVM activations, and empty directories recorded by mount-vm-drive.sh or
  mount-all-vm-drives.sh for the same VMID and mount root. The default mount
  root is $PWD/vm-<VMID>.

  The root-owned state file is required. Before the first unmount, every still
  mounted target is verified to have the same canonical source recorded by the
  mount invocation. Mapper cleanup is refused while a recorded partition remains
  mounted, and unrelated mounts or resources are never selected recursively.

ARGUMENTS
  VMID         Numeric local QEMU VM ID.
  mount-root   Root used by the matching mount command.
               Default: $PWD/vm-<VMID>.

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

The same output is stored verbatim in [`unmount-all-vm-drives.sh.usage`](./unmount-all-vm-drives.sh.usage) and is checked byte-for-byte by the static suite.

## Safety and behavior

- Help/version parsing occurs before elevation or Proxmox/LVM preflight.
- Dry-run uses the exact one-line project contract shown in the live help.
- Consumes the root-owned state file, verifies exact current mount-source identity, unmounts in reverse order, removes owned mappings, and restores temporary activation state.
- Missing/symlink/non-root-owned state, changed mount identity, busy mapper partitions, `/`, and symlink mount roots are refused.

## Test coverage

- Integration group: 30-mount.sh` and `85-qol-workflows.sh
- Positive / real coverage: Consumes the root-owned state file, verifies exact current mount-source identity, unmounts in reverse order, removes owned mappings, and restores temporary activation state.
- Negative / variant coverage: Missing/symlink/non-root-owned state, changed mount identity, busy mapper partitions, `/`, and symlink mount roots are refused.

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/unmount-all-vm-drives.sh" -O "unmount-all-vm-drives.sh" && chmod +x "unmount-all-vm-drives.sh"
```

## Source documentation

The script is standalone and POSIX `/bin/sh`. Public lifecycle/functions follow
the project style guide. `mount-vm-drive.sh` and `mount-all-vm-drives.sh` are
kept source-identical except for their hard-coded `MOUNT_SCOPE` assignment.

## Version

```text
unmount-all-vm-drives.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.

## Related project guidance

See the [POSIX shell style guide](./POSIX-SHELL-STYLE-GUIDE-v3.md), [Proxmox scripting lessons learned](./PROXMOX-SHELL-SCRIPTING-LESSONS-LEARNED.md), and [testing documentation](../tests/README.md).
