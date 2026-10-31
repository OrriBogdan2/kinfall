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
	_dummy(STILL, "still")
	_dummy(MOVER, "move")
	_dummy(SHOOTER, "shoot")
	for tp in TARGETS: _dummy(tp, "target")
	var pad := Node3D.new(); pad.position = PAD; h.add_child(pad)
	Models.part(pad, Models.cyl(0.75, 0.8, 0.12, 20), Models.toon(Color("4a5368")), Vector3(0, 0.06, 0))
	Models.part(pad, Models.cyl(0.55, 0.55, 0.03, 20), Models.glow_mat(Color(0.55, 1.0, 0.85, 0.7)), Vector3(0, 0.13, 0))
	_label(pad, "Reset cooldowns", Vector3(0, 1.0, 0), Color("9ff0e0"), 34)
	var wl := Node3D.new(); wl.position = Vector3(34.5, 0, 58.6); h.add_child(wl)
	_label(wl, "Climb: jump at the wall", Vector3(0, 2.4, 0), UI.INK, 30)
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
	var wid: String = h._weapon()
	var wd: WeaponDef = Content.weapon(wid) if wid != "" else null
	var pr: Dictionary = wd.primary if wd else Data.WEAPONS.get("rifle", {})
	kit["fire"] = {"name": String(pr.get("name", "Weapon")), "cd": float(pr.get("rate", 0.2)) * float(pr.get("burst", 1)), "color": pr.get("color", Color("d9ff66")),
		"dmg": float(pr.get("dmg", 4.0)) * float(pr.get("burst", 1)) * float(pr.get("pellets", 1)), "range": float(pr.get("range", 9.0)), "speed": float(pr.get("speed", 60.0)),
		"melee": float(pr.get("range", 9.0)) < 3.6 or pr.has("arc") or pr.has("swing")}
	if wd and wd.utility != "":
		var ad := Content.ability(wd.utility)
		if ad: kit["secondary"] = _from_ability(ad)
	var glove := _glove()
	if glove != "":
		kit["gear1"] = {"name": String(Gear.ALL.get(glove, {}).get("name", glove.capitalize())), "cd": Gear.cd_of(glove, 1), "color": Color("ffd36a"), "effects": Gear.effects_of(glove, 1)}
	var ak: Dictionary = Save.active_kin()
	var kd: KinDef = Content.kin(String(ak.get("species", ""))) if not ak.is_empty() else null
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
		if not ke.is_empty():
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
	if is_instance_valid(hud): hud.queue_free()
	slot_lbls.clear()
	var card := UI.card(Color(0.06, 0.07, 0.11, 0.86), 8, 12)
	card.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
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
	card.reset_size()
	card.offset_left = -card.size.x * 0.5; card.offset_right = card.size.x * 0.5
	card.offset_top = -112; card.offset_bottom = -112 + card.size.y
	hud = card

func _update_hud() -> void:
	for s in slot_lbls:
		var l: Label = slot_lbls[s][0]
		var cd := float(cds.get(s, 0.0))
		var t := String(slot_lbls[s][1]) if cd <= 0.05 or s == "fire" else "%s %.0fs" % [slot_lbls[s][1], ceil(cd)]
		if l.text != t:
			l.text = t
			l.add_theme_color_override("font_color", UI.INK if cd <= 0.05 or s == "fire" else UI.MUTED)
