"""Composes the game's music and ambience loops procedurally and writes them to audio/*.ogg.

Everything is synthesized here (no samples), so the audio is original and open to ship.
Tracks loop seamlessly: each is a whole number of bars and notes that ring past the end are
wrapped back to the start.
"""
import numpy as np, os, subprocess, tempfile, wave
from scipy.signal import lfilter, butter

SR = 32000
OUT = os.path.join(os.path.dirname(__file__), '..', 'audio')
rng = np.random.default_rng(11)

def note_hz(n):  # midi note to Hz
    return 440.0 * 2 ** ((n - 69) / 12)

def lowpass(x, hz, order=2):
    b, a = butter(order, hz / (SR / 2), 'low'); return lfilter(b, a, x)

def highpass(x, hz, order=2):
    b, a = butter(order, hz / (SR / 2), 'high'); return lfilter(b, a, x)

def adsr(n, a=0.01, d=0.1, s=0.6, r=0.2):
    t = np.arange(n) / SR; dur = n / SR
    e = np.where(t < a, t / max(a, 1e-4), s + (1 - s) * np.exp(-(t - a) / max(d, 1e-4)))
    rel = np.clip((dur - t) / max(r, 1e-4), 0, 1)
    return e * rel

def osc(hz, n, kind='sine', detune=0.0):
    t = np.arange(n) / SR
    ph = 2 * np.pi * hz * (1 + detune) * t
    if kind == 'sine': return np.sin(ph)
    if kind == 'tri': return 2 / np.pi * np.arcsin(np.sin(ph))
    if kind == 'saw': return 2 * ((hz * (1 + detune) * t) % 1) - 1
    if kind == 'sq': return np.sign(np.sin(ph))
    raise ValueError(kind)

def pluck(hz, n, bright=0.5):
    """Karplus-Strong plucked string."""
    period = max(2, int(SR / hz))
    buf = rng.uniform(-1, 1, period)
    out = np.zeros(n)
    k = 0.5 * (0.996 - 0.01 * (1 - bright))
    for i in range(n):
        v = buf[i % period]
        out[i] = v
        buf[i % period] = k * (v + buf[(i + 1) % period]) * 1.0
    return out

class Track:
    def __init__(self, bpm, bars, beats=4):
        self.bpm = bpm; self.beat = 60.0 / bpm
        self.len = int(SR * self.beat * beats * bars)
        self.buf = np.zeros(self.len)
    def at(self, beat_pos):
        return int(beat_pos * self.beat * SR)
    def add(self, start_beat, sig, gain=1.0):
        s = self.at(start_beat) % self.len
        n = len(sig)
        end = s + n
        if end <= self.len:
            self.buf[s:end] += sig * gain
        else:
            first = self.len - s
            self.buf[s:] += sig[:first] * gain
            rest = sig[first:]
            while len(rest) > 0:
                m = min(len(rest), self.len)
                self.buf[:m] += rest[:m] * gain
                rest = rest[m:]

def kick(n=None):
    n = n or int(SR * 0.3); t = np.arange(n) / SR
    f = 50 + 90 * np.exp(-t * 30)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9)

def snare():
    n = int(SR * 0.22); t = np.arange(n) / SR
    return (highpass(rng.uniform(-1, 1, n), 1500) * 0.7 + np.sin(2 * np.pi * 190 * t) * 0.5) * np.exp(-t * 18)

def hat(open_=False):
    n = int(SR * (0.12 if open_ else 0.04)); t = np.arange(n) / SR
    return highpass(rng.uniform(-1, 1, n), 7000) * np.exp(-t * (18 if open_ else 70))

def shaker():
    n = int(SR * 0.08); t = np.arange(n) / SR
    return highpass(rng.uniform(-1, 1, n), 5000) * np.sin(np.pi * t / t[-1]) * 0.6

def pad(notes, n, cutoff=1800):
    s = np.zeros(n)
    for m in notes:
        for d in (-0.004, 0.0, 0.005):
            s += osc(note_hz(m), n, 'saw', d)
    s = lowpass(s / (len(notes) * 3), cutoff)
    return s * adsr(n, 0.6, 1.0, 0.85, 0.8)

