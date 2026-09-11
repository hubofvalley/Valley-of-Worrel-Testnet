#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

awk '/^save_env\(\)/,/^}/ { print }' \
    "$repo/resources/worrelld_node_install_testnet.sh" > "$fixture/save_env.sh"
mkdir -p "$fixture/home/go/bin"
cat > "$fixture/home/go/bin/worrelld" <<'EOF'
#!/usr/bin/env bash
printf 'fixture worrelld\n'
EOF
chmod +x "$fixture/home/go/bin/worrelld"

cat > "$fixture/home/.bash_profile" <<EOF
# preserve this unrelated profile content
export PATH="/opt/custom/bin:\$PATH"
export PATH="\$HOME/go/bin:\$PATH"
export PATH="$fixture/home/go/bin:\$PATH"
EOF

HOME="$fixture/home" SAVE_ENV="$fixture/save_env.sh" bash -c '
  set -euo pipefail
  source "$SAVE_ENV"
  BINARY_DIR="$HOME/go/bin"
  CHAIN_ID=worrell-testnet-1
  HOME_DIR="$HOME/.worrell"
  WORRELL_SERVICE_NAME=worrelld
  PORT_PREFIX=26
  MONIKER=Worrell-Test
  WORRELL_VERSION=v0.1.2
  save_env
  save_env
  canonical_line='export PATH="$HOME/go/bin:$PATH"'
  old_absolute_line="export PATH=\"$HOME/go/bin:\$PATH\""
  test "$(grep -Fxc "$canonical_line" "$HOME/.bash_profile")" -eq 1
  ! grep -Fqx "$old_absolute_line" "$HOME/.bash_profile"
  grep -Fqx '\''# preserve this unrelated profile content'\'' "$HOME/.bash_profile"
  grep -Fqx '\''export PATH="/opt/custom/bin:$PATH"'\'' "$HOME/.bash_profile"
  source "$HOME/.bash_profile"
  test "$(command -v worrelld)" = "$HOME/go/bin/worrelld"
'

echo 'Worrell profile PATH tests: PASS'
