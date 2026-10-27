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
var emote_labels: Array = []
var pet_done := {}

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_env()
	world = World.new(); add_child(world)
	world.make_home(4242)
	var c := Vector2(world.w / 2.0, world.h / 2.0)   # (15, 13)
	var path_col := Color("9c7a52")
	# the house up north, a path from its door down to the portal, branches to the market and the farm
	spots["house"] = Vector3(15.0, 0, 7.5)
	world.set_block_rect(13, 6, 17, 8)
	spots["portal"] = Vector3(15.0, 0, 20.0)
	world.paint_path(Vector2i(14, 9), Vector2i(14, 19), path_col)
	world.paint_path(Vector2i(8, 14), Vector2i(14, 14), path_col)
	world.paint_path(Vector2i(15, 12), Vector2i(19, 12), path_col)
	spots["stall"] = Vector3(7.5, 0, 13.0)
	world.set_block_rect(6, 12, 8, 13)
	spots["pot"] = Vector3(19.5, 0, 8.5)
	world.set_block_rect(19, 8, 19, 8)
	# farm soil inside a fence
	for z in range(11, 19):
		for x in range(20, 25):
			world.paint_tile(x, z, Color("6b4a33"))
	world.set_block_rect(9, 17, 11, 19)   # pond
	world.add_trees_on_rim(12)
	# keep the portal approach and the farm clear of rim trees and rocks
	for z in range(17, world.h):
		for x in range(12, 19):
			if world.inb(x, z) and world.kind[world.idx(x, z)] == World.T_BLOCK and not world.no_deco.has(world.idx(x, z)):
				world.kind[world.idx(x, z)] = World.T_GROUND
	for z in range(9, 20):
		for x in range(19, 26):
			if world.inb(x, z) and world.kind[world.idx(x, z)] == World.T_BLOCK and not world.no_deco.has(world.idx(x, z)):
				world.kind[world.idx(x, z)] = World.T_GROUND
	world.build_meshes()
	fx = Fx.new(); add_child(fx)
	cam = CamRig.new(); add_child(cam)
	cam.zoom_to = 0.72; cam.zoom = 0.72; cam.lead = 0.2
	var house := Models.house(); house.position = spots["house"]; add_child(house)
	var pot := Models.cauldron(); pot.position = spots["pot"]; add_child(pot)
	var stall := Models.stall(); stall.position = spots["stall"]; stall.rotation.y = PI * 0.5; add_child(stall)
	var portal := Models.portal(UI.TEAL); portal.position = spots["portal"]; add_child(portal)
	portal.get_node("Disc").visible = true
	(portal.get_node("Beam") as CPUParticles3D).emitting = true
	var drng := RandomNumberGenerator.new(); drng.seed = 77
	var pond := Models.pond(1.9, 1.5); pond.position = Vector3(10.5, 0, 18.5); add_child(pond)
	for fp in [[Vector3(22.4, 0, 10.4), 0.0, 5.0], [Vector3(22.4, 0, 18.6), 0.0, 5.0], [Vector3(24.8, 0, 14.5), PI / 2, 8.0], [Vector3(19.4, 0, 16.6), PI / 2, 4.0]]:
		var f := Models.fence(fp[2]); f.position = fp[0]; f.rotation.y = fp[1]; add_child(f)
	for lp in [Vector3(13.2, 0, 11.0), Vector3(16.6, 0, 16.5), Vector3(11.5, 0, 15.2), Vector3(18.0, 0, 11.0)]:
		var l := Models.lamp(); l.position = lp; add_child(l)
	for fb in [Vector3(12.6, 0, 9.6), Vector3(17.4, 0, 9.6), Vector3(16.6, 0, 18.4)]:
		var b := Models.flower_bed(drng); b.position = fb; add_child(b)
	var sign_post := Models.signpost(["Expeditions"]); sign_post.position = Vector3(16.8, 0, 19.2); sign_post.rotation.y = -0.3; add_child(sign_post)
	var roster: Array = Save.d["roster"]
	for i in mini(roster.size(), 6):
		var bed := Models.kin_bed(Data.KIN[roster[i]["species"]]["color"])
		bed.position = Vector3(10.4 + (i % 3) * 1.1, 0, 8.4 + (i / 3) * 1.1)
		add_child(bed)
	_build_plots(c)
	player = Models.hunter(Save.d.get("cls", "medium"), Data.TEAM_COLORS[0], Data.CLASSES[Save.d.get("cls", "medium")]["weapon"])
	add_child(player)
	ppos = Vector3(15.0, 0, 15.5)
	player.position = ppos
	cam.snap(ppos)
	_spawn_kin()
	_build_ui()
	_refresh_top()
	if not Save.d["tutorial"].get("home", false):
		_open_welcome()
	# a kin with lines written by Claude keeps them fresh
	var ak := Save.active_kin()
	if Bridge.ai_ok and not ak.is_empty() and int(ak.get("matches", 0)) % 3 == 0:
		Bridge.refresh_lines(ak)

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
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_color = Color("ffe9cf")
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 45.0
	add_child(sun)

