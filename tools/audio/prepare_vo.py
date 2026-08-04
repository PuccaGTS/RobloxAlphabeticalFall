#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Подготовка озвучки к загрузке в Roblox.

Что делает:
  · сводит в моно (Roblox всё равно играет 3D-звук как моно, стерео — вдвое лишний вес);
  · подрезает тишину по краям к единому виду, с мягкими фейдами против щелчков;
  · выравнивает громкость по ITU-R BS.1770-4 (LUFS), а не по пику, — чтобы эталон
    звука буквы не оказался тише похвалы;
  · оставляет запас по пику, потому что Roblox пережимает аудио при загрузке
    и упёртый в 0 dBFS файл начинает трещать на «п», «б», «т»;
  · пишет 16 бит с TPDF-дизерингом;
  · собирает assets/audio/MANIFEST.csv — единственную связь «файл → assetId»,
    так как сами файлы в репозиторий не кладутся (см. .gitignore).

Громкость выравнивается ОДНИМ общим сдвигом на все файлы: цель подбирается так,
чтобы ни один файл не пришлось лимитировать сильнее, чем --max-limit. Разница
между репликами при этом сохраняется ровно нулевая, а искажений нет вовсе.

Запуск:
    python tools/audio/prepare_vo.py                # обработать
    python tools/audio/prepare_vo.py --check        # только измерить, ничего не писать

См. docs/05-AUDIO-VO.md и docs/10-CONTENT-PIPELINE.md.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import math
import sys
import wave
from pathlib import Path

import numpy as np
from scipy.ndimage import minimum_filter1d, uniform_filter1d

from audiolib import REPO, db, loudness_lufs, read_wav, rel, setup_console, to_mono, write_wav16

setup_console()

SRC = REPO / "music" / "Реплики" / "1-69"
OUT = REPO / "music" / "Готовое" / "vo"
MANIFEST = REPO / "assets" / "audio" / "MANIFEST.csv"
SCRIPT = REPO / "docs" / "VO-SCRIPT.md"

# Цель по громкости. -20 LUFS — компромисс: речь остаётся разборчивой на слабом
# динамике планшета, но не требует лимитирования файлов с резкими взрывными.
TARGET_LUFS = -20.0
# Потолок по пику. -3 dBFS оставляет запас на интерсемпловые выбросы после
# пережатия на стороне Roblox.
CEILING_DBFS = -3.0
# Насколько сильно позволено лимитировать самый «пиковый» файл, дБ.
# Упирается всегда в snd_long_m: K-взвешивание срезает низ, а «м-м-м» — носовой
# звук, вся энергия которого как раз внизу. Формально он тихий, по факту пик у
# него высокий. Поднимать допуск смысла нет: на 2 дБ разброс уже 0.2 дБ, а на 4 дБ
# он становится хуже (0.9 дБ) и лимитер лезет ещё в восемь файлов.
MAX_LIMIT_DB = 2.0

PAD_HEAD = 0.025  # тишина перед репликой, с
PAD_TAIL = 0.070  # тишина после реплики, с
FADE = 0.003      # фейд по краям, с — страховка от щелчка
TRIM_MIN = 0.030  # подрезаем, только если убирается больше этого


# ─────────────────────────── обработка ───────────────────────────


def speech_bounds(x: np.ndarray, sr: int) -> tuple[int, int]:
    """Границы речи по огибающей. Порог мягкий, чтобы не срезать тихий выдох «п»."""
    win = max(1, int(0.010 * sr))
    pad = (-x.size) % win
    env = np.sqrt((np.pad(x, (0, pad)) ** 2).reshape(-1, win).mean(axis=1))
    peak = float(np.max(np.abs(x))) if x.size else 0.0
    if peak <= 0:
        return 0, x.size
    thr = max(peak * (10 ** (-45 / 20)), 10 ** (-60 / 20))
    voiced = np.flatnonzero(env > thr)
    if voiced.size == 0:
        return 0, x.size
    return int(voiced[0] * win), int(min(x.size, (voiced[-1] + 1) * win))


def trim(x: np.ndarray, sr: int) -> np.ndarray:
    """Приводит тишину по краям к единому виду, но никогда не удлиняет файл."""
    lo, hi = speech_bounds(x, sr)
    want_lo = max(0, lo - int(PAD_HEAD * sr))
    want_hi = min(x.size, hi + int(PAD_TAIL * sr))
    if want_lo < int(TRIM_MIN * sr):
        want_lo = 0
    if x.size - want_hi < int(TRIM_MIN * sr):
        want_hi = x.size
    return x[want_lo:want_hi]


