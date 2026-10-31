extends CanvasLayer
## Menus that sit on top of any screen: the Esc menu, settings, save files and the admin panel.
## Screens open it (Esc at home, in town, in a match; buttons on the title screen) and listen for
## `closed` to carry on.

signal closed

var root: Control
var dim: ColorRect
var host: CenterContainer
var fps_lbl: Label
var page := ""                  # "" when nothing is open
var ctx := ""                   # title | home | town | match
var stack: Array = []           # pages to go back to with Esc
var tab := "Audio"
var listening := ""             # an action waiting for its new key
var listen_lbl: Label = null
var delete_armed := -1

func _ready() -> void:
	Game.screen_changed.connect(func(_n):
		if page != "": close())
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = UI.theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	dim = ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.visible = false
	root.add_child(dim)
	host = CenterContainer.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(host)
	fps_lbl = UI.label("", 13, UI.MUTED)
	fps_lbl.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	fps_lbl.position = Vector2(-80, 4)
	root.add_child(fps_lbl)

func _process(_d: float) -> void:
	fps_lbl.visible = bool(Settings.get_v("show_fps"))
	if fps_lbl.visible:
		fps_lbl.text = "%d fps" % Engine.get_frames_per_second()

func is_open() -> bool:
	return page != ""

## Admin tools are for the game's owner: always on desktop, and on the web for the artifact's owner.
func admin_allowed() -> bool:
	return not OS.has_feature("web") or Social.is_owner

# ------------------------------------------------------------------ input
func _input(event: InputEvent) -> void:
	if listening != "":
		if event is InputEventKey and event.pressed and not event.echo:
			if (event as InputEventKey).physical_keycode == KEY_ESCAPE:
				listening = ""
				_show_settings()
			else:
				_finish_rebind(event)
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.pressed:
			_finish_rebind(event)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).physical_keycode
		var typing := get_viewport().gui_get_focus_owner() is LineEdit
		if not typing and event.is_action_pressed("inventory") and ctx_now() in ["home", "town", "interior"]:
			if page == "inventory": close()
			elif page == "": open_inventory()
			get_viewport().set_input_as_handled()
			return
		if (k == KEY_F1 or (k == KEY_QUOTELEFT and not typing)) and admin_allowed() and Game.main and ctx_now() != "title":
			if page == "admin": close()
			else: open_admin()
			get_viewport().set_input_as_handled()
			return
	if page != "" and event.is_action_pressed("menu"):
		back()
		get_viewport().set_input_as_handled()

func ctx_now() -> String:
	var s = Game.main.screen_node() if Game.main else null
	if s == null: return "title"
	var path := String(s.get_script().resource_path) if s.get_script() else ""
	if path.ends_with("home.gd"): return "home"
	if path.ends_with("town.gd"): return "town"
	if path.ends_with("interior.gd"): return "interior"
	if s is Match: return "match"
	return "title"

# ------------------------------------------------------------------ pages
func _page(name: String, title_txt: String, width := 620.0, scroll := false) -> VBoxContainer:
	for ch in host.get_children():
		ch.queue_free()
	if page != "" and page != name and not stack.has(page):
		stack.append(page)
	var was_open := page != ""
	page = name
	dim.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not was_open and Game.main:
		var s = Game.main.screen_node()
		if s and s.has_method("on_menu_opened"):
			s.on_menu_opened()
	var pb := UI.scroll_panel(title_txt, width, back, "Back" if stack.size() > 0 else "Close", scroll)
	host.add_child(pb[0])
	return pb[1]

func back() -> void:
	if stack.size() > 0:
		var prev: String = stack.pop_back()
		page = ""
		match prev:
			"pause": open_pause(ctx)
			"settings": open_settings()
			"saves": open_saves()
			"inventory": open_inventory()
			_: close()
	else:
		close()

func close() -> void:
	for ch in host.get_children():
		ch.queue_free()
	page = ""
	stack.clear()
	listening = ""
	delete_armed = -1
	dim.visible = false
	Sfx.play("whoosh", null, -14.0)
	closed.emit()

