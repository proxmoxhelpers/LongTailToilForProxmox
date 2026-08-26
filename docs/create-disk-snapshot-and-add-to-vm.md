# `create-disk-snapshot-and-add-to-vm.sh`

[Back to helper list](../README.md) · [View script](../create-disk-snapshot-and-add-to-vm.sh) · [Raw usage](./create-disk-snapshot-and-add-to-vm.sh.usage)

## Purpose

Create an LVM-thin snapshot from an LV path or `VMID + selector`; numeric/`disk-N`, exact active/`unusedN` slot selectors resolve managed sources, including template/base LVs sized from LVM metadata, while destination naming automatically uses `base-` for templates or `vm-` for normal VMs, with device selection, state handling and optional `boot` promotion.

## Usage

Run the built-in help without performing the operation:

```sh
./create-disk-snapshot-and-add-to-vm.sh --help
```

The current built-in help is:

<!-- BEGIN LIVE HELP -->
```text
create-disk-snapshot-and-add-to-vm.sh 3.7.1 (project 3.7.1)

USAGE
  create-disk-snapshot-and-add-to-vm.sh <source-lv-path> <dest-vmid> [dest-N|dest-disk-N|dest-slot|dest-bus] [hot|pause|stop|restart] [boot] [dryrun]
  create-disk-snapshot-and-add-to-vm.sh <source-vmid> <N|source-disk-N|source-slot|unusedN> <dest-vmid> [dest-N|dest-disk-N|dest-slot|dest-bus] [hot|pause|stop|restart] [boot] [dryrun]

DESCRIPTION
  Creates an LVM-thin snapshot of the source and attaches it to a destination
  QEMU VM.

SOURCE SELECTORS
  <source-lv-path>      Full LVM path such as /dev/pve/vm-123-disk-0 or /dev/pve/base-123-disk-0.
  <source-vmid> N|disk-N  Resolve a vm-*/base-* managed backing volume by disk number.
  <source-vmid> sata0   Resolve an exact configured QEMU disk slot.
  <source-vmid> unusedN Resolve an exact detached/unused storage-backed disk reference.
  Exact source slots must already exist and must be storage-backed disks.

DESTINATION SELECTORS
  omitted      Attach to the first free SCSI slot; choose the next free disk-N.
  N or disk-N  Use that backing disk number; attach to the first free SCSI slot.
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

HELP
  -h, -?, /h, /?, --help  Show this help and exit.
  --version                Show script and project versions and exit.

DRY-RUN
  Forms: dryrun, --dryrun.
  Dry-run: no system changes are made; modifying commands are printed instead of executed.
```
<!-- END LIVE HELP -->

The same output is stored verbatim in [`create-disk-snapshot-and-add-to-vm.sh.usage`](./create-disk-snapshot-and-add-to-vm.sh.usage).

## Test coverage

- Integration reference: `50-copy-snapshot.sh`
- The static suite verifies this helper's POSIX syntax, standalone help/version
  behavior, help aliases, documented parser options, live-help snapshot, and
  documentation synchronization.
- See [`tests/TEST-MATRIX.md`](../tests/TEST-MATRIX.md) for real/negative coverage.

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/create-disk-snapshot-and-add-to-vm.sh" -O "create-disk-snapshot-and-add-to-vm.sh" && chmod +x "create-disk-snapshot-and-add-to-vm.sh"
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
create-disk-snapshot-and-add-to-vm.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.
