extends Node3D
## The shared places: the town (market, notice board, guild registry, online expeditions) and
## guild isles (member cottages and the projects everyone builds together). Other players who are
## here right now walk around too.

const SPEED := 5.0

var mode := "hub"          # hub | guild
var gid := ""              # the guild whose isle this is
var world: World
var cam: CamRig
var fx: Fx
var root_ui: Control
var panel_host: Control
var panel_open := ""
var topbar: Label
var prompt_box: PanelContainer
var prompt_lbl: Label
var player: Node3D
var ppos := Vector3.ZERO
var pvel := Vector3.ZERO
var pface := 0.0
var py := 0.0
var pvy := 0.0
var walk_ph := 0.0
var spots: Array = []          # {kind, pos, label, reach, data}
var interact: Dictionary = {}
var others := {}               # peer id -> {node, label, pos, to, face}
var npcs: Array = []           # wandering kin for life
var guild_doc: Dictionary = {}
var members: Array = []        # [{id, data}]
var project_nodes := {}
var project_prog := {}
var _js_cb = null
var _pres_t := 0.0
var _last_sent := Vector3.INF
var center := Vector2.ZERO
var solids: Array = []         # Rect2 footprints of things built after the ground was laid

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_env()
	world = World.new(); add_child(world)
	fx = Fx.new(); add_child(fx)
	cam = CamRig.new(); add_child(cam)
	cam.zoom_to = 1.05; cam.zoom = 1.05; cam.lead = 0.2
	_build_ui()
	if mode == "guild":
		_build_guild()
		Sfx.play_music("guild")
	else:
		_build_hub()
		Sfx.play_music("hub")
	Sfx.play_ambience("home")
	player = Models.hunter(Data.class_of_save(), Data.TEAM_COLORS[0], Data.weapon_for(Data.class_of_save(), String(Save.d.get("weapon", ""))), "", Save.d.get("look", {}))
	add_child(player)
	player.position = ppos
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--home-zoom="): cam.zoom_to = float(a.substr(12)); cam.zoom = cam.zoom_to
		if a.begins_with("--home-at="):
			var xz := a.substr(10).split(",")
			ppos = Vector3(float(xz[0]), 0, float(xz[1])); player.position = ppos
	cam.snap(ppos)
	_join_presence()

func _exit_tree() -> void:
	var js = JavaScriptBridge.get_interface("kinBridge") if OS.has_feature("web") else null
	if js:
		js.hubLeave()

func _build_env() -> void:
	var env := WorldEnvironment.new()
	env.environment = Look.environment({"top": Color("2a4a8a"), "mid": Color("6a8ad0"), "horizon": Color("ffd2a8"), "below": Color("3a3a6a"),
		"ambient": Color("c9cfe6"), "ambient_energy": 0.5, "fog": Color("8a96c8"), "fog_height": -4.0, "stars": 0.0})
	add_child(env)
	Look.lights(self, Color("ffe6c8"), 0.95, Vector3(-52, -35, 0), 45.0)

func _spot(kind: String, at: Vector3, label: String, reach := 2.2, data = null) -> void:
	spots.append({"kind": kind, "pos": at, "label": label, "reach": reach, "data": data})

