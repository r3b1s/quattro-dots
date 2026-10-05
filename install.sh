#!/usr/bin/env bash
# Install quattro-dots user-level configs via symlinks into ~/.config,
# ~/.local/bin, etc.
# Root-level configs are NOT handled here; see root/cfg-root.
#
#   ./install.sh          link configs, then ask what to set up
#   ./install.sh --yes    answer yes to every prompt
#   ./install.sh --no     answer no to every prompt
#   ./install.sh --help   usage
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
HOME_DIR="${HOME:?HOME is not set}"

ASSUME_YES=0
ASSUME_NO=0

usage() {
  cat <<EOF
Usage: install.sh [--yes|--no|--help]

  (no flags)   link configs and prompt for optional setup
  --yes, -y    answer yes to every prompt, no interaction
  --no,  -n    answer no to every prompt, no interaction
  --help, -h   show this message

The symlinking pass is unconditional; only the package, nix and vesktop
setup steps are gated behind prompts.
EOF
}

# gum owns every question so one binary styles all of them. Prompting is
# skipped entirely under --yes/--no, which is what makes the script
# non-interactive there.

confirm() {
  local prompt="$1"
  gum confirm --affirmative "Yes" --negative "No" "$prompt"
}

ask_yes() {
  local prompt="$1"
  ((ASSUME_YES)) && return 0
  ((ASSUME_NO)) && return 1
  confirm "$prompt"
}

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
skip() { printf '  skipped: %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

for arg in "$@"; do
  case "$arg" in
    -y | --yes)
      ASSUME_YES=1
      ;;
    -n | --no)
      ASSUME_NO=1
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "unknown argument: $arg"
      ;;
  esac
done

((ASSUME_YES && ASSUME_NO)) && die "--yes and --no are mutually exclusive"

command -v gum >/dev/null 2>&1 || die "gum is required: https://github.com/charmbracelet/gum"

log "quattro-dots: linking configs into $HOME_DIR"

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

# herdr and qutebrowser write runtime state (logs, sockets, bookmarks, ...)
# next to their config, so link the individual config files rather than the
# whole directory.
link_file "$REPO/herdr/config.toml" "$HOME_DIR/.config/herdr/config.toml"
link_file "$REPO/qutebrowser/config.py" "$HOME_DIR/.config/qutebrowser/config.py"
link_file "$REPO/qutebrowser/vimium.py" "$HOME_DIR/.config/qutebrowser/vimium.py"
link_file "$REPO/qutebrowser/omarchy_theme.py" "$HOME_DIR/.config/qutebrowser/omarchy_theme.py"

# Reload qutebrowser's colours when the omarchy theme changes, and retint
# Vesktop from the same palette.
link_glob "hooks/theme-set.d/*" "$HOME_DIR/.config/omarchy/hooks/theme-set.d"

# Omarchy renders this palette template into the live theme directory on every
# theme change. hooks/theme-set.d/vesktop pairs the result with
# vesktop/discord.css and writes the composed stylesheet into Vesktop's themes
# folder, which is why discord.css is read from the repo rather than linked.
link_file "$REPO/vesktop/palette.css.tpl" "$HOME_DIR/.config/omarchy/themed/quattro-vesktop.palette.css.tpl"

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
  } >>"$BASHRC"
  echo "bashrc: appended quattro-dots managed block."
fi

# Scaffold preferred home directories.
"$REPO/scaffold-dirs.sh"

# --- optional setup -------------------------------------------------------
#
# Packages are named with their repository (chaotic-aur/qutebrowser-git) so
# pacman cannot silently satisfy a request from a different repository: a
# repo-qualified name fails outright when that repo is missing or the package
# is absent from it, rather than falling back to extra/ or the AUR.

installed() { pacman -Qq "$1" >/dev/null 2>&1; }

install_chaotic() {
  local repo="$1" pkg="$2" target="$1/$2"

  installed "$pkg" && {
    log "$pkg is already installed"
    return 0
  }

  if ! pacman -Si "$target" >/dev/null 2>&1; then
    warn "$target is not available; leaving $pkg alone"
    return 1
  fi

  log "installing $target"
  sudo pacman -S --needed --noconfirm -- "$target"
}

