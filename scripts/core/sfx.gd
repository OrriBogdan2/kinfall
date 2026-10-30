extends Node
## Plays the synthesized sound effects (made by tools/gen_sfx.py). Positional sounds fade with distance
## from the camera focus, and far ones are also muffled (they go through a low-passed bus), so a fight
## across the map stays soft. The SFX bus has a gentle compressor, a touch of room reverb and a
## limiter, so a crowd of sounds blends together instead of piling up into peaks.

const NAMES := ["smg", "rifle", "thump", "boom", "hit", "crit", "kill", "knock", "hurt", "dash", "jump", "land", "grab",
	"throw", "kinhit", "skill", "kin_happy", "kin_unsure", "kin_alert", "recall", "pickup", "catch", "warn", "portal",
	"revive", "click", "reload", "shield", "cloak", "heal", "fall", "plant", "harvest", "ping", "glide", "build", "unlock", "whoosh", "step0", "step1", "step2", "hover", "zap", "bond", "ult", "combo", "swap", "horn", "rail",
	"swipe", "cleave", "charge", "k_venom", "k_spore", "k_gravity", "k_prism", "k_lunar", "k_echo"]
const POOL := 24
## Sounds that only exist as several takes (monster voices, little pops); one is picked at random.
const VOICES := ["v_skitter", "v_spitter", "v_brute", "v_bomber", "v_sentinel", "v_glimmer", "v_warden", "die_small", "die_big"]
## The shortest gap before the same sound can play again, so a crowd doesn't machine-gun it.
const MIN_GAP := {"hit": 45, "crit": 60, "hurt": 120, "kinhit": 60, "die_small": 90, "die_big": 150, "land": 80, "step0": 60, "step1": 60, "step2": 60}
## On top of that, at most STACK_MAX of one sound start within STACK_MS, each extra one a little quieter.
const STACK_MAX := 3
const STACK_MS := 90
const STACK_DB := 3.5
## Distance falloff: full volume within NEAR metres, then a gentle roll-off; muffled beyond FAR.
const NEAR := 3.5
const FAR := 9.0
var last_take := {}
var recent := {}          # sound -> start times (ms) still inside the stacking window

var streams := {}
var players: Array[AudioStreamPlayer] = []
var next := 0
var listener := Vector3.ZERO   # set by the camera each frame
var hear_range := 22.0
var last_played := {}
var rng := RandomNumberGenerator.new()

signal new_track(name: String)
var music: Array[AudioStreamPlayer] = []   # two players so tracks can crossfade
var music_i := 0
var music_name := ""
var amb: AudioStreamPlayer
var amb_name := ""
var music_bus := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bn in ["Music", "SFX", "Ambience", "SFXFar"]:
		AudioServer.add_bus()
		var bi := AudioServer.bus_count - 1
		AudioServer.set_bus_name(bi, bn)
		AudioServer.set_bus_send(bi, "SFX" if bn == "SFXFar" else "Master")
	music_bus = AudioServer.get_bus_index("Music")
	_setup_mix()
	for i in 2:
		var mp := AudioStreamPlayer.new(); mp.bus = "Music"; mp.volume_db = -80.0
		add_child(mp); music.append(mp)
	amb = AudioStreamPlayer.new(); amb.bus = "Ambience"; amb.volume_db = -80.0
	add_child(amb)
	for n in NAMES + VOICES:
		var takes: Array = []
		var s = load("res://audio/%s.wav" % n) if ResourceLoader.exists("res://audio/%s.wav" % n) else null
		if s: takes.append(s)
		for i in range(1, 5):
			var path := "res://audio/%s_%d.wav" % [n, i]
			if ResourceLoader.exists(path):
				takes.append(load(path))
		if takes.size() == 1:
			streams[n] = takes[0]
		elif takes.size() > 1:
			streams[n] = takes
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		players.append(p)

## The effects on the buses: SFX gets a soft compressor, a little room and a limiter; far-away sounds
## are low-passed on their way into it; the master has a last safety limiter.
func _setup_mix() -> void:
	var sfx := AudioServer.get_bus_index("SFX")
	var comp := AudioEffectCompressor.new()
	comp.threshold = -18.0
	comp.ratio = 3.0
	comp.attack_us = 8000.0
	comp.release_ms = 180.0
	AudioServer.add_bus_effect(sfx, comp)
	var rv := AudioEffectReverb.new()
	rv.room_size = 0.35
	rv.damping = 0.75
	rv.spread = 0.6
	rv.hipass = 0.25
	rv.predelay_msec = 18.0
	rv.dry = 1.0
	rv.wet = 0.1
	AudioServer.add_bus_effect(sfx, rv)
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -2.0
	AudioServer.add_bus_effect(sfx, lim)
	var far := AudioServer.get_bus_index("SFXFar")
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 1800.0
	AudioServer.add_bus_effect(far, lp)
	var mlim := AudioEffectHardLimiter.new()
	mlim.ceiling_db = -0.5
	AudioServer.add_bus_effect(0, mlim)

func set_bus(bus_name: String, v: float) -> void:
	var i := AudioServer.get_bus_index(bus_name)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))

func _loop_stream(path: String) -> AudioStream:
	var st = load(path)
	if st is AudioStreamOggVorbis:
		st.loop = true
	return st

## Crossfades to another music track ("home", "match", "title"), or to silence with "".
var music_lock := ""
var _music_tw: Tween      # a track picked in the music list plays until cleared

