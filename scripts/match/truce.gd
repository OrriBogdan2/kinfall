class_name Truce
extends RefCounted
## Emotes, and truces between squads.
##
## Anyone can emote (hold the emote key for the wheel). A Truce emote (a white flag) offers peace to
## the nearest rival squad you can see; one of them answers within a few seconds with Accept or No.
## While a truce holds, bots of both squads leave each other (and each other's kin) alone, truce
## partners share an outpost's yard without contesting the uplink, board the same skiff, and bots
## escort their partners to whichever exit they're using. Nothing stops you shooting a partner, but
## a real attack breaks the truce for both squads, is called out in the feed, and marks the
## betrayer on everyone's map for a while. A truce ends by itself after a few minutes, or when one
## squad is gone (out or extracted).
##
## Bots offer from weak positions (a squad that's hurt, outnumbered, being third-partied, or
## carrying a haul near an exit) and accept by the same weighing; strong or aggressive bots mostly
## refuse, and now and then a strong one fakes acceptance and turns on you a little later.

const EMOTES := [
	{"id": "truce", "name": "Truce", "col": Color("f4f1e6")},
	{"id": "accept", "name": "Deal", "col": Color("8ff0a0")},
	{"id": "follow", "name": "Follow me", "col": Color("8fd8ff")},
	{"id": "thanks", "name": "Thanks!", "col": Color("ffd36a")},
	{"id": "wave", "name": "Hey!", "col": Color("ffffff")},
	{"id": "laugh", "name": "Ha ha!", "col": Color("ffb0e0")},
	{"id": "gg", "name": "GG", "col": Color("c9b6ff")},
	{"id": "refuse", "name": "No", "col": Color("ff8a7a")},
]
const OFFER_T := 6.0          # an offer stands this long
const TRUCE_T := 180.0        # a truce lasts this long
const BREAK_DMG := 14.0       # damage one side does to the other before it counts as an attack
const MARK_T := 15.0          # how long a betrayer shows on everyone's map
const SEE_R := 26.0           # bots weigh peace with squads this close that they can see
const BUBBLE_T := 2.6

var m: Match
var shown: Array = []         # emote bubbles {h, id, t}
var offers := {}              # to_team -> {from, to, by, until}
var pacts := {}               # "a:b" -> {a, b, until, dmg: {from_team: amount}}
var marked := {}              # hunter nid -> until (betrayers)
var _cool := {}               # "a:b" -> time a new offer between them is allowed
var _think := {}              # team -> next bot check
var _answers: Array = []      # bot replies due {team, at, offer}
var events: Array = []        # what happened, for tests

func _init(match_node: Match) -> void:
	m = match_node

static func _key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]

func allied(a: int, b: int) -> bool:
	return a != b and pacts.has(_key(a, b))

## Should h hold its fire at o (allied, and h isn't planning a betrayal)?
func holds(h: Hunter, o: Ent) -> bool:
	var t := o.team
	if o is Kin and (o as Kin).owner_h: t = (o as Kin).owner_h.team
	return allied(h.team, t) and not h.ai.get("betray", false)

func partners(team: int) -> Array:
	var out: Array = []
	for k in pacts:
		var p: Dictionary = pacts[k]
		if int(p["a"]) == team: out.append(int(p["b"]))
		elif int(p["b"]) == team: out.append(int(p["a"]))
	return out

func squad_name(team: int) -> String:
	for h in m.hunters:
		if h.team == team:
			return "%s's squad" % h.pname
	return "a squad"

func _members(team: int) -> Array:
	return m.hunters.filter(func(x): return x.team == team and not x.out and not x.extracted)

func _mine(team: int) -> bool:
	return m.player != null and m.player.team == team