def bell(m, n):
    t = np.arange(n) / SR
    hz = note_hz(m)
    s = np.sin(2 * np.pi * hz * t) + 0.35 * np.sin(2 * np.pi * hz * 2.76 * t) + 0.15 * np.sin(2 * np.pi * hz * 5.4 * t)
    return s * np.exp(-t * 3.2)

def write_ogg(name, x, gain=0.85):
    x = np.asarray(x, float)
    x = x / (np.max(np.abs(x)) or 1) * gain
    tmp = tempfile.NamedTemporaryFile(suffix='.wav', delete=False).name
    with wave.open(tmp, 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())
    out = os.path.join(OUT, name + '.ogg')
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', tmp, '-c:a', 'libvorbis', '-q:a', '3', out], check=True)
    os.unlink(tmp)
    print(name, round(len(x) / SR, 1), 's', os.path.getsize(out) // 1024, 'KB')

# ---------------------------------------------------------------- home: warm and easy, F major
def home_theme():
    T = Track(bpm=88, bars=16)
    prog = [[53, 57, 60, 65], [50, 53, 57, 62], [46, 50, 53, 58], [48, 52, 55, 60]]   # F  Dm  Bb  C
    bass = [41, 38, 46, 36]
    bar_n = T.at(4)
    for bar in range(16):
        ch = prog[bar % 4]
        T.add(bar * 4, pad(ch, bar_n + T.at(1), 1400), 0.22)
        T.add(bar * 4, osc(note_hz(bass[bar % 4]), T.at(3.5), 'tri') * adsr(T.at(3.5), 0.02, 0.4, 0.6, 0.3), 0.32)
        # plucked arpeggio, eighths
        pattern = [0, 2, 1, 3, 2, 1, 3, 2]
        for i, p in enumerate(pattern):
            m = ch[p] + 12
            T.add(bar * 4 + i * 0.5, pluck(note_hz(m), T.at(1.2), 0.6) * adsr(T.at(1.2), 0.002, 0.3, 0.4, 0.4), 0.16)
        # soft shaker on the off-beats, kick on 1 and 3 in the second half
        for b in range(8):
            T.add(bar * 4 + b * 0.5 + 0.25, shaker(), 0.05)
        if bar >= 8:
            T.add(bar * 4, kick(), 0.18); T.add(bar * 4 + 2, kick(), 0.14)
    # a bell melody over the second half, drawn from chord tones
    mel_rng = np.random.default_rng(3)
    for bar in range(4, 16):
        ch = prog[bar % 4]
        beats = [0, 1.5, 2, 3] if bar % 2 == 0 else [0, 1, 2.5]
        for b in beats:
            m = ch[mel_rng.integers(1, 4)] + 24
            T.add(bar * 4 + b, bell(m, T.at(2)), 0.11)
    x = T.buf
    return lowpass(x, 9000)

# ---------------------------------------------------------------- match: driving, A minor
def match_theme():
    T = Track(bpm=126, bars=16)
    prog = [[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62]]    # Am  F  C  G
    roots = [45, 41, 36, 43]
    for bar in range(16):
        ch = prog[bar % 4]; r = roots[bar % 4]
        T.add(bar * 4, pad([n + 12 for n in ch], T.at(4.5), 2200), 0.13)
        # pulsing bass eighths
        for i in range(8):
            m = r - 12 + (12 if i in (3, 7) else 0)
            n = T.at(0.45)
            sig = lowpass(osc(note_hz(m), n, 'saw') * 0.7 + osc(note_hz(m), n, 'sq') * 0.3, 900) * adsr(n, 0.005, 0.1, 0.5, 0.05)
            T.add(bar * 4 + i * 0.5, sig, 0.3)
        # drums: kick on beats, snare on 2 and 4, hats on eighths, fills every 4 bars
        for b in range(4):
            T.add(bar * 4 + b, kick(), 0.5)
            if b in (1, 3): T.add(bar * 4 + b, snare(), 0.26)
        for i in range(8):
            T.add(bar * 4 + i * 0.5, hat(i % 2 == 1 and bar % 2 == 1), 0.07)
        if bar % 4 == 3:
            for i in range(4): T.add(bar * 4 + 3 + i * 0.25, snare(), 0.12 + i * 0.03)
        # arpeggiated lead in the second half
        if bar >= 8:
            for i in range(16):
                m = ch[(i * 2 + bar) % 3] + 24 + (12 if i % 8 == 7 else 0)
                n = T.at(0.25)
                sig = lowpass(osc(note_hz(m), n, 'sq'), 3500) * adsr(n, 0.002, 0.06, 0.3, 0.04)
                T.add(bar * 4 + i * 0.25, sig, 0.06)
    return T.buf

# ---------------------------------------------------------------- title: slow, airy
def title_theme():
    T = Track(bpm=70, bars=8)
    prog = [[57, 60, 64, 69], [53, 57, 60, 65], [55, 59, 62, 67], [52, 55, 59, 64]]   # Am F G Em
    for bar in range(8):
        T.add(bar * 4, pad(prog[bar % 4], T.at(5), 1100), 0.3)
        for b in (0, 1.5, 3):
            T.add(bar * 4 + b, bell(prog[bar % 4][int(b) % 4] + 12, T.at(3)), 0.08)
    return lowpass(T.buf, 7000)

# ---------------------------------------------------------------- ambience
def wind(seconds=12.0, dark=False):
    n = int(SR * seconds)
    x = rng.normal(0, 1, n)
    x = lowpass(x, 500 if dark else 900)
    t = np.arange(n) / SR
    swell = 0.6 + 0.4 * np.sin(2 * np.pi * t / seconds * 2) * np.sin(2 * np.pi * t / seconds * 3 + 1)
    x = x * swell
    # crossfade the ends so it loops
    f = int(SR * 1.0)
    x[:f] = x[:f] * np.linspace(0, 1, f) + x[-f:] * np.linspace(1, 0, f)
    return x[:-f]

def birds(seconds=14.0):
    n = int(SR * seconds)
    x = wind(seconds + 1.0) * 0.25
    x = x[:n] if len(x) >= n else np.pad(x, (0, n - len(x)))
    for _ in range(14):
        s = rng.integers(0, n - SR)
        base = rng.uniform(2200, 3600)
        for k in range(rng.integers(2, 5)):
            m = int(SR * 0.09); t = np.arange(m) / SR
            f = base * (1 + 0.25 * np.sin(np.pi * t / t[-1]))
            c = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * t / t[-1]) * 0.25
            st = s + k * int(SR * 0.13)
            if st + m < n: x[st:st + m] += c
    return x

