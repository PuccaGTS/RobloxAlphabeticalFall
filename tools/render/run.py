"""Собрать место, прогнать проверочный скрипт с Render и сложить снимки в PNG.

    python tools/render/run.py tools/render/PlotCheck.server.luau build/render
"""
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[2]
script, out = Path(sys.argv[1]), sys.argv[2] if len(sys.argv) > 2 else "build/render"
render = (root / "tools/render/Render.luau").read_text(encoding="utf-8")
body = script.read_text(encoding="utf-8")
combined = root / "build/render_script.server.luau"
combined.parent.mkdir(exist_ok=True)
combined.write_text("local Render = (function()\n" + render + "\nend)()\n" + body, encoding="utf-8")
subprocess.run(["rojo", "build", "default.project.json", "-o", "build/game.rbxl"], cwd=root, check=True)
result = subprocess.run(
    ["run-in-roblox", "--place", "build/game.rbxl", "--script", str(combined)],
    cwd=root, capture_output=True,
)
subprocess.run([sys.executable, str(root / "tools/render/topng.py"), out], cwd=root, input=result.stdout + result.stderr)
