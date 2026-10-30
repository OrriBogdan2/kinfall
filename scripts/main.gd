extends Node
## Holds whichever screen is showing: home, a match, or the results.

var current: Node = null
var fade: ScreenFade

## Real play gets ink-wipe transitions between screens. Tooling that screenshots by frame count,
## headless checks and autoplay skip them so their timing stays exact (--show-fade forces them on).
func _fades_on() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	if _has_arg("--show-fade"):
		return true
	return not (_has_arg("--shot=") or _has_arg("--autoplay") or _has_arg("--simtest"))

func _ready() -> void:
	Game.main = self
	fade = ScreenFade.new()
	add_child(fade)
	if _fades_on():
		fade.boot()     # carry on from the boot splash: covered, logo showing, until the first screen is up
	var args := OS.get_cmdline_user_args()
	var opts := {}
	for a in args:
		if a.begins_with("--overlay="):
			# test: open one of the overlay menus a moment after the screen appears
			var which := a.substr(10).split(":")
			get_tree().create_timer(0.6).timeout.connect(func():
				Overlay.ctx = Overlay.ctx_now()
				if which[0] == "pause": Overlay.open_pause(Overlay.ctx_now())
				elif which[0] == "settings":
					if which.size() > 1: Overlay.tab = which[1]
					Overlay.open_settings()
				elif which[0] == "admin": Overlay.open_admin()
				elif which[0] == "saves": Overlay.open_saves()
				elif which[0] == "inventory":
					if which.size() > 1: Overlay.inv_tab = which[1]
					Overlay.open_inventory())
		if a.begins_with("--seed="): opts["seed"] = int(a.substr(7))
		if a == "--god": opts["god"] = true
		if a == "--autoplay": opts["autoplay"] = true
		if a == "--glide-demo": opts["glide_demo"] = true
		if a == "--ledge-demo": opts["ledge_demo"] = true
		if a.begins_with("--mates-revive="): opts["mates_revive"] = float(a.substr(15))
		if a == "--mates-demo": opts["mates_demo"] = true; opts["no_drop"] = true; opts["god"] = true; opts["squad"] = 4; opts["teams"] = 2
		if a == "--life-demo": opts["life_demo"] = true; opts["no_drop"] = true; opts["squad"] = 3; opts["teams"] = 3
		if a.begins_with("--length="): opts["length"] = float(a.substr(9))
		if a == "--no-drop": opts["no_drop"] = true
		if a == "--train-demo": opts["train_demo"] = true; opts["no_drop"] = true
		if a.begins_with("--train-demo="): opts["train_demo"] = a.substr(13); opts["no_drop"] = true
		if a.begins_with("--aim-demo="): opts["aim_demo"] = a.substr(11); opts["no_drop"] = true
		if a == "--loot-demo": opts["loot_demo"] = true
		if a == "--stomp-demo": opts["stomp_demo"] = true
		if a == "--ring-demo": opts["ring_demo"] = true; opts["no_drop"] = true
		if a == "--wall-demo": opts["wall_demo"] = true; opts["no_drop"] = true
		if a == "--cone-demo": opts["cone_demo"] = true
		if a == "--crouch-demo": opts["cone_demo"] = true; opts["crouch_demo"] = true
		if a == "--wall-behind": opts["wall_behind"] = true; opts["no_drop"] = true
		if a == "--meteor-test": opts["meteor_test"] = true; opts["no_drop"] = true
		if a == "--break-demo": opts["break_demo"] = true; opts["no_drop"] = true
		if a == "--watch-heart": opts["watch_heart"] = true
		if a.begins_with("--class="): Save.d["cls"] = a.substr(8); Save.d["weapon"] = ""
		if a.begins_with("--weapon="):
			Save.d["weapon"] = a.substr(9)
			for c in Data.CLASSES:
				if (Data.CLASSES[c]["weapons"] as Array).has(a.substr(9)): Save.d["cls"] = c
		if a == "--ability-demo": opts["ability_demo"] = true
		if a == "--fresh": Save.d = Save.fresh()
		if a.begins_with("--test-kin="):
			# test: a save with one kin "species:level:trust", ready to play at home
			var tk := a.substr(11).split(":")
			if Save.d["roster"].is_empty():
				var nk := Save.new_kin(tk[0], "Pip")
				nk["level"] = int(tk[1]) if tk.size() > 1 else 1
				nk["trust"] = float(tk[2]) if tk.size() > 2 else 50.0
				Save.d["roster"].append(nk); Save.d["active"] = nk["uid"]
			Save.d["tutorial"]["home"] = true
			Save.d["tutorial"]["day1_done"] = true
		if a == "--skip-tutorial": Save.d["tutorial"]["home"] = true
		if a.begins_with("--teams="): opts["teams"] = int(a.substr(8))
		if a.begins_with("--tier="): opts["tier"] = int(a.substr(7))
		if a.begins_with("--squad="): opts["squad"] = int(a.substr(8))
		if a.begins_with("--bot-diff="): opts["bot_diff"] = a.substr(11)
		if a == "--perk-demo": opts["perk_demo"] = true
	if "--check" in args:
		var CheckT = load("res://tools/check.gd")
		var bad := 0
		for f in CheckT.new()._scan("res://scripts"):
			var sc = load(f)
			if sc == null or not sc.can_instantiate():
				print("FAIL ", f); bad += 1
		print("CHECK DONE, failures: ", bad)
		get_tree().quit()
		return
	if "--meshtime" in args:
		# test: how long the big map takes to build its meshes, and how many draws it makes
		var w := World.new()
		add_child(w)
		w.generate(5, World.BIG_SIZE, World.BIG_ISLANDS)
		var t0 := Time.get_ticks_msec()
		w.build_meshes()
		var t1 := Time.get_ticks_msec()
		var n := 0; var mm := 0; var inst := 0
		var stack: Array = [w]
		while not stack.is_empty():
			var c: Node = stack.pop_back()
			if c is MeshInstance3D: n += 1 + (1 if (c as MeshInstance3D).material_override and (c as MeshInstance3D).material_override.next_pass else 0)
			if c is MultiMeshInstance3D: mm += 1; inst += (c as MultiMeshInstance3D).multimesh.instance_count
			for ch in c.get_children(): stack.append(ch)
		print("MESHTIME ms=%d mesh_draws=%d multimeshes=%d instances=%d" % [t1 - t0, n, mm, inst])
		get_tree().quit()
		return
	if "--gentime" in args:
		for sz in [[64, 7], [128, 16], [World.BIG_SIZE, World.BIG_ISLANDS]]:
			var t0 := Time.get_ticks_msec()
			var w := World.new()
			w.generate(int(OS.get_environment("GSEED")) if OS.get_environment("GSEED") != "" else 5, sz[0], sz[1])
			var t1 := Time.get_ticks_msec()
			print("GEN ", sz, " ms=", t1 - t0, " islands=", w.islands.size(), " pads=", w.pads.size(), " portals=", w.portal_spots.size(), " spawns=", w.spawns.size())
			w.free()
		get_tree().quit()
		return
	for a in args:
		if a.begins_with("--biome-shot="):
			# tooling: stand next to a region's point of interest, for screenshots of its look
			var want := a.substr(13)
			var sm := Match.new()
			add_child(sm)
			current = sm
			sm.start({"teams": 2, "squad": 1, "tier": 1, "seed": 9, "no_drop": true, "length": 1e9})
			for ii in sm.world.islands.size():
				if String(sm.world.islands[ii].get("id", "")) == want:
					var poi: Vector3 = sm.world._poi(ii)
					var at := sm.world.free_spot_near(poi + Vector3(3.0, 0, 4.5), [], 1.0, 0.5)
					sm.player.teleport(Vector3(at.x, sm.world.ground_at(at.x, at.z), at.z))
					sm.cam.snap(sm.player.pos)
			for o in sm.hunters:
				if o != sm.player:
					o.teleport(sm.world.spawns[-1]); o.ctrl = "idle"
			return
	if "--perch-check" in args:
		# tooling: for each perch, start on the island next to its updraft chain, jump, glide into the
		# short column, then the tall one, then onto the perch. Reports who made it and how high.
		var pm := Match.new()
		add_child(pm)
		pm.start({"teams": 2, "squad": 1, "tier": 0, "seed": 31, "no_drop": true, "length": 1e9, "autoplay": true})
		pm.set_process(false)
		for mb in pm.mobs: mb.queue_free()
		pm.mobs.clear()
		var ph: Hunter = pm.hunters[0]
		for o in pm.hunters:
			o.ctrl = "idle"
			if o != ph: o.teleport(pm.world.spawns[-1])
		ph.ctrl = "local"
		var chains := {"spire": [Vector2(127, 93), Vector2(130, 89)], "emberspire": [Vector2(72, 100), Vector2(78, 92)], "eye": [Vector2(124, 124), Vector2(130, 128)], "needle": [Vector2(146, 48), Vector2(139, 43)]}
		var ok := 0
		for pid in chains:
			var pi := -1
			for ii in pm.world.islands.size():
				if String(pm.world.islands[ii].get("id", "")) == pid: pi = ii
			var steps: Array = chains[pid]
			var u1: Vector2 = steps[0]
			# the nearest ground to the first column that isn't a perch
			var start := Vector3.INF; var bd := 1e9
			for z in range(int(u1.y) - 10, int(u1.y) + 11):
				for x in range(int(u1.x) - 10, int(u1.x) + 11):
					if not pm.world.inb(x, z) or pm.world.kind[pm.world.idx(x, z)] != World.T_GROUND: continue
					var isl := pm.world.island_of(x, z)
					if pm.world.islands[isl].get("perch", false): continue
					var d := Vector2(x + 0.5, z + 0.5).distance_to(u1)
					if d < bd: bd = d; start = Vector3(x + 0.5, pm.world.ground_at(x + 0.5, z + 0.5), z + 0.5)
			ph.teleport(start); ph.vel = Vector3.ZERO; ph.grounded = true; ph.glide_fuel = 1.0; ph.pad = {}
			var goal := pm.world._poi(pi)
			var stage := 0; var t := 0.0; var top_y := 0.0; var made := false
			while t < 14.0:
				var tgt: Vector2 = steps[stage] if stage < steps.size() else Vector2(goal.x, goal.z)
				var to := tgt - Vector2(ph.pos.x, ph.pos.z)
				ph.inp["move"] = to.normalized() if to.length() > 0.4 else Vector2.ZERO
				ph.inp["jump"] = t < 0.1 or (ph.grounded and pm.world.island_of(ph.pos.x, ph.pos.z) != pi)
				ph.inp["glide"] = t > 0.25
				pm.step(Match.DT); t += Match.DT
				top_y = maxf(top_y, ph.pos.y)
				var up: Dictionary = pm.world.updraft_at(ph.pos)
				if stage < steps.size() and not up.is_empty() and ph.pos.y > float(up["top"]) - 0.6:
					stage += 1
				if ph.grounded and pm.world.island_of(ph.pos.x, ph.pos.z) == pi:
					made = true; break
				if ph.out: break
			if made: ok += 1
			print("PERCH %s: %s in %.1fs, highest %.1fm (perch top %.1fm)" % [pid, "made it" if made else "FAILED", t, top_y, goal.y])
			ph.out = false; ph.hp = ph.max_hp
		print("PERCHCHECK done, %d of %d reached" % [ok, chains.size()])
		get_tree().quit()
		return
	if "--biome-check" in args:
		# tooling: an expedition on the authored map; what each biome spawned, then a minute of play
		var bm := Match.new()
		add_child(bm)
		bm.start({"teams": 4, "squad": 1, "tier": int(opts.get("tier", 1)), "seed": int(opts.get("seed", 9)), "no_drop": true, "autoplay": true})
		bm.set_process(false)
		var by := {}
		var rar := [0, 0, 0, 0]; var nm := 0
		for mb in bm.mobs:
			var b := bm.world.biome_at(mb.pos.x, mb.pos.z)
			if not by.has(b): by[b] = []
			by[b].append(String(mb.md["name"]))
			rar[int(mb.get_meta("rarity", 0))] += 1
			if not (mb.get_meta("muts", []) as Array).is_empty(): nm += 1
		for b in by:
			print("BIOME %s: %d mobs, e.g. %s" % [b, by[b].size(), ", ".join((by[b] as Array).slice(0, 6))])
		var hk := {}
		for hz in bm.biomes.hazards: hk[hz["kind"]] = int(hk.get(hz["kind"], 0)) + 1
		print("BIOME rarity common/uncommon/rare/elite %s, mutated %d of %d; hazards %s" % [str(rar), nm, bm.mobs.size(), str(hk)])
		for i in int(60.0 / Match.DT):
			bm.step(Match.DT)
		print("BIOME sim ok, time %.0f, mobs left %d, fields %d" % [bm.time, bm.mobs.filter(func(x): return not x.dead).size(), bm.fields.list.size()])
		get_tree().quit()
		return
	if "--map-overview" in args:
		add_child(load("res://tests/map_overview.gd").new())
		return
	if "--mapcheck-authored" in args:
		load("res://tools/mapcheck.gd").new().run_authored("skyreach", range(1, 21))
		get_tree().quit()
		return
	if "--mapcheck" in args:
		var MC = load("res://tools/mapcheck.gd")
		if not "--big" in args: MC.new().run(range(1, 201))
		MC.new().run(range(1, 41), World.BIG_SIZE, World.BIG_ISLANDS)
		get_tree().quit()
		return
	if "--speak-test" in args:
		load("res://tools/speaktest.gd").new().run()
		get_tree().quit()
		return
	if "--life-check" in args:
		_life_check()
		return
	if "--mantle-check" in args:
		_mantle_check()
		return
	if Array(args).any(func(a): return String(a).begins_with("--weapon-check")):
		_weapon_check()
		return
	if "--base-check" in args:
		_base_check()
		return
	if "--duel-check" in args:
		_duel_check()
		return
	if "--simtest" in args:
		_simtest(opts)
		return
	if OS.has_feature("web"):
		_expose_test_hooks()
		var hash := str(JavaScriptBridge.eval("location.hash", true))
		_soc_test = hash.contains("soctest")
		if _soc_test:
			# test-only: a ready-made player so the shared features can be driven from a script
			Save.d["tutorial"]["home"] = true
			if Save.d["roster"].is_empty():
				var k := Save.new_kin("zapple")
				Save.d["roster"].append(k)
				Save.d["active"] = k["uid"]
			show_screen("home", {})
			return
		if hash.contains("online"):
			Save.d["tutorial"]["home"] = true
			show_screen("lobby", {})
			return
	# a test scene (tests/combat_sandbox.tscn) can ask for a screen directly
	if has_meta("start"):
		var st: Dictionary = get_meta("start")
		show_screen(String(st["screen"]), st.get("opts", {}))
		return
	if "--sandbox" in args:
		var so := {"training": true, "sandbox": true, "sandbox_demo": "--sandbox-demo" in args, "teams": 1, "squad": 1, "tier": 0, "length": 1e9, "seed": 4242, "no_drop": true, "weapon": "rifle"}
		for a in args:
			if a.begins_with("--kin-demo="):
				# test: bring this species (and the next one) and run its whole kit on the dummies
				so["demo_kin"] = a.substr(11)
				so["sandbox_demo"] = false
				so["kin_demo"] = true
		show_screen("match", so)
		return
	if "--results-test" in args:
		show_screen("results", {"extracted": true, "gems": 42, "seeds": {"sunroot": 1}, "caught": [Save.new_kin("zapple")], "knocks": 3, "damage": 512, "time": 201.0, "kin_events": [{"kind": "refused", "text": "refused to jump into a fight that looked too dangerous", "trust": -1.0}], "kin_trust": 57.0, "tonics": 1})
		return
	for a in args:
		if a.begins_with("--reveal-test"):
			# test: the hatch reveal on its own (--reveal-test=<species>)
			var spr := a.substr(14) if a.length() > 14 else "cindle"
			var holder := Node3D.new(); add_child(holder); current = holder
			var rv := KinReveal.new(spr, {})
			holder.add_child(rv)
			rv.proceed.connect(func(): print("REVEAL proceed"))
			return
	if "--lobby-test" in args:
		show_screen("lobby", {})
		return
	var town_arg := ""
	for a in args:
		if a.begins_with("--town="): town_arg = a.substr(7)
	if "--whistle-test" in args and Save.d["roster"].size() < 3:
		# test: a few kin, so some can be indoors when you whistle
		for sp in ["zapple", "cindle", "puddlet"]:
			var wk := Save.new_kin(sp)
			wk["trust"] = 70.0
			Save.d["roster"].append(wk)
		Save.d["active"] = Save.d["roster"][0]["uid"]
		Save.d["tutorial"]["home"] = true
	if "--test-roster" in args and Save.d["roster"].is_empty():
		# test: a ready-made kin so home and the house rooms have someone to pet
		var tk := Save.new_kin("zapple", "Pip")
		Save.d["roster"].append(tk)
		Save.d["active"] = tk["uid"]
		Save.d["tutorial"]["home"] = true
	var room_arg := ""
	for a in args:
		if a.begins_with("--interior="): room_arg = a.substr(11)
	if room_arg != "":
		show_screen("interior", {"room": room_arg})
		if "--interior-pet" in args:
			# test: pet a kin indoors and show that it counted
			get_tree().create_timer(0.5).timeout.connect(func():
				current._pet_kin(current.kins[0])
				print("PET day1=", Save.d["tutorial"].get("day1"), " box=", is_instance_valid(current.day1_box), " gems=", Save.d["gems"]))
		if "--decorate" in args:
			get_tree().create_timer(0.5).timeout.connect(func():
				current._toggle_decorate()
				current._take("plant"))
	elif town_arg != "":
		show_screen("town", {"mode": town_arg, "gid": "test"})
	elif "--visit-test" in args:
		show_screen("home", {"visit": Social.clean_island(Social.profile_doc()), "visit_id": "test"})    # test: visiting an island
	elif "--feel-lab" in args:
		get_tree().change_scene_to_file.call_deferred("res://tests/feel_test.tscn")    # the Supervive feel playground
	elif "--prologue" in args:
		show_screen("prologue", {"then": "title"})    # test: the opening story
	elif "--creator" in args:
		show_screen("hatch", {"create": true})    # test: the hunter creator
	elif "--match" in args:
		show_screen("match", opts)
	elif "--duel" in args:
		show_screen("match", Match.duel_opts())
	elif "--training" in args:
		show_screen("match", {"training": true, "teams": 1, "squad": 1, "tier": 0, "length": 1e9, "seed": 4242, "no_drop": "--no-drop" in args, "perk_demo": "--perk-demo" in args})
	elif "--tutorial" in args:
		show_screen("match", {"tutorial": true, "teams": 1, "squad": 1, "tier": 0, "length": 1500.0, "tut_test": "--tut-test" in args})
	elif args.is_empty() or "--title" in args:
		show_screen("title", {})
	elif Save.d["roster"].is_empty():
		show_screen("hatch", {})
	else:
		show_screen("home", {})

