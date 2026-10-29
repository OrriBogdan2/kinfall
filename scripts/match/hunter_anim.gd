class_name HunterAnim
extends RefCounted
## Procedural animation for a hunter model (Models.hunter). Everything is posed from a few numbers
## each frame, so it works the same in a match, at home, in town and on the title screen:
##   walk and run cycles with knees and counter-swing, strafing and backpedalling legs, idle
##   breathing and glances, jump tuck and fall stretch, landing dips, dodge dives, crouching,
##   gliding under the wing, ledge pulls, reloads, recoil, flinches and lying downed.
##
## update() takes a state dictionary; every key is optional:
##   vel (Vector3) face (yaw) grounded gliding rolling crouch (0..1) downed ledge reload (0..1, -1 when not)
##   recoil (0..1) flash (0..1) fired (seconds since the last shot) aim (Vector2 world aim dir) carrying

var model: Node3D
var rig: Node3D
var torso: Node3D
var legs: Node3D
var leg_l: Node3D
var leg_r: Node3D
var knee_l: Node3D
var knee_r: Node3D
var head: Node3D
var aim: Node3D
var ph := 0.0            # walk phase, advances with distance travelled
var t := 0.0
var stepped := false     # a foot just came down this frame (for footstep sounds)
var land_k := 0.0        # a landing dip that springs back
var was_grounded := true
var vy_prev := 0.0
var legs_yaw := 0.0
var run_k := 0.0
var air_k := 0.0
var glide_k := 0.0
var crouch_k := 0.0
var roll_k := 0.0
var down_k := 0.0
var ledge_k := 0.0
var lean_f := 0.0
var lean_s := 0.0
var head_look := 0.0
var glance_t := 2.0
var glance_to := 0.0
var lower_k := 0.0       # gun lowered while running and not shooting

func _init(m: Node3D) -> void:
	model = m
	rig = m.get_node("Rig")
	torso = rig.get_node("Torso")
	legs = rig.get_node("Legs")
	leg_l = legs.get_node("LegL")
	leg_r = legs.get_node("LegR")
	knee_l = leg_l.get_node_or_null("Knee")
	knee_r = leg_r.get_node_or_null("Knee")
	head = torso.get_node_or_null("HeadPivot")
	aim = torso.get_node_or_null("Aim")

static func _ease(cur: float, want: float, rate: float, dt: float) -> float:
	return lerpf(cur, want, 1.0 - exp(-rate * dt))

