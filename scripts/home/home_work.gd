class_name HomeWork
extends RefCounted
## Kin at work on the home island (the rules and data are Work's, scripts/core/work.gd).
##
## Every second the farm is looked over for jobs: a dry plot wants watering, an empty one sowing,
## a ripe crop picking, wild trees by a Lumber Camp want felling, a stocked Hearth Oven wants
## kindling, a Spark Mill running down wants cranking, a feeder running low wants filling, a glum
## kin wants cheering up... A farm kin with nothing else on its mind takes the job it's best suited
## to (its element level x the job's priority on the Job Board, less for a long walk), walks over,
## works with a little procedural animation and something in its paws, and what it makes goes into
## your stores (or onto a pile for a Haul kin to carry to the Storage Chest). Working makes kin
## hungrier and more tired; below a point they stop and go to a feeder or a bed. A long shift
## earns a break, and a kin on a High priority job that skips its breaks gets overworked.
##
## home.gd calls: scan() (via tick), pick(k) when a kin is free to choose, step(k, d) every frame,
## pose(k, n, d) after its usual bounce, and job_text(k) for the hover card.

var h                                   # the Home screen
var jobs: Array = []                    # what needs doing right now (see _scan)
var taken := {}                         # job key -> kin uid
var scan_t := 0.0
var spots := {}                         # deco uid -> [sig, Vector3]: where a kin stands to work a station
var pile_nodes := {}                    # pile id -> Node3D
var feed_box: VBoxContainer = null
var feed_lines: Array = []
var anim_t := 0.0

const CAMP_R := 5.0                     # a Lumber Camp / Quarry claims the wild this close
const REGROW := 80.0                    # seconds for a camp's log pile or the quarry's rock to come back
const PILE_CAP := 8
const OVEN_KEEP := 40                   # the oven stops once there's this much kibble
const TONIC_KEEP := 6
const CHARGE_DRAIN := 0.4               # Spark Mill charge per second
const CHILL_DRAIN := 0.25
const TOPUP_AT := 60.0

## Base seconds for each kind of job at level 1 (a level 4 kin takes under half).
const TIME := {"water": 3.0, "plant": 4.0, "tend": 4.5, "harvest": 3.5, "chop": 9.0, "break": 9.0, "log": 6.5, "ore": 7.0,
	"bake": 7.0, "craft": 11.0, "power": 5.0, "chill": 5.0, "carry": 1.2, "stock": 1.5, "mend": 3.5, "brew": 14.0, "ranch": 22.0}
## What each job is called on the hover card and the Job Board.
const VERB := {"water": "Watering the %s", "plant": "Sowing a plot", "tend": "Tending the %s", "harvest": "Picking the %s",
	"chop": "Felling a tree", "break": "Breaking a boulder", "log": "Splitting logs", "ore": "Mining rock", "bake": "Baking kibble",
	"craft": "Crafting scrap", "power": "Cranking the Spark Mill", "chill": "Chilling the Cold Store", "carry": "Hauling %s to the chest",
	"stock": "Filling a feeder", "mend": "Looking after %s", "brew": "Brewing a tonic", "ranch": "Ranching"}
## The animation each job plays.
const ANIM := {"water": "dip", "plant": "dip", "tend": "dip", "harvest": "dip", "chop": "hammer", "break": "hammer", "log": "hammer",
	"ore": "hammer", "bake": "shimmy", "craft": "hammer", "power": "crank", "chill": "shimmy", "carry": "lift", "stock": "lift",
	"mend": "sway", "brew": "sway", "ranch": "lounge"}

func _init(home) -> void:
	h = home

func on() -> bool:
	return h.visit.is_empty()

# ------------------------------------------------------------------ the loop
func tick(d: float) -> void:
	if not on():
		return
	anim_t += d
	Work.ensure()
	_stations_tick(d)
	for k in h.kins:
		if k.has("break_t"):
			k["break_t"] = float(k["break_t"]) - d
			if float(k["break_t"]) <= 0.0: k.erase("break_t")
		# a proper rest (a nap, a night in bed or indoors) ends a shift and the overwork with it
		if float(k.get("nap_t", 0.0)) > 0.0 or k.has("indoors"):
			k["shift"] = 0.0
			if Care.need(k["rec"], "energy") > 55.0: k["rec"].erase("overworked")
	scan_t -= d
	if scan_t <= 0.0:
		scan_t = 1.0
		scan()
	_feed_tick(d)

## What needs doing, from the state of the farm right now.
func scan() -> void:
	jobs.clear()
	if not on() or h.world == null:
		return
	_plot_jobs()
	_wild_jobs()
	_station_jobs()
	_haul_jobs()
	_mend_jobs()
	# forget claims nobody is working on any more
	var live := {}
	for k in h.kins:
		if k.has("job"): live[String(k["job"]["key"])] = String(k["rec"]["uid"])
	taken = live
	_sync_piles()

func _job(key: String, el: String, kind: String, at: Vector3, look: Vector3, extra := {}) -> Dictionary:
	var j := {"key": key, "el": el, "kind": kind, "at": at, "look": look, "t": float(TIME.get(kind, 5.0))}
	j.merge(extra, true)
	jobs.append(j)
	return j

func _isle(p: Vector3) -> int:
	return h.world.island_of(p.x, p.z)

func _ground(x: int, z: int) -> bool:
	var w: World = h.world
	return w.inb(x, z) and w.kind[w.idx(x, z)] == World.T_GROUND

# ------------------------------------------------------------------ jobs from the plots
func _plot_jobs() -> void:
	for arr in ["plots", "gh_plots"]:
		var nodes: Array = h.plots if arr == "plots" else h.gh_plots
		if arr == "gh_plots" and not h._isle_open("orchard"):
			continue
		for i in mini(nodes.size(), (Save.d[arr] as Array).size()):
			var pd: Dictionary = Save.d[arr][i]
			var pp: Vector3 = (nodes[i] as Node3D).position
			var at := pp + Vector3(0, 0, 1.0)
			var ex := {"arr": arr, "i": i}
			var key := "%s:%d" % [arr, i]
			if pd["crop"] == "":
				if _seed_pick() != "": _job("plant:" + key, "bloom", "plant", at, pp, ex)
				continue
			var cd: Dictionary = Data.CROPS[pd["crop"]]
			ex["what"] = String(cd["name"])
			if int(pd["stage"]) >= int(cd["grow"]):
				_job("harvest:" + key, "forage", "harvest", at, pp, ex)
			elif float(pd.get("wt", 0.0)) <= 0.0 or int(pd.get("wet", 2)) < 2:
				_job("water:" + key, "tide", "water", at, pp, ex)
			elif int(pd.get("tend", -1)) != int(pd["stage"]):
				ex["stage"] = int(pd["stage"])
				_job("tend:" + key, "bloom", "tend", at + Vector3(0.6, 0, -0.3), pp, ex)

