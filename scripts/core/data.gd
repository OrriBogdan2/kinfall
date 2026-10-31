extends Node
## Every tunable definition in the game lives here: classes, weapons, kin, monsters, crops.
## Distances are in tiles (1 unit), speeds in tiles per second, times in seconds.

const TEAM_COLORS := [Color("f2a24a"), Color("5ab0f0"), Color("e0607e"), Color("8fd16a"), Color("b48cf2"), Color("f0d45a"),
	Color("4ad8c8"), Color("ff8ad8"), Color("c8a07a"), Color("9ab4ff"), Color("ff6a4a"), Color("b8e05a"), Color("e6e6f0"),
	Color("7a8cff"), Color("ffb8a0"), Color("5ae08a"), Color("d07aff"), Color("ffe08a"), Color("6ac0ff"), Color("ff9a5a")]
## Every expedition has about this many hunters, however they're split into squads.
const MATCH_PLAYERS := 20

const CLASSES := {
	"light": {
		"name": "Light", "color": Color("c9bcff"), "hp": 124, "speed": 5.2, "dashes": 1, "mass": 0.85, "scale": 0.9, "hit_r": 0.35,
		"ex_dist": 5.0, "ex_time": 0.2, "ex_cd": 12.0, "glide_cap": 1.2,
		"weapon": "smg", "weapons": ["smg", "sniper", "twin_blades"],
		"desc": "Fast and fragile. The fastest dash, the longest glide, and hits throw you furthest.",
	},
	"medium": {
		"name": "Medium", "color": Color("9ee2a0"), "hp": 145, "speed": 5.0, "dashes": 1, "mass": 1.0, "scale": 1.0, "hit_r": 0.40,
		"ex_dist": 4.6, "ex_time": 0.2, "ex_cd": 13.0, "glide_cap": 1.0,
		"weapon": "rifle", "weapons": ["rifle", "burst_rifle", "longsword"],
		"desc": "The all-rounder: middle health, speed, dash and glide.",
	},
	"heavy": {
		"name": "Heavy", "color": Color("e6dbc4"), "hp": 193, "speed": 4.73, "dashes": 2, "mass": 1.35, "scale": 1.14, "hit_r": 0.50,
		"ex_dist": 4.2, "ex_time": 0.21, "ex_cd": 15.0, "glide_cap": 0.85,
		"weapon": "shotgun", "weapons": ["shotgun", "minigun", "greatsword"],
		"desc": "Slow and tough. Two short dashes, the most health, and very hard to push off a ledge.",
	},
}

## Fallback only: every real weapon lives in content/weapons.
const WEAPONS := {
	"rifle": {"name": "Rifle", "dmg": 3.87, "rate": 0.08, "speed": 110.0, "mag": 30, "reload": 1.8,
		"kb": 0.8, "spread": 0.035, "range": 9.5, "sfx": "rifle", "color": Color("d9ff66"), "size": 0.12},
}

## Weapons found out on the islands: any weapon with a rarity on top, always better than what you
## brought, and only yours until the expedition ends.
const RARITY := [
	{"name": "Common", "color": Color("d6d2c8"), "dmg": 1.0, "mag": 1.0, "reload": 1.0, "rate": 1.0},
	{"name": "Fine", "color": Color("8fe0a0"), "dmg": 1.15, "mag": 1.15, "reload": 0.92, "rate": 0.95},
	{"name": "Rare", "color": Color("6ab8ff"), "dmg": 1.3, "mag": 1.3, "reload": 0.85, "rate": 0.9},
	{"name": "Epic", "color": Color("c08aff"), "dmg": 1.38, "mag": 1.4, "reload": 0.78, "rate": 0.9},
	{"name": "Legendary", "color": Color("ffb64a"), "dmg": 1.5, "mag": 1.5, "reload": 0.7, "rate": 0.86},
]

## A weapon's stats at a rarity. "short" is the plain name for the ability bar.
## Every weapon: the ones in content/weapons (the source of truth), plus any only defined here.
func weapon_ids() -> Array:
	var ids: Array = Content.ids("weapons")
	for k in WEAPONS:
		if not ids.has(k): ids.append(k)
	return ids

