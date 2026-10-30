extends Node3D
## Tooling: islands of the authored map from the match camera's angle, with no HUD and no sight fog,
## plus a few monsters, hunters and chests standing about, for checking the look of the world.
## Run with -- --art-view=<island id>[,<island id>...] --art-out=/path/prefix [--art-tier=N] [--art-wide]
## (one PNG per island: prefix_<id>.png), or with --shot=out.png --frames=N for a single island.

var views: Array = []
var out := ""
var wide := false
var cam: Camera3D
var w: World
var frame := 0
var cur := -1

func _ready() -> void:
	var tier := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--art-view="): views = a.substr(11).split(",")
		if a.begins_with("--art-tier="): tier = int(a.substr(11))
		if a.begins_with("--art-out="): out = a.substr(10)
		if a == "--art-wide": wide = true
	var T: Dictionary = Data.TIERS[tier]
	var env := WorldEnvironment.new()
	var sky: Color = T["sky"]; var amb: Color = T["ambient"]; var cl: Array = T["clouds"]
	env.environment = Look.environment({"top": sky.darkened(0.2), "mid": sky.lerp(amb, 0.35), "horizon": (cl[1] as Color).lerp(T["sun"], 0.5).lightened(0.15),
		"below": cl[0], "ambient": amb, "ambient_energy": 0.5, "fog": (cl[1] as Color).lightened(0.12).lerp(Color("4a5aa8"), 0.35), "sun_col": T["sun"]})
	add_child(env)
	var sun := Look.lights(self, T["sun"], 1.0, Vector3(-55, -35, 0), 60.0)
	sun.shadow_opacity = 0.8
	RenderingServer.global_shader_parameter_set("vis_on", 0.0)
	w = World.new()
	w.biome = T["biome"].duplicate()
	w.clouds = T["clouds"]
	add_child(w)
	w.generate_authored(World.load_layout("skyreach"), 9)
	w.build_meshes()
	cam = Camera3D.new()
	cam.fov = 35.0
	cam.far = 200.0
	add_child(cam)
	cam.make_current()
	for v in views:
		_stage(String(v))
	_next()

func _focus(id: String) -> Vector3:
	var focus := Vector3(108, 0, 108)
	for ii in w.islands.size():
		if String(w.islands[ii].get("id", "")) == id:
			focus = w._poi(ii) + Vector3(3.0, 0, 4.5)
	focus.y = w.ground_at(focus.x, focus.z) if not w.is_void(focus.x, focus.z) else 0.0
	return focus

## A few things standing about near an island's point of interest, the way a match would have them.
func _stage(id: String) -> void:
	var focus := _focus(id)
	var bj := World.load_biome(w.biome_at(focus.x, focus.z)) if w.biome_at(focus.x, focus.z) != "" else {}
	var taken: Array = []
	var things: Array = []
	for k in ["skitter", "spitter", "brute", "sentinel", "bomber"]:
		var n := Models.mob(k)
		for e in bj.get("mobs", []):
			if String(e["kind"]) == k:
				BiomeRun.recolor_mats(n.get_meta("mats", []), k, Color(String(e.get("color", "ffffff"))))
		things.append(n)
	things.append(Models.hunter("medium", Data.TEAM_COLORS[0], "rifle"))
	things.append(Models.hunter("heavy", Data.TEAM_COLORS[1], "shotgun"))
	things.append(Models.chest(1))
	things.append(Models.chest(0))
	things.append(Models.breakable("crate"))
	things.append(Models.breakable("barrel"))
	var rr := RandomNumberGenerator.new(); rr.seed = 5
	for i in things.size():
		var a := TAU * i / things.size() + 0.3
		var p := w.free_spot_near(focus + Vector3(cos(a), 0, sin(a)) * (3.0 + (i % 3) * 1.6), taken, 1.2, 0.5)
		taken.append(p)
		var n: Node3D = things[i]
		n.position = Vector3(p.x, w.ground_at(p.x, p.z), p.z)
		n.rotation.y = rr.randf() * TAU
		add_child(n)

func _next() -> void:
	cur += 1
	frame = 0
	if cur >= views.size():
		if out != "": get_tree().quit()
		return
	var focus := _focus(String(views[cur]))
	var pitch := deg_to_rad(55.0 if wide else 65.0)
	var dist := 46.0 if wide else 25.0
	cam.position = focus + Vector3(0, sin(pitch) * dist, cos(pitch) * dist)
	cam.rotation = Vector3(-pitch, 0, 0)

func _process(_d: float) -> void:
	if out == "" or cur >= views.size():
		return
	frame += 1
	if frame == 24:
		var path := "%s_%s.png" % [out, views[cur]]
		get_viewport().get_texture().get_image().save_png(path)
		print("SHOT ", path)
		_next()
