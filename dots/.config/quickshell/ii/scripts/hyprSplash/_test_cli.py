#!/usr/bin/env python3
"""hypr-splash 的 CLI / class 推断 / 工作区兜底 / 降级 打桩测试（不启动任何应用）。

覆盖：
  · `--` 透传（flatpak）
  · `--entry-id` + `--exec-json`（ii 集成主路径：命令由 Quickshell 给）
  · 候选 class 的生成（flatpak app id / 末段 / 小写 / 命令名）
  · 实测 class 的学习与下次复用
  · 工作区规则没命中时的"挪回 splash 那边"兜底
  · **降级**：overlay 不可用 / 动画阶段抛异常时，应用必须照样启动，且只启动一次
  · .desktop 的 Path= 与子目录 id

跑法：python3 _test_cli.py
"""
import io, json, sys, tempfile, contextlib
import pathlib
import importlib.util
from importlib.machinery import SourceFileLoader
from pathlib import Path

PATH = str(pathlib.Path(__file__).resolve().parent / "splash")   # 就地跑：脚本就在旁边
loader = SourceFileLoader("splashmod", PATH)
spec = importlib.util.spec_from_loader("splashmod", loader)
m = importlib.util.module_from_spec(spec)
sys.modules["splashmod"] = m
loader.exec_module(m)

# ── 沙箱：不碰真实 Hyprland / Quickshell / 真实 cache ──────────────────────
TMP = Path(tempfile.mkdtemp(prefix="splash-test-"))
m.CACHE_FILE = TMP / "classes.json"

launched = []          # 启动的应用命令
dispatches = []        # hyprctl dispatch ...
warnings = []
asked = []             # wait_for_window 收到的"候选"列表
calls = []             # qs_ipc(...) 调用
NEXT_WINDOW = {}       # 下一轮 wait_for_window 返回的窗口


class Proc:
    def __init__(self, rc=0, out="", err=""):
        self.returncode, self.stdout, self.stderr = rc, out, err


def fake_sh(cmd, timeout=5):
    if cmd[:2] == ["hyprctl", "dispatch"]:
        dispatches.append(cmd[2:])
    return Proc()


def fake_popen(cmd, **kw):
    launched.append(list(cmd))
    return None


m.sh = fake_sh
m.require_shell = lambda: True
m.focused_monitor = lambda: {"name": "eDP-1", "width": 2880, "height": 1800, "x": 0, "y": 0}
m.active_workspace = lambda: (2, "two")
m.qs_ipc = lambda *a, **k: calls.append(a)
m.clients = lambda: []
m.inject_workspace_rules = lambda *a, **k: None
m.clear_workspace_rule = lambda: None
m.resolve_icon = lambda x: "/usr/share/icons/hicolor/256x256/apps/%s.svg" % (x or "app")
m.window_rect = lambda w, mon, sp: (mon, 200, 150, 1200, 800)
m.subprocess.Popen = fake_popen
m._new_windows = lambda before: []
m.wait_for_window = lambda before, names, timeout: (asked.append(list(names)),
                                                    dict(NEXT_WINDOW) or None)[1]
m.wait_splash = lambda: {"address": "0xsplash", "title": "hypr-splash",
                         "at": [0, 40], "size": [2880, 1760], "floating": True,
                         "workspace": {"id": 2, "name": "2"}}
m._client_by_address = lambda addr: dict(NEXT_WINDOW)
m.warn = lambda msg: warnings.append(msg)


def run(args, window=None):
    """跑一次 main()。window = 这一轮假装出现的应用窗口。"""
    for lst in (launched, dispatches, warnings, asked, calls):
        lst.clear()
    NEXT_WINDOW.clear()
    if window:
        NEXT_WINDOW.update(window)
    old = sys.argv
    sys.argv = ["splash"] + args
    buf = io.StringIO()
    code = None
    try:
        with contextlib.redirect_stdout(buf):
            code = m.main()
    except SystemExit as e:
        code = e.code
    finally:
        sys.argv = old
    return code, buf.getvalue()


def hdr(t):
    print("=" * 74)
    print(t)


# ── 1. 候选 class 的生成（纯函数，不跑 main） ──────────────────────────────
hdr("1. class_candidates()")
for title, entry, cmd, explicit in [
    ("flatpak Steam —— 实测真 class 是 `steam`", None,
     ["flatpak", "run", "com.valvesoftware.Steam"], None),
    ("flatpak 腾讯会议 —— 实测真 class 是 app id", None,
     ["flatpak", "run", "--command=wemeetapp", "--file-forwarding",
      "com.tencent.wemeet", "@@u", "@@"], None),
    ("原生 firefox —— entry 带 StartupWMClass",
     {"id": "firefox", "wmclass": "firefox"}, ["/usr/lib/firefox/firefox"], None),
    ("用户强制 --class", None, ["flatpak", "run", "com.valvesoftware.Steam"], "steam"),
    ("裸命令 kitty", None, ["kitty", "-d", "/tmp"], None),
]:
    got = m.class_candidates(entry, cmd, explicit=explicit)
    print(f"  {title}")
    print(f"    候选 → {' / '.join(n for n, _ in got)}")

STEAM = ["run", "--", "flatpak", "run", "com.valvesoftware.Steam"]
STEAM_WIN = {"address": "0xsteam", "class": "steam", "title": "Steam",
             "at": [100, 100], "size": [1280, 800], "floating": False,
             "workspace": {"id": 3, "name": "3"}}      # 开在用户切去的 ws 3