## The Esc menu.
func open_pause(where: String) -> void:
	ctx = where
	stack.clear()
	page = ""
	var v := _page("pause", "Paused" if where == "match" else "Menu", 420)
	var bw := 360.0
	v.add_child(UI.primary("Resume", close, bw))
	if where != "match":
		v.add_child(UI.button("Inventory  (%s)" % Settings.key_cap("inventory"), open_inventory, bw))
	v.add_child(UI.button("Settings", open_settings, bw))
	v.add_child(UI.button("Controls", func(): tab = "Controls"; open_settings(), bw))
	if where == "home":
		v.add_child(UI.button("Change how you look", func():
			close()
			Game.goto("hatch", {"create": true}), bw))
	var scr = Game.main.screen_node() if Game.main else null
	if scr and scr.has_method("unstick"):
		v.add_child(UI.button("I'm stuck", func():
			close()
			scr.unstick()
			Sfx.play("whoosh"), bw))
	if admin_allowed():
		v.add_child(UI.button("Admin tools  (F1)", open_admin, bw))
	if where == "match":
		var m = Game.main.screen_node()
		var tut: bool = m.opts.get("tutorial", false) or m.opts.get("training", false)
		v.add_child(UI.button("Leave the training area" if m.opts.get("training", false) else ("Skip the tutorial" if tut else "Leave match (you lose what you carry)"), func():
			close()
			m.paused = false
			if m.player and m.player.out: Life.make_gone(m, m.player)
			m.result = {"extracted": tut, "why": "left"}
			m._finish(), bw))
	else:
		v.add_child(UI.button("Save files", open_saves, bw))
		v.add_child(UI.button("Save and go to the main menu", func():
			Save.save_game()
			close()
			Game.goto("title"), bw))
	if not OS.has_feature("web"):
		v.add_child(UI.button("Save and quit the game", func():
			Save.save_game()
			get_tree().quit(), bw))

# ------------------------------------------------------------------ settings
func open_settings() -> void:
	_show_settings()

