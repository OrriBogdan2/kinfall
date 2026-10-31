class_name WorkView
extends RefCounted
## Work elements in the menus: the element icons (Icon, drawn so they need no font or texture),
## level pips, the chips on a kin's card, and the Job Board panel (priorities per element, who's
## doing what, pinning a kin to a job or keeping it to rest).

static var tab := "Jobs"

## An element's round icon: its colour, with a little glyph (flame, drop, sprout, bolt...).
class Icon extends Control:
	var el := ""
	var px := 20.0
	func _init(e: String, size := 20.0) -> void:
		el = e; px = size
		custom_minimum_size = Vector2(size, size)
		mouse_filter = Control.MOUSE_FILTER_PASS
		tooltip_text = "%s: %s" % [Work.name_of(el), String(Work.ELEMENTS.get(el, {}).get("desc", ""))]
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		var col := Work.col_of(el)
		draw_circle(c, r, col.darkened(0.55))
		draw_arc(c, r - 0.8, 0, TAU, 24, col, maxf(1.2, r * 0.14), true)
		var g := col.lerp(Color.WHITE, 0.55)
		var s := r * 0.62
		match el:
			"ember":
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.62, s * 0.2), c + Vector2(s * 0.4, s * 0.75), c + Vector2(0, s * 0.95), c + Vector2(-s * 0.4, s * 0.75), c + Vector2(-s * 0.62, s * 0.2)]), g)
				draw_circle(c + Vector2(0, s * 0.45), s * 0.3, col.darkened(0.2))
			"tide":
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.55, s * 0.15), c + Vector2(s * 0.42, s * 0.62), c + Vector2(0, s * 0.85), c + Vector2(-s * 0.42, s * 0.62), c + Vector2(-s * 0.55, s * 0.15)]), g)
			"bloom":
				draw_line(c + Vector2(0, s * 0.9), c + Vector2(0, -s * 0.1), g, maxf(1.2, s * 0.18))
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 0.1), c + Vector2(-s * 0.8, -s * 0.5), c + Vector2(-s * 0.2, s * 0.2)]), g)
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 0.3), c + Vector2(s * 0.85, -s * 0.85), c + Vector2(s * 0.25, s * 0.05)]), g)
			"spark":
				draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.2, -s), c + Vector2(-s * 0.55, s * 0.12), c + Vector2(-s * 0.02, s * 0.12), c + Vector2(-s * 0.2, s), c + Vector2(s * 0.55, -s * 0.15), c + Vector2(s * 0.05, -s * 0.15)]), g)
			"craft":
				draw_line(c + Vector2(-s * 0.6, s * 0.75), c + Vector2(s * 0.25, -s * 0.15), g, maxf(1.5, s * 0.24))
				draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.05, -s * 0.75), c + Vector2(s * 0.85, s * 0.1), c + Vector2(s * 0.5, s * 0.45), c + Vector2(-s * 0.4, -s * 0.4)]), g)
			"forage":
				draw_arc(c + Vector2(0, -s * 0.05), s * 0.55, PI, TAU, 12, g, maxf(1.2, s * 0.16))
				draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.85, -s * 0.05), c + Vector2(s * 0.85, -s * 0.05), c + Vector2(s * 0.6, s * 0.8), c + Vector2(-s * 0.6, s * 0.8)]), g)
			"timber":
				draw_circle(c, s * 0.85, g)
				draw_arc(c, s * 0.55, 0, TAU, 16, col.darkened(0.25), maxf(1.0, s * 0.12))
				draw_arc(c, s * 0.25, 0, TAU, 12, col.darkened(0.25), maxf(1.0, s * 0.12))
			"stone":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.9, s * 0.6), c + Vector2(-s * 0.6, -s * 0.3), c + Vector2(-s * 0.1, -s * 0.75), c + Vector2(s * 0.6, -s * 0.45), c + Vector2(s * 0.9, s * 0.6)]), g)
			"frost":
				for i in 3:
					var a := PI * i / 3.0
					var dv := Vector2(cos(a), sin(a)) * s * 0.95
					draw_line(c - dv, c + dv, g, maxf(1.2, s * 0.17))
			"haul":
				var rc := Rect2(c - Vector2(s * 0.75, s * 0.7), Vector2(s * 1.5, s * 1.4))
				draw_rect(rc, g)
				draw_line(rc.position, rc.end, col.darkened(0.3), maxf(1.0, s * 0.13))
				draw_line(Vector2(rc.end.x, rc.position.y), Vector2(rc.position.x, rc.end.y), col.darkened(0.3), maxf(1.0, s * 0.13))
			"mend":
				draw_rect(Rect2(c - Vector2(s * 0.25, s * 0.85), Vector2(s * 0.5, s * 1.7)), g)
				draw_rect(Rect2(c - Vector2(s * 0.85, s * 0.25), Vector2(s * 1.7, s * 0.5)), g)
			"ranch":
				var pts := PackedVector2Array()
				for i in 20:
					var a := TAU * i / 20.0
					pts.append(c + Vector2(cos(a) * s * 0.62, sin(a) * s * (0.85 if sin(a) < 0.0 else 0.72) + s * 0.08))
				draw_colored_polygon(pts, g)
			_:
				draw_circle(c, s * 0.5, g)

