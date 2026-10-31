class_name HomeTraining
extends RefCounted
## The Training Grounds: a small isle every home has, joined to the main island by a short bridge
## south of the portal. Inside it your whole kit works (weapon on LMB / RMB, glove on Q, your kin's
## ability on E, the ultimate on R) against practice dummies: one that stands still, one that
## strafes, one that lobs slow orbs at you to dodge, and a row of range targets. There's a climbing
## wall to mantle, a gap to glide across to a little islet, and a pad that resets your cooldowns.
## Everywhere else at home you only move (walk, jump, dash, glide).
##
## The numbers and names come from the match's content (WeaponDef, AbilityDef, Gear, KinDef,
## UltimateDef); the casting here is a small stand-alone version, because the match's runner needs a
## whole Match (hunters, mobs, projectiles, HUD) to run in.

const C := Vector2(40, 56)          # the isle
const R := Vector2(8.0, 4.4)
const GAP_C := Vector2(55, 57)      # the islet across the glide gap
const GAP_R := Vector2(2.6, 2.2)
const BRIDGE := [39, 46, 40, 53]
const WALL := [33, 56, 35, 57]      # the climbing wall: a block two terraces high
const PAD := Vector3(42.5, 0, 58.5)
const STILL := Vector3(36.5, 0, 54.5)
const MOVER := Vector3(40.5, 0, 55.0)
const SHOOTER := Vector3(44.5, 0, 54.0)
const RACK := Vector3(38.5, 0, 58.8)    # the Try-on rack: any class, weapon, glove and kin, here only
const TAGS := {"light": "skirmisher · mobile · fragile", "medium": "all-rounder · mid range", "heavy": "frontline · tank · close range"}
const TARGETS := [Vector3(46.5, 0, 57.5), Vector3(46.5, 0, 59.0), Vector3(45.0, 0, 60.0)]

var h
var dummies: Array = []        # {node, pos, kind, base, hits: [[t, dmg]], label, t}
var shots: Array = []          # {node, pos, vel, dmg, life, from}  (yours, or "orb" from the shooter)
var in_zone := false
var cds := {}                  # slot -> seconds left
var hud: Control = null
var slot_lbls := {}
var fire_t := 0.0
var orb_t := 2.0
var kit := {}                  # slot -> {name, cd, color, effects, kind}
var pad_t := 0.0
var now := 0.0
var try := {}                  # what you're trying on here: {cls, weapon, glove, kin}
var loaner: Node3D = null      # a kin of the species you're trying, when it isn't one of yours

func _init(home) -> void:
	h = home

static func defs() -> Array:
	return [["training", C, R], ["training_gap", GAP_C, GAP_R]]

static func reserved() -> Array:
	return [[int(C.x - R.x) - 1, int(C.y - R.y) - 1, int(C.x + R.x) + 1, int(C.y + R.y) + 1],
		[int(GAP_C.x - GAP_R.x) - 1, int(GAP_C.y - GAP_R.y) - 1, int(GAP_C.x + GAP_R.x) + 1, int(GAP_C.y + GAP_R.y) + 1],
		[BRIDGE[0] - 1, BRIDGE[1] - 1, BRIDGE[2] + 1, BRIDGE[3]]]

static func is_zone(world: World, p: Vector3) -> bool:
	return String(world.island_id(p.x, p.z)).begins_with("training")

## Before the meshes: the bridge's planks become ground, and the climbing wall rises.
func prepare() -> void:
	var w: World = h.world
	w.open_bridge(w.bridge_tiles(BRIDGE))
	for z in range(WALL[1], WALL[3] + 1):
		for x in range(WALL[0], WALL[2] + 1):
			if w.inb(x, z) and w.kind[w.idx(x, z)] == World.T_GROUND:
				w.level[w.idx(x, z)] = 2
				w.no_deco[w.idx(x, z)] = true
	for x in range(int(C.x - R.x) + 1, int(C.x + R.x)):
		for z in range(int(C.y - R.y) + 1, int(C.y + R.y)):
			if w.inb(x, z) and w.kind[w.idx(x, z)] == World.T_BLOCK and w.island_id(x, z) == "training":
				w.kind[w.idx(x, z)] = World.T_GROUND       # no rim trees in the way of practice
	w.paint_path(Vector2i(39, 41), Vector2i(39, 46), Color("9c7a52"), true)
	for z in range(int(C.y) - 1, int(C.y) + 2):
		for x in range(int(C.x) - 5, int(C.x) + 6):
			w.paint_tile(x, z, Color("c9a77a"))

