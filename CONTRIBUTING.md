# Contributing

Contributions are welcome when they keep the project focused on **long-tail Proxmox toil**: infrequent operations that are simple enough to automate but awkward or risky enough that people repeatedly reconstruct them by hand.

## Before opening a pull request

Please read:

- [`docs/POSIX-SHELL-STYLE-GUIDE-v3.md`](docs/POSIX-SHELL-STYLE-GUIDE-v3.md)
- [`docs/STYLE-PROFILES-AND-EXCEPTIONS.md`](docs/STYLE-PROFILES-AND-EXCEPTIONS.md)
- [`tests/README.md`](tests/README.md)
- [`tests/TEST-MATRIX.md`](tests/TEST-MATRIX.md)

Project shell entry points target:

```sh
#!/bin/sh
set -eu
```

Do not introduce Bash-only syntax unless the project explicitly adopts a documented exception.

## Safety requirements

A mutating helper should normally:

- support `dryrun` and `--dryrun`;
- complete as much read-only preflight as possible before mutation;
- refuse ambiguous storage/device identity;
- preserve quoted arguments;
- avoid weakening destructive confirmation or ownership checks;
- plan rollback before multi-step mutation;
- verify important postconditions;
- avoid blanket suppression of LVM/Proxmox errors;
- avoid sparse writes to regular LVs unless zero-initialization is guaranteed;
- leave unrelated host state untouched.

For changes to existing helpers, preserve the tested behavior unless the pull request explicitly explains why the behavior is changing.

## Tests

Run the static suite on any ordinary Linux development host:

```sh
./tests/groups/00-static-cli.sh --run
```

On a disposable/appropriate Proxmox VE host, run the complete integration suite:

```sh
./tests/run-all-tests.sh --run --verbose
```

Changes that affect a mutating command should include or update an integration case. A real-system test must operate only on test-owned fixtures and must return protected state to baseline.

## Pull requests

Keep pull requests narrow where practical. Include:

- the problem/use case;
- the safety assumptions;
- the dry-run behavior;
- the real mutation path;
- verification/rollback behavior;
- test evidence.

Avoid unrelated formatting churn in safety-sensitive transaction code.

## Commit and release hygiene

Do not commit:

- private VM configurations;
- hostnames/IPs you do not intend to publish;
- passwords, API tokens, SSH keys or cookies;
- production test logs containing sensitive metadata;
- generated release archives.

By contributing, you agree that your contribution is provided under the repository's [MIT License](LICENSE).
