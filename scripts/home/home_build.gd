class_name HomeBuild
extends RefCounted
## Build mode at home (B, or the Build button): lay out your islands on the tile grid.
##   pick something from the catalog bar and place it (a green ghost fits, a red one doesn't), turn
##   it with R / the wheel / right click, drag fences out in lines that join up, paint paths and pond
##   water tile by tile, click anything already placed (buildings too) to pick it up and move it,
##   X puts a decoration back into storage, Ctrl+Z undoes, and the Island tab has colour themes,
##   expanding the island and resetting the layout.
## Nothing may sit on a path the island needs: every door, the portal, the pot, the stall, the farm
## and the feeders must stay reachable from your house. The data is HomeLayout (Save.d["layout"]);
## this keeps the world's blockers, the kin path grid and the decoration nodes in step with it.

var h                                  # the Home screen
var active := false
var cat := "Garden"
var page := 0
var held := {}                         # {kind: "deco" | "b", id, r, from (deco uid, or -1 for a new one), c}
var ghost: Node3D = null
var ghost_cells: Node3D = null
var ghost_ok := false
var why := ""
var cells: Array = []                  # tiles the ghost covers right now
var anchor := Vector2i(-999, -999)
var drag := {}                         # dragging out a fence line or painting: {from, tiles: {Vector2i: true}, last}
var undo: Array = []
var colour := 0
var bar: Control = null
var hint_lbl: Label = null
var nodes := {}                        # deco uid -> Node3D
var fence_root: Node3D
var water_root: Node3D
var blocked := {}                      # tile index -> true: blockers the layout put into the world
var occ := {}                          # tile index -> "b:<id>" | "d:<uid>" | "w"
var reserved := {}                     # tile index -> true: kept clear for the farm's fixed things
var base_paint := {}
var astar: AStarGrid2D
var ver := 0
var mesh_t := -1.0
var grid_t := 0.0
var _reach_cache := {}
var _fence_sig := ""
var _water_sig := ""
static var pending_toast := ""
var debug_m := Vector2.INF             # tooling: where the "mouse" is, for screenshots

const BASE_BIOME := {"top": Color("5f8d45"), "top2": Color("4a7538"), "side": Color("8b6d52"), "deep": Color("3a3140"), "leaf": Color("5a9a4f")}

func _init(home) -> void:
	h = home

func L() -> Dictionary:
	return HomeLayout.of(h._d())

# ------------------------------------------------------------------ setting the world up
## Before the meshes are built: the theme, painted paths and water, and every blocker the layout adds.
func prepare_world() -> void:
	base_paint = h.world.paint.duplicate()
	_reserve()
	_apply_theme()
	_seed_water()
	_apply_paint()
	_apply_blockers()
	_apply_wild()

# ------------------------------------------------------------------ a procedural home's wild land
var wild_t := {}                       # tile index -> "tree" | "rock" | "water": the wild still standing

func _seed() -> int:
	return int(L().get("seed", 0))

func _wild_keep() -> Dictionary:
	var w: World = h.world
	var keep := reserved.duplicate()
	for i in occ: keep[i] = true
	for b in Data.BUILDINGS:
		var rc := HomeLayout.rect_of(b, h._d())
		for c in HomeLayout.cells_of([rc[0] - 1, rc[1] - 1, rc[2] + 1, rc[3] + 3]):
			if w.inb(c.x, c.y): keep[w.idx(c.x, c.y)] = true
	for f in Econ.feeders() if h.visit.is_empty() else []:
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				var x := int(floor(float(f["x"]))) + dx; var z := int(floor(float(f["z"]))) + dz
				if w.inb(x, z): keep[w.idx(x, z)] = true
	return keep

## The first time a procedural home loads, its pond or stream becomes ordinary layout water
## (so you can fill it in or extend it like any other).
func _seed_water() -> void:
	var lay := L()
	if _seed() == 0 or lay.get("wild_water", false) or not h.visit.is_empty():
		return
	lay["wild_water"] = true
	var w: World = h.world
	var wt := HomeLayout.wild(w, _seed(), _wild_keep())
	for i in wt:
		if wt[i] == "water": lay["water"][HomeLayout.key(i % w.w, i / w.w)] = 1

func _apply_wild() -> void:
	wild_t.clear()
	if _seed() == 0:
		return
	var w: World = h.world
	var cl: Dictionary = L().get("cleared", {})
	var wt := HomeLayout.wild(w, _seed(), _wild_keep())
	for i in wt:
		if wt[i] == "water" or cl.has(HomeLayout.key(i % w.w, i / w.w)): continue
		if w.kind[i] == World.T_GROUND:
			w.kind[i] = World.T_BLOCK
			w.props[i] = wt[i]
			wild_t[i] = wt[i]
	# nothing may be shut in: open the wild (and any generated water) round every pocket
	var lay := L()
	for k in lay["water"]:
		var c := HomeLayout.unkey(k)
		if w.inb(c.x, c.y): wild_t[w.idx(c.x, c.y)] = "water"
	var dp: Vector3 = h._house_door()
	var left := HomeLayout.open_up(w, Vector2i(int(floor(dp.x)), int(floor(dp.z))), wild_t)
	for k in (lay["water"] as Dictionary).keys():
		var c := HomeLayout.unkey(k)
		if w.inb(c.x, c.y) and not left.has(w.idx(c.x, c.y)):
			lay["water"].erase(k)
			blocked.erase(w.idx(c.x, c.y)); occ.erase(w.idx(c.x, c.y))
	for i in left.keys():
		if left[i] == "water": left.erase(i)
	wild_t = left
	for i in w.props.keys():
		if w.kind[i] != World.T_BLOCK: w.props.erase(i)

func clear_wild(t: Vector2i) -> bool:
	var w: World = h.world
	if not w.inb(t.x, t.y): return false
	var i := w.idx(t.x, t.y)
	if not wild_t.has(i): return false
	wild_t.erase(i)
	w.props.erase(i)
	w.kind[i] = World.T_GROUND
	L()["cleared"][HomeLayout.key(t.x, t.y)] = 1
	return true

## The usability rules a home must pass: plenty of open ground on the main island, every bit of it
## reachable from the house, and every place the island needs (doors, portal, farm...) reachable.
func validate() -> Dictionary:
	var w: World = h.world
	var seen := _reach([], [])
	var open := 0; var reached := 0
	for i in w.kind.size():
		if w.island[i] == 0 and w.kind[i] == World.T_GROUND:
			open += 1
			if seen[i] == 1: reached += 1
	var miss: Array = []
	for t in _targets():
		var ti := w.idx(int(floor(t.x)), int(floor(t.z)))
		if w.inb(int(floor(t.x)), int(floor(t.z))) and w.island[ti] > 0 and not _isle_ok(ti): continue    # an isle you haven't bridged yet
		if not _hit(seen, t): miss.append(t)
	return {"ok": open >= 850 and reached == open and miss.is_empty(), "open": open, "reached": reached, "missing": miss}

## After the home's fixed models are in: the decorations, fences and water, and the kin path grid.
func build_visuals() -> void:
	fence_root = Node3D.new(); fence_root.name = "Fences"; h.add_child(fence_root)
	water_root = Node3D.new(); water_root.name = "Water"; h.add_child(water_root)
	_sync_deco()
	_sync_fences()
	_sync_water()
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, h.world.w, h.world.h)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	refresh_grid()
	if pending_toast != "":
		var t := pending_toast
		pending_toast = ""
		h.get_tree().create_timer(0.6).timeout.connect(func(): if h.is_inside_tree(): h._toast(t))

func _reserve() -> void:
	reserved.clear()
	var w: World = h.world
	var rs := func(x0: int, z0: int, x1: int, z1: int):
		for z in range(z0, z1 + 1):
			for x in range(x0, x1 + 1):
				if w.inb(x, z): reserved[w.idx(x, z)] = true
	rs.call(35, 24, 41, 29)      # the house and its door step
	rs.call(41, 26, 43, 28)      # the cooking pot
	rs.call(28, 31, 32, 34)      # the market stall
	rs.call(33, 39, 35, 41)      # the glider rack
	rs.call(36, 37, 40, 41)      # the portal and its sign
	rs.call(41, 40, 43, 41)      # the ferry
	rs.call(31, 35, 35, 39)      # the pond
	rs.call(33, 32, 35, 34)      # the Nesting Nook
	rs.call(39, 31, 42, 34)      # the training yard
	rs.call(43, 29, 48, 38)      # the farm
	rs.call(48, 28, 51, 35)      # the graveyard
	rs.call(32, 26, 36, 29)      # the kin beds by the house
	var oc: Vector2 = Data.ISLES["orchard"]["c"]
	rs.call(int(oc.x) - 4, int(oc.y) + 2, int(oc.x) + 5, int(oc.y) + 4)    # the greenhouse plots
	for k in Data.ISLES:
		var sg: Vector2 = Data.ISLES[k]["sign"]
		rs.call(int(sg.x) - 1, int(sg.y) - 1, int(sg.x) + 1, int(sg.y) + 1)
	for t in h.training_reserved():
		rs.call(t[0], t[1], t[2], t[3])

func _apply_theme() -> void:
	var t: Dictionary = HomeLayout.THEMES.get(String(L().get("theme", "meadow")), HomeLayout.THEMES["meadow"])
	var b: Dictionary = BASE_BIOME.duplicate()
	for k in ["top", "top2", "side", "deep", "leaf"]:
		if t.has(k): b[k] = Color(String(t[k]))
	h.world.biome = b
	for isl in h.world.islands:
		isl["region_fixed"] = int(t.get("region", 0))

func _apply_paint() -> void:
	var w: World = h.world
	w.paint = base_paint.duplicate()
	var lay := L()
	for k in lay["paths"]:
		var c := HomeLayout.unkey(k)
		if not w.inb(c.x, c.y): continue
		var id := String(lay["paths"][k])
		if id == "none": w.paint.erase(w.idx(c.x, c.y))
		elif HomeLayout.CATALOG.has(id): w.paint_tile(c.x, c.y, Color(String(HomeLayout.CATALOG[id]["col"])))
	for k in lay["water"]:
		var c := HomeLayout.unkey(k)
		if w.inb(c.x, c.y): w.paint_tile(c.x, c.y, Color("5d7f8c"))

