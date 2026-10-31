class_name FullMap
extends RefCounted
## The full map (M), as in SUPERVIVE: a big overlay of the whole map with the regions and places named,
## the exits and what they're doing, the train loop, your squad and their pings, enemies your squad can
## see right now, and the match's random spawns (see SpawnPlan) with a legend. Click to ping, right click
## to take your ping down, wheel to zoom, drag to pan. It opens by itself for the planning phase before
## the drop, with the countdown and the squad's drop order. The match keeps going behind it.

const SIDE_W := 268.0
const INK := Color("f3eee2")
const MUTED := Color("a9b0bf")
const GOLD := Color("f2c84a")
const BAD := Color("ff5a4a")
const SEA := Color(0.05, 0.07, 0.13, 0.96)

var hud            # the Hud that draws it
var m: Match
var is_open := false
var auto := false              # opened by the planning phase (closes when the ship sets off)
var zoom := 1.0
var center := Vector2.ZERO     # the world point (x, z) at the middle of the map
var rect := Rect2()            # where the map is on screen
var _press := Vector2.INF
var _press_center := Vector2.ZERO
var _dragged := false
var _roster: Array = []        # [Rect2, Hunter] squad rows you can click to pass the lead
var _hover: Dictionary = {}    # the spawn candidate under the cursor

func _init(h, match_node: Match) -> void:
	hud = h
	m = match_node
	center = Vector2(m.world.w, m.world.h) * 0.5

func open(by_plan := false) -> void:
	is_open = true
	auto = by_plan
	zoom = 1.0
	center = Vector2(m.world.w, m.world.h) * 0.5

func close() -> void:
	is_open = false
	auto = false
	_press = Vector2.INF

# ------------------------------------------------------------------ coordinates
func _layout(sz: Vector2) -> void:
	var top := 76.0
	var s := minf(sz.y - top - 22.0, sz.x - SIDE_W * 2.0 - 56.0)
	s = maxf(s, 300.0)
	rect = Rect2(Vector2(roundf(sz.x * 0.5 - s * 0.5), top), Vector2(s, s))

func view() -> Rect2:
	var full := Vector2(m.world.w, m.world.h)
	var vs := full / zoom
	center.x = clampf(center.x, vs.x * 0.5, full.x - vs.x * 0.5)
	center.y = clampf(center.y, vs.y * 0.5, full.y - vs.y * 0.5)
	return Rect2(center - vs * 0.5, vs)

func k() -> float:
	return rect.size.x / view().size.x

func to_screen(p3: Vector3) -> Vector2:
	var v := view()
	return rect.position + (Vector2(p3.x, p3.z) - v.position) * (rect.size.x / v.size.x)

func to_world(sp: Vector2) -> Vector3:
	var v := view()
	var q := v.position + (sp - rect.position) / (rect.size.x / v.size.x)
	return Vector3(q.x, 0, q.y)

func _zoom_at(sp: Vector2, f: float) -> void:
	var before := to_world(sp)
	zoom = clampf(zoom * f, 1.0, 4.0)
	view()
	var after := to_world(sp)
	center += Vector2(before.x - after.x, before.z - after.z)

# ------------------------------------------------------------------ input
## Mouse on the map: returns true when the map used the event.
func input(ev: InputEvent) -> bool:
	if not is_open:
		return false
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if rect.has_point(mb.position):
				_zoom_at(mb.position, 1.25 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8)
			return true
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				for rs in _roster:
					if (rs[0] as Rect2).has_point(mb.position):
						if m.skydrop and m.player: m.skydrop.pass_lead(m.player, rs[1])
						return true
				if rect.has_point(mb.position):
					_press = mb.position; _press_center = center; _dragged = false
				return true
			if _press != Vector2.INF:
				if not _dragged and rect.has_point(mb.position):
					ping_at(to_world(mb.position))
				_press = Vector2.INF
			return true
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed and m.player:
				m.unping(m.player)
			return true
		return true
	if ev is InputEventMouseMotion and _press != Vector2.INF:
		var mm := ev as InputEventMouseMotion
		if (mm.position - _press).length() > 6.0:
			_dragged = true
		if _dragged and zoom > 1.001:
			center = _press_center - (mm.position - _press) / k()
		return true
	return false

