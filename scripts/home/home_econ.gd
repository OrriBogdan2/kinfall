class_name HomeEcon
extends RefCounted
## The home island's share of loot and kin keeping (the data lives in Econ, on the save):
##   the Armory panel     what you brought home: inspect, pick your loadout, sell, salvage, upgrade
##   feeders              set them down where you like, fill them; hungry kin queue round and eat
##   starving             warnings while it builds up, and a death when it goes too far
##   the graveyard        a grave for every kin that died, with what it remembered
##   the Soul Shrine      keeps their souls and brings one back, a little different
## Home calls in at a few points (build, tick, interact, care goals, panels); everything else is here.

var h                               # the Home screen
var fnodes := {}                    # feeder id -> its node
var gnodes: Array = []              # grave nodes (with the tile each one blocks)
var gate: Node3D
var carry := {}                     # carrying a feeder to set down: {kind, node, from}
var acc := 0.0
var away: Array = []                # what happened while you were away (Econ.catch_up_all)
var told := {}                      # uid -> the starve stage we last warned about
var arm_pick := ""
var arm_tab := "Weapons"

const SEAT_R := 1.05
const QUEUE_R := 2.2
const GATE_AT := Vector3(49.6, 0, 29.6)
const GRAVE_SPOTS := [Vector3(48.9, 0, 31.3), Vector3(50.4, 0, 31.3), Vector3(48.9, 0, 32.7), Vector3(50.4, 0, 32.7), Vector3(48.9, 0, 34.1), Vector3(50.4, 0, 34.1)]

func _init(home) -> void:
	h = home

# ------------------------------------------------------------------ building it
func build() -> void:
	for f in Econ.feeders():
		_spawn_feeder(f)
	gate = EconModels.gate()
	gate.position = GATE_AT
	h.add_child(gate)
	build_graves()

func _spawn_feeder(f: Dictionary) -> void:
	var n := EconModels.feeder(String(f.get("kind", "trough")))
	n.position = _fpos(f)
	n.rotation.y = float(f.get("rot", 0.0))
	h.add_child(n)
	EconModels.set_fill(n, f)
	fnodes[String(f["id"])] = n
	_block(_fpos(f), true)

func _fpos(f: Dictionary) -> Vector3:
	return Vector3(float(f.get("x", 40.0)), 0, float(f.get("z", 29.0)))

func _block(p: Vector3, on: bool) -> void:
	var i: int = h.world.idx(int(floor(p.x)), int(floor(p.z)))
	if on:
		if h.world.kind[i] == World.T_GROUND: h.world.kind[i] = World.T_BLOCK
	elif h.world.kind[i] == World.T_BLOCK:
		h.world.kind[i] = World.T_GROUND

func build_graves() -> void:
	for g in gnodes:
		_block((g as Node3D).position, false)
		(g as Node3D).queue_free()
	gnodes.clear()
	var gs: Array = Econ.graves()
	var shown: Array = gs.slice(maxi(0, gs.size() - GRAVE_SPOTS.size()))
	for i in shown.size():
		var n := EconModels.grave(shown[i], i)
		n.position = GRAVE_SPOTS[i]
		n.set_meta("grave", shown[i])
		h.add_child(n)
		gnodes.append(n)
		_block(n.position, true)

func refresh_feeder(f: Dictionary) -> void:
	var n: Node3D = fnodes.get(String(f["id"]))
	if is_instance_valid(n):
		EconModels.set_fill(n, f)

func _feeder(fid: String) -> Dictionary:
	for f in Econ.feeders():
		if String(f["id"]) == fid: return f
	return {}

# ------------------------------------------------------------------ every frame
func tick(d: float) -> void:
	if not h.visit.is_empty():
		return
	if not carry.is_empty():
		_carry_tick()
	for g in gnodes:
		var w: Node3D = (g as Node3D).get_node_or_null("Wisp")
		if w: w.position.y = 1.45 + sin(Time.get_ticks_msec() / 600.0 + g.position.x) * 0.08
	acc += d
	if acc < 2.0:
		return
	acc = 0.0
	# hoppers top themselves up; starving kin get noticed, and one that's gone too far dies
	for f in Econ.feeders():
		if Econ.auto_refill(f) > 0:
			refresh_feeder(f)
	for rec in KinBox.farm():
		var st := Care.starve_stage(rec)
		if st == "dead":
			_kin_died(rec, Econ.kin_dies(rec, "starved"))
			continue
		var was := String(told.get(rec["uid"], ""))
		if st != was:
			told[rec["uid"]] = st
			if st != "":
				var k: Dictionary = h._kin_entry(rec)
				if not k.is_empty():
					h._emote(k, "!", true)
					h._say(k, KinSpeak.say(rec, "sad", "food") if Care.speech(rec) < 3 else "I'm so hungry...", 3.0, false)
				h._toast("%s: %s" % [rec["name"], String(Care.STARVE_INFO[st][0]).to_lower()])

func _kin_died(rec: Dictionary, g: Dictionary) -> void:
	var k: Dictionary = h._kin_entry(rec)
	if not k.is_empty():
		var n: Node3D = k["node"]
		h.fx.burst(n.position + Vector3(0, 0.6, 0), Color("bff8ec"), 22, 2.5, 0.9, -1.0)
		n.queue_free()
		h.kins.erase(k)
	build_graves()
	Save.save_game()
	_notice("%s has died" % g["name"], ["%s starved. It had nothing to eat for days." % g["name"],
		"Its grave is in the graveyard, east of the farm.", "Keep a feeder filled so it never happens again." + (" A Soul Shrine can bring a kin back." if not Save.has_building("shrine") else "")])

# ------------------------------------------------------------------ what you can walk up to
## The nearest feeder, grave or the graveyard gate if it's closer than bd, as an interact entry.
func find(p2: Vector2, bd: float) -> Dictionary:
	if not h.visit.is_empty():
		return {}
	if not carry.is_empty():
		return {"kind": "place"}
	var best := {}
	for f in Econ.feeders():
		var fp := _fpos(f)
		var dd := p2.distance_to(Vector2(fp.x, fp.z))
		if dd < 1.7 and dd < bd: bd = dd; best = {"kind": "feeder", "f": f}
	for g in gnodes:
		var gp: Vector3 = (g as Node3D).position
		var dd := p2.distance_to(Vector2(gp.x, gp.z + 0.6))
		if dd < 1.1 and dd < bd: bd = dd; best = {"kind": "grave", "g": g.get_meta("grave")}
	var gd := p2.distance_to(Vector2(GATE_AT.x, GATE_AT.z))
	if gd < 1.3 and gd < bd: best = {"kind": "graveyard"}
	return best

