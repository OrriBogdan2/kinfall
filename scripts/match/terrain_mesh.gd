extends RefCounted
## Draws a World's tile grid as clean, deliberate terrain. Only the look changes: walking, heights,
## ramps and which rims you can grab all still follow the tiles exactly.
##
## Every terrace edge is traced as a contour between tile centres (marching squares), so straight
## runs stay straight, one-tile staircases become clean diagonals and corners are rounded off instead
## of reading as stacked cubes. Each contour is extruded into a cliff with a profile that tells you
## what it is: a soft grassy bevel on terrace steps, a pale stone ledge that sticks out on rims you can
## grab, and a smooth dark slate face on the sheer ones. Under each island hangs a tapered, faceted
## rock cone instead of a slab, and stairs are drawn as carved stone flights with side walls.

const LEVEL := 0.8
const RIM := 1.5           # how far an island's outer cliff drops before the rock underneath tapers in
const ROWS := 6            # rows in every cliff profile (shared points must line up between cells)

# style codes, passed to the terrain shader in UV.x (0 = legacy meshes that pick by normal)
const S_TOP := 1.0
const S_ROCK := 2.0
const S_SHEER := 3.0
const S_UNDER := 4.0
const S_CAP := 5.0
const S_STONE := 6.0

enum { E_TERRACE, E_LIP, E_SHEER, E_COAST }

const PAD := 4
var W: Node
var w := 0
var h := 0
var pw := 0
var vals := PackedInt32Array()     # padded grid of levels, -1 for the void (and plank bridges)
var tops := PackedColorArray()     # per tile: the ground colour at its centre
var under := PackedFloat32Array()  # per tile: the height of the island's underside below it
var rn := FastNoiseLite.new()
var _s := {}
var _x := {}

var V := PackedVector3Array()
var N := PackedVector3Array()
var C := PackedColorArray()
var UV := PackedVector2Array()

func _init(world: Node) -> void:
	W = world
	w = W.w; h = W.h
	pw = w + PAD * 2
	rn.seed = int(W.rng.seed) + 77
	rn.frequency = 0.9

func v(x: int, z: int) -> int:
	return vals[(z + PAD) * pw + x + PAD]

## Builds the whole terrain mesh.
func build() -> ArrayMesh:
	_fill_grid()
	_fill_colors()
	_fill_under()
	for cz in range(-1, h):
		for cx in range(-1, w):
			_cell(cx, cz)
	for si in W.stairs:
		var i: int = si
		if W.kind[i] != W.T_VOID:
			_stairs(i % w, i / w, W.stairs[i], W.level[i] * LEVEL)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V
	arr[Mesh.ARRAY_NORMAL] = N
	arr[Mesh.ARRAY_COLOR] = C
	arr[Mesh.ARRAY_TEX_UV] = UV
	var m := ArrayMesh.new()
	if V.size() > 0:
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

## A small texture of tile heights (R) and blockers (G), for the shader's soft contact shadows.
func height_texture() -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RG8)
	for z in h:
		for x in w:
			var lv := v(x, z)
			var blk := 1.0 if lv >= 0 and W.kind[W.idx(x, z)] == W.T_BLOCK else 0.0
			img.set_pixel(x, z, Color(float(lv + 1) / 32.0, blk, 0))
	return ImageTexture.create_from_image(img)

# ------------------------------------------------------------------ grid data
func _fill_grid() -> void:
	vals.resize(pw * (h + PAD * 2)); vals.fill(-1)
	for z in h:
		for x in w:
			var i: int = z * w + x
			if W.kind[i] != W.T_VOID and not W.bridge.has(i):
				vals[(z + PAD) * pw + x + PAD] = int(W.level[i])

