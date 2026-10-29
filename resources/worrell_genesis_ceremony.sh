#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[0;33m'; RESET='\033[0m'

readonly CHAIN_ID="worrell-testnet-2"
readonly PRE_GENESIS_URL="${WORRELL_PRE_GENESIS_URL:-https://raw.githubusercontent.com/worrellchain/networks/main/worrell-testnet-2/pre-genesis.json}"
readonly PRE_GENESIS_SHA256="f5231dc924c762bdbe5aa0605ed6472288c9b71f4b175015e0559edccdd96b94"
readonly FINAL_GENESIS_URL="${WORRELL_FINAL_GENESIS_URL:-https://raw.githubusercontent.com/worrellchain/networks/main/worrell-testnet-2/genesis.json}"
readonly DEFAULT_PORT_PREFIX="${WORRELL_PORT_PREFIX:-18}"
readonly WORRELL_SERVICE_NAME="${WORRELL_SERVICE_NAME:-worrelld-testnet-2.service}"

ROOT_MODE=no
if [ "${EUID:-$(id -u)}" -eq 0 ]; then ROOT_MODE=yes; fi
SERVICE_USER="${WORRELL_SERVICE_USER:-$([ "$ROOT_MODE" = yes ] && printf worrell-testnet-2 || id -un)}"
HOME_DIR="${WORRELL_HOME:-$([ "$ROOT_MODE" = yes ] && printf '/var/lib/%s' "$SERVICE_USER" || printf '%s' "$HOME/.worrell-testnet-2")}"
WORRELLD_BIN="${WORRELLD_BIN:-worrelld}"

info() { printf '%b\n' "${CYAN}$*${RESET}"; }
warn() { printf '%b\n' "${YELLOW}$*${RESET}" >&2; }
die() { printf '%b\n' "${RED}ERROR: $*${RESET}" >&2; exit 1; }

