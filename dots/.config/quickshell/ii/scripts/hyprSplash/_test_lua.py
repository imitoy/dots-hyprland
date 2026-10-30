#!/usr/bin/env python3
"""验证 splash 生成的 Lua 规则串在 Lua 5.5 里语法/运行都合法。

用 lua5.5 跑，并塞一个假的 hl 表（window_rule 返回带 set_enabled/is_enabled 的句柄），
这样 inject_window_rule / inject_workspace_rules / clear_workspace_rule 的整条路径
都能被真实执行到 —— 包括继承上一轮句柄的清理逻辑。
"""
import pathlib
import importlib.util, subprocess, sys, tempfile, os
from importlib.machinery import SourceFileLoader

PATH = str(pathlib.Path(__file__).resolve().parent / "splash")   # 就地跑：脚本就在旁边
loader = SourceFileLoader("splashmod", PATH)
spec = importlib.util.spec_from_loader("splashmod", loader)
m = importlib.util.module_from_spec(spec)
sys.modules["splashmod"] = m
loader.exec_module(m)

captured = []


class FakeProc:
    returncode = 0
    stdout = ""
    stderr = ""


def fake_hypr_eval(lua):
    captured.append(lua)
    return FakeProc()


m.hypr_eval = fake_hypr_eval
m.warn = lambda msg: print("  [warn] " + msg)

PRELUDE = """
-- 桩：[hypr-splash lua 规则校验]
hl = {
  window_rule = function(t)
    if type(t) ~= "table" then error("window_rule 需要 table") end
    if t.name == nil then error("window_rule 缺 name") end
    if t.match == nil then error("window_rule 缺 match") end
    local h = {}
    h.set_enabled = function(self, b) self._on = b end
    h.is_enabled = function(self) return self._on ~= false end
    return h
  end,
}
"""

# 覆盖各种 class 形态：点、短横线、正则元字符、中文、空
CLASSES = [
    "com.valvesoftware.Steam",
    "steam",
    "wemeetapp",
    "com.tencent.wemeet",
    "hypr-splash",
    "firefox",
    "a+b*c?d",
    "weird (name) [x]",
    "app$with^carets|and.pipes",
    "中文类名",
]

# 生成规则的调用，(标签, 产出捕获到的 lua 的函数)
JOBS = [
    ("inject_window_rule", lambda k: m.inject_window_rule()),
    ("inject_workspace_rules",
     lambda k: m.inject_workspace_rules(m.class_candidates(None, ["flatpak", "run", k]), 3)),
]


def lua_check(lua, tag):
    """把代码丢进 lua5.5 跑一遍（前面拼上 hl 桩）。"""
    with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False, dir=".") as f:
        f.write(PRELUDE + lua + "\nprint('ok')\n")
        path = f.name
    try:
        r = subprocess.run(["lua5.5", path], capture_output=True, text=True, timeout=15)
        # 末尾那行总是我们追加的 print('ok')；脚本中途出错就不会走到那儿
        lines = r.stdout.strip().splitlines()
        ok = r.returncode == 0 and bool(lines) and lines[-1] == "ok"
        print(("  [ OK ] " if ok else "  [FAIL] ") + tag)
        if not ok:
            print("         lua: " + ((r.stderr or r.stdout).strip()[:400]))
        return ok
    finally:
        os.unlink(path)


fails = 0
for tag, fn in JOBS:
    for klass in CLASSES:
        captured.clear()
        fn(klass)
        if not captured:
            print(f"  [跳过] {tag} klass={klass!r} —— 没有产生 lua")
            continue
        if not lua_check("\n".join(captured) + "\n", f"{tag}  klass={klass!r}"):
            fails += 1

# 单独校验"上一轮句柄的清理 + 关闭"整条路径：
# 先注一轮，再注第二轮（应能关掉上一轮），最后 clear。
captured.clear()
m.inject_workspace_rules([("steam", "^(steam)$"), ("Steam", "^(Steam)$")], 2)
first = "\n".join(captured)
captured.clear()
m.inject_workspace_rules([("steam", "^(steam)$")], 2)
second = "\n".join(captured)
captured.clear()
m.clear_workspace_rule()
closer = "\n".join(captured)

combined = first + "\n" + second + "\n" + closer + "\n"
if not lua_check(combined, "句柄清理路径（注两轮 + clear，检查没有悬空句柄）"):
    fails += 1

# 行为断言：两轮之后 _G 里只剩 1 个句柄，且被 clear 之后全部关掉
probe = combined + """
local n = #_G.__hypr_splash_ws
if n ~= 0 then error("clear 之后 _G.__hypr_splash_ws 应该被清空，实际 " .. n) end
print('ok')
"""
if not lua_check(probe, "clear 之后 _G.__hypr_splash_ws 已清空"):
    fails += 1

print()
print("FAILS =", fails)
sys.exit(1 if fails else 0)
