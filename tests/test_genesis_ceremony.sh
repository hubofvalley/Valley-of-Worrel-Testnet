#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
helper="$repo/resources/worrell_genesis_ceremony.sh"

bash -n "$helper"
grep -Fq 'readonly CHAIN_ID="worrell-testnet-2"' "$helper"
grep -Fq 'readonly PRE_GENESIS_SHA256="f5231dc924c762bdbe5aa0605ed6472288c9b71f4b175015e0559edccdd96b94"' "$helper"
grep -Fq 'readonly DEFAULT_PORT_PREFIX="${WORRELL_PORT_PREFIX:-18}"' "$helper"
grep -Fq 'final-genesis)' "$helper"
grep -Fq 'CREATE-GENTX' "$helper"
grep -Fq 'APPLY-FINAL-GENESIS' "$helper"

bash "$helper" --help | grep -q 'pre-genesis, gentx, final-genesis, interactive'
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

# Invalid final metadata fails before any download or mutation.
if HOME="$fixture" WORRELL_HOME="$fixture/.worrell-testnet-2" bash "$helper" --mode final-genesis --checksum bad --peers 'id@host:18656' >"$fixture/invalid.out" 2>&1; then
    echo 'invalid final checksum was accepted' >&2
    exit 1
fi
grep -q '64 hexadecimal' "$fixture/invalid.out"

# The [p2p] key is rewritten without touching another section.
sed '/^main "\$@"/,$d' "$helper" > "$fixture/functions.sh"
mkdir -p "$fixture/.worrell-testnet-2/config" "$fixture/bin"
cat > "$fixture/.worrell-testnet-2/config/config.toml" <<'EOF_CONFIG'
proxy_app = "tcp://127.0.0.1:18658"
[p2p]
persistent_peers = ""
[rpc]
laddr = "tcp://127.0.0.1:18657"
EOF_CONFIG
HOME="$fixture" WORRELL_HOME="$fixture/.worrell-testnet-2" bash -c 'set -e; source "$HOME/functions.sh"; config_file="$WORRELL_HOME/config/config.toml"; set_persistent_peers "abc@node.example:18656"'
grep -Fq 'persistent_peers = "abc@node.example:18656"' "$fixture/.worrell-testnet-2/config/config.toml"
grep -Fq 'laddr = "tcp://127.0.0.1:18657"' "$fixture/.worrell-testnet-2/config/config.toml"

# Genesis replacement must fail closed while the managed service is active.
cat > "$fixture/bin/systemctl" <<'EOF_SYSTEMCTL'
#!/usr/bin/env bash
if [ "${1:-}" = is-active ]; then
    printf '%s\n' active
    exit 0
fi
exit 1
EOF_SYSTEMCTL
chmod +x "$fixture/bin/systemctl"
if PATH="$fixture/bin:$PATH" HOME="$fixture" WORRELL_HOME="$fixture/.worrell-testnet-2" bash -c 'set -e; source "$HOME/functions.sh"; require_service_inactive'; then
    echo 'active service was accepted for genesis mutation' >&2
    exit 1
fi

# Gentx is preview-only until the exact confirmation phrase is entered.
printf '%s\n' '{"chain_id":"worrell-testnet-2"}' > "$fixture/.worrell-testnet-2/config/genesis.json"
cat > "$fixture/bin/worrelld" <<'EOF_BIN'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GENTX_CALLS"
EOF_BIN
chmod +x "$fixture/bin/worrelld"
HOME="$fixture" WORRELL_HOME="$fixture/.worrell-testnet-2" WORRELLD_BIN="$fixture/bin/worrelld" GENTX_CALLS="$fixture/calls" GENTX_KEY=operator GENTX_MONIKER=Testnet2 GENTX_IP=203.0.113.10 bash -c 'set -e; source "$HOME/functions.sh"; printf "no\n" | create_gentx'
[ ! -e "$fixture/calls" ]

echo 'Worrell genesis ceremony tests: PASS'
