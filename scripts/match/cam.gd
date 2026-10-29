class_name CamRig
extends Camera3D
## Supervive-style camera: high, far and narrow, leaning toward the cursor so you see where you aim.

const HEIGHT := 27.0
const BACK := 17.5
const LEAD_X := 4.2
const LEAD_Z := 5.4

var focus := Vector3.ZERO
var target: Node3D = null
var trauma := 0.0
var zoom := 1.0
var zoom_to := 1.0
var lead := 1.0
var kick := 0.0               # a quick zoom-in punch on big moments
var top := 0.0                # 0 = the usual angle, 1 = looking straight down (the opening drop)
var top_to := 0.0

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
			off = Vector3(n.x / l * f * LEAD_X, 0, n.y / l * f * LEAD_Z) * lead
	var want := Vector3(p.x, p.y * 0.6, p.z) + off
	focus = focus.lerp(want, minf(1.0, delta * 6.0))
	zoom = lerpf(zoom, zoom_to, minf(1.0, delta * 2.5))
	top = move_toward(top, top_to, delta * (0.9 if top_to < top else 2.0))
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
	far = 120.0 * maxf(1.0, z) + 30.0
	var k := top * top * (3.0 - 2.0 * top)
	position = focus + Vector3(0, HEIGHT * z * (1.0 + 0.15 * k), BACK * z * (1.0 - 0.9 * k)) + shake
	look_at(focus + shake, Vector3.UP if k < 0.95 else Vector3(0, 0, -1))

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
