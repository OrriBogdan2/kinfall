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
# glider, building, unlocking, ui
d = .32; S['glide'] = mix(hp(noise(d), .25) * env(int(SR*d), .005, .05, 6) * .8, hp(noise(d), .12) * env(int(SR*d), .06, .2, 3) * .5)
def knock(f):
    return mix(lp(noise(.07), .3) * env(int(SR*.07), .0005, .02, 6), sweep(f, f * .6, .07, 'tri') * env(int(SR*.07), .0005, .03, 6) * .8)
S['build'] = np.concatenate([knock(420), np.zeros(int(SR*.09)), knock(380), np.zeros(int(SR*.09)), knock(460)])
S['unlock'] = np.concatenate([chirp(523, .1), chirp(659, .1), chirp(784, .1), chirp(1047, .16), chirp(1319, .3)])
d = .03; S['hover'] = sweep(2400, 2000, d, 'sine') * env(int(SR*d), .001, .012, 4) * .35
d = .16; S['whoosh'] = hp(noise(d), .3) * env(int(SR*d), .04, .06, 3) * .5
# ---- variants, so repeated sounds don't sound copy-pasted
V = {}
def vary(name, fn, n=3):
    for i in range(1, n + 1):
        V['%s_%d' % (name, i)] = fn(i)
vary('hit', lambda i: mix(hp(noise(.08 + .01 * i), .45 + .05 * i) * env(int(SR*(.08 + .01 * i)), .0005, .02, 6) * .55, sweep(620 + 90 * i, 180 + 30 * i, .08, 'tri') * env(int(SR*.08), .0005, .03, 6)))
vary('crit', lambda i: mix(V['hit_%d' % i], sweep(1600 + 200 * i, 820 + 60 * i, .18, 'sine') * env(int(SR*.18), .001, .07, 5) * .6))
vary('hurt', lambda i: mix(sweep(260 + 40 * i, 100 + 15 * i, .15, 'sq') * env(int(SR*.15), .001, .06, 5) * .55, lp(noise(.15), .25 + .05 * i) * env(int(SR*.15), .001, .04, 6) * .5))
vary('smg', lambda i: mix(lp(noise(.11), .3 + .04 * i) * env(int(SR*.11), .001, .03, 5), sweep(820 + 80 * i, 280, .11, 'sq') * env(int(SR*.11), .001, .02, 6) * .45))
vary('rifle', lambda i: mix(lp(noise(.22), .22 + .03 * i) * env(int(SR*.22), .001, .06, 5), sweep(380 + 40 * i, 85 + 8 * i, .22, 'tri') * env(int(SR*.22), .001, .05, 5) * .9))
vary('kinhit', lambda i: mix(sweep(460 + 60 * i, 110 + 15 * i, .2, 'tri') * env(int(SR*.2), .001, .08, 4), lp(noise(.2), .18 + .03 * i) * env(int(SR*.2), .001, .05, 5) * .8))
vary('land', lambda i: lp(noise(.1 + .01 * i), .08 + .02 * i) * env(int(SR*(.1 + .01 * i)), .001, .04, 5))
vary('boom', lambda i: mix(lp(noise(.7), .05 + .015 * i) * env(int(SR*.7), .003, .25, 4) * 1.2, sweep(80 + 12 * i, 28, .7) * env(int(SR*.7), .002, .3, 4)), 2)
# ---- monster voices: short, distinct per kind, a few takes each
def tremolo(x, f, depth=.5):
    return x * (1 - depth + depth * (0.5 + 0.5 * np.sin(2 * np.pi * f * np.arange(len(x)) / SR)))
def chitter(i):
    out = []
    for k in range(3 + i % 2):
        f = 1900 + 300 * ((k + i) % 3)
        out += [sweep(f, f * .7, .025, 'sq') * env(int(SR*.025), .0005, .012, 5) * .5, np.zeros(int(SR*(.018 + .006 * i)))]
    return np.concatenate(out)
def gurgle(i):
    d = .32; x = lp(noise(d), .05) * 3
    return tremolo(mix(x * env(int(SR*d), .02, .15, 3), sweep(240 + 30 * i, 160, d, 'sine') * env(int(SR*d), .02, .15, 3) * .5), 18 + 5 * i, .7)
def grunt(i):
    d = .28 + .03 * i
    return lp(mix(sweep(110 + 12 * i, 75, d, 'saw') * env(int(SR*d), .015, .14, 3), lp(noise(d), .1) * env(int(SR*d), .01, .08, 4) * .4), .18)
def fizz(i):
    d = .45
    return hp(noise(d), .35) * np.linspace(.2, 1, int(SR*d)) * env(int(SR*d), .2, .2, 2) * .6 + sweep(500, 900 + 100 * i, d, 'sine') * env(int(SR*d), .2, .2, 2) * .2
def whirr(i):
    d = .3; tt = t(d)
    f = 320 + 40 * i + 30 * np.sin(2 * np.pi * 22 * tt)
    return mix(np.sign(np.sin(2 * np.pi * np.cumsum(f) / SR)) * .25 * env(len(tt), .02, .15, 3), knock(900 + 100 * i) * .5)
def chime(i):
    d = .5; base = [988, 1175, 1319][i % 3]
    return mix(*[sweep(base * h, base * h, d, 'sine') * env(int(SR*d), .002, .3 / h, 3) * (.6 / h) for h in (1, 2.01, 3.03)])
def roar(i):
    d = .7
    return tremolo(lp(mix(sweep(90 + 10 * i, 55, d, 'saw') * env(int(SR*d), .05, .4, 2), lp(noise(d), .12) * env(int(SR*d), .05, .3, 2) * .8), .2), 9 + 2 * i, .35)
for kind, fn in [('skitter', chitter), ('spitter', gurgle), ('brute', grunt), ('bomber', fizz), ('sentinel', whirr), ('glimmer', chime), ('warden', roar)]:
    vary('v_' + kind, fn)
def pop(i, big=False):
    d = .35 if big else .18
    return mix(lp(noise(d), .12 if big else .3) * env(int(SR*d), .001, d * .4, 4), sweep((300 if big else 700) + 60 * i, (70 if big else 200), d, 'tri') * env(int(SR*d), .001, d * .4, 4) * .8)
vary('die_small', lambda i: pop(i))
vary('die_big', lambda i: pop(i, True))
for k, v in S.items(): save(k, v)
for k, v in V.items(): save(k, v, 0.8)
print(len(S) + len(V), 'sounds')
