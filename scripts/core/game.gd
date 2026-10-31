extends Node
## Global glue: input actions, screen switching between home and matches, shared settings.

signal screen_changed(name: String)

var main: Node = null          # set by main.gd
var last_result: Dictionary = {}
var match_opts: Dictionary = {}
var god := false               # admin god mode (Overlay's admin tools)

func _ready() -> void:
	# symbols the text fonts lack (checkmarks, hearts, stars) come from a small fallback font
	var sym: Font = load("res://fonts/Symbols.ttf")
	for f in ["res://fonts/Rubik.ttf", "res://fonts/LilitaOne-Regular.ttf"]:
		var ff: FontFile = load(f)
		if ff and not ff.fallbacks.has(sym):
			ff.fallbacks = ff.fallbacks + [sym]
	_setup_input()
	RenderingServer.set_default_clear_color(Color("10131f"))
	Settings.apply_all()
	Settings.changed.connect(func(k: String):
		if k == "mod_mode": apply_mod())
	if modding():
		god = true

## Mod mode (Settings > Gameplay, for the game's owner): everything unlocked, building and
## bridges are free and need no expeditions, kin can be spawned from the admin tools (F1).
func modding() -> bool:
	return bool(Settings.get_v("mod_mode")) and Overlay.admin_allowed()

func apply_mod() -> void:
	god = modding()
	if not modding() or Save.d.is_empty():
		return
	Save.d["gems"] = maxi(int(Save.d["gems"]), 99999)
	Save.d["extracts"] = maxi(int(Save.d.get("extracts", 0)), 10)
	for s in Data.CROPS:
		if int(Save.d.get("seeds", {}).get(s, 0)) < 10: Save.add_seed(s, 10)
	if not Save.d.has("accs"): Save.d["accs"] = []
	for a in Data.ACCS:
		if not Save.d["accs"].has(a): Save.d["accs"].append(a)
	Save.add_item("tonic", 10)
	Save.save_game()
	var s = main.screen_node() if main else null
	if s and s.has_method("_refresh_top"):
		s._refresh_top()

func _key(action: String, keys: Array, mouse := -1) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	if mouse >= 0:
		var m := InputEventMouseButton.new()
		m.button_index = mouse
		InputMap.action_add_event(action, m)

func _setup_input() -> void:
	_key("up", [KEY_W, KEY_UP]); _key("down", [KEY_S, KEY_DOWN])
	_key("left", [KEY_A, KEY_LEFT]); _key("right", [KEY_D, KEY_RIGHT])
	_key("fire", [], MOUSE_BUTTON_LEFT)
	_key("secondary", [], MOUSE_BUTTON_RIGHT) # your hero's right-click ability
	# match keys (one short kit, like Supervive): LMB weapon, RMB weapon ability, Shift dash, Space
	# jump and glide (Mouse 5 glides too), Q your active glove, E your kin's ability,
	# C or middle mouse throw / recall your kin, R the bond ultimate, 1 heal, F interact, Ctrl sneak.
	_key("signature", [KEY_E])                # your kin's ability
	_key("kin_skill", [])                     # a kin's second ability: retired from the kit (data kept)
	_key("interact", [KEY_F])                 # catch, open, pick up, finish a downed enemy (Supervive: F)
	_key("armor_kit", [])                     # merged into heal (1)
	_key("gear1", [KEY_Q])                    # your active glove
	_key("gear2", [])                         # the second glove slot is passive: no key
	_key("crouch", [KEY_CTRL])                # sneak: slower, quieter, and you see further
	_key("throw", [KEY_C], MOUSE_BUTTON_MIDDLE)  # throw your kin, or call it back (C or middle mouse)
	_key("base", [KEY_B])                     # base to a teammate: a 3s channel (squads only)
	_key("swap_kin", [])                      # one kin per expedition now; kept so old code paths compile
	_key("dash", [KEY_SHIFT])
	_key("jump", [KEY_SPACE])
	_key("glide", [], MOUSE_BUTTON_XBUTTON2)  # hold Mouse 5 (the front side button) in the air to glide, like holding Space; never jumps
	_key("glide", [], MOUSE_BUTTON_XBUTTON1)  # Mouse 4 glides too (not advertised)
	_key("reload", [])                        # reloading is automatic
	_key("ultimate", [KEY_R])                 # bond ultimate, when the bond meter is full
	_key("tonic", [KEY_1])
	_key("scores", [KEY_TAB])
	_key("menu", [KEY_ESCAPE])
	_key("play", [KEY_V])                     # at home: play fetch with a kin
	_key("talk", [KEY_T])                     # at home: talk to a kin
	_key("details", [KEY_C])                  # at home: a kin's details
	_key("whistle", [KEY_H])                  # at home: whistle, and your kin come running
	_key("inventory", [KEY_I])                # your things
	_key("emote", [KEY_T])                    # in a match: hold for the emote wheel (truce, deal, no...); T talks to kin at home
	_key("map", [KEY_M])                      # in a match: the full map (ping it with the mouse)
	_key("pass_lead", [KEY_P])                # riding in / dropping: pass the drop lead to a squadmate
	_key("separate", [KEY_X])                 # riding in / dropping behind the leader: break away and drop solo

