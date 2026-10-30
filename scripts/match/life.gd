class_name Life
## Down, death, revive and respawn, on Supervive's rules tuned for extraction
## (docs/DEATH_AND_REVIVE.md):
##   ALIVE --0 HP--> DOWNED (wisp) --bleeds out / executed / team wiped--> DEAD (deathbox)
##   a teammate standing on your wisp brings you back (4s); a teammate holding interact at your
##   deathbox does too while your soul is there (5s, loot back); a revive beacon brings back the
##   whole team (6s, full health, no loot, resurrection sickness).
## Everything here runs on whichever game owns the hunter (local and bots); remote hunters only
## show what their owner sends.

const R := {
	"bleed_out": 15.0,          # [patch] seconds a wisp lasts on its own
	"revive_radius": 1.6,       # [est] a teammate this close revives you
	"revive_time": 4.0,         # [wiki "a few seconds"] [est]
	"revive_hp": 0.33,          # [est]
	"extra_reviver": 0.5,       # each extra teammate on you: +50% speed [design]
	"stomp_mult": 4.0,          # [wiki] an enemy on a wisp drains it this much faster and blocks the revive
	"execute_time": 3.0,        # [footage] hold interact on an enemy wisp
	"kin_revive_time": 8.0,     # [design] your kin pulling you up (as long as Supervive's Guardian Angel self-revive)
	"box_revive_time": 5.0,     # [est] teammate holds interact at your deathbox
	"box_revive_hp": 0.5,       # [design]
	"soul_time": 90.0,          # [design] box revive window
	"loot_time": 1.0,           # [design] hold interact to take everything from a box
	"beacon_time": 6.0,         # [patch 1.0]
	"beacon_radius": 2.2,
	"beacon_count": 6,
	"sickness_time": 12.0,      # [patch 1.0] resurrection sickness
	"sickness_dmg": 0.75,       # [patch 1.0] -25% damage dealt
}

## Box colour by what's inside: grey, blue, purple, gold.
const BOX_TIERS := [[0, Color("b8b4ac")], [12, Color("6ab8ff")], [35, Color("c08aff")], [80, Color("ffb64a")]]

static func trace(m: Match, txt: String) -> void:
	if m.opts.get("autoplay", false):
		print("LIFE %d %s" % [int(m.time), txt])

static func box_value(b: Dictionary) -> int:
	var v := int(b["gems"])
	for s in b["seeds"]: v += int(b["seeds"][s]) * 3
	v += (b["caught"] as Array).size() * 15
	v += int(b["tonics"]) * 4 + int(b["kits"]) * 4
	return v

static func box_color(b: Dictionary) -> Color:
	var col: Color = BOX_TIERS[0][1]
	for t in BOX_TIERS:
		if box_value(b) >= int(t[0]): col = t[1]
	return col

## Is anyone on this team still in the fight (standing or a wisp)?
static func team_alive(m: Match, team: int) -> bool:
	return m.hunters.any(func(x): return x.team == team and not x.out and not x.extracted)

static func team_standing(m: Match, team: int) -> bool:
	return m.hunters.any(func(x): return x.team == team and not x.out and not x.extracted and not x.downed)

# ------------------------------------------------------------------ wisps
## Every frame, for each wisp: teammates on it revive it, enemies on it stomp it, otherwise it
## bleeds out.
static func tick_wisps(m: Match, dt: float) -> void:
	var base := Data.MATCH["down_hp"] / R["bleed_out"]
	for o in m.hunters:
		if not o.downed or o.out or o.remote:
			continue
		var allies := 0
		var foes := 0
		for h in m.hunters:
			if h == o or h.out or h.extracted or h.downed or h.dropping or h.flat_dist(o) > R["revive_radius"] or absf(h.pos.y - o.pos.y) > 1.6:
				continue
			if h.team == o.team: allies += 1
			else: foes += 1
		var kin_on := false
		for kk in [o.kin, o.kin2]:
			if kk and not (kk as Kin).dead and (kk as Kin).state == "reviving" and (kk as Kin).flat_dist(o) < 1.4:
				kin_on = true
		o.set_meta("stomped", foes > 0)
		if foes > 0:
			# stomped: drains fast and nobody can pick you up
			o.down_hp -= base * R["stomp_mult"] * dt
			o.revive = maxf(0.0, o.revive - dt * 0.5)
		elif allies > 0:
			o.revive += dt / R["revive_time"] * (1.0 + R["extra_reviver"] * (allies - 1))
			if o.revive >= 1.0:
				trace(m, "wisp revive %s" % o.pname)
				m.revive_hunter(o, null)
				continue
		elif not kin_on:
			o.down_hp -= base * dt
		if o.down_hp <= 0.0:
			trace(m, "%s %s" % [o.pname, "bled out" if foes == 0 else "stomped out"])
			m.eliminate(o, o.last_hit_by, "bled out" if foes == 0 else "finished")

