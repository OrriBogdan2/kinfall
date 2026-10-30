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
##
## Verbs (things that stay in the world, see Verbs):
##   projectile  + from:"here" pierce bounce:n return rope deco:"disc"|"hook"|"orb" on_wall:[...] ring
##   yank        to:"caster"|"here" gap time stun          (pulls ctx.target, what a shot hit, to you)
##   zip         time                                      (flies the caster to where a shot stopped)
##   swap        who:"self"|"owner" miss_blink             (trade places with ctx.target)
##   wall        at:"aim"|"front" length hp time dist block:"enemy"|"all" move reflect follow touch:{}
##   reflect     radius arc time dmg_k riposte target      (shots that reach it fly back at the shooter)
##   tether      max time dmg stun yank                    (leash ctx.target; it snaps if they run)
##   trap        radius arm time count spread reveal on_trigger:[...]   (fires on the first foe to step on it)
##   bridge      length width time                        (abyss tiles along the aim become ground)
##   line        length width steps every dmg lift stun slow burn kb   (a fissure erupting along the aim)
##   cloak time      reveal radius time      decoy time      ally_area radius heal shield haste cleanse at
##   area/cone   + spike:{dmg, stun} (extra on airborne foes, slammed down)   launch + dir:"back"
## Any effect can carry "echo": {delay, k} (it repeats at the same spot, k times as strong) and
## "charged": {key: [lo, hi]} (numbers that grow with a held charge, ctx.charge 0..1).

static func run(effects: Array, caster: Node, ctx: Dictionary) -> void:
	if caster == null or not is_instance_valid(caster):
		return
	effects = _readable(effects, caster)
	for e0 in effects:
		if e0 is Dictionary:
			var e: Dictionary = e0
			if e.has("charged"):
				e = _charged(e, ctx)
			var delay := float(e.get("delay", 0.0))
			if (delay > 0.0 or e.has("echo")) and caster.is_inside_tree() and not ctx.has("aim") and caster is Hunter:
				# a delayed or repeating effect lands where you aimed when you cast it
				ctx = ctx.duplicate()
				ctx["aim"] = _aim_point(caster, ctx)
			if e.has("echo"):
				# echo: the same effect again a beat later at the same spot, a little weaker
				var ec: Dictionary = e["echo"]
				var e2: Dictionary = e.duplicate(true)
				e2.erase("echo")
				e2["delay"] = float(e.get("delay", 0.0)) + float(ec.get("delay", 0.8))
				for kk in ["dmg", "kb", "strength", "heal", "amount"]:
					if e2.has(kk): e2[kk] = float(e2[kk]) * float(ec.get("k", 0.5))
				e2["color"] = Color(String(e.get("color", "#ffffff"))).lightened(0.35).to_html(false)
				var c2: Dictionary = ctx.duplicate()
				if not c2.has("at") and String(e.get("at", "")) in ["self", "here", ""] and not caster is Kin:
					c2["at_fixed"] = caster.pos
				run([e2], caster, c2)
				e = e.duplicate(); e.erase("echo")
			delay = float(e.get("delay", 0.0))
			if delay > 0.0 and caster.is_inside_tree():
				var ee: Dictionary = e.duplicate()
				ee.erase("delay")
				caster.get_tree().create_timer(delay, false).timeout.connect(func():
					if is_instance_valid(caster) and not caster.dead: run([ee], caster, ctx))
				continue
			_one(e, caster, ctx)

## "charged": {"dmg": [6, 40]} sets dmg between 6 and 40 by how long the ability was held.
static func _charged(e: Dictionary, ctx: Dictionary) -> Dictionary:
	var k := clampf(float(ctx.get("charge", 1.0)), 0.0, 1.0)
	var out := e.duplicate()
	var ch: Dictionary = e["charged"]
	for key in ch:
		var lohi: Array = ch[key]
		out[key] = lerpf(float(lohi[0]), float(lohi[1]), k)
	out.erase("charged")
	return out

