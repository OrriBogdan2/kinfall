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
		"name": "Light", "hp": 90, "speed": 6.3, "dashes": 3, "mass": 0.9, "scale": 0.9,
		"sig": "cloak", "weapon": "stinger", "weapons": ["stinger", "pulse", "rail"],
		"desc": "Fast and fragile. Three dashes and a cloak to slip out of fights.",
	},
	"medium": {
		"name": "Medium", "hp": 115, "speed": 5.4, "dashes": 2, "mass": 1.0, "scale": 1.0,
		"sig": "mend", "weapon": "repeater", "weapons": ["repeater", "pulse", "rocket", "rail"],
		"desc": "The all-rounder. Heals the team and its kin, and speeds up revives.",
	},
	"heavy": {
		"name": "Heavy", "hp": 155, "speed": 4.7, "dashes": 1, "mass": 1.45, "scale": 1.14,
		"sig": "fortify", "weapon": "thumper", "weapons": ["thumper", "pulse", "rocket"],
		"desc": "Slow and tough. Grenades that blast people off edges, and a shield nothing can push.",
	},
}

const WEAPONS := {
	"stinger": {"name": "Stinger SMG", "dmg": 4.6, "rate": 0.085, "speed": 24.0, "mag": 26, "reload": 1.3,
		"kb": 0.8, "spread": 0.07, "range": 10.0, "sfx": "smg", "color": Color("ffe08a"), "size": 0.09},
	"repeater": {"name": "Repeater", "dmg": 10.0, "rate": 0.21, "speed": 27.0, "mag": 12, "reload": 1.2,
		"kb": 2.4, "spread": 0.015, "range": 12.0, "sfx": "rifle", "color": Color("bfe6ff"), "size": 0.12},
	"thumper": {"name": "Thumper", "dmg": 20.0, "rate": 0.8, "speed": 14.0, "mag": 4, "reload": 1.7,
		"kb": 0.0, "spread": 0.0, "range": 9.0, "sfx": "thump", "color": Color("ff9a4a"), "size": 0.22,
		"boom": 2.1, "boom_kb": 9.5},
	"rail": {"name": "Rail Rifle", "dmg": 24.0, "rate": 0.9, "speed": 46.0, "mag": 4, "reload": 1.8,
		"kb": 3.5, "spread": 0.0, "range": 18.0, "sfx": "rifle", "color": Color("9af0ff"), "size": 0.1},
	"rocket": {"name": "Rocket Launcher", "dmg": 15.0, "rate": 0.65, "speed": 17.0, "mag": 3, "reload": 1.7,
		"kb": 0.0, "spread": 0.0, "range": 11.0, "sfx": "thump", "color": Color("ff7a5a"), "size": 0.2,
		"boom": 1.8, "boom_kb": 8.0},
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
	var w: Dictionary = wd.primary.duplicate() if wd else WEAPONS.get(wid, WEAPONS["repeater"]).duplicate()
	var r: Dictionary = RARITY[clampi(rar, 0, RARITY.size() - 1)]
	w["short"] = String(w["name"]).split(" ")[0]
	if rar > 0:
		w["name"] = "%s %s" % [r["name"], w["name"]]
	w["dmg"] = float(w["dmg"]) * float(r["dmg"])
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

## Heroes: three per weight class. Each has a passive, an E ability and an R ultimate that charges
## as you deal damage, plus a right-click ability of their own. Your kin (C to throw, Q, shoulder) stays the same whoever you play.
const HEROES := {
	"veil": {"name": "Veil", "cls": "light", "weapon": "stinger", "e": "cloak", "r": "vanish", "s": "shadowstep", "color": Color("c9bcff"),
		"role": "Slippery scout", "passive": "Your first shot after leaving cloak always crits."},
	"nyx": {"name": "Nyx", "cls": "light", "weapon": "stinger", "e": "blink", "r": "dance", "s": "bolas", "color": Color("b06ae0"),
		"role": "Blink assassin", "passive": "Knocking down a hunter refreshes Blink."},
	"kestrel": {"name": "Kestrel", "cls": "light", "weapon": "rail", "e": "tether", "r": "skypierce", "s": "divehawk", "color": Color("6ad0e0"),
		"role": "Long-range sniper", "passive": "Shots from more than 9 tiles away deal 25% more damage."},
	"sage": {"name": "Sage", "cls": "medium", "weapon": "repeater", "e": "mend", "r": "sanctuary", "s": "breeze", "color": Color("9ee2a0"),
		"role": "Healer", "passive": "Revives teammates 30% faster."},
	"marlow": {"name": "Marlow", "cls": "medium", "weapon": "repeater", "e": "hook", "r": "anchor", "s": "haymaker", "color": Color("e0b05a"),
		"role": "Hook and slam", "passive": "Hooked foes are slowed for 2 seconds."},
	"pyra": {"name": "Pyra", "cls": "medium", "weapon": "rocket", "e": "rocketjump", "r": "barrage", "s": "satchel", "color": Color("ff7a5a"),
		"role": "Rocket jumper", "passive": "Your blasts knock foes 20% further."},
	"bastion": {"name": "Bastion", "cls": "heavy", "weapon": "thumper", "e": "fortify", "r": "bulwark", "s": "brightshield", "color": Color("e6dbc4"),
		"role": "Unmovable wall", "passive": "Takes 10% less damage while above half health."},
	"tusk": {"name": "Tusk", "cls": "heavy", "weapon": "thumper", "e": "ram", "r": "quake", "s": "cleave", "color": Color("c08a5a"),
		"role": "Charging brawler", "passive": "Hitting someone with Ram refunds half its cooldown."},
	"halo": {"name": "Halo", "cls": "heavy", "weapon": "thumper", "e": "dome", "r": "well", "s": "binding", "color": Color("f2d47a"),
		"role": "Bubble protector", "passive": "Allies inside your dome heal 4 health per second."},
}

const ABIL := {
	"cloak": {"name": "Cloak", "cd": 14.0, "desc": "Vanish for 3s and move 35% faster. Firing reveals you."},
	"mend": {"name": "Mend", "cd": 16.0, "desc": "Heal 35 to you, nearby teammates and kin. Nearby revives jump halfway."},
	"fortify": {"name": "Fortify", "cd": 16.0, "desc": "A 60 point shield for 5s. Nothing can knock you back."},
	"blink": {"name": "Blink", "cd": 7.0, "desc": "Teleport up to 6 tiles toward the cursor. Your next shots for 2s crit."},
	"tether": {"name": "Tether Shot", "cd": 9.0, "desc": "A fast dart that roots the first foe it hits for 1.5s."},
	"hook": {"name": "Chain Hook", "cd": 10.0, "desc": "Throw a hook that drags the first foe it hits to you and stuns it."},
	"rocketjump": {"name": "Rocket Jump", "cd": 9.0, "desc": "Blast off toward the cursor, knocking away anyone next to you."},
	"ram": {"name": "Ram", "cd": 9.0, "desc": "Charge forward, bowling foes over and shoving them hard. Great near edges."},
	"dome": {"name": "Dome", "cd": 15.0, "desc": "A 4s bubble around you that blocks enemy shots from outside."},
	"vanish": {"name": "Vanish", "desc": "Cloak and haste for 5s and refill every dash."},
	"dance": {"name": "Shadow Dance", "desc": "Blink between up to three nearby foes, slashing and stunning each."},
	"skypierce": {"name": "Skypierce", "desc": "Aim for a moment, then fire a beam across the map that pierces everything."},
	"sanctuary": {"name": "Sanctuary", "desc": "A circle that heals you, your team and kin inside it for 6s."},
	"anchor": {"name": "Anchor Drop", "desc": "Leap to the cursor and slam down, launching foes away."},
	"barrage": {"name": "Barrage", "desc": "Fire six rockets into the area around the cursor."},
	"bulwark": {"name": "Bulwark", "desc": "A 120 point shield, no knockback, and nearby foes are slowed for 6s."},
	"quake": {"name": "Quake", "desc": "Stomp a shockwave ahead that launches and stuns everything in it."},
	"well": {"name": "Gravity Well", "desc": "A vortex at the cursor that drags foes in, then bursts."},
	# right click: each hero's second tool, in the spirit of Supervive's secondaries
	"shadowstep": {"name": "Shadow Knife", "cd": 8.0, "desc": "A knife. On a hit you appear behind the foe and your next shots crit."},
	"bolas": {"name": "Chain Bolas", "cd": 9.0, "desc": "Roots the first foe hit. Catch two close together to stun both."},
	"divehawk": {"name": "Dive Hawk", "cd": 10.0, "desc": "A hawk dives on the cursor: damage, knockback and a short stun."},
	"breeze": {"name": "Mending Breeze", "cd": 5.0, "desc": "Heals you and every ally in its path. Three charges."},
	"cleave": {"name": "Cleave", "cd": 6.0, "desc": "A sweeping slam. Hits wounded foes harder; from the air it stuns."},
	"binding": {"name": "Binding Orb", "cd": 9.0, "desc": "An orb at the cursor that roots every foe near it a moment later."},
	"haymaker": {"name": "Haymaker", "cd": 7.0, "desc": "A heavy punch that sends a foe flying. Into a wall, it's stunned."},
	"satchel": {"name": "Satchel Charge", "cd": 8.0, "desc": "Throw a charge, click again to blow it. It launches you too: ride it."},
	"brightshield": {"name": "Brightshield", "cd": 6.0, "desc": "Hold to block everything from the front for up to 3s. You move slower."},
}

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
const PERKS := {
	"quickhands": {"name": "Quick Hands", "desc": "Reload 30% faster."},
	"secondwind": {"name": "Second Wind", "desc": "One extra dash charge."},
	"featherfall": {"name": "Featherfall", "desc": "Glide 60% longer."},
	"scavenger": {"name": "Scavenger", "desc": "Gems you pick up are worth 25% more."},
	"toughskin": {"name": "Tough Skin", "desc": "15 more health."},
	"overcharge": {"name": "Overcharge", "desc": "Your ultimate charges 30% faster."},
}

const SIGS := {
	"cloak": {"name": "Cloak", "cd": 14.0, "desc": "Vanish for 3s and move 35% faster. Firing reveals you."},
	"mend": {"name": "Mend", "cd": 16.0, "desc": "Heal 35 to you, nearby teammates and kin. Nearby revives jump halfway."},
	"fortify": {"name": "Fortify", "cd": 16.0, "desc": "A 60 point shield for 5s. Nothing can knock you back."},
}

## Kin species. These are the built-in defaults; every content/kin/*.json file is merged over them
## (or adds a new species) when the game starts, so new kin need no code.
## skill: what Q does while the kin is out. shoulder: what you get while it rides on you.
var KIN := {
	"cindle": {"name": "Cindle", "type": "ember", "color": Color("ff7a3d"), "belly": Color("ffd28a"),
		"hp": 80.0, "dmg": 9.0, "speed": 6.8, "range": 1.3, "ears": "flame",
		"skill": "fireball", "shoulder": "kindle",
		"traits": {"bravery": 0.75, "loyalty": 0.5, "temper": 0.7, "curiosity": 0.5},
		"voice": "hot-headed, eager, talks in short bursts"},
	"puddlet": {"name": "Puddlet", "type": "tide", "color": Color("4aa8e8"), "belly": Color("c9ecff"),
		"hp": 95.0, "dmg": 7.0, "speed": 6.0, "range": 1.3, "ears": "fin",
		"skill": "wave", "shoulder": "spring",
		"traits": {"bravery": 0.45, "loyalty": 0.85, "temper": 0.2, "curiosity": 0.6},
		"voice": "gentle, worried about you, a little formal"},
	"burrlet": {"name": "Burrlet", "type": "thorn", "color": Color("6fbf5a"), "belly": Color("e2f2b0"),
		"hp": 90.0, "dmg": 8.0, "speed": 6.2, "range": 1.3, "ears": "leaf",
		"skill": "snare", "shoulder": "briar",
		"traits": {"bravery": 0.55, "loyalty": 0.6, "temper": 0.4, "curiosity": 0.8},
		"voice": "curious and odd, notices small things"},
	"zapple": {"name": "Zapple", "type": "volt", "color": Color("f5d03a"), "belly": Color("fff4c2"),
		"hp": 70.0, "dmg": 8.0, "speed": 7.6, "range": 1.3, "ears": "bolt",
		"skill": "chain", "shoulder": "charge",
		"traits": {"bravery": 0.65, "loyalty": 0.4, "temper": 0.6, "curiosity": 0.9},
		"voice": "hyper, easily distracted, loves winning"},
	"pebbit": {"name": "Pebbit", "type": "stone", "color": Color("a39a8c"), "belly": Color("e0d8c8"),
		"hp": 120.0, "dmg": 11.0, "speed": 5.4, "range": 1.4, "ears": "horn",
		"skill": "slam", "shoulder": "bedrock",
		"traits": {"bravery": 0.9, "loyalty": 0.7, "temper": 0.3, "curiosity": 0.2},
		"voice": "slow, steady, few words, deeply loyal once trust is earned"},
	"wisplet": {"name": "Wisplet", "type": "gale", "color": Color("b9a6f5"), "belly": Color("efe8ff"),
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
	"kindle": {"name": "Kindle", "desc": "Your shots set targets burning."},
	"spring": {"name": "Spring", "desc": "You heal 3 HP per second."},
	"briar": {"name": "Briar", "desc": "Your shots slow targets."},
	"charge": {"name": "Charge", "desc": "You fire and reload 20% faster."},
	"bedrock": {"name": "Bedrock", "desc": "You take 15% less damage and half the knockback."},
	"updraft": {"name": "Updraft", "desc": "One extra dash charge."},
}

const MOBS := {
	"skitter": {"name": "Skitter", "hp": 34.0, "speed": 5.2, "dmg": 9.0, "range": 1.2, "windup": 0.4, "cd": 1.3,
		"r": 0.45, "gems": 2, "color": Color("7b5ea8"), "attack": "lunge"},
	"spitter": {"name": "Spitter", "hp": 44.0, "speed": 2.2, "dmg": 11.0, "range": 8.0, "windup": 0.65, "cd": 2.2,
		"r": 0.55, "gems": 3, "color": Color("4f9e6e"), "attack": "spit"},
	"brute": {"name": "Brute", "hp": 170.0, "speed": 3.0, "dmg": 24.0, "range": 2.2, "windup": 0.95, "cd": 2.6,
		"r": 0.9, "gems": 9, "color": Color("8a5a48"), "attack": "slam", "stag": true},
	"bomber": {"name": "Puffbomb", "hp": 26.0, "speed": 4.4, "dmg": 16.0, "range": 1.7, "windup": 1.0, "cd": 1.0,
		"r": 0.5, "gems": 2, "color": Color("e07a3a"), "attack": "fuse", "slam_r": 2.5},
	"sentinel": {"name": "Sentinel", "hp": 70.0, "speed": 0.0, "dmg": 8.0, "range": 10.0, "windup": 0.8, "cd": 2.6,
		"r": 0.55, "gems": 4, "color": Color("5ab0c8"), "attack": "volley", "stag": true},
	"glimmer": {"name": "Glimmerkin", "hp": 110.0, "speed": 5.9, "dmg": 0.0, "range": 0.0, "windup": 1.0, "cd": 99.0,
		"r": 0.45, "gems": 22, "color": Color("ffd25a"), "attack": "none", "flee": true, "stag": true},
	"warden": {"name": "The Warden", "hp": 820.0, "speed": 3.3, "dmg": 30.0, "range": 2.8, "windup": 0.85, "cd": 2.1,
		"r": 1.3, "gems": 30, "color": Color("5a4a7a"), "attack": "slam", "slam_r": 3.3, "stag": true},
}

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
	{"name": "The Meadow", "desc": "Gentle islands. 3 lives. Go down for good and the kin you brought are left behind (the Ransom House sells them back cheap here).",
		"mob": 1.0, "loot": 1.0, "kin_lvl": [1, 3], "unlock": 0, "risk_kin": false, "lives": 3,
		"biome": {"top": Color("5f8d45"), "top2": Color("4a7538"), "side": Color("8b6d52"), "deep": Color("3a3140"), "leaf": Color("5a9a4f")},
		"sky": Color("10131f"), "ambient": Color("b9c4e6"), "sun": Color("fff1dc"), "clouds": [Color(0.06, 0.07, 0.13), Color(0.22, 0.24, 0.38)]},
	{"name": "Dusk Isles", "desc": "Tougher monsters, about twice the loot, and rarer kin. 2 lives. Kin you bring are at risk if you go down.",
		"mob": 1.45, "loot": 1.9, "kin_lvl": [2, 5], "unlock": 2, "risk_kin": false, "lives": 2,
		"biome": {"top": Color("56688a"), "top2": Color("465576"), "side": Color("6d5a74"), "deep": Color("2a2440"), "leaf": Color("8a6fb8")},
		"sky": Color("150f22"), "ambient": Color("c9b4e6"), "sun": Color("ffc9a8"), "clouds": [Color(0.09, 0.05, 0.14), Color(0.32, 0.2, 0.4)]},
	{"name": "The Hollow", "desc": "Brutal and rich, and only 1 life. Rival hunters here love to collect kin left behind.",
		"mob": 2.0, "loot": 3.2, "kin_lvl": [4, 8], "unlock": 5, "risk_kin": true, "lives": 1,
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
}

const MATCH := {
	"length": 360.0,       # seconds until the islands fall
	"portal_open": 150.0,  # first exit portals open this many seconds in
	"extract_time": 3.0,   # seconds standing in an open portal to leave
	"revive_time": 3.0,
	"kin_revive_time": 5.0,
	"bleed": 3.0,          # downed health lost per second
	"down_hp": 60.0,
}
