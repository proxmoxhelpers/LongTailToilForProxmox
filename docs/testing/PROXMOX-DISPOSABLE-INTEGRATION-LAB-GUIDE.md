# Proxmox Disposable Integration Lab Guide

This document describes a practical way to construct disposable integration-test fixtures for Proxmox VE storage and VM-management scripts.

It is based on the architecture that successfully exercised the Proxmox LVM Tools suite using real `qm`, `pvesm`, LVM, device-mapper, mount, and `qemu-img` operations while returning the host to its protected baseline after every group.

---

## 1. Design goal

The lab should provide:

```text
real block devices;
real LVM metadata;
real Proxmox storage definitions;
real stopped QEMU VMs;
real disk attach/detach/move operations;
real mountable filesystems;
real cleanup;
```

without consuming an existing production disk or VM.

The core topology is:

```text
sparse image A                    sparse image B
     │                                 │
     ▼                                 ▼
 loop device A                    loop device B
     │                                 │
     ▼                                 ▼
   PV A                              PV B
     │                                 │
     ▼                                 ▼
 test VG A                         test VG B
     │                                 │
     ▼                                 ▼
 thin pool A                       thin pool B
     │                                 │
     ▼                                 ▼
 Proxmox storage A                Proxmox storage B
       \                             /
        \                           /
         └──── disposable VMs ─────┘
```

This is a real storage stack. Only the backing media is synthetic.

---

## 2. Why loopback-backed LVM works well

Loop devices provide genuine block-device semantics.

That allows the tests to exercise:

```text
pvcreate
vgcreate
lvcreate
lvrename
lvremove
thin pools
device mapper
filesystem creation
mount
Proxmox LVM-thin storage
qm disk operations
```

without partitioning or overwriting a physical disk.

The backing files can be sparse, so a nominal 1 GiB test disk consumes much less physical space when mostly empty.

---

## 3. Never auto-select a real disk

The harness should not contain logic such as:

```text
find the smallest unused /dev/sdX
find an unmounted disk
use the first disk not in pves
```

That is too dangerous on a hypervisor.

The only acceptable block devices for destructive fixture creation should be loop devices that the current run created from its own backing files.

---

## 4. Backing-file ownership

Create backing files under a run-specific sandbox such as:

```text
/var/tmp/proxmox-lvm-tools-test-sandboxes/RUN-ID/
```

Example:

```text
plvtA47920001.img
plvtB47920001.img
```

After `losetup --find --show`, verify that:

```sh
losetup -j "$BACKING_FILE"
```

maps the expected loop device to that exact file.

Record:

```text
VG | loop device | backing file
```

before continuing.

---

## 5. Create two independent storage stacks

Two VGs are valuable because they exercise:

```text
same-VG rename;
cross-VG copy;
cross-VG move;
Proxmox storage migration;
copy between thin pools;
destination-storage selection.
```

A minimal setup is:

```text
VG A + thinpool
VG B + thinpool
```

Use unique names derived from the run token.

---

## 6. Register temporary Proxmox storages

Register each thin pool using a unique storage ID:

```sh
pvesm add lvmthin TEST_STORAGE_A --vgname TEST_VG_A --thinpool thinpool --content images
pvesm add lvmthin TEST_STORAGE_B --vgname TEST_VG_B --thinpool thinpool --content images
```

Before creation:

```text
verify the storage ID does not already exist;
verify the VG does not already exist.
```

Record:

```text
storage ID | expected VG
```

for cleanup.

---

## 7. Use high unused VMIDs, but verify them

A high range is convenient for test VMs, for example:

```text
900000–999999
```

but the range is not proof that the VMID is free.

Before using an ID, search cluster-wide for:

```text
QEMU config
LXC config
already-reserved test VMID
```

Only then reserve it for the run.

---

## 8. Give every test VM a provable name

Create names containing the test token:

```text
plvt-47920001-copy-src
plvt-47920001-copy-dst
```

Record:

```text
VMID | exact expected name
```

Cleanup should destroy a VM only if its current name still matches the recorded value.

If a human or another process changed the VM, cleanup should refuse.

---

## 9. Keep test VMs stopped

Storage-manipulation tests should use stopped VMs unless the running-guest case is specifically under test.

Advantages:

```text
consistent block contents;
no guest writes during copies;
no accidental service disruption;
simpler assertions;
cleaner rollback.
```

Running-guest behavior should be a separate dedicated test profile.

---

## 10. Create thin LVs directly when useful

For low-level tests, create a test LV directly inside the test thin pool.

Example:

```text
vm-TESTVM-disk-0
plvt-copy-TOKEN
plvt-delete-TOKEN
```

