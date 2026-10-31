class_name Flora
## The world's props, sculpted in code (all original, no imported models): trees, boulders, bushes,
## ferns, flowers, mushrooms, reeds and crystals for each biome style ("meadow", "bloom", "frost",
## "ember", "storm", "gloom"), in a hand-painted MOBA look:
##  - chunky shapes from overlapping smooth blobs, their normals bent out from the middle of the
##    whole canopy so a cluster of blobs shades as one soft mass;
##  - colour painted into the vertices: light tops, cool undersides, dark creases where one leaf
##    clump tucks under the next, dark feet where a trunk or rock meets the ground;
##  - UV.x is a material id for the shader's brushwork (see shaders/flora.gdshader), UV2.x how far a
##    vertex bends in the wind and UV2.y how much it flutters; vertex alpha below 1 glows.
## Meshes are cached per (kind, style, variant), so a whole map's scatter costs a few dozen meshes;
## the world batches them in MultiMesh chunks. Purely visual: what blocks is still the map data.

const STYLES := ["meadow", "bloom", "frost", "ember", "storm", "gloom"]
const VARIANTS := 3
static var SHADER: Shader = preload("res://shaders/flora.gdshader")
static var _cache := {}
static var _mats := {}
static var _ico_cache := {}
static var _noise: FastNoiseLite

## Leaf, bark and stone colours per style: dark (deep shadow / crease), mid, light (sunlit top),
## tip (the brightest dabs).
const PAL := {
	"meadow": {"leaf": [Color("213e2c"), Color("3a6c38"), Color("74a442"), Color("c0d470")], "bark": [Color("3a2a26"), Color("6e4c36")],
		"stone": [Color("5d5a62"), Color("948c88"), Color("c4bcb0")], "cap": [Color("4c7a34"), Color("8cb850")], "bush": [Color("27502f"), Color("4b8a40"), Color("9cc858")]},
	"bloom": {"leaf": [Color("94507e"), Color("dc8cb6"), Color("fbbcd8"), Color("fff0f6")], "bark": [Color("3e2a30"), Color("7a5248")],
		"stone": [Color("4e5a5c"), Color("7e8a86"), Color("b4beb0")], "cap": [Color("2f7a5c"), Color("5cb88a")], "bush": [Color("1f5a48"), Color("36906a"), Color("72c890")]},
	"frost": {"leaf": [Color("14303a"), Color("22504e"), Color("3c7a68"), Color("7ab09a")], "bark": [Color("2e2a34"), Color("5e5260")],
		"stone": [Color("4a5670"), Color("7a8aa4"), Color("b0bed2")], "cap": [Color("c4d6ea"), Color("f4f9ff")], "bush": [Color("1d4248"), Color("3a6a6a"), Color("7aa8a2")]},
	"ember": {"leaf": [Color("4a1414"), Color("9a2e1c"), Color("e05a26"), Color("ffb050")], "bark": [Color("1c1416"), Color("4a3430")],
		"stone": [Color("3a2224"), Color("6e3e30"), Color("a8684a")], "cap": [Color("3a3434"), Color("6e6460")], "bush": [Color("3a2420"), Color("6a4030"), Color("a86a3a")]},
	"storm": {"leaf": [Color("1e3a4a"), Color("2f6070"), Color("5a9a9a"), Color("a8dcc8")], "bark": [Color("262634"), Color("525470")],
		"stone": [Color("3c3e58"), Color("62668a"), Color("9aa0c4")], "cap": [Color("4a6a6a"), Color("7aa8a0")], "bush": [Color("1e3e4a"), Color("2f6a72"), Color("6aa8a0")]},
	"gloom": {"leaf": [Color("3a2a6a"), Color("7a5ad0"), Color("b89aff"), Color("f0e4ff")], "bark": [Color("1a1424"), Color("4a3a5e")],
		"stone": [Color("2a2434"), Color("4e4460"), Color("7e7294")], "cap": [Color("5a4a8a"), Color("9a80d8")], "bush": [Color("2a2248"), Color("4a3a7a"), Color("8a6ad0")]},
}

const SUN := Vector3(0.45, 0.75, 0.45)
## Finer canopy clumps (more triangles); off by default, the gallery's close-ups can turn it on.
static var LOD_FINE := false

static func on() -> bool:
	return not ("--prim-art" in OS.get_cmdline_user_args() or "--pack-flora" in OS.get_cmdline_user_args())

static func style_ok(style: String) -> String:
	return style if PAL.has(style) else "meadow"

# ------------------------------------------------------------------ public
## A cached mesh: kind is "tree", "rock", "bush", "fern", "flower", "mushroom", "reed", "crystal",
## "pebble"; variant 0..VARIANTS-1.
static func mesh(kind: String, style: String, variant: int) -> ArrayMesh:
	style = style_ok(style)
	var key := "%s/%s/%d" % [kind, style, variant]
	if _cache.has(key):
		return _cache[key]
	var b := MB.new()
	var r := RandomNumberGenerator.new()
	r.seed = hash(key)
	match kind:
		"tree": _tree(b, style, variant, r)
		"rock":
			_rock(b, style, r, Vector3(0.6, 0.78, 0.54), 0.5, true)
			if variant > 0:
				var a := r.randf() * TAU
				_rock(b, style, r, Vector3(0.3, 0.34, 0.28), 0.5, true, 2, Vector3(cos(a) * 0.55, 0, sin(a) * 0.45))
		"pebble": _rock(b, style, r, Vector3(0.2, 0.13, 0.17), 0.3, false, 1)
		"bush": _bush(b, style, variant, r)
		"fern": _fern(b, style, r)
		"flower": _flowers(b, style, r)
		"mushroom": _mushrooms(b, style, r)
		"reed": _reeds(b, style, r)
		"crystal": _crystal_cluster(b, style, r, 0.55)
		"pillar": _pillar(b, style, variant, r)
		"pine": _pine(b, style, variant, r)
		_: _rock(b, style, r, Vector3(0.6, 0.5, 0.5), 0.5, true)
	var m := b.commit()
	_cache[key] = m
	return m

## The material for a kind: trees and bushes sway, rocks don't, crystals glow brighter.
static func material(kind: String, outline := true) -> ShaderMaterial:
	var key := kind + str(outline)
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = SHADER
	match kind:
		"tree":
			m.set_shader_parameter("sway", 0.09); m.set_shader_parameter("flutter", 0.02); m.set_shader_parameter("wrap", 0.2)
			m.set_shader_parameter("rim_amount", 0.55)
		"bush", "fern", "flower", "reed":
			m.set_shader_parameter("sway", 0.07); m.set_shader_parameter("flutter", 0.015); m.set_shader_parameter("wrap", 0.5)
			m.set_shader_parameter("rim_amount", 0.3)
		"mushroom", "crystal":
			m.set_shader_parameter("sway", 0.0); m.set_shader_parameter("wrap", 0.25)
		_:
			m.set_shader_parameter("sway", 0.0); m.set_shader_parameter("rim_amount", 0.32)
	if outline:
		m.next_pass = Assets.outline_mat()
	_mats[key] = m
	return m

