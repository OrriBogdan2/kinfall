class_name KinSpeak
## How young kin talk: like the creatures in the old monster games, a newly hatched kin can only
## say its own name. It still gets its point across with tone, repetition and what it does.
## As it grows up and comes to trust you it picks up a few words, then short sentences, and
## finally talks freely (see Care.speech).

const SYL := {"cindle": ["Cin", "dle"], "puddlet": ["Pud", "let"], "burrlet": ["Burr", "let"],
	"zapple": ["Zap", "ple"], "pebbit": ["Peb", "bit"], "wisplet": ["Wisp", "let"]}

const FEEL := {
	"happy": ["{A}! {A}-{a}!", "{F}! {F}!", "{A}-{a}! {F}!", "{F}♪"],
	"excited": ["{F}!!", "{A}! {A}! {A}!", "{U}!!", "{A}-{A}-{A}!"],
	"question": ["{A}?", "{F}?", "{a}... {A}?", "{A}-{a}?"],
	"sad": ["{a}... {f}...", "{A}...", "{f}...", "{a}... {a}..."],
	"angry": ["{U}!", "{A}! {A} {A}!!", "Grrr... {A}!", "{A}! {U}!"],
	"sleepy": ["{f}... {b}...", "{A}... zzz...", "{a}-{a}... {f}..."],
	"scared": ["{A}?! {A}!", "{F}...!", "Eep! {A}!", "{a}-{a}-{a}!"],
	"love": ["{F}~ ♥", "{a}-{a}~", "{F}... ♥", "{A}~ {A}~"],
	"content": ["{A}.", "{F}.", "{a}-{a}.", "{F}, {a}."],
	"refuse": ["{A}. {A}.", "{A}! {A}!", "{U}. {A}."],
}

## Little things it does that say what it means without saying it.
const ACTS := {
	"food": ["(eyes the cooking pot)", "(its tummy rumbles)", "(sniffs at your pockets)", "(nudges an empty bowl toward you)"],
	"energy": ["(yawns so wide it wobbles)", "(looks over at its bed)", "(blinks very, very slowly)"],
	"clean": ["(shakes off a puff of dust)", "(scratches at a muddy patch)", "(looks at the pond, then at you)"],
	"joy": ["(drops a ball at your feet)", "(tugs at your sleeve)", "(bounces in a little circle)"],
	"hello": ["(hops over to you)", "(spins around once)", "(wiggles all over)"],
	"cold": ["(keeps its distance)", "(watches you sideways)", "(doesn't come any closer)"],
	"love": ["(rubs against your leg)", "(flops onto its back)", "(nuzzles your hand)"],
	"mean": ["(turns its back on you)", "(flattens its ears)", "(stomps off a few steps)"],
	"sorry": ["(peeks back at you)", "(inches a little closer)"],
	"full": ["(pats its round belly)", "(sits down with a happy sigh)"],
	"brave": ["(swipes at the air)", "(puffs itself up)", "(paws the ground, ready)"],
	"timid": ["(hides behind your leg)", "(looks up at you, unsure)"],
	"curious": ["(tilts its head)", "(stares at you, thinking hard)"],
	"proud": ["(puffs up proudly)", "(stands as tall as it can)"],
	"play": ["(darts off and looks back at you)", "(crouches low, tail going)"],
	"bye": ["(watches you go)", "(waves a paw)", "(follows you a few steps)"],
	"home": ["(rolls around in the grass)", "(sniffs a flower)"],
	"friends": ["(looks over at the other kin)", "(calls out to someone across the farm)"],
	"listen": ["(listens with its ears up)", "(nods along)", "(sits right in front of you)"],
}

## A few words it picks up first.
const WORDS := {"food": "food", "energy": "sleepy", "clean": "bath", "joy": "play", "love": "love", "hello": "hi",
	"mean": "no", "bye": "bye", "fight": "fight", "sorry": "okay", "thanks": "yay", "play": "play", "who": "me, me", "home": "home"}

## Short sentences for a kin that's almost talking.
const SIMPLE := {
	"food": ["{A}! Me hungry. Food?", "Food? Food please. {A}!"],
	"energy": ["Me sleepy... {a}...", "Nap time? {A}..."],
	"clean": ["Me dirty. Bath? {A}.", "Itchy! {A}! Bath?"],
	"joy": ["Play with me! {A}!", "Bored... play? {A}?"],
	"hello": ["Hi hi! {A} happy you here!", "You back! {F}!"],
	"cold": ["...hi.", "{A}. You."],
	"love": ["{A} love you too! ♥", "You best. {F}!"],
	"mean": ["No! That mean. {A}!", "Hurt... {a}..."],
	"sorry": ["Okay. {A} forgive.", "...okay. {A}."],
	"thanks": ["Yay! {A}!", "{A} happy help!"],
	"full": ["Full! Belly big. {A}.", "No more. {A} full."],
	"fight": ["Fight! {A} ready!", "{A} go with you!"],
	"fight_timid": ["Scary... {A} stay close?", "Fight? {a}... okay."],
	"how": ["{A} good! Happy here.", "Good good. {A}!"],
	"who": ["Me {N}! {F}!", "{N}! Me {N}!"],
	"play": ["Play! Chase {A}!", "Ball! Throw ball! {A}!"],
	"bye": ["Bye... come back soon. {A}.", "Bye bye! {A}!"],
	"home": ["Home nice. {A} like.", "Farm good! {A} help!"],
	"friends": ["Friends! Other kin nice.", "{A} want visit!"],
	"remember": ["{A} remember... {M}.", "Remember! {M}. {A}!"],
	"question": ["Hmm... {A} not know.", "{A}? Good question."],
	"chat": ["{A} listen!", "Mm! {A} like talk."],
}

