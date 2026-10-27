class_name Kin
extends Ent
## A kin in a match. It rides on its hunter's shoulder, gets thrown into fights, fights on its own,
## and has a mind: its traits, trust and memories decide whether it obeys, what it calls out, and how brave it is.

var species := "cindle"
var sp: Dictionary = {}
var rec: Dictionary = {}          # the saved record (player kin) or a generated one (bots, wild)
var owner_h: Hunter = null
var state := "shoulder"           # shoulder | flying | active | returning | fainted | reviving | wild | dazed
var settle := 1.0                 # 0..1 while settling onto the shoulder
var traits := {}
var trust := 50.0
var mood := 0.0
var dmg := 8.0
var speed := 6.5
var atk_cd := 0.0
var lunge_t := 0.0
var skill_cd := 0.0
var target: Ent = null
var fly: Dictionary = {}          # thrown or leaping arc
var pend_skill := Vector3.INF     # skill to cast when it lands
var faint_t := 0.0
var hesitate_t := 0.0
var hesitate_to := Vector3.INF
var revive_wait := 0.0
var bark_cd := 0.0
var callout_seen := {}
var think_t := 0.0
var hop_ph := 0.0
var home := Vector3.ZERO          # wild kin wander around here
var wander_to := Vector3.INF
var dazed_t := 0.0
var catch_prog := 0.0
var angry_at: Ent = null
var power := 1.0                  # treat bonus
var events := []                  # things that happened this match, written to memory afterwards
var lines := {}                   # personalised barks, if the AI wrote any
var st_hits := 0                  # what it did this match, which shapes how it evolves
var st_kos := 0
var st_throws := 0
var st_skills := 0
var cd_mult := 1.0

func init_kin(match_node: Node, id: String, species_id: String, record: Dictionary, owner_hunter: Hunter) -> void:
	setup(match_node, id)
	kind = "kin"
	species = species_id
	sp = Data.KIN[species]
	rec = record
	owner_h = owner_hunter
	team = owner_hunter.team if owner_hunter else -1
	traits = rec.get("traits", sp["traits"]).duplicate()
	trust = float(rec.get("trust", 50.0))
	var lvl := float(rec.get("level", 1))
	max_hp = float(sp["hp"]) * (1.0 + (lvl - 1.0) * 0.08)
	hp = max_hp
	dmg = float(sp["dmg"]) * (1.0 + (lvl - 1.0) * 0.06)
	speed = float(sp["speed"])
	var em := Evo.mods(rec)
	max_hp *= em["hp"]; hp = max_hp
	dmg *= em["dmg"]
	speed *= em["speed"]
	cd_mult = em["cd"]
	r = 0.36 * (1.0 + minf(rec.get("forms", []).size() * 0.08, 0.4))
	state = "shoulder" if owner_h else "wild"
	settle = 1.0
	set_model(Models.kin(species, rec))

func t(k: String) -> float:
	return float(traits.get(k, 0.5))

func is_wild() -> bool:
	return owner_h == null

func hittable() -> bool:
	return not dead and state in ["active", "flying", "returning", "reviving", "wild"] and not (state == "flying" and fly.get("leap", false))

func mass() -> float:
	return 0.8 if species != "pebbit" else 1.4

# ------------------------------------------------------------------ mind
func courage() -> float:
	return t("bravery") * 1.2 + trust / 100.0 * 1.2 + mood * 0.3

func danger_at(p: Vector3) -> float:
	var d := (1.0 - hp / max_hp) * 2.0
	for f in m.foes_of(team):
		var dist: float = Vector2(f.pos.x - p.x, f.pos.z - p.z).length()
		if dist < 4.5:
			var w := 0.6
			if f is Hunter: w = 1.4
			elif f.kind == "mob" and f.mkind == "brute": w = 2.0
			d += w * (1.0 - dist / 4.5)
	return d

## The owner asks it to jump into a fight. Returns "go", "hesitate" or "refuse".
func consider_throw(p: Vector3) -> String:
	var danger := danger_at(p)
	var c := courage()
	if danger > c + 1.1:
		return "refuse"
	if danger > c + 0.45:
		return "hesitate"
	return "go"