func label(it: Dictionary) -> String:
	match String(it["kind"]):
		"place":
			var ok := _place_ok(_carry_spot())
			return ("Set the %s down here" % Econ.FEEDERS[carry["kind"]]["name"]) if ok else "Can't set it down here (open ground, away from other feeders)"
		"feeder":
			var f: Dictionary = it["f"]
			return "%s  ·  %d/%d meals" % [Econ.fdef(f)["name"], Econ.fill(f), int(Econ.fdef(f)["cap"])]
		"grave": return "Visit %s's grave" % it["g"]["name"]
		"graveyard": return "The graveyard  ·  %d resting" % Econ.graves().size()
	return ""

func use(it: Dictionary) -> void:
	match String(it["kind"]):
		"place": place()
		"feeder": open_feeder(it["f"])
		"grave": open_grave(it["g"])
		"graveyard": open_graveyard()

# ------------------------------------------------------------------ feeders: kin eat on their own
## A hungry kin picks a feeder on its island with something it'll eat. True if it's off to eat.
func feed_goal(k: Dictionary) -> bool:
	var rec: Dictionary = k["rec"]
	if Care.need(rec, "food") >= Econ.HUNGRY_AT or k.has("eat"):
		return k.has("eat")
	var here: int = h.world.island_of(k["pos"].x, k["pos"].z)
	var best := {}; var bd := 1e9
	var hate := String(rec.get("likes", {}).get("hates", ""))
	for f in Econ.feeders():
		var fp := _fpos(f)
		if h.world.island_of(fp.x, fp.z) != here: continue
		if not (f["food"] as Array).any(func(x): return String(x) != hate): continue
		var dd := Vector2(fp.x - k["pos"].x, fp.z - k["pos"].z).length()
		if dd < bd: bd = dd; best = f
	if best.is_empty():
		return false
	k["eat"] = {"fid": String(best["id"]), "seat": -1, "phase": "go", "t": 0.0}
	k["t"] = 30.0
	k.erase("stare")
	return true

## The ring of places to eat round a feeder (the ones on open ground).
func seats(f: Dictionary) -> Array:
	var out: Array = []
	var n := int(Econ.fdef(f)["seats"])
	var c := _fpos(f)
	for i in n:
		var a := float(i) * TAU / n + 0.4
		var p := c + Vector3(cos(a) * SEAT_R * (1.15 if absf(cos(a)) > 0.7 else 1.0), 0, sin(a) * SEAT_R)
		if not h.world.is_void(p.x, p.z) and h.world.occupy(p.x, p.z, 0.3, 0.0, true) == 0.0:
			out.append(p)
	return out

func _taken(fid: String, i: int, me: Dictionary) -> bool:
	for o in h.kins:
		if o != me and o.has("eat") and String(o["eat"]["fid"]) == fid and int(o["eat"]["seat"]) == i:
			return true
	return false

## Walking up, waiting a turn in the outer ring, eating. True while it's busy with that.
func feed_step(k: Dictionary, d: float) -> bool:
	if not k.has("eat"):
		return false
	var e: Dictionary = k["eat"]
	var f := _feeder(String(e["fid"]))
	if f.is_empty() or k.has("called_t") or k.get("busy", false) or k.has("fetch") or k.has("bath") or float(k.get("nap_t", 0.0)) > 0.0:
		k.erase("eat")
		return false
	var c := _fpos(f)
	var pos: Vector3 = k["pos"]
	match String(e["phase"]):
		"go":
			e["t"] = float(e["t"]) + d
			if Econ.fill(f) == 0 or float(e["t"]) > 40.0:
				k.erase("eat"); k["t"] = 1.0
				h._emote(k, "?")
				return false
			var ss := seats(f)
			if int(e["seat"]) < 0 or int(e["seat"]) >= ss.size():
				e["seat"] = -1
				for i in ss.size():
					if not _taken(String(e["fid"]), i, k):
						e["seat"] = i; break
			if int(e["seat"]) < 0:
				# all the places are taken: wait in the outer ring, each in its own spot
				k["goal"] = h._seat(k, c, QUEUE_R)
				return true
			var sp: Vector3 = ss[int(e["seat"])]
			k["goal"] = sp
			if Vector2(sp.x - pos.x, sp.z - pos.z).length() < 0.4:
				e["phase"] = "eat"; e["t"] = 2.6
				k["hold_t"] = 0.3
				(k["node"] as Node3D).rotation.y = atan2(-(c.x - pos.x), -(c.z - pos.z))
		"eat":
			k["hold_t"] = 0.3
			k["goal"] = pos
			e["t"] = float(e["t"]) - d
			var body: Node3D = (k["node"] as Node3D).get_node_or_null("Body")
			if body:
				var q := absf(sin(float(e["t"]) * 9.0))
				body.scale = Vector3(1.0 + q * 0.08, 1.0 - q * 0.1, 1.0 + q * 0.08)
			if randf() < d * 3.0 and Econ.fill(f) > 0:
				h.fx.burst(c + Vector3(0, 0.4, 0), Care.food_col(String(f["food"][0])), 3, 1.0, 0.25)
			if float(e["t"]) <= 0.0:
				if body: body.scale = Vector3.ONE
				var rec: Dictionary = k["rec"]
				var res := Econ.serve(f, rec)
				refresh_feeder(f)
				k.erase("eat")
				k["t"] = randf_range(1.0, 2.0)
				if res.is_empty():
					h._emote(k, "?")
				elif res.get("love", false):
					k["joy_t"] = 1.0
					h._emote(k, "♥")
					if res.get("new", false): h._toast("%s loves %s!" % [rec["name"], Care.food_name(String(res["food"]))])
				else:
					h._emote(k, "♪")
				Sfx.play("pickup", c, -16.0, 0.1, 1.4)
				# eats until it's had enough, if there's still food
				if Care.need(rec, "food") < Econ.HUNGRY_AT and Econ.fill(f) > 0:
					k["eat"] = {"fid": String(f["id"]), "seat": int(e["seat"]), "phase": "go", "t": 0.0}
	return true

# ------------------------------------------------------------------ feeders: setting them down
func feeders_owned() -> int:
	var n := Econ.feeders().size()
	for k in Save.d.get("feeder_inv", {}): n += int(Save.d["feeder_inv"][k])
	return n + (1 if not carry.is_empty() and String(carry.get("from", "")) == "" else 0)

