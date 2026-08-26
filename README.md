# LongTailToilForProxmox

**LongTailToilForProxmox** is a collection of 81 self-contained, safety-focused helpers for the Proxmox jobs that are easy to automate but awkward to remember because they happen infrequently, covering VMIDs, LVM/LVM-thin volumes, disks, mounts, storage, recovery and repetitive VM configuration changes. Each helper is a single portable `.sh` file, and modifying commands support `dryrun` so you can perform real read-only preflight checks and review the planned changes before anything is modified.

## The 81 helpers

### VM identity, recovery and inspection

#### [`change-vmid-of-vm.sh`](change-vmid-of-vm.sh) · [doc](docs/change-vmid-of-vm.md) · [usage](docs/change-vmid-of-vm.sh.usage)

Change the VMID of a local QEMU VM or LXC container on LVM/LVM-thin, stopping a running guest first, renaming both `vm-OLDID-*` and template `base-OLDID-*` volumes while preserving their family, and intentionally leaving the renamed guest stopped after preflight, backup, verification and rollback protection.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/change-vmid-of-vm.sh" -O "change-vmid-of-vm.sh" && chmod +x "change-vmid-of-vm.sh"
```

```sh
./change-vmid-of-vm.sh 123 456 dryrun
```

#### [`clone-vm-config-only.sh`](clone-vm-config-only.sh) · [doc](docs/clone-vm-config-only.md) · [usage](docs/clone-vm-config-only.sh.usage)

Create a diskless, identity-sanitized QEMU configuration clone at a new VMID: omit disk/unused/EFI/TPM storage references and identity fields, then recreate NICs so Proxmox generates fresh MAC addresses while preserving other NIC settings.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/clone-vm-config-only.sh" -O "clone-vm-config-only.sh" && chmod +x "clone-vm-config-only.sh"
```

```sh
./clone-vm-config-only.sh 123 456 web-copy dryrun
```

#### [`recover-vm-from-volumes.sh`](recover-vm-from-volumes.sh) · [doc](docs/recover-vm-from-volumes.md) · [usage](docs/recover-vm-from-volumes.sh.usage)

Recreate a basic QEMU VM configuration from existing `vm-VMID-disk-N` and/or `base-VMID-disk-N` LVM volumes.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/recover-vm-from-volumes.sh" -O "recover-vm-from-volumes.sh" && chmod +x "recover-vm-from-volumes.sh"
```

```sh
./recover-vm-from-volumes.sh 456 pve dryrun
```

#### [`list-vm-disks.sh`](list-vm-disks.sh) · [doc](docs/list-vm-disks.md) · [usage](docs/list-vm-disks.sh.usage)

List a QEMU VM's configured disks, resolved storage paths and available LVM metadata.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/list-vm-disks.sh" -O "list-vm-disks.sh" && chmod +x "list-vm-disks.sh"
```

```sh
./list-vm-disks.sh 123
```

#### [`list-all-vm-lvm.sh`](list-all-vm-lvm.sh) · [doc](docs/list-all-vm-lvm.md) · [usage](docs/list-all-vm-lvm.sh.usage)

List every LVM volume referenced by QEMU/LXC guests grouped under its VMID, then show all remaining LVM volumes.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/list-all-vm-lvm.sh" -O "list-all-vm-lvm.sh" && chmod +x "list-all-vm-lvm.sh"
```

```sh
./list-all-vm-lvm.sh
```

#### [`verify-vm-disk-numbering.sh`](verify-vm-disk-numbering.sh) · [doc](docs/verify-vm-disk-numbering.md) · [usage](docs/verify-vm-disk-numbering.sh.usage)

Verify all guest LVM disk numbering, highlighting embedded VMID mismatches in red and active numbering that starts above `disk-0`, contains gaps, or contains duplicate `disk-N` values in yellow; `unusedN` archive entries are shown but excluded from sequence checks.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/verify-vm-disk-numbering.sh" -O "verify-vm-disk-numbering.sh" && chmod +x "verify-vm-disk-numbering.sh"
```

```sh
./verify-vm-disk-numbering.sh
```

#### [`audit-vm-storage.sh`](audit-vm-storage.sh) · [doc](docs/audit-vm-storage.md) · [usage](docs/audit-vm-storage.sh.usage)

Audit a local QEMU VM or LXC container's storage-backed references for missing paths, bad mappings and unexpected cross-guest references.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/audit-vm-storage.sh" -O "audit-vm-storage.sh" && chmod +x "audit-vm-storage.sh"
```

```sh
./audit-vm-storage.sh 123
```

#### [`find-volume-owner.sh`](find-volume-owner.sh) · [doc](docs/find-volume-owner.md) · [usage](docs/find-volume-owner.sh.usage)

Find which local guest configuration references a specific LVM path or Proxmox volume ID.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/find-volume-owner.sh" -O "find-volume-owner.sh" && chmod +x "find-volume-owner.sh"
```

```sh
./find-volume-owner.sh /dev/pve/vm-123-disk-0
```

#### [`find-orphaned-volumes.sh`](find-orphaned-volumes.sh) · [doc](docs/find-orphaned-volumes.md) · [usage](docs/find-orphaned-volumes.sh.usage)

Find unreferenced Proxmox-managed `vm-VMID-disk-N` and `base-VMID-disk-N` LVM volumes.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/find-orphaned-volumes.sh" -O "find-orphaned-volumes.sh" && chmod +x "find-orphaned-volumes.sh"
```

```sh
./find-orphaned-volumes.sh pve
```

### Raw LVM operations

#### [`copy-lvm.sh`](copy-lvm.sh) · [doc](docs/copy-lvm.md) · [usage](docs/copy-lvm.sh.usage)

Create and byte-verify an independent copy of an LVM/LVM-thin logical volume.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/copy-lvm.sh" -O "copy-lvm.sh" && chmod +x "copy-lvm.sh"
```

```sh
./copy-lvm.sh /dev/pve/vm-123-disk-0 /dev/fastvg/vm-123-disk-0-copy dryrun
```

#### [`move-lvm.sh`](move-lvm.sh) · [doc](docs/move-lvm.md) · [usage](docs/move-lvm.sh.usage)

Rename an LV in place within a VG, or copy-verify-delete it safely when moving across VGs.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/move-lvm.sh" -O "move-lvm.sh" && chmod +x "move-lvm.sh"
```

```sh
./move-lvm.sh /dev/pve/vm-123-disk-0 /dev/fastvg/vm-123-disk-0 dryrun
```

#### [`rename-lvm.sh`](rename-lvm.sh) · [doc](docs/rename-lvm.md) · [usage](docs/rename-lvm.sh.usage)

Rename an LVM logical volume after validating its source and destination names.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/rename-lvm.sh" -O "rename-lvm.sh" && chmod +x "rename-lvm.sh"
```

```sh
./rename-lvm.sh /dev/pve/vm-123-disk-0 vm-123-disk-0-old dryrun
```

#### [`delete-lvm.sh`](delete-lvm.sh) · [doc](docs/delete-lvm.md) · [usage](docs/delete-lvm.sh.usage)

Delete an LVM logical volume with exact `DELETE` confirmation and post-delete verification; cancellation exits non-zero for automation-safe refusal handling.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/delete-lvm.sh" -O "delete-lvm.sh" && chmod +x "delete-lvm.sh"
```

```sh
./delete-lvm.sh /dev/pve/vm-123-disk-0-old dryrun
```

### Mounting and filesystem inspection

#### [`list-all-vm-lvm-filesystems.sh`](list-all-vm-lvm-filesystems.sh) · [doc](docs/list-all-vm-lvm-filesystems.md) · [usage](docs/list-all-vm-lvm-filesystems.sh.usage)

List every guest and remaining LVM disk with read-only `partx` partition metadata beside the filesystem/container signature detected directly from the partition bytes, using format-specific colors, broad compatibility rules, and red notes for definite table/content mismatches.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/list-all-vm-lvm-filesystems.sh" -O "list-all-vm-lvm-filesystems.sh" && chmod +x "list-all-vm-lvm-filesystems.sh"
```

