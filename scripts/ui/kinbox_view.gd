class_name KinBoxView
extends RefCounted
## The Kin Burrow screen: the farm on the left (who's out, and room for more), the box pages in the
## middle (30 kin a page, each page named), and the kin you picked on the right.
##
## Click a kin to see it. Drag it onto the farm, onto an empty cell, or onto another kin to swap
## them. Right click (or double click) sends it straight across. Search, filter and sort sit on top.
## Built from the UI helpers inside the home screen's panel, so it takes the game's menu style.

const COLS := 6
const CELL := Vector2(68, 76)
const FARM_COLS := 2

static var page := 0
static var query := ""
static var filter := "all"
static var sort_key := "species"
static var sel := ""
static var confirm := ""            # uid waiting on "release?"
static var renaming := false

var home: Node = null
var v: VBoxContainer
var summary: Label
var farm_box: VBoxContainer
var grid: GridContainer
var tabs: HBoxContainer
var page_lbl: Label
var name_row: HBoxContainer
var detail: VBoxContainer
var msg: Label
var _msg_t := 0

static func open(h: Node) -> KinBoxView:
	KinBox.ensure()
	var kv := KinBoxView.new()
	kv.home = h
	kv._build()
	return kv

func _tree() -> SceneTree:
	return home.get_tree() if home and home.is_inside_tree() else null

func _build() -> void:
	v = home._new_panel("Kin Burrow", 1090, true)
	v.add_theme_constant_override("separation", 8)
	var cols := UI.hbox(14)
	v.add_child(cols)
	# the farm: who's out, room left, and the cottage expansion
	var fc := UI.card(Color(0.1, 0.13, 0.1, 0.85), 10, 12)
	UI.set_card_border(fc, Color(UI.GOOD, 0.3), 1)
	fc.custom_minimum_size.x = FARM_COLS * CELL.x + 30
	fc.set_drag_forwarding(Callable(), _can_drop, func(_p, d): _drop_on(d, "farm", null))
	farm_box = UI.vbox(6)
	fc.add_child(farm_box)
	cols.add_child(fc)
	# the box pages: name, page tabs, the grid
	var bc := UI.vbox(6)
	cols.add_child(bc)
	name_row = UI.hbox(6)
	bc.add_child(name_row)
	var ph := UI.hbox(4)
	ph.add_child(UI.button("‹", func(): page = (page - 1 + KinBox.PAGES) % KinBox.PAGES; renaming = false; refresh(), 34))
	tabs = UI.hbox(3)
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ph.add_child(tabs)
	ph.add_child(UI.button("›", func(): page = (page + 1) % KinBox.PAGES; renaming = false; refresh(), 34))
	bc.add_child(ph)
	var gc := UI.card(Color(0.07, 0.07, 0.12, 0.9), 8, 12)
	UI.set_card_border(gc, Color(Color("bfa6ff"), 0.25), 1)
	grid = GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 5); grid.add_theme_constant_override("v_separation", 5)
	gc.add_child(grid)
	bc.add_child(gc)
	# the right side: find and sort, then the kin you picked
	var rc := UI.vbox(6)
	rc.custom_minimum_size.x = 320
	rc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(rc)
	var search := LineEdit.new()
	search.placeholder_text = "Search a name or kind"
	search.text = query
	search.clear_button_enabled = true
	search.text_changed.connect(func(t: String): query = t; refresh())
	rc.add_child(search)
	var fr := UI.hbox(6)
	var fo := OptionButton.new()
	var fopts: Array = [["all", "All kin"], ["special", "Any rare"], ["shimmer", "Shimmering"], ["mutated", "Any mutation"]]
	for mid in Mutations.ids(): fopts.append([mid, Mutations.name_of(mid)])
	for spk in Data.KIN:
		if not Data.KIN[spk].get("rare", false) or (Save.d["roster"] as Array).any(func(r): return String(r["species"]) == spk):
			fopts.append([spk, String(Data.KIN[spk]["name"])])
	for i in fopts.size():
		fo.add_item(String(fopts[i][1]), i)
		fo.set_item_metadata(i, fopts[i][0])
		if String(fopts[i][0]) == filter: fo.select(i)
	fo.item_selected.connect(func(i: int): filter = String(fo.get_item_metadata(i)); refresh())
	fo.tooltip_text = "Show only some kin (the rest dim; page tabs count the matches)"
	fo.fit_to_longest_item = false
	fo.clip_text = true
	fo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fo.custom_minimum_size.x = 120
	fr.add_child(fo)
	var so := OptionButton.new()
	for i in KinBox.SORTS.size():
		if String(KinBox.SORTS[i][0]) == "slot": continue
		so.add_item("By " + String(KinBox.SORTS[i][1]).to_lower())
		so.set_item_metadata(so.item_count - 1, KinBox.SORTS[i][0])
		if String(KinBox.SORTS[i][0]) == sort_key: so.select(so.item_count - 1)
	so.item_selected.connect(func(i: int): sort_key = String(so.get_item_metadata(i)))
	so.tooltip_text = "The order Sort uses"
	so.fit_to_longest_item = false
	so.clip_text = true
	so.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	so.custom_minimum_size.x = 120
	fr.add_child(so)
	rc.add_child(fr)
	var sr := UI.hbox(6)
	var sb := UI.button("Sort this box", func():
		KinBox.sort_page(page, sort_key)
		_done("Sorted %s by %s" % [KinBox.page_name(page), _sort_name()]))
	sb.tooltip_text = "Lay out this page's kin in that order"
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sr.add_child(sb)
	var sa := UI.button("Sort every box", func():
		KinBox.sort_all(sort_key)
		page = 0
		_done("Every box sorted by %s, from the first page" % _sort_name()))
	sa.tooltip_text = "Lay out every boxed kin in that order, filling pages from the first"
	sa.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sr.add_child(sa)
	rc.add_child(sr)
	msg = UI.label("", 13, UI.GOLD)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.custom_minimum_size.x = 300
	msg.visible = false
	rc.add_child(msg)
	var dc := UI.card(UI.CARD, 12, 12)
	dc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail = UI.vbox(6)
	dc.add_child(detail)
	rc.add_child(dc)
	summary = msg      # (the old summary line now lives in the farm and box headers)
	refresh()

