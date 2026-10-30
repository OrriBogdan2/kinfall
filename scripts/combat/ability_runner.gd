class_name AbilityRunner
extends RefCounted
## Runs a set of ability slots for one fighter (a hunter now, kin later): charges, cooldowns,
## and casting through Effects. It knows nothing about who owns it beyond "a body that can cast".

var caster: Node = null
var slots := {}                # slot -> {def: AbilityDef, charges: float, cd: float}
var rate := 1.0                # cooldown speed (gear, buffs)

func _init(owner_node: Node = null) -> void:
	caster = owner_node

func set_slot(slot: String, def: AbilityDef) -> void:
	if def == null:
		slots.erase(slot)
		return
	slots[slot] = {"def": def, "charges": float(def.charges), "cd": 0.0}

func has_slot(slot: String) -> bool:
	return slots.has(slot)

func def_of(slot: String) -> AbilityDef:
	return slots[slot]["def"] if slots.has(slot) else null

func is_ready(slot: String) -> bool:
	return slots.has(slot) and float(slots[slot]["charges"]) >= 1.0

func charges(slot: String) -> int:
	return int(floor(float(slots[slot]["charges"]))) if slots.has(slot) else 0

## Seconds until the next charge comes back (0 when full).
func cd_left(slot: String) -> float:
	return float(slots[slot]["cd"]) if slots.has(slot) else 0.0

func cd_frac(slot: String) -> float:
	if not slots.has(slot) or is_ready(slot):
		return 0.0
	var d: AbilityDef = slots[slot]["def"]
	return clampf(float(slots[slot]["cd"]) / maxf(0.01, d.cooldown * float(slots[slot].get("cd_k", 1.0))), 0.0, 1.0)

## The full cooldown of a slot at its current rank.
func cd_max(slot: String) -> float:
	if not slots.has(slot):
		return 0.0
	return (slots[slot]["def"] as AbilityDef).cooldown * float(slots[slot].get("cd_k", 1.0))

func use(slot: String, ctx := {}) -> bool:
	if not is_ready(slot):
		return false
	var s: Dictionary = slots[slot]
	var d: AbilityDef = s["def"]
	s["charges"] = float(s["charges"]) - 1.0
	# a higher rank (ctx.level) recharges faster: 10% per rank past the first
	s["cd_k"] = clampf(1.0 - 0.1 * (float(ctx.get("level", 1)) - 1.0), 0.5, 1.0)
	if float(s["cd"]) <= 0.0:
		s["cd"] = d.cooldown * float(s["cd_k"])
	var c := ctx.duplicate()
	c["slot"] = slot
	c["ability"] = d.id
	# "as": someone else performs it (a kin on your shoulder lends you its ability)
	var who: Node = c.get("as", caster)
	c.erase("as")
	Effects.run(d.effects, who, c)
	CombatBus.ability_used.emit(who, d.id, slot)
	return true

func tick(dt: float) -> void:
	for slot in slots:
		var s: Dictionary = slots[slot]
		var d: AbilityDef = s["def"]
		if float(s["charges"]) >= d.charges:
			s["cd"] = 0.0
			continue
		s["cd"] = float(s["cd"]) - dt * rate
		if float(s["cd"]) <= 0.0:
			s["charges"] = minf(float(d.charges), float(s["charges"]) + 1.0)
			s["cd"] = d.cooldown * float(s.get("cd_k", 1.0)) if float(s["charges"]) < d.charges else 0.0

func reset() -> void:
	for slot in slots:
		slots[slot]["charges"] = float((slots[slot]["def"] as AbilityDef).charges)
		slots[slot]["cd"] = 0.0
