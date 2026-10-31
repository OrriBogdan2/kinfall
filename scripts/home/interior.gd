extends Node3D
## Inside a building: walk around, hang out with the kin who live there, and decorate. Furniture
## sits on a tile grid; press B (or the Decorate button) to place, turn, move and put things away.

const SPEED := 4.2
const TILE := 1.0

var room := "house"
var visit: Dictionary = {}      # someone else's island snapshot when visiting
var visit_id := ""
var R: Dictionary
var W := 10
var D := 8
var cam: CamRig
var fx: Fx
var player: Node3D
var ppos := Vector3.ZERO
var pvel := Vector3.ZERO
var pface := PI
var walk_ph := 0.0
var decor: Array = []           # [{id, x, z, r}], the live list in the save (or a copy when visiting)
var nodes: Array = []           # one Node3D per decor entry
var occ := {}                   # Vector2i -> index into decor, for pieces you can't walk through
var kins: Array = []            # {rec, node, pos, goal, t, hop}
var spots: Array = []           # {kind, pos, label}
var interact: Dictionary = {}
# ui
var root_ui: Control
var prompt_box: PanelContainer
var prompt_lbl: Label
var panel_host: CenterContainer
var panel_open := ""
var deco_bar: Control = null
var deco_hint: Label = null
var deco_page := 0
var decorating := false
var held := {}                  # the piece in your hand: {id, r, from (index or -1)}
var ghost: Node3D = null
var ghost_ok := false
var ghost_cell := Vector2i.ZERO

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	R = Data.ROOMS.get(room, Data.ROOMS["house"])
	W = int(R["w"]); D = int(R["d"])
	_build_env()
	_build_room()
	fx = Fx.new(); add_child(fx)
	cam = CamRig.new(); add_child(cam)
	cam.zoom_to = 0.62; cam.zoom = 0.62; cam.lead = 0.0
	if visit.is_empty():
		if typeof(Save.d.get("decor")) != TYPE_DICTIONARY: Save.d["decor"] = {}
		if typeof(Save.d["decor"].get(room)) != TYPE_ARRAY:
			var start: Array = []
			for s in R["start"]: start.append({"id": s[0], "x": s[1], "z": s[2], "r": s[3]})
			Save.d["decor"][room] = start
			Save.save_game()
		decor = Save.d["decor"][room]
		if typeof(Save.d.get("furniture")) != TYPE_DICTIONARY: Save.d["furniture"] = {}
	else:
		decor = (visit.get("decor", []) as Array).duplicate(true) if room == "house" else []
	_rebuild_decor()
	var went_in := Progress.day1_mark("inside") if visit.is_empty() else ""
	player = Models.hunter(Data.class_of_save(), Data.TEAM_COLORS[0], Data.weapon_for(Data.class_of_save(), String(Save.d.get("weapon", ""))), "", Save.d.get("look", {}))
	add_child(player)
	ppos = Vector3(W * 0.5, 0, D - 0.9)
	player.position = ppos
	cam.snap(Vector3(W * 0.5, 0, D * 0.5 - 0.6))
	_spawn_kin()
	_build_ui()
	if went_in != "":
		_day1_ticked(went_in)
	Sfx.play_ambience("")
	Sfx.play("whoosh", null, -14.0)

func _build_env() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("0c0d12")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("ffe6c8")
	e.ambient_light_energy = 0.38
	e.glow_enabled = true; e.glow_intensity = 0.5
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, -25, 0)
	sun.light_color = Color("fff0dc"); sun.light_energy = 0.55
	sun.shadow_enabled = true
	add_child(sun)
	var warm := OmniLight3D.new()
	warm.light_color = Color("ffd8a8"); warm.light_energy = 0.7; warm.omni_range = 12.0
	warm.position = Vector3(5, 3.2, 4)
	add_child(warm)

