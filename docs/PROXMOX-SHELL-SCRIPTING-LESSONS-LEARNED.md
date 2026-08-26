# Proxmox and Shell Scripting Lessons Learned

This document captures lessons learned while developing and real-host testing the LongTailToilForProxmox helpers. These are not abstract style preferences; most came from a real failure, rollback problem, fixture defect, or portability issue found during integration testing.

## 1. Proxmox configuration deletion can also delete storage

A command that looks like "remove this config key" may have storage side effects.

The clearest example was:

```sh
qm set "$VMID" --delete unused0
```

When `unused0` referenced an LVM-backed Proxmox volume, Proxmox could free the backing LV. That made this sequence dangerous:

```text
detach source disk
attach same LV to another VM
delete source unusedN key
```

The final step could destroy the LV that had just been attached to the destination VM.

**Lesson:** distinguish "remove a configuration reference" from "delete/free the referenced storage object". When the storage must survive, use a narrowly scoped config-only update and then independently verify that the LV UUID still exists.

## 2. A path is not a durable identity across rename

After `lvrename`, the old path is stale by definition. Code that saves:

```text
/dev/VG/old-name
```

and later compares storage resolution against that path can falsely conclude that a successful rename failed.

**Lesson:** capture LV UUID before rename and use UUID as the durable identity. Names and paths are labels; UUID is identity.

For multi-step transactions, save both:

```text
original VG/LV name
LV UUID
```

Use the name to describe the intended state and the UUID to prove which LV survived.

## 3. Rollback must not use a destructive primitive to repair metadata

A rollback path once tried to remove a stale `unusedN` entry with `qm set --delete`. That "cleanup" deleted the archived LV before it could be renamed back.

**Lesson:** rollback primitives must be at least as conservative as forward-path primitives. Never use a command during rollback unless its storage side effects are understood.

A good rollback sequence is:

```text
identify old LV by UUID
make sure replacement is not the only recoverable copy
restore old LV name
restore old config reference
then remove stale metadata without freeing storage
```

## 4. `set -e` and shell short-circuit expressions are a trap

This looked compact:

```sh
lvs "$TARGET" >/dev/null 2>&1 && die "Target already exists."
```

Inside a function under `set -e`, a false `lvs` status can become the function's return status and terminate the script before the intended code continues.

**Lesson:** do not use `cmd && die` as a guard under `set -e`. Prefer:

```sh
if lvs "$TARGET" >/dev/null 2>&1; then die "Target already exists."; fi
```

Also end helper functions explicitly when an empty/false result is valid.

## 5. User cancellation must have an explicit exit-status contract

A destructive helper once printed:

```text
Cancelled.
```

but exited `0`. A human could tell the operation was cancelled; automation interpreted it as success.

**Lesson:** cancellation of a requested destructive action is not successful completion. Return non-zero unless the command explicitly defines cancellation as success.

## 6. Do not assume every valid LVM LV behaves like an ordinary active block device

Template/base LVs exposed a source-size bug when code used:

```sh
blockdev --getsize64 "$SOURCE"
```

The LV was valid in LVM metadata but the block-device query was not reliable for that state.

**Lesson:** use the subsystem that owns the metadata. For an LVM LV size, prefer:

```sh
lvs --noheadings --units b --nosuffix -o lv_size "$SOURCE"
```

Use `blockdev` when probing an active block-device interface, not as the authoritative LVM metadata source.

## 7. `vm-VMID-disk-N` is not the only managed LVM naming family

Templates and base images use:

```text
base-VMID-disk-N
```

Several helpers originally assumed only:

```text
vm-VMID-disk-N
```

That caused stale names, skipped volumes, and incorrect selector behavior.

**Lesson:** discovery of an existing managed Proxmox LV must understand both families. Renames should preserve the family unless the operation explicitly converts the object's role.

## 8. Embedded VMID and owning VMID can legitimately disagree

A moved or historically renamed VM can reference:

```text
VM 199 -> base-100-disk-1
```

That is inconsistent naming, but still real state.

**Lesson:** selectors should resolve configured reality first, refuse ambiguity, and avoid guessing. Repair helpers may normalize the name afterward, preserving the `vm-`/`base-` family.

## 9. Numeric disk selectors must reject ambiguity

If a guest config contains two managed volumes whose names both end in:

```text
disk-1
```

a selector such as:

```text
199 disk-1
```

is ambiguous even if one of those names embeds VMID 199 and the other embeds an old VMID.

**Lesson:** configuration truth beats naming preference. If more than one configured disk matches, require an explicit slot such as `scsi0`.

## 10. VM device options are bus-specific

Moving a disk from SCSI to SATA while blindly preserving:

```text
iothread=1
```

caused Proxmox schema validation to fail.

