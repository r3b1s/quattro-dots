#!/usr/bin/env bash
# Install/uninstall Sunshine from LizardByte's official pacman repo and open
# Moonlight streaming ports on Omarchy/Arch.
#
# Fork of /usr/share/omarchy/bin/omarchy-install-service-sunshine. Differences:
# the package is pinned to the [lizardbyte] repository (never the [omarchy]
# copy and never the beta repo), firewall rules also cover netbird's "wt0"
# interface, rules carry the "lizardbyte-sunshine" comment, and the systemd
# unit is addressed by its real name (the package ships no literal
# sunshine.service file, only an Alias= written by enable itself, so the
# upstream `enable sunshine` fails on first run).
# Headless mode reuses the SDDM autologin session: SDDM logs you in at boot
# (Class=user, seat-active, DRM master granted), uwsm starts YOUR Hyprland
# with YOUR dotfiles, and sunshine runs as a user unit bound to
# graphical-session.target inside that same session. No second compositor,
# no background-class session, no seat fight: one session, streamed.
# The headless chain is:
# SDDM autologin -> uwsm Hyprland -> SUNSHINE output -> sunshine user unit
#                                               -> Moonlight -> NetBird (wt0).
#
#   ./remote-access-sunshine.sh install [--headless] [--yes]
#       default: sunshine user unit enabled for the session plus a Hyprland
#       autostart entry, mirroring upstream behaviour.
#       The desktop Hyprland session is itself uwsm-managed; sunshine is
#       started inside it (uwsm-app/autostart scope), so WAYLAND_DISPLAY and
#       the uwsm activation environment are always present.
#       --headless: unattended mode for a headless host that is never logged
#       into locally. SDDM autologins you at boot (same posture as an
#       encrypted install, where LUKS is the auth boundary); the resulting
#       uwsm Hyprland session IS the stream source -- your hyprland.lua,
#       your dotfiles, no second compositor. Sunshine runs as a user unit
#       bound to graphical-session.target; a Hyprland autostart hook creates
#       the SUNSHINE headless output inside the live session.
#       install modes are exclusive: desktop mode removes the headless
#       units + autologin; headless mode removes the desktop autostart entry
#       (it would double-start sunshine next to the user unit).
#
#   ./remote-access-sunshine.sh uninstall [--yes]
#       remove everything this script's install created, whichever mode was
#       used: headless system units (file + wants symlink) if present,
#       desktop user unit + autostart entry, admin webapp launcher + icon,
#       UFW rules carrying the lizardbyte-sunshine comment, and the sunshine
#       package itself.
#

usage() {
  cat <<'EOF'
Usage: remote-access-sunshine.sh install [--headless] [--yes]
       remote-access-sunshine.sh uninstall [--yes]

Install lizardbyte/sunshine, open Moonlight streaming ports in UFW, and
install the Sunshine Admin webapp; or remove everything install created.

Commands:
  install            install sunshine (desktop session mode by default)
  uninstall          remove sunshine + every artifact install created

Options for install:
  --headless         unattended headless mode: SDDM autologin at boot,
                     sunshine as a user unit in your uwsm Hyprland session
                     (your own Hyprland config); no desktop autostart entry
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

readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_helper="$script_dir/repo-lizardbyte-sunshine.sh"

readonly pacman_conf='/etc/pacman.conf'

# Pinned reference: the repo prefix forbids pacman from falling back to the
# [omarchy] copy (or any other repo). lizardbyte-beta is never referenced, so
# the stable build wins even when both LizardByte repos are configured.
readonly sunshine_pkg='lizardbyte/sunshine'

# Real unit name shipped by the package. Upstream enables the "sunshine"
# alias, which does not resolve until enable has created it -- hence
# "Unit sunshine.service does not exist" on first install.
readonly sunshine_unit='app-dev.lizardbyte.app.Sunshine.service'

readonly tcp_ports=(47984 47989 48010)
readonly udp_ports=(5353 47998 47999 48000 48002 48010)
readonly private_cidrs=(10.0.0.0/8 172.16.0.0/12 192.168.0.0/16)
readonly vpn_ifaces=(tailscale0 wt0)
readonly ufw_comment='lizardbyte-sunshine'

readonly admin_app='Sunshine Admin'
readonly admin_url='https://localhost:47990'
readonly admin_icon='/usr/share/sunshine/web/images/logo-sunshine-45.png'
readonly admin_exec="omarchy-launch-webapp $admin_url --ignore-certificate-errors"

readonly autostart_file="$HOME/.config/hypr/autostart.lua"
readonly autostart_entry='o.launch_on_start("sunshine")'

# Headless mode: SDDM autologins the invoking user at boot (same posture as
# an encrypted install, where LUKS is the auth boundary). The resulting uwsm
# Hyprland session is Class=user + seat-active, so Aquamarine gets DRM
# master on the virtio-gpu -- no background-class refusal, no second
# compositor. Sunshine runs as a user unit inside that session; a Hyprland
# autostart hook creates the SUNSHINE headless output once the session is up
# (hyprctl needs a live socket, so nothing at install time can do it).
readonly headless_user="$USER"
readonly headless_output_name='SUNSHINE'
readonly headless_output_mode='1920x1080@60'
readonly headless_output_scale=1
# Autostart hook, loaded by hyprland.lua's require("hypr.autostart") chain
# (same mechanism as the desktop sunshine entry -- but creating the output
# instead of launching an app). Separate file so uninstall removes exactly
# what install added without touching your autostart.lua.
readonly headless_autostart_hook="$HOME/.config/hypr/autostart-sunshine-headless.lua"
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
      --remove-user)
        usage >&2
        die '--remove-user was removed with the dedicated sunshine-stream user; uninstall keeps your account (it is yours)'
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

