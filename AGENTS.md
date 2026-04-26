# Prune — Agent Install & Use Guide

> **Audience:** AI coding agents.
> **Format:** deterministic, no chitchat. Skim top to bottom; copy commands as-is.
> **Doc version:** for Prune v0.1.0 (2026-04-26).

## Identity

| Field | Value |
|------|------|
| name | Prune |
| repo | https://github.com/soyruiz/Prune |
| license | MIT |
| binary | `prune` (plus per-harness wrappers `pi-prune`, `goose-prune`, `opencode-prune`, `forge-prune`) |
| purpose | Bulk-delete stored sessions of AI coding-agent CLIs (Pi, Goose, opencode, Forge) with an fzf picker UX |
| shells | bash >= 4, zsh |
| os | Linux x86_64/aarch64; macOS arm64/x86_64 (requires `brew install bash`) |
| runtime deps | fzf, python3, awk, date, sqlite3 (sqlite3 only required for goose/opencode/forge) |

## Install — pick one

### Option A: one-liner (curl|bash)

```bash
curl -fsSL https://raw.githubusercontent.com/soyruiz/Prune/main/install.sh | bash
```

### Option B: manual clone (auditable)

```bash
git clone https://github.com/soyruiz/Prune ~/Proyectos/Prune
cd ~/Proyectos/Prune
./install.sh
```

### Option C: custom paths

```bash
./install.sh --prefix /opt/prune --bin /usr/local/bin
```

Flags:
- `--prefix DIR` — where lib + adapters live (default: `$XDG_DATA_HOME` or `~/.local/share`).
- `--bin DIR` — where `prune` and the wrappers go (default: `~/.local/bin`).
- `--no-rc` — skip editing `~/.zshrc` / `~/.bashrc`.
- `--no-wrappers` — skip the `<harness>-prune` wrappers.
- `--dry-run` — show actions without writing.

## Verify install

```bash
exec $SHELL -l       # reload your shell so the new $PATH takes effect
prune --version      # expected: prune 0.1.0
prune doctor         # expected: deps OK + list of adapters with status
prune                # summary: harnesses installed + session counts
```

## Use — command matrix

| Goal | Command | Notes |
|------|---------|-------|
| Open the picker for one harness | `prune pi` | Tab to select, Enter to delete, Esc to cancel |
| Same with backward-compat wrapper | `pi-prune` | Equivalent to `prune pi` |
| Delete every Pi session older than 30 days | `prune pi 30d` | Confirms first |
| Delete Goose sessions opened in `$PWD` | `prune goose here` | Confirms first |
| Delete ALL opencode sessions | `prune opencode all` | ⚠ permanent — confirms first |
| Dry-run any deletion mode | `prune <harness> <mode> --dry-run` | Lists targets, no delete |
| Health check | `prune doctor` | Lists deps + adapter status |
| Help | `prune --help` | Same content, terse |

Time units accepted: `d` (days), `h` (hours), `m` (minutes). Examples: `30d`, `12h`, `45m`.

## Per-adapter notes

| Harness | Storage | Inventory source | Delete method |
|---------|---------|------------------|---------------|
| Pi | `~/.pi/agent/sessions/**/*.jsonl` | filesystem walk | `rm -f` + collapse empty dirs |
| Goose | `~/.local/share/goose/sessions/sessions.db` | direct sqlite3 query | sqlite3 transaction (Goose v1.31+ confirms via /dev/tty, so `yes |` doesn't work) |
| opencode | `~/.local/share/opencode/opencode.db` | direct sqlite3 query (queries ALL projects, not just `global` like the official CLI) | `opencode session delete` if available, else sqlite3 |
| Forge | `~/.forge/.forge.db` | sqlite3 query of `conversations` table | sqlite3 transaction (Forge has known orphan-row issues with its own delete API) |

Override storage paths via env vars (used by tests; useful for sandboxing):
- `PRUNE_PI_SESSIONS_DIR`
- `PRUNE_GOOSE_DB`
- `PRUNE_OPENCODE_DB`
- `PRUNE_FORGE_DB`

## Adapter contract (for adding a new harness)

A new harness `xxx` is added by dropping `adapters/xxx.sh` into the install dir
or repo. The file must define three bash functions and may optionally define a
fourth:

```bash
# REQUIRED. Print one tab-separated row per session, newest first.
# Columns (minimum): id<TAB>title<TAB>directory<TAB>updated<TAB>messages
# Up to two extra columns are allowed and shown in the picker.
prune_xxx_inventory() { ... }

# REQUIRED. Print a human-readable preview to stdout. Must be safe with bogus
# or malformed IDs (no crash).
prune_xxx_preview() { local id="$1"; ... }

# REQUIRED. Delete the given session ids. Print progress to stdout. Exit 0 on
# full success, 1 on any failure. Use stderr for error messages.
prune_xxx_delete() { local ids=("$@"); ... }

# OPTIONAL. Pre-flight check. Exit 0 if usable, 1 otherwise. Print human
# diagnostic to stderr.
prune_xxx_doctor() { ... }
```

The core (in `lib/core.sh`) handles the picker, confirm dialog, age parser
(`<N>{d,h,m}`), and `here` filter. Adapters never call fzf directly.

See `docs/ADAPTERS.md` for the full contract reference and `adapters/pi.sh` as
the canonical example.

## Troubleshooting matrix

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| `prune: command not found` after install | `~/.local/bin` not on `$PATH` | Open new shell; check installer added the marker block to your rc |
| `bash: declare: -A: invalid option` | bash 3.x (macOS default) | `brew install bash`, then `bash ./install.sh` |
| `prune doctor`: `sqlite3 missing` | sqlite3 not installed | `apt install sqlite3` / `brew install sqlite3` |
| `prune <harness>` shows count 0 but you have sessions | wrong storage path | `PRUNE_<HARNESS>_DB=... prune doctor`; ensure CLI version matches the matrix below |
| Goose sessions survive `prune goose all` | DB locked by running Goose Desktop | quit Goose Desktop, retry |
| `prune opencode` shows fewer sessions than `opencode session list` | nothing — Prune intentionally shows top-level sessions across ALL projects, not just `global` | (working as designed) |

## Compatibility matrix (tested versions)

| Harness | Tested versions | Notes |
|---------|-----------------|-------|
| Pi | 0.70.x, 0.71.x | Supports both flat and nested session-file layouts |
| Goose | 1.10–1.31 | v1.31+ requires SQL fallback for delete |
| opencode | 1.14.25 | DB schema may shift; report breakage via issue |
| Forge | local install (proprietary) | Best effort; orphan rows handled |

## Uninstall

```bash
~/.local/share/prune/uninstall.sh        # canonical
# Or from a fresh clone:
cd ~/Proyectos/Prune && ./uninstall.sh
```

Removes the install dir, all `<harness>-prune` wrappers, and the marker block
from `~/.zshrc` and `~/.bashrc`. Idempotent.

## When to NOT run Prune

- While the same harness's TUI is running in another terminal — the row you
  delete might be the active session. Same caveat as the original Forge `:prune`.
- Inside CI for production data — `--dry-run` first, always.

## Reporting issues

Issues: https://github.com/soyruiz/Prune/issues

Please include:
1. `prune --version` output.
2. `prune doctor` output (redact paths if sensitive).
3. Relevant harness version: `pi --version` / `goose --version` / `opencode --version`.
4. Reproduction steps.
