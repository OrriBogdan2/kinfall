class_name KinPortrait
extends RefCounted
## Little front-on pictures of kin for menus (the Kin Burrow grid). Each one is a tiny SubViewport
## with its own world holding the kin's real model (shimmer, mutations, forms and all), rendered once.
## Viewports live under one holder node at the root and are kept by look, so reopening a menu
## doesn't rebuild them. Headless there is no renderer: callers fall back to a coloured disc.

const SIZE := 112
const KEEP := 160

static var _cache: Dictionary = {}      # look key -> SubViewport
static var _order: Array = []

static func key(rec: Dictionary) -> String:
	return "%s|%s|%s|%s|%s|%d|%s|%d" % [rec.get("uid", ""), rec.get("species", ""), rec.get("shimmer", false), ",".join(Mutations.of(rec)),
		str((rec.get("forms", []) as Array).size()), (rec.get("muts", []) as Array).size(), rec.get("acc", ""), 1 if int(rec.get("level", 1)) < 4 else 0]

static func available() -> bool:
	return DisplayServer.get_name() != "headless"

## A texture of this kin (fills in on the next drawn frame), or null when nothing can render.
static func tex(rec: Dictionary, tree: SceneTree) -> Texture2D:
	if not available() or tree == null or not Data.KIN.has(String(rec.get("species", ""))):
		return null
	var k := key(rec)
	if _cache.has(k) and is_instance_valid(_cache[k]):
		return (_cache[k] as SubViewport).get_texture()
	var holder: Node = tree.root.get_node_or_null("KinPortraits")
	if holder == null:
		holder = Node.new(); holder.name = "KinPortraits"
		tree.root.add_child(holder)
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_2X
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("8a93b8")
	e.ambient_light_energy = 0.95
	env.environment = e
	vp.add_child(env)
	var key_l := DirectionalLight3D.new()
	key_l.rotation_degrees = Vector3(-30, 200, 0)
	key_l.light_color = Color("fff1dc")
	key_l.light_energy = 1.1
	vp.add_child(key_l)
	var mdl := Models.kin(String(rec["species"]), rec)
	# the picture shows its shape, not its size: Giant and Tiny are framed the same
	var s := maxf(0.4, mdl.scale.y)
	mdl.scale = Vector3.ONE
	for ch in mdl.get_children():
		if ch is CPUParticles3D or ch is GPUParticles3D: (ch as Node3D).visible = false
	vp.add_child(mdl)
	var cam := Camera3D.new()
	cam.fov = 30.0
	vp.add_child(cam)
	var look_at := Vector3(0, 0.4, 0)
	cam.transform = Transform3D(Basis(), look_at + Vector3(0.75, 0.32, -1.75)).looking_at(look_at + Vector3(0, -0.02, 0), Vector3.UP)
	cam.current = true
	holder.add_child(vp)
	_cache[k] = vp
	_order.append(k)
	while _order.size() > KEEP:
		var old: String = _order.pop_front()
		if _cache.has(old) and is_instance_valid(_cache[old]): (_cache[old] as Node).queue_free()
		_cache.erase(old)
	return vp.get_texture()

## A picture of a kin for a menu cell: its portrait, or (headless / not ready) a soft disc in its colours.
static func view(rec: Dictionary, tree: SceneTree, px := 56.0) -> Control:
	var t := tex(rec, tree)
	if t != null:
		var tr := TextureRect.new()
		tr.texture = t
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(px, px)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return tr
	return Disc.new(rec, px)

## The fallback picture: a disc in the kin's body and belly colours with its glow as a rim.
class Disc extends Control:
	var body := Color.WHITE
	var belly := Color.WHITE
	var glow := Color.WHITE
	func _init(rec: Dictionary, px: float) -> void:
		var sp: Dictionary = Data.KIN.get(String(rec.get("species", "")), {})
		body = sp.get("color", Color.WHITE); belly = sp.get("belly", body); glow = sp.get("glow", body)
		if rec.get("shimmer", false):
			body = Care.shimmer_col(body); belly = Care.shimmer_col(belly)
		for id in Mutations.of(rec):
			var pal: Dictionary = (Mutations.info(id).get("visual", {}) as Dictionary).get("palette", {})
			if pal.has("body"): body = Mutations._op(body, pal["body"])
			if pal.has("belly"): belly = Mutations._op(belly, pal["belly"])
		custom_minimum_size = Vector2(px, px)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.4
		draw_circle(c, r + 2.0, Color(glow, 0.6))
		draw_circle(c, r, body)
		draw_circle(c + Vector2(0, r * 0.35), r * 0.5, belly)
		for sx in [-1.0, 1.0]:
			draw_circle(c + Vector2(sx * r * 0.36, -r * 0.18), r * 0.13, Color("1a1620"))
