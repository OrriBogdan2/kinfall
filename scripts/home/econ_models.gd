class_name EconModels
## Models for the armory, the feeders, the graveyard and the Soul Shrine on the home island.
## Built from our primitives (Models.part / toon) with a few pack props (Assets) where they fit:
## the dungeon torch and barrels by the armory, the Halloween pack's gravestones, arch and candles.

static func _prop(id: String, size: float, by_height := true, fallback: Callable = Callable()) -> Node3D:
	var n := Assets.prop(id, size, by_height) if Assets.on() else null
	if n == null and fallback.is_valid():
		n = fallback.call()
	return n

static func _label(text: String, col: Color, y: float, size := 40, px := 0.009) -> Label3D:
	var l := Label3D.new()
	l.text = text; l.font = UI.big; l.font_size = size; l.pixel_size = px; l.outline_size = 10
	l.modulate = col; l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = Vector3(0, y, 0)
	return l

## A building for Models.building(): root > Body (what the build animation squashes).
static func building(id: String) -> Node3D:
	var root := Node3D.new()
	var body := Node3D.new(); body.name = "Body"; root.add_child(body)
	match id:
		"armory": _armory(body)
		"shrine": _shrine(body)
	return root

static func _armory(body: Node3D) -> void:
	var stone := Models.toon(Color("8f8a86")); var dark := Models.toon(Color("3e3a44")); var wood := Models.toon(Color("6e4a30"))
	var trim := Models.toon(Color("c9a46a")); var steel := Models.toon(Color("b8c2d0"))
	# a squat stone hall with a slate roof and iron-banded doors
	Models.part(body, Models.box(2.9, 1.7, 1.7), stone, Vector3(0, 0.85, -0.15))
	for sx in [-1.0, 1.0]:
		Models.part(body, Models.box(0.36, 2.0, 0.36), Models.toon(Color("75706c")), Vector3(1.42 * sx, 1.0, 0.68))
	var pr := PrismMesh.new(); pr.size = Vector3(3.4, 1.0, 2.2)
	Models.part(body, pr, Models.toon(Color("4a5368")), Vector3(0, 2.2, -0.15))
	Models.part(body, Models.box(3.3, 0.12, 0.3), trim, Vector3(0, 1.72, 0.72))
	Models.part(body, Models.box(0.95, 1.25, 0.08), wood, Vector3(0, 0.63, 0.72))
	for k in 3:
		Models.part(body, Models.box(0.98, 0.06, 0.1), dark, Vector3(0, 0.22 + k * 0.42, 0.75))
	# a shield and crossed blades over the door
	Models.part(body, Models.cyl(0.3, 0.3, 0.06, 6), Models.toon(Color("b84a3a")), Vector3(0, 1.98, 0.78), Vector3.ONE, Vector3(PI / 2, 0, 0))
	for sx in [-1.0, 1.0]:
		Models.part(body, Models.box(0.07, 0.9, 0.04), steel, Vector3(0.0, 1.98, 0.84), Vector3.ONE, Vector3(0, 0, 0.75 * sx))
	Models.part(body, Models.sphere(0.09, 8), trim, Vector3(0, 1.98, 0.84))
	# a weapon rack out front: three found weapons, glowing their rarity
	var rack := Node3D.new(); rack.position = Vector3(-1.05, 0, 1.25); body.add_child(rack)
	for sx in [-1.0, 1.0]:
		Models.part(rack, Models.box(0.08, 1.0, 0.08), wood, Vector3(0.5 * sx, 0.5, 0))
	Models.part(rack, Models.box(1.1, 0.07, 0.1), wood, Vector3(0, 0.82, 0))
	Models.part(rack, Models.box(1.1, 0.07, 0.1), wood, Vector3(0, 0.3, 0))
	var picks := [["rifle", 2], ["sniper", 3], ["smg", 4]]
	for i in picks.size():
		var gun := Node3D.new(); gun.position = Vector3(-0.32 + i * 0.32, 0.6, 0.05); gun.rotation = Vector3(PI / 2, 0, 0); gun.scale = Vector3.ONE * 1.1
		rack.add_child(gun)
		Models.gun_parts(gun, String(picks[i][0]), Models.toon(Color("4a4d5c")), Models.toon(Color("2b2a33")), Models.toon(Data.RARITY[int(picks[i][1])]["color"], true, 0.5))
	# a torch and barrels from the dungeon pack
	var torch := _prop("dungeon/torch_lit", 0.9)
	if torch:
		torch.position = Vector3(0.95, 1.05, 0.82); body.add_child(torch)
	var lamp := OmniLight3D.new(); lamp.light_color = Color("ffb060"); lamp.light_energy = 0.8; lamp.omni_range = 3.0
	lamp.position = Vector3(0.95, 1.5, 1.1); body.add_child(lamp)
	var barrel := _prop("dungeon/barrel_small", 0.55)
	if barrel:
		barrel.position = Vector3(1.15, 0, 1.25); body.add_child(barrel)
	var crates := _prop("dungeon/crates_stacked", 0.8)
	if crates:
		crates.position = Vector3(1.35, 0, -0.6); crates.rotation.y = 0.4; body.add_child(crates)
	body.add_child(_label("Armory", Color("ffd79a"), 3.05))

