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
# Headless mode additionally wires Sunshine into a uwsm-managed Hyprland
# session that starts at boot, so capture always has a compositor.
# The headless compositor and sunshine run as *system* units as the invoking
# user (no dedicated account): this box is never logged into locally, so
# there is no desktop session to collide with -- and the whole point is
# streaming YOUR primary omarchy configuration, dotfiles and all. A separate
# user would stream a stranger's bare desktop.
# The headless Hyprland instance is a full persistent session:
# Hyprland -> Moonlight (Sunshine) -> NetBird (wt0).
#
#   ./remote-access-sunshine.sh install [--headless] [--yes]
#       default: sunshine user unit enabled for the session plus a Hyprland
#       autostart entry, mirroring upstream behaviour.
#       The desktop Hyprland session is itself uwsm-managed; sunshine is
#       started inside it (uwsm-app/autostart scope), so WAYLAND_DISPLAY and
#       the uwsm activation environment are always present.
#       --headless: unattended mode for a headless host that is never logged
#       into locally. No autostart.lua entry (nothing ever starts a desktop
#       session to fire it). Instead headless Hyprland + sunshine run as
#       system units as YOU at boot, with your own ~/.config/hypr:
#         sunshine-headless.service   uwsm-managed Hyprland on a headless
#                                     output (created at session start,
#                                     1920x1080), restarted on failure, part
#                                     of graphical.target
#         sunshine-streamer.service   sunshine itself (After/Requires the
#                                     compositor, same XDG_RUNTIME_DIR), also
#                                     restarted on failure
#       linger is enabled for your account so the units survive logout.
#       install modes are exclusive: each run installs its own startup hook
#       and disables the other one (headless units are stopped/disabled in
#       desktop mode, the autostart entry is removed in headless mode).
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
  --headless         unattended headless mode for a host that is never
                     logged into locally: uwsm-managed headless Hyprland +
                     sunshine as system units at boot running as you, with
                     your own Hyprland config; no autostart entry
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

# Headless session identity: the invoking user. The headless stack streams
# YOUR desktop -- your ~/.config/hypr, your dotfiles, your Sunshine pairing.
# NOTE: $USER is baked at install time (the account running install), not at
# boot: systemd has no $USER in system units, so the value is expanded into
# the unit files below. Re-run install after `su` to a different account if
# the box changes hands.
readonly headless_user="$USER"
readonly headless_unit_prefix='sunshine'
readonly headless_compositor_unit="${headless_unit_prefix}-headless.service"
readonly headless_streamer_unit="${headless_unit_prefix}-streamer.service"
readonly headless_runtime_leaf="sunshine-${USER}"
readonly headless_runtime_dir="/run/${headless_runtime_leaf}"
readonly headless_output_script='/usr/local/bin/sunshine-headless-output.sh'
# Single-writer record of the live session: the output helper writes
# WAYLAND_DISPLAY=<socket> here once the Hyprland socket exists; the
# streamer reads it via EnvironmentFile=. One ground truth, no guessing.
readonly headless_session_env_file="${headless_runtime_dir}/session.env"

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

disable_headless_services() {
  # Desktop mode must not leave the unattended stack running next to the
  # session instance: two servers would fight over ports and encoders.
  local unit
  for unit in "$headless_streamer_unit" "$headless_compositor_unit"; do
    if systemctl is-enabled --quiet "$unit" 2>/dev/null; then
      sudo systemctl disable --now "$unit"
    fi
  done
}

# ------------------------------------------------------------------ headless --
#
# Boot stack, as the invoking user ($headless_user):
#
#   graphical.target
#     -> sunshine-headless.service (uwsm-managed Hyprland, headless output,
#        your own ~/.config/hypr)
#     -> sunshine-streamer.service (sunshine, After/Requires the compositor)
#
# Why uwsm instead of bare `Hyprland`: the desktop session is uwsm-managed
# (uwsm-app scopes, activation environment, XDG autostart, clean shutdown),
# and Sunshine's wlr capture inherits WAYLAND_DISPLAY from the uwsm session
# environment. A bare compositor process outside uwsm would leave sunshine
# guessing at the socket and skip the session lifecycle the desktop path
# relies on.
#
# Why system units + linger: systemd --user enable --now sunshine solves the
# "Unit sunshine.service does not exist" alias bug but still starts
# sunshine with no compositor behind it on a headless boot. The headless
# compositor must exist first, ordered before the streamer, in the same
# runtime dir -- which is what these two units express.

