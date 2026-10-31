class_name BossModels
## The bodies of the three lair bosses, their ward stones, and the lair's own pieces: the gate, the
## sealing dome, the dial that opens it, rune pylons and the Rare Egg.
##   Stone Colossus (colossus)  a KayKit warrior grown huge and turned to stone: moss, boulder pauldrons, gold rune eyes
##   Stormcoil      (serpent)   a sky serpent: a long chain of storm-blue coils behind a horned head, swept wings
##   Brood Mother   (brood)     a giant hive queen: a spider-legged thorax and a swollen, glowing egg sac
## Every model has root > "Body", like the other monsters, and lists its materials in meta "mats" so
## hits flash it.

static func build(kind: String) -> Node3D:
	match kind:
		"colossus": return colossus()
		"serpent": return serpent()
		"brood": return brood()
		"ward": return ward()
	return null

static func _mats_of(n: Node3D, extra: Array) -> Array:
	var out: Array = n.get_meta("mats", []).duplicate()
	out.append_array(extra)
	return out

# ------------------------------------------------------------------ the Stone Colossus
static func colossus() -> Node3D:
	var stone := Color("9c968a")
	var moss := Color("6f9a4a")
	var gold := Models.toon(Color("ffd36a"), false, 1.3)
	var pk: Node3D = Assets.mob("colossus", moss) if Assets.on() else null
	var extra: Array = [gold]
	var root: Node3D
	if pk:
		root = pk
		# the bones turn to weathered stone; the cloth to moss
		for mat in root.get_meta("mats", []):
			var sm := mat as ShaderMaterial
			if sm == null or not sm.has_meta("pack_part"): continue
			if sm.get_meta("pack_part") == "bone": sm.set_shader_parameter("albedo", stone)
			else: sm.set_shader_parameter("recolor_to", moss)
	else:
		root = Models.mob("warden")
		root.scale = Vector3.ONE * 1.7
	var body: Node3D = root.get_node("Body")
	var rk := Models.toon(Color("7a756c"))
	var mk := Models.toon(moss.darkened(0.1), false)
	extra.append_array([rk, mk])
	var sk := root.find_child("Skeleton3D", true, false) as Skeleton3D
	var at_bone := func(bone: String, fallback: Vector3) -> Node3D:
		if sk and sk.find_bone(bone) >= 0:
			var ba := BoneAttachment3D.new(); ba.bone_name = bone
			sk.add_child(ba)
			var holder := Node3D.new()
			# the skeleton is scaled down inside the model; undo it so parts are sized in metres
			holder.scale = Vector3.ONE / maxf(0.001, sk.global_transform.basis.get_scale().x if sk.is_inside_tree() else _scale_of(sk))
			ba.add_child(holder)
			return holder
		var n := Node3D.new(); n.position = fallback; body.add_child(n)
		return n
	# boulder pauldrons with moss caps, a cairn of stones on the back, gold rune eyes and a rune on the chest
	for side in [["upperarm.l", -1.0], ["upperarm.r", 1.0]]:
		var h: Node3D = at_bone.call(String(side[0]), Vector3(0.7 * float(side[1]), 3.0, 0))
		Models.part(h, Models.sphere(0.42, 8), rk, Vector3(0, 0.12, 0), Vector3(1.2, 0.85, 1.1))
		Models.part(h, Models.sphere(0.3, 8), mk, Vector3(0, 0.36, 0), Vector3(1.2, 0.4, 1.0))
	var chest: Node3D = at_bone.call("chest", Vector3(0, 2.6, 0))
	for i in 3:
		Models.part(chest, Models.sphere(0.34 - i * 0.07, 7), rk, Vector3(0.05 * (i - 1), 0.25 + i * 0.26, 0.42 - i * 0.04), Vector3(1.2, 0.8, 1.0))
	Models.part(chest, Models.box(0.26, 0.26, 0.04), gold, Vector3(0, 0.15, -0.36), Vector3.ONE, Vector3(0, 0, PI / 4))
	var head: Node3D = at_bone.call("head", Vector3(0, 3.6, -0.2))
	for sx in [-1.0, 1.0]:
		Models.part(head, Models.sphere(0.07, 6), gold, Vector3(0.11 * sx, 0.2, -0.26))
	Models.part(head, Models.sphere(0.3, 8), mk, Vector3(0, 0.5, 0.02), Vector3(1.1, 0.35, 1.0))
	# a glow of runes round its feet so you can find it in a dark arena
	var ring := MeshInstance3D.new(); ring.mesh = Models.flat_quad(4.6)
	ring.material_override = Models.ring_mat(Color(1.0, 0.83, 0.42, 0.55), 0.05); ring.position.y = 0.05; ring.name = "Runes"
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(ring)
	root.set_meta("mats", _mats_of(root, extra))
	return root

