class_name KinModels
## The bodies of the six kin species. Each one is built from one or two real animals and an
## element of its own (none of the usual fire / water / leaf):
##   Vespyx   (cindle)  fox + scorpion          Venom
##   Prismander (puddlet) axolotl + crystal frills Prism
##   Mycroll  (burrlet) hedgehog + glowing toadstool quills  Spore
##   Echolop  (zapple)  long-eared hare + bat   Echo
##   Gravadillo (pebbit) armadillo + rhino beetle Gravity
##   Lunowl   (wisplet) owl + luna moth         Lunar
## and the three rare kin from boss eggs:
##   Cairnback (cairnback) tortoise + ibex, a rune cairn on its shell    Titan    (the Stone Colossus)
##   Zephyrak  (zephyrak)  moray eel + swift, a little sky serpent       Tempest  (Stormcoil)
##   Hivara    (hivara)    honeybee + praying mantis, a wax crown        Swarm    (the Brood Mother)
##
## Everything goes under `flex` (the part KinPuppet squashes). Front is -z, the ground is y = 0, and
## the whole kin stays about 0.8 tall so worn accessories and evolution parts still sit right.
## Named nodes the puppet animates: EyeL/EyeR + ShineL/ShineR, Tail, Ears, Legs/Leg*, Wings/Wing*, Spin.
## Returns where things ended up: {"head": Vector3 (eye level, front), "top": float (top of head)}.


## A cylinder from a to b.
static func seg(parent: Node3D, a: Vector3, b: Vector3, r0: float, r1: float, mat: Material, sides := 8) -> MeshInstance3D:
	var mi := Models.part(parent, Models.cyl(r1, r0, a.distance_to(b), sides), mat, (a + b) * 0.5)
	var d := (b - a).normalized()
	if absf(d.dot(Vector3.UP)) > 0.999:
		mi.basis = Basis.IDENTITY if d.y > 0 else Basis(Vector3.RIGHT, PI)
	else:
		mi.basis = Basis(Quaternion(Vector3.UP, d))
	return mi

## A leg on its own hip pivot (so the puppet can swing it): thigh, shin and a paw.
static func leg(legs: Node3D, nm: String, hip: Vector3, length: float, r: float, mat: Material, paw: Material, splay := 0.0) -> void:
	var l := Node3D.new(); l.name = nm; l.position = hip; legs.add_child(l)
	var foot := Vector3(splay, -length, 0)
	seg(l, Vector3.ZERO, foot, r, r * 0.8, mat)
	Models.part(l, Models.sphere(r * 1.25, 8), paw, foot + Vector3(0, 0.01, -r * 0.4), Vector3(1.0, 0.65, 1.35))

## Big glossy eyes with a catch light (the puppet blinks them).
## Eyes set into the surface of a head (an ellipsoid at `center` with these radii), `spread` apart
## to the sides and `up` above the middle.
static func eyes(flex: Node3D, center: Vector3, radii: Vector3, spread: float, up: float, size: float, m_eye: Material, m_white: Material) -> void:
	for sx in [-1.0, 1.0]:
		var sd := "L" if sx < 0.0 else "R"
		var d := Vector3(sx * spread, up, -1.0).normalized()
		var p := center + Vector3(d.x * radii.x, d.y * radii.y, d.z * radii.z) * 0.96
		Models.part(flex, Models.sphere(size, 10), m_eye, p, Vector3(1, 1.15, 0.8), Vector3.ZERO, "Eye" + sd)
		Models.part(flex, Models.sphere(size * 0.36, 6), m_white, p + Vector3(size * 0.35, size * 0.45, -size * 0.6), Vector3.ONE, Vector3.ZERO, "Shine" + sd)

static func build(species: String, flex: Node3D, c: Dictionary, mats: Array) -> Dictionary:
	match species:
		"cindle": return _vespyx(flex, c, mats)
		"puddlet": return _prismander(flex, c, mats)
		"burrlet": return _mycroll(flex, c, mats)
		"zapple": return _echolop(flex, c, mats)
		"pebbit": return _gravadillo(flex, c, mats)
		"wisplet": return _lunowl(flex, c, mats)
		# the rare kin, hatched only from a lair boss's egg
		"cairnback": return _cairnback(flex, c, mats)
		"zephyrak": return _zephyrak(flex, c, mats)
		"hivara": return _hivara(flex, c, mats)
	return {}

