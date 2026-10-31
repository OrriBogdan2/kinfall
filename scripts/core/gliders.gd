class_name Gliders
## Glider skins: a canopy shape and colours, a trail, and its own sounds when it opens and closes.
## Bought with gems at the glider rack by the portal, or earned. Purely cosmetic.
##   cloth / stripe / edge: colours ("team" and "hero" mean the hunter's own colours)
##   shape: wing | leaf | bat | kite | moth      trail: "" | leaves | embers | sparkle | dust | sparks
##   sound: cloth | rustle | leather | chime | flame | flutter | zap  (gentle whooshes, see Synth.glider)
##   cost: gems; unlock: "stat:n" earned instead (Progress.stat), e.g. "extracts:10"

const LIST := [
	{"id": "classic", "name": "Field Wing", "desc": "The standard-issue striped wing every hunter starts with.",
		"cloth": "f3eee2", "stripe": "team", "edge": "hero", "shape": "wing", "trail": "", "sound": "cloth", "cost": 0},
	{"id": "sunset", "name": "Sunset Kite", "desc": "Warm stripes that catch the evening light.",
		"cloth": "ffd6a0", "stripe": "ff7a4a", "edge": "8a3a6a", "shape": "wing", "trail": "", "sound": "cloth", "cost": 120},
	{"id": "leaf", "name": "Great Leaf", "desc": "A giant leaf, veins and all. It rustles when it opens.",
		"cloth": "7ad06a", "stripe": "3f8a3a", "edge": "2a5a2a", "shape": "leaf", "trail": "leaves", "sound": "rustle", "cost": 180},
	{"id": "moth", "name": "Moonmoth", "desc": "Soft, dusty moth wings with eye spots. Flutters open.",
		"cloth": "e8dcc8", "stripe": "6a5a8a", "edge": "4a3a5a", "shape": "moth", "trail": "dust", "sound": "flutter", "cost": 260},
	{"id": "bat", "name": "Nightwing", "desc": "Scalloped bat wings that open with a leathery snap.",
		"cloth": "3a2a4a", "stripe": "6a4a8a", "edge": "1a1224", "shape": "bat", "trail": "", "sound": "leather", "cost": 300},
	{"id": "prism", "name": "Prism Sail", "desc": "Glass-clear panels that chime as they unfold.",
		"cloth": "c8f0ff", "stripe": "9ad0ff", "edge": "ffffff", "shape": "kite", "trail": "sparkle", "sound": "chime", "cost": 380},
	{"id": "ember", "name": "Ember Wing", "desc": "Smoulders the whole way down. Opens with a whump of flame.",
		"cloth": "ff8a3a", "stripe": "ffd23f", "edge": "8a2a1a", "shape": "wing", "trail": "embers", "sound": "flame", "cost": 450},
	{"id": "storm", "name": "Stormcatcher", "desc": "Crackles with static every time it catches the wind. Earned: extract 10 times.",
		"cloth": "2f3c78", "stripe": "9af0ff", "edge": "ffe85a", "shape": "kite", "trail": "sparks", "sound": "zap", "unlock": "extracts:10"},
]

static func get_skin(id: String) -> Dictionary:
	for g in LIST:
		if g["id"] == id: return g
	return LIST[0]

static func owned(id: String) -> bool:
	var g := get_skin(id)
	if int(g.get("cost", 0)) == 0 and not g.has("unlock"):
		return true
	if g.has("unlock"):
		var p := String(g["unlock"]).split(":")
		if Progress.stat(p[0]) >= int(p[1]):
			return true
	return Save.d.get("gliders", []).has(id)

static func equipped() -> String:
	var id := String(Save.d.get("look", {}).get("glider", "classic"))
	return id if owned(id) else "classic"

static func col(spec: String, team: Color, hero: Color) -> Color:
	match spec:
		"team": return team
		"hero": return hero
	return Color(spec)

## The canopy mesh for a skin: a smooth, billowing sheet (arched across the span, cambered front to
## back like a real paraglider cell), two-sided, with normals from the curve so it shades softly.
static var _meshes := {}
static func mesh(id: String, team: Color, hero: Color) -> ArrayMesh:
	var key := "%s|%s|%s" % [id, team.to_html(), hero.to_html()]
	if _meshes.has(key):
		return _meshes[key]
	var am := _build(id, team, hero)
	_meshes[key] = am
	return am

