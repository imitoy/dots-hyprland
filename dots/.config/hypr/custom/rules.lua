-- Custom window / workspace / layer rules
-- https://wiki.hyprland.org/Configuring/Window-Rules/
-- https://wiki.hyprland.org/Configuring/Workspace-Rules/

-- Global: disable blur for all windows (performance)
hl.window_rule({ match = { class = ".*" }, no_blur = true })

-- Steam: immediate (tearing) for all steam windows
hl.window_rule({ match = { class = "^steam" }, immediate = true })

-- Firefox extension
hl.window_rule({ match = { class = "firefox", title = "扩展*" }, float = true})

-- QQ: 图片查看器 - float + center
hl.window_rule({ match = { class = "QQ", title = "图片查看器" }, float = true })
hl.window_rule({ match = { class = "QQ", title = "图片查看器" }, center = true })

-- QQ: 聊天记录 - float + center
hl.window_rule({ match = { class = "QQ", title = ".*的聊天记录" }, float = true })
hl.window_rule({ match = { class = "QQ", title = ".*的聊天记录" }, center = true })

-- QQ: Other non-Q-titled windows - float + center
hl.window_rule({ match = { class = "QQ", title = "^[^Q]" }, float = true })
hl.window_rule({ match = { class = "QQ", title = "^[^Q]" }, center = true })

-- WeChat: 预览 - float + center
hl.window_rule({ match = { class = "wechat", title = "预览" }, float = true })
hl.window_rule({ match = { class = "wechat", title = "预览" }, center = true })

-- WeChat: 图片编辑 - float + center
hl.window_rule({ match = { class = "wechat", title = "图片编辑" }, float = true })
hl.window_rule({ match = { class = "wechat", title = "图片编辑" }, center = true })

-- RedPanda IDE console - float + position + size
hl.window_rule({ match = { class = "RedPandaConsole" }, float = true })
hl.window_rule({ match = { class = "RedPandaConsole" }, move = { "0", "60%" } })
hl.window_rule({ match = { class = "RedPandaConsole" }, size = { "40%", "40%" } })

-- Steam Overfield game
hl.window_rule({ match = { class = "steam_app_3879660" }, float = true, render_unfocused = false})

-- hl.window_rule({ match = { class = "steam_app_3866615458" }, size = {"(monitor_w*1.0)", "(monitor_h*1.0)"}})

-- hl.window_rule({ match = { title = "" }, move = {"monitor_w * 1.1", "monitor_h * 1.1"} })

-- Steam Blue Archive
hl.window_rule({ match = { class = "steam_app_3557620" }, render_unfocused = true})

-- Steam Cities: Skylines
hl.window_rule({ match = { class = "Cities.x64" }, render_unfocused = true})

-- Splash
hl.window_rule({
  name = "hypr-splash-win",
  match = { title = "^(hypr-splash)$" },
  float = true,                                  -- 不加会被当成普通窗口平铺掉
  size = { "monitor_w", "monitor_h" },           -- 铺满
  move = { 0, 0 },
  no_anim = true,                                -- 窗口本身不要开窗动画，动画由容器做
  no_initial_focus = true,                       -- 打开时不抢焦点
  no_focus = true,                               -- 永久不抢焦点
  decorate = false,
  no_shadow = true,
  no_blur = true,
})
