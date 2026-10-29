extends Node3D
## Title screen: a small island drifting in the clouds with your hunter and partner kin on it.

var cam: Camera3D
var t := 0.0
var kin_node: Node3D
var hunter_node: Node3D

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.play_music("title")
	Sfx.play_ambience("home")
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("10131f")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("c4cbe6")
	e.ambient_light_energy = 0.45
	e.glow_enabled = true
	e.glow_intensity = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -60, 0)
	sun.light_color = Color("ffd9b0"); sun.light_energy = 0.95
	sun.shadow_enabled = true
	add_child(sun)
	cam = Camera3D.new(); cam.fov = 38.0; cam.far = 3000.0; add_child(cam)
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(4000, 4000)
	sea.mesh = pm
	var cm := ShaderMaterial.new(); cm.shader = load("res://shaders/clouds.gdshader")
	sea.material_override = cm
	sea.position = Vector3(0, -16.0, 0)
	add_child(sea)
	# the island
	Models.part(self, Models.cyl(4.2, 3.8, 0.5, 30), Models.toon(Color("5f8d45")), Vector3(0, -0.25, 0))
	Models.part(self, Models.cyl(3.8, 1.6, 3.0, 30), Models.toon(Color("8b6d52")), Vector3(0, -2.0, 0))
	Models.part(self, Models.cyl(1.6, 0.2, 2.0, 20), Models.toon(Color("5a4a44")), Vector3(0, -4.5, 0))
	var house := Models.house(); house.position = Vector3(-1.2, 0, -1.8); house.scale = Vector3.ONE * 0.62; house.rotation.y = 0.35
	add_child(house)
	var drng := RandomNumberGenerator.new(); drng.seed = 21
	for p in [Vector3(2.6, 0, -1.6), Vector3(-3.1, 0, 0.6), Vector3(3.0, 0, 1.4)]:
		var tr := Models.tree(drng, Color("5a9a4f")); tr.position = p; add_child(tr)
	var lamp := Models.lamp(); lamp.position = Vector3(1.6, 0, 0.6); add_child(lamp)
	for i in 4:
		var a := TAU * i / 4.0 + 0.6
		var fb := Models.flower_bed(drng, 4); fb.position = Vector3(cos(a) * 3.0, 0, sin(a) * 2.6); fb.scale = Vector3.ONE * 0.8
		add_child(fb)
	var portal := Models.portal(UI.TEAL); portal.position = Vector3(2.6, 0, -0.2); portal.scale = Vector3.ONE * 0.6; portal.rotation.y = -1.0
	portal.get_node("Disc").visible = true
	add_child(portal)
	(portal.get_node("Beam") as CPUParticles3D).emitting = true
	# your hunter and partner, if you have one
	var hero: String = Save.d.get("hero", "")
	if not Data.HEROES.has(hero): hero = "sage"
	var w: String = Save.d.get("weapon", "")
	if not Data.CLASSES[Data.HEROES[hero]["cls"]]["weapons"].has(w): w = Data.HEROES[hero]["weapon"]
	hunter_node = Models.hunter(Data.HEROES[hero]["cls"], Data.TEAM_COLORS[0], w, hero, Save.d.get("look", {}))
	hunter_node.position = Vector3(0.2, 0, 0.3); hunter_node.rotation.y = 2.6
	add_child(hunter_node)
	var ak := Save.active_kin()
	if not ak.is_empty():
		kin_node = Models.kin(ak["species"], ak)
		kin_node.position = Vector3(1.0, 0, 0.9)
		add_child(kin_node)
	var drift := RandomNumberGenerator.new(); drift.seed = 5
	for k in 18:
		var r := Models.rock(drift, drift.randf_range(0.5, 1.6))
		var a := drift.randf() * TAU
		r.position = Vector3(cos(a) * drift.randf_range(9, 22), drift.randf_range(-9, -2), sin(a) * drift.randf_range(9, 22))
		add_child(r)
	_build_ui()

func _build_ui() -> void:
	var ui := CanvasLayer.new(); add_child(ui)
	var root := Control.new(); root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.theme = UI.theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	# a soft shade behind the menu so it reads over the scene
	var shade := TextureRect.new()
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.set_color(0, Color(0.03, 0.04, 0.08, 0.82)); gr.set_color(1, Color(0.03, 0.04, 0.08, 0.0))
	gr.set_offset(0, 0.35); gr.set_offset(1, 1.0)
	gt.gradient = gr; gt.fill_from = Vector2(0, 0); gt.fill_to = Vector2(1, 0); gt.width = 256; gt.height = 4
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	shade.offset_right = 760
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	# the menu column stays vertically centred and fits any window height
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	col.offset_left = 80; col.offset_right = 400; col.offset_top = 24; col.offset_bottom = -40
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 12)
	root.add_child(col)
	var logo := UI.title("KINFALL", 88, UI.ACCENT)
	logo.add_theme_constant_override("outline_size", 18)
	logo.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.08))
	col.add_child(logo)
	var tag := UI.label("Raise them. Risk them. Bring them home.", 20, UI.INK)
	tag.autowrap_mode = TextServer.AUTOWRAP_OFF
	col.add_child(tag)
	col.add_child(UI.spacer(8))
	var has: bool = not Save.d["roster"].is_empty()
	var b1 := UI.primary(("Continue  ·  %s" % Save.d.get("name", "Hunter")) if has else "New game", func(): Game.goto("home" if has else "hatch"), 300)
	col.add_child(b1)
	col.add_child(UI.button("Save files", func(): Overlay.ctx = "title"; Overlay.open_saves(), 300))
	if Bridge.net_available():
		col.add_child(UI.button("Play online with friends", func(): Game.goto("lobby", {}), 300))
	var srv := UI.button("Servers  ·  coming soon", func(): pass, 300)
	srv.disabled = true
	srv.tooltip_text = "Dedicated servers are on the way. For now, play online with friends from the lobby."
	col.add_child(srv)
	col.add_child(UI.button("Settings", func(): Overlay.ctx = "title"; Overlay.open_settings(), 300))
	if not OS.has_feature("web"):
		col.add_child(UI.button("Quit", func(): get_tree().quit(), 300))
	var i := 0
	for ch in col.get_children():
		UI.pop_in(ch, 0.15 + i * 0.08)
		i += 1
	var ver := UI.label("Open source · made with Godot", 13, UI.MUTED)
	ver.autowrap_mode = TextServer.AUTOWRAP_OFF
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	ver.position = Vector2(24, -36)
	root.add_child(ver)
	b1.grab_focus()

func _process(delta: float) -> void:
	t += delta
	var a := 0.9 + t * 0.06
	cam.position = Vector3(cos(a) * 11.0, 4.6 + sin(t * 0.3) * 0.4, sin(a) * 11.0) + Vector3(-2.5, 0, 0)
	cam.look_at(Vector3(-1.2, 0.6, 0), Vector3.UP)
	if kin_node:
		kin_node.get_node("Body").position.y = absf(sin(t * 3.0)) * 0.12
		kin_node.rotation.y = sin(t * 0.7) * 0.6 + 2.4
	if hunter_node:
		hunter_node.get_node("Rig/Torso").position.y = 0.42 + sin(t * 1.6) * 0.015
