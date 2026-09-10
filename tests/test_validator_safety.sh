#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
awk '/^echo -e "\$LOGO"/{exit} {print}' "$repo/resources/valleyofWorrel.sh" > "$fixture/functions.sh"

HOME="$fixture" bash -c '
  source "$HOME/functions.sh"
  amount=20000000; rate=0.05; max_rate=0.25
  min_self=1; max_change=0.01
  if validate_validator_inputs; then echo "accepted min-self=1" >&2; exit 1; fi
  min_self=1000000; max_change=0.50
  if validate_validator_inputs; then echo "accepted max-change above max-rate" >&2; exit 1; fi
  max_change=0.01
  validate_validator_inputs

  local_catching_up() { printf "%s\n" false; }
  get_local_rpc_port() { printf "%s\n" 26657; }
  menu() { :; }
  worrell() {
    case "$1 $2" in
      "keys show") printf "%s\n" worrell1testaddress ;;
      "query bank") printf "%s\n" "{}" ;;
      "tendermint show-validator") printf "%s\n" "{\"@type\":\"/cosmos.crypto.ed25519.PubKey\",\"key\":\"AA==\"}" ;;
      *) return 0 ;;
    esac
  }
  printf "%b" "validator-key\nSafety validator\nvalidator-id\nhttps://example.test\nops@example.test\nEntered validator details\n20000000\n0.05\n0.25\n0.01\n1000000\nno\n" \
    | create_validator >"$HOME/create-validator.out" 2>"$HOME/create-validator.err"
  json=$(awk "/Review validator JSON:/{found=1; next} found { print; if (\$0 == \"}\") exit }" "$HOME/create-validator.out")
  jq -e "(.details == \"Entered validator details\") and (.amount == \"20000000uworrell\")" <<<"$json" >/dev/null
'

echo 'Worrel validator safety tests: PASS'
