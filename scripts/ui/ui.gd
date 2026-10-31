class_name UI
## The menu kit. Every screen builds its menus in code from these helpers, so they share one look:
## colour roles, a three-size type scale, three button tiers, soft cards, segmented tabs, chips,
## keycaps, the panel shell (title, close X, tabs, body, footer) and a blurred backdrop for modals.
## docs/UI_DESIGN.md has the rules and the full API.

# ---------------------------------------------------------------- colour roles
const INK := Color("f3eee2")                        # text
const MUTED := Color("a9b0bf")                      # secondary text
const FAINT := Color(0.66, 0.69, 0.78, 0.55)        # hints, disabled
const BG := Color("0e111a")                         # full-screen menu background
const SURFACE := Color(0.078, 0.088, 0.135, 0.975)  # panels
const PANEL := SURFACE
const CARD := Color(0.135, 0.15, 0.21, 1.0)         # a card raised off a panel
const WELL := Color(0, 0, 0, 0.22)                  # a recess: tab tracks, bars, inputs
const LINE := Color(1, 1, 1, 0.08)                  # hairlines
const ACCENT := Color("f2a24a")                     # the one action colour: primary buttons, focus, picked tabs
const ACCENT_HI := Color("ffd79a")                  # accent text on dark
const GOOD := Color("8fe0a0")                       # success, owned, ready
const BAD := Color("ff6a5a")                        # danger, loss, locked
const GOLD := Color("f2c84a")                       # currency (gems) and rewards
const TEAL := Color("8fe3c8")                       # info, extraction, the portal
const INFO := Color("7cc4ff")
const DARK_INK := Color(0.13, 0.08, 0.05)           # text on accent fills

# ---------------------------------------------------------------- type scale (three sizes, plus caps)
const T_TITLE := 30      # one per panel (Lilita One)
const T_HEAD := 19       # card titles, item names (Lilita One)
const T_BODY := 15       # everything you read (Rubik)
const T_SMALL := 13      # secondary lines (Rubik)
const T_CAPS := 12       # section eyebrows (Rubik bold, spaced)
# ---------------------------------------------------------------- spacing
const GAP := 12          # between things in a group
const GAP_BIG := 20      # between groups
const PAD := 26          # inside a panel

static var big: Font = preload("res://fonts/LilitaOne-Regular.ttf")
static var body: Font = preload("res://fonts/Rubik.ttf")
static var _theme: Theme
static var semi: FontVariation       # Rubik at a heavier weight, for buttons and small headers
static var caps: FontVariation       # spaced-out bold, for section headers

static func rarity_col(r: int) -> Color:
	return Data.RARITY[clampi(r, 0, Data.RARITY.size() - 1)]["color"]