## The seed a Bloom kin sows: your most plentiful common seed (never the rare ones).
func _seed_pick() -> String:
	var best := ""; var bn := 0
	for s in Data.CROPS:
		if float(Data.CROPS[s].get("weight", 1.0)) < 1.0: continue
		var n := int(Save.d["seeds"].get(s, 0))
		if n > bn: bn = n; best = s
	return best

# ------------------------------------------------------------------ the wild round camps and quarries
func _wild_jobs() -> void:
	if h.hb == null:
		return
	var w: World = h.world
	for pair in [["lumber_camp", "tree", "timber", "chop"], ["quarry", "rock", "stone", "break"]]:
		for s in HomeLayout.stations(h._d(), String(pair[2])):
			if s["id"] != pair[0]: continue
			var c := HomeLayout.deco_center(s["e"])
			var near: Array = []
			for i in h.hb.wild_t:
				if h.hb.wild_t[i] != pair[1]: continue
				var tp := Vector3(i % w.w + 0.5, 0, i / w.w + 0.5)
				var dd := Vector2(tp.x - c.x, tp.z - c.z).length()
				if dd <= CAMP_R: near.append([dd, i, tp])
			near.sort_custom(func(a, b): return a[0] < b[0])
			var n := 0
			for it in near:
				if n >= 3: break
				var stand := _beside(Vector2i(int(it[1]) % w.w, int(it[1]) / w.w), c)
				if stand == Vector3.INF: continue
				_job("%s:%d" % [pair[3], int(it[1])], String(pair[2]), String(pair[3]), stand, it[2], {"tile": int(it[1])})
				n += 1

## An open tile next to a wild one, the side nearest `toward`.
func _beside(t: Vector2i, toward: Vector3) -> Vector3:
	var best := Vector3.INF; var bd := 1e9
	for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var q: Vector2i = t + dv
		if not _ground(q.x, q.y): continue
		var p := Vector3(q.x + 0.5, 0, q.y + 0.5)
		var dd := Vector2(p.x - toward.x, p.z - toward.z).length()
		if dd < bd: bd = dd; best = p
	return best

# ------------------------------------------------------------------ stations
## Where a kin stands to work a station: the open tile beside it, its front side first.
func stand(e: Dictionary, slot := 0) -> Vector3:
	var id := String(e["id"])
	var c := HomeLayout.deco_center(e)
	if id == "ranch_pen":
		var side := Vector3(-0.55 + slot * 1.1, 0, 0.15).rotated(Vector3.UP, int(e.get("r", 0)) * PI * 0.5)
		return c + side
	var sig := "%d,%d,%d,%d" % [int(e["x"]), int(e["z"]), int(e.get("r", 0)), h.hb.ver if h.hb else 0]
	var u := int(e["u"])
	if spots.has(u) and spots[u][0] == sig:
		return spots[u][1]
	var cells := HomeLayout.deco_cells(e)
	var x0 := 9999; var z0 := 9999; var x1 := -9999; var z1 := -9999
	for t in cells:
		x0 = mini(x0, t.x); z0 = mini(z0, t.y); x1 = maxi(x1, t.x); z1 = maxi(z1, t.y)
	var face := HomeLayout.facing(int(e.get("r", 0)))
	var best := Vector3.INF; var bs := -1e9
	for z in range(z0 - 1, z1 + 2):
		for x in range(x0 - 1, x1 + 2):
			if x >= x0 and x <= x1 and z >= z0 and z <= z1: continue
			if not _ground(x, z): continue
			var p := Vector3(x + 0.5, 0, z + 0.5)
			var dv := p - c
			var sc := dv.normalized().dot(face) * 2.0 - dv.length()
			if sc > bs: bs = sc; best = p
	if best == Vector3.INF: best = c + face * 1.0
	spots[u] = [sig, best]
	return best

func _st_ok(s: Dictionary) -> bool:
	var c := HomeLayout.deco_center(s["e"])
	return h.world.island_of(c.x, c.z) >= 0

func has_station(id: String) -> bool:
	for s in HomeLayout.stations(h._d()):
		if s["id"] == id and _st_ok(s): return true
	return false

func _first(id: String) -> Dictionary:
	for s in HomeLayout.stations(h._d()):
		if s["id"] == id and _st_ok(s): return s
	return {}

func _station_jobs() -> void:
	var now := Time.get_unix_time_from_system()
	for s in HomeLayout.stations(h._d()):
		if not _st_ok(s): continue
		var e: Dictionary = s["e"]
		var u := int(e["u"])
		var st := Work.station(u)
		var c := HomeLayout.deco_center(e)
		var ex := {"u": u}
		match String(s["id"]):
			"lumber_camp":
				if now >= float(st.get("ready", 0.0)): _job("log:%d" % u, "timber", "log", stand(e), c, ex)
			"quarry":
				if now >= float(st.get("ready", 0.0)): _job("ore:%d" % u, "stone", "ore", stand(e), c, ex)
			"hearth_oven":
				if Work.mat("wood") >= 1 and int(Save.d["items"].get("kibble", 0)) < OVEN_KEEP: _job("bake:%d" % u, "ember", "bake", stand(e), c, ex)
			"workbench":
				if Work.mat("wood") >= 2 and Work.mat("stone") >= 1: _job("craft:%d" % u, "craft", "craft", stand(e), c, ex)
			"spark_mill":
				if float(st.get("charge", 0.0)) < TOPUP_AT: _job("power:%d" % u, "spark", "power", stand(e), c, ex)
			"cold_store":
				if float(st.get("chill", 0.0)) < TOPUP_AT: _job("chill:%d" % u, "frost", "chill", stand(e), c, ex)
			"infirmary":
				if int(Save.d["items"].get("tonic", 0)) < TONIC_KEEP: _job("brew:%d" % u, "mend", "brew", stand(e), c, ex)
			"ranch_pen":
				for slot in 2:
					var ex2 := {"u": u, "slot": slot}
					_job("ranch:%d:%d" % [u, slot], "ranch", "ranch", stand(e, slot), c + Vector3(0, 0, -0.6), ex2)