static func _scale_of(n: Node3D) -> float:
	var s := 1.0
	var c: Node = n
	while c and c is Node3D:
		s *= (c as Node3D).scale.x
		c = c.get_parent()
	return s

# ------------------------------------------------------------------ Stormcoil, the Sky Serpent
## The head is the body ("Body"); the coils are separate nodes in meta "segs" (top level, placed along
## the path the head flew by Boss.render).
const SERPENT_SEGS := 16

static func serpent() -> Node3D:
	var root := Node3D.new()
	var c_body := Color("2f6f9a"); var c_belly := Color("d6f4ff"); var c_glow := Color("9ff4ff"); var c_dark := Color("1d3e5c")
	var m_body := Models.toon(c_body); var m_belly := Models.toon(c_belly); var m_dark := Models.toon(c_dark)
	var m_glow := Models.toon(c_glow, false, 1.3); var m_wing := Models.toon(Color("bfe8ff"), true, 0.15)
	var mats: Array = [m_body, m_belly, m_dark, m_glow, m_wing]
	var body := Node3D.new(); body.name = "Body"; root.add_child(body)
	var head := Node3D.new(); head.name = "Head"; head.position = Vector3(0, 1.3, 0); body.add_child(head)
	# a long horned skull, a pale jaw, glowing eyes and whiskers of static
	Models.part(head, Models.sphere(0.5, 12), m_body, Vector3(0, 0.05, -0.1), Vector3(0.95, 0.75, 1.5))
	Models.part(head, Models.sphere(0.36, 10), m_belly, Vector3(0, -0.18, -0.38), Vector3(0.9, 0.45, 1.25))
	var jaw := Node3D.new(); jaw.name = "Jaw"; jaw.position = Vector3(0, -0.2, -0.2); head.add_child(jaw)
	Models.part(jaw, Models.sphere(0.3, 8), m_belly, Vector3(0, -0.06, -0.38), Vector3(0.85, 0.32, 1.3))
	for sx in [-1.0, 1.0]:
		Models.part(head, Models.sphere(0.085, 8), m_glow, Vector3(0.3 * sx, 0.18, -0.42))
		Models.part(head, Models.cyl(0.0, 0.09, 0.75, 6), m_dark, Vector3(0.22 * sx, 0.45, 0.22), Vector3.ONE, Vector3(-0.9, 0, -0.25 * sx))
		Models.part(head, Models.cyl(0.0, 0.05, 0.42, 5), m_glow, Vector3(0.36 * sx, -0.18, -0.72), Vector3.ONE, Vector3(-1.3, 0, 0.5 * sx))
		# swept swift's wings just behind the head
		var wing := Node3D.new(); wing.name = "Wing" + ("L" if sx < 0 else "R"); wing.position = Vector3(0.38 * sx, 0.0, 0.45); head.add_child(wing)
		for f in 4:
			Models.part(wing, Models.box(1.3 - f * 0.2, 0.05, 0.28), m_wing, Vector3((0.6 - f * 0.08) * sx, 0.02 * f, 0.18 * f), Vector3.ONE, Vector3(0, -0.35 * sx * (1.0 + f * 0.25), 0.15 * sx))
		Models.part(wing, Models.box(1.2, 0.06, 0.08), m_dark, Vector3(0.6 * sx, 0.04, -0.12), Vector3.ONE, Vector3(0, -0.3 * sx, 0.15 * sx))
	# a crest of crackling fins along the top of the skull
	var pm := PrismMesh.new(); pm.size = Vector3(0.06, 0.38, 0.32)
	for i in 3:
		Models.part(head, pm, m_glow, Vector3(0, 0.42 - i * 0.04, 0.1 + i * 0.22), Vector3(1, 1.0 - i * 0.2, 1))
	var segs: Array = []
	for i in SERPENT_SEGS:
		var k := float(i) / SERPENT_SEGS
		var s := Node3D.new(); s.name = "Seg%d" % i; s.top_level = true
		root.add_child(s)
		var rr := lerpf(0.5, 0.16, k)
		Models.part(s, Models.sphere(rr, 10), m_body, Vector3.ZERO, Vector3(1.0, 0.92, 1.25))
		Models.part(s, Models.sphere(rr * 0.82, 8), m_belly, Vector3(0, -rr * 0.32, 0), Vector3(1.05, 0.6, 1.2))
		if i % 2 == 0:
			Models.part(s, pm, m_glow if i % 4 == 0 else m_dark, Vector3(0, rr * 0.95, 0), Vector3(1.0, 1.0 - k * 0.6, 1.0 - k * 0.4))
		if i % 3 == 1:
			Models.part(s, Models.cyl(rr * 1.02, rr * 1.02, 0.05, 12), m_glow, Vector3.ZERO, Vector3(1, 1, 1.2), Vector3(PI / 2, 0, 0))
		if i == SERPENT_SEGS - 1:
			for sx in [-1.0, 1.0]:
				Models.part(s, Models.box(0.7, 0.04, 0.32), m_wing, Vector3(0.3 * sx, 0, 0.25), Vector3.ONE, Vector3(0, 0.6 * sx, 0))
		segs.append(s)
	root.set_meta("segs", segs)
	root.set_meta("mats", mats)
	return root

