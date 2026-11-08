# `hypr/` — Hyprland Keybinding Pipeline & Conditional Layout Bindings

Files in this directory are installed into `~/.config/hypr/` on Omarchy 4.5+ (Quattro RS).

## Layered Keybinding Load Order

In `hyprland.lua` (directly after `require("default.hypr.omarchy")` loads Omarchy's built-in defaults), keybindings are loaded in three explicit stages:

1. **`unbindings.lua`** (`require("hypr.unbindings")`):
   - Dedicated exclusively to `hl.unbind(...)` calls for built-in Omarchy shortcuts that are retired or displaced.
   - Unbinds all 12 preinstalled web app shortcuts (`default/hypr/bindings/applications.lua`), displaced tiling/scratchpad/fullscreen keys (`SUPER + J`, `SUPER + L`, `SUPER + ALT + L`, `SUPER + S`, `SUPER + ALT + S`, `SUPER + F`, `SUPER + CTRL + F`, `SUPER + ALT + F`), and displaced utility/application shortcuts (`SUPER + K`, `SUPER + CTRL + H/K/L`, `SUPER + SHIFT + F`, `SUPER + ALT + SHIFT + F`, `SUPER + SHIFT + N`).
2. **`bindings.lua`** (`require("hypr.bindings")`):
   - Overlays personal replacement bindings on top of the cleaned Omarchy defaults using `o.bind(...)`:
     - `SUPER + HJKL` (focus), `SUPER + SHIFT + HJKL` (swap), `SUPER + SHIFT + CTRL + HJKL` (move), and `SUPER + CTRL + HJKL` (proportional resize).
     - `SUPER + F` / `SHIFT + F` / `CTRL + F` / `ALT + F` / `SHIFT + CTRL + F` for fullscreen and window state control (leaving `SUPER + T` as the stock floating toggle).
     - `SUPER + SHIFT + E` and `SUPER + SHIFT + ALT + E` for launching the file manager (`nautilus` / `nautilus-cwd`).
     - `SUPER + SHIFT + CTRL + ALT + K` for the keybindings menu (`omarchy-menu-keybindings`) and `SUPER + ALT + Backspace` for one-way workspace layout cycling (`omarchy-hyprland-workspace-layout-toggle`).
3. **`layout-specific-bindings.lua` & `layouts/*.lua`** (`require("hypr.layout-specific-bindings")`):
   - Prepends `~/.local/bin` ahead of `/usr/share/omarchy/bin` in `hl.env("PATH", ...)` so `~/.local/bin/omarchy-hyprland-workspace-layout-toggle` shadows the packaged Omarchy script inside Hyprland dispatchers.
   - Sets `general.layout = "master"` as the baseline workspace layout.
   - Defines `o.sync_layout_bindings(mode)`, which conditionally calls `enable()` / `disable()` on the per-layout modules under `hypr/layouts/{master,dwindle,scrolling,floating}.lua` whenever the layout is cycled (`omarchy-hyprland-workspace-layout-toggle`) or when switching workspaces/monitors (`workspace.active` / `monitor.focused`).
   - **`layouts/master.lua`**: Binds `SUPER + S` (`swapwithmaster`), `SUPER + SHIFT + S` (`orientationnext`), `SUPER + N` (`rollprev`), and `SUPER + SHIFT + N` (`rollnext`) **only** while the active workspace is in `master` layout, unbinding them when switching to `dwindle`, `scrolling`, or `floating`.
