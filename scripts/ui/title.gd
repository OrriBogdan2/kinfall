extends Node3D
## Title screen: golden hour over a sea of clouds. Your hunter stands on a floating island with
## their kin, waterfalls spill off the islands around them, and the skyship drifts past.

var cam: Camera3D
var t := 0.0
var kin_nodes: Array = []
var hunter_node: Node3D
var ship: Node3D
var islands: Array = []          # [node, base y, bob phase]
var logo: Control

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.play_music("title")
	Sfx.play_ambience("home")
	var rng := RandomNumberGenerator.new(); rng.seed = 2026
	var env := WorldEnvironment.new()
	env.environment = Look.environment({"top": Color("161a44"), "mid": Color("5c4f9e"), "horizon": Color("ffb27a"), "below": Color("3a2f62"),
		"sun_dir": Vector3(0.62, 0.07, -0.78), "sun_col": Color("ffd2a0"), "ambient": Color("c9b8e6"), "ambient_energy": 0.55,
		"fog": Color("8a6aa8"), "fog_height": -6.0, "fog_height_density": 0.08, "stars": 0.8, "saturation": 1.18})
	add_child(env)
	var sun := Look.lights(self, Color("ffcf9e"), 1.2, Vector3(-30, 105, 0), 50.0)
	sun.shadow_opacity = 0.6
	var fill: DirectionalLight3D = get_node("Fill")
	fill.light_energy = 0.55
	fill.light_color = Color("b9a8ff")
	cam = Camera3D.new(); cam.fov = 42.0; cam.far = 3000.0; add_child(cam)
	# the cloud sea, catching the low sun
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(5000, 5000)
	sea.mesh = pm
	var cm := ShaderMaterial.new(); cm.shader = load("res://shaders/clouds.gdshader")
	cm.set_shader_parameter("deep", Color("2a2556")); cm.set_shader_parameter("light", Color("a98ad0"))
	cm.set_shader_parameter("glow", Color("ffb070")); cm.set_shader_parameter("glow_amount", 0.75)
	cm.set_shader_parameter("sun_xz", Vector2(0.62, -0.78)); cm.set_shader_parameter("scale", 0.02)
	sea.material_override = cm
	sea.position = Vector3(0, -22.0, 0)
	add_child(sea)
	_main_island(rng)
	# islands all around, near and far, some with waterfalls
	var spots := [[Vector3(-13, -3, -10), 3.2], [Vector3(16, 2, -22), 4.5], [Vector3(-26, 5, -36), 6.0], [Vector3(30, -4, -6), 3.0],
		[Vector3(5, 9, -48), 7.0], [Vector3(-40, -6, -14), 4.0], [Vector3(48, 6, -42), 6.5], [Vector3(-8, -9, 14), 2.4]]
	for i in spots.size():
		var sp: Array = spots[i]
		var r: float = sp[1]
		var isl := _scenery_island(rng, r, i % 3 != 2, i in [1, 2, 4])
		isl.position = sp[0]
		isl.rotation.y = rng.randf() * TAU
		add_child(isl)
		islands.append([isl, float((sp[0] as Vector3).y), rng.randf() * TAU])
	# the skyship crossing behind
	ship = Models.skyship()
	ship.scale = Vector3.ONE * 0.9
	add_child(ship)
	# drifting petals and motes of light
	var motes := CPUParticles3D.new()
	motes.amount = 70; motes.lifetime = 9.0; motes.preprocess = 9.0
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX; motes.emission_box_extents = Vector3(18, 6, 14)
	motes.direction = Vector3(1, 0.2, 0.3); motes.spread = 40.0; motes.initial_velocity_min = 0.3; motes.initial_velocity_max = 0.9
	motes.gravity = Vector3(0, -0.05, 0)
	motes.angular_velocity_min = -90; motes.angular_velocity_max = 90
	motes.scale_amount_min = 0.6; motes.scale_amount_max = 1.6
	motes.mesh = Models.box(0.07, 0.01, 0.05)
	var mm := StandardMaterial3D.new(); mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.vertex_color_use_as_albedo = true; mm.albedo_color = Color(1, 1, 1, 0.9); mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	motes.material_override = mm
	var grad := Gradient.new(); grad.set_color(0, Color("ffc8e0")); grad.set_color(1, Color("fff2b0"))
	motes.color_initial_ramp = grad
	motes.position = Vector3(0, 3, 0)
	add_child(motes)
	_build_ui()

