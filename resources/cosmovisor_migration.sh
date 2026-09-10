#!/usr/bin/env bash
set -eo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[0;33m'; RESET='\033[0m'
# shellcheck disable=SC1091
source "$HOME/.bash_profile" 2>/dev/null || true
set -u
export PATH="$HOME/go/bin:/usr/local/bin:$PATH"

ROOT_MODE=no
if [ "${EUID:-$(id -u)}" -eq 0 ]; then ROOT_MODE=yes; fi
HOME_DIR="${WORRELL_HOME:-$([ "$ROOT_MODE" = yes ] && printf '/var/lib/%s' "${WORRELL_SERVICE_USER:-worrell}" || printf '%s' "$HOME/.worrell")}"
WORRELL_ENV_FILE="${WORRELL_ENV_FILE:-$HOME_DIR/.worrell.env}"
if [ -r "$WORRELL_ENV_FILE" ]; then
    # shellcheck disable=SC1090
    source "$WORRELL_ENV_FILE"
fi
SERVICE="${WORRELL_SERVICE_NAME:-worrelld}"
SERVICE_USER="${WORRELL_SERVICE_USER:-$([ "$ROOT_MODE" = yes ] && printf worrell || id -un)}"
SERVICE_GROUP="${WORRELL_SERVICE_GROUP:-$SERVICE_USER}"
BINARY_DIR="${WORRELL_BINARY_DIR:-$([ "$ROOT_MODE" = yes ] && printf '/usr/local/bin' || printf '%s' "$HOME/go/bin")}"
readonly CHAIN_ID="${WORRELL_CHAIN_ID:-worrell-testnet-1}"
readonly COSMOVISOR_VERSION="${WORRELL_COSMOVISOR_VERSION:-v1.7.3}"
COSMOVISOR_BIN="$BINARY_DIR/cosmovisor"
readonly SYSTEMD_UNIT_DIR="${WORRELL_SYSTEMD_UNIT_DIR:-/etc/systemd/system}"
if [ "$ROOT_MODE" = yes ]; then sudo() { "$@"; }; fi
WORRELL_UNSAFE_SKIP_BACKUP="${WORRELL_UNSAFE_SKIP_BACKUP:-true}"
case "$WORRELL_UNSAFE_SKIP_BACKUP" in
    true|false) ;;
    *) echo -e "${RED}WORRELL_UNSAFE_SKIP_BACKUP must be true or false.${RESET}" >&2; exit 1 ;;
esac

