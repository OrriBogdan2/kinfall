class_name Models
## Builds every character and prop out of simple meshes. Each character returns a Node3D whose
## meta "mat" holds the ShaderMaterials to flash on hits, and named child nodes for animation.

static var TOON: Shader = preload("res://shaders/toon.gdshader")
static var OUTLINE: Shader = preload("res://shaders/outline.gdshader")
static var RING: Shader = preload("res://shaders/ring.gdshader")
static var GLOW: Shader = preload("res://shaders/glowball.gdshader")
static var _outline_mat: ShaderMaterial

static func toon(c: Color, outline := true, glow := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TOON
	m.set_shader_parameter("albedo", c)
	m.set_shader_parameter("glow", glow)
	if outline:
		if _outline_mat == null:
			_outline_mat = ShaderMaterial.new()
			_outline_mat.shader = OUTLINE
		m.next_pass = _outline_mat
	return m

static func vtoon() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TOON
	m.set_shader_parameter("use_vertex_color", true)
	m.set_shader_parameter("rim_amount", 0.12)
	return m

static func ring_mat(c: Color, thickness := 0.14) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = RING
	m.set_shader_parameter("color", c)
	m.set_shader_parameter("thickness", thickness)
	return m

static func glow_mat(c: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = GLOW
	m.set_shader_parameter("color", c)
	return m

static func part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, scl := Vector3.ONE, rot := Vector3.ZERO, pname := "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	mi.rotation = rot
	if pname != "":
		mi.name = pname
	parent.add_child(mi)
	return mi

static var _spheres := {}

## A smooth sphere. The segment count scales with size (so big shapes stay round in close-ups and
## tiny dots stay cheap); `seg` is a floor. Cached, so every eye of every hunter shares one mesh.
static func sphere(r: float, seg := 16) -> SphereMesh:
	var sg := seg + (8 if r > 0.12 else 4)
	if seg > 8 or r >= 0.1:
		sg = maxi(sg, int(clampf(r * 100.0, 14.0, 28.0)))
	sg += sg % 2
	var key := "%.4f|%d" % [r, sg]
	if _spheres.has(key):
		return _spheres[key]
	var s := SphereMesh.new()
	s.radius = r; s.height = r * 2.0; s.radial_segments = sg; s.rings = maxi(8, sg / 2)
	_spheres[key] = s
	return s

static func capsule(r: float, h: float) -> CapsuleMesh:
	var key := "cap|%.4f|%.4f" % [r, h]
	if _spheres.has(key):
		return _spheres[key]
	var c := CapsuleMesh.new()
	c.radius = r; c.height = h; c.radial_segments = int(clampf(r * 220.0, 14.0, 32.0)); c.rings = 10
	_spheres[key] = c
	return c

static var _rbox := {}

## A box with softly rounded edges and corners (a real fillet with several steps, so it shades and
## outlines cleanly instead of reading as a cube). Cached by size, so it costs nothing after the first.
static func box(x: float, y: float, z: float) -> Mesh:
	var mn := minf(x, minf(y, z))
	var r := minf(mn * 0.22, 0.07) if mn >= 0.04 else mn * 0.36
	if r < 0.0015:
		var b := BoxMesh.new()
		b.size = Vector3(x, y, z)
		return b
	var key := "%.4f|%.4f|%.4f" % [x, y, z]
	if _rbox.has(key):
		return _rbox[key]
	var am := rounded_box(Vector3(x, y, z), r, 3 if mn > 0.12 else 2)
	_rbox[key] = am
	return am

## A rounded box: every face is a grid whose outer rows are bent around the edges and corners on a
## radius r, with `steps` grid lines per 45 degrees of the bend.
static func rounded_box(size: Vector3, r: float, steps := 3) -> ArrayMesh:
	var h := size * 0.5
	var inner := (h - Vector3(r, r, r)).max(Vector3.ZERO)
	var verts := PackedVector3Array(); var norms := PackedVector3Array(); var uvs := PackedVector2Array(); var idx: Array = []
	var axes := [[0, 1, 2], [1, 2, 0], [2, 0, 1]]
	for ax in axes:
		var w: int = ax[0]; var u: int = ax[1]; var v: int = ax[2]
		var cu := _bevel_coords(h[u], inner[u], r, steps)
		var cv := _bevel_coords(h[v], inner[v], r, steps)
		for sgn in [-1.0, 1.0]:
			var base := verts.size()
			for j in cv.size():
				for i in cu.size():
					var p := Vector3.ZERO
					p[w] = h[w] * sgn; p[u] = cu[i]; p[v] = cv[j]
					var cl := p.clamp(-inner, inner)
					var d := p - cl
					var nd := d.normalized() if d.length() > 0.000001 else Vector3.ZERO
					if nd == Vector3.ZERO: nd[w] = sgn
					verts.append(cl + nd * r)
					norms.append(nd)
					uvs.append(Vector2(float(i) / (cu.size() - 1), float(j) / (cv.size() - 1)))
			var nu := cu.size()
			for j in cv.size() - 1:
				for i in nu - 1:
					var a := base + j * nu + i
					_quad(verts, norms, idx, a, a + 1, a + nu + 1, a + nu)
	return _commit(verts, norms, uvs, idx)

## Grid lines across one face of a rounded box: the flat middle, then the bend toward each edge.
static func _bevel_coords(hh: float, ii: float, r: float, steps: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var bend := PackedFloat32Array()
	for k in range(1, steps + 1):
		bend.append(ii + r * tan(PI * 0.25 * float(k) / steps))
	for k in range(bend.size() - 1, -1, -1): out.append(-bend[k])
	if ii > 0.0001:
		out.append(-ii); out.append(ii)
	else:
		out.append(0.0)
	for b in bend: out.append(b)
	out[0] = -hh; out[out.size() - 1] = hh
	return out

## Two triangles for the quad a-b-c-d, wound so they face along the vertex normals (Godot draws
## clockwise faces as the front).
static func _quad(verts: PackedVector3Array, norms: PackedVector3Array, idx: Array, a: int, b: int, c: int, d: int) -> void:
	for tri in [[a, b, c], [a, c, d]]:
		var p0 := verts[tri[0]]; var p1 := verts[tri[1]]; var p2 := verts[tri[2]]
		var fn := (p1 - p0).cross(p2 - p0)
		if fn.length_squared() < 1e-14:
			continue
		var nsum := norms[tri[0]] + norms[tri[1]] + norms[tri[2]]
		if fn.dot(nsum) > 0.0:
			idx.append(tri[0]); idx.append(tri[2]); idx.append(tri[1])
		else:
			idx.append(tri[0]); idx.append(tri[1]); idx.append(tri[2])

static func _commit(verts: PackedVector3Array, norms: PackedVector3Array, uvs: PackedVector2Array, idx: Array) -> ArrayMesh:
	var arrs := []
	arrs.resize(Mesh.ARRAY_MAX)
	arrs[Mesh.ARRAY_VERTEX] = verts
	arrs[Mesh.ARRAY_NORMAL] = norms
	arrs[Mesh.ARRAY_TEX_UV] = uvs
	arrs[Mesh.ARRAY_INDEX] = PackedInt32Array(idx)
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrs)
	return am

static var _lathes := {}

## A smooth solid of revolution around Y: `profile` is (radius, height) from the bottom up. Points
## with radius 0 close the shape on the axis. Normals come from the profile's own curve, so it
## shades as one soft surface. Cached by `key` when one is given.
static func lathe(profile: PackedVector2Array, seg := 24, key := "") -> ArrayMesh:
	if key != "" and _lathes.has(key):
		return _lathes[key]
	var n := profile.size()
	var verts := PackedVector3Array(); var norms := PackedVector3Array(); var uvs := PackedVector2Array(); var idx: Array = []
	var total := 0.0
	var acc := PackedFloat32Array([0.0])
	for i in range(1, n):
		total += profile[i].distance_to(profile[i - 1])
		acc.append(total)
	for i in n:
		var p := profile[i]
		var t := profile[mini(i + 1, n - 1)] - profile[maxi(i - 1, 0)]
		if t.length() < 1e-6: t = Vector2(0, 1)
		t = t.normalized()
		var n2 := Vector2(t.y, -t.x)
		if p.x < 1e-5 and i == 0: n2 = Vector2(0, -1)
		elif p.x < 1e-5 and i == n - 1: n2 = Vector2(0, 1)
		for j in seg + 1:
			var a := TAU * float(j) / seg
			var ca := cos(a); var sa := sin(a)
			verts.append(Vector3(p.x * ca, p.y, p.x * sa))
			norms.append(Vector3(n2.x * ca, n2.y, n2.x * sa).normalized())
			uvs.append(Vector2(float(j) / seg, acc[i] / maxf(total, 1e-5)))
	for i in n - 1:
		for j in seg:
			var a0 := i * (seg + 1) + j
			var b0 := (i + 1) * (seg + 1) + j
			_quad(verts, norms, idx, a0, a0 + 1, b0 + 1, b0)
	var am := _commit(verts, norms, uvs, idx)
	if key != "": _lathes[key] = am
	return am

## A smooth curve through the given points (Catmull-Rom), `sub` steps per span. The ends are kept.
static func smooth_curve(pts: PackedVector2Array, sub := 4) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n - 1:
		var p0 := pts[maxi(i - 1, 0)]; var p1 := pts[i]; var p2 := pts[i + 1]; var p3 := pts[mini(i + 2, n - 1)]
		for k in sub:
			var t := float(k) / sub
			var t2 := t * t; var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(pts[n - 1])
	for i in out.size():
		out[i].x = maxf(out[i].x, 0.0)
	return out

## Rounds every corner of a closed polygon with an arc of radius r (smaller where the sides are short).
static func _fillet(poly: Array, r: float, steps: int) -> Array:
	var out: Array = []
	var n := poly.size()
	for i in n:
		var p: Vector2 = poly[i]
		var a: Vector2 = poly[(i - 1 + n) % n]
		var b: Vector2 = poly[(i + 1) % n]
		var u := (a - p).normalized(); var v := (b - p).normalized()
		var th := acos(clampf(u.dot(v), -1.0, 1.0))
		if th > PI - 0.02 or th < 0.01 or r <= 0.0:
			out.append(p)
			continue
		var d := r / tan(th * 0.5)
		var rr := r
		var dmax := 0.49 * minf(a.distance_to(p), b.distance_to(p))
		if d > dmax:
			d = dmax; rr = d * tan(th * 0.5)
		var t1 := p + u * d
		var c := p + (u + v).normalized() * rr / sin(th * 0.5)
		var a1 := (t1 - c).angle()
		var a2 := (p + v * d - c).angle()
		var da := wrapf(a2 - a1, -PI, PI)
		for k in steps + 1:
			var ang := a1 + da * float(k) / steps
			out.append(c + Vector2(cos(ang), sin(ang)) * rr)
	return out

static var _cyls := {}

## A plain cylinder (open ends possible), for beams and columns of light.
static func plain_cyl(top: float, bottom: float, h: float, seg := 14) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top; c.bottom_radius = bottom; c.height = h; c.radial_segments = seg + 6; c.rings = 1
	return c

## A cylinder or cone with softly rounded rims (and a rounded tip on a cone), so it shades and
## outlines as one clean shape. Hair-thin ones stay plain. Cached by size.
static func cyl(top: float, bottom: float, h: float, seg := 14) -> Mesh:
	var mr := maxf(top, bottom)
	var radial := maxi(seg + 6, int(clampf(mr * 100.0, 12.0, 40.0)))
	if mr < 0.014 or h < 0.012:
		var c := CylinderMesh.new()
		c.top_radius = top; c.bottom_radius = bottom; c.height = h; c.radial_segments = maxi(seg + 2, 8); c.rings = 1
		return c
	var key := "%.4f|%.4f|%.4f|%d" % [top, bottom, h, radial]
	if _cyls.has(key):
		return _cyls[key]
	var hh := h * 0.5
	var poly: Array = []
	poly.append(Vector2(bottom, -hh) if bottom > 0.0005 else Vector2(0.0, -hh))
	poly.append(Vector2(top, hh) if top > 0.0005 else Vector2(0.0, hh))
	if top > 0.0005: poly.append(Vector2(-top, hh))
	if bottom > 0.0005: poly.append(Vector2(-bottom, -hh))
	var bev := clampf(minf(h, 2.0 * mr) * 0.16, 0.0, 0.045)
	var loop := _fillet(poly, bev, 3)
	var prof := _right_half(loop)
	var am := lathe(prof, radial)
	_cyls[key] = am
	return am

## The x >= 0 half of a closed, counter-clockwise outline that is mirror-symmetric about x = 0,
## from where it crosses the axis at the bottom to where it crosses back at the top.
static func _right_half(loop: Array) -> PackedVector2Array:
	var n := loop.size()
	var out := PackedVector2Array()
	var start := -1
	for i in n:
		if (loop[i] as Vector2).x < 0.0 and (loop[(i + 1) % n] as Vector2).x >= 0.0:
			start = i
			break
	if start < 0:
		return out
	var cross := func(p: Vector2, q: Vector2) -> Vector2:
		var t := p.x / (p.x - q.x) if absf(p.x - q.x) > 1e-9 else 0.0
		return Vector2(0.0, lerpf(p.y, q.y, t))
	out.append(cross.call(loop[start], loop[(start + 1) % n]))
	var k := (start + 1) % n
	for _g in n:
		var p: Vector2 = loop[k]
		var q: Vector2 = loop[(k + 1) % n]
		if p.distance_to(out[out.size() - 1]) > 1e-6:
			out.append(p)
		if q.x < 0.0:
			var c: Vector2 = cross.call(p, q)
			if c.distance_to(out[out.size() - 1]) > 1e-6: out.append(c)
			else: out[out.size() - 1] = c
			break
		k = (k + 1) % n
	return out

## A tapered limb along -Y from the joint: rounded at both ends, `r0` at the top, `r1` at the
## bottom, a little fuller a third of the way down (a muscle, a sleeve). Centred like a capsule.
static func limb(r0: float, r1: float, h: float, bulge := 0.08) -> ArrayMesh:
	var key := "limb|%.4f|%.4f|%.4f|%.3f" % [r0, r1, h, bulge]
	if _lathes.has(key):
		return _lathes[key]
	var hh := h * 0.5
	var pts := PackedVector2Array()
	# bottom cap
	for k in 5:
		var a := -PI * 0.5 + PI * 0.5 * float(k) / 4.0
		pts.append(Vector2(cos(a) * r1, -hh + r1 + sin(a) * r1))
	var mid := lerpf(r1, r0, 0.62) * (1.0 + bulge)
	pts.append(Vector2(lerpf(r1, r0, 0.3), lerpf(-hh + r1, hh - r0, 0.3)))
	pts.append(Vector2(mid, lerpf(-hh + r1, hh - r0, 0.66)))
	for k in 5:
		var a := PI * 0.5 * float(k) / 4.0
		pts.append(Vector2(cos(a) * r0, hh - r0 + sin(a) * r0))
	var prof := smooth_curve(pts, 2)
	prof[0] = Vector2(0, -hh); prof[prof.size() - 1] = Vector2(0, hh)
	var am := lathe(prof, int(clampf(maxf(r0, r1) * 220.0, 14.0, 24.0)))
	_lathes[key] = am
	return am

static var _eyes := {}

## A glossy creature eye in one mesh: a dark eyeball with a big coloured iris (lighter toward the
## bottom, like a painted anime eye) and a pupil, all facing -Z. Coloured by vertex, so it squashes
## as one piece when the kin blinks.
static func eye_mesh(r: float, iris: Color, dark := Color("1a1620")) -> ArrayMesh:
	var key := "%.4f|%s" % [r, iris.to_html()]
	if _eyes.has(key):
		return _eyes[key]
	var sm := SphereMesh.new()
	sm.radius = r; sm.height = r * 2.0; sm.radial_segments = 28; sm.rings = 18
	var arrs := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
	var cols := PackedColorArray()
	cols.resize(verts.size())
	var lo := iris.lightened(0.38)
	var pupil := dark.darkened(0.5)
	for i in verts.size():
		var v := verts[i] / r
		var ang := acos(clampf(-v.z, -1.0, 1.0))
		var c := dark
		if ang < 0.78:
			var k := clampf((-v.y * 0.5 + 0.5), 0.0, 1.0)
			c = iris.lerp(lo, smoothstep(0.35, 0.9, k))
			if ang > 0.66: c = c.lerp(dark, 0.55)          # a dark ring round the iris
			if ang < 0.34: c = pupil
		cols[i] = c
	arrs[Mesh.ARRAY_COLOR] = cols
	arrs[Mesh.ARRAY_TANGENT] = null
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrs)
	_eyes[key] = am
	return am

static var _crystals := {}

## A cut crystal: a faceted prism with a pointed top, flat-shaded on purpose so it glints.
static func crystal(r: float, h: float, sides := 6) -> ArrayMesh:
	var key := "%.4f|%.4f|%d" % [r, h, sides]
	if _crystals.has(key):
		return _crystals[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y0 := -h * 0.5; var y1 := h * 0.18; var y2 := h * 0.5
	var ring0: Array = []; var ring1: Array = []
	for i in sides:
		var a := TAU * float(i) / sides
		ring0.append(Vector3(cos(a) * r * 0.78, y0, sin(a) * r * 0.78))
		ring1.append(Vector3(cos(a) * r, y1, sin(a) * r))
	var tip := Vector3(0, y2, 0)
	var bot := Vector3(0, y0, 0)
	var tris: Array = []
	for i in sides:
		var j := (i + 1) % sides
		tris.append([ring0[i], ring0[j], ring1[j]]); tris.append([ring0[i], ring1[j], ring1[i]])
		tris.append([ring1[i], ring1[j], tip])
		tris.append([bot, ring0[j], ring0[i]])
	for t in tris:
		var a: Vector3 = t[0]; var b: Vector3 = t[1]; var c: Vector3 = t[2]
		var fn := (b - a).cross(c - a).normalized()
		var out := ((a + b + c) / 3.0).normalized() if ((a + b + c) / 3.0).length() > 1e-5 else Vector3.UP
		if fn.dot(out) > 0.0:
			var tmp := b; b = c; c = tmp
			fn = -fn
		for p in [a, b, c]:
			st.set_normal(-fn)
			st.add_vertex(p)
	var am := st.commit()
	_crystals[key] = am
	return am

## A glossy material: metal, gems, polished things catch a crisp highlight.
static func shiny(c: Color, gloss := 0.6) -> ShaderMaterial:
	var m := toon(c)
	m.set_shader_parameter("gloss", gloss)
	m.set_shader_parameter("paint", 0.03)
	return m

static func flat_quad(size: float) -> PlaneMesh:
	var p := PlaneMesh.new()
	p.size = Vector2(size, size)
	return p

# ---------------------------------------------------------------- hunters
## Looks a player can pick for their hunter. Purely visual: the body's size never changes the hitbox.
# Natural tones first, then the wild ones (sky, moss, lilac, gold, stone...). New entries only ever
# go on the end, so saved looks keep their colours.
const LOOK_SKIN := [Color("f6d3b0"), Color("f1c9a0"), Color("e0ac7e"), Color("c68a5c"), Color("9a6440"), Color("6e4428"), Color("4a2e1e"),
	Color("fff0e6"), Color("3a2216"), Color("8ab4ff"), Color("4a6ad8"), Color("8ad07a"), Color("4f8f45"), Color("c4a2f0"), Color("7a4ab8"),
	Color("ff9ab8"), Color("e8c050"), Color("5ac8c0"), Color("d8604a"), Color("9a9aa8"), Color("e8eef8"), Color("ff8a3a")]
const LOOK_HAIR := [Color("2b2124"), Color("5a3a26"), Color("9a6a3a"), Color("e8c87a"), Color("d8d2c8"), Color("c4462e"), Color("6a8aff"), Color("ff8ac8"),
	Color("f6efd8"), Color("8a2e2a"), Color("3ac8c0"), Color("8a4ad8"), Color("5ac85a"), Color("ff8a2a"), Color("c8a8ff"), Color("9af0c8"),
	Color("d81e3c"), Color("2a3a7a"), Color("fbfbfb"), Color("ffd84a")]
const LOOK_BODIES := ["Slim", "Average", "Sturdy"]
const LOOK_GENDERS := ["Female", "Male"]
const LOOK_FACES := ["Bright eyes", "Calm", "Sleepy", "Cheerful", "Fierce", "Wink", "Starry", "Determined", "Smug"]
const LOOK_HAIRS := ["Short", "Long", "Ponytail", "Bun", "Spiky", "Buzzed", "Bob", "Pigtails", "Braid", "Mohawk", "Afro", "Curly", "Swoop", "Bald"]
## What grows on each race's head: every race has its own styles (all take the hair colour). The
## look's "hair" is an index into its race's list (looks saved before this, without "hair_v", held an
## index into LOOK_HAIRS for every race, and are mapped to the closest style with HAIR_FROM_OLD).
const HAIR_STYLES := {
	"human": LOOK_HAIRS,
	"vulpin": ["Fluffy tuft", "Mane", "Long fur", "Brush tail", "Spiky fur", "Sleek", "Fringe"],
	"stoneborn": ["Crystal crown", "Crystal ridge", "Stone ridge", "Moss cap", "Geode"],
	"sprig": ["Leaf crown", "Flower bud", "Vine locks", "Sprout", "Petal bob", "Toadstool"],
	"scalefolk": ["Crest", "Frills", "Horns", "Spines", "Twin crest"],
	"owlet": ["Ear tufts", "Feather crest", "Plume", "Fluffy crown", "Swept back", "Long plumes"],
}
## Old shared-list index (Short, Long, Ponytail, Bun, Spiky, Buzzed, Bob, Pigtails, Braid, Mohawk,
## Afro, Curly, Swoop, Bald) to the closest style of each race.
const HAIR_FROM_OLD := {
	"vulpin": [0, 2, 3, 0, 4, 5, 6, 3, 3, 1, 1, 0, 6, 5],
	"stoneborn": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
	"sprig": [3, 2, 2, 1, 0, 3, 4, 2, 2, 0, 5, 0, 4, 3],
	"scalefolk": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
	"owlet": [0, 5, 2, 3, 1, 0, 4, 5, 2, 1, 3, 3, 4, 0],
}

## The head styles a race can pick from (by race index).
static func hair_styles(race: int) -> Array:
	return HAIR_STYLES[String(RACES[clampi(race, 0, RACES.size() - 1)]["id"])]
## Outfits: a coat colour and headwear. Purely cosmetic.
const LOOK_OUTFITS := ["Hood", "Horned", "Goggles", "Wide hat", "Bandana", "Ember", "Helm", "Brawler", "Halo"]
const OUTFIT_KEYS := ["veil", "nyx", "kestrel", "sage", "marlow", "pyra", "bastion", "tusk", "halo"]
const OUTFIT_COLS := [Color("c9bcff"), Color("b06ae0"), Color("6ad0e0"), Color("9ee2a0"), Color("e0b05a"), Color("ff7a5a"), Color("e6dbc4"), Color("c08a5a"), Color("f2d47a")]
const LOOK_DETAILS := ["None", "Freckles", "Scar", "Face paint", "Stubble", "Beard", "Moustache", "Beauty mark"]

## Races: each one changes the whole silhouette (size, head, build and features), so hunters read as
## different people at a glance from the high match camera. Purely visual: the hitbox comes from the
## class, never the race. "skin": the skin colour picked when you switch to it.
const RACES := [
	{"id": "human", "name": "Human", "scale": 1.0, "head": 1.0, "bulk": 1.0, "skin": 1,
		"desc": "Adaptable folk from every corner of the Skylands."},
	{"id": "vulpin", "name": "Vulpin", "scale": 0.95, "head": 1.06, "bulk": 0.94, "skin": 2,
		"desc": "Fox-eared and quick, with a big brush of a tail."},
	{"id": "stoneborn", "name": "Stoneborn", "scale": 1.17, "head": 0.86, "bulk": 1.3, "skin": 19,
		"desc": "Huge, slow-spoken folk of living rock, with crystals growing out of them."},
	{"id": "sprig", "name": "Sprig", "scale": 0.8, "head": 1.26, "bulk": 0.86, "skin": 11,
		"desc": "Tiny forest sprites with leaf wings and far too much nerve."},
	{"id": "scalefolk", "name": "Scalefolk", "scale": 1.06, "head": 0.96, "bulk": 1.02, "skin": 12,
		"desc": "Sun-loving lizardfolk with a crest and a long tail."},
	{"id": "owlet", "name": "Owlet", "scale": 0.92, "head": 1.18, "bulk": 1.06, "skin": 2,
		"desc": "Wide-eyed bird folk with ear tufts and a feather tail."},
]
const LOOK_RACES := ["Human", "Vulpin", "Stoneborn", "Sprig", "Scalefolk", "Owlet"]

static func default_look() -> Dictionary:
	return {"race": 0, "body": 1, "gender": 1, "face": 0, "skin": 1, "hair": 0, "hair_v": 2, "hair_col": 0, "detail": 0, "outfit": 3}

## A random look for bots and background hunters: any race, any style, the race's own colouring
## most of the time.
static func random_look(rng: RandomNumberGenerator = null) -> Dictionary:
	var R := func(n: int) -> int: return (rng.randi() if rng else randi()) % n
	var race := int(R.call(RACES.size()))
	var skin: int = int(RACES[race]["skin"]) if int(R.call(3)) > 0 else int(R.call(LOOK_SKIN.size()))
	if race == 0: skin = int(R.call(8))
	var gl := "classic" if int(R.call(5)) < 3 else String(Gliders.LIST[int(R.call(Gliders.LIST.size()))]["id"])
	return {"glider": gl, "race": race, "body": R.call(3), "gender": R.call(2), "face": R.call(LOOK_FACES.size()), "skin": skin,
		"hair": R.call(hair_styles(race).size()), "hair_v": 2, "hair_col": R.call(LOOK_HAIR.size()), "detail": R.call(LOOK_DETAILS.size()),
		"outfit": R.call(LOOK_OUTFITS.size())}

## A saved look with every value inside its list (older saves had a third gender option).
static func clean_look(lk: Dictionary) -> Dictionary:
	var out := default_look()
	out.merge(lk, true)
	var lists := {"race": LOOK_RACES, "body": LOOK_BODIES, "gender": LOOK_GENDERS, "face": LOOK_FACES, "skin": LOOK_SKIN, "hair_col": LOOK_HAIR, "detail": LOOK_DETAILS, "outfit": LOOK_OUTFITS}
	for k in lists:
		out[k] = clampi(int(out[k]), 0, (lists[k] as Array).size() - 1)
	var rid := String(RACES[int(out["race"])]["id"])
	if not lk.has("hair_v") and HAIR_FROM_OLD.has(rid):
		out["hair"] = HAIR_FROM_OLD[rid][clampi(int(out["hair"]), 0, LOOK_HAIRS.size() - 1)]
	out["hair_v"] = 2
	out["hair"] = clampi(int(out["hair"]), 0, hair_styles(int(out["race"])).size() - 1)
	return out

## How each class reads at a glance from the match camera, whatever the race or outfit (purely
## visual): overall size on top of the class scale (about 0.88 / 1.0 / 1.18 in all), build, boots,
## weapon size, and the class emblem on the pack (light: a chevron, medium: a diamond, heavy: a shield).
const CLASS_LOOK := {
	"light": {"size": 0.95, "build": 0.88, "boots": 0.9, "weapon": 0.86},
	"medium": {"size": 1.0, "build": 1.0, "boots": 1.0, "weapon": 1.05},
	"heavy": {"size": 1.035, "build": 1.12, "boots": 1.28, "weapon": 1.32},
}

## The class's own marks: its emblem on top of the pack in the class colour (seen from above), a
## trailing scarf for lights, a plated collar and back plate for heavies.
## The class colour, made vivid enough to read on a badge (its own material: hits flash per hunter).
static func class_mat(cls: String) -> ShaderMaterial:
	var cc: Color = Data.CLASSES.get(cls, {}).get("color", Color.WHITE)
	cc = Color.from_hsv(cc.h, maxf(cc.s, 0.6), maxf(cc.v, 0.95))
	var m := toon(cc, true, 0.35)
	m.set_shader_parameter("gloss", 0.5)
	return m

static func _class_marks(torso: Node3D, cls: String, bw: float, m_acc: Material, m_trim: Material) -> void:
	var m_cls := class_mat(cls)
	var at := Vector3(0, 0.655, 0.27 * bw)
	var tilt := Vector3(-1.05, 0, 0)          # lying back on the rolled wing, facing up and back
	match cls:
		"light":
			for sx in [-1.0, 1.0]:
				part(torso, box(0.035, 0.15, 0.025), m_cls, at + Vector3(0.045 * sx, 0.0, 0.0), Vector3.ONE, tilt + Vector3(0, 0, 0.6 * sx))
			# a long scarf trailing from the collar
			for sx in [-1.0, 1.0]:
				_blade(torso, m_acc, Vector3(0.06 * sx, 0.6, 0.18 * bw), Vector3(0.12 * sx, -0.45, 1.0), 0.48 - (sx + 1.0) * 0.05, 0.1, PI * 0.5, 0.18)
		"medium":
			part(torso, box(0.12, 0.12, 0.025), m_cls, at, Vector3.ONE, tilt + Vector3(0, 0, PI * 0.25))
		"heavy":
			part(torso, box(0.2, 0.16, 0.03), m_cls, at + Vector3(0, 0.01, 0.0), Vector3.ONE, tilt)
			part(torso, box(0.08, 0.06, 0.032), m_trim, at + Vector3(0, 0.012, 0.005), Vector3.ONE, tilt)
			# a plated collar and a back plate
			part(torso, cyl(0.25 * bw, 0.27 * bw, 0.09, 24), m_trim, Vector3(0, 0.6, 0.01))
			part(torso, box(0.42 * bw, 0.36, 0.06), m_trim, Vector3(0, 0.36, 0.25 * bw), Vector3.ONE, Vector3(-0.08, 0, 0))

## The hunter's chest and back as one smooth sculpted shape: narrow at the waist, full through the
## ribs, broad at the shoulders and rounded over into the neck. About 0.62 tall, centred.
static func torso_mesh() -> ArrayMesh:
	var key := "torso"
	if _lathes.has(key):
		return _lathes[key]
	var pts := PackedVector2Array([Vector2(0.0, -0.31), Vector2(0.13, -0.305), Vector2(0.2, -0.27), Vector2(0.218, -0.17), Vector2(0.205, -0.05),
		Vector2(0.212, 0.05), Vector2(0.236, 0.14), Vector2(0.248, 0.205), Vector2(0.236, 0.255), Vector2(0.19, 0.293), Vector2(0.11, 0.312), Vector2(0.0, 0.318)])
	var am := lathe(smooth_curve(pts, 3), 36)
	_lathes[key] = am
	return am

static func hunter(cls: String, team_col: Color, weapon: String, outfit := "", appearance := {}) -> Node3D:
	var lk: Dictionary = clean_look(appearance)
	var race: Dictionary = RACES[int(lk["race"])]
	var rid: String = race["id"]
	var root := Node3D.new()
	var headwear := outfit != "bare"     # "bare": the outfit's colours without its hat or hood (galleries)
	var oi: int = OUTFIT_KEYS.find(outfit) if not outfit in ["", "bare"] else int(lk["outfit"])
	if oi < 0: oi = 3
	var look: String = OUTFIT_KEYS[oi]
	var hero_col: Color = OUTFIT_COLS[oi]
	var hc := hero_col
	# outfit: a coat in the hero's colour, darker trousers and leather, team colour on the trim
	var coat_col := hero_col.lerp(Color("3a3f52"), 0.42).lerp(team_col, 0.12)
	var shirt_col := hero_col.lerp(Color("f3eee2"), 0.3).darkened(0.05)
	var pants_col := Color("3a3448").lerp(coat_col, 0.2)
	var mats: Array = []
	var m_body := toon(coat_col); mats.append(m_body)
	var m_shirt := toon(shirt_col); mats.append(m_shirt)
	var m_pants := toon(pants_col); mats.append(m_pants)
	var m_leather := toon(Color("5a3e2e")); mats.append(m_leather)
	var m_skin := toon(LOOK_SKIN[clampi(int(lk["skin"]), 0, LOOK_SKIN.size() - 1)]); mats.append(m_skin)
	var m_hair := toon(LOOK_HAIR[clampi(int(lk["hair_col"]), 0, LOOK_HAIR.size() - 1)]); mats.append(m_hair)
	var m_dark := toon(Color("2b2a33")); mats.append(m_dark)
	var m_acc := toon(team_col); mats.append(m_acc)
	var m_gold := shiny(Color("f2c84a"), 0.7); m_gold.set_shader_parameter("glow", 0.15); mats.append(m_gold)
	var m_gun := shiny(Color("4a4d5c"), 0.5); mats.append(m_gun)
	var m_hero := toon(hc); mats.append(m_hero)
	var m_trim := toon(hero_col.darkened(0.15)); mats.append(m_trim)
	for mm in [m_body, m_shirt, m_hair, m_acc, m_hero, m_trim]:
		(mm as ShaderMaterial).set_shader_parameter("rim_amount", 0.75)
	m_skin.set_shader_parameter("sss", 0.4)
	m_hair.set_shader_parameter("gloss", 0.3)
	m_leather.set_shader_parameter("gloss", 0.15)
	var rig := Node3D.new(); rig.name = "Rig"; root.add_child(rig)
	var legs := Node3D.new(); legs.name = "Legs"; rig.add_child(legs)
	var bw: float = [0.88, 1.0, 1.15][clampi(int(lk["body"]), 0, 2)]
	# the class shows in the build, whatever the race: lights lean, heavies broad with big boots
	bw *= float(CLASS_LOOK.get(cls, {}).get("build", 1.0))
	var boot_k := float(CLASS_LOOK.get(cls, {}).get("boots", 1.0))
	var gender := int(lk["gender"])
	# legs swing from the hip: thigh, knee pad, a tall boot with a cuff and a toe
	for sx in [-1.0, 1.0]:
		var leg := Node3D.new(); leg.name = "LegL" if sx < 0.0 else "LegR"
		leg.position = Vector3(0.11 * sx * bw, 0.44, 0)
		legs.add_child(leg)
		part(leg, limb(0.095 * bw, 0.07 * bw, 0.32, 0.1), m_pants, Vector3(0, -0.12, 0))
		part(leg, sphere(0.045, 8), m_acc, Vector3(0, -0.2, -0.07), Vector3(1.0, 1.0, 0.6))
		# the shin and boot hang from the knee, so legs can bend
		var knee := Node3D.new(); knee.name = "Knee"; knee.position = Vector3(0, -0.2, 0)
		leg.add_child(knee)
		part(knee, limb(0.074, 0.066, 0.24, 0.06), m_leather, Vector3(0, -0.11, 0))
		part(knee, cyl(0.092, 0.092, 0.05, 12), m_trim, Vector3(0, -0.01, 0))
		part(knee, sphere(0.085, 16), m_leather, Vector3(0, -0.205, -0.055), Vector3(0.95, 0.6, 1.5) * boot_k)
		part(knee, sphere(0.07, 14), m_leather, Vector3(0, -0.19, 0.0), Vector3(1.0, 0.75, 1.0) * boot_k)   # heel
		part(knee, box(0.135 * boot_k, 0.034, 0.24 * boot_k), m_dark, Vector3(0, -0.24, -0.05 * boot_k))
		if cls == "heavy":
			part(knee, cyl(0.098, 0.09, 0.12, 16), m_trim, Vector3(0, -0.13, 0))     # plated greaves
	var torso := Node3D.new(); torso.name = "Torso"; torso.position = Vector3(0, 0.42, 0); rig.add_child(torso)
	var fem := gender == 0
	# women: narrower shoulders and waist, wider hips, a bust; men: broader through the chest
	var chest_w := bw * (0.88 if fem else 1.07)
	# hips and a coat that flares a little below the belt
	part(torso, cyl(0.21 * bw, (0.22 if fem else 0.2) * bw, 0.14, 16), m_pants, Vector3(0, 0.02, 0))
	# the class shapes the clothes: light hunters wear a fitted jacket and a short cape, medium ones
	# the long field coat, heavy ones plate armour over a padded skirt
	match cls:
		"light":
			part(torso, cyl(0.215 * bw, 0.235 * bw, 0.16, 16), m_body, Vector3(0, 0.0, 0.01))
			part(torso, box(0.42 * bw, 0.5, 0.03), m_acc, Vector3(0, 0.3, 0.27 * bw), Vector3.ONE, Vector3(0.18, 0, 0))   # cape
			part(torso, cyl(0.19, 0.24, 0.12, 14), m_acc, Vector3(0, 0.6, 0.02))   # cowl
		"heavy":
			part(torso, cyl(0.245 * bw, 0.33 * bw, 0.26, 10), m_pants, Vector3(0, -0.05, 0.01))
			for k in 6:
				var a := TAU * k / 6.0 + PI / 6.0
				part(torso, box(0.17 * bw, 0.22, 0.04), m_trim, Vector3(sin(a) * 0.29 * bw, -0.07, cos(a) * 0.29 * bw), Vector3.ONE, Vector3(-0.22 * cos(a), a, 0.22 * sin(a)))   # tassets
			part(torso, box(0.36 * bw, 0.3, 0.08), m_trim, Vector3(0, 0.36, -0.24 * bw), Vector3.ONE, Vector3(0.08, 0, 0))   # breastplate
		_:
			part(torso, cyl((0.225 if fem else 0.235) * bw, (0.34 if fem else 0.29) * bw, 0.24, 16), m_body, Vector3(0, -0.04, 0.01))
	# chest: a sculpted torso (waist, ribcage, broad shoulders) under the open jacket
	part(torso, torso_mesh(), m_body, Vector3(0, 0.33, 0), Vector3(chest_w, 1.0, bw * 0.9))
	if fem:
		for sx in [-1.0, 1.0]:
			part(torso, sphere(0.1, 14), m_body, Vector3(0.078 * sx * chest_w, 0.405, -0.178 * bw), Vector3(1.0, 0.9, 0.9))
	# a V of shirt at the collar under the jacket's lapels, and a neckerchief in team colour
	part(torso, cyl(0.0, 0.1, 0.16, 3), m_shirt, Vector3(0, 0.52, -0.2 * bw), Vector3(1.0, 1.0, 0.35), Vector3(PI, 0, 0))
	for sx in [-1.0, 1.0]:
		part(torso, box(0.06, 0.3, 0.05), m_trim, Vector3(0.07 * sx * chest_w, 0.42, -0.215 * bw), Vector3.ONE, Vector3(-0.12, 0, 0.3 * sx))
	part(torso, cyl(0.0, 0.07, 0.12, 3), m_acc, Vector3(0, 0.54, -0.235 * bw), Vector3(1.0, 1.0, 0.4), Vector3(PI, 0, 0))
	part(torso, TorusMesh.new() if false else cyl(0.17, 0.2, 0.08, 16), m_trim, Vector3(0, 0.6, 0))   # collar
	part(torso, cyl(0.07 if fem else 0.085, 0.08 if fem else 0.1, 0.1, 10), m_skin, Vector3(0, 0.66, 0))   # neck
	# belt with a buckle and pouches, and a strap across the chest
	part(torso, cyl(0.245 * bw, 0.245 * bw, 0.07, 18), m_leather, Vector3(0, 0.1, 0))
	part(torso, box(0.08, 0.07, 0.03), m_gold, Vector3(0, 0.1, -0.245 * bw))
	for sx in [-1.0, 1.0]:
		part(torso, box(0.1, 0.11, 0.08), m_leather, Vector3(0.19 * sx * bw, 0.06, -0.1), Vector3.ONE, Vector3(0, 0.5 * sx, 0))
	part(torso, box(0.06, 0.62, 0.04), m_leather, Vector3(0.02, 0.36, -0.215 * bw), Vector3.ONE, Vector3(-0.1, 0, 0.62))
	# shoulder pads in team colour (big pauldrons on heavies)
	var pad_k := 1.45 if cls == "heavy" else (0.8 if cls == "light" else 1.0)
	for sx in [-1.0, 1.0]:
		var hm := SphereMesh.new(); hm.radius = 0.13 * pad_k; hm.height = 0.13 * pad_k; hm.is_hemisphere = true; hm.radial_segments = 30; hm.rings = 10
		part(torso, hm, m_acc, Vector3((0.24 + (pad_k - 1.0) * 0.06) * sx * chest_w, 0.52 + (pad_k - 1.0) * 0.04, 0.0), Vector3(1.0, 0.9, 1.1), Vector3(0, 0, -0.45 * sx))
		part(torso, cyl(0.135, 0.135, 0.025, 14), m_trim, Vector3(0.245 * sx * chest_w, 0.5, 0.0), Vector3.ONE, Vector3(0, 0, -0.45 * sx))
		# the class badge on top of each shoulder, seen from the match camera whichever way they face
		var top := Vector3((0.24 + (pad_k - 1.0) * 0.06) * sx * chest_w, 0.52 + (pad_k - 1.0) * 0.04, 0.0) + Vector3(0.13 * pad_k * 0.9 * sin(0.45 * sx) , 0.13 * pad_k * 0.9 * cos(0.45), 0)
		var badge: Vector3 = {"light": Vector3(0.05, 0.02, 0.17), "medium": Vector3(0.1, 0.02, 0.1), "heavy": Vector3(0.17, 0.024, 0.15)}.get(cls, Vector3(0.1, 0.02, 0.1))
		part(torso, box(badge.x, badge.y, badge.z), class_mat(cls), top, Vector3.ONE, Vector3(0, PI * 0.25 if cls == "medium" else 0.0, -0.45 * sx))
	_class_marks(torso, cls, bw, m_acc, m_trim)
	# the glider pack: a rolled wing on a back plate
	part(torso, box(0.3, 0.34, 0.1), m_leather, Vector3(0, 0.36, 0.24 * bw))
	part(torso, cyl(0.075, 0.075, 0.44, 12), toon(Color("f3eee2")), Vector3(0, 0.56, 0.27 * bw), Vector3.ONE, Vector3(0, 0, PI / 2))
	part(torso, cyl(0.08, 0.08, 0.06, 12), m_acc, Vector3(-0.2, 0.56, 0.27 * bw), Vector3.ONE, Vector3(0, 0, PI / 2))
	part(torso, cyl(0.08, 0.08, 0.06, 12), m_acc, Vector3(0.2, 0.56, 0.27 * bw), Vector3.ONE, Vector3(0, 0, PI / 2))
	# head: a slightly bigger head reads better from the top-down camera
	part(torso, sphere(0.235), m_skin, Vector3(0, 0.86, 0), Vector3(1.0, 0.98, 0.98), Vector3.ZERO, "Head")
	if rid == "human":
		for sx in [-1.0, 1.0]:
			part(torso, sphere(0.05, 8), m_skin, Vector3(0.225 * sx, 0.84, 0.01), Vector3(0.6, 1.0, 0.8))   # ears
	var skin_c: Color = LOOK_SKIN[int(lk["skin"])]
	var hair_c: Color = LOOK_HAIR[int(lk["hair_col"])]
	_face(torso, int(lk["face"]), gender, m_dark, m_skin, skin_c, int(lk["detail"]), hair_c, team_col)
	# a hood or helmet covers the hair; only what hangs below it shows. Stoneborn grow crystals and
	# Scalefolk a crest instead of hair.
	# hair (or what grows instead: fur, crystals, leaves, crests, feathers) goes on its own node,
	# which turns and scales with the head
	var hair_n := Node3D.new(); hair_n.name = "Hair"; torso.add_child(hair_n)
	var covered: bool = headwear and look in ["veil", "nyx", "bastion", "tusk", "halo"]
	if rid == "human":
		_hair(hair_n, int(lk["hair"]), gender, m_hair, covered)
	else:
		_race_hair(hair_n, rid, int(lk["hair"]), m_hair, hair_c, skin_c, covered)
	_race_parts(torso, rid, m_skin, m_hair, m_dark, skin_c, hair_c, hero_col)
	match look if headwear else "":
		"veil":
			part(torso, sphere(0.265), m_acc, Vector3(0, 0.92, 0.05), Vector3(1.0, 0.95, 1.05))  # hood
			part(torso, cyl(0.0, 0.08, 0.2, 8), m_acc, Vector3(0, 1.14, 0.18), Vector3.ONE, Vector3(0.9, 0, 0))
			part(torso, cyl(0.2, 0.26, 0.1), m_acc, Vector3(0, 0.62, 0))  # scarf
			part(torso, box(0.12, 0.4, 0.04), m_acc, Vector3(0.12, 0.46, 0.26), Vector3.ONE, Vector3(0.3, 0, 0.2))
			part(torso, box(0.1, 0.42, 0.03), m_acc, Vector3(-0.12, 0.4, 0.27), Vector3.ONE, Vector3(0.35, 0, -0.25))
		"nyx":
			part(torso, sphere(0.265), m_dark, Vector3(0, 0.92, 0.04), Vector3(1.0, 0.95, 1.05))
			part(torso, box(0.36, 0.07, 0.06), toon(hc, false, 1.0), Vector3(0, 0.88, -0.21))   # glowing visor
			for sx in [-1.0, 1.0]:
				part(torso, cyl(0.0, 0.05, 0.24), m_hero, Vector3(0.14 * sx, 1.16, 0.02), Vector3.ONE, Vector3(-0.2, 0, -0.5 * sx))
				part(torso, box(0.05, 0.28, 0.03), toon(Color("e8e0ff"), true, 0.3), Vector3(0.16 * sx, 0.12, 0.27), Vector3.ONE, Vector3(0.5, 0, 0.6 * sx))   # back daggers
			part(torso, box(0.5, 0.56, 0.04), m_dark, Vector3(0, 0.26, 0.3), Vector3.ONE, Vector3(0.25, 0, 0))  # cape
		"kestrel":
			part(torso, cyl(0.23, 0.25, 0.12), m_hero, Vector3(0, 1.02, 0))
			part(torso, box(0.4, 0.08, 0.1), toon(Color("2b2a33")), Vector3(0, 0.9, -0.18))
			part(torso, sphere(0.05, 8), toon(hc, false, 1.0), Vector3(0.09, 0.9, -0.23))
			part(torso, box(0.04, 0.34, 0.1), toon(Color("f3eee2")), Vector3(0.22, 1.12, 0.08), Vector3.ONE, Vector3(-0.4, 0, -0.4))  # feather
			part(torso, cyl(0.07, 0.07, 0.55, 10), toon(Color("7a5236")), Vector3(-0.14, 0.5, 0.3), Vector3.ONE, Vector3(0.2, 0, 0.3))   # quiver
		"sage":
			part(torso, cyl(0.36, 0.36, 0.04, 22), m_acc, Vector3(0, 1.02, 0))  # brim
			part(torso, cyl(0.18, 0.21, 0.2, 18), m_acc, Vector3(0, 1.12, 0))
			part(torso, cyl(0.215, 0.215, 0.045, 18), m_dark, Vector3(0, 1.05, 0))
			part(torso, box(0.03, 0.12, 0.05), toon(Color("9ee2a0")), Vector3(0.18, 1.1, 0.05), Vector3.ONE, Vector3(0, 0, -0.4))   # a leaf in the band
			part(torso, box(0.2, 0.18, 0.1), toon(Color("8a5a35")), Vector3(0.22, 0.12, 0.12), Vector3.ONE, Vector3(0, 0.5, 0))   # satchel
			part(torso, sphere(0.07, 8), toon(Color("9ee2a0"), false, 0.6), Vector3(0.24, 0.24, 0.14))
		"marlow":
			part(torso, sphere(0.245), m_hero, Vector3(0, 0.94, 0.02), Vector3(1.0, 0.6, 1.0))  # bandana
			part(torso, sphere(0.07, 8), m_hero, Vector3(0, 0.92, 0.25))
			part(torso, box(0.07, 0.22, 0.04), m_hero, Vector3(0.04, 0.8, 0.28), Vector3.ONE, Vector3(0.3, 0, 0.3))
			var t := TorusMesh.new(); t.inner_radius = 0.2; t.outer_radius = 0.26
			part(torso, t, toon(Color("8a8d99")), Vector3(0, 0.38, 0), Vector3.ONE, Vector3(0.9, 0, 0.5))  # chain
		"pyra":
			part(torso, sphere(0.21), toon(Color("ff7a3d")), Vector3(0, 1.02, 0.05), Vector3(1.15, 0.8, 1.15))  # hair
			for sx in [-1.0, 1.0]:
				part(torso, cyl(0.075, 0.075, 0.05, 12), toon(Color("9af0ff"), false, 0.7), Vector3(0.09 * sx, 1.01, -0.18), Vector3.ONE, Vector3(PI / 2, 0, 0))
				part(torso, cyl(0.08, 0.08, 0.42, 12), toon(Color("ff7a5a")), Vector3(0.1 * sx, 0.42, 0.32))   # fuel tanks
				part(torso, cyl(0.05, 0.03, 0.08, 10), toon(Color("ffd23f"), false, 0.9), Vector3(0.1 * sx, 0.18, 0.32))
			part(torso, box(0.38, 0.04, 0.04), m_dark, Vector3(0, 1.01, -0.16))
		"bastion":
			part(torso, sphere(0.28), m_acc, Vector3(0, 0.94, 0.02), Vector3(1.05, 0.85, 1.05))  # helmet
			part(torso, box(0.36, 0.07, 0.06), toon(Color("9af0ff"), false, 0.5), Vector3(0, 0.87, -0.22))  # visor
			part(torso, cyl(0.03, 0.03, 0.22, 8), m_gold, Vector3(0, 1.17, 0.02))
			for sx in [-1.0, 1.0]:
				part(torso, sphere(0.145), m_acc, Vector3(0.29 * sx, 0.54, 0), Vector3(1.15, 0.75, 1.15))
			part(torso, cyl(0.32, 0.32, 0.06, 22), m_trim, Vector3(0, 0.38, 0.34), Vector3.ONE, Vector3(PI / 2, 0, 0))   # shield on the back
			part(torso, cyl(0.13, 0.13, 0.07, 16), m_gold, Vector3(0, 0.38, 0.37), Vector3.ONE, Vector3(PI / 2, 0, 0))
		"tusk":
			part(torso, sphere(0.28), m_hero, Vector3(0, 0.94, 0.02), Vector3(1.05, 0.85, 1.05))
			for sx in [-1.0, 1.0]:
				part(torso, cyl(0.0, 0.06, 0.32), toon(Color("f3eee2")), Vector3(0.14 * sx, 0.77, -0.21), Vector3.ONE, Vector3(-1.2, 0, -0.3 * sx))
				part(torso, sphere(0.145), m_hero, Vector3(0.29 * sx, 0.54, 0), Vector3(1.15, 0.75, 1.15))
			part(torso, box(0.52, 0.1, 0.44), m_trim, Vector3(0, 0.05, 0))   # heavy belt
			part(torso, sphere(0.08, 8), toon(Color("f3eee2")), Vector3(0, 0.06, -0.23))
		"halo":
			part(torso, sphere(0.27), m_acc, Vector3(0, 0.94, 0.02), Vector3(1.0, 0.9, 1.0))
			part(torso, box(0.32, 0.12, 0.06), toon(Color("9af0ff"), false, 0.6), Vector3(0, 0.88, -0.22))
			var hr := TorusMesh.new(); hr.inner_radius = 0.17; hr.outer_radius = 0.22
			part(torso, hr, toon(hc, false, 1.3), Vector3(0, 1.3, 0), Vector3.ONE, Vector3.ZERO, "Halo")
			for sx in [-1.0, 1.0]:
				part(torso, sphere(0.145), m_acc, Vector3(0.29 * sx, 0.54, 0), Vector3(1.15, 0.75, 1.15))
			var gen := TorusMesh.new(); gen.inner_radius = 0.12; gen.outer_radius = 0.18
			part(torso, gen, toon(hero_col, false, 1.0), Vector3(0, 0.4, 0.34), Vector3.ONE, Vector3(PI / 2, 0, 0))   # dome generator
	# the arms and the gun move together from the shoulders ("Aim"), for recoil, reloads and poses
	var aim := Node3D.new(); aim.name = "Aim"; aim.position = Vector3(0, 0.5, 0.0); torso.add_child(aim)
	var gun := Node3D.new(); gun.name = "Gun"; gun.position = Vector3(0.22, -0.18, -0.18); aim.add_child(gun)
	# arms: sleeve, a cuff in the trim colour and a glove
	var arm_r := part(aim, limb(0.08, 0.063, 0.42, 0.07), m_body, Vector3(0.25, -0.02, -0.08), Vector3.ONE, Vector3(1.2, 0, 0.15), "ArmR")
	var arm_l := part(aim, limb(0.08, 0.063, 0.46, 0.07), m_body, Vector3(-0.11, -0.04, -0.16), Vector3.ONE, Vector3(1.25, 0, -0.7), "ArmL")
	for arm in [arm_r, arm_l]:
		part(arm, cyl(0.074, 0.08, 0.06, 12), m_trim, Vector3(0, -0.15, 0))
		# a gloved hand: a rounded palm and a thumb
		part(arm, sphere(0.07, 16), m_leather, Vector3(0, -0.235, 0), Vector3(0.95, 1.3, 0.85))
		part(arm, sphere(0.032, 12), m_leather, Vector3(0.0, -0.2, -0.055), Vector3(1.0, 1.4, 1.0))
	gun_parts(gun, weapon, m_gun, m_dark, m_acc)
	gun.scale = Vector3.ONE * float(CLASS_LOOK.get(cls, {}).get("weapon", 1.0))     # heavies carry big guns
	# a magazine that comes out and goes back in on a reload
	part(gun, box(0.06, 0.15, 0.09), m_acc, Vector3(0, -0.13, -0.24), Vector3.ONE, Vector3(0.15, 0, 0), "Mag")
	# the support arm swings from the shoulder, so it can reach for a fresh magazine
	var sh_l: Vector3 = arm_l.transform * Vector3(0, 0.21, 0)
	var arm_piv := Node3D.new(); arm_piv.name = "ArmLPivot"; arm_piv.position = sh_l; aim.add_child(arm_piv)
	aim.remove_child(arm_l); arm_piv.add_child(arm_l)
	arm_l.position -= sh_l
	var muzzle := Node3D.new(); muzzle.name = "Muzzle"; muzzle.position = Vector3(0, 0.02, -0.75); gun.add_child(muzzle)
	var shoulder := Node3D.new(); shoulder.name = "Shoulder"; shoulder.position = Vector3(-0.3, 0.8, 0.04); torso.add_child(shoulder)
	# a paraglider canopy that unfolds above the pack: an arched wing in stripes, with lines down to the harness
	var glider := Node3D.new(); glider.name = "Glider"; glider.position = Vector3(0, 0.62, 0.12); glider.visible = false
	torso.add_child(glider)
	var canopy := MeshInstance3D.new()
	var gskin := String(appearance.get("glider", "classic"))
	canopy.mesh = Gliders.mesh(gskin, team_col, hero_col)
	canopy.material_override = vtoon_outlined()
	canopy.position = Vector3(0, 1.05, 0.02)
	glider.add_child(canopy)
	glider.set_meta("skin", gskin)
	var gtrail := Gliders.trail(gskin, team_col, hero_col)
	if gtrail:
		gtrail.position = Vector3(0, 1.0, 0.3)
		glider.add_child(gtrail)
	var m_line := toon(Color("5a4636"), false)
	for sx in [-1.0, -0.4, 0.4, 1.0]:
		part(glider, cyl(0.008, 0.008, 1.0, 4), m_line, Vector3(0.42 * sx, 0.55, 0), Vector3.ONE, Vector3(0, 0, -0.62 * sx))
	var ring := MeshInstance3D.new(); ring.name = "TeamRing"; ring.mesh = flat_quad(1.0)
	ring.material_override = ring_mat(team_col, 0.16); ring.position = Vector3(0, 0.04, 0)
	root.add_child(ring)
	# the head and everything on it turn and nod together from the neck
	var head := Node3D.new(); head.name = "HeadPivot"; head.position = Vector3(0, 0.68, 0)
	torso.add_child(head)
	for ch in torso.get_children():
		if ch is MeshInstance3D and (String(ch.name).begins_with("@") or ch.name == "Head") and (ch as Node3D).position.y > 0.72:
			torso.remove_child(ch)
			head.add_child(ch)
			(ch as Node3D).position.y -= 0.68
	torso.remove_child(hair_n); head.add_child(hair_n)
	hair_n.position.y -= 0.68
	merge_static(torso)
	merge_static(head)
	merge_static(hair_n)
	for nm in ["LegL", "LegR"]:
		merge_static(legs.get_node(nm))
		merge_static(legs.get_node(nm + "/Knee"))
	# the race's proportions: head size, how broad the body is, overall height
	var hk := float(race["head"])
	var bk := float(race["bulk"])
	head.scale = Vector3.ONE * hk
	head.position.y += (hk - 1.0) * 0.08
	if bk != 1.0:
		for ch in torso.get_children():
			if ch is MeshInstance3D and not String(ch.name).begins_with("Tail") and ch.name != "Wings":
				(ch as Node3D).scale = Vector3(bk, 1.0 + (bk - 1.0) * 0.35, bk)
		aim.scale = Vector3(lerpf(1.0, bk, 0.75), 1.0, 1.0)
		shoulder.position.x *= bk
		legs.scale = Vector3(bk, 1.0, bk)
	root.set_meta("mats", collect_mats(root))
	root.set_meta("race", rid)
	var rs := float(race["scale"])
	var ck := float(CLASS_LOOK.get(cls, {}).get("size", 1.0))
	root.scale = Vector3.ONE * float(Data.CLASSES[cls]["scale"]) * rs * ck
	ring.scale = Vector3.ONE / (rs * ck)       # the ring under your feet shows the real hitbox, whatever your size
	return root

## A cone of radius r and length h growing from `at` along `dir` (spikes, fur tufts, horns).
static func _spike(n: Node3D, m: Material, at: Vector3, dir: Vector3, r: float, h: float, flat := 1.0) -> MeshInstance3D:
	var d := dir.normalized()
	var mi := part(n, cyl(0.0, r, h), m, at + d * h * 0.5)
	var b := Basis(Quaternion(Vector3.UP, d)) if absf(d.dot(Vector3.UP)) < 0.9999 else (Basis.IDENTITY if d.y > 0.0 else Basis(Vector3.RIGHT, PI))
	mi.basis = b * Basis.from_scale(Vector3(flat, 1.0, 1.0))
	return mi

## A soft blade (a feather, a leaf, a petal, a fin): an elongated, flattened ellipsoid from `at`
## along `dir`, `w` wide; `face` turns its flat side.
static func _blade(n: Node3D, m: Material, at: Vector3, dir: Vector3, ln: float, w: float, face := 0.0, thick := 0.24) -> MeshInstance3D:
	var d := dir.normalized()
	var mi := part(n, _blade_mesh(), m, at + d * ln * 0.5)
	var b := Basis(Quaternion(Vector3.UP, d)) if absf(d.dot(Vector3.UP)) < 0.9999 else (Basis.IDENTITY if d.y > 0.0 else Basis(Vector3.RIGHT, PI))
	mi.basis = b * Basis(Vector3.UP, face) * Basis.from_scale(Vector3(w, ln, w * thick))
	return mi

static var _blade_m: SphereMesh
## The unit ellipsoid every blade is stretched from (small on screen, so a modest segment count).
static func _blade_mesh() -> SphereMesh:
	if _blade_m == null:
		_blade_m = SphereMesh.new()
		_blade_m.radius = 0.5; _blade_m.height = 1.0; _blade_m.radial_segments = 16; _blade_m.rings = 10
	return _blade_m

## A point on the head (centre 0, 0.86, 0, radius about 0.235) in the direction (x, y, z).
static func _on_head(x: float, y: float, z: float, out := 0.0) -> Vector3:
	return Vector3(0, 0.86, 0) + Vector3(x, y, z).normalized() * (0.23 + out)

## Each race's own head styles (see HAIR_STYLES): fur for the Vulpin (parted round their ears),
## crystals, stone and moss for the Stoneborn, leaves and flowers for Sprigs, crests, frills, horns
## and spines for Scalefolk, feathers for Owlets. All in the hair colour.
static func _race_hair(n: Node3D, rid: String, style: int, m_hair: Material, hair_c: Color, skin_c: Color, covered: bool) -> void:
	var light := toon(hair_c.lightened(0.3)); (light as ShaderMaterial).set_shader_parameter("rim_amount", 0.75)
	var dark := toon(hair_c.darkened(0.25))
	match rid:
		"vulpin":
			var tip := toon(hair_c.lightened(0.55))
			if not covered:
				part(n, sphere(0.248), m_hair, Vector3(0, 0.905, 0.03), Vector3(1.04, 0.8 if style == 5 else 0.85, 1.02))
			match style:
				0:   # fluffy tuft: a curl of fur between the ears, cheek fluff
					for i in 3:
						var a := (i - 1) * 0.4
						_spike(n, m_hair, _on_head(sin(a) * 0.35, 0.9, -0.5), Vector3(sin(a) * 0.4, 0.6, -0.9), 0.065 - absf(i - 1) * 0.012, 0.2)
					for sx in [-1.0, 1.0]:
						_spike(n, m_hair, _on_head(0.9 * sx, -0.35, -0.2), Vector3(sx, -0.45, -0.1), 0.055, 0.15)
				1:   # mane: a ruff of fur round the back of the head and the neck
					for k in 9:
						var a := (k - 4) * 0.36
						var d := Vector3(sin(a), -0.35, cos(a))
						_spike(n, m_hair if k % 2 == 0 else light, Vector3(0, 0.8, 0.03) + Vector3(sin(a), 0, cos(a)) * 0.16, d, 0.085, 0.2)
					for i in 3:
						_spike(n, m_hair, _on_head((i - 1) * 0.3, 0.9, -0.45), Vector3((i - 1) * 0.3, 0.3, -1.0), 0.05, 0.13)
				2:   # long fur down the back, tips lighter
					part(n, capsule(0.17, 0.5), m_hair, Vector3(0, 0.71, 0.11), Vector3(1.3, 1.0, 0.65))
					for i in 3:
						_spike(n, tip, Vector3((i - 1) * 0.11, 0.5, 0.15), Vector3((i - 1) * 0.2, -1.0, 0.15), 0.07, 0.16)
				3:   # brush tail: a fat fox brush of a ponytail with a white tip
					for p in [[Vector3(0, 0.99, 0.2), 0.08], [Vector3(0, 0.92, 0.29), 0.1], [Vector3(0, 0.8, 0.34), 0.112], [Vector3(0, 0.68, 0.34), 0.095]]:
						part(n, sphere(float(p[1])), m_hair, p[0])
					part(n, sphere(0.075), tip, Vector3(0, 0.58, 0.31))
				4:   # spiky fur swept back over the crown
					for i in 6:
						var a := (i - 2.5) * 0.32
						_spike(n, m_hair, _on_head(sin(a) * 0.6, 0.75, 0.2 + absf(a) * 0.1), Vector3(sin(a) * 0.6, 0.5, 1.0), 0.06, 0.22)
				5:   # sleek: close fur with a flick at the back and cheek tufts
					_spike(n, m_hair, _on_head(0, 0.2, 1.0), Vector3(0, -0.6, 1.0), 0.07, 0.2)
					for sx in [-1.0, 1.0]:
						_spike(n, tip, _on_head(0.92 * sx, -0.3, -0.25), Vector3(sx, -0.3, 0), 0.05, 0.13)
				6:   # fringe: soft locks over the forehead
					for k in 4:
						part(n, sphere(0.075), m_hair, Vector3(-0.12 + k * 0.08, 0.99 - absf(k - 1.5) * 0.015, -0.17), Vector3(0.9, 1.0, 0.7), Vector3(0.4, 0, -0.3 + k * 0.2))
					for sx in [-1.0, 1.0]:
						_spike(n, m_hair, _on_head(0.85 * sx, -0.1, -0.35), Vector3(0.3 * sx, -1.0, -0.1), 0.055, 0.18)
		"stoneborn":
			var gem := toon(hair_c.lightened(0.15), false, 0.75); (gem as ShaderMaterial).set_shader_parameter("gloss", 0.8)
			var rock := toon(skin_c.darkened(0.28).lerp(hair_c, 0.25))
			match style:
				0:   # crystal crown
					for c in [[Vector3(0, 1.14, 0.03), Vector3(-0.2, 0, 0), 0.38], [Vector3(0.12, 1.07, 0.06), Vector3(-0.35, 0, -0.55), 0.28], [Vector3(-0.13, 1.06, 0.05), Vector3(-0.3, 0, 0.6), 0.26], [Vector3(0.0, 1.0, 0.18), Vector3(-0.9, 0, 0), 0.22]]:
						part(n, crystal(0.085, float(c[2]), 6), gem, c[0], Vector3.ONE, c[1])
				1:   # crystal ridge: a row of shards front to back
					for i in 5:
						var h := 0.34 - absf(i - 1.5) * 0.06
						part(n, crystal(0.06, h, 5), gem, _on_head(0, 1.0 - absf(i - 1.5) * 0.1, -0.45 + i * 0.3) + Vector3(0, h * 0.35, 0), Vector3.ONE, Vector3(-0.35 + i * 0.22, 0, 0))
				2:   # stone ridge: rounded plates with glowing seams
					for i in 4:
						var at := _on_head(0, 1.0, -0.5 + i * 0.4, 0.01)
						var pl := part(n, box(0.16 - absf(i - 1.5) * 0.02, 0.09, 0.12), rock, at, Vector3.ONE, Vector3(-0.5 + i * 0.35, 0, 0))
						pl.position += Vector3(0, 0.02, 0)
						if i < 3: part(n, box(0.12, 0.03, 0.02), gem, _on_head(0, 1.0, -0.3 + i * 0.4, 0.03), Vector3.ONE, Vector3(-0.3 + i * 0.35, 0, 0))
				3:   # moss cap with a little crystal sprouting from it
					if not covered:
						part(n, sphere(0.25), m_hair, Vector3(0, 0.93, 0.03), Vector3(1.03, 0.68, 1.03))
					var rng := RandomNumberGenerator.new(); rng.seed = 77
					for k in 9:
						var a := TAU * k / 9.0
						part(n, sphere(0.05), light if k % 2 == 0 else m_hair, _on_head(cos(a) * 0.8, 0.75 + rng.randf() * 0.3, sin(a) * 0.8, 0.0), Vector3(1.0, 0.6, 1.0))
					part(n, crystal(0.04, 0.16, 5), gem, Vector3(0.06, 1.13, 0.0), Vector3.ONE, Vector3(0, 0, -0.3))
				4:   # geode: a cluster of crystals bursting out of the back of the head
					for c in [[Vector3(0.0, 0.25, 1.0), 0.3, 0.075], [Vector3(0.45, 0.5, 0.8), 0.22, 0.06], [Vector3(-0.45, 0.45, 0.85), 0.24, 0.06], [Vector3(0.15, 0.85, 0.5), 0.2, 0.055], [Vector3(-0.2, 0.9, 0.35), 0.16, 0.05], [Vector3(0.0, -0.1, 1.0), 0.18, 0.05]]:
						var d: Vector3 = (c[0] as Vector3).normalized()
						var mi := part(n, crystal(float(c[2]), float(c[1]), 6), gem, _on_head(d.x, d.y, d.z, -0.02) + d * float(c[1]) * 0.4)
						mi.basis = Basis(Quaternion(Vector3.UP, d))
		"sprig":
			var gold := toon(Color("ffd84a"), true, 0.3)
			if not covered and style != 5:
				part(n, sphere(0.25), m_hair, Vector3(0, 0.9, 0.03), Vector3(1.03, 0.82, 1.0))
			match style:
				0:   # leaf crown
					for k in 7:
						var a := TAU * k / 7.0 + 0.2
						var d := Vector3(cos(a) * 0.55, 1.0, sin(a) * 0.55)
						_blade(n, m_hair if k % 2 == 0 else light, Vector3(cos(a) * 0.14, 1.03, sin(a) * 0.13 + 0.02), d, 0.24, 0.11, a)
				1:   # flower bud on top
					var c := Vector3(0, 1.13, 0.02)
					for k in 5:
						var a := TAU * k / 5.0
						_blade(n, light, c, Vector3(cos(a) * 0.8, 0.9, sin(a) * 0.8), 0.17, 0.12, a + PI * 0.5, 0.3)
					part(n, sphere(0.05), gold, c + Vector3(0, 0.03, 0))
					part(n, cyl(0.015, 0.02, 0.06, 8), dark, Vector3(0, 1.08, 0.02))
				2:   # vine locks, each ending in a leaf
					for k in 5:
						var a := PI * 0.5 + (k - 2) * 0.55
						var p := Vector3(cos(a) * 0.2, 0.86, sin(a) * 0.17 + 0.03)
						for j in 4:
							part(n, sphere(0.04 - j * 0.004), dark if j % 2 == 0 else m_hair, p + Vector3(cos(a) * j * 0.02, -j * 0.08, sin(a) * j * 0.02))
						_blade(n, light, p + Vector3(cos(a) * 0.08, -0.3, sin(a) * 0.08), Vector3(cos(a) * 0.3, -1.0, sin(a) * 0.3), 0.12, 0.07, a)
				3:   # a sprout: a stem and two leaves
					part(n, cyl(0.012, 0.016, 0.16, 8), dark, Vector3(0, 1.15, 0.0), Vector3.ONE, Vector3(0, 0, 0.1))
					for sx in [-1.0, 1.0]:
						_blade(n, light if sx > 0.0 else m_hair, Vector3(-0.008, 1.22, 0.0), Vector3(sx, 0.55, 0), 0.2, 0.1, PI * 0.5, 0.3)
				4:   # petal bob: petals hanging round the head like a bob cut
					for k in 9:
						var a := PI * 0.5 + (k - 4) * 0.42
						var d := Vector3(cos(a), 0, sin(a))
						_blade(n, m_hair if k % 2 == 0 else light, Vector3(0, 0.97, 0.02) + d * 0.2, d * 0.35 + Vector3(0, -1.0, 0), 0.24, 0.13, a + PI * 0.5, 0.3)
				5:   # a toadstool cap with spots
					part(n, sphere(0.3), m_hair, Vector3(0, 1.02, 0.02), Vector3(1.15, 0.55, 1.15))
					part(n, cyl(0.26, 0.3, 0.03), toon(Color("f3e6c8")), Vector3(0, 0.96, 0.02))
					var spot := toon(Color("fbf6ee"))
					for k in 6:
						var a := TAU * k / 6.0
						part(n, sphere(0.04), spot, Vector3(cos(a) * 0.2, 1.12, sin(a) * 0.2 + 0.02), Vector3(1.0, 0.45, 1.0))
					part(n, sphere(0.045), spot, Vector3(0, 1.185, 0.02), Vector3(1.0, 0.4, 1.0))
		"scalefolk":
			match style:
				0, 4:   # crest of fins front to back (twin: two of them, splayed), and frills
					for side in ([0.0] if style == 0 else [-1.0, 1.0]):
						for i in 5:
							var z := -0.1 + i * 0.075
							var h := 0.2 - absf(i - 1.5) * 0.025
							_blade(n, m_hair if i % 2 == 0 else light, Vector3(0.07 * side, 1.05 - i * 0.02, z), Vector3(0.3 * side, 1.0, 0.55 + i * 0.2), h + 0.04, 0.09, PI * 0.5, 0.3)
					for sx in [-1.0, 1.0]:
						_blade(n, dark, _on_head(0.9 * sx, 0.1, 0.25), Vector3(sx, 0.35, 0.4), 0.18, 0.1, 0.0, 0.25)
				1:   # frills: a fan of webbed spines round the back of the head
					for sx in [-1.0, 1.0]:
						for i in 4:
							var a := 0.15 + i * 0.32
							_blade(n, m_hair if i % 2 == 0 else light, _on_head(0.9 * sx, 0.1, 0.3), Vector3(sx * cos(a), sin(a) * 0.9 + 0.1, 0.5), 0.22 - i * 0.02, 0.12, 0.0, 0.2)
					_blade(n, dark, _on_head(0, 0.5, 0.9), Vector3(0, 0.4, 1.0), 0.2, 0.14, PI * 0.5, 0.2)
				2:   # horns swept back, and two small brow nubs
					for sx in [-1.0, 1.0]:
						var p := _on_head(0.45 * sx, 0.75, 0.15, -0.02)
						var d := Vector3(0.35 * sx, 0.6, 0.75)
						var r := 0.05
						for j in 4:
							var dd := d.normalized()
							if j == 3:
								_spike(n, light, p, dd, r, 0.13)
							else:
								KinModels.seg(n, p, p + dd * 0.11, r, r * 0.8, m_hair, 14)
								part(n, sphere(r * 0.8), m_hair, p + dd * 0.11)
							p += dd * 0.11
							r *= 0.8
							d = d.rotated(Vector3.RIGHT, 0.4)
						_spike(n, dark, _on_head(0.35 * sx, 0.55, -0.75), Vector3(0.2 * sx, 1.0, -0.2), 0.025, 0.06)
				3:   # spines: rows of little spikes over the crown and down the neck
					for row in 3:
						var x := (row - 1) * 0.35
						for i in 5:
							var at := _on_head(x, 1.0 - i * 0.35, -0.3 + i * 0.4, -0.01)
							_spike(n, m_hair if (row + i) % 2 == 0 else light, at, (at - Vector3(0, 0.86, 0)).normalized() + Vector3(0, 0, 0.5), 0.035 - absf(row - 1) * 0.008, 0.11 - absf(row - 1) * 0.03)
		"owlet":
			match style:
				0:   # ear tufts: a pair of feathers each side
					for sx in [-1.0, 1.0]:
						_blade(n, m_hair, Vector3(0.15 * sx, 1.04, 0.0), Vector3(0.6 * sx, 1.0, 0.1), 0.3, 0.1, 0.0, 0.25)
						_blade(n, light, Vector3(0.12 * sx, 1.04, 0.04), Vector3(0.35 * sx, 1.0, 0.2), 0.22, 0.08, 0.0, 0.25)
				1:   # feather crest fanning up from the brow
					for i in 5:
						var a := (i - 2) * 0.3
						_blade(n, m_hair if i % 2 == 0 else light, _on_head(sin(a) * 0.3, 0.9, -0.3), Vector3(sin(a) * 0.5, 1.0, 0.45), 0.28 - absf(i - 2) * 0.04, 0.085, PI * 0.5 + a, 0.25)
				2:   # plume: two tall curling feathers
					_blade(n, m_hair, Vector3(0, 1.06, 0.02), Vector3(0.05, 1.0, 0.35), 0.4, 0.1, PI * 0.5, 0.22)
					_blade(n, light, Vector3(0.02, 1.06, 0.0), Vector3(0.3, 1.0, 0.1), 0.3, 0.08, PI * 0.5, 0.22)
				3:   # fluffy crown: soft feathers all over the top
					if not covered:
						part(n, sphere(0.248), m_hair, Vector3(0, 0.91, 0.03), Vector3(1.03, 0.84, 1.02))
					for k in 10:
						var a := TAU * k / 10.0
						var at := _on_head(cos(a) * 0.55, 0.85, sin(a) * 0.55)
						_blade(n, light if k % 2 == 0 else m_hair, at, (at - Vector3(0, 0.86, 0)) + Vector3(0, 0.12, 0), 0.13, 0.08, a, 0.35)
				4:   # swept back: feathers laid back along the head
					if not covered:
						part(n, sphere(0.246), m_hair, Vector3(0, 0.9, 0.04), Vector3(1.02, 0.82, 1.02))
					for i in 5:
						var x := (i - 2) * 0.07
						_blade(n, light if i % 2 == 0 else m_hair, _on_head(x * 2.5, 0.85, -0.2), Vector3(x, 0.25, 1.0), 0.32, 0.075, PI * 0.5, 0.25)
				5:   # long plumes hanging down the back
					if not covered:
						part(n, sphere(0.246), m_hair, Vector3(0, 0.9, 0.04), Vector3(1.02, 0.82, 1.02))
					for i in 4:
						var x := (i - 1.5) * 0.08
						_blade(n, m_hair if i % 2 == 0 else light, _on_head(x * 2.0, 0.4, 0.9), Vector3(x, -1.0, 0.35), 0.44 - absf(i - 1.5) * 0.06, 0.08, PI * 0.5, 0.25)

## What each race adds: ears, tails, wings, snouts, crests, crystals.
static func _race_parts(torso: Node3D, rid: String, m_skin: Material, m_hair: Material, m_dark: Material, skin_c: Color, hair_c: Color, hero_col: Color) -> void:
	match rid:
		"vulpin":
			var inner := toon(Color("ffb6bf"))
			for sx in [-1.0, 1.0]:
				part(torso, cyl(0.0, 0.13, 0.38, 4), m_hair, Vector3(0.16 * sx, 1.13, 0.01), Vector3(1.0, 1.0, 0.55), Vector3(0, 0.785, -0.36 * sx))
				part(torso, cyl(0.0, 0.075, 0.24, 4), inner, Vector3(0.155 * sx, 1.1, -0.03), Vector3(1.0, 1.0, 0.3), Vector3(0, 0.785, -0.36 * sx))
			part(torso, sphere(0.1, 12), toon(skin_c.lightened(0.35)), Vector3(0, 0.79, -0.19), Vector3(1.15, 0.75, 0.9))   # muzzle
			part(torso, sphere(0.035, 8), m_dark, Vector3(0, 0.81, -0.285))   # nose
			# the tail: a big brush that sweeps up behind, with a white tip
			var tail := Node3D.new(); tail.name = "Tail"; tail.position = Vector3(0, 0.02, 0.26); torso.add_child(tail)
			var pts := [[Vector3(0, -0.02, 0.08), 0.1], [Vector3(0.06, 0.06, 0.26), 0.16], [Vector3(0.16, 0.18, 0.42), 0.19], [Vector3(0.26, 0.34, 0.5), 0.16]]
			for p in pts:
				part(tail, sphere(float(p[1]), 12), m_hair, p[0])
			part(tail, sphere(0.12, 10), toon(Color("fbf6ee")), Vector3(0.33, 0.47, 0.52))
		"stoneborn":
			var rock := toon(skin_c.darkened(0.28))
			var glow := toon(hero_col.lightened(0.2), false, 0.9)
			for sx in [-1.0, 1.0]:
				part(torso, box(0.16, 0.12, 0.18), rock, Vector3(0.25 * sx, 0.62, 0.03), Vector3.ONE, Vector3(0.1, 0.3 * sx, -0.25 * sx))     # rock plates on the shoulders
				part(torso, crystal(0.05, 0.2, 6), glow, Vector3(0.24 * sx, 0.74, 0.1), Vector3.ONE, Vector3(-0.3, 0, -0.45 * sx))   # shoulder crystals
			# glowing cracks across the chest
			part(torso, box(0.025, 0.2, 0.02), glow, Vector3(-0.05, 0.36, -0.235), Vector3.ONE, Vector3(0, 0, 0.5))
			part(torso, box(0.025, 0.14, 0.02), glow, Vector3(0.05, 0.27, -0.235), Vector3.ONE, Vector3(0, 0, -0.6))
			part(torso, box(0.18, 0.08, 0.18), rock, Vector3(0, 0.84, -0.17), Vector3.ONE, Vector3(0.2, 0, 0))   # heavy brow
		"sprig":
			var tipm := toon(hero_col.lightened(0.3), false, 1.0)
			for sx in [-1.0, 1.0]:
				# antennae with glowing tips, and long pointed ears
				part(torso, cyl(0.012, 0.014, 0.3, 6), m_dark, Vector3(0.08 * sx, 1.16, 0.0), Vector3.ONE, Vector3(-0.25, 0, -0.38 * sx))
				part(torso, sphere(0.045, 8), tipm, Vector3(0.14 * sx, 1.3, -0.04))
				part(torso, cyl(0.0, 0.055, 0.2, 4), m_skin, Vector3(0.28 * sx, 0.88, 0.0), Vector3(1.0, 1.0, 0.5), Vector3(0, 0, -1.25 * sx))
			# leaf wings on the back, see-through and faintly lit
			var wing_m := StandardMaterial3D.new()
			wing_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			wing_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			wing_m.albedo_color = Color(hero_col.lerp(Color("c8ffd8"), 0.5), 0.55)
			wing_m.cull_mode = BaseMaterial3D.CULL_DISABLED
			var wings := Node3D.new(); wings.name = "Wings"; wings.position = Vector3(0, 0.5, 0.3); torso.add_child(wings)
			for sx in [-1.0, 1.0]:
				var wmi := part(wings, sphere(0.26, 12), wing_m, Vector3(0.26 * sx, 0.1, 0.1), Vector3(0.8, 1.9, 0.06), Vector3(1.0, 0.35 * sx, 0.95 * sx))
				wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				var w2 := part(wings, sphere(0.18, 12), wing_m, Vector3(0.2 * sx, -0.16, 0.12), Vector3(0.75, 1.5, 0.06), Vector3(1.0, 0.25 * sx, 2.0 * sx))
				w2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		"scalefolk":
			part(torso, sphere(0.16, 14), m_skin, Vector3(0, 0.8, -0.19), Vector3(0.9, 0.72, 1.25))   # snout
			for sx in [-1.0, 1.0]:
				part(torso, sphere(0.02, 6), m_dark, Vector3(0.05 * sx, 0.84, -0.385))
			# a long tail that tapers down to the ground behind
			var tail := Node3D.new(); tail.name = "Tail"; tail.position = Vector3(0, 0.0, 0.24); torso.add_child(tail)
			var segs := [[Vector3(0, -0.04, 0.08), 0.11, 0.3], [Vector3(0, -0.16, 0.3), 0.085, 0.3], [Vector3(0, -0.3, 0.52), 0.06, 0.28], [Vector3(0, -0.38, 0.72), 0.035, 0.22]]
			for sg in segs:
				part(tail, capsule(float(sg[1]), float(sg[2]) + float(sg[1]) * 2.0), m_skin, sg[0], Vector3.ONE, Vector3(1.05, 0, 0))
		"owlet":
			part(torso, cyl(0.0, 0.05, 0.13, 4), toon(Color("f2a24a")), Vector3(0, 0.8, -0.26), Vector3(1.0, 1.0, 0.8), Vector3(-PI / 2 + 0.35, 0, 0))   # beak
			for sx in [-1.0, 1.0]:
				part(torso, sphere(0.11, 14), m_hair, Vector3(0.27 * sx, 0.3, 0.05), Vector3(0.3, 1.0, 0.15), Vector3(0.1, 0, -0.25 * sx))   # wing feathers at the sides
			var tail := Node3D.new(); tail.name = "Tail"; tail.position = Vector3(0, 0.0, 0.26); torso.add_child(tail)
			for i in 5:
				var a := (i - 2) * 0.32
				part(tail, sphere(0.12, 16), m_hair if i % 2 == 0 else toon(hair_c.lightened(0.25)), Vector3(sin(a) * 0.12, -0.1, 0.14), Vector3(0.4, 1.95, 0.11), Vector3(1.0, 0, a))

## A paraglider wing: arched across its span, rounded at the tips, striped in the given colours.
static func glider_mesh(cloth: Color, stripe: Color, edge: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 12
	var span := 1.05
	for side in [1.0, -1.0]:
		for k in segs:
			var x0 := -span + 2.0 * span * k / segs
			var x1 := -span + 2.0 * span * (k + 1) / segs
			var col: Color = stripe if k % 3 == 1 else (edge if k == 0 or k == segs - 1 else cloth)
			var pts := []
			for x in [x0, x1]:
				var u: float = absf(x) / span
				var y: float = -0.32 * u * u
				var chord: float = 0.42 * sqrt(maxf(0.0, 1.0 - pow(u, 3.0))) + 0.05
				pts.append(Vector3(x, y + side * 0.012, -chord * 0.55))
				pts.append(Vector3(x, y + side * 0.012, chord * 0.45))
			var n: Vector3 = Vector3.UP * side
			st.set_color(col)
			var order := [0, 2, 3, 0, 3, 1] if side > 0.0 else [0, 3, 2, 0, 1, 3]
			for i in order:
				st.set_normal(n)
				st.add_vertex(pts[i])
	return st.commit()

static func vtoon_outlined() -> ShaderMaterial:
	var m := vtoon()
	m.set_shader_parameter("rim_amount", 0.5)
	if _outline_mat == null:
		_outline_mat = ShaderMaterial.new()
		_outline_mat.shader = OUTLINE
	m.next_pass = _outline_mat
	return m

## Bakes a node's plain mesh parts into one mesh per look, so a detailed character costs a handful
## of draw calls. Named parts (Head, ArmR, Halo, ...) and anything with children stay separate.
static func merge_static(node: Node3D) -> void:
	var groups := {}
	var drop: Array = []
	for ch in node.get_children():
		if not (ch is MeshInstance3D) or ch.get_child_count() > 0 or not String(ch.name).begins_with("@"):
			continue
		var mi: MeshInstance3D = ch
		var mat: Material = mi.material_override
		if mat == null or mi.mesh == null:
			continue
		var key := _mat_key(mat)
		if not groups.has(key):
			groups[key] = {"mat": mat, "st": SurfaceTool.new(), "n": 0}
			(groups[key]["st"] as SurfaceTool).begin(Mesh.PRIMITIVE_TRIANGLES)
		var st: SurfaceTool = groups[key]["st"]
		for si in mi.mesh.get_surface_count():
			st.append_from(mi.mesh, si, mi.transform)
		groups[key]["n"] = int(groups[key]["n"]) + 1
		drop.append(mi)
	for key in groups:
		var g: Dictionary = groups[key]
		var mi := MeshInstance3D.new()
		mi.mesh = (g["st"] as SurfaceTool).commit()
		mi.material_override = g["mat"]
		node.add_child(mi)
	for d in drop:
		node.remove_child(d)
		d.free()

static func _mat_key(m: Material) -> String:
	if m is ShaderMaterial:
		var sm := m as ShaderMaterial
		return "%s|%s|%s|%s|%s|%s" % [sm.shader.resource_path, str(sm.get_shader_parameter("albedo")), str(sm.get_shader_parameter("glow")), str(sm.get_shader_parameter("rim_amount")), str(sm.next_pass != null), str(sm.get_shader_parameter("use_vertex_color"))]
	return str(m.get_instance_id())

## Every toon material in a model, for the hit flash.
static func collect_mats(n: Node) -> Array:
	var out: Array = []
	var stack: Array = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is MeshInstance3D and (c as MeshInstance3D).material_override is ShaderMaterial:
			var sm := (c as MeshInstance3D).material_override as ShaderMaterial
			if sm.shader == TOON and not out.has(sm):
				out.append(sm)
		for ch in c.get_children(): stack.append(ch)
	return out

static func m_trim0(c: Color) -> ShaderMaterial:
	return toon(c.darkened(0.55).lerp(Color("3a2f2a"), 0.5))

## Eyes, brows and a mouth: small shapes, but they carry a lot of character.
static func _face(torso: Node3D, face: int, gender: int, m_dark: Material, m_skin: Material, skin: Color, detail: int, hair_c: Color, paint: Color) -> void:
	var fem := gender == 0
	var shine := toon(Color.WHITE, false, 1.0)
	var white := toon(Color("fbf8f2"), false, 0.1)
	var iris := toon([Color("4a3a6a"), Color("3a5a8a"), Color("2a6a4a"), Color("6a3a2a"), Color("7a2a4a")][face % 5], false)
	iris.set_shader_parameter("gloss", 0.85); iris.set_shader_parameter("sss", 0.0)
	var y := 0.865
	var es := 1.14 if fem else 0.9          # bigger, rounder eyes for her; smaller, narrower for him
	var m_hairf := toon(hair_c.darkened(0.15), false)
	for sx in [-1.0, 1.0]:
		var ex: float = (0.086 if fem else 0.09) * sx
		var kind := face
		if face == 5:
			kind = 3 if sx > 0.0 else 0        # wink: one eye shut
		var open := kind in [0, 1, 4, 6, 7, 8]
		match kind:
			0, 4, 6, 7:   # bright eyes, fierce, starry, determined: white, iris, pupil and a shine
				part(torso, sphere(0.05 * es, 12), white, Vector3(ex, y, -0.2), Vector3(0.85, 1.15 if kind in [0, 6] else 0.9, 0.45))
				part(torso, sphere(0.036 * es, 10), iris, Vector3(ex + 0.004 * sx, y - 0.004, -0.218), Vector3(0.9, 1.1, 0.4))
				part(torso, sphere(0.019 * es, 8), m_dark, Vector3(ex + 0.004 * sx, y - 0.004, -0.226), Vector3(1.0, 1.1, 0.4))
				part(torso, sphere(0.012 * es, 6), shine, Vector3(ex + 0.016, y + 0.022, -0.232))
				if kind == 6:
					part(torso, sphere(0.02 * es, 6), shine, Vector3(ex - 0.01, y + 0.012, -0.233), Vector3(1.0, 1.0, 0.4))
					part(torso, sphere(0.008, 6), shine, Vector3(ex - 0.014, y - 0.022, -0.233))
				if kind == 7:
					part(torso, box(0.085 * es, 0.022, 0.02), m_skin, Vector3(ex, y + 0.034 * es, -0.228))   # heavy lid
			1:   # calm: soft dark eyes with a shine
				part(torso, sphere(0.034 * es, 10), m_dark, Vector3(ex, y, -0.215), Vector3(0.9, 1.1, 0.5))
				part(torso, sphere(0.01, 6), shine, Vector3(ex + 0.012, y + 0.014, -0.232))
			2:   # sleepy: half-closed lids
				part(torso, box(0.065 * es, 0.016, 0.02), m_dark, Vector3(ex, y - 0.006, -0.222), Vector3.ONE, Vector3(0, 0, 0.12 * sx))
			8:   # smug: half-lidded, looking sideways
				part(torso, sphere(0.04 * es, 10), white, Vector3(ex, y - 0.01, -0.205), Vector3(0.95, 0.6, 0.45))
				part(torso, sphere(0.022, 8), m_dark, Vector3(ex + 0.016, y - 0.014, -0.224), Vector3(1.0, 0.8, 0.4))
				part(torso, box(0.08 * es, 0.016, 0.02), m_dark, Vector3(ex, y + 0.008, -0.226))
			3:   # cheerful: eyes that smile
				var t := TorusMesh.new(); t.inner_radius = 0.024 * es; t.outer_radius = 0.036 * es; t.rings = 28; t.ring_segments = 10
				part(torso, t, m_dark, Vector3(ex, y - 0.01, -0.215), Vector3(1.0, 1.0, 0.5), Vector3(PI / 2, 0, 0))
				part(torso, box(0.08, 0.032, 0.03), m_skin, Vector3(ex, y - 0.032, -0.22))
		# brows: thin and arched for her, thick and straight for him; angled in when fierce
		var tilt: float = (-0.4 if kind == 4 else (-0.2 if kind == 7 else 0.15)) * sx
		if fem:
			part(torso, box(0.058, 0.011, 0.012), m_hairf, Vector3(ex + 0.006 * sx, y + 0.07, -0.21), Vector3.ONE, Vector3(0, 0, tilt + 0.18 * sx))
		else:
			part(torso, box(0.078, 0.024, 0.018), m_hairf, Vector3(ex, y + 0.062, -0.212), Vector3.ONE, Vector3(0, 0, tilt * 0.8))
		# lashes on her open eyes: two flicks at the outer corner
		if fem and open:
			part(torso, box(0.03, 0.011, 0.012), m_dark, Vector3(ex + 0.048 * sx, y + 0.032, -0.208), Vector3.ONE, Vector3(0, 0, 0.55 * sx))
			part(torso, box(0.022, 0.009, 0.012), m_dark, Vector3(ex + 0.05 * sx, y + 0.012, -0.208), Vector3.ONE, Vector3(0, 0, 0.15 * sx))
			part(torso, box(0.07 * es, 0.012, 0.012), m_dark, Vector3(ex, y + 0.046 * es, -0.222), Vector3.ONE, Vector3(0, 0, -0.08 * sx))
	# his jaw: wider and squarer at the bottom of the face, with a hint of a chin
	if not fem:
		var jaw := cyl(0.205, 0.13, 0.17, 2)   # a soft tapered jaw, a little wider than it is deep
		part(torso, jaw, m_skin, Vector3(0, 0.745, -0.035), Vector3(1.04, 1.0, 0.92))
		part(torso, box(0.1, 0.05, 0.05), m_skin, Vector3(0, 0.672, -0.115), Vector3.ONE, Vector3(-0.35, 0, 0))
	part(torso, sphere(0.016 if fem else 0.021, 6), m_skin, Vector3(0, 0.83, -0.236), Vector3(1.0, 0.8, 0.8))   # nose
	# mouth: rosy lips for her, a plain line or grin for him
	var mz := -0.236
	var smile := face in [0, 3, 5, 6]
	var lip_m: Material = toon(skin.lerp(Color("d0405a"), 0.55), false) if fem else m_dark
	if face == 8:
		part(torso, box(0.05, 0.012, 0.012), lip_m, Vector3(0.012, 0.79, mz), Vector3.ONE, Vector3(0, 0, 0.3))    # smirk
	elif smile:
		var sm := TorusMesh.new(); sm.inner_radius = 0.022; sm.outer_radius = 0.032 if fem else 0.03; sm.rings = 28; sm.ring_segments = 10
		part(torso, sm, lip_m, Vector3(0, 0.79, mz + 0.004), Vector3(1.0, 1.0, 0.4), Vector3(PI / 2, 0, PI))
	elif fem:
		part(torso, sphere(0.022, 8), lip_m, Vector3(0, 0.788, mz), Vector3(1.3, 0.55, 0.4))
	else:
		part(torso, box(0.05, 0.013, 0.012), m_dark, Vector3(0, 0.788, mz))
	if fem or face == 3:
		var blush := toon(Color("ff9a9a"), false)
		for sx in [-1.0, 1.0]:
			part(torso, sphere(0.03, 8), blush, Vector3(0.14 * sx, 0.815, -0.185), Vector3(1.0, 0.6, 0.4))
	# little extras
	match detail:
		1:   # freckles
			var fm := toon(skin.darkened(0.35), false)
			for sx in [-1.0, 1.0]:
				for k in 3:
					part(torso, sphere(0.007, 5), fm, Vector3(sx * (0.1 + k * 0.022), 0.83 + (k % 2) * 0.012, -0.212 + k * 0.006))
		2:   # a scar over one eye
			part(torso, box(0.012, 0.11, 0.012), toon(skin.lerp(Color("c86a6a"), 0.6), false), Vector3(0.1, 0.87, -0.228), Vector3.ONE, Vector3(0, 0, 0.25))
		3:   # face paint in the team colour
			var pm := toon(paint, false, 0.2)
			for sx in [-1.0, 1.0]:
				for k in 2:
					part(torso, box(0.055, 0.012, 0.012), pm, Vector3(sx * 0.12, 0.812 - k * 0.022, -0.2), Vector3.ONE, Vector3(0, 0.4 * sx, 0))
		4:   # stubble
			part(torso, sphere(0.205, 14), toon(skin.lerp(hair_c, 0.45).darkened(0.12), false), Vector3(0, 0.76, -0.025), Vector3(1.18 if not fem else 1.0, 0.6, 1.03))
		5:   # a full beard
			var bm := toon(hair_c)
			part(torso, sphere(0.21, 14), bm, Vector3(0, 0.75, -0.02), Vector3(1.2, 0.72, 1.05))
			part(torso, sphere(0.08, 10), bm, Vector3(0, 0.69, -0.17), Vector3(1.3, 1.1, 0.9))
			part(torso, box(0.06, 0.012, 0.012), m_dark, Vector3(0, 0.79, -0.25))
		6:   # moustache
			for sx in [-1.0, 1.0]:
				part(torso, capsule(0.018, 0.08), toon(hair_c), Vector3(0.03 * sx, 0.808, -0.236), Vector3.ONE, Vector3(0, 0, PI / 2 + 0.35 * sx))
		7:   # beauty mark
			part(torso, sphere(0.008, 5), m_dark, Vector3(0.055, 0.8, -0.23))

## Hair that peeks out under whatever the hero wears on their head: a cap of hair, chunky fringe
## locks over the forehead, then the style.
static func _hair(torso: Node3D, style: int, gender: int, m_hair: Material, covered := false) -> void:
	if style == 13:
		return   # bald
	if covered:
		# under a hood or helmet only what hangs below it shows
		if style not in [5, 9]:
			for sx in [-1.0, 1.0]:
				part(torso, cyl(0.0, 0.06, 0.2, 8), m_hair, Vector3(0.2 * sx, 0.84, -0.06), Vector3(1.0, 1.0, 0.8), Vector3(PI, 0, 0.15 * sx))
		match style:
			1: part(torso, capsule(0.17, 0.52), m_hair, Vector3(0, 0.7, 0.1), Vector3(1.35, 1.0, 0.7))
			7: _pigtails(torso, m_hair)
			8: _braid(torso, m_hair)
		return
	if style == 5 or style == 9:
		part(torso, sphere(0.242), m_hair, Vector3(0, 0.885, 0.02), Vector3(1.0, 0.82, 1.0))
		if style == 9:
			# mohawk: a crest of spikes front to back
			for i in 6:
				var z := -0.16 + i * 0.07
				part(torso, cyl(0.0, 0.05, 0.2 - absf(i - 2.5) * 0.02, 6), m_hair, Vector3(0, 1.08 - absf(i - 2.0) * 0.012, z), Vector3(0.6, 1.0, 1.2), Vector3(-0.3 + i * 0.12, 0, 0))
		return
	if style == 10:
		# afro: a big round cloud of hair
		part(torso, sphere(0.31, 16), m_hair, Vector3(0, 0.98, 0.08), Vector3(1.1, 0.95, 1.0))
		for k in 5:
			var x := -0.13 + k * 0.065
			part(torso, sphere(0.07, 10), m_hair, Vector3(x, 1.0 - absf(k - 2) * 0.012, -0.165), Vector3(1.0, 0.9, 0.7))
		return
	part(torso, sphere(0.25), m_hair, Vector3(0, 0.91, 0.035), Vector3(1.05, 0.86, 1.02))
	# fringe: soft locks sweeping across the forehead
	for k in 4:
		var x := -0.12 + k * 0.08
		part(torso, sphere(0.075, 10), m_hair, Vector3(x, 0.99 - absf(k - 1.5) * 0.015, -0.17), Vector3(0.9, 1.0, 0.7), Vector3(0.4, 0, -0.3 + k * 0.2))
	for sx in [-1.0, 1.0]:
		part(torso, cyl(0.0, 0.06, 0.2, 8), m_hair, Vector3(0.2 * sx, 0.84, -0.06), Vector3(1.0, 1.0, 0.8), Vector3(PI, 0, 0.15 * sx))   # sideburn locks
	match style:
		1:   # long
			part(torso, capsule(0.17, 0.52), m_hair, Vector3(0, 0.7, 0.1), Vector3(1.35, 1.0, 0.7))
			for sx in [-1.0, 1.0]:
				part(torso, cyl(0.0, 0.07, 0.26, 8), m_hair, Vector3(0.16 * sx, 0.5, 0.14), Vector3.ONE, Vector3(PI, 0, 0.1 * sx))
		2:   # ponytail with a tie
			part(torso, sphere(0.05, 8), toon(Color("e0607e")), Vector3(0, 0.95, 0.24))
			part(torso, capsule(0.075, 0.38), m_hair, Vector3(0, 0.82, 0.3), Vector3.ONE, Vector3(0.55, 0, 0))
			part(torso, cyl(0.0, 0.07, 0.16, 8), m_hair, Vector3(0, 0.62, 0.38), Vector3.ONE, Vector3(PI - 0.4, 0, 0))
		3:   # bun
			part(torso, sphere(0.11), m_hair, Vector3(0, 1.08, 0.16))
			part(torso, cyl(0.06, 0.06, 0.03, 10), toon(Color("f2c84a")), Vector3(0, 1.04, 0.13), Vector3.ONE, Vector3(-0.6, 0, 0))
		4:   # spiky
			for i in 7:
				var a := -1.2 + i * 0.4
				part(torso, cyl(0.0, 0.065, 0.22, 8), m_hair, Vector3(sin(a) * 0.14, 1.08, 0.05 + cos(a) * 0.06), Vector3.ONE, Vector3(-0.35, 0, -a * 0.75))
		6:   # bob: straight sides down to the jaw
			for sx in [-1.0, 1.0]:
				part(torso, sphere(0.13, 12), m_hair, Vector3(0.17 * sx, 0.82, 0.04), Vector3(0.6, 1.35, 1.2))
			part(torso, sphere(0.2, 12), m_hair, Vector3(0, 0.82, 0.12), Vector3(1.2, 1.1, 0.7))
		7:   # pigtails
			_pigtails(torso, m_hair)
		8:   # a long braid down the back
			_braid(torso, m_hair)
		11:  # curly: little curls all over
			for k in 14:
				var a := TAU * k / 14.0
				var yy := 0.95 + (k % 3) * 0.05
				part(torso, sphere(0.075, 8), m_hair, Vector3(cos(a) * 0.21, yy, sin(a) * 0.19 + 0.04))
			part(torso, sphere(0.09, 8), m_hair, Vector3(0, 1.12, 0.03))
		12:  # swoop: a big side-swept fringe
			part(torso, sphere(0.16, 12), m_hair, Vector3(0.06, 1.02, -0.13), Vector3(1.4, 0.7, 0.8), Vector3(0.3, 0, -0.35))
			part(torso, cyl(0.0, 0.06, 0.22, 8), m_hair, Vector3(0.2, 0.92, -0.13), Vector3.ONE, Vector3(0.2, 0, -2.2))
		_:   # short: a tuft on the crown
			part(torso, cyl(0.0, 0.05, 0.12, 8), m_hair, Vector3(0.03, 1.12, 0.02), Vector3.ONE, Vector3(-0.3, 0, -0.5))

static func _pigtails(torso: Node3D, m_hair: Material) -> void:
	for sx in [-1.0, 1.0]:
		part(torso, sphere(0.04, 8), toon(Color("e0607e")), Vector3(0.22 * sx, 0.93, 0.12))
		part(torso, capsule(0.07, 0.34), m_hair, Vector3(0.27 * sx, 0.78, 0.15), Vector3.ONE, Vector3(0.25, 0, 0.3 * sx))

static func _braid(torso: Node3D, m_hair: Material) -> void:
	for k in 5:
		part(torso, sphere(0.065 - k * 0.006, 8), m_hair, Vector3(0, 0.86 - k * 0.09, 0.27 + k * 0.01))
	part(torso, sphere(0.03, 6), toon(Color("e0607e")), Vector3(0, 0.44, 0.3))

static func prism_tip() -> PrismMesh:
	var pm := PrismMesh.new(); pm.size = Vector3(1, 1, 1)
	return pm

## The gun's pieces, shared by hunters and the weapons lying around on the islands.
static func gun_parts(gun: Node3D, weapon: String, m_gun: Material, m_dark: Material, m_acc: Material) -> void:
	match weapon:
		"smg":
			part(gun, box(0.1, 0.12, 0.42), m_gun, Vector3(0, 0, -0.12))
			part(gun, box(0.05, 0.16, 0.08), m_dark, Vector3(0, -0.12, -0.04))
			part(gun, box(0.06, 0.06, 0.12), m_acc, Vector3(0, 0.08, -0.12))
		"rifle":
			part(gun, box(0.09, 0.12, 0.7), m_gun, Vector3(0, 0, -0.24))
			part(gun, cyl(0.035, 0.035, 0.3), m_dark, Vector3(0, 0.02, -0.66), Vector3.ONE, Vector3(PI / 2, 0, 0))
			part(gun, box(0.05, 0.08, 0.16), m_acc, Vector3(0, 0.09, -0.16))
		"sniper":
			part(gun, box(0.08, 0.1, 0.9), m_gun, Vector3(0, 0, -0.32))
			part(gun, box(0.04, 0.04, 0.5), toon(Color("9af0ff"), false, 0.8), Vector3(0, 0.07, -0.42))
			part(gun, cyl(0.05, 0.05, 0.14), m_dark, Vector3(0, 0.1, -0.12), Vector3.ONE, Vector3(PI / 2, 0, 0))
		"pulse":
			part(gun, box(0.1, 0.13, 0.62), m_gun, Vector3(0, 0, -0.2))
			part(gun, cyl(0.06, 0.06, 0.2, 12), toon(Color("8ff0ff"), false, 0.9), Vector3(0, 0.0, -0.56), Vector3.ONE, Vector3(PI / 2, 0, 0))
			for k in 3:
				part(gun, box(0.12, 0.02, 0.04), toon(Color("8ff0ff"), false, 0.7), Vector3(0, 0.075, -0.06 - k * 0.1))
			part(gun, box(0.05, 0.16, 0.08), m_dark, Vector3(0, -0.12, -0.02))
		"rocket":
			part(gun, cyl(0.1, 0.1, 0.72), toon(Color("5a6a4a")), Vector3(0, 0.04, -0.22), Vector3.ONE, Vector3(PI / 2, 0, 0))
			part(gun, cyl(0.06, 0.12, 0.12), toon(Color("ff7a5a")), Vector3(0, 0.04, -0.6), Vector3.ONE, Vector3(PI / 2, 0, 0))
			part(gun, box(0.06, 0.16, 0.08), m_dark, Vector3(0, -0.12, -0.05))
		"burst_rifle":
			part(gun, box(0.08, 0.11, 0.34), m_gun, Vector3(0, 0, -0.1))
			part(gun, cyl(0.02, 0.02, 0.22, 6), toon(Color("d6a8ff"), false, 0.8), Vector3(0, 0.02, -0.36), Vector3.ONE, Vector3(PI / 2, 0, 0))
			part(gun, box(0.05, 0.15, 0.07), m_dark, Vector3(0, -0.11, -0.02))
		"shotgun":
			part(gun, box(0.12, 0.13, 0.62), m_gun, Vector3(0, 0, -0.2))
			for sx in [-0.035, 0.035]:
				part(gun, cyl(0.04, 0.04, 0.3, 8), m_dark, Vector3(sx, 0.03, -0.62), Vector3.ONE, Vector3(PI / 2, 0, 0))
			part(gun, box(0.07, 0.07, 0.16), m_acc, Vector3(0, -0.08, -0.36))
		"slugger":
			part(gun, cyl(0.1, 0.12, 0.78, 10), m_gun, Vector3(0, 0, -0.26), Vector3.ONE, Vector3(PI / 2, 0, 0))
			part(gun, cyl(0.15, 0.15, 0.1, 10), m_acc, Vector3(0, 0, -0.64), Vector3.ONE, Vector3(PI / 2, 0, 0))
			part(gun, box(0.08, 0.2, 0.12), m_dark, Vector3(0, -0.15, -0.02))
		"twin_blades":
			# two curved daggers, one held forward and one reversed
			var bl := toon(Color("c8f0ff"), true, 0.35)
			part(gun, box(0.04, 0.03, 0.42), bl, Vector3(0.06, 0, -0.26), Vector3.ONE, Vector3(0, 0.12, 0))
			part(gun, box(0.05, 0.06, 0.12), m_dark, Vector3(0.06, 0, -0.02))
			part(gun, box(0.04, 0.03, 0.34), bl, Vector3(-0.12, -0.06, 0.06), Vector3.ONE, Vector3(0, -0.3, 0))
			part(gun, box(0.05, 0.06, 0.1), m_dark, Vector3(-0.1, -0.06, -0.08))
		"longsword":
			part(gun, box(0.05, 0.12, 0.95), toon(Color("e9e4d4"), true, 0.2), Vector3(0, 0.02, -0.55))
			part(gun, box(0.26, 0.05, 0.06), m_acc, Vector3(0, 0, -0.06))
			part(gun, box(0.05, 0.06, 0.2), m_dark, Vector3(0, 0, 0.06))
		"greatsword":
			# a broad two-handed blade, longer than the hunter's arm span
			var steel := toon(Color("9aa6b8"), true, 0.1)
			part(gun, box(0.06, 0.16, 0.92), steel, Vector3(0, 0.02, -0.62))
			part(gun, prism_tip(), steel, Vector3(0, 0.02, -1.15), Vector3(0.06, 0.16, 0.16), Vector3(-PI / 2, 0, 0))
			part(gun, box(0.07, 0.04, 0.8), toon(Color("ffb070"), true, 0.5), Vector3(0, 0.02, -0.62))
			part(gun, box(0.38, 0.07, 0.08), m_acc, Vector3(0, 0, -0.12))
			part(gun, box(0.06, 0.07, 0.3), m_dark, Vector3(0, 0, 0.06))
		"minigun":
			# a spinning bundle of six barrels on a chunky drum
			part(gun, box(0.2, 0.2, 0.36), m_gun, Vector3(0, 0, -0.06))
			part(gun, cyl(0.13, 0.13, 0.12, 12), m_acc, Vector3(0, 0, -0.28), Vector3.ONE, Vector3(PI / 2, 0, 0))
			var spin := Node3D.new(); spin.name = "Barrels"; spin.position = Vector3(0, 0, -0.56); gun.add_child(spin)
			for k in 6:
				var a := TAU * k / 6.0
				part(spin, cyl(0.025, 0.025, 0.56, 6), m_dark, Vector3(cos(a) * 0.075, sin(a) * 0.075, 0), Vector3.ONE, Vector3(PI / 2, 0, 0))
			part(gun, box(0.08, 0.18, 0.14), m_dark, Vector3(0, -0.17, 0.0))
		"thumper":
			part(gun, cyl(0.12, 0.12, 0.62), m_gun, Vector3(0, 0, -0.2), Vector3.ONE, Vector3(PI / 2, 0, 0))
			part(gun, cyl(0.14, 0.14, 0.08), m_acc, Vector3(0, 0, -0.52), Vector3.ONE, Vector3(PI / 2, 0, 0))
			part(gun, box(0.08, 0.18, 0.12), m_dark, Vector3(0, -0.15, -0.02))

## A found weapon floating over the ground, with a light pillar in its rarity's colour.
static func weapon_drop(weapon: String, rar: int) -> Node3D:
	var root := Node3D.new()
	var col: Color = Data.RARITY[rar]["color"]
	var spin := Node3D.new(); spin.name = "Spin"; spin.position = Vector3(0, 0.7, 0); root.add_child(spin)
	var gun := Node3D.new(); gun.scale = Vector3.ONE * 2.3; gun.rotation.z = 0.25; spin.add_child(gun)
	gun_parts(gun, weapon, toon(Color("4a4d5c")), toon(Color("2b2a33")), toon(col, true, 0.5))
	var beam := part(root, cyl(0.14, 0.26, 5.0, 10), glow_mat(Color(col, 0.34)), Vector3(0, 2.5, 0))
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ring := MeshInstance3D.new(); ring.mesh = flat_quad(1.3)
	ring.material_override = ring_mat(col, 0.12); ring.position.y = 0.05
	root.add_child(ring)
	return root

## A piece of gear lying on the ground: a glowing gem-like token with a light beam.
static func gear_drop(col: Color, rar: int) -> Node3D:
	var root := Node3D.new()
	var rc: Color = Data.RARITY[clampi(rar, 0, Data.RARITY.size() - 1)]["color"]
	var spin := Node3D.new(); spin.name = "Spin"; spin.position = Vector3(0, 0.7, 0); root.add_child(spin)
	var core := PrismMesh.new(); core.size = Vector3(0.38, 0.38, 0.38)
	part(spin, core, toon(col, true, 0.6), Vector3(0, 0.1, 0))
	part(spin, core, toon(col, true, 0.6), Vector3(0, -0.12, 0), Vector3.ONE, Vector3(PI, 0, 0))
	var t := TorusMesh.new(); t.inner_radius = 0.28; t.outer_radius = 0.33
	part(spin, t, toon(rc, false, 0.8), Vector3.ZERO, Vector3.ONE, Vector3(PI / 2, 0, 0))
	var beam := part(root, cyl(0.12, 0.22, 4.0, 10), glow_mat(Color(col, 0.3)), Vector3(0, 2.0, 0))
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ring := MeshInstance3D.new(); ring.mesh = flat_quad(1.2)
	ring.material_override = ring_mat(rc, 0.12); ring.position.y = 0.05
	root.add_child(ring)
	return root

static func gear_pad(col: Color) -> Node3D:
	var root := Node3D.new()
	part(root, cyl(0.5, 0.58, 0.14, 18), toon(Color("3a3f52")), Vector3(0, 0.07, 0))
	var top := part(root, cyl(0.38, 0.38, 0.06, 18), toon(col, false, 1.0), Vector3(0, 0.16, 0), Vector3.ONE, Vector3.ZERO, "Top")
	top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root

static func gear_platform(col: Color) -> Node3D:
	var root := Node3D.new()
	part(root, cyl(1.6, 1.3, 0.24, 24), toon(Color("e8dcc0")), Vector3(0, -0.12, 0))
	part(root, cyl(1.62, 1.62, 0.06, 24), toon(col, false, 0.7), Vector3(0, 0.0, 0))
	var g := part(root, cyl(1.0, 0.2, 0.7, 18), glow_mat(Color(col, 0.35)), Vector3(0, -0.6, 0))
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root

static func gear_smoke() -> Node3D:
	var root := Node3D.new()
	var m := toon(Color(0.78, 0.78, 0.84), false)
	var rng := RandomNumberGenerator.new(); rng.randomize()
	for i in 14:
		var a := rng.randf() * TAU; var r := rng.randf_range(0.0, 3.0)
		var s := rng.randf_range(0.9, 1.6)
		var p := part(root, sphere(0.8), m, Vector3(cos(a) * r, rng.randf_range(0.4, 1.6), sin(a) * r), Vector3.ONE * s)
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root

## Things that break when shot or dashed through.
static func breakable(kind_s: String) -> Node3D:
	if kind_s == "crate":
		var pc := Assets.prop("dungeon/box_small", 0.78, false, {"bright": 1.1})
		if pc: return pc
	elif kind_s == "barrel":
		# the red powder keg: the barrel's wood painted red, its fuse still glowing on top
		var pb := Assets.prop("dungeon/barrel_small", 0.85, true, {"band": Assets.BAND_WOOD, "paint": Color("d8483a"), "bright": 1.1})
		if pb:
			var top := (pb.get_child(0) as MeshInstance3D).get_aabb().size.y * (pb.get_child(0) as MeshInstance3D).scale.y
			part(pb, sphere(0.09, 8), toon(Color("ffd25a"), false, 0.9), Vector3(0, top + 0.06, 0), Vector3.ONE, Vector3.ZERO, "Fuse")
			return pb
	var root := Node3D.new()
	match kind_s:
		"crate":
			var wood := toon(Color("a07448")); var dark := toon(Color("6a4a30"))
			part(root, box(0.7, 0.6, 0.7), wood, Vector3(0, 0.3, 0))
			for y in [0.06, 0.54]:
				part(root, box(0.74, 0.08, 0.74), dark, Vector3(0, y, 0))
			part(root, box(0.08, 0.6, 0.74), dark, Vector3(0, 0.3, 0), Vector3.ONE, Vector3(0, 0, 0.75))
		"pot":
			var clay := toon(Color("c9825a"))
			part(root, sphere(0.3, 14), clay, Vector3(0, 0.3, 0), Vector3(1, 1.05, 1))
			part(root, cyl(0.14, 0.18, 0.14, 12), clay, Vector3(0, 0.62, 0))
			part(root, cyl(0.31, 0.31, 0.05, 14), toon(Color("e8c07a")), Vector3(0, 0.36, 0))
		"barrel":
			var red := toon(Color("c8483a"), true, 0.15); var band := toon(Color("3a3440"))
			part(root, cyl(0.3, 0.3, 0.75, 14), red, Vector3(0, 0.375, 0))
			for y in [0.12, 0.62]:
				part(root, cyl(0.315, 0.315, 0.07, 14), band, Vector3(0, y, 0))
			part(root, sphere(0.09, 8), toon(Color("ffd25a"), false, 0.9), Vector3(0, 0.8, 0), Vector3.ONE, Vector3.ZERO, "Fuse")
	return root

# ---------------------------------------------------------------- kin
static var AURA: Shader = preload("res://shaders/kin_aura.gdshader")

static func aura_mat(c: Color, strength := 0.6) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = AURA
	m.set_shader_parameter("color", c)
	m.set_shader_parameter("strength", strength)
	return m

## The glow a hunter wears while a kin is fused onto them as armor.
static func kin_shell(c: Color) -> Node3D:
	var root := Node3D.new()
	var mi := part(root, capsule(0.62, 2.0), aura_mat(c, 0.75), Vector3(0, 1.0, 0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ring := part(root, flat_quad(2.6), ring_mat(Color(c, 0.9), 0.1), Vector3(0, 0.06, 0))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root

## A kin. Every species has its own body shape, tail, feet and ears (from its "look" in
## content/kin), a rim of light in its glow colour, a soft aura shell and a few drifting particles,
## so you can tell them apart at a glance and see them against busy ground.
static func kin(species: String, rec := {}) -> Node3D:
	var sp: Dictionary = Data.KIN[species]
	var look: Dictionary = sp.get("look", {})
	var glow_c: Color = sp.get("glow", sp["color"])
	var root := Node3D.new()
	var mats: Array = []
	var shimmer: bool = rec.get("shimmer", false)
	var ghost: bool = rec.get("ghost", false)       # brought back by the Soul Shrine: pale and glowing
	if ghost: glow_c = Color("9ff0e0")
	var m_body := toon(Care.ghost_col(sp["color"]) if ghost else (Care.shimmer_col(sp["color"]) if shimmer else sp["color"])); mats.append(m_body)
	m_body.set_shader_parameter("rim_color", glow_c)
	m_body.set_shader_parameter("rim_amount", 2.2 if ghost else 1.4)
	var m_belly := toon(Care.ghost_col(sp["belly"]) if ghost else (Care.shimmer_col(sp["belly"]) if shimmer else sp["belly"])); mats.append(m_belly)
	m_belly.set_shader_parameter("rim_color", glow_c)
	var m_dark := toon((sp["color"] as Color).darkened(0.3)); mats.append(m_dark)
	var m_glow := toon(glow_c, false, 0.7); mats.append(m_glow)
	var m_eye := toon(Color.WHITE, false); mats.append(m_eye)
	m_eye.set_shader_parameter("use_vertex_color", true)
	m_eye.set_shader_parameter("gloss", 0.9)
	m_eye.set_shader_parameter("sss", 0.0)
	m_eye.set_shader_parameter("rim_amount", 0.25)
	m_eye.set_meta("iris", glow_c.lerp(sp["color"], 0.35).darkened(0.08))
	var m_white := toon(Color.WHITE, false, 0.6)
	var m_blush := toon(Color("ff9aa8"), false, 0.2)
	# Body moves the kin around (hops, lunges, tumbles); Flex inside it squashes and stretches (KinPuppet)
	var body_root := Node3D.new(); body_root.name = "Body"; root.add_child(body_root)
	var body := Node3D.new(); body.name = "Flex"; body_root.add_child(body)
	var built := KinModels.build(species, body, {"body": m_body, "belly": m_belly, "dark": m_dark, "glow": m_glow, "eye": m_eye, "white": m_white,
		"wing_col": sp.get("wing", (sp["belly"] as Color).lerp(glow_c, 0.3))}, mats)
	if built.is_empty():
		var shape := String(look.get("body", "round"))
		var head_y := 0.44      # where the eyes sit
		var top_y := 0.68       # where ears sit
		var front_z := -0.28
		match shape:
			"drop":
				# a water drop: round below, tapering to a curl on top
				part(body, sphere(0.34), m_body, Vector3(0, 0.32, 0), Vector3(1.0, 0.88, 1.0))
				part(body, cyl(0.02, 0.24, 0.34), m_body, Vector3(0, 0.66, 0.04), Vector3.ONE, Vector3(0.25, 0, 0))
				part(body, sphere(0.05, 8), m_body, Vector3(0, 0.84, 0.12))
				part(body, sphere(0.24), m_belly, Vector3(0, 0.28, -0.14), Vector3(1.0, 0.95, 0.7))
				top_y = 0.6
			"burr":
				# a round burr of leaves with little thorns all over its back
				part(body, sphere(0.33), m_body, Vector3(0, 0.33, 0), Vector3(1.05, 0.95, 1.0))
				part(body, sphere(0.23), m_belly, Vector3(0, 0.29, -0.15), Vector3(1.0, 0.95, 0.7))
				for i in 9:
					var a := float(i) / 9.0 * TAU
					var up := 0.35 + 0.18 * float(i % 3)
					var dir := Vector3(cos(a) * 0.9, up, sin(a) * 0.9 + 0.35).normalized()
					if dir.z < -0.2: continue
					var sp_n := part(body, cyl(0.0, 0.05, 0.16, 6), m_dark, Vector3(0, 0.36, 0.02) + dir * 0.3)
					sp_n.basis = Basis(Quaternion(Vector3.UP, dir))
			"pear":
				# a pear: a wide bottom and a narrower head, always a little jittery
				part(body, sphere(0.33), m_body, Vector3(0, 0.3, 0), Vector3(1.05, 0.85, 1.0))
				part(body, sphere(0.25), m_body, Vector3(0, 0.56, -0.02))
				part(body, sphere(0.22), m_belly, Vector3(0, 0.26, -0.15), Vector3(1.0, 0.9, 0.7))
				head_y = 0.58; top_y = 0.78; front_z = -0.22
			"boulder":
				# a chunky rock: a wide body with stone plates on its back and a heavy brow
				part(body, sphere(0.36), m_body, Vector3(0, 0.33, 0), Vector3(1.18, 0.86, 1.08))
				part(body, sphere(0.24), m_belly, Vector3(0, 0.27, -0.17), Vector3(1.1, 0.9, 0.65))
				for i in 3:
					part(body, box(0.3 - i * 0.06, 0.08, 0.2), m_dark, Vector3(0, 0.6 - i * 0.12, 0.12 + i * 0.12), Vector3.ONE, Vector3(-0.5 - i * 0.3, 0, 0))
				part(body, box(0.4, 0.07, 0.12), m_dark, Vector3(0, 0.53, -0.26), Vector3.ONE, Vector3(0.35, 0, 0))
				head_y = 0.42
			"cloud":
				# a puff of cloud that floats, with no feet at all
				for pf in [[Vector3(0, 0.42, 0), 0.3], [Vector3(-0.2, 0.38, 0.08), 0.2], [Vector3(0.2, 0.38, 0.08), 0.2], [Vector3(0, 0.6, 0.06), 0.2], [Vector3(0, 0.34, 0.22), 0.18]]:
					part(body, sphere(pf[1]), m_body, pf[0])
				part(body, sphere(0.2), m_belly, Vector3(0, 0.38, -0.14), Vector3(1.0, 0.9, 0.6))
				head_y = 0.48; top_y = 0.72
			_:
				part(body, sphere(0.34), m_body, Vector3(0, 0.34, 0), Vector3(1.05, 0.92, 1.0))
				part(body, sphere(0.24), m_belly, Vector3(0, 0.3, -0.14), Vector3(1.0, 0.95, 0.7))
		# face: big eyes with a catch light, and rosy cheeks
		for sx in [-1.0, 1.0]:
			var sd := "L" if sx < 0.0 else "R"
			part(body, eye_mesh(0.068, m_eye.get_meta("iris")), m_eye, Vector3(0.12 * sx, head_y, front_z), Vector3(1, 1.15, 1), Vector3.ZERO, "Eye" + sd)
			part(body, sphere(0.024, 6), m_white, Vector3(0.12 * sx + 0.025, head_y + 0.035, front_z - 0.05), Vector3.ONE, Vector3.ZERO, "Shine" + sd)
			part(body, sphere(0.04, 6), m_blush, Vector3(0.2 * sx, head_y - 0.08, front_z + 0.05), Vector3(1, 0.5, 0.4))
		# feet
		match String(look.get("feet", "paws")):
			"stumps":
				for sx in [-1.0, 1.0]:
					for sz in [-1.0, 1.0]:
						part(body, cyl(0.08, 0.1, 0.14, 8), m_dark, Vector3(0.2 * sx, 0.06, 0.12 * sz))
			"none":
				body.position.y = 0.12
			_:
				for sx in [-1.0, 1.0]:
					part(body, sphere(0.08, 8), m_body, Vector3(0.2 * sx, 0.06, -0.08), Vector3(1, 0.6, 1.2))
		# tail, on its own pivot so it can wag
		var flex := body
		var tail_n := Node3D.new(); tail_n.name = "Tail"; flex.add_child(tail_n)
		body = tail_n
		match String(look.get("tail", "nub")):
			"flame":
				part(body, cyl(0.0, 0.11, 0.3, 8), m_glow, Vector3(0, 0.36, 0.38), Vector3.ONE, Vector3(-1.0, 0, 0))
				part(body, cyl(0.0, 0.06, 0.2, 8), toon(Color("fff0a0"), false, 0.9), Vector3(0, 0.42, 0.46), Vector3.ONE, Vector3(-0.8, 0, 0))
			"fish":
				part(body, box(0.02, 0.24, 0.22), m_belly, Vector3(0, 0.3, 0.42), Vector3.ONE, Vector3(0.3, 0, 0))
				part(body, sphere(0.09, 8), m_body, Vector3(0, 0.26, 0.32))
			"sprout":
				part(body, cyl(0.015, 0.02, 0.22, 6), toon(Color("5a8a3a")), Vector3(0, 0.4, 0.36), Vector3.ONE, Vector3(-0.6, 0, 0))
				part(body, sphere(0.08, 8), toon(Color("8fd16a")), Vector3(0, 0.5, 0.44), Vector3(1.4, 0.3, 0.8))
			"zig":
				for i in 3:
					part(body, box(0.05, 0.16, 0.05), m_glow, Vector3(0.05 * (1 if i % 2 == 0 else -1), 0.3 + i * 0.1, 0.34 + i * 0.05), Vector3.ONE, Vector3(-0.6, 0, 0.6 * (1 if i % 2 == 0 else -1)))
			"stub":
				part(body, sphere(0.09, 8), m_dark, Vector3(0, 0.22, 0.36))
			"wisp":
				for i in 3:
					part(body, sphere(0.07 - i * 0.015, 8), m_glow, Vector3(0, 0.36 + i * 0.05, 0.36 + i * 0.12), Vector3.ONE, Vector3.ZERO, "Wisp%d" % i)
			_:
				part(body, sphere(0.1, 8), m_body, Vector3(0, 0.26, 0.32))
		body = flex
		_repivot(tail_n, Vector3(0, 0.3, 0.3))
		var ears_n := Node3D.new(); ears_n.name = "Ears"; flex.add_child(ears_n)
		body = ears_n
		match String(sp["ears"]):
			"flame":
				var m_f := toon(Color("ffb347"), true, 0.5); mats.append(m_f)
				part(body, cyl(0.0, 0.12, 0.3), m_f, Vector3(0, top_y + 0.06, 0.02))
				part(body, cyl(0.0, 0.08, 0.22), m_f, Vector3(-0.13, top_y, 0.04), Vector3.ONE, Vector3(0, 0, 0.4))
				part(body, cyl(0.0, 0.08, 0.22), m_f, Vector3(0.13, top_y, 0.04), Vector3.ONE, Vector3(0, 0, -0.4))
			"fin":
				part(body, sphere(0.14), m_belly, Vector3(0, top_y - 0.02, 0.06), Vector3(0.35, 1.1, 1.3))
				part(body, sphere(0.1), m_body, Vector3(-0.3, 0.3, 0.05), Vector3(0.4, 0.8, 1.2))
				part(body, sphere(0.1), m_body, Vector3(0.3, 0.3, 0.05), Vector3(0.4, 0.8, 1.2))
			"leaf":
				var m_l := toon(Color("3e8f3a")); mats.append(m_l)
				part(body, sphere(0.14), m_l, Vector3(-0.14, top_y, 0), Vector3(0.5, 1.2, 0.25), Vector3(0, 0, 0.5))
				part(body, sphere(0.14), m_l, Vector3(0.14, top_y, 0), Vector3(0.5, 1.2, 0.25), Vector3(0, 0, -0.5))
			"bolt":
				var m_b := toon(Color("fff27a"), true, 0.4); mats.append(m_b)
				part(body, box(0.06, 0.26, 0.06), m_b, Vector3(-0.14, top_y + 0.04, 0), Vector3.ONE, Vector3(0, 0, 0.5))
				part(body, box(0.06, 0.26, 0.06), m_b, Vector3(0.14, top_y + 0.04, 0), Vector3.ONE, Vector3(0, 0, -0.5))
				part(body, box(0.05, 0.16, 0.05), m_b, Vector3(-0.22, top_y + 0.18, 0), Vector3.ONE, Vector3(0, 0, -0.4))
				part(body, box(0.05, 0.16, 0.05), m_b, Vector3(0.22, top_y + 0.18, 0), Vector3.ONE, Vector3(0, 0, 0.4))
			"horn":
				var m_h := toon(Color("e8e0cc")); mats.append(m_h)
				part(body, cyl(0.0, 0.07, 0.2), m_h, Vector3(-0.15, top_y - 0.02, -0.05), Vector3.ONE, Vector3(-0.2, 0, 0.35))
				part(body, cyl(0.0, 0.07, 0.2), m_h, Vector3(0.15, top_y - 0.02, -0.05), Vector3.ONE, Vector3(-0.2, 0, -0.35))
			"wisp":
				var m_w := toon(Color("efe8ff"), false, 0.8); mats.append(m_w)
				for i in 3:
					var a := float(i) / 3.0 * TAU
					part(body, sphere(0.06, 8), m_w, Vector3(cos(a) * 0.3, top_y + 0.04 + sin(a * 2.0) * 0.04, sin(a) * 0.3), Vector3.ONE, Vector3.ZERO, "Orb%d" % i)
		body = flex
		_repivot(ears_n, Vector3(0, top_y - 0.06, 0))
	# the aura shell: an outline of light in its glow colour, brightest at the silhouette
	var shell := part(body_root, sphere(0.4, 18), aura_mat(glow_c, 0.0), Vector3(0, 0.4, 0.02), Vector3(1.12, 1.15, 1.1), Vector3.ZERO, "Shell")
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shell.visible = false
	# a few particles that say what it is: embers, bubbles, leaves, sparks, grit, wind
	var pt := CPUParticles3D.new()
	pt.name = "Aura"
	pt.amount = 7
	pt.lifetime = 1.1
	pt.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	pt.emission_sphere_radius = 0.38
	pt.position = Vector3(0, 0.4, 0)
	pt.mesh = sphere(0.035, 4)
	pt.scale_amount_min = 0.6; pt.scale_amount_max = 1.4
	pt.color = glow_c
	pt.local_coords = false
	pt.direction = Vector3.UP
	pt.spread = 30.0
	pt.initial_velocity_min = 0.3; pt.initial_velocity_max = 0.8
	pt.gravity = Vector3(0, 0.6, 0)
	match String(look.get("aura", "")):
		"bubbles": pt.gravity = Vector3(0, 0.9, 0); pt.mesh = sphere(0.045, 6)
		"leaves": pt.gravity = Vector3(0, -0.5, 0); pt.initial_velocity_min = 0.5; pt.spread = 120.0; pt.mesh = box(0.07, 0.01, 0.04)
		"sparks": pt.gravity = Vector3.ZERO; pt.spread = 180.0; pt.initial_velocity_min = 0.8; pt.initial_velocity_max = 1.6; pt.lifetime = 0.5; pt.mesh = box(0.02, 0.09, 0.02)
		"pebbles": pt.gravity = Vector3(0, -2.0, 0); pt.mesh = box(0.05, 0.05, 0.05); pt.amount = 4
		"wind": pt.gravity = Vector3.ZERO; pt.spread = 180.0; pt.initial_velocity_min = 0.6; pt.initial_velocity_max = 1.0; pt.mesh = sphere(0.025, 4)
		"drips": pt.gravity = Vector3(0, -1.6, 0); pt.initial_velocity_min = 0.0; pt.initial_velocity_max = 0.2; pt.mesh = sphere(0.03, 6); pt.scale_amount_min = 0.8
		"prism":
			var pp := PrismMesh.new(); pp.size = Vector3(0.05, 0.08, 0.02)
			pt.mesh = pp; pt.gravity = Vector3(0, 0.3, 0); pt.spread = 180.0; pt.initial_velocity_min = 0.2; pt.initial_velocity_max = 0.5; pt.angular_velocity_min = -180.0; pt.angular_velocity_max = 180.0
		"spores": pt.gravity = Vector3(0, 0.15, 0); pt.spread = 180.0; pt.initial_velocity_min = 0.05; pt.initial_velocity_max = 0.25; pt.lifetime = 2.2; pt.mesh = sphere(0.022, 4); pt.amount = 10
		"rings":
			var tr := TorusMesh.new(); tr.inner_radius = 0.06; tr.outer_radius = 0.075; tr.rings = 12; tr.ring_segments = 3
			pt.mesh = tr; pt.gravity = Vector3.ZERO; pt.direction = Vector3(0, 0.4, -1); pt.spread = 25.0; pt.initial_velocity_min = 0.5; pt.initial_velocity_max = 0.8; pt.amount = 4
			pt.scale_amount_min = 1.0; pt.scale_amount_max = 2.6
		"moondust": pt.gravity = Vector3(0, -0.15, 0); pt.spread = 180.0; pt.initial_velocity_min = 0.05; pt.initial_velocity_max = 0.2; pt.lifetime = 1.8; pt.mesh = sphere(0.02, 4); pt.amount = 9
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.vertex_color_use_as_albedo = true
	pm.albedo_color = Color(1, 1, 1, 0.9)
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pt.material_override = pm
	pt.emitting = false
	root.add_child(pt)
	root.set_meta("mats", mats)
	Evo.dress(root, rec)
	if shimmer:
		# a shimmer sparkles a little, all the time
		for i in 3:
			var a := TAU * i / 3.0
			part(body, sphere(0.035, 6), toon(Color("fff6c0"), false, 1.6), Vector3(cos(a) * 0.42, 0.62 + i * 0.08, sin(a) * 0.42), Vector3.ONE, Vector3.ZERO, "Spark%d" % i)
	var acc: String = rec.get("acc", "")
	if acc != "" and Data.ACCS.has(acc):
		accessory(body, acc)
	root.add_child(KinPuppet.new())
	if int(rec.get("level", 1)) < 4 and (rec.get("forms", []) as Array).is_empty() and not rec.is_empty():
		# hatchlings are small
		root.set_meta("evo_scale", 0.82)
		root.scale = Vector3.ONE * 0.82
	return root

## Moves a group's pivot to `at` without moving what's in it.
static func _repivot(n: Node3D, at: Vector3) -> void:
	n.position = at
	for ch in n.get_children():
		(ch as Node3D).position -= at

## Something a kin wears, on its body at head height.
static func accessory(body: Node3D, id: String) -> void:
	var c: Color = Data.ACCS[id]["col"]
	var m := toon(c)
	match id:
		"bell":
			part(body, sphere(0.07, 10), toon(c, true, 0.4), Vector3(0, 0.2, -0.33))
			part(body, cyl(0.2, 0.2, 0.04, 16), toon(Color("d9604a")), Vector3(0, 0.25, -0.02), Vector3(1.05, 1, 1.05))
		"bow":
			for sx in [-1.0, 1.0]:
				part(body, sphere(0.09, 8), m, Vector3(0.1 * sx + 0.16, 0.66, -0.06), Vector3(1.2, 0.7, 0.5), Vector3(0, 0, 0.5 * sx))
			part(body, sphere(0.04, 6), m, Vector3(0.16, 0.66, -0.07))
		"leafhat":
			part(body, sphere(0.2, 10), m, Vector3(0, 0.66, 0), Vector3(1.3, 0.25, 1.3))
			part(body, cyl(0.01, 0.015, 0.14, 6), toon(Color("6b4a33")), Vector3(0, 0.76, 0))
		"scarf":
			part(body, cyl(0.29, 0.31, 0.09, 16), m, Vector3(0, 0.24, -0.02))
			part(body, box(0.09, 0.2, 0.04), m, Vector3(0.12, 0.13, -0.29), Vector3.ONE, Vector3(0.2, 0, 0.2))
		"crown":
			for i in 7:
				var a := TAU * i / 7.0
				part(body, sphere(0.05, 6), toon(Color("ffd0e8") if i % 2 == 0 else Color("fff27a"), false, 0.3), Vector3(cos(a) * 0.2, 0.68, sin(a) * 0.2))
		"goggles":
			part(body, cyl(0.3, 0.3, 0.05, 16), toon(Color("4e3424")), Vector3(0, 0.53, 0), Vector3(1.0, 1, 1.0), Vector3(0.25, 0, 0))
			for sx in [-1.0, 1.0]:
				part(body, cyl(0.07, 0.07, 0.05, 12), toon(Color("9af0ff"), false, 0.5), Vector3(0.11 * sx, 0.58, -0.27), Vector3.ONE, Vector3(PI / 2 + 0.25, 0, 0))
		"cape":
			part(body, box(0.42, 0.36, 0.03), m, Vector3(0, 0.3, 0.3), Vector3.ONE, Vector3(-0.35, 0, 0))
			part(body, cyl(0.2, 0.2, 0.04, 14), m, Vector3(0, 0.46, 0.05))
		"tophat":
			part(body, cyl(0.17, 0.17, 0.03, 14), m, Vector3(0, 0.68, 0))
			part(body, cyl(0.11, 0.11, 0.2, 14), m, Vector3(0, 0.79, 0))
			part(body, cyl(0.113, 0.113, 0.04, 14), toon(Color("d9604a")), Vector3(0, 0.72, 0))

## An air ring: fly through it for a burst of speed.
static func air_ring() -> Node3D:
	var root := Node3D.new()
	var t := TorusMesh.new(); t.inner_radius = 1.2; t.outer_radius = 1.42; t.rings = 28; t.ring_segments = 8
	var ring := part(root, t, toon(Color("5ad0f0"), true, 0.45), Vector3.ZERO, Vector3.ONE, Vector3(PI / 2, 0, 0), "Ring")
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var disc := part(root, cyl(1.2, 1.2, 0.02, 24), glow_mat(Color(0.55, 0.9, 1.0, 0.12)), Vector3.ZERO, Vector3.ONE, Vector3(PI / 2, 0, 0), "Disc")
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root

## A thought bubble over a kin's head with what it wants in it.
static func want_bubble() -> Node3D:
	var root := Node3D.new()
	var white := toon(Color("f6f2ea"), true)
	part(root, sphere(0.22, 14), white, Vector3(0, 0, 0), Vector3(1.15, 0.95, 0.5))
	part(root, sphere(0.06, 8), white, Vector3(-0.17, -0.24, 0))
	part(root, sphere(0.035, 6), white, Vector3(-0.25, -0.34, 0))
	var food := Node3D.new(); food.name = "food"; root.add_child(food)
	part(food, sphere(0.085, 10), toon(Color("ff6a4a"), false, 0.2), Vector3(0, -0.01, -0.1))
	part(food, sphere(0.04, 6), toon(Color("5aa84a"), false), Vector3(0.03, 0.08, -0.1), Vector3(1.4, 0.6, 0.6))
	var energy := Label3D.new(); energy.name = "energy"; energy.text = "z z"; energy.font = UI.big; energy.font_size = 36
	energy.pixel_size = 0.006; energy.modulate = Color("5a7ae0"); energy.outline_size = 0; energy.position = Vector3(0, 0, -0.12)
	energy.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(energy)
	var clean := Node3D.new(); clean.name = "clean"; root.add_child(clean)
	part(clean, sphere(0.07, 10), toon(Color("5ab8f0"), false, 0.4), Vector3(0, -0.03, -0.1), Vector3(1, 1.25, 1))
	part(clean, cyl(0.0, 0.05, 0.08, 8), toon(Color("5ab8f0"), false, 0.4), Vector3(0, 0.08, -0.1))
	var joy := Node3D.new(); joy.name = "joy"; root.add_child(joy)
	part(joy, sphere(0.08, 10), toon(Color("ff6a5a"), false, 0.2), Vector3(0, 0, -0.1))
	part(joy, cyl(0.081, 0.081, 0.025, 12), toon(Color("f6f2ea"), false), Vector3(0, 0, -0.1), Vector3.ONE, Vector3(0, 0, 0.5))
	return root

## The training yard: a straw dummy on a post, a mat and a couple of hoops.
static func training_yard() -> Node3D:
	var root := Node3D.new()
	var wood := toon(Color("8b6d52")); var straw := toon(Color("e2c47a")); var mat := toon(Color("c9604a"))
	part(root, cyl(0.07, 0.08, 1.3, 8), wood, Vector3(1.0, 0.65, -0.6))
	var dummy := Node3D.new(); dummy.name = "Dummy"; dummy.position = Vector3(1.0, 0.0, -0.6); root.add_child(dummy)
	part(dummy, sphere(0.28, 12), straw, Vector3(0, 0.95, 0), Vector3(1, 1.3, 1))
	part(dummy, sphere(0.16, 10), straw, Vector3(0, 1.45, 0))
	part(dummy, box(0.7, 0.08, 0.08), wood, Vector3(0, 1.1, 0))
	# a sparring mat painted like a target
	part(root, cyl(0.78, 0.8, 0.05, 24), toon(Color("e9dcc0")), Vector3(0, 0.025, 0))
	part(root, cyl(0.62, 0.62, 0.02, 24), mat, Vector3(0, 0.055, 0))
	part(root, cyl(0.44, 0.44, 0.02, 24), toon(Color("e9dcc0"), false), Vector3(0, 0.065, 0))
	part(root, cyl(0.22, 0.22, 0.02, 20), mat, Vector3(0, 0.075, 0))
	var ring_m := toon(Color("f2c84a"))
	for i in 2:
		var t := TorusMesh.new(); t.inner_radius = 0.26; t.outer_radius = 0.32
		part(root, t, ring_m, Vector3(-1.1 - i * 0.6, 0.34, 0.3 - i * 0.2), Vector3.ONE, Vector3(PI / 2, 0.3, 0))
		part(root, cyl(0.025, 0.025, 0.34, 6), wood, Vector3(-1.1 - i * 0.6, 0.0, 0.3 - i * 0.2))
	return root

## The Nesting Nook at home: a flower arbor over a big straw nest with two cushions, where two kin
## who are close can leave an egg. (The egg itself sits in the middle, from nest_egg().)
static func nesting_nook() -> Node3D:
	var root := Node3D.new()
	var wood := toon(Color("8a6a45")); var straw := toon(Color("d8b46a")); var straw_d := toon(Color("b08a48"))
	var pink := toon(Color("ff9ab8"), false, 0.15); var leaf := toon(Color("6aa64a"))
	# a stepping-stone floor
	for i in 7:
		var a := TAU * i / 7.0
		part(root, cyl(0.24, 0.26, 0.06, 8), toon(Color("cfc8bb")), Vector3(cos(a) * 1.45, 0.03, sin(a) * 1.45))
	# the nest: a thick ring of straw with a few loose stalks
	var t := TorusMesh.new(); t.inner_radius = 0.42; t.outer_radius = 0.82; t.rings = 18; t.ring_segments = 8
	part(root, t, straw, Vector3(0, 0.16, 0), Vector3(1.0, 0.7, 1.0))
	for i in 10:
		var a := TAU * i / 10.0 + 0.2
		part(root, box(0.03, 0.03, 0.4), straw_d, Vector3(cos(a) * 0.66, 0.3, sin(a) * 0.66), Vector3.ONE, Vector3(0.3, -a, 0.2))
	# two cushions for the pair, either side
	for sx in [-1.0, 1.0]:
		part(root, sphere(0.3, 14), toon(Color("f2c84a") if sx < 0 else Color("8ab4ff")), Vector3(1.2 * sx, 0.12, 0.55), Vector3(1.0, 0.35, 1.0))
	# the arbor: two posts and an arch of vine and flowers behind the nest
	for sx in [-1.0, 1.0]:
		part(root, cyl(0.06, 0.07, 1.9, 8), wood, Vector3(1.05 * sx, 0.95, -0.7))
	var arch := TorusMesh.new(); arch.inner_radius = 0.98; arch.outer_radius = 1.12; arch.rings = 24; arch.ring_segments = 6
	var ar := part(root, arch, leaf, Vector3(0, 1.9, -0.7), Vector3.ONE, Vector3(PI / 2, 0, 0))
	ar.scale = Vector3(1.0, 1.0, 0.75)
	for i in 11:
		var a := PI * i / 10.0
		part(root, sphere(0.09, 8), pink if i % 2 == 0 else toon(Color("fff3a8"), false, 0.15), Vector3(cos(a) * 1.05, 1.9 + sin(a) * 0.78, -0.7))
	# a heart sign hanging from the top of the arch
	var heart := Node3D.new(); heart.name = "Heart"; heart.position = Vector3(0, 2.25, -0.66); root.add_child(heart)
	part(heart, sphere(0.13, 12), toon(Color("ff5a7a"), false, 0.35), Vector3(-0.08, 0.04, 0))
	part(heart, sphere(0.13, 12), toon(Color("ff5a7a"), false, 0.35), Vector3(0.08, 0.04, 0))
	part(heart, cyl(0.0, 0.19, 0.24, 4), toon(Color("ff5a7a"), false, 0.35), Vector3(0, -0.1, 0), Vector3(1.0, 1.0, 0.45), Vector3(PI, PI / 4, 0))
	PropAnim.on(heart, 0.0, 0.05, 2.0)
	return root

## An egg in a straw nest, for kin you raise from an egg at home.
static func nest_egg(c: Color, spot: Color) -> Node3D:
	var root := Node3D.new()
	part(root, cyl(0.42, 0.34, 0.16, 16), toon(Color("c9a46a")), Vector3(0, 0.08, 0))
	var shell := Node3D.new(); shell.name = "Shell"; root.add_child(shell)
	part(shell, sphere(0.26, 16), toon(c.lightened(0.15)), Vector3(0, 0.36, 0), Vector3(0.92, 1.25, 0.92))
	var rng := RandomNumberGenerator.new(); rng.seed = int(c.r * 1000 + spot.g * 100)
	for i in 6:
		var a := rng.randf() * TAU; var y := rng.randf_range(0.2, 0.55)
		part(shell, sphere(0.05, 8), toon(spot), Vector3(cos(a) * 0.22, y, sin(a) * 0.22), Vector3(1, 1, 0.5))
	return root

# ---------------------------------------------------------------- monsters
static func mob(kind: String) -> Node3D:
	var md: Dictionary = Data.MOBS[kind]
	var pk := Assets.mob(kind, md["color"]) if Assets.on() else null
	if pk:
		if kind == "warden":
			# the boss: half again as big, a gold crown and a violet heart-gem
			pk.scale = Vector3.ONE * 1.5
			var gold := toon(Color("f2c84a"), true, 0.5)
			var crown := Node3D.new(); crown.position = Vector3(0, 1.78, 0); pk.get_node("Body").add_child(crown)
			for i in 5:
				var a := TAU * i / 5.0
				part(crown, cyl(0.0, 0.07, 0.24, 6), gold, Vector3(cos(a) * 0.2, 0.12, sin(a) * 0.2))
			part(crown, cyl(0.24, 0.24, 0.08, 14), gold, Vector3.ZERO)
			part(pk.get_node("Body"), sphere(0.11, 8), toon(Color("c9a0ff"), false, 1.2), Vector3(0, 1.15, -0.22))
			(pk.get_meta("mats") as Array).append(gold)
		return pk
	var root := Node3D.new()
	var mats: Array = []
	var m := toon(md["color"]); mats.append(m)
	var m_dark := toon(Color(md["color"]).darkened(0.5)); mats.append(m_dark)
	var m_eye := toon(Color("ffe25a"), false, 1.2); mats.append(m_eye)
	var body := Node3D.new(); body.name = "Body"; root.add_child(body)
	match kind:
		"skitter":
			# a scuttling beetle: domed shell with a seam, mandibles, six jointed legs on pivots
			part(body, sphere(0.36), m_dark, Vector3(0, 0.36, 0.02), Vector3(1.05, 0.62, 1.2))
			part(body, sphere(0.36), m, Vector3(0, 0.44, 0.06), Vector3(1.0, 0.62, 1.15))
			part(body, box(0.03, 0.05, 0.62), m_dark, Vector3(0, 0.66, 0.08), Vector3.ONE, Vector3(-0.08, 0, 0))
			part(body, sphere(0.2), m_dark, Vector3(0, 0.36, -0.36), Vector3(1.1, 0.8, 0.9))
			for sx in [-1.0, 1.0]:
				part(body, sphere(0.055, 6), m_eye, Vector3(0.1 * sx, 0.44, -0.5))
				var jaw := Node3D.new(); jaw.name = "Jaw" + ("L" if sx < 0 else "R"); jaw.position = Vector3(0.09 * sx, 0.3, -0.5); body.add_child(jaw)
				part(jaw, cyl(0.0, 0.035, 0.2, 5), m_dark, Vector3(0.02 * sx, 0, -0.08), Vector3.ONE, Vector3(-PI / 2, 0, -0.5 * sx))
				for i in 3:
					var lg := Node3D.new(); lg.name = "Leg%d%d" % [i, int(sx)]
					lg.position = Vector3(0.24 * sx, 0.3, -0.2 + i * 0.2); body.add_child(lg)
					part(lg, box(0.26, 0.05, 0.05), m_dark, Vector3(0.12 * sx, 0.03, 0), Vector3.ONE, Vector3(0, 0, 0.35 * sx))
					part(lg, box(0.05, 0.3, 0.05), m_dark, Vector3(0.25 * sx, -0.12, 0), Vector3.ONE, Vector3(0, 0, 0.2 * sx))
		"spitter":
			part(body, cyl(0.1, 0.16, 0.6), m_dark, Vector3(0, 0.3, 0))
			part(body, sphere(0.36), m, Vector3(0, 0.8, 0), Vector3(1.0, 0.9, 1.0), Vector3.ZERO, "Bulb")
			for i in 5:
				var a2 := TAU * i / 5.0
				part(body.get_node("Bulb"), sphere(0.16, 8), m_dark, Vector3(cos(a2) * 0.3, 0.12, sin(a2) * 0.3), Vector3(1.2, 0.3, 0.7), Vector3(0, -a2, 0.6))
			part(body, cyl(0.16, 0.2, 0.12), m_eye, Vector3(0, 0.8, -0.3), Vector3.ONE, Vector3(PI / 2, 0, 0))
			for i in 4:
				var a := float(i) / 4.0 * TAU + 0.4
				part(body, sphere(0.2), m, Vector3(cos(a) * 0.32, 0.08, sin(a) * 0.32), Vector3(1.4, 0.25, 0.7), Vector3(0, -a, 0))
		"bomber":
			var puff := Node3D.new(); puff.name = "Puff"; body.add_child(puff)
			part(puff, sphere(0.42, 16), m, Vector3(0, 0.5, 0))
			for i in 6:
				var a := TAU * i / 6.0
				part(puff, sphere(0.12, 8), m_dark, Vector3(cos(a) * 0.36, 0.5 + sin(a * 2.0) * 0.12, sin(a) * 0.36))
			part(puff, sphere(0.05, 6), m_eye, Vector3(-0.13, 0.6, -0.38))
			part(puff, sphere(0.05, 6), m_eye, Vector3(0.13, 0.6, -0.38))
			part(puff, cyl(0.03, 0.03, 0.22, 6), m_dark, Vector3(0, 0.98, 0))
			part(puff, sphere(0.07, 8), toon(Color("ffd25a"), false, 1.4), Vector3(0, 1.11, 0))
		"glimmer":
			var gold := toon(md["color"], true, 0.8); mats.append(gold)
			part(body, sphere(0.36, 16), gold, Vector3(0, 0.42, 0), Vector3(1, 0.9, 1.1))
			part(body, sphere(0.14, 10), gold, Vector3(-0.22, 0.76, 0.02), Vector3(0.6, 1.4, 0.6))
			part(body, sphere(0.14, 10), gold, Vector3(0.22, 0.76, 0.02), Vector3(0.6, 1.4, 0.6))
			part(body, sphere(0.05, 6), toon(Color("2b2a33")), Vector3(-0.11, 0.5, -0.32))
			part(body, sphere(0.05, 6), toon(Color("2b2a33")), Vector3(0.11, 0.5, -0.32))
			var pm := PrismMesh.new(); pm.size = Vector3(0.2, 0.24, 0.2)
			for i in 3:
				var a := TAU * i / 3.0
				part(body, pm, toon(Color("fff4c0"), false, 1.4), Vector3(cos(a) * 0.55, 0.9, sin(a) * 0.55))
		"sentinel":
			var stone := toon(Color("6a7080")); mats.append(stone)
			var plinth := Assets.prop("halloween/pillar", 0.95, true, {"bright": 1.15, "cache": false}) if Assets.on() else null
			if plinth:
				# a carved stone plinth (pack model) holding the crystal
				plinth.scale = Vector3(1.45, 1.0, 1.45)
				body.add_child(plinth)
				mats.append_array(plinth.get_meta("mats"))
			else:
				part(body, cyl(0.42, 0.55, 0.35, 8), stone, Vector3(0, 0.18, 0))
				part(body, cyl(0.22, 0.32, 0.6, 8), stone, Vector3(0, 0.6, 0))
			var cr := Node3D.new(); cr.name = "Crystal"; cr.position = Vector3(0, 1.25, 0); body.add_child(cr)
			var pm := PrismMesh.new(); pm.size = Vector3(0.42, 0.5, 0.42)
			var cm := toon(md["color"], false, 0.9); mats.append(cm)
			part(cr, pm, cm, Vector3(0, 0.25, 0))
			part(cr, pm, cm, Vector3(0, -0.25, 0), Vector3.ONE, Vector3(PI, 0, 0))
			part(cr, sphere(0.08, 8), m_eye, Vector3(0, 0, -0.2))
		"brute", "warden":
			# a hulking brute: barrel chest, hunched head with tusks, arms and legs on joints so it can swing
			var torso := Node3D.new(); torso.name = "Torso"; torso.position = Vector3(0, 0.62, 0); body.add_child(torso)
			part(torso, sphere(0.6, 14), m, Vector3(0, 0.38, 0), Vector3(1.05, 0.85, 0.85))
			part(torso, sphere(0.42, 12), toon(Color(md["color"]).lightened(0.25)), Vector3(0, 0.28, -0.22), Vector3(1.0, 0.85, 0.6))
			part(torso, sphere(0.34, 10), m_dark, Vector3(-0.48, 0.66, 0.0), Vector3(1.1, 0.8, 1.0))
			part(torso, sphere(0.34, 10), m_dark, Vector3(0.48, 0.66, 0.0), Vector3(1.1, 0.8, 1.0))
			var hd := Node3D.new(); hd.name = "Head"; hd.position = Vector3(0, 0.82, -0.28); torso.add_child(hd)
			part(hd, box(0.5, 0.38, 0.42), m_dark, Vector3(0, 0.05, 0))
			part(hd, box(0.56, 0.1, 0.2), m_dark, Vector3(0, 0.2, -0.16), Vector3.ONE, Vector3(0.25, 0, 0))
			part(hd, sphere(0.055, 6), m_eye, Vector3(-0.12, 0.1, -0.22))
			part(hd, sphere(0.055, 6), m_eye, Vector3(0.12, 0.1, -0.22))
			var tusk := toon(Color("efe6cf")); mats.append(tusk)
			part(hd, cyl(0.0, 0.05, 0.18, 6), tusk, Vector3(-0.15, -0.1, -0.22), Vector3.ONE, Vector3(-0.3, 0, 0.25))
			part(hd, cyl(0.0, 0.05, 0.18, 6), tusk, Vector3(0.15, -0.1, -0.22), Vector3.ONE, Vector3(-0.3, 0, -0.25))
			for sx in [-1.0, 1.0]:
				var arm := Node3D.new(); arm.name = "ArmL" if sx < 0 else "ArmR"
				arm.position = Vector3(0.62 * sx, 0.62, -0.02); torso.add_child(arm)
				part(arm, box(0.3, 0.62, 0.3), m_dark, Vector3(0.04 * sx, -0.3, 0))
				part(arm, sphere(0.24, 10), m, Vector3(0.05 * sx, -0.7, -0.02), Vector3(1.0, 0.9, 1.0))
				var leg := Node3D.new(); leg.name = "LegL" if sx < 0 else "LegR"
				leg.position = Vector3(0.26 * sx, 0.58, 0); body.add_child(leg)
				part(leg, box(0.3, 0.5, 0.34), m_dark, Vector3(0, -0.28, 0))
				part(leg, box(0.34, 0.12, 0.42), m_dark, Vector3(0, -0.52, -0.04))
			if kind == "warden":
				root.scale = Vector3.ONE * 1.5
				var gold := toon(Color("f2c84a"), true, 0.5); mats.append(gold)
				for sx in [-1.0, 0.0, 1.0]:
					part(hd, cyl(0.0, 0.08, 0.3, 6), gold, Vector3(0.15 * sx, 0.42, 0.02))
				part(hd, box(0.56, 0.08, 0.46), gold, Vector3(0, 0.28, 0.02))
				part(torso, sphere(0.12, 8), toon(Color("c9a0ff"), false, 1.2), Vector3(0, 0.4, -0.52))
	root.set_meta("mats", mats)
	return root

# ---------------------------------------------------------------- props
## A rough stone: a faceted lump, sometimes a smaller one beside it, often a cap of moss.
static func rock(rng: RandomNumberGenerator, s: float, moss := Color("6f9a4a")) -> Node3D:
	var root := Node3D.new()
	var g := Color("8d8a86").lerp(Color("6f6a73"), rng.randf())
	var m := toon(g, true)
	m.set_shader_parameter("rim_amount", 0.5)
	var sm := SphereMesh.new(); sm.radius = 0.5; sm.height = 1.0; sm.radial_segments = 7; sm.rings = 4
	var ys := s * rng.randf_range(0.8, 1.3)
	part(root, sm, m, Vector3(0, 0.42 * ys, 0), Vector3(s * rng.randf_range(0.9, 1.2), ys, s * rng.randf_range(0.9, 1.2)), Vector3(rng.randf_range(-0.2, 0.2), rng.randf() * TAU, rng.randf_range(-0.2, 0.2)))
	if rng.randf() < 0.6:
		part(root, sm, m, Vector3(rng.randf_range(-0.35, 0.35) * s, 0.2 * s, rng.randf_range(-0.35, 0.35) * s), Vector3.ONE * s * rng.randf_range(0.4, 0.6), Vector3(0, rng.randf() * TAU, 0))
	if rng.randf() < 0.65:
		var mm := SphereMesh.new(); mm.radius = 0.5; mm.height = 0.5; mm.radial_segments = 8; mm.rings = 3; mm.is_hemisphere = true
		part(root, mm, toon(moss.darkened(rng.randf_range(0.0, 0.2)), false), Vector3(0, 0.78 * ys, 0), Vector3(s * 0.8, ys * 0.35, s * 0.8))
	return root

## Trees in three styles: "round" (layered leafy canopy), "pine" (tiers of needles) and
## "blossom" (pale pink canopy). Leaf colour comes from the biome; each canopy has a darker
## underside and a lighter top so it reads as a volume from above.
static func tree(rng: RandomNumberGenerator, leaf: Color, style := "round") -> Node3D:
	var root := Node3D.new()
	var bark := Color("6b4a35").lerp(Color("4e3a30"), rng.randf())
	var mt := toon(bark)
	var h := rng.randf_range(1.7, 2.5)
	var lean := Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12))
	part(root, cyl(0.09, 0.16, h * 0.62), mt, Vector3(0, h * 0.31, 0), Vector3.ONE, lean)
	for k in 3:
		var a := TAU * k / 3.0 + rng.randf()
		part(root, cyl(0.02, 0.08, 0.36, 6), mt, Vector3(cos(a) * 0.14, 0.08, sin(a) * 0.14), Vector3.ONE, Vector3(sin(a) * 1.1, 0, -cos(a) * 1.1))
	var top := Vector3(lean.z * h * 0.6, h * 0.62, -lean.x * h * 0.6)
	match style:
		"pine":
			var c0 := leaf.lerp(Color("2f5a3a"), 0.45)
			var tiers := 4
			for k in tiers:
				var t := float(k) / tiers
				var r := lerpf(0.85, 0.28, t)
				var shade_c := c0.lerp(c0.lightened(0.25), t)
				part(root, cyl(0.0, r, 0.75, 9), toon(shade_c), top + Vector3(0, -0.15 + k * 0.42, 0), Vector3.ONE, Vector3(0, rng.randf() * TAU, 0))
			if leaf.v > 0.75:
				part(root, cyl(0.0, 0.22, 0.3, 9), toon(Color("f4f8ff")), top + Vector3(0, -0.15 + tiers * 0.42 - 0.05, 0))
		_:
			var base := leaf if style != "blossom" else Color("ffb3d0").lerp(leaf, 0.15)
			var dark := toon(base.lerp(Color("1f3a2a") if style != "blossom" else Color("c86a9a"), 0.35))
			var mid := toon(base)
			var light := toon(base.lightened(0.2).lerp(Color("fff6c0"), 0.08))
			for m2 in [dark, mid, light]:
				(m2 as ShaderMaterial).set_shader_parameter("rim_amount", 0.6)
			var blobs := rng.randi_range(4, 6)
			part(root, sphere(0.62, 12), dark, top + Vector3(0, 0.25, 0), Vector3(1.25, 0.8, 1.25))
			for k in blobs:
				var a := TAU * k / blobs + rng.randf_range(-0.3, 0.3)
				var rr := rng.randf_range(0.32, 0.46)
				part(root, sphere(rr, 10), mid, top + Vector3(cos(a) * 0.5, 0.42 + rng.randf_range(-0.1, 0.15), sin(a) * 0.5), Vector3.ONE)
			part(root, sphere(0.5, 12), light, top + Vector3(0.08, 0.78, -0.06), Vector3(1.0, 0.8, 1.0))
			if style == "blossom":
				for k in 6:
					part(root, sphere(0.06, 6), toon(Color("fff0f6"), false, 0.4), top + Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(0.5, 1.05), rng.randf_range(-0.6, 0.6)))
	return root

## Meshes for grass tufts and tall grass: a handful of tapered, slightly bent blades. UV.y runs
## from root (0) to tip (1) for the grass shader's colour and sway.
static var _grass_meshes := {}
static func grass_mesh(tall: bool) -> ArrayMesh:
	var key := "tall" if tall else "short"
	if _grass_meshes.has(key):
		return _grass_meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := RandomNumberGenerator.new(); r.seed = 77 if tall else 33
	var blades := 7 if tall else 5
	for b in blades:
		var a := r.randf() * TAU
		var dist := r.randf_range(0.0, 0.32 if tall else 0.12)
		var base := Vector3(cos(a) * dist, 0, sin(a) * dist)
		var hgt := r.randf_range(0.7, 1.05) if tall else r.randf_range(0.16, 0.3)
		var wid := r.randf_range(0.07, 0.1) if tall else r.randf_range(0.035, 0.05)
		var face := r.randf() * TAU
		var side := Vector3(cos(face), 0, sin(face))
		var bend := Vector3(-sin(face), 0, cos(face)) * hgt * r.randf_range(0.15, 0.4)
		var segs := 2 if tall else 1
		for k in segs:
			var t0 := float(k) / segs; var t1 := float(k + 1) / segs
			var w0 := wid * (1.0 - t0); var w1 := wid * (1.0 - t1)
			var p0 := base + Vector3(0, hgt * t0, 0) + bend * t0 * t0
			var p1 := base + Vector3(0, hgt * t1, 0) + bend * t1 * t1
			var v := [p0 - side * w0, p0 + side * w0, p1 + side * w1, p1 - side * w1]
			var uv := [Vector2(0, t0), Vector2(1, t0), Vector2(1, t1), Vector2(0, t1)]
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_normal(Vector3.UP)
				st.set_uv(uv[idx])
				st.add_vertex(v[idx])
	var m := st.commit()
	_grass_meshes[key] = m
	return m

## A tiny flower: three petals around a dot, on a short stem (coloured per instance).
static func flower_mesh() -> ArrayMesh:
	if _grass_meshes.has("flower"):
		return _grass_meshes["flower"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := 0.2
	for k in 5:
		var a := TAU * k / 5.0
		var c := Vector3(0, top, 0)
		var p1 := c + Vector3(cos(a - 0.45), 0.02, sin(a - 0.45)) * 0.07
		var p2 := c + Vector3(cos(a), 0.03, sin(a)) * 0.11
		var p3 := c + Vector3(cos(a + 0.45), 0.02, sin(a + 0.45)) * 0.07
		for v in [c, p1, p2, c, p2, p3]:
			st.set_normal(Vector3.UP); st.set_uv(Vector2(0.5, 1.0)); st.add_vertex(v)
	var m := st.commit()
	_grass_meshes["flower"] = m
	return m

static var GRASS: Shader = preload("res://shaders/grass.gdshader")
static func grass_material(sway: float, flower := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = GRASS
	m.set_shader_parameter("sway", sway)
	if flower:
		m.set_shader_parameter("tip_tint", Color(1.0, 1.0, 1.0))
	return m

const CHEST_COLS := [[Color("8a5a35"), Color("f2c84a")], [Color("3f6fb0"), Color("dfe8f2")], [Color("6a3fa8"), Color("f2c84a")]]

## A chest: the imported model (its lid on a hinge), coloured by tier, or the primitive one.
static func chest(tier := 0) -> Node3D:
	var pk := _pack_chest(tier)
	return pk if pk else chest_prim(tier)

const CHEST_WOOD := [null, Color("4f86c8"), Color("8a5ad0")]

static func _pack_chest(tier: int) -> Node3D:
	var id := "dungeon/chest_gold" if tier == 2 else "dungeon/chest"
	var base := Assets.part(id, "chest")
	var lidp := Assets.part(id, "chest_lid")
	if base.is_empty() or lidp.is_empty():
		return null
	var cfg := {"rim": 0.3, "bright": 1.12}
	if CHEST_WOOD[tier] != null:
		cfg["band"] = Assets.BAND_WOOD
		cfg["paint"] = CHEST_WOOD[tier]
	var m := Assets.material("dungeon", cfg)
	var root := Node3D.new()
	var body := Node3D.new(); body.name = "Body"; root.add_child(body)
	var sc := 0.52 * (1.0 + tier * 0.18)
	# the model's lock faces +z and its hinge is at the back (-z); turned round inside Body so the
	# hinge is at +z like the primitive chest, then Body faces the lock to the camera
	var turn := Node3D.new(); turn.rotation.y = PI; turn.scale = Vector3.ONE * sc; body.add_child(turn)
	part(turn, base[0], m, (base[1] as Transform3D).origin)
	var lid := Node3D.new(); lid.name = "Lid"
	lid.set_meta("hinged", true)
	var hinge: Vector3 = (lidp[1] as Transform3D).origin
	lid.position = Vector3(-hinge.x, hinge.y, -hinge.z) * sc
	lid.scale = Vector3.ONE * sc
	body.add_child(lid)
	part(lid, lidp[0], m, Vector3.ZERO, Vector3.ONE, Vector3(0, PI, 0))
	body.rotation.y = PI
	if tier >= 1:
		var cc: Array = CHEST_COLS[clampi(tier, 0, 2)]
		var beam := part(root, cyl(0.16, 0.3, 9.0, 10), glow_mat(Color(cc[1] if tier == 1 else Color("c9a0ff"), 0.22)), Vector3(0, 4.5, 0), Vector3.ONE, Vector3.ZERO, "Beacon")
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.set_meta("mats", [m, m])
	return root

## The chest built from primitives (also the base of a deathbox).
static func chest_prim(tier := 0) -> Node3D:
	var root := Node3D.new()
	var cc: Array = CHEST_COLS[clampi(tier, 0, 2)]
	var mw := toon(cc[0]); var mg := toon(cc[1], true, 0.3 + tier * 0.25)
	var m_seam := toon(Color(cc[0]).darkened(0.35), false)
	var body := Node3D.new(); body.name = "Body"; root.add_child(body)
	# the box: planks, metal corners and a lock plate
	part(body, box(0.8, 0.42, 0.55), mw, Vector3(0, 0.21, 0))
	for k in 2:
		part(body, box(0.81, 0.015, 0.56), m_seam, Vector3(0, 0.14 + k * 0.14, 0))
	for x in [-0.36, 0.36]:
		for z in [-0.25, 0.25]:
			part(body, box(0.1, 0.44, 0.1), mg, Vector3(x, 0.22, z))
	part(body, box(0.84, 0.05, 0.59), mg, Vector3(0, 0.03, 0))
	# the lid hinges at the back; a rounded top with two straps
	var lid := Node3D.new(); lid.name = "Lid"; lid.position = Vector3(0, 0.42, 0.27); body.add_child(lid)
	lid.set_meta("hinged", true)
	part(lid, cyl(0.28, 0.28, 0.8, 14), mw, Vector3(0, 0.0, -0.27), Vector3(0.6, 1.0, 1.0), Vector3(0, 0, PI / 2))
	for x in [-0.27, 0.27]:
		part(lid, cyl(0.29, 0.29, 0.07, 14), mg, Vector3(x, 0.0, -0.27), Vector3(0.6, 1.0, 1.0), Vector3(0, 0, PI / 2))
	part(lid, cyl(0.29, 0.29, 0.04, 14), mg, Vector3(-0.4, 0.0, -0.27), Vector3(0.6, 1.0, 1.0), Vector3(0, 0, PI / 2))
	part(lid, cyl(0.29, 0.29, 0.04, 14), mg, Vector3(0.4, 0.0, -0.27), Vector3(0.6, 1.0, 1.0), Vector3(0, 0, PI / 2))
	part(body, box(0.16, 0.2, 0.05), mg, Vector3(0, 0.4, -0.29))
	part(body, sphere(0.035, 6), toon(Color("2b2a33"), false), Vector3(0, 0.38, -0.32))
	body.scale = Vector3.ONE * (1.0 + tier * 0.18)
	body.rotation.y = PI   # lock facing the camera
	if tier >= 1:
		# a light pillar you can see from other islands
		var beam := part(root, cyl(0.16, 0.3, 9.0, 10), glow_mat(Color(cc[1] if tier == 1 else Color("c9a0ff"), 0.22)), Vector3(0, 4.5, 0), Vector3.ONE, Vector3.ZERO, "Beacon")
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.set_meta("mats", [mw, mg])
	return root

## A dead hunter's deathbox: a squat crate with a glow in its value colour.
static func deathbox(col: Color) -> Node3D:
	var root := chest_prim(0)
	var g := Node3D.new(); g.name = "Glow"; root.add_child(g)
	var beam := part(g, cyl(0.12, 0.24, 5.0, 10), glow_mat(Color(col, 0.3)), Vector3(0, 2.5, 0))
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ring := MeshInstance3D.new(); ring.mesh = flat_quad(1.6)
	ring.material_override = ring_mat(col, 0.1); ring.position.y = 0.04
	g.add_child(ring)
	# the soul: a little wisp bobbing over the box while a teammate can still bring them back
	var soul := Node3D.new(); soul.name = "Soul"; soul.position = Vector3(0, 1.3, 0); root.add_child(soul)
	part(soul, sphere(0.16, 10), glow_mat(Color(0.85, 1.0, 0.95, 0.9)), Vector3.ZERO)
	part(soul, sphere(0.28, 10), glow_mat(Color(0.6, 1.0, 0.85, 0.25)), Vector3.ZERO)
	PropAnim.on(soul, 1.4, 0.12)
	((root.get_meta("mats") as Array)[0] as ShaderMaterial).set_shader_parameter("albedo", Color("5a5560"))
	((root.get_meta("mats") as Array)[1] as ShaderMaterial).set_shader_parameter("albedo", col.darkened(0.2))
	return root

## A revive beacon: a stone pylon with a green crystal. Stand on it with a dead teammate waiting
## and it brings them back.
static func revive_beacon() -> Node3D:
	var root := Node3D.new()
	var stone := toon(Color("8f9aa0"))
	var glow := Color("8fffc0")
	part(root, cyl(1.2, 1.3, 0.16, 8), stone, Vector3(0, 0.08, 0))
	part(root, cyl(0.9, 0.96, 0.12, 8), toon(Color("b8c2c6")), Vector3(0, 0.22, 0))
	for i in 4:
		var a := TAU * i / 4.0 + 0.4
		part(root, box(0.22, 1.5, 0.22), stone, Vector3(cos(a) * 1.0, 0.75, sin(a) * 1.0), Vector3.ONE, Vector3(0, -a, 0))
		part(root, box(0.05, 0.9, 0.02), toon(glow, false, 0.9), Vector3(cos(a) * 0.88, 0.85, sin(a) * 0.88), Vector3.ONE, Vector3(0, -a, 0))
	var g := Node3D.new(); g.name = "Glow"; root.add_child(g)
	var cr := Node3D.new(); cr.position = Vector3(0, 1.7, 0); g.add_child(cr)
	var pm := PrismMesh.new(); pm.size = Vector3(0.5, 0.7, 0.5)
	var cm := toon(glow.darkened(0.1), true, 0.7)
	part(cr, pm, cm, Vector3(0, 0.35, 0))
	part(cr, pm, cm, Vector3(0, -0.35, 0), Vector3.ONE, Vector3(PI, 0, 0))
	PropAnim.on(cr, 0.7, 0.1)
	var beam := part(g, cyl(0.2, 0.4, 12.0, 10), glow_mat(Color(glow, 0.2)), Vector3(0, 6.0, 0))
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ring := MeshInstance3D.new(); ring.name = "Ring"; ring.mesh = flat_quad(4.6)
	ring.material_override = ring_mat(glow, 0.05); ring.position.y = 0.3
	g.add_child(ring)
	return root

static func shrine() -> Node3D:
	var root := Node3D.new()
	var stone := toon(Color("a9a39a"))
	var stone_l := toon(Color("cfc8bb"))
	var moss := toon(Color("7fa65a"), false)
	var glow := Color("8fe3c8")
	# a two-step hexagonal dais with a carved, glowing inlay
	part(root, cyl(1.05, 1.15, 0.18, 6), stone, Vector3(0, 0.09, 0))
	part(root, cyl(0.78, 0.86, 0.18, 6), stone_l, Vector3(0, 0.27, 0))
	part(root, cyl(0.5, 0.5, 0.02, 6), toon(glow, false, 0.8), Vector3(0, 0.37, 0))
	part(root, cyl(0.35, 0.42, 0.22, 6), stone, Vector3(0, 0.47, 0))
	# three leaning standing stones with moss on top
	for i in 3:
		var a := TAU * i / 3.0 + 0.5
		var at := Vector3(cos(a) * 0.98, 0.0, sin(a) * 0.98)
		var tilt := Vector3(sin(a) * 0.12, -a, -cos(a) * 0.12)
		part(root, box(0.26, 1.0 - i * 0.12, 0.2), stone, at + Vector3(0, 0.5 - i * 0.06, 0), Vector3.ONE, tilt)
		part(root, box(0.28, 0.06, 0.22), moss, at + Vector3(0, 1.0 - i * 0.12, 0), Vector3.ONE, tilt)
		part(root, box(0.04, 0.3, 0.01), toon(glow, false, 0.9), at + Vector3(0, 0.55, 0) - Vector3(cos(a), 0, sin(a)) * 0.105, Vector3.ONE, tilt)
	# the healing crystal floats and turns above the dais
	var cr := Node3D.new(); cr.name = "Crystal"; cr.position = Vector3(0, 1.45, 0); root.add_child(cr)
	var pm := PrismMesh.new(); pm.size = Vector3(0.42, 0.62, 0.42)
	var cm := toon(glow.darkened(0.15), true, 0.55)
	part(cr, pm, cm, Vector3(0, 0.31, 0))
	part(cr, pm, cm, Vector3(0, -0.31, 0), Vector3.ONE, Vector3(PI, 0, 0))
	for i in 3:
		var a2 := TAU * i / 3.0
		part(cr, pm, cm, Vector3(cos(a2) * 0.42, -0.1, sin(a2) * 0.42), Vector3.ONE * 0.3)
	PropAnim.on(cr, 0.9, 0.08)
	var base := MeshInstance3D.new(); base.name = "Ring"; base.mesh = flat_quad(3.0)
	base.material_override = ring_mat(glow, 0.06); base.position.y = 0.04
	root.add_child(base)
	return root

static func nest() -> Node3D:
	var root := Node3D.new()
	var twig := toon(Color("8a6a45"))
	var t := TorusMesh.new(); t.inner_radius = 0.55; t.outer_radius = 0.95; t.rings = 16; t.ring_segments = 6
	part(root, t, twig, Vector3(0, 0.15, 0), Vector3(1, 0.7, 1))
	part(root, cyl(0.6, 0.6, 0.06, 14), toon(Color("c9a77a")), Vector3(0, 0.1, 0))
	var cols := [Color("ffe8c4"), Color("cfe8ff"), Color("ffd0dc")]
	for i in 3:
		var a := TAU * i / 3.0
		part(root, sphere(0.16, 10), toon(cols[i]), Vector3(cos(a) * 0.25, 0.28, sin(a) * 0.25), Vector3(1, 1.25, 1))
	return root

const EXTRACT_R := 2.6
static func portal(c: Color) -> Node3D:
	var root := Node3D.new()
	var t := TorusMesh.new(); t.inner_radius = 0.95; t.outer_radius = 1.2; t.rings = 24; t.ring_segments = 8
	var mr := toon(Color("6a6f80"), true)
	var ring := part(root, t, mr, Vector3(0, 1.25, 0), Vector3.ONE, Vector3(PI / 2, 0, 0), "Ring")
	# runes around the ring that light up, and a pair of stone feet
	for i in 8:
		var a := TAU * i / 8.0
		part(ring, box(0.12, 0.3, 0.14), toon(c, false, 0.9), Vector3(cos(a) * 1.08, 0.0, sin(a) * 1.08), Vector3.ONE, Vector3(0, -a, 0))
	for sx in [-1.0, 1.0]:
		part(root, box(0.42, 0.34, 0.5), toon(Color("585c6a")), Vector3(0.95 * sx, 0.17, 0))
		part(root, box(0.3, 0.06, 0.38), toon(Color("7fa65a"), false), Vector3(0.95 * sx, 0.36, 0))
	var disc := part(root, cyl(1.0, 1.0, 0.02, 24), glow_mat(c), Vector3(0, 1.25, 0), Vector3.ONE, Vector3(PI / 2, 0, 0), "Disc")
	disc.visible = false
	var base := MeshInstance3D.new(); base.name = "Base"; base.mesh = flat_quad(3.2)
	base.material_override = ring_mat(c, 0.1); base.position.y = 0.05; root.add_child(base)
	# the extraction circle: dim until you stand in it, then it fills around as you extract
	var zone := MeshInstance3D.new(); zone.name = "Zone"; zone.mesh = flat_quad(EXTRACT_R * 2.0)
	zone.material_override = ring_mat(Color(c, 0.35), 0.035); zone.position.y = 0.06; root.add_child(zone)
	var zf := MeshInstance3D.new(); zf.name = "ZoneFill"; zf.mesh = flat_quad(EXTRACT_R * 2.0)
	var zm := ring_mat(Color(c.lightened(0.35), 0.95), 0.07)
	zm.set_shader_parameter("arc", 0.0)
	zf.material_override = zm; zf.position.y = 0.07; root.add_child(zf)
	var beam := CPUParticles3D.new(); beam.name = "Beam"
	beam.amount = 40; beam.lifetime = 1.6; beam.emitting = false
	var bm := SphereMesh.new(); bm.radius = 0.07; bm.height = 0.14; bm.radial_segments = 6; bm.rings = 3
	var pmat := StandardMaterial3D.new(); pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; pmat.albedo_color = c.lightened(0.3)
	bm.material = pmat
	beam.mesh = bm
	beam.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	beam.emission_ring_axis = Vector3.UP; beam.emission_ring_radius = 1.1; beam.emission_ring_inner_radius = 0.6; beam.emission_ring_height = 0.1
	beam.direction = Vector3.UP; beam.spread = 8.0; beam.gravity = Vector3(0, 2.5, 0)
	beam.initial_velocity_min = 1.0; beam.initial_velocity_max = 2.5
	beam.position = Vector3(0, 0.1, 0)
	root.add_child(beam)
	return root

static func jump_pad(c: Color) -> Node3D:
	var root := Node3D.new()
	part(root, cyl(0.7, 0.8, 0.14, 20), toon(Color("3f4456")), Vector3(0, 0.07, 0))
	var top := part(root, cyl(0.55, 0.55, 0.02, 20), toon(c.darkened(0.25), false, 0.45), Vector3(0, 0.15, 0), Vector3.ONE, Vector3.ZERO, "Top")
	for i in 3:
		part(root, box(0.3, 0.03, 0.08), toon(Color("e8fff6"), false, 0.6), Vector3(0, 0.18, 0.2 - i * 0.2), Vector3.ONE, Vector3(0, 0, 0), "Chev%d" % i)
	return root

static func gem() -> Node3D:
	var root := Node3D.new()
	var p := PrismMesh.new(); p.size = Vector3(0.28, 0.3, 0.28)
	var m := toon(Color("7ef0d0"), false, 0.7)
	part(root, p, m, Vector3(0, 0.15, 0))
	part(root, p, m, Vector3(0, -0.15, 0), Vector3.ONE, Vector3(PI, 0, 0))
	return root

static func armor_shard() -> Node3D:
	var root := Node3D.new()
	var pm := PrismMesh.new(); pm.size = Vector3(0.22, 0.34, 0.08)
	var m := toon(Color("7ac8ff"), false, 0.8)
	part(root, pm, m, Vector3(0, 0.2, 0))
	part(root, pm, m, Vector3(0, 0.05, 0), Vector3(0.7, 0.7, 1), Vector3(PI, 0, 0))
	return root

static func tonic() -> Node3D:
	var root := Node3D.new()
	part(root, sphere(0.16, 12), toon(Color("8ff0a0"), false, 0.6), Vector3(0, 0.16, 0))
	part(root, cyl(0.05, 0.06, 0.14, 8), toon(Color("e6f2ea")), Vector3(0, 0.34, 0))
	part(root, cyl(0.065, 0.065, 0.05, 8), toon(Color("8b6d52")), Vector3(0, 0.43, 0))
	return root

static func seed_bag(c: Color) -> Node3D:
	var root := Node3D.new()
	part(root, sphere(0.2), toon(Color("c8a26a")), Vector3(0, 0.2, 0), Vector3(1, 1.1, 1))
	part(root, sphere(0.09), toon(c, false, 0.4), Vector3(0, 0.42, 0))
	return root

# ---------------------------------------------------------------- home
static func house() -> Node3D:
	var root := Node3D.new()
	var wall := toon(Color("efe2c8")); var roof := toon(Color("b4553f")); var wood := toon(Color("7a5236"))
	var glass := toon(Color("ffd98a"), false, 0.8)
	part(root, box(4.2, 2.2, 3.2), wall, Vector3(0, 1.1, 0))
	var pr := PrismMesh.new(); pr.size = Vector3(4.8, 1.6, 3.6)
	part(root, pr, roof, Vector3(0, 3.0, 0))
	part(root, box(0.9, 1.5, 0.1), wood, Vector3(0, 0.75, 1.62))
	part(root, box(0.8, 0.7, 0.08), glass, Vector3(-1.3, 1.3, 1.62))
	part(root, box(0.8, 0.7, 0.08), glass, Vector3(1.3, 1.3, 1.62))
	part(root, box(0.5, 1.2, 0.5), toon(Color("8a8078")), Vector3(1.3, 3.4, -0.6))
	part(root, box(4.4, 0.25, 3.4), wood, Vector3(0, 0.12, 0))
	return root

static func plot() -> Node3D:
	var root := Node3D.new()
	var soil := toon(Color("6b4a33")); var dark := toon(Color("4e3424"))
	part(root, box(1.7, 0.2, 1.7), soil, Vector3(0, 0.1, 0))
	for i in 3:
		part(root, box(1.5, 0.05, 0.14), dark, Vector3(0, 0.21, -0.5 + i * 0.5))
	# watered soil: darker and a little shiny
	var wet := part(root, box(1.66, 0.02, 1.66), toon(Color("3a2618"), false, 0.25), Vector3(0, 0.205, 0), Vector3.ONE, Vector3.ZERO, "Wet")
	wet.visible = false
	var crop := Node3D.new(); crop.name = "Crop"; root.add_child(crop)
	return root

static func crop(stage: int, grow: int, col: Color) -> Node3D:
	var root := Node3D.new()
	var leaf := toon(Color("5aa04a"))
	var k := clampf(float(stage) / float(grow), 0.0, 1.0)
	for i in 3:
		var x := -0.5 + i * 0.5
		if stage <= 0:
			part(root, sphere(0.06, 6), toon(Color("8a6a45")), Vector3(x, 0.25, 0))
			continue
		var hgt := 0.15 + k * 0.45
		part(root, cyl(0.03, 0.04, hgt, 6), leaf, Vector3(x, 0.2 + hgt * 0.5, 0))
		part(root, sphere(0.12 + k * 0.12, 8), leaf, Vector3(x, 0.22 + hgt, 0), Vector3(1.2, 0.6, 1.2))
		if stage >= grow:
			part(root, sphere(0.13, 10), toon(col, true, 0.25), Vector3(x + 0.08, 0.3 + hgt, 0.08))
	return root

static func cauldron() -> Node3D:
	var root := Node3D.new()
	var iron := toon(Color("3a3a44"))
	part(root, sphere(0.6), iron, Vector3(0, 0.55, 0), Vector3(1, 0.8, 1))
	var t := TorusMesh.new(); t.inner_radius = 0.45; t.outer_radius = 0.58
	part(root, t, iron, Vector3(0, 0.9, 0))
	part(root, cyl(0.47, 0.47, 0.04, 20), toon(Color("7fe0a0"), false, 0.6), Vector3(0, 0.9, 0))
	for i in 3:
		var a := i * TAU / 3.0
		part(root, cyl(0.05, 0.05, 0.4), iron, Vector3(cos(a) * 0.4, 0.15, sin(a) * 0.4))
	part(root, box(0.5, 0.15, 0.5), toon(Color("ff9a4a"), false, 1.0), Vector3(0, 0.08, 0))
	return root

static func stall() -> Node3D:
	var root := Node3D.new()
	var wood := toon(Color("8a5a35"))
	part(root, box(2.2, 0.9, 0.9), wood, Vector3(0, 0.45, 0))
	for x in [-1.0, 1.0]:
		part(root, cyl(0.06, 0.06, 2.0), wood, Vector3(x, 1.0, -0.35))
		part(root, cyl(0.06, 0.06, 2.0), wood, Vector3(x, 1.0, 0.35))
	for i in 4:
		part(root, box(0.56, 0.08, 1.2), toon(Color("e0607e") if i % 2 == 0 else Color("f3eee2")), Vector3(-0.84 + i * 0.56, 2.05, 0), Vector3.ONE, Vector3(0.25, 0, 0))
	for i in 3:
		part(root, sphere(0.14), toon([Color("ff6a4a"), Color("5ab8f0"), Color("f2c84a")][i]), Vector3(-0.6 + i * 0.6, 1.0, 0))
	return root

static func fence(length: float) -> Node3D:
	var root := Node3D.new()
	var wood := toon(Color("a07a52"))
	var posts := maxi(2, int(length / 1.0) + 1)
	for i in posts:
		var x := -length * 0.5 + length * float(i) / float(posts - 1)
		part(root, box(0.12, 0.7, 0.12), wood, Vector3(x, 0.35, 0))
	part(root, box(length, 0.08, 0.06), wood, Vector3(0, 0.5, 0))
	part(root, box(length, 0.08, 0.06), wood, Vector3(0, 0.25, 0))
	return root

static func lamp() -> Node3D:
	var root := Node3D.new()
	var iron := toon(Color("3a3a44"))
	part(root, cyl(0.06, 0.08, 1.9), iron, Vector3(0, 0.95, 0))
	part(root, box(0.3, 0.06, 0.3), iron, Vector3(0, 1.95, 0))
	part(root, box(0.22, 0.28, 0.22), toon(Color("ffd98a"), false, 1.4), Vector3(0, 2.12, 0))
	part(root, cyl(0.0, 0.2, 0.18), iron, Vector3(0, 2.34, 0))
	var l := OmniLight3D.new()
	l.light_color = Color("ffd9a8"); l.light_energy = 0.55; l.omni_range = 4.0
	l.position = Vector3(0, 2.1, 0)
	root.add_child(l)
	return root

static func pond(rx: float, rz: float) -> Node3D:
	var root := Node3D.new()
	var rim := toon(Color("8d8a86"))
	part(root, cyl(1.0, 1.0, 0.06, 28), toon(Color("3d78a8"), false, 0.12), Vector3(0, 0.03, 0), Vector3(rx, 1, rz))
	for i in 14:
		var a := TAU * i / 14.0
		part(root, sphere(0.2, 6), rim, Vector3(cos(a) * rx, 0.06, sin(a) * rz), Vector3(1.2, 0.6, 1.0))
	for i in 3:
		var a := TAU * i / 3.0 + 0.4
		part(root, cyl(0.18, 0.18, 0.02, 10), toon(Color("5fae4f"), false), Vector3(cos(a) * rx * 0.5, 0.08, sin(a) * rz * 0.45))
	return root

static func flower_bed(rng: RandomNumberGenerator, n := 7) -> Node3D:
	var root := Node3D.new()
	var cols := [Color("ff8fb0"), Color("ffd35a"), Color("b48cf2"), Color("ff7a5a"), Color("ffffff")]
	for i in n:
		var p := Vector3(rng.randf_range(-0.7, 0.7), 0, rng.randf_range(-0.35, 0.35))
		part(root, cyl(0.02, 0.02, 0.3, 4), toon(Color("4f8a3e"), false), p + Vector3(0, 0.15, 0))
		part(root, sphere(0.08, 6), toon(cols[rng.randi_range(0, cols.size() - 1)], false, 0.2), p + Vector3(0, 0.32, 0))
	return root

static func kin_bed(c: Color) -> Node3D:
	var root := Node3D.new()
	part(root, cyl(0.42, 0.46, 0.14, 16), toon(c.darkened(0.25)), Vector3(0, 0.07, 0))
	part(root, cyl(0.32, 0.32, 0.06, 16), toon(c.lightened(0.25)), Vector3(0, 0.14, 0))
	return root

static func signpost(text_lines: Array) -> Node3D:
	var root := Node3D.new()
	var wood := toon(Color("8a5a35"))
	part(root, box(0.12, 1.4, 0.12), wood, Vector3(0, 0.7, 0))
	part(root, box(1.1, 0.4, 0.08), toon(Color("c49a6a")), Vector3(0, 1.25, 0.05))
	var l := Label3D.new()
	l.text = "\n".join(text_lines)
	l.font = load("res://fonts/LilitaOne-Regular.ttf")
	l.font_size = 40; l.pixel_size = 0.005; l.modulate = Color("3a2a1a"); l.outline_size = 0
	l.position = Vector3(0, 1.25, 0.1)
	root.add_child(l)
	return root

# ---------------------------------------------------------------- home buildings
static func building(id: String) -> Node3D:
	if id in ["armory", "shrine"]:
		return EconModels.building(id)
	var root := Node3D.new()
	var body := Node3D.new(); body.name = "Body"; root.add_child(body)
	var wood := toon(Color("7a5236")); var stone := toon(Color("9a948c")); var dark := toon(Color("4a4550"))
	var glass := toon(Color("ffd98a"), false, 0.8)
	match id:
		"workshop":
			part(body, box(3.0, 1.9, 2.4), toon(Color("d9c3a0")), Vector3(0, 0.95, -0.1))
			var pr := PrismMesh.new(); pr.size = Vector3(3.5, 1.2, 2.8)
			part(body, pr, toon(Color("4f6a8a")), Vector3(0, 2.5, -0.1))
			part(body, box(1.3, 1.3, 0.08), dark, Vector3(-0.5, 0.65, 1.12))
			part(body, box(0.6, 0.5, 0.08), glass, Vector3(0.85, 1.2, 1.12))
			part(body, box(0.4, 1.4, 0.4), stone, Vector3(1.1, 2.7, -0.6))
			# anvil and a glider hung up to dry
			part(body, box(0.5, 0.35, 0.3), dark, Vector3(1.0, 0.18, 1.6))
			part(body, box(0.7, 0.12, 0.3), dark, Vector3(1.0, 0.42, 1.6))
			part(body, box(1.6, 0.04, 0.5), toon(Color("f3eee2")), Vector3(-0.3, 1.75, 1.2), Vector3.ONE, Vector3(-0.4, 0, 0))
			part(body, box(0.3, 0.05, 0.52), toon(Color("ff9a4a")), Vector3(-0.95, 1.76, 1.2), Vector3.ONE, Vector3(-0.4, 0, 0))
		"board":
			# a little guild house with a big notice board out front and pennants on the roof
			part(body, box(2.6, 1.6, 1.6), toon(Color("e8d2b0")), Vector3(0, 0.8, -0.2))
			var pr0 := PrismMesh.new(); pr0.size = Vector3(3.0, 1.1, 2.0)
			part(body, pr0, toon(Color("b84a3a")), Vector3(0, 2.15, -0.2))
			part(body, box(0.8, 1.2, 0.08), dark, Vector3(-0.6, 0.6, 0.62))
			part(body, box(1.3, 0.9, 0.08), wood, Vector3(0.65, 1.05, 0.66))
			for k in 4:
				var pc: Color = [Color("fff6c0"), Color("cfeaff"), Color("ffd6e0"), Color("e0ffd6")][k]
				part(body, box(0.26, 0.3, 0.02), toon(pc, false), Vector3(0.38 + (k % 2) * 0.55, 1.22 - (k / 2) * 0.38, 0.71), Vector3.ONE, Vector3(0, 0, randf_range(-0.12, 0.12)))
			part(body, cyl(0.03, 0.03, 1.0, 6), wood, Vector3(0.65, 0.3, 0.66))
			for k in 5:
				part(body, PrismMesh.new(), toon([Color("ffd23f"), Color("5ab0f0"), Color("e0607e"), Color("8fd16a"), Color("b48cf2")][k], false), Vector3(-1.2 + k * 0.6, 2.75 - absf(k - 2) * 0.12, -0.2), Vector3(0.22, 0.28, 0.04), Vector3(PI, 0, 0))
			part(body, sphere(0.16, 10), toon(Color("ffd23f"), false, 0.8), Vector3(0, 2.85, -0.2))
		"ransom":
			# Old Pell's Ransom House: a crooked dark-wood shop with a hanging lantern, a kin-shaped
			# sign, and little hutches out front where lost kin wait
			var plum := toon(Color("5a3f5e")); var trim := toon(Color("c9a46a"))
			part(body, box(2.6, 1.7, 1.7), toon(Color("6e5a4a")), Vector3(0, 0.85, -0.2))
			var pr1 := PrismMesh.new(); pr1.size = Vector3(3.0, 1.2, 2.1)
			part(body, pr1, plum, Vector3(0, 2.3, -0.2), Vector3.ONE, Vector3(0, 0, 0.04))
			part(body, box(0.8, 1.2, 0.08), dark, Vector3(0.6, 0.6, 0.66))
			part(body, box(0.5, 0.45, 0.08), toon(Color("ffd58a"), false, 0.8), Vector3(-0.6, 1.15, 0.66))
			part(body, box(2.8, 0.08, 0.5), trim, Vector3(0, 1.72, 0.6))
			# the sign: a round kin face on a post
			part(body, cyl(0.03, 0.03, 0.7, 6), wood, Vector3(-1.45, 1.4, 0.75), Vector3.ONE, Vector3(0, 0, PI / 2))
			part(body, cyl(0.3, 0.3, 0.06, 18), trim, Vector3(-1.75, 1.05, 0.75), Vector3.ONE, Vector3(PI / 2, 0, 0))
			part(body, sphere(0.16, 12), toon(Color("ff9a5a")), Vector3(-1.75, 1.05, 0.8), Vector3(1, 1, 0.4))
			for sx in [-1.0, 1.0]:
				part(body, cyl(0.0, 0.06, 0.12, 6), toon(Color("ff9a5a")), Vector3(-1.75 + 0.09 * sx, 1.22, 0.8))
			# lantern
			part(body, cyl(0.01, 0.01, 0.3, 4), dark, Vector3(1.3, 1.6, 0.85))
			part(body, sphere(0.11, 10), toon(Color("ffd25a"), false, 1.2), Vector3(1.3, 1.4, 0.85), Vector3.ONE, Vector3.ZERO, "Lamp")
			# hutches
			for k in 2:
				var hx := -0.5 + k * 1.1
				part(body, box(0.6, 0.45, 0.45), wood, Vector3(hx, 0.22, 1.2))
				for b in 3:
					part(body, box(0.03, 0.4, 0.03), dark, Vector3(hx - 0.2 + b * 0.2, 0.22, 1.43))
				part(body, sphere(0.12, 10), toon([Color("4aa8e8"), Color("b9a6f5")][k]), Vector3(hx, 0.16, 1.22))
		"cottage", "cottage2":
			var wall := Color("f3dcc4") if id == "cottage" else Color("dfe8cf")
			var roof := Color("5a9ab8") if id == "cottage" else Color("c28a3a")
			part(body, box(2.6, 1.5, 2.0), toon(wall), Vector3(0, 0.75, 0))
			var pr := PrismMesh.new(); pr.size = Vector3(3.0, 1.3, 2.4)
			part(body, pr, toon(roof), Vector3(0, 2.15, 0))
			part(body, cyl(0.38, 0.38, 0.08, 16), wood, Vector3(0, 0.38, 1.02), Vector3(1, 1, 1), Vector3(PI / 2, 0, 0))
			part(body, cyl(0.25, 0.25, 0.06, 12), glass, Vector3(0.85, 1.0, 1.02), Vector3.ONE, Vector3(PI / 2, 0, 0))
			part(body, cyl(0.25, 0.25, 0.06, 12), glass, Vector3(-0.85, 1.0, 1.02), Vector3.ONE, Vector3(PI / 2, 0, 0))
			part(body, box(0.7, 0.16, 0.2), wood, Vector3(0.85, 0.66, 1.1))
			for i in 3:
				part(body, sphere(0.08, 6), toon([Color("ff8fb0"), Color("ffd35a"), Color("b48cf2")][i], false, 0.2), Vector3(0.62 + i * 0.22, 0.8, 1.12))
			part(body, sphere(0.2, 8), toon(Color("ffb3c6"), false, 0.5), Vector3(0, 2.9, 0))
		"greenhouse":
			var frame := toon(Color("f0f0ea"))
			var pane := glow_mat(Color(0.7, 0.95, 1.0, 0.22))
			part(body, box(3.6, 0.2, 2.8), stone, Vector3(0, 0.1, 0))
			part(body, box(3.4, 1.6, 2.6), pane, Vector3(0, 1.0, 0))
			var pr := PrismMesh.new(); pr.size = Vector3(3.5, 1.0, 2.7)
			part(body, pr, pane, Vector3(0, 2.3, 0))
			for x in [-1.7, -0.57, 0.57, 1.7]:
				part(body, box(0.08, 1.7, 0.08), frame, Vector3(x, 1.0, 1.3))
				part(body, box(0.08, 1.7, 0.08), frame, Vector3(x, 1.0, -1.3))
			part(body, box(3.5, 0.08, 0.08), frame, Vector3(0, 1.8, 1.3))
			part(body, box(3.5, 0.08, 0.08), frame, Vector3(0, 1.8, -1.3))
			part(body, box(3.5, 0.08, 0.08), frame, Vector3(0, 2.8, 0))
			for i in 6:
				var px := -1.2 + (i % 3) * 1.2; var pz := -0.6 + (i / 3) * 1.2
				part(body, cyl(0.2, 0.16, 0.3, 8), toon(Color("b4553f")), Vector3(px, 0.35, pz))
				part(body, sphere(0.3, 8), toon(Color("5aa04a")), Vector3(px, 0.75, pz), Vector3(1, 1.2, 1))
		"dojo":
			for side in [[Vector3(0, 0, -1.6), 0.0], [Vector3(0, 0, 1.6), 0.0], [Vector3(-1.9, 0, 0), PI / 2], [Vector3(1.9, 0, 0), PI / 2]]:
				var f := fence(3.2 if side[1] == 0.0 else 3.2)
				f.position = side[0]; f.rotation.y = side[1]
				body.add_child(f)
			part(body, box(3.6, 0.04, 3.0), toon(Color("c9a77a")), Vector3(0, 0.02, 0))
			for x in [-0.9, 0.9]:
				part(body, cyl(0.07, 0.07, 1.3), wood, Vector3(x, 0.65, -0.3))
				part(body, capsule(0.28, 0.8), toon(Color("d8b98a")), Vector3(x, 1.05, -0.3))
				part(body, cyl(0.2, 0.2, 0.04, 14), toon(Color("e0607e")), Vector3(x, 1.15, -0.02), Vector3.ONE, Vector3(PI / 2, 0, 0))
				part(body, cyl(0.08, 0.08, 0.05, 10), toon(Color("f3eee2")), Vector3(x, 1.15, 0.01), Vector3.ONE, Vector3(PI / 2, 0, 0))
			part(body, box(1.4, 0.12, 0.4), wood, Vector3(0, 0.4, 1.1))
			part(body, box(0.1, 0.4, 0.3), wood, Vector3(-0.6, 0.2, 1.1))
			part(body, box(0.1, 0.4, 0.3), wood, Vector3(0.6, 0.2, 1.1))
		"vault":
			part(body, box(3.0, 2.0, 2.2), stone, Vector3(0, 1.0, 0))
			part(body, box(3.3, 0.3, 2.5), toon(Color("7a746c")), Vector3(0, 2.15, 0))
			part(body, cyl(0.7, 0.7, 0.12, 24), toon(Color("6a6f7a")), Vector3(0, 0.95, 1.1), Vector3.ONE, Vector3(PI / 2, 0, 0))
			var t := TorusMesh.new(); t.inner_radius = 0.5; t.outer_radius = 0.66
			part(body, t, toon(Color("f2c84a"), true, 0.3), Vector3(0, 0.95, 1.17), Vector3.ONE, Vector3(PI / 2, 0, 0))
			part(body, box(0.5, 0.08, 0.08), toon(Color("f2c84a")), Vector3(0, 0.95, 1.2))
			var g := gem(); g.position = Vector3(0, 2.75, 0); g.scale = Vector3.ONE * 1.8; g.name = "Gem"; body.add_child(g)
		"hall":
			part(body, box(3.2, 0.3, 2.6), toon(Color("e8e2d6")), Vector3(0, 0.15, 0))
			part(body, box(3.0, 0.2, 2.4), toon(Color("d8d0c0")), Vector3(0, 0.38, 0))
			for x in [-1.2, -0.4, 0.4, 1.2]:
				for z in [-0.9, 0.9]:
					part(body, cyl(0.15, 0.17, 1.8, 10), toon(Color("f3eee2")), Vector3(x, 1.38, z))
			part(body, box(3.2, 0.25, 2.6), toon(Color("e8e2d6")), Vector3(0, 2.38, 0))
			var pr := PrismMesh.new(); pr.size = Vector3(3.4, 0.7, 2.8)
			part(body, pr, toon(Color("b4553f")), Vector3(0, 2.85, 0))
			var gold := toon(Color("f2c84a"), true, 0.4)
			part(body, cyl(0.16, 0.08, 0.2, 10), gold, Vector3(0, 0.6, 0))
			part(body, cyl(0.25, 0.12, 0.35, 12), gold, Vector3(0, 0.88, 0))
			part(body, sphere(0.09, 8), gold, Vector3(0.26, 0.95, 0))
			part(body, sphere(0.09, 8), gold, Vector3(-0.26, 0.95, 0))
	return root

## An empty building site: corner stakes, a rope line, a stack of planks and a sign.
static func lot(w: float, d: float, title: String, price: String) -> Node3D:
	var root := Node3D.new()
	var wood := toon(Color("a07a52"))
	var rope := toon(Color("e8d8b0"), false)
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		part(root, box(0.1, 0.5, 0.1), wood, Vector3(c.x * w * 0.5, 0.25, c.y * d * 0.5))
	part(root, box(w, 0.03, 0.03), rope, Vector3(0, 0.42, -d * 0.5))
	part(root, box(w, 0.03, 0.03), rope, Vector3(0, 0.42, d * 0.5))
	part(root, box(0.03, 0.03, d), rope, Vector3(-w * 0.5, 0.42, 0))
	part(root, box(0.03, 0.03, d), rope, Vector3(w * 0.5, 0.42, 0))
	for i in 3:
		part(root, box(1.2, 0.1, 0.24), toon(Color("b08a5c").darkened(i * 0.08)), Vector3(-w * 0.18, 0.06 + i * 0.11, -d * 0.15 + i * 0.03), Vector3.ONE, Vector3(0, i * 0.15, 0))
	part(root, box(0.5, 0.4, 0.5), toon(Color("8d8a86")), Vector3(w * 0.22, 0.2, -d * 0.2))
	var s := signpost([title, price])
	s.position = Vector3(0, 0, d * 0.5 + 0.35)
	s.name = "Sign"
	root.add_child(s)
	return root

## One plank of a bridge, roughly a tile deep and two tiles wide.
static func plank(rng: RandomNumberGenerator, width: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = box(width, 0.14, 0.42)
	mi.material_override = toon(Color("a07a52").lerp(Color("7a5a3c"), rng.randf()))
	mi.rotation.y = rng.randf_range(-0.04, 0.04)
	return mi


## The ferry stop at home: a post with a bell and a sign, and a short jetty.
static func ferry_post() -> Node3D:
	var root := Node3D.new()
	var wood := toon(Color("7a5236"))
	part(root, box(0.16, 2.2, 0.16), wood, Vector3(0, 1.1, 0))
	part(root, box(0.9, 0.1, 0.1), wood, Vector3(0.38, 2.1, 0))
	part(root, cyl(0.06, 0.18, 0.26, 12), toon(Color("f2c84a"), true, 0.3), Vector3(0.7, 1.86, 0))
	part(root, box(1.2, 0.36, 0.08), toon(Color("c49a6a")), Vector3(0, 1.3, 0.1))
	var l := Label3D.new(); l.text = "Ferry"; l.font = load("res://fonts/LilitaOne-Regular.ttf")
	l.font_size = 48; l.pixel_size = 0.005; l.modulate = Color("3a2a1a"); l.outline_size = 0; l.position = Vector3(0, 1.3, 0.15)
	root.add_child(l)
	for i in 3:
		part(root, box(1.4, 0.08, 0.36), wood, Vector3(0, 0.04, -0.6 - i * 0.38))
	return root


## Guild landmarks.
static func lighthouse(col: Color) -> Node3D:
	var root := Node3D.new()
	var body := Node3D.new(); body.name = "Body"; root.add_child(body)
	var white := toon(Color("f3eee2")); var red := toon(Color("c0443a"))
	part(body, cyl(1.3, 1.5, 0.5, 18), toon(Color("8d8a86")), Vector3(0, 0.25, 0))
	for i in 4:
		part(body, cyl(0.95 - i * 0.12, 1.05 - i * 0.12, 1.4, 16), white if i % 2 == 0 else red, Vector3(0, 1.2 + i * 1.4, 0))
	part(body, cyl(0.7, 0.7, 0.9, 12), toon(col, false, 1.4), Vector3(0, 6.6, 0))
	part(body, cyl(0.0, 0.9, 0.8, 12), red, Vector3(0, 7.45, 0))
	var l := OmniLight3D.new(); l.light_color = col; l.light_energy = 1.4; l.omni_range = 9.0; l.position = Vector3(0, 6.6, 0)
	body.add_child(l)
	return root

static func banner(col: Color) -> Node3D:
	var root := Node3D.new()
	part(root, cyl(0.06, 0.06, 3.2, 8), toon(Color("5a4636")), Vector3(0, 1.6, 0))
	part(root, box(0.7, 1.1, 0.04), toon(col), Vector3(0.38, 2.5, 0), Vector3.ONE, Vector3.ZERO, "Flag")
	part(root, sphere(0.09, 8), toon(Color("f2c84a"), true, 0.4), Vector3(0, 3.25, 0))
	return root

static func notice_board() -> Node3D:
	var root := Node3D.new()
	var wood := toon(Color("7a5236"))
	for x in [-1.0, 1.0]:
		part(root, box(0.14, 2.0, 0.14), wood, Vector3(x, 1.0, 0))
	part(root, box(2.3, 1.3, 0.1), toon(Color("c49a6a")), Vector3(0, 1.35, 0))
	part(root, box(2.5, 0.14, 0.3), wood, Vector3(0, 2.05, 0))
	var cols := [Color("f3eee2"), Color("ffe08a"), Color("cfe8ff"), Color("ffd0dc")]
	for i in 5:
		part(root, box(0.42, 0.5, 0.02), toon(cols[i % 4]), Vector3(-0.8 + i * 0.4, 1.35 + (0.12 if i % 2 else -0.1), 0.07), Vector3.ONE, Vector3(0, 0, (i - 2) * 0.06))
	return root

static func fountain() -> Node3D:
	var root := Node3D.new()
	var stone := toon(Color("b8b2a8"))
	part(root, cyl(1.8, 1.9, 0.5, 24), stone, Vector3(0, 0.25, 0))
	part(root, cyl(1.55, 1.55, 0.06, 24), toon(Color("3d78a8"), false, 0.15), Vector3(0, 0.48, 0))
	part(root, cyl(0.3, 0.4, 1.3, 12), stone, Vector3(0, 1.0, 0))
	part(root, cyl(0.7, 0.5, 0.2, 16), stone, Vector3(0, 1.7, 0))
	var sp := CPUParticles3D.new(); sp.name = "Spray"
	sp.amount = 40; sp.lifetime = 0.9
	var m := SphereMesh.new(); m.radius = 0.05; m.height = 0.1; m.radial_segments = 6; m.rings = 3
	var pm := StandardMaterial3D.new(); pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; pm.albedo_color = Color(0.75, 0.9, 1.0, 0.8); pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.material = pm; sp.mesh = m
	sp.direction = Vector3.UP; sp.spread = 18.0; sp.initial_velocity_min = 2.5; sp.initial_velocity_max = 3.4
	sp.gravity = Vector3(0, -9, 0); sp.position = Vector3(0, 1.8, 0)
	root.add_child(sp)
	return root


## Furniture for building interiors, built at the origin of its footprint's first tile and
## spanning size[0] x size[1] tiles along +x / +z.
static func furniture(id: String) -> Node3D:
	var root := Node3D.new()
	var wood := toon(Color("8a5a3a")); var dark := toon(Color("5e3c26")); var light := toon(Color("c99a6a"))
	var cloth := toon(Color("d9604a")); var cream := toon(Color("f1e6cf")); var leaf := toon(Color("4f9a4a")); var pot := toon(Color("c0663e"))
	var metal := toon(Color("3d3f4a"))
	match id:
		"bed":
			part(root, box(1.8, 0.35, 2.8), wood, Vector3(1.0, 0.25, 1.5))
			part(root, box(1.7, 0.18, 2.5), cream, Vector3(1.0, 0.5, 1.55))
			part(root, box(1.72, 0.12, 1.6), cloth, Vector3(1.0, 0.62, 2.0))
			part(root, box(0.9, 0.16, 0.45), toon(Color("fffaf0")), Vector3(1.0, 0.66, 0.5))
			part(root, box(1.9, 0.9, 0.12), dark, Vector3(1.0, 0.55, 0.12))
		"kin_bed":
			part(root, cyl(0.42, 0.36, 0.22, 16), toon(Color("c9a46a")), Vector3(0.5, 0.11, 0.5))
			part(root, cyl(0.32, 0.32, 0.06, 16), toon(Color("e8b0c0")), Vector3(0.5, 0.2, 0.5))
		"table":
			part(root, box(1.8, 0.1, 0.9), light, Vector3(1.0, 0.72, 0.5))
			for p in [Vector3(0.2, 0.36, 0.15), Vector3(1.8, 0.36, 0.15), Vector3(0.2, 0.36, 0.85), Vector3(1.8, 0.36, 0.85)]:
				part(root, box(0.1, 0.72, 0.1), wood, p)
			part(root, cyl(0.1, 0.08, 0.14, 10), toon(Color("e0e8f0")), Vector3(0.6, 0.84, 0.5))
		"chair":
			part(root, box(0.55, 0.08, 0.55), light, Vector3(0.5, 0.45, 0.5))
			part(root, box(0.55, 0.55, 0.08), wood, Vector3(0.5, 0.72, 0.25))
			for p in [Vector3(0.28, 0.22, 0.28), Vector3(0.72, 0.22, 0.28), Vector3(0.28, 0.22, 0.72), Vector3(0.72, 0.22, 0.72)]:
				part(root, box(0.07, 0.45, 0.07), wood, p)
		"stool":
			part(root, cyl(0.25, 0.25, 0.08, 12), light, Vector3(0.5, 0.45, 0.5))
			part(root, cyl(0.06, 0.1, 0.42, 8), wood, Vector3(0.5, 0.21, 0.5))
		"rug":
			part(root, box(2.9, 0.03, 1.9), toon(Color("6a4c8c"), false), Vector3(1.5, 0.015, 1.0))
			part(root, box(2.5, 0.035, 1.5), toon(Color("e0b25a"), false), Vector3(1.5, 0.02, 1.0))
			part(root, box(2.1, 0.04, 1.1), toon(Color("6a4c8c"), false), Vector3(1.5, 0.025, 1.0))
		"rug_round":
			part(root, cyl(0.95, 0.95, 0.03, 28), toon(Color("3f7a8c"), false), Vector3(1.0, 0.015, 1.0))
			part(root, cyl(0.6, 0.6, 0.035, 28), toon(Color("f2e8d2"), false), Vector3(1.0, 0.02, 1.0))
		"lamp":
			part(root, cyl(0.18, 0.22, 0.06, 12), metal, Vector3(0.5, 0.03, 0.5))
			part(root, cyl(0.03, 0.03, 1.4, 8), metal, Vector3(0.5, 0.72, 0.5))
			part(root, cyl(0.16, 0.28, 0.32, 14), toon(Color("ffe9b8"), false, 0.8), Vector3(0.5, 1.45, 0.5))
			var ol := OmniLight3D.new(); ol.light_color = Color("ffd9a0"); ol.light_energy = 1.4; ol.omni_range = 4.5
			ol.position = Vector3(0.5, 1.4, 0.5); root.add_child(ol)
		"plant":
			part(root, cyl(0.2, 0.15, 0.3, 12), pot, Vector3(0.5, 0.15, 0.5))
			part(root, sphere(0.28), leaf, Vector3(0.5, 0.48, 0.5), Vector3(1, 0.9, 1))
		"big_plant":
			part(root, cyl(0.26, 0.2, 0.4, 12), pot, Vector3(0.5, 0.2, 0.5))
			part(root, cyl(0.04, 0.05, 0.7, 6), dark, Vector3(0.5, 0.7, 0.5))
			for i in 4:
				var a := TAU * i / 4.0
				part(root, sphere(0.26), leaf, Vector3(0.5 + cos(a) * 0.18, 1.1 + (i % 2) * 0.12, 0.5 + sin(a) * 0.18))
		"shelf":
			part(root, box(1.8, 1.8, 0.45), wood, Vector3(1.0, 0.9, 0.3))
			for row in 3:
				for b in 7:
					part(root, box(0.17, 0.42, 0.3), toon([Color("c0443a"), Color("3f6a9c"), Color("d9b04a"), Color("4f8a5a")][(row + b) % 4]), Vector3(0.35 + b * 0.22, 0.42 + row * 0.55, 0.38))
		"chest":
			part(root, box(0.8, 0.5, 0.55), wood, Vector3(0.5, 0.25, 0.5))
			part(root, box(0.84, 0.1, 0.6), dark, Vector3(0.5, 0.52, 0.5))
			part(root, box(0.12, 0.14, 0.04), toon(Color("e0b84a"), false, 0.3), Vector3(0.5, 0.4, 0.78))
		"stove":
			part(root, box(0.85, 0.85, 0.75), metal, Vector3(0.5, 0.42, 0.45))
			part(root, box(0.5, 0.3, 0.05), toon(Color("ff8a3a"), false, 0.9), Vector3(0.5, 0.35, 0.84))
			part(root, cyl(0.08, 0.08, 0.8, 8), metal, Vector3(0.5, 1.2, 0.3))
		"fireplace":
			part(root, box(1.9, 1.2, 0.6), toon(Color("9a8f86")), Vector3(1.0, 0.6, 0.35))
			part(root, box(1.0, 0.6, 0.3), toon(Color("2a2024")), Vector3(1.0, 0.35, 0.55))
			part(root, sphere(0.22), toon(Color("ff9a3a"), false, 1.0), Vector3(1.0, 0.25, 0.6), Vector3(1.4, 0.8, 1))
			var fl := OmniLight3D.new(); fl.light_color = Color("ffb070"); fl.light_energy = 1.6; fl.omni_range = 5.0
			fl.position = Vector3(1.0, 0.5, 0.9); root.add_child(fl)
		"wardrobe":
			part(root, box(1.8, 2.0, 0.6), wood, Vector3(1.0, 1.0, 0.35))
			part(root, box(0.04, 1.8, 0.02), dark, Vector3(1.0, 1.0, 0.66))
			for x in [0.85, 1.15]:
				part(root, sphere(0.04), toon(Color("e0b84a")), Vector3(x, 1.0, 0.68))
		"fishbowl":
			part(root, box(0.6, 0.6, 0.6), wood, Vector3(0.5, 0.3, 0.5))
			part(root, sphere(0.28), toon(Color(0.6, 0.85, 1.0), false, 0.3), Vector3(0.5, 0.86, 0.5))
			part(root, sphere(0.06), toon(Color("ff8a3a")), Vector3(0.55, 0.84, 0.5), Vector3(1.4, 1, 1))
		"easel":
			part(root, box(0.06, 1.4, 0.06), wood, Vector3(0.3, 0.7, 0.55), Vector3.ONE, Vector3(0.12, 0, 0.1))
			part(root, box(0.06, 1.4, 0.06), wood, Vector3(0.7, 0.7, 0.55), Vector3.ONE, Vector3(0.12, 0, -0.1))
			part(root, box(0.8, 0.6, 0.04), toon(Color("f6efe0")), Vector3(0.5, 1.05, 0.45), Vector3.ONE, Vector3(-0.12, 0, 0))
			part(root, sphere(0.14), toon(Color("f2a24a")), Vector3(0.45, 1.08, 0.42), Vector3(1, 1, 0.2))
			part(root, box(0.6, 0.12, 0.02), toon(Color("5aa04a")), Vector3(0.5, 0.86, 0.43))
		"trophy":
			part(root, box(0.6, 0.7, 0.6), dark, Vector3(0.5, 0.35, 0.5))
			part(root, cyl(0.18, 0.08, 0.3, 12), toon(Color("f2c84a"), false, 0.5), Vector3(0.5, 0.95, 0.5))
			part(root, cyl(0.1, 0.12, 0.08, 10), toon(Color("f2c84a"), false, 0.5), Vector3(0.5, 0.74, 0.5))
		"cushion":
			part(root, cyl(0.38, 0.4, 0.16, 16), toon(Color("e07a9a")), Vector3(0.5, 0.08, 0.5))
		"toy_ball":
			part(root, sphere(0.18), toon(Color("ff6a5a")), Vector3(0.5, 0.18, 0.5))
			part(root, cyl(0.185, 0.185, 0.04, 16), toon(Color("fff0d8")), Vector3(0.5, 0.18, 0.5), Vector3.ONE, Vector3(0, 0, PI / 2))
	return root


## The skyship that carries everyone over the islands at the start of an expedition.
# ---------------------------------------------------------------- scenery islands
## A free-standing floating island for scenery (the title screen, distant backdrops): a grassy top
## with a wavy outline, a grass lip, cliffs with rock strata that taper into a jagged spike below.
## Drawn with the island terrain shader so it matches the playable islands.
static func float_island(rng: RandomNumberGenerator, radius: float, depth: float, top_c := Color("6aa64a"), side_c := Color("8b6d52"), deep_c := Color("3a3140")) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 44
	var ph := rng.randf() * 10.0
	var rim: Array = []
	for i in n:
		var a := TAU * i / n
		var wob := 1.0 + 0.13 * sin(a * 3.0 + ph) + 0.07 * sin(a * 7.0 + ph * 2.0) + rng.randf_range(-0.03, 0.03)
		rim.append(Vector2(cos(a), sin(a)) * radius * wob)
	var top_y := 0.0
	# top: a gentle dome, fanned from the middle
	var cen := Vector3(0, top_y + radius * 0.04, 0)
	for i in n:
		var a2: Vector2 = rim[i]; var b2: Vector2 = rim[(i + 1) % n]
		var a := Vector3(a2.x, top_y, a2.y); var b := Vector3(b2.x, top_y, b2.y)
		var ca := top_c.darkened(0.06 + 0.05 * sin(TAU * i / n * 3.0 + ph)); var cb := top_c.darkened(0.06 + 0.05 * sin(TAU * (i + 1) / n * 3.0 + ph))
		st.set_normal(Vector3.UP)
		st.set_color(top_c.lightened(0.05)); st.add_vertex(cen)
		st.set_color(ca); st.add_vertex(a)
		st.set_color(cb); st.add_vertex(b)
	# cliffs: rings shrinking toward a point, with a jagged edge
	var rings := 7
	var prev: Array = []
	for i in n:
		prev.append(Vector3(rim[i].x, top_y, rim[i].y))
	for k in range(1, rings + 1):
		var t := float(k) / rings
		var ring: Array = []
		var shrink := pow(1.0 - t, 1.5) if k < rings else 0.0
		var y := top_y - (0.22 if k == 1 else depth * pow(t, 0.85))
		for i in n:
			var aa := TAU * i / n
			var jag := 0.92 + 0.1 * sin(aa * 5.0 + k * 1.3 + ph) + 0.06 * sin(aa * 11.0 - k * 0.7)
			var r2: Vector2 = rim[i] * (0.97 if k == 1 else shrink * jag)
			ring.append(Vector3(r2.x, y + (sin(aa * 4.0 + k + ph) * depth * 0.05 if k > 1 else 0.0), r2.y))
		var c0: Color = (top_c.darkened(0.1) if k == 1 else side_c.lerp(deep_c, float(k - 1) / rings))
		var c1: Color = (top_c.darkened(0.1) if k == 1 else side_c.lerp(deep_c, float(k) / rings))
		for i in n:
			var a: Vector3 = prev[i]; var b: Vector3 = prev[(i + 1) % n]
			var c: Vector3 = ring[(i + 1) % n]; var d: Vector3 = ring[i]
			var nrm := (d - a).cross(b - a).normalized()
			if nrm.dot(Vector3(a.x, 0, a.z)) < 0.0: nrm = -nrm
			st.set_normal(nrm)
			st.set_color(c0); st.add_vertex(a)
			st.set_color(c0); st.add_vertex(b)
			st.set_color(c1); st.add_vertex(c)
			st.set_color(c0); st.add_vertex(a)
			st.set_color(c1); st.add_vertex(c)
			st.set_color(c1); st.add_vertex(d)
		prev = ring
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = World.terrain_material()
	mi.set_meta("rim", rim)
	return mi

## A curtain of water pouring off an island edge, with mist where it fades out.
static func waterfall(width: float, height: float) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new(); qm.size = Vector2(width, height)
	mi.mesh = qm
	var m := ShaderMaterial.new(); m.shader = load("res://shaders/waterfall.gdshader")
	mi.material_override = m
	mi.position = Vector3(0, -height * 0.5, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var p := CPUParticles3D.new()
	p.amount = 24; p.lifetime = 2.0; p.preprocess = 2.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX; p.emission_box_extents = Vector3(width * 0.4, 0.3, 0.3)
	p.direction = Vector3(0, 1, 0); p.spread = 60.0; p.initial_velocity_min = 0.3; p.initial_velocity_max = 0.8
	p.gravity = Vector3(0, -0.2, 0)
	p.scale_amount_min = 1.0; p.scale_amount_max = 2.5
	p.mesh = sphere(0.25, 6)
	p.material_override = glow_mat(Color(0.9, 0.95, 1.0, 0.25))
	p.position = Vector3(0, -height * 0.8, 0)
	root.add_child(p)
	return root

static func skyship() -> Node3D:
	var root := Node3D.new()
	var wood := toon(Color("7a5236")); var dark := toon(Color("4e3424")); var cloth := toon(Color("f2e6cf"))
	var stripe := toon(Color("d9604a")); var brass := toon(Color("e0b84a"), true, 0.3)
	# the balloon
	part(root, sphere(2.6, 22), cloth, Vector3(0, 4.2, 0), Vector3(1.0, 0.8, 1.9))
	for i in 3:
		part(root, cyl(2.08 * (1.0 - absf(i - 1) * 0.18), 2.08 * (1.0 - absf(i - 1) * 0.18), 0.32, 22), stripe, Vector3(0, 4.2, -2.2 + i * 2.2), Vector3(1, 1, 0.82), Vector3(PI / 2, 0, 0))
	# ribbons running nose to tail over the top, so it reads from the bird's-eye camera too
	for rz in [-0.42, 0.0, 0.42]:
		part(root, sphere(2.63, 22), stripe if rz == 0.0 else toon(Color("f2c84a")), Vector3(0, 4.2, 0), Vector3(0.09, 0.84, 1.92), Vector3(0, 0, rz))
	part(root, sphere(0.5, 12), brass, Vector3(0, 6.3, 0), Vector3(1.0, 0.4, 1.0))
	# ropes
	for x in [-1.0, 1.0]:
		for z in [-1.6, 1.6]:
			part(root, cyl(0.03, 0.03, 2.4, 6), dark, Vector3(x * 0.9, 2.0, z), Vector3.ONE, Vector3(0, 0, x * 0.25))
	# the hull
	part(root, box(2.0, 0.7, 4.4), wood, Vector3(0, 0.35, 0))
	part(root, box(2.2, 0.18, 4.6), dark, Vector3(0, 0.75, 0))
	part(root, cyl(0.6, 0.2, 2.0, 12), wood, Vector3(0, 0.35, -2.8), Vector3(1.6, 1, 0.5), Vector3(PI / 2, 0, 0))
	# propellers at the back
	for x in [-1.3, 1.3]:
		var hub := Node3D.new(); hub.name = "Prop%s" % ("L" if x < 0 else "R"); hub.position = Vector3(x, 0.6, 2.4)
		root.add_child(hub)
		part(hub, cyl(0.12, 0.12, 0.3, 10), brass, Vector3.ZERO, Vector3.ONE, Vector3(PI / 2, 0, 0))
		for b in 3:
			part(hub, box(0.12, 1.1, 0.04), wood, Vector3.ZERO, Vector3.ONE, Vector3(0, 0, TAU * b / 3.0))
	part(root, box(0.1, 1.2, 0.8), stripe, Vector3(0, 1.3, 2.3))
	return root