## The island you stand on, with your hunter, your kin, a tree, a lantern and a banner.
func _main_island(rng: RandomNumberGenerator) -> void:
	var root := Node3D.new(); root.name = "Home"
	add_child(root)
	var isl := Models.float_island(rng, 5.2, 9.0, Color("6aa64a"), Color("9a7a5a"), Color("3a2f48"))
	root.add_child(isl)
	_grass_on(root, isl, rng, 520, 0.7)
	for p in [[Vector3(-3.3, 0, -1.6), "round"], [Vector3(2.9, 0, -2.6), "round"], [Vector3(-1.6, 0, -3.4), "pine"]]:
		var tr := Models.tree(rng, Color("5a9a4f"), p[1]); tr.position = p[0]; tr.scale = Vector3.ONE * 1.25; root.add_child(tr)
	for p in [Vector3(3.6, 0, 1.2), Vector3(-3.9, 0, 1.6), Vector3(0.6, 0, -4.0)]:
		var rk := Models.rock(rng, rng.randf_range(0.7, 1.1)); rk.position = p; root.add_child(rk)
	var lamp := Models.lamp(); lamp.position = Vector3(2.2, 0, -0.9); root.add_child(lamp)
	var flag := Models.banner(UI.ACCENT); flag.position = Vector3(-2.4, 0, -0.4); root.add_child(flag)
	var wf := Models.waterfall(1.4, 16.0); wf.position = Vector3(4.6, -0.1, -2.6); wf.rotation.y = -0.9; root.add_child(wf)
	# your hunter and kin, if you have them
	var hero: String = Save.d.get("hero", "")
	if not Data.HEROES.has(hero): hero = "sage"
	var w: String = Save.d.get("weapon", "")
	if not Data.CLASSES[Data.HEROES[hero]["cls"]]["weapons"].has(w): w = Data.HEROES[hero]["weapon"]
	hunter_node = Models.hunter(Data.HEROES[hero]["cls"], Data.TEAM_COLORS[0], w, hero, Save.d.get("look", {}))
	hunter_node.position = Vector3(0.2, 0, 0.4); hunter_node.rotation.y = PI + 0.75
	hunter_node.scale *= 1.25
	(hunter_node.get_node("TeamRing") as Node3D).visible = false
	root.add_child(hunter_node)
	var recs: Array = []
	var ak := Save.active_kin()
	if not ak.is_empty(): recs.append(ak)
	for r in Save.d.get("roster", []):
		if recs.size() >= 3: break
		if not recs.has(r): recs.append(r)
	var fallback := ["cindle", "puddlet", "zapple"]
	while recs.size() < 3:
		recs.append({"species": fallback[recs.size()], "level": 5})
	var kin_spots := [Vector3(1.5, 0, 2.0), Vector3(-1.2, 0, 2.3), Vector3(2.8, 0, 0.4)]
	for i in recs.size():
		var k := Models.kin(String(recs[i]["species"]), recs[i])
		k.position = kin_spots[i]
		k.rotation.y = PI + 0.3 + rng.randf_range(-0.35, 0.35)
		k.scale *= 1.25
		var shell: MeshInstance3D = k.get_node_or_null("Body/Shell")
		if shell:
			shell.visible = true
			(shell.material_override as ShaderMaterial).set_shader_parameter("strength", 0.45)
		root.add_child(k)
		var aura: CPUParticles3D = k.get_node_or_null("Aura")
		if aura: aura.emitting = true
		kin_nodes.append(k)
	islands.append([root, 0.0, 0.0])

func _scenery_island(rng: RandomNumberGenerator, r: float, trees: bool, falls: bool) -> Node3D:
	var root := Node3D.new()
	var tops := [Color("6aa64a"), Color("7cbc6c"), Color("c99a4c"), Color("8ab86a")]
	var isl := Models.float_island(rng, r, r * rng.randf_range(1.4, 2.0), tops[rng.randi_range(0, tops.size() - 1)], Color("9a7a5a"), Color("3a2f48"))
	root.add_child(isl)
	_grass_on(root, isl, rng, int(r * r * 6.0))
	if trees:
		for k in rng.randi_range(1, 3):
			var a := rng.randf() * TAU
			var tr := Models.tree(rng, Color("5a9a4f").lerp(Color("e0743a"), 0.4 if rng.randf() < 0.3 else 0.0), "pine" if rng.randf() < 0.35 else ("blossom" if rng.randf() < 0.25 else "round"))
			tr.position = Vector3(cos(a), 0, sin(a)) * r * rng.randf_range(0.1, 0.55)
			tr.scale = Vector3.ONE * rng.randf_range(1.0, 1.5)
			root.add_child(tr)
	if falls:
		var rim: Array = isl.get_meta("rim")
		var p2: Vector2 = rim[rng.randi_range(0, rim.size() - 1)]
		var wf := Models.waterfall(r * 0.3, 18.0)
		wf.position = Vector3(p2.x * 0.97, -0.05, p2.y * 0.97)
		wf.rotation.y = atan2(p2.x, p2.y)
		root.add_child(wf)
	return root

