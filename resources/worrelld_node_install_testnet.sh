#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'
YELLOW='\033[0;33m'; ORANGE='\033[38;5;214m'; RESET='\033[0m'

# shellcheck disable=SC1091
source "$HOME/.bash_profile" 2>/dev/null || true
export PATH="$HOME/go/bin:$PATH"

readonly WORRELL_VERSION="${WORRELL_TARGET_VERSION:-v0.1.2}"
readonly CHAIN_ID="worrell-testnet-1"
readonly HOME_DIR="${WORRELL_HOME:-$HOME/.worrell}"
readonly BINARY_DIR="$HOME/go/bin"
readonly GENESIS_URL="https://raw.githubusercontent.com/worrellchain/networks/main/worrell-testnet-1/genesis.json"
readonly GENESIS_SHA256="a81c507b12ba0678c3172394ff4bb03e1c3db60050cc5568c127a24ec19378fd"
readonly PEERS="bb9164c1bd9ed9ff2c0fd9e09b23285698e231de@164.68.98.186:26656,40128ea31b1cfb5d4b24fc9e32ee0c468586c983@worrell-testnet-peer.itrocket.net:12656"

prompt_default() {
    local label="$1" default="$2" answer
    read -r -p "$label [$default]: " answer
    printf '%s' "${answer:-$default}"
}

valid_prefix() { [[ "$1" =~ ^[0-9]{2}$ ]] && ((10#$1 >= 10 && 10#$1 <= 64)); }
valid_service() { [[ "$1" =~ ^[A-Za-z0-9_.@-]+$ ]]; }

save_env() {
    local profile="$HOME/.bash_profile"
    touch "$profile"
    sed -i -E '/^export WORRELL_(CHAIN_ID|HOME|SERVICE_NAME|PORT_PREFIX|MONIKER|TARGET_VERSION)=/d' "$profile"
    {
        printf 'export WORRELL_CHAIN_ID=%q\n' "$CHAIN_ID"
        printf 'export WORRELL_HOME=%q\n' "$HOME_DIR"
        printf 'export WORRELL_SERVICE_NAME=%q\n' "$WORRELL_SERVICE_NAME"
        printf 'export WORRELL_PORT_PREFIX=%q\n' "$PORT_PREFIX"
        printf 'export WORRELL_MONIKER=%q\n' "$MONIKER"
        printf 'export WORRELL_TARGET_VERSION=%q\n' "$WORRELL_VERSION"
        printf 'export PATH="%s:$PATH"\n' "$BINARY_DIR"
    } >> "$profile"
}

set_toml_value() {
    local file="$1" key="$2" value="$3"
    if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$file"; then
        sed -i -E "s|^[[:space:]]*${key}[[:space:]]*=.*|${key} = ${value}|" "$file"
    else
        printf '\n%s = %s\n' "$key" "$value" >> "$file"
    fi
}

remap_config() {
    local prefix="$1" config="$HOME_DIR/config/config.toml" app="$HOME_DIR/config/app.toml"
    local p2p="${prefix}656" rpc="${prefix}657" abci="${prefix}658" prom="${prefix}660" api="${prefix}317" grpc="${prefix}090" grpc_web="${prefix}091"
    P2P_PORT="$p2p" RPC_PORT="$rpc" ABCI_PORT="$abci" PROM_PORT="$prom" API_PORT="$api" GRPC_PORT="$grpc" GRPC_WEB_PORT="$grpc_web" CONFIG="$config" APP="$app" python3 - <<'PY'
from pathlib import Path
import os

def rewrite(path, section_values):
    lines = Path(path).read_text().splitlines()
    section = ""
    out = []
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            section = stripped.strip("[]")
        for key, value in section_values.get(section, {}).items():
            if stripped.startswith(key) and "=" in stripped:
                indent = line[:len(line) - len(line.lstrip())]
                line = f"{indent}{key} = {value}"
                break
        out.append(line)
    Path(path).write_text("\n".join(out) + "\n")

rewrite(os.environ["CONFIG"], {
    "": {"proxy_app": f'"tcp://127.0.0.1:{os.environ["ABCI_PORT"]}"'},
    "p2p": {"laddr": f'"tcp://0.0.0.0:{os.environ["P2P_PORT"]}"'},
    "rpc": {"laddr": f'"tcp://127.0.0.1:{os.environ["RPC_PORT"]}"'},
    "instrumentation": {"prometheus_listen_addr": f'"127.0.0.1:{os.environ["PROM_PORT"]}"'},
})
rewrite(os.environ["APP"], {
    "api": {"address": f'"tcp://127.0.0.1:{os.environ["API_PORT"]}"'},
    "grpc": {"address": f'"localhost:{os.environ["GRPC_PORT"]}"'},
    "grpc-web": {"address": f'"127.0.0.1:{os.environ["GRPC_WEB_PORT"]}"'},
    "": {"minimum-gas-prices": '"0.025uworrell"'},
})
PY
}

install_prebuilt() {
    local os arch artifact workdir
    os=$(uname -s); arch=$(uname -m)
    [ "$os" = "Linux" ] || { echo -e "${RED}Prebuilt systemd install supports Linux only.${RESET}"; return 1; }
    case "$arch" in
        x86_64|amd64) artifact="${WORRELL_VERSION}_linux_amd64.tar.gz" ;;
        aarch64|arm64) artifact="${WORRELL_VERSION}_linux_arm64.tar.gz" ;;
        *) echo -e "${RED}Unsupported architecture: $arch${RESET}"; return 1 ;;
    esac
    workdir=$(mktemp -d)
    curl -fsSL "https://github.com/worrellchain/worrell/releases/download/${WORRELL_VERSION}/${artifact}" -o "$workdir/$artifact"
    curl -fsSL "https://github.com/worrellchain/worrell/releases/download/${WORRELL_VERSION}/release_checksum" -o "$workdir/release_checksum"
    (
        cd "$workdir"
        grep -E "[[:space:]]${artifact//./\\.}$" release_checksum | sha256sum -c -
    )
    if [ "$WORRELL_VERSION" = "v0.1.2" ]; then
        case "$artifact" in
            v0.1.2_linux_amd64.tar.gz) echo "1542bc561227ecd6bfb2d35f3bc81b8fd34e6f6db1404923b5bf5bd4b8303cd2  $workdir/$artifact" | sha256sum -c - ;;
            v0.1.2_linux_arm64.tar.gz) echo "3d4a9ffc754c39400c31af6599d030c2652914094a772f38e7a8284aafc7f58f  $workdir/$artifact" | sha256sum -c - ;;
        esac
    fi
    tar -xzf "$workdir/$artifact" -C "$workdir"
    install -Dm755 "$workdir/worrelld" "$BINARY_DIR/worrelld"
    rm -rf "$workdir"
}

