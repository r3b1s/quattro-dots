-- Personal keybinding overrides for Omarchy 4.5 (Quattro RS).
-- Loaded by hypr/hyprland.lua after hypr/unbindings.lua and before
-- hypr/layout-specific-bindings.lua.

local scratchpad_prefix = "Scratchpad:"

local function special(name, options)
  options = options or {}
  local rule = { workspace = "special:" .. name }
  if options.layout then
    rule.layout = options.layout
  end
  if options.layout_opts then
    rule.layout_opts = options.layout_opts
  end
  if options.on_created_empty then
    rule.on_created_empty = options.on_created_empty
  end
  hl.workspace_rule(rule)
end

local function toggle_special(keys, name, description)
  o.bind(keys, description or (scratchpad_prefix .. " " .. name), hl.dsp.workspace.toggle_special(name))
end

local function move_to_special(keys, name, description)
  o.bind(
    keys,
    description or ("Move to " .. scratchpad_prefix .. " " .. name),
    hl.dsp.window.move({ workspace = "special:" .. name })
  )
end

local function scratchpad(keys, name, command, opts)
  opts = opts or {}
  special(name, {
    layout = opts.layout,
    layout_opts = opts.layout_opts,
    on_created_empty = command,
  })

  toggle_special(keys, name, opts.description or (scratchpad_prefix .. " " .. name))

  if opts.move_keys then
    move_to_special(opts.move_keys, name, opts.move_description or ("Move to " .. scratchpad_prefix .. " " .. name))
  end
end

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

-- ── Relocated Omarchy Utilities & Monitor Scaling ──────────────────────────
o.bind("SUPER + SHIFT + CTRL + ALT + K", "Show key bindings", "omarchy-menu-keybindings")
o.bind("SUPER + ALT + Backspace", "Cycle workspace layout", "omarchy-hyprland-workspace-layout-toggle")
o.bind("SUPER + SHIFT + ALT + equal", "Monitor scaling down", "omarchy-hyprland-monitor-scaling down")

-- ── eco-mode ───────────────────────────────────────────────────────────────
local eco_flag = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/hypr/"
  .. (os.getenv("HYPRLAND_INSTANCE_SIGNATURE") or "") .. "/eco-mode"

local function eco_active()
  local f = io.open(eco_flag, "r")
  if f then
    f:close()
  end
  return f ~= nil
end

if eco_active() then
  hl.config({
    animations = { enabled = false },
    decoration = {
      blur = { enabled = false, special = false, popups = false, input_methods = false },
      shadow = { enabled = false },
      glow = { enabled = false },
      motion_blur = { enabled = false },
      screen_shader = "",
      active_opacity = 1,
      inactive_opacity = 1,
      fullscreen_opacity = 1,
      dim_inactive = false,
      dim_special = 1,
      rounding = 0,
    },
    general = { gaps_in = 0, gaps_out = 0, border_size = 1 },
  })
end

o.bind("SUPER + SHIFT + CTRL + ALT + G", "Toggle eco-mode", function()
  if eco_active() then
    os.remove(eco_flag)
    hl.dispatch(hl.dsp.exec_cmd('omarchy-notification-send "eco-mode off" "Compositor effects restored"'))
  else
    local f = io.open(eco_flag, "w")
    if f then
      f:close()
    end
    hl.dispatch(hl.dsp.exec_cmd('omarchy-notification-send "eco-mode on" "Compositor effects off, no gaps or rounding"'))
  end
  hl.dispatch(hl.dsp.exec_cmd("hyprctl reload"))
end)

-- ── Empty / Utility Special Workspaces (Scratchpads) ───────────────────────
scratchpad("SUPER + A", "a", nil, { move_keys = "SUPER + SHIFT + CTRL + A" })
scratchpad("SUPER + Q", "q", nil, { move_keys = "SUPER + SHIFT + CTRL + Q" })
scratchpad("SUPER + Y", "y", nil, { move_keys = "SUPER + SHIFT + CTRL + Y" })
scratchpad("SUPER + U", "u", nil, { move_keys = "SUPER + SHIFT + CTRL + U" })

-- ── Application-Spawning Special Workspaces ────────────────────────────────
-- Signal
scratchpad("SUPER + comma", "comma", o.launch("signal-desktop"), { move_keys = "SUPER + SHIFT + CTRL + comma" })

-- Obsidian
scratchpad("SUPER + O", "o", o.launch("obsidian"), { move_keys = "SUPER + SHIFT + CTRL + O" })
o.bind("SUPER + SHIFT + O", "Obsidian", o.launch("obsidian"))

-- Discord (Vesktop) — keep transient loading window and main window in special:slash
hl.window_rule({
  match = { class = "^(vesktop)$" },
  workspace = "special:slash",
})
scratchpad(
  "SUPER + SLASH",
  "slash",
  o.launch("vesktop --ozone-platform-hint=auto"),
  { move_keys = "SUPER + SHIFT + CTRL + SLASH" }
)
o.bind(
  "SUPER + Apostrophe",
  "Discord Mute Toggle",
  hl.dsp.send_shortcut({
    mods = "SHIFT + CTRL",
    key = "M",
    window = "class:^(vesktop)$",
  })
)

-- Moonlight — keep native Moonlight windows in special:ctl_m
hl.window_rule({
  match = { class = "^(com\\.moonlight_stream\\.Moonlight)$" },
  workspace = "special:ctl_m",
})
scratchpad("SUPER + CTRL + M", "ctl_m", o.launch("moonlight"))

-- OneLook Thesaurus webapp
scratchpad("SUPER + I", "i", 'omarchy-launch-webapp "https://www.onelook.com/thesaurus"')

-- ── Direct Web App Launches ────────────────────────────────────────────────
o.bind("SUPER + E", "Proton Mail", { webapp = "https://mail.proton.me" })
o.bind("SUPER + equal", "Proton Calendar", { webapp = "https://calendar.proton.me" })
