-- Dedicated unbindings for built-in Omarchy 4.5 shortcuts.
-- Loaded first by hypr/bindings.lua directly after default.hypr.omarchy,
-- before personal overlay bindings and conditional layout-specific bindings.

-- ── Preinstalled Web App Bindings (default/hypr/bindings/applications.lua) ──
for _, chord in ipairs({
  "SUPER + SHIFT + A",        -- ChatGPT
  "SUPER + SHIFT + ALT + A",  -- Grok
  "SUPER + SHIFT + C",        -- HEY Calendar
  "SUPER + SHIFT + E",        -- HEY Email (rebound to File manager)
  "SUPER + SHIFT + ALT + E",  -- New Email (rebound to File manager cwd)
  "SUPER + SHIFT + Y",        -- YouTube
  "SUPER + SHIFT + ALT + G",  -- WhatsApp
  "SUPER + SHIFT + CTRL + G", -- Google Messages
  "SUPER + SHIFT + P",        -- Google Photos
  "SUPER + SHIFT + S",        -- Google Maps (used by master layout orientation)
  "SUPER + SHIFT + X",        -- X
  "SUPER + SHIFT + ALT + X",  -- X Post
}) do
  hl.unbind(chord)
end

-- ── Displaced Tiling, Layout & Scratchpad Bindings (default/hypr/bindings/tiling.lua) ──
for _, chord in ipairs({
  "SUPER + J",       -- Toggle window split (rebound to Move focus down)
  "SUPER + L",       -- Cycle workspace layout (relocated to SUPER + ALT + Backspace; rebound to Move focus right)
  "SUPER + ALT + L", -- Cycle workspace layout back (retired in favor of one-way cycling)
  "SUPER + S",       -- Toggle scratchpad (used by master layout swapwithmaster)
  "SUPER + ALT + S", -- Move window to scratchpad (retired)
  "SUPER + F",       -- Full screen (rebound to Maximize active window)
  "SUPER + CTRL + F",-- Tiled full screen (rebound to In-client fullscreen)
  "SUPER + ALT + F", -- Full width (rebound to Typical fullscreen)
}) do
  hl.unbind(chord)
end

-- ── Displaced Utility & Application Bindings (utilities.lua / applications.lua) ──
for _, chord in ipairs({
  "SUPER + K",               -- Show key bindings (relocated to SUPER + SHIFT + CTRL + ALT + K; rebound to Move focus up)
  "SUPER + CTRL + H",        -- Hardware menu (rebound to Resize window left)
  "SUPER + CTRL + K",        -- Show Herdr key bindings (rebound to Resize window up)
  "SUPER + CTRL + L",        -- Lock system (rebound to Resize window right)
  "SUPER + SHIFT + F",       -- File manager (relocated to SUPER + SHIFT + E; rebound to Window fullscreen)
  "SUPER + ALT + SHIFT + F", -- File manager cwd (relocated to SUPER + SHIFT + ALT + E)
  "SUPER + SHIFT + N",       -- Editor (used by master layout rollnext)
}) do
  hl.unbind(chord)
end
