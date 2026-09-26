-- Extra autostart processes.
-- o.launch_on_start("my-service")

-- Start focused on workspace 1. Which monitor that lands on comes from the
-- workspace rules in hypr/monitors.lua, so changing displays only means
-- reassigning workspaces there -- nothing to update here.
hl.on("hyprland.start", function()
  hl.dispatch(hl.dsp.focus({ workspace = "1" }))
end)


