extends Control
## After a match: what you brought home, what your kin thinks, and the way back to the farm.

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UI.theme()

func show_result(r: Dictionary) -> void:
	Sfx.play_music("title")
	Sfx.play_ambience("")
	var s := Game.apply_result(r)
	var bg := ColorRect.new(); bg.color = UI.BG; bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(bg)
	_stage(r, s)
	var center := CenterContainer.new(); center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(center)
	center.offset_left = 300.0   # leave the left side for the island
	var panel := PanelContainer.new(); panel.custom_minimum_size = Vector2(560, 0); center.add_child(panel)
	UI.pop_in(panel, 0.1)
	var v := UI.vbox(12)
	panel.add_child(UI.scroll_box(v, 70.0))
	var won: bool = r.get("extracted", false)
	v.add_child(UI.title("You made it out" if won else _lost_title(r.get("why", "")), 40, UI.TEAL if won else UI.BAD))
	v.add_child(UI.label("Everything you carried is yours now." if won else "Everything you carried is lost in the islands.", 16, UI.MUTED))
	var stats := UI.hbox(24)
	for pair in [["Knocks", r.get("knocks", 0)], ["Damage", r.get("damage", 0)], ["Time", "%d:%02d" % [int(r.get("time", 0)) / 60, int(r.get("time", 0)) % 60]]]:
		var c := UI.vbox(2)
		c.custom_minimum_size.x = 120
		var lab := UI.label(pair[0], 13, UI.MUTED)
		lab.autowrap_mode = TextServer.AUTOWRAP_OFF
		c.add_child(lab)
		c.add_child(UI.title(str(pair[1]), 26))
		stats.add_child(c)
	v.add_child(stats)
	if won:
		var loot := UI.vbox(6)
		loot.add_child(UI.section("Brought home"))
		loot.add_child(UI.label("%d gems" % s["gems"], 18, UI.GOLD))
		for sd in s["seeds"]:
			loot.add_child(UI.label("%d %s seeds" % [s["seeds"][sd], Data.CROPS[sd]["name"]], 16, Data.CROPS[sd]["color"]))
		for k in s["caught"]:
			loot.add_child(UI.label("A new kin: %s the %s" % [k["name"], Data.KIN[k["species"]]["name"]], 16, Data.KIN[k["species"]]["color"]))
		v.add_child(loot)
	if s.has("kin"):
		var k: Dictionary = s["kin"]
		var kc := UI.card()
		var kv := UI.vbox(6); kc.add_child(kv)
		var td: float = s.get("trust_delta", 0.0)
		var mood := "trusts you more" if td > 0.5 else ("trusts you less" if td < -0.5 else "feels the same about you")
		kv.add_child(UI.label("%s %s (trust %d)" % [k["name"], mood, int(k["trust"])], 17, UI.INK))
		if s["levelup"]:
			kv.add_child(UI.label("%s grew to level %d!" % [k["name"], k["level"]], 16, UI.GOLD))
		for et in s.get("evo", []):
			kv.add_child(UI.label(et, 15, Color("c9a0ff")))
		var mem: Array = k["memory"]
		for i in range(maxi(0, mem.size() - 3), mem.size()):
			kv.add_child(UI.label("Remembers: " + String(mem[i]["text"]), 14, UI.MUTED))
		v.add_child(kc)
	for back in s.get("rescued", []):
		v.add_child(UI.label("You took %s back! It's home again, and it won't forget you came for it." % back["name"], 17, UI.GOOD))
	# kin left behind when you went down, and where they ended up
	var lost_news: Array = s.get("lost_news", [])
	if not lost_news.is_empty():
		var lc := UI.card(Color(0.16, 0.07, 0.07, 0.9))
		var lv := UI.vbox(6); lc.add_child(lv)
		lv.add_child(UI.section("Left behind", Color("ffb0a0")))
		for ln in lost_news:
			var kk: Dictionary = ln["kin"]
			var txt := ""
			var col := UI.BAD
			match String(ln["fate"]):
				"squad": txt = "%s was carried home by your squadmate %s." % [kk["name"], ln["holder"]]; col = UI.GOOD
				"home": txt = "%s found its own way home. It trusts you that much." % kk["name"]; col = UI.GOOD
				"rival": txt = "%s was collected by %s. Make them an offer at the Ransom House, or find them out there and take it back." % [kk["name"], ln["holder"]]
				_: txt = "Nobody collected %s. It's waiting at the Ransom House on your farm." % kk["name"]; col = Color("ffd58a")
			var l := UI.label(txt, 15, col); l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lv.add_child(l)
		v.add_child(lc)
	for nw in s.get("ransom_news", []):
		var l := UI.label(String(nw), 14, Color("ffd58a")); l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)
	if s.get("kin_stranded", false):
		v.add_child(UI.label("With no kin left at home, %s let one of yours go on credit. It waited a long time and trusts you less now." % Ransom.BROKER, 16, UI.BAD))
	if int(s.get("vault_gems", 0)) > 0:
		v.add_child(UI.label("Your vault kept %d of the gems you dropped." % int(s["vault_gems"]), 15, UI.GOLD))
	if s["crops_ready"] > 0:
		v.add_child(UI.label("%d crop%s ready to harvest on your farm." % [s["crops_ready"], "s" if s["crops_ready"] > 1 else ""], 15, UI.GOOD))
	v.add_child(UI.spacer(6))
	if r.get("tutorial", false):
		v.add_child(UI.label("That's the basics. Now come see your home.", 16, UI.GOLD))
	v.add_child(UI.primary("Go home" if r.get("tutorial", false) else "Back to the farm", func(): Game.goto("home"), 240))