func play_music(name: String, fade := 1.5) -> void:
	if name == music_name:
		return
	music_name = name
	if name != "" and not Save.d.get("music", []).has(name):
		# first time hearing this one: it joins the music list
		if not Save.d.has("music"): Save.d["music"] = []
		Save.d["music"].append(name)
		Save.save_game()
		new_track.emit(name)
	var old := music[music_i]
	music_i = 1 - music_i
	var nw := music[music_i]
	# a fade still running would keep pushing its track back up, so it stops here
	if _music_tw and _music_tw.is_valid():
		_music_tw.kill()
	var tw := create_tween().set_parallel(true)
	_music_tw = tw
	tw.tween_property(old, "volume_db", -80.0, fade).set_trans(Tween.TRANS_SINE)
	tw.chain().tween_callback(old.stop)
	if name != "":
		nw.stream = _loop_stream("res://audio/music_%s.ogg" % name)
		nw.volume_db = -40.0
		nw.play()
		tw.tween_property(nw, "volume_db", -9.0, fade).set_trans(Tween.TRANS_SINE)

func play_ambience(name: String) -> void:
	if name == amb_name:
		return
	amb_name = name
	if name == "":
		create_tween().tween_property(amb, "volume_db", -80.0, 1.0)
		return
	amb.stream = _loop_stream("res://audio/amb_%s.ogg" % name)
	amb.volume_db = -40.0
	amb.play()
	create_tween().tween_property(amb, "volume_db", -14.0, 2.0)

## Softens the music for a moment, e.g. under a big slow-motion beat (eased, never a sudden drop).
func duck(seconds: float) -> void:
	var p := music[music_i]
	var tw := create_tween()
	tw.tween_property(p, "volume_db", -17.0, 0.18).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(seconds)
	tw.tween_property(p, "volume_db", -9.0, 0.8).set_trans(Tween.TRANS_SINE)

var _step_i := 0
func step(pos = null, vol := -16.0) -> void:
	_step_i = (_step_i + 1) % 3
	play("step%d" % _step_i, pos, vol, 0.12)

func has(sname: String) -> bool:
	return streams.has(sname)

## How much quieter (dB) a sound at pos is for the listener, or NAN when it's out of earshot.
func _distance_db(pos) -> float:
	if pos == null:
		return 0.0
	var dist := Vector2(pos.x - listener.x, pos.z - listener.z).length()
	if dist > hear_range:
		return NAN
	# a soft inverse-distance roll-off (about -8 dB by 10 m), easing to silence at the edge of hearing
	var db := -20.0 * log(1.0 + maxf(0.0, dist - NEAR) / 5.0) / log(10.0)
	var edge := 1.0 - smoothstep(hear_range * 0.7, hear_range, dist)
	return db + linear_to_db(maxf(edge, 0.001))

## A free voice from the pool, so a new sound doesn't cut one that's still ringing (the oldest if all are busy).
func _voice(pos) -> AudioStreamPlayer:
	var p: AudioStreamPlayer = null
	for k in POOL:
		var c := players[(next + k) % POOL]
		if not c.playing:
			p = c
			next = (next + k + 1) % POOL
			break
	if p == null:
		p = players[next]
		next = (next + 1) % POOL
	var far := pos != null and Vector2(pos.x - listener.x, pos.z - listener.z).length() > FAR
	p.bus = "SFXFar" if far else "SFX"
	return p

## pos: world position, or null for UI sounds. Repeats of one sound within 30ms are merged, and a
## burst of the same sound is capped and stacked quieter.
func play(sname: String, pos = null, vol_db := 0.0, pitch_var := 0.07, pitch := 1.0) -> void:
	if not streams.has(sname):
		return
	var now := Time.get_ticks_msec()
	var gap: int = 260 if sname.begins_with("v_") else int(MIN_GAP.get(sname, 30))
	if now - int(last_played.get(sname, -1000)) < gap:
		return
	var v := vol_db + _distance_db(pos)
	if is_nan(v):
		return
	var times: Array = recent.get(sname, [])
	while not times.is_empty() and now - int(times[0]) > STACK_MS:
		times.pop_front()
	if times.size() >= STACK_MAX:
		return
	v -= STACK_DB * times.size()
	times.append(now)
	recent[sname] = times
	last_played[sname] = now
	var p := _voice(pos)
	var st = streams[sname]
	if st is Array:
		# a different take from last time
		var arr: Array = st
		var i := rng.randi_range(0, arr.size() - 1)
		if arr.size() > 1 and i == int(last_take.get(sname, -1)):
			i = (i + 1) % arr.size()
		last_take[sname] = i
		st = arr[i]
	p.stream = st
	p.volume_db = v
	p.pitch_scale = pitch * (1.0 + rng.randf_range(-pitch_var, pitch_var))
	p.play()


## Plays a ready-made stream (a glider skin's sound, say) with the same distance falloff as play().
func play_stream(st: AudioStream, pos = null, vol_db := 0.0, pitch_var := 0.05) -> void:
	if st == null or players.is_empty():
		return
	# the same stream twice within 80ms (a glider flicked open and shut) plays once
	var key := "#%d" % st.get_instance_id()
	var now := Time.get_ticks_msec()
	if now - int(last_played.get(key, -1000)) < 80:
		return
	var v := vol_db + _distance_db(pos)
	if is_nan(v):
		return
	last_played[key] = now
	var p := _voice(pos)
	p.stream = st
	p.volume_db = v
	p.pitch_scale = 1.0 + rng.randf_range(-pitch_var, pitch_var)
	p.play()
