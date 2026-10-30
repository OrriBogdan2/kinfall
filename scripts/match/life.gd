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
	"revive_hp": 0.25,          # [design] back on your feet with a quarter of your health
	"extra_reviver": 0.5,       # each extra teammate on you: +50% speed [design]
	"stomp_mult": 2.5,          # [design] an enemy standing on a wisp drains it this much faster and blocks the revive
	"stomp_slow": 0.4,          # [design] ...and pins it: the wisp drifts at this fraction of its normal speed
	"execute_time": 3.0,        # [footage] (old: hold interact on an enemy wisp; now the stomp below)
	"stomp_commit": 0.2,        # [design] hold interact this long on an enemy wisp to start the stomp...
	"stomp_time": 2.4,          # [footage] ...then you're locked in for this long, three stomps and done
	"stomp_cycle": 0.7,         # one foot-lift-and-slam
	"kin_revive_time": 8.0,     # [design] your kin pulling you up (as long as Supervive's Guardian Angel self-revive)
	"box_revive_time": 5.0,     # [est] teammate holds interact at your deathbox
	"box_revive_hp": 0.25,      # [design] same as a wisp revive
	"soul_time": 90.0,          # [design] box revive window
	"loot_time": 1.0,           # [design] bots: hold interact to take everything from a box (you get a loot window)
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
		var revivers: Array = []
		var stompers: Array = []
		for h in m.hunters:
			if h == o or h.out or h.extracted or h.downed or h.dropping or h.flat_dist(o) > R["revive_radius"] or absf(h.pos.y - o.pos.y) > 1.6:
				continue
			if h.team == o.team:
				allies += 1
				revivers.append(h)
			else:
				foes += 1
				stompers.append(h)
				h.set_meta("standing_on", o)
				h.set_meta("standing_at", m.time)
		o.set_meta("revivers", revivers if foes == 0 else [])
		o.set_meta("stompers", stompers)
		# the crush: a low thud under the wisp while someone's standing on it, heard by both sides
		if foes > 0:
			var st: float = float(o.get_meta("crush_t", 0.0)) - dt
			if st <= 0.0:
				st = 0.42
				m.sfx("thump", o.pos, -6.0)
			o.set_meta("crush_t", st)
		var kin_on := false
		for kk in [o.kin, o.kin2]:
			if kk and not (kk as Kin).dead and (kk as Kin).state == "reviving" and (kk as Kin).flat_dist(o) < 1.4:
				kin_on = true
		if foes > 0 and not o.get_meta("stomped", false) and o == m.player and m.hud:
			m.hud.toast("%s is on you! Drift away" % stompers[0].pname, Color("ff5a4a"))
		o.set_meta("stomped", foes > 0)
		if foes > 0:
			# stomped: drains fast and nobody can pick you up
			o.down_hp -= base * R["stomp_mult"] * dt
			o.revive = maxf(0.0, o.revive - dt * 0.5)
		elif allies > 0:
			o.revive += dt / R["revive_time"] * (1.0 + R["extra_reviver"] * (allies - 1))
			if o.revive >= 1.0:
				trace(m, "wisp revive %s" % o.pname)
				for rv in revivers: (rv as Hunter).revives += 1
				m.revive_hunter(o, null)
				continue
		elif not kin_on:
			o.down_hp -= base * dt
		if o.down_hp <= 0.0:
			trace(m, "%s %s" % [o.pname, "bled out" if foes == 0 else "stomped out"])
			m.eliminate(o, o.last_hit_by, "bled out" if foes == 0 else "finished")

# ------------------------------------------------------------------ the stomp
## Holding interact on an enemy wisp commits you to stomping it out: a fixed animation you can't
## cancel or move out of. You can still be shot, and a stun or a knockback breaks it (the wisp
## lives), and if the wisp drifts away (off a ledge, say) your stomps miss and it gets away.
static func start_stomp(m: Match, h: Hunter, o: Hunter) -> void:
	h.stomp = {"o": o, "t": 0.0, "hits": 0}
	h.finish_t = 0.0
	trace(m, "stomp start %s on %s" % [h.pname, o.pname])
	m.fx.word(h.pos + Vector3(0, 2.3, 0), "STOMP", Color("ff8a6a"), false)
	if o == m.player and m.hud:
		m.hud.toast("%s is stomping you! Drift away or get help" % h.pname, Color("ff6a5a"))

