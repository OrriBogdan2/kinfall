class_name Evo
## Kin evolution. How you raise a kin decides what it grows into, and it never stops growing.
##
## Every kin builds up four affinities from how it lives: what it eats, what it does in matches
## and its own personality. Every 4 levels it takes a new form along its strongest affinity, so
## one Vespyx can become fierce and another steadfast. Between forms, every 4 levels from level 2,
## it gains a mutation: a new body part (or a bigger version of one it has) with a small perk.
## There is no cap, and the parts and order differ for every kin.

const AFF := {
	"fierce": {"name": "Fierce", "tint": Color("e0503a"), "stat": "dmg", "amt": 0.05,
		"why": "fights hard", "food": "emberberry", "parts": ["horns", "spikes", "fangs", "brow"]},
	"steadfast": {"name": "Steadfast", "tint": Color("c9b27a"), "stat": "hp", "amt": 0.08,
		"why": "looks after you", "food": "sunroot", "parts": ["plates", "shell", "brow", "club"]},
	"curious": {"name": "Curious", "tint": Color("9a7af0"), "stat": "cd", "amt": 0.06,
		"why": "explores and uses its skill", "food": "mindmint", "parts": ["antennae", "spots", "third_eye", "crest"]},
	"swift": {"name": "Swift", "tint": Color("5ad0e0"), "stat": "speed", "amt": 0.05,
		"why": "gets thrown around and moves fast", "food": "tidebloom", "parts": ["wings", "tail_long", "fins", "crest"]},
}

const ROOTS := {"cindle": "Cind", "puddlet": "Pud", "burrlet": "Burr", "zapple": "Zap", "pebbit": "Peb", "wisplet": "Wisp"}
const SUFFIX := {
	"fierce": ["fang", "claw", "maw", "rend", "fury"],
	"steadfast": ["shell", "ward", "keep", "bulwark", "aegis"],
	"curious": ["wick", "seer", "mote", "glim", "oracle"],
	"swift": ["dart", "wing", "gale", "streak", "comet"],
}

const PART_NAMES := {"horns": "horns", "spikes": "back spikes", "fangs": "fangs", "brow": "an armored brow",
	"plates": "armor plates", "shell": "a shell ring", "club": "a club tail", "antennae": "antennae",
	"spots": "glowing spots", "third_eye": "a third eye", "crest": "a crest", "wings": "little wings",
	"tail_long": "a long tail", "fins": "side fins"}

## Makes sure an older record has the fields evolution needs.
static func ensure(rec: Dictionary) -> void:
	if not rec.has("aff"):
		rec["aff"] = {"fierce": 0.0, "steadfast": 0.0, "curious": 0.0, "swift": 0.0}
	if not rec.has("forms"):
		rec["forms"] = []          # one affinity per form taken
	if not rec.has("muts"):
		rec["muts"] = []           # [{id, lv, aff}]

static func add(rec: Dictionary, aff: String, n: float) -> void:
	ensure(rec)
	rec["aff"][aff] = float(rec["aff"].get(aff, 0.0)) + n

## The affinity that wins right now: what it's been doing plus its personality.
static func leading(rec: Dictionary) -> String:
	ensure(rec)
	var tr: Dictionary = rec.get("traits", {})
	var sp: Dictionary = Data.KIN.get(rec.get("species", "cindle"), {})
	var score := {
		"fierce": float(rec["aff"]["fierce"]) + (float(tr.get("bravery", 0.5)) + float(tr.get("temper", 0.5))) * 5.0,
		"steadfast": float(rec["aff"]["steadfast"]) + float(tr.get("loyalty", 0.5)) * 10.0,
		"curious": float(rec["aff"]["curious"]) + float(tr.get("curiosity", 0.5)) * 10.0,
		"swift": float(rec["aff"]["swift"]) + float(sp.get("speed", 6.5)) / 8.0 * 6.0,
	}
	var best := "fierce"; var bv := -1e9
	for k in ["fierce", "steadfast", "curious", "swift"]:
		if score[k] > bv: bv = score[k]; best = k
	return best

## The name of a kin's current form, e.g. "Cindfang" or "Pudward".
static func form_name(rec: Dictionary) -> String:
	ensure(rec)
	var sp_id: String = rec.get("species", "cindle")
	var forms: Array = rec["forms"]
	if forms.is_empty():
		return Data.KIN[sp_id]["name"]
	var last: String = forms[forms.size() - 1]
	var sfx: Array = SUFFIX[last]
	return String(ROOTS.get(sp_id, "Kin")) + String(sfx[mini(forms.size() - 1, sfx.size() - 1)]) + ("" if forms.size() <= sfx.size() else " " + _roman(forms.size() - sfx.size() + 1))

static func _roman(n: int) -> String:
	return ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"][clampi(n, 0, 10)] if n <= 10 else str(n)