**Lesson:** preserve options semantically, not mechanically. Before applying an existing disk value to a new bus, remove or transform options the destination bus does not support, and warn the user.

## 11. Paused VM hot-unplug depends on controller topology

Suspending a VM does not guarantee that a disk can be removed. On real Proxmox, removing the only SCSI disk from a suspended VM could trigger removal of the SCSI controller:

```text
hotplug problem - error on hot-unplugging device 'scsihw0'
```

or:

```text
virtioscsi0
```

**Lesson:** `pause` is not equivalent to `stop`. Preflight must consider:

```text
SCSI controller type
whether the selected disk is the only SCSI disk
whether removing it implies removing the controller
```

If the topology cannot support safe hot-unplug, refuse before mutation and recommend `stop` or `restart`.

## 12. Never bypass Proxmox runtime safety with a direct config edit

When a paused hot-unplug fails, it may be tempting to edit `/etc/pve/qemu-server/VMID.conf` directly and pretend the device was removed.

That can leave QEMU still using the disk while another VM is given the same writable LV.

**Lesson:** direct config editing is not a substitute for runtime device removal. If Proxmox refuses a live transition, either use a supported state transition or fail safely.

## 13. Sparse copy is safe only when skipped blocks are guaranteed zero

For a newly created thin LV, `conv=sparse` is reasonable because unwritten extents read as zero.

For a regular LV, skipped zero blocks can reveal pre-existing underlying data.

**Lesson:** thin and regular destinations require different copy behavior. Regular LVs receive full writes.

## 14. Thin-pool warnings must be filtered narrowly

LVM emits repetitive thin-pool advisories that can obscure useful output. Suppressing all stderr would also suppress real failures.

**Lesson:** filter only specific known advisory text and preserve:

```text
unrelated warnings
real error text
the wrapped command exit status
```

## 15. `partx` option combinations differ from intuitive expectations

A read-only probe used:

```sh
partx --show --raw ...
```

On the real host, `--show` and `--raw` were mutually exclusive.

**Lesson:** external command syntax must be integration-tested on the target platform. A command can parse in shell and still be invalid for the installed utility version.

Use the smallest option set necessary for the desired output.

## 16. Partition-table type and actual filesystem are different facts

GPT/MBR metadata describes partition intent, not necessarily the filesystem currently present.

For example:

```text
table: Microsoft basic data
content: ext4
```

is a meaningful mismatch.

**Lesson:** report table metadata and content signatures separately. Do not collapse them into one "format" field.

## 17. Read-only inspection should not create mappings or mounts unless necessary

Partition inventory can often be performed with offset-based probing:

```text
partx -> partition start/size/type
blkid -p -O/-S -> actual content signature
```

**Lesson:** inspection helpers should default to operations that leave no mapper devices, mounts, or cleanup burden.

## 18. LXC fixtures must be valid LXC configurations

A network test created an LXC config with no `rootfs`, then `pct set` failed with:

```text
missing 'rootfs' configuration
```

The project helper had not yet been meaningfully tested.

**Lesson:** a synthetic fixture must satisfy the platform's minimum validity rules before it is used to judge product behavior.

## 19. Test storage capabilities must match fixture use

An LVM-thin test storage declared only:

```text
content images
```

but was later used for LXC rootfs fixtures.

**Lesson:** fixture storage definitions must advertise every content type the tests will actually use, such as:

```text
images,rootdir
```

## 20. A test failure can be a product defect, a fixture defect, or both

Examples from development:

```text
move-disk-to-vm deleting the LV       -> product defect
partx --show --raw                     -> product + fixture defect
undefined trim in test group           -> harness defect
invalid LXC without rootfs              -> fixture defect
wrong expected first-free SCSI slot     -> assertion defect
```

**Lesson:** classify failures before changing assertions. Do not "fix" a test by weakening it until it goes green.

## 21. Dry-run must verify non-mutation, not merely print `[DRYRUN]`

A dry-run can accidentally:

```text
stop a VM
write bytes to an LV
create a mount
change a config
```

even if its mutation wrapper prints dry-run messages elsewhere.

**Lesson:** capture before/after test-owned state including runtime status and content samples and compare it exactly.

## 22. Protected-state snapshots must include runtime state

Comparing only config files would miss an accidental:

```text
qm stop
qm suspend
pct stop
```

**Lesson:** protected baseline evidence should include guest runtime status as well as configuration and storage metadata.

## 23. Emergency exits still need protected-state comparison

Early fixture setup failures originally cleaned up through a trap but did not always capture the after-state baseline.

**Lesson:** setup-abort and ordinary test completion should converge on the same evidence path:

```text
cleanup
capture protected after-state
compare
retain logs
```

## 24. Cleanup must fail closed by dependency layer

A cleanup routine should not continue deleting lower layers after it loses confidence in an upper layer.