func _fill_colors() -> void:
	tops.resize(w * h)
	var tn := FastNoiseLite.new(); tn.seed = int(W.rng.seed) + 3; tn.frequency = 0.3
	var lip_paint := Color("dccb9c"); var sheer_paint := Color("7d7896")
	for z in h:
		for x in w:
			var i: int = z * w + x
			if v(x, z) < 0:
				continue
			var bio: Dictionary = W._bio(i)
			var cx := x + 0.5; var cz := z + 0.5
			var nv := tn.get_noise_2d(cx * 0.6, cz * 0.6) * 0.5 + 0.5
			var nv2 := tn.get_noise_2d(cx * 2.1 + 40.0, cz * 2.1) * 0.5 + 0.5
			var col: Color = Color(bio["top"]).lerp(bio["top2"], nv).lerp(Color(bio["top"]).lightened(0.08), nv2 * 0.35)
			col = col.lightened(0.03 * W.level[i])
			# paths and soil: blend the paint of this tile and its neighbours, so paths have soft edges.
			# (The rim paints that used to mark grabbable and sheer rims are drawn by the cliff now.)
			var pc := Color(0, 0, 0, 0); var wsum := 0.0
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var tx := x + dx; var tz := z + dz
					if tx < 0 or tz < 0 or tx >= w or tz >= h:
						continue
					var j: int = tz * w + tx
					if not W.paint.has(j):
						continue
					var p: Color = W.paint[j]
					if p == lip_paint or p == sheer_paint:
						continue
					var wt := 1.0 if dx == 0 and dz == 0 else (0.35 if dx == 0 or dz == 0 else 0.2)
					pc += p * wt; wsum += wt
			if wsum > 0.0:
				col = col.lerp(pc / wsum, clampf(wsum / 1.2, 0.0, 1.0) * (0.85 + nv2 * 0.15))
			tops[i] = col

## The underside of each island: a cone of rock that tapers in from the rim, deepest under the
## middle, as in a floating island.
func _fill_under() -> void:
	under.resize(w * h); under.fill(0.0)
	var d := PackedFloat32Array(); d.resize(w * h)
	var big := 1.0e6
	for i in w * h:
		d[i] = big if v(i % w, i / w) >= 0 else 0.0
	var dg := 1.4142
	# two-pass chamfer distance to the nearest void tile
	for z in h:
		for x in w:
			var i: int = z * w + x
			if d[i] == 0.0: continue
			var best: float = d[i]
			best = minf(best, (d[i - 1] if x > 0 else 0.0) + 1.0)
			best = minf(best, (d[i - w] if z > 0 else 0.0) + 1.0)
			best = minf(best, (d[i - w - 1] if x > 0 and z > 0 else 0.0) + dg)
			best = minf(best, (d[i - w + 1] if x < w - 1 and z > 0 else 0.0) + dg)
			d[i] = best
	for z in range(h - 1, -1, -1):
		for x in range(w - 1, -1, -1):
			var i: int = z * w + x
			if d[i] == 0.0: continue
			var best: float = d[i]
			best = minf(best, (d[i + 1] if x < w - 1 else 0.0) + 1.0)
			best = minf(best, (d[i + w] if z < h - 1 else 0.0) + 1.0)
			best = minf(best, (d[i + w + 1] if x < w - 1 and z < h - 1 else 0.0) + dg)
			best = minf(best, (d[i + w - 1] if x > 0 and z < h - 1 else 0.0) + dg)
			d[i] = best
	# soften it, so diagonal coasts and thin necks don't alternate deep and shallow tile by tile
	for _pass in 2:
		var sm := d.duplicate()
		for z in range(1, h - 1):
			for x in range(1, w - 1):
				var i: int = z * w + x
				if d[i] <= 0.0: continue
				var sum := 0.0
				for o in [i - 1, i + 1, i - w, i + w, i - w - 1, i - w + 1, i + w - 1, i + w + 1]:
					sum += d[o]
				sm[i] = maxf(0.5, (d[i] * 2.0 + sum) / 10.0)
		d = sm
	var reach := {}
	for i in w * h:
		if d[i] > 0.0:
			var ii: int = W.island[i]
			reach[ii] = maxf(float(reach.get(ii, 1.0)), d[i] - 0.5)
	for i in w * h:
		if d[i] <= 0.0:
			continue
		var x := i % w; var z := i / w
		var R: float = maxf(1.5, float(reach.get(W.island[i], 1.5)))
		var dc := d[i] - 0.5
		var deep := clampf(3.5 + R * 0.95, 4.0, 30.0)
		var t := clampf(dc / R, 0.0, 1.0)
		var taper := deep * pow(t, 0.62)
		taper *= 1.0 + rn.get_noise_2d(x * 0.31 + 50.0, z * 0.31) * 0.28
		under[i] = v(x, z) * LEVEL - _rim(Vector2(x + 0.5, z + 0.5)) - taper

