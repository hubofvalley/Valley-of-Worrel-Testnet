#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
menu="$repo/resources/valleyofWorrel.sh"

bash -n "$menu"
grep -q '^prompt_back() { read -r -p "Press Enter to go back to main menu\.\.\."' "$menu"
grep -q '^    clear$' "$menu"
grep -q 'Installation flow finished\. Review the output above before returning to the main menu\.' "$menu"
grep -q 'Log follow ended\. Review the output above before returning to the main menu\.' "$menu"
grep -q 'Validator transaction cancelled\. No transaction was submitted\.' "$menu"
grep -q 'Unjail transaction cancelled\. No transaction was submitted\.' "$menu"
grep -q 'Delegation transaction submitted successfully\.' "$menu"
grep -q 'prompt_back$' "$menu"

# These completion paths must pause before the menu redraw clears the terminal.
for pattern in \
    'run_pinned_child apply_snapshot.sh.*' \
    'sudo systemctl restart' \
    'sudo systemctl stop' \
    'Node removed\. Key backup:'; do
    grep -q "$pattern" "$menu"
done

# The old immediate log-follow return must not regress.
! grep -q 'show_logs() { sudo journalctl.*; menu; }' "$menu"

echo 'Worrel UX pause tests: PASS'
