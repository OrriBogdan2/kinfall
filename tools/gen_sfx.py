"""Synthesizes every sound effect into audio/*.wav (mono, 22.05kHz, 16-bit).

    python3 tools/gen_sfx.py           (then: godot --headless --import)

The sound palette is soft and warm on purpose: every sound fades in (a few ms for impacts, longer for
everything else) so nothing clicks, noise is band-limited instead of raw hiss, tones are sines with a
little second harmonic instead of square or saw waves, and each sound is levelled to a target loudness
(RMS) that sits under the music rather than normalised to full scale. Measure the result with
tools/sfx_stats.py.

Needs numpy and scipy. All sounds are original and synthesized here, no samples.
"""
import numpy as np, wave, os
from scipy.signal import butter, sosfilt

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), '..', 'audio')
rng = np.random.default_rng(7)


# ------------------------------------------------------------------ building blocks
def N(d): return int(SR * d)
def T(d): return np.arange(N(d)) / SR
def noise(d): return rng.standard_normal(N(d)) * 0.35


def _sos(kind, hz):
    if kind == 'band':
        lo, hi = hz
        return butter(2, [max(lo, 20) / (SR / 2), min(hi, SR * 0.45) / (SR / 2)], 'band', output='sos')
    return butter(2, min(max(hz, 20), SR * 0.45) / (SR / 2), kind, output='sos')


def lpf(x, hz): return sosfilt(_sos('low', hz), x)
def hpf(x, hz): return sosfilt(_sos('high', hz), x)
def bpf(x, lo, hi): return sosfilt(_sos('band', (lo, hi)), x)


def glide(f0, f1, n):
    """A frequency path from f0 to f1 over n samples (exponential, so it sounds even)."""
    u = np.arange(n) / max(1, n - 1)
    return f0 * (f1 / f0) ** u


def svf_bp(x, freqs, q=1.4):
    """Band-pass with a moving centre (a state-variable filter), for swishes and whooshes."""
    freqs = np.broadcast_to(np.asarray(freqs, dtype=float), x.shape)
    low = band = 0.0; out = np.empty_like(x); damp = 1.0 / q
    for i in range(len(x)):
        f = 2.0 * np.sin(np.pi * min(freqs[i], SR / 6.5) / SR)
        low += f * band
        high = x[i] - low - damp * band
        band += f * high
        out[i] = band
    return out


def env(n, a=0.006, d=0.12, hold=0.0):
    """Raised-cosine fade-in over a seconds, an optional hold, then an exponential fall (time constant d)."""
    t = np.arange(n) / SR
    att = np.where(t < a, 0.5 - 0.5 * np.cos(np.pi * np.clip(t / max(a, 1e-4), 0, 1)), 1.0)
    dec = np.exp(-np.maximum(0.0, t - a - hold) / max(d, 1e-4))
    return att * dec


def swell(n, a=0.1, r=0.2):
    """Fade in over a, hold, fade out over the last r seconds (both raised-cosine)."""
    t = np.arange(n) / SR; dur = n / SR
    up = 0.5 - 0.5 * np.cos(np.pi * np.clip(t / max(a, 1e-4), 0, 1))
    dn = 0.5 - 0.5 * np.cos(np.pi * np.clip((dur - t) / max(r, 1e-4), 0, 1))
    return up * dn


def tone(f0, f1, d, harm=(1.0, 0.12), vib=0.0, vib_hz=5.5):
    """A sine (plus a few soft harmonics) gliding from f0 to f1."""
    n = N(d); f = glide(f0, f1, n)
    if vib:
        f = f * (1.0 + vib * np.sin(2 * np.pi * vib_hz * np.arange(n) / SR))
    ph = 2 * np.pi * np.cumsum(f) / SR
    return sum(a * np.sin(ph * (k + 1)) for k, a in enumerate(harm))


def pluck(f, d=0.25, a=0.004, decay=0.09, harm=(1.0, 0.18, 0.05)):
    return tone(f, f, d, harm) * env(N(d), a, decay)


def bell(f, d=0.6, a=0.006, decay=0.22):
    """A soft glassy chime: a sine with a couple of quieter, faster-fading inharmonic partials."""
    n = N(d)
    x = np.sin(2 * np.pi * f * T(d)) * env(n, a, decay)
    x += 0.22 * np.sin(2 * np.pi * f * 2.76 * T(d)) * env(n, a, decay * 0.45)
    x += 0.08 * np.sin(2 * np.pi * f * 5.4 * T(d)) * env(n, a, decay * 0.25)
    return x


