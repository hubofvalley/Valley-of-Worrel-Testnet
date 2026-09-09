#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'
YELLOW='\033[0;33m'; ORANGE='\033[38;5;214m'; RESET='\033[0m'

# Provider sources reviewed on 2026-09-09. ITRocket uses live metadata because
# its filename rotates; Sychonix publishes a concrete rolling archive URL.
readonly ITROCKET_META_URL="https://server-3.itrocket.net/testnet/worrell/.current_state.json"
readonly ITROCKET_BASE_URL="https://server-3.itrocket.net/testnet/worrell"
readonly SYCHONIX_SNAPSHOT_URL="https://snapshot.sychonix.com/testnet/worrell/worrell-snapshot.tar.lz4"
readonly WORRELL_HOME="${WORRELL_HOME:-$HOME/.worrell}"
readonly WORRELL_SERVICE_NAME="${WORRELL_SERVICE_NAME:-worrelld}"

prompt_back_or_continue() { read -r -p "Press Enter to continue..."; }

require_local_node() {
    [ -f "$WORRELL_HOME/config/genesis.json" ] || { echo -e "${RED}Worrell config not found. Install the node first.${RESET}" >&2; return 1; }
    jq -e '.chain_id == "worrell-testnet-1"' "$WORRELL_HOME/config/genesis.json" >/dev/null || { echo -e "${RED}Local genesis is not worrell-testnet-1. Refusing snapshot application.${RESET}" >&2; return 1; }
    [ -d "$WORRELL_HOME/data" ] || { echo -e "${RED}Worrell data directory not found. Install and sync the node first.${RESET}" >&2; return 1; }
    [ -f "$WORRELL_HOME/data/priv_validator_state.json" ] || { echo -e "${RED}Validator state file not found. Refusing snapshot application.${RESET}" >&2; return 1; }
    [ ! -e "$WORRELL_HOME/data/upgrade-info.json" ] || { echo -e "${RED}Pending upgrade-info.json exists. Resolve the pending upgrade before applying a snapshot.${RESET}" >&2; return 1; }
}

show_snapshot_type() {
    echo -e "${GREEN}Choose the type of snapshot for $1:${RESET}"
    echo "1. Pruned"
    echo "2. Archive"
    echo "3. Back"
}

resolve_itrocket() {
    local metadata snapshot_name
    metadata=$(curl -fsSL --retry 3 --connect-timeout 10 --max-time 30 "$ITROCKET_META_URL") || {
        echo -e "${RED}ITRocket snapshot metadata is unavailable.${RESET}" >&2
        return 1
    }
    snapshot_name=$(jq -r '.snapshot_name // empty' <<< "$metadata")
    [[ "$snapshot_name" =~ ^[A-Za-z0-9._-]+\.tar\.lz4$ ]] || {
        echo -e "${RED}ITRocket returned an unsafe or missing snapshot filename. Refusing use.${RESET}" >&2
        return 1
    }
    SNAPSHOT_URL="$ITROCKET_BASE_URL/$snapshot_name"
    SNAPSHOT_PROVIDER="ITRocket"
    SNAPSHOT_HEIGHT=$(jq -r '.snapshot_height // "unknown"' <<< "$metadata")
    SNAPSHOT_SIZE=$(jq -r '.snapshot_size // "unknown"' <<< "$metadata")
    SNAPSHOT_UPDATED=$(jq -r '.snapshot_block_time // "unknown"' <<< "$metadata")
    SNAPSHOT_PRUNING=$(jq -r '.pruning // "unknown"' <<< "$metadata")
}

resolve_sychonix() {
    SNAPSHOT_URL="$SYCHONIX_SNAPSHOT_URL"
    SNAPSHOT_PROVIDER="Sychonix"
    SNAPSHOT_HEIGHT="not published in the provider page"
    SNAPSHOT_SIZE="checked from archive response"
    SNAPSHOT_UPDATED="rolling archive; provider page"
    SNAPSHOT_PRUNING="provider documents custom pruning"
}

show_snapshot_details() {
    echo -e "${GREEN}${SNAPSHOT_PROVIDER} pruned snapshot${RESET}"
    echo -e "${CYAN}URL:${RESET} $SNAPSHOT_URL"
    echo -e "${CYAN}Height:${RESET} $SNAPSHOT_HEIGHT"
    echo -e "${CYAN}Size:${RESET} $SNAPSHOT_SIZE"
    echo -e "${CYAN}Updated:${RESET} $SNAPSHOT_UPDATED"
    echo -e "${CYAN}Provider pruning:${RESET} $SNAPSHOT_PRUNING"
    echo -e "${YELLOW}The archive replaces only node data. Config and validator keys are never imported.${RESET}"
}

snapshot_headers_are_binary() {
    grep -qiE '^content-type:[[:space:]]*application/(x-)?lz4|^content-type:[[:space:]]*application/octet-stream' "$1"
}

