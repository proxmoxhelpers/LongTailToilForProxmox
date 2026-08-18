# Proxmox LVM Tools Test Suite

Test suite version: **2.9.1**  
Project target: **3.5.1**

This suite exercises all 42 project commands on a real Proxmox node while avoiding production storage and guests.

See [`FIRST-RUN-FINDINGS-2026-08-15.md`](FIRST-RUN-FINDINGS-2026-08-15.md) and [`SECOND-RUN-FINDINGS-2026-08-15.md`](SECOND-RUN-FINDINGS-2026-08-15.md) for the analyses from the first two full integration runs.



## v2.9.1 — v3.5.1 activation-skip and network-fixture corrections

The v3.4.7 real-host run proved that a Proxmox `base-*` template LV can be inactive **and** marked activation-skip. Independent-copy tests now require `lvchange -ay -K` for temporary activation and verify the source returns inactive afterward.

The network group now creates its own registered loopback LVM-thin sandbox before creating the LXC rootfs. A static contract enforces both provisioning order and the explicit ownership assertion.

The real integration definition remains **88 cases**. v3.5.1 needs a fresh real-host run.

## v2.9.0 — v3.5.0 structural/style enforcement

The public helper scaffold is now enforced project-wide: `setup()`, `main()`, `end()`, and `usage()` must be the first four public helper functions; defaults/state initialize at the top of `setup()`; routine root-success elevation output is forbidden; and argument-taking functions must document their call syntax. Runtime behavior tests remain the v3.4.7 88-case definition.

## v2.8.5 — v3.4.7 inactive-source and network-fixture regression coverage

The third current-generation real-host run executed 83 of the 86 registered cases: 82 passed, one independent-copy case failed, and the three network cases were blocked during fixture setup. Eight of ten groups were clean and all nine integration result directories had byte-identical protected before/after snapshots.

The remaining helper defect was specific and reproducible: a template/base LV existed in LVM metadata and could be snapshotted, but was inactive, so `/dev/VG/base-VMID-disk-N` did not exist for `dd`. v3.4.7 adds activation-state preservation to raw and create-copy paths: an inactive source is activated with `lvchange -ay`, copied/verified, and restored with `lvchange -an`; already-active sources are never deactivated and LV permission metadata is never changed.

The suite now adds:
- a raw `copy-lvm.sh` inactive-source case that verifies dry-run non-activation, real copy success, content equality, and restoration to inactive state;
- a create-copy overwrite case using the same inactive `base-*` source;
- stronger assertions around the existing base/template copy-add case;
- a network fixture contract that seeds stopped disposable NIC configs independently and validates them before the project helper becomes the first caller of the `qm set`/`pct set` network mutation API.

The real integration definition is now **88 cases**.

## v2.8.4 — v3.4.6 usage/documentation/style coverage

v3.4.6 keeps the v3.4.4/v3.4.5 storage behavior and the 86-case real integration definition unchanged. The test suite adds a documentation contract requiring every public helper's `docs/<script>.sh.usage` file to match live `--help` output byte-for-byte, and requires every README helper heading to link the script, full documentation page and raw usage page.

The style/documentation inventory now also requires the project lessons-learned document and the new Proxmox/POSIX-shell destructive-test best-practice guides.

## v2.8.3 — v3.4.5 help/documentation coverage

v3.4.5 does not change the v3.4.4 storage transaction semantics or the 86-case real integration definition. It adds a documentation/help contract across all 42 public helpers.

The static suite now requires every public helper to:

- return success for `--help` without crossing its elevation/preflight gate;
- expose a `Usage` section or line in the `--help` output;
- have exactly one linked helper heading in the project README;
- have exactly one same-line `doc` link from that heading;
- have a corresponding `docs/<helper>.md` page;
- show its callable `./helper.sh --help` command on that page;
- remain present exactly once in the test matrix and standalone install inventory.

The per-helper documentation pages are generated from the public helper descriptions and the current built-in help output, then validated as normal repository artifacts.

## v2.8.2 — v3.4.4 second-real-run corrections