# --------------------------------------------------------------------- repo --

# The [lizardbyte] section must exist; without it the pinned reference below
# cannot resolve and pacman would fail rather than fall back elsewhere.
ensure_repo() {
  if grep -qE '^[[:space:]]*\[lizardbyte\][[:space:]]*$' "$pacman_conf"; then
    note '[lizardbyte] is already present in pacman.conf'
  else
    [[ -x "$repo_helper" ]] || die "repo helper not found or not executable: $repo_helper"
    info 'adding the LizardByte repositories'
    "$repo_helper"
    # The new repo has no sync database yet; sync now and install immediately
    # after so the tree never sits in a partial-upgrade state.
    sudo pacman -Sy
  fi

  # A present-but-never-synced repo also fails here; one retry covers it.
  if ! pacman -Si "$sunshine_pkg" >/dev/null 2>&1; then
    info 'refreshing package databases'
    sudo pacman -Sy
  fi
  pacman -Si "$sunshine_pkg" >/dev/null 2>&1 ||
    die "package not found after sync: $sunshine_pkg"
}

# ------------------------------------------------------------------ install --

install_sunshine() {
  info "installing $sunshine_pkg (no fallback to other repositories)"
  sudo pacman -S --needed --noconfirm "$sunshine_pkg"

  # Confirm the installed build is LizardByte's, not a same-version shadow
  # from another repo.
  local installed expected
  installed="$(pacman -Q sunshine | awk '{print $2}')"
  expected="$(pacman -Si "$sunshine_pkg" | awk '/^Version/{print $3}')"
  [[ "$installed" == "$expected" ]] ||
    die "installed sunshine $installed is not $sunshine_pkg $expected"
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
    note 'UFW is not installed; skipping Sunshine firewall rules'
    return 0
  fi

  local port iface
  for port in "${tcp_ports[@]}"; do
    open_ufw_port_for_private_lans tcp "$port"
    for iface in "${vpn_ifaces[@]}"; do
      open_ufw_port_for_iface "$iface" tcp "$port"
    done
  done

  for port in "${udp_ports[@]}"; do
    open_ufw_port_for_private_lans udp "$port"
    for iface in "${vpn_ifaces[@]}"; do
      open_ufw_port_for_iface "$iface" udp "$port"
    done
  done

  sudo ufw reload
}

# ------------------------------------------------------------------- webapp --

install_admin_webapp() {
  command -v omarchy-webapp-install >/dev/null 2>&1 ||
    die 'omarchy-webapp-install was not found; is this an Omarchy system?'
  omarchy-webapp-install "$admin_app" "$admin_url" "$admin_icon" "$admin_exec"
}

# ------------------------------------------------------------------ startup --

enable_hyprland_autostart() {
  mkdir -p "$(dirname "$autostart_file")"
  touch "$autostart_file"

  if ! grep -Fxq "$autostart_entry" "$autostart_file"; then
    printf '\n%s\n' "$autostart_entry" >>"$autostart_file"
  fi
}

disable_hyprland_autostart() {
  if [[ -f $autostart_file ]]; then
    sed -i "\|^$autostart_entry$|d" "$autostart_file"
  fi
}

