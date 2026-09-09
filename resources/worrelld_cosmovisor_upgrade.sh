#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; RESET='\033[0m'
# shellcheck disable=SC1091
source "$HOME/.bash_profile" 2>/dev/null || true
export PATH="$HOME/go/bin:$PATH"

VERSION="${1:-}"
UPGRADE_NAME="${2:-}"
UPGRADE_HEIGHT="${3:-}"
readonly HOME_DIR="${WORRELL_HOME:-$HOME/.worrell}"
readonly BINARY_DIR="$HOME/go/bin"
readonly SERVICE="${WORRELL_SERVICE_NAME:-worrelld}"
readonly COSMOVISOR_BIN="${COSMOVISOR_BIN:-$BINARY_DIR/cosmovisor}"

[ -x "$COSMOVISOR_BIN" ] || { echo -e "${RED}Cosmovisor is not installed.${RESET}" >&2; exit 1; }
[ -d "$HOME_DIR/cosmovisor" ] || { echo -e "${RED}Cosmovisor is not initialized for $HOME_DIR.${RESET}" >&2; exit 1; }
[ -n "$VERSION" ] || read -r -p "Worrell release version (for example v0.1.2): " VERSION
[ -n "$UPGRADE_NAME" ] || read -r -p "On-chain upgrade name: " UPGRADE_NAME
[[ "$VERSION" =~ ^v[0-9A-Za-z._-]+$ ]] || { echo -e "${RED}Invalid release version.${RESET}" >&2; exit 1; }
[[ "$UPGRADE_NAME" =~ ^[A-Za-z0-9._-]+$ ]] || { echo -e "${RED}Invalid upgrade name.${RESET}" >&2; exit 1; }
if [ -n "$UPGRADE_HEIGHT" ]; then
    [[ "$UPGRADE_HEIGHT" =~ ^[0-9]+$ ]] && [ "$UPGRADE_HEIGHT" -gt 0 ] || { echo -e "${RED}Upgrade height must be a positive integer.${RESET}" >&2; exit 1; }
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
export UNSAFE_SKIP_BACKUP=false

args=(add-upgrade "$UPGRADE_NAME" "$workdir/worrelld")
[ -z "$UPGRADE_HEIGHT" ] || args+=(--upgrade-height "$UPGRADE_HEIGHT")
"$COSMOVISOR_BIN" "${args[@]}"

echo -e "${GREEN}Cosmovisor upgrade binary staged successfully.${RESET}"
echo -e "${CYAN}Upgrade:${RESET} $UPGRADE_NAME"
echo -e "${CYAN}Release:${RESET} $VERSION"
[ -z "$UPGRADE_HEIGHT" ] || echo -e "${CYAN}Height:${RESET} $UPGRADE_HEIGHT"
echo -e "${CYAN}Service:${RESET} $SERVICE (not restarted)"
echo -e "For governance upgrades, verify the on-chain plan name exactly. For emergency height-based upgrades, verify the height and binary before proceeding."
