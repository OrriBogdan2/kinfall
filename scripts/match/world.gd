class_name World
extends Node3D
## The floating islands: a tile grid with ground levels, blockers and the abyss in between.
## Generates the layout from a seed, builds the meshes, and answers movement and sight queries.

const VOID := -1.0e9
const LEVEL := 0.8      # height of one terrace
const STEP := 0.32      # how high you can walk up without jumping
const BLOCK_H := 3.0

enum { T_VOID, T_GROUND, T_BLOCK }

var w := 64
var h := 64
var kind := PackedByteArray()
var level := PackedByteArray()
var island := PackedInt32Array()
var depth := PackedFloat32Array()
var rng := RandomNumberGenerator.new()
var islands: Array = []      # {cx, cz, r, base, cells:Array[Vector2i]}
var pads: Array = []         # {pos:Vector3, land:Vector3, from:int, to:int, cd:float, node}
var spawns: Array = []       # Vector3 candidates at island edges
var portal_spots: Array = []
var chest_spots: Array = []
var camp_spots: Array = []
var wild_spots: Array = []
var no_deco := {}
var paint := {}          # tile index -> colour for paths and soil, blended at the corners
var clouds: Array = []
var biome := {"top": Color("5f8d45"), "top2": Color("4a7538"), "side": Color("8b6d52"), "deep": Color("3a3140"), "leaf": Color("5a9a4f")}

func idx(x: int, z: int) -> int:
	return z * w + x

func inb(x: int, z: int) -> bool:
	return x >= 0 and z >= 0 and x < w and z < h

# ------------------------------------------------------------------ queries
func ground_at(x: float, z: float) -> float:
	var ix := int(floor(x)); var iz := int(floor(z))
	if not inb(ix, iz):
		return VOID
	var i := idx(ix, iz)
	if kind[i] == T_VOID:
		return VOID
	return level[i] * LEVEL

func is_void(x: float, z: float) -> bool:
	return ground_at(x, z) <= VOID + 1.0

func is_block(x: float, z: float) -> bool:
	var ix := int(floor(x)); var iz := int(floor(z))
	return inb(ix, iz) and kind[idx(ix, iz)] == T_BLOCK

func island_of(x: float, z: float) -> int:
	var ix := int(floor(x)); var iz := int(floor(z))
	if not inb(ix, iz):
		return -1
	return island[idx(ix, iz)]

## Can a body of radius r stand at (x,z) with feet at y?
## Returns 0 if free, the blocking height if a wall or rock is in the way, -1 if the edge guard stops it.
func occupy(x: float, z: float, r: float, y: float, guard: bool) -> float:
	var worst := 0.0
	for o in [Vector2(0, 0), Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r), Vector2(r, r) * 0.7, Vector2(-r, r) * 0.7, Vector2(r, -r) * 0.7, Vector2(-r, -r) * 0.7]:
		var px: float = x + o.x; var pz: float = z + o.y
		if is_block(px, pz):
			var top := ground_at(px, pz) + BLOCK_H
			if top > y + STEP:
				return top
		var g := ground_at(px, pz)
		if g > y + STEP:
			worst = maxf(worst, g)
	if worst > 0.0:
		return worst
	if guard:
		# don't let a walking hunter step off into the abyss; dashes and knockback ignore this
		if ground_at(x, z) <= VOID + 1.0:
			return -1.0
	return 0.0

## Line of sight at height y between two points (rocks and higher ground block it).
func los(a: Vector3, b: Vector3, y: float) -> bool:
	var d := Vector2(b.x - a.x, b.z - a.z)
	var n := int(d.length() / 0.4) + 1
	for i in range(1, n):
		var t := float(i) / n
		var px := a.x + d.x * t; var pz := a.z + d.y * t
		if is_block(px, pz) and ground_at(px, pz) + BLOCK_H > y:
			return false
		if ground_at(px, pz) > y + 0.2:
			return false
	return true

