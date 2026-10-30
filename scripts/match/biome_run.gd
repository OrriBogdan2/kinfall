class_name BiomeRun
extends RefCounted
## Biome regions on an authored map, while a match runs: which monsters each region spawns (its own
## table, content/biomes/<id>.json), how rare each one is and which mutations it rolled, the region's
## traps, its loot leanings, and the snow/sparks/embers/spores/motes in the air.
##
## Kept apart from the monsters' own attack code: a monster is "dressed" after it spawns (name,
## colour, stats, size, a rarity ring and nameplate), and its mutations work by listening to the hits
## it lands (CombatBus) and to its death.

const RARITY := [
	{"id": "common", "name": "", "col": Color("d6d2c8"), "hp": 1.0, "dmg": 1.0, "scale": 1.0, "gems": 1.0, "mut": 0.15, "max_mut": 1},
	{"id": "uncommon", "name": "Uncommon", "col": Color("8fe0a0"), "hp": 1.25, "dmg": 1.1, "scale": 1.08, "gems": 1.5, "mut": 0.5, "max_mut": 1},
	{"id": "rare", "name": "Rare", "col": Color("6ab8ff"), "hp": 1.6, "dmg": 1.2, "scale": 1.18, "gems": 2.2, "mut": 0.85, "max_mut": 2},
	{"id": "elite", "name": "Elite", "col": Color("ffb64a"), "hp": 2.4, "dmg": 1.35, "scale": 1.32, "gems": 3.5, "mut": 1.0, "max_mut": 2},
]
const MUTATIONS := {
	"frozen": {"name": "Frozen", "col": Color("bff0ff"), "desc": "Its hits slow you, and it shatters when it dies."},
	"charged": {"name": "Charged", "col": Color("fff27a"), "desc": "Its hits arc to a second target."},
	"molten": {"name": "Molten", "col": Color("ff8a3a"), "desc": "Leaves burning ground behind it; its hits burn."},
	"toxic": {"name": "Toxic", "col": Color("9aff6a"), "desc": "Its hits poison, and it bursts into a poison cloud."},
	"void": {"name": "Void", "col": Color("b08aff"), "desc": "Blinks to its target."},
	"armored": {"name": "Armored", "col": Color("d8d2c8"), "desc": "Much tougher, a little slower."},
	"swift": {"name": "Swift", "col": Color("8fe3c8"), "desc": "Moves and attacks faster."},
}

var m: Node = null                  # the Match
var w: World = null
var defs := {}                      # biome id -> its data
var hazards: Array = []             # {kind, pos, node, t, phase, tele, ...}
var pending: Array = []             # delayed effects {t, fn}
var hz_ent: Ent = null              # stands in for "the environment" as a damage source (never credited)
var player_biome := ""
var rng := RandomNumberGenerator.new()

func _init(match_node: Node) -> void:
	m = match_node
	w = m.world
	rng.seed = int(m.seed_val) * 13 + 5
	for isl in w.islands:
		var b := String(isl.get("biome", ""))
		if b != "" and not defs.has(b):
			defs[b] = World.load_biome(b)
	hz_ent = Ent.new()
	hz_ent.team = -3
	hz_ent.dead = true        # so fields and hits never credit it with anything
	CombatBus.hit_landed.connect(_on_hit)

func active() -> bool:
	return not defs.is_empty()

func free_up() -> void:
	if CombatBus.hit_landed.is_connected(_on_hit):
		CombatBus.hit_landed.disconnect(_on_hit)
	if is_instance_valid(hz_ent):
		hz_ent.free()

func _biome(p: Vector3) -> Dictionary:
	var b := w.biome_at(p.x, p.z)
	return defs.get(b, {})

func _danger(p: Vector3) -> int:
	var ii := w.island_of(p.x, p.z)
	return int(w.islands[ii].get("danger", 0)) if ii >= 0 else 0

# ------------------------------------------------------------------ spawning
## The monsters for a camp, from its region's table: base monster kinds, weighted. Empty when the
## camp isn't in a biome (the match's own mix is used then).
func camp_comp(c: Dictionary) -> Array:
	var B := _biome(c["pos"])
	var mobs: Array = B.get("mobs", [])
	if mobs.is_empty():
		return []
	var n := 3
	match String(c.get("kind", "normal")):
		"heavy": n = 4
		"light": n = 2
	var out: Array = []
	if String(c.get("kind", "")) == "heavy":
		# a heavy camp always has its region's big one
		for e in mobs:
			if String(e["kind"]) in ["brute", "sentinel"]:
				out.append(String(e["kind"])); break
	while out.size() < n:
		out.append(String(_pick(mobs)["kind"]))
	return out

