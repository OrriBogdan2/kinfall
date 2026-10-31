class_name SkyTrain
extends Node3D
## The sky train: an engine and a few flat cars running a fixed loop round the middle of the map.
## Everything about it follows from the match clock (the same schedule for everyone): it waits at
## each stop's pier, eases away, dips under the bridges and eases into the next stop.
##
## The cars are platforms you can stand on and ride; each carries a crate of early loot. The engine's
## front is deadly while it's moving, so it warns you: a headlight, a horn as it bears down on you,
## and the rails ahead of it glowing.

const CAR_LEN := 4.6
const CAR_GAP := 5.3          # centre to centre
const HALF_W := 1.2
const ENGINE_KILL_SPEED := 2.0
const GLOW_N := 16

var m: Node = null
var world: World = null
var cars_n := 4
var speed := 8.0
var dwell := 6.0
var loop_len := 1.0
var stops: Array = []         # arc length of each stop, where the train's middle halts
var legs: Array = []          # [{s0, len, t_move}] from stop i to stop i+1
var period := 1.0
var head_s := 0.0             # arc length of the engine's centre
var head_v := 0.0             # its speed along the loop
var cur: Array = []           # Transform3D per car (0 = the engine)
var old: Array = []
var car_nodes: Array = []
var glows: Array = []
var light: SpotLight3D = null
var horn_cd := 0.0
var rail_cd := 0.0
var was_moving := false
var ride_t := {}              # hunter -> match time they last stood on a car

func setup(match_node: Node) -> void:
	m = match_node
	world = m.world
	var R: Dictionary = world.train_route
	var spec: Dictionary = R["spec"]
	cars_n = int(spec.get("cars", 4))
	speed = float(spec.get("speed", 8.0))
	dwell = float(spec.get("dwell", 6.0))
	loop_len = float(R["len"])
	# the engine stops a little past the pier so the middle of the train sits at it
	var mid_off := (cars_n - 1) * CAR_GAP * 0.5
	for s in R["stations"]:
		stops.append(fposmod(float(s) + mid_off, loop_len))
	stops.sort()
	period = 0.0
	for i in stops.size():
		var a: float = stops[i]; var b: float = stops[(i + 1) % stops.size()]
		var ln := fposmod(b - a, loop_len)
		if ln < 0.01: ln = loop_len
		var tm := ln / speed * 1.5
		legs.append({"s0": a, "len": ln, "t": tm})
		period += dwell + tm
	_build_track()
	_build_cars()
	for i in cars_n:
		cur.append(Transform3D()); old.append(Transform3D())
	_place(0.0)
	old = cur.duplicate()
	_attach_crates()

## Where the engine is at a given match time, and how fast it's going.
func _schedule(t: float) -> Vector2:
	var ph := fposmod(t, period)
	for L in legs:
		if ph < dwell:
			return Vector2(float(L["s0"]), 0.0)
		ph -= dwell
		var tm: float = L["t"]
		if ph < tm:
			var u := ph / tm
			# eases out of the stop and into the next: cosine speed profile
			var s := float(L["s0"]) + float(L["len"]) * (u - sin(TAU * u) / TAU)
			var v := float(L["len"]) / tm * (1.0 - cos(TAU * u))
			return Vector2(fposmod(s, loop_len), v)
		ph -= tm
	return Vector2(float(legs[0]["s0"]), 0.0)

func _xform_at(s: float) -> Transform3D:
	var c := world.train_at(s)
	var f := world.train_at(s + CAR_LEN * 0.5) - world.train_at(s - CAR_LEN * 0.5)
	if f.length() < 0.001:
		f = Vector3.FORWARD
	var b := Basis.looking_at(f.normalized(), Vector3.UP)
	return Transform3D(b, c)

func _place(t: float) -> void:
	var sv := _schedule(t)
	head_s = sv.x; head_v = sv.y
	for k in cars_n:
		cur[k] = _xform_at(head_s - k * CAR_GAP)

## Deck height under a point, when it's over one of the flat cars (not the engine) and no more than
## `step` below the deck; otherwise the void.
func deck_y(p: Vector3, step := 0.9, xf: Array = []) -> float:
	var X: Array = cur if xf.is_empty() else xf
	var best := World.VOID
	for k in range(1, cars_n):
		var t: Transform3D = X[k]
		if absf(p.x - t.origin.x) > CAR_LEN or absf(p.z - t.origin.z) > CAR_LEN:
			continue
		var l := t.affine_inverse() * p
		if absf(l.x) <= HALF_W and absf(l.z) <= CAR_LEN * 0.5:
			var d := (t * Vector3(l.x, 0.0, l.z)).y
			if p.y >= d - step:
				best = maxf(best, d)
	return best

