extends Control
## After a match: what you brought home, what your kin thinks, and the way back to the farm.

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UI.theme()

func show_result(r: Dictionary) -> void:
	Sfx.play_music("title")
	Sfx.play_ambience("")
	shown_at = Time.get_ticks_msec()
	var s := Game.apply_result(r)
	var bg := ColorRect.new(); bg.color = UI.BG; bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(bg)
	_stage(r, s)
	var won: bool = r.get("extracted", false)
	# a warm (or cold) wash from the right so the card sits in light
	var wash := TextureRect.new()
	var gt := GradientTexture2D.new(); var gr := Gradient.new()
	gr.set_color(0, Color(0.03, 0.02, 0.07, 0.0)); gr.set_color(1, Color(0.03, 0.02, 0.07, 0.82))
	gr.set_offset(0, 0.25); gr.set_offset(1, 0.7)
	gt.gradient = gr; gt.fill_from = Vector2(0, 0); gt.fill_to = Vector2(1, 0); gt.width = 256; gt.height = 4
	wash.texture = gt; wash.stretch_mode = TextureRect.STRETCH_SCALE
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wash)
	var center := CenterContainer.new(); center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(center)
	center.offset_left = 340.0   # leave the left side for the island
	var panel := PanelContainer.new(); panel.custom_minimum_size = Vector2(580, 0); center.add_child(panel)
	UI.pop_in(panel, 0.1)
	var outer := UI.vbox(14)
	panel.add_child(outer)
	var v := UI.vbox(10)
	# the details scroll if they're taller than the window; the way home stays below them, always visible
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var pad := MarginContainer.new(); pad.add_theme_constant_override("margin_right", 12)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(v)
	sc.add_child(pad)
	outer.add_child(sc)
	var fit := func() -> void:
		if is_instance_valid(sc) and sc.is_inside_tree():
			sc.custom_minimum_size.y = minf(pad.get_combined_minimum_size().y, sc.get_viewport_rect().size.y - 200.0)
	v.minimum_size_changed.connect(func(): fit.call_deferred())
	sc.tree_entered.connect(func(): fit.call_deferred())
	# header: a coloured kicker, the outcome, one line on what it means
	var tier_name := String(Data.TIERS[clampi(Game.last_tier, 0, Data.TIERS.size() - 1)]["name"])
	var kick := "FIRST EXPEDITION" if r.get("tutorial", false) else tier_name.to_upper()
	var head := UI.vbox(2)
	head.add_child(UI.section(kick + ("  ·  EXTRACTED" if won else "  ·  DIDN'T MAKE IT"), UI.TEAL if won else Color("ff9a8a")))
	head.add_child(UI.title("You made it out" if won else _lost_title(r.get("why", "")), 46, UI.INK))
	head.add_child(UI.label("Everything you carried is yours now." if won else "Everything you carried stays out in the islands.", 16, UI.MUTED))
	v.add_child(head)
	var rule := ColorRect.new(); rule.custom_minimum_size = Vector2(0, 3)
	rule.color = Color(UI.TEAL if won else UI.BAD, 0.55)
	v.add_child(rule)
	# three stat tiles that count up
	var secs := int(r.get("time", 0))
	var rows := [
		[["knock", "Knocks", float(r.get("knocks", 0)), ""], ["burst", "Damage dealt", float(r.get("damage", 0)), ""],
			["burst", "Damage taken", float(r.get("taken", 0)), ""], ["clock", "Time", float(secs), "time"]],
		[["knock", "Kills", float(r.get("kills", 0)), ""], ["knock", "Times downed", float(r.get("downs", 0)), ""],
			["heart", "Revives", float(r.get("revives", 0)), ""], ["gem", "Armor reached", float(r.get("armor_tier", 0)), "armor"]],
	]
	var n := 0
	for row in rows:
		var stats := UI.hbox(10)
		for t in row:
			stats.add_child(_stat_tile(t[0], t[1], t[2], t[3], 0.35 + n * 0.08))
			n += 1
		v.add_child(stats)
	if won:
		var chips: Array = []
		if int(s["gems"]) > 0:
			chips.append(["gem", "%d gems" % s["gems"], UI.GOLD])
		for sd in s["seeds"]:
			chips.append(["seed", "%d %s seeds" % [s["seeds"][sd], Data.CROPS[sd]["name"]], Data.CROPS[sd]["color"]])
		for k in s["caught"]:
			chips.append(["egg", "%s the %s" % [k["name"], Data.KIN[k["species"]]["name"]], Data.KIN[k["species"]]["color"]])
		if not chips.is_empty():
			v.add_child(UI.section("Brought home"))
			var flow := HFlowContainer.new()
			flow.add_theme_constant_override("h_separation", 8); flow.add_theme_constant_override("v_separation", 8)
			for i in chips.size():
				flow.add_child(_chip(chips[i][0], chips[i][1], chips[i][2], 0.75 + i * 0.14))
			v.add_child(flow)
	if s.has("kin"):
		v.add_child(_kin_card(s))
	for back in s.get("rescued", []):
		v.add_child(_note("You took %s back! It's home again, and it won't forget you came for it." % back["name"], UI.GOOD))
	# kin left behind when you went down, and where they ended up
	var lost_news: Array = s.get("lost_news", [])
	if not lost_news.is_empty():
		var lc := UI.card(Color(0.17, 0.07, 0.08, 0.92))
		UI.set_card_border(lc, Color(UI.BAD, 0.45), 1)
		var lv := UI.vbox(6); lc.add_child(lv)
		lv.add_child(UI.section("Left behind", Color("ffb0a0")))
		for ln in lost_news:
			var kk: Dictionary = ln["kin"]
			var txt := ""
			var col := UI.BAD
			match String(ln["fate"]):
				"squad": txt = "%s was carried home by your squadmate %s." % [kk["name"], ln["holder"]]; col = UI.GOOD
				"home": txt = "%s found its own way home. It trusts you that much." % kk["name"]; col = UI.GOOD
				"rival": txt = "%s was collected by %s. Make them an offer at the Ransom House, or find them out there and take it back." % [kk["name"], ln["holder"]]
				_: txt = "Nobody collected %s. It's waiting at the Ransom House on your farm." % kk["name"]; col = Color("ffd58a")
			var l := UI.label(txt, 15, col); l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lv.add_child(l)
		v.add_child(lc)
	for nw in s.get("ransom_news", []):
		v.add_child(_note(String(nw), Color("ffd58a")))
	if s.get("kin_stranded", false):
		v.add_child(_note("With no kin left at home, %s let one of yours go on credit. It waited a long time and trusts you less now." % Ransom.BROKER, UI.BAD))
	if int(s.get("vault_gems", 0)) > 0:
		v.add_child(_note("Your vault kept %d of the gems you dropped." % int(s["vault_gems"]), UI.GOLD))
	if s["crops_ready"] > 0:
		v.add_child(_note("%d crop%s ready to harvest on your farm." % [s["crops_ready"], "s" if s["crops_ready"] > 1 else ""], UI.GOOD))
	# the way out stays on screen whatever page the details are on
	var row := UI.hbox(14)
	var go := UI.primary("Go home" if r.get("tutorial", false) else "Back to the farm", func(): Game.goto("home"), 240)
	row.add_child(go)
	if r.get("tutorial", false):
		var tl := UI.label("That's the basics. Now come see your home.", 15, UI.GOLD)
		tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tl)
	var kh := UI.key_hints([["Enter", "continue"]], 12, Color(1, 1, 1, 0.5))
	kh.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(kh)
	outer.add_child(row)
	go.grab_focus()
	Sfx.play("bond" if won else "fall", null, -6.0, 0.0, 1.0 if won else 0.8)