## Readability: an area attack someone on the other side lands on you gets a short wind-up: a
## ground marker that fills, then the hit. Your own casts stay instant.
const ENEMY_WINDUP := 0.32

static func _readable(effects: Array, caster: Node) -> Array:
	var m := _m(caster)
	if m == null or m.get("player") == null or caster == null:
		return effects
	var own: Node = owner_of(caster)
	if own == null or own.get("team") == null or int(own.team) == int(m.player.team):
		return effects
	var out: Array = []
	for e in effects:
		if e is Dictionary and String(e.get("type", "")) == "area" and not e.has("delay") and String(e.get("at", "self")) == "aim" and float(e.get("radius", 2.0)) >= 1.4:
			out.append({"type": "telegraph", "radius": float(e.get("radius", 2.0)), "time": ENEMY_WINDUP, "at": "aim", "color": String(e.get("color", "ff6a4a"))})
			var ee: Dictionary = e.duplicate()
			ee["delay"] = ENEMY_WINDUP
			out.append(ee)
		else:
			out.append(e)
	return out

## Recall weakness: healing and shields from someone who just based to a teammate are halved.
static func _weak_k(caster: Node) -> float:
	var o: Node = owner_of(caster)
	return 0.5 if o and "weak_t" in o and float(o.weak_t) > 0.0 else 1.0

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

## Ground-targeted effects land at the cursor, clamped to a hunter's reach (10m by default, or the
## effect's own "range"), so how far the mouse is sets how far the effect goes.
const HUNTER_REACH := 10.0

static func _aim_point(caster: Node, ctx: Dictionary) -> Vector3:
	if ctx.has("aim"):
		return ctx["aim"]
	if caster is Hunter:
		var a: Vector3 = (caster as Hunter).inp.get("aim", caster.pos)
		var d := Vector2(a.x - caster.pos.x, a.z - caster.pos.z)
		var reach := float(ctx.get("reach", HUNTER_REACH))
		if d.length() > reach:
			d = d.normalized() * reach
			a = Vector3(caster.pos.x + d.x, a.y, caster.pos.z + d.y)
		return a
	return caster.pos

