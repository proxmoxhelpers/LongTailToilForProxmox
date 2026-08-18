# Proxmox LongTail Toil

**Proxmox LongTail Toil** is a collection of 42 self-contained, safety-focused helpers for the Proxmox jobs that are easy to automate but awkward to remember because they happen infrequently, covering VMIDs, LVM/LVM-thin volumes, disks, mounts, storage, recovery and repetitive VM configuration changes. Each helper is a single portable `.sh` file, and modifying commands support `dryrun` so you can perform real read-only preflight checks and review the planned changes before anything is modified.

## The 42 helpers

### VM identity, recovery and inspection

#### `change-vmid-of-vm.sh`

Change the VMID of a stopped local QEMU VM or LXC container on LVM/LVM-thin, renaming both `vm-OLDID-*` and template `base-OLDID-*` volumes while preserving their family, with preflight checks, backup, verification and rollback.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/change-vmid-of-vm.sh" -O "change-vmid-of-vm.sh" && chmod +x "change-vmid-of-vm.sh"
```

```sh
./change-vmid-of-vm.sh 123 456 dryrun
```

#### `clone-vm-config-only.sh`

Clone a QEMU VM configuration to a new VMID without copying its disks.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/clone-vm-config-only.sh" -O "clone-vm-config-only.sh" && chmod +x "clone-vm-config-only.sh"
```

```sh
./clone-vm-config-only.sh 123 456 web-copy dryrun
```

#### `recover-vm-from-volumes.sh`

Recreate a basic QEMU VM configuration from existing `vm-VMID-disk-N` and/or `base-VMID-disk-N` LVM volumes.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/recover-vm-from-volumes.sh" -O "recover-vm-from-volumes.sh" && chmod +x "recover-vm-from-volumes.sh"
```

```sh
./recover-vm-from-volumes.sh 456 pve dryrun
```

#### `list-vm-disks.sh`

List a QEMU VM's configured disks, resolved storage paths and available LVM metadata.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/list-vm-disks.sh" -O "list-vm-disks.sh" && chmod +x "list-vm-disks.sh"
```

```sh
./list-vm-disks.sh 123
```

#### `list-all-vm-lvm.sh`

List every LVM volume referenced by QEMU/LXC guests grouped under its VMID, then show all remaining LVM volumes.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/list-all-vm-lvm.sh" -O "list-all-vm-lvm.sh" && chmod +x "list-all-vm-lvm.sh"
```

```sh
./list-all-vm-lvm.sh
```

#### `verify-vm-disk-numbering.sh`

Verify all guest LVM disk numbering, highlighting embedded VMID mismatches in red and active numbering that starts above `disk-0`, contains gaps, or contains duplicate `disk-N` values in yellow; `unusedN` archive entries are shown but excluded from sequence checks.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/verify-vm-disk-numbering.sh" -O "verify-vm-disk-numbering.sh" && chmod +x "verify-vm-disk-numbering.sh"
```

```sh
./verify-vm-disk-numbering.sh
```

#### `audit-vm-storage.sh`

Audit a VM's storage references for missing paths, bad mappings and unexpected references.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/audit-vm-storage.sh" -O "audit-vm-storage.sh" && chmod +x "audit-vm-storage.sh"
```

```sh
./audit-vm-storage.sh 123
```

#### `find-volume-owner.sh`

Find which local guest configuration references a specific LVM path or Proxmox volume ID.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/find-volume-owner.sh" -O "find-volume-owner.sh" && chmod +x "find-volume-owner.sh"
```

```sh
./find-volume-owner.sh /dev/pve/vm-123-disk-0
```

#### `find-orphaned-volumes.sh`

Find unreferenced Proxmox-managed `vm-VMID-disk-N` and `base-VMID-disk-N` LVM volumes.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/find-orphaned-volumes.sh" -O "find-orphaned-volumes.sh" && chmod +x "find-orphaned-volumes.sh"
```

```sh
./find-orphaned-volumes.sh pve
```

### Raw LVM operations

#### `copy-lvm.sh`

Create and byte-verify an independent copy of an LVM/LVM-thin logical volume.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/copy-lvm.sh" -O "copy-lvm.sh" && chmod +x "copy-lvm.sh"
```

