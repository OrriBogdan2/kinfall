extends CanvasLayer
## In-match interface, drawn every frame: health, ability bar, kin card, timer, minimap, kill feed,
## kin speech bubbles, callout pings, interaction prompts, crosshair and the scoreboard.

var m: Match
var c: Control
var big: Font = preload("res://fonts/LilitaOne-Regular.ttf")
var body: Font = preload("res://fonts/Rubik.ttf")
var hit_t := 0.0
var hit_crit := false
var hurt_t := 0.0
var toasts: Array = []
var minimap: ImageTexture
var kit_t0 := 0.0
var bar_lerp := 1.0

const INK := Color("f3eee2")
const MUTED := Color("a9b0bf")
const PANEL := Color(0.06, 0.07, 0.1, 0.72)
const EDGE := Color(1, 1, 1, 0.08)
const GOOD := Color("8fe0a0")
const BAD := Color("ff6a5a")
const GOLD := Color("f2c84a")

func setup(match_node: Match) -> void:
	m = match_node
	layer = 5
	c = Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	c.draw.connect(_draw_all)
	_build_minimap()

func _process(delta: float) -> void:
	hit_t = maxf(0.0, hit_t - delta)
	_hud_tick(delta)
	flash_t = maxf(0.0, flash_t - delta * 4.0)
	hurt_t = maxf(0.0, hurt_t - delta)
	for t in toasts.duplicate():
		t["t"] += delta
		if t["t"] > 1.8: toasts.erase(t)
	if tips.size() > 0:
		tips[0]["t"] += delta
		if tips[0]["t"] > 7.0: tips.pop_front()
	c.queue_redraw()

var hit_armor := false

func hitmarker(crit: bool, armor := false) -> void:
	hit_t = 0.14
	hit_crit = crit
	hit_armor = armor

var flash_t := 0.0
var flash_col := Color.WHITE
## A full-screen flash for big moments.
func flash(col: Color, strength := 0.35) -> void:
	flash_col = Color(col, strength)
	flash_t = 1.0

func hurt_flash(d: float) -> void:
	hurt_t = clampf(0.25 + d / 60.0, 0.25, 0.6)

func toast(text: String, col: Color) -> void:
	toasts.append({"text": text, "col": col, "t": 0.0})
	if toasts.size() > 3: toasts.pop_front()

var tips: Array = []

func tip(text: String) -> void:
	tips.append({"text": text, "t": 0.0})

func _build_minimap() -> void:
	var w := m.world
	var img := Image.create(w.w, w.h, false, Image.FORMAT_RGBA8)
	for z in w.h:
		for x in w.w:
			var i := w.idx(x, z)
			var col := Color(0, 0, 0, 0)
			if w.kind[i] == World.T_GROUND:
				col = Color(w.biome["top"]).lightened(0.12 + 0.08 * w.level[i])
			elif w.kind[i] == World.T_BLOCK:
				col = Color(w.biome["top2"]).darkened(0.2)
			img.set_pixel(x, z, col)
	minimap = ImageTexture.create_from_image(img)

# ------------------------------------------------------------------ drawing helpers
func _panel(r: Rect2, col := PANEL, rad := 10) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(rad)
	sb.border_color = EDGE
	sb.set_border_width_all(1)
	c.draw_style_box(sb, r)

func _bar(r: Rect2, frac: float, col: Color, back := Color(0, 0, 0, 0.45)) -> void:
	c.draw_rect(r, back)
	c.draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(frac, 0.0, 1.0), r.size.y)), col)