## Stations running down: the mill's charge and the cold store's chill drain; their looks follow.
func _stations_tick(d: float) -> void:
	var now := Time.get_unix_time_from_system()
	var alive := {}
	for s in HomeLayout.stations(h._d()):
		var e: Dictionary = s["e"]
		var u := int(e["u"])
		alive[str(u)] = true
		var st := Work.station(u)
		if st.has("charge"): st["charge"] = maxf(0.0, float(st["charge"]) - CHARGE_DRAIN * d)
		if st.has("chill"): st["chill"] = maxf(0.0, float(st["chill"]) - CHILL_DRAIN * d)
		var n: Node3D = h.hb.nodes.get(u) if h.hb else null
		if not is_instance_valid(n): continue
		match String(s["id"]):
			"lumber_camp", "quarry":
				var part := n.get_node_or_null("Logs" if s["id"] == "lumber_camp" else "Ore") as Node3D
				if part:
					var left := float(st.get("ready", 0.0)) - now
					part.visible = left <= 0.0 or left < REGROW * 0.5
					part.scale = Vector3.ONE * (1.0 if left <= 0.0 else clampf(1.0 - left / REGROW, 0.3, 1.0))
			"spark_mill":
				var wh := n.get_node_or_null("Wheel") as Node3D
				var ch := float(st.get("charge", 0.0))
				if wh: wh.rotation.z -= d * (0.4 + ch / 100.0 * 6.0) if ch > 0.0 else 0.0
				var core := n.get_node_or_null("Charge") as MeshInstance3D
				if core: core.scale = Vector3.ONE * (0.5 + ch / 100.0 * 0.7)
			"cold_store":
				var fr := n.get_node_or_null("Frost") as Node3D
				if fr: fr.visible = float(st.get("chill", 0.0)) > 0.0
			"hearth_oven":
				var fi := n.get_node_or_null("Fire") as Node3D
				if fi: fi.visible = _worked(u)
		var tag := n.get_node_or_null("Tag") as Label3D
		if tag: _tag(tag, s, st, now)
	# drop the state of stations that were put away
	var stt: Dictionary = Work.ensure()["st"]
	for key in stt.keys():
		if not alive.has(key): stt.erase(key)

func _worked(u: int) -> bool:
	for k in h.kins:
		if k.has("job") and int(k["job"].get("u", -1)) == u and String(k["job"]["phase"]) == "work": return true
	return false

## The little label over a station: shown when you're close, with what it's doing.
func _tag(tag: Label3D, s: Dictionary, st: Dictionary, now: float) -> void:
	var c := HomeLayout.deco_center(s["e"])
	var near: bool = Vector2(h.ppos.x - c.x, h.ppos.z - c.z).length() < 4.5 or "--work-demo" in OS.get_cmdline_user_args()
	tag.visible = near and not (h.hb and h.hb.active)
	if not tag.visible:
		return
	var nm := String(HomeLayout.CATALOG[s["id"]]["name"])
	var line := ""
	match String(s["id"]):
		"lumber_camp", "quarry":
			var left := float(st.get("ready", 0.0)) - now
			line = "ready" if left <= 0.0 else "grows back in %ds" % int(ceil(left))
		"spark_mill": line = "charge %d%%" % int(float(st.get("charge", 0.0)))
		"cold_store": line = "chilled %d%%" % int(float(st.get("chill", 0.0)))
		"hearth_oven": line = "%d kibble" % int(Save.d["items"].get("kibble", 0)) if Work.mat("wood") > 0 else "needs wood"
		"workbench": line = "%d scrap" % int(Save.d.get("scrap", 0)) if Work.mat("wood") >= 2 and Work.mat("stone") >= 1 else "needs wood and stone"
		"storage_chest": line = "%d wood · %d stone" % [Work.mat("wood"), Work.mat("stone")]
		"infirmary":
			var tn := int(Save.d["items"].get("tonic", 0))
			line = "%d tonic%s" % [tn, "" if tn == 1 else "s"]
		"job_board": line = "%s set jobs" % Settings.key_cap("interact")
	var who := ""
	for k in h.kins:
		if k.has("job") and int(k["job"].get("u", -1)) == int(s["e"]["u"]): who = String(k["rec"]["name"]); break
	tag.text = nm + ("\n" + line if line != "" else "") + ("\n" + who + " working" if who != "" else "")

# ------------------------------------------------------------------ haul: piles to the chest, food to feeders
func _haul_jobs() -> void:
	var chest := _first("storage_chest")
	var to := stand(chest["e"]) if not chest.is_empty() else Vector3.INF
	if not chest.is_empty():
		for p in Work.ensure()["piles"]:
			var pp := Vector3(float(p["x"]), 0, float(p["z"]))
			_job("carry:%d" % int(p["id"]), "haul", "carry", pp + Vector3(0.45, 0, 0.3), pp, {"pile": int(p["id"]), "to": to, "what": String(p["mat"])})
	if h.hecon == null:
		return
	var pick: Vector3 = to if to != Vector3.INF else h._seat({"rec": {"uid": "pantry"}}, h.spots["pot"], 1.3)
	for f in Econ.feeders():
		if Econ.fill(f) > int(Econ.fdef(f)["cap"]) / 2 or Econ._auto_food() == "":
			continue
		var ss: Array = h.hecon.seats(f)
		var fp: Vector3 = h.hecon._fpos(f)
		var drop: Vector3 = ss[0] if not ss.is_empty() else fp + Vector3(0, 0, 1.0)
		_job("stock:%s" % String(f["id"]), "haul", "stock", pick, pick, {"fid": String(f["id"]), "to": drop, "look2": fp})

## A pile of wood or stone left where it was made, for a Haul kin to carry in. Only when there's a
## chest and someone who'd haul; otherwise it goes straight into your stores.
func _make_pile(at: Vector3, m: String, n: int) -> bool:
	if not has_station("storage_chest"):
		return false
	var w := Work.ensure()
	if (w["piles"] as Array).size() >= PILE_CAP:
		return false
	if not h.kins.any(func(o): return Work.takes(o["rec"], "haul")):
		return false
	w["pid"] = int(w.get("pid", 0)) + 1
	(w["piles"] as Array).append({"id": int(w["pid"]), "x": at.x, "z": at.z, "mat": m, "n": n})
	_sync_piles()
	return true

