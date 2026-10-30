extends RefCounted
## Built stone walls, drawn as old ruins that follow each wall run: chunky bevelled blocks laid in
## staggered courses over a dark mortar core, square posts at corners and ends, a wider capstone on
## top with a cover of grass (or snow, or sand) and the odd stretch worn down a course or two.
## Curved walls (rings) follow a smoothed line instead of zigzagging tile to tile. Purely visual:
## the wall tiles still block exactly as before.

const COURSE := 0.4        # height of one course of stone
const THICK := 0.78        # wall thickness (a tile is 1)
const DIRS := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1), Vector2i(1, -1)]

var W: Node
var rr := RandomNumberGenerator.new()
var nz := FastNoiseLite.new()
var chunks := {}     # Vector2i -> [verts, normals, colours]
var pos := {}        # tile index -> smoothed Vector3 (base of the wall)
var links := {}      # tile index -> Array of linked tile indices
var height := {}     # tile index -> courses

func _init(world: Node) -> void:
	W = world
	rr.seed = int(W.rng.seed) + 211
	nz.seed = int(W.rng.seed) + 5
	nz.frequency = 0.18

func is_wall(x: int, z: int) -> bool:
	return W.inb(x, z) and W.walls.has(W.idx(x, z)) and W.kind[W.idx(x, z)] == W.T_BLOCK

## Mesh instances for every wall on the map, split into 24x24-tile chunks.
func build(mat: Material) -> Array:
	var ww: int = W.w
	for wi in W.walls:
		var i: int = wi
		if W.kind[i] != W.T_BLOCK:
			continue
		var x := i % ww; var z := i / ww
		var ls: Array = []
		for k in 8:
			var d: Vector2i = DIRS[k]
			if not is_wall(x + d.x, z + d.y):
				continue
			if k >= 4 and (is_wall(x + d.x, z) or is_wall(x, z + d.y)):
				continue     # a diagonal step already joined through a straight neighbour
			ls.append(W.idx(x + d.x, z + d.y))
		links[i] = ls
		pos[i] = Vector3(x + 0.5, W.level[i] * W.LEVEL, z + 0.5)
		# mostly full height, worn down a course here and there along a run
		var n := 5
		var wear := nz.get_noise_2d(x, z)
		if wear < -0.3: n = 4
		if wear < -0.55: n = 3
		if ls.size() != 2: n = maxi(n, 5)
		height[i] = n
	# smooth the line of each run: a tile with two neighbours moves toward their midpoint, so rings
	# curve and diagonal steps straighten (straight runs don't move)
	# (a square corner with straight arms on both sides is a built corner: it stays square)
	var fixed := {}
	for ik in pos:
		var i: int = ik
		var ls: Array = links[i]
		if ls.size() != 2:
			continue
		var da := Vector2i(int(ls[0]) % ww - i % ww, int(ls[0]) / ww - i / ww)
		var db := Vector2i(int(ls[1]) % ww - i % ww, int(ls[1]) / ww - i / ww)
		if da.x * db.x + da.y * db.y != 0 or absi(da.x) + absi(da.y) != 1 or absi(db.x) + absi(db.y) != 1:
			continue
		var x := i % ww; var z := i / ww
		if is_wall(x + da.x * 2, z + da.y * 2) and is_wall(x + db.x * 2, z + db.y * 2):
			fixed[i] = true
	for _it in 3:
		var nxt := {}
		for i in pos:
			var ls: Array = links[i]
			var p: Vector3 = pos[i]
			if ls.size() == 2 and not fixed.has(i):
				var m: Vector3 = (pos[ls[0]] + pos[ls[1]]) * 0.5
				p = Vector3(p.x * 0.5 + m.x * 0.5, p.y, p.z * 0.5 + m.z * 0.5)
			nxt[i] = p
		pos = nxt
	for i in pos:
		var bio: Dictionary = W._bio(i)
		var stone := Color("b8b0a0").lerp(Color(bio["side"]), 0.16).lerp(Color(bio["top"]), 0.08)
		var cover := Color(bio["top"]).lerp(Color(bio["leaf"]), 0.3).lightened(0.04)
		var ls: Array = links[i]
		var p: Vector3 = pos[i]
		var n: int = height[i]
		var key := Vector2i(int(p.x) / 24, int(p.z) / 24)
		# runs to each neighbour (each pair once)
		for j in ls:
			if j < i and links.has(j):
				continue
			_run(key, p, pos[j], n, int(height[j]), stone, cover)
		# a post at the joint: square to the run, larger at corners, junctions and ends
		var dirs: Array = []
		for j in ls:
			var d: Vector3 = pos[j] - p; d.y = 0.0
			dirs.append(d.normalized())
		var post := true
		var u := Vector3.RIGHT
		if dirs.size() == 2:
			var dd: float = (dirs[0] as Vector3).dot(dirs[1])
			if dd < -0.97:
				post = false      # a straight run: the blocks carry straight through
			u = ((dirs[0] as Vector3) - (dirs[1] as Vector3)).normalized()
		elif dirs.size() == 1:
			u = dirs[0]
		elif dirs.size() > 2:
			u = dirs[0]
		if post:
			var half := THICK * (0.56 if dirs.size() == 2 else 0.6)
			var pn := n + (1 if dirs.size() <= 1 else 0)
			_post(key, p, u, half, pn, stone, cover)
	var out: Array = []
	for key in chunks:
		var ch: Array = chunks[key]
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = ch[0]; arr[Mesh.ARRAY_NORMAL] = ch[1]; arr[Mesh.ARRAY_COLOR] = ch[2]
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = mat
		mi.name = "Walls_%d_%d" % [key.x, key.y]
		out.append(mi)
	return out

