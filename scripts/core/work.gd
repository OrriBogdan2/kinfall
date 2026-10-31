class_name Work
## Kin at work on the farm. Every kin has a few work elements, its natural knacks for farm jobs,
## each at a level from 1 to 4 (content/kin/<id>.json "work": {"ember": 3, "forage": 1}). Farm kin
## pick up jobs on their own: the best-suited kin takes each job (level x the job's priority, less
## for a long walk), walks there, works for a while (faster at higher levels) and leaves what it
## made in your stores. Hungry or worn-out kin stop to eat and nap; one pushed too hard (a High
## priority job, no breaks) gets overworked and glum. Kin asleep in the Kin Burrow never work.
##
## The Job Board sets a priority per element (Off / Low / Normal / High) and shows who's doing
## what; a kin can be pinned to one element or kept to resting only.
##
## This file is the data and the rules (no nodes): HomeWork (scripts/home/home_work.gd) runs it on
## the home island, and the stations are build-mode items in HomeLayout.CATALOG (cat "Work").
##
## On the save:
##   rec["work_pin"]   an element: it only takes that kind of job ("" or missing: any)
##   rec["work_rest"]  true: it never works
##   rec["overworked"] true while it's been worked without a break (cleared by a proper rest)
##   Save.d["work"]    {prio: {el: 0..3}, st: {deco uid: station state}, piles: [...], made: {what: n}}
##   Save.d["mats"]    {wood, stone}: building materials, spent in build mode and on expansions

const ELEMENTS := {
	"ember": {"name": "Ember", "col": Color("ff7a3a"), "job": "Kindling", "desc": "Keeps the Hearth Oven going: firewood becomes kin kibble."},
	"tide": {"name": "Tide", "col": Color("4ab0ff"), "job": "Watering", "desc": "Waters the crops so they grow."},
	"bloom": {"name": "Bloom", "col": Color("6fd86a"), "job": "Planting", "desc": "Sows seeds in empty plots and tends growing crops along."},
	"spark": {"name": "Spark", "col": Color("ffe04a"), "job": "Powering", "desc": "Cranks the Spark Mill: a powered farm works half again as fast."},
	"craft": {"name": "Craft", "col": Color("e0a868"), "job": "Crafting", "desc": "Turns wood and stone into scrap at the Workbench."},
	"forage": {"name": "Forage", "col": Color("f0c04a"), "job": "Harvesting", "desc": "Picks ripe crops into your pantry."},
	"timber": {"name": "Timber", "col": Color("b0784a"), "job": "Lumbering", "desc": "Fells the wild trees round a Lumber Camp and splits its logs into wood."},
	"stone": {"name": "Stone", "col": Color("a8b0c4"), "job": "Mining", "desc": "Breaks the boulders round a Quarry and mines its rock into stone."},
	"frost": {"name": "Frost", "col": Color("a6eeff"), "job": "Cooling", "desc": "Keeps the Cold Store cold: fresh food fills kin up 15% more."},
	"haul": {"name": "Haul", "col": Color("c6a4ff"), "job": "Hauling", "desc": "Carries logs and stone to the Storage Chest, and food to feeders that run low."},
	"mend": {"name": "Mend", "col": Color("ff8ab4"), "job": "Mending", "desc": "Cheers up tired, glum or hungry kin, and brews tonics at the Infirmary."},
	"ranch": {"name": "Ranch", "col": Color("ffcf9a"), "job": "Ranching", "desc": "Lounges in the Ranch Pen and makes things: glowcaps, sweet buns, kibble."},
}
const ORDER := ["tide", "bloom", "forage", "ember", "timber", "stone", "craft", "spark", "frost", "haul", "mend", "ranch"]
const MAX_LV := 4

const PRIO := ["Off", "Low", "Normal", "High"]
const PRIO_W := [0.0, 0.5, 1.0, 2.0]
const PRIO_DEFAULT := 2

## Work elements for kin that don't list them in their JSON yet (the boss-egg kin).
const FALLBACK := {
	"cairnback": {"stone": 4, "timber": 3, "haul": 2},
	"hivara": {"ranch": 4, "bloom": 3, "craft": 2},
	"zephyrak": {"spark": 4, "tide": 2, "haul": 2},
}
## A guess from the combat type, for a species with no work list at all.
const BY_TYPE := {"venom": "ember", "prism": "tide", "spore": "bloom", "echo": "spark", "gravity": "stone", "lunar": "frost"}

