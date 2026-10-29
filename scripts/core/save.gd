extends Node
## The player's persistent state: gems, the farm, the kin roster with their personalities and memories.

const VERSION := 1
const MAX_MEMORY := 40
const SLOTS := 3

var d: Dictionary = {}
var slot := 1                 # which save file is in play

func _ready() -> void:
	# the last save you played comes back (remembered next to the settings)
	var cf := ConfigFile.new()
	if cf.load("user://settings.cfg") == OK:
		slot = clampi(int(cf.get_value("save", "slot", 1)), 1, SLOTS)
	load_game()

static func path_for(n: int) -> String:
	return "user://kinfall_save.json" if n == 1 else "user://kinfall_save_%d.json" % n

## What a save file holds, for the save list.
func slot_info(n: int) -> Dictionary:
	var out := {"exists": false}
	var p := path_for(n)
	if not FileAccess.file_exists(p):
		return out
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return out
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY or (parsed.get("roster", []) as Array).is_empty():
		return out
	var when := Time.get_datetime_dict_from_unix_time(int(FileAccess.get_modified_time(p)))
	return {"exists": true, "name": String(parsed.get("name", "Hunter")), "kin": (parsed.get("roster", []) as Array).size(),
		"gems": int(parsed.get("gems", 0)), "matches": int(parsed.get("matches", 0)),
		"when": "%d-%02d-%02d" % [when["year"], when["month"], when["day"]]}

func use_slot(n: int) -> void:
	save_game()
	slot = clampi(n, 1, SLOTS)
	load_game()
	var cf := ConfigFile.new()
	cf.load("user://settings.cfg")
	cf.set_value("save", "slot", slot)
	cf.save("user://settings.cfg")

func delete_slot(n: int) -> void:
	if FileAccess.file_exists(path_for(n)):
		DirAccess.remove_absolute(path_for(n))
	if n == slot:
		d = fresh()

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
		"lost_kin": [],       # your kin left behind on expeditions: at the Ransom House or held by a rival
		"rivals": {},         # rival hunters you've dealt with: how greedy they are, how they feel about you
		"offers": [],         # rivals asking to buy back kin you took from them
		"ransom_log": [],     # what happened at the Ransom House, newest last
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
	var rec := {
		"uid": "k%d%d" % [Time.get_ticks_usec() % 1000000, randi() % 1000],
		"species": species,
		"name": kname if kname != "" else Data.KIN_NAMES.pick_random(),
		"level": 1, "xp": 0,
		"traits": tr,
		"trust": 35.0,
		"memory": [],
		"matches": 0, "wins": 0, "kos": 0,
	}
	Care.ensure(rec)
	return rec

func load_game() -> void:
	d = fresh()
	if not FileAccess.file_exists(path_for(slot)):
		return
	var f := FileAccess.open(path_for(slot), FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY and parsed.get("v", 0) == VERSION:
		for k in parsed:
			d[k] = parsed[k]
		# JSON numbers come back as floats; plots and roster are fine with that.

func save_game() -> void:
	var f := FileAccess.open(path_for(slot), FileAccess.WRITE)
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

## The kin you bring as your second (benched, swapped in with X). "none" means bring only one.
## If you haven't picked, your most trusted other kin comes along.
func second_kin() -> Dictionary:
	var a := str(d.get("active", ""))
	var b := str(d.get("active2", ""))
	if b == "none":
		return {}
	var k := kin(b)
	if not k.is_empty() and b != a:
		return k
	var best: Dictionary = {}
	for r in d["roster"]:
		if r["uid"] != a and (best.is_empty() or float(r.get("trust", 0.0)) > float(best.get("trust", 0.0))):
			best = r
	if not best.is_empty():
		d["active2"] = best["uid"]
	return best

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
