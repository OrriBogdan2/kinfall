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
var top_chips: HBoxContainer
var prompt_box: PanelContainer
var prompt_lbl: Label
var hint: Label
var player: Node3D
var ppos := Vector3.ZERO
var pvel := Vector3.ZERO
var spawn := ""             # set when coming back out of a building: start at its door
var py := 0.0               # height of a jump
var farm_t := 0.0
var pvy := 0.0
const JUMP_V := 8.5
const GRAV := 26.0
var pface := 0.0
var walk_ph := 0.0
var house_node: Node3D
var rack_node: Node3D
var rack_pick := ""
var whistle_cd := 0.0
var talk_cd := 0.0          # kin take turns talking: one ambient line at a time
var whistle_player: AudioStreamPlayer
var kins: Array = []           # {rec, node, pos, vel, goal, t, emote, emote_t, hop}
var spots := {}                # name -> Vector3
var plots: Array = []          # nodes, index matches Save plots
var interact := {}
var panel_open := ""
var chat_log: Array = []       # [{role, content}]
var chat_kin: Dictionary = {}
var chat_input: LineEdit
var chat_busy := false
var chat_offline_noted := false
var emote_labels: Array = []
var pet_done := {}

var lots := {}                 # building id -> {node, built}
var visit: Dictionary = {}     # when visiting someone: their island snapshot (see Social.publish_profile)
var visit_id := ""
var petted := {}
var hecon: HomeEcon = null       # the armory, feeders, starving, graveyard and Soul Shrine (home_econ.gd)

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
var p_anim: HunterAnim = null
var lamps: Array = []           # OmniLight3D
var day_t := 0.3                # 0..1, 0.25 is morning, 0.5 noon, 0.75 dusk
var rain: CPUParticles3D
var raining := false
var rain_k := 0.0
var weather_t := 40.0

func _ready() -> void:
	if Game.modding(): Game.apply_mod()
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
	# the Challenge House comes with the farm
	if visit.is_empty() and not Save.d.get("buildings", []).has("board"):
		Save.d["buildings"].append("board")
	# so does Old Pell's Ransom House
	if visit.is_empty() and not Save.d.get("buildings", []).has("ransom"):
		Save.d["buildings"].append("ransom")
	hecon = HomeEcon.new(self)
	if visit.is_empty():
		Econ.ensure()
		_econ_tests(dbg)
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
	spots["rack"] = Vector3(34.5, 0, 40.5)      # the glider rack, beside the portal
	world.set_block_rect(34, 40, 34, 40)
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
	if "--print-home" in OS.get_cmdline_user_args():
		for z in range(16, 46):
			var line := "%2d " % z
			for x in range(18, 60):
				var i := world.idx(x, z)
				line += "." if world.kind[i] == World.T_VOID else ("#" if world.kind[i] == World.T_BLOCK else ("o" if world.paint.has(i) else "g"))
			print(line)
		get_tree().quit()
	world.build_meshes()
	fx = Fx.new(); add_child(fx)
	cam = CamRig.new(); add_child(cam)
	cam.zoom_to = 0.8; cam.zoom = 0.8; cam.lead = 0.2
	if "--home-wide" in OS.get_cmdline_user_args():
		cam.zoom_to = 2.6; cam.zoom = 2.6     # test: the whole farm in one shot
	var house := Models.house(); house.position = spots["house"]; add_child(house)
	house_node = house
	var pot := Models.cauldron(); pot.position = spots["pot"]; add_child(pot)
	var stall := Models.stall(); stall.position = spots["stall"]; stall.rotation.y = PI * 0.5; add_child(stall)
	var portal := Models.portal(UI.TEAL); portal.position = spots["portal"]; add_child(portal)
	if visit.is_empty():
		rack_node = _glider_rack()
		rack_node.position = spots["rack"]
		add_child(rack_node)
	portal.get_node("Disc").visible = true
	(portal.get_node("Beam") as CPUParticles3D).emitting = true
	var drng := RandomNumberGenerator.new(); drng.seed = 77
	var pond := Models.pond(1.9, 1.5); pond.position = Vector3(33.5, 0, 37.5); add_child(pond)
	for fp in [[Vector3(45.4, 0, 29.4), 0.0, 5.0], [Vector3(45.4, 0, 37.6), 0.0, 5.0], [Vector3(47.8, 0, 33.5), PI / 2, 8.0], [Vector3(42.4, 0, 35.6), PI / 2, 4.0]]:
		var f := Models.fence(fp[2]); f.position = fp[0]; f.rotation.y = fp[1]; add_child(f)
	for lp in [Vector3(36.2, 0, 30.0), Vector3(39.6, 0, 35.5), Vector3(36.4, 0, 35.6), Vector3(41.0, 0, 30.0), Vector3(26.0, 0, 29.2), Vector3(51.2, 0, 36.6)]:
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
	player = Models.hunter(Data.class_of_save(), Data.TEAM_COLORS[0], _weapon(), "", Save.d.get("look", {}))
	add_child(player)
	ppos = Vector3(38.0, 0, 34.5)
	if spawn == "house":
		ppos = spots["house"] + Vector3(0, 0, 2.6)
	elif lots.has(spawn):
		ppos = lots[spawn]["door"]
	player.position = ppos
	cam.snap(ppos)
	if "--expedition-test" in dbg:
		get_tree().create_timer(0.5).timeout.connect(_open_expedition)
	for a in dbg:
		if a.begins_with("--rack-test"):
			# test: open the glider rack (optionally on a skin: --rack-test=ember)
			var pick := a.substr(12) if a.length() > 12 else ""
			get_tree().create_timer(0.5).timeout.connect(func():
				if pick != "": rack_pick = pick
				_open_rack())
	if "--crowd-test" in dbg:
		# test: pile every kin onto one spot next to you, then watch them sort themselves out
		get_tree().create_timer(0.3).timeout.connect(func():
			for k in kins:
				k.erase("indoors"); (k["node"] as Node3D).visible = true
				k["pos"] = ppos + Vector3(1.0, 0, 0.5); (k["node"] as Node3D).position = k["pos"]
				k["hi_cd"] = 0.0
			var t := 0.0
			var tick := func(): pass
			for step in [1.0, 3.0, 6.0]:
				get_tree().create_timer(step).timeout.connect(func():
					var md := 99.0; var talking := 0
					for i in kins.size():
						if float(kins[i].get("say_t", 0.0)) > 0.0: talking += 1
						for j in range(i + 1, kins.size()):
							md = minf(md, Vector2(kins[i]["pos"].x - kins[j]["pos"].x, kins[i]["pos"].z - kins[j]["pos"].z).length())
					print("CROWD t=%.0f kin=%d min_gap=%.2f talking=%d" % [step, kins.size(), md, talking])))
	if "--whistle-test" in dbg:
		# test: every kin but one is indoors, then you whistle
		get_tree().create_timer(0.3).timeout.connect(func():
			for j in kins.size():
				if j == 0: continue
				kins[j]["indoors"] = 999.0
				(kins[j]["node"] as Node3D).visible = false
			get_tree().create_timer(0.6).timeout.connect(_whistle))
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
		if a.begins_with("--kin-needs="):
			var nv := a.substr(12).split(",")
			var nk := Save.active_kin()
			Care.ensure(nk)
			for i in mini(4, nv.size()): nk["needs"][Care.NEEDS[i]] = float(nv[i])
			nk["needs_t"] = Time.get_unix_time_from_system()
			get_tree().create_timer(0.3).timeout.connect(func():
				var ke := _kin_entry(nk)
				if not ke.is_empty():
					ke["pos"] = ppos + Vector3(1.2, 0, -0.4); (ke["node"] as Node3D).position = ke["pos"]; ke["hold_t"] = 30.0)
		if a == "--care-test":
			# test: feed, brush, bath, nap and dress in a row
			Save.d["items"]["kibble"] = 2; Save.d["crops"]["sunroot"] = 1
			Save.d["accs"] = ["scarf"]
			var ck := Save.active_kin()
			get_tree().create_timer(0.6).timeout.connect(func(): _care_feed(ck, "kibble"))
			get_tree().create_timer(4.0).timeout.connect(func(): _care_feed(ck, "sunroot"))
			get_tree().create_timer(7.5).timeout.connect(func(): _care_brush(ck))
			get_tree().create_timer(10.5).timeout.connect(func(): _set_acc(ck, "scarf"))
			get_tree().create_timer(11.5).timeout.connect(func(): _care_bath(ck))
			get_tree().create_timer(19.0).timeout.connect(func(): _care_nap(ck); print("CARETEST ", ck["needs"], " known ", ck["known"], " items ", Save.d["items"]))
			get_tree().create_timer(22.0).timeout.connect(func(): print("CARETEST2 nap ", _kin_entry(ck).get("nap_t", 0), " acc ", ck.get("acc", "")); get_tree().quit())
		if a == "--hatch-nest":
			# test: two kin with an egg ready; stand by the nest and hatch it
			var ka := Save.active_kin()
			var kb := Save.new_kin("puddlet", "Drip")
			kb["level"] = 6; kb["trust"] = 60.0
			Save.d["roster"].append(kb)
			Save.d["egg"] = {"a": ka["uid"], "b": kb["uid"], "m": 0, "t": 0.0}
			_spawn_kin()
			_refresh_nest()
			ppos = NEST_AT + Vector3(0, 0, 2.0)
			get_tree().create_timer(1.0).timeout.connect(_hatch_nest_egg)
		if a.begins_with("--drill="):
			var dstat := a.substr(8)
			get_tree().create_timer(0.4).timeout.connect(func(): _start_drill(Save.active_kin(), dstat))
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
		if a == "--ransom-test":
			# test: go down on an expedition with two kin; one is left unclaimed, a rival takes the other,
			# and a rival wants back a kin you took from them
			while Save.d["roster"].size() < 4:
				Save.d["roster"].append(Save.new_kin(Data.KIN.keys()[Save.d["roster"].size() % Data.KIN.size()]))
			var ka: Dictionary = Save.d["roster"][1]
			var kb: Dictionary = Save.d["roster"][2]
			var kc: Dictionary = Save.d["roster"][3]
			kc["lost_from"] = "Moss"
			Save.d["gems"] = maxi(int(Save.d["gems"]), 400)
			var res := Game.apply_result({"extracted": false, "why": "knocked out", "tier": 1, "rivals": ["Vexa", "Moss", "Tarn"],
				"kin_runs": [{"uid": ka["uid"], "events": [], "trust": ka["trust"], "stats": {}}, {"uid": kb["uid"], "events": [], "trust": kb["trust"], "stats": {}}],
				"lost_kin": [{"uid": ka["uid"], "fate": "ransom", "holder": ""}, {"uid": kb["uid"], "fate": "rival", "holder": "Vexa"}]})
			print("RANSOM lost_news=%d news=%s lost=%d offers=%d" % [res["lost_news"].size(), str(res["ransom_news"]), Save.d["lost_kin"].size(), Save.d["offers"].size()])
			if Save.d["offers"].is_empty():
				Save.d["offers"].append({"uid": kc["uid"], "from": "Moss", "gems": 90, "m": 0})
		if a.begins_with("--open="):
			var which := a.substr(7)
			get_tree().create_timer(0.2).timeout.connect(func():
				if which == "loadout": _open_loadout()
				elif which == "expedition": _open_expedition()
				elif which == "kin": _open_kin(Save.active_kin())
				elif which == "shop": _open_shop()
				elif which == "challenges": _open_challenges()
				elif which.begins_with("ransom"):
					if ":" in which: ransom_tab = which.split(":")[1]
					_open_ransom()
				elif which == "kitchen": _open_kitchen()
				elif which == "plot": _open_plot("plots", 0)
				elif which == "chat":
					var ak := Save.active_kin()
					var ke := _kin_entry(ak)
					if not ke.is_empty(): ppos = ke["pos"] + Vector3(1.5, 0, 1.0); cam.snap(ppos)
					_open_chat(ak)
					chat_input.text = "hi, how are you?"
					_send_chat()
				elif which == "fetch":
					var ke := _kin_entry(Save.active_kin())
					if not ke.is_empty(): ppos = ke["pos"] + Vector3(1.5, 0, 1.0); cam.snap(ppos); _play_with_kin(ke))
		if a.begins_with("--home-at="):
			var xy := a.substr(10).split(",")
			ppos = Vector3(float(xy[0]), 0, float(xy[1])); player.position = ppos; cam.snap(ppos)
	_spawn_kin()
	_setup_care()
	if visit.is_empty():
		hecon.build()
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
	_refresh_day1()
	if visit.is_empty():
		hecon.show_away()
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
	# two loose planks side by side (stacked in the same spot they flickered through each other)
	var along := Vector3(1, 0, 0) if ax["horiz"] else Vector3(0, 0, 1)
	var outward := signf((spots_l[spots_l.size() - 1] as Vector3 - p0).dot(along)) if spots_l.size() > 1 else 1.0
	for i in 2:
		var pl := Models.plank(rng, ax["width"] - 0.02)
		pl.position = p0 + along * outward * (i * 0.5) + Vector3(0, 0.07 - i * 0.012, 0)
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
		var pl := Models.plank(rng, ax["width"] - 0.02)
		pl.position = p + Vector3(0, 0.03, 0)
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
	var e := Look.environment({"top": Color("2a4a8a"), "mid": Color("6a8ad0"), "horizon": Color("ffd2a8"), "below": Color("3a3a6a"),
		"ambient": Color("c4cbe6"), "ambient_energy": 0.5, "fog": Color("8a96c8"), "fog_height": -4.0, "stars": 0.0})
	env.environment = e
	add_child(env)
	env_res = e
	var sun := Look.lights(self, Color("ffe9cf"), 0.95, Vector3(-50, -30, 0), 45.0)
	sun_l = sun
	# you always arrive in the morning; the day runs on from there
	day_t = 0.3
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
		# somewhere open, not wedged against a building and not on top of another kin
		var taken: Array = kins.map(func(o): return o["pos"])
		taken.append(ppos)
		var at := world.free_spot_near(world.random_ground(isl), taken, 1.3)
		n.position = at
		var lbl := Label3D.new()
		lbl.font = UI.big; lbl.font_size = 48; lbl.pixel_size = 0.013; lbl.outline_size = 14
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED; lbl.no_depth_test = true
		lbl.position.y = 1.25; lbl.visible = false
		n.add_child(lbl)
		var kd := {"rec": rec, "node": n, "pos": at, "vel": Vector3.ZERO, "goal": Vector3.INF, "t": randf() * 3.0, "emote": lbl, "emote_t": 0.0, "hop": randf() * 6.0, "pers": _personality(rec)}
		var ri2: int = _d()["roster"].find(rec)
		if isl == 0 and ri2 >= 0 and ri2 < 6:
			kd["bed"] = Vector3(32.9 + (ri2 % 3) * 1.6, 0, 27.2 + (ri2 / 3) * 1.6)
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
	pass     # tracks join the music list in the house quietly; no popup every time a new one plays

func _update_sky(d: float) -> void:
	_update_music(d)
	day_t = fmod(day_t + d / DAY_LEN, 1.0)
	var sun_h := sin((day_t - 0.25) * TAU)            # 1 at noon, -1 at midnight
	var light := clampf(sun_h * 1.6 + 0.6, 0.0, 1.0)   # how much daylight (night is short and moonlit)
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
	sun_l.light_energy = lerpf(0.4, 0.9, light) * (1.0 - rain_k * 0.35)
	sun_l.rotation_degrees = Vector3(lerpf(-28.0, -62.0, maxf(sun_h, 0.0)), -30.0 + day_t * 80.0, 0)
	env_res.ambient_light_color = Color("c4cbe6").lerp(Color("8090c8"), 1.0 - light).lerp(Color("ffc9a8"), dusk * 0.35)
	env_res.ambient_light_energy = lerpf(0.36, 0.45, light) * (1.0 - rain_k * 0.2)
	env_res.adjustment_enabled = true
	env_res.adjustment_brightness = lerpf(0.92, 1.0, light) * (1.0 - rain_k * 0.08)
	env_res.adjustment_saturation = lerpf(0.95, 1.14, light) * (1.0 - rain_k * 0.15) * (1.65 if Look.full_renderer() else 1.0)
	Look.night(env_res, (1.0 - light) * 0.75)
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
	_update_hover()
	_move_player(d)
	_move_kin(d)
	_care_tick(d)
	if hecon: hecon.tick(d)
	_update_bubbles(d)
	_train_process(d)
	cam.follow(ppos, d, panel_open == "" and train.is_empty())
	_find_interact()
	if panel_open == "" and not building_now and not Overlay.is_open() and not chat_open and train.is_empty() and not interact.is_empty():
		if Input.is_action_just_pressed("interact"):
			_use(interact)
		elif interact["kind"] == "kin" and visit.is_empty():
			if Input.is_action_just_pressed("play"): _play_with_kin(interact["k"])
			elif Input.is_action_just_pressed("talk"): _open_chat(interact["k"]["rec"])
			elif Input.is_action_just_pressed("details"): _open_kin(interact["k"]["rec"])

func _move_player(d: float) -> void:
	var mv := Vector2.ZERO
	if panel_open == "" and not Overlay.is_open() and not chat_open and train.is_empty():
		mv = Vector2(Input.get_axis("left", "right"), Input.get_axis("up", "down"))
		if mv.length() > 1.0: mv = mv.normalized()
	var hv := Vector2(pvel.x, pvel.z)
	var air := py > 0.001 or pvy > 0.0
	hv += (mv * SPEED - hv) * (1.0 - exp(-(14.0 if not air else 6.0) * d))
	# the island edge is an invisible wall: walking and jumping both stop at it
	var p0 := ppos
	var nx := ppos.x + hv.x * d
	if world.occupy(nx, ppos.z, 0.38, 0.0, true) == 0.0: ppos.x = nx
	else: hv.x = 0.0
	var nz := ppos.z + hv.y * d
	if world.occupy(ppos.x, nz, 0.38, 0.0, true) == 0.0: ppos.z = nz
	else: hv.y = 0.0
	pvel = Vector3(hv.x, 0, hv.y)
	# caught on a corner: slip around it. Boxed in on every side: step out to open ground.
	if mv.length() > 0.3 and Vector2(ppos.x - p0.x, ppos.z - p0.z).length() < SPEED * d * 0.3:
		var dn := mv.normalized()
		var slid := false
		for side in [Vector2(-dn.y, dn.x), Vector2(dn.y, -dn.x)]:
			var t: Vector2 = Vector2(ppos.x, ppos.z) + (side * 0.8 + dn * 0.4) * SPEED * d
			if world.occupy(t.x, t.y, 0.38, 0.0, true) == 0.0:
				ppos.x = t.x; ppos.z = t.y; slid = true
				break
		var boxed := not slid
		if boxed:
			for i in 8:
				var a2 := TAU * i / 8.0
				if world.occupy(ppos.x + cos(a2) * 0.2, ppos.z + sin(a2) * 0.2, 0.38, 0.0, true) == 0.0:
					boxed = false; break
		wedge_t = wedge_t + d if boxed else 0.0
		if wedge_t > 0.8:
			wedge_t = 0.0
			unstick()
	# jumping, just for fun
	if panel_open == "" and not Overlay.is_open() and not chat_open and train.is_empty() and not air and Input.is_action_just_pressed("jump"):
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
	if p_anim == null or p_anim.model != player:
		p_anim = HunterAnim.new(player)
	p_anim.update(d, {"vel": Vector3(hv.x, pvy if py > 0.0 else 0.0, hv.y), "face": pface, "grounded": py <= 0.0, "fired": 99.0})
	if p_anim.stepped:
		Sfx.step(null, -20.0)