## Puts the layout's blockers into the world: built buildings, solid decorations and pond tiles.
func _apply_blockers() -> void:
	var w: World = h.world
	for i in blocked:
		if w.kind[i] == World.T_BLOCK:
			w.kind[i] = World.T_GROUND
		w.no_deco.erase(i)
	blocked.clear()
	occ.clear()
	var lay := L()
	var mark := func(c: Vector2i, tag: String, solid: bool):
		if not w.inb(c.x, c.y): return
		var i := w.idx(c.x, c.y)
		if w.kind[i] == World.T_VOID: return
		occ[i] = tag
		if solid:
			if w.kind[i] == World.T_BLOCK and not w.no_deco.has(i):
				w.kind[i] = World.T_GROUND      # a rim tree that grew where you'd put something
			if w.kind[i] == World.T_GROUND:
				w.kind[i] = World.T_BLOCK
				w.no_deco[i] = true
				blocked[i] = true
	for b in Data.BUILDINGS:
		var built: bool = h._has_b(b)
		for c in HomeLayout.cells_of(HomeLayout.rect_of(b, h._d())):
			mark.call(c, "b:" + b, built)
	for e in lay["deco"]:
		for c in HomeLayout.deco_cells(e):
			mark.call(c, "d:%d" % int(e["u"]), HomeLayout.blocks(String(e["id"])))
	for k in lay["water"]:
		mark.call(HomeLayout.unkey(k), "w", true)
	_evict_feeders()
	if h.visit.is_empty():
		for f in Econ.feeders():
			var fi := w.idx(int(floor(float(f.get("x", 0.0)))), int(floor(float(f.get("z", 0.0)))))
			if not occ.has(fi): occ[fi] = "f:" + String(f["id"])

## A feeder standing where the layout now puts something (after an undo or a reset) moves to open ground.
func _evict_feeders() -> void:
	if not h.visit.is_empty() or h.hecon == null:
		return
	for f in Econ.feeders():
		var fp: Vector3 = h.hecon._fpos(f)
		var i: int = h.world.idx(int(floor(fp.x)), int(floor(fp.z)))
		if occ.has(i) and blocked.has(i):
			var p: Vector3 = h.world.free_spot_near(Econ.FEEDER_START, [], 1.0, 0.5, 14.0)
			f["x"] = snappedf(p.x, 0.1); f["z"] = snappedf(p.z, 0.1)
			var n: Node3D = h.hecon.fnodes.get(String(f["id"]))
			if is_instance_valid(n): n.position = h.hecon._fpos(f)
			h.hecon._block(h.hecon._fpos(f), true)

## Everything after a change: blockers, buildings, decorations, the path grid, beds; the ground
## meshes are rebuilt a moment later if paint or the theme changed.
func apply(ground := false) -> void:
	_apply_blockers()
	_sync_buildings()
	_sync_deco()
	_sync_fences()
	_sync_water()
	if ground:
		_apply_wild()
		_apply_theme()
		_apply_paint()
		mesh_t = 0.2
	ver += 1
	_reach_cache.clear()
	refresh_grid()
	h.unstick()
	assign_beds()

func _sync_buildings() -> void:
	for b in h.lots:
		var p := HomeLayout.place_of(b, h._d())
		var rc := HomeLayout.rect_of(b, h._d())
		var l: Dictionary = h.lots[b]
		var at := HomeLayout.rect_center(rc)
		l["at"] = at
		l["door"] = HomeLayout.door_at(b, int(p["x"]), int(p["z"]), int(p["r"]))
		var holder: Node3D = l["node"]
		holder.position = at
		holder.rotation.y = int(p["r"]) * PI * 0.5
		holder.visible = not (held.get("kind", "") == "b" and String(held.get("id", "")) == b)

# ------------------------------------------------------------------ decoration models
func _leaf() -> Color:
	var t: Dictionary = HomeLayout.THEMES.get(String(L().get("theme", "meadow")), {})
	return Color(String(t["leaf"])) if t.has("leaf") else BASE_BIOME["leaf"]

func make_deco(e: Dictionary) -> Node3D:
	var id := String(e["id"])
	var rng := RandomNumberGenerator.new(); rng.seed = int(e.get("u", 1)) * 7919 + 13
	var col := Color(String(e.get("c", HomeLayout.COLOURS[0])))
	var n: Node3D = null
	match id:
		"flowers": n = Models.flower_bed(rng)
		"bush":
			n = Assets.prop("hexagon/tree_single_A", rng.randf_range(0.8, 1.0), true, {"band": Assets.BAND_HEX_LEAF, "paint": _leaf()})
			if n == null: n = Models.tree(rng, _leaf(), "round"); n.scale = Vector3.ONE * 0.45
		"tree":
			n = Assets.prop("hexagon/tree_single_B", rng.randf_range(2.5, 3.0), true, {"band": Assets.BAND_HEX_LEAF, "paint": _leaf()})
			if n == null: n = Models.tree(rng, _leaf(), "round")
		"pine":
			n = Assets.prop("halloween/tree_pine_orange_large", rng.randf_range(2.7, 3.2), true, {"band": Assets.BAND_HW_PINE, "paint": Color("3f7a4a")})
			if n == null: n = Models.tree(rng, Color("3f7a4a"), "pine")
		"blossom_tree":
			n = Assets.prop("hexagon/tree_single_A", rng.randf_range(2.4, 2.8), true, {"band": Assets.BAND_HEX_LEAF, "paint": Color("ff9ac8")})
			if n == null: n = Models.tree(rng, Color("ff9ac8"), "blossom")
		"lantern":
			n = Assets.prop("halloween/lantern_standing", 1.25, true)
			if n == null:
				n = Models.lamp(); n.scale = Vector3.ONE * 0.6
			else:
				var l := OmniLight3D.new()
				l.light_color = Color("ffd9a8"); l.light_energy = 0.5; l.omni_range = 3.5; l.position = Vector3(0, 1.0, 0)
				n.add_child(l)
		"lamp_post": n = Models.lamp()
		"bench":
			n = Assets.prop("halloween/bench", 1.7)
			if n == null:
				n = Node3D.new()
				var wood := Models.toon(Color("8a6242"))
				Models.part(n, Models.box(1.6, 0.08, 0.45), wood, Vector3(0, 0.42, 0))
				Models.part(n, Models.box(1.6, 0.35, 0.06), wood, Vector3(0, 0.65, -0.2))
				for sx in [-0.7, 0.7]:
					Models.part(n, Models.box(0.08, 0.42, 0.4), wood, Vector3(sx, 0.21, 0))
		"kin_bed": n = Models.kin_bed(col)
		"rug", "rug_long":
			n = Node3D.new()
			var sz := Vector2(1.8, 1.8) if id == "rug" else Vector2(2.8, 1.8)
			Models.part(n, Models.box(sz.x, 0.03, sz.y), Models.toon(col, false), Vector3(0, 0.015, 0))
			Models.part(n, Models.box(sz.x - 0.3, 0.035, sz.y - 0.3), Models.toon(col.lightened(0.35), false), Vector3(0, 0.02, 0))
			Models.part(n, Models.box(sz.x - 0.6, 0.04, sz.y - 0.6), Models.toon(col, false), Vector3(0, 0.025, 0))
		"banner": n = Models.banner(col)
		"pillar":
			n = Assets.prop("dungeon/pillar_decorated", 2.3, true, {"bright": 1.45})
			if n == null:
				n = Node3D.new()
				Models.part(n, Models.cyl(0.3, 0.36, 2.2, 10), Models.toon(Color("b8b2a8")), Vector3(0, 1.1, 0))
		"kin_statue":
			n = Node3D.new()
			var stone := Models.toon(Color("b8b2a8")); var dark := Models.toon(Color("8d8a86"))
			Models.part(n, Models.box(0.9, 0.5, 0.9), dark, Vector3(0, 0.25, 0))
			Models.part(n, Models.box(0.75, 0.08, 0.75), stone, Vector3(0, 0.54, 0))
			var sp := String(e.get("sp", "zapple"))
			if not Data.KIN.has(sp): sp = Data.KIN.keys()[0]
			var k := Models.kin(sp, {})
			k.position = Vector3(0, 0.58, 0); k.scale = Vector3.ONE * 1.25
			for mi in k.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).material_override = stone
			for gp in k.find_children("*", "GPUParticles3D", true, false): gp.queue_free()
			for cp in k.find_children("*", "CPUParticles3D", true, false): cp.queue_free()
			n.add_child(k)
		"fountain":
			n = Models.fountain(); n.scale = Vector3(0.55, 0.65, 0.55)
	if n == null:
		n = Node3D.new()
	return n

func _place_node(n: Node3D, e: Dictionary) -> void:
	n.position = HomeLayout.deco_center(e)
	n.rotation.y = int(e.get("r", 0)) * PI * 0.5

func _lights_of(n: Node) -> Array:
	return n.find_children("*", "OmniLight3D", true, false)

func _free_node(n: Node3D) -> void:
	for l in _lights_of(n):
		h.lamps.erase(l)
	n.queue_free()

func _sync_deco() -> void:
	var want := {}
	for e in L()["deco"]:
		if HomeLayout.CATALOG[String(e["id"])].get("line", false):
			continue
		want[int(e["u"])] = e
	for u in nodes.keys():
		var n: Node3D = nodes[u]
		var e = want.get(u)
		if e == null or String(n.get_meta("sig", "")) != _sig(e):
			_free_node(n)
			nodes.erase(u)
	for u in want:
		var e: Dictionary = want[u]
		if not nodes.has(u):
			var n := make_deco(e)
			n.set_meta("sig", _sig(e))
			_place_node(n, e)
			h.add_child(n)
			nodes[u] = n
			for l in _lights_of(n): h.lamps.append(l)
		(nodes[u] as Node3D).visible = not (held.get("kind", "") == "deco" and int(held.get("from", -1)) == int(u))

func _sig(e: Dictionary) -> String:
	return "%s|%d|%d|%d|%s|%s|%s" % [e["id"], int(e["x"]), int(e["z"]), int(e.get("r", 0)), str(e.get("c", "")), str(e.get("px", "")), str(e.get("sp", ""))]