## Menu screens sit on their own layer so they fill the window.
func _layer(scr: Control) -> CanvasLayer:
	var cl := CanvasLayer.new()
	add_child(cl)
	cl.add_child(scr)
	cl.set_meta("screen", scr)
	return cl

func screen_node() -> Node:
	if current is CanvasLayer and current.has_meta("screen"):
		return current.get_meta("screen")
	return current

func _has_arg(prefix: String) -> bool:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix): return true
	return false

var _gen := 0

func show_screen(screen: String, opts: Dictionary) -> void:
	_gen += 1
	var gen := _gen
	var fx := _fades_on()
	if fx and current:
		await fade.cover()
		if gen != _gen:
			return
	if current:
		current.queue_free()
		current = null
	await get_tree().process_frame
	if gen != _gen:
		return    # another screen was asked for while this one was still on its way
	if fx:
		# the next screen builds this frame (often a heavy one); reveal once it has actually drawn
		fade.reveal_after(3, 0.55)
	match screen:
		"match":
			# a loading screen covers building the world; tests that screenshot by frame count skip it
			var ld = null
			if not opts.get("autoplay", false) and (not _has_arg("--shot=") or _has_arg("--show-loading")):
				ld = load("res://scripts/ui/loading.gd").new()
				ld.setup(opts)
				add_child(ld)
				await ld.shown
				await ld.step(0.2)
				if gen != _gen:
					ld.queue_free()
					return
			var m := Match.new()
			m.name = "Match"
			add_child(m)
			current = m
			m.start(opts)
			if ld:
				# hold the match still while the bar finishes, except online where everyone runs together
				if not opts.has("net"): m.set_process(false)
				await ld.finish()
				if is_instance_valid(m) and m.is_inside_tree(): m.set_process(true)
		"results":
			var R = load("res://scripts/ui/results.gd")
			var scr = R.new()
			current = _layer(scr)
			scr.show_result(opts)
		"lobby":
			var L = load("res://scripts/ui/lobby.gd")
			var scr = L.new()
			scr.setup(opts)
			current = _layer(scr)
		"title":
			var Tt = load("res://scripts/ui/title.gd")
			current = Tt.new()
			add_child(current)
		"prologue":
			var Pr = load("res://scripts/ui/prologue.gd")
			current = Pr.new()
			current.set("then_go", String(opts.get("then", "hatch")))
			add_child(current)
		"hatch":
			var Hx = load("res://scripts/ui/hatch.gd")
			current = Hx.new()
			current.set("edit_only", bool(opts.get("create", false)))
			add_child(current)
		"home":
			var H = load("res://scripts/home/home.gd")
			current = H.new()
			current.set("visit", opts.get("visit", {}))
			current.set("visit_id", String(opts.get("visit_id", "")))
			current.set("spawn", String(opts.get("spawn", "")))
			add_child(current)
		"interior":
			var In = load("res://scripts/home/interior.gd")
			current = In.new()
			current.set("room", String(opts.get("room", "house")))
			current.set("visit", opts.get("visit", {}))
			current.set("visit_id", String(opts.get("visit_id", "")))
			add_child(current)
		"town":
			var Tw = load("res://scripts/social/town.gd")
			current = Tw.new()
			current.set("mode", String(opts.get("mode", "hub")))
			current.set("gid", String(opts.get("gid", "")))
			add_child(current)

