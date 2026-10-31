class_name Boss
extends Mob
## A lair boss (see Lairs). Sleeps until someone walks into its opened lair, then fights everyone
## inside: rival squads, kin, whoever crashes in. Every attack is telegraphed on the ground first.
## Three phases (the second at 66% health, the third at 33%) each add or sharpen an attack, and after
## its enrage timer it hits harder and faster. It never leaves its lair; if the lair empties it goes
## back to sleep and heals.
##
##   Stone Colossus  slams that send out shockwave rings (jump them), thrown boulders, ground fissures;
##                   rockfall on each phase change
##   Stormcoil       circles you and lunges along a telegraphed line, calls lightning on marked
##                   circles, coils up and discharges; a lightning storm on each phase change
##   Brood Mother    spits fans of acid, lobs acid that leaves burning puddles, lays egg sacs that
##                   hatch into adds, burrows and bursts up under you; a brood of adds on each phase

var lair: Dictionary = {}
var dormant := true
var phase := 0
var invul_t := 0.0
var awake_t := 0.0
var empty_t := 0.0
var enraged := false
var atk := ""
var atk_t := 0.0
var atk_end := 0.0
var steps: Array = []        # {t, f: Callable, done} for the attack under way
var next_cd := 2.0
var teles: Array = []        # {n, t, dur}: telegraphs filling on match time
var hazards: Array = []      # lingering ground hazards {at, r, until, every, next, dmg, slow, n}
var flying: Array = []       # boulders and globs in the air {from, to, t, dur, n, r, dmg, col, on_land}
var waves: Array = []        # expanding shockwave rings {at, r, speed, max, hit, n, dmg}
var trail: Array = []        # the serpent's path: newest first
var dash_v := Vector2.ZERO
var dash_t := 0.0
var dash_hit := {}
var buried := false
var anim_kind := ""          # what the model is doing: slam, throw, roar, spit, dash, burrow
var anim_k := 0.0
var damage_by := {}          # team -> damage dealt, for credit
var orbit := 1.0

const COL := {"colossus": Color("ffb04a"), "serpent": Color("7fe8ff"), "brood": Color("b6ff6a")}

func init_boss(match_node: Node, id: String, k: String, at: Vector3, tier_k: float, L: Dictionary) -> void:
	init_mob(match_node, id, k, at, tier_k)
	md = md.duplicate()          # per-boss tuning (the windup the model scrubs to, and so on)
	lair = L
	st = "idle"
	orbit = 1.0 if randf() < 0.5 else -1.0
	if stag_ring:
		stag_ring.mesh = Models.flat_quad(r * 2.0 + 2.4)

func mass() -> float:
	return 80.0

func col() -> Color:
	return COL.get(mkind, Color("ff6a4a"))

## How big a hit it lands, after the tier, its enrage and phase.
func dmg(base: float) -> float:
	return base * dmg_mult * (1.5 if enraged else 1.0) * (1.0 + 0.1 * phase)

func cd_k() -> float:
	return (0.6 if enraged else 1.0) * (1.0 - 0.12 * phase)

func hurt(d: float, by: Ent, opts := {}) -> float:
	if dead or buried:
		return 0.0
	if dormant:
		if String(lair.get("state", "")) in ["open", "awake"] and m.lairs:
			m.lairs.wake(lair, by)
		else:
			return 0.0
	if invul_t > 0.0:
		d *= 0.15
	var real: Ent = by
	if by is Kin and (by as Kin).owner_h: real = (by as Kin).owner_h
	var dealt := super.hurt(d, by, opts)
	if real and dealt > 0.0:
		damage_by[real.team] = float(damage_by.get(real.team, 0.0)) + dealt
	return dealt

func _on_zero(by: Ent, opts: Dictionary) -> void:
	_clear_attack()
	for hz in hazards: _free(hz.get("n"))
	for f in flying: _free(f.get("n"))
	for wv in waves: _free(wv.get("n"))
	hazards.clear(); flying.clear(); waves.clear()
	super._on_zero(by, opts)

func _free(n) -> void:
	if n != null and is_instance_valid(n):
		(n as Node).queue_free()

# ------------------------------------------------------------------ the arena
func centre() -> Vector3:
	return lair.get("c", camp)

func _inside(p: Vector3, pad := 0.0) -> bool:
	var c: Vector3 = centre()
	var hf := float(lair.get("half", 7)) - 0.5 + pad
	return absf(p.x - c.x) <= hf and absf(p.z - c.z) <= hf

## A point kept on the arena floor, clear of the walls.
func clamp_in(p: Vector3, margin := 1.3) -> Vector3:
	var c: Vector3 = centre()
	var hf := float(lair.get("half", 7)) - 0.5 - margin
	return Vector3(clampf(p.x, c.x - hf, c.x + hf), c.y, clampf(p.z, c.z - hf, c.z + hf))

## Everyone it fights: anyone inside the lair (hunters, active kin), whoever they are.
func foes_inside() -> Array:
	var out: Array = []
	for f in m.foes_of(team):
		if f is Mob: continue
		if _inside(f.pos, 0.4): out.append(f)
	return out