enable_desktop_service() {
  systemctl --user daemon-reload
  systemctl --user enable --now "$sunshine_unit"
}

disable_headless_config() {
  # Desktop mode must not leave headless strays: SDDM stays manual, the
  # autostart hook goes, the user unit is disabled (it only ever runs
  # inside the autologin session, so disable --now is session-safe).
  remove_sddm_autologin
  remove_headless_autostart_hook
  systemctl --user disable --now "$sunshine_unit" 2>/dev/null || true
}

# ------------------------------------------------------------------ headless --
#
# Candidate A: reuse the SDDM autologin session. SDDM logs you in at boot
# (Class=user, seat-active -- the two properties the old background-class
# system units could never get, which is what killed DRM master and crashed
# Hyprland in a 60s loop). uwsm then starts YOUR Hyprland with YOUR
# dotfiles; sunshine runs as a user unit bound to graphical-session.target
# in that same session. One compositor, streamed. No second session, no
# seat fight, no XDG_RUNTIME_DIR plumbing: user units inherit the session
# environment (WAYLAND_DISPLAY et al.) from the user manager for free.
# SDDM autologin here mirrors the encrypted-install posture, where the LUKS
# passphrase is the auth boundary; on an unencrypted headless box the
# absence of a disk lock IS the accepted tradeoff.

ensure_headless_prereqs() {
  # The autologin session is seat-active, so logind grants the session ACLs
  # on /dev/uinput itself -- but the input group is a cheap fallback for
  # the window between session start and device probing. Harmless either way.
  if ! id -nG "$headless_user" | tr ' ' '\n' | grep -qx input; then
    info "adding $headless_user to the input group (uinput access)"
    sudo usermod -aG input "$headless_user"
  else
    note "$headless_user is already in the input group"
  fi
}

ensure_headless_session_env() {
  # The headless session IS your desktop session: same ~/.config/hypr
  # (hyprland.lua + your dotfiles), same Sunshine pairing in
  # ~/.config/sunshine. Nothing to stage -- but fail fast when the config
  # is absent, or SDDM autologin would land on a fallback compositor.
  if [[ ! -f "$HOME/.config/hypr/hyprland.lua" ]]; then
    die "no ~/.config/hypr/hyprland.lua found; install your dotfiles first"
  fi
  note 'headless session uses your own ~/.config/hypr (hyprland.lua)'
}

write_sddm_autologin() {
  # Permanent autologin (NOT the one-shot omarchy-provision variant, which
  # deletes itself after first boot). Same file encrypted installs keep
  # forever; same session name SDDM already remembers for you.
  info "enabling SDDM autologin for $headless_user"
  sudo tee "$headless_sddm_conf" >/dev/null <<EOF
[Autologin]
User=$headless_user
Session=omarchy.desktop
EOF
}

remove_sddm_autologin() {
  if [[ -f "$headless_sddm_conf" ]]; then
    info "removing SDDM autologin $headless_sddm_conf"
    sudo rm -f "$headless_sddm_conf"
  fi
}

write_headless_autostart_hook() {
  # Runs inside the live Hyprland session: hyprland.lua's
  # require("hypr.autostart") chain loads ~/.config/hypr/autostart.lua, and
  # install appends a require of this hook file there -- so hyprctl needs no
  # socket hunt, no HYPRLAND_INSTANCE_SIGNATURE derivation, no poll loop.
  # The compositor is up by definition when this fires. Idempotent
  # create-or-reuse: a session restart re-applies the output instead of
  # failing on a duplicate.
  info "writing headless output hook $headless_autostart_hook"
  cat >"$headless_autostart_hook" <<EOF
-- Headless SUNSHINE output for Sunshine streaming.
-- Written by scripts/remote-access-sunshine.sh (install --headless).
-- Required from autostart.lua; runs once the session is live.
hl.on("hyprland.start", function()
  hl.exec_cmd("hyprctl output create headless $headless_output_name || true; hyprctl keyword monitor \"$headless_output_name,$headless_output_mode,0x0,$headless_output_scale\"")
end)
EOF
  if ! grep -Fq 'require("hypr.autostart-sunshine-headless")' "$autostart_file" 2>/dev/null; then
    printf '\nrequire("hypr.autostart-sunshine-headless")\n' >>"$autostart_file"
  fi
}

