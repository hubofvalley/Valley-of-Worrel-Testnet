#!/usr/bin/env bash
set -eo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'
YELLOW='\033[0;33m'; ORANGE='\033[38;5;214m'; RESET='\033[0m'

# Load the controlled installer environment without making root mode depend on
# /root/.bash_profile. Profile loading is retained for normal-user PATH setup.
source "$HOME/.bash_profile" 2>/dev/null || true
set -u
export PATH="$HOME/go/bin:/usr/local/bin:$PATH"
ROOT_MODE=no
if [ "${EUID:-$(id -u)}" -eq 0 ]; then ROOT_MODE=yes; fi

# Provider sources reviewed on 2026-09-09. ITRocket uses live metadata because
# its filename rotates; Sychonix publishes a concrete rolling archive URL.
readonly ITROCKET_META_URL="https://server-3.itrocket.net/testnet/worrell/.current_state.json"
readonly ITROCKET_BASE_URL="https://server-3.itrocket.net/testnet/worrell"
readonly SYCHONIX_SNAPSHOT_URL="https://snapshot.sychonix.com/testnet/worrell/worrell-snapshot.tar.lz4"
WORRELL_HOME="${WORRELL_HOME:-$([ "$ROOT_MODE" = yes ] && printf '/var/lib/%s' "${WORRELL_SERVICE_USER:-worrell}" || printf '%s' "$HOME/.worrell")}"
if [ "$ROOT_MODE" = yes ]; then
    WORRELL_ENV_FILE=/etc/worrelld/worrelld.env
else
    WORRELL_ENV_FILE="${WORRELL_ENV_FILE:-$WORRELL_HOME/.worrell.env}"
fi
if [ -r "$WORRELL_ENV_FILE" ]; then
    # shellcheck disable=SC1090
    source "$WORRELL_ENV_FILE"
fi
WORRELL_SERVICE_NAME="${WORRELL_SERVICE_NAME:-worrelld}"
WORRELL_SERVICE_USER="${WORRELL_SERVICE_USER:-$([ "$ROOT_MODE" = yes ] && printf worrell || id -un)}"
WORRELL_SERVICE_GROUP="${WORRELL_SERVICE_GROUP:-$WORRELL_SERVICE_USER}"
if [ "$ROOT_MODE" = yes ]; then sudo() { "$@"; }; fi

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

fix_node_ownership() {
    [ "$ROOT_MODE" = yes ] || return 0
    chown -R "$WORRELL_SERVICE_USER:$WORRELL_SERVICE_GROUP" "$1"
}

service_is_inactive() {
    local state
    state=$(sudo systemctl is-active "$WORRELL_SERVICE_NAME" 2>/dev/null || true)
    case "$state" in
        inactive|failed|dead) return 0 ;;
        *) return 1 ;;
    esac
}

signer_state_tuple() {
    jq -e -r '[.height, .round, .step] | map(tostring) | map(select(test("^[0-9]+$")) | tonumber) | if length == 3 then @tsv else error("invalid signer state") end' "$1" 2>/dev/null
}

signer_state_at_least() {
    local old_state="$1" new_state="$2" oh or os nh nr ns
    read -r oh or os <<< "$(signer_state_tuple "$old_state")" || return 1
    read -r nh nr ns <<< "$(signer_state_tuple "$new_state")" || return 1
    ((nh > oh || (nh == oh && nr > or) || (nh == oh && nr == or && ns >= os)))
}