static func _box(bg: Color, rad := 10, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.set_corner_radius_all(rad)
	if bw > 0:
		b.border_color = border
		b.set_border_width_all(bw)
	b.anti_aliasing = true
	return b

static func _pad(b: StyleBox, h: float, v: float) -> StyleBox:
	b.content_margin_left = h; b.content_margin_right = h
	b.content_margin_top = v; b.content_margin_bottom = v
	return b

## A button face. hi: a 1px lit top edge; glow: a soft coloured shadow.
static func _face(bg: Color, rad := 10, line := Color(0, 0, 0, 0), lw := 0, hi := Color(0, 0, 0, 0), glow := Color(0, 0, 0, 0), glow_size := 0) -> StyleBoxFlat:
	var b := _box(bg, rad)
	if lw > 0:
		b.border_color = line
		b.set_border_width_all(lw)
	elif hi.a > 0.0:
		b.border_color = hi
		b.border_width_top = 1
	b.border_blend = false
	if glow_size > 0:
		b.shadow_color = glow; b.shadow_size = glow_size; b.shadow_offset = Vector2(0, 2)
	_pad(b, 18, 8)
	return b

static func _ring(rad := 13) -> StyleBoxFlat:
	var f := _box(Color(0, 0, 0, 0), rad, Color(ACCENT_HI, 0.95), 2)
	f.expand_margin_left = 3; f.expand_margin_right = 3; f.expand_margin_top = 3; f.expand_margin_bottom = 3
	return f

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
	var w := 44; var h := 24
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var track := ACCENT if on else Color(0.26, 0.28, 0.36)
	var knob := Color("fff7e8") if on else Color("c9ccd6")
	var kr := 8.5
	var kx := (w - 12.0) if on else 12.0
	for y in h:
		for x in w:
			var cx := clampf(float(x), h * 0.5, w - h * 0.5)
			var dt := Vector2(x - cx, y - (h - 1) * 0.5).length()
			var a := clampf(h * 0.5 - dt, 0.0, 1.0)
			var px := track
			var dk := Vector2(x - kx, y - (h - 1) * 0.5).length()
			if dk < kr + 0.5:
				px = px.lerp(knob, clampf(kr + 0.5 - dk, 0.0, 1.0))
			img.set_pixel(x, y, Color(px, a))
	return ImageTexture.create_from_image(img)

static func _blank(w: int, h: int) -> ImageTexture:
	var img := Image.create(maxi(1, w), maxi(1, h), false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)

static func _btn_type(t: Theme, type: String, n: StyleBox, h: StyleBox, p: StyleBox, d: StyleBox, col: Color, hcol: Color, dcol: Color, ring := 13) -> void:
	t.add_type(type); t.set_type_variation(type, "Button")
	t.set_stylebox("normal", type, n)
	t.set_stylebox("hover", type, h)
	t.set_stylebox("pressed", type, p)
	t.set_stylebox("hover_pressed", type, p)
	t.set_stylebox("disabled", type, d)
	t.set_stylebox("focus", type, _ring(ring))
	for c in ["font_color", "font_focus_color"]: t.set_color(c, type, col)
	for c in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color"]: t.set_color(c, type, hcol)
	t.set_color("font_disabled_color", type, dcol)

static func theme() -> Theme:
	if _theme:
		return _theme
	semi = FontVariation.new(); semi.base_font = body; semi.variation_opentype = {"wght": 560}
	caps = FontVariation.new(); caps.base_font = body; caps.variation_opentype = {"wght": 700}; caps.spacing_glyph = 1
	var t := Theme.new()
	t.default_font = body
	t.default_font_size = 16
	# ---- buttons, three tiers. The plain Button is the secondary tier: a quiet outline, so the one
	# filled (primary) button on a screen is obviously the thing to press.
	var sec_n := _face(Color(1, 1, 1, 0.045), 10, Color(1, 1, 1, 0.15), 1)
	var sec_h := _face(Color(1, 1, 1, 0.1), 10, Color(1, 1, 1, 0.32), 1)
	var sec_p := _face(Color(0, 0, 0, 0.18), 10, Color(ACCENT, 0.7), 1)
	var sec_d := _face(Color(1, 1, 1, 0.02), 10, Color(1, 1, 1, 0.06), 1)
	t.set_stylebox("normal", "Button", sec_n)
	t.set_stylebox("hover", "Button", sec_h)
	t.set_stylebox("pressed", "Button", sec_p)
	t.set_stylebox("hover_pressed", "Button", sec_p)
	t.set_stylebox("disabled", "Button", sec_d)
	t.set_stylebox("focus", "Button", _ring())
	t.set_font("font", "Button", semi)
	t.set_font_size("font_size", "Button", T_BODY)
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", ACCENT_HI)
	t.set_color("font_hover_pressed_color", "Button", ACCENT_HI)
	t.set_color("font_focus_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.52, 0.6))
	t.set_constant("h_separation", "Button", 8)
	# primary: the one filled accent button on a screen
	_btn_type(t, "Primary",
		_face(ACCENT, 10, Color(), 0, ACCENT.lightened(0.45), Color(ACCENT, 0.22), 8),
		_face(ACCENT.lightened(0.1), 10, Color(), 0, ACCENT.lightened(0.6), Color(ACCENT, 0.42), 14),
		_face(ACCENT.darkened(0.12), 10),
		_face(Color(ACCENT.darkened(0.55), 0.55), 10),
		DARK_INK, DARK_INK, Color(1, 1, 1, 0.35))
	# tertiary: text only, for small or rarely used actions
	var gh_n := _face(Color(0, 0, 0, 0), 10); _pad(gh_n, 12, 8)
	var gh_h := _face(Color(1, 1, 1, 0.07), 10); _pad(gh_h, 12, 8)
	var gh_p := _face(Color(0, 0, 0, 0.15), 10); _pad(gh_p, 12, 8)
	_btn_type(t, "Ghost", gh_n, gh_h, gh_p, gh_n, MUTED, Color.WHITE, FAINT)
	# danger: an outline in red that fills on hover (delete, sell, leave)
	_btn_type(t, "Danger",
		_face(Color(BAD, 0.06), 10, Color(BAD, 0.55), 1),
		_face(Color(BAD, 0.2), 10, Color(BAD, 0.9), 1),
		_face(Color(BAD, 0.3), 10, BAD, 1),
		sec_d, Color("ffb3a8"), Color.WHITE, FAINT)
	# a round icon button (the close X)
	var ib_n := _box(Color(1, 1, 1, 0.0), 999); _pad(ib_n, 8, 8)
	var ib_h := _box(Color(1, 1, 1, 0.1), 999); _pad(ib_h, 8, 8)
	var ib_p := _box(Color(0, 0, 0, 0.2), 999); _pad(ib_p, 8, 8)
	_btn_type(t, "IconBtn", ib_n, ib_h, ib_p, ib_n, MUTED, Color.WHITE, FAINT, 999)
	# the picked option in a row of choices: a soft accent fill with an accent edge
	_btn_type(t, "Chosen",
		_face(Color(ACCENT, 0.17), 10, Color(ACCENT, 0.85), 1),
		_face(Color(ACCENT, 0.24), 10, ACCENT, 1),
		_face(Color(ACCENT, 0.3), 10, ACCENT, 1),
		_face(Color(ACCENT, 0.08), 10, Color(ACCENT, 0.3), 1),
		ACCENT_HI, Color("ffe6c2"), Color(ACCENT_HI, 0.5))
	# segmented tabs: segments sit in a dark track; the picked one lifts out of it
	var sg_n := _box(Color(0, 0, 0, 0), 8); _pad(sg_n, 14, 7)
	var sg_h := _box(Color(1, 1, 1, 0.06), 8); _pad(sg_h, 14, 7)
	_btn_type(t, "Seg", sg_n, sg_h, sg_h, sg_n, MUTED, Color.WHITE, FAINT, 10)
	var so_n := _box(Color(0.24, 0.255, 0.33), 8); _pad(so_n, 14, 7)
	so_n.border_width_top = 1; so_n.border_color = Color(1, 1, 1, 0.12); so_n.border_blend = false
	so_n.shadow_color = Color(0, 0, 0, 0.3); so_n.shadow_size = 4; so_n.shadow_offset = Vector2(0, 1)
	_btn_type(t, "SegOn", so_n, so_n, so_n, so_n, Color.WHITE, Color.WHITE, FAINT, 10)
	# a selectable tile (inventory slot, glider, armory piece): a card that lights up
	var tl_n := _box(Color(1, 1, 1, 0.04), 12); _pad(tl_n, 10, 10)
	var tl_h := _box(Color(1, 1, 1, 0.08), 12, Color(1, 1, 1, 0.22), 1); _pad(tl_h, 10, 10)
	var tl_on := _box(Color(ACCENT, 0.14), 12, Color(ACCENT, 0.9), 2); _pad(tl_on, 10, 10)
	_btn_type(t, "Tile", tl_n, tl_h, tl_h, tl_n, INK, Color.WHITE, FAINT, 15)
	_btn_type(t, "TileOn", tl_on, tl_on, tl_on, tl_on, ACCENT_HI, Color.WHITE, FAINT, 15)
	# big front-menu entries (title screen): just words until you point at one, then a soft lit
	# pill with an amber edge slides under it
	t.add_type("MenuItem"); t.set_type_variation("MenuItem", "Button")
	var mi_n := StyleBoxFlat.new(); mi_n.bg_color = Color(0, 0, 0, 0)
	mi_n.content_margin_left = 20; mi_n.content_margin_right = 20; mi_n.content_margin_top = 6; mi_n.content_margin_bottom = 6
	var mi_h := _box(Color(1, 1, 1, 0.08), 10)
	mi_h.border_width_left = 3; mi_h.border_color = ACCENT; mi_h.border_blend = false
	mi_h.content_margin_left = 28; mi_h.content_margin_right = 20; mi_h.content_margin_top = 6; mi_h.content_margin_bottom = 6
	var mi_p := mi_h.duplicate(); mi_p.bg_color = Color(ACCENT, 0.18)
	t.set_stylebox("normal", "MenuItem", mi_n)
	t.set_stylebox("hover", "MenuItem", mi_h)
	t.set_stylebox("pressed", "MenuItem", mi_p)
	t.set_stylebox("hover_pressed", "MenuItem", mi_p)
	t.set_stylebox("focus", "MenuItem", StyleBoxEmpty.new())
	t.set_stylebox("disabled", "MenuItem", mi_n)
	t.set_font("font", "MenuItem", big)
	t.set_font_size("font_size", "MenuItem", 25)
	t.set_color("font_color", "MenuItem", Color(INK, 0.8))
	t.set_color("font_hover_color", "MenuItem", Color.WHITE)
	t.set_color("font_focus_color", "MenuItem", Color.WHITE)
	t.set_color("font_pressed_color", "MenuItem", ACCENT_HI)
	t.set_color("font_hover_pressed_color", "MenuItem", ACCENT_HI)
	t.set_color("font_disabled_color", "MenuItem", Color(INK, 0.3))
	t.set_constant("outline_size", "MenuItem", 6)
	t.set_color("font_outline_color", "MenuItem", Color(0.05, 0.03, 0.1, 0.55))
	t.set_constant("h_separation", "MenuItem", 12)
	# the one big call to action on the front menu
	t.add_type("MenuMain"); t.set_type_variation("MenuMain", "Button")
	var mm_n := _box(ACCENT, 14)
	mm_n.border_width_top = 1; mm_n.border_color = ACCENT.lightened(0.5); mm_n.border_blend = false
	mm_n.content_margin_left = 30; mm_n.content_margin_right = 34; mm_n.content_margin_top = 11; mm_n.content_margin_bottom = 11
	mm_n.shadow_color = Color(1.0, 0.55, 0.2, 0.3); mm_n.shadow_size = 18; mm_n.shadow_offset = Vector2(0, 4)
	var mm_h := mm_n.duplicate(); mm_h.bg_color = ACCENT.lightened(0.1); mm_h.shadow_color = Color(1.0, 0.6, 0.25, 0.5); mm_h.shadow_size = 28
	var mm_p := mm_n.duplicate(); mm_p.bg_color = ACCENT.darkened(0.1); mm_p.shadow_size = 6
	t.set_stylebox("normal", "MenuMain", mm_n)
	t.set_stylebox("hover", "MenuMain", mm_h)
	t.set_stylebox("pressed", "MenuMain", mm_p)
	t.set_stylebox("hover_pressed", "MenuMain", mm_p)
	var mm_f := _box(Color(0, 0, 0, 0), 17, Color(1, 0.95, 0.85, 0.9), 2)
	mm_f.expand_margin_left = 4; mm_f.expand_margin_right = 4; mm_f.expand_margin_top = 4; mm_f.expand_margin_bottom = 4
	t.set_stylebox("focus", "MenuMain", mm_f)
	t.set_font("font", "MenuMain", big)
	t.set_font_size("font_size", "MenuMain", 28)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, "MenuMain", Color(0.16, 0.08, 0.06))
	t.set_constant("h_separation", "MenuMain", 12)
	# text boxes
	var le := _box(WELL, 10, Color(1, 1, 1, 0.1), 1)
	_pad(le, 12, 9)
	var lf := le.duplicate(); lf.border_color = Color(ACCENT, 0.9); lf.set_border_width_all(2)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", lf)
	t.set_color("font_placeholder_color", "LineEdit", FAINT)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", Color(ACCENT, 0.35))
	t.set_color("font_color", "Label", INK)
	# panels: a deep night-blue sheet, soft corners, a hairline edge and a long soft shadow. No gilding:
	# hierarchy comes from the title, spacing and the cards on it, not from frames.
	var pc := _box(SURFACE, 20, LINE, 1)
	pc.shadow_color = Color(0.0, 0.0, 0.03, 0.55); pc.shadow_size = 40; pc.shadow_offset = Vector2(0, 16)
	pc.content_margin_left = PAD; pc.content_margin_right = PAD; pc.content_margin_top = 22; pc.content_margin_bottom = 22
	t.set_stylebox("panel", "PanelContainer", pc)
	# scroll bars: thin and quiet
	for sb_t in ["VScrollBar", "HScrollBar"]:
		var gr := _box(Color(1, 1, 1, 0.16), 4); gr.content_margin_left = 3; gr.content_margin_right = 3
		t.set_stylebox("grabber", sb_t, gr)
		t.set_stylebox("grabber_highlight", sb_t, _box(Color(1, 1, 1, 0.3), 4))
		t.set_stylebox("grabber_pressed", sb_t, _box(Color(ACCENT, 0.6), 4))
		var tr := _box(Color(0, 0, 0, 0.14), 4); tr.content_margin_left = 3; tr.content_margin_right = 3
		t.set_stylebox("scroll", sb_t, tr)
	# progress bars (challenge cards)
	var pbg := _box(WELL, 5); pbg.content_margin_top = 4; pbg.content_margin_bottom = 4
	t.set_stylebox("background", "ProgressBar", pbg)
	t.set_stylebox("fill", "ProgressBar", _box(ACCENT, 5))
	# sliders
	var sl := _box(Color(0, 0, 0, 0.35), 4); sl.content_margin_top = 3; sl.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", sl)
	var ga := _box(ACCENT.darkened(0.05), 4); ga.content_margin_top = 3; ga.content_margin_bottom = 3
	t.set_stylebox("grabber_area", "HSlider", ga)
	t.set_stylebox("grabber_area_highlight", "HSlider", ga)
	t.set_stylebox("focus", "HSlider", _ring(8))
	t.set_icon("grabber", "HSlider", _circle_tex(18, Color("fff7e8"), ACCENT))
	t.set_icon("grabber_highlight", "HSlider", _circle_tex(20, Color.WHITE, ACCENT.lightened(0.2)))
	# toggles
	t.set_icon("checked", "CheckButton", _toggle_tex(true))
	t.set_icon("unchecked", "CheckButton", _toggle_tex(false))
	t.set_icon("checked_disabled", "CheckButton", _toggle_tex(true))
	t.set_icon("unchecked_disabled", "CheckButton", _toggle_tex(false))
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		t.set_stylebox(st, "CheckButton", empty)
	t.set_stylebox("focus", "CheckButton", _ring(14))
	t.set_font("font", "CheckButton", body)
	t.set_font_size("font_size", "CheckButton", T_BODY)
	t.set_color("font_color", "CheckButton", INK)
	t.set_color("font_hover_color", "CheckButton", Color.WHITE)
	t.set_color("font_pressed_color", "CheckButton", INK)
	t.set_color("font_hover_pressed_color", "CheckButton", Color.WHITE)
	t.set_color("font_focus_color", "CheckButton", INK)
	# drop-downs and their lists
	t.set_stylebox("normal", "OptionButton", sec_n)
	t.set_stylebox("hover", "OptionButton", sec_h)
	t.set_stylebox("pressed", "OptionButton", sec_p)
	t.set_stylebox("focus", "OptionButton", _ring())
	t.set_font("font", "OptionButton", semi)
	t.set_font_size("font_size", "OptionButton", T_BODY)
	var pm := _box(Color(0.1, 0.11, 0.16, 0.99), 12, Color(1, 1, 1, 0.1), 1)
	pm.shadow_color = Color(0, 0, 0, 0.45); pm.shadow_size = 14; pm.shadow_offset = Vector2(0, 6)
	_pad(pm, 6, 6)
	t.set_stylebox("panel", "PopupMenu", pm)
	t.set_stylebox("hover", "PopupMenu", _box(Color(ACCENT, 0.22), 7))
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_font_size("font_size", "PopupMenu", T_BODY)
	t.set_constant("v_separation", "PopupMenu", 8)
	# tooltips: small dark cards with a soft shadow
	var tp := _box(Color(0.06, 0.068, 0.1, 0.98), 9, Color(1, 1, 1, 0.12), 1)
	tp.shadow_color = Color(0, 0, 0, 0.4); tp.shadow_size = 10; tp.shadow_offset = Vector2(0, 4)
	_pad(tp, 11, 7)
	t.set_stylebox("panel", "TooltipPanel", tp)
	t.set_color("font_color", "TooltipLabel", INK)
	t.set_font_size("font_size", "TooltipLabel", T_SMALL)
	t.set_stylebox("separator", "HSeparator", _box(LINE, 1))
	t.set_constant("separation", "HSeparator", 6)
	_theme = t
	return t

# ---------------------------------------------------------------- small pieces

## A key drawn as a little keycap ("F", "Space", "Esc"), so prompts read at a glance instead of as
## letters in brackets.
static func keycap(key: String, size := 13) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.93, 0.9, 0.84, 0.95)
	sb.set_corner_radius_all(5)
	sb.border_width_bottom = 2; sb.border_color = Color(0.55, 0.5, 0.45, 0.95)
	sb.content_margin_left = 6 if key.length() <= 1 else 7
	sb.content_margin_right = sb.content_margin_left
	sb.content_margin_top = 1; sb.content_margin_bottom = 0
	sb.anti_aliasing = true
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(size + 10, size + 7)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = key
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", caps if caps else body)
	l.add_theme_font_size_override("font_size", size - 1 if key.length() > 1 else size)
	l.add_theme_color_override("font_color", Color(0.16, 0.12, 0.14))
	p.add_child(l)
	return p

