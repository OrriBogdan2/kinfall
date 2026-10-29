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
var links: Array = []        # glide routes between close islands {from, to, take: Vector3, land: Vector3}
var rings: Array = []        # air rings {pos: Vector3, dir: Vector2}
var winds: Array = []        # wind roads across long gaps {a: Vector3, b: Vector3} (either way)
var updrafts: Array = []     # rising air off island edges {pos: Vector3, r: float, top: float}
const BIG_SIZE := 216            # an expedition map's side, in tiles (about 3x the area it used to be)
const BIG_ISLANDS := 32
const GLIDE_GAP := 14.0      # islands closer than this (edge to edge) are reached by gliding, not pads
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
	# rocks, trees and walls use a slimmer body than the terrain does, so you slide past their
	# corners and fit through one-tile gaps instead of snagging
	var rb := r * 0.7
	for o in [Vector2(0, 0), Vector2(rb, 0), Vector2(-rb, 0), Vector2(0, rb), Vector2(0, -rb), Vector2(rb, rb) * 0.7, Vector2(-rb, rb) * 0.7, Vector2(rb, -rb) * 0.7, Vector2(-rb, -rb) * 0.7]:
		var px: float = x + o.x; var pz: float = z + o.y
		if is_block(px, pz):
			var top := ground_at(px, pz) + BLOCK_H
			if top > y + STEP:
				return top
	for o in [Vector2(0, 0), Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r), Vector2(r, r) * 0.7, Vector2(-r, r) * 0.7, Vector2(r, -r) * 0.7, Vector2(-r, -r) * 0.7]:
		var g := ground_at(x + o.x, z + o.y)
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
	var fallback := Vector3.INF
	for _t in 400:
		var x := rng.randi_range(0, w - 1); var z := rng.randi_range(0, h - 1)
		var i := idx(x, z)
		if kind[i] == T_GROUND and (isl < 0 or island[i] == isl):
			if avoid_block and _near_block(x, z):
				continue
			var spot := Vector3(x + 0.5, level[i] * LEVEL, z + 0.5)
			if avoid_block and not roomy(x, z):
				if fallback == Vector3.INF: fallback = spot
				continue
			return spot
	return fallback if fallback != Vector3.INF else Vector3(w / 2.0, 0, h / 2.0)

## Is this tile part of open ground, rather than a little pocket walled in by rocks, walls,
## buildings or cliffs? (Walks outward over tiles you could step between.)
func roomy(x: int, z: int, need := 40) -> bool:
	if not inb(x, z) or kind[idx(x, z)] != T_GROUND:
		return false
	var seen := {Vector2i(x, z): true}
	var q: Array = [Vector2i(x, z)]
	var qi := 0
	while qi < q.size():
		var c: Vector2i = q[qi]; qi += 1
		if seen.size() >= need:
			return true
		var lc := int(level[idx(c.x, c.y)])
		for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + dv
			if seen.has(n) or not inb(n.x, n.y):
				continue
			var ni := idx(n.x, n.y)
			if kind[ni] != T_GROUND or absi(int(level[ni]) - lc) > 1:
				continue
			seen[n] = true
			q.append(n)
	return seen.size() >= need

## The nearest spot to p where a body fits: on open ground, clear of rocks, walls and buildings,
## and at least `gap` away from every point in `avoid` (so spawns never pile up or start stuck).
func free_spot_near(p: Vector3, avoid: Array = [], gap := 1.0, r := 0.45, max_rad := 10.0) -> Vector3:
	var rad := 0.0
	while rad <= max_rad:
		var n := maxi(1, int(TAU * rad / 0.6))
		for k in n:
			var a := TAU * k / n + rad
			var x := p.x + cos(a) * rad; var z := p.z + sin(a) * rad
			if _fits(x, z, r) and roomy(int(floor(x)), int(floor(z))):
				var ok := true
				for o in avoid:
					if Vector2((o as Vector3).x - x, (o as Vector3).z - z).length() < gap:
						ok = false; break
				if ok:
					return Vector3(x, ground_at(x, z), z)
		rad += 0.5
	return p

