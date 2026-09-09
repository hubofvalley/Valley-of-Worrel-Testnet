#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[0;33m'; RESET='\033[0m'
# shellcheck disable=SC1091
source "$HOME/.bash_profile" 2>/dev/null || true
export PATH="$HOME/go/bin:$PATH"

readonly HOME_DIR="${WORRELL_HOME:-$HOME/.worrell}"
readonly SERVICE="${WORRELL_SERVICE_NAME:-worrelld}"
readonly CHAIN_ID="${WORRELL_CHAIN_ID:-worrell-testnet-1}"
readonly BINARY_DIR="$HOME/go/bin"
readonly COSMOVISOR_VERSION="${WORRELL_COSMOVISOR_VERSION:-v1.7.3}"
readonly COSMOVISOR_BIN="$BINARY_DIR/cosmovisor"

[ "${EUID:-$(id -u)}" -ne 0 ] || { echo -e "${RED}Run as the node OS user, not root.${RESET}" >&2; exit 1; }
[ -x "$BINARY_DIR/worrelld" ] || { echo -e "${RED}Missing $BINARY_DIR/worrelld. Install Worrell first.${RESET}" >&2; exit 1; }
[ -d "$HOME_DIR/config" ] || { echo -e "${RED}Missing node home: $HOME_DIR${RESET}" >&2; exit 1; }

export DAEMON_NAME=worrelld
export DAEMON_HOME="$HOME_DIR"

install_cosmovisor() {
    local artifact workdir
    case "$(uname -m)" in
        x86_64|amd64) artifact="cosmovisor-${COSMOVISOR_VERSION}-linux-amd64.tar.gz" ;;
        aarch64|arm64) artifact="cosmovisor-${COSMOVISOR_VERSION}-linux-arm64.tar.gz" ;;
        *) echo -e "${RED}Unsupported architecture for Cosmovisor.${RESET}" >&2; return 1 ;;
    esac
    workdir=$(mktemp -d)
    trap 'rm -rf "$workdir"' RETURN
    curl -fsSL "https://github.com/cosmos/cosmos-sdk/releases/download/cosmovisor/${COSMOVISOR_VERSION}/${artifact}" -o "$workdir/$artifact"
    curl -fsSL "https://github.com/cosmos/cosmos-sdk/releases/download/cosmovisor/${COSMOVISOR_VERSION}/SHA256SUMS-cosmovisor-${COSMOVISOR_VERSION}.txt" -o "$workdir/SHA256SUMS"
    (
        cd "$workdir"
        grep -E "^[0-9a-fA-F]{64}[[:space:]]+${artifact//./\.}$" SHA256SUMS | sha256sum -c -
    )
    tar -xzf "$workdir/$artifact" -C "$workdir"
    install -Dm755 "$workdir/cosmovisor" "$COSMOVISOR_BIN"
    [ -x "$COSMOVISOR_BIN" ] || { echo -e "${RED}Cosmovisor installation failed.${RESET}" >&2; return 1; }
}

was_active=no
if sudo systemctl is-active --quiet "$SERVICE"; then
    was_active=yes
fi

echo -e "${YELLOW}This migrates ${SERVICE}.service to Cosmovisor without deleting node data or upgrade-info.json.${RESET}"
sudo systemctl stop "$SERVICE" 2>/dev/null || true

install_cosmovisor

if [ ! -x "$HOME_DIR/cosmovisor/current/bin/worrelld" ]; then
    cosmovisor init "$BINARY_DIR/worrelld"
fi
mkdir -p "$HOME_DIR/cosmovisor/upgrades" "$HOME_DIR/cosmovisor/backup"

backup="$HOME/.worrell-backups/cosmovisor-service-$(date +%Y%m%d-%H%M%S).service"
mkdir -p "${backup%/*}"
if sudo test -f "/etc/systemd/system/${SERVICE}.service"; then
    sudo cp -p "/etc/systemd/system/${SERVICE}.service" "$backup"
fi

sudo tee "/etc/systemd/system/${SERVICE}.service" >/dev/null <<EOF
[Unit]
Description=Cosmovisor Worrell Testnet Node
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$USER
Group=$(id -gn)
WorkingDirectory=$HOME_DIR
ExecStart=$COSMOVISOR_BIN run start --home $HOME_DIR --chain-id $CHAIN_ID
StandardOutput=journal
StandardError=journal
Restart=on-failure
RestartSec=3
LimitNOFILE=65536
Environment="DAEMON_NAME=worrelld"
Environment="DAEMON_HOME=$HOME_DIR"
Environment="DAEMON_ALLOW_DOWNLOAD_BINARIES=false"
Environment="DAEMON_RESTART_AFTER_UPGRADE=true"
Environment="DAEMON_DATA_BACKUP_DIR=$HOME_DIR/cosmovisor/backup"
Environment="UNSAFE_SKIP_BACKUP=false"

[Install]
WantedBy=multi-user.target
EOF

profile="$HOME/.bash_profile"
touch "$profile"
sed -i -E '/^export (DAEMON_NAME|DAEMON_HOME|DAEMON_DATA_BACKUP_DIR|WORRELL_COSMOVISOR_VERSION)=/d' "$profile"
{
    printf 'export DAEMON_NAME=%q\n' "$DAEMON_NAME"
    printf 'export DAEMON_HOME=%q\n' "$DAEMON_HOME"
    printf 'export DAEMON_DATA_BACKUP_DIR=%q\n' "$HOME_DIR/cosmovisor/backup"
    printf 'export WORRELL_COSMOVISOR_VERSION=%q\n' "$COSMOVISOR_VERSION"
} >> "$profile"

sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE"
if [ "$was_active" = yes ]; then
    sudo systemctl start "$SERVICE"
    sudo systemctl is-active --quiet "$SERVICE"
fi

echo -e "${GREEN}Cosmovisor migration completed.${RESET}"
echo -e "${CYAN}Version:${RESET} $COSMOVISOR_VERSION"
echo -e "${CYAN}Home:${RESET} $HOME_DIR"
echo -e "${CYAN}Backup:${RESET} $HOME_DIR/cosmovisor/backup"
echo -e "${YELLOW}Previous service backup:${RESET} $backup"
echo -e "${YELLOW}Automatic binary downloads remain disabled. Stage and review binaries before upgrades.${RESET}"