remove_headless_autostart_hook() {
  if [[ -f "$headless_autostart_hook" ]]; then
    info "removing headless output hook $headless_autostart_hook"
    rm -f "$headless_autostart_hook"
  fi
  # Remove only the require line install added; your entries stay untouched.
  if [[ -f $autostart_file ]]; then
    sed -i '/^require("hypr\.autostart-sunshine-headless")$/d' "$autostart_file"
  fi
}

enable_headless_sunshine_unit() {
  # The packaged unit is WantedBy=graphical-session.target only -- which is
  # exactly right here: inside the autologin session that target goes
  # active, the user manager starts the unit with the full session
  # environment (WAYLAND_DISPLAY et al.) for free. No XDG_RUNTIME_DIR
  # plumbing, no session.env file, no socket guessing.
  # Addressed by real unit name: the package ships no literal
  # sunshine.service file, only an Alias= written by enable itself.
  # capture/output_name pin the stream to the SUNSHINE headless output via
  # a drop-in override (not CLI -- user units have no CLI): output_name=1
  # is the capture-time index (the connector name is what Sunshine's
  # capture enumeration has historically filtered out; #5087). A drop-in
  # keeps the packaged unit file pristine across upgrades.
  info "enabling sunshine user unit for the autologin session"
  mkdir -p "$HOME/.config/systemd/user/${sunshine_unit}.d"
  cat >"$HOME/.config/systemd/user/${sunshine_unit}.d/10-headless-capture.conf" <<EOF
# Written by scripts/remote-access-sunshine.sh (install --headless).
# Pin capture to the SUNSHINE headless output created by the autostart hook.
[Service]
ExecStart=
ExecStart=/usr/bin/sunshine capture=wlr output_name=1
EOF
  systemctl --user daemon-reload
  systemctl --user enable --now "$sunshine_unit"
}

remove_headless_sunshine_override() {
  local dropin="$HOME/.config/systemd/user/${sunshine_unit}.d/10-headless-capture.conf"
  if [[ -f "$dropin" ]]; then
    info 'removing sunshine headless capture drop-in'
    rm -f "$dropin"
    rmdir "$HOME/.config/systemd/user/${sunshine_unit}.d" 2>/dev/null || true
    systemctl --user daemon-reload 2>/dev/null || true
  fi
}

enable_headless_service() {
  ensure_headless_prereqs
  ensure_headless_session_env
  write_sddm_autologin
  write_headless_autostart_hook
  enable_headless_sunshine_unit

  if [[ "$(loginctl show-user "$headless_user" --property=Linger --value 2>/dev/null)" != yes ]]; then
    info "enabling linger for $headless_user"
    sudo loginctl enable-linger "$headless_user"
  else
    note "linger already enabled for $headless_user"
  fi

  note "capture output $headless_output_name ($headless_output_mode) is created"
  note 'by the Hyprland autostart hook at session start; sunshine runs as a'
  note 'user unit with the session environment (no display guessing)'
}
# ----------------------------------------------------------------- uninstall --
#
# Removal covers both install modes unconditionally: headless units and the
# desktop autostart/user-unit cannot usefully coexist, but a mode switch
# mid-life (or a half-failed install) can leave strays from either side.
# Order matters: stop services first (ports quiet), then webapp, firewall,
# package. The repo section stays: removing shared pacman.conf state would
# break other LizardByte installs.

disable_desktop_service() {
  # The shipped unit carries Alias=sunshine.service only after a successful
  # enable; disable by the real name, fall back to the alias for trees the
  # upstream script once enabled.
  systemctl --user disable --now "$sunshine_unit" 2>/dev/null || true
  systemctl --user disable --now sunshine.service 2>/dev/null || true
}

remove_headless_units() {
  # Legacy only: pre-candidate-A installs wrote system units + a helper
  # script. Candidate A owns no system files, so on a fresh host this finds
  # nothing; on a previously-tested host it sweeps the old stack so the
  # autologin session is the only compositor.
  local unit
  for unit in sunshine-streamer.service sunshine-headless.service; do
    if systemctl is-active --quiet "$unit" 2>/dev/null; then
      info "stopping legacy $unit"
      sudo systemctl stop "$unit"
    fi
    if systemctl is-enabled --quiet "$unit" 2>/dev/null; then
      info "disabling legacy $unit"
      sudo systemctl disable "$unit"
    fi
    if [[ -f "/etc/systemd/system/$unit" ]]; then
      info "removing legacy /etc/systemd/system/$unit"
      sudo rm -f "/etc/systemd/system/$unit"
    fi
  done
  if [[ -f '/usr/local/bin/sunshine-headless-output.sh' ]]; then
    info 'removing legacy /usr/local/bin/sunshine-headless-output.sh'
    sudo rm -f '/usr/local/bin/sunshine-headless-output.sh'
  fi
  sudo systemctl daemon-reload 2>/dev/null || true
  sudo systemctl reset-failed sunshine-streamer.service sunshine-headless.service 2>/dev/null || true
}