## Pick up a feeder (a new one from storage, or one that's out: from = its id) to put it somewhere.
func start_carry(kind: String, from := "") -> void:
	if not carry.is_empty():
		return
	if from == "":
		var inv: Dictionary = Save.d["feeder_inv"]
		if int(inv.get(kind, 0)) <= 0: return
		inv[kind] = int(inv[kind]) - 1
		if int(inv[kind]) <= 0: inv.erase(kind)
	else:
		var f := _feeder(from)
		var n: Node3D = fnodes.get(from)
		if is_instance_valid(n): n.visible = false
		_block(_fpos(f), false)
		for o in h.kins:
			if o.has("eat") and String(o["eat"]["fid"]) == from: o.erase("eat")
	var node := EconModels.feeder(kind)
	h.add_child(node)
	carry = {"kind": kind, "node": node, "from": from}
	h._close_panel()
	h._toast("Carrying the %s  ·  %s to set it down  ·  Esc to %s" % [Econ.FEEDERS[kind]["name"], Settings.key_cap("interact"), "put it back" if from != "" else "store it"])

func _carry_spot() -> Vector3:
	var f: float = h.pface
	return Vector3(h.ppos.x - sin(f) * 1.5, 0, h.ppos.z - cos(f) * 1.5)

func _carry_tick() -> void:
	var n: Node3D = carry["node"]
	var p := _carry_spot()
	n.position = n.position.lerp(p, 0.3)
	var ok := _place_ok(p)
	n.scale = Vector3.ONE * (1.0 + sin(Time.get_ticks_msec() / 160.0) * 0.03)
	var fl: Label3D = n.get_node_or_null("Fill")
	if fl:
		fl.text = "set it down" if ok else "not here"
		fl.modulate = UI.GOOD if ok else UI.BAD

func _place_ok(p: Vector3) -> bool:
	var w = h.world
	if w.is_void(p.x, p.z) or w.kind[w.idx(int(floor(p.x)), int(floor(p.z)))] != World.T_GROUND:
		return false
	var isl: int = w.island_of(p.x, p.z)
	if isl < 0 or (isl > 0 and not h._isle_open(String(w.islands[isl]["id"]))):
		return false
	for f in Econ.feeders():
		if String(f["id"]) == String(carry.get("from", "")): continue
		if Vector2(p.x - float(f["x"]), p.z - float(f["z"])).length() < 2.8: return false
	for g in gnodes:
		if Vector2(p.x - g.position.x, p.z - g.position.z).length() < 1.8: return false
	for sp in [h.spots.get("house"), h.spots.get("portal"), h.spots.get("stall")]:
		if sp != null and Vector2(p.x - sp.x, p.z - sp.z).length() < 2.6: return false
	# room round it for at least two kin to eat
	var free := 0
	for i in 6:
		var a := float(i) * TAU / 6.0
		var q := p + Vector3(cos(a) * SEAT_R, 0, sin(a) * SEAT_R)
		if not w.is_void(q.x, q.z) and w.occupy(q.x, q.z, 0.3, 0.0, true) == 0.0: free += 1
	return free >= 3

func place() -> void:
	if carry.is_empty():
		return
	var p := _carry_spot()
	if not _place_ok(p):
		Sfx.play("click", null, -6.0, 0.0, 0.6)
		return
	var kind := String(carry["kind"])
	var f: Dictionary
	if String(carry["from"]) != "":
		f = _feeder(String(carry["from"]))
		var old: Node3D = fnodes.get(String(f["id"]))
		if is_instance_valid(old): old.queue_free()
		f["x"] = snappedf(p.x, 0.1); f["z"] = snappedf(p.z, 0.1)
	else:
		var n := 1
		while not _feeder("f%d" % n).is_empty(): n += 1
		f = {"id": "f%d" % n, "kind": kind, "x": snappedf(p.x, 0.1), "z": snappedf(p.z, 0.1), "food": [], "auto": true}
		Save.d["feeders"].append(f)
	(carry["node"] as Node3D).queue_free()
	carry = {}
	_spawn_feeder(f)
	Econ.auto_refill(f)
	refresh_feeder(f)
	h.unstick()
	Sfx.play("build", null, -4.0, 0.1)
	h.fx.dust(p, 10)
	Save.save_game()
	h._toast("%s set down" % Econ.fdef(f)["name"])

func cancel_carry() -> void:
	if carry.is_empty():
		return
	var from := String(carry["from"])
	if from != "":
		var f := _feeder(from)
		var n: Node3D = fnodes.get(from)
		if is_instance_valid(n): n.visible = true
		_block(_fpos(f), true)
	else:
		var inv: Dictionary = Save.d["feeder_inv"]
		inv[carry["kind"]] = int(inv.get(carry["kind"], 0)) + 1
	(carry["node"] as Node3D).queue_free()
	carry = {}
	Save.save_game()

## Back into storage (to set it down somewhere else later). Its food goes back in the pantry.
func store_feeder(f: Dictionary) -> void:
	for key in f.get("food", []):
		if Data.CROPS.has(key): Save.d["crops"][key] = int(Save.d["crops"].get(key, 0)) + 1
		else: Save.d["items"][key] = int(Save.d["items"].get(key, 0)) + 1
	var n: Node3D = fnodes.get(String(f["id"]))
	if is_instance_valid(n): n.queue_free()
	fnodes.erase(String(f["id"]))
	_block(_fpos(f), false)
	Save.d["feeders"].erase(f)
	var inv: Dictionary = Save.d["feeder_inv"]
	inv[f["kind"]] = int(inv.get(f["kind"], 0)) + 1
	for o in h.kins:
		if o.has("eat") and String(o["eat"]["fid"]) == String(f["id"]): o.erase("eat")
	Save.save_game()

