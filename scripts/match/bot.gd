class_name Bot
extends RefCounted
## Bot hunters. They fight, farm monsters, open chests, catch kin, revive teammates and head for exits.

func new_mind(rng: RandomNumberGenerator, skill: float) -> Dictionary:
	return {"skill": clampf(skill + rng.randf_range(-0.15, 0.15), 0.2, 1.0), "think": 0.0, "tgt": null, "goal": Vector3.INF,
		"goal_kind": "", "strafe": 1.0 if rng.randf() < 0.5 else -1.0, "strafe_t": 0.0, "dash_cd": rng.randf_range(1, 3),
		"jump_cd": rng.randf_range(2, 5), "throw_cd": rng.randf_range(1.5, 4), "aim_err": Vector2.ZERO, "hurt_hp": 0.0,
		"wander": Vector3.INF, "stuck": 0.0, "last_pos": Vector3.ZERO}

func think(m: Match, h: Hunter, dt: float) -> void:
	var a := h.ai
	a["think"] -= dt
	a["dash_cd"] -= dt; a["jump_cd"] -= dt; a["throw_cd"] -= dt; a["strafe_t"] -= dt
	var inp := h.inp
	inp["fire"] = false
	inp["interact"] = false
	if h.downed:
		_crawl(m, h)
		return
	if h.dropping:
		# steer the opening glide toward the chosen landing spot
		var land: Vector3 = a.get("land", h.pos)
		var to := Vector2(land.x - h.pos.x, land.z - h.pos.z)
		# too far to glide to from this height: settle for the closest island spot in reach
		var reach := maxf(0.0, (h.pos.y + 1.0) / Hunter.DROP_FALL * Hunter.DROP_SPEED)
		if to.length() > reach * 0.85 and not a.get("retarget", false):
			a["retarget"] = true
			var best := land; var bd := 1e9
			for sp in m.world.spawns + m.world.portal_spots:
				var d := Vector2(sp.x - h.pos.x, sp.z - h.pos.z).length()
				var score := d if d < reach * 0.8 else d + 1000.0
				if score < bd: bd = score; best = sp
			a["land"] = best
			land = best
			to = Vector2(land.x - h.pos.x, land.z - h.pos.z)
		inp["move"] = to.normalized() if to.length() > 0.6 else Vector2.ZERO
		return
	if a["think"] <= 0.0:
		a["think"] = randf_range(0.12, 0.3) / (0.6 + a["skill"])
		_choose(m, h)
	# crossing to another island on a glide route: run off the edge, jump, open the glider at the
	# top of the jump and steer for the landing (through any rings on the way)
	if a.has("cross"):
		var L: Dictionary = a["cross"]
		var land: Vector3 = L["land"]
		var tol := Vector2(land.x - h.pos.x, land.z - h.pos.z)
		a["cross_t"] = float(a.get("cross_t", 12.0)) - dt
		if (h.grounded and m.world.island_of(h.pos.x, h.pos.z) == int(L["to"])) or float(a["cross_t"]) <= 0.0:
			a.erase("cross"); a.erase("cross_t")
		elif not h.grounded and a.get("cross_go", false) and not (m.world.is_void(h.pos.x, h.pos.z) and h.pos.y < land.y - 1.2 and h.vel.y < 0.0):
			inp["move"] = tol.normalized()
			# over the landing: fold the glider and drop onto it
			inp["glide"] = tol.length() > 1.6 or m.world.is_void(h.pos.x, h.pos.z)
			if not h.gliding and h.vel.y < 1.0 and h.can_glide():
				inp["jump"] = true
			return
		elif h.grounded and h.flat_dist(L["take"]) < 0.9 and h.glide_fuel > 0.6:
			inp["move"] = tol.normalized()
			inp["jump"] = true
			a["cross_go"] = true
			return
		else:
			a["cross_go"] = false
	var tgt: Ent = a["tgt"]
	var move := Vector2.ZERO
	# ---- combat
	var finishing: bool = tgt is Hunter and tgt.downed and not tgt.out
	if tgt and not tgt.dead and tgt.hittable() and (finishing or not (tgt is Hunter and not tgt.targetable())):
		var d := h.flat_dist(tgt)
		var to := h.dir_to(tgt)
		var pref: float = {"light": 4.5, "medium": 7.0, "heavy": 5.5}[h.cls]
		if h.wid == "rail": pref = 11.0
		if d > pref + 1.5:
			move = to
		elif d < pref - 2.0:
			move = -to
		if a["strafe_t"] <= 0.0:
			a["strafe_t"] = randf_range(0.6, 1.6)
			a["strafe"] = -a["strafe"]
		move += Vector2(-to.y, to.x) * a["strafe"] * 0.8
		# aim with lead and some error that shrinks with skill
		var lead: Vector2 = Vector2(tgt.vel.x, tgt.vel.z) * (d / float(h.wpn["speed"])) * a["skill"]
		if randf() < dt * 3.0:
			a["aim_err"] = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * (1.15 - a["skill"]) * 1.8
		var aim: Vector2 = Vector2(tgt.pos.x, tgt.pos.z) + lead + a["aim_err"]
		inp["aim"] = Vector3(aim.x, tgt.pos.y + 0.9, aim.y)
		var los: bool = m.world.los(h.pos, tgt.pos, h.pos.y + 0.95)
		if los and d < float(h.wpn["range"]) + 0.5:
			inp["fire"] = true
		elif not los:
			move = to
		# kin
		var k: Kin = h.kin
		if k and a["throw_cd"] <= 0.0:
			if k.state == "shoulder" and d < 8.0 and (tgt is Hunter or (tgt is Mob and tgt.mkind == "brute") or randf() < 0.3):
				k.throw_to(Vector3(tgt.pos.x, tgt.pos.y, tgt.pos.z))
				a["throw_cd"] = randf_range(4, 8)
			elif k.state == "active" and k.skill_cd <= 0.0 and k.flat_dist(tgt) < 6.0:
				k.command_skill(tgt.pos)
				a["throw_cd"] = randf_range(1, 3)
			elif k.state == "active" and (k.hp < k.max_hp * 0.3 or k.flat_dist(h) > 11.0):
				k.recall()
				a["throw_cd"] = 2.0
		# defensive moves
		if h.hp < a["hurt_hp"] - 12.0 and a["dash_cd"] <= 0.0:
			a["dash_cd"] = randf_range(1.2, 3.0) / (0.5 + a["skill"])
			var side: Vector2 = Vector2(-to.y, to.x) * a["strafe"]
			if _safe(m, h, side, 3.5) and _safe(m, h, side, 5.0):
				a["dash_dir"] = side
				inp["dash"] = true
		a["hurt_hp"] = h.hp
		if a["jump_cd"] <= 0.0 and randf() < 0.3:
			a["jump_cd"] = randf_range(2.5, 6)
			inp["jump"] = true
		_use_sig(m, h, tgt)
		_use_sec(m, h, tgt)
	else:
		a["tgt"] = null
		var goal: Vector3 = a["goal"]
		if goal != Vector3.INF:
			move = _path_dir(m, h, goal)
			inp["aim"] = Vector3(h.pos.x + move.x * 3.0, h.pos.y + 0.9, h.pos.z + move.y * 3.0)
			if h.flat_dist(goal) < 1.5 and a["goal_kind"] in ["chest", "catch", "revive"]:
				inp["interact"] = true
				move = Vector2.ZERO
		if h.kin and h.kin.state == "active" and h.kin.flat_dist(h) > 6.0:
			h.kin.recall()
		if h.hp < h.max_hp * 0.45 and h.tonics > 0:
			inp["tonic"] = true
		if Abil.e_id(h) == "mend" and h.sig_cd <= 0.0 and h.hp < h.max_hp * 0.6:
			inp["sig"] = true
	# ---- don't walk off edges (except onto the jump pad we're heading for), and keep off other pads
	var to_pad: bool = (a.has("pad_at") and h.flat_dist(a["pad_at"]) < 2.5) or (a.has("cross") and h.flat_dist(a["cross"]["take"]) < 2.5)
	for pd in m.world.pads:
		if a.has("pad_at") and pd["pos"] == a["pad_at"]:
			continue
		var dp: float = h.flat_dist(pd["pos"])
		if dp < 1.8 and move.length() > 0.1:
			move += -h.dir_to(pd["pos"]) * (1.8 - dp) * 1.5
	a.erase("pad_at")
	if move.length() > 0.01:
		move = move.normalized()
		if not to_pad and not _safe(m, h, move, 1.2):
			var alt := Vector2(-move.y, move.x)
			if _safe(m, h, alt, 1.2): move = alt
			elif _safe(m, h, -alt, 1.2): move = -alt
			else: move = -move
	# walk around rocks and walls we keep bumping into
	if a.get("detour_t", 0.0) > 0.0:
		a["detour_t"] -= dt
		var dd: Vector2 = a["detour_dir"]
		if _safe(m, h, dd, 1.2):
			move = dd
	inp["move"] = move
	if a.has("dash_dir"):
		inp["move"] = a["dash_dir"]
		a.erase("dash_dir")
	# recover if knocked off: jump toward the nearest ground, then glide back to it
	inp["glide"] = false
	if not h.grounded and h.over_void():
		if h.vel.y < 0.0 and h.coyote > 0.0:
			inp["jump"] = true
		var back := _nearest_ground(m, h)
		if back != Vector2.ZERO:
			inp["move"] = back
			inp["glide"] = h.ai["skill"] > 0.35
	# unstick
	if Vector2(h.pos.x - a["last_pos"].x, h.pos.z - a["last_pos"].z).length() < 0.03 and move.length() > 0.5:
		a["stuck"] += dt
		if a["stuck"] > 0.6:
			if _safe(m, h, move, 2.0) and randf() < 0.5:
				inp["jump"] = true
			else:
				a["detour_t"] = randf_range(0.5, 1.1)
				a["detour_dir"] = Vector2(-move.y, move.x) * (1.0 if randf() < 0.5 else -1.0)
			a["stuck"] = 0.0
	else:
		a["stuck"] = 0.0
	a["last_pos"] = h.pos

