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
const BIG_ISLANDS := 19          # fewer, much larger islands, like Supervive's big landmasses
const GLIDE_GAP := 14.0      # islands closer than this (edge to edge) are reached by gliding, not pads
var spawns: Array = []       # Vector3 candidates at island edges
var portal_spots: Array = []
var chest_spots: Array = []
var camp_spots: Array = []
var wild_spots: Array = []
var no_deco := {}
var paint := {}          # tile index -> colour for paths and soil, blended at the corners
var clouds: Array = []
var sheer := {}          # tile index -> true: a smooth cliff rim you can't grab (authored maps)
var lip := {}            # tile index -> true: a rim with a stone lip you can grab (authored maps)
var labels: Array = []   # {name, pos: Vector3, kind: "poi" | "choke"} for the map and minimap
var layout_id := ""      # "" for a generated map, else the authored layout's id
var dyn_walls: Array = []  # barrier walls from abilities (see Verbs): some block movement too
var authored_portals: Array = []   # Vector2 tile spots from an authored layout, in opening order
## The ways out an authored layout places (see Exits): {kind: "dock" | "hatch" | "outpost", pos: Vector3,
## out: Vector2 (a dock's way out over the abyss, optional), walled: bool}. Empty: Exits works them out.
var exit_defs: Array = []
## Boss lairs (see Lairs): walled arenas with one gate, each holding a boss and its Rare Egg.
## {id, name, boss, c: Vector2 (centre), half (tiles from the centre to the wall), gate ("n"/"s"/"e"/"w"),
##  gate_tiles: Array[Vector2i], out: Vector2 (out through the gate), island, y (floor height), entry: Array}
var lair_defs: Array = []
## The sky train's track, when the layout has one: {pts: PackedVector3Array (x, deck height, z) every
## TRAIN_STEP tiles round the loop, len, stations: [arc length], names: [String], spec: the layout's train}
var train_route: Dictionary = {}
const TRAIN_STEP := 0.5
const TRAIN_DIVE := -4.6       # under a bridge the track dips this low, so the cars pass beneath it
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
	if stairs.has(i):
		# a flight of stairs up to the next terrace: the ground rises smoothly across the tile
		var d: Vector2i = stairs[i]
		var fx := x - ix; var fz := z - iz
		var t: float = fx if d.x > 0 else (1.0 - fx if d.x < 0 else (fz if d.y > 0 else 1.0 - fz))
		return (level[i] + clampf(t, 0.0, 1.0)) * LEVEL
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
	if not dyn_walls.is_empty():
		var wb: float = Verbs.wall_blocks(dyn_walls, x, z, r, y)
		if wb > 0.0:
			return wb
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
	for wl in dyn_walls:
		if y > float(wl["y"]) - 0.3 and y < float(wl["y"]) + Verbs.WALL_H and Geometry2D.segment_intersects_segment(Vector2(a.x, a.z), Vector2(b.x, b.z), wl["a"], wl["b"]) != null:
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
	sheer.clear(); lip.clear(); labels.clear(); layout_id = ""; authored_portals.clear(); train_route = {}; props.clear(); exit_defs.clear()
	var shape := FastNoiseLite.new(); shape.seed = seed_val; shape.frequency = 0.09
	var terr := FastNoiseLite.new(); terr.seed = seed_val + 7; terr.frequency = 0.07
	# island centres: a big heart island in the middle and a ring of outer islands around it,
	# evenly spaced by angle so every side of the map has somewhere to land
	# big maps: a few large landmasses instead of many little rocks
	var bigmap := w >= 180
	var centers: Array = [{"c": Vector2(w / 2.0, h / 2.0), "r": rng.randf_range(15.0, 17.0) if bigmap else rng.randf_range(8.5, 9.8)}]
	var n_outer := n_islands - 1
	var a0 := rng.randf() * TAU
	# big maps get a second, wider ring of islands beyond the first
	var n_inner := mini(n_outer, 6)
	var n_far := n_outer - n_inner
	for k in n_inner:
		var r := rng.randf_range(9.0, 11.0) if bigmap else rng.randf_range(5.4, 7.2)
		var ang := a0 + TAU * k / n_inner + rng.randf_range(-0.22, 0.22)
		var dist: float = centers[0]["r"] + r + (rng.randf_range(8.0, 11.0) if bigmap else rng.randf_range(4.0, 6.0))
		var c := Vector2(w / 2.0, h / 2.0) + Vector2(cos(ang), sin(ang)) * dist
		c.x = clampf(c.x, r + 2, w - r - 2); c.y = clampf(c.y, r + 2, h - r - 2)
		centers.append({"c": c, "r": r})
	# the biggest maps add a third, outermost ring of larger islands
	var n_outmost := 0
	if w >= 180:
		n_outmost = maxi(0, n_far - 13)
		n_far -= n_outmost
	for k in n_far:
		var r := rng.randf_range(9.0, 11.5) if bigmap else rng.randf_range(6.0, 8.6)
		var ang := a0 + PI / maxf(1.0, n_far) + TAU * k / n_far + rng.randf_range(-0.12, 0.12)
		var dist: float = centers[0]["r"] + (44.0 if bigmap else 32.0) + r * 0.5 + rng.randf_range(0.0, 5.0)
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
	lair_defs.clear()
	_place_lairs()
	if bigmap:
		_place_compounds()
	_place_stairs()

## On the big islands the point of interest sits inside a walled compound: a square of stone walls
## with a gate in each side and a squat tower at each corner, so each island reads as one place
## (a fort, a ruin, a vault) rather than a scatter of rocks.
func _place_compounds() -> void:
	var keep: Array = spawns + portal_spots + wild_spots
	for c in chest_spots: keep.append(c["pos"])
	for c in camp_spots: keep.append(c["pos"])
	for pd in pads: keep.append(pd["pos"])
	for ii in islands.size():
		var cells: Array = islands[ii]["cells"]
		if cells.size() < 260 or islands[ii].get("lair", false):
			continue
		var poi := _poi(ii)
		if poi == Vector3.INF:
			continue
		var half := 7 if islands[ii]["role"] == "heart" else 5
		var cx := int(floor(poi.x)); var cz := int(floor(poi.z))
		var ring: Array = []
		for k in range(-half, half + 1):
			for e in [Vector2i(k, -half), Vector2i(k, half), Vector2i(-half, k), Vector2i(half, k)]:
				if absi(k) <= 1:
					continue          # a three-wide gate in the middle of each side
				ring.append(e)
		# corner towers: the corners thicken into 2x2 blocks
		for sx in [-1, 1]:
			for sz in [-1, 1]:
				ring.append(Vector2i(sx * (half - 1), sz * (half - 1)))
		for e in ring:
			var q := Vector2i(cx + e.x, cz + e.y)
			var ok := true
			for kp in keep:
				if Vector2((kp as Vector3).x - q.x - 0.5, (kp as Vector3).z - q.y - 0.5).length() < 1.6:
					ok = false; break
			if ok:
				_wall_at(q, ii)

## Stairs: where one terrace steps up to the next, some edges get a flight of steps so you can
## walk up instead of hopping, like the stone stairs between levels in Supervive.
var stairs := {}          # tile index -> Vector2i pointing up the stairs
func _place_stairs() -> void:
	stairs.clear()
	var srng := RandomNumberGenerator.new(); srng.seed = rng.seed + 41
	var spots_all: Array = spawns + portal_spots
	for c in chest_spots: spots_all.append(c["pos"])
	for c in camp_spots: spots_all.append(c["pos"])
	for ii in islands.size():
		var cells: Array = islands[ii]["cells"]
		var cands: Array = []
		for c in cells:
			var i := idx(c.x, c.y)
			if kind[i] != T_GROUND or bridge.has(i):
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var up := Vector2i(c.x + d.x, c.y + d.y)
				var back := Vector2i(c.x - d.x, c.y - d.y)
				if not inb(up.x, up.y) or not inb(back.x, back.y):
					continue
				var iu := idx(up.x, up.y); var ib := idx(back.x, back.y)
				# exactly one terrace up ahead, the same level behind to walk in from
				if kind[iu] != T_GROUND or kind[ib] != T_GROUND or level[iu] != level[i] + 1 or level[ib] != level[i]:
					continue
				cands.append([c, d])
		cands.shuffle()
		var placed: Array = []
		var want := clampi(cells.size() / 45, 1, 6) if layout_id == "" else clampi(cells.size() / 220, 2, 8)
		for cd in cands:
			if placed.size() >= want: break
			var c: Vector2i = cd[0]
			var ok := true
			for p in placed:
				if (p as Vector2i).distance_to(c) < 6.0: ok = false
			for sp in spots_all:
				if Vector2((sp as Vector3).x - c.x - 0.5, (sp as Vector3).z - c.y - 0.5).length() < 2.0: ok = false
			if not ok: continue
			stairs[idx(c.x, c.y)] = cd[1]
			placed.append(c)
			if layout_id != "":
				# authored maps get wide, readable ramps: the flight spreads sideways along the terrace edge
				var dd: Vector2i = cd[1]
				var side := Vector2i(dd.y, dd.x)
				for k in [1, -1, 2, -2]:
					var q: Vector2i = c + side * k
					var up2 := q + dd; var back2 := q - dd
					if not inb(q.x, q.y) or not inb(up2.x, up2.y) or not inb(back2.x, back2.y): continue
					var iq := idx(q.x, q.y)
					if kind[iq] == T_GROUND and kind[idx(up2.x, up2.y)] == T_GROUND and kind[idx(back2.x, back2.y)] == T_GROUND \
							and level[idx(up2.x, up2.y)] == level[iq] + 1 and level[idx(back2.x, back2.y)] == level[iq] and not bridge.has(iq):
						stairs[iq] = dd

