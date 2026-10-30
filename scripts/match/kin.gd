class_name Kin
extends Ent
## A kin in a match. It rides on its hunter's shoulder, gets thrown into fights, fights on its own,
## and has a mind: its traits, trust and memories decide whether it obeys, what it calls out, and how brave it is.
##
## Three separate pieces talk through CombatBus signals and plain calls:
##   this body (movement, states, visuals), KinTactics (who to chase, when to use an ability by
##   itself) and an AbilityRunner holding its two abilities (k1 = Q, k2 = V) from content/kin.

var species := "cindle"
var sp: Dictionary = {}
var rec: Dictionary = {}          # the saved record (player kin) or a generated one (bots, wild)
var owner_h: Hunter = null
var unseen := false             # a rival's kin out of the local player's sight
var state := "shoulder"           # shoulder | flying | active | returning | flying_home | fainted | reviving | wild | dazed | bench | fused
var settle := 1.0                 # 0..1 while settling onto the shoulder
var traits := {}
var trust := 50.0
var mood := 0.0
var dmg := 8.0
var speed := 6.5
var atk_cd := 0.0
var lunge_t := 0.0
var target: Ent = null
var fly: Dictionary = {}          # thrown, leaping or rushing
var pend_skill := Vector3.INF     # ability to cast when it lands
var pend_slot := ""
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
var runner: AbilityRunner = null  # its two abilities
var brain: KinTactics = null        # how it fights on its own
var throw_cd := 0.0               # a moment after a recall before it can be thrown again
var shield := 0.0
var shield_t := 0.0
var haste_t := 0.0
var giant: Dictionary = {}        # the giant form of a bond ultimate, while it lasts
var fuse_t := 0.0                 # fused onto its hunter as armor (a bond ultimate)
var fuse_def: UltimateDef = null
var aura_t := 0.0
var lost_from := ""               # a kin left behind by a hunter who went down (name), for tracking
var lost_uid := ""
var ring: MeshInstance3D = null   # the team-coloured ring under it
var shell_fx: Node3D = null       # the glow around its hunter while fused
static var XRAY: Shader = preload("res://shaders/kin_aura_xray.gdshader")

func init_kin(match_node: Node, id: String, species_id: String, record: Dictionary, owner_hunter: Hunter) -> void:
	setup(match_node, id)
	kind = "kin"
	species = species_id if Data.KIN.has(species_id) else "cindle"
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
	if owner_h:
		# how well it's been raised: trained stats, how it's feeling, how close you are
		var cm := Care.match_mods(rec)
		max_hp *= float(cm["hp"]); hp = max_hp
		dmg *= float(cm["dmg"])
		speed *= float(cm["speed"])
		cd_mult *= float(cm["cd"])
		power *= float(cm["skill"])
		mood = float(cm["mood"])
	r = 0.36 * (1.0 + minf(rec.get("forms", []).size() * 0.08, 0.4))
	state = "shoulder" if owner_h else "wild"
	settle = 1.0
	runner = AbilityRunner.new(self)
	var abl: Array = sp.get("abilities", [])
	for i in mini(2, abl.size()):
		runner.set_slot("k%d" % (i + 1), Content.ability(String(abl[i])))
	runner.rate = 1.0 / maxf(0.3, cd_mult)
	brain = KinTactics.new(self)
	set_model(Models.kin(species, rec))
	ring = MeshInstance3D.new()
	ring.mesh = Models.flat_quad(1.0)
	var tc: Color = Data.TEAM_COLORS[team % Data.TEAM_COLORS.size()] if team >= 0 else Color("e8f4ff")
	ring.material_override = Models.ring_mat(Color(tc, 0.85), 0.16)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.top_level = true
	add_child(ring)

func t(k: String) -> float:
	return float(traits.get(k, 0.5))

func is_wild() -> bool:
	return owner_h == null

func hittable() -> bool:
	return not dead and state in ["active", "flying", "returning", "reviving", "wild"] and not (state == "flying" and fly.get("leap", false))

func mass() -> float:
	var g := float(giant.get("scale", 1.0)) if not giant.is_empty() else 1.0
	return (0.8 if species != "pebbit" else 1.4) * g * g

