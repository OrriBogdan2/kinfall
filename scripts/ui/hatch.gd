extends Node3D
## The first thing a new player sees: a short story, then three eggs on a little island. Pick one,
## keep it warm until it hatches, name what comes out, then head into the tutorial match together.

## The three starter eggs plus a mystery one. Names, tempers and blurbs come from each species'
## "egg" block in content/kin/<id>.json, so every egg is named for its element (Venom Egg, ...).
const STARTERS := ["cindle", "puddlet", "burrlet"]
const MYSTERY := {"species": "mystery", "name": "Mystery Egg", "temper": "???", "desc": "Speckled, and strangely quiet. Nobody knows what's inside.",
	"play": "Something that isn't any of the other three. You'll find out when it hatches."}

static func starter_eggs() -> Array:
	var out: Array = []
	for sp in STARTERS:
		var e: Dictionary = Data.egg_info(sp)
		e["species"] = sp
		for k in ["temper", "desc", "play"]:
			if not e.has(k): e[k] = ""
		out.append(e)
	out.append(MYSTERY.duplicate())
	return out

const STORY := [
	"The night after the storm, the old shrine on your island\nstarted to glow.",
	"When you went to look, there were eggs waiting in the light.\nThree of them, still warm.",
	"Kin choose their hunters.\nToday, one of them is going to choose you.",
]

var cam: Camera3D
var fx: Fx
var eggs: Array = []          # {node, base, data}
var chosen := -1
var stage := "intro"          # intro | pick | warm | hatching | name
var story_i := 0
var story_lbl: Label
var story_box: Control
var warmth := 0.0
var warm_bar: Control
var hover := -1
var auto_warm := false        # test hook: hold the warmth on by itself
var t := 0.0
var hatch_t := 0.0
var warm_step := 0
var kin_node: Node3D
var ui: CanvasLayer
var root_ui: Control
var bottom: VBoxContainer
var title: Label
var cam_from := Vector3(0, 3.6, 6.4)
var egg_defs: Array = []      # EGGS with the mystery egg's species decided
var look: Dictionary = {}
var preview: Node3D
var look_at_t := Vector3(0, 0.25, 0.5)
var edit_only := false
var create_box: Control
var sub_lbl: Label        # opened from the menu just to change how you look
var cam_to := Vector3(0, 3.6, 6.4)

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.play_music("title")
	Sfx.play_ambience("home")
	var env := WorldEnvironment.new()
	env.environment = Look.environment({"top": Color("1a1440"), "mid": Color("7a3a9a"), "horizon": Color("ffa860"), "below": Color("2a1e4a"),
		"sun_dir": Vector3(0.2, 0.12, -0.97), "sun_col": Color("ffd09a"),
		"ambient": Color("c8cdf0"), "ambient_energy": 0.5, "fog": Color("6a5aa8"), "fog_height": -6.0, "stars": 0.7})
	add_child(env)
	Look.lights(self, Color("ffe2c4"), 1.0, Vector3(-40, -25, 0), 30.0)
	# a warm rim light from behind, so everything on the dais gets a glowing outline
	var rim := DirectionalLight3D.new(); rim.light_color = Color("9ad8ff"); rim.light_energy = 0.55
	rim.rotation_degrees = Vector3(-20, 180, 0); add_child(rim)
	fx = Fx.new(); add_child(fx)
	cam = Camera3D.new(); cam.fov = 40.0; add_child(cam)
	cam.position = cam_from
	cam.look_at(Vector3(0, 0.6, 0))
	_build_set()
	egg_defs = starter_eggs()
	var others: Array = Data.KIN.keys().filter(func(k): return not k in ["cindle", "puddlet", "burrlet"])
	for d in egg_defs:
		if d["species"] == "mystery":
			d["species"] = others[randi() % others.size()] if others.size() > 0 else "cindle"
			d["mystery"] = true
	for i in egg_defs.size():
		var d: Dictionary = egg_defs[i]
		var sp: Dictionary = Data.KIN[d["species"]]
		var holder := Node3D.new()
		var x := -2.55 + i * 1.7
		holder.position = Vector3(x, 0, 0.2)
		add_child(holder)
		var nest := Models.nest(); nest.scale = Vector3.ONE * 0.8
		for ch in nest.get_children():
			if ch is MeshInstance3D and (ch as MeshInstance3D).mesh is SphereMesh:
				ch.visible = false
		holder.add_child(nest)
		var egg := EggHatch.new(d["species"], fx, 0.32, 0.42, 1.1)
		if d.get("mystery", false):
			egg.shell_col = Color("c4bcd6"); egg.spot_col = Color("6a5a8a")
		egg.hop_out = 0.35
		egg.position = Vector3(0, 0.12, 0)
		holder.add_child(egg)
		eggs.append({"holder": holder, "egg": egg, "base": holder.position, "data": d})
	_build_ui()
	cam_from = Vector3(-9, 7.5, 16); cam.position = cam_from
	cam_to = Vector3(-3.5, 4.2, 9.0)
	if edit_only:
		stage = "intro"
		_end_intro()
	elif "--skip-intro" in OS.get_cmdline_user_args() or Save.d["tutorial"].get("intro", false):
		_end_intro()
	else:
		_show_story()
	if "--hatch-pick" in OS.get_cmdline_user_args():
		# test: straight to choosing an egg
		if not Save.d.has("look"): Save.d["look"] = Models.default_look()
		_end_intro()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hatch-auto="):
			var i := int(a.substr(13))
			if not Save.d.has("look"): Save.d["look"] = Models.default_look()
			_end_intro()
			_pick(i); _pick(i)
			auto_warm = true