## A row of "[key] what it does" hints. pairs: [["F", "use"], ["Space", "jump"], ...]; a key string
## with spaces in it ("W S") draws one cap per key.
static func key_hints(pairs: Array, size := 13, col := Color(1, 1, 1, 0.75)) -> HBoxContainer:
	var row := hbox(16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for pr in pairs:
		var one := hbox(5)
		one.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for k in String(pr[0]).split(" "):
			if k != "": one.add_child(keycap(k, size))
		var l := label(String(pr[1]), size + 1, col)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.add_theme_constant_override("outline_size", 4)
		l.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.08, 0.6))
		one.add_child(l)
		row.add_child(one)
	return row

## A small spaced-out heading for a group of things in a menu (the "eyebrow").
static func section(text: String, col := Color("c9a46a")) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_override("font", caps if caps else body)
	l.add_theme_font_size_override("font_size", T_CAPS)
	l.add_theme_color_override("font_color", col)
	l.set_meta("pg_head", true)
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

## Body text that wraps: the usual muted line under a heading.
static func para(text: String, size := T_SMALL, col := MUTED) -> Label:
	var l := label(text, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

static func title(text: String, size := 34, col := INK) -> Label:
	var l := label(text, size, col, big)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l

# ---------------------------------------------------------------- buttons
## The secondary button (an outline). icon: an Icons id drawn at its left. Hover lifts it a little,
## pressing sinks it, both in about 100 ms.
static func button(text: String, cb: Callable, minw := 0.0, icon := "") -> Button:
	var b := Button.new()
	b.text = text
	if cb.is_valid():
		b.pressed.connect(func(): Sfx.play("click"); cb.call())
	if minw > 0.0:
		b.custom_minimum_size.x = minw
	if icon != "":
		set_icon(b, icon)
	b.resized.connect(func(): b.pivot_offset = b.size * 0.5)
	var to := func(s: float, secs: float) -> void:
		if not is_instance_valid(b) or not b.is_inside_tree(): return
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2(s, s), secs).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	b.mouse_entered.connect(func():
		if b.disabled: return
		Sfx.play("hover", null, -12.0, 0.05)
		to.call(1.03, 0.09))
	b.mouse_exited.connect(func(): to.call(1.0, 0.11))
	b.button_down.connect(func(): if not b.disabled: to.call(0.97, 0.07))
	b.button_up.connect(func(): to.call(1.03 if b.is_hovered() else 1.0, 0.1))
	b.focus_entered.connect(func():
		# keyboard and pad focus tick and lift like the mouse does
		if not b.is_hovered() and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			Sfx.play("hover", null, -14.0, 0.05)
			to.call(1.03, 0.09))
	b.focus_exited.connect(func(): if not b.is_hovered(): to.call(1.0, 0.11))
	return b

