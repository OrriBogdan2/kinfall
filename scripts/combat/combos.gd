class_name Combos
## Combos: one fighter sets a foe up with a status, the partner pays it off for bonus damage and bond.
## Each combo is a JSON file in content/combos:
##   setup_by  "kin" | "owner" | "any"     who has to apply the status
##   statuses  ["stun", "root", ...]        which statuses count
##   payoff_by "owner" | "kin" | "kin_ability"   whose next hit cashes it in
##   window    seconds the setup lasts      bonus  damage multiplier      bond  meter it adds
## The match connects CombatBus.status_applied to record(); Ent.hurt asks payoff() on each hit.

static func _role(by: Node) -> String:
	if by is Kin: return "kin"
	if by is Hunter: return "owner"
	return ""

static func _owner(by: Node) -> Node:
	if by is Kin: return (by as Kin).owner_h
	return by if by is Hunter else null

static func record(target: Node, status: String, by: Node, _dur: float) -> void:
	if not (target is Ent) or by == null or not is_instance_valid(by):
		return
	var role := _role(by)
	if role == "":
		return
	var own := _owner(by)
	if own == null:
		return
	var m = target.m
	for c in Content.combos():
		if not (c.get("statuses", []) as Array).has(status):
			continue
		var sb := String(c.get("setup_by", "any"))
		if sb != "any" and sb != role:
			continue
		target.marks[String(c["id"])] = {"team": by.team, "owner": own, "until": float(m.time) + float(c.get("window", 2.5))}

## Called from Ent.hurt before damage lands. Returns the (maybe boosted) damage.
static func payoff(target: Ent, by: Ent, dmg: float, opts: Dictionary) -> float:
	var role := _role(by)
	if role == "":
		return dmg
	var own := _owner(by)
	var m = target.m
	for id in target.marks.keys():
		var mk: Dictionary = target.marks[id]
		if float(mk["until"]) < float(m.time):
			target.marks.erase(id)
			continue
		if int(mk["team"]) != by.team or not is_instance_valid(mk["owner"]) or mk["owner"] != own:
			continue
		var c: Dictionary = {}
		for cc in Content.combos():
			if String(cc["id"]) == id: c = cc; break
		if c.is_empty():
			continue
		var pb := String(c.get("payoff_by", "owner"))
		var ok := pb == role
		if pb == "kin_ability":
			ok = role == "kin" and String(opts.get("ab", "")) in ["k1", "k2"]
		# a status can't pay itself off: the setter needs its partner
		if String(c.get("setup_by", "any")) == role and pb == role:
			ok = false
		if not ok:
			continue
		target.marks.erase(id)
		opts["combo"] = id
		opts["crit"] = true
		if own is Hunter:
			Bond.add(own, float(c.get("bond", 0.06)))
		m.on_combo(target, own, c)
		return dmg * float(c.get("bonus", 1.3))
	return dmg