func targets() -> Array:
	return [STILL, PAD, Vector3(C.x, 0, C.y)]

## The isle's things: planks, sign, dummies, targets, the reset pad, the zone's edge.
func build() -> void:
	var w: World = h.world
	var rng := RandomNumberGenerator.new(); rng.seed = 91
	for z in range(BRIDGE[1], BRIDGE[3] + 1):
		var i := w.idx(BRIDGE[0], z)
		if not w.bridge.has(i): continue
		for half in [0.25, 0.75]:
			var pl := Models.plank(rng, 1.98)
			pl.position = Vector3(BRIDGE[0] + 1.0, -0.04, z + half)
			h.add_child(pl)
	var sign := Models.signpost(["Training", "Grounds"]); sign.position = Vector3(41.6, 0, 45.2); sign.rotation.y = -0.2; h.add_child(sign)
	# the zone's edge: a soft glowing line across the bridge end
	var edge := MeshInstance3D.new(); var em := BoxMesh.new(); em.size = Vector3(2.2, 0.04, 0.12); edge.mesh = em
	edge.material_override = Models.glow_mat(Color(0.55, 1.0, 0.85, 0.55)); edge.position = Vector3(40.0, 0.05, 51.6)
	h.add_child(edge)
	for sx in [-1.0, 1.0]:
		var post := Models.part(h, Models.cyl(0.07, 0.09, 1.6, 8), Models.toon(Color("6a7a8a")), Vector3(40.0 + sx * 1.15, 0.8, 51.6))
		Models.part(h, Models.sphere(0.12, 8), Models.toon(Color("9ff0e0"), false, 1.2), Vector3(40.0 + sx * 1.15, 1.7, 51.6))
		post.name = "ZonePost"
	var rk := Node3D.new(); rk.position = RACK; h.add_child(rk)
	var wd := Models.toon(Color("7a5236"))
	for sx in [-0.9, 0.9]:
		Models.part(rk, Models.box(0.12, 1.6, 0.12), wd, Vector3(sx, 0.8, 0))
	Models.part(rk, Models.box(2.0, 0.1, 0.16), wd, Vector3(0, 1.5, 0))
	for k in 3:
		var cc: Color = Data.CLASSES[["light", "medium", "heavy"][k]]["color"]
		Models.part(rk, Models.box(0.36, 0.5 + k * 0.15, 0.08), Models.toon(cc), Vector3(-0.55 + k * 0.55, 1.1 - k * 0.05, 0.08))
	_label(rk, "Try-on rack", Vector3(0, 2.2, 0), UI.GOLD, 34)
	h.world.set_block_rect(int(RACK.x), int(RACK.z), int(RACK.x), int(RACK.z))
	_dummy(STILL, "still")
	_dummy(MOVER, "move")
	_dummy(SHOOTER, "shoot")
	for tp in TARGETS: _dummy(tp, "target")
	var pad := Node3D.new(); pad.position = PAD; h.add_child(pad)
	Models.part(pad, Models.cyl(0.75, 0.8, 0.12, 20), Models.toon(Color("4a5368")), Vector3(0, 0.06, 0))
	Models.part(pad, Models.cyl(0.55, 0.55, 0.03, 20), Models.glow_mat(Color(0.55, 1.0, 0.85, 0.7)), Vector3(0, 0.13, 0))
	_label(pad, "Reset cooldowns", Vector3(0, 1.0, 0), Color("9ff0e0"), 34)
	var wl := Node3D.new(); wl.position = Vector3(34.5, 0, 56.6); h.add_child(wl)
	_label(wl, "Climb: jump at the wall", Vector3(0, 2.9, 0), UI.INK, 30)
	var gl := Node3D.new(); gl.position = Vector3(48.6, 0, 56.5); h.add_child(gl)
	_label(gl, "Glide the gap: jump, hold Space", Vector3(0, 1.6, 0), UI.INK, 30)