func _build_room() -> void:
	var floor_c: Color = R["floor"]; var wall_c: Color = R["wall"]
	# floor boards
	for z in D:
		var plank := Models.part(self, Models.box(W, 0.12, 0.98), Models.toon(floor_c.darkened(0.05 if z % 2 == 0 else 0.0), false), Vector3(W * 0.5, -0.06, z + 0.5))
		plank.name = "Plank%d" % z
	var wall := Models.toon(wall_c)
	var trim := Models.toon(Color("7a5236"))
	Models.part(self, Models.box(W + 0.4, 2.8, 0.2), wall, Vector3(W * 0.5, 1.4, -0.1))
	Models.part(self, Models.box(0.2, 2.8, D + 0.2), wall, Vector3(-0.1, 1.4, D * 0.5))
	Models.part(self, Models.box(0.2, 2.8, D + 0.2), wall, Vector3(W + 0.1, 1.4, D * 0.5))
	Models.part(self, Models.box(W + 0.4, 0.16, 0.24), trim, Vector3(W * 0.5, 0.08, 0.0))
	# windows on the back wall
	for wx in [W * 0.25, W * 0.75]:
		Models.part(self, Models.box(1.3, 0.9, 0.05), Models.toon(Color("9fd0ff"), false, 0.5), Vector3(wx, 1.7, 0.01))
		Models.part(self, Models.box(1.45, 0.08, 0.1), trim, Vector3(wx, 1.22, 0.04))
	# the front is open toward the camera, with a low sill and a doormat
	Models.part(self, Models.box(W * 0.5 - 0.8, 0.35, 0.2), wall, Vector3((W * 0.5 - 0.8) * 0.5, 0.17, D + 0.1))
	Models.part(self, Models.box(W * 0.5 - 0.8, 0.35, 0.2), wall, Vector3(W - (W * 0.5 - 0.8) * 0.5, 0.17, D + 0.1))
	Models.part(self, Models.box(1.4, 0.03, 0.8), Models.toon(Color("8a6a3a"), false), Vector3(W * 0.5, 0.015, D - 0.4))
	spots.append({"kind": "door", "pos": Vector3(W * 0.5, 0, D - 0.4), "label": "Go outside"})
	if room == "house":
		# fixed pieces: the kin journal and the gramophone
		var lect := Node3D.new(); add_child(lect); lect.position = Vector3(7.5, 0, 0.5)
		Models.part(lect, Models.box(0.5, 1.0, 0.4), trim, Vector3(0, 0.5, 0))
		Models.part(lect, Models.box(0.6, 0.06, 0.45), Models.toon(Color("f1e6cf")), Vector3(0, 1.04, 0), Vector3.ONE, Vector3(-0.3, 0, 0))
		var gram := Node3D.new(); add_child(gram); gram.position = Vector3(8.5, 0, 0.5)
		Models.part(gram, Models.box(0.6, 0.7, 0.5), trim, Vector3(0, 0.35, 0))
		Models.part(gram, Models.cyl(0.25, 0.25, 0.03, 18), Models.toon(Color("1e1e24")), Vector3(0, 0.72, 0))
		Models.part(gram, Models.cyl(0.05, 0.3, 0.45, 14), Models.toon(Color("d9b04a"), false, 0.3), Vector3(0.12, 1.05, -0.05), Vector3.ONE, Vector3(-0.6, 0, 0))
		occ[Vector2i(7, 0)] = -2; occ[Vector2i(8, 0)] = -2
		if visit.is_empty():
			spots.append({"kind": "journal", "pos": Vector3(7.5, 0, 1.2), "label": "Read the kin journal"})
			spots.append({"kind": "music", "pos": Vector3(8.5, 0, 1.2), "label": "Play some music"})

# ------------------------------------------------------------------ furniture on the grid
static func footprint(id: String, r: int) -> Vector2i:
	var sz: Array = Data.FURN[id]["size"]
	return Vector2i(int(sz[0]), int(sz[1])) if r % 2 == 0 else Vector2i(int(sz[1]), int(sz[0]))

