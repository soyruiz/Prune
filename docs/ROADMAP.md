# Prune — improvement roadmap (post-v0.1.0)

> Audience: maintainers, contributors, and AI coding agents iterating on the
> tool. Format: PRD — context first, then a tiered list of features with
> rationale + technical sketch + effort estimate.

## Context

Prune v0.1.0 covers four AI coding-agent CLIs (Pi, Goose, opencode, Forge)
with four bulk-delete modes (interactive picker, `all`, `<N>{d,h,m}`, `here`)
and an idempotent installer.

The reason the tool works today is **radical simplicity**: the entire mental
model fits in one sentence — *"type `prune <harness>` or one of its bulk
modes."* That simplicity is the value proposition. **If a new feature forces
the user to read docs before using it, we've failed.**

This roadmap lists the next set of improvements that respect that principle
while delivering disproportionate impact relative to effort. Every candidate
feature must pass four filters, in order:

1. **Does not change default behavior.** Activates explicitly (flag, mode) or
   is invisible (tab completion).
2. **Fits the existing mental model** (`prune <harness> <mode|flag>`). New
   verbs are added only when the value clearly justifies the friction.
3. **Works for all four adapters** or lives in `lib/core.sh`. No
   per-harness reimplementations of cross-cutting concerns.
4. **Implementable in one sitting** (≤1 day, ideally ≤2h). Anything bigger
   moves to Tier C / v0.2.

---

## Design principles (carryover)

- **Single mental model**: `prune <harness>` opens a picker; `prune <harness>
  <mode>` runs a bulk action. New features = new modes/flags within that
  pattern, **not** new structures.
- **Read-only by default, destructive on confirmation.** Adding `--dry-run`
  to any new mode must remain trivial.
- **Stable adapter contract.** The three required functions remain
  `inventory / preview / delete`. Any core feature consumes only the
  `inventory` output. Column 5 (`messages`) is part of the contract and we
  exploit it for filters.
- **No state outside the harness.** No proprietary databases, no config
  files, no persistent "favorites" — each one is UX cost.

---

## Roadmap

### Tier A — Highest ROI, ≤1h each, zero UX change

#### A1. Tab completion (bash + zsh)

**What.** Pressing Tab after `prune` autocompletes the available harnesses;
after `prune <harness>` autocompletes modes (`all`, `here`, `--dry-run`,
`--keep`, `last`, `empty`).

**Why.** Invisible until the user presses Tab → pure upside, zero UX cost.
Speeds up day-to-day use and surfaces the available options without forcing
anyone to read `--help`.

**How.** Two static files:
- `completions/prune.bash` — invoked via `complete -F`.
- `completions/_prune.zsh` — `compdef` format.

Hardcoded lists: harnesses (`pi goose opencode forge`), modes (`all here last
empty doctor`), flags (`--dry-run --keep --json --help --version`).

**Cross-harness.** Identical for all four. The harness list is built at
runtime from `adapters/*.sh` so adding a new adapter doesn't break
completion.

**Install.** `install.sh` copies the files to:
- bash: `$XDG_DATA_HOME/bash-completion/completions/prune`
- zsh: `$XDG_DATA_HOME/zsh/site-functions/_prune` (and add that path to
  `FPATH` from the idempotent marker block, so users with non-standard
  setups still get completion).

**Effort.** ~1h.

#### A2. `prune <harness> last`

**What.** Delete only the most recent session of the harness, with the same
confirmation as any destructive mode.

**Why.** The 80% case: *"I just opened a session by mistake, I want it gone
right now."* Today this requires opening the picker, navigating to the first
item, Tab, Enter, No/Yes. With `last` it's one command.

**How.** New case in `_prune_run_mode` (in `lib/core.sh`):

```bash
last)
    mapfile -t ids < <(printf '%s\n' "$inventory" | head -1 | cut -f1)
    desc="(most recent)"
    ;;
```

The inventory already comes sorted descending by `updated`.

**Cross-harness.** Trivial: uses only column 1 of the contract.