func _label(parent: Node3D, text: String, at: Vector3, col: Color, size := 40) -> Label3D:
	var l := Label3D.new()
	l.text = text; l.font = UI.big; l.font_size = size; l.pixel_size = 0.01; l.outline_size = 10
	l.modulate = col; l.billboard = BaseMaterial3D.BILLBOARD_ENABLED; l.position = at
	parent.add_child(l)
	return l

func _dummy(at: Vector3, kind: String) -> void:
	var n := Node3D.new(); n.position = at; h.add_child(n)
	var straw := Models.toon(Color("d8b98a")); var wood := Models.toon(Color("7a5236"))
	var body := Node3D.new(); body.name = "Body"; n.add_child(body)
	if kind == "target":
		Models.part(body, Models.cyl(0.06, 0.06, 1.2, 6), wood, Vector3(0, 0.6, 0))
		for k in 3:
			Models.part(body, Models.cyl(0.5 - k * 0.15, 0.5 - k * 0.15, 0.06, 18), Models.toon([Color("f3eee2"), Color("e0607e"), Color("f2c84a")][k]), Vector3(0, 1.35, 0.03 * k), Vector3.ONE, Vector3(PI / 2, 0, 0))
	else:
		Models.part(body, Models.cyl(0.07, 0.07, 1.4, 6), wood, Vector3(0, 0.7, 0))
		Models.part(body, Models.capsule(0.32, 0.95), straw, Vector3(0, 1.15, 0))
		Models.part(body, Models.sphere(0.24, 10), straw, Vector3(0, 1.8, 0))
		Models.part(body, Models.box(1.0, 0.08, 0.08), wood, Vector3(0, 1.3, 0))
		var band: Color = {"still": Color("8fe0a0"), "move": Color("5ab0f0"), "shoot": Color("e0607e")}[kind]
		Models.part(body, Models.cyl(0.34, 0.34, 0.1, 14), Models.toon(band), Vector3(0, 1.05, 0))
	var lbl := _label(n, {"still": "Dummy", "move": "Strafing dummy", "shoot": "Shooting dummy", "target": "Target"}[kind], Vector3(0, 2.5, 0), UI.INK, 30)
	dummies.append({"node": n, "pos": at, "base": at, "kind": kind, "hits": [], "label": lbl, "name": lbl.text, "t": 0.0})
	h.world.set_block_rect(int(floor(at.x)), int(floor(at.z)), int(floor(at.x)), int(floor(at.z)))

# ------------------------------------------------------------------ your kit, from the match content
func load_kit() -> void:
	kit.clear()
	var wid: String = String(try.get("weapon", h._weapon()))
	var wd: WeaponDef = Content.weapon(wid) if wid != "" else null
	var pr: Dictionary = wd.primary if wd else Data.WEAPONS.get("rifle", {})
	kit["fire"] = {"name": String(pr.get("name", "Weapon")), "cd": float(pr.get("rate", 0.2)) * float(pr.get("burst", 1)), "color": pr.get("color", Color("d9ff66")),
		"dmg": float(pr.get("dmg", 4.0)) * float(pr.get("burst", 1)) * float(pr.get("pellets", 1)), "range": float(pr.get("range", 9.0)), "speed": float(pr.get("speed", 60.0)),
		"melee": float(pr.get("range", 9.0)) < 3.6 or pr.has("arc") or pr.has("swing")}
	if wd and wd.utility != "":
		var ad := Content.ability(wd.utility)
		if ad: kit["secondary"] = _from_ability(ad)
	var glove := String(try.get("glove", _glove()))
	if glove != "":
		kit["gear1"] = {"name": String(Gear.ALL.get(glove, {}).get("name", glove.capitalize())), "cd": Gear.cd_of(glove, 1), "color": Color("ffd36a"), "effects": Gear.effects_of(glove, 1)}
	var ak: Dictionary = Save.active_kin()
	var ksp := String(try.get("kin", ak.get("species", "")))
	var kd: KinDef = Content.kin(ksp) if ksp != "" else null
	if kd and not kd.abilities.is_empty():
		var sd := Content.ability(String(kd.abilities[0]))
		if sd:
			kit["signature"] = _from_ability(sd)
			kit["signature"]["kin"] = true
	if kd and kd.ultimate != "":
		var ud := Content.ultimate(kd.ultimate)
		kit["ultimate"] = {"name": ud.display_name if ud else "Ultimate", "cd": 20.0, "color": Color("ff9ac8"), "effects": [{"type": "area", "dmg": 40.0, "r": 4.0}]}