func _pick_target() -> Ent:
	var best: Ent = null; var bs := -1e9
	for f in foes_inside():
		if f is Hunter and not (f as Hunter).targetable(): continue
		var s := 20.0 - flat_dist(f) + (5.0 if f == tgt else 0.0) + (3.0 if f is Hunter else 0.0)
		if f == last_hit_by: s += 4.0
		if s > bs: bs = s; best = f
	return best

# ------------------------------------------------------------------ telegraphs and hits on match time
func _tele_c(at: Vector3, rad: float, c: Color, dur: float) -> Node3D:
	var n: Node3D = m.fx.telegraph_circle(at, rad, c)
	teles.append({"n": n, "t": 0.0, "dur": dur})
	return n

func _tele_r(at: Vector3, d: Vector2, length: float, width: float, c: Color, dur: float) -> Node3D:
	var n: Node3D = m.fx.telegraph_rect(at, d, length, width, c)
	teles.append({"n": n, "t": 0.0, "dur": dur})
	return n

func _tick_teles(dt: float) -> void:
	for t in teles.duplicate():
		t["t"] = float(t["t"]) + dt
		var n = t["n"]
		if n == null or not is_instance_valid(n):
			teles.erase(t); continue
		m.fx.telegraph_progress(n, float(t["t"]) / maxf(0.01, float(t["dur"])))
		if float(t["t"]) >= float(t["dur"]):
			m.fx.end_telegraph(n)
			teles.erase(t)

func _hits(f: Ent, at: Vector3, rad: float, dy := 1.8) -> bool:
	return Vector2(f.pos.x - at.x, f.pos.z - at.z).length() < rad + f.r and absf(f.pos.y - at.y) < dy

## A blast on the ground: hurts and throws everyone in it.
func blast(at: Vector3, rad: float, base: float, kb := 7.0, lift := 4.0, extra := {}) -> void:
	var c := col()
	m.fx.ring(at, rad, c.lightened(0.3), 0.32)
	m.fx.burst(at + Vector3(0, 0.4, 0), c, int(clampf(rad * 8.0, 10.0, 34.0)), 6.0, 0.5, 6.0, 1.3)
	m.fx.dust(at, 12)
	m.shake(0.35 if rad < 3.0 else 0.55, at)
	for f in m.foes_of(team):
		if f is Mob: continue
		if _hits(f, at, rad):
			var rel := Vector2(f.pos.x - at.x, f.pos.z - at.z)
			var o := {"kb": (rel.normalized() if rel.length() > 0.05 else Vector2.RIGHT) * kb, "lift": lift, "src": "mob"}
			for k in extra: o[k] = extra[k]
			f.hurt(dmg(base), self, o)

## Along a line from a point: everyone within width/2 of it.
func line_hit(a: Vector3, d: Vector2, length: float, width: float, base: float, kb := 6.0, extra := {}) -> void:
	for f in m.foes_of(team):
		if f is Mob: continue
		var rel := Vector2(f.pos.x - a.x, f.pos.z - a.z)
		var along := rel.dot(d)
		if along < -0.5 or along > length + 0.5: continue
		var side := rel.dot(Vector2(-d.y, d.x))
		if absf(side) > width * 0.5 + f.r or absf(f.pos.y - a.y) > 1.8: continue
		var o := {"kb": Vector2(-d.y, d.x) * signf(side if side != 0.0 else 1.0) * kb + d * 2.0, "lift": 3.0, "src": "mob"}
		for k in extra: o[k] = extra[k]
		f.hurt(dmg(base), self, o)

# ------------------------------------------------------------------ the loop
func sim(dt: float) -> void:
	prev = pos
	if dead:
		return
	tick_status(dt)
	_tick_teles(dt)
	_tick_hazards(dt)
	_tick_flying(dt)
	_tick_waves(dt)
	if remote:
		net_follow(dt)
		return
	if dormant:
		# asleep: breathing, healing back to full, waiting
		hp = minf(max_hp, hp + max_hp * 0.08 * dt)
		vel = Vector3.ZERO
		anim_kind = ""
		body_vertical(dt)
		return
	awake_t += dt
	if invul_t > 0.0: invul_t -= dt
	if md.get("stag", false):
		_tick_stagger(dt)
	# phases at 66% and 33%
	var want := 0 if hp > max_hp * 0.66 else (1 if hp > max_hp * 0.33 else 2)
	if want > phase:
		_phase_up(want)
	if not enraged and awake_t >= float(md.get("enrage", 150.0)):
		enraged = true
		m.lairs.on_enrage(self)
	# nobody left inside: back to sleep after a while
	var inside := foes_inside()
	if inside.is_empty():
		empty_t += dt
		if empty_t > 12.0:
			m.lairs.reset_boss(self)
			return
	else:
		empty_t = 0.0
	if tgt == null or tgt.dead or not tgt.hittable() or not _inside(tgt.pos, 0.6) or randf() < dt * 0.6:
		tgt = _pick_target()
	cd -= dt
	next_cd -= dt
	var spd: float = float(md["speed"]) * (1.25 if enraged else 1.0) * (0.55 if slow_t > 0.0 else 1.0)
	var wish := Vector2.ZERO
	if stun_t > 0.0 or stagger_t > 0.0:
		if atk != "" and stagger_t > 0.0: _clear_attack()
		spd = 0.0
	elif atk != "":
		atk_t += dt
		for s in steps:
			if not s["done"] and atk_t >= float(s["t"]):
				s["done"] = true
				(s["f"] as Callable).call()
				if dead or atk == "": break
		if atk != "" and atk_t >= atk_end:
			_end_attack()
		wish = _attack_move(spd)
	elif tgt:
		wish = _roam(spd)
		if next_cd <= 0.0:
			_choose_attack()
	else:
		wish = dir_to(centre()) * spd * 0.5 if flat_dist(centre()) > 1.5 else Vector2.ZERO
	st = "windup" if anim_kind in ["slam", "throw", "spit", "roar"] else "chase"
	if dash_t > 0.0:
		dash_t -= dt
		vel.x = dash_v.x; vel.z = dash_v.y
		_dash_hits()
	else:
		var hv := Vector2(vel.x, vel.z)
		hv += (wish - hv) * (1.0 - exp(-8.0 * dt))
		vel.x = hv.x; vel.z = hv.y
	slide(dt)
	# never out of its lair
	var cl := clamp_in(pos, r * 0.6)
	if absf(cl.x - pos.x) > 0.001 or absf(cl.z - pos.z) > 0.001:
		pos.x = cl.x; pos.z = cl.z
		if dash_t > 0.0: dash_t = 0.0
	body_vertical(dt)
	var look := Vector2(vel.x, vel.z)
	if tgt and (atk != "" or look.length() < 0.5) and dash_t <= 0.0:
		look = dir_to(tgt)
	if look.length() > 0.1:
		face = lerp_angle(face, atan2(-look.x, -look.y), minf(1.0, dt * (12.0 if mkind == "serpent" else 5.0)))
	if mkind == "serpent":
		_trail_push()

