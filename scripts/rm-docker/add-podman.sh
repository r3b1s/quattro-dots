#!/usr/bin/env bash
# Install Podman and Docker CLI compatibility on Omarchy/Arch, and configure
# lazydocker/Omarchy's Docker launcher to use the rootless Podman API socket.
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: add-podman.sh [--desktop]

Install podman, podman-compose, and podman-docker using yay.
With --desktop, also install podman-desktop.
Enable the rootless Podman socket and configure lazydocker to use it.
EOF
}

desktop=0
while (($#)); do
  case "$1" in
    --desktop)
      desktop=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if (( EUID == 0 )); then
  echo 'Error: do not run this script as root; yay should run as your user.' >&2
  exit 1
fi

command -v yay >/dev/null 2>&1 || {
  echo 'Error: yay was not found; install yay before running this Omarchy/Arch script.' >&2
  exit 1
}
command -v sudo >/dev/null 2>&1 || {
  echo 'Error: sudo is required to create /etc/containers/nodocker.' >&2
  exit 1
}

readonly environment_dir="$HOME/.config/environment.d"
readonly environment_file="$environment_dir/90-podman-docker.conf"
readonly environment_marker='# managed-by-add-podman.sh'
readonly lazydocker_wrapper="$HOME/.local/bin/lazydocker"
readonly wrapper_marker='# managed-by-add-podman.sh'
podman_socket="/run/user/$(id -u)/podman/podman.sock"
readonly podman_socket

expected_environment=$(printf '%s\n' \
  "$environment_marker" \
  "OMARCHY_DOCKER_SOCKET=${podman_socket}")
expected_wrapper=$(cat <<EOF
#!/usr/bin/env bash
${wrapper_marker}
set -euo pipefail
export DOCKER_HOST='unix://${podman_socket}'
exec /usr/bin/lazydocker "\$@"
EOF
)

# Refuse to overwrite existing customizations at paths this script manages.
# The exact generated files are accepted on repeat runs.
if [[ -e "$environment_file" || -L "$environment_file" ]] && [[ "$(<"$environment_file")" != "$expected_environment" ]]; then
  echo "Error: refusing to overwrite an existing or modified file: $environment_file" >&2
  exit 1
fi
if [[ -e "$lazydocker_wrapper" || -L "$lazydocker_wrapper" ]] && [[ "$(<"$lazydocker_wrapper")" != "$expected_wrapper" ]]; then
  echo "Error: refusing to overwrite an existing or modified file: $lazydocker_wrapper" >&2
  exit 1
fi

packages=(podman podman-compose podman-docker)
if ((desktop)); then
  packages+=(podman-desktop)
fi

printf 'Installing with yay: %s\n' "${packages[*]}"
printf 'Note: podman-docker conflicts with the Docker package; resolve that package conflict before continuing if Docker is still installed.\n'
yay -S --needed -- "${packages[@]}"

# podman-docker prints an informational notice on each docker invocation unless
# this system-wide marker exists. Preserve an existing file and create it only
# when absent, making repeated runs harmless.
if [[ -L /etc/containers/nodocker ]]; then
  echo 'Error: /etc/containers/nodocker is a symlink; refusing to replace it.' >&2
  exit 1
elif [[ ! -e /etc/containers/nodocker ]]; then
  sudo install -D -m 644 /dev/null /etc/containers/nodocker
fi

# Rootless Podman's Docker-compatible API is exposed on this per-user socket.
# Enabling it is safe to repeat and avoids running a rootful Podman daemon.
systemctl --user enable --now podman.socket

# Omarchy's Docker launcher checks OMARCHY_DOCKER_SOCKET before deciding to use
# pkexec. Persist that override for future sessions and update the user manager
# now; a fresh login may be needed for existing graphical processes to inherit it.
mkdir -p "$environment_dir"
if [[ ! -e "$environment_file" ]]; then
  tmp_environment=$(mktemp "$environment_file.XXXXXX")
  trap 'rm -f -- "$tmp_environment"' EXIT
  printf '%s\n' "$expected_environment" >"$tmp_environment"
  chmod 644 "$tmp_environment"
  mv -f -- "$tmp_environment" "$environment_file"
  trap - EXIT
fi
systemctl --user set-environment "OMARCHY_DOCKER_SOCKET=${podman_socket}"

# Lazydocker reads DOCKER_HOST from its process environment. This PATH-preferred
# wrapper points it at Podman's API without changing lazydocker's own config or
# binary. Omarchy's existing Docker launcher can continue invoking lazydocker.
if [[ ! -e "$lazydocker_wrapper" ]]; then
  mkdir -p "$(dirname "$lazydocker_wrapper")"
  tmp_wrapper=$(mktemp "${lazydocker_wrapper}.XXXXXX")
  trap 'rm -f -- "$tmp_wrapper"' EXIT
  printf '%s\n' "$expected_wrapper" >"$tmp_wrapper"
  chmod 755 "$tmp_wrapper"
  mv -f -- "$tmp_wrapper" "$lazydocker_wrapper"
  trap - EXIT
fi

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo 'Warning: ~/.local/bin is not currently in PATH; log in again or add it to PATH for the lazydocker wrapper to take effect.' >&2 ;;
esac

echo 'Podman installation completed.'
echo "Rootless Podman API socket enabled: $podman_socket"
echo "Lazydocker and Omarchy's Docker launcher are configured to use that socket."
echo 'Log out and back in if the graphical session does not yet have the updated environment.'
echo 'No lazydocker configuration files or settings were changed.'