validate_t2_identity() {
    local expected_home expected_user expected_bin
    if [ "$ROOT_MODE" = yes ]; then
        expected_home=/var/lib/worrell-testnet-2
        expected_user=worrell-testnet-2
        expected_bin=/usr/local/bin
    else
        expected_home="$HOME/.worrell-testnet-2"
        expected_user="$(id -un)"
        expected_bin="$HOME/go/bin"
    fi
    [ "$CHAIN_ID" = worrell-testnet-2 ] || die 'Genesis ceremony chain identity is not Testnet 2.'
    [ "$HOME_DIR" = "$expected_home" ] || die "Genesis ceremony home is not the exact managed T2 home: $HOME_DIR"
    [ "$SERVICE_USER" = "$expected_user" ] || die "Genesis ceremony service user is not the expected T2 user: $SERVICE_USER"
    case "$WORRELL_SERVICE_NAME" in
        worrelld-testnet-2|worrelld-testnet-2.service) ;;
        *) die "Genesis ceremony service is not worrelld-testnet-2.service: $WORRELL_SERVICE_NAME" ;;
    esac
    if [[ "$WORRELLD_BIN" == */* ]]; then
        [ "$WORRELLD_BIN" = "$expected_bin/worrelld" ] || die "Genesis ceremony binary is outside the managed T2 binary path: $WORRELLD_BIN"
    else
        [ "$WORRELLD_BIN" = worrelld ] || die "Genesis ceremony binary override is not worrelld: $WORRELLD_BIN"
    fi
    [ "$DEFAULT_PORT_PREFIX" = 18 ] || die "Genesis ceremony port prefix must remain 18: $DEFAULT_PORT_PREFIX"
    [ "$PRE_GENESIS_URL" = https://raw.githubusercontent.com/worrellchain/networks/main/worrell-testnet-2/pre-genesis.json ] || die 'Genesis ceremony pre-genesis URL is not the official Testnet 2 URL.'
}

require_tools() {
    local tool
    for tool in curl sha256sum jq python3; do
        command -v "$tool" >/dev/null 2>&1 || die "Required command is missing: $tool"
    done
}

valid_home() {
    [ -n "$HOME_DIR" ] || die 'WORRELL_HOME is empty.'
    [ ! -L "$HOME_DIR" ] || die "Refusing a symlinked node home: $HOME_DIR"
    if [ "$ROOT_MODE" = yes ]; then
        case "$HOME_DIR" in
            /var/lib/$SERVICE_USER|/var/lib/$SERVICE_USER/*) ;;
            *) die "Root-mode node home must stay under /var/lib/$SERVICE_USER: $HOME_DIR" ;;
        esac
    else
        case "$HOME_DIR" in
            "$HOME/.worrell-testnet-2"|"$HOME"/*) ;;
            *) die "Node home must stay under the current user's home: $HOME_DIR" ;;
        esac
    fi
    local_genesis="$HOME_DIR/config/genesis.json"
    config_file="$HOME_DIR/config/config.toml"
    mkdir -p "$HOME_DIR/config"
}

local_genesis="$HOME_DIR/config/genesis.json"
config_file="$HOME_DIR/config/config.toml"
validate_t2_identity

backup_genesis() {
    local path="$1" backup
    [ -e "$path" ] || return 0
    backup="$path.bak.$(date +%Y%m%d-%H%M%S)"
    cp -p "$path" "$backup"
    printf '%s\n' "$backup"
}

fetch_verified() {
    local url="$1" expected="$2" tmp
    tmp="$(mktemp)"
    if ! curl -fsSL --retry 3 --connect-timeout 10 --max-time 60 "$url" -o "$tmp"; then
        rm -f "$tmp"
        die "Could not fetch genesis from $url"
    fi
    echo "$expected  $tmp" | sha256sum -c - >/dev/null || {
        rm -f "$tmp"
        die "Genesis checksum verification failed for $url"
    }
    jq -e --arg chain "$CHAIN_ID" '.chain_id == $chain' "$tmp" >/dev/null || {
        rm -f "$tmp"
        die "Downloaded genesis does not declare chain_id $CHAIN_ID"
    }
    printf '%s\n' "$tmp"
}

validate_with_binary() {
    command -v "$WORRELLD_BIN" >/dev/null 2>&1 || die "Binary not found: $WORRELLD_BIN"
    "$WORRELLD_BIN" genesis validate-genesis --home "$HOME_DIR"
}

fetch_pre_genesis() {
    valid_home
    require_tools
    require_service_inactive
    local tmp previous
    info "Fetching the official worrell-testnet-2 pre-genesis."
    tmp="$(fetch_verified "$PRE_GENESIS_URL" "$PRE_GENESIS_SHA256")"
    if [ -e "$local_genesis" ] && ! cmp -s "$tmp" "$local_genesis"; then
        read -r -p "Replace the current genesis with the verified pre-genesis? (yes/no): " answer
        [ "${answer,,}" = yes ] || { rm -f "$tmp"; warn 'Pre-genesis replacement cancelled; no file changed.'; return 0; }
        previous="$(backup_genesis "$local_genesis")"
        [ -z "$previous" ] || info "Previous genesis backed up to $previous"
    fi
    require_service_inactive
    install -m 0644 "$tmp" "$local_genesis"
    rm -f "$tmp"
    printf '%s\n' "Pre-genesis installed at $local_genesis"
    printf '%s\n' "sha256: $PRE_GENESIS_SHA256"
    info 'The node must not be started as the final network until final genesis is published.'
}

set_persistent_peers() {
    local peers="$1"
    [ -f "$config_file" ] || die "Config not found: $config_file"
    PEERS="$peers" CONFIG="$config_file" python3 - <<'PY'
from pathlib import Path
import json
import os

path = Path(os.environ['CONFIG'])
peers = os.environ['PEERS']
lines = path.read_text().splitlines()
section = ''
found = False
out = []
for line in lines:
    stripped = line.strip()
    if stripped.startswith('[') and stripped.endswith(']'):
        section = stripped[1:-1]
    if section == 'p2p' and '=' in stripped and not stripped.startswith('#'):
        key = stripped.split('=', 1)[0].strip()
        if key == 'persistent_peers':
            indent = line[:len(line) - len(line.lstrip())]
            line = f'{indent}persistent_peers = {json.dumps(peers)}'
            found = True
    out.append(line)
if not found:
    raise SystemExit('config.toml has no [p2p] persistent_peers key')
path.write_text('\n'.join(out) + '\n')
PY
}

valid_checksum() { [[ "${1:-}" =~ ^[0-9a-fA-F]{64}$ ]]; }
valid_peers() { [ -n "${1:-}" ] && [[ "$1" != *$'\n'* && "$1" != *$'\r'* ]]; }

service_is_inactive() {
    local state
    state="$(systemctl is-active "$WORRELL_SERVICE_NAME" 2>/dev/null || true)"
    case "$state" in
        inactive|dead|failed|unknown) return 0 ;;
        *) return 1 ;;
    esac
}

require_service_inactive() {
    service_is_inactive || die "Service $WORRELL_SERVICE_NAME must be inactive before changing genesis."
}

apply_final_genesis() {
    local checksum="${1:-}" peers="${2:-}" url="${3:-$FINAL_GENESIS_URL}"
    local tmp genesis_backup config_backup had_genesis=no
    valid_home
    require_tools
    require_service_inactive
    valid_checksum "$checksum" || die 'Final genesis checksum must be exactly 64 hexadecimal characters.'
    valid_peers "$peers" || die 'Final genesis peers are required and must be a single non-empty value.'
    [ -f "$config_file" ] || die "Config not found: $config_file. Initialize the node before applying final genesis."
    tmp="$(fetch_verified "$url" "$checksum")"
    config_backup="$(mktemp)"
    genesis_backup="$(mktemp)"
    cp -p "$config_file" "$config_backup"
    if [ -e "$local_genesis" ]; then
        had_genesis=yes
        cp -p "$local_genesis" "$genesis_backup"
    fi
    printf '%s\n' 'Final genesis preview:'
    printf '  URL: %s\n  sha256: %s\n  persistent_peers: %s\n' "$url" "$checksum" "$peers"
    read -r -p 'Type APPLY-FINAL-GENESIS to install it and set peers: ' answer
    if [ "$answer" != APPLY-FINAL-GENESIS ]; then
        rm -f "$tmp" "$config_backup" "$genesis_backup"
        warn 'Final genesis application cancelled; no file changed.'
        return 0
    fi
    require_service_inactive
    if ! set_persistent_peers "$peers" || ! install -m 0644 "$tmp" "$local_genesis"; then
        cp -p "$config_backup" "$config_file"
        [ "$had_genesis" = yes ] && cp -p "$genesis_backup" "$local_genesis"
        rm -f "$tmp" "$config_backup" "$genesis_backup"
        die 'Final genesis application failed; previous config/genesis restored.'
    fi
    if ! validate_with_binary; then
        cp -p "$config_backup" "$config_file"
        [ "$had_genesis" = yes ] && cp -p "$genesis_backup" "$local_genesis"
        rm -f "$tmp" "$config_backup" "$genesis_backup"
        warn 'Local worrelld genesis validation failed; previous config/genesis restored.'
        return 1
    fi
    rm -f "$tmp" "$config_backup" "$genesis_backup"
    printf '%s\n' "Final genesis installed at $local_genesis"
    printf '%s\n' "sha256: $checksum"
    printf '%s\n' "persistent_peers: $peers"
    info 'The service remains under operator control. Start it only according to the published genesis_time.'
}

print_gentx_command() {
    local -a args=(genesis gentx "$GENTX_KEY" "$GENTX_AMOUNT" --chain-id "$CHAIN_ID" --moniker "$GENTX_MONIKER" --commission-rate "$GENTX_RATE" --commission-max-rate "$GENTX_MAX_RATE" --commission-max-change-rate "$GENTX_MAX_CHANGE" --min-self-delegation "$GENTX_MIN_SELF" --ip "$GENTX_IP" --p2p-port "$GENTX_P2P_PORT" --home "$HOME_DIR")
    [ -z "$GENTX_WEBSITE" ] || args+=(--website "$GENTX_WEBSITE")
    [ -z "$GENTX_DETAILS" ] || args+=(--details "$GENTX_DETAILS")
    [ -z "$GENTX_IDENTITY" ] || args+=(--identity "$GENTX_IDENTITY")
    printf '  %q' "$WORRELLD_BIN" "${args[@]}"
    printf '\n'
}

create_gentx() {
    valid_home
    require_tools
    [ -f "$local_genesis" ] || die 'Install pre-genesis before preparing a gentx.'
    jq -e --arg chain "$CHAIN_ID" '.chain_id == $chain' "$local_genesis" >/dev/null || die 'Local genesis is not worrell-testnet-2.'
    command -v "$WORRELLD_BIN" >/dev/null 2>&1 || die "Binary not found: $WORRELLD_BIN"
    GENTX_KEY="${GENTX_KEY:-}"
    GENTX_MONIKER="${GENTX_MONIKER:-}"
    GENTX_AMOUNT="${GENTX_AMOUNT:-495000000uworrell}"
    GENTX_RATE="${GENTX_RATE:-0.05}"
    GENTX_MAX_RATE="${GENTX_MAX_RATE:-0.20}"
    GENTX_MAX_CHANGE="${GENTX_MAX_CHANGE:-0.01}"
    GENTX_MIN_SELF="${GENTX_MIN_SELF:-1000000}"
    GENTX_IP="${GENTX_IP:-}"
    GENTX_P2P_PORT="${GENTX_P2P_PORT:-${DEFAULT_PORT_PREFIX}656}"
    GENTX_WEBSITE="${GENTX_WEBSITE:-}"
    GENTX_DETAILS="${GENTX_DETAILS:-}"
    GENTX_IDENTITY="${GENTX_IDENTITY:-}"
    [ -n "$GENTX_KEY" ] || read -r -p 'Key name: ' GENTX_KEY
    [ -n "$GENTX_MONIKER" ] || read -r -p 'Validator moniker: ' GENTX_MONIKER
    [ -n "$GENTX_IP" ] || read -r -p 'Public IP or hostname for the gentx memo: ' GENTX_IP
    [[ "$GENTX_AMOUNT" =~ ^[0-9]+uworrell$ ]] || die 'Gentx amount must be an integer uworrell amount.'
    local amount_units="${GENTX_AMOUNT%uworrell}"
    [[ "$amount_units" =~ ^[0-9]+$ ]] || die 'Gentx self-delegation must be an integer.'
    amount_units=$((10#$amount_units))
    (( amount_units >= 1000000 && amount_units <= 500000000 )) || die 'Gentx self-delegation must be between 1000000uworrell and 500000000uworrell.'
    [[ "$GENTX_P2P_PORT" =~ ^[0-9]+$ ]] || die 'Gentx P2P port must be numeric.'
    (( GENTX_P2P_PORT >= 1 && GENTX_P2P_PORT <= 65535 )) || die 'Gentx P2P port is outside the valid range.'
    [ -n "$GENTX_KEY" ] || die 'Key name is required.'
    [ -n "$GENTX_MONIKER" ] || die 'Validator moniker is required.'
    [ -n "$GENTX_IP" ] || die 'Public IP or hostname is required.'
    printf '%s\n' 'Gentx preview (nothing is signed or written until confirmation):'
    printf '  chain-id: %s\n  home: %s\n  key: %s\n  moniker: %s\n  self-delegation: %s\n  commission: %s (max %s, change %s)\n  minimum self-delegation: %s\n  peer memo: %s:%s\n' "$CHAIN_ID" "$HOME_DIR" "$GENTX_KEY" "$GENTX_MONIKER" "$GENTX_AMOUNT" "$GENTX_RATE" "$GENTX_MAX_RATE" "$GENTX_MAX_CHANGE" "$GENTX_MIN_SELF" "$GENTX_IP" "$GENTX_P2P_PORT"
    print_gentx_command
    read -r -p 'Type CREATE-GENTX to run this command: ' answer
    [ "$answer" = CREATE-GENTX ] || { warn 'Gentx creation cancelled; no command was run.'; return 0; }
    local -a args=(genesis gentx "$GENTX_KEY" "$GENTX_AMOUNT" --chain-id "$CHAIN_ID" --moniker "$GENTX_MONIKER" --commission-rate "$GENTX_RATE" --commission-max-rate "$GENTX_MAX_RATE" --commission-max-change-rate "$GENTX_MAX_CHANGE" --min-self-delegation "$GENTX_MIN_SELF" --ip "$GENTX_IP" --p2p-port "$GENTX_P2P_PORT" --home "$HOME_DIR")
    [ -z "$GENTX_WEBSITE" ] || args+=(--website "$GENTX_WEBSITE")
    [ -z "$GENTX_DETAILS" ] || args+=(--details "$GENTX_DETAILS")
    [ -z "$GENTX_IDENTITY" ] || args+=(--identity "$GENTX_IDENTITY")
    "$WORRELLD_BIN" "${args[@]}"
    printf '%s\n' 'Gentx command completed. Review config/gentx/gentx-*.json before submitting it upstream.'
}

show_menu() {
    while true; do
        printf '\n%b\n' "${GREEN}Worrell testnet-2 genesis ceremony${RESET}"
        printf '%s\n' '1. Fetch and verify official pre-genesis'
        printf '%s\n' '2. Preview/create a gentx (manual confirmation required)'
        printf '%s\n' '3. Apply final genesis (published checksum and peers required)'
        printf '%s\n' 'b. Back'
        read -r -p 'Choose: ' choice
        case "${choice,,}" in
            1) fetch_pre_genesis ;;
            2) create_gentx ;;
            3)
                read -r -p "Final genesis sha256 (64 hex characters): " checksum
                read -r -p 'Final persistent peers (comma-separated): ' peers
                apply_final_genesis "$checksum" "$peers"
                ;;
            b|'') return 0 ;;
            *) warn 'Invalid option.' ;;
        esac
    done
}

main() {
    local mode=interactive checksum= peers= url=
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --mode) [ "$#" -ge 2 ] || die '--mode requires pre-genesis, final-genesis, gentx, or interactive'; mode="$2"; shift 2 ;;
            --home) [ "$#" -ge 2 ] || die '--home requires a path'; HOME_DIR="$2"; shift 2 ;;
            --checksum) [ "$#" -ge 2 ] || die '--checksum requires a sha256'; checksum="$2"; shift 2 ;;
            --peers) [ "$#" -ge 2 ] || die '--peers requires a value'; peers="$2"; shift 2 ;;
            --url) [ "$#" -ge 2 ] || die '--url requires a URL'; url="$2"; shift 2 ;;
            --help|-h) mode=help; shift ;;
            *) die "Unknown argument: $1" ;;
        esac
    done
    case "$mode" in
        pre-genesis) fetch_pre_genesis ;;
        final-genesis) apply_final_genesis "$checksum" "$peers" "${url:-$FINAL_GENESIS_URL}" ;;
        gentx) create_gentx ;;
        interactive) show_menu ;;
        help)
            printf '%s\n' 'Usage: worrell_genesis_ceremony.sh [--mode MODE] [--home PATH] [--checksum SHA256] [--peers PEERS] [--url URL]'
            printf '%s\n' 'Modes: pre-genesis, gentx, final-genesis, interactive'
            ;;
        *) die "Unknown mode: $mode" ;;
    esac
}

main "$@"
