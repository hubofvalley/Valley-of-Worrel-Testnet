#!/usr/bin/env bash

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'
YELLOW='\033[0;33m'; ORANGE='\033[38;5;214m'; RESET='\033[0m'
# shellcheck disable=SC1091
source "$HOME/.bash_profile" 2>/dev/null || true
export PATH="$HOME/go/bin:/usr/local/bin:$PATH"

if [ -z "${WORRELL_HOME:-}" ]; then
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        WORRELL_HOME="/var/lib/${WORRELL_SERVICE_USER:-worrell}"
    else
        WORRELL_HOME="$HOME/.worrell"
    fi
fi
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    WORRELL_ENV_FILE=/etc/worrelld/worrelld.env
else
    WORRELL_ENV_FILE=${WORRELL_ENV_FILE:-$WORRELL_HOME/.worrell.env}
fi
if [ -r "$WORRELL_ENV_FILE" ]; then
    # shellcheck disable=SC1090
    source "$WORRELL_ENV_FILE"
fi
WORRELL_CHAIN_ID=${WORRELL_CHAIN_ID:-worrell-testnet-1}
WORRELL_SERVICE_NAME=${WORRELL_SERVICE_NAME:-worrelld}
if [ -z "${WORRELL_SERVICE_USER:-}" ]; then
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then WORRELL_SERVICE_USER=worrell; else WORRELL_SERVICE_USER=$(id -un); fi
fi
WORRELL_PORT_PREFIX=${WORRELL_PORT_PREFIX:-17}
WORRELL_TARGET_VERSION=${WORRELL_TARGET_VERSION:-v0.1.2}
WORRELL_UNSAFE_SKIP_BACKUP=${WORRELL_UNSAFE_SKIP_BACKUP:-true}
readonly WORRELL_UPGRADE_V0_1_3="v0.1.3"
readonly WORRELL_UPGRADE_PLAN_V0_1_3="v0.1.3"
readonly WORRELL_UPGRADE_HEIGHT_V0_1_3="1186000"
WORRELL_PUBLIC_RPC=${WORRELL_PUBLIC_RPC:-https://lightnode-rpc-worrell.grandvalleys.com}
WORRELL_PUBLIC_RPCS=${WORRELL_PUBLIC_RPCS:-https://lightnode-rpc-worrell.grandvalleys.com,https://worrel-testnet-rpc.oshvank.xyz,https://worrell-testnet-rpc.itrocket.net,https://worrell-testnet-rpc.nodesync.top,https://worrell-testnet-rpc.bonynode.online,https://rpc-worrell.test.onenov.xyz,https://worrellchain-rpctest.codeblocklabs.com,https://t-worrell.rpc.utsa.tech}
WORRELL_PEERS=${WORRELL_PEERS:-bb9164c1bd9ed9ff2c0fd9e09b23285698e231de@164.68.98.186:26656,40128ea31b1cfb5d4b24fc9e32ee0c468586c983@worrell-testnet-peer.itrocket.net:12656}
WORRELL_PUBLIC_PEER=${WORRELL_PUBLIC_PEER:-e812f08760b18ed774369e899763735f80179f76@peer-worrell.grandvalleys.com:17656}
readonly VALLEY_INSTALLER_SHA256="b0f21d67a4ffb0f721e47130bb4ffc8dcf40292d8648bff7adcfcacc70a98b52"
readonly VALLEY_UPDATER_SHA256="fa074336f167c6189e05847bc87e448994bfdc335003ec5c20cb2d47b2243c14"
readonly VALLEY_COSMOVISOR_MIGRATION_SHA256="7b384a62d99a8a068ede9ef3145eb2a5d97121b534f7b3c565170d011aa20b0d"
readonly VALLEY_COSMOVISOR_UPGRADE_SHA256="c2579a36e6a11fdba35b8d9c1ed700d72b9833f5e5f70a7d91abf085d6e54a31"
readonly VALLEY_SNAPSHOT_SHA256="3b10c2e7f81b72d6d13b1b5598527c6608deccaf90240af0b2b089dd7e22931b"
readonly VALLEY_SCRIPT_COMMIT="d4235d48f4cac2a0d1324a56a7c34973cf7f1ec1"
readonly VALLEY_SCRIPT_BASE="https://raw.githubusercontent.com/hubofvalley/Valley-of-Worrel-Testnet/d4235d48f4cac2a0d1324a56a7c34973cf7f1ec1/resources"

export WORRELL_HOME WORRELL_ENV_FILE WORRELL_CHAIN_ID WORRELL_SERVICE_NAME
export WORRELL_SERVICE_USER WORRELL_PORT_PREFIX WORRELL_TARGET_VERSION WORRELL_UNSAFE_SKIP_BACKUP

LOGO=$(cat <<'EOF'
 __        __                    _
 \ \      / /__  _ __ _ __ ___| |
  \ \ /\ / / _ \| '__| '__/ _ \ |
   \ V  V / (_) | |  | | |  __/ |
    \_/\_/ \___/|_|  |_|  \___|_|

  ____                     _  __     __    _ _
 / ___|_ __ __ _ _ __   __| | \ \   / /_ _| | | ___ _   _
| |  _| '__/ _` | '_ \ / _` |  \ \ / / _` | | |/ _ \ | | |
| |_| | | | (_| | | | | (_| |   \ V / (_| | | |  __/ |_| |
 \____|_|  \__,_|_| |_|\__,_|    \_/ \__,_|_|_|\___|\__, |
                                                      |___/
                         Grand Valley
EOF
)

PRIVACY_SAFETY_STATEMENT="
${YELLOW}Privacy and Safety Statement${RESET}

${GREEN}No User Data Stored Externally${RESET}
- Operations run locally. The menu does not upload keys, mnemonics, or node data.

${GREEN}No Phishing Links${RESET}
- URLs are shown for Worrell and Grand Valley node operations. Verify them before use.

${GREEN}Security Best Practices${RESET}
- Review this script and child scripts before execution; keep validator signing keys offline and backed up.

${GREEN}Disclaimer${RESET}
- Grand Valley is not responsible for misuse, downtime, slashing, or loss. Use testnet-only keys first.

${GREEN}Contact${RESET}
- letsbuidltogether@grandvalleys.com
"

is_valid_service_name() { [[ "$1" =~ ^[A-Za-z0-9_.@-]+$ ]]; }

get_local_rpc_port() {
    local cfg="$WORRELL_HOME/config/config.toml"
    [ -f "$cfg" ] || return 0
    awk -F: '/^[[:space:]]*laddr[[:space:]]*=[[:space:]]*"tcp:\/\/127\.0\.0\.1:/ {gsub(/".*/, "", $3); print $3; exit}' "$cfg"
}

local_status() {
    local port=${1:-$(get_local_rpc_port)}
    port=${port:-17657}
    curl -m 5 -fsS "http://127.0.0.1:${port}/status" 2>/dev/null
}

network_status() {
    local rpc response
    IFS=',' read -r -a rpc_list <<< "$WORRELL_PUBLIC_RPCS"
    for rpc in "${rpc_list[@]}"; do
        response=$(curl -m 5 -fsS "${rpc%/}/status" 2>/dev/null || true)
        if [ -n "$response" ] && jq -e --arg chain "$WORRELL_CHAIN_ID" '.result.node_info.network == $chain' >/dev/null 2>&1 <<< "$response"; then
            printf '%s\n' "$response"
            return 0
        fi
    done
    return 1
}

local_height() { local_status | jq -r '.result.sync_info.latest_block_height // empty'; }
network_height() { network_status | jq -r '.result.sync_info.latest_block_height // empty'; }
local_catching_up() {
    local response
    response=$(local_status "${1:-}" || true)
    jq -r 'if .result.sync_info.catching_up == null then "unknown" else .result.sync_info.catching_up end' <<< "$response" 2>/dev/null || printf '%s\n' unknown
}

run_pinned_child() {
    local script="$1" expected="$2" path tmp actual rc
    shift 2
    tmp=""
    case "$script" in
        worrelld_node_install_testnet.sh) expected="$VALLEY_INSTALLER_SHA256" ;;
        worrelld_update.sh) expected="$VALLEY_UPDATER_SHA256" ;;
        cosmovisor_migration.sh) expected="$VALLEY_COSMOVISOR_MIGRATION_SHA256" ;;
        worrelld_cosmovisor_upgrade.sh) expected="$VALLEY_COSMOVISOR_UPGRADE_SHA256" ;;
        apply_snapshot.sh) expected="$VALLEY_SNAPSHOT_SHA256" ;;
        *) echo -e "${RED}Unknown child script. Refusing execution.${RESET}" >&2; return 1 ;;
    esac
    path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$script"
    if [ ! -f "$path" ]; then
        tmp=$(mktemp -d)
        path="$tmp/$script"
        curl -fsSL "$VALLEY_SCRIPT_BASE/$script" -o "$path" || { rm -rf "$tmp"; return 1; }
    fi
    actual=$(sha256sum "$path" | awk '{print $1}')
    if [[ "$expected" == __*__ || "$actual" != "$expected" ]]; then
        echo -e "${RED}Child script integrity check failed. Review local script and checksum.${RESET}" >&2
        echo "Expected: $expected" >&2
        echo "Observed: $actual" >&2
        return 1
    fi
    bash "$path" "$@"
    rc=$?
    [ -z "$tmp" ] || rm -rf "$tmp"
    return "$rc"
}