setup_chaotic() {
  log "setting up the Chaotic-AUR repository"
  "$REPO/scripts/repo-chaotic-aur.sh" || die "Chaotic-AUR setup failed"
}

install_packages() {
  if ask_yes "Set up the Chaotic-AUR repository?"; then
    setup_chaotic
  else
    skip "Chaotic-AUR repository setup"
  fi

  if ask_yes "Install qutebrowser-git from chaotic-aur?"; then
    install_chaotic chaotic-aur qutebrowser-git || true
  else
    skip "chaotic-aur/qutebrowser-git"
  fi

  if ask_yes "Install vesktop from chaotic-aur?"; then
    install_chaotic chaotic-aur vesktop || true
  else
    skip "chaotic-aur/vesktop"
  fi

  if ask_yes "Install nix from extra?"; then
    install_chaotic extra nix || true
  else
    skip "extra/nix"
  fi

  if ask_yes "Install herdr from omarchy?"; then
    install_chaotic omarchy herdr || true
  else
    skip "omarchy/herdr"
  fi
}

# nix.conf is read by every user but written by root, so it is a root-owned
# regular file, not a symlink into the dotfiles repo. Best practice is
# root:root 0644 in a 0755 directory: readable by all, writable only by root,
# which stops a compromised user account from editing daemon behaviour.
setup_nix() {
  if ! installed nix; then
    if ask_yes "Install nix from extra?"; then
      install_chaotic extra nix || true
    else
      skip "extra/nix"
    fi
  fi

  if ! installed nix; then
    warn "nix is not installed; skipping nix.conf setup"
    return 0
  fi

  log "installing nix.conf"
  sudo install -d -m 0755 /etc/nix
  sudo install -m 0644 -o root -g root "$REPO/nix/nix.conf" /etc/nix/nix.conf

  log "enabling the nix daemon"
  sudo systemctl enable --now nix-daemon.service
}

# Vesktop themes itself through Vencord's theme folder. Omarchy renders
# ~/.config/omarchy/themed/quattro-vesktop.palette.css.tpl into the live theme
# directory on each theme change, and hooks/theme-set.d/vesktop composes it
# with vesktop/discord.css into
# ~/.config/vesktop/themes/quattro-dots.theme.css. Re-applying the current theme
# is what renders it once.
setup_vesktop() {
  local theme_name theme_file

  log "applying the Omarchy palette to Vesktop"
  command -v omarchy >/dev/null 2>&1 || {
    warn "omarchy is not on PATH; Vesktop theming is not wired up"
    return 0
  }

  if [[ -d "$HOME_DIR/.config/vesktop" ]]; then
    theme_file="$HOME_DIR/.config/vesktop/themes/quattro-dots.theme.css"
  elif [[ -d "$HOME_DIR/.config/Vencord" ]]; then
    theme_file="$HOME_DIR/.config/Vencord/themes/quattro-dots.theme.css"
  else
    warn "no Vencord client config found; run Vesktop once so ~/.config/vesktop exists"
    return 0
  fi

  theme_name=$(cat "$HOME_DIR/.local/state/omarchy/current/theme.name" 2>/dev/null || true)
  if [[ -z "$theme_name" ]]; then
    warn "no current omarchy theme; run 'omarchy theme set <theme>' to render Vesktop's theme"
    return 0
  fi

  omarchy theme set "$theme_name" || warn "theme reapply failed; run 'omarchy theme set $theme_name' manually"
  [[ -f "$theme_file" ]] || warn "no theme file was written to $theme_file"
}

if ask_yes "Install packages now?"; then
  install_packages
else
  skip "package installation"
fi

if ask_yes "Configure nix (/etc/nix/nix.conf and the nix daemon)?"; then
  setup_nix
else
  skip "nix configuration"
fi

if ask_yes "Configure Vesktop to follow the Omarchy theme?"; then
  setup_vesktop
else
  skip "vesktop theming"
fi

printf '\n'
log "done"
cat <<EOF

Optional (run manually):
  systemctl --user daemon-reload && systemctl --user enable --now syncthing.service
  sudo DOTS="$REPO" "$REPO/root/cfg-root"
EOF