# `bulk-change-vm-network.sh`

[Back to helper list](../README.md) · [View script](../bulk-change-vm-network.sh) · [Raw usage](./bulk-change-vm-network.sh.usage)

## Purpose

Apply the same bridge/tag/firewall settings to one NIC slot across multiple local QEMU VMs and LXC containers while preserving other NIC options; an optional model change applies to QEMU only and is ignored for LXC.

## Usage

Run the built-in help without performing the operation:

```sh
./bulk-change-vm-network.sh --help
```

The current built-in help is:

<!-- BEGIN LIVE HELP -->
```text
bulk-change-vm-network.sh 3.7.1 (project 3.7.1)

USAGE
  bulk-change-vm-network.sh <netN> <bridge> [--tag N|none] [--firewall 0|1] [--model MODEL] <vmid>... [dryrun]

DESCRIPTION
  Applies the requested NIC changes to one netN slot across local QEMU VMs
  and LXC containers while preserving unmodified NIC options.

OPTIONS
  --tag N       Set VLAN tag N.
  --tag none    Remove the existing VLAN tag.
  --firewall N  Set firewall=0 or firewall=1.
  --model MODEL Change the QEMU NIC model while preserving its MAC address.
                LXC uses veth NICs; --model is intentionally ignored for CTs.

NOTES
  Every listed guest must exist locally and already have the selected netN.
  QEMU changes use qm set; LXC changes use pct set.

HELP
  -h, -?, /h, /?, --help  Show this help and exit.
  --version                Show script and project versions and exit.

DRY-RUN
  Forms: dryrun, --dryrun.
  Dry-run: no system changes are made; modifying commands are printed instead of executed.
```
<!-- END LIVE HELP -->

The same output is stored verbatim in [`bulk-change-vm-network.sh.usage`](./bulk-change-vm-network.sh.usage).

## Test coverage

- Integration reference: `90-network.sh`
- The static suite verifies this helper's POSIX syntax, standalone help/version
  behavior, help aliases, documented parser options, live-help snapshot, and
  documentation synchronization.
- See [`tests/TEST-MATRIX.md`](../tests/TEST-MATRIX.md) for real/negative coverage.

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/LongTailToilForProxmox/main/bulk-change-vm-network.sh" -O "bulk-change-vm-network.sh" && chmod +x "bulk-change-vm-network.sh"
```

## Examples

```sh
./bulk-change-vm-network.sh net0 vmbr1 --tag 20 --firewall 1 123 124 125 dryrun
```
## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
bulk-change-vm-network.sh 3.7.1 (project 3.7.1)
```

This page documents the helper as shipped in project **v3.7.1**.
