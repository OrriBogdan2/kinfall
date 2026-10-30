class_name Econ
## The home side of loot and kin keeping, all on the save (Save.d):
##   armory    weapons and gloves you brought home (Loot items), a storage cap you can raise, the
##             loadout you take on the next expedition, valuables to sell and scrap to upgrade with
##   backpack  how many slots you get on an expedition (pack_lvl)
##   feeders   troughs on the farm you fill with food; hungry kin help themselves, even while you're away
##   graves    kin that died (starved), with their memories; the Soul Shrine brings one back, changed
## Starvation itself is in Care (the starve clock); what it leads to (death, a grave) is here.

# ------------------------------------------------------------------ numbers
const ARM_CAPS := [16, 24, 32, 40]
const ARM_UPGRADE := [[100, 6], [220, 14], [400, 25]]       # [gems, scrap] for the next level
const PACK_CAPS := [6, 8, 10, 12]
const PACK_UPGRADE := [[120, 4], [260, 10], [450, 20]]

const FEEDERS := {
	"trough": {"name": "Wooden trough", "cap": 6, "mult": 1.0, "seats": 3, "auto": false, "joy": 0.0, "price": 40, "col": Color("a07850"),
		"desc": "Holds 6 meals. Hungry kin come and help themselves."},
	"basket": {"name": "Woven feeder", "cap": 10, "mult": 1.15, "seats": 4, "auto": false, "joy": 2.0, "price": 90, "col": Color("d8b878"),
		"desc": "Holds 10 meals, and food from it fills 15% more."},
	"hopper": {"name": "Auto hopper", "cap": 14, "mult": 1.25, "seats": 5, "auto": true, "joy": 3.0, "price": 200, "col": Color("8fb8d8"),
		"desc": "Holds 14, fills 25% more, and tops itself up from your pantry when it runs low."},
	"banquet": {"name": "Banquet table", "cap": 20, "mult": 1.5, "seats": 6, "auto": true, "joy": 6.0, "price": 360, "col": Color("e8a0c0"),
		"desc": "Holds 20, refills itself, and every meal fills 50% more and cheers them up."},
}
const FEEDER_ORDER := ["trough", "basket", "hopper", "banquet"]
const MAX_FEEDERS := 4
const FEEDER_START := Vector3(40.4, 0, 29.4)     # your first trough, by the cooking pot
## Food the hoppers won't take from your pantry on their own (treats and rare crops).
const PANTRY_KEEP := ["starfruit", "glowcap", "mindmint", "tonicbrew", "sweetbun"]
## Meals while you're away: a kin eats when its food drops below this.
const HUNGRY_AT := 50.0
## Away from home for more than half a day, kin forage a little: food drops this much an hour.
const AWAY_FOOD_H := 4.0

const SHRINE_SLOTS := 3
const REVIVE_GEMS := 60
const REVIVE_PER_LEVEL := 10
const TITLES := ["the Returned", "Twice-Born", "Soulbright", "Lantern-Lit", "Ember-Kept"]

# ------------------------------------------------------------------ the save
## Fills in what an older save is missing, and puts back anything left "out" by a crash mid-expedition.
static func ensure() -> void:
	var d := Save.d
	ensure_min()
	for k in ["arm_lvl", "pack_lvl", "scrap"]:
		if not d.has(k): d[k] = 0
	for k in ["feeders", "graves"]:
		if not d.has(k): d[k] = []
	if not d.has("feeder_inv"): d["feeder_inv"] = {}
	if not d.get("feeder_given", false):
		d["feeder_given"] = true
		if (d["feeders"] as Array).is_empty():
			# everyone starts with a trough by the pot, with a few meals in it
			d["feeders"].append({"id": "f1", "kind": "trough", "x": FEEDER_START.x, "z": FEEDER_START.z, "food": ["kibble", "kibble", "kibble"], "auto": true})
	if not (d["raid_out"] as Array).is_empty():
		for it in d["raid_out"]:
			_store(it)
		d["raid_out"] = []

static func pack_cap() -> int:
	return PACK_CAPS[clampi(int(Save.d.get("pack_lvl", 0)), 0, PACK_CAPS.size() - 1)]

