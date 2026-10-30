class_name EvolutionNode
extends RefCounted
## One step on a kin's evolution path (content/evolution_v2/<id>.json, docs/KIN_GRAMMAR.md).
## Evolution adds variety, not raw power: a node moves stat points (the total stays the same),
## adds a modifier to one of the kin's abilities, or makes a sidegrade (one number up, another down).
## Phase 3 prices added modifiers against the tier budget.
##
##   grants: [{"kind": "stat_shift", "from": "kin_hp", "to": "kin_damage", "points": 1},
##            {"kind": "add_modifier", "slot": "active", "stage": 0, "modifier": {"type": "pierce", "count": 1}},
##            {"kind": "sidegrade", "slot": "auto", "stage": 0,
##             "up": {"param": "delivery.range", "scale": 1.2}, "down": {"param": "delivery.speed", "scale": 0.85}}]

var id := ""
var display_name := ""
var flavor := ""
var affinity := ""          # fierce | steadfast | curious | swift: what raising it this way leads to
var level := 1              # kin level it can happen at
var after: Array = []       # node ids that must come first
var grants: Array = []      # parsed grants (see above); add_modifier holds a PartSpec in "modifier"
var parts: Array = []       # cosmetic body parts it grows (Evo.PART_NAMES)
var tint := ""

const FIELDS := ["grammar", "id", "name", "flavor", "affinity", "requires", "grants", "cosmetic"]
const REQUIRED := ["grammar", "id", "name", "affinity", "requires", "grants"]

static func parse(v: Variant, rep: GrammarReport) -> EvolutionNode:
	var n := EvolutionNode.new()
	var d := rep.obj(v, "")
	if d.is_empty():
		return null
	rep.scan_refs(d, "")
	rep.keys(d, "", FIELDS, REQUIRED)
	AbilitySpec._grammar(d, rep)
	n.id = rep.ident(d, "id", "")
	n.display_name = rep.text(d, "name", "", "", true)
	n.flavor = rep.text(d, "flavor", "")
	n.affinity = rep.choice(d, "affinity", KinParts.AFFINITIES, "")
	if d.has("requires"):
		var r := rep.obj(d["requires"], "requires")
		rep.keys(r, "requires", ["level", "after"], ["level"])
		n.level = int(rep.number(r, "level", "requires", 1, 60, 1, true))
		for i in rep.arr(r.get("after", []), "requires.after").size():
			var a = r["after"][i]
			if typeof(a) != TYPE_STRING or not GrammarReport.is_ident(a):
				rep.err("requires.after[%d]" % i, "must be a node id, got %s" % KinParts._show(a))
			else:
				n.after.append(a)
	var gl := rep.arr(d.get("grants", []), "grants")
	if d.has("grants") and gl.is_empty():
		rep.err("grants", "needs at least one grant (%s)" % ", ".join(KinParts.EVO_GRANTS))
	for i in gl.size():
		var g := _grant(gl[i], GrammarReport.join("grants", i), rep)
		if not g.is_empty(): n.grants.append(g)
	if d.has("cosmetic"):
		var c := rep.obj(d["cosmetic"], "cosmetic")
		rep.keys(c, "cosmetic", ["parts", "tint"])
		for i in rep.arr(c.get("parts", []), "cosmetic.parts").size():
			var p = c["parts"][i]
			if not KinParts.EVO_PARTS.has(p):
				rep.err("cosmetic.parts[%d]" % i, "unknown body part %s (known: %s)" % [KinParts._show(p), ", ".join(KinParts.EVO_PARTS)])
			else:
				n.parts.append(p)
		n.tint = rep.color(c, "tint", "cosmetic")
	return n

static func _grant(v: Variant, path: String, rep: GrammarReport) -> Dictionary:
	var d := rep.obj(v, path)
	if d.is_empty(): return {}
	var kind := rep.text(d, "kind", path)
	match kind:
		"stat_shift":
			rep.keys(d, path, ["kind", "from", "to", "points"], ["from", "to", "points"])
			var a := rep.text(d, "from", path); var b := rep.text(d, "to", path)
			for pair in [["from", a], ["to", b]]:
				if not KinParts.STATS.has(pair[1]):
					rep.err(path + "." + pair[0], "unknown stat '%s' (known: %s)" % [pair[1], ", ".join(KinParts.STATS.keys())])
			if a == b and a != "":
				rep.err(path, "moves points from %s to itself" % a)
			return {"kind": kind, "from": a, "to": b, "points": int(rep.number(d, "points", path, 1, 2, 1, true))}
		"add_modifier":
			rep.keys(d, path, ["kind", "slot", "stage", "modifier"], ["slot", "modifier"])
			var mp := PartSpec.parse("modifier", d.get("modifier", {}), path + ".modifier", rep)
			return {"kind": kind, "slot": _slot(d, path, rep), "stage": int(rep.number(d, "stage", path, 0, KinParts.MAX_STAGES - 1, 0, true)), "modifier": mp}
		"sidegrade":
			rep.keys(d, path, ["kind", "slot", "stage", "up", "down"], ["slot", "up", "down"])
			var g := {"kind": kind, "slot": _slot(d, path, rep), "stage": int(rep.number(d, "stage", path, 0, KinParts.MAX_STAGES - 1, 0, true))}
			for side: String in ["up", "down"]:
				var sp := path + "." + side
				var s := rep.obj(d.get(side, {}), sp)
				rep.keys(s, sp, ["param", "scale"], ["param", "scale"])
				var lim: Array = KinParts.SIDEGRADE_UP if side == "up" else KinParts.SIDEGRADE_DOWN
				g[side] = {"param": rep.text(s, "param", sp), "scale": rep.number(s, "scale", sp, lim[0], lim[1], 1.0)}
				if not _param_path(String(g[side]["param"])):
					rep.err(sp + ".param", "'%s' must be delivery.<param> or effects.<n>.<param>" % g[side]["param"])
			if String(g["up"]["param"]) == String(g["down"]["param"]) and String(g["up"]["param"]) != "":
				rep.err(path, "up and down change the same number")
			return g
		"":
			rep.err(path + ".kind", "missing: pick %s" % ", ".join(KinParts.EVO_GRANTS))
		_:
			rep.err(path + ".kind", "unknown grant '%s' (known: %s)" % [kind, ", ".join(KinParts.EVO_GRANTS)])
	return {}

static func _slot(d: Dictionary, path: String, rep: GrammarReport) -> String:
	return rep.choice(d, "slot", KinParts.EVO_SLOTS, path)

## "delivery.range" or "effects.1.duration"
static func _param_path(p: String) -> bool:
	var bits := p.split(".")
	if bits.size() == 2 and bits[0] == "delivery": return true
	return bits.size() == 3 and bits[0] == "effects" and bits[1].is_valid_int()