## Fences join up with the fence next to them: every post gets rails toward its neighbours.
func _sync_fences() -> void:
	var f := {}
	for e in L()["deco"]:
		if HomeLayout.CATALOG[String(e["id"])].get("line", false):
			if held.get("kind", "") == "deco" and int(held.get("from", -1)) == int(e["u"]): continue
			f[Vector2i(int(e["x"]), int(e["z"]))] = String(e["id"])
	var sig := str(f)
	if sig == _fence_sig:
		return
	_fence_sig = sig
	for c in fence_root.get_children():
		c.queue_free()
	for c in f:
		var id: String = f[c]
		var n := Node3D.new()
		n.position = Vector3(c.x + 0.5, 0, c.y + 0.5)
		fence_root.add_child(n)
		var links: Array = []
		for dv in [Vector2i(1, 0), Vector2i(0, 1)]:
			if f.get(c + dv, "") == id: links.append(dv)
		var alone: bool = not (f.get(c + Vector2i(1, 0), "") == id or f.get(c + Vector2i(-1, 0), "") == id or f.get(c + Vector2i(0, 1), "") == id or f.get(c + Vector2i(0, -1), "") == id)
		_fence_piece(n, id, links, alone)

func _fence_piece(n: Node3D, id: String, links: Array, alone: bool) -> void:
	match id:
		"fence", "picket":
			var wood := Models.toon(Color("a07a52") if id == "fence" else Color("f1ece0"))
			Models.part(n, Models.box(0.14, 0.8 if id == "fence" else 0.9, 0.14), wood, Vector3(0, 0.4 if id == "fence" else 0.45, 0))
			if id == "picket":
				Models.part(n, Models.cyl(0.0, 0.1, 0.12, 4), wood, Vector3(0, 0.96, 0))
			for dv in links:
				var dir: Vector3 = Vector3(dv.x, 0, dv.y)
				for y in ([0.55, 0.28] if id == "fence" else [0.62, 0.3]):
					var r := Models.part(n, Models.box(1.0, 0.07, 0.05), wood, dir * 0.5 + Vector3(0, y, 0))
					if dv.y != 0: r.rotation.y = PI / 2
				if id == "picket":
					for k in [0.33, 0.66]:
						Models.part(n, Models.box(0.09, 0.78, 0.04), wood, dir * k + Vector3(0, 0.39, 0))
		"stone_wall":
			var st := Models.toon(Color("a9a39a")); var cap := Models.toon(Color("8d8a86"))
			Models.part(n, Models.box(0.5, 0.75, 0.5), cap, Vector3(0, 0.375, 0))
			for dv in links:
				var dir: Vector3 = Vector3(dv.x, 0, dv.y)
				var seg := Models.part(n, Models.box(1.0, 0.6, 0.38), st, dir * 0.5 + Vector3(0, 0.3, 0))
				if dv.y != 0: seg.rotation.y = PI / 2
		"hedge":
			var leaf := Models.toon(_leaf().darkened(0.12))
			Models.part(n, Models.box(0.62, 0.8, 0.62), leaf, Vector3(0, 0.4, 0))
			Models.part(n, Models.sphere(0.36, 8), leaf, Vector3(0, 0.8, 0), Vector3(1, 0.5, 1))
			for dv in links:
				var dir: Vector3 = Vector3(dv.x, 0, dv.y)
				var seg := Models.part(n, Models.box(1.0, 0.75, 0.58), leaf, dir * 0.5 + Vector3(0, 0.375, 0))
				if dv.y != 0: seg.rotation.y = PI / 2
	if alone and id != "hedge" and id != "stone_wall":
		n.scale = Vector3(1.0, 1.0, 1.0)

func _sync_water() -> void:
	var wt: Dictionary = L()["water"]
	var sig := str(wt.keys())
	if sig == _water_sig:
		return
	_water_sig = sig
	for c in water_root.get_children():
		c.queue_free()
	if wt.is_empty():
		return
	var wm := Models.toon(Color("3d78a8"), false, 0.12)
	var rim := Models.toon(Color("8d8a86"))
	var plane := PlaneMesh.new(); plane.size = Vector2(1.02, 1.02)
	var stone := Models.sphere(0.13, 6)
	for k in wt:
		var c := HomeLayout.unkey(k)
		var mi := MeshInstance3D.new(); mi.mesh = plane; mi.material_override = wm
		mi.position = Vector3(c.x + 0.5, 0.05, c.y + 0.5)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		water_root.add_child(mi)
		for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if wt.has(HomeLayout.key(c.x + dv.x, c.y + dv.y)): continue
			for t in [-0.3, 0.05, 0.38]:
				var side: Vector3 = Vector3(-dv.y, 0, dv.x) * t
				var s := MeshInstance3D.new(); s.mesh = stone; s.material_override = rim
				s.position = Vector3(c.x + 0.5 + dv.x * 0.5, 0.07, c.y + 0.5 + dv.y * 0.5) + side
				s.scale = Vector3(1.2, 0.6, 1.0)
				water_root.add_child(s)

## Kin beds you've put down are slept in by kin that don't have one of the six by the house.
func assign_beds() -> void:
	var beds: Array = []
	for e in L()["deco"]:
		if String(e["id"]) == "kin_bed": beds.append(HomeLayout.deco_center(e))
	for k in h.kins:
		if k.get("deco_bed", false):
			k.erase("bed"); k.erase("deco_bed")
	var bi := 0
	for k in h.kins:
		if k.has("bed") or bi >= beds.size():
			continue
		k["bed"] = beds[bi]; k["deco_bed"] = true
		bi += 1

# ------------------------------------------------------------------ kin paths
func refresh_grid() -> void:
	if astar == null:
		return
	var w: World = h.world
	for z in w.h:
		for x in w.w:
			astar.set_point_solid(Vector2i(x, z), w.kind[w.idx(x, z)] != World.T_GROUND)

func _solid_at(x: float, z: float) -> bool:
	var w: World = h.world
	var ix := int(floor(x)); var iz := int(floor(z))
	return not w.inb(ix, iz) or w.kind[w.idx(ix, iz)] != World.T_GROUND

## Nothing solid along the way (with a kin's width either side).
func clear_line(a: Vector2, b: Vector2) -> bool:
	var d := b - a
	var n := int(d.length() / 0.3) + 1
	var side := Vector2(-d.y, d.x).normalized() * 0.28 if d.length() > 0.001 else Vector2.ZERO
	for i in range(1, n + 1):
		var p := a + d * (float(i) / n)
		if _solid_at(p.x, p.y) or _solid_at(p.x + side.x, p.y + side.y) or _solid_at(p.x - side.x, p.y - side.y):
			return false
	return true

## Where a kin should head next to reach its goal: straight there when nothing's in the way,
## otherwise along the tile grid round fences, buildings and ponds.
func steer(k: Dictionary, pos: Vector3, goal: Vector3) -> Vector3:
	if astar == null or goal == Vector3.INF:
		return goal
	var pp := Vector2(pos.x, pos.z); var gp := Vector2(goal.x, goal.z)
	if pp.distance_to(gp) < 0.9:
		return goal
	var key := Vector3i(int(floor(goal.x)), int(floor(goal.z)), ver)
	var p: Dictionary = k.get("path", {})
	if p.get("key", null) != key:
		p = {"key": key, "pts": []}
		k["path"] = p
		if not clear_line(pp, gp):
			var a := Vector2i(int(floor(pos.x)), int(floor(pos.z)))
			var b := Vector2i(int(floor(goal.x)), int(floor(goal.z)))
			if astar.is_in_boundsv(a) and astar.is_in_boundsv(b) and not astar.is_point_solid(a):
				var ids := astar.get_id_path(a, b, true)
				var pts: Array = []
				for i in range(1, ids.size()):
					pts.append(Vector2(ids[i].x + 0.5, ids[i].y + 0.5))
				if not pts.is_empty() and ids[ids.size() - 1] == b:
					pts[pts.size() - 1] = gp
				p["pts"] = pts
	var pts: Array = p["pts"]
	while not pts.is_empty() and pp.distance_to(pts[0]) < 0.45:
		pts.pop_front()
	# cut corners the grid doesn't need: skip ahead while the next-but-one point is in plain sight
	if pts.size() > 1 and clear_line(pp, pts[1]):
		pts.pop_front()
	if pts.is_empty():
		return goal
	return Vector3(pts[0].x, 0, pts[0].y)

# ------------------------------------------------------------------ what may go where
func _isle_ok(i: int) -> bool:
	var isl: int = h.world.island[i]
	return isl == 0 or (isl > 0 and isl < h.world.islands.size() and h._isle_open(String(h.world.islands[isl]["id"])))

func _near_feeder(c: Vector2i) -> bool:
	if h.hecon == null or not h.visit.is_empty():
		return false
	for f in Econ.feeders():
		if absf(float(f.get("x", 0.0)) - (c.x + 0.5)) < 1.6 and absf(float(f.get("z", 0.0)) - (c.y + 0.5)) < 1.6:
			return true
	return false

func _near_plot(c: Vector2i) -> bool:
	for p in h.plots + h.gh_plots:
		if absf((p as Node3D).position.x - (c.x + 0.5)) < 1.3 and absf((p as Node3D).position.z - (c.y + 0.5)) < 1.3:
			return true
	return false

## "" if each tile can take something (self_tag: what's being moved, so its own tiles count as free).
func cell_reason(c: Vector2i, self_tag := "") -> String:
	var w: World = h.world
	if not w.inb(c.x, c.y):
		return "That's off the island"
	var i := w.idx(c.x, c.y)
	if w.kind[i] == World.T_VOID:
		return "That's off the island"
	if w.bridge.has(i):
		return "Not on a bridge"
	if not _isle_ok(i):
		return "Build the bridge to that isle first"
	var o := String(occ.get(i, ""))
	if o != "" and o != self_tag:
		return "Something's already there"
	if wild_t.has(i):
		return "Wild land: clear it first (Island tab, Clear the wild)"
	if w.kind[i] == World.T_BLOCK and not (blocked.has(i) and o == self_tag):
		return "Something's in the way"
	if reserved.has(i) or _near_feeder(c) or _near_plot(c):
		return "That spot is kept clear"
	return ""