```sh
./copy-lvm.sh /dev/pve/vm-123-disk-0 /dev/fastvg/vm-123-disk-0-copy dryrun
```

#### `move-lvm.sh`

Rename an LV in place within a VG, or copy-verify-delete it safely when moving across VGs.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/move-lvm.sh" -O "move-lvm.sh" && chmod +x "move-lvm.sh"
```

```sh
./move-lvm.sh /dev/pve/vm-123-disk-0 /dev/fastvg/vm-123-disk-0 dryrun
```

#### `rename-lvm.sh`

Rename an LVM logical volume after validating its source and destination names.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/rename-lvm.sh" -O "rename-lvm.sh" && chmod +x "rename-lvm.sh"
```

```sh
./rename-lvm.sh /dev/pve/vm-123-disk-0 vm-123-disk-0-old dryrun
```

#### `delete-lvm.sh`

Delete an LVM logical volume with explicit confirmation and post-delete verification.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/delete-lvm.sh" -O "delete-lvm.sh" && chmod +x "delete-lvm.sh"
```

```sh
./delete-lvm.sh /dev/pve/vm-123-disk-0-old dryrun
```

### Mounting and filesystem inspection

#### `list-all-vm-lvm-filesystems.sh`

List every guest and remaining LVM disk with read-only `partx` partition metadata beside the filesystem/container signature detected directly from the partition bytes, using format-specific colors, broad compatibility rules, and red notes for definite table/content mismatches.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/list-all-vm-lvm-filesystems.sh" -O "list-all-vm-lvm-filesystems.sh" && chmod +x "list-all-vm-lvm-filesystems.sh"
```

```sh
./list-all-vm-lvm-filesystems.sh
```

#### `mount-vm-drives.sh`

Mount recognizable filesystems from an LVM-backed VM disk, using `kpartx` for partitions and read-only mode by default.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/mount-vm-drives.sh" -O "mount-vm-drives.sh" && chmod +x "mount-vm-drives.sh"
```

```sh
./mount-vm-drives.sh /dev/pve/vm-123-disk-0 /mnt/vm123 --ro
```

#### `unmount-vm-drives.sh`

Unmount filesystems belonging to an LVM-backed VM disk and safely remove its mapper/empty mount directories.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/unmount-vm-drives.sh" -O "unmount-vm-drives.sh" && chmod +x "unmount-vm-drives.sh"
```

```sh
./unmount-vm-drives.sh /dev/pve/vm-123-disk-0
```

#### `mount-vm-disk.sh`

Resolve a VM disk slot to its LVM device and mount the filesystems beneath a chosen mount root.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/mount-vm-disk.sh" -O "mount-vm-disk.sh" && chmod +x "mount-vm-disk.sh"
```

```sh
./mount-vm-disk.sh 123 scsi0 /mnt/vm123 --ro
```

#### `mount-vm-root.sh`

Mount a VM disk and identify the filesystem that most likely contains the guest's Linux root.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/mount-vm-root.sh" -O "mount-vm-root.sh" && chmod +x "mount-vm-root.sh"
```

```sh
./mount-vm-root.sh 123 scsi0 /mnt/vm123 --ro
```

### VM disk lifecycle

#### `move-disk-to-vm.sh`

Move an LVM-backed disk to another QEMU VM by full LV path or source VM + disk number; numeric selectors understand both `vm-` and `base-` names (including an unambiguous stale embedded VMID), with hot/pause/stop/restart source-state control.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/move-disk-to-vm.sh" -O "move-disk-to-vm.sh" && chmod +x "move-disk-to-vm.sh"
```

```sh
./move-disk-to-vm.sh 123 0 456 pause dryrun
```

#### `attach-existing-lvm-to-vm.sh`

Attach an existing LVM volume to a QEMU VM as a SCSI disk without copying it.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/attach-existing-lvm-to-vm.sh" -O "attach-existing-lvm-to-vm.sh" && chmod +x "attach-existing-lvm-to-vm.sh"
```

