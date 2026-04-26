#!/usr/bin/env bash
# Tests for install.sh / uninstall.sh: idempotency, --prefix/--bin, clean unin.
set -euo pipefail

HERE=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -P "$HERE/.." && pwd)

# shellcheck source=lib/assert.sh
source "$HERE/lib/assert.sh"

TMP=$(mktemp -d)
PREFIX="$TMP/share"
BIN="$TMP/bin"
FAKE_HOME="$TMP/home"
mkdir -p "$FAKE_HOME"
# Pre-create rc files so the installer can edit them.
: > "$FAKE_HOME/.zshrc"
: > "$FAKE_HOME/.bashrc"
trap 'rm -rf "$TMP"' EXIT

run_install() {
    HOME="$FAKE_HOME" "$ROOT/install.sh" --prefix "$PREFIX" --bin "$BIN" "$@"
}

run_uninstall() {
    HOME="$FAKE_HOME" "$ROOT/uninstall.sh" --prefix "$PREFIX" --bin "$BIN" "$@"
}

# ---- dry-run does NOT write anything --------------------------------------
_test_begin "install --dry-run does not create files"
run_install --dry-run >/dev/null 2>&1 || true
if [[ ! -e "$PREFIX/prune" && ! -e "$BIN/prune" ]]; then
    _test_pass
else
    _test_fail "dry-run wrote files"
fi

# ---- real install ---------------------------------------------------------
_test_begin "install writes the binary"
run_install >/dev/null 2>&1
[[ -x "$BIN/prune" ]] && _test_pass || _test_fail "$BIN/prune missing"

_test_begin "install writes lib/core.sh"
[[ -f "$PREFIX/prune/lib/core.sh" ]] && _test_pass || _test_fail "lib/core.sh missing"

_test_begin "install writes adapters/*.sh"
N=$(ls "$PREFIX/prune/adapters"/*.sh 2>/dev/null | wc -l | tr -d ' ')
assert_eq "4" "$N"

_test_begin "install creates wrappers for each adapter"
for h in pi goose opencode forge; do
    if [[ ! -x "$BIN/${h}-prune" ]]; then
        _test_fail "missing wrapper: ${h}-prune"
        break
    fi
done
[[ -x "$BIN/pi-prune" && -x "$BIN/goose-prune" && -x "$BIN/opencode-prune" && -x "$BIN/forge-prune" ]] \
    && _test_pass

_test_begin "install adds marker block to .zshrc"
N=$(grep -c '>>> prune' "$FAKE_HOME/.zshrc")
assert_eq "1" "$N"

_test_begin "install adds marker block to .bashrc"
N=$(grep -c '>>> prune' "$FAKE_HOME/.bashrc")
assert_eq "1" "$N"

# ---- idempotency ----------------------------------------------------------
_test_begin "running install a second time keeps exactly one rc block"
run_install >/dev/null 2>&1
N=$(grep -c '>>> prune' "$FAKE_HOME/.zshrc")
assert_eq "1" "$N"

_test_begin "second install leaves binary executable"
[[ -x "$BIN/prune" ]] && _test_pass || _test_fail "binary lost +x"

# ---- the installed binary actually runs -----------------------------------
_test_begin "installed prune --version works"
GOT=$("$BIN/prune" --version 2>&1)
assert_contains "$GOT" "prune 0.1.0"

_test_begin "installed prune doctor lists 4 adapters"
GOT=$("$BIN/prune" doctor 2>&1)
for h in pi goose opencode forge; do
    if ! grep -q "$h" <<<"$GOT"; then
        _test_fail "doctor missing $h"
        break
    fi
done
grep -q pi <<<"$GOT" && grep -q goose <<<"$GOT" && \
    grep -q opencode <<<"$GOT" && grep -q forge <<<"$GOT" && _test_pass

_test_begin "wrapper pi-prune --help works and forwards correctly"
GOT=$("$BIN/pi-prune" --help 2>&1)
assert_contains "$GOT" "prune <harness>"

# ---- uninstall ------------------------------------------------------------
_test_begin "uninstall --dry-run does not remove files"
run_uninstall --dry-run >/dev/null 2>&1
[[ -x "$BIN/prune" ]] && _test_pass || _test_fail "dry-run removed files"

_test_begin "uninstall removes the install dir"
run_uninstall >/dev/null 2>&1
[[ ! -e "$PREFIX/prune" ]] && _test_pass || _test_fail "$PREFIX/prune still there"

_test_begin "uninstall removes the binary"
[[ ! -e "$BIN/prune" ]] && _test_pass || _test_fail "$BIN/prune still there"

_test_begin "uninstall removes wrappers"
shopt -s nullglob
WRAP=("$BIN"/*-prune)
shopt -u nullglob
N=${#WRAP[@]}
assert_eq "0" "$N"

_test_begin "uninstall strips marker block from .zshrc"
N=$(grep -c '>>> prune' "$FAKE_HOME/.zshrc" || true)
assert_eq "0" "$N"

_test_begin "uninstall strips marker block from .bashrc"
N=$(grep -c '>>> prune' "$FAKE_HOME/.bashrc" || true)
assert_eq "0" "$N"

# ---- second uninstall is a no-op (idempotent) -----------------------------
_test_begin "second uninstall is a no-op"
assert_exit 0 run_uninstall

_test_summary
