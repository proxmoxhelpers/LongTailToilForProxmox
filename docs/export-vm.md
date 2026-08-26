# `export-vm.sh`

[Back to helper list](../README.md) · [View script](../export-vm.sh) · [Raw usage](./export-vm.sh.usage)

## Purpose

Creates one self-contained LongTail VM archive containing a native compressed Proxmox backup payload, the guest configuration and firewall, storage topology, optional full guest-visible content hashes, checksums, audit-only external metadata and an embedded standalone restore program. Exact restore compares persistent guest configuration but intentionally permits Proxmox to regenerate QEMU `vmgenid`.

## Usage and live help

The built-in help is available without performing the operation:

```sh
./export-vm.sh --help
```

<!-- BEGIN LIVE HELP -->
```text
export-vm.sh 3.7.1 (project 3.7.1)

USAGE
  export-vm.sh <VMID> <output.ltvm> [--stop] [--leave-stopped] [--force]
               [--no-content-hash] [dryrun|--preflight]

DESCRIPTION
  Creates one self-contained LongTail VM archive containing:
    - a native compressed vzdump payload
    - the exact guest config and guest firewall file
    - storage topology and, by default, full guest-visible SHA-256 disk hashes
    - guest-related ACL/HA/replication lines as a non-replayed audit record
    - checksums and an embedded standalone restore program

EXACTNESS / PORTABILITY
  The default exact mode refuses locked guests, snapshots, unusedN disks,
  backup=0 disks, external ISO media, LXC bind mounts and explicit
  host-resource config that
  cannot be recreated from the archive alone. Generated cloud-init media is
  restored from its archived configuration and is marked generated rather than
  byte-hashed. "Exact" means persistent guest configuration, backed-up guest
  storage content, and guest firewall identity. QEMU vmgenid is intentionally
  allowed to regenerate during restore and is excluded from exact config
  comparison. Exactness does not mean preserving physical LV UUID/extents/
  device-mapper identity or the guest's live RAM state.
  Cluster-wide ACL/HA/pool/replication policy is not automatically replayed on
  another cluster because doing so would mutate objects outside the guest;
  relevant lines are carried as an audit record.

STATE
  The guest must be stopped. --stop permits a graceful temporary shutdown and
  the original running state is restored after a successful/failed export unless
  --leave-stopped is requested. No force-stop is performed.

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

The same output is stored verbatim in [`export-vm.sh.usage`](./export-vm.sh.usage) and is checked byte-for-byte by the static suite.

## Safety and behavior

- `--help` and `--version` are handled before privilege/environment gates.
- `dryrun`, `--dryrun`, `--plan`, and `--preflight` use the non-mutating plan path; read-only helpers remain read-only.
- `--no-color` disables ANSI output and `--quiet` reduces non-essential LongTail output where supported.
- Ambiguous guest, slot, storage, or LVM identities are refused rather than guessed.
- For mutating helpers, preflight is completed before the first mutation and postconditions are verified after the operation.
- Integration safety/variant coverage: Corrupt/unsafe archive, identity collision, or transfer/restore preflight refusal without guest/storage mutation.

## Test coverage

- Integration group: [`95-vm-archive.sh`](../tests/groups/95-vm-archive.sh)
- Positive / real coverage: Dry-run immutability plus archive/restore safety contracts; local archive round-trip fixtures where available.
- Negative / variant coverage: Corrupt/unsafe archive, identity collision, or transfer/restore preflight refusal without guest/storage mutation.

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/export-vm.sh" -O "export-vm.sh" && chmod +x "export-vm.sh"
```

## Source documentation

The script is standalone. Function comment blocks follow the project POSIX style guide; every argument-taking function documents its call syntax with `Call:` or the sanctioned full-form `Usage:` field.

## Version

```text
export-vm.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.

## Related project guidance

See the [POSIX shell style guide](./POSIX-SHELL-STYLE-GUIDE-v3.md), [Proxmox scripting lessons learned](./PROXMOX-SHELL-SCRIPTING-LESSONS-LEARNED.md), and [testing documentation](./testing/README.md).
