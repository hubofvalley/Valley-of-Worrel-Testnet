#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
installer="$repo/resources/worrelld_node_install_testnet.sh"
menu="$repo/resources/valleyofWorrel.sh"

bash -n "$installer" "$menu"
grep -q 'Install Cosmovisor for this deployment?' "$menu"
grep -q 'Interactive terminal required' "$menu"
grep -q 'Grand Valley' "$menu"
grep -q "| '__|" "$menu"
grep -q "| '_" "$menu"
python3 - "$menu" <<'PYLOGO'
from pathlib import Path
import sys
s = Path(sys.argv[1]).read_text()
start = s.index("LOGO=$(cat <<'EOF'")
end = s.index("\nEOF\n)", start)
lines = s[start:end].splitlines()[1:]
assert all(ord(c) < 128 for line in lines for c in line)
assert max(map(len, lines)) <= 79
assert "Grand Valley" in s[start:end]
PYLOGO
grep -q 'service_mode=direct' "$menu"
grep -q 'service_mode=cosmovisor' "$menu"
grep -q -- '--pruning-mode "$pruning_mode"' "$menu"
grep -q -- '--service-mode "$service_mode"' "$menu"
grep -q 'SERVICE_EXEC_START="$BINARY_DIR/worrelld start --home $HOME_DIR"' "$installer"
grep -q 'SERVICE_EXEC_START="$COSMOVISOR_BIN run start --home $HOME_DIR"' "$installer"
grep -q 'if \[ "$SERVICE_MODE" = cosmovisor \]' "$installer"
grep -q 'ROOT_MODE=yes' "$installer"
grep -q 'SERVICE_USER=.*worrell' "$installer"
grep -q '/var/lib/\$SERVICE_USER' "$installer"
grep -q 'User=\$SERVICE_USER' "$installer"
grep -q 'GOBIN="\$BINARY_DIR" make' "$installer"
grep -q 'WORRELL_ENV_FILE=' "$installer"
grep -q 'write_runtime_env()' "$installer"
grep -q 'export WORRELL_SERVICE_USER=' "$installer"
grep -q 'export WORRELL_BINARY_DIR=' "$installer"
grep -q 'sudo() { "\$@"; }' "$installer"
grep -q 'ROOT_MODE=yes' "$repo/resources/worrelld_update.sh"
grep -q 'ROOT_MODE=yes' "$repo/resources/cosmovisor_migration.sh"
grep -q 'ROOT_MODE=yes' "$repo/resources/worrelld_cosmovisor_upgrade.sh"
grep -q 'fix_node_ownership()' "$repo/resources/apply_snapshot.sh"
grep -q 'WORRELL_ENV_FILE=/etc/worrelld/worrelld.env' "$installer"
grep -q 'install -m 0644 /dev/null "$env_file"' "$installer"
grep -q 'chown root:root "$env_file"' "$installer"
! grep -q 'chown "$SERVICE_USER:$SERVICE_GROUP" "$env_file"' "$installer"
for helper in "$repo/resources/worrelld_update.sh" "$repo/resources/cosmovisor_migration.sh" "$repo/resources/worrelld_cosmovisor_upgrade.sh" "$repo/resources/apply_snapshot.sh" "$repo/resources/valleyofWorrel.sh"; do
    grep -q 'WORRELL_ENV_FILE=/etc/worrelld/worrelld.env' "$helper"
done
python3 - "$repo/resources/apply_snapshot.sh" <<'PYROOT'
from pathlib import Path
import sys
s = Path(sys.argv[1]).read_text()
apply = s[s.index('state_backup='):s.index('echo -e "${GREEN}Snapshot applied successfully.')]
install_idx = apply.index('    if ! install -m 0600 "$state_backup" "$old_data/priv_validator_state.json"')
assert apply.find('    fix_node_ownership "$old_data"', install_idx) > install_idx
rollback = s[s.index('rollback_snapshot()'):s.index('wait_for_healthy_service()')]
assert rollback.index('install -m 0600 "$fresh_state" "$old_data/priv_validator_state.json"') < rollback.index('fix_node_ownership "$old_data"', rollback.index('install -m 0600 "$fresh_state"'))
PYROOT

fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
for args in '--service-mode invalid' '--service-mode' '--unknown'; do
    if HOME="$fixture" bash "$installer" $args >"$fixture/out" 2>&1; then
        echo "installer unexpectedly accepted: $args" >&2
        exit 1
    fi
done
[ ! -e "$fixture/.bash_profile" ]

echo 'Worrell install mode tests: PASS'
