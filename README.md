```
██████╗ ██████╗ ██╗   ██╗███╗   ██╗███████╗
██╔══██╗██╔══██╗██║   ██║████╗  ██║██╔════╝
██████╔╝██████╔╝██║   ██║██╔██╗ ██║█████╗  
██╔═══╝ ██╔══██╗██║   ██║██║╚██╗██║██╔══╝  
██║     ██║  ██║╚██████╔╝██║ ╚████║███████╗
╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝
```

> Bulk-delete stored sessions from AI coding-agent CLIs — with the fzf picker
> UX you'd actually use.

![Prune demo](assets/demo.gif)

`Prune` gives you one consistent way to wipe accumulated sessions across
several agent harnesses (Pi, Goose, opencode, Forge), via an fzf picker with
preview, plus mass-delete shortcuts.

```text
                                     prune pi ❯
  Tab=select  Enter=delete  Esc=cancel

  ID                          TITLE                                              UPDATED           MSGS  CWD
> 019dbc1d-63da-75f1-…         antes interrumpí una sesión, ¿hay un script…       2026-04-25 21:43    22  /home/noname
  019dbc0e-eda7-716a-…         (untitled)                                         2026-04-23 22:36     8  /home/noname/.pi
  019d9b6f-5626-71af-…         dame un mapa rápido de la arquitectura            2026-04-17 12:34    41  /home/noname/Proyectos/Agentic RAG
  019d9b6f-5623-77a9-…         tests fixture nested layout                        2026-04-17 12:34     6  /home/noname/Proyectos/Agentic RAG
  …
                                                              ┌───────────────────────────────────────────┐
                                                              │ id:        019dbc1d-63da-75f1-…           │
                                                              │ cwd:       /home/noname                   │
                                                              │ updated:   2026-04-25 21:43:51            │
                                                              │ messages:  22                              │
                                                              │                                            │
                                                              │ --- first user message ---                 │
                                                              │ antes interrumpí una sesión, ¿hay un      │
                                                              │ script de bifrost a medias por aquí?       │
                                                              │ ...                                        │
                                                              └───────────────────────────────────────────┘
```

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/soyruiz/Prune/main/install.sh | bash
```

Or clone first if you prefer to read the script:

```bash
git clone https://github.com/soyruiz/Prune ~/Proyectos/Prune
cd ~/Proyectos/Prune
./install.sh
```

After install, open a new shell (or `source ~/.zshrc`) and run:

```bash
prune doctor
```

## Use

```text
prune                     summary: which harnesses are installed + session counts
prune <harness>           interactive fzf picker (multi-select with Tab)
prune <harness> all       delete EVERY session (with confirmation)
prune <harness> 30d       delete sessions older than 30 days (units: d, h, m)
prune <harness> here      delete sessions opened in the current directory
prune <harness> --dry-run lists targets without deleting
prune doctor              checks dependencies + per-adapter status
```

Backward-compat wrappers: `pi-prune`, `goose-prune`, `opencode-prune`,
`forge-prune` are equivalent to `prune <harness>`.

## Supported harnesses

| Harness | Storage | Status |
|---------|---------|--------|
| [Pi](https://github.com/badlogic/pi-mono) | `~/.pi/agent/sessions/**/*.jsonl` | tested 0.70.x, 0.71.x |
| [Goose](https://github.com/aaif-goose/goose) | `~/.local/share/goose/sessions/sessions.db` | tested 1.10–1.31 |
| [opencode](https://github.com/sst/opencode) | `~/.local/share/opencode/opencode.db` | tested 1.14.25 |
| Forge (proprietary) | `~/.forge/.forge.db` | best-effort |

Adding a new harness is a 50–80 line bash file implementing three functions —
see [docs/ADAPTERS.md](docs/ADAPTERS.md).

## Why not just `rm` the files?

Each harness stores sessions differently — some in JSONL files in nested
directories, others in SQLite databases with foreign-key relationships across
several tables. A naive `rm` leaves orphan messages, breaks WAL consistency,
or misses entire chunks of data. Prune handles each case correctly.

It's also faster than each harness's built-in delete UI: one fzf picker, all
your sessions across all projects, multi-select, dry-run.

## Requirements

- bash >= 4 (macOS default is 3.2 — `brew install bash`)
- fzf, python3, awk, date
- sqlite3 (only for goose/opencode/forge adapters)
- Linux or macOS

## Status

**v0.1.0 — alpha.** Core API is stable; storage formats of the upstream
harnesses are not, so adapters may need updates as those evolve. Open an
issue if you see drift.

## Documentation

- [AGENTS.md](AGENTS.md) — install/use reference for AI coding agents (deterministic, copy-pasteable).
- [docs/ADAPTERS.md](docs/ADAPTERS.md) — adapter contract + how to add a new harness.
- [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md) — tested versions per harness.
- [CHANGELOG.md](CHANGELOG.md) — release history.
- [CONTRIBUTING.md](CONTRIBUTING.md) — how to run tests + open a PR.

## Acknowledgements

The picker UX was inspired by Forge's original `:prune` action. Thanks to
the maintainers of [fzf](https://github.com/junegunn/fzf), and to the teams
behind Pi, Goose, and opencode.

## License

MIT — see [LICENSE](LICENSE).
