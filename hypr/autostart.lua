hl.on("hyprland.start", function()
  hl.exec_cmd("sh -lc 'sleep 1; pkill -x fcitx5 || true'")
end)