func _sort_name() -> String:
	for s in KinBox.SORTS:
		if String(s[0]) == sort_key: return String(s[1]).to_lower()
	return sort_key

func _say(t: String, col := UI.GOLD) -> void:
	if not is_instance_valid(msg): return
	msg.text = t
	msg.visible = t != ""
	msg.add_theme_color_override("font_color", col)
	_msg_t += 1
	var mine := _msg_t
	var tr := _tree()
	if tr:
		tr.create_timer(5.0).timeout.connect(func():
			if mine == _msg_t and is_instance_valid(msg): msg.text = ""; msg.visible = false)

func _done(t: String) -> void:
	Save.save_game()
	Sfx.play("click")
	refresh()
	_say(t)
	if home and home.has_method("_spawn_kin"): home._spawn_kin()
	if home and home.has_method("_refresh_burrow"): home._refresh_burrow()

func _fail(t: String) -> void:
	Sfx.play("warn", null, -8.0)
	_say(t, UI.BAD)

## Rebuilds the farm list, the page and the side panel (the toolbar stays, so typing keeps focus).
func refresh() -> void:
	if not is_instance_valid(grid):
		return
	var fk := KinBox.farm()
	var bk := KinBox.boxed()
	if not sel.is_empty() and Save.kin(sel).is_empty(): sel = ""
	_build_farm(fk)
	_build_tabs(bk)
	_build_name()
	for ch in grid.get_children(): ch.queue_free()
	for i in KinBox.PAGE:
		var slot := page * KinBox.PAGE + i
		grid.add_child(_cell(KinBox.at(slot), "box", slot))
	_build_detail()

