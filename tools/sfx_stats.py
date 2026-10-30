"""Measures sound effects so a mix pass can be judged by numbers, not just by ear.

    python3 tools/sfx_stats.py [dir=audio] [--json out.json] [--compare before.json]

Per .wav file it reports:
  peak   peak level in dBFS
  rms    RMS level (dBFS) over the part of the sound that is above -40 dB of its peak
  atk    attack: ms for the 1 ms RMS envelope to rise from 10% to 90% of its maximum
  edge   the very first 1 ms's level relative to the peak (dB): high means it starts with a click
  cent   spectral centroid in Hz (energy weighted): lower is darker and calmer
  hf     share of energy above 4 kHz, in percent
"""
import json, os, sys, wave
import numpy as np


def load(path):
    with wave.open(path, 'rb') as w:
        sr = w.getframerate(); ch = w.getnchannels(); sw = w.getsampwidth()
        raw = w.readframes(w.getnframes())
    x = np.frombuffer(raw, dtype=np.int16 if sw == 2 else np.uint8).astype(float)
    x = x / 32768.0 if sw == 2 else (x - 128) / 128.0
    if ch > 1:
        x = x.reshape(-1, ch).mean(axis=1)
    return x, sr


def stats(x, sr):
    pk = float(np.max(np.abs(x))) if len(x) else 0.0
    if pk <= 1e-9:
        return {"peak": -120.0, "rms": -120.0, "atk": 0.0, "edge": -120.0, "cent": 0.0, "hf": 0.0, "dur": len(x) / sr}
    win = max(1, int(sr * 0.001))
    envsq = np.convolve(x * x, np.ones(win) / win, mode='same')
    env = np.sqrt(envsq)
    emax = env.max()
    i10 = int(np.argmax(env >= 0.1 * emax)); i90 = int(np.argmax(env >= 0.9 * emax))
    active = np.abs(x) > pk * 0.01
    rms = float(np.sqrt(np.mean(x[active] ** 2))) if active.any() else 0.0
    edge = float(np.max(np.abs(x[:win]))) / pk
    spec = np.abs(np.fft.rfft(x * np.hanning(len(x)))) ** 2
    f = np.fft.rfftfreq(len(x), 1.0 / sr)
    tot = spec.sum() or 1.0
    return {
        "peak": round(20 * np.log10(pk), 1),
        "rms": round(20 * np.log10(max(rms, 1e-9)), 1),
        "atk": round((i90 - i10) / sr * 1000.0, 1),
        "edge": round(20 * np.log10(max(edge, 1e-6)), 1),
        "cent": round(float((spec * f).sum() / tot)),
        "hf": round(float(spec[f > 4000].sum() / tot) * 100.0, 1),
        "dur": round(len(x) / sr, 3),
    }


def main():
    args = sys.argv[1:]
    out = cmp = None
    if '--json' in args:
        i = args.index('--json'); out = args[i + 1]; del args[i:i + 2]
    if '--compare' in args:
        i = args.index('--compare'); cmp = json.load(open(args[i + 1])); del args[i:i + 2]
    d = args[0] if args else os.path.join(os.path.dirname(__file__), '..', 'audio')
    res = {}
    for fn in sorted(os.listdir(d)):
        if fn.endswith('.wav'):
            res[fn[:-4]] = stats(*load(os.path.join(d, fn)))
    keys = ["peak", "rms", "atk", "edge", "cent", "hf"]
    print("%-16s " % "sound" + " ".join("%7s" % k for k in keys) + ("   (before)" if cmp else ""))
    for k, s in res.items():
        line = "%-16s " % k + " ".join("%7s" % s[c] for c in keys)
        if cmp and k in cmp:
            line += "   " + " ".join("%7s" % cmp[k][c] for c in keys)
        print(line)
    if res:
        avg = {c: float(np.mean([s[c] for s in res.values()])) for c in keys}
        print("%-16s " % "MEAN" + " ".join("%7.1f" % avg[c] for c in keys))
        if cmp:
            common = [k for k in res if k in cmp]
            b = {c: float(np.mean([cmp[k][c] for k in common])) for c in keys}
            print("%-16s " % "MEAN before" + " ".join("%7.1f" % b[c] for c in keys))
    if out:
        json.dump(res, open(out, 'w'), indent=1)


if __name__ == '__main__':
    main()