func _roam(spd: float) -> Vector2:
	var d := flat_dist(tgt)
	var to := dir_to(tgt)
	match mkind:
		"colossus":
			return to * spd if d > 3.0 else Vector2.ZERO
		"brood":
			if d > 8.0: return to * spd
			if d < 4.0: return -to * spd * 0.8
			return Vector2(-to.y, to.x) * orbit * spd * 0.4
		"serpent":
			# circles its target at a lunge's length, weaving
			var rad := 5.5 + sin(awake_t * 0.7) * 1.2
			var side := Vector2(-to.y, to.x) * orbit
			return (side + to * clampf((d - rad) * 0.5, -1.0, 1.0)).normalized() * spd
	return Vector2.ZERO

func _attack_move(spd: float) -> Vector2:
	if mkind == "serpent" and atk == "storm" and tgt:
		return Vector2(-dir_to(tgt).y, dir_to(tgt).x) * orbit * spd * 0.6
	if mkind == "brood" and atk == "spit" and tgt:
		return Vector2.ZERO
	return Vector2.ZERO

# ------------------------------------------------------------------ attacks
func _begin(name: String, length: float, anim := "") -> void:
	atk = name; atk_t = 0.0; atk_end = length; steps = []
	anim_kind = anim; anim_k = 0.0
	m.sfx("v_warden", pos, -2.0, {"colossus": 0.6, "serpent": 1.35, "brood": 0.9}.get(mkind, 1.0))

func _at(t: float, f: Callable) -> void:
	steps.append({"t": t, "f": f, "done": false})

func _end_attack() -> void:
	atk = ""
	anim_kind = ""
	next_cd = float(md["cd"]) * cd_k() * randf_range(0.85, 1.15)

func _clear_attack() -> void:
	for t in teles:
		if t["n"] != null and is_instance_valid(t["n"]): m.fx.end_telegraph(t["n"])
	teles.clear()
	steps.clear()
	atk = ""
	anim_kind = ""
	dash_t = 0.0
	if buried: _surface()

func _choose_attack() -> void:
	var opts: Array = []
	var d := flat_dist(tgt)
	match mkind:
		"colossus":
			if d < 5.0: opts += ["slam", "slam"]
			opts.append("boulders")
			if phase >= 1: opts.append("fissure")
		"serpent":
			opts += ["dash", "storm"]
			if phase >= 1: opts.append("static")
			if d > 6.0: opts.append("dash")
		"brood":
			opts += ["spit", "lob"]
			if m.lairs.adds_alive(lair) < 3 + phase * 2: opts.append("brood")
			if phase >= 1: opts.append("burrow")
	# never the same attack twice in a row, so a fight reads as a rhythm, not a loop
	var last := String(get_meta("last_atk", ""))
	var pool: Array = opts.filter(func(o): return o != last)
	if pool.is_empty(): pool = opts
	var pick: String = pool[randi() % pool.size()]
	set_meta("last_atk", pick)
	if OS.get_cmdline_user_args().has("--boss-debug"): print("BOSSDBG %s t=%.1f %s from %s d=%.1f" % [mkind, awake_t, pick, str(opts), d])
	call("_atk_" + pick)

func _wind() -> float:
	return float(md["windup"]) * (0.8 if enraged else 1.0) * (1.0 - 0.1 * phase)