## Headless check: a whole match with the player on autopilot, stepped as fast as possible.
## Test: the down / death / revive rules, step by step, with idle hunters placed by hand.
## Headless: drops a hunter (and a wisp) just off island edges, holds toward the cliff, and checks
## every mantle: it happens, it ends on top, and the body never sinks into the cliff on the way.
func _mantle_check() -> void:
	var m := Match.new()
	add_child(m)
	m.start({"teams": 2, "squad": 1, "tier": 0, "length": 1e9, "seed": 77, "no_drop": true, "autoplay": true})
	m.set_process(false)
	for mb in m.mobs: mb.queue_free()
	m.mobs.clear()
	var h: Hunter = m.hunters[0]
	for o in m.hunters:
		o.ctrl = "idle"
		if o != h: o.teleport(m.world.random_ground())
	h.ctrl = "local"      # players mantle on a jump/fall, not by walking into walls
	var w: World = m.world
	var tried := 0; var ok := 0; var clip := 0; var worst := 0.0; var durs: Array = []
	for downed_case in [false, true]:
		for trial in 12:
			# find an edge: a ground tile next to the void
			var at := Vector3.INF; var dir := Vector2.ZERO
			for k in 400:
				var g := w.random_ground()
				for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
					# on an authored map only rims with a lip can be grabbed; sheer ones are checked below
					var rim_ok := w.lip.is_empty() or w.lip.has(w.idx(int(floor(g.x + d.x * 0.9)), int(floor(g.z + d.y * 0.9)))) or w.lip.has(w.idx(int(floor(g.x)), int(floor(g.z))))
					if w.is_void(g.x + d.x * 1.6, g.z + d.y * 1.6) and not w.is_void(g.x, g.z) and k % 12 == trial and rim_ok:
						at = g; dir = d; break
				if at != Vector3.INF: break
			if at == Vector3.INF: continue
			tried += 1
			var top := w.ground_at(at.x, at.z)
			# hanging in the air just off the edge, 3m below the lip, pushing back toward the island
			var edge_x := at.x; var edge_z := at.z
			while not w.is_void(edge_x + dir.x * 0.25, edge_z + dir.y * 0.25):
				edge_x += dir.x * 0.25; edge_z += dir.y * 0.25
			h.downed = downed_case
			h.down_hp = 100.0
			h.teleport(Vector3(edge_x + dir.x * (h.r + 0.6), top - 3.0, edge_z + dir.y * (h.r + 0.6)))
			h.grounded = false; h.vel = Vector3(0, -2.0, 0); h.pad = {}; h.grap_cd = 0.0; h.last_gy = top
			var t := 0.0; var mantled := false; var landed := false; var t_m := 0.0
			while t < 3.0:
				h.inp["move"] = -dir
				m.step(Match.DT); t += Match.DT
				if not h.pad.is_empty() and h.pad.has("face"):
					if not mantled: t_m = t
					mantled = true
					# inside the cliff: standing below solid ground that's under you
					var gh := w.ground_at(h.pos.x, h.pos.z)
					if not w.is_void(h.pos.x, h.pos.z) and gh > h.pos.y + 0.06:
						clip += 1; worst = maxf(worst, gh - h.pos.y)
				if mantled and h.pad.is_empty() and h.grounded:
					landed = absf(h.pos.y - top) < 0.6
					durs.append(snappedf(t - t_m, 0.01))
					break
			if mantled and landed: ok += 1
	print("MCHECK mantles ok %d of %d, clipping frames %d (worst %.2fm), climb times %s" % [ok, tried, clip, worst, str(durs)])
	# sheer cliffs: falling past one while pushing into it must never catch you
	if not w.sheer.is_empty():
		var s_tried := 0; var s_caught := 0
		var sheer_keys: Array = w.sheer.keys()
		for trial in 12:
			var i: int = sheer_keys[(trial * 37) % sheer_keys.size()]
			var gx := float(i % w.w) + 0.5; var gz := float(i / w.w) + 0.5
			var dir := Vector2.ZERO
			for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				if w.is_void(gx + d.x, gz + d.y): dir = d; break
			if dir == Vector2.ZERO: continue
			s_tried += 1
			var top := w.ground_at(gx, gz)
			h.downed = false
			h.teleport(Vector3(gx + dir.x * (0.5 + h.r + 0.6), top - 3.0, gz + dir.y * (0.5 + h.r + 0.6)))
			h.grounded = false; h.vel = Vector3(0, -2.0, 0); h.pad = {}; h.grap_cd = 0.0; h.last_gy = top
			var t := 0.0
			while t < 1.5:
				h.inp["move"] = -dir
				m.step(Match.DT); t += Match.DT
				if not h.pad.is_empty() and h.pad.has("face"):
					# caught: fine only if it was a neighbouring lip tile, not the sheer one
					var lx := int(floor((h.pad["to"] as Vector3).x)); var lz := int(floor((h.pad["to"] as Vector3).z))
					if w.sheer.has(w.idx(lx, lz)) or Vector2(lx + 0.5 - gx, lz + 0.5 - gz).length() < 1.2: s_caught += 1
					break
		print("MCHECK sheer cliffs caught %d of %d (should be 0)" % [s_caught, s_tried])
	get_tree().quit()

