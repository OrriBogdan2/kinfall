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

static func sphere(r: float, seg := 16) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r; s.height = r * 2.0; s.radial_segments = seg; s.rings = maxi(6, seg / 2)
	return s

static func capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r; c.height = h; c.radial_segments = 14; c.rings = 6
	return c

static func box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b

static func cyl(top: float, bottom: float, h: float, seg := 14) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top; c.bottom_radius = bottom; c.height = h; c.radial_segments = seg; c.rings = 1
	return c

static func flat_quad(size: float) -> PlaneMesh:
	var p := PlaneMesh.new()
	p.size = Vector2(size, size)
	return p

# ---------------------------------------------------------------- hunters
static func hunter(cls: String, team_col: Color, weapon: String, hero := "") -> Node3D:
	var root := Node3D.new()
	var look0: String = hero if hero != "" else {"light": "veil", "medium": "sage", "heavy": "bastion"}.get(cls, "sage")
	var hero_col: Color = Data.HEROES[look0]["color"] if Data.HEROES.has(look0) else team_col
	# each hero has its own outfit colour; the team shows in the ring at their feet and the trim
	var body_col := team_col.lerp(hero_col, 0.45).lerp(Color("3a3f52"), 0.3)
	var mats: Array = []
	var m_body := toon(body_col); mats.append(m_body)
	var m_skin := toon(Color("f1c9a0")); mats.append(m_skin)
	var m_dark := toon(Color("2b2a33")); mats.append(m_dark)
	var m_acc := toon(team_col); mats.append(m_acc)
	var m_gun := toon(Color("4a4d5c")); mats.append(m_gun)
	var rig := Node3D.new(); rig.name = "Rig"; root.add_child(rig)
	var legs := Node3D.new(); legs.name = "Legs"; rig.add_child(legs)
	part(legs, capsule(0.09, 0.42), m_dark, Vector3(-0.12, 0.22, 0), Vector3.ONE, Vector3.ZERO, "LegL")
	part(legs, capsule(0.09, 0.42), m_dark, Vector3(0.12, 0.22, 0), Vector3.ONE, Vector3.ZERO, "LegR")
	var torso := Node3D.new(); torso.name = "Torso"; torso.position = Vector3(0, 0.42, 0); rig.add_child(torso)
	part(torso, capsule(0.25, 0.72), m_body, Vector3(0, 0.3, 0))
	part(torso, box(0.3, 0.32, 0.16), m_dark, Vector3(0, 0.36, 0.24))  # backpack
	part(torso, sphere(0.215), m_skin, Vector3(0, 0.82, 0), Vector3.ONE, Vector3.ZERO, "Head")
	part(torso, sphere(0.035, 8), m_dark, Vector3(-0.08, 0.84, -0.19))
	part(torso, sphere(0.035, 8), m_dark, Vector3(0.08, 0.84, -0.19))
	var look: String = hero if hero != "" else {"light": "veil", "medium": "sage", "heavy": "bastion"}.get(cls, "sage")
	var hc: Color = Data.HEROES[look]["color"] if Data.HEROES.has(look) else team_col
	var m_hero := toon(hc); mats.append(m_hero)
	match look:
		"veil":
			part(torso, sphere(0.25), m_acc, Vector3(0, 0.88, 0.04), Vector3(1.0, 0.95, 1.05))  # hood
			part(torso, cyl(0.2, 0.26, 0.1), m_acc, Vector3(0, 0.58, 0))  # scarf
			part(torso, box(0.12, 0.34, 0.04), m_acc, Vector3(0.1, 0.42, 0.24), Vector3.ONE, Vector3(0.3, 0, 0.2))
		"nyx":
			part(torso, sphere(0.25), m_dark, Vector3(0, 0.88, 0.04), Vector3(1.0, 0.95, 1.05))
			part(torso, box(0.34, 0.07, 0.06), toon(hc, false, 0.9), Vector3(0, 0.84, -0.2))   # glowing visor
			for sx in [-1.0, 1.0]:
				part(torso, cyl(0.0, 0.05, 0.22), m_hero, Vector3(0.14 * sx, 1.12, 0.02), Vector3.ONE, Vector3(-0.2, 0, -0.5 * sx))
			part(torso, box(0.5, 0.5, 0.04), m_dark, Vector3(0, 0.3, 0.27), Vector3.ONE, Vector3(0.25, 0, 0))  # cape
		"kestrel":
			part(torso, cyl(0.22, 0.24, 0.12), m_hero, Vector3(0, 0.98, 0))
			part(torso, box(0.38, 0.08, 0.1), toon(Color("2b2a33")), Vector3(0, 0.86, -0.17))
			part(torso, sphere(0.05, 8), toon(hc, false, 0.9), Vector3(0.09, 0.86, -0.22))
			part(torso, box(0.04, 0.32, 0.1), toon(Color("f3eee2")), Vector3(0.22, 1.08, 0.08), Vector3.ONE, Vector3(-0.4, 0, -0.4))  # feather
		"sage":
			part(torso, cyl(0.34, 0.34, 0.04), m_acc, Vector3(0, 0.98, 0))  # brim
			part(torso, cyl(0.17, 0.2, 0.2), m_acc, Vector3(0, 1.08, 0))
			part(torso, cyl(0.205, 0.205, 0.04), m_dark, Vector3(0, 1.01, 0))
		"marlow":
			part(torso, sphere(0.23), m_hero, Vector3(0, 0.9, 0.02), Vector3(1.0, 0.6, 1.0))  # bandana
			part(torso, sphere(0.07, 8), m_hero, Vector3(0, 0.88, 0.24))
			part(torso, box(0.07, 0.2, 0.04), m_hero, Vector3(0.04, 0.78, 0.27), Vector3.ONE, Vector3(0.3, 0, 0.3))
			var t := TorusMesh.new(); t.inner_radius = 0.2; t.outer_radius = 0.26
			part(torso, t, toon(Color("8a8d99")), Vector3(0, 0.38, 0), Vector3.ONE, Vector3(0.9, 0, 0.5))  # chain
		"pyra":
			part(torso, sphere(0.2), toon(Color("ff7a3d")), Vector3(0, 0.98, 0.05), Vector3(1.15, 0.8, 1.15))  # hair
			for sx in [-1.0, 1.0]:
				part(torso, cyl(0.07, 0.07, 0.05, 12), toon(Color("9af0ff"), false, 0.6), Vector3(0.09 * sx, 0.97, -0.17), Vector3.ONE, Vector3(PI / 2, 0, 0))
			part(torso, box(0.36, 0.04, 0.04), m_dark, Vector3(0, 0.97, -0.15))
		"bastion":
			part(torso, sphere(0.26), m_acc, Vector3(0, 0.9, 0.02), Vector3(1.05, 0.85, 1.05))  # helmet
			part(torso, box(0.34, 0.06, 0.06), m_dark, Vector3(0, 0.83, -0.2))  # visor
			part(torso, sphere(0.17), m_acc, Vector3(-0.3, 0.55, 0), Vector3(1.2, 0.8, 1.2))
			part(torso, sphere(0.17), m_acc, Vector3(0.3, 0.55, 0), Vector3(1.2, 0.8, 1.2))
		"tusk":
			part(torso, sphere(0.26), m_hero, Vector3(0, 0.9, 0.02), Vector3(1.05, 0.85, 1.05))
			for sx in [-1.0, 1.0]:
				part(torso, cyl(0.0, 0.06, 0.3), toon(Color("f3eee2")), Vector3(0.14 * sx, 0.74, -0.2), Vector3.ONE, Vector3(-1.2, 0, -0.3 * sx))
			part(torso, sphere(0.19), m_hero, Vector3(-0.3, 0.55, 0), Vector3(1.2, 0.8, 1.2))
			part(torso, sphere(0.19), m_hero, Vector3(0.3, 0.55, 0), Vector3(1.2, 0.8, 1.2))
		"halo":
			part(torso, sphere(0.25), m_acc, Vector3(0, 0.9, 0.02), Vector3(1.0, 0.9, 1.0))
			part(torso, box(0.3, 0.12, 0.06), toon(Color("9af0ff"), false, 0.5), Vector3(0, 0.85, -0.2))
			var hr := TorusMesh.new(); hr.inner_radius = 0.17; hr.outer_radius = 0.22
			part(torso, hr, toon(hc, false, 1.2), Vector3(0, 1.26, 0), Vector3.ONE, Vector3.ZERO, "Halo")
			part(torso, sphere(0.17), m_acc, Vector3(-0.3, 0.55, 0), Vector3(1.2, 0.8, 1.2))
			part(torso, sphere(0.17), m_acc, Vector3(0.3, 0.55, 0), Vector3(1.2, 0.8, 1.2))
	# outfit pieces that give each hero its own silhouette
	var m_trim := toon(hero_col.darkened(0.15)); mats.append(m_trim)
	part(torso, cyl(0.255, 0.255, 0.07, 18), m_trim, Vector3(0, 0.08, 0))   # belt
	match look:
		"veil":
			part(torso, box(0.1, 0.42, 0.03), m_acc, Vector3(-0.12, 0.4, 0.27), Vector3.ONE, Vector3(0.35, 0, -0.25))
		"nyx":
			for sx in [-1.0, 1.0]:
				part(torso, box(0.05, 0.26, 0.03), toon(Color("e8e0ff")), Vector3(0.16 * sx, 0.12, 0.26), Vector3.ONE, Vector3(0.5, 0, 0.6 * sx))   # back daggers
		"kestrel":
			part(torso, box(0.06, 0.62, 0.05), m_trim, Vector3(0.0, 0.36, -0.2), Vector3.ONE, Vector3(0, 0, 0.75))   # strap
			part(torso, cyl(0.07, 0.07, 0.55, 10), toon(Color("7a5236")), Vector3(-0.14, 0.5, 0.28), Vector3.ONE, Vector3(0.2, 0, 0.3))   # quiver
		"sage":
			part(torso, box(0.2, 0.18, 0.1), toon(Color("8a5a35")), Vector3(0.22, 0.12, 0.12), Vector3.ONE, Vector3(0, 0.5, 0))   # satchel
			part(torso, sphere(0.07, 8), toon(Color("9ee2a0"), false, 0.5), Vector3(0.24, 0.24, 0.14))
		"marlow":
			part(torso, box(0.42, 0.06, 0.05), toon(Color("5a4636")), Vector3(0, 0.3, -0.22), Vector3.ONE, Vector3(0, 0, -0.6))   # harness
		"pyra":
			for sx in [-1.0, 1.0]:
				part(torso, cyl(0.08, 0.08, 0.42, 12), toon(Color("ff7a5a")), Vector3(0.1 * sx, 0.42, 0.3))   # fuel tanks
				part(torso, cyl(0.05, 0.03, 0.08, 10), toon(Color("ffd23f"), false, 0.8), Vector3(0.1 * sx, 0.18, 0.3))
		"bastion":
			part(torso, cyl(0.3, 0.3, 0.06, 20), m_trim, Vector3(0, 0.38, 0.33), Vector3.ONE, Vector3(PI / 2, 0, 0))   # shield on the back
			part(torso, cyl(0.12, 0.12, 0.07, 14), m_acc, Vector3(0, 0.38, 0.36), Vector3.ONE, Vector3(PI / 2, 0, 0))
		"tusk":
			part(torso, box(0.5, 0.1, 0.42), m_trim, Vector3(0, 0.05, 0))   # heavy belt
			part(torso, sphere(0.08, 8), toon(Color("f3eee2")), Vector3(0, 0.06, -0.22))
		"halo":
			var gen := TorusMesh.new(); gen.inner_radius = 0.12; gen.outer_radius = 0.18
			part(torso, gen, toon(hero_col, false, 0.9), Vector3(0, 0.4, 0.33), Vector3.ONE, Vector3(PI / 2, 0, 0))   # dome generator
	var gun := Node3D.new(); gun.name = "Gun"; gun.position = Vector3(0.22, 0.32, -0.18); torso.add_child(gun)
	# arms reach from the shoulders to the gun
	var arm_r := part(torso, capsule(0.07, 0.42), m_body, Vector3(0.24, 0.48, -0.08), Vector3.ONE, Vector3(1.2, 0, 0.15), "ArmR")
	var arm_l := part(torso, capsule(0.07, 0.46), m_body, Vector3(-0.1, 0.46, -0.16), Vector3.ONE, Vector3(1.25, 0, -0.7), "ArmL")
	part(arm_r, sphere(0.075, 8), m_skin, Vector3(0, -0.23, 0))
	part(arm_l, sphere(0.075, 8), m_skin, Vector3(0, -0.25, 0))
	match weapon:
		"stinger":
			part(gun, box(0.1, 0.12, 0.42), m_gun, Vector3(0, 0, -0.12))
			part(gun, box(0.05, 0.16, 0.08), m_dark, Vector3(0, -0.12, -0.04))
			part(gun, box(0.06, 0.06, 0.12), m_acc, Vector3(0, 0.08, -0.12))
		"repeater":
			part(gun, box(0.09, 0.12, 0.7), m_gun, Vector3(0, 0, -0.24))
			part(gun, cyl(0.035, 0.035, 0.3), m_dark, Vector3(0, 0.02, -0.66), Vector3.ONE, Vector3(PI / 2, 0, 0))
			part(gun, box(0.05, 0.08, 0.16), m_acc, Vector3(0, 0.09, -0.16))
		"rail":
			part(gun, box(0.08, 0.1, 0.9), m_gun, Vector3(0, 0, -0.32))
			part(gun, box(0.04, 0.04, 0.5), toon(Color("9af0ff"), false, 0.8), Vector3(0, 0.07, -0.42))
			part(gun, cyl(0.05, 0.05, 0.14), m_dark, Vector3(0, 0.1, -0.12), Vector3.ONE, Vector3(PI / 2, 0, 0))
		"rocket":
			part(gun, cyl(0.1, 0.1, 0.72), toon(Color("5a6a4a")), Vector3(0, 0.04, -0.22), Vector3.ONE, Vector3(PI / 2, 0, 0))
			part(gun, cyl(0.06, 0.12, 0.12), toon(Color("ff7a5a")), Vector3(0, 0.04, -0.6), Vector3.ONE, Vector3(PI / 2, 0, 0))
			part(gun, box(0.06, 0.16, 0.08), m_dark, Vector3(0, -0.12, -0.05))
		"thumper":
			part(gun, cyl(0.12, 0.12, 0.62), m_gun, Vector3(0, 0, -0.2), Vector3.ONE, Vector3(PI / 2, 0, 0))
			part(gun, cyl(0.14, 0.14, 0.08), m_acc, Vector3(0, 0, -0.52), Vector3.ONE, Vector3(PI / 2, 0, 0))
			part(gun, box(0.08, 0.18, 0.12), m_dark, Vector3(0, -0.15, -0.02))
	var muzzle := Node3D.new(); muzzle.name = "Muzzle"; muzzle.position = Vector3(0, 0.02, -0.75); gun.add_child(muzzle)
	var shoulder := Node3D.new(); shoulder.name = "Shoulder"; shoulder.position = Vector3(-0.3, 0.78, 0.04); torso.add_child(shoulder)
	# a folding cloth glider that pops out above the backpack
	var glider := Node3D.new(); glider.name = "Glider"; glider.position = Vector3(0, 0.62, 0.12); glider.visible = false
	torso.add_child(glider)
	var m_cloth := toon(Color("f3eee2")); var m_frame := toon(Color("5a4636"))
	part(glider, box(0.86, 0.04, 0.72), m_cloth, Vector3(-0.42, 0.98, 0), Vector3.ONE, Vector3(0, 0, 0.16))
	part(glider, box(0.86, 0.04, 0.72), m_cloth, Vector3(0.42, 0.98, 0), Vector3.ONE, Vector3(0, 0, -0.16))
	part(glider, box(0.3, 0.05, 0.74), m_acc, Vector3(-0.66, 0.94, 0), Vector3.ONE, Vector3(0, 0, 0.16))
	part(glider, box(0.3, 0.05, 0.74), m_acc, Vector3(0.66, 0.94, 0), Vector3.ONE, Vector3(0, 0, -0.16))
	part(glider, box(1.8, 0.05, 0.06), m_frame, Vector3(0, 1.0, -0.36))
	part(glider, cyl(0.025, 0.025, 0.9), m_frame, Vector3(-0.22, 0.52, 0), Vector3.ONE, Vector3(0, 0, -0.3))
	part(glider, cyl(0.025, 0.025, 0.9), m_frame, Vector3(0.22, 0.52, 0), Vector3.ONE, Vector3(0, 0, 0.3))
	var ring := MeshInstance3D.new(); ring.name = "TeamRing"; ring.mesh = flat_quad(1.0)
	ring.material_override = ring_mat(team_col, 0.16); ring.position = Vector3(0, 0.04, 0)
	root.add_child(ring)
	root.set_meta("mats", mats)
	root.scale = Vector3.ONE * float(Data.CLASSES[cls]["scale"])
	return root

