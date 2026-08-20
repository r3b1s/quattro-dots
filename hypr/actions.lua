local M = {}

local STATE_KEY = "__omarchy_overrides_hypr_actions_state"
local RULES_KEY = "__omarchy_overrides_window_rules"
local state = rawget(_G, STATE_KEY)

if not state then
	state = {
		i3_mode = {
			active = false,
			snapshot = nil,
		},
	}
	_G[STATE_KEY] = state
end

local gaps_presets = {
	{
		gaps_out = { top = 10, right = 100, bottom = 10, left = 100 },
		gaps_in = 6,
		label = "Window gaps: inner 6px, outer 10/100/10/100",
	},
	{ gaps_out = 100, gaps_in = 6, label = "Window gaps: inner 6px, outer 100px" },
	{ gaps_out = 50, gaps_in = 6, label = "Window gaps: inner 6px, outer 50px" },
	{ gaps_out = 30, gaps_in = 15, label = "Window gaps: inner 15px, outer 30px" },
	{ gaps_out = 20, gaps_in = 10, label = "Window gaps: inner 10px, outer 20px" },
	{ gaps_out = 10, gaps_in = 5, label = "Window gaps: inner 5px, outer 10px" },
	{ gaps_out = 8, gaps_in = 4, label = "Window gaps: inner 4px, outer 8px" },
	{ gaps_out = 6, gaps_in = 3, label = "Window gaps: inner 3px, outer 6px" },
	{ gaps_out = 4, gaps_in = 2, label = "Window gaps: inner 2px, outer 4px" },
	{ gaps_out = 0, gaps_in = 0, label = "Window gaps: inner 0px, outer 0px" },
}

local border_presets = { 16, 8, 6, 4, 3, 2, 1, 0 }
local workspace_layouts = { "master", "dwindle", "scrolling" }

local function notify(text, color, icon)
	hl.notification.create({
		text = text,
		timeout = 1500,
		color = color,
		icon = icon or "info",
	})
end

local function clone(value)
	if type(value) ~= "table" then
		return value
	end

	local copy = {}
	for key, item in pairs(value) do
		copy[key] = clone(item)
	end
	return copy
end

local function normalize_gap(value)
	if type(value) == "number" then
		return { top = value, right = value, bottom = value, left = value }
	end

	if type(value) ~= "table" then
		return { top = 0, right = 0, bottom = 0, left = 0 }
	end

	local top = tonumber(value.top or value[1] or 0) or 0
	local right = tonumber(value.right or value[2] or top) or top
	local bottom = tonumber(value.bottom or value[3] or top) or top
	local left = tonumber(value.left or value[4] or right) or right

	return {
		top = top,
		right = right,
		bottom = bottom,
		left = left,
	}
end

local function gaps_equal(lhs, rhs)
	local a = normalize_gap(lhs)
	local b = normalize_gap(rhs)

	return a.top == b.top and a.right == b.right and a.bottom == b.bottom and a.left == b.left
end

local function float_equal(lhs, rhs)
	return math.abs((tonumber(lhs) or 0) - (tonumber(rhs) or 0)) < 0.001
end

local function get_window_rules()
	local rules = rawget(_G, RULES_KEY)
	if type(rules) ~= "table" then
		rules = {}
		_G[RULES_KEY] = rules
	end

	if not rules.opaque then
		rules.opaque = hl.window_rule({
			name = "opaque",
			match = { class = ".*" },
			tag = "+OPAQUE",
		})
	end

	if not rules.clear then
		rules.clear = hl.window_rule({
			name = "clear",
			match = { class = ".*" },
			tag = "-OPAQUE",
		})
	end

	return rules
end

local function set_i3_rules(enabled)
	local rules = get_window_rules()
	rules.opaque:set_enabled(true)
	rules.clear:set_enabled(not enabled)
end

