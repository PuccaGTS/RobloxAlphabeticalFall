"""Поиск моделей в Creator Store и лист миниатюр для выбора глазами.

    python tools/models/search.py "low poly tree" "cartoon slide" ...

Отбор: бесплатная, без скриптов, до MAX_TRIS треугольников, одобрение от 70 %.
Пишет build/models/<запрос>.png — сетка миниатюр с номерами — и candidates.json.
"""
import io
import json
import sys
import urllib.parse
import urllib.request
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

MAX_TRIS = 15000
root = Path(__file__).resolve().parents[2]
out = root / "build" / "models"
out.mkdir(parents=True, exist_ok=True)
HEADERS = {"User-Agent": "Mozilla/5.0"}


def get(url):
    return json.loads(urllib.request.urlopen(urllib.request.Request(url, headers=HEADERS), timeout=30).read())


def search(keyword, limit=120):
    ids = [d["id"] for d in get(f"https://apis.roblox.com/toolbox-service/v1/marketplace/10?limit={limit}&keyword={urllib.parse.quote(keyword)}").get("data", [])]
    found = []
    for i in range(0, len(ids), 30):
        chunk = ",".join(map(str, ids[i:i + 30]))
        for x in get(f"https://apis.roblox.com/toolbox-service/v1/items/details?assetIds={chunk}").get("data", []):
            asset, voting = x["asset"], x["voting"]
            tech = asset.get("modelTechnicalDetails") or {}
            tris = (tech.get("objectMeshSummary") or {}).get("triangles")
            scripts = (tech.get("instanceCounts") or {}).get("script", 0)
            free = (x.get("fiatProduct") or {}).get("isFree", True)
            if not free or asset.get("hasScripts") or scripts or tris is None or tris > MAX_TRIS:
                continue
            if voting["upVotes"] < 1 or voting["upVotePercent"] < 60:
                continue
            found.append({"assetId": asset["id"], "name": asset["name"], "creator": x["creator"]["name"], "tris": tris, "up": voting["upVotes"], "pct": voting["upVotePercent"]})
    found.sort(key=lambda f: -f["up"])
    return found[:12]


def sheet(keyword, items):
    if not items:
        return
    ids = ",".join(str(i["assetId"]) for i in items)
    thumbs = {t["targetId"]: t.get("imageUrl") for t in get(f"https://thumbnails.roblox.com/v1/assets?assetIds={ids}&size=150x150&format=Png")["data"]}
    cols = 6
    rows = (len(items) + cols - 1) // cols
    image = Image.new("RGB", (cols * 160, rows * 190), "white")
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 12)
    for n, item in enumerate(items):
        x, y = (n % cols) * 160, (n // cols) * 190
        url = thumbs.get(item["assetId"])
        if url:
            try:
                thumb = Image.open(io.BytesIO(urllib.request.urlopen(urllib.request.Request(url, headers=HEADERS), timeout=30).read())).convert("RGB")
                image.paste(thumb, (x + 5, y + 5))
            except Exception:
                pass
        draw.text((x + 5, y + 158), f"#{n} {item['name'][:22]}", fill="black", font=font)
        draw.text((x + 5, y + 172), f"{item['tris']} tri  +{item['up']}", fill="gray", font=font)
    safe = "".join(c if c.isalnum() else "_" for c in keyword)
    image.save(out / f"{safe}.png")


candidates_path = out / "candidates.json"
all_found = json.loads(candidates_path.read_text(encoding="utf-8")) if candidates_path.exists() else {}
for keyword in sys.argv[1:]:
    items = search(keyword)
    all_found[keyword] = items
    sheet(keyword, items)
    print(keyword, len(items))
candidates_path.write_text(json.dumps(all_found, ensure_ascii=False, indent=1), encoding="utf-8")
