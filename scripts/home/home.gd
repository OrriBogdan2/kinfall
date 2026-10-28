extends Node3D
## The home island: walk around the farm, tend crops, cook, shop, spend time with your kin,
## and step through the portal to start an expedition.

const SPEED := 5.0

var world: World
var cam: CamRig
var fx: Fx
var ui: CanvasLayer
var root_ui: Control
var panel_host: Control
var topbar: Label
var prompt_box: PanelContainer
var prompt_lbl: Label
var hint: Label
var player: Node3D
var ppos := Vector3.ZERO
var pvel := Vector3.ZERO
var py := 0.0               # height of a jump
var farm_t := 0.0
var pvy := 0.0
const JUMP_V := 8.5
const GRAV := 26.0
var pface := 0.0
var walk_ph := 0.0
var kins: Array = []           # {rec, node, pos, vel, goal, t, emote, emote_t, hop}
var spots := {}                # name -> Vector3
var plots: Array = []          # nodes, index matches Save plots
var interact := {}
var panel_open := ""
var chat_log: Array = []       # [{role, content}]
var chat_kin: Dictionary = {}
var chat_box: VBoxContainer
var chat_scroll: ScrollContainer
var chat_input: LineEdit
var chat_busy := false
var chat_offline_noted := false
var emote_labels: Array = []
var pet_done := {}

var lots := {}                 # building id -> {node, built}
var visit: Dictionary = {}     # when visiting someone: their island snapshot (see Social.publish_profile)
var visit_id := ""
var petted := {}

## The island being shown: yours, or the one you're visiting.
func _d() -> Dictionary:
	return visit if not visit.is_empty() else Save.d

func _has_b(b: String) -> bool:
	return _d().get("buildings", []).has(b)

func _has_br(k: String) -> bool:
	return _d().get("bridges", []).has(k)
var bridges := {}              # isle id -> {tiles, node, built, label}
var gh_plots: Array = []
var building_now := false
# ---- day, night and weather
const DAY_LEN := 300.0          # seconds for a full day at home
var env_res: Environment
var sun_l: DirectionalLight3D
var lamps: Array = []           # OmniLight3D
var day_t := 0.3                # 0..1, 0.25 is morning, 0.5 noon, 0.75 dusk
var rain: CPUParticles3D
var raining := false
var rain_k := 0.0
var weather_t := 40.0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.play_ambience("home")
	Sfx.new_track.connect(_on_new_track)
	var dbg := OS.get_cmdline_user_args()
	if "--evo-test" in dbg:
		var ek := Save.active_kin()
		ek["level"] = 7
		ek["forms"] = []; ek["muts"] = []
		Evo.simulate(ek, RandomNumberGenerator.new())
		ek["level"] = 8
		Game._evolve(ek, {})
		Save.d["tutorial"]["home"] = true
	if "--home-all" in dbg:
		Save.d["bridges"] = Data.ISLES.keys()
		Save.d["buildings"] = Data.BUILDINGS.keys()
	_build_env()
	world = World.new(); add_child(world)
	world.make_home(4242)
	var path_col := Color("9c7a52")
	# your house up north, a path from its door down to the portal, branches to the market, the farm and the bridges
	spots["house"] = Vector3(38.0, 0, 26.5)
	world.set_block_rect(36, 25, 40, 27)
	spots["portal"] = Vector3(38.0, 0, 39.0)
	world.paint_path(Vector2i(37, 28), Vector2i(37, 38), path_col)
	world.paint_path(Vector2i(39, 31), Vector2i(42, 31), path_col, false)
	world.paint_path(Vector2i(24, 30), Vector2i(36, 30), path_col, false)
	world.paint_path(Vector2i(39, 38), Vector2i(50, 38), path_col, false)
	world.paint_path(Vector2i(44, 21), Vector2i(44, 28), path_col, false)
	world.paint_path(Vector2i(28, 31), Vector2i(28, 34), path_col, false)
	spots["stall"] = Vector3(30.5, 0, 33.0)
	world.set_block_rect(29, 32, 31, 33)
	spots["pot"] = Vector3(42.5, 0, 27.5)
	world.set_block_rect(42, 27, 42, 27)
	for z in range(30, 38):
		for x in range(43, 48):
			world.paint_tile(x, z, Color("6b4a33"))
	world.set_block_rect(32, 36, 34, 38)   # pond
	# a few trees around the rim of every island, kept away from paths, lots and bridges
	world.add_trees_on_rim(34)
	var keep_clear: Array = [[36, 34, 40, 44], [42, 28, 50, 40], [41, 20, 47, 26], [22, 28, 28, 32], [53, 36, 66, 43]]
	for b in Data.BUILDINGS:
		var rc: Array = Data.BUILDINGS[b]["rect"]
		keep_clear.append([rc[0] - 1, rc[1] - 1, rc[2] + 1, rc[3] + 2])
	for k in Data.ISLES:
		var rc: Array = Data.ISLES[k]["bridge"]
		keep_clear.append([rc[0] - 2, rc[1] - 2, rc[2] + 2, rc[3] + 2])
	for rc in keep_clear:
		for z in range(rc[1], rc[3] + 1):
			for x in range(rc[0], rc[2] + 1):
				if world.inb(x, z) and world.kind[world.idx(x, z)] == World.T_BLOCK and not world.no_deco.has(world.idx(x, z)):
					world.kind[world.idx(x, z)] = World.T_GROUND
	# bridges: work out which tiles they cover before any are opened
	for k in Data.ISLES:
		bridges[k] = {"tiles": world.bridge_tiles(Data.ISLES[k]["bridge"]), "built": _has_br(k)}
		if bridges[k]["built"]:
			world.open_bridge(bridges[k]["tiles"])
	for b in Data.BUILDINGS:
		if _has_b(b):
			var rc: Array = Data.BUILDINGS[b]["rect"]
			world.set_block_rect(rc[0], rc[1], rc[2], rc[3])
	world.build_meshes()
	fx = Fx.new(); add_child(fx)
	cam = CamRig.new(); add_child(cam)
	cam.zoom_to = 0.8; cam.zoom = 0.8; cam.lead = 0.2
	var house := Models.house(); house.position = spots["house"]; add_child(house)
	var pot := Models.cauldron(); pot.position = spots["pot"]; add_child(pot)
	var stall := Models.stall(); stall.position = spots["stall"]; stall.rotation.y = PI * 0.5; add_child(stall)
	var portal := Models.portal(UI.TEAL); portal.position = spots["portal"]; add_child(portal)
	portal.get_node("Disc").visible = true
	(portal.get_node("Beam") as CPUParticles3D).emitting = true
	var drng := RandomNumberGenerator.new(); drng.seed = 77
	var pond := Models.pond(1.9, 1.5); pond.position = Vector3(33.5, 0, 37.5); add_child(pond)
	for fp in [[Vector3(45.4, 0, 29.4), 0.0, 5.0], [Vector3(45.4, 0, 37.6), 0.0, 5.0], [Vector3(47.8, 0, 33.5), PI / 2, 8.0], [Vector3(42.4, 0, 35.6), PI / 2, 4.0]]:
		var f := Models.fence(fp[2]); f.position = fp[0]; f.rotation.y = fp[1]; add_child(f)
	for lp in [Vector3(36.2, 0, 30.0), Vector3(39.6, 0, 35.5), Vector3(34.5, 0, 34.2), Vector3(41.0, 0, 30.0), Vector3(26.0, 0, 29.2), Vector3(51.2, 0, 36.6)]:
		var l := Models.lamp(); l.position = lp; add_child(l)
		for ch in l.get_children():
			if ch is OmniLight3D: lamps.append(ch)
	for fb in [Vector3(35.6, 0, 28.6), Vector3(40.4, 0, 28.6), Vector3(39.6, 0, 37.4)]:
		var fbed := Models.flower_bed(drng); fbed.position = fb; add_child(fbed)
	spots["ferry"] = Vector3(42.2, 0, 40.6)
	var fpost := Models.ferry_post(); fpost.position = spots["ferry"]; fpost.rotation.y = -0.4; add_child(fpost)
	var sign_post := Models.signpost(["Expeditions"]); sign_post.position = Vector3(39.8, 0, 38.2); sign_post.rotation.y = -0.3; add_child(sign_post)
	var roster: Array = _d()["roster"]
	for i in mini(roster.size(), 6):
		var bed := Models.kin_bed(Data.KIN[roster[i]["species"]]["color"])
		bed.position = Vector3(33.4 + (i % 3) * 1.1, 0, 27.6 + (i / 3) * 1.1)
		add_child(bed)
	_build_lots()
	_build_bridges()
	_build_plots()
	var hero0 := _hero()
	player = Models.hunter(Data.HEROES[hero0]["cls"], Data.TEAM_COLORS[0], _weapon(), hero0)
	add_child(player)
	ppos = Vector3(38.0, 0, 34.5)
	player.position = ppos
	cam.snap(ppos)
	for a in dbg:
		if a.begins_with("--home-zoom="):
			cam.zoom_to = float(a.substr(12)); cam.zoom = cam.zoom_to
		if a.begins_with("--home-build="):
			var bk := a.substr(13)
			Save.d["bridges"].append(bk)
			get_tree().create_timer(0.3).timeout.connect(func(): _build_bridge_now(bk))
		if a.begins_with("--home-construct="):
			var cb := a.substr(17)
			Save.d["buildings"].append(cb)
			get_tree().create_timer(0.3).timeout.connect(func(): _construct(cb))
		if a == "--home-night": day_t = 0.97
		if a == "--home-noon": day_t = 0.5
		if a == "--home-rain":
			raining = true; rain_k = 1.0; rain.emitting = true; weather_t = 999.0
		if a == "--farm-test":
			# test: a farm in every state, with a farmhand on duty
			Save.d["plot_cap"] = 8
			_build_plots()
			var ks: Array = Data.CROPS.keys()
			for i in 8:
				Save.d["plots"][i] = {"crop": ks[i % ks.size()], "stage": i % 3, "care": 0, "wt": (Time.get_unix_time_from_system() - 85.0) if i % 2 == 0 else 0.0}
				_refresh_plot("plots", i)
			Save.active_kin()["farmhand"] = true
		if a.begins_with("--open="):
			var which := a.substr(7)
			get_tree().create_timer(0.2).timeout.connect(func():
				if which == "loadout": _open_loadout()
				elif which == "expedition": _open_expedition()
				elif which == "kin": _open_kin(Save.active_kin())
				elif which == "shop": _open_shop()
				elif which == "kitchen": _open_kitchen()
				elif which == "plot": _open_plot("plots", 0))
		if a.begins_with("--home-at="):
			var xy := a.substr(10).split(",")
			ppos = Vector3(float(xy[0]), 0, float(xy[1])); player.position = ppos; cam.snap(ppos)
	_spawn_kin()
	if "--hero-lineup" in dbg:
		var hi := 0
		for hid in Data.HEROES:
			var hm := Models.hunter(Data.HEROES[hid]["cls"], Data.TEAM_COLORS[0], Data.HEROES[hid]["weapon"], hid)
			hm.position = Vector3(34.0 + (hi % 5) * 1.9, 0, 31.5 + (hi / 5) * 2.2)
			hm.rotation.y = PI * 0.85
			add_child(hm)
			hi += 1
	if "--kin-lineup" in dbg:
		var lr := RandomNumberGenerator.new(); lr.seed = 11
		var sps: Array = Data.KIN.keys()
		for i in 12:
			var rr := Save.new_kin(sps[i % sps.size()])
			rr["level"] = [1, 4, 8, 12, 16, 22][i / 2]
			Evo.simulate(rr, lr)
			var kn := Models.kin(rr["species"], rr)
			kn.position = Vector3(33.5 + (i % 6) * 1.7, 0, 32.5 + (i / 6) * 1.8)
			kn.rotation.y = PI * 0.1
			kn.scale *= 1.3
			add_child(kn)
	_build_ui()
	_refresh_top()
	if not visit.is_empty():
		pass
	elif not Save.d["tutorial"].get("home", false):
		_open_welcome()
	else:
		_play_evolutions()
	if visit.is_empty() and Social.available():
		Social.publish_profile(true)
		Social.collect_gifts(func(lines: Array):
			if lines.size() > 0 and is_inside_tree():
				_show_when_free(lines))
		Social.collect_payouts(func(total: int):
			if total > 0 and is_inside_tree():
				_toast("The market paid you %d gems" % total)
				_refresh_top())
	# a kin with lines written by Claude keeps them fresh
	var ak := Save.active_kin()
	if visit.is_empty() and Bridge.ai_ok and not ak.is_empty() and int(ak.get("matches", 0)) % 3 == 0:
		Bridge.refresh_lines(ak)

