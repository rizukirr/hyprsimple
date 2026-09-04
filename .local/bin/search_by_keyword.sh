#!/bin/bash

KEYWORD=$1

if [[ -z "$KEYWORD" ]]; then
  # Named for the script, like every other usage line here. "sk" was a command
  # that has never existed under any name, in this project or on PATH.
  echo "Usage: search_by_keyword.sh [keyword]" >&2
  # Without this the search runs anyway, and rg treats an empty pattern as
  # matching every line of every file.
  exit 1
fi

fsearch() {
  rg --line-number --no-heading --color=always "$KEYWORD" |
    fzf --ansi --delimiter : \
      --preview 'bat --style=numbers --color=always {1} --highlight-line {2}' \
      --bind 'enter:execute(nvim {1} +{2})'
}

fsearch