## The set for a new game: a carved stone dais floating at dusk, a rune circle glowing under your
## feet, a broken arch behind with the old world's heart-crystal turning inside it, lanterns and
## banners, rocks drifting round in a slow orbit, wild kin watching from the edges, fireflies,
## a waterfall pouring off into the clouds, and the islands and a skyship far behind.
var orbit: Node3D
var runes: Array = []
var crystal: Node3D
func _build_set() -> void:
	var rr := RandomNumberGenerator.new(); rr.seed = 3
	var stone := Models.toon(Color("d9d2c4"))
	var stone_d := Models.toon(Color("8f8aa0"))
	var gold := Models.toon(Color("f2c46a"), true, 0.4)
	# the floating rock and the dais on top
	var base := Models.float_island(rr, 3.9, 8.0, Color("b9ad96"), Color("8a6f5a"), Color("3a2a4a"))
	base.position.y = -0.32
	add_child(base)
	var dais := Models.part(self, Models.cyl(3.9, 4.1, 0.5, 40), stone, Vector3(0, -0.24, 0))
	dais.name = "Ground"
	Models.part(self, Models.cyl(3.2, 3.2, 0.04, 40), Models.toon(Color("a99c86")), Vector3(0, 0.02, 0))
	for i in 24:
		var a := TAU * i / 24.0
		var bl := Models.part(self, Models.box(0.6, 0.22, 0.3), stone_d if i % 2 == 0 else stone, Vector3(cos(a) * 3.95, 0.06, sin(a) * 3.95))
		bl.rotation.y = -a
	# rune circles: a wide gold one and a smaller cyan one turning the other way
	for spec in [[6.6, Color(1.0, 0.8, 0.4, 0.85), 0.05, 0.25], [4.2, Color(0.55, 0.95, 1.0, 0.7), 0.07, -0.4]]:
		var rn := MeshInstance3D.new(); rn.mesh = Models.flat_quad(float(spec[0]))
		rn.material_override = Models.ring_mat(spec[1], float(spec[2]))
		rn.position.y = 0.05
		rn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(rn)
		runes.append([rn, float(spec[3])])
	for i in 8:
		var a := TAU * i / 8.0 + 0.2
		var gl := Models.part(self, Models.box(0.12, 0.03, 0.34), Models.glow_mat(Color(1.0, 0.85, 0.5, 0.9)), Vector3(cos(a) * 3.0, 0.05, sin(a) * 3.0))
		gl.rotation.y = -a
	# a waterfall pouring off the edge into the clouds
	var wf := Models.waterfall(1.1, 12.0); wf.position = Vector3(3.3, -0.1, -1.6); wf.rotation.y = -0.9
	add_child(wf)
	# the broken arch behind, and the heart-crystal turning inside it
	var arch_c := Vector3(0, -0.2, -5.2)
	for i in 15:
		if i in [10, 11]:
			continue                       # broken off near the top
		var a := PI * i / 14.0
		var bp := arch_c + Vector3(cos(a) * 4.6, sin(a) * 4.6, 0)
		var blk := Models.part(self, Models.box(0.95, 0.75, 0.9), stone if i % 3 else stone_d, bp)
		blk.rotation.z = a - PI * 0.5
	for k in 3:
		var fr := Models.rock(rr, rr.randf_range(0.25, 0.45), Color("cdbfa6"))
		fr.position = arch_c + Vector3(-2.6 + k * 0.7, 4.6 + k * 0.5, 0.3)
		add_child(fr)
		PropAnim.on(fr, 0.3, 0.25, 0.6 + k * 0.2)
	crystal = Node3D.new(); crystal.position = arch_c + Vector3(0, 2.8, 0); add_child(crystal)
	var cm := Models.toon(Color("8ae8ff"), true, 1.4)
	var pm := PrismMesh.new(); pm.size = Vector3(1.1, 2.4, 1.1)
	Models.part(crystal, pm, cm, Vector3(0, 0.6, 0))
	Models.part(crystal, pm, cm, Vector3(0, -0.8, 0), Vector3(1.0, 0.6, 1.0), Vector3(PI, 0, 0))
	for i in 5:
		var a := TAU * i / 5.0
		Models.part(crystal, pm, cm, Vector3(cos(a) * 0.8, -0.2, sin(a) * 0.8), Vector3(0.35, 0.4, 0.35), Vector3(sin(a) * 0.5, 0, -cos(a) * 0.5))
	var cl := OmniLight3D.new(); cl.light_color = Color("8ae8ff"); cl.light_energy = 2.2; cl.omni_range = 9.0; crystal.add_child(cl)
	var beam := Models.part(self, Models.cyl(0.5, 1.4, 30.0, 16), Models.glow_mat(Color(0.55, 0.9, 1.0, 0.16)), arch_c + Vector3(0, 14.0, -0.4))
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# lantern posts and banners either side
	for sx in [-1.0, 1.0]:
		var post := Vector3(sx * 3.35, 0, -1.9)
		Models.part(self, Models.cyl(0.16, 0.22, 2.4, 10), stone_d, post + Vector3(0, 1.2, 0))
		Models.part(self, Models.box(0.5, 0.12, 0.5), gold, post + Vector3(0, 2.45, 0))
		var lan := Models.part(self, Models.sphere(0.22, 12), Models.glow_mat(Color(1.0, 0.75, 0.4, 0.95)), post + Vector3(0, 2.75, 0))
		lan.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ol := OmniLight3D.new(); ol.light_color = Color("ffb36a"); ol.light_energy = 1.6; ol.omni_range = 5.5
		ol.position = post + Vector3(0, 2.75, 0); add_child(ol)
		var bn := Models.banner(UI.ACCENT if sx < 0 else Color("8ae8ff")); bn.position = post + Vector3(sx * -0.5, 0, 0.35); add_child(bn)
	# rocks drifting round in a slow orbit
	orbit = Node3D.new(); add_child(orbit)
	for k in 12:
		var a := TAU * k / 12.0 + rr.randf_range(-0.2, 0.2)
		var rad := rr.randf_range(7.5, 12.0)
		var rk := Models.rock(rr, rr.randf_range(0.4, 1.3), Color("8fb86a"))
		rk.position = Vector3(cos(a) * rad, rr.randf_range(-3.0, 3.5), sin(a) * rad)
		orbit.add_child(rk)
	# wild kin watching from little rocks at the edges
	for spec in [["zapple", Vector3(-5.6, -0.4, -2.4)], ["wisplet", Vector3(5.9, 0.4, -3.2)], ["pebbit", Vector3(-7.4, 1.2, -6.0)]]:
		var perch := Models.float_island(rr, 0.9, 1.6, Color("7ab85a"), Color("8a6f5a"), Color("3a2a4a"))
		perch.position = spec[1]; add_child(perch)
		PropAnim.on(perch, 0.0, 0.18, 0.5 + rr.randf() * 0.4)
		if Data.KIN.has(spec[0]):
			var wk := Models.kin(spec[0], {"level": 3})
			wk.position = Vector3(0, 0.05, 0); wk.rotation.y = atan2(-(0.0 - (spec[1] as Vector3).x), -(2.0 - (spec[1] as Vector3).z))
			wk.set_meta("happy", true)
			perch.add_child(wk)
	# fireflies over the dais and petals drifting past
	var ff := CPUParticles3D.new()
	ff.amount = 60; ff.lifetime = 5.0; ff.preprocess = 5.0
	ff.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX; ff.emission_box_extents = Vector3(7.0, 2.0, 5.0)
	ff.position = Vector3(0, 1.8, -1.0)
	ff.direction = Vector3.UP; ff.spread = 180.0; ff.initial_velocity_min = 0.1; ff.initial_velocity_max = 0.4; ff.gravity = Vector3(0, 0.05, 0)
	var fgr := Gradient.new(); fgr.set_color(0, Color(1, 0.85, 0.4, 0)); fgr.set_color(1, Color(1, 0.85, 0.4, 0)); fgr.add_point(0.5, Color(1, 0.9, 0.5, 1))
	ff.color_ramp = fgr
	var fm := SphereMesh.new(); fm.radius = 0.04; fm.height = 0.08; fm.radial_segments = 6; fm.rings = 3
	var fmat := StandardMaterial3D.new(); fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; fmat.vertex_color_use_as_albedo = true
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; fmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.material = fmat; ff.mesh = fm
	add_child(ff)
	var pt := CPUParticles3D.new()
	pt.amount = 40; pt.lifetime = 7.0; pt.preprocess = 7.0
	pt.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX; pt.emission_box_extents = Vector3(10.0, 1.0, 6.0)
	pt.position = Vector3(-4.0, 5.0, -2.0)
	pt.direction = Vector3(1, -0.3, 0.2); pt.spread = 25.0; pt.initial_velocity_min = 0.6; pt.initial_velocity_max = 1.2; pt.gravity = Vector3(0, -0.25, 0)
	pt.angular_velocity_min = -90.0; pt.angular_velocity_max = 90.0
	var pq := QuadMesh.new(); pq.size = Vector2(0.09, 0.06)
	var pmat := StandardMaterial3D.new(); pmat.albedo_color = Color("ffb3d0"); pmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pq.material = pmat; pt.mesh = pq
	add_child(pt)
	# the cloud sea, far islands and a skyship passing
	var sea := MeshInstance3D.new()
	var spm := PlaneMesh.new(); spm.size = Vector2(4000, 4000)
	sea.mesh = spm
	var sm := ShaderMaterial.new(); sm.shader = load("res://shaders/clouds.gdshader")
	sm.set_shader_parameter("deep", Color("221a4e")); sm.set_shader_parameter("light", Color("8f86d4"))
	sm.set_shader_parameter("glow", Color("ffb070")); sm.set_shader_parameter("glow_amount", 0.9)
	sm.set_shader_parameter("sun_xz", Vector2(0.2, -0.97))
	sea.material_override = sm
	sea.position = Vector3(0, -14.0, -20.0)
	add_child(sea)
	for k in 7:
		var isl := Scenery.island(rr, rr.randf_range(3.0, 7.0), true, rr.randf() < 0.5)
		isl.position = Vector3(rr.randf_range(-60, 60), rr.randf_range(-8, 6), rr.randf_range(-70, -30))
		add_child(isl)
	ship = Models.skyship(); ship.position = Vector3(-40, 9, -45); ship.rotation.y = -PI / 2; ship.scale = Vector3.ONE * 1.2
	add_child(ship)