static func _shrine(body: Node3D) -> void:
	var stone := Models.toon(Color("a8a3b8")); var dark := Models.toon(Color("4a4560"))
	# a round stone dais, a pale arch, and an ember burning over an altar of candles
	Models.part(body, Models.cyl(1.05, 1.15, 0.22, 20), dark, Vector3(0, 0.11, 0))
	Models.part(body, Models.cyl(0.85, 0.95, 0.16, 20), stone, Vector3(0, 0.3, 0))
	var arch := _prop("halloween/arch", 2.3)
	if arch:
		arch.position = Vector3(0, 0.38, -0.45); body.add_child(arch)
	else:
		for sx in [-1.0, 1.0]:
			Models.part(body, Models.box(0.25, 2.0, 0.25), stone, Vector3(0.8 * sx, 1.3, -0.45))
		Models.part(body, Models.box(1.9, 0.25, 0.3), stone, Vector3(0, 2.3, -0.45))
	var cand := _prop("halloween/shrine_candles", 0.7)
	if cand:
		cand.position = Vector3(0, 0.38, -0.1); body.add_child(cand)
	else:
		Models.part(body, Models.box(0.8, 0.5, 0.45), stone, Vector3(0, 0.63, -0.1))
	var ember := Models.part(body, Models.sphere(0.2, 12), Models.toon(Color("9ff0e0"), false, 1.6), Vector3(0, 1.55, -0.1), Vector3.ONE, Vector3.ZERO, "Ember")
	ember.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var halo := Models.part(body, Models.sphere(0.36, 12), Models.glow_mat(Color("9ff0e0", 0.22)), Vector3(0, 1.55, -0.1))
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var l := OmniLight3D.new(); l.light_color = Color("9ff0e0"); l.light_energy = 1.1; l.omni_range = 3.5
	l.position = Vector3(0, 1.6, 0.2); body.add_child(l)
	var motes := CPUParticles3D.new()
	motes.amount = 14; motes.lifetime = 2.2
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE; motes.emission_sphere_radius = 0.6
	motes.direction = Vector3.UP; motes.spread = 20.0; motes.gravity = Vector3.ZERO
	motes.initial_velocity_min = 0.2; motes.initial_velocity_max = 0.5
	motes.scale_amount_min = 0.04; motes.scale_amount_max = 0.08
	var sm := SphereMesh.new(); sm.radius = 0.5; sm.height = 1.0; sm.radial_segments = 6; sm.rings = 3
	motes.mesh = sm; motes.material_override = Models.glow_mat(Color("bff8ec", 0.9))
	motes.position = Vector3(0, 1.3, -0.1)
	body.add_child(motes)
	body.add_child(_label("Soul Shrine", Color("bff8ec"), 2.95))

