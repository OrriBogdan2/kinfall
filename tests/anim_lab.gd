extends Node3D
## The animation lab: hunters (and kin) driven by HunterAnim / KinPuppet with made-up inputs, one
## scenario per run. Open tests/anim_lab.tscn and press F6, or from the command line:
##   godot --path . res://tests/anim_lab.tscn -- --lab=run --shot=/tmp/a.png --shot-every=0.1 --frames=120
## Scenarios (--lab=): idle (fidgets sped up), run, strafe, jump (a flat hop and a long drop each
## class: flips, corkscrew, cannonball), glide, dash, melee, guns (fire, reload), emotes, states
## (downed, revive, stomp, base, stun, hit, cast, drink, ledge), crowd, kin. --lab-top views from
## the game's camera angle; --lab-side from the side.

var cells: Array = []
var lab := "idle"
var time := 0.0
var kin_cells: Array = []

func _arg(k: String, def := "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(k + "="): return a.substr(k.length() + 1)
		if a == k: return "1"
	return def

## --lab-bench: how long HunterAnim.update takes, over a crowd of hunters doing different things.
func _bench() -> void:
	var hs: Array = []
	for i in 40:
		var cls: String = CLS[i % 3]
		var h := Models.hunter(cls, Data.TEAM_COLORS[i % 4], ["smg", "rifle", "minigun", "twin_blades", "longsword", "greatsword"][i % 6], "", LOOKS[i % LOOKS.size()])
		add_child(h)
		hs.append([h, HunterAnim.new(h)])
	var t0 := Time.get_ticks_usec()
	var n := 0
	for f in 300:
		for i in hs.size():
			var a: HunterAnim = hs[i][1]
			var k := i % 5
			var s := {"face": 0.3 * f / 30.0, "fired": 0.05 if k == 3 else 99.0, "vel": Vector3(0, 0, -5.0) if k == 1 else Vector3.ZERO, "grounded": k != 2,
				"swing_n": f / 12 if k == 4 else 0, "combo": (f / 12) % 3, "reload": fmod(f / 60.0, 1.0) if k == 0 else -1.0}
			a.update(1.0 / 60.0, s)
			n += 1
	var us := float(Time.get_ticks_usec() - t0) / n
	print("ANIM BENCH %.1f us per hunter update (%d updates)" % [us, n])
	get_tree().quit()

func _ready() -> void:
	if _arg("--lab-bench") != "":
		_bench()
		return
	lab = _arg("--lab", "idle")
	var env := WorldEnvironment.new()
	env.environment = Look.environment({"top": Color("2a4a8a"), "mid": Color("6a8ad0"), "horizon": Color("ffd2a8"), "stars": 0.0})
	add_child(env)
	Look.lights(self, Color("fff1dc"), 1.0, Vector3(-45, -30, 0), 30.0)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(60, 30)
	ground.mesh = pm
	ground.material_override = Models.toon(Color("5f8d45"), false)
	add_child(ground)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.5, 7.2); cam.rotation = Vector3(-0.1, 0, 0); cam.fov = 40
	match lab:
		"idle", "crowd": _idle()
		"run": _row(["run", "run", "run", "sprint", "sprint", "sprint"])
		"strafe": _row(["strafe", "strafe", "strafe", "back", "back", "back"])
		"jump": _jump()
		"glide": _row(["glide", "glide", "glide", "dive", "dive", "dive"])
		"dash": _row(["dash", "dash", "dash", "land", "land", "land"])
		"melee": _melee()
		"guns": _guns()
		"emotes": _emotes()
		"states": _states()
		"kin": _kin(); cam.position = Vector3(0, 2.2, 6.2); cam.rotation = Vector3(-0.28, 0, 0)
	if lab == "jump":
		cam.position = Vector3(0, 2.6, 10.0); cam.rotation = Vector3(-0.1, 0, 0)
	if lab == "crowd":
		cam.position = Vector3(0, 9.0, 11.0); cam.rotation = Vector3(-0.7, 0, 0)
	if _arg("--lab-top") != "":
		cam.position = Vector3(0, 10.5, 8.0); cam.rotation = Vector3(-0.92, 0, 0); cam.fov = 44
	if _arg("--lab-side") != "":
		cam.position = Vector3(-9.5, 1.6, 0.6); cam.rotation = Vector3(-0.06, -1.5, 0); cam.fov = 48
	if _arg("--lab-grid") != "":
		_grid()
		return
	var ci := int(_arg("--lab-cell", "-1"))
	if ci >= 0 and ci < cells.size():
		# a close look at one of them, from the front three-quarters
		var at: Vector3 = (cells[ci]["base"] as Vector3) * Vector3(1, 0, 1) + Vector3(0, 0.75, 0)
		var yaw := float(_arg("--lab-yaw", "0.5"))
		var dist := float(_arg("--lab-dist", "3.4"))
		cam.position = at + Vector3(sin(yaw) * dist, 0.9, cos(yaw) * dist)
		cam.fov = 40
		add_child(cam)
		cam.look_at(at + Vector3(0, float(_arg("--lab-up", "0.0")), 0), Vector3.UP)
		cam.make_current()
		return
	add_child(cam)
	cam.make_current()

