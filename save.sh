#!/bin/bash
# Refresh this repo from the machine you are on: copies the configs listed in
# common.sh, records every installed shell plugin and git theme, and vendors
# plugins that only exist locally. Nothing is committed without asking.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

echo "Saving configs from $HOME into $REPO_DIR"
echo

# --- Config files ---------------------------------------------------------
for category in "${CATEGORIES[@]}"; do
  for rel in $(cat_field "$category" 4); do
    src="$HOME/$rel"
    dst="$HOME_DIR/$rel"
    if [[ ! -e $src ]]; then
      echo "  skip  $rel (not on this machine)"
      continue
    fi
    rm -rf "$dst"
    mkdir -p "$(dirname "$dst")"
    cp -a "$src" "$dst"
    echo "  saved $rel"
  done
done

# Never keep editor/backup leftovers.
find "$HOME_DIR" \( -name '*.bak' -o -name '*.bak.*' -o -name '*~' -o -name '*.swp' \) -delete

# --- Plugins --------------------------------------------------------------
enabled_ids=$(omarchy plugin list 2>/dev/null | awk 'NR>1 && $3=="third-party" && $2=="enabled" {print $1}')

rm -rf "$PLUGINS_DIR"
mkdir -p "$PLUGINS_DIR"
printf '# id\tsource\tcommit\tenabled\n' > "$PLUGINS_LIST"

echo
for dir in "$PLUGIN_ROOT"/*/; do
  dir=${dir%/}
  id=$(basename "$dir")
  [[ -f $dir/manifest.json ]] || continue
  enabled=n
  grep -qx "$id" <<< "$enabled_ids" && enabled=y

  url=$(git -C "$dir" remote get-url origin 2>/dev/null || true)
  if [[ -n $url ]]; then
    git -C "$dir" fetch -q origin 2>/dev/null || true
    commit=$(git -C "$dir" rev-parse HEAD)
    # Pin only to a commit the remote actually has; a fresh clone cannot
    # check out unpushed local work.
    if [[ -z $(git -C "$dir" branch -r --contains "$commit" 2>/dev/null) ]]; then
      pushed=$(git -C "$dir" merge-base HEAD '@{u}' 2>/dev/null || true)
      echo "  note  $id: HEAD $commit is not pushed, pinning to ${pushed:-HEAD}"
      commit=${pushed:-$commit}
    fi
    if [[ -n $(git -C "$dir" status --porcelain) ]]; then
      echo "  note  $id: has uncommitted local edits that a fresh install will not get"
    fi
    printf '%s\tgit:%s\t%s\t%s\n' "$id" "$url" "$commit" "$enabled" >> "$PLUGINS_LIST"
    echo "  plugin $id (git, enabled=$enabled)"
  else
    cp -a "$dir" "$PLUGINS_DIR/$id"
    printf '%s\tvendored\t-\t%s\n' "$id" "$enabled" >> "$PLUGINS_LIST"
    echo "  plugin $id (vendored copy, enabled=$enabled)"
  fi
done

# --- Git-installed themes -------------------------------------------------
printf '# name\turl\tcommit\n' > "$THEMES_LIST"
for dir in "$THEME_ROOT"/*/; do
  dir=${dir%/}
  url=$(git -C "$dir" remote get-url origin 2>/dev/null || true)
  [[ -n $url ]] || continue
  printf '%s\t%s\t%s\n' "$(basename "$dir")" "$url" "$(git -C "$dir" rev-parse HEAD)" >> "$THEMES_LIST"
  echo "  theme $(basename "$dir") (git)"
done

cp "$HOME/.local/state/omarchy/current/theme.name" "$REPO_DIR/current-theme" 2>/dev/null || true

# --- Commit ---------------------------------------------------------------
echo
cd "$REPO_DIR"
git add -A
if git diff --cached --quiet; then
  echo "Repo already up to date."
  exit 0
fi
git status --short
echo
read -rp "Commit and push these changes? [y/N]: " answer
if [[ $answer == [yY] ]]; then
  git commit -q -m "Sync configs from $(hostname) ($(date +%F))"
  git push -q
  echo "Pushed."
else
  echo "Left staged, not committed."
fi