func _fits(x: float, z: float, r: float) -> bool:
	if is_void(x, z):
		return false
	var g := ground_at(x, z)
	for o in [Vector2(0, 0), Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r), Vector2(r, r) * 0.7, Vector2(-r, r) * 0.7, Vector2(r, -r) * 0.7, Vector2(-r, -r) * 0.7]:
		if is_block(x + o.x, z + o.y) or is_void(x + o.x, z + o.y) or absf(ground_at(x + o.x, z + o.y) - g) > 0.05:
			return false
	return true

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
	links.clear(); rings.clear(); winds.clear(); updrafts.clear()
	var shape := FastNoiseLite.new(); shape.seed = seed_val; shape.frequency = 0.09
	var terr := FastNoiseLite.new(); terr.seed = seed_val + 7; terr.frequency = 0.07
	# island centres: a big heart island in the middle and a ring of outer islands around it,
	# evenly spaced by angle so every side of the map has somewhere to land
	var centers: Array = [{"c": Vector2(w / 2.0, h / 2.0), "r": rng.randf_range(8.5, 9.8)}]
	var n_outer := n_islands - 1
	var a0 := rng.randf() * TAU
	# big maps get a second, wider ring of islands beyond the first
	var n_inner := mini(n_outer, 6)
	var n_far := n_outer - n_inner
	for k in n_inner:
		var r := rng.randf_range(5.4, 7.2)
		var ang := a0 + TAU * k / n_inner + rng.randf_range(-0.22, 0.22)
		var dist: float = centers[0]["r"] + r + rng.randf_range(4.0, 6.0)
		var c := Vector2(w / 2.0, h / 2.0) + Vector2(cos(ang), sin(ang)) * dist
		c.x = clampf(c.x, r + 2, w - r - 2); c.y = clampf(c.y, r + 2, h - r - 2)
		centers.append({"c": c, "r": r})
	# the biggest maps add a third, outermost ring of larger islands
	var n_outmost := 0
	if w >= 180:
		n_outmost = maxi(0, n_far - 13)
		n_far -= n_outmost
	for k in n_far:
		var r := rng.randf_range(6.0, 8.6)
		var ang := a0 + PI / maxf(1.0, n_far) + TAU * k / n_far + rng.randf_range(-0.12, 0.12)
		var dist: float = centers[0]["r"] + 32.0 + r * 0.5 + rng.randf_range(0.0, 5.0)
		var c := Vector2(w / 2.0, h / 2.0) + Vector2(cos(ang), sin(ang)) * dist
		c.x = clampf(c.x, r + 2, w - r - 2); c.y = clampf(c.y, r + 2, h - r - 2)
		centers.append({"c": c, "r": r})
	for k in n_outmost:
		var r := rng.randf_range(7.0, 10.5)
		var ang := a0 + TAU * k / n_outmost + rng.randf_range(-0.1, 0.1)
		var dist: float = centers[0]["r"] + 62.0 + r * 0.5 + rng.randf_range(-3.0, 6.0)
		var c := Vector2(w / 2.0, h / 2.0) + Vector2(cos(ang), sin(ang)) * dist
		c.x = clampf(c.x, r + 2, w - r - 2); c.y = clampf(c.y, r + 2, h - r - 2)
		centers.append({"c": c, "r": r})
	# every island gets a shape of its own so no two feel the same
	var shapes := ["blob", "crescent", "atoll", "twin", "mesa", "canyon", "highlands", "terraces"]
	for ii in centers.size():
		var c: Vector2 = centers[ii]["c"]; var r: float = centers[ii]["r"]
		var base := 0 if ii == 0 else rng.randi_range(0, 2)
		var form: String = ["blob", "mesa", "terraces"][rng.randi_range(0, 2)] if ii == 0 else shapes[rng.randi_range(0, shapes.size() - 1)]
		var fdir := Vector2.from_angle(rng.randf() * TAU)
		var cells: Array = []
		var pad_r := r * (1.25 if form == "twin" else 1.0)
		for z in range(int(c.y - pad_r - 3), int(c.y + pad_r + 4)):
			for x in range(int(c.x - pad_r - 3), int(c.x + pad_r + 4)):
				if not inb(x, z) or x < 1 or z < 1 or x > w - 2 or z > h - 2:
					continue
				var pt := Vector2(x + 0.5, z + 0.5)
				var d := pt.distance_to(c) / r
				var n := shape.get_noise_2d(x, z) * 0.35
				var rel := pt - c
				var along := rel.dot(fdir); var across := rel.dot(fdir.orthogonal())
				match form:
					"twin":
						# two lobes joined by a narrow neck
						var d1 := pt.distance_to(c + fdir * r * 0.62) / (r * 0.66)
						var d2 := pt.distance_to(c - fdir * r * 0.62) / (r * 0.66)
						d = minf(d1, d2)
						if absf(across) < 1.3 and absf(along) < r * 0.7: d = minf(d, 0.5)
				if d + n >= 1.0 or kind[idx(x, z)] != T_VOID:
					continue
				match form:
					"crescent":
						if pt.distance_to(c + fdir * r * 0.8) < r * 0.62: continue
					"atoll":
						if d < 0.33 + n * 0.3: continue      # a hole in the middle to the sky below
					"canyon":
						if absf(across) < 1.1 and absf(along) > 1.6: continue   # split down the middle, one crossing
				var i := idx(x, z)
				kind[i] = T_GROUND
				island[i] = ii
				var lv := base
				var tn := terr.get_noise_2d(x, z)
				match form:
					"mesa":
						# a flat top above stepped sides you can hop up
						lv += 3 if d < 0.45 else (2 if d < 0.6 else (1 if d < 0.78 else 0))
					"terraces":
						# rings of steps climbing to one side
						lv += clampi(int((along / r + 1.0) * 1.6), 0, 3)
					"highlands":
						if tn > 0.0 and d < 0.9: lv += 1
						if tn > 0.25 and d < 0.75: lv += 1
						if tn > 0.45 and d < 0.6: lv += 1
					_:
						if tn > 0.22 and d < 0.8: lv += 1
						if tn > 0.5 and d < 0.6: lv += 1
				level[i] = clampi(lv, 0, 4)
				depth[i] = -(2.2 + (1.0 - clampf(d, 0.0, 1.0)) * 4.5 + rng.randf() * 1.5)
				cells.append(Vector2i(x, z))
		islands.append({"c": c, "r": r, "base": base, "cells": cells, "role": "heart" if ii == 0 else "", "form": form, "fdir": fdir})
	var roles: Array = ["camp", "camp", "nest", "nest", "grove", "shrine"]
	while roles.size() < n_outer: roles.append(["camp", "nest", "grove", "shrine", "camp"][roles.size() % 5])
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
	_place_updrafts()
	_place_spots()

var wall_mat: ShaderMaterial = null   # walls fade where they hide the player
var walls := {}           # tile index -> true: built stone walls (drawn as walls, not rocks)
var bush := {}            # tile index -> true: tall grass you can hide in

func _wall_at(q: Vector2i, ii: int) -> void:
	if inb(q.x, q.y) and kind[idx(q.x, q.y)] == T_GROUND and island[idx(q.x, q.y)] == ii and edge_dist(q.x, q.y, 3) >= 3:
		kind[idx(q.x, q.y)] = T_BLOCK
		walls[idx(q.x, q.y)] = true