func _nearest_ground(m: Match, h: Hunter) -> Vector2:
	var best := Vector2.ZERO; var bd := 1e9
	for a in 16:
		var ang := TAU * a / 16.0
		var dv := Vector2(cos(ang), sin(ang))
		for r in [2.0, 4.0, 6.0, 9.0, 12.0]:
			var x: float = h.pos.x + dv.x * r; var z: float = h.pos.z + dv.y * r
			if not m.world.is_void(x, z) and not m.world.is_block(x, z) and m.world.ground_at(x, z) < h.pos.y + 1.5:
				if r < bd: bd = r; best = dv
				break
	return best

func _safe(m: Match, h: Hunter, d: Vector2, dist: float) -> bool:
	for k in [0.5, 1.0]:
		var p: Vector2 = Vector2(h.pos.x, h.pos.z) + d * dist * k
		if m.world.is_void(p.x, p.y):
			return false
	return true

func _crawl(m: Match, h: Hunter) -> void:
	var best: Hunter = null; var bd := 1e9
	for o in m.hunters:
		if o != h and o.team == h.team and not o.downed and not o.out:
			var d := h.flat_dist(o)
			if d < bd: bd = d; best = o
	var mv := Vector2.ZERO
	if best and bd > 1.2:
		mv = h.dir_to(best)
	if mv.length() > 0 and not _safe(m, h, mv, 1.0):
		mv = Vector2.ZERO
	h.inp["move"] = mv

