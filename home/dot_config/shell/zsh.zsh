# zsh layer: the plugin manager, completion, history and key bindings. Only zsh
# reads this, so zsh syntax is fine here, and only an interactive zsh needs it,
# so ~/.zshrc sources it while ~/.zshenv loads the portable layer. The entry
# point sets shell_dir.

### Plugin manager (zinit)
ZINIT_HOME=${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git

# Installed on first run. Without git, or without a network, the shell starts
# without plugins instead of complaining about it.
if [[ ! -f $ZINIT_HOME/zinit.zsh ]] && (( $+commands[git] )); then
  command mkdir -p "${ZINIT_HOME:h}" && command chmod g-rwX "${ZINIT_HOME:h}"
  command git clone -q https://github.com/zdharma-continuum/zinit "$ZINIT_HOME" 2>/dev/null
fi

# Asked twice below, once either side of compinit, so settle it here.
zinit_ready=0
[[ -f $ZINIT_HOME/zinit.zsh ]] && zinit_ready=1

if (( zinit_ready )); then
  source "$ZINIT_HOME/zinit.zsh"
  autoload -Uz _zinit
  (( ${+_comps} )) && _comps[zinit]=_zinit

  zinit light-mode for \
    zdharma-continuum/zinit-annex-as-monitor \
    zdharma-continuum/zinit-annex-bin-gem-node \
    zdharma-continuum/zinit-annex-patch-dl \
    zdharma-continuum/zinit-annex-rust

  # The plugin runs `fnm env` as it loads, so it needs fnm to be there.
  (( $+commands[fnm] )) && zinit light dominik-schwabe/zsh-fnm
fi

### Completion. After the early plugins, so their compdefs are in place.
zcompdump=${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump
command mkdir -p "${zcompdump:h}"
autoload -Uz compinit && compinit -d "$zcompdump"
unset zcompdump

if (( zinit_ready )); then
  zinit cdreplay -q
  # fzf-tab must load after compinit and before the widget-wrapping plugins.
  zinit light Aloxaf/fzf-tab
  zinit light zsh-users/zsh-autosuggestions
  zinit light zdharma-continuum/fast-syntax-highlighting
fi
unset zinit_ready

### History
HISTSIZE=100000
SAVEHIST=100000
HISTFILE="$HOME/.zsh_history"
setopt SHARE_HISTORY        # share history across sessions
setopt HIST_IGNORE_ALL_DUPS # don't record duplicates
setopt HIST_REDUCE_BLANKS   # strip superfluous blanks
setopt HIST_VERIFY          # confirm before running history expansion

### Completion styling
zstyle ':completion:*' menu no
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
if (( $+commands[eza] )); then
  zstyle ':fzf-tab:complete:cd:*' fzf-preview \
    'eza --tree --icons --color=always --level=2 $realpath'
  zstyle ':fzf-tab:complete:z:*' fzf-preview \
    'eza --tree --icons --color=always --level=2 $realpath'
fi

### Key bindings: type a prefix, press up/down to cycle matching history
zmodload -F zsh/terminfo +p:terminfo 2>/dev/null
[[ -n ${terminfo[kcuu1]} ]] && bindkey "${terminfo[kcuu1]}" history-beginning-search-backward
[[ -n ${terminfo[kcud1]} ]] && bindkey "${terminfo[kcud1]}" history-beginning-search-forward
bindkey '^[[A' history-beginning-search-backward
bindkey '^[[B' history-beginning-search-forward

### Bun's completions
[[ -s ${BUN_INSTALL:-$HOME/.bun}/_bun ]] && source "${BUN_INSTALL:-$HOME/.bun}/_bun"

# Local override, never tracked: this Machine's own settings. Last in the
# layer, so it can undo anything above.
if [[ -r $shell_dir/zsh.local.zsh ]]; then
  source "$shell_dir/zsh.local.zsh"
fi
