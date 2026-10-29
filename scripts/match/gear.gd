class_name Gear
## Gear found on expeditions: two slots. Every piece gives stats; most also have an active you fire
## with F (slot 1) or G (slot 2), like Supervive's relics.

const ALL := {
	"jump_pad": {"name": "Pocket Jump Pad", "cd": 22.0, "col": Color("8ff0c8"), "stats": {"speed": 0.04},
		"desc": "Throw down a jump pad. Anyone who steps on it is launched high. Lasts 20s."},
	"gust_fan": {"name": "Gust Fan", "cd": 16.0, "col": Color("cfeaff"), "stats": {"glide_speed": 0.1},
		"desc": "A burst of wind launches you up and forward and cools your glider. Saves falls, reaches high ground."},
	"platform": {"name": "Emergency Platform", "cd": 40.0, "col": Color("ffd27a"), "stats": {"heat": 0.15},
		"desc": "Pop a floating platform under your feet for 8s. Your rescue over the abyss."},
	"smoke": {"name": "Smoke Bomb", "cd": 22.0, "col": Color("b8b0c8"), "stats": {"speed": 0.04},
		"desc": "A cloud that hides everyone inside it, like tall grass, for 8s."},
	"medkit": {"name": "Field Medkit", "cd": 28.0, "col": Color("8fe0a0"), "stats": {"armor": 10.0},
		"desc": "Heal 40 health and 20 armor."},
	"scanner": {"name": "Scanner", "cd": 26.0, "col": Color("9ab4ff"), "stats": {"cdr": 0.05},
		"desc": "Reveal every rival hunter within 26 tiles for 3s, through walls and grass."},
	"shock": {"name": "Shock Charge", "cd": 16.0, "col": Color("fff27a"), "stats": {"dmg": 0.05},
		"desc": "Blast everything around you away. Great for knocking rivals off the edge."},
	# passive pieces: stats only, no active
	"booster": {"name": "Glider Booster", "cd": 0.0, "col": Color("6ac0ff"), "stats": {"glide_speed": 0.2, "heat": 0.2},
		"desc": "Glide 20% faster and longer."},
	"heat_sink": {"name": "Heat Sink", "cd": 0.0, "col": Color("ff9a5a"), "stats": {"heat": 0.45},
		"desc": "Your glider holds 45% more heat."},
	"power_core": {"name": "Power Core", "cd": 0.0, "col": Color("ff6a4a"), "stats": {"dmg": 0.12},
		"desc": "12% more damage."},
	"vest": {"name": "Plated Vest", "cd": 0.0, "col": Color("b0e4ff"), "stats": {"armor": 25.0},
		"desc": "25 more armor."},
	"boots": {"name": "Swift Boots", "cd": 0.0, "col": Color("8fd16a"), "stats": {"speed": 0.1},
		"desc": "10% faster on foot."},
	"focus": {"name": "Focus Lens", "cd": 0.0, "col": Color("d07aff"), "stats": {"cdr": 0.18},
		"desc": "Abilities recharge 18% faster."},
}

static func active(id: String) -> bool:
	return float(ALL.get(id, {}).get("cd", 0.0)) > 0.0

## Rarer gear has bigger numbers (1x, 1.3x, 1.6x, 2x).
static func mult(rar: int) -> float:
	return [1.0, 1.0, 1.3, 1.6, 2.0][clampi(rar, 0, 4)]

static func stat_text(id: String, rar: int) -> String:
	var bits: Array = []
	var st: Dictionary = ALL[id]["stats"]
	var k := mult(rar)
	for s in st:
		var v := float(st[s]) * k
		match s:
			"speed": bits.append("+%d%% move speed" % int(round(v * 100)))
			"glide_speed": bits.append("+%d%% glide speed" % int(round(v * 100)))
			"heat": bits.append("+%d%% glider heat" % int(round(v * 100)))
			"armor": bits.append("+%d armor" % int(round(v)))
			"dmg": bits.append("+%d%% damage" % int(round(v * 100)))
			"cdr": bits.append("%d%% faster abilities" % int(round(v * 100)))
	return ", ".join(bits)

static func roll(r: RandomNumberGenerator) -> String:
	var keys: Array = ALL.keys()
	return keys[r.randi_range(0, keys.size() - 1)]
