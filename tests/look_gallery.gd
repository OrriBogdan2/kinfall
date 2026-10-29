extends Node3D
## Hunter looks up close: both genders across faces, details, hair styles, skins and hair colours.
## Open tests/look_gallery.tscn and press F6. "--looks-page=N" shows another set.

func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Look.environment({"top": Color("2a4a8a"), "mid": Color("6a8ad0"), "horizon": Color("ffd2a8"), "stars": 0.0})
	add_child(env)
	Look.lights(self, Color("fff1dc"), 1.0, Vector3(-35, -20, 0), 30.0)
	var page := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--looks-page="): page = int(a.substr(13))
	for i in 12:
		var k := i + page * 12
		var lk := {"gender": i % 2, "face": k % Models.LOOK_FACES.size(), "hair": k % Models.LOOK_HAIRS.size(),
			"skin": (k * 5) % Models.LOOK_SKIN.size(), "hair_col": (k * 3) % Models.LOOK_HAIR.size(), "detail": (k / 2) % Models.LOOK_DETAILS.size(), "body": 1}
		var h := Models.hunter("medium", Data.TEAM_COLORS[0], "repeater", "plain", lk)
		h.position = Vector3((i % 6 - 2.5) * 0.85, (i / 6) * 0.0, (i / 6) * -1.8)
		h.rotation.y = PI
		add_child(h)
		var l := Label3D.new()
		l.text = "%s · %s\n%s · %s" % [Models.LOOK_GENDERS[lk["gender"]], Models.LOOK_FACES[lk["face"]], Models.LOOK_HAIRS[lk["hair"]], Models.LOOK_DETAILS[lk["detail"]]]
		l.font_size = 22; l.pixel_size = 0.0028; l.outline_size = 6
		l.position = h.position + Vector3(0, 1.62, 0); l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(l)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.9, 4.6); cam.rotation = Vector3(-0.16, 0, 0); cam.fov = 42
	add_child(cam)
	cam.make_current()
