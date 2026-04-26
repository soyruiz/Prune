# Adapter contract

A Prune adapter teaches the core how to manage sessions for one specific AI
coding-agent CLI ("harness"). Each adapter is a single bash file at
`adapters/<name>.sh` exporting three required functions and one optional one.

The core (in `lib/core.sh`) handles everything that's the same across
harnesses: the fzf picker, confirm dialog, age parser, "here" filter, and
top-level dispatch. Adapters never call `fzf` directly.

## File location and naming

- Path: `adapters/<name>.sh` where `<name>` matches `^[a-z][a-z0-9_-]*$`.
- Functions are prefixed `prune_<name>_`.
- The wrapper (`<name>-prune`) and the subcommand (`prune <name>`) both
  derive from `<name>`.

The installer auto-discovers any `*.sh` file in `adapters/` at install time,
so dropping a new file into the source tree before running `./install.sh` is
all that's needed.

## Required functions

### `prune_<name>_inventory`

Print a tab-separated row per session, **newest first** (sorted by the
"updated" column). Columns, in order:

| # | Column | Type | Notes |
|---|--------|------|-------|
| 1 | `id` | string | Must be unique. Used as the key for delete/preview lookups. Avoid spaces/tabs. |
| 2 | `title` | string | Human-readable label (truncated to ≈80 chars). Use `(untitled)` if missing. |
| 3 | `directory` | string | Absolute path of the cwd at session start. Used by the `here` mode filter. |
| 4 | `updated` | `YYYY-MM-DD HH:MM` | Last-modified time. Must be parseable by GNU `date -d`. |
| 5 | `messages` | integer | Message count. Use `0` if unknown. |
| 6 | `extra1` | string (optional) | Tokens, model, project, etc. Shown in the picker. |
| 7 | `extra2` | string (optional) | Same. |

Stdout only. Must NOT exit nonzero on an empty result — print nothing instead.

### `prune_<name>_preview`

```
prune_<name>_preview <id>
```

Print a human-readable preview of one session. Called with a single `<id>`
from the inventory output. Must be **safe with bogus or malformed IDs** —
print a `(not found)` line and exit 0 rather than crashing. Defense against
SQL injection: validate `<id>` against your harness's known shape (e.g.
`^[A-Za-z0-9_\-]+$`) before interpolating into queries.

Recommended preview content:
- A short metadata header (id, cwd, timestamps, message count, model).
- The first user message (truncated to ~25 lines).
- The last assistant message.

### `prune_<name>_delete`

```
prune_<name>_delete <id> [<id> ...]
```

Delete the given session ids. Stdout for progress (one line per id is fine).
Stderr for errors. Exit 0 if every id was removed, 1 if any failed.

The core has already shown the user a confirmation dialog before this
function runs, so no further prompts inside `prune_<name>_delete`.

For SQLite-backed harnesses, do the work inside a single transaction; this
keeps the DB consistent on failure mid-way. Run `PRAGMA wal_checkpoint(TRUNCATE)`
afterward so the WAL doesn't grow indefinitely.

## Optional function

### `prune_<name>_doctor`

```
prune_<name>_doctor
```

Pre-flight check. Exit 0 if the harness is usable on this machine (storage
present, dependencies installed). Exit 1 with a stderr message if not. The
top-level `prune doctor` aggregates these.

If you don't define `_doctor`, the core falls back to `command -v <name>`.

## Storage path conventions

Make storage paths overridable via environment variables so that tests and
sandboxes can point the adapter at fixtures:

```bash
PRUNE_FOO_DB="${PRUNE_FOO_DB:-$HOME/.local/share/foo/sessions.db}"
```

By convention: `PRUNE_<NAME>_DB` for SQLite-backed adapters,
`PRUNE_<NAME>_SESSIONS_DIR` for filesystem-backed ones.

## Bash-portability rules (these matter for CI and macOS)

- Shebang any helper scripts with `#!/usr/bin/env bash`. Don't use `sh`.
- Don't use zsh-only constructs: `${(f)…}`, `${(j:|:)…}`, `<->[dhm]`,
  `print -P "%F{...}…"`, `${arg[-1]}`. The core provides bash equivalents.
- Don't use a local variable named `path` — zsh ties `path` to `$PATH`
  (typeset -T) and your function will silently break PATH inside its scope.
  Use `file_path`, `target`, or `sid` instead.
- Don't pipe `cmd | python3 - <<'PY'`. The pipe overrides the heredoc and
  python interprets the upstream stdout as its own script source (you'll see
  `NameError: name 'false' is not defined`). Either use `python3 -c '...'`
  with the script as an argument, or invoke `cmd` from inside python via
  `subprocess.run(...)`.

## Tests

Each adapter must ship a `tests/test_<name>.sh` that:
1. Sets storage to a fixture under `tests/fixtures/<name>/`.
2. Asserts inventory shape (number of rows, column count, ordering).
3. Asserts preview output for both valid and bogus ids.
4. Asserts the `here` filter via `_prune_filter_inventory`.
5. Asserts that `delete` actually removes the session AND its dependents.

For SQLite fixtures, check in only the `.sql` schema (with INSERT statements
for sample rows). The build script `tests/fixtures/build.sh` materializes the
`.db` file at test time. This avoids binary files in git.

## Worked example

`adapters/pi.sh` is the canonical example for filesystem-walk adapters.
`adapters/goose.sh` and `adapters/opencode.sh` are the SQLite examples.
`adapters/forge.sh` is the example with embedded XML-in-JSONB columns. Read
the one closest to your harness's storage model.