# ---- the Stone Colossus
func _atk_slam() -> void:
	var w := _wind()
	md["windup"] = w
	var d := dir_to(tgt) if tgt else Vector2(0, 1)
	var at := clamp_in(pos + Vector3(d.x, 0, d.y) * 1.2, 0.5)
	at.y = centre().y
	_begin("slam", w + 0.6, "slam")
	_tele_c(at, float(md["slam_r"]), Color("ff4a3a"), w)
	# the purple stagger window opens on every slam
	if stagger_t <= 0.0:
		if stag_open <= 0.0: m.on_stag_open(self)
		stag_open = maxf(stag_open, w + 0.15)
	_at(w, func():
		blast(at, float(md["slam_r"]), float(md["dmg"]), 9.0, 5.0)
		m.sfx("k_gravity", at, 2.0, 0.6)
		_wave(at, 9.5, 7.5)
		if phase >= 1: m.later(0.45, func(): if not dead: _wave(at, 10.5, 8.5))
		if phase >= 2: m.later(0.9, func(): if not dead: _wave(at, 11.0, 9.5)))

func _wave(at: Vector3, max_r: float, speed: float) -> void:
	var n := MeshInstance3D.new()
	n.mesh = Models.flat_quad(2.0)
	n.material_override = Models.ring_mat(Color(1.0, 0.62, 0.3, 0.95), 0.06)
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.add_child(n)
	n.global_position = at + Vector3(0, 0.1, 0)
	waves.append({"at": at, "r": 0.6, "speed": speed, "max": max_r, "hit": {}, "n": n})

func _tick_waves(dt: float) -> void:
	for wv in waves.duplicate():
		wv["r"] = float(wv["r"]) + float(wv["speed"]) * dt
		var n: MeshInstance3D = wv["n"]
		if is_instance_valid(n):
			n.scale = Vector3.ONE * float(wv["r"])
		var at: Vector3 = wv["at"]
		for f in m.foes_of(team):
			if f is Mob or (wv["hit"] as Dictionary).has(f.nid): continue
			var dd := Vector2(f.pos.x - at.x, f.pos.z - at.z).length()
			# the ring rolls along the ground: jump over it (or dash through it) and it misses
			if absf(dd - float(wv["r"])) < 0.45 + f.r and f.pos.y - f.ground() < 0.45 and absf(f.pos.y - at.y) < 1.2:
				if f is Hunter and ((f as Hunter).roll_t > 0.0): continue
				wv["hit"][f.nid] = true
				f.hurt(dmg(12.0), self, {"kb": Vector2(f.pos.x - at.x, f.pos.z - at.z).normalized() * 6.0, "lift": 3.5, "src": "mob"})
		if float(wv["r"]) >= float(wv["max"]):
			_free(n)
			waves.erase(wv)

func _atk_boulders() -> void:
	var w := 0.85
	md["windup"] = w
	_begin("boulders", w + 1.6, "throw")
	var n := 1 + phase
	var picks: Array = foes_inside()
	picks.shuffle()
	for i in n:
		var f: Ent = picks[i % picks.size()] if not picks.is_empty() else tgt
		var aim := pos if f == null else f.pos + Vector3(f.vel.x, 0, f.vel.z) * 0.6
		var to := clamp_in(aim + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * (0.6 * i), 0.4)
		to.y = centre().y
		var delay := w + i * 0.25
		_tele_c(to, 1.9, Color("ff6a3a"), delay + 1.0)
		_at(delay, func(): _throw(to, 1.0, 1.9, 20.0, Color("9c968a"), "boulder"))

func _throw(to: Vector3, dur: float, rad: float, base: float, c: Color, what: String) -> void:
	var n := Node3D.new()
	if what == "boulder":
		Models.part(n, Models.sphere(0.55, 7), Models.toon(c), Vector3.ZERO, Vector3(1.1, 0.9, 1.0))
		Models.part(n, Models.sphere(0.3, 6), Models.toon(Color("6f9a4a"), false), Vector3(0, 0.4, 0), Vector3(1.3, 0.4, 1.1))
	else:
		Models.part(n, Models.sphere(0.32, 8), Models.toon(c, false, 1.0), Vector3.ZERO)
	m.add_child(n)
	var from := pos + Vector3(0, 3.6 if mkind == "colossus" else 2.0, 0)
	n.global_position = from
	m.sfx("throw", pos, 0.0, 0.6)
	flying.append({"from": from, "to": to, "t": 0.0, "dur": dur, "n": n, "r": rad, "dmg": base, "what": what})

func _tick_flying(dt: float) -> void:
	for f in flying.duplicate():
		f["t"] = float(f["t"]) + dt
		var k := clampf(float(f["t"]) / float(f["dur"]), 0.0, 1.0)
		var a: Vector3 = f["from"]; var b: Vector3 = f["to"]
		var p := a.lerp(b, k) + Vector3(0, 4.0 * k * (1.0 - k) * 3.5, 0)
		if is_instance_valid(f["n"]):
			(f["n"] as Node3D).global_position = p
			(f["n"] as Node3D).rotation.x += dt * 6.0
		if k >= 1.0:
			_free(f["n"])
			flying.erase(f)
			if f["what"] == "boulder":
				blast(b, float(f["r"]), float(f["dmg"]), 6.0, 4.0, {"stun": 0.3})
				m.sfx("boom", b, -2.0, 0.7)
			else:
				m.fx.burst(b + Vector3(0, 0.3, 0), col(), 20, 4.0, 0.5, 5.0)
				m.sfx("k_spore", b, -2.0, 0.7)
				_puddle(b, float(f["r"]), 5.0)