func _place_blockers() -> void:
	walls.clear(); bush.clear()
	for ii in islands.size():
		var isl: Dictionary = islands[ii]
		var cells: Array = isl["cells"]
		for cell in cells:
			var i := idx(cell.x, cell.y)
			if edge_dist(cell.x, cell.y, 2) <= 1:
				continue
			if rng.randf() < 0.03:
				kind[i] = T_BLOCK
		# stone walls to fight around and peek past: straight runs with a doorway, corners,
		# rows of pillars, and on big islands a broken square keep
		var n_walls := 1 + int(cells.size() / 110) + rng.randi_range(0, 1)
		for _w in n_walls:
			var c0: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
			var dv: Vector2i = [Vector2i(1, 0), Vector2i(0, 1)][rng.randi_range(0, 1)]
			var roll := rng.randf()
			if roll < 0.4:
				var length := rng.randi_range(5, 8)
				var gap := rng.randi_range(1, length - 3)
				for k in length:
					if k != gap and k != gap + 1: _wall_at(c0 + dv * k, ii)    # a two-tile doorway
			elif roll < 0.7:
				var a := rng.randi_range(3, 5); var b := rng.randi_range(3, 5)
				var dv2 := Vector2i(dv.y, dv.x) * (1 if rng.randf() < 0.5 else -1)
				for k in a: _wall_at(c0 + dv * k, ii)
				for k in range(1, b): _wall_at(c0 + dv2 * k, ii)
			elif roll < 0.85 or cells.size() < 160:
				for k in 4: _wall_at(c0 + dv * (k * 3), ii)
			else:
				# a small keep: a 6x6 square with two openings
				for k in 6:
					for e in [Vector2i(k, 0), Vector2i(k, 5), Vector2i(0, k), Vector2i(5, k)]:
						if e in [Vector2i(2, 0), Vector2i(3, 0), Vector2i(5, 2), Vector2i(5, 3), Vector2i(0, 2), Vector2i(0, 3)]:
							continue
						_wall_at(c0 + e, ii)
		# patches of tall grass
		for _b in rng.randi_range(2, 4) + int(cells.size() / 160):
			var bc: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
			var rad := rng.randf_range(1.2, 2.3)
			for dz in range(-3, 4):
				for dx in range(-3, 4):
					var q := bc + Vector2i(dx, dz)
					if Vector2(dx, dz).length() > rad + rng.randf_range(-0.3, 0.3): continue
					if inb(q.x, q.y) and kind[idx(q.x, q.y)] == T_GROUND and island[idx(q.x, q.y)] == ii and edge_dist(q.x, q.y, 2) >= 2:
						bush[idx(q.x, q.y)] = true

## Which tiles block sight, for the view-cone shading (red = blocked).
func vis_texture() -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_R8)
	for z in h:
		for x in w:
			if kind[idx(x, z)] == T_BLOCK:
				img.set_pixel(x, z, Color(1, 0, 0))
	return ImageTexture.create_from_image(img)

func in_bush(x: float, z: float) -> bool:
	var ix := int(floor(x)); var iz := int(floor(z))
	return inb(ix, iz) and bush.has(idx(ix, iz)) and kind[idx(ix, iz)] == T_GROUND

func _edge_cell_toward(isl: int, target: Vector2, avoid: Array = [], spacing := PAD_SPACING) -> Vector2i:
	var best := Vector2i(-1, -1); var bd := 1e9
	for cell in islands[isl]["cells"]:
		if kind[idx(cell.x, cell.y)] != T_GROUND or edge_dist(cell.x, cell.y, 3) != 2 or _near_block(cell.x, cell.y):
			continue
		# keep pads well apart so each one clearly goes somewhere different
		var cp := Vector2(cell.x + 0.5, cell.y + 0.5)
		var crowded := false
		for a in avoid:
			if cp.distance_to(a) < spacing:
				crowded = true; break
		if crowded:
			continue
		var d := Vector2(cell.x + 0.5, cell.y + 0.5).distance_to(target)
		if d < bd:
			bd = d; best = cell
	return best

const PAD_SPACING := 6.0

## Closest edge cells between two islands and the gap between them: [gap, cell_a, cell_b].
func _gap(a: int, b: int, edges_of: Dictionary) -> Array:
	var best := [1e9, Vector2i.ZERO, Vector2i.ZERO]
	for ca in edges_of[a]:
		for cb in edges_of[b]:
			var d: float = Vector2(ca.x - cb.x, ca.y - cb.y).length()
			if d < best[0]:
				best = [d, ca, cb]
	return best

func _place_pads() -> void:
	# islands close enough are crossed by gliding (with air rings over the longer gaps); only the
	# far ones get jump pads. A spanning tree on the gaps keeps everything reachable.
	var n := islands.size()
	var edges_of := {}
	for ii in n:
		var e: Array = []
		for cell in islands[ii]["cells"]:
			if kind[idx(cell.x, cell.y)] != T_VOID and edge_dist(cell.x, cell.y, 1) == 1:
				e.append(cell)
		edges_of[ii] = e
	var gaps := {}
	for a in n:
		for b in range(a + 1, n):
			var cd: float = islands[a]["c"].distance_to(islands[b]["c"]) - float(islands[a]["r"]) - float(islands[b]["r"])
			if cd > 30.0:
				continue
			gaps[Vector2i(a, b)] = _gap(a, b, edges_of)
	var linked := {0: true}
	var edges: Array = []
	while linked.size() < n:
		var best := []; var bd := 1e9
		for k in gaps:
			var a: int = k.x; var b: int = k.y
			if linked.has(a) == linked.has(b):
				continue
			if float(gaps[k][0]) < bd:
				bd = float(gaps[k][0]); best = [a, b]
		if best.is_empty():
			# nothing within range: fall back to centre distance
			for a in linked:
				for b in n:
					if linked.has(b): continue
					var d: float = islands[a]["c"].distance_to(islands[b]["c"])
					if d < bd: bd = d; best = [a, b]
			if best.is_empty(): break
			var kk := Vector2i(mini(best[0], best[1]), maxi(best[0], best[1]))
			if not gaps.has(kk): gaps[kk] = _gap(kk.x, kk.y, edges_of)
		linked[best[1] if linked.has(best[0]) else best[0]] = true
		edges.append(best)
	# a few more glide routes between close neighbours, so there's more than one way around
	for k in gaps:
		if float(gaps[k][0]) <= GLIDE_GAP * 0.75 and rng.randf() < 0.5:
			var e := [k.x, k.y]
			if not edges.has(e) and not edges.has([k.y, k.x]):
				edges.append(e)
	var pad_edges: Array = []
	for e in edges:
		var k := Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))
		var g: Array = gaps[k]
		# long gaps, and climbs of more than a terrace or so, get pads instead
		var ga: Vector2i = g[1]; var gb: Vector2i = g[2]
		var dy: float = absf(float(level[idx(ga.x, ga.y)]) - float(level[idx(gb.x, gb.y)])) * LEVEL
		if float(g[0]) > GLIDE_GAP or dy > LEVEL * 2.2 or (dy > LEVEL * 1.2 and float(g[0]) > 10.0):
			# long or steep: a wind road carries gliders across (pads only for the very longest)
			if float(g[0]) > 46.0:
				pad_edges.append(e)
			else:
				_wind_link(k.x, k.y, g)
			continue
		_glide_link(k.x, k.y, g)
	edges = pad_edges
	var used: Array = []
	for e in edges:
		for dir in [[e[0], e[1]], [e[1], e[0]]]:
			var from: int = dir[0]; var to: int = dir[1]
			var c_from := _edge_cell_toward(from, islands[to]["c"], used)
			if c_from.x < 0:
				# a crowded island: settle for less room rather than leave the link out
				c_from = _edge_cell_toward(from, islands[to]["c"], used, 3.0)
			if c_from.x < 0:
				continue
			used.append(Vector2(c_from.x + 0.5, c_from.y + 0.5))
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