## Called each time a kin gains a level. Returns what changed, or {} if nothing did.
static func on_level(rec: Dictionary, rng: RandomNumberGenerator = null) -> Dictionary:
	ensure(rec)
	var lv := int(rec.get("level", 1))
	if rng == null:
		rng = RandomNumberGenerator.new(); rng.seed = hash(str(rec.get("uid", "")) + str(lv))
	if lv >= 4 and lv % 4 == 0:
		var a := leading(rec)
		var before := form_name(rec)
		rec["forms"].append(a)
		return {"kind": "form", "aff": a, "from": before, "to": form_name(rec)}
	if lv >= 2 and lv % 4 == 2:
		var a := leading(rec)
		# mostly from the leading affinity, sometimes from another one it's been building
		if rng.randf() < 0.3:
			a = ["fierce", "steadfast", "curious", "swift"][rng.randi_range(0, 3)]
		var pool: Array = AFF[a]["parts"]
		var part: String = pool[rng.randi_range(0, pool.size() - 1)]
		for m in rec["muts"]:
			if m["id"] == part:
				m["lv"] = int(m["lv"]) + 1
				return {"kind": "grow", "aff": a, "part": part, "lv": m["lv"]}
		rec["muts"].append({"id": part, "lv": 1, "aff": a})
		return {"kind": "mutate", "aff": a, "part": part}
	return {}

## Gives a generated kin (wild or a bot's) the forms and parts it would have grown by its level.
static func simulate(rec: Dictionary, rng: RandomNumberGenerator) -> void:
	ensure(rec)
	var target := int(rec.get("level", 1))
	var bias: String = ["fierce", "steadfast", "curious", "swift"][rng.randi_range(0, 3)]
	for lv in range(2, target + 1):
		add(rec, bias, rng.randf_range(2.0, 6.0))
		add(rec, ["fierce", "steadfast", "curious", "swift"][rng.randi_range(0, 3)], rng.randf_range(0.0, 3.0))
		rec["level"] = lv
		on_level(rec, rng)
	rec["level"] = target

## Stat multipliers from forms and mutations: {"hp", "dmg", "speed", "cd"}.
static func mods(rec: Dictionary) -> Dictionary:
	ensure(rec)
	var out := {"hp": 1.0, "dmg": 1.0, "speed": 1.0, "cd": 1.0}
	for f in rec["forms"]:
		var s: String = AFF[f]["stat"]
		out[s] = _apply(out[s], s, float(AFF[f]["amt"]) * 2.0)
	for m in rec["muts"]:
		var s: String = AFF[m["aff"]]["stat"]
		out[s] = _apply(out[s], s, float(AFF[m["aff"]]["amt"]) * int(m["lv"]))
	# rare mutations (Giant, Crystal...) add their small perks
	var rm := Mutations.mods(rec)
	for k in out: out[k] = float(out[k]) * float(rm[k])
	return out

static func _apply(v: float, s: String, amt: float) -> float:
	return v * (1.0 - amt) if s == "cd" else v * (1.0 + amt)

## What a match taught it: called from Game.apply_result with the kin's match stats.
static func learn(rec: Dictionary, st: Dictionary) -> void:
	add(rec, "fierce", float(st.get("hits", 0)) * 0.4 + float(st.get("kos", 0)) * 3.0)
	add(rec, "steadfast", float(st.get("revives", 0)) * 6.0 + float(st.get("won", 0)) * 2.0)
	add(rec, "curious", float(st.get("skills", 0)) * 0.6 + float(st.get("caught", 0)) * 4.0)
	add(rec, "swift", float(st.get("throws", 0)) * 0.8)

static func describe(ev: Dictionary, rec: Dictionary) -> String:
	var kname: String = rec.get("name", "Your kin")
	var a: Dictionary = AFF[ev["aff"]]
	match String(ev["kind"]):
		"form":
			return "%s became a %s! It grew %s because it %s." % [kname, ev["to"], String(a["name"]).to_lower(), a["why"]]
		"mutate":
			return "%s grew %s. (%s)" % [kname, PART_NAMES.get(ev["part"], ev["part"]), _perk(ev["aff"])]
		"grow":
			return "%s's %s grew bigger. (%s)" % [kname, PART_NAMES.get(ev["part"], ev["part"]), _perk(ev["aff"])]
	return ""

static func _perk(aff: String) -> String:
	match aff:
		"fierce": return "+5% damage"
		"steadfast": return "+8% health"
		"curious": return "skill recharges 6% faster"
		"swift": return "+5% speed"
	return ""

