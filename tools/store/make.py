"""Иконка и превью для страницы игры на Roblox.

    ZZ_WINDOW=2300x1320 python tools/playtest/run.py store   # кадры Play в build/shots
    python tools/store/make.py                               # assets/store/*.png

Превью — настоящие кадры игры (правило Roblox: превью не обещает того, чего
в игре нет), обрезанные до 16:9, с короткой подписью для родителя.
Иконка — рисунок: буквы теми же штрихами, что в игре (Logic/StrokeGlyphs),
на фоне радуги над холмом. Текста на иконке нет: название решает владелец.
"""
import math
import os
import runpy
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

root = Path(__file__).resolve().parents[2]
shots = root / "build" / "shots"
out = root / "assets" / "store"
out.mkdir(parents=True, exist_ok=True)

# Кириллица есть в Montserrat из поставки Studio; FredokaOne её не знает.
fonts = Path(os.environ["LOCALAPPDATA"]) / "Roblox" / "Versions"
montserrat = next(fonts.glob("*/content/fonts/Montserrat-Black.ttf"), None)
if montserrat is None:
    sys.exit("Нет Montserrat-Black.ttf в папке Studio")

# Видовая область Studio в растянутом окне (ZZ_WINDOW=2300x1320): внутри синей рамки.
VIEW = (3, 144, 1946, 989)
# Кнопки Roblox в левом верхнем углу: обрезка начинается правее них.
LEFT_MIN = 140

THUMBS = [
    ("store_plaza", "Мир букв и мир счёта", 973, "bottom"),
    ("store_mirror", "Найди букву, написанную правильно", 973, "bottom"),
    ("store_rain", "Лови букву, которую назвал голос", 912, "bottom"),
    # Подпись сверху: снизу на карточке картинка и слово, их закрывать нельзя.
    ("ui_store_intro", "Я — яблоко: у каждой буквы картинка", 1026, "top"),
    ("store_bubbles", "Лопай пузыри с нужной буквой", 1117, "bottom"),
    ("store_pond_2", "Парк, где всегда кто-то живёт", 912, "bottom"),
]


def thumbnail(name, caption, center_x, where, index):
    shot = Image.open(shots / f"{name}.png").convert("RGB")
    x0, y0, x1, y1 = VIEW
    height = y1 - y0
    width = round(height * 16 / 9)
    left = max(x0 + LEFT_MIN, min(center_x - width // 2, x1 - width))
    frame = shot.crop((left, y0, left + width, y1)).resize((1920, 1080), Image.LANCZOS)
    frame = frame.filter(ImageFilter.UnsharpMask(radius=2, percent=60, threshold=2))

    draw = ImageDraw.Draw(frame, "RGBA")
    font = ImageFont.truetype(str(montserrat), 64)
    box = draw.textbbox((0, 0), caption, font=font)
    pad_x, pad_y = 44, 26
    w, h = box[2] - box[0] + pad_x * 2, box[3] - box[1] + pad_y * 2
    x, y = 60, (56 if where == "top" else 1080 - h - 56)
    draw.rounded_rectangle((x + 6, y + 8, x + w + 6, y + h + 8), radius=h // 2, fill=(20, 20, 40, 90))
    draw.rounded_rectangle((x, y, x + w, y + h), radius=h // 2, fill=(255, 250, 240, 240))
    draw.text((x + pad_x - box[0], y + pad_y - box[1]), caption, font=font, fill=(60, 50, 90))
    # JPEG: PNG кадра игры весит два мегабайта, а на странице разницы не видно.
    path = out / f"thumb_{index}.jpg"
    frame.save(path, quality=92)
    print(path)


def icon():
    glyphs = runpy.run_path(str(root / "tools" / "glyphs" / "preview.py"), run_name="glyphs")
    size = 2048  # рисуем крупно и уменьшаем: так края гладкие
    image = Image.new("RGB", (size, size))
    draw = ImageDraw.Draw(image)
    # Небо: сверху насыщенное, к горизонту светлее.
    for y in range(size):
        t = y / size
        draw.line([(0, y), (size, y)], fill=(int(90 + 110 * t), int(170 + 60 * t), int(245 - 10 * t)))
    # Радуга: концентрические дуги от внешней красной.
    colors = [(235, 80, 80), (245, 150, 60), (250, 220, 80), (110, 200, 110), (90, 170, 240), (90, 110, 220), (160, 100, 210)]
    band = 70
    cx, cy = size // 2, int(size * 0.98)
    for i, color in enumerate(colors):
        r = int(size * 0.62) - i * band
        draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=color)
    r = int(size * 0.62) - len(colors) * band
    sky = image.getpixel((cx, cy - r - 10))
    draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=sky)
    # Холм.
    draw.ellipse((-size * 0.3, size * 0.74, size * 1.3, size * 1.6), fill=(110, 190, 95))
    draw.ellipse((-size * 0.3, size * 0.78, size * 1.3, size * 1.64), fill=(95, 175, 85))

    shapes, transform = glyphs["shapes"], glyphs["transform"]
    outline, width = glyphs["OUTLINE"], glyphs["WIDTH"]

    def letter(letter_id, color, box, tilt):
        layer = Image.new("RGBA", (box, box), (0, 0, 0, 0))
        ld = ImageDraw.Draw(layer)
        strokes = transform(shapes[letter_id])
        scale = box
        for stroke_width, fill in ((width + outline * 1.6, (40, 30, 70, 255)), (width, color + (255,))):
            w = stroke_width * scale
            for stroke in strokes:
                pts = [(p[0] * scale, p[1] * scale) for p in stroke]
                for a, b in zip(pts, pts[1:]):
                    ld.line([a, b], fill=fill, width=int(w))
                for p in pts:
                    ld.ellipse((p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2), fill=fill)
        return layer.rotate(tilt, resample=Image.BICUBIC, expand=False)

    red, blue = (225, 70, 65), (55, 120, 220)
    for letter_id, color, box, x, y, tilt in (
        ("a", red, 1000, 150, 700, 8),
        ("b", blue, 860, 930, 830, -6),
        ("ya", red, 600, 1420, 290, -12),
    ):
        # Тень под буквой.
        shadow = letter(letter_id, (0, 0, 0), box, tilt).split()[3].point(lambda a: int(a * 0.25))
        image.paste((30, 40, 60), (x + 30, y + 40), shadow.filter(ImageFilter.GaussianBlur(18)))
        layer = letter(letter_id, color, box, tilt)
        image.paste(layer, (x, y), layer)

    # Звёздочка — валюта игры.
    emoji = ImageFont.truetype("C:/Windows/Fonts/seguiemj.ttf", 109)
    star = Image.new("RGBA", (160, 160), (0, 0, 0, 0))
    ImageDraw.Draw(star).text((10, 10), "⭐", font=emoji, embedded_color=True)
    star = star.resize((520, 520), Image.LANCZOS).rotate(12, resample=Image.BICUBIC)
    image.paste(star, (140, 120), star)

    path = out / "icon.png"
    image.resize((512, 512), Image.LANCZOS).save(path)
    print(path)


if __name__ == "__main__":
    for index, (name, caption, center, where) in enumerate(THUMBS, start=1):
        thumbnail(name, caption, center, where, index)
    icon()
