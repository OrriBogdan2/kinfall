class_name Assets
## Imported models from CC0 asset packs (KayKit, by Kay Lousberg: see docs/ASSET_CREDITS.md) for the
## world's props and the monsters. Our own hunters and kin stay procedural (Models).
##
## Every pack colours its models from one shared palette texture. Models are vendored without it
## (tools/vendor_gltf.py) and drawn with our toon shader, which samples the palette and can repaint
## one band of hues (the leaves, the cloth) in a biome's colour, so imported props light, outline
## and fog exactly like everything else.
##
## Prop kinds map to variants per biome style ("meadow", "bloom", "frost", "ember", "storm", "gloom").
## A variant is {m: "<pack>/<file>", w: weight, h: [min, max] height in metres (or fp: footprint
## width), paint: what the repainted band becomes ("leaf", "green", "own", "cloth"), plus the band}.
## If a model can't be loaded, callers get null and fall back to the old primitive models; run with
## --prim-art to force that everywhere (for comparisons).

const V := "res://art/vendor/"
static var TOON: Shader = preload("res://shaders/toon.gdshader")

## The hue bands that can be repainted, per source model family.
const BAND_HEX_LEAF := {"hue": 0.45, "width": 0.06, "min_sat": 0.6, "ref": 0.5}
const BAND_HW_PINE := {"hue": 0.06, "width": 0.06, "min_sat": 0.5, "min_val": 0.45, "ref": 0.68}
const BAND_HW_PINE_Y := {"hue": 0.09, "width": 0.05, "min_sat": 0.5, "min_val": 0.45, "ref": 0.74}
const BAND_WOOD := {"hue": 0.045, "width": 0.03, "min_sat": 0.45, "ref": 0.6}
const BAND_SKEL_CLOTH := {"hue": 0.05, "width": 0.04, "min_sat": 0.42, "min_val": 0.3, "ref": 0.66}

const TREES := {
	"meadow": [
		{"m": "hexagon/tree_single_A", "w": 3, "h": [2.3, 3.0], "paint": "green", "band": BAND_HEX_LEAF},
		{"m": "hexagon/tree_single_B", "w": 2, "h": [2.4, 3.2], "paint": "green", "band": BAND_HEX_LEAF},
		{"m": "halloween/tree_pine_orange_large", "w": 3, "h": [2.6, 3.4], "paint": "leaf", "band": BAND_HW_PINE},
		{"m": "halloween/tree_pine_orange_medium", "w": 2, "h": [2.0, 2.6], "paint": "leaf", "band": BAND_HW_PINE},
	],
	"bloom": [
		{"m": "halloween/tree_pine_orange_large", "w": 3, "h": [2.6, 3.4], "paint": "leaf", "band": BAND_HW_PINE},
		{"m": "halloween/tree_pine_orange_medium", "w": 3, "h": [2.0, 2.6], "paint": "leaf", "band": BAND_HW_PINE},
		{"m": "hexagon/tree_single_A", "w": 3, "h": [2.3, 3.0], "paint": "green", "band": BAND_HEX_LEAF},
	],
	"frost": [
		{"m": "halloween/tree_pine_orange_large", "w": 3, "h": [2.7, 3.5], "paint": "leaf", "band": BAND_HW_PINE},
		{"m": "halloween/tree_pine_orange_medium", "w": 2, "h": [2.0, 2.7], "paint": "leaf", "band": BAND_HW_PINE},
		{"m": "hexagon/tree_single_B", "w": 2, "h": [2.4, 3.2], "paint": "leaf", "band": BAND_HEX_LEAF},
		{"m": "halloween/tree_dead_small", "w": 1, "h": [1.8, 2.3], "paint": "own", "bright": 1.7, "tint": Color("d8e4f0")},
	],
	"ember": [
		{"m": "halloween/tree_pine_orange_large", "w": 2, "h": [2.6, 3.3], "paint": "own", "band": BAND_HW_PINE},
		{"m": "halloween/tree_pine_yellow_large", "w": 1, "h": [2.4, 3.0], "paint": "own", "band": BAND_HW_PINE_Y},
		{"m": "halloween/tree_dead_large", "w": 2, "h": [2.6, 3.3], "paint": "own", "bright": 1.7, "tint": Color("8a6a62")},
		{"m": "halloween/tree_dead_medium", "w": 2, "h": [2.0, 2.6], "paint": "own", "bright": 1.7, "tint": Color("8a6a62")},
	],
	"storm": [
		{"m": "halloween/tree_dead_large", "w": 2, "h": [2.6, 3.3], "paint": "own", "bright": 1.7, "tint": Color("b8bcd8")},
		{"m": "halloween/tree_dead_medium", "w": 2, "h": [2.0, 2.6], "paint": "own", "bright": 1.7, "tint": Color("b8bcd8")},
		{"m": "hexagon/tree_single_B", "w": 3, "h": [2.4, 3.2], "paint": "green", "band": BAND_HEX_LEAF},
		{"m": "halloween/tree_pine_orange_medium", "w": 2, "h": [2.0, 2.6], "paint": "leaf", "band": BAND_HW_PINE},
	],
	"gloom": [
		{"m": "halloween/tree_dead_large_decorated", "w": 1, "h": [2.8, 3.4], "paint": "own", "bright": 1.7, "tint": Color("b0a0c8")},
		{"m": "halloween/tree_dead_large", "w": 2, "h": [2.6, 3.3], "paint": "own", "bright": 1.7, "tint": Color("b0a0c8")},
		{"m": "halloween/tree_pine_orange_large", "w": 2, "h": [2.6, 3.3], "paint": "leaf", "band": BAND_HW_PINE},
		{"m": "halloween/tree_pine_orange_medium", "w": 2, "h": [2.0, 2.6], "paint": "leaf", "band": BAND_HW_PINE},
	],
}

