class_name Loot
## Things you can carry home from an expedition, as plain dictionaries (they go in the save as-is):
##   weapon  {t:"weapon", wid, rar, el, uq, uid}   a rarity, maybe an element, maybe a named unique
##   glove   {t:"glove", id, rar, uid}
##   valuable{t:"val", id, uid}                   sold at home; a Soul Ember revives a kin
## Their worth (value) drives smart loot and what the backpack keeps. The element riders run on the
## weapon's own hits (Hunter._emit_shot / _strike call rider()).

## Elements found on weapons, one per biome style (the Greenreach meadow has none of its own).
const ELEMENTS := {
	"fire": {"name": "Ember", "col": Color("ff8a3a"), "biome": "ember", "icon": "fireball",
		"rider": "Burns: 5 damage a second for 3s."},
	"frost": {"name": "Frost", "col": Color("bff0ff"), "biome": "frost", "icon": "snare",
		"rider": "Chills: slows for 1s, and every 5th hit freezes them in place."},
	"storm": {"name": "Storm", "col": Color("fff27a"), "biome": "storm", "icon": "chain",
		"rider": "Every 4th hit arcs to 2 more foes for half damage."},
	"venom": {"name": "Venom", "col": Color("9aff6a"), "biome": "bloom", "icon": "burst",
		"rider": "Poisons: 3 damage a second and a light slow."},
	"void": {"name": "Void", "col": Color("b08aff"), "biome": "gloom", "icon": "shadowstep",
		"rider": "Drains: heals you for 8% of the damage you deal."},
}

## Named weapons: always Legendary, always elemental, with a perk on top of the element and 10%
## more damage. Wardens and vaults drop them, rarely.
const UNIQUES := {
	"sunsplitter": {"name": "Sunsplitter", "wid": "greatsword", "el": "fire", "perk": "Burns twice as hot.", "mods": {"burn_x": 2.0}},
	"hoarfang": {"name": "Hoarfang", "wid": "sniper", "el": "frost", "perk": "Every hit freezes.", "mods": {"freeze_every": 1}},
	"thunderclap": {"name": "Thunderclap", "wid": "minigun", "el": "storm", "perk": "Every 2nd hit arcs.", "mods": {"chain_every": 2}},
	"widowsting": {"name": "Widowsting", "wid": "smg", "el": "venom", "perk": "Poison bites harder and slows more.", "mods": {"burn_x": 1.8, "slow_x": 2.0}},
	"hollowsong": {"name": "Hollowsong", "wid": "rifle", "el": "void", "perk": "Drains 20% instead of 8%.", "mods": {"leech": 0.2}},
}
const UNIQUE_DMG := 1.1

## Treasure to sell at home, and the Soul Ember the Soul Shrine needs.
const VALUABLES := {
	"old_coin": {"name": "Old Coin", "col": Color("e8c27a"), "value": 14, "rar": 1, "desc": "Sells for a few gems."},
	"sky_pearl": {"name": "Sky Pearl", "col": Color("cfeaff"), "value": 32, "rar": 2, "desc": "Sells well."},
	"kin_idol": {"name": "Kin Idol", "col": Color("ffb0d0"), "value": 58, "rar": 3, "desc": "A little carved kin. Collectors pay a lot."},
	"crown_shard": {"name": "Crown Shard", "col": Color("ffd23f"), "value": 105, "rar": 4, "desc": "A piece of an old crown. Worth a fortune."},
	"soul_ember": {"name": "Soul Ember", "col": Color("9ff0e0"), "value": 140, "rar": 4, "desc": "A warm, glowing ember. The Soul Shrine needs one to raise it, and one for every kin it brings back."},
}

## What each kind of thing is worth by rarity (Common..Legendary). Weapons weigh a little more than
## gloves: they're the whole loadout.
const WEAPON_VALUE := [4, 10, 22, 45, 90]
const GLOVE_VALUE := [3, 8, 18, 36, 70]
const ELEMENT_VALUE := 1.4
const UNIQUE_VALUE := 2.2

# ------------------------------------------------------------------ making things
static func _uid() -> String:
	return "i%d%d" % [Time.get_ticks_usec() % 10000000, randi() % 10000]

static func weapon(wid: String, rar: int, el := "", uq := "") -> Dictionary:
	if uq != "" and UNIQUES.has(uq):
		wid = String(UNIQUES[uq]["wid"]); el = String(UNIQUES[uq]["el"]); rar = Data.RARITY.size() - 1
	return {"t": "weapon", "wid": wid, "rar": rar, "el": el, "uq": uq, "uid": _uid()}

static func glove(id: String, rar: int) -> Dictionary:
	return {"t": "glove", "id": id, "rar": rar, "uid": _uid()}

