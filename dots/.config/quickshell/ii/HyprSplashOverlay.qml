pragma ComponentBehavior: Bound

// hypr-splash：应用启动动画的遮罩层。
//
//   阶段一 splash  ：图标在屏幕中心淡入 + 轻微放大，1.6s 后开始呼吸
//   阶段二 handoff ：窗口已经 map，遮罩整体淡出（普通淡出，不做几何变形）
//
// 为什么是普通窗口（FloatingWindow）而不是 layer-shell：
//   overlay 层是 per-output 的全局表面 —— 切到别的 workspace 它照样盖在那里。
//   普通窗口属于创建它的 workspace：切走即消失、切回即还在。这正是
//   "启动一个慢应用 → 切走干别的 → 它开好了再切回来" 要的行为。
//
// 窗口属性（浮动 / 铺满 / 无焦点 / 无动画 / 不装饰）交给 Hyprland 规则；编排脚本在
// 播放前用 hyprctl eval 注入。想固化就写进 ~/.config/hypr/custom/rules.lua，
// scripts/hyprSplash/README.md 给了片段。
//
// 关键：不要 pin。Hyprland 里 pin 的语义是"显示在所有工作区"，那等于退回 layer 时代的
// 全局行为 —— 正好是我们要摆脱的。
//
// 编排与调用见 services/HyprSplash.qml 与 scripts/hyprSplash/splash。
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets

Scope {
    id: root

    // ── 状态 ──────────────────────────────────────────────────────────
    property bool shown: false          // 窗口是否已 map（淡出动画期间保持 true）
    property string phase: "hidden"     // hidden | splash | handoff
    property real fade: 0               // 整体透明度

    // ── 内容 ──────────────────────────────────────────────────────────
    property string iconSource: ""
    property string appLabel: ""
    property color accent: Appearance.colors.colPrimary
    property string targetMonitor: ""

    // ── 形态参数 ──────────────────────────────────────────────────────
    property int iconSize: 132
    property int iconGlyph: 72
    property int radiusIdle: 34

    property real enterScale: 1
    property real pulseDelta: 1
    property int fadeDuration: 200

    /**
     * 统一的退场：整块遮罩（压暗层 / 图标 / 文字）一起淡出，淡完就 unmap。
     * handoff 与 cancel 只是触发时机不同，动作本身一样 —— 都是「普通淡出」，
     * 不缩、不滑、不变形。
     */
    function fadeOut(): void {
        fadeDuration = 180;
        fade = 0;
        unmap.interval = fadeDuration + 20;   // 淡完再拆窗口，留一帧余量
        unmap.restart();
    }

    // ── 对外控制（脚本通过 IpcHandler 调下面三个） ────────────────────
    function begin(icon: string, label: string, color: string, monitor: string): void {
        // 上一轮退场的 unmap 可能还没触发（连着启动两个应用时），必须掐掉，
        // 否则它会在新一轮动画中途把窗口拆了。
        unmap.stop();
        enterAnim.stop();
        pulseAnim.stop();
        enterScale = 0.84;
        pulseDelta = 1;
        iconSource = icon;
        appLabel = label;
        accent = (color.length > 0) ? color : Appearance.colors.colPrimary;
        targetMonitor = monitor;
        phase = "splash";
        fadeDuration = 200;
        shown = true;
        fade = 1;
        enterAnim.restart();
        pulseStart.restart();
    }

    function handoff(monitor: string, x: int, y: int, w: int, h: int): void {
        if (!shown) return;
        pulseAnim.stop();
        pulseDelta = 1;
        if (monitor.length > 0) targetMonitor = monitor;
        phase = "handoff";
        // x / y / w / h 收下但不用：早先会把容器变形到窗口矩形再淡出 —— 视觉上是先有一块
        // 主题色矩形铺满窗口、然后一起淡掉。现在窗口自己播开窗动画（popin），那一下就成了
        // 多余的两层动画，所以退场只留普通淡出。参数保留是为了 IPC 签名不变（脚本一直按
        // 5 个参数调 handoff）。
        fadeOut();
    }

    function cancel(): void {
        if (!shown) return;
        pulseAnim.stop();
        pulseDelta = 1;
        phase = "hidden";
        fadeOut();
    }

    // ── 定时器 ────────────────────────────────────────────────────────
    Timer { id: pulseStart; interval: 1600; onTriggered: pulseAnim.restart() }
    Timer {
        id: unmap
        onTriggered: {
            root.shown = false;
            root.phase = "hidden";
        }
    }

    // ── 动画 ─────────────────────────────────────────────────────────
    NumberAnimation { // 图标入场：0.84 → 1.0，emphasizedDecel 同族曲线
        id: enterAnim
        target: root; property: "enterScale"
        from: 0.84; to: 1.0; duration: 180
        easing.type: Easing.Bezier; easing.bezierCurve: [0.05, 0.7, 0.1, 1.0]
    }
    SequentialAnimation { // 等待期的呼吸：±4%
        id: pulseAnim
        loops: Animation.Infinite
        NumberAnimation { target: root; property: "pulseDelta"; to: 1.04; duration: 1000; easing.type: Easing.InOutSine }
        NumberAnimation { target: root; property: "pulseDelta"; to: 1.00; duration: 1000; easing.type: Easing.InOutSine }
    }

    // ── IPC 接口：qs -c ii ipc call splash <fn> ... ───────────────────
    IpcHandler {
        target: "splash"

        function begin(icon: string, label: string, color: string, monitor: string): void {
            root.begin(icon, label, color, monitor)
        }
        function handoff(monitor: string, x: int, y: int, w: int, h: int): void {
            root.handoff(monitor, x, y, w, h)
        }
        function cancel(): void {
            root.cancel()
        }
        function status(): string {
            return root.phase + (root.shown ? " (mapped)" : " (unmapped)")
        }
    }

    // ── 每块屏幕一个窗口，只有目标屏那个可见 ──────────────────────────
    //
    // 用 Quickshell.screens 起窗口而不是只起一个：目标屏由 begin() 的 monitor
    // 参数决定，非目标屏的窗口 visible=false，根本不 map、不进 clients 列表。
    Variants {
        model: Quickshell.screens

        FloatingWindow {
            id: win
            required property var modelData

            screen: modelData
            title: "hypr-splash"        // ← Hyprland 规则靠这个 title 匹配
            color: "transparent"
            visible: root.shown && (root.targetMonitor === "" || root.targetMonitor === modelData.name)

            // 默认铺满整块屏；实际几何由规则里的 size/move 决定（可能被夹进 workarea，
            // 避开 bar —— 见 README「关于 bar 和 workarea」）。
            implicitWidth: modelData.width
            implicitHeight: modelData.height

            Item {
                id: stage
                anchors.fill: parent
                opacity: root.fade
                Behavior on opacity {
                    NumberAnimation { duration: root.fadeDuration; easing.type: Easing.OutCubic }
                }

                Rectangle { // 背景压暗
                    anchors.fill: parent
                    color: "#000000"
                    opacity: 0.45
                }

                Rectangle {
                    id: blob
                    // 固定停在屏幕中心。退场只淡出，不再变形到窗口矩形（见 handoff 的注释）。
                    x: (stage.width - root.iconSize) / 2
                    y: (stage.height - root.iconSize) / 2
                    width: root.iconSize
                    height: root.iconSize
                    radius: root.radiusIdle
                    color: root.accent
                    scale: root.enterScale * root.pulseDelta
                    transformOrigin: Item.Center

                    // 用 ii 自己的图标组件：绝对路径和主题图标名都能解析，
                    // 渲染方式与 shell 其它地方一致。
                    AppIcon {
                        anchors.centerIn: parent
                        implicitSize: root.iconGlyph
                        source: root.iconSource
                        visible: root.iconSource !== ""
                    }
                }

                Text {
                    anchors.top: blob.bottom
                    anchors.topMargin: 18
                    anchors.left: parent.left
                    anchors.right: parent.right
                    horizontalAlignment: Text.AlignHCenter
                    text: root.appLabel
                    color: Appearance.colors.colOnLayer0
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
            }
        }
    }
}