static func end_stomp(m: Match, h: Hunter, why: String) -> void:
	if h.stomp.is_empty():
		return
	trace(m, "stomp end %s (%s)" % [h.pname, why])
	h.stomp = {}
	if why == "broken":
		m.fx.word(h.pos + Vector3(0, 2.3, 0), "INTERRUPTED", Color("cfeaff"), false)
		m.sfx("whoosh", h.pos, -6.0, 1.3)

static func tick_stomps(m: Match, dt: float) -> void:
	for h in m.hunters:
		if h.stomp.is_empty() or h.remote:
			continue
		var o: Hunter = h.stomp["o"]
		# a hit that stuns or knocks you breaks it; your own input never does
		if h.downed or h.out or h.stun_t > 0.0 or m.time - h.kb_t < 0.08:
			end_stomp(m, h, "broken")
			continue
		if o == null or o.out or not o.downed:
			end_stomp(m, h, "gone")
			continue
		h.root_t = maxf(h.root_t, 0.12)
		var face := Vector2(o.pos.x - h.pos.x, o.pos.z - h.pos.z)
		if face.length() > 0.05: h.inp["aim"] = Vector3(o.pos.x, o.pos.y, o.pos.z)
		var t0 := float(h.stomp["t"])
		var t1 := t0 + dt
		h.stomp["t"] = t1
		var cyc: float = R["stomp_cycle"]
		var hit_at := cyc * 0.7
		var near: bool = h.flat_dist(o) <= float(R["revive_radius"]) + 0.5 and absf(h.pos.y - o.pos.y) < 1.6
		if fmod(t0, cyc) < hit_at and fmod(t1, cyc) >= hit_at:
			# a foot comes down
			h.stomp["hits"] = int(h.stomp["hits"]) + 1
			m.fx.dust(h.pos, 10)
			m.fx.ring(h.pos + Vector3(0, 0.05, 0), 1.2, Color(1, 0.8, 0.7, 0.6), 0.25)
			m.sfx("thump", h.pos, -2.0, 0.85)
			if near:
				m.fx.burst(o.pos + Vector3(0, 0.5, 0), Color("ff6a5a"), 10, 3.0, 0.35, -4.0)
				o.down_hp -= Data.MATCH["down_hp"] * 0.12
			if h.is_local() or o == m.player:
				m.shake(0.12, h.pos)
		if t1 >= float(R["stomp_time"]):
			if near:
				end_stomp(m, h, "done")
				m.eliminate(o, h, "executed")
				m.fx.burst(o.pos + Vector3(0, 0.8, 0), Color("ff6a5a"), 20, 4.0, 0.5, -3.0)
				m.sfx("crit", o.pos, -2.0, 0.7)
			else:
				end_stomp(m, h, "missed")

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
		"tonics": maxi(0, h.tonics - h.free_tonics), "kits": h.armor_kits, "soul_until": m.time + R["soul_time"], "prog": {}, "node": null, "empty": false,
		"gear": [], "weapon": {}}
	h.tonics = mini(h.tonics, h.free_tonics)
	h.armor_kits = 0
	# your gloves and any weapon you found go in the box too (Supervive: the box holds everything)
	for g in h.gear:
		if not (g as Dictionary).is_empty():
			(b["gear"] as Array).append((g as Dictionary).duplicate())
	h.gear = [{}, {}]
	if h.has_method("refresh_gear"): h.refresh_gear()
	if h.wrar > 0:
		b["weapon"] = {"wid": h.wid, "rar": h.wrar}
		h.equip(String(Data.CLASSES[h.cls]["weapon"]), 0)
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