static func _build(id: String, team: Color, hero: Color) -> ArrayMesh:
	var g := get_skin(id)
	var cloth := col(g["cloth"], team, hero)
	var stripe := col(g["stripe"], team, hero)
	var edge := col(g["edge"], team, hero)
	var shape := String(g["shape"])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 18       # pattern cells across the span
	var rows := 3        # front-to-back pattern strips, so patterns can be spots and veins, not just stripes
	var sub_x := 2       # geometry steps per cell, for a smooth curve
	var sub_z := 3
	var span := 1.05 if shape != "moth" else 1.12
	var th := 0.012
	for side in [1.0, -1.0]:
		for k in segs:
			var um := absf(-span + 2.0 * span * (k + 0.5) / segs) / span
			for j in rows:
				var c := _pattern(shape, k, j, segs, um, cloth, stripe, edge)
				st.set_color(c)
				for sx in sub_x:
					for sz in sub_z:
						var x0 := -span + 2.0 * span * (k + float(sx) / sub_x) / segs
						var x1 := -span + 2.0 * span * (k + float(sx + 1) / sub_x) / segs
						var t0 := (j + float(sz) / sub_z) / rows
						var t1 := (j + float(sz + 1) / sub_z) / rows
						var q := [[x0, t0], [x0, t1], [x1, t0], [x1, t1]]
						var pts := []
						var nrm := []
						for e in q:
							pts.append(_surf(shape, span, e[0], e[1]) + Vector3(0, side * th, 0))
							nrm.append(_surf_n(shape, span, e[0], e[1]) * side)
						var order := [0, 2, 3, 0, 3, 1] if side > 0.0 else [0, 3, 2, 0, 1, 3]
						for i in order:
							st.set_normal(nrm[i])
							st.add_vertex(pts[i])
	st.index()
	return st.commit()

## The canopy's outline at x: [height, how far it reaches forward, how far back].
static func _outline_at(shape: String, span: float, x: float) -> Array:
	var u: float = minf(absf(x) / span, 1.0)
	var y: float = -0.32 * u * u
	var lead := 0.0
	var trail := 0.0
	match shape:
		"wing":
			var ch := 0.42 * sqrt(maxf(0.0, 1.0 - pow(u, 3.0))) + 0.05
			lead = ch * 0.55; trail = ch * 0.45
		"leaf":
			var ch2 := 0.62 * sqrt(maxf(0.0, 1.0 - u * u)) + 0.02
			lead = ch2 * 0.5; trail = ch2 * 0.5
			y = -0.22 * u * u
		"bat":
			lead = 0.24 * (1.0 - u * 0.5) + 0.04
			# the trailing edge scallops between the finger bones
			trail = 0.26 * (1.0 - u * 0.4) - 0.13 * absf(sin(u * PI * 3.0))
		"kite":
			lead = 0.5 * (1.0 - u) + 0.04
			trail = 0.3 * (1.0 - u) + 0.02
			y = -0.18 * u
		"moth":
			# two lobes a side: a big forewing and a smaller hindwing
			var fore := 0.34 * sin(PI * clampf(u / 0.95, 0.0, 1.0)) + 0.06
			var hind := 0.3 * sin(PI * clampf((u - 0.05) / 0.6, 0.0, 1.0))
			lead = fore * 0.9 + 0.05; trail = maxf(0.1, hind) + 0.05
			y = -0.2 * u * u
	return [y, lead, trail]

## A point on the canopy: x across the span, t from the leading edge (0) to the trailing edge (1).
## The cloth bellies up between the edges (an airfoil's camber), less toward the tips.
static func _surf(shape: String, span: float, x: float, t: float) -> Vector3:
	var o := _outline_at(shape, span, x)
	var z := lerpf(-float(o[1]), float(o[2]), t)
	var u := minf(absf(x) / span, 1.0)
	var camber := (0.055 if shape in ["wing", "kite"] else 0.035) * sin(PI * clampf(t, 0.0, 1.0)) * (1.0 - u * u * 0.7)
	camber *= 0.35 + 0.65 * smoothstep(0.0, 0.35, t)     # the nose is rounder than the tail
	return Vector3(x, float(o[0]) + camber, z)