var ship: Node3D

func _build_ui() -> void:
	ui = CanvasLayer.new(); add_child(ui)
	root_ui = Control.new(); root_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root_ui.theme = UI.theme()
	root_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root_ui)
	# a soft dark vignette pulls the eye to the middle, like a stage
	var vg := TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL; gt.fill_from = Vector2(0.5, 0.45); gt.fill_to = Vector2(1.05, 1.05)
	var gg := Gradient.new(); gg.set_color(0, Color(0.05, 0.02, 0.1, 0.0)); gg.set_color(1, Color(0.05, 0.02, 0.1, 0.7)); gg.add_point(0.55, Color(0.05, 0.02, 0.1, 0.0))
	gt.gradient = gg
	vg.texture = gt; vg.stretch_mode = TextureRect.STRETCH_SCALE
	vg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); vg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_ui.add_child(vg)
	var top := VBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.position.y = 36
	title = UI.title("Choose your first kin", 40, UI.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_constant_override("outline_size", 12)
	title.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.09, 0.85))
	top.add_child(title)
	var sub := UI.label("Every kin is different. It will remember how you treat it.", 16, Color(1, 0.95, 0.88, 0.9))
	sub.add_theme_constant_override("outline_size", 6)
	sub.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.09, 0.8))
	sub_lbl = sub
	sub.autowrap_mode = TextServer.AUTOWRAP_OFF
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(sub)
	root_ui.add_child(top)
	var holder := CenterContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	holder.offset_top = -330
	holder.offset_bottom = -14
	holder.grow_vertical = Control.GROW_DIRECTION_BEGIN     # a tall card grows up, never off the bottom
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_ui.add_child(holder)
	bottom = UI.vbox(10)
	holder.add_child(bottom)
	_show_pick()