func weapon_stats(wid: String, rar := 0) -> Dictionary:
	var wd := Content.weapon(wid)
	var w: Dictionary = wd.primary.duplicate() if wd else WEAPONS.get(wid, WEAPONS["rifle"]).duplicate()
	var r: Dictionary = RARITY[clampi(rar, 0, RARITY.size() - 1)]
	w["short"] = String(w["name"]).split(" ")[0]
	if rar > 0:
		w["name"] = "%s %s" % [r["name"], w["name"]]
	w["dmg"] = float(w["dmg"]) * float(r["dmg"])
	if w.has("combo_dmg"):
		w["combo_dmg"] = (w["combo_dmg"] as Array).map(func(x): return float(x) * float(r["dmg"]))
	if w.has("charged_dmg"):
		w["charged_dmg"] = float(w["charged_dmg"]) * float(r["dmg"])
	w["mag"] = maxi(int(w["mag"]) + (1 if rar > 0 else 0), int(round(int(w["mag"]) * float(r["mag"]))))
	w["reload"] = float(w["reload"]) * float(r["reload"])
	w["rate"] = float(w["rate"]) * float(r["rate"])
	w["rar"] = rar
	return w

## Rarity of a found weapon. Better places and harder tiers lean higher.
func roll_rarity(r: RandomNumberGenerator, bonus := 0) -> int:
	var x := r.randf()
	var rar := 1
	if x > 0.6: rar = 2
	if x > 0.88: rar = 3
	if x > 0.98: rar = 4
	return clampi(rar + bonus, 1, RARITY.size() - 1)

## The class you play and the weapon you carry are your whole loadout: left and right click come
## from the weapon, Q, E and R from the kin you bring.
func class_of_save() -> String:
	var c: String = Save.d.get("cls", "medium")
	return c if CLASSES.has(c) else "medium"

## The saved weapon if the class can carry it, else the class's default.
func weapon_for(cls: String, w: String) -> String:
	var cd: Dictionary = CLASSES.get(cls, CLASSES["medium"])
	return w if (cd["weapons"] as Array).has(w) else String(cd["weapon"])


## The soundtrack. Tracks join your music list the first time you hear them; some only play in
## rare places or moments.
const MUSIC := {
	"title": {"name": "Kinfall", "hint": "The title screen."},
	"home_day": {"name": "Hearthwind", "hint": "Your home island by day."},
	"home_night": {"name": "Hearthwind (Night)", "hint": "Your home island after dark."},
	"orchard": {"name": "Orchard Light", "hint": "Cross the bridge to Orchard Isle."},
	"meadow": {"name": "Tag in the Meadow", "hint": "Cross the bridge to Kin Meadow."},
	"summit": {"name": "Lookout Wind", "hint": "Cross the bridge to Lookout Peak."},
	"match": {"name": "Into the Isles", "hint": "Head out on an expedition."},
	"hollow": {"name": "The Hollow", "hint": "Brave the Hollow."},
	"hub": {"name": "Market Square", "hint": "Visit the town."},
	"guild": {"name": "Banners", "hint": "Visit a guild isle."},
	"lullaby": {"name": "Kin Lullaby", "hint": "Watch a kin evolve."},
}

## One perk per loadout.
## Perks are found during an expedition, never brought from home: a shrine, a rare chest or a
## boss offers you three and you keep one (Match.offer_perks). They stack up to "max" and last
## until the expedition ends, extracted or not. stats feed Hunter.gear_stat like gear does
## (speed, dmg, armor, cdr, heat, glide_speed); the rest are read by name with Hunter.perk_n().
const PERKS := {
	"quickhands": {"name": "Quick Hands", "desc": "Reload 30% faster.", "icon": "medkit", "col": Color("ffd27a"), "max": 1},
	"secondwind": {"name": "Second Wind", "desc": "One extra dash charge.", "icon": "dash", "col": Color("bfe6ff"), "max": 1},
	"featherfall": {"name": "Featherfall", "desc": "Your glider lasts 60% longer.", "icon": "updraft", "col": Color("cfeaff"), "max": 1},
	"scavenger": {"name": "Scavenger", "desc": "Gems you pick up are worth 25% more.", "icon": "gem", "col": Color("f2c84a"), "max": 2},
	"toughskin": {"name": "Tough Skin", "desc": "+15 max health, healed right away.", "icon": "heart", "col": Color("8fe0a0"), "max": 3},
	"overcharge": {"name": "Overcharge", "desc": "Your bond ultimate charges 30% faster.", "icon": "bond", "col": Color("ffd23f"), "max": 1},
	"keen": {"name": "Keen Edge", "desc": "8% more damage.", "icon": "burst", "col": Color("ff8a6a"), "max": 3, "stats": {"dmg": 0.08}},
	"fleet": {"name": "Fleet Foot", "desc": "6% faster on foot.", "icon": "jump", "col": Color("8fd16a"), "max": 2, "stats": {"speed": 0.06}},
	"plating": {"name": "Plating", "desc": "+20 max armor.", "icon": "fortify", "col": Color("dfe9f7"), "max": 2, "stats": {"armor": 20.0}},
	"focus": {"name": "Clear Mind", "desc": "Abilities recharge 12% faster.", "icon": "pulse", "col": Color("d07aff"), "max": 2, "stats": {"cdr": 0.12}},
	"tailwind": {"name": "Tailwind", "desc": "Glide 15% faster.", "icon": "gust", "col": Color("9fe8ff"), "max": 1, "stats": {"glide_speed": 0.15}},
	"remedy": {"name": "Remedy", "desc": "Tonics heal 40% more.", "icon": "tonic", "col": Color("8fe0a0"), "max": 1},
}