static func _surf_n(shape: String, span: float, x: float, t: float) -> Vector3:
	var e := 0.01
	var dx := _surf(shape, span, x + e, t) - _surf(shape, span, x - e, t)
	var dt := _surf(shape, span, x, minf(t + e, 1.0)) - _surf(shape, span, x, maxf(t - e, 0.0))
	var n := dt.cross(dx).normalized()
	if n.y < 0.0: n = -n
	return n

## The colour of one patch of canopy: k across the span, j front (0) to back.
static func _pattern(shape: String, k: int, j: int, segs: int, um: float, cloth: Color, stripe: Color, edge: Color) -> Color:
	match shape:
		"wing":
			return stripe if k % 4 == 1 or k % 4 == 2 else (edge if k == 0 or k == segs - 1 else cloth)
		"leaf":
			if k == segs / 2 - 1 or k == segs / 2: return stripe          # the midrib
			if j == 1 and k % 3 == 0: return cloth.lerp(stripe, 0.55)      # side veins
			return edge if um > 0.88 else cloth
		"bat":
			if k % 3 == 0: return stripe                                     # the finger bones
			return cloth.lerp(edge, 0.25 * j)
		"kite":
			if um > 0.8: return edge
			return stripe if (k + j) % 2 == 0 else cloth                    # a harlequin of panels
		"moth":
			if um > 0.9: return edge
			if j == 1 and absf(um - 0.5) < 0.12: return stripe              # an eye spot on each wing
			if j == 1 and absf(um - 0.5) < 0.2: return stripe.lerp(cloth, 0.55)
			return cloth.lerp(edge, 0.12 * j)
	return cloth

## A trail of particles behind the glider while it's open (or null for none).
static func trail(id: String, team: Color, hero: Color) -> CPUParticles3D:
	var g := get_skin(id)
	var kind := String(g["trail"])
	if kind == "":
		return null
	var p := CPUParticles3D.new()
	p.name = "Trail"
	p.local_coords = false
	p.amount = 18
	p.lifetime = 1.1
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.9, 0.05, 0.1)
	p.direction = Vector3(0, -0.3, 1)
	p.spread = 25.0
	p.initial_velocity_min = 0.3; p.initial_velocity_max = 0.9
	p.gravity = Vector3(0, -0.6, 0)
	p.scale_amount_min = 0.5; p.scale_amount_max = 1.0
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var q := QuadMesh.new(); q.size = Vector2(0.09, 0.09); q.material = m
	p.mesh = q
	var c0 := col(g["stripe"], team, hero)
	var grad := Gradient.new()
	match kind:
		"embers":
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			grad.set_color(0, Color(1, 0.85, 0.4, 1)); grad.set_color(1, Color(0.9, 0.2, 0.05, 0))
			p.gravity = Vector3(0, 0.8, 0)
		"sparkle", "sparks":
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			grad.set_color(0, Color(c0, 1)); grad.set_color(1, Color(c0, 0))
			p.lifetime = 0.6; p.amount = 22
			q.size = Vector2(0.06, 0.06)
		"leaves":
			grad.set_color(0, Color(c0.lightened(0.2), 1)); grad.set_color(1, Color(c0, 0))
			q.size = Vector2(0.12, 0.07)
			p.angular_velocity_min = -180.0; p.angular_velocity_max = 180.0
			p.amount = 8; p.lifetime = 1.6
		"dust":
			grad.set_color(0, Color(1, 0.97, 0.9, 0.7)); grad.set_color(1, Color(1, 0.97, 0.9, 0))
			p.amount = 14; p.lifetime = 1.4
	p.color_ramp = grad
	return p

# ---------------------------------------------------------------- sounds, made in code
static var _cache := {}

## The open (or close) sound of a skin's sound set.
static func sound(id: String, which := "open") -> AudioStreamWAV:
	var set := String(get_skin(id)["sound"])
	var key := set + "|" + which
	if not _cache.has(key):
		_cache[key] = _make(set, which == "close")
	return _cache[key]

## Made in code by Synth.glider: a soft airy whoosh flavoured by the set, never a snap.
static func _make(set: String, close: bool) -> AudioStreamWAV:
	return Synth.glider(set, close)
