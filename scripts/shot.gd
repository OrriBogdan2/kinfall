extends Node
# Autoload used only by tooling: when started with -- --shot=path.png --frames=N it saves a screenshot and quits.
var path := ""
var frames := 60
var n := 0
func _ready():
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="): path = a.substr(7)
		elif a.begins_with("--frames="): frames = int(a.substr(9))
	if path == "": set_process(false)
func _process(_d):
	n += 1
	if n == frames:
		var img := get_viewport().get_texture().get_image()
		img.save_png(path); print("SHOT ", path); get_tree().quit()
