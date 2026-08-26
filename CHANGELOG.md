# Changelog

## 3.7.1 — 2026-08-20

Real-Proxmox corrective patch based on the v3.7.0 full-suite run.

- **2026-08-26 repository identity update:** standardize the project/repository name on **LongTailToilForProxmox**, update all GitHub/raw-download/install/publishing references accordingly, and keep production helper behavior unchanged.

- Record the exact v3.7.0 real-host result: 74/74 static cases and 130/137 real integration cases passed; all 98 protected host baseline/after pairs and all 130 captured before/after mutation-safety pairs in the supplied evidence archive were byte-identical, with zero anomalies.
- Fix `copy-vm-disk-options.sh` verification so Proxmox's canonical reordering of comma-separated disk options does not create a false failure. Backing volume identity remains position-sensitive/exact; option key/value tokens are compared order-independently.
- Fix `clone-vm-storage-only.sh` for LVM-backed sources. Each source is converted to an invocation-owned regular raw staging image before `qm importdisk`; imported guest-visible bytes are verified against that immutable staging image before attachment. Inactive source activation is restored immediately after staging, and staging data is removed on every exit path.
- Keep hot clone semantics explicit: transfer integrity against the immutable staging image is verified, but a source that changes while staging is created is not claimed to be application- or post-copy-consistent.
- Fix exact same-identity VM restore verification: QEMU `vmgenid` is intentionally allowed to regenerate under Proxmox and is excluded from canonical persistent-config equality. A regenerated `vmgenid` is still required when the archived QEMU config contained one.
- Fix `send-vm-export-and-restore.sh` dry-run so it performs no SSH/SCP/remote preflight at all. `--preflight` remains the explicit remote read-only check and now uses `StrictHostKeyChecking=yes`, refusing an unknown host key instead of modifying `known_hosts`.
- Correct the unmanaged-name integration fixture: Proxmox LVM-thin rejects arbitrary `custom-*` image names as configured disks, so the test now proves that an unrelated custom LV in the owned VG is not scanned or renamed while a valid managed VM disk remains unchanged.
- Correct archive checksum integration validation to execute `sha256sum -c ltvm/checksums.sha256` from the extraction root, matching the archive's intentionally `ltvm/...`-prefixed manifest paths.
- Strengthen integration postconditions for disk-option copy and exact restore.
- Add four focused static regression contracts for semantic option verification, regular-file clone staging, `vmgenid`/checksum-root exactness, and zero-SSH dry-run/host-key-safe preflight.
- Test-suite metadata is **3.1.1**. Static/CLI validation: **78 passed, 0 failed, 0 skipped, 0 anomalies**.
- The real integration definition remains **137 cases across 14 operational groups**. A fresh 2026-08-22 all-groups run passed **78/78 static/CLI and 137/137 real integration cases**, with **15/15 groups passed and zero failures, skips or anomalies**. v3.7.1 is therefore the current real-host integration-validated baseline; see `docs/V3.7.1-REAL-INTEGRATION-RESULTS.md`.
- Re-audit all 81 command interfaces and documentation after acceptance: all live `--help` outputs, `.usage` snapshots and embedded helper-page help blocks are byte-identical; README/helper-index/test-matrix inventories are complete; local Markdown links resolve; stale “current” wording in historical test documentation is corrected. See `docs/V3.7.1-DOCUMENTATION-AUDIT.md`.

## 3.7.0 — 2026-08-19

Mount-family consolidation and project-wide CLI/documentation contract release.

- Replace six historical mount/unmount entry points with five clearer public commands:
  - `mount-vm-drives.sh` -> `mount-lvm-drives.sh`
  - `unmount-vm-drives.sh` -> `unmount-lvm-drives.sh`
  - `mount-vm-disk.sh` + `mount-vm-root.sh` -> `mount-vm-drive.sh`
  - `mount-vm-filesystems.sh` -> `mount-all-vm-drives.sh`
  - `unmount-vm-filesystems.sh` -> `unmount-all-vm-drives.sh`