var wall_mat: ShaderMaterial = null   # walls fade where they hide the player
var walls := {}           # tile index -> true: built stone walls (drawn as walls, not rocks)
var bush := {}            # tile index -> true: tall grass you can hide in
var props := {}           # blocker tile index -> what stands there: "ruin" (an old pillar) or "camp" (crates); else a tree or rock

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
				updrafts.append({"pos": Vector3(p.x, base, p.y), "r": 1.6, "top": float(top_lvl) * LEVEL + 1.6})
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
	if islands[isl].has("poi_at"):
		# authored maps say exactly where the point of interest is
		var pa: Vector2 = islands[isl]["poi_at"]
		var ix := int(floor(pa.x)); var iz := int(floor(pa.y))
		if inb(ix, iz) and kind[idx(ix, iz)] != T_VOID and island[idx(ix, iz)] == isl:
			return Vector3(ix + 0.5, level[idx(ix, iz)] * LEVEL, iz + 0.5)
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
func _pillars(p: Vector3, offs: Array, what := "") -> void:
	for o in offs:
		var x := int(floor(p.x + o.x)); var z := int(floor(p.z + o.y))
		if inb(x, z) and kind[idx(x, z)] == T_GROUND and edge_dist(x, z, 2) >= 2:
			kind[idx(x, z)] = T_BLOCK
			if what != "": props[idx(x, z)] = what

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

## What a point of interest holds, by its role (chests, camps, wild kin, a shrine).
func _dress_poi(ii: int, role: String, poi: Vector3, toward_mid: float, taken: Dictionary) -> void:
	match role:
		"heart":
			# the vault: the best chest in the middle, ringed by rocks, two guard camps
			heart_spot = poi
			chest_spots.append({"pos": poi, "tier": 2})
			_pillars(poi, [Vector2(3.2, 3.2), Vector2(-3.2, 3.2), Vector2(3.2, -3.2), Vector2(-3.2, -3.2)], "ruin")
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
			_pillars(poi, [Vector2(cos(toward_mid + 1.3), sin(toward_mid + 1.3)) * 2.2, Vector2(cos(toward_mid - 1.3), sin(toward_mid - 1.3)) * 2.2], "camp")
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
		"landing":
			# an outer landing where squads come down and gates open: two chests, no monsters
			for k in 2:
				var ch := _near(poi, 2.8, toward_mid + PI * (0.5 + k), ii, taken)
				if ch != Vector3.INF: chest_spots.append({"pos": ch, "tier": 0})
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
			_pillars(poi, [Vector2(2.2, 0), Vector2(-2.2, 0), Vector2(0, 2.2), Vector2(0, -2.2)], "ruin")
			var ch := _near(poi, 3.6, toward_mid + PI, ii, taken)
			if ch != Vector3.INF: chest_spots.append({"pos": ch, "tier": 0})

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
		_dress_poi(ii, role, poi, toward_mid, taken)
		# authored islands can hold more places than their main one: big regions get several
		for ex in islands[ii].get("extras", []):
			var ep := Vector3(float(ex[0]) + 0.5, 0, float(ex[1]) + 0.5)
			if is_void(ep.x, ep.z):
				continue
			ep.y = ground_at(ep.x, ep.z)
			_clear_around(ep, 2.0)
			taken[Vector2i(int(ep.x), int(ep.z))] = true
			_dress_poi(ii, String(ex[2]), ep, atan2(mid.y - ep.z, mid.x - ep.x), taken)
			if (ex as Array).size() > 3:
				labels.append({"name": String(ex[3]), "pos": ep, "kind": "poi", "role": String(ex[2]), "height": ep.y})
	# big islands get a second, smaller find on their far side so the extra ground isn't empty
	if w >= 180:
		for ii in range(1, islands.size()):
			if islands[ii]["cells"].size() < 260 or islands[ii]["role"] == "landing":
				continue
			var poi := _poi(ii)
			if poi == Vector3.INF:
				continue
			var away := atan2(poi.z - mid.y, poi.x - mid.x)
			var p2 := _near(poi, 9.5, away, ii, taken)
			if p2 == Vector3.INF:
				continue
			chest_spots.append({"pos": p2, "tier": 0})
			var cp2 := _near(p2, 2.6, away + PI * 0.5, ii, taken)
			if cp2 != Vector3.INF: camp_spots.append({"pos": cp2, "island": ii, "kind": "light"})
	# authored maps put their exits exactly where the layout says, in the order they open
	if not authored_portals.is_empty():
		for ap in authored_portals:
			var ax := int(floor((ap as Vector2).x)); var az := int(floor((ap as Vector2).y))
			if inb(ax, az) and kind[idx(ax, az)] != T_VOID:
				if kind[idx(ax, az)] == T_BLOCK: kind[idx(ax, az)] = T_GROUND
				portal_spots.append(Vector3(ax + 0.5, level[idx(ax, az)] * LEVEL, az + 0.5))
				taken[Vector2i(ax, az)] = true
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
		if portal_spots.size() >= n_exits or not authored_portals.is_empty():
			break
		var p: Vector3 = pick.call(ii, 2, 7)
		if p != Vector3.INF:
			portal_spots.append(p)
	# hunters land on the outer islands, two spots each near the edge (never on a high perch)
	for ii in range(1, islands.size()):
		if islands[ii].get("perch", false):
			continue
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
const TerrainMesh := preload("res://scripts/match/terrain_mesh.gd")
const RuinWalls := preload("res://scripts/match/ruin_walls.gd")
var _rims: Array = []               # grassy rim spots from the terrain mesher, for the grass fringe
var under := PackedFloat32Array()   # per tile: the height of the island's rocky underside (visual only)

func build_meshes() -> void:
	for c in get_children():
		c.queue_free()
	_assign_regions()
	# the ground, cliffs, stairs and undersides: traced as clean contours, see terrain_mesh.gd
	var tm := TerrainMesh.new(self)
	var mesh := tm.build()
	under = tm.under
	_rims = tm.rims
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_island_roots(st)
	var roots := st.commit()
	var mat: ShaderMaterial = terrain_material().duplicate()
	mat.set_shader_parameter("height_tex", tm.height_texture())
	mat.set_shader_parameter("map_size", Vector2(w, h))
	mat.set_shader_parameter("use_ao", true)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.name = "Ground"
	add_child(mi)
	var ri := MeshInstance3D.new()
	ri.mesh = roots
	ri.material_override = mat
	ri.name = "Roots"
	ri.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ri)
	_decorate()
	_build_air()

## Scatter batches split into 16x16-tile chunks, so the camera only draws the ones it can see.
func _chunked(parent: Node3D, items: Array, mesh: Mesh, mat: Material, label: String, shadows := false) -> void:
	var by := {}
	for it in items:
		var o: Vector3 = (it[0] as Transform3D).origin
		var key := Vector2i(int(o.x) / 16, int(o.z) / 16)
		if not by.has(key): by[key] = []
		by[key].append(it)
	for key in by:
		var list: Array = by[key]
		var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.use_colors = true; mm.mesh = mesh
		mm.instance_count = list.size()
		for k in list.size():
			mm.set_instance_transform(k, list[k][0])
			mm.set_instance_color(k, list[k][1])
		var mi := MultiMeshInstance3D.new(); mi.multimesh = mm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.name = "%s_%d_%d" % [label, key.x, key.y]
		parent.add_child(mi)

## The shared material for every island surface (see shaders/terrain.gdshader).
static var _terrain_mat: ShaderMaterial
static func terrain_material() -> ShaderMaterial:
	if _terrain_mat == null:
		_terrain_mat = ShaderMaterial.new()
		_terrain_mat.shader = load("res://shaders/terrain.gdshader")
	return _terrain_mat

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
		# the tip of the rock cone, and a few smaller spurs further out, all hanging from the underside
		var lo := 1e9; var tip := Vector2i(-1, -1)
		for c in cells:
			var i := idx(c.x, c.y)
			if kind[i] != T_VOID and i < under.size() and under[i] < lo:
				lo = under[i]; tip = c
		if tip.x < 0:
			continue
		var rad := sqrt(cells.size() / PI)
		var top_c: Color = Color(bio["side"]).darkened(0.25).lerp(Color(bio["deep"]), 0.5)
		var deep_c: Color = Color(bio["deep"]).darkened(0.2)
		_root(st, rr, Vector3(tip.x + 0.5, lo + 1.2, tip.y + 0.5), clampf(rad * 0.2, 0.8, 2.6), minf(rad * rr.randf_range(0.25, 0.4) + 2.0, 8.0), top_c, deep_c)
		var n := clampi(int(rad * 0.5), 1, 7)
		for _k in n:
			var c: Vector2i = cells[rr.randi_range(0, cells.size() - 1)]
			var i := idx(c.x, c.y)
			if kind[i] == T_VOID or edge_dist(c.x, c.y, 3) < 3:
				continue
			_root(st, rr, Vector3(c.x + 0.5, under[i] + 0.5, c.y + 0.5), rr.randf_range(0.4, 0.9) + rad * 0.05, rr.randf_range(1.2, 3.0) + rad * 0.15, top_c, deep_c)

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
			st.set_uv(Vector2(4.0, 0.0))
			st.set_color(ca); st.add_vertex(a)
			st.set_color(ca); st.add_vertex(b)
			st.set_color(cb); st.add_vertex(c)
			st.set_color(ca); st.add_vertex(a)
			st.set_color(cb); st.add_vertex(c)
			st.set_color(cb); st.add_vertex(d)