## A single prop as a node (for one-offs like the home island's decorations).
static func node(kind: String, style: String, variant: int, scale := 1.0) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh(kind, style, variant)
	mi.material_override = material("tree" if kind == "pine" else kind, kind in ["rock", "crystal", "pillar"])
	mi.scale = Vector3.ONE * scale
	root.add_child(mi)
	root.set_meta("mats", [mi.material_override])
	return root

# ------------------------------------------------------------------ mesh builder
class MB:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	func add(p: Vector3, nn: Vector3, col: Color, mat_id: float, bend: float, flut: float) -> int:
		v.append(p); n.append(nn); c.append(col); uv.append(Vector2(mat_id, 0.0)); uv2.append(Vector2(bend, flut))
		return v.size() - 1
	func tri(a: int, b: int, cc: int) -> void:
		idx.append(a); idx.append(b); idx.append(cc)
	func commit() -> ArrayMesh:
		var arrs := []
		arrs.resize(Mesh.ARRAY_MAX)
		arrs[Mesh.ARRAY_VERTEX] = v
		arrs[Mesh.ARRAY_NORMAL] = n
		# the outline shell (shaders/outline_smooth.gdshader) grows along TANGENT: the smooth normal
		var tan := PackedFloat32Array(); tan.resize(v.size() * 4)
		for k in v.size():
			tan[k * 4] = n[k].x; tan[k * 4 + 1] = n[k].y; tan[k * 4 + 2] = n[k].z; tan[k * 4 + 3] = 1.0
		arrs[Mesh.ARRAY_TANGENT] = tan
		arrs[Mesh.ARRAY_COLOR] = c
		arrs[Mesh.ARRAY_TEX_UV] = uv
		arrs[Mesh.ARRAY_TEX_UV2] = uv2
		arrs[Mesh.ARRAY_INDEX] = idx
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrs)
		return am

static func _n3(p: Vector3) -> float:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise.frequency = 1.0
		_noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	return _noise.get_noise_3dv(p)