# ------------------------------------------------------------------ the Brood Mother
static func brood() -> Node3D:
	var root := Node3D.new()
	var c_shell := Color("3f4a22"); var c_sac := Color("e0b040"); var c_glow := Color("ffe680")
	var m_shell := Models.toon(c_shell); var m_dark := Models.toon(c_shell.darkened(0.45)); var m_sac := Models.toon(c_sac, true, 0.25)
	var m_glow := Models.toon(c_glow, false, 1.2); var m_eye := Models.toon(Color("ff6a3a"), false, 1.4); var m_bone := Models.toon(Color("e8dcc0"))
	var mats: Array = [m_shell, m_dark, m_sac, m_glow, m_eye, m_bone]
	var body := Node3D.new(); body.name = "Body"; root.add_child(body)
	# the thorax, low and armoured, with a ridge of thorns
	Models.part(body, Models.sphere(0.9, 14), m_shell, Vector3(0, 0.95, -0.2), Vector3(1.2, 0.72, 1.15))
	Models.part(body, Models.sphere(0.7, 12), m_dark, Vector3(0, 0.82, -0.25), Vector3(1.25, 0.6, 1.1))
	for i in 5:
		Models.part(body, Models.cyl(0.0, 0.12, 0.5, 6), m_bone, Vector3(0, 1.48 - absf(i - 2) * 0.08, -0.7 + i * 0.32), Vector3.ONE, Vector3(-0.25, 0, 0))
	# the head: mandibles, a cluster of burning eyes and a crown of thorns
	var hd := Node3D.new(); hd.name = "Head"; hd.position = Vector3(0, 1.0, -1.2); body.add_child(hd)
	Models.part(hd, Models.sphere(0.5, 12), m_shell, Vector3.ZERO, Vector3(1.1, 0.8, 1.0))
	for e in [[-0.2, 0.18], [0.2, 0.18], [-0.1, 0.3], [0.1, 0.3], [-0.32, 0.05], [0.32, 0.05]]:
		Models.part(hd, Models.sphere(0.075, 8), m_eye, Vector3(float(e[0]), float(e[1]), -0.4))
	for sx in [-1.0, 1.0]:
		var mj := Node3D.new(); mj.name = "Jaw" + ("L" if sx < 0 else "R"); mj.position = Vector3(0.2 * sx, -0.18, -0.38); hd.add_child(mj)
		Models.part(mj, Models.cyl(0.0, 0.08, 0.55, 6), m_bone, Vector3(0.05 * sx, -0.05, -0.22), Vector3.ONE, Vector3(-PI / 2 + 0.3, 0, -0.45 * sx))
	for i in 5:
		var a := -0.9 + i * 0.45
		Models.part(hd, Models.cyl(0.0, 0.06, 0.4, 5), m_glow, Vector3(sin(a) * 0.32, 0.48, cos(a) * 0.1), Vector3.ONE, Vector3(-0.2, 0, -a * 0.5))
	# the egg sac: huge, amber and glowing from inside, eggs pressing at its skin
	var sac := Node3D.new(); sac.name = "Sac"; sac.position = Vector3(0, 1.25, 1.25); body.add_child(sac)
	Models.part(sac, Models.sphere(1.05, 16), m_sac, Vector3.ZERO, Vector3(1.0, 0.92, 1.25))
	var rng := RandomNumberGenerator.new(); rng.seed = 77
	for i in 16:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.4, 1), rng.randf_range(-0.2, 1)).normalized()
		Models.part(sac, Models.sphere(rng.randf_range(0.13, 0.22), 8), m_glow, Vector3(d.x * 1.0, d.y * 0.9, d.z * 1.22) * 0.93, Vector3(1, 1.2, 1))
	for i in 4:
		var a := TAU * i / 4.0
		Models.part(sac, Models.box(0.08, 0.06, 2.4), m_dark, Vector3(cos(a) * 0.55, 0.62, sin(a) * 0.1), Vector3.ONE, Vector3(0.3, a, 0))
	# six long jointed legs on hip pivots (LegNS: N 0..2 front to back, S -1/1)
	var legs := Node3D.new(); legs.name = "Legs"; body.add_child(legs)
	for i in 3:
		for sx in [-1, 1]:
			var lg := Node3D.new(); lg.name = "Leg%d%d" % [i, sx]
			lg.position = Vector3(0.75 * sx, 1.0, -0.65 + i * 0.5); legs.add_child(lg)
			var knee := Vector3(1.0 * sx, 0.65, -0.2 + i * 0.2)
			var foot := Vector3(1.55 * sx, -1.0, -0.35 + i * 0.35)
			KinModels.seg(lg, Vector3.ZERO, knee, 0.12, 0.1, m_shell)
			KinModels.seg(lg, knee, foot, 0.1, 0.03, m_dark)
			Models.part(lg, Models.sphere(0.13, 8), m_bone, knee)
	root.set_meta("mats", mats)
	return root

