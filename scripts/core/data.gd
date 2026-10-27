extends Node
## Every tunable definition in the game lives here: classes, weapons, kin, monsters, crops.
## Distances are in tiles (1 unit), speeds in tiles per second, times in seconds.

const TEAM_COLORS := [Color("f2a24a"), Color("5ab0f0"), Color("e0607e"), Color("8fd16a"), Color("b48cf2"), Color("f0d45a")]

const CLASSES := {
	"light": {
		"name": "Light", "hp": 90, "speed": 6.3, "dashes": 3, "mass": 0.9, "scale": 0.9,
		"sig": "cloak", "weapon": "stinger",
		"desc": "Fast and fragile. Three dashes and a cloak to slip out of fights.",
	},
	"medium": {
		"name": "Medium", "hp": 115, "speed": 5.4, "dashes": 2, "mass": 1.0, "scale": 1.0,
		"sig": "mend", "weapon": "repeater",
		"desc": "The all-rounder. Heals the team and its kin, and speeds up revives.",
	},
	"heavy": {
		"name": "Heavy", "hp": 155, "speed": 4.7, "dashes": 1, "mass": 1.45, "scale": 1.14,
		"sig": "fortify", "weapon": "thumper",
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
}

const SIGS := {
	"cloak": {"name": "Cloak", "cd": 14.0, "desc": "Vanish for 3s and move 35% faster. Firing reveals you."},
	"mend": {"name": "Mend", "cd": 16.0, "desc": "Heal 35 to you, nearby teammates and kin. Nearby revives jump halfway."},
	"fortify": {"name": "Fortify", "cd": 16.0, "desc": "A 60 point shield for 5s. Nothing can knock you back."},
}

## Kin species. Crowdsourced creatures would add entries here.
## skill: what Q does while the kin is out. shoulder: what you get while it rides on you.
const KIN := {
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
		"r": 0.9, "gems": 9, "color": Color("8a5a48"), "attack": "slam"},
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
}

const KIN_NAMES := ["Pip", "Mochi", "Bramble", "Sorrel", "Tumble", "Fig", "Juniper", "Biscuit", "Nettle", "Wren", "Sprout", "Ember", "Clove", "Pebble", "Marlo", "Quill", "Dusk", "Taffy", "Rune", "Kip"]
const BOT_NAMES := ["Vexa", "Moss", "Tarn", "Juno", "Rook", "Kestrel", "Nim", "Sable", "Orin", "Lux", "Bryn", "Cato", "Ivy", "Rho", "Wick", "Zed", "Fen", "Mara"]

## Expedition tiers: deeper islands are harder and richer, and in the Hollow your partner can be lost.
const TIERS := [
	{"name": "The Meadow", "desc": "Gentle islands. Lose the match and you only lose what you carried.",
		"mob": 1.0, "loot": 1.0, "kin_lvl": [1, 3], "unlock": 0, "risk_kin": false,
		"biome": {"top": Color("5f8d45"), "top2": Color("4a7538"), "side": Color("8b6d52"), "deep": Color("3a3140"), "leaf": Color("5a9a4f")},
		"sky": Color("10131f"), "ambient": Color("b9c4e6"), "sun": Color("fff1dc"), "clouds": [Color(0.06, 0.07, 0.13), Color(0.22, 0.24, 0.38)]},
	{"name": "Dusk Isles", "desc": "Tougher monsters, about twice the loot, and rarer kin.",
		"mob": 1.45, "loot": 1.9, "kin_lvl": [2, 5], "unlock": 2, "risk_kin": false,
		"biome": {"top": Color("56688a"), "top2": Color("465576"), "side": Color("6d5a74"), "deep": Color("2a2440"), "leaf": Color("8a6fb8")},
		"sky": Color("150f22"), "ambient": Color("c9b4e6"), "sun": Color("ffc9a8"), "clouds": [Color(0.09, 0.05, 0.14), Color(0.32, 0.2, 0.4)]},
	{"name": "The Hollow", "desc": "Brutal and rich. If you don't make it out, a partner that doesn't fully trust you stays behind.",
		"mob": 2.0, "loot": 3.2, "kin_lvl": [4, 8], "unlock": 5, "risk_kin": true,
		"biome": {"top": Color("4f6b5e"), "top2": Color("3d5650"), "side": Color("5a4a44"), "deep": Color("1e1a22"), "leaf": Color("c25a4a")},
		"sky": Color("0d0b10"), "ambient": Color("d0a0a0"), "sun": Color("ffb090"), "clouds": [Color(0.07, 0.03, 0.04), Color(0.3, 0.12, 0.12)]},
]

const MATCH := {
	"length": 360.0,       # seconds until the islands fall
	"portal_open": 150.0,  # first exit portals open this many seconds in
	"extract_time": 3.0,   # seconds standing in an open portal to leave
	"revive_time": 3.0,
	"kin_revive_time": 5.0,
	"bleed": 3.0,          # downed health lost per second
	"down_hp": 60.0,
}
