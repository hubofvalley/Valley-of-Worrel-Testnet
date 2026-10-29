# Valley of Worrell - Testnet 2

Interactive terminal toolkit by **Grand Valley** for the separate `worrell-testnet-2` genesis-ceremony network.

> Official project spelling: **Worrell**. This repository is the Testnet 2 lane; it does not replace Testnet 1.

## Overview

**Worrell** is a proof-of-stake blockchain built with Ignite CLI and the Cosmos SDK, using CometBFT consensus. The official Testnet 2 rehearsal starts from a published pre-genesis, collects signed validator genesis transactions during a bounded window, and starts every participating validator from one coordinator-published final genesis.

This Valley package turns the official node and ceremony procedure into an auditable local workflow. It covers the separate node home, port mapping, v0.2.0 installation, pre-genesis verification, gentx preview and confirmation, final-genesis checksum/peer application, validator/key operations, and optional Cosmovisor preparation. It does not invent final peers, public RPCs, faucet details, or a final-genesis checksum before the coordinator publishes them.

Testnet 1 remains a separate network and is expected to run until **24 November 2026**. Do not reuse its `~/.worrell` home, service, signing key, genesis, or ports for Testnet 2.

## Network

| Field | Value |
|---|---|
| Chain | Worrell Testnet 2 |
| Chain ID | `worrell-testnet-2` |
| Binary | `worrelld` (`v0.2.0`) |
| Denomination | `uworrell` (1 WORRELL = 1,000,000 uworrell) |
| Node home | `~/.worrell-testnet-2` |
| Default service | `worrelld-testnet-2.service` |
| Default port prefix | `18` |
| Default P2P/RPC/ABCI | `18656` / `18657` / `18658` |
| Minimum gas price | `0.025uworrell` |
| Final genesis checksum | **UNKNOWN until published** |
| Final persistent peers | **UNKNOWN until published** |

The port prefix is a Valley-local default chosen to keep Testnet 2 beside Testnet 1. It is not a protocol parameter. RPC, API, gRPC, gRPC-Web, and Prometheus default to loopback; only P2P is public by default.

## Genesis ceremony

The official ceremony currently documents:

- pre-genesis window: 27 October 2026 10:00 UTC to 6 November 2026 10:00 UTC;
- final genesis publication: 7 November 2026;
- network start: 10 November 2026 08:00 UTC;
- Testnet 1 closes: 24 November 2026.

The Valley menu option `1i` / **Genesis ceremony** can:

1. fetch `pre-genesis.json` and verify SHA-256 `f5231dc924c762bdbe5aa0605ed6472288c9b71f4b175015e0559edccdd96b94`;
2. preview the exact gentx command and run it only after typing `CREATE-GENTX`;
3. apply final `genesis.json` only when the coordinator-supplied checksum and persistent peers are entered, then validate the local genesis.

The installer leaves the service disabled and stopped after installing pre-genesis. Do not start or enable a node as the final network until the published final genesis, checksum, peers, and `genesis_time` are available.

## Requirements

| Resource | Recommendation |
|---|---|
| Operating system | Ubuntu 22.04 LTS |
| CPU | 2 vCPU |
| RAM | 4 GB |
| Storage | 100 GB SSD |
| Network | Stable connection with public P2P reachability |

## Run

Run the reviewed public launcher as the node OS user:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/hubofvalley/Valley-of-Worrel-Testnet/main/resources/valleyofWorrel.sh)
```

Use the Testnet 2 home and service defaults. On a root-only host the installer uses `/var/lib/worrell-testnet-2`, the `worrell-testnet-2` service account, and `/etc/worrelld-testnet-2/worrelld.env`; it does not use the Testnet 1 service or home.

## Features

- Pinned official `v0.2.0` release tarballs with upstream `release_checksum` and asset-hash verification.
- Separate Testnet 2 home, service, default ports, and signer state.
- Verified official pre-genesis download and `worrelld genesis validate-genesis` gate.
- Gentx preview with explicit manual confirmation; no automatic key creation or submission.
- Final-genesis mode with required coordinator checksum and persistent peers.
- Optional direct `worrelld` or Cosmovisor service, with automatic binary downloads disabled.
- Read-only status/log helpers and guarded validator/key operations.

Final public RPCs, peers, faucet, explorers, and snapshot sources are **UNKNOWN** until official Testnet 2 metadata is published. Snapshot import is intentionally disabled until a chain-bound provider and checksum are verified; the menu never copies Testnet 1 endpoints.

## Documentation

- [Usage guide](docs/usage.md)
- [Manual node and ceremony guide](docs/node-guide.md)
- [Cosmovisor guide](docs/cosmovisor.md)
- [Version manifest](VERSIONS.json)

## Official links

- [Worrell source](https://github.com/worrellchain/worrell)
- [v0.2.0 release](https://github.com/worrellchain/worrell/releases/tag/v0.2.0)
- [Worrell node runbook](https://github.com/worrellchain/worrell/blob/main/docs/RUNNING-A-NODE.md)
- [Worrell Testnet 2 network metadata](https://github.com/worrellchain/networks/tree/main/worrell-testnet-2)
- [Genesis ceremony README](https://github.com/worrellchain/networks/blob/main/worrell-testnet-2/README.md)
- [Validator Telegram](https://t.me/worrellvalidators)

## Connect with Grand Valley

- [GitHub](https://github.com/hubofvalley)
- [X](https://x.com/bacvalley)
- Email: letsbuidltogether@grandvalleys.com

## License

MIT. Review every script before running it on a server.

**Let's Buidl Worrell Together - Grand Valley**

last updated by: John