func _rim(p: Vector2) -> float:
	return RIM + rn.get_noise_2d(p.x * 0.45, p.y * 0.45) * 0.35

# ------------------------------------------------------------------ contours
## Smoothed "how inside" a tile is for threshold t: a 5x5 binomial blur of (level >= t), 0..1.
const BW := [1.0, 4.0, 6.0, 4.0, 1.0]
func _sv(x: int, z: int, t: int) -> float:
	var key := ((z + PAD) * pw + x + PAD) * 64 + t
	if _s.has(key):
		return _s[key]
	var n := 0.0
	for dz in 5:
		var row := 0.0
		for dx in 5:
			if v(x + dx - 2, z + dz - 2) >= t: row += BW[dx]
		n += row * BW[dz]
	n /= 256.0
	_s[key] = n
	return n

## Where the contour for threshold t crosses the edge between tile centres a (inside) and b (outside):
## {p: Vector2, n: outward Vector2, void: bool, style, rim: float, a: tile index}.
func _cross(ax: int, az: int, bx: int, bz: int, t: int) -> Dictionary:
	var vb := v(bx, bz)
	var te := 0 if vb < 0 else t     # a coastline is one line, whichever terrace meets it
	var ex := mini(ax, bx); var ez := mini(az, bz)
	var key := (((ez + PAD) * pw + ex + PAD) * 2 + (0 if az == bz else 1)) * 64 + te
	if _x.has(key):
		return _x[key]
	# where the blurred field crosses one half: straight runs stay put, shallow staircases line up
	# into straight slopes and corners round off (clamped, so the drawn edge never strays far)
	var sa := _sv(ax, az, te); var sb := _sv(bx, bz, te)
	var f := 0.5
	if sa > 0.5 and sb < 0.5:
		f = clampf((sa - 0.5) / (sa - sb), 0.15, 0.85)
	elif sa <= 0.5:
		f = 0.3
	else:
		f = 0.7
	var A := Vector2(ax + 0.5, az + 0.5); var B := Vector2(bx + 0.5, bz + 0.5)
	var p := A + (B - A) * f
	var g := Vector2(_sv(ax + 1, az, te) - _sv(ax - 1, az, te) + _sv(bx + 1, bz, te) - _sv(bx - 1, bz, te),
		_sv(ax, az + 1, te) - _sv(ax, az - 1, te) + _sv(bx, bz + 1, te) - _sv(bx, bz - 1, te))
	var n := -g
	var ab := (B - A)
	if n.length() < 0.01 or n.normalized().dot(ab) < 0.15:
		n = ab
	n = n.normalized()
	var ia := -1
	if ax >= 0 and az >= 0 and ax < w and az < h: ia = az * w + ax
	var style := E_TERRACE
	var rim := 0.0
	if vb < 0:
		style = E_COAST
		if ia >= 0 and W.sheer.has(ia): style = E_SHEER
		elif ia >= 0 and W.lip.has(ia): style = E_LIP
		rim = v(ax, az) * LEVEL - _rim(p)
	var out := {"p": p, "n": n, "void": vb < 0, "style": style, "rim": rim, "a": ia, "ground": maxi(vb, 0) * LEVEL}
	_x[key] = out
	return out

const CX := [0, 1, 1, 0]
const CZ := [0, 0, 1, 1]

