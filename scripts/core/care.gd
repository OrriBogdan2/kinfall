class_name Care
## Raising a kin: four needs that drift over time, likes and dislikes you find out by trying,
## a nature from its personality, four trained stats, bond ranks, life stages, eggs and shimmers.
## Everything lives on the kin's save record, so it travels into matches and to other players.

const NEEDS := ["food", "energy", "joy", "clean"]
const NEED_INFO := {
	"food": {"name": "Full", "col": Color("f2a24a")},
	"energy": {"name": "Energy", "col": Color("8fd0ff")},
	"joy": {"name": "Happy", "col": Color("ff8fb0")},
	"clean": {"name": "Clean", "col": Color("8fe3c8")},
}
## How fast each need drops at home, per minute. Sleeping refills energy instead.
const DECAY := {"food": 1.5, "energy": 0.7, "joy": 0.6, "clean": 0.45}
## What an expedition takes out of the kin that went.
const MATCH_COST := {"food": -26.0, "energy": -34.0, "clean": -30.0}

## Starving: hours a kin has spent with nothing in it (food at zero), real time, at home or away.
## Each stage keeps the ones before it. A meal takes 4 hours off; being fed (food over 20) undoes it
## three times as fast as it built up. Feeders keep it from ever starting.
const STARVE := {"weak": 6.0, "refuse": 18.0, "sick": 30.0, "dead": 72.0}
const STARVE_INFO := {
	"starving": ["Starving", "Hasn't eaten in a while. Feed it, or fill a feeder."],
	"weak": ["Weak from hunger", "Slow, and weaker on expeditions. Losing trust in you."],
	"refuse": ["Too weak to go out", "Won't come on expeditions until it's eaten."],
	"sick": ["Sick from hunger", "Ill and miserable. It won't last much longer without food."],
}

const STATS := {
	"power": {"name": "Power", "col": Color("ff7a5a"), "desc": "+0.4% damage a point", "drill": "Dummy strikes"},
	"guard": {"name": "Guard", "col": Color("e6c26a"), "desc": "+0.5% health a point", "drill": "Brace and hold"},
	"speed": {"name": "Speed", "col": Color("6ad8ff"), "desc": "+0.25% speed a point", "drill": "Hoop dash"},
	"focus": {"name": "Focus", "col": Color("b9a6f5"), "desc": "Skill recharges 0.3% faster a point", "drill": "Still pond"},
}

const BONDS := [
	[0.0, "Wary", "Might refuse a risky throw."],
	[25.0, "Friendly", "Follows you around the farm."],
	[50.0, "Close", "Starts picking up words. Skills hit 5% harder."],
	[70.0, "Devoted", "Rushes to revive you without a second thought."],
	[90.0, "Soulbound", "Never refuses you. +10% health and damage."],
]

const STAGES := [[1, "Hatchling"], [4, "Youngling"], [8, "Grown"], [16, "Elder"]]

## Natures from the two strongest traits.
const NATURES := {
	"bravery+temper": "Fiery", "bravery+loyalty": "Valiant", "bravery+curiosity": "Daring",
	"loyalty+temper": "Protective", "curiosity+loyalty": "Gentle", "curiosity+temper": "Mischievous",
}

## Things a kin can love or hate. Foods are crops plus what the stall sells.
const FOODS := {
	"kibble": {"name": "Kin kibble", "col": Color("c8a26a"), "food": 30.0, "joy": 0.0, "price": 6, "desc": "Plain and filling."},
	"sweetbun": {"name": "Sweet bun", "col": Color("f6c6a0"), "food": 18.0, "joy": 18.0, "price": 14, "desc": "A treat. Makes any kin happy."},
	"tonicbrew": {"name": "Pep brew", "col": Color("8ff0a0"), "food": 6.0, "joy": 4.0, "energy": 35.0, "price": 18, "desc": "Wakes a tired kin right up."},
}
const PLAYS := ["fetch", "brush", "bath", "chat", "pet"]
const PLAY_NAMES := {"fetch": "playing fetch", "brush": "being brushed", "bath": "baths", "chat": "chatting", "pet": "scratches"}

