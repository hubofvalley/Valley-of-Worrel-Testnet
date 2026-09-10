#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
menu="$repo/resources/valleyofWorrel.sh"
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

# Load menu functions without entering the interactive launcher.
awk '/^echo -e "\$LOGO"/{exit} {print}' "$menu" > "$fixture/functions.sh"

HOME="$fixture" WORRELL_HOME="$fixture/.worrell" EVENTS="$fixture/events" CALLS="$fixture/calls" bash -c '
  source "$HOME/functions.sh"
  worrell_bin() { return 0; }
  worrell() {
    printf "%s\n" "$*" >> "$CALLS"
    if [[ "$*" == *fail-key* ]]; then
      printf "KEY_CREATION_FAILED\n" >&2
      return 1
    fi
    printf "KEY_RECORD\n"
    if [[ "$*" != *--recover* ]]; then
      printf "MNEMONIC_SENTINEL\n" >&2
    fi
  }
  prompt_back() { printf "prompt_back\n" >> "$EVENTS"; }
  menu() { printf "menu\n" >> "$EVENTS"; }

  printf "2\nnew-key\n" | list_or_create_key >"$HOME/create.out" 2>"$HOME/create.err"
  grep -q "^KEY_RECORD$" "$HOME/create.out"
  grep -q "^MNEMONIC_SENTINEL$" "$HOME/create.err"
  ! grep -q "MNEMONIC_SENTINEL" "$HOME/create.out"
  test "$(cat "$CALLS")" = "keys add new-key --home $WORRELL_HOME --output text"
  grep -q "Confirm the mnemonic shown above" "$HOME/create.out"
  test "$(sed -n "1p" "$EVENTS")" = prompt_back
  test "$(sed -n "2p" "$EVENTS")" = menu

  : > "$EVENTS"
  : > "$CALLS"
  printf "3\nrecovered-key\n" | list_or_create_key >"$HOME/recover.out" 2>"$HOME/recover.err"
  grep -q "Recovery uses your existing mnemonic" "$HOME/recover.out"
  grep -q "^KEY_RECORD$" "$HOME/recover.out"
  ! grep -q "MNEMONIC_SENTINEL" "$HOME/recover.out" "$HOME/recover.err"
  test "$(cat "$CALLS")" = "keys add recovered-key --recover --home $WORRELL_HOME --output text"
  test "$(sed -n "1p" "$EVENTS")" = prompt_back
  test "$(sed -n "2p" "$EVENTS")" = menu

  : > "$EVENTS"
  : > "$CALLS"
  printf "2\nfail-key\n" | list_or_create_key >"$HOME/fail.out" 2>"$HOME/fail.err"
  grep -q "Key creation did not complete cleanly" "$HOME/fail.err"
  ! grep -q "Confirm the mnemonic shown above" "$HOME/fail.out"
  test "$(sed -n "1p" "$EVENTS")" = prompt_back
  test "$(sed -n "2p" "$EVENTS")" = menu
'

echo 'Worrel key creation output tests: PASS'