func _make_piece(id: String, r: int) -> Node3D:
	var pivot := Node3D.new()
	var sz: Array = Data.FURN[id]["size"]
	var m := Models.furniture(id)
	m.position = Vector3(-float(sz[0]) * 0.5, 0, -float(sz[1]) * 0.5)
	pivot.add_child(m)
	pivot.rotation.y = -r * PI * 0.5
	return pivot

func _place_node(n: Node3D, id: String, x: int, z: int, r: int) -> void:
	var fp := footprint(id, r)
	n.position = Vector3(x + fp.x * 0.5, 0, z + fp.y * 0.5)

func _rebuild_decor() -> void:
	for n in nodes:
		n.queue_free()
	nodes.clear()
	for k in occ.keys():
		if occ[k] != -2: occ.erase(k)
	var keep: Array = []
	for e in decor:
		if typeof(e) == TYPE_DICTIONARY and Data.FURN.has(e.get("id", "")):
			keep.append(e)
	decor.clear()
	if visit.is_empty():
		decor.append_array(keep)
	else:
		# someone else's room: drop anything that overlaps, sits in the doorway or is out of bounds
		for e in keep:
			var r := int(e.get("r", 0)) % 4
			if _fits(String(e["id"]), int(e["x"]), int(e["z"]), r):
				decor.append(e)
				if not Data.FURN[e["id"]].get("walk", false):
					var fp := footprint(e["id"], r)
					for dz in fp.y:
						for dx in fp.x:
							occ[Vector2i(int(e["x"]) + dx, int(e["z"]) + dz)] = decor.size() - 1
	for i in decor.size():
		var e: Dictionary = decor[i]
		var r := int(e.get("r", 0)) % 4
		var n := _make_piece(e["id"], r)
		add_child(n)
		_place_node(n, e["id"], int(e["x"]), int(e["z"]), r)
		nodes.append(n)
		if not Data.FURN[e["id"]].get("walk", false):
			var fp := footprint(e["id"], r)
			for dz in fp.y:
				for dx in fp.x:
					occ[Vector2i(int(e["x"]) + dx, int(e["z"]) + dz)] = i

func _fits(id: String, x: int, z: int, r: int, ignore := -1) -> bool:
	var fp := footprint(id, r)
	if x < 0 or z < 0 or x + fp.x > W or z + fp.y > D:
		return false
	var walk: bool = Data.FURN[id].get("walk", false)
	for dz in fp.y:
		for dx in fp.x:
			var c := Vector2i(x + dx, z + dz)
			if c.y >= D - 1 and absf(c.x + 0.5 - W * 0.5) < 1.2:
				return false            # keep the doorway clear
			if not walk and occ.has(c) and occ[c] != ignore:
				return false
			if decorating and not walk and absf(c.x + 0.5 - ppos.x) < 0.85 and absf(c.y + 0.5 - ppos.z) < 0.85:
				return false            # not on top of yourself
	if walk:
		# rugs can't overlap other rugs
		for i in decor.size():
			if i == ignore or not Data.FURN[decor[i]["id"]].get("walk", false): continue
			var ofp := footprint(decor[i]["id"], int(decor[i].get("r", 0)))
			if Rect2i(int(decor[i]["x"]), int(decor[i]["z"]), ofp.x, ofp.y).intersects(Rect2i(x, z, fp.x, fp.y)):
				return false
	return true

func _blocked(x: float, z: float) -> bool:
	if x < 0.35 or z < 0.35 or x > W - 0.35 or z > D - 0.2:
		return true
	for o in [Vector2(0, 0), Vector2(0.28, 0), Vector2(-0.28, 0), Vector2(0, 0.28), Vector2(0, -0.28)]:
		if occ.has(Vector2i(int(floor(x + o.x)), int(floor(z + o.y)))):
			return true
	return false

