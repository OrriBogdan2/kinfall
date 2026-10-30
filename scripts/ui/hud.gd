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
				# authored maps: grabbable rims pale, sheer cliffs dark, so the map shows where you can climb
				if w.sheer.has(i): col = Color("6a6488")
				elif w.lip.has(i): col = Color("e6d6ae")
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
var hover_spots: Array = []     # [rect, id] for things on the HUD you can point at
var hover_id := ""
var hover_t := 0.0

func _draw_all() -> void:
	var sz := c.size
	var p := m.player
	hover_spots.clear()
	_draw_world_labels()
	_draw_bubbles()
	_draw_pings(sz)
	if hurt_t > 0.0:
		var a := hurt_t * 0.9
		for i in 6:
			var inset := i * 14.0
			c.draw_rect(Rect2(Vector2(inset, inset), sz - Vector2(inset, inset) * 2.0), Color(0.8, 0.1, 0.08, a * (0.12 - i * 0.018)), false, 14.0)
	if p and not p.out and not p.grounded and p.over_void():
		# [footage] the screen washes purple as you sink below island level, deeper the further down
		var depth := p.last_gy - p.pos.y
		if depth > 0.0:
			abyss_a = lerpf(abyss_a, clampf(depth / 8.0, 0.0, 1.0) * 0.55, 0.15)
	else:
		abyss_a = lerpf(abyss_a, 0.0, 0.15)
	if abyss_a > 0.005:
		c.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.55, 0.1, 0.55, abyss_a))
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
		_draw_glider_heat(p)
	if p:
		_draw_hurt_dirs(sz)
		if not p.out and not p.extracted:
			_draw_vitals(sz, p)
			_draw_abilities(sz, p)
			_draw_weapon(sz, p)
			_draw_kin_card(sz, p)
			_draw_squad(sz, p)
			_draw_perks(sz, p)
			_draw_perk_offer(sz)
		if not p.riding:
			_draw_kit(sz, p)
		else:
			_draw_ship_prompt(sz)
		if not p.riding:
			_draw_prompt(sz, p)
			_draw_crosshair(p)
		if p.downed:
			_draw_downed(sz, p)
		elif p.out and not p.gone and not m.result.get("ending", false):
			_draw_dead(sz, p)
	_draw_small_toasts(sz)
	for i in toasts.size():
		var t: Dictionary = toasts[i]
		var a := clampf(1.8 - t["t"], 0.0, 1.0)
		_ctext(Vector2(sz.x * 0.5, sz.y * 0.3 + i * 26 - t["t"] * 10.0), t["text"], 20, Color(t["col"], a), big)
	if tips.size() > 0:
		_draw_tip(sz, tips[0])
	if Input.is_action_pressed("scores"):
		_draw_scores(sz)
	if p and not p.out and not p.extracted:
		_draw_hover_tip(sz, p)
		if hover_id == "":
			_draw_world_hover(sz, p)

func _draw_world_labels() -> void:
	var cam := m.cam
	# deathboxes and revive beacons
	for b in m.boxes:
		if cam.is_position_behind(b["pos"]):
			continue
		var o: Hunter = b["owner"]
		var bp := cam.unproject_position(b["pos"] + Vector3(0, 1.9, 0))
		var soul := Life.soul_here(m, b)
		var ally: bool = m.player != null and o.team == m.player.team
		if soul and ally and o != m.player:
			_ctext(bp, "%s  ·  %ds" % [o.pname, int(ceil(float(b["soul_until"]) - m.time))], 13, Color("9ee2a0"), big)
		elif not b["empty"] and m.player and m.player.flat_dist(b["pos"]) < 14.0:
			_ctext(bp, "%s's box" % o.pname if o != m.player else "Your box", 12, Life.box_color(b), big)
	# whoever has your kin: marked over their head, or an arrow at the screen edge
	var th: Hunter = m.kin_thief() if m.player and not m.player.out else null
	if th:
		var sz := c.size
		var tp := cam.unproject_position(th.position + Vector3(0, 2.8, 0))
		var on := not cam.is_position_behind(th.position) and Rect2(Vector2(30, 30), sz - Vector2(60, 60)).has_point(tp)
		if on:
			_ctext(tp, "Has your kin", 15, GOLD, big)
			c.draw_colored_polygon(PackedVector2Array([tp + Vector2(-8, 6), tp + Vector2(8, 6), tp + Vector2(0, 16)]), GOLD)
		else:
			var ctr := sz * 0.5
			var d := (tp - ctr).normalized() if not cam.is_position_behind(th.position) else (ctr - tp).normalized()
			var edge := ctr + d * minf(sz.x, sz.y) * 0.44
			var perp := Vector2(-d.y, d.x)
			c.draw_colored_polygon(PackedVector2Array([edge + d * 18.0, edge - d * 6.0 + perp * 11.0, edge - d * 6.0 - perp * 11.0]), GOLD)
			_ctext(edge - d * 26.0, "%dm" % int(m.player.flat_dist(th)), 13, GOLD, big)
	# the tutorial's marker: a pin over what to go to, or an arrow at the screen edge, with the distance
	if m.opts.get("tutorial", false) and m.tut_target != Vector3.INF and m.player and not m.player.out:
		_draw_waypoint(m.tut_target, m.tut_label, Color("8fe3c8"))
	for bc in m.beacons:
		if bc["used"] or cam.is_position_behind(bc["pos"]):
			continue
		if m.player and m.player.flat_dist(bc["pos"]) > 26.0 and float(bc["prog"]) <= 0.0:
			continue
		var bp := cam.unproject_position(bc["pos"] + Vector3(0, 3.2, 0))
		_ctext(bp, "Revive beacon" + ("  ·  contested" if bc["contested"] else ""), 12, Color("8fffc0"), big)
		if float(bc["prog"]) > 0.0:
			_bar(Rect2(bp + Vector2(-40, 6), Vector2(80, 5)), float(bc["prog"]), Color("8fffc0"))
	for h in m.hunters:
		if h == m.player or h.out or h.extracted or not h.model or not h.model.visible or h.unseen:
			continue
		var sp := cam.unproject_position(h.position + Vector3(0, 2.35, 0))
		if cam.is_position_behind(h.position):
			continue
		var tc: Color = Data.TEAM_COLORS[h.team % Data.TEAM_COLORS.size()]
		var ally: bool = m.player and h.team == m.player.team
		_ctext(sp + Vector2(0, -12), h.pname, 16, tc if not ally else GOOD, big)
		if h.downed:
			_bar(Rect2(sp + Vector2(-26, -2), Vector2(52, 5)), h.down_hp / Data.MATCH["down_hp"], BAD)
			_ctext(sp + Vector2(0, 14), "DOWN", 12, BAD, big)
			if h.revive > 0.0:
				_arc(sp + Vector2(0, 30), 10, h.revive, GOOD, 3.0)
		else:
			_vitals(sp + Vector2(0, 4), 64.0, h, (HP_LOW if not ally else GOOD) if h.hp < h.max_hp * 0.35 else (tc if not ally else GOOD), 0.0)
	for mb in m.mobs:
		if mb.dead or cam.is_position_behind(mb.position):
			continue
		var hy := 1.4
		if mb.mkind == "brute": hy = 2.4
		elif mb.mkind == "warden": hy = 3.4
		var sp := cam.unproject_position(mb.position + Vector3(0, hy, 0))
		if mb.stagger_t > 0.0:
			_ctext(sp + Vector2(0, -12), "STAGGERED", 18, Color("fff27a"), big)
		elif mb.stag_open > 0.0:
			var a := 0.75 + 0.25 * sin(m.time * 12.0)
			_ctext(sp + Vector2(0, -12), "STAGGERABLE", 17, Color(0.85, 0.6, 1.0, a), big)
		if mb.hp < mb.max_hp:
			var bw := 64.0 if mb.mkind in ["brute", "warden"] else 48.0
			_bar(Rect2(sp + Vector2(-bw * 0.5, 0), Vector2(bw, 6)), mb.hp / mb.max_hp, Color("e0b0ff") if mb.stagger_t > 0.0 else Color("ff8a6a"))
	# found weapons: name and rarity when you're close enough to care
	var pp: Vector3 = m.player.pos if m.player else cam.focus
	for wp in m.wpicks:
		var wpos: Vector3 = wp["pos"]
		if Vector2(wpos.x - pp.x, wpos.z - pp.z).length() > 7.0 or cam.is_position_behind(wpos):
			continue
		var r: Dictionary = Data.RARITY[int(wp["rar"])]
		var sp := cam.unproject_position(wpos + Vector3(0, 1.45, 0))
		_ctext(sp, String(Data.weapon_stats(String(wp["wid"]), int(wp["rar"]))["name"]), 16, r["color"], big)
	for k in m.kins:
		if k.dead or not k.visible or k.state == "shoulder" or cam.is_position_behind(k.position):
			continue
		var sp := cam.unproject_position(k.position + Vector3(0, 1.05, 0))
		if k.is_wild():
			if k.state == "dazed":
				_ctext(sp + Vector2(0, -8), "Dazed!  %s to catch" % Settings.key_cap("interact"), 17, GOLD, big)
				if k.catch_prog > 0.0:
					_arc(sp + Vector2(0, 10), 9, k.catch_prog, GOLD, 3.0)
			else:
				_ctext(sp + Vector2(0, -10), "Wild %s" % Data.KIN[k.species]["name"], 16, Color("bfe9ff"), big)
				_bar(Rect2(sp + Vector2(-24, -2), Vector2(48, 5)), k.hp / k.max_hp, Color("bfe9ff"))
		elif k.hp < k.max_hp and k.state != "fainted":
			_bar(Rect2(sp + Vector2(-22, 0), Vector2(44, 5)), k.hp / k.max_hp, Data.TEAM_COLORS[k.team % Data.TEAM_COLORS.size()] if k.owner_h != m.player else GOOD)

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
		var lines: Array = m.train_rows()
		var box := Rect2(Vector2(sz.x - 346, 16), Vector2(330, 34 + lines.size() * 24))
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
		if m.tut_id() == "extract" and m.player and m.player.extract_prog > 0.0:
			_panel(Rect2(Vector2(sz.x * 0.5 - 120, 84), Vector2(240, 30)), Color(0.06, 0.07, 0.1, 0.85), 8)
			_bar(Rect2(Vector2(sz.x * 0.5 - 104, 95), Vector2(208, 8)), clampf(m.player.extract_prog, 0.0, 1.0), Color("8fe3c8"))
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
	var y := 36.0
	for f in m.feed:
		var a := clampf(6.0 - f["t"], 0.0, 1.0)
		var s: String = f["text"]
		var w := body.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		_panel(Rect2(Vector2(sz.x - w - 34, y - 18), Vector2(w + 20, 26)), Color(0.06, 0.07, 0.1, 0.6 * a), 8)
		_text(Vector2(sz.x - w - 24, y), s, 14, Color(INK, a))
		y += 30

