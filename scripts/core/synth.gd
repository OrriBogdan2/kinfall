class_name Synth
## Sounds made in code (glider skins, the home whistle), in the same soft palette as tools/gen_sfx.py:
## smooth fade-ins so nothing clicks, band-passed noise instead of raw hiss, sines instead of square
## waves, and levelled to a modest loudness that sits under the music.

const RATE := 22050

## A band-pass whose centre can move every sample (a state-variable filter); one per voice.
class BandPass:
	var low := 0.0
	var band := 0.0
	func step(x: float, hz: float, q := 1.2) -> float:
		var f := 2.0 * sin(PI * minf(hz, RATE / 6.5) / RATE)
		low += f * band
		var high := x - low - band / q
		band += f * high
		return band

## A raised-cosine fade-in over a seconds.
static func fade_in(t: float, a: float) -> float:
	return 1.0 if t >= a else 0.5 - 0.5 * cos(PI * t / a)

## Fades in over a, out over the last r seconds of dur.
static func swell(t: float, dur: float, a: float, r: float) -> float:
	return fade_in(t, a) * fade_in(maxf(0.0, dur - t), r)

## A gate that opens in soft little bursts (for rustles and crackles): call once per sample.
class Grains:
	var g := 0.0
	var target := 0.0
	var rng: RandomNumberGenerator
	var chance := 0.004
	func _init(r: RandomNumberGenerator, per_sample: float) -> void:
		rng = r; chance = per_sample
	func step() -> float:
		if rng.randf() < chance:
			target = rng.randf_range(0.4, 1.0)
		target *= 0.994
		g += (target - g) * 0.03       # about a 2 ms rise: soft, never a click
		return g

## Levels a buffer to an RMS loudness (dB) under a soft ceiling, fades its tail, and makes a stream.
static func to_wav(buf: PackedFloat32Array, rms_db := -21.0, ceil_db := -4.0) -> AudioStreamWAV:
	var n := buf.size()
	var pk := 0.0
	for s in buf: pk = maxf(pk, absf(s))
	var sum := 0.0; var cnt := 0
	for s in buf:
		if absf(s) > pk * 0.01:
			sum += s * s; cnt += 1
	var k := db_to_linear(rms_db) / maxf(sqrt(sum / maxi(1, cnt)), 0.000001)
	var c := db_to_linear(ceil_db)
	var knee := c * 0.7
	var fo := mini(n, int(RATE * 0.02))
	var data := PackedByteArray(); data.resize(n * 2)
	for i in n:
		var v := buf[i] * k
		if absf(v) > knee:
			v = signf(v) * (knee + (c - knee) * tanh((absf(v) - knee) / (c - knee)))
		if i < 32: v *= fade_in(float(i), 32.0)
		if i >= n - fo: v *= 0.5 + 0.5 * cos(PI * float(i - (n - fo)) / fo)
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w