func _pick(entries: Array) -> Dictionary:
	var tot := 0.0
	for e in entries: tot += float(e.get("w", 1.0))
	var r := rng.randf() * tot
	for e in entries:
		r -= float(e.get("w", 1.0))
		if r <= 0.0: return e
	return entries[-1]

## Makes a freshly spawned monster belong to its region: the region's version of it (name, colour,
## stats), a rarity, and mutations from the region's list. Rarity climbs with the tier and with how
## dangerous the island is; rarer monsters roll more mutations.
func dress(mb: Mob) -> void:
	if mb == null or mb.mkind in ["warden", "glimmer"]:
		return
	var B := _biome(mb.pos)
	if B.is_empty():
		return
	var entry := {}
	for e in B.get("mobs", []):
		if String(e["kind"]) == mb.mkind:
			entry = e; break
	var md: Dictionary = mb.md.duplicate()
	if not entry.is_empty():
		md["name"] = String(entry.get("name", md["name"]))
		md["color"] = Color(String(entry.get("color", "ffffff")))
		md["speed"] = float(md["speed"]) * float(entry.get("speed", 1.0))
		mb.max_hp *= float(entry.get("hp", 1.0))
	# rarity: shift weight from common toward the top with the tier and the island's danger
	var lift := float(int(m.tier) + _danger(mb.pos)) * float(B.get("danger_mult", 1.0))
	var wts := [60.0 - lift * 12.0, 25.0 + lift * 4.0, 11.0 + lift * 5.0, 4.0 + lift * 3.0]
	var ri := 0
	var roll: float = rng.randf() * (float(wts[0]) + float(wts[1]) + float(wts[2]) + float(wts[3]))
	for i in 4:
		roll -= maxf(1.0, wts[i])
		if roll <= 0.0: ri = i; break
	var R: Dictionary = RARITY[ri]
	# mutations
	var muts: Array = []
	var pool: Dictionary = B.get("mutations", {})
	var mm := float(B.get("mutation_mult", 1.0))
	if not pool.is_empty():
		var want := 0
		if rng.randf() < float(R["mut"]) * mm: want = 1
		if want == 1 and int(R["max_mut"]) > 1 and rng.randf() < (0.35 if ri == 2 else 0.75) * mm: want = 2
		var keys: Array = pool.keys()
		for _k in want:
			var tot := 0.0
			for k in keys: if not muts.has(k): tot += float(pool[k])
			var r := rng.randf() * tot
			for k in keys:
				if muts.has(k): continue
				r -= float(pool[k])
				if r <= 0.0: muts.append(k); break
	if muts.has("armored"):
		mb.max_hp *= 1.5; md["speed"] = float(md["speed"]) * 0.85
	if muts.has("swift"):
		md["speed"] = float(md["speed"]) * 1.3; md["cd"] = float(md["cd"]) * 0.8
	mb.max_hp *= float(R["hp"])
	mb.hp = mb.max_hp
	mb.dmg_mult *= float(R["dmg"])
	md["gems"] = int(round(float(md["gems"]) * float(R["gems"])))
	var parts: Array = []
	if String(R["name"]) != "": parts.append(String(R["name"]))
	for k in muts: parts.append(String(MUTATIONS[k]["name"]))
	parts.append(String(md["name"]))
	md["name"] = " ".join(parts)
	mb.md = md
	mb.set_meta("rarity", ri)
	mb.set_meta("muts", muts)
	mb.set_meta("mut_t", rng.randf_range(2.0, 4.0))
	_recolor(mb, Color(md["color"]))
	var s := float(R["scale"])
	if s != 1.0:
		mb.scale = Vector3.ONE * s
		mb.r *= s
	_decorate_mob(mb, R, muts)

## Repaints the monster's body in its region's colour (its darker parts follow).
func _recolor(mb: Mob, col: Color) -> void:
	recolor_mats(mb.mats, mb.mkind, col)