## A tile with an icon, a number that counts up from zero, and what it is.
func _stat_tile(icon: String, what: String, value: float, fmt: String, delay: float) -> Control:
	var c := UI.card(Color(1, 1, 1, 0.05), 12, 12)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := UI.hbox(10); c.add_child(h)
	h.add_child(Icons.Glyph.new(icon, Color(1, 0.86, 0.6, 0.9), 34.0))
	var col := UI.vbox(0); h.add_child(col)
	var num := UI.title("0" if fmt == "" else "0:00", 24)
	col.add_child(num)
	if fmt == "armor":
		# the armor tier you finished on, in its own colour
		var tier: Array = Hunter.ARMOR_TIERS[clampi(int(value), 0, Hunter.ARMOR_TIERS.size() - 1)]
		num.text = String(tier[0]); num.add_theme_color_override("font_color", tier[1])
		col.add_child(UI.label(what.to_upper(), 11, UI.MUTED, UI.caps))
		return c
	var lab := UI.label(what.to_upper(), 11, UI.MUTED, UI.caps); lab.autowrap_mode = TextServer.AUTOWRAP_OFF
	col.add_child(lab)
	var show := func(x: float) -> void:
		num.text = ("%d:%02d" % [int(x) / 60, int(x) % 60]) if fmt == "time" else str(int(round(x)))
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_method(show, 0.0, value, clampf(0.4 + value * 0.01, 0.5, 1.1)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return c

## One thing you brought home, as a little pill that pops in with a sound.
func _chip(icon: String, txt: String, col: Color, delay: float) -> Control:
	var c := UI.card(Color(col, 0.16), 8, 999)
	UI.set_card_border(c, Color(col, 0.55), 1)
	var h := UI.hbox(7); c.add_child(h)
	h.add_child(Icons.Glyph.new(icon, col.lightened(0.15), 18.0))
	var l := UI.label(txt, 15, UI.INK); l.autowrap_mode = TextServer.AUTOWRAP_OFF
	h.add_child(l)
	c.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func(): Sfx.play("pickup", null, -8.0, 0.08, 1.0 + delay * 0.1); UI.pop_in(c))
	return c