func _draw_minimap(sz: Vector2) -> void:
	var riding: bool = m.player != null and (m.player.riding or m.player.dropping)
	var s := 340.0 if riding else 210.0
	var r := Rect2(Vector2(16, 16), Vector2(s, s))
	_panel(r, Color(0.05, 0.06, 0.09, 0.78), 12)
	var w := m.world
	var inner := Rect2(r.position + Vector2(8, 8), r.size - Vector2(16, 16))
	# riding in or dropping: the whole map. On the ground: a close view that follows you.
	var view := Rect2(Vector2.ZERO, Vector2(w.w, w.h))
	if not riding and m.player:
		var R := 34.0
		view = Rect2(Vector2(m.player.pos.x, m.player.pos.z) - Vector2(R, R), Vector2(R, R) * 2.0)
	var k := inner.size.x / view.size.x
	var to_map := func(p3: Vector3) -> Vector2:
		return inner.position + (Vector2(p3.x, p3.z) - view.position) * k
	var on_map := func(v: Vector2, pad := 0.0) -> bool:
		return inner.grow(-pad).has_point(v)
	var tex_view := view.intersection(Rect2(Vector2.ZERO, Vector2(w.w, w.h)))
	if tex_view.size.x > 0.0 and tex_view.size.y > 0.0:
		var dest := Rect2(inner.position + (tex_view.position - view.position) * k, tex_view.size * k)
		c.draw_texture_rect_region(minimap, dest, tex_view)
	_draw_map_labels(w, inner, view, k, riding)
	# your view cone, faintly
	if m.player and not riding:
		var pp: Vector2 = to_map.call(m.player.pos)
		var ad: Vector2 = m.player.aim_dir()
		var a0 := atan2(ad.y, ad.x)
		var pts := PackedVector2Array([pp])
		for i in 13:
			var a := a0 - 0.93 + 1.86 * i / 12.0
			var e := pp + Vector2(cos(a), sin(a)) * Match.VIEW_RANGE * k
			pts.append(Vector2(clampf(e.x, inner.position.x, inner.end.x), clampf(e.y, inner.position.y, inner.end.y)))
		c.draw_colored_polygon(pts, Color(1, 1, 1, 0.07))
	for p in m.portals:
		var pv: Vector2 = to_map.call(p["pos"])
		if not on_map.call(pv, 4.0):
			if p["open"]: _edge_arrow(inner, inner.get_center(), pv, Color("8fe3c8"))
			continue
		var col := Color("8fe3c8") if p["open"] else Color(0.6, 0.65, 0.7, 0.6)
		c.draw_arc(pv, 5, 0, TAU, 16, col, 2.0, true)
	if not m.ship.is_empty() and not m.ship.get("gone", false):
		var sa: Vector2 = to_map.call(m.ship["a"]); var sb: Vector2 = to_map.call(m.ship["b"])
		c.draw_line(sa, sb, Color(1, 1, 1, 0.35), 2.0, true)
		c.draw_circle(to_map.call(m.ship_pos()), 5.0, GOLD)
	if m.opts.get("tutorial", false) and m.tut_target != Vector3.INF:
		var tv: Vector2 = to_map.call(m.tut_target)
		if on_map.call(tv, 4.0): c.draw_arc(tv, 6.0, 0, TAU, 16, Color("8fe3c8"), 2.5, true)
		else: _edge_arrow(inner, inner.get_center(), tv, Color("8fe3c8"))
	for pg in m.pings:
		var pv: Vector2 = to_map.call(pg["pos"])
		if on_map.call(pv): c.draw_circle(pv, 4.0, pg["col"])
		else: _edge_arrow(inner, inner.get_center(), pv, pg["col"])
	# sound pings: rings that ripple out where you heard gunfire or a blast you can't see
	for sp in m.sound_pings:
		var age := m.time - float(sp["t"])
		if age > 1.6: continue
		var pv: Vector2 = to_map.call(sp["pos"])
		var boom: bool = sp["kind"] == "boom"
		var col := Color("ff9a5a") if boom else Color("ff5a5a")
		var a := clampf(1.0 - age / 1.6, 0.0, 1.0)
		if on_map.call(pv):
			c.draw_arc(pv, 3.0 + age * (12.0 if boom else 8.0), 0, TAU, 20, Color(col, a), 2.0, true)
			c.draw_circle(pv, 2.5, Color(col, a))
		else:
			_edge_arrow(inner, inner.get_center(), pv, Color(col, a))
	# your squad, with an arrow for anyone off the edge
	for h in m.hunters:
		if h.out or h.extracted or m.player == null or h.team != m.player.team:
			continue
		var pv: Vector2 = to_map.call(h.pos)
		var col := INK if h == m.player else (BAD if h.downed else GOOD)
		if not on_map.call(pv, 3.0):
			_edge_arrow(inner, inner.get_center(), pv, col)
			continue
		if h == m.player:
			var d: Vector2 = h.aim_dir()
			var side := Vector2(-d.y, d.x)
			c.draw_colored_polygon(PackedVector2Array([pv + d * 8.0, pv - d * 4.0 + side * 5.0, pv - d * 2.0, pv - d * 4.0 - side * 5.0]), col)
		else:
			c.draw_circle(pv, 4.5, Color(0, 0, 0, 0.6))
			c.draw_circle(pv, 3.5, col)
			_ctext(pv + Vector2(0, -7), h.pname.substr(0, 1), 11, col, big)

## A world marker: a bobbing pin and label over the spot, or (when it's off screen or behind the
## camera) a big arrow at the screen edge pointing the way. Both show how far it is.
func _draw_waypoint(at: Vector3, label: String, col: Color) -> void:
	var cam := m.cam
	var sz := c.size
	var dist := int(round(Vector2(at.x - m.player.pos.x, at.z - m.player.pos.z).length()))
	var bob := sin(Time.get_ticks_msec() / 1000.0 * 4.0) * 4.0
	var tp := cam.unproject_position(at + Vector3(0, 2.6, 0))
	var behind := cam.is_position_behind(at)
	var on := not behind and Rect2(Vector2(40, 110), sz - Vector2(80, 230)).has_point(tp)
	if on:
		var p := tp + Vector2(0, bob)
		c.draw_circle(p, 13.0, Color(0, 0, 0, 0.45))
		c.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -11), p + Vector2(9, 0), p + Vector2(0, 11), p + Vector2(-9, 0)]), col)
		c.draw_colored_polygon(PackedVector2Array([p + Vector2(-7, 15), p + Vector2(7, 15), p + Vector2(0, 26)]), col)
		_ctext(p + Vector2(0, 44), "%s  ·  %dm" % [label, dist], 15, col, big)
		# a ring on the ground under it
		if not behind:
			var gp := cam.unproject_position(at + Vector3(0, 0.05, 0))
			c.draw_arc(gp, 16.0 + bob, 0, TAU, 28, Color(col, 0.7), 2.5, true)
	else:
		var ctr := sz * 0.5
		var d := (tp - ctr).normalized() if not behind else (ctr - tp).normalized()
		if d.length() < 0.1: d = Vector2.UP
		# kept inside the play area: under the tutorial banner, above the ability bar
		var ctr2 := Vector2(sz.x * 0.5, sz.y * 0.47)
		ctr = ctr2
		var hx := sz.x * 0.5 - 70.0; var hy := sz.y * 0.5 - 150.0
		var t := minf(hx / maxf(0.001, absf(d.x)), hy / maxf(0.001, absf(d.y)))
		var edge := ctr + d * t + d * bob * 0.5
		var perp := Vector2(-d.y, d.x)
		c.draw_colored_polygon(PackedVector2Array([edge + d * 24.0, edge - d * 8.0 + perp * 15.0, edge - d * 8.0 - perp * 15.0]), Color(0, 0, 0, 0.5))
		c.draw_colored_polygon(PackedVector2Array([edge + d * 20.0, edge - d * 6.0 + perp * 12.0, edge - d * 6.0 - perp * 12.0]), col)
		_ctext(edge - d * 34.0, "%s  %dm" % [label, dist], 15, col, big)

