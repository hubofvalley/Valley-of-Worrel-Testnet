#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
menu="$repo/resources/valleyofWorrel.sh"
installer="$repo/resources/worrelld_node_install_testnet.sh"
updater="$repo/resources/worrelld_update.sh"

bash -n "$menu" "$installer" "$updater"
jq empty "$repo/VERSIONS.json"
! grep -R -nE '\{\{[A-Za-z_]+\}\}|__[A-Z_]+__|<<<<<<<|=======|>>>>>>>' "$repo/resources"
! grep -R -n '\${NC}' "$repo/resources"

a=$(sha256sum "$installer" | awk '{print $1}')
u=$(sha256sum "$updater" | awk '{print $1}')
grep -q "VALLEY_INSTALLER_SHA256=\"$a\"" "$menu"
grep -q "VALLEY_UPDATER_SHA256=\"$u\"" "$menu"
grep -q '10#\$1 >= 10' "$installer"
grep -q '10#\$1 <= 64' "$installer"
grep -q 'cd "$workdir"' "$installer"
grep -q 'cd "$workdir"' "$updater"
grep -q 'SSH Access' "$installer"
grep -q 'catching_up' "$menu"
grep -q 'min-self-delegation' "$menu"
grep -q 'Type DELETE' "$menu"

echo 'Worrel contract tests: PASS'