- Make `mount-vm-drive.sh` and `mount-all-vm-drives.sh` use the same mount engine and filesystem-role classifier. The only implementation difference is the hard-coded single-slot versus all-slots scope selector.
- Require stopped QEMU state for VM-level host filesystem mounting; preserve inactive LV activation state with `lvchange -ay -K`; verify exact mounted-source identity; refuse ambiguous pre-existing mapper ownership; record invocation-owned resources; and roll back partial mount failures.
- Pair both VM-level mount commands with `unmount-all-vm-drives.sh`, which consumes the ownership-state file and refuses cleanup when recorded source/target identity no longer matches.
- Keep `mount-lvm-drives.sh` / `unmount-lvm-drives.sh` as the lower-level direct-LVM tools for callers that already know the LV path.
- Standardize public help across all 81 commands. Every command accepts `-h`, `-?`, `/h`, `/?`, and `--help`, identifies itself and the project version, exposes a `USAGE` and descriptive `DESCRIPTION`, and documents every parsed long option.
- Required-argument failures print usage instead of only a terse error.
- Standardize dry-run documentation to the single line: `Dry-run: no system changes are made; modifying commands are printed instead of executed.`
- Regenerate all `.usage` snapshots from live command output and synchronize the exact help block in every per-helper Markdown page.
- Regenerate the helper index, README inventory and 81-command test matrix for the new public command surface.
- Update integration coverage for direct-LVM mounting, one-drive VM mounting, all-drive VM mounting, role detection, read-write persistence, partition mapping, ownership-state cleanup and dry-run immutability.
- Extend static contracts for all help aliases, incomplete-argument usage, parser/help agreement, documentation/live-help identity and the single/all VM mount-engine source-identity rule.
- Static/CLI validation: **74 passed, 0 failed, 0 skipped, 0 anomalies**.
- The real integration definition remains **137 cases across 14 operational groups**. v3.7.0 remains release-candidate / statically validated until that definition is rerun on a disposable real Proxmox/LVM host.

## 3.6.2 — 2026-08-19

Selective integration and hardening of the alternate v3.6.1 QoL/workflow command family onto the v3.5.2 safety baseline.

- Add 40 standalone helpers, bringing the public command count from 42 to **82**, with matching Markdown documentation, live-help snapshots and integration references.
- Normalize all 82 public helper version banners to `3.6.2 (project 3.6.2)` to retain the established project-wide release-version convention.
- Retain the v3.5.2 behavior fixes instead of replacing the original 42 helpers with the older alternate copies.
- Make physical LV identity, not a Proxmox volume-ID string, the safety boundary for shared/reference decisions in the new command runtime.
- Restore inactive-source activation state on every success/failure exit path and authorize incomplete-copy cleanup only by the LV UUID captured after creation.
- Harden reference-only/direct-config helpers with strict slot ranges, stopped/snapshot-free preflight, backups and abnormal-exit rollback.
- Make mount/unmount workflows ownership-record based: exact canonical mounted sources are verified, pre-existing mapper identities are refused, partial failures roll back only invocation-owned resources and unmount refuses changed state.
- Require exact device/mount identity for filesystem growth; separate block growth from filesystem growth and preserve grow-only semantics.
- Harden disk flattening, storage migration, storage-only cloning and disk-rebuild workflows with transaction state, UUID identity, rollback and fail-closed cleanup.
- Harden operation journals against predictable/symlinked/non-root-owned `/var/tmp` state and make archive output commits non-overwriting unless `--force` is explicit.
- Keep whole-VM archive checksums as integrity evidence (not authenticity), validate archive members before extraction/execution, and verify the complete transferred archive hash before remote restore.
- Extend style/testing guidance for exact postconditions, machine-readable output, journals, no-`eval` dispatch, growth layers, portable-backup claims and remote restore transactions.
- Test suite version: **3.0.2**. The integrated tree defines **137** real integration cases across 14 operational groups plus the static/CLI group.
- v3.5.1 remains the last completed real-Proxmox acceptance baseline. v3.6.2 requires a fresh real-host run and is not described as integration-validated by this static port.

## 3.5.2 — 2026-08-18