# ---- the story
func _show_story() -> void:
	stage = "intro"
	_clear_bottom()
	title.get_parent().visible = false
	var shade := ColorRect.new(); shade.color = Color(0.02, 0.03, 0.06, 0.45)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.name = "Shade"
	root_ui.add_child(shade)
	story_box = UI.vbox(18)
	story_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	story_box.alignment = BoxContainer.ALIGNMENT_CENTER
	story_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story_lbl = UI.title("", 30, UI.INK)
	story_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	story_lbl.add_theme_constant_override("outline_size", 10)
	story_lbl.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.07))
	story_box.add_child(story_lbl)
	var hint := UI.key_hints([["Space", "continue"]], 12, Color(1, 1, 1, 0.55))
	hint.alignment = BoxContainer.ALIGNMENT_CENTER
	story_box.add_child(hint)
	root_ui.add_child(story_box)
	var skip := HoldSkip.new()
	skip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	skip.offset_left = -196; skip.offset_right = -24; skip.offset_top = 18; skip.offset_bottom = 62
	skip.skipped.connect(_end_intro)
	skip.name = "SkipIntro"
	root_ui.add_child(skip)
	_story_line()

func _story_line() -> void:
	story_lbl.text = STORY[story_i]
	story_lbl.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(story_lbl, "modulate:a", 1.0, 0.8)
	Sfx.play("whoosh", null, -16.0)
	# the camera drifts closer with each line
	var k := float(story_i + 1) / STORY.size()
	cam_to = Vector3(-9, 7.5, 16).lerp(Vector3(0, 3.6, 6.4), k * 0.85)

func _next_story() -> void:
	story_i += 1
	if story_i >= STORY.size():
		_end_intro()
	else:
		_story_line()

func _end_intro() -> void:
	if stage != "intro":
		return
	stage = "pick"
	Save.d["tutorial"]["intro"] = true
	for n in ["Shade", "SkipIntro"]:
		var c := root_ui.get_node_or_null(n)
		if c: c.queue_free()
	if story_box: story_box.queue_free()
	title.get_parent().visible = true
	if not Save.d.has("look") or edit_only or "--create" in OS.get_cmdline_user_args():
		_show_create()
	else:
		cam_to = Vector3(0, 3.6, 6.4)
		_show_pick()