func ping_at(p: Vector3) -> void:
	if m.player == null or m.player.out:
		return
	p.x = clampf(p.x, 0.5, m.world.w - 0.5); p.z = clampf(p.z, 0.5, m.world.h - 0.5)
	m.squad_ping(m.player, p)

# ------------------------------------------------------------------ drawing
func draw(sz: Vector2) -> void:
	var c: Control = hud.c
	_layout(sz)
	var w := m.world
	var v := view()
	var kk := rect.size.x / v.size.x
	var team: int = m.player.team if m.player else -9
	c.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.01, 0.02, 0.05, 0.76))
	# the header: the planning countdown, or just the map
	var planning: bool = m.skydrop != null and m.skydrop.planning
	if planning:
		var left := maxf(0.0, m.skydrop.plan_t)
		hud._ctext(Vector2(sz.x * 0.5, 40), "PLAN YOUR DROP", 30, GOLD, hud.big)
		hud._ctext(Vector2(sz.x * 0.5, 64), "The ship sets off in %ds  ·  click the map to ping where you want to land" % int(ceil(left)), 15, INK)
		c.draw_rect(Rect2(Vector2(rect.position.x, 70), Vector2(rect.size.x, 3)), Color(1, 1, 1, 0.12))
		c.draw_rect(Rect2(Vector2(rect.position.x, 70), Vector2(rect.size.x * clampf(left / maxf(0.1, m.skydrop.plan_len), 0.0, 1.0), 3)), GOLD)
	else:
		hud._ctext(Vector2(sz.x * 0.5, 44), _map_title(), 28, INK, hud.big)
		hud._ctext(Vector2(sz.x * 0.5, 66), "Click to ping  ·  right click takes your ping down  ·  wheel zooms  ·  %s closes" % Settings.key_cap("map"), 13, MUTED)
	# the map itself
	c.draw_rect(rect.grow(6.0), Color(0, 0, 0, 0.5))
	c.draw_rect(rect, SEA)
	_grid(c, v, kk)
	var tex_view := v.intersection(Rect2(Vector2.ZERO, Vector2(w.w, w.h)))
	if tex_view.size.x > 0.0:
		c.draw_texture_rect_region(hud.minimap, Rect2(rect.position + (tex_view.position - v.position) * kk, tex_view.size * kk), tex_view)
	c.draw_rect(rect, Color(0.85, 0.8, 1.0, 0.35), false, 2.0)
	var saved: Vector3 = hud.mm_circ
	hud.mm_circ = Vector3.ZERO          # the shared map helpers clip to a rectangle here
	_labels(c, kk)
	if m.skytrain:
		hud._draw_map_train(rect, v, kk)
	if m.exits:
		var ek := clampf(0.9 + kk * 0.12, 1.0, 1.8)
		for x in m.exits.list:
			var pv := to_screen(x.get("berth", x["pos"]))
			if rect.grow(-4.0).has_point(pv):
				hud._draw_exit_icon(pv, x, ek)
				var st := _exit_word(x)
				if st != "":
					hud._ctext(pv + Vector2(0, 17.0 * ek), st, 10, Exits.color_of(x) if m.exits.live(x) else MUTED, hud.big)
	hud.mm_circ = saved
	_spawns(c, team, kk)
	_ship(c)
	_pings(c, team)
	_enemies(c, team)
	_squad(c, team)
	_legend(c, sz, team)
	_side(c, sz)
	_cursor(c)

func _map_title() -> String:
	if m.world.layout_id == "skyreach": return "SKYREACH"
	return "THE ISLANDS"

func _exit_word(x: Dictionary) -> String:
	match String(x["state"]):
		"called": return "Skiff %s" % hud._fmt(float(x["t"]))
		"boarding": return "BOARDING"
		"charging": return "Uplink %d%%" % int(float(x["prog"]) * 100.0)
		"open": return "OPEN"
		"closed": return "Closed"
	return ""

