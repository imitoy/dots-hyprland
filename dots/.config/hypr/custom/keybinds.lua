-- Custom keybindings
-- https://wiki.hyprland.org/Configuring/Binds/

require("custom.variables")

-- Edit config files
hl.bind("CTRL + SUPER + Slash", hl.dsp.exec_cmd(
	"xdg-open ~/.config/illogical-impulse/config.json"
), { description = "Edit shell config" })

hl.bind("CTRL + SUPER + ALT + Slash", hl.dsp.exec_cmd(
	"xdg-open ~/.config/hypr/custom/keybinds.lua"
), { description = "Edit extra keybinds" })

-- Workspace previous
hl.bind("SUPER + Tab", hl.dsp.focus({ workspace = "previous" }))

-- Drag threshold
hl.config({
	binds = {
		drag_threshold = 10,
	},
})

-- Mouse click feedback (non-consuming + ignore mods)
hl.bind("mouse:272", hl.dsp.exec_cmd(
	"bash ~/.local/bin/click-feedback.bash"
), { non_consuming = true, ignore_mods = true })

-- Keyboard sound feedback (non-consuming + ignore mods + repeating)
local sound_dir = os.getenv("HOME").."/.local/share/sounds"
local feedback_cmd = "bash ~/.local/bin/keyboard-feedback.bash"

-- Alphanumeric keys (codes 1-129, with gaps for non-alphanumerics)
local keys_with_standard_sound = {
	1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21,
	23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 37, 38, 39, 40,
	41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57,
	58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74,
	75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91,
	92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106,
	107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120,
	121, 122, 123, 124, 125, 126, 127, 128, 129, 174,
}

for _, code in ipairs(keys_with_standard_sound) do
	hl.bind("code:" .. code, hl.dsp.exec_cmd(
		feedback_cmd .. " \"" .. sound_dir .. "/KeypressStandard.ogg\""
	), { non_consuming = true, ignore_mods = true, repeating = true })
end

-- Space
hl.bind("space", hl.dsp.exec_cmd(
	feedback_cmd .. " \"" .. sound_dir .. "/KeypressSpacebar.ogg\""
), { non_consuming = true, ignore_mods = true, repeating = true })

-- Return/Enter
hl.bind("Return", hl.dsp.exec_cmd(
	feedback_cmd .. " \"" .. sound_dir .. "/KeypressReturn.ogg\""
), { non_consuming = true, ignore_mods = true, repeating = true })

hl.bind("KP_Enter", hl.dsp.exec_cmd(
	feedback_cmd .. " \"" .. sound_dir .. "/KeypressStandard.ogg\""
), { non_consuming = true, ignore_mods = true, repeating = true })

-- Backspace
hl.bind("BackSpace", hl.dsp.exec_cmd(
	feedback_cmd .. " \"" .. sound_dir .. "/KeypressDelete.ogg\""
), { non_consuming = true, ignore_mods = true, repeating = true })

-- Super key
hl.bind("Super_L", hl.dsp.exec_cmd(
	feedback_cmd .. " \"" .. sound_dir .. "/KeypressStandard.ogg\""
), { non_consuming = true, ignore_mods = true })

-- Chrome bindings (commented out)
-- hl.bind("CTRL + Q", hl.dsp.send_shortcut("CTRL", "W", "google-chrome"))
-- hl.bind("CTRL + W", hl.dsp.send_shortcut("CTRL", "T", "google-chrome"))
