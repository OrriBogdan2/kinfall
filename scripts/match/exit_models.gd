class_name ExitModels
## The props for the three ways out of an expedition (see Exits): a skiff dock with its horn beacon
## and the sky-skiff that answers it, a sealed rift hatch, and an outpost's uplink mast and lift.
## Built from simple meshes like everything in Models.

const DOCK := Color("ffb84a")      # skiff docks: warm lantern amber
const HATCH := Color("b98aff")     # rift hatches: violet
const UPLINK := Color("6ae0ff")    # outpost uplinks: sky cyan

static func _beam(c: Color, h: float, r0: float, r1: float, a := 0.22) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Models.cyl(r0, r1, h, 12)
	mi.material_override = Models.glow_mat(Color(c, a))
	mi.position.y = h * 0.5
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

static func _sparks(c: Color, amount: int, radius: float, up: float, name_s: String) -> CPUParticles3D:
	var p := CPUParticles3D.new(); p.name = name_s
	p.amount = amount; p.lifetime = 1.6; p.emitting = false
	var bm := SphereMesh.new(); bm.radius = 0.07; bm.height = 0.14; bm.radial_segments = 6; bm.rings = 3
	var pm := StandardMaterial3D.new(); pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; pm.albedo_color = c.lightened(0.3)
	bm.material = pm
	p.mesh = bm
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP; p.emission_ring_radius = radius; p.emission_ring_inner_radius = radius * 0.5; p.emission_ring_height = 0.1
	p.direction = Vector3.UP; p.spread = 10.0; p.gravity = Vector3(0, up, 0)
	p.initial_velocity_min = 1.0; p.initial_velocity_max = 2.6
	p.position = Vector3(0, 0.1, 0)
	return p

## The dock: a plank pier for the skiff to settle on (local -Z points out over the abyss), mooring
## posts with lanterns, and set back from it the horn beacon you call the skiff from.
## Named children: Beacon/Lamp (lights up when called), Beacon/Flare (the tall column everyone sees),
## Berth (the deck ring), Sparks.
static func dock(beacon_off: Vector3) -> Node3D:
	var root := Node3D.new()
	var wood := Models.toon(Color("8a6040")); var dark := Models.toon(Color("5a3c28")); var rope := Models.toon(Color("d8c49a"))
	var brass := Models.toon(Color("e0b84a"), true, 0.25)
	# the pier deck: planks across, two stringers along
	for i in 9:
		Models.part(root, Models.box(3.0, 0.1, 0.52), wood if i % 2 == 0 else Models.toon(Color("9a6c48")), Vector3(0, 0.05, -2.2 + i * 0.56))
	for sx in [-1.35, 1.35]:
		Models.part(root, Models.box(0.16, 0.16, 5.2), dark, Vector3(sx, 0.12, 0))
	# mooring posts at the corners, roped together, with a lantern on the outer pair
	for sx in [-1.45, 1.45]:
		for sz in [-2.4, 2.2]:
			Models.part(root, Models.cyl(0.13, 0.15, 1.1, 8), dark, Vector3(sx, 0.55, sz))
			Models.part(root, Models.cyl(0.17, 0.17, 0.1, 8), brass, Vector3(sx, 1.1, sz))
		Models.part(root, Models.cyl(0.035, 0.035, 4.6, 6), rope, Vector3(sx, 0.85, -0.1), Vector3.ONE, Vector3(PI / 2, 0, 0))
		var lamp := Models.part(root, Models.sphere(0.16, 10), Models.toon(DOCK, false, 1.2), Vector3(sx, 1.32, -2.4))
		lamp.name = "Lantern%s" % ("L" if sx < 0 else "R")
	# the berth ring the skiff's deck covers: board inside it
	var berth := MeshInstance3D.new(); berth.name = "Berth"; berth.mesh = Models.flat_quad(4.6)
	berth.material_override = Models.ring_mat(Color(DOCK, 0.45), 0.04); berth.position.y = 0.13
	root.add_child(berth)
	# the horn beacon: a stone foot, a tall post, a brass horn and a signal lamp on top
	var b := Node3D.new(); b.name = "Beacon"; b.position = beacon_off; root.add_child(b)
	var stone := Models.toon(Color("7d7f8a"))
	Models.part(b, Models.cyl(0.55, 0.65, 0.3, 8), stone, Vector3(0, 0.15, 0))
	Models.part(b, Models.cyl(0.12, 0.15, 2.4, 8), dark, Vector3(0, 1.45, 0))
	Models.part(b, Models.cyl(0.1, 0.36, 0.7, 12), brass, Vector3(0, 2.1, -0.35), Vector3.ONE, Vector3(PI / 2 + 0.3, 0, 0))
	Models.part(b, Models.box(0.5, 0.36, 0.3), Models.toon(Color("4a4e5c")), Vector3(0, 0.95, 0.18))
	var lever := Models.part(b, Models.box(0.08, 0.4, 0.08), brass, Vector3(0.12, 1.15, 0.36), Vector3.ONE, Vector3(-0.5, 0, 0))
	lever.name = "Lever"
	var lamp2 := Models.part(b, Models.sphere(0.24, 12), Models.toon(Color("6a5a40"), true, 0.0), Vector3(0, 2.85, 0))
	lamp2.name = "Lamp"
	var flare := _beam(DOCK, 46.0, 0.35, 0.7, 0.26); flare.name = "Flare"; flare.visible = false
	b.add_child(flare)
	var ring := MeshInstance3D.new(); ring.name = "Ring"; ring.mesh = Models.flat_quad(2.4)
	ring.material_override = Models.ring_mat(Color(DOCK, 0.7), 0.08); ring.position.y = 0.32
	b.add_child(ring)
	root.add_child(_sparks(DOCK, 30, 1.8, 2.0, "Sparks"))
	return root