var turning := false
func _unhandled_input(event: InputEvent) -> void:
	if stage == "create" and preview:
		# drag with the mouse (or hold A / D) to turn your hunter round
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			turning = event.pressed
		elif event is InputEventMouseMotion and turning:
			preview.rotation.y += event.relative.x * 0.012
			return
	if stage == "warm" and ((event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or event.is_action_pressed("jump")):
		_tap_egg()
		return
	if stage == "intro":
		if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or event.is_action_pressed("jump") or event.is_action_pressed("ui_accept"):
			_next_story()
		return
	if stage == "pick" and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and hover >= 0:
		_pick(hover)

## Which egg the mouse is over, by distance on screen.
func _egg_under_mouse() -> int:
	var mp := get_viewport().get_mouse_position()
	var best := -1; var bd := 70.0
	for i in eggs.size():
		var p: Vector3 = (eggs[i]["holder"] as Node3D).global_position + Vector3(0, 0.45, 0)
		if cam.is_position_behind(p): continue
		var d := cam.unproject_position(p).distance_to(mp)
		if d < bd: bd = d; best = i
	return best

func _clear_bottom() -> void:
	for ch in bottom.get_children():
		ch.queue_free()

# ---- your hunter
const LOOK_ROWS := [["race", "Race", Models.LOOK_RACES], ["gender", "Gender", Models.LOOK_GENDERS], ["body", "Body", Models.LOOK_BODIES], ["face", "Face", Models.LOOK_FACES],
	["detail", "Details", Models.LOOK_DETAILS], ["skin", "Skin", Models.LOOK_SKIN], ["hair", "Hair", Models.LOOK_HAIRS], ["hair_col", "Hair colour", Models.LOOK_HAIR], ["outfit", "Outfit", Models.LOOK_OUTFITS]]

func _show_create() -> void:
	stage = "create"
	if look.is_empty():
		look = Models.clean_look(Save.d.get("look", {}))
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--create-race="):   # test: open the creator on a race
				look["race"] = int(a.substr(14)); look["skin"] = int(Models.RACES[int(look["race"])]["skin"])
	title.text = "Make your hunter"
	_clear_bottom()
	if create_box: create_box.queue_free()
	_rebuild_preview()
	for e in eggs: (e["holder"] as Node3D).visible = false
	if sub_lbl: sub_lbl.text = "Drag your hunter (or hold A / D) to turn them round."
	cam_to = Vector3(0, 1.5, 4.6)
	look_at_t = Vector3(0.0, 0.9, 1.6)
	var card := UI.card(UI.CARD, 14, 16)
	card.custom_minimum_size = Vector2(500, 0)
	create_box = card
	var v := UI.vbox(8); card.add_child(v)
	for row in LOOK_ROWS:
		var key: String = row[0]
		var opts: Array = row[2]
		var hr := UI.hbox(8)
		var l := UI.label(row[1], UI.T_BODY, UI.MUTED); l.custom_minimum_size.x = 120
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hr.add_child(l)
		hr.add_child(UI.icon_button("back", func(): _step_look(key, -1, opts.size()), "Previous", 12.0))
		var val := UI.label("", UI.T_BODY, UI.INK, UI.semi); val.custom_minimum_size.x = 170
		val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var i := int(look[key])
		if opts[0] is Color:
			var sw := Panel.new(); sw.custom_minimum_size = Vector2(170, 26)
			var ssb := UI._box(opts[i], 13, Color(1, 1, 1, 0.25), 1)
			sw.add_theme_stylebox_override("panel", ssb)
			sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			hr.add_child(sw)
		else:
			val.text = String(opts[i])
			hr.add_child(val)
		hr.add_child(UI.icon_button("next", func(): _step_look(key, 1, opts.size()), "Next", 12.0))
		v.add_child(hr)
		if key == "race":
			var rd := UI.label(String(Models.RACES[int(look["race"])]["desc"]), UI.T_SMALL, UI.ACCENT_HI)
			rd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			rd.custom_minimum_size.x = 380
			var rm := MarginContainer.new(); rm.add_theme_constant_override("margin_left", 128); rm.add_child(rd)
			v.add_child(rm)
	var nr := UI.hbox(8)
	var nl := UI.label("Your name", UI.T_BODY, UI.MUTED); nl.custom_minimum_size.x = 120
	nr.add_child(nl)
	var ne := LineEdit.new(); ne.text = Save.d.get("name", "Hunter"); ne.max_length = 16; ne.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ne.text_changed.connect(func(t): Save.d["name"] = t.strip_edges() if t.strip_edges() != "" else "Hunter")
	nr.add_child(ne)
	v.add_child(nr)
	var br := UI.hbox(10)
	br.alignment = BoxContainer.ALIGNMENT_END
	br.add_child(UI.ghost("Random", func():
		look = Models.random_look()
		_show_create(), 120, "swap"))
	br.add_child(UI.primary("Looks good", func():
		Save.d["look"] = look.duplicate()
		Save.save_game()
		Sfx.play("click")
		if preview: preview.queue_free()
		preview = null
		if create_box: create_box.queue_free()
		create_box = null
		for e in eggs: (e["holder"] as Node3D).visible = true
		if sub_lbl: sub_lbl.text = "Every kin is different. It will remember how you treat it."
		if edit_only or Save.d.get("tutorial", {}).get("hatched", false):
			Game.goto("home")
			return
		stage = "pick"
		title.text = "Choose your first kin"
		cam_to = Vector3(0, 3.6, 6.4)
		_show_pick(), 200))
	v.add_child(br)
	root_ui.add_child(card)
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT, Control.PRESET_MODE_MINSIZE, 48)
	card.offset_top += 46; card.offset_bottom += 46       # clear of the title