func _text(p: Vector2, s: String, size := 15, col := INK, font: Font = null, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	var f := font if font else body
	c.draw_string_outline(f, p, s, align, width, size, 4, Color(0, 0, 0, 0.55))
	c.draw_string(f, p, s, align, width, size, col)

func _ctext(p: Vector2, s: String, size := 15, col := INK, font: Font = null) -> void:
	var f := font if font else body
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_text(Vector2(p.x - w * 0.5, p.y), s, size, col, f)

func _arc(center: Vector2, radius: float, frac: float, col: Color, width := 3.0) -> void:
	if frac <= 0.0: return
	c.draw_arc(center, radius, -PI / 2, -PI / 2 + TAU * clampf(frac, 0.0, 1.0), 40, col, width, true)

func _fmt(t: float) -> String:
	t = maxf(0.0, t)
	return "%d:%02d" % [int(t) / 60, int(t) % 60]

# ------------------------------------------------------------------ frame
func _draw_all() -> void:
	var sz := c.size
	var p := m.player
	_draw_world_labels()
	_draw_bubbles()
	_draw_pings(sz)
	if hurt_t > 0.0:
		var a := hurt_t * 0.9
		for i in 6:
			var inset := i * 14.0
			c.draw_rect(Rect2(Vector2(inset, inset), sz - Vector2(inset, inset) * 2.0), Color(0.8, 0.1, 0.08, a * (0.12 - i * 0.018)), false, 14.0)
	if p and not p.downed and not p.out and p.hp < p.max_hp * 0.35:
		var pulse := 0.5 + 0.5 * sin(m.time * 6.0)
		for i in 5:
			var inset := i * 16.0
			c.draw_rect(Rect2(Vector2(inset, inset), sz - Vector2(inset, inset) * 2.0), Color(0.75, 0.05, 0.05, (0.09 - i * 0.016) * (0.6 + pulse * 0.4)), false, 16.0)
	if flash_t > 0.0:
		c.draw_rect(Rect2(Vector2.ZERO, sz), Color(flash_col, flash_col.a * flash_t * (0.3 if Settings.get_v("reduce_flashes") else 1.0)))
	if p and (p.out or p.downed) and m.killcam_text != "":
		_ctext(Vector2(sz.x * 0.5, sz.y * 0.22), m.killcam_text, 22, Color("ff9a8a"), big)
	_draw_top(sz)
	_draw_feed(sz)
	_draw_minimap(sz)
	if p and not p.out and not p.extracted:
		_draw_overhead(p)
	if p:
		_draw_hurt_dirs(sz)
		if not p.out and not p.extracted:
			_draw_vitals(sz, p)
			_draw_abilities(sz, p)
			_draw_weapon(sz, p)
			_draw_kin_card(sz, p)
			_draw_squad(sz, p)
		if not p.riding:
			_draw_kit(sz, p)
		else:
			_draw_ship_prompt(sz)
		if not p.riding:
			_draw_prompt(sz, p)
			_draw_crosshair(p)
		if p.downed:
			_draw_downed(sz, p)
	_draw_small_toasts(sz)
	for i in toasts.size():
		var t: Dictionary = toasts[i]
		var a := clampf(1.8 - t["t"], 0.0, 1.0)
		_ctext(Vector2(sz.x * 0.5, sz.y * 0.3 + i * 26 - t["t"] * 10.0), t["text"], 20, Color(t["col"], a), big)
	if tips.size() > 0:
		_draw_tip(sz, tips[0])
	if Input.is_action_pressed("scores"):
		_draw_scores(sz)

func _draw_world_labels() -> void:
	var cam := m.cam
	for h in m.hunters:
		if h == m.player or h.out or h.extracted or not h.model or not h.model.visible:
			continue
		var sp := cam.unproject_position(h.position + Vector3(0, 2.15, 0))
		if cam.is_position_behind(h.position):
			continue
		var tc: Color = Data.TEAM_COLORS[h.team % 6]
		var ally: bool = m.player and h.team == m.player.team
		_ctext(sp + Vector2(0, -8), h.pname, 13, tc if not ally else GOOD, big)
		if h.downed:
			_bar(Rect2(sp + Vector2(-26, -2), Vector2(52, 5)), h.down_hp / Data.MATCH["down_hp"], BAD)
			_ctext(sp + Vector2(0, 14), "DOWN", 12, BAD, big)
			if h.revive > 0.0:
				_arc(sp + Vector2(0, 30), 10, h.revive, GOOD, 3.0)
		else:
			if h.armor > 0.5:
				_seg_bar(Rect2(sp + Vector2(-30, -4), Vector2(60, 3)), h.armor, h.max_armor, h.armor / maxf(1.0, h.max_armor), ARMOR_COL, 25.0)
			_seg_bar(Rect2(sp + Vector2(-30, 2), Vector2(60, 6)), h.hp, h.max_hp, h.hp / h.max_hp, (HP_LOW if not ally else GOOD) if h.hp < h.max_hp * 0.35 else (tc if not ally else GOOD), 25.0)
			if h.shield > 0.0:
				c.draw_rect(Rect2(sp + Vector2(-30, 2), Vector2(60 * clampf(h.shield / 120.0, 0.0, 1.0), 6)), Color(0.85, 0.93, 1.0, 0.5))
	for mb in m.mobs:
		if mb.dead or cam.is_position_behind(mb.position):
			continue
		var hy := 1.4
		if mb.mkind == "brute": hy = 2.4
		elif mb.mkind == "warden": hy = 3.4
		var sp := cam.unproject_position(mb.position + Vector3(0, hy, 0))
		if mb.stagger_t > 0.0:
			_ctext(sp + Vector2(0, -10), "STAGGERED", 15, Color("fff27a"), big)
		elif mb.stag_open > 0.0:
			var a := 0.75 + 0.25 * sin(m.time * 12.0)
			_ctext(sp + Vector2(0, -10), "STAGGERABLE", 14, Color(0.85, 0.6, 1.0, a), big)
		if mb.hp < mb.max_hp:
			_bar(Rect2(sp + Vector2(-20, 0), Vector2(40, 4)), mb.hp / mb.max_hp, Color("e0b0ff") if mb.stagger_t > 0.0 else Color("ff8a6a"))
	# found weapons: name and rarity when you're close enough to care
	var pp: Vector3 = m.player.pos if m.player else cam.focus
	for wp in m.wpicks:
		var wpos: Vector3 = wp["pos"]
		if Vector2(wpos.x - pp.x, wpos.z - pp.z).length() > 7.0 or cam.is_position_behind(wpos):
			continue
		var r: Dictionary = Data.RARITY[int(wp["rar"])]
		var sp := cam.unproject_position(wpos + Vector3(0, 1.45, 0))
		_ctext(sp, String(Data.weapon_stats(String(wp["wid"]), int(wp["rar"]))["name"]), 13, r["color"], big)
	for k in m.kins:
		if k.dead or not k.visible or k.state == "shoulder" or cam.is_position_behind(k.position):
			continue
		var sp := cam.unproject_position(k.position + Vector3(0, 1.05, 0))
		if k.is_wild():
			if k.state == "dazed":
				_ctext(sp + Vector2(0, -6), "Dazed!  F to catch", 13, GOLD, big)
				if k.catch_prog > 0.0:
					_arc(sp + Vector2(0, 10), 9, k.catch_prog, GOLD, 3.0)
			else:
				_ctext(sp + Vector2(0, -8), "Wild %s" % Data.KIN[k.species]["name"], 12, Color("bfe9ff"), big)
				_bar(Rect2(sp + Vector2(-18, -2), Vector2(36, 4)), k.hp / k.max_hp, Color("bfe9ff"))
		elif k.hp < k.max_hp and k.state != "fainted":
			_bar(Rect2(sp + Vector2(-16, 0), Vector2(32, 4)), k.hp / k.max_hp, Data.TEAM_COLORS[k.team % 6] if k.owner_h != m.player else GOOD)

func _draw_bubbles() -> void:
	var cam := m.cam
	for b in m.bubbles:
		var k: Kin = b["ent"]
		if k.dead:
			continue
		var at := k.position + Vector3(0, 1.2, 0)
		if k.state == "shoulder" and k.owner_h:
			at = k.owner_h.position + Vector3(0, 2.3, 0)
		if cam.is_position_behind(at):
			continue
		var sp := cam.unproject_position(at)
		var a := clampf((2.6 - b["t"]) * 3.0, 0.0, 1.0) * clampf(b["t"] * 8.0, 0.0, 1.0)
		var s: String = b["text"]
		var tw := body.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var r := Rect2(sp + Vector2(-tw * 0.5 - 12, -44), Vector2(tw + 24, 30))
		var mine: bool = k.owner_h == m.player
		var col := Color(0.98, 0.96, 0.9, 0.95 * a) if mine else Color(0.2, 0.22, 0.3, 0.85 * a)
		var sb := StyleBoxFlat.new(); sb.bg_color = col; sb.set_corner_radius_all(12)
		c.draw_style_box(sb, r)
		c.draw_colored_polygon(PackedVector2Array([sp + Vector2(-7, -15), sp + Vector2(7, -15), sp + Vector2(0, -6)]), col)
		c.draw_string(body, r.position + Vector2(12, 20), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.1, 0.09, 0.12, a) if mine else Color(INK, a))