func _rect_center(rc: Array) -> Vector3:
	return Vector3((rc[0] + rc[2] + 1) * 0.5, 0, (rc[1] + rc[3] + 1) * 0.5)

func _isle_open(isle: String) -> bool:
	return isle == "main" or _has_br(isle)

# ---- buildings and building sites
func _build_lots() -> void:
	for b in Data.BUILDINGS:
		var bd: Dictionary = Data.BUILDINGS[b]
		var rc: Array = bd["rect"]
		var at := _rect_center(rc)
		var holder := Node3D.new(); holder.position = at; add_child(holder)
		var built := _has_b(b)
		var n: Node3D
		if built:
			n = Models.building(b)
		else:
			n = Models.lot(rc[2] - rc[0] + 1.0, rc[3] - rc[1] + 1.0, bd["name"], "%d gems" % int(bd["cost"]))
		holder.add_child(n)
		lots[b] = {"node": holder, "built": built, "at": at, "door": at + Vector3(0, 0, (rc[3] - rc[1] + 1) * 0.5 + 1.1)}

func _build_bridges() -> void:
	for k in Data.ISLES:
		var isd: Dictionary = Data.ISLES[k]
		var br: Dictionary = bridges[k]
		var node := Node3D.new(); add_child(node)
		br["node"] = node
		var sg := Models.signpost([isd["name"]]); sg.position = Vector3(isd["sign"].x, 0, isd["sign"].y); add_child(sg)
		br["sign"] = sg
		if br["built"]:
			_lay_planks(k, false)
		else:
			_bridge_stub(k)
		var lbl := Label3D.new()
		lbl.font = UI.big; lbl.font_size = 64; lbl.pixel_size = 0.012; lbl.outline_size = 16
		lbl.outline_modulate = Color(0.05, 0.04, 0.08, 0.9)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.text = "%s\n%d gems to bridge" % [isd["name"], int(isd["cost"])]
		lbl.modulate = UI.GOLD
		lbl.position = Vector3(isd["c"].x, 3.2, isd["c"].y)
		lbl.visible = not br["built"]
		add_child(lbl)
		br["label"] = lbl

func _bridge_axis(k: String) -> Dictionary:
	var rc: Array = Data.ISLES[k]["bridge"]
	var horiz: bool = rc[2] - rc[0] > rc[3] - rc[1]
	return {"horiz": horiz, "width": (rc[3] - rc[1] + 1.0) if horiz else (rc[2] - rc[0] + 1.0),
		"mid": (rc[1] + rc[3] + 1) * 0.5 if horiz else (rc[0] + rc[2] + 1) * 0.5}

## Plank positions along the bridge, ordered from the home island outward.
func _plank_spots(k: String) -> Array:
	var ax := _bridge_axis(k)
	var along := {}
	for t in bridges[k]["tiles"]:
		along[t.x if ax["horiz"] else t.y] = true
	var out: Array = []
	for a in along.keys():
		for half in [0.25, 0.75]:
			var u: float = a + half
			out.append(Vector3(u, -0.07, ax["mid"]) if ax["horiz"] else Vector3(ax["mid"], -0.07, u))
	var mc := Vector3(38, 0, 32)
	out.sort_custom(func(p, q): return Vector2(p.x - mc.x, p.z - mc.z).length() < Vector2(q.x - mc.x, q.z - mc.z).length())
	return out

func _bridge_stub(k: String) -> void:
	var spots_l := _plank_spots(k)
	if spots_l.is_empty():
		return
	var node: Node3D = bridges[k]["node"]
	var ax := _bridge_axis(k)
	var p0: Vector3 = spots_l[0]
	var side := Vector3(0, 0, 1) if ax["horiz"] else Vector3(1, 0, 0)
	for sgn in [-1.0, 1.0]:
		var post := Models.part(node, Models.box(0.16, 1.2, 0.16), Models.toon(Color("7a5a3c")), p0 + side * sgn * (ax["width"] * 0.5) + Vector3(0, 0.6, 0))
		post.name = "Post"
	var rng := RandomNumberGenerator.new(); rng.seed = 5
	for i in 2:
		var pl := Models.plank(rng, ax["width"] + 0.1)
		pl.position = p0 + Vector3(0, 0.07, 0)
		if ax["horiz"]: pl.rotation.y += PI / 2
		node.add_child(pl)

func _lay_planks(k: String, animate: bool) -> void:
	var node: Node3D = bridges[k]["node"]
	for c in node.get_children():
		c.queue_free()
	var ax := _bridge_axis(k)
	var rng := RandomNumberGenerator.new(); rng.seed = k.hash()
	var sp := _plank_spots(k)
	var side := Vector3(0, 0, 1) if ax["horiz"] else Vector3(1, 0, 0)
	var rope := Models.toon(Color("e8d8b0"), false)
	var post_m := Models.toon(Color("7a5a3c"))
	for i in sp.size():
		var p: Vector3 = sp[i]
		var pl := Models.plank(rng, ax["width"] + 0.1)
		pl.position = p
		if ax["horiz"]: pl.rotation.y += PI / 2
		node.add_child(pl)
		var extra: Array = [pl]
		if i % 4 == 0 or i == sp.size() - 1:
			for sgn in [-1.0, 1.0]:
				extra.append(Models.part(node, Models.box(0.12, 0.9, 0.12), post_m, p + side * sgn * (ax["width"] * 0.5 + 0.05) + Vector3(0, 0.4, 0)))
		if i < sp.size() - 1:
			var q: Vector3 = sp[i + 1]
			for sgn in [-1.0, 1.0]:
				var a: Vector3 = p + side * sgn * (ax["width"] * 0.5 + 0.05) + Vector3(0, 0.75, 0)
				var b: Vector3 = q + side * sgn * (ax["width"] * 0.5 + 0.05) + Vector3(0, 0.75, 0)
				var r := Models.part(node, Models.box(0.04, 0.04, a.distance_to(b) + 0.02), rope, (a + b) * 0.5)
				r.look_at_from_position((a + b) * 0.5, b, Vector3.UP)
				extra.append(r)
		if animate:
			for e in extra:
				var tgt: Vector3 = e.position
				e.position = tgt + Vector3(0, -2.5, 0)
				e.scale = Vector3.ONE * 0.2
				var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				tw.tween_interval(i * 0.06)
				tw.tween_property(e, "position", tgt, 0.3)
				tw.parallel().tween_property(e, "scale", Vector3.ONE, 0.3)
			if i % 3 == 0:
				get_tree().create_timer(i * 0.06 + 0.25).timeout.connect(func():
					Sfx.play("build", null, -6.0, 0.12)
					fx.dust(p, 6))

func _build_env() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("1a2236")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("c4cbe6")
	e.ambient_light_energy = 0.42
	e.glow_enabled = true
	e.glow_intensity = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	env_res = e
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_color = Color("ffe9cf")
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 45.0
	add_child(sun)
	sun_l = sun
	# the day picks up where you left it, based on the clock
	day_t = fmod(Time.get_unix_time_from_system() / DAY_LEN, 1.0)
	rain = CPUParticles3D.new()
	rain.amount = 260; rain.lifetime = 0.9; rain.emitting = false
	var dm := BoxMesh.new(); dm.size = Vector3(0.025, 0.4, 0.025)
	var rm := StandardMaterial3D.new(); rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(0.75, 0.82, 1.0, 0.45); rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.material = rm
	rain.mesh = dm
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(16, 0.5, 12)
	rain.direction = Vector3(0.15, -1, 0); rain.spread = 3.0
	rain.gravity = Vector3(0, -30, 0)
	rain.initial_velocity_min = 14.0; rain.initial_velocity_max = 18.0
	add_child(rain)

func _build_plots() -> void:
	for n in plots:
		n.queue_free()
	plots.clear()
	for n in gh_plots:
		n.queue_free()
	gh_plots.clear()
	var cap: int = int(Save.d["plot_cap"]) if visit.is_empty() else (_d()["plots"] as Array).size()
	while _d()["plots"].size() < cap:
		_d()["plots"].append({"crop": "", "stage": 0})
	for i in cap:
		var p := Models.plot()
		p.position = Vector3(44.2 + (i % 2) * 2.2, 0, 30.8 + (i / 2) * 2.0)
		add_child(p)
		plots.append(p)
		_refresh_plot("plots", i)
	if _has_b("greenhouse") and _d().get("gh_plots", []).size() >= 4:
		for i in 4:
			var p := Models.plot()
			p.position = Vector3(57.5 + i * 2.2, 0, 40.4)
			add_child(p)
			gh_plots.append(p)
			_refresh_plot("gh_plots", i)

func _plot_node(arr: String, i: int) -> Node3D:
	return plots[i] if arr == "plots" else gh_plots[i]

func _refresh_plot(arr: String, i: int) -> void:
	var p: Node3D = _plot_node(arr, i)
	var holder: Node3D = p.get_node("Crop")
	for ch in holder.get_children():
		ch.queue_free()
	var d: Dictionary = _d()[arr][i]
	(p.get_node("Wet") as Node3D).visible = d["crop"] != "" and float(d.get("wt", 0.0)) > 0.0
	if d["crop"] != "":
		var cd: Dictionary = Data.CROPS[d["crop"]]
		holder.add_child(Models.crop(int(d["stage"]), int(cd["grow"]), cd["color"]))

func _spawn_kin() -> void:
	for k in kins:
		k["node"].queue_free()
	kins.clear()
	var open_isles: Array = [0]
	for i in world.islands.size():
		if i > 0 and _isle_open(world.islands[i]["id"]):
			open_isles.append(i)
	var ri := 0
	for rec in _d()["roster"]:
		var n := Models.kin(rec["species"], rec)
		add_child(n)
		var isl: int = 0 if rec["uid"] == _d().get("active", "") else open_isles[ri % open_isles.size()]
		ri += 1
		var at := world.random_ground(isl)
		n.position = at
		var lbl := Label3D.new()
		lbl.font = UI.big; lbl.font_size = 40; lbl.pixel_size = 0.01; lbl.outline_size = 10
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED; lbl.no_depth_test = true
		lbl.position.y = 1.15; lbl.visible = false
		n.add_child(lbl)
		var kd := {"rec": rec, "node": n, "pos": at, "vel": Vector3.ZERO, "goal": Vector3.INF, "t": randf() * 3.0, "emote": lbl, "emote_t": 0.0, "hop": randf() * 6.0}
		var ri2: int = _d()["roster"].find(rec)
		if isl == 0 and ri2 >= 0 and ri2 < 6:
			kd["bed"] = Vector3(33.4 + (ri2 % 3) * 1.1, 0, 27.6 + (ri2 / 3) * 1.1)
		kins.append(kd)

