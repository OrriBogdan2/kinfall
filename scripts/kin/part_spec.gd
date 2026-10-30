class_name PartSpec
extends RefCounted
## One part of the kin grammar, parsed and checked against KinParts: a delivery, an effect, a
## modifier, a trigger or a cue. `params` holds every parameter resolved (defaults, then the
## preset, then what the file set), so the Phase 2 runtime never has to guess a number.

var kind := ""          # delivery | effect | modifier | trigger | cue
var type := ""
var preset := ""
var target := ""        # effects only: foes | owner | self | allies | wall
var params := {}
var explicit := {}      # only what the file itself set

## The fields every part may carry besides its params.
const _COMMON := ["type", "preset"]

static func parse(kind_: String, v: Variant, path: String, rep: GrammarReport) -> PartSpec:
	var p := PartSpec.new()
	p.kind = kind_
	var d := rep.obj(v, path)
	if d.is_empty():
		if typeof(v) == TYPE_DICTIONARY: rep.err(path, "empty %s: needs at least a type" % kind_)
		return null
	var tbl := KinParts.table(kind_)
	p.type = rep.text(d, "type", path)
	if p.type == "":
		rep.err(GrammarReport.join(path, "type"), "missing: pick a %s from %s" % [kind_, KinParts._list(tbl.keys())])
		return null
	if not tbl.has(p.type):
		rep.err(GrammarReport.join(path, "type"), "unknown %s '%s' (known: %s)" % [kind_, p.type, ", ".join(tbl.keys())])
		return null
	var defs: Dictionary = (tbl[p.type].get("params", {}) as Dictionary).duplicate()
	# a signature brings its own parameters
	if kind_ == "effect" and p.type == "signature" and d.has("id") and KinParts.SIGNATURES.has(d["id"]):
		defs.merge(KinParts.SIGNATURES[d["id"]]["params"])
	var allowed: Array = _COMMON + defs.keys()
	if kind_ == "effect":
		allowed.append("target")
	rep.keys(d, path, allowed)
	# preset: fills params first, the file can override
	var base := {}
	if d.has("preset"):
		p.preset = rep.text(d, "preset", path)
		if not KinParts.PRESETS.has(p.preset):
			rep.err(GrammarReport.join(path, "preset"), "unknown preset '%s' (known: %s)" % [p.preset, ", ".join(KinParts.PRESETS.keys())])
		elif not (KinParts.PRESETS[p.preset]["parts"] as Dictionary).has(p.type):
			rep.err(GrammarReport.join(path, "preset"), "preset '%s' doesn't fit a %s (it fills: %s)" % [p.preset, p.type, ", ".join((KinParts.PRESETS[p.preset]["parts"] as Dictionary).keys())])
		else:
			base = KinParts.PRESETS[p.preset]["parts"][p.type]
	for k in defs:
		var src := d if d.has(k) else base
		var val = rep.param(src, k, defs[k], path) if (d.has(k) or base.has(k) or defs[k][3] == null) else defs[k][3]
		p.params[k] = val
		if d.has(k): p.explicit[k] = d[k]
	if kind_ == "effect":
		var tg: Array = tbl[p.type]["targets"]
		p.target = rep.text(d, "target", path, String(tg[0]))
		if not tg.has(p.target):
			rep.err(GrammarReport.join(path, "target"), "a %s can target %s, not '%s'" % [p.type, KinParts._list(tg), p.target])
		_effect_rules(p, path, rep)
	return p

## Rules inside one effect that a plain min/max can't say.
static func _effect_rules(p: PartSpec, path: String, rep: GrammarReport) -> void:
	match p.type:
		"mark":
			if String(p.params["mode"]) == "vulnerable" and float(p.params["amount"]) > 0.35:
				rep.err(GrammarReport.join(path, "amount"), "a vulnerable mark can add at most 0.35 x damage taken, got %s" % KinParts._num(float(p.params["amount"])))
		"buff":
			var st := String(p.params.get("stat", ""))
			if KinParts.BUFF_STATS.has(st):
				var b: Array = KinParts.BUFF_STATS[st]
				var a := float(p.params["amount"])
				if a == 0.0:
					p.params["amount"] = float(b[2])
				elif a < float(b[0]) or a > float(b[1]):
					rep.err(GrammarReport.join(path, "amount"), "a %s buff must be %s to %s %s, got %s" % [st, KinParts._num(float(b[0])), KinParts._num(float(b[1])), b[3], KinParts._num(a)])

func is_hard_cc() -> bool:
	return kind == "effect" and type in ["stun", "root"]

func category() -> String:
	return KinParts.category(type) if kind == "effect" else ""

func cost() -> float:
	return KinParts.cost(kind, type)