## A unit icosphere: [verts, indices], subdivided `level` times.
static func ico(level: int) -> Array:
	if _ico_cache.has(level):
		return _ico_cache[level]
	var t := (1.0 + sqrt(5.0)) / 2.0
	var vs: Array = [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	for k in vs.size(): vs[k] = (vs[k] as Vector3).normalized()
	var fs: Array = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for _l in level:
		var mid := {}
		var nf: Array = []
		for f in fs:
			var m: Array = []
			for e in 3:
				var a: int = f[e]; var b: int = f[(e + 1) % 3]
				var key := Vector2i(mini(a, b), maxi(a, b))
				if not mid.has(key):
					vs.append(((vs[a] as Vector3) + (vs[b] as Vector3)).normalized())
					mid[key] = vs.size() - 1
				m.append(mid[key])
			nf.append([f[0], m[0], m[2]]); nf.append([f[1], m[1], m[0]]); nf.append([f[2], m[2], m[1]]); nf.append([m[0], m[1], m[2]])
		fs = nf
	var pv := PackedVector3Array(vs)
	var pi := PackedInt32Array()
	for f in fs:
		# outward winding for Godot (clockwise seen from outside)
		pi.append(f[0]); pi.append(f[2]); pi.append(f[1])
	_ico_cache[level] = [pv, pi]
	return _ico_cache[level]

## One clump of a canopy. blobs: every clump of this canopy [{c, r}] (for the dark creases where
## clumps meet); mass: [centre, radius] of the whole canopy (normals bend out from it); pal: the
## dark/mid/light/tip colours; y0/y1 the canopy's height range; ht the tree's height (for the bend).
static func _blob(b: MB, ctr: Vector3, rad: Vector3, blobs: Array, mass: Array, pal: Array, y0: float, y1: float, ht: float,
		bumps: float, seed: float, level := 2, mat_id := 0.0, glow := 0.0, spiky := 0.0) -> void:
	var I := ico(level)
	var uvs: PackedVector3Array = I[0]
	var base := b.v.size()
	var mc: Vector3 = mass[0]
	var mr: float = mass[1]
	for u in uvs:
		var bump := _n3(u * 1.6 + Vector3(seed, seed * 0.7, -seed)) * bumps
		# small scallops along the edge of a leaf clump
		if mat_id == 0.0 or mat_id == 5.0:
			bump += _n3(u * 5.2 + Vector3(seed * 1.7, 0, seed)) * bumps * 0.4
		if spiky > 0.0:
			bump += pow(maxf(0.0, _n3(u * 3.2 + Vector3(-seed, seed, seed * 1.3))), 2.0) * spiky
		var p := ctr + Vector3(u.x * rad.x, u.y * rad.y, u.z * rad.z) * (1.0 + bump)
		var own := Vector3(u.x / rad.x, u.y / rad.y, u.z / rad.z).normalized()
		var out := (p - mc).normalized()
		var leafy := mat_id == 0.0 or mat_id == 5.0
		var nn := own.lerp(out, 0.74 if leafy else 0.62).normalized()
		# crease darkness: how close this point sits to another clump's surface
		var cr := 0.0
		for o in blobs:
			var oc: Vector3 = o["c"]
			if oc.is_equal_approx(ctr): continue
			# only right where this clump tucks under the next (points inside it are hidden anyway)
			var dd := (p - oc).length() / float(o["r"])
			cr = maxf(cr, 1.0 - smoothstep(1.0, 1.22, dd))
		var depth := clampf(1.0 - (p - mc).length() / mr, 0.0, 1.0)
		var hf := clampf((p.y - y0) / maxf(0.01, y1 - y0), 0.0, 1.0)
		var up := nn.y
		var col: Color = (pal[0] as Color).lerp(pal[1], smoothstep(-0.75, 0.15, up))
		col = col.lerp(pal[2], smoothstep(0.25, 0.9, up) * (0.45 + 0.55 * hf))
		var sunk := smoothstep(0.55, 0.95, nn.dot(SUN.normalized()))
		col = col.lerp(pal[3], sunk * 0.35 * hf)
		if leafy:
			# each clump keeps its own form too: a lit crown and a shaded belly
			col = col.lerp(pal[2], smoothstep(0.25, 0.95, own.y) * 0.3)
			col = col.lerp(pal[0], smoothstep(-0.15, -0.85, own.y) * 0.45)
		col = col.lerp(pal[0], clampf(cr * 0.6 + depth * 0.45, 0.0, 0.7))
		col.a = 1.0 - glow
		b.add(p, nn, col, mat_id, clampf(p.y / maxf(ht, 0.01), 0.0, 1.0), 1.0)
	var ids: PackedInt32Array = I[1]
	for k in range(0, ids.size(), 3):
		b.tri(base + ids[k], base + ids[k + 1], base + ids[k + 2])

## A tapered tube along a polyline (trunks, branches, roots, stems). flare: root lobes at the foot.
static func _tube(b: MB, pts: Array, radii: Array, seg: int, c0: Color, c1: Color, ht: float, flare := 0.0, mat_id := 1.0,
		cap := false, glow_cracks := 0.0, seed := 0.0) -> void:
	var rings := pts.size()
	var base := b.v.size()
	var prev_side := Vector3.RIGHT
	for i in rings:
		var p: Vector3 = pts[i]
		var dir: Vector3
		if i == 0: dir = (pts[1] as Vector3) - p
		elif i == rings - 1: dir = p - (pts[i - 1] as Vector3)
		else: dir = (pts[i + 1] as Vector3) - (pts[i - 1] as Vector3)
		dir = dir.normalized()
		var side := prev_side - dir * prev_side.dot(dir)
		if side.length() < 0.01: side = Vector3.FORWARD - dir * Vector3.FORWARD.dot(dir)
		side = side.normalized()
		prev_side = side
		var fwd := dir.cross(side).normalized()
		var t := float(i) / float(rings - 1)
		for j in seg:
			var a := TAU * j / seg
			var rr: float = radii[i]
			if flare > 0.0:
				rr *= 1.0 + flare * pow(maxf(0.0, 1.0 - t * 3.2), 2.0) * (0.55 + 0.45 * cos(a * 4.0 + seed))
			var radial := side * cos(a) + fwd * sin(a)
			var q := p + radial * rr * (1.0 + _n3(Vector3(cos(a) * 2.0, p.y * 3.0, sin(a) * 2.0) + Vector3(seed, 0, 0)) * 0.12)
			var col := c0.lerp(c1, smoothstep(0.0, 0.7, t))
			# the foot sits in its own shadow
			col = col.darkened((1.0 - smoothstep(0.0, 0.35, q.y)) * 0.35)
			if glow_cracks > 0.0:
				var g := smoothstep(0.42, 0.6, _n3(Vector3(a * 1.3, q.y * 4.0, seed)))
				if g > 0.0:
					col = col.lerp(Color("ff7a2a"), g)
					col.a = 1.0 - g * glow_cracks
			b.add(q, radial, col, mat_id, clampf(q.y / maxf(ht, 0.01), 0.0, 1.0), 0.0)
	for i in rings - 1:
		for j in seg:
			var a := base + i * seg + j
			var bb := base + i * seg + (j + 1) % seg
			var cc := base + (i + 1) * seg + (j + 1) % seg
			var d := base + (i + 1) * seg + j
			b.tri(a, cc, bb); b.tri(a, d, cc)
	if cap:
		var tip: Vector3 = pts[rings - 1]
		var ti := b.add(tip + ((pts[rings - 1] as Vector3) - (pts[rings - 2] as Vector3)).normalized() * float(radii[rings - 1]) * 0.6,
			((pts[rings - 1] as Vector3) - (pts[rings - 2] as Vector3)).normalized(), c1, mat_id, clampf(tip.y / maxf(ht, 0.01), 0.0, 1.0), 0.0)
		for j in seg:
			b.tri(base + (rings - 1) * seg + j, ti, base + (rings - 1) * seg + (j + 1) % seg)

## Points along a bent limb from a toward a + dir * len, curving by `bend`.
static func _limb(a: Vector3, dir: Vector3, length: float, bend: Vector3, n: int) -> Array:
	var out: Array = []
	for k in n + 1:
		var t := float(k) / n
		out.append(a + dir.normalized() * length * t + bend * t * t)
	return out

static func _radii(r0: float, r1: float, n: int) -> Array:
	var out: Array = []
	for k in n + 1:
		out.append(lerpf(r0, r1, pow(float(k) / n, 0.8)))
	return out

# ------------------------------------------------------------------ trees
static func _tree(b: MB, style: String, variant: int, r: RandomNumberGenerator) -> void:
	match style:
		"frost": _pine(b, style, variant, r)
		"ember":
			if variant == 2: _ember_tree(b, variant, r)
			else: _broadleaf(b, style, variant, r)
		"gloom": _crystal_tree(b, variant, r)
		_: _broadleaf(b, style, variant, r)

## A broad canopy of leaf clumps on a curving trunk: meadow (round, green), bloom (wide, pink
## blossom), storm (bent by the wind, swept and spiky).
static func _broadleaf(b: MB, style: String, variant: int, r: RandomNumberGenerator) -> void:
	var P: Dictionary = PAL[style]
	var storm := style == "storm"
	var bloom := style == "bloom"
	var ember := style == "ember"
	var ht := r.randf_range(3.1, 3.6) + variant * 0.2
	if bloom: ht -= 0.3
	var lean := Vector3(r.randf_range(-0.25, 0.25), 0, r.randf_range(-0.25, 0.25))
	if storm: lean = Vector3(0.9, 0, 0.25)
	var trunk_top := Vector3(lean.x * ht * 0.35, ht * 0.55, lean.z * ht * 0.35)
	var bend := Vector3(lean.x, 0, lean.z) * 0.6
	var pts := _limb(Vector3.ZERO, trunk_top - bend, trunk_top.length(), bend, 6)
	_tube(b, pts, _radii(0.2, 0.1, 6), 9, P["bark"][0], P["bark"][1], ht, 0.75, 1.0, false, 0.85 if ember else 0.0, r.randf() * 5.0)
	# two or three boughs up into the crown
	var crown := trunk_top + Vector3(0, ht * 0.18, 0)
	for k in 2 + variant % 2:
		var a := TAU * k / (2 + variant % 2) + r.randf()
		var d := Vector3(cos(a) * 0.7, 1.0, sin(a) * 0.7) + lean * 0.5
		var bp := _limb(pts[4], d, ht * 0.32, Vector3(0, 0.05, 0), 3)
		_tube(b, bp, _radii(0.085, 0.035, 3), 6, P["bark"][0], P["bark"][1], ht, 0.0, 1.0, true)
	# the canopy: one big mass, its outline scalloped by the clumps that bulge out of it
	var blobs: Array = []
	var cw := 1.3 if not bloom else 1.5
	var ch := 0.95 if not bloom else 0.8
	if storm: cw = 1.1; ch = 0.85
	if ember: cw = 1.15; ch = 0.85
	var cc := crown + Vector3(0, ch * 0.45, 0)
	blobs.append({"c": cc, "r": cw * 0.9, "s": Vector3(cw * 0.9, ch * 0.85, cw * 0.9)})
	var n := 7 + variant
	for k in n:
		var a := TAU * k / n + r.randf_range(-0.3, 0.3)
		var ring := r.randf_range(0.5, 0.68)
		var y := r.randf_range(-0.2, 0.4)
		var rr := r.randf_range(0.46, 0.58) * (1.1 if bloom else 1.0)
		var p := cc + Vector3(cos(a) * cw * ring, y * ch, sin(a) * cw * ring)
		if storm:
			p += Vector3(0.45, 0, 0.12) * (0.5 + 0.5 * cos(a))   # swept downwind
		var sc := Vector3(rr, rr * 0.82, rr)
		if storm: sc = Vector3(rr * 1.35, rr * 0.7, rr * 0.9)
		blobs.append({"c": p, "r": rr, "s": sc})
	for k in 2 + variant % 2:
		var a := r.randf() * TAU
		var rr := r.randf_range(0.42, 0.55)
		blobs.append({"c": cc + Vector3(cos(a) * 0.35, ch * 0.55, sin(a) * 0.35), "r": rr, "s": Vector3(rr, rr * 0.85, rr)})
	var lo := 1e9; var hi := -1e9
	for bl in blobs:
		lo = minf(lo, (bl["c"] as Vector3).y - (bl["s"] as Vector3).y); hi = maxf(hi, (bl["c"] as Vector3).y + (bl["s"] as Vector3).y)
	var mass := [cc + Vector3(0, -0.1, 0), cw * 1.15]
	var seed := r.randf() * 50.0
	for k in blobs.size():
		var bl: Dictionary = blobs[k]
		# the core is finely divided; the clumps bulging out of it are cheaper (it's their outline
		# that shows, and the noise breaks up their facets)
		_blob(b, bl["c"], bl["s"], blobs, mass, P["leaf"], lo, hi, ht, 0.16 if not storm else 0.1, seed + k * 3.7, 2 if k == 0 or LOD_FINE else 1, 5.0 if bloom else 0.0, 0.0, 0.32 if storm else 0.0)
	if ember:
		# embers smouldering in the crown
		for k in 7:
			var a := r.randf() * TAU
			var p := cc + Vector3(cos(a) * cw * r.randf_range(0.75, 1.0), r.randf_range(-0.2, 0.6) * ch, sin(a) * cw * r.randf_range(0.75, 1.0))
			_blob(b, p, Vector3.ONE * r.randf_range(0.05, 0.08), [], [p, 0.1], [Color("ff5a1a"), Color("ff8a2a"), Color("ffc060"), Color("fff0a0")], p.y - 0.1, p.y + 0.1, ht, 0.1, k * 1.7, 0, 3.0, 0.9)
	if bloom:
		# a few bright blossoms standing out of the canopy
		for k in 7:
			var a := r.randf() * TAU
			var p := cc + Vector3(cos(a) * cw * r.randf_range(0.5, 0.95), r.randf_range(0.0, 0.6) * ch, sin(a) * cw * r.randf_range(0.5, 0.95))
			_blob(b, p, Vector3.ONE * 0.13, [], [p, 0.2], [Color("ffd0e6"), Color("fff0f6"), Color("ffffff"), Color("ffffff")], p.y - 0.2, p.y + 0.2, ht, 0.05, k * 1.3, 1, 5.0, 0.15)

## A frosted pine: tiers of drooping, scalloped boughs with snow lying on top of each.
static func _pine(b: MB, style: String, variant: int, r: RandomNumberGenerator) -> void:
	var P: Dictionary = PAL[style]
	var ht := r.randf_range(3.3, 3.9) + variant * 0.25
	_tube(b, [Vector3.ZERO, Vector3(0, ht * 0.3, 0), Vector3(0, ht * 0.75, 0)], [0.17, 0.12, 0.05], 8, P["bark"][0], P["bark"][1], ht, 0.6, 1.0, false, 0.0, r.randf())
	var tiers := 4 + variant % 2
	var seed := r.randf() * 20.0
	for k in tiers:
		var t := float(k) / tiers
		var y := lerpf(ht * 0.22, ht * 0.86, t)
		var rad := lerpf(1.15, 0.38, t) * r.randf_range(0.92, 1.05)
		var hgt := lerpf(0.95, 0.6, t)
		_bough(b, Vector3(0, y, 0), rad, hgt, P["leaf"], P["cap"], ht, seed + k * 2.3, 13 + (tiers - k))
	# the tip
	_bough(b, Vector3(0, ht * 0.95, 0), 0.22, 0.5, P["leaf"], P["cap"], ht, seed + 9.0, 8)

## One tier of a pine: a cone whose rim droops into scallops, closed underneath, snow on top.
static func _bough(b: MB, at: Vector3, rad: float, hgt: float, pal: Array, snow: Array, ht: float, seed: float, lobes: int) -> void:
	lobes = clampi(lobes / 2, 5, 8)
	var seg := lobes * 4
	var rings := 5
	var base := b.v.size()
	var top := at + Vector3(0, hgt, 0)
	for i in rings + 1:
		var t := float(i) / rings          # 0 at the tip, 1 at the rim
		for j in seg:
			var a := TAU * j / seg + seed
			var lobe := pow(0.5 + 0.5 * cos(a * lobes), 0.7)
			var rr := rad * t * (0.9 + 0.12 * lobe * t) * (1.0 + _n3(Vector3(cos(a), sin(a), seed) * 1.2) * 0.06)
			var droop := t * t * (0.14 + 0.16 * (1.0 - lobe)) * hgt
			var p := top + Vector3(cos(a) * rr, -hgt * t - droop, sin(a) * rr)
			var nn := Vector3(cos(a) * 0.7, 0.8 - t * 0.25, sin(a) * 0.7).normalized()
			var col: Color = (pal[0] as Color).lerp(pal[1], smoothstep(0.0, 0.7, t)).lerp(pal[2], smoothstep(0.75, 1.0, t) * 0.55)
			# the boughs in the gaps between lobes sit in shadow
			col = col.darkened((1.0 - lobe) * 0.18 * t)
			# snow lies over the upper part of each tier, in soft uneven patches
			var sn := smoothstep(0.0, 0.25, t) * (1.0 - smoothstep(0.55, 0.85, t + (1.0 - lobe) * 0.15))
			sn *= smoothstep(-0.25, 0.2, _n3(Vector3(cos(a) * 2.0, t * 1.5, sin(a) * 2.0 + seed)) + 0.3)
			col = col.lerp((snow[1] as Color).lerp(snow[0], 0.25 * t), sn)
			b.add(p, nn, col, 4.0 if sn > 0.5 else 0.0, clampf(p.y / ht, 0.0, 1.0), 0.4)
	for i in rings:
		for j in seg:
			var a := base + i * seg + j
			var bb := base + i * seg + (j + 1) % seg
			var c := base + (i + 1) * seg + (j + 1) % seg
			var d := base + (i + 1) * seg + j
			b.tri(a, c, bb); b.tri(a, d, c)
	# underside: from the rim back in to the trunk, dark
	var ub := b.v.size()
	for j in seg:
		var rim_i := base + rings * seg + j
		b.add(b.v[rim_i], Vector3(0, -1, 0), (pal[0] as Color).darkened(0.25), 0.0, b.uv2[rim_i].x, 0.4)
	var ci := b.add(at + Vector3(0, hgt * 0.15, 0), Vector3.DOWN, (pal[0] as Color).darkened(0.4), 0.0, clampf(at.y / ht, 0.0, 1.0), 0.0)
	for j in seg:
		b.tri(ub + j, ci, ub + (j + 1) % seg)

## An ash tree from the ember lands: a charred, forking trunk with glowing cracks, sparse clumps of
## ash-grey leaves and embers smouldering at the tips.
static func _ember_tree(b: MB, variant: int, r: RandomNumberGenerator) -> void:
	var P: Dictionary = PAL["ember"]
	var ht := r.randf_range(2.9, 3.4) + variant * 0.2
	var lean := Vector3(r.randf_range(-0.2, 0.2), 0, r.randf_range(-0.2, 0.2))
	var tt := Vector3(lean.x, ht * 0.55, lean.z)
	var pts := _limb(Vector3.ZERO, tt, tt.length(), Vector3(lean.x, 0, lean.z) * 0.4, 6)
	_tube(b, pts, _radii(0.22, 0.12, 6), 9, P["bark"][0], P["bark"][1], ht, 0.9, 1.0, false, 0.85, r.randf() * 9.0)
	var tips: Array = []
	var nb := 3 + variant % 2
	for k in nb:
		var a := TAU * k / nb + r.randf_range(-0.3, 0.3)
		var d := Vector3(cos(a), r.randf_range(0.7, 1.1), sin(a))
		var bp := _limb(pts[5], d, ht * r.randf_range(0.32, 0.42), Vector3(cos(a), -0.2, sin(a)) * 0.15, 4)
		_tube(b, bp, _radii(0.09, 0.03, 4), 6, P["bark"][0], P["bark"][1], ht, 0.0, 1.0, true, 0.6, k * 2.0)
		tips.append(bp[4])
	var blobs: Array = []
	for t in tips:
		blobs.append({"c": t + Vector3(0, 0.1, 0), "r": 0.42, "s": Vector3(0.48, 0.36, 0.48)})
	blobs.append({"c": pts[6] + Vector3(0, 0.45, 0), "r": 0.5, "s": Vector3(0.55, 0.42, 0.55)})
	var lo := 1e9; var hi := -1e9
	var mc := Vector3.ZERO
	for bl in blobs:
		mc += bl["c"]
		lo = minf(lo, (bl["c"] as Vector3).y - 0.4); hi = maxf(hi, (bl["c"] as Vector3).y + 0.4)
	mc /= blobs.size()
	for k in blobs.size():
		_blob(b, blobs[k]["c"], blobs[k]["s"], blobs, [mc, 1.2], P["leaf"], lo, hi, ht, 0.2, k * 4.1 + r.randf() * 9.0, 2)
	# embers: little glowing coals caught in the crown
	for k in 6 + variant:
		var bl: Dictionary = blobs[r.randi_range(0, blobs.size() - 1)]
		var dir := Vector3(r.randf_range(-1, 1), r.randf_range(0.0, 1.0), r.randf_range(-1, 1)).normalized()
		var p: Vector3 = (bl["c"] as Vector3) + dir * (bl["s"] as Vector3) * 0.95
		_blob(b, p, Vector3.ONE * r.randf_range(0.05, 0.08), [], [p, 0.1], [Color("ff5a1a"), Color("ff8a2a"), Color("ffc060"), Color("fff0a0")], p.y - 0.1, p.y + 0.1, ht, 0.1, k * 1.7, 0, 3.0, 0.9)

## A gloom tree: a twisted dark trunk that forks into clusters of glowing crystal instead of leaves.
static func _crystal_tree(b: MB, variant: int, r: RandomNumberGenerator) -> void:
	var P: Dictionary = PAL["gloom"]
	var ht := r.randf_range(3.0, 3.5) + variant * 0.2
	var pts: Array = []
	for k in 7:
		var t := k / 6.0
		pts.append(Vector3(sin(t * 4.0 + variant) * 0.14 * t, ht * 0.5 * t, cos(t * 3.0 + variant) * 0.12 * t))
	_tube(b, pts, _radii(0.21, 0.1, 6), 9, P["bark"][0], P["bark"][1], ht, 0.8, 1.0, false, 0.0, r.randf() * 5.0)
	var nb := 3 + variant % 2
	for k in nb:
		var a := TAU * k / nb + r.randf_range(-0.4, 0.4)
		var d := Vector3(cos(a) * 0.8, 1.0, sin(a) * 0.8)
		var bp := _limb(pts[5], d, ht * r.randf_range(0.28, 0.36), Vector3(sin(a), 0.1, -cos(a)) * 0.2, 4)
		_tube(b, bp, _radii(0.08, 0.035, 4), 6, P["bark"][0], P["bark"][1], ht, 0.0, 1.0, true)
		_crystal_spray(b, bp[4], d.normalized(), r, 0.9 + variant * 0.08, ht)
	_crystal_spray(b, pts[6], Vector3.UP, r, 1.1, ht)

## A spray of crystal shards fanning out from a point along dir.
static func _crystal_spray(b: MB, at: Vector3, dir: Vector3, r: RandomNumberGenerator, s: float, ht: float) -> void:
	var P: Dictionary = PAL["gloom"]
	for k in 5:
		var d := (dir + Vector3(r.randf_range(-0.6, 0.6), r.randf_range(-0.2, 0.4), r.randf_range(-0.6, 0.6))).normalized()
		var ln := r.randf_range(0.45, 0.8) * s * (1.25 if k == 0 else 1.0)
		_shard(b, at - d * 0.05, d if k > 0 else dir, ln, ln * r.randf_range(0.17, 0.24), P["leaf"], ht, r.randf() * TAU)

## One six-sided crystal: a prism with a pointed tip, lighter and glowing toward the tip.
static func _shard(b: MB, at: Vector3, dir: Vector3, ln: float, w: float, pal: Array, ht: float, rot := 0.0, glow := 0.55) -> void:
	var side := dir.cross(Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT).normalized()
	var fwd := dir.cross(side).normalized()
	var sides := 6
	var body := ln * 0.7
	for j in sides:
		var a0 := TAU * j / sides + rot; var a1 := TAU * (j + 1) / sides + rot
		var r0 := side * cos(a0) + fwd * sin(a0)
		var r1 := side * cos(a1) + fwd * sin(a1)
		var nrm := (r0 + r1).normalized()
		var p0 := at + r0 * w * 0.8; var p1 := at + r1 * w * 0.8
		var p2 := at + dir * body + r1 * w; var p3 := at + dir * body + r0 * w
		var tip := at + dir * ln
		var lit := 0.5 + 0.5 * nrm.dot(SUN.normalized())
		var cb: Color = (pal[0] as Color).lerp(pal[1], 0.4 + lit * 0.4); cb.a = 1.0 - glow * 0.4
		var ct: Color = (pal[2] as Color).lerp(pal[3], lit * 0.5); ct.a = 1.0 - glow
		var cp: Color = (pal[3] as Color); cp.a = 1.0 - glow
		var by := clampf(at.y / ht, 0.0, 1.0)
		var i0 := b.add(p0, nrm, cb, 3.0, by, 0.0); var i1 := b.add(p1, nrm, cb, 3.0, by, 0.0)
		var i2 := b.add(p2, nrm, ct, 3.0, by, 0.0); var i3 := b.add(p3, nrm, ct, 3.0, by, 0.0)
		b.tri(i0, i2, i1); b.tri(i0, i3, i2)
		var tn := (nrm + dir * 0.8).normalized()
		var j2 := b.add(p2, tn, ct, 3.0, by, 0.0); var j3 := b.add(p3, tn, ct, 3.0, by, 0.0)
		var jt := b.add(tip, tn, cp, 3.0, by, 0.0)
		b.tri(j3, jt, j2)

# ------------------------------------------------------------------ rocks
## A smooth rounded boulder: a squashed, noise-sculpted sphere, flat underneath, with strata in its
## colour, a paler crown, and a cap (moss, snow, ash or lichen) where it faces the sky.
static func _rock(b: MB, style: String, r: RandomNumberGenerator, rad: Vector3, bumps: float, capped: bool, level := 3, off := Vector3.ZERO) -> void:
	var P: Dictionary = PAL[style]
	var I := ico(level)
	var uvs: PackedVector3Array = I[0]
	var ids: PackedInt32Array = I[1]
	var seed := r.randf() * 40.0
	var pos := PackedVector3Array(); pos.resize(uvs.size())
	var floor_y := -rad.y * 0.35
	var top_y := rad.y * r.randf_range(0.55, 0.8)
	for k in uvs.size():
		var u: Vector3 = uvs[k]
		var d := 1.0 + _n3(u * 1.1 + Vector3(seed, 0, 0)) * bumps * 0.45 + _n3(u * 2.6 + Vector3(0, seed, 0)) * bumps * 0.16
		var p := Vector3(u.x * rad.x, u.y * rad.y, u.z * rad.z) * d
		# a flatter top and a flat, sunk foot
		if p.y > top_y: p.y = top_y + (p.y - top_y) * 0.35
		if p.y < floor_y: p.y = floor_y + (p.y - floor_y) * 0.12
		pos[k] = p
	# smooth normals from the faces
	var nrm := PackedVector3Array(); nrm.resize(uvs.size())
	for k in range(0, ids.size(), 3):
		var a := pos[ids[k]]; var bb := pos[ids[k + 2]]; var c := pos[ids[k + 1]]
		var fn := (bb - a).cross(c - a)
		nrm[ids[k]] += fn; nrm[ids[k + 1]] += fn; nrm[ids[k + 2]] += fn
	var base := b.v.size()
	var lo := floor_y; var hi := top_y + rad.y * 0.15
	for k in uvs.size():
		var p := pos[k]
		var nn := nrm[k].normalized()
		if nn.length() < 0.5: nn = uvs[k]
		var hf := clampf((p.y - lo) / maxf(0.01, hi - lo), 0.0, 1.0)
		var stone: Array = P["stone"]
		var col: Color = (stone[0] as Color).lerp(stone[1], smoothstep(0.0, 0.55, hf))
		col = col.lerp(stone[2], smoothstep(0.3, 0.95, nn.y) * smoothstep(0.35, 0.9, hf) * 0.75)
		# strata: alternating pale and dark layers
		var band := fposmod(p.y * 4.2 + _n3(Vector3(p.x, 0, p.z) * 1.4 + Vector3(seed, 0, 0)) * 0.7, 1.0)
		col = col.darkened(0.12 * (1.0 - smoothstep(0.0, 0.25, band)))
		col = col.lightened(0.06 * smoothstep(0.55, 0.75, band) * (1.0 - smoothstep(0.75, 0.95, band)))
		# the foot sits in its own shadow
		col = col.darkened((1.0 - smoothstep(0.0, 0.3, hf)) * 0.32)
		var mid := 2.0
		if capped:
			var capk := smoothstep(0.5, 0.8, nn.y + _n3(p * 2.2 + Vector3(seed, seed, 0)) * 0.35) * smoothstep(0.45, 0.75, hf)
			if capk > 0.0:
				var cap: Array = P["cap"]
				col = col.lerp((cap[0] as Color).lerp(cap[1], smoothstep(0.6, 1.0, nn.y)), capk)
				if capk > 0.5 and style == "frost": mid = 4.0
		b.add(p - Vector3(0, floor_y + 0.06, 0) + off, nn, col, mid, 0.0, 0.0)
	for k in range(0, ids.size(), 3):
		b.tri(base + ids[k], base + ids[k + 1], base + ids[k + 2])
	if style == "gloom" and capped:
		# shards of crystal growing out of the gloom's stones
		for k in 2:
			var a := r.randf() * TAU
			var at := Vector3(cos(a) * rad.x * 0.5, top_y * 0.6 - floor_y, sin(a) * rad.z * 0.5)
			_shard(b, at + off, (Vector3(cos(a), 1.6, sin(a))).normalized(), r.randf_range(0.35, 0.55), 0.09, PAL["gloom"]["leaf"], 1.0, r.randf() * TAU)
	if style == "ember" and capped:
		# a glowing seam
		for k in 3:
			var a := r.randf() * TAU
			var p := Vector3(cos(a) * rad.x * 0.85, r.randf_range(0.1, 0.5) * rad.y - floor_y, sin(a) * rad.z * 0.85)
			p += off
			_blob(b, p, Vector3(0.09, 0.05, 0.09), [], [p, 0.1], [Color("ff5a1a"), Color("ff8a2a"), Color("ffb050"), Color("ffe08a")], p.y - 0.1, p.y + 0.1, 1.0, 0.2, k * 2.0, 1, 3.0, 0.85)

# ------------------------------------------------------------------ undergrowth
## A low bush: a handful of leaf clumps in a dome (bloom ones dotted with flowers, frost ones
## dusted with snow, ember ones dry and rust-red, gloom ones with a glowing bud).
static func _bush(b: MB, style: String, variant: int, r: RandomNumberGenerator) -> void:
	var P: Dictionary = PAL[style]
	var pal: Array = P["bush"]
	var pal4 := [pal[0], pal[1], pal[2], (pal[2] as Color).lightened(0.25)]
	if style == "frost":
		pal4 = [pal[0], pal[1], Color("d8e6f2"), Color("ffffff")]     # dusted with snow
	var blobs: Array = []
	var n := 4 + variant
	var w := 0.5 + variant * 0.06
	blobs.append({"c": Vector3(0, 0.26, 0), "r": 0.36, "s": Vector3(0.4, 0.32, 0.4)})
	for k in n:
		var a := TAU * k / n + r.randf_range(-0.4, 0.4)
		var rr := r.randf_range(0.2, 0.28)
		blobs.append({"c": Vector3(cos(a) * w * 0.55, r.randf_range(0.14, 0.32), sin(a) * w * 0.55), "r": rr, "s": Vector3(rr, rr * 0.82, rr)})
	var mass := [Vector3(0, 0.12, 0), 0.6]
	for k in blobs.size():
		_blob(b, blobs[k]["c"], blobs[k]["s"], blobs, mass, pal4, 0.0, 0.62, 0.6, 0.18, k * 3.3 + variant * 11.0, 1 if k > 0 else 2)
	if style in ["bloom", "meadow"]:
		var fc := Color("ffe4f0") if style == "bloom" else Color("fff2b0")
		for k in 5 + variant:
			var bl: Dictionary = blobs[r.randi_range(0, blobs.size() - 1)]
			var dir := Vector3(r.randf_range(-1, 1), r.randf_range(0.4, 1.0), r.randf_range(-1, 1)).normalized()
			var p: Vector3 = (bl["c"] as Vector3) + dir * (bl["s"] as Vector3)
			_blob(b, p, Vector3(0.055, 0.04, 0.055), [], [p, 0.08], [fc.darkened(0.2), fc, Color.WHITE, Color.WHITE], p.y - 0.05, p.y + 0.05, 0.6, 0.0, k * 1.1, 0, 5.0, 0.12)
	if style == "gloom":
		_shard(b, Vector3(0, 0.35, 0), Vector3.UP, 0.42, 0.07, PAL["gloom"]["leaf"], 0.6, 0.3)

## A fern: arching fronds round a crown, each a tapering leaf strip with notched sides.
static func _fern(b: MB, style: String, r: RandomNumberGenerator) -> void:
	var pal: Array = PAL[style]["bush"]
	var fronds := 7
	for k in fronds:
		var a := TAU * k / fronds + r.randf_range(-0.2, 0.2)
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-sin(a), 0, cos(a))
		var ln := r.randf_range(0.45, 0.6)
		var segs := 5
		var base := b.v.size()
		for i in segs + 1:
			var t := float(i) / segs
			var p := dir * ln * t + Vector3(0, sin(t * 2.6) * 0.32 * ln + 0.02, 0)
			var wd := 0.09 * sin(t * PI) * (0.8 + 0.2 * (i % 2))
			var col: Color = (pal[0] as Color).lerp(pal[2], t * 0.85)
			var nn := Vector3(0, 1, 0).lerp(dir, 0.25).normalized()
			b.add(p - side * wd, nn, col, 0.0, t * 0.6, t)
			b.add(p + side * wd, nn, col, 0.0, t * 0.6, t)
		for i in segs:
			var q := base + i * 2
			b.tri(q, q + 2, q + 1); b.tri(q + 1, q + 2, q + 3)
			b.tri(q, q + 1, q + 2); b.tri(q + 1, q + 3, q + 2)