static func _parts(species: String) -> Dictionary:
	var s: Array = SYL.get(species, ["Kin", "kin"])
	var full: String = Data.KIN.get(species, {}).get("name", "Kin")
	return {"A": s[0], "a": String(s[0]).to_lower(), "b": String(s[1]).to_lower(), "F": full, "f": full.to_lower(), "U": full.to_upper()}

static func fill(species: String, pattern: String, rec := {}) -> String:
	var p := _parts(species)
	var out := pattern
	for k in p:
		out = out.replace("{" + k + "}", String(p[k]))
	out = out.replace("{N}", String(rec.get("name", p["F"])))
	return out.substr(0, 1).to_upper() + out.substr(1)

static func _pick(arr: Array, salt: int) -> String:
	return String(arr[absi(salt) % arr.size()])

static func babble(species: String, feel: String, salt := -1) -> String:
	if salt < 0: salt = randi()
	return fill(species, _pick(FEEL.get(feel, FEEL["content"]), salt))

## A line for a speech bubble at home, with no question asked: greetings and reactions.
static func say(rec: Dictionary, feel: String, act_key := "", salt := -1) -> String:
	if salt < 0: salt = randi()
	var s := babble(rec["species"], feel, salt)
	if act_key != "" and ACTS.has(act_key):
		s += " " + _pick(ACTS[act_key], salt / 3)
	return s

## Answers something you said, at the kin's level of speech. Fluent kin use KinBrain.
static func reply(rec: Dictionary, text: String) -> String:
	var stage := Care.speech(rec)
	if stage >= 3:
		return KinBrain.reply(rec, text)
	var intent := KinBrain.intent_of(text)
	var salt := absi(text.to_lower().hash())
	var trust := float(rec.get("trust", 50.0))
	var tr: Dictionary = rec.get("traits", {})
	var want := Care.want(rec)
	var cold := trust < 30.0
	var feel := "content"
	var act := "listen"
	var key := intent
	match intent:
		"hello":
			feel = "sad" if cold else "happy"; act = "cold" if cold else "hello"
			key = "cold" if cold else "hello"
		"bye": feel = "sad"; act = "bye"
		"sorry": feel = "question" if cold else "love"; act = "sorry"
		"thanks": feel = "happy"; act = "hello"
		"love": feel = "question" if cold else "love"; act = "cold" if cold else "love"
		"mean": feel = "angry" if float(tr.get("temper", 0.5)) > 0.6 else "sad"; act = "mean"
		"food":
			if Care.need(rec, "food") > 85.0:
				feel = "content"; act = "full"; key = "full"
			else:
				feel = "excited"; act = "food"
		"fight":
			if float(tr.get("bravery", 0.5)) > 0.55 and not cold:
				feel = "excited"; act = "brave"
			else:
				feel = "scared"; act = "timid"; key = "fight_timid"
		"how":
			if want != "":
				feel = "sleepy" if want == "energy" else ("sad" if Care.condition(rec) < 40.0 else "question")
				act = want; key = want
			else:
				feel = "happy"; act = "love"
		"who": feel = "excited"; act = "proud"
		"play": feel = "excited"; act = "play"
		"home": feel = "happy"; act = "home"
		"friends": feel = "happy"; act = "friends"
		"remember", "question": feel = "question"; act = "curious"
		_:
			# nothing it understands: it answers with how it feels, and hints at what it wants
			if want != "":
				feel = "sleepy" if want == "energy" else "question"; act = want; key = want
			else:
				feel = "happy" if trust > 55.0 else "content"
	if stage == 2:
		var mem: Array = rec.get("memory", [])
		var m := String(mem[-1]["text"]).trim_prefix("you ") if mem.size() > 0 else "farm"
		var line := fill(rec["species"], _pick(SIMPLE.get(key, SIMPLE["chat"]), salt), rec).replace("{M}", " ".join(m.split(" ").slice(0, 4)))
		return line + (" " + _pick(ACTS[act], salt / 7) if salt % 3 == 0 else "")
	var s := babble(rec["species"], feel, salt)
	if stage == 1:
		var w: String = WORDS.get(key, WORDS.get(intent, ""))
		if w != "":
			var p := _parts(rec["species"])
			var punct := "?" if feel == "question" else ("..." if feel in ["sad", "sleepy"] else "!")
			s = "%s ...%s%s %s!" % [s, w, punct, p["A"]]
	return s + " " + _pick(ACTS.get(act, ACTS["listen"]), salt / 5)

## What a young kin shouts in a match.
static func bark(rec: Dictionary, cat: String) -> String:
	var sp: String = rec.get("species", "cindle")
	var stage := Care.speech(rec)
	var feel := "content"
	var word := ""
	match cat:
		"throw": feel = "excited"; word = "Go"
		"refuse": feel = "refuse"; word = "No"
		"hesitate": feel = "question"; word = "Okay"
		"scared": feel = "scared"; word = "Ow"
		"revive": feel = "excited"; word = "Up"
		"revive_low": feel = "sad"
		"callout": feel = "excited"; word = "Look"
		"wild": feel = "question"; word = "Friend"
		"kill": feel = "happy"; word = "Yay"
		"owner_down": feel = "scared"; word = "No"
		"caught": feel = "happy"; word = "Friend"
		"extract": feel = "love"; word = "Home"
	var s := babble(sp, feel)
	if stage >= 1 and word != "" and randf() < 0.6:
		s = "%s! %s" % [word, s]
	return s