# ------------------------------------------------------------------ the town
func _build_hub() -> void:
	center = Vector2(25, 22)
	world.make_islands(909, 50, 44, [["town", center, Vector2(18, 15)]])
	var stone := Color("a59c8c")
	for z in world.h:
		for x in world.w:
			var dd := Vector2(x + 0.5 - center.x, z + 0.5 - center.y).length()
			if dd < 6.2: world.paint_tile(x, z, stone)
	var path := Color("9c7a52")
	world.paint_path(Vector2i(25, 28), Vector2i(25, 34), path)
	world.paint_path(Vector2i(10, 22), Vector2i(19, 22), path)
	world.paint_path(Vector2i(31, 22), Vector2i(40, 22), path)
	world.paint_path(Vector2i(25, 10), Vector2i(25, 16), path)
	world.set_block_rect(24, 21, 25, 22)          # fountain
	world.set_block_rect(15, 13, 19, 14)          # market stalls
	world.set_block_rect(31, 11, 34, 13)          # guild registry
	world.add_trees_on_rim(22)
	world.build_meshes()
	var f := Models.fountain(); f.position = Vector3(25, 0, 22); add_child(f)
	(f.get_node("Spray") as CPUParticles3D).emitting = true
	for i in 3:
		var st := Models.stall(); st.position = Vector3(15.6 + i * 1.6, 0, 13.8); add_child(st)
	_spot("market", Vector3(17.2, 0, 15.6), "Browse the market", 2.6)
	var nb := Models.notice_board(); nb.position = Vector3(25, 0, 12.6); add_child(nb)
	_spot("notices", Vector3(25, 0, 14.0), "Read the notice board", 2.4)
	var reg := Models.building("hall"); reg.position = Vector3(32.8, 0, 12.4); add_child(reg)
	_spot("guilds", Vector3(32.8, 0, 15.2), "Guild registry", 2.4)
	var portal := Models.portal(UI.TEAL); portal.position = Vector3(25, 0, 33.5); add_child(portal)
	portal.get_node("Disc").visible = true
	(portal.get_node("Beam") as CPUParticles3D).emitting = true
	_spot("lobby", Vector3(25, 0, 33.5), "Expeditions with other players", 2.4)
	var fp := Models.ferry_post(); fp.position = Vector3(10.5, 0, 22); fp.rotation.y = PI * 0.5; add_child(fp)
	_spot("ferry", Vector3(10.5, 0, 22), "Ferry home", 2.2)
	var vp := Models.signpost(["Islands", "to visit"]); vp.position = Vector3(39.5, 0, 22.8); add_child(vp)
	_spot("visit", Vector3(39.5, 0, 22.8), "Visit a player's island", 2.2)
	if Social.my_guild_id() != "":
		var gp := Models.ferry_post(); gp.position = Vector3(40.5, 0, 26.5); gp.rotation.y = -PI * 0.5; add_child(gp)
		_spot("to_guild", Vector3(40.5, 0, 26.5), "Ferry to your guild isle", 2.2)
	for lp in [Vector3(19.5, 0, 18), Vector3(30.5, 0, 18), Vector3(19.5, 0, 26.5), Vector3(30.5, 0, 26.5), Vector3(23, 0, 31.5), Vector3(27, 0, 31.5)]:
		var l := Models.lamp(); l.position = lp; add_child(l)
	var drng := RandomNumberGenerator.new(); drng.seed = 9
	for fb in [Vector3(21, 0, 16.5), Vector3(29, 0, 16.5), Vector3(21, 0, 27.8), Vector3(29, 0, 27.8)]:
		var b := Models.flower_bed(drng); b.position = fb; add_child(b)
	# a few wild kin wander the square
	var sp: Array = Data.common_kin()
	for i in 5:
		var rec := Save.new_kin(sp[drng.randi_range(0, sp.size() - 1)])
		rec["level"] = drng.randi_range(1, 14)
		Evo.simulate(rec, drng)
		_add_npc(rec, world.random_ground(0))
	ppos = Vector3(13.0, 0, 22.5)
	topbar.text = "Town   ·   Market, notice board and guilds   ·   %d gems" % int(Save.d["gems"])

# ------------------------------------------------------------------ a guild isle
func _build_guild() -> void:
	center = Vector2(28, 28)
	world.make_islands(4000 + gid.hash() % 1000, 56, 56, [["guild", center, Vector2(21, 20)]])
	var stone := Color("a59c8c")
	for z in world.h:
		for x in world.w:
			var dd := Vector2(x + 0.5 - center.x, z + 0.5 - center.y).length()
			if dd < 5.0 or (dd > 9.5 and dd < 10.6): world.paint_tile(x, z, stone)
	world.add_trees_on_rim(18)
	world.build_meshes()
	for i in 4:
		var a := TAU * i / 4.0 + PI * 0.25
		var l := Models.lamp(); l.position = Vector3(center.x + cos(a) * 6.2, 0, center.y + sin(a) * 6.2); add_child(l)
	var drng := RandomNumberGenerator.new(); drng.seed = 21
	for i in 6:
		var a := TAU * i / 6.0 + 0.5
		var b := Models.flower_bed(drng); b.position = Vector3(center.x + cos(a) * 8.0, 0, center.y + sin(a) * 8.0); add_child(b)
	ppos = Vector3(28, 0, 44.5)
	var fp := Models.ferry_post(); fp.position = Vector3(28, 0, 45.5); fp.rotation.y = PI; add_child(fp)
	_spot("ferry", Vector3(28, 0, 45.5), "Take the ferry", 2.2)
	topbar.text = "Guild isle"
	Social.get_guild(gid, func(g: Dictionary):
		if not is_inside_tree(): return
		guild_doc = g
		var col := Color(String(g.get("color", "f2a24a")))
		for i in 8:
			var a := TAU * i / 8.0 + 0.2
			var bn := Models.banner(col); bn.position = Vector3(center.x + cos(a) * 11.6, 0, center.y + sin(a) * 11.6); bn.rotation.y = -a
			add_child(bn)
		var motto: String = g.get("motto", "")
		topbar.text = String(g.get("name", "Guild isle")) + (("   ·   " + motto) if motto != "" else "")
		_load_members())