# ------------------------------------------------------------------ kin
func _spawn_kin() -> void:
	var roster: Array = (visit.get("roster", []) if not visit.is_empty() else Save.d["roster"])
	var active: String = (visit.get("active", "") if not visit.is_empty() else Save.d.get("active", ""))
	var here: Array = []
	for rec in roster:
		if room == "house" and rec["uid"] == active: here.push_front(rec)
		elif room != "house" and rec["uid"] != active: here.append(rec)
	if room == "house":
		for rec in roster:
			if here.size() >= 3: break
			if not here.has(rec): here.append(rec)
	for rec in here.slice(0, 4):
		var n := Models.kin(rec["species"], rec)
		var at := _free_spot()
		n.position = at
		add_child(n)
		kins.append({"rec": rec, "node": n, "pos": at, "goal": at, "t": randf() * 2.0, "hop": 0.0})

func _free_spot() -> Vector3:
	for _i in 40:
		var p := Vector3(randf_range(0.6, W - 0.6), 0, randf_range(0.6, D - 1.2))
		if not _blocked(p.x, p.z): return p
	return Vector3(W * 0.5, 0, D - 1.5)

# ------------------------------------------------------------------ loop
func _process(delta: float) -> void:
	var d := minf(delta, 0.05)
	_move_player(d)
	for k in kins:
		k["t"] -= d
		if k["t"] <= 0.0:
			k["t"] = randf_range(2.0, 4.5)
			k["goal"] = _free_spot() if randf() < 0.7 else ppos + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
		var pos: Vector3 = k["pos"]
		if _blocked(pos.x, pos.z):
			# something got put down on top of it: hop out to open floor
			pos = _free_spot()
			k["goal"] = pos
		var to := Vector2(k["goal"].x - pos.x, k["goal"].z - pos.z)
		var n: Node3D = k["node"]
		if to.length() > 0.3:
			var st := to.normalized() * 1.8 * d
			if not _blocked(pos.x + st.x, pos.z): pos.x += st.x
			if not _blocked(pos.x, pos.z + st.y): pos.z += st.y
			n.rotation.y = lerp_angle(n.rotation.y, atan2(-to.x, -to.y), minf(1.0, d * 8.0))
			k["hop"] += d * 9.0
		k["pos"] = pos
		n.position = pos
		n.get_node("Body").position.y = absf(sin(k["hop"])) * 0.1
	cam.follow(Vector3(W * 0.5, 0, D * 0.5 - 0.6).lerp(ppos, 0.2), d, false)
	# steps ticked somewhere else while in here (the inventory) show up straight away
	if is_instance_valid(day1_box) and int(day1_box.get_meta("n", -1)) != Progress.day1_steps().size():
		_refresh_day1()
		_refresh_gems()
	if decorating:
		_update_ghost()
	else:
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
	if not _blocked(nx, ppos.z): ppos.x = nx
	var nz := ppos.z + hv.y * d
	if not _blocked(ppos.x, nz): ppos.z = nz
	pvel = Vector3(hv.x, 0, hv.y)
	player.position = ppos
	if hv.length() > 0.3:
		pface = lerp_angle(pface, atan2(-hv.x, -hv.y), minf(1.0, d * 14.0))
	player.rotation.y = pface
	if not player.has_meta("anim"): player.set_meta("anim", HunterAnim.new(player))
	(player.get_meta("anim") as HunterAnim).update(d, {"vel": pvel, "face": pface, "fired": 99.0})

func _find_interact() -> void:
	var best := {}; var bd := 1.3
	for s in spots:
		var dd := Vector2(s["pos"].x - ppos.x, s["pos"].z - ppos.z).length()
		if dd < bd: bd = dd; best = s
	for k in kins:
		var dd := Vector2(k["pos"].x - ppos.x, k["pos"].z - ppos.z).length()
		if dd < bd: bd = dd; best = {"kind": "kin", "k": k, "label": "Pet %s" % k["rec"]["name"]}
	interact = best
	prompt_box.visible = not best.is_empty() and panel_open == ""
	if prompt_box.visible:
		prompt_lbl.text = Settings.key_cap("interact") + "  " + String(best["label"])
		prompt_box.reset_size()
		var vp := get_viewport().get_visible_rect().size
		prompt_box.position = Vector2((vp.x - prompt_box.size.x) * 0.5, vp.y - 120.0)