# ---------------------------------------------------------------- Vespyx: fox + scorpion, Venom
static func _vespyx(f: Node3D, c: Dictionary, mats: Array) -> Dictionary:
	var body: Material = c["body"]; var belly: Material = c["belly"]; var dark: Material = c["dark"]; var glow: Material = c["glow"]
	# a lean fox body, chest out front
	Models.part(f, Models.capsule(0.17, 0.62), body, Vector3(0, 0.34, 0.02), Vector3(1.0, 0.95, 1.0), Vector3(PI / 2 - 0.12, 0, 0))
	Models.part(f, Models.sphere(0.15), belly, Vector3(0, 0.3, -0.18), Vector3(0.95, 1.0, 0.9))
	# head: a fox face with a long pointed snout and a dark nose
	var hp := Vector3(0, 0.5, -0.27)
	Models.part(f, Models.sphere(0.16), body, hp, Vector3(1.05, 0.92, 1.0))
	Models.part(f, Models.sphere(0.11), belly, hp + Vector3(0, -0.05, -0.06), Vector3(1.2, 0.8, 0.9))
	seg(f, hp + Vector3(0, -0.03, -0.08), hp + Vector3(0, -0.06, -0.26), 0.08, 0.025, body)
	Models.part(f, Models.sphere(0.032, 8), dark, hp + Vector3(0, -0.055, -0.27))
	eyes(f, hp, Vector3(0.168, 0.147, 0.16), 0.55, 0.3, 0.042, c["eye"], c["white"])
	# claws: two small scorpion pincers held up in front
	for sx in [-1.0, 1.0]:
		var base := Vector3(0.13 * sx, 0.28, -0.2)
		var tip := base + Vector3(0.06 * sx, 0.04, -0.17)
		seg(f, base, tip, 0.035, 0.03, dark)
		Models.part(f, Models.sphere(0.06, 8), dark, tip + Vector3(0, 0, -0.03), Vector3(0.8, 0.7, 1.3))
		Models.part(f, Models.cyl(0.0, 0.025, 0.08, 6), dark, tip + Vector3(0.025 * sx, 0.02, -0.1), Vector3.ONE, Vector3(-PI / 2, 0, 0))
	# legs
	var legs := Node3D.new(); legs.name = "Legs"; f.add_child(legs)
	for i in 4:
		var sx := -1.0 if i % 2 == 0 else 1.0
		var z := -0.12 if i < 2 else 0.2
		leg(legs, "Leg%d" % i, Vector3(0.1 * sx, 0.24, z), 0.22, 0.035, body, dark)
	# big triangular fox ears with dark tips
	var ears := Node3D.new(); ears.name = "Ears"; f.add_child(ears)
	for sx in [-1.0, 1.0]:
		var e := Models.part(ears, Models.cyl(0.0, 0.07, 0.2, 4), body, Vector3(0.09 * sx, 0.14, 0.0), Vector3(1.0, 1.0, 0.45), Vector3(0, 0.6 * sx, 0.3 * sx))
		e.rotation = Vector3(-0.15, 0, -0.32 * sx)
		Models.part(ears, Models.cyl(0.0, 0.028, 0.07, 4), dark, Vector3(0.12 * sx, 0.24, 0.0), Vector3(1, 1, 0.5), Vector3(-0.15, 0, -0.32 * sx))
	ears.position = hp + Vector3(0, 0.1, 0.02)
	# the scorpion tail: segments arching up and forward over the back, a glowing stinger
	var tail := Node3D.new(); tail.name = "Tail"; f.add_child(tail)
	var pts := [Vector3(0, 0.36, 0.32), Vector3(0, 0.5, 0.42), Vector3(0, 0.68, 0.4), Vector3(0, 0.82, 0.3), Vector3(0, 0.88, 0.16)]
	for i in pts.size() - 1:
		var r := 0.065 - i * 0.008
		seg(tail, pts[i], pts[i + 1], r, r - 0.008, body if i % 2 == 0 else dark)
		Models.part(tail, Models.sphere(r * 1.05, 8), body, pts[i + 1])
	var st: Vector3 = pts[pts.size() - 1]
	Models.part(tail, Models.sphere(0.06, 10), glow, st + Vector3(0, -0.01, -0.03), Vector3(1, 1, 1.3))
	seg(tail, st + Vector3(0, -0.02, -0.06), st + Vector3(0, -0.12, -0.14), 0.03, 0.002, dark)
	Models._repivot(tail, Vector3(0, 0.36, 0.3))
	return {"head": hp, "top": hp.y + 0.2}

# ---------------------------------------------------------------- Prismander: axolotl, Prism
static func _prismander(f: Node3D, c: Dictionary, mats: Array) -> Dictionary:
	var body: Material = c["body"]; var belly: Material = c["belly"]; var dark: Material = c["dark"]; var glow: Material = c["glow"]
	# a low, long body that sits close to the ground
	Models.part(f, Models.capsule(0.15, 0.66), body, Vector3(0, 0.2, 0.06), Vector3(1.15, 0.85, 1.0), Vector3(PI / 2, 0, 0))
	Models.part(f, Models.capsule(0.11, 0.5), belly, Vector3(0, 0.15, 0.02), Vector3(1.2, 0.6, 1.0), Vector3(PI / 2, 0, 0))
	# a wide, flat head with a long smile
	var hp := Vector3(0, 0.3, -0.27)
	Models.part(f, Models.sphere(0.2), body, hp, Vector3(1.25, 0.8, 1.0))
	var smile := TorusMesh.new(); smile.inner_radius = 0.13; smile.outer_radius = 0.145; smile.rings = 16; smile.ring_segments = 4
	var sm := Models.part(f, smile, dark, hp + Vector3(0, -0.06, -0.06), Vector3(1.0, 1.0, 0.5))
	sm.visible = true
	eyes(f, hp, Vector3(0.25, 0.16, 0.2), 0.9, 0.35, 0.04, c["eye"], c["white"])
	# crystal gills: three glowing prisms fanned out on each side of the head
	var ears := Node3D.new(); ears.name = "Ears"; f.add_child(ears)
	var pm := PrismMesh.new(); pm.size = Vector3(0.07, 0.24, 0.05)
	for sx in [-1.0, 1.0]:
		for i in 3:
			var a := -0.7 + i * 0.55
			Models.part(ears, pm, glow, Vector3(0.22 * sx + cos(a) * 0.06 * sx, sin(a) * 0.08, 0.02 * i), Vector3(1, 1.0 - absf(i - 1) * 0.18, 1), Vector3(0, 0, (-1.2 + i * 0.45) * sx))
	ears.position = hp + Vector3(0, 0.06, 0.06)
	# four short splayed legs with little fingers
	var legs := Node3D.new(); legs.name = "Legs"; f.add_child(legs)
	for i in 4:
		var sx := -1.0 if i % 2 == 0 else 1.0
		var z := -0.12 if i < 2 else 0.24
		leg(legs, "Leg%d" % i, Vector3(0.16 * sx, 0.16, z), 0.13, 0.04, body, belly, 0.05 * sx)
	# a dorsal crystal ridge down the back
	var shard := PrismMesh.new(); shard.size = Vector3(0.05, 0.12, 0.08)
	for i in 4:
		Models.part(f, shard, glow, Vector3(0, 0.33 - i * 0.01, -0.06 + i * 0.11), Vector3.ONE * (1.0 - i * 0.12))
	# a long tapering tail with a clear fin
	var tail := Node3D.new(); tail.name = "Tail"; f.add_child(tail)
	seg(tail, Vector3(0, 0.2, 0.36), Vector3(0, 0.22, 0.7), 0.09, 0.03, body)
	Models.part(tail, Models.box(0.015, 0.16, 0.36), glow, Vector3(0, 0.24, 0.58), Vector3.ONE, Vector3(0.08, 0, 0))
	Models._repivot(tail, Vector3(0, 0.2, 0.36))
	return {"head": hp, "top": hp.y + 0.16}

