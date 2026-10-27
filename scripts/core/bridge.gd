extends Node
## Talks to the page around the game (web build only): Claude for kin conversations and voice lines,
## and rooms for online play. Everything has an offline fallback so the game runs the same anywhere.

signal ai_ready(ok: bool)

var web := false
var js = null                  # window.kinBridge
var _keep: Array = []          # JS callbacks must stay referenced until they fire
var ai_ok := false             # Claude answered at least once this session
var ai_known := false

func _ready() -> void:
	web = OS.has_feature("web")
	if web:
		js = JavaScriptBridge.get_interface("kinBridge")

func has_page() -> bool:
	return js != null

## Asks Claude. messages: [{role, content}] ending on a user turn. cb receives the reply, or "" on any failure.
func ask(messages: Array, cb: Callable, tier := "quick") -> void:
	if js == null:
		cb.call_deferred("")
		return
	var holder := []
	var f := JavaScriptBridge.create_callback(func(args):
		var txt := str(args[0]) if args.size() > 0 else ""
		if txt != "":
			ai_ok = true
		ai_known = true
		_keep.erase(holder[0])
		cb.call(txt))
	holder.append(f)
	_keep.append(f)
	js.ask(JSON.stringify({"messages": messages, "tier": tier}), f)

func kin_brief(k: Dictionary) -> String:
	var sp: Dictionary = Data.KIN[k["species"]]
	var tr: Dictionary = k["traits"]
	var mem := []
	var m: Array = k.get("memory", [])
	for i in range(maxi(0, m.size() - 12), m.size()):
		mem.append("- " + String(m[i]["text"]))
	return ("You are %s, a small creature called a kin (species: %s, a %s type) who lives on a floating-island farm with your hunter. " +
		"Your voice: %s. Traits from 0 to 1: bravery %.2f, loyalty %.2f, temper %.2f, curiosity %.2f. " +
		"Trust in your hunter: %d out of 100 (below 30 you are wary and a bit cold, above 70 you are warm and devoted). " +
		"You are level %d and have been on %d expeditions, made it out of %d. " +
		"What you remember, oldest first:\n%s") % [k["name"], sp["name"], sp["type"], sp["voice"], tr["bravery"], tr["loyalty"], tr["temper"], tr["curiosity"],
		int(k["trust"]), int(k["level"]), int(k.get("matches", 0)), int(k.get("wins", 0)), "\n".join(mem) if mem.size() > 0 else "- nothing yet, you are new here"]

## Writes a set of short voice lines in this kin's personality, stored on the kin for its next matches.
func refresh_lines(k: Dictionary, cb := Callable()) -> void:
	if js == null or not ai_ok:
		return
	var prompt := kin_brief(k) + "\n\nWrite short in-match voice lines (2 to 7 words each, no emoji, no quotes) as JSON with these keys, 3 lines each: " + \
		"throw (being thrown into a fight), refuse (refusing a dangerous throw), hesitate (going reluctantly), scared (retreating hurt), " + \
		"revive (rushing to revive your downed hunter), kill (after a knock), caught (a new kin was caught), extract (escaping the islands). " + \
		"Let your trust level and memories colour the lines. Reply with the JSON object only."
	ask([{"role": "user", "content": prompt}], func(txt: String):
		var s := txt.strip_edges()
		var a := s.find("{"); var b := s.rfind("}")
		if a < 0 or b <= a:
			return
		var parsed = JSON.parse_string(s.substr(a, b - a + 1))
		if typeof(parsed) == TYPE_DICTIONARY:
			var lines := {}
			for key in parsed:
				if typeof(parsed[key]) == TYPE_ARRAY:
					lines[key] = parsed[key].filter(func(x): return typeof(x) == TYPE_STRING and x.length() < 60)
			k["lines"] = lines
			Save.save_game()
			if cb.is_valid(): cb.call(), "quick")

func kin_lines_for_match(m: Node) -> void:
	var p = m.get("player")
	if p and p.kin:
		p.kin.lines = p.kin.rec.get("lines", {})

# ------------------------------------------------------------------ rooms (online play)
func net_available() -> bool:
	return js != null

func net_call(method: String, args: Array) -> void:
	if js == null:
		return
	match args.size():
		0: js.call(method)
		1: js.call(method, args[0])
		2: js.call(method, args[0], args[1])
		_: js.call(method, args[0], args[1], args[2])

func make_callback(f: Callable):
	var cb := JavaScriptBridge.create_callback(f)
	_keep.append(cb)
	return cb
