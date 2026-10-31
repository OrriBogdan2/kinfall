class_name Shiny
## Shimmering kin, the shinies: very rare, and each species has its own hand-picked alternate
## colours (content/kin/<id>.json "shiny": {color, belly, glow, wing?}), not just a hue turn.
## A shimmer that appears (in the wild, out of an egg) arrives with a burst of stars and a chime.
##
## Odds, very rare (owner's call: lower than Pokémon, and eggs barely helped by shiny parents):
##   wild           1 in 4096, x2 at rare spawn points, x1.5 in the Hollow (tier 2+); they stack
##   eggs           1 in 4096; a shimmering parent adds only a slight chance of passing it on:
##                  1 in 2048 with one shimmering parent, about 1 in 1365 (3 in 4096) with two
## Rare mutations keep their own inheritance (Mutations.inherit). The flag lives on the kin's
## record as rec["shimmer"] (the same field as always).

const WILD := 1.0 / 4096.0
const RARE_SPOT_MULT := 2.0
const HOLLOW_MULT := 1.5
const HOLLOW_TIER := 2
## Egg odds by how many parents shimmer.
const EGG := [1.0 / 4096.0, 2.0 / 4096.0, 3.0 / 4096.0]

## Palettes for kin that don't carry one in their JSON yet (the boss-egg kin).
const FALLBACK := {
	"cairnback": {"color": "#8a5a3a", "belly": "#f0e0c0", "glow": "#7ff3ff"},
	"hivara": {"color": "#c0c8d8", "belly": "#2a2a4a", "glow": "#9ad8ff"},
	"zephyrak": {"color": "#8a3a8a", "belly": "#ffd6f0", "glow": "#ffb04a", "wing": "#ffd36a"},
}

static var _pal := {}

## The chance a wild kin shimmers where it was found.
static func wild_chance(tier := 0, rare_spot := false) -> float:
	var m := (RARE_SPOT_MULT if rare_spot else 1.0) * (HOLLOW_MULT if tier >= HOLLOW_TIER else 1.0)
	return minf(1.0, WILD * m)

static func roll_wild(rng: RandomNumberGenerator, tier := 0, rare_spot := false) -> bool:
	return rng.randf() < wild_chance(tier, rare_spot)

## The chance an egg from these two parents shimmers.
static func egg_chance(a: Dictionary, b: Dictionary) -> float:
	var n := (1 if a.get("shimmer", false) else 0) + (1 if b.get("shimmer", false) else 0)
	return float(EGG[n])

static func roll_egg(a: Dictionary, b: Dictionary, rng: RandomNumberGenerator) -> bool:
	return rng.randf() < egg_chance(a, b)

## "1 in 1024" for showing odds.
static func odds_text(p: float) -> String:
	return "1 in %d" % int(round(1.0 / maxf(p, 1e-9)))

# ------------------------------------------------------------------ colours
## A species' shimmer palette: {color, belly, glow, wing} as Colors. Hand-picked in the kin JSON
## when there is one, else from FALLBACK, else the old turn round the colour wheel.
static func palette(species: String) -> Dictionary:
	if _pal.has(species):
		return _pal[species]
	var sp: Dictionary = Data.KIN.get(species, {})
	var raw: Dictionary = {}
	var j: Dictionary = Content._load("kin", species)
	if typeof(j.get("shiny")) == TYPE_DICTIONARY:
		raw = j["shiny"]
	elif FALLBACK.has(species):
		raw = FALLBACK[species]
	var base_c: Color = sp.get("color", Color.WHITE)
	var base_b: Color = sp.get("belly", base_c)
	var base_g: Color = sp.get("glow", base_c)
	var out := {
		"color": Color(String(raw["color"])) if raw.has("color") else Care.shimmer_col(base_c),
		"belly": Color(String(raw["belly"])) if raw.has("belly") else Care.shimmer_col(base_b),
		"glow": Color(String(raw["glow"])) if raw.has("glow") else Care.shimmer_col(base_g),
		"hand": not raw.is_empty(),
	}
	if raw.has("wing"): out["wing"] = Color(String(raw["wing"]))
	elif sp.has("wing"): out["wing"] = Care.shimmer_col(sp["wing"])
	_pal[species] = out
	return out

## One colour slot ("color", "belly", "glow", "wing") for this kin: ghostly, shimmering or plain.
static func col(species: String, rec: Dictionary, slot := "color") -> Color:
	var sp: Dictionary = Data.KIN.get(species, {})
	var base: Color = sp.get(slot, sp.get("belly", Color.WHITE) if slot == "wing" else sp.get("color", Color.WHITE))
	if rec.get("ghost", false):
		return Color("9ff0e0") if slot == "glow" else Care.ghost_col(base)
	if rec.get("shimmer", false):
		var p := palette(species)
		return p.get(slot, base)
	return base

