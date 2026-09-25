#!/usr/bin/env bash
# Bootstrap: take this Machine to having its Tracked configs in place. Safe to re-run.
#
#   curl -fsSL https://raw.githubusercontent.com/iyadh/dotfiles/master/bootstrap.sh | bash
#   ~/.dotfiles/bootstrap.sh
#
# Needs git and curl. Root is only used to install a Managed Machine's shell
# tools, and Bootstrap carries on without it. Environment:
#   DOTFILES_KIND  workstation or managed: answers the one-time Machine kind question
#   DOTFILES_REPO  what to clone into ~/.dotfiles when it doesn't exist yet
set -euo pipefail

dir=$HOME/.dotfiles
repo=${DOTFILES_REPO:-https://github.com/iyadh/dotfiles.git}
bin=$HOME/.local/bin

# The shell tools the Portable core expects on every Machine. A Workstation
# gets its packages in stage 2, so Bootstrap only installs these on a Managed
# Machine. Each name is both the package and the command it provides, which is
# how a second run knows there is nothing left to do.
managed_tools=(starship fzf zoxide)

say() { printf '==> %s\n' "$*"; }
warn() { printf '!  %s\n' "$*" >&2; }
die() {
  printf '✗ %s\n' "$@" >&2
  exit 1
}

# Run a command as root. Already root, nothing to do; otherwise sudo, which may
# ask for a password on the terminal. No way to become root is not fatal here:
# the only caller treats a failure as a warning.
as_root() {
  if [[ $(id -u) -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null; then
    sudo "$@"
  else
    return 1
  fi
}

# Install the Managed Machine's shell tools, one at a time so that one package
# the distribution doesn't carry can't stop the others from arriving.
install_managed_tools() {
  local tool missing=()
  for tool in "${managed_tools[@]}"; do
    command -v "$tool" >/dev/null || missing+=("$tool")
  done
  ((${#missing[@]} > 0)) || return 0 # a second run finds them all and installs nothing

  local pm
  if command -v apt-get >/dev/null; then
    pm=apt
  elif command -v pacman >/dev/null; then
    pm=pacman
  else
    warn "No apt or pacman here, so ${missing[*]} are not installed."
    return 0
  fi

  say "Installing ${missing[*]}"
  case $pm in
    apt) as_root env DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null 2>&1 || true ;;
    pacman) as_root pacman -Sy --noconfirm --quiet >/dev/null 2>&1 || true ;;
  esac

  for tool in "${missing[@]}"; do
    case $pm in
      apt) as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$tool" >/dev/null 2>&1 ;;
      pacman) as_root pacman -S --noconfirm --needed --quiet "$tool" >/dev/null 2>&1 ;;
    esac || warn "Could not install $tool. Bootstrap carried on without it."
  done
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

  # Ask chezmoi rather than DOTFILES_KIND, which is only set on the first run.
  local kind
  kind=$(chezmoi execute-template '{{ .kind }}' 2>/dev/null) || kind=
  if [[ $kind == managed ]]; then
    install_managed_tools
  fi

  say "Done. Update later with: chezmoi update"
  if [[ $on_path == false ]]; then
    say "chezmoi is in $bin; add it to PATH to run it directly."
  fi
}

main "$@"