# ------------------------------------------------------------------ loop
## Sun, sky, lamps and the occasional rain shower.
var _music_t := 0.0
var music_hold := 0.0
## The music follows where you're standing: each island has its own theme, home changes at night.
func _update_music(d: float) -> void:
	_music_t -= d
	music_hold -= d
	if _music_t > 0.0 or music_hold > 0.0:
		return
	_music_t = 0.5
	var isle := world.island_id(ppos.x, ppos.z)
	var night := sin((day_t - 0.25) * TAU) < -0.15
	var want := "home_night" if night else "home_day"
	if isle in ["orchard", "meadow", "summit"]:
		want = isle
	if Sfx.music_lock != "":
		want = Sfx.music_lock
	Sfx.play_music(want, 2.5)

func _on_new_track(name: String) -> void:
	if not is_inside_tree() or root_ui == null:
		return
	_toast("New track: %s" % Data.MUSIC.get(name, {}).get("name", name))

func _update_sky(d: float) -> void:
	_update_music(d)
	day_t = fmod(day_t + d / DAY_LEN, 1.0)
	var sun_h := sin((day_t - 0.25) * TAU)            # 1 at noon, -1 at midnight
	var light := clampf(sun_h * 1.6 + 0.35, 0.0, 1.0)  # how much daylight
	var dusk := clampf(1.0 - absf(sun_h) * 3.0, 0.0, 1.0)
	weather_t -= d
	if weather_t <= 0.0:
		raining = not raining and randf() < 0.45
		weather_t = randf_range(50.0, 110.0) if raining else randf_range(70.0, 160.0)
		rain.emitting = raining
		Sfx.play_ambience("rain" if raining else "home")
	rain_k = move_toward(rain_k, 1.0 if raining else 0.0, d * 0.3)
	rain.position = Vector3(ppos.x, 12.0, ppos.z)
	var day_col := Color("ffe9cf").lerp(Color("ff9a6a"), dusk * 0.8)
	sun_l.light_color = day_col.lerp(Color("8fa6e0"), 1.0 - light)
	sun_l.light_energy = lerpf(0.1, 0.9, light) * (1.0 - rain_k * 0.35)
	sun_l.rotation_degrees = Vector3(lerpf(-28.0, -62.0, maxf(sun_h, 0.0)), -30.0 + day_t * 80.0, 0)
	env_res.ambient_light_color = Color("c4cbe6").lerp(Color("5a6aa8"), 1.0 - light).lerp(Color("ffc9a8"), dusk * 0.35)
	env_res.ambient_light_energy = lerpf(0.2, 0.45, light) * (1.0 - rain_k * 0.2)
	env_res.adjustment_enabled = true
	env_res.adjustment_brightness = lerpf(0.72, 1.0, light) * (1.0 - rain_k * 0.08)
	env_res.adjustment_saturation = lerpf(0.7, 1.0, light) * (1.0 - rain_k * 0.15)
	env_res.background_color = Color("1a2236").lerp(Color("0b0e1a"), 1.0 - light)
	var lamp_on := clampf(1.2 - light * 1.6, 0.0, 1.0)
	for l in lamps:
		l.light_energy = 0.25 + lamp_on * 2.2
		l.omni_range = 4.0 + lamp_on * 3.5

func _process(delta: float) -> void:
	var d := minf(delta, 0.05)
	farm_t -= delta
	if farm_t <= 0.0:
		farm_t = 1.0
		_farm_tick()
	_update_sky(d)
	_move_player(d)
	_move_kin(d)
	cam.follow(ppos, d, panel_open == "")
	_find_interact()
	if panel_open == "" and not building_now and not Overlay.is_open() and Input.is_action_just_pressed("interact") and not interact.is_empty():
		_use(interact)

func _move_player(d: float) -> void:
	var mv := Vector2.ZERO
	if panel_open == "" and not Overlay.is_open():
		mv = Vector2(Input.get_axis("left", "right"), Input.get_axis("up", "down"))
		if mv.length() > 1.0: mv = mv.normalized()
	var hv := Vector2(pvel.x, pvel.z)
	var air := py > 0.001 or pvy > 0.0
	hv += (mv * SPEED - hv) * (1.0 - exp(-(14.0 if not air else 6.0) * d))
	# the island edge is an invisible wall: walking and jumping both stop at it
	var nx := ppos.x + hv.x * d
	if world.occupy(nx, ppos.z, 0.38, 0.0, true) == 0.0: ppos.x = nx
	else: hv.x = 0.0
	var nz := ppos.z + hv.y * d
	if world.occupy(ppos.x, nz, 0.38, 0.0, true) == 0.0: ppos.z = nz
	else: hv.y = 0.0
	pvel = Vector3(hv.x, 0, hv.y)
	# jumping, just for fun
	if panel_open == "" and not Overlay.is_open() and not air and Input.is_action_just_pressed("jump"):
		pvy = JUMP_V
		Sfx.play("jump", null, -12.0)
	if air or pvy > 0.0:
		pvy -= GRAV * d
		py += pvy * d
		if py <= 0.0:
			py = 0.0
			pvy = 0.0
			Sfx.step(null, -16.0)
	player.position = ppos + Vector3(0, py, 0)
	# face the mouse; with the mouse outside the window, face where you're walking
	var vp := get_viewport()
	var mp := vp.get_mouse_position()
	var aim_ok := panel_open == "" and Rect2(Vector2.ZERO, vp.get_visible_rect().size).has_point(mp)
	var want := pface
	if aim_ok:
		var aim := cam.mouse_on_plane(0.9)
		var ad := Vector2(aim.x - ppos.x, aim.z - ppos.z)
		if ad.length() > 0.4: want = atan2(-ad.x, -ad.y)
	elif hv.length() > 0.3:
		want = atan2(-hv.x, -hv.y)
	pface = lerp_angle(pface, want, minf(1.0, d * 14.0))
	player.rotation.y = pface
	var ph0 := walk_ph
	walk_ph += d * hv.length() * 2.2 * (0.0 if py > 0.0 else 1.0)
	if hv.length() > 1.0 and int(walk_ph / PI) != int(ph0 / PI):
		Sfx.step(null, -20.0)
	var legs: Node3D = player.get_node("Rig/Legs")
	var sw := sin(walk_ph) * clampf(hv.length() / 4.0, 0.0, 1.0) * 0.6
	if py > 0.0: sw = 0.0
	legs.get_node("LegL").rotation.x = sw if py <= 0.0 else -0.5
	legs.get_node("LegR").rotation.x = -sw if py <= 0.0 else 0.3
	player.get_node("Rig/Torso").position.y = 0.42 + absf(sin(walk_ph)) * 0.04 * clampf(hv.length() / 4.0, 0.0, 1.0)

func _move_kin(d: float) -> void:
	for k in kins:
		if k.get("busy", false):
			continue
		k["t"] -= d
		var pos: Vector3 = k["pos"]
		var rec: Dictionary = k["rec"]
		var trust := float(rec["trust"])
		var here := world.island_of(pos.x, pos.z)
		# playing tag: chase a friend, then it's their turn
		var other = k.get("chase", null)
		if other != null:
			k["chase_t"] = float(k.get("chase_t", 0.0)) - d
			k["goal"] = other["pos"]
			if Vector2(other["pos"].x - pos.x, other["pos"].z - pos.z).length() < 0.7 or k["chase_t"] <= 0.0:
				k.erase("chase")
				k["t"] = randf_range(1.5, 3.0)
				if k["chase_t"] > 0.0:
					_emote(k, "♪"); _emote(other, "!")
					Sfx.play("kin_happy", other["pos"], -14.0, 0.15, 1.2)
					if not other.get("busy", false) and randf() < 0.7:
						other["chase"] = k; other["chase_t"] = 4.0
				k["goal"] = world.random_ground(maxi(here, 0))
		if k.has("task"):
			var tk: Array = k["task"]
			var tpos: Vector3 = _plot_node(tk[0], tk[1]).position
			k["goal"] = tpos + Vector3(0, 0, 1.0)
			k["task_t"] = float(k.get("task_t", 15.0)) - d
			if k["task_t"] <= 0.0:
				k.erase("task")      # couldn't get there; try again later
			elif Vector2(tpos.x - pos.x, tpos.z + 1.0 - pos.z).length() < 0.6:
				k.erase("task")
				var pd: Dictionary = Save.d[tk[0]][tk[1]]
				if pd["crop"] != "" and float(pd.get("wt", 0.0)) <= 0.0:
					_water(tk[0], tk[1])
					_emote(k, "♪")
					rec["trust"] = minf(100.0, float(rec["trust"]) + 0.2)
				k["t"] = randf_range(1.0, 2.0)
		elif k["t"] <= 0.0 and rec.get("farmhand", false) and visit.is_empty() and (k["farm_t"] if k.has("farm_t") else 0.0) <= 0.0 and _dry_plot() != []:
			k["task"] = _dry_plot()
			k["task_t"] = 15.0
			k["farm_t"] = 6.0
		if k.has("farm_t"): k["farm_t"] = float(k["farm_t"]) - d
		if k["t"] <= 0.0 and not k.has("chase") and not k.has("task"):
			k["t"] = randf_range(2.0, 5.0)
			var night := sin((day_t - 0.25) * TAU) < -0.2
			var friends: Array = kins.filter(func(o): return o != k and not o.get("busy", false) and world.island_of(o["pos"].x, o["pos"].z) == here)
			if night and randf() < 0.6:
				# at night they head for bed and doze
				k["goal"] = k.get("bed", world.random_ground(maxi(here, 0)))
				if randf() < 0.5: _emote(k, "z")
			elif friends.size() > 0 and randf() < 0.22:
				var f: Dictionary = friends[randi() % friends.size()]
				k["chase"] = f; k["chase_t"] = 4.0
				_emote(k, "★")
			elif randf() < 0.25 + trust / 300.0 and world.island_of(ppos.x, ppos.z) == here:
				# kin that trust you like to be near you
				k["goal"] = ppos + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))
			else:
				k["goal"] = world.random_ground(maxi(here, 0))
			if randf() < 0.3:
				_emote(k, "♥" if trust > 65.0 else ("?" if trust < 30.0 else "★"))
		var wish := Vector2.ZERO
		var goal: Vector3 = k["goal"]
		if goal != Vector3.INF:
			var to := Vector2(goal.x - pos.x, goal.z - pos.z)
			if to.length() > 0.4:
				wish = to.normalized() * (3.6 if k.has("chase") else 2.4)
		var hv := Vector2(k["vel"].x, k["vel"].z)
		hv += (wish - hv) * (1.0 - exp(-8.0 * d))
		var nx := pos.x + hv.x * d
		if world.occupy(nx, pos.z, 0.3, 0.0, true) == 0.0: pos.x = nx
		var nz := pos.z + hv.y * d
		if world.occupy(pos.x, nz, 0.3, 0.0, true) == 0.0: pos.z = nz
		k["vel"] = Vector3(hv.x, 0, hv.y)
		k["pos"] = pos
		var n: Node3D = k["node"]
		n.position = pos
		var face := atan2(-hv.x, -hv.y) if hv.length() > 0.2 else atan2(-(ppos.x - pos.x), -(ppos.z - pos.z))
		n.rotation.y = lerp_angle(n.rotation.y, face, minf(1.0, d * 8.0))
		k["hop"] += d * (9.0 if hv.length() > 0.3 else 2.5)
		n.get_node("Body").position.y = absf(sin(k["hop"])) * (0.14 if hv.length() > 0.3 else 0.03)
		n.scale = Vector3.ONE * (1.05 if rec["uid"] == _d().get("active", "") else 0.9) * float(n.get_meta("evo_scale", 1.0))
		if k["emote_t"] > 0.0:
			k["emote_t"] -= d
			var lbl: Label3D = k["emote"]
			lbl.visible = k["emote_t"] > 0.0
			lbl.position.y = 1.15 + (1.6 - k["emote_t"]) * 0.2

