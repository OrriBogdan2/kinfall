class_name CamRig
extends Camera3D
## Supervive-style camera: high, far and narrow, leaning toward the cursor so you see where you aim.

const HEIGHT := 27.0
const BACK := 17.5
const LEAD_X := 4.2
const LEAD_Z := 5.4
## Expedition camera presets (Settings "cam_style"): pitch in degrees, distance, field of view.
const STYLES := {
	"supervive": {"pitch": 65.0, "dist": 25.0, "fov": 35.0, "name": "Supervive"},     # measured from footage
	"high": {"pitch": 70.0, "dist": 27.0, "fov": 36.0, "name": "Top-down"},
	"classic": {"pitch": 57.0, "dist": 32.2, "fov": 28.0, "name": "Classic (flat, far)"},
	"low": {"pitch": 50.0, "dist": 23.0, "fov": 42.0, "name": "Low (more horizon)"},
}

var focus := Vector3.ZERO
var target: Node3D = null
var trauma := 0.0
var zoom := 1.0
var zoom_to := 1.0
var lead := 1.0
var kick := 0.0               # a quick zoom-in punch on big moments
var top := 0.0                # 0 = the usual angle, 1 = looking straight down (the opening drop)
var top_to := 0.0
var pitch := deg_to_rad(57.0)  # how steeply the camera looks down
var dist := 32.2              # how far back it sits
var yaw := 0.0                # turned around the focus (0 = looking north); only the skyship ride turns it
var yaw_to := 0.0
var chase := 0.0              # 0 = the usual angle, 1 = low behind-the-ship view
var chase_to := 0.0
## Cursor panning, from Supervive's three camera presets: [deadzone, maxzone, pan distance,
## camera speed, quadratic easing]. Locked stays centred on you.
const FOLLOW := {
	# Supervive (the default): the view leans toward the cursor in proportion to how far the cursor
	# is from YOU (not from the screen centre), after a small deadzone, eased, and capped so you
	# never leave the screen. [deadzone m, share of the distance, cap m, ease speed]
	"supervive": [1.4, 0.42, 7.5, 6.0, false],
	"standard": [0.2, 0.8, 6.0, 7.0, true],
	"dynamic": [0.1, 0.9, 10.0, 10.0, false],
	"locked": [0.0, 0.0, 0.0, 0.0, false],
}
var follow_mode := "supervive"
var pan := Vector3.ZERO
var base := Vector3.ZERO      # the followed point, before the cursor pan

## Picks one of STYLES (the expedition camera).
func use_style(id: String) -> void:
	var st: Dictionary = STYLES.get(id, STYLES["supervive"])
	pitch = deg_to_rad(float(st["pitch"]))
	dist = float(st["dist"])
	fov = float(st["fov"])

func _ready() -> void:
	fov = 28.0
	near = 1.0
	far = 120.0
	current = true

func snap(p: Vector3) -> void:
	focus = p
	base = p
	pan = Vector3.ZERO
	_apply(Vector3.ZERO)

func punch(a: float) -> void:
	kick = maxf(kick, a)

func add_trauma(a: float) -> void:
	trauma = minf(1.0, trauma + a * float(Settings.get_v("shake")))

