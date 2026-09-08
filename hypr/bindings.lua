-- ####################################################
-- #################### CONSTANTS #####################
-- #####                                          #####

-- ##########################
-- ######## System ##########
-- ##                     ###

local uwsmLaunch = "uwsm-app --"
local terminal = uwsmLaunch .. " xdg-terminal-exec"

-- ##                     ###
-- ######## System ##########
-- ##########################

-- ##########################
-- ##### Keycode Defs #######
-- ##                     ###

local key = {
  -- Function keys
  f1 = "code:67",
  f2 = "code:68",
  f3 = "code:69",
  f4 = "code:70",
  f5 = "code:71",
  f6 = "code:72",
  f7 = "code:73",
  f8 = "code:74",
  f9 = "code:75",
  f10 = "code:76",
  f11 = "code:95",
  f12 = "code:96",

  -- Numbers
  one = "code:10",
  two = "code:11",
  three = "code:12",
  four = "code:13",
  five = "code:14",
  six = "code:15",
  seven = "code:16",
  eight = "code:17",
  nine = "code:18",
  zero = "code:19",

  -- Symbols
  grave = "code:49",
  comma = "code:59",
  period = "code:60",
  slash = "code:61",
  semicolon = "code:47",
  apostrophe = "code:48",
  bracketleft = "code:34",
  bracketright = "code:35",
  backslash = "code:51",
  minus = "code:20",
  equal = "code:21",

  -- Alphabetical, qwerty-sorted
  q = "code:24",
  w = "code:25",
  e = "code:26",
  r = "code:27",
  t = "code:28",
  y = "code:29",
  u = "code:30",
  i = "code:31",
  o = "code:32",
  p = "code:33",
  a = "code:38",
  s = "code:39",
  d = "code:40",
  f = "code:41",
  g = "code:42",
  h = "code:43",
  j = "code:44",
  k = "code:45",
  l = "code:46",
  z = "code:52",
  x = "code:53",
  c = "code:54",
  v = "code:55",
  b = "code:56",
  n = "code:57",
  m = "code:58",

  -- Common
  return_key = "code:36",
  tab = "code:23",
  space = "code:65",
  backspace = "code:22",
  escape = "code:9",
  capslock = "code:66",

  -- Modifiers
  shift_l = "code:50",
  shift_r = "code:62",
  alt_l = "code:64",
  alt_r = "code:108",
  ctrl_l = "code:37",
  ctrl_r = "code:105",
  super_l = "code:133",
  super_r = "code:134",

  -- Misc + nav
  menu = "code:135",
  print = "code:107",
  scrolllock = "code:78",
  pause = "code:127",
  insert = "code:118",
  delete = "code:119",
  home = "code:110",
  end_key = "code:115",
  pageup = "code:112",
  pagedown = "code:117",
  up = "code:111",
  down = "code:116",
  left = "code:113",
  right = "code:114",

  -- Num pad
  numlock = "code:77",
  np_divide = "code:106",
  np_multiply = "code:63",
  np_subtract = "code:82",
  np_add = "code:86",
  np_enter = "code:104",
  np_decimal = "code:91",
  np_0 = "code:90",
  np_1 = "code:87",
  np_2 = "code:88",
  np_3 = "code:89",
  np_4 = "code:83",
  np_5 = "code:84",
  np_6 = "code:85",
  np_7 = "code:79",
  np_8 = "code:80",
  np_9 = "code:81",

  -- Mouse buttons, used as mouse:<value> in some bindings.
  mouse_left = "code:272",
  mouse_right = "code:273",
  mouse_middle = "code:274",
  mouse_back = "code:275",
  mouse_forward = "code:276",
}

local scratchpadPrefix = "Scratchpad:"

-- ##                     ###
-- ##### Keycode Defs #######
-- ##########################

-- #####                                          #####
-- #################### CONSTANTS #####################
-- ####################################################

-- ####################################################
-- ###################### HELPERS #####################
-- #####                                          #####

local function bind(keys, action, description, opts)
  opts = opts or {}
  opts.description = description
  hl.bind(keys, action, opts)
end

local function exec(keys, command, description, opts)
  bind(keys, hl.dsp.exec_cmd(command), description, opts)
end

local function unbind(keys)
  hl.unbind(keys)
end

local function unbindAll(keys)
  for _, binding in ipairs(keys) do
    unbind(binding)
  end
end

