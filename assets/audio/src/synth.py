"""Port of WebAudio synths from ball_territory_web/public/index.html (snd object) to numpy.
Usage: python -I synth.py OUT_DIR  -> writes raw_*.wav (44.1k mono float->16bit)."""
import sys, numpy as np
from scipy.signal import lfilter
from scipy.io import wavfile
SR = 44100
rng = np.random.default_rng(7)

def env(n, v, d_n):
    t = np.arange(n) / max(d_n, 1)
    return v * (0.0008 / v) ** t  # exponentialRamp v -> .0008

def tone(buf, f0, f1, d, v, typ="sine", at=0.0):
    n = int(d * SR); s = int(at * SR)
    f = f0 * (max(20, f1) / f0) ** (np.arange(n) / n)
    ph = 2 * np.pi * np.cumsum(f) / SR
    w = {"sine": np.sin(ph), "square": np.sign(np.sin(ph)),
         "triangle": 2 / np.pi * np.arcsin(np.sin(ph)),
         "sawtooth": 2 * ((ph / (2 * np.pi)) % 1) - 1}[typ]
    y = w * env(n, v, n)
    # stop at d+.02 in web; env already ~0
    buf[s:s + n] += y[: max(0, len(buf) - s)]

def lowpass(x, fc, Q=1.0):
    w0 = 2 * np.pi * fc / SR; a = np.sin(w0) / (2 * Q); c = np.cos(w0)
    b = np.array([(1 - c) / 2, 1 - c, (1 - c) / 2]); aa = np.array([1 + a, -2 * c, 1 - a])
    return lfilter(b / aa[0], aa / aa[0], x)

def hiss(buf, d, v, freq=3000, at=0.0, swell=False):
    n = int(d * SR); s = int(at * SR)
    x = lowpass(rng.uniform(-1, 1, n), freq)
    i = np.arange(n)
    if swell:
        up = int(n * .3)
        g = np.where(i < up, .001 * (v / .001) ** (i / up), v * (0.0008 / v) ** ((i - up) / (n - up)))
    else:
        g = env(n, v, n)
    buf[s:s + n] += (x * g)[: max(0, len(buf) - s)]

def chime(buf, fs, gap=.06, v=.13):
    for i, f in enumerate(fs): tone(buf, f, f, .3, v, "sine", i * gap)

def new(sec): return np.zeros(int(sec * SR))

def pop():  b = new(.3); tone(b, 500, 900, .08, .14); return b
def power(f=440): b = new(.5); tone(b, f, f * 2.2, .28, .2); hiss(b, .25, .08, 5000); return b
def wildfire(): b = new(1.2); hiss(b, .9, .45, 2200); tone(b, 90, 220, .9, .22); return b
def final():
    b = new(2.0)
    tone(b, 110, 440, .5, .3, "sawtooth"); hiss(b, .6, .25, 2500, 0, True)
    for i, f in enumerate([523, 659, 784, 1047]): tone(b, f, f, .16, .16, "square", .35 + i * .09)
    tone(b, 1047, 1047, .7, .14, "triangle", .75); tone(b, 1319, 1319, .7, .1, "triangle", .75)
    return b
def crown():
    b = new(2.5)
    for i, f in enumerate([523, 659, 784]): tone(b, f, f, .14, .15, "triangle", i * .09)
    for f in [1047, 1319, 1568]: tone(b, f, f, 1.4, .1, "triangle", .3)
    hiss(b, .5, .12, 9000, .3); return b

if __name__ == "__main__":
    out = sys.argv[1]
    for name, b in dict(capture=pop(), power=power(), reaction=wildfire(), final=final(), win=crown()).items():
        wavfile.write(f"{out}/raw_{name}.wav", SR, (np.clip(b, -1, 1) * 32767).astype(np.int16))
