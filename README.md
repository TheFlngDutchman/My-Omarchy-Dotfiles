# My Omarchy Dotfiles

My [Omarchy](https://omarchy.org) setup: Hyprland config, the Omarchy shell bar
and menu, terminals, custom themes, and every shell plugin I use. It includes an
interactive installer, so a fresh machine can be set up in one go.

## Install on a machine

```bash
git clone https://github.com/TheFlngDutchman/My-Omarchy-Dotfiles.git ~/My-Omarchy-Dotfiles
cd ~/My-Omarchy-Dotfiles
./install.sh           # asks about each part
./install.sh --yes     # takes the recommended choices without asking
```

The installer asks, in order:

1. **Which configs to install:**
   - Hyprland
   - Monitor layout (off by default, because it only fits my desktop's screens)
   - Omarchy shell and menu
   - Terminals
   - Themes
2. **Which shell plugins to install.** Plugins I have switched on come
   preselected. Type their numbers to change the selection.
3. Whether to clone the git themes, and whether to switch to my current theme.

Before it overwrites anything, it copies the old file to
`~/.local/state/omarchy-dotfiles-backup/<date>/`. At the end it reloads
Hyprland and restarts the shell.

Some plugins live in my private repos (App Grid, Indicators Drawer). Cloning
them needs `gh auth login` and `gh auth setup-git` first. If you skip that, the
installer reports those two and installs everything else.

## Save changes from a machine

```bash
./save.sh
```

This copies the current configs into the repo and records each plugin's git URL
and exact commit. Plugins that exist only locally are copied into `plugins/`.
It shows what changed and asks before committing and pushing.

## What's in here

| Path | Contents |
| --- | --- |
| `home/` | config files, at the same path they have under `~` |
| `plugins.tsv` | every shell plugin: git URL + pinned commit (or `vendored`), and whether it's on |
| `plugins/` | plugins that aren't in any git repo: Blobs, My Network |
| `themes.tsv` | themes installed from git, pinned to a commit |
| `current-theme` | the theme to switch to after installing |
| `common.sh` | which files belong to which category (edit this to add files) |

## Not included, on purpose

- Weather location. It's your home town's coordinates, and this repo is public.
- The Wi-Fi hotspot config. It's machine-specific, and the passphrase lives in
  NetworkManager anyway.
- Backup files (`*.bak*`).
- Omarchy's own stock hook samples.

The Proton VPN plugin is listed but off by default. Every 60 seconds it rewrites
the GNOME keyring's `default` alias, which broke Brave's saved logins once.