## Tiles flooded from the house door, with free_cells opened up and solid_cells shut. Packed bytes, 1 = reached.
func _reach(free_cells: Array, solid_cells: Array) -> PackedByteArray:
	var w: World = h.world
	var n := w.w * w.h
	var open := {}
	for c in free_cells: open[w.idx(c.x, c.y)] = true
	var shut := {}
	for c in solid_cells: shut[w.idx(c.x, c.y)] = true
	var seen := PackedByteArray(); seen.resize(n)
	var dp: Vector3 = h._house_door()
	var s := w.idx(int(floor(dp.x)), int(floor(dp.z)))
	var q: Array = [s]
	seen[s] = 1
	var head := 0
	while head < q.size():
		var i: int = q[head]; head += 1
		var x := i % w.w; var z := i / w.w
		for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = x + dv.x; var nz: int = z + dv.y
			if nx < 0 or nz < 0 or nx >= w.w or nz >= w.h: continue
			var j := nz * w.w + nx
			if seen[j] == 1 or shut.has(j): continue
			if w.kind[j] != World.T_GROUND and not open.has(j): continue
			seen[j] = 1
			q.append(j)
	return seen

## Places the island needs to get to: doors, the portal, pot, stall, rack, ferry, nest, yard, pond,
## graveyard, plots, feeders and bridge signs. A spot counts as reached if any tile next to it is.
func _targets(skip_b := "") -> Array:
	var out: Array = []
	for nm in ["portal", "pot", "stall", "rack", "ferry"]:
		if h.spots.has(nm): out.append(h.spots[nm])
	out.append(h.NEST_AT); out.append(h.YARD_AT); out.append(h.POND_EDGE)
	out.append(HomeEcon.GATE_AT)
	for b in h.lots:
		if b != skip_b: out.append(h.lots[b]["door"] if h.lots[b]["built"] else h.lots[b]["at"])
	for p in h.plots + h.gh_plots: out.append((p as Node3D).position)
	if h.visit.is_empty():
		for f in Econ.feeders(): out.append(Vector3(float(f.get("x", 0.0)), 0, float(f.get("z", 0.0))))
	for k in Data.ISLES:
		var sg: Vector2 = Data.ISLES[k]["sign"]
		out.append(Vector3(sg.x, 0, sg.y))
	for t in h.training_targets(): out.append(t)
	return out

func _hit(seen: PackedByteArray, p: Vector3) -> bool:
	var w: World = h.world
	var cx := int(floor(p.x)); var cz := int(floor(p.z))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if w.inb(cx + dx, cz + dz) and seen[w.idx(cx + dx, cz + dz)] == 1:
				return true
	return false

## True if shutting solid_cells (with free_cells, the thing being moved, taken out) keeps every place
## that could be reached still reachable, and the new door too.
func keeps_paths(free_cells: Array, solid_cells: Array, skip_b := "", door := Vector3.INF) -> bool:
	var ck := "%d|%s|%s" % [ver, skip_b, str(free_cells)]
	var base: PackedByteArray
	if _reach_cache.has(ck):
		base = _reach_cache[ck]
	else:
		base = _reach(free_cells, [])
		_reach_cache[ck] = base
	var after := _reach(free_cells, solid_cells)
	for t in _targets(skip_b):
		if _hit(base, t) and not _hit(after, t):
			return false
	if door != Vector3.INF:
		var w: World = h.world
		var di := w.idx(int(floor(door.x)), int(floor(door.z)))
		if not w.inb(int(floor(door.x)), int(floor(door.z))) or after[di] != 1:
			return false
	return true

## Can held go on these tiles? Sets why.
func fits(item: Dictionary, at: Array) -> bool:
	why = ""
	var tag := ""
	var free_cells: Array = []
	var skip_b := ""
	if item.get("kind", "") == "b":
		skip_b = String(item["id"])
		tag = "b:" + skip_b
		free_cells = HomeLayout.cells_of(HomeLayout.rect_of(skip_b, h._d()))
	elif int(item.get("from", -1)) >= 0:
		tag = "d:%d" % int(item["from"])
		var e := _deco_by_uid(int(item["from"]))
		if not e.is_empty(): free_cells = HomeLayout.deco_cells(e)
	for c in at:
		var r := cell_reason(c, tag)
		if r != "":
			why = r
			return false
	var solid: bool = item.get("kind", "") == "b" and h._has_b(String(item["id"])) or (item.get("kind", "") == "deco" and HomeLayout.blocks(String(item["id"])))
	var door := Vector3.INF
	if item.get("kind", "") == "b":
		door = HomeLayout.door_at(skip_b, at[0].x, at[0].y, int(item["r"]))
		var dt := Vector2i(int(floor(door.x)), int(floor(door.z)))
		if cell_reason(dt, tag) != "" and occ.get(h.world.idx(dt.x, dt.y), "") != tag:
			# the door step has to be open ground (a path is fine)
			var w: World = h.world
			if not w.inb(dt.x, dt.y) or w.kind[w.idx(dt.x, dt.y)] != World.T_GROUND or occ.has(w.idx(dt.x, dt.y)):
				why = "Its door would face something"
				return false
	if solid or door != Vector3.INF:
		if not keeps_paths(free_cells, at if solid else [], skip_b, door):
			why = "That would cut off a door or a path"
			return false
	return true

func _deco_by_uid(u: int) -> Dictionary:
	for e in L()["deco"]:
		if int(e["u"]) == u: return e
	return {}

# ------------------------------------------------------------------ prices
func _can_pay(g: int, s: int) -> bool:
	return int(Save.d["gems"]) >= g and int(Save.d.get("scrap", 0)) >= s

func _pay(g: int, s: int) -> void:
	Save.d["gems"] = int(Save.d["gems"]) - g
	Save.d["scrap"] = int(Save.d.get("scrap", 0)) - s

## What placing n of id costs after using what's in storage: [gems, scrap, from storage].
func cost_of(id: String, n: int) -> Array:
	var inv: Dictionary = L()["inv"]
	var have := mini(n, int(inv.get(id, 0)))
	var p := HomeLayout.price(id, n - have)
	return [p[0], p[1], have]

func price_text(id: String) -> String:
	var c: Dictionary = HomeLayout.CATALOG[id]
	var n := int(L()["inv"].get(id, 0))
	if n > 0:
		return "×%d stored" % n
	var g := int(c.get("gems", 0)); var s := int(c.get("scrap", 0))
	if g == 0 and s == 0:
		return "free"
	var t := "%d gems" % g
	if s > 0: t += " · %d scrap" % s
	if c.has("line") or c.has("brush"): t += " /tile"
	return t

# ------------------------------------------------------------------ undo
func _snap() -> void:
	undo.append({"L": L().duplicate(true), "gems": int(Save.d["gems"]), "scrap": int(Save.d.get("scrap", 0))})
	if undo.size() > 40:
		undo.pop_front()

func undo_last() -> bool:
	if undo.is_empty():
		h._toast("Nothing to undo")
		return false
	_drop_held()
	var s: Dictionary = undo.pop_back()
	var lay: Dictionary = s["L"]
	var paint_changed: bool = str(lay["paths"]) != str(L()["paths"]) or str(lay["water"]) != str(L()["water"]) or lay["theme"] != L()["theme"]
	Save.d["layout"] = lay
	Save.d["gems"] = int(s["gems"]); Save.d["scrap"] = int(s["scrap"])
	apply(paint_changed)
	Save.save_game()
	Sfx.play("whoosh", null, -8.0)
	h._refresh_top()
	_build_bar()
	return true

## Everything back on its lot, every decoration into storage, paths and ponds cleared (undoable).
func reset_layout() -> void:
	_drop_held()
	_snap()
	var lay := L()
	var inv: Dictionary = lay["inv"]
	for e in lay["deco"]:
		inv[String(e["id"])] = int(inv.get(String(e["id"]), 0)) + 1
	lay["deco"] = []
	lay["b"] = {}
	lay["paths"] = {}
	lay["water"] = {}
	apply(true)
	Save.save_game()
	h._toast("Layout reset: decorations are in storage")
	_build_bar()

# ------------------------------------------------------------------ build mode on / off
func can_build() -> bool:
	return h.visit.is_empty() and h.panel_open == "" and not h.chat_open and h.train.is_empty() and not h.building_now and not Overlay.is_open()

func toggle() -> void:
	if active:
		_drop_held()
		active = false
		if is_instance_valid(bar): bar.queue_free()
		bar = null
		h.cam.zoom_to = clampf(h.cam.zoom_to, 0.55, 1.6)
		h.set_build_ui(false)
		Save.save_game()
		return
	if not can_build():
		return
	active = true
	h.prompt_box.visible = false
	h.cam.zoom_to = maxf(h.cam.zoom_to, 1.35)
	h.set_build_ui(true)
	Sfx.play("whoosh", null, -8.0)
	_build_bar()

# ------------------------------------------------------------------ holding things
func take(id: String) -> void:
	_drop_held()
	var c: Dictionary = HomeLayout.CATALOG[id]
	var g := cost_of(id, 1)
	if not c.has("brush") and not c.has("line") and int(g[2]) == 0 and not _can_pay(int(g[0]), int(g[1])):
		h._toast("Not enough %s" % ("gems" if int(Save.d["gems"]) < int(g[0]) else "scrap (salvage spare weapons)"))
		return
	held = {"kind": "deco", "id": id, "r": 0, "from": -1}
	_make_ghost()
	_build_bar()

func take_building(b: String) -> void:
	_drop_held()
	var p := HomeLayout.place_of(b, h._d())
	held = {"kind": "b", "id": b, "r": int(p["r"]), "from": 0}
	_sync_buildings()
	_make_ghost()
	_build_bar()
	Sfx.play("click")

func pick_up_at(c: Vector2i) -> void:
	var w: World = h.world
	if not w.inb(c.x, c.y):
		return
	var o := String(occ.get(w.idx(c.x, c.y), ""))
	if o.begins_with("b:"):
		take_building(o.substr(2))
	elif o.begins_with("f:"):
		var f: Dictionary = h.hecon._feeder(o.substr(2))
		if not f.is_empty(): take_feeder(String(f["kind"]), String(f["id"]))
	elif o.begins_with("d:"):
		var e := _deco_by_uid(int(o.substr(2)))
		if e.is_empty(): return
		held = {"kind": "deco", "id": String(e["id"]), "r": int(e.get("r", 0)), "from": int(e["u"]), "c": e.get("c", "")}
		_sync_deco(); _sync_fences()
		_make_ghost()
		_build_bar()
		Sfx.play("click")

