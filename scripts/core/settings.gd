extends Node
## Game settings. They belong to the player, not to a save file, so every save shares them
## (user://settings.cfg). Changing one applies it right away.

signal changed(key: String)

const PATH := "user://settings.cfg"
const DEFAULTS := {
	# audio
	"master": 0.8, "music": 0.7, "sfx": 1.0, "ambience": 0.8, "mute_unfocused": false,
	# video
	"fullscreen": false, "vsync": true, "max_fps": 0, "msaa": 2, "shadows": true, "ui_scale": 1.0, "show_fps": false,
	# gameplay
	"shake": 1.0, "cam_lead": 1.0, "cam_style": "supervive", "cam_follow": "supervive", "dash_hold": false, "damage_numbers": true, "tips": true, "cast_on_press": true, "crouch_toggle": false, "mod_mode": false, "kin_auto": false, "bot_diff": "auto",
	# accessibility
	"reduce_flashes": false, "hud_opacity": 1.0,
	# controls: action -> list of "key:<physical keycode>" / "mouse:<button>"
	"keys": {}, "keys_v": 2,
}
## Bumped when the default kit changes enough that old custom bindings would be nonsense.
const KEYS_V := 2

## Rebindable actions, in the order the controls list shows them.
const ACTIONS := [
	["up", "Move up"], ["down", "Move down"], ["left", "Move left"], ["right", "Move right"],
	["fire", "Weapon attack"], ["secondary", "Weapon ability (right click)"], ["dash", "Dash"], ["jump", "Jump (hold to glide)"], ["glide", "Glide (hold in the air)"], ["crouch", "Sneak"],
	["gear1", "Glove active"], ["signature", "Kin ability"], ["throw", "Throw / recall kin"], ["ultimate", "Bond ultimate"],
	["interact", "Use, catch, revive, pet"], ["tonic", "Heal (tonic, or armor kit when health is full)"], ["scores", "Scoreboard"],
	["play", "Play fetch with a kin"], ["talk", "Talk to a kin"], ["details", "A kin's details"], ["inventory", "Inventory"],
]

var v: Dictionary = {}
var _defaults_keys := {}
var _dirty := false
var _started := false       # the bindings the game ships with, for "reset"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	v = DEFAULTS.duplicate(true)
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		for k in DEFAULTS:
			if cf.has_section_key("s", k):
				v[k] = cf.get_value("s", k)
	else:
		# older saves kept a few settings inside the save file
		var old: Dictionary = Save.d.get("settings", {})
		for pair in [["volume", "master"], ["music", "music"], ["shake", "shake"], ["cam_lead", "cam_lead"]]:
			if old.has(pair[0]): v[pair[1]] = float(old[pair[0]])
	if not cf.has_section_key("s", "keys_v") and String(v.get("cam_follow", "")) == "standard":
		v["cam_follow"] = "supervive"     # the new Supervive-style cursor lean becomes everyone's default once
	if int(v.get("keys_v", 1)) < KEYS_V or not cf.has_section_key("s", "keys_v"):
		v["keys"] = {}          # the kit changed (Q/E gloves, C kin, G throw): start from the new defaults
		v["keys_v"] = KEYS_V
	if not cf.has_section_key("s", "crouch_toggle") and OS.has_feature("web"):
		v["crouch_toggle"] = true      # browsers close the tab on Ctrl+W, so don't make people hold Ctrl
	get_tree().node_added.connect(_on_node_added)
	get_tree().root.size_changed.connect(_apply_ui_scale)

## Called by Game once the input actions exist, so saved key bindings can replace them.
func apply_all() -> void:
	for a in ACTIONS:
		_defaults_keys[a[0]] = _events_to_list(InputMap.action_get_events(a[0]))
	for k in v:
		apply(k)
	_started = true

func get_v(k: String):
	return v.get(k, DEFAULTS.get(k))

func set_v(k: String, val, write := true) -> void:
	v[k] = val
	apply(k)
	if write:
		save()
	else:
		# dragging a slider: write once things settle instead of on every step
		_dirty = true
		get_tree().create_timer(0.6).timeout.connect(func():
			if _dirty:
				_dirty = false
				save())
	changed.emit(k)

func save() -> void:
	var cf := ConfigFile.new()
	cf.load(PATH)          # keeps the other sections (the last save slot)
	for k in v:
		cf.set_value("s", k, v[k])
	cf.save(PATH)

func reset_all() -> void:
	v = DEFAULTS.duplicate(true)
	for a in _defaults_keys:
		_bind(a, _defaults_keys[a])
	for k in v:
		apply(k)
	save()
	changed.emit("")

