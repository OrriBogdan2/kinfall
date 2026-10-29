class_name HunterController
extends CharacterBody3D
## Supervive-style top-down hunter movement: snappy WASD, jump, hold-to-glide
## with heat, abyss lift, mini-dash / ex-dash, mantling, jump-pad launches.
## Body origin is at the FEET (offset the collision shape up by half height).

signal dashed(is_ex: bool)
signal glide_started
signal glide_ended
signal overheat_started
signal overheat_tick(damage: float)
signal mantled
signal fell_into_abyss

enum State { GROUND, AIR, GLIDE, DASH, MANTLE, DEAD }

@export var cfg: FeelConfig
@export var camera_path: NodePath   ## optional; falls back to the viewport camera
@export var visual_path: NodePath   ## node that turns to face aim / movement
@export var show_aim_laser := true

var state: State = State.AIR
var heat := 0.0
var is_overheated := false
var mini_dash_cd := 0.0
var ex_dash_cd := 0.0
var main_ability_on_cooldown := false  ## hook: forces ex-dash when true
var aim_point := Vector3.ZERO
var ground_level := 0.0                ## last landmass height, baseline for abyss logic
var last_safe_position := Vector3.ZERO

var _dash_time := 0.0
var _dash_dir := Vector3.FORWARD
var _dash_speed := 0.0
var _dash_airborne := false
var _dash_is_ex := false
var _dash_held := 0.0
var _coyote := 0.0
var _jump_buffer := 0.0
var _air_time := 0.0
var _stun := 0.0
var _ground_lock := 0.0  # ignore floor briefly after jumps/launches
var _hit_heat_timer := 0.0
var _face_aim_timer := 0.0
var _mantle_from := Vector3.ZERO
var _mantle_to := Vector3.ZERO
var _mantle_t := 0.0
var _camera: Camera3D
var _visual: Node3D
var _laser: MeshInstance3D


func _ready() -> void:
	if cfg == null:
		cfg = FeelConfig.new()
	KinfallInput.ensure_actions()
	_camera = get_node_or_null(camera_path) as Camera3D
	_visual = get_node_or_null(visual_path) as Node3D
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(50.0)
	last_safe_position = global_position
	ground_level = global_position.y
	if show_aim_laser:
		_build_laser()


# ---------------------------------------------------------------- public API

func is_gliding() -> bool:
	return state == State.GLIDE

func is_spikeable() -> bool:
	return state == State.GLIDE and is_overheated

## Call when this hunter takes damage (heat builds faster while hit).
func notify_damaged() -> void:
	_hit_heat_timer = 0.5

## Spike: stun and plummet. Over the abyss this is near-certain death.
func spike() -> void:
	_stun = cfg.spike_stun
	velocity = Vector3(0.0, -cfg.spike_velocity, 0.0)
	_set_state(State.AIR)

## Jump pads, knockbacks. Keeps horizontal momentum; dashing in adds a boost.
func launch(impulse: Vector3) -> void:
	var h := _flat(velocity)
	if state == State.DASH:
		h = _dash_dir * _dash_speed * cfg.jump_pad_dash_carry
	velocity = h + impulse
	_air_time = 0.0
	_ground_lock = 0.1
	_set_state(State.AIR)

func respawn(at: Vector3) -> void:
	global_position = at
	velocity = Vector3.ZERO
	heat = 0.0
	is_overheated = false
	_stun = 0.0
	ground_level = at.y
	_set_state(State.AIR)


# ---------------------------------------------------------------- main loop

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_tick_timers(delta)
	_update_aim()
	var input_dir := _input_direction()

	if Input.is_action_just_pressed("kf_jump"):
		_jump_buffer = cfg.jump_buffer
	if Input.is_action_just_pressed("kf_dash"):
		_try_dash(input_dir)
	if Input.is_action_pressed("kf_primary") or Input.is_action_pressed("kf_secondary"):
		_face_aim_timer = cfg.face_aim_hold

	match state:
		State.DASH:
			_process_dash(delta)
		State.MANTLE:
			_process_mantle(delta, input_dir)
		_:
			_process_locomotion(delta, input_dir)

	_update_heat(delta)
	_update_facing(delta)
	_update_laser()
	_check_abyss_death()


