class_name KinReveal
extends CanvasLayer
## The moment right after an egg hatches, shared by the first egg and nest eggs.
## A white flash and a little fanfare, light rays turning behind the kin as it pops in with a
## bounce, sparkles drifting up, then its cry. After that you can turn it round on a turntable
## (drag it, or A/D, the arrow keys or the right stick) and read a card about what it is.
## "Name it" closes this and hands over to whatever naming step the caller has.
##
##   var rv := KinReveal.new(species_id, rec)     # rec: the kin's save record ({} for a starter)
##   add_child(rv); rv.proceed.connect(func(): _show_name())

signal proceed

const RATE := 22050

var species := "cindle"
var rec: Dictionary = {}
var sp: Dictionary = {}
var col := Color.WHITE
var glow := Color.WHITE

var root: Control
var bg: ColorRect
var rays: Control
var flash: ColorRect
var vp: SubViewport
var vpc: SubViewportContainer
var turn: Node3D             # the turntable the kin stands on (rotate this)
var kin: Node3D
var title_lbl: Label
var sub_lbl: Label
var info: PanelContainer
var name_btn: Button
var hint: Label
var player: AudioStreamPlayer

var t := 0.0
var ray_k := 0.0             # how strongly the rays show (0..1)
var spin_v := 0.0            # turntable speed from input (rad/s)
var auto_spin := true        # a slow spin until the player takes over
var dragging := false
var ready_to_name := false
var sparks: Array = []       # {p: Vector2, v: Vector2, life: float, max: float, s: float, c: Color}
var rare := false            # hatched from a boss's Rare Egg: everything goes gold
const GOLD_RAY := Color("ffd36a")

func _init(sp_id: String, kin_rec := {}) -> void:
	species = sp_id if Data.KIN.has(sp_id) else String(Data.KIN.keys()[0])
	rec = kin_rec
	layer = 60

func _ready() -> void:
	sp = Data.KIN[species]
	col = Shiny.col(species, rec, "color")
	glow = Shiny.col(species, rec, "glow") if sp.has("glow") or rec.get("shimmer", false) else col
	rare = bool(rec.get("rare", false)) or Data.is_rare(species)
	_build()
	_play_intro()

# ------------------------------------------------------------------ layout
func _build() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.theme = UI.theme()
	add_child(root)
	# a deep backdrop tinted with the kin's own colour
	bg = ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.03, 0.03, 0.06, 0.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	rays = Control.new()
	rays.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rays.draw.connect(_draw_rays)
	root.add_child(rays)
	# the kin, in a little 3D world of its own drawn over the rays
	vpc = SubViewportContainer.new()
	vpc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vpc.stretch = true
	vpc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vpc)
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vpc.add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("d8dcf2")
	e.ambient_light_energy = 0.7
	# the same filmic colour as the outdoor scenes, so the kin looks as polished here as in the world
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.08
	e.tonemap_white = 6.0
	e.adjustment_enabled = true
	e.adjustment_contrast = 1.05
	e.adjustment_saturation = 1.1
	env.environment = e
	vp.add_child(env)
	var key := DirectionalLight3D.new(); key.rotation = Vector3(-0.7, 0.6, 0); key.light_energy = 1.2
	key.light_color = Color("fff1e0")
	key.shadow_enabled = true; key.shadow_opacity = 0.6; key.shadow_blur = 1.5
	key.directional_shadow_max_distance = 8.0
	vp.add_child(key)
	var back := DirectionalLight3D.new(); back.rotation = Vector3(-0.3, PI, 0); back.light_energy = 0.7
	back.light_color = glow.lightened(0.3)
	vp.add_child(back)
	var cam := Camera3D.new()
	cam.fov = 34.0
	# aimed to the kin's right, so the kin sits left of centre and the card fits on the right
	cam.position = Vector3(0.5, 0.95, 3.3)
	vp.add_child(cam)
	cam.look_at(Vector3(0.5, 0.42, 0))
	turn = Node3D.new()
	vp.add_child(turn)
	var plate := MeshInstance3D.new()
	plate.mesh = Models.cyl(0.62, 0.66, 0.06, 40)
	plate.material_override = Models.toon(col.darkened(0.6))
	plate.position.y = -0.03
	turn.add_child(plate)
	var rim := MeshInstance3D.new()
	rim.mesh = Models.flat_quad(1.5)
	rim.material_override = Models.ring_mat(Color(glow, 0.9), 0.08)
	rim.position.y = 0.005
	turn.add_child(rim)
	kin = Models.kin(species, rec)
	kin.rotation.y = PI          # facing the camera
	kin.scale = Vector3.ONE * 0.01
	turn.add_child(kin)
	var pt: CPUParticles3D = kin.get_node_or_null("Aura")
	if pt: pt.emitting = true
	# titles
	var top := VBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top.offset_top = 36
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	title_lbl = UI.title("", 46, UI.INK)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_color_override("font_outline_color", col.darkened(0.6))
	title_lbl.add_theme_constant_override("outline_size", 10)
	top.add_child(title_lbl)
	sub_lbl = UI.label("", 18, glow.lightened(0.35))
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(sub_lbl)
	title_lbl.modulate.a = 0.0
	sub_lbl.modulate.a = 0.0
	# the info card on the right
	info = _info_card()
	info.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	info.offset_right = -48
	info.offset_left = -48 - 400
	info.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	info.grow_vertical = Control.GROW_DIRECTION_BOTH
	info.modulate.a = 0.0
	root.add_child(info)
	# the hint under the kin
	hint = UI.label("Drag to turn it round  ·  A / D", 15, UI.MUTED)
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_bottom = -40
	hint.offset_top = -64
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate.a = 0.0
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hint)
	flash = ColorRect.new()
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(1, 1, 1, 0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash)
	player = AudioStreamPlayer.new()
	player.bus = "SFX"
	add_child(player)

