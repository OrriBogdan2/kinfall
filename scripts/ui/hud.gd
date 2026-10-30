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
				col = Color(w._bio(i)["top"]).lightened(0.12 + 0.08 * mini(w.level[i], 4))
				if w.level[i] >= 8: col = col.lightened(0.35)      # a high perch: brighter, and marked
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
	# abyss danger [footage]: sinking below island level darkens the screen from the edges with a cold
	# tint, more the closer you get to the kill depth and the emptier your glider; near the bottom it
	# pulses red with a quickening heartbeat. It fades away as you climb back up or catch an updraft.
	var want_a := 0.0
	if p and not p.out and not p.grounded and p.over_void():
		var depth := p.last_gy - p.pos.y
		if depth > 0.0:
			var to_kill := maxf(1.0, p.last_gy + 14.0)
			want_a = clampf(depth / to_kill, 0.0, 1.0)
			want_a = clampf(want_a * (1.0 + 0.7 * (1.0 - p.glide_fuel)) + (0.12 if p.glide_fuel <= 0.001 else 0.0), 0.0, 1.0)
	abyss_a = lerpf(abyss_a, want_a, 1.0 - exp(-6.0 * get_process_delta_time()))
	if abyss_a > 0.005:
		var red := clampf((abyss_a - 0.5) * 2.0, 0.0, 1.0)
		var rate := 2.0 + red * 5.0
		abyss_pulse += get_process_delta_time() * rate
		var pulse := pow(0.5 + 0.5 * sin(abyss_pulse * TAU), 3.0)
		# a soft cold wash over everything, then a heavy vignette that closes in from the edges
		c.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.08, 0.04, 0.16, abyss_a * 0.28))
		var rings := 9
		for i in rings:
			var inset := i * minf(sz.x, sz.y) * 0.035 * (0.6 + abyss_a)
			var a := abyss_a * (0.34 - float(i) * 0.034)
			if a <= 0.0: break
			var col := Color(0.04, 0.02, 0.1).lerp(Color(0.35, 0.02, 0.04), red * pulse)
			c.draw_rect(Rect2(Vector2(inset, inset), sz - Vector2(inset, inset) * 2.0), Color(col, a), false, minf(sz.x, sz.y) * 0.04)
		if red > 0.0 and p == m.player:
			var beat := int(floor(abyss_pulse))
			if beat != abyss_beat:
				abyss_beat = beat
				Sfx.play("thump", null, -14.0 + red * 8.0, 0.0, 0.7 + red * 0.15)
	if p and not p.downed and not p.out and p.hp < p.max_hp * 0.35:
		var pulse := 0.5 + 0.5 * sin(m.time * 6.0)
		for i in 5:
			var inset := i * 16.0
			c.draw_rect(Rect2(Vector2(inset, inset), sz - Vector2(inset, inset) * 2.0), Color(0.75, 0.05, 0.05, (0.09 - i * 0.016) * (0.6 + pulse * 0.4)), false, 16.0)
	if flash_t > 0.0:
		c.draw_rect(Rect2(Vector2.ZERO, sz), Color(flash_col, flash_col.a * flash_t * (0.3 if Settings.get_v("reduce_flashes") else 1.0)))
	if p and (p.out or p.downed) and m.killcam_text != "":
		_ctext(Vector2(sz.x * 0.5, maxf(sz.y * 0.22, 104.0 + alerts_h)), m.killcam_text, 22, Color("ff9a8a"), big)
	_draw_top(sz)
	if p and not m.duel:
		_draw_alerts(sz, p)
	else:
		alerts_h = 0.0
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
		if hover_id == "" and m.perk_offer.is_empty():
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
	_draw_wisp_rings()
	for h in m.hunters:
		if h == m.player or h.out or h.extracted or not h.model or not h.model.visible or h.unseen:
			continue
		var sp := cam.unproject_position(h.position + Vector3(0, 2.35, 0))
		if cam.is_position_behind(h.position):
			continue
		_nameplate(sp, h)
	# someone basing to a teammate: a ring filling round them, and a marker on where they'll appear
	for h in m.hunters:
		if h.base_t <= 0.0 or h.out or (h.unseen and h != m.player) or cam.is_position_behind(h.position):
			continue
		var bsp: Vector2 = cam.unproject_position(h.position + Vector3(0, 0.2, 0))
		var bf: float = 1.0 - h.base_t / Hunter.BASE_TIME
		c.draw_arc(bsp, 26.0, 0, TAU, 40, Color(0.56, 0.89, 0.78, 0.25), 3.0, true)
		_arc(bsp, 26.0, bf, Color("8fe3c8"), 4.0)
		_ctext(bsp + Vector2(0, 44), "BASING  %.1f" % h.base_t, 12, Color("8fe3c8"), big)
		var to: Hunter = h.base_to
		if to and is_instance_valid(to) and not cam.is_position_behind(to.position):
			var tsp := cam.unproject_position(to.position + Vector3(0, 3.0, 0))
			_ctext(tsp, "%s incoming" % h.pname.substr(0, 10), 12, Color("8fe3c8"), big)
			c.draw_arc(cam.unproject_position(to.position + Vector3(0, 0.1, 0)), 22.0, 0, TAU, 32, Color(0.56, 0.89, 0.78, 0.4 + 0.3 * sin(m.time * 8.0)), 2.0, true)
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
		# compact bar; rare and mutated monsters (mb.rarity, mb.mutations) wear a tinted frame and
		# little icons for their mutations, and always show their bar
		var rare: bool = int(mb.rarity) > 0 or not mb.mutations.is_empty()
		if mb.hp < mb.max_hp or rare:
			var bw := 64.0 if mb.mkind in ["brute", "warden"] else 48.0
			var br := Rect2(sp + Vector2(-bw * 0.5, 0), Vector2(bw, 6))
			var bfrac := clampf(mb.hp / mb.max_hp, 0.0, 1.0)
			if rare:
				var rc: Color = Data.RARITY[clampi(int(mb.rarity), 0, Data.RARITY.size() - 1)]["color"]
				_rounded(br.grow(3.0), Color(0, 0, 0, 0), 5, rc, 2)
				var mx: float = sp.x - mb.mutations.size() * 7.0 + 7.0
				for mu in mb.mutations:
					c.draw_circle(Vector2(mx, sp.y - 8), 6.0, Color(0.03, 0.03, 0.05, 0.85))
					Icons.draw(c, String(mu.get("icon", "burst")) if mu is Dictionary else String(mu), Vector2(mx, sp.y - 8), 3.6, rc)
					mx += 14.0
			var ct := _chip_of(mb, bfrac)
			_bar(br, bfrac, Color("e0b0ff") if mb.stagger_t > 0.0 else Color("ff8a6a"))
			if ct > bfrac:
				c.draw_rect(Rect2(br.position + Vector2(bw * bfrac, 0), Vector2(bw * (ct - bfrac), 6)), Color(1.0, 0.95, 0.88, 0.8))
			_status_row(sp + Vector2(0, 16), mb)
	# found weapons: name and rarity when you're close enough to care
	var pp: Vector3 = m.player.pos if m.player else cam.focus
	for wp in m.wpicks:
		var wpos: Vector3 = wp["pos"]
		if Vector2(wpos.x - pp.x, wpos.z - pp.z).length() > 7.0 or cam.is_position_behind(wpos):
			continue
		var r: Dictionary = Data.RARITY[int(wp["rar"])]
		var sp := cam.unproject_position(wpos + Vector3(0, 1.45, 0))
		if wp.has("gear") and Gear.ALL.has(String(wp["gear"])):
			# a glove: its name, and which slot it goes in
			var gd: Dictionary = Gear.ALL[String(wp["gear"])]
			_ctext(sp, String(gd["name"]), 15, gd["col"], big)
			_ctext(sp + Vector2(0, 14), ("active  ·  " + Settings.key_cap("gear1")) if Gear.active(String(wp["gear"])) else "passive", 11, Color(INK, 0.75))
		else:
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
		if not is_instance_valid(b["ent"]):
			continue
		var k: Kin = b["ent"]
		if k.dead:
			continue
		var at := k.position + Vector3(0, 1.2, 0)
		if k.state == "shoulder" and k.owner_h:
			at = k.owner_h.position + Vector3(0, 2.3, 0)
		if cam.is_position_behind(at):
			continue
		var sp := cam.unproject_position(at)
		if not (is_finite(sp.x) and is_finite(sp.y)) or absf(sp.x) > 1e5 or absf(sp.y) > 1e5:
			continue
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
	if m.duel:
		_draw_duel(sz)
		return
	if m.opts.get("training", false):
		var rr := Rect2(Vector2(sz.x * 0.5 - 220, 12), Vector2(440, 54))
		_panel(rr, Color(0.06, 0.07, 0.1, 0.88), 12)
		_ctext(Vector2(sz.x * 0.5, 34), "TRAINING AREA", 12, Color("8fe3c8"))
		_ctext(Vector2(sz.x * 0.5, 56), "Nothing can hurt you here  ·  Esc to leave", 15, INK)
		# the checklist: only what's left (up to six), with a count; H folds it away
		var all_rows: Array = m.train_rows()
		var left: Array = all_rows.filter(func(t): return not m.train.has(t[0]))
		var n_done := all_rows.size() - left.size()
		if guide_hidden:
			var pill := Rect2(Vector2(sz.x - 196, 16), Vector2(180, 30))
			_panel(pill, Color(0.06, 0.07, 0.1, 0.8), 10)
			_text(pill.position + Vector2(12, 20), "Guide %d/%d  ·  G to show" % [n_done, all_rows.size()], 13, MUTED)
			return
		var shown: Array = left.slice(0, 6)
		var box := Rect2(Vector2(sz.x - 346, 16), Vector2(330, 58 + maxi(1, shown.size()) * 24))
		_panel(box, Color(0.06, 0.07, 0.1, 0.82), 12)
		_text(box.position + Vector2(14, 24), "Try everything", 15, GOLD, big)
		_text(box.position + Vector2(box.size.x - 120, 24), "%d / %d done" % [n_done, all_rows.size()], 12, MUTED)
		if shown.is_empty():
			_text(box.position + Vector2(14, 50), "All done. Try the duel room!", 13, GOOD)
		for i in shown.size():
			var t: Array = shown[i]
			var key := ("[%s]  " % Settings.key_cap(t[2])) if t[2] != "" else ""
			if t[0] == "move": key = "[%s%s%s%s]  " % [Settings.key_cap("up"), Settings.key_cap("left"), Settings.key_cap("down"), Settings.key_cap("right")]
			_text(box.position + Vector2(14, 50 + i * 24), ("→  " if i == 0 else "○  ") + key + String(t[1]), 13, GOLD if i == 0 else INK)
		_text(box.position + Vector2(14, box.size.y - 10), "G hides the guide and your kit", 11, Color(MUTED, 0.8))
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