# ------------------------------------------------------------------ regions
## Big maps are split into regions with their own look: meadows, autumn woods, frost, red mesas,
## blossom groves. Each keeps a little of the tier's palette so the mood carries over.
const REGIONS := [
	{},
	{"top": Color("b08a50"), "top2": Color("94723f"), "side": Color("8b5a3a"), "leaf": Color("e0743a")},
	{"top": Color("d2e2ea"), "top2": Color("aac6d6"), "side": Color("7a8aa0"), "deep": Color("2c3448"), "leaf": Color("8ac8d8")},
	{"top": Color("c49a66"), "top2": Color("a8804e"), "side": Color("a4583a"), "deep": Color("3a2228"), "leaf": Color("9aa04a")},
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
		if islands[ii].has("region_fixed"):
			reg = int(islands[ii]["region_fixed"]) % REGIONS.size()
		elif w >= 120 and ii > 0:
			var a := fposmod(atan2(c.y - center.y, c.x - center.x) + off, TAU)
			reg = int(a / TAU * REGIONS.size()) % REGIONS.size()
		var b: Dictionary = biome.duplicate()
		var r: Dictionary = REGIONS[reg]
		if islands[ii].has("biome_colors"):
			# an authored biome region: its own palette, with a touch of the tier's mood
			var bc: Dictionary = islands[ii]["biome_colors"]
			r = {}
			for k in bc: r[k] = Color(String(bc[k]))
		for k in r:
			b[k] = Color(r[k]).lerp(Color(biome.get(k, r[k])), 0.12 if islands[ii].has("biome_colors") else 0.22)
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
		var cm := Models.plain_cyl(float(u["r"]), float(u["r"]) * 1.15, hgt, 18)
		cm.cap_top = false; cm.cap_bottom = false
		col.mesh = cm
		var mat := ShaderMaterial.new(); mat.shader = load("res://shaders/updraft.gdshader")
		mat.set_shader_parameter("tiles", hgt / 4.0)
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
	var packed := {}      # imported models, batched: group key -> {mesh, mat, items}
	for z in h:
		for x in w:
			var i := idx(x, z)
			if kind[i] != T_BLOCK or no_deco.has(i) or walls.has(i):
				continue
			var y := level[i] * LEVEL
			var n: Node3D
			var by_shrine := false
			for sp in shrine_spots:
				if Vector2(sp.x - x - 0.5, sp.z - z - 0.5).length() < 2.6: by_shrine = true
			var what: String = props.get(i, "")
			if what == "":
				what = "tree" if drng.randf() < 0.5 and not by_shrine else "rock"
			if _pack_prop(packed, what, i, Vector3(x + 0.5, y, z + 0.5), drng):
				if what in ["tree", "rock"]:
					_undergrowth(packed, x, z, drng)
				continue
			if what == "tree":
				var reg := int(islands[island[i]].get("region", 0)) if island[i] >= 0 and island[i] < islands.size() else 0
				n = Models.tree(drng, _bio(i)["leaf"], "pine" if reg == 2 or drng.randf() < 0.25 else ("blossom" if reg == 4 and drng.randf() < 0.6 else "round"))
			else:
				n = Models.rock(drng, drng.randf_range(0.9, 1.25))
			n.position = Vector3(x + 0.5, y, z + 0.5)
			deco.add_child(n)
	if Assets.on():
		_cliff_rocks(packed, drng)
	for key in packed:
		var g: Dictionary = packed[key]
		_chunked(deco, g["items"], g["mesh"], g["mat"], String(g["label"]), bool(g["shadows"]))
	# stone walls: coursed ruin masonry following each run (see ruin_walls.gd)
	if not walls.is_empty():
		wall_mat = ShaderMaterial.new()
		wall_mat.shader = load("res://shaders/wall.gdshader")
		for wmi in RuinWalls.new(self).build(wall_mat):
			deco.add_child(wmi)
	# tall grass to hide in: dense clumps of long blades that sway
	var tall: Array = []
	for bi in bush:
		if kind[bi] == T_GROUND:
			var bx: int = bi % w; var bz: int = bi / w
			for _k in 4:
				var p := Vector3(bx + drng.randf_range(0.1, 0.9), level[bi] * LEVEL, bz + drng.randf_range(0.1, 0.9))
				var sc := drng.randf_range(0.85, 1.2)
				tall.append([Transform3D(Basis(Vector3.UP, drng.randf() * TAU).scaled(Vector3(sc, sc * drng.randf_range(0.9, 1.25), sc)), p),
					Color(_bio(bi)["leaf"]).lerp(Color(_bio(bi)["top"]), 0.35).darkened(drng.randf_range(0.0, 0.18))])
	_chunked(deco, tall, Models.grass_mesh(true), Models.grass_material(0.16), "Bushes")
	# short grass, flowers and pebbles over open ground, batched in chunks so off-screen ones are skipped
	var xs: Array = []
	var fl: Array = []
	var pb: Array = []
	var fcols := [Color("fff3a8"), Color("ff9ac8"), Color("ffffff"), Color("b8a6ff"), Color("ffb070"), Color("8fd8ff")]
	for z in h:
		for x in w:
			var i := idx(x, z)
			if kind[i] != T_GROUND or bridge.has(i) or bush.has(i):
				continue
			var painted := paint.has(i)
			var tb := _bio(i)
			for _k in (1 if painted else 2):
				if drng.randf() < (0.15 if painted else 0.6):
					var sc := 0.75 + drng.randf() * 0.6
					xs.append([Transform3D(Basis(Vector3.UP, drng.randf() * TAU).scaled(Vector3(sc, sc, sc)), Vector3(x + drng.randf(), level[i] * LEVEL, z + drng.randf())),
						Color(tb["top"]).lerp(Color(tb["top2"]), drng.randf()).lightened(0.05)])
			if not painted and drng.randf() < 0.07:
				fl.append([Transform3D(Basis(Vector3.UP, drng.randf() * TAU).scaled(Vector3.ONE * drng.randf_range(0.8, 1.3)), Vector3(x + drng.randf(), level[i] * LEVEL, z + drng.randf())),
					fcols[drng.randi_range(0, fcols.size() - 1)]])
			if drng.randf() < (0.06 if edge_dist(x, z, 2) < 2 else 0.015):
				pb.append(Vector3(x + drng.randf(), level[i] * LEVEL, z + drng.randf()))
	# a fringe of grass hanging over grassy terrace edges and coasts, so rims read soft and lived-in
	for rm in _rims:
		if drng.randf() > 0.6:
			continue
		var rp: Vector3 = rm[0]; var rn: Vector3 = rm[1]
		var tb2 := _bio(int(rm[2]))
		var sc2 := 0.8 + drng.randf() * 0.5
		var tilt := Basis(rn.cross(Vector3.UP).normalized(), -0.45) if rn.length() > 0.1 else Basis()
		xs.append([Transform3D(tilt * Basis(Vector3.UP, drng.randf() * TAU).scaled(Vector3(sc2, sc2 * 0.9, sc2)), rp + rn * 0.04 - Vector3(0, 0.03, 0)),
			Color(tb2["top"]).lerp(Color(tb2["top2"]), drng.randf()).lightened(0.08)])
	_chunked(deco, xs, Models.grass_mesh(false), Models.grass_material(0.08), "Grass")
	_chunked(deco, fl, Models.flower_mesh(), Models.grass_material(0.05, true), "Flowers")
	var pebbled := false
	if pb.size() > 0 and Assets.on():
		var peb := {}
		for p in pb:
			if not _pack_prop(peb, "pebble", idx(int(p.x), int(p.z)), p, drng):
				peb.clear(); break
		for key in peb:
			var g: Dictionary = peb[key]
			_chunked(deco, g["items"], g["mesh"], g["mat"], "Pebbles")
		pebbled = not peb.is_empty()
	if pb.size() > 0 and not pebbled:
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
		cm.set_shader_parameter("deep", (clouds[0] as Color).lightened(0.1))
		cm.set_shader_parameter("light", (clouds[1] as Color).lightened(0.28))
		cm.set_shader_parameter("glow_amount", 0.25)
	sea.material_override = cm
	sea.position = Vector3(w / 2.0, -18.0, h / 2.0)
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)
	# far below and around: little drifting islets and loose rocks, for depth
	var top_c: Color = biome.get("top", Color("5f8d45"))
	var side_c: Color = biome.get("side", Color("8b6d52"))
	var deep_c: Color = biome.get("deep", Color("3a3140"))
	var placed := 0
	for _k in 120:
		if placed >= 22: break
		var at := Vector3(drng.randf_range(-14, w + 14), drng.randf_range(-14, -5), drng.randf_range(-14, h + 14))
		if not is_void(at.x, at.z) or not is_void(at.x + 3, at.z) or not is_void(at.x - 3, at.z) or not is_void(at.x, at.z + 3):
			continue
		placed += 1
		if drng.randf() < 0.55:
			var rad := drng.randf_range(0.8, 2.0)
			var isl := Models.float_island(drng, rad, rad * drng.randf_range(1.3, 2.2), top_c.darkened(0.08), side_c, deep_c)
			isl.position = at
			isl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			deco.add_child(isl)
		else:
			var r: Node3D = null
			if Assets.on():
				r = Assets.prop("hexagon/mountain_" + ["A", "B", "C"][drng.randi_range(0, 2)], drng.randf_range(0.8, 2.2), false,
					{"tint": Color.WHITE.lerp(side_c.lightened(0.2), 0.45), "bright": 1.05})
				if r: r.rotation = Vector3(drng.randf_range(-0.3, 0.3), drng.randf() * TAU, drng.randf_range(-0.3, 0.3))
			if r == null:
				r = Models.rock(drng, drng.randf_range(0.4, 1.2))
			r.position = at
			deco.add_child(r)

