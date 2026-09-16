#!/usr/bin/env bash
# Exercise the hooks in .githooks/ against a throwaway repo. Run: scripts/test-hooks.sh
set -uo pipefail

hooks=$(cd "$(dirname "$0")/../.githooks" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

passed=0 failed=0

check() { # check <expect: pass|fail> <description> <command...>
  local expect=$1 desc=$2 actual
  shift 2
  if "$@" >/dev/null 2>&1; then actual=pass; else actual=fail; fi
  if [[ $actual == "$expect" ]]; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    printf '✗ expected %s, got %s: %s\n' "$expect" "$actual" "$desc"
  fi
}

# --- commit-msg -------------------------------------------------------------

msg() {
  printf '%b' "$1" >"$tmp/MSG"
  "$hooks/commit-msg" "$tmp/MSG"
}

check pass "feat with scope" msg '✨ feat(zsh): add fzf keybindings'
check pass "no scope" msg '🔧 chore: configure agent skills'
check pass "emoji with variation selector" msg '♻️ refactor(git): tidy aliases'
check pass "emoji without variation selector" msg '♻ refactor(git): tidy aliases'
check pass "breaking change" msg '💥 feat(install)!: switch from symlinks to stow'
check pass "body after blank line" msg '🐛 fix(zsh): restore prompt\n\nStarship was loaded twice.\n\nCloses #3'
check pass "git comments ignored" msg '📝 docs: explain install\n# Please enter the commit message'
check pass "merge commit" msg "Merge branch 'feat/1-x' into master"
check pass "fixup commit" msg 'fixup! ✨ feat(zsh): add fzf keybindings'
check fail "no emoji" msg 'feat(zsh): add fzf keybindings'
check fail "wrong emoji for type" msg '🐛 feat(zsh): add fzf keybindings'
check fail "unknown type" msg '✨ feature(zsh): add fzf keybindings'
check fail "uppercase subject" msg '✨ feat(zsh): Add fzf keybindings'
check fail "trailing period" msg '✨ feat(zsh): add fzf keybindings.'
check fail "uppercase scope" msg '✨ feat(ZSH): add fzf keybindings'
check fail "missing space after colon" msg '✨ feat(zsh):add fzf keybindings'
check fail "breaking without 💥" msg '✨ feat(install)!: switch to stow'
check fail "💥 without !" msg '💥 feat(install): switch to stow'
check pass "first line exactly 72 chars" msg "✨ feat(zsh): $(printf 'a%.0s' {1..59})"
check fail "first line 73 chars" msg "✨ feat(zsh): $(printf 'a%.0s' {1..60})"
check fail "no blank line before body" msg '✨ feat(zsh): add keybindings\nmore detail'
check fail "Claude co-author trailer" msg '✨ feat(zsh): add keybindings\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>'
check fail "Claude Code footer" msg '✨ feat(zsh): add keybindings\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)'

# --- pre-push ---------------------------------------------------------------

sha=1111111111111111111111111111111111111111
zero=0000000000000000000000000000000000000000
push() { printf 'refs/heads/x %s %s %s\n' "$2" "$1" "$zero" | "$hooks/pre-push" origin url; }

check pass "branch with issue" push refs/heads/feat/12-zsh-fzf-keybindings "$sha"
check pass "branch without issue" push refs/heads/chore/agent-setup "$sha"
check pass "tag" push refs/tags/v1.0.0 "$sha"
check pass "deleting an oddly named branch" push refs/heads/old-stuff "$zero"
check fail "push to master" push refs/heads/master "$sha"
check fail "delete master" push refs/heads/master "$zero"
check fail "no type prefix" push refs/heads/zsh-fzf "$sha"
check fail "unknown type" push refs/heads/feature/12-zsh "$sha"
check fail "uppercase slug" push refs/heads/feat/12-Zsh "$sha"
check fail "underscore in slug" push refs/heads/feat/zsh_fzf "$sha"

# --- pre-commit -------------------------------------------------------------

repo=$tmp/repo
git init -q -b master "$repo"
git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init

stage() { # stage <path> <content>: reset the index, then stage one file
  git -C "$repo" rm -rq --cached . >/dev/null 2>&1 || true
  mkdir -p "$(dirname "$repo/$1")"
  printf '%s\n' "$2" >"$repo/$1"
  git -C "$repo" add -f "$1"
}
precommit() { stage "$1" "$2" && (cd "$repo" && "$hooks/pre-commit"); }

check fail "commit on master" precommit zshrc 'alias ll="ls -la"'
git -C "$repo" switch -q -c feat/1-test

# Build fake secrets at runtime so this file doesn't trip the scanner itself.
gh_token="gh""p_$(printf 'a%.0s' {1..36})"
key_header="-----BEGIN OPENSSH PRIV""ATE KEY-----"
aws_key="AK""IAABCDEFGHIJKLMNOP"

check pass "clean file" precommit zsh/zshrc 'alias ll="ls -la"'
check pass "public key" precommit ssh/id_ed25519.pub 'ssh-ed25519 AAAA test'
check pass "env example" precommit .env.example 'TOKEN='
check pass "npm token from env var" precommit npmrc "//registry.npmjs.org/:_auth""Token=\${NPM_TOKEN}"
check pass "allowlisted line" precommit zsh/exports "export GH_TOKEN=$gh_token # gitleaks:allow"
check fail "GitHub token" precommit zsh/exports "export GH_TOKEN=$gh_token"
check fail "private key" precommit ssh/key "$key_header"
check fail "AWS key" precommit aws/config "aws_access_key_id = $aws_key"
check fail "hardcoded npm token" precommit npmrc "//registry.npmjs.org/:_auth""Token=abc123"
check fail ".netrc file" precommit .netrc 'machine example.com'
check fail "private key file" precommit ssh/id_ed25519 'not really a key'
check fail ".env file" precommit .env 'FOO=bar'

printf '%d passed, %d failed\n' "$passed" "$failed"
((failed == 0))