ensure_headless_prereqs() {
  # Sunshine drives virtual keyboard/mouse through /dev/uinput, which is
  # root:input 0660 plus an ACL for the *active* seat user. A headless boot
  # never activates a seat, so group membership is the only path.
  if ! id -nG "$headless_user" | tr ' ' '\n' | grep -qx input; then
    info "adding $headless_user to the input group (uinput access)"
    sudo usermod -aG input "$headless_user"
    note 'group change takes effect at next login; the headless units'
    note 'start at boot, so this only matters on first install -- reboot'
    note 'after install if input capture misbehaves'
  else
    note "$headless_user is already in the input group"
  fi
}

ensure_headless_session_env() {
  # The headless session IS your desktop session: same ~/.config/hypr
  # (hyprland.lua + your dotfiles), same Sunshine pairing in
  # ~/.config/sunshine. Nothing to stage -- but fail fast when the config
  # is absent, or boot would land on a fallback compositor.
  if [[ ! -f "$HOME/.config/hypr/hyprland.lua" ]]; then
    die "no ~/.config/hypr/hyprland.lua found; install your dotfiles first"
  fi
  note 'headless session uses your own ~/.config/hypr (hyprland.lua)'
}

write_headless_output_script() {
  # Helper the compositor unit ExecStarts: bring up the uwsm session in the
  # background, wait for the Hyprland socket (hyprctl needs
  # HYPRLAND_INSTANCE_SIGNATURE, which only exists once Hyprland is up),
  # then create + configure the SUNSHINE capture output. Idempotent, so
  # unit restarts re-apply the output instead of failing on a duplicate.
  # A separate file (not an inline bash -c) because systemd splits
  # ExecStart on whitespace: quoting a 300-char loop through two parsers
  # is how quoting bugs are born.
  info "writing headless output helper $headless_output_script"
  # Quoted heredoc: the helper's $vars survive to boot time. The one
  # installer-side value (session.env path) is stamped in via a placeholder
  # replaced below -- expanding it inline would unquote the whole heredoc
  # and bake every loop variable empty at install time.
  sudo tee "$headless_output_script" >/dev/null <<'HELPER_EOF'
#!/usr/bin/env bash
# Wait for this session's Hyprland socket, then create the capture output.
# uwsm stays in the foreground below via wait so systemd tracks this PID
# and Restart= sees real session failures.
SESSION_ENV_FILE="__SESSION_ENV_FILE__"
OUTPUT_NAME="SUNSHINE"
OUTPUT_MODE="1920x1080@60"
OUTPUT_SCALE="1"

uwsm start -- hyprland.desktop &
UWSM_PID=$!

for _ in $(seq 1 60); do
  # Hyprland socket paths look like $XDG_RUNTIME_DIR/hypr/<sig>/socket.sock
  # (older builds: .socket.sock). The Wayland display name is NOT in that
  # path -- it is the compositor's bound socket under $XDG_RUNTIME_DIR
  # (wayland-0, wayland-1, ...). Probe the newest one: on a headless box
  # the session compositor is the only writer, so newest == ours.
  SOCK="$(ls -t "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null | grep -v '\.lock$' | head -1)"
  if [[ -n "$SOCK" && -S "$SOCK" ]]; then
    export WAYLAND_DISPLAY="$(basename "$SOCK")"
    export HYPRLAND_INSTANCE_SIGNATURE="$(basename "$(dirname "$(ls -t "$XDG_RUNTIME_DIR"/hypr/*/socket.sock "$XDG_RUNTIME_DIR"/hypr/*/.socket.sock 2>/dev/null | head -1)")")"
    # Record the ground truth for the streamer, which sources this file via
    # EnvironmentFile=. No hardcoded display name anywhere. Written before
    # output creation so a hyprctl failure still leaves a correct record.
    printf 'WAYLAND_DISPLAY=%s\n' "$WAYLAND_DISPLAY" >"$SESSION_ENV_FILE"
    if hyprctl output create headless "$OUTPUT_NAME" 2>/dev/null || hyprctl monitors all 2>/dev/null | grep -q "$OUTPUT_NAME"; then
      hyprctl keyword monitor "$OUTPUT_NAME,$OUTPUT_MODE,0x0,$OUTPUT_SCALE"
      break
    fi
  fi
  sleep 1
