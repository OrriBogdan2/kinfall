class_name TopDownCameraRig
extends Node3D
## Supervive-style fixed-angle camera with the three in-game presets:
## Locked (centered on hunter), Standard Dynamic, Fully Dynamic (pans toward
## cursor). Preset values come from published settings guides. Pitch, FOV and
## distance were measured from 60fps gameplay footage (approximate).

enum Mode { LOCKED, STANDARD_DYNAMIC, FULLY_DYNAMIC }

@export var target_path: NodePath
@export var use_preset := true   ## off = keep the panning values set in the inspector
@export var mode := Mode.STANDARD_DYNAMIC:
	set(value):
		mode = value
		if is_node_ready():
			apply_preset(value)

@export_group("Framing")
@export var pitch_deg := 65.0          ## [footage] ~65 deg, from ground-circle ellipses near screen center
@export var yaw_deg := 0.0             ## fixed; Supervive doesn't rotate
@export var fov := 35.0                ## [footage] ~35 deg vertical, from how ellipses change top-to-bottom
@export var distance := 25.0           ## [footage] ~25m: hunter at 4.55 m/s scrolls ~175px/s on a 1080p-equivalent frame
@export var glide_zoom_out := true     ## [guide] on in every preset
@export var delayed_glide_zoom := false ## [guide]
@export var glide_zoom_multiplier := 1.25 ## [est]
@export var zoom_speed := 3.0          ## [est]

@export_group("Panning")
@export_range(0.0, 1.0) var deadzone := 0.2  ## cursor distance (0=center, 1=edge) before panning
@export_range(0.0, 1.0) var maxzone := 0.8   ## cursor distance for full pan
@export var pan_distance := 6.0        ## [guide] 6 standard / 10 fully dynamic (read as meters)
@export var camera_speed := 7.0        ## [guide] pan smoothing speed
@export var quadratic_movement := true ## [guide] eases pan in near the deadzone
@export var lock_to_cursor := false    ## [guide] "no stabilization": pan snaps to target
@export var smooth_corrections := true ## [guide] smooths vertical follow (jumps, ledges)

var camera: Camera3D
var _target: Node3D
var _pan := Vector3.ZERO
var _zoom := 1.0
var _glide_time := 0.0
var _focus_y := 0.0


func _ready() -> void:
	camera = get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		camera = Camera3D.new()
		camera.name = "Camera3D"
		add_child(camera)
	camera.current = true
	_target = get_node_or_null(target_path) as Node3D
	if use_preset:
		apply_preset(mode)
	if _target != null:
		_focus_y = _target.global_position.y
	_update_camera(0.0, true)


func apply_preset(m: Mode) -> void:
	match m:
		Mode.LOCKED:
			deadzone = 0.0; maxzone = 0.0; pan_distance = 0.0; camera_speed = 0.0
			quadratic_movement = false; lock_to_cursor = false; smooth_corrections = false
		Mode.STANDARD_DYNAMIC:
			deadzone = 0.2; maxzone = 0.8; pan_distance = 6.0; camera_speed = 7.0
			quadratic_movement = true; lock_to_cursor = false; smooth_corrections = true
		Mode.FULLY_DYNAMIC:
			deadzone = 0.1; maxzone = 0.9; pan_distance = 10.0; camera_speed = 10.0
			quadratic_movement = false; lock_to_cursor = true; smooth_corrections = false


func _process(delta: float) -> void:
	_update_camera(delta, false)


func _update_camera(delta: float, snap: bool) -> void:
	if _target == null:
		return
	camera.fov = fov
	var tp := _target.global_position

	# Vertical follow
	if smooth_corrections and not snap:
		_focus_y = lerpf(_focus_y, tp.y, 1.0 - exp(-6.0 * delta))
	else:
		_focus_y = tp.y

	# Glide zoom-out
	var gliding: bool = _target.has_method("is_gliding") and _target.is_gliding()
	_glide_time = _glide_time + delta if gliding else 0.0
	var want_zoom := 1.0
	if glide_zoom_out and gliding and (not delayed_glide_zoom or _glide_time > 0.5):
		want_zoom = glide_zoom_multiplier
	_zoom = want_zoom if snap else lerpf(_zoom, want_zoom, 1.0 - exp(-zoom_speed * delta))

	# Cursor pan
	var want_pan := _cursor_pan()
	if snap or lock_to_cursor or camera_speed <= 0.0:
		_pan = want_pan
	else:
		_pan = _pan.lerp(want_pan, 1.0 - exp(-camera_speed * delta))

	var focus := Vector3(tp.x, _focus_y, tp.z) + _pan
	var pitch := deg_to_rad(pitch_deg)
	var yaw := deg_to_rad(yaw_deg)
	var back := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	camera.global_position = focus + back * distance * _zoom
	camera.look_at(focus, Vector3.UP)


func _cursor_pan() -> Vector3:
	if pan_distance <= 0.0 or maxzone <= deadzone:
		return Vector3.ZERO
	var vp := get_viewport()
	var size := vp.get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return Vector3.ZERO
	var half := size * 0.5
	var rel := (vp.get_mouse_position() - half) / half  # -1..1 per axis
	var r := rel.length()
	if r <= deadzone:
		return Vector3.ZERO
	var t := clampf((r - deadzone) / (maxzone - deadzone), 0.0, 1.0)
	if quadratic_movement:
		t *= t
	var dir2 := rel / r
	var yaw := deg_to_rad(yaw_deg)
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	return (right * dir2.x - fwd * dir2.y) * t * pan_distance