# ------------------------------------------------------------------ feeders: the panel
func open_feeder(f: Dictionary) -> void:
	var fd := Econ.fdef(f)
	var v: VBoxContainer = h._new_panel(String(fd["name"]), 620, true)
	var cap := int(fd["cap"])
	var top := UI.hbox(10)
	top.add_child(UI.bar(float(Econ.fill(f)) / cap, Color("ffb36a"), 300, 12))
	top.add_child(UI.label("%d of %d meals" % [Econ.fill(f), cap], 16, UI.INK, UI.semi))
	v.add_child(top)
	var bits: Array = ["Seats %d" % int(fd["seats"])]
	if float(fd["mult"]) > 1.0: bits.append("meals fill %d%% more" % int(round((float(fd["mult"]) - 1.0) * 100.0)))
	if float(fd["joy"]) > 0.0: bits.append("cheers them up")
	var dl := UI.label("%s  ·  %s" % [fd["desc"], "  ·  ".join(bits)], 13, UI.MUTED)
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(dl)
	# what's in it
	if Econ.fill(f) > 0:
		var counts := {}
		for key in f["food"]: counts[key] = int(counts.get(key, 0)) + 1
		var parts: Array = []
		for key in counts: parts.append("%s ×%d" % [Care.food_name(key), counts[key]])
		var il := UI.label("In it: " + ", ".join(parts), 14, UI.INK)
		il.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(il)
	var hungry: Array = KinBox.farm().filter(func(r): return Care.need(r, "food") < Econ.HUNGRY_AT).map(func(r): return String(r["name"]))
	v.add_child(UI.label(("Hungry now: " + ", ".join(hungry)) if not hungry.is_empty() else "Nobody's hungry right now.", 13, Color("ffb070") if not hungry.is_empty() else UI.GOOD))
	# filling it
	var row0 := UI.hbox(8)
	var fill_b := UI.primary("Fill it up", func():
		var got := 0
		while Econ.room_in(f) > 0:
			var key := Econ._auto_food()
			if key == "" or Econ.put_in(f, key, 1) == 0: break
			got += 1
		refresh_feeder(f)
		Sfx.play("pickup", null, -6.0)
		Save.save_game()
		if got == 0: h._toast("Nothing in your pantry to put in (buy kibble, or harvest)")
		open_feeder(f), 160)
	fill_b.disabled = Econ.room_in(f) <= 0
	fill_b.tooltip_text = "Fills it with kibble and everyday crops from your pantry (never treats or rare crops)"
	row0.add_child(fill_b)
	if fd["auto"]:
		var on: bool = f.get("auto", true)
		var ab := UI.choice("Refills itself: %s" % ("on" if on else "off"), on, func():
			f["auto"] = not bool(f.get("auto", true))
			if f["auto"]: Econ.auto_refill(f); refresh_feeder(f)
			Save.save_game()
			open_feeder(f), 200)
		ab.tooltip_text = "Below half full, it tops itself up from your pantry"
		row0.add_child(ab)
	v.add_child(row0)
	v.add_child(UI.section("Put in by hand"))
	var any := false
	for key in Care.FOODS.keys() + Data.CROPS.keys():
		var have := Econ.pantry(key)
		if have <= 0: continue
		any = true
		var r := UI.hbox(8)
		var l := UI.label("%s  ×%d" % [Care.food_name(key), have], 15, Care.food_col(key))
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(l)
		var kk: String = key
		for n in [1, 5]:
			var nn: int = n
			var b := UI.button("+%d" % n, func():
				Econ.put_in(f, kk, nn)
				refresh_feeder(f)
				Sfx.play("pickup", null, -8.0)
				Save.save_game()
				open_feeder(f), 56)
			b.disabled = Econ.room_in(f) <= 0
			r.add_child(b)
		v.add_child(r)
	if not any:
		v.add_child(UI.label("Your pantry's empty. Buy kin kibble at the market stall, or harvest crops.", 14, UI.MUTED))
	# moving it, and the ones in storage
	v.add_child(UI.section("Feeders"))
	var mv := UI.hbox(8)
	mv.add_child(UI.button("Move it", func(): start_carry(String(f["kind"]), String(f["id"])), 120))
	var stb := UI.button("Put it in storage", func(): store_feeder(f); h._close_panel(), 170)
	stb.disabled = Econ.feeders().size() <= 1
	stb.tooltip_text = "Keep at least one out" if Econ.feeders().size() <= 1 else "Its food goes back in your pantry"
	mv.add_child(stb)
	v.add_child(mv)
	var inv: Dictionary = Save.d.get("feeder_inv", {})
	for kind in inv:
		var r2 := UI.hbox(8)
		var l2 := UI.label("In storage: %s ×%d" % [Econ.FEEDERS[kind]["name"], int(inv[kind])], 14, UI.INK)
		l2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r2.add_child(l2)
		var kd: String = kind
		r2.add_child(UI.primary("Set one down", func(): start_carry(kd), 150))
		v.add_child(r2)
	var more := UI.label("Bigger and better feeders at the market stall (Farm). Up to %d on the farm." % Econ.MAX_FEEDERS, 12, UI.MUTED)
	v.add_child(more)

## Shop goods for the market's Farm tab: [key, name, desc, price, colour, on_buy, owned_text].
func shop_goods() -> Array:
	var out: Array = []
	var owned := feeders_owned()
	for kind in Econ.FEEDER_ORDER:
		var fd: Dictionary = Econ.FEEDERS[kind]
		var kk: String = kind
		out.append(["feeder:" + kind, String(fd["name"]), "%s  Holds %d, %d seats." % [fd["desc"], int(fd["cap"]), int(fd["seats"])],
			int(fd["price"]) if owned < Econ.MAX_FEEDERS else -1, fd["col"], func():
				var inv: Dictionary = Save.d["feeder_inv"]
				inv[kk] = int(inv.get(kk, 0)) + 1
				(func(): h._close_panel(); start_carry(kk)).call_deferred(),
			("%d/%d feeders" % [owned, Econ.MAX_FEEDERS]) if owned < Econ.MAX_FEEDERS else "you have %d (the most)" % owned])
	return out

# ------------------------------------------------------------------ starving: telling you
## Called once the home screen is up: what happened while you were away.
func show_away() -> void:
	var lines: Array = []
	var died: Array = []
	for e in away:
		if e["kind"] == "died":
			died.append(e["grave"])
		elif e["kind"] == "starving":
			var info: Array = Care.STARVE_INFO[String(e["stage"])]
			lines.append("%s: %s. %s" % [e["rec"]["name"], String(info[0]).to_lower(), info[1]])
			told[e["rec"]["uid"]] = String(e["stage"])
	away = []
	for g in died:
		_notice("%s has died" % g["name"], ["%s starved while you were away. It had nothing to eat for days." % g["name"],
			"Its grave is in the graveyard, east of the farm. You can visit it there.",
			"A filled feeder keeps your kin fed while you're gone." + (" A Soul Shrine can bring a kin back, a little changed." if not Save.has_building("shrine") else "")])
	if not lines.is_empty():
		lines.append("Fill a feeder (by the cooking pot), or feed them from their card.")
		_notice("Your kin are starving", lines)

func _notice(title: String, lines: Array) -> void:
	if not h.is_inside_tree():
		return
	if h.panel_open != "" or h.building_now or not Save.d["tutorial"].get("home", false):
		h.get_tree().create_timer(1.0).timeout.connect(_notice.bind(title, lines))
		return
	var v: VBoxContainer = h._new_panel(title, 560)
	for l in lines:
		var lb := UI.label(String(l), 15, UI.INK)
		lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(lb)

## Why your partner can't come out (starving too long), or "".
func refuse_reason() -> String:
	var ak := Save.active_kin()
	if ak.is_empty():
		return ""
	if Care.starve_h(ak) >= Care.STARVE["refuse"]:
		return "%s is too weak from hunger to come. Feed it (or fill a feeder) first, or pick another partner." % ak["name"]
	return ""