# ------------------------------------------------------------------ deathboxes
## Where a box goes: where you fell, or the last solid ground before the abyss.
static func box_spot(m: Match, h: Hunter, why: String) -> Vector3:
	var at := h.pos
	if why == "abyss" or m.world.is_void(at.x, at.z) or at.y < m.world.ground_at(at.x, at.z) - 1.0:
		at = h.safe_pos if h.safe_pos != Vector3.INF else at
		if m.world.is_void(at.x, at.z):
			at = m.world.free_spot_near(at, [], 1.0, 0.4, 40.0)
	if m.world.is_void(at.x, at.z):
		return Vector3.INF
	at.y = m.world.ground_at(at.x, at.z)
	return at

static func drop_box(m: Match, h: Hunter, why: String) -> Dictionary:
	for old in m.boxes:
		if old["owner"] == h: old["soul_until"] = 0.0
	var at := box_spot(m, h, why)
	var b := {"owner": h, "team": h.team, "pos": at, "gems": h.gems, "seeds": h.seeds.duplicate(), "caught": h.caught.duplicate(true),
		"tonics": maxi(0, h.tonics - h.free_tonics), "kits": h.armor_kits, "soul_until": m.time + R["soul_time"], "prog": {}, "node": null, "empty": false}
	h.tonics = mini(h.tonics, h.free_tonics)
	h.armor_kits = 0
	if at == Vector3.INF:
		# nowhere to put it: the abyss keeps it
		return b
	trace(m, "box %s value %d at %s" % [h.pname, box_value(b), at.snapped(Vector3.ONE)])
	var n := Models.deathbox(box_color(b))
	n.position = at
	m.add_child(n)
	b["node"] = n
	m.boxes.append(b)
	return b

## Your latest box (an earlier one from before a revive can't bring you back any more).
static func box_of(m: Match, h: Hunter) -> Dictionary:
	for i in range(m.boxes.size() - 1, -1, -1):
		if m.boxes[i]["owner"] == h:
			return m.boxes[i]
	return {}

static func soul_here(m: Match, b: Dictionary) -> bool:
	var o: Hunter = b["owner"]
	return o != null and o.out and not o.gone and m.time < float(b["soul_until"])

## Takes everything in a box.
static func loot_box(m: Match, h: Hunter, b: Dictionary) -> void:
	h.gems += int(b["gems"])
	for s in b["seeds"]:
		h.seeds[s] = int(h.seeds.get(s, 0)) + int(b["seeds"][s])
	for rec in b["caught"]:
		h.caught.append(rec)
	h.tonics += int(b["tonics"])
	h.armor_kits += int(b["kits"])
	_kin_from_box(m, h, b)
	var got := int(b["gems"])
	b["gems"] = 0; b["seeds"] = {}; b["caught"] = []; b["tonics"] = 0; b["kits"] = 0
	b["empty"] = true
	_refresh_box(b)
	m.sfx("pickup", b["pos"], -2.0, 0.9)
	m.fx.burst(b["pos"] + Vector3(0, 0.6, 0), Color("ffd36a"), 14, 3.0, 0.4)
	if h == m.player and m.hud:
		m.hud.toast_small("Looted %s's box%s" % [(b["owner"] as Hunter).pname if b["owner"] != h else "your own", ("  +%d gems" % got) if got > 0 else ""], Color("ffd36a"))

static func _refresh_box(b: Dictionary) -> void:
	var n: Node3D = b["node"]
	if n == null:
		return
	var lid: Node3D = n.get_node_or_null("Body/Lid")
	if lid and b["empty"]:
		lid.rotation.x = -1.1
	var glow: Node3D = n.get_node_or_null("Glow")
	if glow: glow.visible = not b["empty"]

## A teammate brought you back at your box: half health, and whatever's still in it.
static func box_revive(m: Match, b: Dictionary, by: Hunter) -> void:
	var o: Hunter = b["owner"]
	bring_back(m, o, b["pos"], R["box_revive_hp"], false)
	loot_box(m, o, b)
	m.add_feed("%s brought %s back at their box" % [by.pname, o.pname])
	trace(m, "box revive %s by %s" % [o.pname, by.pname])