The v3.4.3 real-host rerun was substantially cleaner: 75 of 84 integration cases passed, 6 failed, and 3 network cases were blocked during fixture setup. Seven of ten groups were clean. Every group, including the failed/setup-aborted groups, produced protected baseline/after snapshots with zero differences.

The remaining findings were narrower:

- all three template/base create-helper cases failed because source size was obtained with `blockdev`; v3.4.4 uses authoritative `lvs --units b --nosuffix -o lv_size` metadata for all four create helpers;
- Proxmox rejected `qm set --delete scsiN` while a VM was suspended when removing a per-disk or last SCSI controller. The helpers now preflight-refuse `pause` for `virtio-scsi-single` and sole-SCSI-controller removal before any mutation, while the positive pause fixtures keep another disposable SCSI disk on a shared `virtio-scsi-pci` controller;
- the network group’s disposable LVM-thin storage supported `images` but not `rootdir`, so the config-only CT fixture could not be validated as a real LXC rootfs consumer. Test storages now advertise `images,rootdir`, and the fixture validates `pct config` and creates the initial NIC with `pct set`.

Two new refusal cases explicitly lock in safe paused-SCSI behavior for move and overwrite operations. The integration definition therefore expands from 84 to **86 cases**.

Three new static regressions require LVM-metadata source sizing, pause-detach preflight protection, and rootfs-capable LXC test storage.

## v2.8.1 — v3.4.3 first-real-run corrections

The first full v3.4.2 real-host attempt reached 54 of the 84 integration cases before setup/case failures blocked the rest. It produced 42 passing integration cases and 12 failing cases; 30 cases in the inspection, mount and copy/snapshot groups never started because fixture setup aborted. The static group remained clean.

v2.8.1 fixes the issues exposed by that run without weakening assertions:

- `partx --show --raw` is replaced by the util-linux-compatible `partx --show --noheadings` form in both the filesystem helper and partition fixtures;
- `move-disk-to-vm.sh` removes source `unusedN` references by direct config-only rewrite and uses the same safe path during rollback, never `qm set --delete unusedN`;
- the pause move fixture uses a shared `virtio-scsi-pci` controller so the test exercises a hot-unpluggable disk rather than controller removal;
- all copy/snapshot test-only `trim` calls are replaced by POSIX `awk` trimming;
- SATA/IDE bus-change tests now expect `iothread` to be removed while preserving compatible options;
- the omitted-destination bus test checks the actual first-free `scsi4` slot instead of the incorrect `scsi1`;
- the LXC network fixture now has a disposable test-owned rootfs so `pct set` is testing the helper rather than rejecting an invalid container config;
- qcow2 export verification uses `qemu-img compare` for logical contents and diagnostic format checks; raw export still uses byte comparison;
- destructive `delete-lvm.sh` cancellation is required to return non-zero;
- emergency setup-failure cleanup now captures and compares protected after-state instead of leaving baseline-only evidence.

Six new static regressions lock these exact fixes in.

## v2.8.0 — v3.4.2 full behavior and harness-safety audit

The 42-command matrix was re-audited against the actual option and transaction branches rather than treating one test per command as sufficient. High-risk groups now cover thin versus regular LV copies, wrong destructive confirmation, shared-reference refusals, direct and partitioned mounts, VM-state modes, overwrite archive-number collisions and delete paths, exact/bare/default device selectors, boot-order preservation, vm/base namespaces, strict selector ambiguity, byte-preserving storage moves/import/export, QEMU/template/LXC VMID changes, and QEMU/LXC network edits.

The harness itself was hardened at the same time:

