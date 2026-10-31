class_name SpawnPlan
extends RefCounted
## Randomised spawns on a fixed map. The layout of an expedition map never changes, but each match
## rolls which of a fixed set of candidate points are live: where the rare kin are, which vaults hold
## a hoard, where the item caches lie, (later) which boss lair is awake. The full map (M) shows every
## candidate of every category, so you can plan a drop around them.
##
## What the map tells you (the SUPERVIVE way of doing it):
##  - Big events ("announce" categories: vaults, boss lairs) are shown live from the start: the whole
##    lobby knows where the hoards are, so they're worth fighting over and worth dropping on.
##  - Everything else (rare kin, item caches) shows as a faint "?" at every possible spot. What's
##    really there is revealed for your squad once one of you gets eyes on it (line of sight, or flying
##    low over it on the drop): either the live marker, or a dim cross for an empty spot.
##  - Whatever is taken (a vault opened, a rare kin caught or killed) shows as spent for everyone who
##    knows the spot.
##
## Categories are a registry (CATS, plus register() for systems that bring their own): each has a
## name, an icon shape, a colour, how many candidates go live, and an optional spawner callback.
## Candidates come from the layout's "spawn_points" (tools/make_skyreach.py), or, on generated maps,
## are derived from the islands. To plug in boss lairs: list points under spawn_points.boss in the
## layout (or call add_candidate), and register a spawner with set_spawner("boss", fn) before
## Match calls roll(); fn(plan, cand) spawns the lair and returns its handle (anything; the plan asks
## taken_fn(cand) whether it's done, if one was registered with set_spawner).

const CATS := {
	"boss": {"name": "Boss lair", "shape": "skull", "col": Color("ff5a4a"), "announce": true, "pick": [1, 1], "order": 0},
	"vault": {"name": "Vault", "shape": "vault", "col": Color("f2c84a"), "announce": true, "pick": [2, 2], "order": 1},
	"rare_kin": {"name": "Rare kin", "shape": "paw", "col": Color("ff9be8"), "announce": false, "pick": [3, 3], "order": 2},
	"cache": {"name": "Item cache", "shape": "crate", "col": Color("8fd8ff"), "announce": false, "pick": [4, 4], "order": 3},
}
const REVEAL_R := 9.0          # flat distance at which a hunter on the ground just knows what's there
const DROP_REVEAL_R := 14.0    # ... and from the glider on the way down

var m: Match
var cats := {}                 # id -> def (CATS plus anything registered)
var cands: Array = []          # {id, cat, i, pos: Vector3, name, active, ref, taken, known: {team: true}}
var spawners := {}             # cat id -> Callable(plan, cand) -> handle
var takers := {}               # cat id -> Callable(cand) -> bool (is it spent?)
var rolled := false
var _t := 0.0

func _init(match_node: Match) -> void:
	m = match_node
	for k in CATS:
		cats[k] = (CATS[k] as Dictionary).duplicate()

## A new category of spawn (or new settings for one): {name, shape, col, announce, pick: [min, max]}.
func register(id: String, def: Dictionary) -> void:
	var d: Dictionary = cats.get(id, {"name": id.capitalize(), "shape": "star", "col": Color.WHITE, "announce": false, "pick": [1, 1], "order": 9})
	d.merge(def, true)
	cats[id] = d

func set_spawner(id: String, spawn_fn: Callable, taken_fn := Callable()) -> void:
	spawners[id] = spawn_fn
	if taken_fn.is_valid():
		takers[id] = taken_fn

func add_candidate(cat: String, pos: Vector3, name := "") -> Dictionary:
	var c := {"id": "%s:%d" % [cat, cands.size()], "cat": cat, "i": count_of(cat), "pos": pos, "name": name, "active": false, "ref": null, "taken": false, "known": {}}
	cands.append(c)
	return c

func count_of(cat: String) -> int:
	var n := 0
	for c in cands:
		if c["cat"] == cat: n += 1
	return n

func of(cat: String) -> Array:
	return cands.filter(func(c): return c["cat"] == cat)

func active_of(cat: String) -> Array:
	return cands.filter(func(c): return c["cat"] == cat and c["active"])

## Categories that have candidates on this map, in legend order.
func shown_cats() -> Array:
	var out: Array = []
	for k in cats:
		if count_of(k) > 0: out.append(k)
	out.sort_custom(func(a, b): return int(cats[a].get("order", 9)) < int(cats[b].get("order", 9)))
	return out

