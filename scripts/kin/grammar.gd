class_name KinGrammar
extends RefCounted
## Loads and checks kin grammar content (docs/KIN_GRAMMAR.md). Files are read as JSON text and
## parsed into typed specs; nothing in them is loaded as a resource or run.
##
##   godot --headless -- --grammar-check                       every v2 file under res://content
##   godot --headless -- --grammar-check=res://tests/grammar_fixtures/broken
##   godot --headless -- --grammar-vocab                       the vocabulary as markdown tables
##
## A root holds abilities_v2/, merges_v2/, evolution_v2/ and kin_v2/ (any may be missing).

const FOLDERS := [["abilities_v2", "abilities"], ["merges_v2", "merges"], ["evolution_v2", "evolution"], ["kin_v2", "kin"]]

## Parses every file under root. Returns {abilities, merges, evolution, kin} (id -> spec) and
## fills `reports` (file -> GrammarReport).
static func load_root(root: String, reports: Dictionary) -> Dictionary:
	var lib := {"abilities": {}, "merges": {}, "evolution": {}, "kin": {}}
	for pair in FOLDERS:
		var folder: String = pair[0]
		var dir := DirAccess.open(root.path_join(folder))
		if dir == null:
			continue
		var files: Array = Array(dir.get_files()).filter(func(f): return String(f).ends_with(".json"))
		files.sort()
		for f in files:
			var rep := GrammarReport.new()
			rep.file = folder + "/" + f
			reports[rep.file] = rep
			var json := JSON.new()
			if json.parse(FileAccess.get_file_as_string(root.path_join(folder).path_join(f))) != OK:
				rep.err("", "not valid JSON (line %d: %s)" % [json.get_error_line(), json.get_error_message()])
				continue
			var spec: RefCounted = null
			match String(pair[1]):
				"abilities": spec = AbilitySpec.parse(json.data, rep)
				"merges": spec = MergeSpec.parse(json.data, rep)
				"evolution": spec = EvolutionNode.parse(json.data, rep)
				"kin": spec = KinSpec.parse(json.data, rep)
			if spec == null:
				continue
			var sid := String(spec.get("id"))
			if sid != "" and sid != String(f).get_basename():
				rep.err("id", "'%s' doesn't match the file name %s" % [sid, f])
			if (lib[pair[1]] as Dictionary).has(sid):
				rep.err("id", "'%s' is already used by another file" % sid)
			elif sid != "":
				lib[pair[1]][sid] = spec
	for kid in lib["kin"]:
		var rep: GrammarReport = reports["kin_v2/%s.json" % kid]
		(lib["kin"][kid] as KinSpec).check_refs(lib, rep)
	return lib

## Prints every structural error under root and returns how many there were.
static func check(root: String) -> int:
	var bad := 0
	for msg in KinParts.self_check():
		print("GRAMMAR ERROR registry: ", msg); bad += 1
	var reports := {}
	var lib := load_root(root, reports)
	print("GRAMMAR %s: %d abilities, %d merges, %d evolution nodes, %d kin" % [root, lib["abilities"].size(), lib["merges"].size(), lib["evolution"].size(), lib["kin"].size()])
	var warns := 0
	for file in reports:
		var rep: GrammarReport = reports[file]
		for w in rep.warnings:
			print("GRAMMAR WARN  ", w); warns += 1
		if rep.ok():
			var extra := ""
			var id := String(file).get_file().get_basename()
			if String(file).begins_with("abilities_v2/") and lib["abilities"].has(id):
				var a: AbilitySpec = lib["abilities"][id]
				extra = "  (tier %d, %s, placeholder cost %s)" % [a.tier, a.trigger.type if a.trigger else "?", KinParts._num(a.cost())]
			print("GRAMMAR ok    ", file, extra)
		for e in rep.errors:
			print("GRAMMAR ERROR ", e); bad += 1
	print("GRAMMAR DONE, errors: %d, warnings: %d" % [bad, warns])
	return bad