local function dispatch(keys, dispatcher, args, description)
  local command = "hyprctl dispatch " .. dispatcher
  if args and args ~= "" then
    command = command .. " " .. args
  end
  exec(keys, command, description)
end

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

local function toggleSpecial(keys, name, description)
  bind(keys, hl.dsp.workspace.toggle_special(name), description or (scratchpadPrefix .. " " .. name))
end

local function moveToSpecial(keys, name, description)
  bind(
    keys,
    hl.dsp.window.move({ workspace = "special:" .. name }),
    description or ("Move to " .. scratchpadPrefix .. " " .. name)
  )
end

local function scratchpad(keys, name, command, opts)
  opts = opts or {}
  special(name, {
    layout = opts.layout,
    layout_opts = opts.layout_opts,
    on_created_empty = command,
  })

  toggleSpecial(keys, name, opts.description or (scratchpadPrefix .. " " .. name))

  if opts.move_keys then
    moveToSpecial(opts.move_keys, name, opts.move_description or ("Move to " .. scratchpadPrefix .. " " .. name))
  end
end

local function resizeStep(axis)
  local mon = hl.get_active_monitor()
  local dim = mon and tonumber(mon[axis]) or (axis == "width" and 1920 or 1080)
  return math.max(1, math.floor(dim * 0.055))
end

local workspaceKeys = {
  { label = "1", code = key.one,   workspace = 1 },
  { label = "2", code = key.two,   workspace = 2 },
  { label = "3", code = key.three, workspace = 3 },
  { label = "4", code = key.four,  workspace = 4 },
  { label = "5", code = key.five,  workspace = 5 },
  { label = "6", code = key.six,   workspace = 6 },
  { label = "7", code = key.seven, workspace = 7 },
  { label = "8", code = key.eight, workspace = 8 },
  { label = "9", code = key.nine,  workspace = 9 },
  { label = "0", code = key.zero,  workspace = 10 },
}

-- #####                                          #####
-- ###################### HELPERS #####################
-- ####################################################

-- ####################################################
-- ###################### SYSTEM ######################
-- #####                                          #####

-- ##########################
-- #### Workspace Mngmnt ####
-- ###                    ###

-- Switch workspaces with SUPER + [0-9]
for _, item in ipairs(workspaceKeys) do
  unbindAll({
    "SUPER + " .. item.label,
    "SUPER + " .. item.code,
  })
  bind(
    "SUPER + " .. item.label,
    hl.dsp.focus({ workspace = item.workspace }),
    "Switch to workspace " .. item.workspace
  )

  -- Move active window to a workspace with SUPER + SHIFT + [0-9]
  unbindAll({
    "SUPER + SHIFT + " .. item.label,
    "SUPER + SHIFT + " .. item.code,
  })
  bind(
    "SUPER + SHIFT + " .. item.label,
    hl.dsp.window.move({ workspace = item.workspace }),
    "Move window to workspace " .. item.workspace
  )
end

-- Move focus between windows.
for _, item in ipairs({
  { label = "H", code = key.h, dir = "l", desc = "Move focus left" },
  { label = "L", code = key.l, dir = "r", desc = "Move focus right" },
  { label = "J", code = key.j, dir = "d", desc = "Move focus down" },
  { label = "K", code = key.k, dir = "u", desc = "Move focus up" },
}) do
  unbind("SUPER + " .. item.label)
  unbind("SUPER + " .. item.code)
  bind("SUPER + " .. item.label, hl.dsp.focus({ direction = item.dir }), item.desc)

  -- Swap active window with the one next to it with SUPER + SHIFT + H/J/K/L.
  unbind("SUPER + SHIFT + " .. item.label)
  unbind("SUPER + SHIFT + " .. item.code)
  bind(
    "SUPER + SHIFT + " .. item.label,
    hl.dsp.window.swap({ direction = item.dir }),
    (item.desc:gsub("Move focus", "Swap window"))
  )

  -- Move active window directionally, without swapping.
  unbind("SUPER + SHIFT + CTRL + " .. item.label)
  unbind("SUPER + SHIFT + CTRL + " .. item.code)
  bind(
    "SUPER + SHIFT + CTRL + " .. item.label,
    hl.dsp.window.move({ direction = item.dir }),
    (item.desc:gsub("Move focus", "Move window"))
  )
end

