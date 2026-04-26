#!/usr/bin/env bash
# Adapter opencode: contract tests against tests/fixtures/opencode/opencode.db.
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

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp "$HERE/fixtures/opencode/opencode.db" "$TMP/opencode.db"
export PRUNE_OPENCODE_DB="$TMP/opencode.db"
# shellcheck source=../adapters/opencode.sh
source "$ROOT/adapters/opencode.sh"

# ---- doctor ---------------------------------------------------------------
_test_begin "opencode doctor passes when DB exists"
assert_exit 0 prune_opencode_doctor

_test_begin "opencode doctor fails on missing DB"
RC=0
PRUNE_OPENCODE_DB=/nope.db prune_opencode_doctor >/dev/null 2>&1 || RC=$?
assert_eq "1" "$RC"

# ---- inventory ------------------------------------------------------------
INV=$(prune_opencode_inventory)

_test_begin "inventory: 3 fixture rows"
GOT=$(printf '%s\n' "$INV" | wc -l | tr -d ' ')
assert_eq "3" "$GOT"

_test_begin "inventory: 7 columns"
ROW=$(printf '%s\n' "$INV" | head -1)
GOT=$(awk -F'\t' '{print NF}' <<<"$ROW")
assert_eq "7" "$GOT"

_test_begin "inventory: ses_fixture00000000000000001 is present"
assert_contains "$INV" "ses_fixture00000000000000001"

_test_begin "inventory: ordered by time_updated DESC"
FIRST_ID=$(printf '%s\n' "$INV" | head -1 | awk -F'\t' '{print $1}')
assert_eq "ses_fixture00000000000000003" "$FIRST_ID"

_test_begin "inventory: includes sessions outside global project"
GOT=$(printf '%s\n' "$INV" | awk -F'\t' '$3=="/home/fake/project"' | wc -l | tr -d ' ')
assert_eq "1" "$GOT"

# ---- preview --------------------------------------------------------------
_test_begin "preview shows session metadata"
GOT=$(prune_opencode_preview "ses_fixture00000000000000001")
assert_contains "$GOT" "ses_fixture00000000000000001"

_test_begin "preview shows first user message text"
GOT=$(prune_opencode_preview "ses_fixture00000000000000001")
assert_contains "$GOT" "hola opencode fixture 1"

_test_begin "preview is robust to bogus id"
assert_exit 0 prune_opencode_preview "ZZZ_INVALID"

_test_begin "preview rejects malformed id"
GOT=$(prune_opencode_preview "abc'; DROP TABLE session; --")
assert_contains "$GOT" "invalid id"

# ---- here filter via core -------------------------------------------------
_test_begin "filter here /tmp/prune-test -> 2 ids"
GOT=$(printf '%s\n' "$INV" | _prune_filter_inventory here "/tmp/prune-test" | wc -l | tr -d ' ')
assert_eq "2" "$GOT"

_test_begin "filter here /home/fake/project -> 1 id"
GOT=$(printf '%s\n' "$INV" | _prune_filter_inventory here "/home/fake/project" | wc -l | tr -d ' ')
assert_eq "1" "$GOT"

# ---- delete (SQL fallback path because no real `opencode` CLI in CI) ------
_test_begin "delete one session removes it from DB"
prune_opencode_delete "ses_fixture00000000000000001" >/dev/null 2>&1 || true
COUNT=$(sqlite3 "$PRUNE_OPENCODE_DB" "SELECT COUNT(*) FROM session WHERE id='ses_fixture00000000000000001';")
assert_eq "0" "$COUNT"

_test_begin "delete cascades messages"
COUNT=$(sqlite3 "$PRUNE_OPENCODE_DB" "PRAGMA foreign_keys=ON; SELECT COUNT(*) FROM message WHERE session_id='ses_fixture00000000000000001';")
assert_eq "0" "$COUNT"

_test_begin "delete cascades parts"
COUNT=$(sqlite3 "$PRUNE_OPENCODE_DB" "PRAGMA foreign_keys=ON; SELECT COUNT(*) FROM part WHERE session_id='ses_fixture00000000000000001';")
assert_eq "0" "$COUNT"

_test_begin "delete remaining 2 in one call"
prune_opencode_delete "ses_fixture00000000000000002" "ses_fixture00000000000000003" >/dev/null 2>&1 || true
COUNT=$(sqlite3 "$PRUNE_OPENCODE_DB" "SELECT COUNT(*) FROM session;")
assert_eq "0" "$COUNT"

_test_summary