**Effort.** ~15 min + tests.

#### A3. `prune <harness> empty`

**What.** Delete sessions with `messages == 0`.

**Why.** This is literally what motivated the project: *"99% of my sessions
add nothing."* Sessions with zero messages are the ones the user opened and
closed without actually working. Very safe (nothing of value to lose) and
very frequent.

**How.** New case in `_prune_run_mode`:

```bash
empty)
    mapfile -t ids < <(printf '%s\n' "$inventory" | awk -F'\t' '$5==0 {print $1}')
    desc="with 0 messages"
    ;;
```

**Cross-harness.** Column 5 (`messages`) is required by the contract. All
four adapters already populate it (verified in their test suites).

**Effort.** ~15 min + tests.

#### A4. `prune <harness> --keep N`

**What.** Delete every session EXCEPT the N most recent.

**Why.** Classic housekeeping pattern: *"keep the latest 20, purge the
rest."* Today the user has to eyeball it with `<N>{d,h,m}`.

**How.** New flag, not a new mode. Any invocation that includes `--keep N`
filters the inventory to drop the first N rows:

```bash
keep_arg=20  # parsed from --keep
mapfile -t ids < <(printf '%s\n' "$inventory" | awk -F'\t' -v n="$keep_arg" 'NR>n {print $1}')
```

Composable with existing modes: `prune pi --keep 20` means "delete all but
the 20 most recent"; `prune pi here --keep 5` means "of the sessions in this
cwd, keep the 5 most recent."

**Cross-harness.** Reads only column 1 + the contract's existing ordering
guarantee.

**Effort.** ~30 min + tests.

---

### Tier B — Strong, agent-friendly, 1-2h each

#### B1. `prune <harness> --json`

**What.** Replace the fzf picker with a JSON dump of the inventory to
stdout. Stable, documented schema for programmatic parsing.

**Why.** Enables scripting (`prune goose --json | jq '...'`) and use by
other AI agents without parsing the picker's tabular format. **Does not
affect default UX** — only activates with the flag.

**How.** Inside `_prune_run_mode`, before invoking the picker or filters,
when `json=1`:

```bash
printf '%s\n' "$inventory" | python3 -c '
import sys, json
keys = ["id","title","directory","updated","messages","extra1","extra2"]
out = []
for line in sys.stdin:
    fields = line.rstrip("\n").split("\t")
    out.append({k: fields[i] if i < len(fields) else None for i,k in enumerate(keys)})
json.dump(out, sys.stdout, indent=2)
'
```

**Cross-harness.** Universal — operates on the common contract.

**Effort.** ~1h with docs + tests + an example in AGENTS.md.

#### B2. `prune <harness> show <id>`

**What.** Print one session's preview to stdout. Equivalent to what fzf's
preview pane already shows, but invocable from the command line.

**Why.** For AI agents and one-liners like `prune goose --json | jq -r
'.[].id' | xargs -n1 prune goose show`. Read-only, non-destructive.

**How.** New subcommand in `bin/prune` that calls `prune_<name>_preview
"$id"` directly.

**Cross-harness.** All four adapters already implement `_preview`.

**Effort.** ~30 min + tests.

#### B3. `prune <harness> info`

**What.** Print summary stats: total sessions, empty ones, with-messages
count, oldest/newest dates, and `extra1` aggregated when numeric (e.g.,
total tokens for goose). Read-only.

**Why.** Gives the user context before deciding what to purge — *"200
sessions, 175 empty, 2.3M tokens spent."* Also a nice candidate for
README screenshots.

**How.** New subcommand consuming the inventory:

```python
import sys
rows = [line.split('\t') for line in sys.stdin if line.strip()]
print(f"sessions: {len(rows)}")
print(f"empty:    {sum(1 for r in rows if r[4]=='0')}")
# tokens, etc., when extra1 is numeric...
```

**Cross-harness.** First five columns are universal. Optional extras
aggregated only when parseable as integers.

**Effort.** ~1h.

#### B4. macOS CI matrix

