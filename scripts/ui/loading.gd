extends CanvasLayer
## The screen between home and an expedition: the tier's sky with islands drifting past and the
## skyship crossing, the tier name, what you're heading into, a tip and a progress bar.

signal shown

const TIPS := [
	"Hold Space in the air to glide. You can open your glider off any booster too.",
	"Knocked off an edge? Touch the island's side and you float back up onto it.",
	"Exits open partway through. Stand inside one to fly home with everything you carry.",
	"C throws your kin. It stuns whatever it hits, and C again calls it back.",
	"Right click is your hero's own ability. Every hero's is different, so try it in Training.",
	"You only see what's in front of you. Rivals behind you or past a wall stay hidden, and so do you.",
	"Tall grass hides you from anyone outside it. Shooting gives you away for a moment.",
	"Crouch (Ctrl) to move quietly: you're only spotted up close.",
	"Get knocked into a wall and you're stunned. Do it to them first.",
	"Shots go exactly where you aim. Fast guns sway in the same small pattern every time, and firing slows your step.",
	"Jump at a wall in the air to kick off it. Light heroes get two kicks.",
	"Crates and barrels break when you shoot or dash through them. Some hide a better weapon.",
	"Weapons you find out here are stronger than your own, but only for this expedition.",
	"Press 1 to drink a tonic. They heal over a few seconds, so drink before it's desperate.",
	"Fight alongside your kin to fill the bond meter, then R calls its bond ultimate.",
	"Q and E are your kin's abilities. Each kin you bring gives you a different kit.",
	"Your kin stuns or roots a foe? Shoot it right away for a combo.",
	"Bring two kin and press X to swap between them mid-fight.",
	"Go down for good and the kin you brought are left behind. Old Pell's Ransom House sells back the ones nobody collects.",
	"A rival took your kin? You'll sense it when they're nearby. Take it back.",
	"Wild kin with a ring under them can be caught. Weaken them first.",
	"Jump off the skyship over an island nobody else picked. Space opens your glider early for a longer, slower last stretch.",
	"One life per expedition. Fall off the islands and a gust from below carries you back up, for a third of your health.",
	"A teammate is down? Stand next to them and hold F to bring them back.",
	"Dash through a shot at the last moment and you take nothing.",
	"Shrines on the islands give a short power-up. Stand by one and press F.",
]
const STAGES := ["Raising the islands", "Waking the monsters", "Hiding the loot", "Fueling the skyship", "Ready"]

var c: Control
var t := 0.0
var prog := 0.0          # what the bar shows
var want := 0.0          # where the bar is heading
var fade := 0.0
var leaving := false
var tier := 0
var T: Dictionary
var title := ""
var sub := ""
var mode_line := ""
var tip := ""
var islands: Array = []  # [x (0..1), y (0..1), size, depth, seed]
var stars: Array = []
var sky_tex: GradientTexture2D
var shade_tex: GradientTexture2D
var puff: GradientTexture2D

func _grad(cols: Array, offs: Array, radial := false) -> GradientTexture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray(cols); g.offsets = PackedFloat32Array(offs)
	var gt := GradientTexture2D.new()
	gt.gradient = g; gt.width = 128; gt.height = 128
	if radial:
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5); gt.fill_to = Vector2(1.0, 0.5)
	else:
		gt.fill_from = Vector2(0, 0); gt.fill_to = Vector2(0, 1)
	return gt

func setup(opts: Dictionary) -> void:
	layer = 45
	tier = clampi(int(opts.get("tier", 0)), 0, Data.TIERS.size() - 1)
	T = Data.TIERS[tier]
	if opts.get("tutorial", false):
		title = "First Expedition"; sub = "A short trip with Pip to learn the ropes."
	elif opts.get("training", false):
		title = "Training Grounds"; sub = "Dummies, ledges and boosters. No danger here."
	else:
		title = String(T["name"]); sub = String(T["desc"])
		var teams := int(opts.get("teams", 6)); var squad := int(opts.get("squad", 1))
		mode_line = "%s  •  %d squads  •  skyship drop" % [["Solo", "Duos", "Trios"][clampi(squad - 1, 0, 2)], teams]
		if opts.has("net"): mode_line = "Online  •  " + mode_line
	tip = TIPS[randi() % TIPS.size()]
	var r := RandomNumberGenerator.new(); r.seed = hash(title) + tier
	for i in 9:
		islands.append([float(i) / 9.0 + r.randf_range(-0.04, 0.04), r.randf_range(0.14, 0.62), r.randf_range(0.7, 1.3), r.randf_range(0.2, 1.0), r.randi()])
	islands.sort_custom(func(a, b): return a[3] < b[3])
	for i in 90:
		stars.append(Vector3(r.randf(), r.randf() * 0.7, r.randf()))
	var sky: Color = T["sky"]
	var cl: Array = T["clouds"]
	sky_tex = _grad([sky.darkened(0.3), sky.lerp(cl[1], 0.35), (cl[1] as Color).lerp(sky, 0.1)], [0.0, 0.6, 1.0])
	shade_tex = _grad([Color(0, 0, 0, 0), Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.8)], [0.0, 0.55, 1.0])
	puff = _grad([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)], [0.0, 0.45, 1.0], true)
	c = Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.draw.connect(_draw)
	add_child(c)