func _draw_pings(sz: Vector2) -> void:
	var cam := m.cam
	for p in m.pings:
		var a := clampf(4.0 - p["t"], 0.0, 1.0)
		var col := Color(p["col"], a)
		var at: Vector3 = p["pos"] + Vector3(0, 1.0, 0)
		var on := cam.on_screen(at)
		if on:
			var sp := cam.unproject_position(at)
			var pulse := 1.0 + sin(p["t"] * 8.0) * 0.15
			c.draw_arc(sp, 14 * pulse, 0, TAU, 24, col, 3.0, true)
			c.draw_circle(sp, 4, col)
		else:
			var center := sz * 0.5
			var sp := cam.unproject_position(at)
			if cam.is_position_behind(at):
				sp = center - (sp - center)
			var d := (sp - center).normalized()
			var edge := center + d * minf(sz.x * 0.46 / maxf(absf(d.x), 0.001), sz.y * 0.44 / maxf(absf(d.y), 0.001))
			var n := Vector2(-d.y, d.x)
			c.draw_colored_polygon(PackedVector2Array([edge + d * 14, edge - d * 8 + n * 10, edge - d * 8 - n * 10]), col)

func _draw_top(sz: Vector2) -> void:
	if m.opts.get("training", false):
		var rr := Rect2(Vector2(sz.x * 0.5 - 220, 12), Vector2(440, 54))
		_panel(rr, Color(0.06, 0.07, 0.1, 0.88), 12)
		_ctext(Vector2(sz.x * 0.5, 34), "TRAINING AREA", 12, Color("8fe3c8"))
		_ctext(Vector2(sz.x * 0.5, 56), "Nothing can hurt you here  ·  Esc to leave", 15, INK)
		# the checklist
		var lines: Array = m.TRAIN
		var box := Rect2(Vector2(16, 90), Vector2(330, 34 + lines.size() * 24))
		_panel(box, Color(0.06, 0.07, 0.1, 0.82), 12)
		_text(box.position + Vector2(14, 24), "Try everything", 15, GOLD, big)
		for i in lines.size():
			var t: Array = lines[i]
			var done: bool = m.train.has(t[0])
			var key := ("[%s]  " % Settings.key_cap(t[2])) if t[2] != "" else ""
			if t[0] == "move": key = "[%s%s%s%s]  " % [Settings.key_cap("up"), Settings.key_cap("left"), Settings.key_cap("down"), Settings.key_cap("right")]
			_text(box.position + Vector2(14, 50 + i * 24), ("✓  " if done else "○  ") + key + String(t[1]), 13, GOOD if done else INK)
		return
	if m.opts.get("tutorial", false):
		var txt: String = m.tut_text
		var w := maxf(360.0, big.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 60.0)
		var rr := Rect2(Vector2(sz.x * 0.5 - w * 0.5, 12), Vector2(w, 66))
		_panel(rr, Color(0.06, 0.07, 0.1, 0.88), 12)
		_ctext(Vector2(sz.x * 0.5, 34), "TUTORIAL  %d / %d" % [mini(m.tut_step + 1, m.TUT.size()), m.TUT.size()], 12, Color("8fe3c8"))
		_ctext(Vector2(sz.x * 0.5, 62), txt, 22, Color("f2c84a"), big)
		return
	var left := m.length - m.time
	var first_open := 1e9
	for p in m.portals:
		if not p["open"]: first_open = minf(first_open, p["open_at"])
	var any_open := m.portals.any(func(p): return p["open"])
	var line := ""
	var col := MUTED
	if left < 30.0:
		line = "The islands are falling"; col = BAD
	elif any_open:
		line = "Exits are open"; col = Color("8fe3c8")
	else:
		line = "Exits open in %s" % _fmt(first_open - m.time)
	var r := Rect2(Vector2(sz.x * 0.5 - 110, 12), Vector2(220, 58))
	_panel(r)
	_ctext(Vector2(sz.x * 0.5, 44), _fmt(left), 30, BAD if left < 30.0 else INK, big)
	_ctext(Vector2(sz.x * 0.5, 63), line, 13, col)
	var teams := {}
	for h in m.hunters:
		if not h.out and not h.extracted: teams[h.team] = true
	_text(Vector2(r.end.x + 12, 34), "%d squads left" % teams.size(), 14, MUTED)

func _draw_feed(sz: Vector2) -> void:
	var y := 250.0
	for f in m.feed:
		var a := clampf(6.0 - f["t"], 0.0, 1.0)
		var s: String = f["text"]
		var w := body.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		_panel(Rect2(Vector2(sz.x - w - 34, y - 18), Vector2(w + 20, 26)), Color(0.06, 0.07, 0.1, 0.6 * a), 8)
		_text(Vector2(sz.x - w - 24, y), s, 14, Color(INK, a))
		y += 30

func _draw_minimap(sz: Vector2) -> void:
	var riding: bool = m.player != null and m.player.riding
	var s := 340.0 if riding else 200.0
	var r := Rect2(Vector2(sz.x - s - 16, 16), Vector2(s, s))
	_panel(r, Color(0.05, 0.06, 0.09, 0.7), 12)
	var w := m.world
	var k := (s - 16) / float(w.w)
	var o := r.position + Vector2(8, 8)
	c.draw_texture_rect(minimap, Rect2(o, Vector2(w.w, w.h) * k), false)
	for p in m.portals:
		var pp: Vector3 = p["pos"]
		var col := Color("8fe3c8") if p["open"] else Color(0.6, 0.65, 0.7, 0.6)
		c.draw_arc(o + Vector2(pp.x, pp.z) * k, 5, 0, TAU, 16, col, 2.0, true)
	if not m.ship.is_empty() and not m.ship.get("gone", false):
		var sa: Vector3 = m.ship["a"]; var sb: Vector3 = m.ship["b"]
		c.draw_line(o + Vector2(sa.x, sa.z) * k, o + Vector2(sb.x, sb.z) * k, Color(1, 1, 1, 0.35), 2.0, true)
		var sp: Vector3 = m.ship_pos()
		c.draw_circle(o + Vector2(sp.x, sp.z) * k, 5.0, GOLD)
	for pg in m.pings:
		var pp: Vector3 = pg["pos"]
		c.draw_circle(o + Vector2(pp.x, pp.z) * k, 3.5, pg["col"])
	for h in m.hunters:
		if h.out or h.extracted: continue
		if m.player and h.team == m.player.team:
			var col := INK if h == m.player else GOOD
			var pp := o + Vector2(h.pos.x, h.pos.z) * k
			c.draw_circle(pp, 4.0 if h == m.player else 3.0, col)
			if h == m.player:
				var d: Vector2 = h.aim_dir()
				c.draw_line(pp, pp + d * 10.0, col, 2.0)

## On narrow windows the ability bar takes the whole bottom row and the player card sits above it.
func _narrow(sz: Vector2) -> bool:
	return sz.x < 1080.0