## Shorthand for the body colour of a record (what most menus tint with).
static func body(rec: Dictionary) -> Color:
	return col(String(rec.get("species", "")), rec, "color")

# ------------------------------------------------------------------ the entrance
## A burst of stars round a shimmer as it shows up, and its chime. parent: a 3D node to hang the
## effect on (it frees itself); at: where, in parent space.
static func sparkle(parent: Node, at: Vector3, species := "", size := 1.0, sound := true) -> Node3D:
	var root := Node3D.new()
	root.name = "ShinySparkle"
	root.position = at
	parent.add_child(root)
	var gc: Color = palette(species)["glow"] if species != "" and Data.KIN.has(species) else Color("fff6c0")
	var cols := [Color("fff6c0"), Color.WHITE, gc.lightened(0.3), Color("ffd36a")]
	# a quick spray of little stars
	var pt := CPUParticles3D.new()
	pt.one_shot = true
	pt.amount = 34
	pt.lifetime = 0.9
	pt.explosiveness = 0.92
	pt.direction = Vector3.UP
	pt.spread = 180.0
	pt.initial_velocity_min = 1.6 * size
	pt.initial_velocity_max = 3.6 * size
	pt.gravity = Vector3(0, -1.5, 0)
	pt.damping_min = 2.0; pt.damping_max = 3.5
	pt.scale_amount_min = 0.6; pt.scale_amount_max = 1.3
	var qm := QuadMesh.new(); qm.size = Vector2(0.16, 0.16) * size
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pm.vertex_color_use_as_albedo = true
	pm.albedo_texture = _star_tex()
	qm.material = pm
	pt.mesh = qm
	var gr := Gradient.new()
	gr.set_color(0, Color(cols[0], 1.0)); gr.set_color(1, Color(gc, 0.0))
	pt.color_ramp = gr
	pt.position.y = 0.5 * size
	root.add_child(pt)
	pt.emitting = true
	# and a ring of bigger stars that pop out, twinkle and fade
	for i in 6:
		var s := MeshInstance3D.new()
		var q := QuadMesh.new(); q.size = Vector2(0.42, 0.42) * size
		var m := pm.duplicate() as StandardMaterial3D
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.vertex_color_use_as_albedo = false
		m.albedo_color = cols[i % cols.size()]
		q.material = m
		s.mesh = q
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a := TAU * i / 6.0
		var to := Vector3(cos(a) * 0.75, 0.55 + (i % 2) * 0.35, sin(a) * 0.75) * size
		s.position = Vector3(0, 0.5 * size, 0)
		s.scale = Vector3.ONE * 0.01
		root.add_child(s)
		var tw := s.create_tween()
		tw.tween_interval(0.05 * i)
		tw.tween_property(s, "position", to, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(s, "scale", Vector3.ONE, 0.22)
		tw.tween_property(s, "scale", Vector3.ONE * 0.5, 0.18)
		tw.tween_property(s, "scale", Vector3.ONE * 1.1, 0.18)
		tw.tween_property(s, "scale", Vector3.ONE * 0.01, 0.35)
	if sound and Engine.get_main_loop() != null:
		Sfx.play_stream(chime(), root.global_position if root.is_inside_tree() else null, -4.0, 0.0)
	var tm := root.create_tween()
	tm.tween_interval(1.9)
	tm.tween_callback(root.queue_free)
	return root

static var _star: ImageTexture = null
## A soft four-point star.
static func _star_tex() -> ImageTexture:
	if _star != null:
		return _star
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5) / (n * 0.5)
			var d := absf(p.x) * absf(p.y) * 9.0 + p.length() * 0.6
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_star = ImageTexture.create_from_image(img)
	return _star

static var _chime: AudioStreamWAV = null
## The shimmer chime: two bright bell runs that glitter upward, made here (no files).
static func chime() -> AudioStreamWAV:
	if _chime != null:
		return _chime
	var rate := 22050
	var dur := 1.25
	var buf := PackedFloat32Array(); buf.resize(int(dur * rate))
	var notes := [[88, 0.0], [91, 0.07], [95, 0.14], [100, 0.21], [96, 0.42], [100, 0.49], [103, 0.56], [107, 0.63]]
	for nt in notes:
		var f := 440.0 * pow(2.0, (float(nt[0]) - 69.0) / 12.0)
		var s0 := int(float(nt[1]) * rate)
		var len := int(0.55 * rate)
		for i in len:
			var ti := float(i) / rate
			var env := minf(1.0, ti / 0.003) * exp(-ti * 7.5)
			var v := sin(TAU * f * ti) + sin(TAU * f * 2.01 * ti) * 0.25 + sin(TAU * f * 3.98 * ti) * 0.08
			var j := s0 + i
			if j < buf.size(): buf[j] += v * env * 0.16
	var data := PackedByteArray(); data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, int(clampf(tanh(buf[i] * 1.3), -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	_chime = w
	return w
