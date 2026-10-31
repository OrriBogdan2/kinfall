class_name KinSpec
extends RefCounted
## A kin species in the grammar (content/kin_v2/<id>.json, docs/KIN_GRAMMAR.md): the animals it's
## based on, its body and looks, a stat profile that spends exactly KinParts.STAT_BUDGET points,
## personality and AI weights, how it's carried, what its throw and dodge rider do, its slots
## (active on E, an optional auto active, the merge) and its evolution paths.
## Parsing checks structure; check_refs() then checks it against the abilities, merges and nodes.

var id := ""
var display_name := ""
var animals: Array = []
var theme := "none"
var flavor := ""
var colors := {}             # body belly glow wing: hex
var look := {}               # body ears tail feet aura: core model builder ids
var size := "small"
var reach := 1.3
var mass := 0.8
var gait := {}
var stat_points := {}        # stat -> points
var personality := {}        # bravery loyalty temper curiosity, 0..1
var ai := {}                 # aggression loyalty caution 0..1, role
var carry_style := "shoulder"
var carry_name := ""
var carry_passives: Array = []
var carry_on_shot := {}
var mount := {}
var throw_effects: Array[PartSpec] = []
var dodge_rider := {}        # name, as, on_pass: Array[PartSpec], on_start/on_end: Array[StageSpec], modifiers
var active := ""
var auto := ""
var merge := ""
var evo_root := ""
var evo_paths: Array = []    # [{affinity, nodes: [ids]}]
var voice := {}
var egg := {}

const FIELDS := ["grammar", "id", "name", "animals", "theme", "flavor", "colors", "look", "body", "stats", "personality", "ai", "carry", "throw", "dodge_rider", "active", "auto", "merge", "evolution", "voice", "egg"]
const REQUIRED := ["grammar", "id", "name", "animals", "colors", "look", "body", "stats", "personality", "ai", "carry", "active", "merge"]