const ROCKS := {
	"meadow": [
		{"m": "hexagon/rock_single_A", "w": 2, "fp": [1.0, 1.35]},
		{"m": "hexagon/rock_single_B", "w": 2, "fp": [1.0, 1.35]},
		{"m": "hexagon/rock_single_C", "w": 2, "fp": [1.0, 1.35]},
		{"m": "hexagon/rock_single_D", "w": 2, "fp": [1.0, 1.35]},
		{"m": "hexagon/rock_single_E", "w": 2, "fp": [1.0, 1.35]},
		{"m": "dungeon/rubble_half", "w": 1, "fp": [1.1, 1.4], "bright": 1.7},
	],
	"frost": [
		{"m": "hexagon/mountain_A", "w": 2, "fp": [1.0, 1.2]},
		{"m": "hexagon/mountain_B", "w": 2, "fp": [1.0, 1.2]},
		{"m": "hexagon/rock_single_C", "w": 2, "fp": [1.0, 1.35]},
		{"m": "hexagon/rock_single_E", "w": 2, "fp": [1.0, 1.35]},
	],
	"ember": [
		{"m": "dungeon/rubble_large", "w": 2, "fp": [1.1, 1.4], "bright": 1.7},
		{"m": "dungeon/rubble_half", "w": 2, "fp": [1.1, 1.4], "bright": 1.7},
		{"m": "hexagon/mountain_C", "w": 1, "fp": [1.0, 1.2]},
		{"m": "hexagon/rock_single_B", "w": 1, "fp": [1.0, 1.35]},
	],
	"storm": [
		{"m": "hexagon/mountain_A", "w": 2, "fp": [1.0, 1.2]},
		{"m": "hexagon/mountain_C", "w": 2, "fp": [1.0, 1.2]},
		{"m": "hexagon/rock_single_A", "w": 2, "fp": [1.0, 1.35]},
		{"m": "hexagon/rock_single_D", "w": 2, "fp": [1.0, 1.35]},
	],
}

## Standing stones of an old ruin: around the Heart's vault, the shrines, and the map's pillars.
const PILLARS := [
	{"m": "dungeon/pillar", "w": 3, "fp": [0.9, 0.95], "bright": 1.45},
	{"m": "dungeon/column", "w": 2, "fp": [0.9, 0.95], "bright": 1.45},
	{"m": "dungeon/pillar_decorated", "w": 1, "fp": [0.9, 0.95], "bright": 1.45},
]
## A camp's cover: crates, barrels and supplies.
const CAMP := [
	{"m": "dungeon/crates_stacked", "w": 2, "fp": [1.1, 1.2]},
	{"m": "dungeon/barrel_large", "w": 1, "fp": [0.95, 1.05]},
	{"m": "hexagon/resource_lumber", "w": 1, "fp": [1.1, 1.25]},
	{"m": "dungeon/box_large", "w": 2, "fp": [1.0, 1.1]},
	{"m": "hexagon/tent", "w": 1, "fp": [1.25, 1.35]},
]
## Little stones scattered over the ground (no collision).
const PEBBLES := [
	{"m": "hexagon/rock_single_A", "w": 1, "fp": [0.18, 0.4]},
	{"m": "hexagon/rock_single_C", "w": 1, "fp": [0.18, 0.4]},
	{"m": "hexagon/rock_single_E", "w": 1, "fp": [0.18, 0.4]},
]