## Bot hunter difficulty. "auto" (the default) picks one from the run tier and how experienced you
## are; admins can force one in Settings > Gameplay or the admin panel (F1).
##   skill: aim lead/accuracy and how often they think   react: seconds before they fire on a new target
##   dmg: their damage   fire: how much of the time they keep the trigger down
##   abil: how readily they use abilities and kin   aggro: how far they chase and how hard they press
const BOT_DIFF := {
	"easy": {"name": "Easy", "skill": 0.28, "react": 0.75, "dmg": 0.65, "fire": 0.5, "abil": 0.3, "aggro": 0.6},
	"medium": {"name": "Medium", "skill": 0.5, "react": 0.45, "dmg": 0.82, "fire": 0.7, "abil": 0.55, "aggro": 0.8},
	"hard": {"name": "Hard", "skill": 0.72, "react": 0.28, "dmg": 0.95, "fire": 0.85, "abil": 0.8, "aggro": 0.95},
	"expert": {"name": "Expert", "skill": 0.92, "react": 0.16, "dmg": 1.05, "fire": 1.0, "abil": 1.0, "aggro": 1.1},
}
const BOT_ORDER := ["easy", "medium", "hard", "expert"]

## Which difficulty "auto" means for a run: the tier sets the base (Meadow easy, Dusk Isles medium,
## the Hollow hard) and lots of successful extractions push it up one step. The tutorial is always easy.
static func auto_bot_diff(tier: int, extracts: int, tutorial := false) -> String:
	if tutorial:
		return "easy"
	var i := clampi(tier, 0, 2)
	if extracts >= 12 * (i + 1):
		i += 1
	return BOT_ORDER[clampi(i, 0, BOT_ORDER.size() - 1)]

const SIGS := {
	"cloak": {"name": "Cloak", "cd": 14.0, "desc": "Vanish for 3s and move 35% faster. Firing reveals you."},
	"mend": {"name": "Mend", "cd": 16.0, "desc": "Heal 35 to you, nearby teammates and kin. Nearby revives jump halfway."},
	"fortify": {"name": "Fortify", "cd": 16.0, "desc": "A 60 point shield for 5s. Nothing can knock you back."},
}

