extends Node3D
## The prologue: a short animated telling of how the Skylands came to be, before your first egg.
## Seven shots, each a little set far apart from the others, with the camera gliding through them
## and a line of story under letterbox bars:
##   1. the world whole  2. the Wyrm wakes and burns it  3. the Sundering breaks it apart
##   4. survivors flee into the sky  5. the kin choose hunters  6. the Skylands rebuilt
##   7. hunters dropping into the wild isles, while the Wyrm sleeps below
## then the KINFALL title card. Click, Space or Esc skips ahead; "Skip" ends it.

signal finished

const SETS := {"whole": Vector3(0, 0, 0), "ships": Vector3(600, 0, 0), "kin": Vector3(1200, 0, 0),
	"home": Vector3(1800, 0, 0), "drop": Vector3(2400, 0, 0)}

var cam: Camera3D
var env: Environment
var t := 0.0
var shot := -1
var shot_t := 0.0
var shots: Array = []
var rng := RandomNumberGenerator.new()
var pieces: Array = []          # the broken continent: {node, dir, fall, spin}
var ships: Array = []
var gliders: Array = []
var kin_nodes: Array = []
var kin_hunter: Node3D
var kin_anim: HunterAnim
var broke := false
var shake := 0.0
var then_go := "hatch"          # where to go after: "hatch" for a new game, "title" when rewatched
# ui
var ui: CanvasLayer
var fade: ColorRect
var flash: ColorRect
var caption: Label
var bar_top: ColorRect
var bar_bot: ColorRect
var card: Control
var done := false
var advancing := false          # fading out to the next shot (the camera keeps moving meanwhile)
var wyrm: Wyrm
var wyrm_paths := {}            # event -> Curve3D the Wyrm flies along in that shot
var towns: Array = []           # [island, local position] of each house and tower, to set alight
var burning := 0
var debris: Array = []          # falling rocks: {node, vel, spin}
var deep_eyes: Node3D

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.play_music("title")
	Sfx.play_ambience("home")
	rng.seed = 77
	var we := WorldEnvironment.new()
	env = Look.environment({"top": Color("1c2050"), "mid": Color("6a5aa8"), "horizon": Color("ffbe86"), "below": Color("3a3268"),
		"sun_dir": Vector3(0.3, 0.14, -0.95), "sun_col": Color("ffd8a8"), "ambient": Color("cfc0ea"), "ambient_energy": 0.6,
		"fog": Color("8a74b0"), "fog_density": 0.0012, "fog_height": -40.0, "fog_height_density": 0.02, "stars": 0.5})
	we.environment = env
	add_child(we)
	var sun := Look.lights(self, Color("ffe2c4"), 1.05, Vector3(-28, 160, 0), 120.0)
	sun.shadow_opacity = 0.5
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(9000, 9000)
	sea.mesh = pm
	var cm := ShaderMaterial.new(); cm.shader = load("res://shaders/clouds.gdshader")
	cm.set_shader_parameter("deep", Color("2e2858")); cm.set_shader_parameter("light", Color("b08ad8"))
	cm.set_shader_parameter("glow", Color("ffb070")); cm.set_shader_parameter("glow_amount", 0.8)
	cm.set_shader_parameter("sun_xz", Vector2(0.3, -0.95)); cm.set_shader_parameter("scale", 0.012)
	sea.material_override = cm
	sea.position = Vector3(1200, -70.0, 0)
	add_child(sea)
	cam = Camera3D.new(); cam.fov = 48.0; cam.far = 5000.0
	add_child(cam)
	cam.make_current()
	_set_whole()
	_set_ships()
	_set_kin()
	_set_home()
	_set_drop()
	_set_wyrm()
	_sky_burn(0.0)            # remember the calm sky before anything tints it
	Look.night(env, 0.0)
	_build_ui()
	# each shot: camera path (from, look, to, look), how long, and its line of story
	var W: Vector3 = SETS["whole"]; var S: Vector3 = SETS["ships"]; var K: Vector3 = SETS["kin"]
	var H: Vector3 = SETS["home"]; var D: Vector3 = SETS["drop"]
	shots = [
		{"a": W + Vector3(-46, 30, 62), "la": W + Vector3(0, 0, 0), "b": W + Vector3(-30, 22, 46), "lb": W + Vector3(0, 2, 0), "dur": 6.0,
			"text": "Long ago, the world was whole, and its people lived in peace."},
		{"a": W + Vector3(-24, 5, 40), "la": W + Vector3(14, 6, -30), "b": W + Vector3(-30, 8, 44), "lb": W + Vector3(2, 12, 0), "dur": 8.0,
			"text": "Then the Wyrm woke beneath the world.", "event": "wyrm"},
		{"a": W + Vector3(-30, 22, 46), "la": W + Vector3(0, 0, 0), "b": W + Vector3(-34, 34, 70), "lb": W + Vector3(0, -22, 0), "dur": 9.0,
			"text": "It tore the land apart.\nThe cities burned, and fell into the clouds.", "event": "break"},
		{"a": S + Vector3(-34, 6, 26), "la": S + Vector3(0, 2, -10), "b": S + Vector3(-8, 9, 30), "lb": S + Vector3(10, 4, -14), "dur": 8.0,
			"text": "The few who survived fled into the sky,\nin ships patched together from the wreckage.", "event": "flee"},
		{"a": K + Vector3(0, 3.2, 9.5), "la": K + Vector3(0, 0.8, 0), "b": K + Vector3(-4.5, 2.4, 6.0), "lb": K + Vector3(0, 0.9, 0), "dur": 8.0,
			"text": "They weren't alone up here. The kin, small bright creatures\nborn of the old world's light, began to choose hunters.", "event": "kin"},
		{"a": H + Vector3(18, 16, 26), "la": H + Vector3(0, 0, 0), "b": H + Vector3(-10, 12, 24), "lb": H + Vector3(2, 0, -2), "dur": 7.0,
			"text": "Now the Skylands are being rebuilt, one island at a time:\nfarms, bridges, homes."},
		{"a": D + Vector3(-6, 30, 26), "la": D + Vector3(4, 8, -30), "b": D + Vector3(-2, 22, 10), "lb": D + Vector3(8, -6, -46), "dur": 8.0,
			"text": "Now hunters fly out to the wild isles for what the fall left behind.\nAnd far below the clouds, the Wyrm sleeps.", "event": "drop"},
	]
	_next_shot()