static var _off := -1
static var _scenes := {}
static var _meshes := {}
static var _pal := {}
static var _mats := {}

## False when the imported models are switched off (--prim-art), so callers build the old ones.
static func on() -> bool:
	if _off < 0:
		_off = 1 if "--prim-art" in OS.get_cmdline_user_args() else 0
	return _off == 0

static func scene(id: String) -> PackedScene:
	if _scenes.has(id):
		return _scenes[id]
	var path := V + id + ".glb"
	var ps: PackedScene = null
	if on() and ResourceLoader.exists(path):
		ps = load(path) as PackedScene
	if ps == null and on():
		push_warning("Assets: couldn't load %s, using the primitive model" % path)
	_scenes[id] = ps
	return ps

static func palette(pack: String) -> Texture2D:
	if not _pal.has(pack):
		var path := V + pack + "/palette.png"
		_pal[pack] = load(path) if ResourceLoader.exists(path) else null
	return _pal[pack]

## The model's static meshes merged into one (in the model's own space), or null.
static func mesh(id: String) -> ArrayMesh:
	if _meshes.has(id):
		return _meshes[id]
	var am: ArrayMesh = null
	var ps := scene(id)
	if ps:
		var root := ps.instantiate() as Node3D
		var st := SurfaceTool.new()
		var any := false
		for mi in _mesh_nodes(root):
			var tr := _rel(mi, root)
			for s in mi.mesh.get_surface_count():
				st.append_from(mi.mesh, s, tr)
				any = true
		if any:
			am = _smooth_tangents(st.commit())
		root.free()
	_meshes[id] = am
	return am

## One named node's own mesh from a model (its children left out), in that node's space, and the
## node's transform in the model. [mesh, Transform3D] or [] if missing. For models with moving
## parts, like a chest's lid.
static func part(id: String, node_name: String) -> Array:
	var key := id + "#" + node_name
	if _meshes.has(key):
		return _meshes[key]
	var out: Array = []
	var ps := scene(id)
	if ps:
		var root := ps.instantiate() as Node3D
		var n := root.find_child(node_name, true, false)
		if n is MeshInstance3D and (n as MeshInstance3D).mesh:
			var st := SurfaceTool.new()
			for s in (n as MeshInstance3D).mesh.get_surface_count():
				st.append_from((n as MeshInstance3D).mesh, s, Transform3D.IDENTITY)
			out = [_smooth_tangents(st.commit()), _rel(n, root)]
		root.free()
	_meshes[key] = out
	return out

## Stores, in each vertex's tangent, the average normal of every face meeting at its position, for
## the outline shell (shaders/outline_smooth.gdshader). The shading still uses the flat normals.
static func _smooth_tangents(src: ArrayMesh) -> ArrayMesh:
	var arrs := src.surface_get_arrays(0)
	var verts: PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrs[Mesh.ARRAY_NORMAL]
	var acc := {}
	for k in verts.size():
		var key := Vector3i(verts[k] * 1000.0)
		acc[key] = acc.get(key, Vector3.ZERO) + norms[k]
	var tan := PackedFloat32Array(); tan.resize(verts.size() * 4)
	for k in verts.size():
		var n: Vector3 = acc[Vector3i(verts[k] * 1000.0)]
		n = n.normalized() if n.length() > 0.0001 else norms[k]
		tan[k * 4] = n.x; tan[k * 4 + 1] = n.y; tan[k * 4 + 2] = n.z; tan[k * 4 + 3] = 1.0
	arrs[Mesh.ARRAY_TANGENT] = tan
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrs)
	return am

static func _mesh_nodes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		out.append(n)
	for c in n.get_children():
		out.append_array(_mesh_nodes(c))
	return out

