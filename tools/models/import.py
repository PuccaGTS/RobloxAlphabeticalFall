"""Импорт моделей Creator Store в файлы проекта через Studio.

    python tools/models/import.py tools/models/picks.json

picks.json — список {"id": "tree_pine", "assetId": 123}. Studio открывает пустое
место, временный плагин берёт каждую модель через game:GetObjects (так можно
и без владения моделью), вырезает скрипты и присылает описание. Скрипт пишет
assets/models/decor/<id>.model.json — Rojo кладёт его в ReplicatedStorage.Assets.decor,
и DecorService ставит модель вместо эскиза (docs/21-DECOR.md).
"""
import http.server
import json
import os
import subprocess
import sys
import threading
import time
import winreg
from pathlib import Path

root = Path(__file__).resolve().parents[2]
picks = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
out_dir = root / "assets" / "models" / "decor"
out_dir.mkdir(parents=True, exist_ok=True)
build = root / "build" / "import"
build.mkdir(parents=True, exist_ok=True)
port = 34874


def rel(p):
    return os.path.relpath(p, build)


project = {
    "name": "ModelImport",
    "tree": {
        "$className": "DataModel",
        "ServerScriptService": {"$className": "ServerScriptService", "Server": {"$className": "Folder", "ZZ_ProbeServer": {"$className": "Folder"}}},
        "Workspace": {
            "$className": "Workspace",
            "$attributes": {"ZZ_Mode": "import", "ZZ_ProbePort": port, "ZZ_ImportIds": json.dumps(picks)},
        },
    },
}
(build / "import.project.json").write_text(json.dumps(project, ensure_ascii=False), encoding="utf-8")
place = build / "import.rbxl"
subprocess.run(["rojo", "build", str(build / "import.project.json"), "-o", str(place)], check=True)

plugins = Path(os.environ["LOCALAPPDATA"]) / "Roblox" / "Plugins"
plugin = plugins / "ZZ_AlphabetFallPlaytest.rbxm"
(build / "plugin.project.json").write_text(json.dumps({"name": "ZZ_AlphabetFallPlaytest", "tree": {"$path": rel(root / "tools/playtest/Plugin.server.luau")}}), encoding="utf-8")
subprocess.run(["rojo", "build", str(build / "plugin.project.json"), "-o", str(plugin)], check=True)


def convert(node):
    out = {"className": node["ClassName"]}
    if node.get("Name"):
        out["name"] = node["Name"]
    if node.get("Properties"):
        out["properties"] = node["Properties"]
    if node.get("Children"):
        out["children"] = [convert(child) for child in node["Children"]]
    return out


done = threading.Event()
class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode("utf-8", "replace")
        if self.path == "/model":
            data = json.loads(body)
            model = convert(data["model"])
            model.pop("name", None)
            path = out_dir / f"{data['id']}.model.json"
            path.write_text(json.dumps(model, ensure_ascii=False, indent=1), encoding="utf-8")
            size = " x ".join(f"{v:.1f}" for v in data.get("size", []))
            print(f"OK {data['id']} [{size}] -> {path.relative_to(root)}" + (f" (пропущено: {data['skipped']})" if data["skipped"] else ""))
        elif body == "DONE":
            done.set()
        else:
            print(body)
        self.send_response(200)
        self.end_headers()
    def log_message(self, *args):
        pass
server = http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()

with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Software\Roblox\RobloxStudio") as key:
    content = winreg.QueryValueEx(key, "ContentFolder")[0]
studio = subprocess.Popen([str(Path(content).parent / "RobloxStudioBeta.exe"), str(place)])
try:
    if not done.wait(600):
        print("TIMEOUT")
finally:
    studio.kill()
    time.sleep(2)
    try:
        plugin.unlink()
    except OSError:
        pass
    server.shutdown()