func _step_look(key: String, d: int, n: int) -> void:
	look[key] = posmod(int(look[key]) + d, n)
	Sfx.play("hover", null, -6.0)
	if key == "race":
		# each race starts in its own colouring; you can still change the skin after
		look["skin"] = int(Models.RACES[int(look["race"])]["skin"])
	_show_create()

var preview_yaw := PI
func _rebuild_preview() -> void:
	if preview:
		preview_yaw = preview.rotation.y
		preview.queue_free()
	preview = Models.hunter(Data.class_of_save(), Data.TEAM_COLORS[0], Data.weapon_for(Data.class_of_save(), String(Save.d.get("weapon", ""))), "", look)
	preview.position = Vector3(0.8, 0, 1.6)
	preview.rotation.y = preview_yaw
	add_child(preview)

func _show_pick() -> void:
	_clear_bottom()
	var row := UI.hbox(14)
	for i in egg_defs.size():
		var d: Dictionary = egg_defs[i]
		var mystery: bool = d.get("mystery", false)
		var card := UI.card(UI.CARD, 12, 14)
		card.custom_minimum_size = Vector2(228, 0)
		if i == chosen:
			UI.set_card_border(card, UI.ACCENT)
		var v := UI.vbox(6); card.add_child(v)
		var hr := UI.hbox(8)
		var ecol: Color = Color("c4bcd6") if mystery else Data.KIN[d["species"]]["color"]
		while ecol.get_luminance() < 0.55:
			ecol = ecol.lerp(Color.WHITE, 0.2)     # dark shells still need a readable name
		var tt := UI.title(d["name"], 22, ecol); tt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hr.add_child(tt)
		hr.add_child(UI.section(d["temper"], ecol))
		v.add_child(hr)
		var dl := UI.label(d["desc"], 14, UI.MUTED)
		dl.custom_minimum_size.x = 200
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(dl)
		if i == chosen:
			var pl := UI.label(d["play"], 13, UI.INK)
			pl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(pl)
		var ii := i
		v.add_child((UI.primary if i == chosen else UI.button).call("This one" if i != chosen else "Hatch it", func(): _pick(ii)))
		row.add_child(card)
	bottom.add_child(row)

func _pick(i: int) -> void:
	if stage != "pick":
		return
	if chosen == i:
		_start_hatch()
		return
	chosen = i
	Sfx.play("click")
	var e: Dictionary = eggs[i]
	fx.burst(e["holder"].position + Vector3(0, 0.6, 0), Data.KIN[e["data"]["species"]]["color"], 10, 2.0, 0.5, 2.0)
	_show_pick()

## Hatching by knocks: each tap hits harder than the last. The egg jumps higher and twists further,
## the camera punches in, the sound climbs in pitch, sparks fly, a new crack opens, and the last
## few knocks flash the screen before it bursts.
const TAPS := 7
var taps := 0
var cam_shake := 0.0
func _tap_egg() -> void:
	if taps >= TAPS or chosen < 0:
		return
	taps += 1
	var k := float(taps) / TAPS
	var wegg: EggHatch = eggs[chosen]["egg"]
	var holder: Node3D = eggs[chosen]["holder"]
	var col: Color = Color("ffd36a").lerp(Color(Data.KIN[egg_defs[chosen]["species"]]["color"]), k)
	# a jump and a twist that grow with every knock
	var hop := create_tween()
	var up := 0.12 + 0.1 + 0.32 * k
	hop.tween_property(wegg, "position:y", up, 0.09 + 0.05 * k).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hop.tween_property(wegg, "position:y", 0.12, 0.12 + 0.06 * k).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	wegg.rotation.z = (0.12 + 0.45 * k) * (1.0 if taps % 2 == 0 else -1.0)
	var sq := create_tween()
	wegg.scale = Vector3(1.0 + 0.12 + 0.2 * k, 1.0 - 0.1 - 0.15 * k, 1.0 + 0.12 + 0.2 * k)
	sq.tween_property(wegg, "scale", Vector3.ONE, 0.25 + 0.1 * k).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	# a new crack each time
	var base := 8 + taps * 3
	wegg._crack(base, base + 2 + int(k * 2.0))
	# sparks, sound and camera
	fx.burst(holder.position + Vector3(0, 0.5, 0), col, int(4 + 26 * k), 1.5 + 4.0 * k, 0.4 + 0.3 * k, -2.0)
	if taps >= TAPS - 2:
		fx.ring(holder.position + Vector3(0, 0.05, 0), 0.8 + 1.4 * k, col, 0.35)
	Sfx.play("hit", null, -10.0 + 10.0 * k, 0.02, 0.8 + 0.7 * k)
	if taps >= 4: Sfx.play("thump", null, -12.0 + 8.0 * k, 0.02, 1.2 - 0.3 * k)
	cam_shake = 0.02 + 0.16 * k * k
	cam_to = Vector3(0, 2.5, 5.4).lerp(Vector3(0, 1.8, 3.9), k)
	if taps >= TAPS - 1:
		var fl := ColorRect.new(); fl.color = Color(1, 0.95, 0.85, 0.25 + 0.35 * k)
		fl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root_ui.add_child(fl)
		create_tween().tween_property(fl, "color:a", 0.0, 0.35).finished.connect(fl.queue_free)
	if title:
		title.text = ["Help it hatch", "Something stirs...", "It knocks back!", "Again!", "Harder!", "It's cracking!", "One more!", "Here it comes!"][mini(taps, 7)]