-- Toggle floating on active window.
unbind("SUPER + SHIFT + CTRL + ALT + F")
unbind("SUPER + SHIFT + CTRL + ALT + " .. key.f)
bind("SUPER + SHIFT + CTRL + ALT + F", hl.dsp.window.float({ action = "toggle" }), "Toggle floating on active window")

-- Nudge floating windows for manual repositioning.
local nudgeFactor = 20
for _, item in ipairs({
  {
    label = "H",
    code = key.h,
    args = "-" .. nudgeFactor .. " 0",
    desc = "Nudge window to the left (floating windows)",
  },
  {
    label = "L",
    code = key.l,
    args = nudgeFactor .. " 0",
    desc = "Nudge window to the right (floating windows)",
  },
  { label = "J", code = key.j, args = "0 -" .. nudgeFactor, desc = "Nudge window down (floating windows)" },
  { label = "K", code = key.k, args = "0 " .. nudgeFactor,  desc = "Nudge window up (floating windows)" },
}) do
  unbind("SUPER + SHIFT + ALT + " .. item.label)
  unbind("SUPER + SHIFT + ALT + " .. item.code)
  dispatch("SUPER + SHIFT + ALT + " .. item.label, "moveactive", item.args, item.desc)
end

-- Resize active window natively.
for _, binding in ipairs({
  "SUPER + " .. key.equal,
  "SUPER + SHIFT + " .. key.equal,
  "SUPER + " .. key.minus,
  "SUPER + SHIFT + " .. key.minus,
}) do
  unbind(binding)
end
unbindAll({
  "SUPER + CTRL + H",
  "SUPER + CTRL + " .. key.h,
})
bind("SUPER + CTRL + H", function() hl.dispatch(hl.dsp.window.resize({ x = -resizeStep("width"),  y = 0, relative = true })) end, "Expand window horizontal", { repeating = true })
unbindAll({
  "SUPER + CTRL + L",
  "SUPER + CTRL + " .. key.l,
})
bind("SUPER + CTRL + L", function() hl.dispatch(hl.dsp.window.resize({ x =  resizeStep("width"),  y = 0, relative = true })) end, "Shrink window horizontal", { repeating = true })
unbindAll({
  "SUPER + CTRL + K",
  "SUPER + CTRL + " .. key.k,
})
bind("SUPER + CTRL + K", function() hl.dispatch(hl.dsp.window.resize({ x = 0, y =  resizeStep("height"), relative = true })) end, "Expand window vertical", { repeating = true })
unbindAll({
  "SUPER + CTRL + J",
  "SUPER + CTRL + " .. key.j,
})
bind("SUPER + CTRL + J", function() hl.dispatch(hl.dsp.window.resize({ x = 0, y = -resizeStep("height"), relative = true })) end, "Shrink window vertical", { repeating = true })

-- Close active window.
unbind("SUPER + W")
unbind("SUPER + " .. key.w)
bind("SUPER + W", hl.dsp.window.close(), "Close active window")

-- Fullscreen states.
local maximizeToggle =
'if [ "$(hyprctl activewindow -j | jq -r \'.fullscreen\')" = "1" ]; then hyprctl dispatch \'hl.dsp.window.fullscreen_state({ internal = 0, client = -1, action = "set" })\'; else hyprctl dispatch \'hl.dsp.window.fullscreen_state({ internal = 1, client = -1, action = "set" })\'; fi'

unbind("SUPER + F")
unbind("SUPER + " .. key.f)
bind("SUPER + F", hl.dsp.exec_cmd(maximizeToggle), "Maximize active window")
unbind("SUPER + SHIFT + F")
unbind("SUPER + SHIFT + " .. key.f)
bind(
  "SUPER + SHIFT + F",
  hl.dsp.window.fullscreen_state({ internal = 2, client = 0, action = "toggle" }),
  "Window fullscreen (client unaware)"
)
unbind("SUPER + CTRL + F")
unbind("SUPER + CTRL + " .. key.f)
bind(
  "SUPER + CTRL + F",
  hl.dsp.window.fullscreen_state({ internal = 0, client = 2, action = "toggle" }),
  "In-client fullscreen (window unaware)"
)
unbind("SUPER + ALT + F")
unbind("SUPER + ALT + " .. key.f)
bind(
  "SUPER + ALT + F",
  hl.dsp.window.fullscreen_state({ internal = 3, client = 3, action = "toggle" }),
  "Typical fullscreen"
)
unbind("SUPER + SHIFT + CTRL + F")
unbind("SUPER + SHIFT + CTRL + " .. key.f)
bind(
  "SUPER + SHIFT + CTRL + F",
  hl.dsp.window.fullscreen_state({ internal = 0, client = 0, action = "set" }),
  "Default window state"
)

