extends Node3D
## Every class and weapon side by side, with a spread of looks, and one with its glider open. Open
## tests/hunter_gallery.tscn and press F6. Pass -- --gallery-top to look from the game's camera angle.

func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Look.environment({"top": Color("2a4a8a"), "mid": Color("6a8ad0"), "horizon": Color("ffd2a8"), "stars": 0.0})
	add_child(env)
	Look.lights(self, Color("fff1dc"), 1.0, Vector3(-45, -30, 0), 30.0)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(40, 16)
	ground.mesh = pm
	ground.material_override = Models.toon(Color("5f8d45"), false)
	add_child(ground)
	var ids: Array = []
	for c in ["light", "medium", "heavy"]:
		for w in Data.CLASSES[c]["weapons"]: ids.append([c, w])
	for i in ids.size():
		var race := i % Models.RACES.size()
		var lk := {"race": race, "body": i % 3, "gender": i % 2, "face": i % 5, "skin": int(Models.RACES[race]["skin"]) if race > 0 else (i * 2) % 8, "hair": i % 6, "hair_col": i % Models.LOOK_HAIR.size(), "outfit": i % Models.LOOK_OUTFITS.size()}
		var h := Models.hunter(ids[i][0], Data.TEAM_COLORS[i % 4], ids[i][1], "", lk)
		h.position = Vector3((i - (ids.size() - 1) * 0.5) * 1.25, 0, 0)
		h.rotation.y = PI + 0.3
		add_child(h)
		if i == 4:
			var gl: Node3D = h.get_node("Rig/Torso/Glider")
			gl.visible = true
			gl.rotation.x = 0.25
	var cam := Camera3D.new()
	if "--gallery-top" in OS.get_cmdline_user_args():
		cam.position = Vector3(0, 9.0, 7.5); cam.rotation = Vector3(-0.85, 0, 0); cam.fov = 50
	else:
		cam.position = Vector3(0, 1.6, 6.4); cam.rotation = Vector3(-0.12, 0, 0); cam.fov = 52
	add_child(cam)
	cam.make_current()
