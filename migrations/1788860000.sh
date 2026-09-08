echo "Move the recording indicator to the left, beside the prayer times"

# waybar/config.jsonc is copied once at install and never touched again, so a
# module hyprsimple moves later does not move on an existing machine. This
# moves it, surgically, in the file the user already has.
#
# Only the two module lists are touched, and only when the module is in
# modules-right and not already in modules-left. A config that has been
# rearranged by hand keeps its arrangement.
#
# python3 rather than sed. The last time this project moved a waybar module
# with sed, the pattern matched "hyprland/workspaces" in every list rather than
# the one it named, and the module landed in two of them.

CONFIG="$HOME/.config/waybar/config.jsonc"

if [[ ! -f $CONFIG ]]; then
  echo "  No waybar config here, so there is nothing to move."
  exit 0
fi

python3 - "$CONFIG" <<'PY'
import re, sys

path = sys.argv[1]
text = open(path).read()
MODULE = '"custom/screenrecording"'

def find_list(name):
    m = re.search(r'("%s"\s*:\s*)\[([^\]]*)\]' % name, text)
    return m

left = find_list("modules-left")
right = find_list("modules-right")

if not left or not right:
    print("  Could not find both module lists, so nothing was changed.")
    raise SystemExit(0)

if MODULE in left.group(2):
    print("  The recording indicator is already on the left.")
    raise SystemExit(0)

if MODULE not in right.group(2):
    print("  The recording indicator is not in modules-right, so it was left alone.")
    raise SystemExit(0)

# Drop it from modules-right, with the comma that goes with it.
new_right = re.sub(r',\s*' + re.escape(MODULE), '', right.group(2))
new_right = re.sub(re.escape(MODULE) + r'\s*,\s*', '', new_right)
if new_right == right.group(2):
    print("  Could not remove it from modules-right cleanly, so nothing was changed.")
    raise SystemExit(0)

# Add it to modules-left, after muslimtify when that is there, else at the end.
items = [i.strip() for i in left.group(2).split(",") if i.strip()]
target = '"custom/muslimtify"'
if target in items:
    items.insert(items.index(target) + 1, MODULE)
else:
    items.append(MODULE)
new_left = ", ".join(items)

out = text[:left.start(2)] + new_left + text[left.end(2):]
# The right-hand list moved if it sits after the left one, so it is located
# again in the rewritten text rather than reusing the old offsets.
right2 = re.search(r'("modules-right"\s*:\s*)\[([^\]]*)\]', out)
out = out[:right2.start(2)] + new_right + out[right2.end(2):]

open(path, "w").write(out)
print("  Moved it to modules-left, after the prayer times.")
PY