# ------------------------------------------------------------------ candidates
## Where the candidates are: the layout's own lists on an authored map, else derived from the islands.
func build(layout: Dictionary) -> void:
	cands.clear()
	var sp: Dictionary = layout.get("spawn_points", {})
	if not sp.is_empty():
		for cat in sp:
			var e = sp[cat]
			var pts: Array = e.get("points", []) if e is Dictionary else e
			if e is Dictionary and e.has("pick"):
				register(String(cat), {"pick": e["pick"]})
			for pt in pts:
				var q := _ground_near(Vector2(float(pt[0]) + 0.5, float(pt[1]) + 0.5))
				if q != Vector3.INF:
					add_candidate(String(cat), q, String(pt[2]) if (pt as Array).size() > 2 else "")
		return
	_derive()

## A generated map: candidates picked from the islands themselves, the same way for the same map.
func _derive() -> void:
	var w := m.world
	if w.islands.size() < 2:
		return
	var r := RandomNumberGenerator.new()
	var h := w.w * 7919 + w.islands.size() * 104729
	for isl in w.islands:
		h = (h * 31 + int((isl["c"] as Vector2).x * 13.0) + int((isl["c"] as Vector2).y * 17.0)) % 2147483647
	r.seed = h
	var order: Array = range(1, w.islands.size())
	order.sort_custom(func(a, b): return int(w.islands[a]["cells"].size()) > int(w.islands[b]["cells"].size()))
	var taken: Array = []
	# vaults: the middle island, and the biggest monster camps
	var heart := w.heart_spot if w.heart_spot != Vector3.INF else Vector3.INF
	var vault_isl: Array = [0] + order.filter(func(ii): return String(w.islands[ii]["role"]) in ["camp", "shrine"]).slice(0, 4)
	for ii in vault_isl:
		var p := _cell_on(ii, r, taken, 3)
		if p != Vector3.INF and (heart == Vector3.INF or p.distance_to(heart) > 3.0):
			add_candidate("vault", p, String(w.islands[ii].get("name", "")))
	# rare kin: the quieter islands (groves and nests first), one spot each
	var kin_isl: Array = order.filter(func(ii): return String(w.islands[ii]["role"]) in ["grove", "nest"]) + order.filter(func(ii): return not String(w.islands[ii]["role"]) in ["grove", "nest"])
	for ii in kin_isl.slice(0, 8):
		var p := _cell_on(ii, r, taken, 2)
		if p != Vector3.INF: add_candidate("rare_kin", p, String(w.islands[ii].get("name", "")))
	# caches: anywhere, two on each big island
	for ii in order.slice(0, 6):
		for _k in 2:
			var p := _cell_on(ii, r, taken, 2)
			if p != Vector3.INF: add_candidate("cache", p, String(w.islands[ii].get("name", "")))

func _cell_on(ii: int, r: RandomNumberGenerator, taken: Array, min_edge: int) -> Vector3:
	var w := m.world
	var cells: Array = w.islands[ii]["cells"]
	if cells.is_empty():
		return Vector3.INF
	for _t in 80:
		var c: Vector2i = cells[r.randi_range(0, cells.size() - 1)]
		var i := w.idx(c.x, c.y)
		if w.kind[i] != World.T_GROUND or w._near_block(c.x, c.y) or w.edge_dist(c.x, c.y, 4) < min_edge:
			continue
		var p := Vector3(c.x + 0.5, w.level[i] * World.LEVEL, c.y + 0.5)
		var near := false
		for q in taken:
			if (q as Vector3).distance_to(p) < 6.0: near = true; break
		for pd in w.pads:
			if (pd["pos"] as Vector3).distance_to(p) < 3.0: near = true; break
		if near:
			continue
		taken.append(p)
		return p
	return Vector3.INF

## The nearest open ground to an authored point (rocks and walls move it a step or two).
func _ground_near(at: Vector2) -> Vector3:
	var w := m.world
	var best := Vector3.INF; var bd := 1e9
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			var x := int(floor(at.x)) + dx; var z := int(floor(at.y)) + dz
			if not w.inb(x, z) or w.kind[w.idx(x, z)] != World.T_GROUND or w._near_block(x, z):
				continue
			var d := Vector2(dx, dz).length()
			if d < bd: bd = d; best = Vector3(x + 0.5, w.level[w.idx(x, z)] * World.LEVEL, z + 0.5)
	return best

