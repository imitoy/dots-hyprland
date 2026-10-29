# hypr-splash

Hyprland 上的 Android 风格应用启动动画：**图标在屏幕中心亮起 → 遮罩淡出 → 窗口接管**。

已经原生集成进 ii（dots-hyprland），点启动器/dock/开始菜单里的应用就会播一遍。

```
dots/.config/quickshell/ii/
├── HyprSplashOverlay.qml       遮罩层（动画全在这里），挂在 shell.qml 的 ShellRoot 下一个
├── services/HyprSplash.qml     对外接口：HyprSplash.launch(entry)
├── scripts/hyprSplash/
│   ├── splash                  编排脚本：注入窗口规则 → 让 overlay 入场 → 启动应用
│   │                           → 等窗口 map → 通知 overlay 淡出
│   └── README.md               本文件
└── modules/common/Config.qml   Config.options.hyprSplash.{enable,timeout,workspaceLock}
```

```
用户点击应用
      │
      ├─ HyprSplash.launch(entry)          ← 所有启动入口都换成这一句
      │     ├─ 开关关掉 / 动画不可用 / runInTerminal  →  entry.execute()   （原有行为）
      │     └─ 否则 → python3 scripts/hyprSplash/splash run \
      │                --qs-dir <ii 目录> --exec-json <entry.command> ...
      │
      └─ 脚本：hyprctl eval 注入规则 → qs -p <ii> ipc call splash begin …
              → Popen(entry.command) → 监听 .socket2.sock 等窗口
              → ipc call splash handoff …   → 窗口接管
```

---

## 0. 为什么 splash 是一个窗口，而不是 layer-shell overlay

一句话：**layer-shell 是 per-output 的全局表面，窗口是 per-workspace 的。**

| | overlay 层（旧做法） | 普通窗口（现在） |
|---|---|---|
| 切到别的 workspace | **照样盖在那里** | 跟着原 workspace 一起消失 |
| 切回来时 | 一直在 | 还在（或已交接完） |
| 能否盖住 bar | 能 | 默认不能（见下） |
| 出现在 `hyprctl clients` | 否 | 是 |

这个差别正好对上你要的用法：**启动一个慢应用 → 先切走干别的 → 它开好了再切回来**。

- 你在 workspace 1 点了应用，splash 出现在 workspace 1；
- 你切到 workspace 2 —— splash 跟着 workspace 1 一起隐了，不挡你；
- 应用在后台开好，交接动画在后台跑完；
- 你切回 workspace 1，看到的是已经就绪的应用。

如果切回来时应用**还没开好**也完全没问题：splash 还在原位等着（呼吸动画照常），就绪那一刻再交接。

> **不要给这个窗口加 `pin`。** Hyprland 里 pin 的语义是「显示在所有工作区」——一旦加上，切到别的
> workspace 它照样盖着，等于退回了 overlay 的全局行为，正好是要摆脱的东西。

### 新窗口开在哪个工作区（`workspaceLock`，默认开）

Hyprland 默认把新窗口开在**当前聚焦**的工作区。所以你点了应用之后一走了之，窗口会开在
你切到的地方，而不是 splash 待着的地方 —— 两边就分家了。

脚本注入一条窗口规则，把新窗口钉回 splash 所在的工作区：

```lua
hl.window_rule({
  name      = "hypr-splash-ws-0",
  match     = { class = "^(steam)$" },
  workspace = "2 silent",   -- silent：窗口开过去，但不把当前的视图也拽走
})
```

这条规则是**临时**的：`hl.window_rule()` 返回句柄，脚本把它们存进 `_G.__hypr_splash_ws`，
交接一完成就逐个 `set_enabled(false)` 关掉；超时和启动失败的分支同样会清。下一轮开始时
还会先关掉上一轮遗留的，避免规则越积越多。

不想要这个行为：`Config.options.hyprSplash.workspaceLock = false`（或命令行 `--no-workspace-lock`）。

#### 但 class 猜不对 —— 所以做了三层保险

**根因：窗口 class 是应用自己设在 surface 上的，外部改不了。**
Hyprland 没有「改写 class」的窗口规则（`initialclass` 只是**匹配条件**），所以没法"给应用
挂个自定义 class"。只能猜到它，而同类应用有四种常见写法：