## The whole vocabulary as markdown tables, generated from KinParts so the doc can't drift.
static func vocab_markdown() -> String:
	var out := PackedStringArray()
	for sec in [["Deliveries", "delivery"], ["Effects", "effect"], ["Modifiers", "modifier"], ["Triggers", "trigger"], ["Cues (auto and AI)", "cue"]]:
		out.append("### " + String(sec[0]) + "\n")
		out.append("| part | what it does | parameter | min | max | default | unit |")
		out.append("|---|---|---|---|---|---|---|")
		var t := KinParts.table(sec[1])
		for type in t:
			var info: Dictionary = t[type]
			var head := "**%s**" % type
			var what := String(info.get("doc", ""))
			if info.has("cat"): what += " · " + String(info["cat"])
			if info.has("targets"): what += " · targets " + "/".join(info["targets"])
			if info.has("events") and not (info["events"] as Array).is_empty(): what += " · then: " + ", ".join(info["events"])
			if info.has("on"): what += " · on " + ", ".join(info["on"])
			var ps: Dictionary = info.get("params", {})
			if ps.is_empty():
				out.append("| %s | %s | - | | | | |" % [head, what])
				continue
			var first := true
			for p in ps:
				out.append(_row(head if first else "", what if first else "", p, ps[p]))
				first = false
		out.append("")
	out.append("### Signature mechanics (reviewed, hand-coded)\n")
	out.append("| id | what it does | parameter | min | max | default | unit |")
	out.append("|---|---|---|---|---|---|---|")
	for s in KinParts.SIGNATURES:
		var first := true
		for p in KinParts.SIGNATURES[s]["params"]:
			out.append(_row("**%s**" % s if first else "", String(KinParts.SIGNATURES[s]["doc"]) if first else "", p, KinParts.SIGNATURES[s]["params"][p]))
			first = false
	out.append("\n### Buff stats\n")
	out.append("| stat | what | min | max | default | unit |")
	out.append("|---|---|---|---|---|---|")
	for s in KinParts.BUFF_STATS:
		var b: Array = KinParts.BUFF_STATS[s]
		out.append("| %s | %s | %s | %s | %s | %s |" % [s, b[4], KinParts._num(b[0]), KinParts._num(b[1]), KinParts._num(b[2]), b[3]])
	out.append("\n### Owner stats (carry passive and merge passives)\n")
	out.append("| stat | category | type | carry max | merge max | unit | what |")
	out.append("|---|---|---|---|---|---|---|")
	for s in KinParts.OWNER_STATS:
		var r: Array = KinParts.OWNER_STATS[s]
		out.append("| %s | %s | %s | %s | %s | %s | %s |" % [s, r[0], r[1], KinParts._num(float(r[2])), KinParts._num(float(r[3])), r[4], r[5]])
	out.append("\n### Stat profile (exactly %d points per kin)\n" % KinParts.STAT_BUDGET)
	out.append("| stat | base | per point | max points | unit | what |")
	out.append("|---|---|---|---|---|---|")
	for s in KinParts.STATS:
		var r: Dictionary = KinParts.STATS[s]
		out.append("| %s | %s | %s | %d | %s | %s |" % [s, KinParts._num(r["base"]), KinParts._num(r["per_point"]), r["max_points"], r["unit"], r["doc"]])
	for sec in [["Body", KinParts.BODY], ["Gait", KinParts.GAIT], ["Mount", KinParts.MOUNT], ["Shot riders", KinParts.SHOT], ["Merge", KinParts.MERGE], ["Merge pulse", KinParts.PULSE]]:
		out.append("\n### %s\n" % sec[0])
		out.append("| parameter | min | max | default | unit | what |")
		out.append("|---|---|---|---|---|---|")
		for p in sec[1]:
			out.append("| %s | %s |" % [" | ".join(_cells(p, sec[1][p])), String(sec[1][p][5])])
	out.append("\n### Presets\n")
	out.append("| preset | fills | what |")
	out.append("|---|---|---|")
	for pr in KinParts.PRESETS:
		var fills := PackedStringArray()
		for type in KinParts.PRESETS[pr]["parts"]:
			fills.append("%s %s" % [type, JSON.stringify(KinParts.PRESETS[pr]["parts"][type])])
		out.append("| %s | %s | %s |" % [pr, "; ".join(fills), KinParts.PRESETS[pr]["doc"]])
	return "\n".join(out)

static func _row(head: String, what: String, p: String, pd: Array) -> String:
	return "| %s | %s | %s |" % [head, what, " | ".join(_cells(p, pd))]

static func _cells(p: String, pd: Array) -> PackedStringArray:
	var lo := ""; var hi := ""
	if String(pd[0]) == "enum":
		lo = "/".join(pd[1])
	elif String(pd[0]) == "bool":
		lo = "true/false"
	else:
		lo = KinParts._num(float(pd[1])); hi = KinParts._num(float(pd[2]))
	var dflt := "required" if pd[3] == null else (KinParts._num(float(pd[3])) if typeof(pd[3]) in [TYPE_FLOAT, TYPE_INT] else str(pd[3]))
	return PackedStringArray([p, lo, hi, dflt, String(pd[4])])
