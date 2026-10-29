class_name UltimateDef
extends Resource
## A bond ultimate (R). Two forms for now:
##   "armor": the kin fuses onto its hunter for `time` seconds. `owner` changes the hunter
##            (dmg speed shield regen refill_dash) and `shots` adds to every shot (burn slow boom chain kb).
##   "giant": the kin grows huge for `time` seconds. `giant` holds scale hp dmg range speed and the
##            `stomp` effects its attacks make.
## `on_start`, `on_end` and `aura` ({every, effects}) are effect lists (see Effects).

@export var id := ""
@export var display_name := ""
@export_multiline var desc := ""
@export var form := "armor"
@export var time := 6.0
@export var color := Color.WHITE
@export var owner_mods: Dictionary = {}
@export var shots: Dictionary = {}
@export var giant: Dictionary = {}
@export var aura: Dictionary = {}
@export var on_start: Array = []
@export var on_end: Array = []

static func from_dict(d: Dictionary) -> UltimateDef:
	var u := UltimateDef.new()
	u.id = String(d.get("id", ""))
	u.display_name = String(d.get("name", u.id.capitalize()))
	u.desc = String(d.get("desc", ""))
	u.form = String(d.get("form", "armor"))
	u.time = float(d.get("time", 6.0))
	u.color = Color(String(d.get("color", "#ffffff")))
	u.owner_mods = d.get("owner", {})
	u.shots = d.get("shots", {})
	u.giant = d.get("giant", {})
	u.aura = d.get("aura", {})
	u.on_start = d.get("on_start", [])
	u.on_end = d.get("on_end", [])
	return u