func _show_settings() -> void:
	var v := _page("settings", "Settings", 680, true)
	var tabs := UI.hbox(6)
	for t in ["Audio", "Video", "Controls", "Gameplay", "Accessibility"]:
		var tn: String = t
		var b := UI.choice(t, t == tab, func(): tab = tn; UI._page_of.erase("Settings"); _show_settings())
		tabs.add_child(b)
	tabs.set_meta("pg_keep", true)
	v.add_child(tabs)
	match tab:
		"Audio":
			_slider(v, "Master volume", "master", 0.0, 1.0)
			_slider(v, "Music", "music", 0.0, 1.0)
			_slider(v, "Sound effects", "sfx", 0.0, 1.0)
			_slider(v, "Ambience (wind, rain)", "ambience", 0.0, 1.0)
			_toggle(v, "Mute when the window isn't focused", "mute_unfocused")
		"Video":
			_toggle(v, "Fullscreen", "fullscreen")
			if not OS.has_feature("web"):
				_toggle(v, "V-sync", "vsync")
			_choice(v, "Frame rate limit", "max_fps", [[0, "None"], [30, "30"], [60, "60"], [120, "120"], [144, "144"]])
			_choice(v, "Anti-aliasing", "msaa", [[0, "Off"], [2, "2x"], [4, "4x"]])
			_toggle(v, "Shadows", "shadows")
			_toggle(v, "Show frame rate", "show_fps")
		"Controls":
			v.add_child(UI.label("Click Change, then press a key or mouse button. Esc cancels.", 13, UI.MUTED))
			for a in Settings.ACTIONS:
				var row := UI.hbox(10)
				var l := UI.label(a[1], 15); l.custom_minimum_size.x = 230
				row.add_child(l)
				var cur := UI.label(Settings.binding_text(a[0]), 15, UI.GOLD)
				cur.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(cur)
				var an: String = a[0]
				row.add_child(UI.button("Change", func():
					listening = an
					cur.text = "Press a key..."
					listen_lbl = cur, 110))
				v.add_child(row)
			v.add_child(UI.label("Esc always opens this menu. Reloading is automatic.", 13, UI.MUTED))
		"Gameplay":
			var name_row := UI.hbox(10)
			var nl := UI.label("Your name", 15); nl.custom_minimum_size.x = 230
			name_row.add_child(nl)
			var ne := LineEdit.new(); ne.text = Save.d.get("name", "Hunter"); ne.max_length = 16
			ne.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ne.text_changed.connect(func(t):
				Save.d["name"] = t.strip_edges() if t.strip_edges() != "" else "Hunter"
				Save.save_game())
			name_row.add_child(ne)
			v.add_child(name_row)
			_choice(v, "Expedition camera", "cam_style", CamRig.STYLES.keys().map(func(k): return [k, CamRig.STYLES[k]["name"]]))
			_choice(v, "Camera follow", "cam_follow", [["supervive", "Supervive (leans to the cursor)"], ["standard", "Standard Dynamic"], ["dynamic", "Fully Dynamic"], ["locked", "Locked"]])
			_slider(v, "Camera lean toward the cursor", "cam_lead", 0.0, 1.5)
			_toggle(v, "Hold Shift for the long dash (tap for the short one)", "dash_hold")
			_toggle(v, "Damage numbers", "damage_numbers")
			_toggle(v, "Tips during matches", "tips")
			_toggle(v, "Abilities fire the moment you press them (off: hold to aim, release to cast)", "cast_on_press")
			_toggle(v, "Tap to crouch (instead of holding the crouch key)", "crouch_toggle")
			_toggle(v, "Kin use their abilities on their own (they can spend cooldowns you wanted)", "kin_auto")
			if admin_allowed():
				_choice(v, "Bot difficulty (admin)", "bot_diff", [["auto", "Auto (by tier)"]] + Data.BOT_ORDER.map(func(k): return [k, Data.BOT_DIFF[k]["name"]]))
				_toggle(v, "Mod mode: everything unlocked, free building and bridges, god mode, spawn kin (F1)", "mod_mode")
		"Accessibility":
			_slider(v, "Interface size", "ui_scale", 0.75, 1.5, 0.05)
			_slider(v, "Screen shake", "shake", 0.0, 1.5)
			_toggle(v, "Fewer flashes", "reduce_flashes")
	var foot := UI.hbox(8)
	foot.add_child(UI.button("Reset everything to defaults", func():
		Settings.reset_all()
		_show_settings()))
	v.add_child(foot)

func _row(v: VBoxContainer, label_txt: String) -> HBoxContainer:
	var r := UI.hbox(10)
	var l := UI.label(label_txt, 15); l.custom_minimum_size.x = 260
	r.add_child(l)
	v.add_child(r)
	return r

func _slider(v: VBoxContainer, label_txt: String, key: String, lo: float, hi: float, step := 0.05) -> void:
	var r := _row(v, label_txt)
	var sl := HSlider.new(); sl.min_value = lo; sl.max_value = hi; sl.step = step
	sl.value = float(Settings.get_v(key)); sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.custom_minimum_size.x = 200
	var pct := UI.label("%d%%" % int(round(sl.value * 100.0)), 14, UI.MUTED); pct.custom_minimum_size.x = 52
	# the interface size only changes when you let go, so the slider doesn't run away from the mouse
	if key == "ui_scale":
		# applies when you let go (or click the track), so the slider doesn't run away from the mouse
		sl.drag_ended.connect(func(_c): Settings.set_v(key, sl.value))
		sl.value_changed.connect(func(val):
			pct.text = "%d%%" % int(round(val * 100.0))
			if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): Settings.set_v(key, val))
	else:
		sl.value_changed.connect(func(val):
			pct.text = "%d%%" % int(round(val * 100.0))
			Settings.set_v(key, val, false))
		sl.drag_ended.connect(func(_c): Settings.save())
	r.add_child(sl)
	r.add_child(pct)

func _toggle(v: VBoxContainer, label_txt: String, key: String) -> void:
	var r := _row(v, label_txt)
	var cb := CheckButton.new()
	cb.button_pressed = bool(Settings.get_v(key))
	cb.toggled.connect(func(on): Settings.set_v(key, on))
	r.add_child(cb)