func _move_kin(d: float) -> void:
	whistle_cd = maxf(0.0, whistle_cd - d)
	talk_cd = maxf(0.0, talk_cd - d)
	_separate_kin(d)
	for k in kins:
		if k.get("busy", false):
			continue
		if k.has("indoors"):
			# inside the house: out of sight until it fancies coming out (or hears you whistle)
			k["indoors"] = float(k["indoors"]) - d
			if float(k["indoors"]) <= 0.0 and not k.has("exiting"):
				_kin_exit_house(k, false)
			continue
		if k.has("leap"):
			_leap_step(k, d)
			continue
		k["t"] -= d
		if k.has("called_t"):
			# you whistled: drop everything and come to you
			k["called_t"] = float(k["called_t"]) - d
			var slot: Vector3 = k.get("call_slot", Vector3.ZERO)
			k["goal"] = ppos + slot
			k.erase("chase"); k.erase("task"); k.erase("going_in")
			var to_me := Vector2(ppos.x + slot.x - k["pos"].x, ppos.z + slot.z - k["pos"].z).length()
			if world.island_of(k["pos"].x, k["pos"].z) != world.island_of(ppos.x, ppos.z) and world.island_of(ppos.x, ppos.z) >= 0:
				_start_leap(k, ppos + slot)
				continue
			if to_me < 0.6 or float(k["called_t"]) <= 0.0:
				var arrived := to_me < 0.6
				k.erase("called_t"); k.erase("call_slot")
				if arrived:
					k["hold_t"] = 1.4; k["joy_t"] = 0.9; k["t"] = randf_range(2.5, 4.0)
					_emote(k, "♥" if float(k["rec"]["trust"]) > 55.0 else "♪")
					Sfx.play("kin_happy", k["pos"], -10.0, 0.15)
		var pos: Vector3 = k["pos"]
		var rec: Dictionary = k["rec"]
		var trust := float(rec["trust"])
		if k.get("nap_go", false):
			k["nap_go_t"] = float(k.get("nap_go_t", 15.0)) - d
			if float(k["nap_go_t"]) <= 0.0: k.erase("nap_go"); k.erase("nap_go_t")
			elif k.has("bed"): k["goal"] = k["bed"]
		var locked: bool = float(k.get("nap_t", 0.0)) > 0.0 or k.has("bath") or k.get("nap_go", false)
		if locked:
			k.erase("chase"); k.erase("task")
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
				if pd["crop"] != "" and (float(pd.get("wt", 0.0)) <= 0.0 or int(pd.get("wet", 2)) < 2):
					_water(tk[0], tk[1], "kin")
					_emote(k, "♪")
					rec["trust"] = minf(100.0, float(rec["trust"]) + (0.07 if int(rec.get("pining", 0)) > 0 else 0.2))
				k["t"] = randf_range(1.0, 2.0)
		elif k["t"] <= 0.0 and not locked and rec.get("farmhand", false) and visit.is_empty() and (k["farm_t"] if k.has("farm_t") else 0.0) <= 0.0 and _dry_plot() != []:
			k["task"] = _dry_plot()
			k["task_t"] = 15.0
			k["farm_t"] = 6.0
		if k.has("farm_t"): k["farm_t"] = float(k["farm_t"]) - d
		var pers: Dictionary = k.get("pers", {})
		if k["t"] <= 0.0 and not locked and not k.has("chase") and not k.has("task") and not k.has("fetch"):
			k["t"] = randf_range(2.0, 5.0) * float(pers.get("rest", 1.0))
			var night := sin((day_t - 0.25) * TAU) < -0.2
			var friends: Array = kins.filter(func(o): return o != k and not o.get("busy", false) and world.island_of(o["pos"].x, o["pos"].z) == here)
			k.erase("stare")
			if _care_goal(k):
				pass
			elif night and randf() < 0.6:
				if here == world.island_of(spots["house"].x, spots["house"].z) and randf() < 0.45:
					# some sleep indoors
					k["going_in"] = true
					k["goal"] = _house_door()
				else:
					# at night they head for bed and doze
					k["goal"] = k.get("bed", world.random_ground(maxi(here, 0)))
				if randf() < 0.5: _emote(k, "z")
			elif not night and randf() < 0.05 and here == world.island_of(spots["house"].x, spots["house"].z):
				# pops inside for a nap now and then
				k["going_in"] = true
				k["goal"] = _house_door()
			elif friends.size() > 0 and randf() < float(pers.get("social", 0.22)):
				var f: Dictionary = friends[randi() % friends.size()]
				k["chase"] = f; k["chase_t"] = 4.0
				_emote(k, "★")
			elif randf() < float(pers.get("cling", 0.25)) + trust / 300.0 and world.island_of(ppos.x, ppos.z) == here:
				# kin that trust you like to be near you, each in its own spot around you
				k["goal"] = _seat(k, ppos, 1.5)
			elif randf() < 0.75 - float(pers.get("roam", 0.5)) * 0.5 and _haunt(k, here) != Vector3.INF:
				# everyone has a favourite corner of the farm they drift back to
				k["goal"] = _haunt(k, here) + Vector3(randf_range(-1.6, 1.6), 0, randf_range(-1.6, 1.6))
			else:
				k["goal"] = world.random_ground(maxi(here, 0))
			if randf() < 0.3 * float(pers.get("chatty", 1.0)):
				_emote(k, "♥" if trust > 65.0 else ("?" if trust < 30.0 else "★"))
		if k.has("fetch"):
			_fetch_step(k, d)
		_care_step(k, d)
		var hold := float(k.get("hold_t", 0.0))
		if hold > 0.0:
			# being petted or talked to: it stays put and looks at you
			k["hold_t"] = hold - d
			k["goal"] = pos
		var wish := Vector2.ZERO
		var goal: Vector3 = k["goal"]
		if goal != Vector3.INF:
			var to := Vector2(goal.x - pos.x, goal.z - pos.z)
			if to.length() > 0.4:
				wish = to.normalized() * (4.4 if (k.has("fetch") or k.has("called_t")) else (3.6 if k.has("chase") else 2.4)) * _care_speed(rec) * float(pers.get("speed", 1.0))
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
		if k.get("going_in", false) and Vector2(pos.x - _house_door().x, pos.z - _house_door().z).length() < 0.6:
			k.erase("going_in")
			var night_now := sin((day_t - 0.25) * TAU) < -0.2
			k["indoors"] = randf_range(70.0, 140.0) if night_now else randf_range(20.0, 55.0)
			n.visible = false
			Sfx.play("thump", pos, -16.0, 0.1, 1.3)
			continue
		var face := atan2(-hv.x, -hv.y) if hv.length() > 0.2 else atan2(-(ppos.x - pos.x), -(ppos.z - pos.z))
		n.rotation.y = lerp_angle(n.rotation.y, face, minf(1.0, d * 8.0))
		k["hop"] += d * (float(pers.get("hop_f", 9.0)) if hv.length() > 0.3 else 2.5)
		var joy := float(k.get("joy_t", 0.0))
		if joy > 0.0:
			# a happy little bounce
			k["joy_t"] = joy - d
			k["hop"] += d * 10.0
		n.get_node("Body").position.y = absf(sin(k["hop"])) * (0.26 if joy > 0.0 else (float(pers.get("hop_a", 0.14)) if hv.length() > 0.3 else 0.03))
		_quirk(k, n, hv.length() > 0.3, d)
		n.set_meta("happy", joy > 0.0)
		if k.has("say"):
			k["say_t"] = float(k.get("say_t", 0.0)) - d
			(k["say"] as Label3D).visible = k["say_t"] > 0.0
		n.scale = Vector3.ONE * (1.05 if rec["uid"] == _d().get("active", "") else 0.9) * float(n.get_meta("evo_scale", 1.0))
		if k["emote_t"] > 0.0:
			k["emote_t"] -= d
			var lbl: Label3D = k["emote"]
			lbl.visible = k["emote_t"] > 0.0
			lbl.position.y = 1.15 + (1.6 - k["emote_t"]) * 0.2

# ---- the glider rack: skins for your glider, each with its own trail and sounds
func _glider_rack() -> Node3D:
	var n := Node3D.new()
	var wood := Models.toon(Color("8a6242")); var dark := Models.toon(Color("4e3424"))
	for sx in [-1.0, 1.0]:
		Models.part(n, Models.cyl(0.06, 0.07, 1.9, 8), wood, Vector3(0.75 * sx, 0.95, 0))
	Models.part(n, Models.cyl(0.05, 0.05, 1.7, 8), dark, Vector3(0, 1.85, 0), Vector3.ONE, Vector3(0, 0, PI / 2))
	var can := MeshInstance3D.new(); can.name = "Canopy"
	can.mesh = Gliders.mesh(Gliders.equipped(), Data.TEAM_COLORS[0], UI.ACCENT)
	can.material_override = Models.vtoon_outlined()
	can.position = Vector3(0, 1.75, 0); can.scale = Vector3.ONE * 0.75; can.rotation = Vector3(-0.35, 0, 0)
	n.add_child(can)
	var sign := Label3D.new(); sign.text = "Gliders"
	sign.font = UI.big; sign.font_size = 40; sign.pixel_size = 0.012; sign.outline_size = 10
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED; sign.position = Vector3(0, 2.35, 0)
	n.add_child(sign)
	return n

func _open_rack() -> void:
	if rack_pick == "": rack_pick = Gliders.equipped()
	var v := _new_panel("Glider skins", 640)
	# a preview of the picked skin, open and turning, trail and all
	var svc := SubViewportContainer.new(); svc.stretch = true; svc.custom_minimum_size = Vector2(580, 170)
	var vp := SubViewport.new(); vp.own_world_3d = true; vp.transparent_bg = true; vp.msaa_3d = Viewport.MSAA_2X
	svc.add_child(vp)
	var w3 := Node3D.new(); vp.add_child(w3)
	Look.lights(w3, Color("fff1dc"), 1.0)
	var holder := Node3D.new(); w3.add_child(holder)
	var can := MeshInstance3D.new()
	can.mesh = Gliders.mesh(rack_pick, Data.TEAM_COLORS[0], UI.ACCENT)
	can.material_override = Models.vtoon_outlined()
	holder.add_child(can)
	var tr := Gliders.trail(rack_pick, Data.TEAM_COLORS[0], UI.ACCENT)
	if tr: tr.position = Vector3(0, -0.05, 0.3); tr.local_coords = true; tr.direction = Vector3(0, -0.2, 1); holder.add_child(tr)
	var pc := Camera3D.new(); pc.fov = 42
	pc.transform = Transform3D(Basis(), Vector3(0, 2.35, 2.05)).looking_at(Vector3(0, -0.15, 0.05), Vector3.UP)
	w3.add_child(pc)
	holder.set_meta("spin", true)
	svc.set_process(true)
	var spin := func(): if is_instance_valid(holder): holder.rotation.y = sin(Time.get_ticks_msec() / 1400.0) * 0.6
	svc.draw.connect(spin)
	var ticker := Timer.new(); ticker.wait_time = 0.033; ticker.autostart = true; svc.add_child(ticker)
	ticker.timeout.connect(func(): spin.call(); svc.queue_redraw())
	v.add_child(svc)
	var g := Gliders.get_skin(rack_pick)
	var info := UI.hbox(10)
	var it := UI.vbox(2); it.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	it.add_child(UI.title(String(g["name"]), 26))
	var d := UI.label(String(g["desc"]), 14, UI.MUTED); d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	it.add_child(d)
	info.add_child(it)
	info.add_child(UI.button("Hear it", func(): _rack_sound(rack_pick), 110))
	var own := Gliders.owned(rack_pick)
	if own:
		if Gliders.equipped() == rack_pick:
			var eq := UI.label("Equipped", 15, UI.GOOD, UI.semi); eq.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			info.add_child(eq)
		else:
			info.add_child(UI.primary("Equip", func(): _rack_equip(rack_pick), 120))
	elif g.has("unlock"):
		var p := String(g["unlock"]).split(":")
		var lk := UI.label("Earned at %s %s  (%d/%s)" % [p[1], p[0], Progress.stat(p[0]), p[1]], 14, Color("ffd79a"))
		lk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		info.add_child(lk)
	else:
		var cost := int(g["cost"])
		var buy := UI.primary("Buy  ·  %d gems" % cost, func(): _rack_buy(rack_pick), 170)
		buy.disabled = int(Save.d["gems"]) < cost
		info.add_child(buy)
	v.add_child(info)
	v.add_child(UI.section("All gliders"))
	var grid := GridContainer.new(); grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8); grid.add_theme_constant_override("v_separation", 8)
	for sk in Gliders.LIST:
		var sid: String = sk["id"]
		var label := String(sk["name"])
		if Gliders.equipped() == sid: label = "✓ " + label
		var b := UI.choice(label, sid == rack_pick, func(): rack_pick = sid; _rack_sound(sid); _open_rack(), 136)
		if not Gliders.owned(sid):
			b.modulate = Color(1, 1, 1, 0.62)
			b.tooltip_text = ("%d gems" % int(sk["cost"])) if not sk.has("unlock") else "Earned, not bought"
		b.clip_text = true
		grid.add_child(b)
	v.add_child(grid)

func _rack_sound(id: String) -> void:
	var ap := AudioStreamPlayer.new()
	ap.stream = Gliders.sound(id, "open")
	ap.bus = "SFX"
	ap.volume_db = -3.0
	add_child(ap)
	ap.play()
	ap.finished.connect(ap.queue_free)

func _rack_buy(id: String) -> void:
	var cost := int(Gliders.get_skin(id).get("cost", 0))
	if int(Save.d["gems"]) < cost:
		return
	Save.d["gems"] = int(Save.d["gems"]) - cost
	if not Save.d.has("gliders"): Save.d["gliders"] = []
	Save.d["gliders"].append(id)
	Sfx.play("unlock")
	_toast("%s unlocked!" % Gliders.get_skin(id)["name"])
	_rack_equip(id)

func _rack_equip(id: String) -> void:
	if not Save.d.has("look"): Save.d["look"] = Models.default_look()
	Save.d["look"]["glider"] = id
	Save.save_game()
	_rack_sound(id)
	if is_instance_valid(rack_node):
		var can := rack_node.get_node_or_null("Canopy") as MeshInstance3D
		if can: can.mesh = Gliders.mesh(id, Data.TEAM_COLORS[0], UI.ACCENT)
	_refresh_top()
	_open_rack()

# ---- the whistle: press H at home and your kin come running, even from inside the house
func _house_door() -> Vector3:
	return spots["house"] + Vector3(0, 0, 2.1)

func _whistle() -> void:
	if whistle_cd > 0.0:
		return
	whistle_cd = 1.6
	_whistle_sound()
	_whistle_ring()
	var my_isle := world.island_of(ppos.x, ppos.z)
	var n := kins.size()
	var inside: Array = []
	var i := 0
	for k in kins:
		var slot := Vector3(cos(TAU * i / maxf(1.0, n) + 0.4), 0, sin(TAU * i / maxf(1.0, n) + 0.4)) * (1.3 + 0.15 * n)
		i += 1
		if k.get("busy", false) or k.has("fetch") or k.has("bath"):
			continue
		var rec: Dictionary = k["rec"]
		# a kin that doesn't trust you might just pretend it didn't hear
		if float(rec["trust"]) < 22.0 and randf() < 0.7:
			if not k.has("indoors"):
				get_tree().create_timer(0.4).timeout.connect(func(): if is_instance_valid(k["node"]): _emote(k, "…"))
			continue
		k["call_slot"] = slot
		if k.has("indoors"):
			inside.append(k)
			continue
		var dist := Vector2(k["pos"].x - ppos.x, k["pos"].z - ppos.z).length()
		get_tree().create_timer(0.12 + dist * 0.015 + randf() * 0.15).timeout.connect(func():
			if not is_instance_valid(k["node"]) or not kins.has(k): return
			k["nap_t"] = 0.0
			k.erase("nap_go"); k.erase("nap_go_t"); k.erase("going_in")
			k["called_t"] = 7.0
			_emote(k, "!")
			Sfx.play("kin_alert", k["pos"], -12.0, 0.15)
			if world.island_of(k["pos"].x, k["pos"].z) != my_isle and my_isle >= 0:
				_start_leap(k, ppos + slot))
	if not inside.is_empty():
		_house_alert(inside)

## The whistle itself: a soft, breathy two-note whistle (made in code by Synth.whistle).
func _whistle_sound() -> void:
	if whistle_player == null:
		whistle_player = AudioStreamPlayer.new()
		whistle_player.bus = "SFX"
		add_child(whistle_player)
		whistle_player.stream = Synth.whistle()
	whistle_player.pitch_scale = randf_range(0.97, 1.03)
	whistle_player.volume_db = -4.0
	whistle_player.play()

## A soft ring spreading out from you, and a little note over your head.
func _whistle_ring() -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new(); tm.inner_radius = 0.92; tm.outer_radius = 1.0; tm.rings = 32; tm.ring_segments = 4
	ring.mesh = tm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.92, 0.6, 0.7)
	ring.material_override = m
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = ppos + Vector3(0, 0.15, 0)
	ring.scale = Vector3(0.4, 1.0, 0.4)
	add_child(ring)
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(9.0, 1.0, 9.0), 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.9)
	tw.chain().tween_callback(ring.queue_free)
	var note := Label3D.new()
	note.text = "♪"
	note.font = UI.big; note.font_size = 64; note.pixel_size = 0.012; note.outline_size = 14
	note.modulate = Color("ffe08a")
	note.billboard = BaseMaterial3D.BILLBOARD_ENABLED; note.no_depth_test = true
	note.position = ppos + Vector3(0.35, 2.1, 0)
	add_child(note)
	var nt := note.create_tween().set_parallel(true)
	nt.tween_property(note, "position:y", note.position.y + 0.8, 0.9)
	nt.tween_property(note, "modulate:a", 0.0, 0.9).set_delay(0.3)
	nt.chain().tween_callback(note.queue_free)

