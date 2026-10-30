extends Node3D
## Tooling: the imported (CC0 pack) props in rows, one row per biome style, under the match's lights,
## next to a hunter for scale. Run with -- --pack-gallery [--gallery=props|mobs] --shot=out.png --frames=N

func _ready() -> void:
	var T: Dictionary = Data.TIERS[0]
	var env := WorldEnvironment.new()
	var sky: Color = T["sky"]; var amb: Color = T["ambient"]; var cl: Array = T["clouds"]
	env.environment = Look.environment({"top": sky.darkened(0.2), "mid": sky.lerp(amb, 0.35), "horizon": (cl[1] as Color).lerp(T["sun"], 0.5).lightened(0.15),
		"below": cl[0], "ambient": amb, "ambient_energy": 0.5, "fog": (cl[1] as Color).lightened(0.12).lerp(Color("4a5aa8"), 0.35), "sun_col": T["sun"]})
	add_child(env)
	var sun := Look.lights(self, T["sun"], 1.0, Vector3(-55, -35, 0), 60.0)
	sun.shadow_opacity = 0.8
	RenderingServer.global_shader_parameter_set("vis_on", 0.0)
	var which := "props"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--gallery="): which = a.substr(10)
	if which == "mobs":
		_mobs()
	else:
		_props()

func _ground(c: Color, at: Vector3, size: Vector2) -> void:
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = size
	g.mesh = pm
	g.material_override = Models.toon(c, false)
	g.position = at
	add_child(g)

func _props() -> void:
	var styles := ["meadow", "bloom", "frost", "ember", "storm", "gloom"]
	var r := RandomNumberGenerator.new(); r.seed = 3
	for si in styles.size():
		var style: String = styles[si]
		var bj := World.load_biome(style)
		var cols: Dictionary = bj.get("colors", {})
		var top := Color(String(cols.get("top", "5f8d45")))
		var z := si * 3.2
		_ground(top, Vector3(6, 0, z), Vector2(26, 3.2))
		var row: Array = []
		row.append_array(Assets.trees(style))
		row.append_array(Assets.rocks(style))
		row.append(Assets.PILLARS[0])
		var x := -5.0
		var w := World.new()
		for v in row:
			var groups := {}
			# a one-tile fake world so _pack_prop can read the biome
			w.w = 1; w.h = 1
			w.island = PackedInt32Array([0]); w.islands = [{"biome": style, "c": Vector2.ZERO}]
			var bc := {}
			for k in cols: bc[k] = Color(String(cols[k]))
			w.biome = bc
			w._isl_bio = [bc]
			var what := "tree" if Assets.trees(style).has(v) else ("rock" if Assets.rocks(style).has(v) else "ruin")
			var list_backup = v
			# force this variant: a list of one
			var am := Assets.mesh(String(v["m"]))
			if am == null: continue
			var mm := {}
			if w._pack_prop_variant(mm, what, 0, Vector3(x, 0, z), r, list_backup):
				for key in mm:
					var g: Dictionary = mm[key]
					w._chunked(self, g["items"], g["mesh"], g["mat"], "g", true)
			x += 1.7
		w.free()
		var hu := Models.hunter("medium", Data.TEAM_COLORS[0], "rifle")
		hu.position = Vector3(x + 0.5, 0, z)
		add_child(hu)
	var cam := Camera3D.new()
	cam.fov = 40
	cam.position = Vector3(5.5, 17.0, 26.0)
	cam.rotation = Vector3(-0.72, 0, 0)
	add_child(cam)
	cam.make_current()

func _mobs() -> void:
	_ground(Color("5f8d45"), Vector3(0, 0, 0), Vector2(30, 10))
	var ids: Array = Data.MOBS.keys()
	for i in ids.size():
		var n := Models.mob(String(ids[i]))
		n.position = Vector3((i - (ids.size() - 1) * 0.5) * 2.4, 0, 0)
		n.rotation.y = 0.4
		add_child(n)
	var hu := Models.hunter("medium", Data.TEAM_COLORS[0], "rifle")
	hu.position = Vector3(-(ids.size() + 1) * 1.2, 0, 0)
	add_child(hu)
	var cam := Camera3D.new()
	cam.fov = 40
	cam.position = Vector3(0, 7.5, 11.0)
	cam.rotation = Vector3(-0.55, 0, 0)
	add_child(cam)
	cam.make_current()