func _choice(v: VBoxContainer, label_txt: String, key: String, opts: Array) -> void:
	var r := _row(v, label_txt)
	var ob := OptionButton.new()
	var cur = Settings.get_v(key)
	for i in opts.size():
		ob.add_item(String(opts[i][1]), i)
		if opts[i][0] == cur: ob.select(i)
	ob.item_selected.connect(func(i): Settings.set_v(key, opts[i][0]))
	r.add_child(ob)

func _finish_rebind(ev: InputEvent) -> void:
	Settings.rebind(listening, ev)
	listening = ""
	Sfx.play("click")
	_show_settings()

# ------------------------------------------------------------------ inventory
var inv_tab := "Items"

func open_inventory() -> void:
	if Progress.day1_mark("inventory") != "":
		Sfx.play("unlock", null, -8.0)
	var v := _page("inventory", "Inventory", 720)
	var tabs := UI.hbox(6)
	for t in ["Items", "Seeds", "Crops", "Furniture", "Kin", "Kindex"]:
		var tn: String = t
		tabs.add_child(UI.choice(t, t == inv_tab, func(): inv_tab = tn; UI._page_of.erase("Inventory"); open_inventory()))
	tabs.set_meta("pg_keep", true)
	v.add_child(tabs)
	var grid := GridContainer.new(); grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10); grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	var cell := func(title_txt: String, count_txt: String, desc: String, col: Color, action_txt := "", action := Callable()) -> void:
		var c := UI.card(UI.CARD, 12, 12)
		c.custom_minimum_size = Vector2(210, 0)
		var cv := UI.vbox(4); c.add_child(cv)
		var top := UI.hbox(8)
		var sw := ColorRect.new(); sw.color = col; sw.custom_minimum_size = Vector2(14, 14); sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(sw)
		var tl := UI.label(title_txt, 15); tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(tl)
		top.add_child(UI.label(count_txt, 15, UI.GOLD))
		cv.add_child(top)
		if desc != "":
			var dl := UI.label(desc, 12, UI.MUTED); dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			cv.add_child(dl)
		if action.is_valid():
			cv.add_child(UI.button(action_txt, action))
		grid.add_child(c)
	var empty := true
	match inv_tab:
		"Items":
			empty = false
			cell.call("Gems", str(int(Save.d["gems"])), "Spend them at the stall, on buildings and furniture.", Color("7ef0d0"))
			cell.call("Tonics", "×%d" % int(Save.d["items"].get("tonic", 0)), "Heal 45 in a match (key %s)." % Settings.key_cap("tonic"), Color("8ff0a0"))
			for f in Care.FOODS:
				var fn := int(Save.d["items"].get(f, 0))
				if fn > 0: cell.call(Care.FOODS[f]["name"], "×%d" % fn, Care.FOODS[f]["desc"] + " Feed it from a kin's card.", Care.FOODS[f]["col"])
			var tr: String = Save.d.get("treat", "")
			if tr != "":
				cell.call("Treat ready", "", "Your partner eats it before the next expedition.", Color("f2c84a"))
		"Seeds":
			for k in Data.CROPS:
				var n := int(Save.d["seeds"].get(k, 0))
				if n <= 0: continue
				empty = false
				cell.call(Data.CROPS[k]["name"] + " seed", "×%d" % n, "Plant it in a farm plot.", Data.CROPS[k]["color"])
		"Crops":
			for k in Data.CROPS:
				var n := int(Save.d["crops"].get(k, 0))
				if n <= 0: continue
				empty = false
				var ck: String = k
				cell.call(Data.CROPS[k]["name"], "×%d" % n, Data.CROPS[k]["desc"], Data.CROPS[k]["color"], "Feed to your partner", func():
					var ak := Save.active_kin()
					if ak.is_empty() or int(Save.d["crops"].get(ck, 0)) <= 0: return
					Save.d["crops"][ck] = int(Save.d["crops"][ck]) - 1
					for af in Evo.AFF:
						if Evo.AFF[af]["food"] == ck: Evo.add(ak, af, 6.0)
					Save.remember(ak, "fed", "was fed a %s" % Data.CROPS[ck]["name"].to_lower(), 4.0)
					Sfx.play("kin_happy")
					Save.save_game()
					open_inventory())
		"Furniture":
			for k in Data.FURN:
				var n := int(Save.d.get("furniture", {}).get(k, 0))
				if n <= 0: continue
				empty = false
				cell.call(Data.FURN[k]["name"], "×%d" % n, "Place it inside your house: go in and press B.", Color("c99a6a"))
		"Kin":
			for rec in Save.d["roster"]:
				empty = false
				var sp: Dictionary = Data.KIN[rec["species"]]
				cell.call(String(rec["name"]), "Lv %d" % int(rec["level"]), "%s%s%s · %s bond · %s%s" % ["in the Kin Burrow · " if KinBox.is_boxed(rec) else "", (" ".join(Mutations.tags(rec)) + " ") if Mutations.special(rec) else "", Evo.form_name(rec), Care.bond(rec)[1], Care.condition_name(rec).to_lower(), "  · partner" if rec["uid"] == Save.d.get("active", "") else ""], Care.shimmer_col(sp["color"]) if rec.get("shimmer", false) else sp["color"])
		"Kindex":
			empty = false
			Care.dex_sync()
			var dx: Dictionary = Save.d.get("dex", {})
			for spk in Data.KIN:
				var e: Dictionary = dx.get(spk, {})
				var sp: Dictionary = Data.KIN[spk]
				if e.is_empty() or not e.get("seen", false):
					cell.call("???", "", "Not seen yet. Look for it on expeditions.", Color(0.3, 0.32, 0.4))
					continue
				var forms: Array = e.get("forms", [])
				var desc := "%s type. %s." % [String(sp["type"]).capitalize(), "Caught" if e.get("caught", false) else "Seen, not caught"]
				if forms.size() > 0: desc += " Forms: " + ", ".join(forms.slice(0, 3)) + ("..." if forms.size() > 3 else "")
				if e.get("shimmer", false): desc += " Shimmer found!"
				var dm: Array = e.get("mutations", [])
				if not dm.is_empty(): desc += " Rare: " + ", ".join(dm.map(func(x): return Mutations.name_of(String(x)))) + "."
				cell.call(String(sp["name"]), "★" if e.get("shimmer", false) else ("✓" if e.get("caught", false) else ""), desc, sp["color"])
	if empty:
		v.add_child(UI.label({"Seeds": "No seeds. Find them on expeditions or buy them at the stall.", "Crops": "No crops yet. Harvest your plots.", "Furniture": "Nothing stored. Furniture you buy or put away lands here.", "Kin": "No kin yet."}.get(inv_tab, ""), 14, UI.MUTED))

