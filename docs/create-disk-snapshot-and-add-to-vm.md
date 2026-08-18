# `create-disk-snapshot-and-add-to-vm.sh`

[Back to helper list](../README.md) · [View script](../create-disk-snapshot-and-add-to-vm.sh) · [Raw usage](./create-disk-snapshot-and-add-to-vm.sh.usage)

## Purpose

Create an LVM-thin snapshot from an LV path, `VMID + disk-N`, or `VMID + exact-slot`; `disk-N` resolves `vm-` or `base-` sources, including template/base LVs sized from LVM metadata, and destination naming automatically uses `base-` for templates or `vm-` for normal VMs, with device selection, state handling and optional `boot` promotion.

## Usage

Run the built-in help without performing the operation:

```sh
./create-disk-snapshot-and-add-to-vm.sh --help
```

The current built-in help is:

```text
create-disk-snapshot-and-add-to-vm.sh 3.4.4 (project 3.4.7)

USAGE
  create-disk-snapshot-and-add-to-vm.sh <source-lv-path> <dest-vmid> [dest-disk-N|dest-slot|dest-bus] [hot|pause|stop|restart] [boot] [dryrun]
  create-disk-snapshot-and-add-to-vm.sh <source-vmid> <source-disk-N|source-slot> <dest-vmid> [dest-disk-N|dest-slot|dest-bus] [hot|pause|stop|restart] [boot] [dryrun]

DESCRIPTION
  Creates an LVM-thin snapshot of the source and attaches it to a destination
  QEMU VM.

SOURCE SELECTORS
  <source-lv-path>      Full LVM path such as /dev/pve/vm-123-disk-0 or /dev/pve/base-123-disk-0.
  <source-vmid> disk-N  Resolve a vm-*/base-* managed backing volume by disk number.
  <source-vmid> sata0   Resolve an exact configured QEMU disk slot.
  Exact source slots must already exist and must be storage-backed disks.

DESTINATION SELECTORS
  omitted      Attach to the first free SCSI slot; choose the next free disk-N.
  disk-N       Use that backing disk number; attach to the first free SCSI slot.
  sata0        Attach specifically at sata0; choose the next free backing disk-N.
  ide2         Attach specifically at ide2.
  scsi4        Attach specifically at scsi4.
  virtio0      Attach specifically at virtio0.
  sata         Attach to the first free SATA slot.
  ide          Attach to the first free IDE slot.
  scsi         Attach to the first free SCSI slot.
  virtio       Attach to the first free VirtIO slot.

  Exact destination slots must be empty. Use an overwrite helper when the
  selected slot is already occupied.

SOURCE VM STATE
  default/hot  Do not pause or stop the source VM.
  pause        Pause a running source VM while the snapshot is created/attached.
  stop         Stop a running source VM and leave it stopped.
  restart      Stop a running source VM, create/attach the snapshot, then start it.

OPTIONAL KEYWORDS
  boot         Make the actual destination slot the first device in VM boot order.
  dryrun       Perform real read-only preflight and print mutations without executing them.

EXAMPLES
  create-disk-snapshot-and-add-to-vm.sh /dev/pve/vm-123-disk-0 456 sata boot dryrun
  create-disk-snapshot-and-add-to-vm.sh 123 ide2 456 virtio0 restart boot dryrun
  create-disk-snapshot-and-add-to-vm.sh 123 disk-0 456 disk-3 pause dryrun

Dry-run:
  Add dryrun or --dryrun anywhere on the command line.
  Read-only preflight checks still run, but modifying commands are printed
  instead of executed and mutation-dependent verification is simulated.
```

The same output is stored verbatim in [`create-disk-snapshot-and-add-to-vm.sh.usage`](./create-disk-snapshot-and-add-to-vm.sh.usage).

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/create-disk-snapshot-and-add-to-vm.sh" -O "create-disk-snapshot-and-add-to-vm.sh" && chmod +x "create-disk-snapshot-and-add-to-vm.sh"
```

## Examples

```sh
./create-disk-snapshot-and-add-to-vm.sh 123 sata0 456 virtio boot pause dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
create-disk-snapshot-and-add-to-vm.sh 3.4.4 (project 3.4.7)
```

This page documents the helper as shipped in project **v3.4.7**.
