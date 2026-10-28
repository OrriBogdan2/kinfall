extends RefCounted
## Prints how kin answer at each speech stage, for checking by eye.
func run() -> void:
	for st in [[1, 40.0], [5, 45.0], [9, 60.0], [13, 80.0]]:
		var rec := Save.new_kin("cindle", "Pip")
		rec["level"] = st[0]; rec["trust"] = st[1]
		Care.ensure(rec)
		rec["needs"]["food"] = 20.0
		print("--- stage ", Care.speech(rec), " lv ", st[0])
		for t in ["hi!", "how are you?", "are you hungry?", "let's go fight", "I love you", "you're useless", "what's up with the weather", "who are you?"]:
			print("  > ", t, "  =>  ", KinSpeak.reply(rec, t))
		for c in ["throw", "refuse", "scared", "kill"]:
			print("  [", c, "] ", KinSpeak.bark(rec, c))