## Fills in anything an older record is missing. Likes come from the kin's id, so they're fixed.
static func ensure(rec: Dictionary) -> void:
	if rec.is_empty():
		return
	if not rec.has("needs"):
		rec["needs"] = {"food": 70.0, "energy": 80.0, "joy": 70.0, "clean": 75.0}
	if not rec.has("needs_t"):
		rec["needs_t"] = Time.get_unix_time_from_system()
	if not rec.has("stats"):
		rec["stats"] = {"power": 0, "guard": 0, "speed": 0, "focus": 0}
	if not rec.has("likes"):
		var r := RandomNumberGenerator.new(); r.seed = hash(String(rec.get("uid", "x")) + "likes")
		var foods: Array = Data.CROPS.keys() + FOODS.keys()
		var love: String = foods[r.randi() % foods.size()]
		var hate: String = love
		while hate == love:
			hate = foods[r.randi() % foods.size()]
		rec["likes"] = {"food": love, "hates": hate, "play": PLAYS[r.randi() % PLAYS.size()]}
	if not rec.has("known"):
		rec["known"] = []          # which of food / hates / play you've found out

static func need(rec: Dictionary, n: String) -> float:
	ensure(rec)
	return float(rec["needs"].get(n, 50.0))

static func change(rec: Dictionary, n: String, amt: float) -> float:
	ensure(rec)
	var before := float(rec["needs"].get(n, 50.0))
	rec["needs"][n] = clampf(before + amt, 0.0, 100.0)
	return float(rec["needs"][n]) - before

## Time passing at home. sleeping: curled up in bed or napping.
static func tick(rec: Dictionary, secs: float, sleeping := false) -> void:
	ensure(rec)
	var mins := secs / 60.0
	var nd: Dictionary = rec["needs"]
	var f0 := float(nd["food"])
	var rate := DECAY["food"] / 60.0 * (0.5 if sleeping else 1.0)
	nd["food"] = clampf(float(nd["food"]) - DECAY["food"] * mins * (0.5 if sleeping else 1.0), 0.0, 100.0)
	# the part of this stretch spent with nothing in it counts toward starving
	starve_step(rec, secs, maxf(0.0, secs - f0 / maxf(0.0001, rate)) if float(nd["food"]) <= 0.0 else 0.0)
	nd["clean"] = clampf(float(nd["clean"]) - DECAY["clean"] * mins * (0.2 if sleeping else 1.0), 0.0, 100.0)
	if sleeping:
		nd["energy"] = clampf(float(nd["energy"]) + 9.0 * mins, 0.0, 100.0)
	else:
		nd["energy"] = clampf(float(nd["energy"]) - DECAY["energy"] * mins, 0.0, 100.0)
	# a hungry, grubby or worn-out kin gets glum faster
	var glum := 1.0 + (1.0 if float(nd["food"]) < 25.0 else 0.0) + (0.5 if float(nd["clean"]) < 20.0 else 0.0) + (0.5 if float(nd["energy"]) < 15.0 else 0.0)
	nd["joy"] = clampf(float(nd["joy"]) - DECAY["joy"] * mins * glum * (0.3 if sleeping else 1.0), 0.0, 100.0)
	if starve_h(rec) >= STARVE["sick"]:
		# sick from hunger: no energy and no joy to speak of
		nd["energy"] = minf(float(nd["energy"]), 35.0)
		nd["joy"] = minf(float(nd["joy"]), 25.0)
	rec["needs_t"] = Time.get_unix_time_from_system()

## The time you were away: it sleeps a lot of it off, and nothing drops below a floor (unless it
## was already hungry when you left). Returns the time away beyond half a day (up to two weeks):
## Econ.catch_up_all runs that slowly, hour by hour, with the feeders.
static func catch_up(rec: Dictionary) -> float:
	ensure(rec)
	var all := clampf(Time.get_unix_time_from_system() - float(rec["needs_t"]), 0.0, 14.0 * 86400.0)
	var gone := minf(all, 12.0 * 3600.0)
	if gone > 30.0:
		var nd: Dictionary = rec["needs"]
		var floors := {"food": 25.0, "joy": 30.0, "clean": 25.0}
		var before := {}
		for k in floors: before[k] = float(nd[k])
		var st0 := float(rec.get("starve", 0.0))
		tick(rec, gone * 0.5, true)
		tick(rec, minf(gone * 0.5, 1800.0), false)
		for k in floors:
			nd[k] = maxf(float(nd[k]), minf(float(before[k]), floors[k]))
		# the floor means it found enough to get by; one that was already empty starved the whole time
		var st1 := st0 + gone if float(before["food"]) <= 0.5 else minf(float(rec.get("starve", 0.0)), st0)
		if st1 > 0.0: rec["starve"] = st1
		else: rec.erase("starve")
	rec["needs_t"] = Time.get_unix_time_from_system()
	return maxf(0.0, all - 12.0 * 3600.0)

