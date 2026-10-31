extends Node3D
## Every race with every one of its head styles (hair, fur, crystals, leaves, crests, feathers), one
## race per row. Run with -- --hair-gallery (add --hair-col=N for another colour). check() is the
## headless --hair-check: every race x style must grow something visible on the head.

func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Look.environment({"top": Color("2a4a8a"), "mid": Color("6a8ad0"), "horizon": Color("ffd2a8"), "stars": 0.0})
	add_child(env)
	Look.lights(self, Color("fff1dc"), 1.0, Vector3(-35, -30, 0), 30.0)
	var hc := 3
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hair-col="): hc = int(a.substr(11))
	var cols := 0
	for r in Models.RACES.size():
		var styles := Models.hair_styles(r)
		cols = maxi(cols, styles.size())
		for i in styles.size():
			var lk := {"race": r, "hair": i, "hair_v": 2, "hair_col": (hc + r * 5) % Models.LOOK_HAIR.size(), "skin": int(Models.RACES[r]["skin"]) if r > 0 else 1,
				"gender": (i + r) % 2, "face": 0, "body": 1, "outfit": 2}
			var h := Models.hunter("medium", Data.TEAM_COLORS[0], "rifle", "bare", lk)
			h.position = Vector3(i * 0.68, -r * 0.92, r * 1.2)
			h.rotation.y = PI + 0.55
			(h.get_node("TeamRing") as Node3D).visible = false
			var gun := h.get_node_or_null("Rig/Torso/Aim/Gun")
			if gun: (gun as Node3D).visible = false
			add_child(h)
			var l := Label3D.new()
			l.text = "%s · %s" % [Models.LOOK_RACES[r], styles[i]]
			l.font_size = 20; l.pixel_size = 0.0022; l.outline_size = 6
			l.position = h.position + Vector3(0, 0.98, 0.5)
			add_child(l)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 5.9
	cam.position = Vector3((cols - 1) * 0.34, -1.05, 20.0)
	add_child(cam)
	cam.make_current()

## Every race x style grows a hair mesh that shows outside the head, reaches above the head's
## middle and touches the head (nothing hidden inside it, nothing floating). Returns the failures.
static func check() -> int:
	var bad := 0
	var n := 0
	for r in Models.RACES.size():
		var styles := Models.hair_styles(r)
		for i in styles.size():
			if styles[i] == "Bald":
				continue
			for outfit in ["bare", "veil", "sage"]:
				var lk := {"race": r, "hair": i, "hair_v": 2, "hair_col": 3, "gender": i % 2, "face": 0, "body": 1, "outfit": 0}
				var h := Models.hunter("medium", Data.TEAM_COLORS[0], "rifle", outfit, lk)
				var head: Node3D = h.get_node("Rig/Torso/HeadPivot")
				var hair := head.get_node_or_null("Hair") as Node3D
				var centre := Vector3(0, 0.18, 0)
				var verts := 0; var outside := 0; var top := -9.0; var nearest := 9.0
				if hair:
					for ch in hair.get_children():
						if not (ch is MeshInstance3D) or (ch as MeshInstance3D).mesh == null:
							continue
						var mi := ch as MeshInstance3D
						var xf := hair.transform * mi.transform
						for si in mi.mesh.get_surface_count():
							var vs: PackedVector3Array = mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
							for v in vs:
								var p := xf * v
								verts += 1
								var d := p.distance_to(centre)
								if d > 0.255: outside += 1
								nearest = minf(nearest, d)
								top = maxf(top, p.y)
				n += 1
				# under a hood or helmet a cap of hair may hide; something must still show without one
				var need := 30 if outfit == "bare" else 1
				var ok := verts > 0 and outside >= need and top > centre.y and nearest < 0.32
				if outfit != "bare" and outside < need:
					ok = true    # covered by headwear is allowed; the bare look is what must show
				if not ok:
					bad += 1
					print("HAIR FAIL %s / %s (%s): verts %d outside %d top %.2f nearest %.2f" % [Models.LOOK_RACES[r], styles[i], outfit, verts, outside, top, nearest])
				h.free()
	# old saves (an index into the shared list, no "hair_v") map into every race's own list
	for r in Models.RACES.size():
		for old in Models.LOOK_HAIRS.size():
			var cl := Models.clean_look({"race": r, "hair": old})
			if int(cl["hair"]) < 0 or int(cl["hair"]) >= Models.hair_styles(r).size():
				bad += 1
				print("HAIR FAIL old save race %d hair %d -> %d" % [r, old, int(cl["hair"])])
	print("HAIR CHECK: %d race x style looks" % n)
	return bad