Write a small identifiable pattern to it.

This gives later copy/compare tests meaningful content without requiring a guest OS.

---

## 11. Use synthetic filesystems for mount tests

A mount test does not need a complete operating system image.

A small ext4 filesystem containing:

```text
/etc
/usr
/etc/os-release
```

is enough to exercise:

```text
filesystem detection;
direct-LV mount;
VM-slot mount;
root-role heuristics;
unmount;
empty mount-directory cleanup.
```

This keeps tests deterministic and fast.

---

## 12. Use synthetic disk images for import/export

For import testing:

```sh
qemu-img create -f raw test.raw 16M
```

is sufficient.

For export testing, export one of the test VM's small disks to a file inside the sandbox and validate it with:

```sh
qemu-img info
```

No production images are required.

---

## 13. Reuse existing infrastructure only when it is non-mutating

The network group in the Proxmox suite uses an existing Linux bridge.

That is safe because the test:

```text
does not create the bridge;
does not modify the bridge;
only points disposable test VM NICs at it.
```

If no bridge exists, the test skips.

This is a useful rule:

> Existing infrastructure may be observed or referenced when the test does not mutate it.

---

## 14. Storage aliases are useful for config-rewrite tests

To test storage-prefix rewrites safely, register a second storage ID pointing to the same test VG/thin pool.

Example:

```text
plvt-a-TOKEN
plvt-alias-TOKEN
```

Then rewrite only disposable guest configurations between those two IDs.

This exercises configuration mutation without requiring a third storage stack.

---

## 15. Fixture sizing

A practical default is:

```text
backing files: 1 GiB sparse each
thin pool:     ~768 MiB each
test LVs:      16–64 MiB
test VM RAM:   128 MiB
```

The exact numbers are less important than ensuring:

```text
enough metadata/data headroom;
small copy duration;
small temporary footprint.
```

Monitor thin-pool usage so the tests themselves cannot exhaust the pool.

---

## 16. Baseline capture on Proxmox

Before creating the test storage, capture protected state.

Useful LVM views:

```sh
vgs --noheadings -o vg_name
pvs --noheadings --separator '|' -o pv_name,vg_name
lvs --noheadings --separator '|' -o vg_name,lv_name
```

Useful Proxmox views:

```text
canonicalized /etc/pve/storage.cfg
hashes of existing QEMU/LXC config files
```

The baseline must be captured before test-owned objects exist.

---

## 17. Canonicalize `storage.cfg`

Do not compare `/etc/pve/storage.cfg` as raw bytes.

`pvesm add/remove` may reorder values such as:

```text
content images,rootdir
```

without changing meaning.

For known set-valued keys such as:

```text
content
nodes
```

split into members and sort.

Scalar options should still compare exactly.

The canonicalizer should detect:

```text
storage added/removed;
VG changed;
thin pool changed;
path changed;
content member added/removed;
node membership changed;
scalar option changed.
```

but ignore member ordering.

---

## 18. Treat `/etc/pve` as a live clustered filesystem

Proxmox configuration files live in `pmxcfs`, not an ordinary local directory.

Implications:

```text
file writes may be serialized differently;
cluster state can change concurrently;
config filenames are authoritative identities;
ordinary filesystem assumptions can be misleading.
```

Use Proxmox CLI validation where possible after direct config edits.

---

## 19. Prefer Proxmox CLI for test mutations

When the script under test uses:

```text
qm
pvesm
```

the integration test should let it do so.

Do not replace the command under test with equivalent direct LVM/config operations in the test.

The point is to prove the real interface path.

The fixture setup itself may use lower-level LVM commands where that is the cleanest way to create synthetic storage.

---

## 20. Verify operations at multiple layers

For a disk attachment, useful checks include:

```text
qm config contains the expected slot;
pvesm resolves the volume;
backing LV exists.
```

For a disk deletion:

```text
guest config reference absent;
storage listing no longer contains exact volume ID;
backing path absent;
LVM metadata absent.
```

For a move:

```text
guest slot points to destination storage;
destination LV exists;
source LV absent when delete semantics were requested.
```

Layered verification catches resolver and abstraction quirks.

---

## 21. Do not use `pvesm path` as an existence predicate

A major lesson from the integration run:

```text
pvesm path VOLID
```

may return a syntactically correct backing path even after the actual volume has been removed.

Therefore:

```text
path resolution != existence proof
```

For existence, use storage listing and backing-object checks.

---

## 22. Canonical device paths matter

LVM devices can appear as:

```text
/dev/VG/LV
/dev/mapper/...
/dev/dm-N
```