func _start_hatch() -> void:
	stage = "warm"
	hatch_t = 0.0
	_clear_bottom()
	title.text = "Help it hatch"
	taps = 0
	var card := UI.card(UI.CARD, 14, 16)
	card.custom_minimum_size = Vector2(460, 0)
	var v := UI.vbox(10); card.add_child(v)
	var l := UI.label("Tap the egg: click (or press Space) again and again. Every knock wakes it a little more.", 15)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)
	warm_bar = Control.new()
	warm_bar.custom_minimum_size = Vector2(420, 16)
	warm_bar.draw.connect(func():
		var bg := StyleBoxFlat.new(); bg.bg_color = Color(0, 0, 0, 0.45); bg.set_corner_radius_all(8)
		warm_bar.draw_style_box(bg, Rect2(Vector2.ZERO, warm_bar.size))
		if warmth > 0.01:
			var fg := StyleBoxFlat.new(); fg.bg_color = Color("ff9a5a").lerp(Color("ffd36a"), warmth); fg.set_corner_radius_all(8)
			warm_bar.draw_style_box(fg, Rect2(Vector2.ZERO, Vector2(warm_bar.size.x * warmth, warm_bar.size.y))))
	v.add_child(warm_bar)
	bottom.add_child(card)
	Sfx.play("whoosh")
	for i in eggs.size():
		var e: Dictionary = eggs[i]
		var tw := create_tween().set_trans(Tween.TRANS_SINE)
		if i == chosen:
			tw.tween_property(e["holder"], "position", Vector3(0, 0, 0.6), 0.7)
		else:
			tw.tween_property(e["holder"], "scale", Vector3.ONE * 0.01, 0.5)
	cam_to = Vector3(0, 2.5, 5.4)

func _process(delta: float) -> void:
	t += delta
	cam.position = cam.position.lerp(cam_to, minf(1.0, delta * 2.0))
	# a slow breathing drift so the shot is never quite still
	cam.position += Vector3(sin(t * 0.37) * 0.004, sin(t * 0.51) * 0.003, 0)
	for rn in runes:
		(rn[0] as Node3D).rotation.y += delta * float(rn[1])
	if orbit: orbit.rotation.y += delta * 0.04
	if crystal:
		crystal.rotation.y += delta * 0.5
		crystal.position.y = -0.2 + 2.8 + sin(t * 1.1) * 0.15
	if ship:
		ship.position.x += delta * 1.6
		if ship.position.x > 60.0: ship.position.x = -60.0
	if stage == "create":
		cam.look_at(look_at_t)
		if preview and not (get_viewport().gui_get_focus_owner() is LineEdit):
			preview.rotation.y += (Input.get_axis("left", "right")) * delta * 2.5
		pass   # the preview stands still; drag it to turn it (see _unhandled_input)
	else:
		cam.look_at(Vector3(0, (0.25 if stage != "pick" else 0.55) if stage != "name" else -0.55, 0.5))
	if stage == "pick":
		var hv := _egg_under_mouse()
		if hv != hover:
			hover = hv
			if hover >= 0: Sfx.play("hover", null, -12.0)
		for i in eggs.size():
			var hs := 1.12 if i == hover else 1.0
			var hn: Node3D = eggs[i]["holder"]
			hn.scale = hn.scale.lerp(Vector3.ONE * hs, minf(1.0, delta * 10.0))
	if cam_shake > 0.0:
		cam.position += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * cam_shake
		cam_shake = maxf(0.0, cam_shake - delta * 1.8)
	if stage == "warm" and chosen >= 0:
		if auto_warm and int(t * 3.0) != int((t - delta) * 3.0):
			_tap_egg()          # test hook: taps by itself
		warmth = lerpf(warmth, float(taps) / TAPS, minf(1.0, delta * 10.0))
		if warm_bar: warm_bar.queue_redraw()
		var wegg: EggHatch = eggs[chosen]["egg"]
		wegg.set_warmth(warmth)
		# between knocks it trembles, more and more the closer it is
		wegg.rotation.z = lerpf(wegg.rotation.z, sin(t * (6.0 + warmth * 30.0)) * warmth * 0.05, minf(1.0, delta * 12.0))
		if taps >= TAPS and warmth >= 0.98:
			stage = "hatching"
			title.text = "Something's moving..."
			_clear_bottom()
			wegg.rotation.z = 0.0
			wegg.position.y = 0.12
			wegg.popped.connect(func(k: Node3D):
				kin_node = k
				title.text = "It's a %s!" % Data.KIN[egg_defs[chosen]["species"]]["name"])
			wegg.done.connect(func():
				stage = "reveal"
				cam_to = Vector3(0, 2.2, 5.6)
				# the big reveal (flash, fanfare, turntable and info), then naming
				var rv := KinReveal.new(egg_defs[chosen]["species"])
				add_child(rv)
				rv.proceed.connect(func():
					stage = "name"
					_show_name()))
			wegg.start()
	for i in eggs.size():
		var egg: Node3D = eggs[i]["egg"]
		if stage == "pick":
			var lift := 0.12 if i == chosen else 0.0
			egg.position.y = lerpf(egg.position.y, 0.12 + lift + (sin(t * 3.0) * 0.03 if i == chosen else 0.0), minf(1.0, delta * 8.0))
			# a little wobble now and then, like something inside is awake
			egg.rotation.z = sin(t * 2.0 + i * 2.1) * 0.06 * (1.0 + float(sin(t * 0.7 + i) > 0.7) * 3.0)

