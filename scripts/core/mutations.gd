class_name Mutations
## Rare kin mutations: Giant, Tiny, Piebald, Melanistic, Albino, Glowing, Twin-tail, Crystal and
## Starmarked (the shimmer stays the shiny and lives on its own flag). Each is a row in
## content/mutations/mutations.json with its odds, look and a small perk; a kin's record keeps the
## ones it has in rec["mutations"] (Evo's level-up body parts are a different thing, in rec["muts"]).
##
## Wild kin roll them at base odds (more in harder tiers and at rare spawn points), eggs roll them
## too, and a parent's mutation has a good chance of passing on: 35% from one parent, 60% if both.

const PATH := "res://content/mutations/mutations.json"
const MULT_MIN := 0.85
const MULT_MAX := 1.15
const OWNER_MAX := {"armor": 10.0, "sight": 0.15}

## Shimmers (the shinies) are Shiny's: 1 in 1024 in the wild and from an egg, more at rare spawn
## points, in the Hollow and from shimmering parents. These stay for older callers.
const SHIMMER_WILD := Shiny.WILD
const SHIMMER_EGG := 1.0 / 1024.0

## How much more often wild kin are mutated in each tier, and at a rare spawn point.
const TIER_MULT := [1.0, 1.5, 2.25, 3.0]
const RARE_SPOT_MULT := 5.0

static var _rows: Array = []
static var _by_id: Dictionary = {}
static var _inherit := [0.35, 0.6]

static func _load() -> void:
	if not _rows.is_empty():
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_warning("Mutations: no %s" % PATH)
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Mutations: %s isn't a JSON object" % PATH)
		return
	_inherit = [float(parsed.get("inherit_one", 0.35)), float(parsed.get("inherit_both", 0.6))]
	for r in parsed.get("mutations", []):
		if typeof(r) != TYPE_DICTIONARY or String(r.get("id", "")) == "":
			continue
		var row: Dictionary = r
		row["rarity"] = maxf(2.0, float(row.get("rarity", 100)))
		row["col"] = Color(String(row.get("col", "#ffffff")))
		_rows.append(row)
		_by_id[String(row["id"])] = row

static func all() -> Array:
	_load()
	return _rows

static func ids() -> Array:
	_load()
	return _rows.map(func(r): return String(r["id"]))

static func info(id: String) -> Dictionary:
	_load()
	return _by_id.get(id, {})

static func name_of(id: String) -> String:
	return String(info(id).get("name", id.capitalize()))

static func col_of(id: String) -> Color:
	return info(id).get("col", Color.WHITE)

static func inherit_odds() -> Array:
	_load()
	return _inherit

## The mutations a record has (only known ones, oldest records have none).
static func of(rec: Dictionary) -> Array:
	_load()
	var out: Array = []
	for m in rec.get("mutations", []):
		if _by_id.has(String(m)) and not out.has(String(m)):
			out.append(String(m))
	return out

static func has(rec: Dictionary, id: String) -> bool:
	return of(rec).has(id)

## A shimmer or any rare mutation.
static func special(rec: Dictionary) -> bool:
	return rec.get("shimmer", false) or not of(rec).is_empty()

## How rare a kin is, for sorting: the shimmer counts as 1 in 1024, each mutation by its odds.
static func rarity_score(rec: Dictionary) -> float:
	var s := 1024.0 if rec.get("shimmer", false) else 0.0
	for id in of(rec):
		s += float(info(id)["rarity"])
	return s