show_intro() {
    local version="not installed; target $WORRELL_TARGET_VERSION" worrelld_bin=""
    if worrelld_bin=$(worrell_bin 2>/dev/null); then version=$("$worrelld_bin" version --long 2>/dev/null | head -1 || true); fi
    echo -e "
Valley of Worrell by ${ORANGE}Grand Valley${RESET}

${GREEN}Worrell Testnet Node System Requirements${RESET}
${YELLOW}| Category  | Requirements |
| --------- | ------------ |
| CPU       | 2+ vCPU      |
| RAM       | 4+ GB        |
| Storage   | 100+ GB SSD  |
| Bandwidth | Public P2P   |${RESET}

- service file name: ${CYAN}${WORRELL_SERVICE_NAME}.service${RESET}
- current chain: ${CYAN}Worrell Testnet${RESET}
- current chain ID: ${CYAN}${WORRELL_CHAIN_ID}${RESET}
- native denom: ${CYAN}uworrell${RESET} (1 WORRELL = 1,000,000 uworrell)
- binary: ${CYAN}${worrelld_bin:-$HOME/go/bin/worrelld}${RESET} (${CYAN}${version}${RESET})
- node directory: ${CYAN}${WORRELL_HOME}${RESET}"
}

show_endpoints() {
    echo -e "${GREEN}
Worrell useful links:${RESET}
- Website: ${BLUE}https://worrellchain.com${RESET}
- Node guide: ${BLUE}https://github.com/worrellchain/worrell/blob/main/docs/RUNNING-A-NODE.md${RESET}
- GitHub: ${BLUE}https://github.com/worrellchain/worrell${RESET}
- Network metadata: ${BLUE}https://github.com/worrellchain/networks/tree/main/worrell-testnet-1${RESET}
- Validator Telegram: ${BLUE}https://t.me/worrellvalidators${RESET}
- Faucet: ${BLUE}http://164.68.98.186:4500${RESET}

${GREEN}Network facts:${RESET}
- Chain ID: ${CYAN}${WORRELL_CHAIN_ID}${RESET}
- Live RPC: ${BLUE}${WORRELL_PUBLIC_RPC}${RESET}
- Live WebSocket: ${BLUE}wss://lightnode-rpc-worrell.grandvalleys.com/websocket${RESET}
- Live direct peer: ${CYAN}${WORRELL_PUBLIC_PEER}${RESET}
- Default port prefix: ${CYAN}17${RESET} (P2P 17656, RPC 17657, ABCI 17658, REST 17317, gRPC 17090, gRPC-Web 17091, Prometheus 17660)
- Public RPC candidates (availability not guaranteed): ${BLUE}${WORRELL_PUBLIC_RPCS//,/, }${RESET}
- Official peers: ${CYAN}${WORRELL_PEERS}${RESET}
- Genesis SHA256: ${CYAN}a81c507b12ba0678c3172394ff4bb03e1c3db60050cc5568c127a24ec19378fd${RESET}
- Explorers: ${BLUE}https://test.anode.team/worrell${RESET}, ${BLUE}https://explorer.oshvank.xyz/worrel-testnet${RESET}

${GREEN}Connect with Grand Valley:${RESET}
- X: ${BLUE}https://x.com/bacvalley${RESET}
- GitHub: ${BLUE}https://github.com/hubofvalley${RESET}
- Email: ${BLUE}letsbuidltogether@grandvalleys.com${RESET}
"
}

prompt_back() { read -r -p "Press Enter to go back to main menu..."; }

install_node() {
    local service_mode answer
    clear
    echo -e "${RED}▓▒░ IMPORTANT DISCLAIMER AND TERMS ░▒▓${RESET}"
    echo -e "${YELLOW}SECURITY${RESET}: scripts stay local; audit source before running."
    echo -e "${YELLOW}SYSTEM IMPACT${RESET}: creates/replaces ${WORRELL_SERVICE_NAME}.service, node home ${WORRELL_HOME}, and remaps ports with a two-digit prefix. Existing home is moved to a timestamped backup."
    echo -e "${YELLOW}REQUIREMENTS${RESET}: Ubuntu 22.04+, 2 vCPU, 4 GB RAM, 100 GB SSD, public P2P reachability."
    echo -e "${YELLOW}VALIDATOR RESPONSIBILITIES${RESET}: keep uptime, protect keys, update safely, and avoid double-signing."
    read -r -p "Proceed with installation/redeployment? (yes/no): " answer
    if [[ "${answer,,}" != yes ]]; then
        echo -e "${RED}Installation cancelled.${RESET}"
        prompt_back
        menu
        return
    fi
    while true; do
        echo -e "${CYAN}Pruning selection${RESET}"
        echo "pruned  = keep recent 100 states and prune every 20 blocks."
        echo "archive = retain all application-state history; requires substantially more disk space."
        read -r -p "Run node as pruned or archive? (p=pruned, a=archive) [p]: " answer
        case "${answer,,}" in
            ""|p|pruned) pruning_mode=pruned; break ;;
            a|archive) pruning_mode=archive; break ;;
            *) echo -e "${RED}Please answer p/pruned or a/archive.${RESET}" ;;
        esac
    done
    while true; do
        echo -e "${CYAN}Runtime selection${RESET}"
        echo "no  = direct worrelld service; you can migrate later via 1g."
        echo "yes = pinned Cosmovisor service; automatic binary downloads remain disabled."
        read -r -p "Install Cosmovisor for this deployment? (yes/no) [no]: " answer
        case "${answer,,}" in
            ""|no|n) service_mode=direct; break ;;
            yes|y) service_mode=cosmovisor; break ;;
            *) echo -e "${RED}Please answer yes or no.${RESET}" ;;
        esac
    done
    if ! run_pinned_child worrelld_node_install_testnet.sh "$VALLEY_INSTALLER_SHA256" --pruning-mode "$pruning_mode" --service-mode "$service_mode"; then
        echo -e "${RED}Installation failed. Review the output above before retrying.${RESET}" >&2
        prompt_back
        menu
        return
    fi
    # Refresh the one-time service/home settings saved by the child installer.
    # shellcheck disable=SC1091
    source "$HOME/.bash_profile" 2>/dev/null || true
    if [ -z "${WORRELL_HOME:-}" ]; then
        if [ "${EUID:-$(id -u)}" -eq 0 ]; then WORRELL_HOME="/var/lib/${WORRELL_SERVICE_USER:-worrell}"; else WORRELL_HOME="$HOME/.worrell"; fi
    fi
    WORRELL_SERVICE_NAME=${WORRELL_SERVICE_NAME:-worrelld}
    WORRELL_PORT_PREFIX=${WORRELL_PORT_PREFIX:-17}
    if [ -r "$WORRELL_ENV_FILE" ]; then
        # shellcheck disable=SC1090
        source "$WORRELL_ENV_FILE"
        export WORRELL_HOME WORRELL_ENV_FILE WORRELL_SERVICE_NAME WORRELL_SERVICE_USER WORRELL_PORT_PREFIX
    fi
    echo -e "${GREEN}Installation flow finished. Review the output above before returning to the main menu.${RESET}"
    prompt_back
    menu
}

