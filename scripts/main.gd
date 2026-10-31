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
		if a == "--pack-demo": opts["pack_demo"] = true; opts["no_drop"] = true
		if a == "--bag-demo": opts["bag_demo"] = true; opts["no_drop"] = true
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
		if a.begins_with("--exit-demo="): opts["exit_demo"] = a.substr(12); opts["no_drop"] = true
		if a == "--truce-demo": opts["truce_demo"] = true; opts["no_drop"] = true
		if a == "--no-plan": opts["no_plan"] = true
		if a.begins_with("--plan-t="): opts["plan_t"] = float(a.substr(9))
		if a == "--map-demo": opts["map_demo"] = "plan"          # the planning map, with pings
		if a == "--map-mid-demo": opts["map_demo"] = "mid"; opts["no_drop"] = true    # the map mid-match, some spawns scouted
		if a == "--drop-demo": opts["drop_demo"] = true; opts["plan_t"] = 0.6          # the squad gliding in formation
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
	if "--pack-gallery" in args:
		add_child(load("res://tests/pack_gallery.gd").new())
		return
	if Array(args).any(func(a): return String(a).begins_with("--art-view=")):
		add_child(load("res://tests/art_view.gd").new())
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
	if "--economy-check" in args:
		_economy_check()
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
	if "--ability-check" in args:
		_ability_check()
		return
	if "--simtest" in args:
		_simtest(opts)
		return
	if "--extract-check" in args:
		_extract_check()
		return
	if "--truce-check" in args:
		_truce_check()
		return
	if "--drop-check" in args:
		_drop_check()
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
			if a.begins_with("--weapon="): so["weapon"] = a.substr(9)
			if a.begins_with("--aim-demo="): so["aim_demo"] = a.substr(11); so["sandbox_demo"] = false
			if a.begins_with("--glove="): so["glove"] = a.substr(8)
			if a.begins_with("--class="): so["cls"] = a.substr(8)
			if a.begins_with("--kin-demo="):
				# test: bring this species (and the next one) and run its whole kit on the dummies
				so["demo_kin"] = a.substr(11)
				so["sandbox_demo"] = false
				so["kin_demo"] = true
		show_screen("match", so)
		return
	if "--results-test" in args:
		show_screen("results", {"extracted": true, "gems": 42, "seeds": {"sunroot": 1}, "caught": [Save.new_kin("zapple")], "knocks": 3, "damage": 512, "taken": 388, "kills": 1, "downs": 1, "deaths": 0, "revives": 2, "armor_tier": 3, "time": 201.0, "kin_events": [{"kind": "refused", "text": "refused to jump into a fight that looked too dangerous", "trust": -1.0}], "kin_trust": 57.0, "tonics": 1})
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
	if "--crowd-test" in args and Save.d["roster"].size() < 6:
		# test: a crowd of kin, to check they keep apart and take turns talking
		for sp in ["zapple", "cindle", "puddlet", "zapple", "cindle", "puddlet"]:
			var ck := Save.new_kin(sp)
			ck["trust"] = 75.0
			Save.d["roster"].append(ck)
		Save.d["active"] = Save.d["roster"][0]["uid"]
		Save.d["tutorial"]["home"] = true
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

