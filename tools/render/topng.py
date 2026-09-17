"""Собирает PNG из строк RENDER-BEGIN / R<y> / RENDER-END (tools/render/Render.luau).

    run-in-roblox ... | python tools/render/topng.py <папка>
"""
import re
import struct
import sys
import zlib
from pathlib import Path


def write_png(path, width, height, rows):
    raw = b"".join(b"\x00" + bytes.fromhex(rows.get(y, "000000" * width)) for y in range(height))
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    Path(path).write_bytes(png)


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    out.mkdir(parents=True, exist_ok=True)
    current = None
    for line in sys.stdin.buffer.read().decode("utf-8", "replace").splitlines():
        begin = re.search(r"RENDER-BEGIN (\S+) (\d+) (\d+)", line)
        if begin:
            current = (begin.group(1), int(begin.group(2)), int(begin.group(3)), {})
            continue
        if current and "RENDER-END" in line:
            name, width, height, rows = current
            write_png(out / f"{name}.png", width, height, rows)
            print(out / f"{name}.png")
            current = None
            continue
        row = re.search(r"R(\d+) ([0-9a-f]+)", line)
        if current and row and len(row.group(2)) == current[1] * 6:
            current[3][int(row.group(1))] = row.group(2)
        elif not current and ("rror" in line or "FAIL" in line):
            print(line)


main()
