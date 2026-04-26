#!/usr/bin/env bash
# Prune installer — idempotent. Re-running is safe and won't duplicate rc lines.
set -euo pipefail

# Markers used to find/remove our edits in shell rc files.
_MARK_BEGIN='# >>> prune (https://github.com/soyruiz/Prune) >>>'
_MARK_END='# <<< prune (https://github.com/soyruiz/Prune) <<<'

usage() {
    cat <<EOF
Prune installer.

Usage:
  ./install.sh [options]

Options:
  --prefix DIR     install prune lib + adapters under DIR/prune/
                   (default: \$XDG_DATA_HOME or ~/.local/share)
  --bin DIR        install the prune executable + wrappers in DIR
                   (default: ~/.local/bin)
  --no-rc          skip editing ~/.zshrc / ~/.bashrc
  --no-wrappers    skip the per-harness wrappers (pi-prune, etc.)
  --dry-run        show what would be done without making changes
  -h, --help       this help

Re-running is safe: existing files are overwritten with the current source,
and rc edits are deduplicated via begin/end markers.

Uninstall: run ./uninstall.sh with the same --prefix / --bin flags.
EOF
}

# ---------- arg parsing ----------------------------------------------------
PREFIX="${XDG_DATA_HOME:-$HOME/.local/share}"
BIN="$HOME/.local/bin"
NO_RC=0
NO_WRAPPERS=0
DRY=0

while (( $# > 0 )); do
    case "$1" in
        --prefix)       PREFIX="$2"; shift 2 ;;
        --bin)          BIN="$2"; shift 2 ;;
        --no-rc)        NO_RC=1; shift ;;
        --no-wrappers)  NO_WRAPPERS=1; shift ;;
        --dry-run)      DRY=1; shift ;;
        -h|--help)      usage; exit 0 ;;
        *) printf 'install.sh: unknown option %s\n' "$1" >&2; exit 2 ;;
    esac
done

DEST="$PREFIX/prune"
SRC=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# ---------- helpers --------------------------------------------------------
say()  { printf '%s\n' "$*"; }
do_or_say() {
    if (( DRY == 1 )); then
        printf '  [dry-run] %s\n' "$*"
    else
        eval "$@"
    fi
}

# ---------- preflight: deps -----------------------------------------------
require_cmd() {
    local c="$1" hint="$2"
    if ! command -v "$c" >/dev/null 2>&1; then
        printf 'install.sh: missing dependency %s — %s\n' "$c" "$hint" >&2
        exit 1
    fi
}

# Bash 4+ (associative arrays, mapfile). macOS default bash 3.2 is rejected.
if (( BASH_VERSINFO[0] < 4 )); then
    cat >&2 <<EOF
install.sh: bash $BASH_VERSION is too old. Prune requires bash >= 4.

  macOS: brew install bash
  then re-run: bash ./install.sh

EOF
    exit 1
fi

require_cmd fzf     "install fzf (https://github.com/junegunn/fzf)"
require_cmd python3 "install python3 (>= 3.8)"
require_cmd awk     "install gawk or use system awk"
require_cmd date    "install coreutils"
# sqlite3 is required by goose/forge/opencode adapters but missing it shouldn't
# block install — `prune doctor` will warn at runtime.
if ! command -v sqlite3 >/dev/null 2>&1; then
    say "warning: sqlite3 not found — goose/opencode/forge adapters will be unusable until you install it."
fi

# ---------- copy lib + adapters -------------------------------------------
say "Installing Prune to $DEST"
do_or_say "mkdir -p \"$DEST\" \"$BIN\""

# Use rsync if available for cleaner output, else tar over a pipe.
copy_tree() {
    local src="$1" dst="$2"
    if (( DRY == 1 )); then
        printf '  [dry-run] copy %s -> %s\n' "$src" "$dst"
        return
    fi
    if command -v rsync >/dev/null 2>&1; then
        rsync -a --delete "$src/" "$dst/"
    else
        rm -rf "$dst"
        mkdir -p "$dst"
        cp -R "$src/." "$dst/"
    fi
}

