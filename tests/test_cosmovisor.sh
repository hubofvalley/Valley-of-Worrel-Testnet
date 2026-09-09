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
grep -q '3df6ef38cf976b00d226f391dc6866b8dc4040fc2f1b4a780d248f6e1cc9332e' "$installer"
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


# Compact Valley routing must accept 1g, and post-upgrade CLI calls must
# resolve through Cosmovisor's current binary rather than the stale direct one.
grep -q '^[[:space:]]*if \[\[ "\$option" =~ \^\[1-3\]\[a-z\]\$' "$menu"
grep -q 'WORRELL_HOME/cosmovisor/current/bin/worrelld' "$menu"

fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/.worrell/cosmovisor/current/bin"
touch "$fixture/.worrell/cosmovisor/current/bin/worrelld"
chmod +x "$fixture/.worrell/cosmovisor/current/bin/worrelld"
cat > "$fixture/unit" <<'EOF'
ExecStart=/home/test/go/bin/cosmovisor run start
EOF
awk '/^echo -e "\$LOGO"/{exit} {print}' "$menu" > "$fixture/functions.sh"
HOME="$fixture" WORRELL_HOME="$fixture/.worrell" WORRELL_SERVICE_NAME=worrelld bash -c '
  sudo() { if [ "$1" = systemctl ] && [ "$2" = cat ]; then cat "$HOME/unit"; else return 1; fi; }
  source "$HOME/functions.sh"
  test "$(worrell_bin)" = "$HOME/.worrell/cosmovisor/current/bin/worrelld"
'

# SDK-valid plan names may contain spaces; emergency staging must fail closed on conflicts.
helper_functions=$(mktemp)
trap 'rm -rf "$fixture" "$helper_functions"' EXIT
sed -n '/^valid_upgrade_name()/,/^}/p; /^valid_upgrade_height()/,/^}/p; /^preflight_emergency_upgrade()/,/^}/p' "$upgrade" > "$helper_functions"
source "$helper_functions"
valid_upgrade_name 'Worrell Upgrade 1'
! valid_upgrade_name ''
valid_upgrade_height 123
! valid_upgrade_height 0
mkdir -p "$fixture/home/cosmovisor/upgrades" "$fixture/home/data"
preflight_emergency_upgrade "$fixture/home" 'Worrell Upgrade 1'
touch "$fixture/home/data/upgrade-info.json"
! preflight_emergency_upgrade "$fixture/home" 'Worrell Upgrade 1'

echo 'Worrel Cosmovisor routing tests: PASS'
