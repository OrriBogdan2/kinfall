extends Control
## Online lobby: everyone who has the game open shows up here. Ready up, and whoever presses Start hosts.

var opts := {}
var list_box: VBoxContainer
var status: Label
var ready_btn: Button
var start_btn: Button
var is_ready := false
var mode := "ffa"
var mode_btns := {}

func setup(o: Dictionary) -> void:
	opts = o

func _ready() -> void:
	Sfx.play_music("title")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UI.theme()
	var bg := ColorRect.new(); bg.color = UI.BG; bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(bg)
	var center := CenterContainer.new(); center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(center)
	var pb := UI.scroll_panel("Play online", 640, func(): Game.goto("home"), "Back")
	var panel: PanelContainer = pb[0]
	var v: VBoxContainer = pb[1]
	center.add_child(panel)
	UI.pop_in(panel)
	status = panel.get_meta("sub")
	UI.subtitle(v, "Connecting...")
	v.add_child(UI.section("Hunters here"))
	list_box = UI.vbox(6)
	list_box.add_child(UI.para("Looking for hunters with the game open...", UI.T_SMALL, UI.FAINT))
	v.add_child(list_box)
	v.add_child(UI.spacer(2))
	v.add_child(UI.section("Teams"))
	var modes := UI.hbox(2)
	var track := PanelContainer.new()
	var tsb := UI._box(UI.WELL, 11, Color(1, 1, 1, 0.05), 1); UI._pad(tsb, 3, 3)
	track.add_theme_stylebox_override("panel", tsb)
	track.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	track.add_child(modes)
	for m in [["ffa", "Everyone for themselves"], ["duo", "Teams of 2"], ["trio", "Teams of 3"]]:
		var key: String = m[0]
		var b := UI.button(m[1], func(): mode = key; _refresh_modes())
		mode_btns[key] = b
		modes.add_child(b)
	v.add_child(track)
	v.add_child(UI.para("Empty spots are filled with bots, up to 4 squads. Whoever presses Start hosts the match and runs the monsters, so keep that tab in front."))
	ready_btn = UI.button("I'm ready", _toggle_ready, 160, "check")
	UI.footer(v).add_child(ready_btn)
	start_btn = UI.footer_primary(v, "Start the match", _start, 220, "portal")
	_refresh_modes()
	Net.peers_changed.connect(_refresh)
	Net.message.connect(_on_msg)
	Net.start()
	await get_tree().create_timer(1.8).timeout
	_announce()
	_refresh()

## Esc goes back to the farm, like the X.
func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("menu") and not Overlay.is_open():
		get_viewport().set_input_as_handled()
		Game.goto("home")

func _exit_tree() -> void:
	if Net.peers_changed.is_connected(_refresh):
		Net.peers_changed.disconnect(_refresh)
	if Net.message.is_connected(_on_msg):
		Net.message.disconnect(_on_msg)

func _refresh_modes() -> void:
	for k in mode_btns:
		mode_btns[k].theme_type_variation = "SegOn" if k == mode else "Seg"

func _announce() -> void:
	var k := Save.active_kin()
	Net.set_presence({"name": Save.d.get("name", "Hunter"), "cls": opts.get("cls", Data.class_of_save()), "weapon": Save.d.get("weapon", ""), "ready": is_ready, "lobby": 1,
		"kin": {"species": k.get("species", "cindle"), "level": int(k.get("level", 1)), "name": k.get("name", "Kin"), "traits": k.get("traits", {}), "trust": float(k.get("trust", 50))}})

func _toggle_ready() -> void:
	is_ready = not is_ready
	ready_btn.text = "Ready" if is_ready else "I'm ready"
	ready_btn.theme_type_variation = "Chosen" if is_ready else ""
	_announce()

func _refresh() -> void:
	if not is_instance_valid(list_box):
		return
	for c in list_box.get_children():
		c.queue_free()
	var how := "through this artifact's room" if Net.mode == "room" else "between browser tabs on this computer (the room isn't available here)"
	status.text = "Connected %s. %d player%s here." % [how, Net.peers.size(), "" if Net.peers.size() == 1 else "s"] if Net.mode != "" else "Connecting..."
	for id in Net.peers:
		var p: Dictionary = Net.peers[id]
		if not p.has("lobby"):
			continue
		var row := UI.card(UI.CARD, 10, 12)
		var h := UI.hbox(12); row.add_child(h)
		h.add_child(UI.IconDot.new("paw", Data.KIN.get(p.get("kin", {}).get("species", "cindle"), Data.KIN["cindle"])["color"], 20.0))
		var nm := UI.label("%s%s" % [p.get("name", "Hunter"), "  (you)" if id == Net.me else ""], UI.T_BODY, UI.ACCENT_HI if id == Net.me else UI.INK, UI.semi)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.autowrap_mode = TextServer.AUTOWRAP_OFF
		h.add_child(nm)
		var kin: Dictionary = p.get("kin", {})
		var info := UI.label("%s · %s" % [Data.CLASSES.get(p.get("cls", "medium"), Data.CLASSES["medium"])["name"], Data.KIN.get(kin.get("species", "cindle"), Data.KIN["cindle"])["name"]], 14, UI.MUTED)
		info.autowrap_mode = TextServer.AUTOWRAP_OFF
		h.add_child(info)
		h.add_child(UI.tag("Ready" if p.get("ready", false) else "Not ready", UI.GOOD if p.get("ready", false) else UI.MUTED))
		list_box.add_child(row)

func _start() -> void:
	if Net.mode == "":
		return
	var squad: int = {"ffa": 1, "duo": 2, "trio": 3}[mode]
	var ids: Array = []
	for id in Net.peers:
		var p: Dictionary = Net.peers[id]
		if p.has("lobby") and (p.get("ready", false) or id == Net.me):
			ids.append(id)
	if not ids.has(Net.me):
		ids.append(Net.me)
	ids.sort()
	var roster := []
	for i in ids.size():
		var id: String = ids[i]
		var p: Dictionary = Net.peers.get(id, Net.my_presence)
		if id == Net.me:
			p = Net.my_presence
		roster.append({"peer": id, "team": i / squad, "name": p.get("name", "Hunter"), "cls": p.get("cls", "medium"), "weapon": p.get("weapon", ""), "kin": p.get("kin", {})})
	var teams := maxi(int(ceil(float(ids.size()) / squad)), int(ceil(Data.MATCH_PLAYERS / float(squad))))
	var d := {"mid": "%d" % (Time.get_ticks_msec() % 100000000), "seed": randi(), "host": Net.me, "roster": roster, "teams": mini(teams, 20), "squad": squad, "tier": int(opts.get("tier", 0))}
	Net.lobby_emit("start", d)
	_go(d)

func _on_msg(topic: String, data, _from: String) -> void:
	if topic != "start" or typeof(data) != TYPE_DICTIONARY:
		return
	for r in data.get("roster", []):
		if String(r["peer"]) == Net.me:
			_go(data)
			return

func _go(d: Dictionary) -> void:
	Save.d["cls"] = opts.get("cls", Save.d.get("cls", "medium"))
	Game.last_tier = int(d.get("tier", 0))
	Game.goto("match", {"net": d, "seed": int(d["seed"]), "teams": int(d["teams"]), "squad": int(d["squad"]), "tier": int(d.get("tier", 0))})