## A few knee-high things on open ground beside a tree or boulder (purely visual).
func _undergrowth(groups: Dictionary, x: int, z: int, r: RandomNumberGenerator) -> void:
	for _k in r.randi_range(0, 2):
		var a := r.randf() * TAU
		var d := r.randf_range(0.75, 1.35)
		var p := Vector2(x + 0.5 + cos(a) * d, z + 0.5 + sin(a) * d)
		var ix := int(floor(p.x)); var iz := int(floor(p.y))
		if not inb(ix, iz):
			continue
		var j := idx(ix, iz)
		if kind[j] != T_GROUND or bush.has(j) or paint.has(j) or stairs.has(j) or bridge.has(j) or level[j] != level[idx(x, z)] or edge_dist(ix, iz, 1) < 2:
			continue
		_pack_prop(groups, "under", j, Vector3(p.x, level[j] * LEVEL, p.y), r)

## Boulders lodged in the cliffs just under an island's rim, so coastlines read as rock instead of a
## clean cut. Purely visual: they sit in the air beside the edge, below the ground you stand on, and
## stay clear of bridges, stairs, pads, updrafts and the sky train's loop.
func _cliff_rocks(groups: Dictionary, r: RandomNumberGenerator) -> void:
	var tc := Vector2.INF; var tr := 0.0
	if not train_route.is_empty():
		tc = train_route["center"]; tr = float(train_route["r"])
	for z in h:
		for x in w:
			var i := idx(x, z)
			if kind[i] == T_VOID or bridge.has(i) or stairs.has(i) or edge_dist(x, z, 1) != 1 or r.randf() > 0.16:
				continue
			var cp := Vector2(x + 0.5, z + 0.5)
			if tc != Vector2.INF and absf(cp.distance_to(tc) - tr) < 4.5:
				continue
			var clear := true
			for pd in pads:
				if Vector2(pd["pos"].x, pd["pos"].z).distance_to(cp) < 3.0: clear = false
			for u in updrafts:
				if Vector2(u["pos"].x, u["pos"].z).distance_to(cp) < 3.0: clear = false
			if not clear:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if inb(x + d.x, z + d.y) and kind[idx(x + d.x, z + d.y)] != T_VOID:
					continue
				var y := level[i] * LEVEL
				var at := Vector3(cp.x + d.x * 0.55, 0.0, cp.y + d.y * 0.55)
				if _pack_prop(groups, "cliff", i, at, r):
					# drop it so its top sits a little under the lip
					var t: Transform3D = _last_item[0]
					t.origin.y += y - _last_top - r.randf_range(0.12, 0.7)
					_last_item[0] = t
				break

## Which look a tile's island has, for picking imported models: its authored biome, or on a
## generated map its region (meadow, autumn, frost, dry, blossom).
func style_at(i: int) -> String:
	var ii := island[i] if i >= 0 and i < island.size() else -1
	if ii < 0 or ii >= islands.size():
		return "meadow"
	var b := String(islands[ii].get("biome", ""))
	if b != "":
		return b
	return ["meadow", "ember", "frost", "storm", "bloom"][int(islands[ii].get("region", 0)) % 5]

## Adds one imported model (a tree, rock, ruin pillar, camp crates or a pebble) at p to the batches
## in groups, picked and sized for the tile's biome. False if the model isn't available, so the
## caller can build the old primitive one instead. Purely visual: what blocks stays the map data.
func _pack_prop(groups: Dictionary, what: String, i: int, p: Vector3, r: RandomNumberGenerator) -> bool:
	if not Assets.on():
		return false
	var style := style_at(i)
	var list: Array
	match what:
		"tree": list = Assets.trees(style)
		"rock", "cliff": list = Assets.rocks(style)
		"ruin": list = Assets.PILLARS
		"camp": list = Assets.CAMP
		"pebble": list = Assets.PEBBLES
		"under": list = Assets.under(style)
		_: return false
	return _pack_prop_variant(groups, what, i, p, r, Assets.pick(list, r))

var _last_item: Array = []     # the [transform, colour] _pack_prop_variant last added, and its top
var _last_top := 0.0
func _pack_prop_variant(groups: Dictionary, what: String, i: int, p: Vector3, r: RandomNumberGenerator, v: Dictionary) -> bool:
	var bio := _bio(i)
	var am := Assets.mesh(String(v["m"]))
	if am == null:
		return false
	var s := Assets.fit_scale(v, am, r)
	var ab := am.get_aabb()
	var b := Basis(Vector3.UP, r.randf() * TAU)
	if what == "tree":
		b = Basis(Vector3(r.randf_range(-1, 1), 0, r.randf_range(-1, 1)).normalized(), r.randf_range(0.0, 0.07)) * b
	b = b.scaled(Vector3.ONE * s)
	var sy := 1.0
	if what == "rock":
		sy = r.randf_range(1.15, 1.5)   # taller boulders, so cover reads as cover
	elif what == "cliff":
		sy = r.randf_range(1.3, 2.2)
		b = b.scaled(Vector3.ONE * r.randf_range(1.2, 1.6))
	b = b * Basis.from_scale(Vector3(1.0, sy, 1.0))
	var tr := Transform3D(b, p + b * -Vector3(ab.position.x + ab.size.x * 0.5, ab.position.y + (0.05 if what != "pebble" else 0.0), ab.position.z + ab.size.z * 0.5))
	var paint := String(v.get("paint", "own"))
	var cfg := {"instanced": true, "bright": float(v.get("bright", 1.0))}
	var col := Color.WHITE
	var jit := r.randf_range(-0.07, 0.07)
	if what in ["tree", "under"] and paint != "own" and v.has("band"):
		cfg["repaint"] = true
		cfg["band"] = v["band"]
		var leaf: Color = bio["leaf"]
		if paint == "green":
			leaf = Color("4f9a52").lerp(Color(bio["top"]), 0.3)
		col = leaf.lightened(jit) if jit > 0.0 else leaf.darkened(-jit)
	else:
		# rocks, ruins, crates and bare trees: the texture's own colours, tinted toward the biome
		cfg["color_tint"] = 1.0
		var base: Color = v.get("tint", Color.WHITE)
		if what in ["rock", "pebble"] or (what == "under" and not v.has("tint") and String(v["m"]).contains("rock")):
			base = Color.WHITE.lerp(Color(bio["side"]).lightened(0.3), 0.35).lerp(Color(bio["top"]), 0.12)
		elif what == "cliff":
			base = Color.WHITE.lerp(Color(bio["side"]), 0.55)
		elif what == "ruin":
			base = Color("fff4e4").lerp(Color(bio["top"]), 0.2).lightened(0.15)
		col = base.lightened(jit) if jit > 0.0 else base.darkened(-jit)
	var key := String(v["m"]) + str(cfg)
	if not groups.has(key):
		groups[key] = {"mesh": am, "mat": Assets.material(Assets.pack_of(String(v["m"])), cfg), "items": [],
			"label": String(v["m"]).get_file(), "shadows": not what in ["pebble", "cliff", "under"]}
	_last_item = [tr, col]
	_last_top = (tr.basis * Vector3(0, ab.size.y, 0)).y
	groups[key]["items"].append(_last_item)
	return true

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


# ------------------------------------------------------------------ authored maps
## Hand-made expedition maps (content/maps/<id>.json). The islands, the land bridges between them
## (the chokepoints), wind roads, jump pads, updrafts, walls, cover and exits are all placed by hand,
## and so is which cliffs you can grab: a rim with a pale stone lip can be caught and climbed, a
## smooth dark slate cliff can't. Only the loot, camps, breakables and spawn picks are dealt out per
## match around each island's point of interest, so every expedition plays out differently on the
## same ground.
static func load_layout(id: String) -> Dictionary:
	var path := "res://content/maps/%s.json" % id
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if typeof(d) == TYPE_DICTIONARY else {}

## Which authored map an expedition of this tier uses (all tiers share Skyreach for now, each with
## its own palette and monsters).
static func layout_for_tier(_tier: int) -> String:
	return "skyreach"

## A biome's data (content/biomes/<id>.json), cached.
static var _biomes := {}
static func load_biome(id: String) -> Dictionary:
	if _biomes.has(id):
		return _biomes[id]
	var path := "res://content/biomes/%s.json" % id
	var d = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	_biomes[id] = d if typeof(d) == TYPE_DICTIONARY else {}
	return _biomes[id]