## A patch of flowers: a few stems with five-petal cups (white petals, tinted per instance), and a
## couple of leaves at the foot.
static func _flowers(b: MB, style: String, r: RandomNumberGenerator) -> void:
	var pal: Array = PAL[style]["bush"]
	for k in 4:
		var a := r.randf() * TAU
		var at := Vector3(cos(a), 0, sin(a)) * r.randf_range(0.0, 0.16)
		var hgt := r.randf_range(0.16, 0.3)
		_tube(b, [at, at + Vector3(0.02, hgt * 0.5, 0), at + Vector3(0.0, hgt, 0.02)], [0.012, 0.01, 0.008], 4, pal[0], pal[1], 0.4, 0.0, 0.0)
		var top := at + Vector3(0.0, hgt, 0.02)
		var ci := b.add(top + Vector3(0, 0.015, 0), Vector3.UP, Color("ffd84a"), 5.0, hgt / 0.4, 0.5)
		var petals := 5
		var ring0 := b.v.size()
		for j in petals * 2:
			var pa := TAU * j / (petals * 2) + a
			var rr := 0.075 if j % 2 == 0 else 0.035
			var p := top + Vector3(cos(pa) * rr, 0.025 if j % 2 == 0 else 0.005, sin(pa) * rr)
			var col := Color("ffffff") if j % 2 == 0 else Color("f0e0e8")
			b.add(p, (Vector3(cos(pa) * 0.4, 1.0, sin(pa) * 0.4)).normalized(), col, 5.0, hgt / 0.4, 0.6)
		for j in petals * 2:
			b.tri(ci, ring0 + j, ring0 + (j + 1) % (petals * 2))
			b.tri(ci, ring0 + (j + 1) % (petals * 2), ring0 + j)