## ------------------------------------------------------------------ combat HUD
## Bottom centre: armor and health over the ability row. Bottom left: your kin. Bottom right: your
## weapon and what you're carrying. Left: your squad. Hits on you show which way they came from.
const ARMOR_COL := Color("7ac8ff")
const HP_COL := Color("8fe0a0")
const HP_LOW := Color("ff6a5a")
var armor_lerp := 1.0
var ready_was := {}        # slot id -> was it ready last frame, for the "ready" flash
var ready_flash := {}      # slot id -> time left on its flash
var hurt_dirs: Array = []  # {ang, t}
var small_toasts: Array = []

func hurt_from(at: Vector3) -> void:
	var p := m.player
	if p == null:
		return
	var d := Vector2(at.x - p.pos.x, at.z - p.pos.z)
	if d.length() < 0.3:
		return
	hurt_dirs.append({"ang": atan2(d.y, d.x), "t": 0.0})
	if hurt_dirs.size() > 6: hurt_dirs.pop_front()

func toast_small(text: String, col: Color) -> void:
	small_toasts.append({"text": text, "col": col, "t": 0.0})
	if small_toasts.size() > 3: small_toasts.pop_front()

func _rounded(r: Rect2, col: Color, rad := 10, border := Color(0, 0, 0, 0), bw := 0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(rad)
	if bw > 0:
		sb.border_color = border
		sb.set_border_width_all(bw)
	sb.anti_aliasing = true
	c.draw_style_box(sb, r)

## A pie slice covering the part of a slot still on cooldown, sweeping clockwise from the top.
func _sweep(center: Vector2, radius: float, frac: float, col: Color) -> void:
	if frac <= 0.001:
		return
	var pts := PackedVector2Array([center])
	var n := 28
	var a0 := -PI / 2.0 + TAU * (1.0 - frac)
	for i in n + 1:
		var a := a0 + TAU * frac * float(i) / n
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	c.draw_colored_polygon(pts, col)

## A segmented bar: ticks every `step` points, a pale trail where damage was just taken.
func _seg_bar(r: Rect2, val: float, maxv: float, trail: float, col: Color, step: float) -> void:
	_rounded(r.grow(2.0), Color(0.03, 0.03, 0.05, 0.82), 4)
	var f := clampf(val / maxf(1.0, maxv), 0.0, 1.0)
	if trail > f:
		c.draw_rect(Rect2(r.position, Vector2(r.size.x * trail, r.size.y)), Color(1.0, 0.92, 0.82, 0.85))
	c.draw_rect(Rect2(r.position, Vector2(r.size.x * f, r.size.y)), col)
	c.draw_rect(Rect2(r.position, Vector2(r.size.x * f, r.size.y * 0.35)), Color(1, 1, 1, 0.18))
	var ticks := int(maxv / step)
	for i in range(1, ticks + (0 if fmod(maxv, step) > 0.01 else 0)):
		var x := r.position.x + r.size.x * (i * step / maxv)
		if x < r.end.x - 1.0:
			c.draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color(0.03, 0.03, 0.05, 0.85), 2.0)

func _keycap(center: Vector2, key: String, col: Color) -> void:
	var kw := big.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var kr := Rect2(center - Vector2(kw * 0.5 + 6, 9), Vector2(kw + 12, 18))
	_rounded(kr, Color(0.04, 0.04, 0.06, 0.95), 6, col, 1)
	c.draw_string(big, Vector2(kr.position.x + 6, kr.position.y + 14), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)

## One ability slot: icon, cooldown sweep and seconds, charges, key, and a flash when it's ready.
func _ab_slot(id: String, rect: Rect2, icon: String, key: String, col: Color, cd_frac: float, cd_secs: float, ready: bool, charges := -1, max_ch := 0, label := "") -> void:
	var ctr := rect.get_center()
	var was: bool = ready_was.get(id, true)
	if ready and not was:
		ready_flash[id] = 0.35
	ready_was[id] = ready
	_rounded(rect, Color(0.05, 0.06, 0.09, 0.9), 12, col if ready else Color(1, 1, 1, 0.12), 2)
	if ready:
		c.draw_rect(Rect2(rect.position + Vector2(3, 3), Vector2(rect.size.x - 6, rect.size.y * 0.42)), Color(col, 0.08))
	Icons.draw(c, icon, ctr + Vector2(0, -2), rect.size.x * 0.27, col if ready else Color(col.lerp(MUTED, 0.6), 0.55))
	if cd_frac > 0.0:
		_sweep(ctr, rect.size.x * 0.66, cd_frac, Color(0.0, 0.0, 0.0, 0.52))
		if cd_secs > 0.0:
			_ctext(ctr + Vector2(0, 8), str(int(ceil(cd_secs))) if cd_secs >= 1.0 else "%.1f" % cd_secs, 22, INK, big)
	if max_ch > 1:
		for i in max_ch:
			var pc := Vector2(rect.position.x + rect.size.x * 0.5 + (i - (max_ch - 1) * 0.5) * 10.0, rect.position.y + 8)
			c.draw_circle(pc, 3.2, Color(0, 0, 0, 0.6))
			c.draw_circle(pc, 2.4, col if i < charges else Color(1, 1, 1, 0.18))
	if label != "":
		_ctext(Vector2(ctr.x, rect.position.y - 6), label, 11, Color(INK, 0.85))
	_keycap(Vector2(ctr.x, rect.end.y), key, col if ready else MUTED)
	var fl := float(ready_flash.get(id, 0.0))
	if fl > 0.0:
		var k := 1.0 - fl / 0.35
		_rounded(rect.grow(2.0 + k * 8.0), Color(0, 0, 0, 0), 14, Color(col, 1.0 - k), 3)

func _hud_tick(delta: float) -> void:
	for id in ready_flash.keys():
		ready_flash[id] = float(ready_flash[id]) - delta
		if float(ready_flash[id]) <= 0.0: ready_flash.erase(id)
	for h in hurt_dirs.duplicate():
		h["t"] = float(h["t"]) + delta
		if float(h["t"]) > 1.2: hurt_dirs.erase(h)
	for t in small_toasts.duplicate():
		t["t"] = float(t["t"]) + delta
		if float(t["t"]) > 1.4: small_toasts.erase(t)

