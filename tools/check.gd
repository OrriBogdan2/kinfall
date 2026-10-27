extends RefCounted
## godot --headless -s res://tools/check.gd : compiles every script and reports errors.
func run() -> void:
	var bad := 0
	for f in _scan("res://scripts"):
		var s = load(f)
		if s == null or (s is GDScript and not s.can_instantiate()):
			print("FAIL ", f); bad += 1
	print("CHECK DONE, failures: ", bad)
func _scan(dir: String) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	for f in d.get_files():
		if f.ends_with(".gd"): out.append(dir + "/" + f)
	for sub in d.get_directories():
		out += _scan(dir + "/" + sub)
	return out