## Headless check for loot and kin keeping: a full backpack asks to swap, smart loot takes the best
## first, extracting fills the armory, feeders feed hungry kin (also while you're away), starving
## runs its course to a grave, and the Soul Shrine brings a kin back changed. Never touches the save.
func _economy_check() -> void:
	Save.no_write = true
	Save.d = Save.fresh()
	Econ.ensure()
	var bad := [0]
	var ok := func(cond: bool, what: String) -> void:
		print("ECON %s %s" % ["ok  " if cond else "FAIL", what])
		if not cond: bad[0] += 1
	var m := Match.new()
	add_child(m)
	m.start({"teams": 2, "squad": 1, "tier": 0, "length": 1e9, "seed": 21, "no_drop": true})
	m.set_process(false)
	var P: Hunter = m.player
	var Q: Hunter = m.hunters.filter(func(x): return x != P)[0]
	var at := P.pos + Vector3(0.6, 0, 0)
	# 1. a full backpack asks what to drop
	P.pack_cap = 2
	P.pack = [Loot.valuable("old_coin"), Loot.weapon("smg", 1)]
	m.spawn_val(Loot.valuable("kin_idol"), at)
	var wp: Dictionary = m.wpicks[m.wpicks.size() - 1]
	Pack.take_ground(m, P, wp)
	ok.call(m.hud.swap_open() and P.pack.size() == 2 and m.wpicks.has(wp), "full backpack opens the swap window (pack %d/%d)" % [P.pack.size(), P.pack_cap])
	Pack.swap(m, P, 0, wp)      # you pick the coin to leave behind
	var ids: Array = P.pack.map(func(it): return String(it.get("id", it.get("wid", ""))))
	ok.call(ids.has("kin_idol") and not ids.has("old_coin") and m.wpicks.any(func(w): return String(w.get("val", "")) == "old_coin"), "swap drops the coin on the ground and packs the idol: %s" % str(ids))
	m.hud.close_swap()
	# a better weapon on the ground goes in your hands, with its element
	P.pack_cap = 4
	m.spawn_weapon("rifle", 3, at, "", false, -1, Loot.weapon("rifle", 3, "fire"))
	Pack.take_ground(m, P, m.wpicks[m.wpicks.size() - 1])
	ok.call(P.welem == "fire" and P.wrar == 3 and String(P.wpn["name"]) == "Epic Ember Rifle", "better weapon equipped: %s" % P.wpn["name"])
	var ex := {}
	Loot.rider(P, ex, 10.0)
	ok.call(float(ex.get("burn", 0.0)) >= 5.0, "fire rider burns (%s)" % str(ex))
	P.welem = "storm"; P.el_n = 3
	var ex2 := {}
	Loot.rider(P, ex2, 10.0)
	ok.call(ex2.has("fx_hit"), "storm rider arcs on the 4th attack")
	P.welem = "fire"
	# 2. smart loot: hands first, then the pack, best first, never worse for better
	var gid: String = Gear.ALL.keys()[0]
	var b := {"owner": Q, "team": Q.team, "pos": P.pos, "gems": 10, "seeds": {"tidebloom": 2}, "caught": [], "tonics": 0, "kits": 0, "soul_until": 0.0,
		"prog": {}, "node": null, "empty": false, "gear": [{"id": gid, "rar": 4}], "weapon": Loot.weapon("sniper", 4, "frost"),
		"pack": [Loot.valuable("old_coin"), Loot.valuable("crown_shard"), Loot.weapon("smg", 1), Loot.weapon("shotgun", 2, "venom"), Loot.valuable("sky_pearl")]}
	P.pack = [Loot.valuable("kin_idol")]
	P.pack_cap = 3
	P.gear = [{}, {}]; P.refresh_gear()
	var g0 := P.gems
	var got := Life.smart_loot(m, P, b)
	var pv: Array = P.pack.map(func(it): return Loot.value(it))
	var left: Array = Pack._box_things(b).map(func(c): return Loot.value(c["it"]))
	var minp: int = pv.min() if not pv.is_empty() else 0
	var maxl: int = left.max() if not left.is_empty() else 0
	print("ECON  smart loot took %d: hand=%s gloves=%s pack=%s values=%s left in box=%s" % [got, P.wpn["name"], str(P.gear), str(P.pack.map(func(it): return Loot.name_of(it))), str(pv), str(left)])
	ok.call(P.wid == "sniper" and P.welem == "frost", "smart loot: the best weapon goes in your hands")
	ok.call(not (P.gear[Gear.slot_of(gid)] as Dictionary).is_empty(), "smart loot: the glove goes on")
	ok.call(P.pack.size() == 3 and minp >= maxl, "smart loot: pack holds the most valuable (min %d >= best left %d)" % [minp, maxl])
	ok.call(P.gems == g0 + 10 and int(P.seeds.get("tidebloom", 0)) >= 2, "smart loot: gems and seeds taken too")
	# 3. extracting brings it all home to the armory; the loadout goes out and comes back
	Save.d["roster"] = [Save.new_kin("cindle", "Pip")]
	Save.d["active"] = Save.d["roster"][0]["uid"]
	var haul := Pack.haul(P)
	var n_arm := haul.filter(func(it): return String(it["t"]) != "val").size()
	var out := Game.apply_result({"extracted": true, "haul": haul, "tier": 0, "gems": 5, "kin_runs": []})
	ok.call(Econ.armory().size() == n_arm and int(Save.d["valuables"].get("crown_shard", 0)) == 1, "extract: %d weapons/gloves in the armory, treasure in the vault %s" % [Econ.armory().size(), str(Save.d["valuables"])])
	ok.call((out.get("haul", []) as Array).size() == haul.size(), "results list what came home (%d)" % (out.get("haul", []) as Array).size())
	var best_w: Dictionary = Econ.armory().filter(func(it): return String(it["t"]) == "weapon")[0]
	Econ.set_loadout("weapon", String(best_w["uid"]))
	var kit := Econ.begin_raid()
	ok.call(kit.size() == 1 and Econ.find(String(best_w["uid"])).is_empty() and (Save.d["raid_out"] as Array).size() == 1, "loadout leaves the armory for the expedition")
	Game.apply_result({"extracted": true, "haul": kit, "tier": 0, "kin_runs": []})
	ok.call(not Econ.find(String(best_w["uid"])).is_empty() and not Econ.loadout("weapon").is_empty(), "extracting brings the loadout weapon back, still picked")
	Econ.begin_raid()
	Game.apply_result({"extracted": false, "why": "knocked out", "lost_items": [best_w], "tier": 0, "kin_runs": []})
	ok.call(Econ.find(String(best_w["uid"])).is_empty() and Econ.loadout("weapon").is_empty(), "dying loses the loadout weapon")
	var sold := Econ.sell(String(Econ.armory()[0]["uid"]))
	var scrap := Econ.salvage(String(Econ.armory()[0]["uid"]))
	ok.call(sold > 0 and scrap > 0, "sell (%d gems) and salvage (%d scrap)" % [sold, scrap])
	m.queue_free()
	# 4. feeders: a hungry kin eats, and a filled feeder keeps kin fed while you're away
	var rec: Dictionary = Save.d["roster"][0]
	Care.ensure(rec)
	rec["likes"]["hates"] = "puffcorn"
	rec["needs"]["food"] = 20.0
	var f: Dictionary = Econ.feeders()[0]
	f["food"] = ["kibble", "kibble", "kibble"]
	var res := Econ.serve(f, rec)
	ok.call(not res.is_empty() and Care.need(rec, "food") > 45.0 and Econ.fill(f) == 2, "feeder feeds a hungry kin: food %d, %d meals left" % [int(Care.need(rec, "food")), Econ.fill(f)])
	var now := Time.get_unix_time_from_system()
	f["kind"] = "hopper"; f["food"] = []; f["auto"] = true
	Save.d["items"]["kibble"] = 14
	rec["needs"]["food"] = 70.0; rec["needs_t"] = now - 3.0 * 86400.0; rec.erase("starve")
	var ev := Econ.catch_up_all()
	ok.call(ev.is_empty() and Care.starve_h(rec) == 0.0 and Care.need(rec, "food") > 0.0, "3 days away with an auto hopper and kibble: fed (food %d, %d kibble left)" % [int(Care.need(rec, "food")), Econ.pantry("kibble")])
	# 5. starving, with nothing to eat: the timeline
	Save.d["feeders"] = []
	Save.d["items"]["kibble"] = 0
	var line: Array = []
	var died_at := -1.0
	for days in [0.5, 1.0, 2.0, 3.0, 4.0, 5.0]:
		var r2: Dictionary = rec.duplicate(true)
		r2["uid"] = "starve%d" % int(days * 10)
		r2["needs"] = {"food": 70.0, "energy": 80.0, "joy": 70.0, "clean": 75.0}
		r2.erase("starve")
		r2["needs_t"] = now - days * 86400.0
		Save.d["roster"] = [r2]
		var ev2 := Econ.catch_up_all()
		var st := Care.starve_stage(r2) if not ev2.any(func(e): return e["kind"] == "died") else "dead"
		if st == "dead" and died_at < 0.0: died_at = days
		line.append("%.1fd: %s (food %d, %.0fh starving, trust %d)" % [days, st if st != "" else "fine", int(Care.need(r2, "food")), Care.starve_h(r2), int(r2["trust"])])
	print("ECON  starving timeline: " + "  |  ".join(line))
	ok.call(died_at >= 3.0 and died_at <= 5.0, "unfed with no feeder, a kin dies after several days (day %.1f)" % died_at)
	ok.call(Econ.graves().size() >= 1 and String(Econ.graves()[0]["cause"]) == "starved" and String(Econ.graves()[0]["name"]) == "Pip", "a grave with its name (%d graves, %d memories)" % [Econ.graves().size(), (Econ.graves()[0]["mem"] as Array).size() if Econ.graves().size() > 0 else 0])
	# 6. the Soul Shrine brings one back, changed
	var g: Dictionary = Econ.graves()[Econ.graves().size() - 1]
	ok.call(Econ.keep_soul(g) != "", "no shrine yet: can't keep a soul")
	Save.d["buildings"].append("shrine")
	Save.d["valuables"]["soul_ember"] = 1
	Save.d["gems"] = 500
	ok.call(Econ.keep_soul(g) == "" and g["soul"], "soul kept in the shrine")
	var before: Dictionary = (g["rec"] as Dictionary).duplicate(true)
	before["level"] = 6
	g["rec"]["level"] = 6; g["level"] = 6
	var rng := RandomNumberGenerator.new(); rng.seed = 9
	var back := Econ.revive(g, rng)
	var tdiff := 0.0
	for t in before["traits"]: tdiff += absf(float(before["traits"][t]) - float(back["traits"].get(t, 0.0)))
	print("ECON  revived %s %s: level %d -> %d, trust %d -> %d, traits moved %.2f, memories %d -> %d, ghost=%s, likes %s -> %s" % [back["name"], back["title"], int(before["level"]), int(back["level"]), int(before["trust"]), int(back["trust"]), tdiff, (before["memory"] as Array).size(), (back["memory"] as Array).size(), back.get("ghost", false), str(before.get("likes", {}).get("food", "")), str(back["likes"]["food"])])
	ok.call(not back.is_empty() and back["ghost"] and String(back["title"]) != "" and int(back["level"]) == 4 and tdiff > 0.05 and Save.d["roster"].has(back) and not Econ.graves().has(g) and Econ.embers() == 0, "revived kin comes back changed")
	# weapons found in a region lean to its element (the meadow has none of its own)
	var erng := RandomNumberGenerator.new(); erng.seed = 77
	var by_biome := {}
	for bi in ["ember", "frost", "storm", "bloom", "gloom", "meadow"]:
		var cnt := {}
		for n in 400:
			var e := Loot.roll_element(erng, bi)
			cnt[e] = int(cnt.get(e, 0)) + 1
		by_biome[bi] = cnt
	var home_el := func(bi: String) -> String:
		for el in Loot.ELEMENTS:
			if String(Loot.ELEMENTS[el]["biome"]) == bi: return el
		return ""
	var lean := true
	for bi in ["ember", "frost", "storm", "bloom", "gloom"]:
		var mine := int(by_biome[bi].get(home_el.call(bi), 0))
		for el in by_biome[bi]:
			if el != "" and el != home_el.call(bi) and int(by_biome[bi][el]) >= mine: lean = false
	print("ECON  elements by biome (of 400): %s" % str(by_biome))
	ok.call(lean and int(by_biome["meadow"].get("", 0)) > 300, "each region's weapons lean to its own element")
	# an old save (from before the armory and feeders) loads and gets them filled in
	var old := Save.fresh()
	for k in ["armory", "raid_out", "loadout", "valuables", "feeders", "graves", "arm_lvl", "pack_lvl", "scrap", "feeder_inv", "feeder_given"]:
		old.erase(k)
	var orec := Save.new_kin("zapple", "Oldie")
	orec.erase("starve")
	old["roster"] = [orec]
	Save.d = old
	Econ.ensure()
	Care.catch_up(orec)
	ok.call(Econ.armory().is_empty() and Econ.feeders().size() == 1 and Econ.graves().is_empty() and Econ.pack_cap() == Econ.PACK_CAPS[0] and Care.starve_stage(orec) == "" and Econ.begin_raid().is_empty(), "an old save loads: a first trough, empty armory, %d-slot backpack" % Econ.pack_cap())
	print("ECON DONE failures: %d" % bad[0])
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

## Headless check for the ability verbs: each one fired at a dummy rival, asserting what it should
## do (a hook drags them in, a wall stops a shot, a mirror sends it back, a slam throws them up...).
var _ac_fail := 0
func _ac(name: String, ok: bool, info := "") -> void:
	print("ACHECK %-26s %s  %s" % [name, "PASS" if ok else "FAIL", info])
	if not ok: _ac_fail += 1

func _ac_setup(dist: float, extra_t := false) -> Array:
	var m := Match.new()
	add_child(m)
	m.start({"training": true, "teams": 1, "squad": 1, "tier": 0, "length": 1e9, "seed": 4242, "no_drop": true, "weapon": "rifle", "cls": "medium"})
	m.set_process(false)
	var P: Hunter = m.player
	for mb in m.mobs: mb.queue_free()
	m.mobs.clear()
	# a flat, open strip of ground for the test: the training map is small and busy, so the logical
	# tiles around the spawn are levelled (headless, nothing is drawn)
	var W = m.world
	var hx := int(floor(P.pos.x)); var hz := int(floor(P.pos.z))
	var hi: int = W.idx(hx, hz)
	var lv: int = int(W.level[hi]) if W.kind[hi] != World.T_VOID else 0
	for dz in range(-3, 4):
		for dx in range(-6, int(dist) + 7):
			if not W.inb(hx + dx, hz + dz): continue
			var i: int = W.idx(hx + dx, hz + dz)
			W.kind[i] = World.T_GROUND
			W.level[i] = lv
			W.island[i] = W.island[hi]
			W.stairs.erase(i); W.walls.erase(i); W.props.erase(i); W.bush.erase(i)
	var home := Vector3(hx + 0.5, lv * World.LEVEL, hz + 0.5)
	P.teleport(home)
	P.vel = Vector3.ZERO
	P.hp = P.max_hp
	var T: Hunter = m.make_hunter("T", 5, "medium", "Target", "idle", {}, home + Vector3(dist, 0, 0))
	T.max_hp = 10000.0; T.hp = T.max_hp; T.armor = 0.0; T.max_armor = 0.0
	var T2: Hunter = null
	if extra_t:
		T2 = m.make_hunter("T2", 5, "medium", "Target2", "idle", {}, home + Vector3(dist + 2.0, 0, 0))
		T2.max_hp = 10000.0; T2.hp = T2.max_hp; T2.armor = 0.0; T2.max_armor = 0.0
	for i in 5: m.step(Match.DT)
	P.inp["aim"] = T.pos + Vector3(0, 0.9, 0); P.inp["aim_y"] = T.pos.y
	if OS.get_cmdline_user_args().has("--ac-debug"):
		print("  setup home=%s P=%s T=%s gP=%.2f gT=%.2f Tgr=%s Pgr=%s" % [home, P.pos, T.pos, m.world.ground_at(P.pos.x, P.pos.z), m.world.ground_at(T.pos.x, T.pos.z), T.grounded, P.grounded])
	return [m, P, T, T2]