## Health and armor over the ability row, with your hero, lives and glider cloth.
func _draw_vitals(sz: Vector2, p: Hunter) -> void:
	var w := 380.0
	var x0 := sz.x * 0.5 - w * 0.5
	var y0 := sz.y - 150.0
	var hc: Color = Data.HEROES[p.hero]["color"]
	# hero badge
	var bc := Vector2(x0 - 30, y0 + 16)
	c.draw_circle(bc, 24, Color(0.04, 0.04, 0.06, 0.92))
	c.draw_arc(bc, 24, 0, TAU, 40, hc, 2.5, true)
	_ctext(bc + Vector2(0, 9), String(Data.HEROES[p.hero]["name"]).substr(0, 1), 24, hc, big)
	if p.lives < 50:
		for i in p.lives:
			var hp_c := bc + Vector2((i - (p.lives - 1) * 0.5) * 11.0, 32)
			c.draw_circle(hp_c, 4.0, Color("ff7a8a"))
	# armor over health
	var frac := clampf(p.hp / p.max_hp, 0.0, 1.0)
	bar_lerp = move_toward(bar_lerp, frac, get_process_delta_time() * (0.35 if bar_lerp > frac else 4.0))
	var af := clampf(p.armor / maxf(1.0, p.max_armor), 0.0, 1.0)
	armor_lerp = move_toward(armor_lerp, af, get_process_delta_time() * (0.5 if armor_lerp > af else 4.0))
	_seg_bar(Rect2(Vector2(x0, y0), Vector2(w, 8)), p.armor, p.max_armor, armor_lerp, ARMOR_COL, 25.0)
	var low := frac < 0.35
	var hcol := HP_LOW.lerp(Color.WHITE, 0.25 * (0.5 + 0.5 * sin(m.time * 9.0))) if low else HP_COL
	_seg_bar(Rect2(Vector2(x0, y0 + 14), Vector2(w, 16)), p.hp, p.max_hp, bar_lerp, hcol, 25.0)
	if p.shield > 0.0:
		c.draw_rect(Rect2(Vector2(x0, y0 + 14), Vector2(w * clampf(p.shield / 120.0, 0.0, 1.0), 16)), Color(0.85, 0.93, 1.0, 0.45))
	var hp_txt := str(int(ceil(p.hp)))
	_text(Vector2(x0 + w + 10, y0 + 30), hp_txt, 24, INK if not low else HP_LOW, big)
	if p.armor > 0.5:
		_text(Vector2(x0 + w + 10, y0 + 8), str(int(ceil(p.armor))), 13, ARMOR_COL, big)
	# glider cloth, while it matters
	if p.gliding or p.glide_fuel < 0.999:
		var gr := Rect2(Vector2(x0 + w * 0.25, y0 - 9), Vector2(w * 0.5, 3))
		c.draw_rect(gr.grow(1.0), Color(0.03, 0.03, 0.05, 0.7))
		var gcol := Color("f3eee2") if p.glide_fuel > 0.25 else Color("ff9a7a")
		c.draw_rect(Rect2(gr.position, Vector2(gr.size.x * p.glide_fuel, 3)), gcol if p.gliding else Color(gcol, 0.5))

## The ability row: kin throw and skill, hero ability, the ultimate in the middle, dash, tonic.
func _draw_abilities(sz: Vector2, p: Hunter) -> void:
	var s := 60.0
	var gap := 12.0
	var us := 72.0
	var k: Kin = p.kin
	var n_small := 5 if k else 3
	var total := n_small * s + us + (n_small) * gap
	var x := sz.x * 0.5 - total * 0.5
	var y := sz.y - 88.0
	var hc: Color = Data.HEROES[p.hero]["color"]
	if k:
		var kc: Color = Data.KIN[k.species]["color"]
		var out_now: bool = k.state in ["active", "flying"]
		var can_throw: bool = k.state in ["shoulder", "active", "flying"]
		_ab_slot("throw", Rect2(Vector2(x, y), Vector2(s, s)), "recall" if out_now else "throw", Settings.key_cap("throw"), kc, 0.0, 0.0, can_throw, -1, 0, "Recall" if out_now else "")
		x += s + gap
		var sk_id: String = Data.KIN[k.species]["skill"]
		var sk: Dictionary = Data.KIN_SKILLS[sk_id]
		var kready: bool = k.skill_cd <= 0.0 and k.state not in ["fainted", "reviving"]
		_ab_slot("kskill", Rect2(Vector2(x, y), Vector2(s, s)), sk_id, Settings.key_cap("kin_skill"), kc, k.skill_cd / float(sk["cd"]) if k.skill_cd > 0.0 else 0.0, k.skill_cd, kready)
		x += s + gap
	var e_id := Abil.e_id(p)
	var e_ab: Dictionary = Data.ABIL[e_id]
	_ab_slot("e", Rect2(Vector2(x, y), Vector2(s, s)), e_id, Settings.key_cap("signature"), hc, p.sig_cd / float(e_ab["cd"]) if p.sig_cd > 0.0 else 0.0, p.sig_cd, p.sig_cd <= 0.0)
	x += s + gap
	# the ultimate: a ring that fills as it charges
	var r_id := Abil.r_id(p)
	var ur := Rect2(Vector2(x, y - (us - s)), Vector2(us, us))
	var ready_r := p.ult >= 1.0
	_ab_slot("r", ur, r_id, Settings.key_cap("ultimate"), GOLD, 0.0, 0.0, ready_r)
	if not ready_r:
		c.draw_arc(ur.get_center(), us * 0.5 + 4.0, -PI / 2, -PI / 2 + TAU * p.ult, 48, GOLD, 3.0, true)
		_ctext(ur.get_center() + Vector2(0, us * 0.5 - 12), "%d%%" % int(p.ult * 100.0), 12, Color(GOLD, 0.9), big)
	else:
		var pulse := 0.5 + 0.5 * sin(m.time * 6.0)
		_rounded(ur.grow(3.0 + pulse * 3.0), Color(0, 0, 0, 0), 15, Color(1.0, 0.82, 0.3, 0.35 + pulse * 0.4), 2)
	x += us + gap
	var dmax := p.max_dashes()
	var dcd := (1.0 - fposmod(p.dashes, 1.0)) if p.dashes < dmax else 0.0
	_ab_slot("dash", Rect2(Vector2(x, y), Vector2(s, s)), "dash", Settings.key_cap("dash"), Color("bfe6ff"), dcd if p.dashes < 1.0 else 0.0, (1.0 - fposmod(p.dashes, 1.0)) * Hunter.DASH_REGEN if p.dashes < 1.0 else 0.0, p.dashes >= 1.0, int(floor(p.dashes)), int(dmax))
	x += s + gap
	_ab_slot("tonic", Rect2(Vector2(x, y), Vector2(s, s)), "tonic", Settings.key_cap("tonic"), GOOD, 0.0, 0.0, p.tonics > 0, -1, 0)
	_ctext(Vector2(x + s - 10, y + 18), "×%d" % p.tonics, 13, INK, big)

