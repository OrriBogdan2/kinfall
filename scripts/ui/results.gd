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
	var center := CenterContainer.new(); center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(center)
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
	if s.has("kin_lost"):
		v.add_child(UI.label("%s stayed behind in the Hollow. It didn't trust you enough to follow you home." % s["kin_lost"]["name"], 16, UI.BAD))
	if s.get("kin_stranded", false):
		v.add_child(UI.label("%s was stranded in the Hollow and only just made it home. It trusts you a lot less now." % s["kin"]["name"], 16, UI.BAD))
	if s.get("kin_home", false):
		v.add_child(UI.label("%s found its own way home. It trusts you that much." % s["kin"]["name"], 16, UI.GOOD))
	if int(s.get("vault_gems", 0)) > 0:
		v.add_child(UI.label("Your vault kept %d of the gems you dropped." % int(s["vault_gems"]), 15, UI.GOLD))
	if s["crops_ready"] > 0:
		v.add_child(UI.label("%d crop%s ready to harvest on your farm." % [s["crops_ready"], "s" if s["crops_ready"] > 1 else ""], 15, UI.GOOD))
	v.add_child(UI.spacer(6))
	if r.get("tutorial", false):
		v.add_child(UI.label("That's the basics. Now come see your home.", 16, UI.GOLD))
	v.add_child(UI.primary("Go home" if r.get("tutorial", false) else "Back to the farm", func(): Game.goto("home"), 240))

func _lost_title(why: String) -> String:
	match why:
		"abyss": return "You fell"
		"left": return "You left the match"
	return "Knocked out"