# ---------------------------------------------------------------- kin
static func kin(species: String, rec := {}) -> Node3D:
	var sp: Dictionary = Data.KIN[species]
	var root := Node3D.new()
	var mats: Array = []
	var m_body := toon(sp["color"]); mats.append(m_body)
	var m_belly := toon(sp["belly"]); mats.append(m_belly)
	var m_eye := toon(Color("1a1620"), false); mats.append(m_eye)
	var m_white := toon(Color.WHITE, false, 0.6)
	var body := Node3D.new(); body.name = "Body"; root.add_child(body)
	part(body, sphere(0.34), m_body, Vector3(0, 0.34, 0), Vector3(1.05, 0.92, 1.0))
	part(body, sphere(0.24), m_belly, Vector3(0, 0.3, -0.14), Vector3(1.0, 0.95, 0.7))
	for sx in [-1.0, 1.0]:
		part(body, sphere(0.065, 10), m_eye, Vector3(0.12 * sx, 0.44, -0.28))
		part(body, sphere(0.022, 6), m_white, Vector3(0.12 * sx + 0.02, 0.47, -0.33))
		part(body, sphere(0.08, 8), m_body, Vector3(0.2 * sx, 0.06, -0.08), Vector3(1, 0.6, 1.2))  # feet
	part(body, sphere(0.1, 8), m_body, Vector3(0, 0.26, 0.32))  # tail
	match String(sp["ears"]):
		"flame":
			var m_f := toon(Color("ffb347"), true, 0.5); mats.append(m_f)
			part(body, cyl(0.0, 0.12, 0.3), m_f, Vector3(0, 0.74, 0.02))
			part(body, cyl(0.0, 0.08, 0.22), m_f, Vector3(-0.13, 0.68, 0.04), Vector3.ONE, Vector3(0, 0, 0.4))
			part(body, cyl(0.0, 0.08, 0.22), m_f, Vector3(0.13, 0.68, 0.04), Vector3.ONE, Vector3(0, 0, -0.4))
		"fin":
			part(body, sphere(0.14), m_belly, Vector3(0, 0.66, 0.06), Vector3(0.35, 1.1, 1.3))
			part(body, sphere(0.1), m_body, Vector3(-0.3, 0.3, 0.05), Vector3(0.4, 0.8, 1.2))
			part(body, sphere(0.1), m_body, Vector3(0.3, 0.3, 0.05), Vector3(0.4, 0.8, 1.2))
		"leaf":
			var m_l := toon(Color("3e8f3a")); mats.append(m_l)
			part(body, sphere(0.14), m_l, Vector3(-0.14, 0.68, 0), Vector3(0.5, 1.2, 0.25), Vector3(0, 0, 0.5))
			part(body, sphere(0.14), m_l, Vector3(0.14, 0.68, 0), Vector3(0.5, 1.2, 0.25), Vector3(0, 0, -0.5))
		"bolt":
			var m_b := toon(Color("fff27a"), true, 0.4); mats.append(m_b)
			part(body, box(0.06, 0.26, 0.06), m_b, Vector3(-0.14, 0.72, 0), Vector3.ONE, Vector3(0, 0, 0.5))
			part(body, box(0.06, 0.26, 0.06), m_b, Vector3(0.14, 0.72, 0), Vector3.ONE, Vector3(0, 0, -0.5))
			part(body, box(0.05, 0.16, 0.05), m_b, Vector3(-0.22, 0.86, 0), Vector3.ONE, Vector3(0, 0, -0.4))
			part(body, box(0.05, 0.16, 0.05), m_b, Vector3(0.22, 0.86, 0), Vector3.ONE, Vector3(0, 0, 0.4))
		"horn":
			var m_h := toon(Color("e8e0cc")); mats.append(m_h)
			part(body, cyl(0.0, 0.07, 0.2), m_h, Vector3(-0.15, 0.66, -0.05), Vector3.ONE, Vector3(-0.2, 0, 0.35))
			part(body, cyl(0.0, 0.07, 0.2), m_h, Vector3(0.15, 0.66, -0.05), Vector3.ONE, Vector3(-0.2, 0, -0.35))
			part(body, box(0.18, 0.1, 0.18), m_body, Vector3(0, 0.6, 0.12), Vector3.ONE, Vector3(0.3, 0.4, 0.2))
		"wisp":
			var m_w := toon(Color("efe8ff"), false, 0.8); mats.append(m_w)
			for i in 3:
				var a := float(i) / 3.0 * TAU
				part(body, sphere(0.06, 8), m_w, Vector3(cos(a) * 0.3, 0.72 + sin(a * 2.0) * 0.04, sin(a) * 0.3), Vector3.ONE, Vector3.ZERO, "Orb%d" % i)
	root.set_meta("mats", mats)
	Evo.dress(root, rec)
	return root

