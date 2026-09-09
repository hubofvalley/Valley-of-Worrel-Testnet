#!/usr/bin/env bash

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'
YELLOW='\033[0;33m'; ORANGE='\033[38;5;214m'; RESET='\033[0m'
# shellcheck disable=SC1091
source "$HOME/.bash_profile" 2>/dev/null || true
export PATH="$HOME/go/bin:$PATH"

WORRELL_HOME=${WORRELL_HOME:-$HOME/.worrell}
WORRELL_CHAIN_ID=${WORRELL_CHAIN_ID:-worrell-testnet-1}
WORRELL_SERVICE_NAME=${WORRELL_SERVICE_NAME:-worrelld}
WORRELL_PORT_PREFIX=${WORRELL_PORT_PREFIX:-26}
WORRELL_TARGET_VERSION=${WORRELL_TARGET_VERSION:-v0.1.2}
WORRELL_PUBLIC_RPC=${WORRELL_PUBLIC_RPC:-https://worrel-testnet-rpc.oshvank.xyz}
WORRELL_PUBLIC_RPCS=${WORRELL_PUBLIC_RPCS:-https://worrel-testnet-rpc.oshvank.xyz,https://worrell-testnet-rpc.itrocket.net,https://worrell-testnet-rpc.nodesync.top,https://worrell-testnet-rpc.bonynode.online,https://rpc-worrell.test.onenov.xyz,https://worrellchain-rpctest.codeblocklabs.com,https://t-worrell.rpc.utsa.tech}
WORRELL_PEERS=${WORRELL_PEERS:-bb9164c1bd9ed9ff2c0fd9e09b23285698e231de@164.68.98.186:26656,40128ea31b1cfb5d4b24fc9e32ee0c468586c983@worrell-testnet-peer.itrocket.net:12656}
readonly VALLEY_INSTALLER_SHA256="45aff6d87b79827787bd5efbbaf63e363c32075e3b3ef497241048560de473ec"
readonly VALLEY_UPDATER_SHA256="07ceef513c3acc65c6a4efa6540f92bf037ce66b16d524f424ca2c07e55a1b70"
readonly VALLEY_COSMOVISOR_MIGRATION_SHA256="9df395e015b0add3b8d73865425f8cd397a4dcdcf9329e65ba34c61253f298f7"
readonly VALLEY_COSMOVISOR_UPGRADE_SHA256="374a7f2f1e2f268ad328414d71baf4a73df7dd1b8b2af165e21e18d5e819dacc"
readonly VALLEY_SCRIPT_BASE="https://raw.githubusercontent.com/hubofvalley/Valley-of-Worrel-Testnet/eeaca969033146d15b26823969ac888d938baa48/resources"

LOGO=''
LOGO+=' __      __                    _ _               _\n'
LOGO+=' \ \    / /                   | | |             | |\n'
LOGO+='  \ \  / /__  _ __ _ __ ___   | | |  ___  _ __  | |\n'
LOGO+='   \ \/ / _ \|  __|  __/ _ \  | | | / _ \|  _ \ | |\n'
LOGO+='    \  / (_) | |  | | | (_) | | | ||  __/| | | || |\n'
LOGO+='     \/ \___/|_|  |_|  \___/  |_|_| \___||_| |_||_|\n'
LOGO+='\n'
LOGO+=' __      __              _ _   _   _             \n'
LOGO+='/__ __ __ __|__ _ __ __ _| | | | | | |            \n'
LOGO+='\_| | (_| | | | (_| | | (_| | | | | | |           \n'
LOGO+='                  Grand Valley                 \n'

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
    port=${port:-26657}
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

run_pinned_child() {
    local script="$1" expected="$2" path tmp actual rc
    shift 2
    tmp=""
    case "$script" in
        worrelld_node_install_testnet.sh) expected="$VALLEY_INSTALLER_SHA256" ;;
        worrelld_update.sh) expected="$VALLEY_UPDATER_SHA256" ;;
        cosmovisor_migration.sh) expected="$VALLEY_COSMOVISOR_MIGRATION_SHA256" ;;
        worrelld_cosmovisor_upgrade.sh) expected="$VALLEY_COSMOVISOR_UPGRADE_SHA256" ;;
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
Valley of Worrel by ${ORANGE}Grand Valley${RESET}

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
    clear
    echo -e "${RED}▓▒░ IMPORTANT DISCLAIMER AND TERMS ░▒▓${RESET}"
    echo -e "${YELLOW}SECURITY${RESET}: scripts stay local; audit source before running."
    echo -e "${YELLOW}SYSTEM IMPACT${RESET}: creates/replaces ${WORRELL_SERVICE_NAME}.service, node home ${WORRELL_HOME}, and remaps ports with a two-digit prefix. Existing home is moved to a timestamped backup."
    echo -e "${YELLOW}REQUIREMENTS${RESET}: Ubuntu 22.04+, 2 vCPU, 4 GB RAM, 100 GB SSD, public P2P reachability."
    echo -e "${YELLOW}VALIDATOR RESPONSIBILITIES${RESET}: keep uptime, protect keys, update safely, and avoid double-signing."
    read -r -p "Proceed with installation/redeployment? (yes/no): " answer
    if [[ "${answer,,}" != yes ]]; then echo -e "${RED}Installation cancelled.${RESET}"; menu; return; fi
    run_pinned_child worrelld_node_install_testnet.sh "$VALLEY_INSTALLER_SHA256"
    # Refresh the one-time service/home settings saved by the child installer.
    # shellcheck disable=SC1091
    source "$HOME/.bash_profile" 2>/dev/null || true
    WORRELL_HOME=${WORRELL_HOME:-$HOME/.worrell}
    WORRELL_SERVICE_NAME=${WORRELL_SERVICE_NAME:-worrelld}
    WORRELL_PORT_PREFIX=${WORRELL_PORT_PREFIX:-26}
    menu
}