## Kin inside the house heard you: a "!" pops over the roof, the house rattles with little feet,
## then they tumble out of the door one after another and run over.
func _house_alert(inside: Array) -> void:
	var names: Array = inside.map(func(k): return String(k["rec"]["name"]))
	var bub := Label3D.new()
	bub.text = "!"
	bub.font = UI.big; bub.font_size = 150; bub.pixel_size = 0.012; bub.outline_size = 26
	bub.modulate = UI.GOLD; bub.outline_modulate = Color(0.12, 0.06, 0.1)
	bub.billboard = BaseMaterial3D.BILLBOARD_ENABLED; bub.no_depth_test = true
	bub.position = spots["house"] + Vector3(0, 4.6, 0)
	bub.scale = Vector3.ONE * 0.1
	add_child(bub)
	var who := Label3D.new()
	who.text = ("%s heard you!" % names[0]) if names.size() == 1 else ("%s and %s heard you!" % [", ".join(names.slice(0, names.size() - 1)), names[-1]])
	who.font = UI.big; who.font_size = 46; who.pixel_size = 0.012; who.outline_size = 12
	who.modulate = UI.INK
	who.billboard = BaseMaterial3D.BILLBOARD_ENABLED; who.no_depth_test = true
	who.position = spots["house"] + Vector3(0, 3.7, 0)
	who.modulate.a = 0.0
	add_child(who)
	var tw := bub.create_tween()
	tw.tween_property(bub, "scale", Vector3.ONE * 1.25, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(bub, "scale", Vector3.ONE, 0.12)
	tw.tween_property(bub, "position:y", bub.position.y + 0.25, 0.35).set_trans(Tween.TRANS_SINE)
	tw.tween_property(bub, "position:y", bub.position.y, 0.35).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(1.2)
	tw.tween_property(bub, "modulate:a", 0.0, 0.3)
	tw.tween_callback(bub.queue_free)
	var wt := who.create_tween()
	wt.tween_property(who, "modulate:a", 1.0, 0.2)
	wt.tween_interval(2.0)
	wt.tween_property(who, "modulate:a", 0.0, 0.3)
	wt.tween_callback(who.queue_free)
	Sfx.play("kin_alert", spots["house"], -6.0, 0.1, 1.15)
	# the house might be off screen: say it on the HUD as well
	_toast(who.text.replace("heard you!", "heard you from the house and are on their way") if names.size() > 1 else who.text.replace("heard you!", "heard you from the house and is on its way"))
	# the house rattles: little feet scurrying for the door
	if is_instance_valid(house_node):
		var base := house_node.scale
		var ht := house_node.create_tween()
		for j in 4:
			ht.tween_property(house_node, "scale", base * Vector3(1.025, 0.97, 1.025), 0.07)
			ht.tween_property(house_node, "scale", base, 0.09)
			ht.tween_interval(0.08)
	for j in 5:
		get_tree().create_timer(0.15 + j * 0.16).timeout.connect(func(): Sfx.play("step%d" % (j % 3), spots["house"], -8.0, 0.2, 1.5))
	for j in inside.size():
		var k: Dictionary = inside[j]
		k["exiting"] = true
		get_tree().create_timer(0.95 + j * 0.35).timeout.connect(func():
			if kins.has(k): _kin_exit_house(k, true))

## Out of the front door (with a little pop), and on to wherever it was going.
func _kin_exit_house(k: Dictionary, called: bool) -> void:
	k.erase("indoors"); k.erase("exiting")
	var door := _house_door() + Vector3(randf_range(-0.4, 0.4), 0, 0.2)
	k["pos"] = door
	k["vel"] = Vector3(0, 0, 2.5)
	var n: Node3D = k["node"]
	n.position = door
	n.visible = true
	var s0 := n.scale
	n.scale = s0 * 0.3
	n.create_tween().tween_property(n, "scale", s0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play("pickup", door, -12.0, 0.1, 1.3)
	if called:
		k["called_t"] = 7.0
		_emote(k, "!")
	else:
		k["goal"] = door + Vector3(randf_range(-3, 3), 0, randf_range(2, 4))
		k["t"] = randf_range(1.0, 3.0)

## Too far to walk (another island): a big happy bound through the air to you.
func _start_leap(k: Dictionary, to: Vector3) -> void:
	var from: Vector3 = k["pos"]
	var dist := Vector2(to.x - from.x, to.z - from.z).length()
	k["leap"] = {"a": from, "b": to, "t": 0.0, "dur": clampf(dist / 10.0, 0.6, 1.6), "h": 1.6 + dist * 0.12}
	_emote(k, "!")
	Sfx.play("jump", from, -10.0, 0.1, 1.3)

func _leap_step(k: Dictionary, d: float) -> void:
	var L: Dictionary = k["leap"]
	L["t"] = float(L["t"]) + d
	var f := clampf(float(L["t"]) / float(L["dur"]), 0.0, 1.0)
	var p: Vector3 = (L["a"] as Vector3).lerp(L["b"], f)
	p.y = sin(PI * f) * float(L["h"])
	var n: Node3D = k["node"]
	n.position = p
	var dir: Vector3 = (L["b"] as Vector3) - (L["a"] as Vector3)
	n.rotation.y = lerp_angle(n.rotation.y, atan2(-dir.x, -dir.z), minf(1.0, d * 10.0))
	if f >= 1.0:
		k.erase("leap")
		k["pos"] = Vector3(p.x, 0, p.z)
		n.position = k["pos"]
		k["vel"] = Vector3.ZERO
		Sfx.play("land", k["pos"], -10.0, 0.1, 1.3)

func _emote(k: Dictionary, s: String, force := false) -> void:
	if not force and float(k.get("say_t", 0.0)) > 0.0:
		return
	if not force:
		# one little symbol per huddle, so a group doesn't sprout a cloud of icons
		for o in kins:
			if o != k and float(o.get("emote_t", 0.0)) > 0.4 and Vector2(o["pos"].x - k["pos"].x, o["pos"].z - k["pos"].z).length() < 3.0:
				return
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
	for nm in ["pot", "stall", "portal", "house", "ferry", "rack"]:
		if not spots.has(nm) or (nm == "rack" and not visit.is_empty()): continue
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
		if k.has("indoors"): continue
		var d := p2.distance_to(Vector2(k["pos"].x, k["pos"].z))
		if d < bd: bd = d; best = {"kind": "kin", "k": k}
	if p2.distance_to(Vector2(NEST_AT.x, NEST_AT.z)) < 1.8 and visit.is_empty():
		best = {"kind": "egg"} if is_instance_valid(nest) else {"kind": "nook"}
	if p2.distance_to(Vector2(YARD_AT.x, YARD_AT.z)) < 1.6 and best.is_empty():
		best = {"kind": "yard"}
	if hecon:
		var hb: Dictionary = hecon.find(p2, bd if not best.is_empty() else 9.0)
		if not hb.is_empty(): best = hb
	interact = best
	if panel_open != "" or best.is_empty() or building_now or chat_open or not train.is_empty():
		prompt_box.visible = false
		return
	prompt_box.visible = true
	var pairs: Array = []
	if best["kind"] == "kin" and visit.is_empty():
		var nm: String = best["k"]["rec"]["name"]
		pairs = [[Settings.key_cap("interact"), "Pet " + nm], [Settings.key_cap("play"), "Play fetch"], [Settings.key_cap("talk"), "Talk"], [Settings.key_cap("details"), "Details"]]
	else:
		pairs = [[Settings.key_cap("interact"), _label_for(best)]]
	# the prompt is keycaps and words, rebuilt only when what it says changes
	var sig := str(pairs)
	if String(prompt_box.get_meta("sig", "")) != sig:
		prompt_box.set_meta("sig", sig)
		prompt_lbl.visible = false
		var old_row := prompt_box.get_node_or_null("Keys")
		if old_row: old_row.free()
		var row := UI.key_hints(pairs, 14, UI.INK)
		row.name = "Keys"
		row.add_theme_constant_override("separation", 22)
		for one in row.get_children():
			var l: Label = one.get_child(one.get_child_count() - 1)
			l.add_theme_font_override("font", UI.big)
			l.add_theme_font_size_override("font_size", 18)
			l.add_theme_color_override("font_color", UI.GOLD if one.get_index() == 0 else UI.INK)
		prompt_box.add_child(row)
		prompt_box.reset_size()
		prompt_box.modulate.a = 0.0
		create_tween().tween_property(prompt_box, "modulate:a", 1.0, 0.12)
	prompt_box.reset_size()
	var vp := get_viewport().get_visible_rect().size
	prompt_box.position = Vector2((vp.x - prompt_box.size.x) * 0.5, vp.y - 110.0)

## Point at a kin to see who it is, how it's doing and what you can do with it.
var hover_k: Dictionary = {}
var hover_box: PanelContainer
var hover_lbl: RichTextLabel
func _update_hover() -> void:
	if hover_box == null:
		hover_box = UI.card(Color(0.05, 0.06, 0.09, 0.92), 10, 12)
		hover_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hover_lbl = RichTextLabel.new()
		hover_lbl.bbcode_enabled = true; hover_lbl.fit_content = true; hover_lbl.scroll_active = false
		hover_lbl.custom_minimum_size = Vector2(300, 0)
		hover_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hover_lbl.add_theme_font_size_override("normal_font_size", 14)
		hover_lbl.add_theme_font_size_override("bold_font_size", 19)
		hover_lbl.add_theme_font_override("bold_font", UI.big)
		hover_box.add_child(hover_lbl)
		root_ui.add_child(hover_box)
	var vp := get_viewport()
	var mp := vp.get_mouse_position()
	var best: Dictionary = {}; var bd := 52.0
	if panel_open == "" and not chat_open and not building_now and not Overlay.is_open():
		for k in kins:
			if k.has("indoors"): continue
			var np: Vector3 = (k["node"] as Node3D).global_position + Vector3(0, 0.45, 0)
			if cam.is_position_behind(np): continue
			var d := cam.unproject_position(np).distance_to(mp)
			if d < bd: bd = d; best = k
	hover_k = best
	hover_box.visible = not best.is_empty()
	if best.is_empty():
		return
	var rec: Dictionary = best["rec"]
	var sp: Dictionary = Data.KIN[rec["species"]]
	var col: Color = Care.shimmer_col(sp["color"]) if rec.get("shimmer", false) else sp["color"]
	var needs: Dictionary = rec.get("needs", {})
	var nl: Array = []
	for n in Care.NEEDS:
		var v := float(needs.get(n, 100.0))
		nl.append("%s %s" % [n.capitalize(), "[color=#ff8a7a]%d%%[/color]" % int(v) if v < 35.0 else "%d%%" % int(v)])
	var b: Array = Care.bond(rec)
	var t := "[b][color=#%s]%s[/color][/b]\n" % [col.to_html(false), rec["name"]]
	t += "[color=#9aa3b8]Lv %d %s  ·  %s  ·  %s bond[/color]\n" % [int(rec["level"]), Evo.form_name(rec), String(sp["type"]).capitalize(), b[1]]
	t += "  ·  ".join(nl) + "\n"
	if visit.is_empty():
		t += "[color=#ffd36a]Click[/color] details    [color=#ffd36a]%s[/color] pet    [color=#ffd36a]%s[/color] fetch    [color=#ffd36a]%s[/color] talk" % [Settings.key_cap("interact"), Settings.key_cap("play"), Settings.key_cap("talk")]
		if rec["uid"] == Save.d.get("active", ""):
			t += "\n[color=#8fe0a0]Your partner: comes on expeditions with you.[/color]"
	hover_lbl.text = t
	hover_box.reset_size()
	var vs := vp.get_visible_rect().size
	var pos := mp + Vector2(20, 16)
	if pos.x + hover_box.size.x > vs.x - 8: pos.x = mp.x - hover_box.size.x - 20
	if pos.y + hover_box.size.y > vs.y - 8: pos.y = mp.y - hover_box.size.y - 16
	hover_box.position = pos

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
			if int(d.get("wet", 2)) < 2: return "Water the %s (the rain only soaked it)" % cd["name"]
			return "%s: watered, growing (%s)" % [cd["name"], _grow_left(it["arr"], d)]
		"pot": return "Cook"
		"rack": return "Glider skins"
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
		"egg": return ("Help the %s hatch!" if _egg_ready() else "Warm the %s") % _egg_label()
		"yard": return "Train your partner"
		"nook": return "Pair two kin for an egg"
		"feeder", "grave", "graveyard", "place": return hecon.label(it)
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
		"rack": _open_rack()
		"stall": _open_shop()
		"portal": _open_expedition()
		"house": Game.goto("interior", {"room": "house"})
		"kin": _pet_kin(it["k"])
		"egg":
			if _egg_ready():
				_hatch_nest_egg()
			else:
				fx.burst(NEST_AT + Vector3(0, 0.5, 0), Color("ffd28a"), 8, 1.4)
				_toast("Warm and still. It hatches after your next expedition, or in a few minutes")
		"yard":
			var ak := Save.active_kin()
			if not ak.is_empty(): _open_train(ak)
		"nook": _open_nook()
		"feeder", "grave", "graveyard", "place": hecon.use(it)

func _unhandled_input(event: InputEvent) -> void:
	if not train.is_empty():
		if event.is_action_pressed("interact") or event.is_action_pressed("jump") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
			_train_hit()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("menu"):
			# walk away from the drill
			var tk: Dictionary = train["k"]
			tk["busy"] = false
			train = {}
			if is_instance_valid(train_bar): train_bar.queue_free()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton and event.pressed and panel_open == "":
		# click a kin to see its details
		if event.button_index == MOUSE_BUTTON_LEFT and not hover_k.is_empty() and visit.is_empty() and not building_now and not chat_open:
			_open_kin(hover_k["rec"])
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: cam.zoom_to = clampf(cam.zoom_to - 0.08, 0.55, 1.6)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: cam.zoom_to = clampf(cam.zoom_to + 0.08, 0.55, 1.6)
	if event.is_action_pressed("whistle") and panel_open == "" and not chat_open and visit.is_empty() and train.is_empty() and not Overlay.is_open():
		_whistle()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("menu") and hecon and not hecon.carry.is_empty():
		hecon.cancel_carry()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("menu") and not Overlay.is_open():
		if chat_open:
			_close_chat()
		elif panel_open != "":
			_close_panel()
		else:
			Overlay.open_pause("home")

# ------------------------------------------------------------------ ui
func _build_ui() -> void:
	ui = CanvasLayer.new(); add_child(ui)
	root_ui = Control.new(); root_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root_ui.theme = UI.theme()
	root_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root_ui)
	var top := UI.card(Color(0.06, 0.07, 0.11, 0.82), 10, 14)
	UI.set_card_border(top, Color(1, 1, 1, 0.07), 1)
	top.position = Vector2(16, 14)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th := UI.hbox(10); top.add_child(th)
	top_chips = UI.hbox(6)
	th.add_child(top_chips)
	topbar = UI.label("", 15, UI.INK)
	topbar.autowrap_mode = TextServer.AUTOWRAP_OFF
	topbar.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	topbar.visible = false
	th.add_child(topbar)
	root_ui.add_child(top)
	prompt_box = UI.card(Color(0.06, 0.07, 0.1, 0.85), 12, 12)
	prompt_lbl = UI.label("", 18, UI.GOLD, UI.big)
	prompt_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	prompt_box.add_child(prompt_lbl)
	root_ui.add_child(prompt_box)
	var hint_box := UI.card(Color(0.06, 0.07, 0.11, 0.66), 8, 12)
	hint_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var keys := UI.key_hints([["W A S D", "walk"], ["Space", "jump"], [Settings.key_cap("interact"), "use"], [Settings.key_cap("whistle"), "whistle"], ["I", "inventory"], ["Esc", "menu"]], 12, Color(1, 1, 1, 0.8))
	hint_box.add_child(keys)
	hint = UI.label("", 14, UI.INK)     # kept for code that still sets hint text; the key row replaces it
	hint.visible = false
	keys.add_child(hint)
	root_ui.add_child(hint_box)
	hint_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 12)
	hint_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel_host = CenterContainer.new()
	panel_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_ui.add_child(panel_host)

func _refresh_top() -> void:
	if not visit.is_empty():
		topbar.text = "Visiting %s's island   ·   Pet their kin, leave a gift at the house   ·   The portal takes you home" % String(visit.get("name", "a friend")).substr(0, 16)
		topbar.visible = true
		return
	topbar.visible = false
	var crops := 0
	for k in Save.d["crops"]: crops += int(Save.d["crops"][k])
	var ak := Save.active_kin()
	var treat: String = Save.d.get("treat", "")
	for ch in top_chips.get_children():
		ch.queue_free()
	if not ak.is_empty():
		var kc: Color = Data.KIN.get(String(ak.get("species", "")), {}).get("color", UI.ACCENT)
		top_chips.add_child(_top_chip("paw", String(ak.get("name", "")), kc, "Your partner: the kin that comes on expeditions with you"))
	top_chips.add_child(_top_chip("gem", str(int(Save.d["gems"])), UI.GOLD, "Gems: spend them on buildings, seeds and treats"))
	top_chips.add_child(_top_chip("tonic", str(int(Save.d["items"].get("tonic", 0))), Color("ff8a9a"), "Tonics: drink one (1) on an expedition to heal"))
	top_chips.add_child(_top_chip("seed", str(crops), UI.GOOD, "Crops you've harvested"))
	if treat != "":
		top_chips.add_child(_top_chip("heart", "Treat: " + _treat_name(treat), Color("ffb0d0"), "A treat is ready to give to a kin"))

## One number on the top bar: an icon, the value, and a tooltip saying what it is.
func _top_chip(icon: String, txt: String, col: Color, tip := "") -> Control:
	var c := UI.card(Color(col, 0.13), 6, 999)
	c.tooltip_text = tip
	c.mouse_filter = Control.MOUSE_FILTER_PASS if tip != "" else Control.MOUSE_FILTER_IGNORE
	var h := UI.hbox(6); c.add_child(h)
	h.add_child(Icons.Glyph.new(icon, col, 16.0))
	var l := UI.label(txt, 15, UI.INK, UI.semi)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	h.add_child(l)
	var m := MarginContainer.new(); m.add_theme_constant_override("margin_right", 4)
	h.add_child(m)
	return c

func _treat_name(t: String) -> String:
	for k in Data.CROPS:
		if Data.CROPS[k]["use"] == t: return Data.CROPS[k]["name"]
	return t

func _new_panel(title_txt: String, width := 520.0, scroll := false) -> VBoxContainer:
	var prev := panel_open
	_close_panel()
	var pb := UI.scroll_panel(title_txt, width, _close_panel, "Close", scroll)
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
	if was.ends_with(" evolved") or was.ends_with(" is changing") or was == "Welcome home":
		_play_evolutions.call_deferred()

# ---- your first day: the checklist lives in Progress so the house rooms can show and tick it too
const DAY1 := Progress.DAY1
var day1_box: PanelContainer = null

func _day1_active() -> bool:
	return visit.is_empty() and Progress.day1_active()

func _day1(step: String) -> void:
	if not visit.is_empty():
		return
	var r := Progress.day1_mark(step)
	if r == "":
		return
	Sfx.play("unlock", null, -8.0)
	if r == "all":
		_toast("First day done! +30 gems")
	_refresh_day1()
	_refresh_top()

func _refresh_day1() -> void:
	if is_instance_valid(day1_box):
		day1_box.queue_free()
	day1_box = null
	if not _day1_active():
		return
	day1_box = Progress.day1_box()
	root_ui.add_child(day1_box)
	if is_instance_valid(panel_host):
		root_ui.move_child(day1_box, panel_host.get_index())     # menus open on top of it

func _open_welcome() -> void:
	# shown once: marked seen as soon as it opens, however it's closed
	Save.d["tutorial"]["home"] = true
	Save.save_game()
	var kn: String = Save.active_kin().get("name", "your kin")
	var v := _new_panel("Welcome home", 560)
	v.add_child(UI.label("This little island is yours. %s lives here with you now, and it remembers everything you do together." % kn, 17))
	v.add_child(UI.label("Between expeditions you grow crops, build up your island and look after your kin. When you're ready, the portal takes you out to the wild isles to hunt for treasure, seeds and new kin.", 16, UI.MUTED))
	v.add_child(UI.label("Just remember: what you find out there is only yours once you make it back.", 16, Color("ffc9a0")))
	var go := UI.hbox(8)
	go.add_child(UI.label("Walk up to anything and press", 16, UI.GOLD))
	go.add_child(UI.keycap(Settings.key_cap("interact"), 14))
	go.add_child(UI.label("Start by saying hi to %s." % kn, 16, UI.GOLD))
	v.add_child(go)
	var b := UI.primary("Let's go", func():
		Save.d["tutorial"]["home"] = true
		Save.save_game()
		_close_panel(), 200)
	v.add_child(b)
	b.grab_focus.call_deferred()

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
	# steps done elsewhere (inside the house, the inventory) show up here
	if _day1_active() and typeof(Save.d["tutorial"].get("day1")) == TYPE_DICTIONARY:
		var dd: Dictionary = Save.d["tutorial"]["day1"]
		if dd.size() >= DAY1.size():
			Save.d["tutorial"]["day1_done"] = true
			Save.d["gems"] = int(Save.d["gems"]) + 30
			_toast("First day done! +30 gems")
			Save.save_game()
			_refresh_day1()
			_refresh_top()
		elif is_instance_valid(day1_box) and int(day1_box.get_meta("n", -1)) != dd.size():
			_refresh_day1()
			if is_instance_valid(day1_box): day1_box.set_meta("n", dd.size())
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
				_water(arr, i, "rain")
				continue
			if wt > 0.0 and now - wt >= Data.WATER_TIME * (0.5 if arr == "gh_plots" else 1.0):
				d["stage"] = int(d["stage"]) + 1
				# rain only makes it wet; watering it yourself (or a farmhand kin) is what counts as tending
				if int(d.get("wet", 2)) >= 2:
					d["care"] = int(d.get("care", 0)) + 1
				d["wt"] = 0.0
				d["wet"] = 0
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
			if d["crop"] != "" and (float(d.get("wt", 0.0)) <= 0.0 or int(d.get("wet", 2)) < 2) and int(d["stage"]) < int(Data.CROPS[d["crop"]]["grow"]):
				if arr == "plots" or _isle_open("orchard"):
					return [arr, i]
	return []

## Watering. who: "you" (by hand), "kin" (a farmhand) or "rain". Rain makes a plant wet so it
## grows; by hand (or a farmhand) it's also tended, which is what earns the bigger harvest. A plant
## the rain already soaked can still be watered by hand to tend it, without restarting its growth.
func _water(arr: String, i: int, who = "you") -> void:
	if typeof(who) == TYPE_BOOL: who = "you" if who else "rain"
	var d: Dictionary = Save.d[arr][i]
	var already := float(d.get("wt", 0.0)) > 0.0
	if not already:
		d["wt"] = Time.get_unix_time_from_system()
	d["wet"] = 1 if who == "rain" else 2
	var pn: Node3D = _plot_node(arr, i)
	if who == "you":
		_day1("water")
		Sfx.play("plant", null, -6.0, 0.1, 1.4)
		fx.burst(pn.position + Vector3(0, 0.8, 0), Color("7ac8ff"), 14, 2.0)
		if already:
			fx.burst(pn.position + Vector3(0, 0.9, 0), Color("bfefff"), 10, 2.4)
			_toast("Tended! Rain only soaks it; your watering counts toward a bigger harvest.")
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
			Progress.add("harvested", n)
			var extra := ""
			# a fully tended common crop sometimes drops a seed (rare ones never do)
			if care >= grow and float(cd.get("weight", 1.0)) >= 1.0 and randf() < 0.5:
				Save.add_seed(d["crop"], 1)
				extra = " and a seed"
			fx.burst(pn.position + Vector3(0, 0.6, 0), cd["color"], 18 + n * 4, 3.0)
			Sfx.play("harvest")
			_toast("%d %s%s%s" % [n, cd["name"], "" if n == 1 else "s", extra])
			d["crop"] = ""; d["stage"] = 0; d["care"] = 0; d["wt"] = 0.0; d["wet"] = 0
			_refresh_plot(arr, i)
			Save.save_game()
			_refresh_top()
			return
		if float(d.get("wt", 0.0)) <= 0.0 or int(d.get("wet", 2)) < 2:
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
			_day1("plant")
			fx.dust(pn.position, 10)
			_refresh_plot(arr, i)
			Save.save_game()
			_close_panel()))
		v.add_child(row)
	if not any:
		v.add_child(UI.label("You have no seeds. Find them in chests and from monsters on expeditions, or buy some at the stall.", 16, UI.MUTED))
	v.add_child(UI.label("Water a plant (" + Settings.key_cap("interact") + ") and it grows a stage every %d seconds while you're home. Expeditions grow everything a stage too. Rain waters for you." % int(Data.WATER_TIME), 13, UI.MUTED))

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

var shop_tab := "Seeds"

var shop_page := 0

