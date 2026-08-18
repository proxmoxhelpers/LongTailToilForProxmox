# Destructive System-Test Safety Checklist

Use this checklist before enabling `--run` for a shell test suite that creates, renames, moves, mounts or deletes system resources.

## Before the run

- [ ] Plan-only mode is the default.
- [ ] `--run` is required explicitly.
- [ ] Root/elevation is checked before fixture creation.
- [ ] Required commands are checked before mutation.
- [ ] A unique run token has been generated.
- [ ] Sandbox/ownership directory is created and recorded.
- [ ] Protected pre-existing state is captured.
- [ ] Candidate VMIDs/CTIDs are proven unused.
- [ ] Candidate storage IDs are proven unused.
- [ ] Candidate VGs/LVs are proven unused.
- [ ] Existing backup paths that cleanup might touch are recorded.
- [ ] The harness does not select production objects by "first match".

## Fixture creation

- [ ] Loop devices point only to files created by this run.
- [ ] PV/VG/LV names contain the run token.
- [ ] Proxmox storage IDs contain the run token.
- [ ] Storage content types match QEMU/LXC use.
- [ ] QEMU fixtures pass `qm config`.
- [ ] LXC fixtures pass `pct config`.
- [ ] Every created resource is recorded immediately.
- [ ] Runtime tests use only disposable guests.
- [ ] Controller topology is intentional for hotplug tests.

## Before each mutating helper

- [ ] A test-owned state snapshot has been captured.
- [ ] Dry-run is executed first.
- [ ] Dry-run after-state equals before-state.
- [ ] Negative/refusal preconditions are constructed deliberately.
- [ ] The real operation targets only recorded test-owned objects.

## After each real helper

- [ ] Exit status matches the contract.
- [ ] Guest config matches the expected result.
- [ ] Guest runtime state matches the expected result.
- [ ] LV existence/nonexistence is verified.
- [ ] LV UUID is checked across rename/move where identity matters.
- [ ] Data bytes are compared when data movement occurred.
- [ ] Snapshot origin/pool is checked for linked snapshots.
- [ ] Mounts and mapper devices are checked for leaks.
- [ ] No unplanned storage reference remains.

## Cleanup

- [ ] Test mounts are removed first.
- [ ] Mapper devices are removed before underlying storage.
- [ ] Guest identity is revalidated before destroy.
- [ ] Every guest storage reference is still test-owned.
- [ ] Remaining guests block storage/VG deletion.
- [ ] Remaining storage definitions block VG/loop deletion.
- [ ] Existing pre-run backup paths are preserved.
- [ ] Any failed ownership proof stops cleanup at that layer.
- [ ] Ownership records are retained when cleanup is incomplete.

## After cleanup

- [ ] Protected after-state is captured even after setup/test failure.
- [ ] Protected baseline/after comparison is clean.
- [ ] Any anomaly is treated as a failure.
- [ ] Result logs are retained.
- [ ] Run summary distinguishes PASS / FAIL / SKIP / ANOMALY.
- [ ] A failed helper is classified as product, fixture, assertion or harness defect before changing tests.

## Release gate

Do not call a release integration-validated unless:

```text
all registered real cases passed
no protected-state anomaly occurred
no cleanup ownership error occurred
no fixture setup group aborted
```

> A safe destructive test suite must prove both that the product did the right thing and that the test harness itself did not touch the wrong thing.