## A wind road: a current of air from one island's edge to another's, either way. Glide into it
## and it carries you along without heating your glider, climbing if the far side is higher.
func _wind_link(a: int, b: int, g: Array) -> void:
	var ca: Vector2i = g[1]; var cb: Vector2i = g[2]
	var pa := Vector3(ca.x + 0.5, level[idx(ca.x, ca.y)] * LEVEL, ca.y + 0.5)
	var pb := Vector3(cb.x + 0.5, level[idx(cb.x, cb.y)] * LEVEL, cb.y + 0.5)
	var land_b := _inward(b, pb, pa); var land_a := _inward(a, pa, pb)
	links.append({"from": a, "to": b, "take": pa, "land": land_b, "wind": true})
	links.append({"from": b, "to": a, "take": pb, "land": land_a, "wind": true})
	winds.append({"a": pa + Vector3(0, 1.6, 0), "b": pb + Vector3(0, 1.6, 0)})

## Where wind carries a glider at p: {dir (along the road, either way), y (its height)} or {}.
func wind_at(p: Vector3) -> Dictionary:
	for wd in winds:
		var a: Vector3 = wd["a"]; var b: Vector3 = wd["b"]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var l2 := ab.length_squared()
		if l2 < 0.01: continue
		var t := clampf(Vector2(p.x - a.x, p.z - a.z).dot(ab) / l2, 0.0, 1.0)
		var q := a.lerp(b, t)
		if Vector2(p.x - q.x, p.z - q.z).length() < 1.9 and absf(p.y - q.y) < 3.0 and t > 0.0 and t < 1.0:
			return {"dir": Vector3(ab.x, b.y - a.y, ab.y).normalized(), "y": q.y}
	return {}

## Rising air off island edges: glide into it to climb.
func updraft_at(p: Vector3) -> Dictionary:
	for u in updrafts:
		var c: Vector3 = u["pos"]
		if Vector2(p.x - c.x, p.z - c.z).length() < float(u["r"]) and p.y < float(u["top"]) and p.y > c.y - 6.0:
			return u
	return {}

func _place_updrafts() -> void:
	# beside the higher islands and along the edges of big ones, so the high ground can be reached
	# by gliding as well as by climbing
	for ii in islands.size():
		var isl: Dictionary = islands[ii]
		var cells: Array = isl["cells"]
		if cells.size() < 30:
			continue
		var top_lvl := 0
		for c in cells:
			top_lvl = maxi(top_lvl, int(level[idx(c.x, c.y)]))
		var n := 1 if cells.size() < 160 else 2
		if top_lvl < 2 and rng.randf() < 0.5:
			continue
		for _k in n:
			# a void spot just off the edge
			for _t in 30:
				var c: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
				if edge_dist(c.x, c.y, 1) != 1:
					continue
				var a := rng.randf() * TAU
				var p := Vector2(c.x + 0.5 + cos(a) * 2.6, c.y + 0.5 + sin(a) * 2.6)
				if not is_void(p.x, p.y):
					continue
				var base := float(level[idx(c.x, c.y)]) * LEVEL
				var ok := true
				for u in updrafts:
					if Vector2((u["pos"] as Vector3).x, (u["pos"] as Vector3).z).distance_to(p) < 10.0: ok = false
				if not ok: continue
				updrafts.append({"pos": Vector3(p.x, base, p.y), "r": 1.6, "top": float(top_lvl) * LEVEL + 7.0})
				break

## A glide route both ways between two close islands, with air rings over anything but a hop.
func _glide_link(a: int, b: int, g: Array) -> void:
	var ca: Vector2i = g[1]; var cb: Vector2i = g[2]
	var pa := Vector3(ca.x + 0.5, level[idx(ca.x, ca.y)] * LEVEL, ca.y + 0.5)
	var pb := Vector3(cb.x + 0.5, level[idx(cb.x, cb.y)] * LEVEL, cb.y + 0.5)
	# land a couple of tiles in from the edge
	var land_b := _inward(b, pb, pa); var land_a := _inward(a, pa, pb)
	links.append({"from": a, "to": b, "take": pa, "land": land_b})
	links.append({"from": b, "to": a, "take": pb, "land": land_a})
	var gap := float(g[0])
	if gap < 5.0:
		return
	var nr := clampi(int(gap / 5.0), 1, 4)
	var top := maxf(pa.y, pb.y) + 1.8
	var dir := Vector2(pb.x - pa.x, pb.z - pa.z).normalized()
	for i in nr:
		var t := float(i + 1) / float(nr + 1)
		var p := pa.lerp(pb, t)
		rings.append({"pos": Vector3(p.x, top + sin(t * PI) * 0.8, p.z), "dir": dir})

func _inward(isl: int, from: Vector3, away: Vector3) -> Vector3:
	var d := Vector2(from.x - away.x, from.z - away.z).normalized()
	for k in [2.5, 2.0, 1.5, 1.0, 0.0]:
		var q: Vector2 = Vector2(from.x, from.z) + d * k
		var i := idx(int(floor(q.x)), int(floor(q.y)))
		if inb(int(floor(q.x)), int(floor(q.y))) and kind[i] == T_GROUND and island[i] == isl:
			return Vector3(floor(q.x) + 0.5, level[i] * LEVEL, floor(q.y) + 0.5)
	return from