# ------------------------------------------------------------------ starving
static func starve_h(rec: Dictionary) -> float:
	return float(rec.get("starve", 0.0)) / 3600.0

## "" (fine), "starving", "weak", "refuse", "sick" or "dead".
static func starve_stage(rec: Dictionary) -> String:
	var h := starve_h(rec)
	if h >= STARVE["dead"]: return "dead"
	if h >= STARVE["sick"]: return "sick"
	if h >= STARVE["refuse"]: return "refuse"
	if h >= STARVE["weak"]: return "weak"
	if float(rec.get("starve", 0.0)) > 0.0 and need(rec, "food") <= 0.5: return "starving"
	return ""

## secs of time passing; zero_secs of it with an empty belly (defaults to all of it if food is 0).
static func starve_step(rec: Dictionary, secs: float, zero_secs := -1.0) -> void:
	var z := zero_secs if zero_secs >= 0.0 else (secs if need(rec, "food") <= 0.5 else 0.0)
	var st := float(rec.get("starve", 0.0))
	if z > 0.0:
		if st / 3600.0 >= STARVE["weak"]:
			# weak and still hungry: it trusts you a little less every few hours
			rec["trust"] = clampf(float(rec.get("trust", 0.0)) - z / 10800.0, 0.0, 100.0)
		st += z
	elif need(rec, "food") > 20.0 and st > 0.0:
		st = maxf(0.0, st - secs * 3.0)
	if st > 0.0: rec["starve"] = st
	else: rec.erase("starve")

## It just ate: a meal takes four hours off the starve clock.
static func fed(rec: Dictionary) -> void:
	if rec.has("starve"):
		var st := maxf(0.0, float(rec["starve"]) - 4.0 * 3600.0)
		if st > 0.0: rec["starve"] = st
		else: rec.erase("starve")

## Overall condition, 0 to 100.
static func condition(rec: Dictionary) -> float:
	ensure(rec)
	var nd: Dictionary = rec["needs"]
	return float(nd["food"]) * 0.3 + float(nd["energy"]) * 0.25 + float(nd["joy"]) * 0.3 + float(nd["clean"]) * 0.15

static func condition_name(rec: Dictionary) -> String:
	var ss := starve_stage(rec)
	if ss != "" and ss != "dead": return String(STARVE_INFO[ss][0])
	var c := condition(rec)
	if c >= 75.0: return "In great shape"
	if c >= 50.0: return "Doing fine"
	if c >= 28.0: return "A bit run down"
	return "Struggling"

## What it most wants right now, or "" if it's content.
static func want(rec: Dictionary) -> String:
	ensure(rec)
	var nd: Dictionary = rec["needs"]
	var best := ""; var bv := 38.0
	for k in ["food", "energy", "clean", "joy"]:
		if float(nd[k]) < bv:
			bv = float(nd[k]); best = k
	return best

## How the kin's shape at home carries into a match.
static func match_mods(rec: Dictionary) -> Dictionary:
	ensure(rec)
	var st: Dictionary = rec["stats"]
	var c := condition(rec)
	var cm := 1.1 if c >= 75.0 else (1.0 if c >= 50.0 else (0.92 if c >= 28.0 else 0.82))
	if starve_h(rec) >= STARVE["weak"]:
		cm *= 0.85        # weak from hunger
	var trust := float(rec.get("trust", 50.0))
	var bond := 1.1 if trust >= 90.0 else 1.0
	return {
		"dmg": (1.0 + float(st["power"]) * 0.004) * cm * bond,
		"hp": (1.0 + float(st["guard"]) * 0.005) * cm * bond,
		"speed": 1.0 + float(st["speed"]) * 0.0025,
		"cd": 1.0 - minf(0.3, float(st["focus"]) * 0.003),
		"skill": 1.05 if trust >= 50.0 else 1.0,
		"mood": clampf((c - 50.0) / 50.0, -1.0, 1.0),
	}

