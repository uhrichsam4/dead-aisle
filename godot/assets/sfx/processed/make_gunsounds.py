#!/usr/bin/env python3
"""Builds the layered gunfire in this folder from the project's own takes
(assets/sfx/gun_shot_1..6.mp3, gun_charge_*, gun_magin_*). No outside audio.

  shot_close_N.wav    mono  - the dry crack: transient-shaped, thumped, saturated,
                              with a bolt-carrier clack under it
  tail_out_N.wav      stereo - wet only: slapbacks off buildings 80-400 ms and a
                              rolling low-passed decay (~1.8 s)
  tail_in_N.wav       stereo - wet only: dense early reflections, boxy, ~0.7 s
  shot_distant_N.wav  mono  - heavily low-passed boom plus its echo, for 3D
  ring.wav            mono  - a faint ear-ring, played very low after sustained fire

Run: python3 make_gunsounds.py   (needs ffmpeg, numpy, scipy)
"""
import os
import subprocess

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, fftconvolve, lfilter, sosfilt

SR = 48000
HERE = os.path.dirname(os.path.abspath(__file__))
SFX = os.path.dirname(HERE)
FFMPEG = "/opt/homebrew/bin/ffmpeg"
rng = np.random.default_rng(1974)


def load(name):
    raw = subprocess.run([FFMPEG, "-v", "error", "-i", os.path.join(SFX, name), "-f", "f32le",
                          "-ac", "1", "-ar", str(SR), "-"], check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64)


def trim_onset(x, rel=0.12, pre_ms=1.5):
    i = int(np.argmax(np.abs(x) > rel * np.max(np.abs(x))))
    return x[max(0, i - int(pre_ms * SR / 1000)):]


def hp(x, f, order=2):
    return sosfilt(butter(order, f, "highpass", fs=SR, output="sos"), x, axis=0)


def lp(x, f, order=2):
    return sosfilt(butter(order, f, "lowpass", fs=SR, output="sos"), x, axis=0)


def bp(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo, hi], "bandpass", fs=SR, output="sos"), x, axis=0)


def peaking(x, f0, gain_db, q):
    """RBJ peaking EQ."""
    a = 10 ** (gain_db / 40)
    w0 = 2 * np.pi * f0 / SR
    alpha = np.sin(w0) / (2 * q)
    b = [1 + alpha * a, -2 * np.cos(w0), 1 - alpha * a]
    den = [1 + alpha / a, -2 * np.cos(w0), 1 - alpha / a]
    return lfilter(np.array(b) / den[0], np.array(den) / den[0], x, axis=0)


def fade(x, fade_in_ms=0.0, fade_out_ms=0.0):
    x = x.copy()
    n = len(x)
    if fade_in_ms > 0:
        k = min(n, int(fade_in_ms * SR / 1000))
        x[:k] = (x[:k].T * np.linspace(0, 1, k)).T
    if fade_out_ms > 0:
        k = min(n, int(fade_out_ms * SR / 1000))
        x[n - k:] = (x[n - k:].T * np.cos(np.linspace(0, np.pi / 2, k)) ** 2).T
    return x


def fit(x, seconds):
    n = int(seconds * SR)
    if len(x) >= n:
        return x[:n]
    pad = np.zeros((n - len(x),) + x.shape[1:])
    return np.concatenate([x, pad])


def save(name, x, peak_db=-1.0):
    """peak_db None keeps the level (already limited) and only guards clipping."""
    x = x - np.mean(x, axis=0)
    if peak_db is None:
        x = x / max(1.0, np.max(np.abs(x)) / 0.89)
        peak_db = round(20 * np.log10(np.max(np.abs(x))), 1)
    else:
        x = x / (np.max(np.abs(x)) + 1e-12) * 10 ** (peak_db / 20)
    wavfile.write(os.path.join(HERE, name), SR, (x * 32767).astype(np.int16))
    print(f"{name}: {len(x) / SR:.2f}s peak {peak_db} dBFS")


def decaying_noise(n, rt60, delay_s, chans=2):
    t = np.arange(n) / SR
    env = np.exp(-6.91 * np.maximum(t - delay_s, 0) / rt60) * (t >= delay_s)
    return (rng.standard_normal((n, chans)).T * env).T


def burst(ms, chans=2):
    n = int(ms * SR / 1000)
    return (rng.standard_normal((n, chans)).T * np.exp(-np.arange(n) / (n / 4))).T


# ------------------------------------------------------------------ sources
shots = [trim_onset(load(f"gun_shot_{i}.mp3")) for i in range(1, 7)]
mechs = []
for name in ["gun_charge_1.mp3", "gun_charge_2.mp3", "gun_charge_3.mp3",
             "gun_magin_1.mp3", "gun_magin_2.mp3"]:
    m = load(name)
    pk = int(np.argmax(np.abs(m)))
    seg = m[max(0, pk - int(0.002 * SR)): pk + int(0.06 * SR)]
    mechs.append(fade(hp(seg, 1400), 0.5, 25) / (np.max(np.abs(seg)) + 1e-12))