var shrine_spots: Array = []     # Vector3
var break_spots: Array = []      # {pos, kind: crate | pot | barrel}
var weapon_spots: Array = []     # Vector3, a found weapon lying in the open
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
	var n_exits := 3 if islands.size() <= 8 else 5
	var step := maxi(1, outer.size() / n_exits)
	var off := rng.randi_range(0, outer.size() - 1)
	var order: Array = []
	for k in n_exits:
		var cand: int = outer[(off + k * step) % outer.size()]
		if not order.has(cand): order.append(cand)
	for ii in outer:
		if not order.has(ii): order.append(ii)
	for ii in order:
		if portal_spots.size() >= n_exits:
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
	# crates, pots and barrels in little clusters, and a few better weapons lying around
	break_spots.clear(); weapon_spots.clear()
	for ii in islands.size():
		var n_b := 2 + rng.randi_range(0, 2) + (1 if islands[ii]["cells"].size() > 140 else 0)
		for _k in n_b:
			var p: Vector3 = pick.call(ii, 2, 12)
			if p == Vector3.INF:
				continue
			var roll := rng.randf()
			var bk := "crate" if roll < 0.45 else ("pot" if roll < 0.75 else "barrel")
			break_spots.append({"pos": p, "kind": bk})
			if rng.randf() < 0.55:
				var q := _near(p, 1.0, rng.randf() * TAU, ii, taken)
				if q != Vector3.INF:
					break_spots.append({"pos": q, "kind": "pot" if bk != "pot" else "crate"})
		if ii > 0 and rng.randf() < 0.5:
			var wp: Vector3 = pick.call(ii, 2, 10)
			if wp != Vector3.INF:
				weapon_spots.append(wp)

## Angle of an island around the map centre.
func a0_of(isl: int) -> float:
	var c: Vector2 = islands[isl]["c"]
	return atan2(c.y - h / 2.0, c.x - w / 2.0)

# ------------------------------------------------------------------ meshes
func build_meshes() -> void:
	for c in get_children():
		c.queue_free()
	_assign_regions()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tn := FastNoiseLite.new(); tn.seed = rng.seed + 3; tn.frequency = 0.3
	_edge_noise = FastNoiseLite.new(); _edge_noise.seed = rng.seed + 17; _edge_noise.frequency = 0.21
	_corner_cache.clear()
	for z in h:
		for x in w:
			var i := idx(x, z)
			if kind[i] == T_VOID or bridge.has(i):
				continue
			var y := level[i] * LEVEL
			var bio := _bio(i)
			cur_bio = bio
			var cols := []
			for cv in [Vector2(x, z), Vector2(x + 1, z), Vector2(x + 1, z + 1), Vector2(x, z + 1)]:
				var v := tn.get_noise_2d(cv.x * 0.6, cv.y * 0.6) * 0.5 + 0.5
				var v2 := tn.get_noise_2d(cv.x * 2.1 + 40.0, cv.y * 2.1) * 0.5 + 0.5
				var col: Color = Color(bio["top"]).lerp(bio["top2"], v).lerp(Color(bio["top"]).lightened(0.08), v2 * 0.35)
				col = col.lightened(0.035 * level[i])
				if not paint.is_empty():
					var pc := Color(0, 0, 0, 0); var pn := 0
					for t in [Vector2i(int(cv.x) - 1, int(cv.y) - 1), Vector2i(int(cv.x), int(cv.y) - 1), Vector2i(int(cv.x) - 1, int(cv.y)), Vector2i(int(cv.x), int(cv.y))]:
						if inb(t.x, t.y) and paint.has(idx(t.x, t.y)):
							pc += paint[idx(t.x, t.y)]; pn += 1
					if pn > 0:
						col = col.lerp(pc / pn, minf(1.0, pn / 2.0) * (0.85 + v2 * 0.15))
				cols.append(col)
			_quad4(st, Vector3(x, y, z) + _corner(x, z), Vector3(x + 1, y, z) + _corner(x + 1, z), Vector3(x + 1, y, z + 1) + _corner(x + 1, z + 1), Vector3(x, y, z + 1) + _corner(x, z + 1), Vector3.UP, cols)
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
			_quad(st, Vector3(x, bottom, z + 1) + _corner(x, z + 1), Vector3(x + 1, bottom, z + 1) + _corner(x + 1, z + 1), Vector3(x + 1, bottom, z) + _corner(x + 1, z), Vector3(x, bottom, z) + _corner(x, z), Vector3.DOWN, Color(bio["deep"]).darkened(0.3))
	_island_roots(st)
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = terrain_material()
	mi.name = "Ground"
	add_child(mi)
	_decorate()
	_build_air()

## The shared material for every island surface (see shaders/terrain.gdshader).
static var _terrain_mat: ShaderMaterial
static func terrain_material() -> ShaderMaterial:
	if _terrain_mat == null:
		_terrain_mat = ShaderMaterial.new()
		_terrain_mat.shader = load("res://shaders/terrain.gdshader")
	return _terrain_mat

## Island outlines don't follow the tile grid: every corner on an island's edge is nudged a little,
## so coastlines and cliffs look carved instead of stacked. (Only what you see moves; walking still
## follows the tiles.)
var _edge_noise: FastNoiseLite
var _corner_cache := {}
func _corner(x: int, z: int) -> Vector3:
	var key := x * 100003 + z
	if _corner_cache.has(key):
		return _corner_cache[key]
	var off := Vector3.ZERO
	var edge := false
	for t in [Vector2i(x - 1, z - 1), Vector2i(x, z - 1), Vector2i(x - 1, z), Vector2i(x, z)]:
		if not inb(t.x, t.y) or kind[idx(t.x, t.y)] == T_VOID or bridge.has(idx(t.x, t.y)):
			edge = true; break
	if edge and _edge_noise:
		off = Vector3(_edge_noise.get_noise_2d(x * 1.7, z * 1.7), 0.0, _edge_noise.get_noise_2d(x * 1.7 + 91.0, z * 1.7 - 37.0)) * 0.5
	_corner_cache[key] = off
	return off