static func arm_cap() -> int:
	return ARM_CAPS[clampi(int(Save.d.get("arm_lvl", 0)), 0, ARM_CAPS.size() - 1)]

# ------------------------------------------------------------------ the armory
static func armory() -> Array:
	return Save.d.get("armory", [])

static func find(uid: String) -> Dictionary:
	for it in armory():
		if String(it.get("uid", "")) == uid: return it
	return {}

static func _store(it: Dictionary) -> void:
	if String(it.get("t", "")) == "val":
		var vd: Dictionary = Save.d["valuables"]
		vd[String(it["id"])] = int(vd.get(String(it["id"]), 0)) + 1
	else:
		Save.d["armory"].append(it)

static func sell(uid: String) -> int:
	var it := find(uid)
	if it.is_empty(): return 0
	var g := Loot.sell_price(it)
	_remove(uid)
	Save.d["gems"] = int(Save.d["gems"]) + g
	return g

static func salvage(uid: String) -> int:
	var it := find(uid)
	if it.is_empty(): return 0
	var n := Loot.scrap_of(it)
	_remove(uid)
	Save.d["scrap"] = int(Save.d.get("scrap", 0)) + n
	return n

static func _remove(uid: String) -> void:
	var arr: Array = Save.d["armory"]
	for i in arr.size():
		if String(arr[i].get("uid", "")) == uid:
			arr.remove_at(i)
			break
	var lo: Dictionary = Save.d["loadout"]
	for k in lo.keys():
		if String(lo[k]) == uid: lo.erase(k)

static func sell_valuable(id: String) -> int:
	var vd: Dictionary = Save.d["valuables"]
	if int(vd.get(id, 0)) <= 0: return 0
	vd[id] = int(vd[id]) - 1
	if int(vd[id]) <= 0: vd.erase(id)
	var g := int(Loot.VALUABLES.get(id, {}).get("value", 0))
	Save.d["gems"] = int(Save.d["gems"]) + g
	return g

static func embers() -> int:
	return int(Save.d.get("valuables", {}).get("soul_ember", 0))

static func use_ember() -> bool:
	if embers() <= 0: return false
	var vd: Dictionary = Save.d["valuables"]
	vd["soul_ember"] = int(vd["soul_ember"]) - 1
	if int(vd["soul_ember"]) <= 0: vd.erase("soul_ember")
	return true

## Buy the next armory or backpack level. which: "arm" or "pack". Returns "" or why not.
static func upgrade(which: String) -> String:
	var lvl := int(Save.d.get(which + "_lvl", 0))
	var costs: Array = ARM_UPGRADE if which == "arm" else PACK_UPGRADE
	if lvl >= costs.size(): return "Fully upgraded"
	var c: Array = costs[lvl]
	if int(Save.d["gems"]) < int(c[0]): return "Not enough gems"
	if int(Save.d.get("scrap", 0)) < int(c[1]): return "Not enough scrap (salvage spare weapons)"
	Save.d["gems"] = int(Save.d["gems"]) - int(c[0])
	Save.d["scrap"] = int(Save.d["scrap"]) - int(c[1])
	Save.d[which + "_lvl"] = lvl + 1
	return ""

## The loadout: slot "weapon", "glove0" (active) or "glove1" (passive) -> an armory uid, or "" for none.
static func loadout(slot: String) -> Dictionary:
	var uid := String(Save.d.get("loadout", {}).get(slot, ""))
	return find(uid) if uid != "" else {}

static func set_loadout(slot: String, uid: String) -> void:
	if uid == "": Save.d["loadout"].erase(slot)
	else: Save.d["loadout"][slot] = uid

static func glove_slot(it: Dictionary) -> String:
	return "glove%d" % Gear.slot_of(String(it.get("id", "")))

## Setting out: the loadout leaves the armory and rides with you (at risk until you're home).
static func begin_raid() -> Array:
	var out: Array = []
	for slot in ["weapon", "glove0", "glove1"]:
		var it := loadout(slot)
		if it.is_empty(): continue
		Save.d["armory"].erase(it)
		out.append(it)
	Save.d["raid_out"] = out.duplicate(true)
	return out

