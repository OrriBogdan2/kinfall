class_name Progress
## Lifetime stats, challenges, and what they unlock in the market.

## [id, name, what to do, stat, target, gem reward]. Finishing one can unlock market goods.
const CHALLENGES := [
	["first_out", "First Way Home", "Make it out of an expedition.", "extracts", 1, 40],
	["mobs25", "Pest Control", "Defeat 25 monsters.", "mobs", 25, 60],
	["harvest20", "Green Thumb", "Harvest 20 crops.", "harvested", 20, 50],
	["catch3", "Collector", "Bring 3 wild kin home.", "caught", 3, 80],
	["rings20", "Ring Runner", "Fly through 20 air rings.", "rings", 20, 60],
	["glide", "Sky Legs", "Spend 3 minutes gliding.", "glide_s", 180, 60],
	["feather", "Featherweight", "Feather back up from below an island's edge 5 times.", "feathers", 5, 80],
	["stag10", "Stagger Step", "Stagger 10 monsters with abilities.", "staggers", 10, 70],
	["slam5", "Into the Wall", "Wall-slam 5 enemies.", "slams", 5, 70],
	["knocks5", "Rival", "Knock down 5 hunters.", "knocks", 5, 90],
	["spike3", "Spike!", "Shoot 3 gliding hunters out of the sky.", "spikes", 3, 100],
	["build2", "Homestead", "Build 2 buildings.", "built", 2, 80],
	["hatch1", "New Life", "Hatch an egg from the nest.", "hatched", 1, 60],
	["out5", "Old Hand", "Make it out of 5 expeditions.", "extracts", 5, 150],
	["bond90", "Soulbound", "Reach a Soulbound bond with any kin.", "max_trust", 90, 120],
	["out15", "Island Legend", "Make it out of 15 expeditions.", "extracts", 15, 300],
]

## What has to happen before the market will sell something. Missing = always for sale.
const SHOP_REQ := {
	"seed:mindmint": {"challenge": "first_out"},
	"seed:puffcorn": {"extracts": 3},
	"seed:glowcap": {"challenge": "harvest20"},
	"seed:starfruit": {"challenge": "out5"},
	"food:sweetbun": {"challenge": "hatch1"},
	"food:tonicbrew": {"challenge": "mobs25"},
	"acc:scarf": {"extracts": 2},
	"acc:crown": {"challenge": "harvest20"},
	"acc:goggles": {"challenge": "rings20"},
	"acc:cape": {"challenge": "knocks5"},
	"acc:tophat": {"challenge": "bond90"},
	"plots": {"challenge": "harvest20"},
	"furn:fireplace": {"challenge": "build2"},
	"furn:trophy": {"challenge": "out5"},
	"furn:fishbowl": {"challenge": "catch3"},
	"furn:easel": {"extracts": 2},
}

static func stat(k: String) -> int:
	match k:
		"extracts": return int(Save.d.get("extracts", 0))
		"max_trust":
			var best := 0.0
			for r in Save.d.get("roster", []): best = maxf(best, float(r.get("trust", 0.0)))
			return int(best)
		"built": return Save.d.get("buildings", []).filter(func(b): return not Data.BUILDINGS.get(b, {}).get("free", false)).size()
	return int(Save.d.get("stats", {}).get(k, 0))

static func add(k: String, n: int = 1) -> void:
	if not Save.d.has("stats"): Save.d["stats"] = {}
	Save.d["stats"][k] = int(Save.d["stats"].get(k, 0)) + n

static func done(id: String) -> bool:
	return Save.d.get("challenges", []).has(id)

static func challenge(id: String) -> Array:
	for c in CHALLENGES:
		if c[0] == id: return c
	return []

static func ready_to_claim() -> Array:
	return CHALLENGES.filter(func(c): return not done(c[0]) and stat(c[3]) >= int(c[4]))

static func claim(id: String) -> int:
	var c := challenge(id)
	if c.is_empty() or done(id) or stat(c[3]) < int(c[4]):
		return 0
	if not Save.d.has("challenges"): Save.d["challenges"] = []
	Save.d["challenges"].append(id)
	Save.d["gems"] = int(Save.d["gems"]) + int(c[5])
	Save.save_game()
	return int(c[5])

static func unlocked(key: String) -> bool:
	if Game.modding():
		return true
	var req: Dictionary = SHOP_REQ.get(key, {})
	if req.has("challenge") and not done(req["challenge"]): return false
	if req.has("extracts") and stat("extracts") < int(req["extracts"]): return false
	return true

static func req_text(key: String) -> String:
	var req: Dictionary = SHOP_REQ.get(key, {})
	if req.has("challenge"):
		var c := challenge(req["challenge"])
		return "Unlocks with the challenge \"%s\"" % c[1] if not c.is_empty() else "Locked"
	if req.has("extracts"):
		return "Unlocks after %d successful expedition%s" % [int(req["extracts"]), "" if int(req["extracts"]) == 1 else "s"]
	return ""

## The goods a challenge unlocks, for its card.
static func unlocks_of(id: String) -> Array:
	var out: Array = []
	for k in SHOP_REQ:
		if SHOP_REQ[k].get("challenge", "") == id:
			out.append(k)
	return out

static func item_name(key: String) -> String:
	var p := key.split(":")
	match p[0]:
		"seed": return "%s seeds" % Data.CROPS[p[1]]["name"]
		"food": return String(Care.FOODS[p[1]]["name"])
		"acc": return String(Data.ACCS[p[1]]["name"])
		"plots": return "More farm plots"
		"furn": return String(Data.FURN[p[1]]["name"])
	return key