cosmovisor_active() {
    [ "$(runtime_mode)" = cosmovisor ]
}

runtime_mode() {
    local content
    content=$(sudo systemctl show "$WORRELL_SERVICE_NAME" -p ExecStart --value 2>/dev/null || true)
    if grep -qE '(^|[[:space:]])cosmovisor[[:space:]]+run[[:space:]]+start([[:space:]]|$)' <<< "$content"; then
        printf '%s\n' cosmovisor
    elif grep -qE '(^|[[:space:]]|/)worrelld[[:space:]]+start([[:space:]]|$)' <<< "$content"; then
        printf '%s\n' direct
    else
        printf '%s\n' unknown
    fi
}

worrell_bin() {
    if cosmovisor_active && [ -x "$WORRELL_HOME/cosmovisor/current/bin/worrelld" ]; then
        printf '%s\n' "$WORRELL_HOME/cosmovisor/current/bin/worrelld"
    elif [ -x "$HOME/go/bin/worrelld" ]; then
        printf '%s\n' "$HOME/go/bin/worrelld"
    else
        command -v worrelld
    fi
}

worrell() {
    local bin
    bin=$(worrell_bin) || { echo -e "${RED}worrelld is not installed.${RESET}" >&2; return 1; }
    "$bin" "$@"
}

show_cosmovisor_status() {
    echo -e "${GREEN}Cosmovisor status${RESET}"
    if ! command -v cosmovisor >/dev/null 2>&1; then
        echo -e "${YELLOW}Cosmovisor is not installed.${RESET}"
    else
        cosmovisor version || true
    fi
    echo "DAEMON_NAME=${DAEMON_NAME:-worrelld}"
    echo "DAEMON_HOME=${DAEMON_HOME:-$WORRELL_HOME}"
    echo "Cosmovisor home: $WORRELL_HOME/cosmovisor"
    if [ -L "$WORRELL_HOME/cosmovisor/current" ]; then
        echo "Current binary: $(readlink -f "$WORRELL_HOME/cosmovisor/current/bin/worrelld" 2>/dev/null || echo unavailable)"
    else
        echo "Current binary: not initialized"
    fi
    prompt_back
    menu
}

stage_cosmovisor_upgrade() {
    local choice version upgrade_name upgrade_height answer
    echo -e "${ORANGE}Stage a Cosmovisor upgrade binary${RESET}"
    echo "1. v0.1.3 — governance plan v0.1.3 at block ${WORRELL_UPGRADE_HEIGHT_V0_1_3} (recommended)"
    echo "c. Custom verified release and upgrade plan"
    echo "b. Back"
    read -r -p "Choose: " choice
    case "${choice,,}" in
        1)
            version="$WORRELL_UPGRADE_V0_1_3"
            upgrade_name="$WORRELL_UPGRADE_PLAN_V0_1_3"
            upgrade_height=""
            echo -e "${YELLOW}Governance mode: no local --upgrade-height is passed; the chain plan supplies block ${WORRELL_UPGRADE_HEIGHT_V0_1_3}.${RESET}"
            read -r -p "Stage $version for governance plan $upgrade_name? (yes/no): " answer
            ;;
        c)
            read -r -p "Release version (for example v0.1.2): " version
            read -r -p "On-chain upgrade name: " upgrade_name
            read -r -p "Emergency upgrade height (leave empty for governance plan): " upgrade_height
            read -r -p "Stage this verified release? (yes/no): " answer
            ;;
        b|"")
            menu
            return
            ;;
        *)
            echo -e "${RED}Invalid option.${RESET}"
            prompt_back
            menu
            return
            ;;
    esac
    if [[ "${answer,,}" == yes ]]; then
        if ! run_pinned_child worrelld_cosmovisor_upgrade.sh "$VALLEY_COSMOVISOR_UPGRADE_SHA256" "$version" "$upgrade_name" "$upgrade_height"; then
            echo -e "${RED}Cosmovisor upgrade staging failed. Review the output above before retrying.${RESET}" >&2
        fi
    else
        echo -e "${YELLOW}Cosmovisor upgrade staging cancelled. No upgrade binary was changed.${RESET}"
    fi
    prompt_back
    menu
}

manage_cosmovisor() {
    echo -e "${ORANGE}Manage Cosmovisor${RESET}"
    echo "1. Migrate current node to Cosmovisor"
    echo "2. Show Cosmovisor status"
    echo "3. Stage a verified upgrade binary"
    echo "4. Back"
    read -r -p "Choose an option (1-4): " choice
    case "$choice" in
        1)
            if ! run_pinned_child cosmovisor_migration.sh "$VALLEY_COSMOVISOR_MIGRATION_SHA256"; then
                echo -e "${RED}Cosmovisor migration failed. Review the output above before retrying.${RESET}" >&2
            fi
            prompt_back
            menu
            ;;
        2) show_cosmovisor_status ;;
        3)
            if ! cosmovisor_active; then
                echo -e "${RED}Migrate the node to Cosmovisor first.${RESET}"; prompt_back; menu; return
            fi
            stage_cosmovisor_upgrade
            ;;
        4) menu ;;
        *)
            echo -e "${RED}Invalid option.${RESET}"
            prompt_back
            menu
            ;;
    esac
}

apply_snapshot() {
    if ! run_pinned_child apply_snapshot.sh "$VALLEY_SNAPSHOT_SHA256"; then
        echo -e "${RED}Snapshot operation failed. Review the output above before retrying.${RESET}" >&2
    fi
    prompt_back
    menu
}

update_node() {
    local mode
    mode=$(runtime_mode)
    if [ "$mode" = cosmovisor ]; then
        echo -e "${YELLOW}Cosmovisor is active. Use Manage Cosmovisor to stage an upgrade binary; direct replacement is disabled.${RESET}"
        manage_cosmovisor
        return
    fi
    if [ "$mode" = unknown ]; then
        echo -e "${RED}Cannot identify the active service mode. Refusing direct binary replacement.${RESET}"
        prompt_back
        menu
        return
    fi
    echo -e "${YELLOW}Updates the local worrelld binary after release checksum verification and briefly restarts the service.${RESET}"
    read -r -p "Proceed? (yes/no): " answer
    if [[ "${answer,,}" == yes ]]; then
        if ! run_pinned_child worrelld_update.sh "$VALLEY_UPDATER_SHA256"; then
            echo -e "${RED}Node update failed. Review the output above before retrying.${RESET}" >&2
        fi
    else
        echo -e "${YELLOW}Update cancelled. No binary was changed.${RESET}"
    fi
    prompt_back
    menu
}