## The market: goods in tabs, shown as cards a page at a time. Some only go on sale once you've
## made it out of enough expeditions or finished a challenge at the Challenge House.
func _open_shop() -> void:
	var v := _new_panel("Market stall", 780)
	var top := UI.hbox(6)
	for t in ["Seeds", "Kin food", "Wear", "Home", "Farm", "Sell"]:
		var tn: String = t
		top.add_child(UI.choice(t, t == shop_tab, func(): shop_tab = tn; shop_page = 0; UI._page_of.erase("Market stall"); _open_shop()))
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	top.add_child(UI.label("%d gems" % int(Save.d["gems"]), 18, UI.GOLD, UI.big))
	top.set_meta("pg_keep", true)
	v.add_child(top)
	if shop_tab == "Sell":
		_shop_sell(v)
		return
	# [key, name, description, price, colour, on_buy, owned_text]
	var goods: Array = []
	match shop_tab:
		"Seeds":
			for c in Data.CROPS:
				var cd: Dictionary = Data.CROPS[c]
				var ck: String = c
				goods.append(["seed:" + c, "%s seeds" % cd["name"], cd["desc"], int(cd["price"]), cd["color"], func(): Save.add_seed(ck, 1), "have %d" % int(Save.d.get("seeds", {}).get(c, 0))])
		"Kin food":
			for f in Care.FOODS:
				var fd: Dictionary = Care.FOODS[f]
				var fk: String = f
				goods.append(["food:" + f, fd["name"], fd["desc"], int(fd["price"]), Color("ffb36a"), func(): Save.add_item(fk, 1), "have %d" % int(Save.d["items"].get(f, 0))])
			goods.append(["tonic", "Tonic", "Heals 45 in a match (%s)." % Settings.key_cap("tonic"), 30, Color("8fe0a0"), func(): Save.add_item("tonic", 1), "have %d" % int(Save.d["items"].get("tonic", 0))])
		"Wear":
			var owned: Array = Save.d.get("accs", [])
			for a in Data.ACCS:
				var ad: Dictionary = Data.ACCS[a]
				var ak: String = a
				goods.append(["acc:" + a, ad["name"], "Put it on from a kin's card (Dress). Worn on expeditions too.", -1 if owned.has(a) else int(ad["price"]), ad["col"], func():
					if not Save.d.has("accs"): Save.d["accs"] = []
					Save.d["accs"].append(ak), "yours" if owned.has(a) else ""])
		"Home":
			for f in Data.FURN:
				var fd: Dictionary = Data.FURN[f]
				var fk: String = f
				goods.append(["furn:" + f, fd["name"], "For your house or a cottage. It waits in your inventory until you place it.", int(fd["price"]), Color("c8a07a"), func():
					if not Save.d.has("furniture"): Save.d["furniture"] = {}
					Save.d["furniture"][fk] = int(Save.d["furniture"].get(fk, 0)) + 1, "have %d" % int(Save.d.get("furniture", {}).get(f, 0))])
		"Farm":
			goods += hecon.shop_goods()
			if int(Save.d["plot_cap"]) < 8:
				goods.append(["plots", "Two more plots", "Grow more at once.", 120 + 80 * (int(Save.d["plot_cap"]) - 4), Color("9c7a52"), func():
					Save.d["plot_cap"] = int(Save.d["plot_cap"]) + 2
					_build_plots(), "%d plots" % int(Save.d["plot_cap"])])
	# open goods first, then the ones still locked
	goods.sort_custom(func(a, b): return int(Progress.unlocked(a[0])) > int(Progress.unlocked(b[0])))
	var per := 6
	var pages := maxi(1, int(ceil(goods.size() / float(per))))
	shop_page = clampi(shop_page, 0, pages - 1)
	var grid := GridContainer.new(); grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10); grid.add_theme_constant_override("v_separation", 10)
	for g in goods.slice(shop_page * per, shop_page * per + per):
		grid.add_child(_shop_card(g))
	if goods.is_empty():
		v.add_child(UI.label("Nothing for sale here right now.", 15, UI.MUTED))
	v.add_child(grid)
	if pages > 1:
		# page arrows live in the header so they never get pushed off the panel
		var pv := UI.button("‹", func(): shop_page -= 1; _open_shop(), 44); pv.disabled = shop_page <= 0
		var nx := UI.button("›", func(): shop_page += 1; _open_shop(), 44); nx.disabled = shop_page >= pages - 1
		top.add_child(pv); top.add_child(UI.label("%d/%d" % [shop_page + 1, pages], 14, UI.MUTED)); top.add_child(nx)

func _shop_card(g: Array) -> Control:
	var key: String = g[0]
	var open := Progress.unlocked(key)
	var price: int = g[3]
	var card := UI.card(UI.CARD if open else Color(0.1, 0.1, 0.13, 0.9), 12, 12)
	card.custom_minimum_size = Vector2(236, 150)
	var v := UI.vbox(6); card.add_child(v)
	var hr := UI.hbox(8)
	var sw := Panel.new(); sw.custom_minimum_size = Vector2(26, 26)
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(g[4]) if open else Color(g[4]).darkened(0.6); sb.set_corner_radius_all(13)
	sw.add_theme_stylebox_override("panel", sb)
	hr.add_child(sw)
	var nm := UI.label(String(g[1]), 17, UI.INK if open else UI.MUTED, UI.big); nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.clip_text = true
	hr.add_child(nm)
	v.add_child(hr)
	var d := UI.label(String(g[2]), 13, UI.MUTED)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(212, 40)
	d.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(d)
	if not open:
		var lk := UI.label("Locked  ·  " + Progress.req_text(key), 12, Color("ff9a8a"))
		lk.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lk.custom_minimum_size.x = 212
		v.add_child(lk)
		return card
	var br := UI.hbox(8)
	var own := UI.label(String(g[6]), 12, UI.MUTED); own.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	br.add_child(own)
	if price >= 0:
		var on_buy: Callable = g[5]
		var b := UI.primary("%d gems" % price, func():
			if int(Save.d["gems"]) < price: return
			Save.d["gems"] = int(Save.d["gems"]) - price
			on_buy.call()
			Sfx.play("pickup")
			Save.save_game()
			_open_shop(), 110)
		b.disabled = int(Save.d["gems"]) < price
		br.add_child(b)
	v.add_child(br)
	return card

## The Challenge House: goals with rewards. Finished ones are claimed here for gems, and some open
## up new goods at the market.
var chal_page := 0
func _open_challenges() -> void:
	var v := _new_panel("Challenge House", 780)
	var ready := Progress.ready_to_claim()
	var donec: int = Save.d.get("challenges", []).size()
	var head := UI.label("%d of %d done%s" % [donec, Progress.CHALLENGES.size(), ("  ·  %d ready to claim!" % ready.size()) if ready.size() > 0 else ""], 16, UI.GOLD if ready.size() > 0 else UI.MUTED)
	var hrow := UI.hbox(8)
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hrow.add_child(head)
	hrow.set_meta("pg_keep", true)
	v.add_child(hrow)
	# ready first, then in progress, then finished
	var list: Array = Progress.CHALLENGES.duplicate()
	list.sort_custom(func(a, b):
		var ra := 0 if ready.has(a) else (2 if Progress.done(a[0]) else 1)
		var rb := 0 if ready.has(b) else (2 if Progress.done(b[0]) else 1)
		return ra < rb)
	var per := 4
	var pages := maxi(1, int(ceil(list.size() / float(per))))
	chal_page = clampi(chal_page, 0, pages - 1)
	var grid := GridContainer.new(); grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10); grid.add_theme_constant_override("v_separation", 10)
	for c in list.slice(chal_page * per, chal_page * per + per):
		grid.add_child(_challenge_card(c, ready.has(c)))
	v.add_child(grid)
	if pages > 1:
		var pv := UI.button("‹", func(): chal_page -= 1; _open_challenges(), 44); pv.disabled = chal_page <= 0
		var nx := UI.button("›", func(): chal_page += 1; _open_challenges(), 44); nx.disabled = chal_page >= pages - 1
		hrow.add_child(pv); hrow.add_child(UI.label("%d/%d" % [chal_page + 1, pages], 14, UI.MUTED)); hrow.add_child(nx)

func _challenge_card(c: Array, ready: bool) -> Control:
	var donec := Progress.done(c[0])
	var card := UI.card(UI.CARD if not donec else Color(0.08, 0.12, 0.09, 0.9), 12, 12)
	card.custom_minimum_size = Vector2(360, 120)
	if ready: UI.set_card_border(card, UI.GOLD)
	var v := UI.vbox(5); card.add_child(v)
	var hr := UI.hbox(8)
	var nm := UI.label(String(c[1]), 18, UI.GOLD if ready else (UI.GOOD if donec else UI.INK), UI.big); nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hr.add_child(nm)
	hr.add_child(UI.label("+%d gems" % int(c[5]), 14, UI.GOLD))
	v.add_child(hr)
	v.add_child(UI.label(String(c[2]), 14, UI.MUTED))
	var cur := mini(Progress.stat(c[3]), int(c[4]))
	var bar := ProgressBar.new(); bar.max_value = float(c[4]); bar.value = float(cur); bar.show_percentage = false
	bar.custom_minimum_size = Vector2(320, 10)
	v.add_child(bar)
	var br := UI.hbox(8)
	var ul: Array = Progress.unlocks_of(c[0]).map(func(k): return Progress.item_name(k))
	var info := UI.label(("%d / %d" % [cur, int(c[4])]) + (("  ·  unlocks " + ", ".join(ul)) if ul.size() > 0 else ""), 12, UI.MUTED)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	br.add_child(info)
	if ready:
		br.add_child(UI.primary("Claim", func():
			var g := Progress.claim(c[0])
			if g > 0:
				Sfx.play("unlock")
				_toast("%s done!  +%d gems" % [c[1], g])
				_refresh_top()
			_open_challenges(), 100))
	elif donec:
		br.add_child(UI.label("Done", 14, UI.GOOD, UI.big))
	v.add_child(br)
	return card

func _shop_sell(v: VBoxContainer) -> void:
	var sell_any := false
	for s in Data.CROPS:
		var n := int(Save.d["crops"].get(s, 0))
		if n <= 0: continue
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
	if not sell_any:
		v.add_child(UI.label("Nothing to sell. Harvest your plots first.", 15, UI.MUTED))

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
# ---- kin: petting, playing and talking happen out in the world; only the details card is a menu
func _kin_entry(rec: Dictionary) -> Dictionary:
	for k in kins:
		if k["rec"] == rec: return k
	return {}

func _face(at: Vector3) -> void:
	pface = atan2(-(at.x - ppos.x), -(at.z - ppos.z))
	player.rotation.y = pface

func _pet_kin(k: Dictionary) -> void:
	var rec: Dictionary = k["rec"]
	if float(k.get("nap_t", 0.0)) > 0.0:
		# a gentle pat wakes it up
		k["nap_t"] = 0.01
	var loves_pet: bool = rec["likes"]["play"] == "pet"
	var now_s := Time.get_ticks_msec() / 1000.0
	if now_s >= float(k.get("pet_ok", 0.0)):
		k["pet_ok"] = now_s + 20.0
		Care.change(rec, "joy", 12.0 if loves_pet else 5.0)
	if loves_pet and Care.discover(rec, "play"): _toast("%s loves scratches" % rec["name"])
	k["hold_t"] = 1.0
	k["joy_t"] = 0.9
	_day1("pet")
	_face(k["pos"])
	_emote(k, "♥", true)
	fx.burst(k["pos"] + Vector3(0, 0.9, 0), Color("ff8fb0"), 12, 1.8)
	Sfx.play("kin_happy", null, -4.0, 0.12)
	if pet_done.get(rec["uid"], -1) != int(Save.d["matches"]):
		pet_done[rec["uid"]] = int(Save.d["matches"])
		Save.remember(rec, "petted", "got a long scratch behind the ears", 1.5)
		Save.save_game()
		_say(k, KinSpeak.say(rec, "love") if Care.speech(rec) < 3 else ["Hehe!", "More!", "That's the spot.", "♥"][randi() % 4], 1.6)

## Fetch: you toss a ball toward the cursor, the kin runs it down and brings it back.
func _play_with_kin(k: Dictionary) -> void:
	if k.has("fetch"):
		return
	var aim := cam.mouse_on_plane(0.0)
	var dir := Vector2(aim.x - ppos.x, aim.z - ppos.z)
	if dir.length() < 1.0: dir = Vector2(sin(pface), cos(pface)) * -1.0
	var to := ppos + Vector3(dir.normalized().x, 0, dir.normalized().y) * clampf(dir.length(), 3.0, 7.0)
	for _i in 8:
		if not world.is_void(to.x, to.z) and not world.is_block(to.x, to.z): break
		to = ppos + (to - ppos) * 0.75
	if world.is_void(to.x, to.z) or world.is_block(to.x, to.z):
		to = ppos + Vector3(1.5, 0, 0)
	var ball := MeshInstance3D.new()
	ball.mesh = Models.sphere(0.16, 12)
	ball.material_override = Models.toon(Color("ff6a5a"))
	add_child(ball)
	ball.position = ppos + Vector3(0, 1.2, 0)
	_face(to)
	k["fetch"] = {"ball": ball, "from": ball.position, "to": to, "t": 0.0, "phase": "fly", "life": 14.0}
	k.erase("chase"); k.erase("task")
	_emote(k, "!")
	Sfx.play("throw", null, -8.0)

func _fetch_step(k: Dictionary, d: float) -> void:
	var f: Dictionary = k["fetch"]
	var ball: MeshInstance3D = f["ball"]
	f["life"] -= d
	var pos: Vector3 = k["pos"]
	match String(f["phase"]):
		"fly":
			f["t"] += d
			var q := clampf(f["t"] / 0.7, 0.0, 1.0)
			var a: Vector3 = f["from"]; var b: Vector3 = f["to"] + Vector3(0, 0.16, 0)
			ball.position = a.lerp(b, q) + Vector3(0, 2.2 * q * (1.0 - q), 0)
			k["goal"] = f["to"]
			if q >= 1.0: f["phase"] = "ground"
		"ground":
			k["goal"] = f["to"]
			if Vector2(pos.x - f["to"].x, pos.z - f["to"].z).length() < 0.55:
				f["phase"] = "carry"
				Sfx.play("pickup", null, -14.0)
		"carry":
			ball.position = pos + Vector3(0, 0.75, 0)
			k["goal"] = ppos
			if Vector2(pos.x - ppos.x, pos.z - ppos.z).length() < 1.3:
				f["life"] = -1.0
				_emote(k, "★")
				k["joy_t"] = 0.8
				_day1("fetch")
				Sfx.play("kin_happy", null, -6.0)
				var rec: Dictionary = k["rec"]
				var loves_fetch: bool = rec["likes"]["play"] == "fetch"
				Care.change(rec, "joy", 24.0 if loves_fetch else 14.0)
				Care.change(rec, "energy", -6.0)
				Care.change(rec, "clean", -4.0)
				if loves_fetch and Care.discover(rec, "play"): _toast("%s loves playing fetch" % rec["name"])
				if int(rec.get("played", -1)) != int(Save.d["matches"]):
					rec["played"] = int(Save.d["matches"])
					Save.remember(rec, "played", "played fetch with you on the farm", 1.5)
					Save.save_game()
	if f["life"] <= 0.0:
		ball.queue_free()
		k.erase("fetch")
		k["t"] = randf_range(1.5, 3.0)

## A speech bubble over a kin's head.
func _say(k: Dictionary, text: String, secs := 4.0, direct := true) -> void:
	if not direct:
		# chatter waits its turn: nobody else talking nearby, and a breath since the last line
		if talk_cd > 0.0 or _talking_near(k, 7.0):
			return
		talk_cd = randf_range(3.0, 5.0)
	else:
		# something you did with this kin: its answer wins, the others go quiet around it
		for o in kins:
			if o != k and o.has("say") and Vector2(o["pos"].x - k["pos"].x, o["pos"].z - k["pos"].z).length() < 5.0:
				o["say_t"] = 0.0
				(o["say"] as Label3D).visible = false
		talk_cd = maxf(talk_cd, 2.0)
	if not k.has("say"):
		var l := Label3D.new()
		l.font = UI.body; l.font_size = 34; l.pixel_size = 0.0105; l.outline_size = 14
		l.outline_modulate = Color(0.06, 0.05, 0.09, 0.95)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED; l.no_depth_test = true
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; l.width = 520
		l.position = Vector3(0, 1.75, 0)
		(k["node"] as Node3D).add_child(l)
		k["say"] = l
	(k["say"] as Label3D).text = text
	k["say_t"] = secs
	(k["say"] as Label3D).visible = true

## The details card: everything about one kin, laid out to fit on screen without scrolling.
func _open_kin(rec: Dictionary) -> void:
	var sp: Dictionary = Data.KIN[rec["species"]]
	Evo.ensure(rec)
	Care.ensure(rec)
	var col: Color = Care.shimmer_col(sp["color"]) if rec.get("shimmer", false) else sp["color"]
	var v := _new_panel("%s the %s%s" % [rec["name"], "shimmering " if rec.get("shimmer", false) else "", Evo.form_name(rec)], 920)
	var cols := UI.hbox(22)
	v.add_child(cols)
	var row := func(parent: Control, label_txt: String, frac: float, c: Color, right := "", lw := 64.0, bw := 130.0) -> void:
		var r := UI.hbox(8)
		var l := UI.label(label_txt, 13, UI.MUTED); l.custom_minimum_size.x = lw
		r.add_child(l)
		r.add_child(UI.bar(frac, c, bw, 7))
		if right != "": r.add_child(UI.label(right, 12, UI.MUTED))
		parent.add_child(r)
	# who it is and how it's doing
	var c1 := UI.vbox(5); c1.custom_minimum_size.x = 270
	c1.add_child(UI.label("Level %d %s kin  ·  %s" % [int(rec["level"]), String(sp["type"]).capitalize(), Care.stage_name(rec)], 15, col))
	c1.add_child(UI.label("%s nature%s" % [Care.nature(rec), "  ·  your partner" if rec["uid"] == Save.d.get("active", "") else ""], 13, UI.GOLD if rec["uid"] == Save.d.get("active", "") else UI.MUTED))
	var bd: Array = Care.bond(rec)
	var nb: Array = Care.next_bond(rec)
	c1.add_child(UI.section("Bond: %s" % bd[1]))
	var lo := float(bd[0]); var hi := float(nb[0]) if nb.size() > 0 else 100.0
	row.call(c1, "Trust", clampf((float(rec["trust"]) - lo) / maxf(1.0, hi - lo), 0.0, 1.0), Color("ffb3c6"), ("next: %s" % nb[1]) if nb.size() > 0 else "max")
	var bl := UI.label(String(bd[2]), 12, UI.MUTED); bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; c1.add_child(bl)
	c1.add_child(UI.section(Care.condition_name(rec), Color("ff9a7a") if Care.starve_stage(rec) != "" else Color("c9a46a")))
	if Care.starve_stage(rec) != "":
		var sl := UI.label(String(Care.STARVE_INFO[Care.starve_stage(rec)][1]), 12, Color("ffb0a0"))
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		c1.add_child(sl)
	if String(rec.get("title", "")) != "":
		c1.add_child(UI.label("%s %s  ·  came back from the Soul Shrine" % [rec["name"], rec["title"]], 12, Color("bff8ec")))
	for n in Care.NEEDS:
		row.call(c1, Care.NEED_INFO[n]["name"], Care.need(rec, n) / 100.0, Care.NEED_INFO[n]["col"], str(int(Care.need(rec, n))))
	cols.add_child(c1)
	# trained stats and what it does in a match
	var c2 := UI.vbox(5); c2.custom_minimum_size.x = 270
	c2.add_child(UI.section("Training  (cap %d)" % Care.stat_cap(rec)))
	for s in Care.STATS:
		row.call(c2, Care.STATS[s]["name"], float(rec["stats"][s]) / float(Care.stat_cap(rec)), Care.STATS[s]["col"], str(int(rec["stats"][s])))
	var sh: Dictionary = Data.SHOULDER[sp["shoulder"]]
	c2.add_child(UI.section("In a match"))
	var abl: Array = sp.get("abilities", [])
	for ai in abl.size():
		var ad := Content.ability(String(abl[ai]))
		if ad == null: continue
		var skl := UI.label("%s (%s): %s" % [ad.display_name, Settings.key_cap("signature" if ai == 0 else "kin_skill"), ad.desc], 12, ad.color.lerp(UI.INK, 0.5)); skl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; c2.add_child(skl)
	var ud := Content.ultimate(String(sp.get("ultimate", "")))
	if ud:
		var ul := UI.label("Bond ultimate, %s (%s): %s" % [ud.display_name, Settings.key_cap("ultimate"), ud.desc], 12, ud.color.lerp(UI.INK, 0.4)); ul.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; c2.add_child(ul)
	var shl := UI.label("On your shoulder, %s: %s" % [sh["name"], sh["desc"]], 12, UI.MUTED); shl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; c2.add_child(shl)
	cols.add_child(c2)
	# how it's growing, and what you know about it
	var c3 := UI.vbox(5); c3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lead := Evo.leading(rec)
	var lv := int(rec["level"])
	var next_form := (lv / 4 + 1) * 4
	var next_mut := lv + ((2 - lv % 4) + 4) % 4
	if next_mut == lv: next_mut += 4
	c3.add_child(UI.section("Growing"))
	c3.add_child(UI.label("%s. Form at %d, mutation at %d." % [String(Evo.AFF[lead]["name"]), next_form, next_mut], 13, Evo.AFF[lead]["tint"]))
	var tot := 0.0
	for a in Evo.AFF: tot += maxf(0.0, float(rec["aff"][a]))
	for a in Evo.AFF:
		row.call(c3, Evo.AFF[a]["name"], float(rec["aff"][a]) / maxf(tot, 1.0), Evo.AFF[a]["tint"], "", 70.0, 110.0)
	c3.add_child(UI.section("Likes"))
	var known: Array = rec["known"]
	var lk: Dictionary = rec["likes"]
	c3.add_child(UI.label("Loves  %s" % (Care.food_name(lk["food"]) if known.has("food") else "???"), 13, UI.INK if known.has("food") else UI.MUTED))
	c3.add_child(UI.label("Won't eat  %s" % (Care.food_name(lk["hates"]) if known.has("hates") else "???"), 13, UI.INK if known.has("hates") else UI.MUTED))
	c3.add_child(UI.label("Favourite  %s" % (Care.PLAY_NAMES[lk["play"]] if known.has("play") else "???"), 13, UI.INK if known.has("play") else UI.MUTED))
	if rec.has("parents"):
		c3.add_child(UI.label("Child of %s and %s" % [rec["parents"][0], rec["parents"][1]], 12, UI.MUTED))
	cols.add_child(c3)
	# the latest memory
	var mem: Array = rec.get("memory", [])
	if mem.size() > 0:
		var t := String(mem[-1]["text"])
		v.add_child(UI.label("Remembers: %s" % (t.substr(0, 1).to_upper() + t.substr(1)), 13, UI.MUTED))
	# looking after it
	var btns := HFlowContainer.new()
	btns.add_theme_constant_override("h_separation", 8); btns.add_theme_constant_override("v_separation", 8)
	btns.add_child(UI.primary("Feed", func(): _open_feed(rec), 90))
	btns.add_child(UI.button("Brush", func(): _care_brush(rec), 90))
	btns.add_child(UI.button("Bath", func(): _care_bath(rec), 90))
	btns.add_child(UI.button("Nap", func(): _care_nap(rec), 90))
	btns.add_child(UI.button("Train", func(): _open_train(rec), 90))
	btns.add_child(UI.button("Dress", func(): _open_wear(rec), 90))
	var why := _can_pair(rec)
	var pb := UI.button("Pair", func(): _open_pair(rec), 90)
	pb.disabled = why != ""
	pb.tooltip_text = why
	btns.add_child(pb)
	if rec["uid"] != Save.d.get("active", ""):
		btns.add_child(UI.button("Make partner", func():
			if Save.d.get("active2", "") == rec["uid"]: Save.d["active2"] = Save.d.get("active", "")
			Save.d["active"] = rec["uid"]
			Save.save_game()
			_open_kin(rec), 130))
		if rec["uid"] != Save.d.get("active2", ""):
			btns.add_child(UI.button("Bring as second", func():
				Save.d["active2"] = rec["uid"]
				Save.save_game()
				_toast("%s will come along on your next expedition (%s swaps it in)" % [rec["name"], Settings.key_cap("swap_kin")])
				_open_kin(rec), 150))
	if rec.get("farmhand", false):
		btns.add_child(UI.button("Stop farming", func():
			rec.erase("farmhand")
			Save.save_game()
			_open_kin(rec), 130))
	else:
		btns.add_child(UI.button("Make farmhand", func():
			for r2 in Save.d["roster"]: r2.erase("farmhand")
			rec["farmhand"] = true
			Save.remember(rec, "farm", "was put in charge of watering the farm", 1.0)
			Save.save_game()
			_toast("%s will water your plants" % rec["name"])
			_open_kin(rec), 130))
	v.add_child(btns)