func _cell(cx: int, cz: int) -> void:
	var vs := [v(cx, cz), v(cx + 1, cz), v(cx + 1, cz + 1), v(cx, cz + 1)]
	if vs[0] == vs[1] and vs[1] == vs[2] and vs[2] == vs[3]:
		if vs[0] < 0:
			return
		var ps: Array = []; var cols: Array = []; var us: Array = []
		for k in 4:
			var tx: int = cx + CX[k]; var tz: int = cz + CZ[k]
			ps.append(Vector2(tx + 0.5, tz + 0.5))
			cols.append(tops[tz * w + tx])
			us.append(under[tz * w + tx])
		var y: float = vs[0] * LEVEL
		_tri3(Vector3(ps[0].x, y, ps[0].y), Vector3(ps[1].x, y, ps[1].y), Vector3(ps[2].x, y, ps[2].y), Vector3.UP, cols[0], cols[1], cols[2], S_TOP, true)
		_tri3(Vector3(ps[0].x, y, ps[0].y), Vector3(ps[2].x, y, ps[2].y), Vector3(ps[3].x, y, ps[3].y), Vector3.UP, cols[0], cols[2], cols[3], S_TOP, true)
		var bio: Dictionary = W._bio(cz * w + cx if cx >= 0 and cz >= 0 else 0)
		_under_tri([Vector3(ps[0].x, us[0], ps[0].y), Vector3(ps[1].x, us[1], ps[1].y), Vector3(ps[2].x, us[2], ps[2].y)], [vs[0], vs[1], vs[2]], bio)
		_under_tri([Vector3(ps[0].x, us[0], ps[0].y), Vector3(ps[2].x, us[2], ps[2].y), Vector3(ps[3].x, us[3], ps[3].y)], [vs[0], vs[2], vs[3]], bio)
		return
	var vmin: int = mini(mini(vs[0], vs[1]), mini(vs[2], vs[3]))
	var smin := 1 << 20
	var distinct: Array = []
	for k in 4:
		if vs[k] >= 0:
			smin = mini(smin, vs[k])
			if not distinct.has(vs[k]): distinct.append(vs[k])
	if distinct.is_empty():
		return
	distinct.sort()
	var bio: Dictionary = {}
	for k in 4:
		if vs[k] >= 0:
			bio = W._bio((cz + CZ[k]) * w + cx + CX[k]) if cx + CX[k] >= 0 and cz + CZ[k] >= 0 and cx + CX[k] < w and cz + CZ[k] < h else W.biome
			break
	for t in distinct:
		var poly := _walk(cx, cz, vs, t)
		# ground at this terrace's height (hidden wherever a higher terrace covers it)
		var y: float = t * LEVEL
		var pts: Array = poly[0]; var cols: Array = poly[1]
		for k in range(1, pts.size() - 1):
			_tri3(Vector3(pts[0].x, y, pts[0].y), Vector3(pts[k].x, y, pts[k].y), Vector3(pts[k + 1].x, y, pts[k + 1].y), Vector3.UP, cols[0], cols[k], cols[k + 1], S_TOP, true)
		if t > vmin:
			for seg in poly[2]:
				_wall(seg[0], seg[1], y, smin * LEVEL)
	# the island's underside
	if vmin < 0:
		var up := _walk(cx, cz, vs, 0)
		var pts: Array = up[0]; var info: Array = up[3]
		var p3: Array = []; var lv: Array = []
		for k in pts.size():
			var inf = info[k]
			if inf is Dictionary:
				p3.append(Vector3(pts[k].x, inf["rim"], pts[k].y)); lv.append(-1)
			else:
				var ti: int = inf
				p3.append(Vector3(pts[k].x, under[ti], pts[k].y)); lv.append(vals[(ti / w + PAD) * pw + ti % w + PAD])
		for k in range(1, p3.size() - 1):
			_under_tri([p3[0], p3[k], p3[k + 1]], [lv[0], lv[k], lv[k + 1]], bio)
	else:
		var us: Array = []
		for k in 4:
			var tx: int = cx + CX[k]; var tz: int = cz + CZ[k]
			us.append(Vector3(tx + 0.5, under[tz * w + tx], tz + 0.5))
		_under_tri([us[0], us[1], us[2]], [vs[0], vs[1], vs[2]], bio)
		_under_tri([us[0], us[2], us[3]], [vs[0], vs[2], vs[3]], bio)

