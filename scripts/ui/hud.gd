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
	flash_t = maxf(0.0, flash_t - delta * 4.0)
	hurt_t = maxf(0.0, hurt_t - delta)
	for t in toasts.duplicate():
		t["t"] += delta
		if t["t"] > 1.8: toasts.erase(t)
	if tips.size() > 0:
		tips[0]["t"] += delta
		if tips[0]["t"] > 7.0: tips.pop_front()
	c.queue_redraw()

func hitmarker(crit: bool) -> void:
	hit_t = 0.14
	hit_crit = crit

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
		_draw_player(sz, p)
		_draw_bar(sz, p)
		_draw_kit(sz, p)
		_draw_prompt(sz, p)
		_draw_crosshair(p)
		if p.downed:
			_draw_downed(sz, p)
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
			_bar(Rect2(sp + Vector2(-26, -2), Vector2(52, 5)), h.hp / h.max_hp, tc if not ally else GOOD)
			if h.shield > 0.0:
				_bar(Rect2(sp + Vector2(-26, 4), Vector2(52, 3)), h.shield / 60.0, Color("cfe8ff"), Color(0, 0, 0, 0))
	for mb in m.mobs:
		if mb.dead or mb.hp >= mb.max_hp or cam.is_position_behind(mb.position):
			continue
		var sp := cam.unproject_position(mb.position + Vector3(0, 1.4 if mb.mkind != "brute" else 2.4, 0))
		_bar(Rect2(sp + Vector2(-20, 0), Vector2(40, 4)), mb.hp / mb.max_hp, Color("ff8a6a"))
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
	var s := 200.0
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