func _emote(k: Dictionary, s: String) -> void:
	var lbl: Label3D = k["emote"]
	lbl.text = s
	lbl.modulate = Color("ff8fb0") if s == "♥" else UI.INK
	k["emote_t"] = 1.6

func _find_interact() -> void:
	var best := {}; var bd := 1.9
	var p2 := Vector2(ppos.x, ppos.z)
	for i in plots.size():
		var d := p2.distance_to(Vector2(plots[i].position.x, plots[i].position.z))
		if d < bd: bd = d; best = {"kind": "plot", "arr": "plots", "i": i}
	for i in gh_plots.size():
		var d := p2.distance_to(Vector2(gh_plots[i].position.x, gh_plots[i].position.z))
		if d < bd: bd = d; best = {"kind": "plot", "arr": "gh_plots", "i": i}
	for nm in ["pot", "stall", "portal", "house", "ferry"]:
		var sp: Vector3 = spots[nm]
		var reach := 2.6 if nm in ["house", "portal"] else 1.9
		var d := p2.distance_to(Vector2(sp.x, sp.z + (2.0 if nm == "house" else 0.0)))
		if d < reach and d < bd + 0.6: bd = d; best = {"kind": nm}
	for b in lots:
		var l: Dictionary = lots[b]
		var dp: Vector3 = l["door"] if l["built"] else l["at"]
		var d := p2.distance_to(Vector2(dp.x, dp.z))
		if d < (1.8 if l["built"] else 2.4) and d < bd + 0.4: bd = d; best = {"kind": "lot", "b": b}
	for k in bridges:
		if bridges[k]["built"]:
			continue
		var sg: Vector2 = Data.ISLES[k]["sign"]
		var d := p2.distance_to(sg)
		if d < 2.4 and d < bd + 0.4: bd = d; best = {"kind": "bridge", "isle": k}
	for k in kins:
		var d := p2.distance_to(Vector2(k["pos"].x, k["pos"].z))
		if d < bd: bd = d; best = {"kind": "kin", "k": k}
	interact = best
	if panel_open != "" or best.is_empty() or building_now:
		prompt_box.visible = false
		return
	prompt_box.visible = true
	prompt_lbl.text = "F  " + _label_for(best)
	prompt_box.reset_size()
	var vp := get_viewport().get_visible_rect().size
	prompt_box.position = Vector2((vp.x - prompt_box.size.x) * 0.5, vp.y - 110.0)

func _label_for(it: Dictionary) -> String:
	if not visit.is_empty():
		match it["kind"]:
			"kin": return ("Pet %s" % it["k"]["rec"]["name"]) if not petted.has(it["k"]["rec"]["uid"]) else "%s is happy you came" % it["k"]["rec"]["name"]
			"house": return "Leave a gift"
			"portal", "ferry": return "Go home"
			"plot": return "%s's crops" % visit.get("name", "Their")
		return "Look around"
	match it["kind"]:
		"ferry": return "Take the ferry"
		"plot":
			var d: Dictionary = Save.d[it["arr"]][it["i"]]
			if d["crop"] == "": return "Plant something"
			var cd: Dictionary = Data.CROPS[d["crop"]]
			if int(d["stage"]) >= int(cd["grow"]): return "Harvest the %s" % cd["name"]
			if float(d.get("wt", 0.0)) <= 0.0: return "Water the %s" % cd["name"]
			return "%s: watered, growing (%s)" % [cd["name"], _grow_left(it["arr"], d)]
		"pot": return "Cook"
		"stall": return "Shop"
		"portal": return "Start an expedition"
		"house": return "Go inside"
		"lot":
			var bd: Dictionary = Data.BUILDINGS[it["b"]]
			if lots[it["b"]]["built"]: return _building_verb(it["b"])
			return "Build a %s" % bd["name"]
		"bridge": return "Build a bridge to %s" % Data.ISLES[it["isle"]]["name"]
		"kin":
			var rec: Dictionary = it["k"]["rec"]
			return "Spend time with %s" % rec["name"]
	return ""

func _use(it: Dictionary) -> void:
	Sfx.play("click")
	if not visit.is_empty():
		_use_visiting(it)
		return
	match it["kind"]:
		"ferry": _open_ferry()
		"plot": _open_plot(it["arr"], it["i"])
		"lot": _open_lot(it["b"])
		"bridge": _open_bridge(it["isle"])
		"pot": _open_kitchen()
		"stall": _open_shop()
		"portal": _open_expedition()
		"house": _open_house()
		"kin": _open_kin(it["k"]["rec"])

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and panel_open == "":
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: cam.zoom_to = clampf(cam.zoom_to - 0.08, 0.55, 1.6)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: cam.zoom_to = clampf(cam.zoom_to + 0.08, 0.55, 1.6)
	if event.is_action_pressed("menu") and not Overlay.is_open():
		if panel_open != "":
			_close_panel()
		else:
			Overlay.open_pause("home")

# ------------------------------------------------------------------ ui
func _build_ui() -> void:
	ui = CanvasLayer.new(); add_child(ui)
	root_ui = Control.new(); root_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root_ui.theme = UI.theme()
	root_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root_ui)
	var top := UI.card(Color(0.06, 0.07, 0.1, 0.78), 12, 12)
	top.position = Vector2(16, 14)
	var th := UI.hbox(14); top.add_child(th)
	th.add_child(UI.title("Kinfall", 26, UI.ACCENT))
	topbar = UI.label("", 15, UI.INK)
	topbar.autowrap_mode = TextServer.AUTOWRAP_OFF
	topbar.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	th.add_child(topbar)
	root_ui.add_child(top)
	prompt_box = UI.card(Color(0.06, 0.07, 0.1, 0.85), 12, 12)
	prompt_lbl = UI.label("", 18, UI.GOLD, UI.big)
	prompt_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	prompt_box.add_child(prompt_lbl)
	root_ui.add_child(prompt_box)
	var hint_box := UI.card(Color(0.06, 0.07, 0.1, 0.7), 8, 10)
	hint = UI.label("WASD walk   ·   Space jump   ·   F use what's in front of you   ·   Scroll to zoom   ·   Esc menu", 14, UI.INK)
	hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	hint_box.add_child(hint)
	hint_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint_box.position.y = -16
	root_ui.add_child(hint_box)
	panel_host = CenterContainer.new()
	panel_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_ui.add_child(panel_host)

func _refresh_top() -> void:
	if not visit.is_empty():
		topbar.text = "Visiting %s's island   ·   Pet their kin, leave a gift at the house   ·   The portal takes you home" % String(visit.get("name", "a friend")).substr(0, 16)
		return
	var crops := 0
	for k in Save.d["crops"]: crops += int(Save.d["crops"][k])
	var ak := Save.active_kin()
	var treat: String = Save.d.get("treat", "")
	topbar.text = "%d gems   ·   %d tonics   ·   %d crops   ·   Partner: %s%s" % [int(Save.d["gems"]), int(Save.d["items"].get("tonic", 0)), crops,
		ak.get("name", "none"), ("   ·   Treat ready: " + _treat_name(treat)) if treat != "" else ""]

func _treat_name(t: String) -> String:
	for k in Data.CROPS:
		if Data.CROPS[k]["use"] == t: return Data.CROPS[k]["name"]
	return t

func _new_panel(title_txt: String, width := 520.0) -> VBoxContainer:
	var prev := panel_open
	_close_panel()
	var pb := UI.scroll_panel(title_txt, width, _close_panel)
	var p: PanelContainer = pb[0]
	var v: VBoxContainer = pb[1]
	panel_host.add_child(p)
	panel_open = title_txt
	if prev != title_txt:
		UI.pop_in(p)
		Sfx.play("whoosh", null, -10.0)
	return v

func _close_panel() -> void:
	var was := panel_open
	for ch in panel_host.get_children():
		ch.queue_free()
	panel_open = ""
	chat_input = null
	_refresh_top()
	if was.ends_with(" evolved") or was.ends_with(" is changing") or was == "Welcome to your island":
		_play_evolutions.call_deferred()

func _open_welcome() -> void:
	var v := _new_panel("Welcome to your island", 560)
	v.add_child(UI.label("Your kin live here with you. Each one has its own personality, remembers what you do together, and decides how far it trusts you.", 16))
	v.add_child(UI.label("Grow crops between expeditions, then step through the portal to hunt in the floating islands. Bring treasure, seeds and new kin home before the islands fall. If you go down, everything you carried is lost.", 16, UI.MUTED))
	v.add_child(UI.label("Walk up to anything and press F. Start by saying hi to %s." % Save.active_kin().get("name", "your kin"), 16, UI.GOLD))
	v.add_child(UI.button("Let's go", func():
		Save.d["tutorial"]["home"] = true
		Save.save_game()
		_close_panel(), 200))

# ---- farm
## How long until the next stage, for a watered plant.
func _grow_left(arr: String, d: Dictionary) -> String:
	var need := Data.WATER_TIME * (0.5 if arr == "gh_plots" else 1.0)
	var left := int(ceil(need - (Time.get_unix_time_from_system() - float(d.get("wt", 0.0)))))
	return "%ds" % maxi(1, left)

## Watered plants grow while you're home; rain and a farmhand kin water for you.
func _farm_tick() -> void:
	if not visit.is_empty():
		return
	var now := Time.get_unix_time_from_system()
	for arr in ["plots", "gh_plots"]:
		var nodes: Array = plots if arr == "plots" else gh_plots
		for i in mini(nodes.size(), Save.d[arr].size()):
			var d: Dictionary = Save.d[arr][i]
			if d["crop"] == "":
				continue
			var cd: Dictionary = Data.CROPS[d["crop"]]
			if int(d["stage"]) >= int(cd["grow"]):
				continue
			var wt := float(d.get("wt", 0.0))
			if wt <= 0.0 and raining:
				_water(arr, i, false)
				continue
			if wt > 0.0 and now - wt >= Data.WATER_TIME * (0.5 if arr == "gh_plots" else 1.0):
				d["stage"] = int(d["stage"]) + 1
				d["care"] = int(d.get("care", 0)) + 1
				d["wt"] = 0.0
				var pn: Node3D = nodes[i]
				fx.burst(pn.position + Vector3(0, 0.5, 0), Color("8fd16a"), 8, 1.6)
				_refresh_plot(arr, i)
				if int(d["stage"]) >= int(cd["grow"]):
					_toast("%s is ready to harvest" % cd["name"])
				Save.save_game()

## The first planted, unwatered plant the farmhand can reach.
func _dry_plot() -> Array:
	for arr in ["plots", "gh_plots"]:
		var nodes: Array = plots if arr == "plots" else gh_plots
		for i in mini(nodes.size(), Save.d[arr].size()):
			var d: Dictionary = Save.d[arr][i]
			if d["crop"] != "" and float(d.get("wt", 0.0)) <= 0.0 and int(d["stage"]) < int(Data.CROPS[d["crop"]]["grow"]):
				if arr == "plots" or _isle_open("orchard"):
					return [arr, i]
	return []

func _water(arr: String, i: int, by_hand := true) -> void:
	var d: Dictionary = Save.d[arr][i]
	d["wt"] = Time.get_unix_time_from_system()
	var pn: Node3D = _plot_node(arr, i)
	if by_hand:
		Sfx.play("plant", null, -6.0, 0.1, 1.4)
		fx.burst(pn.position + Vector3(0, 0.8, 0), Color("7ac8ff"), 14, 2.0)
	_refresh_plot(arr, i)
	Save.save_game()

