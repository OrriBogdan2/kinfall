class_name StageSpec
extends RefCounted
## One step of an ability: a delivery (the shape), the effects it applies to what it touches, the
## modifiers that change how it behaves, and followups that start when a delivery event happens
## ("then": {"on_hit": [stages], "on_land": [...]}). Followups start at "here", where it landed.
##
##   {"delivery": {"type": "projectile", "range": 8},
##    "effects": [{"type": "damage", "amount": 8}, {"type": "stun", "duration": 0.3}],
##    "modifiers": [{"type": "pierce", "count": 2}],
##    "then": {"on_end": [{"delivery": {"type": "burst", "origin": "here", "radius": 1.6}, "effects": [...]}]}}

var delivery: PartSpec
var effects: Array[PartSpec] = []
var modifiers: Array[PartSpec] = []
var then: Dictionary = {}       # event -> Array[StageSpec]

const FIELDS := ["delivery", "effects", "modifiers", "then"]

## depth 1 is a top-level stage; followups are deeper.
static func parse(v: Variant, path: String, rep: GrammarReport, depth := 1) -> StageSpec:
	var s := StageSpec.new()
	var d := rep.obj(v, path)
	if d.is_empty():
		return null
	rep.keys(d, path, FIELDS, ["delivery"])
	if depth > KinParts.MAX_DEPTH:
		rep.err(path, "followups nest %d deep; the most is %d" % [depth, KinParts.MAX_DEPTH])
		return null
	if d.has("delivery"):
		s.delivery = PartSpec.parse("delivery", d["delivery"], GrammarReport.join(path, "delivery"), rep)
	var dt := s.delivery.type if s.delivery else ""
	var effs := rep.arr(d.get("effects", []), GrammarReport.join(path, "effects"))
	if effs.size() > KinParts.MAX_EFFECTS:
		rep.err(GrammarReport.join(path, "effects"), "%d effects; the most in one stage is %d" % [effs.size(), KinParts.MAX_EFFECTS])
	for i in effs.size():
		var ep := GrammarReport.join(GrammarReport.join(path, "effects"), i)
		var e := PartSpec.parse("effect", effs[i], ep, rep)
		if e == null:
			continue
		s.effects.append(e)
		if dt == "wall":
			if not KinParts.WALL_EFFECTS.has(e.type):
				rep.err(ep, "a wall can only carry %s, not %s" % [KinParts._list(KinParts.WALL_EFFECTS), e.type])
			if e.type == "reflect" and not (effs[i] as Dictionary).has("target"):
				e.target = "wall"
		elif e.target == "wall":
			rep.err(GrammarReport.join(ep, "target"), "target 'wall' only makes sense when the delivery is a wall")
	var mods := rep.arr(d.get("modifiers", []), GrammarReport.join(path, "modifiers"))
	if mods.size() > KinParts.MAX_MODIFIERS:
		rep.err(GrammarReport.join(path, "modifiers"), "%d modifiers; the most in one stage is %d" % [mods.size(), KinParts.MAX_MODIFIERS])
	var seen := {}
	for i in mods.size():
		var mp := GrammarReport.join(GrammarReport.join(path, "modifiers"), i)
		var m := PartSpec.parse("modifier", mods[i], mp, rep)
		if m == null:
			continue
		if seen.has(m.type):
			rep.err(mp, "%s is already on this stage; use it once and raise its numbers instead" % m.type)
		seen[m.type] = true
		if dt != "" and not (KinParts.MODIFIERS[m.type]["on"] as Array).has(dt):
			rep.err(mp, "%s doesn't work on a %s (it works on: %s)" % [m.type, dt, ", ".join(KinParts.MODIFIERS[m.type]["on"])])
		s.modifiers.append(m)
	if d.has("then"):
		var tp := GrammarReport.join(path, "then")
		var th := rep.obj(d["then"], tp)
		var evs: Array = KinParts.DELIVERIES[dt]["events"] if dt != "" else []
		for ev in th:
			if not evs.has(ev):
				rep.err(GrammarReport.join(tp, ev), ("a %s has no '%s' event (it has: %s)" % [dt, ev, ", ".join(evs)]) if not evs.is_empty() else "a %s has no followup events" % dt)
				continue
			var list := rep.arr(th[ev], GrammarReport.join(tp, ev))
			var out: Array = []
			for i in list.size():
				var sub := StageSpec.parse(list[i], GrammarReport.join(GrammarReport.join(tp, ev), i), rep, depth + 1)
				if sub: out.append(sub)
			s.then[ev] = out
	if s.delivery:
		s._rules(path, rep, depth)
	return s

## Rules across the parts of one stage.
func _rules(path: String, rep: GrammarReport, depth: int) -> void:
	var dt := delivery.type
	if String(delivery.params.get("origin", "")) == "here" and depth == 1:
		rep.err(GrammarReport.join(path, "delivery.origin"), "'here' is where the previous stage landed, so it only works in a followup (then)")
	if effects.is_empty() and then.is_empty() and not KinParts.SELF_SUFFICIENT.has(dt):
		rep.err(path, "this %s has no effects and no followups, so it does nothing" % dt)
	if dt in ["burst", "zone", "aura"] and float(delivery.params.get("radius", 0.0)) > KinParts.BIG_RADIUS:
		for e in effects:
			if e.category() != "utility":
				rep.err(GrammarReport.join(path, "delivery.radius"), "areas wider than %sm may only carry utility effects (mark, buff), but this one has %s" % [KinParts._num(KinParts.BIG_RADIUS), e.type])
				break
	var lingers := has_modifier("linger")
	for e in effects:
		if e.is_hard_cc() and lingers:
			rep.err(path, "linger can't repeat %s (hard crowd control); use slow in a lingering patch" % e.type)
			break
	# the most units one cast of this stage can touch
	var n := 1.0
	for m in modifiers:
		match m.type:
			"split": n *= float(m.params["count"])
			"bounce", "chain", "pierce": n *= 1.0 + float(m.params["count"])
	if n > float(KinParts.MAX_HITS):
		rep.err(GrammarReport.join(path, "modifiers"), "split, bounce, chain and pierce together could hit %d foes; the cap is %d" % [int(n), KinParts.MAX_HITS])

func has_modifier(t: String) -> bool:
	for m in modifiers:
		if m.type == t: return true
	return false

func modifier(t: String) -> PartSpec:
	for m in modifiers:
		if m.type == t: return m
	return null

## Every stage in this tree, this one first.
func walk() -> Array[StageSpec]:
	var out: Array[StageSpec] = [self]
	for ev in then:
		for s in then[ev]:
			out.append_array((s as StageSpec).walk())
	return out

## Placeholder power: the sum of part costs (Phase 3 prices parameters too).
func cost() -> float:
	var c := delivery.cost() if delivery else 0.0
	for e in effects: c += e.cost()
	for m in modifiers: c += m.cost()
	for ev in then:
		for s in then[ev]: c += (s as StageSpec).cost()
	return c