```sh
./list-all-vm-lvm-filesystems.sh
```

#### [`mount-lvm-drives.sh`](mount-lvm-drives.sh) · [doc](docs/mount-lvm-drives.md) · [usage](docs/mount-lvm-drives.sh.usage)

Mount recognizable filesystems directly from one LVM block volume, using `kpartx` for partitioned media and read-only mode by default.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/mount-lvm-drives.sh" -O "mount-lvm-drives.sh" && chmod +x "mount-lvm-drives.sh"
```

```sh
./mount-lvm-drives.sh /dev/pve/vm-123-disk-0 /mnt/lv123 --ro
```

#### [`unmount-lvm-drives.sh`](unmount-lvm-drives.sh) · [doc](docs/unmount-lvm-drives.md) · [usage](docs/unmount-lvm-drives.sh.usage)

Unmount filesystems sourced from one LVM volume or its `kpartx` mappings, then remove only those mappings after selected-source verification.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/unmount-lvm-drives.sh" -O "unmount-lvm-drives.sh" && chmod +x "unmount-lvm-drives.sh"
```

```sh
./unmount-lvm-drives.sh /dev/pve/vm-123-disk-0
```

#### [`mount-vm-drive.sh`](mount-vm-drive.sh) · [doc](docs/mount-vm-drive.md) · [usage](docs/mount-vm-drive.sh.usage)

Mount one exact active disk slot of a stopped QEMU VM, classify Linux-root/Windows-root/EFI/recovery filesystems, and report the strongest Linux-root candidate using the same ownership-tracked engine as the all-drive command.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/mount-vm-drive.sh" -O "mount-vm-drive.sh" && chmod +x "mount-vm-drive.sh"
```

```sh
./mount-vm-drive.sh 123 scsi0 /mnt/vm123 --ro
```

#### [`mount-all-vm-drives.sh`](mount-all-vm-drives.sh) · [doc](docs/mount-all-vm-drives.md) · [usage](docs/mount-all-vm-drives.sh.usage)

Mount and classify recognizable filesystems from every active block-backed disk of a stopped QEMU VM. It uses the same mount engine as `mount-vm-drive.sh`; only disk selection changes from one exact slot to all active slots.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/mount-all-vm-drives.sh" -O "mount-all-vm-drives.sh" && chmod +x "mount-all-vm-drives.sh"
```

```sh
./mount-all-vm-drives.sh 123 /mnt/vm123 --ro
```

#### [`unmount-all-vm-drives.sh`](unmount-all-vm-drives.sh) · [doc](docs/unmount-all-vm-drives.md) · [usage](docs/unmount-all-vm-drives.sh.usage)

Remove only the mounts, mapper devices, temporary LVM activations, and empty directories recorded by `mount-vm-drive.sh` or `mount-all-vm-drives.sh`, after re-verifying each recorded mount source.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/unmount-all-vm-drives.sh" -O "unmount-all-vm-drives.sh" && chmod +x "unmount-all-vm-drives.sh"
```

```sh
./unmount-all-vm-drives.sh 123 /mnt/vm123
```

### VM disk lifecycle

#### [`move-disk-to-vm.sh`](move-disk-to-vm.sh) · [doc](docs/move-disk-to-vm.md) · [usage](docs/move-disk-to-vm.sh.usage)

Move an LVM-backed disk to another QEMU VM by full LV path or source VM + disk number; numeric selectors understand both `vm-` and `base-` names, with hot/pause/stop/restart source-state control. Source `unusedN` cleanup is config-only so removing the stale source reference cannot free the moved LV. For a running VM losing a SCSI disk in `pause` mode, Proxmox must be able to hot-unplug the disk without removing its controller; `virtio-scsi-single` and last-SCSI-controller removal are refused before mutation.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/move-disk-to-vm.sh" -O "move-disk-to-vm.sh" && chmod +x "move-disk-to-vm.sh"
```

```sh
./move-disk-to-vm.sh 123 0 456 pause dryrun
```

#### [`attach-existing-lvm-to-vm.sh`](attach-existing-lvm-to-vm.sh) · [doc](docs/attach-existing-lvm-to-vm.md) · [usage](docs/attach-existing-lvm-to-vm.sh.usage)

Attach an existing LVM volume to a QEMU VM as a SCSI disk without copying it.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/attach-existing-lvm-to-vm.sh" -O "attach-existing-lvm-to-vm.sh" && chmod +x "attach-existing-lvm-to-vm.sh"
```

```sh
./attach-existing-lvm-to-vm.sh /dev/pve/vm-123-disk-2 123 scsi2 dryrun
```

#### [`detach-disk-from-vm.sh`](detach-disk-from-vm.sh) · [doc](docs/detach-disk-from-vm.md) · [usage](docs/detach-disk-from-vm.sh.usage)

Detach a disk slot from a stopped QEMU VM while preserving the backing volume as an `unusedN` entry.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/detach-disk-from-vm.sh" -O "detach-disk-from-vm.sh" && chmod +x "detach-disk-from-vm.sh"
```

```sh
./detach-disk-from-vm.sh 123 scsi2 dryrun
```

#### [`delete-disk-from-vm.sh`](delete-disk-from-vm.sh) · [doc](docs/delete-disk-from-vm.md) · [usage](docs/delete-disk-from-vm.sh.usage)

On a stopped QEMU VM, permanently delete a disk or `unusedN` volume from both the guest configuration and backing Proxmox storage, refusing shared volumes.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/delete-disk-from-vm.sh" -O "delete-disk-from-vm.sh" && chmod +x "delete-disk-from-vm.sh"
```

```sh
./delete-disk-from-vm.sh 123 unused0 dryrun
```

#### [`cleanup-unused-disks.sh`](cleanup-unused-disks.sh) · [doc](docs/cleanup-unused-disks.md) · [usage](docs/cleanup-unused-disks.sh.usage)

List `unusedN` disks on a QEMU VM, or—when the VM is stopped—delete selected/all unused disks with shared-reference checks.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/cleanup-unused-disks.sh" -O "cleanup-unused-disks.sh" && chmod +x "cleanup-unused-disks.sh"
```

```sh
./cleanup-unused-disks.sh 123 --all dryrun
```

### Disk copy, snapshot and cloning

#### [`create-disk-snapshot-and-add-to-vm.sh`](create-disk-snapshot-and-add-to-vm.sh) · [doc](docs/create-disk-snapshot-and-add-to-vm.md) · [usage](docs/create-disk-snapshot-and-add-to-vm.sh.usage)

Create an LVM-thin snapshot from an LV path or `VMID + selector`; numeric/`disk-N`, exact active/`unusedN` slot selectors resolve managed sources, including template/base LVs sized from LVM metadata, while destination naming automatically uses `base-` for templates or `vm-` for normal VMs, with device selection, state handling and optional `boot` promotion.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/create-disk-snapshot-and-add-to-vm.sh" -O "create-disk-snapshot-and-add-to-vm.sh" && chmod +x "create-disk-snapshot-and-add-to-vm.sh"
```

```sh
./create-disk-snapshot-and-add-to-vm.sh 123 sata0 456 virtio boot pause dryrun
```

#### [`create-disk-copy-and-add-to-vm.sh`](create-disk-copy-and-add-to-vm.sh) · [doc](docs/create-disk-copy-and-add-to-vm.md) · [usage](docs/create-disk-copy-and-add-to-vm.sh.usage)

Create a full verified copy from an LV path or `VMID + selector`; numeric/`disk-N`, exact active/`unusedN` slot selectors resolve managed sources, including template/base LVs sized from LVM metadata, while destination naming automatically uses `base-` for templates or `vm-` for normal VMs, with destination VG/device selection, state handling and optional `boot` promotion.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/create-disk-copy-and-add-to-vm.sh" -O "create-disk-copy-and-add-to-vm.sh" && chmod +x "create-disk-copy-and-add-to-vm.sh"
```