[ -x "$BINARY_DIR/worrelld" ] || { echo -e "${RED}Missing $BINARY_DIR/worrelld. Install Worrell first.${RESET}" >&2; exit 1; }
[ -d "$HOME_DIR/config" ] || { echo -e "${RED}Missing node home: $HOME_DIR${RESET}" >&2; exit 1; }
if [ "$ROOT_MODE" = yes ]; then
    case "$HOME_DIR" in /var/lib/$SERVICE_USER|/var/lib/$SERVICE_USER/*) ;; *) echo -e "${RED}Refusing root-mode node home outside /var/lib/$SERVICE_USER: $HOME_DIR${RESET}" >&2; exit 1 ;; esac
else
    case "$HOME_DIR" in "$HOME/.worrell"|"$HOME"/*) ;; *) echo -e "${RED}Refusing node home outside the current user's home: $HOME_DIR${RESET}" >&2; exit 1 ;; esac
    [ "$(stat -c %u "$HOME_DIR")" = "$(id -u)" ] || { echo -e "${RED}Node home must be owned by the current user: $HOME_DIR${RESET}" >&2; exit 1; }
fi
[ ! -e "$HOME_DIR/data/upgrade-info.json" ] || { echo -e "${RED}Pending data/upgrade-info.json found; review/stage the matching upgrade before migration.${RESET}" >&2; exit 1; }

export DAEMON_NAME=worrelld
export DAEMON_HOME="$HOME_DIR"

install_cosmovisor() {
    local artifact workdir expected
    case "$(uname -m)" in
        x86_64|amd64) artifact="cosmovisor-${COSMOVISOR_VERSION}-linux-amd64.tar.gz"; expected="3df6ef38cf976b00d226f391dc6866b8dc4040fc2f1b4a780d248f6e1cc9332e" ;;
        aarch64|arm64) artifact="cosmovisor-${COSMOVISOR_VERSION}-linux-arm64.tar.gz"; expected="ff27992e1356fbcb858a604455ad28a9727415c3e35b947a4fdb30d8f91295cd" ;;
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
    echo "$expected  $workdir/$artifact" | sha256sum -c -
    tar -xzf "$workdir/$artifact" -C "$workdir"
    install -Dm755 "$workdir/cosmovisor" "$COSMOVISOR_BIN"
    [ -x "$COSMOVISOR_BIN" ] || { echo -e "${RED}Cosmovisor installation failed.${RESET}" >&2; return 1; }
}

was_active=no
autostart=no
if sudo systemctl is-active --quiet "$SERVICE"; then was_active=yes; fi
if sudo systemctl is-enabled --quiet "$SERVICE"; then autostart=yes; fi
unit="$SYSTEMD_UNIT_DIR/${SERVICE}.service"
backup="$HOME/.worrell-backups/cosmovisor-service-$(date +%Y%m%d-%H%M%S).service"
profile="$HOME/.bash_profile"
profile_backup="${backup%.service}.bash_profile"
mkdir -p "${backup%/*}"
unit_existed=no
profile_existed=no
if sudo test -f "$unit"; then
    sudo cp -p "$unit" "$backup"
    unit_existed=yes
fi
if [ -f "$profile" ]; then
    cp -p "$profile" "$profile_backup"
    profile_existed=yes
fi

migration_succeeded=no
rollback() {
    rc=$?
    if [ "$migration_succeeded" = yes ]; then
        trap - EXIT
        exit "$rc"
    fi
    if [ "$unit_existed" = yes ]; then sudo cp -p "$backup" "$unit"; else sudo rm -f "$unit"; fi
    if [ "$profile_existed" = yes ]; then cp -p "$profile_backup" "$profile"; else rm -f "$profile"; fi
    sudo systemctl daemon-reload 2>/dev/null || true
    if [ "$autostart" = yes ]; then sudo systemctl enable "$SERVICE" 2>/dev/null || true; else sudo systemctl disable "$SERVICE" 2>/dev/null || true; fi
    if [ "$was_active" = yes ]; then sudo systemctl start "$SERVICE" 2>/dev/null || true; else sudo systemctl stop "$SERVICE" 2>/dev/null || true; fi
    echo -e "${RED}Cosmovisor migration failed; previous service state was restored where possible. Backup: $backup${RESET}" >&2
    exit "$rc"
}
trap rollback EXIT

echo -e "${YELLOW}This migrates ${SERVICE}.service to Cosmovisor without deleting node data or upgrade-info.json.${RESET}"
if [ "$was_active" = yes ]; then sudo systemctl stop "$SERVICE"; fi

install_cosmovisor

if [ ! -x "$HOME_DIR/cosmovisor/current/bin/worrelld" ]; then
    cosmovisor init "$BINARY_DIR/worrelld"
fi
mkdir -p "$HOME_DIR/cosmovisor/upgrades" "$HOME_DIR/cosmovisor/backup"

sudo mkdir -p "$SYSTEMD_UNIT_DIR"
sudo tee "$unit" >/dev/null <<EOF
[Unit]
Description=Cosmovisor Worrell Testnet Node
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_GROUP
WorkingDirectory=$HOME_DIR
ExecStart=$COSMOVISOR_BIN run start --home $HOME_DIR
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
Environment="UNSAFE_SKIP_BACKUP=$WORRELL_UNSAFE_SKIP_BACKUP"

[Install]
WantedBy=multi-user.target
EOF

if [ "$ROOT_MODE" != yes ]; then
    touch "$profile"
    sed -i -E '/^export (DAEMON_NAME|DAEMON_HOME|DAEMON_DATA_BACKUP_DIR|WORRELL_COSMOVISOR_VERSION|WORRELL_UNSAFE_SKIP_BACKUP)=/d' "$profile"
    {
        printf 'export DAEMON_NAME=%q\n' "$DAEMON_NAME"
        printf 'export DAEMON_HOME=%q\n' "$DAEMON_HOME"
        printf 'export DAEMON_DATA_BACKUP_DIR=%q\n' "$HOME_DIR/cosmovisor/backup"
        printf 'export WORRELL_COSMOVISOR_VERSION=%q\n' "$COSMOVISOR_VERSION"
        printf 'export WORRELL_UNSAFE_SKIP_BACKUP=%q\n' "$WORRELL_UNSAFE_SKIP_BACKUP"
    } >> "$profile"
fi

sudo systemctl daemon-reload
if [ "$autostart" = yes ]; then sudo systemctl enable "$SERVICE"; else sudo systemctl disable "$SERVICE" 2>/dev/null || true; fi
if [ "$was_active" = yes ]; then
    sudo systemctl start "$SERVICE"
    sudo systemctl is-active --quiet "$SERVICE"
else
    sudo systemctl stop "$SERVICE"
fi
if [ "$ROOT_MODE" = yes ]; then
    chown -R "$SERVICE_USER:$SERVICE_GROUP" "$HOME_DIR"
fi
migration_succeeded=yes

echo -e "${GREEN}Cosmovisor migration completed.${RESET}"
echo -e "${CYAN}Version:${RESET} $COSMOVISOR_VERSION"
echo -e "${CYAN}Home:${RESET} $HOME_DIR"
echo -e "${CYAN}Backup:${RESET} $HOME_DIR/cosmovisor/backup"
echo -e "${YELLOW}Previous service backup:${RESET} $backup"
echo -e "${YELLOW}Automatic binary downloads remain disabled. Stage and review binaries before upgrades.${RESET}"