Documentation-contract, structural-consistency and evidence-hardening release based on the clean v3.5.1 real-Proxmox acceptance run.

- Audit all 42 helpers code-first against built-in help, `.usage` snapshots, per-helper pages and README descriptions; document stopped-guest prerequisites, selector forms, QEMU/LXC scope, output-format defaults, alias-only storage-prefix rewrites and overwrite path semantics.
- Normalize elevation lifecycle placement so every public helper performs detection in `setup()` and crosses the elevation boundary in `main()`; read-only inspection helpers now implement the elevation behavior their pages already promised.
- Enforce the documented `import-disk-and-attach.sh` explicit-slot contract by refusing anything outside `scsi0..scsi30` before import.
- Restrict `fix-vm-volume-names.sh` to already-managed `vm-*`/`base-*` volume names. Custom/unmanaged LVM names are left unchanged; managed family and disk number are preserved.
- Make `mount-vm-root.sh` rank Linux-root candidates and report the strongest candidate while retaining Windows/EFI/recovery role classification.
- Correct transaction-function documentation and the misplaced `change_bus` comment; extend static checks for elevation placement, embedded standalone payload synchronization, documented safety semantics and evidence provenance.
- Add test-only failure injection for both overwrite engines after old-disk archive/final replacement rename but before new attachment; rollback must return the complete disposable state to its byte-identical pre-command snapshot. No production failure-injection hook is introduced.
- Expand real integration coverage from 88 to 92 cases with invalid import-slot refusal, unmanaged-name preservation and two rollback failure-injection cases.
- Record the supplied v3.5.1 result as the accepted predecessor baseline: 50/50 static and 88/88 real integration cases passed with zero skips, failures or anomalies.
- Test-suite metadata is now 2.9.2. Result directories capture environment/tool versions, project SHA-256 manifests, fixture manifests and final summaries; successful static evidence is retained.
- v3.5.2 remains release-candidate / statically validated until the revised 92-case real integration definition passes on a disposable real Proxmox host.

## 3.5.1 — 2026-08-17

Bugfix release based on the v3.4.7 real-Proxmox acceptance results supplied on 2026-08-17.

- Fix inactive Proxmox template/base independent copies. `base-*` LVs may carry LVM activation-skip; plain `lvchange -ay` can return success while intentionally leaving the block device absent. The three canonical copy engines now use `lvchange -ay -K` for temporary source activation, retain exact block-device verification, and restore sources to inactive afterward.
- Update the real byte-comparison fixture for inactive base/template LVs to use the same `-K` activation semantics.
- Strengthen the static inactive-source contract so future regressions must retain activation-skip handling.
- Fix the network integration fixture: it now calls `create_storage_sandbox` before creating the LXC rootfs and refuses to proceed unless `TEST_STORAGE_A` is provably registered to the current test run.
- Add a static contract enforcing network rootfs-storage provisioning/ownership order.
- The supplied v3.4.7 run is recorded as 86/88 integration cases passing, with two inactive-base copy failures and one network cleanup anomaly. All other functional cases passed; the two copy failures occurred before destination mutation.
- Test-suite metadata is now 2.9.1. The integration definition remains 88 real cases.
- v3.5.1 remains a release candidate until the focused copy/network groups and then the full suite pass on real Proxmox with zero failures and zero anomalies.

## 3.5.0 — 2026-08-17

Project-wide POSIX shell structure/style refactor; intended runtime semantics remain those of v3.4.7.

- All 42 public helpers now define `setup()`, `main()`, `end()`, then `usage()` as their first four functions.
- User/default/script state initialization is at the top of `setup()` before setup helper calls.
- Routine root-success output such as `[OK] Elevation: running as root.` was removed. Elevation is reported only when the operation actually needs elevation and the current process lacks it.
- `usage()` is immediately after `end()` in every public helper.
- Argument-taking functions now include explicit call syntax in their comment blocks.
- Function scratch variables use one function-derived prefix consistently; inconsistent legacy prefixes were normalized.
- The style guide now defines `_functionprefix_...` for deliberate function-persistent private state and conceptual pseudoarray/pseudoobject notation while preserving POSIX-safe executable representations.
- Standalone embedded companion payloads were regenerated from the refactored canonical helpers.
- Static coverage now enforces lifecycle order, silent elevation, argument-call documentation, help/usage snapshots, standalone structure and the existing safety contracts.
- Test-suite metadata is now 2.9.0; the real Proxmox integration definition remains 88 cases and requires a fresh real-host run because every public helper was structurally rewritten.

