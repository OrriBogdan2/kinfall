extends Node3D
## Title screen: the moment before the drop. Your hunter stands at the bow of the skyship with
## their kin, high over the islands at sunset. Other hunters are already gliding down toward the
## light pillars below, clouds slide past the hull and the ship rolls gently under you.

var cam: Camera3D
var t := 0.0
var ship: Node3D                 # the deck you stand on; the camera rides it
var hunter_node: Node3D
var h_anim: HunterAnim
var kin_nodes: Array = []
var gliders: Array = []          # {node, anim, vel, t, life}
var clouds: Array = []           # {node, speed}
var birds: Node3D
var flag: Node3D
var islands: Array = []          # [node, base y, bob phase]
var logo: Control
var rng := RandomNumberGenerator.new()

const DECK_Y := 0.0
const SUN := Vector3(0.42, 0.1, -0.9)

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.play_music("title")
	Sfx.play_ambience("home")
	rng.seed = 2026
	var env := WorldEnvironment.new()
	env.environment = Look.environment({"top": Color("1a1c4a"), "mid": Color("6a4f9e"), "horizon": Color("ffae6e"), "below": Color("4a3a72"),
		"sun_dir": SUN.normalized(), "sun_col": Color("ffd2a0"), "ambient": Color("d0bce6"), "ambient_energy": 0.6,
		"fog": Color("9a72b0"), "fog_density": 0.0011, "fog_height": -50.0, "fog_height_density": 0.015, "stars": 0.6, "saturation": 1.0, "exposure": 1.0})
	add_child(env)
	# the low sun ahead and to the right: rims everything in gold
	var sun := Look.lights(self, Color("ffe6cc"), 1.05, Vector3(-30, 150, 0), 70.0)
	sun.shadow_opacity = 0.55
	var fill: DirectionalLight3D = get_node("Fill")
	fill.light_energy = 0.6
	fill.light_color = Color("b9a8ff")
	# the sea of clouds, far below
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(6000, 6000)
	sea.mesh = pm
	var cm := ShaderMaterial.new(); cm.shader = load("res://shaders/clouds.gdshader")
	cm.set_shader_parameter("deep", Color("2e2858")); cm.set_shader_parameter("light", Color("b08ad8"))
	cm.set_shader_parameter("glow", Color("ffb070")); cm.set_shader_parameter("glow_amount", 0.85)
	cm.set_shader_parameter("sun_xz", Vector2(SUN.x, SUN.z)); cm.set_shader_parameter("scale", 0.012)
	sea.material_override = cm
	sea.position = Vector3(0, -78.0, 0)
	add_child(sea)
	_archipelago()
	_build_ship()
	_crew()
	_build_clouds()
	_build_birds()
	for i in 4:
		_spawn_glider(i * 2.6)
	_build_ui()

# ---------------------------------------------------------------- the skyship
## Half the deck's width at a point along it: a pointed bow ahead (-z), a squared stern behind.
static func _half_w(z: float) -> float:
	const BOW := -7.0
	const MID := -1.6
	if z < MID:
		return 2.35 * pow(clampf((z - BOW) / (MID - BOW), 0.0, 1.0), 0.62)
	return 2.35 - maxf(0.0, z - 2.6) * 0.3

static func _outline() -> Array:
	var right: Array = []
	var n := 26
	for i in n + 1:
		var z := lerpf(-7.0, 4.6, float(i) / n)
		right.append(Vector2(_half_w(z), z))
	var out: Array = right.duplicate()
	for i in range(n, 0, -1):
		var p: Vector2 = right[i]
		out.append(Vector2(-p.x, p.y))
	# the bow tip appears once; the list runs from the tip down the right side and back up the left
	return out

