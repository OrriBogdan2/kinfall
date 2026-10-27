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

static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = body
	t.default_font_size = 16
	var b := StyleBoxFlat.new(); b.bg_color = Color(0.18, 0.2, 0.28); b.set_corner_radius_all(10)
	b.content_margin_left = 16; b.content_margin_right = 16; b.content_margin_top = 9; b.content_margin_bottom = 9
	var bh := b.duplicate(); bh.bg_color = Color(0.24, 0.26, 0.36)
	var bp := b.duplicate(); bp.bg_color = Color(0.3, 0.32, 0.44)
	var bd := b.duplicate(); bd.bg_color = Color(0.13, 0.14, 0.19)
	var bf := b.duplicate(); bf.bg_color = Color(0, 0, 0, 0); bf.border_color = ACCENT; bf.set_border_width_all(2)
	for kind in ["Button"]:
		t.set_stylebox("normal", kind, b)
		t.set_stylebox("hover", kind, bh)
		t.set_stylebox("pressed", kind, bp)
		t.set_stylebox("disabled", kind, bd)
		t.set_stylebox("focus", kind, bf)
		t.set_color("font_color", kind, INK)
		t.set_color("font_hover_color", kind, Color.WHITE)
		t.set_color("font_disabled_color", kind, Color(0.55, 0.57, 0.63))
	var le := StyleBoxFlat.new(); le.bg_color = Color(0.1, 0.11, 0.16); le.set_corner_radius_all(8); le.border_color = Color(1, 1, 1, 0.12); le.set_border_width_all(1)
	le.content_margin_left = 12; le.content_margin_right = 12; le.content_margin_top = 8; le.content_margin_bottom = 8
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", le)
	t.set_color("font_color", "Label", INK)
	var pc := StyleBoxFlat.new(); pc.bg_color = PANEL; pc.set_corner_radius_all(16)
	pc.content_margin_left = 24; pc.content_margin_right = 24; pc.content_margin_top = 20; pc.content_margin_bottom = 20
	t.set_stylebox("panel", "PanelContainer", pc)
	var sv := StyleBoxFlat.new(); sv.bg_color = Color(1, 1, 1, 0.15); sv.set_corner_radius_all(4)
	t.set_stylebox("grabber", "VScrollBar", sv)
	_theme = t
	return t

static func label(text: String, size := 16, col := INK, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if font:
		l.add_theme_font_override("font", font)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	return b

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