## Trained points can't run too far ahead of its level.
static func stat_cap(rec: Dictionary) -> int:
	return 12 + int(rec.get("level", 1)) * 6

static func add_stat(rec: Dictionary, s: String, n: int) -> int:
	ensure(rec)
	var before := int(rec["stats"].get(s, 0))
	rec["stats"][s] = clampi(before + n, 0, stat_cap(rec))
	return int(rec["stats"][s]) - before

static func bond(rec: Dictionary) -> Array:
	var t := float(rec.get("trust", 0.0))
	var out: Array = BONDS[0]
	for b in BONDS:
		if t >= float(b[0]): out = b
	return out

static func bond_index(rec: Dictionary) -> int:
	var t := float(rec.get("trust", 0.0))
	var i := 0
	for j in BONDS.size():
		if t >= float(BONDS[j][0]): i = j
	return i

static func next_bond(rec: Dictionary) -> Array:
	var i := bond_index(rec)
	return BONDS[i + 1] if i + 1 < BONDS.size() else []

static func stage_name(rec: Dictionary) -> String:
	var lv := int(rec.get("level", 1))
	var out: String = STAGES[0][1]
	for s in STAGES:
		if lv >= int(s[0]): out = s[1]
	return out

static func nature(rec: Dictionary) -> String:
	var tr: Dictionary = rec.get("traits", {})
	var keys := ["bravery", "loyalty", "temper", "curiosity"]
	keys.sort_custom(func(a, b): return float(tr.get(a, 0.5)) > float(tr.get(b, 0.5)))
	var pair := [keys[0], keys[1]]
	pair.sort()
	return String(NATURES.get("+".join(pair), "Easygoing"))

## How well it speaks: 0 only its own name, 1 a few words, 2 simple sentences, 3 fluent.
static func speech(rec: Dictionary) -> int:
	var lv := int(rec.get("level", 1))
	var t := float(rec.get("trust", 0.0))
	if lv >= 12 and t >= 70.0: return 3
	if lv >= 8 and t >= 50.0: return 2
	if lv >= 4 and t >= 35.0: return 1
	return 0

static func food_name(f: String) -> String:
	if Data.CROPS.has(f): return String(Data.CROPS[f]["name"])
	if FOODS.has(f): return String(FOODS[f]["name"])
	return f

static func food_col(f: String) -> Color:
	if Data.CROPS.has(f): return Data.CROPS[f]["color"]
	if FOODS.has(f): return FOODS[f]["col"]
	return Color.WHITE

## Learns something about the kin. Returns true the first time.
static func discover(rec: Dictionary, what: String) -> bool:
	ensure(rec)
	if (rec["known"] as Array).has(what):
		return false
	rec["known"].append(what)
	return true

## Feeding. Returns {ok, love, hate, full, text}.
static func feed(rec: Dictionary, f: String) -> Dictionary:
	ensure(rec)
	var likes: Dictionary = rec["likes"]
	var out := {"ok": true, "love": f == likes["food"], "hate": f == likes["hates"], "full": need(rec, "food") >= 92.0, "new": false}
	if out["hate"]:
		out["ok"] = false
		change(rec, "joy", -6.0)
		out["new"] = discover(rec, "hates")
		return out
	if out["full"] and not out["love"]:
		out["ok"] = false
		return out
	var fill := 28.0
	var joy := 6.0
	if FOODS.has(f):
		fill = float(FOODS[f]["food"]); joy = float(FOODS[f].get("joy", 0.0))
		change(rec, "energy", float(FOODS[f].get("energy", 0.0)))
	if out["love"]:
		joy += 22.0
		out["new"] = discover(rec, "food")
	var was := need(rec, "food")
	change(rec, "food", fill)
	change(rec, "joy", joy)
	fed(rec)
	out["hungry"] = was < 35.0
	return out

