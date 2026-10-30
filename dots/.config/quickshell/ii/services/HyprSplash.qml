pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * hypr-splash —— 应用启动动画（Android 风格）的对外接口。
 *
 *     icon  →  图标在屏幕中心亮起  →  容器变形到目标窗口几何  →  窗口接管
 *
 * 用法：把原来 `entry.execute()` 的地方换成 `HyprSplash.launch(entry)` 即可。
 * 遮罩层是 `HyprSplashOverlay.qml`（挂在 shell.qml 的 ShellRoot 下），
 * 编排脚本在 `scripts/hyprSplash/splash`（Python，只用标准库）。
 *
 * 两条设计原则：
 *
 * 1. **启动命令完全由 Quickshell 决定。** 我们把 `entry.command` /
 *    `entry.workingDirectory` 原样交给脚本，于是「启动什么」和原来的
 *    `execute()` 一字不差 —— Quickshell 的 `execute()` 本身就是
 *    `execDetached({ command, workingDirectory })`。脚本只负责外面那层动画，
 *    自己对 .desktop 的解析仅用于取名字/图标/窗口 class。这样就算解析有偏差，
 *    也不可能启动错东西。
 *
 * 2. **降级优先。** 动画只是锦上添花，任何一环不可用都必须退回直接启动：
 *    开关关掉、python3 缺席、脚本文件不在、`runInTerminal` 的条目，统统走
 *    `launchPlain()`（= 原来的行为）。脚本内部同样遵守这条（见其文件头注释）。
 *
 * 开关与参数见 Config.options.hyprSplash。
 */
Singleton {
    id: root

    // ── 配置 ──────────────────────────────────────────────────────────────
    readonly property bool optEnabled: Config.options?.hyprSplash?.enable ?? false
    readonly property int optTimeout: Config.options?.hyprSplash?.timeout ?? 20
    readonly property bool optWorkspaceLock: Config.options?.hyprSplash?.workspaceLock ?? true

    // ── 路径 ──────────────────────────────────────────────────────────────
    readonly property string scriptPath: Quickshell.shellPath("scripts/hyprSplash/splash")
    // 跟自己的实例说话：ii 也是这么调自己的（见 ScreenSnipToggle.qml 的 region 调用）
    readonly property string shellDir: Quickshell.shellPath("")

    // ── 可用性 ────────────────────────────────────────────────────────────
    // 乐观默认为 true：首次启动不该被探测过程拖掉一拍（探测要几十毫秒）。
    // 真探测到缺东西时才翻成 false，之后的启动就自动退回直接启动。
    property bool launcherReady: true

    Process {
        id: probe
        running: true
        command: ["sh", "-c", 'command -v python3 >/dev/null 2>&1 && [ -r "$1" ]', "sh", root.scriptPath]
        onExited: (exitCode, _exitStatus) => root.launcherReady = (exitCode === 0)
    }

    /** 播放启动动画并启动应用。任何一环不可用就退回直接启动。 */
    function launch(entry) {
        if (!entry)
            return;
        if (!root.optEnabled || !root.launcherReady || entry.runInTerminal) {
            root.launchPlain(entry);
            return;
        }
        const cmd = root.normalizeCommand(entry.command);
        if (cmd.length === 0) { // 拿不到可执行命令就别硬来
            root.launchPlain(entry);
            return;
        }
        Quickshell.execDetached(root.scriptArgs(cmd, entry));
    }

    /**
     * `entry.command`（`list<string>`）→ 真正的 JS 字符串数组。
     *
     * **这一步是必需的，不是洁癖**：`--exec-json` 传的是 `JSON.stringify(cmd)`，
     * 而 `JSON.stringify` 作用在"类数组对象"上会得到 `{}` —— 那样脚本会认为命令
     * 非法而放弃启动，且**它手上没有别的命令可以启动**，应用就起不来了。
     * 所以这里保证「要么是一个正常的非空数组，要么返回空数组让调用方走 launchPlain」。
     *
     * （名字别改回 `argv`：实测过，叫 `argv` 时从外部 `typeof HyprSplash.argv` 是
     *  `undefined`，函数根本调不到 —— 应该是和基类上的某个东西撞名了。）
     */
    function normalizeCommand(command) {
        if (!command)
            return [];
        if (Array.isArray(command))
            return command.map(String);
        try {
            return Array.from(command).map(String);
        } catch (e) {
            return [];
        }
    }

    /** 不走动画地启动 —— 和集成之前完全一样的行为。 */
    function launchPlain(entry) {
        if (!entry)
            return;
        if (!entry.runInTerminal) {
            entry.execute();
            return;
        }
        // Quickshell 的 execute() 不会自己开终端（当前版本忽略 runInTerminal），
        // 这里沿用 ii 原本的兜底写法。
        Quickshell.execDetached(["bash", "-c",
            `${Config.options.apps.terminal} -e '${StringUtils.shellSingleQuoteEscape(entry.command.join(' '))}'`]);
    }

    function scriptArgs(cmd, entry) {
        const args = ["python3", root.scriptPath, "run",
            "--qs-dir", root.shellDir,
            "--exec-json", JSON.stringify(cmd),
            "--timeout", String(root.optTimeout)];
        // 下面这些只是"提示"，用来取名字/图标/窗口 class；拿不到不影响启动。
        if (entry.id)
            args.push("--entry-id", entry.id);
        if (entry.name)
            args.push("--label", entry.name);
        if (entry.icon)
            args.push("--icon", entry.icon);
        if (entry.workingDirectory)
            args.push("--cwd", entry.workingDirectory);
        if (!root.optWorkspaceLock)
            args.push("--no-workspace-lock");
        return args;
    }
}