# ------------------------------------------------------------------ coming back
## Back from the dead (or a wisp) at a spot, with some health.
static func bring_back(m: Match, o: Hunter, at: Vector3, hp_frac: float, sick: bool) -> void:
	o.out = false
	o.gone = false
	o.downed = false
	o.down_hp = 0.0
	o.revive = 0.0
	o.hp = o.max_hp * hp_frac
	o.armor = 0.0
	o.inv_t = 1.5
	o.vel = Vector3.ZERO
	o.stun_t = 0.0
	o.grap = {}; o.pad = {}; o.charge = {}; o.roll_t = 0.0
	o.gliding = false; o.glide_fuel = 1.0
	o.sick_t = R["sickness_time"] if sick else 0.0
	o.teleport(m.world.free_spot_near(at, [], 1.0, 0.4, 6.0) if not m.world.is_void(at.x, at.z) else at)
	o.prev = o.pos
	for w in m.kins.duplicate():
		# a loose kin of yours nobody captured comes running back
		if w.is_wild() and not w.dead and w.lost_owner == o:
			w.dead = true; w.visible = false
			m.give_kin(o, w.rec)
	for kk in [o.kin, o.kin2]:
		# your kin was keeping out of sight; it comes straight back to you
		if kk and not (kk as Kin).dead and (kk as Kin).state == "away":
			var k: Kin = kk
			k.teleport(o.pos + Vector3(0, 1.5, 0))
			k.state = "bench" if k == o.kin2 else "shoulder"
			if k == o.kin: k._hop_on()
	if o.ctrl == "bot":
		o.ai = m.bot_brain.new_mind(m.rng, float(m.opts.get("bot_skill", 0.6)))
	m.sfx("revive", o.pos, 0.0)
	m.fx.ring(o.pos, 2.2, Color("9ee2a0"), 0.5)
	m.fx.burst(o.pos + Vector3(0, 1.0, 0), Color("cff6e0"), 26, 5.0, 0.6, -2.0)
	if o == m.player:
		m.killcam_text = ""
		if m.hud:
			m.hud.flash(Color("9ee2a0"), 0.3)
			m.hud.toast("You're back" + ("  ·  resurrection sickness: -25% damage for 12s" if sick else ""), Color("9ee2a0"))

## Someone died for good: no box revive any more, and no beacon either.
static func make_gone(m: Match, h: Hunter) -> void:
	if h.gone:
		return
	h.gone = true
	# kin that were keeping out of sight flee home: they're never lost that way

# ------------------------------------------------------------------ kin at risk (by run tier)
## When you die, what happens to your kin depends on the tier you're in (docs/DEATH_AND_REVIVE.md):
## the Meadow keeps them safe; in the Dusk Isles the kin you have on you (shoulder or bench) drop
## into your deathbox where anyone can loot them; in the Hollow kin out of your hands (thrown,
## fighting) can also be captured. Safe kin keep out of sight and come back if you're revived.
static func kin_on_death(m: Match, h: Hunter, b: Dictionary) -> void:
	var training: bool = m.opts.get("training", false) or m.opts.get("tutorial", false)
	b["kin"] = []
	for kk in [h.kin, h.kin2]:
		if kk == null or (kk as Kin).dead:
			continue
		var k: Kin = kk
		m.giant_free(k)
		var on_you: bool = k.state in ["shoulder", "bench", "away"]
		if not training and on_you and bool(m.T.get("kin_drop", false)) and b.get("node") != null:
			var rec: Dictionary = k.rec.duplicate(true)
			(b["kin"] as Array).append(rec)
			k.dead = true; k.visible = false
			if h == m.player:
				m.player_lost.append({"uid": String(rec.get("uid", "")), "kin": null, "box": b, "holder": null, "rec": rec})
				m.add_feed("%s dropped into your deathbox" % rec.get("name", "Your kin"))
			continue
		if not training and not on_you and bool(m.T.get("loose_capture", false)):
			# loose in the world: dazed, and anyone can capture it
			m._leave_one_kin(h, k)
			continue
		k.state = "away"
	if not (b["kin"] as Array).is_empty():
		b["empty"] = false
		_refresh_box(b)
		trace(m, "%d kin into %s's box" % [(b["kin"] as Array).size(), h.pname])