func _drop_held() -> void:
	drag = {}
	if held.is_empty():
		_clear_ghost()
		return
	if held["kind"] == "feeder" and String(held["from"]) != "":
		var n: Node3D = h.hecon.fnodes.get(String(held["from"]))
		if is_instance_valid(n): n.visible = true
	held = {}
	_clear_ghost()
	_sync_buildings(); _sync_deco(); _sync_fences()

func _clear_ghost() -> void:
	if is_instance_valid(ghost): ghost.queue_free()
	ghost = null
	if is_instance_valid(ghost_cells): ghost_cells.queue_free()
	ghost_cells = null
	cells = []
	anchor = Vector2i(-999, -999)

func rotate_held() -> void:
	if held.is_empty():
		return
	if held["kind"] == "feeder":
		held["r"] = (int(held["r"]) + 1) % 4
		if ghost: ghost.rotation.y = int(held["r"]) * PI * 0.5
		return
	var c: Dictionary = HomeLayout.CATALOG.get(String(held["id"]), {})
	if held["kind"] == "deco" and (c.has("line") or c.has("brush")):
		return
	held["r"] = (int(held["r"]) + 1) % 4
	anchor = Vector2i(-999, -999)
	_make_ghost()
	Sfx.play("click", null, -6.0, 0.1, 1.3)

func _make_ghost() -> void:
	_clear_ghost()
	if held.is_empty():
		return
	var id := String(held["id"])
	if held["kind"] == "feeder":
		ghost = EconModels.feeder(id)
		var fl: Node = ghost.get_node_or_null("Fill")
		if fl: fl.queue_free()
	elif held["kind"] == "b":
		ghost = Models.building(id) if h._has_b(id) else Models.lot(HomeLayout.base_size(id).x, HomeLayout.base_size(id).y, Data.BUILDINGS[id]["name"], "")
	elif not HomeLayout.CATALOG[id].has("brush") and not HomeLayout.CATALOG[id].has("line"):
		var e := {"id": id, "x": 0, "z": 0, "r": int(held["r"]), "u": 1, "c": _held_colour(), "sp": String(Save.active_kin().get("species", "zapple"))}
		ghost = make_deco(e)
	if ghost:
		for mi in ghost.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).transparency = 0.35
		for l in _lights_of(ghost): l.queue_free()
		h.add_child(ghost)
		ghost.visible = false
	ghost_cells = Node3D.new()
	h.add_child(ghost_cells)

func _held_colour() -> String:
	if held.has("c") and String(held["c"]) != "":
		return String(held["c"])
	return HomeLayout.COLOURS[colour % HomeLayout.COLOURS.size()]

func set_colour(i: int) -> void:
	colour = i
	if not held.is_empty():
		held["c"] = HomeLayout.COLOURS[i]
		_make_ghost()
	_build_bar()

## The tiles under the mouse for what's held.
func _cells_for(m: Vector2) -> Array:
	var id := String(held["id"])
	if held["kind"] == "feeder":
		return [Vector2i(int(floor(m.x)), int(floor(m.y)))]
	if held["kind"] == "b":
		var sz := HomeLayout.turned(HomeLayout.base_size(id), int(held["r"]))
		var x0 := int(round(m.x - sz.x * 0.5)); var z0 := int(round(m.y - sz.y * 0.5))
		return HomeLayout.cells_of([x0, z0, x0 + sz.x - 1, z0 + sz.y - 1])
	var c: Dictionary = HomeLayout.CATALOG[id]
	var t := Vector2i(int(floor(m.x)), int(floor(m.y)))
	if c.has("line"):
		if drag.is_empty():
			return [t]
		var a: Vector2i = drag["from"]
		var out: Array = []
		if absi(t.x - a.x) >= absi(t.y - a.y):
			for x in range(mini(a.x, t.x), maxi(a.x, t.x) + 1): out.append(Vector2i(x, a.y))
		else:
			for z in range(mini(a.y, t.y), maxi(a.y, t.y) + 1): out.append(Vector2i(a.x, z))
		return out
	if c.has("brush"):
		if drag.is_empty():
			return [t]
		return (drag["tiles"] as Dictionary).keys()
	var sz := HomeLayout.size_of(id, int(held["r"]))
	var x0 := int(round(m.x - sz.x * 0.5)); var z0 := int(round(m.y - sz.y * 0.5))
	return HomeLayout.cells_of([x0, z0, x0 + sz.x - 1, z0 + sz.y - 1])

func _brush_ok(c: Vector2i, mode: String) -> bool:
	var w: World = h.world
	if not w.inb(c.x, c.y): return false
	var i := w.idx(c.x, c.y)
	if mode == "wild":
		return wild_t.has(i)
	if w.kind[i] == World.T_VOID or w.bridge.has(i) or not _isle_ok(i) or reserved.has(i):
		return false
	var o := String(occ.get(i, ""))
	if mode == "wild":
		return wild_t.has(i)
	if mode == "water":
		return cell_reason(c) == ""
	return not o.begins_with("b:") and o != "w"

# ------------------------------------------------------------------ every frame
func tick(d: float) -> void:
	if mesh_t >= 0.0:
		mesh_t -= d
		if mesh_t < 0.0:
			h.world.build_meshes()
	grid_t -= d
	if grid_t <= 0.0:
		grid_t = 2.5
		refresh_grid()      # feeders and graves change the ground too
	if not active:
		return
	if held.is_empty():
		_hover_hint()
		return
	var mp: Vector3 = h.cam.mouse_on_plane(0.0)
	var m := Vector2(mp.x, mp.z) if debug_m == Vector2.INF else debug_m
	var id := String(held["id"])
	var c: Dictionary = HomeLayout.CATALOG.get(id, {})
	if not drag.is_empty() and c.has("brush"):
		# paint every tile the mouse passes over, even quickly
		var t := Vector2i(int(floor(m.x)), int(floor(m.y)))
		var last: Vector2i = drag["last"]
		var steps := maxi(absi(t.x - last.x), absi(t.y - last.y))
		for s in steps + 1:
			var f := float(s) / maxf(1.0, steps)
			var q := Vector2i(int(round(lerpf(last.x, t.x, f))), int(round(lerpf(last.y, t.y, f))))
			if _brush_ok(q, String(c["brush"])): drag["tiles"][q] = true
		drag["last"] = t
	var at := _cells_for(m)
	var key := Vector2i(at[0].x, at[0].y) if not at.is_empty() else Vector2i.ZERO
	var sig := str(at) + str(held.get("r", 0))
	if sig != String(ghost_cells.get_meta("sig", "")) if is_instance_valid(ghost_cells) else true:
		cells = at
		_check_cells()
		_draw_cells()
		if is_instance_valid(ghost_cells): ghost_cells.set_meta("sig", sig)
	anchor = key
	if is_instance_valid(ghost) and not cells.is_empty():
		var sz := Vector2(cells[cells.size() - 1].x - cells[0].x + 1, cells[cells.size() - 1].y - cells[0].y + 1)
		ghost.position = Vector3(cells[0].x + sz.x * 0.5, 0.04 + sin(Time.get_ticks_msec() / 220.0) * 0.03, cells[0].y + sz.y * 0.5)
		ghost.rotation.y = int(held["r"]) * PI * 0.5
		ghost.visible = true
	_set_hint()

var _bad := {}       # Vector2i -> true: the ghost's tiles that can't take it
func _check_cells() -> void:
	_bad.clear()
	var id := String(held["id"])
	var c: Dictionary = HomeLayout.CATALOG.get(id, {})
	if held["kind"] == "deco" and c.has("brush"):
		ghost_ok = false
		var good: Array = []
		for t in cells:
			if _brush_ok(t, String(c["brush"])): good.append(t)
			else: _bad[t] = true
		ghost_ok = not good.is_empty()
		why = "" if ghost_ok else "Can't paint here"
		if c["brush"] == "wild" and not ghost_ok: why = "Nothing wild to clear here"
		if ghost_ok and c["brush"] == "water" and not keeps_paths([], good):
			ghost_ok = false; why = "That would cut off a door or a path"
		return
	if held["kind"] == "deco" and c.has("line"):
		var good: Array = []
		for t in cells:
			if cell_reason(t) == "": good.append(t)
			else: _bad[t] = true
		ghost_ok = not good.is_empty()
		why = "" if ghost_ok else cell_reason(cells[0])
		if ghost_ok and not keeps_paths([], good):
			ghost_ok = false; why = "That would cut off a door or a path"
		return
	if held["kind"] == "feeder":
		ghost_ok = feeder_fits(cells[0], String(held["from"]))
		return
	ghost_ok = fits(held, cells)

## A feeder: open ground (not right by another feeder), room round it for kin to eat, no path cut.
func feeder_fits(t: Vector2i, from: String) -> bool:
	why = ""
	var w: World = h.world
	var tag := "f:" + from if from != "" else ""
	if not w.inb(t.x, t.y): why = "That's off the island"; return false
	var i := w.idx(t.x, t.y)
	var o := String(occ.get(i, ""))
	if w.kind[i] == World.T_VOID: why = "That's off the island"; return false
	if w.bridge.has(i): why = "Not on a bridge"; return false
	if not _isle_ok(i): why = "Build the bridge to that isle first"; return false
	if o != "" and o != tag: why = "Something's already there"; return false
	if w.kind[i] != World.T_GROUND and o != tag: why = "Something's in the way"; return false
	if reserved.has(i) or _near_plot(t): why = "That spot is kept clear"; return false
	var p := Vector3(t.x + 0.5, 0, t.y + 0.5)
	for f in Econ.feeders():
		if String(f["id"]) == from: continue
		if Vector2(p.x - float(f["x"]), p.z - float(f["z"])).length() < 2.8: why = "Too close to another feeder"; return false
	var free := 0
	for k in 6:
		var a := float(k) * TAU / 6.0
		var q := p + Vector3(cos(a) * HomeEcon.SEAT_R, 0, sin(a) * HomeEcon.SEAT_R)
		var qi := w.idx(int(floor(q.x)), int(floor(q.z)))
		if not w.is_void(q.x, q.z) and (w.occupy(q.x, q.z, 0.3, 0.0, true) == 0.0 or String(occ.get(qi, "")) == tag) and qi != i: free += 1
	if free < 3: why = "Kin need room round it to eat"; return false
	var fc: Array = []
	if from != "":
		var f0: Dictionary = h.hecon._feeder(from)
		if not f0.is_empty(): fc = [Vector2i(int(floor(float(f0["x"]))), int(floor(float(f0["z"]))))]
	if not keeps_paths(fc, [t]):
		why = "That would cut off a door or a path"; return false
	return true

