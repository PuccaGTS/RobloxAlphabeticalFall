"""Play-проверка в настоящей Studio: игрок заходит, зонд пишет отчёт.

    python tools/playtest/run.py basic

Собирает место с зондом и сценарием tools/playtest/scenarios/<имя>.luau,
ставит временный плагин, открывает Studio, ждёт отчёт по HTTP, закрывает
Studio и убирает плагин.
"""
import http.server
import io
import json
import os
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path

root = Path(__file__).resolve().parents[2]
# Отчёт с эмодзи (⭐) не печатается в кодировке консоли Windows.
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
scenario = sys.argv[1] if len(sys.argv) > 1 else "basic"
build = root / "build" / "playtest"
build.mkdir(parents=True, exist_ok=True)
port = 34873

# Проект места: боевой плюс зонд, сценарий и порт.
project = json.loads((root / "default.project.json").read_text(encoding="utf-8"))
def rel(p):
    return os.path.relpath(p, build)
project["tree"]["ServerScriptService"]["Server"]["ZZ_ProbeServer"] = {"$path": rel(root / "tools/playtest/ProbeServer.server.luau")}
project["tree"]["ServerScriptService"]["Server"]["ZZ_Scenario"] = {"$path": rel(root / f"tools/playtest/scenarios/{scenario}.luau")}
project["tree"]["StarterPlayer"]["StarterPlayerScripts"]["ZZ_ProbeClient"] = {"$path": rel(root / "tools/playtest/ProbeClient.client.luau")}
project["tree"]["StarterPlayer"]["StarterPlayerScripts"]["ZZ_ProbeShots"] = {"$path": rel(root / "tools/playtest/ProbeShots.client.luau")}
project["tree"]["HttpService"] = {"$className": "HttpService", "$properties": {"HttpEnabled": True}}
for key in ("ReplicatedStorage",):
    for name, node in project["tree"][key].items():
        if isinstance(node, dict) and "$path" in node:
            p = node["$path"]
            if isinstance(p, dict):
                p["optional"] = rel(root / p["optional"])
            else:
                node["$path"] = rel(root / p)
for name, node in project["tree"]["ServerScriptService"].items():
    if isinstance(node, dict) and isinstance(node.get("$path"), str):
        node["$path"] = rel(root / node["$path"])
node = project["tree"]["StarterPlayer"]["StarterPlayerScripts"]["Client"]
node["$path"] = rel(root / node["$path"])
attrs = project["tree"]["Workspace"].setdefault("$attributes", {})
attrs["ZZ_ProbePort"] = port
attrs["ZZ_Mode"] = "play"
if os.environ.get("ZZ_ONLY"):
    attrs["ZZ_Only"] = os.environ["ZZ_ONLY"]
(build / "playtest.project.json").write_text(json.dumps(project, ensure_ascii=False, indent=2), encoding="utf-8")
place = build / "playtest.rbxl"
subprocess.run(["rojo", "build", str(build / "playtest.project.json"), "-o", str(place)], check=True)

plugins = Path(os.environ["LOCALAPPDATA"]) / "Roblox" / "Plugins"
plugins.mkdir(parents=True, exist_ok=True)
plugin = plugins / "ZZ_AlphabetFallPlaytest.rbxm"
(build / "plugin.project.json").write_text(json.dumps({"name": "ZZ_AlphabetFallPlaytest", "tree": {"$path": rel(root / "tools/playtest/Plugin.server.luau")}}), encoding="utf-8")
subprocess.run(["rojo", "build", str(build / "plugin.project.json"), "-o", str(plugin)], check=True)

shots = root / "build" / "shots"
shots.mkdir(parents=True, exist_ok=True)

capture_lock = threading.Lock()

