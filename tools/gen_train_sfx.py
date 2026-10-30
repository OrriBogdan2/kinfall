"""Synthesizes the sky train's sounds into audio/: a two-tone horn and a rail clatter.
Kept apart from gen_sfx.py so rerunning it doesn't reshuffle every other sound."""
import numpy as np, wave, os
SR = 22050
OUT = os.path.join(os.path.dirname(__file__), '..', 'audio')
rng = np.random.default_rng(11)
def t(d): return np.arange(int(SR * d)) / SR
def env(n, a=0.002, d=0.1, curve=4.0):
    x = np.arange(n) / SR; return np.minimum(1, x / max(a, 1e-4)) * np.exp(-np.maximum(0, x - a) * curve / max(d, 1e-4))
def lp(x, k):
    y = np.zeros_like(x); acc = 0.0
    for i, v in enumerate(x): acc += k * (v - acc); y[i] = acc
    return y
def save(name, x, gain=0.9):
    x = np.asarray(x, dtype=float); pk = np.max(np.abs(x)) or 1; x = x / pk * gain
    fade = min(len(x), 256); x[-fade:] *= np.linspace(1, 0, fade); x[:64] *= np.linspace(0, 1, 64)
    with wave.open(os.path.join(OUT, name + '.wav'), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes((x * 32767).astype(np.int16).tobytes())

def saw(f, d):
    ph = np.cumsum(np.full(int(SR * d), f)) / SR
    return (ph % 1) * 2 - 1

# horn: a minor-third chord of reedy saws, held, with a slight droop at the end
d = 1.3; n = int(SR * d); tt = t(d)
shape = np.minimum(1, tt / .06) * np.where(tt > d - .25, (d - tt) / .25, 1)
droop = 1 - .02 * np.maximum(0, tt - (d - .3)) / .3
horn = sum(lp(saw(f, d) * droop, .25) * a for f, a in ((220, 1), (261.6, .8), (330, .5)))
save('horn', horn * shape)

# rail: wheels clacking over joints with a low rumble underneath
d = 1.0; n = int(SR * d)
rum = lp(rng.uniform(-1, 1, n), .03) * 2.5
clack = np.zeros(n)
for at in (0.0, .12, .5, .62):
    i = int(at * SR); seg = min(n - i, int(.08 * SR))
    clack[i:i + seg] += lp(rng.uniform(-1, 1, seg), .5) * env(seg, .001, .03, 5)
save('rail', rum * .6 + clack, .7)
print('train sounds written')