## Adds evolved parts, size and colour to a kin model built by Models.kin.
static func dress(root: Node3D, rec: Dictionary) -> void:
	if rec.is_empty():
		return
	ensure(rec)
	var forms: Array = rec["forms"]
	var muts: Array = rec["muts"]
	if forms.is_empty() and muts.is_empty():
		return
	var body: Node3D = root.get_node("Body/Flex") if root.has_node("Body/Flex") else root.get_node("Body")
	var sp: Dictionary = Data.KIN[rec.get("species", "cindle")]
	var base: Color = Shiny.body(rec)
	if forms.size() > 0:
		var last: String = forms[forms.size() - 1]
		base = base.lerp(AFF[last]["tint"], minf(0.1 * forms.size(), 0.35))
		# recolour the body to the form's tint
		var mats: Array = root.get_meta("mats", [])
		if mats.size() > 0:
			(mats[0] as ShaderMaterial).set_shader_parameter("albedo", base)
		root.set_meta("evo_scale", 1.0 + minf(forms.size() * 0.1, 0.6))
	var mats2: Array = root.get_meta("mats", [])
	for m in muts:
		var col: Color = base.lerp(AFF[m["aff"]]["tint"], 0.6)
		var mat := Models.toon(col.darkened(0.1))
		var glow := Models.toon(AFF[m["aff"]]["tint"].lightened(0.3), false, 0.9)
		mats2.append(mat)
		var k := 1.0 + (int(m["lv"]) - 1) * 0.3
		match String(m["id"]):
			"horns":
				for sx in [-1.0, 1.0]:
					Models.part(body, Models.cyl(0.0, 0.06 * k, 0.28 * k), mat, Vector3(0.15 * sx, 0.68 + 0.05 * k, -0.08), Vector3.ONE, Vector3(-0.35, 0, -0.45 * sx))
			"spikes":
				for i in 3:
					Models.part(body, Models.cyl(0.0, 0.07 * k, 0.2 * k), mat, Vector3(0, 0.62 - i * 0.12, 0.12 + i * 0.12), Vector3.ONE, Vector3(0.6 + i * 0.3, 0, 0))
			"fangs":
				for sx in [-1.0, 1.0]:
					Models.part(body, Models.cyl(0.0, 0.025 * k, 0.09 * k), Models.toon(Color.WHITE), Vector3(0.06 * sx, 0.31, -0.33), Vector3.ONE, Vector3(PI, 0, 0))
			"brow":
				Models.part(body, Models.box(0.36 * k, 0.07, 0.14), mat, Vector3(0, 0.55, -0.25), Vector3.ONE, Vector3(0.4, 0, 0))
			"plates":
				for i in 2:
					Models.part(body, Models.box(0.34 * k, 0.06, 0.2), mat, Vector3(0, 0.6 - i * 0.14, 0.14 + i * 0.12), Vector3.ONE, Vector3(-0.5 - i * 0.3, 0, 0))
			"shell":
				var t := TorusMesh.new(); t.inner_radius = 0.33; t.outer_radius = 0.33 + 0.07 * k
				Models.part(body, t, mat, Vector3(0, 0.3, 0))
			"club":
				Models.part(body, Models.sphere(0.12 * k, 10), mat, Vector3(0, 0.22, 0.48))
			"antennae":
				for sx in [-1.0, 1.0]:
					Models.part(body, Models.cyl(0.012, 0.012, 0.3 * k, 6), mat, Vector3(0.09 * sx, 0.78, -0.12), Vector3.ONE, Vector3(-0.3, 0, -0.25 * sx))
					Models.part(body, Models.sphere(0.045 * k, 8), glow, Vector3(0.13 * sx, 0.78 + 0.15 * k, -0.18))
			"spots":
				for i in 4:
					var a := TAU * i / 4.0 + 0.4
					Models.part(body, Models.sphere(0.04 * k, 6), glow, Vector3(cos(a) * 0.33, 0.36 + sin(a * 2.0) * 0.06, sin(a) * 0.3 + 0.03))
			"third_eye":
				Models.part(body, Models.sphere(0.045 * k, 8), glow, Vector3(0, 0.56, -0.29))
			"crest":
				for i in 3:
					Models.part(body, Models.box(0.03, 0.16 * k - i * 0.03, 0.1), mat, Vector3(0, 0.72 - i * 0.02, -0.04 + i * 0.09), Vector3.ONE, Vector3(0.3, 0, 0))
			"wings":
				for sx in [-1.0, 1.0]:
					var w := Models.part(body, Models.sphere(0.16 * k, 10), mat, Vector3(0.26 * sx, 0.5, 0.18), Vector3(0.25, 1.0, 1.4), Vector3(0.3, 0.4 * sx, 0.5 * sx))
					w.name = "Wing%d" % int(sx)
			"tail_long":
				for i in 3:
					Models.part(body, Models.sphere(0.08 * k - i * 0.015, 8), mat, Vector3(0, 0.28 + i * 0.05, 0.36 + i * 0.13))
			"fins":
				for sx in [-1.0, 1.0]:
					Models.part(body, Models.sphere(0.12 * k, 8), mat, Vector3(0.34 * sx, 0.28, 0.0), Vector3(0.2, 0.7, 1.2), Vector3(0, 0, 0.3 * sx))
	root.set_meta("mats", mats2)
	if root.has_meta("evo_scale"):
		root.scale = Vector3.ONE * float(root.get_meta("evo_scale"))