# ------------------------------------------------------------------ ward stones
static func ward() -> Node3D:
	var root := Node3D.new()
	var body := Node3D.new(); body.name = "Body"; root.add_child(body)
	var glow := Color("8fd8ff")
	var m_stone := Models.toon(Color("7d8396")); var m_glow := Models.toon(glow, false, 1.2)
	var mats: Array = [m_stone, m_glow]
	var pl := Assets.prop("dungeon/pillar_decorated", 1.6, true, {"bright": 1.2, "cache": false}) if Assets.on() else null
	if pl:
		body.add_child(pl)
		mats.append_array(pl.get_meta("mats"))
	else:
		Models.part(body, Models.cyl(0.32, 0.45, 1.6, 6), m_stone, Vector3(0, 0.8, 0))
	for i in 4:
		Models.part(body, Models.box(0.05, 0.42, 0.02), m_glow, Vector3(cos(TAU * i / 4.0) * 0.4, 0.8, sin(TAU * i / 4.0) * 0.4), Vector3.ONE, Vector3(0, -TAU * i / 4.0, 0))
	var cr := Node3D.new(); cr.name = "Crystal"; cr.position = Vector3(0, 2.15, 0); body.add_child(cr)
	var pm := PrismMesh.new(); pm.size = Vector3(0.4, 0.5, 0.4)
	Models.part(cr, pm, m_glow, Vector3(0, 0.25, 0))
	Models.part(cr, pm, m_glow, Vector3(0, -0.25, 0), Vector3.ONE, Vector3(PI, 0, 0))
	PropAnim.on(cr, 1.4, 0.1)
	var beam := Models.part(body, Models.cyl(0.05, 0.05, 6.0, 6), Models.glow_mat(Color(glow, 0.35)), Vector3(0, 5.0, 0))
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.set_meta("mats", mats)
	return root

