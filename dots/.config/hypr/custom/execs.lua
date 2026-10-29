-- Auto-start applications
-- https://wiki.hyprland.org/Configuring/Keywords/#executing

hl.on("hyprland.start", function()
	-- hl.exec_cmd("hyprlock") -- uncomment to enable at startup
	hl.exec_cmd("xrdb -merge ~/.Xresources")
	-- hl.exec_cmd("GDK_BACKEND=x11 WEBKIT_DISABLE_COMPOSITING_MODE=1 WEBKIT_DISABLE_DMABUF=1 clash-verge")
	-- hl.exec_cmd("clash-verge")
	hl.exec_cmd("fcitx5")
	hl.exec_cmd("hyprcrl setcursor Adwaita 24")
    hl.exec_cmd("sleep 1.5 && /usr/lib/xdg-desktop-portal -r")

    hl.exec_cmd("sleep 1.5 && xrdb -load ~/.config/X11/xresources")

    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd("/home/imitoy/.local/bin/hypr-click-ripple")
    hl.exec_cmd("sudo /usr/bin/auditctl -w /home/imitoy -p wa -k dotfile_watch")
    hl.exec_cmd("xembedsniproxy")
end)
