class_name KinDef
extends Resource
## A kin species described as data: stats, looks, its two abilities, its bond ultimate and how it
## fights. Loaded from content/kin/<id>.json, so a new kin is a new JSON file (see CONTENT.md).

@export var id := ""
@export var display_name := ""
@export var type := ""
@export var color := Color.WHITE
@export var belly := Color.WHITE
@export var glow := Color.WHITE
@export var wing := Color(0, 0, 0, 0)    # wing membrane colour, for kin that have wings
@export var stats: Dictionary = {}       # hp dmg speed range
@export var look: Dictionary = {}        # ears body tail feet aura
@export var traits: Dictionary = {}      # starting personality: bravery loyalty temper curiosity
@export var abilities: Array = []        # one or two ability ids (Q and V)
@export var ultimate := ""               # an ultimate id (R, when the bond meter is full)
@export var ai: Dictionary = {}          # aggression loyalty caution style
@export var throw_hit: Dictionary = {}   # extra status when it's thrown into a foe
@export var shoulder := ""

static func from_dict(d: Dictionary) -> KinDef:
	var k := KinDef.new()
	k.id = String(d.get("id", ""))
	k.display_name = String(d.get("name", k.id.capitalize()))
	k.type = String(d.get("type", ""))
	k.color = Color(String(d.get("color", "#ffffff")))
	k.belly = Color(String(d.get("belly", "#ffffff")))
	k.glow = Color(String(d.get("glow", d.get("color", "#ffffff"))))
	if d.has("wing"): k.wing = Color(String(d["wing"]))
	k.stats = d.get("stats", {})
	k.look = d.get("look", {})
	k.traits = d.get("traits", {})
	k.abilities = d.get("abilities", [])
	k.ultimate = String(d.get("ultimate", ""))
	k.ai = d.get("ai", {})
	k.throw_hit = d.get("throw_hit", {})
	k.shoulder = String(d.get("shoulder", ""))
	return k

## The entry the rest of the game reads from Data.KIN.
func to_species() -> Dictionary:
	var out := {"name": display_name, "type": type, "color": color, "belly": belly, "glow": glow,
		"hp": float(stats.get("hp", 85.0)), "dmg": float(stats.get("dmg", 8.0)), "speed": float(stats.get("speed", 6.5)),
		"range": float(stats.get("range", 1.3)), "ears": String(look.get("ears", "")), "look": look,
		"skill": String(abilities[0]) if abilities.size() > 0 else "", "abilities": abilities, "ultimate": ultimate,
		"shoulder": shoulder if shoulder != "" else "spring", "traits": traits, "ai": ai, "throw_hit": throw_hit}
	if wing.a > 0.0: out["wing"] = wing
	return out
