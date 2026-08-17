# Proxmox LongTail Toil

**Proxmox LongTail Toil** is a collection of 40 self-contained, safety-focused helpers for the Proxmox jobs that are easy to automate but awkward to remember because they happen infrequently, covering VMIDs, LVM/LVM-thin volumes, disks, mounts, storage, recovery and repetitive VM configuration changes. Each helper is a single portable `.sh` file, and modifying commands support `dryrun` so you can perform real read-only preflight checks and review the planned changes before anything is modified.

## The 40 helpers

### VM identity, recovery and inspection

#### `change-vmid-of-vm.sh`

Change the VMID of a stopped local QEMU VM or LXC container whose backing volumes are on LVM/LVM-thin, with preflight checks, backup, verification and rollback.

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

Recreate a basic QEMU VM configuration from existing `vm-VMID-disk-N` LVM volumes.

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

Find VM-style LVM volumes that do not appear to be referenced by local guest configurations.

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

Move an LVM-backed disk to another QEMU VM by full LV path or source VM + disk number; default is live hot-swap, with optional `pause`, `stop`, or `restart` control for the source VM.

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

Create an LVM-thin snapshot from either a full LV path or `VMID + disk-N`, then attach it to a destination VM; optionally choose the destination backing disk number and use `pause`, `stop`, or `restart` on the source VM.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/create-disk-snapshot-and-add-to-vm.sh" -O "create-disk-snapshot-and-add-to-vm.sh" && chmod +x "create-disk-snapshot-and-add-to-vm.sh"
```

```sh
./create-disk-snapshot-and-add-to-vm.sh 123 disk-0 456 disk-3 pause dryrun
```

#### `create-disk-copy-and-add-to-vm.sh`

Create a full verified copy from either a full LV path or `VMID + disk-N`, attach it to a destination VM, optionally choose the destination backing disk number/VG, and optionally `pause`, `stop`, or `restart` the source VM.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/create-disk-copy-and-add-to-vm.sh" -O "create-disk-copy-and-add-to-vm.sh" && chmod +x "create-disk-copy-and-add-to-vm.sh"
```

```sh
./create-disk-copy-and-add-to-vm.sh 123 disk-0 456 disk-3 fastvg restart dryrun
```

#### `create-disk-copy-and-overwrite-disk-on-vm.sh`

Create and byte-verify an independent copy of the source, replace an existing destination VM disk with it, and preserve the displaced destination volume as `unusedN`; source and destination may each be given by full LV path or `VMID + disk-N`.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/create-disk-copy-and-overwrite-disk-on-vm.sh" -O "create-disk-copy-and-overwrite-disk-on-vm.sh" && chmod +x "create-disk-copy-and-overwrite-disk-on-vm.sh"
```

```sh
./create-disk-copy-and-overwrite-disk-on-vm.sh 123 disk-0 456 disk-1 pause dryrun
```

#### `create-disk-snapshot-and-overwrite-disk-on-vm.sh`

Create an LVM-thin snapshot of the source, replace an existing destination VM disk with that linked snapshot, and preserve the displaced destination volume as `unusedN`; source and destination may each be given by full LV path or `VMID + disk-N`.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/create-disk-snapshot-and-overwrite-disk-on-vm.sh" -O "create-disk-snapshot-and-overwrite-disk-on-vm.sh" && chmod +x "create-disk-snapshot-and-overwrite-disk-on-vm.sh"
```

```sh
./create-disk-snapshot-and-overwrite-disk-on-vm.sh /dev/pve/vm-123-disk-0 /dev/pve/vm-456-disk-1 restart dryrun
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

Renumber a VM's backing `vm-VMID-disk-N` LVs into a contiguous sequence and update its configuration.

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/renumber-vm-disks.sh" -O "renumber-vm-disks.sh" && chmod +x "renumber-vm-disks.sh"
```

```sh
./renumber-vm-disks.sh 123 dryrun
```

#### `fix-vm-volume-names.sh`

Rename backing VM LVs whose embedded VMID does not match the VM that references them.

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

## Safety model

These scripts are deliberately more cautious than the one-liners they replace. Depending on the operation they perform preflight discovery, refuse ambiguous storage mappings, check for collisions/shared references, leave guests stopped when configuration surgery requires it, create backups before direct `/etc/pve` edits, verify postconditions, and use rollback or conservative preservation when a multi-step operation fails.

The copy paths distinguish thin and regular LVs: sparse copying is used only for newly allocated thin destinations, while regular LVs receive full writes so skipped zero blocks cannot expose stale underlying data.

LVM stderr is not globally hidden. Only the three known repetitive thin-pool advisories are filtered; unrelated warnings and errors remain visible.

## Tested on real Proxmox fixtures

The v3.0.1 POSIX implementation was exercised by the repository's disposable integration suite against real Proxmox/LVM tooling, not just mocked command lines.

The validated run covered all 36 command cases, including real `qm`, `pvesm`, LVM/device-mapper, mount/umount, `qemu-img`, storage move/import/export, snapshot, rename, delete, recovery and VMID-change operations. Dry-run before/after snapshots remained unchanged, and protected guest/LVM/storage state returned to baseline with no detected anomalies.

Version 3.2.0 adds the two overwrite helpers and expands the source/destination/state syntax of the existing create-and-add helpers. The integration matrix now covers all 40 commands. Run the suite on your Proxmox host before treating this feature release as validated for your environment.

Run the same suite on your own host:

```sh
./tests/run-all-tests.sh --run --verbose
```

The integration harness creates uniquely named loopback-backed disposable VGs/thin pools and stopped test VMs, verifies each operation, ownership-checks cleanup, and compares protected state before and after.

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
- standard Proxmox/Linux tools used by the selected command (`qm`, `pct`, `pvesm`, LVM, `kpartx`, `findmnt`, `qemu-img`, etc.)

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