rollback_snapshot() {
    local old_data="$1" rollback_data="$2" was_active="$3" service_started="${4:-no}"
    local fresh_state="" fresh_state_valid=no old_state="$rollback_data/priv_validator_state.json"
    echo -e "${RED}Snapshot operation failed; restoring the previous node data.${RESET}" >&2

    # Fence the replacement process before touching either data tree. If it
    # cannot be confirmed inactive, leave both trees untouched for manual recovery.
    if ! sudo systemctl stop "$WORRELL_SERVICE_NAME" 2>/dev/null; then
        if ! service_is_inactive; then
            echo -e "${RED}Could not stop the replacement service safely. Data was not changed; validator remains offline for manual recovery.${RESET}" >&2
            return 1
        fi
    fi
    if ! service_is_inactive; then
        echo -e "${RED}Replacement service is not confirmed inactive. Data was not changed; validator remains offline for manual recovery.${RESET}" >&2
        return 1
    fi

    # Capture signer state only after the replacement process is fenced. Never
    # restart with a state older than the state already used by that process.
    if [ "$service_started" = yes ] && [ -f "$old_data/priv_validator_state.json" ]; then
        if fresh_state=$(mktemp) && install -m 0600 "$old_data/priv_validator_state.json" "$fresh_state" && signer_state_at_least "$old_state" "$fresh_state"; then
            fresh_state_valid=yes
        fi
    fi

    rm -rf "$old_data"
    if [ -d "$rollback_data" ]; then mv "$rollback_data" "$old_data"; fi

    fix_node_ownership "$old_data"
    if [ "$service_started" = yes ]; then
        if [ "$fresh_state_valid" = yes ]; then
            install -m 0600 "$fresh_state" "$old_data/priv_validator_state.json"
            fix_node_ownership "$old_data"
            restore_prior_service_state "$was_active" || true
        else
            echo -e "${RED}Fresh signer state was missing, invalid, or regressed. Validator remains offline for manual recovery.${RESET}" >&2
        fi
    else
        restore_prior_service_state "$was_active" || true
    fi
    [ -z "$fresh_state" ] || rm -f "$fresh_state"
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

restore_prior_service_state() {
    local was_active="$1"
    if [ "$was_active" = yes ]; then
        if ! sudo systemctl start "$WORRELL_SERVICE_NAME"; then
            echo -e "${RED}Could not restore the previously active $WORRELL_SERVICE_NAME service.${RESET}" >&2
            return 1
        fi
        if ! wait_for_healthy_service; then
            echo -e "${RED}Previously active $WORRELL_SERVICE_NAME did not pass health checks after restoration.${RESET}" >&2
            return 1
        fi
    else
        sudo systemctl stop "$WORRELL_SERVICE_NAME" 2>/dev/null || true
    fi
}

apply_selected_snapshot() (
    local workdir archive headers listing extracted state_backup timestamp old_data rollback_data was_active=no
    workdir=$(mktemp -d)
    trap 'rm -rf "$workdir"' EXIT
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
        restore_prior_service_state "$was_active" || true
        return 1
    fi
    if ! service_is_inactive; then
        echo -e "${RED}$WORRELL_SERVICE_NAME is not confirmed inactive after stop; refusing data replacement.${RESET}" >&2
        restore_prior_service_state "$was_active" || true
        return 1
    fi
    if [ -e "$old_data/upgrade-info.json" ]; then
        echo -e "${RED}A pending upgrade-info.json appeared while the service was stopping. Snapshot aborted without replacing data.${RESET}" >&2
        restore_prior_service_state "$was_active" || true
        return 1
    fi
    state_backup="$workdir/priv_validator_state.json"
    if ! install -m 0600 "$old_data/priv_validator_state.json" "$state_backup"; then
        echo -e "${RED}Could not back up validator state after stopping the service.${RESET}" >&2
        restore_prior_service_state "$was_active" || true
        return 1
    fi
    if ! mv "$old_data" "$rollback_data"; then
        echo -e "${RED}Could not prepare the rollback data directory.${RESET}" >&2
        restore_prior_service_state "$was_active" || true
        return 1
    fi
    if ! mv "$extracted/data" "$old_data"; then
        rollback_snapshot "$old_data" "$rollback_data" "$was_active"
        return 1
    fi
    fix_node_ownership "$old_data"
    if ! install -m 0600 "$state_backup" "$old_data/priv_validator_state.json"; then
        rollback_snapshot "$old_data" "$rollback_data" "$was_active"
        return 1
    fi
    fix_node_ownership "$old_data"
    if ! sync; then
        rollback_snapshot "$old_data" "$rollback_data" "$was_active"
        return 1
    fi

    if [ "$was_active" = yes ]; then
        if ! sudo systemctl start "$WORRELL_SERVICE_NAME"; then
            rollback_snapshot "$old_data" "$rollback_data" "$was_active" yes
            return 1
        fi
        if ! wait_for_healthy_service; then
            rollback_snapshot "$old_data" "$rollback_data" "$was_active" yes
            return 1
        fi
    fi
    if [ "$was_active" = yes ]; then
        if ! rm -rf "$rollback_data"; then
            echo -e "${YELLOW}Snapshot applied, but rollback data could not be removed: $rollback_data${RESET}" >&2
        fi
    else
        echo -e "${YELLOW}Node was inactive before the snapshot; rollback data retained at: $rollback_data${RESET}"
    fi
    echo -e "${GREEN}Snapshot applied successfully. Validator state and config were preserved.${RESET}"
    echo -e "${CYAN}Provider:${RESET} $SNAPSHOT_PROVIDER"
    echo -e "${CYAN}Snapshot height:${RESET} $SNAPSHOT_HEIGHT"
    echo -e "${CYAN}Service:${RESET} $WORRELL_SERVICE_NAME (${was_active/yes/restarted})"
    prompt_back_or_continue
)

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
