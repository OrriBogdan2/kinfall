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
## Kin abilities only:
@export var from := "self"             # "kin": the kin casts it (thrown out first if it's on your shoulder) | "owner": it works on you wherever the kin is
@export var cast_range := 0.0          # how far from the kin it can be aimed (0 = anywhere)
@export var auto: Dictionary = {}      # when the kin uses it by itself: {when: foe_in_range|foes_clumped|owner_hurt|owner_falling|owner_fighting, ...}

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
	a.from = String(d.get("from", "self"))
	a.cast_range = float(d.get("range", 0.0))
	a.auto = d.get("auto", {})
	return a

## The aiming shape shown while the key is held: [kind, reach, size] (see Match._update_indicators).
func aim_spec() -> Array:
	if from == "owner":
		return ["self", 0.0, 1.4]
	for e in effects:
		if not (e is Dictionary):
			continue
		var reach := cast_range if cast_range > 0.0 else 8.0
		match String(e.get("type", "")):
			"projectile":
				var rad := float(e.get("size", 0.3)) * 2.0
				for e2 in e.get("on_end", []):
					rad = maxf(rad, float(e2.get("radius", 0.0)))
				return ["area", float(e.get("range", reach)), rad]
			"cone": return ["cone", float(e.get("radius", 5.0)), float(e.get("arc", 0.55))]
			"rush": return ["line", float(e.get("distance", 6.0)), float(e.get("width", 1.0)) * 2.0]
			"leap":
				var rad := 2.0
				for e2 in e.get("on_land", []):
					rad = maxf(rad, float(e2.get("radius", 0.0)))
				return ["area", reach, rad]
			"chain": return ["area", float(e.get("first", reach)), 1.2]
			"zone", "telegraph": return ["area", reach, float(e.get("radius", 2.0))]
			"area":
				if String(e.get("at", "self")) == "aim":
					return ["area", reach, float(e.get("radius", 2.0))]
				return ["self", 0.0, float(e.get("radius", 2.0))]
	return ["self", 0.0, 1.2]