func _use(it: Dictionary) -> void:
	Sfx.play("click")
	match String(it["kind"]):
		"door": _leave()
		"kin": _pet_kin(it["k"])
		"journal": _open_journal()
		"music": _open_music()

## Petting indoors counts just like outside: joy, likes, the memory and the first-day list.
func _pet_kin(k: Dictionary) -> void:
	var rec: Dictionary = k["rec"]
	Sfx.play("kin_happy", null, -4.0)
	fx.burst(k["pos"] + Vector3(0, 0.9, 0), Color("ff8fb0"), 10, 1.6)
	k["t"] = 1.2; k["goal"] = k["pos"]
	if not visit.is_empty():
		return
	var loves_pet: bool = rec.get("likes", {}).get("play", "") == "pet"
	var now_s := Time.get_ticks_msec() / 1000.0
	if now_s >= float(k.get("pet_ok", 0.0)):
		k["pet_ok"] = now_s + 20.0
		Care.change(rec, "joy", 12.0 if loves_pet else 5.0)
	if loves_pet and Care.discover(rec, "play"): _toast("%s loves scratches" % rec["name"])
	if int(rec.get("pet_m", -1)) != int(Save.d["matches"]):
		rec["pet_m"] = int(Save.d["matches"])
		Save.remember(rec, "petted", "got a long scratch behind the ears", 1.5)
	Save.save_game()
	var r := Progress.day1_mark("pet")
	if r != "":
		_day1_ticked(r)

func _day1_ticked(r: String) -> void:
	Sfx.play("unlock", null, -8.0)
	if r == "all":
		_toast("First day done! +30 gems")
	_refresh_day1()
	_refresh_gems()

func _refresh_gems() -> void:
	var g := root_ui.find_child("Gems", true, false) as Label
	if g: g.text = "%d gems" % int(Save.d["gems"])

## The first-day checklist stays on screen indoors too.
var day1_box: PanelContainer = null
func _refresh_day1() -> void:
	if is_instance_valid(day1_box):
		day1_box.queue_free()
	day1_box = null
	if not visit.is_empty() or not Progress.day1_active():
		return
	day1_box = Progress.day1_box()
	root_ui.add_child(day1_box)

func _leave() -> void:
	if decorating: _toggle_decorate()
	Save.save_game()
	if not visit.is_empty():
		Game.goto("home", {"visit": visit, "visit_id": visit_id, "spawn": room})
	else:
		Game.goto("home", {"spawn": room})

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu") and not Overlay.is_open():
		if decorating and not held.is_empty():
			_drop_held(false)
		elif decorating:
			_toggle_decorate()
		elif panel_open != "":
			_close_panel()
		else:
			Overlay.open_pause("home")
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and visit.is_empty() and panel_open == "" and not Overlay.is_open():
		var kc := (event as InputEventKey).physical_keycode
		if event.is_action_pressed("build"):
			_toggle_decorate()
		elif decorating and event.is_action_pressed("rotate") and not held.is_empty():
			held["r"] = (int(held["r"]) + 1) % 4
			_make_ghost()
		elif decorating and (kc == KEY_DELETE or kc == KEY_X) and not held.is_empty():
			_drop_held(true)
	if decorating and event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if held.is_empty(): _pick_up_at_mouse()
			else: _place_held()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if not held.is_empty():
				held["r"] = (int(held["r"]) + 1) % 4
				_make_ghost()

# ------------------------------------------------------------------ decorating
func _toggle_decorate() -> void:
	decorating = not decorating
	if not decorating:
		if not held.is_empty(): _drop_held(false)
		if is_instance_valid(deco_bar): deco_bar.queue_free()
		deco_bar = null
		Save.save_game()
		_deco_button_text()
		return
	_close_panel()
	prompt_box.visible = false
	_build_deco_bar()
	_deco_button_text()