func _build_farm(fk: Array) -> void:
	for ch in farm_box.get_children(): ch.queue_free()
	var hd := UI.section("On the farm  %d/%d" % [fk.size(), KinBox.farm_cap()], UI.GOOD)
	farm_box.add_child(hd)
	var fg := GridContainer.new(); fg.columns = FARM_COLS
	fg.add_theme_constant_override("h_separation", 6); fg.add_theme_constant_override("v_separation", 6)
	farm_box.add_child(fg)
	var a := str(Save.d.get("active", ""))
	var ordered := fk.duplicate()
	ordered.sort_custom(func(x, y): return (0 if String(x["uid"]) == a else 1) < (0 if String(y["uid"]) == a else 1))
	for r in ordered: fg.add_child(_cell(r, "farm", -1))
	for i in maxi(0, KinBox.farm_cap() - fk.size()): fg.add_child(_cell({}, "farm", -1))
	var cost := KinBox.expand_cost()
	if cost >= 0:
		var nxt: int = KinBox.FARM_CAPS[KinBox.farm_lvl() + 1]
		var eb := UI.button("Expand: room for %d\n%d gems" % [nxt, cost], func():
			var why := KinBox.expand()
			if why != "": _fail(why)
			else:
				Sfx.play("unlock")
				_done("The Kin Cottages grew: room for %d kin on the farm" % KinBox.farm_cap())
				if home and home.has_method("_refresh_top"): home._refresh_top(), FARM_COLS * CELL.x + 6)
		eb.tooltip_text = "A Kin Cottage expansion: +2 kin out on the farm"
		eb.disabled = int(Save.d["gems"]) < cost and not Game.modding()
		farm_box.add_child(eb)
	else:
		farm_box.add_child(UI.label("The cottages are\nas big as they get.", 12, UI.MUTED))

func _build_tabs(bk: Array) -> void:
	for ch in tabs.get_children(): ch.queue_free()
	for p in KinBox.PAGES:
		var n := bk.filter(func(r): return KinBox.page_of(r) == p).size()
		var hits := 0
		if _searching():
			hits = bk.filter(func(r): return KinBox.page_of(r) == p and KinBox.matches(r, query, filter)).size()
		var pp: int = p
		var t := "%d" % (p + 1) + ("·%d" % hits if hits > 0 else "")
		var b := UI.choice(t, p == page, func(): page = pp; renaming = false; refresh())
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.x = 0
		b.tooltip_text = "%s: %d kin%s" % [KinBox.page_name(p), n, (", %d match" % hits) if hits > 0 else ""]
		if hits > 0: b.add_theme_color_override("font_color", UI.GOLD)
		elif n == 0: b.modulate = Color(1, 1, 1, 0.6)
		var target: int = p
		b.set_drag_forwarding(Callable(), _can_drop, func(_pos, d):
			var free := KinBox.free_slot({}, target)
			if free < 0 or free / KinBox.PAGE != target: _fail("%s is full" % KinBox.page_name(target)); return
			_drop_on(d, "box", null, free))
		tabs.add_child(b)

func _build_name() -> void:
	for ch in name_row.get_children(): ch.queue_free()
	if renaming:
		var le := LineEdit.new()
		le.text = KinBox.page_name(page)
		le.max_length = 22
		le.custom_minimum_size = Vector2(240, 0)
		le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var commit := func(t: String):
			KinBox.rename(page, t); renaming = false; Save.save_game(); refresh()
		le.text_submitted.connect(commit)
		name_row.add_child(le)
		name_row.add_child(UI.primary("Save", func(): commit.call(le.text), 70))
		le.grab_focus.call_deferred()
		le.select_all.call_deferred()
	else:
		var t := UI.title(KinBox.page_name(page), 22, Color("e6dcff"))
		t.clip_text = true
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_row.add_child(t)
		var n := KinBox.page_kin(page).size()
		var cl := UI.label("%d/%d  ·  %d asleep" % [n, KinBox.PAGE, KinBox.boxed().size()], 12, UI.MUTED)
		cl.tooltip_text = "Kin on this page, and in the whole burrow (room for %d)" % KinBox.capacity()
		cl.mouse_filter = Control.MOUSE_FILTER_PASS
		name_row.add_child(cl)
		var rb := UI.button("Rename", func(): renaming = true; refresh(), 76)
		name_row.add_child(rb)

func _searching() -> bool:
	return query.strip_edges() != "" or (filter != "all" and filter != "")