# ---------------------------------------------------------------- sets
## The world whole: one great landmass of fitted-together islands, with towns on it.
func _set_whole() -> void:
	var o: Vector3 = SETS["whole"]
	var offs := [Vector2(0, 0), Vector2(15, 4), Vector2(-14, 6), Vector2(4, -15), Vector2(-8, -13), Vector2(10, 16), Vector2(-6, 17), Vector2(20, -10), Vector2(-21, -6)]
	for i in offs.size():
		var r := 9.5 if i == 0 else rng.randf_range(7.5, 9.0)
		var isl := Scenery.island(rng, r, true, false)
		var at := o + Vector3(offs[i].x, 0, offs[i].y)
		isl.position = at
		isl.rotation.y = rng.randf() * TAU
		add_child(isl)
		# old towns: houses and stone towers
		for k in 2:
			var a := rng.randf() * TAU
			var hs := Models.house(); hs.scale = Vector3.ONE * 0.55
			hs.position = Vector3(cos(a), 0, sin(a)) * r * 0.45; hs.rotation.y = rng.randf() * TAU
			isl.add_child(hs)
			towns.append([isl, hs.position + Vector3(0, 1.4, 0)])
		var tw := Models.part(isl, Models.cyl(0.8, 1.0, 4.0, 8), Models.toon(Color("c9c0b0")), Vector3(rng.randf_range(-3, 3), 2.0, rng.randf_range(-3, 3)))
		Models.part(isl, Models.cyl(0.0, 1.1, 1.4, 8), Models.toon(Color("c9604a")), tw.position + Vector3(0, 2.7, 0))
		towns.append([isl, tw.position + Vector3(0, 3.2, 0)])
		var dir := Vector3(offs[i].x, 0, offs[i].y).normalized() if i > 0 else Vector3.ZERO
		pieces.append({"node": isl, "base": at, "dir": dir, "fall": rng.randf_range(4.0, 30.0) * (0.3 if i == 0 else 1.0),
			"spin": rng.randf_range(-0.25, 0.25), "drift": rng.randf_range(6.0, 16.0)})