## A cluster of toadstools: fat stems and domed caps, spotted in the meadow, glowing in the gloom.
static func _mushrooms(b: MB, style: String, r: RandomNumberGenerator) -> void:
	var cap_c: Color = {"meadow": Color("d8483a"), "bloom": Color("ff8ac0"), "frost": Color("8ac0e0"), "ember": Color("e07a3a"), "storm": Color("8a8ad8"), "gloom": Color("7af0e0")}[style]
	var glowing := style in ["gloom", "storm", "frost"]
	for k in 3:
		var a := TAU * k / 3.0 + r.randf()
		var at := Vector3(cos(a), 0, sin(a)) * (0.0 if k == 0 else r.randf_range(0.12, 0.2))
		var s := (1.0 if k == 0 else r.randf_range(0.5, 0.7)) * r.randf_range(0.9, 1.1)
		var hgt := 0.22 * s
		_tube(b, [at, at + Vector3(0, hgt * 0.5, 0), at + Vector3(0.01, hgt, 0)], [0.05 * s, 0.04 * s, 0.035 * s], 7, Color("c8bca8"), Color("f4ecdc"), 0.4, 0.0, 6.0)
		var cr := 0.12 * s
		var cc := at + Vector3(0.01, hgt, 0)
		var dark: Color = cap_c.darkened(0.45); dark.a = 1.0 - (0.4 if glowing else 0.0)
		var mid: Color = cap_c; mid.a = dark.a
		var lt: Color = cap_c.lightened(0.3); lt.a = dark.a
		_blob(b, cc, Vector3(cr, cr * 0.62, cr), [], [cc - Vector3(0, cr * 0.4, 0), cr * 1.2], [dark, mid, lt, Color("fff4e8")], cc.y - cr * 0.5, cc.y + cr * 0.6, 0.4, 0.05, k * 2.3, 1, 0.0, 0.4 if glowing else 0.0)
		if style == "meadow":
			for q in 4:
				var qa := r.randf() * TAU
				var p := cc + Vector3(cos(qa) * cr * 0.6, cr * 0.48, sin(qa) * cr * 0.6)
				_blob(b, p, Vector3(0.022, 0.012, 0.022) * s * 1.6, [], [p, 0.05], [Color("fff4e8"), Color("ffffff"), Color("ffffff"), Color("ffffff")], p.y - 0.02, p.y + 0.02, 0.4, 0.0, q, 0)

