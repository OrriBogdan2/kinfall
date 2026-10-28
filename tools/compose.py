"""Kinfall's soundtrack: original folk-style tracks written as note data and rendered through a
General MIDI instrument bank (GeneralUser GS, free for any music use), the way classic MMO
soundtracks were played. Only the rendered .ogg files ship with the game.

    python3 tools/compose.py            # renders every track into audio/
    python3 tools/compose.py home_day   # one track

The bank is fetched once into tools/.cache (not committed).
"""
import os, sys, subprocess, tempfile, wave
import numpy as np
from scipy.signal import fftconvolve, butter, lfilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'audio')
CACHE = os.path.join(HERE, '.cache')
SF2 = os.path.join(CACHE, 'GeneralUser-GS.sf2')
SR = 32000

# General MIDI programs (0-based)
P = {'piano': 0, 'harpsi': 6, 'celesta': 8, 'glock': 9, 'music_box': 10, 'marimba': 12, 'dulcimer': 15,
     'accordion': 21, 'nylon': 24, 'steel': 25, 'ac_bass': 32, 'fretless': 35, 'violin': 40, 'cello': 42,
     'tremolo': 44, 'pizz': 45, 'harp': 46, 'timpani': 47, 'strings': 48, 'slow_strings': 49, 'choir': 52,
     'oohs': 53, 'trumpet': 56, 'trombone': 57, 'tuba': 58, 'horn': 60, 'brass': 61, 'oboe': 68,
     'bassoon': 70, 'clarinet': 71, 'piccolo': 72, 'flute': 73, 'recorder': 74, 'pan_flute': 75,
     'whistle': 78, 'ocarina': 79, 'pad_warm': 89, 'sitar': 104, 'banjo': 105, 'kalimba': 108,
     'bagpipe': 109, 'fiddle': 110, 'taiko': 116, 'melo_tom': 117}
# drum keys on channel 10
D = {'kick': 36, 'snare': 38, 'side': 37, 'hat': 42, 'ohat': 46, 'tamb': 54, 'clap': 39, 'ride': 51,
     'crash': 49, 'tom_lo': 45, 'tom_hi': 50, 'bongo_hi': 60, 'bongo_lo': 61, 'conga': 63, 'shaker': 82,
     'wood_hi': 76, 'wood_lo': 77, 'triangle': 81, 'cabasa': 69}

MODES = {'major': [0, 2, 4, 5, 7, 9, 11], 'minor': [0, 2, 3, 5, 7, 8, 10], 'dorian': [0, 2, 3, 5, 7, 9, 10],
         'mixolydian': [0, 2, 4, 5, 7, 9, 10], 'lydian': [0, 2, 4, 6, 7, 9, 11], 'phrygian': [0, 1, 3, 5, 7, 8, 10]}


class Song:
    def __init__(self, name, bpm, bars, beats=4, root=60, mode='major', seed=1):
        self.name, self.bpm, self.bars, self.beats = name, bpm, bars, beats
        self.root, self.scale = root, MODES[mode]
        self.ev = []            # (beat, chan, key, vel, dur_beats)
        self.prog = {}          # chan -> program
        self.vol = {}           # chan -> 0..127
        self.rng = np.random.default_rng(seed)

    @property
    def length_beats(self):
        return self.bars * self.beats

    def inst(self, ch, program, vol=100):
        self.prog[ch] = P[program] if isinstance(program, str) else program
        self.vol[ch] = vol

    def note(self, ch, beat, key, dur, vel=90):
        self.ev.append((beat, ch, int(key), int(np.clip(vel, 1, 127)), dur))

    def deg(self, d, octave=0):
        """Scale degree (0 = root, may be negative or > 6) to a MIDI key."""
        n = len(self.scale)
        o, i = divmod(d, n)
        return self.root + 12 * (o + octave) + self.scale[i]

    def chord(self, d, octave=0):
        return [self.deg(d, octave), self.deg(d + 2, octave), self.deg(d + 4, octave)]


