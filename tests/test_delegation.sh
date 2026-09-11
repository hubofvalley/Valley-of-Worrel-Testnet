#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
menu="$repo/resources/valleyofWorrel.sh"
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

awk '/^echo -e "\$LOGO"/{exit} {print}' "$menu" > "$fixture/functions.sh"

HOME="$fixture" WORRELL_HOME="$fixture/.worrell" CALLS="$fixture/calls" bash -c '
  source "$HOME/functions.sh"
  : > "$CALLS"
  local_status() {
    printf "%s\n" '\''{"result":{"node_info":{"network":"worrell-testnet-1"},"sync_info":{"catching_up":false}}}'\''
  }
  get_local_rpc_port() { printf "%s\n" 26657; }
  EVENTS="$HOME/events"
  : > "$EVENTS"
  prompt_back() { printf '%s\n' prompt_back >> "$EVENTS"; }
  menu() { printf '%s\n' menu >> "$EVENTS"; }

  account=worrell1testaddress
  validator=worrellvaloper1testvalidator
  worrell() {
    printf "%s\n" "$*" >> "$CALLS"
    case "$1 $2" in
      "keys show") printf "%s\n" "$account" ;;
      "query bank") printf "%s\n" '\''{"balances":[{"denom":"uworrell","amount":"5000000"}]}'\'' ;;
      "query staking") printf '\''{"operator_address":"%s","description":{"moniker":"test"}}\n'\'' "$validator" ;;
      "tx staking") printf "%s\n" '\''{"code":0}'\'' ;;
      *) return 1 ;;
    esac
  }

  valid_uworrell_amount 1uworrell
  valid_uworrell_amount 0001uworrell
  ! valid_uworrell_amount 0uworrell
  ! valid_uworrell_amount 1000000
  ! valid_uworrell_amount 1.5uworrell
  ! valid_uworrell_amount 1uworrelluworrell
  valid_worrell_valoper_address "$validator"
  ! valid_worrell_valoper_address cosmosvaloper1testvalidator
  resolve_worrell_key_address key-name | grep -qx "$account"

  # The cancellation path is fully mocked and must never call tx staking delegate.
  printf "key-name\n%s\n1000000uworrell\nno\n" "$validator" | delegate_to_validator > "$HOME/cancel.out"
  grep -q "Current balance preview" "$HOME/cancel.out"
  grep -q "Validator preview" "$HOME/cancel.out"
  ! grep -q "^tx staking delegate" "$CALLS"
  test "$(sed -n '1p' "$EVENTS")" = prompt_back
  test "$(sed -n '2p' "$EVENTS")" = menu

  : > "$CALLS"
  : > "$EVENTS"
  printf "key-name\n%s\n1000000uworrell\nyes\n" "$validator" | delegate_to_validator > "$HOME/submit.out"
  grep -q "^tx staking delegate $validator 1000000uworrell" "$CALLS"
  grep -q -- "--node tcp://127.0.0.1:26657" "$CALLS"

  # A failed local RPC gate must stop before key, balance, validator, or tx calls.
  : > "$CALLS"
  local_status() {
    printf "%s\n" '\''{"result":{"node_info":{"network":"worrell-testnet-1"},"sync_info":{"catching_up":true}}}'\''
  }
  printf "key-name\n%s\n1000000uworrell\nyes\n" "$validator" | delegate_to_validator > "$HOME/unsynced.out"
  grep -q "not confirmed synced" "$HOME/unsynced.out"
  ! grep -q "keys show\|query bank\|query staking\|tx staking" "$CALLS"

  # A missing chain identity must fail closed even when catching_up is false.
  local_status() {
    printf "%s\n" '\''{"result":{"sync_info":{"catching_up":false}}}'\''
  }
  : > "$CALLS"
  printf "key-name\n%s\n1000000uworrell\nyes\n" "$validator" | delegate_to_validator > "$HOME/missing-network.out"
  grep -q "not confirmed synced" "$HOME/missing-network.out"
  ! grep -q "keys show\|query bank\|query staking\|tx staking" "$CALLS"

  # A key lookup failure must also stop before any preview or transaction.
  local_status() {
    printf "%s\n" '\''{"result":{"node_info":{"network":"worrell-testnet-1"},"sync_info":{"catching_up":false}}}'\''
  }
  worrell() {
    printf "%s\n" "$*" >> "$CALLS"
    case "$1 $2" in
      "keys show") return 1 ;;
      *) return 1 ;;
    esac
  }
  : > "$CALLS"
  printf "missing-key\n%s\n1000000uworrell\nyes\n" "$validator" | delegate_to_validator > "$HOME/missing-key.out"
  grep -q "not found" "$HOME/missing-key.out"
  ! grep -q "query bank\|query staking\|tx staking" "$CALLS"
'

echo 'Worrell delegation safety tests: PASS'