func apply(k: String) -> void:
	match k:
		"master": AudioServer.set_bus_volume_db(0, linear_to_db(maxf(float(v[k]), 0.0001)))
		"music": Sfx.set_bus("Music", float(v[k]))
		"sfx": Sfx.set_bus("SFX", float(v[k]))
		"ambience": Sfx.set_bus("Ambience", float(v[k]))
		"fullscreen":
			# browsers only allow fullscreen from a click, so the web build doesn't restore it at startup
			if OS.has_feature("web") and not _started:
				v[k] = false
				return
			var want := DisplayServer.WINDOW_MODE_FULLSCREEN if v[k] else DisplayServer.WINDOW_MODE_WINDOWED
			if DisplayServer.window_get_mode() != want:
				DisplayServer.window_set_mode(want)
		"vsync":
			if not OS.has_feature("web"):
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if v[k] else DisplayServer.VSYNC_DISABLED)
		"max_fps": Engine.max_fps = int(v[k])
		"msaa":
			var m := int(v[k])
			get_tree().root.msaa_3d = Viewport.MSAA_4X if m >= 4 else (Viewport.MSAA_2X if m >= 2 else Viewport.MSAA_DISABLED)
		"shadows":
			for n in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
				(n as DirectionalLight3D).shadow_enabled = bool(v[k])
		"ui_scale": _apply_ui_scale()
		"keys":
			# kin throw moved off right click when heroes got secondaries
			if v[k].has("throw") and (v[k]["throw"] as Array).has("mouse:2") and not v[k].has("secondary"):
				v[k].erase("throw")
			for a in v[k]:
				_bind(a, v[k][a])

## The interface is laid out for a 1280x720 window and scales with the window both ways: smaller
## windows (a laptop browser with its toolbars) shrink it so nothing ends up off screen, and big
## ones (1440p, 4K) grow it so it reads at the same size it was designed at instead of shrinking
## to a postage stamp in the corner.
func _apply_ui_scale() -> void:
	var win := Vector2(get_tree().root.size)
	if win.x < 10.0 or win.y < 10.0:
		return
	var user := clampf(float(v.get("ui_scale", 1.0)), 0.75, 1.5)
	var fit := minf(win.y / 720.0, win.x / 1240.0)
	var f := user * fit
	# never let the user's own size setting push the layout past the window either
	f = minf(f, minf(win.y / 640.0, win.x / 1100.0))
	if absf(get_tree().root.content_scale_factor - f) > 0.001:
		get_tree().root.content_scale_factor = f

## Lights made later (every screen builds its own) follow the shadow setting too.
func _on_node_added(n: Node) -> void:
	if n is DirectionalLight3D and not bool(v.get("shadows", true)):
		(n as DirectionalLight3D).shadow_enabled = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and bool(v.get("mute_unfocused", false)):
		AudioServer.set_bus_mute(0, true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		AudioServer.set_bus_mute(0, false)

# ------------------------------------------------------------------ key bindings
func _events_to_list(evs: Array) -> Array:
	var out: Array = []
	for e in evs:
		if e is InputEventKey:
			out.append("key:%d" % (e as InputEventKey).physical_keycode)
		elif e is InputEventMouseButton:
			out.append("mouse:%d" % (e as InputEventMouseButton).button_index)
	return out

func _bind(action: String, list: Array) -> void:
	if not InputMap.has_action(action):
		return
	InputMap.action_erase_events(action)
	for s in list:
		var parts := String(s).split(":")
		if parts.size() != 2:
			continue
		if parts[0] == "key":
			var e := InputEventKey.new(); e.physical_keycode = int(parts[1])
			InputMap.action_add_event(action, e)
		elif parts[0] == "mouse":
			var m := InputEventMouseButton.new(); m.button_index = int(parts[1])
			InputMap.action_add_event(action, m)

## Replaces an action's main binding with this key or mouse button.
func rebind(action: String, ev: InputEvent) -> void:
	var list := _events_to_list(InputMap.action_get_events(action))
	var s := ""
	if ev is InputEventKey: s = "key:%d" % (ev as InputEventKey).physical_keycode
	elif ev is InputEventMouseButton: s = "mouse:%d" % (ev as InputEventMouseButton).button_index
	if s == "":
		return
	# keep any second binding (the arrow keys for moving), replace the first
	if list.size() > 0: list[0] = s
	else: list.append(s)
	_bind(action, list)
	var keys: Dictionary = v["keys"]
	keys[action] = list
	save()
	changed.emit("keys")

func binding_text(action: String) -> String:
	var names: Array = []
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			names.append(OS.get_keycode_string((e as InputEventKey).physical_keycode))
		elif e is InputEventMouseButton:
			names.append({1: "LMB", 2: "RMB", 3: "MMB", 4: "Wheel up", 5: "Wheel down", 8: "Mouse 4", 9: "Mouse 5"}.get((e as InputEventMouseButton).button_index, "Mouse %d" % (e as InputEventMouseButton).button_index))
	return " / ".join(names) if names.size() > 0 else "unbound"

## The first binding of an action, short, for HUD key caps ("E", "LMB").
func key_cap(action: String) -> String:
	var evs := InputMap.action_get_events(action)
	if evs.is_empty():
		return "?"
	var e: InputEvent = evs[0]
	if e is InputEventKey:
		return OS.get_keycode_string((e as InputEventKey).physical_keycode).to_upper()
	if e is InputEventMouseButton:
		return {1: "LMB", 2: "RMB", 3: "MMB", 8: "M4", 9: "M5"}.get((e as InputEventMouseButton).button_index, "M%d" % (e as InputEventMouseButton).button_index)
	return "?"
