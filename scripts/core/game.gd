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
	_key("throw", [KEY_C])                    # throw your kin, or call it back
	_key("kin_skill", [KEY_Q])                # your kin's skill at the cursor
	_key("signature", [KEY_E])                # class signature
	_key("interact", [KEY_F])                 # catch, revive, open
	_key("dash", [KEY_SHIFT])
	_key("jump", [KEY_SPACE])
	_key("reload", [])                        # reloading is automatic
	_key("ultimate", [KEY_R])                 # hero ultimate
	_key("tonic", [KEY_1])
	_key("scores", [KEY_TAB])
	_key("menu", [KEY_ESCAPE])
	_key("play", [KEY_G])                     # at home: play fetch with a kin
	_key("talk", [KEY_T])                     # at home: talk to a kin
	_key("details", [KEY_C])                  # at home: a kin's details
	_key("inventory", [KEY_I])                # your things

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
			var nk: Dictionary = rec.duplicate(true)
			nk["uid"] = "k%d%d" % [Time.get_ticks_usec() % 1000000, randi() % 1000]
			nk["name"] = Data.KIN_NAMES.pick_random()
			nk["memory"] = []
			Save.remember(nk, "caught", "was caught by you in the islands and brought home")
			Care.ensure(nk)
			nk["needs"] = {"food": 45.0, "energy": 40.0, "joy": 45.0, "clean": 30.0}
			d["roster"].append(nk)
			Care.dex_mark(nk["species"], "caught")
			if nk.get("shimmer", false): Care.dex_mark(nk["species"], "shimmer")
			out["caught"].append(nk)
	d["items"]["tonic"] = int(r.get("tonics", d["items"].get("tonic", 0)))
	var treat: String = d.get("treat", "")
	d["treat"] = ""
	# the partner kin remembers the match
	var k := Save.active_kin()
	if not k.is_empty():
		k["matches"] = int(k.get("matches", 0)) + 1
		var before := float(k["trust"])
		var counts := {}
		for e in r.get("kin_events", []):
			counts[e["kind"]] = int(counts.get(e["kind"], 0)) + 1
		k["trust"] = clampf(float(r.get("kin_trust", before)) + (1.0 if d.get("guild_perks", []).has("shrine") else 0.0), 0.0, 100.0)
		for kind in counts:
			var ev: Dictionary = {}
			for e in r["kin_events"]:
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
		Evo.learn(k, r.get("kin_stats", {}))
		# an expedition is hungry, tiring, muddy work
		Care.catch_up(k)
		for nd in Care.MATCH_COST:
			Care.change(k, nd, Care.MATCH_COST[nd])
		Care.change(k, "joy", 8.0 if won else -8.0)
		var xp := 40 + (40 if won else 0) + int(r.get("knocks", 0)) * 10
		if treat == "treat_xp": xp = int(xp * 1.5)
		k["xp"] = int(k.get("xp", 0)) + xp
		while int(k["xp"]) >= 100 * int(k["level"]):
			k["xp"] = int(k["xp"]) - 100 * int(k["level"])
			k["level"] = int(k["level"]) + 1
			out["levelup"] = true
			_evolve(k, out)
		out["trust_delta"] = float(k["trust"]) - before
		out["kin"] = k
		# in the Hollow, a partner that doesn't trust you enough stays behind when you fall
		var td: Dictionary = Data.TIERS[clampi(int(r.get("tier", last_tier)), 0, Data.TIERS.size() - 1)]
		if td["risk_kin"] and not won and r.get("why", "") != "left":
			if float(k["trust"]) >= 80.0:
				Save.remember(k, "found_home", "found its own way home from the Hollow after you fell", 2.0)
				out["kin_home"] = true
			elif d["roster"].size() > 1:
				d["roster"].erase(k)
				d["active"] = d["roster"][0]["uid"]
				out["kin_lost"] = k
			else:
				Save.remember(k, "stranded", "was stranded in the Hollow for a long time before limping home", -15.0)
				out["kin_stranded"] = true
	# the vault keeps a third of what you were carrying when you go down
	if not won and Save.has_building("vault") and int(r.get("lost_gems", 0)) > 0:
		out["vault_gems"] = int(r["lost_gems"]) / 3
		d["gems"] = int(d["gems"]) + out["vault_gems"]
	# kin who stayed home rest in the cottages and train in the yard
	var rest := (2.0 if Save.has_building("cottage") else 0.0) + (2.0 if Save.has_building("cottage2") else 0.0)
	for hk in d["roster"]:
		if hk == k or out["caught"].has(hk):
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
				p["care"] = int(p.get("care", 0)) + 1
				p["wt"] = 0.0
			if int(p["stage"]) == grow:
				out["crops_ready"] += 1
	Save.save_game()
	return out

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