install_from_source() {
    local src="$HOME/worrell-src"
    command -v go >/dev/null 2>&1 || { echo -e "${RED}Go 1.25.10+ is required for source builds.${RESET}"; return 1; }
    go_version=$(go version | awk '{print $3}' | sed 's/^go//')
    [ "$(printf '%s\n' 1.25.10 "$go_version" | sort -V | head -1)" = "1.25.10" ] || { echo -e "${RED}Go $go_version is too old; Go 1.25.10+ is required.${RESET}"; return 1; }
    if [ -d "$src/.git" ]; then git -C "$src" fetch --tags --quiet; else git clone https://github.com/worrellchain/worrell.git "$src"; fi
    git -C "$src" checkout "$WORRELL_VERSION"
    make -C "$src" install
    [ -x "$HOME/go/bin/worrelld" ]
}

read -r -p "Enter node moniker [Worrel-Grand-Valley]: " MONIKER
MONIKER=${MONIKER:-Worrel-Grand-Valley}
while true; do
    PORT_PREFIX=$(prompt_default 'Enter two-digit port prefix (26 keeps consensus defaults; API/gRPC become 26317/26090)' '26')
    valid_prefix "$PORT_PREFIX" && break
    echo -e "${RED}Use exactly two digits, for example 26 or 38.${RESET}"
done
WORRELL_SERVICE_NAME=${WORRELL_SERVICE_NAME:-}
while [ -z "$WORRELL_SERVICE_NAME" ]; do
    read -r -p "Enter service name [worrelld]: " WORRELL_SERVICE_NAME
    WORRELL_SERVICE_NAME=${WORRELL_SERVICE_NAME:-worrelld}
    valid_service "$WORRELL_SERVICE_NAME" || { echo -e "${RED}Invalid service name.${RESET}"; WORRELL_SERVICE_NAME=""; }
