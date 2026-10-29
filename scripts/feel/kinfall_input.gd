class_name KinfallInput
extends RefCounted
## Registers Supervive default keybinds at runtime if the project doesn't
## already define them, so the controller works without editing project.godot.

const KEYS := {
	"kf_move_up": [KEY_W, KEY_UP],
	"kf_move_down": [KEY_S, KEY_DOWN],
	"kf_move_left": [KEY_A, KEY_LEFT],
	"kf_move_right": [KEY_D, KEY_RIGHT],
	"kf_jump": [KEY_SPACE],   # tap
	"kf_glide": [KEY_SPACE],  # hold while airborne (separate action, same key, rebindable)
	"kf_dash": [KEY_SHIFT],
	"kf_sneak": [KEY_CTRL],
	"kf_interact": [KEY_E],
	"kf_ability_q": [KEY_Q],
	"kf_ultimate": [KEY_R],
}

const MOUSE := {
	"kf_primary": MOUSE_BUTTON_LEFT,
	"kf_secondary": MOUSE_BUTTON_RIGHT,
}


static func ensure_actions() -> void:
	for action: String in KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key: Key in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	for action: String in MOUSE:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE[action]
		InputMap.action_add_event(action, mb)
