# Valley of Worrel - Usage Guide

## Run

Run the reviewed public launcher directly:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/hubofvalley/Valley-of-Worrel-Testnet/main/resources/valleyofWorrel.sh)
```

Run as the node OS user. Do not use `sudo bash`; the scripts request sudo only for packages, firewall, and systemd operations.

## Menu options

### 1. Node Interactions

| Option | Behaviour | Risk |
|---|---|---|
| `1a` | Deploys or redeploys the node through the audited installer. Backs up an existing `~/.worrell` before replacement. | High: replaces node data after confirmation. |
| `1b` | Updates the pinned `worrelld` release after checksum verification. | Medium: service restart/downtime. |
| `1c` | Shows local and public heights, chain ID, catching-up state, and block difference. | Read-only. |
| `1d` | Follows the selected service journal. | Read-only. |
| `1e` | Sets manual persistent peers or restores the two peers from official network metadata. | Medium: changes config. |
| `1f` | Queries an operator key balance. | Read-only. |

### 2. Validator / Key Interactions

| Option | Behaviour | Risk |
|---|---|---|
| `2a` | Lists keys or creates/recovers a key through `worrelld keys`. | Sensitive local key operation. |
| `2b` | Shows the consensus public key for validator creation. | Read-only. |
| `2c` | Builds a temporary validator JSON and submits `tx staking create-validator` only after explicit confirmation. | On-chain transaction. |
| `2d` | Submits `tx slashing unjail` after explicit confirmation. | On-chain transaction. |
| `2e` | Queries a validator's staking record. | Read-only. |

The menu does not automate faucet requests, delegation, or a Grand Valley validator choice. No verified Grand Valley Worrell validator or delegation endpoint was available during intake.

### 3. Node Management

| Option | Behaviour | Risk |
|---|---|---|
| `3a` | Restarts the selected systemd service. | Short downtime. |
| `3b` | Stops the selected systemd service. | Node offline until restarted. |
| `3c` | Creates a verified validator-key backup, then deletes the selected node home after typed confirmation. | Destructive. Refuses deletion if backup fails. |
| `3d` | Creates a mode-600 archive containing validator/node identity keys only. | Sensitive backup artifact. |

### 4. Endpoints

Prints Worrell links, network-registry RPC candidates, explorer candidates, faucet endpoint, and Grand Valley links. Endpoint availability is not guaranteed by this repository, and no Grand Valley Worrell endpoint or validator is claimed.

### 5. Guidelines

Shows navigation, key safety, port, backup, and validator reminders.

### 6. Exit

Leaves the menu. If the installer saved variables, run `source ~/.bash_profile` in a new shell.

## Recommended first-time flow

1. Review the installer and release checksum source.
2. Run `1a` as a dedicated node OS user.
3. Choose a two-digit port prefix from `10` through `64` if the default ports are occupied. Prefix `26` keeps consensus ports at 26656/26657/26658; API/gRPC/Prometheus are still remapped consistently.
4. Wait for `catching_up: false` in `1c`.
5. Use the official faucet manually if testnet funds are needed.
6. Create a validator only after checking the consensus key, balance, amount, commission, and minimum self-delegation.
7. Monitor logs and signing information continuously.

## Safety

- Use testnet-only keys and keep mnemonics offline.
- Never run two nodes with the same validator signing key.
- Do not expose RPC, REST, gRPC, or Prometheus publicly unless you understand the security impact.
- No official snapshot source was verified, so the menu intentionally does not offer snapshot application.
- `create-validator` and `unjail` are real transactions. Review the preview before confirming.
- The public endpoint list comes from upstream network metadata and may change.

last updated by: John