# ------------------------------------------------------------------ save files
func open_saves() -> void:
	var v := _page("saves", "Save files", 620)
	v.add_child(UI.label("Each save has its own island, kin and gems. Settings are shared by all of them.", 14, UI.MUTED))
	for n in range(1, Save.SLOTS + 1):
		var info := Save.slot_info(n)
		var c := UI.card(UI.CARD, 12, 12)
		if n == Save.slot: UI.set_card_border(c, UI.ACCENT)
		var h := UI.hbox(10); c.add_child(h)
		var col := UI.vbox(2); col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(col)
		var sn: int = n
		if info["exists"]:
			col.add_child(UI.label("Save %d · %s%s" % [n, info["name"], "  (playing)" if n == Save.slot else ""], 17, UI.INK))
			col.add_child(UI.label("%d kin · %d gems · %d expeditions · last played %s" % [info["kin"], info["gems"], info["matches"], info["when"]], 13, UI.MUTED))
			if n == Save.slot:
				h.add_child(UI.label("Playing", 14, UI.GOLD))
			else:
				h.add_child(UI.button("Play", func(): _play_slot(sn), 90))
			if delete_armed == n:
				var playing: bool = n == Save.slot
				h.add_child(UI.button("Yes, delete it" if playing else "Really delete?", func():
					delete_armed = -1
					Save.delete_slot(sn)
					if playing:
						# that was the save in play: start over from the title, on this now-empty slot
						Save.save_game()
						close()
						Game.goto("title")
					else:
						open_saves(), 150))
				if playing:
					col.add_child(UI.label("This is the save you're playing. Deleting it takes you back to the title.", 13, UI.BAD))
			else:
				h.add_child(UI.button("Delete", func():
					delete_armed = sn
					open_saves(), 90))
		else:
			col.add_child(UI.label("Save %d · empty" % n, 17, UI.MUTED))
			h.add_child(UI.button("New game", func(): _play_slot(sn), 130))
		v.add_child(c)