```sh
./create-disk-copy-and-add-to-vm.sh 123 scsi0 456 sata fastvg restart boot dryrun
```

#### [`create-disk-copy-and-overwrite-disk-on-vm.sh`](create-disk-copy-and-overwrite-disk-on-vm.sh) · [doc](docs/create-disk-copy-and-overwrite-disk-on-vm.md) · [usage](docs/create-disk-copy-and-overwrite-disk-on-vm.sh.usage)

Create and byte-verify an independent copy using a destination backing disk number, exact slot, first-free bus, or an LV path that must have exactly one active QEMU reference; replace/archive an occupied target or create into an empty slot, with optional `delete`, VM-state handling, and `boot` promotion. `pause` replacement of an unsafe SCSI topology is refused before mutation.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/create-disk-copy-and-overwrite-disk-on-vm.sh" -O "create-disk-copy-and-overwrite-disk-on-vm.sh" && chmod +x "create-disk-copy-and-overwrite-disk-on-vm.sh"
```

```sh
./create-disk-copy-and-overwrite-disk-on-vm.sh 123 sata0 456 sata0 pause boot dryrun
```

#### [`create-disk-snapshot-and-overwrite-disk-on-vm.sh`](create-disk-snapshot-and-overwrite-disk-on-vm.sh) · [doc](docs/create-disk-snapshot-and-overwrite-disk-on-vm.md) · [usage](docs/create-disk-snapshot-and-overwrite-disk-on-vm.sh.usage)

Create an LVM-thin snapshot using a destination backing disk number, exact slot, first-free bus, or an LV path that must have exactly one active QEMU reference; replace/archive an occupied target or create into an empty slot, with optional `delete`, VM-state handling, and `boot` promotion. `pause` replacement of an unsafe SCSI topology is refused before mutation.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/create-disk-snapshot-and-overwrite-disk-on-vm.sh" -O "create-disk-snapshot-and-overwrite-disk-on-vm.sh" && chmod +x "create-disk-snapshot-and-overwrite-disk-on-vm.sh"
```

```sh
./create-disk-snapshot-and-overwrite-disk-on-vm.sh 123 scsi0 456 virtio restart boot dryrun
```

#### [`copy-disk-between-vms.sh`](copy-disk-between-vms.sh) · [doc](docs/copy-disk-between-vms.md) · [usage](docs/copy-disk-between-vms.sh.usage)

Copy one QEMU VM disk to another VM as an independent verified volume.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/copy-disk-between-vms.sh" -O "copy-disk-between-vms.sh" && chmod +x "copy-disk-between-vms.sh"
```

```sh
./copy-disk-between-vms.sh 123 scsi0 456 fastvg dryrun
```

#### [`snapshot-disk-between-vms.sh`](snapshot-disk-between-vms.sh) · [doc](docs/snapshot-disk-between-vms.md) · [usage](docs/snapshot-disk-between-vms.sh.usage)

Create an LVM-thin snapshot of one VM disk and attach that linked snapshot to another VM.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/snapshot-disk-between-vms.sh" -O "snapshot-disk-between-vms.sh" && chmod +x "snapshot-disk-between-vms.sh"
```

```sh
./snapshot-disk-between-vms.sh 123 scsi0 456 dryrun
```

#### [`clone-single-vm-disk.sh`](clone-single-vm-disk.sh) · [doc](docs/clone-single-vm-disk.md) · [usage](docs/clone-single-vm-disk.sh.usage)

Clone one disk of a QEMU VM and attach the independent copy back to that VM.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/clone-single-vm-disk.sh" -O "clone-single-vm-disk.sh" && chmod +x "clone-single-vm-disk.sh"
```

```sh
./clone-single-vm-disk.sh 123 scsi0 fastvg dryrun
```

### Disk configuration surgery

#### [`change-disk-bus.sh`](change-disk-bus.sh) · [doc](docs/change-disk-bus.md) · [usage](docs/change-disk-bus.sh.usage)

Move a stopped QEMU VM disk configuration from one bus/slot to another without moving its backing volume, defaulting an omitted destination to the first free SCSI slot and preserving destination-compatible options; incompatible `iothread` is removed with a warning for SATA/IDE.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/change-disk-bus.sh" -O "change-disk-bus.sh" && chmod +x "change-disk-bus.sh"
```

```sh
./change-disk-bus.sh 123 scsi1 sata0 dryrun
```

#### [`swap-vm-disks.sh`](swap-vm-disks.sh) · [doc](docs/swap-vm-disks.md) · [usage](docs/swap-vm-disks.sh.usage)

On a stopped QEMU VM, swap the complete configuration values of two existing disk slots after backing up the VM configuration.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/swap-vm-disks.sh" -O "swap-vm-disks.sh" && chmod +x "swap-vm-disks.sh"
```

```sh
./swap-vm-disks.sh 123 scsi0 scsi1 dryrun
```

#### [`set-vm-boot-disk.sh`](set-vm-boot-disk.sh) · [doc](docs/set-vm-boot-disk.md) · [usage](docs/set-vm-boot-disk.sh.usage)

Put a selected VM disk slot first in the QEMU boot order.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/set-vm-boot-disk.sh" -O "set-vm-boot-disk.sh" && chmod +x "set-vm-boot-disk.sh"
```

```sh
./set-vm-boot-disk.sh 123 scsi0 dryrun
```

#### [`replace-vm-disk.sh`](replace-vm-disk.sh) · [doc](docs/replace-vm-disk.md) · [usage](docs/replace-vm-disk.sh.usage)

On a stopped QEMU VM, replace a disk slot with an existing unshared LVM volume while retaining the slot's compatible disk options and preserving the displaced disk as `unusedN`.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/replace-vm-disk.sh" -O "replace-vm-disk.sh" && chmod +x "replace-vm-disk.sh"
```

```sh
./replace-vm-disk.sh 123 scsi0 /dev/pve/vm-123-disk-9 dryrun
```

#### [`renumber-vm-disks.sh`](renumber-vm-disks.sh) · [doc](docs/renumber-vm-disks.md) · [usage](docs/renumber-vm-disks.sh.usage)

On a stopped, snapshot-free QEMU VM, renumber configured managed LVs into contiguous sequences per prefix + embedded-VMID namespace, preserving those namespaces, updating the VM configuration, and refusing shared volumes or destination collisions.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/renumber-vm-disks.sh" -O "renumber-vm-disks.sh" && chmod +x "renumber-vm-disks.sh"
```

```sh
./renumber-vm-disks.sh 123 dryrun
```

#### [`fix-vm-volume-names.sh`](fix-vm-volume-names.sh) · [doc](docs/fix-vm-volume-names.md) · [usage](docs/fix-vm-volume-names.sh.usage)

On a stopped QEMU VM, repairs already-managed `vm-*`/`base-*` backing LV names whose embedded VMID does not match the referencing guest, preserving family and the original `disk-N`. Only configured managed-name references are repair candidates; unrelated custom/unmanaged LVs are never scanned or renamed. Shared volumes and exact corrected-name collisions are refused.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/fix-vm-volume-names.sh" -O "fix-vm-volume-names.sh" && chmod +x "fix-vm-volume-names.sh"
```

```sh
./fix-vm-volume-names.sh 123 dryrun
```

### Storage, import and export

#### [`move-disk-to-storage.sh`](move-disk-to-storage.sh) · [doc](docs/move-disk-to-storage.md) · [usage](docs/move-disk-to-storage.sh.usage)

Move one QEMU VM disk to another configured Proxmox storage using `qm move_disk`.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/move-disk-to-storage.sh" -O "move-disk-to-storage.sh" && chmod +x "move-disk-to-storage.sh"
```

```sh
./move-disk-to-storage.sh 123 scsi0 fast-lvm dryrun
```

#### [`bulk-change-vm-storage.sh`](bulk-change-vm-storage.sh) · [doc](docs/bulk-change-vm-storage.md) · [usage](docs/bulk-change-vm-storage.sh.usage)