def capture_window(name):
    """Снимок окна Studio через PrintWindow: работает, даже если окно перекрыто."""
    import ctypes
    from ctypes import wintypes
    from PIL import Image
    user32 = ctypes.windll.user32
    gdi32 = ctypes.windll.gdi32
    best = [None, 0]
    pid_wanted = studio.pid
    EnumProc = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    def each(hwnd, _):
        pid = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        if pid.value == pid_wanted and user32.IsWindowVisible(hwnd):
            rect = wintypes.RECT()
            user32.GetWindowRect(hwnd, ctypes.byref(rect))
            area = (rect.right - rect.left) * (rect.bottom - rect.top)
            if area > best[1]:
                best[0], best[1] = hwnd, area
        return True
    user32.EnumWindows(EnumProc(each), 0)
    hwnd = best[0]
    if not hwnd:
        print("SHOT: окно Studio не найдено")
        return
    # Свёрнутое окно рисуется в 0×0: разворачиваем, не забирая фокус у пользователя.
    if user32.IsIconic(hwnd):
        user32.ShowWindow(hwnd, 4)  # SW_SHOWNOACTIVATE
        time.sleep(1.5)
    rect = wintypes.RECT()
    user32.GetClientRect(hwnd, ctypes.byref(rect))
    width, height = rect.right, rect.bottom
    hdc = user32.GetDC(hwnd)
    mem = gdi32.CreateCompatibleDC(hdc)
    bitmap = gdi32.CreateCompatibleBitmap(hdc, width, height)
    gdi32.SelectObject(mem, bitmap)
    user32.PrintWindow(hwnd, mem, 3)  # PW_CLIENTONLY | PW_RENDERFULLCONTENT
    class BITMAPINFOHEADER(ctypes.Structure):
        _fields_ = [("biSize", wintypes.DWORD), ("biWidth", wintypes.LONG), ("biHeight", wintypes.LONG), ("biPlanes", wintypes.WORD), ("biBitCount", wintypes.WORD), ("biCompression", wintypes.DWORD), ("biSizeImage", wintypes.DWORD), ("biXPelsPerMeter", wintypes.LONG), ("biYPelsPerMeter", wintypes.LONG), ("biClrUsed", wintypes.DWORD), ("biClrImportant", wintypes.DWORD)]
    header = BITMAPINFOHEADER(ctypes.sizeof(BITMAPINFOHEADER), width, -height, 1, 32, 0, 0, 0, 0, 0, 0)
    buffer = ctypes.create_string_buffer(width * height * 4)
    gdi32.GetDIBits(mem, bitmap, 0, height, buffer, ctypes.byref(header), 0)
    image = Image.frombuffer("RGB", (width, height), buffer.raw, "raw", "BGRX", 0, 1).copy()
    path = shots / f"{name}.png"
    try:
        image.save(path)
    except Exception as error:
        print(f"SHOT save failed {name}: {error!r} size {width}x{height}")
    gdi32.DeleteObject(bitmap)
    gdi32.DeleteDC(mem)
    user32.ReleaseDC(hwnd, hdc)
    print(f"SHOT {path}")

received = []
done = threading.Event()
class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode("utf-8", "replace")
        if self.path == "/capture":
            with capture_lock:
                capture_window(body)
            self.send_response(200)
            self.end_headers()
            return
        received.append(body)
        if body == "DONE":
            done.set()
        self.send_response(200)
        self.end_headers()
    def log_message(self, *args):
        pass
server = http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()

import winreg
with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Software\Roblox\RobloxStudio") as key:
    content = winreg.QueryValueEx(key, "ContentFolder")[0]
exe = Path(content).parent / "RobloxStudioBeta.exe"
studio = subprocess.Popen([str(exe), str(place)])
try:
    if not done.wait(300):
        print("TIMEOUT: отчёта нет за 5 минут")
    for body in received:
        if body != "DONE":
            print(body)
finally:
    studio.kill()
    time.sleep(2)
    try:
        plugin.unlink()
    except OSError:
        pass
    server.shutdown()