# ------------------------------------------------------------------ building blocks
def pad(s, ch, prog_degs, vel=60, octave=-1, dur=None):
    """Sustained chords, one per bar."""
    for bar, d in enumerate(prog_degs):
        for k in s.chord(d, octave):
            s.note(ch, bar * s.beats, k, dur or s.beats, vel)

def arp(s, ch, prog_degs, pattern, step=0.5, vel=70, octave=0, ring=1.5):
    """Broken chords. pattern: indexes into chord tones (+3 = root up an octave)."""
    for bar, d in enumerate(prog_degs):
        tones = s.chord(d, octave) + [s.deg(d, octave + 1)]
        t = 0.0; i = 0
        while t < s.beats - 1e-6:
            s.note(ch, bar * s.beats + t, tones[pattern[i % len(pattern)]], ring, vel - (6 if i % 2 else 0))
            t += step; i += 1

def bass(s, ch, prog_degs, rhythm, vel=88, octave=-2, fifths=True):
    """Root on the downbeat, fifth on the off beats."""
    for bar, d in enumerate(prog_degs):
        for j, (t, dur) in enumerate(rhythm):
            k = s.deg(d + (4 if fifths and j % 2 == 1 else 0), octave)
            s.note(ch, bar * s.beats + t, k, dur, vel)

def drums(s, pattern, bars=None, vel=80, start=0):
    """pattern: list of (beat, drum, vel_scale) per bar."""
    for bar in range(start, bars if bars is not None else s.bars):
        for t, dk, vs in pattern:
            s.note(9, bar * s.beats + t, D[dk], 1.0, vel * vs)

def melody(s, ch, notes, start_bar=0, vel=96, octave=0, legato=1.0):
    """notes: list of (degree or None for rest, duration_beats). Degrees are scale steps."""
    t = start_bar * s.beats
    for d, dur in notes:
        if d is not None:
            s.note(ch, t, s.deg(d, octave), dur * legato, vel + int(s.rng.integers(-6, 6)))
        t += dur
    return t

def phrase_gen(s, prog_degs, rhythms, start_deg=4, end_on_root=True, leap=0.25):
    """Writes a singable line over a chord progression: chord tones on strong beats, stepwise
    motion between them, phrase ends settle on the chord's root or third."""
    out = []
    cur = start_deg
    for bar, d in enumerate(prog_degs):
        rh = rhythms[bar % len(rhythms)]
        tones = [d, d + 2, d + 4, d + 7]
        t = 0.0
        for i, dur in enumerate(rh):
            if dur < 0:
                out.append((None, -dur)); t += -dur; continue
            strong = abs(t - round(t)) < 1e-6 and int(round(t)) % 2 == 0
            last = bar == len(prog_degs) - 1 and i == len(rh) - 1
            if last and end_on_root:
                cands = [d, d + 7, d - 7]
            elif strong:
                cands = tones + [x - 7 for x in tones]
            else:
                cands = [cur - 1, cur + 1, cur - 2, cur + 2] if s.rng.random() > leap else tones
            cands = [c for c in cands if -3 <= c <= 11]
            cur = min(cands, key=lambda c: abs(c - cur) + s.rng.random() * 0.8)
            out.append((cur, dur)); t += dur
    return out


