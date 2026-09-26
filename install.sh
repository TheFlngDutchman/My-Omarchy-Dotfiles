#!/bin/bash
# Interactive installer: pick which configs and shell plugins to put on this
# machine. Anything it would overwrite is backed up first.
#
#   ./install.sh          ask about everything
#   ./install.sh --yes    take the recommended choices without asking

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

ASSUME_YES=0
[[ ${1-} == "--yes" || ${1-} == "-y" ]] && ASSUME_YES=1

BACKUP_DIR="$HOME/.local/state/omarchy-dotfiles-backup/$(date +%Y%m%d-%H%M%S)"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }

ask() { # ask <question> <default y/n> -> returns 0 for yes
  local prompt=$1 default=$2 answer
  if (( ASSUME_YES )); then [[ $default == y ]]; return; fi
  if [[ $default == y ]]; then read -rp "$prompt [Y/n]: " answer; answer=${answer:-y}
  else read -rp "$prompt [y/N]: " answer; answer=${answer:-n}; fi
  [[ $answer == [yY]* ]]
}

backup() { # backup <path relative to $HOME>
  local rel=$1
  [[ -e $HOME/$rel ]] || return 0
  mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
  cp -a "$HOME/$rel" "$BACKUP_DIR/$rel"
}

for tool in git jq omarchy; do
  command -v "$tool" >/dev/null || { echo "Missing '$tool'. This installer is for an Omarchy system."; exit 1; }
done

echo
bold "Omarchy dotfiles installer"
echo "Repo:    $REPO_DIR"
echo "Backups: $BACKUP_DIR"
echo

# --- 1. Config categories -------------------------------------------------
bold "Configs"
chosen_categories=()
for category in "${CATEGORIES[@]}"; do
  if ask "  $(cat_field "$category" 2)?" "$(cat_field "$category" 3)"; then
    chosen_categories+=("$category")
  fi
done

# --- 2. Plugins -----------------------------------------------------------
mapfile -t plugin_rows < <(grep -v '^#' "$PLUGINS_LIST")
declare -a plugin_pick
echo
bold "Shell plugins"
for i in "${!plugin_rows[@]}"; do
  IFS=$'\t' read -r id source commit enabled <<< "${plugin_rows[$i]}"
  pick=$enabled
  [[ -n ${PLUGIN_WARNINGS[$id]-} ]] && pick=n
  plugin_pick[$i]=$pick
done

print_plugins() {
  for i in "${!plugin_rows[@]}"; do
    IFS=$'\t' read -r id source commit enabled <<< "${plugin_rows[$i]}"
    local mark=" "; [[ ${plugin_pick[$i]} == y ]] && mark="x"
    local kind="git"; [[ $source == vendored ]] && kind="local copy"
    printf '  %2d) [%s] %-42s %s\n' "$((i + 1))" "$mark" "$id" "($kind)"
    [[ -n ${PLUGIN_WARNINGS[$id]-} ]] && warn "         warning: ${PLUGIN_WARNINGS[$id]}"
  done
}

