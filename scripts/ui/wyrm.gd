class_name Wyrm
extends Node3D
## The Wyrm: the great dragon whose waking broke the world (the prologue's villain). A long
## serpentine body that follows its head through the air, two huge slow-beating wings, horns,
## ember-glowing eyes and spine, and a fire breath you can switch on.
##
## Move the Wyrm node itself (position along a path); the body trails behind on its own.

const SEGS := 18
const SPACING := 1.35
var spacing := SPACING
var size := 1.0

var segs: Array[Node3D] = []
var trail: Array[Vector3] = []      # where the head has been, newest first
var head: Node3D
var jaw: Node3D
var wing_l: Node3D
var wing_r: Node3D
var breath: CPUParticles3D
var t := 0.0
var flap_rate := 1.0
var roar_k := 0.0

func _init() -> void:
	var hide := Models.toon(Color("2b1d33"))
	var belly := Models.toon(Color("6b3a3c"))
	var horn := Models.toon(Color("d8ccb6"))
	var ember := Models.glow_mat(Color("ff8a2a"))
	var memb := StandardMaterial3D.new()
	memb.albedo_color = Color("4a2238")
	memb.cull_mode = BaseMaterial3D.CULL_DISABLED
	memb.roughness = 0.9
	memb.rim_enabled = true
	memb.rim = 0.4
	# head
	head = Node3D.new(); head.name = "Head"
	add_child(head)
	Models.part(head, Models.box(1.5, 1.1, 2.4), hide, Vector3(0, 0, -0.6))
	Models.part(head, Models.box(1.1, 0.7, 1.4), hide, Vector3(0, -0.1, -2.2))          # snout
	jaw = Node3D.new(); jaw.position = Vector3(0, -0.45, -0.6); head.add_child(jaw)
	Models.part(jaw, Models.box(1.0, 0.3, 2.4), belly, Vector3(0, -0.1, -1.1))
	for sx in [-1.0, 1.0]:
		Models.part(head, Models.cyl(0.0, 0.22, 1.8, 6), horn, Vector3(sx * 0.55, 0.75, 0.4), Vector3.ONE, Vector3(-0.9, 0, sx * -0.35))
		Models.part(head, Models.cyl(0.0, 0.14, 1.0, 6), horn, Vector3(sx * 0.75, 0.2, 0.6), Vector3.ONE, Vector3(-1.2, 0, sx * -0.9))
		Models.part(head, Models.sphere(0.17, 8), ember, Vector3(sx * 0.62, 0.22, -1.25))
		for k in 3:
			Models.part(jaw, Models.cyl(0.0, 0.07, 0.3, 4), horn, Vector3(sx * 0.38, 0.18, -0.6 - k * 0.55), Vector3.ONE, Vector3(PI, 0, 0))
	# fire breath from the mouth
	breath = CPUParticles3D.new()
	breath.emitting = false
	breath.amount = 160
	breath.lifetime = 0.9
	breath.local_coords = false
	breath.direction = Vector3(0, -0.45, -1)
	breath.spread = 11.0
	breath.initial_velocity_min = 26.0
	breath.initial_velocity_max = 34.0
	breath.gravity = Vector3(0, 2.0, 0)
	breath.damping_min = 6.0; breath.damping_max = 10.0
	breath.scale_amount_min = 1.0; breath.scale_amount_max = 2.4
	var sc := Curve.new(); sc.add_point(Vector2(0, 0.3)); sc.add_point(Vector2(0.5, 1.0)); sc.add_point(Vector2(1, 1.4))
	breath.scale_amount_curve = sc
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.92, 0.45, 1.0)); grad.set_color(1, Color(0.25, 0.08, 0.06, 0.0))
	grad.add_point(0.3, Color(1.0, 0.45, 0.08, 1.0))
	grad.add_point(0.7, Color(0.75, 0.15, 0.04, 0.8))
	breath.color_ramp = grad
	var bm := SphereMesh.new(); bm.radius = 0.45; bm.height = 0.9; bm.radial_segments = 8; bm.rings = 4
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.vertex_color_use_as_albedo = true
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.material = fmat
	breath.mesh = bm
	breath.position = Vector3(0, -0.3, -2.9)
	head.add_child(breath)
	# body: a chain of tapering segments, each with a glowing ridge spike
	for i in SEGS:
		var s := Node3D.new()
		var k := float(i) / (SEGS - 1)
		var rad := lerpf(1.25, 0.22, pow(k, 0.8)) * (1.15 if i in [2, 3, 4] else 1.0)
		Models.part(s, Models.sphere(rad, 12), hide, Vector3.ZERO, Vector3(1.0, 0.9, 1.25))
		Models.part(s, Models.sphere(rad * 0.8, 10), belly, Vector3(0, -rad * 0.32, 0), Vector3(1.0, 0.7, 1.2))
		if i % 2 == 0:
			Models.part(s, Models.cyl(0.0, rad * 0.32, rad * 0.9, 5), horn if i > 3 else ember, Vector3(0, rad * 0.95, 0), Vector3.ONE, Vector3(-0.5, 0, 0))
		add_child(s)
		s.top_level = true
		segs.append(s)
	# tail blade
	Models.part(segs[SEGS - 1], Models.box(0.1, 0.9, 1.4), horn, Vector3(0, 0, 0.7))
	# wings on the shoulders: an arm of bones with a ragged membrane between the fingers
	for side in [-1.0, 1.0]:
		var w := Node3D.new()
		w.position = Vector3(side * 1.0, 0.6, 0)
		segs[2].add_child(w)
		var pts := [Vector3(0, 0, 0.6), Vector3(side * 5.5, 1.2, -0.8), Vector3(side * 12.0, 0.4, -0.2),
			Vector3(side * 10.0, 0, 3.2), Vector3(side * 7.0, 0, 2.4), Vector3(side * 5.0, 0, 4.6), Vector3(side * 2.2, 0, 3.4)]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for j in range(1, pts.size() - 1):
			st.add_vertex(pts[0]); st.add_vertex(pts[j]); st.add_vertex(pts[j + 1])
		st.generate_normals()
		var mi := MeshInstance3D.new(); mi.mesh = st.commit(); mi.material_override = memb
		w.add_child(mi)
		for f in [2, 3, 4, 5]:
			var a: Vector3 = pts[1]; var b: Vector3 = pts[f]
			var bone := Models.part(w, Models.cyl(0.07, 0.14, a.distance_to(b), 5), horn, (a + b) * 0.5)
			_along(bone, a, b)
		var arm := Models.part(w, Models.cyl(0.12, 0.28, pts[1].length(), 6), hide, pts[1] * 0.5)
		_along(arm, Vector3.ZERO, pts[1])
		if side < 0: wing_l = w
		else: wing_r = w
	for mi in find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