func _tick_timers(delta: float) -> void:
	mini_dash_cd = maxf(mini_dash_cd - delta, 0.0)
	ex_dash_cd = maxf(ex_dash_cd - delta, 0.0)
	_coyote = maxf(_coyote - delta, 0.0)
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	_stun = maxf(_stun - delta, 0.0)
	_ground_lock = maxf(_ground_lock - delta, 0.0)
	_hit_heat_timer = maxf(_hit_heat_timer - delta, 0.0)
	_face_aim_timer = maxf(_face_aim_timer - delta, 0.0)


# ---------------------------------------------------------------- locomotion

func _process_locomotion(delta: float, input_dir: Vector3) -> void:
	if is_on_floor() and _ground_lock <= 0.0:
		_coyote = cfg.coyote_time
		_air_time = 0.0
		ground_level = global_position.y
		last_safe_position = global_position
		if state != State.GROUND:
			_set_state(State.GROUND)
	else:
		_air_time += delta
		if state == State.GROUND:
			_set_state(State.AIR)

	# Jump (tap Space)
	if _jump_buffer > 0.0 and _coyote > 0.0 and _stun <= 0.0:
		velocity.y = cfg.jump_velocity
		_jump_buffer = 0.0
		_coyote = 0.0
		_air_time = 0.0
		_ground_lock = 0.1
		_set_state(State.AIR)

	# Glide (hold Space while airborne)
	var glide_held := Input.is_action_pressed("kf_glide") and _stun <= 0.0
	if state == State.AIR and glide_held and _air_time >= cfg.glide_engage_delay:
		_set_state(State.GLIDE)
	elif state == State.GLIDE and not glide_held:
		_set_state(State.AIR)

	# Horizontal
	var h := _flat(velocity)
	match state:
		State.GROUND:
			var mult := cfg.sneak_multiplier if Input.is_action_pressed("kf_sneak") else 1.0
			h = _accelerate(h, input_dir * cfg.move_speed * mult, cfg.ground_accel,
					cfg.ground_decel, cfg.ground_overspeed_decel, delta)
		State.AIR:
			h = _accelerate(h, input_dir * cfg.move_speed, cfg.air_accel,
					cfg.air_decel, cfg.air_overspeed_drag, delta)
		State.GLIDE:
			h = _accelerate(h, input_dir * cfg.glide_speed, cfg.glide_accel,
					cfg.glide_decel, cfg.glide_overspeed_drag, delta)

	# Vertical
	if state == State.GLIDE:
		_glide_vertical(delta)
	elif state == State.AIR:
		velocity.y = maxf(velocity.y - cfg.gravity * delta, -cfg.max_fall_speed)
	else:
		velocity.y = -0.5  # keep floor contact

	velocity.x = h.x
	velocity.z = h.z
	move_and_slide()

	if state == State.AIR or state == State.GLIDE:
		_try_mantle(input_dir)


## Momentum-preserving acceleration. Below max speed: move toward the wish
## velocity. Above it (dash, pad, knockback): bleed speed slowly and steer.
func _accelerate(current: Vector3, wish: Vector3, accel: float, decel: float,
		overspeed_decel: float, delta: float) -> Vector3:
	var max_speed := wish.length()
	if max_speed < 0.001:
		return current.move_toward(Vector3.ZERO, decel * delta)
	var cur_speed := current.length()
	if cur_speed > max_speed:
		var wish_dir := wish / max_speed
		var new_speed := maxf(cur_speed - overspeed_decel * delta, max_speed)
		var turn := clampf(accel * delta / cur_speed, 0.0, 1.0)
		var dir := (current / cur_speed).lerp(wish_dir, turn)
		if dir.length_squared() < 0.0001:
			dir = wish_dir
		return dir.normalized() * new_speed
	return current.move_toward(wish, accel * delta)


func _glide_vertical(delta: float) -> void:
	var depth := ground_level - global_position.y
	if depth > 0.05:
		# Below ground level over the abyss: strong lift, then brake near the top.
		# Let go of glide right before ground level to keep the upward momentum.
		if depth > cfg.abyss_brake_distance:
			velocity.y = minf(velocity.y + cfg.abyss_lift_accel * delta, cfg.abyss_lift_max_speed)
		else:
			var target := maxf(depth * cfg.abyss_brake_gain, 1.0)
			velocity.y = move_toward(velocity.y, target, cfg.abyss_brake_decel * delta)
	else:
		velocity.y = maxf(velocity.y - cfg.glide_gravity * delta, -cfg.glide_fall_speed)