## Skyships at dawn, sailing between drifting islands.
func _set_ships() -> void:
	var o: Vector3 = SETS["ships"]
	for i in 4:
		var sh := Models.skyship()
		sh.position = o + Vector3(-14 + i * 7, 3 + i * 1.2, -4 - i * 8)
		sh.rotation.y = -PI / 2
		sh.scale = Vector3.ONE * (1.4 if i == 0 else 1.0)
		add_child(sh)
		ships.append({"node": sh, "speed": rng.randf_range(2.0, 3.5), "base": sh.position})
		if i in [1, 3]:
			_fire(sh, Vector3(0.6, 1.2, 0.8), 0.7)       # damaged in the escape, trailing smoke
	for i in 8:
		var isl := Scenery.island(rng, rng.randf_range(3.0, 7.0), true, rng.randf() < 0.5)
		isl.position = o + Vector3(rng.randf_range(-60, 60), rng.randf_range(-22, -6), rng.randf_range(-90, -15))
		add_child(isl)

## A hunter alone on an island, and the kin who come to them.
func _set_kin() -> void:
	var o: Vector3 = SETS["kin"]
	var isl := Scenery.island(rng, 6.5, false, true)
	isl.position = o
	add_child(isl)
	var tr := Models.tree(rng, Color("5a9a4f"), "blossom"); tr.position = o + Vector3(-2.6, 0, -2.0); tr.scale *= 1.3; add_child(tr)
	kin_hunter = Models.hunter("medium", Data.TEAM_COLORS[0], "repeater", "sage", {"gender": rng.randi() % 2})
	kin_hunter.position = o + Vector3(0.6, 0, 0.6)
	kin_hunter.rotation.y = PI + 0.2
	var ring := kin_hunter.get_node_or_null("TeamRing") as Node3D
	if ring: ring.visible = false
	add_child(kin_hunter)
	kin_anim = HunterAnim.new(kin_hunter)
	var species := ["cindle", "puddlet", "burrlet", "zapple"]
	for i in species.size():
		var k := Models.kin(species[i], {"level": 5})
		var a := -1.2 + i * 0.8
		k.set_meta("home", o + Vector3(cos(a) * 1.9, 0, sin(a) * 1.2 + 1.9))
		k.position = o + Vector3(cos(a) * 7.0, 0, sin(a) * 4.0 + 6.0)     # start out in the grass
		k.visible = false
		k.rotation.y = PI
		add_child(k)
		kin_nodes.append(k)

## A rebuilt home: house, farm, fence, lamps, a bridge to the next island over.
func _set_home() -> void:
	var o: Vector3 = SETS["home"]
	var isl := Scenery.island(rng, 9.0, false, true)
	isl.position = o
	add_child(isl)
	var hs := Models.house(); hs.position = o + Vector3(-2.5, 0, -3.0); add_child(hs)
	for i in 4:
		var pl := Models.plot(); pl.position = o + Vector3(2.0 + (i % 2) * 1.6, 0, 0.5 + (i / 2) * 1.6); add_child(pl)
	var fn := Models.fence(4.0); fn.position = o + Vector3(2.8, 0, 3.4); add_child(fn)
	for p in [Vector3(-0.5, 0, 1.5), Vector3(4.8, 0, -1.8)]:
		var lp := Models.lamp(); lp.position = o + p; add_child(lp)
	var bn := Models.banner(UI.ACCENT); bn.position = o + Vector3(-5.0, 0, 1.0); add_child(bn)
	var isl2 := Scenery.island(rng, 5.0, true, false)
	isl2.position = o + Vector3(17, 0, -2)
	add_child(isl2)
	# bridge planks between them
	var wood := Models.toon(Color("9a7a52"))
	for k in 14:
		Models.part(self, Models.box(0.42, 0.12, 1.6), wood, o + Vector3(8.6 + k * 0.5, 0.02, -1.2 + k * -0.06))
	var k := Models.kin("puddlet", {"level": 5}); k.position = o + Vector3(0.5, 0, 2.6); add_child(k)
	k.set_meta("happy", true)
	kin_nodes.append(k)

