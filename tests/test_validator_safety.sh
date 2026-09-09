#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
awk '/^echo -e "\$LOGO"/{exit} {print}' "$repo/resources/valleyofWorrel.sh" > "$fixture/functions.sh"

HOME="$fixture" bash -c '
  source "$HOME/functions.sh"
  amount=20000000000000; rate=0.05; max_rate=0.25
  min_self=1; max_change=0.01
  if validate_validator_inputs; then echo "accepted min-self=1" >&2; exit 1; fi
  min_self=1000000; max_change=0.50
  if validate_validator_inputs; then echo "accepted max-change above max-rate" >&2; exit 1; fi
  max_change=0.01
  validate_validator_inputs
'

echo 'Worrel validator safety tests: PASS'