```sh
./attach-existing-lvm-to-vm.sh /dev/pve/vm-123-disk-2 123 scsi2 dryrun
```

#### `detach-disk-from-vm.sh`

Detach a VM disk slot while preserving the backing volume as an `unusedN` entry.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/detach-disk-from-vm.sh" -O "detach-disk-from-vm.sh" && chmod +x "detach-disk-from-vm.sh"
```

```sh
./detach-disk-from-vm.sh 123 scsi2 dryrun
```

#### `delete-disk-from-vm.sh`

Delete a VM disk or `unusedN` volume from both the guest configuration and backing Proxmox storage.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/delete-disk-from-vm.sh" -O "delete-disk-from-vm.sh" && chmod +x "delete-disk-from-vm.sh"
```

```sh
./delete-disk-from-vm.sh 123 unused0 dryrun
```

#### `cleanup-unused-disks.sh`

List or delete selected/all `unusedN` disks from a QEMU VM with shared-reference checks.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/cleanup-unused-disks.sh" -O "cleanup-unused-disks.sh" && chmod +x "cleanup-unused-disks.sh"
```

```sh
./cleanup-unused-disks.sh 123 --all dryrun
```

### Disk copy, snapshot and cloning

#### `create-disk-snapshot-and-add-to-vm.sh`

Create an LVM-thin snapshot from an LV path, `VMID + disk-N`, or `VMID + exact-slot`; `disk-N` resolves `vm-` or `base-` sources, and destination naming automatically uses `base-` for templates or `vm-` for normal VMs, with device selection, state handling and optional `boot` promotion.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/create-disk-snapshot-and-add-to-vm.sh" -O "create-disk-snapshot-and-add-to-vm.sh" && chmod +x "create-disk-snapshot-and-add-to-vm.sh"
```

```sh
./create-disk-snapshot-and-add-to-vm.sh 123 sata0 456 virtio boot pause dryrun
```

#### `create-disk-copy-and-add-to-vm.sh`

Create a full verified copy from an LV path, `VMID + disk-N`, or `VMID + exact-slot`; `disk-N` resolves `vm-` or `base-` sources, and destination naming automatically uses `base-` for templates or `vm-` for normal VMs, with destination VG/device selection, state handling and optional `boot` promotion.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/create-disk-copy-and-add-to-vm.sh" -O "create-disk-copy-and-add-to-vm.sh" && chmod +x "create-disk-copy-and-add-to-vm.sh"
```

```sh
./create-disk-copy-and-add-to-vm.sh 123 scsi0 456 sata fastvg restart boot dryrun
```

#### `create-disk-copy-and-overwrite-disk-on-vm.sh`

Create and byte-verify an independent copy using a destination backing disk number, exact slot, or first-free bus; replace/archive an occupied exact target or create into an empty slot, with optional `delete`, VM-state handling, and `boot` promotion.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/create-disk-copy-and-overwrite-disk-on-vm.sh" -O "create-disk-copy-and-overwrite-disk-on-vm.sh" && chmod +x "create-disk-copy-and-overwrite-disk-on-vm.sh"
```

```sh
./create-disk-copy-and-overwrite-disk-on-vm.sh 123 sata0 456 sata0 pause boot dryrun
```

#### `create-disk-snapshot-and-overwrite-disk-on-vm.sh`

Create an LVM-thin snapshot using a destination backing disk number, exact slot, or first-free bus; replace/archive an occupied exact target or create into an empty slot, with optional `delete`, VM-state handling, and `boot` promotion.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/create-disk-snapshot-and-overwrite-disk-on-vm.sh" -O "create-disk-snapshot-and-overwrite-disk-on-vm.sh" && chmod +x "create-disk-snapshot-and-overwrite-disk-on-vm.sh"
```

```sh
./create-disk-snapshot-and-overwrite-disk-on-vm.sh 123 scsi0 456 virtio restart boot dryrun
```

#### `copy-disk-between-vms.sh`

Copy one QEMU VM disk to another VM as an independent verified volume.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/copy-disk-between-vms.sh" -O "copy-disk-between-vms.sh" && chmod +x "copy-disk-between-vms.sh"
```

