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
	c.draw.connect(func():
		c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0, 0, 0, 0.4))
		c.draw_rect(Rect2(Vector2.ZERO, Vector2(c.size.x * clampf(frac, 0.0, 1.0), c.size.y)), col))
	return c

static func spacer(h := 8.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	return c

## Wraps content in a scroll box that grows with it up to the window height minus `margin`.
static func scroll_box(content: Control, margin := 120.0) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(content)
	var fit := func():
		if is_instance_valid(sc) and sc.is_inside_tree():
			sc.custom_minimum_size.y = minf(content.get_combined_minimum_size().y, maxf(140.0, sc.get_viewport_rect().size.y - margin))
	content.minimum_size_changed.connect(fit)
	sc.tree_entered.connect(func():
		fit.call_deferred()
		var vpt := sc.get_viewport()
		if vpt and not vpt.size_changed.is_connected(fit): vpt.size_changed.connect(fit))
	sc.tree_exiting.connect(func():
		var vpt := sc.get_viewport()
		if vpt and vpt.size_changed.is_connected(fit): vpt.size_changed.disconnect(fit))
	return sc

## A menu panel: a title row with a Close button, and a body that scrolls whenever it's taller than
## the window, so nothing can end up off screen. Returns [panel, body]; add content to body.
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
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.name = "Scroll"
	var body := vbox(12)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(body)
	outer.add_child(sc)
	var fit := func():
		if not is_instance_valid(sc) or not sc.is_inside_tree():
			return
		var vp := sc.get_viewport_rect().size
		var w := minf(width, vp.x - 32.0)
		p.custom_minimum_size.x = w
		t.custom_minimum_size.x = 0
		var maxh := maxf(140.0, vp.y - 150.0 - head.get_combined_minimum_size().y)
		sc.custom_minimum_size.y = minf(body.get_combined_minimum_size().y, maxh)
	body.minimum_size_changed.connect(fit)
	p.tree_entered.connect(func():
		fit.call_deferred()
		var vpt := p.get_viewport()
		if vpt and not vpt.size_changed.is_connected(fit):
			vpt.size_changed.connect(fit))
	p.tree_exiting.connect(func():
		var vpt := p.get_viewport()
		if vpt and vpt.size_changed.is_connected(fit):
			vpt.size_changed.disconnect(fit))
	p.custom_minimum_size.x = width
	return [p, body]
