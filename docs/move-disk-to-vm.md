# `move-disk-to-vm.sh`

[Back to helper list](../README.md) · [View script](../move-disk-to-vm.sh) · [Raw usage](./move-disk-to-vm.sh.usage)

## Purpose

Move an LVM-backed disk to another QEMU VM by full LV path or source VM + disk number; numeric selectors understand both `vm-` and `base-` names, with hot/pause/stop/restart source-state control. Source `unusedN` cleanup is config-only so removing the stale source reference cannot free the moved LV. For a running VM losing a SCSI disk in `pause` mode, Proxmox must be able to hot-unplug the disk without removing its controller; `virtio-scsi-single` and last-SCSI-controller removal are refused before mutation.

## Usage

Run the built-in help without performing the operation:

```sh
./move-disk-to-vm.sh --help
```

The current built-in help is:

```text
move-disk-to-vm.sh 3.5.1 (project 3.5.1)

USAGE
  move-disk-to-vm.sh <full-lv-path> <destination-vmid> [pause|stop|restart] [dryrun]
  move-disk-to-vm.sh <source-vmid> <disk-number|slot> <destination-vmid> [pause|stop|restart] [dryrun]

DESCRIPTION
  Moves an existing LVM-backed QEMU disk reference to another QEMU VM without
  copying or renaming the LV. The destination uses its first free SCSI slot.

  The numeric disk form selects a managed backing volume vm-SOURCE-disk-N or base-SOURCE-disk-N; stale embedded IDs are accepted only when the disk number is otherwise unambiguous.
  An explicit source slot such as scsi0, sata1, virtio2, or unused0 is also
  accepted.

SOURCE VM STATE
  default   Hot-swap. Do not stop or pause the source VM.
  pause     Suspend a running source VM before detach, then resume it.
            For SCSI disks, pause requires a shared controller with another
            active SCSI disk; virtio-scsi-single and last-disk controller
            removal are refused before mutation because Proxmox cannot safely
            hot-unplug those controllers while the VM is suspended.
  stop      Stop a running source VM before detach and leave it stopped.
  restart   Stop a running source VM before detach, then start it again.

  pause, stop, restart, dryrun and --dryrun may appear anywhere. Only one of
  pause/stop/restart may be selected. A VM that was already stopped is never
  started automatically.

EXAMPLES
  move-disk-to-vm.sh /dev/pve/vm-123-disk-0 456 dryrun
  move-disk-to-vm.sh 123 0 456 pause dryrun
  move-disk-to-vm.sh restart 123 scsi0 456

Dry-run:
  Add dryrun or --dryrun anywhere on the command line.
  Read-only preflight checks still run, but modifying commands are printed
  instead of executed and mutation-dependent verification is simulated.
```

The same output is stored verbatim in [`move-disk-to-vm.sh.usage`](./move-disk-to-vm.sh.usage).

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/move-disk-to-vm.sh" -O "move-disk-to-vm.sh" && chmod +x "move-disk-to-vm.sh"
```

## Examples

```sh
./move-disk-to-vm.sh 123 0 456 pause dryrun
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
move-disk-to-vm.sh 3.5.1 (project 3.5.1)
```

This page documents the helper as shipped in project **v3.5.1**.