Tests involving ownership or mount state should resolve canonical paths where appropriate.

Do not assume string equality means device identity.

---

## 23. Test direct filesystems and partitioned disks separately

A useful mount matrix eventually includes:

```text
filesystem directly on LV;
GPT + multiple partitions;
MBR partition table;
unknown partition type;
swap;
LUKS;
LVM2_member;
```

The first clean suite used direct ext4 because it provides a compact happy-path fixture.

Partitioned images should be a separate expansion group.

---

## 24. Cleanup order

A safe cleanup order is:

```text
1. unmount test paths;
2. stop/destroy disposable VMs;
3. remove temporary Proxmox storage definitions;
4. remove test VGs;
5. detach loop devices;
6. remove sandbox files;
7. compare protected baseline.
```

This avoids removing storage beneath a still-referencing VM.

---

## 25. Validate ownership at every cleanup layer

Before `qm destroy`:

```text
VMID exists;
name equals recorded test name.
```

Before `pvesm remove`:

```text
storage ID exists;
its vgname equals recorded test VG.
```

Before `vgremove`:

```text
VG exists;
its only relevant PV is the recorded loop device.
```

Before `losetup -d`:

```text
recorded backing file still maps to recorded loop.
```

If any check fails:

```text
warn;
refuse that cleanup step;
leave evidence.
```

---

## 26. Backups created by scripts under test

Some commands create `/root` backups.

The harness should record the disposable VMIDs and storage IDs, then remove only backup paths whose names contain those exact test identifiers.

Do not broadly clean:

```text
/root/*before-*
/root/change-vmid-backup-*
```

because those may belong to real operator activity.

---

## 27. Cluster concurrency

A Proxmox cluster may change while tests run.

Protected-state comparison therefore serves two purposes:

```text
detect test side effects;
detect concurrent environmental changes.
```

When a baseline differs, preserve a diff and fail conservatively.

Then determine whether the change was:

```text
test-caused;
operator-caused;
cluster-caused;
serialization-only.
```

Do not automatically label every difference as a product bug.

---

## 28. Recommended lab prerequisites

Useful commands include:

```text
qm
pvesm
lvs
vgs
pvs
pvcreate
vgcreate
vgremove
lvcreate
lvremove
losetup
truncate
findmnt
mountpoint
kpartx
blkid
mkfs.ext4
qemu-img
awk
sed
grep
sort
cmp
sha256sum
```

The test launcher should verify prerequisites before creating the sandbox.

---

## 29. Recommended group structure

A practical decomposition is:

```text
00 static / CLI
10 inspection / audit
20 raw LVM
30 mount / filesystem
40 VM disk lifecycle
50 copy / snapshot
60 disk config surgery
70 storage / import / export
80 VM config / recovery
90 networking
```

Each group should create only the fixtures it needs and clean them before returning.

---

## 30. What the loopback lab validates well

This architecture is strong for:

```text
LVM mechanics;
LVM-thin mechanics;
Proxmox lvmthin storage IDs;
QEMU VM config mutations;
disk attach/detach/delete;
disk copy/move/snapshot;
mounting;
import/export;
VMID/config changes.
```

---

## 31. What needs additional dedicated environments

The basic loopback lab does not fully represent:

```text
Ceph RBD;
ZFS;
directory/qcow2 storage;
NFS/CIFS;
shared cluster storage;
HA failover;
replication;
live migration;
running-guest consistency;
LXC rootfs behavior;
multipath;
real hardware failure.
```

Those should be separate environment profiles, not forced into the basic lab.

---

## 32. Proxmox test-lab acceptance checklist

- [ ] backing block devices are loop devices created by the current run;
- [ ] backing files live inside a marked sandbox;
- [ ] VGs are unique and pre-flight checked;
- [ ] Proxmox storage IDs are unique and pre-flight checked;
- [ ] VMIDs are checked cluster-wide before use;
- [ ] every disposable VM has a recorded exact name;
- [ ] test VMs remain stopped unless running state is specifically tested;
- [ ] dry-run state is compared before real mutation;
- [ ] real operations use the actual project commands;
- [ ] postconditions are checked through Proxmox and underlying storage layers;
- [ ] cleanup re-proves ownership;
- [ ] baseline comparison occurs after cleanup;
- [ ] any anomaly fails the group and preserves a diff.

---

## 33. Guiding principle

The ideal Proxmox integration lab is disposable enough to destroy without fear, but realistic enough that the commands under test genuinely interact with the same `qm`, `pvesm`, LVM, device-mapper, filesystem, and configuration machinery used in normal administration.