## The same for any monster model's materials (also used by tooling that builds bare models).
static func recolor_mats(mats: Array, mkind: String, col: Color) -> void:
	var base: Color = Data.MOBS[mkind]["color"]
	for mat in mats:
		var sm := mat as ShaderMaterial
		if sm == null: continue
		var a = sm.get_shader_parameter("albedo")
		if typeof(a) != TYPE_COLOR: continue
		var c: Color = a
		if _close(c, base): sm.set_shader_parameter("albedo", col)
		elif _close(c, base.darkened(0.5)): sm.set_shader_parameter("albedo", col.darkened(0.5))

static func _close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) < 0.04

## A ring in the rarity's colour under anything above common, a nameplate, and a little aura per
## mutation, so you can read a monster's threat before you engage.
func _decorate_mob(mb: Mob, R: Dictionary, muts: Array) -> void:
	var ri := int(mb.get_meta("rarity", 0))
	if ri > 0:
		var ring := MeshInstance3D.new()
		ring.mesh = Models.flat_quad(mb.r * 2.0 / maxf(0.01, mb.scale.x) + 0.9)
		ring.material_override = Models.ring_mat(Color(R["col"], 0.9), 0.1)
		ring.position.y = 0.05
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mb.add_child(ring)
	if ri > 0 or not muts.is_empty():
		var lbl := Label3D.new()
		lbl.text = String(mb.md["name"])
		lbl.font = UI.big; lbl.font_size = 30; lbl.pixel_size = 0.009; lbl.outline_size = 9
		lbl.modulate = R["col"] if ri > 0 else Color(MUTATIONS[muts[0]]["col"])
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED; lbl.no_depth_test = true
		lbl.position.y = 1.5 + Data.MOBS[mb.mkind]["r"] * 1.2
		lbl.name = "Nameplate"
		mb.add_child(lbl)
	for k in muts:
		if k in ["armored", "swift"]: continue
		var p := CPUParticles3D.new()
		p.amount = 10; p.lifetime = 1.0; p.preprocess = 1.0
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE; p.emission_sphere_radius = 0.6
		p.direction = Vector3.UP; p.spread = 30.0; p.initial_velocity_min = 0.4; p.initial_velocity_max = 1.2
		p.gravity = Vector3.ZERO
		p.mesh = Models.sphere(0.05, 4)
		p.material_override = Models.glow_mat(Color(MUTATIONS[k]["col"], 0.85))
		p.position.y = 0.6
		mb.add_child(p)
	if ri == 3:
		# elites wear a little crown of light
		var crown := MeshInstance3D.new()
		var tm := TorusMesh.new(); tm.inner_radius = 0.22; tm.outer_radius = 0.3
		crown.mesh = tm
		crown.material_override = Models.glow_mat(Color("ffd27a"))
		crown.position.y = 1.15 + Data.MOBS[mb.mkind]["r"] * 0.8
		mb.add_child(crown)

# ------------------------------------------------------------------ mutations in play
func _muts(e) -> Array:
	return (e as Node).get_meta("muts", []) if e is Mob else []

func _on_hit(attacker: Node, target: Node, amount: float, tags: Array) -> void:
	if not (attacker is Mob) or not (target is Ent) or tags.has("mut"):
		return
	var muts := _muts(attacker)
	if muts.is_empty() or (target as Ent).dead:
		return
	var t := target as Ent
	if muts.has("frozen"):
		t.slow_t = maxf(t.slow_t, 1.4)
		m.fx.burst(t.pos + Vector3(0, 0.8, 0), Color("bff0ff"), 8, 2.5, 0.4, 2.0)
	if muts.has("molten") or muts.has("toxic"):
		t.burn_t = maxf(t.burn_t, 2.5); t.burn_dps = maxf(t.burn_dps, 3.0)
	if muts.has("charged"):
		# the hit jumps to the nearest other foe within reach
		var best: Ent = null; var bd := 4.5
		for f in m.foes_of((attacker as Ent).team):
			if f == t: continue
			var d: float = f.flat_dist(t)
			if d < bd: bd = d; best = f
		if best:
			_zap(t.pos + Vector3(0, 0.8, 0), best.pos + Vector3(0, 0.8, 0))
			best.hurt(amount * 0.4, attacker as Ent, {"src": "mob", "tags": ["mut"], "stun": 0.15})

func _zap(a: Vector3, b: Vector3) -> void:
	var n := 6
	for i in n + 1:
		var p := a.lerp(b, float(i) / n) + Vector3(randf_range(-0.2, 0.2), randf_range(-0.2, 0.2), randf_range(-0.2, 0.2))
		m.fx.burst(p, Color("fff27a"), 2, 1.0, 0.18, 0.0, 0.7)
	m.sfx("zap", b, -6.0, 1.2)

