class_name Ultimate
## Bond ultimates (R). The active kin's species names one in its JSON; the definition lives in
## content/ultimates/<id>.json (see UltimateDef). This file only starts it: the kin body runs the
## form (fused armor or giant) and the hunter reads `fuse` for armor bonuses.

static func def_for(k: Kin) -> UltimateDef:
	if k == null:
		return null
	return Content.ultimate(String(Data.KIN[k.species].get("ultimate", "")))

static func can_cast(h: Hunter) -> bool:
	if h == null or h.ult < 1.0 or h.downed or h.out or h.riding or h.dropping:
		return false
	var k: Kin = h.kin
	return k != null and not k.dead and k.state in ["shoulder", "active", "flying", "returning", "flying_home"] and k.giant.is_empty()

static func cast(h: Hunter) -> bool:
	if not can_cast(h):
		return false
	var k: Kin = h.kin
	var u := def_for(k)
	if u == null:
		return false
	h.ult = 0.0
	var aim: Vector3 = h.inp.get("aim", h.pos)
	var ctx := {"slot": "ult", "ability": u.id, "power": k.ability_power(), "aim": aim}
	if u.form == "giant":
		k.grow(u, aim)
	else:
		k.fuse(u)
	Effects.run(u.on_start, k, ctx)
	CombatBus.ability_used.emit(h, u.id, "ult")
	h.m.on_ult(h, k, u)
	return true