func _mouse_cell() -> Vector2:
	var p := cam.mouse_on_plane(0.0)
	return Vector2(p.x, p.z)

func _update_ghost() -> void:
	if held.is_empty() or ghost == null:
		return
	var m := _mouse_cell()
	var fp := footprint(held["id"], int(held["r"]))
	var cx := int(round(m.x - fp.x * 0.5)); var cz := int(round(m.y - fp.y * 0.5))
	ghost_cell = Vector2i(cx, cz)
	ghost_ok = _fits(held["id"], cx, cz, int(held["r"]), int(held.get("from", -1)))
	_place_node(ghost, held["id"], cx, cz, int(held["r"]))
	ghost.position.y = 0.04
	for mi in ghost.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).transparency = 0.35
	var ring: MeshInstance3D = ghost.get_node_or_null("Ring")
	if ring:
		(ring.material_override as StandardMaterial3D).albedo_color = Color(0.5, 1.0, 0.6, 0.4) if ghost_ok else Color(1.0, 0.4, 0.35, 0.45)

func _make_ghost() -> void:
	if ghost: ghost.queue_free()
	ghost = _make_piece(held["id"], int(held["r"]))
	var fp := footprint(held["id"], int(held["r"]))
	var ring := MeshInstance3D.new(); ring.name = "Ring"
	var pm := PlaneMesh.new(); pm.size = Vector2(fp.x, fp.y); ring.mesh = pm
	var mat := StandardMaterial3D.new(); mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.5, 1, 0.6, 0.4)
	ring.material_override = mat
	ring.rotation.y = int(held["r"]) * PI * 0.5   # undo the pivot's turn: the footprint is already rotated
	ring.position.y = 0.02
	ghost.add_child(ring)
	add_child(ghost)
	_update_ghost()

func _take(id: String) -> void:
	# from your stash, or buy one if you have none
	var inv: Dictionary = Save.d["furniture"]
	if int(inv.get(id, 0)) <= 0:
		var price := int(Data.FURN[id]["price"])
		if int(Save.d["gems"]) < price:
			_toast("You need %d gems for that" % price)
			return
		Save.d["gems"] = int(Save.d["gems"]) - price
		inv[id] = int(inv.get(id, 0)) + 1
		Sfx.play("pickup")
	inv[id] = int(inv[id]) - 1
	held = {"id": id, "r": 0, "from": -1}
	_make_ghost()
	_build_deco_bar()

func _pick_up_at_mouse() -> void:
	var m := _mouse_cell()
	var c := Vector2i(int(floor(m.x)), int(floor(m.y)))
	var idx := -1
	if occ.has(c) and occ[c] >= 0:
		idx = occ[c]
	else:
		# rugs and cushions aren't in the walk-blocking grid
		for i in decor.size():
			var fp := footprint(decor[i]["id"], int(decor[i].get("r", 0)))
			if Rect2i(int(decor[i]["x"]), int(decor[i]["z"]), fp.x, fp.y).has_point(c):
				idx = i
	if idx < 0:
		return
	var e: Dictionary = decor[idx]
	held = {"id": e["id"], "r": int(e.get("r", 0)), "from": idx}
	nodes[idx].visible = false
	Sfx.play("click")
	_make_ghost()

func _place_held() -> void:
	if not ghost_ok:
		Sfx.play("warn", null, -12.0)
		return
	var e := {"id": held["id"], "x": ghost_cell.x, "z": ghost_cell.y, "r": int(held["r"])}
	if int(held.get("from", -1)) >= 0:
		decor[int(held["from"])] = e
	else:
		decor.append(e)
	held = {}
	if ghost: ghost.queue_free()
	ghost = null
	Sfx.play("build", null, -6.0)
	_rebuild_decor()
	fx.dust(nodes[-1].position, 6)
	Save.save_game()
	_build_deco_bar()