## A small arrow on the minimap's edge pointing at something off the map.
func _edge_arrow(inner: Rect2, from: Vector2, to: Vector2, col: Color) -> void:
	var d := (to - from)
	if d.length() < 0.1: return
	d = d.normalized()
	var hx := inner.size.x * 0.5 - 6.0; var hy := inner.size.y * 0.5 - 6.0
	var t := minf(hx / maxf(0.001, absf(d.x)), hy / maxf(0.001, absf(d.y)))
	var p := from + d * t
	var side := Vector2(-d.y, d.x)
	c.draw_colored_polygon(PackedVector2Array([p + d * 5.0, p - d * 3.0 + side * 4.0, p - d * 3.0 - side * 4.0]), col)

## On narrow windows the ability bar takes the whole bottom row and the player card sits above it.
func _narrow(sz: Vector2) -> bool:
	return sz.x < 1080.0

## ------------------------------------------------------------------ combat HUD
## Bottom centre: armor and health over the ability row. Bottom left: your kin. Bottom right: your
## weapon and what you're carrying. Left: your squad. Hits on you show which way they came from.
const ARMOR_COL := Color("dfe9f7")      # armor: silver-white, segmented, sits above health
const STAMINA_COL := Color("ffd66a")    # dash charges: yellow pips under the bars
const HP_COL := Color("8fe0a0")
const HP_LOW := Color("ff6a5a")
var armor_lerp := 1.0
var ready_was := {}        # slot id -> was it ready last frame, for the "ready" flash
var ready_flash := {}      # slot id -> time left on its flash
var slot_fx := {}          # slot id -> {kind: "cast"|"deny", t}: a pop when a press lands, a red shake when it can't

## A press on an ability slot: "cast" pops it, "deny" (on cooldown, not ready) shakes it red.
func ability_feedback(id: String, kind: String) -> void:
	slot_fx[id] = {"kind": kind, "t": 0.0}
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
## Armor over health, the same everywhere: a thin silver armor bar (empty outline when broken, so
## you know it comes back), a thick health bar in 25-point chunks with a pale trail for damage just
## taken, and little shield and cross marks so it's clear which is which.
func _vitals(sp: Vector2, w: float, h: Hunter, hp_col: Color, trail: float, numbers := false) -> void:
	if not sp.is_finite():
		return
	var x0 := sp.x - w * 0.5
	if h.max_armor > 0.5:
		var ar := Rect2(Vector2(x0, sp.y - 9), Vector2(w, 4))
		_seg_bar(ar, h.armor, h.max_armor, 0.0, ARMOR_COL, 100.0)
		var sc := Vector2(x0 - 9, sp.y - 7)
		var shp := PackedVector2Array([sc + Vector2(-4, -4), sc + Vector2(4, -4), sc + Vector2(4, 0), sc + Vector2(0, 4.5), sc + Vector2(-4, 0)])
		c.draw_colored_polygon(shp, Color(0.03, 0.03, 0.05, 0.85))
		c.draw_polyline(shp + PackedVector2Array([shp[0]]), Color(ARMOR_COL, 1.0 if h.armor > 0.5 else 0.35), 1.5)
	var hr := Rect2(Vector2(x0, sp.y), Vector2(w, 9))
	_seg_bar(hr, h.hp, h.max_hp, trail, hp_col, 25.0)
	if h.shield > 0.0:
		c.draw_rect(Rect2(hr.position, Vector2(w * clampf(h.shield / 120.0, 0.0, 1.0), 9)), Color(0.85, 0.93, 1.0, 0.5))
	var pc := Vector2(x0 - 9, sp.y + 4.5)
	c.draw_circle(pc, 5.5, Color(0.03, 0.03, 0.05, 0.85))
	c.draw_rect(Rect2(pc - Vector2(3.5, 1), Vector2(7, 2)), hp_col)
	c.draw_rect(Rect2(pc - Vector2(1, 3.5), Vector2(2, 7)), hp_col)
	if numbers:
		_text(Vector2(hr.end.x + 5, sp.y + 9), str(int(ceil(h.hp))), 12, Color(1, 1, 1, 0.9), big)

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
	var sfx_d: Dictionary = slot_fx.get(id, {})
	var deny := 0.0
	var pop := 0.0
	if not sfx_d.is_empty():
		var ft := float(sfx_d["t"])
		if sfx_d["kind"] == "deny":
			deny = clampf(1.0 - ft / 0.35, 0.0, 1.0)
			rect.position.x += sin(ft * 70.0) * 5.0 * deny
		else:
			pop = clampf(1.0 - ft / 0.3, 0.0, 1.0)
			rect = rect.grow(-rect.size.x * 0.08 * sin(pop * PI))
	var ctr := rect.get_center()
	hover_spots.append([rect, id])
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
	if deny > 0.0:
		_rounded(rect, Color(0.9, 0.15, 0.1, 0.22 * deny), 12, Color(1.0, 0.35, 0.3, deny), 3)
	if pop > 0.0:
		_rounded(rect.grow((1.0 - pop) * 14.0), Color(1, 1, 1, 0.12 * pop), 14, Color(col.lerp(Color.WHITE, 0.5), pop), 3)
	var fl := float(ready_flash.get(id, 0.0))
	if fl > 0.0:
		var k := 1.0 - fl / 0.35
		_rounded(rect.grow(2.0 + k * 8.0), Color(0, 0, 0, 0), 14, Color(col, 1.0 - k), 3)

func _hud_tick(delta: float) -> void:
	for id in slot_fx.keys():
		slot_fx[id]["t"] = float(slot_fx[id]["t"]) + delta
		if float(slot_fx[id]["t"]) > 0.4: slot_fx.erase(id)
	for id in ready_flash.keys():
		ready_flash[id] = float(ready_flash[id]) - delta
		if float(ready_flash[id]) <= 0.0: ready_flash.erase(id)
	for h in hurt_dirs.duplicate():
		h["t"] = float(h["t"]) + delta
		if float(h["t"]) > 1.2: hurt_dirs.erase(h)
	for t in small_toasts.duplicate():
		t["t"] = float(t["t"]) + delta
		if float(t["t"]) > 1.4: small_toasts.erase(t)

## Health and armor over the ability row, with your class badge, lives and glider cloth.
func _draw_vitals(sz: Vector2, p: Hunter) -> void:
	var w := 380.0
	var x0 := sz.x * 0.5 - w * 0.5
	var y0 := sz.y - 150.0
	var hc: Color = p.accent()
	# class badge
	var bc := Vector2(x0 - 30, y0 + 16)
	c.draw_circle(bc, 24, Color(0.04, 0.04, 0.06, 0.92))
	c.draw_arc(bc, 24, 0, TAU, 40, hc, 2.5, true)
	_ctext(bc + Vector2(0, 9), String(p.cdat["name"]).substr(0, 1), 24, hc, big)
	if p.lives < 50 and p.lives > 1:
		for i in p.lives:
			var hp_c := bc + Vector2((i - (p.lives - 1) * 0.5) * 11.0, 32)
			c.draw_circle(hp_c, 4.0, Color("ff7a8a"))
	# armor over health
	var frac := clampf(p.hp / p.max_hp, 0.0, 1.0)
	bar_lerp = move_toward(bar_lerp, frac, get_process_delta_time() * (0.35 if bar_lerp > frac else 4.0))
	var af := clampf(p.armor / maxf(1.0, p.max_armor), 0.0, 1.0)
	armor_lerp = move_toward(armor_lerp, af, get_process_delta_time() * (0.5 if armor_lerp > af else 4.0))
	hover_spots.append([Rect2(Vector2(x0 - 56, y0 - 10), Vector2(w + 110, 48)), "vitals"])
	_seg_bar(Rect2(Vector2(x0, y0), Vector2(w, 8)), p.armor, p.max_armor, armor_lerp, ARMOR_COL, 100.0)
	var low := frac < 0.35
	var hcol := HP_LOW.lerp(Color.WHITE, 0.25 * (0.5 + 0.5 * sin(m.time * 9.0))) if low else HP_COL
	_seg_bar(Rect2(Vector2(x0, y0 + 14), Vector2(w, 16)), p.hp, p.max_hp, bar_lerp, hcol, 25.0)
	if p.shield > 0.0:
		c.draw_rect(Rect2(Vector2(x0, y0 + 14), Vector2(w * clampf(p.shield / 120.0, 0.0, 1.0), 16)), Color(0.85, 0.93, 1.0, 0.45))
	var hp_txt := str(int(ceil(p.hp)))
	_text(Vector2(x0 + w + 10, y0 + 30), hp_txt, 24, INK if not low else HP_LOW, big)
	if p.armor > 0.5:
		_text(Vector2(x0 + w + 10, y0 + 8), str(int(ceil(p.armor))), 13, ARMOR_COL, big)
	# hidden in the grass
	var grass := m.world.in_bush(p.pos.x, p.pos.z)
	if grass or p.crouch:
		var hid := p.reveal_t <= 0.0
		var txt := ("HIDDEN" if hid else "SPOTTED") if grass else ("CROUCHED" if hid else "SPOTTED")
		var fg: Color = (Color("8fe0a0") if grass else Color("c9d2e0")) if hid else HP_LOW
		var tw := big.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var hr := Rect2(Vector2(sz.x * 0.5 - tw * 0.5 - 12, y0 - 46), Vector2(tw + 24, 20))
		_rounded(hr, (Color(0.05, 0.12, 0.06, 0.85) if grass else Color(0.08, 0.09, 0.12, 0.85)) if hid else Color(0.25, 0.06, 0.05, 0.85), 10)
		_text(hr.position + Vector2(12, 15), txt, 13, fg, big)
	# glider heat is shown as a ring beside the glider itself (see _draw_glider_heat)

