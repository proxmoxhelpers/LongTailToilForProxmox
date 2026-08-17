# GitHub Publishing Checklist

Repository:

`proxmoxhelpers/Proxmox-LongTailToil`

## Recommended GitHub About text

> Fix for things that are too easy to automate, too hard to remember and don't happen often enough to bother

Suggested topics:

```text
proxmox
proxmox-ve
pve
lvm
lvm-thin
virtualization
sysadmin
shell
posix-shell
homelab
```

## Before the first public push

- [ ] Confirm the MIT copyright holder/name in `LICENSE`.
- [ ] Add the direct URL for the Proxmox forum thread that inspired the project, if desired.
- [ ] Decide whether `main` will be the default branch.
- [ ] Decide whether v3.1.0 should be tagged immediately as the first public release.
- [ ] Confirm the repository is public.
- [ ] Enable Issues if community bug reports are wanted.
- [ ] Enable GitHub private vulnerability reporting if available.
- [ ] Review `README.md`, `SECURITY.md` and `CONTRIBUTING.md`.
- [ ] Search the repository for accidental hostnames, IPs, credentials, tokens and private test output.
- [ ] Run the static suite one final time.
- [ ] Verify `SHA256SUMS`.

## Suggested initial Git commands

From the repository root:

```sh
git init
git branch -M main
git add .
git commit -m "Initial public release: Proxmox LongTail Toil v3.1.0"
git remote add origin https://github.com/proxmoxhelpers/Proxmox-LongTailToil.git
git push -u origin main
```

## Suggested first release

Tag:

```text
v3.1.0
```

Title:

```text
Proxmox LongTail Toil v3.1.0
```

Short release summary:

> First public integration-validated POSIX release. Includes 38 Proxmox/LVM helpers, project-wide dry-run support, grouped disposable integration tests, and the v3 shell/testing documentation.

Suggested commands:

```sh
git tag -a v3.1.0 -m "Proxmox LongTail Toil v3.1.0"
git push origin v3.1.0
```

## Repository settings worth enabling

- Require pull requests before merging to `main` if multiple maintainers will contribute.
- Require the **POSIX static tests** workflow to pass.
- Delete head branches automatically after merge.
- Enable Dependabot only if/when the repository gains dependencies that benefit from it.
- Enable private vulnerability reporting.
- Add the MIT license in GitHub repository metadata.