func _life_check() -> void:
	var m := Match.new()
	add_child(m)
	m.start({"teams": 2, "squad": 3, "tier": 0, "length": 1e9, "seed": 77, "no_drop": true, "autoplay": true})
	m.set_process(false)
	var mine: Array = m.hunters.filter(func(x): return x.team == 0)
	var foe: Hunter = m.hunters.filter(func(x): return x.team != 0)[0]
	for h in m.hunters:
		h.ctrl = "idle"
		h.inp["move"] = Vector2.ZERO
	for mb in m.mobs: mb.queue_free()
	m.mobs.clear()
	var A: Hunter = mine[0]; var B: Hunter = mine[1]; var C: Hunter = mine[2]
	var home: Vector3 = A.pos
	# the test steps up to 8m in every direction, so start from open ground (spawns can be small landings)
	for k in 2000:
		var g := m.world.random_ground()
		var roomy := true
		for dx in range(-10, 11, 2):
			for dz in range(-6, 7, 2):
				if m.world.is_void(g.x + dx, g.z + dz) or absf(m.world.ground_at(g.x + dx, g.z + dz) - m.world.ground_at(g.x, g.z)) > 0.3: roomy = false
		if roomy:
			home = g; break
	var far := home + Vector3(0, 0, 0)
	var spot := func(h: Hunter, at: Vector3): h.teleport(at); h.vel = Vector3.ZERO
	var run := func(sec: float):
		var t := 0.0
		while t < sec:
			m.step(Match.DT); t += Match.DT
	# park everyone else far apart
	for h in m.hunters:
		if h.team != 0 and h != foe: spot.call(h, m.world.random_ground())
	var away := m.world.random_ground()
	for k in 200:
		if away.distance_to(home) > 40.0: break
		away = m.world.random_ground()
	spot.call(foe, away)
	# 1. ally revive
	spot.call(B, home + Vector3(2, 0, 0)); spot.call(C, home + Vector3(2, 0, 0.5)); spot.call(A, home)
	m.knock(B, foe, {})
	var t0 := m.time
	while B.downed and m.time - t0 < 10.0: run.call(Match.DT)
	print("LCHECK ally revive: back=%s after %.1fs hp %.0f%%" % [not B.downed, m.time - t0, B.hp / B.max_hp * 100.0])
	# 2. bleed out alone (with the kin knocked out, so it can't pull them up)
	for kk in [B.kin, B.kin2]:
		if kk: kk.dead = true
	spot.call(C, home + Vector3(-8, 0, 0)); spot.call(A, home + Vector3(-8, 0, 1))
	B.gems = 20
	m.knock(B, foe, {})
	t0 = m.time
	print("LCHECK  knocked: downed=%s hp=%s" % [B.downed, B.down_hp])
	while not B.out and m.time - t0 < 30.0:
		run.call(Match.DT)
		if int((m.time - t0) * 60.0) % 120 == 0: print("LCHECK   t=%.1f downed=%s down_hp=%.1f revive=%.2f out=%s" % [m.time - t0, B.downed, B.down_hp, B.revive, B.out])
	var bx := Life.box_of(m, B)
	print("LCHECK bleed: dead=%s after %.1fs box=%s gems in box=%d" % [B.out, m.time - t0, not bx.is_empty(), int(bx.get("gems", -1))])
	# 3. box revive
	spot.call(C, bx["pos"]); C.inp["interact"] = true
	t0 = m.time
	while B.out and m.time - t0 < 10.0: run.call(Match.DT)
	C.inp["interact"] = false
	print("LCHECK box revive: back=%s after %.1fs hp %.0f%% gems %d" % [not B.out, m.time - t0, B.hp / B.max_hp * 100.0, B.gems])
	# 4. stomp drain
	for kk in [B.kin, B.kin2]:
		if kk: kk.dead = true
	spot.call(C, home + Vector3(-8, 0, 0))
	spot.call(foe, B.pos)
	m.knock(B, foe, {})
	t0 = m.time
	run.call(Match.DT); run.call(Match.DT)
	var pinned: bool = B.get_meta("stomped", false)
	var stood: bool = foe.get_meta("standing_on", null) == B
	while not B.out and m.time - t0 < 30.0: run.call(Match.DT)
	print("LCHECK stomp: dead=%s after %.1fs (expect ~%.1fs at %.1fx) pinned=%s stomper flagged=%s slow=%.2f" % [B.out, m.time - t0, Life.R["bleed_out"] / Life.R["stomp_mult"], Life.R["stomp_mult"], pinned, stood, Life.R["stomp_slow"]])
	spot.call(foe, m.world.random_ground())
	# 5. beacon
	var bc: Dictionary = m.beacons[0]
	spot.call(C, bc["pos"])
	t0 = m.time
	while B.out and m.time - t0 < 12.0: run.call(Match.DT)
	print("LCHECK beacon: back=%s after %.1fs hp %.0f%% sick %.1fs used=%s" % [not B.out, m.time - t0, B.hp / B.max_hp * 100.0, B.sick_t, bc["used"]])
	# 6. execute
	for kk in [B.kin, B.kin2]:
		if kk: kk.dead = true
	spot.call(C, home + Vector3(-8, 0, 0)); spot.call(B, home + Vector3(6, 0, 0))
	m.knock(B, foe, {})
	spot.call(foe, B.pos + Vector3(0.5, 0, 0)); foe.inp["interact"] = true
	t0 = m.time
	while not B.out and m.time - t0 < 10.0:
		foe.inp["interact"] = true
		run.call(Match.DT)
	print("LCHECK execute: dead=%s after %.1fs (stomp drains too)" % [B.out, m.time - t0])
	# 6b. a committed stomp can't be cancelled by its owner, but a knockback breaks it
	var W2: Hunter = C
	for kk in [W2.kin, W2.kin2]:
		if kk: kk.dead = true
	spot.call(W2, home + Vector3(2, 0, 3))
	m.knock(W2, foe, {})
	spot.call(foe, W2.pos + Vector3(0.5, 0, 0))
	t0 = m.time
	while foe.stomp.is_empty() and m.time - t0 < 2.0:
		foe.inp["interact"] = true
		run.call(Match.DT)
	var committed := not foe.stomp.is_empty()
	for i in 30:
		foe.inp["interact"] = false      # letting go does nothing once committed
		foe.inp["move"] = Vector2(1, 0)
		run.call(Match.DT)
	var still := not foe.stomp.is_empty()
	foe.kb_t = m.time
	run.call(Match.DT)
	print("LCHECK stomp lock: committed=%s still after letting go=%s broken by knock=%s wisp alive=%s" % [committed, still, foe.stomp.is_empty(), not W2.out])
	print("LCHECK beacons=%d boxes=%d" % [m.beacons.size(), m.boxes.size()])
	# 7. Dusk Isles rules: the kin on you go into the box; an enemy looting it takes them
	m.T = Data.TIERS[1]
	var rec := Save.new_kin("zapple")
	A.kin = null; A.kin2 = null
	m.give_kin(A, rec)
	spot.call(A, home); spot.call(B, home + Vector3(-8, 0, 0)); spot.call(C, home + Vector3(-8, 0, 1))
	m.eliminate(A, foe, "knocked out")
	var ab := Life.box_of(m, A)
	print("LCHECK dusk: kin in box=%d" % (ab.get("kin", []) as Array).size())
	spot.call(foe, ab["pos"])
	t0 = m.time
	while not ab["empty"] and m.time - t0 < 4.0:
		foe.inp["interact"] = true
		run.call(Match.DT)
	print("LCHECK dusk loot: foe caught=%d box kin=%d" % [foe.caught.size(), (ab.get("kin", []) as Array).size()])
	# 8. Meadow: kin stay safe (hidden) on death and come back on revive
	m.T = Data.TIERS[0]
	spot.call(foe, m.world.random_ground())
	var B2: Hunter = B
	B2.kin = null; B2.kin2 = null
	m.give_kin(B2, Save.new_kin("zapple"))
	spot.call(B2, home + Vector3(-6, 0, 0))
	m.eliminate(B2, foe, "knocked out")
	print("LCHECK meadow: kin state=%s box kin=%d" % [B2.kin.state, (Life.box_of(m, B2).get("kin", []) as Array).size()])
	# 9. the deathbox loot window: a box with a rare glove and some gems; take one by hand, smart loot the rest
	var lb: Dictionary = {}
	for b0 in m.boxes:
		if not b0.get("empty", true):
			lb = b0
	if not lb.is_empty():
		var gid: String = String(Gear.ALL.keys()[0]) if not Gear.ALL.is_empty() else ""
		if gid != "": (lb["gear"] as Array).append({"id": gid, "rar": 3})
		lb["gems"] = int(lb.get("gems", 0)) + 15
		var looter: Hunter = C
		looter.gear = [{}, {}]; looter.refresh_gear()
		var its: Array = Life.box_items(m, looter, lb)
		var g0 := looter.gems
		var first: Dictionary = its[0]
		Life.take_item(m, looter, lb, first)
		var got := Life.smart_loot(m, looter, lb)
		print("LCHECK loot window: items=%d took first=%s smart=%d gems +%d gear=%s left=%d empty=%s" % [its.size(), first["name"], got, looter.gems - g0, str(looter.gear), Life.box_items(m, looter, lb).size(), lb["empty"]])
	get_tree().quit()

