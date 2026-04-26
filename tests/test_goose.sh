#!/usr/bin/env bash
# Adapter goose: contract tests against tests/fixtures/goose/sessions.db.
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

# Build a fresh fixture DB into a tmp file so destructive tests don't touch
# the in-tree fixture.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cp "$HERE/fixtures/goose/sessions.db" "$TMP/sessions.db"
export PRUNE_GOOSE_DB="$TMP/sessions.db"
# shellcheck source=../adapters/goose.sh
source "$ROOT/adapters/goose.sh"

# ---- doctor ---------------------------------------------------------------
_test_begin "goose doctor passes when DB exists"
assert_exit 0 prune_goose_doctor

_test_begin "goose doctor fails on missing DB"
RC=0
PRUNE_GOOSE_DB=/nope.db prune_goose_doctor >/dev/null 2>&1 || RC=$?
assert_eq "1" "$RC"

# ---- inventory ------------------------------------------------------------
INV=$(prune_goose_inventory)

_test_begin "inventory: 3 fixture rows"
GOT=$(printf '%s\n' "$INV" | wc -l | tr -d ' ')
assert_eq "3" "$GOT"

_test_begin "inventory: 7 columns"
ROW=$(printf '%s\n' "$INV" | head -1)
GOT=$(awk -F'\t' '{print NF}' <<<"$ROW")
assert_eq "7" "$GOT"

_test_begin "inventory: id 20260101_1 is present"
assert_contains "$INV" "20260101_1"

_test_begin "inventory: model_name extracted from JSON"
assert_contains "$INV" "claude-sonnet-4-6"

_test_begin "inventory: ordered by updated DESC"
FIRST_ID=$(printf '%s\n' "$INV" | head -1 | awk -F'\t' '{print $1}')
assert_eq "20260301_1" "$FIRST_ID"

# ---- preview --------------------------------------------------------------
_test_begin "preview shows session metadata"
GOT=$(prune_goose_preview "20260101_1")
assert_contains "$GOT" "20260101_1"

_test_begin "preview shows first user message text"
GOT=$(prune_goose_preview "20260101_1")
assert_contains "$GOT" "hola goose fixture 1"

_test_begin "preview shows last assistant message"
GOT=$(prune_goose_preview "20260101_1")
assert_contains "$GOT" "hola, soy goose"

_test_begin "preview is robust to bogus id"
assert_exit 0 prune_goose_preview "ZZZ_INVALID"

_test_begin "preview rejects malformed id (defense in depth)"
GOT=$(prune_goose_preview "abc'; DROP TABLE sessions; --")
assert_contains "$GOT" "invalid id"

# ---- here filter via core -------------------------------------------------
_test_begin "filter here /tmp/prune-test -> 2 ids"
GOT=$(printf '%s\n' "$INV" | _prune_filter_inventory here "/tmp/prune-test" | wc -l | tr -d ' ')
assert_eq "2" "$GOT"

_test_begin "filter here /home/fake/project -> 1 id"
GOT=$(printf '%s\n' "$INV" | _prune_filter_inventory here "/home/fake/project" | wc -l | tr -d ' ')
assert_eq "1" "$GOT"

# ---- delete ---------------------------------------------------------------
_test_begin "delete one session removes it from DB"
prune_goose_delete "20260101_1" >/dev/null 2>&1 || true
COUNT=$(sqlite3 "$PRUNE_GOOSE_DB" "SELECT COUNT(*) FROM sessions WHERE id='20260101_1';")
assert_eq "0" "$COUNT"

_test_begin "delete cascades messages"
COUNT=$(sqlite3 "$PRUNE_GOOSE_DB" "SELECT COUNT(*) FROM messages WHERE session_id='20260101_1';")
assert_eq "0" "$COUNT"

_test_begin "delete remaining 2 sessions in one call"
prune_goose_delete "20260201_1" "20260301_1" >/dev/null 2>&1 || true
COUNT=$(sqlite3 "$PRUNE_GOOSE_DB" "SELECT COUNT(*) FROM sessions;")
assert_eq "0" "$COUNT"

_test_summary
