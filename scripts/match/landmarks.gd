extends RefCounted
## One big landmark per region, so you can tell where you are from the air: a frozen guardian
## statue over the frost, a forge chimney breathing embers over the ember lands, a twisting storm
## spire crowned with lightning, a blossom arch over the bloom, a giant tree in the groves and the
## Heart's floating ring of runes. Each stands on its own floating rock just off the island's far
## (north) coast, so it never hides anything you could stand on from the camera and never blocks.
## Sculpted in code like the rest of the world's props (see Flora). Purely visual.

const KINDS := {"frost": "statue", "ember": "chimney", "storm": "spire", "bloom": "arch", "gloom": "ring", "meadow": "giant_tree"}

var W: Node
var spots: Array = []     # {pos: Vector3, kind: String, island: int} where landmarks went

func _init(world: Node) -> void:
	W = world

func build(parent: Node3D) -> void:
	for ii in W.islands.size():
		var I: Dictionary = W.islands[ii]
		var role := String(I.get("role", ""))
		if not role in ["heart", "camp", "nest", "shrine", "grove"] and not (W.layout_id == "" and ii > 0 and int(I.get("r", 0)) >= 9):
			continue
		var style := Flora.style_ok(String(I.get("biome", "")) if String(I.get("biome", "")) != "" else W.style_at(W.idx(int(I["c"].x), int(I["c"].y))))
		var kind: String = KINDS.get(style, "giant_tree")
		if role == "grove": kind = "giant_tree"
		var at := _spot(ii)
		if at == Vector3.INF:
			continue
		var n := _make(kind, style, at)
		parent.add_child(n)
		spots.append({"pos": at, "kind": kind, "island": ii})

## A point in the void just off the island's north coast, clear of pads, updrafts, winds, glide
## routes, bridges and the train. INF if there's none.
func _spot(ii: int) -> Vector3:
	var c: Vector2 = W.islands[ii]["c"]
	var best := Vector3.INF
	var best_s := -1e9
	for k in 48:
		var a := TAU * k / 48.0
		# walk out from the middle to the coast
		var d := 2.0
		var last_y := 0.0
		var hit := false
		while d < 60.0:
			var p := c + Vector2(cos(a), sin(a)) * d
			if W.is_void(p.x, p.y):
				hit = true
				break
			last_y = W.ground_at(p.x, p.y)
			d += 0.5
		if not hit:
			continue
		var p := c + Vector2(cos(a), sin(a)) * (d + 5.5)
		# open void all round it (not a notch in the coast, nor beside a bridge)
		var ok := true
		for q in 12:
			var qa := TAU * q / 12.0
			for qr in [2.0, 4.5]:
				if not W.is_void(p.x + cos(qa) * qr, p.y + sin(qa) * qr): ok = false
		if not W.is_void(p.x, p.y): ok = false
		if not ok:
			continue
		var score := -sin(a) * 10.0     # north (toward -z) is behind everything from the camera
		for pd in W.pads:
			score -= 30.0 * float(Vector2(pd["pos"].x, pd["pos"].z).distance_to(p) < 9.0)
			score -= 30.0 * float(Vector2(pd["land"].x, pd["land"].z).distance_to(p) < 7.0)
		for u in W.updrafts:
			score -= 30.0 * float(Vector2(u["pos"].x, u["pos"].z).distance_to(p) < 8.0)
		for wd in W.winds:
			score -= 30.0 * float(_seg_dist(p, Vector2(wd["a"].x, wd["a"].z), Vector2(wd["b"].x, wd["b"].z)) < 6.0)
		for gl in W.links:
			score -= 30.0 * float(_seg_dist(p, Vector2(gl["take"].x, gl["take"].z), Vector2(gl["land"].x, gl["land"].z)) < 6.0)
		for bi in W.bridge:
			var bx: int = int(bi) % W.w; var bz: int = int(bi) / W.w
			if Vector2(bx, bz).distance_to(p) < 7.0:
				score -= 30.0
				break
		if not W.train_route.is_empty():
			if absf(p.distance_to(W.train_route["center"]) - float(W.train_route["r"])) < 7.0: score -= 30.0
		if score > best_s:
			best_s = score
			best = Vector3(p.x, last_y, p.y)
	return best if best_s > -25.0 else Vector3.INF

static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)