# ---- talking: speech bubbles over the kin and a slim bar to type in
var chat_open := false
var chat_bar: Control = null
var chat_hist: Label = null

func _open_chat(rec: Dictionary) -> void:
	_close_panel()
	_close_chat()
	chat_kin = rec
	chat_open = true
	if chat_log.size() == 0 or chat_log[0].get("uid", "") != rec["uid"]:
		chat_log = [{"uid": rec["uid"]}]
	var k := _kin_entry(rec)
	if not k.is_empty():
		k["hold_t"] = 9999.0
		_face(k["pos"])
		if chat_log.size() == 1:
			_say(k, _greeting(rec), 5.0)
	var bar := UI.card(Color(0.06, 0.07, 0.1, 0.92), 12, 14)
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.offset_top = -64; bar.offset_bottom = -64
	bar.custom_minimum_size.x = minf(640.0, get_viewport().get_visible_rect().size.x - 32.0)
	var col := UI.vbox(8)
	bar.add_child(col)
	chat_hist = UI.label("", 13, UI.MUTED)
	chat_hist.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(chat_hist)
	var row := UI.hbox(8)
	chat_input = LineEdit.new()
	chat_input.placeholder_text = "Say something to %s" % rec["name"]
	chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_input.max_length = 200
	chat_input.text_submitted.connect(func(_t): _send_chat())
	row.add_child(chat_input)
	row.add_child(UI.button("Say", _send_chat))
	row.add_child(UI.button("Done", _close_chat))
	col.add_child(row)
	root_ui.add_child(bar)
	chat_bar = bar
	_chat_bubble("", "")
	chat_input.grab_focus()

func _close_chat() -> void:
	if is_instance_valid(chat_bar):
		chat_bar.queue_free()
	chat_bar = null
	chat_input = null
	chat_hist = null
	if chat_open:
		var k := _kin_entry(chat_kin)
		if not k.is_empty(): k["hold_t"] = 0.6
	chat_open = false

func _greeting(rec: Dictionary) -> String:
	var t := float(rec["trust"])
	if Care.speech(rec) < 3:
		var w := Care.want(rec)
		return KinSpeak.say(rec, "sad" if t < 30.0 else ("question" if w != "" else "happy"), "cold" if t < 30.0 else (w if w != "" else "hello"))
	if t > 70.0: return "Hi! I was hoping you'd come say hi."
	if t < 30.0: return "...oh. It's you."
	return "Hey. What's up?"

## Keeps the last few lines of the conversation in the bar.
func _chat_bubble(_role: String, _text: String) -> void:
	if not is_instance_valid(chat_hist):
		return
	var lines: Array = []
	var turns: Array = chat_log.slice(1)
	for t in turns.slice(maxi(0, turns.size() - 4)):
		lines.append(("You: " if t["role"] == "user" else "%s: " % chat_kin.get("name", "Kin")) + String(t["content"]))
	chat_hist.text = "\n".join(lines) if lines.size() > 0 else "Type below and press Enter. %s answers above its head." % chat_kin.get("name", "Your kin")

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
	var k := _kin_entry(rec)
	chat_busy = true
	var dots := create_tween().set_loops()
	for i in 4:
		var n := i
		dots.tween_callback(func(): if not k.is_empty(): _say(k, ".".repeat(n + 1), 1.0))
		dots.tween_interval(0.35)
	var t0 := Time.get_ticks_msec() / 1000.0
	var msgs := []
	var brief := Bridge.kin_brief(rec) + "\n\nYou are chatting with your hunter at home on the farm. Stay in character and respond to what they actually said. " + \
		("Answer in one to three short sentences, plain text, no emoji, no stage directions. " if Care.speech(rec) >= 3 else "Follow the rule above about how you can talk. Keep it short. ") + \
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
			reply = KinSpeak.reply(rec, txt)
		# a kin takes a moment to answer: at least 2 seconds, longer for longer replies
		var want := clampf(2.0 + reply.length() * 0.03, 2.0, 6.0)
		var wait := want - (Time.get_ticks_msec() / 1000.0 - t0)
		if wait > 0.0:
			await get_tree().create_timer(wait).timeout
		dots.kill()
		if not is_inside_tree():
			return
		chat_busy = false
		chat_log.append({"role": "assistant", "content": reply})
		if not k.is_empty():
			_say(k, reply, clampf(3.0 + reply.length() * 0.06, 4.0, 10.0))
		if chat_kin.get("uid", "") == rec["uid"]:
			_chat_bubble("assistant", reply)
			if offline and not chat_offline_noted and is_instance_valid(chat_hist):
				chat_offline_noted = true
				_toast(_offline_reason())
		var loves_chat: bool = rec["likes"]["play"] == "chat"
		Care.change(rec, "joy", 6.0 if loves_chat else 2.0)
		if loves_chat and Care.discover(rec, "play"): _toast("%s loves chatting with you" % rec["name"])
		# talking builds a little trust, once per match
		if int(rec.get("talked", -1)) != int(Save.d["matches"]):
			rec["talked"] = int(Save.d["matches"])
			Save.remember(rec, "talked", "had a chat with you at home", 2.0)
			Save.save_game()
			if Bridge.ai_ok and rec["uid"] == Save.d.get("active", "") and not rec.has("lines"):
				Bridge.refresh_lines(rec), "default")

func _offline_reason() -> String:
	match Bridge.last_err:
		"no_page": return "%s answers on their own here. In the web version they talk through Claude." % chat_kin.get("name", "Your kin")
		"not_granted": return "Claude isn't allowed on this page yet, so %s answers on their own." % chat_kin.get("name", "Your kin")
		"rate_limited": return "Claude is busy for a moment, so %s answered on their own." % chat_kin.get("name", "Your kin")
	return "Couldn't reach Claude, so %s answered on their own." % chat_kin.get("name", "Your kin")

# ---- expedition
var exp_cls := ""
var exp_mode := "solo"
var exp_tier := 0

func _weapon() -> String:
	return Data.weapon_for(Data.class_of_save(), String(Save.d.get("weapon", "")))

func _open_expedition() -> void:
	_day1("portal")
	var v := _new_panel("Expedition", 900, true)
	var cur_c := Data.class_of_save()
	var cols := UI.hbox(18)
	v.add_child(cols)
	# left: who you are (class, weapon, kin)
	var left := UI.vbox(8); left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	left.add_child(UI.section("Class"))
	var crow := UI.hbox(6)
	for c in ["light", "medium", "heavy"]:
		var cd: Dictionary = Data.CLASSES[c]
		var ck: String = c
		var cb := UI.choice(String(cd["name"]), c == cur_c, func():
			Save.d["cls"] = ck
			Save.d["weapon"] = Data.CLASSES[ck]["weapon"]
			Save.save_game()
			_refresh_player_model()
			_open_expedition(), 120)
		cb.tooltip_text = "%d health  ·  %d dash%s\n%s" % [cd["hp"], cd["dashes"], "es" if cd["dashes"] > 1 else "", cd["desc"]]
		crow.add_child(cb)
	left.add_child(crow)
	var ccd: Dictionary = Data.CLASSES[cur_c]
	var cl := UI.label("%d health  ·  %d dash%s  ·  %s" % [ccd["hp"], ccd["dashes"], "es" if ccd["dashes"] > 1 else "", "light frame" if cur_c == "light" else ("hard to push" if cur_c == "heavy" else "all-rounder")], 13, ccd["color"])
	cl.autowrap_mode = TextServer.AUTOWRAP_OFF
	left.add_child(cl)
	left.add_child(UI.section("Weapon"))
	var wr := UI.hbox(6)
	var cur_w := _weapon()
	for w in ccd["weapons"]:
		var wd: Dictionary = Data.weapon_stats(w)
		var wk: String = w
		var wb := UI.choice(String(wd["name"]), w == cur_w, func():
			Save.d["weapon"] = wk
			Save.save_game()
			_refresh_player_model()
			_open_expedition(), 120)
		var wu := Content.weapon(w)
		var un: String = Content.ability(wu.utility).display_name if wu and wu.utility != "" and Content.ability(wu.utility) else ""
		var stat_s := ("Melee: %s damage per hit, reach %.1f" % [str(snappedf(float(wd["dmg"]), 0.1)), float(wd["range"])]) if wd.get("melee", false) else ("%s damage%s, %d per mag, range %d" % [str(snappedf(float(wd["dmg"]), 0.1)), (" x%d" % int(wd["pellets"])) if wd.has("pellets") else "", int(wd["mag"]), int(wd["range"])])
		wb.tooltip_text = (String(wd.get("desc", "")) + "\n" if wd.has("desc") else "") + stat_s + ("\nRight click: " + un if un != "" else "")
		wr.add_child(wb)
	left.add_child(wr)
	var wdef := Content.weapon(cur_w)
	var ud: AbilityDef = Content.ability(wdef.utility) if wdef and wdef.utility != "" else null
	if ud:
		var ul := UI.label("Right click: %s" % ud.display_name, 13, UI.MUTED)
		ul.tooltip_text = ud.desc
		ul.mouse_filter = Control.MOUSE_FILTER_PASS
		left.add_child(ul)
	var ak := Save.active_kin()
	if not ak.is_empty():
		left.add_child(UI.section("Kin you bring"))
		left.add_child(_kin_pick_row("Partner", ak, "active"))
		if Match.TWO_KIN and Save.d["roster"].size() > 1:
			left.add_child(_kin_pick_row("Second", Save.second_kin(), "active2"))
		if float(ak["trust"]) < 30.0:
			var tl := UI.label("%s doesn't trust you much yet and may refuse risky throws." % ak["name"], 13, UI.BAD)
			tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			left.add_child(tl)
	if Save.d.get("treat", "") != "":
		left.add_child(UI.label("Treat: " + _treat_name(Save.d["treat"]), 13, UI.GOLD))
	hecon.loadout_rows(left, _open_expedition)
	# right: where you're going and how
	var right := UI.vbox(8); right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	right.add_child(UI.section("Where"))
	var tiers := UI.vbox(6)
	var ex := int(Save.d.get("extracts", 0))
	for i in Data.TIERS.size():
		var td: Dictionary = Data.TIERS[i]
		var locked := ex < int(td["unlock"])
		var ti := i
		var label_t: String = td["name"]
		if locked:
			label_t = "%s  ·  make it out %d more time%s" % [td["name"], int(td["unlock"]) - ex, "" if int(td["unlock"]) - ex == 1 else "s"]
		var b := UI.choice(label_t, exp_tier == i and not locked, func(): exp_tier = ti; _open_expedition())
		b.disabled = locked
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		tiers.add_child(b)
	right.add_child(tiers)
	var tsel: Dictionary = Data.TIERS[exp_tier]
	var tdl := UI.label(tsel["desc"], 13, UI.BAD if tsel["risk_kin"] else UI.MUTED)
	tdl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(tdl)
	right.add_child(UI.section("Match"))
	var modes := UI.hbox(6)
	for m in [["solo", "Solo"], ["duo", "Duos"], ["trio", "Trios"]]:
		var mk: String = m[0]
		var b := UI.choice(m[1], exp_mode == mk, func(): exp_mode = mk; _open_expedition(), 90)
		b.tooltip_text = {"solo": "20 hunters, every one for themselves", "duo": "10 squads of two", "trio": "7 squads of three"}[mk]
		modes.add_child(b)
	right.add_child(modes)
	if not ak.is_empty():
		var risk := UI.label("Go down for good and the kin you bring are left behind (the Ransom House holds the unclaimed ones).", 12, UI.MUTED)
		risk.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		right.add_child(risk)
	# bottom: go
	var go := UI.hbox(10)
	var start_b := UI.primary("Start expedition", _confirm_start, 240)
	go.add_child(start_b)
	go.add_child(UI.button("Training area", _start_training, 170))
	go.add_child(UI.button("Duel room", _start_duel, 150))
	if Bridge.net_available():
		go.add_child(UI.button("Play online with friends", func(): Game.goto("lobby", {"cls": Data.class_of_save(), "tier": exp_tier}), 240))
	v.add_child(go)
	start_b.grab_focus.call_deferred()

## The old separate loadout page now lives inside the expedition panel.
func _open_loadout() -> void:
	_open_expedition()

## One row of the expedition loadout: which kin, with ‹ › to change it.
func _kin_pick_row(label_t: String, rec: Dictionary, key: String) -> Control:
	var card := UI.card(UI.CARD, 10, 10)
	var row := UI.hbox(10); card.add_child(row)
	var roster: Array = Save.d["roster"]
	var other := str(Save.d.get("active2" if key == "active" else "active", ""))
	var choices: Array = roster.filter(func(r): return r["uid"] != other)
	var cur := str(Save.d.get(key, ""))
	var cycle := func(dir: int) -> void:
		var ids: Array = choices.map(func(r): return r["uid"])
		if key == "active2": ids.append("none")
		var i := ids.find(cur)
		Save.d[key] = ids[(i + dir + ids.size()) % ids.size()] if ids.size() > 0 else cur
		Save.save_game()
		_open_expedition()
	row.add_child(UI.button("‹", func(): cycle.call(-1), 40))
	var info := UI.vbox(2); info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if rec.is_empty():
		info.add_child(UI.label("%s: none" % label_t, 16, UI.MUTED, UI.big))
		info.add_child(UI.label("Bring only your partner. Nothing else at risk.", 12, UI.MUTED))
	else:
		var sp: Dictionary = Data.KIN[rec["species"]]
		var nl := UI.label("%s the %s" % [rec["name"], sp["name"]], 16, sp["color"], UI.big)
		nl.autowrap_mode = TextServer.AUTOWRAP_OFF
		nl.clip_text = true
		info.add_child(nl)
		var sl := UI.label("%s  ·  level %d  ·  trust %d" % [label_t, int(rec.get("level", 1)), int(rec["trust"])], 12, UI.MUTED)
		sl.autowrap_mode = TextServer.AUTOWRAP_OFF
		info.add_child(sl)
		var names: Array = []
		for aid in sp.get("abilities", []):
			var ad := Content.ability(String(aid))
			if ad: names.append(ad.display_name)
		var ud := Content.ultimate(String(sp.get("ultimate", "")))
		var keys := ("%s / %s" % [Settings.key_cap("signature"), Settings.key_cap("ultimate")]) if key == "active" else ("swap in with %s" % Settings.key_cap("swap_kin"))
		var al := UI.label("%s  ·  %s  ·  bond: %s" % [keys, ", ".join(names), ud.display_name if ud else "-"], 12, UI.MUTED)
		al.autowrap_mode = TextServer.AUTOWRAP_OFF
		al.clip_text = true
		al.tooltip_text = al.text
		al.mouse_filter = Control.MOUSE_FILTER_PASS
		info.add_child(al)
	row.add_child(info)
	row.add_child(UI.button("›", func(): cycle.call(1), 40))
	return card

# ---- the Ransom House
var ransom_tab := "house"
var ransom_say := {}      # uid -> the last thing the seller said
var ransom_bid := {}      # uid -> the offer you're typing

func _open_ransom() -> void:
	var v := _new_panel("Ransom House", 820)
	var lost: Array = Save.d.get("lost_kin", [])
	var at_house: Array = lost.filter(func(L): return String(L["where"]) == "ransom")
	var held: Array = lost.filter(func(L): return String(L["where"]) == "rival")
	var offers: Array = Save.d.get("offers", [])
	var intro := UI.label("%s keeps the kin nobody came back for. Lost kin wait here for %d expeditions before they're sold on. Rivals who collected yours will listen to an offer, or you can find them out there and take it back." % [Ransom.BROKER, Ransom.SELL_AFTER], 14, UI.MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(intro)
	var tabs := UI.hbox(8)
	for tb in [["house", "At the house (%d)" % at_house.size()], ["rivals", "Held by rivals (%d)" % held.size()], ["offers", "Offers for you (%d)" % offers.size()], ["log", "What happened"]]:
		var tid: String = tb[0]
		tabs.add_child(UI.choice(tb[1], ransom_tab == tid, func(): ransom_tab = tid; _open_ransom()))
	v.add_child(tabs)
	v.add_child(UI.label("You have %d gems." % int(Save.d["gems"]), 15, UI.GOLD))
	match ransom_tab:
		"house", "rivals":
			var list: Array = at_house if ransom_tab == "house" else held
			if list.is_empty():
				v.add_child(UI.label("Nobody here. Every kin you've lost is home or with a rival." if ransom_tab == "house" else "No rival is holding any of your kin.", 15, UI.MUTED))
			for L in list:
				v.add_child(_ransom_card(L))
		"offers":
			if offers.is_empty():
				v.add_child(UI.label("When you take home a kin a rival left behind, they may ask to buy it back. Their offers show up here.", 15, UI.MUTED))
			for o in offers.duplicate():
				var k := Save.kin(String(o["uid"]))
				if k.is_empty():
					(Save.d["offers"] as Array).erase(o)
					continue
				var card := UI.card(UI.CARD, 12, 12)
				var row := UI.hbox(10); card.add_child(row)
				var info := UI.vbox(3); info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				info.add_child(UI.label("%s wants %s back" % [o["from"], k["name"]], 17, Data.KIN[k["species"]]["color"], UI.big))
				info.add_child(UI.label("They're offering %d gems. It's level %d and its trust in you is %d." % [int(o["gems"]), int(k.get("level", 1)), int(k["trust"])], 13, UI.MUTED))
				row.add_child(info)
				var oo: Dictionary = o
				row.add_child(UI.primary("Sell for %d" % int(o["gems"]), func():
					Ransom.sell_back(oo)
					Sfx.play("pickup")
					_toast("%s goes back to %s. +%d gems" % [k["name"], oo["from"], int(oo["gems"])])
					_refresh_top()
					_open_ransom(), 150))
				row.add_child(UI.button("Keep it", func():
					Ransom.decline(oo)
					_open_ransom(), 100))
				v.add_child(card)
		"log":
			var lg: Array = Save.d.get("ransom_log", [])
			if lg.is_empty():
				v.add_child(UI.label("Nothing yet.", 15, UI.MUTED))
			for i in range(lg.size() - 1, maxi(-1, lg.size() - 13), -1):
				v.add_child(UI.label("Expedition %d: %s" % [int(lg[i]["m"]), lg[i]["text"]], 13, UI.INK))

func _ransom_card(L: Dictionary) -> Control:
	var rec: Dictionary = L["rec"]
	var uid := String(rec["uid"])
	var sp: Dictionary = Data.KIN[rec["species"]]
	var rival_side := String(L["where"]) == "rival"
	var card := UI.card(UI.CARD, 12, 12)
	UI.set_card_border(card, sp["color"])
	var v := UI.vbox(6); card.add_child(v)
	var top := UI.hbox(10)
	var nm := UI.label("%s the %s  ·  level %d" % [rec["name"], sp["name"], int(rec.get("level", 1))], 18, sp["color"], UI.big)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nm)
	top.add_child(UI.label("Asking %d" % int(L["ask"]), 16, UI.GOLD, UI.big))
	v.add_child(top)
	var waited := int(L.get("waited", 0))
	var where := ("Held by %s for %d expedition%s. You may meet them out there: your bond lets you sense it nearby." % [L["holder"], waited, "" if waited == 1 else "s"]) if rival_side else ("Waiting here for %d expedition%s. %s" % [waited, "" if waited == 1 else "s", ("Sold on after %d more." % (Ransom.SELL_AFTER - waited)) if waited < Ransom.SELL_AFTER else "Sold on after your next expedition!"])
	var wl := UI.label(where, 13, UI.BAD if not rival_side and waited >= Ransom.SELL_AFTER - 1 else UI.MUTED)
	wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(wl)
	if ransom_say.has(uid):
		var said := UI.label("%s: \"%s\"" % [L["holder"] if rival_side else Ransom.BROKER, ransom_say[uid]], 14, UI.INK)
		said.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(said)
	var row := UI.hbox(10)
	var bid := int(ransom_bid.get(uid, int(round(float(L["ask"]) * 0.75))))
	var sl := HSlider.new()
	sl.min_value = 0; sl.max_value = maxi(int(L["ask"]), 1); sl.step = 5; sl.value = clampi(bid, 0, int(L["ask"]))
	sl.custom_minimum_size = Vector2(240, 24)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bl := UI.label("Offer %d" % int(sl.value), 15, UI.INK)
	bl.custom_minimum_size.x = 96
	sl.value_changed.connect(func(val): ransom_bid[uid] = int(val); bl.text = "Offer %d" % int(val))
	row.add_child(sl)
	row.add_child(bl)
	var patience := int(L.get("patience", 0))
	var ob := UI.button("Make offer", func():
		var res := Ransom.offer(L, int(ransom_bid.get(uid, int(sl.value))))
		ransom_say[uid] = String(res["line"])
		if res["result"] == "accept":
			Sfx.play("unlock")
			_toast("%s is coming home!" % rec["name"])
			ransom_say.erase(uid)
		elif res["result"] == "counter":
			ransom_bid[uid] = int(res["ask"])
		_refresh_top()
		_open_ransom(), 130)
	ob.disabled = patience <= 0
	ob.tooltip_text = "They've stopped haggling until after your next expedition." if patience <= 0 else "%d more tries before they stop haggling" % patience
	row.add_child(ob)
	var pay := UI.primary("Pay %d" % int(L["ask"]), func():
		if Ransom.pay(L):
			Sfx.play("unlock")
			_toast("%s is coming home!" % rec["name"])
			ransom_say.erase(uid)
			_refresh_top()
			_open_ransom()
		else:
			_toast("You need %d gems" % int(L["ask"])), 130)
	pay.disabled = int(Save.d["gems"]) < int(L["ask"])
	row.add_child(pay)
	v.add_child(row)
	return card