func _open_plot(arr: String, i: int) -> void:
	var d: Dictionary = Save.d[arr][i]
	var pn: Node3D = _plot_node(arr, i)
	if d["crop"] != "":
		var cd: Dictionary = Data.CROPS[d["crop"]]
		var grow := int(cd["grow"])
		if int(d["stage"]) >= grow:
			# a tended plant gives more, and a fully tended one gives a seed back
			var care := int(d.get("care", 0))
			var n := 2 + (1 if care * 2 >= grow else 0)
			Save.d["crops"][d["crop"]] = int(Save.d["crops"].get(d["crop"], 0)) + n
			var extra := ""
			# a fully tended common crop sometimes drops a seed (rare ones never do)
			if care >= grow and float(cd.get("weight", 1.0)) >= 1.0 and randf() < 0.5:
				Save.add_seed(d["crop"], 1)
				extra = " and a seed"
			fx.burst(pn.position + Vector3(0, 0.6, 0), cd["color"], 18 + n * 4, 3.0)
			Sfx.play("harvest")
			_toast("%d %s%s%s" % [n, cd["name"], "" if n == 1 else "s", extra])
			d["crop"] = ""; d["stage"] = 0; d["care"] = 0; d["wt"] = 0.0
			_refresh_plot(arr, i)
			Save.save_game()
			_refresh_top()
			return
		if float(d.get("wt", 0.0)) <= 0.0:
			_water(arr, i)
			return
		var v := _new_panel(cd["name"], 440)
		v.add_child(UI.label("Watered. It grows a stage in %s while you're home, or after your next expedition." % _grow_left(arr, d), 16))
		v.add_child(UI.label("Stage %d of %d. Tended %d time%s: %s" % [int(d["stage"]), grow, int(d.get("care", 0)), "" if int(d.get("care", 0)) == 1 else "s",
			"water it every stage for a bigger harvest, and maybe a seed back." if int(d.get("care", 0)) < grow else "it'll be a big harvest."], 14, UI.MUTED))
		v.add_child(UI.label(cd["desc"], 14, UI.MUTED))
		return
	var v := _new_panel("Plant a seed", 480)
	var any := false
	for s in Data.CROPS:
		var n := int(Save.d["seeds"].get(s, 0))
		if n <= 0: continue
		any = true
		var row := UI.hbox(10)
		var info := UI.vbox(2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UI.label("%s  ×%d" % [Data.CROPS[s]["name"], n], 17, Data.CROPS[s]["color"]))
		info.add_child(UI.label("%d stages. %s" % [Data.CROPS[s]["grow"], Data.CROPS[s]["desc"]], 13, UI.MUTED))
		row.add_child(info)
		var sk: String = s
		row.add_child(UI.button("Plant", func():
			Save.d["seeds"][sk] = int(Save.d["seeds"][sk]) - 1
			d["crop"] = sk; d["stage"] = 0; d["care"] = 0; d["wt"] = 0.0
			Sfx.play("plant")
			fx.dust(pn.position, 10)
			_refresh_plot(arr, i)
			Save.save_game()
			_close_panel()))
		v.add_child(row)
	if not any:
		v.add_child(UI.label("You have no seeds. Find them in chests and from monsters on expeditions, or buy some at the stall.", 16, UI.MUTED))
	v.add_child(UI.label("Water a plant (F) and it grows a stage every %d seconds while you're home. Expeditions grow everything a stage too. Rain waters for you." % int(Data.WATER_TIME), 13, UI.MUTED))

func _open_kitchen() -> void:
	var v := _new_panel("Cooking pot", 520)
	v.add_child(UI.label("Crops become tonics for the match, or a treat your partner eats before the next expedition.", 15, UI.MUTED))
	var any := false
	for s in Data.CROPS:
		var n := int(Save.d["crops"].get(s, 0))
		if n <= 0: continue
		any = true
		var cd: Dictionary = Data.CROPS[s]
		var row := UI.hbox(10)
		var info := UI.vbox(2); info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UI.label("%s  ×%d" % [cd["name"], n], 17, cd["color"]))
		info.add_child(UI.label(cd["desc"], 13, UI.MUTED))
		row.add_child(info)
		var sk: String = s
		var label_txt: String = {"tonic": "Brew 2 tonics", "snack": "Feed a snack", "levelup": "Feed it"}.get(cd["use"], "Make the treat")
		row.add_child(UI.button(label_txt, func():
			var ak := Save.active_kin()
			if (cd["use"] == "snack" or cd["use"] == "levelup") and ak.is_empty():
				_toast("You need a partner kin for that")
				return
			Save.d["crops"][sk] = int(Save.d["crops"][sk]) - 1
			match String(cd["use"]):
				"tonic": Save.add_item("tonic", 2)
				"snack":
					Save.remember(ak, "fed", "got a %s snack from you" % cd["name"], 4.0)
					_toast("%s loved the snack" % ak["name"])
				"levelup":
					var today := int(Time.get_unix_time_from_system() / 86400.0)
					if int(ak.get("starfruit_day", -1)) == today:
						Save.d["crops"][sk] = int(Save.d["crops"][sk]) + 1
						_toast("%s is still full from the last one. Try again tomorrow" % ak["name"])
						return
					ak["starfruit_day"] = today
					ak["level"] = int(ak["level"]) + 1
					var out := {}
					Game._evolve(ak, out)
					Save.remember(ak, "fed", "ate a Starfruit and grew stronger", 2.0)
					_toast("%s is now level %d" % [ak["name"], int(ak["level"])])
					_play_evolutions()
				_: Save.d["treat"] = cd["use"]
			Sfx.play("heal")
			fx.burst(spots["pot"] + Vector3(0, 1.0, 0), cd["color"], 20, 3.0)
			Save.save_game()
			_open_kitchen()))
		v.add_child(row)
	if not any:
		v.add_child(UI.label("Nothing to cook yet. Harvest crops from your plots first.", 16))
	if Save.d.get("treat", "") != "":
		v.add_child(UI.label("Ready for the next match: " + _treat_name(Save.d["treat"]), 15, UI.GOLD))

func _open_shop() -> void:
	var v := _new_panel("Market stall", 520)
	v.add_child(UI.label("You have %d gems." % int(Save.d["gems"]), 16, UI.GOLD))
	for s in Data.CROPS:
		var cd: Dictionary = Data.CROPS[s]
		var sk: String = s
		_shop_row(v, "%s seed" % cd["name"], cd["desc"], int(cd["price"]), func(): Save.add_seed(sk, 1))
	_shop_row(v, "Tonic", "Heals 45 in a match (key 1).", 30, func(): Save.add_item("tonic", 1))
	var sell_any := false
	for s in Data.CROPS:
		var n := int(Save.d["crops"].get(s, 0))
		if n <= 0: continue
		if not sell_any:
			v.add_child(UI.section("Sell your harvest"))
			sell_any = true
		var sk: String = s
		var gain := maxi(1, int(round(int(Data.CROPS[s]["price"]) * 0.4)))
		var row := UI.hbox(10)
		var l := UI.label("%s  ×%d" % [Data.CROPS[s]["name"], n], 16, Data.CROPS[s]["color"]); l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(UI.button("Sell 1 for %d" % gain, func():
			if int(Save.d["crops"].get(sk, 0)) <= 0: return
			Save.d["crops"][sk] = int(Save.d["crops"][sk]) - 1
			Save.d["gems"] = int(Save.d["gems"]) + gain
			Sfx.play("pickup")
			Save.save_game()
			_refresh_top()
			_open_shop(), 140))
		v.add_child(row)
	if int(Save.d["plot_cap"]) < 8:
		_shop_row(v, "Two more plots", "Grow more at once.", 120 + 80 * (int(Save.d["plot_cap"]) - 4), func():
			Save.d["plot_cap"] = int(Save.d["plot_cap"]) + 2
			_build_plots())

func _shop_row(v: VBoxContainer, name_txt: String, desc: String, price: int, on_buy: Callable) -> void:
	var row := UI.hbox(10)
	var info := UI.vbox(2); info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(UI.label(name_txt, 16))
	info.add_child(UI.label(desc, 13, UI.MUTED))
	row.add_child(info)
	var b := UI.button("%d gems" % price, func():
		if int(Save.d["gems"]) < price: return
		Save.d["gems"] = int(Save.d["gems"]) - price
		on_buy.call()
		Sfx.play("pickup")
		Save.save_game()
		_open_shop())
	b.disabled = int(Save.d["gems"]) < price
	row.add_child(b)
	v.add_child(row)

# ---- kin
func _open_kin(rec: Dictionary) -> void:
	var sp: Dictionary = Data.KIN[rec["species"]]
	Evo.ensure(rec)
	var v := _new_panel("%s the %s" % [rec["name"], Evo.form_name(rec)], 640)
	var row := UI.hbox(20)
	var left := UI.vbox(6); left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(UI.label("Level %d %s kin · trust %d" % [int(rec["level"]), String(sp["type"]).capitalize(), int(rec["trust"])], 15, sp["color"]))
	for t in ["bravery", "loyalty", "temper", "curiosity"]:
		var r := UI.hbox(8)
		var l := UI.label(t.capitalize(), 14, UI.MUTED); l.custom_minimum_size.x = 80
		r.add_child(l)
		r.add_child(UI.bar(float(rec["traits"][t]), sp["color"], 160, 8))
		left.add_child(r)
	var tr := UI.hbox(8)
	var tl := UI.label("Trust", 14, Color("ffb3c6")); tl.custom_minimum_size.x = 80
	tr.add_child(tl); tr.add_child(UI.bar(float(rec["trust"]) / 100.0, Color("ffb3c6"), 160, 8))
	left.add_child(tr)
	row.add_child(left)
	var right := UI.vbox(6); right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sk: Dictionary = Data.KIN_SKILLS[sp["skill"]]
	var sh: Dictionary = Data.SHOULDER[sp["shoulder"]]
	right.add_child(UI.label("Q skill: %s" % sk["name"], 15, UI.INK))
	right.add_child(UI.label(sk["desc"], 13, UI.MUTED))
	right.add_child(UI.label("On your shoulder: %s" % sh["name"], 15, UI.INK))
	right.add_child(UI.label(sh["desc"], 13, UI.MUTED))
	row.add_child(right)
	v.add_child(row)
	# how it's growing
	var grow := UI.vbox(4)
	var lead := Evo.leading(rec)
	var lv := int(rec["level"])
	var next_form := (lv / 4 + 1) * 4
	var next_mut := lv + ((2 - lv % 4) + 4) % 4
	if next_mut == lv: next_mut += 4
	grow.add_child(UI.label("Growing %s. Next new form at level %d, next mutation at level %d." % [String(Evo.AFF[lead]["name"]).to_lower(), next_form, next_mut], 14, Evo.AFF[lead]["tint"]))
	var ar := UI.hbox(10)
	var tot := 0.0
	for a in Evo.AFF: tot += maxf(0.0, float(rec["aff"][a]))
	for a in Evo.AFF:
		var cbox := UI.vbox(2)
		var al := UI.label(Evo.AFF[a]["name"], 12, UI.MUTED); al.autowrap_mode = TextServer.AUTOWRAP_OFF
		cbox.add_child(al)
		cbox.add_child(UI.bar(float(rec["aff"][a]) / maxf(tot, 1.0), Evo.AFF[a]["tint"], 120, 6))
		ar.add_child(cbox)
	grow.add_child(ar)
	var parts: Array = []
	for mu in rec["muts"]:
		parts.append(String(Evo.PART_NAMES.get(mu["id"], mu["id"])) + ("" if int(mu["lv"]) == 1 else " (x%d)" % int(mu["lv"])))
	if rec["forms"].size() > 0 or parts.size() > 0:
		var path: Array = []
		for f in rec["forms"]: path.append(Evo.AFF[f]["name"])
		grow.add_child(UI.label(("Path: " + " > ".join(path) if path.size() > 0 else "") + ("   Has: " + ", ".join(parts) if parts.size() > 0 else ""), 13, UI.MUTED))
	grow.add_child(UI.label("Food shapes it too: Emberberry fierce, Sunroot steadfast, Mindmint curious, Tidebloom swift.", 12, UI.MUTED))
	v.add_child(grow)
	var mem: Array = rec.get("memory", [])
	if mem.size() > 0:
		v.add_child(UI.section("Remembers"))
		for i in range(maxi(0, mem.size() - 4), mem.size()):
			v.add_child(UI.label("· " + String(mem[i]["text"]), 14, UI.INK))
	var btns := UI.hbox(8)
	btns.add_child(UI.button("Talk", func(): _open_chat(rec)))
	var pet_b := UI.button("Pet", func():
		pet_done[rec["uid"]] = int(Save.d["matches"])
		Save.remember(rec, "petted", "got a long scratch behind the ears", 1.5)
		Sfx.play("kin_happy")
		for k in kins:
			if k["rec"] == rec: _emote(k, "♥")
		Save.save_game()
		_open_kin(rec))
	pet_b.disabled = pet_done.get(rec["uid"], -1) == int(Save.d["matches"])
	btns.add_child(pet_b)
	for s in Data.CROPS:
		if int(Save.d["crops"].get(s, 0)) > 0:
			var crop_k: String = s
			btns.add_child(UI.button("Feed %s" % Data.CROPS[s]["name"], func():
				Save.d["crops"][crop_k] = int(Save.d["crops"][crop_k]) - 1
				for af in Evo.AFF:
					if Evo.AFF[af]["food"] == crop_k: Evo.add(rec, af, 6.0)
				Save.remember(rec, "fed", "was fed a %s" % Data.CROPS[crop_k]["name"].to_lower(), 4.0)
				Sfx.play("kin_happy")
				Save.save_game()
				_open_kin(rec)))
			break
	if rec["uid"] != Save.d.get("active", ""):
		btns.add_child(UI.button("Bring on expeditions", func():
			Save.d["active"] = rec["uid"]
			Save.save_game()
			_open_kin(rec)))
	else:
		btns.add_child(UI.label("  Your partner", 15, UI.GOLD))
	# one kin can look after the farm: it waters dry plants while you're home
	if rec.get("farmhand", false):
		btns.add_child(UI.button("Stop farming", func():
			rec.erase("farmhand")
			Save.save_game()
			_open_kin(rec)))
	else:
		btns.add_child(UI.button("Make farmhand", func():
			for r2 in Save.d["roster"]: r2.erase("farmhand")
			rec["farmhand"] = true
			Save.remember(rec, "farm", "was put in charge of watering the farm", 1.0)
			Save.save_game()
			_toast("%s will water your plants" % rec["name"])
			_open_kin(rec)))
	v.add_child(btns)