## The part of a cell at or above threshold t: [points, colours, wall segments [[exit, entry]], info]
## where info is the tile index for a corner or the crossing dictionary for a contour point.
func _walk(cx: int, cz: int, vs: Array, t: int) -> Array:
	var pts: Array = []; var cols: Array = []; var info: Array = []
	var marks: Array = []      # [crossing, is_exit]
	for k in 4:
		var k2 := (k + 1) % 4
		var ax: int = cx + CX[k]; var az: int = cz + CZ[k]
		var bx: int = cx + CX[k2]; var bz: int = cz + CZ[k2]
		var ins: bool = vs[k] >= t
		var ins2: bool = vs[k2] >= t
		if ins:
			pts.append(Vector2(ax + 0.5, az + 0.5)); cols.append(tops[az * w + ax]); info.append(az * w + ax)
		if ins and not ins2:
			var X := _cross(ax, az, bx, bz, t)
			pts.append(X["p"]); cols.append(tops[az * w + ax]); info.append(X)
			marks.append([X, true])
		elif ins2 and not ins:
			var X2 := _cross(bx, bz, ax, az, t)
			pts.append(X2["p"]); cols.append(tops[bz * w + bx]); info.append(X2)
			marks.append([X2, false])
	var segs: Array = []
	var n := marks.size()
	for m in n:
		if marks[m][1]:
			for q in range(1, n + 1):
				var e: Array = marks[(m + q) % n]
				if not e[1]:
					segs.append([marks[m][0], e[0]])
					break
	return [pts, cols, segs, info]

# ------------------------------------------------------------------ cliffs
## One stretch of cliff between two contour points: the same row profile at both ends, so cliffs
## join up seamlessly from cell to cell. Where the ground below differs between the two ends, a
## plain skirt under the profile reaches down to the cell's lowest ground, so nothing shows through.
func _wall(P: Dictionary, Q: Dictionary, top: float, ground: float) -> void:
	var rp := _profile(P, top)
	var rq := _profile(Q, top)
	var nref: Vector2 = (P["n"] + Q["n"])
	var n3 := Vector3(nref.x, 0, nref.y).normalized()
	for r in ROWS - 1:
		var a: Vector3 = rp[r][0]; var b: Vector3 = rq[r][0]
		var c: Vector3 = rq[r + 1][0]; var d: Vector3 = rp[r + 1][0]
		var st: float = rp[r][2]
		var fn := (b - a).cross(d - a)
		if fn.length_squared() < 1e-8:
			fn = (c - b).cross(d - b)
		if fn.length_squared() < 1e-8:
			fn = (c - a).cross(d - a)
		if fn.length_squared() < 1e-8:
			continue
		fn = fn.normalized()
		if fn.dot(n3) < 0.0:
			fn = -fn
		if st == S_SHEER:
			var np := Vector3(P["n"].x, 0.0, P["n"].y); var nq := Vector3(Q["n"].x, 0.0, Q["n"].y)
			_quad_n(a, b, c, d, np, nq, nq, np, rp[r][1], rq[r][1], rq[r + 1][1], rp[r + 1][1], st, fn)
		else:
			_quad_n(a, b, c, d, fn, fn, fn, fn, rp[r][1], rq[r][1], rq[r + 1][1], rp[r + 1][1], st, fn)
	if P["void"] and Q["void"]:
		return
	var bp: Vector3 = rp[ROWS - 1][0]; var bq: Vector3 = rq[ROWS - 1][0]
	var sk := minf(minf(bp.y, bq.y), ground)
	if bp.y - sk < 0.01 and bq.y - sk < 0.01:
		return
	var cl: Color = rp[ROWS - 1][1]
	_quad_n(bp, bq, Vector3(bq.x, sk, bq.z), Vector3(bp.x, sk, bp.z), n3, n3, n3, n3, cl, cl, cl, cl, S_ROCK, n3)