## Kin coming out of a box: back to their owner's side, to a teammate to carry home, or off with
## whoever looted it.
static func _kin_from_box(m: Match, h: Hunter, b: Dictionary) -> void:
	var o: Hunter = b["owner"]
	for rec in b.get("kin", []):
		if h == o:
			m.give_kin(h, rec)
			if h == m.player: m.add_feed("%s is back with you" % rec.get("name", "Your kin"))
			continue
		var r2: Dictionary = (rec as Dictionary).duplicate(true)
		if o == m.player:
			r2["lost_from"] = "you"
			for L in m.player_lost:
				if String(L["uid"]) == String(rec.get("uid", "")): L["holder"] = h
			m.add_feed(("%s is carrying %s for you" if h.team == o.team else "%s took %s from your box!") % [h.pname, rec.get("name", "your kin")])
		elif h.team != o.team:
			# a rival's kin: it's yours if you get it home
			r2["trust"] = 20.0
			r2["memory"] = []
			if h == m.player: m.add_feed("You took %s's %s! Extract to keep it." % [o.pname, Data.KIN[r2["species"]]["name"]])
		h.caught.append(r2)
	b["kin"] = []

# ------------------------------------------------------------------ beacons
static func place_beacons(m: Match) -> void:
	if m.opts.get("training", false) or m.opts.get("tutorial", false):
		return
	var isl: Array = []
	for i in m.world.islands.size():
		isl.append(i)
	isl.sort_custom(func(a, b): return float(m.world.islands[a]["r"]) > float(m.world.islands[b]["r"]))
	var spots: Array = []
	for i in isl:
		if spots.size() >= int(R["beacon_count"]):
			break
		for tries in 12:
			var p: Vector3 = m.world.random_ground(i)
			if p == Vector3.INF or m.world.is_void(p.x, p.z):
				continue
			var ok := true
			for s in spots:
				if Vector2(s.x - p.x, s.z - p.z).length() < 30.0: ok = false
			for pt in m.portals:
				if Vector2(pt["pos"].x - p.x, pt["pos"].z - p.z).length() < 6.0: ok = false
			if ok:
				spots.append(p)
				break
	for p in spots:
		var n := Models.revive_beacon()
		n.position = p
		m.add_child(n)
		m.beacons.append({"pos": p, "used": false, "prog": 0.0, "team": -1, "node": n, "contested": false})

## Who a beacon would bring back for this team: every dead or downed teammate still waiting.
static func beacon_targets(m: Match, team: int) -> Array:
	return m.hunters.filter(func(x): return x.team == team and not x.remote and not x.extracted and ((x.out and not x.gone) or x.downed))

static func tick_beacons(m: Match, dt: float) -> void:
	for bc in m.beacons:
		if bc["used"]:
			continue
		var teams := {}
		for h in m.hunters:
			if h.out or h.extracted or h.downed or h.dropping:
				continue
			if h.flat_dist(bc["pos"]) < R["beacon_radius"] and absf(h.pos.y - float(bc["pos"].y)) < 1.8:
				teams[h.team] = true
		bc["contested"] = teams.size() > 1
		if teams.size() == 1:
			var t: int = teams.keys()[0]
			if beacon_targets(m, t).is_empty():
				continue
			if int(bc["team"]) != t:
				# a different team stepping on starts from scratch
				bc["team"] = t
				bc["prog"] = 0.0
			bc["prog"] = float(bc["prog"]) + dt / R["beacon_time"]
			if float(bc["prog"]) >= 1.0:
				_use_beacon(m, bc, t)
		elif teams.is_empty():
			bc["prog"] = maxf(0.0, float(bc["prog"]) - dt * 0.25)

static func _use_beacon(m: Match, bc: Dictionary, team: int) -> void:
	bc["used"] = true
	var names: Array = []
	var i := 0
	for o in beacon_targets(m, team):
		var at: Vector3 = bc["pos"] + Vector3(cos(i * 2.1) * 1.2, 0, sin(i * 2.1) * 1.2)
		bring_back(m, o, at, 1.0, true)
		o.gems = 0; o.seeds = {}; o.caught = []     # you come back empty-handed: your box is where you left it
		names.append(o.pname)
		i += 1
	var n: Node3D = bc["node"]
	var glow: Node3D = n.get_node_or_null("Glow")
	if glow: glow.visible = false
	m.fx.ring(bc["pos"], 4.0, Color("8fffc0"), 0.6)
	m.sfx("unlock", bc["pos"], 0.0, 0.8)
	m.shake(0.3, bc["pos"])
	# everyone on the map hears a beacon go off
	m.ping(bc["pos"], Color("8fffc0"))
	m.add_feed("A revive beacon brought back %s" % ", ".join(names))
	trace(m, "beacon team %d brought back %s" % [team, ", ".join(names)])
	if m.player and m.player.team != team and m.hud:
		m.hud.toast_small("A revive beacon went off " + m.direction_word(m.player.pos, bc["pos"]), Color("8fffc0"))