func _atk_fissure() -> void:
	var w := _wind() * 0.9
	md["windup"] = w
	_begin("fissure", w + 0.5, "slam")
	var d := dir_to(tgt) if tgt else Vector2(0, 1)
	var a := Vector3(pos.x, centre().y, pos.z)
	_tele_r(a, d, 12.0, 2.4, Color("ff4a3a"), w)
	_at(w, func():
		line_hit(a, d, 12.0, 2.4, 22.0, 4.0, {"lift": 7.0})
		for i in 6:
			var q := a + Vector3(d.x, 0, d.y) * (1.0 + i * 2.0)
			m.fx.burst(q + Vector3(0, 0.3, 0), Color("ffb04a"), 10, 5.0, 0.5, 8.0, 1.2)
			m.fx.dust(q, 6)
		m.shake(0.5, a)
		m.sfx("k_gravity", a, 0.0, 0.5))

# ---- Stormcoil
func _atk_dash() -> void:
	var w := _wind()
	md["windup"] = w
	var n := 1 + phase
	_begin("dash", n * (w + 0.55) + 0.2, "dash")
	for i in n:
		var t0 := i * (w + 0.55)
		_at(t0, func():
			if tgt == null: return
			var d := dir_to(tgt)
			var length := 13.0
			var a := Vector3(pos.x, centre().y, pos.z)
			_tele_r(a, d, length, 1.8, Color("7fe8ff"), w)
			set_meta("dash_dir", d)
			m.sfx("zap", pos, -2.0, 0.6))
		_at(t0 + w, func():
			var d: Vector2 = get_meta("dash_dir", Vector2(0, 1))
			dash_v = d * 24.0
			dash_t = 13.0 / 24.0
			dash_hit = {}
			m.sfx("whoosh", pos, 2.0, 0.7))

func _dash_hits() -> void:
	m.fx.burst(pos + Vector3(0, 1.0, 0), Color("bff8ff"), 3, 2.0, 0.3, 0.0, 0.8)
	for f in m.foes_of(team):
		if f is Mob or dash_hit.has(f.nid): continue
		if flat_dist(f) < r + f.r + 0.4 and absf(f.pos.y - pos.y) < 2.0:
			dash_hit[f.nid] = true
			var d := dash_v.normalized()
			var rel := Vector2(f.pos.x - pos.x, f.pos.z - pos.z)
			var side := signf(rel.dot(Vector2(-d.y, d.x)))
			if side == 0.0:
				side = 1.0
			f.hurt(dmg(float(md["dmg"])), self, {"kb": Vector2(-d.y, d.x) * side * 9.0 + d * 3.0, "lift": 4.0, "stun": 0.3, "src": "mob"})

func _atk_storm() -> void:
	var w := 1.1 * (0.85 if enraged else 1.0)
	md["windup"] = w
	_begin("storm", w + 0.5, "roar")
	var spots: Array = []
	for f in foes_inside():
		spots.append(clamp_in(f.pos + Vector3(f.vel.x, 0, f.vel.z) * 0.5, 0.5))
	var want := 3 + phase
	var c: Vector3 = centre()
	var hf := float(lair.get("half", 7)) - 2.0
	while spots.size() < want:
		spots.append(Vector3(c.x + randf_range(-hf, hf), c.y, c.z + randf_range(-hf, hf)))
	for i in spots.size():
		var at: Vector3 = spots[i]
		at.y = c.y
		var delay := w + i * 0.12
		_tele_c(at, 1.8, Color("bff4ff"), delay)
		_at(delay, func():
			m.fx.bolt(at + Vector3(randf_range(-1, 1), 10.0, randf_range(-1, 1)), at, Color("dffaff"))
			m.fx.flash(at + Vector3(0, 0.6, 0), Color("dffaff"), 0.9, 0.08)
			blast(at, 1.8, 18.0, 4.0, 2.0, {"stun": 0.45})
			m.sfx("zap", at, 2.0, 0.8))

func _atk_static() -> void:
	var w := 1.5 * (0.85 if enraged else 1.0)
	md["windup"] = w
	_begin("static", w + 0.6, "roar")
	var at := Vector3(pos.x, centre().y, pos.z)
	_tele_c(at, 4.8, Color("7fe8ff"), w)
	_at(w, func():
		var here := Vector3(pos.x, centre().y, pos.z)
		blast(here, 4.8, 16.0, 10.0, 3.0, {"stun": 0.3})
		# and it arcs to everyone else in the lair
		for f in foes_inside():
			if flat_dist(f) > 4.8:
				m.fx.bolt(pos + Vector3(0, 1.4, 0), f.pos + Vector3(0, 0.8, 0), Color("bff8ff"))
				f.hurt(dmg(8.0), self, {"stun": 0.2, "src": "mob"})
		m.sfx("zap", pos, 4.0, 0.5))