## Little level dots: filled up to lv, out of Work.MAX_LV.
class Pips extends Control:
	var lv := 1
	var col := Color.WHITE
	var dot := 5.0
	func _init(level: int, c: Color, d := 5.0) -> void:
		lv = level; col = c; dot = d
		custom_minimum_size = Vector2(Work.MAX_LV * (d + 2.0), d + 2.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		for i in Work.MAX_LV:
			var p := Vector2(i * (dot + 2.0) + dot * 0.5 + 1.0, size.y * 0.5)
			if i < lv: draw_circle(p, dot * 0.5, col)
			else: draw_arc(p, dot * 0.5 - 0.5, 0, TAU, 10, Color(col, 0.35), 1.0, true)

## One element on a kin: icon, name, pips (and where a bonus level came from).
static func chip(el: String, lv: int, bonus := "", size := 22.0, with_name := true) -> Control:
	var hb := UI.hbox(5)
	hb.add_child(Icon.new(el, size))
	var tv := UI.vbox(0)
	if with_name:
		var l := UI.label(Work.name_of(el), UI.T_SMALL, Work.col_of(el).lerp(UI.INK, 0.4), UI.semi)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		tv.add_child(l)
	var pr := UI.hbox(4)
	var pp := Pips.new(lv, Work.col_of(el), 6.0)
	pp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pr.add_child(pp)
	if bonus != "":
		var bl := UI.label("+1 " + bonus, 11, UI.GOLD)
		bl.autowrap_mode = TextServer.AUTOWRAP_OFF
		pr.add_child(bl)
	tv.add_child(pr)
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(tv)
	hb.tooltip_text = "%s %d: %s" % [Work.name_of(el), lv, String(Work.ELEMENTS[el]["desc"])]
	hb.mouse_filter = Control.MOUSE_FILTER_PASS
	return hb

## A row of a kin's elements, best first.
static func chips(rec: Dictionary, size := 22.0) -> Control:
	var fl := HFlowContainer.new()
	fl.add_theme_constant_override("h_separation", 14); fl.add_theme_constant_override("v_separation", 6)
	var why := Work.bonus_why(rec)
	for it in Work.list(rec):
		fl.add_child(chip(String(it[0]), int(it[1]), String(why.get(it[0], "")), size))
	return fl

## Just the icons, small (Kin Box cells).
static func icons(rec: Dictionary, px := 12.0, most := 3) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for it in Work.list(rec).slice(0, most):
		var ic := Icon.new(String(it[0]), px)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(ic)
	return v

# ------------------------------------------------------------------ the kin's card
## The Work section on a kin's card: its elements, what it's doing, and its job settings.
static func card_section(h: Node, rec: Dictionary, parent: VBoxContainer, reopen: Callable) -> void:
	parent.add_child(UI.section("Work elements", UI.FAINT.lightened(0.2)))
	parent.add_child(chips(rec, 22.0))
	var k: Dictionary = h._kin_entry(rec) if h.has_method("_kin_entry") else {}
	var doing := ""
	if h.get("hw") and not k.is_empty(): doing = h.hw.job_text(k)
	var why := Work.why_not(rec)
	var line := doing if doing != "" else (why if why != "" else ("Pinned to %s jobs" % Work.name_of(Work.pin(rec)) if Work.pin(rec) != "" else "Takes whatever it's best at"))
	if rec.get("overworked", false): line += "  ·  overworked: let it rest"
	parent.add_child(UI.para(line, 12, Color("ffb0a0") if rec.get("overworked", false) else UI.MUTED))
	var row := UI.hbox(4)
	row.add_child(UI.choice("Any job", Work.pin(rec) == "" and not rec.get("work_rest", false), func(): Work.set_pin(rec, ""); Save.save_game(); reopen.call(), 0))
	row.add_child(UI.choice("Rest only", rec.get("work_rest", false), func(): Work.set_rest(rec, not rec.get("work_rest", false)); _drop(h, rec); Save.save_game(); reopen.call(), 0))
	for it in Work.list(rec).slice(0, 3):
		var el := String(it[0])
		var b := UI.choice(Work.name_of(el), Work.pin(rec) == el, func(): Work.set_pin(rec, "" if Work.pin(rec) == el else el); _drop(h, rec); Save.save_game(); reopen.call(), 0)
		b.tooltip_text = "Pin %s to %s jobs only" % [rec["name"], Work.ELEMENTS[el]["job"].to_lower()]
		row.add_child(b)
	for b in row.get_children(): (b as Button).add_theme_font_size_override("font_size", 12)
	parent.add_child(row)

static func _drop(h: Node, rec: Dictionary) -> void:
	if h.get("hw") == null: return
	var k: Dictionary = h._kin_entry(rec)
	if not k.is_empty(): h.hw.drop(k)

# ------------------------------------------------------------------ the Job Board
static func open(h: Node) -> void:
	var v: VBoxContainer = h._new_panel("Job Board", 1010)
	UI.subtitle(v, "Farm kin take the jobs they're best at on their own. Set what matters most.")
	var hx := UI.head_extra(v)
	hx.add_child(UI.chip("seed", "%d wood" % Work.mat("wood"), Work.col_of("timber"), "Wood: from Timber kin at a Lumber Camp"))
	hx.add_child(UI.chip("seed", "%d stone" % Work.mat("stone"), Work.col_of("stone"), "Stone: from Stone kin at a Quarry"))
	hx.add_child(UI.chip("gem", "%d scrap" % int(Save.d.get("scrap", 0)), Work.col_of("craft"), "Scrap: from Craft kin at a Workbench"))
	hx.add_child(UI.chip("heart", "%d kibble" % int(Save.d["items"].get("kibble", 0)), Work.col_of("ember"), "Kibble: from Ember kin at the Hearth Oven"))
	UI.shell_tabs(v, ["Jobs", "Kin"], tab, func(t): tab = t; open(h))
	var hw = h.hw
	if tab == "Jobs":
		var counts := {}
		for j in hw.jobs: counts[j["el"]] = int(counts.get(j["el"], 0)) + 1
		var busy := {}
		for k in h.kins:
			if k.has("job"): busy[k["job"]["el"]] = (busy.get(k["job"]["el"], []) as Array) + [String(k["rec"]["name"])]
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 26); grid.add_theme_constant_override("v_separation", 8)
		v.add_child(grid)
		for el in Work.ORDER:
			grid.add_child(_job_row(h, el, int(counts.get(el, 0)), busy.get(el, [])))
	else:
		var list := UI.vbox(6)
		v.add_child(list)
		var rows: Array = hw.workers()
		if rows.is_empty():
			list.add_child(UI.empty_state("paw", "Nobody on the farm", "Kin out on the farm take jobs. Kin asleep in the Kin Burrow never work."))
		for w in rows:
			list.add_child(_kin_row(h, w))
		var nb := KinBox.boxed().size()
		if nb > 0:
			list.add_child(UI.para("%d more asleep in the Kin Burrow: kin in the burrow never work." % nb, 12, UI.FAINT))
	var ft := UI.footer(v)
	var made: Dictionary = Work.ensure()["made"]
	var bits: Array = []
	for key in ["wood", "stone", "kibble", "scrap", "watered", "sown", "tonics"]:
		if int(made.get(key, 0)) > 0: bits.append("%d %s" % [int(made[key]), key])
	var ml := UI.label(("Made so far: " + ", ".join(bits)) if not bits.is_empty() else "Build work stations (Build, Work tab) and your kin get going.", 12, UI.MUTED)
	ml.autowrap_mode = TextServer.AUTOWRAP_OFF
	ft.add_child(ml)
	UI.footer_primary(v, "Done", func(): h._close_panel(), 100)