func update(dt: float, s: Dictionary) -> void:
	t += dt
	stepped = false
	var vel: Vector3 = s.get("vel", Vector3.ZERO)
	var face: float = s.get("face", model.rotation.y)
	var grounded: bool = s.get("grounded", true)
	var hv := Vector2(vel.x, vel.z)
	var spd := hv.length()
	var fwd := Vector2(-sin(face), -cos(face))
	var right := Vector2(cos(face), -sin(face))
	var mf := hv.dot(fwd)
	var ms := hv.dot(right)
	# blend weights for each pose, eased so changes never pop
	var moving := grounded and spd > 0.4
	run_k = _ease(run_k, clampf(spd / 5.5, 0.0, 1.2) if moving else 0.0, 10.0, dt)
	air_k = _ease(air_k, 0.0 if grounded else 1.0, 12.0, dt)
	glide_k = _ease(glide_k, 1.0 if s.get("gliding", false) else 0.0, 8.0, dt)
	crouch_k = _ease(crouch_k, float(s.get("crouch", 0.0)), 12.0, dt)
	roll_k = _ease(roll_k, 1.0 if s.get("rolling", false) else 0.0, 25.0, dt)
	down_k = _ease(down_k, 1.0 if s.get("downed", false) else 0.0, 7.0, dt)
	ledge_k = _ease(ledge_k, 1.0 if s.get("ledge", false) else 0.0, 14.0, dt)
	lean_f = _ease(lean_f, clampf(mf / 14.0, -0.25, 0.25), 8.0, dt)
	lean_s = _ease(lean_s, clampf(ms / 14.0, -0.22, 0.22), 8.0, dt)
	# landing: a dip proportional to how hard you came down
	if grounded and not was_grounded and vy_prev < -3.0:
		land_k = clampf(-vy_prev / 16.0, 0.3, 1.0)
	was_grounded = grounded
	vy_prev = vel.y
	land_k = maxf(0.0, land_k - dt * 4.0)
	# walk phase, and a footstep each time a foot passes under the body
	var ph0 := ph
	if moving:
		ph += dt * spd * 2.3
	if moving and int(ph / PI) != int(ph0 / PI):
		stepped = true
	# strafing and backpedalling: the legs turn toward where you're going; backwards they swing the other way
	var back := 1.0
	var want_yaw := 0.0
	if spd > 0.6:
		var rel := atan2(ms, mf)
		if absf(rel) > PI * 0.6:
			back = -1.0
			rel = rel - PI * signf(rel)
		want_yaw = -clampf(rel, -1.2, 1.2)
	legs_yaw = lerp_angle(legs_yaw, want_yaw, 1.0 - exp(-10.0 * dt))
	legs.rotation.y = legs_yaw * (1.0 - glide_k) * (1.0 - down_k)
	# ---- legs
	var sw := sin(ph) * 0.78 * minf(run_k, 1.0) * back
	var kl := -(maxf(0.0, sin(ph + 1.3 * back)) * 1.15 + 0.12) * minf(run_k, 1.0)
	var kr := -(maxf(0.0, sin(ph + PI + 1.3 * back)) * 1.15 + 0.12) * minf(run_k, 1.0)
	var hl := sw
	var hr := -sw
	# idle: a relaxed stance, weight shifting from foot to foot
	var idle := (1.0 - minf(run_k, 1.0)) * (1.0 - air_k)
	hl += idle * 0.05 * sin(t * 0.7); hr += idle * -0.04
	# crouch and landing bend the knees and drop the hips
	var bend := maxf(crouch_k, land_k * 0.9)
	hl += bend * 0.6; hr += bend * 0.55
	kl -= bend * 1.1; kr -= bend * 1.05
	# in the air: tuck on the way up, reach down on the way down
	var rising := clampf(vel.y / 8.0, -1.0, 1.0)
	var air_hl := lerpf(0.25, 0.85, maxf(rising, 0.0)); var air_kl := lerpf(-0.25, -1.3, maxf(rising, 0.0))
	var air_hr := lerpf(-0.15, 0.3, maxf(rising, 0.0)); var air_kr := lerpf(-0.15, -0.7, maxf(rising, 0.0))
	var ak := air_k * (1.0 - glide_k)
	hl = lerpf(hl, air_hl, ak); kl = lerpf(kl, air_kl, ak)
	hr = lerpf(hr, air_hr, ak); kr = lerpf(kr, air_kr, ak)
	# gliding: legs dangle and paddle a little
	hl = lerpf(hl, 0.35 + sin(t * 3.2) * 0.12, glide_k); kl = lerpf(kl, -0.45 + sin(t * 3.2 + 1.0) * 0.15, glide_k)
	hr = lerpf(hr, 0.55 - sin(t * 3.2) * 0.12, glide_k); kr = lerpf(kr, -0.6 - sin(t * 3.2 + 1.0) * 0.15, glide_k)
	# a dodge: a long dive, legs kicked back
	hl = lerpf(hl, -0.7, roll_k); kl = lerpf(kl, -0.9, roll_k)
	hr = lerpf(hr, 0.6, roll_k); kr = lerpf(kr, -0.2, roll_k)
	# pulling up a ledge: one knee up
	hl = lerpf(hl, 1.1, ledge_k); kl = lerpf(kl, -1.4, ledge_k)
	# downed: limp
	hl = lerpf(hl, 0.15, down_k); kl = lerpf(kl, -0.35, down_k)
	hr = lerpf(hr, -0.05, down_k); kr = lerpf(kr, -0.1, down_k)
	leg_l.rotation.x = hl
	leg_r.rotation.x = hr
	if knee_l: knee_l.rotation.x = kl
	if knee_r: knee_r.rotation.x = kr
	# ---- body
	var r1 := minf(run_k, 1.0)
	var bob := absf(sin(ph)) * 0.055 * r1
	var breath := sin(t * 2.3) * idle
	torso.position.y = 0.42 + bob - bend * 0.12 + breath * 0.006 + glide_k * 0.02
	torso.scale = Vector3(1.0 - breath * 0.006, 1.0 + breath * 0.012, 1.0 - breath * 0.006)
	var pitch := -lean_f - r1 * 0.12 - crouch_k * 0.32 - land_k * 0.25 + rising * 0.08 * ak - roll_k * 0.65 - glide_k * 0.2 - ledge_k * 0.2
	pitch += float(s.get("flash", 0.0)) * 0.6
	pitch -= float(s.get("recoil", 0.0)) * 0.05
	torso.rotation.x = pitch
	torso.rotation.z = -lean_s * (1.0 + glide_k * 0.6)
	torso.rotation.y = -sin(ph) * 0.14 * r1 * back          # shoulders counter the hips
	rig.rotation.z = sin(ph) * 0.035 * r1
	rig.position.y = -bend * 0.1 - down_k * 0.0
	# ---- arms and gun
	if aim:
		var fired: float = s.get("fired", 0.0)
		var want_lower := 1.0 if (r1 > 0.6 and fired > 1.2 and grounded) else 0.0
		lower_k = _ease(lower_k, want_lower, 6.0, dt)
		var ax := -lower_k * 0.35 + sin(ph * 2.0) * 0.03 * r1 + breath * 0.02
		var az := 0.0
		var ay := 0.0
		var reload: float = s.get("reload", -1.0)
		if reload >= 0.0:
			# tip the gun over, slap in a new magazine, bring it back up
			var rk := sin(clampf(reload, 0.0, 1.0) * PI)
			ax += -rk * 0.45
			az += rk * 0.55
			ay += sin(reload * TAU * 2.0) * 0.05 * rk
		ax += float(s.get("recoil", 0.0)) * 0.32
		# keep the gun level while the body leans (crouching, running, landing)
		ax -= (pitch - float(s.get("flash", 0.0)) * 0.6) * 0.85 * (1.0 - roll_k) * (1.0 - down_k)
		# gliding: hands up on the harness
		ax = lerpf(ax, 1.25, glide_k)
		# ledge: reaching up
		ax = lerpf(ax, 1.6, ledge_k)
		# dodging: tucked in
		ax = lerpf(ax, -0.5, roll_k)
		# downed: arms flop
		ax = lerpf(ax, -0.9, down_k)
		aim.rotation = Vector3(ax, ay, az)
		aim.position = Vector3(0, 0.5 + glide_k * 0.05, float(s.get("recoil", 0.0)) * 0.05)
	# ---- head: steady while the body bobs, glances around when idle, flinches when hit
	if head:
		glance_t -= dt
		if glance_t <= 0.0:
			glance_t = randf_range(1.6, 4.0)
			glance_to = randf_range(-0.45, 0.45) if randf() < 0.6 else 0.0
		head_look = _ease(head_look, glance_to * idle, 3.0, dt)
		head.rotation.y = head_look - torso.rotation.y * 0.8
		head.rotation.x = -pitch * 0.45 + sin(ph * 2.0 + 0.6) * 0.03 * r1 + down_k * 0.4
		head.rotation.z = lean_s * 0.6 + sin(t * 0.9) * 0.03 * idle
