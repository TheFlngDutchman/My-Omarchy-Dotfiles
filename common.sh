# Shared by install.sh and save.sh. Paths are relative to $HOME and are stored
# in the repo under home/ at the same relative path.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_DIR="$REPO_DIR/home"
PLUGINS_DIR="$REPO_DIR/plugins"
PLUGINS_LIST="$REPO_DIR/plugins.tsv"
THEMES_LIST="$REPO_DIR/themes.tsv"
PLUGIN_ROOT="$HOME/.config/omarchy/plugins"
THEME_ROOT="$HOME/.config/omarchy/themes"

# key | label | installed by default (y/n) | paths
CATEGORIES=(
  "hypr|Hyprland: keybindings, input, look & feel, autostart|y|.config/hypr/hyprland.lua .config/hypr/bindings.lua .config/hypr/input.lua .config/hypr/looknfeel.lua .config/hypr/autostart.lua .config/hypr/hyprsunset.conf .config/hypr/xdph.conf"
  "monitors|Monitor layout (specific to this desktop's screens)|n|.config/hypr/monitors.lua .config/hypr/hyprmoncfg-monitors.lua"
  "shell|Omarchy shell: bar layout, idle/lock times, menu, screensaver art|y|.config/omarchy/shell.json .config/omarchy/shell.toml .config/omarchy/extensions/omarchy-menu.jsonc .config/omarchy/branding .local/state/omarchy/settings/io.github.theflngdutchman.dashboard-dl.json"
  "terminals|Terminals: Alacritty, Foot, Ghostty|y|.config/alacritty/alacritty.toml .config/foot/foot.ini .config/ghostty/config"
  "themes|Custom themes and backgrounds (Red Rising, Pandemonium, ...)|y|.config/omarchy/themes/pandemonium .config/omarchy/themes/red-rising .config/omarchy/themes/wallpaperengine .config/omarchy/backgrounds"
)

# Plugins that should not be switched on by default, with the reason shown.
declare -A PLUGIN_WARNINGS=(
  [io.github.iamfitsum.omarchy-proton-vpn]="rewrites the GNOME keyring 'default' alias every 60 s; broke Brave's saved logins on 2026-09-22"
)

cat_field() { # cat_field <category-line> <1-4>
  cut -d'|' -f"$2" <<< "$1"
}
