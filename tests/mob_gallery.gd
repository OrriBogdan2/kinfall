extends Node3D
## Every monster side by side, the brutes and skitters shown mid-stride and mid-windup so their
## joints can be checked. Open tests/mob_gallery.tscn and press F6.

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("1b2030")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("b9c4e6")
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.5, 0)
	sun.light_energy = 1.1
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(40, 14)
	ground.mesh = pm
	ground.material_override = Models.toon(Color("5f8d45"), false)
	add_child(ground)
	var ids: Array = Data.MOBS.keys()
	var n := ids.size() + 1
	for i in n:
		var kind := String(ids[mini(i, ids.size() - 1)])
		var k := Models.mob(kind)
		k.position = Vector3((i - (n - 1) * 0.5) * 2.2, 0, 0)
		k.rotation.y = PI + 0.5
		add_child(k)
		var b: Node3D = k.get_node("Body")
		if i == n - 1:
			# a second warden mid-windup, fists overhead
			for a in ["ArmL", "ArmR"]:
				var arm := b.get_node_or_null("Torso/" + a) as Node3D
				if arm: arm.rotation.x = 2.6
		elif kind == "brute":
			(b.get_node("LegL") as Node3D).rotation.x = 0.5
			(b.get_node("LegR") as Node3D).rotation.x = -0.5
			(b.get_node("Torso/ArmL") as Node3D).rotation.x = -0.3
			(b.get_node("Torso/ArmR") as Node3D).rotation.x = 0.3
		elif kind == "skitter":
			for j in 3:
				for sx in [-1, 1]:
					(b.get_node("Leg%d%d" % [j, sx]) as Node3D).rotation.y = (0.4 if (j % 2 == 0) == (sx > 0) else -0.4)
		var l := Label3D.new()
		l.text = kind
		l.font_size = 48; l.pixel_size = 0.005
		l.position = k.position + Vector3(0, 2.6, 0)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(l)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 4.6, 9.5)
	cam.rotation = Vector3(-0.42, 0, 0)
	cam.fov = 55
	add_child(cam)
	cam.make_current()
