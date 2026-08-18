# Changelog

## 3.4.4 — 2026-08-17

Second real-Proxmox integration-run corrections.

- The v3.4.3 real-host rerun passed 75 of 84 integration cases, with 6 case failures and 3 network cases blocked during fixture setup; all nine groups produced protected before/after snapshots with zero differences.
- All four create helpers now obtain managed source LV size from `lvs --units b --nosuffix -o lv_size` instead of `blockdev`, allowing template/base LVs to pass preflight reliably.
- `move-disk-to-vm.sh` and both overwrite helpers now preflight-refuse `pause` for `virtio-scsi-single` and sole-SCSI-controller removal on a running VM, because real Proxmox rejects that controller hot-unplug while suspended.
- Positive pause integration fixtures now keep a second disposable SCSI disk on a shared `virtio-scsi-pci` controller; two additional refusal cases verify the unsafe topology is rejected before mutation.
- Disposable LVM-thin test storages now advertise `images,rootdir`, and the network CT fixture validates its rootfs/config and initial NIC through `pct`.
- The integration definition expands from 84 to 86 cases.
- Added static regressions for LVM-metadata source sizing, pause-detach topology preflight, and rootfs-capable LXC test storage.
- README and test documentation now record the v3.4.3 real-host result and the remaining validation boundary for v3.4.4.

## 3.4.3 — 2026-08-17

Corrections from the first expanded v3.4.2 real-Proxmox integration attempt.

- Fixed a high-severity `move-disk-to-vm.sh` bug where `qm set --delete unusedN` could free the LV after it had been attached to the destination VM. Source-unused cleanup and rollback now remove only the exact config reference and re-verify that the LV still exists.
- Replaced invalid `partx --show --raw` calls with util-linux-compatible read-only `partx --show --noheadings` usage in the filesystem inspector and integration fixtures.
- Changed `delete-lvm.sh` cancellation to exit non-zero so a refused destructive operation cannot look like successful deletion to automation.
- `change-disk-bus.sh` now removes incompatible `iothread` when moving to SATA/IDE, warns explicitly, and verifies the destination-compatible value.
- Fixed the disk-bus default-slot test to expect the actual first-free `scsi4` fixture slot instead of `scsi1`.
- Removed undefined `trim` calls from the copy/snapshot integration group.
- Gave the LXC network fixture a disposable test-owned rootfs so `pct set` runs against a valid stopped container.
- Reworked qcow2 export verification to use `qemu-img compare` for logical contents and clearer diagnostic format assertions.
- Improved pause-move fixture topology with `virtio-scsi-pci` so the positive pause path tests a hot-unpluggable disk rather than attempting to remove a per-disk SCSI controller.
- Emergency setup failures now run cleanup and protected after-state comparison, producing anomaly evidence even when a group aborts before registered cases begin.
- Added six static regressions for the exact real-host failures above.
- The first v3.4.2 run left all captured protected baseline/after states unchanged for groups that reached normal finish; v3.4.3 still requires a full real-host rerun before promotion.

## 3.4.2 — 2026-08-17

Full behavior-coverage and integration-harness safety audit.

- Re-audited all 42 public helpers against their actual option/state/destructive branches instead of treating one case per command as complete coverage.
- Expanded the real integration definition to 84 cases across the nine Proxmox groups.
- Added thin and regular LV copy coverage, byte/content verification, wrong-confirmation and shared-reference refusals, partitioned mount paths, QEMU state-mode transitions, overwrite archive-number collision/delete/empty-target cases, selector/boot variants, QEMU/template/LXC VMID paths, and QEMU/LXC network variants.
- Every mutating public helper is now statically required to have a `run_dryrun_unchanged` integration case; every public helper must have a non-static integration reference.
- Dry-run/refusal snapshots now include disposable LV metadata/content samples, QEMU/LXC config and runtime status, test storage definitions, files and mounts.
- Protected-host baselines now include local QEMU/LXC runtime status and firewall-file checksums in addition to VG/PV/LV, storage and guest-config state.
- Cleanup now validates exact QEMU/LXC identity and every storage-backed reference before purge, protects pre-existing backup paths, and fails closed between mount, guest, storage and VG/loop cleanup layers.
- Added config-only disposable LXC fixtures for CT-specific VMID/network paths and a loopback-owned regular VG for the non-sparse regular-LV copy path.
- Added a static documentation-coverage invariant requiring all 42 public scripts to appear exactly once in the README helper inventory/download lines and test matrix.
- Updated README/testing documentation to distinguish the last fully real-host validated v3.0.1 baseline from the broader v3.4.2 release-candidate suite.

