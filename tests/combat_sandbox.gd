extends Node
## Combat sandbox: open tests/combat_sandbox.tscn and press F6 (Run Current Scene).
## Drops you on the training island with target dummies, using the loadout below. Nothing here is saved.

@export var weapon := "pulse"          # any id in content/weapons
@export var cls := "medium"

func _ready() -> void:
	if Save.d.get("roster", []).is_empty():
		var k := Save.new_kin("cindle", "Pip")
		k["level"] = 6; k["trust"] = 60.0
		Save.d["roster"] = [k]; Save.d["active"] = k["uid"]
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.set_meta("start", {"screen": "match", "opts": {"training": true, "sandbox": true, "teams": 1, "squad": 1, "tier": 0,
		"length": 1e9, "seed": 4242, "no_drop": true, "weapon": weapon, "cls": cls}})
	add_child(main)