static func valuable(id: String) -> Dictionary:
	return {"t": "val", "id": id, "uid": _uid()}

## A weapon you're holding as an item (the one in hand, from its parts).
static func of_hand(h) -> Dictionary:
	if not h.winst.is_empty():
		return h.winst
	return {"t": "weapon", "wid": h.wid, "rar": h.wrar, "el": "", "uq": ""}

## A found weapon is worth keeping; the plain one your class carries isn't (it's always free).
static func keepable(it: Dictionary) -> bool:
	if it.is_empty():
		return false
	match String(it.get("t", "weapon")):
		"weapon": return int(it.get("rar", 0)) > 0 or String(it.get("el", "")) != "" or String(it.get("uq", "")) != ""
		"glove": return Gear.ALL.has(String(it.get("id", "")))
		"val": return VALUABLES.has(String(it.get("id", "")))
	return false

## Puts a weapon item in a hunter's hands: rarity, element and unique perk.
static func equip(h, it: Dictionary, ammo := -1) -> void:
	h.equip(String(it.get("wid", h.wid)), int(it.get("rar", 0)), ammo)
	h.winst = it.duplicate() if keepable(it) else {}
	h.welem = String(it.get("el", ""))
	h.wuniq = String(it.get("uq", ""))
	h.wpn["name"] = name_of(it)
	if h.wuniq != "":
		h.wpn["dmg"] = float(h.wpn["dmg"]) * UNIQUE_DMG
		if h.wpn.has("charged_dmg"): h.wpn["charged_dmg"] = float(h.wpn["charged_dmg"]) * UNIQUE_DMG
		if h.wpn.has("combo_dmg"): h.wpn["combo_dmg"] = (h.wpn["combo_dmg"] as Array).map(func(x): return float(x) * UNIQUE_DMG)
	if h.welem != "" and h.model:
		# a tint of the element on the gun
		var gun: Node3D = h.model.find_child("Gun", true, false)
		if gun:
			var glow := Models.part(gun, Models.box(0.07, 0.07, 0.07), Models.toon(ELEMENTS[h.welem]["col"], false, 1.2), Vector3(0, 0.12, -0.05))
			glow.name = "Element"

# ------------------------------------------------------------------ what things are called and worth
static func rar_of(it: Dictionary) -> int:
	if String(it.get("t", "")) == "val":
		return int(VALUABLES.get(String(it.get("id", "")), {}).get("rar", 1))
	return clampi(int(it.get("rar", 0)), 0, Data.RARITY.size() - 1)

static func name_of(it: Dictionary) -> String:
	match String(it.get("t", "weapon")):
		"glove":
			var gd: Dictionary = Gear.ALL.get(String(it.get("id", "")), {})
			var r := rar_of(it)
			return "%s%s" % [(String(Data.RARITY[r]["name"]) + " ") if r > 0 else "", gd.get("name", it.get("id", "Glove"))]
		"val":
			return String(VALUABLES.get(String(it.get("id", "")), {}).get("name", "Trinket"))
	var uq := String(it.get("uq", ""))
	if uq != "" and UNIQUES.has(uq):
		return String(UNIQUES[uq]["name"])
	var base: String = Data.weapon_stats(String(it.get("wid", "rifle")), 0)["name"]
	var r2 := rar_of(it)
	var el := String(it.get("el", ""))
	return "%s%s%s" % [(String(Data.RARITY[r2]["name"]) + " ") if r2 > 0 else "", (String(ELEMENTS[el]["name"]) + " ") if ELEMENTS.has(el) else "", base]

## The colour that marks it: element first, then rarity.
static func col_of(it: Dictionary) -> Color:
	if String(it.get("t", "")) == "val":
		return VALUABLES.get(String(it.get("id", "")), {}).get("col", Color("ffd36a"))
	if String(it.get("uq", "")) != "":
		return Data.RARITY[Data.RARITY.size() - 1]["color"]
	return Data.RARITY[rar_of(it)]["color"]

static func el_col(it: Dictionary) -> Color:
	var el := String(it.get("el", ""))
	return ELEMENTS[el]["col"] if ELEMENTS.has(el) else col_of(it)

static func icon_of(it: Dictionary) -> String:
	match String(it.get("t", "weapon")):
		"glove": return Gear.icon_of(String(it.get("id", "")))
		"val": return "bond" if String(it.get("id", "")) == "soul_ember" else "gem"
	return String(it.get("wid", "rifle"))

