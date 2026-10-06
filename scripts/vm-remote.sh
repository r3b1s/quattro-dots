#!/usr/bin/env bash
# Explicitly opt-in remote-access setup for an Omarchy VM guest.
# Kept separate from install.sh: each subcommand asks before changing anything.
#
#   ./vm-remote.sh status      report SPICE + session state (read-only)
#   ./vm-remote.sh spice       install vdagent keep-alive drop-in
#   ./vm-remote.sh autologin   enable passwordless SDDM autologin (needs sudo)
#
# SPICE networking note: the guest has no SPICE listener of its own (check with
# `ss -lnt`: no 3389/5900/3128 in the guest). QEMU on the Proxmox host serves
# the display; the guest only sees a virtio serial channel
# (/dev/virtio-ports/com.redhat.spice.0). So there is no guest-side bind
# address or port to restrict, unlike hypr-rdp's --bind. Access control lives
# on the host: Proxmox firewall rule on the SPICE proxy port (3128/tcp,
# source-restricted to your client IP) or a VPN into the host network.
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: vm-remote.sh <command>

Commands:
  status      read-only report: virtio channel, vdagent daemons, Hyprland session
  spice       user-level spice-vdagent keep-alive (links vm/ override, restarts unit)
  autologin   root: SDDM autologin for this user (session up after reboot, no login)

The session entry the live login uses is probed at autologin time and recorded
in the drop-in, so the unattended session matches the interactive one.
EOF
}

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
ok() { printf '    ok: %s\n' "$*"; }
warn() { printf '    missing: %s\n' "$*" >&2; }

REPO="$(cd "$(dirname "$0")/.." && pwd)"
readonly REPO
readonly override_src="$REPO/vm/spice-vdagent-override.conf"
readonly override_dir="$HOME/.config/systemd/user/spice-vdagent.service.d"
readonly override_dst="$override_dir/override.conf"
readonly sddm_conf='/etc/sddm.conf.d/99-quattro-autologin.conf'

# ------------------------------------------------------------------ status --

cmd_status() {
  local fail=0

  if [[ -e /dev/virtio-ports/com.redhat.spice.0 ]]; then
    ok 'virtio SPICE channel present'
  else
    warn 'no SPICE virtio channel (is Display=SPICE on the Proxmox hardware tab?)'
    fail=1
  fi

  if systemctl is-active -q spice-vdagentd; then
    ok 'spice-vdagentd (system) active'
  else
    warn 'spice-vdagentd (system) not active'
    fail=1
  fi

  if systemctl --user is-active -q spice-vdagent 2>/dev/null; then
    ok 'spice-vdagent (user) active (clipboard live)'
  else
    warn "spice-vdagent (user) not active; run '$0 spice'"
    fail=1
  fi

  local lock
  lock="$(find "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr" -maxdepth 2 -name hyprland.lock 2>/dev/null | head -1 || true)"
  if [[ -n "$lock" ]]; then
    ok "Hyprland instance: $(basename "$(dirname "$lock")")"
  else
    warn 'no Hyprland instance found'
    fail=1
  fi

  systemctl --user show -p NRestarts spice-vdagent 2>/dev/null || true
  return "$fail"
}

# ------------------------------------------------------------------- spice --

# User-level drop-in: --user units are per-user, no root needed.
cmd_spice() {
  [[ -f "$override_src" ]] || die "$override_src not found"
  printf 'This links the vdagent keep-alive drop-in and restarts the user unit:\n'
  printf '  %s\n' "$override_dst"
  read -r -p 'Continue? [y/N] ' reply
  [[ "$reply" =~ ^[Yy]([Ee][Ss])?$ ]] || die 'cancelled'

  mkdir -p "$override_dir"
  ln -sf "$override_src" "$override_dst"
  systemctl --user daemon-reload
  # static unit (pulled in by graphical-session.target.wants): start, not
  # enable -- `enable` warns about the missing [Install] section.
  systemctl --user start spice-vdagent
  info 'spice-vdagent started with keep-alive (Restart=always)'
  note 'shared clipboard survives vdagentd restarts now'
}

# ---------------------------------------------------------------- autologin --

# SDDM owns the graphical session here (no getty override, no greetd), and the
# live login uses hyprland.desktop, so autologin targets that entry.
# Root-owned regular file under /etc, not a symlink into the repo: a
# compromised user account must not be able to edit login behaviour.
cmd_autologin() {
  ((EUID == 0)) || die "run with sudo: sudo $0 autologin"
  [[ -n "${SUDO_USER:-}" ]] || die 'SUDO_USER is not set; run via sudo from your user'

  # Probe the Wayland session the interactive login actually uses, so the
  # unattended session matches it instead of hardcoding a guess.
  local session='hyprland.desktop'
  local desktop
  desktop="$(loginctl show-session "$(loginctl list-sessions --no-legend | awk '$3 == "'"${SUDO_USER}"'" && $5 != "-" {print $1; exit}')" -p Desktop --value 2>/dev/null || true)"
  [[ -n "$desktop" && -f "/usr/share/wayland-sessions/$desktop.desktop" ]] && session="$desktop.desktop"

  printf 'This writes %s with autologin for %s (session: %s).\n' "$sddm_conf" "$SUDO_USER" "$session"
  printf 'The Hyprland session comes up on boot with no login.\n'
  read -r -p 'Continue? [y/N] ' reply
  [[ "$reply" =~ ^[Yy]([Ee][Ss])?$ ]] || die 'cancelled'

  install -Dm644 /dev/stdin "$sddm_conf" <<EOF
# Written by quattro-dots scripts/vm-remote.sh; remove to restore login prompt.
[Autologin]
User=$SUDO_USER
Session=$session
EOF

  info "autologin enabled for $SUDO_USER"
  note 'takes effect on next reboot; agents reach the session via hypr-session-env'
}

command_name="${1:-}"
case "$command_name" in
  status) cmd_status ;;
  spice) cmd_spice ;;
  autologin) cmd_autologin ;;
  -h | --help | '') usage; [[ -n "$command_name" ]] || exit 2 ;;
  *) usage >&2; die "unknown command: $command_name" ;;
esac