static func _job_row(h: Node, el: String, waiting: int, who: Array) -> Control:
	var r := UI.hbox(10)
	r.custom_minimum_size.x = 470
	r.add_child(Icon.new(el, 30.0))
	var tv := UI.vbox(1)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var e: Dictionary = Work.ELEMENTS[el]
	var top := UI.hbox(8)
	var nl := UI.label("%s  ·  %s" % [e["name"], e["job"]], UI.T_BODY, Work.col_of(el).lerp(UI.INK, 0.35), UI.semi)
	nl.autowrap_mode = TextServer.AUTOWRAP_OFF
	top.add_child(nl)
	var best := ""; var bl := 0
	for k in h.kins:
		var lv := Work.level(k["rec"], el)
		if lv > bl and Work.can_work(k["rec"]): bl = lv; best = String(k["rec"]["name"])
	var st := ""
	if not who.is_empty(): st = ", ".join(who) + (" working" if who.size() > 1 else " on it")
	elif waiting > 0: st = "%d waiting" % waiting
	var sl := UI.label(st, 12, UI.GOOD if not who.is_empty() else (UI.GOLD if waiting > 0 else UI.FAINT))
	sl.autowrap_mode = TextServer.AUTOWRAP_OFF
	top.add_child(sl)
	tv.add_child(top)
	var sub := UI.label(("Best: %s (%d)" % [best, bl]) if best != "" else "No farm kin has it", 12, UI.MUTED if best != "" else Color("ff9a8a"))
	sub.autowrap_mode = TextServer.AUTOWRAP_OFF
	sub.tooltip_text = String(e["desc"])
	sub.mouse_filter = Control.MOUSE_FILTER_PASS
	tv.add_child(sub)
	r.add_child(tv)
	var seg := UI.hbox(2)
	var cur := Work.prio(el)
	for i in Work.PRIO.size():
		var pi: int = i
		var b := UI.choice(Work.PRIO[i], cur == i, func():
			Work.set_prio(el, pi)
			Save.save_game()
			if h.get("hw"):
				for k in h.kins:
					if k.has("job") and String(k["job"]["el"]) == el and pi == 0: h.hw.drop(k)
			Sfx.play("click")
			open(h), 0)
		b.add_theme_font_size_override("font_size", 12)
		b.custom_minimum_size = Vector2(54, 30)
		if i == 0 and cur == 0: b.add_theme_color_override("font_color", Color("ff9a8a"))
		seg.add_child(b)
	seg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(seg)
	return r