func ability_power() -> float:
	return power * (1.0 + (float(rec.get("level", 1)) - 1.0) * 0.05)

## Can its abilities and ultimate be used right now?
func ready_to_fight() -> bool:
	return not dead and state not in ["fainted", "reviving", "bench", "wild", "dazed", "away"]

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
	if trust >= 90.0:
		return "go"          # soulbound: it goes wherever you send it
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
func throw_to(p: Vector3, slot := "") -> void:
	if state != "shoulder" or dead:
		return
	if hesitate_t > 0.0 or throw_cd > 0.0:
		return
	if settle < 0.35:
		return
	var verdict := consider_throw(p) if owner_h.is_local() or randf() < 0.3 else "go"
	if verdict == "refuse":
		bark("refuse")
		m.sfx("kin_unsure", owner_h.pos, -2.0)
		note("refused", "refused to jump into a fight that looked too dangerous", -1.0)
		return
	if slot != "":
		pend_skill = p
		pend_slot = slot
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
	CombatBus.kin_thrown.emit(self, owner_h)
	if danger_at(tgt) > 1.2 and hp < max_hp * 0.4:
		note("reckless", "was thrown into danger while hurt", -2.0)
	if randf() < 0.35:
		bark("throw")

## Calls it back. It leaps straight to your shoulder, and can't be thrown again for a moment.
func recall() -> void:
	if not giant.is_empty():
		_shrink()
	if state in ["active", "flying", "returning"] and not fly.get("leap", false) and not fly.get("rush", false):
		if state == "active" and t("temper") > 0.72 and target and target.hp < target.max_hp * 0.3 and randf() < 0.6:
			bark("ignore")
			hesitate_t = 0.6
			hesitate_to = Vector3.INF
			return
		var to := Vector2(owner_h.pos.x - pos.x, owner_h.pos.z - pos.z)
		fly = {"from": pos, "to": owner_h.pos + Vector3(0, 1.5, 0), "t": 0.0, "dur": clampf(to.length() / 22.0, 0.15, 0.45), "hit": {}, "leap": true, "home": true}
		state = "flying_home"
		throw_cd = float(Content.rules("kin_ai").get("recall_cooldown", 1.0))
		m.sfx("recall", pos, -6.0)
		CombatBus.kin_recalled.emit(self, owner_h)

## Old name for a kin ability command, kept for older callers.
func command_skill(p: Vector3, slot := "k1") -> void:
	use_ability(slot, p)

## Uses ability k1 or k2 at a spot. Out on the field the kin casts it itself. On your shoulder it
## never leaves you: it lends you the ability and you perform it (its charge moves you, its
## fireball comes from your hands). Only the throw key sends it out.
func use_ability(slot: String, p: Vector3, auto := false) -> bool:
	if runner == null or not runner.is_ready(slot) or not ready_to_fight() or state == "fused":
		return false
	var def := runner.def_of(slot)
	if def.from == "kin":
		if state == "shoulder":
			if auto or owner_h == null:
				return false        # a riding kin never acts on its own
			_cast(slot, p, auto, owner_h)
			return true
		if state in ["returning", "flying_home"]:
			state = "active"
			fly = {}
		if state == "flying":
			pend_skill = p
			pend_slot = slot
			return false
		if def.cast_range > 0.0:
			var dd := Vector2(p.x - pos.x, p.z - pos.z)
			if dd.length() > def.cast_range:
				dd = dd.normalized() * def.cast_range
				p = Vector3(pos.x + dd.x, p.y, pos.z + dd.y)
	_cast(slot, p, auto)
	return true

func _cast(slot: String, p: Vector3, auto := false, through: Node = null) -> void:
	var def := runner.def_of(slot)
	pend_skill = Vector3.INF
	pend_slot = ""
	var dd := Vector2(p.x - pos.x, p.z - pos.z)
	if dd.length() > 0.1 and def.from == "kin" and through == null:
		face = atan2(-dd.x, -dd.y)
	var ctx := {"aim": p, "power": ability_power() * (0.85 if through else 1.0)}
	if through:
		ctx["as"] = through
	runner.use(slot, ctx)
	if model:
		model.set_meta("pulse", Time.get_ticks_msec())
	st_skills += 1
	m.sfx("skill", pos, -2.0 if not auto else -6.0)
	m.on_kin_ability(self, def, auto)