## A safe island to learn every button: nothing can hurt you and nothing you do there counts.
func _start_training() -> void:
	Save.d["cls"] = Data.class_of_save()
	Save.save_game()
	Game.start_match({"training": true, "teams": 1, "squad": 1, "tier": 0, "length": 1e9, "seed": 4242})

## The duel room: you against one sparring bot you set up yourself.
func _start_duel() -> void:
	Save.d["cls"] = Data.class_of_save()
	Save.save_game()
	Game.start_match(Match.duel_opts())

## Before a run where kin can be lost, say so plainly and make the player confirm.
func _confirm_start() -> void:
	var weak := hecon.refuse_reason()
	if weak != "":
		var wv := _new_panel("Too hungry to go", 560)
		var wl := UI.label(weak, 15, UI.INK); wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		wv.add_child(wl)
		var wr := UI.hbox(10)
		wr.add_child(UI.primary("Feed it", func(): _open_feed(Save.active_kin()), 160))
		wr.add_child(UI.button("Back", _open_expedition, 140))
		wv.add_child(wr)
		return
	var td: Dictionary = Data.TIERS[exp_tier]
	if not td.get("risk_kin", false):
		_start_match()
		return
	var v := _new_panel("Your kin can be lost", 640)
	var names: Array = []
	for rec in Save.d.get("roster", []):
		if rec.get("uid", "") in [Save.d.get("active", ""), Save.d.get("active2", "")]:
			names.append(String(rec.get("name", "your kin")))
	var who := " and ".join(names) if not names.is_empty() else "the kin you bring"
	var lines := ["In %s, if you die, %s drop into your deathbox. Anyone who loots it takes them, and a rival who gets them out keeps them." % [td["name"], who]]
	if td.get("loose_capture", false):
		lines.append("Kin out of your hands (thrown or fighting) can also be captured while you're dead.")
	lines.append("If a rival takes your kin you can chase them down in the match (they're marked and you're faster heading their way), get a teammate to bring you back at your box, or ask for them back after the run.")
	for ln in lines:
		var l := UI.label(ln, 15, UI.INK)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)
	var row := UI.hbox(10)
	row.add_child(UI.primary("I understand, go", _start_match, 220))
	row.add_child(UI.button("Back", _open_expedition, 140))
	v.add_child(row)

func _start_match() -> void:
	Save.d["cls"] = Data.class_of_save()
	Save.save_game()
	# about 20 hunters a match, whatever the squad size (your squadmates are bots)
	var o := {"teams": Data.MATCH_PLAYERS, "squad": 1}
	match exp_mode:
		"duo": o = {"teams": Data.MATCH_PLAYERS / 2, "squad": 2}
		"trio": o = {"teams": int(ceil(Data.MATCH_PLAYERS / 3.0)), "squad": 3}
	o["total"] = Data.MATCH_PLAYERS
	o["tier"] = exp_tier
	o["kit_items"] = Econ.begin_raid()      # the armory loadout rides with you
	Save.save_game()
	Game.start_match(o)

# ---- evolution
## Kin that grew during the last expedition change in front of you when you get home.
func _play_evolutions() -> void:
	if building_now or panel_open != "":
		return
	var k: Dictionary = {}
	for kk in kins:
		if kk["rec"].get("pending_evo", []).size() > 0 and not kk.has("indoors"):
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
		if k.has("say") and is_instance_valid(k["say"]):
			n.remove_child(k["say"]); nn.add_child(k["say"])
		k.erase("bubble")
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
		"armory": return "Open the armory  ·  %d stored" % Econ.armory().size()
		"shrine": return "Visit the Soul Shrine"
	return "Visit the %s" % Data.BUILDINGS[b]["name"]

func _open_lot(b: String) -> void:
	var bd: Dictionary = Data.BUILDINGS[b]
	if lots[b]["built"]:
		if b == "hall":
			_open_hall()
			return
		if b == "board":
			_open_challenges()
			return
		if b == "ransom":
			_open_ransom()
			return
		if b == "armory":
			hecon.open_armory()
			return
		if b == "shrine":
			hecon.open_shrine()
			return
		var v := _new_panel(bd["name"], 480)
		v.add_child(UI.label(bd["desc"], 16))
		if b in ["cottage", "cottage2"]:
			_close_panel()
			Game.goto("interior", {"room": b})
			return
		if false:
			var resting: Array = []
			for rec in Save.d["roster"]:
				if rec["uid"] != Save.d.get("active", ""): resting.append(rec["name"])
			v.add_child(UI.label(("Resting here: " + ", ".join(resting)) if resting.size() > 0 else "Nobody's resting here right now. Kin who aren't your partner sleep here.", 15, UI.MUTED))
		return
	if b == "shrine":
		hecon.open_shrine_lot()
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

var wedge_t := 0.0

## Moves you (and any kin) to the nearest open ground if something has boxed you in.
func unstick() -> void:
	var p2 := world.free_spot_near(ppos, [], 1.0, 0.5)
	if p2.distance_to(ppos) > 0.05:
		ppos = Vector3(p2.x, ppos.y, p2.z)
		if player: player.position = ppos
	for k in kins:
		var kp: Vector3 = k["pos"]
		if not world._fits(kp.x, kp.z, 0.35) or not world.roomy(int(floor(kp.x)), int(floor(kp.z))):
			var np := world.free_spot_near(kp, [ppos], 1.2, 0.4)
			k["pos"] = np
			k["goal"] = Vector3.INF
			(k["node"] as Node3D).position = np

## Builds a building on its lot: the site packs away and the building pops up with dust and hammering.
func _construct(b: String) -> void:
	building_now = true
	var l: Dictionary = lots[b]
	var holder: Node3D = l["node"]
	var rc: Array = Data.BUILDINGS[b]["rect"]
	world.set_block_rect(rc[0], rc[1], rc[2], rc[3])
	# step the player and any kin out of the footprint (and away from its walls)
	unstick()
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
	var need := 0 if Game.modding() else int(isd["need"])
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

# ---- class and loadout
func _refresh_player_model() -> void:
	var at := player.position
	var rot := player.rotation
	player.queue_free()
	var w := _weapon()
	player = Models.hunter(Data.class_of_save(), Data.TEAM_COLORS[0], w, "", Save.d.get("look", {}))
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
	v.add_child(UI.primary("Go inside %s's house" % owner_name, func(): Game.goto("interior", {"room": "house", "visit": visit, "visit_id": visit_id}), 300))
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

# ------------------------------------------------------------------ raising: needs, care, training, eggs
const YARD_AT := Vector3(40.9, 0, 32.7)
const YARD_KIN := Vector3(40.6, 0, 32.9)
const NEST_AT := Vector3(34.4, 0, 33.7)    # the Nesting Nook, between the market stall and the pond
const POND_EDGE := Vector3(35.7, 0, 37.4)
var care_acc := 0.0
var care_save := 0.0
var yard: Node3D = null
var nest: Node3D = null
var train := {}                 # the training session in progress
var train_bar: Control = null
var train_lbl: Label = null
var train_draw: Control = null

## Builds the yard and the nest, and catches every kin up on the time you were away.
func _setup_care() -> void:
	yard = Models.training_yard()
	yard.position = YARD_AT
	add_child(yard)
	# the Nesting Nook: where two close kin leave an egg
	var nook := Models.nesting_nook()
	nook.position = NEST_AT
	add_child(nook)
	var nl := Label3D.new()
	nl.text = "Nesting Nook"; nl.font = UI.big; nl.font_size = 40; nl.pixel_size = 0.008; nl.outline_size = 10
	nl.modulate = Color("ffc0d0"); nl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	nl.position = NEST_AT + Vector3(0, 2.95, -0.7)
	add_child(nl)
	if not visit.is_empty():
		return
	# the time you were away: needs drift, kin eat from the feeders, and hungry ones may starve
	hecon.away = Econ.catch_up_all()
	if hecon.away.any(func(e): return e["kind"] == "died"):
		_spawn_kin()
	Care.dex_sync()
	_refresh_nest()

func _refresh_nest() -> void:
	if is_instance_valid(nest):
		nest.queue_free()
	nest = null
	var egg: Dictionary = Save.d.get("egg", {})
	if egg.is_empty() or not visit.is_empty():
		return
	var col: Color = Data.KIN[_egg_species()]["color"] if _egg_species() != "" else Color("f2e6cf")
	nest = Models.nest_egg(col, Color("fff6c0"))
	nest.position = NEST_AT
	add_child(nest)

## The species in the nest egg ("" if none). Older saves didn't store it: fall back to parent A.
func _egg_species() -> String:
	var egg: Dictionary = Save.d.get("egg", {})
	if egg.is_empty():
		return ""
	var sp := String(egg.get("sp", ""))
	if sp == "" or not Data.KIN.has(sp):
		var a := Save.kin(String(egg.get("a", "")))
		sp = String(a.get("species", ""))
	return sp if Data.KIN.has(sp) else ""

func _egg_label() -> String:
	var sp := _egg_species()
	return Data.egg_name(sp) if sp != "" else "egg"

func _egg_ready() -> bool:
	var egg: Dictionary = Save.d.get("egg", {})
	if egg.is_empty():
		return false
	return int(Save.d["matches"]) >= int(egg.get("m", 0)) or Time.get_unix_time_from_system() >= float(egg.get("t", 0.0))

## Needs drift every second; kin asleep in bed (or napping) get their energy back.
func _care_tick(d: float) -> void:
	if not visit.is_empty():
		return
	care_acc += d
	care_save += d
	if care_acc >= 1.0:
		var night := sin((day_t - 0.25) * TAU) < -0.2
		for k in kins:
			var rec: Dictionary = k["rec"]
			var in_bed: bool = k.has("bed") and Vector2(k["pos"].x - k["bed"].x, k["pos"].z - k["bed"].z).length() < 0.6
			Care.tick(rec, care_acc, float(k.get("nap_t", 0.0)) > 0.0 or (night and in_bed) or k.has("indoors"))
		care_acc = 0.0
	if care_save > 20.0:
		care_save = 0.0
		Save.save_game()
	# a little life: an egg wobbles when it's close, dusty kin shed a little dust
	if is_instance_valid(nest) and _egg_ready():
		var sh: Node3D = nest.get_node("Shell")
		sh.rotation.z = sin(Time.get_ticks_msec() / 90.0) * 0.12 * (1.0 if fmod(Time.get_ticks_msec() / 1000.0, 3.0) < 0.6 else 0.0)