func follow(p: Vector3, delta: float, mouse_lead := true) -> void:
	var want_pan := Vector3.ZERO
	var fm: Array = FOLLOW.get(follow_mode, FOLLOW["supervive"])
	if follow_mode == "supervive" and mouse_lead:
		# where the cursor points on the ground at your height, relative to you
		var cur := mouse_on_plane(p.y)
		var rel3 := Vector3(cur.x - p.x, 0, cur.z - p.z)
		var l3 := rel3.length()
		var dz := float(fm[0])
		if l3 > dz:
			var amt := minf((l3 - dz) * float(fm[1]), float(fm[2]) * maxf(1.0, zoom)) * lead
			want_pan = rel3 / l3 * amt
		pan = pan.lerp(want_pan, 1.0 - exp(-float(fm[3]) * delta))
	elif mouse_lead and float(fm[2]) > 0.0:
		var vp := get_viewport()
		var sz := vp.get_visible_rect().size
		var half := sz * 0.5
		var rel := (vp.get_mouse_position() - half) / half       # -1..1 on each axis
		var l := rel.length()
		if l > float(fm[0]) and float(fm[1]) > float(fm[0]):
			var f := clampf((l - float(fm[0])) / (float(fm[1]) - float(fm[0])), 0.0, 1.0)
			if fm[4]: f *= f
			want_pan = Vector3(rel.x / l, 0, rel.y / l).rotated(Vector3.UP, yaw) * f * float(fm[2]) * lead
	if follow_mode == "supervive" and mouse_lead:
		pass        # (eased above)
	elif not mouse_lead or float(fm[3]) <= 0.0:
		pan = want_pan if mouse_lead else pan.lerp(Vector3.ZERO, minf(1.0, delta * 6.0))
	else:
		pan = pan.lerp(want_pan, 1.0 - exp(-float(fm[3]) * delta))
	if follow_mode == "dynamic" and mouse_lead:
		pan = want_pan
	var want := Vector3(p.x, p.y * 0.6, p.z)
	# across follows briskly; up and down follows softer, so falls and glides don't jolt the view
	var kxz := 1.0 - exp(-8.0 * delta)
	var ky := 1.0 - exp(-3.5 * delta)
	base = Vector3(lerpf(base.x, want.x, kxz), lerpf(base.y, want.y, ky), lerpf(base.z, want.z, kxz))
	focus = base + pan
	zoom = lerpf(zoom, zoom_to, minf(1.0, delta * 2.5))
	top = move_toward(top, top_to, delta * (0.9 if top_to < top else 2.0))
	chase = move_toward(chase, chase_to, delta * 0.7)
	yaw = lerp_angle(yaw, yaw_to, minf(1.0, delta * 1.6))
	var shake := Vector3.ZERO
	if trauma > 0.0:
		var s := trauma * trauma * 0.6
		shake = Vector3(Sfx.rng.randf_range(-s, s), Sfx.rng.randf_range(-s, s) * 0.5, Sfx.rng.randf_range(-s, s))
		trauma = maxf(0.0, trauma - delta * 1.8)
	_apply(shake)
	Sfx.listener = focus

func _apply(shake: Vector3) -> void:
	kick = maxf(0.0, kick - get_process_delta_time() * 0.5)
	var z := zoom * (1.0 - kick)
	far = (120.0 * maxf(1.0, z) + 30.0) * (1.0 + 1.5 * chase)
	var k := top * top * (3.0 - 2.0 * top)
	var c := chase * chase * (3.0 - 2.0 * chase)
	# pitch: the style's angle, tipped toward straight down for a bird's-eye view, or low behind
	# the skyship for the ride
	var p := lerpf(lerpf(pitch, deg_to_rad(88.0), k), deg_to_rad(30.0), c)
	var d := dist * z * (1.0 + 0.15 * k)
	var back := Vector3(0, sin(p), cos(p)).rotated(Vector3.UP, yaw)
	position = focus + back * d + shake
	look_at(focus + shake, Vector3.UP if p < deg_to_rad(85.0) else Vector3(0, 0, -1).rotated(Vector3.UP, yaw))

## Where the mouse points on the horizontal plane at height y.
func mouse_on_plane(y: float) -> Vector3:
	var mp := get_viewport().get_mouse_position()
	var o := project_ray_origin(mp)
	var d := project_ray_normal(mp)
	if absf(d.y) < 0.0001:
		return focus
	var t := (y - o.y) / d.y
	return o + d * t

func on_screen(p: Vector3) -> bool:
	if is_position_behind(p):
		return false
	var s := unproject_position(p)
	var sz := get_viewport().get_visible_rect().size
	return s.x > 20 and s.y > 20 and s.x < sz.x - 20 and s.y < sz.y - 20
