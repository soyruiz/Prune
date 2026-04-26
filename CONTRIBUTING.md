# Contributing to Prune

Thanks for your interest. Prune is intentionally small: one entrypoint, one
core library, one file per harness. The contribution loop is fast.

## Local setup

```bash
git clone https://github.com/soyruiz/Prune
cd Prune
./tests/run.sh        # all tests should pass
shellcheck bin/prune lib/*.sh adapters/*.sh install.sh uninstall.sh
```

Requirements: bash >= 4, fzf, python3, sqlite3, awk, date.

## Running tests

```bash
./tests/run.sh                    # all
./tests/run.sh test_core          # one file
./tests/run.sh test_pi test_goose # several
```

The fixtures script (`tests/fixtures/build.sh`) materializes SQLite databases
from checked-in `.sql` schemas. It runs automatically before the suite.

## Code style

- Bash-portable: see the bash-portability section in `docs/ADAPTERS.md`.
- `set -euo pipefail` at the top of every shell script.
- 4-space indentation, no tabs.
- shellcheck-clean (warning level): `shellcheck -s bash -S warning **/*.sh`.

## Adding a new harness

The fast path:
1. Read `docs/ADAPTERS.md` for the contract.
2. Read `adapters/pi.sh` (filesystem) or `adapters/goose.sh` (SQLite).
3. Create `adapters/<name>.sh` defining `prune_<name>_inventory`,
   `prune_<name>_preview`, `prune_<name>_delete` (and optionally `_doctor`).
4. Create `tests/fixtures/<name>/{schema.sql or sample files}`.
5. Create `tests/test_<name>.sh` covering inventory shape, preview safety,
   here filter, and a destructive delete on a tmp fixture.
6. Update `docs/COMPATIBILITY.md` and `README.md`.
7. `./tests/run.sh` must stay green.

## Pull requests

- One PR = one logical change (a new adapter, a bugfix, a doc update).
- Run shellcheck and the test suite locally before pushing.
- Update `CHANGELOG.md` under `[Unreleased]`.
- Tests are required for new behavior; tests are required to remain green.

## Reporting bugs

Use [GitHub Issues](https://github.com/soyruiz/Prune/issues) and include:

- `prune --version`
- `prune doctor`
- `<harness> --version` for the affected adapter
- Reproduction steps with `--dry-run` first to confirm the targets

## License

By contributing you agree your changes will be released under the project's
[MIT license](LICENSE).
