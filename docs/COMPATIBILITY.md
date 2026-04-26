# Compatibility matrix

Versions of each upstream harness validated against Prune. If your version
isn't listed and Prune misbehaves, please open an issue with `prune doctor`
output and your harness's `--version`.

## Pi

| Version | Status | Notes |
|---------|--------|-------|
| 0.70.x | ✅ tested | Both flat (`<cwd>/<ts>_<uuid>.jsonl`) and nested (`<cwd>/<top>/<sub>/run-N/<jsonl>`) layouts handled |
| 0.71.x | ✅ tested | |

Storage path: `~/.pi/agent/sessions/`.

Override: `PRUNE_PI_SESSIONS_DIR=/custom/path prune pi`.

## Goose

| Version | Status | Notes |
|---------|--------|-------|
| 1.10–1.30 | ✅ tested | Pre-`/dev/tty` confirm |
| 1.31+ | ✅ tested | `goose session remove` reads confirm from `/dev/tty` — Prune uses direct SQL DELETE inside a transaction to bypass |

Storage path: `~/.local/share/goose/sessions/sessions.db`.

Override: `PRUNE_GOOSE_DB=/custom/sessions.db prune goose`.

Schema: tables `sessions`, `messages` (FK on `session_id`), `thread_messages`.
The adapter deletes from all three in one transaction and runs
`PRAGMA wal_checkpoint(TRUNCATE)` to reclaim WAL space.

## opencode

| Version | Status | Notes |
|---------|--------|-------|
| 1.14.25 | ✅ tested | `opencode session list` filters by `project_id = "global"` and hides sessions from project subdirs; Prune queries the DB directly to surface ALL top-level sessions |

Storage path: `~/.local/share/opencode/opencode.db`.

Override: `PRUNE_OPENCODE_DB=/custom/opencode.db prune opencode`.

Schema: `session`, `message`, `part` with `ON DELETE CASCADE` foreign keys.
The adapter deletes via `opencode session delete <id>` when the official CLI
is available on the default DB path; otherwise it falls back to SQL with
`PRAGMA foreign_keys=ON` so the cascade triggers.

## Forge (proprietary)

| Version | Status | Notes |
|---------|--------|-------|
| local install | ⚠ best-effort | Tested against the maintainer's local install; no public version pinning. Adapter handles "orphan" rows (NULL `context`) that Forge's own `forge conversation delete` may fail on |

Storage path: `~/.forge/.forge.db`.

Override: `PRUNE_FORGE_DB=/custom/.forge.db prune forge`.

Schema: single `conversations` table with id, title, workspace_id, context
(XML-ish blob containing `<current_working_directory>` + inline message
tags), and timestamps. The adapter deletes via SQL only — no Forge CLI is
required.

## Reporting drift

If you upgrade a harness and Prune stops working, please:

1. Run `prune doctor` and copy the output.
2. Run `<harness> --version` and note it.
3. Run `prune <harness> --dry-run all` and note any error.
4. Open an issue at https://github.com/soyruiz/Prune/issues with the above.

When possible, contributors should add a fixture under
`tests/fixtures/<harness>/` reproducing the new schema. See
[docs/ADAPTERS.md](ADAPTERS.md) for fixture conventions.
