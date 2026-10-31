class_name HomeLayout
extends RefCounted
## How your home islands are laid out, kept on the save as Save.d["layout"]:
##   grow     how many times you've expanded the main island (its edge grows east and south)
##   b        where each building stands and which way it faces: id -> {x, z, r} (top-left tile, quarter turns);
##            a building that isn't listed stands on its default lot (Data.BUILDINGS rect)
##   deco     decorations you've put down: [{u, id, x, z, r, c?}] (u is a unique number)
##   paths    painted path tiles: "x,z" -> catalog id ("none" clears one of the farm's own paths)
##   water    pond tiles: "x,z" -> 1
##   theme    the islands' ground colours; themes you've bought
##   inv      decorations in storage: id -> count (put away from the island, placed again for free)
## home.gd builds the world from this; HomeBuild (build mode) edits it.

const W := 92                        # the home map, in tiles (was 72 x 50)
const H := 70
const SEED := 4242
const CORE_C := Vector2(38, 32)      # the original island: everything that stood there still does
const CORE_R := Vector2(14, 11)
const LOBE_NW := Vector2(23, 20)     # the open meadow grows out east and south from this corner
const LOBE_R0 := Vector2(21, 15)
const LOBE_STEP := Vector2(2.0, 1.5)
const GAP := 3                       # tiles of sky kept between the main island and every other isle

## Growing the main island: [gems, scrap] for each step.
const EXPAND := [[150, 4], [260, 8], [400, 14], [600, 22]]

## Ground colours for every home island. region is the world's region look (trees, rocks) to use.
const THEMES := {
	"meadow": {"name": "Meadow", "gems": 0, "region": 0},
	"autumn": {"name": "Autumn", "gems": 120, "region": 1, "top": "b08a50", "top2": "94723f", "side": "8b5a3a", "leaf": "e0743a"},
	"snow": {"name": "Snow", "gems": 160, "region": 2, "top": "d2e2ea", "top2": "aac6d6", "side": "7a8aa0", "deep": "2c3448", "leaf": "8ac8d8"},
	"blossom": {"name": "Blossom", "gems": 200, "region": 4, "top": "7cbc6c", "top2": "5c9c5c", "side": "8b6d52", "leaf": "ff9ac8"},
}

## The build-mode catalog. cat: the bar's tab. gems / scrap: the price of one (one tile for lines and
## brushes). size: footprint in tiles before turning. block: kin and you walk around it. line: dragged
## out in a line that joins up (fences). brush: painted on tiles (path / clear / water). colour: you
## pick its colour. light: glows at night. bed: kin sleep on it.
const CATALOG := {
	"fence": {"name": "Wood fence", "cat": "Fences", "gems": 3, "line": true, "block": true},
	"picket": {"name": "Picket fence", "cat": "Fences", "gems": 4, "line": true, "block": true},
	"stone_wall": {"name": "Stone wall", "cat": "Fences", "gems": 6, "line": true, "block": true},
	"hedge": {"name": "Hedge", "cat": "Fences", "gems": 5, "line": true, "block": true},
	"path_stone": {"name": "Stone path", "cat": "Paths", "gems": 2, "brush": "path", "col": "b1a796"},
	"path_dirt": {"name": "Dirt path", "cat": "Paths", "gems": 1, "brush": "path", "col": "9c7a52"},
	"path_wood": {"name": "Boardwalk", "cat": "Paths", "gems": 2, "brush": "path", "col": "8a6242"},
	"path_clear": {"name": "Grass (clear)", "cat": "Paths", "gems": 0, "brush": "clear"},
	"clear_wild": {"name": "Clear the wild", "cat": "Island", "gems": 3, "brush": "wild"},
	"water": {"name": "Pond water", "cat": "Paths", "gems": 6, "brush": "water", "block": true},
	"flowers": {"name": "Flower bed", "cat": "Garden", "gems": 8},
	"bush": {"name": "Bush", "cat": "Garden", "gems": 10, "block": true},
	"tree": {"name": "Leafy tree", "cat": "Garden", "gems": 20, "block": true},
	"pine": {"name": "Pine tree", "cat": "Garden", "gems": 20, "block": true},
	"blossom_tree": {"name": "Blossom tree", "cat": "Garden", "gems": 30, "block": true},
	"lantern": {"name": "Lantern", "cat": "Lights", "gems": 15, "light": true},
	"lamp_post": {"name": "Lamp post", "cat": "Lights", "gems": 20, "light": true},
	"bench": {"name": "Bench", "cat": "Furniture", "gems": 25, "size": [2, 1], "block": true},
	"kin_bed": {"name": "Kin bed", "cat": "Furniture", "gems": 15, "bed": true, "colour": true},
	"rug": {"name": "Picnic rug", "cat": "Furniture", "gems": 20, "size": [2, 2], "colour": true},
	"rug_long": {"name": "Long rug", "cat": "Furniture", "gems": 30, "size": [3, 2], "colour": true},
	"banner": {"name": "Banner", "cat": "Statues", "gems": 20, "colour": true},
	"pillar": {"name": "Old pillar", "cat": "Statues", "gems": 40, "scrap": 2, "block": true},
	"kin_statue": {"name": "Kin statue", "cat": "Statues", "gems": 120, "scrap": 6, "block": true},
	"fountain": {"name": "Fountain", "cat": "Statues", "gems": 150, "scrap": 8, "size": [2, 2], "block": true},
}
const CATS := ["Buildings", "Fences", "Paths", "Garden", "Lights", "Furniture", "Statues", "Island"]
const COLOURS := ["e0607e", "f2c84a", "5ab0f0", "8fd16a", "b48cf2", "f3eee2"]