func _show_name() -> void:
	_clear_bottom()
	var sp_id: String = egg_defs[chosen]["species"]
	var sp: Dictionary = Data.KIN[sp_id]
	var card := UI.card(UI.CARD, 16, 18)
	card.custom_minimum_size = Vector2(520, 0)
	var v := UI.vbox(10); card.add_child(v)
	v.add_child(UI.section("A new kin", sp["color"]))
	v.add_child(UI.title("Name your %s" % sp["name"], 34))
	v.add_child(UI.label("\"%s\"" % KinSpeak.babble(sp_id, "happy"), 22, sp["color"]))
	v.add_child(UI.label("It's %s, and it can only babble for now. Whatever you call it, it'll answer to." % String(sp["voice"]).split(",")[0], 16, UI.MUTED))
	var name_row := UI.hbox(8)
	var nl := UI.label("Its name", 15, UI.MUTED); nl.custom_minimum_size.x = 120
	name_row.add_child(nl)
	var ne := LineEdit.new(); ne.text = Data.KIN_NAMES.pick_random(); ne.max_length = 14; ne.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(ne)
	v.add_child(name_row)
	# a few ideas, and a button for a fresh handful
	var picks := UI.hbox(6)
	var fill_picks := func(self_ref: Callable) -> void:
		for ch in picks.get_children(): ch.queue_free()
		var il := UI.label("Ideas", 13, UI.MUTED); il.custom_minimum_size.x = 120; il.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		picks.add_child(il)
		var pool: Array = Data.KIN_NAMES.duplicate(); pool.shuffle()
		for nm in pool.slice(0, 4):
			var n2: String = nm
			picks.add_child(UI.button(n2, func(): ne.text = n2; ne.caret_column = n2.length()))
		var more := UI.button("More", func(): self_ref.call(self_ref))
		more.flat = true
		picks.add_child(more)
	fill_picks.call(fill_picks)
	v.add_child(picks)
	var you_row := UI.hbox(8)
	var yl := UI.label("Your name", 15, UI.MUTED); yl.custom_minimum_size.x = 120
	you_row.add_child(yl)
	var ye := LineEdit.new(); ye.text = Save.d.get("name", "Hunter"); ye.max_length = 16; ye.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	you_row.add_child(ye)
	v.add_child(you_row)
	# you already told us your name in the hunter creator; don't ask twice
	you_row.visible = not Save.d.has("look")
	var btns := UI.hbox(10)
	btns.add_child(UI.primary("Head out together", func(): _finish(sp_id, ne.text, ye.text, true), 240))
	var skip := UI.button("Skip the tutorial", func(): _finish(sp_id, ne.text, ye.text, false), 180)
	skip.flat = true
	btns.add_child(skip)
	v.add_child(btns)
	bottom.add_child(card)
	UI.pop_in(card)
	# Enter in either box is the same as "Head out together"
	ne.text_submitted.connect(func(_t): _finish(sp_id, ne.text, ye.text, true))
	ye.text_submitted.connect(func(_t): _finish(sp_id, ne.text, ye.text, true))
	ne.grab_focus()
	ne.select_all()

func _finish(sp_id: String, kname: String, you: String, tutorial: bool) -> void:
	var rec := Save.new_kin(sp_id, kname.strip_edges() if kname.strip_edges() != "" else Data.KIN_NAMES.pick_random())
	rec["trust"] = 55.0
	Save.remember(rec, "hatched", "hatched from an egg you chose")
	Save.d["roster"] = [rec]
	Save.d["active"] = rec["uid"]
	Save.d["name"] = you.strip_edges() if you.strip_edges() != "" else "Hunter"
	Save.d["tutorial"]["hatched"] = true
	Save.save_game()
	Sfx.play("click")
	if tutorial:
		Game.start_match({"tutorial": true, "teams": 1, "squad": 1, "tier": 0, "length": 1500.0})
	else:
		Save.d["tutorial"]["match"] = true
		Save.save_game()
		Game.goto("home")
