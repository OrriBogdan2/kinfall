class_name Abil
## Hero abilities. E is on a cooldown, R is an ultimate that charges as you deal damage.
## Everything here runs on the hunter's own game; damage reaches other players through Ent.hurt,
## areas reach them through Match.add_zone, and movement through the usual snapshots.

static func e_id(h: Hunter) -> String:
	return Data.HEROES[h.hero]["e"]

static func r_id(h: Hunter) -> String:
	return Data.HEROES[h.hero]["r"]

static func e_cd(h: Hunter) -> float:
	return float(Data.ABIL[e_id(h)]["cd"])

static func aim_point(h: Hunter, maxd: float) -> Vector3:
	var a: Vector3 = h.inp["aim"]
	var d := Vector2(a.x - h.pos.x, a.z - h.pos.z)
	if d.length() > maxd:
		d = d.normalized() * maxd
	return Vector3(h.pos.x + d.x, h.pos.y, h.pos.z + d.y)

## The farthest open ground along a line, or the start if there's none.
static func reach(m: Match, from: Vector3, to: Vector3) -> Vector3:
	var best := from
	var d := Vector2(to.x - from.x, to.z - from.z)
	var n := int(ceil(d.length() / 0.25))
	for i in range(1, n + 1):
		var q := Vector2(from.x, from.z) + d * (float(i) / n)
		if m.world.is_void(q.x, q.y) or m.world.is_block(q.x, q.y):
			continue
		var gy: float = m.world.ground_at(q.x, q.y)
		if gy > from.y + 2.5:
			continue
		best = Vector3(q.x, gy, q.y)
	return best

# ------------------------------------------------------------------ E
static func use_e(h: Hunter) -> void:
	var m: Match = h.m
	var id := e_id(h)
	if h.sig_cd > 0.0 or h.downed or h.out or h.dropping:
		return
	h.sig_cd = e_cd(h)
	var tc: Color = Data.HEROES[h.hero]["color"]
	match id:
		"cloak":
			h.cloak_t = 3.0; h.haste_t = 3.0
			m.sfx("cloak", h.pos, -2.0)
			m.fx.burst(h.pos + Vector3(0, 0.8, 0), tc, 18, 4.0)
		"mend":
			m.sfx("heal", h.pos, 0.0)
			m.fx.ring(h.pos, 5.0, Color("9ee2a0"), 0.45)
			m.net_fx(["ring", m._r(h.pos.x), m._r(h.pos.y), m._r(h.pos.z), 5.0, "9ee2a0"])
			for o in m.hunters:
				if o.team == h.team and not o.out and o.flat_dist(h) < 5.0:
					if o.downed:
						o.revive = minf(0.95, o.revive + 0.5)
					else:
						o.heal(35.0)
				if o.team == h.team and o.kin and o.kin.state == "active" and o.kin.flat_dist(h) < 5.0:
					o.kin.hp = minf(o.kin.max_hp, o.kin.hp + 35.0)
		"fortify":
			h.shield = maxf(h.shield, 60.0); h.shield_t = 5.0; h.fortify_t = 5.0
			m.sfx("shield", h.pos, 0.0)
			m.fx.ring(h.pos, 1.6, Color("e6dbc4"), 0.3)
		"blink":
			var to := reach(m, h.pos, aim_point(h, 6.0))
			if to.distance_to(h.pos) < 0.6:
				h.sig_cd = 0.3
				return
			m.fx.ghost(h.position, h.face, tc, float(h.cdat["scale"]))
			m.fx.burst(h.pos + Vector3(0, 0.8, 0), tc, 14, 3.0, 0.35, 0.0)
			h.teleport(to)
			h.vel = Vector3.ZERO
			h.grounded = true
			h.crit_t = 2.0
			m.sfx("cloak", h.pos, -4.0, 1.6)
			m.fx.burst(h.pos + Vector3(0, 0.8, 0), tc, 18, 4.0, 0.4, 0.0)
		"tether":
			var d := h.aim_dir()
			m.spawn_shot(h, h.pos + Vector3(d.x * 0.6, 0.95 * float(h.cdat["scale"]), d.y * 0.6), d * 34.0, 12.0, 14.0 / 34.0, 0.14, tc, {"root": 1.5, "kb": 1.0})
			m.sfx("rifle", h.pos, -2.0, 1.5)
		"hook":
			var d := h.aim_dir()
			m.spawn_shot(h, h.pos + Vector3(d.x * 0.6, 0.95, d.y * 0.6), d * 30.0, 10.0, 9.0 / 30.0, 0.16, tc, {"hook": true, "stun": 0.5})
			m.sfx("throw", h.pos, -2.0, 0.8)
		"rocketjump":
			_blast(h, h.pos, 2.4, 10.0, 11.0, tc)
			var to := reach(m, h.pos, aim_point(h, 7.0))
			if to.distance_to(h.pos) > 1.0:
				h.pad_launch(to)
			else:
				h.vel.y = 12.0; h.grounded = false
		"ram":
			var d := h.aim_dir()
			h.charge = {"t": 0.38, "dir": d, "hit": {}}
			h.inv_t = maxf(h.inv_t, 0.2)
			m.sfx("dash", h.pos, 0.0, 0.7)
			m.fx.dash_trail(h)
		"dome":
			m.add_zone("dome", h.pos, 3.6, 4.0, h.team, h)
			m.sfx("shield", h.pos, 0.0, 0.8)

