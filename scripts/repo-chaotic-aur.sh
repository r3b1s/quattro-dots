#!/usr/bin/env bash
# Set up the Chaotic-AUR repository on Omarchy/Arch.
# Based on the official instructions at:
# https://aur.chaotic.cx/docs
#
# Safe to rerun: each step checks whether its target already exists, and the
# repository section is only appended when it is missing from pacman.conf.
set -Eeuo pipefail

# The primary key named in the official docs is "pedrohlc" in the upstream
# keyring repo. pacman refers to it by long key ID, i.e. the last 16 hex
# characters of its full fingerprint EF925EA60F33D0CB85C44AD13056513887B78AEB.
readonly chaotic_key_id='3056513887B78AEB'

# Canonical list of Chaotic-AUR master keys, kept in the official keyring repo.
# This is the source used to detect a key rotation: a keyserver lookup only
# proves the key still exists, not that Chaotic-AUR still publishes it.
readonly keyids_url='https://raw.githubusercontent.com/chaotic-aur/keyring/master/master-keyids'
readonly keyring_url='https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst'
readonly mirrorlist_url='https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

readonly pacman_conf='/etc/pacman.conf'
readonly mirrorlist_file='/etc/pacman.d/chaotic-mirrorlist'

if ((EUID == 0)); then
  echo 'Error: do not run this script as root; sudo is used for the privileged steps.' >&2
  exit 1
fi

for cmd in curl awk grep pacman pacman-key sudo; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "Error: required command was not found: $cmd" >&2
    exit 1
  }
done

key_ids=$(mktemp)
trap 'rm -f -- "$key_ids"' EXIT

# Confirm the hardcoded key is still one of the upstream master keys before any
# system change, so that a rotated key aborts the script instead of silently
# trusting a stale one.
verify_primary_key() {
  if ! curl -fsSL --retry 3 -- "$keyids_url" -o "$key_ids"; then
    echo "Error: could not download the Chaotic-AUR key list from $keyids_url" >&2
    return 1
  fi

  # master-keyids holds one "<full fingerprint><whitespace><owner>" line per
  # master key; match the key ID against the tail of each fingerprint.
  if ! awk -v key="$chaotic_key_id" '
    {
      fingerprint = toupper($1)
      gsub(/\r/, "", fingerprint)
      if (length(fingerprint) == 40 && fingerprint ~ /^[0-9A-F]+$/ \
          && substr(fingerprint, length(fingerprint) - 15) == toupper(key)) {
        found = 1
      }
    }
    END { exit(found ? 0 : 1) }
  ' "$key_ids"; then
    echo "Error: $chaotic_key_id is no longer listed as a Chaotic-AUR master key." >&2
    echo "The upstream key was likely rotated; review $keyids_url and update this script." >&2
    return 1
  fi

  printf 'Verified Chaotic-AUR primary key: %s\n' "$chaotic_key_id"
}

verify_primary_key

# Trust the advertised key locally so the keyring and mirrorlist packages can
# be verified while they are installed.
sudo pacman-key --recv-key "$chaotic_key_id" --keyserver keyserver.ubuntu.com
sudo pacman-key --lsign-key "$chaotic_key_id"

# These must be installed from the CDN before the repository is added: pacman
# refuses to parse pacman.conf while the mirrorlist Include path is missing.
packages_installed=0
if pacman -Qq chaotic-keyring >/dev/null 2>&1 \
  && pacman -Qq chaotic-mirrorlist >/dev/null 2>&1 \
  && [[ -e "$mirrorlist_file" ]]; then
  printf 'chaotic-keyring and chaotic-mirrorlist are already installed; skipping.\n'
else
  sudo pacman -U -- "$keyring_url" "$mirrorlist_url"
  packages_installed=1
fi

repo_added=0
if grep -qE '^[[:space:]]*\[chaotic-aur\][[:space:]]*$' "$pacman_conf"; then
  printf '[chaotic-aur] is already present in %s; skipping.\n' "$pacman_conf"
else
  # The docs append the section at the end. The leading blank line keeps it
  # readable even when the current file does not end with a newline.
  sudo tee -a "$pacman_conf" >/dev/null <<'EOF'

[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
EOF
  repo_added=1
  printf 'Added [chaotic-aur] to %s.\n' "$pacman_conf"
fi

if ((repo_added || packages_installed)); then
  # A full upgrade is needed to pick up the newly added repository, and -Sy on
  # its own would leave the system in a partial-upgrade state. This is left to
  # the user: a system-wide upgrade is too disruptive for a setup script.
  printf '\n'
  printf 'Chaotic-AUR is configured. Finish with a full system upgrade:\n'
  printf '  sudo pacman -Syu\n'
else
  printf 'Chaotic-AUR is already configured; nothing further to do.\n'
fi