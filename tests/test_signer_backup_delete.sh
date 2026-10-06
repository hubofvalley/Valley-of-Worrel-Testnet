#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/home"
awk '/^echo -e "\$LOGO"/{exit} {print}' "$repo/resources/valleyofWorrel.sh" > "$fixture/functions.sh"

HOME="$fixture/home"
export HOME
source "$fixture/functions.sh"
TAR_BIN=$(command -v tar)
grep -q 'Point-in-time signer/state archive created' "$repo/resources/valleyofWorrel.sh"
grep -q 'Do not restore priv_validator_state.json after this node signs again' "$repo/resources/valleyofWorrel.sh"
grep -q 'not an authoritative recovery snapshot' "$repo/docs/usage.md"

make_node() {
    rm -rf -- "$WORRELL_HOME"
    mkdir -p "$WORRELL_HOME/config" "$WORRELL_HOME/data"
    printf '%s\n' '{"priv_key":"fixture-signing-key"}' > "$WORRELL_HOME/config/priv_validator_key.json"
    printf '%s\n' '{"height":"42","round":0,"step":2}' > "$WORRELL_HOME/data/priv_validator_state.json"
    printf '%s\n' '{"node_id":"fixture-node"}' > "$WORRELL_HOME/config/node_key.json"
}

make_node
[ "$(managed_worrell_home_for_mode no)" = "$HOME/.worrell" ]
WORRELL_SERVICE_USER=worrell
export WORRELL_SERVICE_USER
[ "$(managed_worrell_home_for_mode yes)" = /var/lib/worrell ]
WORRELL_SERVICE_USER='bad/name'
! managed_worrell_home_for_mode yes
WORRELL_SERVICE_USER=$(id -un)
export WORRELL_SERVICE_USER
validate_managed_worrell_home

# Exact path and symlink checks must reject alternate homes.
old_home="$WORRELL_HOME"
WORRELL_HOME="$HOME/other-node"
! validate_managed_worrell_home
WORRELL_HOME="$old_home"
mv "$WORRELL_HOME" "$fixture/real-node"
ln -s "$fixture/real-node" "$WORRELL_HOME"
! validate_managed_worrell_home
rm "$WORRELL_HOME"
mv "$fixture/real-node" "$WORRELL_HOME"

# A successful backup contains signer key, signer state, optional node key,
# manifest checksums, and private archive/member modes.
create_signer_backup
archive="$WORRELL_LAST_BACKUP"
[ -f "$archive" ]
[ "$(stat -c '%a' "$archive")" = 600 ]
listing=$("$TAR_BIN" -tzf "$archive")
grep -Fqx 'config/priv_validator_key.json' <<< "$listing"
grep -Fqx 'data/priv_validator_state.json' <<< "$listing"
grep -Fqx 'config/node_key.json' <<< "$listing"
grep -Fqx 'manifest.txt' <<< "$listing"
unpacked=$(mktemp -d)
"$TAR_BIN" -xzf "$archive" -C "$unpacked"
[ "$(stat -c '%a' "$unpacked/config/priv_validator_key.json")" = 600 ]
[ "$(stat -c '%a' "$unpacked/data/priv_validator_state.json")" = 600 ]
[ "$(stat -c '%a' "$unpacked/config/node_key.json")" = 600 ]
jq -e . "$unpacked/config/priv_validator_key.json" >/dev/null
jq -e . "$unpacked/data/priv_validator_state.json" >/dev/null
jq -e . "$unpacked/config/node_key.json" >/dev/null
grep -q '^format=worrell-signer-backup-v1$' "$unpacked/manifest.txt"
grep -q 'file=data/priv_validator_state.json size=' "$unpacked/manifest.txt"
rm -rf "$unpacked"