func _ac_run(m: Match, secs: float, each := Callable()) -> void:
	var t := 0.0
	while t < secs:
		if each.is_valid(): each.call()
		for mb in m.mobs: mb.queue_free()
		m.mobs.clear()
		m.step(Match.DT); t += Match.DT

func _ac_glove(P: Hunter, gid: String, rar := 1) -> void:
	P.gear[0] = {"id": gid, "rar": rar}
	P.gear_cd[0] = 0.0
	P.m.use_gear(P, 0)

func _ability_check() -> void:
	var r: Array
	var m: Match; var P: Hunter; var T: Hunter
	# 1. Hook glove drags the target in
	r = _ac_setup(7.0); m = r[0]; P = r[1]; T = r[2]
	var d0 := P.flat_dist(T)
	_ac_glove(P, "grapple")
	_ac_run(m, 1.0)
	_ac("hook pulls target", P.flat_dist(T) < 3.0, "dist %.1f -> %.1f" % [d0, P.flat_dist(T)])
	m.queue_free(); await get_tree().process_frame
	# 2. Barrier wall stops an enemy shot
	r = _ac_setup(7.0); m = r[0]; P = r[1]; T = r[2]
	P.inp["aim"] = P.pos + Vector3(2.5, 0.9, 0)
	_ac_glove(P, "barrier")
	var whp: float = m.verbs.walls[0]["hp"] if not m.verbs.walls.is_empty() else -1.0
	var php := P.hp
	m.spawn_shot(T, T.pos + Vector3(-0.6, 0.95, 0), Vector2(-30, 0), 20.0, 0.5, 0.15, Color.RED, {})
	_ac_run(m, 0.5)
	var whp2: float = m.verbs.walls[0]["hp"] if not m.verbs.walls.is_empty() else -1.0
	_ac("wall blocks a shot", P.hp >= php and whp2 < whp and whp > 0.0, "wall hp %.0f -> %.0f, player hp %.0f -> %.0f" % [whp, whp2, php, P.hp])
	# a barrier stops bodies too: walk the target into it
	var tx0 := T.pos.x
	_ac_run(m, 1.2, func(): T.inp["move"] = Vector2(-1, 0))
	_ac("wall blocks movement", T.pos.x > P.pos.x + 2.4, "target x %.1f (wall at %.1f)" % [T.pos.x - P.pos.x, 2.5])
	m.queue_free(); await get_tree().process_frame
	# 3. Mirror glove reflects a shot back at the shooter
	r = _ac_setup(6.0); m = r[0]; P = r[1]; T = r[2]
	_ac_glove(P, "bubble")
	php = P.hp
	var thp := T.hp
	m.spawn_shot(T, T.pos + Vector3(-0.6, 0.95, 0), Vector2(-30, 0), 20.0, 0.6, 0.15, Color.RED, {})
	_ac_run(m, 0.6)
	_ac("reflect returns a shot", P.hp >= php and T.hp < thp, "shooter took %.0f, player took %.0f" % [thp - T.hp, php - P.hp])
	m.queue_free(); await get_tree().process_frame
	# 4. Riposte (frontal) parries a melee swing and stuns the swinger
	r = _ac_setup(1.4); m = r[0]; P = r[1]; T = r[2]
	P.runner.set_slot("utility", Content.ability("riposte"))
	P.runner.use("utility", {})
	m.spawn_shot(T, T.pos + Vector3(-0.3, 0.95, 0), Vector2(-40, 0), 10.0, 0.08, 0.3, Color.RED, {"melee": true})
	_ac_run(m, 0.15)
	_ac("riposte parries melee", T.stun_t > 0.3, "attacker stun %.2f" % T.stun_t)
	m.queue_free(); await get_tree().process_frame
	# 5. Earthshatter: leap, knock up; an airborne target is spiked
	r = _ac_setup(5.0); m = r[0]; P = r[1]; T = r[2]
	P.runner.set_slot("utility", Content.ability("earthshatter"))
	P.runner.use("utility", {})
	var acc := {"top": 0.0, "hits": 0, "last": 0.0}
	var g := T.pos.y
	_ac_run(m, 1.0, func(): acc["top"] = maxf(acc["top"], T.pos.y - g))
	_ac("slam knocks up", acc["top"] > 0.5 and T.hp < T.max_hp, "rose %.2fm, took %.0f" % [acc["top"], T.max_hp - T.hp])
	m.queue_free(); await get_tree().process_frame
	r = _ac_setup(5.0); m = r[0]; P = r[1]; T = r[2]
	P.runner.set_slot("utility", Content.ability("earthshatter"))
	P.runner.use("utility", {})
	_ac_run(m, 0.42)
	T.vel.y = 7.0; T.grounded = false
	_ac_run(m, 0.3)
	_ac("slam spikes airborne", T.stun_t > 0.4, "stun %.2f, took %.0f" % [T.stun_t, T.max_hp - T.hp])
	m.queue_free(); await get_tree().process_frame
	# 6. Leash Bolt: tether snaps when stretched
	r = _ac_setup(5.0); m = r[0]; P = r[1]; T = r[2]
	P.runner.set_slot("utility", Content.ability("leash_bolt"))
	P.runner.use("utility", {})
	_ac_run(m, 0.4)
	var tethered := not m.verbs.tethers.is_empty()
	thp = T.hp
	T.teleport(P.pos + Vector3(8.0, 0, 0))
	_ac_run(m, 0.2)
	_ac("tether snaps", tethered and T.hp < thp - 15.0 and T.stun_t > 0.5, "tethered=%s snap dmg %.0f stun %.2f" % [tethered, thp - T.hp, T.stun_t])
	m.queue_free(); await get_tree().process_frame
	# 7. Tripwire Mine roots whoever steps on it
	r = _ac_setup(4.0); m = r[0]; P = r[1]; T = r[2]
	P.runner.set_slot("utility", Content.ability("tripwire_mine"))
	P.inp["aim"] = T.pos + Vector3(-1.5, 0, 0)
	P.runner.use("utility", {})
	_ac_run(m, 1.0)
	var before_root := T.root_t
	_ac_run(m, 1.0, func(): T.inp["move"] = Vector2(-1, 0))
	_ac("trap roots on step", before_root <= 0.0 and (T.root_t > 0.0 or T.hp < T.max_hp) and m.verbs.traps.is_empty(), "root %.2f, took %.0f" % [T.root_t, T.max_hp - T.hp])
	m.queue_free(); await get_tree().process_frame
	# 8. Moon Swap (kin E, performed from the shoulder): trade places
	r = _ac_setup(6.0); m = r[0]; P = r[1]; T = r[2]
	var pa := P.pos; var ta := T.pos
	Effects.run(Content.ability("moon_swap").effects, P, {"aim": T.pos})
	_ac_run(m, 0.5)
	_ac("swap trades places", P.flat_dist(ta) < 1.2 and T.flat_dist(pa) < 1.2, "player at %.1f from target's spot" % P.flat_dist(ta))
	m.queue_free(); await get_tree().process_frame
	# 9. Fissure glove: the line throws the target up
	r = _ac_setup(5.0); m = r[0]; P = r[1]; T = r[2]
	_ac_glove(P, "quake")
	acc["top"] = 0.0; g = T.pos.y
	_ac_run(m, 1.0, func(): acc["top"] = maxf(acc["top"], T.pos.y - g))
	_ac("fissure knocks up", acc["top"] > 0.4 and T.hp < T.max_hp, "rose %.2f" % acc["top"])
	m.queue_free(); await get_tree().process_frame
	# 10. Vortex glove: drags the target to the centre
	r = _ac_setup(6.0); m = r[0]; P = r[1]; T = r[2]
	var ctr := T.pos + Vector3(2.0, 0, 0)
	P.inp["aim"] = ctr
	_ac_glove(P, "shock")
	var dc0 := T.flat_dist(ctr)
	_ac_run(m, 1.0)
	_ac("vortex pulls in", T.flat_dist(ctr) < dc0 - 0.6, "to centre %.1f -> %.1f" % [dc0, T.flat_dist(ctr)])
	m.queue_free(); await get_tree().process_frame
	# 11. Razor Disc: out and back, hitting twice
	r = _ac_setup(4.0); m = r[0]; P = r[1]; T = r[2]
	P.runner.set_slot("utility", Content.ability("razor_disc"))
	P.runner.use("utility", {})
	acc["hits"] = 0; acc["last"] = T.hp
	_ac_run(m, 1.6, func():
		if T.hp < float(acc["last"]) - 0.5: acc["hits"] = int(acc["hits"]) + 1
		acc["last"] = T.hp)
	_ac("boomerang hits twice", int(acc["hits"]) >= 2, "%d hits" % acc["hits"])
	m.queue_free(); await get_tree().process_frame
	# 12. Rail Charge: a full charge pierces two in a line
	r = _ac_setup(5.0, true); m = r[0]; P = r[1]; T = r[2]
	var T2: Hunter = r[3]
	P.runner.set_slot("utility", Content.ability("rail_charge"))
	P.runner.use("utility", {"charge": 1.0})
	_ac_run(m, 0.4)
	_ac("rail pierces", T.hp < T.max_hp - 20.0 and T2.hp < T2.max_hp - 20.0, "%.0f and %.0f" % [T.max_hp - T.hp, T2.max_hp - T2.hp])
	# and the player's held charge path: press, hold 1s, let go
	P.runner.reset()
	T.hp = T.max_hp
	P.inp["aim"] = T.pos + Vector3(0, 0.9, 0)
	P.inp["sec"] = true; P.inp["sec_hold"] = true
	_ac_run(m, 1.0, func(): P.inp["sec_hold"] = true)
	P.inp["sec_hold"] = false
	_ac_run(m, 0.3)
	_ac("rail hold-to-charge", T.hp < T.max_hp - 25.0, "took %.0f" % (T.max_hp - T.hp))
	m.queue_free(); await get_tree().process_frame
	# 13. Breach: throws the target back and you the other way
	r = _ac_setup(2.5); m = r[0]; P = r[1]; T = r[2]
	P.runner.set_slot("utility", Content.ability("breach"))
	var p0 := P.pos; var t0 := T.pos
	P.runner.use("utility", {})
	var pv := P.vel
	_ac_run(m, 0.5)
	print("   breach vel after cast ", pv)
	_ac("breach knocks both apart", T.pos.x - t0.x > 1.5 and p0.x - P.pos.x > 1.0, "target +%.1f, you -%.1f" % [T.pos.x - t0.x, p0.x - P.pos.x])
	m.queue_free(); await get_tree().process_frame
	# 14. Bulwark: a shield that follows you and stops shots
	r = _ac_setup(6.0); m = r[0]; P = r[1]; T = r[2]
	P.runner.set_slot("utility", Content.ability("bulwark"))
	P.runner.use("utility", {})
	php = P.hp
	m.spawn_shot(T, T.pos + Vector3(-0.6, 0.95, 0), Vector2(-30, 0), 20.0, 0.5, 0.15, Color.RED, {})
	_ac_run(m, 0.4)
	_ac("bulwark blocks", P.hp >= php and not m.verbs.walls.is_empty(), "")
	m.queue_free(); await get_tree().process_frame
	# 15. Shadow Step: knife, then you're behind them
	r = _ac_setup(6.0); m = r[0]; P = r[1]; T = r[2]
	P.runner.set_slot("utility", Content.ability("shadow_step"))
	P.runner.use("utility", {})
	_ac_run(m, 0.4)
	_ac("shadow step lands behind", P.pos.x > T.pos.x and P.flat_dist(T) < 1.8 and P.crit_t > 0.0, "x %.1f vs %.1f, target took %.0f" % [P.pos.x, T.pos.x, T.max_hp - T.hp])
	m.queue_free(); await get_tree().process_frame
	# 16. Ice Bridge: over the abyss
	r = _ac_setup(4.0); m = r[0]; P = r[1]; T = r[2]
	var edge := Vector3.INF; var ed := Vector2.ZERO
	for i in 4000:
		var q: Vector3 = m.world.random_ground()
		for dd in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			var q2 := q + Vector3(dd.x, 0, dd.y) * 1.2
			if m.world.is_void(q2.x, q2.z) and not m.world.is_block(q.x, q.z):
				edge = q; ed = dd; break
		if edge != Vector3.INF: break
	P.teleport(edge); P.inp["aim"] = edge + Vector3(ed.x, 0, ed.y) * 8.0
	_ac_glove(P, "frost")
	var ground_ok: bool = not m.world.is_void(edge.x + ed.x * 3.0, edge.z + ed.y * 3.0)
	_ac("ice bridge makes ground", not m.verbs.terrain.is_empty() and ground_ok, "%d tiles" % (m.verbs.terrain[0]["tiles"].size() if not m.verbs.terrain.is_empty() else 0))
	_ac_run(m, 7.5)
	_ac("ice bridge melts", m.verbs.terrain.is_empty() and m.world.is_void(edge.x + ed.x * 3.0, edge.z + ed.y * 3.0), "")
	m.queue_free(); await get_tree().process_frame
	# 17. Prism Wall (kin E) reflects shots back
	r = _ac_setup(7.0); m = r[0]; P = r[1]; T = r[2]
	P.inp["aim"] = P.pos + Vector3(2.5, 0, 0)
	Effects.run(Content.ability("prism_wall").effects, P, {"aim": P.pos + Vector3(2.5, 0, 0)})
	thp = T.hp; php = P.hp
	m.spawn_shot(T, T.pos + Vector3(-0.6, 0.95, 0), Vector2(-30, 0), 20.0, 0.6, 0.15, Color.RED, {})
	_ac_run(m, 0.6)
	_ac("prism wall reflects", T.hp < thp and P.hp >= php, "shooter took %.0f" % (thp - T.hp))
	m.queue_free(); await get_tree().process_frame
	# 18. Stinger Hook (kin E): yanks to the caster and blights
	r = _ac_setup(6.0); m = r[0]; P = r[1]; T = r[2]
	Effects.run(Content.ability("stinger_hook").effects, P, {"aim": T.pos})
	_ac_run(m, 0.8)
	_ac("stinger hook yanks + blights", P.flat_dist(T) < 3.0 and T.blight_t > 0.0, "dist %.1f blight %.1f" % [P.flat_dist(T), T.blight_t])
	m.queue_free(); await get_tree().process_frame
	# 19. Gravity Slam (kin E) pulls in and lifts
	r = _ac_setup(5.0); m = r[0]; P = r[1]; T = r[2]
	var gk: Kin = P.kin
	if gk:
		gk.teleport(P.pos + Vector3(1, 0, 0)); gk.state = "active"
		var land := T.pos + Vector3(1.5, 0, 0)
		Effects.run(Content.ability("slam").effects, gk, {"aim": land})
		acc["top"] = 0.0; g = T.pos.y
		var dl := T.flat_dist(land)
		var mind := {"d": dl, "v": 0.0}
		var to_c := Vector2(land.x - T.pos.x, land.z - T.pos.z).normalized()
		_ac_run(m, 1.0, func():
			acc["top"] = maxf(acc["top"], T.pos.y - g)
			mind["v"] = maxf(float(mind["v"]), Vector2(T.vel.x, T.vel.z).dot(to_c))
			mind["d"] = minf(mind["d"], T.flat_dist(land)))
		# (the kin itself lands in the crater, so the pull ends against its body)
		_ac("gravity slam pulls + lifts", acc["top"] > 0.4 and float(mind["v"]) > 3.0, "rose %.2f, pulled at %.1fm/s toward the crater (kin %s)" % [acc["top"], mind["v"], gk.state])
	m.queue_free(); await get_tree().process_frame
	# 20. Dashes: class verbs and kin riders. Each starts grounded at the same spot, 3m short of the target.
	r = _ac_setup(6.0); m = r[0]; P = r[1]; T = r[2]
	var home2 := P.pos
	var kref = P.kin
	var ready := func(cls: String, sp: String, at: Vector3, mv: Vector2) -> void:
		P.teleport(at); P.vel = Vector3.ZERO
		T.teleport(home2 + Vector3(6.0, 0, 0)); T.vel = Vector3.ZERO
		T.burn_t = 0.0; T.blight_t = 0.0; T.slow_t = 0.0; T.stun_t = 0.0; T.root_t = 0.0; T.knock_t = 0.0
		P.cls = cls; P.dodge_def = Content.class_dodge(cls)
		P.kin = kref if sp != "" else null
		if P.kin: (P.kin as Kin).species = sp
		_ac_run(m, 0.3)
		P.dashes = P.max_dashes(); P.ex_cd = 0.0; P.roll_t = 0.0
		P.inp["move"] = mv
	# Light: phase step, a shot fired through you mid-step does nothing
	ready.call("light", "", home2, Vector2(1, 0))
	var php2 := P.hp
	P.do_dash()
	m.spawn_shot(T, P.pos + Vector3(1.0, 0.95, 0), Vector2(-30, 0), 20.0, 0.3, 0.15, Color.RED, {})
	_ac_run(m, 0.25)
	_ac("light phase: shots pass", P.phase_t >= 0.0 and P.hp >= php2, "hp %.0f -> %.0f" % [php2, P.hp])
	# Medium: the roll reloads
	ready.call("medium", "", home2, Vector2(1, 0))
	P.ammo = 0
	P.do_dash()
	_ac("medium roll reloads", P.ammo > 0, "ammo %d" % P.ammo)
	# Heavy: the charge bowls the target back
	ready.call("heavy", "", T.pos + Vector3(-2.2, 0, 0), Vector2(1, 0))
	var tx := T.pos.x
	P.do_dash()
	_ac_run(m, 0.5)
	_ac("heavy charge knocks back", T.pos.x - tx > 1.0 and T.hp < T.max_hp, "target pushed %.1f, took %.0f" % [T.pos.x - tx, T.max_hp - T.hp])
	if kref:
		# lunar: no travel, an instant blink
		ready.call("medium", "wisplet", home2, Vector2(1, 0))
		var bp := P.pos
		P.do_dash()
		_ac("lunar dash blinks", P.roll_t <= 0.0 and P.flat_dist(bp) > 2.0, "moved %.1f instantly" % P.flat_dist(bp))
		# venom: dash through the target poisons them
		ready.call("medium", "cindle", T.pos + Vector3(-1.8, 0, 0), Vector2(1, 0))
		T.burn_t = 0.0; T.blight_t = 0.0
		P.do_dash()
		_ac_run(m, 0.4)
		_ac("venom dash poisons", T.burn_t > 0.0 or T.blight_t > 0.0, "burn %.1f blight %.1f" % [T.burn_t, T.blight_t])
		# gravity: where you stop, foes nearby are tugged toward you
		ready.call("medium", "pebbit", home2, Vector2(1, 0))
		var tmin := {"x": T.pos.x, "v": 0.0, "px": 0.0}
		P.do_dash()
		_ac_run(m, 0.5, func():
			tmin["x"] = minf(float(tmin["x"]), T.pos.x)
			if -T.vel.x > float(tmin["v"]): tmin["v"] = -T.vel.x; tmin["px"] = P.pos.x - home2.x)
		_ac("gravity dash tugs", float(tmin["v"]) > 3.0, "target pulled at %.1fm/s (you at %.1f), to x %.2f from %.2f; element %s" % [tmin["v"], tmin["px"], float(tmin["x"]) - home2.x, T.pos.x - home2.x, P.kin_element()])
		# echo: a second, shorter dash a beat later
		ready.call("medium", "zapple", home2 + Vector3(-4.0, 0, 0), Vector2(1, 0))
		var e0 := P.pos.x
		P.do_dash()
		_ac_run(m, 0.2)
		var e1 := P.pos.x
		_ac_run(m, 0.5)
		_ac("echo dash repeats", P.pos.x - e1 > 1.0, "first %.1fm, then +%.1fm" % [e1 - e0, P.pos.x - e1])
		# spore: a slowing cloud where you started
		ready.call("medium", "burrlet", home2, Vector2(-1, 0))
		var nf := m.fields.list.size()
		P.do_dash()
		_ac("spore dash leaves cloud", m.fields.list.size() > nf, "")
		# prism: a decoy where you started
		ready.call("medium", "puddlet", home2, Vector2(-1, 0))
		var nd := m.verbs.decoys.size()
		P.do_dash()
		_ac("prism dash leaves decoy", m.verbs.decoys.size() > nd, "")
	m.queue_free(); await get_tree().process_frame
	# 21. Every ability and active glove runs without errors (watch the log for SCRIPT ERROR)
	r = _ac_setup(5.0); m = r[0]; P = r[1]; T = r[2]
	var n := 0
	for id in Content.ids("abilities"):
		var ad := Content.ability(id)
		P.teleport(T.pos + Vector3(-5, 0, 0)); P.vel = Vector3.ZERO
		P.inp["aim"] = T.pos + Vector3(0, 0.9, 0)
		Effects.run(ad.effects, P, {"slot": "utility", "ability": id, "charge": 0.7})
		_ac_run(m, 0.8)
		n += 1
	for gid in Gear.ALL:
		if Gear.active(gid):
			P.teleport(T.pos + Vector3(-5, 0, 0)); P.vel = Vector3.ZERO
			P.inp["aim"] = T.pos + Vector3(0, 0.9, 0)
			for rar in [1, 4]:
				_ac_glove(P, gid, rar)
				_ac_run(m, 0.6)
			n += 1
	_ac("all abilities run", true, "%d ran" % n)
	m.queue_free(); await get_tree().process_frame
	# 22. Ranks: a rank-3 slot makes the same verb stronger and recharge faster
	r = _ac_setup(7.0); m = r[0]; P = r[1]; T = r[2]
	P.inp["aim"] = P.pos + Vector3(2.5, 0.9, 0)
	P.slot_lv["gear"] = 1
	_ac_glove(P, "barrier")
	var hp1: float = m.verbs.walls[-1]["hp"] if not m.verbs.walls.is_empty() else 0.0
	var cd1: float = P.gear_cd[0]
	P.slot_lv["gear"] = 3
	_ac_glove(P, "barrier")
	var hp3: float = m.verbs.walls[-1]["hp"] if not m.verbs.walls.is_empty() else 0.0
	var cd3: float = P.gear_cd[0]
	_ac("rank 3 glove: tougher, faster", hp3 > hp1 * 1.3 and cd3 < cd1 * 0.85, "wall hp %.0f -> %.0f, cooldown %.1f -> %.1f" % [hp1, hp3, cd1, cd3])
	P.runner.set_slot("utility", Content.ability("leash_bolt"))
	P.slot_lv["sec"] = 3
	P.inp["aim"] = T.pos + Vector3(0, 0.9, 0)
	P.runner.use("utility", {"level": P.ability_level("sec")})
	_ac("rank 3 RMB cooldown", P.runner.cd_left("utility") < Content.ability("leash_bolt").cooldown * 0.85, "%.1fs" % P.runner.cd_left("utility"))
	m.queue_free(); await get_tree().process_frame
	print("ACHECK DONE, failures: ", _ac_fail)
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