# Layout used by the installer (the binary's `_resolve_self` follows symlinks):
#   $DEST/lib/         <- core.sh, ui.sh, version.sh
#   $DEST/adapters/    <- pi.sh, goose.sh, opencode.sh, forge.sh
#   $DEST/bin/prune    <- real entrypoint
#   $BIN/prune         <- symlink -> $DEST/bin/prune
for sub in lib adapters; do
    copy_tree "$SRC/$sub" "$DEST/$sub"
done

# Install the real entrypoint inside $DEST/bin/, then symlink into $BIN.
REAL_BIN="$DEST/bin/prune"
INSTALLED_BIN="$BIN/prune"
if (( DRY == 1 )); then
    printf '  [dry-run] write executable %s\n' "$REAL_BIN"
    printf '  [dry-run] symlink %s -> %s\n' "$INSTALLED_BIN" "$REAL_BIN"
else
    mkdir -p "$DEST/bin"
    install -m 0755 "$SRC/bin/prune" "$REAL_BIN"
    ln -sf "$REAL_BIN" "$INSTALLED_BIN"
fi

# Carry uninstall.sh into the install dir so users without the source tree
# can still cleanly uninstall.
if [[ -f "$SRC/uninstall.sh" ]]; then
    if (( DRY == 1 )); then
        printf '  [dry-run] copy uninstall.sh\n'
    else
        install -m 0755 "$SRC/uninstall.sh" "$DEST/uninstall.sh"
    fi
fi

# ---------- per-harness wrappers ------------------------------------------
ADAPTER_NAMES=()
for f in "$DEST/adapters"/*.sh; do
    [[ -e "$f" ]] || continue
    ADAPTER_NAMES+=("$(basename "$f" .sh)")
done

if (( NO_WRAPPERS == 0 )); then
    for name in "${ADAPTER_NAMES[@]}"; do
        wrapper="$BIN/${name}-prune"
        if (( DRY == 1 )); then
            printf '  [dry-run] write wrapper %s\n' "$wrapper"
        else
            cat > "$wrapper" <<EOF
#!/usr/bin/env bash
# Auto-generated by Prune installer. Forwards to: prune ${name} <args>
exec "$INSTALLED_BIN" ${name} "\$@"
EOF
            chmod 0755 "$wrapper"
        fi
    done
fi

# ---------- shell rc edits (idempotent via markers) -----------------------
inject_rc() {
    local rc="$1"
    if [[ ! -f "$rc" ]]; then
        return 0
    fi
    if grep -q "$_MARK_BEGIN" "$rc" 2>/dev/null; then
        # Already installed — nothing to do (idempotent).
        return 0
    fi
    if (( DRY == 1 )); then
        printf '  [dry-run] append PATH+marker block to %s\n' "$rc"
        return 0
    fi
    {
        printf '\n%s\n' "$_MARK_BEGIN"
        printf '%s\n' "case \":\$PATH:\" in *\":$BIN:\"*) ;; *) export PATH=\"$BIN:\$PATH\" ;; esac"
        printf '%s\n' "$_MARK_END"
    } >> "$rc"
}

if (( NO_RC == 0 )); then
    for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
        inject_rc "$rc"
    done
fi

# ---------- final message --------------------------------------------------
if (( DRY == 1 )); then
    say ""
    say "Dry-run complete. No changes written."
    exit 0
fi

say ""
say "✓ Installed Prune ${PRUNE_VERSION:-} to $DEST"
say "  binary:   $INSTALLED_BIN"
if (( NO_WRAPPERS == 0 )); then
    say "  wrappers: ${ADAPTER_NAMES[*]/%/-prune}"
fi
say ""
case ":$PATH:" in
    *":$BIN:"*) say "Run:    prune doctor" ;;
    *)          say "Open a new shell (or 'source ~/.zshrc') and run: prune doctor" ;;
esac
say "Help:   prune --help"