def voice(f0, f1, d, formants, growl=0.0, jitter=0.01, a=0.03, decay=None, src_lp=1400):
    """A creature-ish voice: a buzzy source through vowel-like band-pass formants, then softened."""
    n = N(d); f = glide(f0, f1, n)
    f = f * (1.0 + jitter * lpf(rng.standard_normal(n), 30) * 8)
    ph = np.cumsum(f) / SR
    src = lpf(((ph % 1.0) * 2 - 1), src_lp)               # a saw, rounded off
    if growl:
        src *= 1.0 - growl + growl * (0.5 + 0.5 * np.sin(2 * np.pi * 31.0 * np.arange(n) / SR + 3 * lpf(rng.standard_normal(n), 40)))
    out = sum(g * bpf(src, fc / (1 + bw), fc * (1 + bw)) for fc, bw, g in formants)
    e = swell(n, a, min(0.12, d * 0.4)) if decay is None else env(n, a, decay)
    return out * e


def mix(*xs):
    n = max(len(x) for x in xs); o = np.zeros(n)
    for x in xs: o[:len(x)] += x
    return o


def at(x, delay):
    return np.concatenate([np.zeros(N(delay)), x])


def cat(*xs): return np.concatenate(xs)
def gap(d): return np.zeros(N(d))


def thud(f0=120, f1=50, d=0.25, a=0.004, decay=0.07, body_lp=700, nz=0.6):
    """A soft low impact: a falling sine body with a puff of low-passed noise."""
    n = N(d)
    return tone(f0, f1, d, (1.0, 0.1)) * env(n, a, decay) + lpf(noise(d), body_lp) * env(n, a, decay * 0.6) * nz * 2