done

wait "$UWSM_PID"
HELPER_EOF
  sudo sed -i "s|^SESSION_ENV_FILE=.*|SESSION_ENV_FILE=\"$headless_session_env_file\"|" "$headless_output_script"
  sudo chmod 0755 "$headless_output_script"
}

write_headless_units() {
  # Tear down any previous revision before writing: stale ExecStart lines
  # from an older copy must not survive alongside the new ones.
  disable_headless_services

  info "installing headless units $headless_compositor_unit + $headless_streamer_unit"

  # Compositor: uwsm start generates the wayland-session@ set from the
  # hyprland.desktop entry and blocks until the session exits. No
  # HYPRLAND_CONFIG override: the session loads YOUR ~/.config/hypr
  # (hyprland.lua + dotfiles) exactly as a local login would. Restart=always
  # because a headless box has no greeter to bring the session back; the 5s
  # delay avoids a tight loop when the GPU/backend is missing entirely.
  # Quoted heredoc: the unit's remaining $vars belong to systemd at boot,
  # not to this installer.
  sudo tee "/etc/systemd/system/$headless_compositor_unit" >/dev/null <<UNIT_EOF
[Unit]
Description=Headless Hyprland session for Sunshine streaming (uwsm-managed)
Documentation=man:uwsm(1)
After=systemd-user-sessions.service network-online.target
Wants=network-online.target
PartOf=graphical.target

[Service]
Type=simple
User=$headless_user
PAMName=login
# render/video for the DRM node, input as a fallback if the seat ACL misses.
SupplementaryGroups=render video input
Environment=XDG_RUNTIME_DIR=$headless_runtime_dir
# Headless boot has no login VT, so the DRM backend would refuse master.
# These two hand it a VT to own (mirrors loginctl seat behaviour).
Environment=XDG_SEAT=seat0
Environment=XDG_VTNR=8
RuntimeDirectory=$headless_runtime_leaf
ExecStartPre=/usr/bin/install -d -o $headless_user -g $headless_user -m 0700 $headless_runtime_dir
# Helper below backgrounds uwsm, waits for the Hyprland socket, creates the
# SUNSHINE headless output, then waits on the session (foreground PID, so
# Restart= tracks real session failures).
ExecStart=$headless_output_script
Restart=always
RestartSec=5

[Install]
WantedBy=graphical.target
UNIT_EOF

  # Streamer: sunshine bound to the compositor above. After= orders startup;
  # Requires=/BindsTo stops the streamer if the compositor dies so Restart=
  # converges instead of sunshine capturing a dead socket (BindsTo carries
  # lifecycle only -- no environment crosses that edge).
  # XDG_RUNTIME_DIR must match the compositor: the Wayland socket lives there.
  # WAYLAND_DISPLAY arrives via EnvironmentFile=, written by the output
  # helper once the live socket exists (normally wayland-0, wayland-1+ when
  # a stale socket lingers). The leading `-` tolerates first boot before the
  # helper's first write; Restart=always then retries into the corrected
  # file within seconds instead of parking a dead unit.
  # Your pairing lives in ~/.config/sunshine either way (same user now),
  # so pair once over the admin webapp and both modes share it.
  # capture/output_name pin the stream to the SUNSHINE headless output:
  # output_name=1 is the capture-time index (the connector name is what
  # Sunshine's capture enumeration has historically filtered out; #5087).
  # Passed as CLI overrides so a stray sunshine.conf value cannot shadow
  # them.
  sudo tee "/etc/systemd/system/$headless_streamer_unit" >/dev/null <<EOF
[Unit]
Description=Sunshine game stream host (headless, bound to headless Hyprland)
Documentation=https://app.lizardbyte.dev/Sunshine
After=$headless_compositor_unit
Requires=$headless_compositor_unit
BindsTo=$headless_compositor_unit
PartOf=graphical.target

[Service]
Type=simple
User=$headless_user
PAMName=login
# Same device story as the compositor: encoder + uinput access.
SupplementaryGroups=render video input
Environment=XDG_RUNTIME_DIR=$headless_runtime_dir
EnvironmentFile=-$headless_session_env_file
ExecStartPre=/usr/bin/install -d -o $headless_user -g $headless_user -m 0700 $headless_runtime_dir
ExecStart=/usr/bin/sunshine capture=wlr output_name=1
Restart=always
RestartSec=2

[Install]
WantedBy=graphical.target
EOF

  sudo systemctl daemon-reload
}

