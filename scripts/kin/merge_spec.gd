class_name MergeSpec
extends RefCounted
## A kin's bond ultimate: the merge (content/merges_v2/<id>.json, docs/KIN_GRAMMAR.md). For a
## limited time hunter and kin fight as one: owner passives (movement, defence, offence, senses),
## riders on every shot, stages when it starts and ends, pulses while it lasts, and merged
## versions of the kin's abilities. When it unlocks, how the meter fills and when it ends early
## are core rules (KinParts.MERGE_*), not data.

var id := ""
var display_name := ""
var flavor := ""
var theme := "none"
var duration := 6.0
var grow_duration := 1.0     # extra seconds at full kin level and bond
var grow_strength := 0.1     # extra strength at full kin level and bond
var passives: Array = []     # [{stat, amount, category}]
var on_shot := {}            # {effects: Array[PartSpec], splash, chain}
var on_start: Array[StageSpec] = []
var on_end: Array[StageSpec] = []
var pulses: Array = []       # [{every, stage: StageSpec}]
var merged := {}             # slot ("active" | "auto") -> {stage, add_modifiers: Array[PartSpec], scale: {param: k}}

const FIELDS := ["grammar", "id", "name", "flavor", "theme", "duration", "grow_duration", "grow_strength", "passives", "on_shot", "on_start", "on_end", "pulses", "merged"]
const REQUIRED := ["grammar", "id", "name", "duration", "passives"]

static func parse(v: Variant, rep: GrammarReport) -> MergeSpec:
	var m := MergeSpec.new()
	var d := rep.obj(v, "")
	if d.is_empty():
		return null
	rep.scan_refs(d, "")
	rep.keys(d, "", FIELDS, REQUIRED)
	AbilitySpec._grammar(d, rep)
	m.id = rep.ident(d, "id", "")
	m.display_name = rep.text(d, "name", "", "", true)
	m.flavor = rep.text(d, "flavor", "")
	m.theme = rep.text(d, "theme", "", "none")
	if not KinParts.THEMES.has(m.theme):
		rep.err("theme", "unknown theme '%s' (themes are cosmetic: %s)" % [m.theme, ", ".join(KinParts.THEMES)])
	m.duration = float(rep.param(d, "duration", KinParts.MERGE["duration"], ""))
	m.grow_duration = float(rep.param(d, "grow_duration", KinParts.MERGE["grow_duration"], ""))
	m.grow_strength = float(rep.param(d, "grow_strength", KinParts.MERGE["grow_strength"], ""))
	m.passives = parse_passives(d.get("passives", []), "passives", rep, "merge")
	if d.has("on_shot"):
		m.on_shot = parse_on_shot(d["on_shot"], "on_shot", rep)
	m.on_start = _stages(d, "on_start", rep)
	m.on_end = _stages(d, "on_end", rep)
	for i in rep.arr(d.get("pulses", []), "pulses").size():
		var pp := GrammarReport.join("pulses", i)
		var pd := rep.obj(d["pulses"][i], pp)
		rep.keys(pd, pp, ["every", "stage"], ["every", "stage"])
		var st := StageSpec.parse(pd["stage"], pp + ".stage", rep) if pd.has("stage") else null
		if st: m.pulses.append({"every": float(rep.param(pd, "every", KinParts.PULSE["every"], pp)), "stage": st})
	if d.has("merged"):
		var md := rep.obj(d["merged"], "merged")
		rep.keys(md, "merged", KinParts.EVO_SLOTS)
		for slot in md:
			if KinParts.EVO_SLOTS.has(slot):
				m.merged[slot] = _patch(md[slot], "merged." + slot, rep)
	return m

static func _stages(d: Dictionary, key: String, rep: GrammarReport) -> Array[StageSpec]:
	var out: Array[StageSpec] = []
	var list := rep.arr(d.get(key, []), key)
	if list.size() > KinParts.MAX_STAGES:
		rep.err(key, "%d stages; the most is %d" % [list.size(), KinParts.MAX_STAGES])
	for i in list.size():
		var s := StageSpec.parse(list[i], GrammarReport.join(key, i), rep)
		if s: out.append(s)
	return out