# ------------------------------------------------------------------ the tracks
def home_day():
    # "Hearthwind" - the home theme. G mixolydian, a lilting 3/4. Harp and flute with a lute-like guitar.
    s = Song('home_day', 92, 32, beats=3, root=67, mode='mixolydian', seed=4)
    s.inst(0, 'flute', 104); s.inst(1, 'harp', 92); s.inst(2, 'nylon', 70); s.inst(3, 'ac_bass', 92)
    s.inst(4, 'slow_strings', 56); s.inst(5, 'recorder', 88); s.inst(9, 0, 60)
    A = [0, 0, 3, 3, 6, 6, 4, 4] ; B = [3, 3, 0, 0, 5, 5, 4, 4]
    prog = A + B + A + [3, 3, 0, 6, 3, 4, 0, 0]
    pad(s, 4, prog, vel=48)
    arp(s, 1, prog, [0, 1, 2, 3, 2, 1], step=0.5, vel=66, octave=-1)
    bass(s, 3, prog, [(0, 1.5), (2, 1.0)], vel=80)
    for bar in range(32):
        if bar >= 8:
            for k in s.chord(prog[bar], -1)[1:]:
                s.note(2, bar * 3 + 1, k, 0.5, 52); s.note(2, bar * 3 + 2, k, 0.5, 46)
    # the tune (hand-written): question and answer, then a lift in the B section
    a1 = [(4, 1), (5, 0.5), (4, 0.5), (2, 1), (1, 1.5), (2, 0.5), (4, 1), (5, 2), (None, 1),
          (7, 1), (6, 0.5), (5, 0.5), (4, 1), (2, 1.5), (1, 0.5), (0, 1), (1, 2), (None, 1)]
    a2 = [(4, 1), (5, 0.5), (4, 0.5), (2, 1), (1, 1.5), (2, 0.5), (4, 1), (7, 2), (None, 1),
          (8, 1), (7, 0.5), (6, 0.5), (5, 1), (4, 1.5), (2, 0.5), (1, 1), (0, 3)]
    b1 = [(5, 1.5), (6, 0.5), (7, 1), (8, 2), (7, 1), (6, 1.5), (5, 0.5), (4, 1), (2, 3),
          (3, 1.5), (4, 0.5), (5, 1), (7, 2), (5, 1), (4, 1), (2, 1), (1, 1), (4, 3)]
    t = melody(s, 0, a1, 0, 100); t = melody(s, 0, a2, 8, 100)
    melody(s, 5, b1, 16, 92, octave=0)
    melody(s, 0, a2, 24, 104)
    # soft hand percussion in the second half
    drums(s, [(0, 'bongo_lo', 0.7), (1, 'shaker', 0.4), (1.5, 'shaker', 0.3), (2, 'bongo_hi', 0.5)], start=16)
    return s

def home_night():
    # The home theme at night: slower, ocarina over a music box and soft strings, no drums.
    s = Song('home_night', 72, 16, beats=3, root=62, mode='mixolydian', seed=5)
    s.inst(0, 'ocarina', 96); s.inst(1, 'music_box', 64); s.inst(4, 'slow_strings', 60); s.inst(3, 'fretless', 70)
    prog = [0, 0, 3, 3, 6, 6, 4, 4, 3, 3, 0, 6, 3, 4, 0, 0]
    pad(s, 4, prog, vel=52)
    arp(s, 1, prog, [0, 2, 3, 2], step=0.75, vel=52, octave=1, ring=2.0)
    bass(s, 3, prog, [(0, 3.0)], vel=70, fifths=False)
    a = [(4, 1), (5, 0.5), (4, 0.5), (2, 1), (1, 1.5), (2, 0.5), (4, 1), (5, 2), (None, 1),
         (7, 1), (6, 0.5), (5, 0.5), (4, 1), (2, 1.5), (1, 0.5), (0, 1), (1, 2), (None, 1)]
    b = [(4, 1), (5, 0.5), (4, 0.5), (2, 1), (1, 1.5), (2, 0.5), (4, 1), (7, 2), (None, 1),
         (8, 1), (7, 0.5), (6, 0.5), (5, 1), (4, 1.5), (2, 0.5), (1, 1), (0, 3)]
    melody(s, 0, a, 0, 86); melody(s, 0, b, 8, 86)
    return s