def swish(d=0.22, f0=350, f1=1300, f2=None, a=0.03, q=1.2):
    """Air moving: band-passed noise whose centre sweeps f0 -> f1 (-> f2), faded in and out smoothly."""
    n = N(d)
    path = glide(f0, f1, n) if f2 is None else np.concatenate([glide(f0, f1, n // 2), glide(f1, f2, n - n // 2)])
    return svf_bp(noise(d), path, q) * swell(n, a, d * 0.55)


def crackle(d, per_s=40, lp_hz=1800):
    """Sparse soft crackles: tiny windowed grains of band-passed noise (each fades in over ~3 ms)."""
    n = N(d); out = np.zeros(n)
    for _ in range(int(per_s * d)):
        g = N(rng.uniform(0.006, 0.014)); s0 = rng.integers(0, max(1, n - g))
        out[s0:s0 + g] += bpf(rng.standard_normal(g), 400, lp_hz) * np.hanning(g) * rng.uniform(0.4, 1.0)
    return out

# ------------------------------------------------------------------ levelling and writing
def level(x, rms_db=-20.0, ceil_db=-3.0, lp=None, fade_in=0.0015):
    x = np.asarray(x, dtype=float)
    x = hpf(x, 35)
    if lp:
        x = lpf(x, lp)
    fi = max(1, N(fade_in)); x[:fi] *= 0.5 - 0.5 * np.cos(np.pi * np.arange(fi) / fi)
    fo = min(len(x), N(0.02)); x[-fo:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(fo) / fo)
    pk = np.max(np.abs(x)) or 1.0
    act = np.abs(x) > pk * 0.01
    rms = np.sqrt(np.mean(x[act] ** 2)) or 1.0
    x = x * (10 ** (rms_db / 20) / rms)
    c = 10 ** (ceil_db / 20)
    over = np.abs(x) > c * 0.7
    if over.any():
        # a soft knee: everything above 70% of the ceiling is bent smoothly under it
        k = c * 0.7; s = np.sign(x); m = np.abs(x)
        x = np.where(over, s * (k + (c - k) * np.tanh((m - k) / (c - k))), x)
    return x


def save(name, x, rms_db=-20.0, lp=None, ceil_db=-3.0, fade_in=0.0015):
    x = level(x, rms_db, ceil_db, lp, fade_in)
    with wave.open(os.path.join(OUT, name + '.wav'), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())


def takes(name, fn, n=3, **kw):
    """The base sound plus n variants, so repeats never sound copy-pasted."""
    save(name, fn(0), **kw)
    for i in range(1, n + 1):
        save('%s_%d' % (name, i), fn(i), **kw)


# ================================================================== weapons
# guns: soft, rounded pops (a low body and a short puff), not cracks
def smg(i):
    d = 0.11
    return mix(thud(240 + 15 * i, 140, d, 0.003, 0.022, 1200, 0.3) * 0.6, bpf(noise(d), 450, 1700 + 150 * i) * env(N(d), 0.003, 0.02) * 1.6)
takes('smg', smg, rms_db=-23, lp=2600)


def rifle(i):
    d = 0.28
    return mix(thud(190 + 10 * i, 95, d, 0.003, 0.035, 900, 0.4) * 0.6, bpf(noise(d), 350, 1500 + 100 * i) * env(N(d), 0.004, 0.05) * 1.4,
               bpf(noise(d), 200, 700) * env(N(d), 0.02, 0.1) * 0.6)
takes('rifle', rifle, rms_db=-21, lp=2400)

# the shotgun, heartbeats, heavy bumps: a round low whomp
save('thump', mix(thud(150, 70, 0.4, 0.005, 0.08, 900, 0.4) * 0.6, bpf(noise(0.4), 180, 800) * env(N(0.4), 0.005, 0.06) * 1.4), rms_db=-19, lp=1300)


def boom(i):
    d = 0.8; n = N(d)
    rumble = svf_bp(noise(d), glide(900 - 60 * i, 160, n), 0.9) * env(n, 0.012, 0.22)
    return mix(rumble * 2.2, tone(90 + 6 * i, 45, d, (1.0, 0.25)) * env(n, 0.01, 0.18) * 0.5)
takes('boom', boom, 2, rms_db=-19, lp=1500)

# a gun being reloaded: two muted clicks of a mag, no ringing metal
save('reload', cat(bpf(noise(0.06), 500, 1800) * env(N(0.06), 0.003, 0.012), gap(0.17),
                   mix(bpf(noise(0.08), 400, 1500) * env(N(0.08), 0.003, 0.015), thud(200, 120, 0.08, 0.003, 0.02, 800, 0.3) * 0.6)),
     rms_db=-25, lp=2200)

# a sniper winding up: a quiet rising hum
d = 0.5; save('charge', tone(180, 300, d, (1.0, 0.2, 0.05)) * swell(N(d), 0.12, 0.12) + lpf(noise(d), 900) * swell(N(d), 0.2, 0.1) * 0.3,
              rms_db=-26, lp=1800)


# melee: a soft swish of the blade through air, with a muted body under it
def swipe(i):
    d = 0.2 + 0.015 * i
    return mix(swish(d, 300 + 30 * i, 1100 + 80 * i, 500, 0.025, 1.5), thud(150, 90, d, 0.02, 0.05, 500, 0.3) * 0.3)
takes('swipe', swipe, rms_db=-22, lp=2600)


def cleave(i):
    d = 0.32
    return mix(swish(d, 200, 800 + 60 * i, 300, 0.04, 1.3), at(thud(100 + 8 * i, 50, 0.25, 0.006, 0.07, 500, 0.5), 0.09) * 0.8)
takes('cleave', cleave, 2, rms_db=-20, lp=2000)

# ================================================================== being hit, hitting
# a clear but muted "tok": short and readable, nothing above ~3 kHz
def hit(i):
    d = 0.11
    return mix(tone(520 + 50 * i, 280, d, (1.0, 0.2)) * env(N(d), 0.004, 0.025),
               bpf(noise(d), 600, 2200) * env(N(d), 0.004, 0.015) * 0.9)
takes('hit', hit, rms_db=-21, lp=3000)


# a crit: the same tok with a soft glassy ring on top
def crit(i):
    return mix(hit(i), at(bell(1050 + 70 * i, 0.3, 0.004, 0.08), 0.01) * 0.45)
takes('crit', crit, rms_db=-20, lp=3800)


# being hurt: a muffled low "thup" (you, or your kin)
def hurt(i):
    d = 0.16
    return mix(tone(300 + 20 * i, 160, d, (1.0, 0.2)) * env(N(d), 0.004, 0.04), bpf(noise(d), 250, 1100) * env(N(d), 0.004, 0.03) * 1.3)
takes('hurt', hurt, rms_db=-20, lp=1600)


def kinhit(i):
    d = 0.2
    return mix(tone(360 + 25 * i, 180, d, (1.0, 0.2)) * env(N(d), 0.004, 0.045), bpf(noise(d), 300, 1400) * env(N(d), 0.004, 0.03) * 1.2)
takes('kinhit', kinhit, rms_db=-21, lp=2000)

# a kill: a low thud and a warm two-note bell, not a laser
save('kill', mix(thud(150, 60, 0.3, 0.004, 0.06, 600, 0.4) * 0.7, at(bell(659, 0.5, 0.006, 0.16), 0.03) * 0.5,
                 at(bell(988, 0.5, 0.006, 0.18), 0.12) * 0.4), rms_db=-20, lp=3200)
# knocked down: a soft, heavy low thud
save('knock', mix(thud(160, 65, 0.55, 0.006, 0.13, 700, 0.5) * 0.7, bpf(noise(0.55), 150, 700) * env(N(0.55), 0.01, 0.12) * 1.3), rms_db=-18, lp=1200)


# monsters dying: a puff and a soft fall
def pop(i, big=False):
    if big:
        return mix(thud(150 + 10 * i, 60, 0.45, 0.006, 0.11, 700, 0.5) * 0.6, bpf(noise(0.45), 150, 800) * env(N(0.45), 0.01, 0.1) * 1.3)
    d = 0.22
    return mix(thud(300 + 25 * i, 150, d, 0.005, 0.045, 1000, 0.3) * 0.6, bpf(noise(d), 350, 1400) * env(N(d), 0.006, 0.05) * 1.4)
for i in range(1, 4):
    save('die_small_%d' % i, pop(i), rms_db=-22, lp=1800)
    save('die_big_%d' % i, pop(i, True), rms_db=-19, lp=1000)

# ================================================================== movement
save('dash', swish(0.24, 260, 1100, 450, 0.03, 1.3), rms_db=-22, lp=2400)
save('jump', mix(swish(0.16, 300, 800, None, 0.012, 1.1) * 0.8, tone(170, 260, 0.14, (1.0, 0.1)) * env(N(0.14), 0.008, 0.04) * 0.5), rms_db=-24, lp=2000)


def land(i):
    d = 0.14
    return mix(bpf(noise(d), 150, 800 + 60 * i) * env(N(d), 0.005, 0.035) * 2.0, tone(130 + 8 * i, 85, d) * env(N(d), 0.005, 0.04) * 0.3)
takes('land', land, rms_db=-22, lp=1200)


# footsteps: a quiet, dull pat
for i in range(3):
    d = 0.09
    save('step%d' % i, mix(bpf(noise(d), 180, 700 + 80 * i) * env(N(d), 0.005, 0.022) * 2.0, tone(140 + 15 * i, 100, d) * env(N(d), 0.005, 0.02) * 0.2),
         rms_db=-24, lp=900)
save('grab', mix(tone(330, 220, 0.12, (1.0, 0.15)) * env(N(0.12), 0.006, 0.03) * 0.6, at(swish(0.24, 500, 1000, 400, 0.02, 1.2), 0.04)), rms_db=-23, lp=2000)
save('glide', swish(0.4, 220, 900, 380, 0.06, 1.0), rms_db=-21, lp=2000)
save('whoosh', swish(0.26, 300, 1000, 450, 0.04, 1.1), rms_db=-22, lp=2000)
# falling off the world: a long soft fall in pitch, with air rushing past
d = 1.1; save('fall', mix(tone(420, 110, d, (1.0, 0.15)) * swell(N(d), 0.04, 0.5) * 0.6, swish(d, 900, 300, None, 0.1, 0.9) * 0.6), rms_db=-19, lp=1600)

# ================================================================== kin: voices, throws, abilities
def chirp(f, d, up=True, vib=0.012):
    n = N(d); u = np.arange(n) / n
    ff = f * (1 + (0.18 if up else -0.15) * np.sin(np.pi * u))
    ph = 2 * np.pi * np.cumsum(ff * (1 + vib * np.sin(2 * np.pi * 9 * u * d))) / SR
    return (np.sin(ph) + 0.15 * np.sin(2 * ph)) * swell(n, min(0.015, d * 0.25), d * 0.55)
save('kin_happy', cat(chirp(660, 0.1), gap(0.02), chirp(880, 0.14)), rms_db=-20, lp=3000)
save('kin_unsure', cat(chirp(560, 0.13, False), gap(0.03), chirp(440, 0.18, False)), rms_db=-20, lp=2600)
save('kin_alert', cat(chirp(990, 0.07), gap(0.04), chirp(990, 0.08)), rms_db=-21, lp=3200)
save('recall', tone(700, 330, 0.5, (1.0, 0.15)) * swell(N(0.5), 0.015, 0.35) * 0.7 + swish(0.5, 900, 300, None, 0.05, 1.0) * 0.4, rms_db=-21, lp=2400)
save('throw', mix(swish(0.3, 300, 1100, 500, 0.02, 1.2), tone(240, 420, 0.25, (1.0, 0.1)) * swell(N(0.25), 0.02, 0.15) * 0.3), rms_db=-21, lp=2200)
# a generic ability (gloves, anything without its own sound): a soft rising shimmer
save('skill', mix(tone(330, 660, 0.4, (1.0, 0.2, 0.05)) * swell(N(0.4), 0.025, 0.25) * 0.5, swish(0.4, 400, 1200, 600, 0.04, 1.2) * 0.5),
     rms_db=-21, lp=2600)

# each kin type's own ability cue, fitting its element
# venom (fireball, flare dash): a warm whoomp of flame
d = 0.55; n = N(d)
save('k_venom', mix(svf_bp(noise(d), np.concatenate([glide(200, 1200, n // 3), glide(1200, 300, n - n // 3)]), 0.8) * swell(n, 0.03, 0.4) * 1.5,
                    tone(85, 55, d) * env(n, 0.03, 0.15) * 0.6,
                    crackle(d, 25, 1500) * swell(n, 0.05, 0.3) * 0.8),
     rms_db=-20, lp=1800)
# spore (snare, thorn patch): a soft puff, then two smaller ones
def puff(d, lo, hi): return bpf(noise(d), lo, hi) * env(N(d), 0.01, d * 0.3) + tone(160, 110, d) * env(N(d), 0.01, d * 0.25) * 0.15
save('k_spore', mix(puff(0.25, 300, 1400), at(puff(0.18, 400, 1600) * 0.6, 0.12), at(puff(0.15, 500, 1800) * 0.4, 0.22)), rms_db=-21, lp=2000)
# gravity (slam, rock guard): a low rumbling thud of stone
d = 0.7; n = N(d)
save('k_gravity', mix(thud(110, 50, d, 0.012, 0.16, 500, 0.5) * 0.6, bpf(noise(d), 80, 450) * swell(n, 0.03, 0.4) * 1.6), rms_db=-18, lp=900)
# prism (wave, bubble guard): a glassy soft chime, a fifth and an octave
save('k_prism', mix(bell(784, 0.8, 0.008, 0.25), at(bell(1175, 0.7, 0.008, 0.2), 0.05) * 0.6, at(bell(1568, 0.6, 0.008, 0.15), 0.1) * 0.3,
                    swish(0.5, 500, 1200, 600, 0.05, 1.0) * 0.25), rms_db=-22, lp=4200)
# lunar (gust, updraft): wind swirling up, with a faint pale tone in it
d = 0.7; n = N(d)
save('k_lunar', mix(svf_bp(noise(d), 600 + 400 * np.sin(np.linspace(0, 2.2 * np.pi, n)) ** 2, 1.4) * swell(n, 0.08, 0.35) * 1.2,
                    tone(440, 523, d, (1.0, 0.1)) * swell(n, 0.12, 0.35) * 0.12), rms_db=-21, lp=2200)
# echo (chain spark, overcharge): storm energy, a low rumble with soft crackles
d = 0.6; n = N(d)
save('k_echo', mix(bpf(noise(d), 70, 300) * swell(n, 0.03, 0.35) * 2.0, crackle(d, 45) * swell(n, 0.02, 0.3) * 0.8, tone(80, 60, d) * swell(n, 0.03, 0.3) * 0.25),
     rms_db=-20, lp=1800)
# a lightning arc between foes: a short low crackle, not a buzz
d = 0.32; n = N(d)
save('zap', mix(crackle(d, 90, 2000) * env(n, 0.004, 0.09), lpf(noise(d), 200) * env(n, 0.01, 0.1) * 1.2), rms_db=-21, lp=2200)
# the bond filling: three warm chimes
save('bond', mix(bell(523, 0.5, 0.008, 0.15), at(bell(659, 0.5, 0.008, 0.15), 0.1), at(bell(784, 0.7, 0.008, 0.25), 0.2)), rms_db=-21, lp=3600)
# an ultimate: a deep swell that blooms
d = 1.1; n = N(d)
save('ult', mix(svf_bp(noise(d), glide(150, 700, n), 0.9) * swell(n, 0.15, 0.6) * 1.8, tone(70, 90, d, (1.0, 0.3)) * swell(n, 0.1, 0.6) * 0.35,
                tone(220, 440, d, (1.0, 0.15)) * swell(n, 0.25, 0.5) * 0.25), rms_db=-18, lp=1600)
save('combo', mix(thud(160, 70, 0.3, 0.004, 0.06, 500, 0.4) * 0.6, at(bell(784, 0.45, 0.006, 0.12), 0.02) * 0.5, at(bell(1047, 0.45, 0.006, 0.14), 0.09) * 0.4),
     rms_db=-20, lp=3400)
save('swap', mix(tone(400, 600, 0.3, (1.0, 0.12)) * swell(N(0.3), 0.03, 0.2) * 0.4, swish(0.3, 350, 1000, 500, 0.03, 1.2) * 0.6), rms_db=-22, lp=2200)
save('shield', mix(tone(330, 495, 0.45, (1.0, 0.25, 0.08)) * swell(N(0.45), 0.03, 0.3) * 0.5, at(bell(990, 0.4, 0.02, 0.12), 0.05) * 0.25),
     rms_db=-21, lp=3000)
d = 0.5; save('cloak', svf_bp(noise(d), glide(1300, 400, N(d)), 1.0) * swell(N(d), 0.06, 0.35), rms_db=-24, lp=2200)
d = 0.7; save('heal', mix(tone(392, 523, d, (1.0, 0.12)) * swell(N(d), 0.05, 0.4) * 0.5, at(tone(494, 659, d - 0.08, (1.0, 0.1)) * swell(N(d - 0.08), 0.06, 0.35) * 0.35, 0.08)),
              rms_db=-21, lp=2600)

# ================================================================== the world
save('plant', mix(bpf(noise(0.25), 150, 700) * env(N(0.25), 0.006, 0.06) * 2.0, tone(160, 110, 0.2) * env(N(0.2), 0.006, 0.05) * 0.3), rms_db=-21, lp=1000)
save('harvest', mix(pluck(523), at(pluck(659), 0.08), at(pluck(784, 0.35, 0.004, 0.14), 0.16)), rms_db=-21, lp=2800)
save('ping', bell(880, 0.5, 0.008, 0.16), rms_db=-23, lp=3200)
save('pickup', mix(pluck(659, 0.18, 0.004, 0.05), at(pluck(880, 0.25, 0.004, 0.08), 0.06)), rms_db=-22, lp=3000)
save('catch', mix(*[at(pluck(f, 0.4 if k < 3 else 0.7, 0.005, 0.1 if k < 3 else 0.28), 0.11 * k) for k, f in enumerate((392, 494, 587, 784))]),
     rms_db=-19, lp=3000)
# a warning: a low two-tone hum that swells in, noticeable but never a siren
d = 0.7; n = N(d)
save('warn', mix(tone(196, 196, d, (1.0, 0.25, 0.08)), tone(233, 233, d, (1.0, 0.2)) * 0.6) * swell(n, 0.12, 0.3) * (0.8 + 0.2 * np.sin(2 * np.pi * 5 * T(d))),
     rms_db=-21, lp=1400)
d = 1.0; n = N(d)
save('portal', mix(tone(200, 600, d, (1.0, 0.1)) * swell(n, 0.25, 0.45) * 0.5, tone(300, 900, d) * swell(n, 0.3, 0.45) * 0.2, swish(d, 300, 900, 400, 0.25, 1.0) * 0.4),
     rms_db=-20, lp=2400)
save('revive', mix(bell(523, 0.5, 0.01, 0.14), at(bell(659, 0.5, 0.01, 0.14), 0.13), at(bell(784, 0.8, 0.01, 0.3), 0.26)), rms_db=-20, lp=3400)
# ui: short, soft ticks
save('click', tone(820, 650, 0.05, (1.0, 0.1)) * env(N(0.05), 0.004, 0.01), rms_db=-24, lp=3000)
save('hover', tone(1050, 980, 0.04) * env(N(0.04), 0.004, 0.008), rms_db=-29, lp=3000)
def knock(f):
    return mix(tone(f, f * 0.75, 0.08, (1.0, 0.15)) * env(N(0.08), 0.003, 0.018), bpf(noise(0.08), 400, 1400) * env(N(0.08), 0.003, 0.012) * 0.6)
save('build', cat(knock(300), gap(0.09), knock(270), gap(0.09), knock(330)), rms_db=-22, lp=2000)
save('unlock', mix(*[at(pluck(f, 0.35 if k < 4 else 0.7, 0.005, 0.09 if k < 4 else 0.25), 0.09 * k) for k, f in enumerate((523, 659, 784, 880, 1047))]),
     rms_db=-20, lp=3200)

# ================================================================== monster voices: low and creature-like
# skitter: a small crawling thing, a quick soft chitter over a purr
def skitter(i):
    clicks = [at(bpf(noise(0.03), 700, 1700) * env(N(0.03), 0.002, 0.008), 0.035 * k + 0.004 * i * k) for k in range(3 + i % 2)]
    return mix(voice(150 + 15 * i, 130, 0.2, [(420, 0.3, 1.0), (900, 0.2, 0.4)], growl=0.5, a=0.015) * 0.6, *clicks)
# spitter: a wet throaty gurgle
def spitter(i):
    d = 0.34; n = N(d)
    v = voice(120 + 10 * i, 95, d, [(350, 0.35, 1.0), (750, 0.25, 0.5)], growl=0.3, a=0.03)
    return v * (0.55 + 0.45 * np.sin(2 * np.pi * (16 + 4 * i) * T(d))) + lpf(noise(d), 500) * swell(n, 0.03, 0.15) * 0.5
# brute: a heavy grunt
def brute(i):
    return voice(92 + 8 * i, 66, 0.32 + 0.03 * i, [(320, 0.35, 1.0), (650, 0.25, 0.6), (1100, 0.2, 0.15)], growl=0.45, a=0.025)
# bomber: a nervous rising burble with a low hiss, like something about to go
def bomber(i):
    d = 0.45; n = N(d)
    v = voice(150, 230 + 15 * i, d, [(500, 0.3, 1.0), (1000, 0.2, 0.3)], growl=0.2, a=0.08)
    return mix(v * (0.6 + 0.4 * np.sin(2 * np.pi * 11 * T(d))), bpf(noise(d), 500, 1400) * swell(n, 0.15, 0.12) * 0.5)
# sentinel: a stony guardian's low hum and a soft knock of rock
def sentinel(i):
    d = 0.4
    return mix(voice(72 + 6 * i, 70, d, [(280, 0.3, 1.0), (560, 0.25, 0.4)], growl=0.15, a=0.04) * (0.8 + 0.2 * np.sin(2 * np.pi * 6 * T(d))),
               at(thud(160, 90, 0.12, 0.004, 0.03, 600, 0.5), 0.05) * 0.5)
# glimmer: a glassy wisp, soft and breathy
def glimmer(i):
    base = (587, 659, 523)[i % 3]; d = 0.5
    return mix(bell(base, d, 0.02, 0.16), at(bell(base * 1.5, d - 0.05, 0.02, 0.12), 0.05) * 0.4, swish(d, 500, 1200, 600, 0.05, 1.3) * 0.3)
# warden: a deep, slow roar
def warden(i):
    return voice(62 + 5 * i, 46, 0.8, [(300, 0.35, 1.0), (620, 0.25, 0.6), (1050, 0.2, 0.15)], growl=0.55, a=0.09)
for kind, fn, db, lp_hz in [('skitter', skitter, -23, 2000), ('spitter', spitter, -22, 1500), ('brute', brute, -20, 1300), ('bomber', bomber, -23, 1800),
                            ('sentinel', sentinel, -21, 1200), ('glimmer', glimmer, -24, 3000), ('warden', warden, -18, 1300)]:
    for i in range(1, 4):
        save('v_%s_%d' % (kind, i), fn(i), rms_db=db, lp=lp_hz)
print('sounds written')