**What.** Add a `runs-on: macos-latest` job to the CI workflow. Force bash
5+ via `brew install bash` before tests.

**Why.** Today the README says "macOS supported" but we never verified it.
Green CI on macos-latest turns the promise into a fact and opens the door to
Mac users (a large CLI-tool audience).

**How.** Edit `.github/workflows/ci.yml`:

```yaml
test:
  strategy:
    matrix:
      os: [ubuntu-latest, macos-latest]
  runs-on: ${{ matrix.os }}
  steps:
    - uses: actions/checkout@v4
    - name: Install deps (macOS)
      if: runner.os == 'macOS'
      run: brew install fzf python sqlite gawk bash
    - name: Install deps (Linux)
      if: runner.os == 'Linux'
      run: sudo apt-get install -y fzf python3 sqlite3 gawk
    - run: ./tests/run.sh
```

**Cross-harness.** N/A — tests the core.

**Effort.** ~30-45 min (most of it is debugging the first mac run).

---

### Tier C — High value but complex, candidates for v0.2

#### C1. `prune undo` — restore the last destructive operation

**What.** A built-in trash. Before each `delete`, the adapter dumps affected
rows to `$XDG_STATE_HOME/prune/trash/<harness>/<timestamp>.json`. `prune
undo` reads the latest dump and re-injects rows / restores files.

**Why.** The safety net we still lack. Today `--dry-run` mitigates errors,
but anyone who runs `prune goose all` and regrets it has no way back. A
24h-TTL `undo` turns the tool from "scary" to "confident."

**Why Tier C.** Implementation is NOT uniform across adapters:
- pi (filesystem) → move to trash, restore = inverse mv. Trivial.
- goose / forge (sqlite) → save row JSON, INSERT on restore. Handle inverse
  FK CASCADE.
- opencode (own CLI) → `opencode import` exists but the format differs.
  Likely fall back to SQL.

Adds ~50-80 lines per adapter. **Not ≤1h** — it's 1-2 days done well with
tests. That's why it's deferred.

**Cross-harness UX.** Once shipped, `prune undo` is uniform — the user
doesn't need to know what's happening underneath.

**Effort.** 1-2 days.

#### C2. Snapshot log before bulk deletes

**What.** Lighter version of C1: just record **what** was deleted (id +
title + timestamp) into a JSONL log. No restore, but the user has a record.

**Why.** If C1 is too much, this is 30% of the value at 5% of the effort.
Most "oops, wrong session" cases are resolved knowing the id and looking it
up in the harness's own backups.

**How.** In `_prune_run_mode`, before `prune_<name>_delete`, append to
`$XDG_STATE_HOME/prune/history.jsonl`:

```json
{"ts":"2026-04-26T17:00:00Z","harness":"goose","mode":"all","ids":["20260423_25","..."],"count":3}
```

**Effort.** ~1h. If neither C1 nor C2 fit in v0.2, **at least C2 should ship
as Tier B+ in a v0.1.1 mini-iteration.**

---

### Tier D — Distribution (grows install base, orthogonal to features)

#### D1. Homebrew tap

**What.** Repo `soyruiz/homebrew-prune` with a formula `Formula/prune.rb`.
Enables `brew install soyruiz/prune/prune`.

**Why.** Roughly 30% of devs on Linux/macOS prefer brew over `curl|bash` or
git clone. Without a tap we lose that segment.

**How.** A GitHub Action in this repo that, on every release, publishes the
formula in the tap repo pointing at the release tarball. Standard template.

**Effort.** 2-3h initial setup; ~0 maintenance per release after that.

#### D2. Snap / AUR / Nix flakes

**Why.** Different distros have their canonical mechanisms. AUR for Arch
(`yay -S prune`), Nix flake for nixos. Marginal but positive.

**Why Tier D.** Only justifiable when there's real traction (>50 stars).
Premature before then.

**Effort.** 1-2h each.

---

## Non-goals (things this project will NOT do)