## The main button of a screen: filled accent, dark text. One per screen.
static func primary(text: String, cb: Callable, minw := 0.0, icon := "") -> Button:
	var b := button(text, cb, minw, icon)
	b.theme_type_variation = "Primary"
	return b

## A text-only button for small or rare actions.
static func ghost(text: String, cb: Callable, minw := 0.0, icon := "") -> Button:
	var b := button(text, cb, minw, icon)
	b.theme_type_variation = "Ghost"
	return b

## A red-outlined button for things that can't be undone (pair it with confirm()).
static func danger(text: String, cb: Callable, minw := 0.0, icon := "") -> Button:
	var b := button(text, cb, minw, icon)
	b.theme_type_variation = "Danger"
	return b

## One option in a row of choices; the chosen one is lit instead of marked with a symbol.
static func choice(text: String, chosen: bool, cb: Callable, minw := 0.0, icon := "") -> Button:
	var b := button(text, cb, minw, icon)
	if chosen:
		b.theme_type_variation = "Chosen"
	return b

## A round icon-only button (close, back, arrows).
static func icon_button(icon: String, cb: Callable, tip := "", px := 16.0) -> Button:
	var b := button("", cb)
	b.theme_type_variation = "IconBtn"
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(px + 18, px + 18)
	b.draw.connect(func():
		var c := b.get_theme_color("font_hover_color" if b.is_hovered() else "font_color")
		draw_icon(b, icon, b.size * 0.5, px * 0.5, c))
	b.mouse_entered.connect(b.queue_redraw); b.mouse_exited.connect(b.queue_redraw)
	return b

## Draws an Icons glyph at the left of a button's text (keeps room for it with a blank icon).
static func set_icon(b: Button, icon: String, px := 16) -> void:
	b.icon = _blank(px, px)
	b.set_meta("glyph", icon)
	if b.has_meta("glyph_on"):
		b.queue_redraw()
		return
	b.set_meta("glyph_on", true)
	b.draw.connect(func():
		var id := String(b.get_meta("glyph", ""))
		if id == "": return
		var sb := b.get_theme_stylebox("normal")
		var ml := sb.content_margin_left if sb else 16.0
		var mr := sb.content_margin_right if sb else 16.0
		var x := ml
		if b.alignment == HORIZONTAL_ALIGNMENT_CENTER and b.text != "":
			# the icon sits just left of centred text
			var f := b.get_theme_font("font"); var fs := b.get_theme_font_size("font_size")
			var tw := f.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var gap := float(b.get_theme_constant("h_separation"))
			x = ml + maxf(0.0, (b.size.x - ml - mr - tw - px - gap) * 0.5)
		var col := b.get_theme_color("font_disabled_color" if b.disabled else ("font_hover_color" if b.is_hovered() else "font_color"))
		draw_icon(b, id, Vector2(x + px * 0.5, b.size.y * 0.5), px * 0.5, col))
	b.mouse_entered.connect(b.queue_redraw); b.mouse_exited.connect(b.queue_redraw)

