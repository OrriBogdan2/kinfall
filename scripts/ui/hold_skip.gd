class_name HoldSkip
extends Control
## "Hold to skip" for story scenes: a keycap with a ring around it that fills while Esc (or the
## mouse button, pressed on it) is held, and fires `skipped` when full. Letting go drains it again,
## so a stray tap never throws away a cutscene.

signal skipped

const HOLD := 0.9
var k := 0.0
var mouse_held := false
var done := false
var label_txt := "Hold to skip"

func _init() -> void:
	custom_minimum_size = Vector2(170, 44)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		mouse_held = e.pressed
		accept_event()

func _process(delta: float) -> void:
	if done:
		return
	var held := mouse_held or Input.is_action_pressed("menu")
	if mouse_held and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		mouse_held = false
	var was := k
	k = clampf(k + (delta / HOLD if held else -delta * 2.5), 0.0, 1.0)
	if held and was == 0.0 and k > 0.0:
		Sfx.play("hover", null, -10.0, 0.0, 0.8)
	if k >= 1.0:
		done = true
		Sfx.play("click")
		skipped.emit()
	queue_redraw()

func _draw() -> void:
	var c := Vector2(22, size.y * 0.5)
	var r := 16.0
	var hot := k > 0.0
	draw_circle(c, r + 3.0, Color(0, 0, 0, 0.35))
	draw_arc(c, r, 0, TAU, 40, Color(1, 1, 1, 0.18), 3.0, true)
	if k > 0.0:
		draw_arc(c, r, -PI / 2, -PI / 2 + TAU * k, 40, UI.ACCENT, 3.5, true)
	var f: Font = UI.caps if UI.caps else UI.body
	var tw := f.get_string_size("Esc", HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_string(f, c + Vector2(-tw * 0.5, 4), "Esc", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.95 if hot else 0.7))
	draw_string(UI.semi if UI.semi else UI.body, Vector2(c.x + r + 12, c.y + 5), label_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.9 if hot else 0.6))