-- ###                    ###
-- #### Workspace Mngmnt ####
-- ##########################

-- ##########################
-- ######## Display #########
-- ###                    ###

-- Hyprland display scale controls.
unbindAll({
  "SUPER + SHIFT + equal",
  "SUPER + SHIFT + Equal",
  "SUPER + SHIFT + EQUAL",
  "SUPER + SHIFT + " .. key.equal,
})
exec("SUPER + SHIFT + Equal", "omarchy-hyprland-monitor-scaling up", "Display Scale - Increase")
unbindAll({
  "SUPER + SHIFT + minus",
  "SUPER + SHIFT + Minus",
  "SUPER + SHIFT + MINUS",
  "SUPER + SHIFT + " .. key.minus,
})
exec("SUPER + SHIFT + Minus", "omarchy-hyprland-monitor-scaling down", "Display Scale - Decrease")

-- Hyprland appearance/layout toggles.
unbindAll({
  "SUPER + SHIFT + backspace",
  "SUPER + SHIFT + Backspace",
  "SUPER + SHIFT + BACKSPACE",
  "SUPER + SHIFT + " .. key.backspace,
})
exec("SUPER + SHIFT + Backspace", "hyprland-window-gaps-cycle", "Cycle Window Gap Size")
unbindAll({
  "SUPER + CTRL + backspace",
  "SUPER + CTRL + Backspace",
  "SUPER + CTRL + BACKSPACE",
  "SUPER + CTRL + " .. key.backspace,
})
exec("SUPER + CTRL + Backspace", "hyprland-window-borders-cycle", "Cycle Window Border Thickness")
unbindAll({
  "SUPER + SHIFT + CTRL + ALT + backspace",
  "SUPER + SHIFT + CTRL + ALT + Backspace",
  "SUPER + SHIFT + CTRL + ALT + BACKSPACE",
  "SUPER + SHIFT + CTRL + ALT + " .. key.backspace,
})
exec("SUPER + SHIFT + CTRL + ALT + Backspace", "hyprland-window-round-toggle", "Toggle Window Rounding")

-- ###                    ###
-- ######## Display #########
-- ##########################

-- ##########################
-- ##### Screen Capture #####
-- ###                    ###

-- Screenshots.
unbindAll({
  "SUPER + semicolon",
  "SUPER + Semicolon",
  "SUPER + SEMICOLON",
  "SUPER + " .. key.semicolon,
})
exec("SUPER + Semicolon", 'grim -g "$(slurp -w 0)" - | wl-copy', "Screenshot of region to clipboard")

-- Screen recordings.
unbindAll({
  "SUPER + ALT + semicolon",
  "SUPER + ALT + Semicolon",
  "SUPER + ALT + SEMICOLON",
  "SUPER + ALT + " .. key.semicolon,
})
exec("SUPER + ALT + Semicolon", "omarchy-menu toggle trigger.capture.screenrecord", "Screen Record")
unbindAll({
  "SUPER + R",
  "SUPER + " .. key.r,
})
exec("SUPER + R", "omarchy-capture-screenrecording --with-desktop-audio --with-microphone-audio", "Screen Record")

-- Force recording to stop.
unbindAll({
  "SUPER + SHIFT + R",
  "SUPER + SHIFT + " .. key.r,
})
exec("SUPER + SHIFT + R", "omarchy-capture-screenrecording --stop-recording", "Stop Screen Recording")

-- ###                    ###
-- ##### Screen Capture #####
-- ##########################

-- ##########################
-- ##### Voice Capture ######
-- ###                    ###

-- Override Omarchy's default mic-mute key so it targets the virtual mic sources
-- used by EasyEffects / the Discord mixed mic setup while preserving the stock OSD.
unbind("XF86AudioMicMute")
exec(
  "XF86AudioMicMute",
  "omarchy-audio-input-mute-smart",
  "Mute microphone",
  { locked = true, repeating = true }
)