print_plugins
if (( ! ASSUME_YES )); then
  while true; do
    echo
    read -rp "Numbers to toggle (e.g. '3 7'), 'a' all, 'n' none, Enter to accept: " selection
    [[ -z $selection ]] && break
    case $selection in
      a|A) for i in "${!plugin_rows[@]}"; do plugin_pick[$i]=y; done ;;
      n|N) for i in "${!plugin_rows[@]}"; do plugin_pick[$i]=n; done ;;
      *)
        for n in $selection; do
          if [[ $n =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#plugin_rows[@]} )); then
            i=$((n - 1))
            [[ ${plugin_pick[$i]} == y ]] && plugin_pick[$i]=n || plugin_pick[$i]=y
          else
            echo "  ignoring '$n'"
          fi
        done ;;
    esac
    echo
    print_plugins
  done
fi

# --- 3. Git themes and current theme --------------------------------------
echo
mapfile -t theme_rows < <(grep -v '^#' "$THEMES_LIST" 2>/dev/null)
install_git_themes=0
if (( ${#theme_rows[@]} > 0 )); then
  names=$(cut -f1 <<< "$(printf '%s\n' "${theme_rows[@]}")" | paste -sd, - | sed 's/,/, /g')
  ask "Install git themes ($names)?" y && install_git_themes=1
fi
saved_theme=$(cat "$REPO_DIR/current-theme" 2>/dev/null || true)
apply_theme=0
[[ -n $saved_theme ]] && ask "Switch to the '$saved_theme' theme at the end?" y && apply_theme=1

# --- 4. Confirm -----------------------------------------------------------
echo
bold "About to install"
for category in "${chosen_categories[@]}"; do echo "  config  $(cat_field "$category" 2)"; done
for i in "${!plugin_rows[@]}"; do
  [[ ${plugin_pick[$i]} == y ]] && echo "  plugin  $(cut -f1 <<< "${plugin_rows[$i]}")"
done
(( install_git_themes )) && echo "  themes  from git"
(( apply_theme )) && echo "  theme   set $saved_theme"
echo
ask "Proceed?" y || { echo "Cancelled."; exit 0; }

errors=0

# --- 5. Copy configs ------------------------------------------------------
echo
for category in "${chosen_categories[@]}"; do
  for rel in $(cat_field "$category" 4); do
    src="$HOME_DIR/$rel"
    [[ -e $src ]] || continue
    backup "$rel"
    mkdir -p "$(dirname "$HOME/$rel")"
    if [[ -d $src ]]; then
      rm -rf "${HOME:?}/$rel"
      cp -a "$src" "$HOME/$rel"
    else
      cp -a "$src" "$HOME/$rel"
    fi
    echo "  ok    $rel"
  done
done

# --- 6. Plugins -----------------------------------------------------------
mkdir -p "$PLUGIN_ROOT"
for i in "${!plugin_rows[@]}"; do
  [[ ${plugin_pick[$i]} == y ]] || continue
  IFS=$'\t' read -r id source commit enabled <<< "${plugin_rows[$i]}"
  target="$PLUGIN_ROOT/$id"

  if [[ -e $target ]]; then
    backup ".config/omarchy/plugins/$id"
    rm -rf "$target"
  fi

  if [[ $source == vendored ]]; then
    cp -a "$PLUGINS_DIR/$id" "$target" && echo "  ok    plugin $id" || { echo "  ERR   plugin $id"; ((errors++)); }
    continue
  fi

  url=${source#git:}
  if git clone -q "$url" "$target" 2>/dev/null \
      && git -C "$target" -c advice.detachedHead=false checkout -q "$commit"; then
    echo "  ok    plugin $id @ ${commit:0:7}"
  else
    echo "  ERR   plugin $id: could not clone $url"
    [[ $url == *TheFlngDutchman* ]] && echo "        (private repo? run 'gh auth login' and 'gh auth setup-git', then re-run)"
    rm -rf "$target"
    ((errors++))
  fi
done

# A plugin is switched on when shell.json places it on the bar or lists it
# under "plugins". Add the ones the installed shell.json does not mention.
shell_json="$HOME/.config/omarchy/shell.json"
for i in "${!plugin_rows[@]}"; do
  [[ ${plugin_pick[$i]} == y ]] || continue
  id=$(cut -f1 <<< "${plugin_rows[$i]}")
  [[ -d $PLUGIN_ROOT/$id ]] || continue
  if [[ -f $shell_json ]] && grep -q "\"$id\"" "$shell_json"; then continue; fi
  omarchy plugin enable "$id" >/dev/null 2>&1 && echo "  ok    enabled $id" || echo "  note  could not enable $id; run 'omarchy plugin enable $id'"
done

# Plugins left out of the install but still named in shell.json would show
# up as missing widgets; switch them off instead.
if [[ -f $shell_json ]]; then
  for i in "${!plugin_rows[@]}"; do
    [[ ${plugin_pick[$i]} == n ]] || continue
    id=$(cut -f1 <<< "${plugin_rows[$i]}")
    if [[ ! -d $PLUGIN_ROOT/$id ]] && grep -q "\"$id\"" "$shell_json"; then
      omarchy plugin disable "$id" >/dev/null 2>&1 && echo "  ok    removed $id from the bar (not installed)"
    fi
  done
fi

# --- 7. Git themes --------------------------------------------------------
if (( install_git_themes )); then
  mkdir -p "$THEME_ROOT"
  for row in "${theme_rows[@]}"; do
    IFS=$'\t' read -r name url commit <<< "$row"
    target="$THEME_ROOT/$name"
    if [[ -d $target ]]; then echo "  skip  theme $name (already installed)"; continue; fi
    if git clone -q "$url" "$target" 2>/dev/null \
        && git -C "$target" -c advice.detachedHead=false checkout -q "$commit"; then
      echo "  ok    theme $name"
    else
      echo "  ERR   theme $name: could not clone $url"
      rm -rf "$target"
      ((errors++))
    fi
  done
fi

# --- 8. Apply -------------------------------------------------------------
echo
(( apply_theme )) && omarchy theme set "$saved_theme" >/dev/null 2>&1 && echo "  ok    theme $saved_theme"
if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE-} ]]; then
  hyprctl reload >/dev/null && echo "  ok    Hyprland reloaded"
  config_errors=$(hyprctl configerrors 2>/dev/null)
  [[ -n $config_errors && $config_errors != *"no errors"* ]] && warn "Hyprland reports config errors:" && echo "$config_errors"
  omarchy restart shell >/dev/null 2>&1 && echo "  ok    shell restarted"
else
  echo "  note  not inside Hyprland: log in, or run 'omarchy restart shell' later"
fi

echo
[[ -d $BACKUP_DIR ]] && echo "Your previous files are in $BACKUP_DIR"
if (( errors )); then warn "Finished with $errors error(s)."; exit 1; fi
bold "Done."
