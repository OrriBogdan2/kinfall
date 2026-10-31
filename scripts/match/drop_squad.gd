class_name DropSquad
extends RefCounted
## How a squad comes down together, after SUPERVIVE's drop.
##
## A match on the big map opens with a short planning phase (PLAN_T seconds) while the skyship waits at
## the edge of the map: the full map is up, and everyone can ping where they want to land. Bots ping
## too. Then the ship sets off.
##
## Each squad has a drop leader (the person in it, else its first member). The leader decides when to
## jump; the rest of the squad jumps with them and glides down in formation behind the leader (their
## gliders track the leader's with a fixed offset, so they keep control of nothing but "separate").
## The leader can pass the lead to a squadmate (P, or click a name on the map). Anyone who isn't the
## leader can separate (X) to jump or steer on their own. Bots follow the leader by default and some
## break off near the ground to land a little apart.

const PLAN_T := 8.0
## Formation slots behind the leader: (to the side, behind), in metres, turned with the leader's heading.
const SLOTS := [Vector2(-2.6, 2.2), Vector2(2.6, 2.2), Vector2(0.0, 4.6), Vector2(-5.0, 4.4), Vector2(5.0, 4.4)]

var m: Match
var planning := false
var plan_t := 0.0
var plan_len := PLAN_T
var leads := {}               # team -> Hunter
var heading := {}             # team -> Vector2, the leader's smoothed heading on the drop
var _bot_ping := {}           # hunter nid -> plan time left when it pings
var _ack := []                # bot acknowledgements due {h, at, id}
var clock := 0.0              # runs through the planning phase too (the match clock waits)
var events: Array = []        # what happened, for tests

func _init(match_node: Match) -> void:
	m = match_node

## Called once everyone is aboard.
func setup() -> void:
	var teams := {}
	for h in m.hunters:
		if not teams.has(h.team): teams[h.team] = []
		teams[h.team].append(h)
	for t in teams:
		var mem: Array = teams[t]
		var lead: Hunter = mem[0]
		if m.net_on:
			# online every client must pick the same one: the first person in the squad
			for h in mem:
				if h.ctrl != "bot": lead = h; break
		elif mem.has(m.player):
			lead = m.player
		leads[t] = lead
	var o: Dictionary = m.opts
	if m.big and not m.ship.is_empty() and not o.get("no_plan", false) and not o.get("tutorial", false) and not o.get("training", false) and not o.get("duel", false):
		planning = true
		plan_len = float(o.get("plan_t", PLAN_T))
		plan_t = plan_len
		for h in m.hunters:
			if h.ctrl == "bot" and not h.remote:
				# leaders always ping their pick; the others now and then add their own
				if is_lead(h) or randf() < 0.35:
					_bot_ping[h.nid] = randf_range(1.0, maxf(1.2, plan_len - 2.0)) if is_lead(h) else randf_range(2.5, maxf(2.6, plan_len - 1.0))

func leader(team: int) -> Hunter:
	var l = leads.get(team, null)
	return l if l != null and is_instance_valid(l) else null

func is_lead(h: Hunter) -> bool:
	return h != null and leader(h.team) == h

## Still waiting aboard for the leader to jump.
func waits(h: Hunter) -> bool:
	if h.drop_solo or is_lead(h):
		return false
	var l := leader(h.team)
	return l != null and l.riding and not l.out

func mates(h: Hunter) -> Array:
	return m.hunters.filter(func(x): return x != h and x.team == h.team and not x.out and not x.extracted)

# ------------------------------------------------------------------ the planning phase
func tick_plan(dt: float) -> void:
	if not planning:
		return
	plan_t -= dt
	clock += dt
	for h in m.hunters:
		if _bot_ping.has(h.nid) and plan_t <= float(_bot_ping[h.nid]):
			_bot_ping.erase(h.nid)
			_bot_plan_ping(h)
	_tick_acks()
	if plan_t <= 0.0:
		planning = false
		plan_t = 0.0
		_depart()

## A bot's choice of where to land: the leader picks the squad's spot (its landing island, now and then
## a vault close to it); anyone else suggests somewhere near the leader's pick.
func _bot_plan_ping(h: Hunter) -> void:
	var at: Vector3 = h.ai.get("land", h.pos)
	if is_lead(h):
		var human := _human_ping(h.team)
		if human != Vector3.INF:
			at = human
		elif m.spawn_plan and randf() < 0.3:
			var bd := 60.0
			for c in m.spawn_plan.active_of("vault"):
				var d := Vector2((c["pos"] as Vector3).x - at.x, (c["pos"] as Vector3).z - at.z).length()
				if d < bd: bd = d; at = c["pos"]
	else:
		var lp := _ping_of(leader(h.team))
		if lp != Vector3.INF:
			at = m.world.free_spot_near(lp + Vector3(randf_range(-9, 9), 0, randf_range(-9, 9)), [], 1.0, 0.5, 12.0)
	m.squad_ping(h, at)
	if is_lead(h):
		_set_land(h, at)