show_status() {
    local lh nh diff catching port
    lh=$(local_height || true); nh=$(network_height || true); port=$(get_local_rpc_port); port=${port:-17657}
    catching=$(local_catching_up "$port")
    echo -e "${GREEN}Worrell node status${RESET}"
    echo "Local RPC: http://127.0.0.1:${port}"
    echo "Local height: ${lh:-unavailable}"
    echo "Public height: ${nh:-unavailable}"
    echo "Catching up: $catching"
    if [[ "$lh" =~ ^[0-9]+$ && "$nh" =~ ^[0-9]+$ ]]; then
        diff=$((nh-lh)); echo "Block Difference: $diff"
        echo "Negative value is normal while the local Worrell node is ahead of the selected public RPC."
    fi
    prompt_back
    menu
}

show_logs() {
    if ! sudo journalctl -u "$WORRELL_SERVICE_NAME" -fn 100 -o cat; then
        echo -e "${RED}Could not follow the service journal. Review the service name and permissions.${RESET}" >&2
    fi
    echo -e "${YELLOW}Log follow ended. Review the output above before returning to the main menu.${RESET}"
    prompt_back
    menu
}

set_peers() {
    local cfg="$WORRELL_HOME/config/config.toml" choice peers
    [ -f "$cfg" ] || { echo -e "${RED}Node config not found. Install first.${RESET}"; prompt_back; menu; return; }
    echo "1. Restore official peers"; echo "2. Enter peers manually"; echo "3. Back"
    read -r -p "Choose: " choice
    case "$choice" in
        1) peers="$WORRELL_PEERS" ;;
        2) read -r -p "persistent_peers (<id>@<host>:<port>,...): " peers ;;
        *)
            echo -e "${YELLOW}Peer configuration cancelled.${RESET}"
            prompt_back
            menu
            return
            ;;
    esac
    [ -n "$peers" ] || { echo -e "${RED}Peers cannot be empty.${RESET}"; prompt_back; menu; return; }
    sed -i -E "s|^[[:space:]]*persistent_peers[[:space:]]*=.*|persistent_peers = \"${peers//&/\\&}\"|" "$cfg"
    echo -e "${GREEN}Persistent peers updated. Restart the service to apply.${RESET}"
    prompt_back
    menu
}

list_or_create_key() {
    local action name
    worrell_bin >/dev/null 2>&1 || { echo -e "${RED}worrelld is not installed.${RESET}"; prompt_back; menu; return; }
    echo "1. List keys"; echo "2. Create a key"; echo "3. Recover a key from mnemonic"; echo "4. Back"
    read -r -p "Choose: " action
    case "$action" in
        1) worrell keys list --home "$WORRELL_HOME"; prompt_back ;;
        2)
            read -r -p "Key name: " name
            echo -e "${YELLOW}A new mnemonic will be shown once below. Save it offline; Valley does not store it.${RESET}"
            if worrell keys add "$name" --home "$WORRELL_HOME" --output text; then
                echo -e "${YELLOW}Confirm the mnemonic shown above is safely backed up before leaving this screen.${RESET}"
            else
                echo -e "${RED}Key creation did not complete cleanly. Check whether the key exists before retrying.${RESET}" >&2
            fi
            prompt_back
            ;;
        3)
            read -r -p "Key name: " name
            echo -e "${YELLOW}Recovery uses your existing mnemonic; worrelld will not print it back.${RESET}"
            if ! worrell keys add "$name" --recover --home "$WORRELL_HOME" --output text; then
                echo -e "${RED}Key recovery did not complete cleanly. Check the key name and mnemonic before retrying.${RESET}" >&2
            fi
            prompt_back
            ;;
        *)
            echo -e "${YELLOW}Key operation cancelled.${RESET}"
            prompt_back
            menu
            return
            ;;
    esac
    menu
}

show_pubkey() { worrell tendermint show-validator --home "$WORRELL_HOME"; prompt_back; menu; }

valid_uint() { [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -gt 0 ]; }
valid_fraction() { awk -v value="$1" 'BEGIN { exit !(value ~ /^[0-9]+([.][0-9]+)?$/ && value >= 0 && value <= 1) }'; }
validate_validator_inputs() {
    valid_uint "$amount" && valid_uint "$min_self" || return 1
    [ "$min_self" -ge 1000000 ] && [ "$amount" -ge "$min_self" ] || return 1
    valid_fraction "$rate" && valid_fraction "$max_rate" && valid_fraction "$max_change" || return 1
    awk -v rate="$rate" -v max_rate="$max_rate" -v max_change="$max_change" 'BEGIN { exit !(rate >= 0.05 && max_rate >= rate && max_change >= 0 && max_change <= max_rate) }'
}

query_balance() {
    local name address
    read -r -p "Key name or worrell address: " name
    if [[ "$name" == worrell1* ]]; then address="$name"; else address=$(worrell keys show "$name" -a --home "$WORRELL_HOME"); fi
    worrell query bank balances "$address" --home "$WORRELL_HOME" --node "tcp://127.0.0.1:$(get_local_rpc_port)" || true
    prompt_back
    menu
}

create_validator() {
    local name moniker identity website security details amount rate max_rate max_change min_self tmp sync answer pubkey amount_coin
    sync=$(local_catching_up)
    [ "$sync" = false ] || { echo -e "${RED}Node is not confirmed synced (catching_up=$sync). Wait, then retry.${RESET}"; prompt_back; menu; return; }
    read -r -p "Key name: " name
    if ! worrell keys show "$name" -a --home "$WORRELL_HOME" >/dev/null; then
        echo -e "${RED}Key '$name' was not found. No validator transaction was prepared.${RESET}" >&2
        prompt_back
        menu
        return
    fi
    echo -e "${YELLOW}Current account balance:${RESET}"
    if ! worrell query bank balances "$(worrell keys show "$name" -a --home "$WORRELL_HOME")" --home "$WORRELL_HOME" --node "tcp://127.0.0.1:$(get_local_rpc_port)"; then
        echo -e "${RED}Could not query the account balance. Refusing to prepare a validator transaction.${RESET}" >&2
        prompt_back
        menu
        return
    fi
    read -r -p "Validator moniker [Worrell-Grand-Valley]: " moniker; moniker=${moniker:-Worrell-Grand-Valley}
    echo -e "${CYAN}Optional metadata: identity, website, and security email; validator details are editable; press Enter to keep the displayed defaults.${RESET}"
    read -r -p "Validator identity []: " identity; identity=${identity:-}
    read -r -p "Validator website []: " website; website=${website:-}
    read -r -p "Validator security email []: " security; security=${security:-}
    read -r -p "Validator details [Worrell testnet validator]: " details; details=${details:-Worrell testnet validator}
    read -r -p "Self-delegation amount in uworrell [20000000]: " amount; amount=${amount:-20000000}
    read -r -p "Commission rate [0.05]: " rate; rate=${rate:-0.05}
    read -r -p "Commission max rate [0.25]: " max_rate; max_rate=${max_rate:-0.25}
    read -r -p "Commission max daily change [0.01]: " max_change; max_change=${max_change:-0.01}
    read -r -p "Minimum self-delegation in uworrell [1000000]: " min_self; min_self=${min_self:-1000000}
    if ! validate_validator_inputs; then
        echo -e "${RED}Invalid validator values. Require amount >= min-self, commission >= 0.05, max-rate >= rate, and numeric values.${RESET}"
        prompt_back
        menu
        return
    fi
    tmp=$(mktemp)
    # Cosmos SDK Coin values require the denomination; the prompt is in whole micro-units.
    if ! pubkey=$(worrell tendermint show-validator --home "$WORRELL_HOME"); then
        echo -e "${RED}Could not read the consensus public key. Refusing to prepare a validator transaction.${RESET}" >&2
        rm -f "$tmp"
        prompt_back
        menu
        return
    fi
    amount_coin="${amount}uworrell"
    if ! jq -n --arg pubkey "$pubkey" --arg amount "$amount_coin" --arg moniker "$moniker" --arg identity "$identity" --arg website "$website" --arg security "$security" --arg details "$details" --arg rate "$rate" --arg max_rate "$max_rate" --arg max_change "$max_change" --arg min_self "$min_self" '{pubkey:($pubkey|fromjson),amount:$amount,moniker:$moniker,identity:$identity,website:$website,security:$security,details:$details, "commission-rate":$rate,"commission-max-rate":$max_rate,"commission-max-change-rate":$max_change,"min-self-delegation":$min_self}' > "$tmp"; then
        echo -e "${RED}Could not build valid validator JSON. Refusing to prepare a transaction.${RESET}" >&2
        rm -f "$tmp"
        prompt_back
        menu
        return
    fi
    echo -e "${YELLOW}Review validator JSON:${RESET}"; cat "$tmp"
    read -r -p "Submit on-chain create-validator transaction? (yes/no): " answer
    if [[ "${answer,,}" == yes ]]; then
        if ! worrell tx staking create-validator "$tmp" --from "$name" --chain-id "$WORRELL_CHAIN_ID" --home "$WORRELL_HOME" --node "tcp://127.0.0.1:$(get_local_rpc_port)" --gas auto --gas-adjustment 1.5 --gas-prices 0.025uworrell --yes; then
            echo -e "${RED}Validator transaction failed. Review the error above.${RESET}" >&2
        fi
    else
        echo -e "${GREEN}Validator transaction cancelled. No transaction was submitted.${RESET}"
    fi
    rm -f "$tmp"
    prompt_back
    menu
}

