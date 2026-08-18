# Test Coverage Matrix — v3.4.7

Every public command has at least one non-static integration reference. For mutating commands, the static suite additionally requires at least one `run_dryrun_unchanged` integration case. The matrix describes representative real and negative/variant coverage; it does **not** claim combinatorial testing of every possible argument order, storage backend, filesystem, Proxmox release, or failure injection point.

| # | Command | Group | Positive / real integration coverage | Negative / variant coverage |
|---:|---|---|---|---|
| 1 | `attach-existing-lvm-to-vm.sh` | `40-disk-lifecycle.sh` | Dry-run + real attach to disposable VM/LV. | Shared-volume attach refusal with exact state unchanged. |
| 2 | `audit-vm-storage.sh` | `10-inspection.sh` | Read-only audit of disposable VM/storage state. | Read-only contract; no mutation path. |
| 3 | `bulk-change-vm-network.sh` | `90-network.sh` | Real QEMU + LXC tag/firewall/model update while preserving MAC/other NIC options. | Tag removal/firewall-off; missing-guest preflight refusal before valid targets are touched. |
| 4 | `bulk-change-vm-storage.sh` | `70-storage-io.sh` | Dry-run + real two-VM storage migration between disposable pools with byte-hash preservation. | Both guests verified; old source LVs must disappear. |
| 5 | `change-disk-bus.sh` | `60-disk-config.sh` | Exact destination bus/slot change with destination-compatible option preservation. | Bare-bus first-free, omitted destination default, occupied-slot refusal. |
| 6 | `change-vm-storage-prefix.sh` | `70-storage-io.sh` | Dry-run + real rewrite between two storage IDs mapped to the same disposable VG. | Exact volume tail/options preserved; all owned QEMU configs checked for old prefix. |
| 7 | `change-vmid-of-vm.sh` | `80-vm-config.sh` | Dry-run + real QEMU VMID change, template/base change, and LXC rootfs change; LV UUIDs preserved. | Running-QEMU state behavior; destination-ID collision, snapshot, and shared-volume refusals. |
| 8 | `cleanup-unused-disks.sh` | `40-disk-lifecycle.sh` | Dry-run + real explicit unused-volume cleanup and --all cleanup. | Shared-volume cleanup refusal with exact state unchanged. |
| 9 | `clone-single-vm-disk.sh` | `50-copy-snapshot.sh` | Dry-run + real independent clone; new volume identified by before/after set difference. | Content equality verified. |
| 10 | `clone-vm-config-only.sh` | `80-vm-config.sh` | Dry-run + real diskless config clone. | Name/description preserved; storage-backed entries absent in clone. |
| 11 | `copy-disk-between-vms.sh` | `50-copy-snapshot.sh` | Dry-run + real cross-VM independent copy. | Content equality and independently allocated destination verified. |
| 12 | `copy-lvm.sh` | `20-lvm.sh` | Dry-run + real thin-LV copy, regular-LV destination copy, and inactive-source copy with activation restored. | Full byte/hash verification; static contract forbids sparse regular writes and permission-changing activation. |
| 13 | `create-disk-copy-and-add-to-vm.sh` | `50-copy-snapshot.sh` | Dry-run + real copy using VM/disk, slot and full-path source forms; exact/bare-bus destinations; boot promotion; inactive template/base source activation restored. | hot/stop/restart source-state paths; occupied-slot and ambiguous disk-N refusals; template/base destination. |
| 14 | `create-disk-copy-and-overwrite-disk-on-vm.sh` | `50-copy-snapshot.sh` | Dry-run + real overwrite preserving final disk-N, slot/options and boot behavior; empty-target creation. | Archive collision forces disk-902; preserve/delete paths; inactive base source; ambiguous source refusal; unsafe paused-SCSI topology preflight refusal. |
| 15 | `create-disk-snapshot-and-add-to-vm.sh` | `50-copy-snapshot.sh` | Dry-run + real linked snapshot using slot/full-path sources; exact/bare-bus destinations; boot promotion; template/base source sizing from LVM metadata. | hot/pause source-state paths; occupied-slot and ambiguous disk-N refusals; template/base destination. |
| 16 | `create-disk-snapshot-and-overwrite-disk-on-vm.sh` | `50-copy-snapshot.sh` | Dry-run + real overwrite preserving final disk-N, snapshot origin, slot/options and boot behavior; empty-target creation. | Archive preserve/delete paths; full-path destination; template/base overwrite; ambiguous source refusal; unsafe paused-SCSI topology preflight refusal. |
| 17 | `delete-disk-from-vm.sh` | `40-disk-lifecycle.sh` | Dry-run + real deletion of disposable unused and active test disks. | Shared-reference refusal. |
| 18 | `delete-lvm.sh` | `20-lvm.sh` | Dry-run + explicit DELETE confirmation on disposable LV. | Wrong-confirmation refusal with exact state unchanged. |
| 19 | `detach-disk-from-vm.sh` | `40-disk-lifecycle.sh` | Dry-run + real detach to unusedN. | Running-VM refusal with runtime state verified unchanged. |
| 20 | `export-vm-disk.sh` | `70-storage-io.sh` | Dry-run no-output proof + real qcow2 and inferred raw exports; qcow2 logical data verified with qemu-img compare. | qemu-img format verification and raw byte comparison against source. |
| 21 | `find-orphaned-volumes.sh` | `10-inspection.sh` | Read-only discovery of intentionally orphaned vm- and base-family LVs. | Referenced fixtures must not be reported as orphans. |
| 22 | `find-volume-owner.sh` | `10-inspection.sh` | Read-only resolution of disposable LV to owning guest/slot. | Managed vm/base fixture coverage. |
| 23 | `fix-vm-volume-names.sh` | `60-disk-config.sh` | Dry-run + real stale vm- and base-family name repair, including template/base path. | Exact corrected-name collision refusal; family and disk-N preservation. |
| 24 | `import-disk-and-attach.sh` | `70-storage-io.sh` | Dry-run + real raw-image import with explicit slot and default-slot forms. | Imported bytes compared to source image. |
| 25 | `list-all-vm-lvm-filesystems.sh` | `10-inspection.sh` | Read-only partx + blkid byte-range inspection of real disposable GPT/ext4 data and remaining LVs. | Compatible Linux/ext4 case plus deliberate Microsoft-basic-data/ext4 mismatch. |
| 26 | `list-all-vm-lvm.sh` | `10-inspection.sh` | Read-only grouping of guest-referenced LVs under VMIDs plus remaining-LV list. | Normal/template/base and orphan fixtures. |
| 27 | `list-vm-disks.sh` | `10-inspection.sh` | Read-only listing of attached disposable guest LVs. | Slot/path presence verified. |
| 28 | `mount-vm-disk.sh` | `30-mount.sh` | Dry-run + real read-only mount via VM slot for direct and partitioned disks. | Partitioned path verifies mapper creation/removal stays inside disposable device. |
| 29 | `mount-vm-drives.sh` | `30-mount.sh` | Dry-run + real read-only direct-LV mount plus read-write disposable mount. | RW persistence checked by remounting read-only. |
| 30 | `mount-vm-root.sh` | `30-mount.sh` | Dry-run + real synthetic Linux-root detection from disposable partition. | Detected root content verified. |
| 31 | `move-disk-to-storage.sh` | `70-storage-io.sh` | Dry-run + real move between disposable storages. | Disk options and first-32MiB hash preserved; old LV removed. |
| 32 | `move-disk-to-vm.sh` | `40-disk-lifecycle.sh` | Dry-run + real full-path, numeric and explicit-slot moves. | hot/pause/stop/restart; positive pause uses a shared SCSI controller with another disk; unsafe sole/per-disk SCSI pause is refused before mutation; base/template numeric selector; ambiguous disk-N refusal then explicit-slot resolution. |
| 33 | `move-lvm.sh` | `20-lvm.sh` | Dry-run + real cross-VG move and same-VG rename branch. | Content hash preserved cross-VG; LV UUID preserved same-VG. |
| 34 | `recover-vm-from-volumes.sh` | `80-vm-config.sh` | Dry-run + real recovery from two vm-family orphan LVs and base-family auto-VG discovery. | Recovered guest config/storage references verified. |
| 35 | `rename-lvm.sh` | `20-lvm.sh` | Dry-run + real path-form and VG/old/new-form rename. | LV UUID preserved in both forms. |
| 36 | `renumber-vm-disks.sh` | `60-disk-config.sh` | Dry-run + real namespace-preserving renumber across current vm-* and stale base-OTHERID-* namespaces; template/base case. | Shared-volume renumber refusal. |
| 37 | `replace-vm-disk.sh` | `60-disk-config.sh` | Dry-run + real replacement while preserving slot options and old volume as unusedN. | Shared replacement-volume refusal. |
| 38 | `set-vm-boot-disk.sh` | `60-disk-config.sh` | Dry-run + real boot promotion while preserving remaining order. | Invalid/unconfigured boot slot refusal. |
| 39 | `snapshot-disk-between-vms.sh` | `50-copy-snapshot.sh` | Dry-run + real linked thin snapshot between disposable VMs. | Snapshot origin verified by LVM metadata. |
| 40 | `swap-vm-disks.sh` | `60-disk-config.sh` | Dry-run + real swap of two configured slots. | Each original full config value moves to the opposite slot. |
| 41 | `unmount-vm-drives.sh` | `30-mount.sh` | Dry-run proves disposable mount remains; real unmount removes it. | Independent fixture prevents dependence on a previous mount test. |
| 42 | `verify-vm-disk-numbering.sh` | `10-inspection.sh` | Read-only grouping with stale embedded VMID, non-zero start, gap, duplicate disk-N and unused archive fixtures. | unusedN disk-901 is displayed but explicitly excluded from active sequence analysis. |

## Coverage policy

The suite uses three complementary layers:

1. **Static/CLI contracts** prove POSIX parsing, standalone packaging, public help/version behavior, dry-run argument placement, source-level safety invariants, documentation inventory, and harness self-protection.
2. **Disposable real integration cases** exercise normal success paths against loopback-owned LVM/LVM-thin storage and synthetic QEMU/LXC guests, then verify independent postconditions such as LV UUIDs, content hashes, full byte comparisons, snapshot origins, guest configuration and runtime state.
3. **Negative/refusal cases** deliberately construct collisions, shared references, ambiguous selectors, occupied slots, wrong confirmations, running guests or unsupported state and require the command to fail with the complete test-owned snapshot unchanged.

A command row means its material behavior is represented, not that every syntactic permutation is exhaustively enumerated. State modes and selector families are distributed across the relevant create/move helpers so the underlying implementation branches are exercised without multiplying destructive integration operations unnecessarily.

The current v3.4.7 suite defines 88 real integration cases and remains a release-candidate test definition until it is run on a disposable real Proxmox host with zero failures and zero protected-state anomalies.