## Test: every weapon against a standing target at a couple of ranges, tapping and (for swords)
## charging, and prints the damage per second it actually lands.
func _weapon_check() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--weapon-check="): only = a.substr(15)
	for wid in Data.weapon_ids():
		if only != "" and wid != only:
			continue
		var cls := ""
		for c in Data.CLASSES:
			if Data.CLASSES[c]["weapons"].has(wid): cls = c
		if cls == "":
			continue
		var wd: Dictionary = Data.weapon_stats(wid)
		var modes: Array = ["tap", "charge"] if wd.has("charge_time") else ["hold"]
		for mode in modes:
			for dist in ([1.6] if wd.get("melee", false) else ([1.5, 3.0] if wd.has("pellets") else [3.0, float(wd["range"]) * 0.8])):
				var m := Match.new()
				add_child(m)
				m.start({"training": true, "teams": 1, "squad": 1, "tier": 0, "length": 1e9, "seed": 4242, "no_drop": true, "weapon": wid, "cls": cls})
				m.set_process(false)
				var P: Hunter = m.player
				var T: Hunter = null
				var home := Vector3.ZERO
				# find flat open ground for both
				for tries in 400:
					# the training island first; long sightlines may need the open ground elsewhere
					var at: Vector3 = m.world.random_ground(m.world.island_of(P.pos.x, P.pos.z)) if tries < 200 else m.world.random_ground()
					var to := at + Vector3(dist, 0, 0)
					var ok := true
					for k in 9:
						var q := at.lerp(to, k / 8.0)
						if m.world.is_block(q.x, q.z) or absf(m.world.ground_at(q.x, q.z) - at.y) > 0.01: ok = false
					if ok:
						home = at
						P.teleport(at)
						T = m.make_hunter("T", 5, "medium", "Target", "idle", {}, to)
						break
				if T == null:
					print("WCHECK %s: no spot" % wid); m.queue_free(); continue
				T.max_hp = 100000.0; T.hp = T.max_hp; T.armor = 0.0; T.max_armor = 0.0
				for mb in m.mobs: mb.queue_free()
				m.mobs.clear()
				var t := 0.0
				var dur := 6.0
				while t < dur:
					T.teleport(P.pos + Vector3(dist, 0, 0)); T.vel = Vector3.ZERO
					P.inp["aim"] = T.pos + Vector3(0, 0.9, 0); P.inp["aim_y"] = T.pos.y
					if mode == "tap": P.inp["fire"] = int(t / 0.05) % 2 == 0
					elif mode == "charge":
						# hold until the charge is full, then let go for a moment
						if P.inp["fire"] and P.charge_k() >= 1.0: P.inp["fire"] = false; P.set_meta("rel", 0.5)
						elif not P.inp["fire"]:
							P.set_meta("rel", float(P.get_meta("rel", 0.0)) - Match.DT)
							if float(P.get_meta("rel", 0.0)) <= 0.0:
								P.inp["fire"] = true
								P.teleport(home); P.vel = Vector3.ZERO     # lunges carry you off the test strip
					else: P.inp["fire"] = true
					m.mobs.clear()
					m.step(Match.DT)
					t += Match.DT
				var dealt := T.max_hp - T.hp
				print("WCHECK %-12s %-6s dist %4.1f  dps %6.1f  (%d in %ds)" % [wid, mode, dist, dealt / dur, int(dealt), int(dur)])
				m.queue_free()
				await get_tree().process_frame
	get_tree().quit()