func _from_ability(ad: AbilityDef) -> Dictionary:
	return {"name": ad.short if ad.short != "" else ad.display_name, "cd": ad.cooldown, "color": ad.color, "effects": ad.effects}

## The glove on Q: the one in your loadout if it's an active glove, else a training glove.
func _glove() -> String:
	var lo: Dictionary = Save.d.get("loadout", {})
	for slot in lo:
		var it := Econ.find(String(lo[slot]))
		var gid := String(it.get("id", ""))
		if Gear.ALL.has(gid) and Gear.active(gid): return gid
	for gid in Gear.ALL:
		if Gear.active(gid): return String(gid)
	return ""

# ------------------------------------------------------------------ every frame
func tick(d: float) -> void:
	now += d
	var was := in_zone
	in_zone = is_zone(h.world, h.ppos) and h.visit.is_empty()
	if in_zone != was:
		if in_zone:
			load_kit()
			h._toast("Training Grounds: abilities on")
			_build_hud()
		else:
			h._toast("Leaving the Training Grounds: abilities off")
			if not try.is_empty():
				try = {}
				h._refresh_player_model()
			if is_instance_valid(loaner): loaner.queue_free()
			loaner = null
			if is_instance_valid(hud): hud.queue_free()
			hud = null
	for k in cds: cds[k] = maxf(0.0, float(cds[k]) - d)
	fire_t = maxf(0.0, fire_t - d)
	for dm in dummies:
		dm["t"] = float(dm["t"]) + d
		if dm["kind"] == "move":
			dm["pos"] = (dm["base"] as Vector3) + Vector3(sin(float(dm["t"]) * 0.9) * 2.2, 0, 0)
			(dm["node"] as Node3D).position = dm["pos"]
		var hs: Array = dm["hits"]
		while not hs.is_empty() and now - float(hs[0][0]) > 4.0: hs.pop_front()
		var tot := 0.0
		for e in hs: tot += float(e[1])
		(dm["label"] as Label3D).text = String(dm["name"]) if hs.is_empty() else "%s\n%d dmg · %.0f dps" % [dm["name"], int(round(tot)), tot / 4.0]
		var b: Node3D = (dm["node"] as Node3D).get_node("Body")
		b.rotation.z = lerpf(b.rotation.z, 0.0, minf(1.0, d * 6.0))
	if is_instance_valid(loaner) and Vector2(loaner.position.x - h.ppos.x, loaner.position.z - h.ppos.z).length() > 1.6:
		loaner.position = loaner.position.lerp(h.ppos + Vector3(1.1, 0, 0.6), minf(1.0, d * 3.0))
	if in_zone:
		orb_t -= d
		if orb_t <= 0.0:
			orb_t = 2.4
			for dm in dummies:
				if dm["kind"] == "shoot":
					var from: Vector3 = dm["pos"] + Vector3(0, 1.3, 0)
					var dir: Vector3 = (h.ppos + Vector3(0, 1.0, 0) - from)
					dir.y = 0.0
					_shot(from, dir.normalized() * 6.0, 0.0, 5.0, Color("ff7a8a"), 0.22, "orb")
		if Input.is_action_pressed("fire") and h.panel_open == "" and not (h.hb and h.hb.active) and not Overlay.is_open():
			cast("fire")
		if Vector2(h.ppos.x - PAD.x, h.ppos.z - PAD.z).length() < 0.8:
			pad_t -= d
			if pad_t <= 0.0 and cds.values().any(func(v): return float(v) > 0.0):
				for k in cds: cds[k] = 0.0
				h._toast("Cooldowns reset")
				Sfx.play("unlock", null, -8.0)
				h.fx.ring(PAD, 1.6, Color(0.6, 1.0, 0.85, 0.9), 0.4)
				pad_t = 1.5
		_update_hud()
	_step_shots(d)

