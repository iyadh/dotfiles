#!/usr/bin/env bash
# Bootstrap: take this Machine to having its Tracked configs in place. Safe to re-run.
#
#   curl -fsSL https://raw.githubusercontent.com/iyadh/dotfiles/master/bootstrap.sh | bash
#   ~/.dotfiles/bootstrap.sh
#
# Needs git and curl. No root. Environment:
#   DOTFILES_KIND  workstation or managed: answers the one-time Machine kind question
#   DOTFILES_REPO  what to clone into ~/.dotfiles when it doesn't exist yet
set -euo pipefail

dir=$HOME/.dotfiles
repo=${DOTFILES_REPO:-https://github.com/iyadh/dotfiles.git}
bin=$HOME/.local/bin

say() { printf '==> %s\n' "$*"; }
die() {
  printf '✗ %s\n' "$@" >&2
  exit 1
}

# Piped from a URL, bash reads this script from stdin as it runs. Wrapping it in
# main makes bash read all of it first, so no command can swallow the rest.
main() {
  local cmd
  for cmd in git curl; do
    command -v "$cmd" >/dev/null || die "Bootstrap needs $cmd. Install it and re-run."
  done

  if [[ -n ${DOTFILES_KIND:-} && $DOTFILES_KIND != workstation && $DOTFILES_KIND != managed ]]; then
    die "DOTFILES_KIND must be workstation or managed, not \"$DOTFILES_KIND\"."
  fi

  # The clone. Every symlink points into it, so it lives in one place on every Machine.
  local self=${BASH_SOURCE[0]:-} here
  if [[ -f $self ]]; then
    here=$(cd "$(dirname "$self")" && pwd -P)
    if [[ $here != "$(cd "$dir" 2>/dev/null && pwd -P)" ]]; then
      die "This clone is at $here, but Bootstrap needs it at $dir." \
        "Move it there and re-run: mv \"$here\" \"$dir\""
    fi
  elif [[ ! -e $dir ]]; then
    say "Cloning $repo into $dir"
    git clone -q "$repo" "$dir" </dev/null
  fi
  [[ -f $dir/.chezmoiroot ]] || die "$dir exists but isn't a clone of the dotfiles repo."

  local on_path=true installer
  if ! command -v chezmoi >/dev/null; then
    on_path=false
    if [[ ! -x $bin/chezmoi ]]; then
      say "Installing chezmoi into $bin"
      installer=$(curl -fsSL https://get.chezmoi.io)
      sh -c "$installer" -- -b "$bin" </dev/null
    fi
    PATH=$bin:$PATH
  fi

  # Asks the Machine kind the first time only. chezmoi asks on the terminal, not
  # stdin, so this works when piped too.
  local init=(init --source "$dir")
  [[ -n ${DOTFILES_KIND:-} ]] && init+=(--promptChoice "Machine kind=$DOTFILES_KIND")
  chezmoi "${init[@]}" ||
    die "chezmoi init failed. With no terminal to ask on, set DOTFILES_KIND=workstation or managed."

  # Never overwrite a config chezmoi didn't create: chezmoi records every file it writes.
  local target path conflicts=()
  while IFS= read -r target; do
    path=$HOME/$target
    [[ -e $path || -L $path ]] || continue
    [[ -z $(chezmoi state get --bucket=entryState --key="$path") ]] && conflicts+=("$path")
  done < <(chezmoi managed --include=files,symlinks --path-style=relative)

  if ((${#conflicts[@]} > 0)); then
    printf '✗ These already exist and chezmoi did not create them:\n' >&2
    printf '    %s\n' "${conflicts[@]}" >&2
    printf '  Nothing was changed. Move them aside (keep Local overrides, such as\n' >&2
    printf '  per-client git includes, in ~/.gitconfig.local), then re-run.\n' >&2
    exit 1
  fi

  say "Applying Tracked configs"
  chezmoi apply

  git -C "$dir" config core.hooksPath .githooks

  say "Done. Update later with: chezmoi update"
  if [[ $on_path == false ]]; then
    say "chezmoi is in $bin; add it to PATH to run it directly."
  fi
}

main "$@"