## Glider heat as a ring floating beside the glider, as in Supervive: it fills as you glide (faster
## when you're hit or lifting out of the abyss), drains on the ground, and pulses red when
## overheated, when the next hit will spike you.
func _draw_glider_heat(p: Hunter) -> void:
	if p.dropping or p.downed or p.riding:
		return
	var heat := 1.0 - p.glide_fuel
	if not p.gliding and heat < 0.01:
		return
	var at := p.position + Vector3(0, 2.25 * float(p.cdat["scale"]), 0)
	if m.cam.is_position_behind(at):
		return
	var cpt := m.cam.unproject_position(at) + Vector2(58, -6)
	var hot := heat >= 0.999
	var gcol := Color("ffd27a").lerp(Color("ff5a3a"), clampf(heat * 1.2 - 0.2, 0.0, 1.0))
	if hot: gcol = gcol.lerp(Color.WHITE, 0.35 + 0.35 * sin(m.time * 14.0))
	var a := 1.0 if p.gliding else 0.6
	c.draw_circle(cpt, 15.0, Color(0.03, 0.03, 0.05, 0.75 * a))
	c.draw_arc(cpt, 11.0, 0.0, TAU, 32, Color(1, 1, 1, 0.14 * a), 4.0, true)
	if heat > 0.005:
		c.draw_arc(cpt, 11.0, -PI * 0.5, -PI * 0.5 + TAU * heat, 40, Color(gcol, a), 4.0, true)
	# a little wing in the middle
	var wcol := Color(gcol if hot else Color(1, 1, 1, 0.8), a)
	c.draw_polyline(PackedVector2Array([cpt + Vector2(-6, 2), cpt + Vector2(0, -3), cpt + Vector2(6, 2)]), wcol, 2.0, true)
	if hot:
		c.draw_arc(cpt, 17.0 + 2.0 * sin(m.time * 14.0), 0.0, TAU, 32, Color(1.0, 0.3, 0.2, 0.6), 2.0, true)

## The ability row: kin throw, the active kin's two abilities, your weapon's utility, the bond
## ultimate in the middle, your dodge, tonics, and gear actives.
func _draw_abilities(sz: Vector2, p: Hunter) -> void:
	var s := 60.0
	var gap := 12.0
	var us := 72.0
	var k: Kin = p.kin
	var gear_n := 0
	for gi in 2:
		if not (p.gear[gi] as Dictionary).is_empty() and Gear.active(String(p.gear[gi]["id"])): gear_n += 1
	var util: AbilityDef = p.runner.def_of("utility") if p.runner else null
	var has_sec := util != null
	var n_small := (3 if k else 0) + (1 if has_sec else 0) + 2
	var total := n_small * s + us + n_small * gap + gear_n * (48.0 + 8.0) + (8.0 if gear_n > 0 else 0.0)
	var x := sz.x * 0.5 - total * 0.5
	var y := sz.y - 88.0
	if k:
		var kc: Color = Data.KIN[k.species]["color"]
		var out_now: bool = k.state in ["active", "flying", "returning"]
		var can_throw: bool = (k.state == "shoulder" and k.throw_cd <= 0.0) or out_now
		_ab_slot("throw", Rect2(Vector2(x, y), Vector2(s, s)), "recall" if out_now else "throw", Settings.key_cap("throw"), kc, k.throw_cd / 1.0 if k.throw_cd > 0.0 else 0.0, k.throw_cd, can_throw, -1, 0, "Recall" if out_now else "")
		x += s + gap
		for slot in ["k1", "k2"]:
			var kd: AbilityDef = k.runner.def_of(slot)
			var act := "signature" if slot == "k1" else "kin_skill"
			if kd:
				var rdy: bool = k.runner.is_ready(slot) and k.ready_to_fight() and k.state != "fused"
				_ab_slot(slot, Rect2(Vector2(x, y), Vector2(s, s)), kd.icon, Settings.key_cap(act), kd.color, k.runner.cd_frac(slot), k.runner.cd_left(slot) if not k.runner.is_ready(slot) else 0.0, rdy)
				if not k.ready_to_fight():
					_rounded(Rect2(Vector2(x, y), Vector2(s, s)), Color(0, 0, 0, 0.45), 12)
			x += s + gap
	# right click: the weapon's utility
	if util:
		var sr := Rect2(Vector2(x, y), Vector2(s, s))
		_ab_slot("sec", sr, util.icon, Settings.key_cap("secondary"), util.color, p.runner.cd_frac("utility"), p.runner.cd_left("utility") if not p.runner.is_ready("utility") else 0.0, p.runner.is_ready("utility"), p.runner.charges("utility") if util.charges > 1 else -1, util.charges if util.charges > 1 else 0)
		x += s + gap
	# the bond ultimate: a heart-ring that fills as you and your kin fight together
	var ud := Ultimate.def_for(k) if k else null
	var ur := Rect2(Vector2(x, y - (us - s)), Vector2(us, us))
	var ready_r := Ultimate.can_cast(p)
	var ucol: Color = ud.color if ud else GOLD
	_ab_slot("r", ur, ud.id if ud else "bond", Settings.key_cap("ultimate"), ucol, 0.0, 0.0, ready_r)
	if p.ult < 1.0:
		c.draw_arc(ur.get_center(), us * 0.5 + 4.0, -PI / 2, -PI / 2 + TAU * p.ult, 48, ucol, 3.0, true)
		_ctext(ur.get_center() + Vector2(0, us * 0.5 - 12), "%d%%" % int(p.ult * 100.0), 12, Color(ucol, 0.9), big)
	else:
		var pulse := 0.5 + 0.5 * sin(m.time * 6.0)
		_rounded(ur.grow(3.0 + pulse * 3.0), Color(0, 0, 0, 0), 15, Color(ucol, 0.35 + pulse * 0.4), 2)
	_ctext(Vector2(ur.get_center().x, ur.position.y - 8), "BOND", 11, Color(ucol, 0.85), big)
	if not p.fuse.is_empty():
		var fd: UltimateDef = p.fuse["def"]
		_bar(Rect2(Vector2(ur.position.x, ur.end.y + 12), Vector2(us, 4)), clampf(float(p.fuse["t"]) / fd.time, 0.0, 1.0), fd.color)
	elif k and not k.giant.is_empty():
		var gd: UltimateDef = k.giant["def"]
		_bar(Rect2(Vector2(ur.position.x, ur.end.y + 12), Vector2(us, 4)), clampf(float(k.giant["t"]) / gd.time, 0.0, 1.0), gd.color)
	x += us + gap
	var dmax := p.max_dashes()
	var dcd := (1.0 - fposmod(p.dashes, 1.0)) if p.dashes < dmax else 0.0
	_ab_slot("dash", Rect2(Vector2(x, y), Vector2(s, s)), "dash", Settings.key_cap("dash"), Color("bfe6ff"), dcd if p.dashes < 1.0 else 0.0, (1.0 - fposmod(p.dashes, 1.0)) * p.dash_regen() if p.dashes < 1.0 else 0.0, p.dashes >= 1.0, int(floor(p.dashes)), int(dmax))
	x += s + gap
	_ab_slot("tonic", Rect2(Vector2(x, y), Vector2(s, s)), "tonic", Settings.key_cap("tonic"), GOOD, 0.0, 0.0, p.tonics > 0, -1, 0)
	_ctext(Vector2(x + s - 10, y + 18), "×%d" % p.tonics, 13, INK, big)
	x += s + gap
	_ab_slot("kit", Rect2(Vector2(x, y), Vector2(s, s)), "fortify", Settings.key_cap("armor_kit"), ARMOR_COL, 0.0, 0.0, p.armor_kits > 0, -1, 0)
	_ctext(Vector2(x + s - 10, y + 18), "×%d" % p.armor_kits, 13, INK, big)
	x += s + gap + 8.0
	# gear actives
	for gi in 2:
		var g: Dictionary = p.gear[gi]
		if g.is_empty() or not Gear.active(String(g["id"])):
			continue
		var gd: Dictionary = Gear.ALL[String(g["id"])]
		var gs := 48.0
		var gcd := float(p.gear_cd[gi])
		_ab_slot("gear%d" % gi, Rect2(Vector2(x, y + (s - gs)), Vector2(gs, gs)), String(g["id"]), Settings.key_cap("gear%d" % (gi + 1)), gd["col"], gcd / float(gd["cd"]) if gcd > 0.0 else 0.0, gcd, gcd <= 0.0)
		x += gs + 8.0

