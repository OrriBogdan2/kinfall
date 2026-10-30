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
## Readability and AI:
@export var short := ""                # the one or two word name on the HUD slot ("Hook", "Barrier")
@export var verb := ""                 # what it does, as one word: hook, wall, reflect, slam, trap... (docs, bots)
@export var element := ""              # venom, prism, spore, echo, gravity, lunar, or "" for a hunter's own
@export var bot: Dictionary = {}       # when a bot hunter uses it: {when: in_range|under_fire|clumped|edge|hurt|gap|always, min, max}
@export var charge: Dictionary = {}    # hold to charge: {time, min} (ctx.charge 0..1 feeds "charged" numbers)
@export var aim: Array = []            # override the aim indicator: [kind, reach, size]

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
	a.short = String(d.get("short", a.display_name))
	a.verb = String(d.get("verb", ""))
	a.element = String(d.get("element", ""))
	a.bot = d.get("bot", {})
	a.charge = d.get("charge", {})
	a.aim = d.get("aim", [])
	return a

## The aiming shape shown while the key is held: [kind, reach, size] (see Match._update_indicators).
## kinds: self (ring round you) · area (range ring + landing circle) · line (a lane: length, width) ·
## cone · wall (range ring + the wall's footprint across the aim) · arc (a frontal shield)
func aim_spec() -> Array:
	if aim.size() >= 3:
		return aim
	if from == "owner" and not _has_aimed():
		return ["self", 0.0, 1.4]
	for e in effects:
		if not (e is Dictionary):
			continue
		var reach := cast_range if cast_range > 0.0 else 8.0
		match String(e.get("type", "")):
			"projectile":
				var rad := 0.0
				for e2 in e.get("on_end", []):
					rad = maxf(rad, float(e2.get("radius", 0.0)))
				if rad > 0.0 and not e.has("on_hit") and not e.get("rope", false):
					return ["area", float(e.get("range", reach)), rad]
				return ["line", float(e.get("range", reach)), maxf(0.5, float(e.get("size", 0.2)) * 2.5) * (1.0 + float(e.get("spread", 0.0)))]
			"cone": return ["cone", float(e.get("radius", 5.0)), float(e.get("arc", 0.55))]
			"rush": return ["line", float(e.get("distance", 6.0)), float(e.get("width", 1.0)) * 2.0]
			"line", "bridge": return ["line", float(e.get("length", 8.0)), float(e.get("width", 1.3)) * 2.0]
			"blink": return ["line", float(e.get("distance", 5.0)), 0.7]
			"leap":
				var rad := 2.0
				for e2 in e.get("on_land", []):
					rad = maxf(rad, float(e2.get("radius", 0.0)))
				return ["area", reach, rad]
			"wall":
				if String(e.get("at", "aim")) == "front":
					return ["wall", float(e.get("dist", 1.4)), float(e.get("length", 4.0)), "front"]
				return ["wall", reach, float(e.get("length", 4.0))]
			"reflect":
				if float(e.get("arc", -1.0)) > -0.99:
					return ["cone", float(e.get("radius", 1.7)), float(e.get("arc", 0.0))]
				return ["self", 0.0, float(e.get("radius", 1.7))]
			"chain": return ["area", float(e.get("first", reach)), 1.2]
			"zone", "telegraph", "trap", "ally_area": return ["area", reach, float(e.get("radius", 2.0)) + (float(e.get("spread", 0.0)) if int(e.get("count", 1)) > 1 else 0.0)]
			"area":
				if String(e.get("at", "self")) == "aim":
					return ["area", reach, float(e.get("radius", 2.0))]
				return ["self", 0.0, float(e.get("radius", 2.0))]
	return ["self", 0.0, 1.2]

func _has_aimed() -> bool:
	for e in effects:
		if e is Dictionary and String(e.get("type", "")) in ["projectile", "wall", "line", "trap", "leap", "bridge", "blink", "cone"]:
			return true
	return false
