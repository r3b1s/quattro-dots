#!/usr/bin/env bash
# Install/uninstall wayvnc (VNC server for wlroots compositors) with TLS auth
# and firewall rules scoped to private LANs + VPN interfaces on Omarchy/Arch.
#
# extra/wayvnc ships no systemd unit, so this script installs its own user
# unit bound to graphical-session.target (the session graph wayvnc needs:
# WAYLAND_DISPLAY + screencopy access come from the user manager for free).
# Credentials are config-file-only (wayvncctl has no password API), so the
# script renders ~/.config/wayvnc/config with a generated password and
# self-signed EC certificate + RSA key -- never symlinks it from the repo.
#
# Headless mode reuses the SDDM autologin session: SDDM logs you in at boot
# (Class=user, seat-active, DRM master granted), uwsm starts YOUR Hyprland
# with YOUR dotfiles, and wayvnc runs as a user unit bound to
# graphical-session.target inside that same session. No second compositor,
# no background-class session, no seat fight: one session, streamed.
# The headless chain is:
# SDDM autologin -> uwsm Hyprland -> WAYVNC output -> wayvnc user unit
#                                               -> VNC viewer -> NetBird (wt0).
#
#   ./remote-access-wayvnc.sh install [--headless] [--yes]
#       default: wayvnc user unit enabled for the session (desktop mode).
#       The desktop Hyprland session is itself uwsm-managed; wayvnc is
#       started inside it, so WAYLAND_DISPLAY and the uwsm activation
#       environment are always present.
#       --headless: unattended mode for a headless host that is never logged
#       into locally. SDDM autologins you at boot (same posture as an
#       encrypted install, where LUKS is the auth boundary); the resulting
#       uwsm Hyprland session IS the stream source -- your hyprland.lua,
#       your dotfiles, no second compositor. wayvnc runs as a user unit
#       bound to graphical-session.target; a script-owned oneshot user unit
#       (Requires= of wayvnc) creates the WAYVNC headless output inside the
#       live session. Core Hyprland config is never touched.
#       install modes are exclusive: desktop mode removes the headless
#       units + autologin; headless mode has no desktop autostart entry
#       (wayvnc is session-bound already, nothing to launch).
#
#   ./remote-access-wayvnc.sh uninstall [--yes]
#       remove everything this script's install created, whichever mode was
#       used: headless setup unit + helper + capture drop-in, SDDM autologin,
#       the wayvnc user unit + config + keys, UFW rules carrying the wayvnc
#       comment, and the wayvnc package itself.
#

usage() {
  cat <<'EOF'
Usage: remote-access-wayvnc.sh install [--headless] [--yes]
       remote-access-wayvnc.sh uninstall [--yes]

Install extra/wayvnc with TLS authentication, open VNC port 5900 in UFW
for private LANs and VPN interfaces, and enable it as a user service in
your Hyprland session; or remove everything install created.

Commands:
  install            install wayvnc (desktop session mode by default)
  uninstall          remove wayvnc + every artifact install created

Options for install:
  --headless         unattended headless mode: SDDM autologin at boot,
                     wayvnc as a user unit in your uwsm Hyprland session
                     (your own Hyprland config) capturing a WAYVNC headless
                     output; physical outputs disabled in that session
  --yes, -y          do not ask for confirmation
  -h, --help         show this message

Options for uninstall:
  --yes, -y          do not ask for confirmation
  -h, --help         show this message
EOF
}

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }

readonly wayvnc_pkg='extra/wayvnc'
readonly wayvnc_unit='wayvnc.service'

readonly vnc_port=5900
readonly private_cidrs=(10.0.0.0/8 172.16.0.0/12 192.168.0.0/16)
readonly vpn_ifaces=(tailscale0 wt0)
readonly ufw_comment='wayvnc'

# Rendered (never symlinked: holds the plaintext VNC password). Layout
# mirrors the wayvnc/config template in this repo; values generated here.
readonly wayvnc_conf_dir="$HOME/.config/wayvnc"
readonly wayvnc_conf="$wayvnc_conf_dir/config"
readonly wayvnc_tls_key="$wayvnc_conf_dir/tls_key.pem"
readonly wayvnc_tls_cert="$wayvnc_conf_dir/tls_cert.pem"
readonly wayvnc_rsa_key="$wayvnc_conf_dir/rsa_key.pem"