func _depart() -> void:
	events.append("depart")
	for t in leads:
		var l := leader(int(t))
		if l == null or l.ctrl != "bot" or l.remote:
			continue
		var hp := _human_ping(l.team)
		if hp != Vector3.INF:
			_set_land(l, hp)
		m.plan_jump(l, l.ai.get("land", l.pos))
	for h in m.hunters:
		if h.ctrl == "bot" and h.drop_solo and h.riding:
			m.plan_jump(h, h.ai.get("land", h.pos))

func _set_land(h: Hunter, at: Vector3) -> void:
	h.ai["land"] = at
	h.ai.erase("retarget")
	if not planning and h.riding and h.ctrl == "bot":
		m.plan_jump(h, at)

## A squad ping someone placed: a bot leader takes a person's ping as the squad's spot; the bots answer.
func on_ping(h: Hunter, at: Vector3) -> void:
	var l := leader(h.team)
	if h.ctrl != "bot" and l and l != h and l.ctrl == "bot" and not l.remote and (l.riding or l.dropping):
		_set_land(l, at)
	if h.ctrl != "bot":
		# one squad bot says it's on the way
		var bots: Array = mates(h).filter(func(x): return x.ctrl == "bot" and not x.remote)
		if not bots.is_empty():
			_ack.append({"h": bots.pick_random(), "at": clock + randf_range(0.35, 0.9), "id": "omw"})

func _tick_acks() -> void:
	for a in _ack.duplicate():
		if clock >= float(a["at"]):
			_ack.erase(a)
			var bh: Hunter = a["h"]
			if is_instance_valid(bh) and not bh.out and m.truce:
				m.truce.emote(bh, String(a["id"]))

func _ping_of(h: Hunter) -> Vector3:
	if h == null:
		return Vector3.INF
	for p in m.pings:
		if p.get("by") == h:
			return p["pos"]
	return Vector3.INF

func _human_ping(team: int) -> Vector3:
	var best := Vector3.INF; var bt := 1e9
	for p in m.pings:
		var by = p.get("by")
		if by is Hunter and (by as Hunter).team == team and (by as Hunter).ctrl != "bot" and float(p["t"]) < bt:
			bt = float(p["t"]); best = p["pos"]
	return best

# ------------------------------------------------------------------ lead and separate
## Pass the lead to a squadmate (the next one in the squad, or the one asked for).
func pass_lead(h: Hunter, to: Hunter = null, from_net := false) -> bool:
	if not is_lead(h) or not (h.riding or h.dropping):
		return false
	# aboard: anyone still aboard; in the air: anyone gliding in your formation
	var pool: Array = m.hunters.filter(func(x): return x.team == h.team and not x.out and not x.extracted and x != h and ((h.riding and x.riding) or (h.dropping and x.dropping and x.drop_follow == h)))
	if pool.is_empty():
		if h == m.player and m.hud: m.hud.toast_small("Nobody left to pass the lead to", Color("a9b0bf"))
		return false
	if to == null or not pool.has(to):
		# the next squadmate after you, going round the squad
		var all: Array = m.hunters.filter(func(x): return x.team == h.team)
		var i0 := all.find(h)
		for k in range(1, all.size() + 1):
			var cand: Hunter = all[(i0 + k) % all.size()]
			if pool.has(cand): to = cand; break
	leads[h.team] = to
	to.drop_solo = false
	to.drop_follow = null
	for x in m.hunters:
		if x.team == h.team and x.drop_follow == h:
			x.drop_follow = to
	if h.dropping:
		h.drop_follow = to
		h.drop_slot = _free_slot(to)
	if to.dropping:
		heading[h.team] = Vector2(to.vel.x, to.vel.z).normalized() if Vector2(to.vel.x, to.vel.z).length() > 0.5 else heading.get(h.team, Vector2.UP)
	events.append("lead %s->%s" % [h.pname, to.pname])
	if m.net_on and not from_net:
		m.net_event(["lead", h.nid, to.nid])
	if m.player and m.player.team == h.team and m.hud:
		m.hud.toast_small("%s leads the drop" % ("You" if to == m.player else to.pname), Color("ffd27a"))
	if to.ctrl == "bot" and not to.remote:
		# a bot taking over flies the squad to the spot its people pinged
		var hp := _human_ping(to.team)
		if hp != Vector3.INF:
			to.ai["land"] = hp
			to.ai.erase("retarget")
		if to.riding and not planning:
			m.plan_jump(to, to.ai.get("land", to.pos))
	return true