# A readable archive with the expected filenames but a mismatching manifest
# must not pass the integrity gate.
tampered_dir=$(mktemp -d)
mkdir -p "$tampered_dir/config" "$tampered_dir/data"
cp "$WORRELL_HOME/config/priv_validator_key.json" "$tampered_dir/config/priv_validator_key.json"
cp "$WORRELL_HOME/data/priv_validator_state.json" "$tampered_dir/data/priv_validator_state.json"
printf 'format=worrell-signer-backup-v1\ncreated_utc=test\nfile=config/priv_validator_key.json size=%s sha256=%064d\nfile=data/priv_validator_state.json size=%s sha256=%064d\nfile=config/node_key.json size=%s sha256=%064d\n' \
    "$(stat -c '%s' "$tampered_dir/config/priv_validator_key.json")" 0 \
    "$(stat -c '%s' "$tampered_dir/data/priv_validator_state.json")" 0 \
    "$(stat -c '%s' "$WORRELL_HOME/config/node_key.json")" 0 > "$tampered_dir/manifest.txt"
tampered_archive="$HOME/tampered.tar.gz"
"$TAR_BIN" -czf "$tampered_archive" -C "$tampered_dir" config data manifest.txt
! verify_signer_backup_archive "$tampered_archive" config/priv_validator_key.json data/priv_validator_state.json config/node_key.json
rm -rf "$tampered_dir" "$tampered_archive"

# Required signer state, source copies, and archive creation all fail closed.
rm -f "$WORRELL_HOME/data/priv_validator_state.json"
WORRELL_LAST_BACKUP=''
! create_signer_backup
[ -z "$WORRELL_LAST_BACKUP" ]
make_node
printf '%s\n' '{invalid-json' > "$WORRELL_HOME/data/priv_validator_state.json"
WORRELL_LAST_BACKUP=''
! create_signer_backup
[ -z "$WORRELL_LAST_BACKUP" ]
make_node
install() { return 1; }
WORRELL_LAST_BACKUP=''
! create_signer_backup
[ -z "$WORRELL_LAST_BACKUP" ]
unset -f install
make_node
tar() {
    if [ "${1:-}" = -czf ]; then return 1; fi
    "$TAR_BIN" "$@"
}
WORRELL_LAST_BACKUP=''
! create_signer_backup
[ -z "$WORRELL_LAST_BACKUP" ]
unset -f tar

prompt_back() { :; }
menu() { :; }

# Stop failure and an active service after stop must preserve the home.
make_node
sudo() {
    if [ "$1 $2" = 'systemctl stop' ]; then return 1; fi
    return 1
}
delete_node <<< 'DELETE' >/dev/null 2>"$fixture/stop-failure.err"
[ -d "$WORRELL_HOME" ]
make_node
sudo() {
    if [ "$1 $2" = 'systemctl stop' ]; then return 0; fi
    if [ "$1 $2" = 'systemctl is-active' ]; then printf '%s\n' active; return 0; fi
    return 0
}
delete_node <<< 'DELETE' >/dev/null 2>"$fixture/active-after-stop.err"
[ -d "$WORRELL_HOME" ]

# Backup/tar failure during delete must preserve the home.
make_node
tar() {
    if [ "${1:-}" = -czf ]; then return 1; fi
    command tar "$@"
}
delete_node <<< 'DELETE' >/dev/null 2>"$fixture/delete-tar-failure.err"
[ -d "$WORRELL_HOME" ]
unset -f tar

# Successful deletion still requires an inactive service and leaves the
# private signer backup behind.
make_node
sudo() {
    if [ "$1 $2" = 'systemctl is-active' ]; then printf '%s\n' inactive; return 0; fi
    if [ "$1 $2" = 'systemctl stop' ]; then return 0; fi
    if [ "$1 $2" = 'systemctl disable' ]; then return 0; fi
    if [ "$1 $2" = 'systemctl daemon-reload' ]; then return 0; fi
    if [ "$1" = rm ]; then return 0; fi
    return 0
}
delete_node <<< 'DELETE' >/dev/null
[ ! -e "$WORRELL_HOME" ]
[ -f "$WORRELL_LAST_BACKUP" ]
[ "$(stat -c '%a' "$WORRELL_LAST_BACKUP")" = 600 ]

echo 'Worrell signer backup/delete tests: PASS'