## 3.4.7 — 2026-08-17

Third real-Proxmox integration-run corrections.

- The latest run executed 83 of 86 registered real cases: 82 passed, one copy-helper case failed, and three network cases were blocked during fixture setup; eight of ten groups were otherwise clean.
- All nine integration result directories had byte-identical protected before/after state across VG/PV/LV metadata, storage semantics, guest configs, guest runtime status and firewall checksums.
- `copy-lvm.sh`, `create-disk-copy-and-add-to-vm.sh`, and `create-disk-copy-and-overwrite-disk-on-vm.sh` now temporarily activate an existing inactive source LV for block copy/verification and restore it to inactive afterward without changing LV permission metadata.
- The corrected raw copy implementation is re-embedded into `move-lvm.sh`; corrected create-copy logic is re-embedded into `copy-disk-between-vms.sh` and `clone-single-vm-disk.sh`.
- Raw `copy-lvm.sh` source size now comes from authoritative `lvs` metadata, removing another active-device assumption.
- Added real inactive-source regression cases for raw copy and create-copy overwrite; the existing base/template copy-add case now explicitly requires the source to remain inactive before and after the operation.
- Network fixture setup no longer calls `qm set`/`pct set` for the NIC operation under test. It seeds stopped disposable configs directly, validates them with `qm config`/`pct config`, then lets the registered project-helper case perform the first network mutation.
- Expanded lessons/style/testing documentation with activation-state preservation and fixture/API separation guidance.
- Test-suite metadata is now 2.8.5 with 88 real integration cases.

## 3.4.6 — 2026-08-17

Documentation, usage-snapshot and engineering-lessons release; no storage transaction semantics changed from v3.4.4/v3.4.5.

- Added `docs/PROXMOX-SHELL-SCRIPTING-LESSONS-LEARNED.md`, capturing concrete Proxmox/LVM/POSIX-shell pitfalls discovered during development and real-host integration testing.
- Added three new testing best-practice guides for Proxmox fixtures, POSIX shell harness design and destructive-test safety.
- Expanded `docs/POSIX-SHELL-STYLE-GUIDE-v3.md` with explicit rules for exit-status contracts, `set -e` guard traps, config-reference versus storage deletion, UUID identity across renames, conservative rollback, value classes, authoritative metadata, bus-option compatibility, paused-controller topology, external utility option compatibility and help/usage stability.
- Added 42 verbatim `docs/<script>.sh.usage` files generated from each helper's live `--help` output.
- Updated all 42 helper documentation pages to link their raw usage snapshot and embed the current v3.4.6 help/version output.
- Updated every README helper heading to `script · doc · usage`, with direct links to the executable, documentation page and usage snapshot.
- Updated `docs/HELPERS.md` to index script, documentation and usage pages.
- Strengthened static coverage so each helper must return successful `--help` with a Usage section and its `.usage` file must match live help byte-for-byte.

## 3.4.5 — 2026-08-17

Per-helper help and documentation hardening.

- Audited all 42 public helpers: every `--help` path returns success and exposes a usage section/line before elevation or operation preflight.
- Added one documentation page under `docs/` for every public helper, containing purpose, built-in help, install command, README examples, safety notes and version information.
- Added `docs/HELPERS.md` as the complete 42-helper documentation index.
- Changed every README helper heading to link the script filename directly and include a same-line `doc` link to its per-helper page.
- Strengthened static coverage so `--help` must contain usage text and every public helper must have exactly one README script/doc heading plus an existing matching documentation page.
- Bumped the test-suite metadata to 2.8.3 without changing the 86-case real integration definition or v3.4.4 storage transaction semantics.

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