func _step_shots(d: float) -> void:
	for s in shots.duplicate():
		s["life"] = float(s["life"]) - d
		var p: Vector3 = s["pos"] + (s["vel"] as Vector3) * d
		s["pos"] = p
		(s["node"] as Node3D).position = p
		var gone := float(s["life"]) <= 0.0 or _wall(p)
		if s["from"] == "orb":
			if Vector2(p.x - h.ppos.x, p.z - h.ppos.z).length() < 0.55 and absf(p.y - (h.py + 1.0)) < 1.2:
				gone = true
				if h.dashing(): _float_text(h.ppos + Vector3(0, 2.2, 0), "Dodged!", UI.GOOD)
				else:
					_float_text(h.ppos + Vector3(0, 2.2, 0), "Hit", Color("ff8a7a"))
					h.cam.add_trauma(0.15)
		else:
			var dm := _dummy_at(p, 0.55)
			if not dm.is_empty():
				hit(dm, float(s["dmg"]), s["color"])
				gone = true
		if gone:
			(s["node"] as Node3D).queue_free()
			shots.erase(s)

func _wall(p: Vector3) -> bool:
	return h.world.is_block(p.x, p.z) and _dummy_at(p, 0.6).is_empty()

func _dummy_at(p: Vector3, r: float) -> Dictionary:
	for dm in dummies:
		if Vector2(p.x - dm["pos"].x, p.z - dm["pos"].z).length() < r: return dm
	return {}

func _shot(from: Vector3, vel: Vector3, dmg: float, life: float, col: Color, size: float, who: String) -> void:
	var n := MeshInstance3D.new(); n.mesh = Models.sphere(size, 8)
	n.material_override = Models.glow_mat(Color(col, 0.95))
	n.position = from
	h.add_child(n)
	shots.append({"node": n, "pos": from, "vel": vel, "dmg": dmg, "life": life, "from": who, "color": col})

## A dummy takes a hit: it wobbles, a number pops up, and its readout counts it.
func hit(dm: Dictionary, dmg: float, col := Color.WHITE) -> void:
	if dmg <= 0.0:
		return
	(dm["hits"] as Array).append([now, dmg])
	var b: Node3D = (dm["node"] as Node3D).get_node("Body")
	b.rotation.z = 0.3 * (1.0 if randf() < 0.5 else -1.0)
	_float_text(dm["pos"] + Vector3(randf_range(-0.3, 0.3), 2.0, 0), str(int(round(dmg))), col.lightened(0.3))
	Sfx.play("hit", dm["pos"], -10.0, 0.1)

func _float_text(at: Vector3, t: String, col: Color) -> void:
	var l := Label3D.new(); l.text = t; l.font = UI.big; l.font_size = 52; l.pixel_size = 0.01; l.outline_size = 12
	l.modulate = col; l.billboard = BaseMaterial3D.BILLBOARD_ENABLED; l.no_depth_test = true; l.position = at
	h.add_child(l)
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", at.y + 0.9, 0.7)
	tw.tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.25)
	tw.chain().tween_callback(l.queue_free)

# ------------------------------------------------------------------ casting
func _aim() -> Vector3:
	var a: Vector3 = h.cam.mouse_on_plane(0.9)
	return Vector3(a.x, 0, a.z)