def orchard():
    # Orchard Isle: bright and pastoral, F major, recorder and strummed guitar with tambourine.
    s = Song('orchard', 112, 24, beats=4, root=65, mode='major', seed=7)
    s.inst(0, 'recorder', 100); s.inst(1, 'steel', 72); s.inst(3, 'ac_bass', 90); s.inst(4, 'strings', 50)
    s.inst(5, 'clarinet', 80)
    prog = [0, 3, 4, 0, 5, 3, 1, 4] * 3
    pad(s, 4, prog, vel=44)
    for bar, d in enumerate(prog):
        for t, v in [(0, 70), (1.5, 52), (2, 64), (3, 52), (3.5, 48)]:
            for k in s.chord(d, -1):
                s.note(1, bar * 4 + t, k, 0.45, v)
    bass(s, 3, prog, [(0, 1), (1, 0.5), (2, 1), (3, 0.5)], vel=84)
    rh = [[1, 0.5, 0.5, 1, 1], [1.5, 0.5, 1, 1], [0.5, 0.5, 1, 0.5, 0.5, 1], [2, 1, -1]]
    ph = phrase_gen(s, prog[:8], rh, start_deg=4)
    melody(s, 0, ph, 0, 98); melody(s, 0, ph, 16, 102)
    ph2 = phrase_gen(s, prog[8:16], [[1, 1, 1, 1], [0.5, 0.5, 1, 2]], start_deg=7)
    melody(s, 5, ph2, 8, 88, octave=-1)
    drums(s, [(0, 'tamb', 0.5), (1, 'tamb', 0.7), (2, 'tamb', 0.5), (3, 'tamb', 0.7), (0, 'bongo_lo', 0.6), (2.5, 'bongo_hi', 0.5)])
    return s

def meadow():
    # Kin Meadow: playful. C lydian flavour, pizzicato and piccolo, wood blocks.
    s = Song('meadow', 124, 24, beats=4, root=72, mode='lydian', seed=11)
    s.inst(0, 'piccolo', 92); s.inst(1, 'pizz', 90); s.inst(2, 'marimba', 70); s.inst(3, 'pizz', 86)
    s.inst(4, 'strings', 44)
    prog = [0, 1, 0, 4, 0, 1, 3, 4] * 3
    pad(s, 4, prog, vel=40, octave=-2)
    arp(s, 1, prog, [0, 1, 2, 1], step=0.5, vel=72, octave=-1, ring=0.4)
    bass(s, 3, prog, [(0, 0.5), (1, 0.5), (2, 0.5), (3, 0.5)], vel=88, octave=-2)
    rh = [[0.5, 0.5, 0.5, 0.5, 1, 1], [0.5, 0.5, 1, 1, -1], [0.25, 0.25, 0.5, 0.5, 0.5, 1, 1], [1, 0.5, 0.5, 2]]
    ph = phrase_gen(s, prog[:8], rh, start_deg=2, leap=0.4)
    melody(s, 0, ph, 0, 92, octave=-1); melody(s, 2, ph, 8, 80, octave=-1); melody(s, 0, ph, 16, 96, octave=-1)
    drums(s, [(0, 'wood_lo', 0.6), (1, 'wood_hi', 0.5), (1.5, 'wood_hi', 0.4), (2, 'wood_lo', 0.6), (3, 'wood_hi', 0.5), (3.5, 'triangle', 0.3)])
    return s

def summit():
    # Lookout Peak: open and windy. D dorian, pan flute over choir and harp.
    s = Song('summit', 78, 16, beats=4, root=62, mode='dorian', seed=13)
    s.inst(0, 'pan_flute', 100); s.inst(1, 'harp', 76); s.inst(4, 'choir', 58); s.inst(3, 'cello', 70)
    prog = [0, 6, 3, 0, 0, 6, 4, 0, 3, 3, 0, 0, 5, 6, 4, 0]
    pad(s, 4, prog, vel=50)
    arp(s, 1, prog, [0, 1, 2, 3, 2, 1, 0, 1], step=0.5, vel=60, octave=-1, ring=2.0)
    bass(s, 3, prog, [(0, 4.0)], vel=64, fifths=False)
    rh = [[2, 1, 1], [1.5, 0.5, 2], [1, 1, 1, 1], [3, -1]]
    ph = phrase_gen(s, prog, rh, start_deg=4, leap=0.3)
    melody(s, 0, ph, 0, 94)
    s.note(9, 0, D['crash'], 2, 30)
    return s