## 3.4.1 — 2026-08-17

Selective merge of stronger logic from an alternate 3.2.0 development branch without regressing the newer 3.4.x feature set.

- `verify-vm-disk-numbering.sh` now detects active `disk-N` gaps and duplicates in addition to non-zero starts, while continuing to exclude `unusedN` archive disks from sequence analysis.
- `list-all-vm-lvm-filesystems.sh` now uses read-only `partx --show` partition metadata, a richer GPT/MBR intent table and broader filesystem/container compatibility rules, while retaining inspection of remaining/unreferenced LVs.
- `renumber-vm-disks.sh` now renumbers each prefix + embedded-VMID namespace independently, so configured stale names such as `base-100-disk-*` are not skipped; the shared-volume ownership guard was also restored.
- `fix-vm-volume-names.sh` again includes `efidiskN` and `tpmstateN`, preserves the exact managed `disk-N`, refuses corrected-name collisions, and keys planned-name collision checks by VG + LV name.
- `change-vmid-of-vm.sh` warns about configured managed volumes whose embedded VMID differs from the source VMID and leaves those foreign names untouched for explicit repair.
- Numeric managed `disk-N` selectors in `move-disk-to-vm.sh` and all four create helpers now refuse any configured ambiguity instead of giving a current-VMID name silent precedence over a stale `vm-/base-` match.
- Regenerated affected standalone wrapper payloads and expanded static/integration fixtures for the merged behavior.
- Intentionally retained the newer 3.4.x overwrite transactions, slot/bus selectors, `boot`, empty-target behavior, UUID-safe rollback and template-aware destination naming.

## 3.4.0 — 2026-08-17

Read-only VM/LVM numbering and filesystem inspection.

- Added `verify-vm-disk-numbering.sh`, grouping guest LVM volumes by VMID and highlighting managed `vm-/base-` volumes whose embedded VMID does not match the referencing guest.
- The numbering verifier flags guests whose active managed disk-number set does not start at `disk-0`; `unusedN` archive entries are displayed but excluded from the start-at-zero decision.
- Added `list-all-vm-lvm-filesystems.sh`, which inventories every guest-referenced LV and all remaining LVs without mounting or creating partition mappings.
- Partition metadata and actual content are reported separately: GPT/MBR partition types become `TABLE_HINT`, while `blkid` probes the exact partition byte range for `CONTENT_FORMAT`.
- Added stable terminal colors for FAT/vfat/exFAT, NTFS, ext-family, Btrfs, XFS, LVM, ZFS, LUKS and other detected content.
- Definite partition-type/content conflicts receive a red `MISMATCH` note; broad/unknown table types are not treated as false mismatches.
- Expanded the inspection integration group with a deliberate VMID/disk-number mismatch and a real GPT + ext4 disposable fixture.
- Expanded the project to 42 standalone helpers.

## 3.3.1 — 2026-08-17

Managed Proxmox LVM naming support for both VM and template/base volumes.

- Audited all 40 helpers for assumptions that managed LVs are only named `vm-VMID-disk-N`.
- `change-vmid-of-vm.sh` now renames both `vm-*` and `base-*` volumes while preserving their family.
- `renumber-vm-disks.sh` renumbers `vm-*` and `base-*` families independently.
- `fix-vm-volume-names.sh` preserves `vm-`/`base-`, including stale embedded VMIDs such as `base-100-disk-1` referenced by VMID 199.
- `find-orphaned-volumes.sh` now includes unreferenced `base-VMID-disk-N` volumes.
- `recover-vm-from-volumes.sh` discovers both managed naming families.
- Numeric disk selectors in `move-disk-to-vm.sh` and the four create helpers now recognize both families and can fall back to a stale embedded VMID only when the configured match is unambiguous.
- Create-and-add helpers use `base-DEST-disk-N` for template destinations and `vm-DEST-disk-N` for normal VMs.
- Overwrite helpers preserve the existing target family; empty template targets use `base-`.
- Regenerated standalone wrapper payloads so no top-level helper regressed to an external runtime dependency.
- Added template/base integration fixtures covering inspection, VMID change, renumbering, name repair, recovery, numeric selectors, copy, snapshot and overwrite behavior.

