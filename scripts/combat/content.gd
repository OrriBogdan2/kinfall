class_name Content
## Loads combat content (weapons, abilities, class dodges, later kin) from JSON under res://content.
## Anyone can add a new one by dropping a JSON file in the right folder: no code changes.

static var _cache := {}

static func _load(kind: String, id: String) -> Dictionary:
	var key := kind + "/" + id
	if _cache.has(key):
		return _cache[key]
	var path := "res://content/%s/%s.json" % [kind, id]
	var out := {}
	if FileAccess.file_exists(path):
		var j = JSON.parse_string(FileAccess.get_file_as_string(path))
		if j is Dictionary:
			out = j
		else:
			push_warning("Content: couldn't read " + path)
	_cache[key] = out
	return out

static func ability(id: String) -> AbilityDef:
	var d := _load("abilities", id)
	return AbilityDef.from_dict(d) if not d.is_empty() else null

static func weapon(id: String) -> WeaponDef:
	var d := _load("weapons", id)
	return WeaponDef.from_dict(d) if not d.is_empty() else null

## The dodge a class uses (Shift).
static func class_dodge(cls: String) -> AbilityDef:
	var d := _load("classes", cls)
	return ability(String(d.get("dodge", "dash")))

static func ids(kind: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open("res://content/" + kind)
	if dir:
		for f in dir.get_files():
			if f.ends_with(".json"): out.append(f.get_basename())
	return out