## A close-up of every cell at once: one small viewport per cell (all looking into this world),
## tiled over the screen, so a single screenshot shows them all up close.
func _grid() -> void:
	var only := _arg("--lab-only", "")
	if only != "":
		# keep just these cells (by index), hide the rest
		var keep: Array = Array(only.split(",")).map(func(x): return int(x))
		var kept: Array = []
		for i in cells.size():
			if i in keep: kept.append(cells[i])
			else:
				(cells[i]["h"] as Node3D).visible = false
				(cells[i]["label"] as Node3D).visible = false
		cells = kept
		var kk: Array = []
		for i in kin_cells.size():
			if i in keep: kk.append(kin_cells[i])
			else: (kin_cells[i]["k"] as Node3D).visible = false
		kin_cells = kk
	var n := cells.size() + kin_cells.size()
	var cols := 4 if n > 6 else 3
	if n <= 3: cols = n
	var rows := int(ceil(float(n) / cols))
	var sz := Vector2i(1280 / cols, 720 / rows)
	var layer := CanvasLayer.new(); add_child(layer)
	var yaw := float(_arg("--lab-yaw", "0.7"))
	var dist := float(_arg("--lab-dist", "3.6"))
	var i := 0
	for c in cells + kin_cells:
		var svc := SubViewportContainer.new()
		svc.position = Vector2((i % cols) * sz.x, (i / cols) * sz.y)
		svc.size = sz
		svc.stretch = true
		layer.add_child(svc)
		var sv := SubViewport.new()
		sv.size = sz
		sv.world_3d = get_viewport().find_world_3d()
		sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		svc.add_child(sv)
		var cam := Camera3D.new()
		var at: Vector3 = ((c["base"] as Vector3) * Vector3(1, 0, 1)) + Vector3(0, 0.75 if c.has("h") else 0.35, 0)
		var d := dist * ((c["h"] as Node3D).scale.y if c.has("h") else 0.55)
		at.y *= (c["h"] as Node3D).scale.y if c.has("h") else 1.0
		cam.fov = 40
		sv.add_child(cam)
		cam.position = at + Vector3(sin(yaw) * d, float(_arg("--lab-h", "0.45")) * d, cos(yaw) * d)
		cam.look_at(at, Vector3.UP)
		cam.current = true
		c["cam"] = cam
		c["cam_off"] = cam.position - at
		i += 1
	if c_label_hide(): pass

func c_label_hide() -> bool:
	for c in cells:
		(c["label"] as Label3D).font_size = 22
	return true

const LOOKS := [
	{"race": 0, "body": 1, "gender": 1, "face": 0, "skin": 1, "hair": 1, "hair_col": 2, "outfit": 3},
	{"race": 1, "body": 0, "gender": 0, "face": 2, "skin": 2, "hair": 3, "hair_col": 4, "outfit": 1},
	{"race": 2, "body": 2, "gender": 1, "face": 1, "skin": 19, "hair": 0, "hair_col": 6, "outfit": 6},
	{"race": 3, "body": 0, "gender": 0, "face": 3, "skin": 11, "hair": 1, "hair_col": 3, "outfit": 0},
	{"race": 4, "body": 1, "gender": 1, "face": 4, "skin": 12, "hair": 0, "hair_col": 5, "outfit": 4},
	{"race": 5, "body": 1, "gender": 0, "face": 0, "skin": 2, "hair": 3, "hair_col": 1, "outfit": 2},
]
const CLS := ["light", "medium", "heavy"]
const GUN := {"light": "smg", "medium": "rifle", "heavy": "minigun"}