## The farm's lamps and flower beds start out as decorations, so they can be moved or put away too.
const STOCK := [["lamp_post", 36.2, 30.0], ["lamp_post", 39.6, 35.5], ["lamp_post", 36.4, 35.6], ["lamp_post", 41.0, 30.0],
	["lamp_post", 26.0, 29.2], ["lamp_post", 51.2, 36.6], ["flowers", 35.6, 28.6], ["flowers", 40.4, 28.6], ["flowers", 39.6, 37.4]]

# ------------------------------------------------------------------ the save
static func fresh() -> Dictionary:
	return {"v": 1, "grow": 0, "theme": "meadow", "themes": ["meadow"], "b": {}, "deco": [], "paths": {}, "water": {}, "inv": {}, "uid": 0,
		"seed": 0, "made": true, "cleared": {}}

## Fills in the layout on a save that doesn't have one yet (a new game, or one from before build
## mode): buildings stay on their lots, and the farm's lamps and flower beds become decorations.
static func ensure(d: Dictionary) -> Dictionary:
	if typeof(d.get("layout")) != TYPE_DICTIONARY:
		var L := fresh()
		if not bool(d.get("tutorial", {}).get("home", false)) and int(d.get("matches", 0)) == 0:
			# a brand new home: its own wild land, and a first look round to choose where things go
			var r := RandomNumberGenerator.new(); r.randomize()
			L["seed"] = r.randi_range(1, 2147483646)
			L["made"] = false
		for s in STOCK:
			var e := {"u": _next_uid(L), "id": String(s[0]), "x": int(floor(float(s[1]))), "z": int(floor(float(s[2]))), "r": 0, "px": float(s[1]), "pz": float(s[2])}
			(L["deco"] as Array).append(e)
		d["layout"] = L
	var L: Dictionary = d["layout"]
	var f := fresh()
	for k in f:
		if not L.has(k) or typeof(L[k]) != typeof(f[k]):
			L[k] = f[k] if typeof(f[k]) != TYPE_DICTIONARY and typeof(f[k]) != TYPE_ARRAY else f[k].duplicate()
	L["grow"] = clampi(int(L["grow"]), 0, EXPAND.size())
	if not THEMES.has(String(L["theme"])): L["theme"] = "meadow"
	# JSON brings numbers back as floats; drop anything that isn't in the catalog any more
	var keep: Array = []
	for e in L["deco"]:
		if typeof(e) == TYPE_DICTIONARY and CATALOG.has(String(e.get("id", ""))):
			e["x"] = int(e.get("x", 0)); e["z"] = int(e.get("z", 0)); e["r"] = int(e.get("r", 0)) % 4
			if not e.has("u"): e["u"] = _next_uid(L)
			e["u"] = int(e["u"])
			keep.append(e)
	L["deco"] = keep
	for b in (L["b"] as Dictionary).keys():
		var be = L["b"][b]
		if not Data.BUILDINGS.has(b) or typeof(be) != TYPE_DICTIONARY:
			(L["b"] as Dictionary).erase(b)
			continue
		be["x"] = int(be.get("x", 0)); be["z"] = int(be.get("z", 0)); be["r"] = int(be.get("r", 0)) % 4
	return L

static func of(d: Dictionary) -> Dictionary:
	var L = d.get("layout")
	return L if typeof(L) == TYPE_DICTIONARY else fresh()

