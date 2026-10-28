class_name Fx
extends Node3D
## Pooled visual effects: particle bursts, damage numbers, ground rings, attack telegraphs, lightning.

const TELEGRAPH: Shader = preload("res://shaders/telegraph.gdshader")
var font: Font = preload("res://fonts/LilitaOne-Regular.ttf")

var bursts: Array[CPUParticles3D] = []
var bi := 0
var nums: Array = []          # {node, t, vel}
var num_pool: Array[Label3D] = []
var rings: Array = []         # {node, t, dur, r}
var teles: Array = []
var lines: Array = []         # {node, t}
var flashes: Array = []
var particle_mat: StandardMaterial3D
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	particle_mat = StandardMaterial3D.new()
	particle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_mat.vertex_color_use_as_albedo = true
	particle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var pm := SphereMesh.new(); pm.radius = 0.06; pm.height = 0.12; pm.radial_segments = 6; pm.rings = 3
	pm.material = particle_mat
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1)); ramp.set_color(1, Color(1, 1, 1, 0))
	for i in 28:
		var p := CPUParticles3D.new()
		p.one_shot = true
		p.emitting = false
		p.explosiveness = 0.95
		p.mesh = pm
		p.lifetime = 0.55
		p.amount = 16
		p.direction = Vector3.UP
		p.spread = 180.0
		p.gravity = Vector3(0, -12, 0)
		p.initial_velocity_min = 2.0
		p.initial_velocity_max = 5.0
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.4
		p.damping_min = 2.0
		p.damping_max = 4.0
		p.color_ramp = ramp
		p.local_coords = false
		add_child(p)
		bursts.append(p)
	for i in 40:
		var l := Label3D.new()
		l.font = font
		l.font_size = 52
		l.pixel_size = 0.011
		l.outline_size = 14
		l.outline_modulate = Color(0.05, 0.04, 0.08, 0.9)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.render_priority = 10
		l.outline_render_priority = 9
		l.visible = false
		add_child(l)
		num_pool.append(l)

func burst(at: Vector3, col: Color, amount := 14, speed := 4.0, life := 0.5, grav := 12.0, size := 1.0, dir := Vector3.UP, spread := 180.0) -> void:
	var p := bursts[bi]
	bi = (bi + 1) % bursts.size()
	p.global_position = at
	p.amount = amount
	p.color = col
	p.lifetime = life
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -grav, 0)
	p.scale_amount_min = 0.6 * size
	p.scale_amount_max = 1.4 * size
	p.direction = dir
	p.spread = spread
	p.restart()
	p.emitting = true

func dust(at: Vector3, n := 8) -> void:
	burst(at + Vector3(0, 0.1, 0), Color(0.82, 0.8, 0.72, 0.9), n, 2.2, 0.45, 2.0, 1.3, Vector3.UP, 80.0)

func dash_trail(h) -> void:
	var c: Color = Data.TEAM_COLORS[h.team % Data.TEAM_COLORS.size()]
	burst(h.pos + Vector3(0, 0.6, 0), Color(c, 0.7), 12, 1.2, 0.3, 0.0, 1.6)
	dust(h.pos, 7)
	ring(h.pos, 1.3, Color(c, 0.8), 0.22)

var ghosts: Array = []
var _ghost_mesh: Mesh

## A fading after-image of a dashing hunter.
func ghost(at: Vector3, yaw: float, col: Color, scl: float) -> void:
	if _ghost_mesh == null:
		_ghost_mesh = Models.capsule(0.3, 1.25)
	var mi := MeshInstance3D.new()
	mi.mesh = _ghost_mesh
	mi.material_override = Models.glow_mat(Color(col, 0.55))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = at + Vector3(0, 0.7 * scl, 0)
	mi.rotation.y = yaw
	mi.scale = Vector3(1.0, 1.0, 1.3) * scl
	ghosts.append({"node": mi, "t": 0.0, "col": col})

func number(at: Vector3, v: float, col: Color, crit: bool, prefix := "") -> void:
	if v < 0.5 or (prefix == "" and not Settings.get_v("damage_numbers")):
		return
	var l: Label3D = num_pool.pop_front()
	num_pool.append(l)
	for n in nums:
		if n["node"] == l:
			nums.erase(n); break
	l.text = prefix + str(int(round(v)))
	l.modulate = col
	l.font_size = 64 if crit else 50
	l.global_position = at + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.2, 0.2))
	l.visible = true
	l.scale = Vector3.ONE * (1.6 if crit else 1.25)
	nums.append({"node": l, "t": 0.0, "vel": Vector3(rng.randf_range(-0.6, 0.6), 3.2, 0)})

func ring(at: Vector3, radius: float, col: Color, dur := 0.35) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = Models.flat_quad(2.0)
	mi.material_override = Models.ring_mat(col, 0.12)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = at + Vector3(0, 0.08, 0)
	mi.scale = Vector3.ONE * 0.1
	rings.append({"node": mi, "t": 0.0, "dur": dur, "r": radius, "col": col})