## One cell: a kin (or an empty place) on the farm or in a box cell.
func _cell(rec: Dictionary, where: String, slot: int) -> Control:
	var c := PanelContainer.new()
	c.custom_minimum_size = CELL
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	var empty := rec.is_empty()
	var picked := not empty and String(rec["uid"]) == sel
	var bg := Color(0.13, 0.14, 0.2, 1.0) if not empty else Color(0.1, 0.1, 0.15, 0.55)
	if where == "farm" and empty: bg = Color(0.12, 0.17, 0.13, 0.5)
	var sbx := StyleBoxFlat.new()
	sbx.bg_color = bg
	sbx.set_corner_radius_all(10)
	sbx.content_margin_left = 4; sbx.content_margin_right = 4; sbx.content_margin_top = 3; sbx.content_margin_bottom = 3
	if picked:
		sbx.border_color = UI.GOLD; sbx.set_border_width_all(2)
	elif not empty and Mutations.special(rec):
		var ms := Mutations.of(rec)
		sbx.border_color = Color(Mutations.col_of(ms[0]) if not ms.is_empty() else Color("fff0a0"), 0.6)
		sbx.set_border_width_all(1)
	else:
		sbx.border_color = Color(1, 1, 1, 0.05 if empty else 0.08); sbx.set_border_width_all(1)
	c.add_theme_stylebox_override("panel", sbx)
	c.set_drag_forwarding(func(_p): return _drag(rec, c), _can_drop, func(_p, d): _drop_on(d, where, rec, slot))
	if empty:
		if where == "farm":
			var l := UI.label("free", 12, Color(UI.GOOD, 0.5))
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			c.add_child(l)
		c.tooltip_text = "Room on the farm" if where == "farm" else "Empty: drop a kin here"
		return c
	var sp: Dictionary = Data.KIN[rec["species"]]
	var stack := Control.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(stack)
	var pic := KinPortrait.view(rec, _tree(), 52.0)
	pic.position = Vector2(4, 2)
	pic.size = Vector2(52, 52)
	stack.add_child(pic)
	var lv := UI.label(str(int(rec.get("level", 1))), 11, UI.INK, UI.semi)
	lv.position = Vector2(0, -2)
	lv.add_theme_constant_override("outline_size", 4)
	lv.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	stack.add_child(lv)
	var bdg := Mutations.badges(rec, 13.0)
	bdg.add_theme_constant_override("separation", 1)
	bdg.position = Vector2(CELL.x - 8 - 14 * mini(3, bdg.get_child_count()), -1)
	while bdg.get_child_count() > 3: bdg.get_child(bdg.get_child_count() - 1).free()
	stack.add_child(bdg)
	if String(rec["uid"]) == str(Save.d.get("active", "")):
		var pw := Icons.Glyph.new("paw", UI.GOLD, 14.0)
		pw.position = Vector2(0, 38)
		stack.add_child(pw)
	var nm := UI.label(String(rec["name"]), 11, sp["color"].lerp(UI.INK, 0.55))
	nm.autowrap_mode = TextServer.AUTOWRAP_OFF
	nm.clip_text = true
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.position = Vector2(-2, 53)
	nm.size = Vector2(CELL.x - 4, 16)
	stack.add_child(nm)
	if _searching() and not KinBox.matches(rec, query, filter):
		c.modulate = Color(1, 1, 1, 0.22)
	var tags := Mutations.tags(rec)
	c.tooltip_text = "%s the %s%s\nLevel %d  ·  trust %d%s\nClick to see it, drag to move, right click to send it %s" % [rec["name"], (" ".join(tags) + " ") if not tags.is_empty() else "", Evo.form_name(rec),
		int(rec.get("level", 1)), int(rec.get("trust", 0)), "  ·  your partner" if String(rec["uid"]) == str(Save.d.get("active", "")) else "", "to the burrow" if where == "farm" else "to the farm"]
	var r: Dictionary = rec
	c.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			if e.button_index == MOUSE_BUTTON_RIGHT or (e.button_index == MOUSE_BUTTON_LEFT and e.double_click):
				_quick(r)
			elif e.button_index == MOUSE_BUTTON_LEFT:
				sel = String(r["uid"]); confirm = ""
				Sfx.play("hover", null, -6.0)
				refresh())
	return c