# ------------------------------------------------------------------ the graveyard
func open_graveyard() -> void:
	var v: VBoxContainer = h._new_panel("Graveyard", 620, true)
	var gs: Array = Econ.graves()
	if gs.is_empty():
		var l := UI.label("Nobody rests here. Keep your kin fed and it stays that way.", 15, UI.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)
		return
	for i in range(gs.size() - 1, -1, -1):
		var g: Dictionary = gs[i]
		var r := UI.hbox(10)
		var info := UI.vbox(2); info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sp: Dictionary = Data.KIN.get(String(g["species"]), {})
		info.add_child(UI.label(String(g["name"]) + ("  ·  soul kept in the shrine" if g.get("soul", false) else ""), 17, sp.get("color", UI.INK), UI.big))
		info.add_child(UI.label(Econ.epitaph(g), 12, UI.MUTED))
		r.add_child(info)
		var gg := g
		r.add_child(UI.button("Visit", func(): open_grave(gg), 90))
		v.add_child(r)

func open_grave(g: Dictionary) -> void:
	var sp: Dictionary = Data.KIN.get(String(g["species"]), {})
	var v: VBoxContainer = h._new_panel("%s%s" % [g["name"], (", " + String(g["title"])) if String(g.get("title", "")) != "" else ""], 620, true)
	var el := UI.label(Econ.epitaph(g), 15, sp.get("color", UI.INK))
	el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(el)
	var days := int((Time.get_unix_time_from_system() - float(g.get("t", 0.0))) / 86400.0)
	var gm := int(g["rec"].get("matches", 0))
	var when := "today" if days <= 0 else ("%d day%s ago" % [days, "" if days == 1 else "s"])
	v.add_child(UI.label(("Buried %s, after %d expedition%s together." % [when, gm, "" if gm == 1 else "s"]) if gm > 0 else ("Buried %s. It never went on an expedition." % when), 13, UI.MUTED))
	v.add_child(UI.section("What it remembered"))
	var mem: Array = g.get("mem", [])
	if mem.is_empty():
		v.add_child(UI.label("Not much. It hadn't been with you long.", 14, UI.MUTED))
	for i in range(mem.size() - 1, -1, -1):
		var ml := UI.label("·  It %s." % String(mem[i].get("text", "")), 14, UI.INK)
		ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(ml)
	v.add_child(UI.section("Its soul"))
	_soul_row(v, g)

## Keep the soul / bring it back, with what each needs.
func _soul_row(v: VBoxContainer, g: Dictionary) -> void:
	if not Save.has_building("shrine"):
		var l := UI.label("A Soul Shrine could keep its soul, and one day bring it back. Build one beside the graveyard (it needs a Soul Ember from a vault or a Warden).", 13, UI.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)
		return
	var r := UI.hbox(10)
	if not g.get("soul", false):
		var why := Econ.keep_soul(g.duplicate())    # just to ask; the real one is below
		var b := UI.primary("Keep its soul in the shrine", func():
			var w := Econ.keep_soul(g)
			if w != "": h._toast(w); return
			Sfx.play("unlock", null, -4.0)
			build_graves()
			Save.save_game()
			open_grave(g), 260)
		b.disabled = why != ""
		b.tooltip_text = why
		r.add_child(b)
		r.add_child(UI.label("%d of %d souls kept" % [Econ.souls_kept(), Econ.SHRINE_SLOTS], 13, UI.MUTED))
	else:
		var why2 := Econ.revive_why(g)
		var b2 := UI.primary("Bring it back  (1 Soul Ember, %d gems)" % Econ.revive_cost(g), func(): _revive(g), 330)
		b2.disabled = why2 != ""
		b2.tooltip_text = why2
		r.add_child(b2)
		if why2 != "":
			r.add_child(UI.label(why2, 12, Color("ffb0a0")))
	v.add_child(r)
	var note := UI.label("A kin brought back is still itself, but not quite: its personality shifts, it loses a couple of levels and some trust, it keeps only a few memories, its tastes change, and it has a ghostly shimmer and a new title.", 12, UI.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)

func _revive(g: Dictionary) -> void:
	var rec := Econ.revive(g)
	if rec.is_empty():
		return
	Save.save_game()
	h._close_panel()
	build_graves()
	h._spawn_kin()
	h._refresh_top()
	var at: Vector3 = h.lots["shrine"]["at"] if h.lots.has("shrine") else h.ppos
	h.fx.burst(at + Vector3(0, 1.4, 0), Color("bff8ec"), 40, 4.0, 1.2, -1.0)
	h.fx.ring(at, 3.0, Color("9ff0e0"), 0.6)
	Sfx.play("unlock")
	var ke: Dictionary = h._kin_entry(rec)
	if not ke.is_empty():
		ke["pos"] = at + Vector3(0, 0, 2.0); (ke["node"] as Node3D).position = ke["pos"]; ke["hold_t"] = 3.0
		h._emote(ke, "!", true)
	_notice("%s, %s" % [rec["name"], rec["title"]], ["%s is back. It knows you, but it isn't quite the same." % rec["name"],
		"Level %d now, and a %s nature. It'll have new favourite foods to find out." % [int(rec["level"]), Care.nature(rec).to_lower()]])

# ------------------------------------------------------------------ the Soul Shrine
func open_shrine() -> void:
	var v: VBoxContainer = h._new_panel("Soul Shrine", 640, true)
	var l := UI.label("The ember keeps the souls of kin buried here. With a Soul Ember and some gems it can bring one back, changed by where it's been.", 14, UI.MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)
	v.add_child(UI.label("Soul Embers: %d  ·  souls kept: %d of %d  ·  gems: %d" % [Econ.embers(), Econ.souls_kept(), Econ.SHRINE_SLOTS, int(Save.d["gems"])], 15, Color("bff8ec"), UI.semi))
	var gs: Array = Econ.graves()
	if gs.is_empty():
		v.add_child(UI.label("The graveyard is empty.", 14, UI.MUTED))
		return
	for i in range(gs.size() - 1, -1, -1):
		var g: Dictionary = gs[i]
		var card := UI.card(UI.CARD, 10, 10)
		var cv := UI.vbox(4); card.add_child(cv)
		var sp: Dictionary = Data.KIN.get(String(g["species"]), {})
		cv.add_child(UI.label(String(g["name"]), 18, sp.get("color", UI.INK), UI.big))
		cv.add_child(UI.label(Econ.epitaph(g), 12, UI.MUTED))
		var r := UI.hbox(8)
		if not g.get("soul", false):
			var gg := g
			var why := "" if Econ.souls_kept() < Econ.SHRINE_SLOTS else "The shrine is full"
			var b := UI.button("Keep its soul", func():
				if Econ.keep_soul(gg) == "":
					Sfx.play("unlock", null, -4.0); build_graves(); Save.save_game()
				open_shrine(), 150)
			b.disabled = why != ""
			b.tooltip_text = why
			r.add_child(b)
		else:
			var gg2 := g
			var why2 := Econ.revive_why(g)
			var b2 := UI.primary("Bring back  ·  1 ember, %d gems" % Econ.revive_cost(g), func(): _revive(gg2), 280)
			b2.disabled = why2 != ""
			b2.tooltip_text = why2
			r.add_child(b2)
			if why2 != "":
				var wl := UI.label(why2, 12, Color("ffb0a0"))
				wl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				r.add_child(wl)
		cv.add_child(r)
		v.add_child(card)

