"""Synthesizes every sound effect into audio/*.wav (mono, 22.05kHz, 16-bit)."""
import numpy as np, wave, os
SR = 22050
OUT = os.path.join(os.path.dirname(__file__), '..', 'audio')
rng = np.random.default_rng(7)
def t(d): return np.arange(int(SR * d)) / SR
def env(n, a=0.002, d=0.1, curve=4.0):
    x = np.arange(n) / SR; e = np.minimum(1, x / max(a, 1e-4)) * np.exp(-np.maximum(0, x - a) * curve / max(d, 1e-4)); return e
def noise(d): return rng.uniform(-1, 1, int(SR * d))
def lp(x, k):  # one-pole low-pass, k in (0,1]
    y = np.zeros_like(x); acc = 0.0
    for i, v in enumerate(x): acc += k * (v - acc); y[i] = acc
    return y
def hp(x, k): return x - lp(x, k)
def sweep(f0, f1, d, shape='sine'):
    tt = t(d); f = f0 * (f1 / f0) ** (tt / d); ph = 2 * np.pi * np.cumsum(f) / SR
    if shape == 'sine': return np.sin(ph)
    if shape == 'tri': return 2 / np.pi * np.arcsin(np.sin(ph))
    if shape == 'sq': return np.sign(np.sin(ph)) * .6
    return ((ph / (2 * np.pi)) % 1) * 2 - 1
def mix(*xs):
    n = max(len(x) for x in xs); o = np.zeros(n)
    for x in xs: o[:len(x)] += x
    return o