## Back from an expedition: what you carried goes into the armory (sold if it's full), what you
## lost is gone. Fills out["haul"], out["lost_items"], out["arm_sold"].
static func after_raid(r: Dictionary, out: Dictionary) -> void:
	ensure_min()
	var won: bool = r.get("extracted", false)
	Save.d["raid_out"] = []
	out["haul"] = []
	out["arm_sold"] = 0
	if won:
		for it in r.get("haul", []):
			var item: Dictionary = (it as Dictionary).duplicate(true)
			if not item.has("uid"): item["uid"] = Loot._uid()
			if String(item.get("t", "")) != "val" and armory().size() >= arm_cap():
				out["arm_sold"] = int(out["arm_sold"]) + Loot.sell_price(item)
				Save.d["gems"] = int(Save.d["gems"]) + Loot.sell_price(item)
				item["sold"] = true
			else:
				_store(item)
			out["haul"].append(item)
	else:
		out["lost_items"] = r.get("lost_items", [])
	# loadout pieces that didn't come home are gone from it
	var lo: Dictionary = Save.d["loadout"]
	for k in lo.keys():
		if find(String(lo[k])).is_empty(): lo.erase(k)

static func ensure_min() -> void:
	for k in ["armory", "raid_out"]:
		if not Save.d.has(k): Save.d[k] = []
	for k in ["loadout", "valuables"]:
		if not Save.d.has(k): Save.d[k] = {}

# ------------------------------------------------------------------ feeders
static func feeders() -> Array:
	return Save.d.get("feeders", [])

static func fdef(f: Dictionary) -> Dictionary:
	return FEEDERS.get(String(f.get("kind", "trough")), FEEDERS["trough"])

static func fill(f: Dictionary) -> int:
	return (f.get("food", []) as Array).size()

static func room_in(f: Dictionary) -> int:
	return int(fdef(f)["cap"]) - fill(f)

static func pantry(key: String) -> int:
	return int(Save.d["crops"].get(key, 0)) if Data.CROPS.has(key) else int(Save.d["items"].get(key, 0))

static func _take_pantry(key: String) -> bool:
	if pantry(key) <= 0: return false
	if Data.CROPS.has(key): Save.d["crops"][key] = int(Save.d["crops"][key]) - 1
	else: Save.d["items"][key] = int(Save.d["items"][key]) - 1
	return true

## Puts n of a food from the pantry into a feeder. Returns how many went in.
static func put_in(f: Dictionary, key: String, n := 1) -> int:
	var got := 0
	while got < n and room_in(f) > 0 and _take_pantry(key):
		(f["food"] as Array).append(key)
		got += 1
	return got

## Food a hopper may take on its own, most plentiful first.
static func _auto_food() -> String:
	var best := ""; var bn := 0
	for key in Care.FOODS.keys() + Data.CROPS.keys():
		if PANTRY_KEEP.has(key): continue
		if pantry(key) > bn: bn = pantry(key); best = key
	return best

## A self-filling feeder below half tops itself up from the pantry. Returns how many it took.
static func auto_refill(f: Dictionary) -> int:
	if not fdef(f)["auto"] or not f.get("auto", true) or fill(f) > int(fdef(f)["cap"]) / 2:
		return 0
	var got := 0
	while room_in(f) > 0:
		var key := _auto_food()
		if key == "" or put_in(f, key, 1) == 0: break
		got += 1
	return got

## A kin eats one meal from a feeder: the first food in it that it doesn't hate. Returns the result
## (Care.feed's, plus "food") or {} if there was nothing it would eat.
static func serve(f: Dictionary, rec: Dictionary) -> Dictionary:
	var food: Array = f.get("food", [])
	var hate := String(rec.get("likes", {}).get("hates", ""))
	var love := String(rec.get("likes", {}).get("food", ""))
	var pick := -1
	for i in food.size():
		if String(food[i]) == love: pick = i; break
	if pick < 0:
		for i in food.size():
			if String(food[i]) != hate: pick = i; break
	if pick < 0:
		return {}
	var key := String(food[pick])
	var before := Care.need(rec, "food")
	var res := Care.feed(rec, key)
	if not res.get("ok", false):
		return {}
	food.remove_at(pick)
	# a better feeder makes every meal go further
	var gained := Care.need(rec, "food") - before
	Care.change(rec, "food", gained * (float(fdef(f)["mult"]) - 1.0))
	Care.change(rec, "joy", float(fdef(f)["joy"]))
	res["food"] = key
	auto_refill(f)
	return res

