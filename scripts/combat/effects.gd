class_name Effects
## The building blocks abilities are made of. Each effect is a dictionary with a "type" and its
## numbers, so a new ability is just a new list of these in JSON.
##
##   projectile  dmg speed range size color kb stun slow root burn count spread  on_end:[...] on_hit:[...]
##   area        radius dmg kb lift stun slow root at:"self"|"aim"|"here" delay color
##   dash        speed time invuln shove shove_kb shove_dmg    (hunters only)
##   blink       distance                                     (teleport toward the aim, never into the abyss)
##   launch      up forward                                   (throws the caster into the air)
##   heal        amount
##   shield      amount time
##   haste       amount time

static func run(effects: Array, caster: Node, ctx: Dictionary) -> void:
	for e in effects:
		if e is Dictionary:
			var delay := float(e.get("delay", 0.0))
			if delay > 0.0 and caster and caster.is_inside_tree():
				var ee: Dictionary = e.duplicate()
				ee.erase("delay")
				caster.get_tree().create_timer(delay, false).timeout.connect(func():
					if is_instance_valid(caster): run([ee], caster, ctx))
				continue
			_one(e, caster, ctx)

static func _m(caster: Node) -> Node:
	return caster.get("m") if caster else null

static func _aim_dir(caster: Node, ctx: Dictionary) -> Vector2:
	if ctx.has("dir"):
		return ctx["dir"]
	if caster is Hunter:
		return (caster as Hunter).aim_dir()
	var at: Vector3 = ctx.get("aim", caster.pos)
	var d := Vector2(at.x - caster.pos.x, at.z - caster.pos.z)
	return d.normalized() if d.length() > 0.01 else Vector2(0, -1)

static func _aim_point(caster: Node, ctx: Dictionary) -> Vector3:
	if ctx.has("aim"):
		return ctx["aim"]
	if caster is Hunter:
		return (caster as Hunter).inp.get("aim", caster.pos)
	return caster.pos

static func _hit_opts(e: Dictionary, ctx: Dictionary, kb: Vector2) -> Dictionary:
	var o := {"src": "abil", "ab": String(ctx.get("slot", "")), "tags": [String(ctx.get("slot", "")), String(ctx.get("ability", ""))]}
	if kb.length() > 0.01: o["kb"] = kb
	for k in ["lift", "stun", "slow", "root", "burn"]:
		if e.has(k): o[k] = float(e[k])
	return o

static func _one(e: Dictionary, caster: Node, ctx: Dictionary) -> void:
	var m = _m(caster)
	if m == null:
		return
	var col := Color(String(e.get("color", "#ffffff")))
	match String(e.get("type", "")):
		"projectile":
			var d := _aim_dir(caster, ctx)
			var n := int(e.get("count", 1))
			var spread := float(e.get("spread", 0.0))
			var spd := float(e.get("speed", 20.0))
			var y: float = caster.pos.y + (0.95 if caster is Hunter else 0.6)
			for i in n:
				var a := atan2(d.y, d.x) + (spread * (float(i) / maxf(1.0, n - 1) - 0.5) if n > 1 else 0.0)
				var dir := Vector2(cos(a), sin(a))
				var start := Vector3(caster.pos.x + dir.x * 0.6, y, caster.pos.z + dir.y * 0.6)
				var extra := _hit_opts(e, ctx, Vector2.ZERO)
				extra["kb"] = float(e.get("kb", 0.0))
				if e.has("on_end"): extra["fx_end"] = e["on_end"]
				if e.has("on_hit"): extra["fx_hit"] = e["on_hit"]
				extra["fx_ctx"] = ctx
				m.spawn_shot(caster, start, dir * spd, float(e.get("dmg", 0.0)) * m.dmg_mult(caster if caster is Hunter else null), float(e.get("range", 10.0)) / spd, float(e.get("size", 0.15)), col, extra)
			m.sfx(String(e.get("sfx", "throw")), caster.pos, -3.0, float(e.get("pitch", 1.0)))
		"area":
			var at: Vector3 = caster.pos
			match String(e.get("at", "here" if ctx.has("at") else "self")):
				"aim": at = _aim_point(caster, ctx)
				"here": at = ctx.get("at", caster.pos)
			var r := float(e.get("radius", 2.0))
			m.fx.ring(at, r, col, 0.3)
			m.fx.burst(at + Vector3(0, 0.4, 0), col, int(clampf(r * 10.0, 8.0, 30.0)), 5.0, 0.45, 6.0, 1.1)
			m.sfx("boom", at, -3.0 if r > 2.0 else -7.0, 1.3 - minf(0.5, r * 0.1))
			if r > 2.0: m.shake(0.3, at)
			for f in m.foes_of(caster.team):
				var rel := Vector2(f.pos.x - at.x, f.pos.z - at.z)
				if rel.length() < r + f.r and absf(f.pos.y - at.y) < 2.0:
					var kb := rel.normalized() * float(e.get("kb", 0.0)) if rel.length() > 0.05 else Vector2.ZERO
					f.hurt(float(e.get("dmg", 0.0)) * m.dmg_mult(caster if caster is Hunter else null), caster, _hit_opts(e, ctx, kb))
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
			var d := _aim_dir(caster, ctx)
			caster.vel = Vector3(d.x * float(e.get("forward", 6.0)), float(e.get("up", 12.0)), d.y * float(e.get("forward", 6.0)))
			caster.grounded = false
			m.fx.burst(caster.pos + Vector3(0, 0.3, 0), col, 14, 4.0, 0.4, -2.0)
		"heal":
			caster.heal(float(e.get("amount", 20.0)))
			m.fx.burst(caster.pos + Vector3(0, 1.0, 0), Color("8fe0a0"), 12, 2.5, 0.5, -3.0)
		"shield":
			if "shield" in caster:
				caster.shield = maxf(float(caster.shield), float(e.get("amount", 40.0)))
		"haste":
			if "haste_t" in caster:
				caster.haste_t = maxf(float(caster.haste_t), float(e.get("time", 2.0)))
