#!/usr/bin/env bash
# Tests for lib/core.sh helpers.
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

# ---- _prune_parse_age -----------------------------------------------------
_test_begin "_prune_parse_age 30d -> 2592000"
assert_eq "2592000" "$(_prune_parse_age 30d)"

_test_begin "_prune_parse_age 12h -> 43200"
assert_eq "43200" "$(_prune_parse_age 12h)"

_test_begin "_prune_parse_age 45m -> 2700"
assert_eq "2700" "$(_prune_parse_age 45m)"

_test_begin "_prune_parse_age wat -> exit 1"
assert_exit 1 _prune_parse_age "wat"

_test_begin "_prune_parse_age 5x -> exit 1"
assert_exit 1 _prune_parse_age "5x"

_test_begin "_prune_parse_age empty -> exit 1"
assert_exit 1 _prune_parse_age ""

# ---- _prune_filter_inventory ----------------------------------------------
INVENTORY=$(printf '%s\n' \
    $'id1\ttitle1\t/home/x\t2026-04-25 10:00\t5' \
    $'id2\ttitle2\t/home/y\t2026-04-26 12:00\t3' \
    $'id3\ttitle3\t/home/x\t2026-04-26 14:00\t7')

_test_begin "filter all -> all 3 ids"
GOT=$(printf '%s\n' "$INVENTORY" | _prune_filter_inventory all | wc -l | tr -d ' ')
assert_eq "3" "$GOT"

_test_begin "filter here /home/x -> 2 ids"
GOT=$(printf '%s\n' "$INVENTORY" | _prune_filter_inventory here "/home/x" | wc -l | tr -d ' ')
assert_eq "2" "$GOT"

_test_begin "filter here /nope -> 0 ids"
GOT=$(printf '%s\n' "$INVENTORY" | _prune_filter_inventory here "/nope" | tr -d '\n')
assert_eq "" "$GOT"

# Age filter: cutoff = "now - 1 day" should select rows older than that.
NOW=$(date +%s)
CUTOFF=$(( NOW - 86400 ))
_test_begin "filter age 1d ago -> id1 (2026-04-25)"
# Note: this assumes today is >= 2026-04-26. If running in the past, skip silently.
TODAY=$(date +%Y-%m-%d)
if [[ "$TODAY" > "2026-04-25" ]]; then
    GOT=$(printf '%s\n' "$INVENTORY" | _prune_filter_inventory age "$CUTOFF")
    assert_contains "$GOT" "id1"
else
    _test_pass
fi

# ---- _prune_format_table --------------------------------------------------
_test_begin "format_table: header has HEADER prefix"
GOT=$(printf '%s\n' "$INVENTORY" | _prune_format_table | head -1)
assert_contains "$GOT" "HEADER"

_test_begin "format_table: emits one line per input row + header"
GOT=$(printf '%s\n' "$INVENTORY" | _prune_format_table | wc -l | tr -d ' ')
assert_eq "4" "$GOT"

_test_begin "format_table: keeps id as field 1 for awk extraction"
GOT=$(printf '%s\n' "$INVENTORY" | _prune_format_table | tail -n +2 | awk -F'\t' '{print $1}' | head -1)
assert_eq "id1" "$GOT"

_test_summary