## 3.3.0 — 2026-08-17

Create-helper device selectors and boot-order promotion.

- All four `create-disk-*` helpers accept exact source VM disk slots such as `sata0`, `ide2`, `scsi4`, and `virtio0` in addition to backing `disk-N` selectors.
- Destination selectors may be a backing `disk-N`, an exact QEMU disk slot, or a bare bus name (`ide`, `sata`, `scsi`, `virtio`) meaning the first free slot on that bus.
- Add helpers refuse occupied exact destination slots; overwrite helpers replace occupied exact slots and create into empty exact/bare-bus targets.
- Added `boot` as an anywhere-on-the-command-line keyword. The actual destination slot is moved to the front of the VM boot order after attachment; overwrite `restart` applies the boot order before the VM is started.
- Added explicit Proxmox slot-range validation: IDE 0–3, SATA 0–5, SCSI 0–30, VirtIO 0–15.
- Expanded static and real copy/snapshot integration coverage for source-by-slot, exact destination slots, bare-bus first-free selection, and boot-order verification.

## 3.2.3 — 2026-08-17

Empty-target overwrite/add behavior.

- `create-disk-copy-and-overwrite-disk-on-vm.sh` and `create-disk-snapshot-and-overwrite-disk-on-vm.sh` now accept `DEST_VMID disk-N` even when that destination backing disk is not currently configured.
- When no active destination disk uses the requested number, the helper creates the result as exactly `vm-DESTVMID-disk-N` and attaches it to the first free SCSI slot.
- `delete` becomes a no-op when there is no displaced disk.
- The final LV name must still be physically free; orphaned or otherwise colliding same-name LVs are never overwritten implicitly.
- Existing-target behavior is unchanged: archive to `disk-901+`, preserve by default, or delete only after verified replacement.
- Added real integration cases for both copy and snapshot empty-target creation.

## 3.2.2 — 2026-08-17

Overwrite transaction safety fix.

- Fixed a false storage-mapping failure after the staged replacement LV was renamed to the destination disk number.
- Replacement identity is now verified by LV UUID instead of a stale pre-rename device path.
- Rollback locates the displaced original LV by its saved UUID.
- Rollback no longer calls `qm --delete unusedN`, which can free the backing unused volume.
- Unused-disk reference rewrites/removals are config-only operations; explicit LV deletion happens only for the `delete` path after successful replacement.
- If rollback cannot prove a safe restoration, automatic replacement cleanup is disabled so remaining recovery material is preserved.

## 3.2.1 — 2026-08-17

Corrected overwrite semantics for both disk-overwrite helpers.

- Replacement copies/snapshots now finish with the destination's original `vm-VMID-disk-N` backing number.
- The displaced destination LV is renamed first to the first free `vm-VMID-disk-901+` and preserved as `unusedN`.
- Added the `delete` keyword, accepted anywhere, to permanently remove the displaced archived LV only after the replacement is attached, verified, and requested VM-state restoration succeeds.
- Kept the replacement staging LV temporary: it is renamed into the original disk number immediately before reattachment.
- Added integration coverage for preserve and delete paths for both overwrite helpers.

## 3.2.0 — 2026-08-17

Disk create/overwrite expansion.

