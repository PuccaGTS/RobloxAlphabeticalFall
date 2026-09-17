"""Play-проверка в настоящей Studio: игрок заходит, зонд пишет отчёт.

    python tools/playtest/run.py basic

Собирает место с зондом и сценарием tools/playtest/scenarios/<имя>.luau,
ставит временный плагин, открывает Studio, ждёт отчёт по HTTP, закрывает
Studio и убирает плагин.
"""
import http.server
import json
import os
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path

root = Path(__file__).resolve().parents[2]
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
project["tree"]["Workspace"].setdefault("$attributes", {})["ZZ_ProbePort"] = port
(build / "playtest.project.json").write_text(json.dumps(project, ensure_ascii=False, indent=2), encoding="utf-8")
place = build / "playtest.rbxl"
subprocess.run(["rojo", "build", str(build / "playtest.project.json"), "-o", str(place)], check=True)

plugins = Path(os.environ["LOCALAPPDATA"]) / "Roblox" / "Plugins"
plugins.mkdir(parents=True, exist_ok=True)
plugin = plugins / "ZZ_AlphabetFallPlaytest.rbxm"
(build / "plugin.project.json").write_text(json.dumps({"name": "ZZ_AlphabetFallPlaytest", "tree": {"$path": rel(root / "tools/playtest/Plugin.server.luau")}}), encoding="utf-8")
subprocess.run(["rojo", "build", str(build / "plugin.project.json"), "-o", str(plugin)], check=True)

received = []
done = threading.Event()
class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode("utf-8", "replace")
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
