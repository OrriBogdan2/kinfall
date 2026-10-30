extends Node3D
## Match props side by side under the real sky and lights: chests, shrine, nest, portal, jump pad,
## pickups. Open tests/prop_gallery.tscn and press F6.

func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Look.environment({})
	add_child(env)
	Look.lights(self, Color("fff1d8"), 1.1, Vector3(-0.9, 0.5, 0), 60.0)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(40, 14)
	ground.mesh = pm
	ground.material_override = Models.toon(Color("dfe8ee"), false)
	add_child(ground)
	var items: Array = [Models.chest(0), Models.chest(1), Models.chest(2), Models.breakable("crate"), Models.breakable("barrel"), Models.shrine(), Models.nest(), Models.portal(Color("8fe3c8")), Models.jump_pad(Color("ffd25a")), Models.gem(), Models.tonic()]
	for i in items.size():
		var n: Node3D = items[i]
		n.position = Vector3((i - (items.size() - 1) * 0.5) * 2.6, 0, 0)
		add_child(n)
	(items[2].get_node("Body/Lid") as Node3D).rotation.x = 1.9; (items[0].get_node("Body/Lid") as Node3D).rotation.x = 0.6
	var cam := Camera3D.new()
	cam.position = Vector3(0, 7.0, 13.0)
	cam.rotation = Vector3(-0.55, 0, 0)
	cam.fov = 60
	add_child(cam)
	cam.make_current()
