# quattro-dots

These are the personal dotfiles for a single user running Omarchy 4.5.0 or later.

## Scope

This repository provides a streamlined configuration tailored for Omarchy 4.5+. At present, only the keybinding pipeline and workspace layout cycler are migrated and managed here.

## Core Philosophy: Idempotency & Direct Copy Model

1. **Idempotency as a Hard Requirement**:
   - Every installation, update, and setup routine (starting with `install.sh`) must be strictly **idempotent**.
   - Executing `install.sh` repeatedly must produce the exact same final state without side effects, redundant modifications, duplicate entries, or failures.
   - Existing files matching the repository source in content and permissions are preserved as up-to-date.

2. **Direct Copy (No Symlinks)**:
   - Configuration files and executable scripts are copied directly into `~/.config/` and `~/.local/bin/` rather than symlinked.
   - If a target path currently exists as a symlink (e.g., from older configurations), the installer safely replaces the symlink with a regular file copy.

## Directory Mapping

- **`hypr/`** → `~/.config/hypr/` (permissions: `0644`)
  - 3-stage keybinding pipeline (`unbindings.lua` -> `bindings.lua` -> `layout-specific-bindings.lua`).
  - Dynamic per-layout configurations (`layouts/*.lua`).
  - See `hypr/AGENTS.md` for binding details and scratchpad conventions.
- **`bin/`** → `~/.local/bin/` (permissions: `0755`)
  - Custom shell utilities and overrides (e.g. `omarchy-hyprland-workspace-layout-toggle`).
  - See `bin/AGENTS.md` for binary override details.

## Installation

Run the idempotent installer:

```bash
./install.sh
```

To inspect planned actions without touching files:

```bash
./install.sh --dry-run
```