func _drag(rec: Dictionary, from: Control):
	if rec.is_empty():
		return null
	var pv := KinPortrait.view(rec, _tree(), 56.0)
	pv.modulate = Color(1, 1, 1, 0.85)
	var holder := Control.new()
	holder.add_child(pv)
	pv.position = Vector2(-28, -28)
	from.set_drag_preview(holder)
	sel = String(rec["uid"])
	return {"kin_uid": String(rec["uid"])}

func _can_drop(_p, d) -> bool:
	return typeof(d) == TYPE_DICTIONARY and d.has("kin_uid")

## A kin dropped somewhere: onto the farm, an empty box cell, or another kin (they swap).
func _drop_on(d: Dictionary, where: String, onto, slot := -1) -> void:
	var rec := Save.kin(String(d.get("kin_uid", "")))
	if rec.is_empty(): return
	var why := ""
	var other: Dictionary = onto if typeof(onto) == TYPE_DICTIONARY else {}
	if other == rec: return
	if where == "farm":
		if not KinBox.is_boxed(rec): return        # farm to farm: nothing to do
		if not other.is_empty() and not KinBox.is_boxed(other):
			why = KinBox.swap(other, rec)
			if why == "": _done("%s came out, %s went to sleep in the burrow" % [rec["name"], other["name"]]); return
		else:
			why = KinBox.to_farm(rec)
			if why == "": _done("%s is out on the farm" % rec["name"]); return
	else:
		why = KinBox.to_box(rec, slot)
		if why == "":
			_done(("%s and %s traded places" % [rec["name"], other["name"]]) if not other.is_empty() else "%s is in %s" % [rec["name"], KinBox.page_name(page if slot < 0 else slot / KinBox.PAGE)])
			return
	_fail(why)

## Right click / double click: straight across to the other side.
func _quick(rec: Dictionary) -> void:
	sel = String(rec["uid"])
	if KinBox.is_boxed(rec):
		var why := KinBox.to_farm(rec)
		if why == "": _done("%s is out on the farm" % rec["name"])
		else: _fail(why)
	else:
		var why := KinBox.to_box(rec, KinBox.free_slot({}, page))
		if why == "": _done("%s went to sleep in %s" % [rec["name"], KinBox.page_name(KinBox.page_of(rec))])
		else: _fail(why)