# ------------------------------------------------------------------ ability motion
## A charge along a line (Flare Dash): hits everything it passes through once.
func start_rush(d: Vector2, e: Dictionary, ctx: Dictionary) -> void:
	var dist := float(e.get("distance", 6.0))
	var to := pos
	var k := dist
	while k > 0.5:
		var q := pos + Vector3(d.x, 0, d.y) * k
		if not m.world.is_void(q.x, q.z) and not m.world.is_block(q.x, q.z):
			to = Vector3(q.x, m.world.ground_at(q.x, q.z), q.z); break
		k -= 0.5
	fly = {"from": pos, "to": to, "t": 0.0, "dur": maxf(0.08, pos.distance_to(to) / float(e.get("speed", 22.0))), "hit": {}, "rush": true, "e": e, "ctx": ctx}
	state = "flying"

## A jump onto a spot (Boulder Slam): untouchable in the air, then its landing effects.
func start_leap(to: Vector3, e: Dictionary, ctx: Dictionary) -> void:
	var dd := Vector2(to.x - pos.x, to.z - pos.z)
	if dd.length() > 8.0:
		dd = dd.normalized() * 8.0
		to = Vector3(pos.x + dd.x, 0, pos.z + dd.y)
	var g: float = m.world.ground_at(to.x, to.z)
	to.y = g if g > World.VOID + 1.0 else pos.y
	fly = {"from": pos, "to": to, "t": 0.0, "dur": float(e.get("time", 0.45)), "hit": {}, "leap": true, "height": float(e.get("height", 1.6)),
		"land": e.get("on_land", []), "ctx": ctx}
	state = "flying"

# ------------------------------------------------------------------ bond ultimates
## Armor form: it wraps around its hunter until the time runs out.
func fuse(u: UltimateDef) -> void:
	fuse_def = u
	fuse_t = u.time
	fly = {}
	target = null
	state = "fused"
	teleport(owner_h.pos + Vector3(0, 1.0, 0))
	owner_h.fuse = {"def": u, "t": u.time}
	var om: Dictionary = u.owner_mods
	if float(om.get("shield", 0.0)) > 0.0:
		owner_h.shield = maxf(owner_h.shield, float(om["shield"])); owner_h.shield_t = maxf(owner_h.shield_t, u.time)
	if om.get("refill_dash", false):
		owner_h.dashes = owner_h.max_dashes()
	if shell_fx == null and owner_h.model:
		shell_fx = Models.kin_shell(sp.get("glow", sp["color"]))
		owner_h.add_child(shell_fx)
	m.fx.flash(owner_h.pos + Vector3(0, 1.0, 0), u.color, 1.6, 0.12)

func _sim_fused(dt: float) -> void:
	if owner_h == null or owner_h.out or owner_h.downed:
		_unfuse()
		return
	pos = owner_h.pos + Vector3(0, 1.0, 0)
	prev = pos
	fuse_t -= dt
	var om: Dictionary = fuse_def.owner_mods
	if float(om.get("regen", 0.0)) > 0.0:
		owner_h.hp = minf(owner_h.max_hp, owner_h.hp + float(om["regen"]) * dt)
	_tick_aura(fuse_def, dt)
	if fuse_t <= 0.0:
		_unfuse()

func _unfuse() -> void:
	if fuse_def:
		Effects.run(fuse_def.on_end, self, {"slot": "ult", "ability": fuse_def.id, "power": ability_power()})
	fuse_def = null
	fuse_t = 0.0
	if owner_h:
		owner_h.fuse = {}
	if shell_fx:
		shell_fx.queue_free()
		shell_fx = null
	if state == "fused" and owner_h and not owner_h.out:
		_hop_on()
		m.fx.burst(pos, sp["color"], 16, 3.0)