unjail() {
    local name answer
    read -r -p "Key name: " name
    read -r -p "Submit unjail transaction? (yes/no): " answer
    if [[ "${answer,,}" == yes ]]; then
        if ! worrell tx slashing unjail --from "$name" --chain-id "$WORRELL_CHAIN_ID" --home "$WORRELL_HOME" --node "tcp://127.0.0.1:$(get_local_rpc_port)" --gas auto --gas-adjustment 1.5 --gas-prices 0.025uworrell --yes; then
            echo -e "${RED}Unjail transaction failed. Review the error above.${RESET}" >&2
        fi
    else
        echo -e "${GREEN}Unjail transaction cancelled. No transaction was submitted.${RESET}"
    fi
    prompt_back
    menu
}

valid_worrell_account_address() {
    [[ "${1:-}" =~ ^worrell1[0-9a-z]+$ ]]
}

valid_worrell_valoper_address() {
    [[ "${1:-}" =~ ^worrellvaloper1[0-9a-z]+$ ]]
}

valid_uworrell_amount() {
    local amount="${1:-}" units
    [[ "$amount" =~ ^[0-9]+uworrell$ ]] || return 1
    units=${amount%uworrell}
    [[ "$units" =~ [1-9] ]]
}

resolve_worrell_key_address() {
    local name="${1:-}" address
    [ -n "$name" ] || return 1
    address=$(worrell keys show "$name" -a --home "$WORRELL_HOME" 2>/dev/null) || return 1
    address=${address##*$'\n'}
    address=${address//$'\r'/}
    valid_worrell_account_address "$address" || return 1
    printf '%s\n' "$address"
}

local_rpc_is_synced() {
    local port response
    port=$(get_local_rpc_port)
    port=${port:-17657}
    response=$(local_status "$port") || return 1
    jq -e --arg chain "$WORRELL_CHAIN_ID" \
        '.result.node_info.network == $chain and .result.sync_info.catching_up == false' \
        <<<"$response" >/dev/null 2>&1
}

delegate_to_validator() {
    local name validator amount key_address rpc balance_preview validator_preview answer port
    port=$(get_local_rpc_port)
    port=${port:-17657}
    rpc="tcp://127.0.0.1:$port"
    if ! local_rpc_is_synced; then
        echo -e "${RED}The local Worrell RPC is unavailable or the node is not confirmed synced. Wait for catching_up=false, then retry.${RESET}"
        prompt_back
        menu
        return
    fi

    read -r -p "Key name: " name
    if ! key_address=$(resolve_worrell_key_address "$name"); then
        echo -e "${RED}Key '$name' was not found or did not resolve to a valid worrell1... account address. Create or recover it with menu 2a first.${RESET}"
        prompt_back
        menu
        return
    fi

    read -r -p "Validator operator address (worrellvaloper1...): " validator
    if ! valid_worrell_valoper_address "$validator"; then
        echo -e "${RED}Invalid validator operator address. Expected a worrellvaloper1... address.${RESET}"
        prompt_back
        menu
        return
    fi

    read -r -p "Amount to delegate in uworrell (for example 1000000uworrell): " amount
    if ! valid_uworrell_amount "$amount"; then
        echo -e "${RED}Invalid delegation amount. Enter a positive integer with exactly one uworrell suffix, for example 1000000uworrell.${RESET}"
        prompt_back
        menu
        return
    fi

    if ! balance_preview=$(worrell query bank balances "$key_address" --home "$WORRELL_HOME" --node "$rpc" --output json 2>/dev/null); then
        echo -e "${RED}Could not query the key balance through the local RPC. Refusing to prepare a delegation.${RESET}"
        prompt_back
        menu
        return
    fi
    if ! jq -e 'type == "object" and (.balances | type == "array")' <<<"$balance_preview" >/dev/null 2>&1; then
        echo -e "${RED}The local RPC returned an invalid balance preview. Refusing to prepare a delegation.${RESET}"
        prompt_back
        menu
        return
    fi

    if ! validator_preview=$(worrell query staking validator "$validator" --home "$WORRELL_HOME" --node "$rpc" --output json 2>/dev/null); then
        echo -e "${RED}Could not query validator '$validator' through the local RPC. Refusing to prepare a delegation.${RESET}"
        prompt_back
        menu
        return
    fi
    if ! jq -e --arg validator "$validator" \
        'type == "object" and (.operator_address == $validator or .validator.operator_address == $validator)' \
        <<<"$validator_preview" >/dev/null 2>&1; then
        echo -e "${RED}The local RPC did not return the requested validator. Refusing to prepare a delegation.${RESET}"
        prompt_back
        menu
        return
    fi

    echo -e "${YELLOW}Delegation transaction review:${RESET}"
    echo "- From key: $name ($key_address)"
    echo "- Validator: $validator"
    echo "- Amount: $amount"
    echo -e "${YELLOW}Current balance preview:${RESET}"
    printf '%s\n' "$balance_preview"
    echo -e "${YELLOW}Validator preview:${RESET}"
    printf '%s\n' "$validator_preview"
    read -r -p "Submit this delegation transaction? (yes/no): " answer
    if [[ "${answer,,}" != yes ]]; then
        echo -e "${GREEN}Delegation cancelled. No transaction was submitted.${RESET}"
        prompt_back
        menu
        return
    fi

    if worrell tx staking delegate "$validator" "$amount" \
        --from "$name" \
        --chain-id "$WORRELL_CHAIN_ID" \
        --home "$WORRELL_HOME" \
        --node "$rpc" \
        --gas auto --gas-adjustment 1.5 --gas-prices 0.025uworrell --yes; then
        echo -e "${GREEN}Delegation transaction submitted successfully.${RESET}"
    else
        echo -e "${RED}Delegation transaction failed. Review the error above.${RESET}"
    fi
    prompt_back
    menu
}

query_validator_status() {
    local address
    read -r -p "Valoper address (worrellvaloper1...): " address
    worrell query staking validator "$address" --home "$WORRELL_HOME" --node "tcp://127.0.0.1:$(get_local_rpc_port)" || true
    prompt_back
    menu
}

restart_node() {
    if sudo systemctl restart "$WORRELL_SERVICE_NAME"; then
        echo -e "${GREEN}Node restart command completed.${RESET}"
    else
        echo -e "${RED}Node restart failed. Review service status and logs.${RESET}" >&2
    fi
    prompt_back
    menu
}

stop_node() {
    if sudo systemctl stop "$WORRELL_SERVICE_NAME"; then
        echo -e "${GREEN}Node stop command completed.${RESET}"
    else
        echo -e "${RED}Node stop failed. Review service status and logs.${RESET}" >&2
    fi
    prompt_back
    menu
}

worrell_root_mode() {
    [ "${EUID:-$(id -u)}" -eq 0 ]
}

managed_worrell_home_for_mode() {
    local root_mode="$1" service_user="${WORRELL_SERVICE_USER:-worrell}"
    if [ "$root_mode" = yes ]; then
        [[ "$service_user" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] || return 1
        printf '/var/lib/%s\n' "$service_user"
        return 0
    fi
    case "${HOME:-}" in
        /*) ;;
        *) return 1 ;;
    esac
    [ "$HOME" != "/" ] || return 1
    case "$HOME" in */) return 1 ;; esac
    printf '%s/.worrell\n' "$HOME"
}

managed_worrell_home() {
    if worrell_root_mode; then
        managed_worrell_home_for_mode yes
    else
        managed_worrell_home_for_mode no
    fi
}

validate_managed_worrell_home() {
    local expected canonical
    expected=$(managed_worrell_home) || {
        echo -e "${RED}Could not determine the exact managed Worrell home. Refusing the operation.${RESET}" >&2
        return 1
    }
    [ "${WORRELL_HOME:-}" = "$expected" ] || {
        echo -e "${RED}WORRELL_HOME is not the exact managed Worrell home. Refusing the operation.${RESET}" >&2
        return 1
    }
    if [ ! -d "$WORRELL_HOME" ] || [ -L "$WORRELL_HOME" ]; then
        echo -e "${RED}Managed Worrell home is missing or is a symlink. Refusing the operation.${RESET}" >&2
        return 1
    fi
    canonical=$(readlink -f -- "$WORRELL_HOME" 2>/dev/null) || {
        echo -e "${RED}Could not resolve the managed Worrell home safely. Refusing the operation.${RESET}" >&2
        return 1
    }
    [ "$canonical" = "$expected" ] || {
        echo -e "${RED}Managed Worrell home resolves somewhere unexpected. Refusing the operation.${RESET}" >&2
        return 1
    }
}

validate_signer_material() {
    local path
    validate_managed_worrell_home || return 1
    for path in "$WORRELL_HOME/config" "$WORRELL_HOME/data"; do
        if [ ! -d "$path" ] || [ -L "$path" ]; then
            echo -e "${RED}Required Worrell signer directory is missing or unsafe: $path${RESET}" >&2
            return 1
        fi
    done
    for path in \
        "$WORRELL_HOME/config/priv_validator_key.json" \
        "$WORRELL_HOME/data/priv_validator_state.json"; do
        if [ ! -f "$path" ] || [ -L "$path" ] || [ ! -s "$path" ]; then
            echo -e "${RED}Required Worrell signer material is missing or unsafe. Refusing the operation.${RESET}" >&2
            return 1
        fi
    done
    path="$WORRELL_HOME/config/node_key.json"
    if [ -e "$path" ] || [ -L "$path" ]; then
        if [ ! -f "$path" ] || [ -L "$path" ] || [ ! -s "$path" ]; then
            echo -e "${RED}Optional Worrell node key is present but unsafe. Refusing the operation.${RESET}" >&2
            return 1
        fi
    fi
}

write_signer_backup_manifest() {
    local stage="$1" rel checksum size
    shift
    printf 'format=worrell-signer-backup-v1\n'
    printf 'created_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    for rel in "$@"; do
        checksum=$(sha256sum "$stage/$rel" 2>/dev/null) || return 1
        checksum=${checksum%% *}
        size=$(stat -c '%s' "$stage/$rel" 2>/dev/null) || return 1
        [[ "$checksum" =~ ^[0-9a-f]{64}$ ]] || return 1
        [[ "$size" =~ ^[0-9]+$ ]] || return 1
        printf 'file=%s size=%s sha256=%s\n' "$rel" "$size" "$checksum"
    done
}

create_signer_backup() {
    local stage archive listing rel
    local -a files=(
        config/priv_validator_key.json
        data/priv_validator_state.json
    )
    WORRELL_LAST_BACKUP=""
    validate_signer_material || return 1
    if [ -e "$WORRELL_HOME/config/node_key.json" ]; then
        files+=(config/node_key.json)
    fi
    stage=$(mktemp -d "$HOME/.worrell-signer-backup.XXXXXX") || {
        echo -e "${RED}Could not create a private signer backup workspace.${RESET}" >&2
        return 1
    }
    chmod 700 "$stage" || { rm -rf -- "$stage"; return 1; }
    if ! mkdir -m 700 "$stage/config" "$stage/data"; then
        rm -rf -- "$stage"
        echo -e "${RED}Could not create the private signer backup layout.${RESET}" >&2
        return 1
    fi
    for rel in "${files[@]}"; do
        if ! install -m 0600 "$WORRELL_HOME/$rel" "$stage/$rel"; then
            rm -rf -- "$stage"
            echo -e "${RED}Could not capture required signer backup material; deletion is refused.${RESET}" >&2
            return 1
        fi
    done
    for rel in "${files[@]}"; do
        if ! jq -e . "$stage/$rel" >/dev/null 2>&1; then
            rm -rf -- "$stage"
            echo -e "${RED}Signer backup material is not valid JSON; deletion is refused.${RESET}" >&2
            return 1
        fi
    done
    if ! write_signer_backup_manifest "$stage" "${files[@]}" > "$stage/manifest.txt"; then
        rm -rf -- "$stage"
        echo -e "${RED}Could not create signer backup metadata; deletion is refused.${RESET}" >&2
        return 1
    fi
    chmod 600 "$stage/manifest.txt" || { rm -rf -- "$stage"; return 1; }
    archive=$(mktemp "$HOME/worrell-validator-keys-$(date +%Y%m%d-%H%M%S)-XXXXXX.tar.gz") || {
        rm -rf -- "$stage"
        echo -e "${RED}Could not create a private signer backup artifact.${RESET}" >&2
        return 1
    }
    if ! tar -czf "$archive" -C "$stage" config data manifest.txt; then
        rm -rf -- "$stage" "$archive"
        echo -e "${RED}Signer backup archive creation failed; deletion is refused.${RESET}" >&2
        return 1
    fi
    chmod 600 "$archive" || { rm -rf -- "$stage" "$archive"; return 1; }
    listing=$(tar -tzf "$archive" 2>/dev/null) || {
        rm -rf -- "$stage" "$archive"
        echo -e "${RED}Signer backup archive verification failed; deletion is refused.${RESET}" >&2
        return 1
    }
    for rel in "${files[@]}"; do
        grep -Fqx "$rel" <<< "$listing" || {
            rm -rf -- "$stage" "$archive"
            echo -e "${RED}Signer backup archive is incomplete; deletion is refused.${RESET}" >&2
            return 1
        }
    done
    grep -Fqx manifest.txt <<< "$listing" || {
        rm -rf -- "$stage" "$archive"
        echo -e "${RED}Signer backup metadata is missing; deletion is refused.${RESET}" >&2
        return 1
    }
    rm -rf -- "$stage" || {
        rm -f -- "$archive"
        echo -e "${RED}Could not remove the temporary signer backup workspace; deletion is refused.${RESET}" >&2
        return 1
    }
    WORRELL_LAST_BACKUP="$archive"
}

backup_node() {
    if ! create_signer_backup; then
        echo -e "${RED}Signer backup failed; no further action was taken.${RESET}" >&2
    else
        echo -e "${GREEN}Validator signer/state backup created:${RESET} $WORRELL_LAST_BACKUP"
    fi
    prompt_back
    menu
}

service_is_inactive_for_delete() {
    local state
    state=$(sudo systemctl is-active "$WORRELL_SERVICE_NAME" 2>/dev/null) || true
    case "$state" in
        inactive|dead|failed) return 0 ;;
        *) return 1 ;;
    esac
}