func _pile(id: int) -> Dictionary:
	for p in Work.ensure()["piles"]:
		if int(p["id"]) == id: return p
	return {}

func _sync_piles() -> void:
	var want := {}
	for p in Work.ensure()["piles"]:
		want[int(p["id"])] = p
	for id in pile_nodes.keys():
		if not want.has(id):
			if is_instance_valid(pile_nodes[id]): pile_nodes[id].queue_free()
			pile_nodes.erase(id)
	for id in want:
		if pile_nodes.has(id): continue
		var p: Dictionary = want[id]
		var n: Node3D = Assets.prop("hexagon/resource_lumber" if p["mat"] == "wood" else "hexagon/resource_stone", 0.55, false)
		if n == null:
			n = Node3D.new()
			Models.part(n, Models.box(0.4, 0.2, 0.3), Models.toon(Color("9a6a40") if p["mat"] == "wood" else Color("a8a29a")), Vector3(0, 0.1, 0))
		n.position = Vector3(float(p["x"]), 0, float(p["z"]))
		h.add_child(n)
		pile_nodes[id] = n

# ------------------------------------------------------------------ mend
func _mend_jobs() -> void:
	if not has_station("infirmary"):
		return
	for o in h.kins:
		var r: Dictionary = o["rec"]
		if o.has("indoors") or float(o.get("nap_t", 0.0)) > 0.0 or float(o.get("mended", 0.0)) > Time.get_ticks_msec() / 1000.0:
			continue
		if Care.need(r, "joy") < 35.0 or Care.need(r, "energy") < 25.0 or Care.starve_stage(r) != "":
			_job("mend:%s" % String(r["uid"]), "mend", "mend", o["pos"], o["pos"], {"who": String(r["uid"]), "what": String(r["name"])})

# ------------------------------------------------------------------ choosing a job
func _night() -> bool:
	return sin((h.day_t - 0.25) * TAU) < -0.2

## A free kin looks for work. True if it took a job.
func pick(k: Dictionary) -> bool:
	if not on():
		return false
	var rec: Dictionary = k["rec"]
	if not Work.can_work(rec) or k.has("break_t") or k.has("job"):
		return false
	if Care.need(rec, "food") < Work.START["food"] or Care.need(rec, "energy") < Work.START["energy"]:
		return false
	if _night() and not Work.NOCTURNAL.has(String(rec["species"])):
		return false
	var best := best_job(k)
	if best.is_empty():
		return false
	take(k, best)
	return true

## The job this kin would take now ({} for none).
func best_job(k: Dictionary) -> Dictionary:
	var rec: Dictionary = k["rec"]
	var here := _isle(k["pos"])
	var best := {}; var bs := 0.0
	for j in jobs:
		if taken.has(j["key"]) and taken[j["key"]] != String(rec["uid"]): continue
		if String(j.get("who", "")) == String(rec["uid"]): continue       # nobody nurses itself
		var el := String(j["el"])
		if not Work.takes(rec, el): continue
		var at: Vector3 = j["at"]
		if _isle(at) != here: continue
		var sc := Work.score(Work.level(rec, el), Work.prio(el), Vector2(at.x - k["pos"].x, at.z - k["pos"].z).length())
		if sc > bs: bs = sc; best = j
	return best

func take(k: Dictionary, j: Dictionary) -> void:
	var J := j.duplicate()
	J["phase"] = "go"; J["go_t"] = 0.0; J["vt"] = 1.0
	J["lv"] = Work.level(k["rec"], String(J["el"]))
	k["job"] = J
	taken[String(J["key"])] = String(k["rec"]["uid"])
	k.erase("chase"); k.erase("stare"); k.erase("task")
	if randf() < 0.4: h._emote(k, "!")

## Stops working: done (true) or interrupted. Puts its paws down and frees the job.
func drop(k: Dictionary, _done := false) -> void:
	if not k.has("job"):
		return
	taken.erase(String(k["job"]["key"]))
	k.erase("job")
	var n: Node3D = k["node"]
	var held := n.get_node_or_null("Held")
	if held: held.queue_free()
	var body := n.get_node_or_null("Body") as Node3D
	if body: body.rotation = Vector3.ZERO; body.scale = Vector3.ONE

## Is the job still there to do?
func _valid(J: Dictionary) -> bool:
	match String(J["kind"]):
		"water", "plant", "tend", "harvest":
			var arr := String(J["arr"]); var i := int(J["i"])
			if i >= (Save.d[arr] as Array).size(): return false
			var pd: Dictionary = Save.d[arr][i]
			if J["kind"] == "plant": return pd["crop"] == "" and _seed_pick() != ""
			if pd["crop"] == "": return false
			var grow := int(Data.CROPS[pd["crop"]]["grow"])
			match String(J["kind"]):
				"harvest": return int(pd["stage"]) >= grow
				"water": return int(pd["stage"]) < grow and (float(pd.get("wt", 0.0)) <= 0.0 or int(pd.get("wet", 2)) < 2)
				"tend": return int(pd["stage"]) < grow and float(pd.get("wt", 0.0)) > 0.0 and int(pd.get("tend", -1)) != int(pd["stage"])
		"chop", "break":
			return h.hb != null and h.hb.wild_t.has(int(J["tile"]))
		"carry":
			return not _pile(int(J["pile"])).is_empty() or String(J["phase"]) == "to"
		"stock":
			return not h.hecon._feeder(String(J["fid"])).is_empty()
		"mend":
			return not h._kin_entry(Save.kin(String(J["who"]))).is_empty()
	if J.has("u"):
		for s in HomeLayout.stations(h._d()):
			if int(s["e"]["u"]) == int(J["u"]): return true
		return false
	return true

## How much faster this job goes: the Spark Mill powers the oven, workbench and infirmary.
func powered() -> bool:
	for s in HomeLayout.stations(h._d(), "spark"):
		if float(Work.station(int(s["e"]["u"])).get("charge", 0.0)) > 0.0: return true
	return false

func _boost(J: Dictionary) -> float:
	return 1.5 if String(J["kind"]) in ["bake", "craft", "brew"] and powered() else 1.0