def match():
    # Expeditions: driving and tense. A minor, fiddle over pulsing strings, taiko and toms.
    s = Song('match', 132, 16, beats=4, root=69, mode='minor', seed=17)
    s.inst(0, 'fiddle', 96); s.inst(1, 'pizz', 84); s.inst(2, 'tremolo', 64); s.inst(3, 'cello', 96)
    s.inst(4, 'taiko', 110); s.inst(5, 'horn', 76)
    prog = [0, 0, 5, 5, 3, 3, 4, 4, 0, 0, 5, 5, 3, 4, 0, 0]
    pad(s, 2, prog, vel=56, octave=-1)
    for bar, d in enumerate(prog):
        for i in range(8):
            s.note(3, bar * 4 + i * 0.5, s.deg(d, -2) + (12 if i in (3, 7) else 0), 0.4, 92 - (10 if i % 2 else 0))
            s.note(1, bar * 4 + i * 0.5, s.chord(d, -1)[i % 3], 0.3, 62)
        s.note(4, bar * 4, 48, 1, 100); s.note(4, bar * 4 + 2.5, 48, 1, 84)
    drums(s, [(0, 'kick', 1.0), (1, 'snare', 0.6), (2, 'kick', 0.8), (2.5, 'kick', 0.6), (3, 'snare', 0.7),
              (0.5, 'hat', 0.4), (1.5, 'hat', 0.4), (2.5, 'hat', 0.4), (3.5, 'hat', 0.4)])
    for bar in (3, 7, 11, 15):
        for i in range(4): s.note(9, bar * 4 + 3 + i * 0.25, D['tom_hi'] - i * 2, 0.5, 70 + i * 8)
    rh = [[0.5, 0.5, 1, 0.5, 0.5, 1], [1.5, 0.5, 2], [0.5, 0.5, 0.5, 0.5, 1, 1], [3, -1]]
    ph = phrase_gen(s, prog[:8], rh, start_deg=4, leap=0.3)
    melody(s, 0, ph, 8, 98)
    melody(s, 5, [(0, 4), (2, 4), (-2, 4), (-1, 4)], 0, 70, octave=-1)
    return s

def hollow():
    # The Hollow (rare): dark and slow, phrygian, low strings and a distant choir.
    s = Song('hollow', 84, 16, beats=4, root=64, mode='phrygian', seed=19)
    s.inst(0, 'oboe', 86); s.inst(4, 'slow_strings', 62); s.inst(3, 'cello', 84); s.inst(5, 'oohs', 52); s.inst(6, 'timpani', 90)
    prog = [0, 1, 0, 6, 0, 1, 3, 0] * 2
    pad(s, 4, prog, vel=56, octave=-1); pad(s, 5, prog, vel=40, octave=0)
    for bar, d in enumerate(prog):
        s.note(3, bar * 4, s.deg(d, -2), 2.0, 86); s.note(3, bar * 4 + 2, s.deg(d, -2), 1.5, 70)
        if bar % 2 == 0: s.note(6, bar * 4, s.deg(0, -2), 1.0, 90)
    ph = phrase_gen(s, prog[:8], [[2, 1, 1], [3, -1], [1, 1, 2], [4]], start_deg=2, leap=0.2)
    melody(s, 0, ph, 8, 88)
    return s