## Headless check for basing to a teammate (B): a clean channel arrives weakened; a hit interrupts.
func _base_check() -> void:
	var m := Match.new()
	add_child(m)
	m.start({"teams": 2, "squad": 2, "tier": 0, "no_drop": true, "seed": 77, "autoplay": true, "big": false})
	m.set_process(false)
	var p: Hunter = m.player
	p.ctrl = "local"
	var mate := m.base_target(p)
	if mate == null:
		print("BCHECK FAIL no teammate"); get_tree().quit(); return
	for i in 30: m.step(Match.DT)
	p.inp["move"] = Vector2.ZERO
	p.start_base(mate)
	var t := 0.0
	while t < 3.3:
		p.inp["move"] = Vector2.ZERO
		m.step(Match.DT); t += Match.DT
	var near := p.flat_dist(mate) < 2.5
	print("BCHECK clean: arrived=%s weak=%.1f cd=%.0f dmg_mult=%.2f" % [near, p.weak_t, p.base_cd, m.dmg_mult(p)])
	p.base_cd = 0.0
	p.start_base(mate)
	for i in 30: m.step(Match.DT)
	p.hurt(5.0, null, {"src": "test"})
	print("BCHECK interrupt: channel=%.2f cancelled=%s" % [p.base_t, p.base_t <= 0.0])
	print("BCHECK ", "PASS" if near and p.base_t <= 0.0 else "FAIL")
	get_tree().quit()

