class_name Duel
extends RefCounted
## The duel room, next to the Training Grounds: you against one sparring bot hunter on an empty
## island. Pick its class, weapon, glove, difficulty and behaviour (fight / dodge only / stand
## still), reset whenever you like, and watch your numbers: damage dealt and taken, how many of your
## shots land, how many of its shots you dodge, and knocks. Nobody dies here: a knock resets the round.

const CLASSES := ["light", "medium", "heavy"]
const MODES := ["fight", "dodge", "still"]
const MODE_NAMES := {"fight": "Fights back", "dodge": "Only dodges", "still": "Stands still"}

var m: Match
var bot: Hunter = null
var cls := "medium"
var weapon := ""
var glove := ""
var diff := "medium"
var mode := "fight"
var home_at := Vector3.ZERO      # where you start each round
var bot_at := Vector3.ZERO       # where the bot starts each round
var reset_t := -1.0
var round_n := 1
var stats := {}
var _cb: Callable
var _near: Dictionary = {}       # bot shots that came close: shot -> closest distance
var _last_bot_hit := -9.0
var _test_cast := -1.0

func setup(match_node: Match) -> void:
	m = match_node
	diff = String(Settings.get_v("bot_diff")) if Data.BOT_DIFF.has(String(Settings.get_v("bot_diff"))) else "medium"
	cls = CLASSES[randi() % 3]
	weapon = ""
	_clear_stats()
	if m.player:
		home_at = m.player.pos
		bot_at = _spot_for_bot(home_at)
	for a in OS.get_cmdline_user_args():
		# tooling: --duel-glove=<id> gives the bot a glove, --duel-cast=<seconds> makes it fire it once
		if a.begins_with("--duel-glove="): glove = a.substr(13)
		if a.begins_with("--duel-cast="): _test_cast = float(a.substr(12))
		if a.begins_with("--duel-mode="): mode = a.substr(12)
	_cb = func(by, t, d, tags): _on_hit(by, t, d, tags)
	CombatBus.hit_landed.connect(_cb)
	spawn_bot()

func teardown() -> void:
	if _cb.is_valid() and CombatBus.hit_landed.is_connected(_cb):
		CombatBus.hit_landed.disconnect(_cb)

func _clear_stats() -> void:
	stats = {"dealt": 0.0, "taken": 0.0, "shots": 0, "hits": 0, "bot_shots": 0, "dodged": 0, "knocks": 0, "knocked": 0}

## A spot on your island 7-10 tiles away, on solid ground at your height.
func _spot_for_bot(from: Vector3) -> Vector3:
	var best := from + Vector3(6, 0, 0); var bs := -1.0
	for i in 48:
		var a := TAU * i / 48.0
		for r in [9.0, 8.0, 7.0, 6.0, 5.0]:
			var q := from + Vector3(cos(a) * r, 0, sin(a) * r)
			if m.world.is_void(q.x, q.z) or m.world.is_block(q.x, q.z):
				continue
			var gy: float = m.world.ground_at(q.x, q.z)
			if absf(gy - from.y) > 0.4:
				continue
			if not m.world.los(from + Vector3(0, 0.8, 0), Vector3(q.x, gy + 0.8, q.z), from.y + 0.8):
				continue
			var score: float = r
			if score > bs:
				bs = score; best = Vector3(q.x, gy, q.z)
			break
	return best

## (Re)makes the sparring bot with the current picks.
func spawn_bot() -> void:
	if bot and is_instance_valid(bot):
		_remove_bot()
	var pool: Array = Data.CLASSES[cls]["weapons"]
	if weapon == "" or not pool.has(weapon):
		weapon = String(pool[0])
	var kit := {"weapon": weapon, "perk": ""}
	bot = m.make_hunter(m.next_id("duel"), 1, cls, "Sparring %s" % String(Data.CLASSES[cls].get("name", cls.capitalize())), "bot", m.bot_kin_record(), bot_at, kit, {})
	bot.ai = m.bot_brain.new_mind(m.rng, float(Data.BOT_DIFF[diff]["skill"]), Data.BOT_DIFF[diff])
	bot.lives = 99
	bot.tonics = 0
	if glove != "" and Gear.ALL.has(glove):
		bot.gear[Gear.slot_of(glove)] = {"id": glove, "rar": 2}
		bot.refresh_gear()
	reset()

