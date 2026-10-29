# Worrell Testnet 2 - Manual Node and Ceremony Guide

This guide follows the official [Testnet 2 ceremony README](https://github.com/worrellchain/networks/blob/main/worrell-testnet-2/README.md) and the [Worrell node runbook](https://github.com/worrellchain/worrell/blob/main/docs/RUNNING-A-NODE.md). Re-check the upstream files before every live operation. Testnet 1 remains separate until 24 November 2026.

## Network facts

| Field | Value |
|---|---|
| Chain ID | `worrell-testnet-2` |
| Binary | `worrelld` v0.2.0 |
| Home | `~/.worrell-testnet-2` |
| Denom | `uworrell` (6 decimals) |
| Minimum gas | `0.025uworrell` |
| Default P2P/RPC/ABCI | `18656` / `18657` / `18658` |
| Default REST/gRPC/gRPC-Web | `18317` / `18090` / `18091` |
| Pre-genesis SHA256 | `f5231dc924c762bdbe5aa0605ed6472288c9b71f4b175015e0559edccdd96b94` |
| Final genesis SHA256 | **UNKNOWN until published** |
| Final peers | **UNKNOWN until published** |

The default port prefix `18` is Valley-local and keeps this node beside Testnet 1. It is not an upstream protocol parameter.

## Install v0.2.0

The official release provides these Linux asset hashes:

| Tarball | SHA-256 |
|---|---|
| `v0.2.0_linux_amd64.tar.gz` | `1ccccd39d57467236a2f64ee4809fee4de3cc3f1bc02c47e3e22aa9c6b414c76` |
| `v0.2.0_linux_arm64.tar.gz` | `e4ad1e1bef4aa4656d03a543076d4cc08f91114a1cf93454218063f05992fb52` |

The Valley installer downloads the matching release asset and `release_checksum`, verifies both, and installs `worrelld`. A source build must use the official `v0.2.0` tag. Confirm:

```
worrelld version
# v0.2.0
```

## Initialise the separate home

Do not reuse `~/.worrell` or its validator key:

```
export WORRELL_HOME="$HOME/.worrell-testnet-2"
worrelld init <moniker> --chain-id worrell-testnet-2 --default-denom uworrell --home "$WORRELL_HOME"
```

The initializer creates the consensus and node keys under `$WORRELL_HOME/config/`. Back up `priv_validator_key.json` securely and never use this key in Testnet 1.

## Install and verify pre-genesis

The official pre-genesis is:

```
curl -fsSL https://raw.githubusercontent.com/worrellchain/networks/main/worrell-testnet-2/pre-genesis.json -o "$WORRELL_HOME/config/genesis.json"
echo 'f5231dc924c762bdbe5aa0605ed6472288c9b71f4b175015e0559edccdd96b94  '"$WORRELL_HOME/config/genesis.json" | sha256sum -c -
worrelld genesis validate-genesis --home "$WORRELL_HOME"
```

The Valley `1i` -> `1` flow performs the same download, checksum, and chain-ID checks. It backs up a different existing genesis before replacement.

## Create the operator account and gentx

Follow the upstream ceremony procedure. Create a key in the separate home and store its mnemonic offline:

```
worrelld keys add <key-name> --home "$WORRELL_HOME"
worrelld keys show <key-name> -a --home "$WORRELL_HOME"
worrelld genesis add-genesis-account <worrell1...> 500000000uworrell --home "$WORRELL_HOME"
```

The official gentx window accepts one gentx per account. The upstream suggested self-delegation is `495000000uworrell`; the allowed range is `1000000uworrell` to `500000000uworrell`. A gentx must use chain ID `worrell-testnet-2`, denomination `uworrell`, commission rate at least `0.05`, and a reachable IP/port memo.

The manual command shape is:

```
worrelld genesis gentx <key-name> 495000000uworrell --chain-id worrell-testnet-2 --moniker "<moniker>" --commission-rate 0.05 --commission-max-rate 0.20 --commission-max-change-rate 0.01 --min-self-delegation 1000000 --ip <public-ip-or-hostname> --p2p-port 18656 --home "$WORRELL_HOME"
```

Valley menu `1i` -> `2` previews this command and does not execute it until you type `CREATE-GENTX`. Review `config/gentx/gentx-*.json`, then submit it manually to the official `worrellchain/networks` repository. Valley does not open pull requests or submit keys.

## Apply final genesis

The coordinator publishes final `genesis.json`, its exact SHA-256, and persistent peers after the gentx window. Those values are currently **UNKNOWN**. Do not substitute the pre-genesis hash for the final hash.

When the values are published, use Valley `1i` -> `3`, or the helper directly:

```
resources/worrell_genesis_ceremony.sh --mode final-genesis --checksum <published-64-hex-sha256> --peers '<id>@<host>:<port>,<id>@<host>:<port>'
```

The helper fetches the official final URL, verifies the supplied checksum and `chain_id`, previews the URL/checksum/peers, requires `APPLY-FINAL-GENESIS`, updates only `[p2p] persistent_peers`, installs the file, and runs `worrelld genesis validate-genesis`. It restores the prior config/genesis if the final apply or local validation fails.

Do not edit `genesis.json` or `priv_validator_key.json`. If the checksum fails, stop and download again from the official metadata.

## Start and monitor

Start only after final genesis and the published `genesis_time` are available:

```
worrelld start --home "$WORRELL_HOME"
worrelld status --home "$WORRELL_HOME" 2>&1 | jq '.sync_info | {latest_block_height, catching_up}'
```

The Valley installer keeps `worrel-testnet-2.service` stopped after pre-genesis. The final-genesis helper also does not start it automatically. Start it manually at the coordinated time.

## Ports and service isolation

| Service | Default | Exposure |
|---|---:|---|
| CometBFT P2P | 18656 | Public direct TCP |
| CometBFT RPC | 18657 | Localhost/trusted IPs |
| ABCI | 18658 | Localhost |
| REST API | 18317 | Localhost unless protected |
| gRPC | 18090 | Localhost unless protected |
| gRPC-Web | 18091 | Localhost unless protected |
| Prometheus | 18660 | Localhost/monitoring network |

Use Valley's prefix prompt if these ports are occupied. Keep Testnet 1 on its existing ports and service. Never run both networks with the same consensus key.

## Validator and service safety

- Wait for `catching_up: false` before validator transactions.
- Keep RPC, REST, gRPC, gRPC-Web, and Prometheus private unless protected.
- Review `create-validator`, delegation, and `unjail` previews before explicit confirmation.
- Keep signer backups mode 600 and never restore an old signer state after the node signs again.
- No Testnet 2 faucet, public RPC, explorer, snapshot, or final peer list is asserted here until official metadata supplies it.

## Official sources

- [Worrell v0.2.0 release](https://github.com/worrellchain/worrell/releases/tag/v0.2.0)
- [Worrell node runbook](https://github.com/worrellchain/worrell/blob/main/docs/RUNNING-A-NODE.md)
- [Testnet 2 ceremony README](https://github.com/worrellchain/networks/blob/main/worrell-testnet-2/README.md)
- [Testnet 2 pre-genesis](https://raw.githubusercontent.com/worrellchain/networks/main/worrell-testnet-2/pre-genesis.json)

last updated by: John