Move matching VM disks from one Proxmox storage ID to another across multiple VMIDs.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/bulk-change-vm-storage.sh" -O "bulk-change-vm-storage.sh" && chmod +x "bulk-change-vm-storage.sh"
```

```sh
./bulk-change-vm-storage.sh local-lvm fast-lvm 123 124 125 dryrun
```

#### [`change-vm-storage-prefix.sh`](change-vm-storage-prefix.sh) · [doc](docs/change-vm-storage-prefix.md) · [usage](docs/change-vm-storage-prefix.sh.usage)

Rewrite an old Proxmox storage ID to a new storage ID in stopped local QEMU/LXC guest configurations only when both IDs resolve every affected volume to the same underlying path; this is an alias/reference rewrite, not a data migration.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/change-vm-storage-prefix.sh" -O "change-vm-storage-prefix.sh" && chmod +x "change-vm-storage-prefix.sh"
```

```sh
./change-vm-storage-prefix.sh old-lvm new-lvm dryrun
```

#### [`import-disk-and-attach.sh`](import-disk-and-attach.sh) · [doc](docs/import-disk-and-attach.md) · [usage](docs/import-disk-and-attach.sh.usage)

Import a disk image into Proxmox storage and attach it to a stopped QEMU VM at the first free SCSI slot or an explicitly requested empty `scsi0..scsi30` slot.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/import-disk-and-attach.sh" -O "import-disk-and-attach.sh" && chmod +x "import-disk-and-attach.sh"
```

```sh
./import-disk-and-attach.sh ./server.raw 123 local-lvm scsi1 dryrun
```

#### [`export-vm-disk.sh`](export-vm-disk.sh) · [doc](docs/export-vm-disk.md) · [usage](docs/export-vm-disk.sh.usage)

Export a stopped QEMU VM disk to raw or qcow2 with `qemu-img`; when format is omitted, `.qcow2` selects qcow2 and all other output filenames default to raw.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/export-vm-disk.sh" -O "export-vm-disk.sh" && chmod +x "export-vm-disk.sh"
```

```sh
./export-vm-disk.sh 123 scsi0 ./vm-123-scsi0.qcow2 qcow2 dryrun
```

### Networking

#### [`bulk-change-vm-network.sh`](bulk-change-vm-network.sh) · [doc](docs/bulk-change-vm-network.md) · [usage](docs/bulk-change-vm-network.sh.usage)

Apply the same bridge/tag/firewall settings to one NIC slot across multiple local QEMU VMs and LXC containers while preserving other NIC options; an optional model change applies to QEMU only and is ignored for LXC.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/bulk-change-vm-network.sh" -O "bulk-change-vm-network.sh" && chmod +x "bulk-change-vm-network.sh"
```

```sh
./bulk-change-vm-network.sh net0 vmbr1 --tag 20 --firewall 1 123 124 125 dryrun
```

### v3.6 QoL, workflow and archive helpers

#### [`activate-vm-lvs.sh`](activate-vm-lvs.sh) · [doc](docs/activate-vm-lvs.md) · [usage](docs/activate-vm-lvs.sh.usage)

Activates distinct LVM volumes referenced by one guest using lvchange -ay -K so activation-skip template/base LVs can be exposed. Storage aliases are deduplicated by LV UUID. Already-active LVs are unchanged, and a partial multi-LV activation is rolled back on failure. No guest config is modified.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/activate-vm-lvs.sh" -O "activate-vm-lvs.sh" && chmod +x "activate-vm-lvs.sh"
```

#### [`add-vm-disk-reference-only.sh`](add-vm-disk-reference-only.sh) · [doc](docs/add-vm-disk-reference-only.md) · [usage](docs/add-vm-disk-reference-only.sh.usage)

Adds exactly one QEMU config reference directly after validating the backing volume. It never allocates, copies or frees storage. VM must be stopped and snapshot-free. Existing physical-LV references, including storage aliases, are refused unless --allow-shared is explicit.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/add-vm-disk-reference-only.sh" -O "add-vm-disk-reference-only.sh" && chmod +x "add-vm-disk-reference-only.sh"
```

#### [`audit-vm-boot-config.sh`](audit-vm-boot-config.sh) · [doc](docs/audit-vm-boot-config.md) · [usage](docs/audit-vm-boot-config.sh.usage)

Read-only check for stale boot-order entries and obvious OVMF/EFI disk inconsistencies. Exit 4 reports audit findings.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/audit-vm-boot-config.sh" -O "audit-vm-boot-config.sh" && chmod +x "audit-vm-boot-config.sh"
```

#### [`clone-vm-storage-only.sh`](clone-vm-storage-only.sh) · [doc](docs/clone-vm-storage-only.md) · [usage](docs/clone-vm-storage-only.sh.usage)

Copies every active source disk into an existing destination QEMU VM while preserving source device slots and disk options. The destination must be stopped and snapshot-free; the source must be stopped unless `--hot` is explicitly accepted. Each source is converted to an invocation-owned temporary raw staging image before `qm importdisk`, because Proxmox rejects an LVM block device as an import-file argument. Imported guest-visible bytes are verified against the immutable staging image before attachment. Inactive source LVs are restored immediately after staging, temporary data is removed on all exit paths, and abnormal exits restore the destination config and remove only imported storage whose recorded physical identity is still proven unreferenced.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/clone-vm-storage-only.sh" -O "clone-vm-storage-only.sh" && chmod +x "clone-vm-storage-only.sh"
```

#### [`compare-vm-disks.sh`](compare-vm-disks.sh) · [doc](docs/compare-vm-disks.md) · [usage](docs/compare-vm-disks.sh.usage)

Compares size and the SHA-256 of the first 4 MiB. --full additionally runs a complete byte-for-byte cmp. In normal mode an inactive LVM source may be temporarily activated with -K and is restored on every exit path; dry-run/ preflight never activates an LV and refuses when content cannot be read. Exit 4 means the compared disks differ.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/compare-vm-disks.sh" -O "compare-vm-disks.sh" && chmod +x "compare-vm-disks.sh"
```

#### [`convert-lv-to-thin.sh`](convert-lv-to-thin.sh) · [doc](docs/convert-lv-to-thin.md) · [usage](docs/convert-lv-to-thin.sh.usage)

Creates a new independent thin LV, copies all source bytes using sparse writes only because the destination is thin, and verifies with cmp. Source is never deleted or converted in place.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/convert-lv-to-thin.sh" -O "convert-lv-to-thin.sh" && chmod +x "convert-lv-to-thin.sh"
```

#### [`convert-thin-to-regular-lv.sh`](convert-thin-to-regular-lv.sh) · [doc](docs/convert-thin-to-regular-lv.md) · [usage](docs/convert-thin-to-regular-lv.sh.usage)

Creates and byte-verifies an independent regular LV. The dd path never uses sparse writes, so untouched regular-LV extents are never assumed to read zero. Source is never deleted or converted in place.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/convert-thin-to-regular-lv.sh" -O "convert-thin-to-regular-lv.sh" && chmod +x "convert-thin-to-regular-lv.sh"
```

#### [`copy-vm-disk-options.sh`](copy-vm-disk-options.sh) · [doc](docs/copy-vm-disk-options.md) · [usage](docs/copy-vm-disk-options.sh.usage)

Copies cache/discard/iothread/ssd/backup/replicate/read-only policy options while preserving the destination backing volume, size and unrelated options. Incompatible `iothread` is dropped for IDE/SATA destinations. The destination VM must be stopped. Post-update verification requires the exact same backing volume and compares option key/value tokens independent of Proxmox's canonical comma-field ordering.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/copy-vm-disk-options.sh" -O "copy-vm-disk-options.sh" && chmod +x "copy-vm-disk-options.sh"
```

#### [`copy-vm-disk-to-regular-lv.sh`](copy-vm-disk-to-regular-lv.sh) · [doc](docs/copy-vm-disk-to-regular-lv.md) · [usage](docs/copy-vm-disk-to-regular-lv.sh.usage)

Creates an independent regular-LV copy of a VM disk and verifies every byte. Regular destinations never use sparse dd writes. No VM configuration changes. The source VM must be stopped unless --allow-running explicitly accepts an inconsistent live-copy risk.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/copy-vm-disk-to-regular-lv.sh" -O "copy-vm-disk-to-regular-lv.sh" && chmod +x "copy-vm-disk-to-regular-lv.sh"
```