func _draw_player(sz: Vector2, p: Hunter) -> void:
	var r := Rect2(Vector2(18, sz.y - 150 - (96.0 if _narrow(sz) else 0.0)), Vector2(330, 132))
	_panel(r, PANEL, 14)
	var cls_n: String = String(Data.HEROES[p.hero]["name"]) + " · " + String(Data.CLASSES[p.cls]["name"])
	_text(r.position + Vector2(16, 28), p.pname, 20, INK, big)
	if p.lives < 50:
		var hearts := "♥".repeat(maxi(0, p.lives))
		var hw := body.get_string_size(hearts, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		_text(r.position + Vector2(r.size.x - hw - 14, 26), hearts, 16, Color("ff7a8a"))
	_text(r.position + Vector2(16 + big.get_string_size(p.pname, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 10, 27), cls_n + " · " + String(p.wpn["name"]), 13, MUTED)
	var frac := p.hp / p.max_hp
	bar_lerp = lerpf(bar_lerp, frac, 0.08)
	var hb := Rect2(r.position + Vector2(16, 38), Vector2(298, 14))
	c.draw_rect(hb, Color(0, 0, 0, 0.5))
	c.draw_rect(Rect2(hb.position, Vector2(hb.size.x * bar_lerp, hb.size.y)), Color("ffd6a0"))
	c.draw_rect(Rect2(hb.position, Vector2(hb.size.x * frac, hb.size.y)), GOOD if frac > 0.35 else BAD)
	if p.shield > 0.0:
		c.draw_rect(Rect2(hb.position + Vector2(0, -4), Vector2(hb.size.x * p.shield / 60.0, 3)), Color("cfe8ff"))
	var hp_txt := "%d / %d" % [int(ceil(p.hp)), int(p.max_hp)]
	_text(hb.position + Vector2(hb.size.x - body.get_string_size(hp_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x - 6, 12), hp_txt, 12, INK)
	# carried loot
	_text(r.position + Vector2(16, 74), "Carrying", 12, MUTED)
	var seeds := 0
	for s in p.seeds: seeds += int(p.seeds[s])
	_text(r.position + Vector2(76, 74), "%d gems · %d seeds · %d kin caught" % [p.gems, seeds, p.caught.size()], 13, GOLD if p.gems > 0 else INK)
	# kin card
	var k: Kin = p.kin
	if k:
		var kr := Rect2(r.position + Vector2(12, 86), Vector2(306, 38))
		c.draw_circle(kr.position + Vector2(18, 19), 15, Data.KIN[k.species]["color"])
		c.draw_circle(kr.position + Vector2(13, 16), 2.5, Color.BLACK)
		c.draw_circle(kr.position + Vector2(23, 16), 2.5, Color.BLACK)
		var kname: String = k.rec.get("name", "Kin")
		_text(kr.position + Vector2(42, 14), kname, 15, INK, big)
		var st := ""
		match k.state:
			"shoulder": st = ("On your shoulder: " + Data.SHOULDER[Data.KIN[k.species]["shoulder"]]["name"]) if k.settle >= 1.0 else "Settling in..."
			"flying", "flying_home": st = "In the air"
			"active": st = "Fighting" if k.target else "Out with you"
			"returning": st = "Coming back"
			"fainted": st = "Resting %ds" % int(ceil(k.faint_t))
			"reviving": st = "Reviving you!"
		_text(kr.position + Vector2(42 + big.get_string_size(kname, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 8, 14), st, 12, MUTED)
		_bar(Rect2(kr.position + Vector2(42, 22), Vector2(170, 6)), k.hp / k.max_hp, Data.KIN[k.species]["color"])
		# trust
		_text(kr.position + Vector2(222, 30), "Trust %d" % int(k.trust), 12, Color("ffb3c6"))
		if k.state == "shoulder" and k.settle < 1.0:
			_bar(Rect2(kr.position + Vector2(42, 30), Vector2(170, 3)), k.settle, Color("ffe7a8"), Color(0, 0, 0, 0.3))

func _slot(pos: Vector2, key: String, label: String, frac_cd: float, center: String, ready: bool, col: Color, sub := "") -> void:
	var r := Rect2(pos, Vector2(64, 64))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.11, 0.82)
	sb.set_corner_radius_all(12)
	sb.border_color = col if ready else Color(1, 1, 1, 0.1)
	sb.set_border_width_all(2)
	c.draw_style_box(sb, r)
	if frac_cd > 0.0:
		c.draw_rect(Rect2(r.position + Vector2(2, 2), Vector2(60, 60 * clampf(frac_cd, 0.0, 1.0))), Color(0, 0, 0, 0.5))
	_ctext(r.position + Vector2(32, 38), center, 20 if center.length() <= 3 else 14, INK if ready else MUTED, big)
	_ctext(r.position + Vector2(32, 58), label, 11, MUTED)
	var kw := big.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var kr := Rect2(r.position + Vector2(-4, -10), Vector2(kw + 10, 18))
	var ks := StyleBoxFlat.new(); ks.bg_color = col.darkened(0.2) if ready else Color(0.25, 0.27, 0.33); ks.set_corner_radius_all(5)
	c.draw_style_box(ks, kr)
	c.draw_string(big, kr.position + Vector2(5, 14), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.07, 0.06, 0.08))
	if sub != "":
		_ctext(r.position + Vector2(32, 18), sub, 11, col)

func _draw_bar(sz: Vector2, p: Hunter) -> void:
	var slots := 9
	var total := slots * 72.0
	var x := sz.x * 0.5 - total * 0.5 + 40.0
	var y := sz.y - 86.0
	var k: Kin = p.kin
	# weapon
	var ammo_txt := "%d/%d" % [p.ammo, int(p.wpn["mag"])]
	var reload_f := p.reload_t / float(p.wpn["reload"]) if p.reload_t > 0.0 else 0.0
	_slot(Vector2(x, y), Settings.key_cap("fire"), String(p.wpn["name"]).split(" ")[0], reload_f, "..." if p.reload_t > 0.0 else ammo_txt, p.ammo > 0 and p.reload_t <= 0.0, Color("ffe7a8")); x += 72
	# dash charges
	var dmax := p.max_dashes()
	_slot(Vector2(x, y), Settings.key_cap("dash"), "Dash", 1.0 - fposmod(p.dashes, 1.0) if p.dashes < dmax else 0.0, str(int(floor(p.dashes))), p.dashes >= 1.0, Color("bfe6ff")); x += 72
	_slot(Vector2(x, y), Settings.key_cap("jump"), "Jump", 0.0, "▲", p.grounded, Color("bfe6ff")); x += 72
	var hc: Color = Data.HEROES[p.hero]["color"]
	var e_ab: Dictionary = Data.ABIL[Abil.e_id(p)]
	_slot(Vector2(x, y), Settings.key_cap("signature"), e_ab["name"], p.sig_cd / float(e_ab["cd"]), str(int(ceil(p.sig_cd))) if p.sig_cd > 0.0 else "", p.sig_cd <= 0.0, hc); x += 72
	var r_ab: Dictionary = Data.ABIL[Abil.r_id(p)]
	var ready_r := p.ult >= 1.0
	_slot(Vector2(x, y), Settings.key_cap("ultimate"), r_ab["name"], 1.0 - p.ult, "%d%%" % int(p.ult * 100.0) if not ready_r else "★", ready_r, Color("f2c84a")); x += 72
	if ready_r:
		var pulse := 0.5 + 0.5 * sin(m.time * 6.0)
		var rr := Rect2(Vector2(x - 72, y), Vector2(64, 64)).grow(3.0 + pulse * 3.0)
		c.draw_rect(rr, Color(1.0, 0.82, 0.3, 0.25 + pulse * 0.25), false, 2.0)
	x += 10
	if k:
		var kcol: Color = Data.KIN[k.species]["color"]
		var throw_lbl := "Throw" if k.state == "shoulder" else ("Call back" if k.state in ["active", "flying"] else "—")
		_slot(Vector2(x, y), Settings.key_cap("throw"), throw_lbl, 0.0, "", k.state in ["shoulder", "active", "flying"], kcol, Data.KIN[k.species]["name"]); x += 72
		var sk: Dictionary = Data.KIN_SKILLS[Data.KIN[k.species]["skill"]]
		_slot(Vector2(x, y), Settings.key_cap("kin_skill"), sk["name"].split(" ")[-1], k.skill_cd / float(sk["cd"]), str(int(ceil(k.skill_cd))) if k.skill_cd > 0.0 else "", k.skill_cd <= 0.0 and k.state not in ["fainted", "reviving"], kcol); x += 72
	x += 10
	_slot(Vector2(x, y), Settings.key_cap("tonic"), "Tonic", 0.0, "×%d" % p.tonics, p.tonics > 0, GOOD)

## For the first seconds of every match: what each of your buttons does.
func _draw_kit(sz: Vector2, p: Hunter) -> void:
	if not Settings.get_v("tips") or m.opts.get("tutorial", false) or p.out:
		return
	var show_t := 14.0 if not m.opts.get("training", false) else 1e9
	var t := m.time - kit_t0
	if p.dropping:
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
	var box := Rect2(Vector2(sz.x - w - 16, sz.y - 120 - 16 - lines.size() * 44 - 30), Vector2(w, 30 + lines.size() * 44))
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
		_ctext(Vector2(sz.x * 0.5, y), s, 16, GOLD)
		if prog > 0.0:
			_bar(Rect2(Vector2(sz.x * 0.5 - w * 0.5 - 16, y + 12), Vector2(w + 32, 4)), prog, GOLD)
	if p.extract_prog > 0.0:
		_ctext(Vector2(sz.x * 0.5, sz.y * 0.36), "Extracting...", 26, Color("8fe3c8"), big)
		_bar(Rect2(Vector2(sz.x * 0.5 - 120, sz.y * 0.36 + 12), Vector2(240, 8)), p.extract_prog, Color("8fe3c8"))

func _draw_crosshair(p: Hunter) -> void:
	var mp := c.get_local_mouse_position()
	var col := INK
	var gap := 6.0 + (p.recoil * 6.0)
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		c.draw_line(mp + d * gap, mp + d * (gap + 7.0), Color(0, 0, 0, 0.6), 4.0)
		c.draw_line(mp + d * gap, mp + d * (gap + 7.0), col, 2.0)
	c.draw_circle(mp, 1.6, col)
	if p.reload_t > 0.0:
		_arc(mp, 18, 1.0 - p.reload_t / float(p.wpn["reload"]), Color("ffe7a8"), 3.0)
	if hit_t > 0.0:
		var hc := Color("ffd23f") if hit_crit else Color.WHITE
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
	var w := 76.0
	var frac := clampf(p.hp / p.max_hp, 0.0, 1.0)
	head_hp = lerpf(head_hp, frac, 0.08)
	var hr := Rect2(sp + Vector2(-w * 0.5, 0), Vector2(w, 8))
	c.draw_rect(hr.grow(2), Color(0.04, 0.04, 0.06, 0.75))
	c.draw_rect(Rect2(hr.position, Vector2(w * head_hp, 8)), Color("ffd6a0"))
	c.draw_rect(Rect2(hr.position, Vector2(w * frac, 8)), GOOD if frac > 0.35 else BAD)
	if p.shield > 0.0:
		c.draw_rect(Rect2(hr.position + Vector2(0, -4), Vector2(w * clampf(p.shield / 60.0, 0.0, 1.0), 3)), Color("cfe8ff"))
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
	# glider cloth left, shown while gliding or recharging
	if p.gliding or p.glide_fuel < 0.999:
		var gr := Rect2(sp + Vector2(-w * 0.5, -8), Vector2(w, 3))
		c.draw_rect(gr.grow(1.0), Color(0.04, 0.04, 0.06, 0.6))
		var gcol := Color("f3eee2") if p.glide_fuel > 0.25 else Color("ff9a7a")
		c.draw_rect(Rect2(gr.position, Vector2(w * p.glide_fuel, 3)), gcol if p.gliding else Color(gcol, 0.5))