## Kin species. These are the built-in defaults; every content/kin/*.json file is merged over them
## (or adds a new species) when the game starts, so new kin need no code.
## skill: what Q does while the kin is out. shoulder: what you get while it rides on you.
var KIN := {
	"cindle": {"name": "Vespyx", "type": "venom", "color": Color("4a2f5c"), "belly": Color("d8c6e8"),
		"hp": 80.0, "dmg": 9.0, "speed": 6.8, "range": 1.3, "ears": "flame",
		"skill": "fireball", "shoulder": "kindle",
		"traits": {"bravery": 0.75, "loyalty": 0.5, "temper": 0.7, "curiosity": 0.5},
		"voice": "hot-headed, eager, talks in short bursts"},
	"puddlet": {"name": "Prismander", "type": "prism", "color": Color("f0a6d6"), "belly": Color("ffe2f1"),
		"hp": 95.0, "dmg": 7.0, "speed": 6.0, "range": 1.3, "ears": "fin",
		"skill": "wave", "shoulder": "spring",
		"traits": {"bravery": 0.45, "loyalty": 0.85, "temper": 0.2, "curiosity": 0.6},
		"voice": "gentle, worried about you, a little formal"},
	"burrlet": {"name": "Mycroll", "type": "spore", "color": Color("6b4a3c"), "belly": Color("e9d6bd"),
		"hp": 90.0, "dmg": 8.0, "speed": 6.2, "range": 1.3, "ears": "leaf",
		"skill": "snare", "shoulder": "briar",
		"traits": {"bravery": 0.55, "loyalty": 0.6, "temper": 0.4, "curiosity": 0.8},
		"voice": "curious and odd, notices small things"},
	"zapple": {"name": "Echolop", "type": "echo", "color": Color("4a5aa8"), "belly": Color("c9d2ff"),
		"hp": 70.0, "dmg": 8.0, "speed": 7.6, "range": 1.3, "ears": "bolt",
		"skill": "chain", "shoulder": "charge",
		"traits": {"bravery": 0.65, "loyalty": 0.4, "temper": 0.6, "curiosity": 0.9},
		"voice": "hyper, easily distracted, loves winning"},
	"pebbit": {"name": "Gravadillo", "type": "gravity", "color": Color("3c4058"), "belly": Color("8e8aa8"),
		"hp": 120.0, "dmg": 11.0, "speed": 5.4, "range": 1.4, "ears": "horn",
		"skill": "slam", "shoulder": "bedrock",
		"traits": {"bravery": 0.9, "loyalty": 0.7, "temper": 0.3, "curiosity": 0.2},
		"voice": "slow, steady, few words, deeply loyal once trust is earned"},
	"wisplet": {"name": "Lunowl", "type": "lunar", "color": Color("d9d4f2"), "belly": Color("fff8e6"),
		"hp": 70.0, "dmg": 7.0, "speed": 8.0, "range": 1.3, "ears": "wisp",
		"skill": "gust", "shoulder": "updraft",
		"traits": {"bravery": 0.35, "loyalty": 0.55, "temper": 0.5, "curiosity": 0.7},
		"voice": "airy, teasing, dramatic"},
}

## Things a kin can wear. Bought at the stall, put on from the kin's card, worn into matches too.
const ACCS := {
	"bell": {"name": "Little bell", "price": 25, "col": Color("f2c84a")},
	"bow": {"name": "Ribbon bow", "price": 30, "col": Color("ff7aa8")},
	"leafhat": {"name": "Leaf hat", "price": 35, "col": Color("5aa84a")},
	"scarf": {"name": "Cozy scarf", "price": 40, "col": Color("d9604a")},
	"crown": {"name": "Flower crown", "price": 45, "col": Color("ffd0e8")},
	"goggles": {"name": "Flight goggles", "price": 55, "col": Color("8b6d52")},
	"cape": {"name": "Hero cape", "price": 70, "col": Color("5a7ae0")},
	"tophat": {"name": "Tiny top hat", "price": 80, "col": Color("2b2a33")},
}

func _init() -> void:
	load_kin_content()

## Reads content/kin/*.json into KIN. A file with a new id adds a new species.
func load_kin_content() -> void:
	for id in Content.ids("kin"):
		var kd := Content.kin(id)
		if kd == null:
			continue
		var sp: Dictionary = kd.to_species()
		var base: Dictionary = KIN.get(id, {})
		sp["voice"] = String(Content._load("kin", id).get("voice", base.get("voice", "friendly")))
		KIN[id] = sp

## Species anyone can meet in the wild, pick as a starter or see on a rival: everything but the rare
## kin (content/kin/*.json "rare": true), which only ever hatch from a boss's Rare Egg.
func common_kin() -> Array:
	return KIN.keys().filter(func(k): return not KIN[k].get("rare", false))

func is_rare(sp_id: String) -> bool:
	return bool(KIN.get(sp_id, {}).get("rare", false))

## What a species' egg is called ("Venom Egg"), from content/kin/<id>.json "egg".
func egg_name(sp_id: String) -> String:
	var sp: Dictionary = KIN.get(sp_id, {})
	var e: Dictionary = sp.get("egg", {})
	if e.has("name"):
		return String(e["name"])
	return "%s Egg" % String(sp.get("type", "Kin")).capitalize()

func egg_info(sp_id: String) -> Dictionary:
	var sp: Dictionary = KIN.get(sp_id, {})
	var e: Dictionary = sp.get("egg", {}).duplicate()
	e["name"] = egg_name(sp_id)
	return e

