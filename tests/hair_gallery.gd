extends Node3D
## Every race with every one of its head styles (hair, fur, crystals, leaves, crests, feathers), one
## race per row. Run with -- --hair-gallery (add --hair-col=N for another colour). check() is the
## headless --hair-check: every race x style must grow something visible on the head.

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--class-lineup" in args:
		_class_lineup()
		return
	var env := WorldEnvironment.new()
	env.environment = Look.environment({"top": Color("2a4a8a"), "mid": Color("6a8ad0"), "horizon": Color("ffd2a8"), "stars": 0.0})
	add_child(env)
	Look.lights(self, Color("fff1dc"), 1.0, Vector3(-35, -30, 0), 30.0)
	var back := "--hair-back" in args          # look at them from behind instead
	var cols := 0
	for r in Models.RACES.size():
		var styles := Models.hair_styles(r)
		cols = maxi(cols, styles.size())
		for i in styles.size():
			var lk := {"race": r, "hair": i, "hair_v": 2, "hair_col": [0, 5, 3, 6, 10, 7, 12, 1, 13, 8, 2, 11, 14, 9][i % 14], "skin": int(Models.RACES[r]["skin"]) if r > 0 else 1,
				"gender": (i + r) % 2, "face": 0, "body": 1, "outfit": 2}
			var h := Models.hunter("medium", Data.TEAM_COLORS[0], "rifle", "bare", lk)
			# heads only: everything below the neck is hidden so the rows can sit close together
			var torso: Node3D = h.get_node("Rig/Torso")
			for ch in torso.get_children():
				if ch.name != "HeadPivot" and ch is Node3D: (ch as Node3D).visible = false
			(h.get_node("Rig/Legs") as Node3D).visible = false
			(h.get_node("TeamRing") as Node3D).visible = false
			h.scale = Vector3.ONE * 1.6
			h.rotation.y = (0.6 if back else PI + 0.55)
			add_child(h)
			# every race is a different height: line the heads up on a grid
			var hp: Vector3 = (h.get_node("Rig/Torso/HeadPivot") as Node3D).global_position
			h.position += Vector3(i * 1.05, -r * 1.2, 0) - Vector3(hp.x, hp.y, 0)
			var l := Label3D.new()
			l.text = "%s · %s" % [Models.LOOK_RACES[r], styles[i]]
			l.font_size = 20; l.pixel_size = 0.0028; l.outline_size = 6
			l.position = Vector3(i * 1.05, -r * 1.2 - 0.42, 0.8)
			add_child(l)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 8.4
	cam.position = Vector3((cols - 1) * 0.525, -2.75, 20.0)
	add_child(cam)
	cam.make_current()

## The three classes on two races, from the match camera: who is a heavy should be obvious.
func _class_lineup() -> void:
	var env := WorldEnvironment.new()
	env.environment = Look.environment({"top": Color("2a4a8a"), "mid": Color("6a8ad0"), "horizon": Color("ffd2a8"), "stars": 0.0})
	add_child(env)
	Look.lights(self, Color("fff1dc"), 1.0, Vector3(-52, -35, 0), 40.0)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(40, 30)
	ground.mesh = pm
	ground.material_override = Models.toon(Color("6f9a4a"), false)
	add_child(ground)
	var rows := [[2, {"light": "smg", "medium": "rifle", "heavy": "shotgun"}], [1, {"light": "sniper", "medium": "longsword", "heavy": "minigun"}]]
	for ri in rows.size():
		var race: int = rows[ri][0]
		var ws: Dictionary = rows[ri][1]
		var ci := 0
		for cls in ["light", "medium", "heavy"]:
			var lk := {"race": race, "hair": 1, "hair_v": 2, "hair_col": 3 + ri * 4, "skin": int(Models.RACES[race]["skin"]), "gender": ci % 2, "outfit": 3 + ri}
			var h := Models.hunter(cls, Data.TEAM_COLORS[ri], String(ws[cls]), "", lk)
			h.position = Vector3((ci - 1) * 2.4, 0, (ri - 0.5) * 2.6)
			h.rotation.y = PI * 0.82 + ci * 0.25
			add_child(h)
			var l := Label3D.new()
			l.text = "%s · %s" % [cls.capitalize(), Models.LOOK_RACES[race]]
			l.font_size = 40; l.pixel_size = 0.006; l.outline_size = 10
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.position = h.position + Vector3(0, 0.05, 1.0)
			add_child(l)
			ci += 1
	var cam := Camera3D.new()
	cam.position = Vector3(0, 9.0, 7.5); cam.rotation = Vector3(-0.85, 0, 0); cam.fov = 50
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

