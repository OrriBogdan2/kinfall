class_name AbilityDef
extends Resource
## One ability, described as data. `effects` is a list of effect steps (see Effects) so new
## abilities can be made without writing code. Loaded from content/abilities/<id>.json.

@export var id := ""
@export var display_name := ""
@export_multiline var desc := ""
@export var icon := ""                 # an icon id from Icons, or empty
@export var color := Color.WHITE
@export var cooldown := 6.0            # seconds between uses (per charge)
@export var charges := 1               # uses stored up
@export var effects: Array = []        # [{type: "projectile" | "area" | "dash" | ..., params...}]

static func from_dict(d: Dictionary) -> AbilityDef:
	var a := AbilityDef.new()
	a.id = String(d.get("id", ""))
	a.display_name = String(d.get("name", a.id.capitalize()))
	a.desc = String(d.get("desc", ""))
	a.icon = String(d.get("icon", ""))
	a.color = Color(String(d.get("color", "#ffffff")))
	a.cooldown = float(d.get("cooldown", 6.0))
	a.charges = int(d.get("charges", 1))
	a.effects = d.get("effects", [])
	return a
