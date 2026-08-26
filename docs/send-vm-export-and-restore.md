# `send-vm-export-and-restore.sh`

[Back to helper list](../README.md) · [View script](../send-vm-export-and-restore.sh) · [Raw usage](./send-vm-export-and-restore.sh.usage)

## Purpose

Transfers a trusted `.ltvm` archive with `scp`, verifies the complete archive SHA-256 on the destination, then streams and executes the archive's embedded restore program over SSH. Dry-run validates the local archive and prints every remote action without opening SSH. `--preflight` performs read-only remote checks and requires the destination host key to already be trusted.

## Usage and live help

The built-in help is available without performing the operation:

```sh
./send-vm-export-and-restore.sh --help
```

<!-- BEGIN LIVE HELP -->
```text
send-vm-export-and-restore.sh 3.7.1 (project 3.7.1)

USAGE
  send-vm-export-and-restore.sh <archive.ltvm> <root@proxmoxhost>
      [--vmid NEWID] [--storage STORAGE] [--start]
      [--no-content-verify] [--remote-path PATH] [--keep-remote]
      [dryrun|--preflight]

DESCRIPTION
  One-operation transfer + restore. The archive is copied with scp, its complete
  SHA-256 is compared on the destination, then the restore program embedded in
  the archive is streamed over SSH and executed as root. The destination does
  not need this repository or import-vm.sh installed.

PREFLIGHT
  Dry-run validates the local archive and prints the remote actions without
  opening SSH or changing local/remote state. --preflight contacts the
  destination over SSH and checks root identity, required Proxmox restore
  commands, remote-directory writability, and that the requested remote archive
  path is absent. Preflight requires the host key to be already trusted and
  will not add a new key to known_hosts. It transfers nothing and starts no
  restore. Real execution atomically reserves the absent path before scp, so
  an existing remote file or symlink is never silently overwritten.

FAILURE BEHAVIOR
  A failed verification/restore leaves the transferred archive on the remote
  host for diagnosis. Successful restores remove it unless --keep-remote is set.

TRUST
  Send/restore only .ltvm files from a trusted source. Checksums verify archive
  integrity but are not a signature or creator-authentication mechanism.

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

The same output is stored verbatim in [`send-vm-export-and-restore.sh.usage`](./send-vm-export-and-restore.sh.usage) and is checked byte-for-byte by the static suite.

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
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/send-vm-export-and-restore.sh" -O "send-vm-export-and-restore.sh" && chmod +x "send-vm-export-and-restore.sh"
```

## Source documentation

The script is standalone. Function comment blocks follow the project POSIX style guide; every argument-taking function documents its call syntax with `Call:` or the sanctioned full-form `Usage:` field.

## Version

```text
send-vm-export-and-restore.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.

## Related project guidance

See the [POSIX shell style guide](./POSIX-SHELL-STYLE-GUIDE-v3.md), [Proxmox scripting lessons learned](./PROXMOX-SHELL-SCRIPTING-LESSONS-LEARNED.md), and [testing documentation](./testing/README.md).
