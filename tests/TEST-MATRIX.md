# Test Coverage Matrix — v3.0.1

Every executable project command is covered by at least one group.

| # | Command | Group | Integration coverage |
|---:|---|---|---|
| 1 | `attach-existing-lvm-to-vm.sh` | `40-disk-lifecycle.sh` | dry-run immutability + real attach |
| 2 | `audit-vm-storage.sh` | `10-inspection.sh` | read-only audit of disposable VM |
| 3 | `bulk-change-vm-network.sh` | `90-network.sh` | dry-run + real config change on stopped test VMs |
| 4 | `bulk-change-vm-storage.sh` | `70-storage-io.sh` | dry-run + real move between test storages |
| 5 | `change-disk-bus.sh` | `60-disk-config.sh` | dry-run + real config bus change |
| 6 | `change-vm-storage-prefix.sh` | `70-storage-io.sh` | dry-run + real rewrite between two IDs for the same test pool |
| 7 | `change-vmid-of-vm.sh` | `80-vm-config.sh` | dry-run + real disposable VMID transaction |
| 8 | `cleanup-unused-disks.sh` | `40-disk-lifecycle.sh` | dry-run + real cleanup of test unused disk |
| 9 | `clone-single-vm-disk.sh` | `50-copy-snapshot.sh` | dry-run + real independent clone |
| 10 | `clone-vm-config-only.sh` | `80-vm-config.sh` | dry-run + real diskless test config clone |
| 11 | `copy-disk-between-vms.sh` | `50-copy-snapshot.sh` | dry-run + real cross-VM copy |
| 12 | `copy-lvm.sh` | `20-lvm.sh` | dry-run + real cross-VG independent copy + `cmp` |
| 13 | `create-disk-copy-and-add-to-vm.sh` | `50-copy-snapshot.sh` | dry-run + real copy to second VG and attach |
| 14 | `create-disk-snapshot-and-add-to-vm.sh` | `50-copy-snapshot.sh` | dry-run + real thin snapshot and attach |
| 15 | `delete-disk-from-vm.sh` | `40-disk-lifecycle.sh` | dry-run + real test-volume deletion |
| 16 | `delete-lvm.sh` | `20-lvm.sh` | dry-run + explicit `DELETE` confirmation on test LV |
| 17 | `detach-disk-from-vm.sh` | `40-disk-lifecycle.sh` | dry-run + real detach to `unusedN` |
| 18 | `export-vm-disk.sh` | `70-storage-io.sh` | dry-run no-output proof + real qcow2 export |
| 19 | `find-orphaned-volumes.sh` | `10-inspection.sh` | discovers intentionally orphaned test LV |
| 20 | `find-volume-owner.sh` | `10-inspection.sh` | resolves test LV back to test VM config |
| 21 | `fix-vm-volume-names.sh` | `60-disk-config.sh` | dry-run + real repair of intentionally mismatched test LV |
| 22 | `import-disk-and-attach.sh` | `70-storage-io.sh` | dry-run + real small raw-image import |
| 23 | `list-vm-disks.sh` | `10-inspection.sh` | lists attached disposable test LV |
| 24 | `mount-vm-disk.sh` | `30-mount.sh` | dry-run + real read-only mount via VM slot |
| 25 | `mount-vm-drives.sh` | `30-mount.sh` | dry-run + real read-only direct-LV mount |
| 26 | `mount-vm-root.sh` | `30-mount.sh` | dry-run + real synthetic Linux-root detection |
| 27 | `move-disk-to-storage.sh` | `70-storage-io.sh` | dry-run + real move between test storages |
| 28 | `move-lvm.sh` | `20-lvm.sh` | dry-run + real cross-VG move |
| 29 | `recover-vm-from-volumes.sh` | `80-vm-config.sh` | dry-run + real recovery from orphaned test LV |
| 30 | `rename-lvm.sh` | `20-lvm.sh` | dry-run + real test-LV rename |
| 31 | `renumber-vm-disks.sh` | `60-disk-config.sh` | dry-run + real 3/7 → 0/1 test-volume renumber |
| 32 | `replace-vm-disk.sh` | `60-disk-config.sh` | dry-run + real replacement with test LV |
| 33 | `set-vm-boot-disk.sh` | `60-disk-config.sh` | dry-run + real boot-order update |
| 34 | `snapshot-disk-between-vms.sh` | `50-copy-snapshot.sh` | dry-run + real thin snapshot between test VMs |
| 35 | `swap-vm-disks.sh` | `60-disk-config.sh` | dry-run + real config slot swap |
| 36 | `unmount-vm-drives.sh` | `30-mount.sh` | dry-run proves mount remains + real unmount |

In addition, `00-static-cli.sh` parses all 36 commands and shared libraries with `/bin/sh`, requires `/bin/sh` entry-point shebangs, scans for prohibited Bash constructs, exercises `--help`/`--version`, and tests both `dryrun --version` and `--version dryrun` for all 36 commands.