func note(kindk: String, text: String, trust_d := 0.0) -> void:
	events.append({"kind": kindk, "text": text, "trust": trust_d})
	trust = clampf(trust + trust_d, 0.0, 100.0)

func bark(cat: String, extra := "") -> void:
	if bark_cd > 0.0 and cat not in ["refuse", "hesitate", "revive", "callout"]:
		return
	bark_cd = 3.0
	var txt := KinVoice.line(self, cat, extra)
	if txt != "":
		m.kin_bark(self, txt, cat)

# ------------------------------------------------------------------ owner commands
func throw_to(p: Vector3, with_skill := false) -> void:
	if state != "shoulder" or dead:
		return
	if hesitate_t > 0.0:
		return
	if settle < 0.35:
		return
	var verdict := consider_throw(p) if owner_h.is_local() or randf() < 0.3 else "go"
	if verdict == "refuse":
		bark("refuse")
		m.sfx("kin_unsure", owner_h.pos, -2.0)
		note("refused", "refused to jump into a fight that looked too dangerous", -1.0)
		return
	if with_skill:
		pend_skill = p
	if verdict == "hesitate":
		hesitate_t = 0.45
		hesitate_to = p
		bark("hesitate")
		m.sfx("kin_unsure", owner_h.pos, -4.0)
		return
	_launch(p)

func _launch(p: Vector3) -> void:
	st_throws += 1
	var start := owner_h.pos + Vector3(0, 1.5, 0)
	var dist := Vector2(p.x - start.x, p.z - start.z).length()
	var maxd := 9.0
	var d2 := Vector2(p.x - start.x, p.z - start.z)
	if dist > maxd:
		d2 = d2.normalized() * maxd
	var tgt := Vector3(start.x + d2.x, 0.0, start.z + d2.y)
	var g: float = m.world.ground_at(tgt.x, tgt.z)
	tgt.y = g if g > World.VOID + 1.0 else owner_h.pos.y
	var dur := clampf(d2.length() / 16.0, 0.18, 0.55)
	teleport(start)
	fly = {"from": start, "to": tgt, "t": 0.0, "dur": dur, "hit": {}}
	state = "flying"
	settle = 0.0
	m.sfx("throw", owner_h.pos, 0.0)
	if danger_at(tgt) > 1.2 and hp < max_hp * 0.4:
		note("reckless", "was thrown into danger while hurt", -2.0)
	if randf() < 0.35:
		bark("throw")

func recall() -> void:
	if state in ["active", "flying"] and not fly.get("leap", false):
		if state == "active" and t("temper") > 0.72 and target and target.hp < target.max_hp * 0.3 and randf() < 0.6:
			bark("ignore")
			hesitate_t = 0.6
			hesitate_to = Vector3.INF
			return
		state = "returning"
		fly = {}
		m.sfx("recall", pos, -6.0)

func command_skill(p: Vector3) -> void:
	if skill_cd > 0.0 or dead or state in ["fainted", "reviving"]:
		return
	if state == "shoulder":
		throw_to(p, true)
		return
	if state == "returning":
		state = "active"
	cast(p)

