"""Поиск бесплатных аксессуаров каталога Roblox и лист миниатюр для выбора глазами.

    python tools/models/catalog.py "flower crown" "cat ears" ... [--roblox]

Отбор: цена 0, в продаже, порядок каталога, от 200 добавлений в избранное.
Пишет build/catalog/<запрос>.png — сетка миниатюр с номерами, id и числом
избранного — и build/catalog/candidates.json. Номер вещи идёт в Config/Shop (worn).
"""
import io
import json
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parents[2]
out = root / "build" / "catalog"
out.mkdir(parents=True, exist_ok=True)
HEADERS = {"User-Agent": "Mozilla/5.0"}
# Типы ассетов-аксессуаров: шляпа, волосы, лицо, шея, плечи, грудь, спина, пояс.
ACCESSORY_TYPES = {8, 41, 42, 43, 44, 45, 46, 47}


def get(url):
    for attempt in range(6):
        try:
            return json.loads(urllib.request.urlopen(urllib.request.Request(url, headers=HEADERS), timeout=30).read())
        except urllib.error.HTTPError as error:
            if error.code == 429 and attempt < 5:
                time.sleep(10 * (attempt + 1))
                continue
            raise


def search(keyword, limit=24):
    found, cursor = [], ""
    for _ in range(3):
        url = (
            "https://catalog.roblox.com/v1/search/items/details?Category=11"
            f"&Keyword={urllib.parse.quote(keyword)}&MaxPrice=0&Limit=30&SalesTypeFilter=1"
            + ("&CreatorName=Roblox" if ROBLOX_ONLY else "")
            + (f"&Cursor={cursor}" if cursor else "")
        )
        page = get(url)
        for item in page.get("data", []):
            if item.get("assetType") not in ACCESSORY_TYPES or item.get("price") not in (0, None):
                continue
            if item.get("priceStatus") not in ("Free", None) and item.get("price") != 0:
                continue
            found.append({
                "id": item["id"],
                "name": item["name"],
                "type": item["assetType"],
                "fav": item.get("favoriteCount", 0),
                "creator": item.get("creatorName"),
            })
        cursor = page.get("nextPageCursor")
        if not cursor:
            break
        time.sleep(1)
    # Порядок каталога — по смыслу запроса; избранное только отсекает случайное.
    found = [f for f in found if f["fav"] >= 200]
    return found[:limit]


def sheet(keyword, items):
    if not items:
        return
    ids = ",".join(str(i["id"]) for i in items)
    thumbs = {t["targetId"]: t.get("imageUrl") for t in get(f"https://thumbnails.roblox.com/v1/assets?assetIds={ids}&size=150x150&format=Png")["data"]}
    cols = 6
    rows = (len(items) + cols - 1) // cols
    image = Image.new("RGB", (cols * 160, rows * 200), "white")
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 12)
    for n, item in enumerate(items):
        x, y = (n % cols) * 160, (n // cols) * 200
        url = thumbs.get(item["id"])
        if url:
            try:
                thumb = Image.open(io.BytesIO(urllib.request.urlopen(urllib.request.Request(url, headers=HEADERS), timeout=30).read())).convert("RGB")
                image.paste(thumb, (x + 5, y + 5))
            except Exception:
                pass
        draw.text((x + 5, y + 158), f"#{n} {item['name'][:22]}", fill="black", font=font)
        draw.text((x + 5, y + 172), f"{item['id']} t{item['type']}", fill="gray", font=font)
        draw.text((x + 5, y + 186), f"fav {item['fav']}", fill="gray", font=font)
    safe = "".join(c if c.isalnum() else "_" for c in keyword)
    image.save(out / f"{safe}.png")


# --roblox — только вещи самого Roblox: они аккуратные и не пропадают из каталога.
ROBLOX_ONLY = "--roblox" in sys.argv
keywords = [a for a in sys.argv[1:] if not a.startswith("--")]
candidates_path = out / "candidates.json"
all_found = json.loads(candidates_path.read_text(encoding="utf-8")) if candidates_path.exists() else {}
for keyword in keywords:
    if keyword in all_found:
        continue  # уже искали: каталог быстро отвечает 429, не тратим запросы
    items = search(keyword)
    all_found[keyword] = items
    candidates_path.write_bytes(json.dumps(all_found, ensure_ascii=False, indent=1).encode("utf-8"))
    try:
        sheet(keyword, items)
    except Exception as error:  # картинки с CDN доступны не везде; список важнее
        print("  без листа:", error)
    print(keyword, len(items))
    time.sleep(4)