func _build_plots(c: Vector2) -> void:
	for n in plots:
		n.queue_free()
	plots.clear()
	var cap := int(Save.d["plot_cap"])
	while Save.d["plots"].size() < cap:
		Save.d["plots"].append({"crop": "", "stage": 0})
	for i in cap:
		var col := i % 2
		var row := i / 2
		var p := Models.plot()
		p.position = Vector3(21.2 + col * 2.2, 0, 11.8 + row * 2.0)
		add_child(p)
		plots.append(p)
		_refresh_plot(i)

func _refresh_plot(i: int) -> void:
	var p: Node3D = plots[i]
	var holder: Node3D = p.get_node("Crop")
	for ch in holder.get_children():
		ch.queue_free()
	var d: Dictionary = Save.d["plots"][i]
	if d["crop"] != "":
		var cd: Dictionary = Data.CROPS[d["crop"]]
		holder.add_child(Models.crop(int(d["stage"]), int(cd["grow"]), cd["color"]))

func _spawn_kin() -> void:
	for k in kins:
		k["node"].queue_free()
	kins.clear()
	for rec in Save.d["roster"]:
		var n := Models.kin(rec["species"])
		add_child(n)
		var at := world.random_ground()
		n.position = at
		var lbl := Label3D.new()
		lbl.font = UI.big; lbl.font_size = 40; lbl.pixel_size = 0.01; lbl.outline_size = 10
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED; lbl.no_depth_test = true
		lbl.position.y = 1.15; lbl.visible = false
		n.add_child(lbl)
		kins.append({"rec": rec, "node": n, "pos": at, "vel": Vector3.ZERO, "goal": Vector3.INF, "t": randf() * 3.0, "emote": lbl, "emote_t": 0.0, "hop": randf() * 6.0})

# ------------------------------------------------------------------ loop
func _process(delta: float) -> void:
	var d := minf(delta, 0.05)
	_move_player(d)
	_move_kin(d)
	cam.follow(ppos, d, panel_open == "")
	_find_interact()
	if panel_open == "" and Input.is_action_just_pressed("interact") and not interact.is_empty():
		_use(interact)

func _move_player(d: float) -> void:
	var mv := Vector2.ZERO
	if panel_open == "":
		mv = Vector2(Input.get_axis("left", "right"), Input.get_axis("up", "down"))
		if mv.length() > 1.0: mv = mv.normalized()
	var hv := Vector2(pvel.x, pvel.z)
	hv += (mv * SPEED - hv) * (1.0 - exp(-14.0 * d))
	var nx := ppos.x + hv.x * d
	if world.occupy(nx, ppos.z, 0.38, 0.0, true) == 0.0: ppos.x = nx
	var nz := ppos.z + hv.y * d
	if world.occupy(ppos.x, nz, 0.38, 0.0, true) == 0.0: ppos.z = nz
	pvel = Vector3(hv.x, 0, hv.y)
	player.position = ppos
	if hv.length() > 0.3:
		pface = lerp_angle(pface, atan2(-hv.x, -hv.y), minf(1.0, d * 14.0))
	player.rotation.y = pface
	walk_ph += d * hv.length() * 2.2
	var legs: Node3D = player.get_node("Rig/Legs")
	var sw := sin(walk_ph) * clampf(hv.length() / 4.0, 0.0, 1.0) * 0.6
	legs.get_node("LegL").rotation.x = sw
	legs.get_node("LegR").rotation.x = -sw
	player.get_node("Rig/Torso").position.y = 0.42 + absf(sin(walk_ph)) * 0.04 * clampf(hv.length() / 4.0, 0.0, 1.0)

