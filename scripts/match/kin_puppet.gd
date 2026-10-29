class_name KinPuppet
extends Node
## Small life for a kin model (Models.kin), wherever it is shown: blinking, squash and stretch from its
## own hops, a tail that wags faster when it moves or is happy, ears that twitch and flop on landing,
## a dizzy squint with circling stars when it is dazed, and a quick swell when it casts.
##
## It reads a few metas on the kin root, all optional:
##   "dazed" (bool) "happy" (bool) "pulse" (set to Time msec when an ability goes off)

var root: Node3D
var body: Node3D
var flex: Node3D
var tail: Node3D
var ears: Node3D
var eyes: Array[Node3D] = []
var shines: Array[Node3D] = []
var eye_base: Array[Vector3] = []
var t := 0.0
var blink_t := 2.0
var blink_k := 0.0
var y_prev := 0.0
var vy := 0.0
var vy_prev := 0.0
var sq := 0.0          # squash (+) and stretch (-), springs back
var sq_v := 0.0
var ear_flop := 0.0
var ear_v := 0.0
var twitch_t := 3.0
var twitch := 0.0
var pos_prev := Vector3.ZERO
var move_k := 0.0
var pulse_k := 0.0
var last_pulse := 0
var stars: Node3D
var phase := randf() * TAU

func _ready() -> void:
	root = get_parent() as Node3D
	body = root.get_node_or_null("Body")
	if body == null:
		set_process(false); return
	flex = body.get_node_or_null("Flex")
	if flex == null:
		set_process(false); return
	tail = flex.get_node_or_null("Tail")
	ears = flex.get_node_or_null("Ears")
	for sd in ["L", "R"]:
		var e := flex.get_node_or_null("Eye" + sd) as Node3D
		if e:
			eyes.append(e); eye_base.append(e.scale)
		var s := flex.get_node_or_null("Shine" + sd) as Node3D
		if s:
			shines.append(s)
	y_prev = body.position.y
	pos_prev = root.global_position if root.is_inside_tree() else Vector3.ZERO
	blink_t = randf_range(0.8, 3.5)

func _process(dt: float) -> void:
	if dt <= 0.0 or not is_instance_valid(flex):
		return
	t += dt
	var dazed: bool = root.get_meta("dazed", false)
	var happy: bool = root.get_meta("happy", false)
	# how fast the whole kin is going (for the tail) and how its body bounces (for squash)
	var gp := root.global_position
	var spd := (gp - pos_prev).length() / dt
	pos_prev = gp
	move_k = lerpf(move_k, clampf(spd / 4.0, 0.0, 1.0), 1.0 - exp(-6.0 * dt))
	var y := body.position.y
	vy = (y - y_prev) / dt
	y_prev = y
	# squash when the hop turns from falling to rising (it hit the ground), stretch while flying up
	if vy_prev < -0.6 and vy >= -0.05:
		sq_v += clampf(-vy_prev * 0.9, 0.5, 3.5)
		ear_v -= clampf(-vy_prev * 2.0, 1.0, 6.0)
	vy_prev = vy
	var want := -clampf(vy * 0.035, -0.06, 0.12)
	# springs stepped in small slices so a slow frame can't make them blow up
	var left := minf(dt, 0.1)
	while left > 0.0:
		var h := minf(left, 1.0 / 120.0)
		left -= h
		sq_v += ((want - sq) * 180.0 - sq_v * 14.0) * h
		sq += sq_v * h
		ear_v += (-ear_flop * 120.0 - ear_v * 9.0) * h
		ear_flop += ear_v * h
	sq = clampf(sq, -0.18, 0.28)
	# casting: a quick swell
	var p: int = root.get_meta("pulse", 0)
	if p != last_pulse:
		last_pulse = p
		pulse_k = 1.0
		ear_v += 4.0
	pulse_k = maxf(0.0, pulse_k - dt * 4.0)
	var swell := sin(pulse_k * PI) * 0.16
	var breathe := sin(t * 2.2 + phase) * 0.018 * (1.0 - move_k)
	var sx := 1.0 + sq * 0.6 + swell + breathe * 0.5
	var sy := 1.0 - sq + swell * 0.6 + breathe
	flex.scale = Vector3(sx, sy, sx)
	# a lean into a dizzy wobble
	if dazed:
		flex.rotation.z = sin(t * 5.0) * 0.16
		flex.rotation.x = cos(t * 5.0) * 0.08
	else:
		flex.rotation.z = lerpf(flex.rotation.z, 0.0, 1.0 - exp(-8.0 * dt))
		flex.rotation.x = lerpf(flex.rotation.x, 0.0, 1.0 - exp(-8.0 * dt))
	# blinking, and a squint when dazed
	blink_t -= dt
	if blink_t <= 0.0:
		blink_t = randf_range(1.8, 4.6)
		if randf() < 0.2:
			blink_t = 0.22   # a double blink now and then
		blink_k = 1.0
	blink_k = maxf(0.0, blink_k - dt * 8.0)
	var shut := sin(blink_k * PI)
	if dazed:
		shut = maxf(shut, 0.7 + sin(t * 3.0) * 0.1)
	elif happy:
		shut = maxf(shut, 0.45)
	for i in eyes.size():
		var b := eye_base[i]
		eyes[i].scale = Vector3(b.x * (1.0 + shut * 0.15), b.y * maxf(0.08, 1.0 - shut), b.z)
	for s in shines:
		s.visible = shut < 0.5
	# tail: a wag that quickens when it moves or is happy, droops when dazed
	if tail:
		var rate := 3.0 + move_k * 9.0 + (6.0 if happy else 0.0)
		var amp := 0.18 + move_k * 0.25 + (0.25 if happy else 0.0)
		if dazed:
			rate = 1.2; amp = 0.05
		tail.rotation.y = sin(t * rate + phase) * amp
		tail.rotation.x = lerpf(tail.rotation.x, (0.5 if dazed else -0.1 * move_k), 1.0 - exp(-6.0 * dt))
	# ears: spring that flops on landing, perks on a cast, twitches now and then
	if ears:
		twitch_t -= dt
		if twitch_t <= 0.0:
			twitch_t = randf_range(2.0, 5.0)
			twitch = 1.0
		twitch = maxf(0.0, twitch - dt * 6.0)
		var droop := 0.35 if dazed else 0.0
		ears.rotation.x = clampf(ear_flop * 0.12, -0.5, 0.5) + droop
		ears.rotation.z = sin(twitch * PI * 2.0) * 0.12
	# stars circling the head while dazed
	if dazed and stars == null:
		_make_stars()
	if stars:
		stars.visible = dazed
		if dazed:
			stars.rotation.y += dt * 4.0

func _make_stars() -> void:
	stars = Node3D.new()
	stars.name = "DazeStars"
	stars.position = Vector3(0, 0.95, 0)
	body.add_child(stars)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color("ffe680")
	for i in 3:
		var a := TAU * i / 3.0
		var s := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.1, 0.1, 0.03)
		s.mesh = pm
		s.material_override = m
		s.position = Vector3(cos(a) * 0.26, sin(a * 2.0) * 0.03, sin(a) * 0.26)
		s.rotation.z = a
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		stars.add_child(s)