# ---- the Brood Mother
func _atk_spit() -> void:
	var w := _wind() * 0.85
	md["windup"] = w
	_begin("spit", w + 0.5, "spit")
	var d := dir_to(tgt) if tgt else Vector2(0, 1)
	var n := 3 + phase
	var a := Vector3(pos.x, centre().y, pos.z)
	for i in n:
		var dd := d.rotated(0.22 * (i - (n - 1) * 0.5))
		_tele_r(a, dd, 10.0, 0.5, Color("b6ff6a"), w)
	_at(w, func():
		var d2 := dir_to(tgt) if tgt else d
		for i in n:
			var dd := d2.rotated(0.22 * (i - (n - 1) * 0.5))
			m.spawn_shot(self, pos + Vector3(dd.x * 1.4, 0.9, dd.y * 1.4), dd * 10.0, dmg(14.0), 1.0, 0.36, Color("b6ff6a"), {"mob": true, "kb": 2.5, "slow": 1.0})
		m.sfx("k_spore", pos, 0.0, 0.8))

func _atk_lob() -> void:
	var w := 0.7
	md["windup"] = w
	_begin("lob", w + 1.4, "spit")
	var picks: Array = foes_inside()
	picks.shuffle()
	var n := 2 + phase
	for i in n:
		var f: Ent = picks[i % picks.size()] if not picks.is_empty() else tgt
		var to := clamp_in((pos if f == null else f.pos) + Vector3(randf_range(-1.2, 1.2), 0, randf_range(-1.2, 1.2)) * (0.5 + i * 0.4), 0.6)
		to.y = centre().y
		_tele_c(to, 2.1, Color("b6ff6a"), w + i * 0.2 + 0.9)
		_at(w + i * 0.2, func(): _throw(to, 0.9, 2.1, 0.0, Color("b6ff6a"), "glob"))

## A puddle of acid: burns and slows anyone standing in it for a few seconds.
func _puddle(at: Vector3, rad: float, life: float) -> void:
	var n := MeshInstance3D.new()
	n.mesh = Models.flat_quad(rad * 2.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.6, 0.95, 0.25, 0.45)
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL; tex.fill_from = Vector2(0.5, 0.5); tex.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new(); g.set_color(0, Color(1, 1, 1, 1)); g.set_color(1, Color(1, 1, 1, 0))
	tex.gradient = g
	mat.albedo_texture = tex
	n.material_override = mat
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.add_child(n)
	n.global_position = at + Vector3(0, 0.06, 0)
	hazards.append({"at": at, "r": rad, "until": m.time + life, "every": 0.5, "next": m.time + 0.2, "dmg": 6.0, "slow": 0.7, "n": n})

func _tick_hazards(_dt: float) -> void:
	for hz in hazards.duplicate():
		if m.time >= float(hz["until"]):
			_free(hz["n"])
			hazards.erase(hz)
			continue
		if m.time < float(hz["next"]):
			continue
		hz["next"] = m.time + float(hz["every"])
		for f in m.foes_of(team):
			if f is Mob: continue
			if _hits(f, hz["at"], float(hz["r"]), 1.0):
				f.hurt(dmg(float(hz["dmg"])), self, {"slow": float(hz["slow"]), "src": "mob"})

func _atk_brood() -> void:
	var w := 1.0
	md["windup"] = w
	_begin("brood", w + 2.4, "roar")
	var n := 2 + phase
	for i in n:
		var a := TAU * i / n + randf() * 0.6
		var at := clamp_in(pos + Vector3(cos(a), 0, sin(a)) * 3.0, 0.8)
		at.y = centre().y
		# egg sacs: glowing eggs that wobble, then burst into adds
		var egg := Node3D.new()
		Models.part(egg, Models.sphere(0.32, 10), Models.toon(Color("e0b040"), true, 0.5), Vector3(0, 0.3, 0), Vector3(1, 1.3, 1))
		m.add_child(egg)
		egg.global_position = at
		egg.scale = Vector3.ONE * 0.2
		hazards.append({"at": at, "r": 0.0, "until": m.time + w + 2.2, "every": 99.0, "next": 1e9, "dmg": 0.0, "slow": 0.0, "n": egg})
		_tele_c(at, 0.9, Color("ffe680"), w + 2.2)
		_at(w * 0.5, func(): if is_instance_valid(egg): egg.scale = Vector3.ONE)
		_at(w + 2.2, func():
			m.fx.burst(at + Vector3(0, 0.4, 0), Color("e0b040"), 16, 4.0, 0.5, 6.0)
			m.sfx("die_small", at, -2.0, 1.3)
			m.lairs.spawn_add(lair, ["skitter", "skitter", "bomber", "spitter"][randi() % (2 + mini(phase, 2))], at))

func _atk_burrow() -> void:
	_begin("burrow", 3.6, "burrow")
	_at(0.4, func():
		buried = true
		m.fx.dust(pos, 20)
		m.sfx("k_gravity", pos, 0.0, 0.7))
	var mark := {"at": pos}
	_at(0.5, func():
		var to := clamp_in(tgt.pos if tgt else centre(), 1.0)
		to.y = centre().y
		mark["at"] = to
		_tele_c(to, 3.0, Color("ff4a3a"), 1.6))
	_at(2.1, func():
		var at: Vector3 = mark["at"]
		pos = Vector3(at.x, pos.y, at.z); prev = pos
		_surface()
		blast(at, 3.0, 24.0, 8.0, 8.0)
		m.sfx("boom", at, 2.0, 0.6))

func _surface() -> void:
	buried = false
	if model: model.visible = true