```sh
./copy-disk-between-vms.sh 123 scsi0 456 fastvg dryrun
```

#### `snapshot-disk-between-vms.sh`

Create an LVM-thin snapshot of one VM disk and attach that linked snapshot to another VM.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/snapshot-disk-between-vms.sh" -O "snapshot-disk-between-vms.sh" && chmod +x "snapshot-disk-between-vms.sh"
```

```sh
./snapshot-disk-between-vms.sh 123 scsi0 456 dryrun
```

#### `clone-single-vm-disk.sh`

Clone one disk of a QEMU VM and attach the independent copy back to that VM.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/clone-single-vm-disk.sh" -O "clone-single-vm-disk.sh" && chmod +x "clone-single-vm-disk.sh"
```

```sh
./clone-single-vm-disk.sh 123 scsi0 fastvg dryrun
```

### Disk configuration surgery

#### `change-disk-bus.sh`

Move a VM disk configuration from one bus/slot to another while preserving its disk options.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/change-disk-bus.sh" -O "change-disk-bus.sh" && chmod +x "change-disk-bus.sh"
```

```sh
./change-disk-bus.sh 123 scsi1 sata0 dryrun
```

#### `swap-vm-disks.sh`

Swap the complete configuration values of two VM disk slots.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/swap-vm-disks.sh" -O "swap-vm-disks.sh" && chmod +x "swap-vm-disks.sh"
```

```sh
./swap-vm-disks.sh 123 scsi0 scsi1 dryrun
```

#### `set-vm-boot-disk.sh`

Put a selected VM disk slot first in the QEMU boot order.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/set-vm-boot-disk.sh" -O "set-vm-boot-disk.sh" && chmod +x "set-vm-boot-disk.sh"
```

```sh
./set-vm-boot-disk.sh 123 scsi0 dryrun
```

#### `replace-vm-disk.sh`

Replace a VM disk slot with an existing replacement LVM volume while retaining the slot's disk options.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/replace-vm-disk.sh" -O "replace-vm-disk.sh" && chmod +x "replace-vm-disk.sh"
```

```sh
./replace-vm-disk.sh 123 scsi0 /dev/pve/vm-123-disk-9 dryrun
```

#### `renumber-vm-disks.sh`

Renumber configured managed LVs into contiguous sequences per prefix + embedded-VMID namespace (for example `vm-199-*` separately from stale `base-100-*`), preserving those namespaces, updating the VM configuration, and refusing volumes referenced by another guest.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/renumber-vm-disks.sh" -O "renumber-vm-disks.sh" && chmod +x "renumber-vm-disks.sh"
```

```sh
./renumber-vm-disks.sh 123 dryrun
```

#### `fix-vm-volume-names.sh`

Repair managed backing LV names whose embedded VMID does not match the referencing guest, including normal disks, `unusedN`, EFI and TPM state volumes; preserve `vm-` vs `base-` and the original `disk-N`, and refuse an exact corrected-name collision instead of silently choosing another number.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/fix-vm-volume-names.sh" -O "fix-vm-volume-names.sh" && chmod +x "fix-vm-volume-names.sh"
```

```sh
./fix-vm-volume-names.sh 123 dryrun
```

### Storage, import and export

#### `move-disk-to-storage.sh`

Move one QEMU VM disk to another configured Proxmox storage using `qm move_disk`.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/move-disk-to-storage.sh" -O "move-disk-to-storage.sh" && chmod +x "move-disk-to-storage.sh"
```

```sh
./move-disk-to-storage.sh 123 scsi0 fast-lvm dryrun
```

#### `bulk-change-vm-storage.sh`

Move matching VM disks from one Proxmox storage ID to another across multiple VMIDs.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/bulk-change-vm-storage.sh" -O "bulk-change-vm-storage.sh" && chmod +x "bulk-change-vm-storage.sh"
```

```sh
./bulk-change-vm-storage.sh local-lvm fast-lvm 123 124 125 dryrun
```