## A faint grid with letters and numbers along the edges, for callouts ("dropping C4").
func _grid(c: Control, v: Rect2, kk: float) -> void:
	var cell := m.world.w / 8.0
	for i in range(1, 8):
		var x := rect.position.x + (i * cell - v.position.x) * kk
		var y := rect.position.y + (i * cell - v.position.y) * kk
		if x > rect.position.x and x < rect.end.x:
			c.draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), Color(1, 1, 1, 0.05), 1.0)
		if y > rect.position.y and y < rect.end.y:
			c.draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Color(1, 1, 1, 0.05), 1.0)
	for i in 8:
		var cx := rect.position.x + ((i + 0.5) * cell - v.position.x) * kk
		var cy := rect.position.y + ((i + 0.5) * cell - v.position.y) * kk
		if cx > rect.position.x + 6 and cx < rect.end.x - 6:
			hud._ctext(Vector2(cx, rect.position.y + 13), "ABCDEFGH"[i], 11, Color(1, 1, 1, 0.3), hud.big)
		if cy > rect.position.y + 6 and cy < rect.end.y - 6:
			hud._text(Vector2(rect.position.x + 5, cy + 4), str(i + 1), 11, Color(1, 1, 1, 0.3), hud.big)

## Region and place names (authored maps); on generated maps each island's role.
func _labels(c: Control, kk: float) -> void:
	var w := m.world
	var big_k := clampf(kk / (rect.size.x / w.w), 1.0, 2.0)
	for lb in w.labels:
		var pv := to_screen(lb["pos"])
		if not rect.grow(-8.0).has_point(pv):
			continue
		var nm := String(lb["name"])
		match String(lb["kind"]):
			"perch":
				c.draw_colored_polygon(PackedVector2Array([pv + Vector2(0, -9), pv + Vector2(7, 4), pv + Vector2(-7, 4)]), Color(0, 0, 0, 0.6))
				c.draw_colored_polygon(PackedVector2Array([pv + Vector2(0, -7), pv + Vector2(5, 2.5), pv + Vector2(-5, 2.5)]), Color("9af0ff"))
				hud._ctext(pv + Vector2(0, 17), "%s  %dm" % [nm, int(round(float(lb.get("height", 0.0))))], 10, Color("c8f6ff"))
			"rail":
				c.draw_rect(Rect2(pv - Vector2(4, 4), Vector2(8, 8)), Color(0, 0, 0, 0.6))
				c.draw_rect(Rect2(pv - Vector2(3, 3), Vector2(6, 6)), Color("ffcf7a"))
				if kk > rect.size.x / w.w * 1.4:
					hud._ctext(pv + Vector2(0, 15), nm, 10, Color("ffe2b0"))
			"choke":
				c.draw_colored_polygon(PackedVector2Array([pv + Vector2(0, -5), pv + Vector2(5, 0), pv + Vector2(0, 5), pv + Vector2(-5, 0)]), Color(0, 0, 0, 0.55))
				c.draw_colored_polygon(PackedVector2Array([pv + Vector2(0, -3.5), pv + Vector2(3.5, 0), pv + Vector2(0, 3.5), pv + Vector2(-3.5, 0)]), Color("ffb36a"))
				hud._ctext(pv + Vector2(0, 15), nm, 10, Color(1.0, 0.82, 0.63, 0.85))
			_:
				# a region (an island's own name) big, a place inside it smaller
				var region := false
				for isl in w.islands:
					if String(isl.get("name", "")) == nm: region = true; break
				var col := Color("ffd2f0") if String(lb.get("role", "")) == "heart" else INK
				hud._ctext(pv + Vector2(0, 5), nm.to_upper() if region else nm, int((17 if region else 11) * big_k), col if region else Color(INK, 0.8), hud.big)
	if w.labels.is_empty():
		for isl in w.islands:
			var cc: Vector2 = isl["c"]
			var pv2 := to_screen(Vector3(cc.x, 0, cc.y))
			if rect.has_point(pv2):
				hud._ctext(pv2, String(isl["role"]).capitalize(), 11, Color(INK, 0.6), hud.big)