| 写法 | 例子 |
|---|---|
| app id | `com.tencent.wemeet` ← flatpak 的 Wayland 应用常用这个 |
| app id 末段 | `steam`、`Spotify` |
| 末段的小写 | `steam`（大小写不定） |
| 命令名 | `firefox`、`kitty` |

**实测教训**：Flatpak Steam 的真实 class 是 `steam`，而它的 app id 是
`com.valvesoftware.Steam` —— 只按 app id 猜必然落空，规则**静默失效**（不报错，就是不起作用）。
判断依据就在 `~/.config/hypr/custom/rules.lua` 里：`match = { class = "^steam" }`。

于是现在是三层：

1. **猜一族**（`class_candidates()`）：上面四种写法全部列上，一条候选注一条规则
   （规则之间是「或」的关系），命中哪条都算数。
2. **学会真值**（`~/.cache/hypr-splash/classes.json`）：每次实测到的 class 按应用记下来，
   下次排在候选最前面。于是「第一次靠猜、之后都准」。这个文件可以随时删，删了就从猜开始。
3. **兜底纠正**（`move_to_workspace()`）：窗口一旦出现，我们就知道它的真实 class 和位置了。
   如果它落在别的工作区（说明规则没命中），立刻
   `hyprctl dispatch movetoworkspacesilent <splash 的工作区>,address:<窗口>` 把它挪回去。
   **这一步保证最终结果一定对**，代价是它会在错误的工作区上多存在几十毫秒（通常一两帧，
   基本看不见）—— 而且只有第一次跑会走到这里，第 2 层学会之后就不再需要它了。

### 关于 bar 和 workarea

Hyprland 会把用窗口规则 `move`/`size` 定位的浮窗**夹进 workarea**，即避开你的 bar。所以默认情况下
splash 覆盖的是 bar 以下的整块区域，**bar 保持可见可用**。

退场是整块遮罩淡出，不再把容器变形到某个矩形，所以 splash 窗口被夹到哪儿都不影响动画效果。
脚本仍会去 `hyprctl clients` 里问窗口自己的 `at`/`size` 并打印出来（`wait_splash()` / `window_rect()`），
排查「窗口被夹得对不对」时有用，但它已经**不参与**动画计算了。

想让 splash 连 bar 一起盖住，把规则里的 `size`/`move` 换成 `fullscreen = true` 试试——能否如愿取决于
你的 bar 配置和 Hyprland 的全屏语义，自己试一下最直接。

---

## 1. 怎么打开 / 关掉 / 调

### 开关

```jsonc
// ~/.config/illogical-impulse/config.json（或设置界面里改）
{
  "hyprSplash": {
    "enable": true,          // 总开关
    "timeout": 20,           // 等窗口出现的最长秒数
    "workspaceLock": true    // 新窗口固定开在 splash 所在的工作区
  }
}
```

`enable: false` 时 `HyprSplash.launch()` 直接调 `entry.execute()` —— 行为和加这个功能之前完全一样。

改完不用重启，ii 会热重载（`Super+Ctrl+R` 手动重载）。

### 哪些入口已经接上了

| 入口 | 文件 |
|---|---|
| ii 启动器 + ii 概览 + waffle 搜索结果 | `services/LauncherSearch.qml`（结果对象的 `execute` 闭包，一处改动三处生效） |
| ii dock 左键 / 中键 | `modules/ii/dock/DockAppButton.qml` |
| waffle 开始菜单：固定应用网格 | `modules/waffle/startMenu/startPage/BigAppGrid.qml` |
| waffle 开始菜单：分类列表 | `modules/waffle/startMenu/startPage/AppCategoryGrid.qml` |
| waffle 任务栏按钮（左键/中键/右键菜单） | `modules/waffle/bar/tasks/TaskAppButton.qml` |

没接的地方是**右键菜单里的次要动作**（`entry.actions`，比如「新建私人窗口」）和
`runInTerminal` 的条目 —— 前者保持原样，后者交给 ii 自己用终端跑（`HyprSplash.launch()`
内部会直接退回 `launchPlain()`）。

### 命令行

脚本可以单独跑（排查时最有用）：

```bash
cd ~/.config/quickshell/ii/scripts/hyprSplash

./splash demo --icon firefox          # 只演动画，不启动应用
./splash status                       # overlay 当前阶段
./splash stop                         # 取消正在播的动画

# 完整链路（和 ii 点图标做的事一模一样）
./splash run --entry-id firefox --exec-json '["firefox"]' --label Firefox --icon firefox
./splash run firefox                  # 也可以直接给 .desktop id，自己解析名字/图标
./splash run -- flatpak run com.valvesoftware.Steam   # 整条命令透传
```