# ------------------------------------------------------------------ skills
func cast(p: Vector3) -> void:
	var sk: String = sp["skill"]
	skill_cd = Data.KIN_SKILLS[sk]["cd"] * cd_mult
	st_skills += 1
	pend_skill = Vector3.INF
	m.sfx("skill", pos, 0.0)
	var foes: Array = m.foes_of(team)
	var pw := power * (1.0 + (float(rec.get("level", 1)) - 1.0) * 0.05)
	match sk:
		"fireball":
			var d := Vector2(p.x - pos.x, p.z - pos.z)
			var spd := 13.0
			m.spawn_shot(self, pos + Vector3(0, 0.5, 0), d.normalized() * spd, 22.0 * pw, clampf(d.length(), 1.0, 9.0) / spd, 0.32, Color("ff7a3d"), {"boom": 1.9, "boom_kb": 6.0, "burn": 6.0, "kin": true})
		"wave":
			var d := Vector2(p.x - pos.x, p.z - pos.z).normalized()
			m.fx.cone(pos, d, 5.0, Color("6cc8ff"))
			m.net_fx(["cone", m._r(pos.x), m._r(pos.y), m._r(pos.z), m._r(d.x), m._r(d.y), "6cc8ff"])
			for f in foes:
				var to := Vector2(f.pos.x - pos.x, f.pos.z - pos.z)
				if to.length() < 5.0 and to.normalized().dot(d) > 0.55:
					f.hurt(12.0 * pw, owner_h if owner_h else self, {"kb": d * 10.0, "slow": 1.6, "src": "kin"})
		"snare":
			m.fx.ring(p, 2.2, Color("8fd16a"), 0.5)
			m.net_fx(["ring", m._r(p.x), m._r(p.y), m._r(p.z), 2.2, "8fd16a"])
			m.fx.burst(p + Vector3(0, 0.3, 0), Color("6fbf5a"), 22, 3.0)
			for f in foes:
				if Vector2(f.pos.x - p.x, f.pos.z - p.z).length() < 2.2:
					f.hurt(8.0 * pw, owner_h if owner_h else self, {"root": 1.6, "src": "kin"})
		"chain":
			var hit := []
			var from := pos
			var near := p
			for i in 3:
				var best: Ent = null; var bd := 6.0 if i == 0 else 4.0
				for f in foes:
					if hit.has(f): continue
					var dd: float = Vector2(f.pos.x - near.x, f.pos.z - near.z).length()
					if dd < bd:
						bd = dd; best = f
				if best == null:
					break
				hit.append(best)
				m.fx.bolt(from + Vector3(0, 0.6, 0), best.pos + Vector3(0, 0.8, 0), Color("fff27a"))
				m.net_fx(["bolt", m._r(from.x), m._r(from.y + 0.6), m._r(from.z), m._r(best.pos.x), m._r(best.pos.y + 0.8), m._r(best.pos.z), "fff27a"])
				best.hurt(18.0 * pw, owner_h if owner_h else self, {"stun": 0.4, "src": "kin"})
				from = best.pos; near = best.pos
		"slam":
			var g: float = m.world.ground_at(p.x, p.z)
			var to := Vector3(p.x, g if g > World.VOID + 1.0 else pos.y, p.z)
			var dd := Vector2(to.x - pos.x, to.z - pos.z)
			if dd.length() > 7.0:
				dd = dd.normalized() * 7.0
				to = Vector3(pos.x + dd.x, 0, pos.z + dd.y)
				g = m.world.ground_at(to.x, to.z)
				to.y = g if g > World.VOID + 1.0 else pos.y
			fly = {"from": pos, "to": to, "t": 0.0, "dur": 0.45, "hit": {}, "leap": true, "slam": true}
			state = "flying"
		"gust":
			m.fx.ring(pos, 2.8, Color("d8ccff"), 0.35)
			m.net_fx(["ring", m._r(pos.x), m._r(pos.y), m._r(pos.z), 2.8, "d8ccff"])
			for f in foes:
				var to := Vector2(f.pos.x - pos.x, f.pos.z - pos.z)
				if to.length() < 2.8:
					f.hurt(8.0 * pw, owner_h if owner_h else self, {"kb": to.normalized() * 10.5, "lift": 5.0, "src": "kin"})

func _slam_land() -> void:
	m.fx.ring(pos, 2.0, Color("d8c9b0"), 0.35)
	m.net_fx(["ring", m._r(pos.x), m._r(pos.y), m._r(pos.z), 2.0, "d8c9b0"])
	m.fx.dust(pos, 14)
	m.shake(0.35, pos)
	m.sfx("boom", pos, -4.0)
	for f in m.foes_of(team):
		var to := Vector2(f.pos.x - pos.x, f.pos.z - pos.z)
		if to.length() < 2.0:
			f.hurt(20.0 * power, owner_h if owner_h else self, {"kb": to.normalized() * 10.0, "lift": 6.0, "src": "kin"})

