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

## An active glove's effects at a rarity: the same verb, bigger numbers (damage, wall health,
## healing and shields grow with the rarity multiplier; durations and pull strength by half as much).
const SCALE_FULL := ["dmg", "hp", "heal", "shield", "amount"]
const SCALE_HALF := ["strength", "time"]

static func effects_of(id: String, rar: int) -> Array:
	var effs: Array = (ALL.get(id, {}).get("effects", []) as Array).duplicate(true)
	var k := mult(rar)
	if k == 1.0:
		return effs
	for e in effs:
		_scale(e, k)
	return effs

static func _scale(e, k: float) -> void:
	if not (e is Dictionary):
		return
	for key in e.keys():
		if key in SCALE_FULL and (e[key] is float or e[key] is int):
			e[key] = float(e[key]) * k
		elif key in SCALE_HALF and (e[key] is float or e[key] is int):
			e[key] = float(e[key]) * (1.0 + (k - 1.0) * 0.5)
		elif e[key] is Array:
			for sub in e[key]: _scale(sub, k)
		elif e[key] is Dictionary and key in ["spike"]:
			pass

## Cooldown at a rarity: 8% shorter per step above common.
static func cd_of(id: String, rar: int) -> float:
	return float(ALL.get(id, {}).get("cd", 0.0)) * (1.0 - 0.08 * float(clampi(rar - 1, 0, 3)))

static func desc_of(id: String, rar: int) -> String:
	var d := String(ALL.get(id, {}).get("desc", ""))
	if active(id) and mult(rar) > 1.0 and ALL[id].has("effects"):
		d += "  (%s: +%d%% power, %ds cooldown)" % [String(Data.RARITY[clampi(rar, 0, Data.RARITY.size() - 1)].get("name", "Rare")), int(round((mult(rar) - 1.0) * 100.0)), int(round(cd_of(id, rar)))]
	return d

## An active glove as an AbilityDef, for its aim indicator and for bots.
static var _defs := {}
static func def_of(id: String) -> AbilityDef:
	if _defs.has(id):
		return _defs[id]
	var g: Dictionary = ALL.get(id, {})
	var d := AbilityDef.from_dict({"id": id, "name": g.get("name", id), "short": g.get("short", ""), "verb": g.get("verb", ""), "icon": g.get("icon", id),
		"color": "#" + (g.get("col", Color.WHITE) as Color).to_html(false), "cooldown": g.get("cd", 0.0), "effects": g.get("effects", []), "bot": g.get("bot", {}), "aim": g.get("aim", []), "desc": g.get("desc", "")})
	if not g.has("effects") and g.get("aim", []).is_empty():
		d.aim = ["self", 0.0, 1.2]
	_defs[id] = d
	return d

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