## The cross-section of a cliff at one contour point: ROWS of [position, colour, style of the band
## below]. Depends only on the point and the terrace height, so neighbouring cells agree.
func _profile(X: Dictionary, top: float) -> Array:
	var p: Vector2 = X["p"]; var n: Vector2 = X["n"]
	var ia: int = X["a"]
	var bio: Dictionary = W._bio(ia) if ia >= 0 else W.biome
	var style: int = X["style"]
	var bottom: float = minf(X["rim"], top - 0.3) if X["void"] else float(X["ground"])
	var H := top - bottom
	var side: Color = bio["side"]
	var deep: Color = bio["deep"]
	var topc: Color = Color(bio["top2"]).lerp(bio["top"], 0.4)
	var jit := rn.get_noise_2d(p.x * 3.1 + 7.0, p.y * 3.1 - 3.0) * 0.13
	var jit2 := rn.get_noise_2d(p.x * 2.3 - 11.0, p.y * 2.3 + 5.0) * 0.08
	var rows: Array      # [out offset, y, colour, style of the band below this row]
	match style:
		E_LIP:
			# a ledge you can grab: a pale stone lip that sticks out over the rock
			var stone := Color("e9dcb6").lerp(side, 0.12)
			rows = [[0.0, top, stone.lightened(0.12), S_CAP], [0.17, top - 0.035, stone.lightened(0.1), S_CAP],
				[0.17, top - 0.25, stone.darkened(0.12), S_CAP], [0.02, top - 0.34, side.darkened(0.25), S_ROCK],
				[0.04 + jit, top - 0.34 - (H - 0.34) * 0.45, side.darkened(0.05), S_ROCK], [0.0, bottom, side.lerp(deep, 0.55), S_ROCK]]
		E_SHEER:
			# nothing to hold on to: smooth dark slate from top to bottom
			var slate := Color("5a5373").lerp(deep, 0.2)
			rows = [[0.0, top, slate.lightened(0.28), S_SHEER], [0.03, top - 0.03, slate.lightened(0.2), S_SHEER],
				[0.03, top - 0.09, slate.lightened(0.05), S_SHEER], [0.02, top - 0.12, slate, S_SHEER],
				[0.01, top - 0.12 - (H - 0.12) * 0.5, slate.lerp(deep, 0.3), S_SHEER], [0.0, bottom, deep.darkened(0.2), S_SHEER]]
		E_COAST:
			rows = [[0.0, top, topc.lightened(0.06), S_CAP], [0.08, top - 0.04, topc, S_CAP],
				[0.08, top - 0.17, topc.darkened(0.22), S_CAP], [0.0, top - 0.24, side.darkened(0.12), S_ROCK],
				[0.03 + jit, top - 0.24 - (H - 0.24) * 0.5, side, S_ROCK], [0.0, bottom, side.lerp(deep, 0.6), S_ROCK]]
		_:
			# a terrace step: a soft grassy bevel over a short face of earth and rock
			rows = [[0.0, top, topc.lightened(0.18), S_CAP], [0.06, top - 0.03, topc.lightened(0.1), S_CAP],
				[0.06, top - 0.13, topc.darkened(0.18), S_CAP], [0.0, top - 0.19, side.darkened(0.06), S_ROCK],
				[0.025 + jit2, top - 0.19 - (H - 0.19) * 0.5, side.darkened(0.2), S_ROCK], [0.0, bottom, side.darkened(0.5), S_ROCK]]
	var out: Array = []
	for r in rows:
		out.append([Vector3(p.x + n.x * float(r[0]), float(r[1]), p.y + n.y * float(r[0])), r[2], r[3]])
	return out