func _grass_on(root: Node3D, isl: MeshInstance3D, rng: RandomNumberGenerator, n: int, size := 1.0) -> void:
	var rim: Array = isl.get_meta("rim")
	var rmin := 1e9
	for p in rim: rmin = minf(rmin, (p as Vector2).length())
	var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.use_colors = true; mm.mesh = Models.grass_mesh(false)
	mm.instance_count = n
	for k in n:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * rmin * 0.95
		var sc := rng.randf_range(0.9, 1.8) * size
		mm.set_instance_transform(k, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc), Vector3(cos(a) * d, 0.0, sin(a) * d)))
		mm.set_instance_color(k, Color("7cbc5a").lerp(Color("4e8a3e"), rng.randf()))
	var mi := MultiMeshInstance3D.new(); mi.multimesh = mm
	mi.material_override = Models.grass_material(0.1)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var fm := MultiMesh.new(); fm.transform_format = MultiMesh.TRANSFORM_3D; fm.use_colors = true; fm.mesh = Models.flower_mesh()
	fm.instance_count = n / 8
	var fc := [Color("fff3a8"), Color("ff9ac8"), Color("ffffff"), Color("b8a6ff")]
	for k in fm.instance_count:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * rmin * 0.9
		fm.set_instance_transform(k, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * 1.3), Vector3(cos(a) * d, 0.0, sin(a) * d)))
		fm.set_instance_color(k, fc[rng.randi_range(0, fc.size() - 1)])
	var fi := MultiMeshInstance3D.new(); fi.multimesh = fm
	fi.material_override = Models.grass_material(0.05, true)
	fi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(fi)

func _build_ui() -> void:
	var ui := CanvasLayer.new(); add_child(ui)
	var root := Control.new(); root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.theme = UI.theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	# a soft shade on the left so the menu reads over the scene, and a gentle vignette
	var shade := TextureRect.new()
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.set_color(0, Color(0.04, 0.03, 0.1, 0.78)); gr.set_color(1, Color(0.04, 0.03, 0.1, 0.0))
	gr.set_offset(0, 0.3); gr.set_offset(1, 1.0)
	gt.gradient = gr; gt.fill_from = Vector2(0, 0); gt.fill_to = Vector2(1, 0); gt.width = 256; gt.height = 4
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	shade.offset_right = 820
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	var vig := TextureRect.new()
	var vt := GradientTexture2D.new(); var vg := Gradient.new()
	vg.set_color(0, Color(0, 0, 0, 0.0)); vg.set_color(1, Color(0.02, 0.01, 0.06, 0.55)); vg.set_offset(0, 0.55); vg.set_offset(1, 1.0)
	vt.gradient = vg; vt.fill = GradientTexture2D.FILL_RADIAL; vt.fill_from = Vector2(0.5, 0.5); vt.fill_to = Vector2(1.05, 1.05); vt.width = 128; vt.height = 128
	vig.texture = vt; vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vig)
	# the menu column stays vertically centred and fits any window height
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	col.offset_left = 72; col.offset_right = 520; col.offset_top = 24; col.offset_bottom = -40
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 12)
	root.add_child(col)
	logo = TitleLogo.new()
	logo.custom_minimum_size = Vector2(440, 190)
	col.add_child(logo)
	var tag := UI.label("Raise them. Risk them. Bring them home.", 20, Color("ffe6c8"))
	tag.autowrap_mode = TextServer.AUTOWRAP_OFF
	tag.add_theme_constant_override("outline_size", 6)
	tag.add_theme_color_override("font_outline_color", Color(0.06, 0.04, 0.12, 0.8))
	col.add_child(tag)
	col.add_child(UI.spacer(10))
	var has: bool = not Save.d["roster"].is_empty()
	var b1 := UI.primary(("Continue  ·  %s" % Save.d.get("name", "Hunter")) if has else "New game", func(): Game.goto("home" if has else "hatch"), 320)
	col.add_child(b1)
	col.add_child(UI.button("Save files", func(): Overlay.ctx = "title"; Overlay.open_saves(), 320))
	if Bridge.net_available():
		col.add_child(UI.button("Play online with friends", func(): Game.goto("lobby", {}), 320))
	var srv := UI.button("Servers  ·  coming soon", func(): pass, 320)
	srv.disabled = true
	srv.tooltip_text = "Dedicated servers are on the way. For now, play online with friends from the lobby."
	col.add_child(srv)
	col.add_child(UI.button("Settings", func(): Overlay.ctx = "title"; Overlay.open_settings(), 320))
	if not OS.has_feature("web"):
		col.add_child(UI.button("Quit", func(): get_tree().quit(), 320))
	for ch in col.get_children():
		if ch is Button: (ch as Button).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var i := 0
	for ch in col.get_children():
		UI.pop_in(ch, 0.15 + i * 0.08)
		i += 1
	var ver := UI.label("Open source · made with Godot", 13, Color(1, 1, 1, 0.55))
	ver.autowrap_mode = TextServer.AUTOWRAP_OFF
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	ver.position = Vector2(24, -36)
	root.add_child(ver)
	b1.grab_focus()

