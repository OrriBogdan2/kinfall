extends Node3D
## The first thing a new player sees: three eggs on a little island. Pick one, watch it hatch,
## name what comes out, then head into the tutorial match together.

const EGGS := [
	{"species": "cindle", "name": "Warm egg", "desc": "Warm to the touch, and it kicks when you get close. Something bold is in here."},
	{"species": "puddlet", "name": "Cool egg", "desc": "Cool and smooth. It rocks gently when you talk to it. Something gentle is in here."},
	{"species": "burrlet", "name": "Mossy egg", "desc": "Covered in soft moss, and it keeps turning toward little sounds. Something curious is in here."},
]

var cam: Camera3D
var fx: Fx
var eggs: Array = []          # {node, base, data}
var chosen := -1
var stage := "pick"           # pick | hatching | name
var t := 0.0
var hatch_t := 0.0
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
	var pm := PlaneMesh.new(); pm.size = Vector2(400, 400)
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
		var egg := _egg(sp["color"], sp["belly"])
		egg.position = Vector3(0, 0.12, 0)
		holder.add_child(egg)
		eggs.append({"holder": holder, "egg": egg, "base": holder.position, "data": d})
	_build_ui()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hatch-auto="):
			var i := int(a.substr(13))
			_pick(i); _pick(i)

func _egg(c: Color, spot: Color) -> Node3D:
	var root := Node3D.new()
	var shell := Node3D.new(); shell.name = "Shell"; root.add_child(shell)
	var m := Models.toon(c.lightened(0.15))
	var ms := Models.toon(spot)
	var top := Models.part(shell, Models.sphere(0.32, 18), m, Vector3(0, 0.42, 0), Vector3(0.92, 1.25, 0.92))
	top.name = "Egg"
	var rng := RandomNumberGenerator.new(); rng.seed = int(c.r * 1000)
	for i in 6:
		var a := rng.randf() * TAU; var y := rng.randf_range(0.2, 0.7)
		var p := Vector3(cos(a) * 0.27, y, sin(a) * 0.27)
		Models.part(shell, Models.sphere(0.06, 8), ms, p, Vector3(1, 1, 0.5))
	return root

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
	holder.offset_top = -230
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_ui.add_child(holder)
	bottom = UI.vbox(10)
	holder.add_child(bottom)
	_show_pick()

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
		v.add_child(UI.title(d["name"], 22, Data.KIN[d["species"]]["color"]))
		var dl := UI.label(d["desc"], 14, UI.MUTED)
		dl.custom_minimum_size.x = 220
		v.add_child(dl)
		var ii := i
		v.add_child(UI.button("This one" if i != chosen else "Hatch it", func(): _pick(ii)))
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
	stage = "hatching"
	hatch_t = 0.0
	_clear_bottom()
	title.text = "Something's moving..."
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
	cam.look_at(Vector3(0, 0.25 if stage != "pick" else 0.55, 0.5))
	for i in eggs.size():
		var egg: Node3D = eggs[i]["egg"]
		if stage == "pick":
			var lift := 0.12 if i == chosen else 0.0
			egg.position.y = lerpf(egg.position.y, 0.12 + lift + (sin(t * 3.0) * 0.03 if i == chosen else 0.0), minf(1.0, delta * 8.0))
			# a little wobble now and then, like something inside is awake
			egg.rotation.z = sin(t * 2.0 + i * 2.1) * 0.06 * (1.0 + float(sin(t * 0.7 + i) > 0.7) * 3.0)
	if stage == "hatching" and chosen >= 0:
		hatch_t += delta
		var egg: Node3D = eggs[chosen]["egg"]
		var k := clampf((hatch_t - 0.8) / 2.6, 0.0, 1.0)
		var amp := k * k * 0.35
		egg.rotation.z = sin(hatch_t * (14.0 + k * 22.0)) * amp
		egg.position.x = sin(hatch_t * 31.0) * amp * 0.12
		if k > 0.0 and int(hatch_t * (3.0 + k * 9.0)) != int((hatch_t - delta) * (3.0 + k * 9.0)):
			Sfx.play("build", null, -10.0 + k * 6.0, 0.2, 1.4 + k * 0.5)
			fx.burst(eggs[chosen]["holder"].position + Vector3(0, 0.5, 0), Color("f3eee2"), 3, 1.5, 0.3, 6.0, 0.6)
		if hatch_t > 3.5:
			_crack()