## Reeds and cattails: tall thin blades with a brown head on a few.
static func _reeds(b: MB, style: String, r: RandomNumberGenerator) -> void:
	var pal: Array = PAL[style]["bush"]
	for k in 9:
		var a := r.randf() * TAU
		var at := Vector3(cos(a), 0, sin(a)) * r.randf_range(0.0, 0.2)
		var hgt := r.randf_range(0.5, 0.85)
		var face := r.randf() * TAU
		var side := Vector3(cos(face), 0, sin(face))
		var bend := Vector3(-sin(face), 0, cos(face)) * hgt * r.randf_range(0.1, 0.3)
		var base := b.v.size()
		for i in 4:
			var t := i / 3.0
			var wd := 0.03 * (1.0 - t * 0.9)
			var p := at + Vector3(0, hgt * t, 0) + bend * t * t
			var col: Color = (pal[0] as Color).lerp(pal[2], t)
			b.add(p - side * wd, Vector3.UP, col, 0.0, t, t)
			b.add(p + side * wd, Vector3.UP, col, 0.0, t, t)
		for i in 3:
			var q := base + i * 2
			b.tri(q, q + 2, q + 1); b.tri(q + 1, q + 2, q + 3)
			b.tri(q, q + 1, q + 2); b.tri(q + 1, q + 3, q + 2)
		if k % 3 == 0:
			var top := at + Vector3(0, hgt * 0.92, 0) + bend * 0.85
			_tube(b, [top, top + Vector3(0, 0.12, 0)], [0.028, 0.026], 5, Color("5a3a26"), Color("8a5a36"), 1.0, 0.0, 1.0, true)