- Added `create-disk-copy-and-overwrite-disk-on-vm.sh`.
- Added `create-disk-snapshot-and-overwrite-disk-on-vm.sh`.
- Overwrite helpers accept source and destination as either full LVM paths or `VMID + disk-N`/slot selectors.
- Overwrite helpers default to hot replacement and accept `pause`, `stop`, or `restart` anywhere on the command line.
- The destination VM is the state-controlled VM for overwrite operations because it is the VM losing/replacing a disk.
- Displaced destination volumes are preserved as `unusedN`; they are not automatically deleted.
- Expanded `create-disk-copy-and-add-to-vm.sh` and `create-disk-snapshot-and-add-to-vm.sh` to accept full-path or `VMID + disk-N` sources, optional destination backing disk numbers, and hot/pause/stop/restart source-state modes.
- Preserved the previous copy-and-add positional destination-VG form.
- Expanded the disposable integration matrix to 40 commands and added overwrite cases to `50-copy-snapshot.sh`.


All notable project changes are summarized here.

## 3.1.0 — 2026-08-17

Two new standalone helpers.

- Added `list-all-vm-lvm.sh` to group guest-referenced LVM volumes under QEMU/LXC VMIDs and then list every remaining visible LV.
- Added `move-disk-to-vm.sh` with two source forms:
  - `<full-lv-path> <destination-vmid>`
  - `<source-vmid> <disk-number|slot> <destination-vmid>`
- `move-disk-to-vm.sh` defaults to live hot-swap and accepts `pause`, `stop`, or `restart` anywhere on the command line.
- The transfer preserves the existing LV without copying, deleting, or renaming it and attaches it to the destination VM's first free SCSI slot.
- Active-source transfers detach before destination attach so the same writable LV is never intentionally attached to two running VMs at once.
- Added best-effort rollback when an active source was detached but destination attachment fails before touching the destination config.
- Expanded the real Proxmox integration matrix from 36 to 38 commands, including both CLI forms and all source-state modes.
- Public helpers remain self-contained single files.

## 3.0.1 — 2026-08-15

Integration-validated POSIX baseline.

- Public top-level helpers are now fully self-contained single files.
- Embedded the common/dry-run runtime into all 36 commands.
- Embedded companion implementations into the six wrapper commands that previously invoked sibling project scripts.
- Added a static acceptance test that copies every helper into an empty directory and proves `--help` / `--version` still work without the repository.
- The repository `lib/` directory is retained only as canonical maintenance source; it is not a runtime dependency.

- Corrected POSIX `set -e` regressions exposed by the first v3 real-system run.
- Fixed `rename-lvm.sh`, `unmount-vm-drives.sh`, `renumber-vm-disks.sh` and `recover-vm-from-volumes.sh`.
- Corrected a latent short-circuit guard issue in `set-vm-boot-disk.sh`.
- Added a static regression that rejects unsafe `&& die` guard patterns.
- Re-ran the disposable Proxmox integration suite successfully:
  - 36/36 command integration cases clean;
  - dry-run mutation snapshots unchanged;
  - protected guest/LVM/storage state returned to baseline;
  - no protected-state anomalies detected.

## 3.0.0 — 2026-08-15

Full POSIX `/bin/sh` rewrite.

- Rewrote all 36 command entry points and shared libraries for POSIX shell syntax.
- Standardized `setup()` / `main()` / `end()` lifecycle structure.
- Replaced Bash arrays with auditable plan/journal files.
- Replaced Bash `ERR`/array rollback patterns with POSIX exit traps and transaction journals.
- Preserved project-wide dry-run semantics.
- Added POSIX static acceptance tests and migration documentation.
- First real-system v3 run exposed several `set -e` return-status regressions subsequently fixed in 3.0.1.

## 2.2.2 — 2026-08-15

Known-good pre-v3 behavioral reference.

- Full disposable Proxmox integration suite completed cleanly.
- 10/10 groups passed with zero protected-state anomalies.
- Established the behavioral baseline for the v3 POSIX rewrite.

## 2.1.0

Project-wide dry-run support.

- Added `dryrun` / `--dryrun` to mutating commands.
- Kept read-only preflight real while printing mutations instead of executing them.
- Added simulated mutation-dependent verification and nested dry-run propagation.

## Earlier versions

Earlier releases established the 36-helper command set, safety checks, LVM/Proxmox integration behavior and grouped integration-test architecture.