# ------------------------------------------------------------------ working
## Every frame for a kin with a job. home.gd skips its wandering while this has it.
func step(k: Dictionary, d: float) -> void:
	if not k.has("job"):
		return
	var J: Dictionary = k["job"]
	var rec: Dictionary = k["rec"]
	if k.has("called_t") or k.get("busy", false) or k.has("fetch") or k.has("bath") or k.has("eat") or float(k.get("nap_t", 0.0)) > 0.0 \
			or k.has("indoors") or k.has("leap") or k.get("nap_go", false) or not Work.takes(rec, String(J["el"])):
		drop(k)
		return
	if Care.need(rec, "food") < Work.STOP["food"] or Care.need(rec, "energy") < Work.STOP["energy"]:
		# hungry or worn out: down tools and go eat or sleep (Home's care routines take it from here)
		drop(k)
		k["t"] = 0.0
		k["break_t"] = 6.0
		h._emote(k, "z" if Care.need(rec, "energy") < Work.STOP["energy"] else "?")
		return
	J["vt"] = float(J["vt"]) - d
	if float(J["vt"]) <= 0.0:
		J["vt"] = 1.0
		if not _valid(J):
			drop(k)
			k["t"] = randf_range(0.3, 1.0)
			return
	var pos: Vector3 = k["pos"]
	match String(J["phase"]):
		"go", "to":
			var aim: Vector3 = J["at"] if J["phase"] == "go" else J["to"]
			if J["kind"] == "mend" and J["phase"] == "go":
				var pk: Dictionary = h._kin_entry(Save.kin(String(J["who"])))
				if not pk.is_empty():
					aim = pk["pos"] + Vector3(0.7, 0, 0.2)
					J["look"] = pk["pos"]
					pk["hold_t"] = maxf(float(pk.get("hold_t", 0.0)), 0.5) if Vector2(aim.x - pos.x, aim.z - pos.z).length() < 2.0 else float(pk.get("hold_t", 0.0))
			k["goal"] = aim
			J["go_t"] = float(J["go_t"]) + d
			if float(J["go_t"]) > 35.0:
				drop(k)      # couldn't get there; try something else
				k["break_t"] = 4.0
				return
			if Vector2(aim.x - pos.x, aim.z - pos.z).length() < 0.55:
				if J["phase"] == "go":
					J["phase"] = "work"
					J["left"] = float(J["t"]) / (Work.speed(int(J["lv"])) * _boost(J))
					J["dur"] = J["left"]
					_hold(k, String(J["kind"]))
				else:
					_deliver(k, J)
					drop(k, true)
					k["t"] = randf_range(0.4, 1.2)
		"work":
			k["goal"] = pos
			k["hold_t"] = maxf(float(k.get("hold_t", 0.0)), 0.15)
			var lk: Vector3 = J["look"]
			var n: Node3D = k["node"]
			n.rotation.y = lerp_angle(n.rotation.y, atan2(-(lk.x - pos.x), -(lk.z - pos.z)), minf(1.0, d * 10.0))
			_drain(k, d)
			k["shift"] = float(k.get("shift", 0.0)) + d
			J["left"] = float(J["left"]) - d
			if randf() < d * 1.5:
				h.fx.burst(lk + Vector3(0, 0.5, 0), Work.col_of(String(J["el"])), 3, 1.4, 0.35)
			if float(J["left"]) <= 0.0:
				var more := _finish(k, J)
				if more:
					J["phase"] = "to"; J["go_t"] = 0.0
					_hold(k, "carry_" + String(J.get("what", "stuff")) if J["kind"] == "carry" else String(J["kind"]))
				else:
					drop(k, true)
					k["t"] = randf_range(0.4, 1.2)
				_after_shift(k, String(J["el"]))

## Work takes it out of a kin; one that loves its job (level 3+) enjoys it, unless it's overworked.
func _drain(k: Dictionary, d: float) -> void:
	var rec: Dictionary = k["rec"]
	var m := d / 60.0
	var ow: bool = rec.get("overworked", false)
	Care.change(rec, "food", -Work.DRAIN["food"] * m)
	Care.change(rec, "energy", -Work.DRAIN["energy"] * m * (1.4 if ow else 1.0))
	var lv := int(k["job"].get("lv", 1))
	Care.change(rec, "joy", (-Work.DRAIN["joy"] * 4.0 if ow else (0.4 if lv >= 3 else -Work.DRAIN["joy"])) * m)

## After a stretch of work: a break, or (on a High priority job) overwork.
func _after_shift(k: Dictionary, el: String) -> void:
	if float(k.get("shift", 0.0)) < Work.SHIFT:
		return
	var rec: Dictionary = k["rec"]
	if Work.prio(el) >= 3:
		if not rec.get("overworked", false):
			rec["overworked"] = true
			h._emote(k, "!")
			h._say(k, KinSpeak.say(rec, "sad", "energy"), 2.4, false)
	else:
		k["shift"] = 0.0
		k["break_t"] = Work.BREAK
		drop(k)
		h._emote(k, "♪")

## Something to hold up while it works.
func _hold(k: Dictionary, kind: String) -> void:
	var n: Node3D = k["node"]
	var old := n.get_node_or_null("Held")
	if old: old.free()
	var it := WorkModels.held(kind, String(k["job"]["el"]) if k.has("job") else "")
	n.add_child(it)
	it.position = Vector3(0, 0.5, -0.36)

## The kin's work pose, played over its usual bounce (after home.gd's _quirk).
func pose(k: Dictionary, n: Node3D, d: float) -> void:
	if not k.has("job"):
		return
	var J: Dictionary = k["job"]
	var body := n.get_node_or_null("Body") as Node3D
	var held := n.get_node_or_null("Held") as Node3D
	if body == null:
		return
	var t := anim_t * 1.0 + float(absi(String(k["rec"]["uid"]).hash()) % 10)
	if J["phase"] == "to":
		# carrying it home: held up over its head
		if held: held.position = Vector3(0, 0.95 + body.position.y, -0.05)
		return
	if J["phase"] != "work":
		return
	var a := String(ANIM.get(String(J["kind"]), "dip"))
	match a:
		"hammer":
			var s := sin(t * 9.0)
			body.rotation.x = -maxf(0.0, s) * 0.45 + 0.08
			body.position.y = absf(s) * 0.05
			if held: held.position = Vector3(0, 0.62 + maxf(0.0, s) * 0.18, -0.34 - maxf(0.0, -s) * 0.1)
		"dip":
			var s := sin(t * 4.5)
			body.rotation.x = -0.28 - s * 0.14
			body.position.y = absf(s) * 0.03
			if held: held.position = Vector3(0.05, 0.42 - s * 0.05, -0.4); held.rotation.z = -0.6 + s * 0.25
		"shimmy":
			body.rotation.z = sin(t * 8.0) * 0.16
			body.position.y = absf(sin(t * 8.0)) * 0.04
			if held: held.position = Vector3(0, 0.5, -0.38)
		"crank":
			body.rotation.y = sin(t * 6.0) * 0.4
			body.position.y = absf(sin(t * 12.0)) * 0.08
			if held: held.position = Vector3(sin(t * 6.0) * 0.12, 0.55 + cos(t * 6.0) * 0.1, -0.36)
		"sway":
			body.rotation.z = sin(t * 2.5) * 0.12
			body.rotation.x = -0.12
			if held: held.position = Vector3(0, 0.55 + sin(t * 2.5) * 0.04, -0.36)
		"lounge":
			body.rotation.x = 0.0
			body.scale = Vector3(1.06, 0.9 + sin(t * 1.6) * 0.03, 1.06)
			body.position.y = 0.0
			if held: held.visible = false
		"lift":
			body.position.y = absf(sin(t * 5.0)) * 0.08
			if held: held.position = Vector3(0, 0.6 + body.position.y, -0.3)