enable_headless_service() {
  ensure_headless_prereqs
  ensure_headless_session_env
  write_headless_output_script
  write_headless_units

  sudo systemctl enable --now "$headless_compositor_unit"
  sudo systemctl enable --now "$headless_streamer_unit"

  if [[ "$(loginctl show-user "$headless_user" --property=Linger --value 2>/dev/null)" != yes ]]; then
    info "enabling linger for $headless_user"
    sudo loginctl enable-linger "$headless_user"
  else
    note "linger already enabled for $headless_user"
  fi

  note "capture output $headless_output_name ($headless_output_mode) is created"
  note 'by the compositor unit at session start; sunshine captures it via'
  note 'capture=wlr output_name=1'
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
  local unit
  for unit in "$headless_streamer_unit" "$headless_compositor_unit"; do
    if systemctl is-active --quiet "$unit" 2>/dev/null; then
      info "stopping $unit"
      sudo systemctl stop "$unit"
    fi
    if systemctl is-enabled --quiet "$unit" 2>/dev/null; then
      info "disabling $unit"
      sudo systemctl disable "$unit"
    fi
    if [[ -f "/etc/systemd/system/$unit" ]]; then
      info "removing /etc/systemd/system/$unit"
      sudo rm -f "/etc/systemd/system/$unit"
    fi
  done
  if [[ -f "$headless_output_script" ]]; then
    info "removing $headless_output_script"
    sudo rm -f "$headless_output_script"
  fi
  sudo systemctl daemon-reload
  sudo systemctl reset-failed "$headless_streamer_unit" "$headless_compositor_unit" 2>/dev/null || true
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
  printf 'headless system units (if present), desktop user unit + autostart\n'
  printf 'entry, admin webapp, UFW rules, and the sunshine package.\n'
  printf 'Your account and dotfiles are untouched.\n'
  confirm

  info 'removing headless system units (if present)'
  remove_headless_units

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
    printf 'This will install %s, open its streaming ports, and run headless\n' "$sunshine_pkg"
    printf 'Hyprland (uwsm-managed) plus sunshine as system units at boot (no Hyprland autostart entry).\n'
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
    info 'enabling headless Sunshine stack (removing any Hyprland autostart entry)'
    disable_hyprland_autostart
    enable_headless_service
    note 'admin UI has been installed but not launched; open it after pairing:'
    note "  $admin_url (self-signed certificate warning is expected)"
    note 'stack: Hyprland -> Moonlight (Sunshine) -> NetBird (wt0), as system'
    note "units as $headless_user with your own Hyprland config, at boot via"
    note 'graphical.target'
  else
    info 'enabling Sunshine for this Hyprland session'
    disable_headless_services
    enable_desktop_service
    enable_hyprland_autostart
    if command -v omarchy-launch-webapp >/dev/null 2>&1; then
      # shellcheck disable=SC2086
      $admin_exec >/dev/null 2>&1 &
    fi
  fi

  printf '\n'
  if ((headless)); then
    info 'Sunshine is installed from [lizardbyte] and streams from headless Hyprland at boot; Moonlight ports are open for private LANs, tailscale0 and wt0.'
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
