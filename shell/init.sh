# Shared interactive-shell overrides for Bash.
DOTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DOTS/envs"
source "$DOTS/aliases"
source "$DOTS/fns"
