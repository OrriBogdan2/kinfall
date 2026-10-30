class_name Gear
## Gloves found on expeditions (Supervive's grips). Two slots: slot 1 holds an ACTIVE glove you
## fire with Q, slot 2 a PASSIVE glove that only gives stats. Every glove gives stats; a glove with a
## cooldown is an active one and goes in slot 1, one without goes in slot 2. Picking up a glove
## replaces the one in its slot (the old one drops). They last one expedition, like perks.
## Defined in content/gloves/*.json: name, cd, col, icon, stats, desc, and for most new actives an
## "effects" list run through Effects (the same building blocks abilities use).

static var ALL: Dictionary = {}

static func _static_init() -> void:
	_load()

static func _load() -> void:
	ALL = {}
	var dir := DirAccess.open("res://content/gloves")
	if dir == null:
		return
	var files: Array = []
	for f in dir.get_files():
		var fn := String(f).trim_suffix(".remap")
		if fn.ends_with(".json"): files.append(fn)
	files.sort()
	for fn in files:
		var txt := FileAccess.get_file_as_string("res://content/gloves/" + String(fn))
		var d = JSON.parse_string(txt)
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var id := String(d.get("id", String(fn).trim_suffix(".json")))
		d["col"] = Color(String(d.get("col", "ffffff")))
		d["cd"] = float(d.get("cd", 0.0))
		ALL[id] = d

static func active(id: String) -> bool:
	return float(ALL.get(id, {}).get("cd", 0.0)) > 0.0

## Which slot a glove goes in: 0 the active slot (Q), 1 the passive slot.
static func slot_of(id: String) -> int:
	return 0 if active(id) else 1

static func icon_of(id: String) -> String:
	return String(ALL.get(id, {}).get("icon", id))

## Rarer gloves have bigger numbers (1x, 1.3x, 1.6x, 2x).
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
	keys.sort()
	return keys[r.randi_range(0, keys.size() - 1)]