#### `change-vm-storage-prefix.sh`

Rewrite an old Proxmox storage ID prefix to a new storage ID in affected local guest configurations.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/change-vm-storage-prefix.sh" -O "change-vm-storage-prefix.sh" && chmod +x "change-vm-storage-prefix.sh"
```

```sh
./change-vm-storage-prefix.sh old-lvm new-lvm dryrun
```

#### `import-disk-and-attach.sh`

Import a disk image into Proxmox storage and attach the resulting volume to a QEMU VM.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/import-disk-and-attach.sh" -O "import-disk-and-attach.sh" && chmod +x "import-disk-and-attach.sh"
```

```sh
./import-disk-and-attach.sh ./server.raw 123 local-lvm scsi1 dryrun
```

#### `export-vm-disk.sh`

Export a QEMU VM disk to a raw or qcow2 image using `qemu-img`.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/export-vm-disk.sh" -O "export-vm-disk.sh" && chmod +x "export-vm-disk.sh"
```

```sh
./export-vm-disk.sh 123 scsi0 ./vm-123-scsi0.qcow2 qcow2 dryrun
```

### Networking

#### `bulk-change-vm-network.sh`

Apply the same bridge/tag/firewall/model settings to one NIC slot across multiple QEMU VMs.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/bulk-change-vm-network.sh" -O "bulk-change-vm-network.sh" && chmod +x "bulk-change-vm-network.sh"
```

```sh
./bulk-change-vm-network.sh net0 vmbr1 --tag 20 --firewall 1 123 124 125 dryrun
```

## Standalone by design

The `lib/` directory in the repository is the canonical maintenance source for shared helper code, but the published top-level commands do **not** source it at runtime. The shared runtime is embedded into every helper, and wrapper commands also bundle the companion implementation they need.

