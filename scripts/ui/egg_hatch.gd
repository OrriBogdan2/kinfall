class_name EggHatch
extends Node3D
## An egg that hatches in stages: a couple of curious wiggles, a first crack with a little hop,
## a bigger crack, a chip pops out and two eyes peek through and blink, the cracks glow and run
## all the way round, then the top pops off and the kin springs up out of the bottom half,
## sits there a moment, and hops out. Used for the first egg and for eggs from the nest.

signal popped(kin: Node3D)     # the kin has just appeared
signal done                    # the kin has hopped out and the shell is gone

const STEP := TAU / 36.0       # spacing of the zigzag crack around the middle

var species := "cindle"
var rec: Dictionary = {}
var fx: Fx
var r := 0.32                  # shell radius before the egg's stretch
var cy := 0.42                 # height of the egg's middle
var kin_scale := 1.0
var hop_out := 0.8             # how far the kin hops forward out of its shell
var rx := 0.0
var ry := 0.0

var body: Node3D               # pivots at the bottom, so wiggles rock the egg like a toy
var cap: Node3D
var cup: Node3D
var cracks: Node3D
var peek: Node3D
var eyes: Node3D
var shell_mat: ShaderMaterial
var crack_mat: ShaderMaterial
var col := Color.WHITE
var kin_node: Node3D
var running := false
var shell_col := Color(0, 0, 0, 0)     # set to override the species colours
var spot_col := Color(0, 0, 0, 0)

func _init(sp_id: String, fx_ref: Fx, radius := 0.32, middle := 0.42, kin_size := 1.0, kin_rec := {}) -> void:
	species = sp_id; fx = fx_ref; r = radius; cy = middle; kin_scale = kin_size; rec = kin_rec

func _ready() -> void:
	var sp: Dictionary = Data.KIN[species]
	col = Color(sp["color"]).lightened(0.15) if shell_col.a <= 0.0 else shell_col
	var spot: Color = sp["belly"] if spot_col.a <= 0.0 else spot_col
	rx = r * 0.92
	ry = r * 1.25
	shell_mat = Models.toon(col)
	crack_mat = Models.toon(Color(0.16, 0.1, 0.08), false)
	body = Node3D.new(); body.name = "Body"; add_child(body)
	cup = _half(false)
	cap = _half(true)
	cracks = Node3D.new(); body.add_child(cracks)
	var spot_mat := Models.toon(spot)
	var rng := RandomNumberGenerator.new(); rng.seed = int(col.r * 1000) + species.length()
	for i in 7:
		var a := rng.randf() * TAU
		var lat := rng.randf_range(-0.9, 1.0)
		if absf(lat) < 0.22: lat = 0.35 * signf(lat + 0.001)
		if lat > 0.15 and absf(wrapf(a - PI * 0.5, -PI, PI)) < 0.8:
			a += PI * 0.6          # keep the front clear for the peek hole
		var s := Models.part(cap if lat > 0.0 else cup, Models.sphere(r * 0.19, 8), spot_mat, _surf(a, lat, 1.0) - Vector3(0, cy, 0), Vector3(1, 1, 0.6))
		s.basis = Basis.looking_at(_normal(a, lat), Vector3.UP) * Basis.from_scale(Vector3(1, 1, 0.6))

## One half of the shell: a dome, with a jagged rim that only shows once it has split.
func _half(top: bool) -> Node3D:
	var n := Node3D.new(); n.name = "Cap" if top else "Cup"
	n.position = Vector3(0, cy, 0)        # each half turns about the egg's middle
	body.add_child(n)
	var hm := SphereMesh.new(); hm.radius = r; hm.height = r; hm.is_hemisphere = true
	hm.radial_segments = 20; hm.rings = 8
	var dome := Models.part(n, hm, shell_mat, Vector3.ZERO, Vector3(0.92, 1.25, 0.92))
	if not top:
		dome.rotation.x = PI
		var inside := Models.part(n, Models.cyl(rx * 0.96, rx * 0.96, 0.01, 20), Models.toon(col.darkened(0.45), false), Vector3(0, -0.006, 0))
		inside.name = "Inside"
		inside.visible = false
	var teeth := Node3D.new(); teeth.name = "Teeth"; teeth.visible = false; n.add_child(teeth)
	for k in 36:
		if (k % 2 == 0) == top:
			continue
		var a := PI * 0.5 + k * STEP
		var t := MeshInstance3D.new()
		t.mesh = Models.box(r * 0.26, r * 0.26, 0.012)
		t.material_override = shell_mat
		t.basis = Basis.looking_at(_normal(a, 0.0), Vector3.UP) * Basis(Vector3(0, 0, 1), PI * 0.25)
		t.position = _surf(a, 0.0, 0.995) - Vector3(0, cy, 0)
		teeth.add_child(t)
	return n

