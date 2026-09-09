#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
menu="$repo/resources/valleyofWorrel.sh"
snapshot="$repo/resources/apply_snapshot.sh"

bash -n "$menu" "$snapshot"
grep -q 'local_catching_up' "$menu"
grep -q 'if .result.sync_info.catching_up == null' "$menu"
grep -q 'apply_snapshot.sh' "$menu"
grep -q 'ITRocket' "$snapshot"
grep -q 'Sychonix' "$snapshot"
grep -q 'curl -fsSIL' "$snapshot"
grep -q 'snapshot_headers_are_binary' "$snapshot"
grep -q 'APPLY-WORRELL-SNAPSHOT' "$snapshot"
grep -q 'priv_validator_state.json' "$snapshot"
grep -q 'Pending upgrade-info.json exists' "$snapshot"
grep -q 'upgrade-info.json' "$snapshot"

fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
awk '/^echo -e "\$LOGO"/{exit} {print}' "$menu" > "$fixture/functions.sh"
HOME="$fixture" WORRELL_HOME="$fixture/.worrell" bash -c '
  source "$HOME/functions.sh"
  local_status() { printf "%s\\n" '\''{"result":{"sync_info":{"catching_up":false}}}'\''; }
  test "$(local_catching_up)" = false
  local_status() { printf "%s\\n" '\''{"result":{"sync_info":{"catching_up":true}}}'\''; }
  test "$(local_catching_up)" = true
  local_status() { printf "%s\\n" '\''{"result":{"sync_info":{}}}'\''; }
  test "$(local_catching_up)" = unknown
'

# Provider metadata must resolve a safe rotating filename and reject unsafe names.
mkdir -p "$fixture/bin"
cat > "$fixture/bin/curl" <<'CURL'
#!/usr/bin/env bash
printf '%s\n' '{"snapshot_name":"worrell_2026-09-09_655111_snap.tar.lz4","snapshot_height":"655111","snapshot_size":"168M","snapshot_block_time":"2026-09-09T19:09:08+04","pruning":"custom: 100/0/19"}'
CURL
chmod +x "$fixture/bin/curl"
sed '/^main() {/,$d' "$snapshot" > "$fixture/snapshot-functions.sh"
PATH="$fixture/bin:$PATH" bash -c 'source "$1"; resolve_itrocket; test "$SNAPSHOT_URL" = "https://server-3.itrocket.net/testnet/worrell/worrell_2026-09-09_655111_snap.tar.lz4"' bash "$fixture/snapshot-functions.sh"
cat > "$fixture/bin/curl" <<'CURL'
#!/usr/bin/env bash
printf '%s\n' '{"snapshot_name":"../unsafe.tar.lz4"}'
CURL
chmod +x "$fixture/bin/curl"
if PATH="$fixture/bin:$PATH" bash -c 'source "$1"; resolve_itrocket' bash "$fixture/snapshot-functions.sh"; then
  echo 'unsafe ITRocket filename was accepted' >&2
  exit 1
fi

# Safe archive layout accepted; config/key injection and links rejected.
mkdir -p "$fixture/archive/data/application.db" "$fixture/archive/data/state.db"
printf state > "$fixture/archive/data/application.db/000001.ldb"
printf state > "$fixture/archive/data/state.db/000001.ldb"
tar -C "$fixture/archive" -cf "$fixture/safe.tar" data
lz4 -f "$fixture/safe.tar" "$fixture/safe.tar.lz4" >/dev/null
HOME="$fixture" bash -c 'source "$1"; validate_archive_layout "$2" "$3"' bash "$fixture/snapshot-functions.sh" "$fixture/safe.tar.lz4" "$fixture/listing"
mkdir -p "$fixture/unsafe/config"
tar -C "$fixture/unsafe" -cf "$fixture/unsafe.tar" config
lz4 -f "$fixture/unsafe.tar" "$fixture/unsafe.tar.lz4" >/dev/null
if HOME="$fixture" bash -c 'source "$1"; validate_archive_layout "$2" "$3"' bash "$fixture/snapshot-functions.sh" "$fixture/unsafe.tar.lz4" "$fixture/unsafe-listing"; then
  echo 'unsafe snapshot archive accepted' >&2
  exit 1
fi
mkdir -p "$fixture/link/data"
ln -s /tmp "$fixture/link/data/unsafe-link"
tar -C "$fixture/link" -cf "$fixture/link.tar" data
lz4 -f "$fixture/link.tar" "$fixture/link.tar.lz4" >/dev/null
if HOME="$fixture" bash -c 'source "$1"; validate_archive_layout "$2" "$3"' bash "$fixture/snapshot-functions.sh" "$fixture/link.tar.lz4" "$fixture/link-listing"; then
  echo 'linked snapshot archive accepted' >&2
  exit 1
fi

# Source-order assertions cover the signer-state race and post-start stabilization.
python3 - "$snapshot" <<'PYORDER'
from pathlib import Path
import sys
s = Path(sys.argv[1]).read_text()
start = s.index('apply_selected_snapshot() {')
end = s.index('choose_snapshot_type() {', start)
body = s[start:end]
assert body.index('systemctl stop "$WORRELL_SERVICE_NAME"') < body.index('install -m 0600 "$old_data/priv_validator_state.json"')
assert body.index('wait_for_healthy_service') < body.index('rm -rf "$rollback_data"')
assert 'rollback_snapshot "$old_data" "$rollback_data" "$was_active"' in body
PYORDER

echo 'Worrel status and snapshot tests: PASS'