func _play_slot(n: int) -> void:
	Save.use_slot(n)
	close()
	Social.refresh_guild()
	Game.goto("home" if not Save.d["roster"].is_empty() else "hatch")

# ------------------------------------------------------------------ admin
func open_admin() -> void:
	if page != "admin" and page != "":
		stack.append(page)
	var c := ctx_now()
	var v := _page("admin", "Admin tools", 640)
	v.add_child(UI.label("For testing. F1 or ` opens this anywhere.", 13, UI.MUTED))
	var god := CheckButton.new()
	god.text = "God mode: can't be hurt or fall, no cooldowns, endless ammo"
	god.button_pressed = Game.god
	god.toggled.connect(func(on): Game.god = on)
	v.add_child(god)
	# bot difficulty: Auto follows the run tier (and your experience); the rest force one
	v.add_child(UI.section("Bot difficulty"))
	var drow := HFlowContainer.new()
	drow.add_theme_constant_override("h_separation", 8); drow.add_theme_constant_override("v_separation", 8)
	var cur_d := String(Settings.get_v("bot_diff"))
	for dk in ["auto"] + Data.BOT_ORDER:
		var dkey: String = dk
		drow.add_child(UI.choice("Auto" if dkey == "auto" else String(Data.BOT_DIFF[dkey]["name"]), dkey == cur_d, func():
			Settings.set_v("bot_diff", dkey)
			Sfx.play("pickup")
			open_admin(), 104))
	v.add_child(drow)
	var dnote := "Auto: Meadow bots are Easy, Dusk Isles Medium, the Hollow Hard, one step up once you've extracted a lot."
	if c == "match":
		var mm = Game.main.screen_node()
		dnote += "  This run: %s. Changes apply from the next expedition." % String(Data.BOT_DIFF[mm.bot_diff]["name"])
	v.add_child(UI.label(dnote, 13, UI.MUTED))
	var grid := GridContainer.new(); grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8); grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	var add := func(txt: String, f: Callable):
		var b := UI.button(txt, func():
			f.call()
			Sfx.play("pickup")
			Save.save_game()
			_admin_refresh(), 290)
		grid.add_child(b)
	add.call("+1000 gems", func(): Save.d["gems"] = int(Save.d["gems"]) + 1000)
	add.call("+10 of every seed", func():
		for s in Data.CROPS: Save.add_seed(s, 10))
	add.call("+5 of every crop", func():
		for s in Data.CROPS: Save.d["crops"][s] = int(Save.d["crops"].get(s, 0)) + 5)
	add.call("+5 tonics", func(): Save.add_item("tonic", 5))
	add.call("Partner +1 level", func():
		var k := Save.active_kin()
		if not k.is_empty():
			k["level"] = int(k["level"]) + 1
			Game._evolve(k, {}))
	add.call("Partner full trust", func():
		var k := Save.active_kin()
		if not k.is_empty(): k["trust"] = 100.0)
	add.call("Grow every crop now", func():
		for arr in ["plots", "gh_plots"]:
			for p in Save.d.get(arr, []):
				if p["crop"] != "":
					p["stage"] = int(Data.CROPS[p["crop"]]["grow"])
					p["care"] = p["stage"]
		if c == "home": _reload_home())
	add.call("Unlock every building and bridge", func():
		for b in Data.BUILDINGS:
			if not Save.d["buildings"].has(b): Save.d["buildings"].append(b)
		for i in Data.ISLES:
			if not Save.d["bridges"].has(i): Save.d["bridges"].append(i)
		Save.d["extracts"] = maxi(int(Save.d.get("extracts", 0)), 10)
		if c == "home": _reload_home())
	add.call("Unlock every expedition tier", func(): Save.d["extracts"] = maxi(int(Save.d.get("extracts", 0)), 10))
	add.call("Replay the tutorials", func(): Save.d["tutorial"] = {})
	var spawn := UI.button("Spawn a kin…", open_spawn_kin, 290)
	grid.add_child(spawn)
	if c == "home":
		var h = Game.main.screen_node()
		add.call("Morning", func(): h.day_t = 0.27)
		add.call("Night", func(): h.day_t = 0.95)
		add.call("Rain on / off", func():
			h.raining = not h.raining
			h.weather_t = 999.0 if h.raining else 60.0
			h.rain.emitting = h.raining)
	if c == "match":
		var m = Game.main.screen_node()
		add.call("Ultimate and ability ready", func():
			if m.player:
				m.player.ult = 1.0; m.player.sig_cd = 0.0)
		add.call("Defeat every monster", func():
			for mb in m.mobs:
				if not mb.dead: mb.hurt(99999.0, m.player, {}))
		add.call("Exits ready now", func():
			if m.exits: m.exits.admin_ready())
		add.call("Extract now", func():
			if m.player and not m.player.out:
				close()
				m._extract(m.player))
	var stat := UI.label("", 13, UI.MUTED)
	stat.name = "AdminStat"
	v.add_child(stat)
	_admin_refresh()

