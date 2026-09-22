#!/usr/bin/env bash
# Bootstrap fresh Machines in a throwaway container and check the result.
# Run: scripts/test-bootstrap.sh [debian|arch] (needs Docker). Tests the working tree, committed or not.
#
#   debian  a Managed Machine
#   arch    a Workstation (the EndeavourOS Workstation's configs, not its packages)
#
# Runs in three stages: outside Docker it starts the container; in the container,
# as root, it installs what any Machine has (git, curl) and adds a user; as that
# user it runs the checks, each scenario in its own fresh home directory.
set -uo pipefail

user=tester
distro=${1:-debian}

case $distro in
  debian | arch)
    repo=$(cd "$(dirname "$0")/.." && pwd)
    platform_flag=
    case $distro in
      debian) image=debian:stable-slim kind=managed ;;
      arch) image=archlinux:base kind=workstation platform_flag=--platform=linux/amd64 ;; # Arch images are amd64 only
    esac
    exec docker run --rm ${platform_flag:+"$platform_flag"} -v "$repo:/src:ro" "$image" \
      bash /src/scripts/test-bootstrap.sh --setup "$distro" "$kind"
    ;;
  --setup)
    case $2 in
      debian)
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq >/dev/null && apt-get install -y -qq git curl ca-certificates >/dev/null || exit 1
        ;;
      arch)
        # The download sandbox fails under amd64 emulation (Apple Silicon); nothing to protect here.
        pacman -Sy --noconfirm --needed --quiet --disable-sandbox git curl >/dev/null || exit 1
        ;;
      *) exit 2 ;;
    esac
    useradd --create-home "$user"
    exec runuser -u "$user" -- bash /src/scripts/test-bootstrap.sh --checks "$3"
    ;;
  --checks) kind=$2 ;;
  *) echo "usage: $0 [debian|arch]" >&2 && exit 2 ;;
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

# --- Run from a clone ------------------------------------------------------

fresh_machine
clone_to "$HOME/.dotfiles"

check pass "bootstrap from the clone" env DOTFILES_KIND="$kind" "$HOME/.dotfiles/bootstrap.sh"
PATH=$HOME/.local/bin:$PATH # later scenarios reuse this chezmoi instead of downloading it again

check pass "chezmoi installed without root" test -x "$HOME/.local/bin/chezmoi"
check pass "git config is a symlink into the clone" linked .gitconfig
check pass "git ignore is a symlink into the clone" linked .config/git/ignore
check pass "git reads the tracked config" is "$(git config --global init.defaultBranch)" master
check pass "chezmoi has nothing to apply" chezmoi verify
check pass "clone's hooks path points at its hooks" is "$(git -C "$HOME/.dotfiles" config core.hooksPath)" .githooks
check pass "Machine kind recorded" is "$(chezmoi execute-template '{{ .kind }}')" "$kind"
check fail "tracked git config names no client folder" grep -qi includeif "$HOME/.gitconfig"
check fail "tracked git config holds no identity" git config --file "$HOME/.gitconfig" --get-regexp "^user\\."
# Split so this file doesn't match its own scan of the clone.
secret_var=MAVEN_PUBLICATION"_PASSWORD"
check fail "no Secret anywhere in the clone" grep -rq "$secret_var" "$HOME/.dotfiles"

# Workstation-only Tracked configs: the zsh startup files assume a Workstation.
if [[ $kind == workstation ]]; then
  for startup_file in .zshrc .zprofile .zshenv .zlogin; do
    check pass "$startup_file is a symlink into the clone" linked "$startup_file"
  done
  check fail "tracked zprofile holds no Secret" grep -q "$secret_var" "$HOME/.zprofile"
  check pass "zprofile loads its Local override" grep -q "[.]zprofile[.]local" "$HOME/.zprofile"
  check pass "zshrc loads its Local override" grep -q "[.]zshrc[.]local" "$HOME/.zshrc"
else
  check fail "Managed Machines get no zshrc" test -e "$HOME/.zshrc"
  check fail "Managed Machines get no zprofile" test -e "$HOME/.zprofile"
fi

before=$(snapshot)
check pass "second run needs no answers" bootstrap
check pass "second run changes nothing" is "$(snapshot)" "$before"

printf '[user]\n\temail = client@example.com\n' >"$HOME/.gitconfig.local"
check pass "Local override is loaded" is "$(git -C "$HOME" config user.email)" client@example.com

# --- Piped from a URL ------------------------------------------------------

origin=$tmp/origin
cp -a /src "$origin"
git -C "$origin" add -A
git -C "$origin" -c user.name=t -c user.email=t@t -c core.hooksPath=/dev/null commit -qm test --allow-empty

fresh_machine
piped() { DOTFILES_REPO=$origin DOTFILES_KIND=$kind timeout 120 bash <"$origin/bootstrap.sh"; }

check pass "bootstrap piped into bash" piped
check pass "repo cloned to ~/.dotfiles" test -f "$HOME/.dotfiles/.chezmoiroot"
check pass "git config is a symlink into the clone" linked .gitconfig
check pass "chezmoi has nothing to apply" chezmoi verify
check pass "clone's hooks path points at its hooks" is "$(git -C "$HOME/.dotfiles" config core.hooksPath)" .githooks
check pass "Machine kind recorded" is "$(chezmoi execute-template '{{ .kind }}')" "$kind"
check pass "piping again reuses the clone" piped

# --- A config chezmoi didn't create ----------------------------------------

fresh_machine
clone_to "$HOME/.dotfiles"
printf '[user]\n\tname = Someone Else\n' >"$HOME/.gitconfig"
existing=$(cat "$HOME/.gitconfig")

check fail "bootstrap stops" env DOTFILES_KIND="$kind" "$HOME/.dotfiles/bootstrap.sh"
check pass "it names the file" grep -q "$HOME/.gitconfig" "$tmp/last"
check pass "existing config is untouched" is "$(cat "$HOME/.gitconfig")" "$existing"
check fail "existing config not replaced by a symlink" test -L "$HOME/.gitconfig"
check fail "nothing else applied" test -e "$HOME/.config/git/ignore"

# --- Clone somewhere else --------------------------------------------------

fresh_machine
clone_to "$HOME/src/dotfiles"

check fail "bootstrap refuses a clone outside ~/.dotfiles" env DOTFILES_KIND="$kind" "$HOME/src/dotfiles/bootstrap.sh"
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