# ------------------------------------------------------------------ the lair's pieces
## A portcullis of dark iron bars with a glowing rune band, filling a gap `width` tiles wide.
## Faces +z (turn it to the gate's side). "Bars" is what sinks when it opens.
static func gate(width: float, col: Color) -> Node3D:
	var root := Node3D.new()
	var iron := Models.toon(Color("3a3640")); var trim := Models.toon(Color("6a6270")); var rune := Models.toon(col, false, 1.2)
	var bars := Node3D.new(); bars.name = "Bars"; root.add_child(bars)
	var n := int(width * 3.0)
	for i in n + 1:
		var x := -width * 0.5 + width * i / float(n)
		Models.part(bars, Models.cyl(0.06, 0.06, 3.0, 6), iron, Vector3(x, 1.5, 0))
		Models.part(bars, Models.cyl(0.0, 0.08, 0.25, 6), trim, Vector3(x, -0.1, 0), Vector3.ONE, Vector3(PI, 0, 0))
	for y in [0.6, 1.6, 2.6]:
		Models.part(bars, Models.box(width, 0.12, 0.12), iron, Vector3(0, y, 0))
	Models.part(bars, Models.box(width * 0.95, 0.1, 0.14), rune, Vector3(0, 1.1, 0))
	Models.part(bars, Models.box(0.5, 0.5, 0.16), rune, Vector3(0, 1.6, 0), Vector3.ONE, Vector3(0, 0, PI / 4))
	# the posts either side and a lintel over the top, carved stone
	var stone := Models.toon(Color("8a8494"))
	var posts := Node3D.new(); posts.name = "Posts"; root.add_child(posts)
	for sx in [-1.0, 1.0]:
		var pl := Assets.prop("dungeon/pillar", 3.4, true, {"bright": 1.3}) if Assets.on() else null
		if pl:
			pl.position = Vector3(sx * (width * 0.5 + 0.45), 0, 0)
			posts.add_child(pl)
		else:
			Models.part(posts, Models.box(0.8, 3.4, 0.8), stone, Vector3(sx * (width * 0.5 + 0.45), 1.7, 0))
		var tl := Assets.prop("dungeon/torch_lit", 0.6, true) if Assets.on() else null
		if tl:
			tl.position = Vector3(sx * (width * 0.5 + 0.45), 2.2, 0.45)
			posts.add_child(tl)
		Models.part(posts, Models.sphere(0.13, 8), Models.toon(Color("ffb050"), false, 1.4), Vector3(sx * (width * 0.5 + 0.45), 2.75, 0.5))
	Models.part(posts, Models.box(width + 1.9, 0.5, 0.9), stone, Vector3(0, 3.45, 0))
	Models.part(posts, Models.box(0.6, 0.35, 0.05), rune, Vector3(0, 3.45, 0.46))
	return root

## The seal over a closed lair: a faint dome of light with a glowing rim on the ground.
static func dome(half: float, col: Color) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new(); sm.radius = 1.0; sm.height = 2.0; sm.is_hemisphere = true; sm.radial_segments = 40; sm.rings = 14
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(col, 0.10)
	mat.rim_enabled = false
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3(half * 1.42, half * 0.62, half * 1.42)
	mi.name = "Shell"
	root.add_child(mi)
	var rim := MeshInstance3D.new(); rim.mesh = Models.flat_quad(half * 2.9)
	rim.material_override = Models.ring_mat(Color(col, 0.7), 0.025); rim.position.y = 0.06; rim.name = "Rim"
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(rim)
	return root

## The gate's lock: a stone lectern with a carved ring dial on its face, a needle and lit target arcs
## (Lairs turns "Needle"; the HUD draws the readable version).
static func dial_stone(col: Color) -> Node3D:
	var root := Node3D.new()
	var stone := Models.toon(Color("a29c90")); var dark := Models.toon(Color("4a4652")); var rune := Models.toon(col, false, 1.1)
	Models.part(root, Models.cyl(0.62, 0.72, 0.22, 8), stone, Vector3(0, 0.11, 0))
	Models.part(root, Models.cyl(0.32, 0.42, 0.9, 8), stone, Vector3(0, 0.65, 0))
	var face := Node3D.new(); face.name = "Face"; face.position = Vector3(0, 1.25, 0); face.rotation.x = -0.9; root.add_child(face)
	Models.part(face, Models.cyl(0.62, 0.62, 0.12, 28), dark, Vector3.ZERO)
	var tm := TorusMesh.new(); tm.inner_radius = 0.48; tm.outer_radius = 0.6; tm.rings = 28
	Models.part(face, tm, rune, Vector3(0, 0.07, 0), Vector3(1, 0.5, 1))
	var needle := Node3D.new(); needle.name = "Needle"; needle.position = Vector3(0, 0.1, 0); face.add_child(needle)
	Models.part(needle, Models.box(0.06, 0.04, 0.55), Models.toon(Color("fff4d0"), false, 1.4), Vector3(0, 0, -0.27))
	Models.part(face, Models.sphere(0.08, 8), rune, Vector3(0, 0.1, 0))
	var glow := MeshInstance3D.new(); glow.mesh = Models.flat_quad(2.2)
	glow.material_override = Models.ring_mat(Color(col, 0.8), 0.07); glow.position.y = 0.04; glow.name = "Ring"
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(glow)
	return root