# ------------------------------------------------------------------ simulation
func sim(dt: float) -> void:
	prev = pos
	if dead:
		return
	tick_status(dt)
	for k in ["atk_cd", "skill_cd", "bark_cd", "lunge_t"]:
		set(k, maxf(0.0, get(k) - dt))
	if remote:
		if state != "shoulder":
			net_follow(dt)
		elif owner_h:
			pos = owner_h.pos + Vector3(0, 1.5, 0); prev = pos
		return
	if hesitate_t > 0.0:
		hesitate_t -= dt
		if hesitate_t <= 0.0 and hesitate_to != Vector3.INF and state == "shoulder":
			_launch(hesitate_to)
		elif hesitate_t <= 0.0 and state == "active" and hesitate_to == Vector3.INF:
			state = "returning"
	think_t -= dt
	match state:
		"shoulder": _sim_shoulder(dt)
		"flying": _sim_fly(dt)
		"flying_home": _sim_fly_home(dt)
		"active": _sim_active(dt)
		"returning": _sim_return(dt)
		"fainted": _sim_fainted(dt)
		"reviving": _sim_revive(dt)
		"wild": _sim_wild(dt)
		"dazed": _sim_dazed(dt)
	if owner_h and not owner_h.out and state in ["shoulder", "active", "returning"] and think_t <= 0.0:
		think_t = 0.5
		_callouts()

func _sim_shoulder(dt: float) -> void:
	if owner_h.out or owner_h.extracted:
		return
	pos = owner_h.pos + Vector3(0, 1.5, 0)
	prev = pos
	settle = minf(1.0, settle + dt / 1.0)
	if owner_h.downed:
		_consider_revive(dt)

func _sim_fly(dt: float) -> void:
	fly["t"] += dt
	var k := clampf(fly["t"] / fly["dur"], 0.0, 1.0)
	var a: Vector3 = fly["from"]; var b: Vector3 = fly["to"]
	var arc := sin(k * PI) * (1.6 if fly.get("leap", false) else 0.8)
	pos = a.lerp(b, k) + Vector3(0, arc, 0)
	if not fly.get("leap", false):
		# a thrown kin hits whoever it flies into: damage, a short stun, and an opening for your shots
		for f in m.foes_of(team):
			if fly["hit"].has(f.nid):
				continue
			if Vector2(f.pos.x - pos.x, f.pos.z - pos.z).length() < f.r + 0.5 and absf(f.pos.y + 0.6 - pos.y) < 1.6:
				fly["hit"][f.nid] = true
				var dirv := Vector2(b.x - a.x, b.z - a.z).normalized()
				var extra := {"kb": dirv * (7.0 if species == "pebbit" else 4.0), "stun": 0.6, "src": "throw"}
				match sp["type"]:
					"ember": extra["burn"] = 5.0
					"tide": extra["slow"] = 1.5
					"thorn": extra["root"] = 0.9
					"gale": extra["kb"] = dirv * 8.0
				f.hurt(16.0 * power, owner_h if owner_h else self, extra)
				m.sfx("kinhit", pos, 0.0)
				m.fx.burst(pos, sp["color"], 14, 4.0)
				m.shake(0.25, pos)
				if owner_h and owner_h.is_local():
					m.freeze_frame(0.06)
				target = f
	if k >= 1.0:
		var was_slam: bool = fly.get("slam", false)
		fly = {}
		var g := ground()
		if g <= World.VOID + 1.0:
			pos.y = b.y
			grounded = false
		else:
			pos.y = g
			grounded = true
		vel = Vector3.ZERO
		state = "active"
		if was_slam:
			_slam_land()
		if pend_skill != Vector3.INF:
			cast(pend_skill)

func _sim_fly_home(dt: float) -> void:
	if owner_h == null or owner_h.out:
		return
	fly["t"] += dt
	fly["to"] = owner_h.pos + Vector3(0, 1.5, 0)
	var k := clampf(fly["t"] / fly["dur"], 0.0, 1.0)
	pos = (fly["from"] as Vector3).lerp(fly["to"], k) + Vector3(0, sin(k * PI) * 1.4, 0)
	if k >= 1.0:
		_hop_on()