-- Mic Mute Discord
-- unbindAll({
-- 	"SUPER + SHIFT + CTRL + M",
-- 	"SUPER + SHIFT + CTRL + " .. key.m,
-- })
unbindAll({
  "SUPER + apostrophe",
  "SUPER + Apostrophe",
  "SUPER + APOSTROPHE",
  "SUPER + " .. key.apostrophe,
})
-- via sending shortcut
hl.bind(
  "SUPER + Apostrophe",
  hl.dsp.send_shortcut({
    mods = "SHIFT + CTRL",
    key = "M",
    window = "class:^(vesktop)$",
  }),
  { description = "Discord Mute Toggle" }
)
-- Pass keycombo for discord mute toggle
-- - (alternate way VS sending shortcut as above)
-- hl.bind("SHIFT + CTRL + M", hl.dsp.pass({ window = "class:^(vesktop)$" }))

if o.cmd_present("voxtype") then
  -- Personal Voxtype toggle; stock push-to-talk bindings remain available.
  unbindAll({
    "SUPER + D",
    "SUPER + " .. key.d,
  })
  exec("SUPER + D", "$HOME/.config/hypr/scripts/voxtype-record-toggle", "Toggle dictation")
  require("hypr.bindings-submap-voxtype_suppress")
end

-- ###                    ###
-- ##### Voice Capture ######
-- ##########################

-- ##########################
-- ###### System Apps #######
-- ###                    ###

-- Omarchy menu.
unbindAll({
  "SUPER + space",
  "SUPER + Space",
  "SUPER + SPACE",
  "SUPER + " .. key.space,
})
exec("SUPER + Space", "omarchy-menu", "Omarchy menu")

-- Omarchy app launcher.
unbindAll({
  "SUPER + return",
  "SUPER + Return",
  "SUPER + RETURN",
  "SUPER + " .. key.return_key,
})
exec("SUPER + Return", "omarchy-menu toggle apps", "Launch apps")

-- Terminal new window.
unbindAll({
  "SUPER + SHIFT + T",
  "SUPER + SHIFT + " .. key.t,
})
exec("SUPER + SHIFT + T", terminal, "Terminal")

-- File manager.
unbindAll({
  "SUPER + E",
  "SUPER + " .. key.e,
})
exec("SUPER + E", uwsmLaunch .. " nautilus --new-window", "File manager")

-- Color picker.
unbindAll({
  "SUPER + SHIFT + CTRL + ALT + P",
  "SUPER + SHIFT + CTRL + ALT + " .. key.p,
})
exec("SUPER + SHIFT + CTRL + ALT + P", "pkill hyprpicker || hyprpicker -a", "Color picker")

-- Browsers.
local omarchyLaunchBrowser = "omarchy launch browser"
unbindAll({
  "SUPER + B",
  "SUPER + " .. key.b,
})
exec("SUPER + B", omarchyLaunchBrowser, "Browser")

-- Omarchy default browser scratchpads.
unbindAll({
  "SUPER + U",
  "SUPER + " .. key.u,
})
scratchpad("SUPER + U", "Default-Browser 1", "exec " .. omarchyLaunchBrowser)
unbindAll({
  "SUPER + ALT + B",
  "SUPER + ALT + " .. key.b,
})
scratchpad("SUPER + ALT + B", "Default-Browser 2", "exec " .. omarchyLaunchBrowser)

-- Move window to Default-Browser 1 scratchpad workspace.
unbindAll({
  "SUPER + SHIFT + CTRL + U",
  "SUPER + SHIFT + CTRL + " .. key.u,
})
bind(
  "SUPER + SHIFT + CTRL + U",
  hl.dsp.window.move({ workspace = "special:Default-Browser 1" }),
  "Move window to Default-Browser 1"
)

-- ###                    ###
-- ###### System Apps #######
-- ##########################

-- ##########################
-- ####### Utilities ########
-- ###                    ###

-- Show keybind preview.
unbindAll({
  "SUPER + SHIFT + CTRL + ALT + K",
  "SUPER + SHIFT + CTRL + ALT + " .. key.k,
})
exec("SUPER + SHIFT + CTRL + ALT + K", "omarchy-menu-keybindings", "Show key bindings")

-- Toggle i3/game mode.
unbindAll({
  "SUPER + SHIFT + CTRL + ALT + G",
  "SUPER + SHIFT + CTRL + ALT + " .. key.g,
})
exec("SUPER + SHIFT + CTRL + ALT + G", "hyprland-toggle-i3-mode", "Toggle i3 mode")

