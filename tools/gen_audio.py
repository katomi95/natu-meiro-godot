"""夏迷路：プログラム合成の環境音を WAV に書き出す。

Web版(three.js)では Web Audio で実時間合成していた音を、
Godot（特にWeb書き出し）で確実に鳴らすため事前にファイル化する。

    python tools/gen_audio.py
"""
import os
import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "audio", "synth")
rng = np.random.default_rng(1234)


def save(name, x, peak=0.9):
    x = np.asarray(x, dtype=np.float64)
    m = np.max(np.abs(x)) + 1e-9
    x = x / m * peak
    wavfile.write(os.path.join(OUT, name + ".wav"), SR, (x * 32767).astype(np.int16))
    print(name, f"{len(x) / SR:.1f}s")


def pink(n):
    w = rng.standard_normal(n)
    b, a = [0.049922035, -0.095993537, 0.050612699, -0.004408786], [1, -2.494956002, 2.017265875, -0.522189400]
    return signal.lfilter(b, a, w)


def brown(n):
    x = np.cumsum(rng.standard_normal(n))
    return signal.filtfilt(*signal.butter(1, 20 / (SR / 2), "high"), x)


def bp(x, lo, hi, order=2):
    return signal.sosfilt(signal.butter(order, [lo / (SR / 2), hi / (SR / 2)], "band", output="sos"), x)


def lp(x, f, order=2):
    return signal.sosfilt(signal.butter(order, f / (SR / 2), "low", output="sos"), x)


def hp(x, f, order=2):
    return signal.sosfilt(signal.butter(order, f / (SR / 2), "high", output="sos"), x)


def loopify(x, fade=1.0):
    """末尾を先頭にクロスフェードして継ぎ目の無いループにする"""
    f = int(fade * SR)
    head, body, tail = x[:f], x[f:-f], x[-f:]
    t = np.linspace(0, 1, f)
    mixed = tail * np.cos(t * np.pi / 2) + head * np.sin(t * np.pi / 2)
    return np.concatenate([body, mixed])


def env_ad(n, a, d):
    t = np.arange(n) / SR
    return np.minimum(t / a, 1.0) * np.exp(-np.maximum(t - a, 0) / d)


def lfo(n, rate, depth, phase=0.0):
    t = np.arange(n) / SR
    return 1.0 - depth + depth * (0.5 + 0.5 * np.sin(2 * np.pi * rate * t + phase))


# ---- 雨（ループ） ----
def rain():
    n = SR * 10
    hiss = bp(rng.standard_normal(n), 1200, 7000)
    low = lp(pink(n), 900) * 0.8
    drops = np.zeros(n)
    for _ in range(900):
        i = rng.integers(0, n - 400)
        L = rng.integers(60, 300)
        drops[i:i + L] += rng.standard_normal(L) * np.exp(-np.arange(L) / (L / 5)) * rng.uniform(0.2, 1.0)
    drops = bp(drops, 1500, 6000)
    x = hiss + low + drops * 0.8
    x *= lfo(n, 0.11, 0.25)
    save("rain_loop", loopify(x), 0.8)


# ---- 風（ループ） ----
def wind():
    n = SR * 12
    x = pink(n)
    # ゆっくり変わるローパス
    out = np.zeros(n)
    blk = 512
    zi = None
    for s in range(0, n, blk):
        f = 520 + 280 * np.sin(2 * np.pi * 0.07 * s / SR) + 120 * np.sin(2 * np.pi * 0.19 * s / SR)
        sos = signal.butter(2, f / (SR / 2), "low", output="sos")
        if zi is None:
            zi = signal.sosfilt_zi(sos) * 0
        out[s:s + blk], zi = signal.sosfilt(sos, x[s:s + blk], zi=zi)
    out *= lfo(n, 0.09, 0.55) * lfo(n, 0.23, 0.2, 1.0)
    save("wind_loop", loopify(out, 1.5), 0.8)


# ---- 突風（ワンショット） ----
def gust():
    n = int(SR * 5)
    x = bp(pink(n), 150, 2500)
    t = np.arange(n) / SR
    e = np.sin(np.pi * np.clip(t / 5.0, 0, 1)) ** 1.5
    save("gust", x * e, 0.9)


# ---- 人のざわめき（ループ） ----
def crowd():
    n = SR * 12
    x = np.zeros(n)
    for k in range(6):
        v = bp(pink(n), 250 + k * 60, 1600 + k * 150)
        v *= lfo(n, rng.uniform(0.3, 1.1), 0.7, rng.uniform(0, 6))
        x += v
    # 話し声っぽい断片（フォルマント付きの短い声）
    for _ in range(140):
        L = int(rng.uniform(0.08, 0.35) * SR)
        i = rng.integers(0, n - L)
        t = np.arange(L) / SR
        f0 = rng.uniform(140, 320)
        src = signal.sawtooth(2 * np.pi * f0 * t * (1 + 0.05 * np.sin(2 * np.pi * 5 * t)))
        v = bp(src, rng.uniform(400, 700), rng.uniform(1100, 2400))
        x[i:i + L] += v * np.sin(np.pi * t / t[-1]) * rng.uniform(0.05, 0.25)
    save("crowd_loop", loopify(lp(x, 3000)), 0.8)