static func _next_uid(L: Dictionary) -> int:
	L["uid"] = int(L.get("uid", 0)) + 1
	return int(L["uid"])

static func key(x: int, z: int) -> String:
	return "%d,%d" % [x, z]

static func unkey(k: String) -> Vector2i:
	var p := k.split(",")
	return Vector2i(int(p[0]), int(p[1])) if p.size() == 2 else Vector2i(-1, -1)

# ------------------------------------------------------------------ buildings
## The building's footprint before turning: [width along x, depth along z].
static func base_size(b: String) -> Vector2i:
	var rc: Array = Data.BUILDINGS[b]["rect"]
	return Vector2i(int(rc[2]) - int(rc[0]) + 1, int(rc[3]) - int(rc[1]) + 1)

static func turned(sz: Vector2i, r: int) -> Vector2i:
	return Vector2i(sz.y, sz.x) if r % 2 == 1 else sz

## {x, z, r}: where a building stands (its default lot unless you've moved it).
static func place_of(b: String, d: Dictionary) -> Dictionary:
	var L := of(d)
	var be = (L.get("b", {}) as Dictionary).get(b)
	if typeof(be) == TYPE_DICTIONARY:
		return {"x": int(be["x"]), "z": int(be["z"]), "r": int(be.get("r", 0)) % 4}
	var rc: Array = Data.BUILDINGS[b]["rect"]
	return {"x": int(rc[0]), "z": int(rc[1]), "r": 0}

## The tile rect [x0, z0, x1, z1] a building covers where it stands now.
static func rect_of(b: String, d: Dictionary) -> Array:
	var p := place_of(b, d)
	return rect_at(b, int(p["x"]), int(p["z"]), int(p["r"]))

static func rect_at(b: String, x: int, z: int, r: int) -> Array:
	var sz := turned(base_size(b), r)
	return [x, z, x + sz.x - 1, z + sz.y - 1]

static func rect_center(rc: Array) -> Vector3:
	return Vector3((rc[0] + rc[2] + 1) * 0.5, 0, (rc[1] + rc[3] + 1) * 0.5)

## Which way a quarter turn faces: the door side (+z unturned).
static func facing(r: int) -> Vector3:
	return [Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(-1, 0, 0)][r % 4]

## The spot just outside a building's door (or the middle of its lot's front), for a footprint at x,z turned r.
static func door_at(b: String, x: int, z: int, r: int) -> Vector3:
	var rc := rect_at(b, x, z, r)
	return rect_center(rc) + facing(r) * (base_size(b).y * 0.5 + 1.1)

static func cells_of(rc: Array) -> Array:
	var out: Array = []
	for zz in range(int(rc[1]), int(rc[3]) + 1):
		for xx in range(int(rc[0]), int(rc[2]) + 1):
			out.append(Vector2i(xx, zz))
	return out

# ------------------------------------------------------------------ decorations
static func size_of(id: String, r: int) -> Vector2i:
	var s: Array = CATALOG.get(id, {}).get("size", [1, 1])
	return turned(Vector2i(int(s[0]), int(s[1])), r)

static func deco_cells(e: Dictionary) -> Array:
	var sz := size_of(String(e["id"]), int(e.get("r", 0)))
	return cells_of([int(e["x"]), int(e["z"]), int(e["x"]) + sz.x - 1, int(e["z"]) + sz.y - 1])

static func deco_center(e: Dictionary) -> Vector3:
	if e.has("px"):
		return Vector3(float(e["px"]), 0, float(e["pz"]))
	var sz := size_of(String(e["id"]), int(e.get("r", 0)))
	return Vector3(int(e["x"]) + sz.x * 0.5, 0, int(e["z"]) + sz.y * 0.5)

static func blocks(id: String) -> bool:
	return bool(CATALOG.get(id, {}).get("block", false))

## [gems, scrap] for n of a catalog item.
static func price(id: String, n := 1) -> Array:
	var c: Dictionary = CATALOG.get(id, {})
	return [int(c.get("gems", 0)) * n, int(c.get("scrap", 0)) * n]

# ------------------------------------------------------------------ the land
static func lobe(level: int) -> Array:
	var rr := LOBE_R0 + LOBE_STEP * level
	return [LOBE_NW + rr, rr]

