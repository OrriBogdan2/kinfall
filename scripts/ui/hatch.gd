extends Node3D
## The first thing a new player sees: a short story, then three eggs on a little island. Pick one,
## keep it warm until it hatches, name what comes out, then head into the tutorial match together.

const EGGS := [
	{"species": "cindle", "name": "Warm egg", "temper": "Bold", "desc": "Warm to the touch, and it kicks when you get close. Something bold is in here.",
		"play": "Charges in, hits hard, and throws fireballs. Brave, but quick to anger."},
	{"species": "puddlet", "name": "Cool egg", "temper": "Gentle", "desc": "Cool and smooth. It rocks gently when you talk to it. Something gentle is in here.",
		"play": "Keeps you safe and pushes foes back with waves. Loyal, a bit of a worrier."},
	{"species": "burrlet", "name": "Mossy egg", "temper": "Curious", "desc": "Covered in soft moss, and it keeps turning toward little sounds. Something curious is in here.",
		"play": "Roots foes in place with brambles. Notices everything, wanders off sometimes."},
]

const STORY := [
	"Long ago the world broke apart.\nWhat was left drifts above the clouds as islands.",
	"Out here live the kin: small creatures who choose a hunter,\nand remember every single thing you do together.",
	"Last night a storm passed over your little island.\nThis morning there were three eggs by the door.",
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
var cam_to := Vector3(0, 3.6, 6.4)

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.play_music("title")
	Sfx.play_ambience("home")
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("141a2c")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("c4cbe6")
	e.ambient_light_energy = 0.5
	e.glow_enabled = true
	e.glow_intensity = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_color = Color("ffe9cf"); sun.light_energy = 0.9
	sun.shadow_enabled = true
	add_child(sun)
	fx = Fx.new(); add_child(fx)
	cam = Camera3D.new(); cam.fov = 40.0; add_child(cam)
	cam.position = cam_from
	cam.look_at(Vector3(0, 0.6, 0))
	# a small floating island
	var g := Models.part(self, Models.cyl(3.4, 3.0, 0.5, 28), Models.toon(Color("5f8d45")), Vector3(0, -0.25, 0))
	g.name = "Ground"
	Models.part(self, Models.cyl(3.0, 1.2, 2.6, 28), Models.toon(Color("8b6d52")), Vector3(0, -1.8, 0))
	Models.part(self, Models.cyl(1.2, 0.2, 1.6, 20), Models.toon(Color("5a4a44")), Vector3(0, -3.9, 0))
	var drng := RandomNumberGenerator.new(); drng.seed = 3
	for i in 5:
		var a := TAU * i / 5.0 + 0.3
		var fb := Models.flower_bed(drng, 4); fb.position = Vector3(cos(a) * 2.7, 0, sin(a) * 2.2); fb.scale = Vector3.ONE * 0.8
		add_child(fb)
	for i in 2:
		var tr := Models.tree(drng, Color("5a9a4f")); tr.position = Vector3(-2.6 + i * 5.0, 0, -1.8); add_child(tr)
	var lamp := Models.lamp(); lamp.position = Vector3(2.4, 0, -1.2); add_child(lamp)
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(4000, 4000)
	sea.mesh = pm
	var cm := ShaderMaterial.new(); cm.shader = load("res://shaders/clouds.gdshader")
	sea.material_override = cm
	sea.position = Vector3(0, -14.0, -20.0)
	add_child(sea)
	var drift := RandomNumberGenerator.new(); drift.seed = 9
	for k in 14:
		var r := Models.rock(drift, drift.randf_range(0.4, 1.2))
		r.position = Vector3(drift.randf_range(-14, 14), drift.randf_range(-8, -3), drift.randf_range(-16, 2))
		add_child(r)
	for i in EGGS.size():
		var d: Dictionary = EGGS[i]
		var sp: Dictionary = Data.KIN[d["species"]]
		var holder := Node3D.new()
		var x := -1.7 + i * 1.7
		holder.position = Vector3(x, 0, 0.2)
		add_child(holder)
		var nest := Models.nest(); nest.scale = Vector3.ONE * 0.8
		for ch in nest.get_children():
			if ch is MeshInstance3D and (ch as MeshInstance3D).mesh is SphereMesh:
				ch.visible = false
		holder.add_child(nest)
		var egg := EggHatch.new(d["species"], fx, 0.32, 0.42, 1.1)
		egg.hop_out = 0.35
		egg.position = Vector3(0, 0.12, 0)
		holder.add_child(egg)
		eggs.append({"holder": holder, "egg": egg, "base": holder.position, "data": d})
	_build_ui()
	cam_from = Vector3(-9, 7.5, 16); cam.position = cam_from
	cam_to = Vector3(-3.5, 4.2, 9.0)
	if "--skip-intro" in OS.get_cmdline_user_args() or Save.d["tutorial"].get("intro", false):
		_end_intro()
	else:
		_show_story()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hatch-auto="):
			var i := int(a.substr(13))
			_end_intro()
			_pick(i); _pick(i)
			auto_warm = true

func _build_ui() -> void:
	ui = CanvasLayer.new(); add_child(ui)
	root_ui = Control.new(); root_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root_ui.theme = UI.theme()
	root_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root_ui)
	var top := VBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.position.y = 36
	title = UI.title("Choose your first kin", 40, UI.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(title)
	var sub := UI.label("Every kin is different. It will remember how you treat it.", 16, UI.MUTED)
	sub.autowrap_mode = TextServer.AUTOWRAP_OFF
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(sub)
	root_ui.add_child(top)
	var holder := CenterContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	holder.offset_top = -330
	holder.offset_bottom = -14
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
	var hint := UI.label("Click or press Space to continue", 14, UI.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	story_box.add_child(hint)
	root_ui.add_child(story_box)
	var skip := UI.button("Skip", _end_intro, 100)
	skip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	skip.offset_left = -124; skip.offset_right = -24; skip.offset_top = 20; skip.offset_bottom = 64
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
	cam_to = Vector3(0, 3.6, 6.4)
	_show_pick()

func _unhandled_input(event: InputEvent) -> void:
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

func _show_pick() -> void:
	_clear_bottom()
	var row := UI.hbox(14)
	for i in EGGS.size():
		var d: Dictionary = EGGS[i]
		var card := UI.card(UI.CARD, 12, 14)
		card.custom_minimum_size = Vector2(250, 0)
		if i == chosen:
			UI.set_card_border(card, UI.ACCENT)
		var v := UI.vbox(6); card.add_child(v)
		var hr := UI.hbox(8)
		var tt := UI.title(d["name"], 22, Data.KIN[d["species"]]["color"]); tt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hr.add_child(tt)
		hr.add_child(UI.section(d["temper"], Data.KIN[d["species"]]["color"]))
		v.add_child(hr)
		var dl := UI.label(d["desc"], 14, UI.MUTED)
		dl.custom_minimum_size.x = 220
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

func _start_hatch() -> void:
	stage = "warm"
	hatch_t = 0.0
	_clear_bottom()
	title.text = "Keep it warm"
	var card := UI.card(UI.CARD, 14, 16)
	card.custom_minimum_size = Vector2(460, 0)
	var v := UI.vbox(10); card.add_child(v)
	var l := UI.label("Hold the left mouse button (or Space) to keep the egg warm. Don't let it go cold.", 15)
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
	if stage == "warm" and chosen >= 0:
		var holding := auto_warm or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_action_pressed("jump")
		warmth = clampf(warmth + delta * (0.32 if holding else -0.12), 0.0, 1.0)
		if warm_bar: warm_bar.queue_redraw()
		var wegg: EggHatch = eggs[chosen]["egg"]
		wegg.set_warmth(warmth)
		# it rocks gently in the warmth, and gives a happy little hop as it warms through
		wegg.rotation.z = sin(t * 2.4) * (0.03 + warmth * 0.06)
		var step := int(warmth * 3.0)
		if step > warm_step:
			warm_step = step
			var hop := create_tween()
			hop.tween_property(wegg, "position:y", 0.24, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			hop.tween_property(wegg, "position:y", 0.12, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			Sfx.play("jump", null, -12.0, 0.05, 1.7)
		if holding and int(t * 8.0) != int((t - delta) * 8.0):
			fx.burst(eggs[chosen]["holder"].position + Vector3(0, 0.5, 0), Color("ffb36a"), 2, 1.0, 0.5, -1.0, 0.5)
		if warmth >= 1.0:
			stage = "hatching"
			title.text = "Something's moving..."
			_clear_bottom()
			wegg.rotation.z = 0.0
			wegg.position.y = 0.12
			wegg.popped.connect(func(k: Node3D):
				kin_node = k
				title.text = "It's a %s!" % Data.KIN[EGGS[chosen]["species"]]["name"])
			wegg.done.connect(func():
				stage = "name"
				cam_to = Vector3(0, 2.2, 5.6)
				_show_name())
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
	var sp_id: String = EGGS[chosen]["species"]
	var sp: Dictionary = Data.KIN[sp_id]
	var card := UI.card(UI.CARD, 16, 18)
	card.custom_minimum_size = Vector2(520, 0)
	var v := UI.vbox(10); card.add_child(v)
	v.add_child(UI.label("\"%s\"" % KinSpeak.babble(sp_id, "happy"), 26, sp["color"]))
	v.add_child(UI.label("Your %s is %s. It can only say its own name for now. Give it a name." % [sp["name"], String(sp["voice"]).split(",")[0]], 16))
	var name_row := UI.hbox(8)
	var nl := UI.label("Its name", 15, UI.MUTED); nl.custom_minimum_size.x = 120
	name_row.add_child(nl)
	var ne := LineEdit.new(); ne.text = Data.KIN_NAMES.pick_random(); ne.max_length = 14; ne.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(ne)
	v.add_child(name_row)
	var picks := UI.hbox(6)
	var pool: Array = Data.KIN_NAMES.duplicate(); pool.shuffle()
	for nm in pool.slice(0, 4):
		var n2: String = nm
		picks.add_child(UI.button(n2, func(): ne.text = n2))
	v.add_child(picks)
	var you_row := UI.hbox(8)
	var yl := UI.label("Your name", 15, UI.MUTED); yl.custom_minimum_size.x = 120
	you_row.add_child(yl)
	var ye := LineEdit.new(); ye.text = Save.d.get("name", "Hunter"); ye.max_length = 16; ye.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	you_row.add_child(ye)
	v.add_child(you_row)
	var btns := UI.hbox(10)
	btns.add_child(UI.primary("Head out together", func(): _finish(sp_id, ne.text, ye.text, true), 240))
	var skip := UI.button("Skip the tutorial", func(): _finish(sp_id, ne.text, ye.text, false), 180)
	skip.flat = true
	btns.add_child(skip)
	v.add_child(btns)
	bottom.add_child(card)
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