func _load_members() -> void:
	Social.guild_members(gid, func(rows: Array):
		if not is_inside_tree(): return
		members = rows
		if members.is_empty() and "--town-fake" in OS.get_cmdline_user_args():
			members = _fake_members()
		members.sort_custom(func(a, b): return String(a["id"]) < String(b["id"]))
		# member cottages in a ring
		var slots := clampi(members.size(), 6, 12)
		for i in mini(members.size(), 12):
			var m: Dictionary = members[i]
			var d: Dictionary = m["d"]
			var a := PI * 0.5 + deg_to_rad(32.0) + i * deg_to_rad(296.0) / float(slots - 1)   # the south side is the ferry
			var at := Vector3(center.x + cos(a) * 15.5, 0, center.y + sin(a) * 15.5)
			if world.is_void(at.x, at.z):
				at = Vector3(center.x + cos(a) * 13.5, 0, center.y + sin(a) * 13.5)
			var c := Models.building("cottage" if i % 2 == 0 else "cottage2")
			c.position = at; c.rotation.y = -a - PI * 0.5; c.scale = Vector3.ONE * 0.75
			add_child(c)
			_solid(at, 2.4, 2.4)
			var sg := Models.signpost([String(d["name"])]); sg.position = at + Vector3(cos(a), 0, sin(a)) * -2.0; sg.rotation.y = -a - PI * 0.5
			add_child(sg)
			_spot("member", at + Vector3(cos(a), 0, sin(a)) * -2.2, "Visit %s's island" % d["name"], 2.0, {"id": m["id"], "data": d})
			for rec in d["roster"]:
				if rec["uid"] == d["active"]:
					_add_npc(rec, at + Vector3(cos(a), 0, sin(a)) * -2.8)
		_refresh_projects())

## Re-reads how far each project is and redraws only the projects.
func _refresh_projects() -> void:
	Social.load_progress(gid, guild_doc, func(prog: Dictionary):
		if not is_inside_tree(): return
		if "--town-built" in OS.get_cmdline_user_args():
			for k in Social.PROJECTS: prog[k] = Social.PROJECTS[k]["goal"]
		if gid == Social.my_guild_id():
			Social.guild_progress = prog
			Social._store_perks()
		project_prog = prog
		_build_projects(prog))

func _build_projects(prog: Dictionary) -> void:
	for k in project_nodes:
		project_nodes[k].queue_free()
	project_nodes.clear()
	solids = solids.filter(func(rc): return not (rc as Rect2).has_point(Vector2(28, 28)) and not (rc as Rect2).has_point(Vector2(36.5, 28)) and not (rc as Rect2).has_point(Vector2(19.5, 28)) and not (rc as Rect2).has_point(Vector2(28, 19.5)))
	spots = spots.filter(func(s): return s["kind"] != "project")
	var places := {"hall": Vector3(28, 0, 28), "forge": Vector3(36.5, 0, 28), "shrine": Vector3(19.5, 0, 28), "lighthouse": Vector3(28, 0, 19.5)}
	var col := Color(String(guild_doc.get("color", "f2a24a")))
	for k in Social.PROJECTS:
		var pd: Dictionary = Social.PROJECTS[k]
		var done := int(prog.get(k, 0)) >= int(pd["goal"])
		var at: Vector3 = places[k]
		var n: Node3D
		if done:
			match k:
				"hall": n = Models.building("hall"); n.scale = Vector3.ONE * 1.5
				"forge": n = Models.building("workshop")
				"shrine": n = Models.shrine(); n.scale = Vector3.ONE * 1.6
				"lighthouse": n = Models.lighthouse(col)
		else:
			n = Models.lot(4.0, 3.0, pd["name"], "%d / %d gems" % [int(prog.get(k, 0)), int(pd["goal"])])
		n.position = at
		add_child(n)
		project_nodes[k] = n
		if done:
			match k:
				"hall": _solid(at, 4.4, 3.2)
				"forge": _solid(at, 3.0, 2.4)
				"shrine": _solid(at, 1.6, 1.6)
				"lighthouse": _solid(at, 1.8, 1.8)
		_spot("project", at + Vector3(0, 0, 2.6 if k != "lighthouse" else 2.0), ("%s (built)" % pd["name"]) if done else "Build the %s together" % pd["name"], 2.4, k)

func _add_npc(rec: Dictionary, at: Vector3) -> void:
	var n := Models.kin(rec["species"], rec)
	n.position = at
	add_child(n)
	npcs.append({"node": n, "pos": at, "home": at, "goal": at, "t": randf() * 3.0, "hop": randf() * 5.0})

# ------------------------------------------------------------------ live presence
func _join_presence() -> void:
	if not OS.has_feature("web"):
		return
	var js = JavaScriptBridge.get_interface("kinBridge")
	if js == null:
		return
	_js_cb = JavaScriptBridge.create_callback(func(a):
		var arr = JSON.parse_string(str(a[0])) if a.size() > 0 else null
		if typeof(arr) == TYPE_ARRAY:
			_on_peers(arr))
	js.hubJoin("kf-" + (("guild-" + gid) if mode == "guild" else "town"), _js_cb)