## Holding a feeder to set down: a new one from storage (from = "") or one that's out (its id).
func take_feeder(kind: String, from := "") -> void:
	if not active:
		h._close_panel()
		if not can_build():
			return
		active = true
		h.prompt_box.visible = false
		h.cam.zoom_to = maxf(h.cam.zoom_to, 1.35)
		h.set_build_ui(true)
	_drop_held()
	if from == "" and int(Save.d.get("feeder_inv", {}).get(kind, 0)) <= 0:
		h._toast("No %s in storage" % Econ.FEEDERS[kind]["name"])
		return
	held = {"kind": "feeder", "id": kind, "r": 0, "from": from}
	if from != "":
		var n: Node3D = h.hecon.fnodes.get(from)
		if is_instance_valid(n): n.visible = false
	cat = "Buildings"
	_make_ghost()
	_build_bar()
	Sfx.play("click")

func _place_feeder() -> bool:
	var kind := String(held["id"]); var from := String(held["from"])
	var t: Vector2i = cells[0]
	var p := Vector3(t.x + 0.5, 0, t.y + 0.5)
	var he: HomeEcon = h.hecon
	_snap()
	var f: Dictionary
	if from != "":
		f = he._feeder(from)
		he._block(he._fpos(f), false)
		f["x"] = p.x; f["z"] = p.z; f["rot"] = int(held["r"]) * PI * 0.5
		var n: Node3D = he.fnodes.get(from)
		if is_instance_valid(n):
			n.position = p; n.rotation.y = float(f["rot"]); n.visible = true
		he._block(p, true)
		for o in h.kins:
			if o.has("eat") and String(o["eat"]["fid"]) == from: o.erase("eat")
	else:
		var inv: Dictionary = Save.d["feeder_inv"]
		inv[kind] = int(inv.get(kind, 0)) - 1
		if int(inv[kind]) <= 0: inv.erase(kind)
		var k := 1
		while not he._feeder("f%d" % k).is_empty(): k += 1
		f = {"id": "f%d" % k, "kind": kind, "x": p.x, "z": p.z, "rot": int(held["r"]) * PI * 0.5, "food": [], "auto": true}
		Save.d["feeders"].append(f)
		he._spawn_feeder(f)
		Econ.auto_refill(f)
		he.refresh_feeder(f)
	held = {}
	_clear_ghost()
	apply(false)
	_done(p, "%s set down" % Econ.fdef(f)["name"])
	return true

func _draw_cells() -> void:
	if not is_instance_valid(ghost_cells):
		return
	for ch in ghost_cells.get_children():
		ch.queue_free()
	var pm := PlaneMesh.new(); pm.size = Vector2(0.92, 0.92)
	var good := StandardMaterial3D.new(); good.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; good.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	good.albedo_color = Color(0.45, 1.0, 0.55, 0.42) if ghost_ok else Color(1.0, 0.4, 0.35, 0.5)
	var bad := good.duplicate(); bad.albedo_color = Color(1.0, 0.4, 0.35, 0.5)
	var id := String(held["id"])
	for t in cells:
		var mi := MeshInstance3D.new(); mi.mesh = pm
		mi.material_override = bad if _bad.has(t) else good
		mi.position = Vector3(t.x + 0.5, 0.06, t.y + 0.5)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ghost_cells.add_child(mi)
		if held["kind"] == "deco" and HomeLayout.CATALOG[id].has("line") and not _bad.has(t):
			var post := MeshInstance3D.new(); post.mesh = Models.box(0.14, 0.7, 0.14)
			post.material_override = good; post.position = Vector3(t.x + 0.5, 0.35, t.y + 0.5)
			ghost_cells.add_child(post)
	if held["kind"] == "b" and not cells.is_empty():
		# where the door ends up
		var door := HomeLayout.door_at(id, cells[0].x, cells[0].y, int(held["r"]))
		var mi := MeshInstance3D.new(); var arrow := PrismMesh.new(); arrow.size = Vector3(0.5, 0.5, 0.06)
		mi.mesh = arrow; mi.material_override = good
		mi.position = Vector3(door.x, 0.08, door.z)
		mi.rotation = Vector3(-PI / 2, int(held["r"]) * PI * 0.5 + PI, 0)
		ghost_cells.add_child(mi)

func _hover_hint() -> void:
	var mp: Vector3 = h.cam.mouse_on_plane(0.0)
	var c := Vector2i(int(floor(mp.x)), int(floor(mp.z)))
	var w: World = h.world
	var t := "Pick something from the bar, or click anything you've placed (or a building) to move it."
	if w.inb(c.x, c.y):
		var o := String(occ.get(w.idx(c.x, c.y), ""))
		if o.begins_with("b:"): t = "Click to pick up the %s and move it" % Data.BUILDINGS[o.substr(2)]["name"]
		elif o.begins_with("d:"):
			var e := _deco_by_uid(int(o.substr(2)))
			if not e.is_empty(): t = "Click to pick up the %s" % HomeLayout.CATALOG[String(e["id"])]["name"].to_lower()
		elif o.begins_with("f:"): t = "Click to pick up this feeder and move it"
		elif o == "w": t = "Pond water: paint over it with Grass (clear) to fill it in"
	if hint_lbl and hint_lbl.text != t: hint_lbl.text = t

func _set_hint() -> void:
	if hint_lbl == null:
		return
	var id := String(held["id"])
	var nm: String = Data.BUILDINGS[id]["name"] if held["kind"] == "b" else (Econ.FEEDERS[id]["name"] if held["kind"] == "feeder" else HomeLayout.CATALOG[id]["name"])
	var c: Dictionary = HomeLayout.CATALOG.get(id, {})
	var t := ""
	if not ghost_ok:
		t = "%s: %s" % [nm, why]
	elif c.has("line"):
		t = "%s: click and drag to lay a line  ·  %d tile%s" % [nm, cells.size() - _bad.size(), "" if cells.size() - _bad.size() == 1 else "s"]
	elif c.has("brush"):
		t = "%s: click and drag to paint" % nm
	else:
		t = "%s: click to place it here" % nm
	if hint_lbl.text != t: hint_lbl.text = t
	hint_lbl.add_theme_color_override("font_color", UI.INK if ghost_ok else Color("ffb0a0"))

# ------------------------------------------------------------------ input
## Build mode's own keys and clicks. True if it used the event.
func input(event: InputEvent) -> bool:
	if not active:
		return false
	if event.is_action_pressed("menu"):
		if not held.is_empty(): _drop_held(); _build_bar()
		else: toggle()
		return true
	if event.is_action_pressed("build"):
		toggle()
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		var ke := event as InputEventKey
		if ke.physical_keycode == KEY_Z and (ke.ctrl_pressed or ke.meta_pressed):
			undo_last()
			return true
		if ke.physical_keycode in [KEY_X, KEY_DELETE, KEY_BACKSPACE]:
			store_held()
			return true
	if event.is_action_pressed("rotate"):
		rotate_held()
		return true
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if mb.pressed:
				if not held.is_empty() and not HomeLayout.CATALOG.get(String(held["id"]), {}).has("brush") and not HomeLayout.CATALOG.get(String(held["id"]), {}).has("line"):
					rotate_held()
				else:
					h.cam.zoom_to = clampf(h.cam.zoom_to + (-0.1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 0.1), 0.6, 2.4)
			return true
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if held.is_empty(): pass
			elif drag.is_empty(): rotate_held()
			else: drag = {}
			return true
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var mp: Vector3 = h.cam.mouse_on_plane(0.0)
			var t := Vector2i(int(floor(mp.x)), int(floor(mp.z)))
			if mb.pressed:
				if held.is_empty():
					pick_up_at(t)
				else:
					var c: Dictionary = HomeLayout.CATALOG.get(String(held["id"]), {})
					if held["kind"] == "deco" and (c.has("line") or c.has("brush")):
						drag = {"from": t, "tiles": {}, "last": t}
						if c.has("brush") and _brush_ok(t, String(c["brush"])): drag["tiles"][t] = true
					else:
						place_held()
			elif not drag.is_empty():
				tick(0.0)
				place_held()
				drag = {}
			return true
	return false

# ------------------------------------------------------------------ committing
func place_held() -> bool:
	if held.is_empty() or cells.is_empty():
		return false
	if not ghost_ok:
		Sfx.play("click", null, -6.0, 0.0, 0.6)
		h._toast(why if why != "" else "Can't put that there")
		return false
	var id := String(held["id"])
	var lay := L()
	if held["kind"] == "feeder":
		return _place_feeder()
	if held["kind"] == "b":
		_snap()
		lay["b"][id] = {"x": cells[0].x, "z": cells[0].y, "r": int(held["r"])}
		held = {}
		_clear_ghost()
		apply(false)
		_done(HomeLayout.rect_center(HomeLayout.rect_of(id, h._d())), "%s moved" % Data.BUILDINGS[id]["name"])
		return true
	var c: Dictionary = HomeLayout.CATALOG[id]
	if c.has("brush"):
		return _paint(id, String(c["brush"]))
	var at: Array = cells.filter(func(t): return not _bad.has(t)) if c.has("line") else [cells[0]]
	var from := int(held.get("from", -1))
	var n := at.size() if from < 0 else 0
	var cost := cost_of(id, n)
	if not _can_pay(int(cost[0]), int(cost[1])):
		h._toast("Not enough gems" if int(Save.d["gems"]) < int(cost[0]) else "Not enough scrap (salvage spare weapons)")
		return false
	_snap()
	if from >= 0:
		var e := _deco_by_uid(from)
		e["x"] = at[0].x; e["z"] = at[0].y; e["r"] = int(held["r"]); e.erase("px"); e.erase("pz")
		if held.has("c") and String(held["c"]) != "": e["c"] = String(held["c"])
		held = {}
		_clear_ghost()
	else:
		lay["inv"][id] = int(lay["inv"].get(id, 0)) - int(cost[2])
		if int(lay["inv"][id]) <= 0: lay["inv"].erase(id)
		_pay(int(cost[0]), int(cost[1]))
		for t in at:
			var e := {"u": HomeLayout._next_uid(lay), "id": id, "x": t.x, "z": t.y, "r": int(held["r"])}
			if c.get("colour", false) or id == "banner": e["c"] = _held_colour()
			if id == "kin_statue": e["sp"] = String(Save.active_kin().get("species", "zapple"))
			lay["deco"].append(e)
		anchor = Vector2i(-999, -999)
		if is_instance_valid(ghost_cells): ghost_cells.set_meta("sig", "")
	apply(false)
	_done(Vector3(at[0].x + 0.5, 0, at[0].y + 0.5), "")
	return true