func _build_ship() -> void:
	ship = Node3D.new(); ship.name = "Ship"
	add_child(ship)
	var wood := Models.toon(Color("7a5236")); var dark := Models.toon(Color("4e3424")); var deck_c := Color("8a6a4e")
	var stripe := Models.toon(Color("d9604a")); var brass := Models.toon(Color("e0b84a"), true, 0.3)
	var ol := _outline()
	var n := ol.size()
	# deck: a fan from the middle, with plank seams painted in as stripes of vertex colour
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cen := Vector3(0, DECK_Y, -1.0)
	for i in n:
		var a2: Vector2 = ol[i]; var b2: Vector2 = ol[(i + 1) % n]
		for v in [cen, Vector3(a2.x, DECK_Y, a2.y), Vector3(b2.x, DECK_Y, b2.y)]:
			st.set_normal(Vector3.UP)
			st.set_color(deck_c)
			st.add_vertex(v)
	var deck := MeshInstance3D.new(); deck.mesh = st.commit()
	deck.material_override = Models.toon(Color("8c7764"), false)
	ship.add_child(deck)
	for k in 13:
		var x := -2.2 + k * 0.36
		var z0 := -7.0
		while z0 < 4.6 and _half_w(z0) < absf(x) + 0.05:
			z0 += 0.05
		if z0 >= 4.5: continue
		var len := 4.55 - z0
		Models.part(ship, Models.box(0.025, 0.01, len), Models.toon(Color("7a5236"), false), Vector3(x, DECK_Y + 0.006, z0 + len * 0.5))
	# hull: the sides sweep down and in to a keel, with a red stripe under the rail
	var hs := SurfaceTool.new(); hs.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = [[1.0, 0.0, 0.0], [1.02, -0.35, 0.0], [0.86, -1.3, 0.25], [0.42, -2.3, 0.6]]
	var cols := [Color("8a5f3c"), Color("d9604a"), Color("7a5236"), Color("5a3b26")]
	for r in rings.size() - 1:
		var ra: Array = rings[r]; var rb: Array = rings[r + 1]
		for i in n:
			var p0: Vector2 = ol[i]; var p1: Vector2 = ol[(i + 1) % n]
			var a := Vector3(p0.x * ra[0], DECK_Y + ra[1], p0.y * ra[0] + ra[2]); var b := Vector3(p1.x * ra[0], DECK_Y + ra[1], p1.y * ra[0] + ra[2])
			var c := Vector3(p1.x * rb[0], DECK_Y + rb[1], p1.y * rb[0] + rb[2]); var d := Vector3(p0.x * rb[0], DECK_Y + rb[1], p0.y * rb[0] + rb[2])
			var nrm := (d - a).cross(b - a).normalized()
			if nrm.dot(Vector3(a.x, 0, a.z + 1.0)) < 0.0: nrm = -nrm
			for v in [a, b, c, a, c, d]:
				hs.set_normal(nrm)
				hs.set_color(cols[r] if r != 0 else cols[1])
				hs.add_vertex(v)
	var hull := MeshInstance3D.new(); hull.mesh = hs.commit()
	var hm := Models.vtoon()
	hm.set_shader_parameter("albedo", Color(0.8, 0.78, 0.8))
	hull.material_override = hm
	ship.add_child(hull)
	# gunwale: posts and a rail all the way round
	for i in n:
		var p0: Vector2 = ol[i] * 0.97; var p1: Vector2 = ol[(i + 1) % n] * 0.97
		var a := Vector3(p0.x, DECK_Y + 0.7, p0.y); var b := Vector3(p1.x, DECK_Y + 0.7, p1.y)
		if a.distance_to(b) < 0.01: continue
		var r := Models.part(ship, Models.box(0.1, 0.08, a.distance_to(b) + 0.06), wood, (a + b) * 0.5)
		r.look_at_from_position((a + b) * 0.5, b, Vector3.UP)
		if i % 2 == 0:
			Models.part(ship, Models.box(0.08, 0.7, 0.08), dark, Vector3(p0.x, DECK_Y + 0.35, p0.y))
	# the bowsprit, with a pennant at its tip
	var spr := Models.part(ship, Models.cyl(0.05, 0.1, 3.4, 8), wood, Vector3(0, DECK_Y + 0.9, -8.2), Vector3.ONE, Vector3(-PI / 2 + 0.35, 0, 0))
	spr.name = "Bowsprit"
	Models.part(ship, Models.sphere(0.1, 8), brass, Vector3(0, DECK_Y + 1.45, -9.75))
	flag = Node3D.new(); flag.position = Vector3(0, DECK_Y + 1.5, -9.8); ship.add_child(flag)
	var pen := Models.part(flag, Models.cyl(0.0, 0.22, 1.1, 3), Models.toon(UI.ACCENT), Vector3(0, 0, 0.55), Vector3(1.0, 1.0, 0.18), Vector3(PI / 2, 0, PI / 2))
	pen.name = "Pennant"
	# a lantern on a post by the bow, glowing warm
	Models.part(ship, Models.cyl(0.05, 0.06, 1.6, 8), dark, Vector3(1.3, DECK_Y + 0.8, -3.2))
	Models.part(ship, Models.box(0.5, 0.05, 0.05), dark, Vector3(1.15, DECK_Y + 1.58, -3.2))
	Models.part(ship, Models.box(0.2, 0.26, 0.2), Models.toon(Color("ffd890"), true, 0.7), Vector3(0.95, DECK_Y + 1.38, -3.2))
	var lamp := OmniLight3D.new(); lamp.light_color = Color("ffc070"); lamp.light_energy = 0.8; lamp.omni_range = 4.0
	lamp.position = Vector3(0.95, DECK_Y + 1.3, -3.2); ship.add_child(lamp)
	# cargo: crates, a barrel, a coil of rope, a ship's bell
	var crate := Models.breakable("crate"); crate.position = Vector3(1.55, DECK_Y, -1.2); crate.rotation.y = 0.3; ship.add_child(crate)
	var crate2 := Models.breakable("crate"); crate2.position = Vector3(1.5, DECK_Y + 0.6, -1.15); crate2.rotation.y = -0.2; crate2.scale = Vector3.ONE * 0.8; ship.add_child(crate2)
	var crate3 := Models.breakable("crate"); crate3.position = Vector3(1.0, DECK_Y, -0.3); crate3.rotation.y = 0.9; ship.add_child(crate3)
	var coil := TorusMesh.new(); coil.inner_radius = 0.16; coil.outer_radius = 0.32
	Models.part(ship, coil, Models.toon(Color("e8d8b0")), Vector3(1.4, DECK_Y + 0.06, -1.6), Vector3(1.0, 0.6, 1.0))
	Models.part(ship, coil, Models.toon(Color("e8d8b0")), Vector3(1.4, DECK_Y + 0.14, -1.6), Vector3(0.8, 0.6, 0.8))
	# the balloon overhead, and the ropes that hold it
	var cloth := Models.toon(Color("f2e6cf"))
	Models.part(ship, Models.sphere(4.6, 26), cloth, Vector3(0, DECK_Y + 9.2, 0.6), Vector3(1.0, 0.72, 1.75))
	for i in 3:
		Models.part(ship, Models.cyl(3.7 * (1.0 - absf(i - 1) * 0.16), 3.7 * (1.0 - absf(i - 1) * 0.16), 0.5, 26), stripe, Vector3(0, DECK_Y + 9.2, -3.4 + i * 4.0), Vector3(1.0, 1.0, 0.74), Vector3(PI / 2, 0, 0))
	var rope := Models.toon(Color("5a4636"), false)
	for sx in [-1.0, 1.0]:
		for z in ([-4.6, -2.2] if sx < 0.0 else [-4.6, -2.2, 0.4, 2.8]):
			var a := Vector3(_half_w(z) * 0.97 * sx, DECK_Y + 0.7, z)
			var b := Vector3(2.6 * sx, DECK_Y + 6.4, z * 0.8 + 0.4)
			var rr := Models.part(ship, Models.cyl(0.02, 0.02, a.distance_to(b), 4), rope, (a + b) * 0.5)
			rr.look_at_from_position((a + b) * 0.5, b, Vector3.FORWARD if absf((b - a).normalized().y) > 0.99 else Vector3.UP)
			rr.rotate_object_local(Vector3.RIGHT, PI / 2)
	# the camera rides along, a few steps behind you on the deck
	cam = Camera3D.new(); cam.fov = 50.0; cam.far = 4000.0
	ship.add_child(cam)

