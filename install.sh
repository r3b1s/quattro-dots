#!/usr/bin/env bash
#
# install.sh - Idempotent installer for quattro-dots
#
# Copies configuration files and user binaries into place without symlinking.
# Safe to re-run at any time.
#
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
CONFIG_DIR="${CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"

DRY_RUN=0

usage() {
  cat <<EOF
Usage: ./install.sh [OPTIONS]

Idempotently copies dotfiles and scripts into place (~/.config, ~/.local/bin).
Does not create symlinks.

Options:
  -n, --dry-run   Show actions that would be performed without modifying files
  -h, --help      Show this help message
EOF
}

for arg in "$@"; do
  case "$arg" in
    -n|--dry-run)
      DRY_RUN=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      echo "Error: Unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
info() { printf '  %-14s %s\n' "$1" "$2"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }

# Idempotently copy a file:
# 1. Resolves/removes any existing symlink at destination so it becomes a regular file copy.
# 2. Compares content and octal mode.
# 3. Copies and sets permissions only if different or missing.
copy_file() {
  local src="$1"
  local dest="$2"
  local mode="${3:-0644}"

  if [[ ! -f "$src" ]]; then
    echo "Error: source file not found: $src" >&2
    return 1
  fi

  local dest_dir
  dest_dir="$(dirname -- "$dest")"

  if (( DRY_RUN )); then
    if [[ -L "$dest" ]]; then
      info "[symlink->file]" "$dest (would replace symlink with copy)"
    elif [[ -f "$dest" ]] && cmp -s "$src" "$dest"; then
      info "[up-to-date]" "$dest"
    elif [[ -f "$dest" ]]; then
      info "[would-update]" "$dest"
    else
      info "[would-install]" "$dest"
    fi
    return 0
  fi

  mkdir -p "$dest_dir"

  # If destination is a symlink, remove it so we replace it with a regular copy
  if [[ -L "$dest" ]]; then
    rm -f "$dest"
  fi

  local current_mode=""
  if [[ -e "$dest" ]]; then
    current_mode="$(stat -c '%a' "$dest" 2>/dev/null || true)"
  fi

  # Normalize mode for comparison (strip leading 0 if present)
  local norm_mode="${mode#0}"

  if [[ -f "$dest" ]] && cmp -s "$src" "$dest" && [[ "$current_mode" == "$norm_mode" ]]; then
    info "[up-to-date]" "$dest"
  else
    local status="[installed]"
    [[ -f "$dest" ]] && status="[updated]"
    install -m "$mode" "$src" "$dest"
    info "$status" "$dest"
  fi
}

main() {
  log "Installing quattro-dots to $HOME"
  (( DRY_RUN )) && log "(Dry-run mode: no changes will be made)"

  # 1. Local binaries (~/.local/bin)
  log "Installing binaries to $BIN_DIR"
  if [[ -d "$REPO_DIR/bin" ]]; then
    for src in "$REPO_DIR/bin"/*; do
      [[ -f "$src" ]] || continue
      local base
      base="$(basename "$src")"
      [[ "$base" == "AGENTS.md" || "$base" == .* ]] && continue
      copy_file "$src" "$BIN_DIR/$base" 0755
    done
  fi

  # 2. Hyprland configuration (~/.config/hypr)
  log "Installing Hyprland configuration to $CONFIG_DIR/hypr"
  if [[ -d "$REPO_DIR/hypr" ]]; then
    while IFS= read -r -d '' src; do
      local rel="${src#$REPO_DIR/hypr/}"
      copy_file "$src" "$CONFIG_DIR/hypr/$rel" 0644
    done < <(find "$REPO_DIR/hypr" -type f ! -name "AGENTS.md" ! -name ".*" -print0 | sort -z)
  fi

  log "Done! Installation is up to date."
}

main