func _send_presence(d: float) -> void:
	# real time, not game time: slow frames must not let others think you've left
	var now := Time.get_ticks_msec() / 1000.0
	if now < _pres_t:
		return
	var moved := _last_sent == Vector3.INF or ppos.distance_to(_last_sent) > 0.15
	_pres_t = now + (0.2 if moved else 1.0)
	_last_sent = ppos
	var js = JavaScriptBridge.get_interface("kinBridge") if OS.has_feature("web") else null
	if js == null:
		return
	var ak := Save.active_kin()
	js.hubPresence(JSON.stringify({"n": String(Save.d.get("name", "Hunter")).substr(0, 16), "h": Data.class_of_save(),
		"x": snappedf(ppos.x, 0.01), "z": snappedf(ppos.z, 0.01), "f": snappedf(pface, 0.01), "k": ak.get("species", "")}))

func _on_peers(arr: Array) -> void:
	var seen := {}
	for it in arr:
		var row := Social.dict_of(it)
		var p := Social.dict_of(row.get("p"))
		var id := Social.txt_of(row.get("id"))
		if id == "" or not (p.has("x") and p.has("z")) or seen.size() >= 30:
			continue
		seen[id] = true
		var at := Vector3(clampf(Social.num_of(p["x"]), 0, world.w), 0, clampf(Social.num_of(p["z"]), 0, world.h))
		if not others.has(id):
			var ocl := Social.txt_of(p.get("h"), "medium")
			if not Data.CLASSES.has(ocl): ocl = "medium"
			var n := Models.hunter(ocl, Data.TEAM_COLORS[1 + others.size() % 5], Data.CLASSES[ocl]["weapon"], "")
			add_child(n)
			var lbl := Label3D.new()
			lbl.font = UI.big; lbl.font_size = 40; lbl.pixel_size = 0.01; lbl.outline_size = 10
			lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED; lbl.no_depth_test = true; lbl.position.y = 2.3
			n.add_child(lbl)
			n.position = at
			var kn: Node3D = null
			var ksp := Social.txt_of(p.get("k"))
			if Data.KIN.has(ksp):
				kn = Models.kin(ksp); kn.scale = Vector3.ONE * 0.8; add_child(kn); kn.position = at + Vector3(0.9, 0, 0.5)
			others[id] = {"node": n, "label": lbl, "pos": at, "to": at, "face": 0.0, "kin": kn, "ph": 0.0}
		var o: Dictionary = others[id]
		o["to"] = at
		o["face"] = Social.num_of(p.get("f"))
		(o["label"] as Label3D).text = Social.say_of(p.get("n"), "Hunter")
	for id in others.keys():
		if not seen.has(id):
			others[id]["node"].queue_free()
			if others[id]["kin"]: others[id]["kin"].queue_free()
			others.erase(id)

# ------------------------------------------------------------------ loop
func _process(delta: float) -> void:
	var d := minf(delta, 0.05)
	_move_player(d)
	for o in others.values():
		var pos: Vector3 = o["pos"]
		var to: Vector3 = o["to"]
		var step := to - pos
		o["pos"] = pos + step * minf(1.0, d * 8.0)
		var n: Node3D = o["node"]
		n.position = o["pos"]
		n.rotation.y = lerp_angle(n.rotation.y, o["face"], minf(1.0, d * 10.0))
		if not n.has_meta("anim"): n.set_meta("anim", HunterAnim.new(n))
		(n.get_meta("anim") as HunterAnim).update(d, {"vel": step * 8.0, "face": n.rotation.y, "fired": 99.0})
		if o["kin"]:
			var kn: Node3D = o["kin"]
			kn.position = kn.position.lerp(o["pos"] + Vector3(0.9, 0, 0.5), minf(1.0, d * 3.0))
	for k in npcs:
		k["t"] -= d
		if k["t"] <= 0.0:
			k["t"] = randf_range(2.0, 5.0)
			var home: Vector3 = k["home"]
			var g := home + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
			if not world.is_void(g.x, g.z) and not world.is_block(g.x, g.z): k["goal"] = g
		var pos: Vector3 = k["pos"]
		var goal: Vector3 = k["goal"]
		var v := Vector2(goal.x - pos.x, goal.z - pos.z)
		var n: Node3D = k["node"]
		if v.length() > 0.3:
			var nxt := pos + Vector3(v.x, 0, v.y).normalized() * 2.0 * d
			if not _blocked(nxt.x, nxt.z, 0.3): k["pos"] = nxt
			n.rotation.y = lerp_angle(n.rotation.y, atan2(-v.x, -v.y), minf(1.0, d * 8.0))
			k["hop"] += d * 9.0
		n.position = k["pos"]
		n.get_node("Body").position.y = absf(sin(k["hop"])) * 0.12
	cam.follow(ppos, d, panel_open == "")
	_send_presence(d)
	_find_interact()
	if panel_open == "" and not Overlay.is_open() and Input.is_action_just_pressed("interact") and not interact.is_empty():
		_use(interact)