## Your two kin: the active one big, the benched one small under it.
func _draw_kin_card(sz: Vector2, p: Hunter) -> void:
	var k: Kin = p.kin
	if k == null:
		return
	var w := 250.0
	var r := Rect2(Vector2(16, sz.y - 110), Vector2(w, 94))
	if _narrow(sz):
		r.position.y -= 110.0
	var kc: Color = Data.KIN[k.species]["color"]
	_rounded(r, Color(0.05, 0.06, 0.09, 0.85), 12, Color(Data.KIN[k.species].get("glow", kc), 0.35), 1)
	hover_spots.append([r, "kin"])
	var pc := r.position + Vector2(36, 40)
	c.draw_circle(pc, 25, Color(Data.KIN[k.species].get("glow", kc), 0.25))
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
		"active": st = ("GIANT · " if not k.giant.is_empty() else "") + ("Fighting" if k.target else "Out with you")
		"returning": st = "Coming back"
		"fainted": st = "Resting %ds" % int(ceil(k.faint_t))
		"reviving": st = "Reviving you!"
		"fused": st = "Fused onto you"
	_text(r.position + Vector2(68, 44), st, 12, MUTED)
	_seg_bar(Rect2(r.position + Vector2(68, 54), Vector2(w - 84, 8)), k.hp, k.max_hp, k.hp / k.max_hp, kc, 25.0)
	c.draw_circle(r.position + Vector2(74, 78), 4.0, Color("ffb3c6"))
	_text(r.position + Vector2(84, 83), "Trust %d · %s" % [int(k.trust), Care.bond(k.rec)[1] if k.rec.size() > 0 else ""], 12, Color("ffb3c6"))
	var b: Kin = p.kin2
	if b:
		var br := Rect2(Vector2(r.position.x, r.position.y - 34), Vector2(w, 28))
		var ready_swap := p.swap_cd <= 0.0 and b.hp > 0.0 and k.state != "fused"
		_rounded(br, Color(0.05, 0.06, 0.09, 0.78), 10, Color(Data.KIN[b.species]["color"], 0.6) if ready_swap else Color(1, 1, 1, 0.08), 1)
		hover_spots.append([br, "swap"])
		var bcol: Color = Data.KIN[b.species]["color"]
		c.draw_circle(br.position + Vector2(16, 14), 9, bcol if b.hp > 0.0 else bcol.darkened(0.6))
		_text(br.position + Vector2(32, 19), "%s  ·  benched" % b.rec.get("name", "Kin"), 12, INK)
		_bar(Rect2(br.position + Vector2(w - 82, 12), Vector2(56, 4)), b.hp / b.max_hp, bcol)
		_keycap(br.position + Vector2(w - 14, 14), Settings.key_cap("swap_kin"), Data.KIN[b.species]["color"] if ready_swap else MUTED)
		if p.swap_cd > 0.0:
			_bar(Rect2(br.position + Vector2(32, 24), Vector2(w - 120, 2)), 1.0 - p.swap_cd / maxf(0.1, float(Content.rules("kin_ai").get("swap_cooldown", 3.0))), MUTED)

## Your weapon: rarity, ammo, reload. Under it, what you're carrying home.
func _draw_weapon(sz: Vector2, p: Hunter) -> void:
	var w := 250.0
	var r := Rect2(Vector2(sz.x - w - 16, sz.y - 110), Vector2(w, 94))
	if _narrow(sz):
		r.position.y -= 110.0
	var rc: Color = Data.RARITY[p.wrar]["color"] if p.wrar > 0 else Color("e6dccb")
	_rounded(r, Color(0.05, 0.06, 0.09, 0.85), 12)
	hover_spots.append([r, "weapon"])
	c.draw_rect(Rect2(r.position + Vector2(0, 10), Vector2(3, r.size.y - 20)), rc)
	_text(r.position + Vector2(16, 24), String(p.wpn["name"]), 15, rc, big)
	Icons.draw(c, p.wid, r.position + Vector2(52, 56), 30.0, Color(rc, 0.85))
	var mag := int(p.wpn["mag"])
	var ammo_col := INK if p.ammo > mag * 0.25 else HP_LOW
	if p.wpn.get("melee", false):
		# melee: no ammo; the combo's pips instead, the last one bigger
		_text(r.position + Vector2(112, 62), "MELEE", 16, rc, big)
		var cn: int = (p.wpn.get("combo_dmg", p.wpn.get("combo", [1.0])) as Array).size()
		var live := m.time - p.swing_at <= float(p.wpn["rate"]) + float(p.wpn.get("combo_reset", 0.6))
		for ci in cn:
			var on := live and (p.combo_i % cn) > ci
			var rad := 5.0 if ci == cn - 1 else 3.5
			c.draw_circle(r.position + Vector2(118 + ci * 16, 74), rad, rc if on else Color(1, 1, 1, 0.2))
	elif p.reload_t > 0.0:
		_text(r.position + Vector2(112, 66), "RELOADING", 16, Color("ffe7a8"), big)
		_bar(Rect2(r.position + Vector2(112, 72), Vector2(120, 4)), 1.0 - p.reload_t / float(p.wpn["reload"]), Color("ffe7a8"))
	else:
		_text(r.position + Vector2(112, 70), str(p.ammo), 34, ammo_col, big)
		var aw := big.get_string_size(str(p.ammo), HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
		_text(r.position + Vector2(118 + aw, 70), "/ %d" % mag, 15, MUTED, big)
	var seeds := 0
	for sd in p.seeds: seeds += int(p.seeds[sd])
	_text(r.position + Vector2(16, r.size.y - 8), "%d gems · %d seeds · %d kin" % [p.gems, seeds, p.caught.size()], 12, GOLD if p.gems > 0 else MUTED)

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
		# shown once you land, not over the drop map
		kit_t0 = m.time
		return
	if t > show_t:
		return
	var a := clampf(show_t - t, 0.0, 1.0)
	var lines: Array = []
	var util: AbilityDef = p.runner.def_of("utility") if p.runner else null
	if util:
		lines.append([Settings.key_cap("secondary"), util.display_name, util.desc, util.color])
	if p.kin:
		var k: Kin = p.kin
		var kcol: Color = Data.KIN[k.species]["color"]
		for slot in ["k1", "k2"]:
			var kd: AbilityDef = k.runner.def_of(slot)
			if kd: lines.append([Settings.key_cap("signature" if slot == "k1" else "kin_skill"), kd.display_name, kd.desc, kd.color])
		var ud := Ultimate.def_for(k)
		if ud: lines.append([Settings.key_cap("ultimate"), ud.display_name + " (bond ultimate)", ud.desc + " Fill the bond meter by fighting together.", ud.color])
		lines.append([Settings.key_cap("throw"), "Throw / recall " + String(k.rec.get("name", "your kin")), "Stuns what it hits; then your shots deal a combo. Press again to call it back.", kcol])
		if p.kin2:
			lines.append([Settings.key_cap("swap_kin"), "Swap to " + String((p.kin2 as Kin).rec.get("name", "your other kin")), "Your other kin, with its own abilities and ultimate.", Data.KIN[(p.kin2 as Kin).species]["color"]])
	var w := 356.0
	# each row: the key and name, then the description wrapped to the panel
	var hs: Array = []
	var total := 34.0
	for l in lines:
		var dh := body.get_multiline_string_size(String(l[2]), HORIZONTAL_ALIGNMENT_LEFT, w - 28, 12).y
		hs.append(26.0 + dh + 8.0)
		total += 26.0 + dh + 8.0
	var bottom := sz.y - 120.0
	var box := Rect2(Vector2(sz.x - w - 16, bottom - total), Vector2(w, total))
	if m.opts.get("training", false):
		box.position.y = 240
	_panel(box, Color(0.06, 0.07, 0.1, 0.82 * a), 12)
	_text(box.position + Vector2(14, 22), "Your kit", 14, Color(GOLD, a), big)
	var y := box.position.y + 34
	for i in lines.size():
		var l: Array = lines[i]
		var kw := big.get_string_size(l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var ks := StyleBoxFlat.new(); ks.bg_color = Color(l[3], a); ks.set_corner_radius_all(5)
		c.draw_style_box(ks, Rect2(Vector2(box.position.x + 14, y), Vector2(kw + 12, 20)))
		c.draw_string(big, Vector2(box.position.x + 20, y + 15), l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.07, 0.06, 0.08, a))
		_text(Vector2(box.position.x + 34 + kw, y + 15), l[1], 14, Color(INK, a))
		c.draw_multiline_string(body, Vector2(box.position.x + 14, y + 38), String(l[2]), HORIZONTAL_ALIGNMENT_LEFT, w - 28, 12, -1, Color(MUTED, a))
		y += float(hs[i])

## Perks you've picked up this run: a row of little badges over your health bar, with stacks.
func _draw_perks(sz: Vector2, p: Hunter) -> void:
	if p.perks.is_empty():
		return
	var seen: Array = []
	for pk in p.perks:
		if not seen.has(pk): seen.append(pk)
	var bs := 26.0
	var x := sz.x * 0.5 - (seen.size() * (bs + 6.0)) * 0.5
	var y := sz.y - 194.0
	for pk in seen:
		var pd: Dictionary = Data.PERKS[pk]
		var r := Rect2(Vector2(x, y), Vector2(bs, bs))
		hover_spots.append([r, "perk:" + String(pk)])
		_rounded(r, Color(0.05, 0.06, 0.09, 0.9), 7, Color(pd["col"], 0.8), 1)
		Icons.draw(c, String(pd["icon"]), r.get_center(), bs * 0.3, pd["col"])
		var n := p.perk_n(pk)
		if n > 1:
			_text(r.position + Vector2(bs - 7, bs + 1), str(n), 11, INK, big)
		x += bs + 6.0

## An open perk choice: three cards over the ability bar, picked with 1, 2 or 3.
func _draw_perk_offer(sz: Vector2) -> void:
	var off: Dictionary = m.perk_offer
	if off.is_empty():
		return
	var ids: Array = off["ids"]
	var cw := 196.0; var ch := 70.0; var gap := 10.0
	var total := ids.size() * cw + (ids.size() - 1) * gap
	var x := sz.x * 0.5 - total * 0.5
	var y := sz.y - 290.0         # below your hunter, above your perk badges and bars
	var head: String = {"shrine": "THE SHRINE OFFERS A PERK", "chest": "SOMETHING ELSE IN THE CHEST", "boss": "THE WARDEN'S POWER", "brute": "SPOILS OF THE BRUTE"}.get(String(off.get("src", "")), "PICK A PERK")
	_ctext(Vector2(sz.x * 0.5, y - 12), String(head) + "  ·  lasts this expedition", 13, Color(GOLD, 0.95), big)
	var pulse := 0.5 + 0.5 * sin(m.time * 4.0)
	for i in ids.size():
		var pd: Dictionary = Data.PERKS[ids[i]]
		var col: Color = pd["col"]
		var r := Rect2(Vector2(x, y), Vector2(cw, ch))
		_rounded(r, Color(0.05, 0.06, 0.1, 0.94), 12, Color(col, 0.55 + 0.35 * pulse), 2)
		Icons.draw(c, String(pd["icon"]), r.position + Vector2(22, 22), 11.0, col)
		_text(r.position + Vector2(40, 28), String(pd["name"]), 16, INK, big)
		c.draw_multiline_string(body, r.position + Vector2(12, 47), String(pd["desc"]), HORIZONTAL_ALIGNMENT_LEFT, cw - 24, 12, 2, MUTED)
		_keycap(Vector2(r.get_center().x, r.end.y), str(i + 1), col)
		var n: int = m.player.perk_n(String(ids[i])) if m.player else 0
		if n > 0:
			_text(r.position + Vector2(cw - 34, 22), "x%d" % (n + 1), 12, GOLD, big)
		x += cw + gap

func _draw_prompt(sz: Vector2, p: Hunter) -> void:
	var it := m.interact
	var y := sz.y - 128.0
	if not it.is_empty():
		var prog := 0.0
		match it["kind"]:
			"revive": prog = it["ent"].revive
			"finish": prog = p.finish_t / Life.R["stomp_commit"]
			"stomping": prog = float(p.stomp.get("t", 0.0)) / Life.R["stomp_time"]
			"boxrev": prog = p.box_t / Life.R["box_revive_time"]
			"loot": prog = p.box_t / Life.R["loot_time"]
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
	# the crosshair opens with per-shot bloom and the minigun's spread
	var gap := 6.0 + (p.recoil * 4.0) + p.wbloom * 1.2
	if p.wpn.has("tighten_from_deg") and p.spin > 0.0:
		gap += lerpf(12.0, 0.0, clampf(p.spun_t / float(p.wpn.get("tighten_time", 1.5)), 0.0, 1.0))
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		c.draw_line(mp + d * gap, mp + d * (gap + 7.0), Color(0, 0, 0, 0.6), 4.0)
		c.draw_line(mp + d * gap, mp + d * (gap + 7.0), col, 2.0)
	c.draw_circle(mp, 1.6, col)
	var ck := p.charge_k()
	if ck > 0.0:
		# a sword's charge: fills, then flashes when it's ready to release
		var full := ck >= 1.0
		_arc(mp, 18, ck, Color("fff3b0") if not full or int(m.time * 10.0) % 2 == 0 else Color.WHITE, 4.0 if full else 3.0)
	elif p.warm_t > 0.0:
		_arc(mp, 18, 1.0 - p.warm_t / maxf(0.01, float(p.wpn.get("warmup", 0.6))), p.wpn["color"], 3.0)
	elif p.wpn.has("spin_up") and p.spin > 0.0 and p.spin < 1.0:
		_arc(mp, 18, p.spin, Color("ffb34d"), 3.0)
	elif p.wpn.get("melee", false):
		pass
	elif p.reload_t > 0.0:
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
	var left := p.down_hp / Data.MATCH["down_hp"] * Life.R["bleed_out"]
	var who := "You're a wisp: %ds left. A teammate or your kin standing on you brings you back. Enemies can stomp or execute you." % int(ceil(left))
	if p.kin and p.kin.state == "fainted":
		who = "You're a wisp: %ds left, and your kin is out cold. Only a teammate standing on you can bring you back." % int(ceil(left))
	if p.get_meta("stomped", false):
		who = "An enemy is standing on you! You're draining fast."
	_ctext(Vector2(sz.x * 0.5, sz.y * 0.32 + 28), who, 16, INK)
	_bar(Rect2(Vector2(sz.x * 0.5 - 140, sz.y * 0.32 + 44), Vector2(280, 8)), p.down_hp / Data.MATCH["down_hp"], BAD)
	if p.revive > 0.0:
		_bar(Rect2(Vector2(sz.x * 0.5 - 140, sz.y * 0.32 + 58), Vector2(280, 8)), p.revive, GOOD)

## Dead, but your team's still in it.
func _draw_dead(sz: Vector2, p: Hunter) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.05, 0.03, 0.08, 0.25))
	var y0 := sz.y * 0.62
	_panel(Rect2(Vector2(sz.x * 0.5 - 300, y0 - 44), Vector2(600, 150)))
	_ctext(Vector2(sz.x * 0.5, y0), "You're dead", 30, BAD, big)
	var b := Life.box_of(m, p)
	var lines: Array = []
	if not b.is_empty() and Life.soul_here(m, b):
		lines.append("A teammate can bring you back at your deathbox: %ds left." % int(ceil(float(b["soul_until"]) - m.time)))
	lines.append("Or at any revive beacon (the green pillars), with nothing you carried." if m.beacons.any(func(x): return not x["used"]) else "No revive beacons left.")
	var mate := m.spectating()
	if mate:
		lines.append("Watching %s." % mate.pname)
	lines.append("%s to open the menu and leave." % Settings.key_cap("menu"))
	for i in lines.size():
		_ctext(Vector2(sz.x * 0.5, y0 + 28 + i * 22), lines[i], 16, INK if i < 2 else MUTED)