func _paint(id: String, mode: String) -> bool:
	var lay := L()
	var at: Array = cells.filter(func(t): return not _bad.has(t))
	if at.is_empty():
		return false
	var cost := HomeLayout.price(id, at.size())
	if not _can_pay(int(cost[0]), int(cost[1])):
		h._toast("Not enough gems")
		return false
	_snap()
	_pay(int(cost[0]), int(cost[1]))
	var w: World = h.world
	for t in at:
		var k := HomeLayout.key(t.x, t.y)
		match mode:
			"path": lay["paths"][k] = id
			"water": lay["water"][k] = 1
			"wild": clear_wild(t)
			"clear":
				lay["water"].erase(k)
				if base_paint.has(w.idx(t.x, t.y)): lay["paths"][k] = "none"
				else: lay["paths"].erase(k)
	drag = {}
	if is_instance_valid(ghost_cells): ghost_cells.set_meta("sig", "")
	apply(true)
	_done(Vector3(at[0].x + 0.5, 0, at[0].y + 0.5), "")
	return true

func _done(at: Vector3, msg: String) -> void:
	Sfx.play("build", null, -6.0, 0.1)
	if h.fx: h.fx.dust(at, 8)
	Save.save_game()
	h._refresh_top()
	if msg != "": h._toast(msg)
	_build_bar()

## X: the held decoration goes into storage (or a new one is just put back).
func store_held() -> void:
	if held.is_empty():
		return
	if held["kind"] == "b":
		h._toast("Buildings can be moved, not put away")
		return
	if held["kind"] == "feeder":
		var fid := String(held["from"])
		if fid != "":
			held = {}
			_clear_ghost()
			h.hecon.store_feeder(h.hecon._feeder(fid))
			apply(false)
			h._toast("Feeder put in storage (its food went back in the pantry)")
		else:
			_drop_held()
		_build_bar()
		return
	var from := int(held.get("from", -1))
	if from >= 0:
		_snap()
		var lay := L()
		var e := _deco_by_uid(from)
		lay["deco"].erase(e)
		lay["inv"][String(e["id"])] = int(lay["inv"].get(String(e["id"]), 0)) + 1
		held = {}
		_clear_ghost()
		apply(false)
		Sfx.play("pickup", null, -6.0)
		h._toast("%s put in storage" % HomeLayout.CATALOG[String(e["id"])]["name"])
		Save.save_game()
	else:
		_drop_held()
	_build_bar()

# ------------------------------------------------------------------ the island: themes and growing
func set_theme(t: String) -> void:
	var lay := L()
	var td: Dictionary = HomeLayout.THEMES[t]
	if not (lay["themes"] as Array).has(t):
		if int(Save.d["gems"]) < int(td["gems"]):
			h._toast("You need %d gems for the %s theme" % [int(td["gems"]), td["name"]])
			return
		_snap()
		Save.d["gems"] = int(Save.d["gems"]) - int(td["gems"])
		lay["themes"].append(t)
	else:
		_snap()
	lay["theme"] = t
	apply(true)
	Save.save_game()
	h._refresh_top()
	Sfx.play("unlock", null, -6.0)
	_build_bar()

func open_expand() -> void:
	var lay := L()
	var lv := int(lay["grow"])
	var v: VBoxContainer = h._new_panel("Grow your island", 520)
	if lv >= HomeLayout.EXPAND.size():
		v.add_child(UI.label("Your island is as big as it gets. There's room out on the other isles.", 16))
		return
	var gain := HomeLayout.expand_gain(lv, _seed())
	var c: Array = HomeLayout.EXPAND[lv]
	v.add_child(UI.label("The island's edge grows out to the east and south: %d more tiles of open meadow to build on. (Step %d of %d.)" % [gain, lv + 1, HomeLayout.EXPAND.size()], 16))
	var have := "You have %d gems and %d scrap." % [int(Save.d["gems"]), int(Save.d.get("scrap", 0))]
	v.add_child(UI.label("Costs %d gems and %d scrap. %s" % [int(c[0]), int(c[1]), have], 15, UI.GOLD if _can_pay(int(c[0]), int(c[1])) else UI.BAD))
	var btn := UI.primary("Expand  +%d tiles" % gain, func(): expand(), 240)
	btn.disabled = not _can_pay(int(c[0]), int(c[1]))
	v.add_child(btn)

func expand() -> bool:
	var lay := L()
	var lv := int(lay["grow"])
	if lv >= HomeLayout.EXPAND.size():
		return false
	var c: Array = HomeLayout.EXPAND[lv]
	if not _can_pay(int(c[0]), int(c[1])):
		return false
	var gain := HomeLayout.expand_gain(lv, _seed())
	_pay(int(c[0]), int(c[1]))
	lay["grow"] = lv + 1
	Save.save_game()
	undo.clear()
	pending_toast = "The island grew: +%d tiles" % gain
	Sfx.play("unlock")
	if h.is_inside_tree() and not "--home-build-check" in OS.get_cmdline_user_args():
		Game.goto("home", {})
	return true

