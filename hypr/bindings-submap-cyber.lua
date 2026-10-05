-- Cyber Submap
--
-- The base layer with the home/gaming workstation bindings cut out, for
-- red/blue/purple-team work. Enter and exit with SUPER + CTRL + ALT + C.
--
-- A submap inherits nothing: CBind::matchesContext compares m_metadata.submap
-- against the active submap for exact equality unless BIND_FLAG_SUBMAP_UNIVERSAL
-- is set, so every bind the base layer relies on is redeclared here by hand.
-- The flip side is that nothing needs unbinding either. Omarchy's defaults and
-- bindings.lua's own binds all carry the default submap, so they cannot fire
-- while cyber is active.
--
-- Special workspaces are shared with the base layer, names included, so a
-- workspace opened in either layer is the same workspace and any windows
-- already in it survive a layer switch. Their on_created_empty commands are
-- workspace rules, which are global rather than per-submap, so this layer just
-- toggles them: whatever the base layer configured applies here too.
--
-- Omarchy defaults retired in bindings.lua are not reintroduced here: no
-- YouTube, X, Signal, 1Password, browser-on-SHIFT-RETURN, calendar or F9.

local uwsmLaunch = "uwsm-app --"
local terminal = uwsmLaunch .. " xdg-terminal-exec"
local omarchyLaunchBrowser = "omarchy launch browser"
local launchWebapp = "omarchy-launch-webapp"
local scratchpadPrefix = "Scratchpad:"

-- Keycodes, needed only for the Omarchy defaults that are written as code:NN
-- rather than by keysym (the coarse resize steps, the bracket-key webcam
-- overlay controls, and the silent workspace moves).
local key = {
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
  minus = "code:20",
  equal = "code:21",
  o = "code:32",
  bracketleft = "code:34",
  bracketright = "code:35",
}

local function bind(keys, action, description, opts)
  opts = opts or {}
  opts.description = description
  hl.bind(keys, action, opts)
end

local function exec(keys, command, description, opts)
  bind(keys, hl.dsp.exec_cmd(command), description, opts)
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

local function scratchpad(keys, name, opts)
  opts = opts or {}
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

-- Universal clipboard, mirroring default/hypr/bindings/clipboard.lua. Explicit
-- mods with no window target so the chord reaches both normal windows and
-- focused layer-shell surfaces such as the Omarchy panels; the down/up split
-- works around send_shortcut sometimes leaving synthetic key state stuck. A
-- virtual keyboard (wtype) will not do, because the physically held SUPER
-- merges into the injected chord at the seat.
local function send_shortcut_once(mods, key)
  return function()
    hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "down" }))
    hl.timer(function()
      hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "up" }))
    end, { timeout = 50, type = "oneshot" })
  end
end

-- Lean on the terminal tag so there is one definition of what counts as a
-- terminal. Dynamic tags carry a trailing "*".
local function active_window_is_terminal()
  local window = hl.get_active_window()
  if not window then
    return false
  end
  for _, tag in ipairs(window.tags or {}) do
    if tag:gsub("%*$", "") == "terminal" then
      return true
    end
  end
  return false
end

local function universal_clipboard_shortcut(default_mods, default_key, terminal_mods, terminal_key)
  return function()
    if active_window_is_terminal() then
      send_shortcut_once(terminal_mods, terminal_key)()
    else
      send_shortcut_once(default_mods, default_key)()
    end
  end
end