## The drop: a skyship over the wild isles, hunters gliding toward the Heart.
func _set_drop() -> void:
	var o: Vector3 = SETS["drop"]
	var sh := Models.skyship(); sh.position = o + Vector3(0, 14, -6); sh.rotation.y = -PI / 2 + 0.2; sh.scale *= 1.3; add_child(sh)
	ships.append({"node": sh, "speed": 1.5, "base": sh.position})
	var heart := Scenery.island(rng, 13.0, true, true)
	heart.position = o + Vector3(14, -30, -70)
	add_child(heart)
	Scenery.heart(heart, 13.0)
	for i in 9:
		var isl := Scenery.island(rng, rng.randf_range(4.0, 9.0), true, rng.randf() < 0.4)
		isl.position = o + Vector3(rng.randf_range(-60, 70), rng.randf_range(-40, -24), rng.randf_range(-130, -25))
		add_child(isl)
	var heroes: Array = Data.HEROES.keys()
	for i in 5:
		var hero: String = heroes[i % heroes.size()]
		var h := Models.hunter(Data.HEROES[hero]["cls"], Data.TEAM_COLORS[(i % (Data.TEAM_COLORS.size() - 1)) + 1], Data.HEROES[hero]["weapon"], hero,
			{"gender": i % 2, "skin": rng.randi() % Models.LOOK_SKIN.size(), "hair": rng.randi() % Models.LOOK_HAIRS.size()})
		(h.get_node("TeamRing") as Node3D).visible = false
		(h.get_node("Rig/Torso/Glider") as Node3D).visible = true
		h.position = o + Vector3(rng.randf_range(-3, 3), 12.0, rng.randf_range(-8, -4))
		h.scale *= 1.3
		add_child(h)
		var v := Vector3(rng.randf_range(-0.5, 2.0), -2.2, -rng.randf_range(4.5, 6.5))
		h.rotation.y = atan2(-v.x, -v.z)
		gliders.append({"node": h, "anim": HunterAnim.new(h), "vel": v, "start": h.position, "delay": i * 0.9})

## The Wyrm and the paths it flies in its shots.
func _set_wyrm() -> void:
	wyrm = Wyrm.new()
	add_child(wyrm)
	wyrm.set_size(1.8)
	wyrm.visible = false
	var W: Vector3 = SETS["whole"]; var S: Vector3 = SETS["ships"]
	# rises out of the clouds beyond the world, sweeps low over the towns breathing fire, climbs away
	wyrm_paths["wyrm"] = _curve([W + Vector3(70, -90, -90), W + Vector3(55, -20, -60), W + Vector3(32, 12, -30), W + Vector3(10, 10, -6),
		W + Vector3(-10, 9, 10), W + Vector3(-34, 22, 22), W + Vector3(-70, 40, 30)])
	# far off behind the fleeing ships, a dark shape moving through the clouds
	wyrm_paths["flee"] = _curve([S + Vector3(-110, 2, -120), S + Vector3(-30, 12, -100), S + Vector3(60, 6, -115), S + Vector3(140, -6, -130)])
	# a pair of embers far down in the clouds, for the last shot
	var D: Vector3 = SETS["drop"]
	deep_eyes = Node3D.new()
	deep_eyes.position = D + Vector3(26, -62, -95)
	add_child(deep_eyes)
	for sx in [-1.0, 1.0]:
		Models.part(deep_eyes, Models.sphere(1.3, 12), Models.glow_mat(Color("ff7a2a")), Vector3(sx * 3.2, 0, 0), Vector3(1.4, 0.5, 1.0))
	deep_eyes.scale = Vector3(1, 0.01, 1)