## The duel room: what you're up against at the top, and your numbers on the right.
func _draw_duel(sz: Vector2) -> void:
	var d: Duel = m.duel
	var rr := Rect2(Vector2(sz.x * 0.5 - 260, 12), Vector2(520, 58))
	_panel(rr, Color(0.06, 0.07, 0.1, 0.88), 12)
	_ctext(Vector2(sz.x * 0.5, 32), "DUEL ROOM  ·  ROUND %d" % d.round_n, 12, Color("ff9a8a"))
	_ctext(Vector2(sz.x * 0.5, 56), "%s bot  ·  %s class  ·  %s  ·  %s  ·  %s" % [d.pick_text("diff"), d.pick_text("cls"), d.pick_text("weapon"), d.pick_text("glove") if d.glove != "" else "no glove", d.pick_text("mode")], 15, INK)
	if guide_hidden:
		return
	var st: Dictionary = d.stats
	var shots := maxi(1, int(st["shots"]))
	var rows := [
		["Damage dealt", "%d" % int(st["dealt"]), GOOD],
		["Damage taken", "%d" % int(st["taken"]), Color("ff8a7a")],
		["Shots landed", "%d / %d  (%d%%)" % [int(st["hits"]), int(st["shots"]), int(round(100.0 * int(st["hits"]) / shots)) if int(st["shots"]) > 0 else 0], INK],
		["Shots dodged", "%d / %d" % [int(st["dodged"]), int(st["bot_shots"])], Color("9af0ff")],
		["Knocks", "%d  -  %d" % [int(st["knocks"]), int(st["knocked"])], GOLD],
	]
	var box := Rect2(Vector2(sz.x - 286, 16), Vector2(270, 40 + rows.size() * 24 + 28))
	_panel(box, Color(0.06, 0.07, 0.1, 0.82), 12)
	_text(box.position + Vector2(14, 24), "Your numbers", 15, GOLD, big)
	for i in rows.size():
		var y := box.position.y + 50 + i * 24
		_text(Vector2(box.position.x + 14, y), String(rows[i][0]), 13, MUTED)
		_text(Vector2(box.position.x + 140, y), String(rows[i][1]), 14, rows[i][2], big)
	_text(Vector2(box.position.x + 14, box.end.y - 12), "B bot setup  ·  X reset  ·  G hide", 11, Color(MUTED, 0.85))

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
	mm_bottom = r.end.y
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
	if m.skytrain:
		_draw_map_train(inner, view, k)
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
	# your squad, with an arrow for anyone off the edge (a dead teammate shows at their deathbox)
	for h in m.hunters:
		if m.player == null or h.team != m.player.team:
			continue
		var mst := _mate_state(h) if h != m.player else ["ALIVE", INK, h.pos, ""]
		if mst[2] == Vector3.INF or (h == m.player and (h.out or h.extracted)):
			continue
		var pv: Vector2 = to_map.call(mst[2])
		var col: Color = INK if h == m.player else mst[1]
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
	if not sp.is_finite() or absf(sp.x) > 20000.0 or absf(sp.y) > 20000.0:
		return      # (far off screen: a polygon that big can't be triangulated)
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

var guide_hidden := false
var abyss_pulse := 0.0
var abyss_beat := -1
var glider_hit_t := 0.0
var glider_hit_amt := 0.0

## A hit drained your glider: flash the meter and show how much went.
func glider_hit(amount: float) -> void:
	glider_hit_amt = (glider_hit_amt if glider_hit_t > 0.0 else 0.0) + amount
	glider_hit_t = 0.5
var _h_down := false

