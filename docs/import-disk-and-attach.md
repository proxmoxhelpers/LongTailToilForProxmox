# `import-disk-and-attach.sh`

[Back to helper list](../README.md) · [View script](../import-disk-and-attach.sh) · [Raw usage](./import-disk-and-attach.sh.usage)

## Purpose

Import a disk image into Proxmox storage and attach the resulting volume to a QEMU VM.

## Usage

Run the built-in help without performing the operation:

```sh
./import-disk-and-attach.sh --help
```

The current built-in help is:

```text
Usage: import-disk-and-attach.sh <image-file> <vmid> <destination-storage> [scsiN] [dryrun]
Dry-run:
  Add dryrun or --dryrun anywhere on the command line.
  Read-only preflight checks still run, but modifying commands are printed
  instead of executed and mutation-dependent verification is simulated.
```

The same output is stored verbatim in [`import-disk-and-attach.sh.usage`](./import-disk-and-attach.sh.usage).

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/import-disk-and-attach.sh" -O "import-disk-and-attach.sh" && chmod +x "import-disk-and-attach.sh"
```

## Examples

```sh
./import-disk-and-attach.sh ./server.raw 123 local-lvm scsi1 dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
import-disk-and-attach.sh 3.5.1 (project 3.5.1)
```

This page documents the helper as shipped in project **v3.5.1**.