-- ###                    ###
-- ####### Utilities ########
-- ##########################

-- #####                                          #####
-- ###################### SYSTEM ######################
-- ####################################################

-- ####################################################
-- ################### SCRATCHPADS ####################
-- #####    (Scratchpad == Special Workspace)    #####

-- ##########################
-- #### Sys, Terms, TUI #####
-- ###                    ###

-- term1.
unbindAll({
  "SUPER + T",
  "SUPER + " .. key.t,
})
unbindAll({
  "SUPER + SHIFT + CTRL + T",
  "SUPER + SHIFT + CTRL + " .. key.t,
})
scratchpad("SUPER + T", "term1", terminal, {
  layout = "master",
  layout_opts = { orientation = "center" },
  move_keys = "SUPER + SHIFT + CTRL + T",
  move_description = "Move to term1's dropdown",
})

-- term2.
unbindAll({
  "SUPER + G",
  "SUPER + " .. key.g,
})
unbindAll({
  "SUPER + SHIFT + CTRL + G",
  "SUPER + SHIFT + CTRL + " .. key.g,
})
scratchpad("SUPER + G", "term2", terminal, {
  layout = "master",
  layout_opts = { orientation = "center" },
  move_keys = "SUPER + SHIFT + CTRL + G",
  move_description = "Move to term2's dropdown",
})

-- tmux-sessionizer.
unbindAll({
  "SUPER + CTRL + T",
  "SUPER + CTRL + " .. key.t,
})
exec("SUPER + CTRL + T", terminal .. " -e tmux-sessionizer", "Open tmux sessionizer")

-- lazydocker.
unbindAll({
  "SUPER + SHIFT + D",
  "SUPER + SHIFT + " .. key.d,
})
scratchpad("SUPER + SHIFT + D", "Lazydocker", "exec " .. terminal .. " -e lazydocker")

-- Wiremix & Easy Effects: audio input/output filtering, noise cancellation, etc.
unbindAll({
  "SUPER + SHIFT + W",
  "SUPER + SHIFT + " .. key.w,
})
scratchpad("SUPER + SHIFT + W", "Easy-Effects", "easyeffects; xdg-terminal-exec -e wiremix")

-- Network management.
unbindAll({
  "SUPER + CTRL + W",
  "SUPER + CTRL + " .. key.w,
})
exec("SUPER + CTRL + W", "omarchy-shell shell toggle omarchy.network", "Network")

-- Bluetooth management.
unbindAll({
  "SUPER + ALT + W",
  "SUPER + ALT + " .. key.w,
})
exec("SUPER + ALT + W", "omarchy-shell shell toggle omarchy.bluetooth", "Bluetooth")

-- Task manager.
unbindAll({
  "SUPER + P",
  "SUPER + " .. key.p,
})
scratchpad("SUPER + P", "btop", terminal .. " -e btop")
unbindAll({
  "SUPER + ALT + P",
  "SUPER + ALT + " .. key.p,
})
exec("SUPER + ALT + P", terminal .. " -e btop", "Task Manager")

-- ###                    ###
-- ##### Terminal & TUI #####
-- ##########################

-- ##########################
-- ### Empty Scratchpads ####
-- ###                    ###

-- Utility scratchpad 1.
unbindAll({
  "SUPER + period",
  "SUPER + Period",
  "SUPER + PERIOD",
  "SUPER + " .. key.period,
})
unbindAll({
  "SUPER + SHIFT + CTRL + period",
  "SUPER + SHIFT + CTRL + Period",
  "SUPER + SHIFT + CTRL + PERIOD",
  "SUPER + SHIFT + CTRL + " .. key.period,
})
scratchpad("SUPER + Period", "Utility 1", nil, { move_keys = "SUPER + SHIFT + CTRL + Period" })

-- Utility scratchpad 2.
unbindAll({
  "SUPER + minus",
  "SUPER + Minus",
  "SUPER + MINUS",
  "SUPER + " .. key.minus,
})
unbindAll({
  "SUPER + SHIFT + CTRL + minus",
  "SUPER + SHIFT + CTRL + Minus",
  "SUPER + SHIFT + CTRL + MINUS",
  "SUPER + SHIFT + CTRL + " .. key.minus,
})
scratchpad("SUPER + Minus", "Utility 2", nil, { move_keys = "SUPER + SHIFT + CTRL + Minus" })