| Thing | Why not |
|---|---|
| Plugin system in TS / Python | Massive scope creep; bash + 3 functions works. |
| More sophisticated TUI | fzf IS the TUI. Reimplementing it is absurd. |
| Web UI | Same argument. |
| Persistent config (`~/.pruneconfig`) | Every persistent flag is UX cost. Env vars + ad-hoc flags are enough. |
| "Favorites" / pinned sessions | Extra state, cognitive noise — the opposite of "delete without thinking." |
| `--watch` / cron auto-purge | Too easy to delete something unintended without supervision. |
| i18n | CLI convention = English. |
| Anonymous metrics / telemetry | No. |

---

## Selection guidance — recommended execution order

If we run the roadmap, the recommended order by descending value and minimal
dependencies is:

1. **A1 + A2 + A3 + A4** all in a single PR — same file (`lib/core.sh`) +
   tests + completion files. ~3h total. This alone transforms the UX.
2. **C2** (snapshot log) in a separate PR — minimum safety net. ~1h. Builds
   confidence so users execute `prune all` without fear.
3. **B1 + B2** (`--json` + `show`) in a PR — enables scripting and use by AI
   agents. ~1.5h.
4. **B4** (macOS CI) in a small standalone PR. Closes the README's promise.
5. **B3** (`info`) when the first issue asks for it, not before.
6. **D1** (homebrew tap) once the project hits >25 stars (demand validated).
7. **C1** (real `undo`) in v0.2.

If only 2h are available: ship A1 + A2. Tab-driven picker + a one-shot
"delete the last session" covers ~90% of real use.

---

## Success metrics

Qualitative — we will not add telemetry:
- **Open issues** that say *"wish I could X"* where X is in this PRD.
- **External PRs** adding new adapters (signal that the contract is
  approachable).
- **Stars** as a discovery proxy (not value).
- **GIF clicks** on social — proxy for "engages on sight."

---

## Open questions

1. **`empty` definition.** `messages == 0` literally, or `0 user messages`?
   Today the contract counts ALL messages (assistant + user). For opencode,
   `message` rows include tool-calls. Recommendation: literal `messages ==
   0` for simplicity and predictability. Users who want finer control use
   `--json | jq`.
2. **`--keep N` composability.** Does `prune pi all --keep 20` make sense or
   is it contradictory? Recommendation: allow it. "all subject to `--keep`"
   means "everything except those N kept." Without `all`, `--keep N` only
   applies to sessions already in the active filter.
3. **C2 snapshot log location.** `$XDG_STATE_HOME/prune/` (proper XDG) or
   `$XDG_DATA_HOME/prune/trash/`? Recommendation: state — it's transient.
4. **Tab completion install path.** If `$XDG_DATA_HOME/zsh/site-functions/`
   isn't on the user's `FPATH` by default, completion won't load. Should we
   install to a guaranteed location (`~/.zsh/completions/`) and add it to
   `FPATH` from the idempotent marker block? Recommendation: yes.

---

## Files affected (for implementation)

When the roadmap is executed, the following files are touched:

| Tier | Modified files | New files |
|---|---|---|
| A1 | `install.sh`, `uninstall.sh`, `tests/test_install.sh` | `completions/prune.bash`, `completions/_prune.zsh`, `tests/test_completions.sh` |
| A2 / A3 / A4 | `lib/core.sh`, `bin/prune` (parse `--keep`), 4× `tests/test_<adapter>.sh` (smoke), `AGENTS.md`, `README.md` | none |
| B1 | `lib/core.sh`, `AGENTS.md`, `tests/test_core.sh` | none |
| B2 / B3 | `bin/prune`, `tests/test_*.sh` | none |
| B4 | `.github/workflows/ci.yml` | none |
| C2 | `lib/core.sh`, `bin/prune`, `tests/test_core.sh` | none |
| C1 | 4× `adapters/*.sh`, `lib/core.sh`, heavy fixtures + tests | `lib/trash.sh` (likely) |
| D1 | none (in this repo) | new repo `homebrew-prune` |