## Giant form: it grows huge and fights on its own, stomping with every attack.
func grow(u: UltimateDef, aim: Vector3) -> void:
	var gd: Dictionary = u.giant
	if state in ["shoulder", "flying_home", "returning", "flying"]:
		var at := owner_h.pos
		var d := Vector2(aim.x - at.x, aim.z - at.z)
		if d.length() > 3.0: d = d.normalized() * 3.0
		var q := at + Vector3(d.x, 0, d.y)
		if m.world.is_void(q.x, q.z) or m.world.is_block(q.x, q.z):
			q = at
		q.y = m.world.ground_at(q.x, q.z) if not m.world.is_void(q.x, q.z) else at.y
		teleport(q)
		fly = {}
		state = "active"
		grounded = true
		settle = 0.0
	var sc := float(gd.get("scale", 2.2))
	var bonus := float(gd.get("hp", 120.0))
	giant = {"def": u, "t": u.time, "scale": sc, "bonus": bonus, "r": r, "stomp": gd.get("stomp", [])}
	max_hp += bonus
	hp = minf(max_hp, hp + bonus)
	r = r * (0.5 + sc * 0.5)
	m.shake(0.6, pos)
	m.fx.flash(pos + Vector3(0, 1.0, 0), u.color, 2.0, 0.12)
	m.sfx("boom", pos, 0.0, 0.6)

func _shrink() -> void:
	if giant.is_empty():
		return
	var u: UltimateDef = giant["def"]
	Effects.run(u.on_end, self, {"slot": "ult", "ability": u.id, "power": ability_power()})
	max_hp -= float(giant["bonus"])
	hp = minf(hp, max_hp)
	r = float(giant["r"])
	giant = {}
	m.fx.burst(pos + Vector3(0, 0.6, 0), sp["color"], 20, 4.0)

func _tick_aura(u: UltimateDef, dt: float) -> void:
	if u.aura.is_empty():
		return
	aura_t -= dt
	if aura_t <= 0.0:
		aura_t = float(u.aura.get("every", 1.0))
		Effects.run(u.aura.get("effects", []), self, {"slot": "ult", "ability": u.id, "power": ability_power()})

# ------------------------------------------------------------------ the bench (two kin per run)
func bench() -> void:
	if not giant.is_empty(): _shrink()
	if state == "fused": _unfuse()
	state = "bench"
	fly = {}
	target = null
	pend_skill = Vector3.INF

func unbench() -> void:
	state = "shoulder" if hp > 0.0 else "fainted"
	settle = 0.2
	if owner_h:
		pos = owner_h.pos + Vector3(0, 1.5, 0); prev = pos