#### [`copy-vm-disk-to-thin-lv.sh`](copy-vm-disk-to-thin-lv.sh) · [doc](docs/copy-vm-disk-to-thin-lv.md) · [usage](docs/copy-vm-disk-to-thin-lv.sh.usage)

Creates an independent thin-LV copy of a VM disk and byte-verifies it. Sparse writes are used only because the destination is explicitly thin. The source VM must be stopped unless --allow-running explicitly accepts an inconsistent live-copy risk.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/copy-vm-disk-to-thin-lv.sh" -O "copy-vm-disk-to-thin-lv.sh" && chmod +x "copy-vm-disk-to-thin-lv.sh"
```

#### [`deactivate-vm-lvs.sh`](deactivate-vm-lvs.sh) · [doc](docs/deactivate-vm-lvs.md) · [usage](docs/deactivate-vm-lvs.sh.usage)

Deactivates referenced LVs only when the guest is stopped and each LV is unmounted with zero device-mapper open count. Safety refusal is exit 3.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/deactivate-vm-lvs.sh" -O "deactivate-vm-lvs.sh" && chmod +x "deactivate-vm-lvs.sh"
```

#### [`export-vm-filesystem.sh`](export-vm-filesystem.sh) · [doc](docs/export-vm-filesystem.md) · [usage](docs/export-vm-filesystem.sh.usage)

Exports one filesystem from a stopped QEMU VM through a private host mount. Partitioned disks require an explicit partition number. ext3/4 use noload and XFS uses norecovery so the read-only mount cannot replay guest recovery data. Mapper ownership and exact mount source are verified; output is staged and atomically committed only after a complete archive is created; without --force an output path that appears concurrently is never overwritten. An inactive LVM disk may be temporarily activated in normal mode and is restored on every exit path; dry-run/preflight never activates it. Temporary mounts/mappings are removed on every exit path.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/export-vm-filesystem.sh" -O "export-vm-filesystem.sh" && chmod +x "export-vm-filesystem.sh"
```

#### [`export-vm.sh`](export-vm.sh) · [doc](docs/export-vm.md) · [usage](docs/export-vm.sh.usage)

Creates one self-contained LongTail VM archive containing a native compressed Proxmox backup payload, the guest configuration and firewall, storage topology, optional full guest-visible content hashes, checksums, audit-only external metadata and an embedded standalone restore program. Exact restore compares persistent guest configuration but intentionally permits Proxmox to regenerate QEMU `vmgenid`.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/export-vm.sh" -O "export-vm.sh" && chmod +x "export-vm.sh"
```

#### [`extend-lvm.sh`](extend-lvm.sh) · [doc](docs/extend-lvm.md) · [usage](docs/extend-lvm.sh.usage)

Grow-only raw LVM primitive. It runs lvextend --test before mutation and refuses an LV whose UUID is referenced by any guest storage entry (including storage aliases) unless --allow-referenced is given. Shrinking is never attempted.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/extend-lvm.sh" -O "extend-lvm.sh" && chmod +x "extend-lvm.sh"
```

#### [`find-shared-vm-volumes.sh`](find-shared-vm-volumes.sh) · [doc](docs/find-shared-vm-volumes.md) · [usage](docs/find-shared-vm-volumes.sh.usage)

Read-only inventory of storage physically referenced by more than one local QEMU/LXC guest config. LVM references are grouped by LV UUID, so different Proxmox storage aliases to the same LV are detected as shared. Non-LVM references are grouped by canonical backing path when resolvable. Output includes the physical identity, all observed Proxmox volume IDs, and every guest/slot reference.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/find-shared-vm-volumes.sh" -O "find-shared-vm-volumes.sh" && chmod +x "find-shared-vm-volumes.sh"
```

#### [`find-unreferenced-managed-volumes.sh`](find-unreferenced-managed-volumes.sh) · [doc](docs/find-unreferenced-managed-volumes.md) · [usage](docs/find-unreferenced-managed-volumes.sh.usage)

Lists exactly named vm-VMID-disk-N and base-VMID-disk-N LVs whose physical LV UUID is not referenced by any local QEMU or LXC storage entry. Reference checks therefore include different Proxmox storage aliases to the same LV. Read-only; no volume is deleted.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/find-unreferenced-managed-volumes.sh" -O "find-unreferenced-managed-volumes.sh" && chmod +x "find-unreferenced-managed-volumes.sh"
```

#### [`find-vm-root-filesystem.sh`](find-vm-root-filesystem.sh) · [doc](docs/find-vm-root-filesystem.md) · [usage](docs/find-vm-root-filesystem.sh.usage)

Finds Linux-filesystem signature candidates across a VM's disks without mounting them. It reports slot/partition/offset/size but does not claim which candidate actually contains /. Normal mode may temporarily activate inactive LVM disks with -K and restores them; dry-run/preflight never activates them.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/find-vm-root-filesystem.sh" -O "find-vm-root-filesystem.sh" && chmod +x "find-vm-root-filesystem.sh"
```

#### [`flatten-vm-disk.sh`](flatten-vm-disk.sh) · [doc](docs/flatten-vm-disk.md) · [usage](docs/flatten-vm-disk.sh.usage)

Replaces an LVM-thin snapshot/clone disk with an independent thin copy in the same pool. The VM must be stopped and its config must not contain snapshots. The original linked volume is preserved as an unusedN entry. New content and the new LV identity are verified before the slot is changed. If a later step fails, the original slot is restored and only the UUID-proven incomplete LV created by this invocation is eligible for cleanup.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/flatten-vm-disk.sh" -O "flatten-vm-disk.sh" && chmod +x "flatten-vm-disk.sh"
```

#### [`for-each-vm.sh`](for-each-vm.sh) · [doc](docs/for-each-vm.md) · [usage](docs/for-each-vm.sh.usage)

Safely dispatches a command to selected guests without eval. An argument that is exactly {} is replaced by the VMID; if no {} is present the command is run exactly as supplied. The argv template is stored one argument per line, so command arguments containing newlines are refused. Range/tag filters are fully validated before the first dispatch. dryrun/--plan prints argv and executes nothing.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/for-each-vm.sh" -O "for-each-vm.sh" && chmod +x "for-each-vm.sh"
```

#### [`grow-vm-filesystem.sh`](grow-vm-filesystem.sh) · [doc](docs/grow-vm-filesystem.md) · [usage](docs/grow-vm-filesystem.sh.usage)

Grows a filesystem only after the block device has already been enlarged. VMID:SLOT requires a stopped QEMU VM. A direct LVM selector is refused when its physical LV UUID is guest-referenced, because guest runtime state cannot otherwise be proven. The device must already be active. This version handles whole-device ext2/3/4 while unmounted and mounted XFS at an exact source- verified --mountpoint. Partition-table growth is deliberately refused.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/grow-vm-filesystem.sh" -O "grow-vm-filesystem.sh" && chmod +x "grow-vm-filesystem.sh"
```

#### [`import-vm.sh`](import-vm.sh) · [doc](docs/import-vm.md) · [usage](docs/import-vm.sh.usage)

Restores a LongTail single-file VM archive using the restore program carried inside that archive after validating archive membership and checksums. Exact same-identity restore verifies persistent configuration and guest-visible content while intentionally allowing Proxmox to regenerate QEMU `vmgenid`; restored guests remain stopped unless `--start` is explicitly requested.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/import-vm.sh" -O "import-vm.sh" && chmod +x "import-vm.sh"
```

#### [`migrate-vm-storage-layout.sh`](migrate-vm-storage-layout.sh) · [doc](docs/migrate-vm-storage-layout.md) · [usage](docs/migrate-vm-storage-layout.sh.usage)