## Old single skills, kept for older saves and tips. Kin now use content/abilities.
const KIN_SKILLS := {
	"fireball": {"name": "Fireball", "cd": 6.0, "desc": "A fireball that explodes and sets foes burning."},
	"wave": {"name": "Tidal Wave", "cd": 7.0, "desc": "A wave that shoves and slows everything in front of it."},
	"snare": {"name": "Bramble Snare", "cd": 8.0, "desc": "Roots every foe in an area for 1.6s."},
	"chain": {"name": "Chain Bolt", "cd": 6.0, "desc": "Lightning that jumps between three foes."},
	"slam": {"name": "Boulder Slam", "cd": 8.0, "desc": "Leaps onto the spot and blasts foes away. Great near edges."},
	"gust": {"name": "Gust", "cd": 6.0, "desc": "A burst of wind that hurls nearby foes outward."},
}

const SHOULDER := {
	"kindle": {"name": "Toxin", "desc": "Your shots poison targets."},
	"spring": {"name": "Glimmer", "desc": "You heal 3 HP per second."},
	"briar": {"name": "Mycelium", "desc": "Your shots slow targets."},
	"charge": {"name": "Tempo", "desc": "You fire and reload 20% faster."},
	"bedrock": {"name": "Anchor", "desc": "You take 15% less damage and half the knockback."},
	"updraft": {"name": "Moonstep", "desc": "One extra dash charge."},
}

const MOBS := {
	"skitter": {"name": "Skitter", "hp": 34.0, "speed": 5.2, "dmg": 9.0, "range": 1.2, "windup": 0.55, "cd": 1.3,
		"r": 0.45, "gems": 2, "color": Color("7b5ea8"), "attack": "lunge"},
	"spitter": {"name": "Spitter", "hp": 44.0, "speed": 2.2, "dmg": 11.0, "range": 8.0, "windup": 0.8, "cd": 2.2,
		"r": 0.55, "gems": 3, "color": Color("4f9e6e"), "attack": "spit"},
	"brute": {"name": "Brute", "hp": 170.0, "speed": 3.0, "dmg": 24.0, "range": 2.2, "windup": 1.05, "cd": 2.6,
		"r": 0.9, "gems": 9, "color": Color("8a5a48"), "attack": "slam", "stag": true},
	"bomber": {"name": "Puffbomb", "hp": 26.0, "speed": 4.4, "dmg": 16.0, "range": 1.7, "windup": 1.0, "cd": 1.0,
		"r": 0.5, "gems": 2, "color": Color("e07a3a"), "attack": "fuse", "slam_r": 2.5},
	"sentinel": {"name": "Sentinel", "hp": 70.0, "speed": 0.0, "dmg": 8.0, "range": 10.0, "windup": 0.95, "cd": 2.6,
		"r": 0.55, "gems": 4, "color": Color("5ab0c8"), "attack": "volley", "stag": true},
	"glimmer": {"name": "Glimmerkin", "hp": 110.0, "speed": 5.9, "dmg": 0.0, "range": 0.0, "windup": 1.0, "cd": 99.0,
		"r": 0.45, "gems": 22, "color": Color("ffd25a"), "attack": "none", "flee": true, "stag": true},
	"warden": {"name": "The Warden", "hp": 820.0, "speed": 3.3, "dmg": 30.0, "range": 2.8, "windup": 0.95, "cd": 2.1,
		"r": 1.3, "gems": 30, "color": Color("5a4a7a"), "attack": "slam", "slam_r": 3.3, "stag": true},
	# lair bosses (scripts/match/boss.gd runs them; Lairs wakes them): each drops a Rare Egg of its own kin
	"colossus": {"name": "The Stone Colossus", "hp": 1500.0, "speed": 2.5, "dmg": 26.0, "range": 3.2, "windup": 1.1, "cd": 1.9,
		"r": 1.6, "gems": 40, "color": Color("7d7468"), "attack": "boss", "slam_r": 3.8, "stag": true, "stag_k": 0.04, "boss": true,
		"egg": "cairnback", "enrage": 150.0},
	"serpent": {"name": "Stormcoil, the Sky Serpent", "hp": 1250.0, "speed": 5.2, "dmg": 22.0, "range": 10.0, "windup": 0.95, "cd": 1.5,
		"r": 1.15, "gems": 40, "color": Color("3f86b8"), "attack": "boss", "stag": true, "stag_k": 0.04, "boss": true,
		"egg": "zephyrak", "enrage": 150.0},
	"brood": {"name": "The Brood Mother", "hp": 1350.0, "speed": 2.3, "dmg": 18.0, "range": 9.0, "windup": 1.0, "cd": 1.7,
		"r": 1.55, "gems": 40, "color": Color("8a9a3a"), "attack": "boss", "stag": true, "stag_k": 0.04, "boss": true,
		"egg": "hivara", "enrage": 150.0},
	# a lair's ward stones: break all three (guards come out as you do) and its seal fails
	"ward": {"name": "Ward Stone", "hp": 150.0, "speed": 0.0, "dmg": 0.0, "range": 0.0, "windup": 1.0, "cd": 999.0,
		"r": 0.7, "gems": 3, "color": Color("8fd8ff"), "attack": "none", "ward": true},
}
## The lair bosses, in the order generated maps hand them out.
const BOSSES := ["colossus", "serpent", "brood"]

