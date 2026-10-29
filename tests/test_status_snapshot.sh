#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
snapshot="$repo/resources/apply_snapshot.sh"

bash -n "$snapshot"
output=$(bash "$snapshot" 2>&1 || true)
grep -q 'Snapshot application is disabled' <<<"$output"
! grep -Eq 'ITRocket|Sychonix|server-3\.itrocket|snapshot\.sychonix' "$snapshot"
if bash "$snapshot" >/dev/null 2>&1; then
    echo 'disabled snapshot helper unexpectedly succeeded' >&2
    exit 1
fi

echo 'Worrell snapshot-disabled tests: PASS'