cosmovisor_active() {
    local unit="/etc/systemd/system/${WORRELL_SERVICE_NAME}.service"
    if [ -r "$unit" ]; then
        grep -qE "^ExecStart=.*cosmovisor[[:space:]]+run" "$unit"
    else
        sudo systemctl cat "$WORRELL_SERVICE_NAME" 2>/dev/null | grep -qE "ExecStart=.*cosmovisor[[:space:]]+run"
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

manage_cosmovisor() {
    echo -e "${ORANGE}Manage Cosmovisor${RESET}"
    echo "1. Migrate current node to Cosmovisor"
    echo "2. Show Cosmovisor status"
    echo "3. Stage a verified upgrade binary"
    echo "4. Back"
    read -r -p "Choose an option (1-4): " choice
    case "$choice" in
        1) run_pinned_child cosmovisor_migration.sh "$VALLEY_COSMOVISOR_MIGRATION_SHA256"; menu ;;
        2) show_cosmovisor_status ;;
        3)
            if ! cosmovisor_active; then
                echo -e "${RED}Migrate the node to Cosmovisor first.${RESET}"; prompt_back; menu; return
            fi
            read -r -p "Release version (for example v0.1.2): " version
            read -r -p "On-chain upgrade name: " upgrade_name
            read -r -p "Emergency upgrade height (leave empty for governance plan): " upgrade_height
            run_pinned_child worrelld_cosmovisor_upgrade.sh "$VALLEY_COSMOVISOR_UPGRADE_SHA256" "$version" "$upgrade_name" "$upgrade_height"
            menu
            ;;
        4) menu ;;
        *) echo -e "${RED}Invalid option.${RESET}"; menu ;;
    esac
}

update_node() {
    if cosmovisor_active; then
        echo -e "${YELLOW}Cosmovisor is active. Use Manage Cosmovisor to stage an upgrade binary; direct replacement is disabled.${RESET}"
        manage_cosmovisor
        return
    fi
    echo -e "${YELLOW}Updates the local worrelld binary after release checksum verification and briefly restarts the service.${RESET}"
    read -r -p "Proceed? (yes/no): " answer
    if [[ "${answer,,}" == yes ]]; then run_pinned_child worrelld_update.sh "$VALLEY_UPDATER_SHA256"; fi
    menu
}

