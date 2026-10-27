class_name KinVoice
## What a kin says in a match. Lines depend on its strongest trait and how much it trusts you.
## If the AI wrote personal lines for this kin before the match, those are used most of the time.

const BASE := {
	"throw": {
		"bravery": ["Charging in!", "Watch this!", "Out of my way!"],
		"loyalty": ["Got your back!", "On it, partner!", "I'll handle it!"],
		"temper": ["Finally!", "They're mine!", "Let me at 'em!"],
		"curiosity": ["Ooh, what's that?", "Wheee!", "New friend? No? Okay!"],
	},
	"refuse": {
		"bravery": ["Not THAT many. No.", "Pick a fight I can win!"],
		"loyalty": ["Please, not there. We'll both get hurt.", "I want to help, but not like this."],
		"temper": ["Nope. Throw yourself.", "You throw me there, you're on your own!"],
		"curiosity": ["Hmm. I counted too many teeth.", "That looks like a bad idea."],
	},
	"hesitate": {
		"bravery": ["...fine. Going!", "Ugh. Okay!"],
		"loyalty": ["If you say so...", "Okay... trusting you."],
		"temper": ["You owe me for this!", "Fine! FINE!"],
		"curiosity": ["Uh, is that safe? Going!", "Okay okay okay!"],
	},
	"ignore": {"_": ["One sec, almost got 'em!", "Not yet!", "Finishing this!"]},
	"scared": {
		"bravery": ["Falling back!", "Too hot, coming back!"],
		"loyalty": ["I'm hurt, coming to you!", "Need a breather!"],
		"temper": ["Ow! OW! Retreating!", "That one bites back!"],
		"curiosity": ["Owie. Back to the shoulder.", "I've seen enough!"],
	},
	"revive": {
		"bravery": ["Get up! I've got you!", "Hold on, I'm coming!"],
		"loyalty": ["I'm here! Stay with me!", "Don't you dare give up!"],
		"temper": ["Get UP! We're not done!", "Seriously? Up!"],
		"curiosity": ["Is lying down a strategy? Up!", "Coming! Coming!"],
	},
	"revive_low": {"_": ["...I'll think about it.", "You keep throwing me around. Hmm.", "Do I have to?"]},
	"callout": {"_": ["Hunter %s!", "Someone's coming %s!", "Movement %s!", "Rival %s, careful!"]},
	"wild": {"_": ["A wild %s! Can we catch it?", "I smell a %s nearby!", "Look, a %s!"]},
	"kill": {"_": ["Got one!", "Down they go!", "Too easy!", "Nice!"]},
	"owner_down": {"_": ["NO!", "Hang on!", "Get up!"]},
	"caught": {"_": ["A new friend!", "Welcome to the team!", "Another one for the farm!"]},
	"extract": {"_": ["We made it!", "Home time!", "What a run!"]},
}

static func dominant(k) -> String:
	var best := "bravery"; var bv := -1.0
	for key in ["bravery", "loyalty", "temper", "curiosity"]:
		var v: float = k.t(key)
		if v > bv:
			bv = v; best = key
	return best

static func line(k, cat: String, extra := "") -> String:
	var c := cat
	if cat == "revive" and k.trust < 25.0:
		c = "revive_low"
	var custom: Array = k.lines.get(c, [])
	var pool: Array = []
	if custom.size() > 0 and randf() < 0.75:
		pool = custom
	else:
		var cat_d: Dictionary = BASE.get(c, {})
		if cat_d.has("_"):
			pool = cat_d["_"]
		else:
			pool = cat_d.get(dominant(k), [])
	if pool.is_empty():
		return ""
	var s: String = pool.pick_random()
	if "%s" in s:
		s = s % extra
	return s
