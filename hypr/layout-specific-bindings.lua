-- Layout defaults, workspace layout cycling, and conditional per-layout keybindings.

local paths = require("default.hypr.paths")

-- Ensure ~/.local/bin precedes /usr/share/omarchy/bin inside Hyprland's
-- keybind dispatcher environment so our omarchy-hyprland-workspace-layout-toggle
-- override takes precedence over Omarchy's packaged script.
do
  local home = os.getenv("HOME") or ""
  local user_bin = home .. "/.local/bin"
  local current_path = os.getenv("PATH") or "/usr/local/bin:/usr/bin"
  local omarchy_bin = (os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/bin"
  local entries = { user_bin, omarchy_bin }
  for entry in current_path:gmatch("[^:]+") do
    if entry ~= user_bin and entry ~= omarchy_bin then
      table.insert(entries, entry)
    end
  end
  hl.env("PATH", table.concat(entries, ":"))
end

-- Set master as the default workspace layout (prior to dwindle, scrolling, floating).
hl.config({
  general = {
    layout = "master",
  },
  master = {
    orientation = "left",
    new_status = "slave",
    mfact = 0.5,
    slave_count_for_center_master = 0,
  },
})

-- ── Conditional Per-Layout Bindings ────────────────────────────────────────
local layout_modules = {
  master = require("hypr.layouts.master"),
  dwindle = require("hypr.layouts.dwindle"),
  scrolling = require("hypr.layouts.scrolling"),
  floating = require("hypr.layouts.floating"),
}

local active_layout_mode = nil

local function saved_workspace_mode(workspace_id)
  if not workspace_id or tonumber(workspace_id) < 1 then
    return nil
  end
  local dir = paths.state_home .. "/omarchy/workspace-layouts"
  local f = io.open(dir .. "/" .. tostring(workspace_id) .. ".lua", "r")
  if f then
    local content = f:read("*a") or ""
    f:close()
    local mode = content:match('mode%s*=%s*"([%a]+)"')
    if mode then
      return mode
    end
  end
  local def = io.open(dir .. "/default.lua", "r")
  if def then
    local content = def:read("*a") or ""
    def:close()
    local mode = content:match('default%s*=%s*"([%a]+)"')
    if mode then
      return mode
    end
  end
  return nil
end

local function detect_active_layout()
  local ws = hl.get_active_workspace and hl.get_active_workspace() or nil
  local ws_id = ws and ws.id or nil
  local saved = saved_workspace_mode(ws_id)
  if saved then
    return saved
  end
  if ws and ws.tiledLayout and ws.tiledLayout ~= "" then
    return ws.tiledLayout
  end
  return hl.get_config("general.layout") or "master"
end

function o.sync_layout_bindings(explicit_mode)
  local mode = explicit_mode or detect_active_layout()
  if mode == active_layout_mode then
    return
  end

  if active_layout_mode and layout_modules[active_layout_mode] and layout_modules[active_layout_mode].disable then
    layout_modules[active_layout_mode].disable()
  end

  active_layout_mode = mode

  if layout_modules[mode] and layout_modules[mode].enable then
    layout_modules[mode].enable()
  end
end

-- Apply initial layout bindings and re-sync whenever switching workspaces or monitors.
o.sync_layout_bindings("master")
hl.on("workspace.active", function()
  o.sync_layout_bindings()
end)
hl.on("monitor.focused", function()
  o.sync_layout_bindings()
end)
hl.on("config.reloaded", function()
  active_layout_mode = nil
  o.sync_layout_bindings()
end)