## Puts what you're holding away (into your stash), or back where it was if it came off the floor.
func _drop_held(to_stash: bool) -> void:
	if held.is_empty():
		return
	var from := int(held.get("from", -1))
	if from >= 0 and to_stash:
		decor.remove_at(from)
		Save.d["furniture"][held["id"]] = int(Save.d["furniture"].get(held["id"], 0)) + 1
	elif from < 0:
		Save.d["furniture"][held["id"]] = int(Save.d["furniture"].get(held["id"], 0)) + 1
	held = {}
	if ghost: ghost.queue_free()
	ghost = null
	_rebuild_decor()
	Save.save_game()
	if decorating: _build_deco_bar()

# ------------------------------------------------------------------ ui
var deco_btn: Button

func _build_ui() -> void:
	var ui := CanvasLayer.new(); add_child(ui)
	root_ui = Control.new(); root_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root_ui.theme = UI.theme()
	root_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root_ui)
	var top := UI.glass(8, 14)
	top.position = Vector2(16, 14)
	var th := UI.hbox(14); top.add_child(th)
	th.add_child(UI.title(String(R["name"]) if visit.is_empty() else "%s's house" % String(visit.get("name", "Their")), 24, UI.ACCENT))
	var sub := UI.label("%d gems" % int(Save.d["gems"]), 15)
	sub.name = "Gems"
	th.add_child(sub)
	root_ui.add_child(top)
	prompt_box = UI.glass(10, 16)
	prompt_lbl = UI.label("", 18, UI.GOLD, UI.big)
	prompt_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	prompt_box.add_child(prompt_lbl)
	root_ui.add_child(prompt_box)
	if visit.is_empty():
		deco_btn = UI.primary("Decorate  (%s)" % Settings.key_cap("build"), _toggle_decorate, 200)
		deco_btn.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		deco_btn.position = Vector2(16, -64)
		root_ui.add_child(deco_btn)
		deco_btn.reset_size()
		deco_btn.offset_top = -64; deco_btn.offset_bottom = -16; deco_btn.offset_left = 16; deco_btn.offset_right = 216
	panel_dim = UI.backdrop()
	panel_dim.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and panel_open != "":
			_close_panel())
	root_ui.add_child(panel_dim)
	panel_host = CenterContainer.new()
	panel_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_ui.add_child(panel_host)
	_refresh_day1()

func _deco_button_text() -> void:
	if deco_btn:
		deco_btn.text = ("Done decorating  (%s)" if decorating else "Decorate  (%s)") % Settings.key_cap("build")
	var g := root_ui.find_child("Gems", true, false)
	if g: (g as Label).text = "%d gems" % int(Save.d["gems"])