# ---------------------------------------------------------------- heat

func _update_heat(delta: float) -> void:
	if state == State.GLIDE:
		var rate := cfg.heat_rate
		if _hit_heat_timer > 0.0:
			rate *= cfg.heat_damaged_multiplier
		if global_position.y < ground_level and velocity.y > 0.0:
			rate *= cfg.heat_lift_multiplier
		heat = minf(heat + rate * delta, cfg.heat_max)
	else:
		var diss := cfg.heat_dissipate_ground if state == State.GROUND else cfg.heat_dissipate_air
		heat = maxf(heat - diss * delta, 0.0)

	if not is_overheated and heat >= cfg.heat_max:
		is_overheated = true
		overheat_started.emit()
	elif is_overheated and heat <= cfg.heat_recover_threshold:
		is_overheated = false
	if is_overheated and state == State.GLIDE:
		overheat_tick.emit(cfg.overheat_dps * delta)


# ---------------------------------------------------------------- dash

func _try_dash(input_dir: Vector3) -> void:
	if state == State.DASH or state == State.MANTLE or state == State.DEAD or _stun > 0.0:
		return
	var airborne := state == State.AIR or state == State.GLIDE
	var use_ex := airborne or mini_dash_cd > 0.0 or main_ability_on_cooldown
	if use_ex and ex_dash_cd > 0.0:
		return

	var to_cursor := _flat(aim_point - global_position)
	var dir := Vector3.ZERO
	match cfg.dash_input:
		FeelConfig.DashInput.WASD_FALLBACK_TO_CURSOR:
			dir = input_dir if input_dir != Vector3.ZERO else to_cursor
		FeelConfig.DashInput.CURSOR:
			dir = to_cursor
		FeelConfig.DashInput.WASD:
			dir = input_dir
	if dir.length_squared() < 0.0001:
		dir = _facing_dir()
	_dash_dir = dir.normalized()

	var dist := cfg.ex_dash_distance if use_ex else cfg.mini_dash_distance
	var dur := cfg.ex_dash_duration if use_ex else cfg.mini_dash_duration
	_dash_speed = dist / dur
	_dash_time = dur
	_dash_airborne = airborne
	_dash_is_ex = use_ex
	_dash_held = 0.0
	if use_ex:
		ex_dash_cd = cfg.ex_dash_cooldown
	else:
		mini_dash_cd = cfg.mini_dash_cooldown
	_set_state(State.DASH)
	dashed.emit(use_ex)


func _process_dash(delta: float) -> void:
	_dash_time -= delta
	# Tap/hold kits: holding Shift upgrades the short dash into the long one,
	# and the ability goes on the long cooldown.
	if cfg.dash_hold_for_ex and not _dash_is_ex and Input.is_action_pressed("kf_dash"):
		_dash_held += delta
		if _dash_held >= cfg.dash_hold_threshold:
			_dash_is_ex = true
			_dash_time += cfg.ex_dash_duration - cfg.mini_dash_duration
			_dash_speed = cfg.ex_dash_distance / cfg.ex_dash_duration
			mini_dash_cd = cfg.ex_dash_cooldown
	velocity = _dash_dir * _dash_speed
	velocity.y = 0.0 if _dash_airborne else -2.0
	move_and_slide()
	if _dash_time <= 0.0:
		var grounded := is_on_floor()
		var carry := cfg.dash_exit_carry_ground if grounded else cfg.dash_exit_carry_air
		velocity = _dash_dir * _dash_speed * carry
		velocity.y = 0.0
		_set_state(State.GROUND if grounded else State.AIR)


# ---------------------------------------------------------------- mantle

