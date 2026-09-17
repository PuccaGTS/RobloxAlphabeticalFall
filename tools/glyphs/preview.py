"""Превью штриховых букв из src/shared/Logic/StrokeGlyphs.luau.

    python tools/glyphs/preview.py [build/glyphs.png]

Читает строки таблицы SHAPES, считает их теми же line/poly/arc/dot, что и Luau,
и рисует сетку: буква, её отражение, вверх ногами, на боку. Под отражением —
разница в долях квадрата; красная рамка — отражение неотличимо, в раунд не пойдёт.
"""
import math
import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[2]
source = (root / "src/shared/Logic/StrokeGlyphs.luau").read_text(encoding="utf-8")

T, M, B = (float(v) for v in re.search(r"local T, M, B = ([\d.]+), ([\d.]+), ([\d.]+)", source).groups())
WIDTH = float(re.search(r"StrokeGlyphs.WIDTH = ([\d.]+)", source).group(1))
OUTLINE = float(re.search(r"StrokeGlyphs.OUTLINE = ([\d.]+)", source).group(1))
THRESHOLD = float(re.search(r"MIRROR_MIN_DIFFERENCE = ([\d.]+)", source).group(1))


def line(x1, y1, x2, y2):
    return [(x1, y1), (x2, y2)]


def poly(*v):
    return [(v[i], v[i + 1]) for i in range(0, len(v) - 1, 2)]


def dot(x, y):
    return [(x, y), (x, y)]


def arc(cx, cy, rx, ry, a, b):
    steps = max(3, math.ceil(abs(b - a) / 15))
    return [(cx + rx * math.cos(math.radians(a + (b - a) * i / steps)), cy + ry * math.sin(math.radians(a + (b - a) * i / steps))) for i in range(steps + 1)]


def join(*parts):
    return [p for part in parts for p in part]


env = {"line": line, "poly": poly, "dot": dot, "arc": arc, "join": join, "T": T, "M": M, "B": B}
table = source.split("local SHAPES")[1].split("-- stylua: ignore end")[0]
shapes = {}
for match in re.finditer(r"^\t(\w+) = \{ (.*) \},$", table, re.M):
    shapes[match.group(1)] = eval("[" + match.group(2) + "]", env)

letters = re.findall(r'id = "(\w+)",\s*glyph = "(.)"', (root / "src/shared/Config/Letters.luau").read_text(encoding="utf-8"))


def transform(strokes, mirrored=False, rotation=0):
    result = []
    for stroke in strokes:
        out_stroke = []
        for x, y in stroke:
            if mirrored:
                x = 1 - x
            for _ in range(round(rotation / 90) % 4):
                x, y = 1 - y, x
            out_stroke.append((x, y))
        result.append(out_stroke)
    return result


def seg_distance(px, py, a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    length = dx * dx + dy * dy
    t = max(0, min(1, ((px - a[0]) * dx + (py - a[1]) * dy) / length)) if length > 0 else 0
    return math.hypot(a[0] + dx * t - px, a[1] + dy * t - py)


GRID = 32


def coverage(strokes):
    half = WIDTH / 2
    cells = []
    for row in range(GRID):
        for col in range(GRID):
            px, py = (col + 0.5) / GRID, (row + 0.5) / GRID
            cells.append(any(seg_distance(px, py, s[j], s[min(j + 1, len(s) - 1)]) <= half for s in strokes for j in range(max(1, len(s) - 1))))
    return cells


def difference(a, b):
    left, right = coverage(a), coverage(b)
    either = sum(1 for x, y in zip(left, right) if x or y)
    only = sum(1 for x, y in zip(left, right) if x != y)
    return only / either if either else 0


if __name__ == "__main__":
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "build" / "glyphs.png"
    CELL = 150
    cols = 4
    image = Image.new("RGB", (CELL * cols, CELL * len(letters)), (250, 248, 240))
    draw = ImageDraw.Draw(image)


    def render(strokes, ox, oy, color, pad=15):
        size = CELL - 2 * pad
        to = lambda p: (ox + pad + p[0] * size, oy + pad + p[1] * size)
        for width, fill in ((WIDTH + OUTLINE, (35, 30, 50)), (WIDTH, color)):
            w = width * size
            for stroke in strokes:
                pts = [to(p) for p in stroke]
                for a, b in zip(pts, pts[1:]):
                    draw.line([a, b], fill=fill, width=int(w))
                for p in pts:
                    draw.ellipse([p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2], fill=fill)


    for row, (letter_id, glyph) in enumerate(letters):
        y = row * CELL
        if letter_id not in shapes:
            draw.text((10, y + 10), f"{glyph} {letter_id}: НЕТ ШТРИХОВ", fill=(200, 0, 0))
            continue
        plain = shapes[letter_id]
        mirrored = transform(plain, True)
        diff = difference(plain, mirrored)
        render(plain, 0, y, (52, 116, 214))
        render(mirrored, CELL, y, (214, 69, 65))
        render(transform(plain, False, 180), CELL * 2, y, (120, 120, 130))
        render(transform(plain, False, 90), CELL * 3, y, (120, 120, 130))
        draw.text((4, y + 2), f"{glyph} {letter_id}", fill=(0, 0, 0))
        draw.text((CELL + 4, y + 2), f"{diff:.2f}", fill=(0, 0, 0))
        if diff < THRESHOLD:
            draw.rectangle([CELL, y, CELL * 2 - 1, y + CELL - 1], outline=(220, 0, 0), width=3)
        draw.line([(0, y), (CELL * cols, y)], fill=(200, 200, 200))

    out.parent.mkdir(parents=True, exist_ok=True)
    # Две половины: одна длинная картинка плохо читается.
    half = (len(letters) + 1) // 2
    image.crop((0, 0, CELL * cols, CELL * half)).save(out.with_name(out.stem + "_1.png"))
    image.crop((0, CELL * half, CELL * cols, CELL * len(letters))).save(out.with_name(out.stem + "_2.png"))
    print("mirror differs:", " ".join(g for i, g in letters if i in shapes and difference(shapes[i], transform(shapes[i], True)) >= THRESHOLD))
    print("mirror same:   ", " ".join(g for i, g in letters if i in shapes and difference(shapes[i], transform(shapes[i], True)) < THRESHOLD))
    print(out.with_name(out.stem + "_1.png"))