## The job's result. Returns true when there's a second leg (carrying something somewhere).
func _finish(k: Dictionary, J: Dictionary) -> bool:
	var rec: Dictionary = k["rec"]
	var lv := int(J["lv"])
	var at: Vector3 = J["look"]
	var nm := String(rec["name"])
	rec["trust"] = minf(100.0, float(rec["trust"]) + 0.15)
	match String(J["kind"]):
		"water":
			h._water(String(J["arr"]), int(J["i"]), "kin")
			h.fx.burst(at + Vector3(0, 0.6, 0), Color("7ac8ff"), 12, 2.0)
			Work.count("watered", 1)
		"plant":
			var sd := _seed_pick()
			if sd == "": return false
			var pd: Dictionary = Save.d[String(J["arr"])][int(J["i"])]
			Save.d["seeds"][sd] = int(Save.d["seeds"][sd]) - 1
			pd["crop"] = sd; pd["stage"] = 0; pd["care"] = 0; pd["wt"] = 0.0
			h._refresh_plot(String(J["arr"]), int(J["i"]))
			h.fx.dust(at, 8)
			Sfx.play("plant", at, -10.0)
			produced(at, "%s sowed %s" % [nm, Data.CROPS[sd]["name"]], "bloom", "")
			Work.count("sown", 1)
		"tend":
			var pd: Dictionary = Save.d[String(J["arr"])][int(J["i"])]
			pd["tend"] = int(pd["stage"])
			pd["wt"] = float(pd.get("wt", 0.0)) - Data.WATER_TIME * (0.12 + 0.06 * lv)
			h.fx.burst(at + Vector3(0, 0.6, 0), Color("8fd16a"), 10, 1.6)
			Work.count("tended", 1)
		"harvest":
			var got: int = h._harvest(String(J["arr"]), int(J["i"]), "kin")
			if got > 0:
				var cname := String(J.get("what", "crop"))
				produced(at, "+%d %s · %s" % [got, cname, nm], "forage", "")
		"chop", "break":
			var tile := int(J["tile"])
			var w: World = h.world
			if h.hb.clear_wild(Vector2i(tile % w.w, tile / w.w)):
				h.hb.mesh_t = 0.15
				h.hb.ver += 1
				h.hb._reach_cache.clear()
				h.hb.refresh_grid()
				var m := "wood" if J["kind"] == "chop" else "stone"
				_out(at, m, 3 + (1 if lv >= 3 else 0), nm, String(J["el"]))
				h.fx.dust(at, 14)
				Sfx.play("thump", at, -6.0, 0.1, 0.8)
		"log", "ore":
			Work.station(int(J["u"]))["ready"] = Time.get_unix_time_from_system() + REGROW
			_out(at, "wood" if J["kind"] == "log" else "stone", 2 + (1 if lv >= 3 else 0), nm, String(J["el"]))
			Sfx.play("thump", at, -10.0, 0.1, 1.2)
		"bake":
			if Work.mat("wood") < 1: return false
			Work.add_mat("wood", -1)
			var kb := 2 + (1 if lv >= 3 else 0)
			Save.add_item("kibble", kb)
			Work.count("kibble", kb)
			produced(at, "+%d kibble · %s at the Hearth Oven" % [kb, nm], "ember", "")
		"craft":
			if Work.mat("wood") < 2 or Work.mat("stone") < 1: return false
			Work.add_mat("wood", -2); Work.add_mat("stone", -1)
			Save.d["scrap"] = int(Save.d.get("scrap", 0)) + 1
			Work.count("scrap", 1)
			produced(at, "+1 scrap · %s at the Workbench" % nm, "craft", "")
		"power":
			var st := Work.station(int(J["u"]))
			st["charge"] = minf(100.0, float(st.get("charge", 0.0)) + 20.0 + 15.0 * lv)
			h.fx.burst(at + Vector3(0, 1.0, 0), Color("ffe04a"), 14, 2.6)
			produced(at, "Spark Mill charged to %d%% · %s" % [int(st["charge"]), nm], "spark", "")
		"chill":
			var st := Work.station(int(J["u"]))
			st["chill"] = minf(100.0, float(st.get("chill", 0.0)) + 20.0 + 15.0 * lv)
			h.fx.burst(at + Vector3(0, 0.8, 0), Color("cfefff"), 14, 1.6)
			produced(at, "Cold Store chilled to %d%% · %s" % [int(st["chill"]), nm], "frost", "")
		"brew":
			Save.add_item("tonic", 1)
			Work.count("tonics", 1)
			produced(at, "+1 tonic · %s at the Infirmary" % nm, "mend", "")
		"mend":
			var pr := Save.kin(String(J["who"]))
			var pk: Dictionary = h._kin_entry(pr)
			if pr.is_empty(): return false
			Care.change(pr, "joy", 10.0 + 4.0 * lv)
			Care.change(pr, "energy", 6.0 + 3.0 * lv)
			if not pk.is_empty():
				pk["mended"] = Time.get_ticks_msec() / 1000.0 + 60.0
				h._emote(pk, "♥")
				pk["joy_t"] = 0.8
			produced(at, "%s looked after %s" % [nm, pr["name"]], "mend", "")
			Work.count("mended", 1)
		"ranch":
			var r: Array = Work.RANCH.get(String(rec["species"]), Work.RANCH_DEFAULT)
			var cnt := int(r[2]) + (1 if lv >= 4 else 0)
			match String(r[0]):
				"crop": Save.d["crops"][r[1]] = int(Save.d["crops"].get(r[1], 0)) + cnt
				"mat": Work.add_mat(String(r[1]), cnt)
				_: Save.add_item(String(r[1]), cnt)
			Work.count(String(r[1]), cnt)
			produced(at, "+%d %s · %s in the Ranch Pen" % [cnt, Care.food_name(String(r[1])) if String(r[0]) != "mat" else String(r[1]), nm], "ranch", "")
		"carry":
			var p := _pile(int(J["pile"]))
			if p.is_empty(): return false
			J["load"] = int(p["n"]); J["what"] = String(p["mat"])
			(Work.ensure()["piles"] as Array).erase(p)
			_sync_piles()
			return true
		"stock":
			# pick up food from the chest (or the pantry by the pot), then off to the feeder
			var take_n := 1 + lv
			var load: Array = []
			for _i in take_n:
				var key := Econ._auto_food()
				if key == "" or not Econ._take_pantry(key): break
				load.append(key)
			if load.is_empty(): return false
			J["load"] = load
			J["look"] = J.get("look2", J["to"])
			return true
	Save.save_game()
	return false