# ------------------------------------------------------------------ what's in a box, item by item
## Everything in a box as a list for the loot window: [{key, i, name, sub, icon, col, upgrade}].
static func box_items(m: Match, h: Hunter, b: Dictionary) -> Array:
	var out: Array = []
	if int(b["gems"]) > 0:
		out.append({"key": "gems", "name": "%d gems" % int(b["gems"]), "sub": "Treasure", "icon": "gem", "col": Color("ffd36a"), "upgrade": true})
	for s in b["seeds"]:
		var cd: Dictionary = Data.CROPS.get(s, {})
		out.append({"key": "seeds", "i": s, "name": "%d %s seed%s" % [int(b["seeds"][s]), cd.get("name", s), "" if int(b["seeds"][s]) == 1 else "s"], "sub": "Seeds", "icon": "seed", "col": cd.get("color", Color("8fe0a0")), "upgrade": true})
	for i in (b["caught"] as Array).size():
		var rec: Dictionary = b["caught"][i]
		var sp: Dictionary = Data.KIN.get(String(rec.get("species", "")), {})
		out.append({"key": "caught", "i": i, "name": "%s the %s" % [rec.get("name", "Kin"), sp.get("name", "kin")], "sub": "Kin", "icon": "paw", "col": sp.get("color", Color("ffb0d0")), "upgrade": true})
	if int(b["tonics"]) > 0:
		out.append({"key": "tonics", "name": "%d tonic%s" % [int(b["tonics"]), "" if int(b["tonics"]) == 1 else "s"], "sub": "Heals", "icon": "tonic", "col": Color("ff8a9a"), "upgrade": true})
	if int(b["kits"]) > 0:
		out.append({"key": "kits", "name": "%d armor kit%s" % [int(b["kits"]), "" if int(b["kits"]) == 1 else "s"], "sub": "Repairs armor", "icon": "medkit", "col": Color("9ad0ff"), "upgrade": true})
	for i in (b.get("gear", []) as Array).size():
		var g: Dictionary = b["gear"][i]
		var gd: Dictionary = Gear.ALL.get(String(g["id"]), {})
		var r: Dictionary = Data.RARITY[clampi(int(g["rar"]), 0, Data.RARITY.size() - 1)]
		var slot := Gear.slot_of(String(g["id"]))
		var cur: Dictionary = h.gear[slot]
		var up := cur.is_empty() or int(g["rar"]) > int(cur["rar"])
		out.append({"key": "gear", "i": i, "name": "%s%s" % [(String(r["name"]) + " ") if int(g["rar"]) > 1 else "", gd.get("name", g["id"])],
			"sub": ("Active glove (%s)  ·  " % Settings.key_cap("gear1") if slot == 0 else "Passive glove  ·  ") + Gear.stat_text(String(g["id"]), int(g["rar"])),
			"icon": Gear.icon_of(String(g["id"])), "col": r["color"], "upgrade": up})
	var w: Dictionary = b.get("weapon", {})
	if not w.is_empty():
		var r2: Dictionary = Data.RARITY[clampi(int(w["rar"]), 0, Data.RARITY.size() - 1)]
		var up2 := int(w["rar"]) > h.wrar
		out.append({"key": "weapon", "name": Data.weapon_stats(String(w["wid"]), int(w["rar"]))["name"], "sub": "+%d%% damage" % int(round((float(r2["dmg"]) - 1.0) * 100.0)),
			"icon": String(w["wid"]), "col": r2["color"], "upgrade": up2})
	return out

## Takes one thing out of a box. Swapping gloves or weapons leaves yours in the box in its place.
static func take_item(m: Match, h: Hunter, b: Dictionary, it: Dictionary) -> void:
	match String(it["key"]):
		"gems":
			h.gems += int(b["gems"]); b["gems"] = 0
		"seeds":
			var s: String = it["i"]
			h.seeds[s] = int(h.seeds.get(s, 0)) + int(b["seeds"].get(s, 0))
			(b["seeds"] as Dictionary).erase(s)
		"caught":
			var i := int(it["i"])
			if i < (b["caught"] as Array).size():
				var rec: Dictionary = b["caught"][i]
				(b["caught"] as Array).remove_at(i)
				if h == m.player and String(rec.get("lost_from", "")) == "you":
					m.give_kin(h, rec)
					m.add_feed("%s is back with you!" % rec.get("name", "Your kin"))
				else:
					h.caught.append(rec)
					if String(rec.get("lost_from", "")) != "" and String(rec.get("lost_from", "")) != h.pname:
						h.stolen_carry = true
		"tonics":
			h.tonics += int(b["tonics"]); b["tonics"] = 0
		"kits":
			h.armor_kits += int(b["kits"]); b["kits"] = 0
		"gear":
			var gi := int(it["i"])
			if gi < (b["gear"] as Array).size():
				var g: Dictionary = b["gear"][gi]
				(b["gear"] as Array).remove_at(gi)
				var slot := Gear.slot_of(String(g["id"]))
				var old: Dictionary = h.gear[slot]
				h.gear[slot] = g.duplicate()
				h.gear_cd[slot] = 0.0
				h.refresh_gear()
				if not old.is_empty():
					(b["gear"] as Array).append(old)
		"weapon":
			var w: Dictionary = b["weapon"]
			var old_w := {"wid": h.wid, "rar": h.wrar}
			h.equip(String(w["wid"]), int(w["rar"]))
			b["weapon"] = old_w if int(old_w["rar"]) > 0 else {}
	m.sfx("pickup", b["pos"], -4.0, 0.9)
	_settle_box(b)