## The thought bubble over each kin: what it wants, shown now and then rather than all the time.
func _update_bubbles(d: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var shown: Array = []
	for k in kins:
		var rec: Dictionary = k["rec"]
		if not k.has("bubble"):
			var b := Models.want_bubble()
			b.position = Vector3(0.25, 1.45, 0)
			b.visible = false
			(k["node"] as Node3D).add_child(b)
			k["bubble"] = b
		var bub: Node3D = k["bubble"]
		if not is_instance_valid(bub):
			k.erase("bubble")
			continue
		var w := Care.want(rec) if visit.is_empty() else ""
		var cyc := fmod(now + float(absi(String(rec["uid"]).hash()) % 97) * 0.1, 9.0) < 3.6
		var show: bool = w != "" and cyc and not k.get("busy", false) and not k.has("fetch") and float(k.get("nap_t", 0.0)) <= 0.0 and float(k.get("say_t", 0.0)) <= 0.0
		if show:
			for p in shown:
				if Vector2(p.x - k["pos"].x, p.z - k["pos"].z).length() < 2.6 or _talking_near(k, 2.6):
					show = false; break
		if show: shown.append(k["pos"])
		bub.visible = show
		if show:
			for nm in ["food", "energy", "clean", "joy"]:
				(bub.get_node(nm) as Node3D).visible = nm == w
			bub.position.y = 1.45 + sin(now * 2.2) * 0.04
			# face the camera like a cartoon thought bubble
			bub.look_at(cam.global_position, Vector3.UP)
			bub.scale = Vector3.ONE * 1.4
		# dusty kin shed a little dust as they go
		if visit.is_empty() and Care.need(rec, "clean") < 22.0 and randf() < d * 0.4:
			fx.dust(k["pos"], 3)
		# saying hello when you walk up to it
		k["hi_cd"] = float(k.get("hi_cd", 0.0)) - d
		if visit.is_empty() and float(k["hi_cd"]) <= 0.0 and panel_open == "" and not chat_open and train.is_empty() and not k.get("busy", false):
			if Vector2(ppos.x - k["pos"].x, ppos.z - k["pos"].z).length() < 2.0:
				k["hi_cd"] = randf_range(18.0, 30.0)
				if randf() < 0.5 and float(k.get("nap_t", 0.0)) <= 0.0:
					var trust := float(rec["trust"])
					if Care.speech(rec) < 3:
						_say(k, KinSpeak.say(rec, "sad" if trust < 30.0 else ("question" if w != "" else "happy"), w if w != "" else ("cold" if trust < 30.0 else "")), 2.8, false)
					else:
						_say(k, _greeting(rec), 2.8, false)

## Gentle routines driven by how it's feeling. Returns true if it chose where to go.
func _care_goal(k: Dictionary) -> bool:
	var rec: Dictionary = k["rec"]
	if not visit.is_empty():
		return false
	if Care.need(rec, "energy") < 22.0 and k.has("bed"):
		k["goal"] = k["bed"]
		k["nap_go"] = true
		return true
	if hecon and hecon.feed_goal(k):
		return true      # off to a feeder
	if Care.need(rec, "food") < 30.0 and randf() < 0.4:
		k["goal"] = _seat(k, spots["pot"], 1.4)
		k["stare"] = spots["pot"]
		return true
	if Care.need(rec, "joy") < 30.0 and randf() < 0.6 and world.island_of(ppos.x, ppos.z) == world.island_of(k["pos"].x, k["pos"].z):
		k["goal"] = _seat(k, ppos, 1.4)
		return true
	return false

## Per-frame care states: napping, bathing, staring at the pot.
func _care_step(k: Dictionary, d: float) -> void:
	if hecon and hecon.feed_step(k, d):
		return
	var rec: Dictionary = k["rec"]
	var pos: Vector3 = k["pos"]
	if float(k.get("nap_t", 0.0)) > 0.0:
		k["nap_t"] = float(k["nap_t"]) - d
		k["goal"] = pos
		k["z_t"] = float(k.get("z_t", 0.0)) - d
		if float(k["z_t"]) <= 0.0:
			k["z_t"] = 2.2
			_emote(k, "z")
		k["slept"] = float(k.get("slept", 0.0)) + d
		if float(k["nap_t"]) <= 0.0:
			Care.change(rec, "energy", 40.0 * clampf(float(k["slept"]) / 30.0, 0.0, 1.0))
			k["slept"] = 0.0
			Care.change(rec, "joy", 4.0)
			k["t"] = 1.0
			_emote(k, "!")
		return
	if k.get("nap_go", false) and k.has("bed") and Vector2(pos.x - k["bed"].x, pos.z - k["bed"].z).length() < 0.5:
		k.erase("nap_go"); k.erase("nap_go_t")
		k["slept"] = 0.0
		k["nap_t"] = 30.0
		k["z_t"] = 0.5
	if k.has("stare") and Vector2(pos.x - k["goal"].x, pos.z - k["goal"].z).length() < 0.5:
		var at: Vector3 = k["stare"]
		k.erase("stare")
		k["hold_t"] = 3.0
		_emote(k, "?")
		(k["node"] as Node3D).rotation.y = atan2(-(at.x - pos.x), -(at.z - pos.z))
	if k.has("bath"):
		var b: Dictionary = k["bath"]
		if b["phase"] == "go":
			k["goal"] = POND_EDGE
			b["t"] = float(b["t"]) + d
			if Vector2(pos.x - POND_EDGE.x, pos.z - POND_EDGE.z).length() < 0.6 or float(b["t"]) > 10.0:
				b["phase"] = "splash"; b["t"] = 3.0
				Sfx.play("plant", POND_EDGE, -4.0, 0.1, 1.4)
		else:
			k["goal"] = pos
			b["t"] = float(b["t"]) - d
			k["hop"] = float(k["hop"]) + d * 14.0
			if randf() < d * 6.0:
				fx.burst(pos + Vector3(randf_range(-0.3, 0.3), 0.5, randf_range(-0.3, 0.3)), Color("8fd0ff"), 6, 2.2, 0.4)
			if float(b["t"]) <= 0.0:
				k.erase("bath")
				_finish_bath(k)

## Speed multiplier for a tired kin.
func _care_speed(rec: Dictionary) -> float:
	return (0.7 if Care.need(rec, "energy") < 25.0 else 1.0) * (0.7 if Care.starve_h(rec) >= Care.STARVE["weak"] else 1.0)

# ---- care actions, from the kin's card; they play out in the world, not in a menu
func _care_start(k: Dictionary) -> bool:
	if k.is_empty():
		return false
	_close_panel()
	k.erase("chase"); k.erase("task"); k.erase("stare"); k.erase("nap_go"); k.erase("eat")
	k["nap_t"] = 0.0
	return true

func _care_feed(rec: Dictionary, f: String) -> void:
	var k := _kin_entry(rec)
	if not _care_start(k):
		return
	var have := int(Save.d["crops"].get(f, 0)) if Data.CROPS.has(f) else int(Save.d["items"].get(f, 0))
	if have <= 0:
		return
	# it comes over to you and you put the food down in front of it
	var at := ppos + Vector3(sin(pface) * -1.0, 0, cos(pface) * -1.0)
	if world.is_void(at.x, at.z) or world.is_block(at.x, at.z): at = ppos + Vector3(0.9, 0, 0.4)
	k["pos"] = at
	(k["node"] as Node3D).position = at
	k["hold_t"] = 3.2
	_face(at)
	var food := MeshInstance3D.new()
	food.mesh = Models.sphere(0.11, 10)
	food.material_override = Models.toon(Care.food_col(f))
	var fp := at + Vector3((ppos.x - at.x) * 0.35, 0.12, (ppos.z - at.z) * 0.35)
	food.position = fp
	add_child(food)
	(k["node"] as Node3D).rotation.y = atan2(-(fp.x - at.x), -(fp.z - at.z))
	var res := Care.feed(rec, f)
	if res["ok"]:
		# taken out of the pantry now, so two quick feeds can't both use the last one
		if Data.CROPS.has(f): Save.d["crops"][f] = int(Save.d["crops"][f]) - 1
		else: Save.d["items"][f] = int(Save.d["items"][f]) - 1
	var body: Node3D = (k["node"] as Node3D).get_node("Body")
	var tw := create_tween()
	if res["ok"]:
		for i in 3:
			tw.tween_property(body, "scale", Vector3(1.12, 0.86, 1.12), 0.14)
			tw.tween_property(body, "scale", Vector3.ONE, 0.14)
			tw.tween_callback(func(): fx.burst(fp, Care.food_col(f), 4, 1.2, 0.3); Sfx.play("pickup", fp, -16.0, 0.1, 1.4))
		tw.tween_callback(func(): food.queue_free())
	else:
		# a sniff, then a firm no
		tw.tween_interval(0.4)
		var n: Node3D = k["node"]
		var r0 := n.rotation.y
		for i in 3:
			tw.tween_property(n, "rotation:y", r0 + 0.5, 0.08)
			tw.tween_property(n, "rotation:y", r0 - 0.5, 0.08)
		tw.tween_property(n, "rotation:y", r0, 0.08)
		tw.tween_interval(0.6)
		tw.tween_callback(func(): food.queue_free())
	tw.tween_callback(func(): _after_feed(k, f, res))

func _after_feed(k: Dictionary, f: String, res: Dictionary) -> void:
	var rec: Dictionary = k["rec"]
	var nm: String = rec["name"]
	if res["hate"]:
		_say(k, KinSpeak.say(rec, "angry", "mean") if Care.speech(rec) < 3 else "Ugh. No. Not that.", 3.0)
		if res["new"]: _toast("You found out %s won't eat %s" % [nm, Care.food_name(f)])
		return
	if res["full"] and not res["ok"]:
		_say(k, KinSpeak.say(rec, "content", "full") if Care.speech(rec) < 3 else "I'm full, thanks!", 3.0)
		return
	if Data.CROPS.has(f):
		for af in Evo.AFF:
			if Evo.AFF[af]["food"] == f: Evo.add(rec, af, 6.0)
	if res["love"]:
		k["joy_t"] = 1.2
		_emote(k, "♥")
		fx.burst(k["pos"] + Vector3(0, 0.9, 0), Color("ff8fb0"), 16, 2.2)
		Sfx.play("kin_happy", null, -2.0, 0.1)
		_say(k, KinSpeak.say(rec, "love", "love") if Care.speech(rec) < 3 else "My favourite! Thank you!", 3.0)
		if res["new"]: _toast("%s loves %s!" % [nm, Care.food_name(f)])
	else:
		_emote(k, "♪")
		Sfx.play("kin_happy", null, -8.0)
		_say(k, KinSpeak.say(rec, "happy") if Care.speech(rec) < 3 else "Mm, thanks.", 2.4)
	if res.get("hungry", false):
		Save.remember(rec, "fed", "was fed when it was hungry", 2.0)
	elif int(rec.get("fed_m", -1)) != int(Save.d["matches"]):
		rec["fed_m"] = int(Save.d["matches"])
		Save.remember(rec, "fed", "was fed %s by you" % Care.food_name(f).to_lower(), 1.0)
	Save.save_game()
	_refresh_top()

func _care_brush(rec: Dictionary) -> void:
	var k := _kin_entry(rec)
	if not _care_start(k):
		return
	if Vector2(ppos.x - k["pos"].x, ppos.z - k["pos"].z).length() > 1.4:
		k["pos"] = ppos + Vector3(0.9, 0, 0.3)
		(k["node"] as Node3D).position = k["pos"]
	k["hold_t"] = 2.2
	_face(k["pos"])
	var tw := create_tween()
	for i in 5:
		tw.tween_callback(func(): fx.burst(k["pos"] + Vector3(randf_range(-0.2, 0.2), 0.5, randf_range(-0.2, 0.2)), Color("fff6c0"), 5, 1.4, 0.35); Sfx.play("click", null, -18.0, 0.1, 1.6))
		tw.tween_interval(0.32)
	tw.tween_callback(func():
		var clean_before := Care.need(rec, "clean")
		Care.change(rec, "clean", 32.0)
		var loves: bool = rec["likes"]["play"] == "brush"
		Care.change(rec, "joy", 18.0 if loves else 6.0)
		k["joy_t"] = 0.8
		_emote(k, "♥" if loves else "★")
		_say(k, KinSpeak.say(rec, "love" if loves else "content") if Care.speech(rec) < 3 else ("Ooh, that's lovely." if loves else "Thanks, that's better."), 2.6)
		if loves and Care.discover(rec, "play"): _toast("%s loves being brushed" % rec["name"])
		if clean_before < 30.0: Save.remember(rec, "brushed", "got brushed clean when it was a mess", 1.5)
		Save.save_game())

func _care_bath(rec: Dictionary) -> void:
	var k := _kin_entry(rec)
	if not _care_start(k):
		return
	k["bath"] = {"phase": "go", "t": 0.0}
	_emote(k, "!")

func _finish_bath(k: Dictionary) -> void:
	var rec: Dictionary = k["rec"]
	Care.change(rec, "clean", 100.0)
	Care.change(rec, "energy", -4.0)
	var loves: bool = rec["likes"]["play"] == "bath"
	var grumpy: bool = not loves and float(rec["traits"].get("curiosity", 0.5)) < 0.45
	Care.change(rec, "joy", 16.0 if loves else (-5.0 if grumpy else 4.0))
	fx.burst(k["pos"] + Vector3(0, 0.6, 0), Color("8fd0ff"), 18, 3.0, 0.5)
	if loves:
		_emote(k, "♥")
		_say(k, KinSpeak.say(rec, "excited", "love") if Care.speech(rec) < 3 else "Again! Again!", 2.8)
		if Care.discover(rec, "play"): _toast("%s loves baths" % rec["name"])
	elif grumpy:
		_emote(k, "!")
		_say(k, (KinSpeak.babble(rec["species"], "angry") + " (shakes water everywhere)") if Care.speech(rec) < 3 else "Brr. I'm soaked.", 2.8)
	else:
		_emote(k, "★")
	k["t"] = 1.5
	Save.save_game()

func _care_nap(rec: Dictionary) -> void:
	var k := _kin_entry(rec)
	if not _care_start(k):
		return
	if k.has("bed"):
		k["goal"] = k["bed"]
		k["nap_go"] = true
		k["nap_go_t"] = 15.0
	else:
		k["nap_t"] = 30.0
		k["slept"] = 0.0
	_say(k, KinSpeak.say(rec, "sleepy") if Care.speech(rec) < 3 else "Just a little nap...", 2.0)

# ---- training: a timing game at the yard; three rounds, each a little faster
func _start_drill(rec: Dictionary, stat: String) -> void:
	var k := _kin_entry(rec)
	if k.is_empty():
		return
	if Care.need(rec, "energy") < 20.0 or Care.need(rec, "food") < 12.0:
		_close_panel()
		var why := "energy" if Care.need(rec, "energy") < 20.0 else "food"
		_say(k, KinSpeak.say(rec, "sleepy" if why == "energy" else "sad", why), 3.0)
		_toast("%s is too %s to train. %s first" % [rec["name"], "tired" if why == "energy" else "hungry", "Let it nap" if why == "energy" else "Feed it"])
		return
	if int(rec["stats"][stat]) >= Care.stat_cap(rec):
		_toast("%s can't train %s any further until it levels up" % [rec["name"], Care.STATS[stat]["name"]])
		return
	if not _care_start(k):
		return
	k["busy"] = true
	k["pos"] = YARD_KIN
	var n: Node3D = k["node"]
	n.position = YARD_KIN
	var dummy := yard.get_node("Dummy") as Node3D
	var dpos := dummy.global_position
	n.rotation.y = atan2(-(dpos.x - YARD_KIN.x), -(dpos.z - YARD_KIN.z))
	ppos = YARD_KIN + Vector3(-0.6, 0, 1.4)
	player.position = ppos
	_face(YARD_KIN)
	train = {"k": k, "stat": stat, "round": 0, "results": [], "m": 0.0, "dir": 1.0, "speed": 0.85, "zone": randf_range(0.3, 0.7), "wait": 0.0}
	_build_train_bar()
	Sfx.play("whoosh", null, -8.0)

func _build_train_bar() -> void:
	if is_instance_valid(train_bar): train_bar.queue_free()
	var bar := UI.card(Color(0.06, 0.07, 0.1, 0.92), 12, 14)
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.offset_top = -64; bar.offset_bottom = -64
	bar.custom_minimum_size.x = minf(560.0, get_viewport().get_visible_rect().size.x - 32.0)
	var col := UI.vbox(8); bar.add_child(col)
	train_lbl = UI.label("", 15)
	col.add_child(train_lbl)
	train_draw = Control.new()
	train_draw.custom_minimum_size = Vector2(0, 26)
	train_draw.draw.connect(_draw_train)
	col.add_child(train_draw)
	col.add_child(UI.label("Press %s (or click) when the marker is in the gold" % Settings.key_cap("interact"), 12, UI.MUTED))
	root_ui.add_child(bar)
	train_bar = bar
	_train_label()

func _train_label() -> void:
	if not is_instance_valid(train_lbl) or train.is_empty():
		return
	var st: Dictionary = Care.STATS[train["stat"]]
	var res: Array = train["results"]
	var marks := ""
	for r in res: marks += {"great": "  ★", "good": "  ●", "miss": "  ✕"}[r]
	train_lbl.text = "%s  ·  round %d of 3%s" % [st["drill"], mini(int(train["round"]) + 1, 3), marks]
	train_lbl.add_theme_color_override("font_color", st["col"])

func _draw_train() -> void:
	if train.is_empty() or not is_instance_valid(train_draw):
		return
	var w := train_draw.size.x
	var h := train_draw.size.y
	train_draw.draw_rect(Rect2(0, h * 0.3, w, h * 0.4), Color(1, 1, 1, 0.1))
	var z: float = train["zone"]
	train_draw.draw_rect(Rect2(w * (z - 0.16), h * 0.3, w * 0.32, h * 0.4), Color(UI.ACCENT, 0.45))
	train_draw.draw_rect(Rect2(w * (z - 0.06), h * 0.2, w * 0.12, h * 0.6), UI.GOLD)
	var mx := w * float(train["m"])
	train_draw.draw_rect(Rect2(mx - 3, 0, 6, h), UI.INK)

func _train_process(d: float) -> void:
	if train.is_empty():
		return
	if float(train["wait"]) > 0.0:
		train["wait"] = float(train["wait"]) - d
		if float(train["wait"]) <= 0.0 and int(train["round"]) >= 3:
			_finish_training()
		return
	var m := float(train["m"]) + float(train["dir"]) * float(train["speed"]) * d
	if m > 1.0: m = 2.0 - m; train["dir"] = -1.0
	if m < 0.0: m = -m; train["dir"] = 1.0
	train["m"] = m
	if is_instance_valid(train_draw): train_draw.queue_redraw()

func _train_hit() -> void:
	if train.is_empty() or float(train["wait"]) > 0.0:
		return
	var off := absf(float(train["m"]) - float(train["zone"]))
	var r := "great" if off < 0.06 else ("good" if off < 0.16 else "miss")
	train["results"].append(r)
	train["round"] = int(train["round"]) + 1
	train["wait"] = 1.1
	train["speed"] = float(train["speed"]) * 1.35
	train["zone"] = randf_range(0.2, 0.8)
	_train_anim(train["k"], String(train["stat"]), r)
	_train_label()

## What the kin does each round.
func _train_anim(k: Dictionary, stat: String, r: String) -> void:
	var n: Node3D = k["node"]
	var body: Node3D = n.get_node("Body")
	var dummy := yard.get_node("Dummy") as Node3D
	var tw := create_tween()
	var col: Color = Care.STATS[stat]["col"]
	match stat:
		"power":
			var to := YARD_KIN.lerp(dummy.global_position, 0.55)
			tw.tween_property(n, "position", to, 0.12)
			tw.tween_callback(func():
				if r != "miss":
					fx.burst(dummy.global_position + Vector3(0, 1.0, 0), Color("e2c47a"), 12 if r == "great" else 6, 3.0, 0.4)
					Sfx.play("kinhit", dummy.global_position, -6.0)
					var dt := create_tween()
					dt.tween_property(dummy, "rotation:z", 0.35 if r == "great" else 0.18, 0.08)
					dt.tween_property(dummy, "rotation:z", 0.0, 0.3)
				else:
					Sfx.play("whoosh", null, -10.0))
			tw.tween_property(n, "position", YARD_KIN, 0.2)
		"guard":
			tw.tween_property(body, "scale", Vector3(1.2, 0.72, 1.2), 0.12)
			tw.tween_callback(func(): if r != "miss": fx.ring(YARD_KIN, 1.2, col, 0.3); Sfx.play("shield", null, -10.0))
			tw.tween_interval(0.3)
			tw.tween_property(body, "scale", Vector3.ONE, 0.15)
		"speed":
			var hoop := yard.global_position + Vector3(-1.4, 0, 0.2)
			tw.tween_property(n, "position", hoop, 0.18 if r != "miss" else 0.35)
			tw.tween_callback(func(): if r != "miss": fx.burst(hoop + Vector3(0, 0.4, 0), col, 8, 2.5, 0.3))
			tw.tween_property(n, "position", YARD_KIN, 0.18 if r != "miss" else 0.35)
		"focus":
			tw.tween_property(n, "rotation:y", n.rotation.y + TAU, 0.6)
			tw.tween_callback(func(): if r != "miss": fx.burst(YARD_KIN + Vector3(0, 0.5, 0), col, 14 if r == "great" else 7, 1.6, 0.6, -3.0))
	_emote(k, {"great": "★", "good": "♪", "miss": "?"}[r])

func _finish_training() -> void:
	var k: Dictionary = train["k"]
	var rec: Dictionary = k["rec"]
	var stat: String = train["stat"]
	var pts := 0
	for r in train["results"]:
		pts += {"great": 3, "good": 2, "miss": 0}[r]
		if r != "miss" and Save.has_building("dojo"): pts += 1
	var mult := 1.0
	if Care.need(rec, "joy") >= 60.0: mult *= 1.25
	if Care.need(rec, "energy") < 35.0: mult *= 0.7
	var gained := Care.add_stat(rec, stat, int(round(pts * mult)))
	Care.change(rec, "energy", -18.0)
	Care.change(rec, "food", -6.0)
	Care.change(rec, "joy", 4.0 if (train["results"] as Array).has("great") else -2.0)
	var aff: String = {"power": "fierce", "guard": "steadfast", "speed": "swift", "focus": "curious"}[stat]
	Evo.add(rec, aff, 2.0)
	if int(rec.get("trained_m", -1)) != int(Save.d["matches"]):
		rec["trained_m"] = int(Save.d["matches"])
		Save.remember(rec, "trained", "trained %s with you at the yard" % String(Care.STATS[stat]["name"]).to_lower(), 1.0)
	Save.save_game()
	_toast("+%d %s  (%d of %d)" % [gained, Care.STATS[stat]["name"], int(rec["stats"][stat]), Care.stat_cap(rec)] if gained > 0 else "No gain this time. Try again after a rest")
	_say(k, KinSpeak.say(rec, "excited" if gained >= 6 else ("happy" if gained > 0 else "sad")) if Care.speech(rec) < 3 else ("I'm getting stronger!" if gained > 0 else "Again. I'll get it."), 2.6)
	k["busy"] = false
	k["t"] = 1.5
	train = {}
	if is_instance_valid(train_bar): train_bar.queue_free()
	train_bar = null

# ---- eggs: two kin who are close leave an egg in the nest; you hatch and name it
func _can_pair(rec: Dictionary) -> String:
	if not Save.d.get("egg", {}).is_empty(): return "There's already an egg in the nest"
	if int(rec["level"]) < 5: return "Needs to be level 5"
	if float(rec["trust"]) < 50.0: return "Needs a Close bond (trust 50)"
	if int(rec.get("bred_m", -99)) > int(Save.d["matches"]) - 3: return "Needs a few more expeditions' rest"
	if Save.d["roster"].size() >= 12: return "Your farm is full (12 kin)"
	if not Save.d.get("egg", {}).is_empty(): return "There's already an egg in the nest"
	return ""

## The Nesting Nook: choose two kin who are ready, and they leave an egg in the nest.
var nook_pick: Array = []
func _open_nook() -> void:
	var v := _new_panel("Nesting Nook", 600)
	v.add_child(UI.label("Pick two kin who are close. They curl up in the nest together and leave an egg; it mixes their personalities and may take after either parent. It hatches after your next expedition, or in about ten minutes at home.", 14, UI.MUTED))
	if not Save.d.get("egg", {}).is_empty():
		v.add_child(UI.label("There's already a %s in the nest." % _egg_label(), 16, UI.GOLD))
		return
	nook_pick = nook_pick.filter(func(u): return not Save.kin(String(u)).is_empty() and _can_pair(Save.kin(String(u))) == "")
	for o in Save.d["roster"]:
		var why := _can_pair(o)
		var row := UI.hbox(10)
		var picked: bool = nook_pick.has(o["uid"])
		var l := UI.label("%s  ·  Lv %d %s" % [o["name"], int(o["level"]), Evo.form_name(o)], 16, Data.KIN[o["species"]]["color"] if why == "" else UI.MUTED)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if why != "":
			var wl := UI.label(why, 13, UI.MUTED); wl.autowrap_mode = TextServer.AUTOWRAP_OFF
			row.add_child(wl)
		else:
			var uid: String = o["uid"]
			var cb := func():
				if nook_pick.has(uid): nook_pick.erase(uid)
				elif nook_pick.size() < 2: nook_pick.append(uid)
				_close_panel(); _open_nook()
			row.add_child(UI.primary("Picked", cb, 110) if picked else UI.button("Pick", cb, 110))
		v.add_child(row)
	if nook_pick.size() == 2:
		var a := Save.kin(String(nook_pick[0])); var b := Save.kin(String(nook_pick[1]))
		v.add_child(UI.primary("Pair %s and %s" % [a["name"], b["name"]], func():
			nook_pick = []
			_make_egg(a, b), 320))
	else:
		v.add_child(UI.label("Pick %d more." % (2 - nook_pick.size()), 14, UI.MUTED))

func _make_egg(rec: Dictionary, ok: Dictionary) -> void:
	# which parent it takes after is settled now, so the egg can wear that element's name and colour
	var esp: String = rec["species"] if randf() < 0.5 else ok["species"]
	Save.d["egg"] = {"a": rec["uid"], "b": ok["uid"], "sp": esp, "m": int(Save.d["matches"]) + 1, "t": Time.get_unix_time_from_system() + 600.0}
	rec["bred_m"] = int(Save.d["matches"]); ok["bred_m"] = int(Save.d["matches"])
	Save.remember(rec, "egg", "had an egg with %s" % ok["name"], 2.0)
	Save.remember(ok, "egg", "had an egg with %s" % rec["name"], 2.0)
	Save.save_game()
	_close_panel()
	_refresh_nest()
	fx.burst(NEST_AT + Vector3(0, 0.6, 0), Color("ff8fb0"), 24, 3.0)
	Sfx.play("unlock")
	_toast("A %s appeared in the Nesting Nook" % Data.egg_name(esp))

func _open_pair(rec: Dictionary) -> void:
	var v := _new_panel("Pair %s" % rec["name"], 560)
	v.add_child(UI.label("Two kin who are close leave an egg in the Nesting Nook. It hatches after your next expedition (or about ten minutes at home).", 14, UI.MUTED))
	var any := false
	for o in Save.d["roster"]:
		if o == rec or _can_pair(o) != "":
			continue
		any = true
		var row := UI.hbox(10)
		var l := UI.label("%s  ·  Lv %d %s" % [o["name"], int(o["level"]), Evo.form_name(o)], 16, Data.KIN[o["species"]]["color"])
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var ok: Dictionary = o
		row.add_child(UI.primary("Pair them", func(): _make_egg(rec, ok), 150))
		v.add_child(row)
	if not any:
		v.add_child(UI.label("No other kin is ready yet. Partners need level 5, a Close bond and a few expeditions' rest.", 15))

func _hatch_nest_egg() -> void:
	var egg: Dictionary = Save.d.get("egg", {})
	var a := Save.kin(String(egg.get("a", "")))
	var b := Save.kin(String(egg.get("b", "")))
	if a.is_empty() or b.is_empty():
		Save.d["egg"] = {}
		_refresh_nest()
		return
	var rng := RandomNumberGenerator.new(); rng.randomize()
	var baby := Care.breed(a, b, rng, _egg_species())
	Save.d["egg"] = {}
	# it's yours from the moment it hatches; the naming card only renames it
	baby["name"] = Data.KIN_NAMES.pick_random()
	Save.remember(baby, "born", "hatched in the nest on your farm", 0.0)
	Progress.add("hatched")
	Save.d["roster"].append(baby)
	Care.dex_mark(baby["species"], "caught")
	if baby.get("shimmer", false): Care.dex_mark(baby["species"], "shimmer")
	Save.save_game()
	building_now = true
	# the egg hatches in stages: wiggles, cracks, a peek, then the kin pops out
	var shell_c: Color = Color(Data.KIN[baby["species"]]["color"]).lightened(0.15)
	if is_instance_valid(nest):
		nest.get_node("Shell").visible = false
	var eh := EggHatch.new(baby["species"], fx, 0.26, 0.36, 1.0, baby)
	eh.shell_col = shell_c
	eh.spot_col = Color("fff6c0")
	eh.position = NEST_AT
	eh.scale = Vector3.ONE * 1.2
	add_child(eh)
	eh.start()
	var zoom0: float = cam.zoom_to
	cam.zoom_to = 0.5
	eh.done.connect(func():
		var land: Vector3 = eh.kin_node.global_position if is_instance_valid(eh.kin_node) else NEST_AT + Vector3(0.8, 0, 0.6)
		land.y = 0.0
		if is_instance_valid(eh.kin_node): eh.kin_node.queue_free()
		eh.queue_free()
		_refresh_nest()
		building_now = false
		cam.zoom_to = zoom0
		_spawn_kin()
		var ke := _kin_entry(baby)
		if not ke.is_empty():
			ke["pos"] = Vector3(land.x, ke["pos"].y, land.z)
			(ke["node"] as Node3D).position = ke["pos"]
		# the big reveal (flash, fanfare, turntable and info), then naming
		var rv := KinReveal.new(baby["species"], baby)
		add_child(rv)
		panel_open = "reveal"; building_now = true      # hold the hunter still while you turn it round
		rv.proceed.connect(func():
			panel_open = ""; building_now = false
			_name_baby(baby)))

func _name_baby(baby: Dictionary) -> void:
	var sp: Dictionary = Data.KIN[baby["species"]]
	var v := _new_panel("It hatched!", 520)
	v.add_child(UI.label("\"%s\"" % KinSpeak.babble(baby["species"], "happy"), 24, Care.shimmer_col(sp["color"]) if baby.get("shimmer", false) else sp["color"]))
	v.add_child(UI.label("A %s%s, child of %s and %s. %s nature." % ["shimmering " if baby.get("shimmer", false) else "", sp["name"], baby["parents"][0], baby["parents"][1], Care.nature(baby)], 15))
	var row := UI.hbox(8)
	var ne := LineEdit.new(); ne.text = Data.KIN_NAMES.pick_random(); ne.max_length = 14; ne.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ne)
	v.add_child(row)
	var picks := UI.hbox(6)
	var pool: Array = Data.KIN_NAMES.duplicate(); pool.shuffle()
	for nm in pool.slice(0, 4):
		var n2: String = nm
		picks.add_child(UI.button(n2, func(): ne.text = n2))
	v.add_child(picks)
	ne.text = String(baby["name"])
	v.add_child(UI.primary("Welcome home", func():
		baby["name"] = ne.text.strip_edges() if ne.text.strip_edges() != "" else String(baby["name"])
		Save.save_game()
		_close_panel()
		var old := _kin_entry(baby)
		var spot: Vector3 = old["pos"] if not old.is_empty() else NEST_AT + Vector3(0.8, 0, 0.6)
		_spawn_kin()
		var ke := _kin_entry(baby)
		if not ke.is_empty():
			ke["pos"] = spot
			(ke["node"] as Node3D).position = ke["pos"]
			_say(ke, KinSpeak.say(baby, "excited", "hello"), 3.0), 220))