## A meal from any feeder with something this kin will eat (for time away). {} if none.
static func serve_any(rec: Dictionary) -> Dictionary:
	for f in feeders():
		auto_refill(f)
		var res := serve(f, rec)
		if not res.is_empty(): return res
	return {}

## The time you were away, for every kin at once: the usual catch-up (Care.catch_up) for up to half
## a day, then for longer absences food runs down slowly, hour by hour, and hungry kin eat from the
## feeders in turn. Kin with nothing left to eat start to starve (Care's starve clock).
## Returns what happened: [{kind: "died"|"starving", rec, ...}].
static func catch_up_all() -> Array:
	var roster: Array = Save.d["roster"]
	var extra := {}
	for rec in roster:
		var ex := Care.catch_up(rec)
		if ex > 0.0: extra[rec["uid"]] = ex
		# half a day or less away: still a meal if they're hungry and there's food out
		if Care.need(rec, "food") < HUNGRY_AT:
			serve_any(rec)
	var guard := 0
	while not extra.is_empty() and guard < 24 * 14:
		guard += 1
		for rec in roster:
			if not extra.has(rec["uid"]): continue
			var step := minf(3600.0, float(extra[rec["uid"]]))
			extra[rec["uid"]] = float(extra[rec["uid"]]) - step
			if float(extra[rec["uid"]]) <= 0.0: extra.erase(rec["uid"])
			Care.change(rec, "food", -AWAY_FOOD_H * step / 3600.0)
			if Care.need(rec, "food") < HUNGRY_AT:
				serve_any(rec)
			Care.starve_step(rec, step)
	return check_starving()

## Kin whose starving has gone too far die; the rest get a warning. [{kind, rec, grave?}]
static func check_starving() -> Array:
	var ev: Array = []
	for rec in (Save.d["roster"] as Array).duplicate():
		var st := Care.starve_stage(rec)
		if st == "dead":
			ev.append({"kind": "died", "rec": rec, "grave": kin_dies(rec, "starved")})
		elif st != "":
			ev.append({"kind": "starving", "rec": rec, "stage": st})
	return ev

# ------------------------------------------------------------------ death and the graveyard
## A kin dies: off the roster, into a grave with its memories.
static func kin_dies(rec: Dictionary, cause: String) -> Dictionary:
	var d := Save.d
	d["roster"].erase(rec)
	var mem: Array = (rec.get("memory", []) as Array).duplicate(true)
	var g := {"uid": String(rec["uid"]), "name": String(rec["name"]), "species": String(rec["species"]), "level": int(rec.get("level", 1)),
		"cause": cause, "t": Time.get_unix_time_from_system(), "m": int(d.get("matches", 0)), "mem": mem.slice(maxi(0, mem.size() - 8)),
		"shimmer": rec.get("shimmer", false), "ghost": rec.get("ghost", false), "title": String(rec.get("title", "")), "soul": false, "rec": rec.duplicate(true)}
	d["graves"].append(g)
	if str(d.get("active", "")) == String(rec["uid"]):
		d["active"] = d["roster"][0]["uid"] if not (d["roster"] as Array).is_empty() else ""
	if str(d.get("active2", "")) == String(rec["uid"]):
		d["active2"] = ""
	return g

static func graves() -> Array:
	return Save.d.get("graves", [])

static func souls_kept() -> int:
	return graves().filter(func(g): return g.get("soul", false)).size()

static func epitaph(g: Dictionary) -> String:
	var sp: Dictionary = Data.KIN.get(String(g.get("species", "")), {})
	var why := "Starved while you were away" if String(g.get("cause", "")) == "starved" else "Lost"
	return "%s, a level %d %s. %s." % [g["name"], int(g["level"]), sp.get("name", "kin"), why]

## What bringing a kin back costs: one Soul Ember, and gems by its level.
static func revive_cost(g: Dictionary) -> int:
	return REVIVE_GEMS + REVIVE_PER_LEVEL * int(g.get("level", 1))