## You at the bow, your kin around you.
func _crew() -> void:
	var hero: String = Save.d.get("hero", "")
	if not Data.HEROES.has(hero): hero = "sage"
	var w: String = Save.d.get("weapon", "")
	if not Data.CLASSES[Data.HEROES[hero]["cls"]]["weapons"].has(w): w = Data.HEROES[hero]["weapon"]
	hunter_node = Models.hunter(Data.HEROES[hero]["cls"], Data.TEAM_COLORS[0], w, hero, Save.d.get("look", {}))
	hunter_node.position = Vector3(0.15, DECK_Y, -4.7)
	hunter_node.rotation.y = -0.35
	hunter_node.scale *= 1.1
	(hunter_node.get_node("TeamRing") as Node3D).visible = false
	ship.add_child(hunter_node)
	h_anim = HunterAnim.new(hunter_node)
	var recs: Array = []
	var ak := Save.active_kin()
	if not ak.is_empty(): recs.append(ak)
	for r in Save.d.get("roster", []):
		if recs.size() >= 3: break
		if not recs.has(r): recs.append(r)
	var fallback := ["cindle", "puddlet", "zapple"]
	while recs.size() < 3:
		recs.append({"species": fallback[recs.size()], "level": 5})
	# the first rides your shoulder, one perches on the rail beside you, one bounces on a crate
	var spots := [null, Vector3(-0.85, DECK_Y + 0.74, -5.2), Vector3(0.95, DECK_Y, -3.7)]
	for i in recs.size():
		var k := Models.kin(String(recs[i]["species"]), recs[i])
		if i == 0:
			var sh: Node3D = hunter_node.get_node("Rig/Torso/Shoulder")
			sh.add_child(k)
			k.scale = Vector3.ONE * 0.62
			k.rotation.y = 0.2
		else:
			k.position = spots[i]
			k.rotation.y = 0.4 if i == 1 else -0.9
			k.scale *= 0.95
			ship.add_child(k)
		var aura: CPUParticles3D = k.get_node_or_null("Aura")
		if aura: aura.emitting = true
		kin_nodes.append(k)

