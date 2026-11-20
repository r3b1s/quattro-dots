#!/usr/bin/env bash
#
# opt/gpu-session/install.sh — Idempotent opt-in installer for dual-GPU
# session switching (RX 580 desktop + RTX 3070 AI VRAM isolation) and the
# Omarchy Quickshell KeyboardPanel plugin (t.gpu-session).
#
# Uses direct file copies (no symlinks), matching quattro-dots' install.sh.
# Safe to re-run at any time.
#
set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPO_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd -P)"
readonly CONFIG_DIR="${CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}}"
readonly BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
readonly PLUGIN_ID="t.gpu-session"
readonly PLUGIN_SRC="$SCRIPT_DIR/plugin/$PLUGIN_ID"
readonly PLUGIN_DST="$CONFIG_DIR/omarchy/plugins/$PLUGIN_ID"
readonly HYPR_MAIN_SRC="$REPO_DIR/hypr/hyprland.lua"
readonly HYPR_MAIN_DST="$CONFIG_DIR/hypr/hyprland.lua"
readonly HYPR_GPU_SRC="$SCRIPT_DIR/hypr/gpu.lua"
readonly HYPR_GPU_DST="$CONFIG_DIR/hypr/gpu.lua"
readonly HYPR_MONITORS="$CONFIG_DIR/hypr/monitors.lua"
readonly ENV_FILE="$CONFIG_DIR/uwsm/env.d/10-gpu.conf"
readonly SHELL_JSON="$CONFIG_DIR/omarchy/shell.json"

DRY_RUN=0
REMOVE=0
PLUGIN_CHANGED=0

usage() {
  cat <<'EOF'
Usage: ./opt/gpu-session/install.sh [OPTIONS]

Idempotently installs gpu-session (~/.local/bin/gpu-session), the t.gpu-session
Omarchy shell plugin (~/.config/omarchy/plugins/t.gpu-session/), UWSM GPU
environment configuration (~/.config/uwsm/env.d/10-gpu.conf), and host-local
Hyprland GPU overrides (~/.config/hypr/gpu.lua) and EDID monitor rules.

Options:
  -n, --dry-run   Show planned actions without modifying files
      --remove    Remove gpu-session, plugin, UWSM config, and hypr/gpu.lua
  -h, --help      Show this help message
EOF
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
info() { printf '  %-16s %s\n' "$1" "$2"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }

if [[ "$(id -u)" -eq 0 ]]; then
  die "run as your normal user, not root"
fi

while (( $# > 0 )); do
  case "$1" in
    -n|--dry-run)
      DRY_RUN=1
      shift
      ;;
    --remove)
      REMOVE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "unknown argument: $1"
      ;;
  esac
done

copy_file() {
  local src="$1"
  local dest="$2"
  local mode="${3:-0644}"

  [[ -f "$src" ]] || die "source file not found: $src"

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

  mkdir -p "$(dirname -- "$dest")"
  if [[ -L "$dest" ]]; then
    rm -f "$dest"
  fi

  local current_mode=""
  if [[ -e "$dest" ]]; then
    current_mode="$(stat -c '%a' "$dest" 2>/dev/null || true)"
  fi
  local norm_mode="${mode#0}"

  if [[ -f "$dest" ]] && cmp -s "$src" "$dest" && [[ "$current_mode" == "$norm_mode" ]]; then
    info "[up-to-date]" "$dest"
  else
    local status="[installed]"
    if [[ -f "$dest" ]]; then
      status="[updated]"
    fi
    install -m "$mode" "$src" "$dest"
    info "$status" "$dest"
  fi
}

install_plugin_files() {
  if [[ -L "$PLUGIN_DST" ]]; then
    if (( DRY_RUN )); then
      info "[symlink->dir]" "$PLUGIN_DST (would replace symlink with directory)"
    else
      rm -f "$PLUGIN_DST"
      mkdir -p "$PLUGIN_DST"
      PLUGIN_CHANGED=1
    fi
  fi

  while IFS= read -r -d '' src; do
    local rel="${src#$PLUGIN_SRC/}"
    local dest="$PLUGIN_DST/$rel"
    local before_cmp=0
    if [[ -f "$dest" ]] && cmp -s "$src" "$dest" && [[ "$(stat -c '%a' "$dest" 2>/dev/null || true)" == "644" ]]; then
      before_cmp=1
    fi
    copy_file "$src" "$dest" 0644
    if (( before_cmp == 0 )); then
      PLUGIN_CHANGED=1
    fi
  done < <(find "$PLUGIN_SRC" -type f ! -name ".*" -print0 | sort -z)
}

ensure_uwsm_env() {
  local target="${GPU_SESSION_DEFAULT:-rx580}"
  if [[ -r "$ENV_FILE" ]]; then
    local line
    line="$(grep -m1 '^# quattro-dots gpu-session: target=' "$ENV_FILE" 2>/dev/null || true)"
    case "${line#*=}" in
      rx580|rtx3070) target="${line#*=}" ;;
    esac
  fi

  local cli="$BIN_DIR/gpu-session"
  if (( DRY_RUN )) && [[ ! -x "$cli" ]]; then
    cli="$SCRIPT_DIR/bin/gpu-session"
  fi

  if (( DRY_RUN )); then
    "$cli" "$target" --dry-run
  else
    "$cli" "$target" >/dev/null
    info "[configured]" "$ENV_FILE (target=$target)"
  fi
}