stop_service_for_delete() {
    if ! sudo systemctl stop "$WORRELL_SERVICE_NAME" 2>/dev/null; then
        echo -e "${RED}Could not stop $WORRELL_SERVICE_NAME; deletion refused.${RESET}" >&2
        return 1
    fi
    if ! service_is_inactive_for_delete; then
        echo -e "${RED}$WORRELL_SERVICE_NAME is not confirmed inactive; deletion refused.${RESET}" >&2
        return 1
    fi
}

worrell_service_unit_path() {
    printf '/etc/systemd/system/%s.service\n' "$1"
}

prepare_delete_unit_backup() {
    local unit_path="$1" backup_name
    WORRELL_DELETE_UNIT_EXISTED=no
    WORRELL_DELETE_UNIT_BACKUP_DIR=""
    WORRELL_DELETE_UNIT_BACKUP_PATH=""
    if [ -L "$unit_path" ]; then
        echo -e "${RED}The Worrell service unit is a symlink; deletion refused.${RESET}" >&2
        return 1
    fi
    if [ -e "$unit_path" ]; then
        if [ ! -f "$unit_path" ] || [ ! -s "$unit_path" ]; then
            echo -e "${RED}The Worrell service unit is missing, empty, or not a regular file; deletion refused.${RESET}" >&2
            return 1
        fi
        WORRELL_DELETE_UNIT_BACKUP_DIR=$(mktemp -d "$HOME/.worrell-delete-unit.XXXXXX") || {
            echo -e "${RED}Could not create a private service-unit rollback workspace; deletion refused.${RESET}" >&2
            return 1
        }
        chmod 700 "$WORRELL_DELETE_UNIT_BACKUP_DIR" || {
            rm -rf -- "$WORRELL_DELETE_UNIT_BACKUP_DIR"
            WORRELL_DELETE_UNIT_BACKUP_DIR=""
            return 1
        }
        backup_name=${unit_path##*/}
        WORRELL_DELETE_UNIT_BACKUP_PATH="$WORRELL_DELETE_UNIT_BACKUP_DIR/$backup_name"
        if ! install -m 0600 "$unit_path" "$WORRELL_DELETE_UNIT_BACKUP_PATH" || [ ! -s "$WORRELL_DELETE_UNIT_BACKUP_PATH" ]; then
            rm -rf -- "$WORRELL_DELETE_UNIT_BACKUP_DIR"
            WORRELL_DELETE_UNIT_BACKUP_DIR=""
            WORRELL_DELETE_UNIT_BACKUP_PATH=""
            echo -e "${RED}Could not capture the service unit for rollback; deletion refused.${RESET}" >&2
            return 1
        fi
        WORRELL_DELETE_UNIT_EXISTED=yes
    fi
}

restore_deleted_unit() {
    [ "${WORRELL_DELETE_UNIT_EXISTED:-no}" = yes ] || return 0
    if ! sudo install -m 0644 -- "$WORRELL_DELETE_UNIT_BACKUP_PATH" "$WORRELL_DELETE_UNIT_PATH"; then
        echo -e "${RED}Could not restore the Worrell service unit; the node home remains preserved.${RESET}" >&2
        return 1
    fi
    if ! sudo systemctl daemon-reload; then
        echo -e "${RED}The Worrell service unit was restored, but systemd reload still failed; the node home remains preserved.${RESET}" >&2
        return 1
    fi
}

cleanup_deleted_unit_backup() {
    [ -z "${WORRELL_DELETE_UNIT_BACKUP_DIR:-}" ] || rm -rf -- "$WORRELL_DELETE_UNIT_BACKUP_DIR"
    WORRELL_DELETE_UNIT_BACKUP_DIR=""
    WORRELL_DELETE_UNIT_BACKUP_PATH=""
    WORRELL_DELETE_UNIT_EXISTED=no
}

delete_node() {
    local answer unit_path
    validate_managed_worrell_home || { prompt_back; menu; return; }
    is_valid_service_name "$WORRELL_SERVICE_NAME" || {
        echo -e "${RED}Service name is invalid or ambiguous; deletion refused.${RESET}" >&2
        prompt_back
        menu
        return
    }
    case "$WORRELL_SERVICE_NAME" in
        -*|.*|*..*)
            echo -e "${RED}Service name is unsafe; deletion refused.${RESET}" >&2
            prompt_back
            menu
            return
            ;;
    esac
    validate_signer_material || { prompt_back; menu; return; }
    echo -e "${RED}BACK UP validator signer and state before deleting. This stops the service and removes the node home.${RESET}"
    read -r -p "Type DELETE to continue: " answer
    if [ "$answer" != DELETE ]; then
        echo -e "${YELLOW}Deletion cancelled. No node data was changed.${RESET}"
        prompt_back
        menu
        return
    fi
    if ! stop_service_for_delete; then
        prompt_back
        menu
        return
    fi
    # Re-check the exact path and signer inputs after downtime, before capture.
    validate_signer_material || { prompt_back; menu; return; }
    if ! create_signer_backup; then
        echo -e "${RED}Signer backup failed; deletion refused.${RESET}" >&2
        prompt_back
        menu
        return
    fi
    if ! service_is_inactive_for_delete; then
        echo -e "${RED}$WORRELL_SERVICE_NAME became active again; deletion refused.${RESET}" >&2
        prompt_back
        menu
        return
    fi
    unit_path=$(worrell_service_unit_path "$WORRELL_SERVICE_NAME") || {
        echo -e "${RED}Could not resolve the Worrell service unit path; deletion refused.${RESET}" >&2
        prompt_back
        menu
        return
    }
    [ -n "$unit_path" ] || {
        echo -e "${RED}The Worrell service unit path is empty; deletion refused.${RESET}" >&2
        prompt_back
        menu
        return
    }
    WORRELL_DELETE_UNIT_PATH="$unit_path"
    if ! prepare_delete_unit_backup "$unit_path"; then
        prompt_back
        menu
        return
    fi
    if ! sudo systemctl disable "$WORRELL_SERVICE_NAME" 2>/dev/null; then
        cleanup_deleted_unit_backup
        echo -e "${RED}Could not disable $WORRELL_SERVICE_NAME; deletion refused.${RESET}" >&2
        prompt_back
        menu
        return
    fi
    if ! service_is_inactive_for_delete; then
        cleanup_deleted_unit_backup
        echo -e "${RED}$WORRELL_SERVICE_NAME is not confirmed inactive after disable; deletion refused.${RESET}" >&2
        prompt_back
        menu
        return
    fi
    if ! sudo rm -f -- "$unit_path"; then
        cleanup_deleted_unit_backup
        echo -e "${RED}Could not remove the Worrell service unit; node home was preserved.${RESET}" >&2
        prompt_back
        menu
        return
    fi
    if ! sudo systemctl daemon-reload; then
        if ! restore_deleted_unit; then
            echo -e "${RED}Service-unit rollback was not fully confirmed; node home remains preserved.${RESET}" >&2
        fi
        cleanup_deleted_unit_backup
        echo -e "${RED}Could not reload systemd after removing the service unit; node home was preserved.${RESET}" >&2
        prompt_back
        menu
        return
    fi
    if ! service_is_inactive_for_delete; then
        if ! restore_deleted_unit; then
            echo -e "${RED}Service-unit rollback was not fully confirmed; node home remains preserved.${RESET}" >&2
        fi
        cleanup_deleted_unit_backup
        echo -e "${RED}$WORRELL_SERVICE_NAME is not confirmed inactive before home removal; node home was preserved.${RESET}" >&2
        prompt_back
        menu
        return
    fi
    if ! validate_managed_worrell_home; then
        if ! restore_deleted_unit; then
            echo -e "${RED}Service-unit rollback was not fully confirmed; node home remains preserved.${RESET}" >&2
        fi
        cleanup_deleted_unit_backup
        echo -e "${RED}Managed Worrell home changed or became unsafe; deletion refused.${RESET}" >&2
        prompt_back
        menu
        return
    fi
    if ! rm -rf -- "$WORRELL_HOME" || [ -e "$WORRELL_HOME" ] || [ -L "$WORRELL_HOME" ]; then
        if ! restore_deleted_unit; then
            echo -e "${RED}Service-unit rollback was not fully confirmed; signer data remains preserved as far as possible.${RESET}" >&2
        fi
        cleanup_deleted_unit_backup
        echo -e "${RED}Could not remove the exact managed Worrell home completely. Signer backup remains at $WORRELL_LAST_BACKUP.${RESET}" >&2
        prompt_back
        menu
        return
    fi
    cleanup_deleted_unit_backup
    if [ -f "$HOME/.bash_profile" ] && ! sed -i -E '/^export WORRELL_(CHAIN_ID|HOME|SERVICE_NAME|PORT_PREFIX|MONIKER|TARGET_VERSION|UNSAFE_SKIP_BACKUP|ENV_FILE|SERVICE_USER)=/d' "$HOME/.bash_profile" 2>/dev/null; then
        echo -e "${YELLOW}Node was removed, but the shell profile could not be cleaned. Signer backup: $WORRELL_LAST_BACKUP${RESET}" >&2
    fi
    echo -e "${GREEN}Node removed. Key backup: $WORRELL_LAST_BACKUP (includes signer state and optional node key).${RESET}"
    prompt_back
    menu
}