func random_ground(isl := -1, avoid_block := true) -> Vector3:
	for _t in 400:
		var x := rng.randi_range(0, w - 1); var z := rng.randi_range(0, h - 1)
		var i := idx(x, z)
		if kind[i] == T_GROUND and (isl < 0 or island[i] == isl):
			if avoid_block and _near_block(x, z):
				continue
			return Vector3(x + 0.5, level[i] * LEVEL, z + 0.5)
	return Vector3(w / 2.0, 0, h / 2.0)

func _near_block(x: int, z: int) -> bool:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if inb(x + dx, z + dz) and kind[idx(x + dx, z + dz)] == T_BLOCK:
				return true
	return false

func edge_dist(x: int, z: int, maxd := 4) -> int:
	for r in range(1, maxd + 1):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dz) != r:
					continue
				if not inb(x + dx, z + dz) or kind[idx(x + dx, z + dz)] == T_VOID:
					return r
	return maxd + 1

# ------------------------------------------------------------------ generation
func generate(seed_val: int, size := 64, n_islands := 7) -> void:
	rng.seed = seed_val
	w = size; h = size
	kind.resize(w * h); kind.fill(T_VOID)
	level.resize(w * h); level.fill(0)
	island.resize(w * h); island.fill(-1)
	depth.resize(w * h); depth.fill(0.0)
	islands.clear(); pads.clear(); spawns.clear(); portal_spots.clear(); chest_spots.clear(); camp_spots.clear(); wild_spots.clear()
	var shape := FastNoiseLite.new(); shape.seed = seed_val; shape.frequency = 0.09
	var terr := FastNoiseLite.new(); terr.seed = seed_val + 7; terr.frequency = 0.07
	# island centres: a big heart island in the middle and a ring of outer islands around it,
	# evenly spaced by angle so every side of the map has somewhere to land
	var centers: Array = [{"c": Vector2(w / 2.0, h / 2.0), "r": rng.randf_range(8.5, 9.8)}]
	var n_outer := n_islands - 1
	var a0 := rng.randf() * TAU
	for k in n_outer:
		var r := rng.randf_range(5.4, 7.2)
		var ang := a0 + TAU * k / n_outer + rng.randf_range(-0.22, 0.22)
		var dist: float = centers[0]["r"] + r + rng.randf_range(4.0, 6.0)
		var c := Vector2(w / 2.0, h / 2.0) + Vector2(cos(ang), sin(ang)) * dist
		c.x = clampf(c.x, r + 2, w - r - 2); c.y = clampf(c.y, r + 2, h - r - 2)
		centers.append({"c": c, "r": r})
	for ii in centers.size():
		var c: Vector2 = centers[ii]["c"]; var r: float = centers[ii]["r"]
		var base := 0 if ii == 0 else rng.randi_range(0, 2)
		var cells: Array = []
		for z in range(int(c.y - r - 3), int(c.y + r + 4)):
			for x in range(int(c.x - r - 3), int(c.x + r + 4)):
				if not inb(x, z) or x < 1 or z < 1 or x > w - 2 or z > h - 2:
					continue
				var d := Vector2(x + 0.5, z + 0.5).distance_to(c) / r
				var n := shape.get_noise_2d(x, z) * 0.35
				if d + n < 1.0 and kind[idx(x, z)] == T_VOID:
					var i := idx(x, z)
					kind[i] = T_GROUND
					island[i] = ii
					var lv := base
					var tn := terr.get_noise_2d(x, z)
					if tn > 0.22 and d < 0.8:
						lv += 1
					if tn > 0.5 and d < 0.6:
						lv += 1
					level[i] = clampi(lv, 0, 4)
					depth[i] = -(2.2 + (1.0 - d) * 4.5 + rng.randf() * 1.5)
					cells.append(Vector2i(x, z))
		islands.append({"c": c, "r": r, "base": base, "cells": cells, "role": "heart" if ii == 0 else ""})
	var roles: Array = ["camp", "camp", "nest", "nest", "grove", "shrine"]
	while roles.size() < n_outer: roles.append(["camp", "nest", "grove"][roles.size() % 3])
	roles = roles.slice(0, n_outer)
	roles.shuffle()
	# shuffle with our own rng so maps stay deterministic per seed
	for k in range(roles.size() - 1, 0, -1):
		var j := rng.randi_range(0, k)
		var tmp = roles[k]; roles[k] = roles[j]; roles[j] = tmp
	for k in n_outer:
		if k + 1 < islands.size():
			islands[k + 1]["role"] = roles[k]
	_place_blockers()
	_place_pads()
	_place_spots()