## Crops grow on the farm while you play matches. Each becomes something for your next match.
const CROPS := {
	"emberberry": {"name": "Emberberry", "grow": 2, "color": Color("ff6a4a"), "price": 20,
		"use": "treat_power", "desc": "Treat: your kin deals 25% more damage next match."},
	"tidebloom": {"name": "Tidebloom", "grow": 1, "color": Color("5ab8f0"), "price": 12,
		"use": "tonic", "desc": "Brews 2 tonics. Key 1 in a match heals 45."},
	"sunroot": {"name": "Sunroot", "grow": 2, "color": Color("f2c84a"), "price": 18,
		"use": "treat_hardy", "desc": "Treat: your kin has 40% more health next match."},
	"mindmint": {"name": "Mindmint", "grow": 3, "color": Color("8fe0b0"), "price": 25,
		"use": "treat_calm", "desc": "Treat: +12 trust. Calm kin follow risky orders."},
	"puffcorn": {"name": "Puffcorn", "grow": 1, "color": Color("f6e3a8"), "price": 8,
		"use": "snack", "desc": "Snack: your partner gets +4 trust right away. Quick and cheap."},
	"glowcap": {"name": "Glowcap", "grow": 2, "color": Color("b48cff"), "price": 30, "weight": 0.6,
		"use": "treat_xp", "desc": "Treat: your partner learns half again as much next match."},
	"starfruit": {"name": "Starfruit", "grow": 4, "color": Color("fff07a"), "price": 60, "weight": 0.3,
		"use": "levelup", "desc": "Rare. Your partner gains a level right away (once a day)."},
}

## Furniture for decorating the insides of buildings. size is in floor tiles (w, d); "walk" lets you
## walk over it (rugs). Prices are in gems at the stall or the decorating catalog.
const FURN := {
	"bed": {"name": "Bed", "price": 60, "size": [2, 3]},
	"kin_bed": {"name": "Kin basket", "price": 25, "size": [1, 1]},
	"table": {"name": "Table", "price": 40, "size": [2, 1]},
	"chair": {"name": "Chair", "price": 15, "size": [1, 1]},
	"stool": {"name": "Stool", "price": 10, "size": [1, 1]},
	"rug": {"name": "Rug", "price": 30, "size": [3, 2], "walk": true},
	"rug_round": {"name": "Round rug", "price": 30, "size": [2, 2], "walk": true},
	"lamp": {"name": "Floor lamp", "price": 25, "size": [1, 1]},
	"plant": {"name": "Potted plant", "price": 15, "size": [1, 1]},
	"big_plant": {"name": "Big plant", "price": 35, "size": [1, 1]},
	"shelf": {"name": "Bookshelf", "price": 45, "size": [2, 1]},
	"chest": {"name": "Chest", "price": 30, "size": [1, 1]},
	"stove": {"name": "Stove", "price": 55, "size": [1, 1]},
	"fireplace": {"name": "Fireplace", "price": 90, "size": [2, 1]},
	"wardrobe": {"name": "Wardrobe", "price": 50, "size": [2, 1]},
	"fishbowl": {"name": "Fish bowl", "price": 35, "size": [1, 1]},
	"easel": {"name": "Painting", "price": 40, "size": [1, 1]},
	"trophy": {"name": "Trophy stand", "price": 70, "size": [1, 1]},
	"cushion": {"name": "Floor cushion", "price": 12, "size": [1, 1], "walk": true},
	"toy_ball": {"name": "Kin toy", "price": 8, "size": [1, 1], "walk": true},
}