- every mutating public helper must have a `run_dryrun_unchanged` integration reference;
- dry-run/refusal snapshots include test LV metadata, sampled LV content hashes, QEMU/LXC configs and runtime state, test storage definitions, test files and mounts;
- protected-host baselines include pre-existing VG/PV/LV metadata, guest-config checksums, local QEMU/LXC runtime status, canonical storage configuration and firewall-file checksums;
- cleanup verifies exact test guest identity **and** every storage-backed reference before any guest purge;
- cleanup fails closed by layer: remaining mounts block guest/storage cleanup, remaining guests block storage/VG cleanup, remaining storage definitions block VG/loop cleanup, and ownership records are retained if cleanup cannot prove safety;
- project backup paths that already existed before the test run are recorded and never removed by cleanup;
- disposable LXC config fixtures exercise CT paths without selecting an existing container;
- a third loopback-owned regular VG exercises the non-sparse regular-LV copy path.

Static CI now also fails if a public helper is missing from the integration groups, if a mutating helper lacks a dry-run immutability case, or if README/test-matrix command inventory drifts from the 42 public scripts.

## v2.7.0 — v3.4.1 alternate-branch merge regression coverage

The alternate-branch review added regression coverage for improvements that were stronger than the current implementation without importing the older branch wholesale.

The numbering fixture now requires active-sequence start, gap and duplicate analysis while excluding `unusedN` archives. The filesystem fixture uses `partx` partition offsets and includes both a compatible Linux-filesystem/ext4 partition and an intentionally mismatched Microsoft-basic-data/ext4 partition.

Disk configuration coverage now verifies namespace-preserving renumbering across both a current `vm-VMID-*` namespace and a stale `base-OTHERID-*` namespace, plus exact stale `vm-` and `base-` name repair. Static tests additionally require shared-volume refusal, EFI/TPM name-repair coverage, richer partition-type compatibility, and strict ambiguity rejection for managed `disk-N` selectors.

## v2.6.0 — v3.4.0 numbering/filesystem inspection coverage

Adds two read-only standalone helpers:

```text
verify-vm-disk-numbering.sh
list-all-vm-lvm-filesystems.sh
```

The inspection fixture now includes an intentionally stale managed volume name (`vm-OTHERID-disk-5`) to verify embedded-VMID and non-zero-start warnings, plus a disposable GPT-partitioned LV containing a real ext4 filesystem image. The filesystem inventory must report the partition-table hint and directly probed content format separately.

## v2.5.0 — v3.3.1 vm/base managed-volume family coverage

Adds regression and real-fixture coverage for both Proxmox managed LVM naming families:

```text
vm-VMID-disk-N
base-VMID-disk-N
```

The suite now checks VMID changes, renumbering, volume-name repair, orphan discovery, recovery, disk-number selectors, and create/copy/snapshot behavior against template/base-image naming.

## v2.4.0 — v3.3.0 create device-selector/boot coverage

The copy/snapshot integration group now exercises exact source slots, exact destination slots, bare destination bus selectors, and the `boot` keyword. It verifies the resulting attachment slot and confirms the selected slot is first in the destination VM boot order.

The static group also requires all four create helpers to expose `source-slot`, `dest-slot|dest-bus`, `first_free_bus_slot`, and `boot` behavior through their public CLI/runtime.

## v2.2.3 — v3.2.3 empty-target overwrite/add coverage

The copy/snapshot integration group now verifies both overwrite helpers when the requested destination `disk-N` does not already exist. It requires exact disk-number creation, first-free-SCSI attachment, no archive/unused entry, `delete` no-op behavior, and normal data/origin verification.

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

The integration groups do **not** select an existing disk, VG, thin pool, VM, CT, storage definition or Linux bridge for mutation. Every mutating group creates uniquely named fixtures backed by sparse loop files and records exact ownership before real operations begin.

Before mutation, the harness captures protected pre-existing VG/PV/LV metadata, canonical Proxmox storage semantics, guest-config checksums, local QEMU/LXC runtime status and firewall-file checksums. Test-owned dry-run/refusal snapshots are stronger still: they include LV metadata and sampled content hashes, QEMU/LXC configs and status, temporary storage definitions, files/non-files under the test data directory, and mounts below the sandbox. A mutating helper's dry run must leave that complete snapshot byte-for-byte unchanged.