static func parse(v: Variant, rep: GrammarReport) -> KinSpec:
	var k := KinSpec.new()
	var d := rep.obj(v, "")
	if d.is_empty():
		return null
	rep.scan_refs(d, "")
	rep.keys(d, "", FIELDS, REQUIRED)
	AbilitySpec._grammar(d, rep)
	k.id = rep.ident(d, "id", "")
	k.display_name = rep.text(d, "name", "", "", true)
	k.flavor = rep.text(d, "flavor", "")
	k.theme = rep.text(d, "theme", "", "none")
	if not KinParts.THEMES.has(k.theme):
		rep.err("theme", "unknown theme '%s' (themes are cosmetic: %s)" % [k.theme, ", ".join(KinParts.THEMES)])
	# based on one or two real animals
	var an := rep.arr(d.get("animals", []), "animals")
	if d.has("animals") and (an.size() < 1 or an.size() > 2):
		rep.err("animals", "a kin is based on 1 or 2 real animals, got %d" % an.size())
	for i in an.size():
		if typeof(an[i]) != TYPE_STRING or String(an[i]).strip_edges() == "":
			rep.err("animals[%d]" % i, "must be an animal's name")
		else:
			k.animals.append(an[i])
	# looks
	if d.has("colors"):
		var c := rep.obj(d["colors"], "colors")
		rep.keys(c, "colors", ["body", "belly", "glow", "wing"], ["body", "belly", "glow"])
		for key in c: k.colors[key] = rep.color(c, key, "colors")
	if d.has("look"):
		var l := rep.obj(d["look"], "look")
		rep.keys(l, "look", KinParts.LOOK.keys(), ["body"])
		for key in KinParts.LOOK:
			k.look[key] = rep.param(l, key, ["enum", KinParts.LOOK[key], null, "none" if key != "body" else null, "", ""], "look")
	if d.has("body"):
		var b := rep.obj(d["body"], "body")
		rep.keys(b, "body", KinParts.BODY.keys() + ["gait"], ["size"])
		k.size = String(rep.param(b, "size", KinParts.BODY["size"], "body"))
		k.reach = float(rep.param(b, "reach", KinParts.BODY["reach"], "body"))
		k.mass = float(rep.param(b, "mass", KinParts.BODY["mass"], "body"))
		var g := rep.obj(b.get("gait", {}), "body.gait")
		rep.keys(g, "body.gait", KinParts.GAIT.keys())
		for key in KinParts.GAIT: k.gait[key] = rep.param(g, key, KinParts.GAIT[key], "body.gait")
	# stat profile: exactly STAT_BUDGET points
	if d.has("stats"):
		var s := rep.obj(d["stats"], "stats")
		rep.keys(s, "stats", KinParts.STATS.keys())
		var total := 0
		for key in s:
			if not KinParts.STATS.has(key): continue
			var pts := int(rep.number(s, key, "stats", 0, KinParts.STATS[key]["max_points"], 0, true))
			k.stat_points[key] = pts
			total += pts
		if total != KinParts.STAT_BUDGET:
			rep.err("stats", "spends %d points; every kin spends exactly %d" % [total, KinParts.STAT_BUDGET])
	k.personality = _unit_block(d, "personality", KinParts.TRAITS, rep)
	k.ai = _unit_block(d, "ai", KinParts.AI_KEYS, rep, ["role"])
	if d.has("ai") and typeof(d["ai"]) == TYPE_DICTIONARY:
		k.ai["role"] = rep.choice(d["ai"], "role", KinParts.ROLES, "ai")
	# carry
	if d.has("carry"):
		var c := rep.obj(d["carry"], "carry")
		rep.keys(c, "carry", ["style", "name", "passives", "on_shot", "mount"], ["style"])
		k.carry_style = rep.choice(c, "style", KinParts.CARRY.keys(), "carry")
		k.carry_name = rep.text(c, "name", "carry")
		if KinParts.CARRY.has(k.carry_style) and not (KinParts.CARRY[k.carry_style]["sizes"] as Array).has(k.size):
			rep.err("carry.style", "a %s kin can't be carried as %s (%s takes %s kin)" % [k.size, k.carry_style, k.carry_style, " or ".join(KinParts.CARRY[k.carry_style]["sizes"])])
		k.carry_passives = MergeSpec.parse_passives(c.get("passives", []), "carry.passives", rep, "carry")
		if c.has("on_shot"):
			k.carry_on_shot = MergeSpec.parse_on_shot(c["on_shot"], "carry.on_shot", rep)
		if k.carry_style == "mount":
			var mo := rep.obj(c.get("mount", {}), "carry.mount")
			rep.keys(mo, "carry.mount", KinParts.MOUNT.keys())
			for key in KinParts.MOUNT: k.mount[key] = rep.param(mo, key, KinParts.MOUNT[key], "carry.mount")
		elif c.has("mount"):
			rep.err("carry.mount", "only a mount kin has mount settings")
	# throw
	if d.has("throw"):
		var t := rep.obj(d["throw"], "throw")
		rep.keys(t, "throw", ["effects"], ["effects"])
		var effs := rep.arr(t.get("effects", []), "throw.effects")
		if effs.size() > 3:
			rep.err("throw.effects", "%d effects; a throw carries at most 3" % effs.size())
		for i in effs.size():
			var e := PartSpec.parse("effect", effs[i], "throw.effects[%d]" % i, rep)
			if e:
				if e.target != "foes": rep.err("throw.effects[%d].target" % i, "a throw lands on a foe")
				k.throw_effects.append(e)
	if d.has("dodge_rider"):
		k.dodge_rider = _rider(d["dodge_rider"], rep)
	# slots
	k.active = rep.ident(d, "active", "")
	k.auto = rep.ident(d, "auto", "", false)
	k.merge = rep.ident(d, "merge", "")
	if k.active != "" and k.active == k.auto:
		rep.err("auto", "the auto active must differ from the active")
	# evolution
	if d.has("evolution"):
		var ev := rep.obj(d["evolution"], "evolution")
		rep.keys(ev, "evolution", ["root", "paths"], ["root", "paths"])
		k.evo_root = rep.text(ev, "root", "evolution", "", true)
		if k.evo_root.length() > 8:
			rep.err("evolution.root", "'%s' is the start of evolved names (Cind + fang); keep it to 8 letters" % k.evo_root)
		var paths := rep.arr(ev.get("paths", []), "evolution.paths")
		for i in paths.size():
			var pp := "evolution.paths[%d]" % i
			var p := rep.obj(paths[i], pp)
			rep.keys(p, pp, ["affinity", "nodes"], ["affinity", "nodes"])
			var aff := rep.choice(p, "affinity", KinParts.AFFINITIES, pp)
			var ids: Array = []
			for j in rep.arr(p.get("nodes", []), pp + ".nodes").size():
				var nid = p["nodes"][j]
				if typeof(nid) != TYPE_STRING or not GrammarReport.is_ident(nid):
					rep.err("%s.nodes[%d]" % [pp, j], "must be a node id")
				else:
					ids.append(nid)
			k.evo_paths.append({"affinity": aff, "nodes": ids})
	if d.has("voice"):
		var vo := rep.obj(d["voice"], "voice")
		rep.keys(vo, "voice", ["line", "syllables"], ["syllables"])
		k.voice["line"] = rep.text(vo, "line", "voice")
		var sy := rep.arr(vo.get("syllables", []), "voice.syllables")
		if sy.size() != 2:
			rep.err("voice.syllables", "a kin says its name in 2 syllables, got %d" % sy.size())
		k.voice["syllables"] = sy
	if d.has("egg"):
		var e := rep.obj(d["egg"], "egg")
		rep.keys(e, "egg", ["name", "temper", "desc", "play"], ["name"])
		for key in e: k.egg[key] = rep.text(e, key, "egg")
	return k