# ------------------------------------------------------------------ simulation
func sim(dt: float) -> void:
	prev = pos
	if dead:
		return
	if state == "away":
		# your hunter is dead and waiting on a revive: the kin keeps out of sight until then
		if owner_h: pos = owner_h.pos; prev = pos
		return
	tick_status(dt)
	for k in ["atk_cd", "bark_cd", "lunge_t", "throw_cd", "haste_t"]:
		set(k, maxf(0.0, get(k) - dt))
	if shield_t > 0.0:
		shield_t -= dt
		if shield_t <= 0.0: shield = 0.0
	if runner:
		runner.tick(dt)
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
			recall()
	if not giant.is_empty():
		giant["t"] = float(giant["t"]) - dt
		_tick_aura(giant["def"], dt)
		if float(giant["t"]) <= 0.0 or state != "active":
			_shrink()
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
		"fused": _sim_fused(dt)
		"bench":
			if owner_h:
				pos = owner_h.pos; prev = pos
			if hp < max_hp:
				hp = minf(max_hp, hp + max_hp * 0.02 * dt)   # resting in your satchel
	if owner_h and not owner_h.out and state in ["shoulder", "active"] and brain:
		brain.think_abilities(dt)
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
	var rush: bool = fly.get("rush", false)
	var arc := 0.0 if rush else sin(k * PI) * (float(fly.get("height", 1.6)) if fly.get("leap", false) else 0.8)
	pos = a.lerp(b, k) + Vector3(0, arc, 0)
	if rush:
		var e: Dictionary = fly["e"]
		for f in m.foes_of(team):
			if fly["hit"].has(f.nid):
				continue
			if Vector2(f.pos.x - pos.x, f.pos.z - pos.z).length() < f.r + float(e.get("width", 1.0)) and absf(f.pos.y - pos.y) < 1.8:
				fly["hit"][f.nid] = true
				var dirv := Vector2(b.x - a.x, b.z - a.z).normalized()
				var o := {"src": "kin", "ab": String(fly["ctx"].get("slot", "k1")), "tags": [String(fly["ctx"].get("slot", "")), String(fly["ctx"].get("ability", "")), "kin"], "kb": dirv.rotated(PI / 2 * (1.0 if randf() < 0.5 else -1.0)) * float(e.get("kb", 4.0))}
				for st in ["burn", "stun", "slow", "root"]:
					if e.has(st): o[st] = float(e[st])
				f.hurt(float(e.get("dmg", 10.0)) * float(fly["ctx"].get("power", 1.0)), self, o)
		if randf() < 0.6:
			m.fx.burst(pos + Vector3(0, 0.3, 0), Color(String(e.get("color", "#ffffff"))), 3, 1.5, 0.35, -2.0)
	elif not fly.get("leap", false):
		# a thrown kin hits whoever it flies into: damage, a short stun, and an opening for your shots
		for f in m.foes_of(team):
			if fly["hit"].has(f.nid):
				continue
			if Vector2(f.pos.x - pos.x, f.pos.z - pos.z).length() < f.r + 0.5 and absf(f.pos.y + 0.6 - pos.y) < 1.6:
				fly["hit"][f.nid] = true
				var dirv := Vector2(b.x - a.x, b.z - a.z).normalized()
				var extra := {"kb": dirv * 4.0, "stun": 0.6, "src": "throw", "ab": "throw", "tags": ["throw", "kin"]}
				var th: Dictionary = sp.get("throw_hit", {})
				for st in ["burn", "slow", "root"]:
					if th.has(st): extra[st] = float(th[st])
				if th.has("stun"): extra["stun"] = maxf(0.6, float(th["stun"]))
				if th.has("kb"): extra["kb"] = dirv * float(th["kb"])
				f.hurt(16.0 * power, self, extra)
				m.sfx("kinhit", pos, 0.0)
				m.fx.burst(pos, sp["color"], 14, 4.0)
				m.shake(0.25, pos)
				if owner_h and owner_h.is_local():
					m.freeze_frame(0.06)
				target = f
	if k >= 1.0:
		var land: Array = fly.get("land", [])
		var lctx: Dictionary = fly.get("ctx", {})
		var rush_end: Array = fly["e"].get("on_end", []) if rush else []
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
		if not land.is_empty():
			m.fx.dust(pos, 14)
			m.shake(0.35, pos)
			var c2 := lctx.duplicate(); c2["at"] = pos
			Effects.run(land, self, c2)
		if not rush_end.is_empty():
			var c3 := lctx.duplicate(); c3["at"] = pos
			Effects.run(rush_end, self, c3)
		if pend_skill != Vector3.INF and pend_slot != "":
			var ps := pend_slot
			var pp := pend_skill
			pend_slot = ""
			pend_skill = Vector3.INF
			use_ability(ps, pp)

func _sim_fly_home(dt: float) -> void:
	if owner_h == null or owner_h.out:
		return
	fly["t"] += dt
	fly["to"] = owner_h.pos + Vector3(0, 1.5, 0)
	var k := clampf(fly["t"] / fly["dur"], 0.0, 1.0)
	pos = (fly["from"] as Vector3).lerp(fly["to"], k) + Vector3(0, sin(k * PI) * 1.4, 0)
	if k >= 1.0:
		_hop_on()