remove_admin_webapp() {
  if command -v omarchy-webapp-remove >/dev/null 2>&1; then
    omarchy-webapp-remove "$admin_app" 2>/dev/null || true
  else
    note 'omarchy-webapp-remove not found; skipping webapp removal'
  fi
}

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
  local port iface
  for port in "${tcp_ports[@]}"; do
    close_ufw_port_for_private_lans tcp "$port"
    for iface in "${vpn_ifaces[@]}"; do
      close_ufw_port_for_iface "$iface" tcp "$port"
    done
  done

  for port in "${udp_ports[@]}"; do
    close_ufw_port_for_private_lans udp "$port"
    for iface in "${vpn_ifaces[@]}"; do
      close_ufw_port_for_iface "$iface" udp "$port"
    done
  done

  sudo ufw reload
}

remove_sunshine_package() {
  if pacman -Qq sunshine >/dev/null 2>&1; then
    info 'removing the sunshine package'
    sudo pacman -Rns --noconfirm sunshine
  else
    note 'sunshine is not installed; skipping package removal'
  fi
}

cmd_uninstall() {
  printf 'This will remove sunshine and every artifact install created:\n'
  printf 'SDDM autologin, headless autostart hook, sunshine user unit,\n'
  printf 'desktop autostart entry, admin webapp, UFW rules, and the package.\n'
  printf 'Your account and dotfiles are untouched.\n'
  confirm

  info 'removing legacy headless system units (if present)'
  remove_headless_units

  info 'removing SDDM autologin + headless autostart hook'
  remove_sddm_autologin
  remove_headless_autostart_hook
  remove_headless_sunshine_override

  info 'removing desktop user unit + Hyprland autostart entry'
  disable_desktop_service
  disable_hyprland_autostart

  info 'removing Sunshine admin web app'
  remove_admin_webapp

  info 'closing Sunshine firewall ports'
  close_ufw_ports

  remove_sunshine_package

  printf '\n'
  info 'Sunshine and its install artifacts have been removed.'
}

# ---------------------------------------------------------------------- main --

cmd_install() {
  if ((headless)); then
    printf 'This will install %s, open its streaming ports, and set up\n' "$sunshine_pkg"
    printf 'unattended streaming: SDDM autologin at boot into your Hyprland\n'
    printf 'session (your own config), SUNSHINE output via autostart hook,\n'
    printf 'sunshine as a user unit inside that session.\n'
  else
    printf 'This will install %s, open its streaming ports, and start it for\n' "$sunshine_pkg"
    printf 'your Hyprland session (user service + autostart entry).\n'
  fi
  confirm

  ensure_repo
  install_sunshine

  info 'opening Sunshine firewall ports'
  open_ufw_ports

  info 'installing Sunshine admin web app'
  install_admin_webapp

  if ((headless)); then
    info 'enabling headless streaming (removing any desktop autostart entry)'
    disable_hyprland_autostart
    enable_headless_service
    note 'admin UI has been installed but not launched; open it after pairing:'
    note "  $admin_url (self-signed certificate warning is expected)"
    note 'chain: SDDM autologin -> your Hyprland -> SUNSHINE output ->'
    note 'sunshine user unit -> Moonlight over NetBird (wt0)'
    note 'reboot to verify: no password prompt, session starts on its own'
  else
    info 'enabling Sunshine for this Hyprland session'
    disable_headless_config
    enable_desktop_service
    enable_hyprland_autostart
    if command -v omarchy-launch-webapp >/dev/null 2>&1; then
      # shellcheck disable=SC2086
      $admin_exec >/dev/null 2>&1 &
    fi
  fi

  printf '\n'
  if ((headless)); then
    info 'Sunshine is installed from [lizardbyte] and streams your autologin Hyprland session at boot; Moonlight ports are open for private LANs, tailscale0 and wt0.'
  else
    info 'Sunshine is installed from [lizardbyte] with Moonlight ports open for private LANs, tailscale0 and wt0.'
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