# ---------------------------------------------------------------- monsters
static func mob(kind: String) -> Node3D:
	var md: Dictionary = Data.MOBS[kind]
	var root := Node3D.new()
	var mats: Array = []
	var m := toon(md["color"]); mats.append(m)
	var m_dark := toon(Color(md["color"]).darkened(0.5)); mats.append(m_dark)
	var m_eye := toon(Color("ffe25a"), false, 1.2); mats.append(m_eye)
	var body := Node3D.new(); body.name = "Body"; root.add_child(body)
	match kind:
		"skitter":
			part(body, sphere(0.38), m, Vector3(0, 0.38, 0), Vector3(1.1, 0.75, 1.25))
			part(body, sphere(0.22), m_dark, Vector3(0, 0.5, 0.18), Vector3(1.2, 0.7, 1.0))
			for sx in [-1.0, 1.0]:
				part(body, sphere(0.05, 6), m_eye, Vector3(0.12 * sx, 0.46, -0.38))
				for i in 3:
					part(body, box(0.05, 0.05, 0.42), m_dark, Vector3(0.36 * sx, 0.2, -0.18 + i * 0.2), Vector3.ONE, Vector3(0, PI / 2, 0.6 * sx), "Leg%d%d" % [i, int(sx)])
		"spitter":
			part(body, cyl(0.1, 0.16, 0.6), m_dark, Vector3(0, 0.3, 0))
			part(body, sphere(0.36), m, Vector3(0, 0.8, 0), Vector3(1.0, 0.9, 1.0), Vector3.ZERO, "Bulb")
			part(body, cyl(0.16, 0.2, 0.12), m_eye, Vector3(0, 0.8, -0.3), Vector3.ONE, Vector3(PI / 2, 0, 0))
			for i in 4:
				var a := float(i) / 4.0 * TAU + 0.4
				part(body, sphere(0.2), m, Vector3(cos(a) * 0.32, 0.08, sin(a) * 0.32), Vector3(1.4, 0.25, 0.7), Vector3(0, -a, 0))
		"brute", "warden":
			if kind == "warden":
				root.scale = Vector3.ONE * 1.5
				var gold := toon(Color("f2c84a"), true, 0.5); mats.append(gold)
				for sx in [-1.0, 0.0, 1.0]:
					part(body, cyl(0.0, 0.09, 0.32, 6), gold, Vector3(0.16 * sx, 1.93, -0.12))
				part(body, box(0.62, 0.08, 0.56), gold, Vector3(0, 1.8, -0.12))
				part(body, sphere(0.12, 8), toon(Color("c9a0ff"), false, 1.2), Vector3(0, 1.0, -0.42))
			part(body, box(1.0, 0.9, 0.8), m, Vector3(0, 0.95, 0))
			part(body, box(0.55, 0.45, 0.5), m_dark, Vector3(0, 1.55, -0.12), Vector3.ONE, Vector3.ZERO, "Head")
			part(body, sphere(0.06, 6), m_eye, Vector3(-0.13, 1.6, -0.38))
			part(body, sphere(0.06, 6), m_eye, Vector3(0.13, 1.6, -0.38))
			part(body, box(0.34, 0.95, 0.34), m_dark, Vector3(-0.68, 0.8, -0.05), Vector3.ONE, Vector3.ZERO, "ArmL")
			part(body, box(0.34, 0.95, 0.34), m_dark, Vector3(0.68, 0.8, -0.05), Vector3.ONE, Vector3.ZERO, "ArmR")
			part(body, box(0.3, 0.5, 0.34), m_dark, Vector3(-0.25, 0.25, 0))
			part(body, box(0.3, 0.5, 0.34), m_dark, Vector3(0.25, 0.25, 0))
	root.set_meta("mats", mats)
	return root

