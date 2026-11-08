-- Master-layout-specific keybindings.
-- Loaded conditionally by hypr/layout-specific-bindings.lua only while the
-- active workspace is using the "master" layout.

return {
  enable = function()
    o.rebind("SUPER + S", "Swap focused window with master", hl.dsp.layout("swapwithmaster"))
    o.rebind("SUPER + SHIFT + S", "Cycle master orientation", hl.dsp.layout("orientationnext"))
    o.rebind("SUPER + N", "Roll to previous window (master)", hl.dsp.layout("rollprev"))
    o.rebind("SUPER + SHIFT + N", "Roll to next window (master)", hl.dsp.layout("rollnext"))
  end,

  disable = function()
    hl.unbind("SUPER + S")
    hl.unbind("SUPER + SHIFT + S")
    hl.unbind("SUPER + N")
    hl.unbind("SUPER + SHIFT + N")
  end,
}