hl.define_submap("cyber", function()
  -- ##########################
  -- #### Workspace Mngmnt ####
  -- ###                    ###

  -- Switch workspaces with SUPER + [0-9], move with SUPER + SHIFT + [0-9].
  for _, item in ipairs({
    { label = "1", workspace = 1 },
    { label = "2", workspace = 2 },
    { label = "3", workspace = 3 },
    { label = "4", workspace = 4 },
    { label = "5", workspace = 5 },
    { label = "6", workspace = 6 },
    { label = "7", workspace = 7 },
    { label = "8", workspace = 8 },
    { label = "9", workspace = 9 },
    { label = "0", workspace = 10 },
  }) do
    bind("SUPER + " .. item.label, hl.dsp.focus({ workspace = item.workspace }), "Switch to workspace " .. item.workspace)
    bind(
      "SUPER + SHIFT + " .. item.label,
      hl.dsp.window.move({ workspace = item.workspace }),
      "Move window to workspace " .. item.workspace
    )
  end

  -- Cycle workspaces without reaching for a number. layouts.lua sets
  -- binds.workspace_back_and_forth, so revisiting a workspace returns to the
  -- previously active one rather than stepping monotonically.
  bind("SUPER + TAB", hl.dsp.focus({ workspace = "e+1" }), "Next workspace")
  bind("SUPER + SHIFT + TAB", hl.dsp.focus({ workspace = "e-1" }), "Previous workspace")
  bind("SUPER + CTRL + TAB", hl.dsp.focus({ workspace = "previous" }), "Former workspace")

  -- Move the whole workspace between monitors, and jump between them.
  for _, item in ipairs({
    { label = "LEFT", mon = "l" },
    { label = "RIGHT", mon = "r" },
    { label = "UP", mon = "u" },
    { label = "DOWN", mon = "d" },
  }) do
    bind(
      "SUPER + SHIFT + ALT + " .. item.label,
      hl.dsp.workspace.move({ monitor = item.mon }),
      "Move workspace to " .. item.label:lower() .. " monitor"
    )
  end
  bind("CTRL + ALT + TAB", hl.dsp.focus({ monitor = "+1" }), "Focus on next monitor")
  bind("CTRL + ALT + SHIFT + TAB", hl.dsp.focus({ monitor = "-1" }), "Focus on previous monitor")

  -- Arrow keys mirror the HJKL focus/swap pair; the arrow and HJKL forms are
  -- distinct binds in the base layer and stay that way here.
  for _, item in ipairs({
    { label = "LEFT", dir = "l", desc = "Move focus left" },
    { label = "RIGHT", dir = "r", desc = "Move focus right" },
    { label = "UP", dir = "u", desc = "Move focus up" },
    { label = "DOWN", dir = "d", desc = "Move focus down" },
  }) do
    bind("SUPER + " .. item.label, hl.dsp.focus({ direction = item.dir }), item.desc)
    bind(
      "SUPER + SHIFT + " .. item.label,
      hl.dsp.window.swap({ direction = item.dir }),
      (item.desc:gsub("Move focus", "Swap window"))
    )
    bind(
      "SUPER + SHIFT + CTRL + " .. item.label,
      hl.dsp.window.move({ direction = item.dir }),
      (item.desc:gsub("Move focus", "Move window"))
    )
  end

  -- Cycle windows without alt-tab reaching past the layer.
  bind("ALT + TAB", hl.dsp.window.cycle_next(), "Focus on next window")
  bind("ALT + SHIFT + TAB", hl.dsp.window.cycle_next({ next = false }), "Focus on previous window")
  exec("CTRL + ALT + DELETE", "omarchy-hyprland-window-close-all", "Close all windows")

  -- Move the focused window to a workspace without following it there.
  for workspace, code in ipairs({
    key.one, key.two, key.three, key.four, key.five,
    key.six, key.seven, key.eight, key.nine, key.zero,
  }) do
    bind(
      "SUPER + SHIFT + ALT + " .. code,
      hl.dsp.window.move({ workspace = workspace, follow = false }),
      "Move window silently to workspace " .. workspace
    )
  end

  -- Coarse resize steps. The plain SUPER and SUPER+SHIFT pairs are unbound in
  -- the base layer, so only the four remaining modifier stacks are mirrored.
  for _, item in ipairs({
    { mods = "SUPER + CTRL + ", x = -300, y = 0, desc = "Expand window left a lot" },
    { mods = "SUPER + CTRL + ", x = 300, y = 0, desc = "Shrink window left a lot" },
    { mods = "SUPER + SHIFT + CTRL + ", x = 0, y = -300, desc = "Shrink window up a lot" },
    { mods = "SUPER + SHIFT + CTRL + ", x = 0, y = 300, desc = "Expand window down a lot" },
    { mods = "SUPER + ALT + ", x = -25, y = 0, desc = "Expand window left a little" },
    { mods = "SUPER + ALT + ", x = 25, y = 0, desc = "Shrink window left a little" },
    { mods = "SUPER + SHIFT + ALT + ", x = 0, y = -25, desc = "Shrink window up a little" },
    { mods = "SUPER + SHIFT + ALT + ", x = 0, y = 25, desc = "Expand window down a little" },
  }) do
    for _, k in ipairs({ key.minus, key.equal }) do
      bind(item.mods .. k, hl.dsp.window.resize({ x = item.x, y = item.y, relative = true }), item.desc, { repeating = true })
    end
  end

  -- Omarchy's own scratchpad, which launches omarchy-agent. The cyber layer
  -- keeps its own sup_* scratchpads; this one is the agent drawer.
  bind("SUPER + grave", hl.dsp.workspace.toggle_special("scratchpad"), "Toggle scratchpad")
  bind(
    "SUPER + SHIFT + grave",
    hl.dsp.window.move({ workspace = "special:scratchpad", follow = false }),
    "Move window to scratchpad"
  )

  -- Move focus between windows.
  for _, item in ipairs({
    { label = "H", dir = "l", desc = "Move focus left" },
    { label = "L", dir = "r", desc = "Move focus right" },
    { label = "J", dir = "d", desc = "Move focus down" },
    { label = "K", dir = "u", desc = "Move focus up" },
  }) do
    bind("SUPER + " .. item.label, hl.dsp.focus({ direction = item.dir }), item.desc)
    bind(
      "SUPER + SHIFT + " .. item.label,
      hl.dsp.window.swap({ direction = item.dir }),
      (item.desc:gsub("Move focus", "Swap window"))
    )
    bind(
      "SUPER + SHIFT + CTRL + " .. item.label,
      hl.dsp.window.move({ direction = item.dir }),
      (item.desc:gsub("Move focus", "Move window"))
    )
  end

  -- Toggle floating on active window.
  bind("SUPER + SHIFT + CTRL + ALT + F", hl.dsp.window.float({ action = "toggle" }), "Toggle floating on active window")

  -- Nudge floating windows for manual repositioning.
  local nudgeFactor = 20
  for _, item in ipairs({
    { label = "H", x = -nudgeFactor, y = 0, desc = "Nudge window to the left (floating windows)" },
    { label = "L", x = nudgeFactor, y = 0, desc = "Nudge window to the right (floating windows)" },
    { label = "J", x = 0, y = -nudgeFactor, desc = "Nudge window down (floating windows)" },
    { label = "K", x = 0, y = nudgeFactor, desc = "Nudge window up (floating windows)" },
  }) do
    bind(
      "SUPER + SHIFT + ALT + " .. item.label,
      hl.dsp.window.move({ x = item.x, y = item.y, relative = true }),
      item.desc
    )
  end

  -- Resize active window natively.
  bind("SUPER + CTRL + H", function() hl.dispatch(hl.dsp.window.resize({ x = -resizeStep("width"), y = 0, relative = true })) end, "Expand window horizontal", { repeating = true })
  bind("SUPER + CTRL + L", function() hl.dispatch(hl.dsp.window.resize({ x =  resizeStep("width"), y = 0, relative = true })) end, "Shrink window horizontal", { repeating = true })
  bind("SUPER + CTRL + K", function() hl.dispatch(hl.dsp.window.resize({ x = 0, y =  resizeStep("height"), relative = true })) end, "Expand window vertical", { repeating = true })
  bind("SUPER + CTRL + J", function() hl.dispatch(hl.dsp.window.resize({ x = 0, y = -resizeStep("height"), relative = true })) end, "Shrink window vertical", { repeating = true })

  -- Close active window.
  bind("SUPER + W", hl.dsp.window.close(), "Close active window")

  -- Fullscreen states.
  local maximizeToggle =
    'if [ "$(hyprctl activewindow -j | jq -r \'.fullscreen\')" = "1" ]; then hyprctl dispatch \'hl.dsp.window.fullscreen_state({ internal = 0, client = -1, action = "set" })\'; else hyprctl dispatch \'hl.dsp.window.fullscreen_state({ internal = 1, client = -1, action = "set" })\'; fi'
  exec("SUPER + F", maximizeToggle, "Maximize active window")
  bind(
    "SUPER + SHIFT + F",
    hl.dsp.window.fullscreen_state({ internal = 2, client = 0, action = "toggle" }),
    "Window fullscreen (client unaware)"
  )
  bind(
    "SUPER + CTRL + F",
    hl.dsp.window.fullscreen_state({ internal = 0, client = 2, action = "toggle" }),
    "In-client fullscreen (window unaware)"
  )
  bind(
    "SUPER + ALT + F",
    hl.dsp.window.fullscreen_state({ internal = 3, client = 3, action = "toggle" }),
    "Typical fullscreen"
  )
  bind(
    "SUPER + SHIFT + CTRL + F",
    hl.dsp.window.fullscreen_state({ internal = 0, client = 0, action = "set" }),
    "Default window state"
  )

  -- Master-layout binds, mirrored from layouts.lua.
  bind("SUPER + S", hl.dsp.layout("swapwithmaster"), "Swap Focused Window <-> Master")
  bind("SUPER + SHIFT + S", hl.dsp.layout("orientationnext"), "Cycle Workspace Orientation (Master Layout)")
  bind("SUPER + N", hl.dsp.layout("rollprev"), "Roll to Prev Window (Master Layout)")
  bind("SUPER + SHIFT + N", hl.dsp.layout("rollnext"), "Roll to Next Window (Master Layout)")
  exec("SUPER + ALT + Backspace", "hyprland-workspace-layout", "Cycle Workspace Layout")

  -- ###                    ###
  -- #### Workspace Mngmnt ####
  -- ##########################

  -- ##########################
  -- ######## Display #########
  -- ###                    ###

  exec("SUPER + SHIFT + Equal", "omarchy-hyprland-monitor-scaling up", "Display Scale - Increase")
  exec("SUPER + SHIFT + Minus", "omarchy-hyprland-monitor-scaling down", "Display Scale - Decrease")
  exec("SUPER + SHIFT + Backspace", "hyprland-window-gaps-cycle", "Cycle Window Gap Size")
  exec("SUPER + CTRL + Backspace", "hyprland-window-borders-cycle", "Cycle Window Border Thickness")
  exec("SUPER + SHIFT + CTRL + ALT + Backspace", "hyprland-window-round-toggle", "Toggle Window Rounding")

  -- ###                    ###
  -- ######## Display #########
  -- ##########################

  -- ##########################
  -- #### Omarchy Shell ######
  -- ###                    ###

  -- System menus.
  exec("SUPER + ESCAPE", "omarchy-menu toggle system", "System menu")
  exec("SUPER + ALT + SPACE", "omarchy-menu toggle apps", "Apps menu")
  exec("SUPER + CTRL + SPACE", "omarchy-menu toggle background", "Background switcher")
  exec("SUPER + SHIFT + CTRL + SPACE", "omarchy-menu toggle theme", "Theme menu")
  exec("SUPER + CTRL + O", "omarchy-menu toggle toggle", "Toggle menu")
  exec("SUPER + CTRL + C", "omarchy-menu toggle capture", "Capture menu")
  exec("SUPER + CTRL + S", "omarchy-menu toggle share", "Share")
  exec("SUPER + CTRL + R", "omarchy-menu toggle reminder-set", "Set reminder")

  -- Panels. The network and bluetooth toggles live in the System Apps section
  -- above, as plain execs rather than shell panels.
  exec("SUPER + CTRL + B", "omarchy-shell shell toggle omarchy.bluetooth", "Bluetooth")
  exec("SUPER + CTRL + D", "omarchy-shell shell toggle omarchy.monitor", "Display")
  exec("SUPER + CTRL + N", "omarchy-shell shell toggle omarchy.nightlight", "Nightlight")
  exec("SUPER + CTRL + E", "omarchy-shell shell toggle omarchy.emojis", "Emojis")
  exec("SUPER + CTRL + ALT + D", "omarchy-shell shell toggle omarchy.clock", "Calendar")
  exec("SUPER + CTRL + ALT + E", "omarchy-shell shell toggle omarchy.elsewhen", "World clock")

  -- Toggles and transient OSDs.
  exec("SUPER + CTRL + Q", "omacalc", "Calculator")
  exec("SUPER + CTRL + I", "omarchy-toggle-idle", "Toggle locking on idle")
  exec("SUPER + CTRL + ALT + F", "omarchy-toggle-fullscreen-desktop", "Toggle full screen desktop")
  exec("SUPER + BACKSPACE", "omarchy-hyprland-window-transparency-toggle", "Toggle window transparency")
  exec("SUPER + CTRL + DELETE", "omarchy-hyprland-monitor-internal toggle", "Toggle laptop display")
  exec("SUPER + CTRL + ALT + DELETE", "omarchy-hyprland-monitor-internal-mirror toggle", "Toggle laptop display mirroring")
  exec("SUPER + CTRL + ALT + T", "omarchy-notification-time", "Show time")
  exec("SUPER + CTRL + ALT + B", "omarchy-notification-battery", "Show battery remaining")
  exec("SUPER + CTRL + ALT + W", "omarchy-notification-weather", "Toggle weather")
  exec("SUPER + CTRL + ALT + R", "omarchy-reminder show", "Show reminders")
  exec("SUPER + SHIFT + CTRL + R", "omarchy-reminder clear", "Clear reminders")
  exec("SUPER + SHIFT + CTRL + A", "omarchy-agent --pick", "Agent")
  exec("SUPER + CTRL + PERIOD", "omarchy-transcode", "Transcode")

  -- Cursor zoom, which reads and writes the live config value.
  bind("SUPER + CTRL + Z", function()
    local zoom = hl.get_config("cursor.zoom_factor") or 1
    hl.config({ cursor = { zoom_factor = zoom + 1 } })
  end, "Zoom in")
  bind("SUPER + CTRL + ALT + Z", function()
    hl.config({ cursor = { zoom_factor = 1 } })
  end, "Reset zoom")

  -- Terminal-hosted tools. Omarchy exposes these as launcher scripts.
  exec("SUPER + CTRL + RETURN", "omarchy-launch-terminal-herdr", "Herdr")
  exec("SUPER + ALT + RETURN", "omarchy-launch-terminal-tmux", "Tmux")
  exec("SUPER + ALT + K", "omarchy-menu-tmux-keybindings", "Tmux keybindings")

  -- Notifications. SUPER + comma itself is the sup_comma scratchpad in this
  -- layer, so only the remaining modifier stacks are available here.
  exec("SUPER + SHIFT + comma", "omarchy-shell notifications dismissAll", "Dismiss all notifications")
  exec("SUPER + CTRL + comma", "omarchy-toggle-notification-silencing", "Toggle silencing notifications")
  exec("SUPER + ALT + comma", "omarchy-shell notifications invokeLast", "Invoke last notification")
  exec("SUPER + SHIFT + ALT + comma", "omarchy-shell notifications showHistory", "Open notification history")

  -- ###                    ###
  -- #### Omarchy Shell ######
  -- ##########################

  -- ##########################
  -- ##### Screen Capture #####
  -- ###                    ###

  exec("SUPER + Semicolon", 'grim -g "$(slurp -w 0)" - | wl-copy', "Screenshot of region to clipboard")
  exec("SUPER + ALT + Semicolon", "omarchy-menu toggle trigger.capture.screenrecord", "Screen Record")
  exec("SUPER + R", "omarchy-capture-screenrecording --with-desktop-audio --with-microphone-audio", "Screen Record")
  exec("SUPER + SHIFT + R", "omarchy-capture-screenrecording --stop-recording", "Stop Screen Recording")
  exec("SUPER + PRINT", "omarchy-capture-text", "Extract text (OCR) from screenshot")
  exec("PRINT", "omarchy-capture-screenshot", "Screenshot")
  exec("ALT + PRINT", "omarchy-capture-screenrecording --stop-recording || omarchy-menu toggle trigger.capture.screenrecord", "Screenrecording")

  -- ###                    ###
  -- ##### Screen Capture #####
  -- ##########################

  -- ##########################
  -- ###### Clipboard #########
  -- ###                    ###

  -- Universal copy/paste. These send the chord to the focused surface rather
  -- than dispatching a clipboard action, so they work inside terminals,
  -- browsers and the Omarchy panels alike.
  --
  -- There is no select-all here: the base layer gives SUPER + A to the browser
  -- and cyber mirrors that, so select-all has no home. Use the focused
  -- window's own chord (CTRL+A) instead.
  bind("SUPER + C", universal_clipboard_shortcut("CTRL", "C", "CTRL SHIFT", "C"), "Universal copy")
  bind("SUPER + V", universal_clipboard_shortcut("CTRL", "V", "CTRL SHIFT", "V"), "Universal paste")
  bind("SUPER + X", send_shortcut_once("CTRL", "X"), "Universal cut")
  exec("SUPER + CTRL + V", "omarchy-shell shell toggle omarchy.clipboard", "Clipboard manager")


  -- ##########################
  -- ##### Audio & Media ######
  -- ###                    ###

  -- Omarchy binds these in the default submap only, so the keys go dead the
  -- moment cyber is entered and every one has to be redeclared here. Command
  -- forms match what default/hypr/bindings/media.lua resolves to.
  exec("XF86AudioRaiseVolume", "omarchy-audio-output-volume raise", "Volume up", { locked = true, repeating = true })
  exec("XF86AudioLowerVolume", "omarchy-audio-output-volume lower", "Volume down", { locked = true, repeating = true })
  exec("XF86AudioMute", "omarchy-audio-output-volume mute-toggle", "Mute", { locked = true })
  exec("SHIFT + XF86AudioMute", "omarchy-audio-output-switch", "Switch audio output", { locked = true })
  exec("ALT + XF86AudioRaiseVolume", "omarchy-audio-output-volume +1", "Volume up precise", { locked = true, repeating = true })
  exec("ALT + XF86AudioLowerVolume", "omarchy-audio-output-volume -1", "Volume down precise", { locked = true, repeating = true })
  exec("XF86AudioMicMute", "omarchy-audio-input-mute-smart", "Mute microphone", { locked = true, repeating = true })
  exec("SHIFT + XF86AudioPause", "omarchy-audio-source-switch", "Switch media source", { locked = true })
  exec("SHIFT + XF86AudioPlay", "omarchy-audio-source-switch", "Switch media source", { locked = true })
  exec("XF86AudioNext", "omarchy-shell media next", "Next track", { locked = true })
  exec("XF86AudioPrev", "omarchy-shell media previous", "Previous track", { locked = true })
  exec("XF86AudioPlay", "omarchy-shell media playPause", "Play", { locked = true })
  exec("XF86AudioPause", "omarchy-shell media playPause", "Pause", { locked = true })
  exec("XF86MonBrightnessUp", "omarchy-brightness-display +5%", "Brightness up", { locked = true, repeating = true })
  exec("XF86MonBrightnessDown", "omarchy-brightness-display 5%-", "Brightness down", { locked = true, repeating = true })
  exec("ALT + XF86MonBrightnessUp", "omarchy-brightness-display +1%", "Brightness up precise", { locked = true, repeating = true })
  exec("ALT + XF86MonBrightnessDown", "omarchy-brightness-display 1%-", "Brightness down precise", { locked = true, repeating = true })
  exec("SHIFT + XF86MonBrightnessUp", "omarchy-brightness-display 100%", "Brightness maximum", { locked = true, repeating = true })
  exec("SHIFT + XF86MonBrightnessDown", "omarchy-brightness-display 1%", "Brightness minimum", { locked = true, repeating = true })
  exec("XF86KbdBrightnessUp", "omarchy-brightness-keyboard up", "Keyboard brightness up", { locked = true, repeating = true })
  exec("XF86KbdBrightnessDown", "omarchy-brightness-keyboard down", "Keyboard brightness down", { locked = true, repeating = true })
  exec("XF86KbdLightOnOff", "omarchy-brightness-keyboard cycle", "Keyboard backlight cycle", { locked = true })
  exec("ALT + XF86AudioPlay", "omarchy-shell media next", "Next track", { locked = true })
  exec("ALT + SHIFT + XF86AudioPlay", "omarchy-shell media previous", "Previous track", { locked = true })
  exec("XF86Eject", "eject", "Eject media", { locked = true })

  -- ##########################
  -- #### Hardware Extras ####
  -- ###                    ###

  exec("XF86Calculator", "omacalc", "Calculator", { locked = true })
  exec("XF86PowerOff", "omarchy-menu toggle system", "Power menu", { locked = true })
  exec("XF86TouchpadToggle", "omarchy-toggle-touchpad", "Toggle touchpad", { locked = true })
  exec("XF86TouchpadOn", "omarchy-toggle-touchpad on", "Enable touchpad", { locked = true })
  exec("XF86TouchpadOff", "omarchy-toggle-touchpad off", "Disable touchpad", { locked = true })

  -- ###                    ###
  -- #### Hardware Extras ####
  -- ##########################

  -- ###                    ###
  -- ##### Audio & Media ######
  -- ##########################

  -- ##########################
  -- ###### System Apps #######
  -- ###                    ###

  exec("SUPER + Space", "omarchy-menu", "Omarchy menu")
  exec("SUPER + Return", "omarchy-menu toggle apps", "Launch apps")
  exec("SUPER + SHIFT + T", terminal, "Terminal")
  exec("SUPER + E", uwsmLaunch .. " nautilus --new-window", "File manager")
  exec("SUPER + SHIFT + ALT + E", "omarchy-launch-nautilus-cwd", "File manager (cwd)")
  exec("SUPER + SHIFT + CTRL + ALT + P", "pkill hyprpicker || hyprpicker -a", "Color picker")
  exec("SUPER + B", omarchyLaunchBrowser, "Browser")
  exec("SUPER + A", omarchyLaunchBrowser, "Browser")
  exec(
    "SUPER + SHIFT + B",
    "command -v qutebrowser >/dev/null 2>&1 && " .. uwsmLaunch .. " qutebrowser || " .. omarchyLaunchBrowser,
    "Qutebrowser"
  )

  -- Wipe the whole clipboard history.
  exec(
    "SUPER + SHIFT + CTRL + ALT + V",
    "$HOME/.config/hypr/scripts/clipboard-history-wipe",
    "Wipe clipboard history"
  )

  exec("SUPER + SHIFT + CTRL + ALT + K", "omarchy-menu-keybindings", "Show key bindings")
  exec("SUPER + SHIFT + I", "hyprland-toggle-i3-mode", "Toggle i3 mode")

  -- Network / Bluetooth, and the tmux sessionizer.
  exec("SUPER + CTRL + W", "omarchy-shell shell toggle omarchy.network", "Network")
  exec("SUPER + ALT + W", "omarchy-shell shell toggle omarchy.bluetooth", "Bluetooth")
  exec("SUPER + CTRL + T", terminal .. " -e tmux-sessionizer", "Open tmux sessionizer")

  -- ###                    ###
  -- ###### System Apps #######
  -- ##########################

  -- ##########################
  -- ##### Voice Capture ######
  -- ###                    ###

  hl.bind(
    "SUPER + Apostrophe",
    hl.dsp.send_shortcut({
      mods = "SHIFT + CTRL",
      key = "M",
      window = "class:^(vesktop)$",
    }),
    { description = "Discord Mute Toggle" }
  )

  if o.cmd_present("voxtype") then
    exec("SUPER + D", "$HOME/.config/hypr/scripts/voxtype-record-toggle", "Toggle dictation")
  end

  -- ###                    ###
  -- ##### Voice Capture ######
  -- ##########################

  -- ##########################
  -- ####### Utilities ########
  -- ###                    ###

  exec("SUPER + ALT + P", terminal .. " -e btop", "Task Manager")
  exec("SUPER + SHIFT + A", launchWebapp .. ' "https://www.perplexity.ai/"', "Perplexity Web")
  exec("SUPER + CTRL + A", launchWebapp .. ' "https://claude.ai"', "Claude Web")
  exec("SUPER + ALT + A", launchWebapp .. ' "https://chatgpt.com"', "ChatGPT Web")

  -- ###                    ###
  -- ####### Utilities ########
  -- ##########################

  -- ####################################################
  -- ################### SCRATCHPADS ####################
  -- #####    (Scratchpad == Special Workspace)    #####

  -- ##########################
  -- #### Sys, Terms, TUI #####
  -- ###                    ###

  scratchpad("SUPER + T", "sup_t", {
    move_keys = "SUPER + SHIFT + CTRL + T",
    move_description = "Move to sup_t's dropdown",
  })

  scratchpad("SUPER + G", "sup_g", { move_keys = "SUPER + SHIFT + CTRL + G" })

  scratchpad("SUPER + SHIFT + D", "sup_sft_d")
  scratchpad("SUPER + SHIFT + W", "sup_sft_w")
  scratchpad("SUPER + P", "sup_p")

  -- ###                    ###
  -- #### Sys, Terms, TUI #####
  -- ##########################

  -- ##########################
  -- ### Empty Scratchpads ####
  -- ###                    ###

  scratchpad("SUPER + Q", "sup_q", { move_keys = "SUPER + SHIFT + CTRL + Q" })
  scratchpad("SUPER + Period", "sup_period", { move_keys = "SUPER + SHIFT + CTRL + Period" })
  scratchpad("SUPER + Minus", "sup_minus", { move_keys = "SUPER + SHIFT + CTRL + Minus" })
  scratchpad("SUPER + Y", "sup_y", { move_keys = "SUPER + SHIFT + CTRL + Y" })

  -- ###                    ###
  -- ### Empty Scratchpads ####
  -- ##########################

  -- ##########################
  -- ####### Misc Apps ########
  -- ###                    ###

  scratchpad("SUPER + Comma", "sup_comma", { move_keys = "SUPER + SHIFT + CTRL + Comma" })
  scratchpad("SUPER + Slash", "sup_slash", { move_keys = "SUPER + SHIFT + CTRL + Slash" })

  scratchpad("SUPER + O", "sup_o", { move_keys = "SUPER + SHIFT + CTRL + O" })
  exec("SUPER + SHIFT + O", uwsmLaunch .. " obsidian -disable-gpu", "Obsidian")

  scratchpad("SUPER + CTRL + M", "sup_ctl_m")
  scratchpad("SUPER + M", "sup_m")
  scratchpad("SUPER + SHIFT + P", "sup_sft_p")
  scratchpad("SUPER + CTRL + P", "sup_ctl_p")

  -- ###                    ###
  -- ####### Misc Apps ########
  -- ##########################

  -- ##########################
  -- ######## Webapps #########
  -- ###                    ###

  scratchpad("SUPER + U", "sup_u")
  scratchpad("SUPER + ALT + B", "sup_alt_b")
  scratchpad("SUPER + I", "sup_i")

  scratchpad("SUPER + Equal", "sup_equal")
  scratchpad("SUPER + ALT + Equal", "sup_alt_equal")

  -- ###                    ###
  -- ######## Webapps #########
  -- ##########################

  -- ####################################################
  -- ################### SCRATCHPADS ####################
  -- ####################################################

  -- ##########################
  -- ###### Mouse Controls ####
  -- ###                    ###

  -- Drag and resize. These need { mouse = true } (BIND_FLAG_MOUSE) for the
  -- press/release pair to resolve as one gesture rather than two binds.
  bind("SUPER + mouse:272", hl.dsp.window.drag(), "Move window", { mouse = true })
  bind("SUPER + mouse:273", hl.dsp.window.resize(), "Resize window", { mouse = true })

  -- Scroll the active workspace.
  bind("SUPER + mouse_down", hl.dsp.focus({ workspace = "e+1" }), "Scroll active workspace forward")
  bind("SUPER + mouse_up", hl.dsp.focus({ workspace = "e-1" }), "Scroll active workspace backward")

  -- Step through the active group.
  bind("SUPER + ALT + mouse_down", hl.dsp.group.next(), "Next window in group")
  bind("SUPER + ALT + mouse_up", hl.dsp.group.prev(), "Previous window in group")

  -- ###                    ###
  -- ###### Mouse Controls ####
  -- ##########################

  -- ##########################
  -- ###### Final Parity ######
  -- ###                    ###

  -- Remaining base-layer defaults, so this layer really is a mirror.

  -- Monitor scaling, the down half of the pair above.
  exec("SUPER + ALT + SLASH", "omarchy-hyprland-monitor-scaling down", "Monitor scaling down")

  -- Omarchy's OCR chord. This layer puts OCR on the bare SUPER + PRINT, but
  -- the stock combo costs nothing and may already be muscle memory.
  exec("SUPER + CTRL + PRINT", "omarchy-capture-text", "Extract text (OCR) from screenshot")

  -- The keycode twin of the sup_o scratchpad toggle. bindings.lua binds that
  -- one by code: rather than by keysym, so both spellings exist side by side.
  bind("SUPER + " .. key.o, hl.dsp.workspace.toggle_special("sup_o"), "Scratchpad: sup_o")

  -- Move the focused window into the primary browser scratchpad, matching the
  -- toggle above which has no move key of its own in this layer.
  bind(
    "SUPER + SHIFT + CTRL + U",
    hl.dsp.window.move({ workspace = "special:sup_u" }),
    "Move window to sup_u"
  )

  -- Webcam overlay resize.
  exec("SUPER + ALT + " .. key.bracketleft, "omarchy-capture-webcam-resize smaller", "Make webcam overlay smaller")
  exec("SUPER + ALT + " .. key.bracketright, "omarchy-capture-webcam-resize larger", "Make webcam overlay larger")

  -- Lid switch. Not a keypress: Hyprland emits these when the lid opens and
  -- closes, so there is nothing to press and nothing can shadow them.
  exec("switch:on:Lid Switch", "omarchy-system-lid-close", "Lid closed", { locked = true })
  exec("switch:off:Lid Switch", "omarchy-hyprland-monitor-clamshell", "Lid opened", { locked = true })

  -- Top bar visibility, and Omarchy's stock dictation chord alongside the
  -- personal SUPER + D toggle in the Voice Capture section above.
  exec("SUPER + SHIFT + SPACE", "omarchy-toggle-bar", "Toggle top bar")
  if o.cmd_present("voxtype") then
    exec("SUPER + CTRL + X", "voxtype record toggle", "Toggle dictation")
  end

  -- Send the Moonlight-focus chord to a live stream window when one exists.
  bind(
    "SHIFT + CTRL + ALT + code:52",
    hl.dsp.send_shortcut({
      mods = "SHIFT + CTRL + ALT",
      key = "code:52",
      window = "class:com.moonlight_stream.Moonlight",
    }),
    "Toggle Moonlight Focus"
  )

  -- Move the focused window into Omarchy's own scratchpad, the counterpart to
  -- the SUPER + grave toggle above.
  bind(
    "SUPER + ALT + S",
    hl.dsp.window.move({ workspace = "special:scratchpad", follow = false }),
    "Move window to scratchpad"
  )

  -- Entries into the gaps-resize and VM-passthrough submaps. Both replace the
  -- active submap rather than stacking on it, so taking either one from cyber
  -- leaves cyber and its exit chord behind; Escape returns to the base layer.
  bind("SUPER + CTRL + G", function()
    hl.dispatch(hl.dsp.submap("gaps-resize"), { description = "Submap: Desktop Resizing" })
  end, "Submap: Desktop Resizing")
  bind("SUPER + Delete", function()
    hl.dispatch(hl.dsp.submap("passthru"), { description = "Submap: Modkey VM Passthru" })
  end, "Submap: Modkey VM Passthru")

  -- ###                    ###
  -- ###### Final Parity ######
  -- ##########################

  -- ##########################
  -- ###### Leave Cyber ######
  -- ###                    ###

  -- Exit is the same chord as entry. Escape and Delete are deliberately left
  -- unbound here: both are first-class keys in cyber work (dismissing dialogs,
  -- clearing selections), and a submap bind cannot pass a key through to the
  -- focused window anyway, so binding them would only ever swallow the press.
  bind("SUPER + CTRL + ALT + C", function()
    hl.dispatch(hl.dsp.submap("reset"), { description = "End Cyber submap" })
    hl.dispatch(hl.dsp.exec_cmd('omarchy-notification-send "Cyber submap off"'))
  end, "Exit cyber submap")

  -- ###                    ###
  -- ###### Leave Cyber ######
  -- ##########################
end)

-- ##########################
-- ###### Enter Cyber ######
-- ###                    ###

hl.bind("SUPER + CTRL + ALT + C", function()
  hl.dispatch(hl.dsp.submap("cyber"), { description = "Submap: Cyber" })
  hl.dispatch(hl.dsp.exec_cmd('omarchy-notification-send "Cyber submap on" "SUPER+CTRL+ALT+C to exit"'))
end, { description = "Submap: Cyber" })

-- ###                    ###
-- ###### Enter Cyber ######
-- ##########################
