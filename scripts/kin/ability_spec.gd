class_name AbilitySpec
extends RefCounted
## A kin ability in the grammar (content/abilities_v2/<id>.json, docs/KIN_GRAMMAR.md):
## a trigger, a cooldown and cost, a tier, and 1-4 stages of delivery + effects + modifiers.
## Parsing only checks structure; nothing here runs. Phase 2's executor reads these objects.

var id := ""
var display_name := ""
var short := ""             # the one or two words on the HUD slot
var flavor := ""            # the creator's own words; the rules text is generated from the parts (Phase 4)
var theme := "none"         # cosmetic tint and particles only
var tier := 1               # budget bracket (Phase 3 sets each tier's cap)
var from := "kin"           # kin: the kin performs it (thrown out first if carried) | owner: it works on the hunter wherever the kin is
var cast_range := 0.0       # how far from the caster it can be aimed (0 = no limit / self)
var cooldown := 8.0
var charges := 1
var bond_cost := 0.0        # fraction of the bond meter spent on use
var trigger: PartSpec
var cue: PartSpec           # the situation the AI uses it in (needed for auto; bots and auto-cast read it too)
var stages: Array[StageSpec] = []

const FIELDS := ["grammar", "id", "name", "short", "flavor", "theme", "tier", "from", "range", "cooldown", "charges", "cost", "trigger", "cue", "stages"]
const REQUIRED := ["grammar", "id", "name", "trigger", "stages"]

static func parse(v: Variant, rep: GrammarReport) -> AbilitySpec:
	var a := AbilitySpec.new()
	var d := rep.obj(v, "")
	if d.is_empty():
		return null
	rep.scan_refs(d, "")
	rep.keys(d, "", FIELDS, REQUIRED)
	_grammar(d, rep)
	a.id = rep.ident(d, "id", "")
	a.display_name = rep.text(d, "name", "", "", true)
	a.short = rep.text(d, "short", "", a.display_name)
	a.flavor = rep.text(d, "flavor", "")
	a.theme = rep.text(d, "theme", "", "none")
	if not KinParts.THEMES.has(a.theme):
		rep.err("theme", "unknown theme '%s' (themes are cosmetic: %s)" % [a.theme, ", ".join(KinParts.THEMES)])
	a.tier = int(rep.number(d, "tier", "", 1, 3, 1, true))
	a.from = rep.choice(d, "from", ["kin", "owner"], "", "kin")
	a.cast_range = rep.number(d, "range", "", 0.0, 25.0, 0.0)
	a.cooldown = rep.number(d, "cooldown", "", 1.0, 60.0, 8.0)
	a.charges = int(rep.number(d, "charges", "", 1, 3, 1, true))
	if d.has("cost"):
		var c := rep.obj(d["cost"], "cost")
		rep.keys(c, "cost", ["bond"])
		a.bond_cost = rep.number(c, "bond", "cost", 0.0, 0.5, 0.0)
	if d.has("trigger"):
		a.trigger = PartSpec.parse("trigger", d["trigger"], "trigger", rep)
	if d.has("cue"):
		a.cue = PartSpec.parse("cue", d["cue"], "cue", rep)
	if a.trigger and a.trigger.type == "auto" and a.cue == null and not d.has("cue"):
		rep.err("cue", "missing: an auto ability needs a cue, the situation the kin uses it in (%s)" % ", ".join(KinParts.CUES.keys()))
	var list := rep.arr(d.get("stages", []), "stages")
	if d.has("stages") and list.is_empty():
		rep.err("stages", "needs at least one stage")
	if list.size() > KinParts.MAX_STAGES:
		rep.err("stages", "%d stages; the most is %d" % [list.size(), KinParts.MAX_STAGES])
	for i in list.size():
		var s := StageSpec.parse(list[i], GrammarReport.join("stages", i), rep)
		if s == null:
			continue
		a.stages.append(s)
		if a.from == "owner" and s.delivery and String(s.delivery.params.get("origin", "")) == "caster":
			rep.err(GrammarReport.join("stages", i) + ".delivery.origin", "a from:owner ability happens at the hunter; use origin owner or aim, not caster")
	return a

static func _grammar(d: Dictionary, rep: GrammarReport) -> void:
	if d.has("grammar") and not (typeof(d["grammar"]) in [TYPE_INT, TYPE_FLOAT] and int(d["grammar"]) == KinParts.GRAMMAR_VERSION):
		rep.err("grammar", "this file is grammar %s; this build reads grammar %d" % [KinParts._num(float(d["grammar"])) if typeof(d["grammar"]) in [TYPE_INT, TYPE_FLOAT] else KinParts._show(d["grammar"]), KinParts.GRAMMAR_VERSION])

## Every stage, followups included.
func all_stages() -> Array[StageSpec]:
	var out: Array[StageSpec] = []
	for s in stages:
		out.append_array(s.walk())
	return out

func effect_types() -> Array:
	var out: Array = []
	for s in all_stages():
		for e in s.effects:
			if not out.has(e.type): out.append(e.type)
	return out

## Placeholder power cost (Phase 3).
func cost() -> float:
	var c := 0.0
	for s in stages: c += s.cost()
	return c