## Your weapon: rarity, ammo, reload. Under it, what you're carrying home.
func _draw_weapon(sz: Vector2, p: Hunter) -> void:
	var w := 250.0
	var r := Rect2(Vector2(sz.x - w - 16, sz.y - 110), Vector2(w, 94))
	if _narrow(sz):
		r.position.y -= 110.0
	var rc: Color = Data.RARITY[p.wrar]["color"] if p.wrar > 0 else Color("e6dccb")
	_rounded(r, Color(0.05, 0.06, 0.09, 0.85), 12)
	c.draw_rect(Rect2(r.position + Vector2(0, 10), Vector2(3, r.size.y - 20)), rc)
	_text(r.position + Vector2(16, 24), String(p.wpn["name"]), 15, rc, big)
	Icons.draw(c, p.wid, r.position + Vector2(52, 56), 30.0, Color(rc, 0.85))
	var mag := int(p.wpn["mag"])
	var ammo_col := INK if p.ammo > mag * 0.25 else HP_LOW
	if p.reload_t > 0.0:
		_text(r.position + Vector2(112, 66), "RELOADING", 16, Color("ffe7a8"), big)
		_bar(Rect2(r.position + Vector2(112, 72), Vector2(120, 4)), 1.0 - p.reload_t / float(p.wpn["reload"]), Color("ffe7a8"))
	else:
		_text(r.position + Vector2(112, 70), str(p.ammo), 34, ammo_col, big)
		var aw := big.get_string_size(str(p.ammo), HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
		_text(r.position + Vector2(118 + aw, 70), "/ %d" % mag, 15, MUTED, big)
	var seeds := 0
	for sd in p.seeds: seeds += int(p.seeds[sd])
	_text(r.position + Vector2(16, r.size.y - 8), "%d gems · %d seeds · %d kin" % [p.gems, seeds, p.caught.size()], 12, GOLD if p.gems > 0 else MUTED)

## Your partner: how it's doing and what it's up to.
func _draw_kin_card(sz: Vector2, p: Hunter) -> void:
	var k: Kin = p.kin
	if k == null:
		return
	var w := 250.0
	var r := Rect2(Vector2(16, sz.y - 110), Vector2(w, 94))
	if _narrow(sz):
		r.position.y -= 110.0
	var kc: Color = Data.KIN[k.species]["color"]
	_rounded(r, Color(0.05, 0.06, 0.09, 0.85), 12)
	var pc := r.position + Vector2(36, 40)
	c.draw_circle(pc, 22, kc)
	c.draw_circle(pc + Vector2(-7, -3), 3.2, Color.BLACK)
	c.draw_circle(pc + Vector2(7, -3), 3.2, Color.BLACK)
	if k.state == "fainted":
		c.draw_circle(pc, 22, Color(0, 0, 0, 0.5))
	var kname: String = k.rec.get("name", "Kin")
	_text(r.position + Vector2(68, 26), kname, 16, INK, big)
	var st := ""
	match k.state:
		"shoulder": st = ("On your shoulder · " + Data.SHOULDER[Data.KIN[k.species]["shoulder"]]["name"]) if k.settle >= 1.0 else "Settling in..."
		"flying", "flying_home": st = "In the air"
		"active": st = "Fighting" if k.target else "Out with you"
		"returning": st = "Coming back"
		"fainted": st = "Resting %ds" % int(ceil(k.faint_t))
		"reviving": st = "Reviving you!"
	_text(r.position + Vector2(68, 44), st, 12, MUTED)
	_seg_bar(Rect2(r.position + Vector2(68, 54), Vector2(w - 84, 8)), k.hp, k.max_hp, k.hp / k.max_hp, kc, 25.0)
	c.draw_circle(r.position + Vector2(74, 78), 4.0, Color("ffb3c6"))
	_text(r.position + Vector2(84, 83), "Trust %d · %s" % [int(k.trust), Care.bond(k.rec)[1] if k.rec.size() > 0 else ""], 12, Color("ffb3c6"))

## Your squadmates down the left side.
func _draw_squad(sz: Vector2, p: Hunter) -> void:
	var y := sz.y * 0.42
	for h in m.hunters:
		if h == p or h.team != p.team or h.out:
			continue
		var r := Rect2(Vector2(16, y), Vector2(190, 40))
		_rounded(r, Color(0.05, 0.06, 0.09, 0.75), 10)
		_text(r.position + Vector2(10, 17), h.pname, 13, GOOD if not h.downed else HP_LOW, big)
		if h.downed:
			_text(r.position + Vector2(10 + big.get_string_size(h.pname, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 8, 17), "DOWN", 12, HP_LOW, big)
			_bar(Rect2(r.position + Vector2(10, 26), Vector2(170, 5)), h.down_hp / Data.MATCH["down_hp"], HP_LOW)
		else:
			_bar(Rect2(r.position + Vector2(10, 22), Vector2(170, 3)), h.armor / maxf(1.0, h.max_armor), ARMOR_COL)
			_bar(Rect2(r.position + Vector2(10, 27), Vector2(170, 6)), h.hp / h.max_hp, HP_COL)
		y += 46

## Red arcs around the middle of the screen pointing at whoever just hit you.
func _draw_hurt_dirs(sz: Vector2) -> void:
	var ctr := sz * 0.5
	for h in hurt_dirs:
		var a := clampf(1.0 - float(h["t"]) / 1.2, 0.0, 1.0)
		var ang: float = h["ang"]
		var rad := minf(sz.x, sz.y) * 0.22
		c.draw_arc(ctr, rad, ang - 0.32, ang + 0.32, 18, Color(1.0, 0.25, 0.2, 0.75 * a), 7.0, true)
		var tip := ctr + Vector2(cos(ang), sin(ang)) * (rad + 12.0)
		var nrm := Vector2(-sin(ang), cos(ang))
		c.draw_colored_polygon(PackedVector2Array([tip, tip - Vector2(cos(ang), sin(ang)) * 12.0 + nrm * 9.0, tip - Vector2(cos(ang), sin(ang)) * 12.0 - nrm * 9.0]), Color(1.0, 0.25, 0.2, 0.8 * a))

func _draw_small_toasts(sz: Vector2) -> void:
	for i in small_toasts.size():
		var t: Dictionary = small_toasts[i]
		var a := clampf(1.4 - float(t["t"]), 0.0, 1.0) * clampf(float(t["t"]) * 10.0, 0.0, 1.0)
		_ctext(Vector2(sz.x * 0.5, sz.y * 0.5 + 64 + i * 22 - float(t["t"]) * 8.0), t["text"], 16, Color(t["col"], a), big)

## Aboard the skyship: when to jump.
func _draw_ship_prompt(sz: Vector2) -> void:
	var left := maxf(0.0, float(m.ship.get("ride", 0.0)) - m.time)
	var w := 460.0
	var cam := m.cam
	# where you'd come down if you jumped now: a ring on the ground under the ship
	var sp: Vector3 = m.ship_pos()
	if not m.world.is_void(sp.x, sp.z):
		var g := Vector3(sp.x, m.world.ground_at(sp.x, sp.z), sp.z)
		var gp := cam.unproject_position(g)
		var top := cam.unproject_position(sp)
		var dash := 0.0
		var L := gp.distance_to(top)
		while dash < L:
			c.draw_line(top.lerp(gp, dash / L), top.lerp(gp, minf(1.0, (dash + 6.0) / L)), Color(1, 0.85, 0.4, 0.55), 2.0)
			dash += 12.0
		var pul := 1.0 + sin(m.time * 5.0) * 0.08
		c.draw_arc(gp, 22.0 * pul, 0, TAU, 40, GOLD, 3.0, true)
		c.draw_arc(gp, 8.0, 0, TAU, 20, Color(GOLD, 0.6), 2.0, true)
	var rr := Rect2(Vector2(sz.x * 0.5 - w * 0.5, 92), Vector2(w, 92))
	_panel(rr, Color(0.06, 0.07, 0.1, 0.88), 14)
	_ctext(Vector2(sz.x * 0.5, rr.position.y + 36), "Press %s to jump" % Settings.key_cap("jump"), 26, GOLD, big)
	_ctext(Vector2(sz.x * 0.5, rr.position.y + 62), "Pick your spot on the map. Everyone left aboard drops in %ds" % int(ceil(left)), 14, INK)
	_bar(Rect2(Vector2(rr.position.x + 20, rr.position.y + 76), Vector2(w - 40, 4)), clampf(m.time / maxf(1.0, float(m.ship.get("ride", 1.0))), 0.0, 1.0), GOLD)

## For the first seconds of every match: what each of your buttons does.
func _draw_kit(sz: Vector2, p: Hunter) -> void:
	if not Settings.get_v("tips") or m.opts.get("tutorial", false) or p.out:
		return
	var show_t := 14.0 if not m.opts.get("training", false) else 1e9
	var t := m.time - kit_t0
	if p.dropping or p.riding:
		kit_t0 = m.time
		t = 0.0
	if t > show_t:
		return
	var a := clampf(show_t - t, 0.0, 1.0)
	var lines: Array = []
	var e_ab: Dictionary = Data.ABIL[Abil.e_id(p)]
	var r_ab: Dictionary = Data.ABIL[Abil.r_id(p)]
	lines.append([Settings.key_cap("signature"), e_ab["name"], e_ab["desc"], Data.HEROES[p.hero]["color"]])
	lines.append([Settings.key_cap("ultimate"), r_ab["name"] + " (ultimate)", r_ab["desc"], Color("f2c84a")])
	if p.kin:
		var sk: Dictionary = Data.KIN_SKILLS[Data.KIN[p.kin.species]["skill"]]
		lines.append([Settings.key_cap("throw"), "Throw " + String(p.kin.rec.get("name", "your kin")), "Stuns what it hits. Click again to call it back.", Data.KIN[p.kin.species]["color"]])
		lines.append([Settings.key_cap("kin_skill"), sk["name"], sk["desc"], Data.KIN[p.kin.species]["color"]])
	var w := 420.0
	var box := Rect2(Vector2(sz.x - w - 16, sz.y - 186 - lines.size() * 44 - 30), Vector2(w, 30 + lines.size() * 44))
	if m.opts.get("training", false):
		box.position.y = 240
	_panel(box, Color(0.06, 0.07, 0.1, 0.82 * a), 12)
	_text(box.position + Vector2(14, 22), "Your kit", 14, Color(GOLD, a), big)
	for i in lines.size():
		var l: Array = lines[i]
		var y := box.position.y + 34 + i * 44
		var kw := big.get_string_size(l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var ks := StyleBoxFlat.new(); ks.bg_color = Color(l[3], a); ks.set_corner_radius_all(5)
		c.draw_style_box(ks, Rect2(Vector2(box.position.x + 14, y), Vector2(kw + 12, 20)))
		c.draw_string(big, Vector2(box.position.x + 20, y + 15), l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.07, 0.06, 0.08, a))
		_text(Vector2(box.position.x + 34 + kw, y + 15), l[1], 14, Color(INK, a))
		c.draw_string(body, Vector2(box.position.x + 14, y + 36), String(l[2]), HORIZONTAL_ALIGNMENT_LEFT, w - 28, 12, Color(MUTED, a))

func _draw_prompt(sz: Vector2, p: Hunter) -> void:
	var it := m.interact
	var y := sz.y - 128.0
	if not it.is_empty():
		var prog := 0.0
		match it["kind"]:
			"revive": prog = it["ent"].revive
			"catch": prog = it["ent"].catch_prog
			"chest": prog = it["chest"]["prog"]
		var s: String = it["label"]
		var w := body.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		_panel(Rect2(Vector2(sz.x * 0.5 - w * 0.5 - 16, y - 22), Vector2(w + 32, 32)))
		_ctext(Vector2(sz.x * 0.5, y), s, 16, it.get("col", GOLD))
		if prog > 0.0:
			_bar(Rect2(Vector2(sz.x * 0.5 - w * 0.5 - 16, y + 12), Vector2(w + 32, 4)), prog, GOLD)
	if p.extract_prog > 0.0:
		_ctext(Vector2(sz.x * 0.5, sz.y * 0.36), "Extracting...", 26, Color("8fe3c8"), big)
		_bar(Rect2(Vector2(sz.x * 0.5 - 120, sz.y * 0.36 + 12), Vector2(240, 8)), p.extract_prog, Color("8fe3c8"))

func _draw_crosshair(p: Hunter) -> void:
	var mp := c.get_local_mouse_position()
	var col := INK
	var gap := 6.0 + (p.recoil * 6.0) + p.bloom * 9.0
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		c.draw_line(mp + d * gap, mp + d * (gap + 7.0), Color(0, 0, 0, 0.6), 4.0)
		c.draw_line(mp + d * gap, mp + d * (gap + 7.0), col, 2.0)
	c.draw_circle(mp, 1.6, col)
	if p.reload_t > 0.0:
		_arc(mp, 18, 1.0 - p.reload_t / float(p.wpn["reload"]), Color("ffe7a8"), 3.0)
	else:
		# ammo left, as a thin ring that empties as you fire
		var af := float(p.ammo) / maxf(1.0, float(p.wpn["mag"]))
		c.draw_arc(mp, 22, PI * 0.62, PI * 0.62 + PI * 0.76, 24, Color(0, 0, 0, 0.35), 3.0, true)
		c.draw_arc(mp, 22, PI * 0.62, PI * 0.62 + PI * 0.76 * af, 24, Color(1, 1, 1, 0.75) if af > 0.25 else Color(HP_LOW, 0.9), 2.0, true)
	if hit_t > 0.0:
		var hc := Color("ffd23f") if hit_crit else Color.WHITE
		if hit_armor: hc = ARMOR_COL if not hit_crit else Color("cfefff")
		var s := 10.0 + (1.0 - hit_t / 0.14) * 4.0
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			c.draw_line(mp + d * 5.0, mp + d * s, hc, 2.5)

func _draw_downed(sz: Vector2, p: Hunter) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.3, 0.02, 0.02, 0.18))
	_ctext(Vector2(sz.x * 0.5, sz.y * 0.32), "You're down", 34, BAD, big)
	var who := "Your kin or a teammate can pick you up."
	if p.kin and p.kin.state == "fainted":
		who = "Your kin is out cold. Only a teammate can help."
	_ctext(Vector2(sz.x * 0.5, sz.y * 0.32 + 28), who, 16, INK)
	_bar(Rect2(Vector2(sz.x * 0.5 - 140, sz.y * 0.32 + 44), Vector2(280, 8)), p.down_hp / Data.MATCH["down_hp"], BAD)
	if p.revive > 0.0:
		_bar(Rect2(Vector2(sz.x * 0.5 - 140, sz.y * 0.32 + 58), Vector2(280, 8)), p.revive, GOOD)

