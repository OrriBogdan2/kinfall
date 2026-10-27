extends RefCounted
## Checks generated maps: every island must be reachable from every other through jump pads.
func run(seeds: Array) -> void:
	var bad := 0
	for sd in seeds:
		var w := World.new()
		w.generate(sd, 64, 7)
		var n := w.islands.size()
		var ok := true
		for a in n:
			var seen := {a: true}; var q := [a]
			while q.size() > 0:
				var cur: int = q.pop_front()
				for pd in w.pads:
					if pd["from"] == cur and not seen.has(pd["to"]):
						seen[pd["to"]] = true; q.append(pd["to"])
			if seen.size() < n:
				ok = false
		for pd in w.pads:
			for o in w.pads:
				if Vector2(o["pos"].x - pd["land"].x, o["pos"].z - pd["land"].z).length() < 2.5:
					ok = false
		if not ok or w.portal_spots.size() < 3 or w.spawns.size() < 6:
			bad += 1
			print("MAP BAD seed=%d islands=%d pads=%d portals=%d spawns=%d" % [sd, n, w.pads.size(), w.portal_spots.size(), w.spawns.size()])
		w.free()
	print("MAPCHECK done, bad: ", bad, " of ", seeds.size())