func _surf(a: float, lat: float, out := 1.03) -> Vector3:
	return Vector3(rx * cos(lat) * cos(a) * out, cy + ry * sin(lat) * out, rx * cos(lat) * sin(a) * out)

func _normal(a: float, lat: float) -> Vector3:
	return Vector3(cos(lat) * cos(a) / rx, sin(lat) / ry, cos(lat) * sin(a) / rx).normalized()

func _zig(k: int) -> Vector3:
	return _surf(PI * 0.5 + k * STEP, 0.14 * (1.0 if k % 2 == 0 else -1.0))

## A run of the zigzag crack from point k0 to k1 (inclusive), drawn on the shell.
func _crack(k0: int, k1: int) -> void:
	for k in range(k0, k1):
		_seg(_zig(k), _zig(k + 1))

func _seg(p0: Vector3, p1: Vector3) -> void:
	var d := p1 - p0
	if d.length() < 0.001:
		return
	var m := MeshInstance3D.new()
	m.mesh = Models.box(r * 0.07, r * 0.07, d.length() + r * 0.05)
	m.material_override = crack_mat
	var mid := (p0 + p1) * 0.5
	m.basis = Basis.looking_at(d.normalized(), (mid - Vector3(0, cy, 0)).normalized())
	m.position = mid
	m.scale = Vector3.ZERO
	cracks.add_child(m)
	create_tween().tween_property(m, "scale", Vector3.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## A gentle glow while it's kept warm (0..1).
func set_warmth(w: float) -> void:
	shell_mat.set_shader_parameter("glow", w * 0.3)

func _gp(local: Vector3) -> Vector3:
	return global_transform * local

func _sfx(n: String, vol := 0.0, pitch := 1.0) -> void:
	Sfx.play(n, null, vol, 0.08, pitch)

# ------------------------------------------------------------------ the hatch
func start() -> void:
	if running:
		return
	running = true
	var tw := create_tween()
	# 1: two curious wiggles
	for dir in [1.0, -1.0]:
		tw.tween_callback(_sfx.bind("hover", -8.0, 0.8 + 0.2 * dir))
		tw.tween_property(body, "rotation:z", 0.2 * dir, 0.24).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(body, "rotation:z", 0.0, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.3)
	# 2: a hop, and the first crack
	_hop(tw, 0.1)
	tw.tween_callback(func():
		_crack(-2, 2)
		_chips(_zig(0), 5)
		_sfx("build", -4.0, 1.9))
	tw.tween_interval(0.6)
	_shiver(tw, 4, 0.05, 0.05)
	tw.tween_interval(0.45)
	# 3: a bigger wiggle and the crack spreads
	for dir in [-1.0, 1.0]:
		tw.tween_property(body, "rotation:z", 0.26 * dir, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(body, "rotation:z", 0.0, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		_crack(-6, -2); _crack(2, 6)
		_seg(_zig(1), _surf(PI * 0.5 + 1.4 * STEP, 0.36)); _seg(_surf(PI * 0.5 + 1.4 * STEP, 0.36), _surf(PI * 0.5 + 0.7 * STEP, 0.55))
		_chips(_zig(-4), 4); _chips(_zig(4), 4)
		_sfx("build", -2.0, 1.6))
	tw.tween_interval(0.7)
	# 4: a chip pops out and someone peeks through
	tw.tween_callback(_open_peek)
	tw.tween_interval(0.6)
	tw.tween_callback(_blink)
	tw.tween_interval(0.45)
	tw.tween_callback(func(): _look(-1.0))
	tw.tween_interval(0.45)
	tw.tween_callback(func(): _look(1.0))
	tw.tween_interval(0.4)
	tw.tween_callback(func(): _look(0.0); _blink())
	tw.tween_interval(0.5)
	tw.tween_callback(_close_peek)
	tw.tween_interval(0.35)
	# 5: the cracks glow and run all the way round
	tw.tween_callback(func():
		crack_mat.set_shader_parameter("albedo", Color("ffe08a"))
		crack_mat.set_shader_parameter("glow", 1.2)
		_crack(6, 30)
		_sfx("build", 0.0, 1.3))
	_shiver(tw, 6, 0.07, 0.055)
	tw.tween_property(body, "scale", Vector3(1.12, 0.84, 1.12), 0.16).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(_pop)

func _hop(tw: Tween, h: float) -> void:
	tw.tween_callback(_sfx.bind("jump", -10.0, 1.7))
	tw.tween_property(body, "scale", Vector3(1.1, 0.88, 1.1), 0.08)
	tw.tween_property(body, "position:y", h, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(body, "scale", Vector3(0.94, 1.08, 0.94), 0.14)
	tw.tween_property(body, "position:y", 0.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(body, "scale", Vector3(1.08, 0.92, 1.08), 0.06)
	tw.tween_property(body, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _shiver(tw: Tween, n: int, amp: float, step: float) -> void:
	for i in n:
		tw.tween_property(body, "rotation:z", amp * (1.0 if i % 2 == 0 else -1.0), step)
	tw.tween_property(body, "rotation:z", 0.0, step)

func _chips(local: Vector3, n: int) -> void:
	if fx:
		fx.burst(_gp(local), Color("f6f0e2"), n, 1.6, 0.4, 7.0, 0.55)

func _open_peek() -> void:
	var a := PI * 0.5
	var lat := 0.5
	var nrm := _normal(a, lat)
	peek = Node3D.new()
	peek.position = _surf(a, lat, 1.02) - Vector3(0, cy, 0)
	peek.basis = Basis.looking_at(-nrm, Vector3.UP)     # local +z points out of the shell
	cap.add_child(peek)
	var hole := Models.part(peek, Models.sphere(r * 0.3, 14), Models.toon(Color("2a1c2e"), false), Vector3(0, 0, 0.0), Vector3(1.3, 0.85, 0.3))
	hole.scale = Vector3.ZERO
	create_tween().tween_property(hole, "scale", Vector3(1.3, 0.85, 0.3), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	eyes = Node3D.new(); eyes.position = Vector3(0, -0.004, r * 0.1); peek.add_child(eyes)
	var em := Models.toon(Color("fffaf0"), false, 0.8)
	for sx in [-1.0, 1.0]:
		var e := Models.part(eyes, Models.sphere(r * 0.075, 10), em, Vector3(sx * r * 0.15, 0, 0), Vector3(0.85, 1.2, 0.6))
		e.name = "Eye"
	eyes.scale = Vector3.ZERO
	var tw := create_tween()
	tw.tween_interval(0.18)
	tw.tween_property(eyes, "scale", Vector3.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# the chip that came out tumbles away
	var chip := Models.part(get_parent(), Models.sphere(r * 0.2, 8), shell_mat, _gp(_surf(a, lat, 1.05)), Vector3(1, 0.8, 0.35))
	var land := _gp(_surf(a, lat, 1.05)) + Vector3(0.25, 0, 0.45)
	land.y = global_position.y + 0.03
	var ct := create_tween().set_parallel(true)
	ct.tween_property(chip, "position:x", land.x, 0.5)
	ct.tween_property(chip, "position:z", land.z, 0.5)
	ct.tween_property(chip, "rotation", Vector3(2.0, 1.0, 3.0), 0.5)
	var cyt := create_tween()
	cyt.tween_property(chip, "position:y", chip.position.y + 0.25, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	cyt.tween_property(chip, "position:y", land.y, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	cyt.tween_interval(2.2)
	cyt.tween_property(chip, "scale", Vector3.ZERO, 0.3)
	cyt.tween_callback(chip.queue_free)
	_chips(_surf(a, lat), 4)
	_sfx("build", -2.0, 2.2)
	_sfx("kin_unsure", -10.0, 1.35)

func _blink() -> void:
	if not is_instance_valid(eyes):
		return
	var tw := create_tween()
	tw.tween_property(eyes, "scale:y", 0.1, 0.06)
	tw.tween_property(eyes, "scale:y", 1.0, 0.09)

func _look(dx: float) -> void:
	if is_instance_valid(eyes):
		create_tween().tween_property(eyes, "position:x", dx * r * 0.06, 0.14).set_trans(Tween.TRANS_SINE)

func _close_peek() -> void:
	if is_instance_valid(eyes):
		var tw := create_tween()
		tw.tween_property(eyes, "scale", Vector3.ZERO, 0.12)
	_sfx("kin_alert", -12.0, 1.4)

func _pop() -> void:
	var sp: Dictionary = Data.KIN[species]
	var kc: Color = sp["color"]
	cracks.visible = false
	if is_instance_valid(peek): peek.visible = false
	for half in [cap, cup]:
		(half as Node3D).get_node("Teeth").visible = true
	cup.get_node("Inside").visible = true
	body.scale = Vector3.ONE
	var top := _gp(Vector3(0, cy, 0))
	if fx:
		fx.burst(top + Vector3(0, 0.1, 0), kc, 26, 3.6, 0.8, 4.0, 1.1)
		fx.burst(top + Vector3(0, 0.1, 0), Color("fff6c0"), 18, 2.6, 0.7, 2.0, 0.8)
		fx.burst(top, Color("f6f0e2"), 14, 2.8, 0.5, 9.0, 0.6)
		fx.ring(global_position, 1.6 * r / 0.32, Color(UI.GOLD, 0.9), 0.5)
	_sfx("unlock", 0.0, 1.1)
	get_tree().create_timer(0.2).timeout.connect(func(): _sfx("kin_happy", 0.0, 1.15))
	# the top flips off and lands beside the nest
	var ct := create_tween().set_parallel(true)
	var side := Vector3(-0.75, 0, 0.25) * (r / 0.32)
	ct.tween_property(cap, "position:x", side.x, 0.7)
	ct.tween_property(cap, "position:z", side.z, 0.7)
	ct.tween_property(cap, "rotation", Vector3(0.3, 0.4, PI), 0.7).set_trans(Tween.TRANS_SINE)
	var cyt := create_tween()
	cyt.tween_property(cap, "position:y", cy + 0.55 * (r / 0.32), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	cyt.tween_property(cap, "position:y", ry * 0.97, 0.4).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	cyt.tween_callback(_sfx.bind("land", -8.0, 1.4))
	# the kin springs up out of the bottom half
	kin_node = Models.kin(species, rec)
	get_parent().add_child(kin_node)
	kin_node.global_position = _gp(Vector3(0, cy - 0.2 * r / 0.32, 0))
	kin_node.rotation.y = PI
	kin_node.scale = Vector3.ONE * 0.05 * kin_scale
	var sit := _gp(Vector3(0, cy * 0.55, 0))
	var kt := create_tween()
	kt.tween_property(kin_node, "scale", Vector3(0.9, 1.25, 0.9) * kin_scale, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	kt.parallel().tween_property(kin_node, "global_position:y", sit.y + 0.45 * r / 0.32, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	kt.tween_property(kin_node, "global_position:y", sit.y, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	kt.parallel().tween_property(kin_node, "scale", Vector3(1.15, 0.85, 1.15) * kin_scale, 0.2)
	kt.tween_property(kin_node, "scale", Vector3.ONE * kin_scale, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	kt.tween_callback(func(): popped.emit(kin_node))
	# sits in its shell for a moment, then hops out to the front
	kt.tween_interval(0.9)
	var out := global_position + Vector3(0.0, 0.0, hop_out) * (r / 0.32) * 1.3
	kt.tween_callback(_sfx.bind("jump", -8.0, 1.5))
	kt.tween_property(kin_node, "scale", Vector3(1.12, 0.86, 1.12) * kin_scale, 0.08)
	kt.tween_property(kin_node, "global_position:z", out.z, 0.38)
	kt.parallel().tween_property(kin_node, "global_position:x", out.x, 0.38)
	kt.parallel().tween_property(kin_node, "scale", Vector3.ONE * kin_scale, 0.12)
	kt.parallel().tween_method(func(f: float): kin_node.global_position.y = lerpf(sit.y, out.y, f) + sin(f * PI) * 0.45 * r / 0.32, 0.0, 1.0, 0.38)
	kt.tween_property(kin_node, "scale", Vector3(1.15, 0.85, 1.15) * kin_scale, 0.07)
	kt.tween_property(kin_node, "scale", Vector3.ONE * kin_scale, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	kt.tween_callback(func():
		if fx: fx.burst(out + Vector3(0, 0.1, 0), Color("fff6c0"), 6, 1.2, 0.4, 3.0, 0.6)
		_sfx("land", -10.0, 1.6))
	# the empty shell shrinks away
	kt.tween_interval(0.5)
	kt.tween_property(body, "scale", Vector3.ZERO, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	kt.tween_callback(func(): done.emit())