func _info_card() -> PanelContainer:
	var card := UI.card(Color(0.08, 0.09, 0.14, 0.92), 18, 14)
	UI.set_card_border(card, Color(_bright(col), 0.9), 2)
	card.custom_minimum_size = Vector2(400, 0)
	var v := UI.vbox(8); card.add_child(v)
	var head := UI.hbox(10)
	var nm := UI.title(String(sp["name"]), 32, _bright(col))
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(nm)
	head.add_child(_chip(String(sp.get("type", "")).capitalize(), glow))
	v.add_child(head)
	var animals: Array = sp.get("animals", [])
	if not animals.is_empty():
		v.add_child(UI.label("Part %s" % " · part ".join(animals.map(func(a): return String(a).to_lower())), 15, UI.MUTED))
	if rare:
		var boss := String(Data.MOBS.get(String(sp.get("boss", rec.get("from_boss", ""))), {}).get("name", "a lair boss"))
		v.add_child(UI.label("RARE KIN  ·  its egg was guarded by %s" % boss, 15, UI.GOLD))
	if rec.get("shimmer", false):
		v.add_child(UI.label("Shimmering! Its own rare colours (about %s)." % Shiny.odds_text(Shiny.WILD), 15, UI.GOLD))
	for mid in Mutations.of(rec):
		var mr := UI.hbox(8)
		mr.add_child(Mutations.Badge.new(mid, 20.0))
		var mtl := UI.label("%s! %s" % [Mutations.name_of(mid), Mutations.perk_text(mid)], 15, Mutations.col_of(mid))
		mtl.autowrap_mode = TextServer.AUTOWRAP_OFF
		mr.add_child(mtl)
		v.add_child(mr)
	var desc := String(sp.get("desc", ""))
	if desc != "":
		var dl := UI.label(desc, 15, UI.INK)
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.custom_minimum_size.x = 360
		v.add_child(dl)
	if rec.has("parents"):
		v.add_child(UI.label("Child of %s and %s" % [rec["parents"][0], rec["parents"][1]], 14, UI.MUTED))
	if rec.has("traits"):
		v.add_child(UI.label("%s nature" % Care.nature(rec), 14, UI.MUTED))
	v.add_child(UI.spacer(2))
	v.add_child(UI.section("Base stats", _bright(col)))
	var top_hp := 1.0; var top_dmg := 1.0; var top_spd := 1.0
	for k in Data.KIN:
		top_hp = maxf(top_hp, float(Data.KIN[k].get("hp", 1.0)))
		top_dmg = maxf(top_dmg, float(Data.KIN[k].get("dmg", 1.0)))
		top_spd = maxf(top_spd, float(Data.KIN[k].get("speed", 1.0)))
	v.add_child(_stat("Health", float(sp.get("hp", 0.0)), top_hp))
	v.add_child(_stat("Power", float(sp.get("dmg", 0.0)), top_dmg))
	v.add_child(_stat("Speed", float(sp.get("speed", 0.0)), top_spd))
	var abil: Array = []
	for id in sp.get("abilities", []):
		var ad := Content.ability(String(id))
		abil.append(ad.display_name if ad else String(id).capitalize())
	var ult := String(sp.get("ultimate", ""))
	if not abil.is_empty() or ult != "":
		v.add_child(UI.spacer(2))
		v.add_child(UI.section("Moves", _bright(col)))
		if not abil.is_empty():
			v.add_child(UI.label(", ".join(abil), 15, UI.INK))
		if ult != "":
			var ud := Content.ultimate(ult)
			v.add_child(UI.label("Bond move: %s" % (ud.display_name if ud else ult.capitalize()), 14, UI.GOLD))
	v.add_child(UI.spacer(6))
	name_btn = UI.primary("Name it", _go, 360)
	name_btn.disabled = true
	v.add_child(name_btn)
	return card