## A feeder: its own shape by kind, a heap of food that grows with how full it is (node "Food"),
## and its fill over it ("Fill").
static func feeder(kind: String) -> Node3D:
	var fd: Dictionary = Econ.FEEDERS.get(kind, Econ.FEEDERS["trough"])
	var root := Node3D.new()
	var col: Color = fd["col"]
	var wood := Models.toon(Color("7a5236")); var main := Models.toon(col)
	match kind:
		"basket":
			Models.part(root, Models.cyl(0.55, 0.42, 0.42, 14), main, Vector3(0, 0.21, 0))
			for k in 3:
				Models.part(root, Models.cyl(0.565 - k * 0.04, 0.565 - k * 0.04, 0.04, 14), Models.toon(col.darkened(0.25)), Vector3(0, 0.08 + k * 0.13, 0))
		"hopper":
			for sx in [-1.0, 1.0]:
				Models.part(root, Models.box(0.08, 1.1, 0.08), Models.toon(Color("5a6a7a")), Vector3(0.38 * sx, 0.55, -0.25))
			Models.part(root, Models.cyl(0.32, 0.12, 0.55, 12), main, Vector3(0, 1.05, -0.25))
			Models.part(root, Models.box(1.1, 0.22, 0.55), Models.toon(Color("6a7a8a")), Vector3(0, 0.11, 0.05))
			Models.part(root, Models.box(0.06, 0.4, 0.06), Models.toon(Color("6a7a8a")), Vector3(0, 0.6, -0.15), Vector3.ONE, Vector3(0.5, 0, 0))
		"banquet":
			Models.part(root, Models.box(1.6, 0.1, 0.8), Models.toon(Color("8a5a3a")), Vector3(0, 0.45, 0))
			Models.part(root, Models.box(1.5, 0.02, 0.7), Models.toon(Color("fff0f4")), Vector3(0, 0.51, 0))
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					Models.part(root, Models.box(0.08, 0.45, 0.08), wood, Vector3(0.7 * sx, 0.22, 0.32 * sz))
			Models.part(root, Models.box(1.62, 0.06, 0.06), main, Vector3(0, 0.5, 0.41))
		_:
			# a plank trough on two little trestles
			Models.part(root, Models.box(1.15, 0.08, 0.5), wood, Vector3(0, 0.2, 0))
			for sx in [-1.0, 1.0]:
				Models.part(root, Models.box(0.08, 0.26, 0.5), wood, Vector3(0.56 * sx, 0.3, 0))
			for sz in [-1.0, 1.0]:
				Models.part(root, Models.box(1.15, 0.24, 0.06), Models.toon(Color("8a6242")), Vector3(0, 0.33, 0.24 * sz))
			for sx in [-1.0, 1.0]:
				Models.part(root, Models.box(0.12, 0.2, 0.42), Models.toon(Color("5a3c28")), Vector3(0.42 * sx, 0.08, 0))
	var food_y := float({"basket": 0.36, "hopper": 0.24, "banquet": 0.56}.get(kind, 0.3))
	var food := Node3D.new(); food.name = "Food"; food.position = Vector3(0, food_y, 0.05 if kind == "hopper" else 0.0)
	root.add_child(food)
	var w := float({"basket": 0.8, "hopper": 0.9, "banquet": 1.3}.get(kind, 0.95))
	for i in 9:
		var a := float(i) * 2.4
		var r := 0.08 + float(i % 3) * 0.1
		Models.part(food, Models.sphere(0.1 + float(i % 2) * 0.03, 8), Models.toon(Color("c8a26a")), Vector3(cos(a) * r * w * 1.6, 0.05, sin(a) * r * 0.6), Vector3.ONE, Vector3.ZERO, "Bit%d" % i)
	var fl := _label("", Color("ffe3b0"), float({"hopper": 1.65, "banquet": 1.1}.get(kind, 0.95)), 34, 0.008)
	fl.name = "Fill"; fl.no_depth_test = true
	root.add_child(fl)
	return root