func on_mob_dead(mb: Mob) -> void:
	var muts := _muts(mb)
	if muts.is_empty():
		return
	var at := mb.pos
	if muts.has("frozen"):
		# shatters: a marked circle, then shards
		var tele: Node3D = m.fx.telegraph_circle(at, 2.3, Color("bff0ff"))
		_later(0.6, func():
			m.fx.end_telegraph(tele)
			m.fx.burst(at + Vector3(0, 0.6, 0), Color("dff8ff"), 26, 6.0, 0.5, 6.0, 1.2)
			m.sfx("crit", at, -4.0, 1.4)
			for f in m.foes_of(-2):
				if Vector2(f.pos.x - at.x, f.pos.z - at.z).length() < 2.3 + f.r and absf(f.pos.y - at.y) < 1.6:
					f.hurt(9.0 * float(m.T.get("mob", 1.0)), null, {"src": "mob", "tags": ["mut"], "slow": 1.8})
		, tele)
	if muts.has("toxic"):
		m.fields.add(hz_ent, at, {"radius": 2.5, "color": "#9aff6a", "time": 4.0, "every": 0.5, "dmg": 3.0, "slow": 0.6}, {"slot": "toxic", "ability": "toxic"}, float(m.T.get("mob", 1.0)))
	if muts.has("molten"):
		m.fields.add(hz_ent, at, {"radius": 1.8, "color": "#ff7a3a", "time": 3.0, "every": 0.5, "dmg": 3.0, "burn": 2.0}, {"slot": "molten", "ability": "molten"}, float(m.T.get("mob", 1.0)))
	if muts.has("charged"):
		m.fx.ring(at, 2.0, Color("fff27a"), 0.3)
		for f in m.foes_of(-2):
			if Vector2(f.pos.x - at.x, f.pos.z - at.z).length() < 2.0 + f.r:
				f.hurt(5.0, null, {"src": "mob", "tags": ["mut"], "stun": 0.3})

func _later(t: float, fn: Callable, tele: Node3D = null) -> void:
	pending.append({"t": t, "fn": fn, "tele": tele, "t0": t})

func tick(dt: float) -> void:
	for p in pending.duplicate():
		p["t"] = float(p["t"]) - dt
		if p["tele"] and is_instance_valid(p["tele"]):
			m.fx.telegraph_progress(p["tele"], 1.0 - float(p["t"]) / float(p["t0"]))
		if float(p["t"]) <= 0.0:
			pending.erase(p)
			(p["fn"] as Callable).call()
	for mb in m.mobs:
		if mb.dead or mb.remote: continue
		var muts := _muts(mb)
		if muts.is_empty(): continue
		var mt := float(mb.get_meta("mut_t", 3.0)) - dt
		if mt > 0.0:
			mb.set_meta("mut_t", mt); continue
		mb.set_meta("mut_t", rng.randf_range(2.6, 3.6))
		if muts.has("molten") and mb.st in ["chase", "windup", "recover"]:
			m.fields.add(hz_ent, mb.pos, {"radius": 1.1, "color": "#ff7a3a", "time": 3.0, "every": 0.5, "dmg": 2.0, "burn": 1.5}, {"slot": "molten", "ability": "molten"}, float(m.T.get("mob", 1.0)))
		if muts.has("void") and mb.tgt and mb.st == "chase" and mb.flat_dist(mb.tgt) > 3.5:
			_blink(mb)
	_tick_hazards(dt)
	_tick_region_banner()

## A void monster marks where it's going, then blinks there.
func _blink(mb: Mob) -> void:
	var t: Ent = mb.tgt
	var d := Vector2(mb.pos.x - t.pos.x, mb.pos.z - t.pos.z).normalized()
	var to := Vector3(t.pos.x + d.x * 2.2, 0, t.pos.z + d.y * 2.2)
	if w.is_void(to.x, to.z) or w.is_block(to.x, to.z) or absf(w.ground_at(to.x, to.z) - mb.pos.y) > 1.0:
		return
	to.y = w.ground_at(to.x, to.z)
	var tele: Node3D = m.fx.telegraph_circle(to, 1.0, Color("b08aff"))
	_later(0.5, func():
		m.fx.end_telegraph(tele)
		if mb.dead: return
		m.fx.burst(mb.pos + Vector3(0, 0.6, 0), Color("b08aff"), 14, 3.0, 0.4, 0.0)
		mb.teleport(to)
		m.fx.burst(to + Vector3(0, 0.6, 0), Color("b08aff"), 14, 3.0, 0.4, 0.0)
		m.sfx("cloak", to, -6.0, 1.3)
	, tele)