## The second leg: putting down what it carried.
func _deliver(k: Dictionary, J: Dictionary) -> void:
	var nm := String(k["rec"]["name"])
	match String(J["kind"]):
		"carry":
			var m := String(J.get("what", "wood"))
			var n := int(J.get("load", 0))
			Work.add_mat(m, n)
			Work.count(m, n)
			produced(J["to"], "+%d %s into the chest · %s" % [n, m, nm], "haul", m)
		"stock":
			var f: Dictionary = h.hecon._feeder(String(J["fid"]))
			var load: Array = J.get("load", [])
			var put := 0
			for key in load:
				if not f.is_empty() and Econ.room_in(f) > 0:
					(f["food"] as Array).append(key); put += 1
				else:
					# no room after all: back in the pantry
					if Data.CROPS.has(key): Save.d["crops"][key] = int(Save.d["crops"].get(key, 0)) + 1
					else: Save.add_item(key, 1)
			if not f.is_empty(): h.hecon.refresh_feeder(f)
			if put > 0: produced(J["to"], "%s filled a feeder (+%d)" % [nm, put], "haul", "")
	Save.save_game()

## Wood or stone made: onto a pile for a hauler, or straight into your stores.
func _out(at: Vector3, m: String, n: int, who: String, el: String) -> void:
	if _make_pile(at + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3)), m, n):
		produced(at, "%s left %d %s for a hauler" % [who, n, m], el, m)
		return
	Work.add_mat(m, n)
	Work.count(m, n)
	produced(at, "+%d %s · %s" % [n, m, who], el, m)

# ------------------------------------------------------------------ telling you
## A station made something: a word floating up from it and a line in the work feed.
func produced(at: Vector3, text: String, el: String, _what: String) -> void:
	if h.fx:
		var w := text.split(" · ")[0]
		h.fx.word(at + Vector3(0, 1.3, 0), w, Work.col_of(el).lightened(0.25))
	Sfx.play("pickup", at, -14.0, 0.1, 1.3)
	feed(text, Work.col_of(el), el)