func _move_player(d: float) -> void:
	var mv := Vector2.ZERO
	if panel_open == "" and not Overlay.is_open():
		mv = Vector2(Input.get_axis("left", "right"), Input.get_axis("up", "down"))
		if mv.length() > 1.0: mv = mv.normalized()
	var hv := Vector2(pvel.x, pvel.z)
	hv += (mv * SPEED - hv) * (1.0 - exp(-14.0 * d))
	var nx := ppos.x + hv.x * d
	if not _blocked(nx, ppos.z, 0.38): ppos.x = nx
	var nz := ppos.z + hv.y * d
	if not _blocked(ppos.x, nz, 0.38): ppos.z = nz
	pvel = Vector3(hv.x, 0, hv.y)
	if panel_open == "" and not Overlay.is_open() and py <= 0.0 and pvy <= 0.0 and Input.is_action_just_pressed("jump"):
		pvy = 8.5
		Sfx.play("jump", null, -12.0)
	if py > 0.0 or pvy > 0.0:
		pvy -= 26.0 * d
		py = maxf(0.0, py + pvy * d)
		if py <= 0.0: pvy = 0.0
	player.position = ppos + Vector3(0, py, 0)
	# face the mouse, or where you walk when the mouse is outside the window
	var vp := get_viewport()
	var mp := vp.get_mouse_position()
	var want := pface
	if panel_open == "" and Rect2(Vector2.ZERO, vp.get_visible_rect().size).has_point(mp):
		var aim := cam.mouse_on_plane(0.9)
		if Vector2(aim.x - ppos.x, aim.z - ppos.z).length() > 0.4: want = atan2(-(aim.x - ppos.x), -(aim.z - ppos.z))
	elif hv.length() > 0.3:
		want = atan2(-hv.x, -hv.y)
	pface = lerp_angle(pface, want, minf(1.0, d * 14.0))
	player.rotation.y = pface
	if not player.has_meta("anim"): player.set_meta("anim", HunterAnim.new(player))
	var pa: HunterAnim = player.get_meta("anim")
	pa.update(d, {"vel": Vector3(hv.x, 0, hv.y), "face": pface, "fired": 99.0})
	if pa.stepped:
		Sfx.step(null, -20.0)

func _blocked(x: float, z: float, r: float) -> bool:
	if world.occupy(x, z, r, 0.0, true) != 0.0:
		return true
	for rc in solids:
		if (rc as Rect2).grow(r).has_point(Vector2(x, z)):
			return true
	return false

func _solid(at: Vector3, w: float, d: float) -> void:
	solids.append(Rect2(at.x - w * 0.5, at.z - d * 0.5, w, d))

func _find_interact() -> void:
	var best := {}; var bd := 99.0
	for s in spots:
		var p: Vector3 = s["pos"]
		var dd := Vector2(p.x - ppos.x, p.z - ppos.z).length()
		if dd < float(s["reach"]) and dd < bd:
			bd = dd; best = s
	interact = best
	if panel_open != "" or best.is_empty():
		prompt_box.visible = false
		return
	prompt_box.visible = true
	prompt_lbl.text = Settings.key_cap("interact") + "  " + String(best["label"])
	prompt_box.reset_size()
	var vp := get_viewport().get_visible_rect().size
	prompt_box.position = Vector2((vp.x - prompt_box.size.x) * 0.5, vp.y - 110.0)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu") and not Overlay.is_open():
		if panel_open != "": _close_panel()
		else: Overlay.open_pause("town")
	if event is InputEventMouseButton and event.pressed and panel_open == "":
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: cam.zoom_to = clampf(cam.zoom_to - 0.08, 0.55, 1.5)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: cam.zoom_to = clampf(cam.zoom_to + 0.08, 0.55, 1.5)

# ------------------------------------------------------------------ ui
func _build_ui() -> void:
	var ui := CanvasLayer.new(); add_child(ui)
	root_ui = Control.new(); root_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root_ui.theme = UI.theme()
	root_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root_ui)
	var top := UI.card(Color(0.06, 0.07, 0.1, 0.78), 12, 12)
	top.position = Vector2(16, 14)
	var th := UI.hbox(14); top.add_child(th)
	th.add_child(UI.title("Kinfall", 26, UI.ACCENT))
	topbar = UI.label("", 15, UI.INK)
	topbar.autowrap_mode = TextServer.AUTOWRAP_OFF
	th.add_child(topbar)
	root_ui.add_child(top)
	prompt_box = UI.card(Color(0.06, 0.07, 0.1, 0.85), 12, 12)
	prompt_lbl = UI.label("", 18, UI.GOLD, UI.big)
	prompt_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	prompt_box.add_child(prompt_lbl)
	root_ui.add_child(prompt_box)
	var hint_box := UI.card(Color(0.06, 0.07, 0.1, 0.7), 8, 10)
	var hint := UI.label("WASD walk   ·   Space jump   ·   " + Settings.key_cap("interact") + " use   ·   Scroll to zoom   ·   Esc menu", 14, UI.INK)
	hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	hint_box.add_child(hint)
	hint_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint_box.offset_top = -14; hint_box.offset_bottom = -14
	root_ui.add_child(hint_box)
	panel_host = CenterContainer.new()
	panel_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_ui.add_child(panel_host)