show_guidelines() {
    echo -e "${GREEN}Guidelines${RESET}"
    echo "- 1a installs/redeploys; choose pruned/archive storage and direct worrelld/Cosmovisor runtime. Existing data is moved to a timestamped backup."
    echo "- 1b updates the binary with release checksum verification; Cosmovisor nodes use 1g."
    echo "- 1h applies a verified pruned snapshot from ITRocket or Sychonix; it preserves validator state and config."
    echo "- 1g manages Cosmovisor: migration, status, and verified upgrade staging."
    echo "- 1c compares local/public heights; wait for catching_up=false before staking."
    echo "- 1d follows service logs; press Ctrl+C to return."
    echo "- 1e restores official peers or sets them manually."
    echo "- 1f queries a key/address balance."
    echo "- 2a manages keys; keep mnemonics offline. 2b shows consensus pubkey."
    echo "- 2c creates a validator transaction after showing a reviewable JSON file."
    echo "- 2d submits unjail only after the jail period and root cause are understood."
    echo "- 2f previews balance and validator state, then submits tx staking delegate only after explicit confirmation. Use a positive integer with exactly one uworrell suffix."
    echo "- 3a/3b restart or stop the node. 3c stops and verifies the service before deletion, then keeps a private signer/state backup. 3d backs up the validator key, validator state, optional node key, and non-secret checksums."
    echo "- Never run two instances with the same priv_validator_key.json."
    echo "- RPC/API/gRPC/Prometheus should stay private unless protected."
    prompt_back
    menu
}