## The home world: the islands from their definitions, then the main island's meadow grown out to
## the save's size. The original island's shape is untouched, so nothing that stood on it falls off.
static func make_world(world: World, level: int, seed := 0) -> void:
	var defs: Array = [["main", CORE_C, CORE_R]]
	for k in Data.ISLES:
		defs.append([k, Data.ISLES[k]["c"], Data.ISLES[k]["r"]])
	defs.append_array(HomeTraining.defs())      # the Training Grounds, which every home has
	world.make_islands(SEED, W, H, defs)
	grow_main(world, level, seed)

## The meadow's outline. seed 0 is the classic island; any other seed gives its own shape: the
## meadow's size wobbles, its edge noise differs and one to three headlands bulge out of it.
static func shape_of(level: int, seed: int) -> Array:
	var lb := lobe(level)
	var c: Vector2 = lb[0]; var rr: Vector2 = lb[1]
	var bulges: Array = []
	if seed != 0:
		var r := RandomNumberGenerator.new(); r.seed = seed
		var j := Vector2(r.randf_range(-1.5, 2.5), r.randf_range(-1.0, 2.0))
		rr += j; c += j
		for k in r.randi_range(1, 3):
			var a := r.randf_range(-0.25 * PI, 0.75 * PI)          # east round to south
			var at := c + Vector2(cos(a) * rr.x, sin(a) * rr.y) * r.randf_range(0.8, 0.95)
			bulges.append([at, Vector2(r.randf_range(4.5, 7.5), r.randf_range(4.0, 6.5))])
	return [c, rr, bulges]

static func grow_main(world: World, level: int, seed := 0) -> void:
	var shape := FastNoiseLite.new(); shape.seed = SEED if seed == 0 else seed; shape.frequency = 0.12
	var drng := RandomNumberGenerator.new(); drng.seed = SEED + 3
	var sh := shape_of(level, seed)
	var c: Vector2 = sh[0]; var rr: Vector2 = sh[1]
	var bulges: Array = sh[2]
	# keep a strip of sky round every other isle
	var near := {}
	for i in world.kind.size():
		if world.island[i] > 0:
			var x0 := i % world.w; var z0 := i / world.w
			for dz in range(-GAP, GAP + 1):
				for dx in range(-GAP, GAP + 1):
					near[(z0 + dz) * world.w + x0 + dx] = true
	var cells: Array = world.islands[0]["cells"]
	for z in range(1, world.h - 1):
		for x in range(1, world.w - 1):
			var i := world.idx(x, z)
			if world.island[i] > 0 or near.has(i):
				continue
			var dl := Vector2((x + 0.5 - c.x) / rr.x, (z + 0.5 - c.y) / rr.y).length()
			for bg in bulges:
				dl = minf(dl, Vector2((x + 0.5 - bg[0].x) / bg[1].x, (z + 0.5 - bg[0].y) / bg[1].y).length())
			if dl + shape.get_noise_2d(x, z) * 0.14 >= 1.0:
				continue
			var dc := Vector2((x + 0.5 - CORE_C.x) / CORE_R.x, (z + 0.5 - CORE_C.y) / CORE_R.y).length()
			var dep := -(2.0 + (1.0 - minf(dl, dc)) * 5.0 + drng.randf())
			if world.kind[i] == World.T_VOID:
				world.kind[i] = World.T_GROUND
				world.island[i] = 0
				world.depth[i] = dep
				cells.append(Vector2i(x, z))
			else:
				world.depth[i] = minf(world.depth[i], dep)

## Open ground on the main island (what you can build on, before anything is put down).
static func main_tiles(level: int, seed := 0) -> int:
	var w := World.new()
	make_world(w, level, seed)
	var n := 0
	for i in w.kind.size():
		if w.island[i] == 0 and w.kind[i] == World.T_GROUND: n += 1
	w.free()
	return n

static var _tiles := {}
## How many tiles the next expansion adds (cached: it builds two worlds to count).
static func expand_gain(level: int, seed := 0) -> int:
	if level >= EXPAND.size():
		return 0
	for lv in [level, level + 1]:
		if not _tiles.has(Vector2i(lv, seed)): _tiles[Vector2i(lv, seed)] = main_tiles(lv, seed)
	return int(_tiles[Vector2i(level + 1, seed)]) - int(_tiles[Vector2i(level, seed)])

