class_name Scenery
## Scenery pieces shared by the title screen and the prologue: decorated floating islands with
## grass, flowers, trees and waterfalls, and the Heart crystal with its pillar of light.

static func island(rr: RandomNumberGenerator, r: float, trees: bool, falls: bool) -> Node3D:
	var root := Node3D.new()
	var tops := [Color("6aa64a"), Color("7cbc6c"), Color("c99a4c"), Color("8ab86a")]
	var isl := Models.float_island(rr, r, r * rr.randf_range(1.4, 2.0), tops[rr.randi_range(0, tops.size() - 1)], Color("9a7a5a"), Color("3a2f48"))
	root.add_child(isl)
	grass_on(root, isl, rr, int(r * r * 6.0))
	if trees:
		for k in rr.randi_range(1, 3):
			var a := rr.randf() * TAU
			var tr := Models.tree(rr, Color("5a9a4f").lerp(Color("e0743a"), 0.4 if rr.randf() < 0.3 else 0.0), "pine" if rr.randf() < 0.35 else ("blossom" if rr.randf() < 0.25 else "round"))
			tr.position = Vector3(cos(a), 0, sin(a)) * r * rr.randf_range(0.1, 0.55)
			tr.scale = Vector3.ONE * rr.randf_range(1.0, 1.5)
			root.add_child(tr)
	if falls:
		var rim: Array = isl.get_meta("rim")
		var p2: Vector2 = rim[rr.randi_range(0, rim.size() - 1)]
		var wf := Models.waterfall(r * 0.3, 18.0)
		wf.position = Vector3(p2.x * 0.97, -0.05, p2.y * 0.97)
		wf.rotation.y = atan2(p2.x, p2.y)
		root.add_child(wf)
	return root

static func grass_on(root: Node3D, isl: MeshInstance3D, rr: RandomNumberGenerator, n: int, size := 1.0) -> void:
	var rim: Array = isl.get_meta("rim")
	var rmin := 1e9
	for p in rim: rmin = minf(rmin, (p as Vector2).length())
	var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.use_colors = true; mm.mesh = Models.grass_mesh(false)
	mm.instance_count = n
	for k in n:
		var a := rr.randf() * TAU
		var d := sqrt(rr.randf()) * rmin * 0.95
		var sc := rr.randf_range(0.9, 1.8) * size
		mm.set_instance_transform(k, Transform3D(Basis(Vector3.UP, rr.randf() * TAU).scaled(Vector3.ONE * sc), Vector3(cos(a) * d, 0.0, sin(a) * d)))
		mm.set_instance_color(k, Color("7cbc5a").lerp(Color("4e8a3e"), rr.randf()))
	var mi := MultiMeshInstance3D.new(); mi.multimesh = mm
	mi.material_override = Models.grass_material(0.1)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var fm := MultiMesh.new(); fm.transform_format = MultiMesh.TRANSFORM_3D; fm.use_colors = true; fm.mesh = Models.flower_mesh()
	fm.instance_count = n / 8
	var fc := [Color("fff3a8"), Color("ff9ac8"), Color("ffffff"), Color("b8a6ff")]
	for k in fm.instance_count:
		var a := rr.randf() * TAU
		var d := sqrt(rr.randf()) * rmin * 0.9
		fm.set_instance_transform(k, Transform3D(Basis(Vector3.UP, rr.randf() * TAU).scaled(Vector3.ONE * 1.3), Vector3(cos(a) * d, 0.0, sin(a) * d)))
		fm.set_instance_color(k, fc[rr.randi_range(0, fc.size() - 1)])
	var fi := MultiMeshInstance3D.new(); fi.multimesh = fm
	fi.material_override = Models.grass_material(0.05, true)
	fi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(fi)

## The Heart: a great crystal at the middle of the islands, with a light that climbs into the sky.
static func heart(isl: Node3D, r: float) -> void:
	var cm := Models.toon(Color("8ae8ff"), true, 1.3)
	var pm := PrismMesh.new(); pm.size = Vector3(2.6, 6.5, 2.6)
	var spire := Node3D.new(); spire.position = Vector3(0, 3.6, 0); isl.add_child(spire)
	Models.part(spire, pm, cm, Vector3(0, 1.0, 0))
	Models.part(spire, pm, cm, Vector3(0, -1.4, 0), Vector3(1.0, 0.5, 1.0), Vector3(PI, 0, 0))
	for i in 5:
		var a := TAU * i / 5.0
		Models.part(spire, pm, cm, Vector3(cos(a) * 1.4, -0.8, sin(a) * 1.4), Vector3(0.45, 0.5, 0.45), Vector3(sin(a) * 0.4, 0, -cos(a) * 0.4))
	PropAnim.on(spire, 0.25, 0.3, 0.8)
	var beam := Models.part(isl, Models.cyl(1.4, 2.4, 120.0, 16), Models.glow_mat(Color(0.55, 0.9, 1.0, 0.24)), Vector3(0, 62.0, 0))
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ring := MeshInstance3D.new(); ring.mesh = Models.flat_quad(r * 1.3)
	ring.material_override = Models.ring_mat(Color(0.55, 0.9, 1.0, 0.6), 0.04); ring.position.y = 0.1
	isl.add_child(ring)