def save(name, x, gain=0.9):
    x = np.asarray(x, dtype=float); pk = np.max(np.abs(x)) or 1; x = x / pk * gain
    fade = min(len(x), 64); x[-fade:] *= np.linspace(1, 0, fade)
    with wave.open(os.path.join(OUT, name + '.wav'), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes((x * 32767).astype(np.int16).tobytes())
S = {}
# weapons
d = .12; S['smg'] = mix(lp(noise(d), .35) * env(int(SR*d), .001, .03, 5), sweep(900, 300, d, 'sq') * env(int(SR*d), .001, .02, 6) * .5)
d = .22; S['rifle'] = mix(lp(noise(d), .25) * env(int(SR*d), .001, .06, 5), sweep(420, 90, d, 'tri') * env(int(SR*d), .001, .05, 5) * .9)
d = .35; S['thump'] = mix(sweep(160, 50, d) * env(int(SR*d), .002, .12, 4), lp(noise(d), .08) * env(int(SR*d), .001, .05, 6) * .7)
d = .7; S['boom'] = mix(lp(noise(d), .06) * env(int(SR*d), .003, .25, 4) * 1.2, sweep(90, 30, d) * env(int(SR*d), .002, .3, 4))
# impacts
d = .09; S['hit'] = mix(hp(noise(d), .5) * env(int(SR*d), .0005, .02, 6) * .6, sweep(700, 200, d, 'tri') * env(int(SR*d), .0005, .03, 6))
d = .18; S['crit'] = mix(S['hit'] * 1.0, sweep(1800, 900, d, 'sine') * env(int(SR*d), .001, .07, 5) * .6)
d = .5; S['kill'] = mix(sweep(300, 1200, .12, 'tri') * env(int(SR*.12), .001, .08, 3) * .6, np.concatenate([np.zeros(int(SR*.06)), sweep(600, 1500, .3, 'sine') * env(int(SR*.3), .002, .15, 4) * .5]), lp(noise(d), .2) * env(int(SR*d), .001, .06, 6) * .5)
d = .45; S['knock'] = mix(sweep(220, 55, d, 'saw') * env(int(SR*d), .002, .2, 3), lp(noise(d), .1) * env(int(SR*d), .001, .1, 5))
d = .16; S['hurt'] = mix(sweep(300, 120, d, 'sq') * env(int(SR*d), .001, .06, 5) * .6, lp(noise(d), .3) * env(int(SR*d), .001, .04, 6) * .5)
# movement
d = .2; S['dash'] = hp(noise(d), .2) * env(int(SR*d), .03, .08, 4) * np.linspace(.3, 1, int(SR*d)) ** .5
d = .14; S['jump'] = sweep(260, 520, d, 'tri') * env(int(SR*d), .002, .06, 4) * .7
d = .12; S['land'] = lp(noise(d), .1) * env(int(SR*d), .001, .04, 5)
d = .3; S['grab'] = mix(sweep(1200, 600, .08, 'sq') * env(int(SR*.08), .001, .03, 5) * .4, np.concatenate([np.zeros(int(SR*.05)), hp(noise(.25), .3) * env(int(SR*.25), .02, .1, 4) * .6]))
# kin
d = .28; S['throw'] = mix(hp(noise(d), .15) * env(int(SR*d), .02, .12, 3) * .7, sweep(300, 700, d, 'sine') * env(int(SR*d), .01, .1, 3) * .4)
d = .22; S['kinhit'] = mix(sweep(500, 120, d, 'tri') * env(int(SR*d), .001, .08, 4), lp(noise(d), .2) * env(int(SR*d), .001, .05, 5) * .8)
d = .4; S['skill'] = mix(sweep(400, 1600, .2, 'sine') * env(int(SR*.2), .005, .15, 2) * .6, np.concatenate([np.zeros(int(SR*.1)), lp(noise(.3), .15) * env(int(SR*.3), .01, .15, 4)]))
def chirp(f, d, up=True):
    tt = t(d); ff = f * (1 + (.25 if up else -.2) * np.sin(np.pi * tt / d)); return np.sin(2 * np.pi * np.cumsum(ff) / SR) * env(len(tt), .01, d * .6, 2.5)
S['kin_happy'] = np.concatenate([chirp(880, .09), chirp(1175, .12)])
S['kin_unsure'] = np.concatenate([chirp(700, .12, False), chirp(560, .16, False)])
S['kin_alert'] = np.concatenate([chirp(1320, .06), np.zeros(int(SR*.03)), chirp(1320, .06)])
d = .5; S['recall'] = sweep(900, 300, d, 'sine') * env(int(SR*d), .01, .25, 3) * .6
# world
d = .25; S['pickup'] = np.concatenate([sweep(900, 900, .06, 'tri') * env(int(SR*.06), .001, .04, 3), sweep(1350, 1350, .12, 'tri') * env(int(SR*.12), .001, .08, 3)])
d = .9; S['catch'] = np.concatenate([sweep(523, 523, .12, 'tri') * env(int(SR*.12), .002, .1, 2), sweep(659, 659, .12, 'tri') * env(int(SR*.12), .002, .1, 2), sweep(784, 784, .12, 'tri') * env(int(SR*.12), .002, .1, 2), sweep(1047, 1047, .4, 'tri') * env(int(SR*.4), .002, .3, 2)])
d = .6; S['warn'] = sweep(180, 260, d, 'saw') * env(int(SR*d), .25, .2, 3) * .5
d = .9; S['portal'] = mix(sweep(200, 800, d, 'sine') * env(int(SR*d), .2, .4, 2) * .5, sweep(300, 1200, d, 'sine') * env(int(SR*d), .25, .4, 2) * .3)
d = .8; S['revive'] = np.concatenate([chirp(660, .15), chirp(880, .15), chirp(1320, .35)])
d = .06; S['click'] = sweep(1400, 900, d, 'tri') * env(int(SR*d), .001, .02, 4) * .6
d = .5; S['reload'] = np.concatenate([lp(noise(.05), .4) * env(int(SR*.05), .001, .02, 5), np.zeros(int(SR*.18)), hp(noise(.06), .3) * env(int(SR*.06), .001, .02, 5) * 1.2])
d = .35; S['shield'] = mix(sweep(300, 900, d, 'tri') * env(int(SR*d), .01, .2, 3) * .5, sweep(450, 1350, d, 'sine') * env(int(SR*d), .01, .2, 3) * .3)
d = .5; S['cloak'] = hp(noise(d), .25) * env(int(SR*d), .1, .2, 3) * np.linspace(1, 0, int(SR*d))
d = .6; S['heal'] = mix(sweep(523, 1046, d, 'sine') * env(int(SR*d), .05, .3, 2) * .4, sweep(659, 1318, d, 'sine') * env(int(SR*d), .08, .3, 2) * .3)
d = 1.2; S['fall'] = sweep(700, 80, d, 'sine') * env(int(SR*d), .02, .8, 2) * .6
d = .3; S['plant'] = lp(noise(d), .05) * env(int(SR*d), .005, .1, 4)
S['harvest'] = np.concatenate([chirp(784, .08), chirp(988, .08), chirp(1175, .14)])
d = .2; S['ping'] = sweep(1600, 1600, d, 'sine') * env(int(SR*d), .001, .12, 3) * .5
for k, v in S.items(): save(k, v)
print(len(S), 'sounds')
