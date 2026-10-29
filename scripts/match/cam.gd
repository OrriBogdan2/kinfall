class_name CamRig
extends Camera3D
## Supervive-style camera: high, far and narrow, leaning toward the cursor so you see where you aim.

const HEIGHT := 27.0
const BACK := 17.5
const LEAD_X := 4.2
const LEAD_Z := 5.4
## Expedition camera presets (Settings "cam_style"): pitch in degrees, distance, field of view.
const STYLES := {
	"supervive": {"pitch": 62.0, "dist": 25.0, "fov": 38.0, "name": "Supervive (steep, wide)"},
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
	_apply(Vector3.ZERO)

func punch(a: float) -> void:
	kick = maxf(kick, a)

func add_trauma(a: float) -> void:
	trauma = minf(1.0, trauma + a * float(Settings.get_v("shake")))

func follow(p: Vector3, delta: float, mouse_lead := true) -> void:
	var off := Vector3.ZERO
	if mouse_lead:
		var vp := get_viewport()
		var sz := vp.get_visible_rect().size
		var mp := vp.get_mouse_position()
		var half := minf(sz.x, sz.y) * 0.5
		var n := Vector2((mp.x - sz.x * 0.5) / half, (mp.y - sz.y * 0.5) / half)
		var l := n.length()
		var f := clampf((l - 0.12) / 0.8, 0.0, 1.0)
		if l > 0.0:
			off = Vector3(n.x / l * f * LEAD_X, 0, n.y / l * f * LEAD_Z).rotated(Vector3.UP, yaw) * lead
	var want := Vector3(p.x, p.y * 0.6, p.z) + off
	focus = focus.lerp(want, minf(1.0, delta * 6.0))
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