check_snapshot_url() {
    local headers
    headers=$(mktemp)
    if ! curl -fsSIL --retry 2 --connect-timeout 10 --max-time 30 -D "$headers" -o /dev/null "$SNAPSHOT_URL"; then
        rm -f "$headers"
        echo -e "${RED}Snapshot archive is unavailable.${RESET}" >&2
        return 1
    fi
    if ! snapshot_headers_are_binary "$headers"; then
        rm -f "$headers"
        echo -e "${RED}Snapshot URL did not return an LZ4/octet-stream archive.${RESET}" >&2
        return 1
    fi
    rm -f "$headers"
    echo -e "${GREEN}Snapshot archive available.${RESET}"
}

validate_archive_layout() {
    local archive="$1" listing="$2" details="${2}.details"
    lz4 -t "$archive" >/dev/null
    lz4 -dc "$archive" | tar -tf - > "$listing"
    [ -s "$listing" ] || { echo -e "${RED}Snapshot archive is empty.${RESET}" >&2; return 1; }
    awk '
        BEGIN { has_data = 0; bad = 0 }
        /^data\/$/ { has_data = 1 }
        /^data\// { next }
        { bad = 1 }
        END {
            if (!has_data || bad) exit 1
        }
    ' "$listing" || {
        echo -e "${RED}Snapshot archive must contain only a top-level data/ directory.${RESET}" >&2
        return 1
    }
    if grep -Eq '(^/|(^|/)\.\.(\/|$))' "$listing"; then
        echo -e "${RED}Snapshot archive contains an unsafe path.${RESET}" >&2
        return 1
    fi
    lz4 -dc "$archive" | tar -tvf - > "$details"
    awk '$1 !~ /^[-d]/ { exit 1 }' "$details" || {
        echo -e "${RED}Snapshot archive contains a symlink, hard link, or special file.${RESET}" >&2
        return 1
    }
}

extract_snapshot() {
    local archive="$1" target="$2"
    mkdir -p "$target"
    lz4 -dc "$archive" | tar -xf - --no-same-owner --no-same-permissions -C "$target"
    [ -d "$target/data" ] || { echo -e "${RED}Verified archive did not produce data/.${RESET}" >&2; return 1; }
    [ -d "$target/data/application.db" ] && [ -d "$target/data/state.db" ] || { echo -e "${RED}Verified archive is missing Worrell application/state databases.${RESET}" >&2; return 1; }
    rm -f "$target/data/priv_validator_state.json" "$target/data/upgrade-info.json"
}

rollback_snapshot() {
    local old_data="$1" rollback_data="$2" was_active="$3"
    echo -e "${RED}Snapshot operation failed; restoring the previous node data.${RESET}" >&2
    sudo systemctl stop "$WORRELL_SERVICE_NAME" 2>/dev/null || true
    rm -rf "$old_data"
    if [ -d "$rollback_data" ]; then mv "$rollback_data" "$old_data"; fi
    if [ "$was_active" = yes ]; then
        sudo systemctl start "$WORRELL_SERVICE_NAME" || true
    fi
}

wait_for_healthy_service() {
    local port attempt response
    port=$(awk -F: '/^[[:space:]]*laddr[[:space:]]*=.*127\.0\.0\.1:/ {gsub(/".*/, "", $3); print $3; exit}' "$WORRELL_HOME/config/config.toml")
    port=${port:-26657}
    for attempt in 1 2 3 4 5; do
        sudo systemctl is-active --quiet "$WORRELL_SERVICE_NAME" || return 1
        response=$(curl -fsS --connect-timeout 2 --max-time 5 "http://127.0.0.1:${port}/status" 2>/dev/null || true)
        if jq -e '.result.node_info.network == "worrell-testnet-1" and (.result.sync_info.latest_block_height | tonumber) >= 1' >/dev/null 2>&1 <<< "$response"; then
            return 0
        fi
        sleep 3
    done
    return 1
}

