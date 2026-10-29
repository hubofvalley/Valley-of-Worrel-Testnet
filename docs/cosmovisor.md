# Cosmovisor Guide

Worrell's application includes the Cosmos SDK `x/upgrade` module and prioritises its upgrade pre-blocker. This makes it compatible with Cosmovisor's `data/upgrade-info.json` hand-off at an upgrade height.

## New installation

Pruning selection is independent of runtime selection. Snapshot application is also independent of runtime selection and does not change the Cosmovisor/direct service mode. Cosmovisor is optional during `1a` installation. The prompt is:

```text
Install Cosmovisor for this deployment? (yes/no) [no]:
```

- blank, `no`, or `n`: install a direct `worrelld` systemd service; no Cosmovisor download or initialisation occurs;
- `yes` or `y`: install the pinned Cosmovisor release, initialise `worrelld` under `~/.worrell-testnet-2/cosmovisor/genesis/bin/`, and run the service as:


```text
cosmovisor run start --home ~/.worrell-testnet-2
```

The chain ID is stored during node initialization. Worrell v0.2.0 rejects `--chain-id` on `start`, so the service intentionally passes only `--home` to the application.

The default is direct mode. The pruning choice made during installation is preserved by the runtime choice and is not changed by direct-to-Cosmovisor migration. Selecting direct mode does not uninstall an existing Cosmovisor binary. Selecting Cosmovisor keeps automatic binary downloads disabled for validator safety. To change an existing direct node without rebuilding its home, use the migration flow below. Re-running `1a` is a redeployment: existing node data is moved to a timestamped backup.

## Existing node migration

1. Launch Valley of Worrell.
2. Select `1. Node Interactions` -> `g. Manage Cosmovisor`.
3. Select `1. Migrate current node to Cosmovisor`.
4. Confirm the service is active and inspect `sudo journalctl -u worrel-testnet-2 -fn 100`.

Migration stops the service briefly, preserves node data and `data/upgrade-info.json`, backs up the previous service unit and shell profile, preserves the prior active/enabled state, and restarts the service only if it was active before migration. It refuses to migrate while a pending `data/upgrade-info.json` exists.

## Stage an upgrade binary

Select `Manage Cosmovisor` -> `Stage a verified upgrade binary` for a future, coordinator-published plan. Testnet 2 starts with the official `v0.2.0` binary; no upgrade plan, height, or release beyond `v0.2.0` is assumed in this repository. Enter the exact on-chain plan name and optional emergency height only when upstream publishes them.

The helper downloads the architecture-specific release, verifies it against the upstream `release_checksum`, and calls `cosmovisor add-upgrade`. Staging does not activate a binary or restart the service. Valley verifies the immutable helper script separately before execution. Governance plan names must match the on-chain name exactly. Never enable automatic binary downloads on a validator.

## Layout and environment

```text
$WORRELL_HOME/cosmovisor/
├── current -> genesis (or upgrades/<name>)
├── genesis/bin/worrelld
├── upgrades/<name>/bin/worrelld
└── backup/
```

For a normal node user, `$WORRELL_HOME` is `~/.worrell-testnet-2`; in root-only mode it is `/var/lib/worrell-testnet-2`.

The service sets `DAEMON_NAME=worrelld`, `DAEMON_HOME=$WORRELL_HOME`, `DAEMON_ALLOW_DOWNLOAD_BINARIES=false`, `DAEMON_RESTART_AFTER_UPGRADE=true`, `DAEMON_DATA_BACKUP_DIR=$WORRELL_HOME/cosmovisor/backup`, and `UNSAFE_SKIP_BACKUP=false` by default. This keeps Cosmovisor's application-data backup enabled for validator-capable installation and migration paths. A lightnode or other non-validator operator may explicitly opt in to skipping that backup with `WORRELL_UNSAFE_SKIP_BACKUP=true`; an existing explicit environment value is preserved.

## Verify the hand-off

Staging is not activation. After a successful staging run, `current` remains on the previously active binary until the chain's governance or emergency plan is handled. Use Valley -> Node Interactions -> Manage Cosmovisor -> **Verify staged or completed handoff**:

- **Verify staged binary before the upgrade** checks the exact plan name, staged `upgrades/<name>/bin/worrelld` executable and version, and confirms that `current` has not been promoted early.
- **Verify post-upgrade activation and recovery** requires `data/upgrade-info.json`, checks its exact plan name and optional height, requires `current` to resolve to the matching `upgrades/<name>`, checks the active binary version, and rejects an inactive service or restart loop.

The check is read-only and never deletes or rewrites `data/upgrade-info.json`. If `upgrade-info.json` is present but `current` still points to `genesis`, treat that as a failed hand-off: keep the file, inspect `sudo journalctl -u worrel-testnet-2 -n 100 --no-pager`, and recover only after the exact binary and plan have been verified.

## Recovery

- Check service logs first.
- Check `cosmovisor version` and run the hand-off verification for the exact release and plan.
- Verify the upgrade name, binary architecture, release checksum, `current` target, and executable version.
- Do not delete `data/upgrade-info.json` during recovery; it is the application's upgrade signal.
- Treat repeated restarts or a stale `current` target as a failed hand-off, not as proof that the upgrade is complete.
- If a migration needs rollback, stop the service and restore the timestamped service-unit backup after reviewing it.

Final genesis, peers, and future upgrade timing remain UNKNOWN until official Testnet 2 metadata is published.

last updated by: John