func flash(at: Vector3, col: Color, size := 0.35, dur := 0.06) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = Models.sphere(size, 8)
	mi.material_override = Models.glow_mat(col)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = at
	flashes.append({"node": mi, "t": 0.0, "dur": dur})

func bolt(a: Vector3, b: Vector3, col: Color) -> void:
	var pts := [a]
	for i in range(1, 5):
		var k := i / 5.0
		pts.append(a.lerp(b, k) + Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.2, 0.2), rng.randf_range(-0.3, 0.3)))
	pts.append(b)
	for i in pts.size() - 1:
		var p0: Vector3 = pts[i]; var p1: Vector3 = pts[i + 1]
		var mi := MeshInstance3D.new()
		mi.mesh = Models.box(0.07, 0.07, 1.0)
		mi.material_override = Models.glow_mat(col)
		add_child(mi)
		mi.global_position = (p0 + p1) * 0.5
		mi.look_at(p1, Vector3.UP if absf((p1 - p0).normalized().y) < 0.95 else Vector3.RIGHT)
		mi.scale = Vector3(1, 1, p0.distance_to(p1))
		lines.append({"node": mi, "t": 0.0, "dur": 0.18})
	burst(b, col, 10, 3.0, 0.3, 4.0)

func cone(at: Vector3, d: Vector2, length: float, col: Color) -> void:
	for i in 3:
		burst(at + Vector3(d.x, 0.5, d.y) * (0.5 + i * 1.2), col, 12, 6.0, 0.4, 4.0, 1.4, Vector3(d.x, 0.2, d.y), 25.0)

# ---- telegraphs
func _tele_mesh(col: Color, shape: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mat := ShaderMaterial.new()
	mat.shader = TELEGRAPH
	mat.set_shader_parameter("color", col)
	mat.set_shader_parameter("shape", shape)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	teles.append(mi)
	return mi

func telegraph_circle(at: Vector3, radius: float, col: Color) -> Node3D:
	var mi := _tele_mesh(col, 0)
	mi.mesh = Models.flat_quad(radius * 2.0)
	mi.global_position = at + Vector3(0, 0.07, 0)
	return mi

func telegraph_rect(at: Vector3, d: Vector2, length: float, width: float, col: Color) -> Node3D:
	var mi := _tele_mesh(col, 1)
	var pm := PlaneMesh.new(); pm.size = Vector2(width, length)
	mi.mesh = pm
	mi.set_meta("len", length)
	aim_telegraph(mi, at, d)
	return mi

func aim_telegraph(mi: Node3D, at: Vector3, d: Vector2) -> void:
	var length: float = mi.get_meta("len", 2.0)
	mi.global_position = at + Vector3(d.x, 0, d.y) * (length * 0.5) + Vector3(0, 0.07, 0)
	mi.rotation = Vector3(0, atan2(-d.x, -d.y), 0)

func telegraph_progress(mi: Node3D, p: float) -> void:
	(mi as MeshInstance3D).material_override.set_shader_parameter("progress", clampf(p, 0.0, 1.0))

func end_telegraph(mi: Node3D) -> void:
	teles.erase(mi)
	mi.queue_free()

func _process(delta: float) -> void:
	for n in nums.duplicate():
		n["t"] += delta
		var l: Label3D = n["node"]
		n["vel"].y -= 9.0 * delta
		l.global_position += n["vel"] * delta
		var k: float = n["t"]
		l.scale = Vector3.ONE * lerpf(l.scale.x, 1.0, minf(1.0, delta * 12.0))
		l.modulate.a = clampf(1.6 - k * 2.2, 0.0, 1.0)
		if k > 0.75:
			l.visible = false
			nums.erase(n)
	for rg in rings.duplicate():
		rg["t"] += delta
		var k: float = rg["t"] / rg["dur"]
		var mi: MeshInstance3D = rg["node"]
		mi.scale = Vector3.ONE * lerpf(0.2, rg["r"], 1.0 - pow(1.0 - minf(k, 1.0), 3.0))
		mi.material_override.set_shader_parameter("color", Color(rg["col"], clampf(1.0 - k, 0.0, 1.0)))
		if k >= 1.0:
			mi.queue_free(); rings.erase(rg)
	for f in flashes.duplicate():
		f["t"] += delta
		var mi: MeshInstance3D = f["node"]
		mi.scale = Vector3.ONE * (1.0 + f["t"] / f["dur"])
		if f["t"] >= f["dur"]:
			mi.queue_free(); flashes.erase(f)
	for g in ghosts.duplicate():
		g["t"] += delta
		var k: float = g["t"] / 0.26
		var gm: MeshInstance3D = g["node"]
		gm.material_override.set_shader_parameter("color", Color(g["col"], 0.55 * (1.0 - k)))
		gm.scale *= 1.0 - delta * 1.5
		if k >= 1.0:
			gm.queue_free(); ghosts.erase(g)
	for ln in lines.duplicate():
		ln["t"] += delta
		if ln["t"] >= ln["dur"]:
			ln["node"].queue_free(); lines.erase(ln)