static func _kin_row(h: Node, w: Dictionary) -> Control:
	var k: Dictionary = w["k"]
	var rec: Dictionary = k["rec"]
	var card := UI.card(UI.CARD, 8, 10)
	var r := UI.hbox(10)
	card.add_child(r)
	r.add_child(KinPortrait.view(rec, h.get_tree(), 40.0))
	var nv := UI.vbox(0)
	nv.custom_minimum_size.x = 150
	var nl := UI.label(String(rec["name"]), UI.T_BODY, Shiny.body(rec).lerp(UI.INK, 0.5), UI.semi)
	nl.autowrap_mode = TextServer.AUTOWRAP_OFF
	nl.clip_text = true
	nv.add_child(nl)
	nv.add_child(UI.label("%s · Lv %d" % [Data.KIN[rec["species"]]["name"], int(rec["level"])], 12, UI.MUTED))
	r.add_child(nv)
	var ch := UI.hbox(10)
	ch.custom_minimum_size.x = 250
	for it in Work.list(rec).slice(0, 3):
		ch.add_child(chip(String(it[0]), int(it[1]), "", 20.0, false))
	r.add_child(ch)
	var dv := UI.vbox(0)
	dv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var el := String(w["el"])
	var dl := UI.label(String(w["text"]), 13, Work.col_of(el).lerp(UI.INK, 0.4) if el != "" else UI.MUTED, UI.semi if el != "" else null)
	dl.autowrap_mode = TextServer.AUTOWRAP_OFF
	dl.clip_text = true
	dv.add_child(dl)
	var mood := ""
	if rec.get("overworked", false): mood = "Overworked: needs a rest"
	elif Care.want(rec) != "": mood = "Wants: %s" % String(Care.NEED_INFO[Care.want(rec)]["name"]).to_lower()
	if mood != "": dv.add_child(UI.label(mood, 11, Color("ffb0a0") if rec.get("overworked", false) else UI.FAINT))
	r.add_child(dv)
	var opt := OptionButton.new()
	opt.add_item("Any job"); opt.set_item_metadata(0, "")
	opt.add_item("Rest only"); opt.set_item_metadata(1, "rest")
	var sel := 1 if rec.get("work_rest", false) else 0
	for it in Work.list(rec):
		opt.add_item("Only %s" % Work.name_of(String(it[0])))
		opt.set_item_metadata(opt.item_count - 1, String(it[0]))
		if Work.pin(rec) == String(it[0]): sel = opt.item_count - 1
	opt.select(sel)
	opt.custom_minimum_size.x = 140
	opt.item_selected.connect(func(i: int):
		var m := String(opt.get_item_metadata(i))
		if m == "rest": Work.set_rest(rec, true)
		else: Work.set_pin(rec, m)
		_drop(h, rec)
		Save.save_game()
		open(h))
	opt.tooltip_text = "Pin it to one kind of job, or keep it to resting"
	opt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(opt)
	return card