static func _where(e: Dictionary, caster: Node, ctx: Dictionary, default := "self") -> Vector3:
	if ctx.has("at_fixed") and String(e.get("at", default)) in ["self", "here"]:
		return ctx["at_fixed"]
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
			var origin: Vector3 = caster.pos
			var y: float = caster.pos.y + (0.95 if caster is Hunter else 0.5)
			var lead := 0.6
			if String(e.get("from", "")) == "here" and ctx.has("at"):
				# split / burst shots start from wherever the parent landed
				origin = ctx["at"]; y = origin.y + 0.2; lead = 0.25
				if ctx.has("dir"): d = ctx["dir"]
			var ring := bool(e.get("ring", false))
			for i in n:
				var a := atan2(d.y, d.x) + (spread * (float(i) / maxf(1.0, n - 1) - 0.5) if n > 1 else 0.0)
				if ring: a = atan2(d.y, d.x) + TAU * float(i) / float(n)
				var dir := Vector2(cos(a), sin(a))
				var start := Vector3(origin.x + dir.x * lead, y, origin.z + dir.y * lead)
				var extra := _hit_opts(e, ctx, Vector2.ZERO, caster)
				extra["kb"] = float(e.get("kb", 0.0))
				if caster is Kin: extra["kin"] = true
				if e.has("on_end"): extra["fx_end"] = e["on_end"]
				if e.has("on_hit"): extra["fx_hit"] = e["on_hit"]
				if e.has("on_wall"): extra["fx_wall"] = e["on_wall"]
				for kk in ["pierce", "bounce", "return", "rope", "deco", "spin"]:
					if e.has(kk): extra[kk] = e[kk]
				if e.get("pierce", false) or e.get("return", false): extra["hitset"] = {}
				if String(e.get("from", "")) == "here": extra["cos_free"] = true
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
					if float(e.get("kb", 0.0)) < 0.0 and rel.length() <= 0.05: kb = Vector2.ZERO
					var o := _hit_opts(e, ctx, kb, caster)
					var dmg := float(e.get("dmg", 0.0)) * pw
					if e.has("spike") and not f.grounded and f.pos.y > f.ground() + 0.35:
						dmg *= 1.0 + float(e["spike"].get("dmg", 0.5))
						o["stun"] = maxf(float(o.get("stun", 0.0)), float(e["spike"].get("stun", 0.8)))
						o.erase("lift")
						m.fx.word(f.pos + Vector3(0, 2.0, 0), "SPIKED", col, true)
						f.vel.y = -16.0
					f.hurt(dmg, caster, o)
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
			# a warning marker on the ground that fills up, then disappears as the hit lands
			var at := _where(e, caster, ctx, "aim")
			var tt := float(e.get("time", 0.4))
			var tele: Node3D = m.fx.telegraph_circle(at, float(e.get("radius", 2.0)), Color(col, 0.9))
			m.sfx("warn", at, -10.0, 0.8)
			var tw := tele.create_tween()
			tw.tween_method(func(k: float): if is_instance_valid(tele): m.fx.telegraph_progress(tele, k), 0.0, 1.0, tt)
			tw.tween_callback(func(): if is_instance_valid(tele): m.fx.end_telegraph(tele))
		"rush":
			if caster is Kin:
				(caster as Kin).start_rush(_aim_dir(caster, ctx), e, ctx)
			elif caster is Hunter:
				(caster as Hunter).dash_with({"speed": float(e.get("speed", 20.0)), "time": float(e.get("distance", 6.0)) / float(e.get("speed", 20.0)), "shove": true, "shove_kb": float(e.get("kb", 6.0)), "shove_dmg": float(e.get("dmg", 8.0)), "kind": "rush"})
		"leap":
			var to := _where(e, caster, ctx, "aim")
			# everyone sees where it will come down: a ring that fills until the landing
			var lr := 2.0
			for e2 in e.get("on_land", []):
				lr = maxf(lr, float(e2.get("radius", 0.0)))
			var tele: Node3D = m.fx.telegraph_circle(to, lr, Color(col if e.has("color") else Color("ffb070"), 0.9))
			var lt := float(e.get("time", 0.5))
			var tw := tele.create_tween()
			tw.tween_method(func(k: float): if is_instance_valid(tele): m.fx.telegraph_progress(tele, k), 0.0, 1.0, lt)
			tw.tween_callback(func(): if is_instance_valid(tele): m.fx.end_telegraph(tele))
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
				if t is Hunter and String(e.get("dir", "")) != "back":
					var mv: Vector2 = (t as Hunter).inp.get("move", Vector2.ZERO)
					if mv.length() > 0.1: d = mv.normalized()
				if String(e.get("dir", "")) == "back":
					d = -d
				t.vel = Vector3(d.x * float(e.get("forward", 6.0)), float(e.get("up", 12.0)), d.y * float(e.get("forward", 6.0)))
				t.grounded = false
				if t is Hunter:
					(t as Hunter).fly_t = 0.5
					(t as Hunter).roll_t = 0.0
				m.fx.burst(t.pos + Vector3(0, 0.3, 0), col, 18, 5.0, 0.5, -2.0)
				m.sfx("whoosh", t.pos, -2.0, 1.2)
		"heal":
			for t in _targets(e, caster):
				_heal(t, float(e.get("amount", 20.0)) * _weak_k(caster))
				m.fx.burst(t.pos + Vector3(0, 1.0, 0), Color("8fe0a0"), 12, 2.5, 0.5, -3.0)
		"shield":
			for t in _targets(e, caster):
				if "shield" in t:
					t.shield = maxf(float(t.shield), float(e.get("amount", 40.0)) * _weak_k(caster))
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
		"yank":
			_yank(e, caster, ctx, m)
		"zip":
			var mover: Node = caster
			var to: Vector3 = ctx.get("at", caster.pos)
			var dd := Vector2(to.x - mover.pos.x, to.z - mover.pos.z)
			if dd.length() < 0.8:
				return
			var stop := Vector2(to.x, to.z) - dd.normalized() * 0.7
			var g: float = m.world.ground_at(stop.x, stop.y)
			var dest := Vector3(stop.x, (g + 0.05) if g > World.VOID + 1.0 and g >= to.y - 1.6 else to.y + 0.6, stop.y)
			var tt := clampf(dd.length() / float(e.get("speed", 24.0)), 0.15, 0.55)
			m.fx.bolt(mover.pos + Vector3(0, 1.0, 0), to, col)
			if mover is Hunter:
				(mover as Hunter).gliding = false
				(mover as Hunter).launch_to(dest, tt)
				(mover as Hunter).glide_cd = 0.0
			elif mover is Kin:
				(mover as Kin).start_leap(dest, {"time": tt, "height": 0.6}, ctx)
			m.sfx("whoosh", mover.pos, -2.0, 1.4)
		"swap":
			var who: Node = owner_of(caster) if String(e.get("who", "self")) == "owner" else caster
			var tgt = ctx.get("target", null)
			if tgt is Ent and is_instance_valid(tgt) and not tgt.dead and tgt.mass() < 6.0 and who is Ent:
				var a: Vector3 = who.pos; var b: Vector3 = tgt.pos
				m.fx.ghost(who.position, who.face, col, 1.0)
				m.fx.burst(a + Vector3(0, 0.9, 0), col, 16, 4.0, 0.4)
				m.fx.burst(b + Vector3(0, 0.9, 0), col, 16, 4.0, 0.4)
				m.fx.bolt(a + Vector3(0, 1.0, 0), b + Vector3(0, 1.0, 0), col)
				who.teleport(b); tgt.teleport(a)
				who.vel = Vector3.ZERO; tgt.vel = Vector3.ZERO
				if who is Hunter: (who as Hunter).gliding = false
				if tgt is Hunter: (tgt as Hunter).gliding = false
				tgt.grounded = false; who.grounded = false
				if float(e.get("stun", 0.0)) > 0.0:
					tgt.hurt(maxf(0.1, float(e.get("dmg", 0.0)) * pw), caster, {"stun": float(e["stun"]), "src": "abil", "ab": String(ctx.get("slot", "abil"))})
				m.sfx("cloak", b, -1.0, 1.5)
			elif e.get("miss_blink", false) and ctx.has("at") and who is Ent:
				var at: Vector3 = ctx["at"]
				if not m.world.is_void(at.x, at.z) and not m.world.is_block(at.x, at.z):
					m.fx.burst(who.pos + Vector3(0, 0.9, 0), col, 12, 3.0, 0.3)
					who.teleport(Vector3(at.x, m.world.ground_at(at.x, at.z), at.z))
					m.fx.burst(who.pos + Vector3(0, 0.9, 0), col, 12, 3.0, 0.3)
		"wall":
			var d := _aim_dir(caster, ctx)
			var at: Vector3
			if String(e.get("at", "aim")) == "front":
				at = caster.pos + Vector3(d.x, 0, d.y) * float(e.get("dist", 1.4))
			else:
				at = _where(e, caster, ctx, "aim")
			var g: float = m.world.ground_at(at.x, at.z)
			at.y = g if g > World.VOID + 1.0 else caster.pos.y
			m.verbs.add_wall(caster, at, d, e, pw)
		"reflect":
			for t in _targets(e, caster):
				m.verbs.add_mirror(t, e)
		"tether":
			var b = ctx.get("target", null)
			if b is Ent and is_instance_valid(b) and not b.dead:
				m.verbs.add_tether(owner_of(caster) if String(e.get("who", "self")) == "owner" else caster, b, e, pw)
		"trap":
			var at := _where(e, caster, ctx, "aim")
			var nn := int(e.get("count", 1))
			var sp := float(e.get("spread", 1.6))
			var d := _aim_dir(caster, ctx)
			for i in nn:
				var q := at
				if nn > 1:
					var a := atan2(d.y, d.x) + TAU * float(i) / float(nn)
					q = at + Vector3(cos(a), 0, sin(a)) * sp
					if m.world.is_void(q.x, q.z) or m.world.is_block(q.x, q.z): continue
					q.y = m.world.ground_at(q.x, q.z)
				m.verbs.add_trap(caster, q, e, {"slot": ctx.get("slot", ""), "ability": ctx.get("ability", ""), "power": pw})
		"bridge":
			var d := _aim_dir(caster, ctx)
			var from: Vector3 = caster.pos
			var g0: float = m.world.ground_at(from.x, from.z)
			if g0 > World.VOID + 1.0: from.y = g0
			m.verbs.add_bridge(caster, from, d, e)
		"line":
			_fissure(e, caster, ctx, m, pw, col)
		"cloak":
			for t in _targets(e, caster):
				if t is Hunter:
					(t as Hunter).cloak_t = maxf((t as Hunter).cloak_t, float(e.get("time", 2.0)))
					m.fx.burst(t.pos + Vector3(0, 0.9, 0), col, 14, 3.0, 0.4)
			m.sfx("cloak", caster.pos, -3.0)
		"reveal":
			var rad := float(e.get("radius", 18.0))
			var c0: Vector3 = owner_of(caster).pos
			for o in m.hunters:
				if o.team != caster.team and not o.out and o.flat_dist(c0) < rad:
					o.reveal_t = maxf(o.reveal_t, float(e.get("time", 3.0)))
					m.fx.ring(o.pos, 1.2, col, 0.6)
			m.fx.ring(c0, rad, Color(col, 0.6), 0.7)
			m.sfx("ping", c0, -2.0, 1.1)
		"decoy":
			var own := owner_of(caster)
			if own is Hunter:
				m.verbs.add_decoy(own, own.pos, float(e.get("time", 2.0)), col)
		"ally_area":
			var at := _where(e, caster, ctx, "aim")
			var rad := float(e.get("radius", 2.5))
			m.fx.ring(at, rad, col, 0.45)
			m.fx.burst(at + Vector3(0, 0.6, 0), col, 20, 3.0, 0.6, -3.0)
			for h in m.hunters:
				if h.team != caster.team or h.out or h.flat_dist(at) > rad + h.r:
					continue
				var who_l: Array = [h]
				if h.kin and h.kin.state in ["active", "giant"] and h.kin.flat_dist(at) < rad + 0.5: who_l.append(h.kin)
				for t in who_l:
					if float(e.get("heal", 0.0)) > 0.0: _heal(t, float(e["heal"]) * _weak_k(caster))
					if float(e.get("shield", 0.0)) > 0.0 and "shield" in t:
						t.shield = maxf(float(t.shield), float(e["shield"]) * _weak_k(caster))
						if "shield_t" in t: t.shield_t = maxf(float(t.shield_t), float(e.get("time", 4.0)))
					if float(e.get("haste", 0.0)) > 0.0 and "haste_t" in t: t.haste_t = maxf(float(t.haste_t), float(e["haste"]))
					if e.get("cleanse", false) and t is Ent:
						t.slow_t = 0.0; t.root_t = 0.0; t.stun_t = 0.0; t.burn_t = 0.0
			m.sfx("heal", at, -3.0, 1.2)