## The kin's colour, lifted until it reads on a dark card.
func _bright(c: Color) -> Color:
	var out := c
	while out.get_luminance() < 0.55:
		out = out.lerp(Color.WHITE, 0.2)
	return out

func _chip(text: String, c: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(c, 0.25); sb.border_color = c
	sb.set_border_width_all(2); sb.set_corner_radius_all(12)
	sb.content_margin_left = 12; sb.content_margin_right = 12; sb.content_margin_top = 3; sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(UI.label(text, 15, c.lightened(0.4)))
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p

func _stat(name: String, val: float, top: float) -> HBoxContainer:
	var h := UI.hbox(10)
	var l := UI.label(name, 14, UI.MUTED); l.custom_minimum_size.x = 70
	h.add_child(l)
	var b := UI.bar(clampf(val / top, 0.05, 1.0), _bright(col), 230.0, 10.0)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(b)
	h.add_child(UI.label(str(snappedf(val, 0.1)).trim_suffix(".0"), 14, UI.INK))
	return h

# ------------------------------------------------------------------ the reveal
func _play_intro() -> void:
	# white flash and the fanfare
	flash.color.a = 1.0
	_play(_jingle())
	var tw := create_tween()
	tw.tween_property(flash, "color:a", 0.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var bt := create_tween()
	bt.tween_property(bg, "color", Color(col.darkened(0.82), 0.93), 0.4)
	create_tween().tween_property(self, "ray_k", 1.0, 0.5).set_trans(Tween.TRANS_SINE)
	_burst(70)
	if rec.get("shimmer", false):
		# a shimmer: a second shower of gold stars and its chime as it lands
		get_tree().create_timer(0.45).timeout.connect(func():
			if not is_inside_tree(): return
			_shiny_burst()
			_play(Shiny.chime()))
	# the kin pops in with a bounce
	var kt := create_tween()
	kt.tween_interval(0.12)
	kt.tween_property(kin, "scale", Vector3(0.95, 1.2, 0.95), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	kt.tween_property(kin, "scale", Vector3(1.18, 0.9, 1.18), 0.12)
	kt.tween_property(kin, "scale", Vector3.ONE * 1.05, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	# its name comes in
	title_lbl.text = "You hatched %s %s!" % [_a_an(String(sp["name"])), sp["name"]]
	if rec.get("shimmer", false):
		title_lbl.text = "A shimmering %s!" % sp["name"]
	if not Mutations.of(rec).is_empty():
		var pre: String = ("shimmering " if rec.get("shimmer", false) else "") + Mutations.prefix(rec)
		title_lbl.text = "%s %s %s!" % ["An" if "aeiouAEIOU".contains(pre.substr(0, 1)) else "A", pre, sp["name"]]
	sub_lbl.text = "%s kin" % String(sp.get("type", "")).capitalize()
	if rare:
		# a boss's egg: a gold flash, gold rays, a shower of gold
		title_lbl.text = "A RARE %s!" % String(sp["name"]).to_upper()
		title_lbl.add_theme_color_override("font_color", GOLD_RAY.lightened(0.2))
		title_lbl.add_theme_color_override("font_outline_color", Color("6a4a10"))
		sub_lbl.text = "Rare %s kin  ·  hatched from a boss's egg" % String(sp.get("type", "")).capitalize()
		sub_lbl.add_theme_color_override("font_color", GOLD_RAY)
		flash.color = Color(1.0, 0.9, 0.55, 1.0)
		_burst(90)
	var tt := create_tween()
	tt.tween_interval(0.35)
	title_lbl.scale = Vector2(0.6, 0.6)
	tt.tween_property(title_lbl, "modulate:a", 1.0, 0.2)
	tt.parallel().tween_property(title_lbl, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tt.tween_property(sub_lbl, "modulate:a", 1.0, 0.25)
	# then its cry, a happy hop, and the card slides in
	tt.tween_interval(0.35)
	tt.tween_callback(func():
		_play(_cry())
		kin.set_meta("happy", true)
		var hop := create_tween()
		hop.tween_property(kin, "position:y", 0.22, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		hop.tween_property(kin, "position:y", 0.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_burst(24))
	tt.tween_interval(0.5)
	tt.tween_callback(func():
		info.position.x += 60
		var it := create_tween().set_parallel(true)
		it.tween_property(info, "modulate:a", 1.0, 0.3)
		it.tween_property(info, "position:x", info.position.x - 60, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		create_tween().tween_property(hint, "modulate:a", 1.0, 0.4)
		ready_to_name = true
		name_btn.disabled = false
		name_btn.grab_focus())

func _a_an(w: String) -> String:
	return "an" if w.length() > 0 and w[0].to_lower() in "aeiou" else "a"

func _burst(n: int) -> void:
	var c := _centre()
	for i in n:
		var a := randf() * TAU
		var s := randf_range(120.0, 520.0)
		var life := randf_range(0.7, 1.6)
		var pc: Color = [Color.WHITE, glow.lightened(0.4), col.lightened(0.5), Color("fff3b0")].pick_random()
		if rare and randf() < 0.6: pc = [GOLD_RAY, Color("fff3b0"), Color("ffe08a")].pick_random()
		sparks.append({"p": c, "v": Vector2(cos(a), sin(a)) * s, "life": life, "max": life, "s": randf_range(3.0, 7.0), "c": pc})

## Big gold and white four-point stars thrown out in a ring (a shimmer's entrance).
func _shiny_burst() -> void:
	var c := _centre() + Vector2(0, -20)
	for i in 46:
		var a := TAU * i / 46.0 + randf() * 0.08
		var s := randf_range(260.0, 640.0) if i % 2 == 0 else randf_range(90.0, 220.0)
		var life := randf_range(1.0, 1.9)
		var pc: Color = [Color("fff3b0"), Color.WHITE, Color("ffd36a"), glow.lightened(0.5)][i % 4]
		sparks.append({"p": c, "v": Vector2(cos(a), sin(a)) * s, "life": life, "max": life, "s": randf_range(6.0, 11.0), "c": pc})
	flash.color = Color(1.0, 0.95, 0.75, 0.55)
	create_tween().tween_property(flash, "color:a", 0.0, 0.5)

func _centre() -> Vector2:
	var sz := root.size if root and root.size.x > 1.0 else Vector2(1280, 720)
	return Vector2(sz.x * 0.36, sz.y * 0.52)

func _go() -> void:
	if not ready_to_name:
		return
	ready_to_name = false
	Sfx.play("click")
	var tw := create_tween()
	tw.tween_property(root, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func():
		proceed.emit()
		queue_free())

# ------------------------------------------------------------------ per frame
func _process(dt: float) -> void:
	t += dt
	# turning it round: keys and right stick
	var ax := Input.get_axis("left", "right") if not (get_viewport().gui_get_focus_owner() is LineEdit) else 0.0
	var stick := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X) if Input.get_connected_joypads().size() > 0 else 0.0
	if absf(stick) < 0.2: stick = 0.0
	var input := ax + stick
	if absf(input) > 0.05:
		auto_spin = false
		spin_v = lerpf(spin_v, input * 2.6, minf(1.0, dt * 10.0))
	elif not dragging:
		spin_v = lerpf(spin_v, 0.45 if auto_spin else 0.0, minf(1.0, dt * (1.5 if auto_spin else 3.0)))
	if not dragging:
		turn.rotation.y += spin_v * dt
	# sparkles drift and fade, and a few keep rising off the kin
	if randf() < dt * 14.0:
		var c := _centre() + Vector2(randf_range(-110, 110), randf_range(-40, 90))
		var life := randf_range(1.0, 2.0)
		sparks.append({"p": c, "v": Vector2(randf_range(-15, 15), randf_range(-70, -30)), "life": life, "max": life, "s": randf_range(2.0, 4.5), "c": GOLD_RAY.lightened(0.3) if rare and randf() < 0.7 else glow.lightened(0.5)})
	for s in sparks:
		s["life"] -= dt
		s["p"] += s["v"] * dt
		s["v"] *= pow(0.12, dt)
	sparks = sparks.filter(func(s): return s["life"] > 0.0)
	rays.queue_redraw()

func _input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed and not info.get_global_rect().has_point(ev.position):
			dragging = true
			auto_spin = false
			spin_v = 0.0
		elif not ev.pressed:
			dragging = false
	elif ev is InputEventMouseMotion and dragging:
		var d: float = ev.relative.x * 0.012
		turn.rotation.y += d
		spin_v = d / maxf(get_process_delta_time(), 0.001) * 0.5      # a little fling when let go
	elif ev is InputEventScreenDrag:
		auto_spin = false
		turn.rotation.y += ev.relative.x * 0.012
	elif ready_to_name and (ev.is_action_pressed("ui_accept")) and not (get_viewport().gui_get_focus_owner() is LineEdit):
		get_viewport().set_input_as_handled()
		_go()

func _draw_rays() -> void:
	var c := _centre()
	var sz := rays.size
	var reach := sz.length()
	if ray_k > 0.01:
		# soft glow
		for i in 6:
			var r := lerpf(380.0, 60.0, i / 5.0) * (0.9 + 0.1 * sin(t * 2.0))
			rays.draw_circle(c, r, Color(glow.lightened(0.3), 0.05 * ray_k + 0.025 * i * ray_k))
		# turning rays, two rings going opposite ways
		for ring in 2:
			var n := 14 if ring == 0 else 9
			var w := 0.09 if ring == 0 else 0.05
			var rot := t * (0.25 if ring == 0 else -0.4)
			var rc := Color(Color.WHITE.lerp(GOLD_RAY if rare else glow, 0.4 + 0.3 * ring), (0.18 if rare else (0.13 if ring == 0 else 0.09)) * ray_k)
			for i in n:
				var a := rot + TAU * i / n
				var pts := PackedVector2Array([c,
					c + Vector2(cos(a - w), sin(a - w)) * reach,
					c + Vector2(cos(a + w), sin(a + w)) * reach])
				rays.draw_colored_polygon(pts, rc)
		rays.draw_circle(c, 70.0 + 6.0 * sin(t * 3.0), Color(1, 1, 1, 0.12 * ray_k))
		if rare:
			# a slow gold halo of shimmering motes
			for i in 24:
				var a2 := t * 0.6 + TAU * i / 24.0
				var rr := 170.0 + 10.0 * sin(t * 2.0 + i)
				rays.draw_circle(c + Vector2(cos(a2), sin(a2)) * rr, 3.0 + 2.0 * (0.5 + 0.5 * sin(t * 5.0 + i * 1.7)), Color(GOLD_RAY, 0.7 * ray_k))
	# sparkles: little four-point stars
	for s in sparks:
		var k: float = clampf(s["life"] / s["max"], 0.0, 1.0)
		var p: Vector2 = s["p"]
		var r: float = s["s"] * (0.5 + 0.5 * k)
		var cc: Color = s["c"]; cc.a = k
		rays.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r * 2.2), p + Vector2(r * 0.45, 0), p + Vector2(0, r * 2.2), p + Vector2(-r * 0.45, 0)]), cc)
		rays.draw_colored_polygon(PackedVector2Array([p + Vector2(-r * 2.2, 0), p + Vector2(0, r * 0.45), p + Vector2(r * 2.2, 0), p + Vector2(0, -r * 0.45)]), cc)

# ------------------------------------------------------------------ sound (made here, no files)
func _play(s: AudioStreamWAV) -> void:
	var p := AudioStreamPlayer.new()
	p.bus = "SFX"
	p.stream = s
	p.volume_db = -6.0
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

## A short rising fanfare: a quick arpeggio up, then a bright held chord with a shimmer on top.
func _jingle() -> AudioStreamWAV:
	var notes := [[72, 0.0, 0.09], [76, 0.09, 0.09], [79, 0.18, 0.09], [84, 0.27, 0.12], [83, 0.42, 0.08], [86, 0.5, 0.7], [79, 0.5, 0.7], [76, 0.5, 0.7]]
	# nudge the key by species, so each kin's fanfare sits a little differently
	var shift: int = [0, 2, -3, 3, -5, 5][absi(species.hash()) % 6]
	var dur := 1.35
	var buf := PackedFloat32Array(); buf.resize(int(dur * RATE))
	for nt in notes:
		var f := 440.0 * pow(2.0, (float(nt[0] + shift) - 69.0) / 12.0)
		var s0 := int(float(nt[1]) * RATE)
		var len := int(float(nt[2]) * RATE)
		for i in len:
			var ti := float(i) / RATE
			var env := minf(1.0, ti / 0.008) * exp(-ti * (3.0 if float(nt[2]) > 0.3 else 9.0))
			# a rounded tone (a sine with a hint of odd harmonics) with a little vibrato on the long notes
			var ph := TAU * f * ti + (sin(TAU * 6.0 * ti) * 0.04 * minf(1.0, ti * 4.0) if float(nt[2]) > 0.3 else 0.0)
			var v := sin(ph) + sin(ph * 3.0) / 3.0 * 0.3 + sin(ph * 2.0) * 0.12
			var j := s0 + i
			if j < buf.size(): buf[j] += v * env * 0.22
	# a soft sparkle of little bells over the chord (an octave lower than a glint, and faded in)
	var rng := RandomNumberGenerator.new(); rng.seed = species.hash()
	for k in 7:
		var f2 := 440.0 * pow(2.0, (float(84 + [0, 4, 7, 12][k % 4] + shift) - 69.0) / 12.0)
		var s1 := int((0.55 + k * 0.07 + rng.randf() * 0.02) * RATE)
		for i in int(0.12 * RATE):
			var ti := float(i) / RATE
			var j := s1 + i
			if j < buf.size(): buf[j] += sin(TAU * f2 * ti) * minf(1.0, ti / 0.004) * exp(-ti * 25.0) * 0.04
	return _wav(buf)

## The kin's own little cry: two chirpy syllables, pitched and shaped by its species.
func _cry() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new(); rng.seed = species.hash() * 7 + 3
	var base := lerpf(300.0, 820.0, rng.randf())
	var spd := float(sp.get("speed", 6.5))
	base *= clampf(spd / 6.5, 0.75, 1.3)
	var dur := 0.62
	var buf := PackedFloat32Array(); buf.resize(int(dur * RATE))
	var syl := [[0.0, 0.2, 1.0, 1.45], [0.25, 0.34, 1.3, 0.9]]   # start, length, pitch from, pitch to
	var ph := 0.0
	for sy in syl:
		var s0 := int(float(sy[0]) * RATE)
		var len := int(float(sy[1]) * RATE)
		ph = 0.0
		for i in len:
			var k := float(i) / len
			var f := base * lerpf(float(sy[2]), float(sy[3]), k * k * (3.0 - 2.0 * k))
			f *= 1.0 + sin(TAU * 22.0 * k * float(sy[1])) * 0.04
			ph += TAU * f / RATE
			var env := sin(PI * minf(1.0, k * 1.15)) * (1.0 - k * 0.3)
			var v := sin(ph) * 0.7 + sin(ph * 2.0) * 0.22 + sin(ph * 3.0) * 0.08
			var j := s0 + i
			if j < buf.size(): buf[j] += v * env * 0.4
	return _wav(buf)

func _wav(buf: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray(); data.resize(buf.size() * 2)
	for i in buf.size():
		var s := int(clampf(tanh(buf[i] * 1.2), -1.0, 1.0) * 32000.0)
		data.encode_s16(i * 2, s)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w
