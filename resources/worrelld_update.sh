#!/usr/bin/env bash
set -eo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'
YELLOW='\033[0;33m'; ORANGE='\033[38;5;214m'; RESET='\033[0m'
# shellcheck disable=SC1091
source "$HOME/.bash_profile" 2>/dev/null || true
set -u
export PATH="$HOME/go/bin:/usr/local/bin:$PATH"

ROOT_MODE=no
if [ "${EUID:-$(id -u)}" -eq 0 ]; then ROOT_MODE=yes; fi
WORRELL_HOME="${WORRELL_HOME:-$([ "$ROOT_MODE" = yes ] && printf '/var/lib/%s' "${WORRELL_SERVICE_USER:-worrell}" || printf '%s' "$HOME/.worrell")}"
WORRELL_ENV_FILE="${WORRELL_ENV_FILE:-$WORRELL_HOME/.worrell.env}"
if [ -r "$WORRELL_ENV_FILE" ]; then
    # shellcheck disable=SC1090
    source "$WORRELL_ENV_FILE"
fi
VERSION=${1:-${WORRELL_TARGET_VERSION:-v0.1.2}}
BINARY_DIR="${WORRELL_BINARY_DIR:-$([ "$ROOT_MODE" = yes ] && printf '/usr/local/bin' || printf '%s' "$HOME/go/bin")}"
SERVICE=${WORRELL_SERVICE_NAME:-worrelld}
SERVICE_USER=${WORRELL_SERVICE_USER:-$([ "$ROOT_MODE" = yes ] && printf worrell || id -un)}
SERVICE_GROUP=${WORRELL_SERVICE_GROUP:-$SERVICE_USER}
if [ "$ROOT_MODE" = yes ]; then sudo() { "$@"; }; fi
case "$(uname -m)" in
    x86_64|amd64) artifact="${VERSION}_linux_amd64.tar.gz"; expected="1542bc561227ecd6bfb2d35f3bc81b8fd34e6f6db1404923b5bf5bd4b8303cd2" ;;
    aarch64|arm64) artifact="${VERSION}_linux_arm64.tar.gz"; expected="3d4a9ffc754c39400c31af6599d030c2652914094a772f38e7a8284aafc7f58f" ;;
    *) echo -e "${RED}Unsupported architecture.${RESET}"; exit 1 ;;
esac
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
curl -fsSL "https://github.com/worrellchain/worrell/releases/download/${VERSION}/${artifact}" -o "$workdir/$artifact"
curl -fsSL "https://github.com/worrellchain/worrell/releases/download/${VERSION}/release_checksum" -o "$workdir/release_checksum"
(
    cd "$workdir"
    grep -E "[[:space:]]${artifact//./\\.}$" release_checksum | sha256sum -c -
)
if [ "$VERSION" = "v0.1.2" ]; then
    echo "$expected  $workdir/$artifact" | sha256sum -c -
fi
tar -xzf "$workdir/$artifact" -C "$workdir"
[ -x "$workdir/worrelld" ]
"$workdir/worrelld" version --long | head -5

restart=no
if sudo systemctl is-active --quiet "$SERVICE"; then restart=yes; sudo systemctl stop "$SERVICE"; fi
backup="$BINARY_DIR/worrelld.previous.$(date +%Y%m%d-%H%M%S)"
if [ -x "$BINARY_DIR/worrelld" ]; then cp -p "$BINARY_DIR/worrelld" "$backup"; fi
install -Dm755 "$workdir/worrelld" "$BINARY_DIR/worrelld"
if [ "$restart" = yes ]; then
    if ! sudo systemctl start "$SERVICE" || ! sudo systemctl is-active --quiet "$SERVICE"; then
        echo -e "${RED}New binary failed service health check; restoring previous binary.${RESET}" >&2
        [ -x "$backup" ] && install -Dm755 "$backup" "$BINARY_DIR/worrelld"
        sudo systemctl start "$SERVICE" || true
        exit 1
    fi
fi
echo -e "${GREEN}Installed worrelld ${VERSION} with verified release checksum.${RESET}"
worrelld version --long | head -5