## Uses one slot of your kit (fire, secondary, gear1, signature, ultimate). False if it's off here,
## missing or cooling down.
func cast(slot: String) -> bool:
	if not in_zone or not kit.has(slot) or float(cds.get(slot, 0.0)) > 0.0:
		return false
	var k: Dictionary = kit[slot]
	cds[slot] = float(k["cd"])
	var aim := _aim()
	var me: Vector3 = h.ppos
	var dir := Vector3(aim.x - me.x, 0, aim.z - me.z)
	dir = dir.normalized() if dir.length() > 0.1 else Vector3(-sin(h.pface), 0, -cos(h.pface))
	if slot == "fire":
		if k["melee"]:
			for dm in dummies:
				var to := Vector3(dm["pos"].x - me.x, 0, dm["pos"].z - me.z)
				if to.length() < float(k["range"]) + 0.6 and to.normalized().dot(dir) > 0.3: hit(dm, float(k["dmg"]), k["color"])
			h.fx.burst(me + dir * 1.2 + Vector3(0, 1.0, 0), k["color"], 6, 2.0, 0.2)
		else:
			_shot(me + Vector3(0, 1.0, 0) + dir * 0.5, dir * minf(float(k["speed"]), 40.0), float(k["dmg"]), float(k["range"]) / minf(float(k["speed"]), 40.0) + 0.05, k["color"], 0.1, "you")
		Sfx.play("rifle" if not k["melee"] else "whoosh", null, -14.0, 0.1)
		return true
	var at := aim
	var src := me
	if k.get("kin", false):
		# your kin does it: it bounds over to the spot first
		var ke: Dictionary = h._kin_entry(Save.active_kin())
		if is_instance_valid(loaner):
			src = loaner.position
			var tw := loaner.create_tween()
			tw.tween_property(loaner, "position", aim, 0.35).set_trans(Tween.TRANS_SINE)
		elif not ke.is_empty():
			src = ke["pos"]
			h._start_leap(ke, aim)
	var hitany := false
	for e in k.get("effects", []):
		if typeof(e) != TYPE_DICTIONARY: continue
		var dmg := float(e.get("dmg", e.get("damage", e.get("amount", 0.0))))
		var typ := String(e.get("type", ""))
		if typ == "dash":
			h.start_dash(Vector2(dir.x, dir.z), float(e.get("speed", 18.0)), float(e.get("time", 0.18)))
			hitany = true
		elif typ in ["projectile", "shot", "bolt"] and dmg > 0.0:
			_shot(src + Vector3(0, 1.0, 0), dir * float(e.get("speed", 26.0)), dmg, float(e.get("range", 12.0)) / float(e.get("speed", 26.0)), k["color"], 0.18, "you")
			hitany = true
		elif dmg > 0.0:
			_area(at, float(e.get("r", e.get("radius", 2.5))), dmg, k["color"])
			hitany = true
	if not hitany:
		_area(at, 2.5, 10.0, k["color"])
	_float_text(src + Vector3(0, 2.4, 0), String(k["name"]), Color(k["color"]).lightened(0.4))
	Sfx.play("whoosh", null, -8.0, 0.1)
	return true

func _area(at: Vector3, r: float, dmg: float, col: Color) -> void:
	h.fx.ring(at, r, Color(col, 0.9), 0.35)
	h.fx.burst(at + Vector3(0, 0.5, 0), col, 12, 3.0, 0.4)
	for dm in dummies:
		if Vector2(dm["pos"].x - at.x, dm["pos"].z - at.z).length() < r + 0.4: hit(dm, dmg, col)

## Q / E / R / RMB inside the zone. True if used.
func input(event: InputEvent) -> bool:
	if not in_zone:
		return false
	for slot in ["secondary", "gear1", "signature", "ultimate"]:
		if event.is_action_pressed(slot):
			if not cast(slot) and kit.has(slot):
				Sfx.play("click", null, -10.0, 0.0, 0.6)
			return true
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and event.pressed:
		cast("fire")
		return true
	return false

# ------------------------------------------------------------------ the kit bar
func _build_hud() -> void:
	if is_instance_valid(hud): hud.free()
	slot_lbls.clear()
	var card := UI.card(Color(0.06, 0.07, 0.11, 0.86), 8, 12)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := UI.hbox(14); card.add_child(row)
	row.add_child(UI.label("Training", 15, Color("9ff0e0"), UI.big))
	for pr in [["fire", "LMB"], ["secondary", "RMB"], ["gear1", Settings.key_cap("gear1")], ["signature", Settings.key_cap("signature")], ["ultimate", Settings.key_cap("ultimate")]]:
		if not kit.has(pr[0]): continue
		var one := UI.hbox(5)
		one.add_child(UI.keycap(String(pr[1]), 12))
		var l := UI.label(String(kit[pr[0]]["name"]), 13, UI.INK)
		one.add_child(l)
		slot_lbls[pr[0]] = [l, String(kit[pr[0]]["name"])]
		row.add_child(one)
	h.root_ui.add_child(card)
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 62)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hud = card