func _place_blockers() -> void:
	for isl in islands:
		for cell in isl["cells"]:
			var i := idx(cell.x, cell.y)
			if edge_dist(cell.x, cell.y, 2) <= 1:
				continue
			if rng.randf() < 0.055:
				kind[i] = T_BLOCK

func _edge_cell_toward(isl: int, target: Vector2) -> Vector2i:
	var best := Vector2i(-1, -1); var bd := 1e9
	for cell in islands[isl]["cells"]:
		if kind[idx(cell.x, cell.y)] != T_GROUND or edge_dist(cell.x, cell.y, 3) != 2 or _near_block(cell.x, cell.y):
			continue
		var d := Vector2(cell.x + 0.5, cell.y + 0.5).distance_to(target)
		if d < bd:
			bd = d; best = cell
	return best

func _place_pads() -> void:
	# connect islands with a spanning tree of jump pads, plus a couple of extra links
	var n := islands.size()
	var linked := {0: true}
	var edges: Array = []
	while linked.size() < n:
		var best := []; var bd := 1e9
		for a in linked:
			for b in n:
				if linked.has(b):
					continue
				var d: float = islands[a]["c"].distance_to(islands[b]["c"])
				if d < bd:
					bd = d; best = [a, b]
		if best.is_empty():
			break
		linked[best[1]] = true
		edges.append(best)
	for _e in 2:
		var a := rng.randi_range(0, n - 1); var b := rng.randi_range(0, n - 1)
		if a != b and not edges.has([a, b]) and not edges.has([b, a]):
			edges.append([a, b])
	for e in edges:
		for dir in [[e[0], e[1]], [e[1], e[0]]]:
			var from: int = dir[0]; var to: int = dir[1]
			var c_from := _edge_cell_toward(from, islands[to]["c"])
			if c_from.x < 0:
				continue
			var p := Vector3(c_from.x + 0.5, level[idx(c_from.x, c_from.y)] * LEVEL, c_from.y + 0.5)
			pads.append({"pos": p, "land": Vector3.INF, "from": from, "to": to, "cd": 0.0})
	# landing spots: on the target island, facing where you came from, but clear of every pad and rock
	for pd in pads:
		var to: int = pd["to"]
		var src := Vector2(pd["pos"].x, pd["pos"].z)
		var best := Vector3.INF; var bs := -1e9
		for cell in islands[to]["cells"]:
			var i := idx(cell.x, cell.y)
			if kind[i] != T_GROUND or _near_block(cell.x, cell.y):
				continue
			var cp := Vector2(cell.x + 0.5, cell.y + 0.5)
			var clear := true
			for other in pads:
				if Vector2(other["pos"].x, other["pos"].z).distance_to(cp) < 3.0:
					clear = false; break
			if not clear:
				continue
			var ed := edge_dist(cell.x, cell.y, 5)
			var score := -cp.distance_to(src) - (6.0 if ed < 2 else 0.0)
			if score > bs:
				bs = score; best = Vector3(cp.x, level[i] * LEVEL, cp.y)
		pd["land"] = best
	pads = pads.filter(func(pd): return pd["land"] != Vector3.INF)

var shrine_spots: Array = []     # Vector3
var heart_spot := Vector3.INF