# ---------------------------------------------------------------- the islands below
func _archipelago() -> void:
	var spots := [[Vector3(72, -34, -78), 14.0, "heart"], [Vector3(22, -34, -50), 6.0, ""], [Vector3(-44, -32, -56), 7.5, "beacon"],
		[Vector3(36, -27, -108), 9.0, "beacon"], [Vector3(-36, -40, -124), 10.0, ""], [Vector3(6, -44, -160), 13.0, "beacon"],
		[Vector3(64, -36, -168), 11.0, ""], [Vector3(110, -40, -120), 12.0, "beacon"], [Vector3(46, -26, -44), 5.0, ""], [Vector3(-72, -30, -140), 8.5, "beacon"], [Vector3(-30, -38, -76), 8.0, ""],
		[Vector3(-24, -46, -34), 4.5, ""], [Vector3(14, -22, -30), 3.2, ""], [Vector3(-90, -38, -210), 14.0, ""], [Vector3(90, -46, -240), 16.0, ""]]
	var beacon_cols := [Color("8ae8ff"), Color("c9a0ff"), Color("ffd25a"), Color("8ae8ff")]
	var bi := 0
	for sp in spots:
		var r: float = sp[1]
		var isl := _scenery_island(rng, r, true, r > 5.0 and rng.randf() < 0.6)
		isl.position = sp[0]
		isl.rotation.y = rng.randf() * TAU
		add_child(isl)
		islands.append([isl, float((sp[0] as Vector3).y), rng.randf() * TAU])
		match String(sp[2]):
			"heart": _heart(isl, r)
			"beacon":
				_beacon(isl, beacon_cols[bi % beacon_cols.size()], r)
				bi += 1

## The Heart: a great crystal at the middle of the islands, with a light that climbs into the sky.
func _heart(isl: Node3D, r: float) -> void:
	var cm := Models.toon(Color("8ae8ff"), true, 1.3)
	var pm := PrismMesh.new(); pm.size = Vector3(2.6, 6.5, 2.6)
	var spire := Node3D.new(); spire.position = Vector3(0, 3.6, 0); isl.add_child(spire)
	Models.part(spire, pm, cm, Vector3(0, 1.0, 0))
	Models.part(spire, pm, cm, Vector3(0, -1.4, 0), Vector3(1.0, 0.5, 1.0), Vector3(PI, 0, 0))
	for i in 5:
		var a := TAU * i / 5.0
		Models.part(spire, pm, cm, Vector3(cos(a) * 1.4, -0.8, sin(a) * 1.4), Vector3(0.45, 0.5, 0.45), Vector3(sin(a) * 0.4, 0, -cos(a) * 0.4))
	PropAnim.on(spire, 0.25, 0.3, 0.8)
	var beam := Models.part(isl, Models.cyl(1.4, 2.4, 120.0, 16), Models.glow_mat(Color(0.55, 0.9, 1.0, 0.24)), Vector3(0, 62.0, 0))
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ring := MeshInstance3D.new(); ring.mesh = Models.flat_quad(r * 1.3)
	ring.material_override = Models.ring_mat(Color(0.55, 0.9, 1.0, 0.6), 0.04); ring.position.y = 0.1
	isl.add_child(ring)

