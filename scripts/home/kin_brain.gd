class_name KinBrain
## Specific things come first in INTENTS, so "hi, how are you?" is answered as "how are you".
## How a kin answers when Claude can't be reached (desktop builds, or the page wasn't allowed to
## ask). It reads what you said, then answers in the kin's own temperament, trust and memories,
## so a reply always responds to you instead of being a random line.

const INTENTS := [
	["sorry", ["sorry", "apolog", "my bad", "forgive", "didn't mean", "didnt mean"]],
	["thanks", ["thank", "thx", "ty", "appreciate"]],
	["love", ["love you", "best kin", "good kin", "good job", "proud", "well done", "you're great", "youre great", "amazing", "cute"]],
	["mean", ["stupid", "useless", "hate", "bad kin", "worst", "idiot", "shut up", "annoying"]],
	["how", ["how are you", "how're you", "how do you feel", "you ok", "you okay", "feeling", "how's it going", "hows it going"]],
	["food", ["hungry", "eat", "food", "snack", "treat", "berry", "berries", "dinner", "lunch"]],
	["fight", ["fight", "match", "expedition", "throw", "battle", "hollow", "warden", "extract", "dungeon", "go out"]],
	["home", ["farm", "garden", "home", "island", "crop", "plant", "house", "cottage"]],
	["remember", ["remember", "last time", "yesterday", "what happened", "memory"]],
	["who", ["who are you", "your name", "what are you", "tell me about yourself", "about you"]],
	["friends", ["friend", "other kin", "guild", "town", "visit"]],
	["play", ["play", "game", "fun", "tag", "bored"]],
	["bye", ["bye", "goodnight", "good night", "see you", "later", "cya"]],
	["hello", ["hi", "hello", "hey", "yo", "morning", "evening", "sup"]],
]

static func intent_of(text: String) -> String:
	var t := " " + text.to_lower().strip_edges() + " "
	for pair in INTENTS:
		for w in pair[1]:
			# short words must stand alone ("hi" shouldn't match "this")
			if w.length() <= 3:
				var re := RegEx.create_from_string("\\b" + w + "\\b")
				if re.search(t): return pair[0]
			elif t.contains(w):
				return pair[0]
	if t.strip_edges().ends_with("?"):
		return "question"
	return "chat"

static func reply(rec: Dictionary, text: String) -> String:
	var tr: Dictionary = rec["traits"]
	var trust := float(rec["trust"])
	var mood := "warm" if trust > 70.0 else ("cold" if trust < 30.0 else "neutral")
	var bold := float(tr.get("bravery", 0.5)) > 0.62
	var hot := float(tr.get("temper", 0.5)) > 0.62
	var curious := float(tr.get("curiosity", 0.5)) > 0.62
	var loyal := float(tr.get("loyalty", 0.5)) > 0.62
	var mem: Array = rec.get("memory", [])
	var last := String(mem[-1]["text"]) if mem.size() > 0 else ""
	var lines: Array = []
	match intent_of(text):
		"hello":
			lines = {"warm": ["Hi! I was hoping you'd come over.", "There you are! I saved you a spot in the sun."],
				"neutral": ["Hey. What's up?", "Oh, hi."], "cold": ["...hi.", "Oh. It's you."]}[mood]
		"bye":
			lines = ["Okay. Don't be gone long.", "See you soon. I'll watch the crops."] if mood != "cold" else ["Fine.", "Bye, I guess."]
		"sorry":
			if mood == "cold": lines = ["...okay. Just don't do it again.", "Words are easy. We'll see."]
			else: lines = ["It's okay. I know you didn't mean it.", "Thanks for saying that. We're good."]
		"thanks":
			lines = ["Anytime!", "Of course. That's what partners do."] if mood != "cold" else ["Sure.", "Mm."]
		"love":
			if mood == "cold": lines = ["...you mean that?", "Hm. Maybe you're not so bad."]
			else: lines = ["Hehe. You're my favourite hunter.", "Stop it, you'll make my ears go hot."]
		"mean":
			lines = ["Hey! That's not fair!", "Say that again and I'm not jumping for you."] if hot else ["...that hurt, you know.", "Okay. I'll be over here."]
		"how":
			if mood == "cold": lines = ["Tired. Bruised. Thanks for asking, I guess."]
			elif bold: lines = ["Itching for another run, honestly.", "Great! My claws are sharp and I'm ready."]
			else: lines = ["Pretty good! It's quiet here.", "Happy. The island smells like rain today."]
		"food":
			lines = ["Yes! Emberberries please.", "If you have a treat I won't say no."] if mood != "cold" else ["I'll eat. Doesn't mean we're friends."]
		"fight":
			if mood == "cold": lines = ["Only if you stop throwing me at everything.", "I'll come. I won't promise to jump."]
			elif bold: lines = ["Let's go! Throw me at the biggest one.", "I'm ready. Point me at something."]
			elif loyal: lines = ["I'll go wherever you go.", "Just keep me close and I'll be fine."]
			else: lines = ["Okay... but let's be careful this time.", "If it looks scary, can we leave early?"]
		"home":
			lines = ["I like it here. Can we grow more Sunroot?", "The farm's looking good. I helped!"] if not curious else ["I found tiny footprints by the plots. Not mine.", "Did you know the pond has a frog now?"]
		"remember":
			if last != "": lines = ["I remember. I %s." % last.trim_prefix("you ") if not last.begins_with("you") else "I remember when %s." % last]
			else: lines = ["We haven't done much together yet. Let's make some memories."]
		"who":
			var sp: Dictionary = Data.KIN[rec["species"]]
			lines = ["I'm %s! A %s %s, level %d." % [rec["name"], sp["type"], sp["name"], int(rec["level"])]]
		"friends":
			lines = ["Other kin are nice, but you're my hunter.", "Can we go visit someone? I want to show off."]
		"play":
			lines = ["Tag! You're it!", "Chase me around the pond!"] if mood != "cold" else ["Not really in the mood."]
		"question":
			if curious: lines = ["Hmm. Good question. What do you think?", "I wonder about that too. Let's find out."]
			else: lines = ["I don't know. You're the hunter.", "Maybe? Ask me after a snack."]
		_:
			if last != "" and mood != "cold":
				lines = ["Mm-hm. I keep thinking about how %s." % last.trim_prefix("you "), "Okay! I'm listening."]
			elif hot: lines = ["Uh huh. Is there a point to this?", "Get to it!"]
			else: lines = ["Mm-hm. Tell me more.", "I like it when you talk to me."]
	# the same words get the same answer, so it never feels like a slot machine
	return lines[absi(text.to_lower().hash()) % lines.size()]