func _hunter(cls: String, wpn: String, i: int, at: Vector3, mode: String, face := PI + 0.5) -> Dictionary:
	var h := Models.hunter(cls, Data.TEAM_COLORS[i % 4], wpn, "", LOOKS[i % LOOKS.size()])
	if _arg("--lab-grid") != "":
		# spread out so each close-up shows just its own hunter, all facing the same way
		at = Vector3(at.x * 2.6, at.y, at.z * 2.0)
		face = PI
	h.position = at
	h.rotation.y = face
	add_child(h)
	var l := Label3D.new(); l.text = mode; l.font_size = 36; l.pixel_size = 0.005
	l.position = at + Vector3(0, 2.0, 0); l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(l)
	var c := {"h": h, "a": HunterAnim.new(h), "mode": mode, "cls": cls, "base": at, "y": 0.0, "vy": 0.0, "t": 0.0, "i": i, "label": l}
	cells.append(c)
	return c

func _row(modes: Array) -> void:
	for i in modes.size():
		var cls: String = CLS[i % 3]
		_hunter(cls, GUN[cls], i, Vector3((i - (modes.size() - 1) * 0.5) * 1.6, 0, 0), modes[i])

func _idle() -> void:
	var n := 18 if lab == "crowd" else 6
	for i in n:
		var cls: String = CLS[i % 3]
		var w: String = (["twin_blades", "longsword", "greatsword"] if i % 6 >= 3 else [GUN["light"], GUN["medium"], GUN["heavy"]])[i % 3]
		var at := Vector3((i % 6 - 2.5) * 1.6, 0, (i / 6) * -2.2)
		var c := _hunter(cls, w, i, at, "idle")
		if lab == "idle":
			(c["a"] as HunterAnim).fidget_wait = 0.4 + i * 0.5

func _jump() -> void:
	for i in 6:
		var cls: String = CLS[i % 3]
		var c := _hunter(cls, GUN[cls], i, Vector3((i - 2.5) * 2.0, 0, 0), "hop" if i < 3 else "drop", PI + 0.7)
		if i >= 3:
			# a long drop: off a 3m ledge
			var hx: float = (c["h"] as Node3D).position.x
			c["base"] = Vector3(hx, 3.0, 0)

func _melee() -> void:
	var ws := [["light", "twin_blades"], ["medium", "longsword"], ["heavy", "greatsword"]]
	for i in 6:
		var w: Array = ws[i % 3]
		_hunter(w[0], w[1], i, Vector3((i - 2.5) * 2.0, 0, 0), "combo" if i < 3 else "charged")

func _guns() -> void:
	var ws := [["light", "smg"], ["light", "burst_rifle"], ["medium", "rifle"], ["medium", "shotgun"], ["heavy", "minigun"], ["medium", "sniper"]]
	for i in ws.size():
		_hunter(ws[i][0], ws[i][1], i, Vector3((i - 2.5) * 1.9, 0, 0), "fire+reload")

func _emotes() -> void:
	var ids := ["wave", "accept", "laugh", "follow", "truce", "gg", "thanks", "refuse"]
	for i in ids.size():
		var cls: String = CLS[i % 3]
		_hunter(cls, GUN[cls], i, Vector3((i - 3.5) * 1.55, 0, 0), "emote:" + ids[i], PI + 0.3)

func _states() -> void:
	var ss := ["downed", "crawl", "revive", "stomp", "base", "stun", "hit", "cast", "drink", "ledge"]
	for i in ss.size():
		var cls: String = CLS[i % 3]
		_hunter(cls, GUN[cls], i, Vector3((i % 5 - 2.0) * 2.1, 0, (i / 5) * -2.4), ss[i], PI + 0.4)

func _kin() -> void:
	var sp := ["cindle", "puddlet", "burrlet", "zapple", "pebbit", "wisplet", "cairnback", "zephyrak", "hivara"]
	var modes := ["idle", "walk", "run", "attack", "sleep", "happy", "jump"]
	var only := _arg("--kin-mode", "")
	for i in sp.size():
		if not Data.KIN.has(sp[i]): continue
		var mode: String = only if only != "" else modes[i % modes.size()]
		var k := Models.kin(sp[i], {"level": 9})
		k.position = Vector3((i % 5 - 2.0) * 1.5, 0, (i / 5) * -1.6)
		k.rotation.y = PI + 0.6
		add_child(k)
		var l := Label3D.new(); l.text = "%s %s" % [sp[i], mode]; l.font_size = 30; l.pixel_size = 0.005
		l.position = k.position + Vector3(0, 1.2, 0); l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(l)
		kin_cells.append({"k": k, "mode": mode, "base": k.position, "t": 0.0})

