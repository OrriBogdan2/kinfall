extends RefCounted
## Checks generated maps: every island must be reachable from every other through jump pads.
func run(seeds: Array, size := 64, n_isl := 7) -> void:
	var bad := 0
	var walled := 0
	var tot_pads := 0; var tot_links := 0; var tot_rings := 0
	for sd in seeds:
		var w := World.new()
		var t0 := Time.get_ticks_msec()
		w.generate(sd, size, n_isl)
		if Time.get_ticks_msec() - t0 > 2000: print("SLOW seed=", sd, " ms=", Time.get_ticks_msec() - t0)
		var n := w.islands.size()
		var ok := true
		for a in n:
			var seen := {a: true}; var q := [a]
			while q.size() > 0:
				var cur: int = q.pop_front()
				for pd in w.pads + w.links:
					if pd["from"] == cur and not seen.has(pd["to"]):
						seen[pd["to"]] = true; q.append(pd["to"])
			if seen.size() < n:
				ok = false
		for pd in w.pads:
			for o in w.pads:
				if Vector2(o["pos"].x - pd["land"].x, o["pos"].z - pd["land"].z).length() < 2.5:
					ok = false
		# walls must never cut off part of an island
		for ii in n:
			var cells: Array = w.islands[ii]["cells"]
			var ground: Array = cells.filter(func(c): return w.kind[w.idx(c.x, c.y)] == World.T_GROUND)
			if ground.is_empty(): continue
			var seen2 := {ground[0]: true}; var q2: Array = [ground[0]]
			while q2.size() > 0:
				var cc: Vector2i = q2.pop_front()
				for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx: Vector2i = cc + dv
					if not seen2.has(nx) and w.inb(nx.x, nx.y) and w.kind[w.idx(nx.x, nx.y)] == World.T_GROUND and w.island[w.idx(nx.x, nx.y)] == ii:
						seen2[nx] = true; q2.append(nx)
			if ground.size() - seen2.size() > 0:
				walled += ground.size() - seen2.size()
		tot_pads += w.pads.size(); tot_links += w.links.size(); tot_rings += w.rings.size()
		if not ok or w.portal_spots.size() < 3 or w.spawns.size() < 6:
			bad += 1
			print("MAP BAD seed=%d islands=%d pads=%d portals=%d spawns=%d" % [sd, n, w.pads.size(), w.portal_spots.size(), w.spawns.size()])
		w.free()
	print("walled-off tiles: ", walled)
	print("MAPCHECK done, bad: ", bad, " of ", seeds.size(), "  avg pads %.1f glide links %.1f rings %.1f" % [tot_pads / float(seeds.size()), tot_links / float(seeds.size()), tot_rings / float(seeds.size())])

## Checks an authored map across many match seeds: every island reachable from every other (bridges,
## wind roads and pads), every point of interest on solid ground, no walls cutting off ground, every
## island with rim you can climb back onto, exits where the layout says, and spawns spread fairly.
func run_authored(id: String, seeds: Array) -> void:
	var L := World.load_layout(id)
	if L.is_empty():
		print("MAPCHECK AUTHORED: no layout ", id); return
	var bad := 0
	for sd in seeds:
		var w := World.new()
		var t0 := Time.get_ticks_msec()
		w.generate_authored(L, sd)
		var ms := Time.get_ticks_msec() - t0
		var n := w.islands.size()
		var probs: Array = []
		for a in n:
			var seen := {a: true}; var q := [a]
			while q.size() > 0:
				var cur: int = q.pop_front()
				for pd in w.pads + w.links:
					if pd["from"] == cur and not seen.has(pd["to"]):
						seen[pd["to"]] = true; q.append(pd["to"])
			if seen.size() < n: probs.append("island %s can't reach all (%d/%d)" % [w.islands[a].get("id", a), seen.size(), n])
		for ii in n:
			var poi := w._poi(ii)
			if poi == Vector3.INF or w.is_block(poi.x, poi.z): probs.append("poi of %s not on open ground" % w.islands[ii].get("id", ii))
			var lips := 0
			for cell in w.islands[ii]["cells"]:
				if w.lip.has(w.idx(cell.x, cell.y)): lips += 1
			if lips < 6: probs.append("%s has almost no grabbable rim (%d)" % [w.islands[ii].get("id", ii), lips])
			var cells: Array = w.islands[ii]["cells"]
			var ground: Array = cells.filter(func(c): return w.kind[w.idx(c.x, c.y)] == World.T_GROUND)
			if ground.is_empty(): continue
			var seen2 := {ground[0]: true}; var q2: Array = [ground[0]]
			while q2.size() > 0:
				var cc: Vector2i = q2.pop_front()
				for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx: Vector2i = cc + dv
					if not seen2.has(nx) and w.inb(nx.x, nx.y) and w.kind[w.idx(nx.x, nx.y)] == World.T_GROUND and w.island[w.idx(nx.x, nx.y)] == ii:
						seen2[nx] = true; q2.append(nx)
			if ground.size() - seen2.size() > 2: probs.append("%s: %d tiles walled off" % [w.islands[ii].get("id", ii), ground.size() - seen2.size()])
		var n_ex := 0
		for ek in ["portals", "docks", "outposts", "hatches"]: n_ex += (L.get(ek, []) as Array).size()
		if w.portal_spots.size() != n_ex: probs.append("exits %d of %d" % [w.portal_spots.size(), n_ex])
		# spawn fairness: how far the nearest other spawn island is, for each spawn island
		var by := {}
		for sp in w.spawns: by[w.island_of(sp.x, sp.z)] = sp
		var dmins: Array = []
		for a in by:
			var dm := 1e9
			for b in by:
				if a != b: dm = minf(dm, Vector2(by[a].x - by[b].x, by[a].z - by[b].z).length())
			dmins.append(dm)
		dmins.sort()
		var tiles := 0
		for i in w.kind.size(): if w.kind[i] != World.T_VOID: tiles += 1
		if sd == seeds[0]:
			print("AUTHORED %s: islands=%d ground=%d sheer=%d lip=%d pads=%d links=%d winds=%d updrafts=%d portals=%d spawns=%d chests=%d camps=%d shrines=%d labels=%d ms=%d" % [id, n, tiles, w.sheer.size(), w.lip.size(), w.pads.size(), w.links.size(), w.winds.size(), w.updrafts.size(), w.portal_spots.size(), w.spawns.size(), w.chest_spots.size(), w.camp_spots.size(), w.shrine_spots.size(), w.labels.size(), ms])
			print("  spawn islands %d, nearest-neighbour spacing min %.1f median %.1f" % [by.size(), dmins[0] if dmins.size() > 0 else 0.0, dmins[dmins.size() / 2] if dmins.size() > 0 else 0.0])
		if not probs.is_empty():
			bad += 1
			print("MAP BAD seed=%d: %s" % [sd, "; ".join(probs)])
		w.free()
	print("MAPCHECK AUTHORED done, bad: ", bad, " of ", seeds.size())