func _crack() -> void:
	stage = "name"
	var e: Dictionary = eggs[chosen]
	var sp_id: String = e["data"]["species"]
	var sp: Dictionary = Data.KIN[sp_id]
	var at: Vector3 = e["holder"].position
	var egg: Node3D = e["egg"]
	egg.visible = false
	# shell halves fly apart
	for sgn in [-1.0, 1.0]:
		var half := Models.part(self, Models.sphere(0.3, 14), Models.toon(Color(sp["color"]).lightened(0.15)), at + Vector3(0.12 * sgn, 0.55, 0), Vector3(0.35, 0.6, 0.6))
		var tw := create_tween().set_parallel(true)
		tw.tween_property(half, "position", at + Vector3(0.9 * sgn, 0.12, 0.3), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(half, "rotation", Vector3(0, 0, 1.6 * sgn), 0.5)
		tw.chain().tween_interval(0.4)
		tw.chain().tween_property(half, "scale", Vector3.ZERO, 0.5)
	fx.burst(at + Vector3(0, 0.6, 0), sp["color"], 30, 4.0, 0.8, 4.0, 1.2)
	fx.burst(at + Vector3(0, 0.6, 0), Color("f3eee2"), 16, 3.0, 0.6, 8.0, 0.8)
	fx.ring(at, 2.0, Color(UI.GOLD, 0.9), 0.5)
	Sfx.play("unlock")
	get_tree().create_timer(0.25).timeout.connect(func(): Sfx.play("kin_happy"))
	kin_node = Models.kin(sp_id)
	kin_node.position = at + Vector3(0, 0.1, 0)
	kin_node.scale = Vector3.ONE * 0.1
	kin_node.rotation.y = PI
	add_child(kin_node)
	var tw2 := create_tween()
	tw2.tween_property(kin_node, "scale", Vector3.ONE * 1.3, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw2.tween_property(kin_node, "position:y", 0.55, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw2.tween_property(kin_node, "position:y", 0.1, 0.22).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	title.text = "It's a %s!" % sp["name"]
	get_tree().create_timer(0.9).timeout.connect(_show_name)

func _show_name() -> void:
	_clear_bottom()
	var sp_id: String = EGGS[chosen]["species"]
	var sp: Dictionary = Data.KIN[sp_id]
	var card := UI.card(UI.CARD, 16, 18)
	card.custom_minimum_size = Vector2(520, 0)
	var v := UI.vbox(10); card.add_child(v)
	v.add_child(UI.label("Your %s is %s. Give it a name." % [sp["name"], String(sp["voice"]).split(",")[0]], 16))
	var name_row := UI.hbox(8)
	var nl := UI.label("Its name", 15, UI.MUTED); nl.custom_minimum_size.x = 120
	name_row.add_child(nl)
	var ne := LineEdit.new(); ne.text = Data.KIN_NAMES.pick_random(); ne.max_length = 14; ne.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(ne)
	v.add_child(name_row)
	var you_row := UI.hbox(8)
	var yl := UI.label("Your name", 15, UI.MUTED); yl.custom_minimum_size.x = 120
	you_row.add_child(yl)
	var ye := LineEdit.new(); ye.text = Save.d.get("name", "Hunter"); ye.max_length = 16; ye.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	you_row.add_child(ye)
	v.add_child(you_row)
	var btns := UI.hbox(10)
	btns.add_child(UI.button("Head out together", func(): _finish(sp_id, ne.text, ye.text, true), 240))
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
