#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/.worrell/config"
cat > "$fixture/.worrell/config/config.toml" <<'EOF'
proxy_app = "tcp://127.0.0.1:26658"
[p2p]
laddr = "tcp://0.0.0.0:26656"
[rpc]
laddr = "tcp://127.0.0.1:26657"
[instrumentation]
prometheus_listen_addr = ":26660"
EOF
cat > "$fixture/.worrell/config/app.toml" <<'EOF'
minimum-gas-prices = "0stake"
[api]
address = "tcp://localhost:1317"
[grpc]
address = "localhost:9090"
[grpc-web]
address = "0.0.0.0:9091"
EOF
awk '/^read -r -p "Enter node moniker/{exit} {print}' "$repo/resources/worrelld_node_install_testnet.sh" > "$fixture/functions.sh"
HOME="$fixture" WORRELL_HOME="$fixture/.worrell" bash -c 'source "$HOME/functions.sh"; valid_prefix 10; valid_prefix 64; ! valid_prefix 09; ! valid_prefix 65; remap_config 38'
grep -q 'proxy_app = "tcp://127.0.0.1:38658"' "$fixture/.worrell/config/config.toml"
grep -q 'laddr = "tcp://0.0.0.0:38656"' "$fixture/.worrell/config/config.toml"
grep -q 'laddr = "tcp://127.0.0.1:38657"' "$fixture/.worrell/config/config.toml"
grep -q 'prometheus_listen_addr = ":38660"' "$fixture/.worrell/config/config.toml"
grep -q 'address = "tcp://127.0.0.1:38317"' "$fixture/.worrell/config/app.toml"
grep -q 'address = "localhost:38090"' "$fixture/.worrell/config/app.toml"
grep -q 'address = "127.0.0.1:38091"' "$fixture/.worrell/config/app.toml"
grep -q 'minimum-gas-prices = "0.025uworrell"' "$fixture/.worrell/config/app.toml"

echo 'Worrel port mapping tests: PASS'