## Smart loot (press interact again with a box open): every gem, seed, kin and consumable, and the
## gloves or weapon only where they beat what you've got. Returns how many things it took.
static func smart_loot(m: Match, h: Hunter, b: Dictionary) -> int:
	var n := 0
	var guard := 0
	while guard < 30:
		guard += 1
		var took := false
		for it in box_items(m, h, b):
			if it["upgrade"]:
				take_item(m, h, b, it)
				n += 1
				took = true
				break
		if not took:
			break
	if n > 0:
		m.fx.burst(b["pos"] + Vector3(0, 0.6, 0), Color("ffd36a"), 14, 3.0, 0.4)
	return n

static func _settle_box(b: Dictionary) -> void:
	b["empty"] = int(b["gems"]) <= 0 and (b["seeds"] as Dictionary).is_empty() and (b["caught"] as Array).is_empty() \
		and int(b["tonics"]) <= 0 and int(b["kits"]) <= 0 and (b.get("gear", []) as Array).is_empty() and (b.get("weapon", {}) as Dictionary).is_empty()
	_refresh_box(b)

## Takes everything in a box.
static func loot_box(m: Match, h: Hunter, b: Dictionary) -> void:
	# gloves and a found weapon: the owner gets theirs back; anyone else only takes upgrades
	if (b["owner"] as Hunter) == h:
		for g in (b.get("gear", []) as Array).duplicate():
			take_item(m, h, b, {"key": "gear", "i": (b["gear"] as Array).find(g)})
		if not (b.get("weapon", {}) as Dictionary).is_empty():
			take_item(m, h, b, {"key": "weapon"})
	else:
		for it in box_items(m, h, b):
			if it["key"] in ["gear", "weapon"] and it["upgrade"]:
				take_item(m, h, b, it)
				break
	h.gems += int(b["gems"])
	for s in b["seeds"]:
		h.seeds[s] = int(h.seeds.get(s, 0)) + int(b["seeds"][s])
	for rec in b["caught"]:
		if h == m.player and String(rec.get("lost_from", "")) == "you":
			# one of yours the dead hunter had taken: it's straight back at your side
			m.give_kin(h, rec)
			m.add_feed("%s is back with you!" % rec.get("name", "Your kin"))
			continue
		h.caught.append(rec)
		if String(rec.get("lost_from", "")) != "" and String(rec.get("lost_from", "")) != h.pname:
			h.stolen_carry = true
	h.tonics += int(b["tonics"])
	h.armor_kits += int(b["kits"])
	_kin_from_box(m, h, b)
	var got := int(b["gems"])
	b["gems"] = 0; b["seeds"] = {}; b["caught"] = []; b["tonics"] = 0; b["kits"] = 0
	_settle_box(b)
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
		o.ai = m.bot_brain.new_mind(m.rng, float(m.opts.get("bot_skill", m.bot_cfg.get("skill", 0.6))), m.bot_cfg)
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
			if h.team != o.team:
				h.stolen_carry = true
				m.kin_stolen(h, rec)
		elif h.team != o.team:
			# a rival's kin: it's yours if you get it home (and it remembers how much it loved them)
			r2["prev_trust"] = float(rec.get("trust", 50.0))
			r2["lost_from"] = o.pname
			r2["trust"] = 20.0
			r2["memory"] = []
			h.stolen_carry = true
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
