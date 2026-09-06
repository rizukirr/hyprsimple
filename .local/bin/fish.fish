# Enable zoxide (smart cd) — replaces `cd`
if command -v zoxide >/dev/null 2>&1
    zoxide init --cmd cd fish | source
end

# Enable fzf
if command -v fzf >/dev/null 2>&1
    fzf --fish | source
end

# enable starship
if command -v starship >/dev/null 2>&1
    starship init fish | source
end

# yazi configuration
function y
    if command -v yazi >/dev/null 2>&1
        set -l tmp (mktemp -t "yazi-cwd.XXXXXX")
        yazi $argv --cwd-file="$tmp"
        if set -l cwd (command cat -- "$tmp"); and test -n "$cwd"; and test "$cwd" != "$PWD"
            builtin cd -- "$cwd"
        end
        rm -f -- "$tmp"
    end
end

# lsd reads ls flags, so ls stays ls with nicer output.
#
# grep has no alias at all. It used to be aliased to rg, which is not a drop in
# for it and does not claim to be. Its -r is --replace, not --recursive, so
#
#   grep -r hello .
#
# searched for the regex . and replaced every character it matched, printing
# hellohellohellohello... and exiting 0. rg also skips anything .gitignore
# excludes and every hidden file, so a plain grep inside a repository quietly
# missed files grep would have found. Both failures look like results.
#
# grep is grep and rg is rg. Both are installed, and each keeps the flags its
# own documentation describes.
alias ls='lsd'
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
