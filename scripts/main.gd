extends Node
## Holds whichever screen is showing: home, a match, or the results.

var current: Node = null

func _ready() -> void:
	Game.main = self
	var args := OS.get_cmdline_user_args()
	var opts := {}
	for a in args:
		if a.begins_with("--seed="): opts["seed"] = int(a.substr(7))
		if a == "--god": opts["god"] = true
		if a == "--autoplay": opts["autoplay"] = true
		if a == "--glide-demo": opts["glide_demo"] = true
		if a.begins_with("--length="): opts["length"] = float(a.substr(9))
		if a == "--no-drop": opts["no_drop"] = true
		if a == "--watch-heart": opts["watch_heart"] = true
		if a.begins_with("--hero="): Save.d["hero"] = a.substr(7); Save.d["weapon"] = ""
		if a == "--ability-demo": opts["ability_demo"] = true
		if a == "--fresh": Save.d = Save.fresh()
		if a == "--skip-tutorial": Save.d["tutorial"]["home"] = true
		if a.begins_with("--teams="): opts["teams"] = int(a.substr(8))
		if a.begins_with("--tier="): opts["tier"] = int(a.substr(7))
		if a.begins_with("--squad="): opts["squad"] = int(a.substr(8))
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
	if "--mapcheck" in args:
		var MC = load("res://tools/mapcheck.gd")
		MC.new().run(range(1, 201))
		get_tree().quit()
		return
	if "--simtest" in args:
		_simtest(opts)
		return
	if OS.has_feature("web"):
		_expose_test_hooks()
		var hash := str(JavaScriptBridge.eval("location.hash", true))
		if hash.contains("online"):
			Save.d["tutorial"]["home"] = true
			show_screen("lobby", {})
			return
	if "--results-test" in args:
		show_screen("results", {"extracted": true, "gems": 42, "seeds": {"sunroot": 1}, "caught": [Save.new_kin("zapple")], "knocks": 3, "damage": 512, "time": 201.0, "kin_events": [{"kind": "refused", "text": "refused to jump into a fight that looked too dangerous", "trust": -1.0}], "kin_trust": 57.0, "tonics": 1})
		return
	if "--lobby-test" in args:
		show_screen("lobby", {})
		return
	if "--match" in args:
		show_screen("match", opts)
	elif "--tutorial" in args:
		show_screen("match", {"tutorial": true, "teams": 1, "squad": 1, "tier": 0, "length": 1500.0, "tut_test": "--tut-test" in args})
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

func show_screen(screen: String, opts: Dictionary) -> void:
	if current:
		current.queue_free()
		current = null
	await get_tree().process_frame
	match screen:
		"match":
			var m := Match.new()
			m.name = "Match"
			add_child(m)
			current = m
			m.start(opts)
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
		"hatch":
			var Hx = load("res://scripts/ui/hatch.gd")
			current = Hx.new()
			add_child(current)
		"home":
			var H = load("res://scripts/home/home.gd")
			current = H.new()
			add_child(current)

## Headless check: a whole match with the player on autopilot, stepped as fast as possible.
func _simtest(opts: Dictionary) -> void:
	opts["autoplay"] = true
	var m := Match.new()
	add_child(m)
	m.start(opts)
	m.set_process(false)
	var t0 := Time.get_ticks_msec()
	var log_t := 0.0
	while not m.over and m.time < m.length + 5.0:
		m.step(Match.DT)
		if m.result.get("ending", false) and m.time > 0.0:
			m._finish_now = true
		log_t += Match.DT
		if log_t >= 30.0:
			log_t = 0.0
			var alive := m.hunters.filter(func(x): return not x.out and not x.extracted).size()
			var down := m.hunters.filter(func(x): return x.downed).size()
			var P: Hunter = m.player
			print("  island=", m.world.island_of(P.pos.x, P.pos.z), " pads=", m.world.pads.map(func(pd): return "%d>%d@(%d,%d)" % [pd["from"], pd["to"], pd["pos"].x, pd["pos"].z]))
			print("  player pos=%s goal=%s kind=%s tgt=%s move=%s grounded=%s" % [P.pos.snapped(Vector3(0.1,0.1,0.1)), str(P.ai.get("goal")), P.ai.get("goal_kind"), str(P.ai.get("tgt")), str(P.inp["move"]), P.grounded])
			print("t=%d alive=%d down=%d mobs=%d shots=%d pickups=%d feed=%s" % [m.time, alive, down, m.mobs.filter(func(x): return not x.dead).size(), m.shots.size(), m.pickups.size(), str(m.feed.map(func(f): return f["text"]))])
		if m.result.get("ending", false):
			break
	for line in m.feed_all:
		print("   | ", line)
	if m.player:
		var isl := m.world.island_of(m.player.pos.x, m.player.pos.z)
		print("player island ", isl, " pads out: ", m.world.pads.filter(func(pd): return pd["from"] == isl).map(func(pd): return [pd["pos"], pd["to"], pd["land"]]))
	print("SIMTEST done in %dms, sim time %d, result %s" % [Time.get_ticks_msec() - t0, m.time, str(m.result)])
	for h in m.hunters:
		print("  %s team %d %s knocks %d kills %d dmg %d gems %d %s" % [h.pname, h.team, h.cls, h.knocks, h.kills, h.dmg_done, h.gems, "OUT" if h.out else ("EXTRACTED" if h.extracted else "alive")])
	get_tree().quit()

# ------------------------------------------------------------------ browser test hooks
var _cmd_cb = null

## window.kinGameCmd("ready" | "start" | "state" | "move:x,z" | "fire:x,z" | "god") for automated browser tests.
## Results land in window.kinGameOut as JSON.
func _expose_test_hooks() -> void:
	_cmd_cb = JavaScriptBridge.create_callback(func(a): _cmd(str(a[0])))
	JavaScriptBridge.get_interface("window").kinGameCmd = _cmd_cb

func _cmd(c: String) -> void:
	var out := {}
	var current = screen_node()
	if current and current.has_method("_toggle_ready") and c == "ready":
		current._toggle_ready()
	elif current and current.has_method("_start") and c == "start":
		current._start()
	elif current is Match:
		var m: Match = current
		if c == "state":
			out = {"time": m.time, "host": m.is_host, "me": Net.me, "hunters": m.hunters.map(func(h): return [h.nid, h.pname, h.team, snappedf(h.hp, 0.1), h.remote, h.downed, h.out, h.pos.snapped(Vector3(0.1, 0.1, 0.1))]),
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