func _move_kin(d: float) -> void:
	for k in kins:
		k["t"] -= d
		var pos: Vector3 = k["pos"]
		var rec: Dictionary = k["rec"]
		var trust := float(rec["trust"])
		if k["t"] <= 0.0:
			k["t"] = randf_range(2.0, 5.0)
			if randf() < 0.25 + trust / 300.0:
				# kin that trust you like to be near you
				k["goal"] = ppos + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))
			else:
				k["goal"] = world.random_ground()
			if randf() < 0.3:
				_emote(k, "♥" if trust > 65.0 else ("?" if trust < 30.0 else "★"))
		var wish := Vector2.ZERO
		var goal: Vector3 = k["goal"]
		if goal != Vector3.INF:
			var to := Vector2(goal.x - pos.x, goal.z - pos.z)
			if to.length() > 0.4:
				wish = to.normalized() * 2.4
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
		n.scale = Vector3.ONE * (1.05 if rec["uid"] == Save.d.get("active", "") else 0.9)
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
		if d < bd: bd = d; best = {"kind": "plot", "i": i}
	for nm in ["pot", "stall", "portal", "house"]:
		var sp: Vector3 = spots[nm]
		var reach := 2.6 if nm in ["house", "portal"] else 1.9
		var d := p2.distance_to(Vector2(sp.x, sp.z + (2.0 if nm == "house" else 0.0)))
		if d < reach and d < bd + 0.6: bd = d; best = {"kind": nm}
	for k in kins:
		var d := p2.distance_to(Vector2(k["pos"].x, k["pos"].z))
		if d < bd: bd = d; best = {"kind": "kin", "k": k}
	interact = best
	if panel_open != "" or best.is_empty():
		prompt_box.visible = false
		return
	prompt_box.visible = true
	prompt_lbl.text = "F  " + _label_for(best)
	prompt_box.reset_size()
	var vp := get_viewport().get_visible_rect().size
	prompt_box.position = Vector2((vp.x - prompt_box.size.x) * 0.5, vp.y - 110.0)

func _label_for(it: Dictionary) -> String:
	match it["kind"]:
		"plot":
			var d: Dictionary = Save.d["plots"][it["i"]]
			if d["crop"] == "": return "Plant something"
			var cd: Dictionary = Data.CROPS[d["crop"]]
			if int(d["stage"]) >= int(cd["grow"]): return "Harvest the %s" % cd["name"]
			return "%s: ready in %d more match%s" % [cd["name"], int(cd["grow"]) - int(d["stage"]), "" if int(cd["grow"]) - int(d["stage"]) == 1 else "es"]
		"pot": return "Cook"
		"stall": return "Shop"
		"portal": return "Start an expedition"
		"house": return "Go inside"
		"kin":
			var rec: Dictionary = it["k"]["rec"]
			return "Spend time with %s" % rec["name"]
	return ""

func _use(it: Dictionary) -> void:
	Sfx.play("click")
	match it["kind"]:
		"plot": _open_plot(it["i"])
		"pot": _open_kitchen()
		"stall": _open_shop()
		"portal": _open_expedition()
		"house": _open_house()
		"kin": _open_kin(it["k"]["rec"])

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		if panel_open != "":
			_close_panel()
		else:
			_open_settings()

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
	hint = UI.label("WASD walk   ·   F use what's in front of you   ·   Esc settings", 14, UI.INK)
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
	_close_panel()
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(width, 0)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var v := UI.vbox(12)
	p.add_child(v)
	var head := UI.hbox(8)
	var t := UI.title(title_txt, 30)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UI.button("Close", _close_panel))
	v.add_child(head)
	panel_host.add_child(p)
	panel_open = title_txt
	return v