# ------------------------------------------------------------------ the wild
## A procedural home's wild land: copses of trees, boulders and a pond or a stream out in the
## meadow, away from the farm. Returns {tile index: "tree" | "rock" | "water"}; keep is a set of
## tile indices to leave alone (paths, kept-clear spots, lots). Deterministic for a seed.
static func wild(world: World, seed: int, keep: Dictionary) -> Dictionary:
	var out := {}
	if seed == 0:
		return out
	var r := RandomNumberGenerator.new(); r.seed = seed + 101
	var cand: Array = []
	for i in world.kind.size():
		if world.island[i] != 0 or world.kind[i] != World.T_GROUND or keep.has(i) or world.paint.has(i) or world.bridge.has(i):
			continue
		var x := i % world.w; var z := i / world.w
		var dc := Vector2((x + 0.5 - CORE_C.x) / CORE_R.x, (z + 0.5 - CORE_C.y) / CORE_R.y).length()
		if dc < 1.1 or world.edge_dist(x, z, 3) < 2:
			continue
		cand.append(i)
	if cand.is_empty():
		return out
	var ok_tile := func(i: int) -> bool:
		return i >= 0 and i < world.kind.size() and world.island[i] == 0 and world.kind[i] == World.T_GROUND and not keep.has(i) and not world.paint.has(i) and not out.has(i)
	# copses: short random walks of trees with the odd boulder
	for k in r.randi_range(10, 15):
		var i: int = cand[r.randi_range(0, cand.size() - 1)]
		var what := "tree" if r.randf() < 0.7 else "rock"
		for s in r.randi_range(3, 10):
			if ok_tile.call(i): out[i] = what if r.randf() < 0.8 else ("rock" if what == "tree" else "tree")
			var dv: Vector2i = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)][r.randi_range(0, 3)]
			i += dv.y * world.w + dv.x
	# water: a round pond, or a stream winding in from the island's edge
	var wi: int = cand[r.randi_range(0, cand.size() - 1)]
	if r.randf() < 0.5:
		var wx := wi % world.w; var wz := wi / world.w
		var pr := Vector2(r.randf_range(1.6, 2.8), r.randf_range(1.4, 2.4))
		for dz in range(-3, 4):
			for dx in range(-3, 4):
				if Vector2(dx / pr.x, dz / pr.y).length() < 1.0 and ok_tile.call(wi + dz * world.w + dx):
					out[wi + dz * world.w + dx] = "water"
	else:
		var p := Vector2(wi % world.w, wi / world.w)
		var dir := Vector2.from_angle(r.randf() * TAU)
		for s in r.randi_range(10, 18):
			var ti := int(p.y) * world.w + int(p.x)
			if ok_tile.call(ti): out[ti] = "water"
			dir = dir.rotated(r.randf_range(-0.5, 0.5))
			p += dir
	return out

## Every bit of open ground on the main island has to be reachable from the house: wild tiles that
## shut a pocket in are taken out again until none do. Returns the wild that's left.
static func open_up(world: World, start: Vector2i, wild_t: Dictionary) -> Dictionary:
	for _round in 12:
		var seen := {}
		var q: Array = [world.idx(start.x, start.y)]
		seen[q[0]] = true
		var head := 0
		while head < q.size():
			var i: int = q[head]; head += 1
			for dv in [1, -1, world.w, -world.w]:
				var j: int = i + dv
				if j < 0 or j >= world.kind.size() or seen.has(j): continue
				if world.kind[j] != World.T_GROUND and not world.bridge.has(j): continue
				seen[j] = true
				q.append(j)
		var shut: Array = []
		for i in world.kind.size():
			if world.island[i] == 0 and world.kind[i] == World.T_GROUND and not seen.has(i): shut.append(i)
		if shut.is_empty():
			break
		# open the wild next to each pocket
		for i in shut:
			for dv in [1, -1, world.w, -world.w]:
				var j: int = i + dv
				if wild_t.has(j):
					wild_t.erase(j)
					world.kind[j] = World.T_GROUND
	return wild_t

## Feeders left out over what used to be ground (the Orchard Isle moved when the islands grew)
## go back to open ground near the pot.
static func rescue_feeders(world: World) -> void:
	var fs: Array = Save.d.get("feeders", [])
	for f in fs:
		var x := float(f.get("x", 0.0)); var z := float(f.get("z", 0.0))
		if not world.inb(int(floor(x)), int(floor(z))) or world.is_void(x, z) or world.kind[world.idx(int(floor(x)), int(floor(z)))] != World.T_GROUND:
			var others: Array = fs.filter(func(o): return o != f).map(func(o): return Vector3(float(o.get("x", 0.0)), 0, float(o.get("z", 0.0))))
			var p := world.free_spot_near(Econ.FEEDER_START, others, 2.8, 0.5, 14.0)
			f["x"] = snappedf(p.x, 0.1); f["z"] = snappedf(p.z, 0.1)
