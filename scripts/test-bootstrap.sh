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
        apt-get update -qq >/dev/null && apt-get install -y -qq git curl ca-certificates zsh sudo >/dev/null || exit 1
        ;;
      arch)
        # The download sandbox fails under amd64 emulation (Apple Silicon); nothing to protect here.
        pacman -Sy --noconfirm --needed --quiet --disable-sandbox git curl zsh sudo >/dev/null || exit 1
        ;;
      *) exit 2 ;;
    esac
    useradd --create-home "$user"
    # A Managed Machine's owner can become root to install packages. Without a
    # terminal there is nobody to type a password, so make it passwordless.
    printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$user" >"/etc/sudoers.d/$user"
    chmod 440 "/etc/sudoers.d/$user"
    exec runuser -u "$user" -- bash /src/scripts/test-bootstrap.sh --checks "$3"
    ;;
  # A real terminal always says what it is, and tools like tput and starship
  # need to know. A container leaves TERM unset or "dumb", which is not the
  # terminal these checks are standing in for.
  --checks)
    kind=$2
    [[ ${TERM:-dumb} == dumb ]] && TERM=xterm-256color
    export TERM
    ;;
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

# A Machine nobody has used. Not an empty directory: a real new account is
# populated from /etc/skel, so it already carries the distribution's own
# .bashrc and friends. Bootstrap meets those on every fresh Linux Machine.
fresh_machine() {
  HOME=$(mktemp -d "$tmp/home.XXXX")
  export HOME
  [[ -d /etc/skel ]] && cp -a /etc/skel/. "$HOME/"
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

# Run a snippet in an interactive shell on a pseudo-terminal, the way a person
# would. Without a terminal bash complains about job control and zsh leaves out
# its line editor, so the checks below would be judging a shell nobody runs.
# The snippet's output and the shell's own stderr come back in separate files.
in_shell() { # in_shell <bash|zsh> <snippet>
  printf '%s\n' "$2" >"$tmp/snippet"
  : >"$tmp/shell-out"
  : >"$tmp/shell-err"
  timeout 300 script -qec \
    "$1 -i -c '. $tmp/snippet' >$tmp/shell-out 2>$tmp/shell-err" /dev/null \
    </dev/null >/dev/null 2>&1
}

# Startup has to be silent whatever is installed, or every session opens with
# noise. check reports this function's output, so a failure shows the noise.
starts_silently() { # starts_silently <bash|zsh>
  in_shell "$1" :
  [[ ! -s $tmp/shell-err ]] || { cat "$tmp/shell-err"; return 1; }
}

# What an interactive shell holds in a variable once it has started.
startup_var() { # startup_var <bash|zsh> <name>
  in_shell "$1" "printf %s \"\${$2-}\""
  cat "$tmp/shell-out"
}

# The PATH an interactive shell ends up with, one entry per line.
startup_path() { startup_var "$1" PATH | tr ':' '\n'; }

# starship reads its config on every prompt and reports a bad one on stderr, so
# silence is the pass. check reports this function's output, which is the
# complaint itself — the config's own text can't be the signal, since it
# legitimately contains words like "error_symbol".
starship_accepts_its_config() {
  local complaints
  complaints=$({ starship print-config >/dev/null; } 2>&1)
  [[ -z $complaints ]] && return 0
  printf '%s\n' "$complaints"
  return 1
}

# check reports this function's output, so a mismatch shows what the shell
# actually had, and what it complained about on the way there.
has_var() { # has_var <bash|zsh> <name> <value>
  local got
  got=$(startup_var "$1" "$2")
  [[ $got == "$3" ]] && return 0
  printf '%s=%s\n' "$2" "$got"
  cat "$tmp/shell-err"
  return 1
}

# The tools the layers integrate with, stubbed: each integration runs and
# leaves a mark, without the container needing the real thing.
stub_tools() {
  local tool
  mkdir -p "$1"
  for tool in starship zoxide fzf; do
    printf '#!/bin/sh\nprintf "export %s_STUB=1\\n"\n' "${tool^^}" >"$1/$tool"
    chmod +x "$1/$tool"
  done
}

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

# --- A Managed Machine whose owner can't become root -----------------------
#
# First, because the packages a later scenario installs stay installed for the
# rest of the container: once starship is on PATH there is no missing package
# left to fail on. A Workstation never reaches the install, so it skips this.

if [[ $kind == managed ]]; then
  fresh_machine
  clone_to "$HOME/.dotfiles"

  # A sudo that refuses, the way an account outside sudoers behaves.
  mkdir -p "$HOME/norootbin"
  printf '#!/bin/sh\nexit 1\n' >"$HOME/norootbin/sudo"
  chmod +x "$HOME/norootbin/sudo"

  check pass "bootstrap finishes without a way to become root" \
    env DOTFILES_KIND="$kind" PATH="$HOME/norootbin:$PATH" "$HOME/.dotfiles/bootstrap.sh"
  check pass "it warns about the tools it couldn't install" grep -qi "could not install" "$tmp/last"
  check pass "the Tracked configs still went in" linked .gitconfig
fi

# --- Run from a clone ------------------------------------------------------

fresh_machine
clone_to "$HOME/.dotfiles"

check pass "bootstrap from the clone" env DOTFILES_KIND="$kind" "$HOME/.dotfiles/bootstrap.sh"
cp "$tmp/last" "$tmp/first-run" # what the first run said, for checks further down
PATH=$HOME/.local/bin:$PATH # later scenarios reuse this chezmoi instead of downloading it again

check pass "chezmoi installed without root" test -x "$HOME/.local/bin/chezmoi"
check pass "git config is a symlink into the clone" linked .gitconfig
check pass "git ignore is a symlink into the clone" linked .config/git/ignore

# The distribution's own dotfiles were in the way and were set aside, not lost.
# Debian's skel carries .bashrc, Arch's carries .bash_profile too.
if [[ -f /etc/skel/.bashrc ]]; then
  check pass "the distribution's .bashrc gave way to the tracked one" linked .bashrc
  saved=$(echo "$HOME"/.dotfiles-backup/*/.bashrc)
  check pass "and is still readable in the backup" test -s "$saved"
  # In bash, not with cmp: the Arch image has no diffutils, and neither does
  # Bootstrap assume one.
  check pass "with its contents intact" is "$(cat "$saved" 2>/dev/null)" "$(cat /etc/skel/.bashrc)"
  check pass "bootstrap said where it put them" grep -q "dotfiles-backup" "$tmp/first-run"
fi
# The prompt is part of the Portable core, so every Machine kind gets it.
check pass "starship config is a symlink into the clone" linked .config/starship.toml
check pass "git reads the tracked config" is "$(git config --global init.defaultBranch)" master
check pass "chezmoi has nothing to apply" chezmoi verify
check pass "clone's hooks path points at its hooks" is "$(git -C "$HOME/.dotfiles" config core.hooksPath)" .githooks
check pass "Machine kind recorded" is "$(chezmoi execute-template '{{ .kind }}')" "$kind"
check fail "tracked git config names no client folder" grep -qi includeif "$HOME/.gitconfig"
check fail "tracked git config holds no identity" git config --file "$HOME/.gitconfig" --get-regexp "^user\\."
# Split so this file doesn't match its own scan of the clone.
secret_var=MAVEN_PUBLICATION"_PASSWORD"
check fail "no Secret anywhere in the clone" grep -rq "$secret_var" "$HOME/.dotfiles"

# The shell tools the Portable core expects. A Managed Machine gets them from
# its package manager during Bootstrap; a Workstation's packages are stage 2.
# Before the stubs further down, which would answer for the real thing.
for tool in starship fzf zoxide; do
  if [[ $kind == managed ]]; then
    check pass "$tool installed on a Managed Machine" command -v "$tool"
  else
    check fail "$tool not installed on a Workstation" command -v "$tool"
  fi
done

# Wherever starship is installed, make it read the Imported config for real: a
# file that parses on the Mac can still be rejected by the older starship a
# distribution packages. Asked of starship's presence rather than the Machine
# kind, so a Workstation that gains starship is checked too.
if command -v starship >/dev/null; then
  check pass "starship accepts the tracked config" starship_accepts_its_config
fi

# Shell layers. Every Machine gets the portable and zsh layers now; the macOS
# layer belongs to a Mac alone, and neither container is one.
for layer in .bashrc .bash_profile .zshrc .zshenv .config/shell/portable.sh .config/shell/zsh.zsh; do
  check pass "$layer is a symlink into the clone" linked "$layer"
done
check fail "no macOS layer off a Mac" test -e "$HOME/.config/shell/macos.sh"
check fail "the shell layers hold no Secret" grep -rq "$secret_var" "$HOME/.config/shell"
check fail "no tracked config hard-codes a home directory" \
  grep -rqE '/(Users|home)/[a-z]' "$HOME/.dotfiles/home"

# Startup with whatever this Machine kind actually has: a Workstation has none
# of the optional tools, so it exercises the quiet-skip path; a Managed Machine
# has the three Bootstrap just installed.
for shell in bash zsh; do
  check pass "interactive $shell starts silently" starts_silently $shell
  check pass "$shell repeats no PATH entry" is "$(startup_path $shell | sort | uniq -d)" ""
done

# Each layer loads its Local override when it's there, and the checks above
# already ran with none. The portable one has to reach both shells, the zsh one
# only zsh, and an override is never tracked.
printf 'export PORTABLE_OVERRIDE=1\n' >"$HOME/.config/shell/portable.local.sh"
printf 'export ZSH_OVERRIDE=1\n' >"$HOME/.config/shell/zsh.local.zsh"
for shell in bash zsh; do
  check pass "$shell loads the portable Local override" has_var $shell PORTABLE_OVERRIDE 1
done
check pass "zsh loads the zsh Local override" has_var zsh ZSH_OVERRIDE 1
check pass "bash is not given the zsh Local override" has_var bash ZSH_OVERRIDE ""
check pass "an override leaves chezmoi with nothing to apply" chezmoi verify
check fail "no Local override is tracked" git -C "$HOME/.dotfiles" ls-files --error-unmatch \
  home/dot_config/shell/portable.local.sh
rm -f "$HOME/.config/shell/portable.local.sh" "$HOME/.config/shell/zsh.local.zsh"

# Startup once starship, fzf and zoxide are there.
stub_tools "$HOME/.local/bin"
for shell in bash zsh; do
  check pass "interactive $shell starts silently with the tools installed" \
    starts_silently $shell
  for tool in STARSHIP FZF ZOXIDE; do
    check pass "$shell runs the ${tool,,} integration" has_var $shell "${tool}_STUB" 1
  done
done

before=$(snapshot)
check pass "second run needs no answers" bootstrap
check fail "second run installs nothing" grep -qi "installing" "$tmp/last"
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

# --- A distribution default the owner has edited ---------------------------
#
# The line above this one is the whole point: setting untouched defaults aside
# must not become a licence to discard a file somebody has put work into.

if [[ -f /etc/skel/.bashrc ]]; then
  fresh_machine
  clone_to "$HOME/.dotfiles"
  printf '\nalias mine="something I wrote"\n' >>"$HOME/.bashrc"
  edited=$(cat "$HOME/.bashrc")

  check fail "bootstrap stops on an edited default" \
    env DOTFILES_KIND="$kind" "$HOME/.dotfiles/bootstrap.sh"
  check pass "it names the file" grep -q "$HOME/.bashrc" "$tmp/last"
  check pass "the edit is untouched" is "$(cat "$HOME/.bashrc")" "$edited"
  check fail "it was not replaced by a symlink" test -L "$HOME/.bashrc"
  check fail "nothing was moved aside" test -e "$HOME/.dotfiles-backup"
  check fail "nothing else applied" test -e "$HOME/.config/git/ignore"
fi

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
