#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
menu="$repo/resources/valleyofWorrel.sh"
installer="$repo/resources/worrelld_node_install_testnet.sh"
migration="$repo/resources/cosmovisor_migration.sh"
upgrade="$repo/resources/worrelld_cosmovisor_upgrade.sh"

bash -n "$menu" "$installer" "$migration" "$upgrade"
grep -q 'releases/download/cosmovisor' "$installer"
grep -q 'SHA256SUMS-cosmovisor' "$installer"
grep -q '3df6ef38cf976b00d226f391dc6866b8dc4040fc2f1b4a780d248f6e1cc9332e' "$installer"
grep -q 'SERVICE_EXEC_START="\$COSMOVISOR_BIN run start --home \$HOME_DIR"' "$installer"
grep -q 'SERVICE_EXEC_START="\$BINARY_DIR/worrelld start --home \$HOME_DIR"' "$installer"
! grep -q 'ExecStart=.*run start.*--chain-id' "$installer"
! grep -q 'ExecStart=.*run start.*--chain-id' "$migration"
grep -q 'SERVICE_MODE=direct' "$installer"
grep -q -- '--service-mode' "$installer"
grep -q 'DAEMON_ALLOW_DOWNLOAD_BINARIES=false' "$installer"
grep -q 'WORRELL_UNSAFE_SKIP_BACKUP="${WORRELL_UNSAFE_SKIP_BACKUP:-true}"' "$installer"
grep -q 'UNSAFE_SKIP_BACKUP=$WORRELL_UNSAFE_SKIP_BACKUP' "$installer"
grep -q 'WORRELL_UNSAFE_SKIP_BACKUP="${WORRELL_UNSAFE_SKIP_BACKUP:-true}"' "$migration"
grep -q 'UNSAFE_SKIP_BACKUP=$WORRELL_UNSAFE_SKIP_BACKUP' "$migration"
grep -q 'WORRELL_UNSAFE_SKIP_BACKUP="${WORRELL_UNSAFE_SKIP_BACKUP:-true}"' "$upgrade"
grep -q 'UNSAFE_SKIP_BACKUP="$WORRELL_UNSAFE_SKIP_BACKUP"' "$upgrade"
grep -q 'data/upgrade-info.json' "$repo/docs/cosmovisor.md"
grep -q 'rejects `--chain-id` on `start`' "$repo/docs/cosmovisor.md"
! grep -q 'cosmovisor run start.*--chain-id' "$repo/docs/cosmovisor.md"
grep -q 'cosmovisor_migration.sh' "$menu"
grep -q 'worrelld_cosmovisor_upgrade.sh' "$menu"
grep -q 'VALLEY_COSMOVISOR_MIGRATION_SHA256' "$menu"
grep -q 'WORRELL_UPGRADE_V0_1_3="v0.1.3"' "$menu"
grep -q 'WORRELL_UPGRADE_PLAN_V0_1_3="v0.1.3"' "$menu"
grep -q 'WORRELL_UPGRADE_HEIGHT_V0_1_3="1186000"' "$menu"
grep -q 'stage_cosmovisor_upgrade' "$menu"
grep -q 'no local --upgrade-height is passed' "$menu"
grep -q 'VALLEY_COSMOVISOR_UPGRADE_SHA256' "$menu"
grep -q '"cosmovisor"' "$repo/VALLEY.json"
jq -e '.upgrade_options[] | select(.tag == "v0.1.3" and .governance_plan_name == "v0.1.3" and .governance_upgrade_height == "1186000")' "$repo/VERSIONS.json" >/dev/null
grep -q 'b6e8687d1af51f8dea81c1ba6ecd93b358ce6bb80468159c1c7f70d4b908a6ec' "$repo/VERSIONS.json"
grep -q '11c2e324b03693380515e97b8090a86f132bc4ea467d80d0e8d05709d15ee5d0' "$repo/VERSIONS.json"

# The predefined governance option must pass the plan name and an empty
# emergency height to the staging helper.
stage_fixture=$(mktemp)
trap 'rm -f "$stage_fixture"' EXIT
{
    printf '%s\n' 'RED= GREEN= ORANGE= YELLOW= RESET='
    printf '%s\n' 'WORRELL_UPGRADE_V0_1_3=v0.1.3'
    printf '%s\n' 'WORRELL_UPGRADE_PLAN_V0_1_3=v0.1.3'
    printf '%s\n' 'WORRELL_UPGRADE_HEIGHT_V0_1_3=1186000'
    printf '%s\n' 'VALLEY_COSMOVISOR_UPGRADE_SHA256=fixture'
    printf '%s\n' 'menu() { :; }' 'prompt_back() { :; }'
    printf '%s\n' 'run_pinned_child() { printf "CAPTURE=%s|%s|%s|%s|%s\\n" "$@"; }'
    sed -n '/^stage_cosmovisor_upgrade()/,/^}/p' "$menu"
    printf '%s\n' 'printf "1\\nyes\\n" | stage_cosmovisor_upgrade'
} > "$stage_fixture"
stage_output=$(bash "$stage_fixture")
grep -q 'CAPTURE=worrelld_cosmovisor_upgrade.sh|fixture|v0.1.3|v0.1.3|' <<< "$stage_output"

rm -f "$stage_fixture"
trap - EXIT
echo 'Worrell Cosmovisor tests: PASS'