show_status() {
    local lh nh diff catching port
    lh=$(local_height || true); nh=$(network_height || true); port=$(get_local_rpc_port); port=${port:-26657}
    catching=$(local_status "$port" | jq -r '.result.sync_info.catching_up // "unknown"' 2>/dev/null || echo unknown)
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

show_logs() { sudo journalctl -u "$WORRELL_SERVICE_NAME" -fn 100 -o cat; menu; }

set_peers() {
    local cfg="$WORRELL_HOME/config/config.toml" choice peers
    [ -f "$cfg" ] || { echo -e "${RED}Node config not found. Install first.${RESET}"; prompt_back; menu; return; }
    echo "1. Restore official peers"; echo "2. Enter peers manually"; echo "3. Back"
    read -r -p "Choose: " choice
    case "$choice" in
        1) peers="$WORRELL_PEERS" ;;
        2) read -r -p "persistent_peers (<id>@<host>:<port>,...): " peers ;;
        *) menu; return ;;
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
        2) read -r -p "Key name: " name; worrell keys add "$name" --home "$WORRELL_HOME" ;;
        3) read -r -p "Key name: " name; worrell keys add "$name" --recover --home "$WORRELL_HOME" ;;
        *) menu; return ;;
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
    local name moniker amount rate max_rate max_change min_self tmp sync answer
    sync=$(local_status | jq -r '.result.sync_info.catching_up // "unknown"' 2>/dev/null || echo unknown)
    [ "$sync" = false ] || { echo -e "${RED}Node is not confirmed synced (catching_up=$sync). Wait, then retry.${RESET}"; prompt_back; menu; return; }
    read -r -p "Key name: " name
    worrell keys show "$name" -a --home "$WORRELL_HOME" >/dev/null
    echo -e "${YELLOW}Current account balance:${RESET}"
    worrell query bank balances "$(worrell keys show "$name" -a --home "$WORRELL_HOME")" --home "$WORRELL_HOME" --node "tcp://127.0.0.1:$(get_local_rpc_port)" || true
    read -r -p "Validator moniker [Worrel-Grand-Valley]: " moniker; moniker=${moniker:-Worrel-Grand-Valley}
    read -r -p "Self-delegation amount in uworrell [20000000000000]: " amount; amount=${amount:-20000000000000}
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
    jq -n --arg pubkey "$(worrell tendermint show-validator --home "$WORRELL_HOME")" --arg amount "$amount" --arg moniker "$moniker" --arg rate "$rate" --arg max_rate "$max_rate" --arg max_change "$max_change" --arg min_self "$min_self" '{pubkey:($pubkey|fromjson),amount:$amount,moniker:$moniker,identity:"",website:"",security:"",details:"Worrell testnet validator", "commission-rate":$rate,"commission-max-rate":$max_rate,"commission-max-change-rate":$max_change,"min-self-delegation":$min_self}' > "$tmp"
    echo -e "${YELLOW}Review validator JSON:${RESET}"; cat "$tmp"
    read -r -p "Submit on-chain create-validator transaction? (yes/no): " answer
    if [[ "${answer,,}" == yes ]]; then
        worrell tx staking create-validator "$tmp" --from "$name" --chain-id "$WORRELL_CHAIN_ID" --home "$WORRELL_HOME" --node "tcp://127.0.0.1:$(get_local_rpc_port)" --gas auto --gas-adjustment 1.5 --gas-prices 0.025uworrell --yes
    fi
    rm -f "$tmp"
    menu
}

unjail() {
    local name answer
    read -r -p "Key name: " name
    read -r -p "Submit unjail transaction? (yes/no): " answer
    if [[ "${answer,,}" == yes ]]; then worrell tx slashing unjail --from "$name" --chain-id "$WORRELL_CHAIN_ID" --home "$WORRELL_HOME" --node "tcp://127.0.0.1:$(get_local_rpc_port)" --gas auto --gas-adjustment 1.5 --gas-prices 0.025uworrell --yes; fi
    menu
}

query_validator_status() {
    local address
    read -r -p "Valoper address (worrellvaloper1...): " address
    worrell query staking validator "$address" --home "$WORRELL_HOME" --node "tcp://127.0.0.1:$(get_local_rpc_port)" || true
    prompt_back
    menu
}

restart_node() { sudo systemctl restart "$WORRELL_SERVICE_NAME"; menu; }
stop_node() { sudo systemctl stop "$WORRELL_SERVICE_NAME"; menu; }

