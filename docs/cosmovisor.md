# Cosmovisor Guide

Worrell's application includes the Cosmos SDK `x/upgrade` module and prioritises its upgrade pre-blocker. This makes it compatible with Cosmovisor's `data/upgrade-info.json` hand-off at an upgrade height.

## New installation

Pruning selection is independent of runtime selection. Snapshot application is also independent of runtime selection and does not change the Cosmovisor/direct service mode. Cosmovisor is optional during `1a` installation. The prompt is:

```text
Install Cosmovisor for this deployment? (yes/no) [no]:
```

- blank, `no`, or `n`: install a direct `worrelld` systemd service; no Cosmovisor download or initialisation occurs;
- `yes` or `y`: install the pinned Cosmovisor release, initialise `worrelld` under `~/.worrell/cosmovisor/genesis/bin/`, and run the service as:


```text
cosmovisor run start --home ~/.worrell
```

The chain ID is stored during node initialization. Worrell v0.1.2 rejects `--chain-id` on `start`, so the service intentionally passes only `--home` to the application.

The default is direct mode. The pruning choice made during installation is preserved by the runtime choice and is not changed by direct-to-Cosmovisor migration. Selecting direct mode does not uninstall an existing Cosmovisor binary. Selecting Cosmovisor keeps automatic binary downloads disabled for validator safety. To change an existing direct node without rebuilding its home, use the migration flow below. Re-running `1a` is a redeployment: existing node data is moved to a timestamped backup.

## Existing node migration

1. Launch Valley of Worrel.
2. Select `1. Node Interactions` -> `g. Manage Cosmovisor`.
3. Select `1. Migrate current node to Cosmovisor`.
4. Confirm the service is active and inspect `sudo journalctl -u worrelld -fn 100`.

Migration stops the service briefly, preserves node data and `data/upgrade-info.json`, backs up the previous service unit and shell profile, preserves the prior active/enabled state, and restarts the service only if it was active before migration. It refuses to migrate while a pending `data/upgrade-info.json` exists.

## Stage an upgrade binary

Select `Manage Cosmovisor` -> `Stage a verified upgrade binary`, then enter:

- the upstream Worrell release, for example `v0.1.2`;
- the exact governance upgrade plan name;
- an emergency upgrade height only when explicitly coordinated.

The helper downloads the architecture-specific release, verifies both the upstream `release_checksum` and Valley's pinned archive hash, and calls `cosmovisor add-upgrade`. Governance plan names may contain spaces; the helper does not impose a narrower SDK-incompatible grammar. It does not restart the service. For governance upgrades, the plan name must match the on-chain name exactly. Never enable automatic binary downloads on a validator.

## Layout and environment

```text
~/.worrell/cosmovisor/
├── current -> genesis (or upgrades/<name>)
├── genesis/bin/worrelld
├── upgrades/<name>/bin/worrelld
└── backup/
```

The service sets `DAEMON_NAME=worrelld`, `DAEMON_HOME=~/.worrell`, `DAEMON_ALLOW_DOWNLOAD_BINARIES=false`, `DAEMON_RESTART_AFTER_UPGRADE=true`, `DAEMON_DATA_BACKUP_DIR=~/.worrell/cosmovisor/backup`, and `UNSAFE_SKIP_BACKUP=false`.

## Recovery

- Check service logs first.
- Check `cosmovisor version` and the `current` symlink.
- Verify the upgrade name, binary architecture, and release checksum.
- Do not delete `data/upgrade-info.json` during recovery; it is the application's upgrade signal.
- If a migration needs rollback, stop the service and restore the timestamped service-unit backup after reviewing it.