## Right-click secondaries: each hero's own read on when it pays off.
func _use_sec(m: Match, h: Hunter, tgt: Ent) -> void:
	var id := Abil.s_id(h)
	h.inp["sec_hold"] = false
	if id == "" or tgt == null:
		return
	var d := h.flat_dist(tgt)
	var hurt := h.hp < h.max_hp * 0.5
	var facing: bool = tgt is Hunter and h.aim_dir().dot(h.dir_to(tgt)) > 0.6
	if id == "brightshield":
		h.inp["sec_hold"] = (hurt or h.armor <= 0.0) and facing and d < 12.0
		if h.inp["sec_hold"] and not h.bshield_on and h.sec_cd <= 0.0:
			h.inp["sec"] = true
		return
	if id == "satchel" and not h.satchel.is_empty():
		var sp: Vector3 = h.satchel["pos"]
		if Vector2(tgt.pos.x - sp.x, tgt.pos.z - sp.z).length() < 2.6 and float(h.satchel["t"]) < 5.3:
			h.inp["sec"] = true
		return
	if id == "breeze":
		if h.sec_ch > 0 and (hurt or (d < 2.5 and randf() < 0.05)):
			h.inp["sec"] = true
		return
	if h.sec_cd > 0.0:
		return
	var go := false
	match id:
		"shadowstep", "bolas", "binding": go = d < 9.0 and randf() < 0.1
		"divehawk": go = d < 8.0 and randf() < 0.1
		"haymaker", "cleave": go = d < 2.3
		"satchel": go = d < 7.5 and randf() < 0.08
	if tgt is Mob and (tgt as Mob).stag_open > 0.0 and d < 6.0:
		go = true
	if go:
		h.inp["sec"] = true