func _hud_tick(delta: float) -> void:
	_track_mates(m.player, delta)
	_loot_tick(delta)
	glider_hit_t = maxf(0.0, glider_hit_t - delta)
	# G folds the training guide and the kit panel away (and back)
	var hd := Input.is_physical_key_pressed(KEY_G)
	if hd and not _h_down and (m.opts.get("training", false) or m.opts.get("duel", false)):
		guide_hidden = not guide_hidden
	_h_down = hd
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
	# a hit just drained it (2x): the ring flashes red and shows the chunk it lost
	if glider_hit_t > 0.0:
		var hk := glider_hit_t / 0.5
		c.draw_arc(cpt, 19.0, 0.0, TAU, 32, Color(1.0, 0.25, 0.2, 0.8 * hk), 3.0, true)
		_ctext(cpt + Vector2(0, -24), "-%d%%" % int(round(glider_hit_amt * 100.0)), 13, Color(1.0, 0.45, 0.35, hk), big)
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
	# the kit, left to right: Q glove · E kin ability · RMB weapon ability · R bond (big) · Shift dash ·
	# C throw kin · 1 heal, with the passive glove as a small badge at the end
	var s := 60.0
	var gap := 12.0
	var us := 72.0
	var k: Kin = p.kin
	var util: AbilityDef = p.runner.def_of("utility") if p.runner else null
	var g0: Dictionary = p.gear[0]
	var g1: Dictionary = p.gear[1]
	var n_small := 1 + (1 if k else 0) + (1 if util else 0) + 1 + (1 if k else 0) + 1
	var total := n_small * s + us + n_small * gap + (44.0 if not g1.is_empty() else 0.0)
	var x := sz.x * 0.5 - total * 0.5
	var y := sz.y - 88.0
	# Q: the active glove (an empty slot shows dim, so you know to look for one)
	var qr := Rect2(Vector2(x, y), Vector2(s, s))
	if not g0.is_empty() and Gear.ALL.has(String(g0["id"])):
		var gd: Dictionary = Gear.ALL[String(g0["id"])]
		var gcd := float(p.gear_cd[0])
		_ab_slot("gear0", qr, Gear.icon_of(String(g0["id"])), Settings.key_cap("gear1"), gd["col"], gcd / float(gd["cd"]) if gcd > 0.0 else 0.0, gcd, gcd <= 0.0)
	else:
		_rounded(qr, Color(0.05, 0.06, 0.09, 0.55), 12, Color(1, 1, 1, 0.12), 1)
		_ctext(qr.get_center() + Vector2(0, 5), "glove", 11, Color(MUTED, 0.6))
		_keycap(Vector2(qr.get_center().x, qr.end.y + 2), Settings.key_cap("gear1"), Color(MUTED, 0.5))
	x += s + gap
	# E: your kin's ability
	if k:
		var kd: AbilityDef = k.runner.def_of("k1")
		if kd:
			var rdy: bool = k.runner.is_ready("k1") and k.ready_to_fight() and k.state != "fused"
			_ab_slot("k1", Rect2(Vector2(x, y), Vector2(s, s)), kd.icon, Settings.key_cap("signature"), kd.color, k.runner.cd_frac("k1"), k.runner.cd_left("k1") if not k.runner.is_ready("k1") else 0.0, rdy)
			if not k.ready_to_fight():
				_rounded(Rect2(Vector2(x, y), Vector2(s, s)), Color(0, 0, 0, 0.45), 12)
		x += s + gap
	# right click: the weapon's ability
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
		var gdu: UltimateDef = k.giant["def"]
		_bar(Rect2(Vector2(ur.position.x, ur.end.y + 12), Vector2(us, 4)), clampf(float(k.giant["t"]) / gdu.time, 0.0, 1.0), gdu.color)
	x += us + gap
	var dmax := p.max_dashes()
	var dcd := (1.0 - fposmod(p.dashes, 1.0)) if p.dashes < dmax else 0.0
	_ab_slot("dash", Rect2(Vector2(x, y), Vector2(s, s)), "dash", Settings.key_cap("dash"), Color("bfe6ff"), dcd if p.dashes < 1.0 else 0.0, (1.0 - fposmod(p.dashes, 1.0)) * p.dash_regen() if p.dashes < 1.0 else 0.0, p.dashes >= 1.0, int(floor(p.dashes)), int(dmax))
	x += s + gap
	# C: throw / recall your kin
	if k:
		var kc: Color = Data.KIN[k.species]["color"]
		var out_now: bool = k.state in ["active", "flying", "returning"]
		var can_throw: bool = (k.state == "shoulder" and k.throw_cd <= 0.0) or out_now
		_ab_slot("throw", Rect2(Vector2(x, y), Vector2(s, s)), "recall" if out_now else "throw", Settings.key_cap("throw"), kc, k.throw_cd / 1.0 if k.throw_cd > 0.0 else 0.0, k.throw_cd, can_throw, -1, 0, "Recall" if out_now else "")
		x += s + gap
	# 1: heal (a tonic for health; an armor kit once health is full)
	var hurt := p.hp < p.max_hp - 0.5
	var heal_ready := (p.tonics > 0 and hurt) or (p.armor_kits > 0 and p.armor < p.max_armor - 0.5)
	var heal_col := GOOD if hurt or p.armor_kits <= 0 else ARMOR_COL
	_ab_slot("tonic", Rect2(Vector2(x, y), Vector2(s, s)), "tonic" if hurt or p.armor_kits <= 0 else "fortify", Settings.key_cap("tonic"), heal_col, 0.0, 0.0, heal_ready, -1, 0)
	_text(Vector2(x + s - 22, y + 16), "×%d" % p.tonics, 12, Color(GOOD, 0.95), big)
	_text(Vector2(x + s - 22, y + 30), "×%d" % p.armor_kits, 12, Color(ARMOR_COL, 0.95), big)
	x += s + gap
	# B: base to a teammate (squads only)
	if m.hunters.any(func(o): return o != p and o.team == p.team):
		var brr := Rect2(Vector2(x, y + s - 40.0), Vector2(40, 40))
		_ab_slot("base", brr, "swap", Settings.key_cap("base"), Color("8fe3c8"), p.base_cd / Hunter.BASE_CD if p.base_cd > 0.0 else 0.0, p.base_cd, p.base_cd <= 0.0 and p.base_t <= 0.0)
		x += 48.0
	# the passive glove: a small badge (hover it for what it does)
	if not g1.is_empty() and Gear.ALL.has(String(g1["id"])):
		var pg: Dictionary = Gear.ALL[String(g1["id"])]
		var pr := Rect2(Vector2(x, y + s - 36.0), Vector2(36, 36))
		_rounded(pr, Color(0.05, 0.06, 0.09, 0.85), 9, Color(pg["col"], 0.75), 1)
		Icons.draw(c, Gear.icon_of(String(g1["id"])), pr.get_center(), 10.0, pg["col"])
		hover_spots.append([pr, "gear1"])

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
## A teammate's state, for the squad frames, markers and arrows: [label, colour, where to point,
## timer text]. Alive, a downed wisp, dead (with the soul window at their deathbox), gone, or out.
func _mate_state(h: Hunter) -> Array:
	if h.extracted:
		return ["EXTRACTED", Color("8fe3c8"), Vector3.INF, ""]
	if h.out:
		var b: Dictionary = Life.box_of(m, h)
		if h.gone or b.is_empty():
			return ["DEAD", Color("8a8f9e"), Vector3.INF, ""]
		var left := float(b.get("soul_until", 0.0)) - m.time
		if left > 0.0:
			return ["DEATHBOX", Color("ff6a5a"), b.get("pos", h.pos), "%d:%02d" % [int(left) / 60, int(left) % 60]]
		return ["DEAD", Color("8a8f9e"), b.get("pos", h.pos), ""]
	if h.downed:
		return ["WISP", Color("ffb36a"), h.pos, ""]
	return ["ALIVE", GOOD, h.pos, ""]

## Portraits, one per hunter, rendered once (and a greyed copy for the fallen).
var portraits := {}       # nid -> SubViewport
var portraits_grey := {}  # nid -> ImageTexture

func portrait(h: Hunter) -> Texture2D:
	if not portraits.has(h.nid):
		var look: Dictionary = Save.d.get("look", {}) if h.ctrl == "local" else h.bot_look
		var vp := Portraits.make(h.cls, Data.TEAM_COLORS[h.team % Data.TEAM_COLORS.size()], h.wid, look)
		add_child(vp)
		portraits[h.nid] = vp
	return (portraits[h.nid] as SubViewport).get_texture()

func portrait_grey(h: Hunter) -> Texture2D:
	if not portraits_grey.has(h.nid):
		var g := Portraits.grey(portrait(h))
		if g == null:
			return portrait(h)
		portraits_grey[h.nid] = g
	return portraits_grey[h.nid]