## The landmark on its floating rock; its feet at the island's ground level.
func _make(kind: String, style: String, at: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "Landmark_" + kind
	root.position = at - Vector3(0, 0.6, 0)
	# the floating rock it stands on: a boulder upside down, flat side up, tapering below
	var rock := Flora.node("rock", style, 1, 1.0)
	rock.scale = Vector3(5.2, 4.2, 5.2)
	rock.rotation = Vector3(PI, 0.7, 0)
	rock.position = Vector3(0, 0.25, 0)
	root.add_child(rock)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh(kind, style)
	mi.material_override = Flora.material("tree" if kind in ["arch", "giant_tree"] else "rock", true)
	root.add_child(mi)
	match kind:
		"ring":
			# the ring turns slowly above its crystal, tilted
			var ring := MeshInstance3D.new()
			ring.mesh = _ring_mesh()
			ring.material_override = Flora.material("crystal", true)
			var piv := Node3D.new(); piv.position = Vector3(0, 7.5, 0)
			piv.rotation = Vector3(0.35, 0, 0.2)
			root.add_child(piv)
			piv.add_child(ring)
			PropAnim.on(piv, 0.18, 0.25, 0.7)
			_sparks(root, Color("c8a0ff"), Vector3(0, 7.5, 0), 3.5, "motes")
		"spire":
			for k in 4:
				var fr := Flora.node("rock", "storm", k % 3, 0.9 + k * 0.25)
				var a := TAU * k / 4.0
				var piv := Node3D.new(); piv.position = Vector3(0, 4.0 + k * 1.6, 0)
				root.add_child(piv)
				fr.position = Vector3(cos(a), 0, sin(a)) * (2.6 - k * 0.3)
				fr.rotation = Vector3(0.6 * k, a, 0.3)
				piv.add_child(fr)
				PropAnim.on(piv, 0.25 + k * 0.07, 0.2, 0.9 + k * 0.2)
			_sparks(root, Color("fff2a0"), Vector3(0, 12.6, 0), 1.0, "sparks")
		"chimney":
			_sparks(root, Color("ff7a2a"), Vector3(0, 10.6, 0), 0.9, "embers")
			var lamp := OmniLight3D.new(); lamp.light_color = Color("ff8a3a"); lamp.light_energy = 1.4; lamp.omni_range = 8.0
			lamp.position = Vector3(0, 10.5, 0); lamp.shadow_enabled = false
			root.add_child(lamp)
		"statue":
			_sparks(root, Color(0.9, 0.95, 1.0), Vector3(0, 6.0, 0), 3.0, "snow")
	return root

func _sparks(root: Node3D, col: Color, at: Vector3, r: float, kind: String) -> void:
	var p := CPUParticles3D.new()
	p.amount = 22; p.lifetime = 3.0; p.preprocess = 3.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE; p.emission_sphere_radius = r
	p.direction = Vector3.UP; p.spread = 30.0
	p.gravity = Vector3(0, 0.6 if kind == "embers" else (-0.4 if kind == "snow" else 0.1), 0)
	p.initial_velocity_min = 0.4; p.initial_velocity_max = 1.4 if kind == "embers" else 0.6
	p.position = at
	root.add_child(p)
	var qm := QuadMesh.new(); qm.size = Vector2(0.22, 0.22)
	p.mesh = qm
	var m := ShaderMaterial.new(); m.shader = load("res://shaders/mote.gdshader")
	m.set_shader_parameter("core", 0.9)
	m.set_shader_parameter("intensity", 1.6)
	if kind == "sparks": m.set_shader_parameter("stretch", 2.5)
	p.material_override = m
	p.color = col
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.75, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	p.color_ramp = g

# ------------------------------------------------------------------ meshes
static var _meshes := {}
static func mesh(kind: String, style: String) -> ArrayMesh:
	var key := kind + "/" + style
	if _meshes.has(key):
		return _meshes[key]
	var b := Flora.MB.new()
	var r := RandomNumberGenerator.new(); r.seed = hash(key)
	match kind:
		"statue": _statue(b, r)
		"chimney": _chimney(b, r)
		"spire": _spire(b, r)
		"arch": _arch(b, r)
		"ring": _ring_base(b, r)
		_: _giant_tree(b, style, r)
	var m := b.commit()
	_meshes[key] = m
	return m

## A hooded guardian of pale stone, frosted over, resting both hands on a sword of ice.
static func _statue(b: Flora.MB, r: RandomNumberGenerator) -> void:
	var st := [Color("5a6884"), Color("98a8c4"), Color("d4e0f0"), Color("f4f9ff")]
	var ht := 9.0
	# the robe: a tapering column, flared at the hem, with folds
	var pts: Array = []; var rad: Array = []
	for k in 9:
		var t := k / 8.0
		pts.append(Vector3(0, t * 6.2, -0.1 * t))
		rad.append(lerpf(1.55, 0.95, pow(t, 0.7)) * (1.0 + 0.12 * (1.0 - t)))
	_column(b, pts, rad, 16, st, ht, 7, 0.08)
	# shoulders and the hood
	var blobs := [{"c": Vector3(-0.85, 6.1, 0), "r": 0.75}, {"c": Vector3(0.85, 6.1, 0), "r": 0.75}, {"c": Vector3(0, 6.9, -0.15), "r": 0.95}]
	Flora._blob(b, Vector3(-0.85, 6.0, 0), Vector3(0.78, 0.6, 0.7), blobs, [Vector3(0, 6.2, 0), 2.0], st, 5.0, 8.0, ht, 0.08, 1.0, 2, 2.0)
	Flora._blob(b, Vector3(0.85, 6.0, 0), Vector3(0.78, 0.6, 0.7), blobs, [Vector3(0, 6.2, 0), 2.0], st, 5.0, 8.0, ht, 0.08, 2.0, 2, 2.0)
	Flora._blob(b, Vector3(0, 7.0, -0.15), Vector3(0.82, 1.0, 0.85), blobs, [Vector3(0, 6.6, 0), 1.6], st, 5.0, 8.2, ht, 0.06, 3.0, 2, 2.0)
	# the face in the hood's shadow
	var dark := [Color("1a2030"), Color("2a3448"), Color("3a4862"), Color("4a5a78")]
	Flora._blob(b, Vector3(0, 6.85, 0.52), Vector3(0.5, 0.6, 0.35), [], [Vector3(0, 6.85, 0.3), 0.8], dark, 6.3, 7.4, ht, 0.03, 4.0, 2, 2.0)
	# glowing eyes
	for sx in [-0.17, 0.17]:
		var e := Vector3(sx, 6.95, 0.8)
		Flora._blob(b, e, Vector3(0.07, 0.05, 0.05), [], [e, 0.1], [Color("8ad8ff"), Color("bff0ff"), Color("ffffff"), Color("ffffff")], 6.9, 7.0, ht, 0.0, 5.0, 1, 3.0, 0.9)
	# arms down to the hands on the hilt
	for sx in [-1.0, 1.0]:
		var arm := [Vector3(sx * 0.95, 5.9, 0.1), Vector3(sx * 0.9, 5.0, 0.55), Vector3(sx * 0.45, 4.3, 1.15), Vector3(sx * 0.15, 4.15, 1.35)]
		Flora._tube(b, arm, [0.42, 0.4, 0.34, 0.3], 10, st[1], st[2], ht, 0.0, 2.0, true)
	Flora._blob(b, Vector3(0, 4.15, 1.4), Vector3(0.42, 0.34, 0.34), [], [Vector3(0, 4.15, 1.4), 0.5], st, 3.8, 4.5, ht, 0.05, 6.0, 2, 2.0)
	# the sword of ice, point down in front of the robe
	var ice := [Color("2a6a9a"), Color("6ac0ff"), Color("c8f0ff"), Color("ffffff")]
	Flora._shard(b, Vector3(0, 4.6, 1.42), Vector3(0, -1, 0.02).normalized(), 4.3, 0.22, ice, ht, 0.0, 0.45)
	Flora._tube(b, [Vector3(-0.7, 4.55, 1.42), Vector3(0.7, 4.55, 1.42)], [0.11, 0.11], 6, st[1], st[2], ht, 0.0, 2.0, true)
	Flora._tube(b, [Vector3(0, 4.5, 1.42), Vector3(0, 5.2, 1.42)], [0.08, 0.08], 6, st[0], st[1], ht, 0.0, 2.0, true)
	# frost crystals growing at the hem
	for k in 6:
		var a := TAU * k / 6.0 + r.randf()
		Flora._shard(b, Vector3(cos(a) * 1.5, 0.0, sin(a) * 1.5), Vector3(cos(a) * 0.5, 1.0, sin(a) * 0.5).normalized(), r.randf_range(0.8, 1.4), 0.2, ice, ht, r.randf() * TAU, 0.4)

## A vertical column (robe, chimney) with folds or bands, snow or soot on its upward faces.
static func _column(b: Flora.MB, pts: Array, rad: Array, seg: int, pal: Array, ht: float, folds: int, fold_amp: float, bands := 0.0, glow_bands := false) -> void:
	var base := b.v.size()
	var n: int = pts.size()
	for i in n:
		var p: Vector3 = pts[i]
		var t := float(i) / (n - 1)
		for j in seg + 1:
			var a := TAU * j / seg
			var fold := 1.0 + fold_amp * sin(a * folds) * (1.0 - t * 0.5)
			var rr: float = float(rad[i]) * fold
			var q := p + Vector3(cos(a) * rr, 0, sin(a) * rr)
			var nn := Vector3(cos(a), 0.15, sin(a)).normalized()
			var col: Color = (pal[0] as Color).lerp(pal[1], smoothstep(0.0, 0.5, t)).lerp(pal[2], smoothstep(0.4, 1.0, t) * 0.6)
			col = col.lerp(pal[0], (0.5 - 0.5 * sin(a * folds)) * fold_amp * 3.0)
			col = col.darkened((1.0 - smoothstep(0.0, 0.12, t)) * 0.35)
			if bands > 0.0:
				var bb := fposmod(q.y / bands, 1.0)
				if bb < 0.12:
					col = col.darkened(0.3)
					if glow_bands and int(q.y / bands) % 2 == 1:
						col = col.lerp(Color("ff6a1a"), 0.85); col.a = 0.2
			b.add(q, nn, col, 2.0, clampf(q.y / ht, 0.0, 1.0), 0.0)
	for i in n - 1:
		for j in seg:
			var a: int = base + i * (seg + 1) + j
			var bb: int = a + 1
			var c: int = a + seg + 2
			var d: int = a + seg + 1
			b.tri(a, bb, c); b.tri(a, c, d)

## A stone forge chimney: a tapering stack banded with glowing seams, buttressed at its foot, its
## mouth glowing.
static func _chimney(b: Flora.MB, r: RandomNumberGenerator) -> void:
	var st := [Color("2a1a1a"), Color("6a3a2c"), Color("a8684a"), Color("d89a6a")]
	var ht := 11.0
	var pts: Array = []; var rad: Array = []
	for k in 11:
		var t := k / 10.0
		pts.append(Vector3(0.15 * sin(t * 2.0), t * 10.0, 0))
		rad.append(lerpf(1.6, 0.95, t) + (0.18 if k == 10 else 0.0))
	_column(b, pts, rad, 14, st, ht, 14, 0.035, 1.25, true)
	# the lip and the glow inside it
	Flora._tube(b, [Vector3(0.14, 10.0, 0), Vector3(0.14, 10.45, 0)], [1.25, 1.18], 14, st[1], st[2], ht, 0.0, 2.0)
	var glow := [Color("ff4a10"), Color("ff8a2a"), Color("ffc060"), Color("fff0b0")]
	Flora._blob(b, Vector3(0.14, 10.25, 0), Vector3(1.05, 0.3, 1.05), [], [Vector3(0.14, 10.0, 0), 1.2], glow, 10.0, 10.5, ht, 0.1, 1.0, 2, 3.0, 0.95)
	# buttresses and rubble at the foot
	for k in 5:
		var a := TAU * k / 5.0 + r.randf()
		var p := Vector3(cos(a) * 1.6, 0.4, sin(a) * 1.6)
		Flora._blob(b, p, Vector3(0.75, 0.8, 0.75) * r.randf_range(0.8, 1.2), [], [p, 1.0], st, 0.0, 1.4, ht, 0.3, k * 3.0, 2, 2.0)
	# a smaller second flue
	var p2: Array = []; var r2: Array = []
	for k in 5:
		p2.append(Vector3(1.55, 0.5 + k * 1.3, 0.6)); r2.append(lerpf(0.55, 0.42, k / 4.0))
	_column(b, p2, r2, 10, st, ht, 10, 0.03, 1.25, true)

## A twisting spire of storm rock, crowned with a glowing crystal.
static func _spire(b: Flora.MB, r: RandomNumberGenerator) -> void:
	var st := [Color("23243a"), Color("4a4e72"), Color("8a90b8"), Color("c8ccec")]
	var ht := 13.0
	for arm in 3:
		var pts: Array = []; var rad: Array = []
		var a0 := TAU * arm / 3.0
		for k in 13:
			var t := k / 12.0
			var a := a0 + t * 2.4
			var off := 0.75 * (1.0 - t)
			pts.append(Vector3(cos(a) * off, t * 11.5 * (0.85 + 0.15 * arm / 2.0), sin(a) * off))
			rad.append(lerpf(1.0, 0.12, pow(t, 0.9)))
		Flora._tube(b, pts, rad, 9, st[0], st[2], ht, 0.5, 2.0, true, 0.0, arm * 2.0)
	var cry := [Color("8a7a1a"), Color("f2e46a"), Color("fff6b0"), Color("ffffff")]
	Flora._shard(b, Vector3(0, 10.6, 0), Vector3.UP, 2.6, 0.45, cry, ht, 0.0, 0.85)
	for k in 4:
		var a := TAU * k / 4.0 + 0.4
		Flora._shard(b, Vector3(0, 10.7, 0), Vector3(cos(a) * 0.6, 1.0, sin(a) * 0.6).normalized(), 1.3, 0.24, cry, ht, a, 0.75)

## Two blossoming trunks arching over to meet, hung with flowers.
static func _arch(b: Flora.MB, r: RandomNumberGenerator) -> void:
	var P: Dictionary = Flora.PAL["bloom"]
	var ht := 8.5
	for sx in [-1.0, 1.0]:
		var pts: Array = []; var rad: Array = []
		for k in 10:
			var t := k / 9.0
			var a := t * PI * 0.5
			pts.append(Vector3(sx * 3.4 * cos(a), 7.2 * sin(a) + 0.2 * sin(t * 9.0), 0.35 * sin(t * 5.0 + sx)))
			rad.append(lerpf(0.62, 0.32, t))
		Flora._tube(b, pts, rad, 10, P["bark"][0], P["bark"][1], ht, 0.9, 1.0, false, 0.0, sx * 3.0)
	var blobs: Array = []
	for k in 13:
		var t := k / 12.0
		var a := lerpf(0.35, PI - 0.35, t)
		var c := Vector3(cos(a) * 3.3, sin(a) * 7.0 + 0.5, r.randf_range(-0.5, 0.5))
		var rr := r.randf_range(0.8, 1.15)
		blobs.append({"c": c, "r": rr, "s": Vector3(rr, rr * 0.8, rr)})
	for k in blobs.size():
		Flora._blob(b, blobs[k]["c"], blobs[k]["s"], blobs, [Vector3(0, 6.2, 0), 4.0], P["leaf"], 3.0, 8.4, ht, 0.15, k * 3.1, 2, 5.0)
	# hanging blossom strands
	for k in 7:
		var x := lerpf(-2.0, 2.0, k / 6.0)
		var top := Vector3(x, 6.6 - absf(x) * 0.5, r.randf_range(-0.4, 0.4))
		for q in 3:
			var p := top - Vector3(0, 0.45 * (q + 1), 0)
			Flora._blob(b, p, Vector3.ONE * (0.2 - q * 0.04), [], [p, 0.3], [Color("d86aa0"), Color("ffa8d0"), Color("ffe0f0"), Color.WHITE], p.y - 0.2, p.y + 0.2, ht, 0.1, k * 2.0 + q, 1, 5.0, 0.1)

## A grove's giant: a huge broad tree.
static func _giant_tree(b: Flora.MB, style: String, r: RandomNumberGenerator) -> void:
	var P: Dictionary = Flora.PAL[style]
	var ht := 12.0
	var pts := Flora._limb(Vector3.ZERO, Vector3(0.3, 5.5, 0.2), 5.5, Vector3(0.4, 0, 0.2), 6)
	Flora._tube(b, pts, Flora._radii(1.0, 0.55, 6), 14, P["bark"][0], P["bark"][1], ht, 0.9, 1.0, false, 0.0, 1.0)
	for k in 4:
		var a := TAU * k / 4.0 + r.randf()
		var bp := Flora._limb(pts[4], Vector3(cos(a) * 0.9, 1.0, sin(a) * 0.9), 3.6, Vector3(0, 0.3, 0), 4)
		Flora._tube(b, bp, Flora._radii(0.4, 0.15, 4), 8, P["bark"][0], P["bark"][1], ht, 0.0, 1.0, true)
	var blobs: Array = []
	var cc := Vector3(0.4, 8.2, 0.2)
	blobs.append({"c": cc, "r": 2.6, "s": Vector3(2.9, 2.2, 2.9)})
	for k in 10:
		var a := TAU * k / 10.0 + r.randf_range(-0.3, 0.3)
		var rr := r.randf_range(1.2, 1.7)
		var c := cc + Vector3(cos(a) * 2.9, r.randf_range(-0.8, 1.2), sin(a) * 2.9)
		blobs.append({"c": c, "r": rr, "s": Vector3(rr, rr * 0.82, rr)})
	for k in 3:
		var a := r.randf() * TAU
		blobs.append({"c": cc + Vector3(cos(a), 1.9, sin(a)), "r": 1.4, "s": Vector3(1.5, 1.2, 1.5)})
	for k in blobs.size():
		Flora._blob(b, blobs[k]["c"], blobs[k]["s"], blobs, [cc - Vector3(0, 0.3, 0), 4.2], P["leaf"], 5.6, 11.2, ht, 0.14, k * 2.7, 2, 5.0 if style == "bloom" else 0.0)

## The Heart's crystal and the stone it rises from (the ring turns above it, see _ring_mesh).
static func _ring_base(b: Flora.MB, r: RandomNumberGenerator) -> void:
	var pal: Array = Flora.PAL["gloom"]["leaf"]
	Flora._shard(b, Vector3(0, 0.2, 0), Vector3.UP, 5.5, 0.8, pal, 10.0, 0.0, 0.7)
	for k in 6:
		var a := TAU * k / 6.0 + r.randf()
		Flora._shard(b, Vector3(cos(a) * 0.6, 0.0, sin(a) * 0.6), Vector3(cos(a) * 0.5, 1.0, sin(a) * 0.5).normalized(), r.randf_range(2.0, 3.4), 0.4, pal, 10.0, a, 0.6)
	var st: Array = Flora.PAL["gloom"]["stone"]
	var stone := [st[0], st[1], st[2], (st[2] as Color).lightened(0.2)]
	for k in 7:
		var a := TAU * k / 7.0
		var p := Vector3(cos(a) * 2.2, 0.3, sin(a) * 2.2)
		Flora._blob(b, p, Vector3(0.8, 0.7, 0.8), [], [p, 1.0], stone, 0.0, 1.2, 10.0, 0.3, k * 2.0, 2, 2.0)

static var _ring: ArrayMesh
## A great stone ring carved with runes that glow.
static func _ring_mesh() -> ArrayMesh:
	if _ring:
		return _ring
	var b := Flora.MB.new()
	var st: Array = Flora.PAL["gloom"]["stone"]
	var R := 4.4; var rt := 0.5
	var seg := 64; var sides := 10
	var base := b.v.size()
	for i in seg + 1:
		var a := TAU * i / seg
		var c := Vector3(cos(a) * R, 0, sin(a) * R)
		var out := Vector3(cos(a), 0, sin(a))
		var rune := (i % 8) in [2, 3, 4, 5]
		for j in sides + 1:
			var q := TAU * j / sides
			var nn := out * cos(q) + Vector3.UP * sin(q)
			var flat := 1.0 if absf(sin(q)) < 0.7 else 0.85
			var p := c + nn * rt * flat * Vector3(1, 1.5, 1)
			var col: Color = (st[0] as Color).lerp(st[2], 0.5 + 0.5 * sin(q))
			if rune and absf(cos(q)) > 0.8:
				col = Color("c8a0ff"); col.a = 0.15
			b.add(p, nn, col, 2.0, 0.0, 0.0)
	for i in seg:
		for j in sides:
			var a := base + i * (sides + 1) + j
			var bb := a + 1
			var c := a + sides + 2
			var d := a + sides + 1
			b.tri(a, c, bb); b.tri(a, d, c)
	_ring = b.commit()
	return _ring
