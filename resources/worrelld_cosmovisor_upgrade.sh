#!/usr/bin/env bash
set -eo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; RESET='\033[0m'
# shellcheck disable=SC1091
source "$HOME/.bash_profile" 2>/dev/null || true
set -u
export PATH="$HOME/go/bin:/usr/local/bin:$PATH"

VERSION="${1:-}"
UPGRADE_NAME="${2:-}"
UPGRADE_HEIGHT="${3:-}"
ROOT_MODE=no
if [ "${EUID:-$(id -u)}" -eq 0 ]; then ROOT_MODE=yes; fi
HOME_DIR="${WORRELL_HOME:-$([ "$ROOT_MODE" = yes ] && printf '/var/lib/%s' "${WORRELL_SERVICE_USER:-worrell}" || printf '%s' "$HOME/.worrell")}"
WORRELL_ENV_FILE="${WORRELL_ENV_FILE:-$HOME_DIR/.worrell.env}"
if [ -r "$WORRELL_ENV_FILE" ]; then
    # shellcheck disable=SC1090
    source "$WORRELL_ENV_FILE"
fi
BINARY_DIR="${WORRELL_BINARY_DIR:-$([ "$ROOT_MODE" = yes ] && printf '/usr/local/bin' || printf '%s' "$HOME/go/bin")}"
readonly SERVICE="${WORRELL_SERVICE_NAME:-worrelld}"
readonly COSMOVISOR_BIN="${COSMOVISOR_BIN:-$BINARY_DIR/cosmovisor}"
if [ "$ROOT_MODE" = yes ]; then sudo() { "$@"; }; fi
WORRELL_UNSAFE_SKIP_BACKUP="${WORRELL_UNSAFE_SKIP_BACKUP:-true}"
case "$WORRELL_UNSAFE_SKIP_BACKUP" in
    true|false) ;;
    *) echo -e "${RED}WORRELL_UNSAFE_SKIP_BACKUP must be true or false.${RESET}" >&2; exit 1 ;;
esac

valid_upgrade_name() {
    [ -n "$1" ] || return 1
    case "$1" in *$'\n'*|*$'\r'*) return 1 ;; esac
}

valid_upgrade_height() {
    [ -n "$1" ] && [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -gt 0 ]
}

preflight_emergency_upgrade() {
    local home="$1" name="$2" target_dir encoded_name
    encoded_name=$(python3 - "$name" <<'PY2'
import sys
from urllib.parse import quote
print(quote(sys.argv[1].lower(), safe="-_.~"))
PY2
)
    target_dir="$home/cosmovisor/upgrades/$encoded_name"
    [ ! -e "$target_dir" ] || return 1
    [ ! -e "$home/data/upgrade-info.json" ] || return 1
}

[ -x "$COSMOVISOR_BIN" ] || { echo -e "${RED}Cosmovisor is not installed.${RESET}" >&2; exit 1; }
[ -d "$HOME_DIR/cosmovisor" ] || { echo -e "${RED}Cosmovisor is not initialized for $HOME_DIR.${RESET}" >&2; exit 1; }
if [ "$ROOT_MODE" = yes ]; then
    case "$HOME_DIR" in /var/lib/${WORRELL_SERVICE_USER:-worrell}|/var/lib/${WORRELL_SERVICE_USER:-worrell}/*) ;; *) echo -e "${RED}Refusing root-mode node home outside /var/lib/worrell.${RESET}" >&2; exit 1 ;; esac
fi
[ -n "$VERSION" ] || read -r -p "Worrell release version (for example v0.1.2): " VERSION
[ -n "$UPGRADE_NAME" ] || read -r -p "On-chain upgrade name: " UPGRADE_NAME
[[ "$VERSION" =~ ^v[0-9A-Za-z._-]+$ ]] || { echo -e "${RED}Invalid release version.${RESET}" >&2; exit 1; }
valid_upgrade_name "$UPGRADE_NAME" || { echo -e "${RED}Upgrade name cannot be empty or contain a newline.${RESET}" >&2; exit 1; }
if [ -n "$UPGRADE_HEIGHT" ]; then
    valid_upgrade_height "$UPGRADE_HEIGHT" || { echo -e "${RED}Upgrade height must be a positive integer.${RESET}" >&2; exit 1; }
fi

case "$(uname -m)" in
    x86_64|amd64) artifact="${VERSION}_linux_amd64.tar.gz" ;;
    aarch64|arm64) artifact="${VERSION}_linux_arm64.tar.gz" ;;
    *) echo -e "${RED}Unsupported architecture.${RESET}" >&2; exit 1 ;;
esac

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
curl -fsSL "https://github.com/worrellchain/worrell/releases/download/${VERSION}/${artifact}" -o "$workdir/$artifact"
curl -fsSL "https://github.com/worrellchain/worrell/releases/download/${VERSION}/release_checksum" -o "$workdir/release_checksum"
(
    cd "$workdir"
    grep -E "[[:space:]]${artifact//./\\.}$" release_checksum | sha256sum -c -
)
tar -xzf "$workdir/$artifact" -C "$workdir"
[ -x "$workdir/worrelld" ] || { echo -e "${RED}Release archive did not contain executable worrelld.${RESET}" >&2; exit 1; }

export DAEMON_NAME=worrelld
export DAEMON_HOME="$HOME_DIR"
export DAEMON_ALLOW_DOWNLOAD_BINARIES=false
export DAEMON_RESTART_AFTER_UPGRADE=true
export DAEMON_DATA_BACKUP_DIR="$HOME_DIR/cosmovisor/backup"
export UNSAFE_SKIP_BACKUP="$WORRELL_UNSAFE_SKIP_BACKUP"

if [ -n "$UPGRADE_HEIGHT" ]; then
    preflight_emergency_upgrade "$HOME_DIR" "$UPGRADE_NAME" || { echo -e "${RED}Emergency staging conflicts with an existing upgrade directory or upgrade-info.json; refusing mutation.${RESET}" >&2; exit 1; }
fi

args=(add-upgrade "$UPGRADE_NAME" "$workdir/worrelld")
[ -z "$UPGRADE_HEIGHT" ] || args+=(--upgrade-height "$UPGRADE_HEIGHT")
"$COSMOVISOR_BIN" "${args[@]}"

echo -e "${GREEN}Cosmovisor upgrade binary staged successfully.${RESET}"
echo -e "${CYAN}Upgrade:${RESET} $UPGRADE_NAME"
echo -e "${CYAN}Release:${RESET} $VERSION"
[ -z "$UPGRADE_HEIGHT" ] || echo -e "${CYAN}Height:${RESET} $UPGRADE_HEIGHT"
echo -e "${CYAN}Service:${RESET} $SERVICE (not restarted)"
echo -e "For governance upgrades, verify the on-chain plan name exactly. For emergency height-based upgrades, verify the height and binary before proceeding."