## Pull what a shot hit (ctx.target) to the caster, or every foe near ctx.at if "radius" is set.
static func _yank(e: Dictionary, caster: Node, ctx: Dictionary, m: Node) -> void:
	var anchor: Node = owner_of(caster) if String(e.get("to", "caster")) == "owner" else caster
	var victims: Array = []
	if e.has("radius"):
		var at: Vector3 = ctx.get("at", caster.pos)
		for f in m.foes_of(caster.team):
			if f.flat_dist(at) < float(e["radius"]) + f.r and f.hittable(): victims.append(f)
	elif ctx.get("target", null) is Ent and is_instance_valid(ctx["target"]):
		victims.append(ctx["target"])
	var col := Color(String(e.get("color", "#e0b05a")))
	for v in victims:
		if v.dead or v == anchor:
			continue
		var rel := Vector2(v.pos.x - anchor.pos.x, v.pos.z - anchor.pos.z)
		var dist := rel.length()
		if dist < 1.2:
			continue
		var gap := float(e.get("gap", 1.3))
		var p2 := Vector2(anchor.pos.x, anchor.pos.z) + rel.normalized() * gap
		if String(e.get("to", "caster")) == "here" and ctx.has("at"):
			var hp: Vector3 = ctx["at"]; p2 = Vector2(hp.x, hp.z)
		var g: float = m.world.ground_at(p2.x, p2.y)
		var dest := Vector3(p2.x, g if g > World.VOID + 1.0 else anchor.pos.y, p2.y)
		var tt := clampf(dist / float(e.get("speed", 26.0)), 0.14, 0.42)
		m.verbs.yank(v, dest, tt, 0.8)
		m.fx.bolt(anchor.pos + Vector3(0, 1.0, 0), v.pos + Vector3(0, 0.9, 0), col)
		if float(e.get("stun", 0.0)) > 0.0 or float(e.get("dmg", 0.0)) > 0.0 or e.has("burn") or e.has("slow"):
			var o := {"src": "kin" if caster is Kin else "abil", "ab": String(ctx.get("slot", "abil")), "tags": [String(ctx.get("slot", "")), String(ctx.get("ability", ""))]}
			for kk in ["stun", "slow", "burn", "root"]:
				if e.has(kk): o[kk] = float(e[kk])
			v.hurt(maxf(0.1, float(e.get("dmg", 0.0)) * _power(caster, ctx)), caster, o)
		m.fx.word(v.pos + Vector3(0, 2.0, 0), "HOOKED", col, false)
	if not victims.is_empty():
		m.sfx("grab", anchor.pos, -1.0, 1.1)