func _update_hud() -> void:
	for s in slot_lbls:
		var l: Label = slot_lbls[s][0]
		var cd := float(cds.get(s, 0.0))
		var t := String(slot_lbls[s][1]) if cd <= 0.05 or s == "fire" else "%s %.0fs" % [slot_lbls[s][1], ceil(cd)]
		if l.text != t:
			l.text = t
			l.add_theme_color_override("font_color", UI.INK if cd <= 0.05 or s == "fire" else UI.MUTED)

# ------------------------------------------------------------------ the Try-on rack
func near_rack(p: Vector3) -> bool:
	return Vector2(p.x - RACK.x, p.z - (RACK.z + 1.0)).length() < 1.8

func _cls() -> String:
	return String(try.get("cls", Data.class_of_save()))

## Puts on what's picked: your hunter's build and weapon change on the spot, and the kit with them.
func apply_try() -> void:
	var cls := _cls()
	var w := String(try.get("weapon", ""))
	if w == "" or not (Data.CLASSES[cls]["weapons"] as Array).has(w):
		w = String(Data.CLASSES[cls]["weapon"]); try["weapon"] = w
	var at: Vector3 = h.player.position; var rot: Vector3 = h.player.rotation
	h.player.queue_free()
	h.player = Models.hunter(cls, Data.TEAM_COLORS[0], w, "", Save.d.get("look", {}))
	h.player.position = at; h.player.rotation = rot
	h.add_child(h.player)
	h.glider_node = null
	var sp := String(try.get("kin", ""))
	var mine: bool = Save.d["roster"].any(func(r): return String(r["species"]) == sp)
	if is_instance_valid(loaner): loaner.queue_free()
	loaner = null
	if sp != "" and not mine and Data.KIN.has(sp):
		loaner = Models.kin(sp, {})
		loaner.position = h.ppos + Vector3(1.1, 0, 0.6)
		h.add_child(loaner)
	load_kit()
	_build_hud()

func _line(v: VBoxContainer, key: String, nm: String, desc: String) -> void:
	var r := UI.hbox(8)
	r.add_child(UI.keycap(key, 12))
	var l := UI.label("%s: %s" % [nm, desc] if desc != "" else nm, 13, UI.INK)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(l)
	v.add_child(r)