# ------------------------------------------------------------------ emotes
func emote(h: Hunter, id: String, from_net := false) -> void:
	if h == null or h.out or h.extracted:
		return
	for s in shown.duplicate():
		if s["h"] == h: shown.erase(s)
	shown.append({"h": h, "id": id, "t": 0.0})
	m.sfx("click" if id != "truce" else "ping", h.pos, -6.0, 1.2 if id != "refuse" else 0.8)
	if m.net_on and not from_net:
		m.net_event(["emo", h.nid, id])
	match id:
		"truce": _offer(h)
		"accept": _answer(h, true)
		"refuse": _answer(h, false)
		"follow":
			# bots on your squad, and your truce partners', tag along for a while
			for b in m.hunters:
				if b != h and b.ctrl == "bot" and (b.team == h.team or allied(b.team, h.team)) and b.flat_dist(h) < 30.0:
					b.ai["follow"] = {"h": h, "until": m.time + 25.0}

static func emote_def(id: String) -> Dictionary:
	for e in EMOTES:
		if e["id"] == id: return e
	return EMOTES[0]

## The rival squad a truce offer from h goes to: the nearest one h can see.
func _offer_target(h: Hunter) -> int:
	var best := -1; var bd := 30.0
	for o in m.hunters:
		if o.team == h.team or o.out or o.extracted or o.riding or o.dropping:
			continue
		var d := h.flat_dist(o)
		if d < bd and m.can_see(h.team, o):
			bd = d; best = o.team
	return best

func _offer(h: Hunter) -> void:
	var to := _offer_target(h)
	if to < 0:
		if h == m.player and m.hud: m.hud.toast_small("Nobody in sight to offer a truce to", Color("f4f1e6"))
		return
	if allied(h.team, to):
		return
	offers[to] = {"from": h.team, "to": to, "by": h, "until": m.time + OFFER_T}
	_cool["%d>%d" % [h.team, to]] = m.time + 25.0
	events.append("offer %d->%d" % [h.team, to])
	if _mine(to) and m.hud and not m.player.out:
		m.hud.toast("%s offers a truce! Hold %s and pick Deal to accept" % [h.pname, Settings.key_cap("emote")], Color("f4f1e6"))
	elif _mine(h.team) and m.hud:
		m.hud.toast_small("Truce offered to %s" % squad_name(to), Color("f4f1e6"))
	# a bot squad answers in a moment (one with a living player in it waits for the player)
	if _bot_team(to) and (not m.net_on or m.is_host):
		_answers.append({"team": to, "at": m.time + randf_range(1.0, 3.0), "from": h.team})

func _bot_team(team: int) -> bool:
	for x in _members(team):
		if x.ctrl != "bot" or x.remote:
			return false     # a squad with a person in it answers for itself
	return not _members(team).is_empty()

func _answer(h: Hunter, yes: bool) -> void:
	var o: Dictionary = offers.get(h.team, {})
	if o.is_empty() or m.time > float(o["until"]):
		return
	offers.erase(h.team)
	if yes:
		make(int(o["from"]), h.team)
	else:
		events.append("refused %d->%d" % [int(o["from"]), h.team])
		if _mine(int(o["from"])) and m.hud:
			m.hud.toast_small("%s turned down the truce" % squad_name(h.team), Color("ff8a7a"))

## A truce between two squads starts now.
func make(a: int, b: int) -> void:
	pacts[_key(a, b)] = {"a": a, "b": b, "until": m.time + TRUCE_T, "dmg": {}}
	events.append("truce %d:%d" % [mini(a, b), maxi(a, b)])
	for h in m.hunters:
		if h.team == a or h.team == b:
			h.ai.erase("betray")
			if h.ai.get("tgt") is Ent and allied(h.team, (h.ai["tgt"] as Ent).team): h.ai["tgt"] = null
	m.add_feed("%s and %s made a truce" % [squad_name(a), squad_name(b)])
	m.sfx("unlock", null, -8.0, 1.1)
	if m.player and (_mine(a) or _mine(b)) and m.hud:
		m.hud.toast("Truce with %s: don't shoot each other, and you can share a way out" % squad_name(b if _mine(a) else a), Color("f4f1e6"))

func end(k: String, why: String) -> void:
	var p: Dictionary = pacts.get(k, {})
	if p.is_empty():
		return
	pacts.erase(k)
	events.append("ended %s %s" % [k, why])
	if why != "":
		m.add_feed(why)