func _process(delta: float) -> void:
	t += delta
	if leaving:
		fade = maxf(0.0, fade - delta * 2.2)
		if fade <= 0.0:
			queue_free()
	else:
		var was := fade
		fade = minf(1.0, fade + delta * 3.5)
		if was < 1.0 and fade >= 1.0:
			shown.emit()
	prog = move_toward(prog, want, delta * 0.9)
	c.queue_redraw()

## Move the bar to a stage (0..1) and wait until it gets there.
func step(frac: float) -> void:
	want = maxf(want, frac)
	while prog < want - 0.01 and is_inside_tree():
		await get_tree().process_frame

func finish() -> void:
	await step(1.0)
	var hold := 0.35
	while hold > 0.0 and is_inside_tree():
		hold -= get_process_delta_time()
		await get_tree().process_frame
	leaving = true

func _stage() -> String:
	return STAGES[clampi(int(prog * (STAGES.size() - 1) + 0.02), 0, STAGES.size() - 1)]

func _draw() -> void:
	var sz := c.size
	var a := fade
	var sky: Color = T["sky"]
	var cl: Array = T["clouds"]
	var biome: Dictionary = T["biome"]
	# sky: dark at the top, the tier's cloud colour near the horizon
	c.draw_texture_rect(sky_tex, Rect2(Vector2.ZERO, sz), false, Color(1, 1, 1, a))
	for s in stars:
		var tw := 0.5 + 0.5 * sin(t * 1.7 + s.z * 30.0)
		c.draw_circle(Vector2(s.x * sz.x, s.y * sz.y), 1.0 + s.z, Color(1, 1, 1, a * (0.15 + 0.35 * tw) * (1.0 - s.y)))
	# far cloud bank
	for i in 16:
		var x := fposmod(i * 130.0 - t * 8.0, sz.x + 400.0) - 200.0
		var r := 150.0 + (i % 3) * 40.0
		c.draw_texture_rect(puff, Rect2(Vector2(x, sz.y * 0.8 + sin(i * 1.3) * 30.0) - Vector2(r, r * 0.6), Vector2(r * 2, r * 1.2)), false, Color((cl[1] as Color).lightened(0.12), a * 0.6))
	# islands drifting past, nearer ones bigger and faster
	for isl in islands:
		var d: float = isl[3]
		var x := fposmod(float(isl[0]) * (sz.x + 400.0) - t * 22.0 * d, sz.x + 400.0) - 200.0
		var y: float = float(isl[1]) * sz.y + sin(t * 0.8 + float(isl[4] % 100)) * 6.0
		_island(Vector2(x, y), float(isl[2]) * (70.0 + 170.0 * d), d, biome, a, int(isl[4]))
	# the skyship sailing across
	var sx := fposmod(t * 70.0 + sz.x * 0.35, sz.x + 500.0) - 250.0
	_ship(Vector2(sx, sz.y * 0.2 + sin(t * 1.3) * 5.0), a)
	# near cloud wisps over the bottom
	for i in 12:
		var x := fposmod(i * 170.0 - t * 30.0, sz.x + 500.0) - 250.0
		c.draw_texture_rect(puff, Rect2(Vector2(x - 200, sz.y - 90.0 + sin(i * 2.1) * 25.0), Vector2(400, 220)), false, Color((cl[1] as Color).lightened(0.25), a * 0.5))
	# a soft shade behind the text
	c.draw_texture_rect(shade_tex, Rect2(0, sz.y * 0.42, sz.x, sz.y * 0.58), false, Color(1, 1, 1, a))
	# text
	var cx := sz.x * 0.5
	var base := sz.y * 0.54
	var kick := "EXPEDITION" if mode_line != "" else "GETTING READY"
	_text(Vector2(cx, base), kick, UI.caps, 15, Color(UI.GOLD, a), 3)
	_text(Vector2(cx, base + 62), title, UI.big, 58, Color(UI.INK, a))
	_wrap(Vector2(cx, base + 96), sub, 17, minf(620.0, sz.x - 60.0), Color(UI.MUTED, a))
	if mode_line != "":
		_text(Vector2(cx, base + 176), mode_line, UI.semi, 15, Color(UI.TEAL, a))
	# progress
	var bw := minf(520.0, sz.x - 80.0)
	var br := Rect2(cx - bw * 0.5, sz.y - 96, bw, 10)
	c.draw_rect(br, Color(1, 1, 1, a * 0.12))
	c.draw_rect(Rect2(br.position, Vector2(bw * prog, 10)), Color(UI.ACCENT, a))
	c.draw_circle(br.position + Vector2(bw * prog, 5), 7.0, Color(UI.GOLD, a))
	_text(Vector2(br.position.x, br.position.y - 10), _stage() + "…", UI.semi, 14, Color(UI.INK, a * 0.85), 0, HORIZONTAL_ALIGNMENT_LEFT)
	_text(Vector2(br.end.x, br.position.y - 10), "%d%%" % int(prog * 100.0), UI.semi, 14, Color(UI.INK, a * 0.6), 0, HORIZONTAL_ALIGNMENT_RIGHT)
	_wrap(Vector2(cx, sz.y - 54), "Tip: " + tip, 15, minf(640.0, sz.x - 60.0), Color(UI.INK, a * 0.75))

