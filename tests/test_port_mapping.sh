#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/.worrell-testnet-2/config"
cat > "$fixture/.worrell-testnet-2/config/config.toml" <<'EOF'
proxy_app = "tcp://127.0.0.1:26658"
[p2p]
laddr = "tcp://0.0.0.0:26656"
[rpc]
laddr = "tcp://127.0.0.1:26657"
[instrumentation]
prometheus_listen_addr = ":26660"
EOF
cat > "$fixture/.worrell-testnet-2/config/app.toml" <<'EOF'
minimum-gas-prices = "0stake"
pruning = "custom"
pruning-keep-recent = "100"
pruning-interval = "20"
[api]
address = "tcp://localhost:1317"
[grpc]
address = "localhost:9090"
[grpc-web]
address = "0.0.0.0:9091"
EOF
awk '/^if \[ ! -t 0 \]; then/{exit} {print}' "$repo/resources/worrelld_node_install_testnet.sh" > "$fixture/functions.sh"
HOME="$fixture" WORRELL_HOME="$fixture/.worrell-testnet-2" bash -c 'source "$HOME/functions.sh"; valid_prefix 10; valid_prefix 64; ! valid_prefix 09; ! valid_prefix 65; remap_config 38'
grep -q 'proxy_app = "tcp://127.0.0.1:38658"' "$fixture/.worrell-testnet-2/config/config.toml"
grep -q 'laddr = "tcp://0.0.0.0:38656"' "$fixture/.worrell-testnet-2/config/config.toml"
grep -q 'laddr = "tcp://127.0.0.1:38657"' "$fixture/.worrell-testnet-2/config/config.toml"
grep -q 'prometheus_listen_addr = "127.0.0.1:38660"' "$fixture/.worrell-testnet-2/config/config.toml"
grep -q 'address = "tcp://127.0.0.1:38317"' "$fixture/.worrell-testnet-2/config/app.toml"
grep -q 'address = "localhost:38090"' "$fixture/.worrell-testnet-2/config/app.toml"
grep -q 'address = "127.0.0.1:38091"' "$fixture/.worrell-testnet-2/config/app.toml"
grep -q 'minimum-gas-prices = "0.025uworrell"' "$fixture/.worrell-testnet-2/config/app.toml"
grep -q 'pruning = "custom"' "$fixture/.worrell-testnet-2/config/app.toml"
grep -q 'pruning-keep-recent = "100"' "$fixture/.worrell-testnet-2/config/app.toml"
grep -q 'pruning-interval = "20"' "$fixture/.worrell-testnet-2/config/app.toml"

echo 'Worrell port mapping tests: PASS'