func walkable_to(p: Vector3) -> bool:
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
	var guard: Ent = _wisp_threat() if owner_h and owner_h.downed else null
	if guard:
		# someone's come to stomp or execute your hunter: the kin goes for them first
		target = guard
	elif owner_h and owner_h.downed:
		_consider_revive(dt)
		if state != "active":
			return
	var big := not giant.is_empty()
	# cautious kin back off to you when they're hurt
	if owner_h and not big and hp < max_hp * brain.retreat_frac():
		if bark_cd <= 0.0:
			bark("scared")
		state = "returning"
		return
	if owner_h and flat_dist(owner_h) > brain.leash() + (6.0 if big else 0.0):
		state = "returning"
		return
	if guard == null and (target == null or target.dead or not target.hittable() or (target is Hunter and target.downed) or flat_dist(target) > brain.chase_range() + 3.0 or randf() < dt * 0.5):
		target = brain.pick_target()
	var wish := Vector2.ZERO
	var spd := speed * (0.6 if slow_t > 0.0 else 1.0) * (1.3 if haste_t > 0.0 else 1.0)
	if big: spd *= float((giant["def"] as UltimateDef).giant.get("speed", 1.0))
	if root_t > 0.0 or stun_t > 0.0:
		spd = 0.0
	if target:
		var to := Vector2(target.pos.x - pos.x, target.pos.z - pos.z)
		var d := to.length()
		var reach: float = sp["range"] + target.r
		if big: reach = float((giant["def"] as UltimateDef).giant.get("range", 2.4)) + target.r
		if d > reach * 0.8:
			wish = to.normalized() * spd
		if d < reach and atk_cd <= 0.0 and absf(target.pos.y - pos.y) < (2.5 if big else 1.5):
			atk_cd = 1.1 if big else 0.95
			lunge_t = 0.15
			vel.x += to.normalized().x * 5.0; vel.z += to.normalized().y * 5.0
			if big:
				var u: UltimateDef = giant["def"]
				m.shake(0.3, pos)
				m.fx.dust(pos, 10)
				target.hurt(dmg * power * float(u.giant.get("dmg", 2.0)), self, {"kb": to.normalized() * 6.0, "src": "kin", "ab": "ult", "tags": ["ult", "kin"]})
				Effects.run(giant["stomp"], self, {"slot": "ult", "ability": u.id, "power": ability_power()})
			else:
				target.hurt(dmg * power, self, {"kb": to.normalized() * 2.0, "src": "kin", "tags": ["kin", "melee"]})
			m.sfx("kinhit", pos, -6.0 if not big else 0.0, 0.7 if big else 1.0)
	elif owner_h:
		# no fight nearby: hang around the owner, closer the more loyal it is
		var to := Vector2(owner_h.pos.x - pos.x, owner_h.pos.z - pos.z)
		if to.length() > brain.idle_radius() + 1.0:
			wish = to.normalized() * spd
		if to.length() > 6.0 and not walkable_to(owner_h.pos):
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
	if not walkable_to(owner_h.pos) or to.length() > 9.0:
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
	if not giant.is_empty(): _shrink()
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
	if not giant.is_empty(): _shrink()
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

## An enemy standing over your downed hunter (to stomp or execute them).
func _wisp_threat() -> Ent:
	if owner_h == null or not owner_h.downed or hp <= 0.0:
		return null
	for f in m.hunters:
		if f.team != owner_h.team and not f.downed and not f.out and f.hittable() and f.flat_dist(owner_h) < 3.0:
			return f
	return null

