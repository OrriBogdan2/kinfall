class_name Verbs
extends RefCounted
## The things abilities leave in the world that keep working after the cast: barrier walls,
## reflect windows, tethers, traps, temporary terrain, decoys and forced movement (yanks). Effects
## create them (see Effects), the match ticks them, checks every shot against them and draws them.
## Each one is plain data plus one scene node, so new abilities are new JSON, not new code.

var m: Node = null
var walls: Array = []     # {a, b: Vector2, y, hp, max_hp, t, team, by, block: "enemy"|"all", move, reflect, node, col, touch, follow, th}
var mirrors: Array = []   # {ent, t, r, arc, team, k, riposte, node, col, front}
var tethers: Array = []   # {a, b: Ent, max, t, dmg, stun, col, node, pw}
var traps: Array = []     # {at, r, team, arm, t, effects, caster, ctx, node, col}
var terrain: Array = []   # {tiles: [[i, kind, level]], t, node, warned}
var drags: Array = []     # {ent, from, to, t, dur, h}
var decoys: Array = []    # {pos, team, t, node, owner}

const WALL_TH := 0.32      # half thickness of a barrier
const WALL_H := 2.3

func _init(match_node: Node) -> void:
	m = match_node
	m.world.dyn_walls = walls

# ------------------------------------------------------------------ barrier walls
## A wall segment centred at `at`, running across `d` (the aim), `length` long.
func add_wall(by: Node, at: Vector3, d: Vector2, e: Dictionary, pw: float) -> Dictionary:
	var length := float(e.get("length", 4.0))
	var side := Vector2(-d.y, d.x)
	var c2 := Vector2(at.x, at.z)
	var col := Color(String(e.get("color", "#9ad8ff")))
	var w := {"a": c2 - side * length * 0.5, "b": c2 + side * length * 0.5, "y": at.y, "hp": float(e.get("hp", 120.0)) * pw,
		"max_hp": float(e.get("hp", 120.0)) * pw, "t": float(e.get("time", 4.0)), "team": int(by.team), "by": by,
		"block": String(e.get("block", "enemy")), "move": bool(e.get("move", false)), "reflect": bool(e.get("reflect", false)),
		"col": col, "touch": e.get("touch", {}), "follow": bool(e.get("follow", false)), "dist": float(e.get("dist", 1.4)),
		"len": length, "th": WALL_TH, "touched": {}, "hit_t": 0.0, "nid": by.get("nid") if by else ""}
	# don't seal anyone inside it: a movement-blocking wall skips the bits that would trap someone
	w["node"] = _wall_node(w)
	walls.append(w)
	m.fx.burst(Vector3(c2.x, at.y + 0.4, c2.y), col, 20, 4.0, 0.45, 2.0, 1.2)
	m.sfx("shield", at, -2.0, 0.7)
	return w