var hunter_node: Node3D
var h_anim: HunterAnim
var kin_node: Node3D
var won_k := false
var t := 0.0

## Behind the card: your hunter and kin on a little island, cheering if you made it out,
## sitting it out if you didn't.
func _stage(r: Dictionary, s: Dictionary) -> void:
	won_k = r.get("extracted", false)
	var svc := SubViewportContainer.new(); svc.stretch = true
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(svc)
	var vp := SubViewport.new(); vp.own_world_3d = true; vp.msaa_3d = Viewport.MSAA_2X
	svc.add_child(vp)
	var w3 := Node3D.new(); vp.add_child(w3)
	var env := WorldEnvironment.new(); env.environment = Look.environment({}); w3.add_child(env)
	if not won_k:
		Look.night(env.environment, 0.6)
	Look.lights(w3, Color("fff1d8") if won_k else Color("b9c4ff"), 1.05 if won_k else 0.7)
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	var isl := Models.float_island(rng, 2.6, 5.0, Color("6aa64a"), Color("9a7a5a"), Color("3a2f48"))
	w3.add_child(isl)
	var tr := Models.tree(rng, Color("5a9a4f"), "round"); tr.position = Vector3(-1.4, 0, -1.2); w3.add_child(tr)
	var rk := Models.rock(rng, 0.7); rk.position = Vector3(1.5, 0, -0.9); w3.add_child(rk)
	hunter_node = Models.hunter(Data.class_of_save(), Data.TEAM_COLORS[0], Data.weapon_for(Data.class_of_save(), String(Save.d.get("weapon", ""))), "", Save.d.get("look", {}))
	hunter_node.position = Vector3(-0.3, 0, 0.3); hunter_node.rotation.y = PI + 0.5
	var ring := hunter_node.get_node_or_null("TeamRing") as Node3D
	if ring: ring.visible = false
	w3.add_child(hunter_node)
	h_anim = HunterAnim.new(hunter_node)
	if s.has("kin") and won_k:
		kin_node = Models.kin(String(s["kin"]["species"]), s["kin"])
		kin_node.position = Vector3(0.75, 0, 0.6); kin_node.rotation.y = PI + 0.9
		kin_node.set_meta("happy", true)
		w3.add_child(kin_node)
	var cam := Camera3D.new(); cam.fov = 40
	# the island sits left of the results card
	cam.position = Vector3(4.6, 2.6, 8.4)
	w3.add_child(cam)
	cam.look_at(Vector3(3.3, 0.6, 0))

func _process(dt: float) -> void:
	t += dt
	if h_anim:
		var vy := 0.0
		if won_k:
			# a little victory hop every couple of seconds
			var ph := fmod(t, 2.2)
			hunter_node.position.y = maxf(0.0, sin(ph / 0.5 * PI)) * 0.35 if ph < 0.5 else 0.0
			vy = cos(ph / 0.5 * PI) * 2.0 if ph < 0.5 else 0.0
		h_anim.update(dt, {"grounded": hunter_node.position.y < 0.01, "vel": Vector3(0, vy, 0), "crouch": 0.0 if won_k else 0.7, "downed": false})
	if kin_node:
		kin_node.get_node("Body").position.y = absf(sin(t * 5.0)) * 0.25

func _lost_title(why: String) -> String:
	match why:
		"abyss": return "You fell"
		"left": return "You left the match"
	return "Knocked out"