## Headless smoke test for the duel room: your autopilot against the sparring bot for a few
## minutes, changing the bot's class, behaviour, glove and difficulty along the way.
func _duel_check() -> void:
	var o := Match.duel_opts()
	o["autoplay"] = true
	var m := Match.new()
	add_child(m)
	m.start(o)
	m.set_process(false)
	var ok := true
	if m.duel == null or m.duel.bot == null:
		print("DUEL FAIL no bot"); get_tree().quit(); return
	print("DUEL START player=%s bot=%s dist=%.1f" % [m.player.pos.snapped(Vector3(0.1, 0.1, 0.1)), m.duel.bot.pos.snapped(Vector3(0.1, 0.1, 0.1)), m.player.flat_dist(m.duel.bot)])
	var plan := {20.0: ["mode", 1], 40.0: ["mode", 1], 60.0: ["mode", 1], 80.0: ["cls", 1], 100.0: ["glove", 1], 120.0: ["diff", 1], 140.0: ["weapon", 1]}
	var done := {}
	while m.time < 170.0:
		m.step(Match.DT)
		for t in plan:
			if m.time >= float(t) and not done.has(t):
				done[t] = true
				m.duel.cycle(String(plan[t][0]), int(plan[t][1]))
				print("DUEL t=%d %s -> %s / %s / %s / %s / %s" % [m.time, plan[t][0], m.duel.pick_text("cls"), m.duel.pick_text("weapon"), m.duel.pick_text("glove"), m.duel.pick_text("diff"), m.duel.pick_text("mode")])
		if m.duel.bot == null or not is_instance_valid(m.duel.bot):
			print("DUEL FAIL bot lost at ", m.time); ok = false; break
		if m.over:
			print("DUEL FAIL match ended at ", m.time); ok = false; break
	var st: Dictionary = m.duel.stats
	print("DUEL STATS ", st, " rounds=", m.duel.round_n, " bots=", m.hunters.size())
	if int(st["shots"]) <= 0 or float(st["dealt"]) <= 0.0:
		print("DUEL FAIL nothing landed"); ok = false
	print("DUEL CHECK ", "PASS" if ok else "FAIL")
	get_tree().quit()

func _simtest(opts: Dictionary) -> void:
	opts["autoplay"] = true
	var m := Match.new()
	add_child(m)
	m.start(opts)
	m.set_process(false)
	var t0 := Time.get_ticks_msec()
	var log_t := 0.0
	var kill_at := -1.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--kill-at="): kill_at = float(a.substr(10))
	while not m.over and m.time < m.length + 5.0:
		m.step(Match.DT)
		if kill_at > 0.0 and m.time >= kill_at and m.player and not m.player.out:
			# test: the player goes down for good here, to check what happens to the kin they brought
			var near: Hunter = null
			for o in m.hunters:
				if o != m.player and not o.out and (near == null or o.flat_dist(m.player) < near.flat_dist(m.player)): near = o
			m.player.lives = 1
			m.eliminate(m.player, near, "knocked out", true)
			kill_at = -1.0
		if m.result.get("ending", false) and m.time > 0.0:
			m._finish_now = true
		log_t += Match.DT
		if log_t >= 30.0:
			log_t = 0.0
			var alive := m.hunters.filter(func(x): return not x.out and not x.extracted).size()
			var down := m.hunters.filter(func(x): return x.downed).size()
			var P: Hunter = m.player
			print("  island=", m.world.island_of(P.pos.x, P.pos.z), " pads=", m.world.pads.map(func(pd): return "%d>%d@(%d,%d)" % [pd["from"], pd["to"], pd["pos"].x, pd["pos"].z]))
			var TG = P.ai.get("tgt")
			if TG: print("  DBG tgt=%s pos=%s hp=%s dead=%s drop=%s vel=%s grap=%s ride=%s cross=%s blockhere=%s ground=%s" % [TG.get_class() + ":" + str(TG.get_script().resource_path.get_file()), TG.pos.snapped(Vector3(0.1,0.1,0.1)), TG.hp, TG.dead, P.dropping, P.vel.snapped(Vector3(0.1,0.1,0.1)), P.grap.size(), P.riding, P.ai.has("cross"), m.world.is_block(P.pos.x, P.pos.z), m.world.ground_at(P.pos.x, P.pos.z)])
			print("  player pos=%s goal=%s kind=%s tgt=%s move=%s grounded=%s" % [P.pos.snapped(Vector3(0.1,0.1,0.1)), str(P.ai.get("goal")), P.ai.get("goal_kind"), str(P.ai.get("tgt")), str(P.inp["move"]), P.grounded])
			print("t=%d alive=%d down=%d mobs=%d shots=%d pickups=%d feed=%s" % [m.time, alive, down, m.mobs.filter(func(x): return not x.dead).size(), m.shots.size(), m.pickups.size(), str(m.feed.map(func(f): return f["text"]))])
		if m.result.get("ending", false):
			break
	for line in m.feed_all:
		print("   | ", line)
	# per-weapon totals, to spot a weapon that never lands or lands far too much
	var wsum := {}
	for h in m.hunters:
		var e: Array = wsum.get(h.wid, [0, 0.0, 0])
		e[0] += 1; e[1] += h.dmg_done; e[2] += h.knocks
		wsum[h.wid] = e
	for k in wsum:
		print("WPN %s n=%d dmg=%d knocks=%d" % [k, wsum[k][0], int(wsum[k][1]), wsum[k][2]])
	if m.player:
		var isl := m.world.island_of(m.player.pos.x, m.player.pos.z)
		print("player island ", isl, " pads out: ", m.world.pads.filter(func(pd): return pd["from"] == isl).map(func(pd): return [pd["pos"], pd["to"], pd["land"]]))
	var nb := 0
	for b in m.breaks: nb += int(b["dead"])
	var wr: Array = []
	for h in m.hunters: wr.append(h.wrar)
	print("SIMSTAT breaks %d/%d weapons left %d rarities %s staggers %d rings %d pads %d" % [nb, m.breaks.size(), m.wpicks.size(), str(wr), m.stag_n, m.ring_n, m.world.pads.size()])
	print("SIMTEST done in %dms, sim time %d, result %s" % [Time.get_ticks_msec() - t0, m.time, str(m.result)])
	print("SIMKIN %s lost=%s" % [str(m.kstat), str(m._resolve_lost().map(func(L): return [L["fate"], L["holder"]]))])
	for h in m.hunters:
		print("  %s team %d %s knocks %d kills %d dmg %d gems %d %s" % [h.pname, h.team, h.cls, h.knocks, h.kills, h.dmg_done, h.gems, "OUT" if h.out else ("EXTRACTED" if h.extracted else "alive")])
	get_tree().quit()