func _car_under(p: Vector3, xf: Array, up := 0.25) -> int:
	for k in range(1, cars_n):
		var t: Transform3D = xf[k]
		if absf(p.x - t.origin.x) > CAR_LEN or absf(p.z - t.origin.z) > CAR_LEN:
			continue
		var l := t.affine_inverse() * p
		if absf(l.x) <= HALF_W + 0.1 and absf(l.z) <= CAR_LEN * 0.5 + 0.1 and l.y > -0.3 and l.y < up:
			return k
	return -1

func _carry(k: int, p: Vector3) -> Vector3:
	return (cur[k] as Transform3D) * ((old[k] as Transform3D).affine_inverse() * p)

func tick(dt: float) -> void:
	old = cur.duplicate()
	_place(float(m.time))
	var moving := head_v > 0.3
	# riders: anyone standing on a car moves with it (and for a moment after a hop, so jumping on a
	# moving train doesn't leave you behind)
	for h in m.hunters:
		if h.out or h.extracted or h.riding:
			continue
		var k := _car_under(h.pos, old, 0.25 if h.grounded else 4.0)
		if k < 0:
			continue
		if h.grounded:
			ride_t[h] = m.time
		elif m.time - float(ride_t.get(h, -9.0)) > 1.2:
			continue
		h.pos = _carry(k, h.pos)
	for p in m.pickups:
		if p.has("ride"):
			var k2 := int(p["ride"])
			p["pos"] = _carry(k2, p["pos"])
			var d := deck_y(p["pos"], 1.5)
			if d <= World.VOID + 1.0 and float(p["pos"].y) < (cur[k2] as Transform3D).origin.y - 1.0:
				p.erase("ride")
		else:
			var k3 := _car_under(p["pos"], old, 0.5)
			if k3 >= 0: p["pos"] = _carry(k3, p["pos"])
	for wp in m.wpicks:
		if wp.has("ride"):
			var k4 := int(wp["ride"])
			wp["pos"] = _carry(k4, wp["pos"])
			(wp["node"] as Node3D).position = wp["pos"]
			(wp["node"] as Node3D).rotation.y = (cur[k4] as Transform3D).basis.get_euler().y
	for c in m.chests:
		if c.has("ride"):
			var k5 := int(c["ride"])
			var at: Vector3 = (cur[k5] as Transform3D) * (c["off"] as Vector3)
			c["pos"] = at
			var n: Node3D = c["node"]
			n.position = at
			n.rotation.y = (cur[k5] as Transform3D).basis.get_euler().y + PI * 0.5
	_kill_zone()
	_visuals(dt, moving)
	if moving and not was_moving:
		m.sfx("horn", (cur[0] as Transform3D).origin, -2.0, 0.95)    # all aboard: pulling out
	was_moving = moving

## The engine's front: anything standing in its way while it moves is hit for good.
func _kill_zone() -> void:
	if head_v < ENGINE_KILL_SPEED:
		return
	var t: Transform3D = cur[0]
	var fwd := -t.basis.z
	var hit := func(e) -> bool:
		var l := t.affine_inverse() * (e.pos as Vector3)
		return absf(l.x) < HALF_W + 0.3 and l.z < -CAR_LEN * 0.5 + 0.8 and l.z > -CAR_LEN * 0.5 - 1.3 and l.y > -1.0 and l.y < 2.8
	for h in m.hunters:
		if h.out or h.extracted or h.remote or h.riding or not h.hittable():
			continue
			var l0: Vector3 = t.affine_inverse() * h.pos
		if hit.call(h):
			var kb := Vector2(fwd.x, fwd.z) * 22.0
			h.hurt(9999.0, null, {"src": "train", "kb": kb, "lift": 7.0})
			m.fx.burst(h.pos + Vector3(0, 1.0, 0), Color("ffcf6a"), 26, 6.0, 0.5)
			m.sfx("horn", t.origin, 2.0, 0.8)
			if h == m.player: m.shake(0.6, h.pos)
	for mb in m.mobs:
		if not mb.dead and hit.call(mb):
			mb.hurt(9999.0, null, {"src": "train", "kb": Vector2(fwd.x, fwd.z) * 22.0, "lift": 7.0})