# ------------------------------------------------------------------ breaking it
## Every hit in the match comes through here (Match.on_damage). A real attack on a truce partner
## (more than a stray splash) breaks the truce and marks whoever did it.
func on_damage(target: Ent, by: Ent, d: float) -> void:
	if pacts.is_empty() or by == null or d <= 0.0:
		return
	var credit: Ent = by
	if by is Kin and (by as Kin).owner_h: credit = (by as Kin).owner_h
	if not (credit is Hunter):
		return
	var tt := target.team
	if target is Kin and (target as Kin).owner_h: tt = (target as Kin).owner_h.team
	if not allied(credit.team, tt):
		return
	var k := _key(credit.team, tt)
	var dm: Dictionary = pacts[k]["dmg"]
	dm[credit.team] = float(dm.get(credit.team, 0.0)) + d * (0.5 if by is Kin else 1.0)
	if float(dm[credit.team]) < BREAK_DMG:
		return
	var traitor: Hunter = credit
	marked[traitor.nid] = m.time + MARK_T
	traitor.reveal_t = maxf(traitor.reveal_t, MARK_T)
	end(k, "%s broke the truce!" % traitor.pname)
	m.sfx("warn", null, -4.0, 1.2)
	# the betrayed bots turn on them right away
	for h in _members(tt):
		if h.ctrl == "bot":
			h.ai["tgt"] = traitor
			h.last_hit_by = traitor
	if m.hud and m.player and not m.player.out:
		m.hud.toast("%s broke the truce!" % traitor.pname, Color("ff6a5a"))

func is_marked(h: Hunter) -> bool:
	return float(marked.get(h.nid, -1.0)) > m.time

# ------------------------------------------------------------------ the clock
func tick(dt: float) -> void:
	for s in shown.duplicate():
		s["t"] = float(s["t"]) + dt
		if float(s["t"]) > BUBBLE_T: shown.erase(s)
	for t in offers.keys():
		if m.time > float(offers[t]["until"]): offers.erase(t)
	for k in pacts.keys():
		var p: Dictionary = pacts[k]
		var a := int(p["a"]); var b := int(p["b"])
		if m.time > float(p["until"]):
			end(k, "The truce between %s and %s ran out" % [squad_name(a), squad_name(b)])
		elif _members(a).is_empty() or _members(b).is_empty():
			end(k, "")
	for nid in marked.keys():
		if float(marked[nid]) < m.time: marked.erase(nid)
	if m.net_on and not m.is_host:
		return
	for an in _answers.duplicate():
		if m.time >= float(an["at"]):
			_answers.erase(an)
			_bot_reply(int(an["team"]), int(an["from"]))
	_bot_offers()
	_bot_betrayals()

# ------------------------------------------------------------------ bots
## How strong a squad looks right now: living members, their health and armor, armor tiers.
func strength(team: int) -> float:
	var s := 0.0
	for h in _members(team):
		if h.downed:
			s += 0.3
			continue
		s += 1.0 + 1.5 * (h.hp + h.armor) / maxf(1.0, h.max_hp + h.max_armor) + 0.2 * h.armor_tier
		if h.kin and not h.kin.dead and (h.kin as Kin).state != "fainted": s += 0.3
	return s

## The other squads close by that this squad can see.
func _near_squads(team: int) -> Dictionary:
	var out := {}
	for me in _members(team):
		if me.dropping or me.riding: continue
		for o in m.hunters:
			if o.team == team or o.out or o.extracted or o.riding or o.dropping:
				continue
			var d: float = me.flat_dist(o)
			if d < SEE_R and m.can_see(team, o):
				out[o.team] = minf(float(out.get(o.team, 1e9)), d)
	return out