## The sky-skiff: a small hull with outrigger fins, a striped lift-bag and a stern propeller.
## Local -Z is the bow. The deck is flush with y = 0 so hunters standing on the pier stand on it.
static func skiff() -> Node3D:
	var root := Node3D.new()
	var wood := Models.toon(Color("7a5236")); var dark := Models.toon(Color("4e3424")); var cloth := Models.toon(Color("f2e6cf"))
	var stripe := Models.toon(Color("e08a3a")); var brass := Models.toon(Color("e0b84a"), true, 0.3)
	var hull := Node3D.new(); hull.name = "Hull"; root.add_child(hull)
	# deck and gunwales
	Models.part(hull, Models.box(2.6, 0.12, 4.6), Models.toon(Color("a07850")), Vector3(0, -0.02, 0))
	for sx in [-1.32, 1.32]:
		Models.part(hull, Models.box(0.14, 0.4, 4.4), dark, Vector3(sx, 0.18, 0))
	Models.part(hull, Models.box(2.5, 0.4, 0.14), dark, Vector3(0, 0.18, 2.25))
	# the keel below, tapering to a bow
	Models.part(hull, Models.box(2.3, 0.7, 4.2), wood, Vector3(0, -0.45, 0.1))
	var bow := PrismMesh.new(); bow.size = Vector3(2.3, 1.1, 0.7)
	Models.part(hull, bow, wood, Vector3(0, -0.3, -2.45), Vector3.ONE, Vector3(-PI / 2, 0, 0))
	# outrigger fins, like a glider's wings
	for sx in [-1.0, 1.0]:
		Models.part(hull, Models.box(1.6, 0.08, 1.4), cloth, Vector3(sx * 2.0, 0.05, 0.4), Vector3.ONE, Vector3(0, 0, sx * -0.18))
		Models.part(hull, Models.box(1.6, 0.06, 0.18), stripe, Vector3(sx * 2.0, 0.1, -0.25), Vector3.ONE, Vector3(0, 0, sx * -0.18))
	# the lift-bag on two masts
	for z in [-1.2, 1.2]:
		Models.part(hull, Models.cyl(0.06, 0.08, 2.6, 6), dark, Vector3(0, 1.3, z))
	var bag := Node3D.new(); bag.name = "Bag"; bag.position = Vector3(0, 3.1, 0); hull.add_child(bag)
	Models.part(bag, Models.sphere(1.5, 18), cloth, Vector3.ZERO, Vector3(0.95, 0.6, 1.75))
	Models.part(bag, Models.sphere(1.52, 18), stripe, Vector3.ZERO, Vector3(0.12, 0.62, 1.77))
	for z in [-1.4, 0.0, 1.4]:
		Models.part(bag, Models.cyl(1.0 - absf(z) * 0.22, 1.0 - absf(z) * 0.22, 0.2, 18), stripe, Vector3(0, 0, z), Vector3(1.4, 1, 0.6), Vector3(PI / 2, 0, 0))
	# the stern propeller and a pennant
	var prop := Node3D.new(); prop.name = "Prop"; prop.position = Vector3(0, 0.6, 2.6); hull.add_child(prop)
	Models.part(prop, Models.cyl(0.12, 0.12, 0.3, 10), brass, Vector3.ZERO, Vector3.ONE, Vector3(PI / 2, 0, 0))
	for k in 3:
		Models.part(prop, Models.box(0.14, 1.2, 0.04), wood, Vector3.ZERO, Vector3.ONE, Vector3(0, 0, TAU * k / 3.0))
	Models.part(hull, Models.box(0.04, 0.5, 0.8), Models.toon(DOCK), Vector3(0, 4.3, 0.4))
	# running lights
	for sx in [-1.32, 1.32]:
		Models.part(hull, Models.sphere(0.11, 8), Models.toon(DOCK, false, 1.4), Vector3(sx, 0.45, -2.1))
	root.add_child(_sparks(DOCK, 24, 1.6, -3.0, "Wake"))
	return root