## Hero abilities: E when it fits the moment, R once it's charged and worth it.
func _use_sig(m: Match, h: Hunter, tgt: Ent) -> void:
	var d := h.flat_dist(tgt) if tgt else 1e9
	var to := h.dir_to(tgt) if tgt else Vector2.ZERO
	var hurt := h.hp < h.max_hp * 0.45
	if h.sig_cd <= 0.0:
		var go := false
		match Abil.e_id(h):
			"cloak": go = hurt
			"mend": go = h.hp < h.max_hp * 0.55 or m.hunters.any(func(o): return o != h and o.team == h.team and o.downed and o.flat_dist(h) < 5.0)
			"fortify": go = d < 7.0 and h.hp < h.max_hp * 0.8
			"blink": go = d > 3.0 and d < 8.0 and randf() < 0.25 and _safe(m, h, to, minf(d, 6.0))
			"tether": go = d < 12.0 and tgt is Hunter
			"hook": go = d > 3.0 and d < 8.5 and (tgt is Hunter or (tgt is Mob and tgt.mkind != "brute" and tgt.mkind != "warden"))
			"rocketjump":
				go = (d < 2.4 and randf() < 0.4) or (hurt and randf() < 0.3)
				if hurt and go:
					h.inp["aim"] = Vector3(h.pos.x - to.x * 6.0, h.pos.y, h.pos.z - to.y * 6.0)
			"ram": go = d < 5.5 and d > 1.0 and _safe(m, h, to, d + 1.5)
			"dome": go = tgt is Hunter and h.hp < h.max_hp * 0.65
		# a staggerable monster in reach: any damaging ability will do
		if tgt is Mob and (tgt as Mob).stag_open > 0.0 and d < 6.0 and Abil.e_id(h) in ["tether", "hook", "rocketjump", "ram"]:
			go = true
		if go:
			h.inp["sig"] = true
	if h.ult >= 1.0 and tgt:
		var go_r := false
		match Abil.r_id(h):
			"vanish": go_r = hurt
			"sanctuary", "bulwark": go_r = h.hp < h.max_hp * 0.6 and d < 8.0
			"dance": go_r = d < 8.0
			"skypierce": go_r = d < 20.0 and m.world.los(h.pos, tgt.pos, h.pos.y + 0.95)
			"anchor": go_r = d < 9.0 and _safe(m, h, to, d)
			"barrage", "well": go_r = d < 10.0
			"quake": go_r = d < 6.0
		if go_r:
			h.inp["ult"] = true

