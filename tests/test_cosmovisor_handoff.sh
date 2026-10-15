#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
menu="$repo/resources/valleyofWorrel.sh"
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
home="$fixture/home"
fake="$fixture/bin"
mkdir -p "$home/cosmovisor/genesis/bin" "$home/cosmovisor/upgrades/v0.1.3/bin" "$home/data" "$fake"

write_fake_app() {
    local path="$1" version="$2"
    cat > "$path" <<EOF
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
    version) printf 'name=worrelld version=$version\n' ;;
    start) printf 'fake worrelld start using $version\n' ;;
    *) printf 'fake worrelld ($version)\n' ;;
esac
EOF
    chmod +x "$path"
}

write_fake_app "$home/cosmovisor/genesis/bin/worrelld" v0.1.2
write_fake_app "$home/cosmovisor/upgrades/v0.1.3/bin/worrelld" v0.1.3
ln -s genesis "$home/cosmovisor/current"
printf '%s\n' active > "$fake/service-state"
printf '%s\n' 0 > "$fake/restarts"
printf '%s\n' 0 > "$fake/show-calls"
cat > "$fake/systemctl" <<'EOF_SYSTEMCTL'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
    is-active) cat "${FAKE_SERVICE_STATE}" ;;
    show)
        calls=$(cat "${FAKE_SHOW_CALLS}")
        printf '%s\n' "$((calls + 1))" > "${FAKE_SHOW_CALLS}"
        if [ "$calls" -ge 1 ] && [ -n "${FAKE_RESTARTS_SECOND:-}" ]; then
            printf '%s\n' "${FAKE_RESTARTS_SECOND}"
        else
            cat "${FAKE_RESTARTS}"
        fi
        ;;
    *) exit 1 ;;
esac
EOF_SYSTEMCTL
chmod +x "$fake/systemctl"

# Load only the menu's definitions. This avoids starting the interactive menu or
# touching a real node while exercising the same verifier used by operators.
awk '/^echo -e "\$LOGO"/{exit} {print}' "$menu" > "$fixture/functions.sh"
run_verify() {
    local phase="$1" version="$2" name="$3" height="$4"
    HOME="$fixture" WORRELL_HOME="$home" WORRELL_SERVICE_NAME=worrelld \
        WORRELL_COSMOVISOR_STABILITY_SECONDS=0 FAKE_SERVICE_STATE="$fake/service-state" \
        FAKE_RESTARTS="$fake/restarts" FAKE_SHOW_CALLS="$fake/show-calls" PATH="$fake:$PATH" bash -c '
            sudo() { "$@"; }
            source "$HOME/functions.sh"
            verify_cosmovisor_handoff "$1" "$2" "$3" "$4"
        ' -- "$phase" "$version" "$name" "$height"
}

# Staging preflight checks the exact upgrade binary while confirming that
# staging has not activated it.
run_verify preflight v0.1.3 v0.1.3 1186000 >/dev/null

printf '%s\n' '{"name":"v0.1.3","height":"1186000"}' > "$home/data/upgrade-info.json"
info_hash_before=$(sha256sum "$home/data/upgrade-info.json" | awk '{print $1}')
if run_verify post-upgrade v0.1.3 v0.1.3 1186000 >"$fixture/stale.out" 2>&1; then
    echo 'stale current unexpectedly passed post-upgrade verification' >&2
    exit 1
fi
grep -q 'Stale Cosmovisor current' "$fixture/stale.out"
[ "$info_hash_before" = "$(sha256sum "$home/data/upgrade-info.json" | awk '{print $1}')" ]

# Prefer a real Cosmovisor binary when the runner already has one. The fake
# driver is deterministic and keeps CI dependency-free when it is unavailable.
if command -v cosmovisor >/dev/null 2>&1; then
    DAEMON_NAME=worrelld DAEMON_HOME="$home" DAEMON_ALLOW_DOWNLOAD_BINARIES=false \
        DAEMON_RESTART_AFTER_UPGRADE=false DAEMON_DATA_BACKUP_DIR="$home/cosmovisor/backup" \
        UNSAFE_SKIP_BACKUP=true timeout 10 cosmovisor run start --home "$home" >"$fixture/cosmovisor.out" 2>&1
else
    echo 'Cosmovisor binary unavailable; portable handoff shim used; live-binary verification remains outstanding.' >&2
    cat > "$fake/cosmovisor" <<'EOF_COSMOVISOR'
#!/usr/bin/env bash
set -euo pipefail
[ "${1:-}" = run ]
home="${DAEMON_HOME:?}"
name=$(jq -er '.name | strings' "$home/data/upgrade-info.json")
encoded=$(python3 - "$name" <<'PY_ENCODE'
import sys
from urllib.parse import quote
print(quote(sys.argv[1].lower(), safe="-_.~"))
PY_ENCODE
)
ln -sfn "upgrades/$encoded" "$home/cosmovisor/current"
shift 2
exec "$home/cosmovisor/current/bin/worrelld" "$@"
EOF_COSMOVISOR
    chmod +x "$fake/cosmovisor"
    DAEMON_HOME="$home" "$fake/cosmovisor" run start --home "$home" >"$fixture/cosmovisor.out"
fi

test "$(readlink -f "$home/cosmovisor/current")" = "$(readlink -f "$home/cosmovisor/upgrades/v0.1.3")"
run_verify post-upgrade v0.1.3 v0.1.3 1186000 >/dev/null
[ "$info_hash_before" = "$(sha256sum "$home/data/upgrade-info.json" | awk '{print $1}')" ]

# A historical systemd restart count is allowed when stable, but an
# increase during the observation window is a failure.
printf '%s\n' 123 > "$fake/restarts"
printf '%s\n' 0 > "$fake/show-calls"
run_verify post-upgrade v0.1.3 v0.1.3 1186000 >/dev/null
printf '%s\n' 0 > "$fake/show-calls"
if FAKE_RESTARTS_SECOND=124 run_verify post-upgrade v0.1.3 v0.1.3 1186000 >"$fixture/restart-loop.out" 2>&1; then
    echo 'restart loop unexpectedly passed post-upgrade verification' >&2
    exit 1
fi
grep -q 'restart-loop guard triggered' "$fixture/restart-loop.out"

printf 'Worrell Cosmovisor handoff integration tests: PASS\n'
