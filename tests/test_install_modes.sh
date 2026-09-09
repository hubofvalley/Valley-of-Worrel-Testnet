#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
installer="$repo/resources/worrelld_node_install_testnet.sh"
menu="$repo/resources/valleyofWorrel.sh"

bash -n "$installer" "$menu"
grep -q 'Install Cosmovisor for this deployment?' "$menu"
grep -q 'Interactive terminal required' "$menu"
grep -q 'Grand Valley' "$menu"
grep -q 'service_mode=direct' "$menu"
grep -q 'service_mode=cosmovisor' "$menu"
grep -q -- '--service-mode "$service_mode"' "$menu"
grep -q 'SERVICE_EXEC_START="$BINARY_DIR/worrelld start --home $HOME_DIR"' "$installer"
grep -q 'SERVICE_EXEC_START="$COSMOVISOR_BIN run start --home $HOME_DIR"' "$installer"
grep -q 'if \[ "$SERVICE_MODE" = cosmovisor \]' "$installer"

fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
for args in '--service-mode invalid' '--service-mode' '--unknown'; do
    if HOME="$fixture" bash "$installer" $args >"$fixture/out" 2>&1; then
        echo "installer unexpectedly accepted: $args" >&2
        exit 1
    fi
done
[ ! -e "$fixture/.bash_profile" ]

echo 'Worrel install mode tests: PASS'
