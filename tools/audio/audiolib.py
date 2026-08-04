#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Общий слой для скриптов подготовки аудио: чтение/запись wav, громкость по
ITU-R BS.1770-4, вспомогательная мелочь.

Отдельным модулем, потому что и озвучка, и музыка меряются одной линейкой —
иначе они разъедутся по громкости, а это ровно то, с чем мы боремся.
"""

from __future__ import annotations

import csv
import math
import sys
import wave
from pathlib import Path

import numpy as np
from scipy.signal import lfilter

REPO = Path(__file__).resolve().parents[2]


def setup_console() -> None:
    """Windows-консоль иначе роняет вывод на кириллице."""
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")


def rel(path: Path) -> str:
    """Путь для вывода: короткий внутри репозитория, полный — снаружи."""
    try:
        return str(path.resolve().relative_to(REPO))
    except ValueError:
        return str(path)


def db(x: float) -> float:
    return -99.0 if x <= 1e-12 else 20.0 * math.log10(x)


# ─────────────────────────── чтение и запись ───────────────────────────


def read_wav(path: Path) -> tuple[np.ndarray, int]:
    """
    Возвращает массив (кадры, каналы) во float64 [-1, 1] и частоту дискретизации.
    Моно тоже приходит двумерным — так вызывающий код не обрастает ветвлениями.
    """
    with wave.open(str(path), "rb") as w:
        nch, sw, sr, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        raw = w.readframes(n)

    if sw == 1:
        data = (np.frombuffer(raw, dtype=np.uint8).astype(np.float64) - 128.0) / 128.0
    elif sw == 2:
        data = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
    elif sw == 3:
        b = np.frombuffer(raw, dtype=np.uint8).reshape(-1, 3).astype(np.int32)
        v = (b[:, 0] | (b[:, 1] << 8) | (b[:, 2] << 16)).astype(np.int32)
        v = np.where(v & 0x800000, v - 0x1000000, v)
        data = v.astype(np.float64) / 8388608.0
    elif sw == 4:
        data = np.frombuffer(raw, dtype="<i4").astype(np.float64) / 2147483648.0
    else:
        raise RuntimeError(f"{path.name}: разрядность {sw * 8} бит не поддерживается")

    return data.reshape(-1, nch), sr


def to_mono(x: np.ndarray) -> np.ndarray:
    return x.mean(axis=1) if x.ndim == 2 else x


def write_wav16(path: Path, x: np.ndarray, sr: int, seed: int = 0xA3BA) -> None:
    """
    Пишет 16 бит с TPDF-дизерингом — без него тихие хвосты гранулируются.
    Зерно фиксировано: повторный прогон даёт побайтово тот же файл.
    """
    if x.ndim == 1:
        x = x[:, None]
    rng = np.random.default_rng(seed)
    lsb = 1.0 / 32768.0
    dither = (rng.random(x.shape) - rng.random(x.shape)) * lsb
    y = np.clip(x + dither, -1.0, 1.0 - lsb)
    ints = np.clip(np.round(y * 32768.0), -32768, 32767).astype("<i2")

    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(x.shape[1])
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(ints.tobytes())


# ─────────────────────────── громкость ───────────────────────────


def k_weight(x: np.ndarray, sr: int) -> np.ndarray:
    """K-взвешивание BS.1770-4. Коэффициенты табличные для 48 кГц."""
    if sr != 48000:
        raise RuntimeError(f"K-взвешивание задано для 48 кГц, получено {sr}")
    # ступень 1: полочный фильтр головы слушателя
    s1 = lfilter([1.53512485958697, -2.69169618940638, 1.19839281085285],
                 [1.0, -1.69065929318241, 0.73248077421585], x, axis=0)
    # ступень 2: RLB-фильтр верхних частот
    return lfilter([1.0, -2.0, 1.0], [1.0, -1.99004745483398, 0.99007225036621], s1, axis=0)


def loudness_lufs(x: np.ndarray, sr: int) -> float:
    """
    Интегральная громкость по BS.1770-4 с двойным гейтом. Каналы суммируются
    с весами 1.0 (L/R), как требует стандарт.

    Для коротких фрагментов (реплика «п» длится 0.36 с) блоков в 400 мс не
    набирается вовсе; тогда честнее вернуть среднее по всему фрагменту, чем -inf.
    """
    if x.ndim == 1:
        x = x[:, None]
    if x.shape[0] == 0:
        return -99.0

    y = k_weight(x, sr)
    block, hop = int(0.400 * sr), int(0.100 * sr)  # перекрытие 75 %

    if y.shape[0] < block:
        ms = float(np.sum(np.mean(y ** 2, axis=0)))
        return -0.691 + 10.0 * math.log10(ms) if ms > 0 else -99.0

    starts = range(0, y.shape[0] - block + 1, hop)
    power = np.array([float(np.sum(np.mean(y[s:s + block] ** 2, axis=0))) for s in starts])
    power = np.where(power > 0, power, 1e-30)
    lj = -0.691 + 10.0 * np.log10(power)

    keep = lj > -70.0  # абсолютный гейт
    if not keep.any():
        return -99.0
    relative = -0.691 + 10.0 * math.log10(float(np.mean(power[keep]))) - 10.0
    keep &= lj > relative  # относительный гейт
    if not keep.any():
        return -99.0
    return -0.691 + 10.0 * math.log10(float(np.mean(power[keep])))


def peak_db(x: np.ndarray) -> float:
    return db(float(np.abs(x).max(initial=0.0)))


def update_manifest(path: Path, rows: list[dict]) -> tuple[int, int]:
    """
    Обновляет манифест по ключам, не трогая чужие строки.

    Озвучка и музыка живут в одном файле, но готовятся разными скриптами: если
    писать его целиком, второй скрипт затрёт работу первого. Уже проставленные
    вручную asset_id и дату загрузки сохраняем всегда — их набивает человек.
    """
    fields = ["key", "file", "sec", "lufs", "peak_dbfs", "sha1", "asset_id", "uploaded"]
    existing: dict[str, dict] = {}
    if path.exists():
        with path.open(encoding="utf-8", newline="") as f:
            for row in csv.DictReader(f):
                existing[row["key"]] = row

    kept = 0
    for row in rows:
        old = existing.get(row["key"], {})
        row.setdefault("asset_id", old.get("asset_id", ""))
        row.setdefault("uploaded", old.get("uploaded", ""))
        if row["asset_id"]:
            kept += 1
        existing[row["key"]] = row

    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        w.writeheader()
        for key in sorted(existing):
            w.writerow({k: existing[key].get(k, "") for k in fields})
    return len(existing), kept


def band_energy(x: np.ndarray, sr: int, bands: list[tuple[float, float]]) -> list[float]:
    """Доля энергии в каждой полосе, %. Считается по моно-сумме."""
    m = to_mono(x)
    if m.size == 0:
        return [0.0] * len(bands)
    n = min(m.size, sr * 60)  # минуты хватает, дальше только время жечь
    seg = m[:n] * np.hanning(n)
    p = np.abs(np.fft.rfft(seg)) ** 2
    fr = np.fft.rfftfreq(n, 1 / sr)
    tot = p.sum() or 1.0
    return [float(p[(fr >= lo) & (fr < hi)].sum() / tot * 100) for lo, hi in bands]
