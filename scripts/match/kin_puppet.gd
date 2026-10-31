class_name KinPuppet
extends Node
## Small life for a kin model (Models.kin), wherever it is shown: blinking, squash and stretch from its
## own hops, a tail that wags faster when it moves or is happy, ears that twitch and flop on landing,
## a dizzy squint with circling stars when it is dazed, and a quick swell when it casts.
##
## On top of that, each body plan moves its own way (BODY below): quadrupeds trot and break into a
## gallop with the back rocking, bipeds (the hare) hop, flyers hover and beat their wings, the sky
## serpent ripples along its length, blobs jiggle. Each has an idle breath, a curled-up sleep, a
## lunge for attacks, a wiggle of joy, a crouch before a jump and a stretch in the air.
##
## It reads a few metas on the kin root, all optional:
##   "dazed" (bool) "happy" (bool) "pulse" (set to Time msec when an ability goes off)
##   "kstate": "" | "attack" (lunging) | "sleep" | "perch" (riding a shoulder)
## Only Flex and the limbs are posed here; Body stays free for whoever moves the kin (hops,
## home quirks and work poses, match lunges).

## The body plan of each species (anything else, the older round kin, moves like a blob).
const BODY := {"cindle": "quad", "puddlet": "quad", "burrlet": "quad", "pebbit": "quad", "cairnback": "quad",
	"zapple": "biped", "wisplet": "flyer", "hivara": "flyer", "zephyrak": "serpent"}