## Which biome a point is in ("" off the map or on a generated map).
func biome_at(x: float, z: float) -> String:
	var ii := island_of(x, z)
	return String(islands[ii].get("biome", "")) if ii >= 0 and ii < islands.size() else ""

func is_sheer(x: int, z: int) -> bool:
	return inb(x, z) and sheer.has(idx(x, z))

static func _v2(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))

## Normalised distance of a point from a shape: below 1 is inside.
static func _shape_d(S: Dictionary, pt: Vector2) -> float:
	if S.has("circle"):
		return pt.distance_to(_v2(S["circle"])) / maxf(0.5, float(S["r"]))
	if S.has("ellipse"):
		var c := _v2(S["ellipse"])
		var q := (pt - c).rotated(-deg_to_rad(float(S.get("rot", 0.0))))
		return Vector2(q.x / float(S["rx"]), q.y / float(S["rz"])).length()
	if S.has("rect"):
		var r: Array = S["rect"]
		var c2 := Vector2((float(r[0]) + float(r[2])) * 0.5, (float(r[1]) + float(r[3])) * 0.5)
		var hx := maxf(0.5, (float(r[2]) - float(r[0])) * 0.5); var hz := maxf(0.5, (float(r[3]) - float(r[1])) * 0.5)
		return maxf(absf(pt.x - c2.x) / hx, absf(pt.y - c2.y) / hz)
	if S.has("capsule"):
		var cp: Array = S["capsule"]
		var a := Vector2(float(cp[0]), float(cp[1])); var b := Vector2(float(cp[2]), float(cp[3]))
		return Geometry2D.get_closest_point_to_segment(pt, a, b).distance_to(pt) / maxf(0.5, float(S["r"]))
	return 99.0

static func _shape_box(S: Dictionary) -> Rect2:
	if S.has("circle"):
		var c := _v2(S["circle"]); var r := float(S["r"]) + 3.0
		return Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0)
	if S.has("ellipse"):
		var c2 := _v2(S["ellipse"]); var r2 := maxf(float(S["rx"]), float(S["rz"])) + 3.0
		return Rect2(c2 - Vector2(r2, r2), Vector2(r2, r2) * 2.0)
	if S.has("rect"):
		var r: Array = S["rect"]
		return Rect2(Vector2(float(r[0]), float(r[1])) - Vector2(2, 2), Vector2(float(r[2]) - float(r[0]), float(r[3]) - float(r[1])) + Vector2(4, 4))
	if S.has("capsule"):
		var cp: Array = S["capsule"]; var rr := float(S["r"]) + 2.0
		var a := Vector2(float(cp[0]), float(cp[1])); var b := Vector2(float(cp[2]), float(cp[3]))
		return Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(rr, rr), (b - a).abs() + Vector2(rr, rr) * 2.0)
	return Rect2()