## A line of eruptions running out along the aim, one after another (a fissure). Each foe is hit once.
static func _fissure(e: Dictionary, caster: Node, ctx: Dictionary, m: Node, pw: float, col: Color) -> void:
	var d := _aim_dir(caster, ctx)
	var start: Vector3 = caster.pos
	var length := float(e.get("length", 8.0))
	var steps := int(e.get("steps", 6))
	var every := float(e.get("every", 0.06))
	var width := float(e.get("width", 1.3))
	var tele: Node3D = m.fx.telegraph_rect(start, d, length, width * 2.0, Color(col, 0.9))
	var total := every * steps + 0.05
	var tw := tele.create_tween()
	tw.tween_method(func(k: float): if is_instance_valid(tele): m.fx.telegraph_progress(tele, k), 0.0, 1.0, total)
	tw.tween_callback(func(): if is_instance_valid(tele): m.fx.end_telegraph(tele))
	var hit := {}
	for i in steps:
		var k := (float(i) + 1.0) / float(steps)
		var p := start + Vector3(d.x, 0, d.y) * length * k
		var go := func():
			if not is_instance_valid(caster) or caster.dead:
				return
			if m.world.is_void(p.x, p.z):
				return
			var g: float = m.world.ground_at(p.x, p.z)
			var at := Vector3(p.x, g, p.z)
			m.fx.burst(at + Vector3(0, 0.2, 0), col, 10, 6.0, 0.4, 14.0, 1.3, Vector3.UP, 20.0)
			m.fx.ring(at, width, col, 0.25)
			for f in m.foes_of(caster.team):
				if hit.has(f.get_instance_id()) or not _hits(f, at, width):
					continue
				hit[f.get_instance_id()] = true
				var side := Vector2(-d.y, d.x)
				if Vector2(f.pos.x - at.x, f.pos.z - at.z).dot(side) < 0.0: side = -side
				f.hurt(float(e.get("dmg", 12.0)) * pw, caster, _hit_opts(e, ctx, (side * 0.4 + d * 0.6).normalized() * float(e.get("kb", 0.0)), caster))
			if i % 2 == 0: m.sfx("thump", at, -6.0, 1.2)
		if i == 0: go.call()
		else: caster.get_tree().create_timer(every * i, false).timeout.connect(go)
	m.shake(0.25, start)
