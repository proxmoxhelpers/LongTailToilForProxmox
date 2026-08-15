# Changelog

All notable project changes are summarized here.

## 3.0.1 — 2026-08-15

Integration-validated POSIX baseline.

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