func open_tryon() -> void:
	var cls := _cls()
	var v: VBoxContainer = h._new_panel("Try-on rack", 680, true)
	v.add_child(UI.label("Feel out any build here. It only applies on the Training Grounds.", 14, UI.MUTED))
	var cr := UI.hbox(8)
	for c in ["light", "medium", "heavy"]:
		var cc: String = c
		cr.add_child(UI.choice(String(Data.CLASSES[c]["name"]), c == cls, func(): try["cls"] = cc; try.erase("weapon"); apply_try(); open_tryon(), 120))
	v.add_child(cr)
	var cd: Dictionary = Data.CLASSES[cls]
	var card := UI.card(UI.CARD, 10, 10); var cv := UI.vbox(4); card.add_child(cv)
	cv.add_child(UI.label("%s  ·  %s" % [cd["name"], TAGS.get(cls, "")], 17, cd["color"], UI.big))
	cv.add_child(UI.label("%s  %d health, %d dash%s." % [cd["desc"], int(cd["hp"]), int(cd["dashes"]), "es" if int(cd["dashes"]) > 1 else ""], 13, UI.MUTED))
	load_kit()
	var wd: WeaponDef = Content.weapon(String(try.get("weapon", h._weapon())))
	if wd: _line(cv, "LMB", wd.display_name, String(wd.primary.get("desc", "")))
	if wd and wd.utility != "":
		var ud := Content.ability(wd.utility)
		if ud: _line(cv, "RMB", ud.display_name, ud.desc)
	var dd := Content.class_dodge(cls)
	if dd: _line(cv, "Shift", dd.display_name, dd.desc)
	var gl := String(try.get("glove", _glove()))
	if gl != "": _line(cv, Settings.key_cap("gear1"), String(Gear.ALL.get(gl, {}).get("name", gl)), Gear.desc_of(gl, 1))
	if kit.has("signature"):
		var ksp := String(try.get("kin", Save.active_kin().get("species", "")))
		var kd := Content.kin(ksp)
		if kd and not kd.abilities.is_empty():
			var sd := Content.ability(String(kd.abilities[0]))
			if sd: _line(cv, Settings.key_cap("signature"), "%s (%s)" % [sd.display_name, kd.display_name], sd.desc)
	if kit.has("ultimate"): _line(cv, Settings.key_cap("ultimate"), String(kit["ultimate"]["name"]), "the bond ultimate (on a 20s timer here)")
	v.add_child(card)
	v.add_child(UI.section("Weapon"))
	var wr := UI.hbox(8)
	for w in cd["weapons"]:
		var ww: String = w
		var wdd: WeaponDef = Content.weapon(w)
		var b := UI.choice(wdd.display_name if wdd else String(w).capitalize(), String(try.get("weapon", h._weapon())) == w, func(): try["cls"] = cls; try["weapon"] = ww; apply_try(); open_tryon(), 150)
		if wdd: b.tooltip_text = String(wdd.primary.get("desc", ""))
		wr.add_child(b)
	v.add_child(wr)
	v.add_child(UI.section("Glove"))
	var gf := HFlowContainer.new(); gf.add_theme_constant_override("h_separation", 6); gf.add_theme_constant_override("v_separation", 6)
	for g in Gear.ALL:
		if not Gear.active(g): continue
		var gg: String = g
		var b := UI.choice(String(Gear.ALL[g].get("name", g)), gl == g, func(): try["cls"] = cls; try["glove"] = gg; apply_try(); open_tryon(), 130)
		b.tooltip_text = Gear.desc_of(g, 1)
		gf.add_child(b)
	v.add_child(gf)
	v.add_child(UI.section("Kin (yours, or a loaner of any kind you've met)"))
	var kf := HFlowContainer.new(); kf.add_theme_constant_override("h_separation", 6); kf.add_theme_constant_override("v_separation", 6)
	var sps: Array = []
	for r in Save.d["roster"]:
		if not sps.has(String(r["species"])): sps.append(String(r["species"]))
	for sp in Save.d.get("dex", {}):
		if Data.KIN.has(sp) and not sps.has(String(sp)): sps.append(String(sp))
	var cur := String(try.get("kin", Save.active_kin().get("species", "")))
	for sp in sps:
		var ss: String = sp
		var kd := Content.kin(sp)
		var tag := String(kd.type).capitalize() if kd else ""
		var b := UI.choice("%s  ·  %s" % [Data.KIN[sp]["name"], tag], cur == sp, func(): try["cls"] = cls; try["kin"] = ss; apply_try(); open_tryon(), 170)
		if kd: b.tooltip_text = kd.desc
		kf.add_child(b)
	v.add_child(kf)
	var bot := UI.hbox(10)
	bot.add_child(UI.primary("Set as my class", func(): set_my_class(), 200))
	bot.add_child(UI.button("Take it all off", func(): try = {}; h._refresh_player_model(); load_kit(); _build_hud(); open_tryon(), 170))
	v.add_child(bot)

## The class (and weapon) you're trying becomes the one you take on expeditions.
func set_my_class() -> void:
	var cls := _cls()
	Save.d["cls"] = cls
	if try.has("weapon"): Save.d["weapon"] = String(try["weapon"])
	Save.save_game()
	h._toast("You're a %s now, with the %s" % [Data.CLASSES[cls]["name"], Content.weapon(String(Save.d.get("weapon", ""))).display_name if Content.weapon(String(Save.d.get("weapon", ""))) else "class weapon"])
	h._refresh_top()
