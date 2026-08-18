# Proxmox LVM Tools Test Suite

Test suite version: **2.2.2**  
Project target: **3.2.2**

This suite exercises all 40 project commands on a real Proxmox node while avoiding production storage and guests.

See [`FIRST-RUN-FINDINGS-2026-08-15.md`](FIRST-RUN-FINDINGS-2026-08-15.md) and [`SECOND-RUN-FINDINGS-2026-08-15.md`](SECOND-RUN-FINDINGS-2026-08-15.md) for the analyses from the first two full integration runs.



## v2.2.2 — v3.2.2 overwrite rollback/identity fix

The overwrite helpers now verify replacement volumes by LV UUID across renames, never use `qm --delete unusedN` during rollback, restore the displaced disk by its saved LV UUID, and refuse automatic cleanup of the replacement if rollback cannot prove a safe restoration.

The static suite rejects regression to the unsafe rollback pattern. The real copy/snapshot group remains the acceptance test for the complete transaction.

## v2.2.1 — v3.2.1 overwrite disk-number semantics

The two overwrite helpers now preserve the destination backing disk number. A destination `vm-VMID-disk-N` is first detached and renamed to the first free `vm-VMID-disk-901+`; the staged copy/snapshot is then renamed to the original `disk-N` before attachment. The optional `delete` keyword removes the archived old LV only after replacement and state restoration succeed.

The copy/snapshot integration group verifies both preservation and deletion paths for both overwrite helpers.

## v2.2.0 — v3.2.0 disk create/overwrite expansion

Project v3.2.0 adds two standalone overwrite helpers and expands both existing create-and-add helpers:

```text
create-disk-copy-and-overwrite-disk-on-vm.sh
create-disk-snapshot-and-overwrite-disk-on-vm.sh
```

The source can now be expressed as either a full LVM path or `VMID + disk-N`/slot. The two overwrite helpers accept the destination as either a full LVM path or `VMID + disk-N`/slot, preserve the displaced destination volume as `unusedN`, and support hot/pause/stop/restart destination-state modes.

The existing copy/snapshot-and-add helpers now accept the same flexible source syntax, optional destination backing disk numbers, and hot/pause/stop/restart source-state modes.

The `50-copy-snapshot.sh` group adds real disposable tests for both overwrite helpers in addition to the existing copy/snapshot cases.

## v2.1.0 — v3.1.0 long-tail additions

Project v3.1.0 adds two standalone helpers and expands the integration matrix to **38 commands**:

```text
list-all-vm-lvm.sh
move-disk-to-vm.sh
```

The inspection group verifies that referenced LVM volumes are grouped under their VMIDs and that an intentionally orphaned LV appears in the remaining-volume section.

The disk-lifecycle group exercises both `move-disk-to-vm.sh` CLI forms against disposable LVM-thin volumes and covers all four source-state behaviors:

```text
default hot-swap
pause -> suspend/detach/resume
stop -> stop/detach/leave stopped
restart -> stop/detach/start
```

Every mutating path is dry-run checked first and the group still compares protected host state after cleanup.

## v2.0.1 — v3.0.1 set -e regression fixes

The first real Proxmox v3.0.0 run completed **6/10 groups**, with **30/36 integration cases passing** and **0 protected-state anomalies**.

The six failing cases were traced to one POSIX `set -e` control-flow class:

```text
rename-lvm.sh
unmount-vm-drives.sh
mount-vm-disk.sh        (cascade from unmount cleanup)
mount-vm-root.sh        (cascade from unmount cleanup)
renumber-vm-disks.sh
recover-vm-from-volumes.sh
```

Several negative probes had been written as `probe && die ...`. When such an AND-list was the final command of a function, the expected false result of `probe` became the function's return status and `set -e` terminated the script.

v2.0.1 converts those probes to explicit `if ...; then die ...; fi` blocks, adds explicit successful returns to affected validators, hardens boot-order iteration, and adds a static regression forbidding `&& die` in project shell source.

## v2.0.2 — standalone helper contract

Every top-level project command is now a self-contained single file. The static group copies each helper into an otherwise empty directory and requires both `--help` and `--version` to work there. It also rejects runtime sourcing of `lib/common.sh` / `lib/dryrun.sh`, `SCRIPT_DIR` repository coupling, and the old external companion-script dispatcher.

The repository `lib/` directory remains only as the canonical maintenance source for the embedded shared runtime.

## v2.0.0 — v3 POSIX migration

The test harness remains POSIX shell and now targets project v3.0.0.

The static group was deliberately separated from the Proxmox/LVM fixture lifecycle so it can run on an ordinary development host:

```sh
./tests/groups/00-static-cli.sh --run
```

It now verifies:

```text
all 36 command entry points parse with /bin/sh
canonical maintenance libraries parse with /bin/sh
every command entry point declares #!/bin/sh
known prohibited Bash constructs are absent
all --help paths work before privilege/environment preflight
all --version paths report project 3.0.0
dryrun placement before/after --version works for all commands
the v2 helper/test-runner regressions remain fixed under /bin/sh
```

The nine real integration groups retain the same disposable Proxmox fixture architecture and the same 36-command coverage matrix. A v3 package should not be considered integration-validated until those groups are rerun on Proxmox and finish with zero failures and zero protected-state anomalies.

## v1.0.2 runner corrections