func _new_panel(title_txt: String, width := 540.0) -> VBoxContainer:
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
	for ch in panel_host.get_children():
		ch.queue_free()
	panel_open = ""

func _toast(txt: String) -> void:
	var c := UI.card(Color(0.06, 0.07, 0.1, 0.9), 12, 18)
	var l := UI.label(txt, 20, UI.GOLD, UI.big)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	c.add_child(l)
	root_ui.add_child(c)
	c.reset_size()
	var vp := get_viewport().get_visible_rect().size
	c.position = Vector2((vp.x - c.size.x) * 0.5, 100)
	var tw := create_tween()
	tw.tween_interval(2.4)
	tw.tween_property(c, "modulate:a", 0.0, 0.4)
	tw.tween_callback(c.queue_free)

func _row(v: VBoxContainer, text: String, col := UI.INK, size := 15) -> HBoxContainer:
	var row := UI.hbox(10)
	var l := UI.label(text, size, col)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	v.add_child(row)
	return row

func _loading(v: VBoxContainer) -> VBoxContainer:
	var list := UI.vbox(6)
	v.add_child(list)
	list.add_child(UI.label("Loading...", 14, UI.MUTED))
	return list

func _clear(list: VBoxContainer) -> bool:
	if not is_instance_valid(list):
		return false
	for c in list.get_children():
		c.queue_free()
	return true

## Greys out every button in the open panel while a request is out, so nothing runs twice.
func _lock() -> void:
	for b in panel_host.find_children("*", "Button", true, false):
		if (b as Button).text != "Close": (b as Button).disabled = true

# ------------------------------------------------------------------ what F does
func _use(it: Dictionary) -> void:
	Sfx.play("click")
	match String(it["kind"]):
		"ferry":
			if mode == "guild":
				var v := _new_panel("Ferry", 420)
				v.add_child(UI.button("Home", func(): Game.goto("home"), 360))
				v.add_child(UI.button("The town", func(): Game.goto("town", {"mode": "hub"}), 360))
			else:
				Game.goto("home")
		"to_guild": Game.goto("town", {"mode": "guild", "gid": Social.my_guild_id()})
		"lobby": Game.goto("lobby", {"cls": Save.d.get("cls", "medium"), "tier": 0})
		"market": _open_market()
		"notices": _open_notices()
		"guilds": _open_guilds()
		"visit": _open_visits()
		"member":
			var m = it.get("data")
			if typeof(m) != TYPE_DICTIONARY:
				return
			if String(m["id"]) == Social.me:
				Game.goto("home")
			else:
				Game.goto("home", {"visit": m["data"], "visit_id": m["id"]})
		"project":
			if Social.PROJECTS.has(it.get("data")):
				_open_project(String(it["data"]))

func _open_visits() -> void:
	var v := _new_panel("Islands to visit", 520)
	var list := _loading(v)
	Social.list_islands(func(rows: Array):
		if not _clear(list): return
		if rows.is_empty():
			list.add_child(UI.label("No other islands yet.", 14, UI.MUTED))
		for r in rows.slice(0, 14):
			var d: Dictionary = r["d"]
			var row := _row(list, "%s  ·  %d kin  ·  %d buildings" % [d["name"], d["roster"].size(), d["buildings"].size()])
			var rid: String = r["id"]
			row.add_child(UI.button("Visit", func(): Game.goto("home", {"visit": d, "visit_id": rid}), 100)))

