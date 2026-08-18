# `create-disk-copy-and-overwrite-disk-on-vm.sh`

[Back to helper list](../README.md) · [View script](../create-disk-copy-and-overwrite-disk-on-vm.sh) · [Raw usage](./create-disk-copy-and-overwrite-disk-on-vm.sh.usage)

## Purpose

Create and byte-verify an independent copy using a destination backing disk number, exact slot, or first-free bus; replace/archive an occupied exact target or create into an empty slot, with optional `delete`, VM-state handling, and `boot` promotion. `pause` replacement of a running SCSI target is preflight-refused when Proxmox would need to remove a per-disk or last SCSI controller.

## Usage

Run the built-in help without performing the operation:

```sh
./create-disk-copy-and-overwrite-disk-on-vm.sh --help
```

The current built-in help is:

```text
create-disk-copy-and-overwrite-disk-on-vm.sh 3.5.1 (project 3.5.1)

USAGE
  create-disk-copy-and-overwrite-disk-on-vm.sh <source-lv-path> <destination-lv-path> [hot|pause|stop|restart] [delete] [boot] [dryrun]
  create-disk-copy-and-overwrite-disk-on-vm.sh <source-lv-path> <dest-vmid> <dest-disk-N|dest-slot|dest-bus> [hot|pause|stop|restart] [delete] [boot] [dryrun]
  create-disk-copy-and-overwrite-disk-on-vm.sh <source-vmid> <source-disk-N|source-slot> <destination-lv-path> [hot|pause|stop|restart] [delete] [boot] [dryrun]
  create-disk-copy-and-overwrite-disk-on-vm.sh <source-vmid> <source-disk-N|source-slot> <dest-vmid> <dest-disk-N|dest-slot|dest-bus> [hot|pause|stop|restart] [delete] [boot] [dryrun]

DESCRIPTION
  Creates an independent copy from the source and places it on the requested destination
  VM. Existing destination disks are replaced transactionally; empty exact/bus
  destinations create a new disk.

SOURCE SELECTORS
  <source-lv-path>      Full LVM path.
  <source-vmid> disk-N  Resolve a managed vm-/base- backing volume.
  <source-vmid> sata0   Resolve an exact configured QEMU disk slot.
  Source slots such as sata0, ide2, scsi4, and virtio0 must already exist.

DESTINATION SELECTORS
  disk-N       Target that backing disk number. If absent, create it on first free SCSI.
  sata0        Use exactly sata0; replace it if occupied, create there if empty.
  ide2         Use exactly ide2.
  scsi4        Use exactly scsi4.
  virtio0      Use exactly virtio0.
  sata         Use the first free SATA slot and choose a free backing disk number.
  ide          Use the first free IDE slot and choose a free backing disk number.
  scsi         Use the first free SCSI slot and choose a free backing disk number.
  virtio       Use the first free VirtIO slot and choose a free backing disk number.

SOURCE ACTIVATION
  If a valid LVM source exists but has no active block device (common for a
  template/base LV), it is temporarily activated for copy/verification and
  restored to inactive afterward. Its LVM permission is not changed.

DESTINATION VM STATE
  default/hot  Replace/add without pausing or stopping the destination VM.
  pause        Pause a running destination VM during replacement, then resume.
               For SCSI targets, pause requires a shared controller with another
               active SCSI disk. virtio-scsi-single and last-SCSI-controller
               removal are refused before mutation because Proxmox rejects that
               hot-unplug while the VM is suspended.
  stop         Stop a running destination VM and leave it stopped.
  restart      Stop a running destination VM, change the disk, then start it.

OPTIONAL KEYWORDS
  delete       Permanently remove the displaced old disk after successful verification.
               Has no effect when the selected destination slot/disk was empty.
  boot         Make the actual destination slot first in the VM boot order.
  dryrun       Perform real read-only preflight and print mutations without executing them.

  hot, pause, stop, restart, delete, boot, dryrun and --dryrun may appear anywhere.

EXAMPLES
  create-disk-copy-and-overwrite-disk-on-vm.sh 123 sata0 456 sata0 boot dryrun
  create-disk-copy-and-overwrite-disk-on-vm.sh 123 disk-0 456 virtio delete restart boot dryrun
  create-disk-copy-and-overwrite-disk-on-vm.sh /dev/pve/vm-123-disk-0 456 scsi4 pause dryrun
  create-disk-copy-and-overwrite-disk-on-vm.sh /dev/pve/vm-123-disk-0 /dev/pve/vm-456-disk-1 delete dryrun

Dry-run:
  Add dryrun or --dryrun anywhere on the command line.
  Read-only preflight checks still run, but modifying commands are printed
  instead of executed and mutation-dependent verification is simulated.
```

The same output is stored verbatim in [`create-disk-copy-and-overwrite-disk-on-vm.sh.usage`](./create-disk-copy-and-overwrite-disk-on-vm.sh.usage).

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/create-disk-copy-and-overwrite-disk-on-vm.sh" -O "create-disk-copy-and-overwrite-disk-on-vm.sh" && chmod +x "create-disk-copy-and-overwrite-disk-on-vm.sh"
```

## Examples

```sh
./create-disk-copy-and-overwrite-disk-on-vm.sh 123 sata0 456 sata0 pause boot dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
create-disk-copy-and-overwrite-disk-on-vm.sh 3.5.1 (project 3.5.1)
```

This page documents the helper as shipped in project **v3.5.1**.
