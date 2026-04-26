#!/usr/bin/env bash
# Adapter pi: contract tests against tests/fixtures/pi/ (read-only) and a
# tmp-copied fixture set for the destructive delete test.
set -euo pipefail

HERE=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -P "$HERE/.." && pwd)

# shellcheck source=lib/assert.sh
source "$HERE/lib/assert.sh"
# shellcheck source=../lib/version.sh
source "$ROOT/lib/version.sh"
# shellcheck source=../lib/ui.sh
NO_COLOR=1 source "$ROOT/lib/ui.sh"
# shellcheck source=../lib/core.sh
source "$ROOT/lib/core.sh"

# Point the adapter at the read-only fixture dir.
export PRUNE_PI_SESSIONS_DIR="$HERE/fixtures/pi"
# shellcheck source=../adapters/pi.sh
source "$ROOT/adapters/pi.sh"

# ---- doctor ---------------------------------------------------------------
_test_begin "pi doctor passes when fixtures dir exists"
assert_exit 0 prune_pi_doctor

_test_begin "pi doctor fails on missing dir"
RC=0
PRUNE_PI_SESSIONS_DIR=/nope/no/dir prune_pi_doctor >/dev/null 2>&1 || RC=$?
assert_eq "1" "$RC"

# ---- inventory ------------------------------------------------------------
INV=$(prune_pi_inventory)

_test_begin "inventory: 4 fixture rows (flat + nested layouts)"
GOT=$(printf '%s\n' "$INV" | wc -l | tr -d ' ')
assert_eq "4" "$GOT"

_test_begin "inventory: nested-layout session is found"
GOT=$(printf '%s\n' "$INV" | awk -F'\t' '$3=="/home/nested/project"' | wc -l | tr -d ' ')
assert_eq "1" "$GOT"

_test_begin "inventory: row has 6 tab-separated fields"
ROW=$(printf '%s\n' "$INV" | head -1)
GOT=$(awk -F'\t' '{print NF}' <<<"$ROW")
assert_eq "6" "$GOT"

_test_begin "inventory: column 3 (directory) reflects cwd"
GOT=$(printf '%s\n' "$INV" | awk -F'\t' '{print $3}' | sort -u | wc -l | tr -d ' ')
assert_eq "3" "$GOT"

_test_begin "inventory: column 5 (msg count) is numeric"
GOT=$(printf '%s\n' "$INV" | awk -F'\t' '{print $5}' | grep -cE '^[0-9]+$')
assert_eq "4" "$GOT"

# ---- preview --------------------------------------------------------------
SID1=$(printf '%s\n' "$INV" | head -1 | awk -F'\t' '{print $1}')
_test_begin "preview shows first user message"
GOT=$(prune_pi_preview "$SID1")
assert_contains "$GOT" "first user message"

_test_begin "preview is robust to bogus id"
assert_exit 0 prune_pi_preview "ZZZZZZZZ"

# ---- here filter (via core) -----------------------------------------------
_test_begin "filter here /tmp/prune-test -> 2 ids"
GOT=$(printf '%s\n' "$INV" | _prune_filter_inventory here "/tmp/prune-test" | wc -l | tr -d ' ')
assert_eq "2" "$GOT"

_test_begin "filter here /home/fake/project -> 1 id"
GOT=$(printf '%s\n' "$INV" | _prune_filter_inventory here "/home/fake/project" | wc -l | tr -d ' ')
assert_eq "1" "$GOT"

_test_begin "filter here /home/nested/project -> 1 id (nested layout)"
GOT=$(printf '%s\n' "$INV" | _prune_filter_inventory here "/home/nested/project" | wc -l | tr -d ' ')
assert_eq "1" "$GOT"

_test_begin "filter here /nope -> 0 ids"
GOT=$(printf '%s\n' "$INV" | _prune_filter_inventory here "/nope" | tr -d '\n')
assert_eq "" "$GOT"

# ---- delete (destructive — copy fixtures to tmp first) -------------------
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp -r "$HERE/fixtures/pi/." "$TMP/"

export PRUNE_PI_SESSIONS_DIR="$TMP"

_test_begin "delete one session removes its file"
INV2=$(prune_pi_inventory)
SID=$(printf '%s\n' "$INV2" | head -1 | awk -F'\t' '{print $1}')
PATH_BEFORE=$(printf '%s\n' "$INV2" | head -1 | awk -F'\t' '{print $6}')
prune_pi_delete "$SID" >/dev/null 2>&1 || true
if [[ -f "$PATH_BEFORE" ]]; then
    _test_fail "file still exists: $PATH_BEFORE"
else
    INV3=$(prune_pi_inventory)
    NEW=$(printf '%s\n' "$INV3" | wc -l | tr -d ' ')
    if [[ "$NEW" == "3" ]]; then
        _test_pass
    else
        _test_fail "expected 3 remaining, got $NEW"
    fi
fi

_test_begin "delete a flat-layout session cleans up its cwd-encoded dir"
INV2=$(prune_pi_inventory)
SID=$(printf '%s\n' "$INV2" | awk -F'\t' '$3=="/home/fake/project"{print $1; exit}')
if [[ -n "$SID" ]]; then
    prune_pi_delete "$SID" >/dev/null 2>&1 || true
fi
if [[ -d "$TMP/--home-fake-project--" ]]; then
    _test_fail "empty dir not removed"
else
    _test_pass
fi

_test_begin "delete a nested-layout session cleans up the whole nested chain"
INV2=$(prune_pi_inventory)
SID=$(printf '%s\n' "$INV2" | awk -F'\t' '$3=="/home/nested/project"{print $1; exit}')
if [[ -n "$SID" ]]; then
    prune_pi_delete "$SID" >/dev/null 2>&1 || true
fi
if [[ -d "$TMP/--home-nested-project--" ]]; then
    _test_fail "nested empty dir chain not collapsed"
else
    _test_pass
fi

# Restore the read-only fixtures path for any later tests in this file
export PRUNE_PI_SESSIONS_DIR="$HERE/fixtures/pi"

_test_summary
