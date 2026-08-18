# `bulk-change-vm-network.sh`

[Back to helper list](../README.md) · [View script](../bulk-change-vm-network.sh) · [Raw usage](./bulk-change-vm-network.sh.usage)

## Purpose

Apply the same bridge/tag/firewall/model settings to one NIC slot across multiple QEMU VMs.

## Usage

Run the built-in help without performing the operation:

```sh
./bulk-change-vm-network.sh --help
```

The current built-in help is:

```text
Usage: bulk-change-vm-network.sh <netN> <bridge> [--tag N|none] [--firewall 0|1] [--model MODEL] <vmid>... [dryrun]
Dry-run:
  Add dryrun or --dryrun anywhere on the command line.
  Read-only preflight checks still run, but modifying commands are printed
  instead of executed and mutation-dependent verification is simulated.
```

The same output is stored verbatim in [`bulk-change-vm-network.sh.usage`](./bulk-change-vm-network.sh.usage).

## Install this helper

```sh
wget -q "https://raw.githubusercontent.com/proxmoxhelpers/Proxmox-LongTailToil/main/bulk-change-vm-network.sh" -O "bulk-change-vm-network.sh" && chmod +x "bulk-change-vm-network.sh"
```

## Examples

```sh
./bulk-change-vm-network.sh net0 vmbr1 --tag 20 --firewall 1 123 124 125 dryrun
```

```sh
git clone https://github.com/proxmoxhelpers/Proxmox-LongTailToil.git && cd Proxmox-LongTailToil
```

```sh
./some-command.sh --help
```

```sh
./some-command.sh --version
```

```sh
vm-VMID-disk-N
base-VMID-disk-N
```

```sh
./tests/run-all-tests.sh --run --verbose
```

```sh
NO_COLOR=1 ./some-command.sh ...
```

## Safety and behavior

- Supports `dryrun` / `--dryrun`; preflight checks still run, mutations are printed instead of executed, and mutation-dependent verification is simulated.
- The real operation has a root/elevation gate, while `--help` and `--version` are available without passing that gate.
- Resolve ambiguous VM/storage/LV selections explicitly rather than relying on name guessing.
- Review the command output and verification result before making follow-up changes.

## Version

```text
bulk-change-vm-network.sh 3.0.0 (project 3.4.7)
```

This page documents the helper as shipped in project **v3.4.7**.
