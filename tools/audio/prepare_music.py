#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Подготовка фоновой музыки: выбор трека на остров и бесшовный луп.

Что делает:
  · меряет темп, громкость и распределение энергии по полосам;
  · выбирает из кандидатов на остров тот, что меньше мешает озвучке;
  · режет луп длиной в целое число тактов и сшивает края кроссфейдом,
    чтобы Sound.Looped не давал слышимого шва;
  · срезает инфраниз, который планшет всё равно не воспроизведёт, а место
    в миксе занимает;
  · выравнивает громкость между островами и относительно озвучки.

Почему выбор идёт по полосе 100–500 Гц: голос диктора живёт именно там
(основной тон 111 Гц), и бас фонка бьёт ровно в неё. Дакинг в AudioController
опускает музыку на время реплики, но он давит громкость, а не маскировку,
поэтому трек лучше брать тот, у которого в этой полосе изначально меньше.

Кандидаты берутся по имени файла: «Остров1_1.wav» → остров 1. Остальные файлы
в папке считаются запасными и в выбор не идут, но меряются наравне.

Запуск:
    python tools/audio/prepare_music.py --check      # только измерить
    python tools/audio/prepare_music.py              # собрать лупы
    python tools/audio/prepare_music.py --pick 2=Остров2_1
"""

from __future__ import annotations

import argparse
import hashlib
import math
import re
import sys
from pathlib import Path

import numpy as np
from scipy.signal import butter, sosfiltfilt

sys.path.insert(0, str(Path(__file__).resolve().parent))
from audiolib import (REPO, band_energy, db, loudness_lufs, peak_db, read_wav, rel,
                      setup_console, to_mono, update_manifest, write_wav16)

setup_console()

SRC = REPO / "music" / "Фоновые"
OUT = REPO / "music" / "Готовое" / "music"
MANIFEST = REPO / "assets" / "audio" / "MANIFEST.csv"

# Ключи из src/shared/Config/Islands.luau — там они уже прописаны, а в реестре ещё нет.
ISLAND_KEYS = {
    1: ("mus_island1_shore", "Поющий берег"),
    2: ("mus_island2_hills", "Мягкие холмы"),
    3: ("mus_island3_valley", "Стучащая долина"),
}

# Музыка тише озвучки: на -22.1 LUFS стоит голос, музыке оставляем запас,
# иначе при дакинге до 30 % она всё равно будет лезть вперёд.
TARGET_LUFS = -23.0
CEILING_DBFS = -3.0
HPF_HZ = 45.0          # ниже этого планшет не играет, а энергию полоса ест
LOOP_TARGET = 75.0     # середина требуемых доком 60–90 с
CROSSFADE = 0.25       # сшивка шва, с

VO_BAND = (100.0, 500.0)   # где живёт голос диктора
BANDS = [(0, 60), (60, 100), (100, 500), (500, 2000), (2000, 8000), (8000, 24000)]


# ─────────────────────────── анализ ───────────────────────────


def onset_envelope(mono: np.ndarray, sr: int) -> tuple[np.ndarray, float]:
    """Спектральный поток: по нему ищется темп. Возвращает огибающую и её частоту."""
    n_fft, hop = 1024, 512
    frames = 1 + (mono.size - n_fft) // hop
    if frames < 4:
        return np.zeros(0), sr / hop
    idx = np.arange(n_fft)[None, :] + hop * np.arange(frames)[:, None]
    win = np.hanning(n_fft)
    spec = np.abs(np.fft.rfft(mono[idx] * win, axis=1))
    flux = np.diff(spec, axis=0)
    flux = np.maximum(flux, 0).sum(axis=1)  # только нарастание — это и есть атаки
    if flux.size and flux.std() > 0:
        flux = (flux - flux.mean()) / flux.std()
    return flux, sr / hop


def detect_bpm(mono: np.ndarray, sr: int) -> float:
    """Темп по автокорреляции огибающей атак. Диапазон 60–200 BPM."""
    env, fps = onset_envelope(mono, sr)
    if env.size < 16:
        return 0.0
    ac = np.correlate(env, env, mode="full")[env.size - 1:]
    lo, hi = int(fps * 60 / 200), int(fps * 60 / 60)
    hi = min(hi, ac.size - 1)
    if hi <= lo:
        return 0.0
    lag = int(np.argmax(ac[lo:hi])) + lo
    return 60.0 * fps / lag if lag else 0.0


def usable_region(mono: np.ndarray, sr: int) -> tuple[int, int]:
    """
    Границы «рабочей» части: без вступления из тишины и без финального затухания.
    Suno почти всегда доводит хвост до нуля, и луп через него звучит как провал.
    """
    w = int(0.25 * sr)
    if mono.size < w * 4:
        return 0, mono.size
    pad = (-mono.size) % w
    env = np.sqrt((np.pad(mono, (0, pad)) ** 2).reshape(-1, w).mean(axis=1))
    med = float(np.median(env))
    if med <= 0:
        return 0, mono.size
    strong = np.flatnonzero(env > med * 0.5)
    if strong.size == 0:
        return 0, mono.size
    return int(strong[0] * w), int(min(mono.size, (strong[-1] + 1) * w))


def loop_seam_score(mono: np.ndarray, start: int, length: int, fade: int) -> float:
    """
    Насколько похожи материал в начале лупа и тот, что придёт ему на смену.
    Единица — идеальное совпадение, около нуля — шов будет слышен.
    """
    a = mono[start: start + fade]
    b = mono[start + length: start + length + fade]
    if a.size != b.size or a.size == 0:
        return -1.0
    na, nb = np.linalg.norm(a), np.linalg.norm(b)
    if na == 0 or nb == 0:
        return -1.0
    return float(np.dot(a, b) / (na * nb))


def choose_loop(mono: np.ndarray, sr: int, bpm: float, target: float,
                fade: int) -> tuple[int, int, float]:
    """
    Подбирает начало и длину лупа. Длина — целое число тактов, чтобы доля
    не разъезжалась на стыке; из всех вариантов берётся тот, у которого шов
    сходится лучше всего.

    После выбора такта длина ещё подгоняется по сэмплам: одного такта мало,
    чтобы волны совпали по фазе, а на кроссфейде расхождение слышно как
    провал громкости.
    """
    lo, hi = usable_region(mono, sr)
    span = hi - lo
    if span <= fade * 2:
        return 0, mono.size, -1.0

    bar = (4 * 60.0 / bpm) if bpm > 0 else 2.0
    bar_n = max(1, int(round(bar * sr)))
    max_len = span - fade

    # Держимся коридора 55–95 с, но короткому треку разрешаем луп покороче,
    # иначе для него не найдётся ни одного варианта вовсе.
    len_lo = min(int(55 * sr), int(max_len * 0.5))
    len_hi = max_len

    # Длину поощряем: короткий луп сходится легче, но за сеанс повторится столько
    # раз, что надоест сильнее, чем неидеальный стык.
    def rank(length: int, seam: float) -> float:
        return seam + 0.35 * min(length / (target * sr), 1.0)

    best = (lo, min(int(target * sr), max_len), -2.0)
    best_rank = -9.0
    for bars in range(1, int(max_len / bar_n) + 1):
        length = bars * bar_n
        if length < len_lo or length > len_hi or length < sr * 4:
            continue
        for k in range(0, 33):                      # до 32 тактов вступления
            start = lo + k * bar_n
            if start + length + fade > hi:
                break
            s = loop_seam_score(mono, start, length, fade)
            if rank(length, s) > best_rank:
                best, best_rank = (start, length, s), rank(length, s)

    start, length, score = best
    if score <= -2.0:
        # Тактовая сетка ничего не дала — берём рабочую часть целиком.
        length = max_len
        score = loop_seam_score(mono, lo, length, fade)
        start = lo

    # подгонка длины по сэмплам: ищем сдвиг, при котором волны совпадают
    win = min(fade, 4096)
    a = mono[start: start + win]
    if a.size == win and np.linalg.norm(a) > 0:
        span_search = min(bar_n // 2, sr // 4)
        best_shift, best_corr = 0, score
        for shift in range(-span_search, span_search + 1, 16):
            L = length + shift
            if L < len_lo or start + L + fade > hi:
                continue
            b = mono[start + L: start + L + win]
            if b.size != win:
                continue
            nb = np.linalg.norm(b)
            if nb == 0:
                continue
            c = float(np.dot(a, b) / (np.linalg.norm(a) * nb))
            if c > best_corr:
                best_shift, best_corr = shift, c
        if best_shift:
            length += best_shift
            score = loop_seam_score(mono, start, length, fade)
    return start, length, score


def make_loop(x: np.ndarray, start: int, length: int, fade: int) -> np.ndarray:
    """
    Вырезает луп и сшивает его равномощным кроссфейдом: хвост длиной fade
    вливается в голову, поэтому переход с последнего сэмпла на нулевой
    оказывается непрерывным.
    """
    seg = x[start: start + length + fade]
    if seg.shape[0] < length + fade:
        return x[start: start + length]
    out = seg[:length].copy()
    t = np.linspace(0.0, 1.0, fade)[:, None]
    rise, fall = np.sin(t * math.pi / 2), np.cos(t * math.pi / 2)
    out[:fade] = out[:fade] * rise + seg[length: length + fade] * fall
    return out


def highpass(x: np.ndarray, sr: int, hz: float) -> np.ndarray:
    sos = butter(2, hz / (sr / 2), btype="highpass", output="sos")
    return sosfiltfilt(sos, x, axis=0)


# ─────────────────────────── основной проход ───────────────────────────


def island_of(stem: str) -> int | None:
    m = re.match(r"^Остров\s*(\d+)\s*[_-]", stem, re.IGNORECASE)
    return int(m.group(1)) if m else None


def main() -> int:
    ap = argparse.ArgumentParser(description="Подготовка фоновой музыки для Roblox")
    ap.add_argument("--src", type=Path, default=SRC)
    ap.add_argument("--out", type=Path, default=OUT)
    ap.add_argument("--manifest", type=Path, default=MANIFEST)
    ap.add_argument("--target", type=float, default=TARGET_LUFS)
    ap.add_argument("--ceiling", type=float, default=CEILING_DBFS)
    ap.add_argument("--loop", type=float, default=LOOP_TARGET, help="желаемая длина лупа, с")
    ap.add_argument("--hpf", type=float, default=HPF_HZ, help="срез инфраниза, Гц")
    ap.add_argument("--pick", action="append", default=[], metavar="ОСТРОВ=ФАЙЛ",
                    help="выбрать трек вручную, например --pick 2=Остров2_1")
    ap.add_argument("--check", action="store_true", help="только измерить, ничего не писать")
    args = ap.parse_args()

    if not args.src.is_dir():
        print(f"нет папки с музыкой: {rel(args.src)}", file=sys.stderr)
        return 1
    files = sorted(p for p in args.src.iterdir() if p.suffix.lower() == ".wav")
    if not files:
        print(f"в {rel(args.src)} нет wav-файлов", file=sys.stderr)
        return 1

    forced: dict[int, str] = {}
    for item in args.pick:
        if "=" not in item:
            print(f"--pick ждёт вид ОСТРОВ=ФАЙЛ, получено: {item}", file=sys.stderr)
            return 1
        n, name = item.split("=", 1)
        forced[int(n)] = name.strip()

    print(f"Читаю {len(files)} треков из {rel(args.src)}\n")
    tracks = []
    for i, path in enumerate(files, 1):
        x, sr = read_wav(path)
        mono = to_mono(x)
        bpm = detect_bpm(mono, sr)
        fade = int(CROSSFADE * sr)
        start, length, seam = choose_loop(mono, sr, bpm, args.loop, fade)
        bands = band_energy(x, sr, BANDS)
        tracks.append(dict(path=path, stem=path.stem, x=x, sr=sr, mono=mono,
                           dur=mono.size / sr, bpm=bpm, lufs=loudness_lufs(x, sr),
                           peak=peak_db(x), bands=bands, vo_band=bands[2],
                           sub=bands[0], start=start, length=length, seam=seam,
                           island=island_of(path.stem)))
        print(f"\r  разобрано {i}/{len(files)}", end="", flush=True)
    print("\n")

    print(f"{'трек':<26}{'сек':>6}{'BPM':>6}{'LUFS':>7}{'<60Гц':>7}"
          f"{'100-500':>9}{'луп':>7}{'шов':>7}")
    for t in tracks:
        print(f"{t['stem'][:26]:<26}{t['dur']:>6.0f}{t['bpm']:>6.0f}{t['lufs']:>7.1f}"
              f"{t['sub']:>6.1f}%{t['vo_band']:>8.1f}%{t['length'] / t['sr']:>7.0f}"
              f"{t['seam']:>7.2f}")

    print("\n«100-500» — доля энергии в полосе голоса: чем меньше, тем меньше музыка "
          "глушит букву.\n«шов» — сходимость лупа: выше 0.3 стык не слышен, ниже 0.1 "
          "заметен.")

    # ── выбор трека на остров ──
    print("\n\nВЫБОР ТРЕКА НА ОСТРОВ\n")
    chosen: dict[int, dict] = {}
    for island in sorted(ISLAND_KEYS):
        key, title = ISLAND_KEYS[island]
        cands = [t for t in tracks if t["island"] == island]
        if not cands:
            print(f"  остров {island} «{title}»: кандидатов нет "
                  f"(нужен файл вида Остров{island}_1.wav)")
            continue

        if island in forced:
            # вручную можно взять любой трек папки, не только именованный по острову
            pick = next((t for t in tracks if t["stem"] == forced[island]), None)
            if pick is None:
                print(f"  остров {island}: файла «{forced[island]}» нет в папке", file=sys.stderr)
                return 1
            reason = "выбран вручную"
        else:
            # Шов весит больше полосы: разница в пару процентов почти не слышна,
            # а слышимый стык повторяется каждую минуту весь сеанс.
            def score(t: dict) -> float:
                return (t["seam"] * 20.0
                        - t["vo_band"] * 1.0
                        + min(t["length"] / t["sr"] / args.loop, 1.0) * 10.0)
            pick = max(cands, key=score)
            others = [c for c in cands if c is not pick]
            if others and pick["seam"] > others[0]["seam"] + 0.1:
                reason = "заметно чище сходится луп"
            elif others and pick["vo_band"] < others[0]["vo_band"]:
                reason = "меньше лезет в полосу голоса"
            else:
                reason = "лучший по сумме признаков"

        chosen[island] = pick
        alts = ", ".join(f"{c['stem']} ({c['vo_band']:.1f}%)" for c in cands if c is not pick)
        print(f"  остров {island} «{title}» → {pick['stem']}  "
              f"[{pick['vo_band']:.1f}% в полосе голоса, шов {pick['seam']:.2f}] — {reason}")
        if alts:
            print(f"      не взят: {alts}")

    if not chosen:
        print("\nНи одного трека не выбрано — переименуй файлы в вид «Остров1_1.wav»",
              file=sys.stderr)
        return 1

    # ── сборка ──
    print("\n\nСБОРКА ЛУПОВ\n")
    print(f"{'ключ':<22}{'из':<18}{'сек':>6}{'сдвиг':>8}{'LUFS':>7}{'пик':>7}")
    rows = []
    short: list[tuple[str, float, str]] = []
    for island in sorted(chosen):
        key, _ = ISLAND_KEYS[island]
        t = chosen[island]
        fade = int(CROSSFADE * t["sr"])
        y = make_loop(t["x"], t["start"], t["length"], fade)
        y = highpass(y, t["sr"], args.hpf)

        lufs = loudness_lufs(y, t["sr"])
        gain = args.target - lufs
        y = y * (10 ** (gain / 20))

        top = float(np.abs(y).max(initial=0.0))
        ceil_lin = 10 ** (args.ceiling / 20)
        if top > ceil_lin:            # музыке лимитер не нужен, хватает статики
            y *= ceil_lin / top
        out_lufs, out_peak = loudness_lufs(y, t["sr"]), peak_db(y)

        secs = y.shape[0] / t["sr"]
        note = ""
        if secs < 55:
            note = "  ← короче 60 с, док просит 60–90"
            short.append((key, secs, t["stem"]))
        if t["seam"] < 0.15:
            note += "  ← шов может быть слышен"
        print(f"{key:<22}{t['stem'][:18]:<18}{secs:>6.0f}"
              f"{gain:>+8.1f}{out_lufs:>7.1f}{out_peak:>7.1f}{note}")

        if not args.check:
            dst = args.out / f"{key}.wav"
            write_wav16(dst, y, t["sr"])
            rows.append(dict(key=key, file=f"{key}.wav", sec=f"{y.shape[0] / t['sr']:.2f}",
                             lufs=f"{out_lufs:.1f}", peak_dbfs=f"{out_peak:.1f}",
                             sha1=hashlib.sha1(dst.read_bytes()).hexdigest()[:12]))

    if args.check:
        print("\n--check: файлы не записаны")
        return 0

    total = sum((args.out / r["file"]).stat().st_size for r in rows)
    print(f"\nЗаписано {len(rows)} лупов в {rel(args.out)} ({total / 1048576:.1f} МБ, "
          f"стерео 16 бит)")

    count, kept = update_manifest(args.manifest, rows)
    print(f"Манифест: {rel(args.manifest)}, всего строк {count}"
          + (f", сохранено {kept} проставленных assetId" if kept else ""))
    print("\nДальше: ключи mus_island* надо завести в AudioRegistry.luau — "
          "сейчас они есть только в Islands.luau")
    return 0


if __name__ == "__main__":
    sys.exit(main())