# ---------------------------------------------------------------- Mycroll: hedgehog + toadstools, Spore
static func _mycroll(f: Node3D, c: Dictionary, mats: Array) -> Dictionary:
	var body: Material = c["body"]; var belly: Material = c["belly"]; var dark: Material = c["dark"]; var glow: Material = c["glow"]
	# a round hedgehog body, a soft face and a pointed nose
	Models.part(f, Models.sphere(0.3), body, Vector3(0, 0.3, 0.06), Vector3(1.05, 0.88, 1.15))
	var hp := Vector3(0, 0.3, -0.24)
	Models.part(f, Models.sphere(0.15), belly, hp, Vector3(1.05, 0.95, 1.0))
	seg(f, hp + Vector3(0, -0.02, -0.08), hp + Vector3(0, -0.04, -0.22), 0.07, 0.02, belly)
	Models.part(f, Models.sphere(0.03, 8), dark, hp + Vector3(0, -0.04, -0.23))
	eyes(f, hp, Vector3(0.158, 0.143, 0.15), 0.5, 0.35, 0.036, c["eye"], c["white"])
	# instead of quills: a forest of little glowing toadstools all over its back
	var cap: Material = glow
	var stalk: Material = belly
	var rng := RandomNumberGenerator.new(); rng.seed = 4711
	for i in 16:
		var a := rng.randf_range(-PI * 0.95, PI * 0.95)
		var up := rng.randf_range(0.25, 1.0)
		var dir := Vector3(sin(a) * (1.0 - up * 0.6), up, cos(a) * (1.0 - up * 0.6) + 0.35).normalized()
		if dir.z < -0.25:
			continue
		var at := Vector3(0, 0.3, 0.06) + Vector3(dir.x * 0.31, dir.y * 0.26, dir.z * 0.33)
		var h := rng.randf_range(0.06, 0.12)
		seg(f, at, at + dir * h, 0.018, 0.014, stalk, 6)
		var cr := rng.randf_range(0.045, 0.075)
		var cm := Models.part(f, Models.sphere(cr, 8), cap, at + dir * (h + cr * 0.2), Vector3(1.0, 0.55, 1.0))
		cm.basis = Basis(Quaternion(Vector3.UP, dir)).scaled(Vector3(1.0, 0.55, 1.0))
	# round little ears
	var ears := Node3D.new(); ears.name = "Ears"; f.add_child(ears)
	for sx in [-1.0, 1.0]:
		Models.part(ears, Models.sphere(0.05, 8), belly, Vector3(0.11 * sx, 0.0, 0.0), Vector3(1, 1, 0.5))
	ears.position = hp + Vector3(0, 0.12, 0.05)
	var legs := Node3D.new(); legs.name = "Legs"; f.add_child(legs)
	for i in 4:
		var sx := -1.0 if i % 2 == 0 else 1.0
		var z := -0.1 if i < 2 else 0.22
		leg(legs, "Leg%d" % i, Vector3(0.14 * sx, 0.12, z), 0.1, 0.035, belly, dark)
	# a stubby tail with one big toadstool on it
	var tail := Node3D.new(); tail.name = "Tail"; f.add_child(tail)
	Models.part(tail, Models.sphere(0.05, 8), body, Vector3(0, 0.2, 0.42))
	seg(tail, Vector3(0, 0.22, 0.43), Vector3(0, 0.34, 0.5), 0.02, 0.016, stalk, 6)
	Models.part(tail, Models.sphere(0.07, 10), cap, Vector3(0, 0.36, 0.51), Vector3(1.1, 0.55, 1.1))
	Models._repivot(tail, Vector3(0, 0.2, 0.4))
	return {"head": hp, "top": 0.62}