## Rare mutations sharpen a knack (+1, or a new one at level 1).
const MUT_BONUS := {"giant": "haul", "tiny": "forage", "crystal": "stone", "glowing": "spark", "twintail": "haul", "albino": "frost", "melanistic": "ember"}
## Elder kin (two forms taken) are a level better at what they're best at.
const ELDER_FORMS := 2

## What a kin in the Ranch Pen makes: [store ("crop" or "item"), key, how many].
const RANCH := {"burrlet": ["crop", "glowcap", 1], "wisplet": ["item", "sweetbun", 1], "hivara": ["item", "sweetbun", 2], "cairnback": ["mat", "stone", 2]}
const RANCH_DEFAULT := ["item", "kibble", 2]

## Kin awake at night (owls, bats): the rest leave work for the morning.
const NOCTURNAL := ["wisplet", "zapple"]

## Extra need drain while working, per minute (on top of Care's usual drift).
const DRAIN := {"food": 1.2, "energy": 1.6, "joy": 0.35}
## Kin stop working below these (and go eat or nap), and won't start below the second set.
const STOP := {"food": 22.0, "energy": 16.0}
const START := {"food": 34.0, "energy": 26.0}
## Working this long without a break makes a kin want one; on a High priority job it keeps going
## and gets overworked instead.
const SHIFT := 150.0
const BREAK := 25.0

static var _base := {}

# ------------------------------------------------------------------ a kin's elements
## A species' own elements {el: level}.
static func base(species: String) -> Dictionary:
	if _base.has(species):
		return _base[species]
	var out := {}
	var j: Dictionary = Content._load("kin", species)
	var raw = j.get("work", FALLBACK.get(species, null))
	if typeof(raw) == TYPE_DICTIONARY:
		for el in raw:
			if ELEMENTS.has(String(el)):
				out[String(el)] = clampi(int(raw[el]), 1, MAX_LV)
	if out.is_empty():
		var t := String(Data.KIN.get(species, {}).get("type", ""))
		out[String(BY_TYPE.get(t, "haul"))] = 2
		out["haul"] = maxi(int(out.get("haul", 0)), 1)
	_base[species] = out
	return out

## A kin's elements with its bonuses: rare mutations, being an Elder, and the farmhand role
## (a farmhand waters even without Tide). {el: level}.
static func of(rec: Dictionary) -> Dictionary:
	var out: Dictionary = base(String(rec.get("species", ""))).duplicate()
	for mid in Mutations.of(rec):
		if MUT_BONUS.has(mid):
			var el: String = MUT_BONUS[mid]
			out[el] = mini(MAX_LV, int(out.get(el, 0)) + 1)
	if (rec.get("forms", []) as Array).size() >= ELDER_FORMS:
		var top := _top(out)
		if top != "": out[top] = mini(MAX_LV, int(out[top]) + 1)
	if rec.get("farmhand", false):
		out["tide"] = maxi(int(out.get("tide", 0)), 1)
	return out

static func _top(d: Dictionary) -> String:
	var best := ""; var bv := 0
	for el in ORDER:
		if int(d.get(el, 0)) > bv: bv = int(d[el]); best = el
	return best

static func level(rec: Dictionary, el: String) -> int:
	return int(of(rec).get(el, 0))

## [[el, level], ...] best first (ties in ORDER).
static func list(rec: Dictionary) -> Array:
	var d := of(rec)
	var out: Array = []
	for el in ORDER:
		if d.has(el): out.append([el, int(d[el])])
	out.sort_custom(func(a, b): return int(a[1]) > int(b[1]) or (int(a[1]) == int(b[1]) and ORDER.find(a[0]) < ORDER.find(b[0])))
	return out

## Where each bonus level comes from, for the kin's card: {el: "Giant"}.
static func bonus_why(rec: Dictionary) -> Dictionary:
	var b := base(String(rec.get("species", "")))
	var out := {}
	for mid in Mutations.of(rec):
		if MUT_BONUS.has(mid): out[MUT_BONUS[mid]] = Mutations.name_of(mid)
	if (rec.get("forms", []) as Array).size() >= ELDER_FORMS:
		var top := _top(b)
		if top != "": out[top] = (String(out[top]) + ", Elder") if out.has(top) else "Elder"
	if rec.get("farmhand", false) and not b.has("tide"): out["tide"] = "Farmhand"
	return out

