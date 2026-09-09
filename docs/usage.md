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
| `1a` | Deploys or redeploys the node through the audited installer, then asks whether to use pruned or archive storage, and whether to run the service directly with `worrelld` or through pinned Cosmovisor. Backs up an existing `~/.worrell` before replacement. | High: replaces node data after confirmation. |
| `1b` | Updates the pinned `worrelld` release after checksum verification when the node is using the direct systemd binary. Cosmovisor-managed nodes are routed to `1g`. | Medium: service restart/downtime. |
| `1c` | Shows local and public heights, chain ID, catching-up state, and block difference. | Read-only. |
| `1d` | Follows the selected service journal. | Read-only. |
| `1e` | Sets manual persistent peers or restores the two peers from official network metadata. | Medium: changes config. |
| `1f` | Queries an operator key balance. | Read-only. |
| `1g` | Manages Cosmovisor: migrates an existing node, shows status, or stages a verified upgrade binary. | Medium/high: service unit changes or upgrade preparation. |

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
4. Choose pruning when prompted: blank/`p` uses custom pruning with keep recent `100` and interval `20`; `a` uses archive mode and retains application-state history.
5. Choose the install runtime: blank/`no` keeps the direct `worrelld` systemd service; `yes` installs pinned Cosmovisor with automatic downloads disabled. You can migrate a direct node later through `1g`.
6. Wait for `catching_up: false` in `1c`.
7. Use the official faucet manually if testnet funds are needed.
8. Create a validator only after checking the consensus key, balance, amount, commission, and minimum self-delegation.
9. Monitor logs and signing information continuously.

## Pruning

During `1a`, choose `p`/blank for pruned mode or `a` for archive mode. Pruned mode writes:

```toml
pruning = "custom"
pruning-keep-recent = "100"
pruning-interval = "20"
```

Archive mode writes `pruning = "nothing"` plus zero custom values, retaining application-state history and requiring substantially more disk space. Re-running `1a` is a redeployment: the old node home is moved to a timestamped backup, so changing modes does not restore history already deleted by a previous pruned database. Pruning is independent of direct/Cosmovisor runtime and is not changed by `1g` migration.

## Cosmovisor

Worrell's application wires the Cosmos SDK `x/upgrade` module, so the node can be run through Cosmovisor. During `1a`, choose the runtime explicitly: blank/`no` (the default) installs a direct `worrelld` service; `yes` installs and initialises pinned Cosmovisor. Existing direct-binary nodes can use `1g` -> **Migrate current node to Cosmovisor**.

Cosmovisor is optional at install time. Selecting direct mode does not uninstall an existing Cosmovisor binary, and selecting Cosmovisor does not enable automatic downloads. For a governance upgrade, stage the exact release and on-chain plan name with **Stage a verified upgrade binary**, then verify the prepared path and upgrade plan before the height. The optional emergency height is only for a coordinated local height-based upgrade and must be independently confirmed. The migration does not delete `data/upgrade-info.json` or node data.

Cosmovisor state is stored under `~/.worrell/cosmovisor/`:

```text
current -> genesis (or upgrades/<upgrade-name>)
genesis/bin/worrelld
upgrades/<upgrade-name>/bin/worrelld
backup/
```

## Safety

- Use testnet-only keys and keep mnemonics offline.
- Never run two nodes with the same validator signing key.
- Do not expose RPC, REST, gRPC, or Prometheus publicly unless you understand the security impact.
- No official snapshot source was verified, so the menu intentionally does not offer snapshot application.
- `create-validator` and `unjail` are real transactions. Review the preview before confirming.
- The public endpoint list comes from upstream network metadata and may change.

last updated by: John