# ---- market
func _open_market() -> void:
	var v := _new_panel("Market", 600)
	v.add_child(UI.label("Players sell seeds, crops and kin here. You have %d gems." % int(Save.d["gems"]), 14, UI.MUTED))
	var list := _loading(v)
	Social.list_market(func(rows: Array):
		if not _clear(list): return
		if rows.is_empty():
			list.add_child(UI.label("Nothing for sale right now. Be the first.", 14, UI.MUTED))
		for r in rows.slice(0, 12):
			var l: Dictionary = r["l"]
			var key: String = l["key"]
			var mine: bool = l["seller"] == Social.me
			var row: HBoxContainer
			if l["kind"] == "kin":
				var ck: Dictionary = l["kin"]
				row = _row(list, "%s the %s  ·  Lv %d%s  ·  %d gems  ·  from %s" % [ck["name"], Data.KIN[key]["name"], int(ck["level"]), "  ·  shimmer" if ck["shimmer"] else "",
					int(l["price"]), l["seller_name"]], Data.KIN[key]["color"])
			else:
				row = _row(list, "%s%s  ·  %d gems  ·  from %s" % [Data.CROPS[key]["name"], " seed" if l["kind"] == "seed" else "",
					int(l["price"]), l["seller_name"]], Data.CROPS[key]["color"])
			var lid: String = r["id"]
			if mine:
				var tb := UI.button("Take back", func():
					_lock()
					Social.unlist(lid, func(okk: bool):
						if okk: _toast("Taken back")
						if panel_open == "Market": _open_market()), 120)
				tb.disabled = not Save.d.get("listings", {}).has(lid)
				row.add_child(tb)
			else:
				var b := UI.button("Buy", func():
					_lock()
					Social.buy(lid, func(what: String):
						if what != "":
							Sfx.play("pickup")
							_toast("Bought a %s" % what)
						else:
							_toast("Someone else got there first")
						if panel_open == "Market": _open_market()), 100)
				b.disabled = int(Save.d["gems"]) < int(l["price"])
				row.add_child(b))
	v.add_child(UI.section("Sell"))
	var any := false
	for kind in ["seed", "crop"]:
		var store: Dictionary = Save.d["seeds"] if kind == "seed" else Save.d["crops"]
		for key in store:
			if int(store[key]) <= 0 or not Data.CROPS.has(key): continue
			any = true
			var price := int(Data.CROPS[key]["price"]) * (2 if kind == "crop" else 1)
			var row := _row(v, "%s%s  ×%d" % [Data.CROPS[key]["name"], " seed" if kind == "seed" else "", int(store[key])], Data.CROPS[key]["color"])
			var kk: String = key; var kd: String = kind
			row.add_child(UI.button("List 1 for %d gems" % price, func():
				_lock()
				Social.sell(kd, kk, price, func(okk: bool):
					if okk: _toast("Listed. You'll be paid when it sells.")
					if panel_open == "Market": _open_market()), 200))
	if not any:
		v.add_child(UI.label("You have no seeds or crops to sell yet.", 14, UI.MUTED))
	# kin: one at a time leaves your farm and waits at the market until someone buys it
	v.add_child(UI.section("Sell a kin"))
	var roster: Array = Save.d["roster"]
	if roster.size() <= 1:
		v.add_child(UI.label("You need at least two kin to sell one.", 14, UI.MUTED))
	else:
		for rec in roster:
			var price := Social.kin_price(int(rec["level"]))
			var row := _row(v, "%s  ·  Lv %d %s" % [rec["name"], int(rec["level"]), Evo.form_name(rec)], Data.KIN[rec["species"]]["color"])
			var uid: String = rec["uid"]
			var nm: String = rec["name"]
			row.add_child(UI.button("Sell for %d gems" % price, func():
				_lock()
				Social.sell_kin(uid, price, func(okk: bool):
					if okk: _toast("%s is waiting at the market. You'll be paid when someone takes them home." % nm)
					if panel_open == "Market": _open_market()), 200))

# ---- notice board
func _open_notices() -> void:
	var v := _new_panel("Notice board", 600)
	var list := _loading(v)
	Social.list_notices(func(rows: Array):
		if not _clear(list): return
		if rows.is_empty():
			list.add_child(UI.label("The board is empty.", 14, UI.MUTED))
		for r in rows.slice(0, 10):
			var n: Dictionary = r["n"]
			var c := UI.card(UI.CARD, 8, 10)
			var cv := UI.vbox(2); c.add_child(cv)
			cv.add_child(UI.label(n["name"], 13, UI.GOLD))
			cv.add_child(UI.label(n["text"], 15))
			list.add_child(c))
	var row := UI.hbox(8)
	var inp := LineEdit.new(); inp.placeholder_text = "Pin a note: looking for a squad, selling Mindmint..."; inp.max_length = 140
	inp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(inp)
	row.add_child(UI.button("Pin it", func():
		if inp.text.strip_edges() == "": return
		_lock()
		Social.post_notice(inp.text, func(okk: bool):
			if okk: Sfx.play("pickup")
			if panel_open == "Notice board": _open_notices()), 100))
	v.add_child(row)

