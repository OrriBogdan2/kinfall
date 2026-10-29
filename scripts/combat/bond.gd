class_name Bond
## The bond meter: fighting together fills it. Your hits, your kin's hits, combos and knockouts all
## add to it (numbers in content/rules/bond.json). When it's full, R calls your active kin's
## bond ultimate. It's stored on the hunter as `ult` (0..1).

static func rules() -> Dictionary:
	return Content.rules("bond")

static func add(h: Hunter, amount: float) -> void:
	if h == null or h.out or amount <= 0.0:
		return
	var was := h.ult
	h.ult = minf(1.0, h.ult + amount * (1.3 if h.perk == "overcharge" else 1.0))
	if was < 1.0 and h.ult >= 1.0:
		h.m.on_bond_ready(h)

## Connected to CombatBus.hit_landed by the match.
static func on_hit(attacker: Node, target: Node, amount: float, _tags: Array) -> void:
	if attacker == null or not is_instance_valid(attacker) or target == null:
		return
	var rl := rules()
	var h: Hunter = null
	var rate := 0.0
	if attacker is Hunter:
		h = attacker
		rate = float(rl.get("per_player_dmg", 0.003))
	elif attacker is Kin and (attacker as Kin).owner_h:
		h = (attacker as Kin).owner_h
		rate = float(rl.get("per_kin_dmg", 0.005))
	if h == null or target.team == h.team or not (target is Ent):
		return
	if bool(rl.get("kin_required", true)) and not h.has_kin_ready():
		return
	if target is Mob:
		rate *= float(rl.get("mob_factor", 0.6))     # fighting other hunters fills it faster than farming monsters
	var add_v := minf(amount * rate, float(rl.get("max_per_hit", 0.06)))
	if attacker is Kin and target.hp <= 0.0:
		add_v += float(rl.get("kin_ko", 0.1))
	add(h, add_v)

static func passive(h: Hunter, dt: float) -> void:
	if h.has_kin_ready():
		add(h, float(rules().get("passive_per_sec", 0.003)) * dt)
