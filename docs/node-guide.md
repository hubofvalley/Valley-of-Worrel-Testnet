# Worrell Testnet - Manual Node Guide

This guide translates the official Worrell runbook into the Valley paths. Re-check upstream before every live operation.

## Network facts

| Field | Value |
|---|---|
| Chain ID | `worrell-testnet-1` |
| Binary | `worrelld` |
| Release | `v0.1.2` (recommended upstream prerelease) |
| Home | `~/.worrell` |
| Denom | `uworrell` (6 decimals) |
| Minimum gas | `0.025uworrell` |
| SDK / consensus | Cosmos SDK `v0.53.6` / CometBFT |
| Genesis SHA256 | `a81c507b12ba0678c3172394ff4bb03e1c3db60050cc5568c127a24ec19378fd` |

Official source: [RUNNING-A-NODE.md](https://github.com/worrellchain/worrell/blob/main/docs/RUNNING-A-NODE.md).

## Install the binary

The recommended path is the official release tarball plus `release_checksum`:

```bash
mkdir -p "$HOME/go/bin" "$HOME/.cache/worrell"
cd "$HOME/.cache/worrell"
curl -fsSLO https://github.com/worrellchain/worrell/releases/download/v0.1.2/v0.1.2_linux_amd64.tar.gz
curl -fsSLO https://github.com/worrellchain/worrell/releases/download/v0.1.2/release_checksum
grep '  v0.1.2_linux_amd64.tar.gz$' release_checksum | sha256sum -c -
tar -xzf v0.1.2_linux_amd64.tar.gz
install worrelld "$HOME/go/bin/worrelld"
export PATH="$HOME/go/bin:$PATH"
worrelld version --long | head -5
```

Use the matching `linux_arm64` asset on ARM. A source build requires Go `1.25.10+`, git, make, and build-essential:

```bash
git clone https://github.com/worrellchain/worrell.git
cd worrell
git checkout v0.1.2
make install
```

## Initialise and join

```bash
export WORRELL_HOME="$HOME/.worrell"
worrelld init <moniker> --chain-id worrell-testnet-1 --home "$WORRELL_HOME"
curl -fsSL https://raw.githubusercontent.com/worrellchain/networks/main/worrell-testnet-1/genesis.json \
  -o "$WORRELL_HOME/config/genesis.json"
echo 'a81c507b12ba0678c3172394ff4bb03e1c3db60050cc5568c127a24ec19378fd  '"$WORRELL_HOME/config/genesis.json" | sha256sum -c -
worrelld genesis validate-genesis --home "$WORRELL_HOME"
```

Set the official peers in `config.toml`:

```toml
[p2p]
persistent_peers = "bb9164c1bd9ed9ff2c0fd9e09b23285698e231de@164.68.98.186:26656,40128ea31b1cfb5d4b24fc9e32ee0c468586c983@worrell-testnet-peer.itrocket.net:12656"

[rpc]
laddr = "tcp://127.0.0.1:26657"
```

Set `minimum-gas-prices = "0.025uworrell"` in `app.toml`. Valley can remap local RPC, P2P, ABCI, API, gRPC, and Prometheus ports with a two-digit prefix; the official peer ports remain unchanged.

## Start and sync

```bash
worrelld start --home "$WORRELL_HOME"
worrelld status --home "$WORRELL_HOME" 2>&1 | jq '.sync_info'
```

Create a validator only when `catching_up` is `false`. The official runbook states that state sync is enabled on the network, but no separate snapshot artifact is verified here.

## Key and validator

```bash
worrelld keys add <key-name> --home "$WORRELL_HOME"
worrelld keys show <key-name> -a --home "$WORRELL_HOME"
worrelld query bank balances "$(worrelld keys show <key-name> -a --home "$WORRELL_HOME")" --home "$WORRELL_HOME"
worrelld tendermint show-validator --home "$WORRELL_HOME"
```

The upstream example uses:

- amount: `20000000000000uworrell`
- commission rate: `0.05`
- commission max rate: `0.25`
- commission max change rate: `0.01`
- minimum self-delegation: `1000000` (`1 WORRELL`, not `1 uworrell`)

Review the generated JSON before submission:

```bash
worrelld tx staking create-validator validator.json \
  --from <key-name> --chain-id worrell-testnet-1 --home "$WORRELL_HOME" \
  --gas auto --gas-adjustment 1.5 --gas-prices 0.025uworrell --yes
```

Testnet faucet requests are manual and rate-limited by upstream. Never put a mnemonic or private key in a script, URL, issue, or chat.

## Service and monitoring

Use systemd with automatic restart and `LimitNOFILE=65536` or higher:

```bash
sudo systemctl status worrelld --no-pager
sudo journalctl -u worrelld -fn 100 -o cat
worrelld status --home "$WORRELL_HOME"
worrelld query slashing signing-info "$(worrelld tendermint show-address --home "$WORRELL_HOME")" --home "$WORRELL_HOME"
```

Never run two instances with the same `priv_validator_key.json`. Double-signing is materially worse than ordinary downtime.

## Ports

| Service | Default | Recommended exposure |
|---|---:|---|
| CometBFT P2P | 26656 | Public |
| CometBFT RPC | 26657 | Localhost / trusted IPs |
| ABCI | 26658 | Localhost |
| REST API | 1317 | Localhost unless protected |
| gRPC | 9090 | Localhost unless protected |
| Prometheus | 26660 | Localhost / monitoring network |

## Official endpoints

The upstream networks metadata publishes RPC, REST, gRPC, and explorer candidates. Valley displays them as candidates only; availability can change. See [usage.md](usage.md) and the upstream [network metadata](https://github.com/worrellchain/networks/tree/main/worrell-testnet-1).
