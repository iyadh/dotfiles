## Agent skills

### GitHub

Anything that touches GitHub rather than the git repository goes through the `gh` CLI: issues, pull requests, reviews, labels, workflow runs, checks, releases, and whatever has no command of its own via `gh api`. Plain `git` still does the git half — commit, branch, push, rebase.

Don't reach for the web UI, and don't `curl` `api.github.com` by hand: `gh` already carries the authentication and knows the repo from the clone it runs in.

### Issue tracker

Issues live in GitHub Issues for iyadh/dotfiles, managed with the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Uses the five default labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.

### Git workflow

GitHub flow with squash merges; Conventional Commits with gitmoji (`✨ feat(zsh): add fzf keybindings`); no AI attribution in commits or PRs. See `docs/agents/git-workflow.md`.

Enforced by git hooks in `.githooks/`; after cloning, run `git config core.hooksPath .githooks`. Never use `--no-verify` unless the user asks.
