class_name WorkModels
## The work stations' models (HomeLayout.CATALOG, cat "Work"), built from simple parts and the
## vendored props. Each has a few named children HomeWork switches with the station's state:
##   Logs / Ore     the camp's log pile and the quarry's rock (hidden while they grow back)
##   Fire           the oven's flame (lit while baking)
##   Wheel          the Spark Mill's wheel (turns while it has charge), Charge its glowing core
##   Frost          the Cold Store's frosty glow (while chilled)
##   Tag            a small floating label with the station's name and state
## Footprints are 1 x 1, 2 x 1 (along x before turning) or 3 x 2 (the pen).

static func _p(id: String, size: float, by_h := true, cfg := {}) -> Node3D:
	return Assets.prop(id, size, by_h, cfg)

static func station(id: String, e: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var wood := Models.toon(Color("8a5a35"))
	var dark := Models.toon(Color("5a3a24"))
	var stone := Models.toon(Color("9a948c"))
	var iron := Models.toon(Color("3a3a44"))
	match id:
		"job_board":
			Models.part(n, Models.box(0.1, 1.5, 0.1), dark, Vector3(-0.38, 0.75, 0))
			Models.part(n, Models.box(0.1, 1.5, 0.1), dark, Vector3(0.38, 0.75, 0))
			Models.part(n, Models.box(0.95, 0.72, 0.07), wood, Vector3(0, 1.08, 0.02))
			Models.part(n, Models.box(1.08, 0.08, 0.16), dark, Vector3(0, 1.5, 0.02))
			# little job notes pinned on, one per element colour
			var els: Array = Work.ORDER
			for i in 6:
				var c: Color = Work.col_of(els[(i * 2) % els.size()])
				Models.part(n, Models.box(0.2, 0.17, 0.02), Models.toon(c.lerp(Color.WHITE, 0.35), false), Vector3(-0.3 + (i % 3) * 0.3, 1.2 - (i / 3) * 0.26, 0.07), Vector3.ONE, Vector3(0, 0, rng.randf_range(-0.15, 0.15)))
		"lumber_camp":
			# a chopping stump with an axe, and the log pile that grows back
			Models.part(n, Models.cyl(0.3, 0.34, 0.42, 12), wood, Vector3(-0.5, 0.21, 0))
			Models.part(n, Models.cyl(0.29, 0.29, 0.02, 12), Models.toon(Color("e0c08a"), false), Vector3(-0.5, 0.43, 0))
			Models.part(n, Models.box(0.05, 0.5, 0.05), dark, Vector3(-0.42, 0.62, 0.05), Vector3.ONE, Vector3(0, 0, -0.5))
			Models.part(n, Models.box(0.2, 0.12, 0.03), iron, Vector3(-0.52, 0.48, 0.05), Vector3.ONE, Vector3(0, 0, -0.5))
			var logs := _p("hexagon/resource_lumber", 0.9, false)
			if logs == null:
				logs = Node3D.new()
				for i in 5:
					Models.part(logs, Models.cyl(0.11, 0.11, 0.8, 10), Models.toon(Color("9a6a40")), Vector3(0, 0.12 + (i / 3) * 0.2, -0.22 + (i % 3) * 0.22 + (i / 3) * 0.11), Vector3.ONE, Vector3(0, 0, PI / 2))
			logs.name = "Logs"; logs.position = Vector3(0.45, 0, 0)
			n.add_child(logs)
		"quarry":
			var bed := _p("dungeon/rubble_large", 1.6, false, {"bright": 1.3})
			if bed: bed.position = Vector3(-0.15, 0, 0.05); n.add_child(bed)
			Models.part(n, Models.box(0.05, 0.6, 0.05), dark, Vector3(-0.65, 0.3, 0.2), Vector3.ONE, Vector3(0.3, 0, 0.4))
			Models.part(n, Models.box(0.34, 0.06, 0.06), iron, Vector3(-0.58, 0.58, 0.28), Vector3.ONE, Vector3(0.3, 0, 0.4))
			var ore := _p("hexagon/resource_stone", 0.85, false)
			if ore == null:
				ore = Node3D.new()
				Models.part(ore, Models.sphere(0.36, 8), stone, Vector3(0, 0.28, 0), Vector3(1.1, 0.8, 1.0))
			ore.name = "Ore"; ore.position = Vector3(0.42, 0, 0)
			n.add_child(ore)
		"storage_chest":
			var ch := _p("dungeon/chest", 0.85, false)
			if ch == null:
				ch = Node3D.new()
				Models.part(ch, Models.box(0.8, 0.5, 0.55), wood, Vector3(0, 0.25, 0))
				Models.part(ch, Models.box(0.84, 0.16, 0.59), dark, Vector3(0, 0.56, 0))
			n.add_child(ch)
		"hearth_oven":
			# a round clay oven with a chimney and a fire mouth facing out
			var clay := Models.toon(Color("c27a52"))
			Models.part(n, Models.cyl(0.42, 0.46, 0.24, 14), stone, Vector3(0, 0.12, 0))
			Models.part(n, Models.sphere(0.42), clay, Vector3(0, 0.36, 0), Vector3(1.0, 0.95, 1.0))
			Models.part(n, Models.cyl(0.09, 0.11, 0.4, 10), clay, Vector3(0.18, 0.86, -0.12))
			Models.part(n, Models.box(0.36, 0.26, 0.2), Models.toon(Color("2a1a14"), false), Vector3(0, 0.36, 0.34))
			var fire := Node3D.new(); fire.name = "Fire"; n.add_child(fire)
			Models.part(fire, Models.sphere(0.12, 8), Models.toon(Color("ffb04a"), false, 1.6), Vector3(0, 0.33, 0.33), Vector3(1.3, 0.9, 0.6))
			var fl := OmniLight3D.new(); fl.light_color = Color("ff9a4a"); fl.light_energy = 0.8; fl.omni_range = 2.6; fl.position = Vector3(0, 0.5, 0.6)
			fire.add_child(fl)
			fire.visible = false
		"workbench":
			Models.part(n, Models.box(1.6, 0.1, 0.7), wood, Vector3(0, 0.62, 0))
			for x in [-0.7, 0.7]:
				for z in [-0.26, 0.26]:
					Models.part(n, Models.box(0.09, 0.6, 0.09), dark, Vector3(x, 0.3, z))
			Models.part(n, Models.box(0.3, 0.16, 0.18), iron, Vector3(-0.45, 0.75, 0.0))
			Models.part(n, Models.box(0.04, 0.32, 0.04), dark, Vector3(0.2, 0.8, 0.1), Vector3.ONE, Vector3(0, 0, 1.2))
			Models.part(n, Models.box(0.14, 0.08, 0.08), iron, Vector3(0.33, 0.86, 0.1))
			var rack := _p("hexagon/crate_A_small", 0.45)
			if rack: rack.position = Vector3(0.55, 0.67, -0.1); n.add_child(rack)
		"spark_mill":
			# a little windmill-like crank tower with a glowing core
			Models.part(n, Models.cyl(0.32, 0.4, 1.2, 8), stone, Vector3(0, 0.6, 0))
			Models.part(n, Models.cyl(0.05, 0.42, 0.42, 8), Models.toon(Color("6a4a8a")), Vector3(0, 1.4, 0))
			var core := MeshInstance3D.new(); core.name = "Charge"
			core.mesh = Models.sphere(0.13, 10); core.material_override = Models.toon(Color("ffe04a"), false, 1.5)
			core.position = Vector3(0, 0.75, 0.33)
			n.add_child(core)
			var wheel := Node3D.new(); wheel.name = "Wheel"; wheel.position = Vector3(0, 1.05, 0.36)
			n.add_child(wheel)
			Models.part(wheel, Models.cyl(0.06, 0.06, 0.08, 8), iron, Vector3.ZERO, Vector3.ONE, Vector3(PI / 2, 0, 0))
			for i in 4:
				var bl := Models.part(wheel, Models.box(0.12, 0.62, 0.03), Models.toon(Color("f3eee2")), Vector3.ZERO, Vector3.ONE, Vector3(0, 0, i * PI / 4))
				bl.position = Vector3(cos(i * PI / 4 + PI / 2), sin(i * PI / 4 + PI / 2), 0) * 0.0
		"cold_store":
			var ice := Models.toon(Color("cfefff"))
			Models.part(n, Models.box(0.86, 0.8, 0.72), Models.toon(Color("6a8aa8")), Vector3(0, 0.4, 0))
			Models.part(n, Models.box(0.92, 0.12, 0.78), ice, Vector3(0, 0.86, 0))
			Models.part(n, Models.box(0.5, 0.56, 0.04), Models.toon(Color("4a6a88")), Vector3(0, 0.4, 0.37))
			Models.part(n, Models.box(0.06, 0.14, 0.05), iron, Vector3(0.18, 0.44, 0.4))
			for i in 4:
				Models.part(n, Models.cyl(0.0, 0.05, 0.22, 6), ice, Vector3(-0.36 + i * 0.24, 0.72, 0.38), Vector3.ONE, Vector3(PI, 0, 0))
			var fr := MeshInstance3D.new(); fr.name = "Frost"
			fr.mesh = Models.sphere(0.5, 12); fr.material_override = Models.glow_mat(Color(0.65, 0.92, 1.0, 0.18))
			fr.position = Vector3(0, 0.5, 0); fr.scale = Vector3(1.1, 0.9, 1.0)
			n.add_child(fr)
			fr.visible = false
		"ranch_pen":
			# a low fence round a straw-strewn patch with a feed tub; open on the front side
			var straw := Models.toon(Color("d8c27a"), false)
			Models.part(n, Models.box(2.7, 0.03, 1.7), straw, Vector3(0, 0.015, 0))
			for side in [[Vector3(0, 0, -0.9), 2.9, 0.0], [Vector3(-1.45, 0, 0), 1.8, PI / 2], [Vector3(1.45, 0, 0), 1.8, PI / 2], [Vector3(-0.95, 0, 0.9), 1.0, 0.0], [Vector3(0.95, 0, 0.9), 1.0, 0.0]]:
				var f := Node3D.new(); f.position = side[0]; f.rotation.y = side[2]; n.add_child(f)
				var ln: float = side[1]
				Models.part(f, Models.box(ln, 0.07, 0.06), wood, Vector3(0, 0.42, 0))
				Models.part(f, Models.box(ln, 0.07, 0.06), wood, Vector3(0, 0.22, 0))
				for k in int(ln / 0.6) + 1:
					Models.part(f, Models.box(0.08, 0.55, 0.08), dark, Vector3(-ln * 0.5 + k * (ln / maxf(1.0, int(ln / 0.6))), 0.27, 0))
			Models.part(n, Models.cyl(0.24, 0.2, 0.22, 12), wood, Vector3(-0.9, 0.11, -0.5))
			Models.part(n, Models.cyl(0.2, 0.2, 0.02, 12), straw, Vector3(-0.9, 0.22, -0.5))
			var sack := _p("hexagon/sack", 0.45)
			if sack: sack.position = Vector3(1.0, 0, -0.5); n.add_child(sack)
		"infirmary":
			# a cot under a white awning, a herb shelf and a little red-cross banner
			var cloth := Models.toon(Color("f3eee2"))
			Models.part(n, Models.box(1.0, 0.18, 0.5), Models.toon(Color("ffb8c8")), Vector3(-0.35, 0.3, 0))
			for x in [-0.8, 0.1]:
				Models.part(n, Models.box(0.07, 0.3, 0.45), dark, Vector3(x, 0.15, 0))
			Models.part(n, Models.box(0.36, 0.12, 0.4), cloth, Vector3(-0.7, 0.44, 0))
			for x in [-0.9, 0.2]:
				Models.part(n, Models.cyl(0.04, 0.04, 1.4, 6), wood, Vector3(x, 0.7, -0.3))
			Models.part(n, Models.box(1.3, 0.05, 0.75), cloth, Vector3(-0.35, 1.38, -0.05), Vector3.ONE, Vector3(0.2, 0, 0))
			Models.part(n, Models.box(0.5, 0.7, 0.3), wood, Vector3(0.55, 0.35, -0.1))
			for i in 3:
				Models.part(n, Models.sphere(0.07, 6), Models.toon([Color("8fe0a0"), Color("ff8ab4"), Color("8fd0ff")][i], false, 0.4), Vector3(0.42 + i * 0.13, 0.78, 0.0))
			Models.part(n, Models.box(0.22, 0.06, 0.02), Models.toon(Color("e0405e"), false), Vector3(0.55, 0.45, 0.06))
			Models.part(n, Models.box(0.06, 0.22, 0.02), Models.toon(Color("e0405e"), false), Vector3(0.55, 0.45, 0.06))
	var tag := Label3D.new()
	tag.name = "Tag"
	tag.font = UI.big; tag.font_size = 40; tag.pixel_size = 0.0085; tag.outline_size = 10
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED; tag.no_depth_test = true
	tag.modulate = Color("fff3d6")
	tag.position = Vector3(0, 1.75 if id != "ranch_pen" else 1.1, 0)
	tag.text = String(HomeLayout.CATALOG.get(id, {}).get("name", id))
	tag.visible = false
	n.add_child(tag)
	return n

## Something a working kin holds up while it works (a log, a stone, a watering can...).
static func held(kind: String, el: String) -> Node3D:
	var n := Node3D.new()
	n.name = "Held"
	var c := Work.col_of(el)
	match kind:
		"water":
			Models.part(n, Models.cyl(0.09, 0.1, 0.16, 10), Models.toon(Color("5a8ac8")), Vector3.ZERO)
			Models.part(n, Models.cyl(0.015, 0.025, 0.16, 6), Models.toon(Color("5a8ac8")), Vector3(0.1, 0.05, 0), Vector3.ONE, Vector3(0, 0, -0.9))
		"chop", "log", "carry_wood":
			Models.part(n, Models.cyl(0.06, 0.06, 0.32, 8), Models.toon(Color("9a6a40")), Vector3.ZERO, Vector3.ONE, Vector3(0, 0, PI / 2))
		"mine", "ore", "carry_stone":
			Models.part(n, Models.sphere(0.1, 6), Models.toon(Color("a8a29a")), Vector3.ZERO, Vector3(1.2, 0.9, 1.0))
		"plant", "tend", "harvest":
			Models.part(n, Models.sphere(0.08, 8), Models.toon(Color("8fd16a")), Vector3.ZERO)
			Models.part(n, Models.box(0.12, 0.02, 0.05), Models.toon(Color("6fd86a"), false), Vector3(0, 0.08, 0))
		"bake":
			Models.part(n, Models.box(0.2, 0.08, 0.12), Models.toon(Color("c8a26a")), Vector3.ZERO)
		"craft":
			Models.part(n, Models.box(0.03, 0.2, 0.03), Models.toon(Color("5a3a24")), Vector3.ZERO)
			Models.part(n, Models.box(0.1, 0.06, 0.06), Models.toon(Color("3a3a44")), Vector3(0, 0.1, 0))
		"stock":
			Models.part(n, Models.box(0.2, 0.14, 0.16), Models.toon(Color("d8b878")), Vector3.ZERO)
			Models.part(n, Models.sphere(0.05, 6), Models.toon(Color("f2a24a")), Vector3(0, 0.09, 0))
		"brew", "mend":
			Models.part(n, Models.cyl(0.05, 0.07, 0.14, 8), Models.toon(Color("8ff0a0"), false, 0.6), Vector3.ZERO)
		_:
			Models.part(n, Models.sphere(0.07, 6), Models.toon(c, false, 0.8), Vector3.ZERO)
	return n