## Rooms you can go into: floor size in tiles and what's in them to begin with.
const ROOMS := {
	"house": {"name": "Your house", "w": 10, "d": 8, "floor": Color("8f6644"), "wall": Color("efe2c8"),
		"start": [["bed", 1, 1, 0], ["rug", 4, 4, 0], ["table", 6, 1, 0], ["chair", 6, 2, 0], ["lamp", 0, 6, 0], ["stove", 9, 1, 0], ["kin_bed", 8, 6, 0], ["plant", 9, 6, 0]]},
	"cottage": {"name": "Kin Cottage", "w": 8, "d": 6, "floor": Color("86603f"), "wall": Color("e8d8b8"),
		"start": [["kin_bed", 1, 1, 0], ["kin_bed", 3, 1, 0], ["rug_round", 4, 3, 0], ["toy_ball", 6, 4, 0]]},
	"cottage2": {"name": "Meadow Cottage", "w": 8, "d": 6, "floor": Color("86603f"), "wall": Color("dfe8c8"),
		"start": [["kin_bed", 1, 1, 0], ["kin_bed", 6, 1, 0], ["cushion", 3, 3, 0], ["plant", 7, 4, 0]]},
}

## Farming: a watered plant grows a stage after this long at home (half in the greenhouse).
const WATER_TIME := 90.0

## A random seed for loot, rare crops less often.
func pick_seed(r: RandomNumberGenerator = null) -> String:
	var total := 0.0
	for k in CROPS: total += float(CROPS[k].get("weight", 1.0))
	var x := (r.randf() if r else randf()) * total
	for k in CROPS:
		x -= float(CROPS[k].get("weight", 1.0))
		if x <= 0.0: return k
	return CROPS.keys()[0]

const KIN_NAMES := ["Pip", "Mochi", "Bramble", "Sorrel", "Tumble", "Fig", "Juniper", "Biscuit", "Nettle", "Wren", "Sprout", "Ember", "Clove", "Pebble", "Marlo", "Quill", "Dusk", "Taffy", "Rune", "Kip"]
const BOT_NAMES := ["Vexa", "Moss", "Tarn", "Juno", "Rook", "Kestrel", "Nim", "Sable", "Orin", "Lux", "Bryn", "Cato", "Ivy", "Rho", "Wick", "Zed", "Fen", "Mara"]

## Expedition tiers: deeper islands are harder and richer, and in the Hollow your partner can be lost.
const TIERS := [
	{"name": "The Meadow", "desc": "Gentle islands. Your kin are always safe here: lose your loot, never your kin.",
		"mob": 1.0, "loot": 1.0, "kin_lvl": [1, 3], "unlock": 0, "risk_kin": false, "kin_drop": false, "loose_capture": false, "lives": 1,
		"biome": {"top": Color("5f8d45"), "top2": Color("4a7538"), "side": Color("8b6d52"), "deep": Color("3a3140"), "leaf": Color("5a9a4f")},
		"sky": Color("10131f"), "ambient": Color("b9c4e6"), "sun": Color("fff1dc"), "clouds": [Color(0.06, 0.07, 0.13), Color(0.22, 0.24, 0.38)]},
	{"name": "Dusk Isles", "desc": "Tougher monsters, more loot, rarer kin. Kin you have on you drop into your deathbox when you die, and anyone can loot them. Kin out of your hands escape.",
		"mob": 1.45, "loot": 1.75, "kin_lvl": [2, 5], "unlock": 2, "risk_kin": true, "kin_drop": true, "loose_capture": false, "lives": 1,
		"biome": {"top": Color("56688a"), "top2": Color("465576"), "side": Color("6d5a74"), "deep": Color("2a2440"), "leaf": Color("8a6fb8")},
		"sky": Color("150f22"), "ambient": Color("c9b4e6"), "sun": Color("ffc9a8"), "clouds": [Color(0.09, 0.05, 0.14), Color(0.32, 0.2, 0.4)]},
	{"name": "The Hollow", "desc": "Brutal and rich. Kin on you drop into your deathbox and can be looted, and kin out of your hands can be captured (hold the interact key for 3s).",
		"mob": 2.0, "loot": 2.75, "kin_lvl": [4, 8], "unlock": 5, "risk_kin": true, "kin_drop": true, "loose_capture": true, "lives": 1,
		"biome": {"top": Color("4f6b5e"), "top2": Color("3d5650"), "side": Color("5a4a44"), "deep": Color("1e1a22"), "leaf": Color("c25a4a")},
		"sky": Color("0d0b10"), "ambient": Color("d0a0a0"), "sun": Color("ffb090"), "clouds": [Color(0.07, 0.03, 0.04), Color(0.3, 0.12, 0.12)]},
]