## Keeps at most one mutation from each group (one size, one palette).
static func _tidy(list: Array, rng: RandomNumberGenerator) -> Array:
	var groups := {}
	var shuffled := list.duplicate()
	for i in range(shuffled.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = shuffled[i]; shuffled[i] = shuffled[j]; shuffled[j] = t
	var keep: Array = []
	for id in shuffled:
		var g := String(info(id).get("group", ""))
		if g != "":
			if groups.has(g): continue
			groups[g] = true
		keep.append(id)
	# a stable order (the table's), so the same kin always lists them the same way
	var out: Array = []
	for r in _rows:
		if keep.has(String(r["id"])): out.append(String(r["id"]))
	return out

## A fresh roll at base odds times mult (wild kin, eggs). Usually empty.
static func roll(rng: RandomNumberGenerator, mult := 1.0) -> Array:
	_load()
	var got: Array = []
	for r in _rows:
		if rng.randf() < mult / float(r["rarity"]):
			got.append(String(r["id"]))
	return _tidy(got, rng)

## What an egg gets from its parents: each parent's mutation passes on 35% of the time (60% when
## both parents have it), plus the egg's own roll at base odds.
static func inherit(a: Dictionary, b: Dictionary, rng: RandomNumberGenerator) -> Array:
	_load()
	var ma := of(a)
	var mb := of(b)
	var got: Array = []
	for r in _rows:
		var id := String(r["id"])
		var n := (1 if ma.has(id) else 0) + (1 if mb.has(id) else 0)
		var p := 1.0 / float(r["rarity"])
		if n == 1: p = maxf(p, float(_inherit[0]))
		elif n == 2: p = maxf(p, float(_inherit[1]))
		if rng.randf() < p:
			got.append(id)
	return _tidy(got, rng)

static func shimmer_breed_chance(a: Dictionary, b: Dictionary) -> float:
	return Shiny.egg_chance(a, b)

## A wild kin's roll for where it was found: the tier and whether it's a rare spawn point.
static func roll_wild(rec: Dictionary, rng: RandomNumberGenerator, tier := 0, rare_spot := false) -> void:
	var m := float(TIER_MULT[clampi(tier, 0, TIER_MULT.size() - 1)]) * (RARE_SPOT_MULT if rare_spot else 1.0)
	var got := roll(rng, m)
	if got.is_empty(): rec.erase("mutations")
	else: rec["mutations"] = got

# ------------------------------------------------------------------ perks
## The kin's own stat multipliers from its mutations: {"hp", "dmg", "speed", "cd"} (Evo.mods folds them in).
static func mods(rec: Dictionary) -> Dictionary:
	var out := {"hp": 1.0, "dmg": 1.0, "speed": 1.0, "cd": 1.0}
	for id in of(rec):
		var pk: Dictionary = info(id).get("perk", {})
		for k in out:
			if pk.has(k):
				out[k] = float(out[k]) * clampf(float(pk[k]), MULT_MIN, MULT_MAX)
	for k in out:
		out[k] = clampf(float(out[k]), MULT_MIN * MULT_MIN, MULT_MAX * MULT_MAX)
	return out

## A flat bonus for the hunter carrying this kin ("armor", "sight"), 0 if none.
static func owner_stat(rec: Dictionary, k: String) -> float:
	var t := 0.0
	for id in of(rec):
		t += float((info(id).get("owner", {}) as Dictionary).get(k, 0.0))
	return clampf(t, 0.0, float(OWNER_MAX.get(k, 0.0)))

## The perk in words, e.g. "+12% health, -7% speed".
static func perk_text(id: String) -> String:
	var r := info(id)
	var parts: Array = []
	var names := {"hp": "health", "dmg": "damage", "speed": "speed"}
	var pk: Dictionary = r.get("perk", {})
	for k in ["hp", "dmg", "speed"]:
		if pk.has(k):
			var pc := int(round((clampf(float(pk[k]), MULT_MIN, MULT_MAX) - 1.0) * 100.0))
			parts.append("%s%d%% %s" % ["+" if pc >= 0 else "", pc, names[k]])
	if pk.has("cd"):
		var pc := int(round((1.0 - clampf(float(pk["cd"]), MULT_MIN, MULT_MAX)) * 100.0))
		parts.append("skill recharges %d%% %s" % [absi(pc), "faster" if pc >= 0 else "slower"])
	var ow: Dictionary = r.get("owner", {})
	if ow.has("armor"): parts.append("+%d armor for its hunter" % int(minf(float(ow["armor"]), OWNER_MAX["armor"])))
	if ow.has("sight"): parts.append("+%d%% sight for its hunter" % int(round(minf(float(ow["sight"]), OWNER_MAX["sight"]) * 100.0)))
	return ", ".join(parts) if not parts.is_empty() else "looks only"

## "Giant Albino" style prefix for names, "" for none.
static func prefix(rec: Dictionary) -> String:
	return " ".join(of(rec).map(func(id): return name_of(id)))

## Everything rare about it in a few words: "Shimmering, Giant, Albino".
static func tags(rec: Dictionary) -> Array:
	var out: Array = []
	if rec.get("shimmer", false): out.append("Shimmering")
	for id in of(rec): out.append(name_of(id))
	return out

# ------------------------------------------------------------------ the look
static func _op(c: Color, op) -> Color:
	if typeof(op) != TYPE_DICTIONARY:
		return c
	var o: Dictionary = op
	if o.has("set"): c = Color(String(o["set"]))
	if o.has("mix"): c = c.lerp(Color(String(o["mix"])), clampf(float(o.get("amt", 0.5)), 0.0, 1.0))
	if o.has("darken"): c = c.darkened(clampf(float(o["darken"]), 0.0, 1.0))
	if o.has("lighten"): c = c.lightened(clampf(float(o["lighten"]), 0.0, 1.0))
	if o.has("desat"):
		var g := c.r * 0.3 + c.g * 0.55 + c.b * 0.15
		c = c.lerp(Color(g, g, g, c.a), clampf(float(o["desat"]), 0.0, 1.0))
	return c

static func _albedo(m) -> Color:
	if m is ShaderMaterial:
		var v = (m as ShaderMaterial).get_shader_parameter("albedo")
		if v is Color: return v
	return Color.WHITE

static func _set_albedo(m, c: Color) -> void:
	if m is ShaderMaterial:
		(m as ShaderMaterial).set_shader_parameter("albedo", c)

## Changes a kin model (built by Models.kin, after Evo.dress) to show its mutations: its size,
## palette, rim light and extra parts. The model's mats are [body, belly, dark, glow, eye, ...].
static func dress(root: Node3D, rec: Dictionary) -> void:
	var list := of(rec)
	if list.is_empty():
		return
	var mats: Array = root.get_meta("mats", [])
	var body: Node3D = root.get_node("Body/Flex") if root.has_node("Body/Flex") else (root.get_node("Body") if root.has_node("Body") else root)
	var sp: Dictionary = Data.KIN.get(String(rec.get("species", "")), {})
	var orig_body: Color = _albedo(mats[0]) if mats.size() > 0 else sp.get("color", Color.WHITE)
	var glow_c: Color = sp.get("glow", orig_body)
	var slots := {"body": 0, "belly": 1, "dark": 2, "glow": 3, "eye": 4}
	var scale := 1.0
	for id in list:
		var vis: Dictionary = info(id).get("visual", {})
		scale *= clampf(float(vis.get("scale", 1.0)), 0.6, 1.45)
		var pal: Dictionary = vis.get("palette", {})
		for s in slots:
			if pal.has(s) and int(slots[s]) < mats.size():
				_set_albedo(mats[slots[s]], _op(_albedo(mats[slots[s]]), pal[s]))
		if vis.has("rim") and mats.size() > 1:
			for i in 2:
				if mats[i] is ShaderMaterial:
					(mats[i] as ShaderMaterial).set_shader_parameter("rim_amount", clampf(float(vis["rim"]), 0.0, 4.0))
					(mats[i] as ShaderMaterial).set_shader_parameter("rim_color", glow_c)
		var tint := Color(String(vis.get("tint", "#ffffff")))
		match String(vis.get("part", "")):
			"patches":
				var pm := Models.toon(orig_body)
				mats.append(pm)
				var spots := [Vector3(0.22, 0.42, 0.08), Vector3(-0.2, 0.3, 0.16), Vector3(0.05, 0.55, 0.2), Vector3(-0.12, 0.5, -0.18), Vector3(0.26, 0.24, -0.1)]
				for i in spots.size():
					var p: Vector3 = spots[i]
					var n := Vector3(p.x, p.y - 0.33, p.z).normalized()
					Models.part(body, Models.sphere(0.11 - i * 0.008, 8), pm, Vector3(0, 0.33, 0) + n * 0.31, Vector3(1.0, 0.45, 1.0), Vector3(n.z * 1.2, 0, -n.x * 1.2), "Patch%d" % i)
			"glow_marks":
				var gm := Models.toon(glow_c, false, 1.5)
				mats.append(gm)
				for i in 3:
					var y := 0.48 - i * 0.11
					var t := TorusMesh.new(); t.inner_radius = 0.3 - absf(i - 1) * 0.04; t.outer_radius = t.inner_radius + 0.035
					t.rings = 16; t.ring_segments = 4
					Models.part(body, t, gm, Vector3(0, y, 0.04), Vector3(1.0, 1.0, 1.0), Vector3(0.25, 0, 0), "GlowBand%d" % i)
				for sx in [-1.0, 1.0]:
					Models.part(body, Models.sphere(0.035, 6), gm, Vector3(0.12 * sx, 0.6, -0.26), Vector3.ONE, Vector3.ZERO, "GlowDot%d" % int(sx))
			"twin_tail":
				var tm: ShaderMaterial = mats[0] if mats.size() > 0 else Models.toon(orig_body)
				var tipm := Models.toon(glow_c, false, 0.6)
				mats.append(tipm)
				for sx in [-1.0, 1.0]:
					for i in 4:
						var k := float(i)
						Models.part(body, Models.sphere(0.075 - k * 0.012, 8), tm, Vector3(sx * (0.08 + k * 0.07), 0.24 + k * 0.08, 0.34 + k * 0.1), Vector3.ONE, Vector3.ZERO, "TwinTail%d_%d" % [int(sx), i])
					Models.part(body, Models.sphere(0.045, 8), tipm, Vector3(sx * 0.37, 0.58, 0.72), Vector3.ONE, Vector3.ZERO, "TwinTip%d" % int(sx))
			"crystals":
				var cm := Models.toon(tint, false, 0.75)
				cm.set_shader_parameter("rim_amount", 2.6)
				cm.set_shader_parameter("rim_color", Color.WHITE)
				mats.append(cm)
				var gems := [[Vector3(0, 0.66, 0.04), 0.26, 0.0], [Vector3(0.13, 0.6, 0.16), 0.2, -0.5], [Vector3(-0.13, 0.6, 0.16), 0.2, 0.5],
					[Vector3(0.06, 0.52, 0.3), 0.15, -0.3], [Vector3(-0.06, 0.5, 0.3), 0.14, 0.3]]
				for i in gems.size():
					var g: Array = gems[i]
					var c := CylinderMesh.new(); c.top_radius = 0.0; c.bottom_radius = 0.06; c.height = float(g[1]); c.radial_segments = 4; c.rings = 1
					Models.part(body, c, cm, g[0], Vector3.ONE, Vector3(0.35, 0.4 * i, float(g[2])), "Crystal%d" % i)
			"stars":
				var stm := Models.toon(tint, false, 1.8)
				mats.append(stm)
				var dots := [Vector3(0.2, 0.5, -0.18), Vector3(-0.24, 0.42, -0.1), Vector3(0.28, 0.3, 0.1), Vector3(-0.1, 0.58, 0.14), Vector3(-0.27, 0.24, 0.16), Vector3(0.1, 0.36, 0.3)]
				for i in dots.size():
					var p: Vector3 = dots[i]
					var n := Vector3(p.x, p.y - 0.33, p.z).normalized()
					Models.part(body, Models.sphere(0.028 if i % 2 == 0 else 0.02, 6), stm, Vector3(0, 0.33, 0) + n * 0.34, Vector3.ONE, Vector3.ZERO, "Star%d" % i)
				# a four-pointed star on the brow
				for r in [0.0, PI * 0.5]:
					Models.part(body, Models.box(0.12, 0.02, 0.02), stm, Vector3(0, 0.6, -0.27), Vector3.ONE, Vector3(0, 0, r + PI * 0.25), "BrowStar%d" % int(r * 10))
	root.set_meta("mats", mats)
	if absf(scale - 1.0) > 0.01:
		var es := float(root.get_meta("evo_scale", 1.0)) * scale
		root.set_meta("evo_scale", es)
		root.scale = Vector3.ONE * es
	root.set_meta("mutations", list)

# ------------------------------------------------------------------ badges
## A small round badge showing one mutation (or "shimmer"), drawn so it needs no special font.
class Badge extends Control:
	var id := ""
	var col := Color.WHITE
	var shape := "dot"
	func _init(mut_id := "", px := 16.0) -> void:
		id = mut_id
		if id == "shimmer":
			col = Color("fff0a0"); shape = "star5"
		else:
			var r := Mutations.info(id)
			col = r.get("col", Color.WHITE); shape = String(r.get("badge", "dot"))
		custom_minimum_size = Vector2(px, px)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_PASS
		tooltip_text = "Shimmering: rare colours" if id == "shimmer" else "%s: %s (%s)" % [Mutations.name_of(id), String(Mutations.info(id).get("desc", "")), Mutations.perk_text(id)]
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c, r, Color(0.05, 0.05, 0.09, 0.92))
		draw_arc(c, r - 0.8, 0, TAU, 24, Color(col, 0.9), 1.4, true)
		var k := r * 0.58
		match shape:
			"tri_up": draw_colored_polygon(PackedVector2Array([c + Vector2(0, -k), c + Vector2(k, k * 0.75), c + Vector2(-k, k * 0.75)]), col)
			"tri_down": draw_colored_polygon(PackedVector2Array([c + Vector2(0, k), c + Vector2(k, -k * 0.75), c + Vector2(-k, -k * 0.75)]), col)
			"half":
				draw_circle(c, k, Color(col.darkened(0.55)))
				var pts := PackedVector2Array([c])
				for i in 13: pts.append(c + Vector2.from_angle(-PI * 0.5 + PI * i / 12.0) * k)
				draw_colored_polygon(pts, col)
			"dot": draw_circle(c, k, col)
			"ring": draw_arc(c, k * 0.8, 0, TAU, 20, col, maxf(1.5, k * 0.45), true)
			"rays":
				draw_circle(c, k * 0.45, col)
				for i in 8:
					var a := TAU * i / 8.0
					draw_line(c + Vector2.from_angle(a) * k * 0.65, c + Vector2.from_angle(a) * k * 1.05, col, 1.4, true)
			"twin":
				for sx in [-1.0, 1.0]:
					draw_line(c + Vector2(sx * k * 0.15, k * 0.8), c + Vector2(sx * k * 0.75, -k * 0.7), col, maxf(1.5, k * 0.32), true)
			"gem": draw_colored_polygon(PackedVector2Array([c + Vector2(0, -k), c + Vector2(k * 0.7, 0), c + Vector2(0, k), c + Vector2(-k * 0.7, 0)]), col)
			"star4":
				var p4 := PackedVector2Array()
				for i in 8:
					p4.append(c + Vector2.from_angle(-PI * 0.5 + PI * i / 4.0) * (k * 1.05 if i % 2 == 0 else k * 0.32))
				draw_colored_polygon(p4, col)
			"star5":
				var p5 := PackedVector2Array()
				for i in 10:
					p5.append(c + Vector2.from_angle(-PI * 0.5 + PI * i / 5.0) * (k * 1.05 if i % 2 == 0 else k * 0.45))
				draw_colored_polygon(p5, col)

## A row of badges for everything rare about a kin (empty HBox if nothing).
static func badges(rec: Dictionary, px := 16.0) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 3)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if rec.get("shimmer", false): h.add_child(Badge.new("shimmer", px))
	for id in of(rec): h.add_child(Badge.new(id, px))
	return h