func _try_mantle(input_dir: Vector3) -> void:
	if input_dir == Vector3.ZERO or velocity.y > cfg.mantle_max_upward_speed:
		return
	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3.UP * 0.5
	var q := PhysicsRayQueryParameters3D.create(origin, origin + input_dir * cfg.mantle_probe_distance)
	q.exclude = [get_rid()]
	var wall := space.intersect_ray(q)
	if wall.is_empty() or (wall.normal as Vector3).y > 0.3:
		return
	var probe_top: Vector3 = (wall.position as Vector3) - (wall.normal as Vector3) * 0.45 \
			+ Vector3.UP * (cfg.mantle_reach_up + 0.5)
	var q2 := PhysicsRayQueryParameters3D.create(probe_top,
			probe_top + Vector3.DOWN * (cfg.mantle_reach_up + 1.0))
	q2.exclude = [get_rid()]
	var top := space.intersect_ray(q2)
	if top.is_empty() or (top.normal as Vector3).y < 0.7:
		return
	var rise: float = (top.position as Vector3).y - global_position.y
	if rise < 0.25 or rise > cfg.mantle_reach_up:
		return
	_mantle_from = global_position
	_mantle_to = (top.position as Vector3) + Vector3.UP * 0.05
	_mantle_t = 0.0
	velocity = Vector3.ZERO
	_set_state(State.MANTLE)
	mantled.emit()


func _process_mantle(delta: float, input_dir: Vector3) -> void:
	_mantle_t = minf(_mantle_t + delta / cfg.mantle_duration, 1.0)
	var t := _mantle_t
	var flat := _mantle_from.lerp(_mantle_to, t * t)          # forward late
	var y := lerpf(_mantle_from.y, _mantle_to.y, 1.0 - pow(1.0 - t, 3.0))  # up early
	global_position = Vector3(flat.x, y, flat.z)
	if _mantle_t >= 1.0:
		velocity = input_dir * cfg.move_speed
		_set_state(State.GROUND)


# ---------------------------------------------------------------- aim, facing

func _active_camera() -> Camera3D:
	return _camera if _camera != null else get_viewport().get_camera_3d()


func _update_aim() -> void:
	var cam := _active_camera()
	if cam == null:
		return
	var mp := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mp)
	var dir := cam.project_ray_normal(mp)
	var plane := Plane(Vector3.UP, global_position.y + cfg.aim_plane_height)
	var hit: Variant = plane.intersects_ray(from, dir)
	if hit != null:
		aim_point = hit


func _input_direction() -> Vector3:
	if _stun > 0.0:
		return Vector3.ZERO
	var v := Input.get_vector("kf_move_left", "kf_move_right", "kf_move_up", "kf_move_down")
	var fwd := Vector3.FORWARD
	var right := Vector3.RIGHT
	var cam := _active_camera()
	if cam != null:
		var f := _flat(-cam.global_basis.z)
		if f.length_squared() > 0.0001:
			fwd = f.normalized()
			right = _flat(cam.global_basis.x).normalized()
	return right * v.x - fwd * v.y


func _update_facing(delta: float) -> void:
	if _visual == null:
		return
	var target := Vector3.ZERO
	if _face_aim_timer > 0.0:
		target = _flat(aim_point - global_position)
	elif state == State.DASH:
		target = _dash_dir
	else:
		target = _flat(velocity)
	if target.length_squared() < 0.04:
		return
	var yaw := atan2(-target.x, -target.z)
	_visual.rotation.y = lerp_angle(_visual.rotation.y, yaw, 1.0 - exp(-cfg.turn_rate * delta))


func _facing_dir() -> Vector3:
	if _visual != null:
		return _flat(-_visual.global_basis.z).normalized()
	return Vector3.FORWARD


func _build_laser() -> void:
	_laser = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.05, 0.02, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.25, 0.25, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	box.material = mat
	_laser.mesh = box
	_laser.top_level = true
	_laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_laser)


func _update_laser() -> void:
	if _laser == null:
		return
	var start := global_position + Vector3.UP * 0.1
	var to := _flat(aim_point - global_position)
	var length := minf(to.length(), cfg.aim_laser_length)
	if length < 0.1:
		_laser.visible = false
		return
	_laser.visible = true
	var dir := to.normalized()
	_laser.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), start + dir * length * 0.5)
	_laser.scale = Vector3(1.0, 1.0, length)


# ---------------------------------------------------------------- helpers

func _check_abyss_death() -> void:
	if global_position.y < ground_level - cfg.abyss_death_depth:
		_set_state(State.DEAD)
		velocity = Vector3.ZERO
		fell_into_abyss.emit()


func _set_state(s: State) -> void:
	if s == state:
		return
	if state == State.GLIDE:
		glide_ended.emit()
	state = s
	if s == State.GLIDE:
		glide_started.emit()


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