func _open_chat(rec: Dictionary) -> void:
	var v := _new_panel("Talking with %s" % rec["name"], 600)
	chat_kin = rec
	if chat_log.size() == 0 or chat_log[0].get("uid", "") != rec["uid"]:
		chat_log = [{"uid": rec["uid"]}]
	chat_scroll = ScrollContainer.new()
	chat_scroll.custom_minimum_size = Vector2(0, 280)
	chat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	chat_box = UI.vbox(8)
	chat_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_scroll.add_child(chat_box)
	v.add_child(chat_scroll)
	for msg in chat_log.slice(1):
		_chat_bubble(msg["role"], msg["content"])
	if chat_log.size() == 1:
		_chat_bubble("assistant", _greeting(rec))
	var row := UI.hbox(8)
	chat_input = LineEdit.new()
	chat_input.placeholder_text = "Say something to %s" % rec["name"]
	chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_input.text_submitted.connect(func(_t): _send_chat())
	row.add_child(chat_input)
	row.add_child(UI.button("Send", _send_chat))
	v.add_child(row)
	chat_input.grab_focus()

func _greeting(rec: Dictionary) -> String:
	var t := float(rec["trust"])
	if t > 70.0: return "Hi! I was hoping you'd come say hi."
	if t < 30.0: return "...oh. It's you."
	return "Hey. What's up?"

func _chat_bubble(role: String, text: String) -> void:
	var mine := role == "user"
	var c := UI.card(Color(0.95, 0.92, 0.85) if not mine else Color(0.2, 0.24, 0.34), 10, 12)
	var l := UI.label(text, 15, Color(0.1, 0.09, 0.12) if not mine else UI.INK)
	l.custom_minimum_size.x = 380
	c.add_child(l)
	var h := UI.hbox(0)
	if mine:
		var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(sp)
	h.add_child(c)
	chat_box.add_child(h)
	await get_tree().process_frame
	if is_instance_valid(chat_scroll):
		chat_scroll.scroll_vertical = int(chat_scroll.get_v_scroll_bar().max_value)

func _send_chat() -> void:
	if chat_input == null or chat_busy:
		return
	var txt := chat_input.text.strip_edges()
	if txt == "":
		return
	chat_input.text = ""
	chat_log.append({"role": "user", "content": txt})
	_chat_bubble("user", txt)
	var rec := chat_kin
	chat_busy = true
	var typing := UI.label("%s is typing" % rec["name"], 13, UI.MUTED)
	chat_box.add_child(typing)
	var dots := create_tween().set_loops()
	for i in 4:
		var n := i
		dots.tween_callback(func(): if is_instance_valid(typing): typing.text = "%s is typing%s" % [rec["name"], ".".repeat(n)])
		dots.tween_interval(0.35)
	var t0 := Time.get_ticks_msec() / 1000.0
	var msgs := []
	var brief := Bridge.kin_brief(rec) + "\n\nYou are chatting with your hunter at home on the farm. Stay in character and answer what they actually said, in one to three short sentences, plain text, no emoji, no stage directions. " + \
		"If they apologise or are kind, you can warm up a little. If they ask you to do something in a match, you can agree or set conditions based on your trust."
	var turns: Array = chat_log.slice(1)
	turns = turns.slice(maxi(0, turns.size() - 10))
	for i in turns.size():
		var tmsg: Dictionary = turns[i]
		var content: String = tmsg["content"]
		if i == 0 and tmsg["role"] == "user":
			content = brief + "\n\nYour hunter says: " + content
		msgs.append({"role": tmsg["role"], "content": content})
	if msgs.size() > 0 and msgs[0]["role"] != "user":
		msgs.push_front({"role": "user", "content": brief + "\n\n(The hunter walks up to you.)"})
	Bridge.ask(msgs, func(reply: String):
		var offline := reply.strip_edges() == ""
		if offline:
			reply = KinBrain.reply(rec, txt)
		# a kin takes a moment to answer: at least 2 seconds, longer for longer replies
		var want := clampf(2.0 + reply.length() * 0.03, 2.0, 6.0)
		var wait := want - (Time.get_ticks_msec() / 1000.0 - t0)
		if wait > 0.0:
			await get_tree().create_timer(wait).timeout
		if not is_inside_tree():
			return
		chat_busy = false
		if chat_kin.get("uid", "") != rec["uid"]:
			# you went off to talk to someone else; this one keeps its thought to itself
			dots.kill()
			return
		dots.kill()
		if is_instance_valid(typing): typing.queue_free()
		chat_log.append({"role": "assistant", "content": reply})
		if is_instance_valid(chat_box):
			_chat_bubble("assistant", reply)
			if offline and not chat_offline_noted:
				chat_offline_noted = true
				chat_box.add_child(UI.label(_offline_reason(), 12, UI.MUTED))
		# talking builds a little trust, once per match
		if int(rec.get("talked", -1)) != int(Save.d["matches"]):
			rec["talked"] = int(Save.d["matches"])
			Save.remember(rec, "talked", "had a chat with you at home", 2.0)
			Save.save_game()
			if Bridge.ai_ok and rec["uid"] == Save.d.get("active", "") and not rec.has("lines"):
				Bridge.refresh_lines(rec), "default")

func _offline_reason() -> String:
	match Bridge.last_err:
		"no_page": return "(%s is answering on their own here. In the web version they talk through Claude.)" % chat_kin.get("name", "Your kin")
		"not_granted": return "(Claude isn't allowed on this page yet, so %s is answering on their own. Allow it from the page's permissions to have real conversations.)" % chat_kin.get("name", "Your kin")
		"rate_limited": return "(Claude is busy for a moment, so %s answered on their own.)" % chat_kin.get("name", "Your kin")
	return "(Couldn't reach Claude, so %s answered on their own.)" % chat_kin.get("name", "Your kin")

# ---- expedition
var exp_cls := ""
var exp_mode := "solo"
var exp_tier := 0

func _hero() -> String:
	var h: String = Save.d.get("hero", "")
	if not Data.HEROES.has(h):
		h = {"light": "veil", "medium": "sage", "heavy": "bastion"}.get(Save.d.get("cls", "medium"), "sage")
	return h

func _weapon() -> String:
	var hd: Dictionary = Data.HEROES[_hero()]
	var w: String = Save.d.get("weapon", hd["weapon"])
	return w if Data.CLASSES[hd["cls"]]["weapons"].has(w) else hd["weapon"]

func _open_expedition() -> void:
	var v := _new_panel("Expedition", 720)
	var hero := _hero()
	var hd: Dictionary = Data.HEROES[hero]
	var w: String = Save.d.get("weapon", hd["weapon"])
	if not Data.CLASSES[hd["cls"]]["weapons"].has(w): w = hd["weapon"]
	var pk: String = Save.d.get("perk", "")
	var hc := UI.card(UI.CARD, 12, 14)
	var hrow := UI.hbox(12); hc.add_child(hrow)
	var hv := UI.vbox(4); hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_child(UI.title("%s  ·  %s" % [hd["name"], Data.CLASSES[hd["cls"]]["name"]], 24, hd["color"]))
	hv.add_child(UI.label("%s  ·  E %s  ·  R %s  ·  %s" % [Data.WEAPONS[w]["name"], Data.ABIL[hd["e"]]["name"], Data.ABIL[hd["r"]]["name"],
		Data.PERKS[pk]["name"] if Data.PERKS.has(pk) else "no perk"], 14, UI.MUTED))
	hrow.add_child(hv)
	hrow.add_child(UI.button("Hero and loadout", _open_loadout, 200))
	v.add_child(hc)
	var ak := Save.active_kin()
	if not ak.is_empty():
		var sp: Dictionary = Data.KIN[ak["species"]]
		var kl := "Partner: %s the %s, trust %d. RMB throws it into fights; Q fires its %s." % [ak["name"], sp["name"], int(ak["trust"]), Data.KIN_SKILLS[sp["skill"]]["name"]]
		v.add_child(UI.label(kl, 15, sp["color"]))
		if float(ak["trust"]) < 30.0:
			v.add_child(UI.label("%s doesn't trust you much yet and may refuse risky throws. Spend time with it, or feed it a Mindmint treat." % ak["name"], 13, UI.BAD))
	if Save.d.get("treat", "") != "":
		v.add_child(UI.label("Treat: " + _treat_name(Save.d["treat"]), 14, UI.GOLD))
	v.add_child(UI.section("Where"))
	var tiers := UI.hbox(8)
	var ex := int(Save.d.get("extracts", 0))
	for i in Data.TIERS.size():
		var td: Dictionary = Data.TIERS[i]
		var locked := ex < int(td["unlock"])
		var ti := i
		var label_t: String = td["name"]
		if locked:
			label_t = "%s (make it out %d more time%s)" % [td["name"], int(td["unlock"]) - ex, "" if int(td["unlock"]) - ex == 1 else "s"]
		var b := UI.choice(label_t, exp_tier == i and not locked, func(): exp_tier = ti; _open_expedition())
		b.disabled = locked
		tiers.add_child(b)
	v.add_child(tiers)
	var tsel: Dictionary = Data.TIERS[exp_tier]
	v.add_child(UI.label(tsel["desc"], 14, UI.BAD if tsel["risk_kin"] else UI.MUTED))
	if tsel["risk_kin"] and not ak.is_empty():
		var safe := float(ak["trust"]) >= 80.0
		v.add_child(UI.label(("%s trusts you enough to find its way home if you fall." if safe else "%s's trust is %d. Below 80, it won't come home if you fall here.") % ([ak["name"]] if safe else [ak["name"], int(ak["trust"])]), 14, UI.GOOD if safe else UI.BAD))
	v.add_child(UI.section("Match"))
	var modes := UI.hbox(8)
	for m in [["solo", "Solo · 4 squads"], ["duo", "Duos with a bot · 3 squads"], ["big", "Solo · 6 squads"]]:
		var mk: String = m[0]
		var b := UI.choice(m[1], exp_mode == mk, func(): exp_mode = mk; _open_expedition())
		modes.add_child(b)
	v.add_child(modes)
	var go := UI.hbox(10)
	go.add_child(UI.primary("Start expedition", _start_match, 220))
	go.add_child(UI.button("Training area", _start_training, 180))
	if Bridge.net_available():
		go.add_child(UI.button("Play online with friends", func(): Game.goto("lobby", {"cls": Data.HEROES[_hero()]["cls"], "tier": exp_tier}), 240))
	v.add_child(go)