## The empty lot: what the shrine needs before you can build it.
func open_shrine_lot() -> void:
	var bd: Dictionary = Data.BUILDINGS["shrine"]
	var v: VBoxContainer = h._new_panel("Build the Soul Shrine", 520)
	var dl := UI.label(String(bd["desc"]), 15)
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(dl)
	var ex := int(Save.d.get("extracts", 0))
	v.add_child(UI.label("%s  3 successful expeditions  (%d)" % ["✓" if ex >= 3 else "·", ex], 15, UI.GOOD if ex >= 3 else UI.MUTED))
	v.add_child(UI.label("%s  A Soul Ember to light it  (%d)" % ["✓" if Econ.embers() > 0 else "·", Econ.embers()], 15, UI.GOOD if Econ.embers() > 0 else UI.MUTED))
	v.add_child(UI.label("%s  %d gems  (%d)" % ["✓" if int(Save.d["gems"]) >= int(bd["cost"]) else "·", int(bd["cost"]), int(Save.d["gems"])], 15, UI.GOOD if int(Save.d["gems"]) >= int(bd["cost"]) else UI.MUTED))
	var why := Econ.shrine_why()
	var btn := UI.primary("Build it", func():
		if Econ.shrine_why() != "" or Save.has_building("shrine"): return
		Econ.use_ember()
		Save.d["gems"] = int(Save.d["gems"]) - int(bd["cost"])
		Save.d["buildings"].append("shrine")
		Save.save_game()
		h._close_panel()
		h._construct("shrine"), 200)
	btn.disabled = why != ""
	btn.tooltip_text = why
	v.add_child(btn)
	if why != "":
		v.add_child(UI.label(why, 13, Color("ffb0a0")))

# ------------------------------------------------------------------ the Armory
func open_armory() -> void:
	var v: VBoxContainer = h._new_panel("Armory", 960, true)
	var items: Array = Econ.armory().duplicate()
	items.sort_custom(func(a, b): return Loot.value(a) > Loot.value(b))
	var weapons: Array = items.filter(func(it): return String(it.get("t", "")) == "weapon")
	var gloves: Array = items.filter(func(it): return String(it.get("t", "")) == "glove")
	# the top line: what's stored, scrap and gems, and the two upgrades
	var top := UI.hbox(8)
	top.add_child(_chip("satchel", "Stored %d/%d" % [items.size(), Econ.arm_cap()], UI.INK, "Weapons and gloves you've brought home. Full: new ones are sold as they come in"))
	top.add_child(_chip("gem", str(int(Save.d["gems"])), UI.GOLD, "Gems"))
	top.add_child(_chip("medkit", "%d scrap" % int(Save.d.get("scrap", 0)), Color("c8d0dc"), "Scrap: salvage spare weapons and gloves for it. Upgrades need it"))
	top.add_child(_chip("bond", "%d ember%s" % [Econ.embers(), "" if Econ.embers() == 1 else "s"], Color("9ff0e0"), "Soul Embers, for the Soul Shrine"))
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	top.add_child(_upgrade_btn("arm", "Storage", Econ.arm_cap(), Econ.ARM_CAPS))
	top.add_child(_upgrade_btn("pack", "Backpack", Econ.pack_cap(), Econ.PACK_CAPS))
	v.add_child(top)
	var tabs := UI.hbox(6)
	for t in [["Weapons", weapons.size()], ["Gloves", gloves.size()], ["Treasure", _treasure_n()]]:
		var tn: String = t[0]
		tabs.add_child(UI.choice("%s  %d" % [t[0], t[1]], arm_tab == tn, func(): arm_tab = tn; arm_pick = ""; open_armory(), 140))
	var lo_l := UI.label("Next expedition: %s" % _loadout_line(), 13, UI.GOLD)
	lo_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lo_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lo_l.clip_text = true
	tabs.add_child(lo_l)
	v.add_child(tabs)
	if arm_tab == "Treasure":
		_treasure(v)
		return
	var list: Array = weapons if arm_tab == "Weapons" else gloves
	if list.is_empty():
		var el := UI.label("Nothing here yet. %s you carry out of an expedition (in your hands or your backpack) ends up here." % ("Weapons" if arm_tab == "Weapons" else "Gloves"), 15, UI.MUTED)
		el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(el)
		return
	if Econ.find(arm_pick).is_empty() or not list.has(Econ.find(arm_pick)):
		arm_pick = String(list[0]["uid"])
	var it := Econ.find(arm_pick)
	var cols := UI.hbox(16)
	v.add_child(cols)
	cols.add_child(_detail(it))
	var grid := GridContainer.new(); grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8); grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for x in list:
		grid.add_child(_tile(x))
	cols.add_child(grid)

func _chip(icon: String, txt: String, col: Color, tip: String) -> Control:
	var c := UI.card(Color(col, 0.12), 6, 999)
	c.tooltip_text = tip
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	var hb := UI.hbox(6); c.add_child(hb)
	hb.add_child(Icons.Glyph.new(icon, col, 15.0))
	var l := UI.label(txt, 14, UI.INK, UI.semi)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	hb.add_child(l)
	return c

func _upgrade_btn(which: String, what: String, now: int, caps: Array) -> Control:
	var lvl := int(Save.d.get(which + "_lvl", 0))
	var costs: Array = Econ.ARM_UPGRADE if which == "arm" else Econ.PACK_UPGRADE
	if lvl >= costs.size():
		var l := UI.label("%s %d (max)" % [what, now], 13, UI.MUTED)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return l
	var c: Array = costs[lvl]
	var b := UI.button("%s %d → %d  ·  %dg %ds" % [what, now, int(caps[lvl + 1]), int(c[0]), int(c[1])], func():
		var why := Econ.upgrade(which)
		if why != "": h._toast(why); return
		Sfx.play("unlock")
		Save.save_game()
		h._refresh_top()
		open_armory())
	b.disabled = int(Save.d["gems"]) < int(c[0]) or int(Save.d.get("scrap", 0)) < int(c[1])
	b.tooltip_text = "%s: %d gems and %d scrap" % ["More room in the armory" if which == "arm" else "More backpack slots on expeditions", int(c[0]), int(c[1])]
	return b