## Draws an icon: one of the Icons ids, or one of the menu's own ("close", "back", "next", "check",
## "lock", "plus", "gear", "home", "bag", "shop", "portal", "hammer", "info").
static func draw_icon(c: CanvasItem, id: String, at: Vector2, s: float, col: Color) -> void:
	var w := maxf(1.8, s * 0.22)
	match id:
		"close":
			c.draw_line(at + Vector2(-s, -s) * 0.62, at + Vector2(s, s) * 0.62, col, w, true)
			c.draw_line(at + Vector2(s, -s) * 0.62, at + Vector2(-s, s) * 0.62, col, w, true)
		"back", "next":
			var d := -1.0 if id == "back" else 1.0
			c.draw_polyline(PackedVector2Array([at + Vector2(0.3 * d * -s, -0.7 * s), at + Vector2(-0.4 * d * -s, 0), at + Vector2(0.3 * d * -s, 0.7 * s)]), col, w, true)
		"check":
			c.draw_polyline(PackedVector2Array([at + Vector2(-0.7, 0.0) * s, at + Vector2(-0.2, 0.5) * s, at + Vector2(0.7, -0.55) * s]), col, w, true)
		"plus":
			c.draw_line(at + Vector2(-0.7, 0) * s, at + Vector2(0.7, 0) * s, col, w, true)
			c.draw_line(at + Vector2(0, -0.7) * s, at + Vector2(0, 0.7) * s, col, w, true)
		"lock":
			c.draw_rect(Rect2(at + Vector2(-0.62, -0.05) * s, Vector2(1.24, 0.9) * s), col)
			c.draw_arc(at + Vector2(0, -0.12) * s, 0.4 * s, PI, TAU, 12, col, w, true)
		"gear":
			c.draw_arc(at, 0.5 * s, 0, TAU, 20, col, w, true)
			for i in 8:
				var a := TAU * i / 8.0
				c.draw_line(at + Vector2(cos(a), sin(a)) * 0.6 * s, at + Vector2(cos(a), sin(a)) * 0.95 * s, col, w * 1.3, true)
			c.draw_circle(at, 0.18 * s, col)
		"home":
			c.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -0.85) * s, at + Vector2(0.85, -0.05) * s, at + Vector2(0.6, -0.05) * s, at + Vector2(0.6, 0.75) * s,
				at + Vector2(-0.6, 0.75) * s, at + Vector2(-0.6, -0.05) * s, at + Vector2(-0.85, -0.05) * s]), col)
		"bag":
			c.draw_rect(Rect2(at + Vector2(-0.7, -0.35) * s, Vector2(1.4, 1.1) * s), col)
			c.draw_arc(at + Vector2(0, -0.35) * s, 0.36 * s, PI, TAU, 12, col, w, true)
		"shop":
			c.draw_colored_polygon(PackedVector2Array([at + Vector2(-0.85, -0.2) * s, at + Vector2(-0.6, -0.75) * s, at + Vector2(0.6, -0.75) * s, at + Vector2(0.85, -0.2) * s]), col)
			c.draw_rect(Rect2(at + Vector2(-0.68, -0.1) * s, Vector2(1.36, 0.85) * s), Color(col, col.a * 0.75))
		"portal":
			c.draw_arc(at, 0.78 * s, 0, TAU, 24, col, w, true)
			c.draw_arc(at, 0.42 * s, 0, TAU, 18, Color(col, col.a * 0.7), w, true)
		"hammer":
			c.draw_line(at + Vector2(-0.6, 0.75) * s, at + Vector2(0.25, -0.15) * s, col, w * 1.4, true)
			c.draw_colored_polygon(PackedVector2Array([at + Vector2(-0.05, -0.75) * s, at + Vector2(0.75, 0.05) * s, at + Vector2(0.45, 0.35) * s, at + Vector2(-0.35, -0.45) * s]), col)
		"info":
			c.draw_arc(at, 0.85 * s, 0, TAU, 24, col, w, true)
			c.draw_circle(at + Vector2(0, -0.42) * s, 0.12 * s, col)
			c.draw_line(at + Vector2(0, -0.12) * s, at + Vector2(0, 0.5) * s, col, w, true)
		_:
			Icons.draw(c as Control, id, at, s, col)

## Shows a keycap at the right end of a button ("Enter", "Esc", "1"), so the key that does the same
## thing is right there on it.
static func with_key(b: Button, key: String) -> Button:
	var kc := keycap(key, 12)
	var w := kc.get_combined_minimum_size().x
	# make room on the right of every state's face, then park the cap there
	var room := func() -> void:
		for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var sb := b.get_theme_stylebox(st)
			if sb == null: continue
			var d := sb.duplicate()
			d.content_margin_right = maxf(sb.content_margin_right, 0.0) + w + 10.0
			b.add_theme_stylebox_override(st, d)
	if b.is_inside_tree(): room.call()
	else: b.tree_entered.connect(room, CONNECT_ONE_SHOT)
	b.add_child(kc)
	var place := func():
		var sb := b.get_theme_stylebox("normal")
		var r := (sb.content_margin_right - w - 10.0) if sb else 16.0
		kc.size = kc.get_combined_minimum_size()
		kc.position = Vector2(b.size.x - maxf(r, 10.0) - w, (b.size.y - kc.size.y) * 0.5)
	b.resized.connect(place)
	b.tree_entered.connect(func(): place.call_deferred())
	return b

# ---------------------------------------------------------------- tabs, chips, cards
## A segmented control: names in a dark track, the current one lifted. cb gets the picked name.
## counts (optional): name -> a small number shown after it. Arrow keys move along it.
static func tabs(names: Array, cur: String, cb: Callable, counts := {}, minw := 0.0) -> PanelContainer:
	var track := PanelContainer.new()
	var sb := _box(WELL, 11, Color(1, 1, 1, 0.05), 1)
	_pad(sb, 3, 3)
	track.add_theme_stylebox_override("panel", sb)
	track.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var row := hbox(2)
	track.add_child(row)
	for n in names:
		var nm := String(n)
		var txt := nm
		if counts.has(nm): txt = "%s  %s" % [nm, str(counts[nm])]
		var b := button(txt, func(): if nm != cur: cb.call(nm), minw)
		b.theme_type_variation = "SegOn" if nm == cur else "Seg"
		b.set_meta("tab", nm)
		row.add_child(b)
	track.set_meta("pg_keep", true)
	return track

## A selectable card (a tier, a skin, an item): lights up on hover and focus, the picked one wears
## an accent edge. Add your content to the returned container. Click, Enter or the pad's A pick it.
static func tile_card(on: bool, cb: Callable, pad := 12, col := ACCENT) -> PanelContainer:
	var p := PanelContainer.new()
	var n := _box(Color(col, 0.13) if on else Color(1, 1, 1, 0.04), 12, Color(col, 0.9) if on else Color(1, 1, 1, 0.06), 2 if on else 1)
	_pad(n, pad, pad)
	var h := n.duplicate() as StyleBoxFlat
	if not on:
		h.bg_color = Color(1, 1, 1, 0.08); h.border_color = Color(1, 1, 1, 0.24)
	else:
		h.bg_color = Color(col, 0.18)
	p.add_theme_stylebox_override("panel", n)
	p.focus_mode = Control.FOCUS_ALL
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	p.resized.connect(func(): p.pivot_offset = p.size * 0.5)
	var lit := func(yes: bool) -> void:
		p.add_theme_stylebox_override("panel", h if yes else n)
		var tw := p.create_tween()
		tw.tween_property(p, "scale", Vector2(1.015, 1.015) if yes else Vector2.ONE, 0.09).set_trans(Tween.TRANS_SINE)
	p.mouse_entered.connect(func(): Sfx.play("hover", null, -14.0, 0.05); lit.call(true))
	p.mouse_exited.connect(func(): if not p.has_focus(): lit.call(false))
	p.focus_entered.connect(func(): lit.call(true))
	p.focus_exited.connect(func(): if not p.get_global_rect().has_point(p.get_global_mouse_position()): lit.call(false))
	var ring := _ring(15)
	p.draw.connect(func():
		if p.has_focus() and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and p.get_viewport() and not p.get_global_rect().has_point(p.get_global_mouse_position()):
			p.draw_style_box(ring, Rect2(Vector2.ZERO, p.size)))
	p.focus_entered.connect(p.queue_redraw); p.focus_exited.connect(p.queue_redraw)
	p.gui_input.connect(func(ev):
		var go: bool = (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT) or ev.is_action_pressed("ui_accept")
		if go and cb.is_valid():
			p.accept_event()
			Sfx.play("click")
			cb.call())
	return p