func _curve(pts: Array) -> Curve3D:
	var c := Curve3D.new()
	for i in pts.size():
		var p: Vector3 = pts[i]
		var tin := Vector3.ZERO; var tout := Vector3.ZERO
		if i > 0 and i < pts.size() - 1:
			var tan := ((pts[i + 1] as Vector3) - (pts[i - 1] as Vector3)) * 0.25
			tin = -tan; tout = tan
		c.add_point(p, tin, tout)
	return c

## Flames and a smoke column on a node (a burning house, a damaged ship).
func _fire(parent: Node3D, at: Vector3, size := 1.0) -> void:
	var f := CPUParticles3D.new()
	f.amount = 26; f.lifetime = 0.8
	f.position = at
	f.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE; f.emission_sphere_radius = 0.5 * size
	f.direction = Vector3.UP; f.spread = 18.0
	f.initial_velocity_min = 1.5 * size; f.initial_velocity_max = 3.5 * size
	f.gravity = Vector3(0, 2.0, 0)
	f.scale_amount_min = 0.6 * size; f.scale_amount_max = 1.3 * size
	var fg := Gradient.new(); fg.set_color(0, Color(1, 0.9, 0.5, 1)); fg.set_color(1, Color(0.8, 0.15, 0.05, 0))
	f.color_ramp = fg
	f.mesh = _blob(0.35, true)
	parent.add_child(f)
	var sm := CPUParticles3D.new()
	sm.amount = 22; sm.lifetime = 4.0
	sm.position = at + Vector3(0, 0.8, 0)
	sm.direction = Vector3(0.25, 1, 0); sm.spread = 12.0
	sm.initial_velocity_min = 2.0; sm.initial_velocity_max = 3.5
	sm.gravity = Vector3(0.6, 0.4, 0)
	sm.scale_amount_min = 1.2 * size; sm.scale_amount_max = 2.6 * size
	var sc := Curve.new(); sc.add_point(Vector2(0, 0.4)); sc.add_point(Vector2(1, 2.2))
	sm.scale_amount_curve = sc
	var sg := Gradient.new(); sg.set_color(0, Color(0.25, 0.2, 0.22, 0.75)); sg.set_color(1, Color(0.35, 0.32, 0.38, 0.0))
	sm.color_ramp = sg
	sm.mesh = _blob(0.6, false)
	parent.add_child(sm)

func _blob(r: float, glow: bool) -> SphereMesh:
	var m := SphereMesh.new(); m.radius = r; m.height = r * 2.0; m.radial_segments = 8; m.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if glow: mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.material = mat
	return m

## Tints the sky toward a burning red (0 = as it was).
func _sky_burn(k: float) -> void:
	var sm := env.sky.sky_material as ShaderMaterial if env and env.sky else null
	if sm == null:
		return
	if not sm.has_meta("calm"):
		sm.set_meta("calm", [sm.get_shader_parameter("top"), sm.get_shader_parameter("mid"), sm.get_shader_parameter("horizon")])
	var calm: Array = sm.get_meta("calm")
	var red := [Color("2a1020"), Color("7a2a2a"), Color("ff7a3a")]
	for i in 3:
		sm.set_shader_parameter(["top", "mid", "horizon"][i], (calm[i] as Color).lerp(red[i], k))

func _wyrm_along(ev: String, k: float) -> void:
	var c: Curve3D = wyrm_paths[ev]
	wyrm.global_position = c.sample_baked(c.get_baked_length() * clampf(k, 0.0, 1.0), true)

