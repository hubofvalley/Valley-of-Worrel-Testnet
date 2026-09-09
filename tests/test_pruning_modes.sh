#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
installer="$repo/resources/worrelld_node_install_testnet.sh"

bash -n "$installer"
grep -q -- '--pruning-mode' "$installer"
grep -q 'pruning-keep-recent' "$installer"
grep -q 'pruning-interval' "$installer"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.worrell/config"
cat > "$tmp/functions.sh" < <(awk '/^configure_pruning\(\)/,/^install_prebuilt\(\)/ { if ($0 !~ /^install_prebuilt\(\)/) print }' "$installer")

make_app() {
    cat > "$tmp/.worrell/config/app.toml" <<'TOML'
minimum-gas-prices = "0.025uworrell"
pruning = "default"
pruning-keep-recent = "362880"
pruning-interval = "10"
[api]
pruning = "decoy"
pruning-keep-recent = "decoy"
pruning-interval = "decoy"
TOML
}

for mode in pruned archive; do
    make_app
    HOME_DIR="$tmp/.worrell" PRUNING_MODE="$mode" bash -c 'source "$1"; configure_pruning' bash "$tmp/functions.sh"
    cp "$tmp/.worrell/config/app.toml" "$tmp/verified-$mode.toml"
done

grep -q '^pruning = "custom"$' "$tmp/verified-pruned.toml"
grep -q '^pruning-keep-recent = "100"$' "$tmp/verified-pruned.toml"
grep -q '^pruning-interval = "20"$' "$tmp/verified-pruned.toml"
grep -q '^pruning = "nothing"$' "$tmp/verified-archive.toml"
grep -q '^pruning-keep-recent = "0"$' "$tmp/verified-archive.toml"
grep -q '^pruning-interval = "0"$' "$tmp/verified-archive.toml"
grep -q '^pruning = "decoy"$' "$tmp/verified-pruned.toml"
grep -q '^pruning = "decoy"$' "$tmp/verified-archive.toml"

make_app
sed -i '/^\[api\]/i pruning = "custom"' "$tmp/.worrell/config/app.toml"
if HOME_DIR="$tmp/.worrell" PRUNING_MODE=pruned bash -c 'source "$1"; configure_pruning' bash "$tmp/functions.sh"; then
    echo 'duplicate root pruning key was accepted' >&2
    exit 1
fi

make_app
sed -i '/^pruning-interval = "10"$/d' "$tmp/.worrell/config/app.toml"
if HOME_DIR="$tmp/.worrell" PRUNING_MODE=pruned bash -c 'source "$1"; configure_pruning' bash "$tmp/functions.sh"; then
    echo 'missing root pruning key was accepted' >&2
    exit 1
fi

for args in '--pruning-mode invalid' '--pruning-mode' '--pruning-mode archive --bad'; do
    if HOME="$tmp" bash "$installer" $args >"$tmp/invalid.out" 2>&1; then
        echo "installer unexpectedly accepted: $args" >&2
        exit 1
    fi
done

echo 'Worrel pruning mode tests: PASS'
