echo "Remove the obsolete Muslimtify compatibility helper"

set -euo pipefail
helper="$HOME/.local/bin/hyprsimple-muslimtify.sh"
[[ -e $helper || -L $helper ]] || exit 0
rm -f -- "$helper"
[[ ! -e $helper && ! -L $helper ]]