## Reasons a squad would rather not fight this one: weaker, third-partied, a haul near an exit,
## hanging over the abyss. Positive means peace looks good.
func _peace_score(team: int, other: int, near: Dictionary) -> float:
	var mine := strength(team); var theirs := maxf(0.5, strength(other))
	var sc := (1.0 - mine / theirs) * 1.2
	var hostile := 0
	for t in near:
		if t != other and not allied(team, int(t)): hostile += 1
	if hostile > 0: sc += 0.35
	var gems := 0; var near_exit := false; var danger := false
	for h in _members(team):
		gems += h.gems
		if m.exits:
			for ep in m.exits.spots():
				if h.flat_dist(ep) < 35.0: near_exit = true
		if h.over_void() or h.below_lip: danger = true
	if gems > 60 and near_exit: sc += 0.25
	if danger: sc += 0.2
	# personality and difficulty: easier bots are more peaceable, hard ones more stubborn
	var lead: Hunter = null
	for h in _members(team):
		if h.ctrl == "bot": lead = h; break
	if lead:
		if not lead.ai.has("peace"): lead.ai["peace"] = randf_range(-0.25, 0.25)
		sc += float(lead.ai["peace"])
		sc -= (float((lead.ai.get("diff", {}) as Dictionary).get("aggro", 0.8)) - 0.8) * 1.2
	return sc

func _bot_offers() -> void:
	var teams := {}
	for h in m.hunters:
		if h.ctrl == "bot" and not h.out and not h.extracted: teams[h.team] = true
	for team in teams:
		if not _bot_team(team) or m.time < float(_think.get(team, 0.0)):
			continue
		_think[team] = m.time + randf_range(1.5, 2.5)
		var near := _near_squads(team)
		for other in near:
			var o := int(other)
			if allied(team, o) or offers.has(o) or offers.has(team) or m.time < float(_cool.get("%d>%d" % [team, o], 0.0)):
				continue
			var p := clampf(_peace_score(team, o, near), 0.0, 0.85)
			if randf() < p * 0.5:
				# the member closest to them waves the flag
				var by: Hunter = null; var bd := 1e9
				for h in _members(team):
					if h.downed or h.ctrl != "bot": continue
					for x in _members(o):
						if h.flat_dist(x) < bd: bd = h.flat_dist(x); by = h
				if by:
					emote(by, "truce")
				break

func _bot_reply(team: int, from: int) -> void:
	var o: Dictionary = offers.get(team, {})
	if o.is_empty() or int(o["from"]) != from:
		return
	var who: Hunter = null
	for h in _members(team):
		if not h.downed: who = h; break
	if who == null:
		return
	var near := _near_squads(team)
	if not near.has(from): near[from] = 10.0
	var acc := clampf(0.3 + _peace_score(team, from, near), 0.03, 0.95)
	var ratio := strength(team) / maxf(0.5, strength(from))
	var hard: bool = float((who.ai.get("diff", {}) as Dictionary).get("aggro", 0.8)) >= 0.95
	# a much stronger squad sometimes pretends, then turns on them
	if ratio > 1.3 and randf() < (0.18 if hard else 0.08):
		emote(who, "accept")
		for h in _members(team):
			h.ai["betray_at"] = m.time + randf_range(5.0, 12.0)
		events.append("fake %d" % team)
		return
	emote(who, "accept" if randf() < acc else "refuse")

func _bot_betrayals() -> void:
	for h in m.hunters:
		if h.ctrl != "bot" or not h.ai.has("betray_at"):
			continue
		if m.time >= float(h.ai["betray_at"]):
			h.ai.erase("betray_at")
			if not partners(h.team).is_empty():
				h.ai["betray"] = true

## Bot helper: should this bot (any bot on a squad with a player who offers) say yes to a pending
## offer by the same weighing? Used by tests; bots answer through _bot_reply on their own.
func would_accept(team: int, from: int) -> float:
	var near := _near_squads(team)
	if not near.has(from): near[from] = 10.0
	return clampf(0.3 + _peace_score(team, from, near), 0.03, 0.95)

# ------------------------------------------------------------------ for the HUD
## A truce partner close to where the player is aiming (to warn before shooting them).
func partner_at(p: Vector3, team: int) -> Hunter:
	for h in m.hunters:
		if h.team != team and not h.out and not h.extracted and allied(team, h.team) and Vector2(h.pos.x - p.x, h.pos.z - p.z).length() < 1.3:
			return h
	return null