func _remove_bot() -> void:
	m.hunters.erase(bot)
	if bot.kin:
		m.kins.erase(bot.kin)
		m.bubbles = m.bubbles.filter(func(b): return b["ent"] != bot.kin)
		bot.kin.queue_free()
	bot.queue_free()
	bot = null

## Back to your marks, both healed, cooldowns kept.
func reset() -> void:
	reset_t = -1.0
	for h in [m.player, bot]:
		if h == null:
			continue
		h.downed = false
		h.out = false
		h.hp = h.max_hp
		h.armor = h.max_armor
		h.down_hp = 0.0
		h.stun_t = 0.0
		h.inv_t = 0.6
		h.vel = Vector3.ZERO
		h.teleport(home_at if h == m.player else bot_at)
		if h.kin and (h.kin as Kin).state != "shoulder":
			(h.kin as Kin).recall()
	_near.clear()
	m.fx.ring(home_at, 1.6, Color("8fe3c8"), 0.35)
	m.fx.ring(bot_at, 1.6, Color("ff8a7a"), 0.35)
	m.sfx("revive", null, -8.0, 1.2)

func heal_both() -> void:
	for h in [m.player, bot]:
		if h:
			h.hp = h.max_hp
			h.armor = h.max_armor

func tick(dt: float) -> void:
	if bot == null or m.player == null:
		return
	if _test_cast > 0.0 and m.time >= _test_cast:
		_test_cast = -1.0
		bot.inp["aim"] = m.player.pos
		m.use_gear(bot, 0)
	# a knock ends the round; both come back after a beat
	if reset_t < 0.0 and (m.player.downed or bot.downed):
		reset_t = 1.4
		if bot.downed:
			stats["knocks"] = int(stats["knocks"]) + 1
			m.hud.toast("Knock! Round %d to you" % round_n, Color("8fe3c8"))
		else:
			stats["knocked"] = int(stats["knocked"]) + 1
			m.hud.toast("Knocked. Round %d to the bot" % round_n, Color("ff8a7a"))
		round_n += 1
	if reset_t >= 0.0:
		reset_t -= dt
		if reset_t <= 0.0:
			reset()
	# watch the bot's shots: one that comes close and doesn't hurt you is a dodge
	var live := {}
	for s in m.shots:
		if s["by"] == bot:
			var sid := int(s.get("sid", 0))
			var d := Vector2(float(s["pos"].x) - m.player.pos.x, float(s["pos"].z) - m.player.pos.z).length()
			live[sid] = true
			if not _near.has(sid):
				_near[sid] = d
				stats["bot_shots"] = int(stats["bot_shots"]) + 1
			else:
				_near[sid] = minf(float(_near[sid]), d)
	for sid in _near.keys():
		if not live.has(sid):
			if float(_near[sid]) < 1.6 and m.time - _last_bot_hit > 0.12:
				stats["dodged"] = int(stats["dodged"]) + 1
			_near.erase(sid)

## Runs right after the bots think: the behaviour toggle trims what the sparring bot may do.
func after_think() -> void:
	if bot == null:
		return
	match mode:
		"still":
			bot.inp["move"] = Vector2.ZERO
			for k in ["fire", "dash", "jump", "sig", "sec", "ult", "gear1", "throw"]:
				bot.inp[k] = false
		"dodge":
			for k in ["fire", "sig", "sec", "ult", "gear1", "throw"]:
				bot.inp[k] = false

func note_shot(by: Ent) -> void:
	if by == m.player:
		stats["shots"] = int(stats["shots"]) + 1

func _on_hit(by, t, d, tags) -> void:
	if bot == null or m.player == null:
		return
	var credit = by
	if by is Kin and (by as Kin).owner_h:
		credit = (by as Kin).owner_h
	if credit == m.player and t == bot:
		stats["dealt"] = float(stats["dealt"]) + float(d)
		if (tags as Array).has("primary") or (tags as Array).has("shot") or (tags as Array).has("melee"):
			stats["hits"] = int(stats["hits"]) + 1
	elif credit == bot and t == m.player:
		stats["taken"] = float(stats["taken"]) + float(d)
		_last_bot_hit = m.time