Migrates one or all active disks of a stopped, snapshot-free QEMU VM using qm move_disk. SLOT, when supplied, must be an exact QEMU disk slot. Each successful move is verified to use the destination storage. If execution is interrupted or a later move/verification fails, selected disks that reached the destination are best-effort moved back in reverse order to their recorded recorded original storages. A rollback can create a different physical LV identity even though Proxmox copies the disk content back, so any rollback warning requires operator inspection before retrying.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/migrate-vm-storage-layout.sh" -O "migrate-vm-storage-layout.sh" && chmod +x "migrate-vm-storage-layout.sh"
```

#### [`normalize-vm-disk-options.sh`](normalize-vm-disk-options.sh) · [doc](docs/normalize-vm-disk-options.md) · [usage](docs/normalize-vm-disk-options.sh.usage)

Conservative option cleanup. Currently removes iothread from IDE/SATA slots, where it is not compatible, and otherwise leaves disk options untouched. VM must be stopped.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/normalize-vm-disk-options.sh" -O "normalize-vm-disk-options.sh" && chmod +x "normalize-vm-disk-options.sh"
```

#### [`plan-vm-storage-move.sh`](plan-vm-storage-move.sh) · [doc](docs/plan-vm-storage-move.md) · [usage](docs/plan-vm-storage-move.sh.usage)

Read-only migration planner. Shows every selected disk, virtual byte count, thin-pool/origin lineage and destination storage status before any move. LVM sizes come from metadata, so inactive activation-skip/template LVs can be planned without being activated. --slot requires an exact QEMU disk slot.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/plan-vm-storage-move.sh" -O "plan-vm-storage-move.sh" && chmod +x "plan-vm-storage-move.sh"
```

#### [`rebuild-vm-from-existing-disks.sh`](rebuild-vm-from-existing-disks.sh) · [doc](docs/rebuild-vm-from-existing-disks.md) · [usage](docs/rebuild-vm-from-existing-disks.sh.usage)

Discovers exactly named, unreferenced vm-VMID-disk-N/base-VMID-disk-N LVs, proves a unique Proxmox storage mapping by LV UUID, rejects duplicate disk-N candidates, and proposes a minimal recovery VM ordered by backing disk number. It is plan-only unless --apply is used. Hardware that cannot be inferred safely (NICs, exact machine/CPU/firmware) is not guessed beyond the explicit defaults/options. If apply fails after the new VM config is created, only that new config is eligible for cleanup and no recovered storage volume is freed.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/rebuild-vm-from-existing-disks.sh" -O "rebuild-vm-from-existing-disks.sh" && chmod +x "rebuild-vm-from-existing-disks.sh"
```

#### [`remove-vm-disk-reference-only.sh`](remove-vm-disk-reference-only.sh) · [doc](docs/remove-vm-disk-reference-only.md) · [usage](docs/remove-vm-disk-reference-only.sh.usage)

Removes exactly one QEMU config line without calling qm --delete or pvesm free, so the backing volume cannot be freed as a side effect. VM must be stopped and snapshot-free. Active-slot removal requires explicit --active.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/remove-vm-disk-reference-only.sh" -O "remove-vm-disk-reference-only.sh" && chmod +x "remove-vm-disk-reference-only.sh"
```

#### [`rename-unused-disk-reference.sh`](rename-unused-disk-reference.sh) · [doc](docs/rename-unused-disk-reference.md) · [usage](docs/rename-unused-disk-reference.sh.usage)

Rewrites only an unusedN config reference after proving old and new volume IDs resolve to the same LV UUID/backing device. VM must be stopped and snapshot-free. It never invokes qm --delete or a storage free operation.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/rename-unused-disk-reference.sh" -O "rename-unused-disk-reference.sh" && chmod +x "rename-unused-disk-reference.sh"
```

#### [`renumber-vm-device-slots.sh`](renumber-vm-device-slots.sh) · [doc](docs/renumber-vm-device-slots.md) · [usage](docs/renumber-vm-device-slots.sh.usage)

Compacts QEMU device positions independently from backing LV disk numbers. VM must be stopped and snapshot-free. Boot-order slot names are remapped in the same one-pass config transaction. Backing volume names never change.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/renumber-vm-device-slots.sh" -O "renumber-vm-device-slots.sh" && chmod +x "renumber-vm-device-slots.sh"
```

#### [`repair-vm-storage-consistency.sh`](repair-vm-storage-consistency.sh) · [doc](docs/repair-vm-storage-consistency.md) · [usage](docs/repair-vm-storage-consistency.sh.usage)

Conservative repair companion. It currently repairs only one class that can be proven unambiguous: a referenced vm-/base- managed LV whose embedded VMID differs from the referencing stopped, snapshot-free VM, while the exact corrected LV name is unused and the physical LV has exactly one guest-storage reference (storage aliases count as the same LV). Without --apply the command is plan-only. Ambiguous findings are never guessed or automatically repaired.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/repair-vm-storage-consistency.sh" -O "repair-vm-storage-consistency.sh" && chmod +x "repair-vm-storage-consistency.sh"
```

#### [`resize-vm-disk.sh`](resize-vm-disk.sh) · [doc](docs/resize-vm-disk.md) · [usage](docs/resize-vm-disk.sh.usage)

Grow-only Proxmox disk resize for an LVM-backed QEMU disk. Absolute and relative IEC sizes are validated before qm resize. The exact backing LV UUID must survive and its resulting byte size must meet the requested target. Partitions/filesystems are not changed; grow them separately when appropriate.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/resize-vm-disk.sh" -O "resize-vm-disk.sh" && chmod +x "resize-vm-disk.sh"
```

#### [`send-vm-export-and-restore.sh`](send-vm-export-and-restore.sh) · [doc](docs/send-vm-export-and-restore.md) · [usage](docs/send-vm-export-and-restore.sh.usage)

Transfers a trusted `.ltvm` archive with `scp`, verifies the complete archive SHA-256 on the destination, then streams and executes the archive's embedded restore program over SSH. Dry-run validates the local archive and prints every remote action without opening SSH. `--preflight` performs read-only remote checks and requires the destination host key to already be trusted.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/send-vm-export-and-restore.sh" -O "send-vm-export-and-restore.sh" && chmod +x "send-vm-export-and-restore.sh"
```

#### [`show-last-operation.sh`](show-last-operation.sh) · [doc](docs/show-last-operation.md) · [usage](docs/show-last-operation.sh.usage)

Displays the most recent LongTail transaction journal, or a specific journal by operation ID. The journal root and selected file must be root-owned and non-symlink regular storage. Set LONGTAILTOIL_JOURNAL_DIR to inspect a non-default root.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/show-last-operation.sh" -O "show-last-operation.sh" && chmod +x "show-last-operation.sh"
```

#### [`show-thin-snapshot-tree.sh`](show-thin-snapshot-tree.sh) · [doc](docs/show-thin-snapshot-tree.md) · [usage](docs/show-thin-snapshot-tree.sh.usage)

Read-only inventory of thin snapshot ancestry. Each LV is shown with its pool and direct origin so base/template lineage remains visible.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/show-thin-snapshot-tree.sh" -O "show-thin-snapshot-tree.sh" && chmod +x "show-thin-snapshot-tree.sh"
```

#### [`show-vm-filesystem-layout.sh`](show-vm-filesystem-layout.sh) · [doc](docs/show-vm-filesystem-layout.md) · [usage](docs/show-vm-filesystem-layout.sh.usage)

Read-only filesystem/partition map across all active disk slots on one QEMU VM, or one exact slot. It never mounts or creates partition mapper devices. Normal mode may temporarily activate an inactive LVM disk with -K and restores it; dry-run/preflight refuses rather than changing activation state.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/show-vm-filesystem-layout.sh" -O "show-vm-filesystem-layout.sh" && chmod +x "show-vm-filesystem-layout.sh"
```

#### [`show-vm-storage-map.sh`](show-vm-storage-map.sh) · [doc](docs/show-vm-storage-map.md) · [usage](docs/show-vm-storage-map.sh.usage)

Shows slot -> Proxmox volume -> resolved path -> LVM UUID/size/pool/origin for one QEMU VM or LXC container. The command is read-only.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/show-vm-storage-map.sh" -O "show-vm-storage-map.sh" && chmod +x "show-vm-storage-map.sh"
```

