class_name UI
## Small helpers for building the menus in code with one consistent look.

const INK := Color("f3eee2")
const MUTED := Color("a9b0bf")
const BG := Color("12151f")
const PANEL := Color(0.08, 0.09, 0.13, 0.94)
const CARD := Color(0.13, 0.14, 0.2, 1.0)
const ACCENT := Color("f2a24a")
const GOOD := Color("8fe0a0")
const BAD := Color("ff6a5a")
const GOLD := Color("f2c84a")
const TEAL := Color("8fe3c8")

static var big: Font = preload("res://fonts/LilitaOne-Regular.ttf")
static var body: Font = preload("res://fonts/Rubik.ttf")
static var _theme: Theme
static var semi: FontVariation       # Rubik at a heavier weight, for buttons and small headers
static var caps: FontVariation       # spaced-out bold, for section headers

static func _box(bg: Color, rad := 10, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.set_corner_radius_all(rad)
	if bw > 0:
		b.border_color = border
		b.set_border_width_all(bw)
	b.anti_aliasing = true
	return b

## A chunky game button: a raised face with a darker lip underneath that sinks when pressed.
static func _btn(face: Color, lip: Color, pressed := false) -> StyleBoxFlat:
	var b := _box(face, 11)
	b.border_color = lip
	b.border_width_bottom = 2 if pressed else 5
	b.border_width_top = 3 if pressed else 0
	b.border_blend = false
	b.content_margin_left = 18; b.content_margin_right = 18
	b.content_margin_top = 9; b.content_margin_bottom = 8
	b.shadow_color = Color(0, 0, 0, 0.25 if not pressed else 0.1)
	b.shadow_size = 4 if not pressed else 1
	b.shadow_offset = Vector2(0, 2)
	return b

static func _circle_tex(d: int, col: Color, ring := Color(0, 0, 0, 0)) -> ImageTexture:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c := (d - 1) * 0.5
	for y in d:
		for x in d:
			var r := Vector2(x - c, y - c).length()
			var a := clampf(c - r + 0.5, 0.0, 1.0)
			var px := col
			if ring.a > 0.0 and r > c - 2.5: px = ring
			img.set_pixel(x, y, Color(px, px.a * a))
	return ImageTexture.create_from_image(img)

static func _toggle_tex(on: bool) -> ImageTexture:
	var w := 46; var h := 26
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var track := ACCENT if on else Color(0.24, 0.26, 0.34)
	var knob := Color("fff7e8")
	var kr := 9.0
	var kx := (w - 13.0) if on else 13.0
	for y in h:
		for x in w:
			# a pill
			var cx := clampf(float(x), h * 0.5, w - h * 0.5)
			var dt := Vector2(x - cx, y - (h - 1) * 0.5).length()
			var a := clampf(h * 0.5 - dt, 0.0, 1.0)
			var px := track
			var dk := Vector2(x - kx, y - (h - 1) * 0.5).length()
			if dk < kr + 0.5:
				px = knob
			img.set_pixel(x, y, Color(px, a))
	return ImageTexture.create_from_image(img)

static func theme() -> Theme:
	if _theme:
		return _theme
	semi = FontVariation.new(); semi.base_font = body; semi.variation_opentype = {"wght": 560}
	caps = FontVariation.new(); caps.base_font = body; caps.variation_opentype = {"wght": 700}; caps.spacing_glyph = 1
	var t := Theme.new()
	t.default_font = body
	t.default_font_size = 16
	# buttons
	var face := Color(0.2, 0.22, 0.31); var lip := Color(0.1, 0.11, 0.17)
	t.set_stylebox("normal", "Button", _btn(face, lip))
	t.set_stylebox("hover", "Button", _btn(face.lightened(0.12), lip))
	t.set_stylebox("pressed", "Button", _btn(face.darkened(0.12), lip, true))
	t.set_stylebox("hover_pressed", "Button", _btn(face.darkened(0.06), lip, true))
	var dis := _btn(Color(0.14, 0.15, 0.2), Color(0.09, 0.1, 0.13)); dis.shadow_size = 0
	t.set_stylebox("disabled", "Button", dis)
	var foc := _box(Color(0, 0, 0, 0), 11, Color(ACCENT, 0.8), 2)
	t.set_stylebox("focus", "Button", foc)
	t.set_font("font", "Button", semi)
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", Color(0.48, 0.5, 0.57))
	# the main action on a screen
	t.add_type("Primary"); t.set_type_variation("Primary", "Button")
	var pf := ACCENT; var pl := ACCENT.darkened(0.42)
	t.set_stylebox("normal", "Primary", _btn(pf, pl))
	t.set_stylebox("hover", "Primary", _btn(pf.lightened(0.12), pl))
	t.set_stylebox("pressed", "Primary", _btn(pf.darkened(0.08), pl, true))
	t.set_stylebox("hover_pressed", "Primary", _btn(pf.darkened(0.04), pl, true))
	var dark_ink := Color(0.12, 0.08, 0.05)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(c, "Primary", dark_ink)
	# the picked option in a row of choices
	t.add_type("Chosen"); t.set_type_variation("Chosen", "Button")
	var cf := Color(0.27, 0.24, 0.2); var cl := ACCENT.darkened(0.3)
	var cn := _btn(cf, cl); cn.border_color = cl; cn.border_width_left = 2; cn.border_width_right = 2; cn.border_width_top = 2
	cn.border_color = ACCENT
	t.set_stylebox("normal", "Chosen", cn)
	var ch := cn.duplicate(); ch.bg_color = cf.lightened(0.08)
	t.set_stylebox("hover", "Chosen", ch)
	t.set_stylebox("pressed", "Chosen", cn)
	t.set_color("font_color", "Chosen", Color("ffd79a"))
	t.set_color("font_hover_color", "Chosen", Color("ffe2b3"))
	# text boxes
	var le := _box(Color(0.08, 0.09, 0.13), 9, Color(1, 1, 1, 0.1), 1)
	le.content_margin_left = 12; le.content_margin_right = 12; le.content_margin_top = 9; le.content_margin_bottom = 9
	var lf := le.duplicate(); lf.border_color = Color(ACCENT, 0.85); lf.set_border_width_all(2)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", lf)
	t.set_color("font_placeholder_color", "LineEdit", Color(0.55, 0.57, 0.64))
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", Color(ACCENT, 0.35))
	t.set_color("font_color", "Label", INK)
	# panels: a soft lit edge and a drop shadow
	var pc := _box(PANEL, 18, Color(1, 1, 1, 0.07), 1)
	pc.border_width_top = 2; pc.border_color = Color(1, 1, 1, 0.09)
	pc.shadow_color = Color(0, 0, 0, 0.5); pc.shadow_size = 26; pc.shadow_offset = Vector2(0, 10)
	pc.content_margin_left = 26; pc.content_margin_right = 26; pc.content_margin_top = 20; pc.content_margin_bottom = 22
	t.set_stylebox("panel", "PanelContainer", pc)
	# scroll bars: thin and quiet
	for sb_t in ["VScrollBar", "HScrollBar"]:
		var gr := _box(Color(1, 1, 1, 0.18), 5); gr.content_margin_left = 4; gr.content_margin_right = 4
		t.set_stylebox("grabber", sb_t, gr)
		t.set_stylebox("grabber_highlight", sb_t, _box(Color(1, 1, 1, 0.3), 5))
		t.set_stylebox("grabber_pressed", sb_t, _box(Color(ACCENT, 0.6), 5))
		var tr := _box(Color(0, 0, 0, 0.2), 5); tr.content_margin_left = 4; tr.content_margin_right = 4
		t.set_stylebox("scroll", sb_t, tr)
	# sliders
	var sl := _box(Color(0, 0, 0, 0.35), 4); sl.content_margin_top = 3; sl.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", sl)
	var ga := _box(ACCENT.darkened(0.1), 4); ga.content_margin_top = 3; ga.content_margin_bottom = 3
	t.set_stylebox("grabber_area", "HSlider", ga)
	t.set_stylebox("grabber_area_highlight", "HSlider", ga)
	t.set_icon("grabber", "HSlider", _circle_tex(20, Color("fff7e8"), ACCENT))
	t.set_icon("grabber_highlight", "HSlider", _circle_tex(22, Color.WHITE, ACCENT.lightened(0.2)))
	# toggles
	t.set_icon("checked", "CheckButton", _toggle_tex(true))
	t.set_icon("unchecked", "CheckButton", _toggle_tex(false))
	t.set_icon("checked_disabled", "CheckButton", _toggle_tex(true))
	t.set_icon("unchecked_disabled", "CheckButton", _toggle_tex(false))
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		t.set_stylebox(st, "CheckButton", empty)
	t.set_font("font", "CheckButton", body)
	t.set_color("font_color", "CheckButton", INK)
	t.set_color("font_hover_color", "CheckButton", Color.WHITE)
	t.set_color("font_pressed_color", "CheckButton", INK)
	t.set_color("font_hover_pressed_color", "CheckButton", Color.WHITE)
	# drop-downs and their lists
	t.set_stylebox("normal", "OptionButton", _btn(face, lip))
	t.set_stylebox("hover", "OptionButton", _btn(face.lightened(0.12), lip))
	t.set_stylebox("pressed", "OptionButton", _btn(face.darkened(0.12), lip, true))
	t.set_stylebox("focus", "OptionButton", foc)
	var pm := _box(Color(0.1, 0.11, 0.16, 0.98), 10, Color(1, 1, 1, 0.1), 1)
	pm.content_margin_left = 6; pm.content_margin_right = 6; pm.content_margin_top = 6; pm.content_margin_bottom = 6
	t.set_stylebox("panel", "PopupMenu", pm)
	t.set_stylebox("hover", "PopupMenu", _box(Color(ACCENT, 0.25), 6))
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	# tooltips
	var tp := _box(Color(0.07, 0.08, 0.11, 0.97), 8, Color(1, 1, 1, 0.12), 1)
	tp.content_margin_left = 10; tp.content_margin_right = 10; tp.content_margin_top = 6; tp.content_margin_bottom = 6
	t.set_stylebox("panel", "TooltipPanel", tp)
	t.set_color("font_color", "TooltipLabel", INK)
	t.set_stylebox("separator", "HSeparator", _box(Color(1, 1, 1, 0.08), 1))
	t.set_constant("separation", "HSeparator", 6)
	_theme = t
	return t

## The main button of a screen (orange, dark text).
static func primary(text: String, cb: Callable, minw := 0.0) -> Button:
	var b := button(text, cb, minw)
	b.theme_type_variation = "Primary"
	return b

## One option in a row of choices; the chosen one is highlighted instead of marked with a symbol.
static func choice(text: String, chosen: bool, cb: Callable, minw := 0.0) -> Button:
	var b := button(text, cb, minw)
	if chosen:
		b.theme_type_variation = "Chosen"
	return b

## A small spaced-out heading for a group of things in a menu.
static func section(text: String, col := Color("c9a46a")) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_override("font", caps if caps else body)
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", col)
	return l

static func label(text: String, size := 16, col := INK, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if font:
		l.add_theme_font_override("font", font)
	# short labels sit on one line; only real sentences wrap (a wrapping label in a row collapses to nothing)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if text.length() > 48 else TextServer.AUTOWRAP_OFF
	return l

static func title(text: String, size := 34, col := INK) -> Label:
	var l := label(text, size, col, big)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l

static func button(text: String, cb: Callable, minw := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func(): Sfx.play("click"); cb.call())
	if minw > 0.0:
		b.custom_minimum_size.x = minw
	# a little lift and tick on hover
	b.resized.connect(func(): b.pivot_offset = b.size * 0.5)
	b.mouse_entered.connect(func():
		if b.disabled: return
		Sfx.play("hover", null, -12.0, 0.05)
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2(1.035, 1.035), 0.08).set_trans(Tween.TRANS_SINE))
	b.mouse_exited.connect(func():
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2.ONE, 0.1).set_trans(Tween.TRANS_SINE))
	return b