# ---------------------------------------------------------------- props
static func rock(rng: RandomNumberGenerator, s: float) -> Node3D:
	var root := Node3D.new()
	var g := Color("8d8a86").lerp(Color("6f6a73"), rng.randf())
	var m := toon(g, true)
	var sm := SphereMesh.new(); sm.radius = 0.5; sm.height = 1.0; sm.radial_segments = 7; sm.rings = 4
	part(root, sm, m, Vector3(0, 0.45 * s, 0), Vector3(s * rng.randf_range(0.9, 1.15), s * rng.randf_range(0.9, 1.4), s * rng.randf_range(0.9, 1.15)), Vector3(0, rng.randf() * TAU, 0))
	if rng.randf() < 0.6:
		part(root, sm, m, Vector3(rng.randf_range(-0.3, 0.3) * s, 0.2 * s, rng.randf_range(-0.3, 0.3) * s), Vector3.ONE * s * 0.55, Vector3(0, rng.randf() * TAU, 0))
	return root

static func tree(rng: RandomNumberGenerator, leaf: Color) -> Node3D:
	var root := Node3D.new()
	var mt := toon(Color("6b4a35"))
	var ml := toon(leaf.lerp(Color("2f5a3a"), rng.randf() * 0.4))
	var h := rng.randf_range(1.6, 2.4)
	part(root, cyl(0.1, 0.15, h * 0.5), mt, Vector3(0, h * 0.25, 0))
	part(root, cyl(0.0, 0.7, h * 0.55), ml, Vector3(0, h * 0.55, 0))
	part(root, cyl(0.0, 0.52, h * 0.45), ml, Vector3(0, h * 0.82, 0))
	return root