func _spawns(c: Control, team: int, kk: float) -> void:
	_hover = {}
	var sp: SpawnPlan = m.spawn_plan
	if sp == null:
		return
	var mp := c.get_local_mouse_position()
	var s := clampf(6.0 + kk * 0.6, 7.0, 12.0)
	for cnd in sp.cands:
		var pv := to_screen(cnd["pos"])
		if not rect.grow(-6.0).has_point(pv):
			continue
		var def: Dictionary = sp.cats.get(cnd["cat"], {})
		var st := sp.state_for(cnd, team)
		var col: Color = def.get("col", Color.WHITE)
		marker(c, String(def.get("shape", "star")), pv, s, col, st)
		if pv.distance_to(mp) < s + 4.0:
			_hover = cnd
	if not _hover.is_empty():
		var def: Dictionary = sp.cats.get(_hover["cat"], {})
		var st := sp.state_for(_hover, team)
		var line := String(def.get("name", "?"))
		if String(_hover["name"]) != "": line += "  ·  " + String(_hover["name"])
		var what: String = {"unknown": "Might be here: scout it to find out", "active": "Here this match", "empty": "Nothing here this match", "taken": "Already taken"}[st]
		var pv := to_screen(_hover["pos"])
		var wv := maxf(hud.big.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x, hud.body.get_string_size(what, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x) + 20.0
		var r := Rect2(pv + Vector2(14, -42), Vector2(wv, 44))
		if r.end.x > rect.end.x: r.position.x = pv.x - 14 - wv
		hud._rounded(r, Color(0.04, 0.05, 0.08, 0.92), 8, Color(def.get("col", Color.WHITE), 0.5), 1)
		hud._text(r.position + Vector2(10, 19), line, 14, def.get("col", Color.WHITE), hud.big)
		hud._text(r.position + Vector2(10, 36), what, 12, INK)

## A spawn marker in one of its states: "unknown" (faint, with a ?), "active", "empty" (a cross),
## "taken" (a tick). Shared with the legend.
func marker(c: Control, shape: String, pv: Vector2, s: float, col: Color, st: String) -> void:
	var a := 1.0
	var ic := col
	match st:
		"unknown": a = 0.5; ic = Color(col, 0.55)
		"empty": a = 0.4; ic = Color(0.6, 0.62, 0.68, 0.5)
		"taken": a = 0.55; ic = Color(0.7, 0.72, 0.78, 0.7)
	if st == "active":
		var ph := fmod(Time.get_ticks_msec() / 1000.0 * 0.8, 1.0)
		c.draw_arc(pv, s * (1.5 + ph * 0.9), 0, TAU, 28, Color(col, 0.6 * (1.0 - ph)), 2.0, true)
	c.draw_circle(pv, s * 1.35, Color(0, 0, 0, 0.6 * a + 0.1))
	c.draw_arc(pv, s * 1.35, 0, TAU, 24, Color(ic, 0.9 if st == "active" else 0.45), 1.5, true)
	icon(c, shape, pv, s * 0.78, ic)
	match st:
		"unknown":
			hud._ctext(pv + Vector2(s * 1.15, -s * 0.55), "?", int(s * 1.5), Color(1, 1, 1, 0.85), hud.big)
		"empty":
			c.draw_line(pv + Vector2(-s, -s), pv + Vector2(s, s), Color(BAD, 0.75), 2.0)
			c.draw_line(pv + Vector2(-s, s), pv + Vector2(s, -s), Color(BAD, 0.75), 2.0)
		"taken":
			c.draw_polyline(PackedVector2Array([pv + Vector2(-s * 0.7, 0), pv + Vector2(-s * 0.15, s * 0.6), pv + Vector2(s * 0.85, -s * 0.7)]), Color("8fe0a0"), 2.5, true)

## Category icons: a paw (rare kin), a chest (vault), a crate (cache), a skull (boss lair), else a star.
func icon(c: Control, shape: String, p: Vector2, s: float, col: Color) -> void:
	match shape:
		"paw":
			Icons.draw(c, "paw", p, s, col)
		"vault":
			c.draw_rect(Rect2(p + Vector2(-s, -s * 0.2), Vector2(s * 2.0, s * 1.1)), col)
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(-s, -s * 0.3), p + Vector2(-s * 0.8, -s * 0.85), p + Vector2(s * 0.8, -s * 0.85), p + Vector2(s, -s * 0.3)]), col)
			c.draw_rect(Rect2(p + Vector2(-s * 0.2, -s * 0.45), Vector2(s * 0.4, s * 0.5)), Color(0, 0, 0, 0.7))
		"crate":
			var r := Rect2(p - Vector2(s, s) * 0.85, Vector2(s, s) * 1.7)
			c.draw_rect(r, col, false, maxf(1.5, s * 0.28))
			c.draw_line(r.position, r.end, col, maxf(1.2, s * 0.2))
			c.draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y), col, maxf(1.2, s * 0.2))
		"skull":
			c.draw_circle(p + Vector2(0, -s * 0.15), s * 0.85, col)
			c.draw_rect(Rect2(p + Vector2(-s * 0.5, s * 0.35), Vector2(s, s * 0.55)), col)
			c.draw_circle(p + Vector2(-s * 0.32, -s * 0.15), s * 0.24, Color(0, 0, 0, 0.85))
			c.draw_circle(p + Vector2(s * 0.32, -s * 0.15), s * 0.24, Color(0, 0, 0, 0.85))
		_:
			var pts := PackedVector2Array()
			for i in 10:
				var a := -PI * 0.5 + TAU * i / 10.0
				pts.append(p + Vector2(cos(a), sin(a)) * s * (1.0 if i % 2 == 0 else 0.45))
			c.draw_colored_polygon(pts, col)