## 66% and 33%: a roar, a shove, and something new.
func _phase_up(p: int) -> void:
	_clear_attack()
	phase = p
	invul_t = 1.6
	anim_kind = "roar"; anim_k = 0.0
	md["windup"] = 1.2
	m.fx.ring(pos, 6.0, col(), 0.5)
	m.fx.burst(pos + Vector3(0, 1.5, 0), col(), 40, 8.0, 0.7, 2.0, 1.6)
	m.shake(0.7, pos)
	m.sfx("v_warden", pos, 4.0, 0.5)
	m.sfx("boom", pos, 0.0, 0.5)
	for f in foes_inside():
		if flat_dist(f) < 5.5:
			f.hurt(dmg(6.0), self, {"kb": dir_to(f) * 11.0, "lift": 4.0, "src": "mob"})
	m.lairs.on_boss_phase(self, p)
	_begin("phase", 2.4, "roar")
	var c: Vector3 = centre()
	var hf := float(lair.get("half", 7)) - 2.0
	match mkind:
		"colossus":
			# the ceiling of the old forge comes down in places
			for i in 5 + p * 2:
				var at := Vector3(c.x + randf_range(-hf, hf), c.y, c.z + randf_range(-hf, hf))
				var dl := 0.9 + randf() * 0.9
				_tele_c(at, 1.6, Color("ff6a3a"), dl)
				_at(dl, func():
					m.fx.burst(at + Vector3(0, 3.0, 0), Color("9c968a"), 14, 3.0, 0.6, 14.0, 1.4, Vector3.DOWN, 30.0)
					blast(at, 1.6, 16.0, 4.0, 2.0))
		"serpent":
			for i in 6 + p * 2:
				var at := Vector3(c.x + randf_range(-hf, hf), c.y, c.z + randf_range(-hf, hf))
				var dl := 1.0 + i * 0.1
				_tele_c(at, 1.7, Color("bff4ff"), dl)
				_at(dl, func():
					m.fx.bolt(at + Vector3(0, 10.0, 0), at, Color("dffaff"))
					blast(at, 1.7, 15.0, 3.0, 2.0, {"stun": 0.4}))
		"brood":
			for i in 2 + p:
				var a := TAU * i / (2.0 + p)
				var at := clamp_in(pos + Vector3(cos(a), 0, sin(a)) * 3.5, 0.8)
				_at(0.6 + i * 0.15, func(): m.lairs.spawn_add(lair, "skitter" if i % 2 == 0 else "bomber", at))

# ------------------------------------------------------------------ the serpent's coils
func _trail_push() -> void:
	var here := Vector3(pos.x, pos.y, pos.z)
	if trail.is_empty() or (trail[0] as Vector3).distance_to(here) > 0.18:
		trail.push_front(here)
		if trail.size() > 140: trail.pop_back()

func _trail_at(dist: float) -> Vector3:
	var acc := 0.0
	var last: Vector3 = trail[0] if not trail.is_empty() else pos
	for i in range(1, trail.size()):
		var p: Vector3 = trail[i]
		var sd := last.distance_to(p)
		if acc + sd >= dist:
			return last.lerp(p, (dist - acc) / maxf(0.001, sd))
		acc += sd
		last = p
	return last

# ------------------------------------------------------------------ looks
func render(delta: float, alpha: float) -> void:
	if freeze_t <= 0.0:
		position = prev.lerp(pos, alpha)
	squash = maxf(0.0, squash - delta * 2.5)
	var f := clampf(flash_t / 0.12, 0.0, 1.0)
	for mt in mats:
		if mt is ShaderMaterial: mt.set_shader_parameter("flash", f)
	if stag_ring:
		stag_ring.visible = stag_open > 0.0 and stagger_t <= 0.0 and not dead
		if stag_ring.visible:
			var pul := 1.0 + sin(m.time * 10.0) * 0.08
			stag_ring.scale = Vector3(pul, 1.0, pul)
		stag_stars.visible = stagger_t > 0.0
		if stag_stars.visible: stag_stars.rotation.y += delta * 5.0
	if not model:
		return
	if dead:
		death_t += delta
		var k := clampf(death_t / 1.4, 0.0, 1.0)
		model.position.y = -k * 1.5
		model.rotation.z = k * 0.5
		visible = k < 1.0
		for mt in mats:
			if mt is ShaderMaterial: mt.set_shader_parameter("flash", 1.0 - k)
		for s in model.get_meta("segs", []):
			(s as Node3D).visible = k < 0.6
		return
	model.visible = not buried
	model.rotation.y = face
	if anim_kind != "":
		anim_k = minf(1.0, anim_k + delta / maxf(0.2, float(md.get("windup", 1.0))))
	var body: Node3D = model.get_node("Body")
	var spd := Vector2(vel.x, vel.z).length()
	anim += delta * (1.5 + minf(spd, 6.0) * 1.2)
	var sleep := 1.0 if dormant else 0.0
	match mkind:
		"colossus": _anim_colossus(delta, body, spd, sleep)
		"serpent": _anim_serpent(delta, body, spd, sleep)
		"brood": _anim_brood(delta, body, spd, sleep)
	if enraged:
		for mt in mats:
			if mt is ShaderMaterial: mt.set_shader_parameter("flash", maxf(f, 0.12 + 0.08 * sin(m.time * 9.0)))