## A rift hatch: a heavy rune-ringed stone collar set into the ground with an iron lid and a key slot.
## Named children: Lid (slides aside when opened), Rift (the swirling way down), Runes, Sparks.
static func hatch() -> Node3D:
	var root := Node3D.new()
	var stone := Models.toon(Color("6f6a7c")); var iron := Models.toon(Color("4a4858")); var rim := Models.toon(Color("8c86a0"))
	Models.part(root, Models.cyl(1.05, 1.15, 0.2, 10), stone, Vector3(0, 0.1, 0))
	Models.part(root, Models.cyl(0.98, 0.98, 0.06, 10), rim, Vector3(0, 0.21, 0))
	var runes := Node3D.new(); runes.name = "Runes"; root.add_child(runes)
	for i in 6:
		var a := TAU * i / 6.0
		Models.part(runes, Models.box(0.16, 0.05, 0.08), Models.toon(HATCH, false, 0.5), Vector3(cos(a) * 0.98, 0.23, sin(a) * 0.98), Vector3.ONE, Vector3(0, -a, 0))
	# the dark well under the lid, and the rift that swirls in it once it's open
	Models.part(root, Models.cyl(0.78, 0.78, 0.04, 16), Models.toon(Color("15121e"), false), Vector3(0, 0.2, 0))
	var rift := Node3D.new(); rift.name = "Rift"; rift.visible = false; root.add_child(rift)
	var disc := Models.part(rift, Models.cyl(0.74, 0.74, 0.02, 20), Models.glow_mat(Color(HATCH, 0.9)), Vector3(0, 0.24, 0))
	disc.name = "Disc"
	var swirl := MeshInstance3D.new(); swirl.mesh = Models.flat_quad(1.4)
	swirl.material_override = Models.ring_mat(Color(HATCH.lightened(0.4), 0.9), 0.18); swirl.position.y = 0.26
	rift.add_child(swirl)
	PropAnim.on(rift, 3.0)
	rift.add_child(_beam(HATCH, 3.5, 0.3, 0.7, 0.2))
	# the lid: an iron disc with straps and a glowing keyhole
	var lid := Node3D.new(); lid.name = "Lid"; root.add_child(lid)
	Models.part(lid, Models.cyl(0.8, 0.84, 0.12, 14), iron, Vector3(0, 0.27, 0))
	for k in [-0.35, 0.35]:
		Models.part(lid, Models.box(1.5, 0.05, 0.14), Models.toon(Color("6a6878")), Vector3(0, 0.34, k))
	var hole := Models.part(lid, Models.box(0.14, 0.05, 0.26), Models.toon(HATCH, false, 0.9), Vector3(0, 0.35, 0))
	hole.name = "Keyhole"
	root.add_child(_sparks(HATCH, 26, 0.7, 3.0, "Sparks"))
	return root