func _ship(c: Control) -> void:
	if m.ship.is_empty() or m.ship.get("gone", false):
		return
	var a := to_screen(m.ship["a"]); var b := to_screen(m.ship["b"])
	var L := a.distance_to(b)
	var d := 0.0
	while d < L:
		c.draw_line(a.lerp(b, d / L), a.lerp(b, minf(1.0, (d + 8.0) / L)), Color(1, 1, 1, 0.35), 2.0, true)
		d += 14.0
	var sp := to_screen(m.ship_pos())
	var dir: Vector3 = m.ship["dir"]
	var fw := Vector2(dir.x, dir.z).normalized(); var sd := Vector2(-fw.y, fw.x)
	sp = Vector2(clampf(sp.x, rect.position.x + 8, rect.end.x - 8), clampf(sp.y, rect.position.y + 8, rect.end.y - 8))
	c.draw_colored_polygon(PackedVector2Array([sp + fw * 13.0, sp - fw * 8.0 + sd * 8.0, sp - fw * 4.0, sp - fw * 8.0 - sd * 8.0]), Color(0, 0, 0, 0.6))
	c.draw_colored_polygon(PackedVector2Array([sp + fw * 11.0, sp - fw * 6.0 + sd * 6.5, sp - fw * 3.0, sp - fw * 6.0 - sd * 6.5]), GOLD)
	hud._ctext(sp + Vector2(0, -14), "SKYSHIP", 10, GOLD, hud.big)

func _pings(c: Control, team: int) -> void:
	for pg in m.pings:
		var pt = pg.get("team", null)
		if pt != null and int(pt) != team:
			continue
		var pv := to_screen(pg["pos"])
		if not rect.has_point(pv):
			continue
		var col: Color = pg["col"]
		if pg.has("by"):
			# a squad ping: a pin with the pinger's initial
			var by: Hunter = pg["by"]
			var bob := sin(Time.get_ticks_msec() / 1000.0 * 4.0) * 2.0
			var tip := pv
			var head := pv + Vector2(0, -20 + bob)
			c.draw_arc(tip, 9.0, 0, TAU, 24, Color(col, 0.7), 2.0, true)
			c.draw_colored_polygon(PackedVector2Array([tip, head + Vector2(-8, 3), head + Vector2(8, 3)]), Color(0, 0, 0, 0.6))
			c.draw_circle(head, 10.0, Color(0, 0, 0, 0.6))
			c.draw_circle(head, 8.0, col)
			c.draw_colored_polygon(PackedVector2Array([tip + Vector2(0, -2), head + Vector2(-6, 4), head + Vector2(6, 4)]), col)
			hud._ctext(head + Vector2(0, 5), by.pname.substr(0, 1).to_upper() if is_instance_valid(by) else "?", 12, Color(0.06, 0.06, 0.1), hud.big)
		else:
			var a := clampf(4.0 - float(pg["t"]), 0.0, 1.0)
			c.draw_arc(pv, 6.0 + sin(float(pg["t"]) * 8.0) * 1.5, 0, TAU, 20, Color(col, a), 2.0, true)
			c.draw_circle(pv, 3.0, Color(col, a))

## Rivals your squad can see right now (nobody else: the map is no wallhack), and betrayers.
func _enemies(c: Control, team: int) -> void:
	if m.player == null:
		return
	for h in m.hunters:
		if h.team == team or h.out or h.extracted or h.riding:
			continue
		var marked: bool = m.truce != null and m.truce.is_marked(h)
		if not marked and not m.can_see(team, h):
			continue
		var pv := to_screen(h.pos)
		if not rect.has_point(pv):
			continue
		var allied: bool = m.truce != null and m.truce.allied(team, h.team)
		c.draw_circle(pv, 6.0, Color(0, 0, 0, 0.6))
		c.draw_circle(pv, 4.5, Color("f4f1e6") if allied and not marked else BAD)