func _choose(m: Match, h: Hunter) -> void:
	var a := h.ai
	# fight: nearest rival hunter in sight, else monsters close by
	var best: Ent = null; var bs := -1e9
	for o in m.hunters:
		if o.team == h.team or not o.targetable():
			continue
		if o is Hunter and not m.can_see(h.team, o):
			continue
		var d := h.flat_dist(o)
		# early on bots farm monsters and only fight hunters who come close or shoot them
		var reach := 13.0 if m.time > 100.0 or h.last_hit_by == o or (o is Hunter and h.last_hit_by == o.kin) else 8.0
		if d > reach or absf(o.pos.y - h.pos.y) > 3.0:
			continue
		if not m.world.los(h.pos, o.pos, h.pos.y + 0.95) and d > 4.0:
			continue
		var s: float = 20.0 - d + (6.0 if o == a["tgt"] else 0.0) - o.hp * 0.03
		if s > bs: bs = s; best = o
	if best == null:
		for mb in m.mobs:
			if mb.dead: continue
			var d := h.flat_dist(mb)
			if d < 8.0 and absf(mb.pos.y - h.pos.y) < 2.0 and m.world.los(h.pos, mb.pos, h.pos.y + 0.95):
				var s := 10.0 - d
				if mb.tgt == h: s += 5.0
				if s > bs: bs = s; best = mb
	# finish off downed rivals before their kin or team picks them up
	if best == null:
		for o in m.hunters:
			if o.team != h.team and o.downed and not o.out and h.flat_dist(o) < 11.0 and m.world.los(h.pos, o.pos, h.pos.y + 0.95):
				best = o; break
	# angry wild kin also count
	if best == null:
		for k in m.kins:
			if k.is_wild() and k.state == "wild" and not k.dead and h.flat_dist(k) < 7.0 and (k.angry_at == h or randf() < 0.5):
				best = k; break
	a["tgt"] = best
	if best:
		return
	# no fight: pick a goal
	var time_left := m.length - m.time
	var goal := Vector3.INF; var gk := ""
	for o in m.hunters:
		if o != h and o.team == h.team and o.downed and not o.out:
			goal = o.pos; gk = "revive"; break
	if goal == Vector3.INF:
		var open_portals := m.portals.filter(func(p): return p["open"])
		if open_portals.size() > 0 and (time_left < 110.0 or h.gems > 40 or randf() < 0.002):
			var bp = null; var bd := 1e9
			for p in open_portals:
				if _banned(m, a, p["pos"]) and open_portals.size() > 1:
					continue
				var d := h.flat_dist(p["pos"])
				if d < bd: bd = d; bp = p
			if bp == null:
				bp = open_portals.pick_random()
			goal = bp["pos"]; gk = "portal"
	if goal == Vector3.INF:
		for k in m.kins:
			if k.state == "dazed" and not k.dead and h.flat_dist(k) < 14.0:
				goal = k.pos; gk = "catch"; break
	if goal == Vector3.INF:
		var bd := 18.0
		for c in m.chests:
			if c["open"]: continue
			var d := h.flat_dist(c["pos"])
			if d < bd: bd = d; goal = c["pos"]; gk = "chest"
	if goal == Vector3.INF:
		var bd := 12.0
		for p in m.pickups:
			if m.world.is_void(p["pos"].x, p["pos"].z):
				continue
			var d := h.flat_dist(p["pos"])
			if d < bd: bd = d; goal = p["pos"]; gk = "loot"
	if goal == Vector3.INF:
		# roam toward monsters or another island
		if a["wander"] == Vector3.INF or h.flat_dist(a["wander"]) < 2.0 or randf() < 0.02:
			var alive_mobs := m.mobs.filter(func(x): return not x.dead)
			if alive_mobs.size() > 0 and randf() < 0.6:
				a["wander"] = alive_mobs.pick_random().pos
			else:
				a["wander"] = m.world.random_ground()
		goal = a["wander"]; gk = "roam"
	# give up on goals we can't seem to reach
	if goal != a["goal"]:
		a["goal_best"] = 1e9
		a["goal_since"] = m.time
	elif goal != Vector3.INF:
		var d := h.flat_dist(goal)
		if d < float(a.get("goal_best", 1e9)) - 0.5:
			a["goal_best"] = d
			a["goal_since"] = m.time
		elif m.time - float(a.get("goal_since", m.time)) > 14.0:
			var bans: Dictionary = a.get("banned", {})
			bans[goal] = m.time + 20.0
			a["banned"] = bans
			a["goal_since"] = m.time
			a["goal_best"] = 1e9
	if _banned(m, a, goal):
		goal = m.world.random_ground(); gk = "roam"
	a["goal"] = goal
	a["goal_kind"] = gk

## Direction to walk toward a goal, using jump pads to cross to other islands.
func _path_dir(m: Match, h: Hunter, goal: Vector3) -> Vector2:
	var here := m.world.island_of(h.pos.x, h.pos.z)
	var there := m.world.island_of(goal.x, goal.z)
	if here < 0 or there < 0 or here == there:
		if here >= 0 and h.grounded: h.ai.erase("cross")
		return _steer(m, h, goal)
	# breadth-first search over the island graph
	var prev := {here: -1}
	var q := [here]
	while q.size() > 0:
		var cur: int = q.pop_front()
		if cur == there:
			break
		for pd in m.world.pads + m.world.links:
			if pd["from"] == cur and not prev.has(pd["to"]):
				prev[pd["to"]] = cur
				q.append(pd["to"])
	if not prev.has(there):
		return h.dir_to(goal)
	var nxt := there
	while prev[nxt] != here and prev[nxt] != -1:
		nxt = prev[nxt]
	for pd in m.world.pads:
		if pd["from"] == here and pd["to"] == nxt:
			h.ai["pad_at"] = pd["pos"]
			h.ai.erase("cross")
			return _steer(m, h, pd["pos"])
	for lk in m.world.links:
		if lk["from"] == here and lk["to"] == nxt:
			if not h.ai.has("cross") or h.ai["cross"] != lk:
				h.ai["cross"] = lk
				h.ai["cross_t"] = 14.0
			return _steer(m, h, lk["take"])
	return h.dir_to(goal)