## Points a cylinder (built along Y) from a to b.
static func _along(n: Node3D, a: Vector3, b: Vector3) -> void:
	var d := (b - a).normalized()
	var up := Vector3.UP if absf(d.y) < 0.95 else Vector3.FORWARD
	n.basis = Basis.looking_at(d, up) * Basis(Vector3.RIGHT, -PI / 2)

## Jump somewhere new without the body stretching across the sky to get there.
func teleport(p: Vector3, facing := Vector3.FORWARD) -> void:
	global_position = p
	trail.clear()
	for i in SEGS * 6:
		trail.append(p - facing.normalized() * i * spacing / 6.0)

## Grows the whole beast (head, body and wings) by k.
func set_size(k: float) -> void:
	size = k
	head.scale = Vector3.ONE * k
	for sg in segs:
		sg.scale = Vector3.ONE * k
	spacing = SPACING * k
	breath.scale_amount_min = 0.8 * k; breath.scale_amount_max = 1.5 * k
	breath.initial_velocity_min = 26.0 * k; breath.initial_velocity_max = 34.0 * k

func roar() -> void:
	roar_k = 1.0

func _process(delta: float) -> void:
	t += delta
	var p := global_position
	if trail.is_empty():
		teleport(p)
	# face where we're going
	var prev: Vector3 = trail[0]
	var mv := p - prev
	if mv.length() > 0.001:
		var fwd := mv.normalized()
		head.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP).scaled_local(Vector3.ONE * size), p)
	if mv.length() > 0.05:
		trail.push_front(p)
		if trail.size() > SEGS * 10:
			trail.resize(SEGS * 10)
	# lay the body along the trail by distance
	var want := spacing
	var acc := 0.0
	var j := 0
	var last := p
	for i in SEGS:
		var target := want * (i + 1)
		while j < trail.size() - 1 and acc + last.distance_to(trail[j + 1]) < target:
			acc += last.distance_to(trail[j + 1])
			last = trail[j + 1]
			j += 1
		var nxt: Vector3 = trail[mini(j + 1, trail.size() - 1)]
		var rem := target - acc
		var sp := last.move_toward(nxt, rem)
		var s := segs[i]
		var ahead: Vector3 = p if i == 0 else segs[i - 1].global_position
		s.global_position = sp + Vector3(0, sin(t * 2.0 - i * 0.5) * 0.15, 0)
		if (ahead - sp).length() > 0.01:
			s.global_transform.basis = Basis.looking_at((ahead - sp).normalized(), Vector3.UP).scaled_local(Vector3.ONE * size)
	# heavy, slow wingbeats
	var ph := sin(t * TAU * 0.55 * flap_rate)
	if wing_l: wing_l.rotation = Vector3(0, 0, -ph * 0.6 + 0.1)
	if wing_r: wing_r.rotation = Vector3(0, 0, ph * 0.6 - 0.1)
	# jaw opens to roar or breathe
	roar_k = maxf(0.0, roar_k - delta * 0.6)
	var open := maxf(sin(roar_k * PI), 1.0 if breath.emitting else 0.0)
	jaw.rotation.x = lerpf(jaw.rotation.x, open * 0.55, minf(1.0, delta * 8.0))