-- Utility scratchpad 3.
unbindAll({
  "SUPER + Y",
  "SUPER + " .. key.y,
})
unbindAll({
  "SUPER + SHIFT + CTRL + Y",
  "SUPER + SHIFT + CTRL + " .. key.y,
})
scratchpad("SUPER + Y", "Utility 3", nil, { move_keys = "SUPER + SHIFT + CTRL + Y" })

-- ###                    ###
-- ### Empty Scratchpads ####
-- ##########################

-- ##########################
-- ####### Misc Apps ########
-- ###                    ###

-- Signal.
unbindAll({
  "SUPER + comma",
  "SUPER + Comma",
  "SUPER + COMMA",
  "SUPER + " .. key.comma,
})
unbindAll({
  "SUPER + SHIFT + CTRL + comma",
  "SUPER + SHIFT + CTRL + Comma",
  "SUPER + SHIFT + CTRL + COMMA",
  "SUPER + SHIFT + CTRL + " .. key.comma,
})
scratchpad("SUPER + Comma", "Signal", uwsmLaunch .. " signal-desktop", { move_keys = "SUPER + SHIFT + CTRL + Comma" })

-- Discord.
unbindAll({
  "SUPER + slash",
  "SUPER + Slash",
  "SUPER + SLASH",
  "SUPER + " .. key.slash,
})
unbindAll({
  "SUPER + SHIFT + CTRL + slash",
  "SUPER + SHIFT + CTRL + " .. key.slash,
})
scratchpad(
  "SUPER + Slash",
  "Discord",
  uwsmLaunch .. " flatpak run dev.vencord.Vesktop --ozone-platform-hint=auto",
  { move_keys = "SUPER + SHIFT + CTRL + Slash" }
)

-- Notes 1: Obsidian.
unbindAll({
  "SUPER + O",
  "SUPER + " .. key.o,
})
unbindAll({
  "SUPER + SHIFT + CTRL + O",
  "SUPER + SHIFT + CTRL + " .. key.o,
})
scratchpad(
  "SUPER + " .. key.o,
  "Obsidian",
  uwsmLaunch .. " obsidian -disable-gpu",
  { move_keys = "SUPER + SHIFT + CTRL + O" }
)
unbindAll({
  "SUPER + SHIFT + O",
  "SUPER + SHIFT + " .. key.o,
})
exec("SUPER + SHIFT + O", uwsmLaunch .. " obsidian -disable-gpu", "Obsidian")

-- Remote desktop.
unbindAll({
  "SUPER + CTRL + M",
  "SUPER + CTRL + " .. key.m,
})
scratchpad("SUPER + CTRL + M", "Moonlight", uwsmLaunch .. " flatpak run com.moonlight_stream.Moonlight")

-- Grayjay.
unbindAll({
  "SUPER + M",
  "SUPER + " .. key.m,
})
scratchpad("SUPER + M", "Grayjay", uwsmLaunch .. " flatpak run app.grayjay.Grayjay")

unbindAll({
  "SUPER + SHIFT + M",
  "SUPER + SHIFT + " .. key.m,
})
exec("SUPER + SHIFT + M", uwsmLaunch .. " flatpak run app.grayjay.Grayjay", "Grayjay")

-- Password manager 1: Bitwarden.
unbindAll({
  "SUPER + SHIFT + P",
  "SUPER + SHIFT + " .. key.p,
})
scratchpad("SUPER + SHIFT + P", "Bitwarden", uwsmLaunch .. " bitwarden-desktop")

-- Password manager 2: KeepassXC.
unbindAll({
  "SUPER + CTRL + P",
  "SUPER + CTRL + " .. key.p,
})
scratchpad("SUPER + CTRL + P", "KeepassXC", uwsmLaunch .. " keepassxc")

-- Cryptomator.
unbindAll({
  "SUPER + SHIFT + CTRL + P",
  "SUPER + SHIFT + CTRL + " .. key.p,
})
scratchpad("SUPER + SHIFT + CTRL + P", "Cryptomator", uwsmLaunch .. " flatpak run org.cryptomator.Cryptomator", {
  layout = "master",
  layout_opts = { orientation = "center" },
})

-- ###                    ###
-- ####### Misc Apps ########
-- ##########################

-- ##########################
-- ######## Webapps #########
-- ###                    ###

local launchWebapp = "omarchy-launch-webapp"

