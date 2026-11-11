# `hypr/` — Hyprland Keybinding Pipeline & Conditional Layout Bindings

Files in this directory are installed into `~/.config/hypr/` on Omarchy 4.5+.

## Layered Keybinding Load Order

In `hyprland.lua` (directly after `require("default.hypr.omarchy")` loads Omarchy's built-in defaults), keybindings are loaded in three explicit stages:

1. **`unbindings.lua`** (`require("hypr.unbindings")`):
   - Dedicated exclusively to `hl.unbind(...)` calls for built-in Omarchy shortcuts that are retired or displaced.
   - Unbinds all 12 preinstalled web app shortcuts (`default/hypr/bindings/applications.lua`), displaced tiling/scratchpad/fullscreen/resize/scaling keys (`SUPER + Q`, `SUPER + O`, `SUPER + J`, `SUPER + L`, `SUPER + ALT + L`, `SUPER + S`, `SUPER + ALT + S`, `SUPER + F`, `SUPER + CTRL + F`, `SUPER + ALT + F`, `code:20` / `code:21` resize chords, `SUPER + SLASH`, `SUPER + ALT + SLASH`), and displaced clipboard/input-method/utility/application shortcuts (`SUPER + A`, `SUPER + SHIFT + CTRL + A`, `SUPER + I`, `SUPER + comma`, `SUPER + K`, `SUPER + CTRL + H/K/L`, `SUPER + SHIFT + F`, `SUPER + ALT + SHIFT + F`, `SUPER + SHIFT + N`, `SUPER + SHIFT + O`).
2. **`bindings.lua`** (`require("hypr.bindings")`):
   - Overlays personal replacement bindings on top of the cleaned Omarchy defaults using `o.bind(...)`:
     - `SUPER + HJKL` (focus), `SUPER + SHIFT + HJKL` (swap), `SUPER + SHIFT + CTRL + HJKL` (move), and `SUPER + CTRL + HJKL` (proportional resize).
     - `SUPER + F` / `SHIFT + F` / `CTRL + F` / `ALT + F` / `SHIFT + CTRL + F` for fullscreen and window state control (leaving `SUPER + T` as the stock floating toggle).
     - `SUPER + SHIFT + E` and `SUPER + SHIFT + ALT + E` for launching the file manager (`nautilus` / `nautilus-cwd`).
     - `SUPER + SHIFT + CTRL + ALT + K` for the keybindings menu (`omarchy-menu-keybindings`), `SUPER + ALT + Backspace` for one-way workspace layout cycling (`omarchy-hyprland-workspace-layout-toggle`), `SUPER + SHIFT + ALT + equal` for decreasing monitor scaling (`omarchy-hyprland-monitor-scaling down`), and `SUPER + SHIFT + CTRL + ALT + G` for toggling Eco mode.
     - Empty utility special workspaces (`special:a`, `special:q`, `special:y`, `special:u`) with companion `SUPER + SHIFT + CTRL + <key>` move-window bindings.
     - Application-spawning special workspaces: Signal (`special:comma` on `SUPER + comma` / `SUPER + SHIFT + CTRL + comma`), Obsidian (`special:o` on `SUPER + O` / `SUPER + SHIFT + CTRL + O`), Vesktop/Discord (`special:slash` on `SUPER + SLASH` / `SUPER + SHIFT + CTRL + SLASH` + window rule), Moonlight (`special:ctl_m` on `SUPER + CTRL + M` + window rule), and OneLook Thesaurus (`special:i` on `SUPER + I`), along with Discord mute toggle (`SUPER + Apostrophe` sending `SHIFT + CTRL + M` targeted to Vesktop) and new Obsidian window launch (`SUPER + SHIFT + O`).
     - Direct web app launches (without special workspaces) for Proton Mail (`SUPER + E`) and Proton Calendar (`SUPER + equal`).
3. **`layout-specific-bindings.lua` & `layouts/*.lua`** (`require("hypr.layout-specific-bindings")`):
   - Prepends `~/.local/bin` ahead of `/usr/share/omarchy/bin` in `hl.env("PATH", ...)` so `~/.local/bin/omarchy-hyprland-workspace-layout-toggle` shadows the packaged Omarchy script inside Hyprland dispatchers.
   - Sets `general.layout = "master"` as the baseline workspace layout.
   - Defines `o.sync_layout_bindings(mode)`, which conditionally calls `enable()` / `disable()` on the per-layout modules under `hypr/layouts/{master,dwindle,scrolling,floating}.lua` whenever the layout is cycled (`omarchy-hyprland-workspace-layout-toggle`) or when switching workspaces/monitors (`workspace.active` / `monitor.focused`).
   - **`layouts/master.lua`**: Binds `SUPER + S` (`swapwithmaster`), `SUPER + SHIFT + S` (`orientationnext`), `SUPER + N` (`rollprev`), and `SUPER + SHIFT + N` (`rollnext`) **only** while the active workspace is in `master` layout, unbinding them when switching to `dwindle`, `scrolling`, or `floating`.

## Special Workspace (Scratchpad) Naming Convention

Special workspaces defined by **this dotfiles repository** are named after the keybinding that opens them, omitting `SUPER` (which is always implicit):

```text
[sft_][ctl_][alt_]<key>
```

- Modifiers appear in the fixed order `sft` (`SHIFT`), `ctl` (`CTRL`), `alt` (`ALT`) only when present, separated by underscores, followed by the lowercase xkb keysym name:
  - `SUPER + I` → `i` (`special:i`)
  - `SUPER + O` → `o` (`special:o`)
  - `SUPER + A` → `a` (`special:a`)
  - `SUPER + Q` → `q` (`special:q`)
  - `SUPER + Y` → `y` (`special:y`)
  - `SUPER + U` → `u` (`special:u`)
  - `SUPER + SLASH` → `slash` (`special:slash`)
  - `SUPER + comma` → `comma` (`special:comma`)
  - `SUPER + CTRL + M` → `ctl_m` (`special:ctl_m`)
- Names are hardcoded at each definition rather than dynamically generated.
- **Scope**: This naming convention applies **exclusively** to special workspaces configured by this repository (`quattro-dots`). It does **not** apply to built-in special workspaces defined by Omarchy's own default configuration (such as `special:scratchpad` or `special:qconsole`).