done
read -r -p "Enable UFW and allow P2P port ${PORT_PREFIX}656? (yes/no) [no]: " ENABLE_UFW
ENABLE_UFW=${ENABLE_UFW:-no}
SSH_PORT=$(prompt_default 'SSH TCP port to preserve in UFW' '22')
[[ "$SSH_PORT" =~ ^[0-9]+$ ]] && ((SSH_PORT >= 1 && SSH_PORT <= 65535)) || { echo -e "${RED}Invalid SSH port.${RESET}"; exit 1; }
read -r -p "Use prebuilt ${WORRELL_VERSION} binary? (yes/no) [yes]: " USE_PREBUILT
USE_PREBUILT=${USE_PREBUILT:-yes}

if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo -e "${RED}Run this installer as the node OS user, not root.${RESET}" >&2
    exit 1
fi
case "$HOME_DIR" in
    "$HOME/.worrell"|"$HOME"/*) ;;
    *) echo -e "${RED}Refusing node home outside the current user's home: $HOME_DIR${RESET}" >&2; exit 1 ;;
esac

sudo apt-get update
sudo apt-get install -y curl git jq build-essential wget lz4 unzip openssl ca-certificates
sudo systemctl stop "$WORRELL_SERVICE_NAME" 2>/dev/null || true
sudo systemctl disable "$WORRELL_SERVICE_NAME" 2>/dev/null || true
sudo rm -f "/etc/systemd/system/${WORRELL_SERVICE_NAME}.service"

if [ -d "$HOME_DIR" ]; then
    backup="$HOME/.worrell-backups/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$HOME/.worrell-backups"
    mv "$HOME_DIR" "$backup"
    echo -e "${YELLOW}Existing node home moved to $backup${RESET}"
fi
mkdir -p "$BINARY_DIR"
if [ "${USE_PREBUILT,,}" = "yes" ]; then install_prebuilt; else install_from_source; fi
command -v worrelld >/dev/null 2>&1 || export PATH="$BINARY_DIR:$PATH"
worrelld version --long | head -5
worrelld init "$MONIKER" --chain-id "$CHAIN_ID" --home "$HOME_DIR"
curl -fsSL "$GENESIS_URL" -o "$HOME_DIR/config/genesis.json"
echo "${GENESIS_SHA256}  $HOME_DIR/config/genesis.json" | sha256sum -c -
worrelld genesis validate-genesis --home "$HOME_DIR"

remap_config "$PORT_PREFIX"
sed -i -E "s|^[[:space:]]*persistent_peers[[:space:]]*=.*|persistent_peers = \"${PEERS}\"|" "$HOME_DIR/config/config.toml"

sudo tee "/etc/systemd/system/${WORRELL_SERVICE_NAME}.service" >/dev/null <<EOF
[Unit]
Description=Worrell Testnet node
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$USER
Group=$(id -gn)
WorkingDirectory=$HOME_DIR
ExecStart=$BINARY_DIR/worrelld start --home $HOME_DIR --chain-id $CHAIN_ID
Restart=on-failure
RestartSec=3
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

if [ "${ENABLE_UFW,,}" = "yes" ]; then
    sudo ufw allow "${SSH_PORT}/tcp" comment "SSH Access"
    sudo ufw allow "${PORT_PREFIX}656/tcp" comment "Worrell Testnet P2P"
    sudo ufw --force enable
fi
save_env
sudo systemctl daemon-reload
sudo systemctl enable --now "$WORRELL_SERVICE_NAME"
if sudo systemctl is-active --quiet "$WORRELL_SERVICE_NAME"; then
    echo -e "${GREEN}Worrel node installed and service is active.${RESET}"
else
    echo -e "${RED}Service did not become active. Inspect: sudo journalctl -u ${WORRELL_SERVICE_NAME} -n 100 --no-pager${RESET}" >&2
    exit 1
fi
echo -e "${CYAN}Home:${RESET} $HOME_DIR"
echo -e "${CYAN}RPC:${RESET} http://127.0.0.1:${PORT_PREFIX}657"
echo -e "${CYAN}Logs:${RESET} sudo journalctl -u ${WORRELL_SERVICE_NAME} -fn 100"
echo -e "${YELLOW}Reload saved variables with: source ~/.bash_profile${RESET}"