def fade_edges(x: np.ndarray, sr: int) -> np.ndarray:
    n = min(int(FADE * sr), x.size // 2)
    if n <= 0:
        return x
    ramp = np.linspace(0.0, 1.0, n)
    x = x.copy()
    x[:n] *= ramp
    x[-n:] *= ramp[::-1]
    return x


def limit(x: np.ndarray, sr: int, ceiling: float) -> tuple[np.ndarray, float]:
    """
    Лимитер с предпросмотром. Возвращает сигнал и максимальное ослабление в дБ.

    Гейн сглаживается, поэтому вместо щелчка получается незаметное приседание
    на взрывном согласном.
    """
    peak = np.abs(x)
    if float(peak.max(initial=0.0)) <= ceiling:
        return x, 0.0

    need = np.ones_like(x)
    hot = peak > ceiling
    need[hot] = ceiling / peak[hot]

    look = max(1, int(0.005 * sr))
    g = minimum_filter1d(need, size=2 * look + 1, mode="nearest")
    g = uniform_filter1d(g, size=2 * look + 1, mode="nearest")
    g = minimum_filter1d(g, size=2 * look + 1, mode="nearest")

    y = x * g
    # После сглаживания возможен остаточный выброс — добиваем статикой.
    top = float(np.abs(y).max(initial=0.0))
    if top > ceiling:
        y *= ceiling / top
    return y, -db(float(g.min(initial=1.0)))


# ─────────────────────────── список реплик ───────────────────────────


def expected_keys() -> list[str]:
    """Ключи из docs/VO-SCRIPT.md — источник правды по составу озвучки."""
    if not SCRIPT.exists():
        return []
    keys: list[str] = []
    for line in SCRIPT.read_text(encoding="utf-8").splitlines():
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.split("|")]
        if len(cells) > 2 and cells[2].startswith("`") and cells[2].endswith("`"):
            keys.append(cells[2].strip("`"))
    return keys


# ─────────────────────────── основной проход ───────────────────────────