> **`--entry-id` + `--exec-json` 是 ii 用的形式，也是推荐形式。**
> 命令由 Quickshell 给（`entry.command`），**保证和 ii 原本 `execute()` 跑的一字不差** ——
> Quickshell 的 `execute()` 本身就是 `execDetached({ command, workingDirectory })`。
> `--entry-id` 只用来查名字/图标/`StartupWMClass`，所以就算脚本对 `.desktop` 的解析有偏差，
> 也不可能启动错东西。

---

## 2. 参数速查

`run`：

| 参数 | 作用 |
|---|---|
| `--entry-id ID` | `.desktop` id，**只用来查名字/图标/`StartupWMClass`**，不当命令用 |
| `--exec-json JSON` | 要启动的命令，JSON 数组，如 `'["firefox","-new-tab"]'`。ii 集成传的就是它 |
| `--cwd DIR` | 工作目录。默认取 `.desktop` 的 `Path=`（有些应用靠相对路径找资源），没有则 `~` |
| `--class C` | 强制指定窗口 class。**一般不用给** —— 脚本会自己生成一族候选（app id / 末段 / 小写 / 命令名 / `StartupWMClass` / 上次学到的），并把每次实测到的真值记进 `~/.cache/hypr-splash/classes.json` |
| `--icon / --label / --color` | 覆盖图标、名称、容器底色 |
| `--timeout S` | 等窗口出现的最长秒数，默认 20；超时会取消动画 |
| `--workspace-lock` / `--no-workspace-lock` | 新窗口是否固定开在 **splash 所在的**那个工作区（默认开，见第 0 节） |
| `--splash` / `--no-splash` | 是否播动画（默认播）。`--no-splash` 就是纯启动器 |
| `--qs-dir DIR` / `--qs NAME` | 指定 ii 的 Quickshell 实例。默认自动探测：先 `-p <配置目录>`（QML 传的就是 `Quickshell.shellPath("")`），再 `qs -c ii` |
| `--debug` | 打印事件流与窗口匹配过程（排查用；等价于 `SPLASH_DEBUG=1`） |
| `-- 命令...` | `--` 之后整段当命令，跳过 `.desktop` 解析。Flatpak 走这条路 |

`app` 位置参数、`--exec-json`、`-- 命令` 三选一。都不给（`./splash run`）会直接报用法退出 ——
不会静默去读 stdin 挂住。

`demo`：`--hold 1.5`（图标停留秒数）。以前还有个 `--rect` 用来指定交接目标矩形，退场改成
普通淡出之后它没有意义了，已删。

**脚本不会碰应用窗口的动画。** 早先版本会注入 `no_anim = true` 把应用窗口压成瞬时出现，
代价是交接那一瞬变成硬切；现在窗口照常走合成器的 `windowsIn`，和 overlay 的淡出自然叠在一起。
想给某个应用换个味道，自己往 `custom/rules.lua` 写一条就行（不必由启动器代劳）：

```lua
hl.window_rule({ match = { class = "^steam$" }, animation = "popin 9%" })
```

### Flatpak

Flatpak 应用不能直接给名字（`steam` 不是命令），用 `--` 把整条命令透传：

```bash
./splash run -- flatpak run com.valvesoftware.Steam
./splash run -- flatpak run com.tencent.wemeet
./splash run -- flatpak run --command=wemeetapp --file-forwarding com.tencent.wemeet @@u @@
```

`--` 之后的整段会原样执行。脚本会自己从里面**反推**：

- **名字/图标**：从命令里挑出像 app id 的那一段，去 `~/.local/share/flatpak/exports/share/applications`
  和 `/var/lib/flatpak/exports/share/applications` 找同名 `.desktop`，拿到真正的 `Name`/`Icon`。
  找不到就在图标搜索路径（含 `/var/lib/flatpak/exports/share/icons`）里按 app id 猜。
- **窗口 class**：不赌一个，而是列一族候选（见第 0 节）。
- **标签兜底**：万一 `.desktop` 和图标都没找到，标签取 app id 的最后一段
  （`com.valvesoftware.Steam` → `Steam`），而不是难看且错误的 `flatpak`。