# ---- guilds
func _open_guilds() -> void:
	var v := _new_panel("Guild registry", 600)
	if not Social.guild.is_empty():
		v.add_child(UI.label("You're in %s." % String(Social.guild.get("name", "a guild")), 16, UI.GOLD))
		var hb := UI.hbox(8)
		var gid0 := Social.my_guild_id()
		hb.add_child(UI.button("Go to the guild isle", func(): Game.goto("town", {"mode": "guild", "gid": gid0}), 240))
		hb.add_child(UI.button("Leave the guild", func():
			_lock()
			Social.leave_guild(func():
				_toast("You left the guild")
				if panel_open == "Guild registry": _open_guilds()), 200))
		v.add_child(hb)
	else:
		v.add_child(UI.label("Guilds share an isle: every member gets a cottage, and you build projects together that help everyone on expeditions.", 14, UI.MUTED))
		var row := UI.hbox(8)
		var nm := LineEdit.new(); nm.placeholder_text = "Guild name"; nm.max_length = 24; nm.custom_minimum_size.x = 200
		var mo := LineEdit.new(); mo.placeholder_text = "Motto (optional)"; mo.max_length = 60; mo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nm); row.add_child(mo)
		row.add_child(UI.button("Found it", func():
			if nm.text.strip_edges().length() < 3:
				_toast("Pick a name of at least 3 letters")
				return
			_lock()
			var gname := Social.say_of(nm.text, "Guild", 24)
			Social.create_guild(gname, mo.text, func(okk: bool):
				if okk:
					Sfx.play("unlock")
					_toast("%s is founded" % gname)
				if panel_open == "Guild registry": _open_guilds()), 120))
		v.add_child(row)
	v.add_child(UI.section("Guilds"))
	var list := _loading(v)
	Social.list_guilds(func(rows: Array):
		if not _clear(list): return
		if rows.is_empty():
			list.add_child(UI.label("No guilds yet. Found the first one.", 14, UI.MUTED))
		for r in rows.slice(0, 10):
			var g: Dictionary = r["g"]
			var row := _row(list, g["name"] + (("  ·  " + g["motto"]) if g["motto"] != "" else ""))
			var rid: String = r["id"]
			row.add_child(UI.button("Visit", func(): Game.goto("town", {"mode": "guild", "gid": rid}), 90))
			if Social.guild.is_empty():
				row.add_child(UI.button("Join", func():
					_lock()
					Social.join_guild(rid, func(_okk):
						Sfx.play("unlock")
						_toast("Welcome to %s" % g["name"])
						if panel_open == "Guild registry": _open_guilds()), 90)))

# ---- guild projects
func _open_project(k: String) -> void:
	var pd: Dictionary = Social.PROJECTS[k]
	var title := String(pd["name"])
	var v := _new_panel(title, 520)
	var mine: bool = gid != "" and gid == Social.my_guild_id()
	v.add_child(UI.label("When it's built, everyone in the guild gets: " + String(pd["perk"]), 15))
	var body := _loading(v)
	Social.load_progress(gid, guild_doc, func(prog: Dictionary):
		if not is_inside_tree() or panel_open != title or not _clear(body): return
		var total := int(prog.get(k, 0))
		var goal := int(pd["goal"])
		body.add_child(UI.label("%d of %d gems put in" % [mini(total, goal), goal], 15, UI.GOLD))
		body.add_child(UI.bar(float(total) / goal, UI.GOLD, 460, 10))
		if total >= goal:
			body.add_child(UI.label("Built. Its perk is active for every member.", 15, UI.GOOD))
			return
		if not mine:
			body.add_child(UI.label("Only members can help build this.", 14, UI.MUTED))
			return
		var hb := UI.hbox(8)
		for amt in [10, 50, 150]:
			var a: int = mini(amt, goal - total)
			var b := UI.button("Put in %d gems" % a, func():
				_lock()
				Social.contribute(k, a, func(okk: bool):
					if okk:
						Sfx.play("build")
						fx.burst(Vector3(ppos.x, 1.0, ppos.z - 1.5), UI.GOLD, 16, 3.0)
						_toast("Thanks for helping")
						_refresh_projects()
					if panel_open == title: _open_project(k)), 150)
			b.disabled = int(Save.d["gems"]) < a or a <= 0
			hb.add_child(b)
		body.add_child(hb)
		body.add_child(UI.label("You have %d gems." % int(Save.d["gems"]), 13, UI.MUTED)))

## Test-only: a guild's worth of made-up members so the isle can be looked at offline.
func _fake_members() -> Array:
	var out := []
	var sp: Array = Data.common_kin()
	var rng := RandomNumberGenerator.new(); rng.seed = 3
	for i in 7:
		var rec := Save.new_kin(sp[i % sp.size()])
		rec["level"] = rng.randi_range(2, 18)
		Evo.simulate(rec, rng)
		out.append({"id": "fake%d" % i, "d": Social.clean_island({"name": ["Wren", "Ollie", "Mara", "Tobin", "Ivy", "Juno", "Pip"][i], "roster": [rec], "active": rec["uid"], "buildings": ["cottage"]})})
	return out