# ---------------------------------------------------------------- Echolop: hare + bat, Echo
static func _echolop(f: Node3D, c: Dictionary, mats: Array) -> Dictionary:
	var body: Material = c["body"]; var belly: Material = c["belly"]; var dark: Material = c["dark"]; var glow: Material = c["glow"]
	# a sitting hare: a pear-shaped body, big feet, a fluffy chest
	Models.part(f, Models.sphere(0.24), body, Vector3(0, 0.26, 0.06), Vector3(1.0, 1.1, 1.1))
	Models.part(f, Models.sphere(0.16), belly, Vector3(0, 0.3, -0.1), Vector3(1.0, 1.1, 0.8))
	var hp := Vector3(0, 0.5, -0.1)
	Models.part(f, Models.sphere(0.15), body, hp, Vector3(1.05, 0.95, 1.0))
	Models.part(f, Models.sphere(0.06, 8), belly, hp + Vector3(0, -0.06, -0.12), Vector3(1.4, 0.8, 0.8))
	Models.part(f, Models.sphere(0.022, 6), dark, hp + Vector3(0, -0.03, -0.15))
	eyes(f, hp, Vector3(0.158, 0.143, 0.15), 0.5, 0.2, 0.04, c["eye"], c["white"])
	# little bat fangs
	for sx in [-1.0, 1.0]:
		Models.part(f, Models.cyl(0.0, 0.012, 0.035, 6), c["white"], hp + Vector3(0.025 * sx, -0.1, -0.12), Vector3.ONE, Vector3(PI, 0, 0))
	# huge ears: long hare ears with bat-like ribbed inner skin and a glowing echo rim
	var ears := Node3D.new(); ears.name = "Ears"; f.add_child(ears)
	for sx in [-1.0, 1.0]:
		var e := Node3D.new(); e.position = Vector3(0.07 * sx, 0.0, 0.0); e.rotation = Vector3(0.12, 0, -0.22 * sx); ears.add_child(e)
		Models.part(e, Models.sphere(0.07), body, Vector3(0, 0.2, 0), Vector3(0.9, 3.0, 0.38))
		Models.part(e, Models.sphere(0.055), belly, Vector3(0, 0.2, -0.018), Vector3(0.8, 2.6, 0.2))
		for k in 3:
			Models.part(e, Models.box(0.008, 0.11, 0.008), dark, Vector3(0, 0.12 + k * 0.08, -0.03), Vector3.ONE, Vector3(0, 0, (k - 1) * 0.25))
		var rim := TorusMesh.new(); rim.inner_radius = 0.05; rim.outer_radius = 0.06; rim.rings = 12; rim.ring_segments = 4
		Models.part(e, rim, glow, Vector3(0, 0.4, 0), Vector3(1, 1, 1), Vector3(PI / 2, 0, 0))
	ears.position = hp + Vector3(0, 0.12, 0.02)
	# folded bat wings on its sides
	var wings := Node3D.new(); wings.name = "Wings"; f.add_child(wings)
	for sx in [-1.0, 1.0]:
		var w := Node3D.new(); w.name = "Wing" + ("L" if sx < 0 else "R"); w.position = Vector3(0.2 * sx, 0.34, 0.06); wings.add_child(w)
		var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var pts := [Vector3.ZERO, Vector3(0.24 * sx, 0.1, 0.06), Vector3(0.3 * sx, -0.06, 0.12), Vector3(0.18 * sx, -0.12, 0.16), Vector3(0.08 * sx, -0.1, 0.12)]
		for j in range(1, pts.size() - 1):
			st.add_vertex(pts[0]); st.add_vertex(pts[j]); st.add_vertex(pts[j + 1])
		st.generate_normals()
		var memb := Models.toon(Color(c["wing_col"]), false)
		(memb as ShaderMaterial).set_shader_parameter("rim_amount", 0.4)
		var mi := MeshInstance3D.new(); mi.mesh = st.commit(); mi.material_override = memb; w.add_child(mi)
		var mm := StandardMaterial3D.new(); mm.cull_mode = BaseMaterial3D.CULL_DISABLED; mm.albedo_color = Color(c["wing_col"]); mm.roughness = 1.0
		mi.material_override = mm
		seg(w, Vector3.ZERO, pts[1], 0.012, 0.008, dark)
		seg(w, pts[1], pts[2], 0.01, 0.006, dark)
	# big hind feet, small front paws
	var legs := Node3D.new(); legs.name = "Legs"; f.add_child(legs)
	for sx in [-1.0, 1.0]:
		Models.part(legs, Models.sphere(0.07, 8), body, Vector3(0.14 * sx, 0.05, 0.02), Vector3(0.9, 0.55, 1.9))
		leg(legs, "Leg" + ("L" if sx < 0 else "R"), Vector3(0.08 * sx, 0.2, -0.14), 0.18, 0.028, body, belly)
	# a cotton tail
	var tail := Node3D.new(); tail.name = "Tail"; f.add_child(tail)
	Models.part(tail, Models.sphere(0.08, 10), belly, Vector3(0, 0.16, 0.32))
	Models._repivot(tail, Vector3(0, 0.16, 0.28))
	return {"head": hp, "top": hp.y + 0.15}

# ---------------------------------------------------------------- Gravadillo: armadillo + rhino beetle, Gravity
static func _gravadillo(f: Node3D, c: Dictionary, mats: Array) -> Dictionary:
	var body: Material = c["body"]; var belly: Material = c["belly"]; var dark: Material = c["dark"]; var glow: Material = c["glow"]
	# a heavy domed shell made of bands, with glowing seams between them
	Models.part(f, Models.sphere(0.3), belly, Vector3(0, 0.24, 0.04), Vector3(1.1, 0.75, 1.3))
	for i in 5:
		var z := -0.2 + i * 0.11
		var r := 0.34 - absf(i - 2) * 0.03
		var band := Models.part(f, Models.sphere(r), body, Vector3(0, 0.28, z), Vector3(1.0, 0.92, 0.36))
		band.rotation.x = (i - 2) * 0.12
		var seam := TorusMesh.new(); seam.inner_radius = r * 0.88; seam.outer_radius = r * 0.93; seam.rings = 20; seam.ring_segments = 4
		if i < 4:
			Models.part(f, seam, glow, Vector3(0, 0.28, z + 0.055), Vector3(1.0, 1.0, 0.92), Vector3(PI / 2, 0, 0))
	# a blunt armored head and a beetle horn curving up from the snout
	var hp := Vector3(0, 0.27, -0.36)
	Models.part(f, Models.sphere(0.13), body, hp, Vector3(1.0, 0.85, 1.2))
	Models.part(f, Models.sphere(0.08, 8), belly, hp + Vector3(0, -0.04, -0.1), Vector3(1.0, 0.8, 1.0))
	var hpts := [hp + Vector3(0, 0.02, -0.12), hp + Vector3(0, 0.12, -0.18), hp + Vector3(0, 0.25, -0.17), hp + Vector3(0, 0.33, -0.1)]
	for i in 3:
		seg(f, hpts[i], hpts[i + 1], 0.045 - i * 0.012, 0.035 - i * 0.012, dark)
	Models.part(f, Models.sphere(0.02, 6), glow, hpts[3])
	eyes(f, hp, Vector3(0.13, 0.11, 0.156), 0.6, 0.35, 0.032, c["eye"], c["white"])
	# small armored ears
	var ears := Node3D.new(); ears.name = "Ears"; f.add_child(ears)
	for sx in [-1.0, 1.0]:
		Models.part(ears, Models.cyl(0.0, 0.04, 0.09, 5), body, Vector3(0.1 * sx, 0.0, 0.0), Vector3.ONE, Vector3(0, 0, -0.5 * sx))
	ears.position = hp + Vector3(0, 0.12, 0.06)
	var legs := Node3D.new(); legs.name = "Legs"; f.add_child(legs)
	for i in 4:
		var sx := -1.0 if i % 2 == 0 else 1.0
		var z := -0.14 if i < 2 else 0.24
		leg(legs, "Leg%d" % i, Vector3(0.2 * sx, 0.14, z), 0.12, 0.05, dark, dark)
	# a banded tail
	var tail := Node3D.new(); tail.name = "Tail"; f.add_child(tail)
	for i in 3:
		Models.part(tail, Models.sphere(0.07 - i * 0.015, 8), body if i % 2 == 0 else dark, Vector3(0, 0.16 - i * 0.03, 0.44 + i * 0.09))
	Models._repivot(tail, Vector3(0, 0.17, 0.4))
	# pebbles caught in its pull, circling it
	var spin := Node3D.new(); spin.name = "Spin"; f.add_child(spin)
	spin.position = Vector3(0, 0.35, 0.04)
	for i in 3:
		var a := TAU * i / 3.0
		Models.part(spin, Models.box(0.06, 0.05, 0.06), dark, Vector3(cos(a) * 0.48, sin(a * 2.0) * 0.06, sin(a) * 0.48), Vector3.ONE, Vector3(a, a * 0.5, 0))
	return {"head": hp, "top": 0.52}

