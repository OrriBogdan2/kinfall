extends Node3D
## Tooling: the authored expedition map from straight above (or at an angle), with its place names.
## Run with -- --map-overview [--map-angle] --shot=out.png --frames=N

func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Look.environment({"top": Color("2a4a8a"), "mid": Color("6a8ad0"), "horizon": Color("ffd2a8"), "stars": 0.0})
	add_child(env)
	Look.lights(self, Color("fff1dc"), 1.0, Vector3(-55, -30, 0), 60.0)
	var w := World.new()
	w.biome = Data.TIERS[0]["biome"].duplicate()
	w.clouds = Data.TIERS[0]["clouds"]
	add_child(w)
	w.generate_authored(World.load_layout("skyreach"), 7)
	w.build_meshes()
	for lb in w.labels:
		var l := Label3D.new()
		l.text = String(lb["name"])
		l.font = UI.big; l.font_size = 64 if lb["kind"] == "poi" else 40; l.pixel_size = 0.06; l.outline_size = 16
		l.modulate = Color("fff4d8") if lb["kind"] == "poi" else (Color("ffe2a0") if lb["kind"] == "rail" else Color("ffb36a"))
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED; l.no_depth_test = true
		l.position = (lb["pos"] as Vector3) + Vector3(0, 6, 0)
		add_child(l)
	if not w.train_route.is_empty():
		# the sky train's loop, as a dotted amber line
		var s := 0.0
		while s < float(w.train_route["len"]):
			var q := w.train_at(s)
			var d := MeshInstance3D.new(); d.mesh = Models.box(0.9, 0.3, 0.9)
			d.material_override = Models.glow_mat(Color(1.0, 0.75, 0.35, 0.9 if q.y > -1.0 else 0.4))
			d.position = q
			add_child(d)
			s += 2.0
	for p in w.portal_spots:
		var m := MeshInstance3D.new(); m.mesh = Models.cyl(1.4, 1.4, 6.0, 12)
		m.material_override = Models.glow_mat(Color("8fe3c8")); m.position = p + Vector3(0, 3, 0)
		add_child(m)
	var cam := Camera3D.new()
	if "--map-angle" in OS.get_cmdline_user_args():
		cam.position = Vector3(112, 24, 141); cam.rotation = Vector3(-0.95, 0, 0); cam.fov = 42
	else:
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL; cam.size = 222.0
		cam.position = Vector3(108, 120, 108); cam.rotation = Vector3(-PI / 2, 0, 0)
	cam.far = 400.0
	add_child(cam)
	cam.make_current()