static func _rel(n: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur and cur != root:
		t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t

## The toon material for a pack's models. cfg: band (the repaintable hues), paint (Color or null),
## tint (Color multiplying everything), instanced (MultiMesh: the instance colour is the paint
## target, or with color_tint the tint), outline.
static func material(pack: String, cfg := {}) -> ShaderMaterial:
	var key := pack + str(cfg)
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = TOON
	m.set_shader_parameter("use_tex", true)
	m.set_shader_parameter("albedo_tex", palette(pack))
	m.set_shader_parameter("albedo", Color(cfg.get("tint", Color.WHITE)) * float(cfg.get("bright", 1.0)))
	m.set_shader_parameter("rim_amount", float(cfg.get("rim", 0.3)))
	m.set_shader_parameter("tex_sat", float(cfg.get("sat", 0.92)))
	m.set_shader_parameter("paint", float(cfg.get("paint_noise", 0.05)))
	var band: Dictionary = cfg.get("band", {})
	if not band.is_empty():
		m.set_shader_parameter("recolor_hue", float(band["hue"]))
		m.set_shader_parameter("recolor_width", float(band["width"]))
		m.set_shader_parameter("recolor_min_sat", float(band.get("min_sat", 0.25)))
		m.set_shader_parameter("recolor_min_val", float(band.get("min_val", 0.0)))
		m.set_shader_parameter("recolor_ref", float(band.get("ref", 0.6)))
	if cfg.get("instanced", false):
		m.set_shader_parameter("use_vertex_color", true)
		m.set_shader_parameter("recolor", 1.0 if cfg.get("repaint", false) else 0.0)
		m.set_shader_parameter("color_tint", float(cfg.get("color_tint", 0.0)))
	elif cfg.get("paint") != null:
		m.set_shader_parameter("recolor", 1.0)
		m.set_shader_parameter("recolor_to", cfg["paint"])
	if cfg.get("outline", true):
		m.next_pass = outline_mat()
	if not cfg.get("cache", true):
		return m
	_mats[key] = m
	return m

static var _outline: ShaderMaterial
static func outline_mat() -> ShaderMaterial:
	if _outline == null:
		_outline = ShaderMaterial.new()
		_outline.shader = load("res://shaders/outline_smooth.gdshader")
	return _outline

## Picks a variant by weight.
static func pick(list: Array, rng: RandomNumberGenerator) -> Dictionary:
	var tot := 0.0
	for v in list: tot += float(v.get("w", 1))
	var r := rng.randf() * tot
	for v in list:
		r -= float(v.get("w", 1))
		if r <= 0.0: return v
	return list[-1]

## Uniform scale that brings a variant's mesh to its height or footprint range.
static func fit_scale(v: Dictionary, am: ArrayMesh, rng: RandomNumberGenerator) -> float:
	var ab := am.get_aabb()
	if v.has("h"):
		return rng.randf_range(float(v["h"][0]), float(v["h"][1])) / maxf(0.01, ab.size.y)
	var fp: Array = v.get("fp", [1.0, 1.0])
	return rng.randf_range(float(fp[0]), float(fp[1])) / maxf(0.01, maxf(ab.size.x, ab.size.z))

static func pack_of(id: String) -> String:
	return id.get_slice("/", 0)

## The tree list for a biome style (falls back to meadow).
static func trees(style: String) -> Array:
	return TREES.get(style, TREES["meadow"])

static func rocks(style: String) -> Array:
	return ROCKS.get(style, ROCKS["meadow"])

## A single static prop as its own node (one mesh, our material), sized to fit, sitting on y = 0.
## null when the model isn't there.
static func prop(id: String, size: float, by_height := false, cfg := {}) -> Node3D:
	var am := mesh(id)
	if am == null:
		return null
	var ab := am.get_aabb()
	var s := size / maxf(0.01, ab.size.y if by_height else maxf(ab.size.x, ab.size.z))
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = material(pack_of(id), cfg)
	mi.scale = Vector3.ONE * s
	mi.position = Vector3(-(ab.position.x + ab.size.x * 0.5) * s, -ab.position.y * s, -(ab.position.z + ab.size.z * 0.5) * s)
	root.add_child(mi)
	root.set_meta("mats", [mi.material_override])
	return root