# ---------------------------------------------------------------- Lunowl: owl + luna moth, Lunar
static func _lunowl(f: Node3D, c: Dictionary, mats: Array) -> Dictionary:
	var body: Material = c["body"]; var belly: Material = c["belly"]; var dark: Material = c["dark"]; var glow: Material = c["glow"]
	# a round owl body that floats a little off the ground
	Models.part(f, Models.sphere(0.25), body, Vector3(0, 0.4, 0.04), Vector3(1.0, 1.15, 0.95))
	Models.part(f, Models.sphere(0.18), belly, Vector3(0, 0.37, -0.1), Vector3(1.0, 1.15, 0.7))
	# chest markings: little crescent moons
	for i in 3:
		var cres := TorusMesh.new(); cres.inner_radius = 0.025; cres.outer_radius = 0.035; cres.rings = 10; cres.ring_segments = 4
		Models.part(f, cres, glow, Vector3((i - 1) * 0.07, 0.3 + (i % 2) * 0.05, -0.22), Vector3(1, 1, 0.5), Vector3(PI / 2, 0, 0.6))
	# an owl face: a heart-shaped facial disc, huge round eyes and a little hooked beak
	var hp := Vector3(0, 0.6, -0.1)
	Models.part(f, Models.sphere(0.2), body, hp, Vector3(1.15, 0.95, 1.0))
	for sx in [-1.0, 1.0]:
		Models.part(f, Models.sphere(0.09, 12), belly, hp + Vector3(0.08 * sx, 0.0, -0.14), Vector3(1.0, 1.0, 0.4))
	eyes(f, hp, Vector3(0.23, 0.19, 0.24), 0.42, 0.05, 0.05, c["eye"], c["white"])
	Models.part(f, Models.cyl(0.0, 0.025, 0.07, 6), Models.toon(Color("e8c070")), hp + Vector3(0, -0.07, -0.2), Vector3.ONE, Vector3(PI * 0.85, 0, 0))
	# feathery moth antennae instead of ear tufts
	var ears := Node3D.new(); ears.name = "Ears"; f.add_child(ears)
	for sx in [-1.0, 1.0]:
		var a := Vector3(0.06 * sx, 0.0, 0.0)
		var b := Vector3(0.16 * sx, 0.2, -0.05)
		seg(ears, a, b, 0.01, 0.008, dark, 6)
		for k in 5:
			var p := a.lerp(b, 0.3 + k * 0.15)
			Models.part(ears, Models.box(0.08 - k * 0.01, 0.008, 0.012), glow, p, Vector3.ONE, Vector3(0, 0, 0.9 * sx))
	ears.position = hp + Vector3(0, 0.15, 0.02)
	# luna moth wings: broad pale forewings, long trailing hindwings, an eye-spot on each
	var wings := Node3D.new(); wings.name = "Wings"; f.add_child(wings)
	for sx in [-1.0, 1.0]:
		var w := Node3D.new(); w.name = "Wing" + ("L" if sx < 0 else "R"); w.position = Vector3(0.14 * sx, 0.48, 0.14); wings.add_child(w)
		var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var fore := [Vector3.ZERO, Vector3(0.22 * sx, 0.2, 0.02), Vector3(0.42 * sx, 0.18, 0.05), Vector3(0.4 * sx, 0.02, 0.08), Vector3(0.2 * sx, -0.06, 0.06)]
		var hind := [Vector3(0, -0.04, 0.02), Vector3(0.22 * sx, -0.1, 0.08), Vector3(0.3 * sx, -0.3, 0.16), Vector3(0.24 * sx, -0.44, 0.2), Vector3(0.08 * sx, -0.18, 0.08)]
		for poly in [fore, hind]:
			for j in range(1, poly.size() - 1):
				st.add_vertex(poly[0]); st.add_vertex(poly[j]); st.add_vertex(poly[j + 1])
		st.generate_normals()
		var mm := StandardMaterial3D.new(); mm.cull_mode = BaseMaterial3D.CULL_DISABLED; mm.albedo_color = Color(c["wing_col"]); mm.roughness = 1.0
		mm.rim_enabled = true; mm.rim = 0.5
		var mi := MeshInstance3D.new(); mi.mesh = st.commit(); mi.material_override = mm; w.add_child(mi)
		var spot := Models.part(w, Models.sphere(0.04, 8), glow, Vector3(0.28 * sx, 0.08, 0.06), Vector3(1, 1, 0.3))
		spot.rotation.y = 0.3 * sx
		Models.part(w, Models.sphere(0.018, 6), dark, Vector3(0.28 * sx, 0.08, 0.05), Vector3(1, 1, 0.3))
		seg(w, Vector3.ZERO, fore[2], 0.008, 0.005, dark, 5)
	# tucked talons, no walking legs: it drifts
	for sx in [-1.0, 1.0]:
		Models.part(f, Models.sphere(0.035, 8), Models.toon(Color("e8c070")), Vector3(0.07 * sx, 0.16, -0.08), Vector3(1.2, 0.6, 1.4))
	# a short fan of tail feathers
	var tail := Node3D.new(); tail.name = "Tail"; f.add_child(tail)
	for i in 3:
		Models.part(tail, Models.box(0.05, 0.015, 0.16), body, Vector3((i - 1) * 0.05, 0.26, 0.3), Vector3.ONE, Vector3(0.3, (i - 1) * 0.35, 0))
	Models._repivot(tail, Vector3(0, 0.28, 0.22))
	return {"head": hp, "top": hp.y + 0.2}