backup_node() {
    local dest temp
    [ -f "$WORRELL_HOME/config/priv_validator_key.json" ] || { echo -e "${RED}Validator signing key not found.${RESET}"; prompt_back; menu; return; }
    dest="$HOME/worrell-validator-keys-$(date +%Y%m%d-%H%M%S).tar.gz"
    temp=$(mktemp -d)
    cp -p "$WORRELL_HOME/config/priv_validator_key.json" "$temp/priv_validator_key.json"
    [ ! -f "$WORRELL_HOME/config/node_key.json" ] || cp -p "$WORRELL_HOME/config/node_key.json" "$temp/node_key.json"
    chmod 600 "$temp"/*
    if ! tar -czf "$dest" -C "$temp" .; then
        rm -rf "$temp" "$dest"
        echo -e "${RED}Key backup failed; no further action taken.${RESET}"
    else
        chmod 600 "$dest"
        rm -rf "$temp"
        echo -e "${GREEN}Validator/node key backup created:${RESET} $dest"
    fi
    prompt_back
    menu
}

delete_node() {
    local answer backup temp
    echo -e "${RED}BACK UP validator keys before deleting. This stops the service and removes the node home.${RESET}"
    read -r -p "Type DELETE to continue: " answer
    [ "$answer" = DELETE ] || { menu; return; }
    case "$WORRELL_HOME" in
        "$HOME/.worrell"|"$HOME"/*) ;;
        *) echo -e "${RED}Refusing deletion outside the current user's home.${RESET}"; menu; return ;;
    esac
    [ -f "$WORRELL_HOME/config/priv_validator_key.json" ] || { echo -e "${RED}Signing key is missing; refusing deletion without a verified backup source.${RESET}"; menu; return; }
    backup="$HOME/worrell-validator-keys-$(date +%Y%m%d-%H%M%S).tar.gz"
    temp=$(mktemp -d)
    if ! cp -p "$WORRELL_HOME/config/priv_validator_key.json" "$temp/priv_validator_key.json" || ! tar -czf "$backup" -C "$temp" .; then
        rm -rf "$temp" "$backup"
        echo -e "${RED}Key backup failed; deletion refused.${RESET}"
        menu
        return
    fi
    chmod 600 "$backup"; rm -rf "$temp"
    sudo systemctl disable --now "$WORRELL_SERVICE_NAME" 2>/dev/null || true
    sudo rm -f "/etc/systemd/system/${WORRELL_SERVICE_NAME}.service"
    rm -rf "$WORRELL_HOME"
    sed -i -E '/^export WORRELL_(CHAIN_ID|HOME|SERVICE_NAME|PORT_PREFIX|MONIKER|TARGET_VERSION)=/d' "$HOME/.bash_profile" 2>/dev/null || true
    sudo systemctl daemon-reload
    echo -e "${GREEN}Node removed. Key backup: $backup${RESET}"
    menu
}

show_guidelines() {
    echo -e "${GREEN}Guidelines${RESET}"
    echo "- 1a installs/redeploys; existing data is moved to a timestamped backup."
    echo "- 1b updates the binary with release checksum verification; Cosmovisor nodes use 1g."
    echo "- 1g manages Cosmovisor: migration, status, and verified upgrade staging."
    echo "- 1c compares local/public heights; wait for catching_up=false before staking."
    echo "- 1d follows service logs; press Ctrl+C to return."
    echo "- 1e restores official peers or sets them manually."
    echo "- 1f queries a key/address balance."
    echo "- 2a manages keys; keep mnemonics offline. 2b shows consensus pubkey."
    echo "- 2c creates a validator transaction after showing a reviewable JSON file."
    echo "- 2d submits unjail only after the jail period and root cause are understood."
    echo "- 3a/3b restart or stop the node. 3c deletes after a successful key backup and typed confirmation. 3d backs up validator/node keys only."
    echo "- Never run two instances with the same priv_validator_key.json."
    echo "- RPC/API/gRPC/Prometheus should stay private unless protected."
    prompt_back
    menu
}

menu() {
    clear
    local height option main sub
    height=$(network_height || true)
    echo -e "${ORANGE}Valley of Worrel Testnet${RESET}"
    echo -e "${GREEN}Latest Block Height:${RESET} ${height:-unavailable}"
    echo -e "${GREEN}1. Node Interactions${RESET}"
    echo "   a. Install / redeploy node"
    echo "   b. Update worrelld binary"
    echo "   c. Show node status"
    echo "   d. Follow node logs"
    echo "   e. Configure persistent peers"
    echo "   f. Query account balance"
    echo "   g. Manage Cosmovisor"
    echo -e "${GREEN}2. Validator/Key Interactions${RESET}"
    echo "   a. Create / recover / list keys"
    echo "   b. Show consensus public key"
    echo "   c. Create validator"
    echo "   d. Unjail validator"
    echo "   e. Query validator status"
    echo -e "${GREEN}3. Node Management${RESET}"
    echo "   a. Restart node"
    echo "   b. Stop node"
    echo "   c. Delete node (backup first)"
    echo "   d. Backup validator/node keys"
    echo "4. Show Endpoints & Useful Links"
    echo "5. Show Guidelines"
    echo -e "${RED}6. Exit${RESET}"
    echo -e "${YELLOW}Reminder: source ~/.bash_profile after installation.${RESET}"
    echo "Let's Buidl Worrel Together - Grand Valley"
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
echo -e "$PRIVACY_SAFETY_STATEMENT"
read -r -p "Press Enter to continue..."
show_intro
echo -e "$(show_endpoints)"
read -r -p "Press Enter to continue..."
menu