func generate_authored(L: Dictionary, seed_val: int) -> void:
	rng.seed = seed_val
	w = int(L.get("size", BIG_SIZE)); h = w
	kind.resize(w * h); kind.fill(T_VOID)
	level.resize(w * h); level.fill(0)
	island.resize(w * h); island.fill(-1)
	depth.resize(w * h); depth.fill(0.0)
	islands.clear(); pads.clear(); spawns.clear(); portal_spots.clear(); chest_spots.clear(); camp_spots.clear(); wild_spots.clear()
	links.clear(); rings.clear(); winds.clear(); updrafts.clear()
	sheer.clear(); lip.clear(); labels.clear(); walls.clear(); bush.clear(); paint.clear(); authored_portals.clear(); train_route = {}; props.clear()
	layout_id = String(L.get("id", "authored"))
	# the ground is the same every match: its noise and depths come from the layout, not the match
	var lr := RandomNumberGenerator.new(); lr.seed = int(L.get("seed", 1))
	var nz := FastNoiseLite.new(); nz.seed = int(L.get("seed", 1)); nz.frequency = 0.055   # broad, gentle coastlines
	var defs: Array = L.get("islands", [])
	var ids := {}
	for ii in defs.size():
		ids[String(defs[ii]["id"])] = ii
	for ii in defs.size():
		var D: Dictionary = defs[ii]
		var shapes: Array = D.get("shapes", [])
		if shapes.is_empty():
			continue
		var nk := float(D.get("noise", 0.12))
		var box := _shape_box(shapes[0])
		for S in shapes:
			box = box.merge(_shape_box(S))
		var cells: Array = []
		for z in range(maxi(1, int(box.position.y)), mini(h - 1, int(box.end.y) + 1)):
			for x in range(maxi(1, int(box.position.x)), mini(w - 1, int(box.end.x) + 1)):
				var i := idx(x, z)
				if kind[i] != T_VOID:
					continue
				var pt := Vector2(x + 0.5, z + 0.5)
				var lv := -1
				var d0 := 99.0
				for si in shapes.size():
					var S: Dictionary = shapes[si]
					var sd := _shape_d(S, pt)
					# the outline gets a gentle natural coast; terraces inside are crisp, deliberate shapes
					var n := nz.get_noise_2d(x, z) * nk if si == 0 else 0.0
					if si == 0: d0 = sd
					if sd + n < 1.0:
						if S.get("cut", false):
							lv = -1; break
						lv = maxi(lv, int(S.get("lv", 0)))
				if lv < 0:
					continue
				kind[i] = T_GROUND
				island[i] = ii
				level[i] = clampi(lv, 0, 20)      # authored perches float far higher than any terrace
				depth[i] = -(2.2 + (1.0 - clampf(d0, 0.0, 1.0)) * 4.5 + lr.randf() * 1.5) * (0.6 if D.get("perch", false) else 1.0)
				cells.append(Vector2i(x, z))
		var c0: Dictionary = shapes[0]
		var cen := _shape_box(c0).get_center() if not (c0.has("circle") or c0.has("ellipse")) else _v2(c0.get("circle", c0.get("ellipse", [0, 0])))
		var poi := _v2(D.get("poi", [cen.x, cen.y]))
		islands.append({"c": cen, "r": sqrt(cells.size() / PI), "base": 0, "cells": cells, "role": String(D.get("role", "grove")),
			"form": "authored", "fdir": Vector2.RIGHT, "name": String(D.get("name", "")), "id": String(D["id"]),
			"region_fixed": int(D.get("region", 0)), "poi_at": poi, "drop": bool(D.get("drop", false)), "sheer_arcs": D.get("sheer", []),
			"biome": String(D.get("biome", "")), "danger": int(D.get("danger", 0)), "perch": bool(D.get("perch", false)), "extras": D.get("extras", [])})
		if String(D.get("biome", "")) != "":
			var bj := load_biome(String(D["biome"]))
			if bj.has("colors"):
				islands[ii]["biome_colors"] = bj["colors"]
		if String(D.get("name", "")) != "":
			var top_lv := 0
			for S in shapes: top_lv = maxi(top_lv, int(S.get("lv", 0)))
			labels.append({"name": String(D["name"]), "pos": Vector3(poi.x, 0, poi.y), "kind": "perch" if D.get("perch", false) else "poi",
				"role": String(D.get("role", "")), "height": top_lv * LEVEL})
	_tidy_ground()
	# land bridges: narrow, sheer-sided necks of ground between two islands. The whole bridge
	# belongs to the first island, so walking along it never changes which island you're on.
	var neck := {}
	for B in L.get("bridges", []):
		var a: int = ids.get(String(B["a"]), -1); var b: int = ids.get(String(B["b"]), -1)
		if a < 0 or b < 0:
			continue
		var p0 := _v2(B["from"]); var p1 := _v2(B["to"])
		var rr := float(B.get("r", 1.4))
		var lv0 := int(level[idx(int(p0.x), int(p0.y))]) if kind[idx(int(p0.x), int(p0.y))] != T_VOID else 0
		var lv1 := int(level[idx(int(p1.x), int(p1.y))]) if kind[idx(int(p1.x), int(p1.y))] != T_VOID else 0
		for z in range(int(minf(p0.y, p1.y) - rr - 1), int(maxf(p0.y, p1.y) + rr + 2)):
			for x in range(int(minf(p0.x, p1.x) - rr - 1), int(maxf(p0.x, p1.x) + rr + 2)):
				if not inb(x, z):
					continue
				var pt := Vector2(x + 0.5, z + 0.5)
				var q := Geometry2D.get_closest_point_to_segment(pt, p0, p1)
				if q.distance_to(pt) > rr:
					continue
				var i := idx(x, z)
				if kind[i] != T_VOID:
					continue
				kind[i] = T_GROUND
				island[i] = a
				var t := clampf(p0.distance_to(q) / maxf(0.01, p0.distance_to(p1)), 0.0, 1.0)
				level[i] = mini(lv0, lv1) if t > 0.15 and t < 0.85 else (lv0 if t <= 0.15 else lv1)
				depth[i] = -1.6
				neck[i] = true
				islands[a]["cells"].append(Vector2i(x, z))
		var mid := p0.lerp(p1, 0.5)
		if String(B.get("name", "")) != "":
			labels.append({"name": String(B["name"]), "pos": Vector3(mid.x, 0, mid.y), "kind": "choke"})
		# for bots: walk the bridge (it's island a), then a short hop onto island b, and back
		var dirn := (p1 - p0).normalized()
		var P0 := Vector3(p0.x, 0, p0.y); var P1 := Vector3(p1.x, 0, p1.y)
		var on_b := _inward(b, P1, P0)
		on_b.y = ground_at(on_b.x, on_b.z)
		var on_bridge := Vector3(floor(p1.x - dirn.x * 2.5) + 0.5, 0, floor(p1.y - dirn.y * 2.5) + 0.5)
		on_bridge.y = ground_at(on_bridge.x, on_bridge.z) if not is_void(on_bridge.x, on_bridge.z) else on_b.y
		links.append({"from": a, "to": b, "take": on_bridge, "land": on_b, "bridge": true})
		links.append({"from": b, "to": a, "take": on_b, "land": on_bridge, "bridge": true})
	if L.has("train"):
		_build_train(L["train"], neck)
	_authored_blockers(defs, neck)
	lair_defs.clear()
	for LD in L.get("lairs", []):
		var li: int = ids.get(String(LD.get("island", "")), -1)
		if li >= 0:
			_stamp_lair(LD, li)
	# which rims can be caught: bridges and the authored arcs are sheer, the rest have a stone lip
	for ii in islands.size():
		var arcs: Array = islands[ii].get("sheer_arcs", [])
		var cen2: Vector2 = islands[ii]["c"]
		for cell in islands[ii]["cells"]:
			var i := idx(cell.x, cell.y)
			if neck.has(i) and kind[i] != T_VOID and edge_dist(cell.x, cell.y, 1) != 1:
				paint[i] = Color("958f8a")      # the middle of a bridge: the same stone path
				continue
			if kind[i] == T_VOID or edge_dist(cell.x, cell.y, 1) != 1:
				continue
			var sh := neck.has(i)
			if not sh:
				var ang := fposmod(rad_to_deg(atan2(cell.y + 0.5 - cen2.y, cell.x + 0.5 - cen2.x)), 360.0)
				for arc in arcs:
					var a0 := float(arc[0]); var span := fposmod(float(arc[1]) - a0, 360.0)
					if span == 0.0: span = 360.0
					if fposmod(ang - a0, 360.0) <= span:
						sh = true; break
			if sh:
				sheer[i] = true
				# bridges get a worn stone path on top; other sheer rims a cold slate border
				paint[i] = Color("958f8a") if neck.has(i) else Color("7d7896")
			else:
				lip[i] = true
				paint[i] = Color("dccb9c")
	# wind roads, jump pads and updrafts, all where the layout puts them
	var edges_of := {}
	for ii in islands.size():
		var e: Array = []
		for cell in islands[ii]["cells"]:
			if kind[idx(cell.x, cell.y)] != T_VOID and edge_dist(cell.x, cell.y, 1) == 1 and not neck.has(idx(cell.x, cell.y)):
				e.append(cell)
		edges_of[ii] = e
	for W in L.get("winds", []):
		var a: int = ids.get(String(W[0]), -1); var b: int = ids.get(String(W[1]), -1)
		if a < 0 or b < 0:
			continue
		var g := _gap(a, b, edges_of)
		_wind_link(a, b, g)
		if (W as Array).size() > 2:
			var ga: Vector2i = g[1]; var gb: Vector2i = g[2]
			labels.append({"name": String(W[2]), "pos": Vector3((ga.x + gb.x) * 0.5 + 0.5, 0, (ga.y + gb.y) * 0.5 + 0.5), "kind": "choke"})
	var used: Array = []
	for P in L.get("pads", []):
		var a: int = ids.get(String(P[0]), -1); var b: int = ids.get(String(P[1]), -1)
		if a < 0 or b < 0:
			continue
		# a launch pad up to a perch only goes one way: you glide back down
		for dir in ([[a, b]] if (P as Array).size() > 2 else [[a, b], [b, a]]):
			var from: int = dir[0]; var to: int = dir[1]
			var c_from := _edge_cell_toward(from, islands[to]["c"], used)
			if c_from.x < 0: c_from = _edge_cell_toward(from, islands[to]["c"], used, 3.0)
			if c_from.x < 0: continue
			used.append(Vector2(c_from.x + 0.5, c_from.y + 0.5))
			pads.append({"pos": Vector3(c_from.x + 0.5, level[idx(c_from.x, c_from.y)] * LEVEL, c_from.y + 0.5), "land": Vector3.INF, "from": from, "to": to, "cd": 0.0})
	for pd in pads:
		var to: int = pd["to"]
		var src := Vector2(pd["pos"].x, pd["pos"].z)
		var best := Vector3.INF; var bs := -1e9
		for cell in islands[to]["cells"]:
			var i := idx(cell.x, cell.y)
			if kind[i] != T_GROUND or _near_block(cell.x, cell.y) or neck.has(i):
				continue
			var cp := Vector2(cell.x + 0.5, cell.y + 0.5)
			var clear := true
			for other in pads:
				if Vector2(other["pos"].x, other["pos"].z).distance_to(cp) < 3.0:
					clear = false; break
			if not clear: continue
			var score := -cp.distance_to(src) - (6.0 if edge_dist(cell.x, cell.y, 5) < 3 else 0.0)
			if score > bs: bs = score; best = Vector3(cp.x, level[i] * LEVEL, cp.y)
		pd["land"] = best
	pads = pads.filter(func(pd): return pd["land"] != Vector3.INF)
	for U in L.get("updrafts", []):
		var at := _v2(U["at"])
		updrafts.append({"pos": Vector3(at.x, 0.0, at.y), "r": 1.7, "top": float(U.get("top", 2)) * LEVEL + 1.6})
	# glide routes down from the perches (one way: you can't glide up to them)
	for G in L.get("glides", []):
		var a: int = ids.get(String(G[0]), -1); var b: int = ids.get(String(G[1]), -1)
		if a < 0 or b < 0:
			continue
		var g := _gap(a, b, edges_of)
		var ca: Vector2i = g[1]; var cb: Vector2i = g[2]
		var pa := Vector3(ca.x + 0.5, level[idx(ca.x, ca.y)] * LEVEL, ca.y + 0.5)
		var pb := Vector3(cb.x + 0.5, level[idx(cb.x, cb.y)] * LEVEL, cb.y + 0.5)
		links.append({"from": a, "to": b, "take": pa, "land": _inward(b, pb, pa), "glide": true})
	for ap in L.get("portals", []):
		authored_portals.append(_v2(ap))
	exit_defs.clear()
	for ek in [["docks", "dock"], ["outposts", "outpost"], ["hatches", "hatch"]]:
		for ap in L.get(ek[0], []):
			authored_portals.append(_v2(ap))
			exit_defs.append({"kind": ek[1], "at": _v2(ap), "out": Vector2(float(ap[2]), float(ap[3])) if (ap as Array).size() >= 4 else Vector2.ZERO,
				"walled": (ap as Array).size() >= 3 and ek[1] == "outpost" and bool(ap[2])})
	_place_spots()
	_clear_lair_spots()
	for ed in exit_defs:
		var ea: Vector2 = ed["at"]
		ed["pos"] = Vector3(floor(ea.x) + 0.5, ground_at(ea.x, ea.y), floor(ea.y) + 0.5)
	# loot placed by hand: the perches' chests and weapons
	for ii in defs.size():
		var D2: Dictionary = defs[ii]
		for ch in D2.get("chests", []):
			var cx := int(ch[0]); var cz := int(ch[1])
			if inb(cx, cz) and kind[idx(cx, cz)] != T_VOID:
				kind[idx(cx, cz)] = T_GROUND
				chest_spots.append({"pos": Vector3(cx + 0.5, level[idx(cx, cz)] * LEVEL, cz + 0.5), "tier": int(ch[2])})
		if D2.has("weapon"):
			var wx := int(D2["weapon"][0]); var wz := int(D2["weapon"][1])
			if inb(wx, wz) and kind[idx(wx, wz)] == T_GROUND:
				weapon_spots.append(Vector3(wx + 0.5, level[idx(wx, wz)] * LEVEL, wz + 0.5))
	_place_stairs()