# ---------------------------------------------------------------- Cairnback: tortoise + ibex, Titan (rare)
static func _cairnback(f: Node3D, c: Dictionary, mats: Array) -> Dictionary:
	var body: Material = c["body"]; var belly: Material = c["belly"]; var dark: Material = c["dark"]; var glow: Material = c["glow"]
	var stone := Models.toon(Color("8e8a82")); var moss := Models.toon(Color("6f9a4a"), false)
	mats.append_array([stone, moss])
	# a high domed shell of hexagonal plates, gold runes glowing in the seams between them
	var sc := Vector3(0, 0.3, 0.06); var sr := Vector3(0.35, 0.27, 0.38)
	Models.part(f, Models.sphere(0.32), dark, sc, sr / 0.32)
	Models.part(f, Models.cyl(0.37, 0.39, 0.07, 18), belly, Vector3(0, 0.16, 0.06), Vector3(1.0, 1.0, 1.1))
	var plate := Models.toon(Color("7d7a86"))
	mats.append(plate)
	for ring in [[0.62, 7, 0.0], [1.15, 1, 0.0]]:
		for i in int(ring[1]):
			var a := TAU * i / float(ring[1]) + float(ring[2])
			var e := float(ring[0])
			var d := Vector3(cos(a) * cos(e), sin(e), sin(a) * cos(e)).normalized()
			var pp := sc + Vector3(d.x * sr.x, d.y * sr.y, d.z * sr.z) * 0.98
			var nrm := Vector3(d.x / sr.x, d.y / sr.y, d.z / sr.z).normalized()
			var pl := Models.part(f, Models.cyl(0.085, 0.1, 0.05, 6), plate, pp)
			pl.basis = Basis(Quaternion(Vector3.UP, nrm)) * Basis.from_scale(Vector3(1.0, 1.0, 1.0))
			var rn := Models.part(f, Models.cyl(0.03, 0.03, 0.02, 6), glow, pp + nrm * 0.03)
			rn.basis = Basis(Quaternion(Vector3.UP, nrm))
	# the little cairn of stacked stones on top, a moss tuft and a gold rune-stone
	var cairn := Node3D.new(); cairn.name = "Cairn"; cairn.position = Vector3(0, 0.6, 0.08); f.add_child(cairn)
	Models.part(cairn, Models.sphere(0.07, 8), stone, Vector3(0, 0.03, 0), Vector3(1.3, 0.6, 1.1))
	Models.part(cairn, Models.sphere(0.05, 8), stone, Vector3(0.01, 0.09, 0), Vector3(1.2, 0.6, 1.0))
	Models.part(cairn, Models.sphere(0.035, 8), glow, Vector3(0, 0.14, 0), Vector3(1.0, 0.8, 1.0))
	Models.part(cairn, Models.sphere(0.05, 6), moss, Vector3(-0.05, 0.02, 0.04), Vector3(1.0, 0.5, 1.0))
	# a stout neck and an ibex head: a short muzzle, a beard, great ridged horns sweeping back
	var hp := Vector3(0, 0.3, -0.36)
	seg(f, Vector3(0, 0.24, -0.2), hp + Vector3(0, -0.02, 0.06), 0.08, 0.07, belly)
	Models.part(f, Models.sphere(0.12), belly, hp, Vector3(0.95, 0.9, 1.15))
	Models.part(f, Models.sphere(0.07, 8), belly, hp + Vector3(0, -0.04, -0.1), Vector3(0.9, 0.75, 1.0))
	Models.part(f, Models.sphere(0.02, 6), dark, hp + Vector3(0, -0.03, -0.17))
	Models.part(f, Models.cyl(0.0, 0.03, 0.09, 5), stone, hp + Vector3(0, -0.13, -0.06), Vector3.ONE, Vector3(PI, 0, 0))
	eyes(f, hp, Vector3(0.114, 0.108, 0.138), 0.6, 0.3, 0.03, c["eye"], c["white"])
	var ears := Node3D.new(); ears.name = "Ears"; f.add_child(ears)
	for sx in [-1.0, 1.0]:
		# great ridged ibex horns sweeping up and back, gold at the tips
		var pts := [Vector3(0.05 * sx, 0.0, 0.0), Vector3(0.09 * sx, 0.16, 0.04), Vector3(0.13 * sx, 0.26, 0.16), Vector3(0.15 * sx, 0.26, 0.3), Vector3(0.16 * sx, 0.16, 0.38)]
		for i in pts.size() - 1:
			seg(ears, pts[i], pts[i + 1], 0.04 - i * 0.007, 0.033 - i * 0.007, stone)
			Models.part(ears, Models.sphere(0.036 - i * 0.006, 6), stone if i < 3 else glow, pts[i + 1], Vector3(1.0, 0.7, 1.0))
		Models.part(ears, Models.cyl(0.0, 0.025, 0.06, 4), body, Vector3(0.11 * sx, -0.03, 0.04), Vector3(1, 1, 0.5), Vector3(0, 0, -1.2 * sx))
	ears.position = hp + Vector3(0, 0.08, 0.0)
	var legs := Node3D.new(); legs.name = "Legs"; f.add_child(legs)
	for i in 4:
		var sx := -1.0 if i % 2 == 0 else 1.0
		var z := -0.12 if i < 2 else 0.26
		leg(legs, "Leg%d" % i, Vector3(0.24 * sx, 0.16, z), 0.14, 0.055, belly, dark)
	var tail := Node3D.new(); tail.name = "Tail"; f.add_child(tail)
	Models.part(tail, Models.cyl(0.0, 0.04, 0.1, 6), belly, Vector3(0, 0.16, 0.44), Vector3.ONE, Vector3(-PI / 2 - 0.4, 0, 0))
	Models._repivot(tail, Vector3(0, 0.17, 0.4))
	return {"head": hp, "top": 0.78}