# ---- what it wears
func _open_wear(rec: Dictionary) -> void:
	var v := _new_panel("Dress %s" % rec["name"], 520)
	var owned: Array = Save.d.get("accs", [])
	if owned.is_empty():
		v.add_child(UI.label("You don't own anything for kin to wear yet. The market stall sells bells, bows, hats and more.", 15))
		return
	var grid := GridContainer.new(); grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8); grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	var cur: String = rec.get("acc", "")
	grid.add_child(UI.choice("Nothing", cur == "", func(): _set_acc(rec, ""), 220))
	for a in owned:
		var ak: String = a
		var worn_by := ""
		for o in Save.d["roster"]:
			if o != rec and String(o.get("acc", "")) == ak: worn_by = o["name"]
		grid.add_child(UI.choice(Data.ACCS[ak]["name"] + ("  (on %s)" % worn_by if worn_by != "" else ""), cur == ak, func(): _set_acc(rec, ak), 220))

func _set_acc(rec: Dictionary, a: String) -> void:
	for o in Save.d["roster"]:
		if o != rec and a != "" and String(o.get("acc", "")) == a:
			o["acc"] = ""
	rec["acc"] = a
	Save.save_game()
	_close_panel()
	_spawn_kin()
	var ke := _kin_entry(rec)
	if not ke.is_empty():
		ke["pos"] = ppos + Vector3(1.0, 0, 0.4)
		(ke["node"] as Node3D).position = ke["pos"]
		ke["joy_t"] = 0.8
		_emote(ke, "★")
		if a != "": Care.change(rec, "joy", 5.0)

func _open_feed(rec: Dictionary) -> void:
	var v := _new_panel("Feed %s" % rec["name"], 560)
	var known: Array = rec["known"]
	var any := false
	var row_for := func(f: String, n: int, desc: String) -> void:
		any = true
		var row := UI.hbox(10)
		var info := UI.vbox(2); info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var tag := ""
		if known.has("food") and rec["likes"]["food"] == f: tag = "  ♥ loves it"
		elif known.has("hates") and rec["likes"]["hates"] == f: tag = "  ✕ won't eat it"
		info.add_child(UI.label("%s  ×%d%s" % [Care.food_name(f), n, tag], 16, Care.food_col(f)))
		info.add_child(UI.label(desc, 12, UI.MUTED))
		row.add_child(info)
		row.add_child(UI.button("Feed", func(): _care_feed(rec, f), 100))
		v.add_child(row)
	for f in Care.FOODS:
		var n := int(Save.d["items"].get(f, 0))
		if n > 0: row_for.call(f, n, Care.FOODS[f]["desc"])
	for f in Data.CROPS:
		var n := int(Save.d["crops"].get(f, 0))
		if n > 0:
			var aff := ""
			for af in Evo.AFF:
				if Evo.AFF[af]["food"] == f: aff = "Grows it %s. " % String(Evo.AFF[af]["name"]).to_lower()
			row_for.call(f, n, aff + "Fills it up.")
	if not any:
		v.add_child(UI.label("Nothing to feed it. Harvest crops, or buy kibble and buns at the market stall.", 15))

func _open_train(rec: Dictionary) -> void:
	var v := _new_panel("Train %s" % rec["name"], 560)
	v.add_child(UI.label("A short drill at the yard. Time your presses: gold is great, orange is good. Costs some energy and food; a happy kin learns faster.", 14, UI.MUTED))
	for s in Care.STATS:
		var st: Dictionary = Care.STATS[s]
		var row := UI.hbox(10)
		var info := UI.vbox(2); info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UI.label("%s  ·  %d of %d" % [st["name"], int(rec["stats"][s]), Care.stat_cap(rec)], 16, st["col"]))
		info.add_child(UI.label("%s. %s." % [st["drill"], st["desc"]], 12, UI.MUTED))
		row.add_child(info)
		var sk: String = s
		var b := UI.button("Train", func(): _start_drill(rec, sk), 100)
		b.disabled = int(rec["stats"][s]) >= Care.stat_cap(rec)
		row.add_child(b)
		v.add_child(row)
	v.add_child(UI.label("Energy %d  ·  Full %d" % [int(Care.need(rec, "energy")), int(Care.need(rec, "food"))], 13, UI.MUTED))

# ---- kin as individuals: personal space, turns to talk, and a personality in how they move

## How this kin carries itself, from its traits and kind: pace, bounce, how social or clingy it
## is, how far it roams, how long it lingers, how chatty it is, and a little habit of its own.
func _personality(rec: Dictionary) -> Dictionary:
	var tr: Dictionary = rec.get("traits", {})
	var brave := float(tr.get("bravery", 0.5)); var hot := float(tr.get("temper", 0.5))
	var cur := float(tr.get("curiosity", 0.5)); var loyal := float(tr.get("loyalty", 0.5))
	var h := absi(String(rec.get("uid", rec.get("name", ""))).hash())
	var typ := String(Data.KIN.get(rec.get("species", ""), {}).get("type", ""))
	# [hop rate, hop height, pace]: heavy kinds plod, light ones skip
	var gait: Array = {"gravity": [5.5, 0.06, 0.82], "spore": [7.0, 0.11, 0.9], "lunar": [4.5, 0.2, 0.95],
		"prism": [11.0, 0.09, 1.12], "venom": [9.5, 0.05, 1.06], "echo": [8.0, 0.16, 1.0]}.get(typ, [9.0, 0.14, 1.0])
	var quirks := ["spin", "sniff", "hop", "sit", "look", "wiggle"]
	return {
		"speed": float(gait[2]) * lerpf(0.86, 1.18, (brave + hot) * 0.5) * (0.94 + float(h % 13) * 0.01),
		"hop_f": float(gait[0]) * (0.9 + float(h % 7) * 0.035),
		"hop_a": float(gait[1]),
		"social": lerpf(0.06, 0.4, cur * 0.6 + (1.0 - loyal) * 0.4),
		"cling": lerpf(0.08, 0.5, loyal),
		"roam": cur,
		"rest": lerpf(1.6, 0.7, hot * 0.5 + cur * 0.5),
		"chatty": lerpf(0.35, 1.3, hot * 0.5 + cur * 0.5),
		"haunt": h % 7,
		"quirk": quirks[(h / 7) % quirks.size()],
	}

## A spot in a ring around a place, different for every kin, so a crowd fans out instead of piling up.
func _seat(k: Dictionary, center: Vector3, r := 1.4) -> Vector3:
	var i := maxi(0, kins.find(k))
	var a := float(i) * 2.39996 + float(absi(String(k["rec"]["uid"]).hash()) % 100) * 0.013
	var rr := r + float(i / 6) * 0.9
	var p := center + Vector3(cos(a) * rr, 0, sin(a) * rr)
	if world.is_void(p.x, p.z) or world.occupy(p.x, p.z, 0.3, 0.0, true) != 0.0:
		return world.free_spot_near(p, kins.map(func(o): return o["pos"]), 1.0)
	return p

## The kin's favourite corner on this island, or INF if it isn't here.
func _haunt(k: Dictionary, here: int) -> Vector3:
	var picks := [spots.get("pot", Vector3.INF), POND_EDGE, spots.get("house", Vector3.INF) + Vector3(0, 0, 3.0), YARD_AT,
		NEST_AT + Vector3(1.5, 0, 1.0), spots.get("rack", Vector3.INF) + Vector3(1.2, 0, 0.8), spots.get("stall", Vector3.INF) + Vector3(0, 0, 2.0)]
	var p: Vector3 = picks[int(k.get("pers", {}).get("haunt", 0)) % picks.size()]
	if p == Vector3.INF or world.island_of(p.x, p.z) != here:
		return Vector3.INF
	return p

func _talking_near(k: Dictionary, r: float) -> bool:
	for o in kins:
		if o != k and float(o.get("say_t", 0.0)) > 0.0 and Vector2(o["pos"].x - k["pos"].x, o["pos"].z - k["pos"].z).length() < r:
			return true
	return false

func _kin_r(k: Dictionary) -> float:
	var n: Node3D = k["node"]
	return 0.42 * n.scale.x

## Personal space: kin push gently apart (and step around you) instead of stacking in one spot.
## A kin that's being petted, napping or busy holds its ground and the others make room.
func _separate_kin(d: float) -> void:
	var act: Array = kins.filter(func(o): return not o.has("indoors") and not o.has("leap") and (o["node"] as Node3D).visible and not o.get("busy", false))
	var fixed := func(o: Dictionary) -> bool: return float(o.get("hold_t", 0.0)) > 0.0 or float(o.get("nap_t", 0.0)) > 0.0 or o.has("bath")
	var p2 := Vector2(ppos.x, ppos.z)
	for i in act.size():
		var a: Dictionary = act[i]
		if fixed.call(a): continue
		var ap := Vector2(a["pos"].x, a["pos"].z)
		var push := Vector2.ZERO
		for j in act.size():
			if j == i: continue
			var b: Dictionary = act[j]
			var diff := ap - Vector2(b["pos"].x, b["pos"].z)
			var need := _kin_r(a) + _kin_r(b)
			var dl := diff.length()
			if dl < need:
				if dl < 0.001: diff = Vector2.from_angle(float(i) * 2.4); dl = 0.001
				push += diff / dl * (need - dl) * (1.0 if fixed.call(b) else 0.5)
		var dp := ap - p2
		var need_p := _kin_r(a) + 0.38
		if dp.length() < need_p and not a.has("fetch"):
			if dp.length() < 0.001: dp = Vector2.from_angle(float(i) * 2.4)
			push += dp.normalized() * (need_p - dp.length())
		if push == Vector2.ZERO: continue
		push = push.limit_length(3.5 * d + 0.02)
		var pos: Vector3 = a["pos"]
		if world.occupy(pos.x + push.x, pos.z, 0.3, 0.0, true) == 0.0 and not world.is_void(pos.x + push.x, pos.z): pos.x += push.x
		if world.occupy(pos.x, pos.z + push.y, 0.3, 0.0, true) == 0.0 and not world.is_void(pos.x, pos.z + push.y): pos.z += push.y
		a["pos"] = pos
		(a["node"] as Node3D).position = pos

## Each kin's little habit when it stops: a spin, a sniff at the ground, a happy hop, sitting down,
## looking around, or a wiggle. Rare and staggered, so it reads as character, not a dance routine.
func _quirk(k: Dictionary, n: Node3D, moving: bool, d: float) -> void:
	var body := n.get_node_or_null("Body") as Node3D
	if body == null: return
	k["qt"] = float(k.get("qt", randf_range(4.0, 12.0))) - d
	var q := float(k.get("q_on", 0.0))
	if moving or float(k.get("hold_t", 0.0)) > 0.0 or float(k.get("nap_t", 0.0)) > 0.0 or k.has("bath") or k.has("fetch"):
		# interrupted: only undo our own pose, so feeding and training animations keep theirs
		if q > 0.0:
			k["q_on"] = 0.0
			body.rotation = Vector3.ZERO; body.scale = Vector3.ONE
		k["qt"] = maxf(float(k["qt"]), 3.0)
		return
	if q <= 0.0 and float(k["qt"]) <= 0.0:
		k["qt"] = randf_range(7.0, 16.0) * float(k.get("pers", {}).get("rest", 1.0))
		k["q_on"] = 1.2
		q = 1.2
	if q <= 0.0:
		return
	q -= d
	k["q_on"] = q
	var t := 1.0 - clampf(q / 1.2, 0.0, 1.0)      # 0 -> 1 over the habit
	var e := sin(t * PI)
	match String(k.get("pers", {}).get("quirk", "look")):
		"spin": body.rotation.y = t * TAU
		"sniff": body.rotation.x = e * 0.35; body.position.y = -e * 0.04
		"hop": body.position.y = absf(sin(t * TAU * 1.5)) * 0.22
		"sit": body.scale = Vector3(1.0 + e * 0.12, 1.0 - e * 0.16, 1.0 + e * 0.12)
		"look": body.rotation.y = sin(t * TAU) * 0.7
		"wiggle": body.rotation.z = sin(t * TAU * 3.0) * 0.18 * e
	if q <= 0.0:
		body.rotation = Vector3.ZERO; body.scale = Vector3.ONE

# ------------------------------------------------------------------ test hooks for the economy
## --armory-test, --feeder-test, --grave-test, --shrine-test: set up a save and open the thing,
## for screenshots (nothing is written to the real save).
func _econ_tests(dbg) -> void:
	var any := false
	for a in dbg:
		if String(a) in ["--armory-test", "--feeder-test", "--grave-test", "--shrine-test", "--starve-test"]: any = true
	if not any:
		return
	Save.no_write = true
	Save.d["tutorial"]["home"] = true
	Save.d["tutorial"]["day1_done"] = true
	Save.d["gems"] = maxi(int(Save.d["gems"]), 900)
	Save.d["extracts"] = maxi(int(Save.d.get("extracts", 0)), 6)
	var rng := RandomNumberGenerator.new(); rng.seed = 5
	if "--armory-test" in dbg:
		if not Save.d["buildings"].has("armory"): Save.d["buildings"].append("armory")
		Save.d["armory"] = []
		for t in [["rifle", 2, "fire", ""], ["sniper", 3, "frost", ""], ["", 0, "", "thunderclap"], ["smg", 1, "", ""], ["shotgun", 4, "venom", ""],
				["longsword", 2, "storm", ""], ["burst_rifle", 3, "", ""], ["greatsword", 2, "void", ""]]:
			Save.d["armory"].append(Loot.weapon(String(t[0]), int(t[1]), String(t[2]), String(t[3])))
		var gk: Array = Gear.ALL.keys()
		for i in mini(4, gk.size()):
			Save.d["armory"].append(Loot.glove(String(gk[i]), 1 + i % 4))
		Save.d["valuables"] = {"old_coin": 3, "sky_pearl": 1, "kin_idol": 1, "soul_ember": 1}
		Save.d["scrap"] = 9
		Save.d["loadout"] = {"weapon": Save.d["armory"][2]["uid"]}
		get_tree().create_timer(0.4).timeout.connect(func():
			hecon.arm_pick = String(Save.d["armory"][2]["uid"])
			hecon.open_armory())
	if "--feeder-test" in dbg or "--starve-test" in dbg:
		while Save.d["roster"].size() < 6:
			Save.d["roster"].append(Save.new_kin(Data.KIN.keys()[Save.d["roster"].size() % Data.KIN.size()]))
		Save.d["items"]["kibble"] = 12
		Save.d["crops"]["tidebloom"] = 4
		Save.d["feeders"] = [{"id": "f1", "kind": "trough", "x": Econ.FEEDER_START.x, "z": Econ.FEEDER_START.z, "food": ["kibble", "kibble", "tidebloom", "kibble", "kibble", "kibble"], "auto": true}]
		Save.d["feeder_given"] = true
		for rec in Save.d["roster"]:
			Care.ensure(rec)
			rec["needs"]["food"] = 18.0 if "--feeder-test" in dbg else 0.0
			rec["needs_t"] = Time.get_unix_time_from_system()
			rec["likes"]["hates"] = "puffcorn"
		if "--starve-test" in dbg:
			# one kin a day and a half without food, another a whole day: warnings on the way in
			Save.d["roster"][0]["starve"] = 20.0 * 3600.0
			Save.d["roster"][1]["starve"] = 7.0 * 3600.0
		if "--feeder-test" in dbg:
			get_tree().create_timer(0.3).timeout.connect(func():
				ppos = Econ.FEEDER_START + Vector3(0.5, 0, 3.2); player.position = ppos; cam.snap(ppos)
				for i in kins.size():
					var k: Dictionary = kins[i]
					k.erase("indoors"); (k["node"] as Node3D).visible = true
					k["pos"] = Econ.FEEDER_START + Vector3(cos(i * 1.1) * 3.4, 0, sin(i * 1.1) * 2.6 + 0.4)
					k["pos"] = world.free_spot_near(k["pos"], [], 0.6)
					(k["node"] as Node3D).position = k["pos"]
					k["t"] = 0.0
					hecon.feed_goal(k))
			for step in [3.0, 8.0, 14.0, 22.0]:
				get_tree().create_timer(step).timeout.connect(func():
					var md := 99.0; var eating := 0; var waiting := 0
					for i in kins.size():
						if kins[i].has("eat"):
							if String(kins[i]["eat"]["phase"]) == "eat": eating += 1
							elif int(kins[i]["eat"]["seat"]) < 0: waiting += 1
						for j in range(i + 1, kins.size()):
							md = minf(md, Vector2(kins[i]["pos"].x - kins[j]["pos"].x, kins[i]["pos"].z - kins[j]["pos"].z).length())
					var fed := (Save.d["roster"] as Array).filter(func(r): return Care.need(r, "food") > 30.0).size()
					print("FEEDER t=%.0f kin=%d eating=%d waiting=%d fed=%d fill=%d min_gap=%.2f" % [step, kins.size(), eating, waiting, fed, Econ.fill(Econ.feeders()[0]), md]))
	if "--grave-test" in dbg or "--shrine-test" in dbg:
		while Save.d["roster"].size() < 3:
			Save.d["roster"].append(Save.new_kin(Data.KIN.keys()[Save.d["roster"].size() % Data.KIN.size()]))
		Save.d["graves"] = []
		for i in 4:
			var rec := Save.new_kin(Data.KIN.keys()[(i + 2) % Data.KIN.size()], ["Biscuit", "Wren", "Clove", "Sorrel"][i])
			rec["level"] = 3 + i * 2
			Save.remember(rec, "caught", "was caught by you in the islands and brought home")
			Save.remember(rec, "extracted", "made it out of the islands with you")
			Save.remember(rec, "fed", "was fed emberberry by you")
			Save.remember(rec, "love", "loved playing fetch with you")
			Save.d["roster"].append(rec)
			var g := Econ.kin_dies(rec, "starved")
			g["t"] = Time.get_unix_time_from_system() - 86400.0 * (i + 1)
			g["soul"] = i < 2 and "--shrine-test" in dbg
		if "--shrine-test" in dbg and not Save.d["buildings"].has("shrine"):
			Save.d["buildings"].append("shrine")
		Save.d["valuables"] = {"soul_ember": 2}
		get_tree().create_timer(0.3).timeout.connect(func():
			ppos = Vector3(49.6, 0, 37.6) if "--shrine-test" in dbg else Vector3(49.7, 0, 35.6)
			player.position = ppos; cam.snap(ppos)
			if "--shrine-open" in dbg: hecon.open_shrine()
			elif "--grave-open" in dbg: hecon.open_grave(Econ.graves()[Econ.graves().size() - 1]))