sync_hypr_gpu() {
  copy_file "$HYPR_GPU_SRC" "$HYPR_GPU_DST" 0644
  if [[ -f "$HYPR_MAIN_SRC" ]]; then
    copy_file "$HYPR_MAIN_SRC" "$HYPR_MAIN_DST" 0644
  fi
}

sync_monitors_edid() {
  if [[ ! -f "$HYPR_MONITORS" ]]; then
    warn "$HYPR_MONITORS not found; skipping EDID monitor conversion"
    return 0
  fi

  local tmp
  tmp="$(mktemp)"

  awk '
    /^[[:space:]]*hl\.monitor\(/ {
      gsub(/output[[:space:]]*=[[:space:]]*"DP-6"/, "output = \"desc:HP Inc. HP E233 CNC74320LH\"")
      gsub(/output[[:space:]]*=[[:space:]]*"DP-5"/, "output = \"desc:HP Inc. HP E233 CNC7431ZWK\"")
    }
    { print }
  ' "$HYPR_MONITORS" > "$tmp"

  if cmp -s "$tmp" "$HYPR_MONITORS"; then
    rm -f "$tmp"
    info "[up-to-date]" "$HYPR_MONITORS (EDID monitor match)"
    return 0
  fi

  if (( DRY_RUN )); then
    rm -f "$tmp"
    info "[would-update]" "$HYPR_MONITORS (replace DP-6/DP-5 with desc: EDID selectors)"
    return 0
  fi

  cp "$HYPR_MONITORS" "${HYPR_MONITORS}.bak.$(date +%s)"
  install -m 0644 "$tmp" "$HYPR_MONITORS"
  rm -f "$tmp"
  info "[updated]" "$HYPR_MONITORS (EDID monitor match)"
}

plugin_on_bar() {
  [[ -f "$SHELL_JSON" ]] || return 1
  jq -e --arg id "$PLUGIN_ID" '
    (.bar.layout // {}) | to_entries | any(
      (.value | type) == "array" and any(.value[]; (if type == "object" then .id else . end) == $id)
    )
  ' "$SHELL_JSON" >/dev/null 2>&1
}

register_shell_plugin() {
  if (( DRY_RUN )); then
    if plugin_on_bar; then
      info "[up-to-date]" "omarchy bar already includes $PLUGIN_ID"
    else
      info "[would-put]" "omarchy bar put $PLUGIN_ID --section right"
    fi
    return 0
  fi

  if command -v omarchy-plugin-validate >/dev/null 2>&1; then
    omarchy-plugin-validate "$PLUGIN_DST"
    info "[validated]" "$PLUGIN_DST"
  fi

  if pgrep -x quickshell >/dev/null 2>&1 && command -v omarchy-shell >/dev/null 2>&1; then
    omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
    if plugin_on_bar; then
      if (( PLUGIN_CHANGED )); then
        omarchy-shell shell reloadPlugins >/dev/null 2>&1 || true
        info "[reloaded]" "$PLUGIN_ID in omarchy-shell"
      else
        info "[up-to-date]" "omarchy bar ($PLUGIN_ID)"
      fi
    elif command -v omarchy-bar >/dev/null 2>&1; then
      omarchy-bar put "$PLUGIN_ID" --section right >/dev/null
      info "[placed]" "$PLUGIN_ID on bar (section: right)"
    fi
  else
    warn "omarchy-shell is not running; run 'omarchy bar put $PLUGIN_ID --section right' once inside Hyprland"
  fi
}

remove_path() {
  local target="$1"
  if [[ -e "$target" || -L "$target" ]]; then
    if (( DRY_RUN )); then
      info "[would-remove]" "$target"
    else
      rm -rf "$target"
      info "[removed]" "$target"
    fi
  else
    info "[absent]" "$target"
  fi
}

do_remove() {
  log "Removing quattro-dots opt/gpu-session from $HOME"
  if (( DRY_RUN )); then
    log "(Dry-run mode: no changes will be made)"
  fi

  if (( ! DRY_RUN )) && pgrep -x quickshell >/dev/null 2>&1 && command -v omarchy-shell >/dev/null 2>&1; then
    omarchy-shell shell setPluginEnabled "$PLUGIN_ID" false >/dev/null 2>&1 || true
  fi

  remove_path "$PLUGIN_DST"

  if (( ! DRY_RUN )) && pgrep -x quickshell >/dev/null 2>&1 && command -v omarchy-shell >/dev/null 2>&1; then
    omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  fi

  if [[ -f "$SHELL_JSON" ]] && plugin_on_bar; then
    if (( DRY_RUN )); then
      info "[would-update]" "$SHELL_JSON (remove $PLUGIN_ID from bar layout)"
    else
      local tmp
      tmp="$(mktemp)"
      jq --arg id "$PLUGIN_ID" '
        .bar.layout |= with_entries(
          if (.value | type) == "array" then
            .value |= map(select((if type == "object" then .id else . end) != $id))
          else . end
        )
      ' "$SHELL_JSON" > "$tmp"
      install -m 0644 "$tmp" "$SHELL_JSON"
      rm -f "$tmp"
      info "[updated]" "$SHELL_JSON (removed $PLUGIN_ID)"
    fi
  fi

  remove_path "$BIN_DIR/gpu-session"
  remove_path "$ENV_FILE"
  remove_path "$HYPR_GPU_DST"

  info "[note]" "$HYPR_MONITORS EDID rules were left intact (safe on all GPUs)"
  log "Removal complete."
}

do_install() {
  log "Installing quattro-dots opt/gpu-session to $HOME"
  if (( DRY_RUN )); then
    log "(Dry-run mode: no changes will be made)"
  fi

  log "Installing CLI binary"
  copy_file "$SCRIPT_DIR/bin/gpu-session" "$BIN_DIR/gpu-session" 0755

  log "Installing Omarchy shell plugin ($PLUGIN_ID)"
  install_plugin_files

  log "Configuring UWSM GPU environment"
  ensure_uwsm_env

  log "Configuring Hyprland GPU overrides and EDID monitors"
  sync_hypr_gpu
  sync_monitors_edid

  log "Registering shell plugin"
  register_shell_plugin

  log "Done!"
}

if (( REMOVE )); then
  do_remove
else
  do_install
fi