## A portrait in a rounded frame. state: "" alive, "down" (red pulse), "dead" (grey + X), "out" (check).
func _draw_portrait(r: Rect2, h: Hunter, state: String, border: Color) -> void:
	_rounded(r.grow(2.0), Color(0.02, 0.02, 0.04, 0.95), 8)
	var col: Color = Data.TEAM_COLORS[h.team % Data.TEAM_COLORS.size()]
	c.draw_rect(r, Color(col.darkened(0.55), 0.9))
	if state == "dead":
		c.draw_texture_rect(portrait_grey(h), r, false, Color(0.8, 0.8, 0.85, 0.85))
		var k := r.size.x * 0.2
		for pair in [[r.position + Vector2(k, k), r.end - Vector2(k, k)], [Vector2(r.end.x - k, r.position.y + k), Vector2(r.position.x + k, r.end.y - k)]]:
			c.draw_line(pair[0], pair[1], Color(0, 0, 0, 0.7), 9.0, true)
			c.draw_line(pair[0], pair[1], Color("ff5a4a"), 5.0, true)
	else:
		c.draw_texture_rect(portrait(h), r, false)
	if state == "down":
		var pulse := 0.5 + 0.5 * sin(m.time * 8.0)
		c.draw_rect(r, Color(0.9, 0.1, 0.05, 0.15 + 0.2 * pulse))
		c.draw_rect(r.grow(1.0), Color(1.0, 0.25, 0.15, 0.55 + 0.45 * pulse), false, 2.5)
	elif state == "out":
		c.draw_rect(r, Color(0.05, 0.15, 0.12, 0.45))
		var a := r.position + r.size * Vector2(0.25, 0.52)
		var b := r.position + r.size * Vector2(0.43, 0.7)
		var d := r.position + r.size * Vector2(0.76, 0.3)
		c.draw_polyline(PackedVector2Array([a, b, d]), Color("8fe3c8"), 5.0, true)
	else:
		c.draw_rect(r.grow(1.0), Color(border, 0.8), false, 1.5)

## Seconds a wisp has left at the normal bleed rate.
func _bleed_left(h: Hunter) -> float:
	return h.down_hp / (Data.MATCH["down_hp"] / Life.R["bleed_out"])

var mm_bottom := 226.0    # where the minimap ends (it grows while you ride in)