func _process(delta: float) -> void:
	time += delta
	if _arg("--lab-print") != "" and int(time * 2.0) != int((time - delta) * 2.0):
		for c in cells.slice(0, 2):
			var h: Node3D = c["h"]
			var aim: Node3D = h.get_node("Rig/Torso/Aim")
			var gun: Node3D = aim.get_node("Gun")
			var tor: Node3D = h.get_node("Rig/Torso")
			var hr: Node3D = tor.get_node("ArmRPivot/Elbow/Hand"); var hl: Node3D = tor.get_node("ArmLPivot/Elbow/Hand")
			print("  handR %s handL %s shR %s gripR %s gripL %s" % [tor.global_transform.inverse() * hr.global_position, tor.global_transform.inverse() * hl.global_position, tor.get_node("ArmRPivot").position, tor.global_transform.inverse() * (gun.global_transform * Vector3(0, -0.07, 0.04)), tor.global_transform.inverse() * (gun.global_transform * Vector3(0, -0.06, -0.2))])
			print("t%.1f %s aim_rot %s gun_pos %s gun_fwd %s torso %s" % [time, c["mode"], aim.rotation, gun.position, -(h.global_basis.inverse() * gun.global_basis.z).normalized(), h.get_node("Rig/Torso").rotation])
	if _arg("--lab-quit") != "" and time > float(_arg("--lab-quit")):
		get_tree().quit()
	for c in cells:
		_drive(c, delta)
	for kc in kin_cells:
		_drive_kin(kc, delta)

func _drive(c: Dictionary, dt: float) -> void:
	var h: Node3D = c["h"]
	var a: HunterAnim = c["a"]
	c["t"] = float(c["t"]) + dt
	var t: float = c["t"]
	var face := h.rotation.y
	var fwd := Vector3(-sin(face), 0, -cos(face))
	var right := Vector3(cos(face), 0, -sin(face))
	var s := {"face": face, "fired": 99.0}
	var mode: String = c["mode"]
	match mode:
		"run": s["vel"] = fwd * 5.2
		"sprint": s["vel"] = fwd * 7.2
		"strafe": s["vel"] = right * 5.0
		"back": s["vel"] = -fwd * 4.2
		"glide":
			s["gliding"] = true; s["grounded"] = false; s["vel"] = fwd * 6.0 + Vector3(0, -1.7, 0)
			h.get_node("Rig/Torso/Glider").visible = true
			h.position.y = 1.2
		"dive":
			s["diving"] = true; s["grounded"] = false; s["vel"] = fwd * 8.0 + Vector3(0, -10, 0)
			h.position.y = 1.4
		"dash":
			var ph := fmod(t, 1.4)
			s["rolling"] = ph < 0.18
			s["vel"] = fwd * (20.0 if ph < 0.18 else 0.0)
			s["dash_dir"] = Vector2(fwd.x, fwd.z)
		"land":
			# drops onto the ground from a height again and again
			var ph2 := fmod(t, 1.6)
			s["grounded"] = ph2 > 0.5
			s["vel"] = Vector3(0, -9.0 if ph2 <= 0.5 else 0.0, 0)
			h.position.y = maxf(0.0, (0.5 - ph2) * 4.0)
		"hop", "drop":
			_sim_jump(c, dt, s, fwd)
		"combo", "charged":
			var cyc := fmod(t, 2.0)
			var step := int(cyc / 0.42)
			s["fired"] = cyc if cyc < 1.5 else 99.0
			if mode == "combo":
				if step < 3 and step != int(c.get("last", -1)):
					c["last"] = step
					c["n"] = int(c.get("n", 0)) + 1
				if step >= 3: c["last"] = -1
				s["swing_n"] = int(c.get("n", 0)); s["combo"] = int(c.get("last", 0)) if int(c.get("last", -1)) >= 0 else 2
			else:
				s["charge"] = clampf(cyc / 0.8, 0.0, 1.0) if cyc < 0.8 else 0.0
				if cyc >= 0.8 and int(c.get("last", -1)) != 1:
					c["last"] = 1; c["n"] = int(c.get("n", 0)) + 1
				if cyc < 0.8: c["last"] = 0
				s["swing_n"] = int(c.get("n", 0)); s["combo"] = -1
		"fire+reload":
			var cyc2 := fmod(t, 4.0)
			if cyc2 < 1.4:
				var rate := 0.1 if c["h"].get_meta("wid") != "sniper" else 0.7
				c["since"] = float(c.get("since", 0.0)) + dt
				if float(c["since"]) >= rate: c["since"] = 0.0
				s["fired"] = float(c["since"])
			elif cyc2 < 2.0:
				s["fired"] = cyc2 - 1.4
			else:
				s["fired"] = cyc2 - 1.4
				s["reload"] = clampf((cyc2 - 2.0) / 1.8, 0.0, 1.0) if cyc2 < 3.8 else -1.0
		"downed": s["downed"] = true
		"crawl": s["downed"] = true; s["vel"] = fwd * 1.3
		"revive": s["reviving"] = true
		"stomp": s["stomp"] = fmod(t, 0.8) / 0.8
		"base": s["base"] = fmod(t, 3.0) / 3.0
		"stun": s["stun"] = true
		"hit":
			s["hit_t"] = fmod(t, 0.9)
			s["hit_dir"] = Vector2(fwd.x, fwd.z) * -1.0 if int(t / 0.9) % 2 == 0 else Vector2(right.x, right.z)
		"cast":
			s["cast"] = fmod(t, 1.2); s["cast_slot"] = "ult" if int(t / 1.2) % 2 == 1 else "sec"
		"drink": s["drink"] = fmod(t, 1.4) / 1.1 if fmod(t, 1.4) < 1.1 else -1.0
		"ledge": s["mantle"] = fmod(t, 1.0); s["grounded"] = false
	if mode.begins_with("emote:"):
		s["emote"] = mode.substr(6)
		s["emote_t"] = fmod(t, 3.0)
	if _arg("--lab-fidget") != "" and mode == "idle":
		a.fidget_wait = minf(a.fidget_wait, 0.2)
	a.update(dt, s)
	if c.has("cam") and mode in ["hop", "drop"]:
		var cam: Camera3D = c["cam"]
		cam.position = Vector3(h.position.x, h.position.y + 0.75 * h.scale.y, h.position.z) + (c["cam_off"] as Vector3)