## The island's point of interest: the open ground cell nearest its middle.
func _poi(isl: int) -> Vector3:
	var c: Vector2 = islands[isl]["c"]
	var best := Vector2i(-1, -1); var bd := 1e9
	for cell in islands[isl]["cells"]:
		if kind[idx(cell.x, cell.y)] == T_VOID or edge_dist(cell.x, cell.y, 3) < 3:
			continue
		var d := Vector2(cell.x + 0.5, cell.y + 0.5).distance_to(c)
		if d < bd: bd = d; best = cell
	if best.x < 0:
		return Vector3.INF
	return Vector3(best.x + 0.5, level[idx(best.x, best.y)] * LEVEL, best.y + 0.5)

func _clear_around(p: Vector3, rad: float) -> void:
	for z in range(int(p.z - rad - 1), int(p.z + rad + 1)):
		for x in range(int(p.x - rad - 1), int(p.x + rad + 1)):
			if inb(x, z) and kind[idx(x, z)] == T_BLOCK and Vector2(x + 0.5 - p.x, z + 0.5 - p.z).length() <= rad:
				kind[idx(x, z)] = T_GROUND

## Rocks set out in a pattern around a point of interest, as cover.
func _pillars(p: Vector3, offs: Array) -> void:
	for o in offs:
		var x := int(floor(p.x + o.x)); var z := int(floor(p.z + o.y))
		if inb(x, z) and kind[idx(x, z)] == T_GROUND and edge_dist(x, z, 2) >= 2:
			kind[idx(x, z)] = T_BLOCK

## A ground cell near p at a given distance, on the same island and not by an edge.
func _near(p: Vector3, dist: float, ang: float, isl: int, taken: Dictionary) -> Vector3:
	for t in 16:
		var a := ang + (t / 2) * 0.45 * (1.0 if t % 2 == 0 else -1.0)
		for dd in [dist, dist * 0.75, dist * 1.25]:
			var x := int(floor(p.x + cos(a) * dd)); var z := int(floor(p.z + sin(a) * dd))
			if not inb(x, z): continue
			var i := idx(x, z)
			if kind[i] != T_GROUND or island[i] != isl or edge_dist(x, z, 2) < 2 or _near_block(x, z) or taken.has(Vector2i(x, z)):
				continue
			taken[Vector2i(x, z)] = true
			return Vector3(x + 0.5, level[i] * LEVEL, z + 0.5)
	return Vector3.INF

