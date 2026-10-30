class_name ScreenFade
extends CanvasLayer
## Covers the window while one screen is swapped for another, so the game never hard-cuts or shows
## a frozen half-built frame. It sweeps in as a ragged ink wipe, holds while the next screen builds,
## then sweeps back out. At boot it starts fully covered, showing the logo over the same ink colour
## as the boot splash, so the splash flows straight into the title.

const INK := Color(0.02, 0.015, 0.035)

var rect: ColorRect
var logo: TextureRect
var _tw: Tween
var covered := false

func _init() -> void:
	layer = 120
	name = "ScreenFade"

func _ready() -> void:
	rect = ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/ink_wipe.gdshader")
	rect.material = m
	rect.color = Color(INK, 0.0)
	add_child(rect)
	logo = TextureRect.new()
	logo.texture = load("res://art/splash.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.set_anchors_preset(Control.PRESET_TOP_LEFT)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo.modulate.a = 0.0
	add_child(logo)

## Keeps the logo exactly where and how big the boot splash drew it (native size, shrunk only to
## fit the window), whatever the interface scale is, so the hand-off is seamless.
func _process(_d: float) -> void:
	if logo.modulate.a <= 0.0:
		return
	var win := Vector2(get_tree().root.size)
	var img := Vector2(1100, 420)
	var k := minf(1.0, minf(win.x / img.x, win.y / img.y))
	var sc := maxf(0.01, get_tree().root.content_scale_factor)
	var sz := img * k / sc
	logo.size = sz
	logo.position = (win / sc - sz) * 0.5

## Starts fully covered with the logo showing (used once, at boot).
func boot() -> void:
	rect.color.a = 1.0
	logo.modulate.a = 1.0
	covered = true
	rect.mouse_filter = Control.MOUSE_FILTER_STOP

## Sweeps the ink in until the window is covered.
func cover(dur := 0.3) -> void:
	if covered:
		return
	covered = true
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	if _tw: _tw.kill()
	_tw = create_tween()
	_tw.tween_property(rect, "color:a", 1.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await _tw.finished

## Sweeps the ink back out, revealing whatever is underneath. The logo (if showing) fades first.
func reveal(dur := 0.5) -> void:
	if not covered:
		return
	covered = false
	if _tw: _tw.kill()
	_tw = create_tween()
	if logo.modulate.a > 0.0:
		_tw.tween_property(logo, "modulate:a", 0.0, 0.25)
	_tw.tween_property(rect, "color:a", 0.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tw.tween_callback(func(): rect.mouse_filter = Control.MOUSE_FILTER_IGNORE)
	await _tw.finished

## Waits a few rendered frames (so a screen that just built has actually drawn), then reveals.
func reveal_after(frames := 3, dur := 0.5) -> void:
	for i in frames:
		await get_tree().process_frame
	await reveal(dur)
