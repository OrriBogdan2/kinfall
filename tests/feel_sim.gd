extends SceneTree
## Headless feel check: godot --headless --path . -s tests/feel_sim.gd

var world: Node3D
var h: HunterController
var flags := {}


func _initialize() -> void:
	world = load("res://tests/feel_test.tscn").instantiate()
	root.add_child(world)
	_run()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _press(a: String) -> void:
	Input.action_press(a)


func _release(a: String) -> void:
	Input.action_release(a)


func _flat_speed() -> float:
	return Vector2(h.velocity.x, h.velocity.z).length()


func _run() -> void:
	await _frames(2)
	h = world.hunter
	await _frames(30)
	print("settled state=", HunterController.State.keys()[h.state], " y=%.2f" % h.global_position.y)

	# 1. Acceleration
	var t := 0
	_press("kf_move_up")
	while _flat_speed() < h.cfg.move_speed * 0.95 and t < 120:
		await _frames(1); t += 1
	print("time to 95%% speed: %.3fs" % (t / 60.0))
	var p0 := h.global_position
	await _frames(60)
	print("distance in 1s: %.2fm (dir z=%.2f, W should be -z)" % [(h.global_position - p0).length(), (h.global_position - p0).z])
	_release("kf_move_up")
	t = 0
	while _flat_speed() > 0.05 and t < 120:
		await _frames(1); t += 1
	print("stop time: %.3fs" % (t / 60.0))

	# 2. Jump
	await _frames(10)
	var base_y := h.global_position.y
	_press("kf_jump"); await _frames(1); _release("kf_jump")
	var apex := base_y
	t = 0
	while t < 90:
		await _frames(1); t += 1
		apex = maxf(apex, h.global_position.y)
		if h.state == HunterController.State.GROUND and t > 5:
			break
	print("jump apex: %.2fm, airtime %.2fs" % [apex - base_y, t / 60.0])

	# 3. Mini dash then ex dash
	await _frames(10)
	h.respawn(Vector3(0, 0.1, 10)); await _frames(20)
	p0 = h.global_position
	_press("kf_move_right"); _press("kf_dash"); await _frames(1); _release("kf_dash")
	await _frames(12)
	print("mini dash: %.2fm in 0.2s, cd=%.1f, exit speed %.2f" % [(h.global_position - p0).length(), h.mini_dash_cd, _flat_speed()])
	_release("kf_move_right")
	await _frames(30)
	p0 = h.global_position
	_press("kf_move_left"); _press("kf_dash"); await _frames(1); _release("kf_dash")
	await _frames(16)
	print("ex dash (mini on cd): %.2fm, ex_cd=%.1f" % [(h.global_position - p0).length(), h.ex_dash_cd])
	_release("kf_move_left")

	# 4. Glide across the abyss gap (island 1 edge z=-18, island 2 edge z=-27)
	h.respawn(Vector3(0, 0.1, -15)); await _frames(30)
	h.mini_dash_cd = 0; h.ex_dash_cd = 0
	_press("kf_move_up")
	await _frames(30)
	_press("kf_jump"); _press("kf_glide")
	await _frames(1); _release("kf_jump")
	var min_y := 99.0
	var glide_frames := 0
	t = 0
	var crossed := false
	while t < 600:
		await _frames(1); t += 1
		min_y = minf(min_y, h.global_position.y)
		if h.state == HunterController.State.GLIDE: glide_frames += 1
		if h.global_position.z < -28.0 and not crossed:
			crossed = true
			print("crossed 13m gap in %.2fs, lowest y=%.2f, heat=%d, glide speed %.2f" % [t / 60.0, min_y, int(h.heat), _flat_speed()])
			break
	if not crossed:
		print("FAILED to cross gap: z=%.2f y=%.2f state=%s" % [h.global_position.z, h.global_position.y, HunterController.State.keys()[h.state]])
	_release("kf_move_up")

	# 5. Hover over abyss until overheat
	h.respawn(Vector3(0, 0.1, -15)); await _frames(20)
	h.global_position = Vector3(40, 0.5, 20)  # over the abyss, ground_level stays 0
	h.velocity = Vector3.ZERO
	t = 0
	var over_at := -1.0
	var min_hover := 99.0
	while t < 900:
		await _frames(1); t += 1
		if t > 60: min_hover = minf(min_hover, h.global_position.y)
		if h.is_overheated and over_at < 0: over_at = t / 60.0
		if h.state == HunterController.State.DEAD: break
	print("abyss hover: overheat at %.2fs, hover min y after settle %.2f, state=%s" % [over_at, min_hover, HunterController.State.keys()[h.state]])
	_release("kf_glide")

	# 6. Abyss recovery: fall below ground level, open glider
	h.respawn(Vector3(40, -6, 20)); h.ground_level = 0.0
	h.velocity = Vector3(0, -6, 0)
	_press("kf_glide")
	t = 0
	var max_vy := -99.0
	while t < 180:
		await _frames(1); t += 1
		max_vy = maxf(max_vy, h.velocity.y)
		if h.global_position.y > -0.3: break
	print("abyss lift: back to ground level in %.2fs, peak rise %.1f m/s, y=%.2f" % [t / 60.0, max_vy, h.global_position.y])
	_release("kf_glide")
	# feather: release before ground to convert lift into height
	h.respawn(Vector3(40, -8, 20)); h.ground_level = 0.0
	_press("kf_glide")
	while h.global_position.y < -3.0:
		await _frames(1)
	_release("kf_glide")
	var top := -99.0
	for i in 60:
		await _frames(1)
		top = maxf(top, h.global_position.y)
	print("feathered release at y=-3: peak y=%.2f" % top)

	# 7. Mantle onto raised island (top y=1, west face x=25) from below edge
	h.respawn(Vector3(24.45, -6.0, -6)); h.ground_level = 0.0
	h.velocity = Vector3.ZERO
	_press("kf_move_right")
	h.mantled.connect(func(): flags["mantled"] = true)
	await _frames(40)
	_release("kf_move_right")
	await _frames(20)
	print("mantle triggered=%s, state=%s, y=%.2f (island top 1.0)" % [flags.get("mantled", false), HunterController.State.keys()[h.state], h.global_position.y])

	# 7b. Zik drill: walk off an edge, free-fall 1s, open glider, get back up
	h.respawn(Vector3(0, 0.1, 16.5)); await _frames(20)
	_press("kf_move_down")
	t = 0
	while h.global_position.z < 18.6 and t < 120:
		await _frames(1); t += 1
	_release("kf_move_down")
	var fell_at := t
	var balloon_seen := -1
	for i in 60:
		await _frames(1)
		if balloon_seen < 0 and h._balloon.visible: balloon_seen = i
	var deep := h.depth_below_ground()
	_press("kf_glide")
	t = 0
	while h.depth_below_ground() > 0.3 and t < 180:
		await _frames(1); t += 1
	print("walk-off: balloon after %.2fs, depth after 1s fall %.1fm, glide back to ground level in %.2fs, heat %d" % [balloon_seen / 60.0, deep, t / 60.0, int(h.heat)])
	# spikeable while below ground? hit while gliding drops the glider
	var mult := h.incoming_damage_multiplier()
	h.notify_damaged()
	print("hit while gliding: took x%.1f damage, then state=%s" % [mult, HunterController.State.keys()[h.state]])
	_release("kf_glide")

	# 8. Jump pad at z=-14
	h.respawn(Vector3(0, 0.1, -8)); await _frames(20)
	_press("kf_move_up")
	var pad_apex := -99.0
	for i in 150:
		await _frames(1)
		pad_apex = maxf(pad_apex, h.global_position.y)
	_release("kf_move_up")
	print("jump pad apex: %.2fm" % pad_apex)

	# 9. Fall to death
	h.respawn(Vector3(40, 0.5, 20)); h.ground_level = 0.0
	h.fell_into_abyss.connect(func(): flags["died"] = true)
	await _frames(240)
	print("abyss death without glide=%s" % flags.get("died", false))
	await _frames(90)
	print("respawned state=%s" % HunterController.State.keys()[h.state])

	# 10. Camera modes
	var rig: TopDownCameraRig = world.rig
	for m in [0, 1, 2]:
		rig.mode = m
		await _frames(5)
		print("camera mode %s: pan=%.1f deadzone=%.1f pos=%s" % [TopDownCameraRig.Mode.keys()[m], rig.pan_distance, rig.deadzone, rig.camera.global_position.snapped(Vector3.ONE * 0.1)])
	quit()
