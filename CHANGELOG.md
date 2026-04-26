# Changelog

All notable changes to Prune will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] — 2026-04-26

Initial release.

### Added
- Unified `prune` CLI with subcommand-per-harness pattern.
- Adapters for four AI coding-agent CLIs:
  - **Pi** — JSONL session files under `~/.pi/agent/sessions/`.
  - **Goose** — SQLite at `~/.local/share/goose/sessions/sessions.db` (handles v1.31+ TTY-only confirm via direct SQL).
  - **opencode** — SQLite at `~/.local/share/opencode/opencode.db` via the official `opencode db` subcommand (queries across all projects, not just `global`).
  - **Forge** — SQLite at `~/.forge/.forge.db`.
- Four bulk-delete modes per adapter: interactive fzf picker, `all`, `<N>{d,h,m}` (older than), `here` (matching `$PWD`).
- Backward-compatible wrappers: `pi-prune`, `goose-prune`, `opencode-prune`, `forge-prune`.
- Idempotent `install.sh` and symmetric `uninstall.sh`.
- `prune doctor` runtime check for dependencies and per-adapter health.
- `--dry-run` for any deletion mode.
- Bash 4+ and zsh support.
- Test suite with SQLite/JSONL fixtures (no real harness installation required for CI).
- GitHub Actions CI: shellcheck + tests on push/PR.