## Each island hangs a cluster of rocky roots underneath it: one big one in the middle and smaller
## ones scattered under the rest, so islands read as floating rocks rather than slabs.
func _island_roots(st: SurfaceTool) -> void:
	var rr := RandomNumberGenerator.new(); rr.seed = rng.seed + 29
	for ii in islands.size():
		var cells: Array = islands[ii].get("cells", [])
		if cells.is_empty():
			cells = []
			for i in kind.size():
				if island[i] == ii and kind[i] != T_VOID: cells.append(Vector2i(i % w, i / w))
		if cells.size() < 6:
			continue
		var bio: Dictionary = _isl_bio[ii] if ii < _isl_bio.size() else biome
		var cx := 0.0; var cz := 0.0; var lo := 1e9
		for c in cells:
			cx += c.x + 0.5; cz += c.y + 0.5
			var i := idx(c.x, c.y)
			lo = minf(lo, depth[i] + level[i] * LEVEL * 0.3)
		cx /= cells.size(); cz /= cells.size()
		var rad := sqrt(cells.size() / PI)
		var top_c: Color = Color(bio["side"]).darkened(0.25)
		var deep_c: Color = Color(bio["deep"]).darkened(0.2)
		_root(st, rr, Vector3(cx, lo + 0.6, cz), rad * 0.62, rad * rr.randf_range(1.0, 1.4) + 3.0, top_c, deep_c)
		var n := clampi(int(rad * 0.9), 2, 9)
		for _k in n:
			var c: Vector2i = cells[rr.randi_range(0, cells.size() - 1)]
			var i := idx(c.x, c.y)
			var b := depth[i] + level[i] * LEVEL * 0.3
			_root(st, rr, Vector3(c.x + 0.5, b + 0.4, c.y + 0.5), rr.randf_range(0.5, 1.2) + rad * 0.12, rr.randf_range(1.5, 4.0) + rad * 0.4, top_c, deep_c)

func _root(st: SurfaceTool, rr: RandomNumberGenerator, at: Vector3, r: float, length: float, c0: Color, c1: Color) -> void:
	var seg := 9
	var rings := 5
	var pts: Array = []
	var ph := rr.randf() * TAU
	var lean := Vector2(rr.randf_range(-0.15, 0.15), rr.randf_range(-0.15, 0.15)) * length
	for k in rings + 1:
		var t := float(k) / rings
		var ring: Array = []
		var rk := r * pow(1.0 - t, 1.25) * (1.0 if k < rings else 0.0)
		for j in seg:
			var a := ph + TAU * j / seg
			var jr := rk * rr.randf_range(0.75, 1.15)
			ring.append(at + Vector3(cos(a) * jr + lean.x * t * t, -length * t, sin(a) * jr + lean.y * t * t))
		pts.append(ring)
	for k in rings:
		var ca: Color = c0.lerp(c1, float(k) / rings)
		var cb: Color = c0.lerp(c1, float(k + 1) / rings)
		for j in seg:
			var a: Vector3 = pts[k][j]; var b: Vector3 = pts[k][(j + 1) % seg]
			var c: Vector3 = pts[k + 1][(j + 1) % seg]; var d: Vector3 = pts[k + 1][j]
			var nrm := (b - a).cross(d - a).normalized()
			if nrm.dot(Vector3(a.x - at.x, 0, a.z - at.z)) < 0.0: nrm = -nrm
			st.set_normal(nrm)
			st.set_color(ca); st.add_vertex(a)
			st.set_color(cb); st.add_vertex(c)
			st.set_color(ca); st.add_vertex(b)
			st.set_color(ca); st.add_vertex(a)
			st.set_color(cb); st.add_vertex(d)
			st.set_color(cb); st.add_vertex(c)

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
		Vector2i(1, 0): p0 = Vector3(x + 1, 0, z + 1) + _corner(x + 1, z + 1); p1 = Vector3(x + 1, 0, z) + _corner(x + 1, z)
		Vector2i(-1, 0): p0 = Vector3(x, 0, z) + _corner(x, z); p1 = Vector3(x, 0, z + 1) + _corner(x, z + 1)
		Vector2i(0, 1): p0 = Vector3(x, 0, z + 1) + _corner(x, z + 1); p1 = Vector3(x + 1, 0, z + 1) + _corner(x + 1, z + 1)
		_: p0 = Vector3(x + 1, 0, z) + _corner(x + 1, z); p1 = Vector3(x, 0, z) + _corner(x, z)
	# a grassy lip, then dirt fading into dark rock toward the bottom
	var lip := minf(0.18, top - lo)
	var grass: Color = Color(cur_bio["top2"]).darkened(0.12)
	var dirt: Color = cur_bio["side"]
	_band(st, p0, p1, top, top - lip, n, grass, grass)
	var mid := maxf(lo, top - lip - 1.2)
	_band(st, p0, p1, top - lip, mid, n, dirt, dirt.darkened(0.15))
	if mid > lo:
		_band(st, p0, p1, mid, lo, n, dirt.darkened(0.15), cur_bio["deep"] if to_void else dirt.darkened(0.3))

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