# ------------------------------------------------------------------ traps and hazards
## Places each region's traps on its islands, away from exits, points of interest and the edges.
func place_hazards() -> void:
	var taken: Array = []
	for p in w.portal_spots: taken.append(p)
	for c in w.chest_spots: taken.append(c["pos"])
	for c in w.camp_spots: taken.append(c["pos"])
	for ii in w.islands.size():
		if w.islands[ii].get("perch", false):
			continue      # the perches' danger is the drop, not traps
		var B: Dictionary = defs.get(String(w.islands[ii].get("biome", "")), {})
		for H in B.get("hazards", []):
			var n := int(H.get("per_island", 1)) + (1 if int(w.islands[ii].get("danger", 0)) >= 2 else 0)
			for _k in n:
				var p := _hazard_spot(ii, taken)
				if p == Vector3.INF: continue
				taken.append(p)
				_add_hazard(String(H["kind"]), p)

func _hazard_spot(ii: int, taken: Array) -> Vector3:
	var cells: Array = w.islands[ii]["cells"]
	for _t in 60:
		var c: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
		var i := w.idx(c.x, c.y)
		if w.kind[i] != World.T_GROUND or w.edge_dist(c.x, c.y, 3) < 3 or w.stairs.has(i):
			continue
		var p := Vector3(c.x + 0.5, w.level[i] * World.LEVEL, c.y + 0.5)
		var ok := true
		for q in taken:
			if Vector2((q as Vector3).x - p.x, (q as Vector3).z - p.z).length() < 6.0:
				ok = false; break
		if ok: return p
	return Vector3.INF

func _add_hazard(kind: String, p: Vector3) -> void:
	var n := Node3D.new()
	m.add_child(n)
	n.global_position = p
	var hz := {"kind": kind, "pos": p, "node": n, "t": rng.randf_range(2.0, 6.0), "phase": "idle", "tele": null}
	match kind:
		"ice_patch":
			var r := rng.randf_range(2.2, 3.4)
			hz["r"] = r
			var disc := MeshInstance3D.new()
			disc.mesh = Models.cyl(r, r, 0.03, 28)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.82, 0.94, 1.0, 0.72); mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.metallic = 0.2; mat.roughness = 0.05
			disc.material_override = mat
			disc.position.y = 0.03
			disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			n.add_child(disc)
			var edge := MeshInstance3D.new(); edge.mesh = Models.flat_quad(r * 2.0)
			edge.material_override = Models.ring_mat(Color("e8f8ff"), 0.05); edge.position.y = 0.05
			n.add_child(edge)
		"lightning_rod":
			Models.part(n, Models.cyl(0.06, 0.1, 3.2, 8), Models.toon(Color("6a6e80")), Vector3(0, 1.6, 0))
			Models.part(n, Models.cyl(0.35, 0.45, 0.25, 10), Models.toon(Color("3a3c4a")), Vector3(0, 0.12, 0))
			var tip := Models.part(n, Models.sphere(0.18, 10), Models.glow_mat(Color("fff27a")), Vector3(0, 3.3, 0))
			tip.name = "Tip"
		"lava_vent":
			Models.part(n, Models.cyl(0.5, 1.1, 0.55, 10), Models.toon(Color("3a2420")), Vector3(0, 0.27, 0))
			var core := Models.part(n, Models.cyl(0.42, 0.42, 0.05, 10), Models.glow_mat(Color("ff7a2a")), Vector3(0, 0.56, 0))
			core.name = "Core"
		"spore_pod":
			var pod := Models.part(n, Models.sphere(0.55, 12), Models.toon(Color("c06ad0")), Vector3(0, 0.45, 0), Vector3(1.0, 0.85, 1.0))
			pod.name = "Pod"
			for i in 5:
				var a := TAU * i / 5.0
				Models.part(n, Models.sphere(0.12, 6), Models.toon(Color("ffd0f0"), false, 0.6), Vector3(cos(a) * 0.4, 0.6, sin(a) * 0.4))
		"void_rift":
			var disc2 := MeshInstance3D.new(); disc2.mesh = Models.cyl(1.0, 1.0, 0.02, 24)
			disc2.material_override = Models.glow_mat(Color(0.2, 0.05, 0.35, 0.9))
			disc2.position.y = 0.04
			n.add_child(disc2)
			var rim := MeshInstance3D.new(); rim.mesh = Models.flat_quad(2.4)
			rim.material_override = Models.ring_mat(Color("b08aff"), 0.08); rim.position.y = 0.06
			rim.name = "Rim"
			n.add_child(rim)
	hazards.append(hz)