## A block of 0..1 numbers with exactly these keys (plus `extra` keys handled by the caller).
static func _unit_block(d: Dictionary, key: String, names: Array, rep: GrammarReport, extra: Array = []) -> Dictionary:
	var out := {}
	if not d.has(key):
		return out
	var b := rep.obj(d[key], key)
	rep.keys(b, key, names + extra, names + extra)
	for n in names:
		out[n] = rep.number(b, n, key, 0.0, 1.0, 0.5)
	return out

## The class dodge's kin rider: effects on what you dodge through, stages at the start or end,
## an echo, or the dodge becoming a blink.
static func _rider(v: Variant, rep: GrammarReport) -> Dictionary:
	var d := rep.obj(v, "dodge_rider")
	rep.keys(d, "dodge_rider", ["name", "as", "on_pass", "on_start", "on_end", "modifiers"], ["name"])
	var out := {"name": rep.text(d, "name", "dodge_rider"), "as": rep.choice(d, "as", ["dash", "blink"], "dodge_rider", "dash"),
		"on_pass": [], "on_start": MergeSpec._stages(d, "on_start", rep), "on_end": MergeSpec._stages(d, "on_end", rep), "modifiers": []}
	var effs := rep.arr(d.get("on_pass", []), "dodge_rider.on_pass")
	for i in effs.size():
		var e := PartSpec.parse("effect", effs[i], "dodge_rider.on_pass[%d]" % i, rep)
		if e:
			if e.is_hard_cc(): rep.err("dodge_rider.on_pass[%d]" % i, "a dodge can't %s what it passes through" % e.type)
			out["on_pass"].append(e)
	var mods := rep.arr(d.get("modifiers", []), "dodge_rider.modifiers")
	for i in mods.size():
		var m := PartSpec.parse("modifier", mods[i], "dodge_rider.modifiers[%d]" % i, rep)
		if m:
			if m.type != "repeat": rep.err("dodge_rider.modifiers[%d]" % i, "a dodge rider can only take repeat, not %s" % m.type)
			out["modifiers"].append(m)
	if (out["on_pass"] as Array).is_empty() and (out["on_start"] as Array).is_empty() and (out["on_end"] as Array).is_empty() and (out["modifiers"] as Array).is_empty() and out["as"] == "dash":
		rep.err("dodge_rider", "does nothing: add on_pass, on_start, on_end, modifiers or as: blink")
	return out