# ------------------------------------------------------------------ underside
func _under_tri(p: Array, _lv: Array, bio: Dictionary) -> void:
	var a: Vector3 = p[0]; var b: Vector3 = p[1]; var c: Vector3 = p[2]
	var fn := (b - a).cross(c - a)
	if fn.length_squared() < 1e-10:
		return
	fn = fn.normalized()
	if fn.y > 0.0: fn = -fn
	var side: Color = bio.get("side", Color("8b6d52"))
	var deep: Color = bio.get("deep", Color("3a3140"))
	var cols: Array = []
	for q in p:
		var y: float = (q as Vector3).y
		var k := clampf((-y - 0.5) / 14.0, 0.0, 1.0)
		cols.append(side.darkened(0.12).lerp(deep.darkened(0.15), sqrt(k)))
	_tri3(a, b, c, fn, cols[0], cols[1], cols[2], S_UNDER, false)

# ------------------------------------------------------------------ stairs
## A carved stone flight across one tile, rising toward dir, with stone side walls where the flight
## ends (a wide authored flight only gets them at its two ends).
func _stairs(x: int, z: int, dir: Vector2i, y: float) -> void:
	var i := z * w + x
	var bio: Dictionary = W._bio(i)
	var stone := Color("cdc4b2").lerp(Color(bio["side"]), 0.22).lerp(Color(bio["top"]), 0.08)
	var n := 4
	var to_world := func(u: float, s: float, hgt: float) -> Vector3:
		var fx: float; var fz: float
		match dir:
			Vector2i(1, 0): fx = u; fz = s
			Vector2i(-1, 0): fx = 1.0 - u; fz = 1.0 - s
			Vector2i(0, 1): fx = 1.0 - s; fz = u
			_: fx = s; fz = 1.0 - u
		return Vector3(x + fx, y + hgt, z + fz)
	var upv := Vector3(dir.x, 0, dir.y)
	var side_a := Vector3(-dir.y, 0, dir.x)
	# which ends of the flight need a side wall
	var cheeks: Array = []
	for sv in [0.0, 1.0]:
		var sd: Vector3 = to_world.call(0.5, -0.5 if sv == 0.0 else 1.5, 0.0)
		var nx := int(floor(sd.x)); var nz := int(floor(sd.z))
		var j := nz * w + nx
		var same: bool = nx >= 0 and nz >= 0 and nx < w and nz < h and W.stairs.has(j) and W.stairs[j] == dir
		cheeks.append(not same)
	var s0 := 0.13 if cheeks[0] else 0.0
	var s1 := 0.87 if cheeks[1] else 1.0
	for k in n:
		var u0 := float(k) / n; var u1 := float(k + 1) / n
		var hgt := LEVEL * float(k + 1) / n
		var tread := stone.lightened(0.07 if k % 2 == 0 else 0.0)
		var nose := 0.035
		# tread, with a little nosing over the riser below
		_quad_n(to_world.call(u0 - nose, s0, hgt), to_world.call(u1, s0, hgt), to_world.call(u1, s1, hgt), to_world.call(u0 - nose, s1, hgt),
			Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, tread.lightened(0.05), tread, tread, tread.lightened(0.05), S_STONE, Vector3.UP)
		# the nosing's front lip and the riser, in shadow under it
		_quad_n(to_world.call(u0 - nose, s0, hgt - 0.05), to_world.call(u0 - nose, s1, hgt - 0.05), to_world.call(u0 - nose, s1, hgt), to_world.call(u0 - nose, s0, hgt),
			-upv, -upv, -upv, -upv, tread.darkened(0.05), tread.darkened(0.05), tread, tread, S_STONE, -upv)
		_quad_n(to_world.call(u0, s0, hgt - LEVEL / n), to_world.call(u0, s1, hgt - LEVEL / n), to_world.call(u0, s1, hgt - 0.05), to_world.call(u0, s0, hgt - 0.05),
			-upv, -upv, -upv, -upv, stone.darkened(0.38), stone.darkened(0.38), stone.darkened(0.24), stone.darkened(0.24), S_STONE, -upv)
	# side walls: a sloped stone parapet along each open end of the flight
	for q in 2:
		if not cheeks[q]:
			continue
		var sa: float = 0.0 if q == 0 else 0.87
		var sb: float = 0.13 if q == 0 else 1.0
		var outn: Vector3 = -side_a if q == 0 else side_a
		var cs := stone.darkened(0.08)
		var t0 := 0.32; var t1 := LEVEL + 0.12
		var lo := -0.05
		var A0: Vector3 = to_world.call(-0.02, sa, lo); var A1: Vector3 = to_world.call(1.0, sa, lo)
		var B0: Vector3 = to_world.call(-0.02, sb, lo); var B1: Vector3 = to_world.call(1.0, sb, lo)
		var TA0: Vector3 = to_world.call(-0.02, sa, t0); var TA1: Vector3 = to_world.call(1.0, sa, t1)
		var TB0: Vector3 = to_world.call(-0.02, sb, t0); var TB1: Vector3 = to_world.call(1.0, sb, t1)
		var cap := cs.lightened(0.16)
		var ramp := (TA1 - TA0).normalized().cross(outn).normalized()
		if ramp.y < 0.0: ramp = -ramp
		_quad_n(TA0, TA1, TB1, TB0, ramp, ramp, ramp, ramp, cap, cap, cap, cap, S_STONE, ramp)
		var outer := [A0, A1, TA1, TA0] if q == 0 else [B0, B1, TB1, TB0]
		var inner := [B0, B1, TB1, TB0] if q == 0 else [A0, A1, TA1, TA0]
		_quad_n(outer[0], outer[1], outer[2], outer[3], outn, outn, outn, outn, cs.darkened(0.3), cs.darkened(0.3), cs, cs, S_STONE, outn)
		_quad_n(inner[0], inner[1], inner[2], inner[3], -outn, -outn, -outn, -outn, cs.darkened(0.35), cs.darkened(0.35), cs.darkened(0.05), cs.darkened(0.05), S_STONE, -outn)
		_quad_n(A0, B0, TB0, TA0, -upv, -upv, -upv, -upv, cs.darkened(0.3), cs.darkened(0.3), cs.darkened(0.1), cs.darkened(0.1), S_STONE, -upv)