## A glider opening (an airy whoosh as the canopy fills) or folding away (a softer falling swish),
## flavoured by its skin's sound set.
static func glider(set: String, close: bool) -> AudioStreamWAV:
	var dur := 0.34 if close else 0.6
	var n := int(RATE * dur)
	var buf := PackedFloat32Array(); buf.resize(n)
	var rng := RandomNumberGenerator.new(); rng.seed = hash(set) + (7 if close else 0)
	var air := BandPass.new()
	var extra := BandPass.new()
	var crk := BandPass.new()
	var grains := Grains.new(rng, 0.006 if set == "rustle" else 0.0025)
	var lo := 0.0
	# the whoosh's centre: up and back down as the canopy opens; just down as it folds
	var c0 := 260.0; var c1 := 900.0; var c2 := 360.0
	match set:
		"leather", "flame": c0 = 200.0; c1 = 650.0; c2 = 260.0
		"chime", "zap": c0 = 300.0; c1 = 1000.0; c2 = 420.0
	for i in n:
		var t := float(i) / RATE
		var u := t / dur
		var noise := rng.randf_range(-1.0, 1.0)
		var centre := lerpf(c1, c2, u) if close else (lerpf(c0, c1, u / 0.4) if u < 0.4 else lerpf(c1, c2, (u - 0.4) / 0.6))
		var v := air.step(noise, centre, 1.0) * swell(t, dur, 0.035 if close else 0.06, dur * 0.6)
		match set:
			"cloth":
				# the canopy catching air: a soft low fwump under the whoosh
				var tf := t - 0.08
				if tf > 0.0 and not close:
					v += sin(TAU * lerpf(120.0, 80.0, minf(1.0, tf / 0.2)) * tf) * fade_in(tf, 0.01) * exp(-tf / 0.07) * 0.35
			"rustle":
				# a giant leaf: a soft leafy rustle riding the air
				v = v * 0.7 + extra.step(noise, 1300.0, 1.6) * grains.step() * 1.0 * swell(t, dur, 0.02, dur * 0.5)
			"leather":
				# two slow, soft flaps of a wing
				for at in ([0.03, 0.17] if not close else [0.04]):
					var tf: float = t - at
					if tf > 0.0:
						v += (sin(TAU * 95.0 * tf) * 0.5 + extra.step(noise, 320.0, 0.9) * 0.6) * fade_in(tf, 0.012) * exp(-tf / 0.05) * 0.6
			"chime":
				# glass panels unfolding: three soft chimes (two, falling, as it folds)
				v *= 0.55
				var notes := [[784.0, 0.03], [988.0, 0.1], [1175.0, 0.17]] if not close else [[988.0, 0.02], [784.0, 0.09]]
				for nt in notes:
					var tf: float = t - float(nt[1])
					if tf > 0.0:
						var f: float = nt[0]
						v += (sin(TAU * f * tf) + 0.15 * sin(TAU * f * 2.76 * tf) * exp(-tf / 0.05)) * fade_in(tf, 0.006) * exp(-tf / 0.16) * 0.22
			"flame":
				# a warm whump of flame with a few soft crackles
				v = v * 0.8 + extra.step(noise, lerpf(250.0, 650.0, minf(1.0, u * 2.5)), 0.8) * swell(t, dur, 0.04, dur * 0.6) * 0.9
				v += crk.step(noise, 1300.0, 1.5) * grains.step() * 0.6 * swell(t, dur, 0.03, dur * 0.5)
			"flutter":
				# moth wings beating as they open
				var beat := pow(0.5 + 0.5 * sin(TAU * 13.0 * t), 1.5)
				v *= 0.45 + 0.75 * beat
			"zap":
				# static in the canopy: a low rumble with soft crackles, not a buzz
				v = v * 0.7 + extra.step(noise, 140.0, 0.8) * swell(t, dur, 0.03, dur * 0.6) * 1.2
				v += crk.step(noise, 1600.0, 1.5) * grains.step() * 0.8 * swell(t, dur, 0.03, dur * 0.5)
		lo += (v - lo) * 0.45      # round off the top end (about 3 kHz)
		buf[i] = lo
	return to_wav(buf, -25.0 if close else -21.0)

## The home whistle that calls your kin: a soft, breathy two-note "fwee-fweeoo".
static func whistle() -> AudioStreamWAV:
	var notes := [[880.0, 1040.0, 0.15], [0.0, 0.0, 0.05], [990.0, 1320.0, 0.28]]
	var total := 0.0
	for nt in notes: total += float(nt[2])
	var buf := PackedFloat32Array(); buf.resize(int(RATE * total))
	var rng := RandomNumberGenerator.new(); rng.seed = 5
	var breath := BandPass.new()
	var ph := 0.0
	var i := 0
	for nt in notes:
		var cnt := int(RATE * float(nt[2]))
		for j in cnt:
			var t := float(j) / RATE
			var u := float(j) / cnt
			var f := lerpf(float(nt[0]), float(nt[1]), u * u * (3.0 - 2.0 * u))
			var v := 0.0
			if f > 0.0:
				ph += TAU * f * (1.0 + 0.006 * sin(TAU * 5.5 * t)) / RATE
				var e := swell(t, float(nt[2]), 0.03, 0.06)
				v = (sin(ph) + 0.06 * sin(ph * 2.0)) * e + breath.step(rng.randf_range(-1.0, 1.0), f, 4.0) * e * 0.5
			if i < buf.size(): buf[i] = v
			i += 1
	return to_wav(buf, -20.0)