func _place_spots() -> void:
	shrine_spots.clear()
	heart_spot = Vector3.INF
	var taken := {}
	for pd in pads:
		taken[Vector2i(int(pd["pos"].x), int(pd["pos"].z))] = true
	var pick := func(isl: int, min_edge: int, max_edge: int) -> Vector3:
		for _t in 300:
			var cells: Array = islands[isl]["cells"]
			var c: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
			var i := idx(c.x, c.y)
			if kind[i] != T_GROUND or _near_block(c.x, c.y) or taken.has(c):
				continue
			var ed := edge_dist(c.x, c.y, 6)
			if ed < min_edge or ed > max_edge:
				continue
			var near := false
			for k in taken:
				if (k - c).length() < 3.0:
					near = true; break
			if near:
				continue
			taken[c] = true
			return Vector3(c.x + 0.5, level[i] * LEVEL, c.y + 0.5)
		return Vector3.INF
	var mid := Vector2(w / 2.0, h / 2.0)
	for ii in islands.size():
		var role: String = islands[ii]["role"]
		var poi := _poi(ii)
		if poi == Vector3.INF:
			continue
		var toward_mid := atan2(mid.y - poi.z, mid.x - poi.x)
		_clear_around(poi, 2.4)
		taken[Vector2i(int(poi.x), int(poi.z))] = true
		match role:
			"heart":
				# the vault: the best chest in the middle, ringed by rocks, two guard camps
				heart_spot = poi
				chest_spots.append({"pos": poi, "tier": 2})
				_pillars(poi, [Vector2(3.2, 3.2), Vector2(-3.2, 3.2), Vector2(3.2, -3.2), Vector2(-3.2, -3.2)])
				for k in 2:
					var cp := _near(poi, 4.5, a0_of(ii) + PI * k, ii, taken)
					if cp != Vector3.INF: camp_spots.append({"pos": cp, "island": ii, "kind": "heavy"})
				var side := _near(poi, 6.0, a0_of(ii) + PI * 0.5, ii, taken)
				if side != Vector3.INF: chest_spots.append({"pos": side, "tier": 1})
			"camp":
				# a rare chest with the monsters standing between it and the middle of the map
				chest_spots.append({"pos": poi, "tier": 1})
				var cp := _near(poi, 2.6, toward_mid, ii, taken)
				if cp != Vector3.INF: camp_spots.append({"pos": cp, "island": ii, "kind": "normal"})
				_pillars(poi, [Vector2(cos(toward_mid + 1.3), sin(toward_mid + 1.3)) * 2.2, Vector2(cos(toward_mid - 1.3), sin(toward_mid - 1.3)) * 2.2])
			"nest":
				# wild kin around a nest, a small guard, a plain chest off to the side
				for k in 2:
					var wp := _near(poi, 1.8, toward_mid + PI * k, ii, taken)
					if wp != Vector3.INF: wild_spots.append(wp)
				var cp := _near(poi, 3.5, toward_mid + PI * 0.5, ii, taken)
				if cp != Vector3.INF: camp_spots.append({"pos": cp, "island": ii, "kind": "light"})
				var ch := _near(poi, 3.5, toward_mid - PI * 0.5, ii, taken)
				if ch != Vector3.INF: chest_spots.append({"pos": ch, "tier": 0})
				islands[ii]["nest"] = poi
			"grove":
				# quiet: two plain chests and a light camp
				for k in 2:
					var ch := _near(poi, 2.8, toward_mid + PI * (0.5 + k), ii, taken)
					if ch != Vector3.INF: chest_spots.append({"pos": ch, "tier": 0})
				var cp := _near(poi, 1.0, toward_mid, ii, taken)
				if cp != Vector3.INF: camp_spots.append({"pos": cp, "island": ii, "kind": "light"})
				if rng.randf() < 0.5:
					var wp := _near(poi, 3.5, toward_mid + PI, ii, taken)
					if wp != Vector3.INF: wild_spots.append(wp)
			"shrine":
				shrine_spots.append(poi)
				_pillars(poi, [Vector2(2.2, 0), Vector2(-2.2, 0), Vector2(0, 2.2), Vector2(0, -2.2)])
				var ch := _near(poi, 3.6, toward_mid + PI, ii, taken)
				if ch != Vector3.INF: chest_spots.append({"pos": ch, "tier": 0})
	# exits on three outer islands spread around the ring
	var outer: Array = range(1, islands.size())
	outer.sort_custom(func(x, y): return a0_of(x) < a0_of(y))
	var step := maxi(1, outer.size() / 3)
	var off := rng.randi_range(0, outer.size() - 1)
	var order: Array = []
	for k in 3:
		var cand: int = outer[(off + k * step) % outer.size()]
		if not order.has(cand): order.append(cand)
	for ii in outer:
		if not order.has(ii): order.append(ii)
	for ii in order:
		if portal_spots.size() >= 3:
			break
		var p: Vector3 = pick.call(ii, 2, 7)
		if p != Vector3.INF:
			portal_spots.append(p)
	# hunters land on the outer islands, two spots each near the edge
	for ii in range(1, islands.size()):
		var got := 0
		for _k in 2:
			var p: Vector3 = pick.call(ii, 2, 4)
			if p == Vector3.INF:
				p = pick.call(ii, 1, 6)
			if p != Vector3.INF:
				spawns.append(p); got += 1

## Angle of an island around the map centre.
func a0_of(isl: int) -> float:
	var c: Vector2 = islands[isl]["c"]
	return atan2(c.y - h / 2.0, c.x - w / 2.0)