func _sim_revive(dt: float) -> void:
	var threat := _wisp_threat()
	if threat:
		state = "active"
		target = threat
		bark("owner_down")
		return
	if owner_h == null or not owner_h.downed or owner_h.out:
		state = "active"
		revive_wait = 0.0
		return
	var to := Vector2(owner_h.pos.x - pos.x, owner_h.pos.z - pos.z)
	if to.length() > 1.3:
		if not walkable_to(owner_h.pos):
			pos = owner_h.pos + Vector3(0.6, 0, 0); prev = pos
		_ground_move(to.normalized() * speed * 1.3, dt)
		return
	_ground_move(Vector2.ZERO, dt)
	var speedup := 0.8 + trust / 100.0 * 0.4
	owner_h.revive += dt / Life.R["kin_revive_time"] * speedup
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
	dazed_t = 9.0 if lost_from == "" else 1e9   # a kin left behind waits where it was lost
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
	if state in ["dazed", "bench", "fused"]:
		return 0.0
	if is_wild() and by and by is Hunter:
		angry_at = by
	elif is_wild() and by and by is Kin and by.owner_h:
		angry_at = by.owner_h
	if shield > 0.0 and d > 0.0:
		var soak := minf(shield, d)
		shield -= soak
		d -= soak
		if d <= 0.0:
			flash_t = 0.08
			return 0.0
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
	visible = not dead and state != "bench" and state != "away" and not (owner_h and (owner_h.out or owner_h.extracted or owner_h.riding))
	if not model:
		return
	var body: Node3D = model.get_node("Body")
	var shell: Node3D = model.get_node_or_null("Body/Shell")
	hop_ph += delta * (9.0 if Vector2(vel.x, vel.z).length() > 0.5 else 3.0)
	var out_now := state in ["active", "flying", "returning", "reviving", "flying_home"]
	if ring:
		ring.visible = visible and (out_now or has_meta("lineup")) and not unseen
		if ring.visible:
			var rs := r * 2.6 + 0.3
			ring.global_position = Vector3(global_position.x, m.world.ground_at(global_position.x, global_position.z) + 0.06, global_position.z)
			ring.scale = Vector3.ONE * rs * (1.0 + 0.06 * sin(m.time * 5.0))
	if shell and not has_meta("xr") and m.player:
		# your squad's kin glow through grass and walls, so you never lose track of them
		set_meta("xr", true)
		if team == m.player.team and owner_h:
			var sm0: ShaderMaterial = (shell as MeshInstance3D).material_override
			sm0.shader = XRAY
	if shell:
		var want := 0.0 if state in ["shoulder", "fused"] else (1.0 if not giant.is_empty() else 0.6)
		if state in ["wild", "dazed"]: want = 0.25 if not has_meta("lineup") else 0.6
		shell.set_meta("a", lerpf(float(shell.get_meta("a", 0.0)), want, minf(1.0, delta * 6.0)))
		var sm: ShaderMaterial = (shell as MeshInstance3D).material_override
		sm.set_shader_parameter("strength", float(shell.get_meta("a", 0.0)))
		shell.visible = float(shell.get_meta("a", 0.0)) > 0.02
	var parts: Node = model.get_node_or_null("Aura")
	if parts:
		(parts as CPUParticles3D).emitting = visible and state not in ["shoulder", "bench", "fused"] and not unseen
	if state == "fused" and owner_h and owner_h.model:
		# wrapped around its hunter's back as armor
		global_position = owner_h.model.global_position + Vector3(0, 1.05, 0) + Vector3(sin(owner_h.face), 0, cos(owner_h.face)) * 0.32
		model.rotation.y = owner_h.face
		model.scale = Vector3.ONE * 0.85
		body.position.y = sin(m.time * 6.0) * 0.04
		body.rotation.x = 0.0
		return
	if state == "shoulder" and owner_h and owner_h.model:
		var sh: Node3D = owner_h.model.get_node("Rig/Torso/Shoulder")
		global_position = sh.global_position
		model.rotation.y = owner_h.face
		model.scale = Vector3.ONE * lerpf(0.75, 0.55, settle) * minf(float(model.get_meta("evo_scale", 1.0)), 1.2)
		body.position.y = absf(sin(hop_ph * 0.5)) * 0.03
		body.rotation.x = 0.0
		return
	var gs := 1.0
	if not giant.is_empty():
		var u: UltimateDef = giant["def"]
		var left := float(giant["t"])
		var grow_k := clampf((u.time - left) / 0.35, 0.0, 1.0) * clampf(left / 0.3, 0.0, 1.0)
		gs = lerpf(1.0, float(giant["scale"]), grow_k)
	model.scale = Vector3.ONE * 0.95 * float(model.get_meta("evo_scale", 1.0)) * gs
	model.rotation.y = face
	var moving := Vector2(vel.x, vel.z).length() > 0.5
	body.position.y = absf(sin(hop_ph)) * (0.14 if moving else 0.03) + (0.12 if lunge_t > 0.0 else 0.0)
	var sq := squash
	body.scale = Vector3(1.0 + sq * 0.4, 1.0 - sq * 0.45, 1.0 + sq * 0.4)
	model.set_meta("dazed", state in ["fainted", "dazed"] or stun_t > 0.0)
	if state in ["fainted", "dazed"]:
		body.rotation.z = lerpf(body.rotation.z, 1.4 if state == "fainted" else 0.0, delta * 6.0)
		body.rotation.y += delta * (4.0 if state == "dazed" else 0.0)
	else:
		body.rotation.z = lerpf(body.rotation.z, 0.0, delta * 8.0)
		body.rotation.x = -0.4 if lunge_t > 0.0 else 0.0
	if state == "flying" and not fly.get("rush", false):
		body.rotation.x += delta * 14.0

func _exit_tree() -> void:
	if shell_fx and is_instance_valid(shell_fx):
		shell_fx.queue_free()
