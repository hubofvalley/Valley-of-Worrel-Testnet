# Valley of Worrell - Testnet

Interactive terminal toolkit by **Grand Valley** for deploying and managing a Worrell Testnet full node and validator.

> Official project spelling: **Worrell**. The Valley product name follows the official spelling: **Valley of Worrell**.

## Overview

**Valley of Worrell Testnet** is an open-source Grand Valley project for operating nodes and validators on the **Worrell** test network.

**Worrell** is a proof-of-stake blockchain built with Ignite CLI and the Cosmos SDK, using CometBFT consensus and focused on payments and energy infrastructure. The project includes staking and delegation, on-chain governance, dynamic inflation, and IBC support that is installed upstream but disabled at genesis while the network stabilises.

This Valley package turns the official Worrell node procedure into an auditable, interactive workflow. It covers node installation, configuration, syncing, peer management, validator/key operations, systemd lifecycle, and Cosmovisor-based upgrade preparation. The live Grand Valley RPC is published below; faucet automation and automatic transaction signing remain out of scope.

## Network

| Field | Value |
|---|---|
| Chain | Worrell Testnet |
| Chain ID | `worrell-testnet-1` |
| Binary | `worrelld` (`v0.1.2`, upstream prerelease) |
| Denomination | `uworrell` (1 WORRELL = 1,000,000 uworrell) |
| Node home | `~/.worrell` |
| Default service | `worrelld.service` |
| Default port prefix | `17` |
| Live P2P/RPC/ABCI | `17656` / `17657` / `17658` |
| Minimum gas price | `0.025uworrell` |

## Requirements

| Resource | Testnet recommendation |
|---|---|
| Operating system | Ubuntu 22.04 LTS |
| CPU | 2 vCPU |
| RAM | 4 GB |
| Storage | 100 GB SSD |
| Network | Stable connection; public P2P reachability |

## Run

Run the reviewed public launcher directly:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/hubofvalley/Valley-of-Worrel-Testnet/main/resources/valleyofWorrel.sh)
```

Run it as the OS user that owns the node. On a root-only RPC host, the installer now creates a dedicated `worrell` system user and stores the node under `/var/lib/worrell`; do not wrap the launcher in `sudo` when a normal node user exists.

## Features

- Valley of startup flow, menu, colour scheme, and safety prompts.
- Pinned upstream `v0.1.2` prerelease binary with release-checksum and asset-hash verification.
- Optional build-from-source path using the official Worrell repository.
- Official genesis download and `worrelld genesis validate-genesis` gate.
- Official persistent peers, configurable two-digit local port prefix, and optional UFW.
- Idempotent systemd service installation with ownership and backup checks.
- Selectable pruned or archive application-state storage, optional direct `worrelld` or Cosmovisor-managed service, and guarded pruned snapshot application from ITRocket or Sychonix. Cosmovisor automatic binary downloads remain disabled. The menu includes a predefined verified `v0.1.3` governance-upgrade staging option plus a custom release path; live runtime remains `v0.1.2` until the chain upgrade.
- Read-only status, logs, peer management, key/balance helpers, validator creation, guarded `tx staking delegate` delegation, and unjail flow.
- Snapshot application is available through a guarded pruned-snapshot flow; archive snapshots remain disabled until a provider is verified.
- Faucet requests remain manual; validator, delegation, and unjail transactions require a local preview and explicit operator confirmation.

## Documentation

- [Usage guide](docs/usage.md)
- [Manual node guide](docs/node-guide.md)
- [Version manifest](VERSIONS.json)
- [Cosmovisor upgrade guide](docs/cosmovisor.md)

## Live Grand Valley deployment

- RPC: `https://lightnode-rpc-worrell.grandvalleys.com`
- WebSocket: `wss://lightnode-rpc-worrell.grandvalleys.com/websocket`
- Direct P2P: `e812f08760b18ed774369e899763735f80179f76@peer-worrell.grandvalleys.com:17656`
- RPC node moniker: `grandvalley-lightnode`
- Default port prefix: `17` (`17656` P2P, `17657` RPC)
- Runtime: Cosmovisor with `UNSAFE_SKIP_BACKUP=true` by default; set `WORRELL_UNSAFE_SKIP_BACKUP=false` when rollback protection is required.

Peer traffic is direct TCP to port `17656`; it is not served through an Nginx HTTP or stream proxy.

## Official links

- [Worrell source](https://github.com/worrellchain/worrell)
- [Worrell node runbook](https://github.com/worrellchain/worrell/blob/main/docs/RUNNING-A-NODE.md)
- [Worrell network metadata](https://github.com/worrellchain/networks/tree/main/worrell-testnet-1)
- [Validator Telegram](https://t.me/worrellvalidators)
- [Worrell X](https://x.com/worrellchain)

## Connect with Grand Valley

- [GitHub](https://github.com/hubofvalley)
- [X](https://x.com/bacvalley)
- Email: letsbuidltogether@grandvalleys.com

## License

MIT. Review every script before running it on a server.

**Let's Buidl Worrell Together - Grand Valley**

last updated by: John