## Gathers a grave's soul into the shrine (it has room for a few). Returns "" or why not.
static func keep_soul(g: Dictionary) -> String:
	if not Save.has_building("shrine"): return "Build the Soul Shrine first"
	if g.get("soul", false): return "Already in the shrine"
	if souls_kept() >= SHRINE_SLOTS: return "The shrine holds %d souls at most" % SHRINE_SLOTS
	g["soul"] = true
	return ""

## Brings a kin back from its kept soul. It returns slightly different: its personality shifted, a
## ghostly shimmer, a couple of levels and some trust lost, only a few memories, a new title, and
## new tastes. Returns the new record, or {} if it can't (see revive_why).
static func revive(g: Dictionary, rng: RandomNumberGenerator = null) -> Dictionary:
	if revive_why(g) != "":
		return {}
	if rng == null:
		rng = RandomNumberGenerator.new(); rng.randomize()
	use_ember()
	Save.d["gems"] = int(Save.d["gems"]) - revive_cost(g)
	var rec: Dictionary = (g["rec"] as Dictionary).duplicate(true)
	rec["uid"] = "k%d%d" % [Time.get_ticks_usec() % 1000000, rng.randi() % 1000]
	# its personality comes back a little rearranged
	var tr: Dictionary = rec.get("traits", {})
	var keys: Array = tr.keys()
	if keys.size() >= 2:
		var a: String = keys[rng.randi() % keys.size()]
		var b: String = a
		while b == a: b = keys[rng.randi() % keys.size()]
		var va := float(tr[a]); var vb := float(tr[b])
		tr[a] = lerpf(va, vb, 0.6); tr[b] = lerpf(vb, va, 0.6)
	for t in tr:
		tr[t] = clampf(float(tr[t]) + rng.randf_range(-0.08, 0.08), 0.05, 0.95)
	rec["level"] = maxi(1, int(rec.get("level", 1)) - 2)
	rec["xp"] = 0
	rec["trust"] = clampf(float(rec.get("trust", 40.0)) * 0.7, 25.0, 70.0)
	if rec.has("stats"):
		for s in rec["stats"]: rec["stats"][s] = int(int(rec["stats"][s]) * 0.75)
	var mem: Array = rec.get("memory", [])
	rec["memory"] = mem.slice(maxi(0, mem.size() - 3))
	rec["ghost"] = true
	rec["title"] = TITLES[rng.randi() % TITLES.size()]
	rec["revived"] = int(rec.get("revived", 0)) + 1
	rec.erase("likes"); rec.erase("known")          # new tastes: it has to be got to know again
	rec.erase("needs"); rec.erase("needs_t"); rec.erase("starve")
	rec.erase("pending_evo"); rec.erase("lost_from"); rec.erase("farmhand")
	Care.ensure(rec)
	rec["needs"] = {"food": 80.0, "energy": 60.0, "joy": 55.0, "clean": 90.0}
	Save.remember(rec, "returned", "came back from the Soul Shrine, %s" % rec["title"], 0.0)
	Save.d["roster"].append(rec)
	Save.d["graves"].erase(g)
	if str(Save.d.get("active", "")) == "":
		Save.d["active"] = rec["uid"]
	return rec

static func revive_why(g: Dictionary) -> String:
	if not Save.has_building("shrine"): return "Build the Soul Shrine first"
	if not g.get("soul", false): return "Gather its soul into the shrine first"
	if embers() <= 0: return "Needs a Soul Ember (found in vaults and on Wardens)"
	if int(Save.d["gems"]) < revive_cost(g): return "Needs %d gems" % revive_cost(g)
	return ""

## What the shrine itself needs before you can build it.
static func shrine_why() -> String:
	if int(Save.d.get("extracts", 0)) < 3 and not Game.modding(): return "Make it out of %d more expedition%s first" % [3 - int(Save.d.get("extracts", 0)), "" if 3 - int(Save.d.get("extracts", 0)) == 1 else "s"]
	if embers() <= 0: return "It needs a Soul Ember to light it (found in vaults and on Wardens)"
	if int(Save.d["gems"]) < int(Data.BUILDINGS["shrine"]["cost"]): return "Not enough gems"
	return ""