# ------------------------------------------------------------------ close
def close_shot(src, k):
    x = fit(src, 0.52)
    x = hp(x, 32)
    t = np.arange(len(x)) / SR
    # chest thump: the low band of the first ~60 ms pushed up
    low = lp(x, 170, 4) * np.exp(-t / 0.045)
    # the crack: the top of the first few ms, sharpened
    crack = hp(x, 2500, 2) * np.exp(-t / 0.004)
    x = x + 1.1 * low + 0.9 * crack
    # transient shaping: the first 12 ms stand proud of the body
    x *= 1.0 + 0.8 * np.exp(-t / 0.012)
    # the body sits under the crack, pulled down faster than the source did
    x *= np.exp(-np.maximum(t - 0.05, 0) / 0.16) * 0.7 + 0.3 * np.exp(-t / 0.35)
    # density: soft saturation, the recorder's preamp clipping on a shot
    x = x / np.max(np.abs(x))
    x = np.tanh(2.6 * x) / np.tanh(2.6)
    # the mechanical layer: bolt carrier slamming, a few ms after the crack
    m = mechs[k % len(mechs)]
    off = int(rng.uniform(0.006, 0.016) * SR)
    x[off:off + len(m)] += 0.22 * m[: len(x) - off]
    x = peaking(x, 3200, 2.5, 0.9)   # presence
    # loudness-match the takes on their first 100 ms, then limit the peaks,
    # so no variant jumps out of a burst
    rms = np.sqrt(np.mean(x[: SR // 10] ** 2))
    x = x * (10 ** (-9.0 / 20) / rms)
    x = np.tanh(x / 0.89) * 0.89
    return fade(x, 0, 140)


for i, s in enumerate(shots):
    save(f"shot_close_{i + 1}.wav", close_shot(s, i), None)


# ------------------------------------------------------------------ outdoor
def outdoor_ir(seconds=1.9):
    n = int(seconds * SR)
    ir = np.zeros((n, 2))
    # rolling diffuse decay: lows hang longest, highs die first
    for lo, hi, rt in [(None, 350, 2.1), (350, 1800, 1.4), (1800, 5000, 0.55)]:
        nz = decaying_noise(n, rt, 0.045)
        nz = lp(nz, hi) if lo is None else bp(nz, lo, hi)
        ir += nz
    ir = fade(ir, 0, 0)
    t = np.arange(n) / SR
    ir = (ir.T * np.clip((t - 0.045) / 0.12, 0, 1)).T          # slow bloom
    # rolling: the decay swells and sags as it comes back off different walls
    roll = lp(rng.standard_normal((n, 2)), 3.0, 2)
    roll = roll / (np.max(np.abs(roll)) + 1e-12)
    ir *= 1.0 + 0.55 * roll
    ir *= 0.45
    # slapbacks off buildings
    delays = np.sort(rng.uniform(0.08, 0.40, 5))
    gains = np.linspace(1.0, 0.35, 5) * rng.uniform(0.7, 1.0, 5)
    for d, g in zip(delays, gains):
        for c in range(2):
            dd = int((d + rng.uniform(-0.004, 0.004)) * SR)
            b = lp(burst(rng.uniform(8, 22), 1)[:, 0], 2600)
            pan = rng.uniform(0.5, 1.0) if (c == 0) == (rng.random() < 0.5) else rng.uniform(0.25, 0.6)
            ir[dd:dd + len(b), c] += 3.2 * g * pan * b[: n - dd]
    ir = lp(hp(ir, 60), 3800)
    return fade(ir, 0, 300)


def tail(src, ir, seconds, lowpass):
    dry = fade(fit(src, 0.22), 0, 40)
    wet = np.stack([fftconvolve(dry, ir[:, c]) for c in range(2)], axis=1)
    wet = lp(wet, lowpass)
    return fade(fit(wet, seconds), 2, 350)


out_irs = []
for i in range(4):
    ir = outdoor_ir()
    out_irs.append(ir)
    save(f"tail_out_{i + 1}.wav", tail(shots[(i * 2 + 1) % 6], ir, 2.0, 3200))


# ------------------------------------------------------------------ indoor
def indoor_ir(seconds=0.75):
    n = int(seconds * SR)
    ir = decaying_noise(n, rng.uniform(0.5, 0.65), 0.004) * 0.6
    # dense early reflections off shelving, floor, a low ceiling
    for _ in range(40):
        d = rng.uniform(0.002, 0.038)
        g = rng.uniform(0.3, 1.0) * np.exp(-d / 0.025) * rng.choice([-1, 1])
        dd = int(d * SR)
        ir[dd, int(rng.integers(0, 2))] += 2.4 * g
    # a faint flutter between two parallel walls
    per = rng.uniform(0.009, 0.013)
    for k in range(1, 14):
        dd = int(k * per * SR)
        if dd < n:
            ir[dd, :] += 0.9 * 0.78 ** k
    ir = hp(ir, 90)
    ir = peaking(ir, rng.uniform(260, 380), 7.0, 1.1)   # boxy
    ir = peaking(ir, 1100, 2.0, 1.5)
    ir = lp(ir, 5200)
    return fade(ir, 0, 120)


for i in range(4):
    save(f"tail_in_{i + 1}.wav", tail(shots[(i * 2) % 6], indoor_ir(), 0.8, 6000))


# ------------------------------------------------------------------ distant
for i in range(3):
    src = fit(shots[(i * 2 + 1) % 6], 0.4)
    direct = lp(lp(hp(src, 45), 650, 4), 900)
    direct = fade(direct, 0, 200)
    ir = out_irs[i].mean(axis=1)
    echo = lp(fftconvolve(fade(fit(src, 0.22), 0, 40), ir), 1400, 4)
    n = int(2.2 * SR)
    x = fit(direct * 1.0, 2.2) + 0.55 * fit(echo, 2.2) / (np.max(np.abs(echo)) + 1e-12) * np.max(np.abs(direct))
    x = np.tanh(1.6 * x / np.max(np.abs(x)))
    save(f"shot_distant_{i + 1}.wav", fade(x, 1, 500))


# ------------------------------------------------------------------ ear ring
n = int(1.8 * SR)
t = np.arange(n) / SR
ring = np.sin(2 * np.pi * 3950 * t) + 0.5 * np.sin(2 * np.pi * 4110 * t + 1.0)
ring *= np.clip(t / 0.25, 0, 1) * np.exp(-t / 0.7)
save("ring.wav", fade(ring, 0, 300), -6.0)