def rain(seconds=10.0):
    n = int(SR * seconds)
    x = lowpass(highpass(rng.normal(0, 1, n), 400), 5000) * 0.5
    for _ in range(int(seconds * 40)):
        s = rng.integers(0, n - 400); m = rng.integers(60, 240); t = np.arange(m) / SR
        x[s:s + m] += highpass(rng.uniform(-1, 1, m), 2000) * np.exp(-t * 300) * rng.uniform(0.3, 1.0)
    f = int(SR * 1.0)
    x[:f] = x[:f] * np.linspace(0, 1, f) + x[-f:] * np.linspace(1, 0, f)
    return x[:-f]

def footstep(seed):
    r = np.random.default_rng(seed)
    n = int(SR * 0.09); t = np.arange(n) / SR
    x = lowpass(r.uniform(-1, 1, n), 1200 + seed * 300) * np.exp(-t * 45)
    x += np.sin(2 * np.pi * (90 + seed * 15) * t) * np.exp(-t * 60) * 0.5
    return x

def wav_out(name, x, gain=0.8):
    x = np.asarray(x, float); x = x / (np.max(np.abs(x)) or 1) * gain
    with wave.open(os.path.join(OUT, name + '.wav'), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())

if __name__ == '__main__':
    write_ogg('music_home', home_theme(), 0.8)
    write_ogg('music_match', match_theme(), 0.8)
    write_ogg('music_title', title_theme(), 0.75)
    write_ogg('amb_home', birds(), 0.6)
    write_ogg('amb_match', wind(14.0, True), 0.6)
    write_ogg('amb_rain', rain(), 0.55)
    for i in range(3):
        wav_out('step%d' % i, footstep(i), 0.7)
    print('done')