func _squad(c: Control, team: int) -> void:
	for h in m.hunters:
		if m.player == null or h.team != team or h.out or h.extracted:
			continue
		var at: Vector3 = h.pos if not h.riding else m.ship_pos()
		var pv := to_screen(at)
		if not rect.has_point(pv):
			continue
		var col := m.mate_col(h)
		if h == m.player and not h.riding:
			var d: Vector2 = h.aim_dir() if not h.dropping else Vector2(h.vel.x, h.vel.z).normalized()
			if d.length() < 0.1: d = Vector2.UP
			var side := Vector2(-d.y, d.x)
			c.draw_colored_polygon(PackedVector2Array([pv + d * 12.0, pv - d * 6.0 + side * 8.0, pv - d * 3.0, pv - d * 6.0 - side * 8.0]), Color(0, 0, 0, 0.7))
			c.draw_colored_polygon(PackedVector2Array([pv + d * 10.0, pv - d * 5.0 + side * 6.5, pv - d * 2.5, pv - d * 5.0 - side * 6.5]), INK)
		elif not h.riding:
			c.draw_circle(pv, 6.5, Color(0, 0, 0, 0.6))
			c.draw_circle(pv, 5.0, col)
			hud._ctext(pv + Vector2(0, -9), h.pname.substr(0, 1), 12, col, hud.big)
		if m.skydrop and m.skydrop.is_lead(h) and (h.riding or h.dropping):
			crown(c, pv + Vector2(0, -20 if not h.riding else -24), col if h != m.player else GOLD)

func crown(c: Control, p: Vector2, col: Color) -> void:
	var pts := PackedVector2Array([p + Vector2(-7, 4), p + Vector2(-7, -3), p + Vector2(-3.5, 0), p + Vector2(0, -5), p + Vector2(3.5, 0), p + Vector2(7, -3), p + Vector2(7, 4)])
	var back := PackedVector2Array()
	for q in pts: back.append(p + (q - p) * 1.3)
	c.draw_colored_polygon(back, Color(0, 0, 0, 0.6))
	c.draw_colored_polygon(pts, col)

## The match hides the system cursor (it draws its own crosshair), so the map draws its own too.
func _cursor(c: Control) -> void:
	var mp := c.get_local_mouse_position()
	if not rect.has_point(mp):
		var arrow := PackedVector2Array([mp, mp + Vector2(0, 17), mp + Vector2(4.5, 13), mp + Vector2(8, 20), mp + Vector2(10.5, 19), mp + Vector2(7.5, 12), mp + Vector2(13, 12)])
		var back := PackedVector2Array()
		for q in arrow: back.append(mp + (q - mp) * 1.18 + Vector2(-1, -1.5))
		c.draw_colored_polygon(back, Color(0, 0, 0, 0.8))
		c.draw_colored_polygon(arrow, INK)
		return
	var col := m.mate_col(m.player) if m.player else INK
	c.draw_arc(mp, 9.0, 0, TAU, 24, Color(col, 0.8), 1.5, true)
	c.draw_line(mp + Vector2(-14, 0), mp + Vector2(-5, 0), col, 1.5)
	c.draw_line(mp + Vector2(5, 0), mp + Vector2(14, 0), col, 1.5)
	c.draw_line(mp + Vector2(0, -14), mp + Vector2(0, -5), col, 1.5)
	c.draw_line(mp + Vector2(0, 5), mp + Vector2(0, 14), col, 1.5)
	if m.player:
		var wp := to_world(mp)
		var dist := int(round(Vector2(wp.x - m.player.pos.x, wp.z - m.player.pos.z).length()))
		hud._text(mp + Vector2(14, 22), "%dm" % dist, 12, Color(INK, 0.8), hud.big)