## Break away from the squad's drop: you jump and steer on your own.
func separate(h: Hunter, from_net := false) -> bool:
	if is_lead(h) or h.drop_solo or not (h.riding or h.dropping):
		return false
	h.drop_solo = true
	h.drop_follow = null
	events.append("separate %s" % h.pname)
	if m.net_on and not from_net:
		m.net_event(["dsep", h.nid])
	if h == m.player and m.hud:
		m.hud.toast_small("You're dropping solo" + ("  ·  %s to jump" % Settings.key_cap("jump") if h.riding else ""), Color("8fd8ff"))
	if h.riding and h.ctrl == "bot" and not h.remote:
		m.plan_jump(h, h.ai.get("land", h.pos))
	return true

## The leader just jumped: everyone still following jumps with them and takes a slot behind.
func on_lead_jump(l: Hunter) -> void:
	var hd := Vector2(l.vel.x, l.vel.z)
	heading[l.team] = hd.normalized() if hd.length() > 0.1 else Vector2(m.ship.get("dir", Vector3.FORWARD).x, m.ship.get("dir", Vector3.FORWARD).z)
	var n := 0
	for f in m.hunters:
		if f == l or f.team != l.team or not f.riding or f.drop_solo or f.out or f.remote:
			continue
		m.ship_jump(f, true)
		f.drop_follow = l
		f.drop_slot = n
		n += 1
		var tg := target_of(f)
		f.teleport(Vector3(tg.x, l.pos.y, tg.y))
		f.vel = l.vel
		f.drop_from = Vector2(f.pos.x, f.pos.z)
		# some bots break off low down to land a little apart from the squad
		if f.ctrl == "bot":
			f.ai["sep_h"] = randf_range(6.0, 13.0) if randf() < 0.45 else -1.0
	events.append("jump %s +%d" % [l.pname, n])

func _free_slot(l: Hunter) -> int:
	var used := {}
	for x in m.hunters:
		if x.drop_follow == l: used[x.drop_slot] = true
	for i in SLOTS.size():
		if not used.has(i): return i
	return 0

## Where a follower's slot is right now (flat map coordinates).
func target_of(f: Hunter) -> Vector2:
	var l: Hunter = f.drop_follow
	if l == null:
		return Vector2(f.pos.x, f.pos.z)
	var fwd: Vector2 = heading.get(l.team, Vector2.UP)
	var side := Vector2(-fwd.y, fwd.x)
	var s: Vector2 = SLOTS[clampi(f.drop_slot, 0, SLOTS.size() - 1)]
	return Vector2(l.pos.x, l.pos.z) + side * s.x - fwd * s.y

## The glider's horizontal velocity for a follower: the leader's, plus whatever closes the gap to its slot.
func follow_hv(f: Hunter, gs: float) -> Vector2:
	var l: Hunter = f.drop_follow
	var err := target_of(f) - Vector2(f.pos.x, f.pos.z)
	return (Vector2(l.vel.x, l.vel.z) + err * 3.0).limit_length(gs * 1.6 + 3.0)

func follow_vy(f: Hunter) -> float:
	var l: Hunter = f.drop_follow
	return l.vel.y + clampf((l.pos.y - f.pos.y) * 2.5, -6.0, 6.0)

## Every step of the match: keep the formation's heading, let followers go once the leader is down.
func tick(dt: float) -> void:
	clock += dt
	_tick_acks()
	for t in leads:
		var l := leader(int(t))
		if l == null or not l.dropping:
			continue
		var v := Vector2(l.vel.x, l.vel.z)
		if v.length() > 1.5:
			var cur: Vector2 = heading.get(int(t), v.normalized())
			heading[int(t)] = cur.slerp(v.normalized(), 1.0 - exp(-2.5 * dt)).normalized()
	for f in m.hunters:
		if f.drop_follow == null:
			continue
		var l: Hunter = f.drop_follow
		if not f.dropping or not is_instance_valid(l) or l.out or not l.dropping or l.team != f.team:
			# the leader is down (or gone): everyone glides the last bit on their own
			if f.dropping and f.ctrl == "bot" and is_instance_valid(l):
				f.ai["land"] = _near_land(l.pos, f)
				f.ai["retarget"] = true
			f.drop_follow = null
			continue
		if f.ctrl == "bot" and not f.remote and float(f.ai.get("sep_h", -1.0)) > 0.0:
			var gy: float = m.world.ground_at(f.pos.x, f.pos.z) if not m.world.is_void(f.pos.x, f.pos.z) else -99.0
			if gy > -50.0 and f.pos.y - gy < float(f.ai["sep_h"]):
				f.ai["land"] = _near_land(f.pos, f)
				f.ai["retarget"] = true
				separate(f)

func _near_land(around: Vector3, f: Hunter) -> Vector3:
	var a := randf() * TAU
	var q := around + Vector3(cos(a), 0, sin(a)) * randf_range(5.0, 9.0)
	if m.world.is_void(q.x, q.z):
		q = around
	var p := m.world.free_spot_near(q, [], 1.0, 0.5, 10.0)
	return Vector3(p.x, m.world.ground_at(p.x, p.z), p.z) if not m.world.is_void(p.x, p.z) else f.ai.get("land", around)