-- LLM webapps scratchpad.
unbindAll({
  "SUPER + A",
  "SUPER + " .. key.a,
})
unbindAll({
  "SUPER + SHIFT + CTRL + A",
  "SUPER + SHIFT + CTRL + " .. key.a,
})
scratchpad(
  "SUPER + " .. key.a,
  "LLM Webapps",
  launchWebapp
  .. ' "https://chatgpt.com"; '
  .. launchWebapp
  .. ' "https://claude.ai"; '
  .. launchWebapp
  .. ' "https://google.com"',
  {
    layout = "master",
    layout_opts = { orientation = "center" },
    move_keys = "SUPER + SHIFT + CTRL + A",
  }
)

-- Dictionary.
unbindAll({
  "SUPER + I",
  "SUPER + " .. key.i,
})
scratchpad("SUPER + I", "Dictionary", launchWebapp .. ' "https://www.onelook.com/thesaurus"')

-- Code forge 2: GitLab.
unbindAll({
  "SUPER + ALT + G",
  "SUPER + ALT + " .. key.g,
})
scratchpad("SUPER + ALT + G", "GitLab", launchWebapp .. ' "https://gitlab.com"')

-- Calendar.
unbindAll({
  "SUPER + equal",
  "SUPER + Equal",
  "SUPER + EQUAL",
  "SUPER + " .. key.equal,
})
scratchpad("SUPER + Equal", "Calendar", launchWebapp .. ' "https://calendar.proton.me"')
unbindAll({
  "SUPER + CTRL + equal",
  "SUPER + CTRL + Equal",
  "SUPER + CTRL + EQUAL",
  "SUPER + CTRL + " .. key.equal,
})
exec("SUPER + CTRL + Equal", launchWebapp .. ' "https://calendar.proton.me"', "Calendar")

-- Email.
unbindAll({
  "SUPER + ALT + equal",
  "SUPER + ALT + Equal",
  "SUPER + ALT + EQUAL",
  "SUPER + ALT + " .. key.equal,
})
scratchpad("SUPER + ALT + Equal", "Email", launchWebapp .. ' "https://mail.proton.me"')
unbindAll({
  "SUPER + CTRL + ALT + equal",
  "SUPER + CTRL + ALT + Equal",
  "SUPER + CTRL + ALT + EQUAL",
  "SUPER + CTRL + ALT + " .. key.equal,
})
exec("SUPER + CTRL + ALT + Equal", launchWebapp .. ' "https://mail.proton.me"', "Email")

-- ###                    ###
-- ######## Webapps #########
-- ##########################

-- #####                                          #####
-- ################### SCRATCHPADS ####################
-- ####################################################

-- ##########################
-- ##### Niche Utility ######
-- ###                    ###

-- Toggle focus on Moonlight remote desktop stream window.
dispatch(
  "SHIFT + CTRL + ALT + " .. key.z,
  "sendshortcut",
  "SHIFT CTRL ALT, " .. key.z .. ", class:com.moonlight_stream.Moonlight",
  "Toggle Moonlight Focus"
)
exec(
  "SHIFT + CTRL + ALT + " .. key.z,
  [[omarchy-notification-send "Moonlight Focus Toggled"]],
  "Notify Moonlight Focus Toggled"
)

-- ###                    ###
-- ##### Niche Utility ######
-- ##########################

-- ##########################
-- ####### Other Apps #######
-- ###                    ###

-- Perplexity.
unbindAll({
  "SUPER + SHIFT + A",
  "SUPER + SHIFT + " .. key.a,
})
exec("SUPER + SHIFT + A", launchWebapp .. ' "https://www.perplexity.ai/"', "Perplexity Web")

-- Claude.
unbindAll({
  "SUPER + CTRL + A",
  "SUPER + CTRL + " .. key.a,
})
exec("SUPER + CTRL + A", launchWebapp .. ' "https://claude.ai"', "Claude Web")

-- ChatGPT.
unbindAll({
  "SUPER + ALT + A",
  "SUPER + ALT + " .. key.a,
})
exec("SUPER + ALT + A", launchWebapp .. ' "https://chatgpt.com"', "ChatGPT Web")

-- ###                    ###
-- ####### Other Apps #######
-- ##########################

require("hypr.layouts")
require("hypr.bindings-submap-voxtype_suppress")
require("hypr.bindings-submap-gaps-resize")
require("hypr.bindings-submap-vm-passthru")