# ------------------------------------------------------------------ regions
## Big maps are split into regions with their own look: meadows, autumn woods, frost, red mesas,
## blossom groves. Each keeps a little of the tier's palette so the mood carries over.
const REGIONS := [
	{},
	{"top": Color("c99a4c"), "top2": Color("a97a3c"), "side": Color("8b5a3a"), "leaf": Color("e0743a")},
	{"top": Color("d2e2ea"), "top2": Color("aac6d6"), "side": Color("7a8aa0"), "deep": Color("2c3448"), "leaf": Color("8ac8d8")},
	{"top": Color("d8a86a"), "top2": Color("c08a50"), "side": Color("a4583a"), "deep": Color("3a2228"), "leaf": Color("9aa04a")},
	{"top": Color("7cbc6c"), "top2": Color("5c9c5c"), "side": Color("8b6d52"), "leaf": Color("ff9ac8")},
]
var cur_bio: Dictionary = {}
var _isl_bio: Array = []
func _assign_regions() -> void:
	_isl_bio.clear()
	var center := Vector2(w * 0.5, h * 0.5)
	var off := rng.randf() * TAU
	for ii in islands.size():
		var c: Vector2 = islands[ii]["c"]
		var reg := 0
		if w >= 120 and ii > 0:
			var a := fposmod(atan2(c.y - center.y, c.x - center.x) + off, TAU)
			reg = int(a / TAU * REGIONS.size()) % REGIONS.size()
		var b: Dictionary = biome.duplicate()
		var r: Dictionary = REGIONS[reg]
		for k in r:
			b[k] = Color(r[k]).lerp(Color(biome.get(k, r[k])), 0.22)
		islands[ii]["region"] = reg
		_isl_bio.append(b)

func _bio(i: int) -> Dictionary:
	var ii := island[i] if i >= 0 and i < island.size() else -1
	return _isl_bio[ii] if ii >= 0 and ii < _isl_bio.size() else biome

## Wind roads as ribbons of flowing streaks; updrafts as glowing columns of rising air.
func _build_air() -> void:
	var wsh: Shader = load("res://shaders/wind.gdshader")
	for wd in winds:
		var a: Vector3 = wd["a"]; var b: Vector3 = wd["b"]
		var d := b - a
		var len := d.length()
		for k in 3:
			var mi := MeshInstance3D.new()
			var qm := QuadMesh.new(); qm.size = Vector2(len, 2.4 if k == 0 else 1.4)
			mi.mesh = qm
			var mat := ShaderMaterial.new(); mat.shader = wsh
			mat.set_shader_parameter("color", Color(0.75, 0.95, 1.0, 0.32 if k == 0 else 0.22))
			mat.set_shader_parameter("tiles", maxf(2.0, len / 3.0))
			mat.set_shader_parameter("speed", 0.9 + 0.25 * k)
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			# lay the quad along the road: flat for the main ribbon, tilted for the two wisps
			var fwd := d.normalized()
			var side := fwd.cross(Vector3.UP).normalized()
			var up := side.cross(fwd).normalized()
			var roll: float = [0.0, 1.0, -1.0][k]
			# QuadMesh faces +z; turn it so its width runs along the road and it lies flat
			mi.basis = Basis(fwd, up.rotated(fwd, roll * 0.9), -side.rotated(fwd, roll * 0.9))
			mi.position = (a + b) * 0.5 + Vector3(0, -0.2 + k * 0.25, 0)
	for u in updrafts:
		var c: Vector3 = u["pos"]
		var hgt: float = float(u["top"]) - c.y + 6.0
		var col := MeshInstance3D.new()
		col.mesh = Models.cyl(float(u["r"]), float(u["r"]) * 1.15, hgt, 18)
		var mat := ShaderMaterial.new(); mat.shader = wsh
		mat.set_shader_parameter("color", Color(1.0, 0.95, 0.75, 0.22))
		mat.set_shader_parameter("tiles", hgt / 2.5)
		mat.set_shader_parameter("speed", 1.4)
		col.material_override = mat
		col.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		col.position = Vector3(c.x, c.y - 6.0 + hgt * 0.5, c.z)
		add_child(col)
		var p := CPUParticles3D.new()
		p.amount = 18; p.lifetime = 1.6; p.preprocess = 1.6
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE; p.emission_sphere_radius = float(u["r"]) * 0.8
		p.direction = Vector3.UP; p.spread = 8.0; p.initial_velocity_min = 5.0; p.initial_velocity_max = 8.0
		p.gravity = Vector3.ZERO
		p.mesh = Models.sphere(0.06, 4)
		p.material_override = Models.glow_mat(Color(1.0, 0.96, 0.8, 0.8))
		p.position = Vector3(c.x, c.y - 3.0, c.z)
		add_child(p)