# ---------------------------------------------------------------- ui
func _build_ui() -> void:
	ui = CanvasLayer.new(); ui.layer = 5; add_child(ui)
	var root := Control.new(); root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.theme = UI.theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	# letterbox bars that slide in
	bar_top = ColorRect.new(); bar_top.color = Color(0.02, 0.02, 0.04)
	bar_top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE); bar_top.offset_bottom = 0.0
	bar_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar_top)
	bar_bot = ColorRect.new(); bar_bot.color = Color(0.02, 0.02, 0.04)
	bar_bot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE); bar_bot.offset_top = 0.0
	bar_bot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar_bot)
	var tw := create_tween().set_parallel()
	tw.tween_property(bar_top, "offset_bottom", 78.0, 1.2).set_trans(Tween.TRANS_SINE)
	tw.tween_property(bar_bot, "offset_top", -128.0, 1.2).set_trans(Tween.TRANS_SINE)
	caption = Label.new()
	caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	caption.offset_top = -122.0; caption.offset_bottom = -12.0
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.add_theme_font_override("font", UI.big)
	caption.add_theme_font_size_override("font_size", 28)
	caption.add_theme_color_override("font_color", Color("ffe6c8"))
	caption.add_theme_constant_override("line_spacing", 4)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(caption)
	flash = ColorRect.new(); flash.color = Color(1, 0.95, 0.85, 0.0)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash)
	fade = ColorRect.new(); fade.color = Color(0.02, 0.02, 0.04, 1.0)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fade)
	var skip := UI.button("Skip", func(): _finish(), 100)
	skip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	skip.offset_left = -124; skip.offset_right = -24; skip.offset_top = 18; skip.offset_bottom = 60
	root.add_child(skip)
	var hint := UI.label("Click or press Space to continue", 13, Color(1, 1, 1, 0.45))
	hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	hint.position = Vector2(24, 28)
	root.add_child(hint)

func _next_shot() -> void:
	shot += 1
	shot_t = 0.0
	if shot >= shots.size():
		_title_card()
		return
	advancing = false
	var ev0 := String(shots[shot].get("event", ""))
	if ev0 == "wyrm":
		var c: Curve3D = wyrm_paths["wyrm"]
		wyrm.teleport(c.sample_baked(0.0), c.sample_baked(1.0) - c.sample_baked(0.0))
		wyrm.visible = true
	elif ev0 == "flee":
		var c2: Curve3D = wyrm_paths["flee"]
		wyrm.teleport(c2.sample_baked(0.0), c2.sample_baked(1.0) - c2.sample_baked(0.0))
		wyrm.breath.emitting = false
		wyrm.visible = true
		wyrm.flap_rate = 0.8
	elif ev0 != "break":
		wyrm.visible = false
		Look.night(env, 0.0)
		_sky_burn(0.0)
	var s: Dictionary = shots[shot]
	caption.text = String(s["text"])
	caption.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 0.0, 0.7)
	tw.parallel().tween_property(caption, "modulate:a", 1.0, 1.2).set_delay(0.5)
	Sfx.play("whoosh", null, -14.0, 0.05, 0.8)

## Fade out and on to the next shot.
func _advance() -> void:
	if done or advancing or shot >= shots.size():
		return
	advancing = true      # don't trigger twice; the camera keeps gliding while it fades
	var tw := create_tween()
	tw.tween_property(caption, "modulate:a", 0.0, 0.35)
	tw.parallel().tween_property(fade, "color:a", 1.0, 0.6)
	tw.tween_callback(_next_shot)

func _title_card() -> void:
	caption.text = ""
	card = Control.new(); card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.get_child(0).add_child(card)
	var col := VBoxContainer.new(); col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(col)
	var big := Label.new(); big.text = "KINFALL"
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.add_theme_font_override("font", UI.big); big.add_theme_font_size_override("font_size", 110)
	big.add_theme_color_override("font_color", Color("f7a03c"))
	big.add_theme_constant_override("outline_size", 18); big.add_theme_color_override("font_outline_color", Color("2a1530"))
	col.add_child(big)
	var sub := Label.new(); sub.text = "Your story starts with an egg."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_override("font", UI.big); sub.add_theme_font_size_override("font_size", 26)
	sub.add_theme_color_override("font_color", Color("ffe6c8"))
	col.add_child(sub)
	card.modulate.a = 0.0
	big.pivot_offset = Vector2(400, 60)
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 0.75, 0.6)
	tw.parallel().tween_property(card, "modulate:a", 1.0, 1.0)
	Sfx.play("bond", null, -4.0, 0.0, 0.9)
	tw.tween_interval(2.6)
	tw.tween_callback(_finish)