## Headless check of every way out: call a skiff (monster waves come, a rival can board too, it
## leaves with whoever's on deck), open a rift hatch with a key (and lose a key to a deathbox, then
## loot it back), and charge an uplink (a rival in the yard stalls it, it completes, the lift opens).
func _extract_check() -> void:
	var ok := true
	var fresh := func() -> Match:
		var mm := Match.new()
		add_child(mm)
		mm.start({"teams": 2, "squad": 2, "tier": 0, "seed": 77, "no_drop": true, "autoplay": true})
		mm.set_process(false)
		for h in mm.hunters:
			h.ctrl = "idle"; h.inp["move"] = Vector2.ZERO
			h.max_hp = 5000.0; h.hp = 5000.0
		for mb in mm.mobs: mb.queue_free()
		mm.mobs.clear()
		return mm
	var run := func(mm: Match, sec: float, every := Callable()):
		var t := 0.0
		while t < sec and not mm.over:
			if every.is_valid(): every.call()
			mm.step(Match.DT); t += Match.DT
	# keeps the test quiet: wave monsters cleared, and the idle hunters held where they were put
	# (biome hazards like gusts would otherwise shove them around)
	var calm := func(mm: Match):
		for mb in mm.mobs:
			if not mb.dead: mb.dead = true; mb.visible = false
		for h in mm.hunters:
			if h.has_meta("pin") and not h.extracted and not h.out:
				h.teleport(h.get_meta("pin")); h.vel = Vector3.ZERO
	var done := func(mm: Match):
		mm.over = true       # the end-of-match timer must not take us to the results screen
		mm.queue_free()
	# ---- 1. the skiff
	var m: Match = fresh.call()
	var P: Hunter = m.player
	var mate: Hunter = m.hunters.filter(func(x): return x.team == P.team and x != P)[0]
	var R: Hunter = m.hunters.filter(func(x): return x.team != P.team)[0]
	var docks := m.exits.of_kind("dock")
	print("EXCHECK exits: %d docks, %d hatches, %d outposts" % [docks.size(), m.exits.of_kind("hatch").size(), m.exits.of_kind("outpost").size()])
	if docks.is_empty() or m.exits.of_kind("hatch").is_empty() or m.exits.of_kind("outpost").is_empty():
		print("EXCHECK FAIL a kind of exit is missing"); ok = false
	var d: Dictionary = docks[0]
	m.time = float(d["open_at"]) + 1.0
	P.teleport(d["pos"] + Vector3(0.3, 0, 0.3))
	var t0 := m.time
	var pings_before := m.pings.size()
	run.call(m, 2.5, func(): P.inp["interact"] = true)
	P.inp["interact"] = false
	var flare: bool = (d["node"] as Node3D).get_node("Beacon/Flare").visible
	print("EXCHECK skiff: state=%s after holding %.1fs, arrives in %.0fs; loud: map pings +%d, flare=%s" % [d["state"], m.time - t0, float(d["t"]), m.pings.size() - pings_before, flare])
	if d["state"] != "called" or m.pings.size() <= pings_before or not flare: ok = false; print("EXCHECK FAIL skiff not called (or not loud)")
	# the waves come in: hold everyone where they are (a brute could knock the idle test hunters
	# off the landing) but leave the monsters be, to count them
	P.set_meta("pin", P.pos); mate.set_meta("pin", mate.pos); R.set_meta("pin", R.pos)
	run.call(m, 30.0, func():
		for h in [P, mate, R]:
			if not h.out: h.teleport(h.get_meta("pin")); h.vel = Vector3.ZERO; h.hp = h.max_hp)
	var waves := m.mobs.filter(func(x): return not x.dead and int(x.get_meta("exit", -1)) == int(d["i"])).size()
	print("EXCHECK skiff: waves=%d monsters alive from them=%d t left=%.0f" % [int(d["waves"]), waves, float(d["t"])])
	if int(d["waves"]) < 2 or waves <= 0: ok = false; print("EXCHECK FAIL no monster waves")
	# the player and a rival step on the deck; the teammate stays on the pier's foot (not aboard)
	for mb in m.mobs: mb.dead = true; mb.visible = false
	P.teleport(d["berth"]); R.teleport(d["berth"] + Vector3(0.8, 0, 0.4))
	mate.teleport(d["pos"])
	for h in [P, R, mate]: h.set_meta("pin", h.pos)
	while d["state"] == "called" and m.time - t0 < 80.0: run.call(m, Match.DT, calm.bind(m))
	print("EXCHECK skiff: state=%s (boarding %.0fs) player %.1fm from the berth (y %.2f vs %.2f) downed=%s out=%s" % [d["state"], float(d["t"]), P.flat_dist(d["berth"]), P.pos.y, d["berth"].y, P.downed, P.out])
	run.call(m, 1.0, calm.bind(m))
	print("EXCHECK skiff: aboard=%s" % str((d["aboard"] as Array).map(func(x): return x.pname)))
	while d["state"] == "boarding" and m.time - t0 < 100.0: run.call(m, Match.DT, calm.bind(m))
	print("EXCHECK skiff: left. player extracted=%s how=%s where=%s  rival extracted=%s  mate (on the pier) extracted=%s" % [P.extracted, m.result.get("how", ""), m.result.get("where", ""), R.extracted, mate.extracted])
	if not P.extracted or m.result.get("how", "") != "skiff" or not R.extracted or mate.extracted: ok = false; print("EXCHECK FAIL skiff boarding")
	done.call(m)
	await get_tree().process_frame
	# ---- 2. the rift hatch
	m = fresh.call()
	P = m.player
	R = m.hunters.filter(func(x): return x.team != P.team)[0]
	mate = m.hunters.filter(func(x): return x.team == P.team and x != P)[0]
	var hx: Dictionary = m.exits.of_kind("hatch")[0]
	R.rift_keys = 0
	R.teleport(hx["pos"] + Vector3(0.6, 0, 0.6))
	run.call(m, 0.5, func(): R.inp["interact"] = true)
	print("EXCHECK hatch: without a key: state=%s rival extracted=%s" % [hx["state"], R.extracted])
	if hx["state"] != "sealed" or R.extracted: ok = false; print("EXCHECK FAIL hatch opened without a key")
	R.inp["interact"] = false
	R.teleport(m.world.random_ground())
	# a key in a deathbox: the teammate dies carrying one, the player loots it
	mate.rift_keys = 1
	mate.lives = 1
	mate.teleport(hx["pos"] + Vector3(3.0, 0, 0))
	m.eliminate(mate, R, "knocked out", true)
	var bx := Life.box_of(m, mate)
	print("EXCHECK hatch: teammate died with a key: their keys=%d box keys=%d" % [mate.rift_keys, int(bx.get("keys", -1))])
	if mate.rift_keys != 0 or int(bx.get("keys", 0)) != 1: ok = false; print("EXCHECK FAIL key not in the box")
	P.rift_keys = 0
	var got_key := false
	for it in Life.box_items(m, P, bx):
		if it["key"] == "keys": Life.take_item(m, P, bx, it); got_key = true
	print("EXCHECK hatch: looted the box: player keys=%d" % P.rift_keys)
	if not got_key or P.rift_keys != 1: ok = false; print("EXCHECK FAIL couldn't loot the key")
	var feed0 := m.feed_all.size()
	var pings0 := m.pings.size()
	P.teleport(hx["pos"] + Vector3(0.7, 0, 0.5))
	t0 = m.time
	run.call(m, 0.4, func(): P.inp["interact"] = true)
	P.inp["interact"] = false
	print("EXCHECK hatch: opened in %.2fs state=%s player extracted=%s how=%s keys left=%d  quiet: new pings=%d" % [m.time - t0, hx["state"], P.extracted, m.result.get("how", ""), P.rift_keys, m.pings.size() - pings0])
	if not P.extracted or m.result.get("how", "") != "hatch" or P.rift_keys != 0 or m.pings.size() != pings0: ok = false; print("EXCHECK FAIL hatch")
	# the hatch stays open a moment: a rival steps in after
	R.teleport(hx["pos"] + Vector3(0.3, 0, 0.2))
	run.call(m, 0.3)
	var rival_in := R.extracted
	run.call(m, 6.0)
	print("EXCHECK hatch: rival slipped in behind=%s, then it sealed again: %s" % [rival_in, hx["state"]])
	if not rival_in or hx["state"] != "sealed": ok = false; print("EXCHECK FAIL hatch window")
	done.call(m)
	await get_tree().process_frame
	# ---- 3. the uplink
	m = fresh.call()
	P = m.player
	R = m.hunters.filter(func(x): return x.team != P.team)[0]
	var o: Dictionary = m.exits.of_kind("outpost")[0]
	m.time = float(o["open_at"]) + 1.0
	P.teleport(o["pos"] + Vector3(0.6, 0, 0.6))
	run.call(m, 2.0, func(): P.inp["interact"] = true)
	P.inp["interact"] = false
	P.set_meta("pin", o["pos"] + Vector3(0.6, 0, 0.6))
	print("EXCHECK uplink: state=%s team=%d" % [o["state"], int(o["team"])])
	if o["state"] != "charging": ok = false; print("EXCHECK FAIL uplink didn't start")
	run.call(m, 8.0, calm.bind(m))
	var p1 := float(o["prog"])
	R.teleport(o["pos"] + Vector3(-1.6, 0, 1.0))
	R.set_meta("pin", R.pos)
	run.call(m, 1.0, calm.bind(m))
	var pa := float(o["prog"])
	run.call(m, 3.0, calm.bind(m))
	var pb := float(o["prog"])
	print("EXCHECK uplink: %d%% after 8s; rival in the yard: contested=%s %d%% -> %d%% over 3s (paused)" % [int(p1 * 100), o["contested"], int(pa * 100), int(pb * 100)])
	if p1 <= 0.1 or not o["contested"] or absf(pb - pa) > 0.001: ok = false; print("EXCHECK FAIL contest")
	R.remove_meta("pin")
	R.teleport(m.world.random_ground())
	t0 = m.time
	while o["state"] == "charging" and m.time - t0 < 60.0:
		run.call(m, 0.5, calm.bind(m))
	print("EXCHECK uplink: state=%s after %.0fs more, waves=%d prog=%.2f contested=%s player in yard=%s (%.1fm) downed=%s" % [o["state"], m.time - t0, int(o["waves"]), float(o["prog"]), o["contested"], m.exits.in_yard(o, P), P.flat_dist(o["pos"]), P.downed])
	for h in m.hunters: print("   ", h.pname, " team ", h.team, " ", h.flat_dist(o["pos"]), " in yard ", m.exits.in_yard(o, h))
	if o["state"] != "open" or int(o["waves"]) < 2: ok = false; print("EXCHECK FAIL uplink never completed (or no waves)")
	P.remove_meta("pin")
	P.teleport(o["pos"] + Vector3(0.4, 0, 0.3))
	run.call(m, 0.3)
	print("EXCHECK uplink: player extracted=%s how=%s where=%s" % [P.extracted, m.result.get("how", ""), m.result.get("where", "")])
	if not P.extracted or m.result.get("how", "") != "uplink": ok = false; print("EXCHECK FAIL lift")
	done.call(m)
	await get_tree().process_frame
	# ---- 4. docks close late, one stays open
	m = fresh.call()
	var closing := m.exits.of_kind("dock").filter(func(x): return float(x["close_at"]) < 1e8).size()
	m.time = m.length - 25.0
	run.call(m, 0.5)
	var still := m.exits.of_kind("dock").filter(func(x): return x["state"] != "closed")
	print("EXCHECK docks: %d close during the match, %d still open near the end; a call now takes %.0fs" % [closing, still.size(), m.exits.call_time()])
	if still.size() != 1 or m.exits.call_time() > 10.0: ok = false; print("EXCHECK FAIL closing")
	done.call(m)
	print("EXCHECK ", "PASS" if ok else "FAIL")
	get_tree().quit()