The second Proxmox run showed that semantic storage comparison still needed one more normalization layer. Proxmox may reorder comma-separated set-valued fields such as `content` and `nodes` when `pvesm` rewrites `storage.cfg`.

The comparator now emits one canonical record per set member before sorting. Reordering `images,rootdir` to `rootdir,images`, for example, no longer counts as an anomaly, while adding/removing a member still does.

A static regression test covers this behavior.

## v1.0.1 runner corrections

The first real Proxmox run exposed two harness issues that are corrected here:

- each test case now executes in its own `set -e` subshell, so a failed project command is the actual case failure and cannot be hidden by a later assertion;
- protected storage configuration is compared semantically rather than by raw file checksum, because `pvesm add/remove` can harmlessly rewrite ordering/formatting in `storage.cfg`.

The test cases no longer depend on shell variables created by earlier cases; persistent fixture state is either prepared before the cases or re-discovered from Proxmox.

## Test-system design documentation

The reusable design lessons behind this suite are documented in [`../docs/testing/`](../docs/testing/README.md). Those guides explain the isolation model, loopback-backed Proxmox lab, shell-runner implementation patterns, semantic baseline comparison, evidence handling, and regression workflow used to reach the clean v2.2.2 reference integration pass and the v3 POSIX migration.

## Safety model

The integration groups do **not** select an existing disk, VG, thin pool, VM, CT, or storage for mutation.

For each mutating group the harness:

1. captures pre-existing VG/PV/LV identities, guest-config checksums, and a canonical semantic representation of `storage.cfg`;
2. creates two sparse loopback image files under `/var/tmp`;
3. associates only those files with new loop devices;
4. creates uniquely named test PVs, VGs and thin pools on those loop devices;
5. registers uniquely named Proxmox LVM-thin storage IDs;
6. dynamically chooses unused high VMIDs and creates stopped, test-named VMs only as needed;
7. runs every mutating project command with `dryrun` first;
8. snapshots all test-owned state before and after the dry run and requires exact equality;
9. runs the real operation only against disposable fixtures;
10. verifies the expected result;
11. re-validates ownership before every cleanup action;
12. compares protected state after cleanup and writes anomaly diffs if anything changed unexpectedly.

Cleanup refuses to remove a VM whose name no longer matches the exact expected test name, a storage whose `vgname` no longer matches the recorded test VG, or a VG whose PV is no longer the recorded loop device.

A test failure therefore does **not** authorize broader cleanup.

## Default behavior

Every launcher defaults to plan-only mode:

```sh
./tests/run-all-tests.sh
./tests/groups/20-lvm.sh
```

No sandbox is created without the explicit:

```text
--run
```

## Run all groups

```sh
./tests/run-all-tests.sh --run
```

Verbose passing logs:

```sh
./tests/run-all-tests.sh --run --verbose
```

The all-groups launcher intentionally has no `--keep` option. Each group cleans up before the next group starts.

## Run one group

```sh
./tests/groups/20-lvm.sh --run
```

A single group may retain its sandbox for manual inspection:

```sh
./tests/groups/20-lvm.sh --run --keep
```

`--keep` is intentionally limited to individual group launchers. The retained path and ownership marker are printed at the end.

## Groups

| Launcher | Area |
|---|---|
| `00-static-cli.sh` | syntax, version, dryrun keyword parsing, documentation |
| `10-inspection.sh` | disk listing, ownership, orphan discovery, storage audit |
| `20-lvm.sh` | raw LV copy, move, rename, delete |
| `30-mount.sh` | direct LV mount/unmount, VM-slot mount, root detection |
| `40-disk-lifecycle.sh` | attach, detach, delete, unused cleanup |
| `50-copy-snapshot.sh` | VM disk copy/snapshot/clone helpers |
| `60-disk-config.sh` | bus, swap, boot, replacement, renumber, naming repair |
| `70-storage-io.sh` | storage moves, import/export, storage-prefix rewrite |
| `80-vm-config.sh` | VMID change, config-only clone, recovery |
| `90-network.sh` | bulk VM network config |

## Requirements

Integration mode is intended for a Proxmox VE node and expects the normal Proxmox/LVM utilities plus tools required by the commands under test. Examples include:

```text
qm pvesm lvs vgs pvs lvcreate lvremove vgcreate vgremove pvcreate
losetup truncate findmnt mountpoint kpartx blkid qemu-img mkfs.ext4
```

A missing prerequisite causes the relevant group/test to fail or explicitly skip where appropriate.

The network group does not create or modify a Linux bridge. It uses an already-existing bridge and skips its single integration case if no bridge exists.

## Results

Logs are written below:

```text
/var/tmp/proxmox-lvm-tools-test-results/
```

Each run receives a unique directory.

Protected-state differences are written as:

```text
anomaly-vgs.diff
anomaly-pvs.diff
anomaly-lvs.diff
anomaly-storage.diff
anomaly-guests.diff
```

An anomaly is reported separately from a test assertion because a Proxmox cluster can legitimately change concurrently. For safety, any protected-state anomaly still makes that group return nonzero and must be inspected before trusting the run.

## Important

These are integration tests for storage-management software. The fixture design is deliberately isolated, but run them first on a non-production Proxmox node whenever possible.

Never manually rename a test VG/storage/VM during a running test. Ownership changes intentionally cause cleanup to refuse the affected object.
