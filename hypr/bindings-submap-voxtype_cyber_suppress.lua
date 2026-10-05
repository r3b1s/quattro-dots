-- Voxtype Suppress (cyber) Submap
--
-- The keyboard-suppression layer used while dictation output is being typed.
-- Same job as voxtype_suppress, but its exits return to the cyber submap
-- instead of resetting to the default layer: dictation started from cyber
-- must land back in cyber.
--
-- Why it cannot simply reuse voxtype_suppress: a submap is one named layer,
-- and leaving it via hl.dsp.submap("reset") always drops to the default submap.
-- Hyprland has no "return to wherever I came from" transition, and voxtype's
-- post_output_command fires long after the originating keypress, so the return
-- target cannot be inferred from the key that started it. Hence a dedicated
-- layer, entered only from cyber (see voxtype-suppress-start), whose exits are
-- hardcoded to cyber.
--
-- The modifier binds swallow bare modifier presses so keys the transcriber is
-- about to type cannot re-trigger shortcuts mid-dictation. They are marked
-- transparent + ignore_mods, matching the base-layer layer.

hl.define_submap("voxtype_cyber_suppress", function()
  local function back_to_cyber(description)
    return function()
      hl.dispatch(hl.dsp.submap("cyber"), { description = description })
      hl.dispatch(hl.dsp.exec_cmd('omarchy-notification-send "Dictation: KB re-enabled" "Back in cyber submap"'))
    end
  end

  -- Delete mirrors the base layer's exit key; the SUPER + CTRL + ALT + C chord
  -- is cyber's own exit, bound here too so reaching for it is never a dead end.
  hl.bind("Delete", back_to_cyber("End voxtype suppression (cyber)"), { description = "End Voxtype Suppression (cyber)" })
  hl.bind("SUPER + CTRL + ALT + C", back_to_cyber("End Cyber submap"), { description = "End Cyber submap" })

  for _, mod in ipairs({ "Super_L", "Super_R", "Alt_L", "Alt_R", "Control_L", "Control_R" }) do
    hl.bind(mod, hl.dsp.exec_cmd("exec true"), { transparent = true, ignore_mods = true })
  end
end)