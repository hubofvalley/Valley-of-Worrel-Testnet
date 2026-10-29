#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
menu="$repo/resources/valleyofWorrel.sh"
installer="$repo/resources/worrelld_node_install_testnet.sh"
updater="$repo/resources/worrelld_update.sh"
migration="$repo/resources/cosmovisor_migration.sh"
upgrade="$repo/resources/worrelld_cosmovisor_upgrade.sh"
snapshot="$repo/resources/apply_snapshot.sh"
genesis="$repo/resources/worrell_genesis_ceremony.sh"

bash -n "$menu" "$installer" "$updater" "$migration" "$upgrade" "$snapshot" "$genesis"
jq empty "$repo/VERSIONS.json"
grep -q '^## Overview$' "$repo/README.md"
grep -q 'Install Cosmovisor for this deployment' "$repo/resources/valleyofWorrel.sh"
grep -q 'VALLEY_GENESIS_CEREMONY_SHA256=' "$repo/resources/valleyofWorrel.sh"
grep -q 'Snapshot application is disabled' "$snapshot"
! grep -Eq 'ITRocket|Sychonix|server-3\.itrocket|snapshot\.sychonix' "$snapshot"
grep -q 'Grand Valley' "$repo/resources/valleyofWorrel.sh"
grep -qi 'proof-of-stake blockchain' "$repo/README.md"
! grep -R -nE '\{\{[A-Za-z_]+\}\}|__[A-Z_]+__|<<<<<<<|=======|>>>>>>>' "$repo/resources"
! grep -R -n '\${NC}' "$repo/resources"

a=$(sha256sum "$installer" | awk '{print $1}')
u=$(sha256sum "$updater" | awk '{print $1}')
m=$(sha256sum "$migration" | awk '{print $1}')
x=$(sha256sum "$upgrade" | awk '{print $1}')
g=$(sha256sum "$genesis" | awk '{print $1}')
grep -q "VALLEY_INSTALLER_SHA256=\"$a\"" "$menu"
grep -q "VALLEY_UPDATER_SHA256=\"$u\"" "$menu"
grep -q "VALLEY_COSMOVISOR_MIGRATION_SHA256=\"$m\"" "$menu"
grep -q "VALLEY_COSMOVISOR_UPGRADE_SHA256=\"$x\"" "$menu"
grep -q "VALLEY_GENESIS_CEREMONY_SHA256=\"$g\"" "$menu"
script_commit=$(sed -n 's/^readonly VALLEY_SCRIPT_COMMIT="\([0-9a-f]\{40\}\)"$/\1/p' "$menu")
[ -n "$script_commit" ]
git -C "$repo" cat-file -e "$script_commit^{commit}"
if git -C "$repo" diff --quiet HEAD -- resources/worrelld_node_install_testnet.sh resources/worrelld_update.sh resources/cosmovisor_migration.sh resources/worrelld_cosmovisor_upgrade.sh resources/worrell_genesis_ceremony.sh; then
    for helper in worrelld_node_install_testnet.sh worrelld_update.sh cosmovisor_migration.sh worrelld_cosmovisor_upgrade.sh worrell_genesis_ceremony.sh; do
        pinned=$(git -C "$repo" show "$script_commit:resources/$helper" | sha256sum | awk '{print $1}')
        case "$helper" in
            worrelld_node_install_testnet.sh) expected="$a" ;;
            worrelld_update.sh) expected="$u" ;;
            cosmovisor_migration.sh) expected="$m" ;;
            worrelld_cosmovisor_upgrade.sh) expected="$x" ;;
            worrell_genesis_ceremony.sh) expected="$g" ;;
        esac
        test "$pinned" = "$expected"
    done
elif [ "${VALLEY_ALLOW_UNPINNED_WORKTREE:-0}" = 1 ]; then
    echo 'Worrell helper pin check explicitly deferred for this uncommitted worktree.' >&2
else
    echo 'Worrell helper files changed; commit them and refresh VALLEY_SCRIPT_COMMIT before release.' >&2
    exit 1
fi
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
jq -e '.components[].capabilities | index("cosmovisor_handoff_verification")' "$repo/VALLEY.json" >/dev/null
grep -q 'Type DELETE' "$menu"
grep -q 'worrell-testnet-2' "$repo/resources/worrell_genesis_ceremony.sh"
grep -q 'CREATE-GENTX' "$repo/resources/worrell_genesis_ceremony.sh"
grep -q 'APPLY-FINAL-GENESIS' "$repo/resources/worrell_genesis_ceremony.sh"
grep -q 'genesis_ceremony' "$repo/VALLEY.json"

echo 'Worrell contract tests: PASS'