func _loadout_line() -> String:
	var w := Econ.loadout("weapon")
	var bits: Array = [Loot.name_of(w) if not w.is_empty() else "your class weapon"]
	for s in ["glove0", "glove1"]:
		var g := Econ.loadout(s)
		if not g.is_empty(): bits.append(Loot.name_of(g))
	return ", ".join(bits)

func _in_loadout(it: Dictionary) -> String:
	for s in ["weapon", "glove0", "glove1"]:
		if String(Save.d["loadout"].get(s, "")) == String(it.get("uid", "")): return s
	return ""

## One stored thing as a square tile: its icon in its element colour, its rarity as the border.
func _tile(it: Dictionary) -> Control:
	var sel := String(it["uid"]) == arm_pick
	var card := UI.card(Color(Loot.col_of(it), 0.16 if sel else 0.07), 8, 10)
	UI.set_card_border(card, Color(Loot.col_of(it), 0.95 if sel else 0.4), 3 if sel else 2)
	card.custom_minimum_size = Vector2(124, 104)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.tooltip_text = "%s\n%s\nWorth %d" % [Loot.name_of(it), Loot.sub_of(it), Loot.value(it)]
	var cv := UI.vbox(2); card.add_child(cv)
	var top := UI.hbox(4)
	top.add_child(Icons.Glyph.new(Loot.icon_of(it), Loot.el_col(it), 34.0))
	var tsp := Control.new(); tsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tsp)
	if _in_loadout(it) != "":
		top.add_child(UI.label("✓", 18, UI.GOOD, UI.big))
	cv.add_child(top)
	var nm := UI.label(Loot.name_of(it), 13, Loot.col_of(it), UI.semi)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.custom_minimum_size.x = 104
	cv.add_child(nm)
	var uid := String(it["uid"])
	card.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			arm_pick = uid
			Sfx.play("click")
			open_armory())
	return card

## The picked thing: turning in a little window, what it does, and what you can do with it.
func _detail(it: Dictionary) -> Control:
	var col := UI.vbox(6); col.custom_minimum_size.x = 340
	col.add_child(_preview(it))
	col.add_child(UI.title(Loot.name_of(it), 26, Loot.col_of(it)))
	var rn := String(Data.RARITY[Loot.rar_of(it)]["name"])
	var el := String(it.get("el", ""))
	var kind := "Weapon" if String(it["t"]) == "weapon" else ("Active glove" if Gear.active(String(it.get("id", ""))) else "Passive glove")
	col.add_child(UI.label("%s %s%s  ·  worth %d" % [rn, kind.to_lower(), ("  ·  " + String(Loot.ELEMENTS[el]["name"])) if el != "" else "", Loot.value(it)], 14, UI.MUTED))
	if String(it["t"]) == "weapon":
		var ws: Dictionary = Data.weapon_stats(String(it["wid"]), Loot.rar_of(it))
		var dmg := float(ws["dmg"]) * (Loot.UNIQUE_DMG if String(it.get("uq", "")) != "" else 1.0)
		var stat := ("Melee  ·  %s a hit  ·  reach %.1f" % [str(snappedf(dmg, 0.1)), float(ws["range"])]) if ws.get("melee", false) else ("%s damage%s  ·  %d a mag  ·  range %d" % [str(snappedf(dmg, 0.1)), (" x%d" % int(ws["pellets"])) if ws.has("pellets") else "", int(ws["mag"]), int(ws["range"])])
		col.add_child(UI.label(stat, 14, UI.INK))
		if el != "":
			var rl := UI.label(String(Loot.ELEMENTS[el]["rider"]), 14, Loot.ELEMENTS[el]["col"])
			rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			col.add_child(rl)
		var uq := String(it.get("uq", ""))
		if Loot.UNIQUES.has(uq):
			var ul := UI.label("Named weapon: %s  +10%% damage." % Loot.UNIQUES[uq]["perk"], 14, Data.RARITY[4]["color"])
			ul.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			col.add_child(ul)
	else:
		var gl := UI.label(Loot.sub_of(it), 14, UI.INK)
		gl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(gl)
		var gdesc := String(Gear.ALL.get(String(it["id"]), {}).get("desc", ""))
		if gdesc != "":
			var gd2 := UI.label(gdesc, 13, UI.MUTED); gd2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			col.add_child(gd2)
	var slot := "weapon" if String(it["t"]) == "weapon" else Econ.glove_slot(it)
	var on := _in_loadout(it) != ""
	var row := UI.hbox(8)
	var uid := String(it["uid"])
	if on:
		var lb := UI.button("✓ Taking it", func(): Econ.set_loadout(slot, ""); Save.save_game(); open_armory(), 190)
		lb.tooltip_text = "Picked for your next expedition. Click to leave it at home"
		row.add_child(lb)
	else:
		row.add_child(UI.primary("Take it next time", func(): Econ.set_loadout(slot, uid); Sfx.play("pickup"); Save.save_game(); open_armory(), 190))
	row.add_child(UI.button("Sell  %d" % Loot.sell_price(it), func():
		var g := Econ.sell(uid)
		Sfx.play("pickup"); h._toast("Sold for %d gems" % g)
		arm_pick = ""; Save.save_game(); h._refresh_top(); open_armory(), 90))
	row.add_child(UI.button("Salvage  +%d" % Loot.scrap_of(it), func():
		var n := Econ.salvage(uid)
		Sfx.play("build", null, -6.0); h._toast("+%d scrap" % n)
		arm_pick = ""; Save.save_game(); open_armory(), 110))
	col.add_child(row)
	var risk := UI.label("What you take is at risk: go down and it's in your deathbox.", 12, UI.MUTED)
	risk.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(risk)
	return col