## Your kin's card: how it feels about you now (the trust bar slides to where it ended up), and
## what it will remember about this one.
func _kin_card(s: Dictionary) -> Control:
	var k: Dictionary = s["kin"]
	var sp: Dictionary = Data.KIN.get(String(k.get("species", "")), {})
	var kcol: Color = sp.get("color", UI.ACCENT)
	var kc := UI.card(Color(0.12, 0.13, 0.19, 0.95), 14, 12)
	UI.set_card_border(kc, Color(kcol, 0.4), 1)
	var kv := UI.vbox(7); kc.add_child(kv)
	var top := UI.hbox(10); kv.add_child(top)
	top.add_child(Icons.Glyph.new("paw", kcol, 22.0))
	var nm := UI.title(String(k["name"]), 24, UI.INK); top.add_child(nm)
	var lvl := UI.label("level %d %s" % [int(k["level"]), String(sp.get("name", ""))], 14, UI.MUTED)
	lvl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(lvl)
	var td: float = s.get("trust_delta", 0.0)
	var mood := "trusts you more" if td > 0.5 else ("trusts you less" if td < -0.5 else "feels the same about you")
	var trow := UI.hbox(10); kv.add_child(trow)
	var tl := UI.label("Trust", 13, UI.MUTED); tl.custom_minimum_size.x = 46; trow.add_child(tl)
	var now := clampf(float(k["trust"]) / 100.0, 0.0, 1.0)
	var was := clampf((float(k["trust"]) - td) / 100.0, 0.0, 1.0)
	var bar_box := Control.new(); bar_box.custom_minimum_size = Vector2(240, 10); bar_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var frac := {"v": was}
	bar_box.draw.connect(func():
		var r := Rect2(Vector2.ZERO, bar_box.size)
		bar_box.draw_rect(r, Color(0, 0, 0, 0.4))
		bar_box.draw_rect(Rect2(r.position, Vector2(r.size.x * float(frac["v"]), r.size.y)), UI.GOOD if td >= 0.0 else Color("ffb36a")))
	trow.add_child(bar_box)
	var ml := UI.label("%s  (%+d)" % [mood, int(round(td))] if absf(td) >= 0.5 else mood, 14, UI.GOOD if td > 0.5 else (Color("ffb36a") if td < -0.5 else UI.MUTED))
	trow.add_child(ml)
	var tw := create_tween()
	tw.tween_interval(1.0)
	tw.tween_method(func(x: float): frac["v"] = x; bar_box.queue_redraw(), was, now, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if s["levelup"]:
		var lu := UI.label("%s grew to level %d!" % [k["name"], k["level"]], 17, UI.GOLD, UI.big)
		kv.add_child(lu)
		tw.tween_callback(func(): Sfx.play("unlock", null, -4.0); UI.pop_in(lu))
	for et in s.get("evo", []):
		kv.add_child(UI.label(et, 15, Color("c9a0ff")))
	var mem: Array = k["memory"]
	for i in range(maxi(0, mem.size() - 1), mem.size()):
		var l := UI.label("Remembers: " + String(mem[i]["text"]), 14, Color(UI.MUTED, 0.9))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		kv.add_child(l)
	return kc

func _note(txt: String, col: Color) -> Label:
	var l := UI.label(txt, 15, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

var shown_at := 0
## Enter, Space or Esc also takes you home, so you can never get stuck on this screen.
func _unhandled_input(e: InputEvent) -> void:
	if Time.get_ticks_msec() - shown_at < 900:
		return
	if e.is_action_pressed("ui_accept") or e.is_action_pressed("menu") or e.is_action_pressed("jump"):
		get_viewport().set_input_as_handled()
		Game.goto("home")

var hunter_node: Node3D
var h_anim: HunterAnim
var kin_node: Node3D
var won_k := false
var t := 0.0

## Behind the card: your hunter and kin on a little island, cheering if you made it out,
## sitting it out if you didn't.
func _stage(r: Dictionary, s: Dictionary) -> void:
	won_k = r.get("extracted", false)
	var svc := SubViewportContainer.new(); svc.stretch = true
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(svc)
	var vp := SubViewport.new(); vp.own_world_3d = true; vp.msaa_3d = Viewport.MSAA_2X
	svc.add_child(vp)
	var w3 := Node3D.new(); vp.add_child(w3)
	var env := WorldEnvironment.new(); env.environment = Look.environment({}); w3.add_child(env)
	if not won_k:
		Look.night(env.environment, 0.6)
	Look.lights(w3, Color("fff1d8") if won_k else Color("b9c4ff"), 1.05 if won_k else 0.7)
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	var isl := Models.float_island(rng, 2.6, 5.0, Color("6aa64a"), Color("9a7a5a"), Color("3a2f48"))
	w3.add_child(isl)
	var tr := Models.tree(rng, Color("5a9a4f"), "round"); tr.position = Vector3(-1.4, 0, -1.2); w3.add_child(tr)
	var rk := Models.rock(rng, 0.7); rk.position = Vector3(1.5, 0, -0.9); w3.add_child(rk)
	hunter_node = Models.hunter(Data.class_of_save(), Data.TEAM_COLORS[0], Data.weapon_for(Data.class_of_save(), String(Save.d.get("weapon", ""))), "", Save.d.get("look", {}))
	hunter_node.position = Vector3(-0.3, 0, 0.3); hunter_node.rotation.y = PI + 0.5
	var ring := hunter_node.get_node_or_null("TeamRing") as Node3D
	if ring: ring.visible = false
	w3.add_child(hunter_node)
	h_anim = HunterAnim.new(hunter_node)
	if s.has("kin") and won_k:
		kin_node = Models.kin(String(s["kin"]["species"]), s["kin"])
		kin_node.position = Vector3(0.75, 0, 0.6); kin_node.rotation.y = PI + 0.9
		kin_node.set_meta("happy", true)
		w3.add_child(kin_node)
	var cam := Camera3D.new(); cam.fov = 40
	# the island sits left of the results card
	cam.position = Vector3(4.6, 2.6, 8.4)
	w3.add_child(cam)
	cam.look_at(Vector3(3.3, 0.6, 0))

func _process(dt: float) -> void:
	t += dt
	if h_anim:
		var vy := 0.0
		if won_k:
			# a little victory hop every couple of seconds
			var ph := fmod(t, 2.2)
			hunter_node.position.y = maxf(0.0, sin(ph / 0.5 * PI)) * 0.35 if ph < 0.5 else 0.0
			vy = cos(ph / 0.5 * PI) * 2.0 if ph < 0.5 else 0.0
		h_anim.update(dt, {"grounded": hunter_node.position.y < 0.01, "vel": Vector3(0, vy, 0), "crouch": 0.0 if won_k else 0.7, "downed": false})
	if kin_node:
		kin_node.get_node("Body").position.y = absf(sin(t * 5.0)) * 0.25

func _lost_title(why: String) -> String:
	match why:
		"abyss": return "You fell"
		"left": return "You left the match"
	return "Knocked out"
