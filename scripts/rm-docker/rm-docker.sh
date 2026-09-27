#!/usr/bin/env bash
# Remove Omarchy's Docker packages and Docker-specific UFW configuration.
# Safe to rerun: each cleanup checks whether its target still exists.
# This does not install Podman or delete Docker data/configuration directories automatically.
set -Eeuo pipefail

if (( EUID == 0 )); then
  echo 'Error: do not run this script as root; yay must run as your user.' >&2
  exit 1
fi

readonly docker_dns_comment_hex='616c6c6f772d646f636b65722d646e73'
readonly docker_dns_address='172.17.0.1'
readonly docker_dns_port='53'
readonly docker_ufw_mark='# BEGIN UFW AND DOCKER'

command -v sudo >/dev/null 2>&1 || {
  echo 'Error: sudo is required.' >&2
  exit 1
}
sudo_cmd=(sudo)

run_privileged() {
  "${sudo_cmd[@]}" "$@"
}

command -v yay >/dev/null 2>&1 || {
  echo 'Error: yay was not found; install yay before running this Omarchy/Arch script.' >&2
  exit 1
}

packages=(docker docker-buildx docker-compose containerd ufw-docker)
installed_packages=()
for package in "${packages[@]}"; do
  if yay -Qq "$package" >/dev/null 2>&1; then
    installed_packages+=("$package")
  fi
done

printf 'This will stop/disable Docker services, remove Docker-specific UFW rules, and uninstall these installed packages:\n'
if ((${#installed_packages[@]})); then
  printf '  %s\n' "${installed_packages[@]}"
else
  printf '  (none of the listed packages)\n'
fi
printf '\nDocker data/config paths will be offered for optional deletion after package removal.\n'
printf 'The stale Docker socket(s), docker0 interface, and local docker group will be removed if present.\n'
printf 'User configuration/shortcuts, Omarchy-managed systemd settings, and UFW backups will be kept.\n'
read -r -p 'Continue? [y/N] ' reply
[[ "$reply" =~ ^[Yy]([Ee][Ss])?$ ]] || {
  echo 'Cancelled.'
  exit 0
}

if (( EUID != 0 )); then
  run_privileged -v
fi

# Stop socket activation before package removal, then stop any running daemons.
for unit in docker.socket docker.service containerd.service; do
  if systemctl cat "$unit" >/dev/null 2>&1; then
    run_privileged systemctl disable --now "$unit"
  fi
done

firewall_changed=0

# ufw-docker removes its marked forwarding-rule blocks from after.rules and
# after6.rules. It may report a Swarm-related error on non-Swarm hosts even
# after removing those blocks, so verify the files rather than trusting only
# its exit code.
had_ufw_docker_blocks=0
for rules_file in /etc/ufw/after.rules /etc/ufw/after6.rules; do
  if [[ -r "$rules_file" ]] && grep -Fq "$docker_ufw_mark" "$rules_file"; then
    had_ufw_docker_blocks=1
  fi
done

if command -v ufw-docker >/dev/null 2>&1; then
  if ! run_privileged ufw-docker uninstall; then
    echo 'Warning: ufw-docker uninstall returned an error; checking whether its rules were removed.' >&2
  fi
fi

for rules_file in /etc/ufw/after.rules /etc/ufw/after6.rules; do
  if [[ -r "$rules_file" ]] && grep -Fq "$docker_ufw_mark" "$rules_file"; then
    echo "Error: Docker firewall rules remain in $rules_file; stopping before package removal." >&2
    exit 1
  fi
done
if ((had_ufw_docker_blocks)); then
  firewall_changed=1
fi

# Remove the two stock Omarchy Docker DNS allowances by their rule definitions,
# never by UFW's position-dependent numbered listing. Checking the persisted
# UFW tuple makes this safe to rerun and also works while UFW is inactive.
remove_docker_dns_rule() {
  local source_subnet=$1
  local tuple="### tuple ### allow udp 53 ${docker_dns_address} any ${source_subnet} in comment=${docker_dns_comment_hex}"
  local rule_found=0

  if [[ -r /etc/ufw/user.rules ]] && grep -Fq -- "$tuple" /etc/ufw/user.rules; then
    rule_found=1
  fi

  if ((rule_found)); then
    run_privileged ufw --force delete allow in proto udp \
      from "$source_subnet" to "$docker_dns_address" port "$docker_dns_port" \
      comment allow-docker-dns

    if grep -Fq -- "$tuple" /etc/ufw/user.rules; then
      echo "Error: UFW did not remove the Docker DNS rule from $source_subnet; stopping before package removal." >&2
      exit 1
    fi
    firewall_changed=1
  fi
}

if command -v ufw >/dev/null 2>&1 && [[ -e /etc/ufw/user.rules ]]; then
  remove_docker_dns_rule '172.16.0.0/12'
  remove_docker_dns_rule '192.168.0.0/16'
fi

if ((firewall_changed)) && systemctl is-active --quiet ufw.service; then
  run_privileged systemctl restart ufw.service
fi

if ((${#installed_packages[@]})); then
  yay -Rns -- "${installed_packages[@]}"
else
  echo 'No listed Docker packages are installed; nothing to remove with yay.'
fi

# Docker's service units are now disabled/removed, so any remaining API sockets
# are stale. /var/run commonly aliases /run; check both names without assuming
# numbered paths or deleting an unexpected non-socket file.
for socket_path in /run/docker.sock /var/run/docker.sock; do
  if [[ -S "$socket_path" ]]; then
    run_privileged rm -f -- "$socket_path"
    echo "Removed stale socket: $socket_path"
  elif [[ -e "$socket_path" || -L "$socket_path" ]]; then
    echo "Warning: leaving $socket_path because it exists but is not a socket." >&2
  fi
done

# Remove Docker's default bridge if it survived daemon shutdown.
if command -v ip >/dev/null 2>&1 && ip link show dev docker0 >/dev/null 2>&1; then
  run_privileged ip link delete dev docker0
  echo 'Removed Docker network interface: docker0'
fi

# Remove only the local docker group, if present. This does not touch Omarchy's
# Docker launcher, keybinding, alias, or lazydocker configuration.
if grep -q '^docker:' /etc/group; then
  run_privileged groupdel docker
  echo 'Removed local docker group.'
fi

confirm_and_remove() {
  local path=$1
  local kind=$2
  local reply

  if [[ ! -e "$path" && ! -L "$path" ]]; then
    echo "Not present; skipping: $path"
    return
  fi

  printf '\nOptional cleanup: %s %s\n' "$kind" "$path"
  if ! IFS= read -r -p 'Delete it? [y/N] ' reply; then
    reply=''
  fi
  if [[ "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    if [[ "$kind" == directory ]]; then
      run_privileged rm -rf -- "$path"
    else
      run_privileged rm -f -- "$path"
    fi
    echo "Deleted: $path"
  else
    echo "Kept: $path"
  fi
}

# These prompts are deliberately separate so the user can preserve any
# directory or daemon configuration independently. Missing targets are skipped,
# so rerunning after cleanup (or after choosing to keep a target) is safe.
confirm_and_remove /var/lib/docker directory
confirm_and_remove /var/lib/containerd directory
confirm_and_remove /etc/docker/daemon.json file

echo 'Docker removal steps completed.'
echo 'Omarchy-managed systemd settings, UFW backups, and user shortcuts/configuration were kept.'