> **为什么不用 argparse 的 `REMAINDER`：** 它和 `app`（`nargs="?"`）放在一起时，`--` 后面第一个词会被
> `app` 抢走 —— `run -- flatpak run com.foo` 会变成 `app="flatpak"`、命令只剩 `run com.foo`，
> flatpak 本体直接丢了（报 `No such file or directory: 'run'`）。现在 `--` 由 `main()` 自己切，
> 是 `run` 子命令专有的行为，其它子命令里的裸 `--` 交回给 argparse。

### 建议把窗口规则固化

脚本每次播放前都会用 `hyprctl eval` 注入一条运行时规则（名字 `hypr-splash-win`），`hyprctl reload` 会清掉。
想一劳永逸，往 `~/.config/hypr/custom/rules.lua` 追加：

```lua
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
```

不加也能跑（脚本会自动注入）；加了的好处是**窗口第一次 map 就带属性**，不依赖注入时序。

规则靠窗口 `title` 匹配，因为 Quickshell 窗口的 class 是通用值、区分不出是哪一块。title 由
`HyprSplashOverlay.qml` 里的 `title: "hypr-splash"` 设置，改它就要同步改这条规则**和脚本里的
`SPLASH_TITLE`**。

---

## 3. 时间线

| 时刻 | 发生什么 |
|---|---|
| t=0 | 脚本注入 splash 窗口规则 → `ipc call splash begin` → 窗口 map（在**当前 workspace**） |
| t≈180ms | 图标在窗口中心淡入并放大到位（0.84 → 1.0，emphasizedDecel 同族曲线），下方显示应用名 |
| t≈1.6s | 图标开始 ±4% 呼吸（应用起得慢时的「还在加载」信号，Android 同款） |
| t=N | 事件 socket 收到 `openwindow` → 之后 0.4s 内按 20ms 一轮「急查」`clients`（事件早于窗口入列，见第 5 节） |
| t=N | 命中候选 class → 如果它落在别的工作区，先挪回 splash 那个（见第 0 节的第 3 层保险） |
| t=N | `ipc call splash handoff` → 整个遮罩（压暗层 + 图标 + 应用名）180ms 普通淡出 |
| t=N+200ms | 淡完 → 窗口 unmap，真实窗口自己播 `windowsIn`（popin） |
| 期间 | 你切到别的 workspace：splash 跟着原 workspace 隐掉，动画照常在后台跑完 |
| t>timeout | 超时 → `cancel`，同样是这个淡出 |

---

## 4. 调参

- **手感**：`HyprSplashOverlay.qml` 里 `iconSize`(132) / `iconGlyph`(72) / 入场曲线
  （`enterAnim` 的 `bezierCurve`）/ 退场时长（`fadeOut()` 里的 180ms）/ 呼吸节奏。
- **退场**：`fadeOut()` 就是全部 —— 整块遮罩透明度 1 → 0，`Easing.OutCubic`，不缩不放不变形。
  `handoff()` 收到的窗口矩形参数现在**只用于日志**，不再驱动动画。
- **配色**：容器底色默认取 ii 的 `Appearance.colors.colPrimary`（跟着 Material You 走）；
  脚本里的 `PALETTE` 是按应用名散列的备选，只有显式传 `--color` 或 QML 里改 `accent` 才用得上。
- **压暗程度**：`HyprSplashOverlay.qml` 里那个黑色 `Rectangle` 的 `opacity: 0.45`。
- **呼吸节奏**：`pulseStart` 的 `interval`(1600) 和 `pulseAnim` 的 `duration`(1000)。

改 QML 不用重启，ii 会热重载（改 `shell.qml` 的结构会整体重载一次）。

---

## 5. 窗口匹配不到怎么办

脚本等窗口的逻辑是：**监听 Hyprland 的 `.socket2.sock` 拿唤醒信号，然后每次都重新扫
`hyprctl clients`**。匹配条件是「地址不在启动前的快照里（= 新窗口）」且「class 命中候选里的任一个」。

> 早先的写法是拿事件里的地址去查单个窗口。但事件到达时窗口往往还没进 `clients` 列表，
> 那条事件就被永久丢弃了 —— 多窗口的应用（腾讯会议、Electron 系）特别容易踩。
>
> 第二个坑：事件到了、这一轮扫不到，而下一个事件永远不来 —— 于是白等满一个 select 超时。
> 现在收到事件后会在 0.4s 内按 20ms 一轮「急查」，把这段延迟压掉。