# ------------------------------------------------------------------ the side panel
func _build_detail() -> void:
	for ch in detail.get_children(): ch.queue_free()
	var rec := Save.kin(sel)
	if rec.is_empty():
		detail.add_child(UI.section("The Kin Burrow"))
		for t in ["Your farm has room for %d kin. Everyone else sleeps here, safe and warm: kin in the burrow don't get hungry, don't need looking after and don't wander." % KinBox.farm_cap(),
				"Click a kin to see it. Drag it to the farm, into a box, or onto another kin to swap them. Right click sends it straight across.",
				"New kin go to the farm when there's room. Repeats of a kind you already have out go to the burrow, unless they shimmer or carry a rare mutation.",
				"Your partner and your first kin always stay out. Pick a sleeping kin for an expedition and it comes out to go with you."]:
			var l := UI.label(t, 13, UI.MUTED); l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = 270
			detail.add_child(l)
		return
	var sp: Dictionary = Data.KIN[rec["species"]]
	var col: Color = Shiny.body(rec)
	var top := UI.hbox(10)
	top.add_child(KinPortrait.view(rec, _tree(), 76.0))
	var tv := UI.vbox(1)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nl := UI.title(String(rec["name"]), 22, col.lerp(UI.INK, 0.35))
	nl.clip_text = true
	tv.add_child(nl)
	tv.add_child(UI.label("Level %d %s  ·  %s" % [int(rec["level"]), Evo.form_name(rec), String(sp["type"]).capitalize()], 13, UI.INK))
	var where := KinBox.went_text(rec) if KinBox.is_boxed(rec) else "Out on the farm"
	if String(rec["uid"]) == str(Save.d.get("active", "")): where = "Your partner, on the farm"
	tv.add_child(UI.label(where, 12, Color("cdb8ff") if KinBox.is_boxed(rec) else UI.GOOD))
	top.add_child(tv)
	detail.add_child(top)
	if rec.get("shimmer", false):
		detail.add_child(_rare_row("shimmer", "Shimmering", "rare colours", Color("fff0a0")))
	for mid in Mutations.of(rec):
		detail.add_child(_rare_row(mid, Mutations.name_of(mid), Mutations.perk_text(mid), Mutations.col_of(mid)))
	var bd: Array = Care.bond(rec)
	var joined := ""
	if float(rec.get("got_t", 0.0)) > 0.0:
		var dt := Time.get_datetime_dict_from_unix_time(int(rec["got_t"]))
		joined = "  ·  joined %d-%02d-%02d" % [dt["year"], dt["month"], dt["day"]]
	detail.add_child(UI.label("Trust %d  ·  %s bond%s" % [int(rec.get("trust", 0)), bd[1], joined], 12, Color("ffb3c6")))
	var cond := ("Asleep, needs on hold (%s)" % Care.condition_name(rec).to_lower()) if KinBox.is_boxed(rec) else Care.condition_name(rec)
	if rec.has("parents"): cond += "  ·  child of %s and %s" % [rec["parents"][0], rec["parents"][1]]
	var cl := UI.label(cond, 12, UI.MUTED)
	cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cl.custom_minimum_size.x = 280
	detail.add_child(cl)
	var btns := HFlowContainer.new()
	btns.add_theme_constant_override("h_separation", 6); btns.add_theme_constant_override("v_separation", 6)
	var r: Dictionary = rec
	if KinBox.is_boxed(rec):
		var fb := UI.primary("Send to farm", func():
			var why := KinBox.to_farm(r)
			if why == "": _done("%s is out on the farm" % r["name"])
			else: _fail(why), 130)
		btns.add_child(fb)
	else:
		var bb := UI.button("Put in burrow", func():
			var why := KinBox.to_box(r, KinBox.free_slot({}, page))
			if why == "": _done("%s went to sleep in %s" % [r["name"], KinBox.page_name(KinBox.page_of(r))])
			else: _fail(why), 130)
		bb.disabled = KinBox.pinned(rec) != ""
		bb.tooltip_text = KinBox.pinned(rec)
		btns.add_child(bb)
	btns.add_child(UI.button("Details", func():
		if home and home.has_method("_open_kin"): home._open_kin(r), 90))
	if String(rec["uid"]) != str(Save.d.get("active", "")):
		btns.add_child(UI.button("Make partner", func():
			var swapped := KinBox.bring_out(r)
			if Save.d.get("active2", "") == r["uid"]: Save.d["active2"] = Save.d.get("active", "")
			Save.d["active"] = r["uid"]
			_done("%s is your partner%s" % [r["name"], (" (%s went to the burrow to make room)" % swapped["name"]) if not swapped.is_empty() else ""]), 120))
	if confirm == String(rec["uid"]):
		var cr := UI.vbox(6)
		var rcl := UI.label("Let %s go for good? It goes back to the wild and won't come back." % rec["name"], 13, UI.BAD)
		rcl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rcl.custom_minimum_size.x = 260
		cr.add_child(rcl)
		var yr := UI.hbox(6)
		yr.add_child(UI.button("Yes, release", func():
			var nm := String(r["name"])
			var why := KinBox.release(r)
			confirm = ""
			if why == "":
				sel = ""
				_done("%s went back to the wild. Goodbye, %s" % [nm, nm])
			else: _fail(why), 130))
		yr.add_child(UI.button("Keep it", func(): confirm = ""; refresh(), 90))
		cr.add_child(yr)
		detail.add_child(btns)
		detail.add_child(cr)
		return
	var rel := UI.button("Release", func(): confirm = String(r["uid"]); refresh(), 90)
	var rwhy := KinBox.pinned(rec)
	if rwhy == "" and (Save.d["roster"] as Array).size() <= 1: rwhy = "It's your only kin"
	rel.disabled = rwhy != ""
	rel.tooltip_text = rwhy if rwhy != "" else "Let it go back to the wild"
	btns.add_child(rel)
	detail.add_child(btns)