func feed(text: String, col: Color, el := "") -> void:
	if h.root_ui == null:
		return
	if not is_instance_valid(feed_box):
		feed_box = UI.vbox(4)
		feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		feed_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		feed_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		feed_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
		feed_box.offset_right = -18; feed_box.offset_bottom = -132
		feed_box.alignment = BoxContainer.ALIGNMENT_END
		h.root_ui.add_child(feed_box)
	var row := UI.glass(6, 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hb := UI.hbox(6)
	row.add_child(hb)
	if el != "" and Work.ELEMENTS.has(el):
		hb.add_child(WorkView.Icon.new(el, 18.0))
	var l := UI.label(text, 13, col.lerp(UI.INK, 0.45), UI.semi)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	hb.add_child(l)
	feed_box.add_child(row)
	feed_lines.append({"n": row, "t": 6.0})
	while feed_lines.size() > 4:
		var old: Dictionary = feed_lines.pop_front()
		if is_instance_valid(old["n"]): old["n"].queue_free()

func _feed_tick(d: float) -> void:
	for f in feed_lines:
		f["t"] = float(f["t"]) - d
		if is_instance_valid(f["n"]):
			(f["n"] as Control).modulate.a = clampf(float(f["t"]) / 1.0, 0.0, 1.0)
			(f["n"] as Control).visible = h.panel_open == "" or h.panel_open == "Job Board"
	for f in feed_lines.filter(func(x): return float(x["t"]) <= 0.0):
		if is_instance_valid(f["n"]): f["n"].queue_free()
		feed_lines.erase(f)

## What a kin is up to, for the hover card ("" when it isn't working).
func job_text(k: Dictionary) -> String:
	if not k.has("job"):
		return ""
	var J: Dictionary = k["job"]
	var v := String(VERB.get(String(J["kind"]), "Working"))
	if v.contains("%s"): v = v % String(J.get("what", "it"))
	var lv := int(J.get("lv", 1))
	var where := "on the way" if J["phase"] == "go" else ("carrying it over" if J["phase"] == "to" else "%d%%" % int(100.0 * (1.0 - float(J.get("left", 0.0)) / maxf(0.01, float(J.get("dur", 1.0))))))
	return "%s (%s %d, %s)" % [v, Work.name_of(String(J["el"])), lv, where]

## Who's doing what, for the Job Board: [{k, text, el}].
func workers() -> Array:
	var out: Array = []
	for k in h.kins:
		var r: Dictionary = k["rec"]
		var t := job_text(k)
		var why := Work.why_not(r)
		if t == "":
			if why != "": t = why
			elif k.has("break_t"): t = "On a break"
			elif k.has("eat"): t = "Eating"
			elif float(k.get("nap_t", 0.0)) > 0.0 or k.has("indoors"): t = "Resting"
			elif _night() and not Work.NOCTURNAL.has(String(r["species"])): t = "Off for the night"
			else: t = "Free: nothing it's suited to needs doing"
		out.append({"k": k, "text": t, "el": String(k["job"]["el"]) if k.has("job") else ""})
	return out

# ------------------------------------------------------------------ tooling: --work-demo, --shiny-lineup
## A made-up farm for screenshots: six kin, every station east of the farm, some wood and stone.
## Never written to the save.
static func demo_save() -> Dictionary:
	var d := Save.fresh()
	d["tutorial"] = {"home": true, "day1_done": true}
	d["gems"] = 900; d["scrap"] = 6
	d["seeds"] = {"tidebloom": 4, "puffcorn": 3, "sunroot": 2}
	d["plots"] = [{"crop": "sunroot", "stage": 0, "care": 0, "wt": 0.0}, {"crop": "puffcorn", "stage": 1, "care": 1, "wt": 0.0},
		{"crop": "", "stage": 0}, {"crop": "emberberry", "stage": 1, "care": 0, "wt": 1.0, "wet": 2}]
	var names := [["puddlet", "Drip"], ["pebbit", "Rocky"], ["cindle", "Ash"], ["zapple", "Zip"], ["burrlet", "Moss"], ["wisplet", "Hoot"]]
	for p in names:
		var r := Save.new_kin(p[0], p[1])
		r["level"] = 6; r["trust"] = 70.0
		for n in Care.NEEDS: r["needs"][n] = 90.0
		d["roster"].append(r)
	d["active"] = d["roster"][0]["uid"]
	d["roster"][0]["starter"] = true
	d["roster"][4]["mutations"] = ["giant"]
	var L := HomeLayout.fresh()
	var u := 0
	for s in [["job_board", 52, 31], ["lumber_camp", 54, 31], ["quarry", 57, 31], ["storage_chest", 60, 31], ["hearth_oven", 52, 35],
			["workbench", 54, 35], ["spark_mill", 57, 35], ["cold_store", 59, 35], ["infirmary", 52, 39], ["ranch_pen", 56, 38]]:
		u += 1
		(L["deco"] as Array).append({"u": u, "id": s[0], "x": s[1], "z": s[2], "r": 0})
	L["uid"] = u
	d["layout"] = L
	d["mats"] = {"wood": 14, "stone": 9}
	d["work"] = {"prio": {}, "st": {}, "made": {"wood": 23, "stone": 11, "kibble": 16, "watered": 9}, "piles": []}
	return d

## Everyone at work at once, posed mid-job, for a screenshot.
func demo(which: String) -> void:
	h.day_t = 0.45
	var mid := Vector3(55.5, 0, 35.5)
	# the camera follows you: stand in the middle of it all, out of sight
	h.ppos = Vector3(54.8, 0, 34.6); h.player.position = h.ppos; h.player.visible = false
	h.cam.zoom_to = 0.92; h.cam.zoom = 0.92; h.cam.snap(h.ppos)
	if which == "--shiny-lineup":
		for k in h.kins: (k["node"] as Node3D).visible = false; k["busy"] = true
		var sps: Array = Data.KIN.keys()
		for i in sps.size():
			for sh in 2:
				var rec := Save.new_kin(sps[i]); rec["level"] = 6; rec["shimmer"] = sh == 1
				var n := Models.kin(sps[i], rec)
				n.position = Vector3(49.9 + i * 2.1, 0, 33.2 + sh * 2.5)
				n.rotation.y = PI * 0.15
				n.scale *= 1.5
				h.add_child(n)
				var l := Label3D.new()
				l.text = ("%s\nshimmering" % Data.KIN[sps[i]]["name"]) if sh == 1 else String(Data.KIN[sps[i]]["name"])
				l.font = UI.big; l.font_size = 36; l.pixel_size = 0.009; l.outline_size = 10
				l.billboard = BaseMaterial3D.BILLBOARD_ENABLED; l.no_depth_test = true
				l.modulate = Color("fff3b0") if sh == 1 else Color.WHITE
				l.position = n.position + Vector3(0, 1.75, 0)
				h.add_child(l)
				if sh == 1: Shiny.sparkle(h, n.position, sps[i], 1.3, false)
		for u in h.hb.nodes: (h.hb.nodes[u] as Node3D).visible = false
		h.ppos = Vector3(55.2, 0, 34.6); h.player.position = h.ppos
		h.cam.zoom_to = 0.62; h.cam.zoom = 0.62; h.cam.snap(h.ppos)
		return
	scan()
	var used := {}
	for k in h.kins:
		k["pos"] = mid; (k["node"] as Node3D).position = mid
		var best := {}; var bs := 0.0
		for j in jobs:
			if used.has(j["key"]): continue
			var sc := float(Work.level(k["rec"], String(j["el"])))
			if sc > bs: bs = sc; best = j
		if best.is_empty(): continue
		used[best["key"]] = true
		take(k, best)
		var J: Dictionary = k["job"]
		k["pos"] = J["at"]; (k["node"] as Node3D).position = J["at"]
		J["phase"] = "work"; J["left"] = 999.0; J["dur"] = 1400.0
		_hold(k, String(J["kind"]))
		k["t"] = 999.0
	if which == "--work-close":
		h.ppos = Vector3(55.6, 0, 34.0); h.player.position = h.ppos
		h.cam.zoom_to = 0.5; h.cam.zoom = 0.5; h.cam.snap(h.ppos)
	if which == "--work-build":
		h.get_tree().create_timer(0.6).timeout.connect(func():
			h.hb.toggle(); h.hb.cat = "Work"; h.hb.take("hearth_oven"); h.hb.debug_m = Vector2(61.5, 39.5); h.hb._build_bar())
	if which.begins_with("--work-board"):
		var tb := which.substr(13) if which.length() > 13 else "Jobs"
		h.get_tree().create_timer(0.6).timeout.connect(func(): h.open_job_board(tb))
	elif which == "--work-card":
		h.get_tree().create_timer(0.6).timeout.connect(func(): h.kin_tab = "Care"; h._open_kin(h.kins[1]["rec"]))
	elif which == "--work-box":
		h.get_tree().create_timer(0.6).timeout.connect(func(): KinBoxView.filter = "el:haul"; h._open_burrow())
	elif which == "--work-hover":
		var k: Dictionary = h.kins[1]
		h.get_tree().create_timer(0.8).timeout.connect(func():
			var sp: Vector2 = h.cam.unproject_position((k["node"] as Node3D).global_position + Vector3(0, 0.45, 0))
			h.get_viewport().warp_mouse(sp))
