#!/bin/zsh

# Enable zoxide (smart cd) — replaces `cd`
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init --cmd cd zsh)"
fi

# Enable fzf
if command -v fzf >/dev/null 2>&1; then
  eval "$(fzf --zsh)"
fi

# enable starship
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
fi

# yazi configuration
y() {
  if command -v yazi >/dev/null 2>&1; then
    local tmp cwd
    tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
    yazi "$@" --cwd-file="$tmp"
    if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
      builtin cd -- "$cwd"
    fi
    rm -f -- "$tmp"
  fi
}

# History configuration
HISTSIZE=10000
SAVEHIST=20000
HISTFILE="$HOME/.zsh_history"
setopt hist_ignore_all_dups
setopt hist_ignore_space
setopt append_history
setopt share_history

# better ls and grep
alias ls='lsd'
alias grep='rg --color=auto'
alias ffile='~/.local/bin/search.sh'
alias fany='~/.local/bin/search_by_keyword.sh'

# networking
alias hotspot='~/.local/bin/hotspot.sh'
alias wifi='~/.local/bin/wifi.sh'

# cpu mode
alias cpu='~/.local/bin/toggle_cpu_mode.sh'

# hyprsimple management
alias hyprsimple-update='~/.local/bin/hyprsimple-update.sh'
alias hyprsimple-migrate='~/.local/bin/hyprsimple-migrate.sh'
alias hyprsimple-refresh-config='~/.local/bin/hyprsimple-refresh-config.sh'
alias hyprsimple-debug='~/.local/bin/hyprsimple-debug.sh'

# muslimtify add/remove
alias muslimtify-add='~/.local/bin/hyprsimple-muslimtify.sh add'
alias muslimtify-remove='~/.local/bin/hyprsimple-muslimtify.sh remove'