func _finish() -> void:
	if done:
		return
	done = true
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.5)
	tw.tween_callback(func():
		finished.emit()
		Save.d["tutorial"]["prologue"] = true
		Save.d["tutorial"]["intro"] = true      # the hatch screen's own short story is covered
		Game.goto(then_go))

func _unhandled_input(event: InputEvent) -> void:
	if done:
		return
	if event.is_action_pressed("menu"):
		_finish()
	elif event.is_action_pressed("jump") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		if shot < shots.size() and shot_t > 0.8 and not advancing:
			_advance()

# ---------------------------------------------------------------- the show
func _process(delta: float) -> void:
	t += delta
	shot_t += delta
	if shot >= 0 and shot < shots.size():
		var s: Dictionary = shots[shot]
		# keeps going a little past the end while it fades out, so a click never snaps it back
		var k := clampf(shot_t / float(s["dur"]), 0.0, 1.08)
		var e := k * k * (3.0 - 2.0 * k) if k <= 1.0 else 1.0 + (k - 1.0)
		var pos: Vector3 = (s["a"] as Vector3).lerp(s["b"], e)
		var look: Vector3 = (s["la"] as Vector3).lerp(s["lb"], e)
		if shake > 0.0:
			pos += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * shake
			shake = maxf(0.0, shake - delta * 1.2)
		cam.position = pos
		cam.look_at(look, Vector3.UP)
		_events(String(s.get("event", "")), shot_t, delta)
		if shot_t >= float(s["dur"]) and not advancing:
			_advance()
	for d in debris.duplicate():
		var n: Node3D = d["node"]
		d["vel"] += Vector3(0, -9.0, 0) * delta
		n.position += (d["vel"] as Vector3) * delta
		n.rotation += (d["spin"] as Vector3) * delta
		if n.position.y < -90.0:
			n.queue_free(); debris.erase(d)
	flash.color.a = maxf(0.0, flash.color.a - delta * 1.6)
	for sh in ships:
		var n: Node3D = sh["node"]
		n.position.x += float(sh["speed"]) * delta
		n.position.y = (sh["base"] as Vector3).y + sin(t * 0.6 + float(sh["speed"])) * 0.3
		for pn in ["PropL", "PropR"]:
			var pr := n.get_node_or_null(pn) as Node3D
			if pr: pr.rotation.z += delta * 10.0