## The sky train's loop: a ring round the middle of the map. At each stop a short stone pier runs
## out from the islands on either side to the track, so you can just walk on; between stops, wherever
## the ring passes a bridge or a rim, the track dips under it.
func _build_train(T: Dictionary, neck: Dictionary) -> void:
	var c := _v2(T.get("center", [w * 0.5, h * 0.5]))
	var R := float(T.get("r", 30.0))
	var n := int(ceil(TAU * R / TRAIN_STEP))
	var stops: Array = T.get("stations", [])
	var names: Array = T.get("names", [])
	var st_s: Array = []
	for a in stops:
		var ang := deg_to_rad(float(a))
		st_s.append(fposmod(ang, TAU) * R)
		var dir := Vector2(cos(ang), sin(ang))
		# piers: from the nearest ground inside and outside the ring, up to the track's edge
		for side: float in [-1.0, 1.0]:
			var found := -1.0
			var r0 := R + side * 1.7
			for k in 30:
				var rr := r0 + side * k * 0.5
				var q := c + dir * rr
				if inb(int(q.x), int(q.y)) and kind[idx(int(q.x), int(q.y))] == T_GROUND and not neck.has(idx(int(q.x), int(q.y))) \
						and level[idx(int(q.x), int(q.y))] < 4:
					found = rr; break
			if found < 0.0:
				continue
			var g0 := c + dir * found
			var gi := idx(int(g0.x), int(g0.y))
			var owner := island[gi]; var lv := level[gi]
			var p0 := c + dir * (found - side * 2.0); var p1 := c + dir * r0
			for z in range(int(minf(p0.y, p1.y)) - 3, int(maxf(p0.y, p1.y)) + 4):
				for x in range(int(minf(p0.x, p1.x)) - 3, int(maxf(p0.x, p1.x)) + 4):
					if not inb(x, z):
						continue
					var pt := Vector2(x + 0.5, z + 0.5)
					if Geometry2D.get_closest_point_to_segment(pt, p0, p1).distance_to(pt) > 1.6:
						continue
					var i := idx(x, z)
					if kind[i] != T_VOID:
						continue
					kind[i] = T_GROUND; island[i] = owner; level[i] = lv; depth[i] = -1.6
					neck[i] = true
					islands[owner]["cells"].append(Vector2i(x, z))
		if names.size() > st_s.size() - 1:
			var at := c + dir * R
			labels.append({"name": String(names[st_s.size() - 1]), "pos": Vector3(at.x, 0, at.y), "kind": "rail"})
	# the deck height round the loop: level with the ground at the stops, under anything in the way
	var want := PackedFloat32Array(); want.resize(n)
	for k in n:
		var s := k * TRAIN_STEP
		var ang := s / R
		var q := c + Vector2(cos(ang), sin(ang)) * R
		var near_stop := false
		for ss in st_s:
			var ds := absf(fposmod(s - float(ss) + TAU * R * 0.5, TAU * R) - TAU * R * 0.5)
			if ds < 5.0: near_stop = true
		var blocked := false
		if not near_stop:
			for z in range(int(q.y - 3), int(q.y + 4)):
				for x in range(int(q.x - 3), int(q.x + 4)):
					# (high perches float well clear of the cars)
					if inb(x, z) and kind[idx(x, z)] != T_VOID and level[idx(x, z)] < 6 and Vector2(x + 0.5, z + 0.5).distance_to(q) < 2.9:
						blocked = true
		want[k] = TRAIN_DIVE if blocked else 0.0
	# ramps: the deck never changes height faster than the dive over ~8 tiles
	var slope := absf(TRAIN_DIVE) / 8.0 * TRAIN_STEP
	var y := want.duplicate()
	for _pass in 2:
		for k in range(1, n * 2):
			y[k % n] = minf(y[k % n], y[(k - 1) % n] + slope)
		for k in range(n * 2 - 2, -1, -1):
			y[k % n] = minf(y[k % n], y[(k + 1) % n] + slope)
	var pts := PackedVector3Array(); pts.resize(n)
	for k in n:
		var ang := k * TRAIN_STEP / R
		pts[k] = Vector3(c.x + cos(ang) * R, y[k], c.y + sin(ang) * R)
	train_route = {"pts": pts, "len": n * TRAIN_STEP, "stations": st_s, "names": names, "spec": T, "center": c, "r": R}

## Where the track is a given arc length round the loop (wraps), and its heading there.
func train_at(s: float) -> Vector3:
	var pts: PackedVector3Array = train_route["pts"]
	var n := pts.size()
	var f := fposmod(s, float(train_route["len"])) / TRAIN_STEP
	var k := int(f) % n
	return pts[k].lerp(pts[(k + 1) % n], f - floor(f))

## Walls, pillars and tall grass from the layout, plus a light scatter of rocks for cover away from
## the edges, the bridges and the points of interest.
func _authored_blockers(defs: Array, neck: Dictionary) -> void:
	for ii in defs.size():
		if ii >= islands.size():
			break
		var D: Dictionary = defs[ii]
		for Wd in D.get("walls", []):
			for q in _wall_tiles(Wd):
				_wall_at(q, ii)
		for pp in D.get("pillars", []):
			var px := int(pp[0]); var pz := int(pp[1])
			if inb(px, pz) and kind[idx(px, pz)] == T_GROUND and island[idx(px, pz)] == ii:
				kind[idx(px, pz)] = T_BLOCK
				props[idx(px, pz)] = "ruin"
		for bz in D.get("bush", []):
			var bc := Vector2(float(bz[0]), float(bz[1])); var rad := float(bz[2])
			for z in range(int(bc.y - rad - 1), int(bc.y + rad + 2)):
				for x in range(int(bc.x - rad - 1), int(bc.x + rad + 2)):
					if Vector2(x + 0.5, z + 0.5).distance_to(bc) > rad + rng.randf_range(-0.2, 0.3): continue
					if inb(x, z) and kind[idx(x, z)] == T_GROUND and island[idx(x, z)] == ii and edge_dist(x, z, 2) >= 2:
						bush[idx(x, z)] = true
		# cover: a few deliberate rock formations (a 2x2 boulder, an L, a short ridge) spaced well
		# apart on open, flat ground, never single random blocks scattered everywhere
		var poi := _v2(D.get("poi", [0, 0]))
		if D.get("perch", false) or D.get("no_rocks", false):
			continue
		var cells2: Array = islands[ii]["cells"].duplicate()
		var want := int(cells2.size() / 240)
		var placed: Array = []
		var tries := 0
		while placed.size() < want and tries < want * 30 + 30:
			tries += 1
			var c: Vector2i = cells2[rng.randi_range(0, cells2.size() - 1)]
			var cp := Vector2(c.x + 0.5, c.y + 0.5)
			if cp.distance_to(poi) < 7.0 or edge_dist(c.x, c.y, 5) <= 4:
				continue
			var far := true
			for p in placed:
				if (p as Vector2).distance_to(cp) < 11.0: far = false; break
			if not far: continue
			var shape: Array = [[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
				[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1)],
				[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)],
				[Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)]][rng.randi_range(0, 3)]
			var lv0 := int(level[idx(c.x, c.y)])
			var ok := true
			for o in shape:
				var q: Vector2i = c + o
				# flat ground all around it, so it reads as a rock on a plateau, not a step
				for dz in range(-1, 2):
					for dx in range(-1, 2):
						var r2 := q + Vector2i(dx, dz)
						if not inb(r2.x, r2.y) or kind[idx(r2.x, r2.y)] != T_GROUND or int(level[idx(r2.x, r2.y)]) != lv0 or neck.has(idx(r2.x, r2.y)) or bush.has(idx(r2.x, r2.y)):
							ok = false
			if not ok: continue
			for o in shape:
				kind[idx(c.x + o.x, c.y + o.y)] = T_BLOCK
			placed.append(cp)

## Cleans an authored island's ground so it's easy to walk: removes one-tile specks and spurs of
## ground, fills one-tile holes, and evens out terrace levels so no lone tile sits a step above or
## below its neighbours (the little bumps that made walking feel bouncy).
func _tidy_ground() -> void:
	for _pass in 2:
		for z in range(1, h - 1):
			for x in range(1, w - 1):
				var i := idx(x, z)
				var n_ground := 0
				var lv_count := {}
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var j := idx(x + d.x, z + d.y)
					if kind[j] != T_VOID:
						n_ground += 1
						lv_count[int(level[j])] = int(lv_count.get(int(level[j]), 0)) + 1
				if kind[i] == T_VOID:
					if n_ground >= 3:
						# a pinhole in the ground: fill it at the level around it
						var best_lv := 0; var bc := -1
						for lv in lv_count:
							if int(lv_count[lv]) > bc: bc = int(lv_count[lv]); best_lv = int(lv)
						var nb := idx(x + 1, z) if kind[idx(x + 1, z)] != T_VOID else (idx(x - 1, z) if kind[idx(x - 1, z)] != T_VOID else (idx(x, z + 1) if kind[idx(x, z + 1)] != T_VOID else idx(x, z - 1)))
						kind[i] = T_GROUND; level[i] = best_lv; island[i] = island[nb]; depth[i] = depth[nb]
						if island[i] >= 0: islands[island[i]]["cells"].append(Vector2i(x, z))
					continue
				if n_ground <= 1:
					# a speck or a one-tile spur sticking out into the air
					var ii := island[i]
					kind[i] = T_VOID; level[i] = 0; island[i] = -1
					if ii >= 0: islands[ii]["cells"].erase(Vector2i(x, z))
					continue
				# a lone tile on a different terrace from all four neighbours goes to the common level
				var mine := int(level[i])
				if not lv_count.has(mine) and lv_count.size() > 0:
					var best := mine; var bcount := -1
					for lv in lv_count:
						if int(lv_count[lv]) > bcount: bcount = int(lv_count[lv]); best = int(lv)
					if bcount >= 3:
						level[i] = best

