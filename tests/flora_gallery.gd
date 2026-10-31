extends Node3D
## Tooling (--flora-gallery): every sculpted world prop (Flora) for each biome style, a row per
## style, under the match's light, for checking the look. --flora-close=<style> shows one style up
## close; --flora-stats prints vertex and triangle counts and build times. Use with --shot / --frames.

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var close := ""
	for a in args:
		if a.begins_with("--flora-close="): close = a.substr(14)
	var T: Dictionary = Data.TIERS[0]
	var env := WorldEnvironment.new()
	var sky: Color = T["sky"]; var amb: Color = T["ambient"]; var cl: Array = T["clouds"]
	env.environment = Look.environment({"top": sky.darkened(0.2), "mid": sky.lerp(amb, 0.35), "horizon": (cl[1] as Color).lerp(T["sun"], 0.5).lightened(0.15),
		"below": cl[0], "ambient": amb, "ambient_energy": 0.5, "fog": (cl[1] as Color).lightened(0.12).lerp(Color("4a5aa8"), 0.35), "sun_col": T["sun"]})
	add_child(env)
	var sun := Look.lights(self, T["sun"], 1.0, Vector3(-55, -35, 0), 60.0)
	sun.shadow_opacity = 0.8
	RenderingServer.global_shader_parameter_set("vis_on", 0.0)
	var kinds := ["tree", "tree", "tree", "rock", "rock", "bush", "bush", "fern", "flower", "mushroom", "reed", "crystal", "pebble"]
	var vars := [0, 1, 2, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0]
	var styles: Array = Flora.STYLES if close == "" else [close]
	var t0 := Time.get_ticks_usec()
	var tv := 0; var tt := 0
	for si in styles.size():
		var st: String = styles[si]
		var ground := MeshInstance3D.new()
		var pm := PlaneMesh.new(); pm.size = Vector2(kinds.size() * 2.2 + 2, 3.4)
		ground.mesh = pm
		var gm := StandardMaterial3D.new()
		var bc: Dictionary = World.load_biome(st).get("colors", {})
		gm.albedo_color = Color(String(bc.get("top", "7a9a5a")))
		gm.roughness = 1.0
		ground.material_override = gm
		ground.position = Vector3(kinds.size() * 1.1 - 1.1, 0, si * 3.6)
		add_child(ground)
		for k in kinds.size():
			var n := Flora.node(kinds[k], st, vars[k])
			n.position = Vector3(k * 2.2, 0, si * 3.6)
			n.rotation.y = 0.4 * k
			add_child(n)
			var m: Mesh = (n.get_child(0) as MeshInstance3D).mesh
			var a := m.surface_get_arrays(0)
			if si == 0 or "--flora-stats" in args:
				print("FLORA %-8s %-6s v%d verts %5d tris %5d" % [kinds[k], st, vars[k], (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3])
			tv += (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(); tt += (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	print("FLORA built %d meshes in %.1f ms (%d verts, %d tris)" % [kinds.size() * styles.size(), (Time.get_ticks_usec() - t0) / 1000.0, tv, tt])
	var cam := Camera3D.new()
	cam.fov = 35.0
	add_child(cam)
	if close == "":
		var c := Vector3(kinds.size() * 1.1 - 1.1, 0, (styles.size() - 1) * 1.8)
		cam.position = c + Vector3(0, 30, 22)
		cam.look_at(c + Vector3(0, 1.0, 0))
	else:
		var c := Vector3(9.0, 0, 0)
		cam.position = c + Vector3(0, 7.5, 11.0)
		cam.look_at(c + Vector3(0, 1.0, 0))
	cam.make_current()