## Headless check of truces: a weak bot squad offers one to a strong squad (by its own weighing),
## the strong squad answers; with a truce in place neither targets the other; an attack breaks it,
## is announced and marks the betrayer; truce partners share an uplink's yard without contesting it.
func _truce_check() -> void:
	var ok := true
	var m := Match.new()
	add_child(m)
	m.start({"teams": 2, "squad": 2, "tier": 0, "seed": 77, "no_drop": true, "autoplay": true})
	m.set_process(false)
	for mb in m.mobs: mb.queue_free()
	m.mobs.clear()
	m.time = 120.0
	var A: Array = m.hunters.filter(func(x): return x.team == 0)
	var B: Array = m.hunters.filter(func(x): return x.team == 1)
	# open flat ground for the stand-off
	var home: Vector3 = A[0].pos
	for k in 3000:
		var g := m.world.random_ground()
		var roomy := true
		for dx in range(-8, 9, 2):
			for dz in range(-4, 5, 2):
				if m.world.is_void(g.x + dx, g.z + dz) or m.world.is_block(g.x + dx, g.z + dz) or absf(m.world.ground_at(g.x + dx, g.z + dz) - g.y) > 0.3: roomy = false
		if roomy:
			home = g; break
	var spots := {}
	for i in A.size(): spots[A[i]] = home + Vector3(-3.5, 0, -1.0 + 2.0 * i)
	for i in B.size(): spots[B[i]] = home + Vector3(3.5, 0, -1.0 + 2.0 * i)
	for h in m.hunters:
		h.ctrl = "bot"
		h.teleport(spots[h])
	# squad A is hurt and bare; squad B is fresh with good armor
	for h in A:
		h.hp = h.max_hp * 0.2; h.armor = 0.0
	for h in B:
		h.armor_tier = 3; h.armor = h.max_armor
	var hold := func():
		for h in m.hunters:
			if not h.out and not h.extracted:
				h.teleport(spots[h]); h.vel = Vector3.ZERO; h.inv_t = 5.0
				if h.downed: m.revive_hunter(h, null)
				if h.team == 0: h.hp = minf(h.hp, h.max_hp * 0.2); h.armor = 0.0; h.tonics = 0     # squad A stays hurt
	var run := func(sec: float):
		var t := 0.0
		while t < sec:
			hold.call(); m.step(Match.DT); t += Match.DT
	var cross := func() -> int:
		var n := 0
		for h in m.hunters:
			var tg = h.ai.get("tgt")
			if tg is Hunter and (tg as Hunter).team != h.team: n += 1
		return n
	var T: Truce = m.truce
	print("TCHECK strength A=%.1f B=%.1f  peace score A->B=%.2f  B would accept from A=%.2f  A would accept from B=%.2f" % [T.strength(0), T.strength(1), T._peace_score(0, 1, {1: 7.0}), T.would_accept(1, 0), T.would_accept(0, 1)])
	if T.would_accept(1, 0) >= T.would_accept(0, 1): ok = false; print("TCHECK FAIL the stronger squad should be less keen")
	run.call(2.0)
	var before: int = cross.call()
	print("TCHECK before any truce: %d hunters targeting the other squad" % before)
	if before == 0: ok = false; print("TCHECK FAIL they never squared up")
	# the weak squad should raise the flag by itself within a while
	var t0 := m.time
	while not T.events.any(func(e): return String(e).begins_with("offer 0->1")) and m.time - t0 < 40.0:
		run.call(0.25)
	var offered: bool = T.events.any(func(e): return String(e).begins_with("offer 0->1"))
	print("TCHECK weak squad offered a truce: %s after %.1fs" % [offered, m.time - t0])
	if not offered: ok = false; print("TCHECK FAIL no offer")
	run.call(3.5)
	var answered := "accepted" if T.allied(0, 1) else ("faked" if T.events.has("fake 1") else ("refused" if T.events.any(func(e): return String(e).begins_with("refused")) else "no answer"))
	print("TCHECK strong squad answered: %s  (events %s)" % [answered, str(T.events)])
	if answered == "no answer": ok = false; print("TCHECK FAIL no answer")
	if not T.allied(0, 1):
		print("TCHECK (making the truce by hand for the rest of the check)")
		T.make(0, 1)
	for h in m.hunters: h.ai.erase("betray_at"); h.ai.erase("betray")
	run.call(3.0)
	var during: int = cross.call()
	print("TCHECK during the truce: %d hunters targeting the other squad" % during)
	if during != 0: ok = false; print("TCHECK FAIL truce partners still targeted")
	# an attack breaks it
	var traitor: Hunter = B[0]; var victim: Hunter = A[0]
	victim.inv_t = 0.0
	victim.hurt(20.0, traitor, {"src": "shot"})
	var announced: bool = m.feed_all.any(func(f): return String(f).contains("broke the truce"))
	run.call(0.6)
	var hits_back: int = A.filter(func(x): return x.ai.get("tgt") == traitor).size()
	print("TCHECK attack: truce holds=%s announced=%s betrayer marked=%s revealed %.0fs, victims targeting the betrayer=%d" % [T.allied(0, 1), announced, T.is_marked(traitor), traitor.reveal_t, hits_back])
	if T.allied(0, 1) or not announced or not T.is_marked(traitor) or hits_back == 0: ok = false; print("TCHECK FAIL breaking")
	# sharing an uplink
	T.marked.clear()
	T.make(0, 1)
	var o: Dictionary = m.exits.of_kind("outpost")[0]
	m.time = maxf(m.time, float(o["open_at"]) + 1.0)
	m.exits.act(o, "start", A[0])
	spots[A[0]] = o["pos"] + Vector3(1.0, 0, 0.8)
	spots[B[0]] = o["pos"] + Vector3(-1.2, 0, -0.9)
	spots[A[1]] = o["pos"] + Vector3(30, 0, 30); spots[B[1]] = o["pos"] + Vector3(30, 0, 30)
	for h in [A[1], B[1]]: spots[h] = m.world.free_spot_near(spots[h], [], 1.0, 0.5, 20.0)
	var p0 := float(o["prog"])
	run.call(3.0)
	var p1 := float(o["prog"])
	print("TCHECK uplink with a truce partner in the yard: contested=%s %d%% -> %d%%" % [o["contested"], int(p0 * 100), int(p1 * 100)])
	if o["contested"] or p1 <= p0: ok = false; print("TCHECK FAIL partner contested the uplink")
	T.end("0:1", "")
	run.call(1.0)
	var p2 := float(o["prog"])
	run.call(2.0)
	print("TCHECK without the truce: contested=%s %d%% -> %d%%" % [o["contested"], int(p2 * 100), int(float(o["prog"]) * 100)])
	if not o["contested"]: ok = false; print("TCHECK FAIL rival didn't contest")
	# the other way round: now squad B is the beaten one, and an offer to it (as a player would
	# make from the emote wheel) gets accepted by its own weighing
	T.marked.clear(); T._cool.clear()
	spots[A[0]] = home + Vector3(-3.5, 0, -1.0); spots[A[1]] = home + Vector3(-3.5, 0, 1.0)
	spots[B[0]] = home + Vector3(3.5, 0, -1.0); spots[B[1]] = home + Vector3(3.5, 0, 1.0)
	for h in A: h.hp = h.max_hp; h.armor = h.max_armor; h.armor_tier = 3; h.tonics = 3
	for h in B: h.hp = h.max_hp * 0.15; h.armor = 0.0; h.armor_tier = 0; h.tonics = 0; h.ai.erase("betray")
	m.player.team = 0
	var hold2 := func():
		for h in m.hunters:
			h.teleport(spots[h]); h.vel = Vector3.ZERO; h.inv_t = 5.0
			if h.team == 1: h.hp = minf(h.hp, h.max_hp * 0.15); h.armor = 0.0
	var tt := 0.0
	while tt < 1.0: hold2.call(); m.step(Match.DT); tt += Match.DT
	print("TCHECK reversed: B would accept from A=%.2f" % T.would_accept(1, 0))
	T.emote(A[0], "truce")
	tt = 0.0
	while tt < 3.5 and not T.allied(0, 1): hold2.call(); m.step(Match.DT); tt += Match.DT
	print("TCHECK reversed: the beaten squad accepted=%s after %.1fs (events %s)" % [T.allied(0, 1), tt, str(T.events.slice(-3))])
	if not T.allied(0, 1) and not T.events.has("fake 1"): ok = false; print("TCHECK FAIL beaten squad refused")
	m.over = true
	print("TCHECK ", "PASS" if ok else "FAIL")
	get_tree().quit()