## A pill: an icon and a value with a tooltip (gems, scrap, stored). col tints it.
static func chip(icon: String, txt: String, col := INK, tip := "", size := 14) -> PanelContainer:
	var c := PanelContainer.new()
	var sb := _box(Color(col, 0.11), 999)
	_pad(sb, 10, 4)
	c.add_theme_stylebox_override("panel", sb)
	c.tooltip_text = tip
	c.mouse_filter = Control.MOUSE_FILTER_PASS if tip != "" else Control.MOUSE_FILTER_IGNORE
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var h := hbox(6); c.add_child(h)
	if icon != "":
		var g := IconDot.new(icon, col, size + 2.0)
		h.add_child(g)
	var l := label(txt, size, INK, semi)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	h.add_child(l)
	return c

## A small coloured tag ("Rare", "Equipped", "Locked").
static func tag(txt: String, col: Color) -> PanelContainer:
	var c := PanelContainer.new()
	var sb := _box(Color(col, 0.16), 6)
	_pad(sb, 7, 2)
	c.add_theme_stylebox_override("panel", sb)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := label(txt.to_upper(), 11, col.lightened(0.15), caps)
	c.add_child(l)
	return c

## Fades and lifts a panel in, so menus open instead of just appearing (about 200 ms).
static func pop_in(c: Control, delay := 0.0) -> void:
	c.modulate.a = 0.0
	c.scale = Vector2(0.965, 0.965)
	var set_pivot := func(): c.pivot_offset = Vector2(c.size.x * 0.5, c.size.y * 0.6)
	c.resized.connect(set_pivot)
	set_pivot.call()
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "modulate:a", 1.0, 0.14).set_delay(delay)
	tw.tween_property(c, "scale", Vector2.ONE, 0.22).set_delay(delay).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)

## A card raised off a panel: soft corners, a faint lit top and a small shadow, no frame.
static func card(col := CARD, pad := 14, rad := 12) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(rad)
	sb.anti_aliasing = true
	sb.content_margin_left = pad; sb.content_margin_right = pad; sb.content_margin_top = pad; sb.content_margin_bottom = pad
	if col.a > 0.6 and rad < 100:
		sb.shadow_color = Color(0, 0, 0, 0.22); sb.shadow_size = 6; sb.shadow_offset = Vector2(0, 3)
		sheen(p, rad, 0.05)
	p.add_theme_stylebox_override("panel", sb)
	return p

static func set_card_border(p: PanelContainer, col: Color, w := 2) -> void:
	var sb: StyleBoxFlat = p.get_theme_stylebox("panel").duplicate()
	sb.border_color = col
	sb.set_border_width_all(w)
	p.add_theme_stylebox_override("panel", sb)

## Dark glass for things that float over the world (prompts, hint rows, the hub bar, hover cards).
static func glass(pad := 10, rad := 14) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := _box(Color(0.045, 0.052, 0.085, 0.8), rad, Color(1, 1, 1, 0.07), 1)
	sb.shadow_color = Color(0, 0, 0, 0.25); sb.shadow_size = 10; sb.shadow_offset = Vector2(0, 4)
	_pad(sb, pad + 2, pad)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

## A soft light across the top of a panel or card, fading out downward: the "subtle gradient".
static func sheen(c: Control, rad := 20, a0 := 0.06, band := 0.55) -> void:
	if c.has_meta("sheen"):
		return
	c.set_meta("sheen", true)
	c.draw.connect(func():
		var w := c.size.x; var h := c.size.y * band
		if w < 4.0 or h < 4.0: return
		var r := minf(float(rad), minf(w, c.size.y) * 0.5)
		var pts := PackedVector2Array(); var cols := PackedColorArray()
		var add := func(p: Vector2): pts.append(p); cols.append(Color(1, 1, 1, a0 * clampf(1.0 - p.y / h, 0.0, 1.0)))
		add.call(Vector2(0, h))
		for i in 7:
			var a := PI + (PI * 0.5) * i / 6.0
			add.call(Vector2(r, r) + Vector2(cos(a), sin(a)) * r)
		for i in 7:
			var a := PI * 1.5 + (PI * 0.5) * i / 6.0
			add.call(Vector2(w - r, r) + Vector2(cos(a), sin(a)) * r)
		add.call(Vector2(w, h))
		c.draw_polygon(pts, cols))

## An icon, a heading and a line: what an empty list shows instead of a bare sentence.
static func empty_state(icon: String, head: String, sub: String) -> Control:
	var v := vbox(6)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var g := IconDot.new(icon, Color(MUTED, 0.7), 34.0)
	g.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(spacer(10))
	v.add_child(g)
	var t := label(head, T_HEAD, INK, big); t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := para(sub, T_SMALL, MUTED); s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.custom_minimum_size.x = 380
	s.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(s)
	v.add_child(spacer(10))
	return v

## A label: value row (settings rows, item stats): the label muted on the left, the value right.
static func kv(k: String, val: String, col := INK) -> HBoxContainer:
	var r := hbox(8)
	var kl := label(k, T_SMALL, MUTED); kl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(kl)
	r.add_child(label(val, T_SMALL, col, semi))
	return r

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
		var bg := StyleBoxFlat.new(); bg.bg_color = Color(0, 0, 0, 0.35); bg.set_corner_radius_all(int(r))
		c.draw_style_box(bg, Rect2(Vector2.ZERO, c.size))
		var fw := c.size.x * clampf(frac, 0.0, 1.0)
		if fw > 1.0:
			var fg := StyleBoxFlat.new(); fg.bg_color = col; fg.set_corner_radius_all(int(r))
			c.draw_style_box(fg, Rect2(Vector2.ZERO, Vector2(maxf(fw, r * 2.0), c.size.y))))
	return c

