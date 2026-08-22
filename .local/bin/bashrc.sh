#!/bin/bash

# Enable bash completion
if [[ -f /usr/share/bash-completion/bash_completion ]]; then
  . /usr/share/bash-completion/bash_completion
fi

# Enable zoxide
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init --cmd cd bash)"
fi

# Enable fzf
if command -v fzf >/dev/null 2>&1; then
  eval "$(fzf --bash)"
fi

# enable startship
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init bash)"
fi

# yazi configuration
y() {
  if command -v yazi >/dev/null 2>&1; then
    local tmp
    tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
    local cwd
    yazi "$@" --cwd-file="$tmp"
    IFS= read -r -d '' cwd <"$tmp"
    [ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd" || return
    rm -f -- "$tmp"
  fi
}

# Hitory configuration
HISTSIZE=10000
HISTFILESIZE=20000
HISTCONTROL=ignoreboth
shopt -s histappend
shopt -s checkwinsize
PS1='[\u@\h \W]\$ '

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

# muslimtify add/remove
alias muslimtify-add='~/.local/bin/hyprsimple-muslimtify.sh add'
alias muslimtify-remove='~/.local/bin/hyprsimple-muslimtify.sh remove'