## The outpost's uplink: a stone plinth with a brass console and a tall mast topped with a crystal.
## The lift is a ring of pylons around it that opens a column of light when the uplink is complete.
## Named children: Mast/Crystal (spins and glows while charging), Charge (a ring that fills),
## Lift (the open way out), Beam (the charging column), Sparks.
static func uplink() -> Node3D:
	var root := Node3D.new()
	var stone := Models.toon(Color("8a8f9c")); var dark := Models.toon(Color("4a4e5c")); var brass := Models.toon(Color("e0b84a"), true, 0.25)
	Models.part(root, Models.cyl(0.8, 0.95, 0.36, 8), stone, Vector3(0, 0.18, 0))
	Models.part(root, Models.box(0.8, 0.7, 0.5), dark, Vector3(0, 0.7, 0.25))
	var screen := Models.part(root, Models.box(0.6, 0.36, 0.05), Models.toon(UPLINK, false, 0.6), Vector3(0, 0.82, 0.52), Vector3.ONE, Vector3(-0.35, 0, 0))
	screen.name = "Screen"
	var mast := Node3D.new(); mast.name = "Mast"; root.add_child(mast)
	Models.part(mast, Models.cyl(0.09, 0.14, 3.2, 8), dark, Vector3(0, 2.0, -0.15))
	for y in [1.4, 2.2, 3.0]:
		Models.part(mast, Models.cyl(0.32, 0.32, 0.06, 10), brass, Vector3(0, y, -0.15))
	var cr := Node3D.new(); cr.name = "Crystal"; cr.position = Vector3(0, 3.9, -0.15); mast.add_child(cr)
	var pm := PrismMesh.new(); pm.size = Vector3(0.5, 0.7, 0.5)
	var cm := Models.toon(UPLINK.darkened(0.15), true, 0.4)
	Models.part(cr, pm, cm, Vector3(0, 0.35, 0))
	Models.part(cr, pm, cm, Vector3(0, -0.35, 0), Vector3.ONE, Vector3(PI, 0, 0))
	PropAnim.on(cr, 0.6, 0.08)
	# the lift: four pylons round the plinth, and the light that opens between them
	for i in 4:
		var a := TAU * i / 4.0 + PI / 4.0
		Models.part(root, Models.box(0.3, 1.2, 0.3), stone, Vector3(cos(a) * 1.9, 0.6, sin(a) * 1.9))
		Models.part(root, Models.box(0.1, 0.6, 0.32), Models.toon(UPLINK, false, 0.7), Vector3(cos(a) * 1.9, 0.9, sin(a) * 1.9), Vector3.ONE, Vector3(0, -a, 0))
	var charge := MeshInstance3D.new(); charge.name = "Charge"; charge.mesh = Models.flat_quad(5.2)
	var chm := Models.ring_mat(Color(UPLINK.lightened(0.3), 0.95), 0.08)
	chm.set_shader_parameter("arc", 0.0)
	charge.material_override = chm; charge.position.y = 0.08
	root.add_child(charge)
	var zone := MeshInstance3D.new(); zone.name = "Zone"; zone.mesh = Models.flat_quad(5.2)
	zone.material_override = Models.ring_mat(Color(UPLINK, 0.35), 0.035); zone.position.y = 0.07
	root.add_child(zone)
	var lift := Node3D.new(); lift.name = "Lift"; lift.visible = false; root.add_child(lift)
	var pad := MeshInstance3D.new(); pad.mesh = Models.flat_quad(3.6)
	var lpm := Models.ring_mat(Color(UPLINK.lightened(0.2), 0.9), 0.1)
	lpm.set_shader_parameter("fill", 0.25)
	pad.material_override = lpm; pad.position.y = 0.09
	lift.add_child(pad)
	lift.add_child(_beam(UPLINK, 30.0, 1.5, 1.7, 0.18))
	var col := _beam(UPLINK, 34.0, 0.25, 0.4, 0.3); col.name = "Beam"; col.visible = false
	root.add_child(col)
	root.add_child(_sparks(UPLINK, 40, 1.5, 3.0, "Sparks"))
	return root

## Corner posts with pennants for an outpost on a map without authored walls.
static func palisade(half: float) -> Node3D:
	var root := Node3D.new()
	var wood := Models.toon(Color("6e5038"))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			Models.part(root, Models.cyl(0.14, 0.18, 1.8, 8), wood, Vector3(sx * half, 0.9, sz * half))
			Models.part(root, Models.box(0.04, 0.4, 0.6), Models.toon(UPLINK), Vector3(sx * half, 1.55, sz * half + 0.32))
	return root

## A Rift Key: a crystal bow on a short iron shaft.
static func rift_key() -> Node3D:
	var root := Node3D.new()
	var gem := Node3D.new(); gem.position.y = 0.32; root.add_child(gem)
	var pm := PrismMesh.new(); pm.size = Vector3(0.22, 0.26, 0.12)
	var cm := Models.toon(HATCH, true, 0.9)
	Models.part(gem, pm, cm, Vector3(0, 0.13, 0))
	Models.part(gem, pm, cm, Vector3(0, -0.13, 0), Vector3.ONE, Vector3(PI, 0, 0))
	var iron := Models.toon(Color("c8c4d8"), true, 0.2)
	Models.part(root, Models.box(0.05, 0.34, 0.05), iron, Vector3(0, 0.02, 0))
	Models.part(root, Models.box(0.12, 0.05, 0.05), iron, Vector3(0.06, -0.08, 0))
	Models.part(root, Models.box(0.08, 0.05, 0.05), iron, Vector3(0.04, 0.02, 0))
	var halo := MeshInstance3D.new(); halo.mesh = Models.flat_quad(0.9)
	halo.material_override = Models.ring_mat(Color(HATCH, 0.7), 0.12); halo.position.y = -0.2
	root.add_child(halo)
	return root