## A safe island to learn every button: nothing can hurt you and nothing you do there counts.
func _start_training() -> void:
	Save.d["cls"] = Data.HEROES[_hero()]["cls"]
	Save.save_game()
	Game.start_match({"training": true, "teams": 1, "squad": 1, "tier": 0, "length": 1e9, "seed": 4242})

func _start_match() -> void:
	Save.d["cls"] = Data.HEROES[_hero()]["cls"]
	Save.save_game()
	var o := {"teams": 4, "squad": 1}
	match exp_mode:
		"duo": o = {"teams": 3, "squad": 2}
		"big": o = {"teams": 6, "squad": 1}
	o["tier"] = exp_tier
	Game.start_match(o)

# ---- evolution
## Kin that grew during the last expedition change in front of you when you get home.
func _play_evolutions() -> void:
	if building_now or panel_open != "":
		return
	var k: Dictionary = {}
	for kk in kins:
		if kk["rec"].get("pending_evo", []).size() > 0:
			k = kk; break
	if k.is_empty():
		return
	building_now = true
	var rec: Dictionary = k["rec"]
	var evs: Array = rec["pending_evo"]
	rec["pending_evo"] = []
	Save.save_game()
	var n: Node3D = k["node"]
	# bring it next to you
	var at := ppos + Vector3(1.6, 0, 0.6)
	if world.is_void(at.x, at.z) or world.is_block(at.x, at.z):
		at = ppos + Vector3(0, 0, 1.4)
	k["pos"] = at
	k["goal"] = Vector3.INF
	k["busy"] = true
	n.position = at
	cam.zoom_to = 0.55
	var big := false
	for e in evs:
		if e["kind"] == "form": big = true
	var tint: Color = Evo.AFF[evs[evs.size() - 1]["aff"]]["tint"]
	Sfx.play("skill")
	music_hold = 25.0
	Sfx.play_music("lullaby", 1.0)
	var tw := create_tween()
	tw.tween_interval(0.4)
	tw.tween_property(n, "rotation:y", n.rotation.y + TAU * (3.0 if big else 1.0), 1.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	for i in 6:
		get_tree().create_timer(0.4 + i * 0.22).timeout.connect(func(): fx.burst(at + Vector3(0, 0.5, 0), tint, 6, 2.0, 0.4, -2.0))
	tw.tween_callback(func():
		# swap in the grown model
		if not is_instance_valid(n):
			building_now = false
			return
		var nn := Models.kin(rec["species"], rec)
		nn.position = at
		nn.rotation = n.rotation
		var lbl: Label3D = k["emote"]
		n.remove_child(lbl)
		nn.add_child(lbl)
		add_child(nn)
		n.queue_free()
		k["node"] = nn
		k["busy"] = false
		k["t"] = 3.0
		fx.burst(at + Vector3(0, 0.5, 0), tint, 36, 5.0, 0.8, 4.0, 1.3)
		fx.ring(at, 3.0, Color(tint, 0.9), 0.5)
		Sfx.play("unlock")
		Sfx.play("kin_happy")
		_emote(k, "★")
		building_now = false
		cam.zoom_to = 0.8
		var v := _new_panel(("%s evolved" if big else "%s is changing") % rec["name"], 520)
		for e in evs:
			v.add_child(UI.label(String(e.get("text", Evo.describe(e, rec))), 16, Evo.AFF[e["aff"]]["tint"]))
		v.add_child(UI.label("How you raise it decides what it grows into next. Feed it, fight beside it, look after it.", 14, UI.MUTED)))

# ---- buildings and bridges
func _building_verb(b: String) -> String:
	match b:
		"hall": return "Look at your trophies"
		"cottage", "cottage2": return "Peek into the %s" % Data.BUILDINGS[b]["name"]
	return "Visit the %s" % Data.BUILDINGS[b]["name"]

func _open_lot(b: String) -> void:
	var bd: Dictionary = Data.BUILDINGS[b]
	if lots[b]["built"]:
		if b == "hall":
			_open_hall()
			return
		var v := _new_panel(bd["name"], 480)
		v.add_child(UI.label(bd["desc"], 16))
		if b in ["cottage", "cottage2"]:
			var resting: Array = []
			for rec in Save.d["roster"]:
				if rec["uid"] != Save.d.get("active", ""): resting.append(rec["name"])
			v.add_child(UI.label(("Resting here: " + ", ".join(resting)) if resting.size() > 0 else "Nobody's resting here right now. Kin who aren't your partner sleep here.", 15, UI.MUTED))
		return
	var v := _new_panel("Build a %s" % bd["name"], 500)
	v.add_child(UI.label(bd["desc"], 16))
	var cost := int(bd["cost"])
	v.add_child(UI.label("Costs %d gems. You have %d." % [cost, int(Save.d["gems"])], 15, UI.GOLD if int(Save.d["gems"]) >= cost else UI.BAD))
	var btn := UI.button("Build it", func():
		if int(Save.d["gems"]) < cost or Save.has_building(b): return
		Save.d["gems"] = int(Save.d["gems"]) - cost
		Save.d["buildings"].append(b)
		Save.save_game()
		_close_panel()
		_construct(b), 200)
	btn.disabled = int(Save.d["gems"]) < cost
	v.add_child(btn)

## Builds a building on its lot: the site packs away and the building pops up with dust and hammering.
func _construct(b: String) -> void:
	building_now = true
	var l: Dictionary = lots[b]
	var holder: Node3D = l["node"]
	var rc: Array = Data.BUILDINGS[b]["rect"]
	world.set_block_rect(rc[0], rc[1], rc[2], rc[3])
	# step the player out of the footprint if needed
	if world.is_block(ppos.x, ppos.z):
		ppos = l["door"]
	for c in holder.get_children():
		var tw0 := create_tween()
		tw0.tween_property(c, "scale", Vector3(1, 0.01, 1), 0.25)
		tw0.tween_callback(c.queue_free)
	var n := Models.building(b)
	holder.add_child(n)
	var body: Node3D = n.get_node("Body")
	body.scale = Vector3(0.6, 0.0, 0.6)
	var tw := create_tween()
	tw.tween_interval(0.3)
	tw.tween_property(body, "scale", Vector3(1.0, 0.45, 1.0), 0.35).set_trans(Tween.TRANS_SINE)
	tw.tween_property(body, "scale", Vector3(1.0, 0.8, 1.0), 0.35).set_trans(Tween.TRANS_SINE)
	tw.tween_property(body, "scale", Vector3(1.0, 1.0, 1.0), 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	for i in 5:
		get_tree().create_timer(0.3 + i * 0.24).timeout.connect(func():
			Sfx.play("build", null, -3.0, 0.15)
			fx.dust(l["at"] + Vector3(randf_range(-1.4, 1.4), 0, randf_range(-1.0, 1.0)), 10))
	get_tree().create_timer(1.55).timeout.connect(func():
		Sfx.play("unlock")
		fx.burst(l["at"] + Vector3(0, 2.6, 0), UI.GOLD, 26, 6.0, 0.8, 8.0, 1.2)
		fx.ring(l["at"], 4.0, Color(UI.GOLD, 0.9), 0.5)
		l["built"] = true
		building_now = false
		if b == "greenhouse": _build_plots()
		_toast("%s built" % Data.BUILDINGS[b]["name"]))
	cam.zoom_to = 0.95

func _open_bridge(k: String) -> void:
	var isd: Dictionary = Data.ISLES[k]
	var v := _new_panel("Bridge to %s" % isd["name"], 520)
	v.add_child(UI.label(isd["desc"], 16))
	var ex := int(Save.d.get("extracts", 0))
	var cost := int(isd["cost"])
	var need := int(isd["need"])
	if ex < need:
		v.add_child(UI.label("Make it out of %d more expedition%s to get the materials." % [need - ex, "" if need - ex == 1 else "s"], 15, UI.BAD))
		return
	v.add_child(UI.label("Costs %d gems. You have %d." % [cost, int(Save.d["gems"])], 15, UI.GOLD if int(Save.d["gems"]) >= cost else UI.BAD))
	var btn := UI.button("Build the bridge", func():
		if int(Save.d["gems"]) < cost or Save.has_bridge(k): return
		Save.d["gems"] = int(Save.d["gems"]) - cost
		Save.d["bridges"].append(k)
		Save.save_game()
		_close_panel()
		_build_bridge_now(k), 220)
	btn.disabled = int(Save.d["gems"]) < cost
	v.add_child(btn)

func _build_bridge_now(k: String) -> void:
	building_now = true
	var br: Dictionary = bridges[k]
	br["built"] = true
	_lay_planks(k, true)
	var n: int = _plank_spots(k).size()
	cam.zoom_to = 1.15
	get_tree().create_timer(n * 0.06 + 0.4).timeout.connect(func():
		world.open_bridge(br["tiles"])
		Sfx.play("unlock")
		var far: Vector3 = _plank_spots(k)[n - 1]
		fx.burst(far + Vector3(0, 1.0, 0), UI.GOLD, 24, 5.0, 0.8)
		var lbl: Label3D = br["label"]
		var tw := create_tween()
		tw.tween_property(lbl, "modulate:a", 0.0, 0.6)
		tw.tween_callback(func(): lbl.visible = false)
		building_now = false
		_spawn_kin()
		_toast("%s is open" % Data.ISLES[k]["name"]))

func _toast(txt: String) -> void:
	var c := UI.card(Color(0.06, 0.07, 0.1, 0.9), 12, 18)
	var l := UI.label(txt, 22, UI.GOLD, UI.big)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	c.add_child(l)
	root_ui.add_child(c)
	c.reset_size()
	var vp := get_viewport().get_visible_rect().size
	c.position = Vector2((vp.x - c.size.x) * 0.5, 90)
	c.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(c, "modulate:a", 1.0, 0.2)
	tw.parallel().tween_property(c, "position:y", 110.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(2.2)
	tw.tween_property(c, "modulate:a", 0.0, 0.4)
	tw.tween_callback(c.queue_free)

func _open_hall() -> void:
	var v := _new_panel("Trophy Hall", 560)
	var st: Dictionary = Save.d.get("stats", {})
	var grid := GridContainer.new(); grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30); grid.add_theme_constant_override("v_separation", 6)
	for row in [["Expeditions", int(Save.d["matches"])], ["Made it out", int(Save.d.get("extracts", 0))],
			["Hunters knocked out", int(st.get("knocks", 0))], ["Best match, kills", int(st.get("best_kills", 0))],
			["Most gems carried home", int(st.get("best_gems", 0))], ["Kin brought home", int(st.get("caught", 0))]]:
		grid.add_child(UI.label(row[0], 16, UI.MUTED))
		grid.add_child(UI.label(str(row[1]), 18, UI.GOLD, UI.big))
	v.add_child(grid)
	v.add_child(UI.section("Your kin"))
	var kr := HFlowContainer.new()
	kr.add_theme_constant_override("h_separation", 8)
	for rec in Save.d["roster"]:
		var sp: Dictionary = Data.KIN[rec["species"]]
		var c := UI.card(UI.CARD, 6, 10)
		c.add_child(UI.label("%s · %s · lv %d" % [rec["name"], sp["name"], int(rec["level"])], 14, sp["color"]))
		kr.add_child(c)
	v.add_child(kr)

# ---- heroes and loadout
func _open_loadout() -> void:
	var v := _new_panel("Hero and loadout", 780)
	var hero := _hero()
	var hd: Dictionary = Data.HEROES[hero]
	var cols := UI.hbox(10)
	for c in ["light", "medium", "heavy"]:
		var cd: Dictionary = Data.CLASSES[c]
		var col := UI.vbox(6); col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var hl := UI.label("%s  ·  %d HP  ·  %d dash%s" % [cd["name"], cd["hp"], cd["dashes"], "es" if cd["dashes"] > 1 else ""], 13, UI.MUTED)
		hl.autowrap_mode = TextServer.AUTOWRAP_OFF
		col.add_child(hl)
		for hid in Data.HEROES:
			if Data.HEROES[hid]["cls"] != c: continue
			var hh: Dictionary = Data.HEROES[hid]
			var hk: String = hid
			var b := UI.button("%s  ·  %s" % [hh["name"], hh["role"]], func():
				Save.d["hero"] = hk
				Save.d["cls"] = Data.HEROES[hk]["cls"]
				Save.d["weapon"] = Data.HEROES[hk]["weapon"]
				Save.save_game()
				_refresh_player_model()
				_open_loadout())
			if hid == hero:
				b.theme_type_variation = "Chosen"
			col.add_child(b)
		cols.add_child(col)
	v.add_child(cols)
	var det := UI.card(UI.CARD, 12, 14)
	var dv := UI.vbox(5); det.add_child(dv)
	dv.add_child(UI.title("%s, %s" % [hd["name"], String(hd["role"]).to_lower()], 22, hd["color"]))
	dv.add_child(UI.label("Passive: " + String(hd["passive"]), 14))
	dv.add_child(UI.label("E  %s: %s" % [Data.ABIL[hd["e"]]["name"], Data.ABIL[hd["e"]]["desc"]], 14))
	dv.add_child(UI.label("R  %s: %s" % [Data.ABIL[hd["r"]]["name"], Data.ABIL[hd["r"]]["desc"]], 14, UI.GOLD))
	v.add_child(det)
	v.add_child(UI.section("Weapon"))
	var wr := UI.hbox(8)
	var cur_w: String = Save.d.get("weapon", hd["weapon"])
	for w in Data.CLASSES[hd["cls"]]["weapons"]:
		var wd: Dictionary = Data.WEAPONS[w]
		var wk: String = w
		var wb := UI.choice(String(wd["name"]), w == cur_w, func():
			Save.d["weapon"] = wk
			Save.save_game()
			_refresh_player_model()
			_open_loadout())
		wb.tooltip_text = "%d damage, %d per mag, range %d" % [int(wd["dmg"]), int(wd["mag"]), int(wd["range"])]
		wr.add_child(wb)
	v.add_child(wr)
	v.add_child(UI.section("Perk"))
	var pr := HFlowContainer.new()
	pr.add_theme_constant_override("h_separation", 8); pr.add_theme_constant_override("v_separation", 8)
	var cur_p: String = Save.d.get("perk", "")
	for pkey in Data.PERKS:
		var pd: Dictionary = Data.PERKS[pkey]
		var pk: String = pkey
		var pb := UI.choice(String(pd["name"]), pkey == cur_p, func():
			Save.d["perk"] = pk
			Save.save_game()
			_open_loadout())
		pb.tooltip_text = pd["desc"]
		pr.add_child(pb)
	v.add_child(pr)
	if Data.PERKS.has(cur_p):
		v.add_child(UI.label(Data.PERKS[cur_p]["desc"], 14, UI.GOLD))
	v.add_child(UI.button("Back to the expedition", _open_expedition, 240))

func _refresh_player_model() -> void:
	var hero := _hero()
	var at := player.position
	var rot := player.rotation
	player.queue_free()
	var w := _weapon()
	player = Models.hunter(Data.HEROES[hero]["cls"], Data.TEAM_COLORS[0], w, hero)
	player.position = at; player.rotation = rot
	add_child(player)

# ---- music list
func _open_music() -> void:
	var v := _new_panel("Music", 560)
	var have: Array = Save.d.get("music", [])
	v.add_child(UI.label("%d of %d tracks found. Pick one to play it here, or let the music follow where you are." % [have.size(), Data.MUSIC.size()], 14, UI.MUTED))
	for id in Data.MUSIC:
		var md: Dictionary = Data.MUSIC[id]
		var row := UI.hbox(10)
		var got: bool = have.has(id)
		var nl := UI.label(String(md["name"]) if got else "???", 16, UI.INK if got else UI.MUTED)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nl)
		if got:
			var tid: String = id
			var playing: bool = Sfx.music_name == id
			var b := UI.button("Playing" if playing else "Play", func():
				Sfx.music_lock = tid
				Sfx.play_music(tid, 1.0)
				_open_music(), 120)
			b.disabled = playing
			row.add_child(b)
		else:
			var hl := UI.label(String(md["hint"]), 13, UI.MUTED)
			hl.autowrap_mode = TextServer.AUTOWRAP_OFF
			row.add_child(hl)
		v.add_child(row)
	if Sfx.music_lock != "":
		v.add_child(UI.button("Let the music follow where I am", func():
			Sfx.music_lock = ""
			Sfx.music_name = ""
			_music_t = 0.0
			_open_music(), 320))

# ---- visiting and the ferry
func _use_visiting(it: Dictionary) -> void:
	var owner_name := String(visit.get("name", "Their owner")).substr(0, 16)
	match it["kind"]:
		"kin":
			var rec: Dictionary = it["k"]["rec"]
			if petted.has(rec["uid"]):
				_emote(it["k"], "♥")
				return
			petted[rec["uid"]] = true
			Social.send_gift(visit_id, "pet", String(rec["uid"]))
			_emote(it["k"], "♥")
			Sfx.play("kin_happy")
			_toast("%s will remember your visit" % rec["name"])
		"house":
			_open_gift_panel(owner_name)
		"portal", "ferry":
			Game.goto("home")
		_:
			_toast("This belongs to %s" % owner_name)

func _open_gift_panel(owner_name: String) -> void:
	var v := _new_panel("Leave a gift for %s" % owner_name, 520)
	v.add_child(UI.label("They'll find it next time they're home.", 14, UI.MUTED))
	var any := false
	for kind in ["seed", "crop"]:
		var store: Dictionary = Save.d["seeds"] if kind == "seed" else Save.d["crops"]
		for key in store:
			if int(store[key]) <= 0 or not Data.CROPS.has(key):
				continue
			any = true
			var row := UI.hbox(10)
			var l := UI.label("%s%s  ×%d" % [Data.CROPS[key]["name"], " seed" if kind == "seed" else "", int(store[key])], 15, Data.CROPS[key]["color"])
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(l)
			var kk: String = key
			var kd: String = kind
			row.add_child(UI.button("Give one", func():
				var st: Dictionary = Save.d["seeds"] if kd == "seed" else Save.d["crops"]
				if int(st.get(kk, 0)) <= 0:
					return
				st[kk] = int(st[kk]) - 1
				Save.save_game()
				_close_panel()
				Social.send_gift(visit_id, kd, kk, func(okk: bool):
					if okk:
						Sfx.play("pickup")
						if is_inside_tree(): _toast("Gift left for %s" % owner_name)
					else:
						st[kk] = int(st.get(kk, 0)) + 1      # it didn't arrive, so it's still yours
						Save.save_game()
						if is_inside_tree(): _toast("The gift couldn't be left. Try again in a moment.")), 140))
			v.add_child(row)
	if not any:
		v.add_child(UI.label("You have nothing to give yet. Seeds and crops make good gifts.", 15))

## The "while you were away" note waits until nothing else is on screen.
func _show_when_free(lines: Array) -> void:
	if not is_inside_tree():
		return
	if panel_open != "" or building_now or not Save.d["tutorial"].get("home", false):
		get_tree().create_timer(1.0).timeout.connect(_show_when_free.bind(lines))
		return
	var v := _new_panel("While you were away", 520)
	for l in lines: v.add_child(UI.label(l, 15))
	_refresh_top()

func _open_ferry() -> void:
	var v := _new_panel("Ferry", 520)
	if not Social.available():
		v.add_child(UI.label("The ferry connects you with other players: the town, guilds and friends' islands. It runs in the web version of Kinfall.", 15))
		return
	v.add_child(UI.label("Where to?", 14, UI.MUTED))
	v.add_child(UI.button("The town: market, notice board and guilds", func(): Game.goto("town", {"mode": "hub"}), 440))
	if not Social.guild.is_empty():
		var gname := String(Social.guild.get("name", "your guild"))
		var gid := Social.my_guild_id()
		v.add_child(UI.button("Your guild isle: %s" % gname, func(): Game.goto("town", {"mode": "guild", "gid": gid}), 440))
	v.add_child(UI.label("Visit a friend's island", 14, UI.MUTED))
	var list := UI.vbox(6)
	v.add_child(list)
	list.add_child(UI.label("Looking for islands...", 14, UI.MUTED))
	Social.list_islands(func(rows: Array):
		if not is_instance_valid(list):
			return
		for c in list.get_children():
			c.queue_free()
		if rows.is_empty():
			list.add_child(UI.label("Nobody else has an island here yet. Share the game with a friend to visit each other.", 14, UI.MUTED))
		for r in rows.slice(0, 12):
			var d: Dictionary = r["d"]
			var row := UI.hbox(10)
			var l := UI.label("%s  ·  %d kin  ·  %d buildings" % [d["name"], d["roster"].size(), d["buildings"].size()], 15)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(l)
			var rid: String = r["id"]
			row.add_child(UI.button("Visit", func(): Game.goto("home", {"visit": d, "visit_id": rid}), 100))
			list.add_child(row))


# ---- house
func _open_house() -> void:
	var v := _new_panel("Your house", 620)
	v.add_child(UI.label("Your kin. The one you bring on expeditions is your partner.", 15, UI.MUTED))
	for rec in Save.d["roster"]:
		var row := UI.card(UI.CARD, 10, 10)
		var h := UI.hbox(12); row.add_child(h)
		var sp: Dictionary = Data.KIN[rec["species"]]
		var dot := ColorRect.new(); dot.color = sp["color"]; dot.custom_minimum_size = Vector2(14, 14)
		h.add_child(dot)
		var info := UI.label("%s the %s  ·  level %d  ·  trust %d" % [rec["name"], Evo.form_name(rec), int(rec["level"]), int(rec["trust"])], 15)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(info)
		var r: Dictionary = rec
		if rec["uid"] == Save.d.get("active", ""):
			h.add_child(UI.label("Partner", 14, UI.GOLD))
		else:
			h.add_child(UI.button("Make partner", func():
				Save.d["active"] = r["uid"]
				Save.save_game()
				_open_house()))
		h.add_child(UI.button("Visit", func(): _open_kin(r)))
		v.add_child(row)
	var hb := UI.hbox(8)
	hb.add_child(UI.button("Music", _open_music, 160))
	hb.add_child(UI.button("Settings", _open_settings, 160))
	v.add_child(hb)

# ---- settings
func _open_settings() -> void:
	_close_panel()
	Overlay.ctx = "home"
	Overlay.open_settings()
