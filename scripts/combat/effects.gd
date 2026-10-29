class_name Effects
## The building blocks abilities are made of. Each effect is a dictionary with a "type" and its
## numbers, so a new ability is just a new list of these in JSON. The caster can be a hunter or a
## kin; "target" picks who a buff lands on: "self" (default), "owner" (the kin's hunter), "both", "allies".
## "at" picks where an area happens: "self", "owner", "aim" (the cursor or the kin's target), "here".
##
##   projectile  dmg speed range size color kb stun slow root burn count spread  on_end:[...] on_hit:[...]
##   area        radius dmg kb lift stun slow root burn at delay color
##   cone        radius arc dmg kb slow stun color                  (in front of the caster, toward the aim)
##   chain       count first jump dmg stun color                    (lightning hopping between foes)
##   pull        radius strength at                                 (drags foes toward the spot)
##   zone        radius time every dmg slow root burn heal at color (a patch that keeps working)
##   telegraph   radius time at color                               (a warning ring, no effect)
##   rush        distance speed width dmg burn stun kb on_end:[...] (the caster charges along the aim)
##   leap        time height on_land:[...]                          (the caster jumps onto the aim)
##   dash        speed time invuln shove shove_kb shove_dmg         (hunters only)
##   blink       distance                                           (teleport toward the aim, never into the abyss)
##   launch      up forward                                         (throws the target into the air)
##   heal        amount        shield amount time      haste time      guard amount time (less damage taken)
##   cleanse     (clears slow, root, stun and burn)     refill_dash      cool_glider      crit time      burst color

static func run(effects: Array, caster: Node, ctx: Dictionary) -> void:
	for e in effects:
		if e is Dictionary:
			var delay := float(e.get("delay", 0.0))
			if delay > 0.0 and caster and caster.is_inside_tree():
				var ee: Dictionary = e.duplicate()
				ee.erase("delay")
				caster.get_tree().create_timer(delay, false).timeout.connect(func():
					if is_instance_valid(caster) and not caster.dead: run([ee], caster, ctx))
				continue
			_one(e, caster, ctx)

static func _m(caster: Node) -> Node:
	return caster.get("m") if caster else null

## The hunter a kin belongs to, or the caster itself.
static func owner_of(caster: Node) -> Node:
	if caster is Kin and (caster as Kin).owner_h:
		return (caster as Kin).owner_h
	return caster

static func _aim_dir(caster: Node, ctx: Dictionary) -> Vector2:
	if ctx.has("dir"):
		return ctx["dir"]
	var at: Vector3 = _aim_point(caster, ctx)
	var d := Vector2(at.x - caster.pos.x, at.z - caster.pos.z)
	if d.length() > 0.01:
		return d.normalized()
	if caster is Hunter:
		return (caster as Hunter).aim_dir()
	return Vector2(-sin(caster.face), -cos(caster.face))

static func _aim_point(caster: Node, ctx: Dictionary) -> Vector3:
	if ctx.has("aim"):
		return ctx["aim"]
	if caster is Hunter:
		return (caster as Hunter).inp.get("aim", caster.pos)
	return caster.pos

static func _where(e: Dictionary, caster: Node, ctx: Dictionary, default := "self") -> Vector3:
	match String(e.get("at", "here" if ctx.has("at") else default)):
		"aim":
			var p := _aim_point(caster, ctx)
			var m = _m(caster)
			var g: float = m.world.ground_at(p.x, p.z)
			return Vector3(p.x, g if g > World.VOID + 1.0 else caster.pos.y, p.z)
		"here": return ctx.get("at", caster.pos)
		"owner": return owner_of(caster).pos
	return caster.pos

static func _targets(e: Dictionary, caster: Node) -> Array:
	var own := owner_of(caster)
	match String(e.get("target", "self")):
		"owner": return [own]
		"both": return [caster] if own == caster else [caster, own]
		"allies":
			var out: Array = []
			var m = _m(caster)
			var rad := float(e.get("radius", 5.0))
			for h in m.hunters:
				if h.team == caster.team and not h.out and h.flat_dist(own) < rad:
					out.append(h)
					if h.kin and h.kin.state in ["active", "giant"] and h.kin.flat_dist(own) < rad:
						out.append(h.kin)
			return out
	return [caster]