## A rune pylon: a squat standing stone with a rune that lights up when someone holds interact at it.
static func rune_pylon(col: Color) -> Node3D:
	var root := Node3D.new()
	var stone := Models.toon(Color("8d8a9a")); var dim := Models.toon(Color("4a4f60"), false, 0.2)
	Models.part(root, Models.cyl(0.55, 0.65, 0.2, 6), stone, Vector3(0, 0.1, 0))
	Models.part(root, Models.box(0.6, 1.9, 0.45), stone, Vector3(0, 1.1, 0), Vector3.ONE, Vector3(0, 0.3, 0.04))
	var rn := Models.part(root, Models.box(0.26, 0.6, 0.06), dim, Vector3(0, 1.25, -0.24), Vector3.ONE, Vector3(0, 0.3, 0.04))
	rn.name = "Rune"
	var lit := Node3D.new(); lit.name = "Lit"; lit.visible = false; root.add_child(lit)
	var beam := Models.part(lit, Models.cyl(0.12, 0.25, 9.0, 8), Models.glow_mat(Color(col, 0.4)), Vector3(0, 6.5, 0))
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Models.part(lit, Models.box(0.28, 0.62, 0.07), Models.toon(col, false, 1.4), Vector3(0, 1.25, -0.25), Vector3.ONE, Vector3(0, 0.3, 0.04))
	var ring := MeshInstance3D.new(); ring.mesh = Models.flat_quad(2.0)
	ring.material_override = Models.ring_mat(Color(col, 0.75), 0.08); ring.position.y = 0.05; ring.name = "Ring"
	root.add_child(ring)
	return root

## The Rare Egg on the ground: big, gold and glowing, with a light shaft you can see across the map.
static func rare_egg(col: Color) -> Node3D:
	var root := Node3D.new()
	var spin := Node3D.new(); spin.name = "Spin"; spin.position = Vector3(0, 0.15, 0); root.add_child(spin)
	var shell := Models.toon(Color("ffe08a"), true, 0.55)
	shell.set_shader_parameter("rim_color", Color("fff6c0"))
	shell.set_shader_parameter("rim_amount", 2.0)
	Models.part(spin, Models.sphere(0.4, 18), shell, Vector3(0, 0.3, 0), Vector3(0.85, 1.18, 0.85))
	var rng := RandomNumberGenerator.new(); rng.seed = int(col.r * 997 + col.b * 31)
	var spot := Models.toon(col, false, 1.3)
	for i in 9:
		var a := rng.randf() * TAU; var y := rng.randf_range(0.3, 0.85)
		var rr := sqrt(maxf(0.0, 1.0 - pow((y - 0.55) / 0.47, 2.0))) * 0.34
		y -= 0.25
		Models.part(spin, Models.sphere(rng.randf_range(0.04, 0.07), 8), spot, Vector3(cos(a) * rr, y, sin(a) * rr), Vector3(1, 1, 0.5))
	PropAnim.on(spin, 0.6, 0.1)
	var nest := Models.toon(Color("6a5638"))
	Models.part(root, Models.cyl(0.5, 0.42, 0.18, 14), nest, Vector3(0, 0.09, 0))
	var beam := Models.part(root, Models.cyl(0.18, 0.4, 14.0, 12), Models.glow_mat(Color(1.0, 0.85, 0.35, 0.32)), Vector3(0, 7.0, 0))
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ring := MeshInstance3D.new(); ring.mesh = Models.flat_quad(2.2)
	ring.material_override = Models.ring_mat(Color("ffd36a"), 0.1); ring.position.y = 0.05
	root.add_child(ring)
	var p := CPUParticles3D.new()
	p.amount = 22; p.lifetime = 1.4
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE; p.emission_sphere_radius = 0.55
	p.direction = Vector3.UP; p.spread = 30.0; p.initial_velocity_min = 0.5; p.initial_velocity_max = 1.4
	p.gravity = Vector3.ZERO; p.scale_amount_min = 0.05; p.scale_amount_max = 0.1
	p.mesh = Models.sphere(0.5, 4)
	p.material_override = Models.glow_mat(Color(1.0, 0.9, 0.5, 0.9))
	p.position = Vector3(0, 0.6, 0)
	root.add_child(p)
	return root