function M.cycle_gaps()
	local current_out = hl.get_config("general.gaps_out")
	local current_in = hl.get_config("general.gaps_in")
	local current_index = nil

	for index, preset in ipairs(gaps_presets) do
		if gaps_equal(current_out, preset.gaps_out) and gaps_equal(current_in, preset.gaps_in) then
			current_index = index
			break
		end
	end

	local next_preset
	if current_index then
		next_preset = gaps_presets[(current_index % #gaps_presets) + 1]
	else
		next_preset = gaps_presets[#gaps_presets]
	end

	hl.config({
		general = {
			gaps_out = clone(next_preset.gaps_out),
			gaps_in = clone(next_preset.gaps_in),
		},
	})

	notify(next_preset.label, "rgb(89b4fa)")
end

function M.toggle_rounding()
	local current_rounding = tonumber(hl.get_config("decoration.rounding")) or 0
	local next_rounding = current_rounding == 0 and 10 or 0

	hl.config({
		decoration = {
			rounding = next_rounding,
		},
	})

	notify(string.format("Window rounding: %dpx", next_rounding), next_rounding == 0 and "rgb(d20f39)" or "rgb(40a02b)")
end

function M.cycle_borders()
	local current = tonumber(hl.get_config("general.border_size")) or 0
	local next_value = border_presets[1]

	for index, value in ipairs(border_presets) do
		if value == current then
			next_value = border_presets[(index % #border_presets) + 1]
			break
		end
	end

	hl.config({
		general = {
			border_size = next_value,
		},
	})

	notify(string.format("Window borders: %dpx", next_value), "rgb(89b4fa)")
end

local function get_target_workspace()
	local active_window = hl.get_active_window()
	if active_window and active_window.workspace then
		return active_window.workspace
	end

	return hl.get_active_special_workspace() or hl.get_active_workspace()
end

function M.cycle_workspace_layout()
	local workspace = get_target_workspace()
	if not workspace then
		notify("Workspace layout failed: no active workspace", "rgb(d20f39)", "error")
		return
	end

	local current_layout = workspace.tiled_layout
	local current_index = nil
	for index, layout in ipairs(workspace_layouts) do
		if layout == current_layout then
			current_index = index
			break
		end
	end

	local next_layout
	if current_index then
		next_layout = workspace_layouts[(current_index % #workspace_layouts) + 1]
	else
		next_layout = workspace_layouts[1]
	end

	hl.workspace_rule({ workspace = workspace.config_name, layout = next_layout })
	notify(string.format("Workspace layout (%s): %s", workspace.config_name, next_layout), "rgb(89b4fa)")
end

function M.toggle_i3_mode()
	local i3_mode = state.i3_mode

	if not i3_mode.active then
		i3_mode.snapshot = {
			animations_enabled = hl.get_config("animations.enabled"),
			shadow_enabled = hl.get_config("decoration.shadow.enabled"),
			blur_enabled = hl.get_config("decoration.blur.enabled"),
			blur_special = hl.get_config("decoration.blur.special"),
			fullscreen_opacity = hl.get_config("decoration.fullscreen_opacity"),
			inactive_opacity = hl.get_config("decoration.inactive_opacity"),
			active_opacity = hl.get_config("decoration.active_opacity"),
			gaps_out = clone(hl.get_config("general.gaps_out")),
			gaps_in = clone(hl.get_config("general.gaps_in")),
			border_size = hl.get_config("general.border_size"),
			rounding = hl.get_config("decoration.rounding"),
			dim_special = hl.get_config("decoration.dim_special"),
		}

		hl.config({
			animations = {
				enabled = false,
			},
			decoration = {
				shadow = {
					enabled = false,
				},
				blur = {
					enabled = false,
					special = false,
				},
				fullscreen_opacity = 1,
				inactive_opacity = 1,
				active_opacity = 1,
				rounding = 0,
				dim_special = 1,
			},
			general = {
				gaps_out = 10,
				gaps_in = 5,
				border_size = 6,
			},
		})

		set_i3_rules(true)
		i3_mode.active = true
		notify("i3 Mode [ON]", "rgb(40a02b)", "ok")
		return
	end

	local snapshot = i3_mode.snapshot or {}
	hl.config({
		animations = {
			enabled = snapshot.animations_enabled,
		},
		decoration = {
			shadow = {
				enabled = snapshot.shadow_enabled,
			},
			blur = {
				enabled = snapshot.blur_enabled,
				special = snapshot.blur_special,
			},
			fullscreen_opacity = snapshot.fullscreen_opacity,
			inactive_opacity = snapshot.inactive_opacity,
			active_opacity = snapshot.active_opacity,
			rounding = snapshot.rounding,
			dim_special = snapshot.dim_special,
		},
		general = {
			gaps_out = clone(snapshot.gaps_out),
			gaps_in = clone(snapshot.gaps_in),
			border_size = snapshot.border_size,
		},
	})

	set_i3_rules(false)
	i3_mode.snapshot = nil
	i3_mode.active = false
	notify("i3 Mode [OFF]", "rgb(d20f39)", "warning")
end

return M