卡住时按这个顺序查：

```bash
./splash run --debug --entry-id firefox --exec-json '["firefox"]'   # 看事件流、候选 class、命中情况
hyprctl clients | grep -i "class:"     # 看实际 class 到底是什么
cat ~/.cache/hypr-splash/classes.json  # 看已经学会的 class（删掉即可重新开始猜）
qs -p ~/.config/quickshell/ii ipc show # ii 到底有没有把 splash 这个 IPC 目标挂上
```

- **超时后会列出「这期间实际出现过的新窗口」**，照着它写 `--class` 就行。
- **候选全没命中也不会白演**：期间只冒出一个新窗口时，脚本直接用它（并打印提示），
  同时把它的 class 记进缓存 —— 下次就准了。
- **`./splash stop`** 随时可以清掉还挂在屏幕上的动画。
- **`--no-splash`** 是排查用的开关：绝对不碰 overlay，只启动应用。

---

## 6. 降级与容错

**动画是锦上添花，任何一环出问题都必须退回「直接把应用启动起来」。** 这条是硬约束，两层都实现：

`HyprSplash.qml` 这一层：

| 情况 | 行为 |
|---|---|
| `enable = false` | `entry.execute()` |
| `runInTerminal = true` | `launchPlain()`（ii 原本的做法：用终端跑） |
| `entry.command` 为空 | `entry.execute()` |
| python3 或脚本文件不在（启动时探测一次） | `entry.execute()`，之后的启动都不再试 |

脚本这一层（`cmd_run()`）：

| 情况 | 行为 |
|---|---|
| 找不到 `hyprctl` / 连不上 Hyprland / 没有 `qs` | 跳过动画，直接启动 |
| ii 没在跑（`ipc show` 里没有 `splash`） | 跳过动画，直接启动 |
| `ipc call splash begin` 失败 | 跳过动画，直接启动 |
| 动画流程里任何异常 | 跳过动画，直接启动 |
| 等不到窗口（超时） | 动画取消，但**应用已经启动过了，不会再启动第二次** |

最后一条靠 `state["spawned"]`：它在 `Popen` 成功之后才置位，之后无论怎么失败都不清 ——
所以「降级」永远不会变成「启动两次」。

> 唯一的外部依赖是 **python3**（脚本只用标准库）。这在这个 dots 里本来就是硬依赖
> （颜色/缩略图脚本都是 Python），而且启动时会探测一次，缺了就永久退回原行为。

---

## 7. 已知边界

- **首帧灰屏**：Chromium / Electron 的第一帧常是纯灰。容器淡出和窗口显形之间如果看到一下闪灰，
  属于这套方案的已知短板。
- **fork 后开窗的应用**：`hl.dsp.exec_cmd(cmd, rules)` 那条路是靠 PID 匹配的，Electron / Flatpak
  会失配 —— 所以本脚本改用「事件 socket 监听 + 按 class 匹配」，绕开了这个问题。
- **splash 会出现在 `hyprctl clients` 里**：这是窗口化的代价。好在 ii 的 dock 按 `.desktop` 条目分组，
  没有 `hypr-splash` 这个条目，所以不会在 dock 上冒出一个图标。别的读 client 列表的工具
  （alt-tab 之类）可能会看到它 —— 有 `no_focus`，它不会被选中。
- **规则靠 title 匹配**：改了 `HyprSplashOverlay.qml` 里的 `title`，要同步改 `custom/rules.lua`
  和脚本里的 `SPLASH_TITLE`，否则窗口会被平铺。
- **跨显示器**：窗口出现在非聚焦屏时，动画会在那块屏上重放一次（`targetMonitor` 变了）。
  够用，但不是无缝的。
- **多层窗口的应用**（Electron 会先开一个 splash 小窗）：脚本取的是**第一个**命中候选的窗口，
  可能抓到那个小窗。用 `--class` 指定精确 class 可以缩小范围。
- **窗口动画由合成器负责**：脚本不注入任何动画规则，应用窗口走你自己的 `windowsIn`
  （当前是 `popin 80%`，约 300ms）。遮罩在同一个瞬间开始 180ms 淡出，两者是交叉淡入淡出 ——
  这是刻意换回来的：先前用 `no_anim` 把窗口压成瞬时，代价是硬切。
  想彻底不叠，就在 `custom/rules.lua` 里给那个 class 加 `no_anim = true`（全局生效，自己承担）。