func _beacon(isl: Node3D, c: Color, r: float) -> void:
	var a := rng.randf() * TAU
	var at := Vector3(cos(a), 0, sin(a)) * r * 0.35
	var ch := Models.chest(2 if c.b < 0.6 else 1)
	ch.position = at; ch.scale = Vector3.ONE * 1.6
	isl.add_child(ch)
	var beam := Models.part(isl, Models.cyl(0.7, 1.1, 70.0, 10), Models.glow_mat(Color(c, 0.3)), at + Vector3(0, 35.0, 0))
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

# ---------------------------------------------------------------- life in the sky
## Another hunter jumps off the ship and glides down toward the islands.
func _spawn_glider(age := 0.0) -> void:
	var heroes: Array = Data.HEROES.keys()
	var hero: String = heroes[rng.randi_range(0, heroes.size() - 1)]
	var team := rng.randi_range(1, Data.TEAM_COLORS.size() - 1)
	var lk := {"gender": rng.randi() % 2, "face": rng.randi() % Models.LOOK_FACES.size(), "skin": rng.randi() % Models.LOOK_SKIN.size(), "hair": rng.randi() % Models.LOOK_HAIRS.size(), "hair_col": rng.randi() % Models.LOOK_HAIR.size()}
	var h := Models.hunter(Data.HEROES[hero]["cls"], Data.TEAM_COLORS[team], Data.HEROES[hero]["weapon"], hero, lk)
	(h.get_node("TeamRing") as Node3D).visible = false
	var gl: Node3D = h.get_node("Rig/Torso/Glider")
	gl.visible = true
	gl.rotation.x = 0.25
	h.scale *= 1.25
	add_child(h)
	# they jump off the starboard side, out in the open part of the view
	var start := Vector3(rng.randf_range(4.0, 11.0), rng.randf_range(-1.0, 2.5), rng.randf_range(-24.0, -14.0))
	var vel := Vector3(rng.randf_range(0.3, 1.6), -1.3, -rng.randf_range(3.5, 5.0))
	var g := {"node": h, "anim": HunterAnim.new(h), "vel": vel, "t": age, "life": 22.0, "start": start}
	h.position = start + vel * age
	h.rotation.y = atan2(-vel.x, -vel.z)
	gliders.append(g)

func _build_clouds() -> void:
	var sh: Shader = load("res://shaders/cloud_puff.gdshader")
	for i in 22:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new(); var s := rng.randf_range(8.0, 22.0); q.size = Vector2(s * 1.6, s)
		mi.mesh = q
		var m := ShaderMaterial.new(); m.shader = sh
		m.set_shader_parameter("seed", rng.randf() * 10.0)
		m.set_shader_parameter("alpha", rng.randf_range(0.55, 0.9))
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(rng.randf_range(-70, 70), rng.randf_range(-26, 6), rng.randf_range(-200, 30))
		if absf(mi.position.x) < 9.0 and mi.position.y > -8.0: mi.position.x += 14.0 * signf(mi.position.x + 0.01)
		add_child(mi)
		clouds.append({"node": mi, "speed": rng.randf_range(3.5, 6.5)})

func _build_birds() -> void:
	birds = Node3D.new(); birds.position = Vector3(-14, 6.0, -40); add_child(birds)
	var m := Models.toon(Color("3a2f48"), false)
	for i in 7:
		var b := Node3D.new()
		var row := (i + 1) / 2
		b.position = Vector3((1 if i % 2 == 0 else -1) * row * 0.9, 0, row * 0.8)
		birds.add_child(b)
		for sx in [-1.0, 1.0]:
			var wing := Node3D.new(); wing.name = "W%d" % int(sx); b.add_child(wing)
			Models.part(wing, Models.box(0.55, 0.03, 0.18), m, Vector3(0.28 * sx, 0, 0))
		Models.part(b, Models.sphere(0.09, 6), m, Vector3.ZERO, Vector3(0.8, 0.8, 1.6))