func _draw_scores(sz: Vector2) -> void:
	var r := Rect2(Vector2(sz.x * 0.5 - 300, sz.y * 0.18), Vector2(600, 40 + m.hunters.size() * 28))
	_panel(r, Color(0.05, 0.06, 0.09, 0.9), 14)
	_text(r.position + Vector2(20, 30), "Hunter", 14, MUTED); _text(r.position + Vector2(260, 30), "Kin", 14, MUTED)
	_text(r.position + Vector2(380, 30), "Knocks", 14, MUTED); _text(r.position + Vector2(450, 30), "Damage", 14, MUTED); _text(r.position + Vector2(530, 30), "State", 14, MUTED)
	var hs := m.hunters.duplicate()
	hs.sort_custom(func(a, b): return a.team < b.team)
	var y := r.position.y + 58
	for h in hs:
		var tc: Color = Data.TEAM_COLORS[h.team % Data.TEAM_COLORS.size()]
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
var abyss_a := 0.0

## Health and stamina (dash charges) right above your hunter, where your eyes already are.
func _draw_overhead(p: Hunter) -> void:
	var cam := m.cam
	var at := p.position + Vector3(0, 2.7 * float(p.cdat["scale"]), 0)
	if cam.is_position_behind(at) or p.downed or p.riding:
		return
	var sp := cam.unproject_position(at)
	var w := 84.0
	var frac := clampf(p.hp / p.max_hp, 0.0, 1.0)
	head_hp = maxf(frac, lerpf(head_hp, frac, 0.06))
	_vitals(sp, w, p, GOOD if frac > 0.35 else BAD, head_hp, true)
	# stamina: one yellow pip per dash under the bars, the next one filling as it recharges
	var n := int(p.max_dashes()) + 1
	for i in n:
		var cpt := sp + Vector2(-w * 0.5 + 6 + i * 13, 17)
		# the last pip is the long dash (Shift in the air, or when the short ones are spent)
		var fill := clampf(p.dashes - i, 0.0, 1.0) if i < n - 1 else 1.0 - p.ex_cd / Hunter.EX_DASH_CD
		var dia := PackedVector2Array([cpt + Vector2(0, -5), cpt + Vector2(5, 0), cpt + Vector2(0, 5), cpt + Vector2(-5, 0)])
		c.draw_colored_polygon(dia, Color(0.04, 0.04, 0.06, 0.8))
		if fill >= 1.0:
			var inner := PackedVector2Array([cpt + Vector2(0, -3.5), cpt + Vector2(3.5, 0), cpt + Vector2(0, 3.5), cpt + Vector2(-3.5, 0)])
			c.draw_colored_polygon(inner, STAMINA_COL)
		elif fill > 0.0:
			c.draw_arc(cpt, 3.0, -PI * 0.5, -PI * 0.5 + TAU * fill, 10, Color(STAMINA_COL, 0.6), 2.0)
	if p.reload_t > 0.0:
		# reloading: a filling ring beside your head, and the word under your bars
		var rf := 1.0 - p.reload_t / float(p.wpn["reload"])
		var rc := sp + Vector2(w * 0.5 + 16, 4)
		c.draw_circle(rc, 11.0, Color(0.04, 0.04, 0.06, 0.75))
		c.draw_arc(rc, 8.0, 0, TAU, 24, Color(1, 1, 1, 0.15), 3.0, true)
		_arc(rc, 8.0, rf, Color("ffe7a8"), 3.0)
		_ctext(sp + Vector2(0, 33), "RELOADING", 11, Color("ffe7a8"), big)
	if p.drink_t > 0.0:
		var df := 1.0 - p.drink_t / Hunter.DRINK_TIME
		var dc := sp + Vector2(-w * 0.5 - 16, 4)
		c.draw_circle(dc, 11.0, Color(0.04, 0.04, 0.06, 0.75))
		_arc(dc, 8.0, df, Color("8ff0a0"), 3.0)
		_ctext(sp + Vector2(0, 33 if p.reload_t <= 0.0 else 46), "DRINKING", 11, Color("8ff0a0"), big)
	if p.kit_t > 0.0:
		var kf := 1.0 - p.kit_t / Hunter.KIT_TIME
		var kc := sp + Vector2(-w * 0.5 - 16, 4)
		c.draw_circle(kc, 11.0, Color(0.04, 0.04, 0.06, 0.75))
		_arc(kc, 8.0, kf, ARMOR_COL, 3.0)
		_ctext(sp + Vector2(0, 33 if p.reload_t <= 0.0 else 46), "REPAIRING", 11, ARMOR_COL, big)

