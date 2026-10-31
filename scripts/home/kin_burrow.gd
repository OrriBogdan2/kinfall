class_name KinBurrow
## The Kin Burrow on the home island: a grassy mound with a round door, where the kin who aren't out
## on the farm sleep. Little round windows glow along its sides, one for every few kin inside, and
## a hanging lantern by the door glows lilac when someone's in.

const LILAC := Color("bfa6ff")

## The building. sleepers: how many kin are inside (lights that many windows, up to six).
static func model(sleepers := 0) -> Node3D:
	var root := Node3D.new()
	root.name = "KinBurrow"
	var earth := Models.toon(Color("7a5a3e"))
	var turf := Models.toon(Color("6fae5a"))
	var turf2 := Models.toon(Color("8cc56a"))
	var wood := Models.toon(Color("a8743f"))
	var dark := Models.toon(Color("3a2a22"))
	var stone := Models.toon(Color("9a9aa6"))
	var glow := Models.toon(LILAC, false, 1.3)
	var dim := Models.toon(Color("4a4258"), false, 0.1)
	# the mound: earth below, a thick cap of turf, a few tufts and stones
	Models.part(root, Models.sphere(1.25, 18), earth, Vector3(0, 0.15, 0), Vector3(1.25, 0.72, 1.0), Vector3.ZERO, "Mound")
	Models.part(root, Models.sphere(1.24, 18), turf, Vector3(0, 0.36, 0.06), Vector3(1.22, 0.62, 0.98), Vector3.ZERO, "Turf")
	for t in [[Vector3(-0.7, 1.05, 0.2), 0.22], [Vector3(0.55, 1.12, -0.1), 0.26], [Vector3(0.1, 1.2, 0.4), 0.18], [Vector3(-0.2, 1.16, -0.45), 0.2]]:
		Models.part(root, Models.sphere(float(t[1]), 10), turf2, t[0], Vector3(1.0, 0.7, 1.0))
	for st in [Vector3(-1.35, 0.08, -0.55), Vector3(1.4, 0.06, -0.4), Vector3(-1.1, 0.06, -0.95), Vector3(1.05, 0.05, -1.0)]:
		Models.part(root, Models.sphere(0.16, 8), stone, st, Vector3(1.2, 0.6, 1.0))
	# the round door at the front (the front faces +Z, toward where you walk up)
	var door_at := Vector3(0, 0.5, 1.12)
	var frame := TorusMesh.new(); frame.inner_radius = 0.42; frame.outer_radius = 0.56; frame.rings = 20; frame.ring_segments = 8
	Models.part(root, frame, wood, door_at, Vector3.ONE, Vector3(PI * 0.5, 0, 0), "DoorFrame")
	Models.part(root, Models.cyl(0.44, 0.44, 0.08, 20), dark, door_at + Vector3(0, 0, -0.03), Vector3.ONE, Vector3(PI * 0.5, 0, 0), "Door")
	Models.part(root, Models.cyl(0.38, 0.38, 0.06, 20), wood, door_at + Vector3(0, 0, 0.02), Vector3.ONE, Vector3(PI * 0.5, 0, 0))
	for i in 3:
		Models.part(root, Models.box(0.04, 0.66, 0.03), dark, door_at + Vector3(-0.18 + i * 0.18, 0, 0.06))
	Models.part(root, Models.sphere(0.05, 8), Models.toon(Color("e8c86a"), false, 0.4), door_at + Vector3(0.24, 0, 0.09), Vector3.ONE, Vector3.ZERO, "Knob")
	# a paw print over the door
	var paw := Models.toon(LILAC.darkened(0.25), false, 0.5)
	Models.part(root, Models.sphere(0.09, 8), paw, door_at + Vector3(0, 0.72, -0.02), Vector3(1.0, 0.8, 0.35))
	for px in [-0.11, -0.04, 0.04, 0.11]:
		Models.part(root, Models.sphere(0.035, 6), paw, door_at + Vector3(px, 0.84 + (0.02 if absf(px) < 0.05 else 0.0), -0.03), Vector3(1, 1, 0.4))
	# round windows along the sides: lit when kin sleep inside
	var wins := [Vector3(-0.95, 0.55, 0.62), Vector3(0.95, 0.55, 0.62), Vector3(-1.25, 0.42, 0.0), Vector3(1.25, 0.42, 0.0), Vector3(-0.6, 0.85, -0.7), Vector3(0.6, 0.85, -0.7)]
	var lit := clampi(int(ceil(float(sleepers) / 5.0)), 0, wins.size()) if sleepers > 0 else 0
	for i in wins.size():
		var w: Vector3 = wins[i]
		var face := Vector3(w.x, 0, w.z).normalized()
		var yaw := atan2(face.x, face.z)
		var wf := TorusMesh.new(); wf.inner_radius = 0.13; wf.outer_radius = 0.18; wf.rings = 14; wf.ring_segments = 6
		Models.part(root, wf, wood, w, Vector3.ONE, Vector3(PI * 0.5, yaw, 0), "WinFrame%d" % i)
		var pane := Models.part(root, Models.cyl(0.135, 0.135, 0.03, 14), glow if i < lit else dim, w - face * 0.02, Vector3.ONE, Vector3(PI * 0.5, yaw, 0), "Window%d" % i)
		pane.set_meta("lit", i < lit)
	# a post with a hanging lantern by the door
	var post_at := Vector3(0.95, 0, 1.4)
	Models.part(root, Models.cyl(0.05, 0.06, 1.3, 8), wood, post_at + Vector3(0, 0.65, 0))
	Models.part(root, Models.box(0.36, 0.05, 0.05), wood, post_at + Vector3(-0.15, 1.28, 0))
	Models.part(root, Models.cyl(0.01, 0.01, 0.16, 4), dark, post_at + Vector3(-0.28, 1.18, 0))
	var lantern_m := glow if sleepers > 0 else Models.toon(Color("e8d8a0"), false, 0.5)
	Models.part(root, Models.sphere(0.1, 10), lantern_m, post_at + Vector3(-0.28, 1.03, 0), Vector3(1.0, 1.25, 1.0), Vector3.ZERO, "Lantern")
	Models.part(root, Models.cyl(0.06, 0.1, 0.05, 8), dark, post_at + Vector3(-0.28, 1.15, 0))
	var light := OmniLight3D.new()
	light.light_color = LILAC if sleepers > 0 else Color("ffd9a0")
	light.light_energy = 0.9
	light.omni_range = 3.2
	light.position = post_at + Vector3(-0.28, 1.0, 0.1)
	light.name = "Glow"
	root.add_child(light)
	# a flat stone step in front of the door
	Models.part(root, Models.cyl(0.42, 0.46, 0.08, 16), stone, Vector3(0, 0.04, 1.5), Vector3(1.3, 1.0, 0.8))
	return root

## Lights the right number of windows for how many kin sleep inside.
static func set_sleepers(root: Node3D, sleepers: int) -> void:
	if root == null or not is_instance_valid(root):
		return
	var lit := clampi(int(ceil(float(sleepers) / 5.0)), 0, 6) if sleepers > 0 else 0
	var glow := Models.toon(LILAC, false, 1.3)
	var dim := Models.toon(Color("4a4258"), false, 0.1)
	for i in 6:
		var w := root.get_node_or_null("Window%d" % i) as MeshInstance3D
		if w: w.material_override = glow if i < lit else dim
	var l := root.get_node_or_null("Glow") as OmniLight3D
	if l: l.light_color = LILAC if sleepers > 0 else Color("ffd9a0")