## A merged ability: which stage of the kin's ability changes, modifiers it gains, and numbers on
## that stage's delivery that grow (x1.0 to x1.3). Checked against the real ability by KinSpec.
static func _patch(v: Variant, path: String, rep: GrammarReport) -> Dictionary:
	var d := rep.obj(v, path)
	rep.keys(d, path, ["stage", "add_modifiers", "scale"])
	var out := {"stage": int(rep.number(d, "stage", path, 0, KinParts.MAX_STAGES - 1, 0, true)), "add_modifiers": [], "scale": {}}
	var mods := rep.arr(d.get("add_modifiers", []), path + ".add_modifiers")
	for i in mods.size():
		var mp := PartSpec.parse("modifier", mods[i], GrammarReport.join(path + ".add_modifiers", i), rep)
		if mp: out["add_modifiers"].append(mp)
	var sc := rep.obj(d.get("scale", {}), path + ".scale")
	for k in sc:
		var kv: float = rep.number(sc, k, path + ".scale", KinParts.MERGED_SCALE[0], KinParts.MERGED_SCALE[1], 1.0)
		out["scale"][k] = kv
	if (out["add_modifiers"] as Array).is_empty() and (out["scale"] as Dictionary).is_empty():
		rep.err(path, "a merged ability needs add_modifiers or scale (or leave the slot out)")
	return out

## Owner passives: [{"stat": "move_speed", "amount": 0.3}]. `which` is "carry" or "merge" (caps differ).
static func parse_passives(v: Variant, path: String, rep: GrammarReport, which: String) -> Array:
	var out: Array = []
	var seen := {}
	var list := rep.arr(v, path)
	for i in list.size():
		var pp := GrammarReport.join(path, i)
		var d := rep.obj(list[i], pp)
		if d.is_empty(): continue
		rep.keys(d, pp, ["stat", "amount"], ["stat", "amount"])
		var st := rep.text(d, "stat", pp)
		if not KinParts.OWNER_STATS.has(st):
			rep.err(pp + ".stat", "unknown owner stat '%s' (known: %s)" % [st, ", ".join(KinParts.OWNER_STATS.keys())])
			continue
		if seen.has(st):
			rep.err(pp + ".stat", "%s is listed twice" % st)
		seen[st] = true
		var row: Array = KinParts.OWNER_STATS[st]
		var hi := float(row[2] if which == "carry" else row[3])
		if hi <= 0.0:
			rep.err(pp + ".stat", "%s can only come from a merge, not a carried kin" % st)
			continue
		var amt := rep.number(d, "amount", pp, 0.0, hi, 0.0, String(row[1]) == "int")
		out.append({"stat": st, "amount": amt, "category": row[0]})
	return out

## Riders on the hunter's shots: {"effects": [...], "splash": m, "chain": n}. No stun or root.
static func parse_on_shot(v: Variant, path: String, rep: GrammarReport) -> Dictionary:
	var d := rep.obj(v, path)
	rep.keys(d, path, ["effects", "splash", "chain"])
	var out := {"effects": [], "splash": float(rep.param(d, "splash", KinParts.SHOT["splash"], path)), "chain": int(rep.param(d, "chain", KinParts.SHOT["chain"], path))}
	var effs := rep.arr(d.get("effects", []), path + ".effects")
	if effs.size() > 3:
		rep.err(path + ".effects", "%d shot riders; the most is 3" % effs.size())
	for i in effs.size():
		var ep := GrammarReport.join(path + ".effects", i)
		var e := PartSpec.parse("effect", effs[i], ep, rep)
		if e == null: continue
		if not KinParts.SHOT_EFFECTS.has(e.type):
			rep.err(ep, "%s can't ride on every shot (allowed: %s)" % [e.type, ", ".join(KinParts.SHOT_EFFECTS)])
		out["effects"].append(e)
	if (out["effects"] as Array).is_empty() and out["splash"] == 0.0 and out["chain"] == 0:
		rep.err(path, "on_shot needs effects, splash or chain (or leave it out)")
	return out