func _decorate() -> void:
	var drng := RandomNumberGenerator.new(); drng.seed = rng.seed + 11
	var deco := Node3D.new(); deco.name = "Deco"; add_child(deco)
	for z in h:
		for x in w:
			var i := idx(x, z)
			if kind[i] != T_BLOCK or no_deco.has(i) or walls.has(i):
				continue
			var y := level[i] * LEVEL
			var n: Node3D
			if drng.randf() < 0.5:
				var reg := int(islands[island[i]].get("region", 0)) if island[i] >= 0 and island[i] < islands.size() else 0
				n = Models.tree(drng, _bio(i)["leaf"], "pine" if reg == 2 or drng.randf() < 0.25 else ("blossom" if reg == 4 and drng.randf() < 0.6 else "round"))
			else:
				n = Models.rock(drng, drng.randf_range(0.9, 1.25))
			n.position = Vector3(x + 0.5, y, z + 0.5)
			deco.add_child(n)
	# stone walls, batched: a block per tile with a cap stone on top
	var wlist: Array = []
	for wi in walls:
		if kind[wi] == T_BLOCK:
			wlist.append(wi)
	if wlist.size() > 0:
		wall_mat = ShaderMaterial.new()
		wall_mat.shader = load("res://shaders/wall.gdshader")
		for part_i in 2:
			var wm := MultiMesh.new(); wm.transform_format = MultiMesh.TRANSFORM_3D; wm.use_colors = true
			wm.mesh = Models.box(1.0, 2.0, 1.0) if part_i == 0 else Models.box(1.08, 0.22, 1.08)
			wm.instance_count = wlist.size()
			for k in wlist.size():
				var wi: int = wlist[k]
				var wx := wi % w; var wz := wi / w
				var y0 := level[wi] * LEVEL
				var tr := Transform3D(Basis(), Vector3(wx + 0.5, y0 + (1.0 if part_i == 0 else 2.05), wz + 0.5))
				wm.set_instance_transform(k, tr)
				var shade := drng.randf_range(-0.06, 0.06)
				wm.set_instance_color(k, Color("837d74").lightened(shade) if part_i == 0 else Color("a39c90").lightened(shade))
			var wmi := MultiMeshInstance3D.new(); wmi.multimesh = wm
			wmi.material_override = wall_mat
			deco.add_child(wmi)
	# tall grass to hide in: dense clumps of long blades that sway
	var blist: Array = []
	for bi in bush:
		if kind[bi] == T_GROUND:
			for _k in 4: blist.append(bi)
	if blist.size() > 0:
		var bm := MultiMesh.new(); bm.transform_format = MultiMesh.TRANSFORM_3D; bm.use_colors = true
		bm.mesh = Models.grass_mesh(true)
		bm.instance_count = blist.size()
		for k in blist.size():
			var bi: int = blist[k]
			var bx := bi % w; var bz := bi / w
			var p := Vector3(bx + drng.randf_range(0.1, 0.9), level[bi] * LEVEL, bz + drng.randf_range(0.1, 0.9))
			var sc := drng.randf_range(0.85, 1.2)
			bm.set_instance_transform(k, Transform3D(Basis(Vector3.UP, drng.randf() * TAU).scaled(Vector3(sc, sc * drng.randf_range(0.9, 1.25), sc)), p))
			bm.set_instance_color(k, Color(_bio(bi)["leaf"]).lerp(Color(_bio(bi)["top"]), 0.35).darkened(drng.randf_range(0.0, 0.18)))
		var bmi := MultiMeshInstance3D.new(); bmi.multimesh = bm
		bmi.material_override = Models.grass_material(0.16)
		bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bmi.name = "Bushes"
		deco.add_child(bmi)
	# short grass, flowers and pebbles over open ground, batched
	var xs: Array = []
	var fl: Array = []
	var pb: Array = []
	for z in h:
		for x in w:
			var i := idx(x, z)
			if kind[i] != T_GROUND or bridge.has(i) or bush.has(i):
				continue
			var painted := paint.has(i)
			for _k in (1 if painted else 3):
				if drng.randf() < (0.15 if painted else 0.55):
					xs.append([Vector3(x + drng.randf(), level[i] * LEVEL, z + drng.randf()), drng.randf(), i])
			if not painted and drng.randf() < 0.07:
				fl.append([Vector3(x + drng.randf(), level[i] * LEVEL, z + drng.randf()), i])
			if drng.randf() < (0.06 if edge_dist(x, z, 2) < 2 else 0.015):
				pb.append(Vector3(x + drng.randf(), level[i] * LEVEL, z + drng.randf()))
	var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.use_colors = true; mm.mesh = Models.grass_mesh(false)
	mm.instance_count = xs.size()
	for k in xs.size():
		var sc := 0.7 + float(xs[k][1]) * 0.6
		mm.set_instance_transform(k, Transform3D(Basis(Vector3.UP, drng.randf() * TAU).scaled(Vector3(sc, sc, sc)), xs[k][0]))
		var tb := _bio(int(xs[k][2]))
		mm.set_instance_color(k, Color(tb["top"]).lerp(Color(tb["top2"]), drng.randf()).lightened(0.05))
	var mmi := MultiMeshInstance3D.new(); mmi.multimesh = mm
	mmi.material_override = Models.grass_material(0.08)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.name = "Grass"
	deco.add_child(mmi)
	if fl.size() > 0:
		var fcols := [Color("fff3a8"), Color("ff9ac8"), Color("ffffff"), Color("b8a6ff"), Color("ffb070"), Color("8fd8ff")]
		var fm := MultiMesh.new(); fm.transform_format = MultiMesh.TRANSFORM_3D; fm.use_colors = true; fm.mesh = Models.flower_mesh()
		fm.instance_count = fl.size()
		for k in fl.size():
			fm.set_instance_transform(k, Transform3D(Basis(Vector3.UP, drng.randf() * TAU).scaled(Vector3.ONE * drng.randf_range(0.8, 1.3)), fl[k][0]))
			fm.set_instance_color(k, fcols[drng.randi_range(0, fcols.size() - 1)])
		var fmi := MultiMeshInstance3D.new(); fmi.multimesh = fm
		fmi.material_override = Models.grass_material(0.05, true)
		fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		deco.add_child(fmi)
	if pb.size() > 0:
		var pm2 := MultiMesh.new(); pm2.transform_format = MultiMesh.TRANSFORM_3D; pm2.use_colors = true
		var sm := SphereMesh.new(); sm.radius = 0.1; sm.height = 0.12; sm.radial_segments = 6; sm.rings = 3
		pm2.mesh = sm
		pm2.instance_count = pb.size()
		for k in pb.size():
			var sc := drng.randf_range(0.6, 1.6)
			pm2.set_instance_transform(k, Transform3D(Basis(Vector3.UP, drng.randf() * TAU).scaled(Vector3(sc * drng.randf_range(0.8, 1.4), sc, sc)), pb[k] + Vector3(0, 0.02, 0)))
			pm2.set_instance_color(k, Color("9a948c").lerp(Color("6f6a73"), drng.randf()))
		var pmi := MultiMeshInstance3D.new(); pmi.multimesh = pm2
		pmi.material_override = Models.vtoon()
		pmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		deco.add_child(pmi)
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
	var defs: Array = [["main", Vector2(38, 32), Vector2(14, 11)]]
	for k in Data.ISLES:
		defs.append([k, Data.ISLES[k]["c"], Data.ISLES[k]["r"]])
	make_islands(seed_val, 72, 50, defs)

## Flat islands for social places: defs is [[id, centre, radii], ...].
func make_islands(seed_val: int, ww: int, hh: int, defs: Array) -> void:
	rng.seed = seed_val
	w = ww; h = hh
	kind.resize(w * h); kind.fill(T_VOID)
	level.resize(w * h); level.fill(0)
	island.resize(w * h); island.fill(-1)
	depth.resize(w * h); depth.fill(0.0)
	islands.clear(); pads.clear(); spawns.clear(); portal_spots.clear(); chest_spots.clear(); camp_spots.clear(); wild_spots.clear()
	bridge.clear()
	var shape := FastNoiseLite.new(); shape.seed = seed_val; shape.frequency = 0.12
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