func _process(delta: float) -> void:
	t += delta
	# a slow drifting camera, low over the island, looking past it toward the sun
	var a := 0.55 + sin(t * 0.05) * 0.22
	cam.position = Vector3(sin(a) * 11.0 - 3.2, 2.9 + sin(t * 0.21) * 0.3, cos(a) * 11.0 + 2.4)
	cam.look_at(Vector3(-2.6, 1.5, -2.2), Vector3.UP)
	for isl in islands:
		var n: Node3D = isl[0]
		n.position.y = float(isl[1]) + sin(t * 0.45 + float(isl[2])) * (0.12 if isl[1] == 0.0 else 0.4)
	if ship:
		var sx := fmod(t * 1.6 + 40.0, 120.0) - 30.0
		ship.position = Vector3(sx, 13.0 + sin(t * 0.4) * 0.4, -34.0)
		ship.rotation.y = -PI / 2
		for pn in ["PropL", "PropR"]:
			(ship.get_node(pn) as Node3D).rotation.z += delta * 10.0
	for i in kin_nodes.size():
		var k: Node3D = kin_nodes[i]
		k.get_node("Body").position.y = absf(sin(t * (2.6 + i * 0.4) + i)) * 0.14
	if hunter_node:
		hunter_node.get_node("Rig/Torso").position.y = 0.42 + sin(t * 1.6) * 0.015


## The game's name, drawn big: a chunky extruded word with a warm glow and a little paraglider
## sailing over it.
class TitleLogo extends Control:
	var tt := 0.0
	func _process(delta: float) -> void:
		tt += delta
		queue_redraw()
	func _draw() -> void:
		var f: Font = UI.big
		var txt := "KINFALL"
		var fs := 108
		var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var base := Vector2(4, size.y - 34)
		# warm glow behind
		draw_string_outline(f, base, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 46, Color(1.0, 0.55, 0.25, 0.12))
		draw_string_outline(f, base, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 26, Color(1.0, 0.6, 0.3, 0.16))
		# extrusion: stacked copies going down, dark plum
		for i in range(9, 0, -1):
			var c := Color("3a1f3e").lerp(Color("7a3a3a"), 1.0 - float(i) / 9.0)
			draw_string_outline(f, base + Vector2(0, i * 1.4), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 14, c)
			draw_string(f, base + Vector2(0, i * 1.4), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
		# ink outline, the face, then a light bevel on top
		draw_string_outline(f, base, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 14, Color("2a1530"))
		draw_string(f, base, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("f7a03c"))
		draw_string(f, base + Vector2(0, -3), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.86, 0.5, 0.55))
		draw_string(f, base + Vector2(0, -6), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.95, 0.75, 0.18))
		# a paraglider sailing over the word, bobbing a little
		var gx := 4 + w * 0.62 + sin(tt * 0.8) * 6.0
		var gy := base.y - fs * 0.92 + sin(tt * 1.3) * 4.0
		var span := 74.0
		var pts := PackedVector2Array()
		var pts2 := PackedVector2Array()
		for k in 21:
			var u := float(k) / 20.0 * 2.0 - 1.0
			pts.append(Vector2(gx + u * span, gy + u * u * 18.0))
			pts2.append(Vector2(gx + u * span * 0.94, gy + u * u * 18.0 + 11.0 * (1.0 - absf(u) * 0.6)))
		var poly := PackedVector2Array(pts)
		for k in range(pts2.size() - 1, -1, -1): poly.append(pts2[k])
		draw_colored_polygon(poly, Color("f3eee2"))
		for k in [5, 10, 15]:
			var st := PackedVector2Array([pts[k], pts[k + 2], pts2[k + 2], pts2[k]])
			draw_colored_polygon(st, Color("f2a24a"))
		draw_polyline(pts, Color("2a1530"), 3.0, true)
		draw_polyline(pts2, Color("2a1530"), 3.0, true)
		# lines down to a tiny rider with a kin on their shoulder
		var rider := Vector2(gx, gy + 52)
		for k in [2, 8, 12, 18]:
			draw_line(pts2[k], rider, Color(0.16, 0.08, 0.2, 0.8), 1.5, true)
		draw_circle(rider, 7.0, Color("2a1530"))
		draw_circle(rider + Vector2(0, 1), 5.0, Color("5ab0f0"))
		draw_circle(rider + Vector2(8, -4), 4.0, Color("ff7a3d"))
