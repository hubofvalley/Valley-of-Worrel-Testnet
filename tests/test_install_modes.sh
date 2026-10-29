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
grep -q 'WORRELL_ENV_FILE=/etc/worrelld-testnet-2/worrelld.env' "$installer"
grep -q 'fence_existing_service()' "$installer"
grep -q 'systemctl is-active' "$installer"
grep -q 'systemctl is-enabled' "$installer"
! grep -q 'systemctl enable' "$installer"
! grep -q 'systemctl stop.*|| true' "$installer"

fence_fixture=$(mktemp -d)
trap 'rm -rf "$fence_fixture"' EXIT
awk '/^fence_existing_service\(\) \{/,/^}/ {print}' "$installer" > "$fence_fixture/function.sh"
cat > "$fence_fixture/sudo" <<'EOF_SUDO'
#!/usr/bin/env bash
set -e
[ "${1:-}" = systemctl ] || exit 1
case "${2:-}" in
    disable) exit 0 ;;
    stop) [ "${FENCE_MODE:-}" != stop-fail ] ;;
    is-active)
        if [ "${FENCE_MODE:-}" = active ] || [ "${FENCE_MODE:-}" = stop-fail ]; then printf '%s\n' active; elif [ "${FENCE_MODE:-}" = state-error ]; then exit 1; else printf '%s\n' inactive; fi
        exit 3
        ;;
    is-enabled)
        printf '%s\n' not-found
        exit 1
        ;;
    *) exit 1 ;;
esac
EOF_SUDO
chmod +x "$fence_fixture/sudo"
{
    printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'WORRELL_SERVICE_NAME=worrelld-testnet-2' 'sudo() { "$FENCE_SUDO" "$@"; }'
    cat "$fence_fixture/function.sh"
    printf '%s\n' 'fence_existing_service'
} > "$fence_fixture/run-fence.sh"
chmod +x "$fence_fixture/run-fence.sh"
if FENCE_SUDO="$fence_fixture/sudo" PATH="$fence_fixture:$PATH" FENCE_MODE=stop-fail "$fence_fixture/run-fence.sh" >/dev/null 2>&1; then
    echo 'failed stop was not fail-closed' >&2
    exit 1
fi
if FENCE_SUDO="$fence_fixture/sudo" PATH="$fence_fixture:$PATH" FENCE_MODE=active "$fence_fixture/run-fence.sh" >/dev/null 2>&1; then
    echo 'active service after stop was accepted' >&2
    exit 1
fi
if FENCE_SUDO="$fence_fixture/sudo" PATH="$fence_fixture:$PATH" FENCE_MODE=state-error "$fence_fixture/run-fence.sh" >/dev/null 2>&1; then
    echo 'ambiguous service state was accepted' >&2
    exit 1
fi
FENCE_SUDO="$fence_fixture/sudo" PATH="$fence_fixture:$PATH" FENCE_MODE=inactive "$fence_fixture/run-fence.sh" >/dev/null
rm -rf "$fence_fixture"
grep -q 'install -m 0644 /dev/null "$env_file"' "$installer"
grep -q 'chown root:root "$env_file"' "$installer"
! grep -q 'chown "$SERVICE_USER:$SERVICE_GROUP" "$env_file"' "$installer"
for helper in "$repo/resources/worrelld_update.sh" "$repo/resources/cosmovisor_migration.sh" "$repo/resources/worrelld_cosmovisor_upgrade.sh" "$repo/resources/valleyofWorrel.sh"; do
    grep -q 'WORRELL_ENV_FILE=/etc/worrelld-testnet-2/worrelld.env' "$helper"
done
env_fixture=$(mktemp -d)
awk '/^validate_t2_environment\(\) \{/,/^}/ {print}' "$menu" > "$env_fixture/function.sh"
cat > "$env_fixture/run-env.sh" <<'EOF_ENV'
#!/usr/bin/env bash
set -euo pipefail
source "$ENV_FUNCTION"
RED= RESET=
WORRELL_CHAIN_ID=worrell-testnet-2
WORRELL_HOME="$HOME/.worrell-testnet-2"
WORRELL_ENV_FILE="$HOME/.worrell-testnet-2/.worrell-testnet-2.env"
WORRELL_SERVICE_NAME=worrelld-testnet-2
WORRELL_SERVICE_USER="$(id -un)"
WORRELL_PORT_PREFIX=18
WORRELL_TARGET_VERSION=v0.2.0
validate_t2_environment
WORRELL_CHAIN_ID=worrell-testnet-1
WORRELL_HOME="$HOME/.worrell"
WORRELL_ENV_FILE="$HOME/.worrell/.worrell-testnet-2.env"
WORRELL_SERVICE_NAME=worrelld
WORRELL_PORT_PREFIX=17
WORRELL_TARGET_VERSION=v0.1.2
if validate_t2_environment; then
    echo 'legacy profile environment was accepted' >&2
    exit 1
fi
EOF_ENV
chmod +x "$env_fixture/run-env.sh"
HOME="$env_fixture" ENV_FUNCTION="$env_fixture/function.sh" "$env_fixture/run-env.sh" >/dev/null 2>&1
rm -rf "$env_fixture"

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