static func name_of(el: String) -> String:
	return String(ELEMENTS.get(el, {}).get("name", el.capitalize()))

static func col_of(el: String) -> Color:
	return ELEMENTS.get(el, {}).get("col", Color.WHITE)

## How much faster a higher level works: 1.0 at level 1, 2.2 at level 4.
static func speed(lv: int) -> float:
	return 0.6 + 0.4 * clampi(lv, 1, MAX_LV)

## How keen a kin is on one job: its level times the job's priority, less for a long walk.
static func score(lv: int, prio_i: int, dist: float) -> float:
	if lv <= 0 or prio_i <= 0:
		return 0.0
	return float(lv) * float(PRIO_W[clampi(prio_i, 0, 3)]) / (1.0 + dist / 8.0)

# ------------------------------------------------------------------ who may work
## "" if it can take jobs, else why not.
static func why_not(rec: Dictionary) -> String:
	if rec.is_empty():
		return "nobody"
	if KinBox.is_boxed(rec):
		return "Asleep in the Kin Burrow"
	if rec.get("work_rest", false):
		return "Resting only"
	if rec.get("ghost_wait", false):
		return "Away"
	var ss := Care.starve_stage(rec)
	if ss in ["weak", "refuse", "sick", "dead"]:
		return "Too weak from hunger"
	return ""

static func can_work(rec: Dictionary) -> bool:
	return why_not(rec) == ""

static func pin(rec: Dictionary) -> String:
	return String(rec.get("work_pin", ""))

static func set_pin(rec: Dictionary, el: String) -> void:
	if el == "" or not ELEMENTS.has(el): rec.erase("work_pin")
	else: rec["work_pin"] = el
	rec.erase("work_rest")

static func set_rest(rec: Dictionary, on: bool) -> void:
	if on:
		rec["work_rest"] = true
		rec.erase("work_pin")
	else:
		rec.erase("work_rest")

## Would it take a job of this element at all (its pin, the element's priority, its level)?
static func takes(rec: Dictionary, el: String) -> bool:
	if not can_work(rec) or prio(el) <= 0 or level(rec, el) <= 0:
		return false
	var p := pin(rec)
	return p == "" or p == el

# ------------------------------------------------------------------ the save
static func ensure() -> Dictionary:
	if typeof(Save.d.get("work")) != TYPE_DICTIONARY:
		Save.d["work"] = {}
	var w: Dictionary = Save.d["work"]
	for k in ["prio", "st", "made"]:
		if typeof(w.get(k)) != TYPE_DICTIONARY: w[k] = {}
	if typeof(w.get("piles")) != TYPE_ARRAY: w["piles"] = []
	if typeof(Save.d.get("mats")) != TYPE_DICTIONARY:
		Save.d["mats"] = {}
	for m in ["wood", "stone"]:
		Save.d["mats"][m] = int(Save.d["mats"].get(m, 0))
	return w

static func prio(el: String) -> int:
	var w := ensure()
	return clampi(int(w["prio"].get(el, PRIO_DEFAULT)), 0, 3)

static func set_prio(el: String, p: int) -> void:
	ensure()["prio"][el] = clampi(p, 0, 3)

static func station(u: int) -> Dictionary:
	var st: Dictionary = ensure()["st"]
	var key := str(u)
	if typeof(st.get(key)) != TYPE_DICTIONARY:
		st[key] = {}
	return st[key]

static func mat(m: String) -> int:
	ensure()
	return int(Save.d["mats"].get(m, 0))

static func add_mat(m: String, n: int) -> void:
	ensure()
	Save.d["mats"][m] = maxi(0, int(Save.d["mats"].get(m, 0)) + n)

## Counts what the farm has made, for the Job Board.
static func count(what: String, n: int) -> void:
	var made: Dictionary = ensure()["made"]
	made[what] = int(made.get(what, 0)) + n

## Food stays fresh while any Cold Store is chilled: meals from feeders fill 15% more.
static func fresh() -> bool:
	for k in ensure()["st"]:
		var s = Save.d["work"]["st"][k]
		if typeof(s) == TYPE_DICTIONARY and float(s.get("chill", 0.0)) > 0.0:
			return true
	return false

const FRESH_MULT := 1.15