# ------------------------------------------------------------------ meshes
func build_meshes() -> void:
	for c in get_children():
		c.queue_free()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tn := FastNoiseLite.new(); tn.seed = rng.seed + 3; tn.frequency = 0.3
	for z in h:
		for x in w:
			var i := idx(x, z)
			if kind[i] == T_VOID or bridge.has(i):
				continue
			var y := level[i] * LEVEL
			var cols := []
			for cv in [Vector2(x, z), Vector2(x + 1, z), Vector2(x + 1, z + 1), Vector2(x, z + 1)]:
				var v := tn.get_noise_2d(cv.x * 0.6, cv.y * 0.6) * 0.5 + 0.5
				var v2 := tn.get_noise_2d(cv.x * 2.1 + 40.0, cv.y * 2.1) * 0.5 + 0.5
				var col: Color = biome["top"].lerp(biome["top2"], v).lerp(biome["top"].lightened(0.08), v2 * 0.35)
				col = col.lightened(0.035 * level[i])
				if not paint.is_empty():
					var pc := Color(0, 0, 0, 0); var pn := 0
					for t in [Vector2i(int(cv.x) - 1, int(cv.y) - 1), Vector2i(int(cv.x), int(cv.y) - 1), Vector2i(int(cv.x) - 1, int(cv.y)), Vector2i(int(cv.x), int(cv.y))]:
						if inb(t.x, t.y) and paint.has(idx(t.x, t.y)):
							pc += paint[idx(t.x, t.y)]; pn += 1
					if pn > 0:
						col = col.lerp(pc / pn, minf(1.0, pn / 2.0) * (0.85 + v2 * 0.15))
				cols.append(col)
			_quad4(st, Vector3(x, y, z), Vector3(x + 1, y, z), Vector3(x + 1, y, z + 1), Vector3(x, y, z + 1), Vector3.UP, cols)
			var bottom := depth[i] + y * 0.3
			for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + dir.x; var nz: int = z + dir.y
				var ny := -1.0e9
				if inb(nx, nz) and kind[idx(nx, nz)] != T_VOID and not bridge.has(idx(nx, nz)):
					ny = level[idx(nx, nz)] * LEVEL
				if ny >= y - 0.001:
					continue
				var lo := maxf(ny, bottom)
				_side(st, x, z, dir, y, lo, ny <= -1.0e8)
			# underside of the column
			_quad(st, Vector3(x, bottom, z + 1), Vector3(x + 1, bottom, z + 1), Vector3(x + 1, bottom, z), Vector3(x, bottom, z), Vector3.DOWN, biome["deep"].darkened(0.3))
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Models.vtoon()
	mi.name = "Ground"
	add_child(mi)
	_decorate()

func _quad4(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, cols: Array) -> void:
	st.set_normal(n)
	st.set_color(cols[0]); st.add_vertex(a)
	st.set_color(cols[1]); st.add_vertex(b)
	st.set_color(cols[2]); st.add_vertex(c)
	st.set_color(cols[0]); st.add_vertex(a)
	st.set_color(cols[2]); st.add_vertex(c)
	st.set_color(cols[3]); st.add_vertex(d)

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color, col2 = null) -> void:
	var c2: Color = col if col2 == null else col2
	st.set_normal(n)
	st.set_color(col); st.add_vertex(a)
	st.set_color(col); st.add_vertex(b)
	st.set_color(c2); st.add_vertex(c)
	st.set_color(col); st.add_vertex(a)
	st.set_color(c2); st.add_vertex(c)
	st.set_color(c2); st.add_vertex(d)

func _side(st: SurfaceTool, x: int, z: int, dir: Vector2i, top: float, lo: float, to_void: bool) -> void:
	var n := Vector3(dir.x, 0, dir.y)
	var p0: Vector3; var p1: Vector3
	match dir:
		Vector2i(1, 0): p0 = Vector3(x + 1, 0, z + 1); p1 = Vector3(x + 1, 0, z)
		Vector2i(-1, 0): p0 = Vector3(x, 0, z); p1 = Vector3(x, 0, z + 1)
		Vector2i(0, 1): p0 = Vector3(x, 0, z + 1); p1 = Vector3(x + 1, 0, z + 1)
		_: p0 = Vector3(x + 1, 0, z); p1 = Vector3(x, 0, z)
	# a grassy lip, then dirt fading into dark rock toward the bottom
	var lip := minf(0.18, top - lo)
	var grass: Color = biome["top2"].darkened(0.12)
	var dirt: Color = biome["side"]
	_band(st, p0, p1, top, top - lip, n, grass, grass)
	var mid := maxf(lo, top - lip - 1.2)
	_band(st, p0, p1, top - lip, mid, n, dirt, dirt.darkened(0.15))
	if mid > lo:
		_band(st, p0, p1, mid, lo, n, dirt.darkened(0.15), biome["deep"] if to_void else dirt.darkened(0.3))