## How much grip the ground has at p (1 normal, low on ice), for the hunter's footing.
func grip(p: Vector3) -> float:
	for hz in hazards:
		if hz["kind"] == "ice_patch" and Vector2(p.x - hz["pos"].x, p.z - hz["pos"].z).length() < float(hz["r"]) and absf(p.y - hz["pos"].y) < 0.3:
			return 0.12
	return 1.0

func _near_hunter(p: Vector3, d: float) -> Hunter:
	var best: Hunter = null; var bd := d
	for h in m.hunters:
		if h.out or h.downed or h.extracted: continue
		var dd := Vector2(h.pos.x - p.x, h.pos.z - p.z).length()
		if dd < bd: bd = dd; best = h
	return best

func _hit_area(at: Vector3, r: float, dmg: float, o: Dictionary) -> void:
	for f in m.foes_of(-3):
		if Vector2(f.pos.x - at.x, f.pos.z - at.z).length() < r + f.r and absf(f.pos.y - at.y) < 1.8:
			var oo := o.duplicate(); oo["tags"] = ["mut", "hazard"]; oo["src"] = "hazard"
			f.hurt(dmg * float(m.T.get("mob", 1.0)), null, oo)

func _tick_hazards(dt: float) -> void:
	for hz in hazards:
		var n: Node3D = hz["node"]
		var p: Vector3 = hz["pos"]
		match String(hz["kind"]):
			"lightning_rod":
				hz["t"] = float(hz["t"]) - dt
				if hz["phase"] == "idle" and float(hz["t"]) <= 0.0:
					# pick a spot near the rod (near a hunter if one's close), mark it, then strike
					var h := _near_hunter(p, 9.0)
					var at := p + Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3))
					if h: at = Vector3(h.pos.x, h.pos.y, h.pos.z) + Vector3(rng.randf_range(-0.8, 0.8), 0, rng.randf_range(-0.8, 0.8))
					if w.is_void(at.x, at.z): at = p
					at.y = w.ground_at(at.x, at.z)
					hz["at"] = at
					hz["tele"] = m.fx.telegraph_circle(at, 1.8, Color("fff27a"))
					hz["phase"] = "warn"; hz["t"] = 1.2; hz["t0"] = 1.2
					m.sfx("warn", at, -14.0, 1.6)
				elif hz["phase"] == "warn":
					m.fx.telegraph_progress(hz["tele"], 1.0 - float(hz["t"]) / float(hz["t0"]))
					if float(hz["t"]) <= 0.0:
						m.fx.end_telegraph(hz["tele"]); hz["tele"] = null
						var at2: Vector3 = hz["at"]
						_zap(p + Vector3(0, 3.3, 0), at2 + Vector3(0, 0.3, 0))
						m.fx.burst(at2 + Vector3(0, 0.4, 0), Color("fff9c0"), 30, 7.0, 0.35, 2.0, 1.2)
						m.sfx("boom", at2, -4.0, 1.5)
						m.shake(0.35, at2)
						_hit_area(at2, 1.8, 14.0, {"stun": 0.4})
						hz["phase"] = "idle"; hz["t"] = rng.randf_range(5.0, 8.0)
			"lava_vent":
				hz["t"] = float(hz["t"]) - dt
				var core := n.get_node_or_null("Core") as MeshInstance3D
				if hz["phase"] == "idle" and float(hz["t"]) <= 0.0:
					hz["tele"] = m.fx.telegraph_circle(p, 2.2, Color("ff8a3a"))
					hz["phase"] = "warn"; hz["t"] = 1.1; hz["t0"] = 1.1
					m.sfx("warn", p, -14.0, 0.7)
				elif hz["phase"] == "warn":
					m.fx.telegraph_progress(hz["tele"], 1.0 - float(hz["t"]) / float(hz["t0"]))
					if core: core.scale = Vector3.ONE * (1.0 + 0.4 * sin(m.time * 20.0))
					if float(hz["t"]) <= 0.0:
						m.fx.end_telegraph(hz["tele"]); hz["tele"] = null
						m.fx.burst(p + Vector3(0, 0.6, 0), Color("ff9a3a"), 34, 7.5, 0.7, 9.0, 1.4)
						m.sfx("boom", p, -4.0, 0.8)
						_hit_area(p, 2.2, 10.0, {"burn": 3.0, "kb": Vector2.ZERO, "lift": 5.0})
						m.fields.add(hz_ent, p, {"radius": 1.6, "color": "#ff7a3a", "time": 2.5, "every": 0.5, "dmg": 2.0, "burn": 2.0}, {"slot": "lava", "ability": "lava"}, float(m.T.get("mob", 1.0)))
						if core: core.scale = Vector3.ONE
						hz["phase"] = "idle"; hz["t"] = rng.randf_range(5.0, 8.0)
			"spore_pod":
				var pod := n.get_node_or_null("Pod") as Node3D
				if hz["phase"] == "idle":
					if _near_hunter(p, 2.6):
						hz["tele"] = m.fx.telegraph_circle(p, 2.6, Color("c06ad0"))
						hz["phase"] = "warn"; hz["t"] = 0.9; hz["t0"] = 0.9
						m.sfx("warn", p, -16.0, 1.3)
				elif hz["phase"] == "warn":
					hz["t"] = float(hz["t"]) - dt
					var k := 1.0 - float(hz["t"]) / float(hz["t0"])
					m.fx.telegraph_progress(hz["tele"], k)
					if pod: pod.scale = Vector3(1.0, 0.85, 1.0) * (1.0 + k * 0.5)
					if float(hz["t"]) <= 0.0:
						m.fx.end_telegraph(hz["tele"]); hz["tele"] = null
						m.fx.burst(p + Vector3(0, 0.6, 0), Color("d88aff"), 28, 4.0, 0.8, -1.0, 1.4)
						m.sfx("thump", p, -4.0, 0.7)
						m.fields.add(hz_ent, p, {"radius": 2.6, "color": "#b06ad0", "time": 4.0, "every": 0.5, "dmg": 3.0, "slow": 0.6}, {"slot": "spore", "ability": "spore"}, float(m.T.get("mob", 1.0)))
						if pod: pod.visible = false
						hz["phase"] = "spent"; hz["t"] = 14.0
				else:
					hz["t"] = float(hz["t"]) - dt
					if float(hz["t"]) <= 0.0:
						if pod: pod.visible = true; pod.scale = Vector3(1.0, 0.85, 1.0)
						hz["phase"] = "idle"
			"void_rift":
				hz["t"] = float(hz["t"]) - dt
				var rim := n.get_node_or_null("Rim") as Node3D
				if rim: rim.rotation.y += dt * (4.0 if hz["phase"] == "pull" else 1.0)
				if hz["phase"] == "idle" and float(hz["t"]) <= 0.0:
					hz["tele"] = m.fx.telegraph_circle(p, 4.5, Color("b08aff"))
					hz["phase"] = "warn"; hz["t"] = 1.2; hz["t0"] = 1.2
					m.sfx("warn", p, -14.0, 0.6)
				elif hz["phase"] == "warn":
					m.fx.telegraph_progress(hz["tele"], 1.0 - float(hz["t"]) / float(hz["t0"]))
					if float(hz["t"]) <= 0.0:
						m.fx.end_telegraph(hz["tele"]); hz["tele"] = null
						hz["phase"] = "pull"; hz["t"] = 1.4; hz["tick"] = 0.0
						m.sfx("cloak", p, -2.0, 0.6)
				elif hz["phase"] == "pull":
					hz["tick"] = float(hz["tick"]) - dt
					if float(hz["tick"]) <= 0.0:
						hz["tick"] = 0.25
						m.fx.burst(p + Vector3(0, 0.3, 0), Color("b08aff"), 8, -3.0, 0.4, 0.0, 1.0)
						for f in m.foes_of(-3):
							var to := Vector2(p.x - f.pos.x, p.z - f.pos.z)
							if to.length() < 4.5 + f.r and absf(f.pos.y - p.y) < 2.0:
								if to.length() > 0.6: f.impulse(to.normalized() * 3.2, 0.0)
								if to.length() < 1.3: f.hurt(3.0 * float(m.T.get("mob", 1.0)), null, {"src": "hazard", "tags": ["mut", "hazard"]})
					if float(hz["t"]) <= 0.0:
						hz["phase"] = "idle"; hz["t"] = rng.randf_range(7.0, 10.0)

