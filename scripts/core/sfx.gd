extends Node
## Plays the synthesized sound effects. Positional sounds fade with distance from the camera focus.

const NAMES := ["smg", "rifle", "thump", "boom", "hit", "crit", "kill", "knock", "hurt", "dash", "jump", "land", "grab",
	"throw", "kinhit", "skill", "kin_happy", "kin_unsure", "kin_alert", "recall", "pickup", "catch", "warn", "portal",
	"revive", "click", "reload", "shield", "cloak", "heal", "fall", "plant", "harvest", "ping", "glide", "build", "unlock", "whoosh"]
const POOL := 24

var streams := {}
var players: Array[AudioStreamPlayer] = []
var next := 0
var listener := Vector3.ZERO   # set by the camera each frame
var hear_range := 22.0
var last_played := {}
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	for n in NAMES:
		var s = load("res://audio/%s.wav" % n)
		if s:
			streams[n] = s
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		players.append(p)

func set_volume(v: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.001)))

## pos: world position, or null for UI sounds. Repeats of one sound within 30ms are merged.
func play(sname: String, pos = null, vol_db := 0.0, pitch_var := 0.07, pitch := 1.0) -> void:
	if not streams.has(sname):
		return
	var now := Time.get_ticks_msec()
	if now - int(last_played.get(sname, -1000)) < 30:
		return
	last_played[sname] = now
	var v := vol_db
	if pos != null:
		var dist := Vector2(pos.x - listener.x, pos.z - listener.z).length()
		if dist > hear_range:
			return
		v += linear_to_db(clampf(1.0 - dist / hear_range, 0.05, 1.0))
	var p := players[next]
	next = (next + 1) % POOL
	p.stream = streams[sname]
	p.volume_db = v
	p.pitch_scale = pitch * (1.0 + rng.randf_range(-pitch_var, pitch_var))
	p.play()
