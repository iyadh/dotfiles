#!/usr/bin/env bash
# Bootstrap fresh Machines in a throwaway Debian container and check the result.
# Run: scripts/test-bootstrap.sh (needs Docker). Tests the working tree, committed or not.
#
# Runs in three stages: outside Docker it starts the container; in the container,
# as root, it installs what any Machine has (git, curl) and adds a user; as that
# user it runs the checks, each scenario in its own fresh home directory.
set -uo pipefail

user=tester

case ${1:-} in
  "")
    repo=$(cd "$(dirname "$0")/.." && pwd)
    exec docker run --rm -v "$repo:/src:ro" debian:stable-slim bash /src/scripts/test-bootstrap.sh --setup
    ;;
  --setup)
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null && apt-get install -y -qq git curl ca-certificates >/dev/null || exit 1
    useradd --create-home "$user"
    exec runuser -u "$user" -- bash /src/scripts/test-bootstrap.sh --checks
    ;;
  --checks) ;;
  *) echo "usage: $0" >&2 && exit 2 ;;
esac

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

passed=0 failed=0

check() { # check <expect: pass|fail> <description> <command...>
  local expect=$1 desc=$2 actual
  shift 2
  if "$@" >"$tmp/out" 2>&1; then actual=pass; else actual=fail; fi
  mv "$tmp/out" "$tmp/last" # the previous check's output, for checks about messages
  if [[ $actual == "$expect" ]]; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    printf '✗ expected %s, got %s: %s\n' "$expect" "$actual" "$desc"
    sed 's/^/    /' "$tmp/last"
  fi
}

# A Machine nobody has used: an empty home directory.
fresh_machine() {
  HOME=$(mktemp -d "$tmp/home.XXXX")
  export HOME
  cd "$HOME" || exit 1
}

# The working tree as a clone, without the hooks path so Bootstrap has to set it.
clone_to() {
  mkdir -p "$(dirname "$1")"
  cp -a /src "$1"
  git -C "$1" config --unset core.hooksPath || true
}

bootstrap() { timeout 120 "$HOME/.dotfiles/bootstrap.sh" </dev/null; }
linked() { [[ -L $HOME/$1 && $(readlink "$HOME/$1") == "$HOME/.dotfiles/"* ]]; }
is() { [[ $1 == "$2" ]]; }

# Everything in the home directory: type, mode, link target and content.
# chezmoi's state database is its own bookkeeping, rewritten on every run.
snapshot() {
  find "$HOME" -path "$HOME/.cache" -prune -o -not -name chezmoistate.boltdb -print0 |
    sort -z |
    while IFS= read -r -d '' path; do
      printf '%s %s %s' "$path" "$(stat -c '%F %a' "$path")" "$(readlink "$path")"
      [[ -f $path && ! -L $path ]] && sha256sum <"$path" | tr -d '\n'
      printf '\n'
    done
}

# --- Run from a clone, Managed Machine ------------------------------------

fresh_machine
clone_to "$HOME/.dotfiles"

check pass "bootstrap from the clone" env DOTFILES_KIND=managed "$HOME/.dotfiles/bootstrap.sh"
PATH=$HOME/.local/bin:$PATH # later scenarios reuse this chezmoi instead of downloading it again

check pass "chezmoi installed without root" test -x "$HOME/.local/bin/chezmoi"
check pass "git config is a symlink into the clone" linked .gitconfig
check pass "git ignore is a symlink into the clone" linked .config/git/ignore
check pass "git reads the tracked config" is "$(git config --global init.defaultBranch)" master
check pass "chezmoi has nothing to apply" chezmoi verify
check pass "clone's hooks path points at its hooks" is "$(git -C "$HOME/.dotfiles" config core.hooksPath)" .githooks
check pass "Machine kind recorded" is "$(chezmoi execute-template '{{ .kind }}')" managed
check fail "tracked git config names no client folder" grep -qi includeif "$HOME/.gitconfig"
check fail "tracked git config holds no identity" git config --file "$HOME/.gitconfig" --get-regexp "^user\\."

before=$(snapshot)
check pass "second run needs no answers" bootstrap
check pass "second run changes nothing" is "$(snapshot)" "$before"

printf '[user]\n\temail = client@example.com\n' >"$HOME/.gitconfig.local"
check pass "Local override is loaded" is "$(git -C "$HOME" config user.email)" client@example.com

# --- Piped from a URL, Workstation -----------------------------------------

origin=$tmp/origin
cp -a /src "$origin"
git -C "$origin" add -A
git -C "$origin" -c user.name=t -c user.email=t@t -c core.hooksPath=/dev/null commit -qm test --allow-empty

fresh_machine
piped() { DOTFILES_REPO=$origin DOTFILES_KIND=workstation timeout 120 bash <"$origin/bootstrap.sh"; }

check pass "bootstrap piped into bash" piped
check pass "repo cloned to ~/.dotfiles" test -f "$HOME/.dotfiles/.chezmoiroot"
check pass "git config is a symlink into the clone" linked .gitconfig
check pass "chezmoi has nothing to apply" chezmoi verify
check pass "clone's hooks path points at its hooks" is "$(git -C "$HOME/.dotfiles" config core.hooksPath)" .githooks
check pass "Machine kind recorded" is "$(chezmoi execute-template '{{ .kind }}')" workstation
check pass "piping again reuses the clone" piped

# --- A config chezmoi didn't create ----------------------------------------

fresh_machine
clone_to "$HOME/.dotfiles"
printf '[user]\n\tname = Someone Else\n' >"$HOME/.gitconfig"
existing=$(cat "$HOME/.gitconfig")

check fail "bootstrap stops" env DOTFILES_KIND=managed "$HOME/.dotfiles/bootstrap.sh"
check pass "it names the file" grep -q "$HOME/.gitconfig" "$tmp/last"
check pass "existing config is untouched" is "$(cat "$HOME/.gitconfig")" "$existing"
check fail "existing config not replaced by a symlink" test -L "$HOME/.gitconfig"
check fail "nothing else applied" test -e "$HOME/.config/git/ignore"

# --- Clone somewhere else --------------------------------------------------

fresh_machine
clone_to "$HOME/src/dotfiles"

check fail "bootstrap refuses a clone outside ~/.dotfiles" env DOTFILES_KIND=managed "$HOME/src/dotfiles/bootstrap.sh"
check fail "nothing applied" test -e "$HOME/.gitconfig"

# --- No way to ask the Machine kind ----------------------------------------

fresh_machine
clone_to "$HOME/.dotfiles"

check fail "bootstrap with no terminal and no DOTFILES_KIND" bootstrap
check pass "it says how to answer" grep -q DOTFILES_KIND "$tmp/last"
check fail "bootstrap with an unknown kind" env DOTFILES_KIND=laptop "$HOME/.dotfiles/bootstrap.sh"
check fail "nothing applied" test -e "$HOME/.gitconfig"

printf '%d passed, %d failed\n' "$passed" "$failed"
((failed == 0))
