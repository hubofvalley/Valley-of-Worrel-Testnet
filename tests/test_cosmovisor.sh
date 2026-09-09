#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
menu="$repo/resources/valleyofWorrel.sh"
installer="$repo/resources/worrelld_node_install_testnet.sh"
migration="$repo/resources/cosmovisor_migration.sh"
upgrade="$repo/resources/worrelld_cosmovisor_upgrade.sh"

bash -n "$menu" "$installer" "$migration" "$upgrade"
grep -q 'releases/download/cosmovisor' "$installer"
grep -q 'SHA256SUMS-cosmovisor' "$installer"
grep -q 'ExecStart=\$COSMOVISOR_BIN run start' "$installer"
grep -q 'DAEMON_ALLOW_DOWNLOAD_BINARIES=false' "$installer"
grep -q 'UNSAFE_SKIP_BACKUP=false' "$installer"
grep -q 'data/upgrade-info.json' "$repo/docs/cosmovisor.md"
grep -q 'cosmovisor_migration.sh' "$menu"
grep -q 'worrelld_cosmovisor_upgrade.sh' "$menu"
grep -q 'VALLEY_COSMOVISOR_MIGRATION_SHA256' "$menu"
grep -q 'VALLEY_COSMOVISOR_UPGRADE_SHA256' "$menu"
grep -q '"cosmovisor"' "$repo/VALLEY.json"

echo 'Worrel Cosmovisor tests: PASS'