func _wall_tiles(Wd: Dictionary) -> Array:
	var out: Array = []
	if Wd.has("line"):
		var l: Array = Wd["line"]
		var a := Vector2(float(l[0]), float(l[1])); var b := Vector2(float(l[2]), float(l[3]))
		var n := int(maxf(absf(b.x - a.x), absf(b.y - a.y))) + 1
		for k in n:
			var p := a.lerp(b, float(k) / maxf(1.0, n - 1))
			var q := Vector2i(int(floor(p.x)), int(floor(p.y)))
			if not out.has(q): out.append(q)
	elif Wd.has("ring"):
		var c := _v2(Wd["ring"]); var r := float(Wd["r"])
		var gates := int(Wd.get("gates", 4)); var gw := float(Wd.get("gate_w", 2))
		for z in range(int(c.y - r - 2), int(c.y + r + 2)):
			for x in range(int(c.x - r - 2), int(c.x + r + 2)):
				var d := Vector2(x + 0.5, z + 0.5).distance_to(c)
				if absf(d - r) > 0.55: continue
				var ang := atan2(z + 0.5 - c.y, x + 0.5 - c.x)
				var gate := false
				for k in gates:
					var ga := -PI / 2 + TAU * k / maxf(1, gates)
					if absf(wrapf(ang - ga, -PI, PI)) * r < gw * 0.5 + 0.6: gate = true
				if not gate: out.append(Vector2i(x, z))
	elif Wd.has("box"):
		var bx: Array = Wd["box"]
		var x0 := int(bx[0]); var z0 := int(bx[1]); var x1 := int(bx[2]); var z1 := int(bx[3])
		var gw2 := int(Wd.get("gate_w", 3))
		var gs: Array = Wd.get("gates", [])
		var mx := (x0 + x1) / 2; var mz := (z0 + z1) / 2
		for x in range(x0, x1 + 1):
			for zz in [z0, z1]:
				var side := "n" if zz == z0 else "s"
				if gs.has(side) and absi(x - mx) <= gw2 / 2: continue
				out.append(Vector2i(x, zz))
		for z in range(z0 + 1, z1):
			for xx in [x0, x1]:
				var side2 := "w" if xx == x0 else "e"
				if gs.has(side2) and absi(z - mz) <= gw2 / 2: continue
				out.append(Vector2i(xx, z))
	return out

# ------------------------------------------------------------------ boss lairs
## Is this spot inside a lair's walls (pad: tiles of slack round the inside)?
func lair_at(x: float, z: float, pad := 0.0) -> int:
	for li in lair_defs.size():
		var D: Dictionary = lair_defs[li]
		var c: Vector2 = D["c"]; var hf := float(D["half"]) - 0.5 + pad
		if absf(x - c.x) <= hf and absf(z - c.y) <= hf:
			return li
	return -1

## Stamps a lair onto an island: the floor inside is levelled and cleared, a square of stone walls
## goes round it with a three-wide gap on the gate side (Lairs seals the gap with a gate at match start).
## D: {id, name, boss, at: [x, z], half, gate, entry}
func _stamp_lair(D: Dictionary, ii: int) -> void:
	var at := _v2(D.get("at", [0, 0]))
	var cx := int(floor(at.x)); var cz := int(floor(at.y))
	var hf := int(D.get("half", 6))
	if not inb(cx, cz) or kind[idx(cx, cz)] == T_VOID:
		return
	var lv := int(level[idx(cx, cz)])
	var gate := String(D.get("gate", "s"))
	var out: Vector2 = {"n": Vector2(0, -1), "s": Vector2(0, 1), "e": Vector2(1, 0), "w": Vector2(-1, 0)}[gate]
	var gate_tiles: Array = []
	for z in range(cz - hf, cz + hf + 1):
		for x in range(cx - hf, cx + hf + 1):
			if not inb(x, z):
				continue
			var i := idx(x, z)
			if kind[i] == T_VOID:
				continue
			# the floor: one level, nothing growing or standing on it
			level[i] = lv
			kind[i] = T_GROUND
			bush.erase(i); props.erase(i); walls.erase(i); paint.erase(i)
			var rim := x == cx - hf or x == cx + hf or z == cz - hf or z == cz + hf
			if not rim:
				paint[i] = Color("8a8378") if (x + z) % 2 == 0 else Color("7f786e")    # worn flagstones
				continue
			var side := "n" if z == cz - hf else ("s" if z == cz + hf else ("w" if x == cx - hf else "e"))
			var along := x - cx if side in ["n", "s"] else z - cz
			if side == gate and absi(along) <= 1 and not ((x == cx - hf or x == cx + hf) and (z == cz - hf or z == cz + hf)):
				gate_tiles.append(Vector2i(x, z))
				paint[i] = Color("b8a77a")
				continue
			kind[i] = T_BLOCK
			walls[i] = true
	# the approach: no rocks in the way of the gate, and a stone path out to where the dial stands
	for k in range(1, 5):
		for s2 in range(-2, 3):
			var q := Vector2i(cx, cz) + Vector2i(out * (hf + k)) + Vector2i(Vector2(-out.y, out.x) * s2)
			if inb(q.x, q.y) and kind[idx(q.x, q.y)] == T_BLOCK and not walls.has(idx(q.x, q.y)):
				kind[idx(q.x, q.y)] = T_GROUND
			if inb(q.x, q.y) and kind[idx(q.x, q.y)] == T_GROUND and absi(s2) <= 1:
				paint[idx(q.x, q.y)] = Color("b8a77a")
				bush.erase(idx(q.x, q.y))
	var c := Vector2(cx + 0.5, cz + 0.5)
	islands[ii]["lair"] = true
	lair_defs.append({"id": String(D.get("id", "lair%d" % lair_defs.size())), "name": String(D.get("name", "Boss Lair")),
		"boss": String(D.get("boss", "colossus")), "c": c, "half": hf, "gate": gate, "gate_tiles": gate_tiles, "out": out,
		"island": ii, "y": lv * LEVEL, "entry": D.get("entry", ["dial"])})
	labels.append({"name": String(D.get("name", "Boss Lair")), "pos": Vector3(c.x, 0, c.y), "kind": "lair", "role": "lair", "height": lv * LEVEL})

## Nothing else is placed inside a lair: no spawns, chests, camps, wild kin or loot lying about.
func _clear_lair_spots() -> void:
	if lair_defs.is_empty():
		return
	var outside := func(p: Vector3) -> bool: return lair_at(p.x, p.z, 1.5) < 0
	spawns = spawns.filter(outside)
	portal_spots = portal_spots.filter(outside)
	wild_spots = wild_spots.filter(outside)
	shrine_spots = shrine_spots.filter(outside)
	weapon_spots = weapon_spots.filter(outside)
	chest_spots = chest_spots.filter(func(c): return outside.call(c["pos"]))
	camp_spots = camp_spots.filter(func(c): return outside.call(c["pos"]))
	break_spots = break_spots.filter(func(c): return outside.call(c["pos"]))

## Generated maps: one lair (two on the big map) on the largest outer islands, set where the island's
## point of interest was, each a different boss.
func _place_lairs() -> void:
	var want := 2 if w >= 180 else (1 if w >= 96 else 0)
	if want == 0:
		return
	var cand: Array = range(1, islands.size()).filter(func(ii): return String(islands[ii]["role"]) in ["camp", "nest", "grove", "shrine"])
	cand.sort_custom(func(a, b): return islands[a]["cells"].size() > islands[b]["cells"].size())
	var hf := 6 if w >= 180 else 5
	var used: Array = []
	var b0 := rng.randi_range(0, Data.BOSSES.size() - 1)
	for ii in cand:
		if lair_defs.size() >= want:
			break
		# the roomiest spot on the island: as far from its rim as it gets, near its middle
		var best := Vector2i(-1, -1); var bs := -1e9
		var cc: Vector2 = islands[ii]["c"]
		for cell in islands[ii]["cells"]:
			if kind[idx(cell.x, cell.y)] == T_VOID:
				continue
			var ed := edge_dist(cell.x, cell.y, 9)
			if ed < hf + 1:
				continue
			var sc := float(ed) * 2.0 - Vector2(cell.x + 0.5, cell.y + 0.5).distance_to(cc)
			if sc > bs: bs = sc; best = cell
		if best.x < 0:
			continue
		# no pads, updrafts or spawns inside, and the gate faces the map's middle
		var clash := false
		for pd in pads:
			if absf(pd["pos"].x - best.x - 0.5) <= hf + 2 and absf(pd["pos"].z - best.y - 0.5) <= hf + 2: clash = true
		for u in updrafts:
			if absf(u["pos"].x - best.x - 0.5) <= hf + 2 and absf(u["pos"].z - best.y - 0.5) <= hf + 2: clash = true
		var ground_n := 0
		for z in range(best.y - hf, best.y + hf + 1):
			for x in range(best.x - hf, best.x + hf + 1):
				if inb(x, z) and kind[idx(x, z)] != T_VOID and island[idx(x, z)] == ii: ground_n += 1
		if clash or ground_n < int((2 * hf + 1) * (2 * hf + 1) * 0.86):
			continue
		var to_mid := Vector2(w / 2.0 - best.x, h / 2.0 - best.y)
		var gate := ("e" if to_mid.x > 0 else "w") if absf(to_mid.x) > absf(to_mid.y) else ("s" if to_mid.y > 0 else "n")
		var boss: String = Data.BOSSES[(b0 + lair_defs.size()) % Data.BOSSES.size()]
		var nm: String = {"colossus": "The Sunken Forge", "serpent": "Stormcrown Eyrie", "brood": "The Thornhive"}.get(boss, "Boss Lair")
		var entry: Array = {"colossus": ["dial"], "serpent": ["dial", "runes"], "brood": ["dial", "wards"]}.get(boss, ["dial"])
		_stamp_lair({"id": "lair%d" % lair_defs.size(), "name": nm, "boss": boss, "at": [best.x, best.y], "half": hf, "gate": gate, "entry": entry}, ii)
		used.append(ii)
	_clear_lair_spots()