func _pick_target() -> Ent:
	var reach := 4.0 + t("bravery") * 6.0
	var best: Ent = null; var bs := -1e9
	var attacker: Ent = owner_h.last_hit_by if owner_h else null
	for f in m.foes_of(team):
		if f is Hunter and (f.downed or f.cloak_t > 0.0):
			continue
		var d := flat_dist(f)
		if d > reach:
			continue
		if not _walkable_to(f.pos):
			continue
		var s := -d
		if f == attacker and t("loyalty") > 0.5: s += 4.0
		if f == target: s += 1.5
		if f is Hunter: s += 1.0 * t("temper")
		if s > bs:
			bs = s; best = f
	return best

func _walkable_to(p: Vector3) -> bool:
	var d := Vector2(p.x - pos.x, p.z - pos.z)
	var n := int(d.length() / 0.6) + 1
	for i in range(1, n + 1):
		var q := Vector2(pos.x, pos.z) + d * (float(i) / n)
		if m.world.is_void(q.x, q.y):
			return false
	return absf(p.y - pos.y) < 2.0

func _sim_active(dt: float) -> void:
	if owner_h and (owner_h.out or owner_h.extracted):
		return
	if owner_h and owner_h.downed:
		_consider_revive(dt)
		if state != "active":
			return
	# timid kin retreat when hurt
	if owner_h and hp < max_hp * (0.5 - t("bravery") * 0.35):
		if bark_cd <= 0.0:
			bark("scared")
		state = "returning"
		return
	if owner_h and flat_dist(owner_h) > 15.0:
		state = "returning"
		return
	if target == null or target.dead or not target.hittable() or (target is Hunter and target.downed) or flat_dist(target) > 11.0 or randf() < dt * 0.5:
		target = _pick_target()
	var wish := Vector2.ZERO
	var spd := speed * (0.6 if slow_t > 0.0 else 1.0)
	if root_t > 0.0 or stun_t > 0.0:
		spd = 0.0
	if target:
		var to := Vector2(target.pos.x - pos.x, target.pos.z - pos.z)
		var d := to.length()
		var reach: float = sp["range"] + target.r
		if d > reach * 0.8:
			wish = to.normalized() * spd
		if d < reach and atk_cd <= 0.0 and absf(target.pos.y - pos.y) < 1.5:
			atk_cd = 0.95
			lunge_t = 0.15
			vel.x += to.normalized().x * 5.0; vel.z += to.normalized().y * 5.0
			var hit_dmg := dmg * power
			target.hurt(hit_dmg, owner_h if owner_h else self, {"kb": to.normalized() * 2.0, "src": "kin"})
			m.sfx("kinhit", pos, -6.0)
	elif owner_h:
		# no fight nearby: stay close to the owner
		var to := Vector2(owner_h.pos.x - pos.x, owner_h.pos.z - pos.z)
		if to.length() > 2.5:
			wish = to.normalized() * spd
		if to.length() > 6.0 and not _walkable_to(owner_h.pos):
			state = "returning"
	_ground_move(wish, dt)

func _ground_move(wish: Vector2, dt: float) -> void:
	var hv := Vector2(vel.x, vel.z)
	var k := 12.0 if grounded else 2.0
	if hv.length() > speed * 1.3:
		k = 3.0 if grounded else 0.6
	hv += (wish - hv) * (1.0 - exp(-k * dt))
	# don't walk off edges on purpose
	var ahead := Vector2(pos.x, pos.z) + hv.normalized() * (r + 0.25)
	if grounded and hv.length() <= speed * 1.3 and wish.length() > 0.1 and m.world.is_void(ahead.x, ahead.y):
		hv = Vector2.ZERO
	vel.x = hv.x; vel.z = hv.y
	slide(dt)
	body_vertical(dt)
	if hv.length() > 0.3:
		face = lerp_angle(face, atan2(-hv.x, -hv.y), minf(1.0, dt * 12.0))

func _sim_return(dt: float) -> void:
	if owner_h == null or owner_h.out:
		return
	var to := Vector2(owner_h.pos.x - pos.x, owner_h.pos.z - pos.z)
	if to.length() < 1.2:
		_hop_on()
		return
	if not _walkable_to(owner_h.pos) or to.length() > 9.0:
		# leap straight back to the shoulder
		fly = {"from": pos, "to": owner_h.pos + Vector3(0, 1.5, 0), "t": 0.0, "dur": clampf(to.length() / 18.0, 0.2, 0.6), "hit": {}, "leap": true, "home": true}
		state = "flying_home"
		return
	_ground_move(to.normalized() * speed * 1.25, dt)