# ------------------------------------------------------------------ hover tips
## Point at anything on the bottom bar (abilities, health, weapon, kin) to see what it is.
func _draw_hover_tip(sz: Vector2, p: Hunter) -> void:
	var mp := c.get_local_mouse_position()
	var hit: Array = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hover="):      # test hook: point at a HUD element
			for hs in hover_spots:
				if hs[1] == arg.substr(8): mp = (hs[0] as Rect2).get_center()
	for hs in hover_spots:
		if (hs[0] as Rect2).has_point(mp):
			hit = hs
	var id: String = hit[1] if hit.size() > 0 else ""
	if id != hover_id:
		hover_id = id
		hover_t = 0.0
	hover_t += get_process_delta_time()
	if id == "" or hover_t < 0.25:
		return
	var lines := _tip_lines(id, p)
	if lines.is_empty():
		return
	# [title, colour] then rows of [text, colour, size]
	var head: Array = lines[0]
	var w := 340.0
	var h := 40.0
	for i in range(1, lines.size()):
		h += _wrapped_h(String(lines[i][0]), w - 28, int(lines[i][2])) + 4.0
	var anchor: Rect2 = hit[0]
	var pos := Vector2(anchor.get_center().x - w * 0.5, anchor.position.y - h - 14)
	pos.x = clampf(pos.x, 8, sz.x - w - 8)
	pos.y = maxf(8, pos.y)
	var a := clampf((hover_t - 0.25) / 0.12, 0.0, 1.0)
	var box := Rect2(pos, Vector2(w, h))
	_rounded(box, Color(0.05, 0.06, 0.09, 0.95 * a), 12, Color(head[1], 0.6 * a), 2)
	_text(pos + Vector2(14, 26), String(head[0]), 17, Color(head[1], a), big)
	var y := pos.y + 40
	for i in range(1, lines.size()):
		var ln: Array = lines[i]
		var fs := int(ln[2])
		var hh := _wrapped_h(String(ln[0]), w - 28, fs)
		c.draw_multiline_string(body, Vector2(pos.x + 14, y + fs), String(ln[0]), HORIZONTAL_ALIGNMENT_LEFT, w - 28, fs, -1, Color(ln[1], a))
		y += hh + 4.0

func _wrapped_h(txt: String, w: float, fs: int) -> float:
	return body.get_multiline_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, w, fs).y

func _secs(x: float) -> String:
	return ("%ds" % int(x)) if absf(x - round(x)) < 0.05 else ("%.1fs" % x)

func _tip_lines(id: String, p: Hunter) -> Array:
	var hc: Color = p.accent()
	var out: Array = []
	if id.begins_with("perk:"):
		var pd: Dictionary = Data.PERKS.get(id.substr(5), {})
		if not pd.is_empty():
			var n := p.perk_n(id.substr(5))
			out.append([String(pd["name"]) + ("  x%d" % n if n > 1 else ""), pd["col"]])
			out.append([String(pd["desc"]), INK])
			out.append(["Found this expedition. Gone when it ends.", MUTED])
		return out
	match id:
		"sec" when p.runner and p.runner.def_of("utility") != null:
			var u: AbilityDef = p.runner.def_of("utility")
			out.append([u.display_name, u.color])
			out.append(["Weapon utility (%s)  ·  %s" % [String(p.wpn.get("name", "")), Settings.key_cap("secondary")], MUTED, 12])
			out.append([u.desc, INK, 14])
			out.append(["Cooldown %s%s" % [_secs(u.cooldown), ("  ·  ready in %s" % _secs(p.runner.cd_left("utility"))) if not p.runner.is_ready("utility") else "  ·  ready"], MUTED, 13])
		"k1", "k2":
			var k: Kin = p.kin
			if k == null: return []
			var kd: AbilityDef = k.runner.def_of(id)
			if kd == null: return []
			out.append([kd.display_name, kd.color])
			out.append(["%s's ability  ·  %s" % [k.rec.get("name", "Kin"), Settings.key_cap("signature" if id == "k1" else "kin_skill")], MUTED, 12])
			out.append([kd.desc, INK, 14])
			var where := "Your kin casts it; from your shoulder it's thrown out first." if kd.from == "kin" else "Works on you wherever your kin is."
			out.append(["Cooldown %s%s. %s" % [_secs(kd.cooldown / maxf(0.1, k.runner.rate)), ("  ·  ready in %s" % _secs(k.runner.cd_left(id))) if not k.runner.is_ready(id) else "  ·  ready", where], MUTED, 13])
			if not kd.auto.is_empty():
				out.append(["Your kin also uses it on its own when it sees the chance (turn this off in Settings).", Color(kd.color, 0.85), 12])
		"r":
			var ud := Ultimate.def_for(p.kin) if p.kin else null
			if ud == null: return []
			out.append([ud.display_name, ud.color])
			out.append(["Bond ultimate  ·  %s  ·  %s" % [Settings.key_cap("ultimate"), "fuses onto you" if ud.form == "armor" else "giant form"], MUTED, 12])
			out.append([ud.desc, INK, 14])
			out.append(["Bond %d%%. Fills as you and your kin land hits together, faster with combos." % int(p.ult * 100.0), GOLD, 13])
		"swap":
			var b: Kin = p.kin2
			if b == null: return []
			out.append(["Swap to %s" % b.rec.get("name", "your other kin"), Data.KIN[b.species]["color"]])
			out.append(["Second kin  ·  %s" % Settings.key_cap("swap_kin"), MUTED, 12])
			var names := []
			for sl in ["k1", "k2"]:
				var bd: AbilityDef = b.runner.def_of(sl)
				if bd: names.append(bd.display_name)
			var bu := Ultimate.def_for(b)
			out.append(["Brings out %s: %s, and %s as its bond ultimate. The kin you swap out rests and heals." % [Data.KIN[b.species]["name"], " and ".join(names), bu.display_name if bu else "its ultimate"], INK, 14])
		"kin":
			var k: Kin = p.kin
			if k == null: return []
			var ai := k.brain
			out.append(["%s the %s" % [k.rec.get("name", "Kin"), Data.KIN[k.species]["name"]], Data.KIN[k.species]["color"]])
			out.append(["Level %d  ·  %d / %d health  ·  trust %d" % [int(k.rec.get("level", 1)), int(ceil(k.hp)), int(k.max_hp), int(k.trust)], MUTED, 12])
			var traits := []
			if ai.aggression > 0.6: traits.append("aggressive: chases foes far")
			if ai.loyalty > 0.65: traits.append("loyal: stays by you and goes after whoever hurts you")
			if ai.caution > 0.55: traits.append("cautious: backs off when hurt")
			if traits.is_empty(): traits.append("steady: a bit of everything")
			out.append(["In a fight it's " + "; ".join(traits) + ".", INK, 14])
		"gear0", "gear1":
			var g: Dictionary = p.gear[int(id.substr(4))]
			if g.is_empty(): return []
			var gd: Dictionary = Gear.ALL[String(g["id"])]
			out.append([gd["name"], gd["col"]])
			out.append(["Gear active  ·  %s" % Settings.key_cap("gear%d" % (int(id.substr(4)) + 1)), MUTED, 12])
			out.append([gd["desc"], INK, 14])
			out.append([Gear.stat_text(String(g["id"]), int(g.get("rar", 1))), MUTED, 13])
		"throw":
			var k: Kin = p.kin
			if k == null: return []
			var sp: Dictionary = Data.KIN[k.species]
			var sh: Dictionary = Data.SHOULDER[sp["shoulder"]]
			out.append(["Throw %s" % k.rec.get("name", "your kin"), sp["color"]])
			out.append(["Kin  ·  %s" % Settings.key_cap("throw"), MUTED, 12])
			out.append(["Throws your kin at the cursor. Whatever it hits is stunned, and your shots crit stunned foes. Press again to call it back.", INK, 14])
			out.append(["On your shoulder: %s. %s" % [sh["name"], sh["desc"]], Color(sp["color"], 0.95), 13])
		"dash":
			var dd: AbilityDef = p.dodge_def
			out.append([dd.display_name if dd else "Dash", dd.color if dd else Color("bfe6ff")])
			out.append(["%s class dodge  ·  %s" % [String(p.cls).capitalize(), Settings.key_cap("dash")], MUTED, 12])
			out.append([dd.desc if dd else "A quick burst the way you're moving.", INK, 14])
			out.append(["%d of %d charges. One comes back every %s." % [int(floor(p.dashes)), int(p.max_dashes()), _secs(p.dash_regen())], MUTED, 13])
		"kit":
			out.append(["Armor kit", ARMOR_COL])
			out.append(["Item  ·  %s" % Settings.key_cap("armor_kit"), MUTED, 12])
			out.append(["Repairs your armor to full. Armor takes 20%% off every hit while it lasts, and doesn't come back on its own. You're carrying %d." % p.armor_kits, INK, 14])
		"tonic":
			out.append(["Tonic", GOOD])
			out.append(["Item  ·  %s" % Settings.key_cap("tonic"), MUTED, 12])
			out.append(["Heals 40%% of your health. Health doesn't come back on its own. You're carrying %d. Find more in chests, or cook them at home." % p.tonics, INK, 14])
		"weapon":
			var wp: Dictionary = p.wpn
			var rc: Color = Data.RARITY[p.wrar]["color"] if p.wrar > 0 else Color("e6dccb")
			out.append([wp["name"], rc])
			out.append(["%s weapon  ·  reloads by itself when empty" % (String(Data.RARITY[p.wrar]["name"]) if p.wrar > 0 else "Standard"), MUTED, 12])
			var rate := 1.0 / maxf(0.01, float(wp["rate"]))
			out.append(["%.0f damage a shot  ·  %.1f shots a second  ·  about %d damage a second" % [float(wp["dmg"]), rate, int(float(wp["dmg"]) * rate)], INK, 14])
			out.append(["Magazine %d  ·  reload %s  ·  range %d tiles" % [int(wp["mag"]), _secs(float(wp["reload"])), int(float(wp.get("range", 10.0)))], MUTED, 13])
			out.append(["Shots spread while you move or jump. Stand still or crouch to tighten them.", MUTED, 12])
		"vitals":
			out.append(["%s class" % String(p.cls).capitalize(), hc])
			out.append(["Speed %.1f  ·  %s" % [p.base_speed, String(p.cdat.get("desc", ""))], MUTED, 12])
			out.append(["Health %d / %d   ·   Armor %d / %d" % [int(ceil(p.hp)), int(p.max_hp), int(ceil(p.armor)), int(p.max_armor)], INK, 14])
			out.append(["Armor takes 20% off every hit until it wears out. Neither armor nor health comes back on its own: use armor kits and tonics.", MUTED, 13])
			if p.lives < 50:
				out.append(["Lives left: %d" % p.lives, Color("ff7a8a"), 13])
	return out

