extends RefCounted
## --kinbox-check: the farm cap and the Kin Burrow (KinBox), where new kin go, moving, sorting and
## releasing, boxed kin sleeping through time away, an old crowded save moving its overflow into
## the box, rare mutations passing to eggs at the right rates, wild mutation odds, their perks and
## their look, and the home island only putting farm kin out. Never touches the real save.

var bad := 0
var main: Node

func ok(cond: bool, what: String) -> void:
	print("KINBOX %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond: bad += 1

func _kin(sp: String, nm: String, trust := 40.0, lvl := 3) -> Dictionary:
	var r := Save.new_kin(sp, nm)
	r["trust"] = trust; r["level"] = lvl
	return r

func run(m: Node) -> void:
	main = m
	Save.no_write = true
	Save.d = Save.fresh()
	Econ.ensure()
	KinBox.ensure()
	var sps: Array = []
	for k in Data.KIN:
		if not Data.KIN[k].get("rare", false): sps.append(k)
	# ---------------------------------------------------------------- 1. where new kin go
	var st := _kin(sps[0], "Starter", 60.0, 5)
	st["starter"] = true
	Save.d["roster"] = [st]; Save.d["active"] = st["uid"]
	var add := func(r: Dictionary) -> String:
		Save.d["roster"].append(r)
		return KinBox.route_new(r)
	ok(add.call(_kin(sps[1], "Two")) == "farm", "a new kind goes to the farm")
	var dup := _kin(sps[0], "Dupe")
	ok(add.call(dup) == "box" and KinBox.is_boxed(dup), "a plain repeat of a kind already on the farm goes to the Kin Burrow")
	var dup_s := _kin(sps[0], "Shiny"); dup_s["shimmer"] = true
	ok(add.call(dup_s) == "farm", "a shimmering repeat goes to the farm")
	var dup_m := _kin(sps[1], "Big"); dup_m["mutations"] = ["giant"]
	ok(add.call(dup_m) == "farm", "a mutated (Giant) repeat goes to the farm")
	# fill the farm with new kinds, then one more of a new kind has to go in the box
	var i := 2
	while KinBox.farm().size() < KinBox.farm_cap():
		add.call(_kin(sps[i % sps.size()], "Fill%d" % i, 30.0 + i))
		i += 1
	ok(KinBox.farm().size() == KinBox.FARM_CAPS[0], "farm holds %d to start (%d out)" % [KinBox.FARM_CAPS[0], KinBox.farm().size()])
	var over := _kin(sps[3 % sps.size()], "Over"); over["shimmer"] = true
	ok(add.call(over) == "box" and KinBox.farm().size() == KinBox.farm_cap(), "the farm is full: even a shimmer waits in the box (cap respected)")
	# through the real results path: a caught kin's destination is on the record
	var caught := _kin(sps[0], "Caught")
	var res := Game.apply_result({"extracted": true, "caught": [caught], "tier": 0, "gems": 0, "kin_runs": []})
	var got: Dictionary = (res.get("caught", []) as Array)[0] if not (res.get("caught", []) as Array).is_empty() else {}
	ok(not got.is_empty() and KinBox.is_boxed(got) and String(got.get("went", "")) == "box", "caught on an expedition: a repeat lands in the box (%s)" % KinBox.went_text(got))
	Care.dex_sync()
	ok((Save.d["dex"][sps[1]]["mutations"] as Array).has("giant"), "the Kindex records a Giant %s" % Data.KIN[sps[1]]["name"])
	# ---------------------------------------------------------------- 2. moving, sorting, releasing
	ok(KinBox.to_farm(dup) != "", "can't bring one out onto a full farm: \"%s\"" % KinBox.to_farm(dup))
	ok(KinBox.to_box(st) != "", "the partner/starter stays on the farm: \"%s\"" % KinBox.to_box(st))
	var two: Dictionary = KinBox.farm().filter(func(r): return r["name"] == "Two")[0]
	Save.d["active"] = two["uid"]
	ok(KinBox.to_box(two) != "" and KinBox.to_box(st) != "", "partner can't be boxed, nor the starter")
	Save.d["active"] = st["uid"]
	ok(KinBox.swap(two, dup) == "" and KinBox.is_boxed(two) and not KinBox.is_boxed(dup) and KinBox.farm().size() == KinBox.farm_cap(), "swap: a boxed kin and a farm kin trade places")
	var s0 := int(two["box_slot"])
	ok(KinBox.to_box(two, 45) == "" and int(two["box_slot"]) == 45 and KinBox.page_of(two) == 1, "move inside the box to page 2, cell 16")
	var occupant := KinBox.at(s0)
	ok(KinBox.at(s0).is_empty() or occupant != two, "its old cell is free")
	ok(KinBox.to_box(over, 45) == "" and int(over["box_slot"]) == 45 and int(two["box_slot"]) != 45, "drop onto a full cell: they swap cells")
	for j in 12:
		var r := _kin(sps[j % sps.size()], "Box%d" % j, 20.0 + j, 1 + (j * 7) % 13)
		Save.d["roster"].append(r)
		KinBox.to_box(r)
	KinBox.sort_all("level")
	var lv_ok := true
	var bx := KinBox.sorted(KinBox.boxed(), "slot")
	for j in range(1, bx.size()):
		if int(bx[j]["level"]) > int(bx[j - 1]["level"]): lv_ok = false
	ok(lv_ok and int(bx[0]["box_slot"]) == 0 and int(bx[bx.size() - 1]["box_slot"]) == bx.size() - 1, "sort all by level: highest first, packed from cell 0 (%d boxed)" % bx.size())
	KinBox.sort_page(0, "name")
	var p0 := KinBox.sorted(KinBox.page_kin(0), "slot").map(func(r): return String(r["name"]).to_lower())
	var p0s := p0.duplicate(); p0s.sort()
	ok(p0 == p0s, "sort a page by name")
	var rar := KinBox.sorted(Save.d["roster"] as Array, "rarity")
	ok(Mutations.special(rar[0]), "rarity sort puts a shimmer or mutated kin first (%s)" % rar[0]["name"])
	ok(KinBox.matches(dup_m, "big", "all") and KinBox.matches(dup_m, "", "giant") and not KinBox.matches(dup, "", "mutated") and KinBox.matches(dup_s, "", "shimmer"), "search by name, filter by mutation / shimmer")
	var n0 := (Save.d["roster"] as Array).size()
	var victim: Dictionary = KinBox.boxed()[0]
	ok(KinBox.release(victim) == "" and (Save.d["roster"] as Array).size() == n0 - 1 and Save.kin(String(victim["uid"])).is_empty(), "release a boxed kin")
	ok(KinBox.release(st) != "", "can't release your starter/partner")
	# a boxed second kin taken on an expedition comes out, swapping with a farm kin if it must
	var second: Dictionary = KinBox.boxed()[0]
	Save.d["active2"] = second["uid"]
	var went := KinBox.bring_out(second)
	ok(not KinBox.is_boxed(second) and not went.is_empty() and KinBox.is_boxed(went) and KinBox.farm().size() == KinBox.farm_cap(), "a boxed kin picked for an expedition comes out (%s went in to make room)" % went.get("name", "-"))
	# expanding the cottages
	Save.d["gems"] = 5000
	ok(KinBox.expand() == "" and KinBox.farm_cap() == 8 and KinBox.expand() == "" and KinBox.expand() == "" and KinBox.farm_cap() == 12 and KinBox.expand() != "", "Kin Cottage expansions: 6 -> 8 -> 10 -> 12, then no more (%d gems left)" % int(Save.d["gems"]))
	Save.d["farm_lvl"] = 0
	# ---------------------------------------------------------------- 3. boxed kin sleep through time away
	var now := Time.get_unix_time_from_system()
	var sleeper: Dictionary = KinBox.boxed()[0]
	var awake: Dictionary = KinBox.farm().filter(func(r): return KinBox.pinned(r) == "")[0]
	Save.d["feeders"] = []
	for r in [sleeper, awake]:
		Care.ensure(r)
		r["needs"] = {"food": 50.0, "energy": 50.0, "joy": 50.0, "clean": 50.0}
		r.erase("starve")
		r["needs_t"] = now - 4.0 * 86400.0
	var ev := Econ.catch_up_all()
	ok(is_equal_approx(Care.need(sleeper, "food"), 50.0) and is_equal_approx(Care.need(sleeper, "joy"), 50.0) and Care.starve_h(sleeper) == 0.0 and not ev.any(func(e): return e["rec"] == sleeper), "4 days away: a boxed kin's needs are frozen (food %d, starving %.0fh)" % [int(Care.need(sleeper, "food")), Care.starve_h(sleeper)])
	ok(Care.need(awake, "food") < 50.0, "... while a farm kin got hungry (food %d, starving %.0fh)" % [int(Care.need(awake, "food")), Care.starve_h(awake)])
	Care.tick(sleeper, 3600.0)
	ok(is_equal_approx(Care.need(sleeper, "food"), 50.0), "an hour's tick doesn't touch a boxed kin")
	# ---------------------------------------------------------------- 4. an old crowded save
	var old := Save.fresh()
	old.erase("box_v"); old.erase("farm_lvl"); old.erase("box")
	var ros: Array = []
	for j in 11:
		var r := _kin(sps[j % sps.size()], "Old%d" % j, 10.0 + j * 7.0, 1 + j)
		r.erase("got_t")
		ros.append(r)
	ros[3]["trust"] = 1.0; ros[3]["level"] = 1      # a weak partner still stays out
	old["roster"] = ros
	old["active"] = ros[3]["uid"]
	Save.d = old
	var moved := KinBox.ensure()
	var farm := KinBox.farm()
	var kept_names: Array = farm.map(func(r): return String(r["name"]))
	var best_out := true
	var min_farm := 1e9
	for r in farm:
		if KinBox.pinned(r) == "": min_farm = minf(min_farm, float(r["trust"]) + float(r["level"]) * 4.0)
	for r in KinBox.boxed():
		if float(r["trust"]) + float(r["level"]) * 4.0 > min_farm: best_out = false
	ok(moved == 5 and farm.size() == 6 and KinBox.boxed().size() == 5 and int(Save.d.get("box_notice", 0)) == 5, "old save with 11 kin: 6 stay out, 5 boxed, one notice (%s)" % ", ".join(kept_names))
	ok(not KinBox.is_boxed(ros[3]) and ros[0].get("starter", false) and not KinBox.is_boxed(ros[0]) and best_out, "the partner and the first kin stay out, then the most trusted / highest level")
	ok(KinBox.ensure() == 0 and KinBox.farm().size() == 6, "migration only happens once")
	# ---------------------------------------------------------------- 5. inheritance
	var rng := RandomNumberGenerator.new(); rng.seed = 4242
	var a := _kin(sps[0], "Ma"); var b := _kin(sps[1], "Pa")
	var N := 20000
	var cnt := func(pa: Dictionary, pb: Dictionary, id: String) -> float:
		var hits := 0
		for _j in N:
			if Mutations.inherit(pa, pb, rng).has(id): hits += 1
		return float(hits) / N
	var r0: float = cnt.call(a, b, "glowing")
	a["mutations"] = ["glowing"]
	var r1: float = cnt.call(a, b, "glowing")
	b["mutations"] = ["glowing"]
	var r2: float = cnt.call(a, b, "glowing")
	var base := 1.0 / float(Mutations.info("glowing")["rarity"])
	print("KINBOX  Glowing in eggs over %d: no parent %.4f (base %.4f), one parent %.3f, both %.3f" % [N, r0, base, r1, r2])
	ok(absf(r0 - base) < 0.004, "no Glowing parent: eggs glow at base odds (1 in %d)" % int(Mutations.info("glowing")["rarity"]))
	ok(absf(r1 - 0.35) < 0.02, "one Glowing parent: about 35%% of eggs (%.1f%%)" % (r1 * 100.0))
	ok(absf(r2 - 0.60) < 0.02, "both parents Glowing: about 60%% of eggs (%.1f%%)" % (r2 * 100.0))
	a["mutations"] = ["giant"]; b["mutations"] = ["tiny"]
	var both_size := 0; var any_size := 0
	for _j in 4000:
		var mm := Mutations.inherit(a, b, rng)
		if mm.has("giant") and mm.has("tiny"): both_size += 1
		if mm.has("giant") or mm.has("tiny"): any_size += 1
	ok(both_size == 0 and any_size > 1200, "a Giant and a Tiny parent never make a Giant Tiny egg (%d of 4000 got one size)" % any_size)
	# shimmers, through the real breeding (traits, evolution and all)
	a.erase("mutations"); b.erase("mutations")
	var sh := [0, 0, 0]
	var M := 3000
	Save.d["roster"] = [a, b]
	for cs in 3:
		a["shimmer"] = cs >= 1; b["shimmer"] = cs >= 2
		for _j in M:
			if Care.breed(a, b, rng).get("shimmer", false): sh[cs] += 1
	var expd := [Mutations.SHIMMER_EGG, Mutations.SHIMMER_EGG + Mutations.SHIMMER_PARENT, Mutations.SHIMMER_EGG + 2.0 * Mutations.SHIMMER_PARENT]
	print("KINBOX  shimmering eggs over %d each: none %.3f (%.3f), one %.3f (%.3f), both %.3f (%.3f)" % [M, sh[0] / float(M), expd[0], sh[1] / float(M), expd[1], sh[2] / float(M), expd[2]])
	ok(absf(sh[0] / float(M) - expd[0]) < 0.02 and absf(sh[1] / float(M) - expd[1]) < 0.03 and absf(sh[2] / float(M) - expd[2]) < 0.03, "shimmer inheritance: 1 in 16, ~31% with one shimmering parent, ~56% with two")
	a["shimmer"] = false; b["shimmer"] = false
	a["mutations"] = ["crystal"]
	var cb := 0
	for _j in M:
		if Mutations.has(Care.breed(a, b, rng), "crystal"): cb += 1
	ok(absf(cb / float(M) - 0.35) < 0.03, "Care.breed passes a parent's Crystal on %.1f%% of the time" % (cb * 100.0 / M))
	# ---------------------------------------------------------------- 6. wild odds
	var expect_any := func(mult: float) -> float:
		var p_none := 1.0
		for mrow in Mutations.all(): p_none *= 1.0 - minf(1.0, mult / float(mrow["rarity"]))
		return 1.0 - p_none
	var W := 40000
	var line: Array = []
	for t in [0, 1, 2]:
		var hit := 0
		for _j in W:
			var wr := {}
			Mutations.roll_wild(wr, rng, t)
			if wr.has("mutations"): hit += 1
		var e: float = expect_any.call(float(Mutations.TIER_MULT[t]))
		line.append("tier %d %.2f%% (expect ~%.2f%%)" % [t, hit * 100.0 / W, e * 100.0])
		ok(absf(hit / float(W) - e) < e * 0.15 + 0.002, "wild kin mutated in tier %d: %.2f%%" % [t, hit * 100.0 / W])
	var rh := 0
	for _j in W / 4:
		var wr := {}
		Mutations.roll_wild(wr, rng, 0, true)
		if wr.has("mutations"): rh += 1
	var er: float = expect_any.call(Mutations.RARE_SPOT_MULT)
	print("KINBOX  wild mutation odds: %s; rare spawn point %.1f%% (expect ~%.1f%%)" % [", ".join(line), rh * 400.0 / W, er * 100.0])
	ok(absf(rh * 4.0 / W - er) < er * 0.15, "rare spawn points: %.1f%% mutated" % (rh * 400.0 / W))
	# the real wild spawner, a few matches' worth
	var seen := 0; var mutd := 0
	for sd in 1:
		var mt := Match.new()
		main.add_child(mt)
		mt.start({"teams": 2, "squad": 1, "tier": 2, "length": 1e9, "seed": 300 + sd, "no_drop": true})
		mt.set_process(false)
		for k in mt.kins:
			if k.is_wild():
				seen += 1
				if not Mutations.of(k.rec).is_empty(): mutd += 1
		mt.queue_free()
		await main.get_tree().process_frame
	ok(seen > 0, "real matches spawn wild kin with the mutation roll (%d wild, %d mutated)" % [seen, mutd])
	# ---------------------------------------------------------------- 7. perks and looks
	var g := _kin(sps[0], "Big"); g["mutations"] = ["giant"]
	var em := Evo.mods(g)
	ok(is_equal_approx(em["hp"], 1.12) and is_equal_approx(em["speed"], 0.93), "Giant: +12%% health, -7%% speed (%s)" % str(em))
	var c := _kin(sps[0], "Gem"); c["mutations"] = ["crystal", "glowing"]
	ok(Mutations.owner_stat(c, "armor") == 6.0 and is_equal_approx(Mutations.owner_stat(c, "sight"), 0.08), "Crystal gives its hunter +6 armor, Glowing +8% sight")
	var all_ok := true
	for row in Mutations.all():
		var mm := Mutations.mods({"mutations": [row["id"]]})
		for k in mm:
			if float(mm[k]) < Mutations.MULT_MIN or float(mm[k]) > Mutations.MULT_MAX: all_ok = false
	ok(all_ok and Mutations.all().size() >= 8, "%d mutations in content/mutations, every perk within %d%%" % [Mutations.all().size(), int((Mutations.MULT_MAX - 1.0) * 100.0)])
	var plain := Models.kin(sps[0], _kin(sps[0], "Plain"))
	var giant := Models.kin(sps[0], g)
	var tiny_r := _kin(sps[0], "Wee"); tiny_r["mutations"] = ["tiny"]
	var tiny := Models.kin(sps[0], tiny_r)
	ok(giant.scale.x > plain.scale.x * 1.25 and tiny.scale.x < plain.scale.x * 0.75, "Giant and Tiny change the model's size (%.2f / %.2f / %.2f)" % [tiny.scale.x, plain.scale.x, giant.scale.x])
	var alb := _kin(sps[0], "Snow"); alb["mutations"] = ["albino"]
	var am := Models.kin(sps[0], alb)
	var ac: Color = ((am.get_meta("mats") as Array)[0] as ShaderMaterial).get_shader_parameter("albedo")
	ok(ac.get_luminance() > 0.75, "Albino is pale (body luminance %.2f)" % ac.get_luminance())
	var parts_ok := true
	for pid in [["crystal", "Crystal0"], ["starmarked", "Star0"], ["twintail", "TwinTip1"], ["glowing", "GlowBand0"], ["piebald", "Patch0"]]:
		var pr := _kin(sps[1], "P"); pr["mutations"] = [pid[0]]
		var pm := Models.kin(sps[1], pr)
		if pm.find_child(String(pid[1]), true, false) == null: parts_ok = false; print("KINBOX  missing part ", pid)
		pm.free()
	ok(parts_ok, "Crystal, Starmarked, Twin-tail, Glowing and Piebald add their parts")
	for n in [plain, giant, tiny, am]: n.free()
	# ---------------------------------------------------------------- 8. the home island only puts farm kin out
	Save.d = Save.fresh()
	Econ.ensure()
	var hs := _kin(sps[0], "Home", 60.0, 5); hs["starter"] = true
	Save.d["roster"] = [hs]; Save.d["active"] = hs["uid"]
	Save.d["tutorial"]["home"] = true; Save.d["tutorial"]["day1_done"] = true
	for j in 9:
		var r := _kin(sps[(j + 1) % sps.size()], "H%d" % j)
		Save.d["roster"].append(r)
		KinBox.route_new(r)
	var H = load("res://scripts/home/home.gd").new()
	main.add_child(H)
	for _f in 4: await main.get_tree().process_frame
	var out_uids: Array = H.kins.map(func(k): return String(k["rec"]["uid"]))
	var boxed_out := KinBox.boxed().any(func(r): return out_uids.has(String(r["uid"])))
	ok(H.kins.size() == KinBox.farm().size() and not boxed_out and KinBox.boxed().size() == 4, "home puts the %d farm kin out; the %d in the burrow stay inside" % [H.kins.size(), KinBox.boxed().size()])
	H._open_burrow()
	for _f in 2: await main.get_tree().process_frame
	ok(H.panel_open == "Kin Burrow" and is_instance_valid(H.kinbox_view.grid) and H.kinbox_view.grid.get_child_count() == KinBox.PAGE, "the Kin Burrow screen opens with a %d-cell page" % KinBox.PAGE)
	H.kinbox_view._quick(KinBox.boxed()[0])
	ok(KinBox.boxed().size() == 4, "quick move onto a full farm is refused (still %d boxed)" % KinBox.boxed().size())
	H.kinbox_view._quick(KinBox.farm().filter(func(r): return KinBox.pinned(r) == "")[0])
	for _f in 2: await main.get_tree().process_frame
	ok(KinBox.boxed().size() == 5 and H.kins.size() == KinBox.farm().size(), "quick move a farm kin into the box: it leaves the island (%d out)" % H.kins.size())
	H.queue_free()
	print("KINBOX DONE failures: %d" % bad)
	main.get_tree().quit()