## The legend, right of the map: every spawn category on this map and how much your squad knows.
func _legend(c: Control, sz: Vector2, team: int) -> void:
	var x0 := rect.end.x + 22.0
	var wv := minf(SIDE_W, sz.x - x0 - 14.0)
	if wv < 150.0:
		return
	var sp: SpawnPlan = m.spawn_plan
	var cats: Array = sp.shown_cats() if sp else []
	var rows := cats.size()
	var r := Rect2(Vector2(x0, rect.position.y), Vector2(wv, 66 + rows * 46 + 138))
	hud._rounded(r, Color(0.04, 0.05, 0.08, 0.88), 12)
	hud._text(r.position + Vector2(14, 26), "THIS MATCH", 16, GOLD, hud.big)
	hud._text(r.position + Vector2(14, 44), "Same map every time, different spawns", 11, MUTED)
	var y := r.position.y + 72.0
	for cat in cats:
		var def: Dictionary = sp.cats[cat]
		var col: Color = def.get("col", Color.WHITE)
		var all: Array = sp.of(cat)
		var live := 0; var found := 0; var gone := 0
		for cnd in all:
			if cnd["active"]: live += 1
			var st := sp.state_for(cnd, team)
			if st == "active": found += 1
			elif st == "taken": gone += 1
		var announce: bool = def.get("announce", false)
		marker(c, String(def.get("shape", "star")), Vector2(r.position.x + 26, y), 8.0, col, "active" if announce or found > 0 else "unknown")
		hud._text(Vector2(r.position.x + 48, y - 2), String(def.get("name", cat)), 15, col, hud.big)
		var line := ("%d here this match%s" % [live, ("  ·  %d taken" % gone) if gone > 0 else ""]) if announce else ("%d possible spots  ·  %d found" % [all.size(), found + gone])
		hud._text(Vector2(r.position.x + 48, y + 15), line, 11, INK)
		y += 46.0
	# what the marks mean
	y += 4.0
	c.draw_line(Vector2(r.position.x + 14, y - 14), Vector2(r.end.x - 14, y - 14), Color(1, 1, 1, 0.08), 1.0)
	var keyrows := [["unknown", "Could be there: scout it"], ["active", "Here this match"], ["empty", "Empty this match"], ["taken", "Taken"]]
	for kr in keyrows:
		marker(c, "star", Vector2(r.position.x + 26, y), 6.0, Color("d8d4ff"), String(kr[0]))
		hud._text(Vector2(r.position.x + 48, y + 4), String(kr[1]), 12, INK)
		y += 22.0
	hud._text(Vector2(r.position.x + 14, y + 6), "Vaults and lairs are known to all.", 11, MUTED)
	hud._text(Vector2(r.position.x + 14, y + 20), "The rest show up once your squad sees them.", 11, MUTED)
	# exits, under the spawns
	var r2 := Rect2(Vector2(x0, r.end.y + 10), Vector2(wv, 104))
	if r2.end.y < sz.y - 10 and m.exits:
		hud._rounded(r2, Color(0.04, 0.05, 0.08, 0.88), 12)
		hud._text(r2.position + Vector2(14, 22), "WAYS OUT", 14, Color("8fe3c8"), hud.big)
		var ex := [["dock", "Skiff dock (loud)"], ["outpost", "Uplink outpost"], ["hatch", "Rift hatch (needs a key)"]]
		for i in ex.size():
			var fake := {"kind": ex[i][0], "state": "idle", "prog": 0.0}
			var col := Exits.color_of(fake)
			_exit_glyph(c, String(ex[i][0]), Vector2(r2.position.x + 26, r2.position.y + 42 + i * 22), col)
			hud._text(Vector2(r2.position.x + 48, r2.position.y + 47 + i * 22), String(ex[i][1]), 12, INK)

func _exit_glyph(c: Control, kind: String, pv: Vector2, col: Color) -> void:
	match kind:
		"dock":
			c.draw_colored_polygon(PackedVector2Array([pv + Vector2(-6, 1), pv + Vector2(6, 1), pv + Vector2(4, 5), pv + Vector2(-4, 5)]), col)
			c.draw_colored_polygon(PackedVector2Array([pv + Vector2(0, -7), pv + Vector2(5, 0), pv + Vector2(0, 0)]), col)
		"hatch":
			c.draw_colored_polygon(PackedVector2Array([pv + Vector2(0, -5), pv + Vector2(5, 0), pv + Vector2(0, 5), pv + Vector2(-5, 0)]), col)
		"outpost":
			c.draw_rect(Rect2(pv - Vector2(5.5, 5.5), Vector2(11, 11)), col, false, 2.0)
			c.draw_circle(pv, 2.2, col)

