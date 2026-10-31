extends RefCounted
## The air around and under the islands: drifting layers of soft cloud at several depths over the
## opaque cloud sea, slanting shafts of sunlight down into the void, and far-off floating rocks and
## islets (sculpted like the world's props, see Flora) so the void has depth. Purely visual.

const LAYERS := [
	# depth, scale, speed, cover, alpha, shade toward lit
	{"y": -6.5, "scale": 0.075, "speed": 0.02, "cover": 0.62, "alpha": 0.55},
	{"y": -11.0, "scale": 0.05, "speed": 0.013, "cover": 0.54, "alpha": 0.8},
]

var W: Node

func _init(world: Node) -> void:
	W = world

## deep, light: the tier's cloud colours.
func build(parent: Node3D, deep: Color, light: Color, rng: RandomNumberGenerator) -> void:
	var size: float = maxi(W.w, W.h) * 9.0
	var ctr := Vector3(W.w / 2.0, 0, W.h / 2.0)
	var sh: Shader = load("res://shaders/cloud_layer.gdshader")
	for k in LAYERS.size():
		var L: Dictionary = LAYERS[k]
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new(); pm.size = Vector2(size, size)
		mi.mesh = pm
		var m := ShaderMaterial.new(); m.shader = sh
		# the higher layer is the lighter one, catching more sun
		var up := 1.0 - float(k) / LAYERS.size()
		m.set_shader_parameter("lit", light.lightened(0.35 + 0.2 * up).lerp(Color("ffe2c8"), 0.12))
		m.set_shader_parameter("shade", deep.lerp(light, 0.45 + 0.2 * up))
		m.set_shader_parameter("rim", Color("ffd2a8"))
		m.set_shader_parameter("haze", deep.lerp(light, 0.5))
		m.set_shader_parameter("scale", L["scale"])
		m.set_shader_parameter("speed", L["speed"])
		m.set_shader_parameter("cover", L["cover"])
		m.set_shader_parameter("alpha", L["alpha"])
		m.set_shader_parameter("seed", float(k) * 4.3 + rng.randf() * 3.0)
		mi.material_override = m
		mi.position = ctr + Vector3(0, float(L["y"]), 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.name = "CloudLayer%d" % k
		parent.add_child(mi)
	_shafts(parent, rng)
	_far_rocks(parent, rng)

## Shafts of sunlight slanting down past the island edges into the clouds.
func _shafts(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var sh: Shader = load("res://shaders/light_shaft.gdshader")
	var axis := Vector3(0.45, -1.0, 0.55).normalized()     # down and away from the sun
	var placed := 0
	for _k in 200:
		if placed >= int(clampf(W.w * W.h / 2000.0, 4, 20)):
			break
		var at := Vector3(rng.randf_range(0, W.w), 0, rng.randf_range(0, W.h))
		# in the void, but near an island (that's where you look)
		if not W.is_void(at.x, at.z):
			continue
		var near := false
		for d in [Vector2(5, 0), Vector2(-5, 0), Vector2(0, 5), Vector2(0, -5)]:
			if not W.is_void(at.x + d.x, at.z + d.y): near = true
		if not near:
			continue
		placed += 1
		var mi := MeshInstance3D.new()
		var qm := QuadMesh.new(); qm.size = Vector2(1, 1)
		mi.mesh = qm
		var m := ShaderMaterial.new(); m.shader = sh
		m.set_shader_parameter("color", Color("ffe0b8"))
		m.set_shader_parameter("intensity", rng.randf_range(0.045, 0.08))
		m.set_shader_parameter("seed", rng.randf() * 10.0)
		mi.material_override = m
		var ln := rng.randf_range(16.0, 26.0)
		var wd := rng.randf_range(6.0, 10.0)
		# the shader faces the quad to the camera round its own Y axis: lay Y along the shaft
		var y_axis := -axis * ln
		var x_axis := axis.cross(Vector3.FORWARD).normalized() * wd
		var z_axis := x_axis.cross(y_axis).normalized()
		mi.transform = Transform3D(Basis(x_axis, y_axis, z_axis), at + Vector3(0, -6.0, 0))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)

## A ring of far-off floating rocks and islets around the map, below and level with the islands,
## fading into the haze: some bare boulders tumbling slowly, some islets with a tree or two.
func _far_rocks(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var bio: Dictionary = W.biome
	var top_c: Color = bio.get("top", Color("5f8d45"))
	var side_c: Color = bio.get("side", Color("8b6d52"))
	var deep_c: Color = bio.get("deep", Color("3a3140"))
	var ctr := Vector2(W.w / 2.0, W.h / 2.0)
	var rad := maxf(W.w, W.h) * 0.5
	var n := int(clampf(rad * 0.35, 10, 40))
	var mats := {}
	for k in n:
		var a := TAU * k / n + rng.randf_range(-0.2, 0.2)
		var d := rad * rng.randf_range(1.12, 1.6)
		var at := Vector3(ctr.x + cos(a) * d, rng.randf_range(-16.0, 2.0), ctr.y + sin(a) * d)
		var style: String = Flora.STYLES[rng.randi_range(0, Flora.STYLES.size() - 1)]
		if rng.randf() < 0.45:
			var r := rng.randf_range(2.5, 6.0)
			var isl := Models.float_island(rng, r, r * rng.randf_range(1.4, 2.4), top_c.darkened(0.1), side_c, deep_c)
			isl.position = at
			isl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(isl)
			for t in rng.randi_range(1, 3):
				var tn := Flora.node("tree", style, rng.randi_range(0, Flora.VARIANTS - 1), rng.randf_range(0.9, 1.3))
				var ta := rng.randf() * TAU
				tn.position = at + Vector3(cos(ta), 0, sin(ta)) * r * rng.randf_range(0.0, 0.5)
				tn.rotation.y = rng.randf() * TAU
				parent.add_child(tn)
		else:
			var rn := Flora.node("rock", style, rng.randi_range(0, Flora.VARIANTS - 1), rng.randf_range(2.0, 5.0))
			rn.position = at
			rn.rotation = Vector3(rng.randf_range(-0.6, 0.6), rng.randf() * TAU, rng.randf_range(-0.6, 0.6))
			parent.add_child(rn)
