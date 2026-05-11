#!/bin/bash
# Interactive dotfiles sync — copy between ~/.config and this repo's dotfiles/

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$REPO_DIR/dotfiles"
CONFIG_DIR="$HOME/.config"

# Collect all tracked files relative to dotfiles/
mapfile -t FILES < <(find "$DOTFILES_DIR" -type f | sed "s|$DOTFILES_DIR/||" | sort)

if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "No dotfiles found in $DOTFILES_DIR"
    exit 1
fi

# --- Direction ---
echo ""
echo "Dotfiles sync"
echo "============="
echo ""
echo "  1) Save   — copy FROM ~/.config  TO  repo  (backup your current config)"
echo "  2) Load   — copy FROM repo       TO  ~/.config  (restore to this machine)"
echo ""
read -rp "Choose [1/2]: " direction
[[ "$direction" != "1" && "$direction" != "2" ]] && echo "Cancelled." && exit 0

# --- File selection ---
echo ""
echo "Available files:"
for i in "${!FILES[@]}"; do
    printf "  %3d) %s\n" "$((i+1))" "${FILES[$i]}"
done
echo ""
echo "Enter file numbers separated by spaces, or 'a' for all:"
read -rp "> " selection

if [[ "$selection" == "a" || "$selection" == "A" ]]; then
    selected=("${FILES[@]}")
else
    selected=()
    for n in $selection; do
        idx=$((n - 1))
        if [[ $idx -ge 0 && $idx -lt ${#FILES[@]} ]]; then
            selected+=("${FILES[$idx]}")
        else
            echo "Skipping invalid number: $n"
        fi
    done
fi

[[ ${#selected[@]} -eq 0 ]] && echo "Nothing selected." && exit 0

# --- Confirm ---
echo ""
if [[ "$direction" == "1" ]]; then
    echo "Will copy FROM ~/.config TO repo:"
else
    echo "Will copy FROM repo TO ~/.config:"
fi
for f in "${selected[@]}"; do
    echo "  $f"
done
echo ""
read -rp "Proceed? [y/N]: " confirm
[[ "$confirm" != "y" && "$confirm" != "Y" ]] && echo "Cancelled." && exit 0

# --- Copy ---
errors=0
for f in "${selected[@]}"; do
    if [[ "$direction" == "1" ]]; then
        src="$CONFIG_DIR/$f"
        dst="$DOTFILES_DIR/$f"
    else
        src="$DOTFILES_DIR/$f"
        dst="$CONFIG_DIR/$f"
    fi

    if [[ ! -f "$src" ]]; then
        echo "SKIP (not found): $src"
        ((errors++))
        continue
    fi

    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst" && echo "OK  $f" || { echo "ERR $f"; ((errors++)); }
done

echo ""
if [[ $errors -eq 0 ]]; then
    echo "Done — ${#selected[@]} file(s) synced."
else
    echo "Done with $errors error(s)."
fi