- **class 猜错会有一次闪现**：兜底移动（第 0 节第 3 层）会让窗口在错误的工作区上多存在几十毫秒。
  只发生在某个应用的第一次启动；学会之后不再走这条路。
- **`workspaceLock = false` 时不做兜底移动**：关掉就真的是「窗口开在你当下待的地方」。
- **不要改 `~/.config/quickshell/ii` 里的文件**：那个目录是 `setup install-files`
  用 `rsync -a --delete` 从仓库同步过来的（见 `sdata/subcmd-install/3.files-exp.yaml`），
  没提交的改动会在下次更新时被删掉。改仓库里的 `dots/.config/quickshell/ii/…`。

### 关于 `misc:initial_workspace_tracking`（没采用，但值得知道）

Hyprland 有个原生相关选项（官方变量表原文）：

> `initial_workspace_tracking` — if enabled, windows will open on the workspace they were
> invoked on. **0 - disabled, 1 - single-shot, 2 - persistent (all children too)**

`hyprland/general.lua` 里设的是 `false`（= 0，关闭）。**本脚本没有依赖它**，原因：

- 它按「进程是在哪个工作区被调起的」来追踪，而追踪记录是**合成器自己 spawn 时**建立的
  （`exec` 派发器那条路）。脚本用 `subprocess.Popen` 直接拉起应用，合成器没有这条记录。
- 就算改成用 `hl.dsp.exec_cmd` 拉起，Flatpak 的进程链也是断的 —— `flatpak run` 把启动请求
  交给 `flatpak-portal` / systemd user service，真正的应用进程不是它的子进程，而
  `= 2` 的 "all children too" 是沿进程树往上找的，找不到。

所以这条路对 Flatpak 不可靠，而现在这套（一族候选 + 学会真值 + 兜底移动）对原生应用和
Flatpak 一视同仁。**别为了这个去开它** —— 那是全局行为变更，会影响你所有应用的窗口落点。

---

## 8. 独立模式（不用 ii）

脚本**优先**找正在运行的 ii 实例（`-p <配置目录>` / `qs -c ii`）；如果它所在目录里放了一份
自己的 `shell.qml`，才允许把它当独立 Quickshell 实例拉起来。所以想让 hypr-splash 脱离 ii
单独用，把 `HyprSplashOverlay.qml` 和下面这个 `shell.qml` 放进同一个目录：

```qml
//@ pragma UseQApplication
import QtQuick
import Quickshell

ShellRoot {
    HyprSplashOverlay {}
}
```

然后 `./splash run ...` 就会自己 `qs -p <该目录>` 拉起实例（`ensure_shell()`）。
注意这个目录**不能是 ii 的目录** —— ii 的目录里也有 `shell.qml`，但那里 overlay 是 ii 的一部分，
再拉一个实例只会打架（所以显式 `--qs-dir` / `--qs` 指定的一律按「不拉起」处理）。

---

## 9. 自测

改完 `splash` 后不用真的启动应用就能验一遍（**都不需要 Hyprland**，纯离线）：

```bash
python3 _test_cli.py   # class 候选推断、实测学习、工作区兜底、-- 透传、--exec-json、降级路径
python3 _test_lua.py   # 把生成的窗口规则串丢进 lua5.5 跑一遍，确认语法/运行都合法
```

`_test_cli.py` 全程打桩（`hyprctl` / `qs` / `subprocess.Popen` / `require_shell` 都是假的，
缓存也写到临时目录），所以不会真的启动应用、也不会动你的 `~/.cache/hypr-splash/`。
重点覆盖第 6 节那几条降级路径 —— 尤其「动画阶段抛异常时应用只被启动一次」。

`_test_lua.py` 覆盖了正则元字符（`a+b*c?d`、`app$with^carets|and.pipes`）和中文 class —— 这类字符串
用 `re.escape()` 处理会产出 `\-` 这种 Lua 非法转义，是之前踩过的坑。它还会验证
「连注两轮 + clear」之后 `_G.__hypr_splash_ws` 里不留悬空句柄。

> 这两个文件是开发时的离线自测，不属于 ii 的运行时代码，放在这里方便改脚本时随手跑。
