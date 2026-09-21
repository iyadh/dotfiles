# Git workflow

## Branching: GitHub flow

- `master` is always in a working state. Never commit to it directly, never force-push it.
- Every change starts on a short-lived branch cut from an up-to-date `master`.
- Branch name: `<type>/<issue>-<slug>`, e.g. `feat/12-zsh-fzf-keybindings`. Use the commit types below. Omit `<issue>` only when no issue exists.
- One branch per issue. Keep it small enough to review in one sitting.
- Open a PR into `master`. The PR body links its issue with `Closes #<issue>`.
- Rebase the branch onto `master` to pick up changes; don't merge `master` into it.
- Delete the branch after merge.

## Merging: squash merge only

- Every PR lands on `master` as a single squashed commit.
- The **PR title becomes that commit's message**, so the PR title must follow the commit convention below.
- Commits on a branch should still follow the convention, but they are squashed away and may be less polished.

## Commit convention: Conventional Commits + gitmoji

```
<emoji> <type>(<scope>): <subject>

[optional body: what and why, wrapped at 72]

[optional footer: Closes #12, BREAKING CHANGE: ...]
```

Example: `✨ feat(zsh): add fzf keybindings`

- **Subject**: imperative mood, lowercase, no trailing period, 72 characters max for the whole first line.
- **Scope**: the tool or area touched: `zsh`, `git`, `brew`, `starship`, `alacritty`, `zed`, `macos`, `install`, `claude`, … Omit the scope only for repo-wide changes.
- **Breaking change** (something that needs manual action on an existing machine): add `!` after the scope and use 💥, e.g. `💥 feat(install)!: switch from symlinks to stow`, with a `BREAKING CHANGE:` footer explaining the migration.

| Type       | Emoji | Use for                                              |
| ---------- | ----- | ---------------------------------------------------- |
| `feat`     | ✨    | New config, tool, alias, function, or capability     |
| `fix`      | 🐛    | Something that was broken now works                  |
| `docs`     | 📝    | README, `CONTEXT.md`, ADRs, comments only            |
| `style`    | 🎨    | Formatting only, no behaviour change                 |
| `refactor` | ♻️    | Restructure without changing behaviour               |
| `perf`     | ⚡️    | Faster shell startup, lighter config                 |
| `test`     | ✅    | Tests or checks for the install scripts              |
| `build`    | 📦️    | Brewfile, package lists, dependencies                |
| `ci`       | 👷    | GitHub Actions and other automation                  |
| `chore`    | 🔧    | Repo maintenance that fits nothing above             |
| `revert`   | ⏪️    | Reverting a previous commit                          |

## Attribution

Do not add AI attribution to commits or PRs: no `Co-Authored-By: Claude` trailer, no "Generated with Claude Code" footer.

## Enforcement: git hooks

The hooks in `.githooks/` enforce this document locally. Turn them on once per clone:

```sh
git config core.hooksPath .githooks
```

| Hook         | Checks                                                                                   |
| ------------ | ---------------------------------------------------------------------------------------- |
| `commit-msg` | Commit format, emoji matches type, 72-char first line, blank line before body, no AI attribution |
| `pre-commit` | No commits on `master`; no staged secrets (sensitive filenames, token patterns, plus gitleaks when installed) |
| `pre-push`   | No pushes to `master`; branch name matches `<type>/<issue>-<slug>`                        |

- Mark a false-positive secret by adding `gitleaks:allow` to that line.
- Types, emoji, and the protected branch are defined once in `.githooks/lib.sh`. Change them there and in this document together.
- After changing a hook, run `scripts/test-hooks.sh` and `scripts/shellcheck.sh`.
- Never bypass the hooks with `--no-verify` unless the user explicitly asks.

On GitHub, `.github/workflows/conventions.yml` runs the same `commit-msg` hook against each PR's title and body (the future squash commit), checks the branch name, and runs `scripts/test-hooks.sh` and `scripts/shellcheck.sh`. The Bootstrap workflow runs `scripts/test-bootstrap.sh`. Branch protection on `master` requires a PR with passing checks, applies to admins, and the repo allows squash merges only.