menu() {
    clear
    local height option main sub
    height=$(network_height || true)
    echo -e "${ORANGE}Valley of Worrell Testnet${RESET}"
    echo -e "${GREEN}Latest Block Height:${RESET} ${height:-unavailable}"
    echo -e "${GREEN}1. Node Interactions${RESET}"
    echo "   a. Install / redeploy node"
    echo "   b. Update worrelld binary"
    echo "   c. Show node status"
    echo "   d. Follow node logs"
    echo "   e. Configure persistent peers"
    echo "   f. Query account balance"
    echo "   g. Manage Cosmovisor"
    echo "   h. Apply Snapshot"
    echo -e "${GREEN}2. Validator/Key Interactions${RESET}"
    echo "   a. Create / recover / list keys"
    echo "   b. Show consensus public key"
    echo "   c. Create validator"
    echo "   d. Unjail validator"
    echo "   e. Query validator status"
    echo "   f. Delegate to validator"
    echo -e "${GREEN}3. Node Management${RESET}"
    echo "   a. Restart node"
    echo "   b. Stop node"
    echo "   c. Delete node (backup first)"
    echo "   d. Backup validator/node keys"
    echo "4. Show Endpoints & Useful Links"
    echo "5. Show Guidelines"
    echo -e "${RED}6. Exit${RESET}"
    echo -e "${YELLOW}Reminder: source ~/.bash_profile after installation.${RESET}"
    echo "Let's Buidl Worrell Together - Grand Valley"
    read -r -p "Choose an option (e.g., 1a or 1 then a): " option
    if [[ "$option" =~ ^[1-3][a-z]$ ]]; then main=${option:0:1}; sub=${option:1:1}; else main=$option; sub=""; fi
    if [[ "$main" =~ ^[1-3]$ && -z "$sub" ]]; then read -r -p "Choose a sub-option: " sub; fi
    case "$main" in
        1)
            case "$sub" in
                a) install_node ;;
                b) update_node ;;
                c) show_status ;;
                d) show_logs ;;
                e) set_peers ;;
                f) query_balance ;;
                g) manage_cosmovisor ;;
                h) apply_snapshot ;;
                *) menu ;;
            esac
            ;;
        2)
            case "$sub" in
                a) list_or_create_key ;;
                b) show_pubkey ;;
                c) create_validator ;;
                d) unjail ;;
                e) query_validator_status ;;
                f) delegate_to_validator ;;
                *) menu ;;
            esac
            ;;
        3)
            case "$sub" in
                a) restart_node ;;
                b) stop_node ;;
                c) delete_node ;;
                d) backup_node ;;
                *) menu ;;
            esac
            ;;
        4) show_endpoints; prompt_back; menu ;;
        5) show_guidelines ;;
        6) exit 0 ;;
        *) menu ;;
    esac
}

echo -e "$LOGO"
if [ ! -t 0 ]; then
    echo -e "${RED}Interactive terminal required. Re-run this launcher from a TTY.${RESET}" >&2
    exit 1
fi
echo -e "$PRIVACY_SAFETY_STATEMENT"
read -r -p "Press Enter to continue..."
show_intro
echo -e "$(show_endpoints)"
read -r -p "Press Enter to continue..."
menu
