# Changelog

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
