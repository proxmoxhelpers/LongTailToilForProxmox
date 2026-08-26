# Helper Documentation Index

Every public helper is a standalone POSIX `/bin/sh` script. Each **doc** page
explains the helper and embeds its exact live help; each **usage** file is the
byte-for-byte output of `./helper.sh --help`.

| Helper | Documentation | Usage |
|---|---|---|
| [`activate-vm-lvs.sh`](../activate-vm-lvs.sh) | [doc](activate-vm-lvs.md) | [usage](activate-vm-lvs.sh.usage) |
| [`add-vm-disk-reference-only.sh`](../add-vm-disk-reference-only.sh) | [doc](add-vm-disk-reference-only.md) | [usage](add-vm-disk-reference-only.sh.usage) |
| [`attach-existing-lvm-to-vm.sh`](../attach-existing-lvm-to-vm.sh) | [doc](attach-existing-lvm-to-vm.md) | [usage](attach-existing-lvm-to-vm.sh.usage) |
| [`audit-vm-boot-config.sh`](../audit-vm-boot-config.sh) | [doc](audit-vm-boot-config.md) | [usage](audit-vm-boot-config.sh.usage) |
| [`audit-vm-storage.sh`](../audit-vm-storage.sh) | [doc](audit-vm-storage.md) | [usage](audit-vm-storage.sh.usage) |
| [`bulk-change-vm-network.sh`](../bulk-change-vm-network.sh) | [doc](bulk-change-vm-network.md) | [usage](bulk-change-vm-network.sh.usage) |
| [`bulk-change-vm-storage.sh`](../bulk-change-vm-storage.sh) | [doc](bulk-change-vm-storage.md) | [usage](bulk-change-vm-storage.sh.usage) |
| [`change-disk-bus.sh`](../change-disk-bus.sh) | [doc](change-disk-bus.md) | [usage](change-disk-bus.sh.usage) |
| [`change-vm-storage-prefix.sh`](../change-vm-storage-prefix.sh) | [doc](change-vm-storage-prefix.md) | [usage](change-vm-storage-prefix.sh.usage) |
| [`change-vmid-of-vm.sh`](../change-vmid-of-vm.sh) | [doc](change-vmid-of-vm.md) | [usage](change-vmid-of-vm.sh.usage) |
| [`cleanup-unused-disks.sh`](../cleanup-unused-disks.sh) | [doc](cleanup-unused-disks.md) | [usage](cleanup-unused-disks.sh.usage) |
| [`clone-single-vm-disk.sh`](../clone-single-vm-disk.sh) | [doc](clone-single-vm-disk.md) | [usage](clone-single-vm-disk.sh.usage) |
| [`clone-vm-config-only.sh`](../clone-vm-config-only.sh) | [doc](clone-vm-config-only.md) | [usage](clone-vm-config-only.sh.usage) |
| [`clone-vm-storage-only.sh`](../clone-vm-storage-only.sh) | [doc](clone-vm-storage-only.md) | [usage](clone-vm-storage-only.sh.usage) |
| [`compare-vm-disks.sh`](../compare-vm-disks.sh) | [doc](compare-vm-disks.md) | [usage](compare-vm-disks.sh.usage) |
| [`convert-lv-to-thin.sh`](../convert-lv-to-thin.sh) | [doc](convert-lv-to-thin.md) | [usage](convert-lv-to-thin.sh.usage) |
| [`convert-thin-to-regular-lv.sh`](../convert-thin-to-regular-lv.sh) | [doc](convert-thin-to-regular-lv.md) | [usage](convert-thin-to-regular-lv.sh.usage) |
| [`copy-disk-between-vms.sh`](../copy-disk-between-vms.sh) | [doc](copy-disk-between-vms.md) | [usage](copy-disk-between-vms.sh.usage) |
| [`copy-lvm.sh`](../copy-lvm.sh) | [doc](copy-lvm.md) | [usage](copy-lvm.sh.usage) |
| [`copy-vm-disk-options.sh`](../copy-vm-disk-options.sh) | [doc](copy-vm-disk-options.md) | [usage](copy-vm-disk-options.sh.usage) |
| [`copy-vm-disk-to-regular-lv.sh`](../copy-vm-disk-to-regular-lv.sh) | [doc](copy-vm-disk-to-regular-lv.md) | [usage](copy-vm-disk-to-regular-lv.sh.usage) |
| [`copy-vm-disk-to-thin-lv.sh`](../copy-vm-disk-to-thin-lv.sh) | [doc](copy-vm-disk-to-thin-lv.md) | [usage](copy-vm-disk-to-thin-lv.sh.usage) |
| [`create-disk-copy-and-add-to-vm.sh`](../create-disk-copy-and-add-to-vm.sh) | [doc](create-disk-copy-and-add-to-vm.md) | [usage](create-disk-copy-and-add-to-vm.sh.usage) |
| [`create-disk-copy-and-overwrite-disk-on-vm.sh`](../create-disk-copy-and-overwrite-disk-on-vm.sh) | [doc](create-disk-copy-and-overwrite-disk-on-vm.md) | [usage](create-disk-copy-and-overwrite-disk-on-vm.sh.usage) |
| [`create-disk-snapshot-and-add-to-vm.sh`](../create-disk-snapshot-and-add-to-vm.sh) | [doc](create-disk-snapshot-and-add-to-vm.md) | [usage](create-disk-snapshot-and-add-to-vm.sh.usage) |
| [`create-disk-snapshot-and-overwrite-disk-on-vm.sh`](../create-disk-snapshot-and-overwrite-disk-on-vm.sh) | [doc](create-disk-snapshot-and-overwrite-disk-on-vm.md) | [usage](create-disk-snapshot-and-overwrite-disk-on-vm.sh.usage) |
| [`deactivate-vm-lvs.sh`](../deactivate-vm-lvs.sh) | [doc](deactivate-vm-lvs.md) | [usage](deactivate-vm-lvs.sh.usage) |
| [`delete-disk-from-vm.sh`](../delete-disk-from-vm.sh) | [doc](delete-disk-from-vm.md) | [usage](delete-disk-from-vm.sh.usage) |
| [`delete-lvm.sh`](../delete-lvm.sh) | [doc](delete-lvm.md) | [usage](delete-lvm.sh.usage) |
| [`detach-disk-from-vm.sh`](../detach-disk-from-vm.sh) | [doc](detach-disk-from-vm.md) | [usage](detach-disk-from-vm.sh.usage) |
| [`export-vm-disk.sh`](../export-vm-disk.sh) | [doc](export-vm-disk.md) | [usage](export-vm-disk.sh.usage) |
| [`export-vm-filesystem.sh`](../export-vm-filesystem.sh) | [doc](export-vm-filesystem.md) | [usage](export-vm-filesystem.sh.usage) |
| [`export-vm.sh`](../export-vm.sh) | [doc](export-vm.md) | [usage](export-vm.sh.usage) |
| [`extend-lvm.sh`](../extend-lvm.sh) | [doc](extend-lvm.md) | [usage](extend-lvm.sh.usage) |
| [`find-orphaned-volumes.sh`](../find-orphaned-volumes.sh) | [doc](find-orphaned-volumes.md) | [usage](find-orphaned-volumes.sh.usage) |
| [`find-shared-vm-volumes.sh`](../find-shared-vm-volumes.sh) | [doc](find-shared-vm-volumes.md) | [usage](find-shared-vm-volumes.sh.usage) |
| [`find-unreferenced-managed-volumes.sh`](../find-unreferenced-managed-volumes.sh) | [doc](find-unreferenced-managed-volumes.md) | [usage](find-unreferenced-managed-volumes.sh.usage) |
| [`find-vm-root-filesystem.sh`](../find-vm-root-filesystem.sh) | [doc](find-vm-root-filesystem.md) | [usage](find-vm-root-filesystem.sh.usage) |
| [`find-volume-owner.sh`](../find-volume-owner.sh) | [doc](find-volume-owner.md) | [usage](find-volume-owner.sh.usage) |
| [`fix-vm-volume-names.sh`](../fix-vm-volume-names.sh) | [doc](fix-vm-volume-names.md) | [usage](fix-vm-volume-names.sh.usage) |
| [`flatten-vm-disk.sh`](../flatten-vm-disk.sh) | [doc](flatten-vm-disk.md) | [usage](flatten-vm-disk.sh.usage) |
| [`for-each-vm.sh`](../for-each-vm.sh) | [doc](for-each-vm.md) | [usage](for-each-vm.sh.usage) |
| [`grow-vm-filesystem.sh`](../grow-vm-filesystem.sh) | [doc](grow-vm-filesystem.md) | [usage](grow-vm-filesystem.sh.usage) |
| [`import-disk-and-attach.sh`](../import-disk-and-attach.sh) | [doc](import-disk-and-attach.md) | [usage](import-disk-and-attach.sh.usage) |
| [`import-vm.sh`](../import-vm.sh) | [doc](import-vm.md) | [usage](import-vm.sh.usage) |
| [`list-all-vm-lvm-filesystems.sh`](../list-all-vm-lvm-filesystems.sh) | [doc](list-all-vm-lvm-filesystems.md) | [usage](list-all-vm-lvm-filesystems.sh.usage) |
| [`list-all-vm-lvm.sh`](../list-all-vm-lvm.sh) | [doc](list-all-vm-lvm.md) | [usage](list-all-vm-lvm.sh.usage) |
| [`list-vm-disks.sh`](../list-vm-disks.sh) | [doc](list-vm-disks.md) | [usage](list-vm-disks.sh.usage) |
| [`migrate-vm-storage-layout.sh`](../migrate-vm-storage-layout.sh) | [doc](migrate-vm-storage-layout.md) | [usage](migrate-vm-storage-layout.sh.usage) |
| [`mount-all-vm-drives.sh`](../mount-all-vm-drives.sh) | [doc](mount-all-vm-drives.md) | [usage](mount-all-vm-drives.sh.usage) |
| [`mount-lvm-drives.sh`](../mount-lvm-drives.sh) | [doc](mount-lvm-drives.md) | [usage](mount-lvm-drives.sh.usage) |
| [`mount-vm-drive.sh`](../mount-vm-drive.sh) | [doc](mount-vm-drive.md) | [usage](mount-vm-drive.sh.usage) |
| [`move-disk-to-storage.sh`](../move-disk-to-storage.sh) | [doc](move-disk-to-storage.md) | [usage](move-disk-to-storage.sh.usage) |
| [`move-disk-to-vm.sh`](../move-disk-to-vm.sh) | [doc](move-disk-to-vm.md) | [usage](move-disk-to-vm.sh.usage) |
| [`move-lvm.sh`](../move-lvm.sh) | [doc](move-lvm.md) | [usage](move-lvm.sh.usage) |
| [`normalize-vm-disk-options.sh`](../normalize-vm-disk-options.sh) | [doc](normalize-vm-disk-options.md) | [usage](normalize-vm-disk-options.sh.usage) |
| [`plan-vm-storage-move.sh`](../plan-vm-storage-move.sh) | [doc](plan-vm-storage-move.md) | [usage](plan-vm-storage-move.sh.usage) |
| [`rebuild-vm-from-existing-disks.sh`](../rebuild-vm-from-existing-disks.sh) | [doc](rebuild-vm-from-existing-disks.md) | [usage](rebuild-vm-from-existing-disks.sh.usage) |
| [`recover-vm-from-volumes.sh`](../recover-vm-from-volumes.sh) | [doc](recover-vm-from-volumes.md) | [usage](recover-vm-from-volumes.sh.usage) |
| [`remove-vm-disk-reference-only.sh`](../remove-vm-disk-reference-only.sh) | [doc](remove-vm-disk-reference-only.md) | [usage](remove-vm-disk-reference-only.sh.usage) |
| [`rename-lvm.sh`](../rename-lvm.sh) | [doc](rename-lvm.md) | [usage](rename-lvm.sh.usage) |
| [`rename-unused-disk-reference.sh`](../rename-unused-disk-reference.sh) | [doc](rename-unused-disk-reference.md) | [usage](rename-unused-disk-reference.sh.usage) |
| [`renumber-vm-device-slots.sh`](../renumber-vm-device-slots.sh) | [doc](renumber-vm-device-slots.md) | [usage](renumber-vm-device-slots.sh.usage) |
| [`renumber-vm-disks.sh`](../renumber-vm-disks.sh) | [doc](renumber-vm-disks.md) | [usage](renumber-vm-disks.sh.usage) |
| [`repair-vm-storage-consistency.sh`](../repair-vm-storage-consistency.sh) | [doc](repair-vm-storage-consistency.md) | [usage](repair-vm-storage-consistency.sh.usage) |
| [`replace-vm-disk.sh`](../replace-vm-disk.sh) | [doc](replace-vm-disk.md) | [usage](replace-vm-disk.sh.usage) |
| [`resize-vm-disk.sh`](../resize-vm-disk.sh) | [doc](resize-vm-disk.md) | [usage](resize-vm-disk.sh.usage) |
| [`send-vm-export-and-restore.sh`](../send-vm-export-and-restore.sh) | [doc](send-vm-export-and-restore.md) | [usage](send-vm-export-and-restore.sh.usage) |
| [`set-vm-boot-disk.sh`](../set-vm-boot-disk.sh) | [doc](set-vm-boot-disk.md) | [usage](set-vm-boot-disk.sh.usage) |
| [`show-last-operation.sh`](../show-last-operation.sh) | [doc](show-last-operation.md) | [usage](show-last-operation.sh.usage) |
| [`show-thin-snapshot-tree.sh`](../show-thin-snapshot-tree.sh) | [doc](show-thin-snapshot-tree.md) | [usage](show-thin-snapshot-tree.sh.usage) |
| [`show-vm-filesystem-layout.sh`](../show-vm-filesystem-layout.sh) | [doc](show-vm-filesystem-layout.md) | [usage](show-vm-filesystem-layout.sh.usage) |
| [`show-vm-storage-map.sh`](../show-vm-storage-map.sh) | [doc](show-vm-storage-map.md) | [usage](show-vm-storage-map.sh.usage) |
| [`snapshot-disk-between-vms.sh`](../snapshot-disk-between-vms.sh) | [doc](snapshot-disk-between-vms.md) | [usage](snapshot-disk-between-vms.sh.usage) |
| [`sort-vm-disk-slots.sh`](../sort-vm-disk-slots.sh) | [doc](sort-vm-disk-slots.md) | [usage](sort-vm-disk-slots.sh.usage) |
| [`swap-vm-disks.sh`](../swap-vm-disks.sh) | [doc](swap-vm-disks.md) | [usage](swap-vm-disks.sh.usage) |
| [`unmount-all-vm-drives.sh`](../unmount-all-vm-drives.sh) | [doc](unmount-all-vm-drives.md) | [usage](unmount-all-vm-drives.sh.usage) |
| [`unmount-lvm-drives.sh`](../unmount-lvm-drives.sh) | [doc](unmount-lvm-drives.md) | [usage](unmount-lvm-drives.sh.usage) |
| [`verify-vm-disk-content.sh`](../verify-vm-disk-content.sh) | [doc](verify-vm-disk-content.md) | [usage](verify-vm-disk-content.sh.usage) |
| [`verify-vm-disk-numbering.sh`](../verify-vm-disk-numbering.sh) | [doc](verify-vm-disk-numbering.md) | [usage](verify-vm-disk-numbering.sh.usage) |
| [`verify-vm-storage-consistency.sh`](../verify-vm-storage-consistency.sh) | [doc](verify-vm-storage-consistency.md) | [usage](verify-vm-storage-consistency.sh.usage) |

The static suite verifies that all 81 public helpers have documentation and usage
snapshots, that every parser option appears in live help, and that the embedded
help in every documentation page exactly matches the executable command.

The 2026-08-22 v3.7.1 documentation audit independently re-ran `--help` for all
81 commands and reconfirmed **81/81** byte-for-byte matches between live output,
the corresponding `.usage` snapshot, and the embedded Markdown help block. It
also reconfirmed the 81-command README inventory, this index, and the current
test matrix. See [`V3.7.1-DOCUMENTATION-AUDIT.md`](V3.7.1-DOCUMENTATION-AUDIT.md).

[Back to README](../README.md)