That means this is valid:

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/change-vmid-of-vm.sh" -O change-vmid-of-vm.sh
chmod +x change-vmid-of-vm.sh
./change-vmid-of-vm.sh --help
```

You can move that file to `/root`, `/usr/local/sbin`, a rescue directory, or another host without copying anything else from this repository.

## Install the whole repository

If you expect to use more than one helper, cloning the repository is simpler than downloading commands individually:

```sh
git clone https://github.com/proxmoxhelpers/Proxmox-LongTailToil.git && cd Proxmox-LongTailToil
```

Every command supports:

```sh
./some-command.sh --help
```

and:

```sh
./some-command.sh --version
```

Most commands that can modify the host also accept `dryrun` or `--dryrun` anywhere on the command line.

## Proxmox managed LVM names

Where a helper interprets Proxmox-managed LVM volume names, both standard families are supported:

```text
vm-VMID-disk-N
base-VMID-disk-N
```

`base-` is used by Proxmox templates/base images. Operations that rename an existing managed volume preserve its family; operations that create a destination disk use `base-` when the destination QEMU guest is a template and `vm-` otherwise. Disk-number selectors first prefer the current VMID and may fall back to a stale embedded VMID only when exactly one configured managed volume has that `disk-N`.

## Safety model

These scripts are deliberately more cautious than the one-liners they replace. Depending on the operation they perform preflight discovery, refuse ambiguous storage mappings and shared references, check name/slot collisions, preserve or explicitly control guest state, create backups before direct `/etc/pve` edits, verify postconditions, and use rollback or conservative preservation when a multi-step transaction fails.

The copy paths distinguish thin and regular LVs: sparse copying is used only for newly allocated thin destinations, while regular LVs receive full writes so skipped zero blocks cannot expose stale underlying data. LVM stderr is not globally hidden; only the three known repetitive thin-pool advisories are filtered, while unrelated warnings and errors remain visible.

Every mutating helper supports project dry-run semantics, and the integration suite enforces at least one exact-state dry-run case for every mutating public command. Refusal paths are tested the same way: the command must fail while the complete disposable state remains unchanged.

The integration harness is intentionally fail-closed. It creates uniquely named loopback-backed test VGs/storage and dynamically allocated disposable QEMU/LXC guests, records ownership before mutation, and refuses cleanup if a guest identity/storage mapping no longer matches that ownership. Remaining mounts block guest/storage cleanup; remaining guests block storage/VG cleanup; remaining storage definitions block VG/loop cleanup. Pre-existing project backup paths are recorded before each run and are never removed as test artifacts.

Protected-host comparisons include pre-existing VG/PV/LV metadata, canonical storage semantics, guest configuration checksums, local QEMU/LXC runtime state and firewall-file checksums. Dry-run/refusal snapshots additionally include disposable LV metadata and sampled content hashes, guest configs/status, test storage definitions, test files and mounts. Data-sensitive copy/move/import/export tests independently verify bytes with `cmp` or hashes.

## Tested on real Proxmox fixtures

The last fully documented real-Proxmox integration-validated POSIX baseline is **v3.0.1**, whose then-current 36-command suite completed cleanly with dry-run state unchanged and protected guest/LVM/storage state returned to baseline.

The current **v3.4.2** release candidate contains 42 standalone helpers and an expanded **84-case** real integration definition plus static/CLI contracts. The suite now covers thin and regular LV copies, destructive-confirmation/refusal behavior, direct and partitioned mounts, shared-reference guards, hot/pause/stop/restart state modes, overwrite archive/delete/empty-target transactions, device slot/bus selectors, boot-order preservation, `vm-`/`base-` naming, QEMU/template/LXC VMID changes, QEMU/LXC network edits, and byte-preserving storage move/import/export paths.

The v3.4.2 harness also protects more host state than the earlier baseline: it records local guest runtime status and firewall checksums, samples disposable LV content for dry-run/refusal comparisons, and uses layered cleanup that stops rather than guessing when ownership cannot be proven.

Run the full current suite on a disposable or non-production Proxmox node:

```sh
./tests/run-all-tests.sh --run --verbose
```

A v3.4.2 build should be described as **release-candidate / statically validated** until that real-host run finishes with zero failed cases and zero protected-state anomalies. The command-by-command behavior map is in [`tests/TEST-MATRIX.md`](tests/TEST-MATRIX.md).

## Why this exists

This project was originally inspired by the long-running Proxmox forum thread **“Changing VMID of a VM”**, started in January 2020.

That discussion is a good example of long-tail toil: the underlying operation can look deceptively simple—rename an LV, edit a config, rename a file—but over the years the thread accumulated edge cases around LVM/LVM-thin, ZFS, templates, snapshots, backing-volume naming, collisions, shared references, PBS workflows and cluster configuration. The official safe answer is often backup/restore or clone/delete, while operators sometimes need a faster in-place maintenance operation and end up reconstructing the same shell procedure from memory.

`change-vmid-of-vm.sh` grew from that idea, and the repository expanded into the other infrequent Proxmox tasks with the same philosophy: **preflight first, show a dry run, mutate only the intended disposable/selected objects, then verify what actually happened.**

For VMID changes specifically, remember that changing a VMID is not an ordinary rename supported by Proxmox. The helper intentionally supports only the storage/configuration cases it knows how to validate and tells you to review external references such as backup jobs, ACLs, HA, replication, pools, hooks and other automation afterward.

## Requirements

- Proxmox VE
- POSIX `/bin/sh`
- root privileges or `sudo` for modifying operations
- LVM/LVM-thin for the LVM-specific helpers
- standard Proxmox/Linux tools used by the selected command (`qm`, `pct`, `pvesm`, LVM, `kpartx`, `partx`, `sfdisk`, `blkid`, `findmnt`, `qemu-img`, etc.)

Read-only inspection helpers do not require elevation merely to run `--help`, `--version`, or their normal inspection paths where the host permits access.

## Documentation

- [POSIX shell style guide](docs/POSIX-SHELL-STYLE-GUIDE-v3.md)
- [Style profiles and exceptions](docs/STYLE-PROFILES-AND-EXCEPTIONS.md)
- [v3 migration notes](docs/V3-MIGRATION-NOTES.md)
- [Testing documentation](docs/testing/README.md)
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