apply_selected_snapshot() {
    local workdir archive headers listing extracted state_backup timestamp old_data rollback_data was_active=no
    workdir=$(mktemp -d)
    trap 'rm -rf "$workdir"' RETURN
    archive="$workdir/worrell-snapshot.tar.lz4"
    headers="$workdir/headers"
    listing="$workdir/listing"
    extracted="$workdir/extracted"
    timestamp=$(date -u +%Y%m%dT%H%M%SZ)
    old_data="$WORRELL_HOME/data"
    rollback_data="$WORRELL_HOME/.valley-snapshot-rollback-$timestamp"

    echo -e "${GREEN}Downloading and validating $SNAPSHOT_PROVIDER snapshot before downtime...${RESET}"
    curl -fsSL --retry 3 --connect-timeout 10 --max-time 3600 -D "$headers" "$SNAPSHOT_URL" -o "$archive"
    snapshot_headers_are_binary "$headers" || { echo -e "${RED}Downloaded snapshot response was not an LZ4/octet-stream archive.${RESET}" >&2; return 1; }
    [ "$(stat -c '%s' "$archive")" -ge 1048576 ] || { echo -e "${RED}Snapshot archive is unexpectedly small.${RESET}" >&2; return 1; }
    validate_archive_layout "$archive" "$listing"
    extract_snapshot "$archive" "$extracted"

    read -r -p "Type APPLY-WORRELL-SNAPSHOT to replace node data: " confirm
    [ "$confirm" = APPLY-WORRELL-SNAPSHOT ] || { echo -e "${YELLOW}Snapshot cancelled before downtime.${RESET}"; return 0; }

    if sudo systemctl is-active --quiet "$WORRELL_SERVICE_NAME"; then was_active=yes; fi
    if ! sudo systemctl stop "$WORRELL_SERVICE_NAME"; then
        echo -e "${RED}Could not stop $WORRELL_SERVICE_NAME; snapshot was not applied.${RESET}" >&2
        return 1
    fi
    sudo systemctl is-active --quiet "$WORRELL_SERVICE_NAME" && {
        echo -e "${RED}$WORRELL_SERVICE_NAME is still active after stop; refusing data replacement.${RESET}" >&2
        [ "$was_active" = yes ] && sudo systemctl start "$WORRELL_SERVICE_NAME" || true
        return 1
    }
    state_backup="$workdir/priv_validator_state.json"
    if ! install -m 0600 "$old_data/priv_validator_state.json" "$state_backup"; then
        echo -e "${RED}Could not back up validator state after stopping the service.${RESET}" >&2
        [ "$was_active" = yes ] && sudo systemctl start "$WORRELL_SERVICE_NAME" || true
        return 1
    fi
    if ! mv "$old_data" "$rollback_data"; then
        echo -e "${RED}Could not prepare the rollback data directory.${RESET}" >&2
        [ "$was_active" = yes ] && sudo systemctl start "$WORRELL_SERVICE_NAME" || true
        return 1
    fi
    if ! mv "$extracted/data" "$old_data"; then
        rollback_snapshot "$old_data" "$rollback_data" "$was_active"
        return 1
    fi
    if ! install -m 0600 "$state_backup" "$old_data/priv_validator_state.json"; then
        rollback_snapshot "$old_data" "$rollback_data" "$was_active"
        return 1
    fi
    if ! sync; then
        rollback_snapshot "$old_data" "$rollback_data" "$was_active"
        return 1
    fi

    if [ "$was_active" = yes ]; then
        if ! sudo systemctl start "$WORRELL_SERVICE_NAME"; then
            rollback_snapshot "$old_data" "$rollback_data" "$was_active"
            return 1
        fi
        if ! wait_for_healthy_service; then
            rollback_snapshot "$old_data" "$rollback_data" "$was_active"
            return 1
        fi
    fi
    if ! rm -rf "$rollback_data"; then
        echo -e "${YELLOW}Snapshot applied, but rollback data could not be removed: $rollback_data${RESET}" >&2
    fi
    echo -e "${GREEN}Snapshot applied successfully. Validator state and config were preserved.${RESET}"
    echo -e "${CYAN}Provider:${RESET} $SNAPSHOT_PROVIDER"
    echo -e "${CYAN}Snapshot height:${RESET} $SNAPSHOT_HEIGHT"
    echo -e "${CYAN}Service:${RESET} $WORRELL_SERVICE_NAME (${was_active/yes/restarted})"
    prompt_back_or_continue
}

choose_snapshot_type() {
    local provider="$1" choice
    while true; do
        show_snapshot_type "$provider"
        read -r -p "Enter your choice: " choice
        case "$choice" in
            1)
                if [ "$provider" = ITRocket ]; then resolve_itrocket; else resolve_sychonix; fi || return 1
                show_snapshot_details
                check_snapshot_url || return 1
                prompt_back_or_continue
                apply_selected_snapshot
                return
                ;;
            2)
                echo -e "${YELLOW}Archive snapshot is not verified/available for $provider. Option reserved for future use.${RESET}"
                prompt_back_or_continue
                ;;
            3) return 0 ;;
            *) echo -e "${RED}Invalid choice. Please select 1, 2, or 3.${RESET}" ;;
        esac
    done
}

main() {
    require_local_node || exit 1
    local choice
    while true; do
        echo -e "${GREEN}Choose a snapshot provider:${RESET}"
        echo "1. ITRocket"
        echo "2. Sychonix"
        echo "3. Back"
        read -r -p "Enter your choice: " choice
        case "$choice" in
            1) choose_snapshot_type ITRocket; return ;;
            2) choose_snapshot_type Sychonix; return ;;
            3) return 0 ;;
            *) echo -e "${RED}Invalid choice. Please select 1, 2, or 3.${RESET}" ;;
        esac
    done
}

main "$@"