func goto(screen: String, opts := {}) -> void:
	match_opts = opts
	if main:
		main.show_screen(screen, opts)
	screen_changed.emit(screen)

func start_match(opts := {}) -> void:
	last_tier = int(opts.get("tier", 0))
	goto("match", opts)

var last_tier := 0

func finish_match(r: Dictionary) -> void:
	last_result = r
	goto("results", r)

## Writes a finished match into the save: loot, caught kin, crops growing, and what your kin remembers.
## Returns a summary for the results screen.
func apply_result(r: Dictionary) -> Dictionary:
	var d := Save.d
	var out := {"gems": 0, "seeds": {}, "caught": [], "kin_lines": [], "levelup": false, "crops_ready": 0}
	d["matches"] = int(d["matches"]) + 1
	var won: bool = r.get("extracted", false)
	# lifetime counts for challenges
	var ms: Dictionary = r.get("stats", {})
	for k in ["mobs", "rings", "feathers", "staggers", "slams", "spikes"]:
		if ms.has(k): Progress.add(k, int(ms[k]))
	Progress.add("glide_s", int(float(ms.get("glide_t", 0.0))))
	Progress.add("knocks", int(r.get("knocks", 0)))
	if won: Progress.add("caught", r.get("caught", []).size())
	if won:
		d["extracts"] = int(d.get("extracts", 0)) + 1
		out["gems"] = int(r.get("gems", 0))
		if d.get("guild_perks", []).has("hall"):
			out["gems"] = int(round(out["gems"] * 1.1))
		d["gems"] = int(d["gems"]) + out["gems"]
		for s in r.get("seeds", {}):
			Save.add_seed(s, int(r["seeds"][s]))
			out["seeds"][s] = int(r["seeds"][s])
		for rec in r.get("caught", []):
			if not Ransom.find(String(rec.get("uid", ""))).is_empty():
				continue     # one of yours, back from a rival: handled below
			var nk: Dictionary = rec.duplicate(true)
			var from := String(rec.get("lost_from", ""))
			nk["uid"] = "k%d%d" % [Time.get_ticks_usec() % 1000000, randi() % 1000]
			if from == "" or from == "you":
				nk["name"] = Data.KIN_NAMES.pick_random()
				nk["memory"] = []
				nk.erase("lost_from")
				Save.remember(nk, "caught", "was caught by you in the islands and brought home")
			else:
				# a rival's kin you took home: it still misses them. One that loved its old hunter
				# (trust 80+) pines for a good while and is very slow to bond with you
				nk["memory"] = []
				nk["trust"] = 15.0
				if float(rec.get("prev_trust", 0.0)) >= 80.0:
					nk["trust"] = 5.0
					nk["pining"] = 6
					Save.remember(nk, "pining", "loved %s and won't warm to anyone else easily" % from, -5.0)
				Save.remember(nk, "taken", "belonged to %s until you took it home" % from)
			Care.ensure(nk)
			nk["needs"] = {"food": 45.0, "energy": 40.0, "joy": 45.0, "clean": 30.0}
			d["roster"].append(nk)
			Care.dex_mark(nk["species"], "caught")
			if nk.get("shimmer", false): Care.dex_mark(nk["species"], "shimmer")
			out["caught"].append(nk)
	d["items"]["tonic"] = int(r.get("tonics", d["items"].get("tonic", 0)))
	if r.has("rift_keys"):
		d["items"]["rift_key"] = int(r["rift_keys"])     # carried keys come home with you, or stay in your deathbox
	var treat: String = d.get("treat", "")
	d["treat"] = ""
	# every kin you brought remembers the match
	var runs: Array = r.get("kin_runs", [])
	if runs.is_empty() and not Save.active_kin().is_empty():
		runs = [{"uid": Save.active_kin()["uid"], "events": r.get("kin_events", []), "trust": r.get("kin_trust", Save.active_kin()["trust"]), "stats": r.get("kin_stats", {})}]
	var k := Save.active_kin()
	var brought: Array = []
	for ri in runs.size():
		var run: Dictionary = runs[ri]
		var kk := Save.kin(String(run.get("uid", "")))
		if kk.is_empty():
			continue
		brought.append(kk)
		_kin_after(kk, run, won, r, treat, out, ri == 0)
	# kin you got back from a rival come home as themselves
	for rec in r.get("caught", []).duplicate():
		if not won:
			break
		var L := Ransom.find(String(rec.get("uid", "")))
		if not L.is_empty():
			var back := Ransom.restore(L, "took it back on an expedition")
			out["rescued"] = out.get("rescued", []) + [back]
			out["caught"].erase(back)
	# time passes for kin already lost: prices drift, unclaimed ones get sold, rivals ask for theirs back
	out["ransom_news"] = Ransom.tick(r.get("rivals", []))
	# going down leaves your kin behind; where they end up was settled in the match
	var lost_news: Array = []
	if not won and r.get("why", "") != "left":
		for lk in r.get("lost_kin", []):
			var kk := Save.kin(String(lk.get("uid", "")))
			if kk.is_empty():
				continue
			var fate := String(lk.get("fate", "ransom"))
			if fate == "squad":
				Save.remember(kk, "carried_home", "was carried home by %s after you fell" % lk.get("holder", "your squad"), 1.0)
				lost_news.append({"kin": kk, "fate": "squad", "holder": lk.get("holder", "")})
				continue
			if float(kk["trust"]) >= 90.0 and randf() < 0.5:
				# soulbound kin sometimes find their own way back to you
				Save.remember(kk, "found_home", "found its own way home after you fell", 2.0)
				lost_news.append({"kin": kk, "fate": "home", "holder": ""})
				continue
			Ransom.lose(kk, fate, String(lk.get("holder", "")), int(r.get("tier", last_tier)))
			lost_news.append({"kin": kk, "fate": fate, "holder": lk.get("holder", "")})
		if d["roster"].is_empty() and not d["lost_kin"].is_empty():
			# with no kin left at all, Old Pell lets the first one go on credit
			var L: Dictionary = d["lost_kin"][0]
			var back := Ransom.restore(L, "were given it on credit by %s" % Ransom.BROKER)
			Save.remember(back, "stranded", "waited a long time before it was let go", -10.0)
			out["kin_stranded"] = true
		if Save.kin(str(d.get("active", ""))).is_empty() and d["roster"].size() > 0:
			d["active"] = d["roster"][0]["uid"]
		if Save.kin(str(d.get("active2", ""))).is_empty() and str(d.get("active2", "")) != "none":
			d["active2"] = ""
	out["lost_news"] = lost_news
	# weapons, gloves and treasure: into the armory, or lost with you
	Econ.after_raid(r, out)
	if not brought.is_empty():
		out["kin"] = brought[0]
	# the vault keeps a third of what you were carrying when you go down
	if not won and Save.has_building("vault") and int(r.get("lost_gems", 0)) > 0:
		out["vault_gems"] = int(r["lost_gems"]) / 3
		d["gems"] = int(d["gems"]) + out["vault_gems"]
	# kin who stayed home rest in the cottages and train in the yard
	var rest := (2.0 if Save.has_building("cottage") else 0.0) + (2.0 if Save.has_building("cottage2") else 0.0)
	for hk in d["roster"]:
		if hk == k or brought.has(hk) or out["caught"].has(hk):
			continue
		if rest > 0.0:
			hk["trust"] = clampf(float(hk["trust"]) + rest, 0.0, 100.0)
		if Save.has_building("dojo"):
			hk["xp"] = int(hk.get("xp", 0)) + 40
			while int(hk["xp"]) >= 100 * int(hk["level"]):
				hk["xp"] = int(hk["xp"]) - 100 * int(hk["level"])
				hk["level"] = int(hk["level"]) + 1
				_evolve(hk, out)
	# records for the trophy hall
	var stt: Dictionary = d["stats"]
	stt["kills"] = int(stt.get("kills", 0)) + int(r.get("kills", 0))
	stt["knocks"] = int(stt.get("knocks", 0)) + int(r.get("knocks", 0))
	stt["best_kills"] = maxi(int(stt.get("best_kills", 0)), int(r.get("kills", 0)))
	if won:
		stt["best_gems"] = maxi(int(stt.get("best_gems", 0)), int(r.get("gems", 0)))
		stt["caught"] = int(stt.get("caught", 0)) + r.get("caught", []).size()
	# crops grow a stage per match (two in the greenhouse); a plant you watered counts as tended
	for arr in (["plots", "gh_plots"] if Save.has_building("greenhouse") else ["plots"]):
		for p in d[arr]:
			if p["crop"] == "":
				continue
			var grow := int(Data.CROPS[p["crop"]]["grow"])
			var before_s := int(p["stage"])
			if before_s >= grow:
				continue
			p["stage"] = mini(before_s + (2 if arr == "gh_plots" else 1), grow)
			if float(p.get("wt", 0.0)) > 0.0:
				if int(p.get("wet", 2)) >= 2:     # rain-soaked only still grows, but isn't tended
					p["care"] = int(p.get("care", 0)) + 1
				p["wt"] = 0.0
				p["wet"] = 0
			if int(p["stage"]) == grow:
				out["crops_ready"] += 1
	Save.save_game()
	return out

