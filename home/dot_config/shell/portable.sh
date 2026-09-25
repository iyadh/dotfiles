# shellcheck shell=sh
# shellcheck disable=SC1091 # every file sourced here is optional and untracked
# shellcheck disable=SC2154 # the entry point sets shell_dir
# Portable layer: the environment, PATH and aliases every Machine shares.
# bash and zsh both read this, so it stays POSIX: no arrays, no [[ ]], no local.
#
# The entry point (~/.zshenv, ~/.bashrc) sets shell_dir and sources this first.
# Two things here are deliberately out of line:
#
#   - the macOS layer loads at the top, so the PATH entries below end up in
#     front of Homebrew's, the way they were before the config was split;
#   - the tool integrations sit in a function the entry point calls last,
#     because the prompt and the line-editor widgets have to wrap whatever the
#     zsh layer loaded.

# Is this directory worth adding to PATH? No if it isn't there, so a Machine
# without a tool carries no stale entry, and no if PATH already has it, so
# re-sourcing never duplicates one. These outlive the file, and a Local
# override is welcome to call them.
shell_path_wants() {
  [ -d "$1" ] || return 1
  case ":$PATH:" in
    *":$1:"*) return 1 ;;
  esac
  return 0
}

shell_path_prepend() {
  shell_path_wants "$1" || return 0
  PATH="$1:$PATH"
  export PATH
}

shell_path_append() {
  shell_path_wants "$1" || return 0
  PATH="$PATH:$1"
  export PATH
}

# The macOS layer, which chezmoi puts on Macs only.
[ -r "$shell_dir/macos.sh" ] && . "$shell_dir/macos.sh"

### Environment
export BUN_INSTALL="$HOME/.bun"

### PATH. Prepends stack up, so these run back to front: the last call here
### ends up first in PATH. The resulting order is the one the Mac had before
### the split, minus the repeats.
shell_path_prepend "$HOME/.cargo/bin"
shell_path_prepend "$BUN_INSTALL/bin"
shell_path_prepend "$HOME/.config/yarn/global/node_modules/.bin"
shell_path_prepend "$HOME/.yarn/bin"
shell_path_prepend "$HOME/.antigravity/antigravity/bin"
shell_path_prepend "$HOME/.local/bin"
shell_path_prepend "$HOME/.antigravity-ide/antigravity-ide/bin"

# Behind everything above, the way they were before the split.
shell_path_append "$HOME/.lmstudio/bin"
shell_path_append "$HOME/.rvm/bin"

### rvm, which wants to be a shell function rather than the script on PATH.
### Interactive shells only: it is a convenience at the prompt, and sourcing it
### for every `zsh -c` would put a slow script in the way of every script.
case $- in
  *i*) [ -s "$HOME/.rvm/scripts/rvm" ] && . "$HOME/.rvm/scripts/rvm" ;;
esac

# Integrations for the tools whose setup differs per shell. The entry point
# calls this last. Each tool is skipped without a word when it isn't installed,
# so the same layer serves a bare Managed Machine and a full Workstation.
shell_tool_integrations() {
  case $- in
    *i*) ;;
    *) return 0 ;;
  esac

  # Each tool wants to be told which shell it is setting up.
  if [ -n "${ZSH_VERSION-}" ]; then
    shell_name=zsh
  elif [ -n "${BASH_VERSION-}" ]; then
    shell_name=bash
  else
    return 0
  fi

  command -v fzf >/dev/null 2>&1 && eval "$(fzf "--$shell_name" 2>/dev/null)"
  command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init "$shell_name" 2>/dev/null)"
  command -v starship >/dev/null 2>&1 && eval "$(starship init "$shell_name" 2>/dev/null)"

  unset shell_name
  return 0
}

# Local override, never tracked: this Machine's own settings. Last in the
# layer, so it can undo anything above. An if rather than &&, so an absent
# override doesn't leave $? at 1 and greet the first prompt with a failure
# marker; the other layers do the same.
if [ -r "$shell_dir/portable.local.sh" ]; then
  . "$shell_dir/portable.local.sh"
fi
