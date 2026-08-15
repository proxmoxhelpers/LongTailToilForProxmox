# Proxmox LongTail Toil

**Proxmox LongTail Toil** is a collection of small, safety-focused helpers for the Proxmox jobs that are too easy to automate, too hard to remember, and do not happen often enough to bother scripting from scratch each time.  
It covers the awkward long-tail work around VMIDs, LVM/LVM-thin volumes, disks, mounts, storage, recovery and repetitive VM configuration changes.  
The goal is simple: turn a risky sequence of half-remembered shell commands into a preflighted, dry-runnable, verified operation.

> **“Fix for things that are too easy to automate, too hard to remember and don't happen often enough to bother.”**

Repository: [proxmoxhelpers/Proxmox-LongTailToil](https://github.com/proxmoxhelpers/Proxmox-LongTailToil)

> This is an independent community project and is not affiliated with or endorsed by Proxmox Server Solutions GmbH.

## The 36 helpers

For modifying commands, the examples below use `dryrun` where practical. Dry-run still performs real read-only preflight checks, but prints modifying commands instead of executing them. Remove `dryrun` only after reviewing the plan.

Each single-file download line also fetches the two shared v3 libraries required by the command.

### VM identity, recovery and inspection

#### `change-vmid-of-vm.sh`

Change the VMID of a stopped local QEMU VM or LXC container whose backing volumes are on LVM/LVM-thin, with preflight checks, backup, verification and rollback.

```sh
for f in change-vmid-of-vm.sh lib/common.sh lib/dryrun.sh; do mkdir -p "$(dirname "$f")"; wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/$f" -O "$f"; done; chmod +x change-vmid-of-vm.sh
```

```sh
./change-vmid-of-vm.sh 123 456 dryrun
```

#### `clone-vm-config-only.sh`

Clone a QEMU VM configuration to a new VMID without copying its disks.

```sh
for f in clone-vm-config-only.sh lib/common.sh lib/dryrun.sh; do mkdir -p "$(dirname "$f")"; wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/$f" -O "$f"; done; chmod +x clone-vm-config-only.sh
```

```sh
./clone-vm-config-only.sh 123 456 web-copy dryrun
```

#### `recover-vm-from-volumes.sh`

Recreate a basic QEMU VM configuration from existing `vm-VMID-disk-N` LVM volumes.

```sh
for f in recover-vm-from-volumes.sh lib/common.sh lib/dryrun.sh; do mkdir -p "$(dirname "$f")"; wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/$f" -O "$f"; done; chmod +x recover-vm-from-volumes.sh
```

```sh
./recover-vm-from-volumes.sh 456 pve dryrun
```

#### `list-vm-disks.sh`

List a QEMU VM's configured disks, resolved storage paths and available LVM metadata.

```sh
for f in list-vm-disks.sh lib/common.sh lib/dryrun.sh; do mkdir -p "$(dirname "$f")"; wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/$f" -O "$f"; done; chmod +x list-vm-disks.sh
```

```sh
./list-vm-disks.sh 123
```

#### `audit-vm-storage.sh`

Audit a VM's storage references for missing paths, bad mappings and unexpected references.

```sh
for f in audit-vm-storage.sh lib/common.sh lib/dryrun.sh; do mkdir -p "$(dirname "$f")"; wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/$f" -O "$f"; done; chmod +x audit-vm-storage.sh
```

```sh
./audit-vm-storage.sh 123
```

#### `find-volume-owner.sh`

Find which local guest configuration references a specific LVM path or Proxmox volume ID.

```sh
for f in find-volume-owner.sh lib/common.sh lib/dryrun.sh; do mkdir -p "$(dirname "$f")"; wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/$f" -O "$f"; done; chmod +x find-volume-owner.sh
```

```sh
./find-volume-owner.sh /dev/pve/vm-123-disk-0
```

#### `find-orphaned-volumes.sh`

Find VM-style LVM volumes that do not appear to be referenced by local guest configurations.

```sh
for f in find-orphaned-volumes.sh lib/common.sh lib/dryrun.sh; do mkdir -p "$(dirname "$f")"; wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/$f" -O "$f"; done; chmod +x find-orphaned-volumes.sh
```

```sh
./find-orphaned-volumes.sh pve
```

### Raw LVM operations

#### `copy-lvm.sh`

Create and byte-verify an independent copy of an LVM/LVM-thin logical volume.

```sh
for f in copy-lvm.sh lib/common.sh lib/dryrun.sh; do mkdir -p "$(dirname "$f")"; wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/$f" -O "$f"; done; chmod +x copy-lvm.sh
```

```sh
./copy-lvm.sh /dev/pve/vm-123-disk-0 /dev/fastvg/vm-123-disk-0-copy dryrun
```

#### `move-lvm.sh`

Rename an LV in place within a VG, or copy-verify-delete it safely when moving across VGs.

```sh
for f in move-lvm.sh lib/common.sh lib/dryrun.sh; do mkdir -p "$(dirname "$f")"; wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/$f" -O "$f"; done; chmod +x move-lvm.sh
```

```sh
./move-lvm.sh /dev/pve/vm-123-disk-0 /dev/fastvg/vm-123-disk-0 dryrun
```

#### `rename-lvm.sh`

Rename an LVM logical volume after validating its source and destination names.

```sh
for f in rename-lvm.sh lib/common.sh lib/dryrun.sh; do mkdir -p "$(dirname "$f")"; wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/$f" -O "$f"; done; chmod +x rename-lvm.sh
```

```sh
./rename-lvm.sh /dev/pve/vm-123-disk-0 vm-123-disk-0-old dryrun
```

#### `delete-lvm.sh`

Delete an LVM logical volume with explicit confirmation and post-delete verification.

```sh
for f in delete-lvm.sh lib/common.sh lib/dryrun.sh; do mkdir -p "$(dirname "$f")"; wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/$f" -O "$f"; done; chmod +x delete-lvm.sh
```

```sh
./delete-lvm.sh /dev/pve/vm-123-disk-0-old dryrun
```

### Mounting and filesystem inspection

#### `mount-vm-drives.sh`

Mount recognizable filesystems from an LVM-backed VM disk, using `kpartx` for partitions and read-only mode by default.

```sh
for f in mount-vm-drives.sh lib/common.sh lib/dryrun.sh; do mkdir -p "$(dirname "$f")"; wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/$f" -O "$f"; done; chmod +x mount-vm-drives.sh
```

```sh
./mount-vm-drives.sh /dev/pve/vm-123-disk-0 /mnt/vm123 --ro
```

#### `unmount-vm-drives.sh`

Unmount filesystems belonging to an LVM-backed VM disk and safely remove its mapper/empty mount directories.

```sh
for f in unmount-vm-drives.sh lib/common.sh lib/dryrun.sh; do mkdir -p "$(dirname "$f")"; wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/$f" -O "$f"; done; chmod +x unmount-vm-drives.sh
```

```sh
./unmount-vm-drives.sh /dev/pve/vm-123-disk-0
```

#### `mount-vm-disk.sh`

Resolve a VM disk slot to its LVM device and mount the filesystems beneath a chosen mount root.

```sh
for f in mount-vm-disk.sh lib/common.sh lib/dryrun.sh; do mkdir -p "$(dirname "$f")"; wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/$f" -O "$f"; done; chmod +x mount-vm-disk.sh
```

```sh
./mount-vm-disk.sh 123 scsi0 /mnt/vm123 --ro
```

#### `mount-vm-root.sh`

Mount a VM disk and identify the filesystem that most likely contains the guest's Linux root.

```sh
for f in mount-vm-root.sh lib/common.sh lib/dryrun.sh; do mkdir -p "$(dirname "$f")"; wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/$f" -O "$f"; done; chmod +x mount-vm-root.sh
```

```sh
./mount-vm-root.sh 123 scsi0 /mnt/vm123 --ro
```

### VM disk lifecycle

#### `attach-existing-lvm-to-vm.sh`

Attach an existing LVM volume to a QEMU VM as a SCSI disk without copying it.

```sh
for f in attach-existing-lvm-to-vm.sh lib/common.sh lib/dryrun.sh; do mkdir -p "$(dirname "$f")"; wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/$f" -O "$f"; done; chmod +x attach-existing-lvm-to-vm.sh
```

```sh
./attach-existing-lvm-to-vm.sh /dev/pve/vm-123-disk-2 123 scsi2 dryrun
```

#### `detach-disk-from-vm.sh`

Detach a VM disk slot while preserving the backing volume as an `unusedN` entry.

```sh
for f in detach-disk-from-vm.sh lib/common.sh lib/dryrun.sh; do mkdir -p "$(dirname "$f")"; wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/$f" -O "$f"; done; chmod +x detach-disk-from-vm.sh
```

```sh
./detach-disk-from-vm.sh 123 scsi2 dryrun
```

#### `delete-disk-from-vm.sh`

Delete a VM disk or `unusedN` volume from both the guest configuration and backing Proxmox storage.

```sh
for f in delete-disk-from-vm.sh lib/common.sh lib/dryrun.sh; do mkdir -p "$(dirname "$f")"; wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/$f" -O "$f"; done; chmod +x delete-disk-from-vm.sh
```

```sh
./delete-disk-from-vm.sh 123 unused0 dryrun
```

#### `cleanup-unused-disks.sh`

List or delete selected/all `unusedN` disks from a QEMU VM with shared-reference checks.

```sh
for f in cleanup-unused-disks.sh lib/common.sh lib/dryrun.sh; do mkdir -p "$(dirname "$f")"; wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/$f" -O "$f"; done; chmod +x cleanup-unused-disks.sh
```

```sh
./cleanup-unused-disks.sh 123 --all dryrun
```

### Disk copy, snapshot and cloning

#### `create-disk-snapshot-and-add-to-vm.sh`

Create an LVM-thin snapshot of a source LV and attach it to another QEMU VM.

```sh
for f in create-disk-snapshot-and-add-to-vm.sh lib/common.sh lib/dryrun.sh; do mkdir -p "$(dirname "$f")"; wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/$f" -O "$f"; done; chmod +x create-disk-snapshot-and-add-to-vm.sh
```

```sh
./create-disk-snapshot-and-add-to-vm.sh /dev/pve/vm-123-disk-0 456 dryrun
```

#### `create-disk-copy-and-add-to-vm.sh`

Create a full independent copy of an LV and attach it to a destination QEMU VM.

```sh
for f in create-disk-copy-and-add-to-vm.sh lib/common.sh lib/dryrun.sh; do mkdir -p "$(dirname "$f")"; wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/$f" -O "$f"; done; chmod +x create-disk-copy-and-add-to-vm.sh
```

```sh
./create-disk-copy-and-add-to-vm.sh /dev/pve/vm-123-disk-0 456 fastvg dryrun
```

#### `copy-disk-between-vms.sh`

Copy one QEMU VM disk to another VM as an independent verified volume.

```sh
for f in copy-disk-between-vms.sh lib/common.sh lib/dryrun.sh; do mkdir -p "$(dirname "$f")"; wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/$f" -O "$f"; done; chmod +x copy-disk-between-vms.sh
```

```sh
./copy-disk-between-vms.sh 123 scsi0 456 fastvg dryrun
```

#### `snapshot-disk-between-vms.sh`

Create an LVM-thin snapshot of one VM disk and attach that linked snapshot to another VM.

```sh
for f in snapshot-disk-between-vms.sh lib/common.sh lib/dryrun.sh; do mkdir -p "$(dirname "$f")"; wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/$f" -O "$f"; done; chmod +x snapshot-disk-between-vms.sh
```

```sh
./snapshot-disk-between-vms.sh 123 scsi0 456 dryrun
```

#### `clone-single-vm-disk.sh`

Clone one disk of a QEMU VM and attach the independent copy back to that VM.

```sh
for f in clone-single-vm-disk.sh lib/common.sh lib/dryrun.sh; do mkdir -p "$(dirname "$f")"; wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/$f" -O "$f"; done; chmod +x clone-single-vm-disk.sh
```

```sh
./clone-single-vm-disk.sh 123 scsi0 fastvg dryrun
```

### Disk configuration surgery

#### `change-disk-bus.sh`

Move a VM disk configuration from one bus/slot to another while preserving its disk options.

```sh
for f in change-disk-bus.sh lib/common.sh lib/dryrun.sh; do mkdir -p "$(dirname "$f")"; wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/$f" -O "$f"; done; chmod +x change-disk-bus.sh
```

```sh
./change-disk-bus.sh 123 scsi1 sata0 dryrun
```

#### `swap-vm-disks.sh`

Swap the complete configuration values of two VM disk slots.

```sh
for f in swap-vm-disks.sh lib/common.sh lib/dryrun.sh; do mkdir -p "$(dirname "$f")"; wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/$f" -O "$f"; done; chmod +x swap-vm-disks.sh
```

```sh
./swap-vm-disks.sh 123 scsi0 scsi1 dryrun
```

#### `set-vm-boot-disk.sh`

Put a selected VM disk slot first in the QEMU boot order.

```sh
for f in set-vm-boot-disk.sh lib/common.sh lib/dryrun.sh; do mkdir -p "$(dirname "$f")"; wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/$f" -O "$f"; done; chmod +x set-vm-boot-disk.sh
```

```sh
./set-vm-boot-disk.sh 123 scsi0 dryrun
```

#### `replace-vm-disk.sh`

Replace a VM disk slot with an existing replacement LVM volume while retaining the slot's disk options.

```sh
for f in replace-vm-disk.sh lib/common.sh lib/dryrun.sh; do mkdir -p "$(dirname "$f")"; wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/$f" -O "$f"; done; chmod +x replace-vm-disk.sh
```

```sh
./replace-vm-disk.sh 123 scsi0 /dev/pve/vm-123-disk-9 dryrun
```

#### `renumber-vm-disks.sh`

Renumber a VM's backing `vm-VMID-disk-N` LVs into a contiguous sequence and update its configuration.

```sh
for f in renumber-vm-disks.sh lib/common.sh lib/dryrun.sh; do mkdir -p "$(dirname "$f")"; wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/$f" -O "$f"; done; chmod +x renumber-vm-disks.sh
```

```sh
./renumber-vm-disks.sh 123 dryrun
```

#### `fix-vm-volume-names.sh`

Rename backing VM LVs whose embedded VMID does not match the VM that references them.

```sh
for f in fix-vm-volume-names.sh lib/common.sh lib/dryrun.sh; do mkdir -p "$(dirname "$f")"; wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/$f" -O "$f"; done; chmod +x fix-vm-volume-names.sh
```

```sh
./fix-vm-volume-names.sh 123 dryrun
```

### Storage, import and export

#### `move-disk-to-storage.sh`

Move one QEMU VM disk to another configured Proxmox storage using `qm move_disk`.

```sh
for f in move-disk-to-storage.sh lib/common.sh lib/dryrun.sh; do mkdir -p "$(dirname "$f")"; wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/$f" -O "$f"; done; chmod +x move-disk-to-storage.sh
```

```sh
./move-disk-to-storage.sh 123 scsi0 fast-lvm dryrun
```

#### `bulk-change-vm-storage.sh`

Move matching VM disks from one Proxmox storage ID to another across multiple VMIDs.

```sh
for f in bulk-change-vm-storage.sh lib/common.sh lib/dryrun.sh; do mkdir -p "$(dirname "$f")"; wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/$f" -O "$f"; done; chmod +x bulk-change-vm-storage.sh
```

```sh
./bulk-change-vm-storage.sh local-lvm fast-lvm 123 124 125 dryrun
```

#### `change-vm-storage-prefix.sh`

Rewrite an old Proxmox storage ID prefix to a new storage ID in affected local guest configurations.

```sh
for f in change-vm-storage-prefix.sh lib/common.sh lib/dryrun.sh; do mkdir -p "$(dirname "$f")"; wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/$f" -O "$f"; done; chmod +x change-vm-storage-prefix.sh
```

```sh
./change-vm-storage-prefix.sh old-lvm new-lvm dryrun
```

#### `import-disk-and-attach.sh`

Import a disk image into Proxmox storage and attach the resulting volume to a QEMU VM.

```sh
for f in import-disk-and-attach.sh lib/common.sh lib/dryrun.sh; do mkdir -p "$(dirname "$f")"; wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/$f" -O "$f"; done; chmod +x import-disk-and-attach.sh
```

```sh
./import-disk-and-attach.sh ./server.raw 123 local-lvm scsi1 dryrun
```

#### `export-vm-disk.sh`

Export a QEMU VM disk to a raw or qcow2 image using `qemu-img`.

```sh
for f in export-vm-disk.sh lib/common.sh lib/dryrun.sh; do mkdir -p "$(dirname "$f")"; wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/$f" -O "$f"; done; chmod +x export-vm-disk.sh
```

```sh
./export-vm-disk.sh 123 scsi0 ./vm-123-scsi0.qcow2 qcow2 dryrun
```

### Networking

#### `bulk-change-vm-network.sh`

Apply the same bridge/tag/firewall/model settings to one NIC slot across multiple QEMU VMs.

```sh
for f in bulk-change-vm-network.sh lib/common.sh lib/dryrun.sh; do mkdir -p "$(dirname "$f")"; wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/$f" -O "$f"; done; chmod +x bulk-change-vm-network.sh
```

```sh
./bulk-change-vm-network.sh net0 vmbr1 --tag 20 --firewall 1 123 124 125 dryrun
```

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
