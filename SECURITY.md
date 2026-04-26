# Security policy

## Supported versions

Prune is in early development. Security fixes are applied to the latest
released minor on `main`.

| Version | Supported |
|---------|-----------|
| 0.1.x   | ✅ |
| < 0.1.0 | ❌ (pre-release) |

## Reporting a vulnerability

Please **do not** open a public issue for security-sensitive reports.

Instead:

1. Use GitHub's [private security advisory](https://github.com/soyruiz/Prune/security/advisories/new) flow, **or**
2. Email the maintainer at the address listed on https://github.com/soyruiz.

Include:
- Affected version (`prune --version`).
- Adapter affected, if any.
- A reproduction or proof-of-concept (private to you and the maintainer).
- Suggested mitigation, if you have one.

You can expect:
- An acknowledgement within 72 hours.
- A fix or mitigation plan within 7 days for high-severity issues, longer for
  lower-severity reports.
- Public disclosure once a patch is released, with credit to the reporter
  unless you prefer to remain anonymous.

## Threat model

Prune is a local CLI that:
- Reads session metadata from harness-managed SQLite databases and JSONL
  files.
- Deletes sessions via either the upstream CLI or direct SQL.
- Never sends data over the network and has no daemon component.

Realistic risks Prune cares about:
- **Path / SQL injection via session ids** — adapters validate ids against a
  conservative `^[A-Za-z0-9_\-]+$` regex before interpolating into queries.
- **Accidental data loss from running against the wrong DB** — the
  `--dry-run` flag and the `prune doctor` pre-check exist for this.
- **Race with a live harness writing to its DB** — out of scope for the CLI;
  the README and AGENTS.md document the recommendation to quit the harness
  TUI before a bulk delete.

Out of scope:
- Local code execution by an attacker who already has shell access (Prune is
  bash; everything is observable in `bin/prune`).
- Tampering with the upstream harness's binaries.