## Your squad, stacked under the minimap: portrait, name, armor over segmented health, status icons.
## A knocked teammate pulses red with their bleed-out timer; a dead one is greyed with an X and the
## time left to bring them back from their deathbox; one who got out wears a check mark.
func _draw_squad(sz: Vector2, p: Hunter) -> void:
	var y := mm_bottom + 10.0
	var w := 210.0
	for h in m.hunters:
		if h == p or h.team != p.team:
			continue
		var st := _mate_state(h)
		var lbl := String(st[0])
		var r := Rect2(Vector2(16, y), Vector2(w, 60))
		var down := lbl == "WISP"
		var pulse := 0.5 + 0.5 * sin(m.time * 8.0)
		_rounded(r, Color(0.05, 0.06, 0.09, 0.84), 10, Color(st[1], 0.35 + (0.5 * pulse if down else 0.0)), 2 if down else 1)
		var pr := Rect2(r.position + Vector2(6, 6), Vector2(48, 48))
		var pst := ""
		match lbl:
			"WISP": pst = "down"
			"DEATHBOX", "DEAD": pst = "dead"
			"EXTRACTED": pst = "out"
		_draw_portrait(pr, h, pst, _unit_col(h))
		var tx := pr.end.x + 8.0
		var tw := r.end.x - 8.0 - tx
		_text(Vector2(tx, r.position.y + 19), h.pname.substr(0, 13), 14, INK if lbl == "ALIVE" else Color(INK, 0.7), big)
		# how far, on the right of the name row
		var at: Vector3 = st[2]
		if at != Vector3.INF and lbl != "DEAD":
			var dist_txt := "%dm" % int(round(Vector2(at.x - p.pos.x, at.z - p.pos.z).length()))
			_text(Vector2(r.end.x - 8 - body.get_string_size(dist_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x, r.position.y + 18), dist_txt, 11, MUTED, body)
		match lbl:
			"ALIVE":
				if h.max_armor > 0.5:
					_seg_bar(Rect2(Vector2(tx, r.position.y + 27), Vector2(tw, 4)), h.armor, h.max_armor, 0.0, ARMOR_COL, 25.0)
				var frac := clampf(h.hp / h.max_hp, 0.0, 1.0)
				_seg_bar(Rect2(Vector2(tx, r.position.y + 34), Vector2(tw, 8)), h.hp, h.max_hp, _chip_of(h, frac), HP_COL if frac > 0.35 else HP_LOW, 25.0)
				if _has_status(h):
					_status_row(Vector2(tx + tw * 0.5, r.position.y + 52), h)
			"WISP":
				var left := _bleed_left(h)
				var stp: bool = h.get_meta("stomped", false)
				_bar(Rect2(Vector2(tx, r.position.y + 28), Vector2(tw, 6)), h.down_hp / Data.MATCH["down_hp"], (Color("ff2a1a") if stp else Color("ff6a4a")).lerp(Color.WHITE, (0.5 if stp else 0.25) * pulse))
				_text(Vector2(tx, r.position.y + 51), ("STOMPED  %ds" if stp else "KNOCKED  %ds") % int(ceil(left)), 13, Color("ff4a3a") if stp else Color("ff8a6a"), big)
				if h.revive > 0.0:
					_arc(Vector2(r.end.x - 16, r.position.y + 46), 8, h.revive, GOOD, 3.0)
			"DEATHBOX":
				_text(Vector2(tx, r.position.y + 37), "DEAD", 13, Color("ff6a5a"), big)
				_text(Vector2(tx, r.position.y + 53), "Deathbox  %s" % String(st[3]), 12, Color("ffb0a0"))
			"EXTRACTED":
				_text(Vector2(tx, r.position.y + 42), "EXTRACTED", 13, Color("8fe3c8"), big)
			_:
				_text(Vector2(tx, r.position.y + 42), "ELIMINATED", 13, MUTED, big)
		y += 66
	_draw_squad_markers(sz, p)

func _has_status(e: Ent) -> bool:
	return e.stun_t > 0.0 or e.root_t > 0.0 or e.slow_t > 0.0 or e.burn_t > 0.0 or e.guard_t > 0.0 \
		or (e is Hunter and ((e as Hunter).shield > 0.0 or (e as Hunter).weak_t > 0.0))

## Ally alerts, top centre under the timer. A teammate getting knocked gets a big card (their face,
## name, bleed-out countdown, and how far and which way); it turns green if they're picked up, red if
## they're lost, then fades. Smaller cards for a teammate eliminated or revived from their deathbox.
var mate_last := {}       # nid -> last squad state label
var alerts: Array = []    # {h, kind, t}

func _track_mates(p: Hunter, delta: float) -> void:
	for a in alerts.duplicate():
		a["t"] = float(a["t"]) + delta
		var life := 999.0 if a["kind"] == "knocked" else 2.6
		if float(a["t"]) > life or (a["kind"] == "knocked" and not is_instance_valid(a["h"])) or (a["kind"] == "knocked" and not (a["h"] as Hunter).downed and float(a["t"]) > 1.0):
			alerts.erase(a)
	if p == null:
		return
	for h in m.hunters:
		if h == p or h.team != p.team:
			continue
		var now := String(_mate_state(h)[0])
		var was := String(mate_last.get(h.nid, now))
		mate_last[h.nid] = now
		if now == was:
			continue
		var card = null
		for a in alerts:
			if a["h"] == h and a["kind"] == "knocked":
				card = a
		if now == "WISP":
			if card == null:
				alerts.append({"h": h, "kind": "knocked", "t": 0.0})
			Sfx.play("warn", null, -4.0, 0.0, 0.8)
		elif was == "WISP" and now == "ALIVE":
			if card: card["kind"] = "revived"; card["t"] = 0.0
			else: alerts.append({"h": h, "kind": "revived", "t": 0.0})
			Sfx.play("revive", null, -6.0)
		elif (now == "DEATHBOX" or now == "DEAD") and was in ["WISP", "ALIVE"]:
			if card: card["kind"] = "eliminated"; card["t"] = 0.0
			else: alerts.append({"h": h, "kind": "eliminated", "t": 0.0, "small": true})
			Sfx.play("warn", null, -8.0, 0.0, 0.6)
		elif was == "DEATHBOX" and now == "ALIVE":
			alerts.append({"h": h, "kind": "revived", "t": 0.0, "small": true})
			Sfx.play("revive", null, -6.0)
		elif was == "DEATHBOX" and now == "DEAD":
			alerts.append({"h": h, "kind": "lost", "t": 0.0, "small": true})
	while alerts.size() > 3:
		alerts.pop_front()

var alerts_h := 0.0       # how much room the alerts take (tips sit below them)

func _draw_alerts(sz: Vector2, p: Hunter) -> void:
	var y := 82.0
	alerts_h = 0.0
	for a in alerts:
		var h: Hunter = a["h"]
		var kind := String(a["kind"])
		var t := float(a["t"])
		var fade := 1.0 if kind == "knocked" else clampf((2.6 - t) / 0.6, 0.0, 1.0)
		var pop := clampf(t / 0.15, 0.0, 1.0)
		var small: bool = a.get("small", false)
		var w := 300.0 if not small else 236.0
		var hh := 70.0 if not small else 44.0
		var r := Rect2(Vector2(sz.x * 0.5 - w * 0.5, y + (1.0 - pop) * -10.0), Vector2(w, hh))
		var col := Color("ff5a3a")
		var title := "ALLY KNOCKED"
		match kind:
			"revived": col = GOOD; title = "ALLY REVIVED"
			"eliminated": col = BAD; title = "ALLY ELIMINATED"
			"lost": col = MUTED; title = "WISP LOST"
		var pulse := 0.5 + 0.5 * sin(m.time * 8.0) if kind == "knocked" else 0.0
		_rounded(r, Color(0.06, 0.03, 0.04, 0.9 * fade), 10, Color(col, (0.6 + 0.4 * pulse) * fade), 2)
		var ps := hh - 12.0
		var pr := Rect2(r.position + Vector2(6, 6), Vector2(ps, ps))
		var pst := "down" if kind == "knocked" else ("dead" if kind in ["eliminated", "lost"] else "")
		if fade > 0.05:
			_draw_portrait(pr, h, pst, col)
		var tx := pr.end.x + 10.0
		if small:
			_text(Vector2(tx, r.position.y + 19), title, 12, Color(col, fade), big)
			_text(Vector2(tx, r.position.y + 36), h.pname.substr(0, 16), 14, Color(INK, fade), big)
		else:
			_text(Vector2(tx, r.position.y + 21), title, 13, Color(col, fade), big)
			_text(Vector2(tx, r.position.y + 42), h.pname.substr(0, 16), 17, Color(INK, fade), big)
			if kind == "knocked":
				_text(Vector2(tx, r.position.y + 61), "%ds to revive" % int(ceil(_bleed_left(h))), 12, Color("ffb0a0"))
				# which way, and how far
				var dv := Vector2(h.pos.x - p.pos.x, h.pos.z - p.pos.z)
				var ctr := Vector2(r.end.x - 34, r.position.y + 30)
				var ang := _screen_dir(dv)
				var tip := ctr + Vector2.from_angle(ang) * 13.0
				var side := Vector2.from_angle(ang + PI * 0.5) * 7.0
				var back := ctr - Vector2.from_angle(ang) * 6.0
				c.draw_circle(ctr, 17.0, Color(0, 0, 0, 0.35))
				c.draw_colored_polygon(PackedVector2Array([tip, back + side, back - side]), col)
				_ctext(Vector2(ctr.x, r.position.y + 63), "%dm" % int(round(dv.length())), 12, INK, big)
			else:
				_text(Vector2(tx, r.position.y + 61), "Back on their feet" if kind == "revived" else "Get to their deathbox", 12, Color(MUTED, fade))
		y += hh + 8.0
		alerts_h += hh + 8.0

## A ground direction as a screen angle, using the camera's view.
func _screen_dir(dv: Vector2) -> float:
	var cam := m.cam
	if cam == null or m.player == null:
		return dv.angle()
	var a := cam.unproject_position(m.player.position)
	var b := cam.unproject_position(m.player.position + Vector3(dv.x, 0, dv.y).normalized() * 3.0)
	return (b - a).angle()

## Supervive-style nameplate over another hunter: a class badge and the name, armor segments over a
## segmented health bar (each tick is a fixed chunk of health), a white chip that drains after a hit,
## and a row of status icons. Allies wear their team colour, enemies hostile red. No mana anywhere.
const HOSTILE := Color("ff5a4a")
var chip := {}            # nid -> trailing health fraction (the white chip after a hit)

func _unit_col(h: Hunter) -> Color:
	if m.player and h.team != m.player.team:
		return HOSTILE
	return Data.TEAM_COLORS[h.team % Data.TEAM_COLORS.size()] if h != m.player else p_team_col()

func p_team_col() -> Color:
	return Data.TEAM_COLORS[m.player.team % Data.TEAM_COLORS.size()] if m.player else GOOD

func _chip_of(e: Ent, frac: float) -> float:
	var was := float(chip.get(e.nid, frac))
	var t := maxf(frac, move_toward(was, frac, get_process_delta_time() * 0.6))
	chip[e.nid] = t
	return t

func _nameplate(sp: Vector2, h: Hunter) -> void:
	if not sp.is_finite():
		return
	var col := _unit_col(h)
	var w := 70.0
	var x0 := sp.x - w * 0.5
	# badge + name
	var cc: Color = Data.CLASSES.get(h.cls, {}).get("color", INK)
	var bc := Vector2(x0 - 10, sp.y - 16)
	c.draw_circle(bc, 7.5, Color(0.03, 0.03, 0.05, 0.9))
	c.draw_arc(bc, 7.5, 0, TAU, 18, col, 1.6, true)
	_ctext(bc + Vector2(0, 4), String(h.cls).substr(0, 1).to_upper(), 10, cc, big)
	_text(Vector2(x0 + 2, sp.y - 11), h.pname.substr(0, 14), 13, col.lerp(Color.WHITE, 0.25), big)
	if h.downed:
		var stomped: bool = h.get_meta("stomped", false)
		var pulse := 0.5 + 0.5 * sin(m.time * 14.0)
		var bcol := Color("ff3a2a").lerp(Color.WHITE, 0.3 * pulse) if stomped else Color("ffb36a")
		_seg_bar(Rect2(Vector2(x0, sp.y - 2), Vector2(w, 6)), h.down_hp, Data.MATCH["down_hp"], 0.0, bcol, 25.0)
		var revs: Array = h.get_meta("revivers", [])
		if stomped:
			var sts: Array = h.get_meta("stompers", [])
			_ctext(sp + Vector2(0, 16), "STOMPED  ·  %s" % (sts[0] as Hunter).pname if not sts.is_empty() else "STOMPED", 11, bcol, big)
		elif h.revive > 0.0 and not revs.is_empty():
			_ctext(sp + Vector2(0, 16), "%s reviving  %d%%" % [(revs[0] as Hunter).pname, int(h.revive * 100.0)], 11, GOOD, big)
		else:
			_ctext(sp + Vector2(0, 16), "DOWN", 11, Color("ffb36a"), big)
		return
	if h.max_armor > 0.5:
		_seg_bar(Rect2(Vector2(x0, sp.y - 4), Vector2(w, 3)), h.armor, h.max_armor, 0.0, ARMOR_COL, 25.0)
	var frac := clampf(h.hp / h.max_hp, 0.0, 1.0)
	_seg_bar(Rect2(Vector2(x0, sp.y + 2), Vector2(w, 7)), h.hp, h.max_hp, _chip_of(h, frac), col if frac > 0.35 else col.lerp(Color.WHITE, 0.2 + 0.2 * sin(m.time * 9.0)), 25.0)
	if h.shield > 0.0:
		c.draw_rect(Rect2(Vector2(x0, sp.y + 2), Vector2(w * clampf(h.shield / 120.0, 0.0, 1.0), 7)), Color(0.85, 0.93, 1.0, 0.5))
	_status_row(Vector2(sp.x, sp.y + 19), h)

## Little icons for what's happening to someone: stunned, rooted, slowed, burning, shielded, braced.
func _status_row(at: Vector2, e: Ent) -> void:
	var icons: Array = []
	if e.stun_t > 0.0: icons.append(["concussion", Color("fff27a")])
	if e.root_t > 0.0: icons.append(["binding", Color("8fe0a0")])
	if e.slow_t > 0.0: icons.append(["snare", Color("9ae8ff")])
	if e.burn_t > 0.0: icons.append(["fireball", Color("ff9a5a")])
	if e is Hunter and (e as Hunter).shield > 0.0: icons.append(["brightshield", Color("d8ecff")])
	if e.guard_t > 0.0: icons.append(["anchor", Color("f2e6cf")])
	if e is Hunter and (e as Hunter).weak_t > 0.0: icons.append(["swap", Color("ffb36a"), (e as Hunter).weak_t])
	var x := at.x - icons.size() * 8.0 + 8.0
	for ic in icons:
		c.draw_circle(Vector2(x, at.y), 7.0, Color(0.03, 0.03, 0.05, 0.85))
		Icons.draw(c, String(ic[0]), Vector2(x, at.y), 4.2, ic[1])
		if ic.size() > 2:
			_ctext(Vector2(x, at.y + 17), "%.1f" % float(ic[2]), 10, ic[1], big)
		x += 16.0

## Teammates you can't see on screen get an arrow at the screen edge (with distance, coloured by
## how they're doing); a dead teammate's deathbox gets a marker while their soul can still be saved.
func _draw_squad_markers(sz: Vector2, p: Hunter) -> void:
	var cam := m.cam
	var inner := Rect2(Vector2(70, 90), sz - Vector2(140, 220))
	for h in m.hunters:
		if h == p or h.team != p.team:
			continue
		var st := _mate_state(h)
		var at: Vector3 = st[2]
		if at == Vector3.INF:
			continue
		var col: Color = st[1]
		var wp := at + Vector3(0, 2.4, 0)
		var dist := int(round(Vector2(at.x - p.pos.x, at.z - p.pos.z).length()))
		var behind := cam.is_position_behind(wp)
		var sp := cam.unproject_position(wp)
		if not behind and inner.has_point(sp):
			if String(st[0]) == "DEATHBOX":
				# the overhead label doesn't exist for the dead: mark the box
				_ctext(sp + Vector2(0, -6), "%s  ·  %s" % [h.pname.substr(0, 12), st[3]], 14, col, big)
				c.draw_circle(sp + Vector2(0, 8), 5.0, col)
			continue
		var ctr := sz * 0.5
		var d := (sp - ctr) * (-1.0 if behind else 1.0)
		if d.length() < 1.0: continue
		d = d.normalized()
		var t := minf(inner.size.x * 0.5 / maxf(0.001, absf(d.x)), inner.size.y * 0.5 / maxf(0.001, absf(d.y)))
		var e := ctr + d * t
		var side := Vector2(-d.y, d.x)
		c.draw_colored_polygon(PackedVector2Array([e + d * 16.0, e - d * 6.0 + side * 11.0, e - d * 6.0 - side * 11.0]), col)
		var lbl := "%s %dm" % [h.pname.substr(0, 10), dist]
		if String(st[0]) == "WISP": lbl = "%s DOWN %dm" % [h.pname.substr(0, 10), dist]
		elif String(st[0]) == "DEATHBOX": lbl = "%s's box %s" % [h.pname.substr(0, 10), st[3]]
		_ctext(e - d * 26.0 + Vector2(0, 5), lbl, 13, col, big)

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
	if not Settings.get_v("tips") or m.opts.get("tutorial", false) or p.out or guide_hidden or not m.perk_offer.is_empty():
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
		var kd1: AbilityDef = k.runner.def_of("k1")
		if kd1: lines.append([Settings.key_cap("signature"), kd1.display_name, kd1.desc, kd1.color])
		var ud := Ultimate.def_for(k)
		if ud: lines.append([Settings.key_cap("ultimate"), ud.display_name + " (bond ultimate)", ud.desc + " Fill the bond meter by fighting together.", ud.color])
		lines.append([Settings.key_cap("throw"), "Throw / recall " + String(k.rec.get("name", "your kin")), "Stuns what it hits; then your shots deal a combo. Press again to call it back.", kcol])
	var g0: Dictionary = p.gear[0]
	if not g0.is_empty() and Gear.ALL.has(String(g0["id"])):
		var gdd: Dictionary = Gear.ALL[String(g0["id"])]
		lines.append([Settings.key_cap("gear1"), String(gdd["name"]), String(gdd["desc"]), gdd["col"]])
	else:
		lines.append([Settings.key_cap("gear1"), "Glove (empty)", "Find gloves in chests, vaults and on bosses. An active glove goes here.", MUTED])
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
	var compact := false
	if m.opts.get("training", false):
		# in training it stays up, so it lives on the left under the minimap, clear of the checklist;
		# on a short screen it drops the descriptions rather than run into your kin card
		box.position = Vector2(16, 240)
		if total > sz.y - 240 - 124:
			compact = true
			hs = []
			for l in lines: hs.append(28.0)
			total = 34.0 + 28.0 * lines.size() + 4.0
		box.size.y = total
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
		if not compact:
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
	var y := sz.y - 222.0
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
	var stomped: bool = p.get_meta("stomped", false)
	if stomped:
		var sts: Array = p.get_meta("stompers", [])
		who = "%s is on you! You're pinned and draining %.1fx faster. Drift away!" % [(sts[0] as Hunter).pname if not sts.is_empty() else "An enemy", Life.R["stomp_mult"]]
		_edge_pulse(sz, Color(1.0, 0.1, 0.05), 0.35 + 0.3 * (0.5 + 0.5 * sin(m.time * 9.0)))
	_ctext(Vector2(sz.x * 0.5, sz.y * 0.32 + 28), who, 16, Color("ff7a6a") if stomped else INK)
	_bar(Rect2(Vector2(sz.x * 0.5 - 140, sz.y * 0.32 + 44), Vector2(280, 8)), p.down_hp / Data.MATCH["down_hp"], Color("ff2a1a").lerp(Color.WHITE, 0.3 * (0.5 + 0.5 * sin(m.time * 14.0))) if stomped else BAD)
	if p.revive > 0.0:
		_bar(Rect2(Vector2(sz.x * 0.5 - 140, sz.y * 0.32 + 58), Vector2(280, 8)), p.revive, GOOD)
		var revs: Array = p.get_meta("revivers", [])
		if not revs.is_empty():
			_ctext(Vector2(sz.x * 0.5, sz.y * 0.32 + 84), "%s is reviving you  %d%%" % [(revs[0] as Hunter).pname, int(p.revive * 100.0)], 15, GOOD, big)

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
	var r := Rect2(Vector2(sz.x * 0.5 - w * 0.5, 84 + alerts_h), Vector2(w, lines.y + 34))
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
	_vitals(sp, w, p, p_team_col().lerp(Color.WHITE, 0.15) if frac > 0.35 else BAD, head_hp, true)
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
	_status_row(sp + Vector2(0, 30), p)
	# high up: a small readout of how far above the ground you are
	var alt := m.player_altitude() if p == m.player else 0.0
	if alt > 6.0 and not p.grounded:
		_ctext(sp + Vector2(-w * 0.5 - 30, 8), "%dm" % int(round(alt)), 13, Color("bfe6ff"), big)
		c.draw_colored_polygon(PackedVector2Array([sp + Vector2(-w * 0.5 - 30, -10), sp + Vector2(-w * 0.5 - 35, -3), sp + Vector2(-w * 0.5 - 25, -3)]), Color("bfe6ff"))
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
			out.append(["Active glove  ·  %s" % Settings.key_cap("gear1") if int(id.substr(4)) == 0 else "Passive glove", MUTED, 12])
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
			out.append(["Item  ·  %s (when your health is full)" % Settings.key_cap("tonic"), MUTED, 12])
			out.append(["Repairs your armor to full. Armor takes 20%% off every hit while it lasts, and doesn't come back on its own. You're carrying %d." % p.armor_kits, INK, 14])
		"base":
			out.append(["Base to a teammate", Color("8fe3c8")])
			out.append(["Squads  ·  %s" % Settings.key_cap("base"), MUTED, 12])
			out.append(["A 3s channel to the teammate nearest your cursor. Stand still: moving, attacking or any damage interrupts it. You arrive weakened for 3s: half damage, and your crowd control, healing and shields are halved.", INK, 14])
			out.append(["Cooldown %ds%s" % [int(Hunter.BASE_CD), ("  ·  ready in %ds" % int(ceil(p.base_cd))) if p.base_cd > 0.0 else "  ·  ready"], MUTED, 13])
		"tonic":
			out.append(["Heal", GOOD])
			out.append(["Item  ·  %s" % Settings.key_cap("tonic"), MUTED, 12])
			out.append(["Drinks a tonic (40%% of your health) when you're hurt; with full health it uses an armor kit instead. Neither comes back on its own. Carrying %d tonics and %d kits." % [p.tonics, p.armor_kits], INK, 14])
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

## The sky train on the minimap: its loop as a dashed amber line (fainter where it runs under a
## bridge), and the train itself, the engine marked red so you can see which way it's coming.
var _train_line := PackedVector2Array()
var _train_low: Array = []
func _draw_map_train(inner: Rect2, view: Rect2, k: float) -> void:
	var st: SkyTrain = m.skytrain
	if _train_line.is_empty():
		var s := 0.0
		while s < st.loop_len:
			var p := m.world.train_at(s)
			_train_line.append(Vector2(p.x, p.z)); _train_low.append(p.y < -1.0)
			s += 1.5
	var n := _train_line.size()
	for i in n:
		if i % 2 == 1:
			continue
		var a := inner.position + (_train_line[i] - view.position) * k
		var b := inner.position + (_train_line[(i + 1) % n] - view.position) * k
		if not (inner.has_point(a) and inner.has_point(b)):
			continue
		c.draw_line(a, b, Color(1.0, 0.72, 0.35, 0.35 if _train_low[i] else 0.8), 2.0, true)
	var cars: Array = st.car_positions()
	for ci in range(cars.size() - 1, -1, -1):
		var pv: Vector2 = inner.position + ((cars[ci] as Vector2) - view.position) * k
		if not inner.grow(-3.0).has_point(pv):
			continue
		c.draw_circle(pv, 4.0 if ci == 0 else 3.2, Color(0, 0, 0, 0.6))
		c.draw_circle(pv, 3.0 if ci == 0 else 2.3, Color("ff5a3a") if ci == 0 else Color("ffcf7a"))

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
		if String(lb["kind"]) == "perch":
			# a high perch: an up-arrow with its height, so you know it takes vertical tech
			c.draw_colored_polygon(PackedVector2Array([pv + Vector2(0, -8), pv + Vector2(6, 3), pv + Vector2(-6, 3)]), Color(0, 0, 0, 0.6))
			c.draw_colored_polygon(PackedVector2Array([pv + Vector2(0, -6), pv + Vector2(4.5, 2), pv + Vector2(-4.5, 2)]), Color("9af0ff"))
			if overview:
				_ctext(pv + Vector2(0, 15), "%s  %dm" % [nm, int(round(float(lb.get("height", 0.0))))], 10, Color("c8f6ff"))
			continue
		if String(lb["kind"]) == "rail":
			# a train stop: a small amber square, named in the overview
			c.draw_rect(Rect2(pv - Vector2(4, 4), Vector2(8, 8)), Color(0, 0, 0, 0.6))
			c.draw_rect(Rect2(pv - Vector2(3, 3), Vector2(6, 6)), Color("ffcf7a"))
			if overview:
				_ctext(pv + Vector2(0, 14), nm, 10, Color("ffe2b0"))
			continue
		if String(lb["kind"]) == "choke":
			# a chokepoint: a small orange diamond, named in the overview
			c.draw_colored_polygon(PackedVector2Array([pv + Vector2(0, -5), pv + Vector2(5, 0), pv + Vector2(0, 5), pv + Vector2(-5, 0)]), Color(0, 0, 0, 0.55))
			c.draw_colored_polygon(PackedVector2Array([pv + Vector2(0, -3.5), pv + Vector2(3.5, 0), pv + Vector2(0, 3.5), pv + Vector2(-3.5, 0)]), Color("ffb36a"))
			if overview:
				_ctext(pv + Vector2(0, 14), nm, 10, Color("ffd2a0"))
		else:
			var col := Color("ffd2f0") if String(lb.get("role", "")) == "heart" else INK
			_ctext(pv + Vector2(0, 4), nm, 13 if overview else 11, col, big)

# ------------------------------------------------------------------ the deathbox loot window
## Pressing interact at a deathbox opens this: everything inside, each with its icon and rarity
## colour, "upgrade" marked where it beats what you've got. Click one to take it (swapping a glove
## or weapon leaves yours in the box); press interact again, or Smart loot, to grab everything
## worth having. Walking away, going down or emptying the box closes it.
var loot_open = null          # the box Dictionary, or null
var loot_panel: PanelContainer
var loot_sig := ""

func loot_is(b: Dictionary) -> bool:
	return loot_open != null and is_same(loot_open, b)

func mouse_on_ui() -> bool:
	if loot_panel == null or not is_instance_valid(loot_panel) or not loot_panel.visible:
		return false
	return loot_panel.get_global_rect().grow(6.0).has_point(loot_panel.get_global_mouse_position())

func open_loot(b: Dictionary) -> void:
	loot_open = b
	loot_sig = ""
	Sfx.play("whoosh", null, -10.0, 0.05, 1.3)
	_build_loot()
	if loot_panel: UI.pop_in(loot_panel)

func close_loot() -> void:
	loot_open = null
	if loot_panel and is_instance_valid(loot_panel):
		loot_panel.queue_free()
	loot_panel = null

func _loot_tick(_delta: float) -> void:
	if loot_open == null:
		return
	var p: Hunter = m.player
	var b: Dictionary = loot_open
	if p == null or p.out or p.downed or b.get("empty", true) or p.flat_dist(b["pos"]) > 2.4 or not m.boxes.has(b):
		close_loot()
		return
	# rebuild only when what's in it (or what you're holding) changes
	var sig := str(Life.box_items(m, p, b).map(func(it): return [it["name"], it["upgrade"]])) + str(p.gear) + p.wid + str(p.wrar)
	if sig != loot_sig:
		_build_loot()

func _build_loot() -> void:
	var p: Hunter = m.player
	var b: Dictionary = loot_open
	if loot_panel and is_instance_valid(loot_panel):
		loot_panel.queue_free()
	var items: Array = Life.box_items(m, p, b)
	loot_sig = str(items.map(func(it): return [it["name"], it["upgrade"]])) + str(p.gear) + p.wid + str(p.wrar)
	var pc := PanelContainer.new()
	pc.theme = UI.theme()
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	var bc: Color = Life.box_color(b)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.065, 0.1, 0.95)
	sb.set_corner_radius_all(14)
	sb.border_color = Color(bc, 0.8); sb.set_border_width_all(2); sb.border_width_top = 4
	sb.content_margin_left = 14; sb.content_margin_right = 14; sb.content_margin_top = 12; sb.content_margin_bottom = 12
	sb.shadow_color = Color(0, 0, 0, 0.5); sb.shadow_size = 18
	pc.add_theme_stylebox_override("panel", sb)
	var v := UI.vbox(6); pc.add_child(v)
	var o: Hunter = b["owner"]
	var head := UI.hbox(8); v.add_child(head)
	head.add_child(Icons.Glyph.new("gem", bc, 18.0))
	var t := UI.title(("Your deathbox" if o == p else "%s's deathbox" % o.pname), 22, INK)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var cl := UI.button("✕", func(): close_loot(), 36)
	cl.flat = true
	head.add_child(cl)
	if items.is_empty():
		v.add_child(UI.label("Empty.", 14, MUTED))
	var list := UI.vbox(6)
	if items.size() > 5:
		var sc := ScrollContainer.new()
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.custom_minimum_size.y = 5 * 60.0
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(list)
		v.add_child(sc)
	else:
		v.add_child(list)
	for it in items:
		var row := UI.hbox(8)
		var rp := PanelContainer.new()
		var rs := StyleBoxFlat.new()
		rs.bg_color = Color(it["col"], 0.12 if it["upgrade"] else 0.06)
		rs.set_corner_radius_all(9)
		rs.border_color = Color(it["col"], 0.55 if it["upgrade"] else 0.2); rs.border_width_left = 3
		rs.content_margin_left = 8; rs.content_margin_right = 8; rs.content_margin_top = 5; rs.content_margin_bottom = 5
		rp.add_theme_stylebox_override("panel", rs)
		rp.add_child(row)
		row.add_child(Icons.Glyph.new(String(it["icon"]), it["col"], 24.0))
		var col := UI.vbox(0); col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var nm := UI.label(String(it["name"]), 15, INK, UI.semi)
		nm.autowrap_mode = TextServer.AUTOWRAP_OFF
		col.add_child(nm)
		var sub := UI.label(String(it["sub"]), 12, MUTED)
		sub.autowrap_mode = TextServer.AUTOWRAP_OFF
		sub.clip_text = true
		sub.custom_minimum_size.x = 210
		col.add_child(sub)
		row.add_child(col)
		if it["key"] in ["gear", "weapon"]:
			var tag := UI.label("UPGRADE" if it["upgrade"] else "WORSE", 11, GOOD if it["upgrade"] else MUTED, UI.caps)
			tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(tag)
		var itc: Dictionary = it
		var take := UI.button("Swap" if it["key"] in ["gear", "weapon"] else "Take", func():
			if loot_open != null and m.player:
				Life.take_item(m, m.player, loot_open, itc)
				if (loot_open as Dictionary).get("empty", false): close_loot()
				else: _build_loot(), 76)
		take.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(take)
		list.add_child(rp)
	var foot := UI.hbox(8); v.add_child(foot)
	var sm := UI.primary("Smart loot  (%s)" % Settings.key_cap("interact"), func():
		if loot_open != null and m.player:
			var got := Life.smart_loot(m, m.player, loot_open)
			toast_small(("Smart looted %d thing%s" % [got, "" if got == 1 else "s"]) if got > 0 else "Nothing here beats what you've got", Color("ffd36a"))
			close_loot(), 200)
	foot.add_child(sm)
	var hint := UI.label("Takes everything useful; leaves worse gear", 12, MUTED)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(hint)
	pc.custom_minimum_size.x = 430
	add_child(pc)
	loot_panel = pc
	# to the right of centre, clear of your hunter and the ability bar
	await get_tree().process_frame
	if is_instance_valid(pc):
		var vs := pc.get_viewport_rect().size
		pc.position = Vector2(vs.x * 0.5 + 90.0, maxf(90.0, vs.y * 0.5 - pc.size.y * 0.5 - 40.0))