func _island(p: Vector2, w: float, d: float, biome: Dictionary, a: float, sd: int) -> void:
	var r := RandomNumberGenerator.new(); r.seed = sd
	var shade := lerpf(0.45, 0.0, d)   # far islands fade into the sky
	var topc: Color = (biome["top"] as Color).darkened(shade)
	var sidec: Color = (biome["side"] as Color).darkened(shade)
	var deepc: Color = (biome["deep"] as Color).darkened(shade)
	var h := w * 0.28
	# the rocky underside, a jagged point
	var under := PackedVector2Array([p + Vector2(-w * 0.5, 0), p + Vector2(w * 0.5, 0)])
	var n := 6
	for i in n + 1:
		var f := 1.0 - float(i) / n
		var depth := h * (1.0 + 1.6 * sin(PI * f)) * r.randf_range(0.75, 1.1)
		under.append(p + Vector2(-w * 0.5 + w * f, depth))
	c.draw_colored_polygon(under, Color(deepc, a))
	c.draw_colored_polygon(PackedVector2Array([p + Vector2(-w * 0.5, 0), p + Vector2(w * 0.5, 0), p + Vector2(w * 0.46, h * 0.7), p + Vector2(-w * 0.46, h * 0.7)]), Color(sidec, a))
	# grass top as a flat ellipse
	var top := PackedVector2Array()
	for i in 24:
		var ang := TAU * i / 24.0
		top.append(p + Vector2(cos(ang) * w * 0.5, sin(ang) * h * 0.45))
	c.draw_colored_polygon(top, Color(topc, a))
	# a couple of trees
	for i in r.randi_range(1, 3):
		var tp := p + Vector2(r.randf_range(-w * 0.3, w * 0.3), r.randf_range(-h * 0.2, h * 0.05))
		var ts := w * r.randf_range(0.06, 0.1)
		c.draw_rect(Rect2(tp + Vector2(-ts * 0.12, -ts * 0.6), Vector2(ts * 0.24, ts * 0.6)), Color(sidec.darkened(0.2), a))
		c.draw_circle(tp + Vector2(0, -ts * 0.9), ts * 0.55, Color((biome["leaf"] as Color).darkened(shade), a))

func _ship(p: Vector2, a: float) -> void:
	var bal := PackedVector2Array()
	for i in 28:
		var ang := TAU * i / 28.0
		bal.append(p + Vector2(cos(ang) * 58.0, sin(ang) * 26.0))
	c.draw_colored_polygon(bal, Color(Color("f2e6cf"), a))
	for k in [-24.0, 0.0, 24.0]:
		var hh := 26.0 * sqrt(maxf(0.0, 1.0 - pow(k / 58.0, 2)))
		c.draw_line(p + Vector2(k, -hh), p + Vector2(k, hh), Color(Color("d9604a"), a), 5.0)
	for x in [-30.0, 30.0]:
		c.draw_line(p + Vector2(x, 20), p + Vector2(x * 0.7, 46), Color(Color("4e3424"), a), 1.5)
	c.draw_colored_polygon(PackedVector2Array([p + Vector2(-36, 44), p + Vector2(36, 44), p + Vector2(28, 58), p + Vector2(-30, 58)]), Color(Color("7a5236"), a))
	var spin := t * 18.0
	c.draw_line(p + Vector2(-40, 50) + Vector2(0, cos(spin) * 9), p + Vector2(-40, 50) - Vector2(0, cos(spin) * 9), Color(Color("e0b84a"), a), 3.0)

func _text(pos: Vector2, s: String, f: Font, size: int, col: Color, spacing := 0, al := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var w := 900.0
	var x := pos.x - w * 0.5
	if al == HORIZONTAL_ALIGNMENT_LEFT: x = pos.x
	elif al == HORIZONTAL_ALIGNMENT_RIGHT: x = pos.x - w
	if spacing > 0:
		s = " ".join(s.split(""))
	c.draw_string(f, Vector2(x + 2, pos.y + 2), s, al, w, size, Color(0, 0, 0, col.a * 0.4))
	c.draw_string(f, Vector2(x, pos.y), s, al, w, size, col)

func _wrap(pos: Vector2, s: String, size: int, w: float, col: Color) -> void:
	c.draw_multiline_string(UI.body, Vector2(pos.x - w * 0.5, pos.y + size), s, HORIZONTAL_ALIGNMENT_CENTER, w, size, 3, col)
