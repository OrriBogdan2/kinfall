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