func _wall_node(w: Dictionary) -> Node3D:
	var col: Color = w["col"]
	var n := Node3D.new()
	var length: float = w["len"]
	# a translucent slab with a bright rim and posts at both ends: reads as "solid" at a glance
	var body := Models.part(n, Models.box(length, WALL_H, WALL_TH * 2.0), Models.glow_mat(Color(col, 0.38)), Vector3(0, WALL_H * 0.5, 0))
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.name = "Body"
	var rim := Models.part(n, Models.box(length + 0.1, 0.12, WALL_TH * 2.2), Models.glow_mat(Color(col.lightened(0.4), 0.95)), Vector3(0, WALL_H, 0))
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var base := Models.part(n, Models.box(length + 0.1, 0.1, WALL_TH * 2.4), Models.glow_mat(Color(col, 0.8)), Vector3(0, 0.05, 0))
	base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for sx in [-0.5, 0.5]:
		Models.part(n, Models.box(0.22, WALL_H + 0.2, WALL_TH * 2.6), Models.toon(col.darkened(0.25), true, 0.6), Vector3(length * sx, (WALL_H + 0.2) * 0.5, 0))
	if w["reflect"]:
		# a prism wall: facets that catch the light
		for i in 3:
			var fx := (float(i) - 1.0) * length * 0.3
			var f := Models.part(n, Models.box(0.08, WALL_H * 0.8, WALL_TH * 2.3), Models.glow_mat(Color(1, 1, 1, 0.55)), Vector3(fx, WALL_H * 0.45, 0), Vector3.ONE, Vector3(0, 0, 0.35))
			f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.add_child(n)
	_place_wall(w, n)
	n.scale = Vector3(1, 0.05, 1)
	n.create_tween().tween_property(n, "scale", Vector3.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return n

func _place_wall(w: Dictionary, n: Node3D) -> void:
	var a: Vector2 = w["a"]; var b: Vector2 = w["b"]
	var mid := (a + b) * 0.5
	n.global_position = Vector3(mid.x, float(w["y"]), mid.y)
	n.rotation = Vector3(0, -atan2(b.y - a.y, b.x - a.x), 0)

func _break_wall(w: Dictionary) -> void:
	walls.erase(w)
	var a: Vector2 = w["a"]; var b: Vector2 = w["b"]
	for i in 4:
		var p := a.lerp(b, (i + 0.5) / 4.0)
		m.fx.burst(Vector3(p.x, float(w["y"]) + 1.0, p.y), w["col"], 10, 4.0, 0.45, 9.0, 1.2)
	m.sfx("knock", Vector3((a.x + b.x) * 0.5, float(w["y"]), (a.y + b.y) * 0.5), -4.0, 1.4)
	if is_instance_valid(w["node"]):
		(w["node"] as Node3D).queue_free()

## Is a body at (x, z) with radius r and feet at y blocked by a barrier? (World.occupy asks.)
static func wall_blocks(list: Array, x: float, z: float, r: float, y: float) -> float:
	for w in list:
		if not w["move"]:
			continue
		if absf(y - float(w["y"])) > 1.9:
			continue
		var p := Vector2(x, z)
		var c := Geometry2D.get_closest_point_to_segment(p, w["a"], w["b"])
		if p.distance_to(c) < r * 0.8 + float(w["th"]):
			return float(w["y"]) + 3.0
	return 0.0

# ------------------------------------------------------------------ reflect windows
func add_mirror(ent: Node, e: Dictionary) -> void:
	var col := Color(String(e.get("color", "#bff6ff")))
	var arc := float(e.get("arc", -1.0))
	var r := float(e.get("radius", 1.7))
	var n := Node3D.new()
	if arc > -0.99:
		# a curved frontal shield: a fan of glowing panels
		var half := acos(clampf(arc, -1.0, 1.0))
		for i in 7:
			var a := -half + 2.0 * half * i / 6.0
			var pnl := Models.part(n, Models.box(r * 2.0 * half / 6.0 + 0.08, 1.7, 0.08), Models.glow_mat(Color(col, 0.55)), Vector3(sin(a) * r, 0.95, -cos(a) * r), Vector3.ONE, Vector3(0, -a, 0))
			pnl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		var s := Models.part(n, Models.sphere(r, 20), Models.glow_mat(Color(col, 0.22)), Vector3(0, 0.9, 0))
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rg := Models.part(n, Models.flat_quad(r * 2.0), Models.ring_mat(Color(col, 0.9), 0.08), Vector3(0, 0.08, 0))
	rg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.add_child(n)
	mirrors.append({"ent": ent, "t": float(e.get("time", 0.6)), "t0": float(e.get("time", 0.6)), "r": r, "arc": arc, "team": int(ent.team),
		"k": float(e.get("dmg_k", 1.25)), "riposte": float(e.get("riposte", 0.0)), "node": n, "col": col, "caught": 0})
	m.sfx("shield", ent.pos, -3.0, 1.4)

func _mirror_dir(mr: Dictionary) -> Vector2:
	var ent = mr["ent"]
	if ent is Hunter:
		return (ent as Hunter).aim_dir()
	return Vector2(-sin(ent.face), -cos(ent.face))

# ------------------------------------------------------------------ tethers
func add_tether(a: Ent, b: Ent, e: Dictionary, pw: float) -> void:
	if a == null or b == null or a == b:
		return
	for t in tethers:
		if t["b"] == b and t["a"] == a:
			tethers.erase(t)
			if is_instance_valid(t["node"]): t["node"].queue_free()
			break
	var col := Color(String(e.get("color", "#ffd27a")))
	var n := MeshInstance3D.new()
	n.mesh = Models.box(0.09, 0.09, 1.0)
	n.material_override = Models.glow_mat(col)
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.add_child(n)
	var ring := MeshInstance3D.new()
	ring.mesh = Models.flat_quad(2.0)
	ring.material_override = Models.ring_mat(Color(col, 0.6), 0.03)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.add_child(ring)
	tethers.append({"a": a, "b": b, "max": float(e.get("max", 6.0)), "t": float(e.get("time", 3.0)), "dmg": float(e.get("dmg", 18.0)) * pw,
		"stun": float(e.get("stun", 1.0)), "col": col, "node": n, "ring": ring, "yank": bool(e.get("yank", true))})
	m.sfx("zap", b.pos, -4.0, 1.3)

# ------------------------------------------------------------------ traps
func add_trap(caster: Node, at: Vector3, e: Dictionary, ctx: Dictionary) -> void:
	var col := Color(String(e.get("color", "#c8ff8a")))
	var r := float(e.get("radius", 1.2))
	var n := Node3D.new()
	var rg := Models.part(n, Models.flat_quad(r * 2.0), Models.ring_mat(Color(col, 0.8), 0.1), Vector3(0, 0.07, 0))
	rg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rg.name = "Ring"
	var core := Models.part(n, Models.cyl(0.22, 0.28, 0.12, 10), Models.toon(col.darkened(0.3), true, 0.9), Vector3(0, 0.06, 0))
	core.name = "Core"
	# a little cross so it reads as a mine, not a heal pad
	for a in [0.0, PI * 0.5]:
		var bar := Models.part(n, Models.box(r * 1.3, 0.02, 0.08), Models.glow_mat(Color(col, 0.7)), Vector3(0, 0.08, 0), Vector3.ONE, Vector3(0, a + PI * 0.25, 0))
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.add_child(n)
	n.global_position = at
	traps.append({"at": at, "r": r, "team": int(caster.team), "arm": float(e.get("arm", 0.6)), "t": float(e.get("time", 20.0)),
		"effects": e.get("on_trigger", []), "caster": caster, "ctx": ctx, "node": n, "col": col, "reveal": float(e.get("reveal", 0.0))})
	m.fx.burst(at + Vector3(0, 0.2, 0), col, 8, 2.0, 0.3)
	m.sfx("click", at, -4.0, 0.9)

# ------------------------------------------------------------------ terrain
## Turns abyss tiles along a line into ground for a while: an ice bridge (or any element's span).
func add_bridge(by: Node, from: Vector3, d: Vector2, e: Dictionary) -> int:
	var length := float(e.get("length", 9.0))
	var width := float(e.get("width", 2.0))
	var col := Color(String(e.get("color", "#bff0ff")))
	var w: World = m.world
	var lv := int(round(from.y / World.LEVEL))
	var tiles: Array = []
	var seen := {}
	var n := Node3D.new()
	var side := Vector2(-d.y, d.x)
	var k := 0.6
	var mat := Models.toon(col, true, 0.5)
	var glass := Models.glow_mat(Color(col.lightened(0.3), 0.45))
	while k <= length:
		for s in range(-int(width * 2.0), int(width * 2.0) + 1):
			var p := Vector2(from.x, from.z) + d * k + side * (float(s) * 0.25)
			var tx := int(floor(p.x)); var tz := int(floor(p.y))
			if not w.inb(tx, tz):
				continue
			var i := w.idx(tx, tz)
			if seen.has(i):
				continue
			seen[i] = true
			if w.kind[i] != World.T_VOID:
				continue
			tiles.append([i, int(w.kind[i]), int(w.level[i])])
			w.kind[i] = World.T_GROUND
			w.level[i] = clampi(lv, 0, 255)
			var slab := Models.part(n, Models.box(1.0, 0.28, 1.0), mat, Vector3(tx + 0.5, lv * World.LEVEL - 0.14, tz + 0.5))
			slab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var under := Models.part(n, Models.cyl(0.45, 0.05, 0.6, 6), glass, Vector3(tx + 0.5, lv * World.LEVEL - 0.55, tz + 0.5))
			under.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		k += 0.5
	if tiles.is_empty():
		n.free()
		return 0
	m.add_child(n)
	terrain.append({"tiles": tiles, "t": float(e.get("time", 6.0)), "node": n, "col": col, "slow": e.get("slow", 0.0), "team": int(by.team)})
	m.sfx("shield", from, -2.0, 1.6)
	return tiles.size()

# ------------------------------------------------------------------ forced movement
## Pull a body to a spot over `dur` seconds in a low arc. Hunters fly there with their own physics;
## monsters and kin are carried.
func yank(ent: Ent, to: Vector3, dur: float, hop := 1.2) -> void:
	if ent == null or ent.dead:
		return
	if ent is Hunter:
		var h := ent as Hunter
		h.gliding = false
		h.roll_t = 0.0
		h.launch_to(to + Vector3(0, 0.3, 0), dur)
		h.knock_t = 0.0
		return
	if ent.mass() >= 6.0:
		return          # too heavy to drag (wardens, sentinels)
	for dg in drags:
		if dg["ent"] == ent:
			drags.erase(dg); break
	drags.append({"ent": ent, "from": ent.pos, "to": to, "t": 0.0, "dur": maxf(0.08, dur), "h": hop})

# ------------------------------------------------------------------ decoys
func add_decoy(owner: Hunter, at: Vector3, time: float, col: Color) -> void:
	var n := Node3D.new()
	var body := Models.part(n, Models.capsule(0.32, 1.5), Models.glow_mat(Color(col, 0.55)), Vector3(0, 0.8, 0))
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var head := Models.part(n, Models.sphere(0.24, 10), Models.glow_mat(Color(col.lightened(0.3), 0.7)), Vector3(0, 1.75, 0))
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.add_child(n)
	n.global_position = at
	decoys.append({"pos": at, "team": owner.team, "t": time, "node": n, "owner": owner})

## Where a bot shooting at `h` thinks they are: a fresh decoy of theirs draws the fire.
func decoy_of(h: Hunter) -> Dictionary:
	for dc in decoys:
		if dc["owner"] == h:
			return dc
	return {}

# ------------------------------------------------------------------ shots
## Called for every step of every shot. Returns "" (carry on), "end" (stopped by a wall) or
## "bounce" (reflected: it now belongs to the reflector).
func shot_check(s: Dictionary, p: Vector3) -> String:
	if walls.is_empty() and mirrors.is_empty():
		return ""
	var x: Dictionary = s["x"]
	var p2 := Vector2(p.x, p.z)
	for w in walls:
		if w["block"] != "all" and int(w["team"]) == int(s["team"]):
			continue
		if p.y < float(w["y"]) - 0.3 or p.y > float(w["y"]) + WALL_H + 0.3:
			continue
		var c := Geometry2D.get_closest_point_to_segment(p2, w["a"], w["b"])
		if p2.distance_to(c) > float(w["th"]) + float(s["r"]):
			continue
		if w["reflect"] and not x.get("melee", false):
			var ab: Vector2 = (w["b"] as Vector2) - (w["a"] as Vector2)
			var nrm := Vector2(-ab.y, ab.x).normalized()
			var v: Vector2 = s["vel"]
			if v.dot(nrm) > 0.0: nrm = -nrm
			_take_shot(s, v - 2.0 * v.dot(nrm) * nrm, w["by"] if is_instance_valid(w["by"]) else null, int(w["team"]), 1.0)
			s["pos"] = Vector3(c.x, p.y, c.y) + Vector3(nrm.x, 0, nrm.y) * (float(w["th"]) + float(s["r"]) + 0.12)
			_hit_wall(w, float(s["dmg"]) * 0.5, s["col"])
			return "bounce"
		_hit_wall(w, float(s["dmg"]), s["col"])
		m.fx.burst(p, w["col"], 6, 3.0, 0.25, 4.0, 0.8)
		return "end"
	for mr in mirrors:
		if int(mr["team"]) == int(s["team"]) or s["by"] == mr["ent"]:
			continue
		var ent = mr["ent"]
		if not is_instance_valid(ent):
			continue
		var rel := Vector2(p.x - ent.pos.x, p.z - ent.pos.z)
		if rel.length() > float(mr["r"]) + float(s["r"]) or absf(p.y - (ent.pos.y + 0.9)) > 1.8:
			continue
		if float(mr["arc"]) > -0.99 and rel.length() > 0.2 and rel.normalized().dot(_mirror_dir(mr)) < float(mr["arc"]):
			continue
		mr["caught"] = int(mr["caught"]) + 1
		if x.get("melee", false):
			# a parry: the swing is stopped and the attacker is staggered
			var att = s["by"]
			if float(mr["riposte"]) > 0.0 and is_instance_valid(att) and att is Ent:
				(att as Ent).hurt(4.0, ent, {"stun": float(mr["riposte"]), "src": "abil", "ab": "parry", "kb": (att as Ent).dir_to(ent) * -5.0})
				m.fx.word(att.pos + Vector3(0, 2.0, 0), "PARRIED", mr["col"], true)
			m.fx.flash(p, mr["col"], 0.5, 0.08)
			m.sfx("shield", p, 0.0, 1.8)
			return "end"
		var att2 = s["by"]
		var back: Vector2 = -(s["vel"] as Vector2)
		if is_instance_valid(att2) and att2 is Node3D:
			var to := Vector2(att2.pos.x - p.x, att2.pos.z - p.z)
			if to.length() > 0.3: back = to.normalized() * (s["vel"] as Vector2).length()
		_take_shot(s, back * 1.1, ent, int(mr["team"]), float(mr["k"]))
		m.fx.flash(p, mr["col"], 0.4, 0.06)
		m.fx.burst(p, mr["col"], 8, 4.0, 0.3, 2.0)
		m.sfx("shield", p, -4.0, 1.9)
		if ent == m.player and m.hud: m.hud.toast_small("REFLECTED", mr["col"])
		return "bounce"
	return ""

func _take_shot(s: Dictionary, v: Vector2, by, team: int, k: float) -> void:
	s["vel"] = v
	s["team"] = team
	if by: s["by"] = by
	s["dmg"] = float(s["dmg"]) * k
	s["life"] = maxf(float(s["life"]), 0.7)
	s["start"] = s["pos"]
	var x: Dictionary = (s["x"] as Dictionary).duplicate()
	for kk in ["dy", "dyd", "y0", "gmax", "mob", "near", "farf", "pg"]:
		x.erase(kk)
	x["reflected"] = true
	s["x"] = x
	if s["node"]:
		(s["node"] as MeshInstance3D).material_override.set_shader_parameter("color", Color("ffffff").lerp(s["col"], 0.4))

func _hit_wall(w: Dictionary, dmg: float, _col: Color) -> void:
	w["hp"] = float(w["hp"]) - dmg
	w["hit_t"] = 0.12
	if float(w["hp"]) <= 0.0:
		_break_wall(w)

# ------------------------------------------------------------------ simulation
func tick(dt: float) -> void:
	for w in walls.duplicate():
		w["t"] = float(w["t"]) - dt
		w["hit_t"] = maxf(0.0, float(w["hit_t"]) - dt)
		if w["follow"] and is_instance_valid(w["by"]) and not w["by"].dead:
			# a living shield: it stays between its owner and wherever they're facing
			var by = w["by"]
			var d: Vector2 = (by as Hunter).aim_dir() if by is Hunter else Vector2(-sin(by.face), -cos(by.face))
			var c: Vector2 = Vector2(by.pos.x, by.pos.z) + d * float(w["dist"])
			var side := Vector2(-d.y, d.x)
			w["a"] = c - side * float(w["len"]) * 0.5
			w["b"] = c + side * float(w["len"]) * 0.5
			w["y"] = by.pos.y
		var touch: Dictionary = w["touch"]
		if not touch.is_empty():
			for f in m.foes_of(int(w["team"])):
				var c2 := Geometry2D.get_closest_point_to_segment(Vector2(f.pos.x, f.pos.z), w["a"], w["b"])
				if Vector2(f.pos.x, f.pos.z).distance_to(c2) < f.r + 0.5 and absf(f.pos.y - float(w["y"])) < 2.0:
					var key: String = str(f.get_instance_id())
					if float(w["touched"].get(key, -9.0)) > m.time - 0.6:
						continue
					w["touched"][key] = m.time
					var o := {"src": "abil", "ab": "wall"}
					for kk in ["slow", "burn", "root", "stun"]:
						if touch.has(kk): o[kk] = float(touch[kk])
					f.hurt(maxf(0.1, float(touch.get("dmg", 0.0))), w["by"] if is_instance_valid(w["by"]) else null, o)
		if float(w["t"]) <= 0.0:
			_break_wall(w)
	for mr in mirrors.duplicate():
		mr["t"] = float(mr["t"]) - dt
		if float(mr["t"]) <= 0.0 or not is_instance_valid(mr["ent"]) or mr["ent"].dead:
			mirrors.erase(mr)
			if is_instance_valid(mr["node"]): mr["node"].queue_free()
	for t in tethers.duplicate():
		var a = t["a"]; var b = t["b"]
		if not is_instance_valid(a) or not is_instance_valid(b) or a.dead or b.dead or (b is Hunter and (b.downed or b.out)):
			_drop_tether(t); continue
		t["t"] = float(t["t"]) - dt
		var d: float = a.flat_dist(b)
		if d > float(t["max"]):
			# stretched too far: it snaps, and the snap hurts
			b.hurt(float(t["dmg"]), a, {"stun": float(t["stun"]), "src": "abil", "ab": "tether", "kb": b.dir_to(a) * 7.0, "lift": 2.0})
			m.fx.bolt(a.pos + Vector3(0, 1.0, 0), b.pos + Vector3(0, 1.0, 0), t["col"])
			m.fx.word(b.pos + Vector3(0, 2.0, 0), "SNAP", t["col"], true)
			m.sfx("zap", b.pos, 0.0, 0.8)
			if t["yank"]:
				yank(b, a.pos + Vector3(b.dir_to(a).x, 0, b.dir_to(a).y) * -(float(t["max"]) * 0.5), 0.25)
			_drop_tether(t)
		elif float(t["t"]) <= 0.0:
			_drop_tether(t)
	for tr in traps.duplicate():
		tr["t"] = float(tr["t"]) - dt
		tr["arm"] = float(tr["arm"]) - dt
		var caster = tr["caster"]
		if float(tr["t"]) <= 0.0 or not is_instance_valid(caster):
			_drop_trap(tr); continue
		if float(tr["arm"]) > 0.0:
			continue
		var at: Vector3 = tr["at"]
		for f in m.foes_of(int(tr["team"])):
			if f.flat_dist(at) < float(tr["r"]) + f.r and absf(f.pos.y - at.y) < 1.5 and f.hittable():
				var c3: Dictionary = (tr["ctx"] as Dictionary).duplicate()
				c3["at"] = at
				c3["target"] = f
				if float(tr["reveal"]) > 0.0 and f is Hunter:
					f.reveal_t = maxf(f.reveal_t, float(tr["reveal"]))
				m.fx.word(at + Vector3(0, 1.6, 0), "TRAP", tr["col"], false)
				if caster.dead:
					_drop_trap(tr); break
				Effects.run(tr["effects"], caster, c3)
				_drop_trap(tr)
				break
	for tz in terrain.duplicate():
		tz["t"] = float(tz["t"]) - dt
		if float(tz["t"]) <= 0.0:
			var w: World = m.world
			for td in tz["tiles"]:
				w.kind[int(td[0])] = int(td[1])
				w.level[int(td[0])] = int(td[2])
			if is_instance_valid(tz["node"]): tz["node"].queue_free()
			terrain.erase(tz)
	for dg in drags.duplicate():
		var ent: Ent = dg["ent"]
		if not is_instance_valid(ent) or ent.dead:
			drags.erase(dg); continue
		dg["t"] = float(dg["t"]) + dt
		var k := clampf(float(dg["t"]) / float(dg["dur"]), 0.0, 1.0)
		var p: Vector3 = (dg["from"] as Vector3).lerp(dg["to"], k)
		p.y += sin(k * PI) * float(dg["h"])
		ent.pos = p
		ent.vel = Vector3.ZERO
		ent.grounded = false
		if k >= 1.0:
			drags.erase(dg)
	for dc in decoys.duplicate():
		dc["t"] = float(dc["t"]) - dt
		if float(dc["t"]) <= 0.0:
			if is_instance_valid(dc["node"]):
				m.fx.burst((dc["pos"] as Vector3) + Vector3(0, 1.0, 0), Color("ffffff"), 10, 3.0, 0.3)
				dc["node"].queue_free()
			decoys.erase(dc)

func dragging(ent: Ent) -> bool:
	for dg in drags:
		if dg["ent"] == ent: return true
	return false

func _drop_tether(t: Dictionary) -> void:
	tethers.erase(t)
	if is_instance_valid(t["node"]): t["node"].queue_free()
	if is_instance_valid(t["ring"]): t["ring"].queue_free()

func _drop_trap(tr: Dictionary) -> void:
	traps.erase(tr)
	if is_instance_valid(tr["node"]):
		m.fx.burst((tr["at"] as Vector3) + Vector3(0, 0.3, 0), tr["col"], 10, 3.0, 0.3)
		tr["node"].queue_free()

## Every rendered frame: walls flash when hit and fade as they weaken, tethers stretch and redden,
## traps are only faint glints to the other side.
func render(_alpha: float) -> void:
	var pt: int = m.player.team if m.player else -99
	for w in walls:
		var n: Node3D = w["node"]
		if not is_instance_valid(n): continue
		if w["follow"]: _place_wall(w, n)
		var body := n.get_node_or_null("Body") as MeshInstance3D
		if body:
			var hk := clampf(float(w["hp"]) / maxf(1.0, float(w["max_hp"])), 0.0, 1.0)
			var c: Color = w["col"]
			var a := 0.18 + 0.3 * hk
			if float(w["hit_t"]) > 0.0: c = c.lerp(Color.WHITE, 0.7); a = 0.75
			if float(w["t"]) < 0.6: a *= 0.5 + 0.5 * sin(m.time * 30.0)
			body.material_override.set_shader_parameter("color", Color(c, a))
	for mr in mirrors:
		var n2: Node3D = mr["node"]
		if not is_instance_valid(n2) or not is_instance_valid(mr["ent"]): continue
		var ent = mr["ent"]
		n2.global_position = (ent as Node3D).position
		var d := _mirror_dir(mr)
		n2.rotation = Vector3(0, atan2(-d.x, -d.y), 0)
		n2.scale = Vector3.ONE * (1.0 + 0.04 * sin(m.time * 25.0))
	for t in tethers:
		var a: Ent = t["a"]; var b: Ent = t["b"]
		var n3: MeshInstance3D = t["node"]
		if not is_instance_valid(n3) or not is_instance_valid(a) or not is_instance_valid(b): continue
		var p0 := a.position + Vector3(0, 1.0, 0)
		var p1 := b.position + Vector3(0, 1.0, 0)
		if p0.distance_to(p1) < 0.05: continue
		n3.global_position = (p0 + p1) * 0.5
		n3.look_at(p1, Vector3.UP if absf((p1 - p0).normalized().y) < 0.95 else Vector3.RIGHT)
		var k := clampf(a.flat_dist(b) / float(t["max"]), 0.0, 1.0)
		n3.scale = Vector3(1.0 + k * 0.8, 1.0 + k * 0.8, p0.distance_to(p1))
		n3.material_override.set_shader_parameter("color", (t["col"] as Color).lerp(Color("ff4a3a"), k * k))
		var rg: MeshInstance3D = t["ring"]
		rg.global_position = Vector3(a.position.x, a.position.y + 0.08, a.position.z)
		rg.scale = Vector3.ONE * float(t["max"])
	for tr in traps:
		var n4: Node3D = tr["node"]
		if not is_instance_valid(n4): continue
		var mine := int(tr["team"]) == pt
		var armed := float(tr["arm"]) <= 0.0
		n4.visible = mine or not armed or fmod(m.time, 1.6) < 0.25
		var rgn := n4.get_node_or_null("Ring") as MeshInstance3D
		if rgn:
			rgn.material_override.set_shader_parameter("color", Color(tr["col"], (0.85 if armed else 0.35) if mine else 0.35))
	for tz in terrain:
		var n5: Node3D = tz["node"]
		if is_instance_valid(n5) and float(tz["t"]) < 1.2:
			n5.visible = fmod(float(tz["t"]), 0.24) > 0.08   # about to go: it flickers
	for dc in decoys:
		var n6: Node3D = dc["node"]
		if is_instance_valid(n6):
			n6.scale = Vector3.ONE * (1.0 + 0.03 * sin(m.time * 12.0))

func clear() -> void:
	for w in walls.duplicate(): _break_wall(w)
	for t in tethers.duplicate(): _drop_tether(t)
	for tr in traps.duplicate(): _drop_trap(tr)
	for mr in mirrors:
		if is_instance_valid(mr["node"]): mr["node"].queue_free()
	mirrors.clear()
