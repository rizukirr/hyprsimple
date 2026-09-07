echo "Clear out two files nothing reads"

# --- themes/<name>/btop.theme -----------------------------------------------
#
# Fifteen of these shipped, one per theme, and nothing has read them since the
# template system landed. theme-switcher.sh copies
# themes/<name>/generated/btop.theme, rendered from templates/btop.theme.tpl,
# and never looks at the file beside it. Measured on a live install: the one in
# the theme directory differs from the one btop is actually using, and only one
# of the fifteen carries the full set of keys.
#
# So editing one changed nothing, and comparing one against the running theme
# was misleading twice over.
#
# Removed only where the file is still byte-identical to a version hyprsimple
# shipped. Anything else at that path is somebody's own and is left alone.

SHIPPED_BTOP="
  b7badcd7144d486cb35fa93090b0f94e
  7797ba82dcd99f94ea1cc87a61a620bf
  2baedeb16a89db75c137fdb7d23350af
  f91256f8eb403ed431ecfb557ea61995
  5a19e4b5c265026f5fab404053fc33ad
  99d191bfd096d74105b9107aeefd5d1c
  cb0232d415c26e5d1e758de77801b400
  62e2a70bc915adcc165d66f89d86b601
  5d775a574351e3a57c380997896e4e7e
  c341f1274a4fc90ce33a9c3852ad389d
  d420ed69f29fe174a1b48a432d2541e7
  2cac7fd1eb65910e04583abee4f59459
  b6bcb82d63ade53c0102d79d898f6fa4
  0bc9cb8edc22a659598257ab86aebc17
"

removed=0
kept=()

for theme_file in "$HOME"/.config/hypr/themes/*/btop.theme; do
  [[ -f $theme_file ]] || continue
  sum=$(md5sum "$theme_file" | cut -d' ' -f1)
  if grep -qw "$sum" <<<"$SHIPPED_BTOP"; then
    rm -f "$theme_file"
    removed=$((removed + 1))
  else
    kept+=("$theme_file")
  fi
done

if (( removed > 0 )); then
  echo "  Removed $removed btop theme file(s) nothing was reading."
fi
if (( ${#kept[@]} > 0 )); then
  echo "  Left alone, because they are not the versions hyprsimple shipped:"
  printf '    %s\n' "${kept[@]}"
  echo "  Nothing reads them either. btop uses themes/<name>/generated/btop.theme."
fi

# --- a ~/.bashrc symlinked into a checkout ----------------------------------
#
# An installer before 9aaa1e4 did
#
#   ln -sf "$DOTFILES_DIR/.bashrc" "$HOME/.bashrc"
#
# pointing the home file at whatever directory the repository was cloned into,
# which is not the canonical install path and is somewhere hyprsimple never
# looks again. Moving or deleting that clone leaves ~/.bashrc dangling, and a
# dangling rc file means bash starts with no aliases, no starship and no
# zoxide, silently.
#
# hyprsimple no longer ships a .bashrc at all, which would turn such a link
# dangling for anyone who pulls in that old clone, so the link is replaced with
# a real file holding what it used to point at.

BASHRC="$HOME/.bashrc"

if [[ -L $BASHRC ]]; then
  target=$(readlink "$BASHRC")
  if [[ $target == *".bashrc" && $target != "$BASHRC" ]]; then
    rm -f "$BASHRC"
    cat >"$BASHRC" <<'RC'
# If not running interactively, don't do anything
[[ $- != *i* ]] && return

source "$HOME/.local/bin/bashrc.sh"
RC
    echo "  Replaced the ~/.bashrc symlink with a real file."
    echo "  It pointed at $target, which hyprsimple no longer ships."
    if [[ -e "$BASHRC.backup" ]]; then
      echo "  Anything you had before that link was made is at $BASHRC.backup."
    fi
  fi
fi
