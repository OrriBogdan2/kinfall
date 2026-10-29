class_name WeaponDef
extends Resource
## A weapon: the primary attack's numbers plus the weapon's utility ability (right click).
## Loaded from content/weapons/<id>.json.

@export var id := ""
@export var display_name := ""
@export var primary := {}              # dmg, rate, speed, mag, reload, kb, spread, range, size, color, sfx, boom...
@export var utility := ""              # an AbilityDef id
@export var classes: Array = ["light", "medium", "heavy"]

static func from_dict(d: Dictionary) -> WeaponDef:
	var w := WeaponDef.new()
	w.id = String(d.get("id", ""))
	w.display_name = String(d.get("name", w.id.capitalize()))
	w.primary = d.get("primary", {}).duplicate()
	w.primary["name"] = w.display_name
	if w.primary.has("color"): w.primary["color"] = Color(String(w.primary["color"]))
	w.utility = String(d.get("utility", ""))
	w.classes = d.get("classes", w.classes)
	return w
