-- Dedicated unbindings for built-in Omarchy 4.5 shortcuts.
-- Loaded by hypr/hyprland.lua directly after default.hypr.omarchy,
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

-- ── Displaced Tiling, Layout, Resize & Scaling Bindings (default/hypr/bindings/tiling.lua) ──
for _, chord in ipairs({
  "SUPER + P",                        -- Pseudo window (relocated to SUPER + SHIFT + CTRL + ALT + P; rebound to special:p btop)
  "SUPER + T",                        -- Toggle window floating/tiling (relocated to SUPER + SHIFT + CTRL + ALT + F; rebound to special:t terminal)
  "SUPER + Q",                        -- Close window (rebound to special:q)
  "SUPER + O",                        -- Pop window out (rebound to special:o Obsidian)
  "SUPER + J",                        -- Toggle window split (rebound to Move focus down)
  "SUPER + L",                        -- Cycle workspace layout (relocated to SUPER + ALT + Backspace; rebound to Move focus right)
  "SUPER + ALT + L",                  -- Cycle workspace layout back (retired in favor of one-way cycling)
  "SUPER + S",                        -- Toggle scratchpad (used by master layout swapwithmaster)
  "SUPER + ALT + S",                  -- Move window to scratchpad (retired)
  "SUPER + F",                        -- Full screen (rebound to Maximize active window)
  "SUPER + CTRL + F",                 -- Tiled full screen (rebound to In-client fullscreen)
  "SUPER + ALT + F",                  -- Full width (rebound to Typical fullscreen)
  "SUPER + code:20",                  -- Expand window left (Minus)
  "SUPER + SHIFT + code:20",          -- Shrink window up (Minus)
  "SUPER + ALT + code:20",            -- Expand window left a little (Minus)
  "SUPER + SHIFT + ALT + code:20",    -- Shrink window up a little (Minus)
  "SUPER + CTRL + code:20",           -- Expand window left a lot (Minus)
  "SUPER + CTRL + SHIFT + code:20",   -- Shrink window up a lot (Minus)
  "SUPER + code:21",                  -- Shrink window left (Equal; rebound to Proton Calendar)
  "SUPER + SHIFT + code:21",          -- Expand window down (Equal; rebound to Monitor scaling up)
  "SUPER + ALT + code:21",            -- Shrink window left a little (Equal; rebound to Monitor scaling down)
  "SUPER + SHIFT + ALT + code:21",    -- Expand window down a little (Equal)
  "SUPER + CTRL + code:21",           -- Shrink window left a lot (Equal)
  "SUPER + CTRL + SHIFT + code:21",   -- Expand window down a lot (Equal)
  "SUPER + SLASH",                    -- Monitor scaling up (relocated to SUPER + SHIFT + equal; rebound to special:slash Vesktop)
  "SUPER + ALT + SLASH",              -- Monitor scaling down (relocated to SUPER + ALT + equal)
}) do
  hl.unbind(chord)
end

-- ── Displaced Clipboard, Input Method & Utility Bindings ─────────────────────
for _, chord in ipairs({
  "SUPER + A",               -- Select all (clipboard.lua; rebound to special:a)
  "SUPER + SHIFT + CTRL + A",-- Agent picker (utilities.lua; rebound to Move to special:a)
  "SUPER + I",               -- Switch input language (input-method.lua; rebound to special:i Thesaurus)
  "SUPER + comma",           -- Dismiss/invoke/focus last notification (utilities.lua; rebound to special:comma Signal)
  "SUPER + K",               -- Show key bindings (relocated to SUPER + SHIFT + CTRL + ALT + K; rebound to Move focus up)
  "SUPER + CTRL + H",        -- Hardware menu (rebound to Resize window left)
  "SUPER + CTRL + K",        -- Show Herdr key bindings (rebound to Resize window up)
  "SUPER + CTRL + L",        -- Lock system (rebound to Resize window right)
  "SUPER + SHIFT + F",       -- File manager (relocated to SUPER + SHIFT + E; rebound to Window fullscreen)
  "SUPER + ALT + SHIFT + F", -- File manager cwd (relocated to SUPER + SHIFT + ALT + E)
  "SUPER + SHIFT + N",       -- Editor (used by master layout rollnext)
  "SUPER + SHIFT + O",       -- Obsidian (applications.lua; rebound to open new Obsidian window)
  "SUPER + SHIFT + SLASH",   -- Passwords / 1Password (applications.lua; retired)
  "SUPER + SHIFT + T",       -- Activity / btop (utilities.lua; rebound to new terminal window)
}) do
  hl.unbind(chord)
end