func _preview(it: Dictionary) -> Control:
	var svc := SubViewportContainer.new(); svc.stretch = true; svc.custom_minimum_size = Vector2(340, 130)
	var vp := SubViewport.new(); vp.own_world_3d = true; vp.transparent_bg = true; vp.msaa_3d = Viewport.MSAA_2X
	svc.add_child(vp)
	var w3 := Node3D.new(); vp.add_child(w3)
	Look.lights(w3, Color("fff1dc"), 1.0)
	var holder := Node3D.new(); w3.add_child(holder)
	if String(it["t"]) == "weapon":
		var tilt := Node3D.new(); tilt.rotation = Vector3(0, PI / 2, 0.15)
		holder.add_child(tilt)
		var gun := Node3D.new()
		tilt.add_child(gun)
		Models.gun_parts(gun, String(it["wid"]), Models.toon(Color("7a7f92")), Models.toon(Color("4d4b58")), Models.toon(Loot.col_of(it), true, 0.5))
		# centre it on the turntable and size it to the window, whatever its shape
		var bb := _bounds(gun, Transform3D.IDENTITY)
		if bb.size.length() > 0.01:
			var k := 2.0 / maxf(bb.size.x, maxf(bb.size.y, bb.size.z))
			gun.scale = Vector3.ONE * k
			gun.position = -bb.get_center() * k
	else:
		var gd := Models.gear_drop(Gear.ALL.get(String(it["id"]), {}).get("col", Color.WHITE), Loot.rar_of(it))
		gd.position.y = -0.7
		for ch in gd.get_children():
			if ch.name != "Spin": ch.visible = false
		holder.add_child(gd)
	var el := String(it.get("el", ""))
	if el != "":
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new(); tm.inner_radius = 1.05; tm.outer_radius = 1.12
		ring.mesh = tm; ring.material_override = Models.glow_mat(Color(Loot.ELEMENTS[el]["col"], 0.7))
		ring.rotation.x = 0.3
		holder.add_child(ring)
	var pc := Camera3D.new(); pc.fov = 40
	pc.transform = Transform3D(Basis(), Vector3(0, 0.7, 3.2)).looking_at(Vector3(0, 0.0, 0), Vector3.UP)
	w3.add_child(pc)
	var ticker := Timer.new(); ticker.wait_time = 0.033; ticker.autostart = true; svc.add_child(ticker)
	ticker.timeout.connect(func(): if is_instance_valid(holder): holder.rotation.y = Time.get_ticks_msec() / 1200.0)
	return svc

## The box round every mesh under n, in the space n's parent sees it (n needn't be in the tree).
func _bounds(n: Node3D, xf: Transform3D) -> AABB:
	var out := AABB(); var any := false
	for ch in n.get_children():
		if not (ch is Node3D) or not (ch as Node3D).visible: continue
		var cx: Transform3D = xf * (ch as Node3D).transform
		var bb := AABB()
		var got := false
		if ch is MeshInstance3D and (ch as MeshInstance3D).mesh:
			bb = cx * (ch as MeshInstance3D).mesh.get_aabb(); got = true
		var sub := _bounds(ch, cx)
		if sub.size != Vector3.ZERO:
			bb = bb.merge(sub) if got else sub; got = true
		if got:
			out = out.merge(bb) if any else bb; any = true
	return out

func _treasure_n() -> int:
	var n := 0
	for k in Save.d.get("valuables", {}): n += int(Save.d["valuables"][k])
	return n

func _treasure(v: VBoxContainer) -> void:
	var vd: Dictionary = Save.d.get("valuables", {})
	if vd.is_empty():
		var el := UI.label("No treasure yet. Coins, pearls, idols and crown shards from chests, Wardens and rival hunters' boxes end up here to sell.", 15, UI.MUTED)
		el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(el)
		return
	var total := 0
	for id in vd:
		if id != "soul_ember": total += int(vd[id]) * int(Loot.VALUABLES[id]["value"])
	for id in Loot.VALUABLES:
		if int(vd.get(id, 0)) <= 0: continue
		var it := Loot.valuable(id)
		var r := UI.hbox(10)
		r.add_child(Icons.Glyph.new(Loot.icon_of(it), Loot.col_of(it), 26.0))
		var info := UI.vbox(1); info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UI.label("%s  ×%d" % [Loot.name_of(it), int(vd[id])], 16, Loot.col_of(it), UI.semi))
		info.add_child(UI.label(String(Loot.VALUABLES[id]["desc"]), 12, UI.MUTED))
		r.add_child(info)
		var idd: String = id
		r.add_child(UI.button("Sell 1  ·  %d" % int(Loot.VALUABLES[id]["value"]), func():
			var g := Econ.sell_valuable(idd)
			Sfx.play("pickup"); h._toast("+%d gems" % g); Save.save_game(); h._refresh_top(); open_armory(), 140))
		v.add_child(r)
	if total > 0:
		v.add_child(UI.primary("Sell all treasure  ·  %d gems  (keeps Soul Embers)" % total, func():
			var g := 0
			for id in (Save.d["valuables"] as Dictionary).keys():
				if id == "soul_ember": continue
				while int(Save.d["valuables"].get(id, 0)) > 0: g += Econ.sell_valuable(id)
			Sfx.play("unlock"); h._toast("+%d gems" % g); Save.save_game(); h._refresh_top(); open_armory(), 380))

# ------------------------------------------------------------------ the expedition panel
## "From your armory" rows for the expedition panel: weapon and gloves, ‹ › to cycle what's stored.
func loadout_rows(parent: VBoxContainer, reopen: Callable) -> void:
	if not Save.has_building("armory") and Econ.armory().is_empty():
		return
	parent.add_child(UI.section("From your armory"))
	for slot in ["weapon", "glove0", "glove1"]:
		var pool: Array = Econ.armory().filter(func(it):
			if slot == "weapon": return String(it.get("t", "")) == "weapon"
			return String(it.get("t", "")) == "glove" and Econ.glove_slot(it) == slot)
		if pool.is_empty() and slot != "weapon":
			continue
		pool.sort_custom(func(a, b): return Loot.value(a) > Loot.value(b))
		var cur := Econ.loadout(slot)
		var ids: Array = [""] + pool.map(func(it): return String(it["uid"]))
		var at := maxi(0, ids.find(String(cur.get("uid", ""))))
		var card := UI.card(UI.CARD, 6, 10)
		var row := UI.hbox(8); card.add_child(row)
		var what := String({"weapon": "Weapon", "glove0": "Active glove", "glove1": "Passive glove"}[slot])
		var nm := UI.label("%s:  %s" % [what, Loot.name_of(cur) if not cur.is_empty() else ("the one above" if slot == "weapon" else "none")], 14, Loot.col_of(cur) if not cur.is_empty() else UI.MUTED, UI.semi)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.clip_text = true
		nm.tooltip_text = Loot.sub_of(cur) if not cur.is_empty() else ""
		nm.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(nm)
		var sl: String = slot
		for dir in [-1, 1]:
			var dd: int = dir
			var b := UI.button("‹" if dir < 0 else "›", func():
				Econ.set_loadout(sl, String(ids[(at + dd + ids.size()) % ids.size()]))
				Save.save_game()
				reopen.call(), 36)
			b.disabled = ids.size() <= 1
			row.add_child(b)
		parent.add_child(card)
	var pl := UI.label("%sBackpack: %d slots  ·  what you take can be lost if you go down" % ["An armory weapon replaces the one above  ·  " if not Econ.loadout("weapon").is_empty() else "", Econ.pack_cap()], 12, UI.MUTED)
	pl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(pl)
