extends Node3D
## Playground for tuning feel. Builds two islands over an abyss, a ledge to
## mantle, pillars, a jump pad, and a debug HUD.
## F1/F2/F3 = Locked / Standard Dynamic / Fully Dynamic camera.

var hunter: HunterController
var rig: TopDownCameraRig
var hud: Label
const SPAWN := Vector3(0, 0.1, 8)


func _ready() -> void:
	_build_environment()
	_island(Vector3(0, -6, 0), Vector3(36, 12, 36), Color(0.38, 0.52, 0.36))
	_island(Vector3(0, -6, -38), Vector3(28, 12, 22), Color(0.42, 0.48, 0.38))  # 13m gap
	_island(Vector3(30, -5, -6), Vector3(10, 12, 10), Color(0.5, 0.45, 0.35))   # raised island, top at 1m
	_block(Vector3(-8, 1.25, -6), Vector3(6, 2.5, 4), Color(0.55, 0.5, 0.45))  # 2.5m ledge to mantle
	for p: Vector3 in [Vector3(6, 1.5, -4), Vector3(10, 1.5, 4), Vector3(-12, 1.5, 6)]:
		_block(p, Vector3(1.5, 3, 1.5), Color(0.45, 0.45, 0.5))
	_jump_pad(Vector3(0, 0, -14))
	_spawn_hunter()
	_spawn_camera()
	_build_hud()


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.5, 0.8)
	sky_mat.ground_bottom_color = Color(0.05, 0.04, 0.1)  # dark abyss below
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.shadow_enabled = true
	add_child(sun)


func _island(center: Vector3, size: Vector3, color: Color) -> void:
	_block(center, size, color)


func _block(center: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = center
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	bm.material = mat
	mesh.mesh = bm
	body.add_child(mesh)
	add_child(body)


func _jump_pad(at: Vector3) -> void:
	var pad := JumpPad.new()
	pad.position = at + Vector3(0, 0.3, 0)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.2
	cyl.height = 0.6
	shape.shape = cyl
	pad.add_child(shape)
	var mesh := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.2
	cm.bottom_radius = 1.2
	cm.height = 0.1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.8, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.6, 1.0)
	cm.material = mat
	mesh.mesh = cm
	pad.add_child(mesh)
	add_child(pad)


func _spawn_hunter() -> void:
	hunter = HunterController.new()
	hunter.name = "Hunter"
	hunter.position = SPAWN
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	shape.shape = cap
	shape.position.y = 0.9  # origin at feet
	hunter.add_child(shape)

	var visual := Node3D.new()
	visual.name = "Visual"
	var body_mesh := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.4
	cm.height = 1.8
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.7, 0.3)
	cm.material = mat
	body_mesh.mesh = cm
	body_mesh.position.y = 0.9
	visual.add_child(body_mesh)
	var nose := MeshInstance3D.new()
	var nm := BoxMesh.new()
	nm.size = Vector3(0.25, 0.25, 0.5)
	nose.mesh = nm
	nose.position = Vector3(0, 1.3, -0.5)
	visual.add_child(nose)
	hunter.add_child(visual)

	hunter.visual_path = NodePath("Visual")
	add_child(hunter)
	hunter.fell_into_abyss.connect(_on_fell)


func _spawn_camera() -> void:
	rig = TopDownCameraRig.new()
	rig.name = "CameraRig"
	rig.target_path = NodePath("../Hunter")
	add_child(rig)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	hud = Label.new()
	hud.position = Vector2(16, 16)
	hud.add_theme_font_size_override("font_size", 18)
	layer.add_child(hud)
	add_child(layer)


func _on_fell() -> void:
	await get_tree().create_timer(1.0).timeout
	hunter.respawn(hunter.last_safe_position + Vector3.UP * 0.2)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match (event as InputEventKey).physical_keycode:
			KEY_F1: rig.mode = TopDownCameraRig.Mode.LOCKED
			KEY_F2: rig.mode = TopDownCameraRig.Mode.STANDARD_DYNAMIC
			KEY_F3: rig.mode = TopDownCameraRig.Mode.FULLY_DYNAMIC


func _process(_delta: float) -> void:
	if hud == null or hunter == null:
		return
	var h := Vector3(hunter.velocity.x, 0, hunter.velocity.z)
	hud.text = "State: %s\nSpeed: %.2f m/s   Vy: %.2f\nHeat: %d%s\nDash: %.1fs   Ex-dash: %.1fs\nCamera: %s  (F1/F2/F3)\nWASD move | Space jump, hold to glide | Shift dash | Ctrl sneak" % [
		HunterController.State.keys()[hunter.state], h.length(), hunter.velocity.y,
		int(hunter.heat), "  OVERHEATED" if hunter.is_overheated else "",
		hunter.mini_dash_cd, hunter.ex_dash_cd,
		TopDownCameraRig.Mode.keys()[rig.mode]]