#### [`sort-vm-disk-slots.sh`](sort-vm-disk-slots.sh) · [doc](docs/sort-vm-disk-slots.md) · [usage](docs/sort-vm-disk-slots.sh.usage)

Reassigns one bus's device positions in ascending managed disk-N order. Unmanaged volumes sort after managed volumes in their original order. Backing LVs are not renamed; boot-order device names are remapped.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/sort-vm-disk-slots.sh" -O "sort-vm-disk-slots.sh" && chmod +x "sort-vm-disk-slots.sh"
```

#### [`verify-vm-disk-content.sh`](verify-vm-disk-content.sh) · [doc](docs/verify-vm-disk-content.md) · [usage](docs/verify-vm-disk-content.sh.usage)

Read-only partition/content sanity check using partx and offset-aware blkid. It never mounts, fscks, creates partition mappers, or writes disk content. Normal mode may temporarily activate an inactive LVM LV with -K and restores its original state; dry-run/preflight refuses rather than changing activation.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/verify-vm-disk-content.sh" -O "verify-vm-disk-content.sh" && chmod +x "verify-vm-disk-content.sh"
```

#### [`verify-vm-storage-consistency.sh`](verify-vm-storage-consistency.sh) · [doc](docs/verify-vm-storage-consistency.md) · [usage](docs/verify-vm-storage-consistency.sh.usage)

Performs a read-only consistency audit of QEMU and LXC storage references. Checks pvesm resolution, backing-path existence, managed LV VMID identity, and configured multi-guest references. unusedN references are inspected but are not treated as writable shared-disk conflicts.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/verify-vm-storage-consistency.sh" -O "verify-vm-storage-consistency.sh" && chmod +x "verify-vm-storage-consistency.sh"
```

## Standalone by design

The `lib/` directory in the repository is the canonical maintenance source for shared helper code, but the published top-level commands do **not** source it at runtime. The shared runtime is embedded into every helper, and wrapper commands also bundle the companion implementation they need.

That means this is valid:

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/change-vmid-of-vm.sh" -O change-vmid-of-vm.sh
chmod +x change-vmid-of-vm.sh
./change-vmid-of-vm.sh --help
```

You can move that file to `/root`, `/usr/local/sbin`, a rescue directory, or another host without copying anything else from this repository.

## Install the whole repository

If you expect to use more than one helper, cloning the repository is simpler than downloading commands individually:

```sh
git clone https://github.com/proxmoxhelpers/LongTailToilForProxmox.git && cd LongTailToilForProxmox
```

Every command supports:

```sh
./some-command.sh --help
```

and:

```sh
./some-command.sh --version
```

Every mutating public command accepts the project dry-run form documented by its own live help (`dryrun` / `--dryrun`, with `--plan` and/or `--preflight` where that helper exposes those aliases). Use each helper's `--help` as the authoritative CLI contract.

## Proxmox managed LVM names

Where a helper interprets Proxmox-managed LVM volume names, both standard families are supported:

```text
vm-VMID-disk-N
base-VMID-disk-N
```

`base-` is used by Proxmox templates/base images. Operations that rename an existing managed volume preserve its family; operations that create a destination disk use `base-` when the destination QEMU guest is a template and `vm-` otherwise. Numeric `disk-N` selectors consider both current and stale configured `vm-`/`base-` names and refuse the operation if more than one configured disk matches that number.

## Safety model

These scripts are deliberately more cautious than the one-liners they replace. Depending on the operation they perform preflight discovery, refuse ambiguous storage mappings and shared references, check name/slot collisions, preserve or explicitly control guest state, create backups before direct `/etc/pve` edits, verify postconditions, and use rollback or conservative preservation when a multi-step transaction fails.

The copy paths distinguish thin and regular LVs: sparse copying is used only for newly allocated thin destinations, while regular LVs receive full writes so skipped zero blocks cannot expose stale underlying data. LVM stderr is not globally hidden; only the three known repetitive thin-pool advisories are filtered, while unrelated warnings and errors remain visible.

Every mutating helper supports project dry-run semantics, and the integration suite enforces at least one exact-state dry-run case for every mutating public command. Refusal paths are tested the same way: the command must fail while the complete disposable state remains unchanged.

The integration harness is intentionally fail-closed. It creates uniquely named loopback-backed test VGs/storage and dynamically allocated disposable QEMU/LXC guests, records ownership before mutation, and refuses cleanup if a guest identity/storage mapping no longer matches that ownership. Remaining mounts block guest/storage cleanup; remaining guests block storage/VG cleanup; remaining storage definitions block VG/loop cleanup. Pre-existing project backup paths are recorded before each run and are never removed as test artifacts.

Protected-host comparisons include pre-existing VG/PV/LV metadata, canonical storage semantics, guest configuration checksums, local QEMU/LXC runtime state and firewall-file checksums. Dry-run/refusal snapshots additionally include disposable LV metadata and sampled content hashes, guest configs/status, test storage definitions, test files and mounts. Data-sensitive copy/move/import/export tests independently verify bytes with `cmp` or hashes.

## Tested on real Proxmox fixtures

Project **v3.5.1** was the earlier clean real-Proxmox integration baseline. Its supplied 2026-08-17 run completed all ten groups with **50/50 static cases and 88/88 real integration cases passing, zero skips, zero failures and zero anomalies**. See [`docs/V3.5.1-REAL-INTEGRATION-RESULTS.md`](docs/V3.5.1-REAL-INTEGRATION-RESULTS.md).

The exact **v3.7.0 / suite v3.1.0** tree was then run in full on 2026-08-20. It passed **74/74 static cases and 130/137 real integration cases** with zero protected-state anomalies. All 98 protected baseline/after pairs and all 130 captured before/after mutation-safety pairs in the supplied evidence archive were byte-identical. The seven failed cases reduced to the six root causes corrected in v3.7.1; see [`docs/V3.7.0-REAL-INTEGRATION-RESULTS.md`](docs/V3.7.0-REAL-INTEGRATION-RESULTS.md).

The current **v3.7.1 / suite v3.1.1** tree contains **81 standalone helpers**. Its fresh 2026-08-22 all-groups run passes **78/78 static/CLI cases and 137/137 real integration cases across all 14 operational groups**, with zero failures, skips or anomalies. v3.7.1 is therefore the current **real-host integration-validated** baseline for the covered matrix; see [`docs/V3.7.1-REAL-INTEGRATION-RESULTS.md`](docs/V3.7.1-REAL-INTEGRATION-RESULTS.md).

Run the full current suite on a disposable or non-production Proxmox node:

```sh
./tests/run-all-tests.sh --run --verbose
```

The command-by-command behavior map is in [`tests/TEST-MATRIX.md`](tests/TEST-MATRIX.md). The 2026-08-22 acceptance result is recorded in [`docs/V3.7.1-REAL-INTEGRATION-RESULTS.md`](docs/V3.7.1-REAL-INTEGRATION-RESULTS.md).

## Why this exists

This project was originally inspired by the long-running Proxmox forum thread **“Changing VMID of a VM”**, started in January 2020.

That discussion is a good example of long-tail toil: the underlying operation can look deceptively simple—rename an LV, edit a config, rename a file—but over the years the thread accumulated edge cases around LVM/LVM-thin, ZFS, templates, snapshots, backing-volume naming, collisions, shared references, PBS workflows and cluster configuration. The official safe answer is often backup/restore or clone/delete, while operators sometimes need a faster in-place maintenance operation and end up reconstructing the same shell procedure from memory.

`change-vmid-of-vm.sh` grew from that idea, and the repository expanded into the other infrequent Proxmox tasks with the same philosophy: **preflight first, show a dry run, mutate only the intended disposable/selected objects, then verify what actually happened.**

