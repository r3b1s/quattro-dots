#!/usr/bin/env bash
# Install quattro-dots user-level configs via symlinks into ~/.config, ~/.local/bin, etc.
# Root-level configs are NOT handled here; see root/cfg-root.
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
HOME_DIR="${HOME:?HOME is not set}"

link_file() {
  local src="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"

  if [[ -e "$dest" || -L "$dest" ]]; then
    if [[ -d "$dest" && ! -L "$dest" ]]; then
      if [[ -n "$(ls -A "$dest" 2>/dev/null)" ]]; then
        echo "error: $dest is a non-empty directory; not overwriting." >&2
        return 1
      fi
      rmdir "$dest"
    else
      rm -f "$dest"
    fi
  fi

  ln -s "$src" "$dest"
  echo "linked $dest -> $src"
}

link_glob() {
  local src_glob="$1" dest_dir="$2"
  local src dest base
  for src in "$REPO"/$src_glob; do
    [[ -e "$src" || -L "$src" ]] || continue
    base="$(basename "$src")"
    link_file "$src" "$dest_dir/$base"
  done
}

link_glob "hypr/*.lua" "$HOME_DIR/.config/hypr"
link_glob "hypr/scripts/*" "$HOME_DIR/.config/hypr/scripts"
link_file "$REPO/voxtype/config.toml" "$HOME_DIR/.config/voxtype/config.toml"
link_file "$REPO/tmux/tmux.conf" "$HOME_DIR/.config/tmux/tmux.conf"
link_file "$REPO/starship/starship.toml" "$HOME_DIR/.config/starship.toml"
link_file "$REPO/mise/config.toml" "$HOME_DIR/.config/mise/config.toml"

# herdr and qutebrowser write runtime state (logs, sockets, bookmarks, ...)
# next to their config, so link the individual config files rather than the
# whole directory.
link_file "$REPO/herdr/config.toml" "$HOME_DIR/.config/herdr/config.toml"
link_file "$REPO/qutebrowser/config.py" "$HOME_DIR/.config/qutebrowser/config.py"
link_file "$REPO/qutebrowser/vimium.py" "$HOME_DIR/.config/qutebrowser/vimium.py"
link_file "$REPO/qutebrowser/omarchy_theme.py" "$HOME_DIR/.config/qutebrowser/omarchy_theme.py"

# Reload qutebrowser's colours when the omarchy theme changes.
link_glob "hooks/theme-set.d/*" "$HOME_DIR/.config/omarchy/hooks/theme-set.d"

# nvim is linked as a directory: its lua/plugins/theme.lua is itself a symlink
# into the live omarchy theme, so the tree has to be followed as one unit.
link_file "$REPO/nvim" "$HOME_DIR/.config/nvim"

link_glob "shell/*" "$HOME_DIR/.config/shell"
link_glob "bin/*" "$HOME_DIR/.local/bin"
link_glob "systemd/environment.d/*.conf" "$HOME_DIR/.config/environment.d"
link_file "$REPO/syncthing/syncthing.service" "$HOME_DIR/.config/systemd/user/syncthing.service"

# Idempotent ~/.bashrc managed block.
BASHRC="$HOME_DIR/.bashrc"
STAMP="# >>> quattro-dots >>>"
if [[ -f "$BASHRC" ]] && grep -qF "$STAMP" "$BASHRC"; then
  echo "bashrc: quattro-dots block already present; skipping."
else
  touch "$BASHRC"
  {
    echo "# >>> quattro-dots >>>"
    echo '[[ -r "$HOME/.config/shell/init.sh" ]] && source "$HOME/.config/shell/init.sh"'
    echo "# <<< quattro-dots <<<"
  } >> "$BASHRC"
  echo "bashrc: appended quattro-dots managed block."
fi

# Scaffold preferred home directories.
"$REPO/scaffold-dirs.sh"

echo
echo "Optional (run manually):"
echo "  systemctl --user daemon-reload && systemctl --user enable --now syncthing.service"
echo "  sudo DOTS=\"$REPO\" \"$REPO/root/cfg-root\""