# ------------------------------------------------------------------ R
static func use_r(h: Hunter) -> void:
	var m: Match = h.m
	if h.ult < 1.0 or h.downed or h.out or h.dropping:
		return
	h.ult = 0.0
	var tc: Color = Data.HEROES[h.hero]["color"]
	m.sfx("skill", h.pos, 0.0, 0.8)
	m.ult_moment(h)
	if h == m.player and m.hud:
		m.hud.toast(Data.ABIL[r_id(h)]["name"], tc)
	match r_id(h):
		"vanish":
			h.cloak_t = 5.0; h.haste_t = 5.0
			h.dashes = h.max_dashes()
			m.sfx("cloak", h.pos, 0.0)
		"dance":
			var targets: Array = []
			for f in m.foes_of(h.team):
				if f.flat_dist(h) < 9.0 and (f is Hunter or f is Mob):
					targets.append(f)
			targets.sort_custom(func(a, b): return a.flat_dist(h) < b.flat_dist(h))
			for i in mini(3, targets.size()):
				h.acts.append({"t": 0.05 + i * 0.22, "kind": "slash", "tgt": targets[i]})
			if targets.is_empty():
				h.ult = 1.0
		"skypierce":
			var d := h.aim_dir()
			h.acts.append({"t": 0.7, "kind": "beam", "dir": d})
			h.root_t = maxf(h.root_t, 0.7)
			h.acts_tele = m.fx.telegraph_rect(h.pos, d, 26.0, 1.0, Color(tc, 0.8))
		"sanctuary":
			m.add_zone("sanctuary", h.pos, 4.2, 6.0, h.team, h)
		"anchor":
			var to := reach(m, h.pos, aim_point(h, 10.0))
			h.pad_launch(to)
			h.acts.append({"t": float(h.pad.get("dur", 0.8)), "kind": "slam", "at": to})
		"barrage":
			var c := aim_point(h, 11.0)
			for i in 6:
				h.acts.append({"t": 0.05 + i * 0.2, "kind": "rocket", "at": c + Vector3(randf_range(-2.2, 2.2), 0, randf_range(-2.2, 2.2))})
		"bulwark":
			h.shield = maxf(h.shield, 120.0); h.shield_t = 6.0; h.fortify_t = 6.0
			for i in 12:
				h.acts.append({"t": 0.5 * i, "kind": "aura"})
			m.sfx("shield", h.pos, 0.0, 0.7)
		"quake":
			h.acts.append({"t": 0.35, "kind": "quake", "dir": h.aim_dir()})
			h.root_t = maxf(h.root_t, 0.35)
		"well":
			m.add_zone("well", aim_point(h, 10.0), 4.5, 3.5, h.team, h)