## Fades and scales a panel in, so menus open instead of just appearing.
static func pop_in(c: Control, delay := 0.0) -> void:
	c.modulate.a = 0.0
	c.scale = Vector2(0.94, 0.94)
	var set_pivot := func(): c.pivot_offset = c.size * 0.5
	c.resized.connect(set_pivot)
	set_pivot.call()
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "modulate:a", 1.0, 0.16).set_delay(delay)
	tw.tween_property(c, "scale", Vector2.ONE, 0.26).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

static func card(col := CARD, pad := 14, rad := 12) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(rad)
	sb.content_margin_left = pad; sb.content_margin_right = pad; sb.content_margin_top = pad; sb.content_margin_bottom = pad
	p.add_theme_stylebox_override("panel", sb)
	return p

static func set_card_border(p: PanelContainer, col: Color, w := 2) -> void:
	var sb: StyleBoxFlat = p.get_theme_stylebox("panel").duplicate()
	sb.border_color = col
	sb.set_border_width_all(w)
	p.add_theme_stylebox_override("panel", sb)

static func vbox(sep := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v

static func hbox(sep := 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h

static func bar(frac: float, col: Color, w := 120.0, h := 8.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.draw.connect(func():
		var r := minf(c.size.y * 0.5, 4.0)
		var bg := StyleBoxFlat.new(); bg.bg_color = Color(0, 0, 0, 0.4); bg.set_corner_radius_all(int(r))
		c.draw_style_box(bg, Rect2(Vector2.ZERO, c.size))
		var fw := c.size.x * clampf(frac, 0.0, 1.0)
		if fw > 1.0:
			var fg := StyleBoxFlat.new(); fg.bg_color = col; fg.set_corner_radius_all(int(r))
			c.draw_style_box(fg, Rect2(Vector2.ZERO, Vector2(fw, c.size.y))))
	return c

static func spacer(h := 8.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	return c

## Wraps content in a scroll box that grows with it up to the window height minus `margin`.
## Nothing in the game scrolls. When a menu has more than fits on screen, it splits into pages
## with a small "Page 1 of 2" control, and it remembers which page you were on when it's rebuilt,
## so clicking a button never jumps you somewhere else.
static var _page_of := {}       # menu key -> page shown
static var _tall := {}          # menu key -> tallest the menu has been, so it never jumps around
static var _live := {}          # menu key -> how many of it are open

## Wraps a VBox of content so it pages instead of overflowing. margin: room left for the rest of
## the screen. Returns the wrapper to add where the content would have gone.
static func paged(content: VBoxContainer, margin: float, key: String, head: Control = null, width_hint := 600.0) -> VBoxContainer:
	var wrap := vbox(8)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_child(content)
	var pager := hbox(10)
	pager.alignment = BoxContainer.ALIGNMENT_CENTER
	pager.visible = false
	var prev := button("‹  Back", Callable(), 110)
	var lbl := label("", 14, MUTED)
	var next := button("Next  ›", Callable(), 110)
	pager.add_child(prev); pager.add_child(lbl); pager.add_child(next)
	wrap.add_child(pager)
	var state := {"busy": false, "t0": 0}
	var fit := func() -> void:
		if state["busy"] or not is_instance_valid(content) or not content.is_inside_tree():
			return
		state["busy"] = true
		var vp := content.get_viewport_rect().size
		var maxh := maxf(160.0, vp.y - margin - (head.get_combined_minimum_size().y if head else 0.0))
		var w := content.size.x if content.size.x > 60.0 else width_hint
		_paginate(content, maxh - pager.get_combined_minimum_size().y - 8.0, key, pager, lbl, prev, next, w)
		# never shrink while it's open, so the menu doesn't hop as its contents change. Sizes are
		# only trusted once the layout has settled (wrapped text measures tall at first).
		content.custom_minimum_size.y = 0.0
		var h := content.get_combined_minimum_size().y
		if Time.get_ticks_msec() - int(state["t0"]) > 300:
			_tall[key] = maxf(float(_tall.get(key, 0.0)), h)
		content.custom_minimum_size.y = minf(float(_tall.get(key, 0.0)), maxh)
		state["busy"] = false
	var refit := func() -> void:
		if not state["busy"]: fit.call_deferred()
	prev.pressed.connect(func(): _page_of[key] = maxi(0, int(_page_of.get(key, 0)) - 1); Sfx.play("click"); fit.call())
	next.pressed.connect(func(): _page_of[key] = int(_page_of.get(key, 0)) + 1; Sfx.play("click"); fit.call())
	content.minimum_size_changed.connect(refit)
	content.child_entered_tree.connect(func(_c): refit.call())
	wrap.tree_entered.connect(func():
		_live[key] = int(_live.get(key, 0)) + 1
		state["t0"] = Time.get_ticks_msec()
		refit.call()
		wrap.get_tree().create_timer(0.35).timeout.connect(func(): if is_instance_valid(wrap): refit.call())
		var vpt := wrap.get_viewport()
		if vpt and not vpt.size_changed.is_connected(refit): vpt.size_changed.connect(refit))
	wrap.tree_exiting.connect(func():
		_live[key] = int(_live.get(key, 1)) - 1
		# closed for good (not just rebuilt this frame): forget its size and page
		var ml := Engine.get_main_loop() as SceneTree
		if ml: ml.process_frame.connect(func():
			if int(_live.get(key, 0)) <= 0:
				_tall.erase(key); _page_of.erase(key), CONNECT_ONE_SHOT)
		var vpt := wrap.get_viewport()
		if vpt and vpt.size_changed.is_connected(refit): vpt.size_changed.disconnect(refit))
	return wrap

## Splits a VBox's children (and the rows of any grid among them) into pages that fit maxh.
static func _paginate(content: VBoxContainer, maxh: float, key: String, pager: Control, lbl: Label, prev: Button, next: Button, w := 600.0) -> void:
	var units: Array = []          # each: {nodes: [...], h}
	for c in content.get_children():
		if not (c is Control):
			continue
		if c.has_meta("pg_off"):
			c.visible = true; c.remove_meta("pg_off")
		if c is GridContainer:
			var g := c as GridContainer
			var cols := maxi(1, g.columns)
			var items: Array = []
			for gc in g.get_children():
				if gc is Control:
					if gc.has_meta("pg_off"): gc.visible = true; gc.remove_meta("pg_off")
					if gc.visible: items.append(gc)
			var vs := float(g.get_theme_constant("v_separation"))
			for i in range(0, items.size(), cols):
				var row: Array = items.slice(i, i + cols)
				var rh := 0.0
				for it in row: rh = maxf(rh, est_h(it as Control, (w - (cols - 1) * float(g.get_theme_constant("h_separation"))) / cols))
				units.append({"nodes": row, "h": rh + (vs if i > 0 else 0.0), "grid": g})
			continue
		if not c.visible:
			continue
		if c.has_meta("pg_keep"):
			# headers and tab rows stay on every page
			maxh -= est_h(c as Control, w) + float(content.get_theme_constant("separation"))
			continue
		units.append({"nodes": [c], "h": est_h(c as Control, w)})
	var sep := float(content.get_theme_constant("separation"))
	var total := 0.0
	for u in units: total += float(u["h"]) + sep
	if total - sep <= maxh or units.size() <= 1:
		pager.visible = false
		return
	# fill pages greedily
	var pages: Array = [[]]
	var used := 0.0
	for u in units:
		var h := float(u["h"]) + sep
		if used + h > maxh and not (pages[-1] as Array).is_empty():
			pages.append([])
			used = 0.0
		pages[-1].append(u)
		used += h
	var pg := clampi(int(_page_of.get(key, 0)), 0, pages.size() - 1)
	_page_of[key] = pg
	for i in pages.size():
		if i == pg:
			continue
		for u in pages[i]:
			for n in u["nodes"]:
				(n as Control).visible = false
				(n as Control).set_meta("pg_off", true)
	pager.visible = true
	lbl.text = "Page %d of %d" % [pg + 1, pages.size()]
	prev.disabled = pg == 0
	next.disabled = pg >= pages.size() - 1

## How tall a control will be at a given width, worked out from the text itself so wrapped labels
## measure right before the layout has run (they report huge heights until then).
static func est_h(c: Control, w: float) -> float:
	if c == null or (not c.visible and not c.has_meta("pg_off")):
		return 0.0
	var own := c.custom_minimum_size.y
	if c is Label:
		var l := c as Label
		if l.autowrap_mode == TextServer.AUTOWRAP_OFF:
			return l.get_combined_minimum_size().y
		var f := l.get_theme_font("font")
		var fs := l.get_theme_font_size("font_size")
		var ls := float(l.get_theme_constant("line_spacing"))
		var lines := 0
		for para in l.text.split("\n"):
			var tw := f.get_string_size(para, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			lines += maxi(1, int(ceil(tw / maxf(20.0, w - 4.0) + 0.0001)))
		return maxf(own, lines * (f.get_height(fs) + ls))
	if c is GridContainer:
		var g := c as GridContainer
		var cols := maxi(1, g.columns)
		var cw := (w - (cols - 1) * float(g.get_theme_constant("h_separation"))) / cols
		var items: Array = g.get_children().filter(func(x): return x is Control and (x.visible or x.has_meta("pg_off")))
		var total := 0.0
		for i in range(0, items.size(), cols):
			var rh := 0.0
			for it in items.slice(i, i + cols): rh = maxf(rh, est_h(it, cw))
			total += rh + (float(g.get_theme_constant("v_separation")) if i > 0 else 0.0)
		return maxf(own, total)
	if c is VBoxContainer:
		var sep := float(c.get_theme_constant("separation"))
		var total := 0.0; var n := 0
		for ch in c.get_children():
			if ch is Control and ch.visible:
				total += est_h(ch, w); n += 1
		return maxf(own, total + sep * maxi(0, n - 1))
	if c is HBoxContainer:
		var sep := float(c.get_theme_constant("separation"))
		var kids: Array = c.get_children().filter(func(x): return x is Control and x.visible)
		var fixed := 0.0; var expanders := 0
		for ch in kids:
			if (ch as Control).size_flags_horizontal & Control.SIZE_EXPAND: expanders += 1
			else: fixed += (ch as Control).get_combined_minimum_size().x
		var free := maxf(40.0, w - fixed - sep * maxi(0, kids.size() - 1))
		var hmax := 0.0
		for ch in kids:
			var cw: float = free / maxi(1, expanders) if (ch as Control).size_flags_horizontal & Control.SIZE_EXPAND else (ch as Control).get_combined_minimum_size().x
			hmax = maxf(hmax, est_h(ch, cw))
		return maxf(own, hmax)
	if c is PanelContainer or c is MarginContainer:
		var pad := Vector2.ZERO
		if c is PanelContainer:
			var sb := c.get_theme_stylebox("panel")
			if sb: pad = sb.get_minimum_size()
		var hmax := 0.0
		for ch in c.get_children():
			if ch is Control and ch.visible: hmax = maxf(hmax, est_h(ch, w - pad.x))
		return maxf(own, hmax + pad.y)
	if c is HFlowContainer:
		var hs := float(c.get_theme_constant("h_separation")); var vs := float(c.get_theme_constant("v_separation"))
		var x := 0.0; var rows := 1; var rh := 0.0; var total := 0.0
		for ch in c.get_children():
			if not (ch is Control and ch.visible): continue
			var ms := (ch as Control).get_combined_minimum_size()
			if x > 0.0 and x + ms.x > w:
				total += rh + vs; rows += 1; x = 0.0; rh = 0.0
			x += ms.x + hs
			rh = maxf(rh, ms.y)
		return maxf(own, total + rh)
	return c.get_combined_minimum_size().y

## Old name, kept for the results screen: the content, paged rather than scrolled.
static func scroll_box(content: Control, margin := 120.0) -> Control:
	if content is VBoxContainer:
		return paged(content as VBoxContainer, margin, "box")
	return content

## A menu panel: a title row with a Close button, and a body that pages whenever it's taller than
## the window, so nothing ends up off screen and nothing scrolls. Returns [panel, body].
static func scroll_panel(title_txt: String, width: float, on_close: Callable, close_txt := "Close") -> Array:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var outer := vbox(12)
	p.add_child(outer)
	var head := hbox(8)
	var t := title(title_txt, 30)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.clip_text = true
	head.add_child(t)
	if on_close.is_valid():
		head.add_child(button(close_txt, on_close))
	outer.add_child(head)
	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 2)
	rule.color = Color(ACCENT, 0.35)
	outer.add_child(rule)
	var body := vbox(12)
	outer.add_child(paged(body, 170.0, title_txt, head, width - 56.0))
	var fitw := func():
		if is_instance_valid(p) and p.is_inside_tree():
			p.custom_minimum_size.x = minf(width, p.get_viewport_rect().size.x - 32.0)
	p.tree_entered.connect(func(): fitw.call_deferred())
	p.custom_minimum_size.x = width
	return [p, body]