var species := ""
var plan := "blob"
var flex_base := Vector3.ZERO
var gait := 0.0
var att_k := 0.0
var sleep_k := 0.0
var air := 0.0
var happy_k := 0.0
var perch_k := 0.0

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
var legs: Array[Node3D] = []
var wings: Array[Node3D] = []
var spin: Node3D
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
	var lg := flex.get_node_or_null("Legs")
	if lg:
		for ch in lg.get_children():
			if String(ch.name).begins_with("Leg"): legs.append(ch)
	var wg := flex.get_node_or_null("Wings")
	if wg:
		for ch in wg.get_children(): wings.append(ch)
	spin = flex.get_node_or_null("Spin")
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
	plan = String(BODY.get(species, "blob"))
	flex_base = flex.position

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
	var ks := String(root.get_meta("kstate", ""))
	var ek := 1.0 - exp(-8.0 * dt)
	att_k = lerpf(att_k, 1.0 if ks == "attack" else 0.0, 1.0 - exp(-18.0 * dt))
	sleep_k = lerpf(sleep_k, 1.0 if ks == "sleep" else 0.0, 1.0 - exp(-3.0 * dt))
	perch_k = lerpf(perch_k, 1.0 if ks == "perch" else 0.0, ek)
	happy_k = lerpf(happy_k, 1.0 if happy else 0.0, ek)
	air = lerpf(air, clampf(vy * 0.4, -1.0, 1.0), 1.0 - exp(-10.0 * dt))
	gait += dt * (4.0 + move_k * 12.0 + happy_k * 4.0)
	var breathe := sin(t * (2.2 - sleep_k * 1.0) + phase) * (0.018 + sleep_k * 0.03) * (1.0 - move_k)
	var sx := 1.0 + sq * 0.6 + swell + breathe * 0.5
	var sy := 1.0 - sq + swell * 0.6 + breathe
	var sz := 1.0
	var rx := 0.0
	var ry := 0.0
	var rz := 0.0
	var off := Vector3.ZERO
	match plan:
		"quad":
			# a trot rocks the back a little; a run is a gallop, the spine bunching and stretching
			var run := clampf((move_k - 0.55) / 0.45, 0.0, 1.0)
			rx += sin(gait) * 0.05 * move_k + sin(gait) * 0.12 * run
			sz += sin(gait) * 0.05 * run
			rz += sin(gait * 0.5) * 0.03 * move_k * (1.0 - run)
			off.y += absf(sin(gait)) * 0.02 * move_k
			# idle: a little sniff, head down and up
			rx += sin(t * 0.7 + phase) * 0.03 * (1.0 - move_k)
		"biped":
			# hops: crouch, spring, stretch
			rx -= 0.08 * move_k + air * 0.1
			sy -= maxf(0.0, -air) * 0.08
			rz += sin(t * 1.3 + phase) * 0.025 * (1.0 - move_k)
		"flyer":
			# hovering: a slow bob, tipped forward when it flies along
			off.y += 0.07 + sin(t * 2.6 + phase) * 0.035 * (1.0 - sleep_k) * (1.0 - perch_k)
			off.y *= (1.0 - sleep_k) * (1.0 - perch_k)
			rx -= 0.22 * move_k
			rz += sin(t * 1.7 + phase) * 0.05 * (1.0 - move_k)
		"serpent":
			# a ripple down its length, and a lazy sway in the air
			ry += sin(gait * 0.8) * (0.12 + move_k * 0.12)
			rz += sin(gait * 0.8 + 1.2) * 0.08
			off.y += 0.06 + sin(t * 2.0 + phase) * 0.04
			off.y *= (1.0 - sleep_k) * (1.0 - perch_k)
		_:
			# a blob jiggles, wobbling after every bounce
			sx += sin(t * 9.0 + phase) * 0.02 * move_k
			rz += sin(gait * 0.5) * 0.08 * move_k
	# attack: a quick lunge, stretched long, head down
	rx -= att_k * 0.35
	sz += att_k * 0.18
	sy -= att_k * 0.06
	# a jump: crouch before (squash already), stretch going up, tuck coming down
	if plan != "flyer" and plan != "serpent":
		rx += air * -0.15
	# joy: a wiggle side to side
	rz += sin(t * 14.0) * 0.12 * happy_k
	# asleep: curled up low, tipped onto its side a little
	sy *= 1.0 - sleep_k * 0.22
	sx *= 1.0 + sleep_k * 0.08
	rz += sleep_k * 0.25
	rx += sleep_k * 0.1
	off.y -= sleep_k * 0.03
	flex.scale = Vector3(sx, sy, sx * sz)
	flex.position = flex_base + off
	# a lean into a dizzy wobble
	if dazed:
		rz += sin(t * 5.0) * 0.16
		rx += cos(t * 5.0) * 0.08
	flex.rotation.z = lerpf(flex.rotation.z, rz, ek)
	flex.rotation.x = lerpf(flex.rotation.x, rx, ek)
	flex.rotation.y = lerpf(flex.rotation.y, ry, ek)
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
	elif sleep_k > 0.5:
		shut = 1.0
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
		if dazed or sleep_k > 0.5:
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
	# legs: a trot that speeds up with it (diagonal pairs together), a gallop when running (front
	# pair, then back pair), both feet together for hoppers, tucked up asleep, dangling for flyers
	var gal := clampf((move_k - 0.55) / 0.45, 0.0, 1.0)
	for i in legs.size():
		var trot := 0.0 if i % 4 in [0, 3] else PI
		var gal_ph := (0.0 if i < 2 else PI * 0.9) + (0.35 if i % 2 == 1 else 0.0)
		var ph := lerpf(trot, gal_ph, gal)
		var a := sin(gait + ph) * (0.55 + gal * 0.25) * move_k
		match plan:
			"biped":
				a = -air * 0.6 + sin(gait) * 0.2 * move_k
			"flyer":
				a = 0.35 + sin(t * 3.0 + i) * 0.1
		a += att_k * (-0.5 if i < 2 else 0.3)
		a = lerpf(a, -0.9 if i < 2 else 0.9, sleep_k)
		legs[i].rotation.x = a
	# wings: a slow flutter at rest, quick beats when it moves; flyers beat fast all the time,
	# and fold them asleep
	for i in wings.size():
		var side := -1.0 if String(wings[i].name).ends_with("L") else 1.0
		var rate := 5.0 + move_k * 9.0
		var amp := 0.25 + move_k * 0.3
		if plan in ["flyer", "serpent"]:
			rate = 16.0 + move_k * 10.0; amp = 0.45 + move_k * 0.2
		rate += absf(air) * 10.0
		amp = lerpf(amp, 0.05, maxf(sleep_k, perch_k * 0.6))
		var flap := sin(t * rate + phase) * amp
		wings[i].rotation.z = side * (flap - 0.1 - sleep_k * 0.4)
	if spin:
		spin.rotation.y += dt * (1.2 + move_k * 2.0)
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