def title():
    # The main theme: E dorian, horns and strings with harp, slow and wide.
    s = Song('title', 80, 16, beats=4, root=64, mode='dorian', seed=23)
    s.inst(0, 'horn', 96); s.inst(1, 'harp', 80); s.inst(4, 'strings', 64); s.inst(3, 'cello', 80); s.inst(5, 'flute', 84)
    prog = [0, 3, 6, 4, 0, 3, 5, 4, 2, 3, 0, 6, 3, 4, 0, 0]
    pad(s, 4, prog, vel=58)
    arp(s, 1, prog, [0, 1, 2, 3, 2, 1, 0, 1], step=0.5, vel=64, octave=-1, ring=2.0)
    bass(s, 3, prog, [(0, 2.0), (2, 2.0)], vel=76)
    theme = [(4, 2), (5, 1), (4, 1), (2, 3), (1, 1), (0, 2), (1, 1), (2, 1), (4, 4),
             (4, 2), (5, 1), (7, 1), (8, 3), (7, 1), (6, 2), (5, 1), (4, 1), (5, 4)]
    melody(s, 0, theme, 0, 92, octave=-1)
    melody(s, 5, theme, 8, 92)
    s.note(9, 0, D['crash'], 2, 40); s.note(9, 32, D['crash'], 2, 34)
    return s

def hub():
    # The hub town: a busy market. D mixolydian, fiddle and banjo, clapping and tambourine.
    s = Song('hub', 118, 16, beats=4, root=62, mode='mixolydian', seed=29)
    s.inst(0, 'fiddle', 98); s.inst(1, 'banjo', 76); s.inst(2, 'accordion', 64); s.inst(3, 'ac_bass', 92)
    prog = [0, 0, 6, 0, 3, 0, 6, 4, 0, 0, 6, 0, 3, 6, 4, 0]
    pad(s, 2, prog, vel=52)
    arp(s, 1, prog, [0, 2, 1, 2], step=0.5, vel=70, octave=0, ring=0.5)
    bass(s, 3, prog, [(0, 1), (1, 1), (2, 1), (3, 1)], vel=86)
    drums(s, [(0, 'kick', 0.7), (1, 'clap', 0.5), (2, 'kick', 0.6), (3, 'clap', 0.6), (0.5, 'tamb', 0.4), (1.5, 'tamb', 0.4), (2.5, 'tamb', 0.4), (3.5, 'tamb', 0.5)])
    rh = [[0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 1], [1, 0.5, 0.5, 2], [0.5, 0.5, 1, 0.5, 0.5, 1], [1, 1, 2]]
    ph = phrase_gen(s, prog[:8], rh, start_deg=4, leap=0.3)
    melody(s, 0, ph, 0, 96); melody(s, 0, phrase_gen(s, prog[8:], rh, start_deg=7, leap=0.3), 8, 98)
    return s

def guild():
    # Guild isles: warm and proud. Bb major, low brass and accordion in a march.
    s = Song('guild', 100, 16, beats=4, root=58, mode='major', seed=31)
    s.inst(0, 'trumpet', 82); s.inst(1, 'accordion', 70); s.inst(2, 'brass', 60); s.inst(3, 'tuba', 90); s.inst(5, 'clarinet', 84)
    prog = [0, 3, 4, 0, 5, 1, 4, 0, 3, 0, 1, 4, 0, 3, 4, 0]
    pad(s, 2, prog, vel=50, octave=0)
    bass(s, 3, prog, [(0, 1), (2, 1)], vel=88, octave=-2)
    for bar, d in enumerate(prog):
        for t in (1, 3):
            for k in s.chord(d, 0): s.note(1, bar * 4 + t, k, 0.6, 60)
    drums(s, [(0, 'kick', 0.6), (1, 'snare', 0.35), (2, 'kick', 0.5), (3, 'snare', 0.4), (3.75, 'snare', 0.25)])
    ph = phrase_gen(s, prog[:8], [[1, 1, 1, 1], [1.5, 0.5, 2], [1, 0.5, 0.5, 1, 1], [3, -1]], start_deg=4)
    melody(s, 5, ph, 0, 90); melody(s, 0, ph, 8, 88)
    return s