# ------------------------------------------------------------------ the roll
## Which candidates are live this match. Seeded by the match seed (the same for everyone online),
## on its own generator so it never shifts the rest of the match's dice.
func roll(seed_val: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed_val * 92821 + 4099
	for cat in shown_cats():
		var pool: Array = of(cat)
		var pk: Array = cats[cat].get("pick", [1, 1])
		var n := clampi(r.randi_range(int(pk[0]), int(pk[1])), 0, pool.size())
		# shuffle with our own generator (Array.shuffle uses the global one)
		for i in range(pool.size() - 1, 0, -1):
			var j := r.randi_range(0, i)
			var t = pool[i]; pool[i] = pool[j]; pool[j] = t
		for i in n:
			pool[i]["active"] = true
	rolled = true

## Spawns what's live: vault chests, item caches, rare kin (host only, like all wild kin), and
## whatever a registered spawner brings.
func spawn_all() -> void:
	var wr := RandomNumberGenerator.new(); wr.seed = m.seed_val * 53 + 11
	var keys: Array = Data.weapon_ids()
	for c in cands:
		if not c["active"]:
			continue
		var p: Vector3 = c["pos"]
		match String(c["cat"]):
			"vault":
				c["ref"] = m.add_chest(p, 2)
			"cache":
				c["ref"] = m.add_chest(p, 1)
				# and a good weapon beside it, the same for everyone online
				var wk := String(keys[wr.randi() % keys.size()])
				var rar := clampi(Data.roll_rarity(wr, 1), 2, 4)
				var wp := m.world.free_spot_near(p + Vector3(1.4, 0, 0.4), [p], 0.6)
				wp.y = m.world.ground_at(wp.x, wp.z)
				m.spawn_weapon(wk, rar, wp, "sc%d" % int(c["i"]), false, -1, Loot.weapon(wk, rar, Loot.roll_element(wr, m.world.biome_at(p.x, p.z))))
			"rare_kin":
				if not m.net_on or m.is_host:
					c["ref"] = _spawn_rare(p, wr)
			_:
				var fn: Callable = spawners.get(String(c["cat"]), Callable())
				if fn.is_valid():
					c["ref"] = fn.call(self, c)

func _spawn_rare(p: Vector3, r: RandomNumberGenerator) -> Kin:
	var sp: String = Data.KIN.keys()[r.randi_range(0, Data.KIN.size() - 1)]
	var rec := Save.new_kin(sp)
	var lv: Array = m.T.get("kin_lvl", [1, 3])
	rec["level"] = int(lv[1]) + r.randi_range(2, 4)
	Evo.simulate(rec, r)
	rec["shimmer"] = r.randf() < 0.35          # a rare colour, much more often than out in the open
	var k := m.spawn_wild(rec, p)
	k.set_meta("rare", true)
	return k

# ------------------------------------------------------------------ what each squad knows
func tick(dt: float) -> void:
	_t -= dt
	if _t > 0.0:
		return
	_t = 0.25
	for c in cands:
		if not c["taken"] and c["active"]:
			c["taken"] = _is_taken(c)
	var teams := {}
	for h in m.hunters:
		if h.out or h.extracted or h.riding:
			continue
		teams[h.team] = true
	for c in cands:
		var known: Dictionary = c["known"]
		for t in teams:
			if known.has(t):
				continue
			if _team_sees(int(t), c["pos"]):
				known[t] = true
				if m.player and int(t) == m.player.team and m.hud and c["active"] and not c["taken"]:
					var def: Dictionary = cats.get(c["cat"], {})
					if not def.get("announce", false):
						m.hud.toast_small("%s spotted%s" % [String(def.get("name", "Something")), (" at " + String(c["name"])) if String(c["name"]) != "" else ""], def.get("col", Color.WHITE))

func _team_sees(team: int, p: Vector3) -> bool:
	for h in m.hunters:
		if h.team != team or h.out or h.extracted or h.riding:
			continue
		var d := Vector2(p.x - h.pos.x, p.z - h.pos.z).length()
		if d < (DROP_REVEAL_R if h.dropping else REVEAL_R):
			return true
	return m.sees(team, p + Vector3(0, 0.4, 0))

func _is_taken(c: Dictionary) -> bool:
	var fn: Callable = takers.get(String(c["cat"]), Callable())
	if fn.is_valid():
		return bool(fn.call(c))
	var ref = c["ref"]
	if ref == null:
		return false
	if ref is Dictionary:
		return bool((ref as Dictionary).get("open", false))
	if ref is Kin:
		var k := ref as Kin
		return not is_instance_valid(k) or k.dead or not k.is_wild()
	if ref is Object and not is_instance_valid(ref):
		return true
	return false

## How a candidate looks to a squad: "unknown" (a faint ?), "active", "empty" or "taken".
func state_for(c: Dictionary, team: int) -> String:
	var def: Dictionary = cats.get(c["cat"], {})
	var knows: bool = def.get("announce", false) or (c["known"] as Dictionary).has(team) or team < -1
	if not knows:
		return "unknown"
	if not c["active"]:
		return "empty"
	return "taken" if c["taken"] else "active"

## For tests and tools: which candidate ids are live.
func active_ids() -> Array:
	var out: Array = []
	for c in cands:
		if c["active"]: out.append(String(c["id"]))
	return out