## The drop: the planning phase, map pings, the squad following its leader in formation, passing the
## lead, separating, and the randomised spawns (different between seeds, rare kin only where rolled).
func _drop_check() -> void:
	var ok := true
	var m := Match.new()
	add_child(m)
	m.start({"teams": 3, "squad": 3, "tier": 0, "seed": 4101})
	m.set_process(false)
	var P: Hunter = m.player
	var D: DropSquad = m.skydrop
	var mates: Array = m.hunters.filter(func(x): return x.team == P.team and x != P)
	print("DCHECK planning=%s plan_t=%.1f riding=%s leader=%s map open=%s" % [D.planning, D.plan_t, P.riding, D.leader(P.team).pname, m.hud.map_open()])
	if not D.planning or absf(D.plan_t - DropSquad.PLAN_T) > 0.01 or not P.riding or D.leader(P.team) != P or not m.hud.map_open():
		ok = false; print("DCHECK FAIL planning phase did not start right")
	# a ping placed on the map (the same path a click takes)
	var target: Vector3 = m.world.spawns[0]
	var sp: SpawnPlan = m.spawn_plan
	if sp and not sp.active_of("vault").is_empty(): target = sp.active_of("vault")[0]["pos"]
	m.hud.full_map.ping_at(target)
	var mine := m.my_ping()
	print("DCHECK map ping at %s -> %s (squad pings %d)" % [str(target.snapped(Vector3(0.1, 0.1, 0.1))), str(mine.get("pos", Vector3.INF)), m.pings.filter(func(q): return q.has("by")).size()])
	if mine.is_empty() or Vector2(mine["pos"].x - target.x, mine["pos"].z - target.z).length() > 0.6: ok = false; print("DCHECK FAIL map ping")
	var steps := 0
	var t0 := m.time
	while D.planning and steps < 2000:
		m.step(Match.DT); steps += 1
	var bot_pings := m.pings.filter(func(q): return q.has("by") and (q["by"] as Hunter).ctrl == "bot").size()
	var acks := m.truce.shown.filter(func(e): return e["id"] == "omw").size() if m.truce else 0
	print("DCHECK planning lasted %.2fs, match clock %.2f -> %.2f, bot pings %d, bot replies %d, events %s" % [steps * Match.DT, t0, m.time, bot_pings, acks, str(D.events)])
	if absf(steps * Match.DT - DropSquad.PLAN_T) > 0.1 or m.time != t0: ok = false; print("DCHECK FAIL planning length / clock")
	if bot_pings < 1: ok = false; print("DCHECK FAIL bots never pinged")
	# a follower can't jump by themselves while the leader is aboard
	var f0: Hunter = mates[0]
	m.ship_jump(f0)
	if not f0.riding: ok = false; print("DCHECK FAIL a follower jumped without the leader")
	# ride to the middle of the map, then the leader jumps
	var mid := Vector3(m.world.w * 0.5, 0, m.world.h * 0.5)
	while Vector2(m.ship_pos().x - mid.x, m.ship_pos().z - mid.z).length() > 26.0 and m.time < 60.0 and P.riding:
		m.step(Match.DT)
	m.ship_jump(P)
	var fol := mates.filter(func(x): return x.drop_follow == P)
	print("DCHECK leader jumped at t=%.1f: %d of %d squadmates jumped with them (%s)" % [m.time, fol.size(), mates.size(), str(mates.map(func(x): return [x.pname, x.riding, x.dropping]))])
	if fol.size() != mates.size(): ok = false; print("DCHECK FAIL the squad didn't jump together")
	var sep_plan: Array = fol.map(func(x): return snappedf(float(x.ai.get("sep_h", -1.0)), 0.1))
	for f in fol: f.ai["sep_h"] = -1.0       # (bots that break off low down: checked below, not here)
	# the leader steers; the squad follows in its slots
	var worst := 0.0; var t := 0.0
	while t < 1.3 and P.dropping:
		P.inp["move"] = Vector2(1, 0.3).normalized() if t < 0.7 else Vector2(-0.2, 1).normalized()
		m.step(Match.DT); t += Match.DT
		if t > 0.5:
			for f in fol:
				if f.drop_follow == P:
					worst = maxf(worst, D.target_of(f).distance_to(Vector2(f.pos.x, f.pos.z)))
	var spread: Array = fol.map(func(x): return snappedf(Vector2(x.pos.x - P.pos.x, x.pos.z - P.pos.z).length(), 0.1))
	var dy: Array = fol.map(func(x): return snappedf(x.pos.y - P.pos.y, 0.1))
	print("DCHECK formation: worst slot error %.2fm, distance to leader %s, height difference %s (bots planning to break off at %s m)" % [worst, str(spread), str(dy), str(sep_plan)])
	if worst > 1.6 or fol.any(func(x): return x.drop_follow != P): ok = false; print("DCHECK FAIL formation")
	# pass the lead: the next squadmate leads, you follow them
	var passed := D.pass_lead(P)
	var L2: Hunter = D.leader(P.team)
	t = 0.0
	while t < 0.8 and P.dropping:
		m.step(Match.DT); t += Match.DT
	var err2 := D.target_of(P).distance_to(Vector2(P.pos.x, P.pos.z)) if P.drop_follow else 99.0
	print("DCHECK pass lead=%s: leader now %s, you follow %s (slot error %.2fm), others follow %s" % [passed, L2.pname, P.drop_follow.pname if P.drop_follow else "nobody", err2, str(fol.map(func(x): return x.drop_follow.pname if x.drop_follow else "-"))])
	if not passed or L2 == P or P.drop_follow != L2 or err2 > 2.5 or fol.any(func(x): return x != L2 and x.drop_follow != L2): ok = false; print("DCHECK FAIL pass lead")
	# separate: you steer yourself again
	var sep := D.separate(P)
	var v0 := Vector2(P.vel.x, P.vel.z)
	var want := -Vector2(L2.vel.x, L2.vel.z).normalized() if Vector2(L2.vel.x, L2.vel.z).length() > 0.5 else Vector2(-1, 0)
	var alt0 := m.player_altitude()
	t = 0.0
	while t < 0.7 and P.dropping:
		P.inp["move"] = want
		m.step(Match.DT); t += Match.DT
	var v1 := Vector2(P.vel.x, P.vel.z)
	print("DCHECK separate=%s at %.1fm up: solo=%s follow=%s, velocity %s -> %s (steering %s)" % [sep, alt0, P.drop_solo, P.drop_follow, str(v0.snapped(Vector2(0.1, 0.1))), str(v1.snapped(Vector2(0.1, 0.1))), str(want.snapped(Vector2(0.01, 0.01)))])
	if not sep or P.drop_follow != null or not P.drop_solo or v1.normalized().dot(want) < 0.7: ok = false; print("DCHECK FAIL separate")
	# everyone lands
	t = 0.0
	while t < 20.0 and m.hunters.any(func(x): return x.dropping or x.riding):
		m.step(Match.DT); t += Match.DT
	print("DCHECK landed after %.1fs more; squad on ground %s" % [t, str(m.hunters.filter(func(x): return x.team == P.team).map(func(x): return [x.pname, x.grounded, x.pos.snapped(Vector3(1, 1, 1))]))])
	if m.hunters.any(func(x): return x.dropping or x.riding): ok = false; print("DCHECK FAIL someone never landed")
	# the spawns: the same candidates every match, a different live subset per seed
	var layout := World.load_layout("skyreach")
	var subsets := {}
	for sd in [4101, 4102, 4103]:
		var plan := SpawnPlan.new(m)
		plan.build(layout)
		plan.roll(sd)
		subsets[sd] = plan.active_ids()
	print("DCHECK candidates %s; live by seed: %s" % [str(sp.shown_cats().map(func(cc): return "%s %d/%d" % [cc, sp.active_of(cc).size(), sp.of(cc).size()])), str(subsets)])
	if subsets[4101] != sp.active_ids(): ok = false; print("DCHECK FAIL the same seed rolled differently")
	if subsets[4101] == subsets[4102] and subsets[4102] == subsets[4103]: ok = false; print("DCHECK FAIL seeds roll the same spawns")
	# rare kin only at the live rare-kin points, one at each
	var rare: Array = m.kins.filter(func(k): return k.has_meta("rare"))
	var live: Array = sp.active_of("rare_kin")
	var stray := 0
	for k in rare:
		var near := false
		for cnd in live:
			if Vector2(k.home.x - cnd["pos"].x, k.home.z - cnd["pos"].z).length() < 3.0: near = true
		if not near: stray += 1
	var at_dead := 0
	for cnd in sp.of("rare_kin"):
		if cnd["active"]: continue
		for k in rare:
			if Vector2(k.home.x - cnd["pos"].x, k.home.z - cnd["pos"].z).length() < 3.0: at_dead += 1
	print("DCHECK rare kin: %d spawned for %d live points (%d strays, %d at points not rolled)" % [rare.size(), live.size(), stray, at_dead])
	if rare.size() != live.size() or stray > 0 or at_dead > 0: ok = false; print("DCHECK FAIL rare kin spawns")
	# scouting: walk the player to an unrolled candidate and its state turns from "?" to empty
	var hidden: Array = sp.cands.filter(func(cc): return not sp.cats[cc["cat"]].get("announce", false) and not cc["active"])
	if not hidden.is_empty():
		var hc: Dictionary = hidden[0]
		var before := sp.state_for(hc, P.team)
		P.teleport(hc["pos"] + Vector3(1.5, 0, 0))
		for i in 30: m.step(Match.DT)
		print("DCHECK scouting %s: %s -> %s" % [hc["id"], before, sp.state_for(hc, P.team)])
		if before != "unknown" or sp.state_for(hc, P.team) != "empty": ok = false; print("DCHECK FAIL scouting")
	m.over = true
	print("DCHECK ", "PASS" if ok else "FAIL")
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
	var until := 1e9
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--kill-at="): kill_at = float(a.substr(10))
		if a.begins_with("--sim-until="): until = float(a.substr(12))
	print("SIMTEST seed ", m.seed_val)
	while not m.over and m.time < m.length + 5.0 and m.time < until:
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
			if "--stuck-debug" in OS.get_cmdline_user_args():
				var W: World = m.world
				var tiles := []
				for dz in range(-1, 2):
					for dx in range(-1, 2):
						var ti := W.idx(int(P.pos.x) + dx, int(P.pos.z) + dz)
						tiles.append("%d/%d%s" % [W.kind[ti], W.level[ti], "w" if W.walls.has(ti) else ""])
				print("  STUCK? vel=%s pad=%s grap=%d stun=%.1f root=%.1f base=%.1f drop=%s ride=%s glide=%s roll=%.2f cross=%s tiles=%s hist=%s" % [P.vel.snapped(Vector3(0.1,0.1,0.1)), str(P.pad.keys()), P.grap.size(), P.stun_t, P.root_t, P.base_t, P.dropping, P.riding, P.gliding, P.roll_t, str(P.ai.get("cross", {}).get("take", "")), str(tiles), str(P.get_meta("hist", []).slice(-3))])
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
