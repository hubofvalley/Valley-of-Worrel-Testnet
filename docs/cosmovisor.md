# Cosmovisor Guide

Worrell's application includes the Cosmos SDK `x/upgrade` module and prioritises its upgrade pre-blocker. This makes it compatible with Cosmovisor's `data/upgrade-info.json` hand-off at an upgrade height.

## New installation

The Valley installer installs the pinned Cosmovisor release, initialises the current `worrelld` binary under `~/.worrell/cosmovisor/genesis/bin/`, and runs the service as:

```text
cosmovisor run start --home ~/.worrell --chain-id worrell-testnet-1
```

Automatic binary downloads remain disabled. This is intentional for validator safety.

## Existing node migration

1. Launch Valley of Worrel.
2. Select `1. Node Interactions` -> `g. Manage Cosmovisor`.
3. Select `1. Migrate current node to Cosmovisor`.
4. Confirm the service is active and inspect `sudo journalctl -u worrelld -fn 100`.

Migration stops the service briefly, preserves node data and `data/upgrade-info.json`, backs up the previous service unit, and restarts the service only if it was active before migration.

## Stage an upgrade binary

Select `Manage Cosmovisor` -> `Stage a verified upgrade binary`, then enter:

- the upstream Worrell release, for example `v0.1.2`;
- the exact governance upgrade plan name;
- an emergency upgrade height only when explicitly coordinated.

The helper downloads the architecture-specific release, verifies the upstream `release_checksum`, and calls `cosmovisor add-upgrade`. It does not restart the service. For governance upgrades, the plan name must match the on-chain name exactly. Never enable automatic binary downloads on a validator.

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
