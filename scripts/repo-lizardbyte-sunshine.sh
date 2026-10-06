#!/usr/bin/env bash
# Set up LizardByte's official pacman repositories for Sunshine on Omarchy/Arch.
# Based on the official instructions at:
# https://github.com/LizardByte/pacman-repo
#
# Adds both the stable [lizardbyte] and [lizardbyte-beta] repositories.
# Safe to rerun: each repository section is only appended when missing.
set -Eeuo pipefail

readonly pacman_conf='/etc/pacman.conf'

if ((EUID == 0)); then
  echo 'Error: do not run this script as root; sudo is used for the privileged steps.' >&2
  exit 1
fi

for cmd in grep pacman sudo; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "Error: required command was not found: $cmd" >&2
    exit 1
  }
done

repo_added=0
if grep -qE '^[[:space:]]*\[lizardbyte\][[:space:]]*$' "$pacman_conf"; then
  printf '[lizardbyte] is already present in %s; skipping.\n' "$pacman_conf"
else
  # The docs append the section at the end. The leading blank line keeps it
  # readable even when the current file does not end with a newline.
  sudo tee -a "$pacman_conf" >/dev/null <<'EOF'

[lizardbyte]
SigLevel = Optional
Server = https://github.com/LizardByte/pacman-repo/releases/latest/download
EOF
  repo_added=1
  printf 'Added [lizardbyte] to %s.\n' "$pacman_conf"
fi

if grep -qE '^[[:space:]]*\[lizardbyte-beta\][[:space:]]*$' "$pacman_conf"; then
  printf '[lizardbyte-beta] is already present in %s; skipping.\n' "$pacman_conf"
else
  sudo tee -a "$pacman_conf" >/dev/null <<'EOF'

[lizardbyte-beta]
SigLevel = Optional
Server = https://github.com/LizardByte/pacman-repo/releases/download/beta
EOF
  repo_added=1
  printf 'Added [lizardbyte-beta] to %s.\n' "$pacman_conf"
fi

if ((repo_added)); then
  # A full upgrade is needed to pick up the newly added repositories, and -Sy
  # on its own would leave the system in a partial-upgrade state. This is left
  # to the user: a system-wide upgrade is too disruptive for a setup script.
  printf '\n'
  printf 'LizardByte repositories are configured. Finish with a full system upgrade:\n'
  printf '  sudo pacman -Syu\n'
  printf 'Then install Sunshine with e.g.:\n'
  printf '  sudo pacman -S lizardbyte/sunshine\n'
else
  printf 'LizardByte repositories are already configured; nothing further to do.\n'
fi