## A jump: up from the ground (hop) or off a ledge (drop), then back to where it started.
func _sim_jump(c: Dictionary, dt: float, s: Dictionary, fwd: Vector3) -> void:
	var h: Node3D = c["h"]
	var base: Vector3 = c["base"]
	var y: float = c["y"]
	var vy: float = c["vy"]
	var airborne: bool = c.get("air", false)
	c["wait"] = float(c.get("wait", 0.6)) - dt
	if not airborne and float(c["wait"]) <= 0.0:
		airborne = true
		vy = 9.0
		y = base.y
	if airborne:
		vy = vy - 30.0 * dt if vy > 0.0 else move_toward(vy, -9.0, 30.0 * dt)
		y += vy * dt
		if y <= 0.0:
			y = 0.0; vy = 0.0; airborne = false
			c["wait"] = 1.2
	elif float(c["wait"]) < 0.9:
		y = base.y if float(c["wait"]) < 0.25 else 0.0
	c["y"] = y; c["vy"] = vy; c["air"] = airborne
	h.position = Vector3(base.x, y, base.z)
	s["grounded"] = not airborne
	s["vel"] = Vector3(fwd.x, 0, fwd.z) * (3.5 if airborne else 0.0) + Vector3(0, vy, 0)
	if airborne:
		s["air_h"] = y

func _drive_kin(kc: Dictionary, dt: float) -> void:
	var k: Node3D = kc["k"]
	kc["t"] = float(kc["t"]) + dt
	var t: float = kc["t"]
	var body: Node3D = k.get_node("Body")
	var mode: String = kc["mode"]
	var base: Vector3 = kc["base"]
	k.set_meta("kstate", "")
	k.set_meta("happy", false)
	match mode:
		"walk", "run":
			var sp := 1.4 if mode == "walk" else 3.6
			var x := fmod(t * sp, 1.6) - 0.8
			k.position = base + Vector3(x, 0, 0)
			k.rotation.y = -PI * 0.5
			body.position.y = absf(sin(t * (7.0 if mode == "walk" else 11.0))) * (0.05 if mode == "walk" else 0.12)
		"attack":
			k.set_meta("kstate", "attack" if fmod(t, 1.2) < 0.35 else "")
			body.rotation.x = -0.4 if fmod(t, 1.2) < 0.2 else 0.0
		"sleep":
			k.set_meta("kstate", "sleep")
		"happy":
			k.set_meta("happy", true)
			body.position.y = absf(sin(t * 10.0)) * 0.2
		"jump":
			var ph := fmod(t, 1.3)
			body.position.y = maxf(0.0, sin(clampf(ph / 0.7, 0.0, 1.0) * PI) * 0.6)