# Compact Valley routing must accept 1g, and post-upgrade CLI calls must
# resolve through Cosmovisor's current binary rather than the stale direct one.
grep -q '^[[:space:]]*if \[\[ "\$option" =~ \^\[1-3\]\[a-z\]\$' "$menu"
grep -q 'WORRELL_HOME/cosmovisor/current/bin/worrelld' "$menu"

fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/.worrell/cosmovisor/current/bin"
touch "$fixture/.worrell/cosmovisor/current/bin/worrelld"
chmod +x "$fixture/.worrell/cosmovisor/current/bin/worrelld"
cat > "$fixture/effective" <<'EOF'
/home/test/go/bin/cosmovisor run start
EOF
awk '/^echo -e "\$LOGO"/{exit} {print}' "$menu" > "$fixture/functions.sh"
HOME="$fixture" WORRELL_HOME="$fixture/.worrell" WORRELL_SERVICE_NAME=worrelld bash -c '
  sudo() { if [ "$1" = systemctl ] && [ "$2" = show ]; then cat "$HOME/effective"; else return 1; fi; }
  source "$HOME/functions.sh"
  test "$(runtime_mode)" = cosmovisor
  test "$(worrell_bin)" = "$HOME/.worrell/cosmovisor/current/bin/worrelld"
  printf "/home/test/go/bin/worrelld start --home /tmp\n" > "$HOME/effective"
  test "$(runtime_mode)" = direct
  printf "ambiguous\n" > "$HOME/effective"
  test "$(runtime_mode)" = unknown
'

# SDK-valid plan names may contain spaces; emergency staging must fail closed on conflicts.
helper_functions=$(mktemp)
trap 'rm -rf "$fixture" "$helper_functions"' EXIT
sed -n '/^valid_upgrade_name()/,/^}/p; /^valid_upgrade_height()/,/^}/p; /^preflight_emergency_upgrade()/,/^}/p' "$upgrade" > "$helper_functions"
source "$helper_functions"
valid_upgrade_name 'Worrell Upgrade 1'
! valid_upgrade_name ''
valid_upgrade_height 123
! valid_upgrade_height 0
mkdir -p "$fixture/home/cosmovisor/upgrades" "$fixture/home/data"
preflight_emergency_upgrade "$fixture/home" 'Worrell Upgrade 1'
mkdir -p "$fixture/home/cosmovisor/upgrades/worrell%20upgrade%201"
! preflight_emergency_upgrade "$fixture/home" 'Worrell Upgrade 1'
rm -rf "$fixture/home/cosmovisor/upgrades/worrell%20upgrade%201"
touch "$fixture/home/data/upgrade-info.json"
! preflight_emergency_upgrade "$fixture/home" 'Worrell Upgrade 1'

echo 'Worrell Cosmovisor routing tests: PASS'

# A failure inside install_cosmovisor after stopping an active node must restore
# the unit, profile, and both active/enabled states.
rollback_fixture=$(mktemp -d)
rollback_bin="$rollback_fixture/bin"
mkdir -p "$rollback_bin" "$rollback_fixture/home/go/bin" "$rollback_fixture/home/.worrell/config" "$rollback_fixture/systemd"
touch "$rollback_fixture/home/go/bin/worrelld"
chmod +x "$rollback_fixture/home/go/bin/worrelld"
printf 'original profile\n' > "$rollback_fixture/home/.bash_profile"
printf 'ExecStart=/home/test/go/bin/worrelld start\n' > "$rollback_fixture/systemd/worrelld.service"
printf 'active=1\nenabled=1\n' > "$rollback_fixture/state"
cat > "$rollback_bin/sudo" <<'EOS'
#!/usr/bin/env bash
exec "$@"
EOS
cat > "$rollback_bin/systemctl" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
state="$FAKE_SYSTEMD_STATE"
case "$1" in
  is-active) grep -q '^active=1$' "$state" ;;
  is-enabled) grep -q '^enabled=1$' "$state" ;;
  stop) sed -i 's/^active=1$/active=0/' "$state" ;;
  start) sed -i 's/^active=0$/active=1/' "$state" ;;
  enable) sed -i 's/^enabled=0$/enabled=1/' "$state" ;;
  disable) sed -i 's/^enabled=1$/enabled=0/' "$state" ;;
  daemon-reload) ;;
  *) exit 1 ;;
esac
EOS
cat > "$rollback_bin/curl" <<'EOS'
#!/usr/bin/env bash
exit 1
EOS
chmod +x "$rollback_bin"/*
set +e
HOME="$rollback_fixture/home" PATH="$rollback_bin:$PATH" WORRELL_HOME="$rollback_fixture/home/.worrell" WORRELL_SERVICE_NAME=worrelld WORRELL_SYSTEMD_UNIT_DIR="$rollback_fixture/systemd" FAKE_SYSTEMD_STATE="$rollback_fixture/state" bash "$migration" >/tmp/worrel-migration-failure.out 2>&1
migration_rc=$?
set -e
test "$migration_rc" -ne 0
grep -q 'ExecStart=/home/test/go/bin/worrelld start' "$rollback_fixture/systemd/worrelld.service"
grep -q '^original profile$' "$rollback_fixture/home/.bash_profile"
grep -q '^active=1$' "$rollback_fixture/state"
grep -q '^enabled=1$' "$rollback_fixture/state"
rm -rf "$rollback_fixture" /tmp/worrel-migration-failure.out

echo 'Worrell Cosmovisor rollback tests: PASS'