Real tests operate only on dynamically allocated high VMIDs/CTIDs and uniquely named storage. Most guests remain stopped; state-mode tests briefly start or suspend **only disposable QEMU guests** in order to verify `hot`, `pause`, `stop` and `restart` behavior. Config-only LXC fixtures remain disposable and stopped. The network group uses an already-existing Linux bridge but never creates, modifies or removes the bridge itself.

Cleanup is deliberately fail-closed. Before a test VM/CT can be purged, its exact expected test name/hostname must still match and every storage-backed reference must still map to a storage/VG owned by that run. Cleanup proceeds in layers: unresolved test mounts stop deeper cleanup; surviving owned guests stop storage/VG cleanup; surviving storage definitions stop VG/loop cleanup; and any unresolved VG/loop leaves the ownership directory in place for manual recovery. A cleanup failure never authorizes broader deletion. Pre-existing project backup paths under `/root` are recorded before the run and are never removed as test artifacts.

A third loopback-owned regular VG is created only for the regular-LV copy test so the suite can prove that regular destinations receive full writes rather than sparse writes. Data-sensitive copy/move/import/export cases verify content independently with `cmp` or hashes.

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
| `00-static-cli.sh` | POSIX/standalone CLI, project safety contracts, harness self-tests, command/documentation coverage |
| `10-inspection.sh` | disk/LV listing, ownership/orphans/audit, numbering defects, partition-table/content verification |
| `20-lvm.sh` | thin + regular LV copy, same/cross-VG move, rename forms, confirmation-safe delete |
| `30-mount.sh` | direct and partitioned mounts, RO/RW behavior, VM-slot mount, root detection, unmount |
| `40-disk-lifecycle.sh` | attach/detach/delete/unused cleanup, shared-reference refusals, VM-to-VM moves and state modes |
| `50-copy-snapshot.sh` | add/overwrite copy/snapshot, selectors, boot, state modes, archive/delete/empty-target/template paths, wrappers |
| `60-disk-config.sh` | bus/default/first-free changes, swap, boot, replacement, renumber namespaces, naming repair and refusals |
| `70-storage-io.sh` | storage moves, bulk moves, import/export byte verification, storage-prefix rewrite |
| `80-vm-config.sh` | QEMU/template/LXC VMID changes, collision/snapshot/shared refusals, config-only clone, recovery |
| `90-network.sh` | QEMU + LXC bulk NIC changes, option preservation, tag removal, missing-guest refusal |

The command-by-command mapping and representative variant coverage are in [`TEST-MATRIX.md`](TEST-MATRIX.md).

## Requirements

Integration mode is intended for a Proxmox VE node and expects normal Proxmox/LVM utilities plus the tools used by the selected groups. The expanded v3.4.2 suite uses, among others:

```text
qm pct pvesm
lvs vgs pvs lvcreate lvremove vgcreate vgremove pvcreate
losetup truncate dd cmp sha256sum
findmnt mount mountpoint umount kpartx dmsetup
sfdisk partx blkid mkfs.ext4
qemu-img
```

A missing prerequisite causes the relevant group/test to fail or explicitly skip only where the test is intentionally conditional. The network group does not create or modify a Linux bridge; it uses an already-existing bridge and skips when no suitable bridge exists.

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
anomaly-guest-status.diff
anomaly-firewall.diff
```

An anomaly is reported separately from a test assertion because a Proxmox cluster can legitimately change concurrently. For safety, any protected-state anomaly still makes that group return nonzero and must be inspected before trusting the run.

## Important

These are real integration tests for storage-management software. The fixtures and cleanup rules are deliberately isolated, but run the full suite first on a non-production Proxmox node whenever possible.

Do not manually rename, attach production storage to, or repurpose a test VG/storage/VM/CT during a running group. Ownership changes intentionally cause cleanup to refuse the affected layer and retain evidence rather than guessing.

The last fully documented real-Proxmox integration-validated POSIX baseline is project **v3.0.1** for its then-current 36-command matrix. The expanded **v3.4.2 / suite v2.8.0** definition has stronger coverage for all 42 current helpers, but it must complete a fresh real-host run with zero failures and zero protected-state anomalies before being described as integration-validated.