## Coursed stone from a to b: courses both ends share run the whole way; the taller end's extra
## courses step down partway along, like a wall that has crumbled.
func _run(key: Vector2i, a: Vector3, b: Vector3, na: int, nb: int, stone: Color, cover: Color) -> void:
	var d := b - a; d.y = 0.0
	var length := d.length()
	if length < 0.01:
		return
	var u := d / length
	var v := Vector3(-u.z, 0, u.x)
	var base := minf(a.y, b.y)
	var hi := maxi(na, nb)
	var lo := mini(na, nb)
	_box(key, (a + b) * 0.5 + Vector3(0, base - (a.y + b.y) * 0.5, 0), u, v, length * 0.5, THICK * 0.5 - 0.05, lo * COURSE - 0.05, stone.darkened(0.55), stone.darkened(0.5), 0.0)
	for k in hi:
		var s0 := 0.0; var s1 := length
		if k >= lo:
			# only the taller end reaches this course
			var reach := length * (0.55 - 0.18 * (k - lo))
			if na > nb: s1 = reach
			else: s0 = length - reach
			if s1 - s0 < 0.2:
				continue
		var cuts: Array = [s0]
		var off := s0 + (rr.randf_range(0.25, 0.5) if k % 2 == 0 else rr.randf_range(0.5, 0.8))
		while off < s1 - 0.25:
			cuts.append(off); off += rr.randf_range(0.55, 0.85)
		cuts.append(s1)
		for q in cuts.size() - 1:
			var c0: float = cuts[q]; var c1: float = cuts[q + 1]
			var at := a + u * ((c0 + c1) * 0.5)
			at.y = base + k * COURSE
			var hu := (c1 - c0) * 0.5 - 0.012
			var col := _shade(stone, k)
			if k == hi - 1 or (k == lo - 1 and _exposed(c0, c1, length, na, nb, lo)):
				# capstone: wider, lighter, with a cover of grass or snow on top
				_box(key, at, u, v, hu + 0.01, THICK * 0.5 + 0.05, COURSE - 0.015, col.lightened(0.06), col.lightened(0.16), 0.05)
				_box(key, at + Vector3(0, COURSE - 0.02, 0), u, v, hu - 0.02, THICK * 0.5 + 0.0, 0.07, cover.darkened(0.12), cover, 0.035)
			else:
				_box(key, at + v * rr.randf_range(-0.02, 0.02), u, v, hu, THICK * 0.5 + rr.randf_range(-0.01, 0.015), COURSE - 0.015, col, col.lightened(0.08), 0.045)