# ------------------------------------------------------------------ looks
func _build_track() -> void:
	var pts: PackedVector3Array = world.train_route["pts"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := pts.size()
	for k in n:
		var a: Vector3 = pts[k]; var b: Vector3 = pts[(k + 1) % n]
		var f := (b - a); f.y = 0.0
		if f.length() < 0.001: continue
		f = f.normalized()
		var side := Vector3(-f.z, 0, f.x)
		for rx in [-0.85, 0.85]:
			# two rails: a thin bar each side under the wheels
			_quad(st, a + side * (rx - 0.09) + Vector3(0, -0.32, 0), a + side * (rx + 0.09) + Vector3(0, -0.32, 0),
				b + side * (rx + 0.09) + Vector3(0, -0.32, 0), b + side * (rx - 0.09) + Vector3(0, -0.32, 0), Color("c9a061"))
		if k % 3 == 0:
			# sleepers: a dark plank across every few steps
			var o := Vector3(0, -0.42, 0)
			_quad(st, a + side * -1.15 + o, a + side * 1.15 + o, a + f * 0.35 + side * 1.15 + o, a + f * 0.35 + side * -1.15 + o, Color("4a3a33"))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := Models.toon(Color.WHITE, false)
	mat.set_shader_parameter("use_vertex_color", true)
	mat.set_shader_parameter("glow", 0.15)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "Track"
	add_child(mi)
	# the warning glow that runs ahead of the engine along the rails
	for i in GLOW_N:
		var g := MeshInstance3D.new()
		g.mesh = Models.box(1.9, 0.08, 0.5)
		g.material_override = Models.glow_mat(Color(1.0, 0.45, 0.2, 0.0))
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(g)
		glows.append(g)

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	for v in [a, b, c, a, c, d]:
		st.set_color(col); st.add_vertex(v)
	for v in [a, c, b, a, d, c]:
		st.set_color(col); st.add_vertex(v)

func _build_cars() -> void:
	var wood := Models.toon(Color("7a5236"))
	var dark := Models.toon(Color("2f2a33"))
	var brass := Models.toon(Color("d6a85a"), true, 0.1)
	var paint := Models.toon(Color("3f6fa8"))
	var red := Models.toon(Color("c8452f"), true, 0.15)
	for k in cars_n:
		var n := Node3D.new()
		n.name = "Car%d" % k
		add_child(n)
		car_nodes.append(n)
		# undercarriage and wheels
		Models.part(n, Models.box(1.5, 0.35, CAR_LEN - 0.6), dark, Vector3(0, -0.45, 0))
		for zz in [-CAR_LEN * 0.32, CAR_LEN * 0.32]:
			for xx in [-0.85, 0.85]:
				Models.part(n, Models.cyl(0.32, 0.32, 0.18, 12), brass, Vector3(xx, -0.42, zz), Vector3.ONE, Vector3(0, 0, PI * 0.5))
		if k == 0:
			# the engine: boiler, cab, funnel, a red cow-catcher and the headlight
			Models.part(n, Models.box(HALF_W * 2.0, 0.3, CAR_LEN), dark, Vector3(0, -0.15, 0))
			Models.part(n, Models.cyl(0.85, 0.85, CAR_LEN * 0.6, 16), paint, Vector3(0, 0.75, -0.5), Vector3.ONE, Vector3(PI * 0.5, 0, 0))
			Models.part(n, Models.box(HALF_W * 2.0, 1.9, 1.6), paint, Vector3(0, 0.95, CAR_LEN * 0.5 - 0.8))
			Models.part(n, Models.box(HALF_W * 2.2, 0.18, 1.8), brass, Vector3(0, 1.95, CAR_LEN * 0.5 - 0.8))
			Models.part(n, Models.cyl(0.22, 0.3, 0.9, 10), dark, Vector3(0, 1.85, -1.3))
			Models.part(n, Models.box(HALF_W * 2.0, 0.5, 0.5), red, Vector3(0, -0.05, -CAR_LEN * 0.5 - 0.15), Vector3.ONE, Vector3(-0.5, 0, 0))
			for xx in [-0.75, 0.75]:
				Models.part(n, Models.box(0.12, 0.7, 0.12), red, Vector3(xx, 0.2, -CAR_LEN * 0.5 + 0.05))
			var lamp := Models.part(n, Models.sphere(0.26, 12), Models.glow_mat(Color("fff2b8")), Vector3(0, 0.8, -CAR_LEN * 0.5 - 0.05))
			lamp.name = "Lamp"
			light = SpotLight3D.new()
			light.light_color = Color("ffe7a8")
			light.light_energy = 3.0
			light.spot_range = 24.0
			light.spot_angle = 26.0
			light.position = Vector3(0, 0.8, -CAR_LEN * 0.5 - 0.2)
			light.rotation = Vector3(-0.12, 0, 0)
			n.add_child(light)
		else:
			# a flat car: plank deck, low brass rails along the sides (open at the ends)
			Models.part(n, Models.box(HALF_W * 2.0, 0.22, CAR_LEN), wood, Vector3(0, -0.11, 0))
			for xx in [-HALF_W + 0.06, HALF_W - 0.06]:
				Models.part(n, Models.box(0.08, 0.08, CAR_LEN - 0.8), brass, Vector3(xx, 0.42, 0))
				for zz in [-CAR_LEN * 0.36, 0.0, CAR_LEN * 0.36]:
					Models.part(n, Models.box(0.07, 0.42, 0.07), brass, Vector3(xx, 0.21, zz))
			# a coupling bar to the car in front
			Models.part(n, Models.box(0.2, 0.12, CAR_GAP - CAR_LEN + 0.3), dark, Vector3(0, -0.3, -CAR_GAP * 0.5))
		Flora.paint_set_piece(n)

## One crate per flat car: early-game loot, the last car's a little better.
func _attach_crates() -> void:
	for k in range(1, cars_n):
		var tier := 1 if k == cars_n - 1 else 0
		var n := Models.chest(tier)
		m.add_child(n)
		var off := Vector3(0, 0, CAR_LEN * 0.18 * (1.0 if k % 2 == 0 else -1.0))
		var at: Vector3 = (cur[k] as Transform3D) * off
		n.position = at
		m.chests.append({"pos": at, "open": false, "prog": 0.0, "node": n, "tier": tier, "ride": k, "off": off})

func _visuals(dt: float, moving: bool) -> void:
	for k in cars_n:
		var n: Node3D = car_nodes[k]
		n.transform = cur[k]
		if moving:
			n.position.y += sin(float(m.time) * 18.0 + k) * 0.02
	# rails ahead of the engine glow brighter the faster it comes; brightest right in front
	var heat := clampf(head_v / speed, 0.0, 1.0)
	for i in GLOW_N:
		var g: MeshInstance3D = glows[i]
		var s := head_s + CAR_LEN * 0.5 + 1.0 + i * 1.6
		var p := world.train_at(s)
		var f := world.train_at(s + 0.5) - world.train_at(s - 0.5)
		g.position = p + Vector3(0, -0.3, 0)
		if f.length() > 0.001:
			g.basis = Basis.looking_at(f.normalized(), Vector3.UP)
		var a := heat * (1.0 - float(i) / GLOW_N) * (0.55 + 0.45 * sin(float(m.time) * 10.0 - i * 0.7))
		g.visible = a > 0.02
		(g.material_override as ShaderMaterial).set_shader_parameter("color", Color(1.0, 0.42 + 0.3 * (1.0 - heat), 0.18, clampf(a, 0.0, 1.0)))
	if light:
		light.light_energy = 1.4 + heat * 2.6
	# sound: the horn as it bears down on you, the rails singing when it's close
	horn_cd -= dt; rail_cd -= dt
	var pl = m.player
	if pl and not pl.out and moving:
		var t: Transform3D = cur[0]
		var to: Vector3 = pl.pos - t.origin
		var ahead := to.dot(-t.basis.z)
		if ahead > 0.0 and ahead < 26.0 and Vector2(to.x, to.z).length() < 26.0 and horn_cd <= 0.0 and head_v > speed * 0.5:
			var lat := absf(to.dot(t.basis.x))
			if lat < 4.0:
				m.sfx("horn", t.origin, 0.0)
				horn_cd = 5.0
		var near := 1e9
		for k in cars_n:
			near = minf(near, ((cur[k] as Transform3D).origin - pl.pos).length())
		if near < 16.0 and rail_cd <= 0.0:
			m.sfx("rail", t.origin, -12.0 + (16.0 - near) * 0.5, 0.9 + heat * 0.2)
			rail_cd = 0.8

## The loop as points for the minimap, every few tiles.
func route_2d(step := 3.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	var s := 0.0
	while s < loop_len:
		var p := world.train_at(s)
		out.append(Vector2(p.x, p.z))
		s += step
	return out

func car_positions() -> Array:
	var out: Array = []
	for k in cars_n:
		var o: Vector3 = (cur[k] as Transform3D).origin
		out.append(Vector2(o.x, o.z))
	return out