func _draw_scores(sz: Vector2) -> void:
	var r := Rect2(Vector2(sz.x * 0.5 - 300, sz.y * 0.18), Vector2(600, 40 + m.hunters.size() * 28))
	_panel(r, Color(0.05, 0.06, 0.09, 0.9), 14)
	_text(r.position + Vector2(20, 30), "Hunter", 14, MUTED); _text(r.position + Vector2(260, 30), "Kin", 14, MUTED)
	_text(r.position + Vector2(380, 30), "Knocks", 14, MUTED); _text(r.position + Vector2(450, 30), "Damage", 14, MUTED); _text(r.position + Vector2(530, 30), "State", 14, MUTED)
	var hs := m.hunters.duplicate()
	hs.sort_custom(func(a, b): return a.team < b.team)
	var y := r.position.y + 58
	for h in hs:
		var tc: Color = Data.TEAM_COLORS[h.team % 6]
		c.draw_rect(Rect2(Vector2(r.position.x + 12, y - 14), Vector2(4, 18)), tc)
		_text(Vector2(r.position.x + 22, y), "%s (%s)" % [h.pname, Data.CLASSES[h.cls]["name"]], 15, INK if h != m.player else GOLD)
		if h.kin: _text(Vector2(r.position.x + 260, y), Data.KIN[h.kin.species]["name"], 14, Data.KIN[h.kin.species]["color"])
		_text(Vector2(r.position.x + 392, y), str(h.knocks), 15)
		_text(Vector2(r.position.x + 456, y), str(int(h.dmg_done)), 15)
		var st := "Out" if h.out else ("Extracted" if h.extracted else ("Down" if h.downed else "Alive"))
		_text(Vector2(r.position.x + 530, y), st, 14, BAD if h.out else (Color("8fe3c8") if h.extracted else INK))
		y += 28