func _band(st: SurfaceTool, p0: Vector3, p1: Vector3, y0: float, y1: float, n: Vector3, c0: Color, c1: Color) -> void:
	if y0 - y1 < 0.001:
		return
	var a := Vector3(p0.x, y0, p0.z); var b := Vector3(p1.x, y0, p1.z)
	var c := Vector3(p1.x, y1, p1.z); var d := Vector3(p0.x, y1, p0.z)
	st.set_normal(n)
	st.set_color(c0); st.add_vertex(a)
	st.set_color(c0); st.add_vertex(b)
	st.set_color(c1); st.add_vertex(c)
	st.set_color(c0); st.add_vertex(a)
	st.set_color(c1); st.add_vertex(c)
	st.set_color(c1); st.add_vertex(d)

func _decorate() -> void:
	var drng := RandomNumberGenerator.new(); drng.seed = rng.seed + 11
	var deco := Node3D.new(); deco.name = "Deco"; add_child(deco)
	for z in h:
		for x in w:
			var i := idx(x, z)
			if kind[i] != T_BLOCK or no_deco.has(i):
				continue
			var y := level[i] * LEVEL
			var n: Node3D
			if drng.randf() < 0.5:
				n = Models.tree(drng, biome["leaf"])
			else:
				n = Models.rock(drng, drng.randf_range(0.9, 1.25))
			n.position = Vector3(x + 0.5, y, z + 0.5)
			deco.add_child(n)
	# grass tufts and flowers, batched
	var tuft := Models.cyl(0.0, 0.06, 0.22, 4)
	var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.use_colors = true; mm.mesh = tuft
	var xs: Array = []
	for z in h:
		for x in w:
			var i := idx(x, z)
			if kind[i] != T_GROUND or paint.has(i) or bridge.has(i):
				continue
			for _k in 2:
				if drng.randf() < 0.45:
					xs.append([Vector3(x + drng.randf(), level[i] * LEVEL + 0.1, z + drng.randf()), drng.randf()])
	mm.instance_count = xs.size()
	for k in xs.size():
		var t := Transform3D(Basis().scaled(Vector3.ONE * (0.7 + xs[k][1] * 0.8)), xs[k][0])
		mm.set_instance_transform(k, t)
		var c: Color = biome["top2"].darkened(0.1).lerp(Color("f4e27a") if xs[k][1] > 0.93 else biome["top"].lightened(0.15), xs[k][1])
		mm.set_instance_color(k, c)
	var mmi := MultiMeshInstance3D.new(); mmi.multimesh = mm
	var mat := Models.vtoon(); mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	deco.add_child(mmi)
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(maxi(w, h) * 14, maxi(w, h) * 14)
	sea.mesh = pm
	var cm := ShaderMaterial.new(); cm.shader = load("res://shaders/clouds.gdshader")
	if clouds.size() == 2:
		cm.set_shader_parameter("deep", clouds[0])
		cm.set_shader_parameter("light", clouds[1])
	sea.material_override = cm
	sea.position = Vector3(w / 2.0, -18.0, h / 2.0)
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)
	# drifting rocks in the abyss for depth
	for _k in 40:
		var r := Models.rock(drng, drng.randf_range(0.6, 2.2))
		r.position = Vector3(drng.randf_range(-10, w + 10), drng.randf_range(-15, -6), drng.randf_range(-10, h + 10))
		deco.add_child(r)