# ---- 雷 ----
def thunder(near):
    n = SR * 7
    t = np.arange(n) / SR
    rumble = lp(brown(n), 180 if near else 110, 3)
    rumble *= np.exp(-t / (2.2 if near else 2.8)) * (0.6 + 0.4 * lp(np.abs(rng.standard_normal(n)), 3))
    x = rumble
    if near:
        L = int(0.5 * SR)
        crack = hp(rng.standard_normal(L), 400) * np.exp(-np.arange(L) / (0.08 * SR))
        x[:L] += crack * 0.9
        # 二次の破裂
        i = int(0.25 * SR)
        x[i:i + L] += lp(rng.standard_normal(L), 2500) * np.exp(-np.arange(L) / (0.15 * SR)) * 0.5
    else:
        x = np.concatenate([np.zeros(int(0.3 * SR)), x])[:n]
    x *= np.minimum(t / 0.02, 1)
    save("thunder_near" if near else "thunder_far", x, 0.95)


# ---- 足音 ----
def steps():
    L = int(0.16 * SR)
    t = np.arange(L) / SR
    dirt = lp(rng.standard_normal(L), 1400) * np.exp(-t / 0.025) + lp(brown(L), 300) * np.exp(-t / 0.04) * 0.4
    save("step_dirt", dirt, 0.8)
    L2 = int(0.28 * SR)
    t2 = np.arange(L2) / SR
    grass = bp(rng.standard_normal(L2), 2000, 7000) * (np.exp(-t2 / 0.06) * (0.6 + 0.4 * rng.random(L2)))
    save("step_grass", grass, 0.7)
    # 濡れたアスファルト
    wet = bp(rng.standard_normal(L), 700, 5000) * np.exp(-t / 0.03) + lp(rng.standard_normal(L), 600) * np.exp(-t / 0.05) * 0.5
    save("step_wet", wet, 0.8)


# ---- アブラゼミ（最後に遠くで一匹だけ） ----
def aburazemi():
    n = SR * 9
    t = np.arange(n) / SR
    x = bp(rng.standard_normal(n), 3200, 7200, 3)
    am = 0.55 + 0.45 * np.sign(np.sin(2 * np.pi * 58 * t))  # ジジジ…の細かな断続
    x *= lp(am, 400)
    # 鳴き始め・鳴き終わりの山
    e = np.clip(t / 1.2, 0, 1) * np.clip((9 - t) / 2.5, 0, 1)
    e *= 0.8 + 0.2 * np.sin(2 * np.pi * 0.6 * t)
    save("cicada_solo", x * e, 0.8)


# ---- ヒグラシ（カナカナカナ…） ----
def higurashi():
    n = int(SR * 4.2)
    x = np.zeros(n)
    k = 0
    pos = 0.05
    while pos < 3.8:
        L = int(0.11 * SR)
        t = np.arange(L) / SR
        f = 4700 - k * 35 + 900 * np.exp(-t / 0.02)
        ph = 2 * np.pi * np.cumsum(f) / SR
        chirp = np.sin(ph) * (1 + 0.6 * np.sin(2 * np.pi * 190 * t))
        amp = np.exp(-k * 0.09) * (1 if k > 0 else 0.7)
        e = np.sin(np.pi * t / t[-1]) ** 0.6
        i = int(pos * SR)
        x[i:i + L] += chirp * e * amp
        pos += 0.165 + k * 0.004
        k += 1
    x = bp(x, 2500, 8000)
    save("higurashi", x, 0.8)


# ---- 鳥（遠くのさえずり） ----
def bird():
    n = int(SR * 1.2)
    x = np.zeros(n)
    pos = 0.02
    for k in range(rng.integers(3, 6)):
        L = int(rng.uniform(0.06, 0.12) * SR)
        t = np.arange(L) / SR
        f0 = rng.uniform(2800, 4200)
        f = f0 + rng.uniform(-1500, 1500) * (t / t[-1])
        ph = 2 * np.pi * np.cumsum(f) / SR
        i = int(pos * SR)
        if i + L >= n:
            break
        x[i:i + L] += np.sin(ph) * np.sin(np.pi * t / t[-1])
        pos += L / SR + rng.uniform(0.03, 0.12)
    save("bird", x, 0.7)


# ---- 虫（草むらのチッチッ） ----
def insect():
    n = int(SR * 1.0)
    x = np.zeros(n)
    for k in range(6):
        L = int(0.035 * SR)
        t = np.arange(L) / SR
        i = int((0.05 + k * 0.12) * SR)
        x[i:i + L] += np.sin(2 * np.pi * 5200 * t) * np.sin(np.pi * t / t[-1]) * (1 - k * 0.1)
    save("insect", x, 0.6)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    rain(); wind(); gust(); crowd(); thunder(True); thunder(False)
    steps(); bird(); insect()
    # aburazemi() / higurashi() は実素材（ポケットサウンド）に差し替えたため未使用
