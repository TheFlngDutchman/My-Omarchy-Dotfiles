-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and supported resolutions with: hyprctl monitors all

local omarchy_gdk_scale = 1
local omarchy_monitor_scale = 1

hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))
hl.monitor({ output = "DP-1", mode = "2560x1440@74.78", position = "0x0", scale = omarchy_monitor_scale })
hl.monitor({ output = "HDMI-A-1", mode = "1920x1080@75", position = "2560x180", scale = omarchy_monitor_scale })

-- DP-1 is the main display: odd workspaces live there, even ones on HDMI-A-1.
for workspace = 1, 10 do
	local monitor = (workspace % 2 == 1) and "DP-1" or "HDMI-A-1"
	hl.workspace_rule({
		workspace = tostring(workspace),
		monitor = monitor,
		default = (workspace <= 2),
	})
end

-- Configure a specific monitor.
-- hl.monitor({ output = "DP-2", mode = "2560x1440@144", position = "0x0", scale = 1 })

-- Portrait/rotated secondary monitor (transform: 1 = 90°, 3 = 270°).
-- hl.monitor({ output = "DP-2", mode = "preferred", position = "auto", scale = 1, transform = 1 })
