#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
menu="$repo/resources/valleyofWorrel.sh"
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

awk '/^echo -e "\$LOGO"/{exit} {print}' "$menu" > "$fixture/functions.sh"

python3 - "$menu" <<'PY'
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text().splitlines()
explanation = next(i for i, line in enumerate(lines) if "Optional metadata: identity, website, and security email" in line)
assert lines[explanation + 1].startswith('    read -r -p "Validator identity []: "')
assert lines[explanation + 2].startswith('    read -r -p "Validator website []: "')
assert lines[explanation + 3].startswith('    read -r -p "Validator security email []: "')
PY

HOME="$fixture" WORRELL_HOME="$fixture/.worrell" bash -c '
  source "$HOME/functions.sh"
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

  run_case() {
    local label="$1" input="$2" expected_identity="$3" expected_website="$4" expected_security="$5" json
    printf "%b" "$input" | create_validator >"$HOME/$label.out" 2>"$HOME/$label.err"
    json=$(awk "/Review validator JSON:/{found=1; next} found { print; if (\$0 == \"}\") exit }" "$HOME/$label.out")
    jq -e --arg identity "$expected_identity" --arg website "$expected_website" --arg security "$expected_security" \
      "(.identity == \$identity) and (.website == \$website) and (.security == \$security)" <<<"$json" >/dev/null
  }

  run_case blank "validator-key\n" "" "" ""
  run_case supplied "validator-key\nSupplied moniker\nvalidator-id\nhttps://example.test\nops@example.test\n20000000000000\n0.05\n0.25\n0.01\n1000000\nno\n" \
    validator-id https://example.test ops@example.test
'

echo 'Worrel validator metadata tests: PASS'
