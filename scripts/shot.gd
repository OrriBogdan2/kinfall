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
		var img := get_viewport().get_texture().get_image()
		img.save_png(path); print("SHOT ", path); get_tree().quit()