Safe ordering:

```text
mounts
guest configs
storage definitions
LV/VG/PV
loop devices
ownership directory
```

If a guest cannot be proven test-owned, do not remove the storage under it.

## 25. Ownership must be recorded when the resource is created

Names are not enough. A test VMID or storage name can be reused or modified unexpectedly.

**Lesson:** record ownership immediately and validate exact identity before cleanup:

```text
expected guest name/hostname
expected test storage mapping
expected VG
expected loop device
```

## 26. Do not remove pre-existing backup paths during cleanup

Tests that exercise backup-producing helpers may write below `/root`.

**Lesson:** record whether a backup path existed before the test run. Cleanup may remove only artifacts proven to have been created by that run.

## 27. Export tests should compare logical contents, not container bytes

A qcow2 export is not byte-identical to the source block device because qcow2 is a container format.

**Lesson:** verify:

```text
qemu-img info       -> expected container format
qemu-img compare    -> logical disk contents
cmp                 -> raw export byte equality
```

## 28. First-free slot assertions must derive from the fixture

A test expected `scsi1` even though `scsi0..scsi3` were occupied and the actual first free slot was `scsi4`.

**Lesson:** assertions should either derive the expected slot from fixture state or construct the fixture so the intended result is unambiguous.

## 29. Help is part of the API

A system helper's safest entry point is often:

```sh
./helper.sh --help
```

It must work without root and without requiring Proxmox resources to exist.

**Lesson:** parse `--help` and `--version` before privilege gates and operational preflight. Keep usage text accurate enough to be treated as a stable public interface.

## 30. Convert every real-host defect into a regression test

Static checks alone did not reveal many of these issues.

**Lesson:** every defect should leave behind at least one of:

```text
static source contract
negative/refusal integration case
real success-path integration case
harness self-test
documentation/style rule
```

The project gets safer when a bug becomes institutional memory rather than a one-time patch.

## 31. LVM metadata existence does not imply an active block-device node

A real template/base copy test reached correct LVM metadata and size discovery, then failed at:

```text
dd: failed to open '/dev/VG/base-VMID-disk-N': No such file or directory
```

The `base-*` LV existed and could be snapshotted, but its block device was inactive.

**Lesson:** distinguish:

```text
LV exists in LVM metadata
LV is active in device-mapper
/dev/VG/LV block-device node exists
```

For a block copy, an inactive source may be temporarily activated with `lvchange -ay`, copied and verified, then returned to inactive with `lvchange -an`. Record whether the helper performed the activation so an already-active source is never deactivated accidentally.

Do **not** add `-p r`/`--permission r` merely to activate a template LV; that changes LV metadata. Activation-state restoration and permission-state preservation are separate responsibilities.

## 32. Fixture setup should not pre-run the API being tested

A network group repeatedly aborted during fixture setup before any registered test case ran because setup itself used `qm set` / `pct set` to build the initial NIC state.

Even when that setup call is "just preparation", a failure there prevents the project helper from being evaluated and often yields poor diagnostics.

**Lesson:** when practical, construct a stopped synthetic fixture using the narrowest independent mechanism, validate that fixture, and reserve the API under test for the registered case.

For example:

```text
seed a stopped disposable config
qm config / pct config -> prove it parses
run project helper       -> first actual qm set / pct set network mutation
```

This gives failures the correct classification and log boundary.

## Guiding principle

For Proxmox storage automation, treat every name, config key, CLI flag and state transition as potentially carrying more semantics than it appears to.

> Discover with the platform, identify with durable metadata, mutate narrowly, verify independently, and make rollback more conservative than the forward path.

## 33. A "complete VM backup" is a claim that must be testable

A native backup can still omit state by policy: excluded disks, unused volumes,
external media and host resources may live outside the payload.

**Lesson:** exact export should inventory those classes before backup and
refuse when the resulting file would not be self-sufficient. A visible refusal
is safer than a successful partial archive bearing an "exact" label.

## 34. Virtual exactness is different from physical storage identity

Restoring a VM to another host can reproduce the VMID, guest configuration,
firewall configuration and every guest-visible disk byte while necessarily
creating new LV UUIDs, allocation extents and device-mapper identities.

**Lesson:** document the exactness boundary. Verify guest-visible content and
configuration, but do not promise backend metadata that cannot or should not
survive a portable restore.

## 35. Hash the guest-visible disk, not merely an image container

Two qcow2 files can represent identical virtual disks with different container
bytes, metadata layout or allocation.

**Lesson:** when proving portable VM-disk identity, hash the logical block
content. For a regular image file, normalize it through a read-only conversion
to raw (or an equivalent logical-content reader) before comparing with the
restored block device.

## 36. Cluster policy should not hitchhike into a guest restore