static func spacer(h := 8.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

## Something that takes up the free width in a row (pushes what follows to the right).
static func fill() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

## Moves focus to the first button inside c (or c itself), so keyboard and pad users land somewhere.
static func focus_first(c: Control) -> void:
	var go := func():
		if not is_instance_valid(c) or not c.is_inside_tree(): return
		var vp := c.get_viewport()
		if vp and vp.gui_get_focus_owner() and c.is_ancestor_of(vp.gui_get_focus_owner()): return
		# the panel's primary first, then the first button that isn't a tab
		if c.has_meta("primary") and is_instance_valid(c.get_meta("primary")):
			var pb: Button = c.get_meta("primary")
			if not pb.disabled and pb.is_visible_in_tree():
				pb.grab_focus()
				return
		var f := _first_focusable(c)
		if f: f.grab_focus()
	go.call_deferred()

static func _first_focusable(n: Node) -> Control:
	if n is Control:
		var c := n as Control
		if not c.is_visible_in_tree(): return null
		if c.focus_mode != Control.FOCUS_NONE and (c is BaseButton) and not (c as BaseButton).disabled and not (c.theme_type_variation in ["IconBtn", "Seg", "SegOn"]):
			return c
	for ch in n.get_children():
		var f := _first_focusable(ch)
		if f: return f
	return null

# ---------------------------------------------------------------- the modal backdrop
static var _bd_shader: Shader = null

## A full-screen layer that blurs and darkens whatever is behind a modal menu. Starts hidden;
## show_backdrop() fades it in and out.
static func backdrop() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.03, 0.035, 0.06, 1.0)
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	if _bd_shader == null:
		_bd_shader = load("res://shaders/ui_backdrop.gdshader")
	var m := ShaderMaterial.new(); m.shader = _bd_shader
	r.material = m
	r.visible = false
	r.modulate.a = 0.0
	return r

static func show_backdrop(r: ColorRect, on: bool) -> void:
	if not is_instance_valid(r): return
	if r.has_meta("tw"):
		var old: Tween = r.get_meta("tw")
		if old and old.is_valid(): old.kill()
	if on:
		r.visible = true
		var tw := r.create_tween()
		tw.tween_property(r, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_SINE)
		r.set_meta("tw", tw)
	elif r.visible:
		var tw := r.create_tween()
		tw.tween_property(r, "modulate:a", 0.0, 0.14).set_trans(Tween.TRANS_SINE)
		tw.tween_callback(func(): r.visible = false)
		r.set_meta("tw", tw)

## Wraps content in a scroll box that grows with it up to the window height minus `margin`.
## Nothing in the game scrolls. When a menu has more than fits on screen, it splits into pages
## with a small "Page 1 of 2" control, and it remembers which page you were on when it's rebuilt,
## so clicking a button never jumps you somewhere else.
static var _page_of := {}       # menu key -> page shown
static var _tall := {}          # menu key -> tallest the menu has been, so it never jumps around
static var _live := {}          # menu key -> how many of it are open

## Wraps a VBox of content so it pages instead of overflowing. margin: room left for the rest of
## the screen. Returns the wrapper to add where the content would have gone.
static func paged(content: VBoxContainer, margin: float, key: String, head: Control = null, width_hint := 600.0, foot: Control = null) -> VBoxContainer:
	var wrap := vbox(8)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_child(content)
	var pager := hbox(10)
	pager.alignment = BoxContainer.ALIGNMENT_CENTER
	pager.visible = false
	var prev := ghost("Back", Callable(), 100, "back")
	var lbl := label("", T_SMALL, MUTED)
	var next := ghost("Next", Callable(), 100, "next")
	pager.add_child(prev); pager.add_child(lbl); pager.add_child(next)
	wrap.add_child(pager)
	var state := {"busy": false, "t0": 0}
	var fit := func() -> void:
		if state["busy"] or not is_instance_valid(content) or not content.is_inside_tree():
			return
		state["busy"] = true
		var vp := content.get_viewport_rect().size
		var maxh := maxf(160.0, vp.y - margin - (head.get_combined_minimum_size().y if head else 0.0) - (foot.get_combined_minimum_size().y + float(GAP_BIG) if foot and foot.visible else 0.0))
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
	if foot: foot.visibility_changed.connect(refit)
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
	# a heading never sits alone at the bottom of a page: it moves over with what it introduces
	for i in range(pages.size() - 1):
		var pgi: Array = pages[i]
		while pgi.size() > 1 and (pgi[-1]["nodes"][0] as Control).has_meta("pg_head"):
			pages[i + 1].push_front(pgi.pop_back())
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

# ---------------------------------------------------------------- the panel shell
## A menu panel, the same everywhere: a title (and an optional subtitle) with a close X at the top
## right, an optional row of tabs, the body, and an optional footer of actions at the bottom right.
## The body pages (or, with scroll, scrolls) whenever it's taller than the window, so nothing ends up
## off screen. Returns [panel, body]; use subtitle(body, ...), shell_tabs(body, ...), footer(body)
## and head_extra(body) to fill the rest.
static func scroll_panel(title_txt: String, width: float, on_close: Callable, close_txt := "Close", scroll := false) -> Array:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.theme_type_variation = ""
	sheen(p, 20, 0.055, 0.45)
	var outer := vbox(GAP_BIG - 4)
	p.add_child(outer)
	var top := vbox(GAP)
	outer.add_child(top)
	var head := hbox(GAP)
	if on_close.is_valid() and close_txt == "Back":
		# a sub-page: the way back sits before the title
		var bb := icon_button("back", on_close, "Back  (Esc)", 14.0)
		bb.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		bb.focus_mode = Control.FOCUS_NONE
		bb.name = "Close"
		head.add_child(bb)
	var tcol := vbox(2); tcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := title(title_txt, T_TITLE, INK)
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tcol.add_child(t)
	var sub := label("", T_SMALL + 1, MUTED)
	sub.visible = false
	tcol.add_child(sub)
	head.add_child(tcol)
	var extra := hbox(8)
	extra.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(extra)
	if on_close.is_valid() and close_txt != "Back":
		var xb := icon_button("close", on_close, close_txt + "  (Esc)", 14.0)
		xb.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		xb.focus_mode = Control.FOCUS_NONE     # Esc does it; keep it out of the keyboard path
		xb.name = "Close"
		head.add_child(xb)
	top.add_child(head)
	var tabs_slot := vbox(0)
	tabs_slot.visible = false
	top.add_child(tabs_slot)
	var body := vbox(GAP)
	var foot := hbox(10)
	foot.visible = false
	foot.alignment = BoxContainer.ALIGNMENT_END
	var foot_left := hbox(12)
	foot_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot_left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(foot_left)
	var foot_right := hbox(10)
	foot.add_child(foot_right)
	if scroll:
		# a real scroll for long lists like Settings: grows with its content up to the window height
		var sc := ScrollContainer.new()
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pad := MarginContainer.new(); pad.add_theme_constant_override("margin_right", 14)
		pad.add_theme_constant_override("margin_left", 3); pad.add_theme_constant_override("margin_top", 3); pad.add_theme_constant_override("margin_bottom", 3)
		pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pad.add_child(body)
		sc.add_child(pad)
		outer.add_child(sc)
		var fit := func() -> void:
			if is_instance_valid(sc) and sc.is_inside_tree():
				var chrome := top.get_combined_minimum_size().y + (foot.get_combined_minimum_size().y + GAP_BIG if foot.visible else 0.0)
				sc.custom_minimum_size.y = minf(pad.get_combined_minimum_size().y, sc.get_viewport_rect().size.y - 110.0 - chrome)
		body.minimum_size_changed.connect(func(): fit.call_deferred())
		top.minimum_size_changed.connect(func(): fit.call_deferred())
		foot.visibility_changed.connect(func(): fit.call_deferred())
		sc.tree_entered.connect(func(): fit.call_deferred())
		body.set_meta("scroll", sc)
	else:
		outer.add_child(paged(body, 110.0, title_txt, top, width - PAD * 2.0, foot))
	outer.add_child(foot)
	body.set_meta("shell", p)
	p.set_meta("title", t); p.set_meta("sub", sub); p.set_meta("extra", extra)
	p.set_meta("tabs", tabs_slot); p.set_meta("foot", foot); p.set_meta("foot_left", foot_left); p.set_meta("foot_right", foot_right)
	var fitw := func():
		if is_instance_valid(p) and p.is_inside_tree():
			p.custom_minimum_size.x = minf(width, p.get_viewport_rect().size.x - 32.0)
	p.tree_entered.connect(func(): fitw.call_deferred())
	p.custom_minimum_size.x = width
	# keyboard and pad users start on the first thing they can press
	p.tree_entered.connect(func(): focus_first(p))
	return [p, body]