# ---------------------------------------------------------------- Zephyrak: moray eel + swift, Tempest (rare)
static func _zephyrak(f: Node3D, c: Dictionary, mats: Array) -> Dictionary:
	var body: Material = c["body"]; var belly: Material = c["belly"]; var dark: Material = c["dark"]; var glow: Material = c["glow"]
	# a long eel body held up in an S, hovering: chain of spheres from the head back to a tail fin
	var pts: Array = []
	for i in 10:
		var k := i / 9.0
		pts.append(Vector3(sin(k * PI * 1.8) * 0.24, 0.42 - k * 0.22 + sin(k * PI) * 0.1, -0.14 + k * 0.6))
	for i in pts.size():
		var rr := lerpf(0.13, 0.05, float(i) / pts.size())
		Models.part(f, Models.sphere(rr, 10), body, pts[i], Vector3(1.0, 0.95, 1.15))
		if i % 3 == 2:
			var bnd := TorusMesh.new(); bnd.inner_radius = rr * 0.92; bnd.outer_radius = rr * 1.05; bnd.rings = 12; bnd.ring_segments = 4
			Models.part(f, bnd, glow, pts[i], Vector3.ONE, Vector3(PI / 2, 0, 0))
		Models.part(f, Models.sphere(rr * 0.8, 8), belly, pts[i] + Vector3(0, -rr * 0.35, 0), Vector3(1.05, 0.55, 1.1))
		if i % 2 == 1:
			var pm := PrismMesh.new(); pm.size = Vector3(0.02, rr * 0.9, rr * 1.2)
			Models.part(f, pm, glow, pts[i] + Vector3(0, rr * 0.95, 0))
	# head: a moray's blunt snout, a gaping little jaw, glowing eyes, a crest of static
	var hp := Vector3(0, 0.56, -0.28)
	Models.part(f, Models.sphere(0.15), body, hp, Vector3(0.95, 0.85, 1.3))
	Models.part(f, Models.sphere(0.1, 8), belly, hp + Vector3(0, -0.06, -0.08), Vector3(0.9, 0.5, 1.2))
	eyes(f, hp, Vector3(0.1425, 0.1275, 0.195), 0.55, 0.3, 0.036, c["eye"], c["white"])
	for sx in [-1.0, 1.0]:
		Models.part(f, Models.cyl(0.0, 0.01, 0.12, 4), glow, hp + Vector3(0.08 * sx, -0.06, -0.18), Vector3.ONE, Vector3(-1.2, 0, 0.6 * sx))
	var ears := Node3D.new(); ears.name = "Ears"; f.add_child(ears)
	for i in 3:
		var pm2 := PrismMesh.new(); pm2.size = Vector3(0.02, 0.12 - i * 0.02, 0.1)
		Models.part(ears, pm2, glow, Vector3(0, 0.0, i * 0.07), Vector3.ONE, Vector3(-0.3, 0, 0))
	ears.position = hp + Vector3(0, 0.13, 0.02)
	# swept swift's wings: long, narrow, crescent
	var wings := Node3D.new(); wings.name = "Wings"; f.add_child(wings)
	for sx in [-1.0, 1.0]:
		var w := Node3D.new(); w.name = "Wing" + ("L" if sx < 0 else "R"); w.position = Vector3(0.1 * sx, 0.48, -0.06); wings.add_child(w)
		w.rotation.z = 0.55 * sx
		# swift's feathers: four long blades fanned back, the leading one edged with static
		var fm := Models.toon(Color(c["wing_col"]), true, 0.25)
		for k in 4:
			Models.part(w, Models.box(0.46 - k * 0.07, 0.03, 0.09), fm, Vector3((0.22 - k * 0.02) * sx, 0.0, 0.03 + k * 0.07), Vector3.ONE, Vector3(0, -(0.25 + k * 0.22) * sx, 0))
		seg(w, Vector3.ZERO, Vector3(0.44 * sx, 0.02, -0.06), 0.014, 0.006, glow, 5)
	# a forked tail fin crackling at the tips
	var tail := Node3D.new(); tail.name = "Tail"; f.add_child(tail)
	var tp: Vector3 = pts[pts.size() - 1]
	for sx in [-1.0, 1.0]:
		Models.part(tail, Models.box(0.02, 0.14, 0.16), Models.toon(Color(c["wing_col"]), false), tp + Vector3(0.03 * sx, 0.04 * sx, 0.1), Vector3.ONE, Vector3(0.5 * sx, 0, 0.3 * sx))
		Models.part(tail, Models.sphere(0.02, 6), glow, tp + Vector3(0.04 * sx, 0.12 * sx, 0.17))
	Models._repivot(tail, tp)
	var spin := Node3D.new(); spin.name = "Spin"; spin.position = Vector3(0, 0.4, 0.1); f.add_child(spin)
	for i in 3:
		var a := TAU * i / 3.0
		Models.part(spin, Models.sphere(0.022, 6), glow, Vector3(cos(a) * 0.42, sin(a * 3.0) * 0.06, sin(a) * 0.42))
	return {"head": hp, "top": hp.y + 0.2}