## Runs queued pieces of abilities: windups, sequences and lingering effects.
static func tick(h: Hunter, dt: float) -> void:
	if h.acts.is_empty():
		return
	var m: Match = h.m
	var tc: Color = Data.HEROES[h.hero]["color"]
	for a in h.acts.duplicate():
		a["t"] -= dt
		if a["t"] > 0.0:
			if a["kind"] == "beam" and h.acts_tele:
				m.fx.aim_telegraph(h.acts_tele, h.pos, a["dir"])
				m.fx.telegraph_progress(h.acts_tele, 1.0 - a["t"] / 0.7)
			continue
		h.acts.erase(a)
		match String(a["kind"]):
			"slash":
				var t: Ent = a["tgt"]
				if t == null or t.dead or not is_instance_valid(t):
					continue
				var behind := t.pos + Vector3(t.pos.x - h.pos.x, 0, t.pos.z - h.pos.z).normalized() * 1.0
				if m.world.is_void(behind.x, behind.z) or m.world.is_block(behind.x, behind.z):
					behind = t.pos
				m.fx.ghost(h.position, h.face, tc, float(h.cdat["scale"]))
				h.teleport(Vector3(behind.x, m.world.ground_at(behind.x, behind.z), behind.z))
				h.face = atan2(-(t.pos.x - h.pos.x), -(t.pos.z - h.pos.z))
				t.hurt(28.0 * m.dmg_mult(h), h, {"stun": 0.4, "kb": Vector2(t.pos.x - h.pos.x, t.pos.z - h.pos.z).normalized() * 4.0, "src": "abil", "crit": true})
				m.fx.burst(t.pos + Vector3(0, 0.9, 0), tc, 16, 4.0, 0.3)
				m.sfx("crit", t.pos, -2.0)
			"beam":
				if h.acts_tele:
					m.fx.end_telegraph(h.acts_tele)
					h.acts_tele = null
				var d: Vector2 = a["dir"]
				var a0 := h.pos + Vector3(0, 0.95, 0)
				var b0 := a0 + Vector3(d.x, 0, d.y) * 26.0
				m.fx.bolt(a0, b0, tc.lightened(0.3))
				m.net_fx(["bolt", m._r(a0.x), m._r(a0.y), m._r(a0.z), m._r(b0.x), m._r(b0.y), m._r(b0.z), tc.lightened(0.3).to_html(false)])
				m.sfx("boom", h.pos, -2.0, 1.6)
				m.shake(0.3, h.pos)
				for f in m.foes_of(h.team):
					var rel := Vector2(f.pos.x - h.pos.x, f.pos.z - h.pos.z)
					var along := rel.dot(d)
					if along > 0.0 and along < 26.0 and absf(rel.cross(d)) < 0.9 + f.r:
						f.hurt(62.0 * m.dmg_mult(h), h, {"kb": d * 12.0, "lift": 4.0, "src": "abil"})
			"slam":
				var at: Vector3 = h.pos
				_blast(h, at, 3.6, 40.0, 12.0, tc, 6.0)
				m.shake(0.5, at)
			"rocket":
				var c: Vector3 = a["at"]
				var from := h.pos + Vector3(0, 0.95, 0)
				var dv := Vector2(c.x - from.x, c.z - from.z)
				var spd := 18.0
				m.spawn_shot(h, from, dv.normalized() * spd, 18.0 * m.dmg_mult(h), dv.length() / spd, 0.2, Color("ff7a5a"), {"boom": 2.0, "boom_kb": 9.0 * (1.2 if h.hero == "pyra" else 1.0)})
				m.sfx("thump", h.pos, -4.0)
			"aura":
				for f in m.foes_of(h.team):
					if f.flat_dist(h) < 4.0:
						f.hurt(2.0, h, {"slow": 0.8, "src": "abil"})
				m.fx.ring(h.pos, 4.0, Color(tc, 0.5), 0.4)
			"quake":
				var d: Vector2 = a["dir"]
				m.fx.cone(h.pos, d, 8.0, Color("c08a5a"))
				m.net_fx(["cone", m._r(h.pos.x), m._r(h.pos.y), m._r(h.pos.z), m._r(d.x), m._r(d.y), "c08a5a"])
				m.sfx("boom", h.pos, 0.0, 0.7)
				m.shake(0.6, h.pos)
				for f in m.foes_of(h.team):
					var rel := Vector2(f.pos.x - h.pos.x, f.pos.z - h.pos.z)
					if rel.length() < 8.0 and rel.length() > 0.01 and rel.normalized().dot(d) > 0.55:
						f.hurt(45.0 * m.dmg_mult(h), h, {"stun": 0.6, "kb": rel.normalized() * 10.0, "lift": 5.0, "src": "abil"})

## A burst around a point that knocks foes away from it.
static func _blast(h: Hunter, at: Vector3, radius: float, dmg: float, kb: float, col: Color, lift := 4.0) -> void:
	var m: Match = h.m
	m.fx.ring(at, radius, col, 0.3)
	m.fx.burst(at + Vector3(0, 0.4, 0), col, 24, 6.0, 0.5, 6.0, 1.2)
	m.net_fx(["ring", m._r(at.x), m._r(at.y), m._r(at.z), radius, col.to_html(false)])
	m.sfx("boom", at, -2.0)
	if h.hero == "pyra":
		kb *= 1.2
	for f in m.foes_of(h.team):
		var rel := Vector2(f.pos.x - at.x, f.pos.z - at.z)
		if rel.length() < radius + f.r and absf(f.pos.y - at.y) < 2.0:
			var dir := rel.normalized() if rel.length() > 0.05 else Vector2(1, 0)
			f.hurt(dmg * m.dmg_mult(h), h, {"kb": dir * kb, "lift": lift, "src": "abil"})

## Ram: while charging, bowl over anyone in the way.
static func charge_hits(h: Hunter) -> void:
	var m: Match = h.m
	for f in m.foes_of(h.team):
		if h.charge["hit"].has(f.nid):
			continue
		if f.flat_dist(h) < h.r + f.r + 0.5 and absf(f.pos.y - h.pos.y) < 1.5:
			h.charge["hit"][f.nid] = true
			var d: Vector2 = h.charge["dir"]
			f.hurt(22.0 * m.dmg_mult(h), h, {"kb": d * 12.5, "lift": 4.0, "src": "abil"})
			m.shake(0.35, f.pos)
			m.fx.burst(f.pos + Vector3(0, 0.8, 0), Color("c08a5a"), 18, 5.0, 0.4)
			if h.hero == "tusk" and h.charge["hit"].size() == 1:
				h.sig_cd = minf(h.sig_cd, e_cd(h) * 0.5)