readonly wayvnc_unit_src="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/wayvnc/wayvnc.service"
readonly wayvnc_unit_dst="$HOME/.config/systemd/user/$wayvnc_unit"
readonly wayvnc_headless_override_dir="$HOME/.config/systemd/user/${wayvnc_unit}.d"
readonly wayvnc_headless_override="$wayvnc_headless_override_dir/10-headless-capture.conf"

# Headless mode: SDDM autologins the invoking user at boot (same posture as
# an encrypted install, where LUKS is the auth boundary). The resulting uwsm
# Hyprland session is Class=user + seat-active, so Aquamarine gets DRM
# master -- no background-class refusal, no second compositor. wayvnc runs
# as a user unit inside that session; a oneshot user unit creates the
# WAYVNC headless output once the session is up (hyprctl needs a live
# socket, so nothing at install time can do it).
# Decoupled by design: NOTHING in ~/.config/hypr or this repo's hypr/ is
# touched. The output-setup unit is PartOf/BindsTo the wayvnc unit, so it
# only ever runs when wayvnc itself starts inside a live session -- manual
# logins, SSH sessions, and other hosts never see it.
readonly headless_user="$USER"
readonly headless_output_name='WAYVNC'
readonly headless_output_mode='1920x1080@60'
readonly headless_output_scale=1
# Oneshot topology unit + helper, both owned by this script under
# ~/.config (never the repo's hypr/). The unit is started as a dependency
# of wayvnc.service -- no autostart.lua, no require() line, no Lua hook.
readonly headless_setup_unit='wayvnc-headless-output.service'
readonly headless_setup_unit_dst="$HOME/.config/systemd/user/$headless_setup_unit"
readonly headless_setup_outputs="$HOME/.config/wayvnc/setup-outputs.sh"
readonly headless_sddm_conf='/etc/sddm.conf.d/autologin.conf'

command_name="${1:-}"
case "$command_name" in
  -h | --help | help)
    usage
    exit 0
    ;;
  install | uninstall)
    shift
    ;;
  '')
    usage >&2
    die 'no command given; use install or uninstall'
    ;;
  *)
    usage >&2
    die "unknown command: $command_name (use install or uninstall)"
    ;;
esac

headless=0
assume_yes=0
if [[ "$command_name" == install ]]; then
  while (($#)); do
    case "$1" in
      --headless)
        headless=1
        ;;
      -y | --yes)
        assume_yes=1
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        usage >&2
        die "unknown argument for install: $1"
        ;;
    esac
    shift
  done
