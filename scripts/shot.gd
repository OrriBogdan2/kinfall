extends Node
# Autoload used only by tooling: when started with -- --shot=path.png --frames=N it saves a screenshot and quits.
# --shot-every=S with --frames=N also saves path_1.png, path_2.png ... every S seconds of game time.
var path := ""
var frames := 60
var every := 0.0
var n := 0
var t := 0.0
var k := 0
func _ready():
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="): path = a.substr(7)
		elif a.begins_with("--frames="): frames = int(a.substr(9))
		elif a.begins_with("--shot-every="): every = float(a.substr(13))
	if path == "": set_process(false)
func _process(d):
	n += 1
	if every > 0.0:
		t += d
		if t >= every * (k + 1):
			k += 1
			get_viewport().get_texture().get_image().save_png(path.replace(".png", "_%d.png" % k))
	if n == frames:
		if "--overflow-check" in OS.get_cmdline_user_args():
			_overflow(get_tree().root)
		var img := get_viewport().get_texture().get_image()
		img.save_png(path); print("SHOT ", path); get_tree().quit()

## Tooling: lists visible controls that stick out of the window.
func _overflow(node: Node) -> void:
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return
	if node is Control:
		var c := node as Control
		var vr := c.get_viewport_rect()
		var r := c.get_global_rect()
		if r.size.x > 2 and r.size.y > 2 and c.modulate.a > 0.05 and (r.end.y > vr.size.y + 2 or r.position.y < -2 or r.end.x > vr.size.x + 2 or r.position.x < -2):
			print("OVERFLOW ", c.get_path(), " ", r, " vp ", vr.size)
			return
	for ch in node.get_children():
		_overflow(ch)