static func _power(caster: Node, ctx: Dictionary) -> float:
	var m = _m(caster)
	if caster is Hunter:
		return m.dmg_mult(caster)
	return float(ctx.get("power", 1.0))

static func _hit_opts(e: Dictionary, ctx: Dictionary, kb: Vector2, caster: Node) -> Dictionary:
	var slot := String(ctx.get("slot", ""))
	var o := {"src": "kin" if caster is Kin else "abil", "ab": slot if slot != "" else "abil", "tags": [slot, String(ctx.get("ability", ""))]}
	if caster is Kin: o["tags"].append("kin")
	if kb.length() > 0.01: o["kb"] = kb
	for k in ["lift", "stun", "slow", "root", "burn"]:
		if e.has(k): o[k] = float(e[k])
	return o

static func _hits(f: Ent, at: Vector3, r: float) -> bool:
	return Vector2(f.pos.x - at.x, f.pos.z - at.z).length() < r + f.r and absf(f.pos.y - at.y) < 2.2

static func _heal(t: Node, n: float) -> void:
	if t is Hunter:
		(t as Hunter).heal(n)
	elif t is Ent and not t.dead and t.hp > 0.0:
		t.hp = minf(t.max_hp, t.hp + n)

static func _one(e: Dictionary, caster: Node, ctx: Dictionary) -> void:
	var m = _m(caster)
	if m == null or caster == null or caster.dead:
		return
	var col := Color(String(e.get("color", "#ffffff")))
	var pw := _power(caster, ctx)
	match String(e.get("type", "")):
		"projectile":
			var d := _aim_dir(caster, ctx)
			var n := int(e.get("count", 1))
			var spread := float(e.get("spread", 0.0))
			var spd := float(e.get("speed", 20.0))
			var y: float = caster.pos.y + (0.95 if caster is Hunter else 0.5)
			for i in n:
				var a := atan2(d.y, d.x) + (spread * (float(i) / maxf(1.0, n - 1) - 0.5) if n > 1 else 0.0)
				var dir := Vector2(cos(a), sin(a))
				var start := Vector3(caster.pos.x + dir.x * 0.6, y, caster.pos.z + dir.y * 0.6)
				var extra := _hit_opts(e, ctx, Vector2.ZERO, caster)
				extra["kb"] = float(e.get("kb", 0.0))
				if caster is Kin: extra["kin"] = true
				if e.has("on_end"): extra["fx_end"] = e["on_end"]
				if e.has("on_hit"): extra["fx_hit"] = e["on_hit"]
				extra["fx_ctx"] = ctx
				m.spawn_shot(caster, start, dir * spd, float(e.get("dmg", 0.0)) * pw, float(e.get("range", 10.0)) / spd, float(e.get("size", 0.15)), col, extra)
			m.sfx(String(e.get("sfx", "throw")), caster.pos, -3.0, float(e.get("pitch", 1.0)))
		"area":
			var at := _where(e, caster, ctx)
			var r := float(e.get("radius", 2.0))
			m.fx.ring(at, r, col, 0.3)
			m.fx.burst(at + Vector3(0, 0.4, 0), col, int(clampf(r * 10.0, 8.0, 30.0)), 5.0, 0.45, 6.0, 1.1)
			m.sfx("boom", at, -3.0 if r > 2.0 else -7.0, 1.3 - minf(0.5, r * 0.1))
			if r > 2.0: m.shake(0.3, at)
			for f in m.foes_of(caster.team):
				if _hits(f, at, r):
					var rel := Vector2(f.pos.x - at.x, f.pos.z - at.z)
					var kb := rel.normalized() * float(e.get("kb", 0.0)) if rel.length() > 0.05 else Vector2.ZERO
					f.hurt(float(e.get("dmg", 0.0)) * pw, caster, _hit_opts(e, ctx, kb, caster))
		"cone":
			var d := _aim_dir(caster, ctx)
			var r := float(e.get("radius", 5.0))
			var arc := float(e.get("arc", 0.55))
			m.fx.cone(caster.pos, d, r, col)
			m.sfx("whoosh", caster.pos, -4.0, 0.9)
			for f in m.foes_of(caster.team):
				var to := Vector2(f.pos.x - caster.pos.x, f.pos.z - caster.pos.z)
				if to.length() < r + f.r and (to.length() < 0.6 or to.normalized().dot(d) > arc) and absf(f.pos.y - caster.pos.y) < 2.2:
					f.hurt(float(e.get("dmg", 0.0)) * pw, caster, _hit_opts(e, ctx, d * float(e.get("kb", 0.0)), caster))
		"chain":
			var from: Vector3 = owner_of(caster).pos if String(e.get("from", "")) == "owner" else caster.pos
			var near := _aim_point(caster, ctx) if not String(e.get("from", "")) == "owner" else from
			var hit: Array = []
			if e.get("skip_here", false) and ctx.has("at"):
				# arcing on from whatever a shot just hit
				from = ctx["at"]; near = from
				for f in m.foes_of(caster.team):
					if Vector2(f.pos.x - from.x, f.pos.z - from.z).length() < f.r + 0.7: hit.append(f)
			for i in int(e.get("count", 3)):
				var best: Ent = null
				var bd := float(e.get("first", 6.0)) if i == 0 else float(e.get("jump", 4.0))
				for f in m.foes_of(caster.team):
					if hit.has(f) or not f.hittable(): continue
					var dd: float = Vector2(f.pos.x - near.x, f.pos.z - near.z).length()
					if dd < bd:
						bd = dd; best = f
				if best == null:
					break
				hit.append(best)
				m.fx.bolt(from + Vector3(0, 0.6, 0), best.pos + Vector3(0, 0.8, 0), col)
				best.hurt(float(e.get("dmg", 12.0)) * pw, caster, _hit_opts(e, ctx, Vector2.ZERO, caster))
				from = best.pos; near = best.pos
			if hit.size() > 0:
				m.sfx("zap", hit[0].pos, -3.0)
		"pull":
			var at := _where(e, caster, ctx)
			var r := float(e.get("radius", 4.0))
			m.fx.ring(at, r, col, 0.4)
			for f in m.foes_of(caster.team):
				var rel := Vector2(at.x - f.pos.x, at.z - f.pos.z)
				if rel.length() < r + f.r and rel.length() > 0.4 and absf(f.pos.y - at.y) < 2.5:
					f.impulse(rel.normalized() * float(e.get("strength", 6.0)) * clampf(rel.length() / r + 0.3, 0.4, 1.0), 1.0)
		"zone":
			var at := _where(e, caster, ctx, "aim")
			m.fields.add(caster, at, e, ctx, pw)
		"telegraph":
			var at := _where(e, caster, ctx, "aim")
			m.fx.ring(at, float(e.get("radius", 2.0)), Color(col, 0.7), float(e.get("time", 0.4)))
		"rush":
			if caster is Kin:
				(caster as Kin).start_rush(_aim_dir(caster, ctx), e, ctx)
			elif caster is Hunter:
				(caster as Hunter).dash_with({"speed": float(e.get("speed", 20.0)), "time": float(e.get("distance", 6.0)) / float(e.get("speed", 20.0)), "shove": true, "shove_kb": float(e.get("kb", 6.0)), "shove_dmg": float(e.get("dmg", 8.0))})
		"leap":
			var to := _where(e, caster, ctx, "aim")
			if caster is Kin:
				(caster as Kin).start_leap(to, e, ctx)
			elif caster is Hunter:
				(caster as Hunter).launch_to(to, float(e.get("time", 0.5)))
				if e.has("on_land"):
					var land: Array = e["on_land"]
					caster.get_tree().create_timer(float(e.get("time", 0.5)), false).timeout.connect(func():
						if is_instance_valid(caster): run(land, caster, {"at": caster.pos, "slot": ctx.get("slot", ""), "ability": ctx.get("ability", "")}))
		"dash":
			if caster is Hunter:
				(caster as Hunter).dash_with(e)
		"blink":
			var d := _aim_dir(caster, ctx)
			var dist := float(e.get("distance", 5.0))
			var best: Vector3 = caster.pos
			var k := dist
			while k > 0.5:
				var p: Vector3 = caster.pos + Vector3(d.x, 0, d.y) * k
				if not m.world.is_void(p.x, p.z) and not m.world.is_block(p.x, p.z):
					best = Vector3(p.x, m.world.ground_at(p.x, p.z), p.z); break
				k -= 0.5
			m.fx.burst(caster.pos + Vector3(0, 0.8, 0), col, 14, 3.0, 0.3)
			caster.teleport(best)
			m.fx.burst(best + Vector3(0, 0.8, 0), col, 14, 3.0, 0.3)
		"launch":
			for t in _targets(e, caster):
				var d := _aim_dir(t, {}) if t is Hunter and not ctx.has("dir") else _aim_dir(caster, ctx)
				if t is Hunter:
					var mv: Vector2 = (t as Hunter).inp.get("move", Vector2.ZERO)
					if mv.length() > 0.1: d = mv.normalized()
				t.vel = Vector3(d.x * float(e.get("forward", 6.0)), float(e.get("up", 12.0)), d.y * float(e.get("forward", 6.0)))
				t.grounded = false
				if t is Hunter:
					(t as Hunter).fly_t = 0.5
					(t as Hunter).roll_t = 0.0
				m.fx.burst(t.pos + Vector3(0, 0.3, 0), col, 18, 5.0, 0.5, -2.0)
				m.sfx("whoosh", t.pos, -2.0, 1.2)
		"heal":
			for t in _targets(e, caster):
				_heal(t, float(e.get("amount", 20.0)))
				m.fx.burst(t.pos + Vector3(0, 1.0, 0), Color("8fe0a0"), 12, 2.5, 0.5, -3.0)
		"shield":
			for t in _targets(e, caster):
				if "shield" in t:
					t.shield = maxf(float(t.shield), float(e.get("amount", 40.0)))
					if "shield_t" in t: t.shield_t = maxf(float(t.shield_t), float(e.get("time", 5.0)))
				m.fx.ring(t.pos + Vector3(0, 0.1, 0), 1.0 if t is Hunter else 0.7, col, 0.4)
			m.sfx("shield", caster.pos, -3.0)
		"haste":
			for t in _targets(e, caster):
				if "haste_t" in t:
					t.haste_t = maxf(float(t.haste_t), float(e.get("time", 2.0)))
		"guard":
			for t in _targets(e, caster):
				if t is Ent:
					t.guard_t = maxf(t.guard_t, float(e.get("time", 3.0)))
					t.guard_k = float(e.get("amount", 0.5))
					m.fx.burst(t.pos + Vector3(0, 0.5, 0), col, 14, 2.5, 0.4)
		"cleanse":
			for t in _targets(e, caster):
				if t is Ent:
					t.slow_t = 0.0; t.root_t = 0.0; t.stun_t = 0.0; t.burn_t = 0.0
		"refill_dash":
			for t in _targets(e, caster):
				if t is Hunter:
					(t as Hunter).dashes = (t as Hunter).max_dashes()
		"cool_glider":
			for t in _targets(e, caster):
				if t is Hunter:
					(t as Hunter).glide_fuel = 1.0
					(t as Hunter).shot_down = false
		"crit":
			for t in _targets(e, caster):
				if t is Hunter:
					(t as Hunter).crit_t = maxf((t as Hunter).crit_t, float(e.get("time", 2.0)))
		"burst":
			for t in _targets(e, caster):
				m.fx.burst(t.pos + Vector3(0, 0.9, 0), col, 18, 4.0, 0.45)
				m.fx.ring(t.pos, 1.2, col, 0.3)