## One line under the name: what it does.
static func sub_of(it: Dictionary) -> String:
	match String(it.get("t", "weapon")):
		"glove":
			var id := String(it.get("id", ""))
			if not Gear.ALL.has(id): return "Glove"
			return ("Active glove  ·  " if Gear.active(id) else "Passive glove  ·  ") + Gear.stat_text(id, rar_of(it))
		"val":
			return "Treasure  ·  sells for %d gems" % sell_price(it) if String(it.get("id", "")) != "soul_ember" else "Revives a kin at the Soul Shrine"
	var bits: Array = []
	var r: Dictionary = Data.RARITY[rar_of(it)]
	var dm := (float(r["dmg"]) * (UNIQUE_DMG if String(it.get("uq", "")) != "" else 1.0) - 1.0) * 100.0
	if dm > 0.5: bits.append("+%d%% damage" % int(round(dm)))
	var el := String(it.get("el", ""))
	if ELEMENTS.has(el): bits.append(String(ELEMENTS[el]["rider"]).split(":")[0])
	var uq := String(it.get("uq", ""))
	if UNIQUES.has(uq): bits.append(String(UNIQUES[uq]["perk"]))
	return "  ·  ".join(bits) if not bits.is_empty() else "Plain"

static func value(it: Dictionary) -> int:
	if it.is_empty():
		return 0
	match String(it.get("t", "weapon")):
		"glove": return GLOVE_VALUE[rar_of(it)]
		"val": return int(VALUABLES.get(String(it.get("id", "")), {}).get("value", 5))
	var v := float(WEAPON_VALUE[rar_of(it)])
	if String(it.get("el", "")) != "": v *= ELEMENT_VALUE
	if String(it.get("uq", "")) != "": v *= UNIQUE_VALUE
	return int(round(v))

## What the armory pays for it (a bit over half its worth).
static func sell_price(it: Dictionary) -> int:
	if String(it.get("t", "")) == "val":
		return value(it)
	return maxi(1, int(round(value(it) * 0.6)))

## Scrap from breaking it down at the armory, for upgrades.
static func scrap_of(it: Dictionary) -> int:
	return [1, 1, 2, 4, 7][rar_of(it)] + (2 if String(it.get("el", "")) != "" else 0) + (5 if String(it.get("uq", "")) != "" else 0)

# ------------------------------------------------------------------ rolling drops
## An element for a weapon found at this spot: the region's own element often, any element sometimes.
static func roll_element(rng: RandomNumberGenerator, biome := "") -> String:
	for el in ELEMENTS:
		if biome != "" and String(ELEMENTS[el]["biome"]) == biome and rng.randf() < 0.45:
			return el
	if rng.randf() < 0.12:
		return ELEMENTS.keys()[rng.randi() % ELEMENTS.size()]
	return ""

static func roll_unique(rng: RandomNumberGenerator) -> String:
	return UNIQUES.keys()[rng.randi() % UNIQUES.size()]

## A valuable by rarity tier (0 small, 1 good, 2 great).
static func roll_valuable(rng: RandomNumberGenerator, tier: int) -> String:
	var x := rng.randf()
	match tier:
		0: return "old_coin" if x < 0.8 else "sky_pearl"
		1: return "old_coin" if x < 0.35 else ("sky_pearl" if x < 0.8 else "kin_idol")
	return "sky_pearl" if x < 0.3 else ("kin_idol" if x < 0.7 else "crown_shard")

# ------------------------------------------------------------------ element riders
## Adds the weapon's element to one attack's hit options. Called once per attack.
static func rider(h, extra: Dictionary, dmg: float) -> void:
	var el: String = h.welem
	if el == "":
		return
	var mods: Dictionary = UNIQUES.get(String(h.wuniq), {}).get("mods", {})
	h.el_n += 1
	var n: int = h.el_n
	match el:
		"fire":
			extra["burn"] = maxf(float(extra.get("burn", 0.0)), 5.0 * float(mods.get("burn_x", 1.0)))
		"frost":
			extra["slow"] = maxf(float(extra.get("slow", 0.0)), 1.0)
			if n % int(mods.get("freeze_every", 5)) == 0:
				extra["root"] = maxf(float(extra.get("root", 0.0)), 0.6)
		"storm":
			if n % int(mods.get("chain_every", 4)) == 0 and not extra.has("fx_hit"):
				extra["fx_hit"] = [{"type": "chain", "count": 2, "first": 5.0, "dmg": dmg * 0.5, "color": "#fff27a", "skip_here": true}]
				extra["fx_ctx"] = {"slot": "weapon", "ability": "storm"}
		"venom":
			extra["burn"] = maxf(float(extra.get("burn", 0.0)), 3.0 * float(mods.get("burn_x", 1.0)))
			extra["slow"] = maxf(float(extra.get("slow", 0.0)), 0.35 * float(mods.get("slow_x", 1.0)))
		"void":
			extra["leech"] = float(mods.get("leech", 0.08))