const CHEST_COLS := [[Color("8a5a35"), Color("f2c84a")], [Color("3f6fb0"), Color("dfe8f2")], [Color("6a3fa8"), Color("f2c84a")]]

static func chest(tier := 0) -> Node3D:
	var root := Node3D.new()
	var cc: Array = CHEST_COLS[clampi(tier, 0, 2)]
	var mw := toon(cc[0]); var mg := toon(cc[1], true, 0.3 + tier * 0.25)
	var body := Node3D.new(); body.name = "Body"; root.add_child(body)
	part(body, box(0.8, 0.45, 0.55), mw, Vector3(0, 0.23, 0))
	part(body, box(0.84, 0.18, 0.59), mw, Vector3(0, 0.55, 0), Vector3.ONE, Vector3.ZERO, "Lid")
	part(body, box(0.14, 0.2, 0.06), mg, Vector3(0, 0.42, -0.3))
	part(body, box(0.86, 0.06, 0.6), mg, Vector3(0, 0.46, 0))
	if tier >= 1:
		for x in [-0.42, 0.42]:
			part(body, box(0.06, 0.5, 0.6), mg, Vector3(x, 0.3, 0))
	body.scale = Vector3.ONE * (1.0 + tier * 0.18)
	if tier >= 1:
		# a light pillar you can see from other islands
		var beam := part(root, cyl(0.16, 0.3, 9.0, 10), glow_mat(Color(cc[1] if tier == 1 else Color("c9a0ff"), 0.22)), Vector3(0, 4.5, 0), Vector3.ONE, Vector3.ZERO, "Beacon")
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.set_meta("mats", [mw, mg])
	return root