# ------------------------------------------------------------------ browser test hooks
var _cmd_cb = null

## window.kinGameCmd("ready" | "start" | "state" | "move:x,z" | "fire:x,z" | "god") for automated browser tests.
## Results land in window.kinGameOut as JSON.
var _soc_test := false      # the shared-feature test hooks only answer on a #soctest page

func _expose_test_hooks() -> void:
	_cmd_cb = JavaScriptBridge.create_callback(func(a): _cmd(str(a[0])))
	JavaScriptBridge.get_interface("window").kinGameCmd = _cmd_cb

func _cmd(c: String) -> void:
	var out := {}
	var current = screen_node()
	if (c.begins_with("goto:") or c.begins_with("soc:")) and _soc_test:
		_social_cmd(c, current)
		return
	if current and current.has_method("_toggle_ready") and c == "ready":
		current._toggle_ready()
	elif current and current.has_method("_start") and c == "start":
		current._start()
	elif current is Match:
		var m: Match = current
		if c == "state":
			out = {"time": m.time, "mid": m.get_instance_id(), "host": m.is_host, "me": Net.me, "hunters": m.hunters.map(func(h): return [h.nid, h.pname, h.team, snappedf(h.hp, 0.1), h.remote, h.downed, h.out, h.pos.snapped(Vector3(0.1, 0.1, 0.1)), h.dropping, h.cls]),
				"mobs": m.mobs.filter(func(x): return not x.dead).size(), "kills": m.player.kills if m.player else 0, "knocks": m.player.knocks if m.player else 0,
				"feed": m.feed.map(func(f): return f["text"]), "pickups": m.pickups.size(), "gems": m.player.gems if m.player else 0}
		elif c.begins_with("tp:") and m.player:
			var nid := c.substr(3)
			var t: Ent = m.ents_by_id.get(nid, null)
			if t:
				# stand a few tiles away on solid ground at the same height
				for off in [Vector3(2.5, 0, 0), Vector3(-2.5, 0, 0), Vector3(0, 0, 2.5), Vector3(0, 0, -2.5), Vector3(1.8, 0, 1.8), Vector3(-1.8, 0, -1.8)]:
					var q: Vector3 = t.pos + off
					if absf(m.world.ground_at(q.x, q.z) - t.pos.y) < 0.1 and not m.world.is_block(q.x, q.z):
						m.player.teleport(q)
						break
		elif c.begins_with("shoot:") and m.player:
			var t: Ent = m.ents_by_id.get(c.substr(6), null)
			if t:
				m.player.inp["aim"] = t.pos + Vector3(0, 0.9, 0)
				m.player.fire_cd = 0.0
				m.player.fire()
		elif c == "god" and m.player:
			m.player.max_hp = 9999; m.player.hp = 9999
	elif current and current.has_method("_open_chat"):
		if c.begins_with("chat:"):
			var rec: Dictionary = Save.active_kin()
			current._open_chat(rec)
			current.chat_input.text = c.substr(5)
			current._send_chat()
		elif c == "chatlog":
			out = {"log": current.chat_log.slice(1), "lines": Save.active_kin().get("lines", {}), "ai_ok": Bridge.ai_ok}
	elif current and current.has_method("show_result"):
		out = {"screen": "results"}
	JavaScriptBridge.eval("window.kinGameOut = " + JSON.stringify(out) + ";", true)

## Test hooks for the shared features. Answers land in window.kinSocOut (they're mostly async).
func _soc_reply(v) -> void:
	JavaScriptBridge.eval("window.kinSocOut = " + JSON.stringify(v) + ";", true)

func _social_cmd(c: String, current) -> void:
	var p := c.split(":")
	match p[0] + ":" + p[1]:
		"goto:town": Game.goto("town", {"mode": p[2], "gid": p[3] if p.size() > 3 else ""})
		"goto:home": Game.goto("home")
		"goto:visit":
			Social.get_doc("profiles/" + p[2], func(d: Dictionary): Game.goto("home", {"visit": Social.clean_island(d), "visit_id": p[2]}))
		"soc:state":
			var st := {"me": Social.me, "mode": Social.mode, "ok": Social.ok, "guild": Social.guild, "progress": Social.guild_progress,
				"perks": Save.d.get("guild_perks", []), "gems": Save.d["gems"], "seeds": Save.d["seeds"], "crops": Save.d["crops"],
				"listings": Save.d.get("listings", {}), "screen": str(current.get_script().resource_path) if current and current.get_script() else ""}
			if current and "others" in current: st["others"] = (current.others as Dictionary).size()
			if current and "members" in current: st["members"] = (current.members as Array).size()
			if current and "project_nodes" in current: st["projects"] = (current.project_nodes as Dictionary).keys()
			if current and "visit" in current: st["visiting"] = String((current.visit as Dictionary).get("name", ""))
			_soc_reply(st)
		"soc:name": Save.d["name"] = p[2]; _soc_reply(true)
		"soc:give":
			Save.d["gems"] = int(Save.d["gems"]) + int(p[2])
			if p.size() > 3: Save.add_seed(p[3], 3)
			_soc_reply(true)
		"soc:publish": Social.publish_profile(true); _soc_reply(true)
		"soc:create": Social.create_guild(p[2], "We test things", func(okk): _soc_reply(okk))
		"soc:join": Social.join_guild(p[2], func(okk): _soc_reply(okk))
		"soc:leave": Social.leave_guild(func(): _soc_reply(true))
		"soc:guilds": Social.list_guilds(func(rows): _soc_reply(rows))
		"soc:contrib": Social.contribute(p[2], int(p[3]), func(okk): _soc_reply(okk))
		"soc:sell": Social.sell(p[2], p[3], int(p[4]), func(okk): _soc_reply(okk))
		"soc:market": Social.list_market(func(rows): _soc_reply(rows))
		"soc:buy": Social.buy(p[2], func(what): _soc_reply(what))
		"soc:unlist": Social.unlist(p[2], func(okk): _soc_reply(okk))
		"soc:notice": Social.post_notice(p[2], func(okk): _soc_reply(okk))
		"soc:notices": Social.list_notices(func(rows): _soc_reply(rows))
		"soc:gift": Social.send_gift(p[2], p[3], p[4], func(okk): _soc_reply(okk))
		"soc:collect":
			Social.collect_gifts(func(lines):
				Social.collect_payouts(func(total): _soc_reply({"lines": lines, "paid": total})))
		"soc:islands": Social.list_islands(func(rows): _soc_reply(rows.map(func(r): return r["id"])))
		"soc:refresh": Social.refresh_guild(func(): _soc_reply(Social.guild))
		"soc:open":
			if current and current.has_method("_use"):
				current._use({"kind": p[2], "data": p[3] if p.size() > 3 else null, "label": ""})
			_soc_reply(true)
		"soc:walk":
			if current and "ppos" in current:
				current.ppos = Vector3(float(p[2]), 0, float(p[3]))
			_soc_reply(true)