func _hop_on() -> void:
	state = "shoulder"
	settle = 0.0
	target = null
	fly = {}
	pos = owner_h.pos + Vector3(0, 1.5, 0)

func _sim_fainted(dt: float) -> void:
	faint_t -= dt
	if not over_void():
		body_vertical(dt)
	if faint_t <= 0.0 and owner_h and not owner_h.out:
		hp = max_hp * 0.5
		_hop_on()
		m.fx.burst(owner_h.pos + Vector3(0, 1.5, 0), sp["color"], 10, 2.0)

func faint(fell := false) -> void:
	state = "fainted"
	faint_t = 8.0
	hp = 0.0
	target = null
	fly = {}
	m.fx.burst(pos + Vector3(0, 0.4, 0), sp["color"], 16, 3.0)
	if owner_h:
		note("fainted", "fainted in a fight" if not fell else "fell off the island", -0.5)
		if fell:
			pos = owner_h.pos
			prev = pos
	m.on_kin_faint(self)

func _on_zero(_by: Ent, _opts: Dictionary) -> void:
	if state in ["dazed", "fainted"]:
		hp = maxf(hp, 1.0)
		return
	if is_wild():
		hp = 1.0
		_daze()
		return
	faint()

func fall_out() -> void:
	if is_wild():
		dead = true
		m.on_fell(self)
		return
	faint(true)

func _consider_revive(dt: float) -> void:
	if state == "fainted" or hp <= 0.0:
		return
	if revive_wait <= 0.0:
		# loyal kin rush in; a kin that doesn't trust you takes a moment
		revive_wait = 0.1 + (1.0 - t("loyalty")) * 1.2 + (1.0 - trust / 100.0) * 1.8
		bark("revive")
	revive_wait -= dt
	if revive_wait > 0.0:
		return
	if state == "shoulder":
		pos = owner_h.pos + Vector3(0.6, 0, 0.3)
		pos.y = owner_h.pos.y
		grounded = true
	state = "reviving"

func _sim_revive(dt: float) -> void:
	if owner_h == null or not owner_h.downed or owner_h.out:
		state = "active"
		revive_wait = 0.0
		return
	var to := Vector2(owner_h.pos.x - pos.x, owner_h.pos.z - pos.z)
	if to.length() > 1.3:
		if not _walkable_to(owner_h.pos):
			pos = owner_h.pos + Vector3(0.6, 0, 0); prev = pos
		_ground_move(to.normalized() * speed * 1.3, dt)
		return
	_ground_move(Vector2.ZERO, dt)
	var speedup := 0.8 + trust / 100.0 * 0.4
	owner_h.revive += dt / Data.MATCH["kin_revive_time"] * speedup
	if owner_h.revive >= 1.0:
		m.revive_hunter(owner_h, self)
		note("revived", "pulled you back up when you were down", 4.0)
		revive_wait = 0.0
		_hop_on()

# ---- wild kin
func _sim_wild(dt: float) -> void:
	var wish := Vector2.ZERO
	if angry_at and (angry_at.dead or flat_dist(angry_at) > 10.0 or (angry_at is Hunter and angry_at.downed)):
		angry_at = null
	if angry_at:
		var to := Vector2(angry_at.pos.x - pos.x, angry_at.pos.z - pos.z)
		if t("bravery") < 0.45:
			wish = -to.normalized() * speed * 0.9  # timid wild kin run away
		else:
			if to.length() > 1.2:
				wish = to.normalized() * speed * 0.85
			elif atk_cd <= 0.0:
				atk_cd = 1.1
				lunge_t = 0.15
				angry_at.hurt(dmg * 0.8, self, {"kb": to.normalized() * 2.0, "src": "kin"})
	else:
		if wander_to == Vector3.INF or flat_dist(wander_to) < 0.5 or randf() < dt * 0.15:
			var a := randf() * TAU
			var q := home + Vector3(cos(a), 0, sin(a)) * randf_range(0.5, 3.5)
			if not m.world.is_void(q.x, q.z) and not m.world.is_block(q.x, q.z):
				wander_to = q
		if wander_to != Vector3.INF:
			var to := Vector2(wander_to.x - pos.x, wander_to.z - pos.z)
			wish = to.normalized() * speed * 0.35
	_ground_move(wish, dt)