var admin_mut := ""            # admin spawn: the rare mutation the next kin comes with
var admin_shimmer := false
## Admin: pick any species to add to your farm.
func open_spawn_kin() -> void:
	if page != "spawn" and page != "":
		stack.append(page)
	var v := _page("spawn", "Spawn a kin", 640)
	v.add_child(UI.label("Adds a level 8 kin with a Close bond to your farm (or the Kin Burrow, if it's a repeat or the farm is full).", 13, UI.MUTED))
	var mrow := HFlowContainer.new()
	mrow.add_theme_constant_override("h_separation", 6); mrow.add_theme_constant_override("v_separation", 6)
	mrow.add_child(UI.label("Mutation:", 13, UI.MUTED))
	for mid in [""] + Mutations.ids():
		var mk: String = mid
		mrow.add_child(UI.choice("none" if mk == "" else Mutations.name_of(mk), admin_mut == mk, func(): admin_mut = mk; open_spawn_kin()))
	mrow.add_child(UI.choice("Shimmer", admin_shimmer, func(): admin_shimmer = not admin_shimmer; open_spawn_kin()))
	v.add_child(mrow)
	var grid := GridContainer.new(); grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8); grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	for sp in Data.KIN:
		var sid: String = sp
		var b := UI.button(String(Data.KIN[sid]["name"]), func():
			var rec := Save.new_kin(sid)
			rec["level"] = 8
			rec["trust"] = 60.0
			Evo.simulate(rec, RandomNumberGenerator.new())
			if admin_mut != "": rec["mutations"] = [admin_mut]
			if admin_shimmer: rec["shimmer"] = true
			Save.d["roster"].append(rec)
			KinBox.route_new(rec)
			Care.dex_got(rec)
			Save.save_game()
			Sfx.play("unlock")
			var s = Game.main.screen_node() if Game.main else null
			if s and s.has_method("_spawn_kin"):
				s._spawn_kin()
			_admin_refresh(), 196)
		b.add_theme_color_override("font_color", Data.KIN[sid]["color"])
		grid.add_child(b)
	var stat := UI.label("", 13, UI.MUTED)
	stat.name = "AdminStat"
	v.add_child(stat)
	_admin_refresh()

func _admin_refresh() -> void:
	var st := root.find_child("AdminStat", true, false)
	if st:
		var k := Save.active_kin()
		(st as Label).text = "%d gems · partner %s level %d, trust %d" % [int(Save.d["gems"]), k.get("name", "none"), int(k.get("level", 0)), int(k.get("trust", 0))]
	var s = Game.main.screen_node() if Game.main else null
	if s and s.has_method("_refresh_top"):
		s._refresh_top()

func _reload_home() -> void:
	close()
	Game.goto("home")
