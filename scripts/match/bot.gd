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
	if a["think"] <= 0.0:
		a["think"] = randf_range(0.12, 0.3) / (0.6 + a["skill"])
		_choose(m, h)
	var tgt: Ent = a["tgt"]
	var move := Vector2.ZERO
	# ---- combat
	var finishing: bool = tgt is Hunter and tgt.downed and not tgt.out
	if tgt and not tgt.dead and tgt.hittable() and (finishing or not (tgt is Hunter and not tgt.targetable())):
		var d := h.flat_dist(tgt)
		var to := h.dir_to(tgt)
		var pref: float = {"light": 4.5, "medium": 7.0, "heavy": 5.5}[h.cls]
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
		if h.cls == "medium" and h.sig_cd <= 0.0 and h.hp < h.max_hp * 0.6:
			inp["sig"] = true
	# ---- don't walk off edges (except onto the jump pad we're heading for), and keep off other pads
	var to_pad: bool = a.has("pad_at") and h.flat_dist(a["pad_at"]) < 2.5
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
	# recover if knocked off: jump toward the nearest ground
	if not h.grounded and h.over_void() and h.vel.y < 0.0 and h.coyote > 0.0:
		inp["jump"] = true
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

func _use_sig(m: Match, h: Hunter, tgt: Ent) -> void:
	if h.sig_cd > 0.0:
		return
	match h.cls:
		"light":
			if h.hp < h.max_hp * 0.45: h.inp["sig"] = true
		"medium":
			if h.hp < h.max_hp * 0.55 or m.hunters.any(func(o): return o != h and o.team == h.team and o.downed and o.flat_dist(h) < 5.0):
				h.inp["sig"] = true
		"heavy":
			if tgt and h.flat_dist(tgt) < 7.0 and h.hp < h.max_hp * 0.8: h.inp["sig"] = true

func _choose(m: Match, h: Hunter) -> void:
	var a := h.ai
	# fight: nearest rival hunter in sight, else monsters close by
	var best: Ent = null; var bs := -1e9
	for o in m.hunters:
		if o.team == h.team or not o.targetable():
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
		return h.dir_to(goal)
	# breadth-first search over the island graph
	var prev := {here: -1}
	var q := [here]
	while q.size() > 0:
		var cur: int = q.pop_front()
		if cur == there:
			break
		for pd in m.world.pads:
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
			return h.dir_to(pd["pos"])
	return h.dir_to(goal)

func _banned(m: Match, a: Dictionary, p: Vector3) -> bool:
	var bans: Dictionary = a.get("banned", {})
	return bans.has(p) and float(bans[p]) > m.time
