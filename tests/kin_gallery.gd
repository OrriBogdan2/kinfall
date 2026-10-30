extends Node3D
## Every kin species side by side, glowing as they do when they're out in a fight. Open
## tests/kin_gallery.tscn and press F6 to look at them (or to check a new kin you added in content/kin).

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("1b2030")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("b9c4e6")
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.5, 0)
	sun.light_energy = 1.1
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(30, 12)
	ground.mesh = pm
	ground.material_override = Models.toon(Color("5f8d45"), false)
	add_child(ground)
	var ids: Array = Data.KIN.keys()
	var close := "--kin-close" in OS.get_cmdline_user_args()
	var yaw := 0.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--kin-yaw="): yaw = float(a.substr(10))
	for i in ids.size():
		var k := Models.kin(String(ids[i]), {"level": 6})
		k.position = Vector3((i - (ids.size() - 1) * 0.5) * 1.6, 0, 0)
		k.rotation.y = PI + 0.35 + yaw
		k.scale = Vector3.ONE * 1.3
		add_child(k)
		var shell: MeshInstance3D = k.get_node_or_null("Body/Shell")
		if shell and not close:
			shell.visible = true
			(shell.material_override as ShaderMaterial).set_shader_parameter("strength", 0.6)
		var pt: CPUParticles3D = k.get_node_or_null("Aura")
		if pt: pt.emitting = true
		var ring := MeshInstance3D.new()
		ring.mesh = Models.flat_quad(1.4)
		ring.material_override = Models.ring_mat(Color(Data.TEAM_COLORS[0], 0.85), 0.16)
		ring.position = k.position + Vector3(0, 0.03, 0)
		add_child(ring)
		var l := Label3D.new()
		l.text = String(Data.KIN[ids[i]]["name"])
		l.font_size = 48; l.pixel_size = 0.005
		l.position = k.position + Vector3(0, 1.45, 0)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(l)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 4.2, 6.5)
	cam.rotation = Vector3(-0.55, 0, 0)
	cam.fov = 50
	if close:
		cam.position = Vector3(0, 1.6, 4.4); cam.rotation = Vector3(-0.22, 0, 0); cam.fov = 62
	add_child(cam)
	cam.make_current()