func _exposed(c0: float, c1: float, length: float, na: int, nb: int, lo: int) -> bool:
	# a block on the lower common course is open to the sky where the taller end's next course stops
	if na == nb:
		return true
	var reach := length * 0.55
	var mid := (c0 + c1) * 0.5
	return mid > reach if na > nb else mid < length - reach

## A square post standing at a joint or at the end of a run.
func _post(key: Vector2i, p: Vector3, u: Vector3, half: float, n: int, stone: Color, cover: Color) -> void:
	var v := Vector3(-u.z, 0, u.x)
	for k in n:
		var at := p + Vector3(0, k * COURSE, 0)
		var col := _shade(stone, k).lightened(0.03)
		if k == n - 1:
			_box(key, at, u, v, half + 0.04, half + 0.04, COURSE - 0.015, col.lightened(0.05), col.lightened(0.16), 0.05)
			_box(key, at + Vector3(0, COURSE - 0.02, 0), u, v, half - 0.02, half - 0.02, 0.07, cover.darkened(0.12), cover, 0.035)
		else:
			_box(key, at, u, v, half, half, COURSE - 0.015, col, col.lightened(0.08), 0.045)

func _shade(stone: Color, k: int) -> Color:
	var j := rr.randf_range(-0.04, 0.04)
	var c := stone.darkened(0.05 * (2 - mini(k, 2)))     # lower courses a touch darker
	return c.lightened(j) if j > 0.0 else c.darkened(-j)

func _ch(key: Vector2i) -> Array:
	if not chunks.has(key):
		chunks[key] = [PackedVector3Array(), PackedVector3Array(), PackedColorArray()]
	return chunks[key]

## A block standing on c (its base centre), along u and v, hh tall, with its top edges bevelled by b;
## no bottom face.
func _box(key: Vector2i, c: Vector3, u: Vector3, v: Vector3, hu: float, hv: float, hh: float, side: Color, top: Color, b: float) -> void:
	var ch := _ch(key)
	b = minf(b, minf(hu, hv) * 0.4)
	var p := [c - u * hu - v * hv, c + u * hu - v * hv, c + u * hu + v * hv, c - u * hu + v * hv]
	var sh := Vector3.UP * (hh - b)
	var up := Vector3.UP * hh
	var tp := [p[0] + (u + v) * b + up, p[1] + (v - u) * b + up, p[2] - (u + v) * b + up, p[3] + (u - v) * b + up]
	_quad(ch, tp[0], tp[1], tp[2], tp[3], Vector3.UP, top, top)
	for k in 4:
		var a: Vector3 = p[k]; var bb: Vector3 = p[(k + 1) % 4]
		var n := (a + bb) * 0.5 - c
		n.y = 0.0
		n = n.normalized()
		_quad(ch, a, bb, bb + sh, a + sh, n, side.darkened(0.14), side)
		if b > 0.0:
			var bn := (n + Vector3.UP).normalized()
			_quad(ch, a + sh, bb + sh, tp[(k + 1) % 4], tp[k], bn, side.lightened(0.06), top)

func _quad(ch: Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, lo: Color, hi: Color) -> void:
	var cols := [lo, lo, hi, hi] if n.y < 0.5 else [hi, hi, hi, hi]
	var pts := [a, b, c, d]
	if (b - a).cross(c - a).dot(n) > 0.0:
		pts = [d, c, b, a]; cols = [cols[3], cols[2], cols[1], cols[0]]
	for t in [[0, 1, 2], [0, 2, 3]]:
		for q in t:
			ch[0].append(pts[q]); ch[1].append(n); ch[2].append(cols[q])