## Left of the map: your squad, who leads the drop, and the keys for it.
func _side(c: Control, sz: Vector2) -> void:
	_roster.clear()
	var p: Hunter = m.player
	if p == null:
		return
	var wv := minf(SIDE_W, rect.position.x - 36.0)
	if wv < 150.0:
		return
	var x0 := rect.position.x - 22.0 - wv
	var squad: Array = m.hunters.filter(func(x): return x.team == p.team)
	var in_drop: bool = p.riding or p.dropping
	var r := Rect2(Vector2(x0, rect.position.y), Vector2(wv, 48 + squad.size() * 44 + (118 if in_drop else 40)))
	hud._rounded(r, Color(0.04, 0.05, 0.08, 0.88), 12)
	hud._text(r.position + Vector2(14, 26), "YOUR SQUAD", 16, GOLD, hud.big)
	var y := r.position.y + 50.0
	var i_lead: bool = m.skydrop != null and m.skydrop.is_lead(p)
	for h in squad:
		var row := Rect2(Vector2(r.position.x + 8, y), Vector2(wv - 16, 38))
		var col := m.mate_col(h)
		var lead: bool = m.skydrop != null and m.skydrop.is_lead(h)
		var can_pass: bool = i_lead and h != p and in_drop and (h.riding if p.riding else (h.dropping and h.drop_follow == p))
		var hov := can_pass and row.has_point(c.get_local_mouse_position())
		hud._rounded(row, Color(1, 1, 1, 0.1 if hov else 0.04), 8, Color(col, 0.5 if hov else 0.0), 1 if hov else 0)
		c.draw_circle(row.position + Vector2(18, 19), 9.0, col)
		hud._ctext(row.position + Vector2(18, 24), h.pname.substr(0, 1).to_upper(), 13, Color(0.06, 0.06, 0.1), hud.big)
		hud._text(row.position + Vector2(34, 17), h.pname.substr(0, 14) + ("  (you)" if h == p else ""), 14, INK if not h.out else MUTED, hud.big)
		var sub := ""
		if h.out: sub = "Out"
		elif h.extracted: sub = "Extracted"
		elif lead and in_drop: sub = "Drop leader"
		elif h.drop_solo and (h.riding or h.dropping): sub = "Dropping solo"
		elif h.riding or h.dropping: sub = "Following the leader"
		var pg: Dictionary = {}
		for q in m.pings:
			if q.get("by") == h: pg = q
		if not pg.is_empty() and not h.out:
			sub += ("  ·  " if sub != "" else "") + "pinged %s" % _grid_ref(pg["pos"])
		hud._text(row.position + Vector2(34, 32), sub, 11, GOLD if lead and in_drop else MUTED)
		if lead and in_drop:
			crown(c, Vector2(row.end.x - 18, row.position.y + 18), GOLD)
		elif can_pass:
			hud._text(Vector2(row.end.x - 74, row.position.y + 24), "make leader", 11, Color(col, 0.9 if hov else 0.6))
			_roster.append([row, h])
		y += 44.0
	if in_drop and m.skydrop:
		y += 6.0
		var keys: Array = []
		if i_lead:
			keys = [["jump", "Jump (the squad jumps with you)" if p.riding else "Glider: you steer the squad"], ["pass_lead", "Pass the lead"]]
		elif p.drop_solo:
			keys = [["jump", "Jump" if p.riding else "Glide on your own"]]
		else:
			keys = [["separate", "Separate and drop solo"]]
		for kk in keys:
			var cap := Settings.key_cap(String(kk[0]))
			var kr := Rect2(Vector2(r.position.x + 14, y), Vector2(maxf(28.0, hud.big.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 14.0), 24))
			hud._rounded(kr, Color(1, 1, 1, 0.12), 5, Color(1, 1, 1, 0.3), 1)
			hud._ctext(kr.get_center() + Vector2(0, 5), cap, 13, INK, hud.big)
			hud._text(Vector2(kr.end.x + 8, y + 17), String(kk[1]), 12, INK)
			y += 30.0
		if i_lead and squad.size() > 1:
			hud._text(Vector2(r.position.x + 14, y + 10), "or click a squadmate to make them leader", 11, MUTED)
	else:
		hud._text(Vector2(r.position.x + 14, y + 14), "Pings last %ds" % int(Match.SQUAD_PING_T), 11, MUTED)

func _grid_ref(p: Vector3) -> String:
	var cell := m.world.w / 8.0
	return "%s%d" % ["ABCDEFGH"[clampi(int(p.x / cell), 0, 7)], clampi(int(p.z / cell), 0, 7) + 1]