## Heads for a spot on this island, finding a way around walls when they're in the way.
func _steer(m: Match, h: Hunter, goal: Vector3) -> Vector2:
	var from := Vector2(h.pos.x, h.pos.z)
	var to := Vector2(goal.x, goal.z)
	if _clear_line(m, from, to):
		h.ai.erase("wp")
		return h.dir_to(goal)
	var gt := Vector2i(int(floor(goal.x)), int(floor(goal.z)))
	var wp: Dictionary = h.ai.get("wp", {})
	if wp.is_empty() or wp["goal"] != gt or m.time - float(wp["t"]) > 2.0:
		wp = {"goal": gt, "t": m.time, "path": _grid_path(m, Vector2i(int(floor(h.pos.x)), int(floor(h.pos.z))), gt)}
		h.ai["wp"] = wp
	var path: Array = wp["path"]
	if path.is_empty():
		return h.dir_to(goal)
	# aim for the furthest waypoint we can walk straight to
	var pick: Vector2 = path[0]
	for i in range(path.size() - 1, -1, -1):
		if _clear_line(m, from, path[i]):
			pick = path[i]
			break
	while path.size() > 1 and from.distance_to(path[0]) < 0.6:
		path.pop_front()
	var d := pick - from
	return d.normalized() if d.length() > 0.05 else h.dir_to(goal)

func _clear_line(m: Match, a: Vector2, b: Vector2) -> bool:
	var d := b - a
	var n := int(d.length() / 0.4) + 1
	var side := Vector2(-d.y, d.x).normalized() * 0.32
	for k in range(1, n + 1):
		var p := a + d * (float(k) / n)
		if m.world.is_block(p.x, p.y) or m.world.is_block(p.x + side.x, p.y + side.y) or m.world.is_block(p.x - side.x, p.y - side.y):
			return false
	return true

## Breadth-first search over walkable tiles (a window around the trip), returning tile centres.
func _grid_path(m: Match, a: Vector2i, b: Vector2i) -> Array:
	var W: World = m.world
	var lo := Vector2i(mini(a.x, b.x) - 8, mini(a.y, b.y) - 8)
	var hi := Vector2i(maxi(a.x, b.x) + 8, maxi(a.y, b.y) + 8)
	var prev := {a: a}
	var q: Array = [a]
	var found := false
	var steps := 0
	while q.size() > 0 and steps < 4000:
		steps += 1
		var cur: Vector2i = q.pop_front()
		if cur == b or (absi(cur.x - b.x) <= 1 and absi(cur.y - b.y) <= 1 and W.is_block(b.x + 0.5, b.y + 0.5)):
			b = cur
			found = true
			break
		for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: Vector2i = cur + dv
			if prev.has(nx) or nx.x < lo.x or nx.y < lo.y or nx.x > hi.x or nx.y > hi.y or not W.inb(nx.x, nx.y):
				continue
			var i := W.idx(nx.x, nx.y)
			if W.kind[i] != World.T_GROUND:
				continue
			if absf(W.ground_at(nx.x + 0.5, nx.y + 0.5) - W.ground_at(cur.x + 0.5, cur.y + 0.5)) > 1.7:
				continue
			prev[nx] = cur
			q.append(nx)
	if not found:
		return []
	var out: Array = []
	var c := b
	while c != a:
		out.push_front(Vector2(c.x + 0.5, c.y + 0.5))
		c = prev[c]
	return out

func _banned(m: Match, a: Dictionary, p: Vector3) -> bool:
	var bans: Dictionary = a.get("banned", {})
	return bans.has(p) and float(bans[p]) > m.time