# ---------------------------------------------------------------- Hivara: honeybee + praying mantis, Swarm (rare)
static func _hivara(f: Node3D, c: Dictionary, mats: Array) -> Dictionary:
	var body: Material = c["body"]; var belly: Material = c["belly"]; var dark: Material = c["dark"]; var glow: Material = c["glow"]
	var band := Models.toon(Color("2a1e14")); var wax := Models.toon(Color("ffd860"), true, 0.35)
	mats.append_array([band, wax])
	# a striped bee abdomen behind, a slender mantis thorax rising up in front
	var abd := Vector3(0, 0.26, 0.2)
	Models.part(f, Models.sphere(0.2), body, abd, Vector3(1.0, 0.95, 1.35))
	for i in 3:
		var stp := TorusMesh.new(); stp.inner_radius = 0.15 - absf(i - 1) * 0.03; stp.outer_radius = 0.2 - absf(i - 1) * 0.035; stp.rings = 18; stp.ring_segments = 6
		Models.part(f, stp, band, abd + Vector3(0, 0, -0.08 + i * 0.1), Vector3(1.0, 0.95, 1.0), Vector3(PI / 2, 0, 0))
	Models.part(f, Models.cyl(0.0, 0.03, 0.08, 6), dark, abd + Vector3(0, -0.04, 0.29), Vector3.ONE, Vector3(-PI / 2 - 0.3, 0, 0))
	seg(f, abd + Vector3(0, 0.02, -0.18), Vector3(0, 0.46, -0.16), 0.07, 0.06, body)
	Models.part(f, Models.sphere(0.09), body, Vector3(0, 0.36, -0.12), Vector3(1.0, 1.2, 1.0))
	# a fuzzy collar
	Models.part(f, Models.sphere(0.1, 10), belly, Vector3(0, 0.44, -0.16), Vector3(1.3, 0.7, 1.2))
	# head: a mantis triangle, big compound eyes, feathery bee antennae, a little wax crown
	var hp := Vector3(0, 0.58, -0.2)
	Models.part(f, Models.sphere(0.12), body, hp, Vector3(1.25, 0.95, 0.9))
	Models.part(f, Models.cyl(0.0, 0.07, 0.1, 3), body, hp + Vector3(0, -0.08, -0.04), Vector3(1.4, 1.0, 0.8), Vector3(PI, 0, 0))
	eyes(f, hp, Vector3(0.15, 0.114, 0.108), 0.95, 0.25, 0.05, c["eye"], c["white"])
	var ears := Node3D.new(); ears.name = "Ears"; f.add_child(ears)
	for sx in [-1.0, 1.0]:
		var a := Vector3(0.04 * sx, 0.0, 0.0); var b := Vector3(0.12 * sx, 0.16, -0.08); var cc := Vector3(0.17 * sx, 0.2, -0.16)
		seg(ears, a, b, 0.01, 0.008, dark, 5)
		seg(ears, b, cc, 0.008, 0.006, dark, 5)
		Models.part(ears, Models.sphere(0.022, 6), glow, cc)
	for i in 5:
		var a2 := TAU * i / 5.0
		Models.part(ears, Models.cyl(0.0, 0.02, 0.06, 5), wax, Vector3(cos(a2) * 0.06, 0.06, sin(a2) * 0.05 + 0.02))
	Models.part(ears, Models.cyl(0.07, 0.07, 0.025, 10), wax, Vector3(0, 0.03, 0.02))
	ears.position = hp + Vector3(0, 0.1, 0.02)
	# folded mantis blades held up in front
	for sx in [-1.0, 1.0]:
		var sh := Vector3(0.07 * sx, 0.4, -0.18)
		var el := sh + Vector3(0.04 * sx, 0.1, -0.1)
		var tip := el + Vector3(0.0, -0.17, -0.04)
		seg(f, sh, el, 0.025, 0.022, body)
		seg(f, el, tip, 0.022, 0.006, dark)
		for k in 3:
			Models.part(f, Models.cyl(0.0, 0.008, 0.03, 4), c["white"], el.lerp(tip, 0.25 + k * 0.22) + Vector3(0, 0, 0.018), Vector3.ONE, Vector3(PI / 2, 0, 0))
	# four glassy wings
	var wings := Node3D.new(); wings.name = "Wings"; f.add_child(wings)
	for sx in [-1.0, 1.0]:
		var w := Node3D.new(); w.name = "Wing" + ("L" if sx < 0 else "R"); w.position = Vector3(0.06 * sx, 0.44, -0.02); wings.add_child(w)
		for k in 2:
			var mm := StandardMaterial3D.new(); mm.cull_mode = BaseMaterial3D.CULL_DISABLED
			mm.albedo_color = Color(Color(c["wing_col"]), 0.75); mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; mm.rim_enabled = true; mm.rim = 0.7
			var wm := Models.part(w, Models.sphere(0.12, 10), mm, Vector3(0.14 * sx, 0.04 - k * 0.04, 0.08 + k * 0.1), Vector3(1.4 - k * 0.3, 0.08, 0.6), Vector3(0, (0.4 + k * 0.4) * sx, 0.25 * sx))
			wm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var legs := Node3D.new(); legs.name = "Legs"; f.add_child(legs)
	for i in 4:
		var sx := -1.0 if i % 2 == 0 else 1.0
		var z := 0.0 if i < 2 else 0.18
		leg(legs, "Leg%d" % i, Vector3(0.09 * sx, 0.22, z), 0.2, 0.018, dark, dark, 0.06 * sx)
	var tail := Node3D.new(); tail.name = "Tail"; f.add_child(tail)
	Models.part(tail, Models.sphere(0.01, 4), band, abd + Vector3(0, 0, 0.3))
	Models._repivot(tail, abd + Vector3(0, 0, 0.25))
	# its swarm: three tiny bees circling
	var spin := Node3D.new(); spin.name = "Spin"; spin.position = Vector3(0, 0.5, 0.0); f.add_child(spin)
	for i in 3:
		var a := TAU * i / 3.0
		var bee := Node3D.new(); bee.position = Vector3(cos(a) * 0.44, sin(a * 2.0) * 0.08, sin(a) * 0.44); spin.add_child(bee)
		Models.part(bee, Models.sphere(0.025, 6), body, Vector3.ZERO, Vector3(1, 1, 1.4))
		Models.part(bee, Models.sphere(0.012, 4), band, Vector3(0, 0, 0.012))
		Models.part(bee, Models.sphere(0.02, 4), Models.toon(Color.WHITE, false, 0.6), Vector3(0, 0.02, 0), Vector3(1.6, 0.2, 0.8))
	return {"head": hp, "top": hp.y + 0.22}