func _build_deco_bar() -> void:
	if is_instance_valid(deco_bar): deco_bar.queue_free()
	_deco_button_text()
	var bar := UI.card(Color(0.06, 0.07, 0.1, 0.92), 10, 14)
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 232; bar.offset_right = -16; bar.offset_top = -170; bar.offset_bottom = -16
	var col := UI.vbox(6); bar.add_child(col)
	deco_hint = UI.label("Pick something to place. Click a piece in the room to move it.   Left click place  ·  Right click or R turn  ·  Del put away  ·  Esc cancel", 13, UI.MUTED)
	deco_hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	col.add_child(deco_hint)
	# no scrolling: the catalog shows a page at a time
	var line := UI.hbox(8)
	line.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(line)
	var inv: Dictionary = Save.d["furniture"]
	# what you own first, then the catalog
	var ids: Array = Data.FURN.keys()
	ids.sort_custom(func(a, b): return int(inv.get(a, 0)) > int(inv.get(b, 0)))
	var vpw := get_viewport().get_visible_rect().size.x
	var per := maxi(2, int((vpw - 232.0 - 16.0 - 28.0 - 2.0 * 60.0) / 140.0))
	var pages := int(ceil(ids.size() / float(per)))
	deco_page = clampi(deco_page, 0, pages - 1)
	var prev := UI.button("‹", func(): deco_page -= 1; _build_deco_bar(), 52)
	prev.custom_minimum_size.y = 78; prev.disabled = deco_page == 0
	line.add_child(prev)
	var row := UI.hbox(8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(row)
	for id in ids.slice(deco_page * per, deco_page * per + per):
		var f: Dictionary = Data.FURN[id]
		var n := int(inv.get(id, 0))
		var fid: String = id
		var b := UI.button("%s\n%s" % [f["name"], ("×%d" % n) if n > 0 else "%d gems" % int(f["price"])], func(): if held.is_empty(): _take(fid), 132)
		b.custom_minimum_size.y = 78
		if n > 0: b.theme_type_variation = "Chosen"
		elif int(Save.d["gems"]) < int(f["price"]): b.disabled = true
		row.add_child(b)
	var next := UI.button("›", func(): deco_page += 1; _build_deco_bar(), 52)
	next.custom_minimum_size.y = 78; next.disabled = deco_page >= pages - 1
	line.add_child(next)
	root_ui.add_child(bar)
	deco_bar = bar

func _toast(txt: String) -> void:
	var c := UI.card(Color(0.06, 0.07, 0.1, 0.9), 12, 18)
	var l := UI.label(txt, 20, UI.GOLD, UI.big)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	c.add_child(l)
	root_ui.add_child(c)
	c.reset_size()
	var vp := get_viewport().get_visible_rect().size
	c.position = Vector2((vp.x - c.size.x) * 0.5, 90)
	var tw := create_tween()
	tw.tween_interval(2.0)
	tw.tween_property(c, "modulate:a", 0.0, 0.4)
	tw.tween_callback(c.queue_free)

func _new_panel(title_txt: String, width := 560.0) -> VBoxContainer:
	_close_panel()
	var pb := UI.scroll_panel(title_txt, width, _close_panel)
	panel_host.add_child(pb[0])
	panel_open = title_txt
	UI.show_backdrop(panel_dim, true)
	UI.pop_in(pb[0])
	return pb[1]

var panel_dim: ColorRect = null

func _close_panel() -> void:
	for ch in panel_host.get_children():
		ch.queue_free()
	if panel_open != "" and panel_dim: UI.show_backdrop(panel_dim, false)
	panel_open = ""

## Every kin you have, and who comes along on expeditions.
func _open_journal() -> void:
	var v := _new_panel("Kin journal", 640)
	v.add_child(UI.label("Your kin. The one you bring on expeditions is your partner.", 14, UI.MUTED))
	for rec in Save.d["roster"]:
		var row := UI.card(UI.CARD, 10, 10)
		var h := UI.hbox(12); row.add_child(h)
		var sp: Dictionary = Data.KIN[rec["species"]]
		var dot := ColorRect.new(); dot.color = sp["color"]; dot.custom_minimum_size = Vector2(14, 14)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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
				_open_journal()))
		v.add_child(row)

func _open_music() -> void:
	var v := _new_panel("Gramophone", 560)
	var heard: Array = Save.d.get("music", [])
	v.add_child(UI.label("Every tune you've heard on your travels. Pick one to play at home.", 14, UI.MUTED))
	for tid in Data.MUSIC:
		var md: Dictionary = Data.MUSIC[tid]
		var row := UI.hbox(10)
		var known := heard.has(tid)
		var l := UI.label(String(md["name"]) if known else "???  ·  " + String(md.get("hint", "")), 15, UI.INK if known else UI.MUTED)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if known:
			var t: String = tid
			row.add_child(UI.choice("Playing" if Sfx.music_lock == tid else "Play", Sfx.music_lock == tid, func():
				Sfx.music_lock = t
				Sfx.play_music(t, 1.0)
				_open_music(), 110))
		v.add_child(row)
	if Sfx.music_lock != "":
		v.add_child(UI.button("Back to the island's own music", func():
			Sfx.music_lock = ""
			_open_music(), 300))

## The menu's "I'm stuck": back to the doormat.
func unstick() -> void:
	ppos = Vector3(W * 0.5, 0, D - 1.0)
	if player: player.position = ppos