## Point the cursor at a monster, a kin or another hunter to see what it is.
func _draw_world_hover(sz: Vector2, p: Hunter) -> void:
	var mp := c.get_local_mouse_position()
	var cam := m.cam
	var best: Ent = null; var bd := 46.0
	var cands: Array = []
	for mb in m.mobs:
		if not mb.dead: cands.append(mb)
	for k in m.kins:
		if not k.dead and k.visible and k.state != "shoulder": cands.append(k)
	for h in m.hunters:
		if h != p and not h.out and not h.extracted and not h.unseen and h.visible: cands.append(h)
	for e in cands:
		var ep: Vector3 = (e as Node3D).position + Vector3(0, 0.7, 0)
		if cam.is_position_behind(ep):
			continue
		var d := cam.unproject_position(ep).distance_to(mp)
		if d < bd: bd = d; best = e
	if best == null:
		return
	var lines: Array = []
	if best is Mob:
		var mb: Mob = best
		var md: Dictionary = mb.md
		lines.append([String(md["name"]), Color(md["color"]).lightened(0.35)])
		lines.append(["Monster  ·  %d / %d health" % [int(ceil(mb.hp)), int(mb.max_hp)], MUTED])
		var how := {"lunge": "Lunges at whoever is closest.", "spit": "Spits from range: keep moving.", "slam": "Winds up a ground slam: step out of the circle.",
			"fuse": "Rolls in and blows up. Shoot it before it reaches you.", "volley": "Fires a spread of bolts down a line.", "none": "Runs from you. Catch it before it escapes."}
		lines.append([String(how.get(String(md["attack"]), "Dangerous up close.")), INK])
		if md.get("stag", false):
			lines.append(["Staggerable: hit it with an ability while the purple ring shows.", Color(0.85, 0.6, 1.0)])
		lines.append(["Drops %d gems." % int(md["gems"]), GOLD])
	elif best is Kin:
		var k: Kin = best
		var sp: Dictionary = Data.KIN[k.species]
		var nm := String(k.rec.get("name", sp["name"]))
		lines.append([("%s (lost)" % nm if k.lost_from != "" else "Wild %s" % sp["name"]) if k.is_wild() else nm, sp["color"]])
		lines.append(["%s type  ·  level %d  ·  %d / %d health" % [String(sp["type"]).capitalize(), int(k.rec.get("level", 1)), int(ceil(k.hp)), int(k.max_hp)], MUTED])
		if k.is_wild():
			if k.state == "dazed":
				lines.append(["Dazed. Hold %s next to it to catch it." % Settings.key_cap("interact"), GOLD])
			else:
				lines.append(["Knock its health down to daze it, then hold %s to catch it." % Settings.key_cap("interact"), INK])
			if k.rec.get("shimmer", false):
				lines.append(["A shimmering one. Rare.", Color("ffd6ff")])
			if k.lost_from != "":
				lines.append(["Left behind by %s. Whoever collects it keeps it." % ("you" if k.lost_from == "you" else k.lost_from), GOLD if k.lost_from == "you" else MUTED])
		elif k.owner_h == p:
			var a1: AbilityDef = k.runner.def_of("k1")
			lines.append(["Yours. %s throws it, %s uses %s." % [Settings.key_cap("throw"), Settings.key_cap("signature"), a1.display_name if a1 else "its ability"], INK])
		elif k.lost_from == "you" and k.lost_uid != "":
			lines.append(["Your lost kin! Held by %s. Take it back." % (k.owner_h.pname if k.owner_h else "a rival"), GOLD])
		else:
			lines.append(["A rival hunter's kin.", BAD])
	elif best is Hunter:
		var h: Hunter = best
		var ally: bool = h.team == p.team
		lines.append([h.pname, GOOD if ally else Data.TEAM_COLORS[h.team % Data.TEAM_COLORS.size()]])
		lines.append(["%s class  ·  %s  ·  %s" % [String(h.cls).capitalize(), String(h.wpn.get("name", "")), "teammate" if ally else "rival"], MUTED])
		lines.append(["Health %d / %d   ·   Armor %d / %d" % [int(ceil(h.hp)), int(h.max_hp), int(ceil(h.armor)), int(h.max_armor)], INK])
		if h.downed:
			lines.append(["Down. %s" % ("Hold %s next to them to revive." % Settings.key_cap("interact") if ally else "Finish them before they're revived."), BAD if not ally else GOOD])
	var w := 300.0
	var h2 := 36.0
	for i in range(1, lines.size()):
		h2 += _wrapped_h(String(lines[i][0]), w - 24, 13) + 3.0
	var pos := mp + Vector2(22, 18)
	if pos.x + w > sz.x - 8: pos.x = mp.x - w - 22
	if pos.y + h2 > sz.y - 160: pos.y = mp.y - h2 - 18
	var box := Rect2(pos, Vector2(w, h2))
	_rounded(box, Color(0.05, 0.06, 0.09, 0.9), 10, Color(lines[0][1], 0.5), 2)
	_text(pos + Vector2(12, 24), String(lines[0][0]), 16, lines[0][1], big)
	var y := pos.y + 34
	for i in range(1, lines.size()):
		var hh := _wrapped_h(String(lines[i][0]), w - 24, 13)
		c.draw_multiline_string(body, Vector2(pos.x + 12, y + 13), String(lines[i][0]), HORIZONTAL_ALIGNMENT_LEFT, w - 24, 13, -1, lines[i][1])
		y += hh + 3.0

## Place names on the minimap (authored maps). Riding in or dropping you see the whole map with every
## point of interest and chokepoint named; on the ground, the names of places near you.
func _draw_map_labels(w: World, inner: Rect2, view: Rect2, k: float, overview: bool) -> void:
	if w.labels.is_empty():
		return
	for lb in w.labels:
		var p3: Vector3 = lb["pos"]
		var pv := inner.position + (Vector2(p3.x, p3.z) - view.position) * k
		if not inner.grow(-6.0).has_point(pv):
			continue
		var nm := String(lb["name"])
		if String(lb["kind"]) == "choke":
			# a chokepoint: a small orange diamond, named in the overview
			c.draw_colored_polygon(PackedVector2Array([pv + Vector2(0, -5), pv + Vector2(5, 0), pv + Vector2(0, 5), pv + Vector2(-5, 0)]), Color(0, 0, 0, 0.55))
			c.draw_colored_polygon(PackedVector2Array([pv + Vector2(0, -3.5), pv + Vector2(3.5, 0), pv + Vector2(0, 3.5), pv + Vector2(-3.5, 0)]), Color("ffb36a"))
			if overview:
				_ctext(pv + Vector2(0, 14), nm, 10, Color("ffd2a0"))
		else:
			var col := Color("ffd2f0") if String(lb.get("role", "")) == "heart" else INK
			_ctext(pv + Vector2(0, 4), nm, 13 if overview else 11, col, big)