else
  while (($#)); do
    case "$1" in
      -y | --yes)
        assume_yes=1
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        usage >&2
        die "unknown argument for uninstall: $1"
        ;;
    esac
    shift
  done
fi

if ((EUID == 0)); then
  die 'do not run this script as root; sudo is used for the privileged steps'
fi

for cmd in grep pacman sudo systemctl uwsm; do
  command -v "$cmd" >/dev/null 2>&1 || die "required command was not found: $cmd"
done

confirm() {
  if ((assume_yes)); then
    printf 'Running unattended (--yes).\n'
  else
    read -r -p 'Continue? [y/N] ' reply
    [[ "$reply" =~ ^[Yy]([Ee][Ss])?$ ]] || die 'cancelled'
  fi
}

# ------------------------------------------------------------------ install --

install_wayvnc() {
  info "installing $wayvnc_pkg"
  sudo pacman -S --needed --noconfirm "$wayvnc_pkg"
}

# ----------------------------------------------------------------- firewall --

open_ufw_port_for_private_lans() {
  local proto="$1" port="$2" cidr
  for cidr in "${private_cidrs[@]}"; do
    sudo ufw allow in proto "$proto" from "$cidr" to any port "$port" comment "$ufw_comment" >/dev/null
  done
}

open_ufw_port_for_iface() {
  local iface="$1" proto="$2" port="$3"
  if ip link show "$iface" >/dev/null 2>&1; then
    sudo ufw allow in on "$iface" to any port "$port" proto "$proto" comment "$ufw_comment" >/dev/null
  else
    note "interface $iface not present; skipping its rules"
  fi
}

open_ufw_ports() {
  if ! command -v ufw >/dev/null 2>&1; then
    note 'UFW is not installed; skipping wayvnc firewall rules'
    return 0
  fi

  command -v ip >/dev/null 2>&1 || die 'required command was not found: ip'

  open_ufw_port_for_private_lans tcp "$vnc_port"
  local iface
  for iface in "${vpn_ifaces[@]}"; do
    open_ufw_port_for_iface "$iface" tcp "$vnc_port"
  done

  sudo ufw reload
}
# enable_auth=true requires password + private_key_file + certificate_file
# together; a missing member fails startup, so all three land atomically.
write_wayvnc_config() {
  for cmd in openssl ssh-keygen; do
    command -v "$cmd" >/dev/null 2>&1 || die "required command was not found: $cmd"
  done

  info "rendering $wayvnc_conf with fresh credentials"
  mkdir -p "$wayvnc_conf_dir"
  chmod 700 "$wayvnc_conf_dir"

  # Fresh secrets every install: never reuse, never print twice.
  # Alphanumeric only: base64 padding ('=') and symbols risk confusing
  # wayvnc's key=value parser and shell/vncviewer quoting alike.
  local password host
  password="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)"
  [[ -n "$password" ]] || die 'password generation failed'
  host="$(hostname)"

  # Self-signed EC cert (upstream README recipe); clients pin on first
  # connect. Short-ish lifetime: rotation note printed at the end.
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:secp384r1 \
    -sha384 -days 825 -nodes \
    -keyout "$wayvnc_tls_key" -out "$wayvnc_tls_cert" \
    -subj "/CN=$host" >/dev/null 2>&1

  # RSA-AES key (TOFU, SSH-like); coexists with TLS, client picks.
  rm -f "$wayvnc_rsa_key"
  ssh-keygen -m pem -f "$wayvnc_rsa_key" -t rsa -N '' -C "wayvnc@$host" >/dev/null 2>&1

  chmod 600 "$wayvnc_tls_key" "$wayvnc_rsa_key"

  cat >"$wayvnc_conf" <<EOF
# Rendered by scripts/remote-access-wayvnc.sh; do not symlink into the repo.
# Re-run install to rotate the password and keys.
use_relative_paths=true
address=0.0.0.0
port=$vnc_port
enable_auth=true
username=remote
password=$password
rsa_private_key_file=rsa_key.pem
private_key_file=tls_key.pem
certificate_file=tls_cert.pem
xkb_layout=us
EOF
  chmod 600 "$wayvnc_conf"

  note "VNC username: remote"
  note "VNC password: $password  (shown once -- store it in a password manager)"
  note 'TLS certificate is self-signed; accept/pin it on first connect'
}

# ------------------------------------------------------------------ startup --

enable_wayvnc_unit() {
  [[ -f "$wayvnc_unit_src" ]] || die "unit source not found: $wayvnc_unit_src"
  info "linking $wayvnc_unit_dst"
  mkdir -p "$(dirname "$wayvnc_unit_dst")"
  ln -sf "$wayvnc_unit_src" "$wayvnc_unit_dst"
  systemctl --user daemon-reload
  systemctl --user enable --now "$wayvnc_unit"
}

disable_wayvnc_unit() {
  systemctl --user disable --now "$wayvnc_unit" 2>/dev/null || true
  if [[ -L "$wayvnc_unit_dst" ]]; then
    info "removing unit link $wayvnc_unit_dst"
    rm -f "$wayvnc_unit_dst"
    systemctl --user daemon-reload 2>/dev/null || true
  fi
}

disable_headless_config() {
  # Desktop mode must not leave headless strays: SDDM stays manual, the
  # setup unit + helper go, the capture drop-in goes, the unit loses its
  # output pin (it only ever runs inside a session, so disable --now
  # on the restart below is session-safe). Core Hyprland config is never
  # touched, so there is nothing to unpick there.
  remove_sddm_autologin
  remove_headless_setup_unit
  remove_headless_override
}

# ------------------------------------------------------------------ headless --
#
# SDDM autologin lands you in YOUR Hyprland with YOUR dotfiles; wayvnc runs
# as a user unit bound to graphical-session.target in that same session.
# One compositor, streamed. No second session, no seat fight, no
# XDG_RUNTIME_DIR plumbing: user units inherit the session environment
# (WAYLAND_DISPLAY et al.) from the user manager for free.
# SDDM autologin here mirrors the encrypted-install posture, where the LUKS
# passphrase is the auth boundary; on an unencrypted headless box the
# absence of a disk lock IS the accepted tradeoff.

ensure_headless_prereqs() {
  # The autologin session is seat-active, so logind grants the session ACLs
  # on /dev/uinput itself -- but the input group is a cheap fallback for
  # the window between session start and device probing. Harmless either way.
  # video/render cover the DRM nodes (/dev/dri/card*, renderD*) for the
  # window before the session ACLs land. Needs a re-login (or the
  # post-install reboot, which headless needs anyway) to take effect.
  local group
  for group in input video render; do
    if ! id -nG "$headless_user" | tr ' ' '\n' | grep -qx "$group"; then
      info "adding $headless_user to the $group group"
      sudo usermod -aG "$group" "$headless_user"
    else
      note "$headless_user is already in the $group group"
    fi
  done
  # The setup-outputs helper parses `hyprctl monitors -j`. jq ships on
  # omarchy desktops, but headless-first installs must not assume it.
  if ! command -v jq >/dev/null 2>&1; then
    info 'installing jq (headless output topology helper)'
    sudo pacman -S --needed --noconfirm jq
  fi
}

ensure_headless_session_env() {
  # The headless session IS your desktop session: same ~/.config/hypr
  # (hyprland.lua + your dotfiles), nothing to stage -- but fail fast when
  # the config is absent, or SDDM autologin would land on a fallback
  # compositor.
  if [[ ! -f "$HOME/.config/hypr/hyprland.lua" ]]; then
    die "no ~/.config/hypr/hyprland.lua found; install your dotfiles first"
  fi
  note 'headless session uses your own ~/.config/hypr (hyprland.lua)'
}

write_sddm_autologin() {
  # Permanent autologin (NOT a one-shot provision variant, which deletes
  # itself after first boot). Root-owned regular file, not a repo symlink:
  # a compromised user account must not be able to edit login behaviour.
  info "enabling SDDM autologin for $headless_user"
  sudo tee "$headless_sddm_conf" >/dev/null <<EOF
# Written by scripts/remote-access-wayvnc.sh; remove to restore login prompt.
[Autologin]
User=$headless_user
Session=hyprland-uwsm.desktop
EOF
}

remove_sddm_autologin() {
  if [[ -f "$headless_sddm_conf" ]]; then
    if grep -q 'remote-access-wayvnc.sh' "$headless_sddm_conf" 2>/dev/null; then
      info "removing SDDM autologin $headless_sddm_conf"
      sudo rm -f "$headless_sddm_conf"
    else
      note "$headless_sddm_conf is not ours; leaving it alone"
    fi
  fi
}

write_headless_setup_unit() {
  # Oneshot unit that runs BEFORE wayvnc inside the same user manager:
  # it creates the WAYVNC headless output and disables physicals, then
  # wayvnc starts and enumerates exactly one output. Wired via Requires=
  # in the drop-in below, so it never fires without wayvnc itself.
  # Gated inside the helper on the sddm-autologin logind Service: manual
  # logins are untouched (wayvnc then captures the physical session).
  # Topology uses the native Lua monitor API via `hyprctl eval`: the
  # legacy `hyprctl keyword monitor` string syntax died with the 0.55 Lua
  # migration and silently configures nothing. `hyprctl monitors -j`
  # stays: JSON listing was never legacy syntax.
  # Scale is pinned to 1 explicitly: desktop monitor configs (omarchy
  # scale 1.25+) otherwise inflate the framebuffer and burn encoder.
  # Fully decoupled: nothing in ~/.config/hypr or this repo's hypr/ is
  # touched. No autostart.lua edit, no require() line, no Lua hook.
  info "writing headless setup unit $headless_setup_unit_dst"
  mkdir -p "$(dirname "$headless_setup_unit_dst")"
  cat >"$headless_setup_unit_dst" <<'SETUP_UNIT_EOF'
# Written by scripts/remote-access-wayvnc.sh (install --headless).
# Oneshot: create the WAYVNC headless output before wayvnc enumerates
# outputs. Runs only as a Requires= dependency of wayvnc.service; the
# helper below no-ops unless this is the sddm-autologin session.
[Unit]
Description=WAYVNC headless output for wayvnc
PartOf=__UNIT__
After=graphical-session.target
Before=__UNIT__
[Service]
Type=oneshot
ExecStart=%h/.config/wayvnc/setup-outputs.sh
RemainAfterExit=yes
[Install]
WantedBy=__UNIT__
SETUP_UNIT_EOF
  sed -i "s/__UNIT__/$wayvnc_unit/g" "$headless_setup_unit_dst"
  mkdir -p "$(dirname "$headless_setup_outputs")"
  cat >"$headless_setup_outputs" <<'SETUP_EOF'
#!/bin/sh
# Single-output surgery for the autologin headless session ONLY.
# Invoked by wayvnc-headless-output.service, which runs only as a
# dependency of the wayvnc unit. The gate below checks the session's
# logind Service: sddm-autologin means unattended boot -- reshape
# topology. Anything else (sddm manual login, ssh, existing desktop)
# leaves all outputs alone: disabling a human's only physical output is
# how you get a black screen with a valid stream.
set -eu
if [ "$(loginctl show-session "${XDG_SESSION_ID:-}" -p Service --value 2>/dev/null)" != "sddm-autologin" ]; then
  exit 0
fi
# WAYVNC at pinned mode/scale; create-or-reuse so restarts re-apply.
hyprctl output create headless "__OUTPUT__" || true
hyprctl eval 'hl.monitor({ output = "__OUTPUT__", mode = "__MODE__", position = "0x0", scale = __SCALE__ })'
# Sleep so the mode set lands before the topology change.
sleep 1
hyprctl monitors -j | jq -r --arg keep "__OUTPUT__" '.[] | select(.name != $keep) | .name' |
  while IFS= read -r mon; do
    [ -n "$mon" ] && hyprctl eval "hl.monitor({ output = \"$mon\", disabled = true })"
  done
SETUP_EOF
  sed -i -e "s/__OUTPUT__/$headless_output_name/g" -e "s/__MODE__/$headless_output_mode/" -e "s/__SCALE__/$headless_output_scale/" "$headless_setup_outputs"
  chmod +x "$headless_setup_outputs"
}

remove_headless_setup_unit() {
  if [[ -f "$headless_setup_unit_dst" ]]; then
    info "removing headless setup unit $headless_setup_unit_dst"
    rm -f "$headless_setup_unit_dst"
  fi
  if [[ -f "$headless_setup_outputs" ]]; then
    info "removing headless outputs helper $headless_setup_outputs"
    rm -f "$headless_setup_outputs"
  fi
  systemctl --user daemon-reload 2>/dev/null || true
}


write_headless_override() {
  # Pin capture to the WAYVNC headless output via a drop-in override, and
  # pull in the setup unit: output_name pinning keeps wayvnc off any stray
  # physical output that survives the setup unit. A drop-in keeps the repo
  # unit file pristine.
  info "pinning wayvnc capture to $headless_output_name"
  mkdir -p "$wayvnc_headless_override_dir"
  cat >"$wayvnc_headless_override" <<'OVERRIDE_EOF'
# Written by scripts/remote-access-wayvnc.sh (install --headless).
# Pin capture to the WAYVNC headless output (sole output after the setup
# unit disables physicals). Requires= runs the setup unit first.
[Unit]
Requires=__SETUP_UNIT__
After=__SETUP_UNIT__
[Service]
ExecStart=
ExecStart=/usr/bin/wayvnc --config=%h/.config/wayvnc/config --output=__OUTPUT__ --max-fps=30
OVERRIDE_EOF
  sed -i -e "s/__SETUP_UNIT__/$headless_setup_unit/g" -e "s/__OUTPUT__/$headless_output_name/g" "$wayvnc_headless_override"
}

remove_headless_override() {
  if [[ -f "$wayvnc_headless_override" ]]; then
    info 'removing wayvnc headless capture drop-in'
    rm -f "$wayvnc_headless_override"
    rmdir "$wayvnc_headless_override_dir" 2>/dev/null || true
    systemctl --user daemon-reload 2>/dev/null || true
  fi
}

enable_headless_service() {
  ensure_headless_prereqs
  ensure_headless_session_env
  write_sddm_autologin
  write_headless_setup_unit
  write_headless_override

  if [[ "$(loginctl show-user "$headless_user" --property=Linger --value 2>/dev/null)" != yes ]]; then
    info "enabling linger for $headless_user"
    sudo loginctl enable-linger "$headless_user"
  else
    note "linger already enabled for $headless_user"
  fi

  note "capture output $headless_output_name ($headless_output_mode) is created"
  note 'by the setup unit before wayvnc starts; wayvnc runs as a user unit'
  note 'with the session environment (no display guessing)'
}
# ----------------------------------------------------------------- uninstall --
#
# Removal covers both install modes unconditionally: a mode switch mid-life
# (or a half-failed install) can leave strays from either side.
# Order matters: stop services first (port quiet), then config, firewall,
# package.

delete_ufw_rule() {
  sudo ufw --force delete "$@" >/dev/null 2>&1 || true
}

close_ufw_port_for_private_lans() {
  local proto="$1" port="$2" cidr
  for cidr in "${private_cidrs[@]}"; do
    delete_ufw_rule allow in proto "$proto" from "$cidr" to any port "$port"
  done
}

close_ufw_port_for_iface() {
  local iface="$1" proto="$2" port="$3"
  delete_ufw_rule allow in on "$iface" to any port "$port" proto "$proto"
}

close_ufw_ports() {
  if ! command -v ufw >/dev/null 2>&1; then
    note 'UFW is not installed; skipping firewall cleanup'
    return 0
  fi

  # Comment text is not part of the delete match (ufw deletes by rule spec),
  # so rules this script wrote -- with or without tailscale0/wt0 present at
  # install time -- all match these specs.
  local iface
  close_ufw_port_for_private_lans tcp "$vnc_port"
  for iface in "${vpn_ifaces[@]}"; do
    close_ufw_port_for_iface "$iface" tcp "$vnc_port"
  done

  sudo ufw reload
}

remove_wayvnc_config() {
  if [[ -d "$wayvnc_conf_dir" ]]; then
    info "removing wayvnc config + keys $wayvnc_conf_dir"
    rm -rf "$wayvnc_conf_dir"
  else
    note 'wayvnc config dir is already gone; skipping'
  fi
}

remove_wayvnc_package() {
  if pacman -Qq wayvnc >/dev/null 2>&1; then
    info 'removing the wayvnc package'
    sudo pacman -Rns --noconfirm wayvnc
  else
    note 'wayvnc is not installed; skipping package removal'
  fi
}

cmd_uninstall() {
  printf 'This will remove wayvnc and every artifact install created:\n'
  printf 'SDDM autologin, headless setup unit + helper + capture drop-in,\n'
  printf 'wayvnc user unit, config + TLS keys, UFW rules, and the package.\n'
  printf 'Your account and dotfiles are untouched; core Hyprland config was\n'
  printf 'never modified.\n'
  confirm

  info 'stopping + unlinking the wayvnc user unit'
  remove_headless_override
  disable_wayvnc_unit

  info 'removing SDDM autologin + headless setup unit'
  remove_sddm_autologin
  remove_headless_setup_unit

  info 'removing wayvnc config + keys'
  remove_wayvnc_config

  info 'closing wayvnc firewall ports'
  close_ufw_ports

  remove_wayvnc_package

  printf '\n'
  info 'wayvnc and its install artifacts have been removed.'
}

# ---------------------------------------------------------------------- main --

cmd_install() {
  if ((headless)); then
    printf 'This will install %s, open VNC port %s, and set up\n' "$wayvnc_pkg" "$vnc_port"
    printf 'unattended streaming: SDDM autologin at boot into your Hyprland\n'
    printf 'session (your own config), WAYVNC output via a script-owned\n'
    printf 'setup unit (Requires= of wayvnc, no Hyprland config changes),\n'
  else
    printf 'This will install %s, open VNC port %s, and start it for\n' "$wayvnc_pkg" "$vnc_port"
    printf 'your Hyprland session (TLS auth + user service).\n'
  fi
  confirm

  install_wayvnc

  info 'opening wayvnc firewall ports (private LANs + VPN interfaces only)'
  open_ufw_ports

  info 'rendering wayvnc config + TLS credentials'
  write_wayvnc_config

  if ((headless)); then
    info 'enabling headless streaming (no desktop autostart entry; the user unit is session-bound)'
    enable_wayvnc_unit
    enable_headless_service
    note 'chain: SDDM autologin -> your Hyprland -> WAYVNC output ->'
    note 'wayvnc user unit -> VNC viewer over LAN or NetBird (wt0)'
    note 'reboot to verify: no password prompt, session starts on its own'
    note 'then connect a VNC viewer to <host>:5900 with the printed password'
    note 'TLS certificate is valid for 825 days; re-run install to rotate'
  else
    info 'enabling wayvnc for this Hyprland session'
    disable_headless_config
    remove_headless_override
    enable_wayvnc_unit
    # Drop-in removal changes ExecStart: restart so the running instance
    # sheds the --output pin (enable --now only starts when inactive).
    systemctl --user restart "$wayvnc_unit"
    note 'connect a VNC viewer to <host>:5900 with the printed password'
    note 'TLS certificate is valid for 825 days; re-run install to rotate'
  fi

  printf '\n'
  if ((headless)); then
    info 'wayvnc streams your autologin Hyprland session at boot; port 5900 is open for private LANs, tailscale0 and wt0.'
  else
    info 'wayvnc serves your Hyprland session with TLS auth; port 5900 is open for private LANs, tailscale0 and wt0.'
  fi
}

case "$command_name" in
  install)
    cmd_install
    ;;
  uninstall)
    cmd_uninstall
    ;;
esac