# ------------------------------------------------------------------ wisp and deathbox revive rings
## A ring on the ground round every wisp you can see, the size of the revive range: green and
## filling as a teammate brings them up (both teams see it), red and pulsing while an enemy is
## standing on it. Near a downed teammate you get a "step in" cue with how far off you are; on top
## of an enemy wisp you get "Standing on <name>". Deathbox revives get the same ring.
func _ground_ring(at: Vector3, r: float, col: Color, width: float, frac := 1.0, start := -PI * 0.5) -> void:
	var cam := m.cam
	var n := 40
	var pts := PackedVector2Array()
	var steps := maxi(2, int(ceil(n * clampf(frac, 0.0, 1.0))))
	for i in steps + 1:
		var a := start + TAU * frac * float(i) / float(steps)
		var wp := at + Vector3(cos(a) * r, 0.08, sin(a) * r)
		if cam.is_position_behind(wp):
			return
		pts.append(cam.unproject_position(wp))
	c.draw_polyline(pts, col, width, true)

func _draw_wisp_rings() -> void:
	var p: Hunter = m.player
	var rr: float = Life.R["revive_radius"]
	for o in m.hunters:
		if not o.downed or o.out or (o.unseen and o != p) or m.cam.is_position_behind(o.position):
			continue
		var stomped: bool = o.get_meta("stomped", false)
		var pulse := 0.5 + 0.5 * sin(m.time * 10.0)
		if stomped:
			_ground_ring(o.pos, rr * (1.0 + 0.08 * pulse), Color(1.0, 0.18, 0.1, 0.55 + 0.35 * pulse), 4.0)
			_ground_ring(o.pos, rr * 0.55, Color(1.0, 0.3, 0.2, 0.35 * pulse), 2.5)
		else:
			var ally: bool = p != null and o.team == p.team
			var base := GOOD if ally else Color("ffb36a")
			_ground_ring(o.pos, rr, Color(base, 0.35), 2.0)
			if o.revive > 0.0:
				_ground_ring(o.pos, rr, Color(GOOD, 0.95), 5.0, o.revive)
		if p == null or p.out or p.downed or p == o:
			continue
		var d := p.flat_dist(o)
		var lp := m.cam.unproject_position(o.pos + Vector3(0, 0.1, 0)) + Vector2(0, 30)
		if o.team == p.team and not stomped and d > rr and d < 9.0:
			_ctext(lp, "Step in to revive  ·  %.1fm" % (d - rr), 13, GOOD, big)
	# you, standing on an enemy wisp
	if p and not p.out and p.has_meta("standing_on") and m.time - float(p.get_meta("standing_at", -9.0)) < 0.15:
		var o2 = p.get_meta("standing_on")
		if is_instance_valid(o2) and (o2 as Hunter).downed:
			var sz := c.size
			var s := "Standing on %s  ·  they drain %.1fx faster and can barely move" % [(o2 as Hunter).pname, Life.R["stomp_mult"]]
			var w := body.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			_rounded(Rect2(Vector2(sz.x * 0.5 - w * 0.5 - 14, sz.y * 0.5 + 70), Vector2(w + 28, 28)), Color(0.12, 0.02, 0.02, 0.85), 8, Color(1, 0.3, 0.2, 0.7), 2)
			_ctext(Vector2(sz.x * 0.5, sz.y * 0.5 + 89), s, 15, Color("ff8a7a"))
	# deathbox revives in progress
	for b in m.boxes:
		if m.time - float(b.get("rev_at", -9.0)) > 0.15 or m.cam.is_position_behind(b["pos"]):
			continue
		var by = b.get("rev_by")
		_ground_ring(b["pos"], 1.6, Color(GOOD, 0.3), 2.0)
		_ground_ring(b["pos"], 1.6, Color(GOOD, 0.95), 5.0, float(b.get("rev_prog", 0.0)))
		var bp := m.cam.unproject_position(b["pos"] + Vector3(0, 2.0, 0))
		var o3: Hunter = b["owner"]
		_ctext(bp, "%s bringing back %s  %d%%" % [(by as Hunter).pname if is_instance_valid(by) else "Someone", o3.pname, int(float(b.get("rev_prog", 0.0)) * 100.0)], 12, GOOD, big)

## A soft coloured glow round the screen edges (danger to you).
func _edge_pulse(sz: Vector2, col: Color, a: float) -> void:
	var bands := 6
	for i in bands:
		var t := float(i) / bands
		var w := 70.0 * (1.0 - t)
		var cc := Color(col, a * (1.0 - t) * 0.35)
		c.draw_rect(Rect2(Vector2.ZERO, Vector2(sz.x, w)), cc)
		c.draw_rect(Rect2(Vector2(0, sz.y - w), Vector2(sz.x, w)), cc)
		c.draw_rect(Rect2(Vector2.ZERO, Vector2(w, sz.y)), cc)
		c.draw_rect(Rect2(Vector2(sz.x - w, 0), Vector2(w, sz.y)), cc)