func _close_panel() -> void:
	for ch in panel_host.get_children():
		ch.queue_free()
	panel_open = ""
	chat_input = null
	_refresh_top()

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
func _open_plot(i: int) -> void:
	var d: Dictionary = Save.d["plots"][i]
	if d["crop"] != "":
		var cd: Dictionary = Data.CROPS[d["crop"]]
		if int(d["stage"]) >= int(cd["grow"]):
			Save.d["crops"][d["crop"]] = int(Save.d["crops"].get(d["crop"], 0)) + 2
			fx.burst(plots[i].position + Vector3(0, 0.6, 0), cd["color"], 18, 3.0)
			Sfx.play("harvest")
			d["crop"] = ""; d["stage"] = 0
			_refresh_plot(i)
			Save.save_game()
			_refresh_top()
			return
		var v := _new_panel(cd["name"], 440)
		v.add_child(UI.label("Growing. Ready in %d more match%s." % [int(cd["grow"]) - int(d["stage"]), "" if int(cd["grow"]) - int(d["stage"]) == 1 else "es"], 16))
		v.add_child(UI.label(cd["desc"], 15, UI.MUTED))
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
		info.add_child(UI.label("Grows in %d match%s. %s" % [Data.CROPS[s]["grow"], "" if Data.CROPS[s]["grow"] == 1 else "es", Data.CROPS[s]["desc"]], 13, UI.MUTED))
		row.add_child(info)
		var sk: String = s
		row.add_child(UI.button("Plant", func():
			Save.d["seeds"][sk] = int(Save.d["seeds"][sk]) - 1
			d["crop"] = sk; d["stage"] = 0
			Sfx.play("plant")
			fx.dust(plots[i].position, 10)
			_refresh_plot(i)
			Save.save_game()
			_close_panel()))
		v.add_child(row)
	if not any:
		v.add_child(UI.label("You have no seeds. Find them in chests and from monsters on expeditions, or buy some at the stall.", 16, UI.MUTED))

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
		var label_txt := "Brew 2 tonics" if cd["use"] == "tonic" else "Make the treat"
		row.add_child(UI.button(label_txt, func():
			Save.d["crops"][sk] = int(Save.d["crops"][sk]) - 1
			if cd["use"] == "tonic":
				Save.add_item("tonic", 2)
			else:
				Save.d["treat"] = cd["use"]
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
	if int(Save.d["plot_cap"]) < 8:
		_shop_row(v, "Two more plots", "Grow more at once.", 120 + 80 * (int(Save.d["plot_cap"]) - 4), func():
			Save.d["plot_cap"] = int(Save.d["plot_cap"]) + 2
			_build_plots(Vector2(world.w / 2.0, world.h / 2.0)))

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
	var v := _new_panel("%s the %s" % [rec["name"], sp["name"]], 600)
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
	var mem: Array = rec.get("memory", [])
	if mem.size() > 0:
		v.add_child(UI.label("Remembers", 13, UI.MUTED))
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
	if not Bridge.has_page():
		v.add_child(UI.label("Conversations need the web version of the game, where your kin talk through Claude. Here they answer with a few stock lines.", 13, UI.MUTED))
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
	if not Bridge.has_page():
		var reply := _stock_reply(rec)
		chat_log.append({"role": "assistant", "content": reply})
		_chat_bubble("assistant", reply)
		return
	chat_busy = true
	var thinking := UI.label("%s is thinking..." % rec["name"], 13, UI.MUTED)
	chat_box.add_child(thinking)
	var msgs := []
	var brief := Bridge.kin_brief(rec) + "\n\nYou are chatting with your hunter at home on the farm. Stay in character, answer in one to three short sentences, plain text, no emoji, no stage directions. " + \
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
		chat_busy = false
		if is_instance_valid(thinking): thinking.queue_free()
		if reply == "":
			reply = _stock_reply(rec)
		chat_log.append({"role": "assistant", "content": reply})
		if is_instance_valid(chat_box):
			_chat_bubble("assistant", reply)
		# talking builds a little trust, once per match
		if int(rec.get("talked", -1)) != int(Save.d["matches"]):
			rec["talked"] = int(Save.d["matches"])
			Save.remember(rec, "talked", "had a chat with you at home", 2.0)
			Save.save_game()
			if Bridge.ai_ok and rec["uid"] == Save.d.get("active", "") and not rec.has("lines"):
				Bridge.refresh_lines(rec), "default")

func _stock_reply(rec: Dictionary) -> String:
	var t := float(rec["trust"])
	var dom := "bravery"; var best := 0.0
	for k in rec["traits"]:
		if float(rec["traits"][k]) > best: best = float(rec["traits"][k]); dom = k
	var pool := {
		"bravery": ["When do we go back out? I'm ready.", "Next time, throw me at the big one."],
		"loyalty": ["As long as we stick together, I'm happy.", "Did you eat? You should eat."],
		"temper": ["Hmph. Fine. What?", "I'm still annoyed about last time."],
		"curiosity": ["I found a weird bug by the plots!", "What's past the clouds, do you think?"],
	}
	if t < 30.0:
		return ["I don't really want to talk.", "Maybe stop throwing me into everything first."].pick_random()
	return pool[dom].pick_random()

# ---- expedition
var exp_cls := ""
var exp_mode := "solo"
var exp_tier := 0

func _open_expedition() -> void:
	if exp_cls == "":
		exp_cls = Save.d.get("cls", "medium")
	var v := _new_panel("Expedition", 720)
	v.add_child(UI.label("Choose your hunter", 13, UI.MUTED))
	var cards := UI.hbox(10)
	for c in ["light", "medium", "heavy"]:
		var cd: Dictionary = Data.CLASSES[c]
		var card := UI.card(UI.CARD, 12, 12)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if c == exp_cls:
			UI.set_card_border(card, UI.ACCENT)
		var cv := UI.vbox(4); card.add_child(cv)
		cv.add_child(UI.title(cd["name"], 22))
		cv.add_child(UI.label("%d HP · %d dash%s · %s" % [cd["hp"], cd["dashes"], "es" if cd["dashes"] > 1 else "", Data.WEAPONS[cd["weapon"]]["name"]], 13, UI.MUTED))
		cv.add_child(UI.label("E: " + String(Data.SIGS[cd["sig"]]["name"]) + ". " + String(Data.SIGS[cd["sig"]]["desc"]), 13))
		var ck: String = c
		cv.add_child(UI.button("Selected" if c == exp_cls else "Pick", func(): exp_cls = ck; _open_expedition()))
		cards.add_child(card)
	v.add_child(cards)
	var ak := Save.active_kin()
	if not ak.is_empty():
		var sp: Dictionary = Data.KIN[ak["species"]]
		var kl := "Partner: %s the %s, trust %d. RMB throws it into fights; Q fires its %s." % [ak["name"], sp["name"], int(ak["trust"]), Data.KIN_SKILLS[sp["skill"]]["name"]]
		v.add_child(UI.label(kl, 15, sp["color"]))
		if float(ak["trust"]) < 30.0:
			v.add_child(UI.label("%s doesn't trust you much yet and may refuse risky throws. Spend time with it, or feed it a Mindmint treat." % ak["name"], 13, UI.BAD))
	if Save.d.get("treat", "") != "":
		v.add_child(UI.label("Treat: " + _treat_name(Save.d["treat"]), 14, UI.GOLD))
	v.add_child(UI.label("Where", 13, UI.MUTED))
	var tiers := UI.hbox(8)
	var ex := int(Save.d.get("extracts", 0))
	for i in Data.TIERS.size():
		var td: Dictionary = Data.TIERS[i]
		var locked := ex < int(td["unlock"])
		var ti := i
		var label_t: String = td["name"] + ("  ✓" if exp_tier == i else "")
		if locked:
			label_t = "%s (make it out %d more time%s)" % [td["name"], int(td["unlock"]) - ex, "" if int(td["unlock"]) - ex == 1 else "s"]
		var b := UI.button(label_t, func(): exp_tier = ti; _open_expedition())
		b.disabled = locked
		tiers.add_child(b)
	v.add_child(tiers)
	var tsel: Dictionary = Data.TIERS[exp_tier]
	v.add_child(UI.label(tsel["desc"], 14, UI.BAD if tsel["risk_kin"] else UI.MUTED))
	if tsel["risk_kin"] and not ak.is_empty():
		var safe := float(ak["trust"]) >= 80.0
		v.add_child(UI.label(("%s trusts you enough to find its way home if you fall." if safe else "%s's trust is %d. Below 80, it won't come home if you fall here.") % ([ak["name"]] if safe else [ak["name"], int(ak["trust"])]), 14, UI.GOOD if safe else UI.BAD))
	v.add_child(UI.label("Match", 13, UI.MUTED))
	var modes := UI.hbox(8)
	for m in [["solo", "Solo · 4 squads"], ["duo", "Duos with a bot · 3 squads"], ["big", "Solo · 6 squads"]]:
		var mk: String = m[0]
		var b := UI.button(m[1] + ("  ✓" if exp_mode == mk else ""), func(): exp_mode = mk; _open_expedition())
		modes.add_child(b)
	v.add_child(modes)
	var go := UI.hbox(10)
	go.add_child(UI.button("Start expedition", _start_match, 220))
	if Bridge.net_available():
		go.add_child(UI.button("Play online with friends", func(): Game.goto("lobby", {"cls": exp_cls, "tier": exp_tier}), 240))
	v.add_child(go)

func _start_match() -> void:
	Save.d["cls"] = exp_cls
	Save.save_game()
	var o := {"teams": 4, "squad": 1}
	match exp_mode:
		"duo": o = {"teams": 3, "squad": 2}
		"big": o = {"teams": 6, "squad": 1}
	o["tier"] = exp_tier
	Game.start_match(o)

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
		var info := UI.label("%s the %s  ·  level %d  ·  trust %d" % [rec["name"], sp["name"], int(rec["level"]), int(rec["trust"])], 15)
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
	v.add_child(UI.button("Settings", _open_settings, 180))

# ---- settings
func _open_settings() -> void:
	var v := _new_panel("Settings", 480)
	var st: Dictionary = Save.d["settings"]
	var name_row := UI.hbox(8)
	var nl := UI.label("Your name", 15)
	nl.custom_minimum_size.x = 200
	name_row.add_child(nl)
	var ne := LineEdit.new(); ne.text = Save.d.get("name", "Hunter"); ne.size_flags_horizontal = Control.SIZE_EXPAND_FILL; ne.max_length = 16
	ne.text_changed.connect(func(t): Save.d["name"] = t.strip_edges() if t.strip_edges() != "" else "Hunter")
	name_row.add_child(ne)
	v.add_child(name_row)
	for s in [["volume", "Volume"], ["shake", "Screen shake"], ["cam_lead", "Camera lean toward cursor"]]:
		var r := UI.hbox(8)
		var l := UI.label(s[1], 15); l.custom_minimum_size.x = 200
		r.add_child(l)
		var sl := HSlider.new(); sl.min_value = 0.0; sl.max_value = 1.5 if s[0] != "volume" else 1.0; sl.step = 0.05
		sl.value = float(st.get(s[0], 1.0)); sl.custom_minimum_size.x = 200
		var key: String = s[0]
		sl.value_changed.connect(func(val):
			st[key] = val
			if key == "volume": Sfx.set_volume(val))
		r.add_child(sl)
		v.add_child(r)
	v.add_child(UI.label("In a match: WASD move · LMB fire · Shift dash · Space jump · RMB throw or call back your kin · Q kin skill · E class ability · F catch, revive, open · 1 tonic · Tab scores · Esc pause", 13, UI.MUTED))
	var row := UI.hbox(8)
	row.add_child(UI.button("Save", func(): Save.save_game(); _close_panel()))
	row.add_child(UI.button("Start over", func():
		Save.reset()
		Game.goto("home")))
	v.add_child(row)