# ------------------------------------------------------------------ loot
## A weapon for a chest at p: the region leans toward its own weapons.
func weapon_at(p: Vector3, keys: Array) -> String:
	var L: Dictionary = _biome(p).get("loot", {})
	var wts: Dictionary = L.get("weapons", {})
	if wts.is_empty():
		return String(keys[randi() % keys.size()])
	var tot := 0.0
	for k in wts: if keys.has(k): tot += float(wts[k])
	var r := rng.randf() * tot
	for k in wts:
		if not keys.has(k): continue
		r -= float(wts[k])
		if r <= 0.0: return String(k)
	return String(keys[randi() % keys.size()])

## Extra rarity steps for loot in this region (the Gloom pays better), plus the island's danger.
func rarity_bonus_at(p: Vector3) -> int:
	return int(_biome(p).get("loot", {}).get("rarity_bonus", 0)) + (1 if _danger(p) >= 2 else 0)

## The region's gear leanings (tags), for glove/gear tables that read them.
func gear_tags_at(p: Vector3) -> Array:
	return _biome(p).get("loot", {}).get("gear", [])

# ------------------------------------------------------------------ the air and the banner
## Snow, sparks, embers, spores or motes drifting over each region's islands.
func decorate() -> void:
	for ii in w.islands.size():
		var B: Dictionary = defs.get(String(w.islands[ii].get("biome", "")), {})
		if B.is_empty(): continue
		var c: Vector2 = w.islands[ii]["c"]
		var r := float(w.islands[ii]["r"]) * 1.1
		var p := CPUParticles3D.new()
		p.amount = int(clampf(r * 4.0, 20, 70)); p.lifetime = 5.0; p.preprocess = 5.0
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX; p.emission_box_extents = Vector3(r, 2.5, r)
		p.mesh = Models.sphere(0.06, 4)
		var col := Color(String(B.get("tint", "ffffff")))
		match String(B.get("particles", "")):
			"snow":
				p.direction = Vector3.DOWN; p.gravity = Vector3(0.3, -0.6, 0); p.initial_velocity_min = 0.3; p.initial_velocity_max = 0.8
				col = Color(1, 1, 1, 0.9)
			"sparks":
				p.direction = Vector3.UP; p.gravity = Vector3.ZERO; p.initial_velocity_min = 0.1; p.initial_velocity_max = 0.5; p.lifetime = 1.6
				p.scale_amount_min = 0.5; p.scale_amount_max = 1.2
			"embers":
				p.direction = Vector3.UP; p.gravity = Vector3(0, 0.4, 0); p.initial_velocity_min = 0.4; p.initial_velocity_max = 1.0
			"spores":
				p.direction = Vector3.UP; p.gravity = Vector3(0, 0.05, 0); p.initial_velocity_min = 0.05; p.initial_velocity_max = 0.25; p.spread = 180.0
			"motes":
				p.direction = Vector3.UP; p.gravity = Vector3(0, 0.15, 0); p.initial_velocity_min = 0.1; p.initial_velocity_max = 0.3; p.spread = 180.0
			_:
				p.direction = Vector3.UP; p.gravity = Vector3(0, 0.05, 0); p.initial_velocity_min = 0.05; p.initial_velocity_max = 0.2; p.spread = 180.0
				col = Color(col, 0.6)
		p.material_override = Models.glow_mat(Color(col, minf(col.a, 0.8)))
		m.add_child(p)
		p.global_position = Vector3(c.x, 3.5, c.y)

## Says which region you've walked or glided into, and what it has in store.
func _tick_region_banner() -> void:
	var P = m.player
	if P == null or P.out or P.dropping or P.riding or m.hud == null:
		return
	var b := w.biome_at(P.pos.x, P.pos.z)
	if b == "" or b == player_biome:
		return
	player_biome = b
	var B: Dictionary = defs.get(b, {})
	m.hud.toast("%s  ·  %s" % [String(B.get("name", b)), String(B.get("blurb", ""))], Color(String(B.get("tint", "ffffff"))))