## A cluster of crystals standing out of the ground (gloom, or any style's rare outcrop).
static func _crystal_cluster(b: MB, style: String, r: RandomNumberGenerator, s: float) -> void:
	var pal: Array = PAL["gloom"]["leaf"] if style in ["gloom", "meadow", "bloom"] else [Color("1f4a6a"), Color("3a8ac8"), Color("8ad8ff"), Color("eaffff")]
	if style == "ember": pal = [Color("6a1a10"), Color("d8481a"), Color("ff9a3a"), Color("fff0a0")]
	for k in 5:
		var a := TAU * k / 5.0 + r.randf()
		var d := Vector3(cos(a) * 0.45, 1.0, sin(a) * 0.45).normalized() if k > 0 else Vector3.UP
		var ln := r.randf_range(0.5, 0.85) * s * (1.5 if k == 0 else 1.0)
		_shard(b, Vector3(cos(a), 0, sin(a)) * (0.0 if k == 0 else 0.12) - Vector3(0, 0.05, 0), d, ln, ln * 0.22, pal, 1.0, r.randf() * TAU)

# ------------------------------------------------------------------ ruins
## A standing stone of an old ruin: a fluted column on a square plinth, its top broken off at a
## slant (variant 0 keeps its capital), weathered, with moss or snow on the break and rubble at
## its foot.
static func _pillar(b: MB, style: String, variant: int, r: RandomNumberGenerator) -> void:
	var st: Array = PAL[style]["stone"]
	var pale := [(st[1] as Color).lerp(Color("e8e0d0"), 0.45), (st[2] as Color).lerp(Color("fff6e8"), 0.45)]
	var ht := 2.3
	# the plinth
	_box(b, Vector3(0, 0.15, 0), Vector3(0.62, 0.15, 0.62), (st[0] as Color).lerp(pale[0], 0.5), pale[0], ht)
	var top := ht * (1.0 if variant == 0 else r.randf_range(0.55, 0.85))
	var seg := 16
	var rings := 8
	var base := b.v.size()
	var tilt := Vector2(r.randf_range(-1, 1), r.randf_range(-1, 1)).normalized() * (0.0 if variant == 0 else 0.22)
	for i in rings + 1:
		var t := float(i) / rings
		for j in seg + 1:
			var a := TAU * j / seg
			var flute := 1.0 - 0.07 * pow(absf(sin(a * 4.0)), 0.6)
			var rr := lerpf(0.42, 0.36, t) * flute
			var y := 0.3 + (top - 0.3) * t
			if i == rings:
				y += cos(a) * tilt.x * 0.4 + sin(a) * tilt.y * 0.4
			var q := Vector3(cos(a) * rr, y, sin(a) * rr)
			var col: Color = pale[0].lerp(pale[1], smoothstep(0.1, 0.9, t)).darkened(0.12 * (1.0 - flute) * 10.0 * 0.3)
			col = col.darkened((1.0 - smoothstep(0.0, 0.25, t)) * 0.25)
			var chip := _n3(Vector3(cos(a) * 3.0, y * 2.0, sin(a) * 3.0 + variant))
			if chip > 0.45: col = col.darkened(0.18)
			b.add(q, Vector3(cos(a), 0, sin(a)), col, 2.0, 0.0, 0.0)
	for i in rings:
		for j in seg:
			var a := base + i * (seg + 1) + j
			b.tri(a, a + 1, a + seg + 2); b.tri(a, a + seg + 2, a + seg + 1)
	if variant == 0:
		_box(b, Vector3(0, top + 0.1, 0), Vector3(0.55, 0.1, 0.55), pale[0], pale[1], ht)
		_box(b, Vector3(0, top + 0.26, 0), Vector3(0.48, 0.07, 0.48), pale[0], pale[1], ht)
	else:
		# the broken top, mossed or snowed over
		var capc: Array = PAL[style]["cap"]
		var cc := Vector3(0, top + 0.02, 0)
		_blob(b, cc, Vector3(0.36, 0.1, 0.36), [], [cc, 0.4], [capc[0], capc[0], capc[1], (capc[1] as Color).lightened(0.2)], top - 0.1, top + 0.1, ht, 0.25, variant * 3.0, 2, 4.0 if style == "frost" else 6.0)
		# a fallen piece at its foot
		var a := r.randf() * TAU
		_rock(b, style, r, Vector3(0.26, 0.2, 0.22), 0.4, false, 1, Vector3(cos(a) * 0.75, 0, sin(a) * 0.75))
	for k in 2:
		var a := r.randf() * TAU
		_rock(b, style, r, Vector3(0.14, 0.1, 0.12), 0.5, false, 1, Vector3(cos(a) * 0.7, 0, sin(a) * 0.7))