func _scenery_island(rr: RandomNumberGenerator, r: float, trees: bool, falls: bool) -> Node3D:
	var root := Node3D.new()
	var tops := [Color("6aa64a"), Color("7cbc6c"), Color("c99a4c"), Color("8ab86a")]
	var isl := Models.float_island(rr, r, r * rr.randf_range(1.4, 2.0), tops[rr.randi_range(0, tops.size() - 1)], Color("9a7a5a"), Color("3a2f48"))
	root.add_child(isl)
	_grass_on(root, isl, rr, int(r * r * 6.0))
	if trees:
		for k in rr.randi_range(1, 3):
			var a := rr.randf() * TAU
			var tr := Models.tree(rr, Color("5a9a4f").lerp(Color("e0743a"), 0.4 if rr.randf() < 0.3 else 0.0), "pine" if rr.randf() < 0.35 else ("blossom" if rr.randf() < 0.25 else "round"))
			tr.position = Vector3(cos(a), 0, sin(a)) * r * rr.randf_range(0.1, 0.55)
			tr.scale = Vector3.ONE * rr.randf_range(1.0, 1.5)
			root.add_child(tr)
	if falls:
		var rim: Array = isl.get_meta("rim")
		var p2: Vector2 = rim[rr.randi_range(0, rim.size() - 1)]
		var wf := Models.waterfall(r * 0.3, 18.0)
		wf.position = Vector3(p2.x * 0.97, -0.05, p2.y * 0.97)
		wf.rotation.y = atan2(p2.x, p2.y)
		root.add_child(wf)
	return root

func _grass_on(root: Node3D, isl: MeshInstance3D, rr: RandomNumberGenerator, n: int, size := 1.0) -> void:
	var rim: Array = isl.get_meta("rim")
	var rmin := 1e9
	for p in rim: rmin = minf(rmin, (p as Vector2).length())
	var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.use_colors = true; mm.mesh = Models.grass_mesh(false)
	mm.instance_count = n
	for k in n:
		var a := rr.randf() * TAU
		var d := sqrt(rr.randf()) * rmin * 0.95
		var sc := rr.randf_range(0.9, 1.8) * size
		mm.set_instance_transform(k, Transform3D(Basis(Vector3.UP, rr.randf() * TAU).scaled(Vector3.ONE * sc), Vector3(cos(a) * d, 0.0, sin(a) * d)))
		mm.set_instance_color(k, Color("7cbc5a").lerp(Color("4e8a3e"), rr.randf()))
	var mi := MultiMeshInstance3D.new(); mi.multimesh = mm
	mi.material_override = Models.grass_material(0.1)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var fm := MultiMesh.new(); fm.transform_format = MultiMesh.TRANSFORM_3D; fm.use_colors = true; fm.mesh = Models.flower_mesh()
	fm.instance_count = n / 8
	var fc := [Color("fff3a8"), Color("ff9ac8"), Color("ffffff"), Color("b8a6ff")]
	for k in fm.instance_count:
		var a := rr.randf() * TAU
		var d := sqrt(rr.randf()) * rmin * 0.9
		fm.set_instance_transform(k, Transform3D(Basis(Vector3.UP, rr.randf() * TAU).scaled(Vector3.ONE * 1.3), Vector3(cos(a) * d, 0.0, sin(a) * d)))
		fm.set_instance_color(k, fc[rr.randi_range(0, fc.size() - 1)])
	var fi := MultiMeshInstance3D.new(); fi.multimesh = fm
	fi.material_override = Models.grass_material(0.05, true)
	fi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(fi)