For VMID changes specifically, remember that changing a VMID is not an ordinary rename supported by Proxmox. The helper intentionally supports only the storage/configuration cases it knows how to validate and tells you to review external references such as backup jobs, ACLs, HA, replication, pools, hooks and other automation afterward.

## Requirements

- Proxmox VE
- POSIX `/bin/sh`
- root privileges or `sudo` for normal helper execution; `--help` and `--version` return before elevation
- LVM/LVM-thin for the LVM-specific helpers
- standard Proxmox/Linux tools used by the selected command (`qm`, `pct`, `pvesm`, LVM, `kpartx`, `partx`, `sfdisk`, `blkid`, `findmnt`, `qemu-img`, etc.)

`--help` and `--version` return before the operation/elevation boundary. Normal helper execution uses the common root/elevation gate consistently, including read-only inspection helpers, so privileged Proxmox/LVM metadata access behaves the same whether a command is launched as root or through `sudo`.

## Documentation

- [POSIX shell style guide](docs/POSIX-SHELL-STYLE-GUIDE-v3.md)
- [Proxmox and shell scripting lessons learned](docs/PROXMOX-SHELL-SCRIPTING-LESSONS-LEARNED.md)
- [Helper documentation / usage index](docs/HELPERS.md)
- [Style profiles and exceptions](docs/STYLE-PROFILES-AND-EXCEPTIONS.md)
- [v3 migration notes](docs/V3-MIGRATION-NOTES.md)
- [Testing documentation](docs/testing/README.md)
- [Proxmox test harness best practices](docs/testing/PROXMOX-TEST-HARNESS-BEST-PRACTICES.md)
- [POSIX shell test harness best practices](docs/testing/POSIX-SHELL-TEST-HARNESS-BEST-PRACTICES.md)
- [Destructive system-test safety checklist](docs/testing/DESTRUCTIVE-SYSTEM-TEST-SAFETY-CHECKLIST.md)
- [Disposable Proxmox integration lab guide](docs/testing/PROXMOX-DISPOSABLE-INTEGRATION-LAB-GUIDE.md)
- [Test-system design guide](docs/testing/TEST-SYSTEM-DESIGN-GUIDE.md)
- [Shell test-harness implementation guide](docs/testing/SHELL-TEST-HARNESS-IMPLEMENTATION-GUIDE.md)
- [Test evidence, triage and regression guide](docs/testing/TEST-EVIDENCE-TRIAGE-AND-REGRESSION-GUIDE.md)
- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)
- [Changelog](CHANGELOG.md)
- [v3.2.2 overwrite rollback/identity fix](docs/V3.2.2-OVERWRITE-ROLLBACK-FIX.md)
- [v3.2.2 static validation](docs/V3.2.2-STATIC-VALIDATION.md)
- [v3.3.0 create-device selectors and boot](docs/V3.3.0-CREATE-DEVICE-SELECTORS-AND-BOOT.md)
- [v3.3.0 static validation](docs/V3.3.0-STATIC-VALIDATION.md)
- [v3.3.1 vm/base managed-volume support](docs/V3.3.1-VM-BASE-MANAGED-VOLUMES.md)
- [v3.3.1 static validation](docs/V3.3.1-STATIC-VALIDATION.md)
- [v3.4.0 numbering/filesystem inspection](docs/V3.4.0-INSPECTION-HELPERS.md)
- [v3.4.0 static validation](docs/V3.4.0-STATIC-VALIDATION.md)
- [v3.4.1 alternate-branch merge review](docs/V3.4.1-ALTERNATE-BRANCH-MERGE-REVIEW.md)
- [v3.4.1 static validation](docs/V3.4.1-STATIC-VALIDATION.md)
- [v3.4.2 full test/safety audit](docs/V3.4.2-TEST-AUDIT.md)
- [v3.4.2 static validation](docs/V3.4.2-STATIC-VALIDATION.md)
- [v3.4.3 real-integration triage and fixes](docs/V3.4.3-REAL-INTEGRATION-TRIAGE.md)
- [v3.4.3 static validation](docs/V3.4.3-STATIC-VALIDATION.md)
- [v3.4.4 second real-run triage and fixes](docs/V3.4.4-SECOND-REAL-RUN-TRIAGE.md)
- [v3.4.4 static validation](docs/V3.4.4-STATIC-VALIDATION.md)
- [v3.4.5 help/documentation audit](docs/V3.4.5-HELP-DOCUMENTATION-AUDIT.md)
- [v3.4.5 static validation](docs/V3.4.5-STATIC-VALIDATION.md)
- [v3.4.6 lessons/docs/style audit](docs/V3.4.6-LESSONS-DOCS-STYLE-AUDIT.md)
- [v3.4.6 static validation](docs/V3.4.6-STATIC-VALIDATION.md)
- [v3.4.7 third real-run triage and corrections](docs/V3.4.7-THIRD-REAL-RUN-TRIAGE.md)
- [v3.4.7 static validation](docs/V3.4.7-STATIC-VALIDATION.md)
- [v3.4.7 real-Proxmox test results](docs/V3.4.7-REAL-RUN-RESULTS.md)
- [v3.5.0 project-wide shell style refactor](docs/V3.5.0-STYLE-REFACTOR.md)
- [v3.5.0 static validation](docs/V3.5.0-STATIC-VALIDATION.md)
- [v3.5.1 triage of the v3.4.7 real-host run](docs/V3.5.1-REAL-RUN-TRIAGE.md)
- [v3.5.1 static validation](docs/V3.5.1-STATIC-VALIDATION.md)
- [v3.5.1 real-Proxmox integration results](docs/V3.5.1-REAL-INTEGRATION-RESULTS.md)
- [v3.5.2 static validation](docs/V3.5.2-STATIC-VALIDATION.md)
- [v3.6.2 selective port/integration review](docs/V3.6.2-PORT-INTEGRATION-REVIEW.md)
- [v3.7.1 static validation](docs/V3.7.1-STATIC-VALIDATION.md)
- [v3.7.1 documentation/code/usage audit](docs/V3.7.1-DOCUMENTATION-AUDIT.md)
- [v3.7.1 real-Proxmox integration results](docs/V3.7.1-REAL-INTEGRATION-RESULTS.md)
- [v3.7.0 real-Proxmox integration results](docs/V3.7.0-REAL-INTEGRATION-RESULTS.md)
- [v3.7.0 mount/CLI refactor](docs/V3.7.0-MOUNT-CLI-REFACTOR.md)
- [v3.7.0 static validation](docs/V3.7.0-STATIC-VALIDATION.md)
- [v3.6.2 static validation](docs/V3.6.2-STATIC-VALIDATION.md)
- [Current command-by-command test matrix](tests/TEST-MATRIX.md)
- [v3.2.3 empty-target behavior](docs/V3.2.3-EMPTY-TARGET.md)
- [v3.2.3 static validation](docs/V3.2.3-STATIC-VALIDATION.md)
- [v3.2.1 overwrite disk-number fix](docs/V3.2.1-OVERWRITE-DISK-NUMBER-FIX.md)
- [v3.2.1 static validation](docs/V3.2.1-STATIC-VALIDATION.md)
- [v3.2.0 disk create/overwrite helpers](docs/V3.2.0-DISK-CREATE-OVERWRITE.md)
- [v3.2.0 pre-integration validation](docs/V3.2.0-STATIC-VALIDATION.md)
- [v3.1.0 new helpers](docs/V3.1.0-NEW-HELPERS.md)
- [v3.1.0 pre-integration validation](docs/V3.1.0-STATIC-VALIDATION.md)
- [GitHub publishing checklist](docs/GITHUB-PUBLISHING-CHECKLIST.md)
- [MIT License](LICENSE)

## Colour output

Status output is colourized when stdout is a terminal.

Disable colour explicitly with:

```sh
NO_COLOR=1 ./some-command.sh ...
```

## A final note

These helpers automate maintenance operations that can alter VM configuration and storage. `dryrun` is there for a reason: use it, read the plan, keep backups for important guests, and make sure the command's documented storage assumptions match the machine you are operating on.