static func shrine() -> Node3D:
	var root := Node3D.new()
	var stone := toon(Color("b8b2a8"))
	part(root, cyl(0.9, 1.05, 0.3, 8), stone, Vector3(0, 0.15, 0))
	part(root, cyl(0.55, 0.7, 0.5, 8), stone, Vector3(0, 0.55, 0))
	var cr := Node3D.new(); cr.name = "Crystal"; cr.position = Vector3(0, 1.6, 0); root.add_child(cr)
	var pm := PrismMesh.new(); pm.size = Vector3(0.45, 0.6, 0.45)
	var cm := toon(Color("8fe3c8"), false, 0.9)
	part(cr, pm, cm, Vector3(0, 0.3, 0))
	part(cr, pm, cm, Vector3(0, -0.3, 0), Vector3.ONE, Vector3(PI, 0, 0))
	var base := MeshInstance3D.new(); base.name = "Ring"; base.mesh = flat_quad(3.0)
	base.material_override = ring_mat(Color("8fe3c8"), 0.08); base.position.y = 0.06
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

static func portal(c: Color) -> Node3D:
	var root := Node3D.new()
	var t := TorusMesh.new(); t.inner_radius = 0.95; t.outer_radius = 1.2; t.rings = 24; t.ring_segments = 8
	var mr := toon(Color("4a4f60"), true)
	part(root, t, mr, Vector3(0, 1.25, 0), Vector3.ONE, Vector3(PI / 2, 0, 0), "Ring")
	var disc := part(root, cyl(1.0, 1.0, 0.02, 24), glow_mat(c), Vector3(0, 1.25, 0), Vector3.ONE, Vector3(PI / 2, 0, 0), "Disc")
	disc.visible = false
	var base := MeshInstance3D.new(); base.name = "Base"; base.mesh = flat_quad(3.2)
	base.material_override = ring_mat(c, 0.1); base.position.y = 0.05; root.add_child(base)
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