## Shows a feeder's contents: the heap's size and colours, and "n/cap" over it.
static func set_fill(n: Node3D, f: Dictionary) -> void:
	var food: Array = f.get("food", [])
	var cap := int(Econ.fdef(f)["cap"])
	var frac := float(food.size()) / maxf(1.0, cap)
	var heap: Node3D = n.get_node_or_null("Food")
	if heap:
		heap.visible = food.size() > 0
		heap.scale = Vector3(0.55 + frac * 0.45, 0.4 + frac * 0.9, 0.55 + frac * 0.45)
		for i in heap.get_child_count():
			var bit := heap.get_child(i) as MeshInstance3D
			if bit == null: continue
			var key := String(food[i % food.size()]) if food.size() > 0 else ""
			bit.visible = i < maxi(2, int(round(frac * 9.0)))
			if key != "": bit.material_override = Models.toon(Care.food_col(key))
	var lbl: Label3D = n.get_node_or_null("Fill")
	if lbl:
		lbl.text = "%d/%d" % [food.size(), cap] if food.size() > 0 else "empty"
		lbl.modulate = Color("ffe3b0") if frac > 0.3 else (Color("ffb070") if food.size() > 0 else Color("ff8a7a"))

## A grave: a stone with the kin's name, a little mound, flowers in its colour. A soul kept in the
## shrine shows as a wisp hovering over it.
static func grave(g: Dictionary, i: int) -> Node3D:
	var root := Node3D.new()
	var sp: Dictionary = Data.KIN.get(String(g.get("species", "")), {})
	var col: Color = sp.get("color", Color("c8c0d8"))
	if g.get("shimmer", false): col = Care.shimmer_col(col)
	var ids := ["halloween/gravestone", "halloween/grave_A", "halloween/gravemarker_A"]
	var st := _prop(ids[i % ids.size()], 0.85)
	if st == null:
		st = Node3D.new()
		Models.part(st, Models.box(0.55, 0.7, 0.14), Models.toon(Color("9a94a8")), Vector3(0, 0.35, 0))
		Models.part(st, Models.cyl(0.275, 0.275, 0.14, 12), Models.toon(Color("9a94a8")), Vector3(0, 0.7, 0), Vector3.ONE, Vector3(PI / 2, 0, 0))
	st.position = Vector3(0, 0, -0.18)
	root.add_child(st)
	Models.part(root, Models.sphere(0.4, 10), Models.toon(Color("6b5a44")), Vector3(0, 0.0, 0.25), Vector3(0.9, 0.22, 1.3))
	for k in 3:
		Models.part(root, Models.sphere(0.06, 6), Models.toon(col.lightened(0.2), false, 0.3), Vector3(-0.2 + k * 0.2, 0.08, 0.55))
	var lbl := _label(String(g.get("name", "")), Color("e8e0f0"), 1.15, 34, 0.008)
	root.add_child(lbl)
	if g.get("soul", false):
		var wisp := Models.part(root, Models.sphere(0.13, 10), Models.toon(Color("bff8ec"), false, 1.4), Vector3(0, 1.45, 0), Vector3.ONE, Vector3.ZERO, "Wisp")
		wisp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root

## The graveyard's gate: a little arch with a sign, and a lantern.
static func gate() -> Node3D:
	var root := Node3D.new()
	var arch := _prop("halloween/fence_pillar", 1.0)
	var fence_l := _prop("halloween/fence", 0.9, false)
	if fence_l:
		fence_l.position = Vector3(-1.1, 0, 0); root.add_child(fence_l)
	var fence_r := _prop("halloween/fence_broken", 0.9, false)
	if fence_r:
		fence_r.position = Vector3(1.1, 0, 0); root.add_child(fence_r)
	if arch:
		arch.position = Vector3(-0.45, 0, 0); root.add_child(arch)
		var a2 := _prop("halloween/fence_pillar", 1.0)
		a2.position = Vector3(0.45, 0, 0); root.add_child(a2)
	var lantern := _prop("halloween/post_lantern", 1.5)
	if lantern:
		lantern.position = Vector3(1.6, 0, 0.3); root.add_child(lantern)
	var l := OmniLight3D.new(); l.light_color = Color("ffd7a0"); l.light_energy = 0.6; l.omni_range = 3.0
	l.position = Vector3(1.6, 1.4, 0.5); root.add_child(l)
	root.add_child(_label("Graveyard", Color("d8d0e8"), 1.6, 38))
	return root
