# Valley of Worrel - Testnet

Interactive terminal toolkit by **Grand Valley** for deploying and managing a Worrell Testnet full node and validator.

> Official project spelling: **Worrell**. The Valley product name is **Valley of Worrel** to match the requested Grand Valley naming.

## Network

| Field | Value |
|---|---|
| Chain | Worrell Testnet |
| Chain ID | `worrell-testnet-1` |
| Binary | `worrelld` (`v0.1.2`, upstream prerelease) |
| Denomination | `uworrell` (1 WORRELL = 1,000,000 uworrell) |
| Node home | `~/.worrell` |
| Default service | `worrelld.service` |
| Default P2P/RPC/ABCI | `26656` / `26657` / `26658` |
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

Run it as the OS user that owns the node. Do not run the launcher with `sudo`.

## Features

- Valley of startup flow, menu, colour scheme, and safety prompts.
- Pinned upstream `v0.1.2` prerelease binary with release-checksum and asset-hash verification.
- Optional build-from-source path using the official Worrell repository.
- Official genesis download and `worrelld genesis validate-genesis` gate.
- Official persistent peers, configurable two-digit local port prefix, and optional UFW.
- Idempotent systemd service installation with ownership and backup checks.
- Read-only status, logs, peer management, key/balance helpers, validator creation, and unjail flow.
- No snapshot automation: no official Worrell Testnet snapshot source was verified.
- No automatic faucet or transaction signing: funds and signing remain operator-controlled.

## Documentation

- [Usage guide](docs/usage.md)
- [Manual node guide](docs/node-guide.md)
- [Version manifest](VERSIONS.json)

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

**Let's Buidl Worrel Together - Grand Valley**

last updated by: John