func _daze() -> void:
	burn_t = 0.0
	state = "dazed"
	dazed_t = 9.0
	angry_at = null
	m.fx.burst(pos + Vector3(0, 0.8, 0), Color("fff2a0"), 10, 2.0)
	m.on_wild_dazed(self)

func _sim_dazed(dt: float) -> void:
	dazed_t -= dt
	_ground_move(Vector2.ZERO, dt)
	hp = minf(max_hp * 0.25, hp + dt * 0.5)
	if dazed_t <= 0.0:
		state = "wild"
		hp = max_hp * 0.45
		catch_prog = 0.0

func hurt(d: float, by: Ent, opts := {}) -> float:
	if state == "dazed":
		return 0.0
	if is_wild() and by and by is Hunter:
		angry_at = by
	elif is_wild() and by and by.owner_h:
		angry_at = by.owner_h
	return super.hurt(d, by, opts)

# ------------------------------------------------------------------ callouts
func _callouts() -> void:
	var range_c := 13.0 + t("curiosity") * 6.0
	var cam: Node = m.cam
	for f in m.hunters:
		if f.team == team or not f.targetable():
			continue
		var d: float = owner_h.flat_dist(f)
		if d > range_c or callout_seen.has(f.nid) and m.time - float(callout_seen[f.nid]) < 14.0:
			continue
		if owner_h.is_local() and cam and cam.on_screen(f.pos):
			callout_seen[f.nid] = m.time
			continue
		callout_seen[f.nid] = m.time
		if owner_h.is_local():
			bark("callout", m.direction_word(owner_h.pos, f.pos))
			m.ping(f.pos, Color("ff8a6a"))
		return
	for wk in m.kins:
		if not wk.is_wild() or wk.dead or callout_seen.has(wk.nid):
			continue
		if owner_h.flat_dist(wk) < range_c * 0.8:
			callout_seen[wk.nid] = m.time
			if owner_h.is_local():
				bark("wild", Data.KIN[wk.species]["name"])
				m.ping(wk.pos, Color("9fe8ff"))
			return

# ------------------------------------------------------------------ visuals
func render(delta: float, alpha: float) -> void:
	super.render(delta, alpha)
	visible = not dead and not (owner_h and (owner_h.out or owner_h.extracted))
	if not model:
		return
	var body: Node3D = model.get_node("Body")
	hop_ph += delta * (9.0 if Vector2(vel.x, vel.z).length() > 0.5 else 3.0)
	if state == "shoulder" and owner_h and owner_h.model:
		var sh: Node3D = owner_h.model.get_node("Rig/Torso/Shoulder")
		global_position = sh.global_position
		model.rotation.y = owner_h.face
		model.scale = Vector3.ONE * lerpf(0.75, 0.55, settle) * minf(float(model.get_meta("evo_scale", 1.0)), 1.2)
		body.position.y = absf(sin(hop_ph * 0.5)) * 0.03
		body.rotation.x = 0.0
		return
	model.scale = Vector3.ONE * 0.95 * float(model.get_meta("evo_scale", 1.0))
	model.rotation.y = face
	var moving := Vector2(vel.x, vel.z).length() > 0.5
	body.position.y = absf(sin(hop_ph)) * (0.14 if moving else 0.03) + (0.12 if lunge_t > 0.0 else 0.0)
	var sq := squash
	body.scale = Vector3(1.0 + sq * 0.4, 1.0 - sq * 0.45, 1.0 + sq * 0.4)
	if state in ["fainted", "dazed"]:
		body.rotation.z = lerpf(body.rotation.z, 1.4 if state == "fainted" else 0.0, delta * 6.0)
		body.rotation.y += delta * (4.0 if state == "dazed" else 0.0)
	else:
		body.rotation.z = lerpf(body.rotation.z, 0.0, delta * 8.0)
		body.rotation.x = -0.4 if lunge_t > 0.0 else 0.0
	if state == "flying":
		body.rotation.x += delta * 14.0