def main() -> int:
    ap = argparse.ArgumentParser(description="Подготовка озвучки к загрузке в Roblox")
    ap.add_argument("--src", type=Path, default=SRC)
    ap.add_argument("--out", type=Path, default=OUT)
    ap.add_argument("--manifest", type=Path, default=MANIFEST)
    ap.add_argument("--target", type=float, default=TARGET_LUFS, help="целевая громкость, LUFS")
    ap.add_argument("--ceiling", type=float, default=CEILING_DBFS, help="потолок пика, dBFS")
    ap.add_argument("--max-limit", type=float, default=MAX_LIMIT_DB,
                    help="сколько дБ лимитирования допустимо, чтобы поднять общую цель")
    ap.add_argument("--no-trim", action="store_true", help="не трогать тишину по краям")
    ap.add_argument("--check", action="store_true", help="только измерить, ничего не писать")
    args = ap.parse_args()

    if not args.src.is_dir():
        print(f"нет папки с исходниками: {args.src}", file=sys.stderr)
        return 1

    files = sorted(p for p in args.src.iterdir() if p.suffix.lower() == ".wav")
    if not files:
        print(f"в {args.src} нет wav-файлов", file=sys.stderr)
        return 1

    # ── проход 1: читаем, чистим, измеряем ──
    print(f"Читаю {len(files)} файлов из {rel(args.src)}\n")
    items = []
    for i, path in enumerate(files, 1):
        x, sr = read_wav(path)
        x = to_mono(x)
        src_dur = x.size / sr
        src_peak = db(float(np.abs(x).max(initial=0.0)))
        if not args.no_trim:
            x = trim(x, sr)
        x = fade_edges(x, sr)
        lufs = loudness_lufs(x, sr)
        peak = db(float(np.abs(x).max(initial=0.0)))
        items.append(dict(key=path.stem, sr=sr, audio=x, lufs=lufs, peak=peak,
                          dur=x.size / sr, src_dur=src_dur, src_peak=src_peak))
        print(f"\r  измерено {i}/{len(files)}", end="", flush=True)
    print("\n")

    # ── выбор общей цели ──
    # Ослабление для файла i:  gain_i = target - lufs_i
    # Пик после него:          peak_i + gain_i  ≤  ceiling + max_limit
    headroom = min(args.ceiling + args.max_limit - it["peak"] + it["lufs"] for it in items)
    target = min(args.target, headroom)
    tight = min(items, key=lambda it: args.ceiling + args.max_limit - it["peak"] + it["lufs"])

    print(f"Цель: {args.target:+.1f} LUFS, потолок {args.ceiling:+.1f} dBFS, "
          f"лимитирование до {args.max_limit:.0f} дБ")
    if target < args.target - 0.05:
        print(f"  ↓ опускаю цель до {target:+.1f} LUFS: упирается «{tight['key']}» "
              f"(крест-фактор {tight['peak'] - tight['lufs']:.1f} дБ)")
    else:
        print(f"  цель достижима без снижения")
    print()

    # ── проход 2: применяем ──
    ceiling_lin = 10 ** (args.ceiling / 20)
    rows = []
    limited = []
    for it in items:
        gain_db = target - it["lufs"]
        y = it["audio"] * (10 ** (gain_db / 20))
        y, reduced = limit(y, it["sr"], ceiling_lin)
        if reduced > 0.05:
            limited.append((it["key"], reduced))
        it["out"] = y
        it["gain"] = gain_db
        it["reduced"] = reduced
        it["out_lufs"] = loudness_lufs(y, it["sr"])
        it["out_peak"] = db(float(np.abs(y).max(initial=0.0)))

    # ── отчёт ──
    print(f"{'реплика':<22}{'сек':>6}{'было LUFS':>11}{'сдвиг':>8}"
          f"{'стало LUFS':>12}{'пик':>8}{'лимит':>8}")
    for it in sorted(items, key=lambda i: i["key"]):
        lim = f"{it['reduced']:.1f}" if it["reduced"] > 0.05 else "—"
        print(f"{it['key']:<22}{it['dur']:>6.2f}{it['lufs']:>11.1f}"
              f"{it['gain']:>+8.1f}{it['out_lufs']:>12.1f}{it['out_peak']:>8.1f}{lim:>8}")

    src_spread = max(i["lufs"] for i in items) - min(i["lufs"] for i in items)
    out_spread = max(i["out_lufs"] for i in items) - min(i["out_lufs"] for i in items)
    print()
    print(f"Разброс громкости: было {src_spread:.1f} дБ → стало {out_spread:.1f} дБ")
    print(f"Максимальный пик:  было {max(i['src_peak'] for i in items):.1f} → "
          f"стало {max(i['out_peak'] for i in items):.1f} dBFS")
    print(f"Лимитирование затронуло файлов: {len(limited)}"
          + (f" (сильнее всех «{max(limited, key=lambda t: t[1])[0]}», "
             f"{max(l[1] for l in limited):.1f} дБ)" if limited else ""))

    trimmed = sum(1 for i in items if i["src_dur"] - i["dur"] > 0.001)
    saved = sum(i["src_dur"] - i["dur"] for i in items)
    print(f"Подрезано по краям: {trimmed} файлов, суммарно {saved:.1f} с")

    # ── сверка состава ──
    want = expected_keys()
    if want:
        have = {i["key"] for i in items}
        missing = [k for k in want if k not in have]
        extra = sorted(have - set(want))
        print(f"Состав по VO-SCRIPT.md: {len(have)}/{len(want)}"
              + (f", нет: {missing}" if missing else "")
              + (f", лишние: {extra}" if extra else ""))

    if args.check:
        print("\n--check: файлы не записаны")
        return 0

    # ── запись ──
    args.out.mkdir(parents=True, exist_ok=True)
    for it in items:
        write_wav16(args.out / f"{it['key']}.wav", it["out"], it["sr"])
        it["sha1"] = hashlib.sha1((args.out / f"{it['key']}.wav").read_bytes()).hexdigest()[:12]

    total = sum((args.out / f"{i['key']}.wav").stat().st_size for i in items)
    src_total = sum(p.stat().st_size for p in files)
    print(f"\nЗаписано {len(items)} файлов в {rel(args.out)}")
    print(f"Объём: {src_total / 1048576:.0f} МБ → {total / 1048576:.0f} МБ "
          f"(моно 16 бит, {items[0]['sr'] // 1000} кГц)")

    # ── манифест ──
    args.manifest.parent.mkdir(parents=True, exist_ok=True)
    existing: dict[str, dict] = {}
    if args.manifest.exists():
        with args.manifest.open(encoding="utf-8", newline="") as f:
            for row in csv.DictReader(f):
                existing[row["key"]] = row

    with args.manifest.open("w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["key", "file", "sec", "lufs", "peak_dbfs", "sha1", "asset_id", "uploaded"])
        for it in sorted(items, key=lambda i: i["key"]):
            old = existing.get(it["key"], {})
            # assetId и дату загрузки проставляет человек после загрузки — не затираем
            w.writerow([it["key"], f"{it['key']}.wav", f"{it['dur']:.2f}",
                        f"{it['out_lufs']:.1f}", f"{it['out_peak']:.1f}", it["sha1"],
                        old.get("asset_id", ""), old.get("uploaded", "")])

    kept = sum(1 for it in items if existing.get(it["key"], {}).get("asset_id"))
    print(f"Манифест: {rel(args.manifest)}"
          + (f" (сохранено {kept} уже проставленных assetId)" if kept else ""))
    print("\nДальше: залить папку на аккаунт группы, вписать assetId в манифест, "
          "затем в AudioRegistry.luau")
    return 0


if __name__ == "__main__":
    sys.exit(main())