## The home island: one flat round island with room for the farm, house and portal.
func make_home(seed_val: int) -> void:
	rng.seed = seed_val
	w = 72; h = 50
	kind.resize(w * h); kind.fill(T_VOID)
	level.resize(w * h); level.fill(0)
	island.resize(w * h); island.fill(-1)
	depth.resize(w * h); depth.fill(0.0)
	islands.clear(); pads.clear(); spawns.clear(); portal_spots.clear(); chest_spots.clear(); camp_spots.clear(); wild_spots.clear()
	bridge.clear()
	var shape := FastNoiseLite.new(); shape.seed = seed_val; shape.frequency = 0.12
	var defs: Array = [["main", Vector2(38, 32), Vector2(14, 11)]]
	for k in Data.ISLES:
		defs.append([k, Data.ISLES[k]["c"], Data.ISLES[k]["r"]])
	for di in defs.size():
		var c: Vector2 = defs[di][1]; var rr: Vector2 = defs[di][2]
		var cells: Array = []
		for z in range(maxi(1, int(c.y - rr.y - 2)), mini(h - 1, int(c.y + rr.y + 2))):
			for x in range(maxi(1, int(c.x - rr.x - 2)), mini(w - 1, int(c.x + rr.x + 2))):
				var d := Vector2((x + 0.5 - c.x) / rr.x, (z + 0.5 - c.y) / rr.y).length()
				if d + shape.get_noise_2d(x, z) * 0.14 < 1.0:
					var i := idx(x, z)
					kind[i] = T_GROUND
					island[i] = di
					depth[i] = -(2.0 + (1.0 - d) * (5.0 if di == 0 else 3.6) + rng.randf() * 1.0)
					cells.append(Vector2i(x, z))
		islands.append({"id": defs[di][0], "c": c, "r": rr.x, "base": 0, "cells": cells})

## Walkable plank tiles over the void between home islands. They are drawn separately.
var bridge := {}

func bridge_tiles(rect: Array) -> Array:
	var out: Array = []
	for z in range(int(rect[1]), int(rect[3]) + 1):
		for x in range(int(rect[0]), int(rect[2]) + 1):
			if inb(x, z) and (kind[idx(x, z)] == T_VOID or bridge.has(idx(x, z))):
				out.append(Vector2i(x, z))
	return out

func open_bridge(tiles: Array) -> void:
	for t in tiles:
		var i := idx(t.x, t.y)
		kind[i] = T_GROUND
		bridge[i] = true

func island_id(x: float, z: float) -> String:
	var i := island_of(x, z)
	return islands[i]["id"] if i >= 0 and i < islands.size() else ""

func set_block_rect(x0: int, z0: int, x1: int, z1: int) -> void:
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			if inb(x, z) and kind[idx(x, z)] != T_VOID:
				kind[idx(x, z)] = T_BLOCK
				no_deco[idx(x, z)] = true

func add_trees_on_rim(n: int) -> void:
	var placed := 0
	for _t in 400:
		if placed >= n: break
		var x := rng.randi_range(1, w - 2); var z := rng.randi_range(1, h - 2)
		var i := idx(x, z)
		if kind[i] == T_GROUND and edge_dist(x, z, 3) == 2:
			kind[i] = T_BLOCK
			placed += 1

func paint_tile(x: int, z: int, col: Color) -> void:
	if inb(x, z) and kind[idx(x, z)] != T_VOID:
		paint[idx(x, z)] = col

## A dirt path between two tile positions, one tile wide with a little wobble.
func paint_path(a: Vector2i, b: Vector2i, col: Color, wide := true) -> void:
	var n := maxi(absi(b.x - a.x), absi(b.y - a.y)) + 1
	for i in n:
		var t := float(i) / maxf(1.0, n - 1)
		var x := int(round(lerpf(a.x, b.x, t))); var z := int(round(lerpf(a.y, b.y, t)))
		paint_tile(x, z, col)
		if not wide:
			continue
		if absi(b.x - a.x) > absi(b.y - a.y):
			paint_tile(x, z + 1, col)
		else:
			paint_tile(x + 1, z, col)
