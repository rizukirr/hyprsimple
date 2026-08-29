echo "Drop the repository history hyprsimple does not need"

# A default clone brings every branch, every remote-tracking ref and every tag,
# and git keeps an object alive as long as any reference reaches it. That is why
# an install carries the full history, 192 MB against 27 MB for a shallow one,
# including every version of the wallpapers removed in the repo slimming.
#
# git pull only ever adds objects, so an install never shrinks on its own.
#
# This is the only migration that deletes data permanently. There is nothing to
# restore from afterwards, so it refuses and changes nothing whenever it sees
# something it does not expect. Losing 165 MB of disk is better than losing a
# commit somebody meant to keep.

REPO="$HYPRSIMPLE_PATH"
[[ -d $REPO/.git ]] || exit 0

if [[ -f $REPO/.git/shallow ]]; then
  echo "  Already shallow, nothing to do"
  exit 0
fi

branch=$(git -C "$REPO" symbolic-ref --quiet --short HEAD) || {
  echo "  HEAD is detached, leaving this install alone"
  exit 0
}

if [[ -n $(git -C "$REPO" status --porcelain) ]]; then
  echo "  $REPO has local changes, leaving it alone"
  exit 0
fi

# A branch holding commits the tracked branch cannot reach is somebody's work.
unmerged=()
while IFS= read -r b; do
  [[ $b == "$branch" ]] && continue
  if [[ -n $(git -C "$REPO" rev-list --count "$branch..$b" 2>/dev/null) ]] &&
     (($(git -C "$REPO" rev-list --count "$branch..$b") > 0)); then
    unmerged+=("$b")
  fi
done < <(git -C "$REPO" for-each-ref --format='%(refname:short)' refs/heads)

if ((${#unmerged[@]} > 0)); then
  echo "  These branches have commits not on $branch, so nothing was deleted:"
  for b in "${unmerged[@]}"; do
    echo "    $b"
  done
  echo "  Merge or delete them and run hyprsimple-update again to reclaim the space."
  exit 0
fi

before=$(du -sm "$REPO/.git" | cut -f1)

# 1. Cut the parent chain so history stops being reachable through the branch.
git -C "$REPO" fetch --quiet --depth 1 origin "$branch" || {
  echo "  Could not reach origin, leaving this install alone"
  exit 0
}

# 2. Drop every other reference. Until these are gone they still reach the old
#    objects regardless of the shallow fetch.
while IFS= read -r b; do
  [[ $b == "$branch" ]] && continue
  git -C "$REPO" branch -D "$b" >/dev/null 2>&1
done < <(git -C "$REPO" for-each-ref --format='%(refname:short)' refs/heads)

while IFS= read -r r; do
  [[ $r == "refs/remotes/origin/$branch" ]] && continue
  git -C "$REPO" update-ref -d "$r" 2>/dev/null
done < <(git -C "$REPO" for-each-ref --format='%(refname)' refs/remotes refs/tags)

# 3. The reflog is a hidden reference that would keep everything alive.
git -C "$REPO" reflog expire --expire=now --all 2>/dev/null

# 4. Rewrite the pack without the unreachable objects. This reclaims the space.
git -C "$REPO" repack -adq 2>/dev/null
git -C "$REPO" prune --expire=now 2>/dev/null

after=$(du -sm "$REPO/.git" | cut -f1)
echo "  Install history: ${before} MB -> ${after} MB"