func _draw_tip(sz: Vector2, t: Dictionary) -> void:
	var a := clampf(minf(t["t"] * 4.0, (7.0 - t["t"]) * 2.0), 0.0, 1.0)
	var text: String = t["text"]
	var w := minf(560.0, body.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 40.0)
	var lines := body.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, w - 40.0, 16)
	var r := Rect2(Vector2(sz.x * 0.5 - w * 0.5, 84), Vector2(w, lines.y + 34))
	_panel(r, Color(0.98, 0.95, 0.88, 0.94 * a), 12)
	c.draw_multiline_string(body, r.position + Vector2(20, 28), text, HORIZONTAL_ALIGNMENT_LEFT, w - 40.0, 16, -1, Color(0.1, 0.09, 0.12, a))

var head_hp := 1.0

## Health and stamina (dash charges) right above your hunter, where your eyes already are.
func _draw_overhead(p: Hunter) -> void:
	var cam := m.cam
	var at := p.position + Vector3(0, 2.7 * float(p.cdat["scale"]), 0)
	if cam.is_position_behind(at) or p.downed:
		return
	var sp := cam.unproject_position(at)
	var w := 70.0
	var frac := clampf(p.hp / p.max_hp, 0.0, 1.0)
	head_hp = lerpf(head_hp, frac, 0.08)
	if p.armor > 0.5:
		_seg_bar(Rect2(sp + Vector2(-w * 0.5, -5), Vector2(w, 3)), p.armor, p.max_armor, p.armor / maxf(1.0, p.max_armor), ARMOR_COL, 25.0)
	_seg_bar(Rect2(sp + Vector2(-w * 0.5, 0), Vector2(w, 7)), p.hp, p.max_hp, head_hp, GOOD if frac > 0.35 else BAD, 25.0)
	if p.shield > 0.0:
		c.draw_rect(Rect2(sp + Vector2(-w * 0.5, 0), Vector2(w * clampf(p.shield / 120.0, 0.0, 1.0), 7)), Color(0.85, 0.93, 1.0, 0.5))
	# stamina: one segment per dash, the next one filling as it recharges
	var n := int(p.max_dashes())
	var gap := 3.0
	var segw := (w - gap * (n - 1)) / n
	for i in n:
		var r := Rect2(sp + Vector2(-w * 0.5 + i * (segw + gap), 12), Vector2(segw, 5))
		c.draw_rect(r.grow(1.5), Color(0.04, 0.04, 0.06, 0.75))
		var fill := clampf(p.dashes - i, 0.0, 1.0)
		var col := Color("bfe6ff") if fill >= 1.0 else Color("5f7f99")
		c.draw_rect(Rect2(r.position, Vector2(segw * fill, 5)), col)
	if p.reload_t > 0.0:
		var rf := 1.0 - p.reload_t / float(p.wpn["reload"])
		c.draw_rect(Rect2(sp + Vector2(-w * 0.5, 21), Vector2(w * rf, 2)), Color("ffe7a8"))
