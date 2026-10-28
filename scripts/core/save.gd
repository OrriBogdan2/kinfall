extends Node
## The player's persistent state: gems, the farm, the kin roster with their personalities and memories.

const PATH := "user://kinfall_save.json"
const VERSION := 1
const MAX_MEMORY := 40

var d: Dictionary = {}

func _ready() -> void:
	load_game()

func fresh() -> Dictionary:
	# a new save has no kin yet: the first thing you do is pick an egg and hatch it
	return {
		"v": VERSION,
		"name": "Hunter",
		"gems": 60,
		"cls": "medium",
		"active": "",
		"roster": [],
		"seeds": {"tidebloom": 2, "emberberry": 1},
		"crops": {},
		"items": {"tonic": 1},
		"treat": "",
		"plots": _empty_plots(4),
		"plot_cap": 4,
		"matches": 0,
		"extracts": 0,
		"settings": {"volume": 0.8, "shake": 1.0, "cam_lead": 1.0},
		"tutorial": {},
		"buildings": [],
		"music": [],
		"guild_perks": [],
		"bridges": [],
		"gh_plots": _empty_plots(4),
		"stats": {"kills": 0, "best_kills": 0, "best_gems": 0, "caught": 0, "knocks": 0},
	}

func _empty_plots(n: int) -> Array:
	var a := []
	for i in n:
		a.append({"crop": "", "stage": 0})
	return a

func new_kin(species: String, kname := "") -> Dictionary:
	var sp: Dictionary = Data.KIN[species]
	var tr := {}
	for k in sp["traits"]:
		tr[k] = clampf(float(sp["traits"][k]) + randf_range(-0.15, 0.15), 0.05, 0.95)
	return {
		"uid": "k%d%d" % [Time.get_ticks_usec() % 1000000, randi() % 1000],
		"species": species,
		"name": kname if kname != "" else Data.KIN_NAMES.pick_random(),
		"level": 1, "xp": 0,
		"traits": tr,
		"trust": 35.0,
		"memory": [],
		"matches": 0, "wins": 0, "kos": 0,
	}

func load_game() -> void:
	d = fresh()
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY and parsed.get("v", 0) == VERSION:
		for k in parsed:
			d[k] = parsed[k]
		# JSON numbers come back as floats; plots and roster are fine with that.

func save_game() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))

func reset() -> void:
	d = fresh()
	save_game()

# --- roster helpers ---
func kin(uid: String) -> Dictionary:
	for k in d["roster"]:
		if k["uid"] == uid:
			return k
	return {}

func active_kin() -> Dictionary:
	var k := kin(str(d.get("active", "")))
	if k.is_empty() and d["roster"].size() > 0:
		k = d["roster"][0]
		d["active"] = k["uid"]
	return k

func remember(k: Dictionary, kind: String, text: String, trust_delta := 0.0) -> void:
	if k.is_empty():
		return
	var mem: Array = k["memory"]
	mem.append({"m": int(d.get("matches", 0)), "kind": kind, "text": text})
	while mem.size() > MAX_MEMORY:
		mem.pop_front()
	k["trust"] = clampf(float(k["trust"]) + trust_delta, 0.0, 100.0)

func has_building(b: String) -> bool:
	return d.get("buildings", []).has(b)

func has_bridge(b: String) -> bool:
	return d.get("bridges", []).has(b)

func add_item(key: String, n: int) -> void:
	d["items"][key] = int(d["items"].get(key, 0)) + n

func add_seed(key: String, n: int) -> void:
	d["seeds"][key] = int(d["seeds"].get(key, 0)) + n
