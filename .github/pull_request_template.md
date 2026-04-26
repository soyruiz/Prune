<!--
Thanks for the PR. Fill in the sections below; remove any that don't apply.
-->

## Summary

<!-- 1-3 sentences. What does this PR change and why? -->

## Type of change

- [ ] Bug fix
- [ ] New feature (no breaking change)
- [ ] Breaking change
- [ ] New adapter
- [ ] Documentation only
- [ ] Refactor / chore (no behavior change)

## Adapter affected (if applicable)

<!-- pi / goose / opencode / forge / core / install / docs -->

## Tested against

<!-- For adapter PRs: which version(s) of the upstream harness did you test? -->
- [ ] Local: `<harness> --version` =
- [ ] CI passes (shellcheck + tests)
- [ ] Manual smoke: `prune <harness> --dry-run all` against real data

## Checklist

- [ ] `./tests/run.sh` passes locally
- [ ] `shellcheck --severity=warning --shell=bash <changed-files>` passes
- [ ] If adding an adapter: contract docs in `docs/ADAPTERS.md` are still accurate
- [ ] If changing behavior: `CHANGELOG.md` updated under `[Unreleased]`

## Notes / screenshots

<!-- Optional. Useful for visual changes (paste an asciicast or GIF). -->
