# Proxmox Test Harness Best Practices

This guide focuses on building integration tests that exercise real `qm`, `pct`, `pvesm`, LVM and device-mapper behavior without endangering existing Proxmox guests or storage.

## 1. Use real platform tools against disposable resources

Mocking is useful for parser tests, but storage helpers need real-system integration coverage because Proxmox commands can have side effects that are not obvious from CLI syntax.

Use disposable resources for real tests:

```text
sparse backing files
loop devices
test PV/VG/thin pool
test storage IDs
high unused VMIDs/CTIDs
small stopped guests
```

Do not point a destructive case at a pre-existing guest merely because the test is expected to fail.

## 2. Capture protected host state before creating fixtures

Record pre-existing:

```text
PVs/VGs/LVs
Proxmox storage semantics
guest configuration checksums
QEMU runtime status
LXC runtime status
firewall checksums
```

This protected baseline is separate from test-owned state.

## 3. Test-owned storage names must be unique per run

Generate a run token and include it in:

```text
VG names
thin pool names
storage IDs
VM names
CT hostnames
temporary paths
```

A cleanup function should never infer ownership from a broad prefix alone.

## 4. Validate storage content types

If QEMU and LXC are both tested, storage must advertise the required content classes:

```text
images
rootdir
```

A fixture that Proxmox itself considers invalid does not test the helper.

## 5. Build minimally valid QEMU and LXC fixtures

For QEMU, set the controller type deliberately when testing hotplug behavior.

For LXC, provide a valid `rootfs` before testing commands that call `pct set`.

Before handing a fixture to a project helper, prove:

```sh
qm config "$VMID" >/dev/null
pct config "$CTID" >/dev/null
pvesm path "$VOLID" >/dev/null
```

as applicable.

## 6. Keep guests stopped unless runtime state is the behavior under test

A stopped guest is safer and more deterministic.

When testing:

```text
hot
pause
stop
restart
```

use only disposable guests and record their runtime state before and after the case.

## 7. Controller topology is part of the fixture

A SCSI disk test is incomplete unless it controls:

```text
scsihw model
number of SCSI disks
target slot
whether removing the disk removes the controller
```

For a positive paused-hotplug test, use a shared controller and a second disposable keeper disk so removing one disk does not imply removing the controller.

Also include a refusal test for unsupported topology.

## 8. Separate config-reference deletion from storage deletion

Never assume:

```sh
qm set VMID --delete unused0
```

is metadata-only.

When a test expects the underlying LV to survive, verify its UUID before and after removing the config reference.

## 9. Verify identity with UUID, not just name

Names change during:

```text
VMID change
renumber
overwrite archive
rollback
```

Record LV UUIDs and prove the intended object survives each rename.

## 10. Verify bytes where data matters

For copy/move/import/export paths:

```text
cmp
sha256sum
qemu-img compare
```

should independently prove content preservation.

Configuration equality alone is not enough.

## 11. Negative tests must prove nothing changed

A refusal test should capture a complete test-owned snapshot before calling the helper and compare it after the expected failure.

Include:

```text
LV metadata
LV content samples
guest configs
guest runtime status
storage definitions
mounts
test files
```

## 12. Test Proxmox-side failure semantics

Useful negative cases include:

```text
destination VMID exists
snapshot present
shared LV reference
occupied destination slot
ambiguous disk-N
unsupported paused controller topology
invalid corrected LV name collision
wrong destructive confirmation
```

Each should fail before mutation where practical.

## 13. Cleanup must validate ownership again

Do not assume a resource is still test-owned merely because setup created it.

Before `qm destroy` or `pct destroy`, prove:

```text
exact expected test identity
all storage-backed references map only to test-owned storage/VGs
```

If that proof fails, stop cleanup at that layer.

## 14. Cleanup from the top of the dependency graph downward

Recommended order:

```text
unmount / remove mapper devices
destroy disposable guests
remove test storage definitions
remove test LVs/VGs/PVs
detach loop devices
remove sandbox/ownership record
```

A surviving upper-layer object blocks deletion of lower-layer resources it might depend on.

## 15. Treat setup aborts like test failures

The trap path must still:

```text
perform conservative cleanup
capture protected after-state
compare protected baseline
write logs
```

A fixture setup failure is exactly when evidence is most valuable.

## 16. Preserve evidence even after successful cleanup

Keep per-group result directories containing:

```text
case logs
baseline snapshots
after snapshots
anomaly diffs
fixture IDs
run token
```

The goal is to make a failure reviewable after the disposable resources are gone.

## Do not pre-run the API under test during fixture setup

If the product test is meant to evaluate a specific mutating API path, fixture setup should not depend on that same path when a safe independent fixture mechanism exists.

Bad test boundary:

```text
fixture setup -> pct set net0 ...
test case     -> project helper -> pct set net0 ...
```

If the first `pct set` fails, the helper was never tested.

Prefer:

```text
fixture setup -> seed stopped synthetic config directly
fixture check -> qm/pct config parses successfully
test case     -> project helper -> first qm/pct set mutation
```

This does not mean direct configuration editing is preferred for production helpers. It is a controlled test-fixture technique used on uniquely owned, stopped disposable guests to isolate the behavior under test.

## 17. Recommended Proxmox harness acceptance checklist

Before trusting a harness:

- [ ] Plan-only mode creates nothing.
- [ ] Real mode uses only uniquely named disposable storage.
- [ ] QEMU and LXC fixtures are valid before helpers run.
- [ ] Runtime-state tests use only disposable guests.
- [ ] Storage content classes match fixture use.
- [ ] Dry-run compares real before/after state.
- [ ] Negative tests prove exact non-mutation.
- [ ] Data-sensitive operations verify bytes independently.
- [ ] Cleanup re-validates ownership.
- [ ] Setup aborts still produce after-state evidence.
- [ ] Protected pre-existing state is compared after every group.
- [ ] Result logs survive cleanup.

> The safest Proxmox test harness is one that assumes both the product and the test harness itself can be wrong.
