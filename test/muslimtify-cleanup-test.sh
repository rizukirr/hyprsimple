#!/bin/bash
# Cleanup only the obsolete helper in an isolated home.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" HYPRSIMPLE_PATH="$REPO"
mkdir -p "$HOME/.local/bin" "$HOME/.config/muslimtify" "$HOME/.config/hyprsimple" "$HOME/.local/share/hyprsimple-plugins/muslimtify" "$TMP/bin"
printf custom >"$HOME/.config/muslimtify/config.json"
printf settings >"$HOME/.config/hyprsimple/plugins.json"
printf plugin >"$HOME/.local/share/hyprsimple-plugins/muslimtify/manifest.json"
cp -a "$HOME" "$TMP/expected"
run() { bash "$REPO/migrations/1791554376.sh"; }
run
printf obsolete >"$HOME/.local/bin/hyprsimple-muslimtify.sh"
run
run
diff -r "$TMP/expected" "$HOME"
ln -s "$HOME/.config/muslimtify/config.json" "$HOME/.local/bin/hyprsimple-muslimtify.sh"
run
diff -r "$TMP/expected" "$HOME"
ln -s "$HOME/missing" "$HOME/.local/bin/hyprsimple-muslimtify.sh"
run
diff -r "$TMP/expected" "$HOME"
printf obsolete >"$HOME/.local/bin/hyprsimple-muslimtify.sh"
printf '#!/bin/bash\nexit 1\n' >"$TMP/bin/rm"
chmod +x "$TMP/bin/rm"
if PATH="$TMP/bin:$PATH" run; then echo 'not ok - failed deletion accepted'; exit 1; fi
[[ -f $HOME/.local/bin/hyprsimple-muslimtify.sh ]]
printf '#!/bin/bash\nexit 0\n' >"$TMP/bin/rm"
if PATH="$TMP/bin:$PATH" run; then echo 'not ok - retained helper accepted'; exit 1; fi
run
diff -r "$TMP/expected" "$HOME"
echo 'ok - absent, repeat, symlink and failed deletion preserve all other home files'