func _rare_row(id: String, nm: String, txt: String, col: Color) -> Control:
	var h := UI.hbox(6)
	h.add_child(Mutations.Badge.new(id, 18.0))
	var l := UI.label(nm, 14, col, UI.semi)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	h.add_child(l)
	var dl := UI.label(txt, 12, UI.MUTED)
	dl.autowrap_mode = TextServer.AUTOWRAP_OFF
	dl.clip_text = true
	dl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dl.custom_minimum_size.x = 60
	h.add_child(dl)
	h.tooltip_text = "%s: %s" % [nm, String(Mutations.info(id).get("desc", "Rare colours, turned round the colour wheel."))] + ("" if id == "shimmer" else " (%s)" % txt)
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	return h

# ------------------------------------------------------------------ tooling: --kinbox-demo[=box|lineup|card]
## A made-up collection for screenshots: a full farm and three pages of kin in the burrow, some of
## them rare. Never written to the save.
static func demo_roster() -> void:
	Save.no_write = true
	var rng := RandomNumberGenerator.new(); rng.seed = 77
	var sps: Array = Data.KIN.keys().filter(func(k): return not Data.KIN[k].get("rare", false))
	var first: Dictionary = Save.active_kin()
	if first.is_empty():
		first = Save.new_kin(sps[0], "Pip"); Save.d["roster"].append(first); Save.d["active"] = first["uid"]
	first["starter"] = true
	var mids := Mutations.ids()
	for i in 72:
		var r := Save.new_kin(sps[i % sps.size()])
		r["level"] = 1 + rng.randi() % 18
		r["trust"] = rng.randf_range(10.0, 90.0)
		Evo.simulate(r, rng)
		if i % 5 == 0: r["mutations"] = [mids[(i / 5) % mids.size()]]
		if i % 13 == 3: r["shimmer"] = true
		if i == 20: r["mutations"] = ["giant", "starmarked"]; r["shimmer"] = true
		r["got_t"] = Time.get_unix_time_from_system() - (72 - i) * 3600.0
		Save.d["roster"].append(r)
		KinBox.route_new(r)
	Save.d["box"]["names"][0] = "Box 1: Keepers"
	Save.d["tutorial"]["home"] = true
	Save.d["tutorial"]["day1_done"] = true

static func demo_show(h: Node, which: String) -> void:
	match which:
		"lineup":
			var base: Vector3 = h.ppos + Vector3(-5.2, 0, -1.6)
			var list: Array = [["", false], ["", true]]
			for mid in Mutations.ids(): list.append([mid, false])
			for i in list.size():
				var r := Save.new_kin("puddlet" if i % 2 == 0 else "cindle", "Demo")
				r["level"] = 6
				if String(list[i][0]) != "": r["mutations"] = [list[i][0]]
				r["shimmer"] = list[i][1]
				var n := Models.kin(String(r["species"]), r)
				n.position = base + Vector3((i % 6) * 2.0, 0, (i / 6) * 2.4)
				n.rotation.y = PI * 0.12
				n.scale *= 1.25
				h.add_child(n)
				var lb := Label3D.new()
				lb.text = "plain" if i == 0 else ("Shimmer" if i == 1 else Mutations.name_of(String(list[i][0])))
				lb.font = UI.big; lb.font_size = 44; lb.pixel_size = 0.007; lb.outline_size = 12
				lb.modulate = Color("fff0a0") if i == 1 else (Mutations.col_of(String(list[i][0])) if i > 1 else Color.WHITE)
				lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED; lb.no_depth_test = true
				lb.position = n.position + Vector3(0, 1.75, 0.3)
				h.add_child(lb)
			h.cam.zoom_to = 0.62; h.cam.zoom = 0.62
			h.cam.snap(base + Vector3(5.0, 0, 1.4))
			h.ppos = base + Vector3(5.0, 0, 4.6)
		"card":
			var pick: Dictionary = {}
			for r in Save.d["roster"]:
				if (r.get("mutations", []) as Array).size() >= 2: pick = r
			if pick.is_empty(): pick = Save.active_kin()
			h._open_kin(pick)
		"none":
			pass
		_:
			page = 0
			sel = ""
			for r in Save.d["roster"]:
				if r.get("shimmer", false) and not Mutations.of(r).is_empty(): sel = String(r["uid"])
			if which.begins_with("page"): page = clampi(int(which.substr(4)) - 1, 0, KinBox.PAGES - 1)
			if which == "search": query = "a"; filter = "mutated"
			h._open_burrow()
