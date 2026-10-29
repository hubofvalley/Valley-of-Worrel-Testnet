# Valley of Worrell - Testnet 2 Usage Guide

This repository targets `worrell-testnet-2` only. Testnet 1 remains separate until 24 November 2026.

## Run

Run as the node OS user:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/hubofvalley/Valley-of-Worrel-Testnet/main/resources/valleyofWorrel.sh)
```

Do not use `sudo bash` when a normal node user exists. The default home is `~/.worrell-testnet-2`, the default service is `worrelld-testnet-2.service`, and the Valley-local default port prefix is `18`:

| Role | Default | Exposure |
|---|---:|---|
| CometBFT P2P | 18656 | Public |
| CometBFT RPC | 18657 | Loopback |
| ABCI | 18658 | Loopback |
| Prometheus | 18660 | Loopback |
| REST API | 18317 | Loopback |
| gRPC | 18090 | Loopback |
| gRPC-Web | 18091 | Loopback |

The prefix is local operator configuration, not a protocol parameter. The installer uses `/var/lib/worrell-testnet-2` and `/etc/worrelld-testnet-2/worrelld.env` in root-only mode.

## Menu options

| Option | Behaviour | Risk |
|---|---|---|
| `1a` | Installs or redeploys Testnet 2 with verified pre-genesis, v0.2.0, selected pruning, and direct/Cosmovisor runtime. The service is enabled but remains stopped until final genesis is applied. | High: replaces the node home after confirmation. |
| `1b` | Updates a direct `worrelld` binary after upstream checksum and v0.2.0 asset verification. | Medium: service restart/downtime. |
| `1c` | Shows local height, unknown/unavailable public height, chain ID, and catching-up status. | Read-only. |
| `1d` | Follows the configured service journal. | Read-only. |
| `1e` | Sets persistent peers manually. Coordinator peers remain UNKNOWN until final genesis is published. | Medium: changes config. |
| `1f` | Queries an operator key balance through the local RPC. | Read-only. |
| `1g` | Migrates to Cosmovisor, shows status, stages a verified future release, or verifies a staged hand-off. No Testnet 2 upgrade plan is assumed. | Medium/high. |
| `1h` | Runs the guarded snapshot helper. Snapshot providers for Testnet 2 are UNKNOWN until verified; do not copy Testnet 1 state. | High: replaces data after confirmation. |
| `1i` | Opens the genesis ceremony: verifies pre-genesis, previews/confirms gentx, or applies final genesis with a required checksum and peers. | High: changes genesis/config; gentx is signed. |
| `2a` | Lists, creates, or recovers keys. Mnemonics remain local and are shown only by the binary. | Sensitive local key operation. |
| `2b` | Shows the consensus public key. | Read-only. |
| `2c` | Previews and submits `create-validator` only after explicit confirmation and local sync checks. | On-chain transaction. |
| `2d` | Submits `unjail` only after explicit confirmation. | On-chain transaction. |
| `2e` | Queries validator status. | Read-only. |
| `2f` | Previews account balance and target validator, then submits `tx staking delegate` only after explicit confirmation. | On-chain transaction. |
| `3a` | Restarts the Testnet 2 service. | Short downtime. |
| `3b` | Stops the service. | Node offline until restarted. |
| `3c` | Creates a mode-600 signer/state backup, then deletes the exact managed Testnet 2 home only after safety checks and typed confirmation. | Destructive. |
| `3d` | Creates a mode-600 point-in-time signer/state archive without deleting the home. It is not an authoritative recovery snapshot; never restore its `priv_validator_state.json` after the node signs again. | Sensitive backup artifact. |
| `4` | Shows official source links, pre-genesis checksum, local ports, and explicit UNKNOWN final metadata. | Read-only. |
| `5` | Shows safety and Testnet 1 separation guidance. | Read-only. |
| `6` | Exits. | None. |

## Genesis ceremony flow

### Pre-genesis

`1i` -> `1` downloads:

```
https://raw.githubusercontent.com/worrellchain/networks/main/worrell-testnet-2/pre-genesis.json
```

and verifies:

```
f5231dc924c762bdbe5aa0605ed6472288c9b71f4b175015e0559edccdd96b94
```

The file is installed at $WORRELL_HOME/config/genesis.json. Existing files are backed up before replacement. The helper checks `chain_id` and does not start the service.

### Gentx preview and confirmation

Before `1i` -> `2`, initialise the separate home, create the operator key, and add the official allocation to the local pre-genesis as described by upstream. The Valley helper does not create keys, print mnemonics, or submit pull requests.

The preview uses the official ceremony parameters: chain ID `worrell-testnet-2`, denomination `uworrell`, self-delegation between `1000000uworrell` and `500000000uworrell`, default suggested self-delegation `495000000uworrell`, minimum commission `0.05`, maximum commission `0.20`, maximum daily change `0.01`, minimum self-delegation `1000000`, and the operator's public IP/port memo. It runs nothing until you type `CREATE-GENTX`.

Review `config/gentx/gentx-*.json` and submit it to the official network repository yourself. One gentx per operator account is expected by upstream.

### Final genesis

After the coordinator publishes final `genesis.json`, its exact SHA-256, and the persistent peers, use `1i` -> `3`. Enter the 64-character checksum and comma-separated peers. The helper fetches the URL, verifies the checksum and `chain_id`, previews the changes, requires `APPLY-FINAL-GENESIS`, updates only `[p2p] persistent_peers`, installs the final file, and runs `worrelld genesis validate-genesis`.

The Valley does not guess a final checksum, peers, faucet, RPC, or `genesis_time`. Start the service only at the published `genesis_time` and never reuse Testnet 1 signer material.

## First-time flow

1. Review the installer, helper scripts, and official ceremony README.
2. Run `1a`; keep the service stopped with verified pre-genesis.
3. Use `1i` to verify pre-genesis and prepare the gentx preview.
4. Create the operator account and add the upstream allocation to the local genesis.
5. Confirm the gentx only after reviewing every field; submit it manually upstream.
6. When final metadata is published, apply it with `1i` and verify the local genesis.
7. Start at the published `genesis_time`, then wait for `catching_up=false` before validator transactions.
8. Keep Testnet 1's `~/.worrell`, service, ports, and signer untouched until 24 November 2026.

## Safety

- Keep Testnet 1 and Testnet 2 homes, services, ports, and signing keys separate.
- Never put a mnemonic or private key in a script, URL, issue, or chat.
- Keep RPC, REST, gRPC, gRPC-Web, and Prometheus private unless protected.
- `create-validator`, delegation, and `unjail` are real transactions. Review the full preview before confirming.
- Never start two nodes with the same consensus signing key.
- A final-genesis checksum mismatch is a hard stop; download again from the official metadata and do not edit the file.

## Official sources

- [Worrell v0.2.0 release](https://github.com/worrellchain/worrell/releases/tag/v0.2.0)
- [Worrell node runbook](https://github.com/worrellchain/worrell/blob/main/docs/RUNNING-A-NODE.md)
- [Testnet 2 ceremony README](https://github.com/worrellchain/networks/blob/main/worrell-testnet-2/README.md)
- [Testnet 2 metadata](https://github.com/worrellchain/networks/tree/main/worrell-testnet-2)

last updated by: John
