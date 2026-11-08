-- Personal keybinding overrides for Omarchy 4.5 (Quattro RS).
-- Loaded by hypr/hyprland.lua after hypr/unbindings.lua and before
-- hypr/layout-specific-bindings.lua.

local function resize_step(axis)
  local mon = hl.get_active_monitor()
  local dim = mon and tonumber(mon[axis]) or (axis == "width" and 1920 or 1080)
  return math.max(1, math.floor(dim * 0.055))
end

-- ── Window Focus, Swap, Move & Resize (HJKL) ───────────────────────────────
for _, item in ipairs({
  { key = "H", dir = "l", label = "left" },
  { key = "J", dir = "d", label = "down" },
  { key = "K", dir = "u", label = "up" },
  { key = "L", dir = "r", label = "right" },
}) do
  o.bind("SUPER + " .. item.key, "Move focus " .. item.label, hl.dsp.focus({ direction = item.dir }))
  o.bind("SUPER + SHIFT + " .. item.key, "Swap window " .. item.label, hl.dsp.window.swap({ direction = item.dir }))
  o.bind("SUPER + SHIFT + CTRL + " .. item.key, "Move window " .. item.label, hl.dsp.window.move({ direction = item.dir }))
end

o.bind("SUPER + CTRL + H", "Resize window left", function()
  hl.dispatch(hl.dsp.window.resize({ x = -resize_step("width"), y = 0, relative = true }))
end, { repeating = true })

o.bind("SUPER + CTRL + L", "Resize window right", function()
  hl.dispatch(hl.dsp.window.resize({ x = resize_step("width"), y = 0, relative = true }))
end, { repeating = true })

o.bind("SUPER + CTRL + K", "Resize window up", function()
  hl.dispatch(hl.dsp.window.resize({ x = 0, y = resize_step("height"), relative = true }))
end, { repeating = true })

o.bind("SUPER + CTRL + J", "Resize window down", function()
  hl.dispatch(hl.dsp.window.resize({ x = 0, y = -resize_step("height"), relative = true }))
end, { repeating = true })

-- ── Fullscreen States (F) ──────────────────────────────────────────────────
-- Excludes SUPER + SHIFT + CTRL + ALT + F (toggle floating), leaving floating on stock SUPER + T.
local maximize_toggle =
  'if [ "$(hyprctl activewindow -j | jq -r \'.fullscreen\')" = "1" ]; then hyprctl dispatch \'hl.dsp.window.fullscreen_state({ internal = 0, client = -1, action = "set" })\'; else hyprctl dispatch \'hl.dsp.window.fullscreen_state({ internal = 1, client = -1, action = "set" })\'; fi'

o.bind("SUPER + F", "Maximize active window", hl.dsp.exec_cmd(maximize_toggle))
o.bind(
  "SUPER + SHIFT + F",
  "Window fullscreen (client unaware)",
  hl.dsp.window.fullscreen_state({ internal = 2, client = 0, action = "toggle" })
)
o.bind(
  "SUPER + CTRL + F",
  "In-client fullscreen (window unaware)",
  hl.dsp.window.fullscreen_state({ internal = 0, client = 2, action = "toggle" })
)
o.bind(
  "SUPER + ALT + F",
  "Typical fullscreen",
  hl.dsp.window.fullscreen_state({ internal = 3, client = 3, action = "toggle" })
)
o.bind(
  "SUPER + SHIFT + CTRL + F",
  "Default window state",
  hl.dsp.window.fullscreen_state({ internal = 0, client = 0, action = "set" })
)

-- ── File Manager (E) ───────────────────────────────────────────────────────
o.bind("SUPER + SHIFT + E", "File manager", { omarchy = "nautilus" })
o.bind("SUPER + SHIFT + ALT + E", "File manager (cwd)", { omarchy = "nautilus-cwd" })

-- ── Relocated Omarchy Utilities ────────────────────────────────────────────
o.bind("SUPER + SHIFT + CTRL + ALT + K", "Show key bindings", "omarchy-menu-keybindings")
o.bind("SUPER + ALT + Backspace", "Cycle workspace layout", "omarchy-hyprland-workspace-layout-toggle")