# ── 2. 规则没命中 → 兜底挪窗口 → 学到的 class 记进缓存 ────────────────────
hdr("2. flatpak Steam：兜底移动 + class 学习")
code, out = run(STEAM, STEAM_WIN)
print(f"  exit={code}")
for line in out.rstrip().splitlines():
    print("  | " + line)
print(f"  脚本找的候选: {asked}")
print(f"  dispatch: {dispatches}")
for w in warnings:
    print(f"  [warn] {w}")
print(f"  缓存: {json.loads(m.CACHE_FILE.read_text()) if m.CACHE_FILE.exists() else '（空）'}")

hdr("3. 同一个应用第二次启动 —— 学到的 class 应排最前")
run(STEAM, STEAM_WIN)
print(f"  脚本找的候选: {asked}")
print(f"  缓存: {json.loads(m.CACHE_FILE.read_text())}")

# ── 4. 窗口本来就开对了 → 不该有任何 dispatch ─────────────────────────────
hdr("4. 窗口已在 splash 的工作区 → 不做任何移动")
w4 = dict(STEAM_WIN, workspace={"id": 2, "name": "2"})
run(STEAM, w4)
print(f"  dispatch（应为空）: {dispatches}")

# ── 5. --no-workspace-lock 该关掉一切 ─────────────────────────────────────
hdr("5. --no-workspace-lock")
run(["run", "--no-workspace-lock"] + STEAM[1:], STEAM_WIN)
print(f"  dispatch（应为空）: {dispatches}")

# ── 6. 参数解析（回归） ───────────────────────────────────────────────────
hdr("6. 参数解析：app 与 -- 二选一")
for argv in (["run"], ["run", "--"], ["run", "firefox"], STEAM,
             ["run", "firefox", "--", "--private-window"]):
    code, out = run(argv)
    print(f"  ./splash {' '.join(argv):48s} exit={code}  launch={launched or '（无）'}")

# ── 7. ii 集成主路径：--entry-id + --exec-json ────────────────────────────
hdr("7. --entry-id + --exec-json（ii 集成主路径）")
REAL_FIND_ENTRY = m.find_entry
REAL_DESKTOP_DIRS = m.DESKTOP_DIRS
m.find_entry = lambda aid: {"id": aid, "name": "VLC media player", "icon": "vlc",
                            "exec": "vlc %U", "wmclass": "vlc", "path": ""}
VLC_WIN = {"address": "0xvlc", "class": "vlc", "title": "VLC",
           "at": [0, 0], "size": [1600, 900], "floating": False,
           "workspace": {"id": 2, "name": "2"}}
code, out = run(["run", "--entry-id", "vlc", "--label", "VLC media player",
                 "--icon", "vlc",
                 "--exec-json", '["vlc", "--no-video-title-show", "/tmp/a b.mp4"]'],
                VLC_WIN)
print(f"  exit={code}")
print(f"  launch（参数必须逐项传递，带空格的那项不能被拆开）:")
for c in launched:
    print(f"    {c}")
print(f"  ipc: {[c[0] for c in calls]}")
print(f"  脚本找的候选: {asked}")

# ── 8. 降级：overlay 不可用 → 应用照样启动 ────────────────────────────────
hdr("8. 降级：overlay 不可用（require_shell=False）")
m.require_shell = lambda: False
code, out = run(STEAM, STEAM_WIN)
m.require_shell = lambda: True
print(f"  exit={code}  launch={launched}  ipc（应为空）={calls}")

# ── 9. --no-splash ────────────────────────────────────────────────────────
hdr("9. --no-splash：不碰 overlay，直接启动")
code, out = run(["run", "--no-splash"] + STEAM[1:], STEAM_WIN)
print(f"  exit={code}  launch={launched}  ipc（应为空）={calls}")

# ── 10. 动画阶段抛异常 → 也要启动应用，而且只启动一次 ─────────────────────
hdr("10. 动画阶段异常 → 降级且只启动一次")


def boom(*a, **k):
    raise RuntimeError("boom（模拟等窗口时炸了）")


real_wait = m.wait_for_window
m.wait_for_window = boom
code, out = run(STEAM, STEAM_WIN)
m.wait_for_window = real_wait
print(f"  exit={code}  启动次数={len(launched)}（必须是 1）  launch={launched}")
print(f"  [warn] {[w for w in warnings]}")

# ── 11. .desktop 的 Path= 与子目录 id ─────────────────────────────────────
hdr("11. Path= 与子目录 id")
m.find_entry = REAL_FIND_ENTRY          # 换回真实现（第 7 节打的是桩）
sub = TMP / "applications"
(sub / "sub" / "kde4").mkdir(parents=True)
(sub / "sub" / "kde4" / "foo.desktop").write_text(
    "[Desktop Entry]\nType=Application\nName=Foo\nExec=foo --flag\n"
    f"Path={TMP}\nStartupWMClass=foo\n", encoding="utf-8")
m.DESKTOP_DIRS = [str(sub)]
for aid in ("foo", "kde4-foo", "sub-kde4-foo"):
    e = m.find_entry(aid)
    print(f"  find_entry({aid!r}) → {'命中 name=%r wmclass=%r' % (e['name'], e['wmclass']) if e else '未命中'}")
e = m.find_entry("kde4-foo")
print(f"  _entry_cwd(entry)         → {m._entry_cwd(e)}   （期望 {TMP}）")
print(f"  _entry_cwd(entry, '/tmp') → {m._entry_cwd(e, '/tmp')}   （--cwd 优先）")
print(f"  find_entry('不存在的应用')  → {m.find_entry('不存在的应用')}")
m.DESKTOP_DIRS = REAL_DESKTOP_DIRS
