#!/usr/bin/env bash
# Adapter forge: contract tests against tests/fixtures/forge/.forge.db.
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
cp "$HERE/fixtures/forge/.forge.db" "$TMP/.forge.db"
export PRUNE_FORGE_DB="$TMP/.forge.db"
# shellcheck source=../adapters/forge.sh
source "$ROOT/adapters/forge.sh"

# ---- doctor ---------------------------------------------------------------
_test_begin "forge doctor passes when DB exists"
assert_exit 0 prune_forge_doctor

_test_begin "forge doctor fails on missing DB"
RC=0
PRUNE_FORGE_DB=/nope.db prune_forge_doctor >/dev/null 2>&1 || RC=$?
assert_eq "1" "$RC"

# ---- inventory ------------------------------------------------------------
INV=$(prune_forge_inventory)

_test_begin "inventory: 4 fixture rows (incl. orphan)"
GOT=$(printf '%s\n' "$INV" | wc -l | tr -d ' ')
assert_eq "4" "$GOT"

_test_begin "inventory: 5 columns"
ROW=$(printf '%s\n' "$INV" | head -1)
GOT=$(awk -F'\t' '{print NF}' <<<"$ROW")
assert_eq "5" "$GOT"

_test_begin "inventory: orphan flagged with [orphan] prefix"
assert_contains "$INV" "[orphan]"

_test_begin "inventory: cwd extracted from context XML"
GOT=$(printf '%s\n' "$INV" | awk -F'\t' '$3=="/tmp/prune-test"' | wc -l | tr -d ' ')
assert_eq "2" "$GOT"

_test_begin "inventory: untitled becomes (untitled)"
assert_contains "$INV" "(untitled)"

# ---- preview --------------------------------------------------------------
_test_begin "preview shows conversation metadata"
GOT=$(prune_forge_preview "conv-fixture-001")
assert_contains "$GOT" "conv-fixture-001"

_test_begin "preview shows first user message text"
GOT=$(prune_forge_preview "conv-fixture-001")
assert_contains "$GOT" "hola forge fixture 1"

_test_begin "preview is robust to bogus id"
assert_exit 0 prune_forge_preview "ZZZ_INVALID"

_test_begin "preview rejects malformed id"
GOT=$(prune_forge_preview "abc'; DROP TABLE conversations; --")
assert_contains "$GOT" "invalid id"

# ---- here filter via core -------------------------------------------------
_test_begin "filter here /tmp/prune-test -> 2 ids"
GOT=$(printf '%s\n' "$INV" | _prune_filter_inventory here "/tmp/prune-test" | wc -l | tr -d ' ')
assert_eq "2" "$GOT"

_test_begin "filter here /home/fake/project -> 1 id"
GOT=$(printf '%s\n' "$INV" | _prune_filter_inventory here "/home/fake/project" | wc -l | tr -d ' ')
assert_eq "1" "$GOT"

# ---- delete ---------------------------------------------------------------
_test_begin "delete one conversation removes it from DB"
prune_forge_delete "conv-fixture-001" >/dev/null 2>&1 || true
COUNT=$(sqlite3 "$PRUNE_FORGE_DB" "SELECT COUNT(*) FROM conversations WHERE conversation_id='conv-fixture-001';")
assert_eq "0" "$COUNT"

_test_begin "delete handles orphan (no context) row"
prune_forge_delete "conv-fixture-orphan" >/dev/null 2>&1 || true
COUNT=$(sqlite3 "$PRUNE_FORGE_DB" "SELECT COUNT(*) FROM conversations WHERE conversation_id='conv-fixture-orphan';")
assert_eq "0" "$COUNT"

_test_begin "delete remaining 2 in one call"
prune_forge_delete "conv-fixture-002" "conv-fixture-003" >/dev/null 2>&1 || true
COUNT=$(sqlite3 "$PRUNE_FORGE_DB" "SELECT COUNT(*) FROM conversations;")
assert_eq "0" "$COUNT"

_test_summary