ACLs, HA membership, pools and replication jobs affect cluster-wide objects and
may reference nodes, users or resources that do not exist on the destination.

**Lesson:** archive relevant lines as audit evidence if useful, but do not
silently replay them as part of "restore the VM." Reapplying external policy
deserves its own explicit, independently validated workflow.

## 37. Verify a remote transfer before running restore logic

`scp` returning zero proves the copy command succeeded; it does not prove the
destination file is the exact file selected locally.

**Lesson:** compute the complete archive SHA-256 locally and remotely, compare
them, and only then execute restore. On failure retain the remote archive and
journal/evidence instead of deleting the clues.

## 38. High-level automation increases the importance of refusal

A composed operation can amplify one bad assumption across every disk in a VM.

**Lesson:** bulk migration, cloning and rebuild helpers should plan the whole
operation before mutation, use stopped guests by default where topology changes
span multiple devices, and retain completed resources when rollback cannot be
proved.

## 39. Testing new primitives and workflows requires different evidence

A primitive can often be proven with one exact before/after assertion. A
workflow needs evidence at each boundary: source identity, planned destination,
intermediate resource, config transition, final identity, data equality and
cleanup/rollback state.

**Lesson:** organize integration groups by risk domain and make every mutating
public helper pass an exact-state dry-run case in addition to representative
real success/refusal coverage.

## 40. Containment is not equality when verifying mounts

A mount/unmount workflow initially verified success with `findmnt --target PATH`.
After the guest filesystem had been unmounted, that lookup could still succeed
because it returned the host filesystem *containing* `PATH`.

**Lesson:** use an exact mountpoint predicate such as `findmnt -M PATH` when the
postcondition is "this path itself is or is not a mountpoint." More generally,
verify the exact relationship you intend rather than a broader containment or
resolution relationship.

## 41. Archive integrity is not archive authenticity

A portable `.ltvm` archive can checksum every member and still be malicious if
an attacker intentionally created the archive and its checksum list together.

**Lesson:** validate archive paths/types/checksums before extraction or execution,
but also treat the file as trusted input. SHA-256 proves accidental/tamper
integrity relative to the included manifest; it is not a signature and does not
identify who produced the archive.

Reject before extraction:

```text
absolute/traversal paths
duplicate members
symlinks and hardlinks
devices and FIFOs
unchecked regular files
invalid or duplicate checksum paths
```

## 42. Journal a mutation before verifying the mutation

A multi-step repair originally recorded a completed LV rename only after its
post-rename verification. If the rename succeeded but verification itself
failed, rollback did not yet know that the rename had happened.

**Lesson:** once a mutating command returns success, immediately record the
durable identity needed to undo it, then run verification. The rollback journal
must describe reality even when the next assertion is the thing that fails.

For rename-heavy storage work, LV UUID is more durable than the current LV name.

## 43. Inactive source handling belongs in composed workflows too

Fixing inactive `base-*` copies in a low-level copy helper is not enough. A
higher-level storage-clone workflow can eventually reach the same inactive LV
through `pvesm path` and hand a nonexistent `/dev/VG/LV` node to another tool.

**Lesson:** every block-reading workflow must independently preserve the source
activation contract:

```text
discover size/identity from LVM metadata;
remember whether the source was inactive;
activate temporarily with activation-skip override only when required;
perform the read/copy;
restore inactivity on success, failure and signal cleanup;
never change LV permission metadata merely to make it readable.
```


## 44. A green documentation test can still be too weak

A source-documentation check that merely looks backward for *some* comment can
mistake a section banner for a function comment. Likewise, a check that only
searches for `Call:` somewhere in the accumulated comment buffer can give a
false pass when the line belongs to another function.

The stronger contract is structural:

```text
function-named header
Call:/Usage: syntax when positional arguments are consumed
descriptive line explaining behavior or invariant
function definition
```

Static checks should delimit the immediately preceding comment block and handle
both brace-bodied and subshell-bodied POSIX functions.

## 45. Exact help snapshots can preserve stale help perfectly

A byte-identical `.usage` snapshot proves synchronization, not completeness. If
the live help says only `Usage: ...`, the snapshot can be perfectly current and
still omit the script version, description, safety semantics, or common options.

Test both dimensions:

1. **content contract** — help contains the required public-interface sections;
2. **synchronization contract** — snapshots and helper docs embed that exact help.

This is why v3.6.1 tests `USAGE`, `DESCRIPTION`, common options, project/version
identity, raw `.usage` equality, and per-helper documentation embedding
separately.

## Guiding principle

For Proxmox storage automation, treat every name, config key, CLI flag and state transition as potentially carrying more semantics than it appears to.

> Discover with the platform, identify with durable metadata, mutate narrowly, verify independently, and make rollback more conservative than the forward path.
