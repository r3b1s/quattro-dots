# `bin/` — Local Binary Overrides

Scripts in this directory are symlinked into `~/.local/bin` and take precedence over Omarchy's packaged scripts in `/usr/share/omarchy/bin` and `/usr/bin`.

## `omarchy-hyprland-workspace-layout-toggle`

- Overrides Omarchy 4.5's stock `omarchy-hyprland-workspace-layout-toggle` (which only cycles `dwindle` -> `scrolling` -> `floating`).
- Cycles in the order **`master` -> `dwindle` -> `scrolling` -> `floating` -> `master`**, keeping `master` first as the default layout.
- Evaluates both `o.workspace_mode({ workspace = ..., mode = ... })` and `o.sync_layout_bindings("<mode>")` via `hyprctl eval` so that layout-specific keybindings in `~/.config/hypr/layouts/<mode>.lua` are conditionally loaded/unloaded immediately on layout switch.
- Note: Because `/usr/share/omarchy/default/hypr/envs.lua` prepends `/usr/share/omarchy/bin` to `PATH` inside Hyprland, `hypr/layout-specific-bindings.lua` re-prepends `~/.local/bin` ahead of `/usr/share/omarchy/bin` via `hl.env("PATH", ...)`.