# ------------------------------------------------------------------ emit
## One triangle; flips the winding so it faces along n (Godot's front faces are clockwise).
func _tri3(a: Vector3, b: Vector3, c: Vector3, n: Vector3, ca: Color, cb: Color, cc: Color, st: float, _top: bool) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b; b = c; c = t
		var tc := cb; cb = cc; cc = tc
	V.append(a); V.append(b); V.append(c)
	N.append(n); N.append(n); N.append(n)
	C.append(ca); C.append(cb); C.append(cc)
	var u := Vector2(st, 0.0)
	UV.append(u); UV.append(u); UV.append(u)

func _quad_n(a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3,
		ca: Color, cb: Color, cc: Color, cd: Color, st: float, face: Vector3) -> void:
	var flip := (b - a).cross(c - a).dot(face) > 0.0
	if (b - a).cross(c - a).length_squared() < 1e-10:
		flip = (c - a).cross(d - a).dot(face) > 0.0
	var u := Vector2(st, 0.0)
	var tris := [[a, b, c, na, nb, nc, ca, cb, cc], [a, c, d, na, nc, nd, ca, cc, cd]]
	for t in tris:
		if flip:
			V.append(t[0]); V.append(t[2]); V.append(t[1])
			N.append(t[3]); N.append(t[5]); N.append(t[4])
			C.append(t[6]); C.append(t[8]); C.append(t[7])
		else:
			V.append(t[0]); V.append(t[1]); V.append(t[2])
			N.append(t[3]); N.append(t[4]); N.append(t[5])
			C.append(t[6]); C.append(t[7]); C.append(t[8])
		UV.append(u); UV.append(u); UV.append(u)