func _anim_colossus(delta: float, body: Node3D, spd: float, sleep: float) -> void:
	body.position.y = -0.25 * sleep
	body.rotation.x = 0.25 * sleep
	var ap: AnimationPlayer = model.get_meta("anim") if model.has_meta("anim") else null
	if ap == null:
		return
	var C: Dictionary = model.get_meta("clips")
	var clip := String(C["idle"]); var rate := 0.6 if sleep > 0.0 else 1.0
	var scrub := -1.0
	match anim_kind:
		"slam": clip = String(C["attack"]); scrub = anim_k * float(C["hit"]) if atk_t < float(md["windup"]) else -1.0
		"throw": clip = String(C.get("throw", C["attack"])); scrub = anim_k * float(C.get("throw_hit", 0.5)) if atk_t < float(md["windup"]) else -1.0
		"roar": clip = String(C.get("roar", C["idle"])); rate = 1.4
		_:
			if spd > 0.3: clip = String(C["walk"]); rate = clampf(spd / 1.6, 0.5, 1.4)
	if stagger_t > 0.0: rate = 0.3
	if ap.current_animation != clip:
		ap.play(clip, 0.15)
	if scrub >= 0.0:
		ap.speed_scale = 0.0
		ap.seek(ap.get_animation(clip).length * clampf(scrub, 0.0, 1.0), true)
	else:
		ap.speed_scale = rate

func _anim_serpent(delta: float, body: Node3D, spd: float, sleep: float) -> void:
	var hover := 1.0 - sleep * 0.85
	var head: Node3D = body.get_node("Head")
	var bob := sin(m.time * 2.2) * 0.18
	head.position.y = 0.35 + hover * (1.0 + bob)
	head.rotation.x = -0.25 * (anim_k if anim_kind == "dash" else 0.0) + 0.3 * sleep
	var jaw: Node3D = head.get_node_or_null("Jaw")
	if jaw: jaw.rotation.x = 0.1 + (0.55 * anim_k if anim_kind in ["roar", "dash"] else 0.0) + sin(m.time * 5.0) * 0.04
	for wn in ["WingL", "WingR"]:
		var wg: Node3D = head.get_node_or_null(wn)
		if wg: wg.rotation.z = sin(m.time * (7.0 if dash_t > 0.0 else 3.5)) * 0.35 * (1.0 if wn == "WingL" else -1.0) * hover
	var segs: Array = model.get_meta("segs", [])
	var floor_y := position.y
	for i in segs.size():
		var s: Node3D = segs[i]
		var p: Vector3
		if trail.size() < 2 or sleep > 0.0:
			# asleep: coiled in a loose spiral round itself
			var a := face + i * 0.55
			var rr := 0.9 + i * 0.09
			p = position + Vector3(sin(a) * rr, 0.25 + 0.04 * i, cos(a) * rr)
		else:
			p = _trail_at(0.62 * (i + 1))
			p.y = floor_y + 0.3 + hover * (0.95 + sin(m.time * 2.2 - i * 0.45) * 0.3 - i * 0.03)
		var tw := 1.0 - exp(-14.0 * delta)
		s.global_position = s.global_position.lerp(p, tw) if s.global_position.length() > 0.01 else p
		var ahead: Vector3 = segs[i - 1].global_position if i > 0 else position + Vector3(0, head.position.y, 0)
		if s.global_position.distance_to(ahead) > 0.05:
			s.look_at(ahead, Vector3.UP)

func _anim_brood(delta: float, body: Node3D, spd: float, sleep: float) -> void:
	var legs: Node3D = body.get_node("Legs")
	var mv := clampf(spd / 2.0, 0.0, 1.0)
	body.position.y = -0.35 * sleep + (absf(sin(anim * 1.2)) * 0.06 * mv) - (0.2 * anim_k if anim_kind in ["spit", "roar"] else 0.0)
	body.rotation.x = (0.25 * anim_k if anim_kind == "spit" else 0.0) - (0.2 * anim_k if anim_kind == "roar" else 0.0)
	for i in 3:
		for sx in [-1, 1]:
			var lg := legs.get_node_or_null("Leg%d%d" % [i, sx]) as Node3D
			if lg == null: continue
			var ph := anim * 1.4 + (PI if (i % 2 == 0) == (sx > 0) else 0.0)
			lg.rotation.y = sin(ph) * 0.35 * mv
			lg.rotation.z = maxf(0.0, cos(ph)) * 0.25 * sx * mv - (0.35 * sx if anim_kind == "roar" else 0.0) * anim_k
	var sac: Node3D = body.get_node("Sac")
	var pulse := 1.0 + sin(m.time * (2.0 + phase * 1.5)) * 0.04 + (0.12 * anim_k if anim_kind == "brood" else 0.0)
	sac.scale = Vector3(pulse, pulse * 0.98, pulse)
	var hd: Node3D = body.get_node("Head")
	for jn in ["JawL", "JawR"]:
		var j := hd.get_node_or_null(jn) as Node3D
		if j: j.rotation.y = (0.15 + 0.5 * anim_k * float(anim_kind in ["spit", "roar"]) + sin(m.time * 6.0) * 0.05) * (1.0 if jn == "JawL" else -1.0)
	if buried:
		body.position.y = -2.0