func _build_ui() -> void:
	var ui := CanvasLayer.new(); add_child(ui)
	var root := Control.new(); root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.theme = UI.theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	# a soft shade on the left so the menu reads over the scene, and a gentle vignette
	var shade := TextureRect.new()
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.set_color(0, Color(0.04, 0.03, 0.1, 0.78)); gr.set_color(1, Color(0.04, 0.03, 0.1, 0.0))
	gr.set_offset(0, 0.3); gr.set_offset(1, 1.0)
	gt.gradient = gr; gt.fill_from = Vector2(0, 0); gt.fill_to = Vector2(1, 0); gt.width = 256; gt.height = 4
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	shade.offset_right = 820
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	var vig := TextureRect.new()
	var vt := GradientTexture2D.new(); var vg := Gradient.new()
	vg.set_color(0, Color(0, 0, 0, 0.0)); vg.set_color(1, Color(0.02, 0.01, 0.06, 0.55)); vg.set_offset(0, 0.55); vg.set_offset(1, 1.0)
	vt.gradient = vg; vt.fill = GradientTexture2D.FILL_RADIAL; vt.fill_from = Vector2(0.5, 0.5); vt.fill_to = Vector2(1.05, 1.05); vt.width = 128; vt.height = 128
	vig.texture = vt; vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vig)
	# the menu column stays vertically centred and fits any window height
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	col.offset_left = 72; col.offset_right = 520; col.offset_top = 24; col.offset_bottom = -40
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 12)
	root.add_child(col)
	logo = TitleLogo.new()
	logo.custom_minimum_size = Vector2(440, 190)
	col.add_child(logo)
	var tag := UI.label("Raise them. Risk them. Bring them home.", 20, Color("ffe6c8"))
	tag.autowrap_mode = TextServer.AUTOWRAP_OFF
	tag.add_theme_constant_override("outline_size", 6)
	tag.add_theme_color_override("font_outline_color", Color(0.06, 0.04, 0.12, 0.8))
	col.add_child(tag)
	col.add_child(UI.spacer(10))
	var has: bool = not Save.d["roster"].is_empty()
	var b1 := UI.primary(("Continue  ·  %s" % Save.d.get("name", "Hunter")) if has else "New game", func(): Game.goto("home" if has else "hatch"), 320)
	col.add_child(b1)
	col.add_child(UI.button("Save files", func(): Overlay.ctx = "title"; Overlay.open_saves(), 320))
	if Bridge.net_available():
		col.add_child(UI.button("Play online with friends", func(): Game.goto("lobby", {}), 320))
	var srv := UI.button("Servers  ·  coming soon", func(): pass, 320)
	srv.disabled = true
	srv.tooltip_text = "Dedicated servers are on the way. For now, play online with friends from the lobby."
	col.add_child(srv)
	col.add_child(UI.button("Settings", func(): Overlay.ctx = "title"; Overlay.open_settings(), 320))
	if not OS.has_feature("web"):
		col.add_child(UI.button("Quit", func(): get_tree().quit(), 320))
	for ch in col.get_children():
		if ch is Button: (ch as Button).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var i := 0
	for ch in col.get_children():
		UI.pop_in(ch, 0.15 + i * 0.08)
		i += 1
	var ver := UI.label("Open source · made with Godot", 13, Color(1, 1, 1, 0.55))
	ver.autowrap_mode = TextServer.AUTOWRAP_OFF
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	ver.position = Vector2(24, -36)
	root.add_child(ver)
	b1.grab_focus()

func _process(delta: float) -> void:
	t += delta
	# the ship rolls and pitches a little; the camera rides with it and drifts slowly
	ship.rotation = Vector3(sin(t * 0.37) * 0.008, sin(t * 0.11) * 0.01, sin(t * 0.53) * 0.012)
	ship.position.y = sin(t * 0.61) * 0.18
	var sway := sin(t * 0.07)
	cam.position = Vector3(-3.4 + sway * 0.35, DECK_Y + 3.5 + sin(t * 0.23) * 0.08, 1.6 + sway * 0.2)
	cam.look_at(ship.to_global(Vector3(2.0 + sway * 0.4, -4.0, -19.0)), Vector3.UP)
	if flag:
		flag.rotation = Vector3(sin(t * 7.0) * 0.12, PI / 2 + sin(t * 4.3) * 0.25, 0)
	for isl in islands:
		var n: Node3D = isl[0]
		n.position.y = float(isl[1]) + sin(t * 0.35 + float(isl[2])) * 0.6
	# clouds slide past as the ship sails on
	for c in clouds:
		var n: Node3D = c["node"]
		n.position.z += float(c["speed"]) * delta
		if n.position.z > 40.0:
			n.position.z = rng.randf_range(-220.0, -180.0)
			n.position.x = rng.randf_range(-70, 70)
			if absf(n.position.x) < 9.0: n.position.x += 14.0 * signf(n.position.x + 0.01)
	# gliders drift down and away; when one is gone another jumps
	for g in gliders.duplicate():
		g["t"] = float(g["t"]) + delta
		var h: Node3D = g["node"]
		var v: Vector3 = g["vel"]
		h.position = (g["start"] as Vector3) + v * float(g["t"]) + Vector3(sin(float(g["t"]) * 0.7) * 1.2, 0, 0)
		var grow := clampf(float(g["t"]) / 0.8, 0.0, 1.0) * clampf((float(g["life"]) - float(g["t"])) / 1.5, 0.0, 1.0)
		h.scale = Vector3.ONE * 1.25 * grow
		(g["anim"] as HunterAnim).update(delta, {"gliding": true, "grounded": false, "vel": v, "face": h.rotation.y})
		if float(g["t"]) > float(g["life"]):
			h.queue_free()
			gliders.erase(g)
			_spawn_glider()
	# birds wheel in the distance
	if birds:
		birds.position = Vector3(-14 + sin(t * 0.05) * 30.0, 6.0 + sin(t * 0.2) * 1.5, -40 + cos(t * 0.05) * 10.0)
		birds.rotation.y = atan2(-cos(t * 0.05) * 1.5, sin(t * 0.05) * 0.5) * 0.0 + PI * 0.5 + sin(t * 0.05) * 0.6
		for i in birds.get_child_count():
			var b := birds.get_child(i)
			for sx in [-1, 1]:
				var w := b.get_node_or_null("W%d" % sx) as Node3D
				if w: w.rotation.z = sin(t * 9.0 + i * 0.7) * 0.6 * sx
	# you, looking out over the islands, and your kin
	if h_anim:
		h_anim.update(delta, {"face": hunter_node.rotation.y, "fired": 99.0})
	for i in kin_nodes.size():
		var k: Node3D = kin_nodes[i]
		if i == 2:
			# hopping excitedly beside you
			k.get_node("Body").position.y = absf(sin(t * 4.2)) * 0.3
			k.set_meta("happy", true)
		elif i == 1:
			k.get_node("Body").position.y = absf(sin(t * 1.3)) * 0.04