static func _shell_of(body: Control) -> PanelContainer:
	var n: Node = body
	while n:
		if n.has_meta("shell"): return n.get_meta("shell")
		if n.has_meta("foot"): return n as PanelContainer
		n = n.get_parent()
	return null

## A short line under a panel's title.
static func subtitle(body: Control, txt: String) -> void:
	var p := _shell_of(body)
	if p == null: return
	var s: Label = p.get_meta("sub")
	s.text = txt
	s.visible = txt != ""

## Changes a panel's title.
static func set_title(body: Control, txt: String) -> void:
	var p := _shell_of(body)
	if p: (p.get_meta("title") as Label).text = txt

## A row next to the close X for chips and small things (gems, stored count).
static func head_extra(body: Control) -> HBoxContainer:
	var p := _shell_of(body)
	return p.get_meta("extra") if p else hbox()

## Tabs under the title (a segmented control). Returns the tabs control.
static func shell_tabs(body: Control, names: Array, cur: String, cb: Callable, counts := {}) -> Control:
	var p := _shell_of(body)
	var tb := tabs(names, cur, cb, counts)
	if p == null:
		body.add_child(tb)
		return tb
	var slot: VBoxContainer = p.get_meta("tabs")
	for ch in slot.get_children(): ch.queue_free()
	slot.add_child(tb)
	slot.visible = true
	return tb

## The footer's action row (bottom right). Add buttons to it; the primary goes last.
static func footer(body: Control) -> HBoxContainer:
	var p := _shell_of(body)
	if p == null:
		var h := hbox(10); h.alignment = BoxContainer.ALIGNMENT_END
		body.add_child(h)
		return h
	(p.get_meta("foot") as Control).visible = true
	return p.get_meta("foot_right")

## The footer's main button: primary, with an Enter keycap. Hosts press it on Enter when nothing
## else has focus (press_primary).
static func footer_primary(body: Control, text: String, cb: Callable, minw := 0.0, icon := "") -> Button:
	var b := with_key(primary(text, cb, minw, icon), "Enter")
	footer(body).add_child(b)
	var p := _shell_of(body)
	if p: p.set_meta("primary", b)
	return b

## Presses the primary footer button of the panel under host, if it has one. True when it did.
static func press_primary(host: Node) -> bool:
	for ch in host.get_children():
		if ch.has_meta("primary"):
			var b = ch.get_meta("primary")
			if is_instance_valid(b) and not (b as Button).disabled and (b as Button).is_visible_in_tree():
				(b as Button).pressed.emit()
				return true
	return false

## The footer's left side: hints and notes that go with the actions.
static func footer_left(body: Control) -> HBoxContainer:
	var p := _shell_of(body)
	if p == null: return hbox()
	(p.get_meta("foot") as Control).visible = true
	return p.get_meta("foot_left")

## A plain sheet (a panel without the shell), for full-screen menus like results or the lobby.
static func sheet(width := 0.0) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	sheen(p, 20, 0.055, 0.45)
	if width > 0.0: p.custom_minimum_size.x = width
	return p

## A small modal on top of a panel host: a question, Cancel, and a danger (or primary) button.
## Only for things that can't be undone.
static func confirm(host: Control, head: String, text: String, yes_txt: String, on_yes: Callable, dangerous := true) -> Control:
	var layer := Modal.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new(); dim.color = Color(0.02, 0.02, 0.05, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var cc := CenterContainer.new(); cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(cc)
	var p := sheet(420)
	cc.add_child(p)
	var v := vbox(GAP); p.add_child(v)
	v.add_child(title(head, 24))
	v.add_child(para(text, T_BODY, MUTED))
	v.add_child(spacer(4))
	var row := hbox(10); row.alignment = BoxContainer.ALIGNMENT_END
	var no := ghost("Cancel", func(): layer.queue_free())
	row.add_child(no)
	var yes := (danger if dangerous else primary).call(yes_txt, func(): layer.queue_free(); on_yes.call()) as Button
	row.add_child(yes)
	v.add_child(row)
	layer.set_meta("modal", true)
	host.add_child(layer)
	pop_in(p)
	no.grab_focus.call_deferred()
	return layer

## The layer under confirm(): Esc (or the pad's B) cancels it before anything else sees the key.
class Modal extends Control:
	func _input(ev: InputEvent) -> void:
		if ev.is_action_pressed("ui_cancel") or (InputMap.has_action("menu") and ev.is_action_pressed("menu")):
			get_viewport().set_input_as_handled()
			queue_free()

## A glyph that knows the menu's own icons too (close, back, gear, home, ...).
class IconDot extends Control:
	var id := ""
	var col := Color.WHITE
	func _init(icon_id := "", c := Color.WHITE, px := 18.0) -> void:
		id = icon_id; col = c
		custom_minimum_size = Vector2(px, px)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
	func _draw() -> void:
		UI.draw_icon(self, id, size * 0.5, minf(size.x, size.y) * 0.5, col)

## The old rule under a menu title (a gilded line with a diamond). The shell doesn't use it any more;
## kept for anything that still wants an ornament.
class Ornament extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(0, 14)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var w := size.x
		var y := size.y * 0.5
		var gold := Color(0.92, 0.74, 0.46)
		var n := 40
		for i in n:
			var a := float(i) / n
			var b := float(i + 1) / n
			var k := sin(a * PI)
			draw_line(Vector2(w * a, y), Vector2(w * b, y), Color(gold, 0.08 + 0.5 * k), 2.0)
		var c := Vector2(w * 0.5, y)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -6), c + Vector2(7, 0), c + Vector2(0, 6), c + Vector2(-7, 0)]), gold)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -3), c + Vector2(3.5, 0), c + Vector2(0, 3), c + Vector2(-3.5, 0)]), Color(0.12, 0.08, 0.12))
		for sx in [-1.0, 1.0]:
			draw_circle(c + Vector2(22 * sx, 0), 2.2, Color(gold, 0.85))
