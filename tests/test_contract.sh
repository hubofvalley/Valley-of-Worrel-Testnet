#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
menu="$repo/resources/valleyofWorrel.sh"
installer="$repo/resources/worrelld_node_install_testnet.sh"
updater="$repo/resources/worrelld_update.sh"
migration="$repo/resources/cosmovisor_migration.sh"
upgrade="$repo/resources/worrelld_cosmovisor_upgrade.sh"
snapshot="$repo/resources/apply_snapshot.sh"

bash -n "$menu" "$installer" "$updater" "$migration" "$upgrade" "$snapshot"
jq empty "$repo/VERSIONS.json"
grep -q '^## Overview$' "$repo/README.md"
grep -q 'Install Cosmovisor for this deployment' "$repo/resources/valleyofWorrel.sh"
grep -q 'VALLEY_SNAPSHOT_SHA256=' "$repo/resources/valleyofWorrel.sh"
grep -q 'Apply Snapshot' "$repo/resources/valleyofWorrel.sh"
grep -q 'Grand Valley' "$repo/resources/valleyofWorrel.sh"
grep -qi 'proof-of-stake blockchain' "$repo/README.md"
! grep -R -nE '\{\{[A-Za-z_]+\}\}|__[A-Z_]+__|<<<<<<<|=======|>>>>>>>' "$repo/resources"
! grep -R -n '\${NC}' "$repo/resources"

a=$(sha256sum "$installer" | awk '{print $1}')
u=$(sha256sum "$updater" | awk '{print $1}')
m=$(sha256sum "$migration" | awk '{print $1}')
x=$(sha256sum "$upgrade" | awk '{print $1}')
v=$(sha256sum "$snapshot" | awk '{print $1}')
v=$(sha256sum "$repo/resources/apply_snapshot.sh" | awk '{print $1}')
grep -q "VALLEY_INSTALLER_SHA256=\"$a\"" "$menu"
grep -q "VALLEY_UPDATER_SHA256=\"$u\"" "$menu"
grep -q "VALLEY_COSMOVISOR_MIGRATION_SHA256=\"$m\"" "$menu"
grep -q "VALLEY_COSMOVISOR_UPGRADE_SHA256=\"$x\"" "$menu"
grep -q "VALLEY_SNAPSHOT_SHA256=\"$v\"" "$menu"
grep -q '10#\$1 >= 10' "$installer"
grep -q '10#\$1 <= 64' "$installer"
grep -q 'cd "$workdir"' "$installer"
grep -q 'cd "$workdir"' "$updater"
grep -q 'SSH Access' "$installer"
grep -q 'catching_up' "$menu"
grep -q 'min-self-delegation' "$menu"
grep -q 'tx staking delegate' "$menu"
grep -q 'Delegate to validator' "$menu"
! grep -q 'tx staking stake' "$menu"
jq -e '.components[].capabilities | index("staking_tx")' "$repo/VALLEY.json" >/dev/null
grep -q 'Type DELETE' "$menu"

echo 'Worrel contract tests: PASS'
