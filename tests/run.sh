#!/usr/bin/env bash
# Run all (or selected) tests. Each test file is a bash script returning
# exit 0 on full pass.
set -euo pipefail

HERE=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$HERE"

# Build SQLite fixtures on demand (idempotent, fast).
if [[ -x ./fixtures/build.sh ]]; then
    ./fixtures/build.sh >/dev/null
fi

declare -a TESTS
if (( $# > 0 )); then
    for arg in "$@"; do
        # Accept "test_pi" or "test_pi.sh" or full path.
        case "$arg" in
            *.sh) TESTS+=("$arg") ;;
            *)    TESTS+=("${arg}.sh") ;;
        esac
    done
else
    mapfile -t TESTS < <(ls test_*.sh 2>/dev/null)
fi

if (( ${#TESTS[@]} == 0 )); then
    printf 'No tests found.\n' >&2
    exit 1
fi

failed=0
for t in "${TESTS[@]}"; do
    printf '\n=== %s ===\n' "$t"
    if bash "$t"; then :; else failed=$(( failed + 1 )); fi
done

printf '\n'
if (( failed == 0 )); then
    printf '✓ all %d test file(s) passed\n' "${#TESTS[@]}"
    exit 0
else
    printf '✗ %d test file(s) failed\n' "$failed" >&2
    exit 1
fi