# ---- the setup menu (B): picks, applied by respawning the bot
func cycle(what: String, step := 1) -> void:
	match what:
		"cls":
			cls = CLASSES[(CLASSES.find(cls) + step + 3) % 3]
			weapon = ""
		"weapon":
			var pool: Array = Data.CLASSES[cls]["weapons"]
			weapon = String(pool[(pool.find(weapon) + step + pool.size()) % pool.size()])
		"glove":
			var keys: Array = [""] + Gear.ALL.keys().filter(func(g): return Gear.active(String(g)))
			keys.sort()
			glove = String(keys[(keys.find(glove) + step + keys.size()) % keys.size()])
		"diff":
			var order: Array = Data.BOT_ORDER
			diff = String(order[(order.find(diff) + step + order.size()) % order.size()])
		"mode":
			mode = MODES[(MODES.find(mode) + step + MODES.size()) % MODES.size()]
			return       # behaviour changes on the fly, no respawn
	spawn_bot()

func pick_text(what: String) -> String:
	match what:
		"cls": return String(Data.CLASSES[cls].get("name", cls.capitalize()))
		"weapon": return String(Data.weapon_stats(weapon, 0).get("name", weapon)) if weapon != "" else "-"
		"glove": return String(Gear.ALL[glove]["name"]) if glove != "" and Gear.ALL.has(glove) else "None"
		"diff": return String(Data.BOT_DIFF[diff]["name"])
		"mode": return String(MODE_NAMES[mode])
	return ""

# ---- keys and the menu
var keys_node: Node = null
var menu_layer: CanvasLayer = null

## B opens the setup menu, X resets the round. A little node so keys work even while paused.
class DuelKeys extends Node:
	var d: Duel
	func _init(owner_duel: Duel) -> void:
		d = owner_duel
		process_mode = Node.PROCESS_MODE_ALWAYS
	func _unhandled_input(e: InputEvent) -> void:
		if not (e is InputEventKey and e.pressed and not e.echo):
			return
		var k := (e as InputEventKey).physical_keycode
		if k == KEY_B:
			if d.menu_layer: d.close_menu()
			elif not Overlay.is_open(): d.open_menu()
			get_viewport().set_input_as_handled()
		elif k == KEY_X and d.menu_layer == null and not d.m.paused:
			d.reset()
			get_viewport().set_input_as_handled()
		elif k == KEY_ESCAPE and d.menu_layer:
			d.close_menu()
			get_viewport().set_input_as_handled()

func attach_keys() -> void:
	keys_node = DuelKeys.new(self)
	m.add_child(keys_node)

func open_menu() -> void:
	m.paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu_layer = CanvasLayer.new()
	menu_layer.layer = 40
	m.add_child(menu_layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = UI.theme()
	menu_layer.add_child(root)
	var shade := ColorRect.new(); shade.color = Color(0, 0, 0, 0.4)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)
	var center := CenterContainer.new(); center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var pb := UI.scroll_panel("Sparring bot", 520, close_menu, "Done")
	center.add_child(pb[0])
	_fill_menu(pb[1])
	UI.pop_in(pb[0])

func _fill_menu(v: VBoxContainer) -> void:
	for ch in v.get_children():
		ch.queue_free()
	v.add_child(UI.label("Changing the class, weapon, glove or difficulty brings in a fresh bot. The behaviour switches on the spot.", 14, UI.MUTED))
	for row in [["cls", "Class"], ["weapon", "Weapon"], ["glove", "Glove (Q)"], ["diff", "Difficulty"], ["mode", "Behaviour"]]:
		var what: String = row[0]
		var h := UI.hbox(8)
		var l := UI.label(row[1], 15, UI.MUTED); l.custom_minimum_size.x = 120
		h.add_child(l)
		h.add_child(UI.button("‹", func(): cycle(what, -1); _fill_menu(v), 44))
		var val := UI.label(pick_text(what), 16, UI.INK); val.custom_minimum_size.x = 200
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.add_child(val)
		h.add_child(UI.button("›", func(): cycle(what, 1); _fill_menu(v), 44))
		v.add_child(h)
	var acts := UI.hbox(8)
	acts.add_child(UI.button("Reset round", func(): reset(); close_menu(), 150))
	acts.add_child(UI.button("Heal both", func(): heal_both(), 130))
	acts.add_child(UI.button("Clear stats", func(): _clear_stats(); round_n = 1, 130))
	v.add_child(acts)
	v.add_child(UI.label("B opens this menu  ·  X resets the round  ·  Esc leaves the room", 13, UI.MUTED))

func close_menu() -> void:
	if menu_layer:
		menu_layer.queue_free()
		menu_layer = null
	m.paused = false
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
