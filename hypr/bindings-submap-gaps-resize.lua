-- Gaps Resize Submap
--
-- Enter with SUPER+CTRL+G to adjust gaps on specific axes.
--   h/l: gaps_out (sides)  |  j/k: gaps_out (top/bottom)  [5.5% step]
--   arrows: gaps_in (uniform)  [0.4% step]
--   Esc: exit submap

-- Screen-percentage step factors.
-- gaps_out: 5.5% (same as hypr/scripts/delta-resize)
-- gaps_in:  0.4% (inner gaps are smaller, uniform)
-- Uses hl.* API directly to avoid IPC deadlocks.
local FACTOR_OUT = 0.055
local FACTOR_IN = 0.001

local function mon_dim(axis)
	local mon = hl.get_active_monitor() or hl.get_monitor_at_cursor()
	local dim = mon and tonumber(mon[axis]) or (axis == "width" and 1920 or 1080)
	return dim
end

local function step_out(axis)
	return math.max(1, math.floor(mon_dim(axis) * FACTOR_OUT))
end

local function step_in()
	return math.max(1, math.floor(mon_dim("width") * FACTOR_IN))
end

local submapNotify = 'omarchy-notification-send "Gaps Resize [ON]" "h/l: out  |  j/k: out  |  arrows: in  |  Esc: exit"'

-- ── gap helpers ───────────────────────────────────────────────────────────────

-- Normalize gaps_out to a table with top/right/bottom/left keys.
-- Hyprland stores uniform gaps as a single number and asymmetric gaps as a table.
local function norm(val)
	if type(val) == "number" then
		return { top = val, right = val, bottom = val, left = val }
	end
	if type(val) ~= "table" then
		return { top = 0, right = 0, bottom = 0, left = 0 }
	end
	return {
		top = tonumber(val.top) or 0,
		right = tonumber(val.right) or 0,
		bottom = tonumber(val.bottom) or 0,
		left = tonumber(val.left) or 0,
	}
end

-- Pack back to a single number if all sides equal, otherwise a table.
local function pack(g)
	if g.top == g.right and g.right == g.bottom and g.bottom == g.left then
		return g.top
	end
	return { top = g.top, right = g.right, bottom = g.bottom, left = g.left }
end

-- Clamp to zero (negative gaps are nonsensical).
local function clamp(v)
	return math.max(0, v)
end

-- ── submap definition ─────────────────────────────────────────────────────────

hl.define_submap("gaps-resize", function()
	hl.bind("l", function()
		local s = step_out("width")
		local g = norm(hl.get_config("general.gaps_out"))
		g.left = clamp(g.left + s)
		g.right = clamp(g.right + s)
		hl.config({ general = { gaps_out = pack(g) } })
	end, { repeating = true })

	hl.bind("h", function()
		local s = step_out("width")
		local g = norm(hl.get_config("general.gaps_out"))
		g.left = clamp(g.left - s)
		g.right = clamp(g.right - s)
		hl.config({ general = { gaps_out = pack(g) } })
	end, { repeating = true })

	hl.bind("k", function()
		local s = step_out("height")
		local g = norm(hl.get_config("general.gaps_out"))
		g.top = clamp(g.top + s)
		g.bottom = clamp(g.bottom + s)
		hl.config({ general = { gaps_out = pack(g) } })
	end, { repeating = true })

	hl.bind("j", function()
		local s = step_out("height")
		local g = norm(hl.get_config("general.gaps_out"))
		g.top = clamp(g.top - s)
		g.bottom = clamp(g.bottom - s)
		hl.config({ general = { gaps_out = pack(g) } })
	end, { repeating = true })

	-- Arrow keys → uniform gaps_in (all sides equally, 0.1% step)
	hl.bind("Right", function()
		local s = step_in()
		local g = norm(hl.get_config("general.gaps_in"))
		g.left = clamp(g.left + s)
		g.right = clamp(g.right + s)
		g.top = clamp(g.top + s)
		g.bottom = clamp(g.bottom + s)
		hl.config({ general = { gaps_in = pack(g) } })
	end, { repeating = true })

	hl.bind("Up", function()
		local s = step_in()
		local g = norm(hl.get_config("general.gaps_in"))
		g.left = clamp(g.left + s)
		g.right = clamp(g.right + s)
		g.top = clamp(g.top + s)
		g.bottom = clamp(g.bottom + s)
		hl.config({ general = { gaps_in = pack(g) } })
	end, { repeating = true })

	hl.bind("Left", function()
		local s = step_in()
		local g = norm(hl.get_config("general.gaps_in"))
		g.left = clamp(g.left - s)
		g.right = clamp(g.right - s)
		g.top = clamp(g.top - s)
		g.bottom = clamp(g.bottom - s)
		hl.config({ general = { gaps_in = pack(g) } })
	end, { repeating = true })

	hl.bind("Down", function()
		local s = step_in()
		local g = norm(hl.get_config("general.gaps_in"))
		g.left = clamp(g.left - s)
		g.right = clamp(g.right - s)
		g.top = clamp(g.top - s)
		g.bottom = clamp(g.bottom - s)
		hl.config({ general = { gaps_in = pack(g) } })
	end, { repeating = true })

	hl.bind("Escape", function()
		hl.dispatch(hl.dsp.submap("reset"), { description = "Exit Gaps Resize", submap = "gaps-resize" })
	end)
end)

-- ── entry binding ─────────────────────────────────────────────────────────────

hl.unbind("SUPER + CTRL + G")
hl.unbind("SUPER + CTRL + " .. "code:42") -- g keycode
--
hl.bind("SUPER + CTRL + G", function()
	hl.dispatch(hl.dsp.submap("gaps-resize"), { description = "Submap: Desktop Resizing" })
	hl.dispatch(hl.dsp.exec_cmd(submapNotify))
end)
