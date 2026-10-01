#!/usr/bin/env bash
# Scaffold preferred directories in the home directory.
# When run via sudo, directories are created for the invoking user (SUDO_USER), not root.
set -euo pipefail

DIRS=(
  Engagements
  Projects
  Dotfiles
  Work
  3rdParty
  Machines
)

if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
  TARGET_USER="$SUDO_USER"
  TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
  [[ -n "$TARGET_HOME" ]] || { echo "error: cannot resolve home for $TARGET_USER" >&2; exit 1; }
  run_as_user() { sudo -u "$TARGET_USER" -- "$@"; }
else
  TARGET_HOME="${HOME:?HOME is not set}"
  run_as_user() { "$@"; }
fi

for d in "${DIRS[@]}"; do
  run_as_user mkdir -p "$TARGET_HOME/$d"
  echo "dir: $TARGET_HOME/$d"
done