## An axis-aligned bevel-free box, lighter on top (plinths, capitals).
static func _box(b: MB, c: Vector3, e: Vector3, c0: Color, c1: Color, ht: float) -> void:
	var faces := [[Vector3.UP, Vector3.RIGHT, Vector3.BACK], [Vector3.DOWN, Vector3.RIGHT, Vector3.FORWARD], [Vector3.RIGHT, Vector3.UP, Vector3.FORWARD],
		[Vector3.LEFT, Vector3.UP, Vector3.BACK], [Vector3.BACK, Vector3.UP, Vector3.RIGHT], [Vector3.FORWARD, Vector3.UP, Vector3.LEFT]]
	for f in faces:
		var n: Vector3 = f[0]; var u: Vector3 = f[1]; var v: Vector3 = f[2]
		var col: Color = c1 if n.y > 0.5 else (c0.darkened(0.3) if n.y < -0.5 else c0)
		var o := c + n * e
		var ue := u * e; var ve := v * e
		var i0 := b.add(o - ue - ve, n, col, 2.0, 0.0, 0.0)
		var i1 := b.add(o + ue - ve, n, col, 2.0, 0.0, 0.0)
		var i2 := b.add(o + ue + ve, n, col, 2.0, 0.0, 0.0)
		var i3 := b.add(o - ue + ve, n, col, 2.0, 0.0, 0.0)
		if (u.cross(v)).dot(n) > 0.0:
			b.tri(i0, i2, i1); b.tri(i0, i3, i2)
		else:
			b.tri(i0, i1, i2); b.tri(i0, i2, i3)

# ------------------------------------------------------------------ set pieces
## Gives a set piece built from primitives (docks, hatches, outposts, shrines, the train, lairs) the
## painted value structure of the characters: each part lighter at its top and darker at its foot,
## dark where it tucks into the next part, and form shadow on its turned-away edges.
static func paint_set_piece(n: Node3D, grad := 0.24, crease := 0.3, edge := 0.2) -> void:
	if not on():
		return
	Models.bake_part_y(n)
	for m in Models.collect_mats(n):
		var sm := m as ShaderMaterial
		var gl = sm.get_shader_parameter("glow")
		if gl != null and float(gl) > 0.3:
			continue
		Models.painted(sm, 0, grad, crease, edge)
		sm.set_shader_parameter("rim_amount", 0.42)
		sm.set_shader_parameter("paint", 0.07)
