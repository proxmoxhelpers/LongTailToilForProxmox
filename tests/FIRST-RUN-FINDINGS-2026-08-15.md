# First Full Integration Run Findings — 2026-08-15

The first complete v2.2.0 run on a real Proxmox node was valuable because it exposed both command defects and test-harness defects that static syntax checking could not detect.

## Observed result

The original all-groups summary reported:

```text
Groups passed : 2
Groups failed : 8
```

Several groups with otherwise successful cases also reported `storage.cfg` anomalies.

## Root causes and v2.2.1 corrections

| Area | Root cause | Classification | v2.2.1 correction |
|---|---|---|---|
| protected storage baseline | raw SHA-256 of `storage.cfg` changed after harmless `pvesm add/remove` rewrite/reordering | test harness | compare canonical semantic storage definitions instead of raw file bytes |
| case execution | test functions were invoked directly in an `if`, which disables reliable `set -e` behavior inside the function | test harness | run each case in its own `set -eu` subshell and capture the first real failure |
| `other_volume_references` | normal “no references found” result inherited status 1 from the final `grep` | shared command helper | explicitly return 0 after producing zero or more reference lines |
| `dryrun_summary` | returned 1 whenever dry-run mode was disabled | shared dry-run helper | always return 0; print only when dry-run is enabled |
| `move-lvm.sh` | successful `copy-lvm.sh` returned 1 because of `dryrun_summary`, so cross-VG move stopped before source deletion | command behavior caused by shared helper | fixed by `dryrun_summary` return contract |
| `unmount-vm-drives.sh` | helper returned status 1 after a successful real-mode `rmdir` because a dry-run predicate was its final command | command | use explicit conditional and return 0 after successful cleanup |
| `renumber-vm-disks.sh` | keyed `sort -u` treated all disk lines as equal because the selected uniqueness key was the VMID | command | sort by extracted numeric disk suffix while preserving uniqueness of the full volume ID |
| orphan/owner inspection | LV-name-only matching can confuse same-named volumes on different storages | command correctness | compare canonical resolved block-device identity |
| LVM warning filter | Bash process substitution caused LVM to report leaked file descriptor 63 | command plumbing | capture `lvcreate` stderr to a temporary file, filter only known advisories, replay all other stderr, preserve real status |

## Regression coverage added

The static/CLI group now directly tests:

- `dryrun_summary` returns success in normal mode;
- an empty `other_volume_references` result is success;
- the test runner stops a case at its first failed command instead of allowing later assertions to mask it.

## Important

v2.2.1 has been syntax- and helper-regression-tested in the build environment, but the full Proxmox integration suite must be rerun on a Proxmox node to validate the real storage/VM behaviors after these corrections.
