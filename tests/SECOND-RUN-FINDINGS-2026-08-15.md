# Second Full Integration Run Findings — 2026-08-15

Target tested: **Proxmox LVM Tools v2.2.1**  
Follow-up release: **v2.2.2**

## Result summary

The second full Proxmox run was substantially cleaner than the first:

- 44 individual test cases executed;
- 43 individual cases passed;
- 1 individual case failed;
- the only command-level failure was `delete-disk-from-vm.sh`;
- every other command integration case passed;
- seven groups were marked failed only because the protected storage baseline still reported harmless `storage.cfg` list reordering as an anomaly.

The all-groups result of `3 passed / 7 failed` therefore overstated the remaining functional problem count. The group result intentionally treats any protected-state anomaly as a failure, which is the correct conservative policy; the comparator itself was still too strict.

## 1. `delete-disk-from-vm.sh` false failure after successful deletion

Observed output:

```text
Logical volume "vm-918806-disk-10" successfully removed.
Removed volume 'plvt-a-44718806:vm-918806-disk-10'
ERROR: Volume still resolves after deletion.
```

The delete itself succeeded.

The script then ran:

```bash
pvesm path "$VOLID"
```

and treated exit status `0` as proof that the volume still existed.

That assumption is invalid. `pvesm path` can construct the path implied by a syntactically valid Proxmox volume ID even after its backing LV has already been deleted.

### v2.2.2 correction

Before deletion, the script now records:

- storage ID;
- resolved backing path.

After `pvesm free`, verification now:

1. runs `pvesm list STORAGE --vmid VMID`;
2. requires the exact volume ID to be absent from that storage listing;
3. requires the previously resolved backing path to be absent.

A successful path synthesis is no longer treated as an existence test.

## 2. Protected storage anomalies were only unordered set serialization

Every attached `anomaly-storage.diff` was inspected.

No storage definition, storage ID, VG name, thin pool, path, or content member changed.

The differences were exclusively permutations such as:

```diff
-local-14tb-lvm|lvmthin|content|rootdir,images
+local-14tb-lvm|lvmthin|content|images,rootdir
```

and:

```diff
-local|dir|content|iso,backup,vztmpl
+local|dir|content|vztmpl,iso,backup
```

`pvesm add/remove` may rewrite these comma-separated sets in a different order.

### v2.2.2 correction

The storage canonicalizer now treats the known set-valued fields:

```text
content
nodes
```

as unordered sets.

Instead of comparing:

```text
content|images,rootdir
```

it emits sorted member records equivalent to:

```text
content|images
content|rootdir
```

This preserves useful anomaly detection:

- adding a content type still changes the baseline;
- removing a content type still changes the baseline;
- changing any scalar option still changes the baseline;
- adding/removing a storage still changes the baseline;
- merely reordering set members does not.

A static regression test now creates two synthetic `storage.cfg` files with differently ordered `content` and `nodes` values and requires their canonical forms to compare equal.

## 3. Static regression test emitted `$2: unbound variable`

The static group displayed:

```text
environment: line 1: $2: unbound variable
```

even though the case itself passed.

The test intentionally replaced `all_guest_configs()` with a stub, but the stub incorrectly referenced its own `$2` positional parameter even though `other_volume_references` calls `all_guest_configs` with no arguments.

Because that stub ran through process substitution, the background error did not make the outer assertion fail.

### v2.2.2 correction

The test now stores the fixture path in a named variable before defining the zero-argument stub.

The regression continues to verify that an empty `other_volume_references` result is valid successful data, but it no longer emits unrelated shell errors.

## 4. What passed in v2.2.1

The second run confirmed the previous fixes across real Proxmox operations.

Passing integration coverage included:

- volume ownership/orphan discovery;
- VM storage audit;
- independent LV copy;
- cross-VG LV move;
- LV rename/delete;
- direct LV mount/unmount;
- VM-slot mount and synthetic root detection;
- attach/detach and unused-disk cleanup;
- thin snapshots and independent VM disk copies;
- disk bus changes;
- disk swaps;
- boot-order changes;
- disk replacement;
- disk renumbering;
- volume-name repair;
- individual and bulk Proxmox storage moves;
- raw-image import;
- qcow2 export;
- storage-prefix rewrite;
- VMID change;
- diskless config cloning;
- VM recovery from volumes;
- bulk network changes.

Notably, the previous renumber, volume-name repair, VM recovery, unmount status, and cross-VG move issues all passed their real integration tests.

## 5. Expected next-run result

With the v2.2.2 corrections, the prior remaining failure classes should be removed:

- `delete-disk-from-vm.sh` should pass after a real deletion;
- harmless `content`/`nodes` ordering changes should no longer create protected-state anomalies;
- the static group should no longer print an unbound-variable diagnostic.

Any remaining failure on the next run should therefore be treated as new evidence rather than recurrence of the two known v2.2.1 issues.