## What one kin you brought takes from a match: memories, trust, growth, hunger and XP.
func _kin_after(k: Dictionary, run: Dictionary, won: bool, r: Dictionary, treat: String, out: Dictionary, lead: bool) -> void:
	var d := Save.d
	k["matches"] = int(k.get("matches", 0)) + 1
	if int(k.get("pining", 0)) > 0:
		k["pining"] = int(k["pining"]) - 1
	var before := float(k["trust"])
	var evs: Array = run.get("events", [])
	var counts := {}
	for e in evs:
		counts[e["kind"]] = int(counts.get(e["kind"], 0)) + 1
	k["trust"] = clampf(float(run.get("trust", before)) + (1.0 if d.get("guild_perks", []).has("shrine") else 0.0), 0.0, 100.0)
	for kind in counts:
		var ev: Dictionary = {}
		for e in evs:
			if e["kind"] == kind: ev = e; break
		var txt: String = ev["text"]
		if counts[kind] > 1:
			txt += " (%d times)" % counts[kind]
		Save.remember(k, kind, txt)
	if won:
		k["wins"] = int(k.get("wins", 0)) + 1
		Save.remember(k, "extracted", "made it out of the islands with you", 3.0)
		k["traits"]["bravery"] = clampf(float(k["traits"]["bravery"]) + 0.015, 0.05, 0.95)
	else:
		Save.remember(k, "lost", "lost a match with you (%s)" % _why(r.get("why", "")), -1.0)
	Evo.learn(k, run.get("stats", {}))
	# an expedition is hungry, tiring, muddy work
	Care.catch_up(k)
	for nd in Care.MATCH_COST:
		Care.change(k, nd, Care.MATCH_COST[nd] * (1.0 if lead else 0.7))
	Care.change(k, "joy", 8.0 if won else -8.0)
	var xp := 40 + (40 if won else 0) + int(r.get("knocks", 0)) * 10
	if not lead: xp = int(xp * 0.7)
	if treat == "treat_xp": xp = int(xp * 1.5)
	k["xp"] = int(k.get("xp", 0)) + xp
	while int(k["xp"]) >= 100 * int(k["level"]):
		k["xp"] = int(k["xp"]) - 100 * int(k["level"])
		k["level"] = int(k["level"]) + 1
		out["levelup"] = true
		_evolve(k, out)
	if lead:
		out["trust_delta"] = float(k["trust"]) - before

## A level up can bring a new form or a mutation. The home island plays it when you get back.
func _evolve(k: Dictionary, out: Dictionary) -> void:
	var ev := Evo.on_level(k)
	if ev.is_empty():
		return
	ev["text"] = Evo.describe(ev, k)
	if ev["kind"] == "form": Care.dex_mark(k["species"], "form", String(ev["to"]))
	if not k.has("pending_evo"):
		k["pending_evo"] = []
	k["pending_evo"].append(ev)
	if not out.has("evo"):
		out["evo"] = []
	out["evo"].append(ev["text"])

func _why(w: String) -> String:
	match w:
		"abyss": return "fell into the abyss"
		"team wiped", "finished": return "got knocked out"
		"bled out": return "bled out"
		"left": return "left early"
	return w
