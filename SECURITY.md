# Security Policy

These helpers can run as root and can modify Proxmox configuration, LVM storage, mounts and guest state. Treat safety regressions as security-sensitive even when they are not conventional remote vulnerabilities.

## Supported version

Security and destructive-safety fixes are targeted at the latest tagged release.

## Reporting a vulnerability or destructive-safety issue

Prefer GitHub's **private vulnerability reporting / Security Advisory** feature for issues that could cause data loss, privilege problems, command injection, unsafe path handling or exposure of sensitive host data.

If private reporting is not enabled, open a public issue containing only enough information to identify that a security-sensitive problem exists and request a private contact path. Do **not** publish working destructive exploits, credentials or private infrastructure details in a public issue.

For ordinary correctness bugs, use the normal bug-report template.

## Helpful report information

When safe to provide, include:

- helper name and project version;
- Proxmox VE version;
- storage backend/type;
- whether `dryrun` reproduces the problem;
- expected vs actual behavior;
- minimal redacted configuration;
- relevant test-group log or failure excerpt.

Do not include secrets, private keys, authentication tokens or unredacted production configuration.