# ------------------------------------------------------------------ the bar
func _build_bar() -> void:
	if not active:
		return
	if is_instance_valid(bar): bar.queue_free()
	var vpw: float = h.get_viewport().get_visible_rect().size.x
	var card := UI.card(Color(0.06, 0.07, 0.1, 0.93), 10, 14)
	UI.set_card_border(card, Color(1, 1, 1, 0.08), 1)
	card.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	card.offset_left = 16; card.offset_right = -16; card.offset_top = -196; card.offset_bottom = -12
	var col := UI.vbox(7); card.add_child(col)
	# the tabs, then undo / reset / done
	var tabs := UI.hbox(5)
	col.add_child(tabs)
	for ct in HomeLayout.CATS:
		var cc: String = ct
		var tb := UI.choice(ct, ct == cat, func(): cat = cc; page = 0; _build_bar())
		tb.add_theme_font_size_override("font_size", 14)
		tabs.add_child(tb)
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL; tabs.add_child(sp)
	var held_c: bool = not held.is_empty() and held["kind"] == "deco" and (HomeLayout.CATALOG[String(held["id"])].get("colour", false))
	if held_c or (held.is_empty() and cat in ["Furniture", "Statues"]):
		for i in HomeLayout.COLOURS.size():
			var ci := i
			var sw := Button.new()
			sw.custom_minimum_size = Vector2(26, 26)
			var sb := StyleBoxFlat.new(); sb.bg_color = Color(String(HomeLayout.COLOURS[i])); sb.set_corner_radius_all(13)
			if i == colour: sb.border_width_bottom = 3; sb.border_width_top = 3; sb.border_width_left = 3; sb.border_width_right = 3; sb.border_color = UI.INK
			for st in ["normal", "hover", "pressed"]: sw.add_theme_stylebox_override(st, sb)
			sw.pressed.connect(func(): Sfx.play("click"); set_colour(ci))
			sw.tooltip_text = "Colour for banners, rugs and kin beds"
			tabs.add_child(sw)
	var ub := UI.button("Undo", func(): undo_last(), 76); ub.disabled = undo.is_empty(); tabs.add_child(ub)
	tabs.add_child(UI.primary("Done", func(): toggle(), 80))
	# the items
	var line := UI.hbox(8)
	line.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(line)
	var items := _tab_items()
	var per := maxi(2, int((vpw - 32.0 - 28.0 - 2.0 * 52.0) / 146.0))
	var pages := maxi(1, int(ceil(items.size() / float(per))))
	page = clampi(page, 0, pages - 1)
	var prev := UI.button("‹", func(): page -= 1; _build_bar(), 44)
	prev.custom_minimum_size.y = 80; prev.disabled = page == 0
	line.add_child(prev)
	var row := UI.hbox(8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(row)
	for it in items.slice(page * per, page * per + per):
		var b := UI.button(String(it["t"]), it["cb"], 138)
		b.custom_minimum_size.y = 80
		b.add_theme_font_size_override("font_size", 14)
		if it.get("on", false): b.theme_type_variation = "Chosen"
		b.disabled = it.get("off", false)
		if it.has("tip"): b.tooltip_text = String(it["tip"])
		row.add_child(b)
	var next := UI.button("›", func(): page += 1; _build_bar(), 44)
	next.custom_minimum_size.y = 80; next.disabled = page >= pages - 1
	line.add_child(next)
	# what to do, and the keys
	var foot := UI.hbox(16)
	col.add_child(foot)
	hint_lbl = UI.label("", 14, UI.INK)
	hint_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	hint_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_lbl.clip_text = true
	foot.add_child(hint_lbl)
	foot.add_child(UI.key_hints([["LMB", "place / pick up"], [Settings.key_cap("rotate"), "turn"], ["X", "store"], ["Ctrl Z", "undo"], ["Esc", "cancel"], [Settings.key_cap("build"), "done"]], 12, Color(1, 1, 1, 0.75)))
	h.root_ui.add_child(card)
	bar = card
	if held.is_empty(): _hover_hint()
	else: _set_hint()

func _tab_items() -> Array:
	var out: Array = []
	var lay := L()
	match cat:
		"Buildings":
			if h.visit.is_empty():
				for kind in Econ.FEEDER_ORDER:
					var nf := int(Save.d.get("feeder_inv", {}).get(kind, 0))
					if nf <= 0: continue
					var kk: String = kind
					out.append({"t": "%s\n×%d to set down" % [Econ.FEEDERS[kind]["name"], nf], "cb": func(): take_feeder(kk), "on": held.get("kind", "") == "feeder" and String(held.get("from", "x")) == "" and String(held.get("id", "")) == kind})
			for b in h.lots:
				var bb: String = b
				var nm: String = Data.BUILDINGS[b]["name"]
				var isl: int = h.world.island_of(h.lots[b]["at"].x, h.lots[b]["at"].z)
				var open: bool = isl >= 0 and _isle_ok(h.world.idx(int(floor(h.lots[b]["at"].x)), int(floor(h.lots[b]["at"].z))))
				out.append({"t": "%s\n%s" % [nm, "Move" if h._has_b(b) else "Move the lot"], "cb": func(): take_building(bb), "off": not open,
					"on": held.get("kind", "") == "b" and String(held.get("id", "")) == b, "tip": "" if open else "Build the bridge to its isle first"})
		"Island":
			for t in HomeLayout.THEMES:
				var tt: String = t
				var td: Dictionary = HomeLayout.THEMES[t]
				var own: bool = (lay["themes"] as Array).has(t)
				var now: bool = String(lay["theme"]) == t
				out.append({"t": "%s theme\n%s" % [td["name"], "In use" if now else ("Owned" if own else "%d gems" % int(td["gems"]))],
					"cb": func(): set_theme(tt), "on": now, "off": not own and int(Save.d["gems"]) < int(td["gems"])})
			var lv := int(lay["grow"])
			if lv < HomeLayout.EXPAND.size():
				var c: Array = HomeLayout.EXPAND[lv]
				out.append({"t": "Expand island\n%d gems · %d scrap" % [int(c[0]), int(c[1])], "cb": func(): open_expand(), "tip": "Grow the island's edge (step %d of %d)" % [lv + 1, HomeLayout.EXPAND.size()]})
			else:
				out.append({"t": "Expand island\nfull size", "cb": func(): pass, "off": true})
			if _seed() != 0:
				out.append({"t": "Clear the wild\n%s" % price_text("clear_wild"), "cb": func(): take("clear_wild"), "tip": "Cut back trees and boulders out in the wild meadow, tile by tile",
					"on": held.get("id", "") == "clear_wild"})
			out.append({"t": "Reset layout\nundoable", "cb": func(): reset_layout(), "tip": "Buildings back on their lots, decorations into storage, paths and ponds cleared"})
		_:
			for id in HomeLayout.CATALOG:
				var c: Dictionary = HomeLayout.CATALOG[id]
				if String(c["cat"]) != cat: continue
				var iid: String = id
				var pc := cost_of(id, 1)
				out.append({"t": "%s\n%s" % [c["name"], price_text(id)], "cb": func(): take(iid),
					"on": held.get("kind", "") == "deco" and String(held.get("id", "")) == id and int(held.get("from", -1)) < 0,
					"off": int(pc[2]) == 0 and not _can_pay(int(pc[0]), int(pc[1]))})
	return out

# ------------------------------------------------------------------ "Make it home": the first look round
## A new procedural home starts with a choice of where the first things go: the feeder, the
## Workshop's lot and the Kin Cottage's lot, three suggested spots each (marked on the ground).
## The wild is cut back round whatever you pick; the rest of the meadow stays wild to clear later.
var make := {}                          # item -> [options]; options are Vector2i (feeder) or {x, z, r}
var make_pick := {}
var make_marks: Array = []
const MAKE_ITEMS := [["feeder", "First feeder", "f2c84a"], ["workshop", "Workshop lot", "5ab0f0"], ["cottage", "Kin Cottage lot", "ff9ac8"]]

func needs_making() -> bool:
	return h.visit.is_empty() and not bool(L().get("made", true))

func suggest() -> Dictionary:
	var out := {}
	var w: World = h.world
	var home_p: Vector3 = h._house_door()
	# the feeder: open spots near the pot, spread out
	var fs: Array = []
	var f1: Dictionary = Econ.feeders()[0] if not Econ.feeders().is_empty() else {}
	for rr in range(2, 12):
		for k in 24:
			if fs.size() >= 3: break
			var a := float(k) / 24.0 * TAU
			var t := Vector2i(int(floor(Econ.FEEDER_START.x + cos(a) * rr)), int(floor(Econ.FEEDER_START.z + sin(a) * rr)))
			if fs.any(func(o): return Vector2(o).distance_to(Vector2(t)) < 4.0): continue
			if feeder_fits(t, String(f1.get("id", ""))): fs.append(t)
	out["feeder"] = fs
	for b in ["workshop", "cottage"]:
		var opts: Array = []
		var p0 := HomeLayout.place_of(b, h._d())
		var item := {"kind": "b", "id": b, "r": 0, "from": 0}
		if fits(item, HomeLayout.cells_of(HomeLayout.rect_of(b, h._d()))): opts.append(p0)
		var cands: Array = []
		for z in range(4, w.h - 4):
			for x in range(4, w.w - 4):
				if w.island[w.idx(x, z)] != 0: continue
				var dd := Vector2(x - home_p.x, z - home_p.z).length()
				if dd < 6.0 or dd > 24.0: continue
				cands.append([dd + float((x * 7 + z * 13) % 5), x, z])
		cands.sort_custom(func(a, b2): return a[0] < b2[0])
		for cd in cands:
			if opts.size() >= 3: break
			var x: int = cd[1]; var z: int = cd[2]
			var r := 0 if (x + z) % 3 != 0 else 1
			item["r"] = r
			var rc := HomeLayout.rect_at(b, x, z, r)
			if opts.any(func(o): return Vector2(o["x"], o["z"]).distance_to(Vector2(x, z)) < 7.0): continue
			if out.has("workshop") and b == "cottage" and (out["workshop"] as Array).any(func(o): return Vector2(o["x"], o["z"]).distance_to(Vector2(x, z)) < 5.0): continue
			if fits(item, HomeLayout.cells_of(rc)): opts.append({"x": x, "z": z, "r": r})
		out[b] = opts
	return out

func open_make_home() -> void:
	if make.is_empty():
		make = suggest()
		for it in MAKE_ITEMS: make_pick[it[0]] = 0
	_mark_make()
	var v: VBoxContainer = h._new_panel("Make it home", 560)
	v.add_child(UI.label("This bit of wild sky-meadow is yours. Pick where your first things go: the marks on the ground show the choices. The wild gets cut back round them; the rest you can clear and build on later.", 15))
	for it in MAKE_ITEMS:
		var key: String = it[0]
		var opts: Array = make.get(key, [])
		if opts.is_empty(): continue
		var row := UI.hbox(8)
		var l := UI.label(String(it[1]), 16, Color(String(it[2])), UI.semi)
		l.custom_minimum_size.x = 170
		row.add_child(l)
		for i in opts.size():
			var ii := i
			row.add_child(UI.choice("Spot %s" % "ABC"[i], int(make_pick.get(key, 0)) == i, func(): make_pick[key] = ii; open_make_home(), 96))
		v.add_child(row)
	var go := UI.hbox(10)
	go.add_child(UI.primary("Use suggested layout", func(): use_suggested(), 230))
	go.add_child(UI.button("Done", func(): finish_make_home(), 120))
	v.add_child(go)

func _mark_make() -> void:
	for m in make_marks:
		if is_instance_valid(m): m.queue_free()
	make_marks.clear()
	for it in MAKE_ITEMS:
		var key: String = it[0]
		var opts: Array = make.get(key, [])
		for i in opts.size():
			var at: Vector3
			if key == "feeder": at = Vector3(opts[i].x + 0.5, 0, opts[i].y + 0.5)
			else: at = HomeLayout.rect_center(HomeLayout.rect_at(key, int(opts[i]["x"]), int(opts[i]["z"]), int(opts[i]["r"])))
			var chosen := int(make_pick.get(key, 0)) == i
			var n := Node3D.new(); n.position = at
			var ring := MeshInstance3D.new(); var tm := TorusMesh.new(); tm.inner_radius = 0.8 if key == "feeder" else 1.5; tm.outer_radius = tm.inner_radius + 0.14
			ring.mesh = tm; ring.material_override = Models.glow_mat(Color(Color(String(it[2])), 0.9 if chosen else 0.35)); ring.position.y = 0.06
			n.add_child(ring)
			var l := Label3D.new(); l.text = "%s %s" % [String(it[1]).split(" ")[0] if key != "feeder" else "Feeder", "ABC"[i]]
			l.font = UI.big; l.font_size = 44 if chosen else 34; l.pixel_size = 0.01; l.outline_size = 10
			l.modulate = Color(String(it[2])) if chosen else Color(1, 1, 1, 0.6); l.billboard = BaseMaterial3D.BILLBOARD_ENABLED; l.position.y = 1.6
			n.add_child(l)
			h.add_child(n)
			make_marks.append(n)

func use_suggested() -> void:
	if make.is_empty():
		make = suggest()
	for it in MAKE_ITEMS: make_pick[it[0]] = 0
	finish_make_home()

func finish_make_home() -> void:
	if make.is_empty():
		make = suggest()
	var lay := L()
	var carve: Array = [h._house_door()]
	var fo: Array = make.get("feeder", [])
	if not fo.is_empty() and not Econ.feeders().is_empty():
		var t: Vector2i = fo[clampi(int(make_pick.get("feeder", 0)), 0, fo.size() - 1)]
		var f: Dictionary = Econ.feeders()[0]
		h.hecon._block(h.hecon._fpos(f), false)
		f["x"] = t.x + 0.5; f["z"] = t.y + 0.5
		var n: Node3D = h.hecon.fnodes.get(String(f["id"]))
		if is_instance_valid(n): n.position = h.hecon._fpos(f)
		h.hecon._block(h.hecon._fpos(f), true)
		carve.append(h.hecon._fpos(f))
	for b in ["workshop", "cottage"]:
		var opts: Array = make.get(b, [])
		if opts.is_empty(): continue
		var o: Dictionary = opts[clampi(int(make_pick.get(b, 0)), 0, opts.size() - 1)]
		lay["b"][b] = {"x": int(o["x"]), "z": int(o["z"]), "r": int(o["r"])}
		carve.append(HomeLayout.rect_center(HomeLayout.rect_at(b, int(o["x"]), int(o["z"]), int(o["r"]))))
	# cut the wild back round your choices
	var w: World = h.world
	for i in wild_t.keys():
		var p := Vector3(i % w.w + 0.5, 0, i / w.w + 0.5)
		if carve.any(func(c): return Vector2(c.x - p.x, c.z - p.z).length() < 4.5):
			clear_wild(Vector2i(i % w.w, i / w.w))
	lay["made"] = true
	for m in make_marks:
		if is_instance_valid(m): m.queue_free()
	make_marks.clear()
	apply(true)
	Save.save_game()
	h._close_panel()
	if not Save.d["tutorial"].get("home", false) and h.is_inside_tree():
		h._open_welcome.call_deferred()