func _events(ev: String, st: float, delta: float) -> void:
	match ev:
		"wyrm":
			var dur: float = shots[shot]["dur"]
			_wyrm_along("wyrm", st / (dur + 0.6))
			if st > 2.2 and wyrm.roar_k <= 0.0 and not wyrm.has_meta("roared"):
				wyrm.set_meta("roared", true)
				wyrm.roar()
				shake = 0.9
				Sfx.play("v_warden", null, 2.0, 0.0, 0.55)
				Sfx.play("boom", null, -6.0, 0.0, 0.35)
				var tk := create_tween()
				tk.tween_method(_sky_burn, 0.0, 0.6, 3.0)
			wyrm.breath.emitting = st > 3.4 and st < 5.6
			if wyrm.breath.emitting and burning < towns.size() and randf() < delta * 6.0:
				var tn: Array = towns[burning]
				_fire(tn[0], tn[1], 1.3)
				burning += 1
				Sfx.play("boom", null, -14.0, 0.1, 1.4)
		"break":
			# the Wyrm circles overhead while the world comes apart
			wyrm.visible = true
			wyrm.breath.emitting = false
			var ang := 2.2 + st * 0.42
			wyrm.global_position = (SETS["whole"] as Vector3) + Vector3(cos(ang) * 21.0, 13.0 + sin(st * 0.8) * 3.0, sin(ang) * 21.0)
			if burning < towns.size():
				for i in range(burning, towns.size()):
					_fire(towns[i][0], towns[i][1], 1.2)
				burning = towns.size()
			if st > 1.6 and randf() < delta * 14.0 and debris.size() < 70:
				# rocks breaking off the edges and tumbling away
				var p: Dictionary = pieces[rng.randi_range(0, pieces.size() - 1)]
				var rock := Models.part(self, Models.box(rng.randf_range(0.5, 1.6), rng.randf_range(0.5, 1.4), rng.randf_range(0.5, 1.6)), Models.toon(Color("6b5246")),
					(p["node"] as Node3D).position + Vector3(rng.randf_range(-9, 9), rng.randf_range(-3, 1), rng.randf_range(-9, 9)))
				debris.append({"node": rock, "vel": Vector3(rng.randf_range(-3, 3), rng.randf_range(-1, 3), rng.randf_range(-3, 3)), "spin": Vector3(rng.randf_range(-3, 3), rng.randf_range(-3, 3), rng.randf_range(-3, 3))})
			if st > 1.6 and not broke:
				broke = true
				flash.color.a = 0.85
				shake = 1.4
				Sfx.play("boom", null, 0.0, 0.0, 0.6)
				Sfx.play("boom", null, -4.0, 0.0, 0.45)
				Sfx.play("v_warden", null, 0.0, 0.0, 0.5)
				var dk := create_tween()
				dk.tween_method(_sky_burn, 0.6, 1.0, 1.5)
			if broke:
				# the pieces drift apart, tilt and sink into the clouds
				var k := clampf((st - 1.6) / 6.0, 0.0, 1.0)
				var e := 1.0 - pow(1.0 - k, 2.0)
				for p in pieces:
					var n: Node3D = p["node"]
					n.position = (p["base"] as Vector3) + (p["dir"] as Vector3) * float(p["drift"]) * e + Vector3(0, -float(p["fall"]) * k * k, 0)
					n.rotation.z = float(p["spin"]) * e
					n.rotation.x = float(p["spin"]) * 0.6 * e
				if randf() < delta * 3.0 and st < 6.0:
					flash.color.a = maxf(flash.color.a, 0.3)
		"kin":
			# one by one the kin come bounding out of the grass to the hunter
			kin_anim.update(delta, {"face": kin_hunter.rotation.y, "fired": 99.0})
			for i in mini(4, kin_nodes.size()):
				var k: Node3D = kin_nodes[i]
				var start := 0.8 + i * 0.9
				if st < start: continue
				if not k.visible:
					k.visible = true
					Sfx.play("pickup", null, -10.0, 0.05, 1.2 + i * 0.1)
				var home: Vector3 = k.get_meta("home")
				var d := home - k.position
				d.y = 0.0
				if d.length() > 0.1:
					k.position += d.normalized() * minf(d.length(), delta * 4.5)
					k.rotation.y = atan2(-d.x, -d.z)
					k.get_node("Body").position.y = absf(sin(st * 9.0 + i)) * 0.3
				else:
					k.rotation.y = lerp_angle(k.rotation.y, atan2(-(kin_hunter.position.x - k.position.x), -(kin_hunter.position.z - k.position.z)), delta * 4.0)
					k.get_node("Body").position.y = absf(sin(st * 4.0 + i)) * 0.12
					k.set_meta("happy", true)
		"flee":
			_wyrm_along("flee", st / 8.0)
			_sky_burn(maxf(0.0, 0.55 - st * 0.12))     # the fires fall behind them
		"drop":
			# the last thing you see: two embers opening far down in the clouds
			deep_eyes.scale.y = lerpf(deep_eyes.scale.y, 1.0 if st > 4.8 else 0.01, minf(1.0, delta * 3.0))
			for g in gliders:
				var tt: float = st - float(g["delay"])
				var h: Node3D = g["node"]
				if tt < 0.0:
					h.visible = false
					continue
				h.visible = true
				h.position = (g["start"] as Vector3) + (g["vel"] as Vector3) * tt
				(g["anim"] as HunterAnim).update(delta, {"gliding": true, "grounded": false, "vel": g["vel"], "face": h.rotation.y})
