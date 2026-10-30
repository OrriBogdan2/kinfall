extends Node3D
## Every glider skin, open, in a row (tooling: renders a screenshot with -- --shot=...).

func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Look.environment({"top": Color("2a4a8a"), "mid": Color("6a8ad0"), "horizon": Color("ffd2a8"), "stars": 0.0})
	add_child(env)
	Look.lights(self, Color("fff1dc"), 1.0)
	var n := Gliders.LIST.size()
	for i in n:
		var g: Dictionary = Gliders.LIST[i]
		var mi := MeshInstance3D.new()
		mi.mesh = Gliders.mesh(String(g["id"]), Data.TEAM_COLORS[0], UI.ACCENT)
		mi.material_override = Models.vtoon_outlined()
		mi.position = Vector3((i % 4 - 1.5) * 2.5, 0, (i / 4) * 1.8 - 0.9)
		add_child(mi)
		var l := Label3D.new(); l.text = String(g["name"]); l.font = UI.big; l.font_size = 36; l.pixel_size = 0.01
		l.position = mi.position + Vector3(0, 0.1, 0.7); l.rotation.x = -1.0
		add_child(l)
	var cam := Camera3D.new(); cam.fov = 45
	cam.transform = Transform3D(Basis(), Vector3(0, 6.5, 3.6)).looking_at(Vector3(0, 0, 0.2), Vector3.UP)
	add_child(cam)
	cam.make_current()