## The game's name, drawn big: a chunky extruded word with a warm glow and a little paraglider
## sailing over it.
class TitleLogo extends Control:
	var tt := 0.0
	func _process(delta: float) -> void:
		tt += delta
		queue_redraw()
	func _draw() -> void:
		var f: Font = UI.big
		var txt := "KINFALL"
		var fs := 108
		var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var base := Vector2(4, size.y - 34)
		# warm glow behind
		draw_string_outline(f, base, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 46, Color(1.0, 0.55, 0.25, 0.12))
		draw_string_outline(f, base, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 26, Color(1.0, 0.6, 0.3, 0.16))
		# extrusion: stacked copies going down, dark plum
		for i in range(9, 0, -1):
			var c := Color("3a1f3e").lerp(Color("7a3a3a"), 1.0 - float(i) / 9.0)
			draw_string_outline(f, base + Vector2(0, i * 1.4), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 14, c)
			draw_string(f, base + Vector2(0, i * 1.4), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
		# ink outline, the face, then a light bevel on top
		draw_string_outline(f, base, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 14, Color("2a1530"))
		draw_string(f, base, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("f7a03c"))
		draw_string(f, base + Vector2(0, -3), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.86, 0.5, 0.55))
		draw_string(f, base + Vector2(0, -6), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.95, 0.75, 0.18))
		# a paraglider sailing over the word, bobbing a little
		var gx := 4 + w * 0.62 + sin(tt * 0.8) * 6.0
		var gy := base.y - fs * 0.92 + sin(tt * 1.3) * 4.0
		var span := 74.0
		var pts := PackedVector2Array()
		var pts2 := PackedVector2Array()
		for k in 21:
			var u := float(k) / 20.0 * 2.0 - 1.0
			pts.append(Vector2(gx + u * span, gy + u * u * 18.0))
			pts2.append(Vector2(gx + u * span * 0.94, gy + u * u * 18.0 + 11.0 * (1.0 - absf(u) * 0.6)))
		var poly := PackedVector2Array(pts)
		for k in range(pts2.size() - 1, -1, -1): poly.append(pts2[k])
		draw_colored_polygon(poly, Color("f3eee2"))
		for k in [5, 10, 15]:
			var st := PackedVector2Array([pts[k], pts[k + 2], pts2[k + 2], pts2[k]])
			draw_colored_polygon(st, Color("f2a24a"))
		draw_polyline(pts, Color("2a1530"), 3.0, true)
		draw_polyline(pts2, Color("2a1530"), 3.0, true)
		# lines down to a tiny rider with a kin on their shoulder
		var rider := Vector2(gx, gy + 52)
		for k in [2, 8, 12, 18]:
			draw_line(pts2[k], rider, Color(0.16, 0.08, 0.2, 0.8), 1.5, true)
		draw_circle(rider, 7.0, Color("2a1530"))
		draw_circle(rider + Vector2(0, 1), 5.0, Color("5ab0f0"))
		draw_circle(rider + Vector2(8, -4), 4.0, Color("ff7a3d"))