## Home islands beyond the first one. Build a bridge to reach them. Rects are in home grid tiles.
const ISLES := {
	"orchard": {"name": "Orchard Isle", "cost": 100, "need": 1, "c": Vector2(60, 38), "r": Vector2(6.8, 5.6),
		"bridge": [46, 38, 56, 39], "sign": Vector2(49.5, 36.8), "desc": "A sunny isle with room for a greenhouse."},
	"meadow": {"name": "Kin Meadow", "cost": 140, "need": 2, "c": Vector2(12, 30), "r": Vector2(7.2, 6.2),
		"bridge": [17, 30, 26, 31], "sign": Vector2(25.2, 29.0), "desc": "Open fields where kin love to play. Room for a cottage and a training yard."},
	"summit": {"name": "Lookout Peak", "cost": 220, "need": 4, "c": Vector2(45, 9), "r": Vector2(7.6, 5.6),
		"bridge": [44, 12, 45, 24], "sign": Vector2(46.8, 23.6), "desc": "A high rock for a vault and a trophy hall."},
}

## Buildings you can buy for your islands. "rect" is the tile footprint [x0, z0, x1, z1].
const BUILDINGS := {
	"workshop": {"name": "Workshop", "isle": "main", "cost": 90, "rect": [28, 26, 30, 28],
		"desc": "Tune your glider. You glide 50% longer on expeditions."},
	"cottage": {"name": "Kin Cottage", "isle": "main", "cost": 110, "rect": [27, 35, 29, 36],
		"desc": "Kin who stay home rest here and gain 2 trust after every expedition."},
	"greenhouse": {"name": "Greenhouse", "isle": "orchard", "cost": 150, "rect": [58, 34, 61, 36],
		"desc": "Four more plots. Crops planted here grow twice as fast."},
	"cottage2": {"name": "Meadow Cottage", "isle": "meadow", "cost": 140, "rect": [8, 26, 10, 27],
		"desc": "Kin who stay home gain 2 more trust after every expedition."},
	"dojo": {"name": "Training Yard", "isle": "meadow", "cost": 180, "rect": [11, 32, 14, 34],
		"desc": "Kin who stay home gain 40 XP after every expedition."},
	"vault": {"name": "Vault", "isle": "summit", "cost": 220, "rect": [41, 7, 43, 8],
		"desc": "If you go down, you still keep a third of the gems you were carrying."},
	"board": {"name": "Challenge House", "isle": "main", "cost": 0, "rect": [31, 22, 33, 23], "free": true,
		"desc": "Challenges to take on, their rewards, and what they unlock at the market."},
	"ransom": {"name": "Ransom House", "isle": "main", "cost": 0, "rect": [42, 39, 44, 40], "free": true,
		"desc": "Old Pell's place. Kin left behind on expeditions end up here, and it's where you deal with rivals who took yours."},
	"hall": {"name": "Trophy Hall", "isle": "summit", "cost": 120, "rect": [47, 6, 49, 8],
		"desc": "Keeps your records and every kin you've brought home."},
	"armory": {"name": "Armory", "isle": "main", "cost": 40, "rect": [45, 25, 47, 26],
		"desc": "Stores the weapons and gloves you bring home. Pick what you take on your next expedition, sell or salvage the rest, and get a bigger backpack."},
	"shrine": {"name": "Soul Shrine", "isle": "main", "cost": 150, "rect": [49, 35, 50, 36], "needs_ember": true,
		"desc": "Lit by a Soul Ember. Keeps the souls of kin buried in the graveyard, and can bring one back (a little different)."},
}

const MATCH := {
	"length": 360.0,       # seconds until the islands fall
	"portal_open": 150.0,  # first exit portals open this many seconds in
	"extract_time": 4.0,   # seconds standing in an exit's circle to leave; a hit from another hunter resets it
	"revive_time": 3.0,
	"kin_revive_time": 5.0,
	"bleed": 2.5,          # downed health lost per second
	"down_hp": 100.0,      # so about 40 seconds downed before you bleed out
}