def lullaby():
    # A kin lullaby (rare, unlocked by evolving a kin): celesta and harp, very soft.
    s = Song('lullaby', 66, 8, beats=3, root=72, mode='major', seed=37)
    s.inst(0, 'celesta', 84); s.inst(1, 'harp', 60); s.inst(4, 'slow_strings', 44)
    prog = [0, 3, 4, 0, 5, 3, 4, 0]
    pad(s, 4, prog, vel=40, octave=-1)
    arp(s, 1, prog, [0, 1, 2], step=1.0, vel=54, octave=-1, ring=2.5)
    melody(s, 0, [(4, 2), (2, 1), (3, 2), (1, 1), (2, 1), (4, 1), (5, 1), (4, 3), (4, 2), (5, 1), (7, 2), (5, 1), (4, 1), (2, 1), (1, 1), (0, 3)], 0, 80)
    return s

TRACKS = {f.__name__: f for f in [home_day, home_night, orchard, meadow, summit, match, hollow, title, hub, guild, lullaby]}


# ------------------------------------------------------------------ rendering
def ensure_bank():
    if os.path.exists(SF2):
        return
    os.makedirs(CACHE, exist_ok=True)
    tmp = os.path.join(CACHE, 'gu')
    subprocess.run(['git', 'clone', '--depth', '1', 'https://github.com/mrbumpy409/GeneralUser-GS.git', tmp], check=True)
    os.replace(os.path.join(tmp, 'GeneralUser-GS.sf2'), SF2)

def reverb_ir(seconds=2.2, damp=4.0):
    n = int(SR * seconds); t = np.arange(n) / SR
    rng = np.random.default_rng(5)
    ir = rng.normal(0, 1, (n, 2)) * np.exp(-t * damp)[:, None]
    b, a = butter(1, 5000 / (SR / 2), 'low')
    ir = lfilter(b, a, ir, axis=0)
    ir[0] = 0
    return ir / np.sqrt(np.sum(ir ** 2, axis=0))

def render(s, tail=3.0, verb=0.22):
    import tinysoundfont
    syn = tinysoundfont.Synth(samplerate=SR, gain=-6)
    sfid = syn.sfload(SF2)
    for ch, prog in s.prog.items():
        syn.program_select(ch, sfid, 128 if ch == 9 else 0, prog, ch == 9)
        syn.control_change(ch, 7, s.vol.get(ch, 100))
    spb = 60.0 / s.bpm
    total = s.length_beats * spb + tail
    events = []
    for beat, ch, key, vel, dur in s.ev:
        events.append((beat * spb, 1, ch, key, vel))
        events.append(((beat + dur) * spb, 0, ch, key, 0))
    events.sort(key=lambda e: (e[0], e[1]))
    out = []
    now = 0.0
    for t, on, ch, key, vel in events:
        n = int((t - now) * SR)
        if n > 0:
            out.append(np.frombuffer(syn.generate(n), dtype=np.float32).reshape(-1, 2).copy())
            now += n / SR
        if on: syn.noteon(ch, key, vel)
        else: syn.noteoff(ch, key)
    n = int((total - now) * SR)
    if n > 0:
        out.append(np.frombuffer(syn.generate(n), dtype=np.float32).reshape(-1, 2).copy())
    x = np.concatenate(out)
    wet = fftconvolve(x, reverb_ir(), mode='full', axes=0)[:len(x)]
    x = x * (1 - verb) + wet * verb * 1.6
    # wrap the ringing tail onto the start so the loop is seamless
    L = int(s.length_beats * spb * SR)
    loop = x[:L].copy()
    tl = x[L:]
    loop[:len(tl)] += tl[:L]
    return loop

def write(name, x):
    x = x / (np.max(np.abs(x)) or 1) * 0.89
    tmp = tempfile.NamedTemporaryFile(suffix='.wav', delete=False).name
    with wave.open(tmp, 'wb') as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())
    out = os.path.join(OUT, 'music_%s.ogg' % name)
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', tmp, '-c:a', 'libvorbis', '-q:a', '2', out], check=True)
    os.unlink(tmp)
    print('%-11s %5.1fs %4d KB' % (name, len(x) / SR, os.path.getsize(out) // 1024))

if __name__ == '__main__':
    ensure_bank()
    names = sys.argv[1:] or list(TRACKS)
    for n in names:
        write(n, render(TRACKS[n]()))
