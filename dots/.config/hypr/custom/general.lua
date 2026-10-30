-- Monitors
-- https://wiki.hyprland.org/Configuring/Monitors/

hl.monitor({
	output = "eDP-1",
	mode = "2560x1600@240.00Hz",
	position = "auto",
	scale = 2,
})

hl.monitor({
	output = "eDP-2",
	mode = "2560x1600@240.00Hz",
	position = "auto",
	scale = 2,
})

--[[
hl.monitor({
    output = "HEADLESS-1",
    mode = "2424x1080@120Hz",
    position = "auto",
    scale = 2,
})]]

hl.monitor({
output = "",
	mode = "preferred",
	position = "auto",
 	scale = 1,
	mirror = "eDP-1",
})

-- General / XWayland / Cursor settings
hl.config({
	xwayland = {
		force_zero_scaling = true,
	},
	general = {
		border_size = 1,
		col = {
			active_border = "rgb(8EA8EF)",
		},
		allow_tearing = true,
	},
	cursor = {
		inactive_timeout = 5,
	},
})