## Checks the slots and evolution against the loaded library {abilities, merges, evolution}.
func check_refs(lib: Dictionary, rep: GrammarReport) -> void:
	var abil: Dictionary = lib.get("abilities", {})
	var slots := {}
	if active != "":
		if not abil.has(active):
			rep.err("active", "no ability '%s' in abilities_v2" % active)
		else:
			slots["active"] = abil[active]
			var a: AbilitySpec = abil[active]
			if a.trigger and a.trigger.type != "on_cast":
				rep.err("active", "'%s' is the player's E, so its trigger must be on_cast (it's %s)" % [active, a.trigger.type])
	if auto != "":
		if not abil.has(auto):
			rep.err("auto", "no ability '%s' in abilities_v2" % auto)
		else:
			slots["auto"] = abil[auto]
			var a: AbilitySpec = abil[auto]
			if a.trigger and a.trigger.type == "on_cast":
				rep.err("auto", "'%s' is the kin's own ability, so its trigger can't be on_cast" % auto)
	if merge != "":
		if not (lib.get("merges", {}) as Dictionary).has(merge):
			rep.err("merge", "no merge '%s' in merges_v2" % merge)
		else:
			var m: MergeSpec = lib["merges"][merge]
			for slot in m.merged:
				var path := "merge(%s).merged.%s" % [merge, slot]
				if not slots.has(slot):
					rep.err(path, "patches the %s ability, but this kin has none" % slot)
					continue
				var p: Dictionary = m.merged[slot]
				var st := _stage(slots[slot], int(p["stage"]), path, rep)
				if st == null: continue
				for mp in p["add_modifiers"]:
					_can_add(st, mp, path, rep)
				for key in p["scale"]:
					if not _has_number(st, "delivery." + key):
						rep.err(path + ".scale." + key, "%s's stage %d %s has no number '%s'" % [slots[slot].id, int(p["stage"]), st.delivery.type, key])
					else:
						_scaled_ok(st, "delivery." + key, float(p["scale"][key]), path + ".scale." + key, rep)
	var nodes: Dictionary = lib.get("evolution", {})
	for i in evo_paths.size():
		var pth: Dictionary = evo_paths[i]
		var pp := "evolution.paths[%d]" % i
		var pts := stat_points.duplicate()
		var seen: Array = []
		var lv := 0
		for j in (pth["nodes"] as Array).size():
			var nid: String = pth["nodes"][j]
			var np := "%s.nodes[%d]" % [pp, j]
			if not nodes.has(nid):
				rep.err(np, "no evolution node '%s' in evolution_v2" % nid); continue
			var n: EvolutionNode = nodes[nid]
			if n.affinity != String(pth["affinity"]):
				rep.err(np, "'%s' is a %s node on the %s path" % [nid, n.affinity, pth["affinity"]])
			if n.level < lv:
				rep.err(np, "'%s' is level %d but comes after a level %d node" % [nid, n.level, lv])
			lv = n.level
			for req in n.after:
				if not seen.has(req):
					rep.err(np, "'%s' needs '%s' earlier on the same path" % [nid, req])
			seen.append(nid)
			for g in n.grants:
				match String(g["kind"]):
					"stat_shift":
						var a := String(g["from"]); var b := String(g["to"])
						if not KinParts.STATS.has(a) or not KinParts.STATS.has(b): continue
						pts[a] = int(pts.get(a, 0)) - int(g["points"])
						pts[b] = int(pts.get(b, 0)) + int(g["points"])
						if int(pts[a]) < 0:
							rep.err(np, "'%s' moves points out of %s, which has none left on this path" % [nid, a])
						if int(pts[b]) > int(KinParts.STATS[b]["max_points"]):
							rep.err(np, "'%s' pushes %s past its max of %d points" % [nid, b, int(KinParts.STATS[b]["max_points"])])
					"add_modifier", "sidegrade":
						var slot := String(g["slot"])
						if not slots.has(slot):
							rep.err(np, "'%s' changes the %s ability, but this kin has none" % [nid, slot]); continue
						var st := _stage(slots[slot], int(g["stage"]), np + "(" + nid + ")", rep)
						if st == null: continue
						if g["kind"] == "add_modifier":
							if g["modifier"]: _can_add(st, g["modifier"], np + "(" + nid + ")", rep)
						else:
							for side in ["up", "down"]:
								if not _has_number(st, String(g[side]["param"])):
									rep.err(np, "'%s' %s: %s's stage %d has no number '%s'" % [nid, side, slots[slot].id, int(g["stage"]), g[side]["param"]])
								else:
									_scaled_ok(st, String(g[side]["param"]), float(g[side]["scale"]), "%s(%s).%s" % [np, nid, side], rep)

static func _stage(a: AbilitySpec, i: int, path: String, rep: GrammarReport) -> StageSpec:
	if i >= a.stages.size():
		rep.err(path, "'%s' has no stage %d" % [a.id, i])
		return null
	return a.stages[i] if a.stages[i].delivery else null

static func _can_add(st: StageSpec, mp: PartSpec, path: String, rep: GrammarReport) -> void:
	if st.has_modifier(mp.type):
		rep.err(path, "the %s already has %s" % [st.delivery.type, mp.type])
	elif not (KinParts.MODIFIERS[mp.type]["on"] as Array).has(st.delivery.type):
		rep.err(path, "%s doesn't work on a %s" % [mp.type, st.delivery.type])

## A number scaled by a merge or a sidegrade must still sit inside its part's bounds.
static func _scaled_ok(st: StageSpec, p: String, k: float, path: String, rep: GrammarReport) -> void:
	var bits := p.split(".")
	var part: PartSpec = st.delivery if bits[0] == "delivery" else st.effects[int(bits[1])]
	var key: String = bits[bits.size() - 1]
	var pd: Array = KinParts.params_of(part.kind, part.type).get(key, [])
	if pd.is_empty():
		return
	var v := float(part.params[key]) * k
	if String(pd[0]) == "int": v = roundf(v)
	var msg := KinParts.value_error(pd, v)
	if msg != "":
		rep.err(path, "x%s takes %s %s to %s: %s" % [KinParts._num(k), part.type, key, KinParts._num(v), msg])

static func _has_number(st: StageSpec, p: String) -> bool:
	var bits := p.split(".")
	var params := {}
	if bits[0] == "delivery":
		params = st.delivery.params
	elif bits.size() == 3 and int(bits[1]) < st.effects.size():
		params = st.effects[int(bits[1])].params
	var key: String = bits[bits.size() - 1]
	return params.has(key) and typeof(params[key]) in [TYPE_FLOAT, TYPE_INT]

## The kin's real stat values from its points.
func stat(key: String) -> float:
	var s: Dictionary = KinParts.STATS.get(key, {})
	return float(s.get("base", 0.0)) + float(s.get("per_point", 0.0)) * float(stat_points.get(key, 0))