## Kin from an egg: mostly one parent's species, a blend of both personalities, a head start
## along a parent's way of growing, and a small chance to shimmer.
static func breed(a: Dictionary, b: Dictionary, rng: RandomNumberGenerator, sp := "") -> Dictionary:
	if sp == "" or not Data.KIN.has(sp):
		sp = a["species"] if rng.randf() < 0.5 else b["species"]
	var baby := Save.new_kin(sp)
	for t in baby["traits"]:
		var mix := (float(a["traits"].get(t, 0.5)) + float(b["traits"].get(t, 0.5))) * 0.5
		baby["traits"][t] = clampf(mix + rng.randf_range(-0.12, 0.12), 0.05, 0.95)
	Evo.ensure(baby)
	var lead := Evo.leading(a if rng.randf() < 0.5 else b)
	Evo.add(baby, lead, 8.0)
	var shimmer_chance := 1.0 / 12.0 + (0.15 if a.get("shimmer", false) else 0.0) + (0.15 if b.get("shimmer", false) else 0.0)
	baby["shimmer"] = rng.randf() < shimmer_chance
	baby["trust"] = 55.0
	baby["parents"] = [String(a["name"]), String(b["name"])]
	ensure(baby)
	return baby

## Rare Eggs brought home from boss lairs wait in the hatchery (Save.d["rare_eggs"]) and settle into the
## nest one at a time, whenever it's empty. Returns true if one just settled.
static func settle_rare_egg() -> bool:
	if not Save.d.get("egg", {}).is_empty():
		return false
	var q: Array = Save.d.get("rare_eggs", [])
	if q.is_empty():
		return false
	var e: Dictionary = q.pop_front()
	Save.d["egg"] = {"sp": String(e.get("sp", "")), "rare": true, "boss": String(e.get("boss", "")), "m": int(Save.d.get("matches", 0)), "t": 0.0}
	return true

## What hatches from a Rare Egg: a kin of the rare species its boss guarded, a little grown already,
## glad to see you, now and then shimmering too.
static func hatch_rare(egg: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var sp := String(egg.get("sp", ""))
	if not Data.KIN.has(sp):
		sp = String(Data.common_kin()[0])
	var baby := Save.new_kin(sp)
	baby["rare"] = true
	baby["level"] = 3
	baby["trust"] = 50.0
	baby["shimmer"] = rng.randf() < 0.1
	baby["from_boss"] = String(egg.get("boss", ""))
	Evo.ensure(baby)
	ensure(baby)
	return baby

## A shimmer's colours: the species palette turned partway round the colour wheel.
static func shimmer_col(c: Color) -> Color:
	var h := fposmod(c.h + 0.45, 1.0)
	return Color.from_hsv(h, clampf(c.s * 0.85 + 0.1, 0.0, 1.0), clampf(c.v * 1.05 + 0.05, 0.0, 1.0), c.a)

## A kin back from the Soul Shrine: its colours washed pale and cool, like moonlight.
static func ghost_col(c: Color) -> Color:
	return c.lerp(Color("cfeff0"), 0.55).lerp(Color("9ff0e0"), 0.12)

## The Kindex: what you've seen, caught and grown.
static func dex_mark(species: String, what: String, extra := "") -> void:
	if not Save.d.has("dex"):
		Save.d["dex"] = {}
	var dx: Dictionary = Save.d["dex"]
	if not dx.has(species):
		dx[species] = {"seen": false, "caught": false, "forms": [], "shimmer": false}
	var e: Dictionary = dx[species]
	match what:
		"seen": e["seen"] = true
		"caught": e["seen"] = true; e["caught"] = true
		"form":
			if extra != "" and not (e["forms"] as Array).has(extra): e["forms"].append(extra)
		"shimmer": e["shimmer"] = true

## Everything already in the roster counts toward the Kindex.
static func dex_sync() -> void:
	for rec in Save.d.get("roster", []):
		dex_mark(rec["species"], "caught")
		var fn := Evo.form_name(rec)
		if fn != String(Data.KIN[rec["species"]]["name"]): dex_mark(rec["species"], "form", fn)
		if rec.get("shimmer", false): dex_mark(rec["species"], "shimmer")
