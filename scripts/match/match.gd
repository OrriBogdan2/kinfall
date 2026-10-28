class_name Match
extends Node3D
## One PvPvE extraction match: islands, hunters and their kin, monsters, wild kin, chests and exits.
## The simulation runs at a fixed 60 steps per second; visuals interpolate between steps.

const DT := 1.0 / 60.0

var opts := {}
var world: World
var fx: Fx
var cam: CamRig
var hud: Node = null
var env: WorldEnvironment
var hunters: Array = []
var kins: Array = []
var mobs: Array = []
var shots: Array = []
var pickups: Array = []     # {pos, vel, kind:"gem"|"seed"|"tonic", v, key, node, t}
var chests: Array = []      # {pos, open, prog, node, tier}
var shrines: Array = []     # {pos, used, prog, node}
var breaks: Array = []      # {i, pos, kind, hp, node, dead}
var wpicks: Array = []      # found weapons on the ground {id, pos, wid, rar, node}
var wdrop_n := 0
var warden_done := false
# ---- tutorial
var tut_step := -1
var tut_text := ""
var tut_moved := 0.0
var tut_kills := 0
var tut_flag := false
var tut_down_t := 0.0
var tut_wait := 0.0
var tut_throws0 := 0
var portals: Array = []     # {pos, open_at, open, node}
var time := 0.0
var acc := 0.0
var player: Hunter = null
var over := false
var result := {}
var shot_pool: Array[MeshInstance3D] = []
var nid_n := 0
var feed: Array = []        # kill feed lines {text, t}
var pings: Array = []       # {pos, col, t}
var bubbles: Array = []     # {ent, text, t, cat}
var interact := {}          # what F would do right now for the local player
var paused := false
var slowmo := 0.0
var slow_k := 0.35
var killcam_text := ""
var hitstop := 0.0
var aim_line: MeshInstance3D
var aim_ring: MeshInstance3D
var muzzle_light: OmniLight3D
var collapse_warned := false
var rng := RandomNumberGenerator.new()
var pending_input := {"dash": false, "jump": false, "sig": false, "reload": false, "tonic": false, "throw": false, "skill": false, "ult": false}
var zones: Array = []      # hero areas: dome, sanctuary, well
var bot_brain := Bot.new()
var seed_val := 0
var length := 360.0
var net_on := false
var tier := 0
var T: Dictionary = {}
var is_host := true
var drop_n := 0
var ents_by_id := {}
var _net_seen_rec := {}
var _rev_out := {}
var _net_rev_t := 0.0
var _finish_now := false

func _ready() -> void:
	set_process(false)

func start(o: Dictionary) -> void:
	opts = o
	seed_val = int(o.get("seed", randi()))
	rng.seed = seed_val
	seed(seed_val)
	# real expeditions happen on the big map and start from the skyship
	big = not (o.get("tutorial", false) or o.get("training", false)) and o.get("big", true)
	length = float(o.get("length", Data.MATCH["length"] * (1.35 if big else 1.0)))
	tier = clampi(int(o.get("tier", 0)), 0, Data.TIERS.size() - 1)
	T = Data.TIERS[tier]
	_build_env()
	Sfx.play_music("hollow" if tier >= 2 else "match")
	Sfx.play_ambience("match")
	world = World.new()
	world.name = "World"
	world.biome = T["biome"].duplicate()
	world.clouds = T["clouds"]
	add_child(world)
	world.generate(seed_val, 128 if big else 64, 16 if big else 7)
	world.build_meshes()
	fx = Fx.new(); fx.name = "Fx"; add_child(fx)
	cam = CamRig.new(); cam.name = "Cam"; add_child(cam)
	cam.lead = float(Settings.get_v("cam_lead"))
	_build_shot_pool()
	if o.has("net"):
		net_on = true
		is_host = Net.me == String(o["net"]["host"])
		Net.begin_match("kf-" + String(o["net"]["mid"]), String(o["net"]["host"]), self)
	_spawn_pads_and_portals()
	_spawn_hunters()
	_spawn_mobs()
	_spawn_chests()
	_spawn_breakables()
	if o.get("break_demo", false) and player and not breaks.is_empty():
		# test: stand by some breakables with two found weapons on the ground
		var b0: Vector3 = breaks[0]["pos"]
		for b in breaks:
			if b["kind"] == "barrel": b0 = b["pos"]; break
		player.teleport(b0 + Vector3(2.2, 0, 0.6))
		spawn_weapon("rail", 3, b0 + Vector3(1.6, 0, 1.8), "", false)
		spawn_weapon("stinger", 4, b0 + Vector3(3.0, 0, 1.6), "", false)
	_spawn_wild()
	var Hud = load("res://scripts/ui/hud.gd")
	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.setup(self)
	if player and player.dropping:
		hud.toast("Steer to choose where you land", Color("f3eee2"))
	if player:
		cam.snap(player.pos)
	_build_aim()
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	set_process(true)
	Bridge.kin_lines_for_match(self)

func next_id(prefix: String) -> String:
	nid_n += 1
	return "%s%d" % [prefix, nid_n]

# ------------------------------------------------------------------ setup
func _build_env() -> void:
	env = WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = T["sky"]
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = T["ambient"]
	e.ambient_light_energy = 0.45
	e.fog_enabled = true
	e.fog_light_color = Color("1b2238")
	e.fog_density = 0.0
	e.fog_height = -2.0
	e.fog_height_density = 0.18
	e.glow_enabled = true
	e.glow_intensity = 0.6
	e.glow_bloom = 0.05
	e.glow_hdr_threshold = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.0
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_color = T["sun"]
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	sun.shadow_bias = 0.03
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.shadow_opacity = 0.85
	add_child(sun)

func _build_shot_pool() -> void:
	var mesh := Models.sphere(0.5, 10)
	for i in 160:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = Models.glow_mat(Color.WHITE)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		shot_pool.append(mi)

func _spawn_pads_and_portals() -> void:
	for pd in world.pads:
		var n := Models.jump_pad(Color("8fe3c8"))
		n.position = pd["pos"]
		n.rotation.y = atan2(-(pd["land"].x - pd["pos"].x), -(pd["land"].z - pd["pos"].z))
		add_child(n)
		pd["node"] = n
		# where it goes: a sign over the pad, and the flight path and landing ring when you're close
		var to_role: String = world.islands[pd["to"]]["role"] if pd["to"] < world.islands.size() else ""
		var lbl := Label3D.new()
		lbl.text = "to " + String({"heart": "the Heart", "camp": "the monster camp", "nest": "the kin nest", "grove": "the grove", "shrine": "the shrine"}.get(to_role, "the next island"))
		lbl.font = UI.big; lbl.font_size = 34; lbl.pixel_size = 0.01; lbl.outline_size = 10
		lbl.modulate = Color("c9fff0"); lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED; lbl.no_depth_test = true
		lbl.position = pd["pos"] + Vector3(0, 1.3, 0)
		add_child(lbl)
		var arc := Node3D.new()
		var a: Vector3 = pd["pos"]; var b: Vector3 = pd["land"]
		var dist := Vector2(b.x - a.x, b.z - a.z).length()
		var hh := maxf(a.y, b.y) - a.y + 2.5 + dist * 0.12
		var dm := Models.sphere(0.07, 8)
		var mat := Models.glow_mat(Color("bff7e6"))
		for i in range(1, 18):
			var k := i / 18.0
			var mi := MeshInstance3D.new(); mi.mesh = dm; mi.material_override = mat
			mi.position = Vector3(lerpf(a.x, b.x, k), lerpf(a.y, b.y, k) + 4.0 * hh * k * (1.0 - k) + 0.3, lerpf(a.z, b.z, k))
			arc.add_child(mi)
		var ring := MeshInstance3D.new()
		var rm := PlaneMesh.new(); rm.size = Vector2(1.6, 1.6); ring.mesh = rm
		ring.material_override = Models.ring_mat(Color("8fe3c8"))
		ring.position = b + Vector3(0, 0.05, 0)
		arc.add_child(ring)
		arc.visible = false
		add_child(arc)
		pd["arc"] = arc
	var open_at := float(Data.MATCH["portal_open"]) * length / float(Data.MATCH["length"])
	for i in world.portal_spots.size():
		var n := Models.portal(Color("8fe3c8"))
		n.position = world.portal_spots[i]
		add_child(n)
		portals.append({"pos": world.portal_spots[i], "open_at": (1e9 if opts.get("tutorial", false) or opts.get("training", false) else open_at + i * 35.0), "open": false, "node": n})

func make_hunter(id: String, team: int, cls: String, pname: String, ctrl: String, kin_rec: Dictionary, at: Vector3, kit := {}) -> Hunter:
	var h := Hunter.new()
	h.init_hunter(self, id, team, cls, pname, ctrl, kit)
	h.lives = 99 if (opts.get("tutorial", false) or opts.get("training", false)) else int(T.get("lives", 2))
	add_child(h)
	h.teleport(at)
	hunters.append(h)
	ents_by_id[id] = h
	if not kin_rec.is_empty():
		var k := Kin.new()
		k.init_kin(self, id + "k", kin_rec["species"], kin_rec, h)
		add_child(k)
		k.teleport(at + Vector3(0, 1.5, 0))
		kins.append(k)
		ents_by_id[k.nid] = k
		h.kin = k
	return h

func my_kit() -> Dictionary:
	return {"hero": Save.d.get("hero", ""), "weapon": Save.d.get("weapon", ""), "perk": Save.d.get("perk", "")}

func bot_kit() -> Dictionary:
	var heroes: Array = Data.HEROES.keys()
	var hero: String = heroes[rng.randi_range(0, heroes.size() - 1)]
	var pool: Array = Data.CLASSES[Data.HEROES[hero]["cls"]]["weapons"]
	var w: String = Data.HEROES[hero]["weapon"] if rng.randf() < 0.6 else pool[rng.randi_range(0, pool.size() - 1)]
	var perks: Array = Data.PERKS.keys()
	return {"hero": hero, "weapon": w, "perk": perks[rng.randi_range(0, perks.size() - 1)]}

func bot_kin_record() -> Dictionary:
	var sp: String = Data.KIN.keys()[rng.randi_range(0, Data.KIN.size() - 1)]
	var rec := Save.new_kin(sp)
	rec["trust"] = rng.randf_range(40, 80)
	rec["level"] = rng.randi_range(1, 4 + tier * 3)
	Evo.simulate(rec, rng)
	return rec

func _spawn_hunters() -> void:
	var n_teams := int(opts.get("teams", 4))
	var squad := int(opts.get("squad", 1))
	# one starting island per squad, spread out as far as possible
	var by_isl := {}
	for sp in world.spawns:
		var ii := world.island_of(sp.x, sp.z)
		if not by_isl.has(ii): by_isl[ii] = sp
	var pool: Array = by_isl.values()
	pool.shuffle()
	var spots: Array = []
	if pool.size() > 0:
		spots.append(pool.pop_back())
	while pool.size() > 0:
		var best := 0; var bd := -1.0
		for i in pool.size():
			var dmin := 1e9
			for q in spots: dmin = minf(dmin, Vector2(pool[i].x - q.x, pool[i].z - q.z).length())
			if dmin > bd: bd = dmin; best = i
		spots.append(pool[best]); pool.remove_at(best)
	if spots.is_empty():
		spots = world.spawns.duplicate()
	if opts.get("tutorial", false):
		# start somewhere quiet
		for sp in world.spawns:
			var isl := world.island_of(sp.x, sp.z)
			if isl > 0 and world.islands[isl]["role"] in ["grove", "nest"]:
				spots = [sp]; break
	var names: Array = Data.BOT_NAMES.duplicate(); names.shuffle()
	if net_on:
		_spawn_net_hunters(spots, names)
		return
	for t in n_teams:
		var base: Vector3 = spots[t % spots.size()] if spots.size() > 0 else world.random_ground()
		for s in squad:
			var at := base
			if s > 0:
				for _k in 30:
					var q := base + Vector3(rng.randf_range(-1.6, 1.6), 0, rng.randf_range(-1.6, 1.6))
					if not world.is_void(q.x, q.z) and not world.is_block(q.x, q.z) and absf(world.ground_at(q.x, q.z) - base.y) < 0.3:
						at = Vector3(q.x, world.ground_at(q.x, q.z), q.z); break
			if t == 0 and s == 0 and not opts.get("spectate", false):
				var rec: Dictionary = Save.active_kin()
				player = make_hunter("p0", 0, Save.d.get("cls", "medium"), Save.d.get("name", "Hunter"), "bot" if opts.get("autoplay", false) else "local", rec, at, my_kit())
				if opts.get("autoplay", false):
					player.ai = bot_brain.new_mind(rng, 0.7)
				player.teleport(at)
				player.tonics = int(Save.d["items"].get("tonic", 0))
				_apply_home_perks(player)
				if player.kin:
					_apply_treat(player.kin)
				_start_drop(player, at)
				continue
			var bk := bot_kit()
			var h := make_hunter(next_id("b"), t, "", names.pop_back() if names.size() > 0 else "Bot", "bot", bot_kin_record(), at, bk)
			h.ai = bot_brain.new_mind(rng, float(opts.get("bot_skill", 0.6)))
			h.tonics = 1
			_start_drop(h, at)

## Every match starts in the sky. Hunters glide down from above their squad's side of the map
## and steer to wherever they want to land.
func _start_drop(h: Hunter, at: Vector3) -> void:
	if opts.get("no_drop", false):
		return
	if big and time < 1.0:
		# everyone boards the skyship; bots plan to jump when it passes nearest their spot
		if ship.is_empty(): _setup_ship()
		h.riding = true
		h.ai["land"] = at
		var a: Vector3 = ship["a"]; var b: Vector3 = ship["b"]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var k := clampf(Vector2(at.x - a.x, at.z - a.z).dot(ab) / ab.length_squared(), 0.04, 0.97)
		h.ai["jump_at"] = clampf(k * float(ship["dur"]) - 2.2 + rng.randf_range(-0.8, 0.8), 0.6, float(ship["ride"]) - 0.5)
		h.teleport(ship_pos())
		return
	# straight above your squad's landing spot, so letting go of the keys still lands you safely
	var off := Vector3(rng.randf_range(-1.0, 1.0), 0, rng.randf_range(-1.0, 1.0))
	if world.is_void(at.x + off.x, at.z + off.z):
		off = Vector3.ZERO
	h.teleport(at + off + Vector3(0, 17.0, 0))
	h.dropping = true
	h.grounded = false
	h.gliding = true
	h.glide_k = 1.0
	h.ai["land"] = at

# ---- the skyship
const SHIP_Y := 26.0
const SHIP_SPEED := 11.0
var big := false
var ship := {}

func _setup_ship() -> void:
	var ang := rng.randf() * TAU
	var c := Vector3(world.w / 2.0 + rng.randf_range(-10, 10), SHIP_Y, world.h / 2.0 + rng.randf_range(-10, 10))
	var dir := Vector3(cos(ang), 0, sin(ang))
	var half := world.w * 0.6
	# "ride" is the last moment to jump: still over the islands on the far side
	ship = {"a": c - dir * half, "b": c + dir * half, "dur": 2.0 * half / SHIP_SPEED, "ride": (half + 34.0) / SHIP_SPEED, "dir": dir}
	var n := Models.skyship()
	n.rotation.y = atan2(-dir.x, -dir.z)
	add_child(n)
	ship["node"] = n

func ship_pos() -> Vector3:
	if ship.is_empty() or not ship.has("a"):
		return Vector3.ZERO
	return (ship["a"] as Vector3).lerp(ship["b"], clampf(time / float(ship["dur"]), 0.0, 1.0))

func ship_jump(h: Hunter) -> void:
	if not h.riding:
		return
	h.riding = false
	var off := Vector3(rng.randf_range(-0.8, 0.8), 0, rng.randf_range(-0.8, 0.8))
	h.teleport(ship_pos() + Vector3(0, -1.5, 0) + off)
	h.dropping = true
	h.gliding = true
	h.glide_k = 1.0
	h.grounded = false
	h.vel = ship["dir"] * 6.0
	if h == player:
		sfx("whoosh", null, -2.0)
		if hud: hud.toast("Steer with %s%s%s%s to pick where you land" % [Settings.key_cap("up"), Settings.key_cap("left"), Settings.key_cap("down"), Settings.key_cap("right")], Color("cfeaff"))

func _update_ship(dt: float) -> void:
	if ship.is_empty():
		return
	var n: Node3D = ship["node"]
	# drawn along the line past the end too, so it sails off over the clouds
	n.position = (ship["a"] as Vector3).lerp(ship["b"], time / float(ship["dur"])) + Vector3(0, 1.4 + sin(time * 1.3) * 0.25, 0)
	for pn in ["PropL", "PropR"]:
		(n.get_node(pn) as Node3D).rotation.z += dt * 14.0
	var done := time >= float(ship["ride"])
	for h in hunters:
		if not h.riding or h.remote:
			continue
		var auto: bool = h.ctrl == "bot" or opts.get("autoplay", false)
		if done or (auto and time >= float(h.ai.get("jump_at", 0.0))):
			ship_jump(h)
	if done and time > float(ship["dur"]) * 1.5:
		n.queue_free()
		ship["node"] = null
		ship["gone"] = true

func on_drop_landed(h: Hunter) -> void:
	h.inv_t = maxf(h.inv_t, 2.0)     # a moment to get your bearings after landing
	if world.is_block(h.pos.x, h.pos.z):
		var best := h.pos; var bd := 1e9
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				var q := Vector3(floor(h.pos.x) + dx + 0.5, 0, floor(h.pos.z) + dz + 0.5)
				if not world.is_void(q.x, q.z) and not world.is_block(q.x, q.z):
					var d := Vector2(dx, dz).length()
					if d < bd: bd = d; best = Vector3(q.x, world.ground_at(q.x, q.z), q.z)
		h.teleport(best)
	fx.dust(h.pos, 14)
	fx.ring(h.pos, 2.2, Color(1, 1, 1, 0.8), 0.3)
	sfx("land", h.pos, -2.0, 0.8)
	h.squash = 0.4
	if h == player:
		shake(0.25, h.pos)

## Perks you carry from home: your workshop, and the projects your guild has finished.
func _apply_home_perks(h: Hunter) -> void:
	if Save.has_building("workshop"):
		h.glide_max *= 1.5
	var gp: Array = Save.d.get("guild_perks", [])
	if gp.has("lighthouse"):
		h.glide_max *= 1.25
	if gp.has("forge"):
		h.tonics += 1
		h.free_tonics = 1

func _apply_treat(k: Kin) -> void:
	match String(Save.d.get("treat", "")):
		"treat_power": k.power = 1.25
		"treat_hardy": k.max_hp *= 1.4; k.hp = k.max_hp
		"treat_calm": k.trust = minf(100.0, k.trust + 12.0)

func _spawn_mobs() -> void:
	if net_on and not is_host:
		return
	for c in world.camp_spots:
		var p: Vector3 = c["pos"]
		var comp: Array
		match String(c.get("kind", "normal")):
			"heavy": comp = ["brute", "spitter", "skitter"]
			"light": comp = ["skitter", "skitter"] if rng.randf() < 0.6 else ["spitter", "skitter"]
			_:
				if rng.randf() < 0.15 * tier + 0.2:
					comp = ["brute", "skitter", "skitter"]
				elif rng.randf() < 0.5:
					comp = ["skitter", "skitter", "spitter"]
				else:
					comp = ["spitter", "skitter", "skitter"]
		for kk in comp:
			var q := p
			for _t in 20:
				var cand := p + Vector3(rng.randf_range(-1.8, 1.8), 0, rng.randf_range(-1.8, 1.8))
				if not world.is_void(cand.x, cand.z) and not world.is_block(cand.x, cand.z):
					q = Vector3(cand.x, world.ground_at(cand.x, cand.z), cand.z); break
			spawn_mob(kk, q)

func spawn_mob(kk: String, at: Vector3) -> Mob:
	var mb := Mob.new()
	mb.init_mob(self, next_id("m"), kk, at, float(T.get("mob", 1.0)) if not T.is_empty() else 1.0)
	add_child(mb)
	mobs.append(mb)
	ents_by_id[mb.nid] = mb
	return mb

func _spawn_chests() -> void:
	for cs in world.chest_spots:
		var p: Vector3 = cs["pos"]
		var t := int(cs["tier"])
		var n := Models.chest(t)
		n.position = p
		n.rotation.y = rng.randf() * TAU
		add_child(n)
		chests.append({"pos": p, "open": false, "prog": 0.0, "node": n, "tier": t})
	for sp in world.shrine_spots:
		var n := Models.shrine()
		n.position = sp
		add_child(n)
		shrines.append({"pos": sp, "used": false, "prog": 0.0, "node": n})
	for isl in world.islands:
		if isl.has("nest"):
			var n := Models.nest()
			n.position = isl["nest"]
			add_child(n)

# ------------------------------------------------------------------ breakables and found weapons
const BREAK_HP := {"pot": 6.0, "crate": 22.0, "barrel": 12.0}

func _spawn_breakables() -> void:
	for b in world.break_spots:
		var n := Models.breakable(String(b["kind"]))
		n.position = b["pos"]
		n.rotation.y = rng.randf() * TAU
		add_child(n)
		breaks.append({"i": breaks.size(), "pos": b["pos"], "kind": b["kind"], "hp": BREAK_HP[b["kind"]], "node": n, "dead": false})
	# the weapons lying in the open are the same for everyone in an online match
	var wr := RandomNumberGenerator.new(); wr.seed = seed_val * 31 + 7
	var keys: Array = Data.WEAPONS.keys()
	for i in world.weapon_spots.size():
		spawn_weapon(String(keys[wr.randi() % keys.size()]), Data.roll_rarity(wr, 1 if tier >= 2 else 0), world.weapon_spots[i], "ws%d" % i, false)

func spawn_weapon(w: String, rar: int, at: Vector3, id := "", send := true) -> void:
	if id == "":
		wdrop_n += 1
		id = "w%s_%d" % [player.nid if player else "x", wdrop_n]
	var n := Models.weapon_drop(w, rar)
	n.position = at
	add_child(n)
	wpicks.append({"id": id, "pos": at, "wid": w, "rar": rar, "node": n})
	if net_on and send:
		net_event(["wdrop", id, w, rar, _r(at.x), _r(at.y), _r(at.z)])

func _take_weapon(h: Hunter, wp: Dictionary, from_net := false) -> void:
	wpicks.erase(wp)
	(wp["node"] as Node3D).queue_free()
	if from_net:
		return
	if net_on:
		net_event(["wtake", wp["id"], h.nid, wp["wid"], wp["rar"]])
	var old_w := h.wid; var old_r := h.wrar
	h.equip(String(wp["wid"]), int(wp["rar"]))
	var ba := randf() * TAU
	var back := Vector3(cos(ba), 0, sin(ba)) * 0.9
	spawn_weapon(old_w, old_r, Vector3(h.pos.x + back.x, h.ground(), h.pos.z + back.z))
	var col: Color = Data.RARITY[int(wp["rar"])]["color"]
	sfx("reload", h.pos, 0.0, 0.8)
	fx.ring(h.pos, 1.4, col, 0.35)
	fx.burst(h.pos + Vector3(0, 0.9, 0), col, 14, 3.0, 0.5)
	if h == player:
		var r: Dictionary = Data.RARITY[int(wp["rar"])]
		hud.toast("%s  ·  +%d%% damage" % [h.wpn["name"], int(round((float(r["dmg"]) - 1.0) * 100.0))] if int(wp["rar"]) > 0 else String(h.wpn["name"]), col)

func _update_wpicks(dt: float) -> void:
	for wp in wpicks:
		var n: Node3D = wp["node"]
		var sp: Node3D = n.get_node("Spin")
		sp.rotation.y += dt * 1.6
		sp.position.y = 0.7 + sin(time * 2.4 + float(wp["pos"].x)) * 0.08
	# bots grab anything better that they walk past
	for h in hunters:
		if h.ctrl != "bot" or h.out or h.downed or h.dropping or h.riding or h.remote:
			continue
		for wp in wpicks:
			if int(wp["rar"]) > h.wrar and h.flat_dist(wp["pos"]) < 1.4 and absf(h.pos.y - float(wp["pos"].y)) < 1.0:
				_take_weapon(h, wp)
				break

## Damage a crate, pot or barrel. Breaking it is shared online; whoever broke it rolls for a weapon.
func hit_break(b: Dictionary, dmg: float, by: Ent) -> void:
	if b["dead"]:
		return
	b["hp"] = float(b["hp"]) - dmg
	var n: Node3D = b["node"]
	n.scale = Vector3(1.12, 0.9, 1.12)
	create_tween().tween_property(n, "scale", Vector3.ONE, 0.12)
	if float(b["hp"]) <= 0.0:
		_break(b, by)

func _break(b: Dictionary, by: Ent, from_net := false) -> void:
	if b["dead"]:
		return
	b["dead"] = true
	if net_on and not from_net:
		net_event(["brk", b["i"], by.nid if by else ""])
	var at: Vector3 = b["pos"]
	var kind_s: String = b["kind"]
	(b["node"] as Node3D).queue_free()
	var col: Color = {"pot": Color("c9825a"), "crate": Color("a07448"), "barrel": Color("c8483a")}[kind_s]
	fx.burst(at + Vector3(0, 0.4, 0), col, 16, 4.0, 0.5, 9.0, 0.8)
	sfx("knock" if kind_s == "crate" else "hit", at, -4.0, 0.7 if kind_s == "crate" else 1.3)
	var loot := float(T["loot"])
	match kind_s:
		"pot":
			for i in randi_range(1, 2):
				drop("gem", at + Vector3(0, 0.5, 0), maxi(1, int(round(2 * loot))))
			if randf() < 0.2:
				drop("seed", at + Vector3(0, 0.5, 0), 1, Data.pick_seed())
		"crate":
			for i in randi_range(2, 4):
				drop("gem", at + Vector3(0, 0.5, 0), maxi(1, int(round(2 * loot))))
			if randf() < 0.3:
				drop("tonic", at + Vector3(0, 0.5, 0), 1)
			if not from_net and randf() < 0.16:
				var keys: Array = Data.WEAPONS.keys()
				spawn_weapon(String(keys[randi() % keys.size()]), Data.roll_rarity(rng), at)
		"barrel":
			_barrel_boom(at, by)

## An exploding barrel: hurts and throws everyone nearby, its breaker included.
func _barrel_boom(at: Vector3, by: Ent) -> void:
	var radius := 2.6
	var c := at + Vector3(0, 0.4, 0)
	fx.ring(c, radius, Color("ff8a4a"), 0.35)
	fx.burst(c, Color("ffb070"), 34, 7.0, 0.6, 6.0, 1.5)
	fx.flash(c, Color("ffd9a0"), radius * 0.5, 0.1)
	sfx("boom", c, 2.0, 0.85)
	shake(0.6, c)
	var bodies: Array = []
	for h in hunters:
		if h.hittable(): bodies.append(h)
	for mb in mobs:
		if not mb.dead: bodies.append(mb)
	for k in kins:
		if k.hittable(): bodies.append(k)
	for e in bodies:
		if e.remote:
			continue
		var d := Vector2(e.pos.x - c.x, e.pos.z - c.z).length()
		if d < radius + e.r and absf(e.pos.y + 0.5 - c.y) < 2.0:
			var f := 1.0 - 0.5 * minf(1.0, d / radius)
			var dir := Vector2(e.pos.x - c.x, e.pos.z - c.z).normalized()
			var credit: Ent = by if by and by.team != e.team else null
			e.hurt(22.0 * f, credit, {"src": "boom", "kb": dir * 10.0 * f, "lift": 7.5 * f})
	# chain into other barrels nearby
	for b in breaks:
		if not b["dead"] and Vector2(b["pos"].x - c.x, b["pos"].z - c.z).length() < radius + 0.4 and absf(b["pos"].y - at.y) < 2.0:
			hit_break(b, 30.0, by)

## Breakables are solid: push bodies out, and dashing straight through one smashes it.
func _collide_breaks() -> void:
	if breaks.is_empty():
		return
	var bodies: Array = []
	for h in hunters:
		if h.hittable() and h.grap.is_empty(): bodies.append(h)
	for mb in mobs:
		if not mb.dead: bodies.append(mb)
	for e in bodies:
		for b in breaks:
			if b["dead"]:
				continue
			var bp: Vector3 = b["pos"]
			if absf(e.pos.y - bp.y) > 0.6:
				continue
			var d := Vector2(e.pos.x - bp.x, e.pos.z - bp.z)
			var mind: float = e.r + 0.36
			var l := d.length()
			if l >= mind:
				continue
			if e is Hunter and (e as Hunter).roll_t > 0.0 and not e.remote:
				_break(b, e)
				continue
			if l < 0.0001:
				d = Vector2(1, 0); l = 0.0001
			var push := d / l * (mind - l)
			if world.occupy(e.pos.x + push.x, e.pos.z + push.y, e.r, e.pos.y, e.grounded) == 0.0:
				e.pos.x += push.x; e.pos.z += push.y

func _spawn_wild() -> void:
	if net_on and not is_host:
		return
	for p in world.wild_spots:
		var sp: String = Data.KIN.keys()[rng.randi_range(0, Data.KIN.size() - 1)]
		var rec := Save.new_kin(sp)
		rec["level"] = rng.randi_range(T["kin_lvl"][0], T["kin_lvl"][1])
		Evo.simulate(rec, rng)
		spawn_wild(rec, p)

func spawn_wild(rec: Dictionary, at: Vector3, dazed := false) -> Kin:
	var k := Kin.new()
	k.init_kin(self, next_id("w"), rec["species"], rec, null)
	add_child(k)
	k.teleport(at)
	k.home = at
	kins.append(k)
	ents_by_id[k.nid] = k
	if net_on:
		_net_seen_rec[k.nid] = rec
	if dazed:
		k.hp = 1.0
		k._daze()
	return k

# ------------------------------------------------------------------ queries
func local_player() -> Hunter:
	return player

func foes_of(team: int) -> Array:
	var out: Array = []
	for h in hunters:
		if h.team != team and h.hittable() and not h.downed:
			out.append(h)
	for k in kins:
		if k.dead or k.is_wild():
			continue
		if k.team != team and k.hittable():
			out.append(k)
	if team != -2:
		for mb in mobs:
			if not mb.dead:
				out.append(mb)
	return out

func dmg_mult(h: Hunter) -> float:
	return 1.25 if h and h.bless_t > 0.0 else 1.0

func sfx(n: String, p = null, vol := 0.0, pitch := 1.0) -> void:
	Sfx.play(n, p, vol, 0.07, pitch)

func shake(a: float, at: Vector3) -> void:
	if player == null:
		return
	var d := Vector2(at.x - player.pos.x, at.z - player.pos.z).length()
	cam.add_trauma(a * clampf(1.0 - d / 14.0, 0.0, 1.0))

func direction_word(from: Vector3, to: Vector3) -> String:
	var d := Vector2(to.x - from.x, to.z - from.z)
	var a := rad_to_deg(atan2(d.y, d.x))
	var words := ["east", "southeast", "south", "southwest", "west", "northwest", "north", "northeast"]
	return "to the " + words[int(round(fposmod(a, 360.0) / 45.0)) % 8]

func ping(p: Vector3, col: Color) -> void:
	pings.append({"pos": p, "col": col, "t": 0.0})
	sfx("ping", null, -10.0)

func kin_bark(k: Kin, txt: String, cat: String) -> void:
	for b in bubbles:
		if b["ent"] == k:
			bubbles.erase(b); break
	bubbles.append({"ent": k, "text": txt, "t": 0.0, "cat": cat})
	if k.owner_h == player:
		var s := "kin_happy"
		if cat in ["refuse", "hesitate", "scared", "revive_low", "ignore"]: s = "kin_unsure"
		elif cat in ["callout", "wild"]: s = "kin_alert"
		sfx(s, null, -6.0)

var feed_all: Array = []

func add_feed(t: String) -> void:
	feed_all.append("%d %s" % [int(time), t])
	feed.append({"text": t, "t": 0.0})
	if feed.size() > 5:
		feed.pop_front()

# ------------------------------------------------------------------ events
func on_damage(target: Ent, by: Ent, d: float, o: Dictionary) -> void:
	var crit: bool = o.get("crit", false)
	var src: String = o.get("src", "")
	var credit: Ent = by
	if by is Kin and by.owner_h:
		credit = by.owner_h
	if credit is Hunter and target != credit:
		credit.dmg_done += d
		if not credit.remote and target.team != credit.team and src != "burn":
			credit.ult = minf(1.0, credit.ult + d / 320.0 * (1.3 if credit.perk == "overcharge" else 1.0))
	var mine := credit == player or (target == player)
	var col := Color("fff4d6")
	if crit: col = Color("ffd23f")
	if target == player: col = Color("ff6a5a")
	elif target is Kin and target.owner_h == player: col = Color("ffa08a")
	if mine or (player and target.flat_dist(player) < 12.0):
		fx.number(target.pos + Vector3(0, 1.5 if target is Hunter else 1.0, 0), d, col, crit)
	if credit == player and target != player and src != "burn":
		sfx("crit" if crit else "hit", target.pos, -2.0)
		if hud: hud.hitmarker(crit)
	if target == player:
		sfx("hurt", null, -4.0)
		cam.add_trauma(clampf(d / 40.0, 0.12, 0.45))
		if hud: hud.hurt_flash(d)
	fx.burst(target.pos + Vector3(0, 0.8, 0), Color("fff2d0") if not crit else Color("ffd23f"), 6 if d < 10 else 12, 3.5, 0.3, 8.0, 0.7)

## Cancels anything a hero had queued up: ability sequences, a charging Ram, a beam windup.
func cancel_abilities(h: Hunter) -> void:
	h.acts.clear()
	h.charge = {}
	if h.acts_tele:
		fx.end_telegraph(h.acts_tele)
		h.acts_tele = null

func knock(h: Hunter, by: Ent, _o: Dictionary) -> void:
	if h.downed or h.out:
		return
	cancel_abilities(h)
	if by is Hunter and by.hero == "nyx" and by.team != h.team:
		by.sig_cd = 0.0
	h.downed = true
	h.down_hp = Data.MATCH["down_hp"]
	h.hp = 0.0
	h.revive = 0.0
	h.cloak_t = 0.0
	h.reload_t = 0.0
	h.grap = {}
	var credit: Ent = by
	if by is Kin and by.owner_h:
		credit = by.owner_h
	if h == player:
		# getting knocked hits hard: slow time, flash red, pull the camera in
		_slow(0.55, 0.3)
		cam.punch(0.12)
		if hud: hud.flash(Color("ff3a2a"), 0.3)
		Sfx.duck(0.6)
		killcam_text = ("Knocked down by %s" % credit.pname) if credit is Hunter and credit != h else "You're down"
	if credit is Hunter and credit != h:
		credit.knocks += 1
		add_feed("%s knocked %s" % [credit.pname, h.pname])
		if credit == player:
			_reward_moment(h.pos)
			if player.kin and player.kin.state != "fainted":
				player.kin.bark("kill")
	else:
		add_feed("%s went down" % h.pname)
	sfx("knock", h.pos, 0.0)
	fx.burst(h.pos + Vector3(0, 0.8, 0), Data.TEAM_COLORS[h.team % 6], 24, 5.0, 0.6)
	if net_on and not h.remote:
		net_event(["knock", h.nid, credit.nid if credit else ""])
	if h == player:
		cam.add_trauma(0.6)
		if h.kin and h.kin.state != "fainted":
			h.kin.bark("owner_down")
	_check_team(h.team)

func freeze_frame(t: float) -> void:
	hitstop = maxf(hitstop, t)

func _reward_moment(at: Vector3) -> void:
	_slow(0.22, 0.35)
	freeze_frame(0.07)
	cam.add_trauma(0.35)
	cam.punch(0.08)
	if hud: hud.flash(Color.WHITE, 0.25)
	fx.ring(at, 3.0, Color(1, 0.95, 0.8, 0.9), 0.35)
	fx.burst(at + Vector3(0, 1.0, 0), Color("ffd23f"), 26, 6.0, 0.6, 6.0, 1.2)
	Sfx.duck(0.25)
	sfx("kill", null, -2.0)

func _slow(t: float, k: float) -> void:
	if net_on:
		return
	slow_k = k if slowmo <= 0.0 else minf(slow_k, k)
	slowmo = maxf(slowmo, t)

## A hero's ultimate going off: punch the camera for the one who used it.
func ult_moment(h: Hunter) -> void:
	var col: Color = Data.HEROES[h.hero]["color"]
	fx.ring(h.pos, 4.5, Color(col, 0.9), 0.45)
	fx.burst(h.pos + Vector3(0, 1.2, 0), col, 30, 6.0, 0.6, 2.0, 1.3)
	if h == player:
		cam.punch(0.1)
		cam.add_trauma(0.3)
		if hud: hud.flash(col, 0.22)
		freeze_frame(0.05)

func _check_team(team: int) -> void:
	if opts.get("tutorial", false) or opts.get("training", false):
		return
	var members: Array = hunters.filter(func(x): return x.team == team and not x.out and not x.extracted)
	if members.is_empty():
		return
	for x in members:
		if not x.downed:
			return
		if x.kin and not x.kin.dead and x.kin.state not in ["fainted"] and x.kin.hp > 0.0:
			return
	for x in members:
		if not x.remote:
			eliminate(x, x.last_hit_by, "team wiped")

func revive_hunter(h: Hunter, by: Ent) -> void:
	if h.remote:
		return
	if net_on:
		net_event(["up", h.nid])
	h.downed = false
	h.hp = h.max_hp * 0.4
	h.revive = 0.0
	h.inv_t = 1.5
	sfx("revive", h.pos, 0.0)
	fx.ring(h.pos, 1.8, Color("9ee2a0"), 0.4)
	add_feed("%s is back up" % h.pname)
	if by is Hunter and by != h:
		by.dmg_done += 0.0

func eliminate(h: Hunter, by: Ent, why: String, final := false) -> void:
	if h.out:
		return
	if h.lives > 1 and not h.remote and not over and not final:
		_lose_life(h, by, why)
		return
	cancel_abilities(h)
	h.out = true
	h.downed = false
	if net_on and not h.remote:
		net_event(["out", h.nid, by.nid if by else "", why])
	var credit: Ent = by
	if by is Kin and by.owner_h:
		credit = by.owner_h
	if credit is Hunter and credit != h and credit.team != h.team:
		credit.kills += 1
	add_feed("%s is out" % h.pname if why != "abyss" else "%s fell into the abyss" % h.pname)
	# everything they carried spills out; caught kin escape
	if net_on and not is_host and not h.remote:
		net_event(["spill", _r(h.pos.x), _r(h.pos.y), _r(h.pos.z), h.gems, h.seeds, h.caught])
	elif not world.is_void(h.pos.x, h.pos.z) and not h.remote:
		var n := mini(10, int(ceil(h.gems / 5.0)))
		for i in n:
			drop("gem", h.pos + Vector3(0, 0.5, 0), maxi(1, h.gems / maxi(1, n)))
		for s in h.seeds:
			drop("seed", h.pos + Vector3(0, 0.5, 0), int(h.seeds[s]), s)
		for rec in h.caught:
			spawn_wild(rec, h.pos, true)
	h.lost_gems = h.gems
	h.gems = 0; h.seeds = {}; h.caught = []
	if h.kin:
		if h.ctrl == "bot" and not world.is_void(h.pos.x, h.pos.z) and h.kin.state != "fainted":
			# a bot's kin is left behind: weakened and catchable
			var rec: Dictionary = h.kin.rec.duplicate(true)
			var at := h.kin.pos if h.kin.state != "shoulder" else h.pos
			if world.is_void(at.x, at.z):
				at = h.pos
			spawn_wild(rec, at, true)
		h.kin.dead = true
		h.kin.visible = false
	if h == player:
		result = {"extracted": false, "why": why}
		_end_soon(2.2)
		if why != "abyss":
			_slow(0.8, 0.3)
		killcam_text = ("Taken out by %s" % credit.pname) if credit is Hunter and credit != h else ("You fell" if why == "abyss" else "You're out")
	elif credit == player and player and not player.out:
		# taking out the last rival squad gets the big moment
		var rivals := hunters.any(func(x): return x.team != player.team and not x.out and not x.extracted)
		if not rivals:
			_slow(1.0, 0.22)
			cam.punch(0.16)
			if hud:
				hud.flash(Color("ffd23f"), 0.3)
				hud.toast("Last squad down", Color("ffd23f"))
			Sfx.duck(1.0)
	_check_last()

## Losing a life: some of what you carry spills where you went down, and you glide back in
## somewhere quiet with full health and a moment of protection.
func _lose_life(h: Hunter, by: Ent, why: String) -> void:
	cancel_abilities(h)
	h.lives -= 1
	var lose := int(ceil(h.gems * 0.3))
	if lose > 0 and not world.is_void(h.pos.x, h.pos.z):
		if net_on and not is_host:
			net_event(["spill", _r(h.pos.x), _r(h.pos.y), _r(h.pos.z), lose, {}, []])
		else:
			var n := mini(5, lose)
			for i in n:
				# the last pile takes the remainder so nothing is lost to rounding
				drop("gem", h.pos + Vector3(0, 0.5, 0), (lose / n) + (lose % n if i == n - 1 else 0))
	elif lose > 0:
		h.lost_gems += lose
	h.gems -= lose
	if net_on:
		net_event(["up", h.nid])
	var credit: Ent = by.owner_h if by is Kin and by.owner_h else by
	if credit is Hunter and credit != h and credit.team != h.team:
		credit.kills += 1
	if h.lives < 50:
		add_feed("%s lost a life (%d left)" % [h.pname, h.lives])
	h.downed = false
	h.down_hp = 0.0
	h.revive = 0.0
	h.hp = h.max_hp
	h.inv_t = 3.0
	h.vel = Vector3.ZERO
	h.grap = {}; h.pad = {}; h.charge = {}; h.roll_t = 0.0
	h.stun_t = 0.0
	# the safest place: the spawn farthest from anyone who isn't on your team
	var best: Vector3 = world.spawns[0] if world.spawns.size() > 0 else world.random_ground()
	var bd := -1.0
	for sp in world.spawns:
		var dmin := 1e9
		for o in hunters:
			if o.team != h.team and not o.out and not o.extracted:
				dmin = minf(dmin, Vector2(o.pos.x - sp.x, o.pos.z - sp.z).length())
		if dmin > bd: bd = dmin; best = sp
	var was: bool = opts.get("no_drop", false)
	opts["no_drop"] = false
	_start_drop(h, best)
	opts["no_drop"] = was
	if h.kin and h.kin.state == "fainted":
		h.kin.hp = h.kin.max_hp * 0.5
	if h == player and h.lives < 50:
		killcam_text = ""
		_slow(0.6, 0.35)
		if hud:
			hud.flash(Color("ff3a2a"), 0.35)
			hud.toast(("Last life. Be careful" if h.lives == 1 else "%d lives left" % h.lives) + ("  ·  you dropped %d gems" % lose if lose > 0 else ""), Color("ffb0a0"))

func _check_last() -> void:
	var teams := {}
	for h in hunters:
		if not h.out and not h.extracted:
			teams[h.team] = true
	if teams.size() <= 1:
		for p in portals:
			if not p["open"]:
				p["open_at"] = minf(p["open_at"], time)

func on_fell(e: Ent) -> void:
	if e is Hunter and opts.get("autoplay", false):
		print("FELL ", e.pname, " hist=", e.get_meta("hist", []))
	if e is Hunter:
		if e.out:
			return
		sfx("fall", e.pos, 0.0)
		if e == player and S_dev_god():
			var back: Vector3 = e.ai.get("land", world.spawns[0] if world.spawns.size() > 0 else world.random_ground())
			e.teleport(back)
			if opts.get("tutorial", false):
				hud.toast("Careful near the edges", Color("f3eee2"))
			e.vel = Vector3.ZERO
			return
		var by: Ent = e.last_hit_by if time - e.kb_t < 4.0 else null
		eliminate(e, by, "abyss")
	elif e is Mob:
		e.dead = true
		e._cancel_tele()
		on_mob_dead(e, e.last_hit_by, {"src": "fall"})
	elif e is Kin:
		e.dead = true

func S_dev_god() -> bool:
	return bool(opts.get("god", false)) or bool(opts.get("tutorial", false)) or bool(opts.get("training", false)) or Game.god

func on_mob_dead(mb: Mob, by: Ent, _o: Dictionary) -> void:
	if net_on:
		net_event(["mobdead", mb.nid, by.nid if by else ""])
	var credit: Ent = by
	if by is Kin and by.owner_h:
		credit = by.owner_h
	if credit == player:
		tut_kills += 1
	sfx("kill", mb.pos, -6.0, 1.3)
	fx.burst(mb.pos + Vector3(0, 0.6, 0), mb.md["color"], 22, 5.0, 0.6)
	if not world.is_void(mb.pos.x, mb.pos.z):
		for i in int(mb.md["gems"]):
			drop("gem", mb.pos + Vector3(0, 0.6, 0), int(round(3 * float(T["loot"]))))
		if rng.randf() < (0.35 if mb.mkind == "brute" else 0.12):
			drop("seed", mb.pos + Vector3(0, 0.6, 0), 1, Data.pick_seed())
	if credit == player and player.kin and randf() < 0.15:
		player.kin.bark("kill")

func on_kin_faint(k: Kin) -> void:
	if k.owner_h == player:
		add_feed("%s fainted" % k.rec.get("name", "Your kin"))
	_check_team(k.team)

func on_wild_dazed(k: Kin) -> void:
	if player and k.flat_dist(player) < 10.0:
		add_feed("The wild %s is dazed. Hold F to catch it!" % Data.KIN[k.species]["name"])

func on_ledge_grab(h: Hunter) -> void:
	if h == player and hud and h.over_void():
		hud.toast("Caught the ledge", Color("cfe6c0"))

# ------------------------------------------------------------------ pickups
func drop(kind_s: String, at: Vector3, v: int, key := "", pid := "", vel0 = null) -> void:
	if net_on and not is_host and pid == "":
		return
	if pid == "":
		drop_n += 1
		pid = "d%d" % drop_n
	var n: Node3D
	match kind_s:
		"gem": n = Models.gem()
		"seed": n = Models.seed_bag(Data.CROPS[key]["color"])
		"tonic": n = Models.tonic()
		_: n = Models.gem()
	add_child(n)
	n.position = at
	var a := randf() * TAU
	var v0: Vector3 = vel0 if vel0 != null else Vector3(cos(a) * randf_range(1.5, 3.5), randf_range(4.0, 7.0), sin(a) * randf_range(1.5, 3.5))
	pickups.append({"id": pid, "pos": at, "vel": v0, "kind": kind_s, "v": v, "key": key, "node": n, "t": 0.0})
	if net_on and is_host:
		net_event(["drop", pid, kind_s, v, key, _r(at.x), _r(at.y), _r(at.z), _r(v0.x), _r(v0.y), _r(v0.z)])

func _update_pickups(dt: float) -> void:
	for p in pickups.duplicate():
		p["t"] += dt
		var pos: Vector3 = p["pos"]
		var g := world.ground_at(pos.x, pos.z)
		var v: Vector3 = p["vel"]
		var grabbed := false
		if p["t"] > 0.5:
			for h in hunters:
				if h.out or h.extracted or h.downed or h.remote:
					continue
				if net_on and not is_host and h != player:
					continue
				var d: float = Vector2(h.pos.x - pos.x, h.pos.z - pos.z).length()
				if d < 2.2 and absf(h.pos.y - pos.y) < 2.0:
					var dir: Vector3 = (h.pos + Vector3(0, 0.6, 0) - pos)
					v = dir.normalized() * (6.0 + (2.2 - d) * 6.0)
					if dir.length() < 0.6:
						_collect(h, p)
						grabbed = true
					break
		if grabbed:
			continue
		if v.length() < 20.0:
			v.y -= 20.0 * dt
		pos += v * dt
		if g > World.VOID + 1.0 and pos.y < g + 0.3 and pos.y > g - 1.0:
			pos.y = g + 0.3
			v = Vector3(v.x * 0.6, -v.y * 0.3 if v.y < -2.0 else 0.0, v.z * 0.6)
		p["pos"] = pos; p["vel"] = v
		var n: Node3D = p["node"]
		n.position = pos + Vector3(0, sin(time * 3.0 + p["v"]) * 0.06, 0)
		n.rotation.y += dt * 2.0
		if pos.y < -12.0:
			n.queue_free(); pickups.erase(p)

func _collect(h: Hunter, p: Dictionary) -> void:
	p["node"].queue_free()
	pickups.erase(p)
	if net_on:
		net_event(["take", p["id"]])
	match p["kind"]:
		"gem": h.gems += int(round(float(p["v"]) * (1.25 if h.perk == "scavenger" else 1.0)))
		"seed": h.seeds[p["key"]] = int(h.seeds.get(p["key"], 0)) + int(p["v"])
		"tonic":
			h.tonics = mini(3, h.tonics + 1)
			if h == player: hud.toast("+1 tonic", Color("8ff0a0"))
	if h == player:
		sfx("pickup", null, -8.0, 1.0 + minf(0.4, h.gems * 0.004))
		if p["kind"] == "seed":
			hud.toast("+%d %s seed" % [p["v"], Data.CROPS[p["key"]]["name"]], Data.CROPS[p["key"]]["color"])

# ------------------------------------------------------------------ shots
func spawn_shot(by: Ent, at: Vector3, v2: Vector2, dmg: float, life: float, size: float, col: Color, extra := {}) -> void:
	var mi: MeshInstance3D = null
	for s in shot_pool:
		if not s.visible:
			mi = s; break
	if mi:
		mi.visible = true
		mi.material_override.set_shader_parameter("color", col)
		mi.scale = Vector3.ONE * size * 2.0
		mi.global_position = at
	var team := by.team
	shots.append({"pos": at, "vel": v2, "dmg": dmg, "team": team, "by": by, "life": life, "r": size, "col": col, "x": extra, "node": mi, "prev": at, "start": at})
	if net_on and not extra.get("cos", false) and not by.remote:
		net_event(["s", _r(at.x), _r(at.y), _r(at.z), _r(v2.x), _r(v2.y), snappedf(life, 0.01), snappedf(size, 0.01), col.to_html(false), float(extra.get("boom", 0.0)), team, 1 if extra.get("mob", false) else 0])
	if by is Hunter:
		fx.flash(at, col.lightened(0.4), 0.22, 0.05)

func _update_shots(dt: float) -> void:
	for s in shots.duplicate():
		s["life"] -= dt
		var p: Vector3 = s["pos"]
		s["prev"] = p
		var v: Vector2 = s["vel"]
		var step := Vector3(v.x, 0, v.y) * dt
		var n := int(ceil(step.length() / 0.25))
		var hit := false
		for i in n:
			p += step / n
			# domes stop shots fired at them from outside
			if _dome_blocks(s, p):
				_shot_end(s, p, null)
				hit = true; break
			# terrain and rocks
			if world.is_block(p.x, p.z) and world.ground_at(p.x, p.z) + World.BLOCK_H > p.y or world.ground_at(p.x, p.z) > p.y:
				_shot_end(s, p, null)
				hit = true; break
			var bh := _shot_break(s, p)
			if not bh.is_empty():
				if not s["x"].get("cos", false) and not s["x"].has("boom") and not s["x"].get("mob", false):
					hit_break(bh, float(s["dmg"]), s["by"])
				_shot_end(s, p, null)
				hit = true; break
			for e in _shot_targets(s):
				var ey: float = e.pos.y + (0.9 if e is Hunter else 0.5)
				if Vector2(e.pos.x - p.x, e.pos.z - p.z).length() < e.r + s["r"] + 0.08 and absf(ey - p.y) < 1.1:
					_shot_end(s, p, e)
					hit = true; break
			if hit:
				break
		if hit:
			continue
		s["pos"] = p
		if s["life"] <= 0.0:
			_shot_end(s, p, null)

func _shot_break(s: Dictionary, p: Vector3) -> Dictionary:
	for b in breaks:
		if not b["dead"] and absf(p.y - (float(b["pos"].y) + 0.4)) < 0.75 and Vector2(b["pos"].x - p.x, b["pos"].z - p.z).length() < 0.36 + float(s["r"]):
			return b
	return {}

func _shot_targets(s: Dictionary) -> Array:
	var x: Dictionary = s["x"]
	var out: Array = []
	if x.get("cos", false):
		# a remote shooter's bullet stops on whatever it visibly hits; the owner reports the damage
		for h in hunters:
			if h.team != s["team"] and h.hittable(): out.append(h)
		for mb in mobs:
			if not mb.dead and not x.get("mob", false): out.append(mb)
		return out
	if x.get("mob", false):
		for h in hunters:
			if h.hittable() and not h.downed: out.append(h)
		for k in kins:
			if not k.is_wild() and k.hittable(): out.append(k)
		return out
	for h in hunters:
		if h.team != s["team"] and h.hittable(): out.append(h)
	for k in kins:
		if k.team != s["team"] and k.hittable(): out.append(k)
	for mb in mobs:
		if not mb.dead: out.append(mb)
	return out

func _shot_end(s: Dictionary, at: Vector3, e: Ent) -> void:
	shots.erase(s)
	if s["node"]:
		s["node"].visible = false
	var x: Dictionary = s["x"]
	if x.get("cos", false):
		if x.get("boom", 0.0) > 0.0:
			fx.ring(at, x["boom"], Color("ffb070"), 0.3)
			fx.burst(at, Color("ffb070"), 26, 6.0, 0.5, 6.0, 1.3)
			sfx("boom", at, 0.0)
			shake(0.45, at)
		else:
			fx.burst(at, s["col"], 5, 2.0, 0.25, 6.0, 0.6)
		return
	if x.has("boom"):
		_boom(s, at)
		return
	if e == null:
		fx.burst(at, s["col"], 5, 2.0, 0.25, 6.0, 0.6)
		return
	var by: Ent = s["by"]
	var dmg: float = s["dmg"]
	var crit := false
	if e.stun_t > 0.0 and not x.get("mob", false):
		dmg *= 1.5
		crit = true
	if x.get("crit", false) and not crit:
		dmg *= 1.5
		crit = true
	if x.has("far") and Vector2(at.x - s["start"].x, at.z - s["start"].z).length() > float(x["far"]):
		dmg *= 1.25
	var dir: Vector2 = (s["vel"] as Vector2).normalized()
	var o := {"src": "shot", "crit": crit}
	if float(x.get("kb", 0.0)) > 0.0:
		o["kb"] = dir * float(x["kb"])
	if x.has("burn"): o["burn"] = x["burn"]
	if x.has("slow"): o["slow"] = x["slow"]
	if x.has("root"): o["root"] = x["root"]
	if x.has("stun"): o["stun"] = x["stun"]
	if x.get("hook", false) and by:
		# drag it back toward whoever threw the hook
		var back := Vector2(by.pos.x - e.pos.x, by.pos.z - e.pos.z)
		o["kb"] = back.normalized() * clampf(back.length() * 2.2, 6.0, 15.0)
		o["lift"] = 3.0
		o["slow"] = 2.0
		fx.bolt(by.pos + Vector3(0, 0.95, 0), e.pos + Vector3(0, 0.8, 0), Color("e0b05a"))
		net_fx(["bolt", _r(by.pos.x), _r(by.pos.y + 0.95), _r(by.pos.z), _r(e.pos.x), _r(e.pos.y + 0.8), _r(e.pos.z), "e0b05a"])
	e.hurt(dmg, by, o)

func _boom(s: Dictionary, at: Vector3) -> void:
	var x: Dictionary = s["x"]
	var radius: float = x["boom"]
	fx.ring(at, radius, Color("ffb070"), 0.3)
	fx.burst(at, Color("ffb070"), 26, 6.0, 0.5, 6.0, 1.3)
	fx.flash(at, Color("ffd9a0"), radius * 0.45, 0.08)
	sfx("boom", at, 0.0)
	shake(0.45, at)
	var by: Ent = s["by"]
	if not x.get("mob", false):
		for b in breaks:
			if not b["dead"] and Vector2(b["pos"].x - at.x, b["pos"].z - at.z).length() < radius + 0.36 and absf(float(b["pos"].y) + 0.4 - at.y) < 2.0:
				hit_break(b, float(s["dmg"]), by)
	for e in _shot_targets(s):
		var d := Vector2(e.pos.x - at.x, e.pos.z - at.z).length()
		if d < radius + e.r and absf(e.pos.y + 0.5 - at.y) < 2.0:
			var f := 1.0 - 0.45 * minf(1.0, d / radius)
			var dir := Vector2(e.pos.x - at.x, e.pos.z - at.z).normalized()
			var o := {"src": "boom", "kb": dir * float(x.get("boom_kb", 8.0)) * f, "lift": 7.0 * f}
			if x.has("burn"): o["burn"] = x["burn"]
			e.hurt(float(s["dmg"]) * f, by, o)

# ------------------------------------------------------------------ main loop
func _process(delta: float) -> void:
	if paused and not net_on:
		return
	_tips()
	if hitstop > 0.0 and not net_on:
		hitstop -= delta
		_gather_input()
		return
	var d := minf(delta, 0.1)
	if slowmo > 0.0:
		slowmo -= d
		d *= slow_k
	_gather_input()
	acc += d
	var steps := 0
	while acc >= DT and steps < 6:
		acc -= DT
		steps += 1
		step(DT)
	var alpha := acc / DT
	for e in hunters: e.render(delta, alpha)
	for e in kins: e.render(delta, alpha)
	for e in mobs: e.render(delta, alpha)
	for s in shots:
		if s["node"]:
			var mi: MeshInstance3D = s["node"]
			mi.global_position = (s["prev"] as Vector3).lerp(s["pos"], alpha)
			var v: Vector2 = s["vel"]
			if v.length() > 1.0:
				mi.look_at(mi.global_position + Vector3(v.x, 0, v.y), Vector3.UP)
				var r: float = s["r"]
				mi.scale = Vector3(r * 2.0, r * 2.0, r * 2.0 + v.length() * 0.025)
	if player and player.riding:
		# aboard the skyship: a wide view of the whole map below
		cam.zoom_to = 2.4
		cam.follow(Vector3(player.pos.x, 16.0 / 0.6, player.pos.z), delta, false)
	elif player and not player.out and not player.downed:
		cam.zoom_to = 1.45 if player.dropping else 1.0
		cam.follow(player.prev.lerp(player.pos, alpha), delta, true)
	elif player and (player.downed or player.out):
		# death camera: frame you and whoever got you
		var foc := player.prev.lerp(player.pos, alpha)
		if player.pos.y < -2.0:
			foc = cam.focus
		var killer: Ent = player.last_hit_by
		if killer is Kin and killer.owner_h: killer = killer.owner_h
		if killer is Hunter and killer != player and not killer.out and killer.flat_dist(player) < 16.0:
			foc = foc.lerp(killer.pos, 0.5 if player.downed else 0.85)
		cam.zoom_to = 0.8
		cam.follow(foc, delta, false)
	elif player:
		cam.follow(cam.focus, delta, false)
	_update_aim(alpha)
	for pd in world.pads:
		var top: Node3D = pd["node"].get_node("Top")
		top.scale = Vector3.ONE * (1.0 + sin(time * 5.0) * 0.06)
		if pd.has("arc") and player:
			var near := Vector2(player.pos.x - pd["pos"].x, player.pos.z - pd["pos"].z).length() < 6.0
			(pd["arc"] as Node3D).visible = near or player.pad.size() > 0 and (player.pad["to"] as Vector3).distance_to(pd["land"]) < 0.5
	for b in bubbles.duplicate():
		b["t"] += delta
		if b["t"] > 2.6: bubbles.erase(b)
	for p in pings.duplicate():
		p["t"] += delta
		if p["t"] > 4.0: pings.erase(p)
	for f in feed.duplicate():
		f["t"] += delta
		if f["t"] > 6.0: feed.erase(f)

func _gather_input() -> void:
	if player == null or player.out:
		return
	var mv := Vector2(Input.get_axis("left", "right"), Input.get_axis("up", "down"))
	if mv.length() > 1.0:
		mv = mv.normalized()
	player.inp["move"] = mv
	player.inp["aim"] = cam.mouse_on_plane(player.pos.y + 0.95)
	player.inp["fire"] = Input.is_action_pressed("fire") and not paused
	if paused:
		player.inp["move"] = Vector2.ZERO
	player.inp["interact"] = Input.is_action_pressed("interact")
	player.inp["glide"] = Input.is_action_pressed("jump") and not paused
	for a in [["dash", "dash"], ["jump", "jump"], ["signature", "sig"], ["reload", "reload"], ["tonic", "tonic"], ["throw", "throw"], ["kin_skill", "skill"], ["ultimate", "ult"]]:
		if Input.is_action_just_pressed(a[0]):
			pending_input[a[1]] = true

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu") and not over and not result.get("ending", false) and not Overlay.is_open():
		Overlay.open_pause("match")

## Called by the Overlay whenever one of its menus opens over this match.
func on_menu_opened() -> void:
	paused = true
	if not Overlay.closed.is_connected(_on_menu_closed):
		Overlay.closed.connect(_on_menu_closed, CONNECT_ONE_SHOT)

func _on_menu_closed() -> void:
	paused = false
	if not over:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

func step(dt: float) -> void:
	if over:
		return
	time += dt
	if Game.god and player and not player.out:
		# admin god mode: full health, endless ammo, nothing on cooldown
		player.hp = player.max_hp
		player.ammo = int(player.wpn["mag"])
		player.sig_cd = 0.0
		player.ult = 1.0
		player.dashes = player.max_dashes()
		player.glide_fuel = 1.0
		if player.downed: revive_hunter(player, player)
	if opts.get("ability_demo", false) and player and not player.dropping:
		var best: Ent = null; var bd := 1e9
		for f in foes_of(player.team):
			if player.flat_dist(f) < bd: bd = player.flat_dist(f); best = f
		if best:
			player.inp["aim"] = best.pos + Vector3(0, 0.9, 0)
			player.inp["fire"] = bd < 10.0
			if bd > 6.0: player.inp["move"] = player.dir_to(best)
			else: player.inp["move"] = Vector2.ZERO
		if int(time * 60.0) % 90 == 0: player.inp["sig"] = true
		if time > 4.0 and int(time * 60.0) % 240 == 0:
			player.ult = 1.0; player.inp["ult"] = true
	if opts.get("ledge_demo", false) and player and time < 0.05:
		# test: start just off the edge of your island, a few metres below the lip
		var p0 := player.pos
		for i in 60:
			var q := p0 + Vector3(0.5 * i, 0, 0)
			if world.is_void(q.x, q.z):
				player.teleport(Vector3(q.x + 1.0, player.pos.y - 4.0, q.z)); player.grounded = false
				break
	if opts.get("glide_demo", false) and player:
		if time < 0.05:
			player.teleport(player.pos + Vector3(0, 6, 0)); player.grounded = false
		player.inp["glide"] = true
		player.inp["move"] = Vector2(1, 0.3).normalized()
	if player and not player.out:
		for k in ["dash", "jump", "sig", "reload", "tonic", "ult"]:
			if pending_input[k]:
				player.inp[k] = true
				pending_input[k] = false
		if pending_input["throw"]:
			pending_input["throw"] = false
			_player_throw()
		if pending_input["skill"]:
			pending_input["skill"] = false
			if player.kin and not player.downed and not player.dropping:
				player.kin.command_skill(_ground_aim(player))
	for h in hunters:
		if h.ctrl == "bot" and not h.remote and not h.out and not h.extracted:
			bot_brain.think(self, h, dt)
	for h in hunters: h.sim(dt)
	if opts.get("autoplay", false) and int(time * 60.0) % 15 == 0:
		for h in hunters:
			var hist: Array = h.get_meta("hist", [])
			hist.append("%.1f:(%.1f,%.1f,%.1f) v(%.1f,%.1f,%.1f) g%d f%.2f r%.2f gr%d void%d gl%d fuel%.1f kb%.1f dn%d st%.1f cd%.1f %s" % [time, h.pos.x, h.pos.y, h.pos.z, h.vel.x, h.vel.y, h.vel.z, int(h.grounded), h.fly_t, h.roll_t, int(h.grap.size() > 0), int(h.over_void()), int(h.gliding), h.glide_fuel, time - h.kb_t, int(h.downed), h.stun_t, h.grap_cd, String(h.ai.get("goal_kind", ""))])
			if hist.size() > 10: hist.pop_front()
			h.set_meta("hist", hist)
	for k in kins: k.sim(dt)
	for mb in mobs: mb.sim(dt)
	_separate()
	_collide_breaks()
	_update_shots(dt)
	_update_pickups(dt)
	_update_wpicks(dt)
	_update_pads(dt)
	if not ship.is_empty() and not ship.get("gone", false):
		_update_ship(dt)
	_update_interact(dt)
	_update_portals(dt)
	_update_events()
	_update_zones(dt)
	if opts.get("tutorial", false):
		if opts.get("tut_test", false):
			_tut_drive()
		_update_tutorial(dt)
	if opts.get("training", false):
		_update_training(dt)
	_update_rules(dt)
	if net_on:
		_net_rev_t -= dt
		if _net_rev_t <= 0.0:
			_net_rev_t = 0.1
			_process_net_revives()
		Net.tick(dt)

func _ground_aim(h: Hunter) -> Vector3:
	var a: Vector3 = h.inp["aim"]
	var g := world.ground_at(a.x, a.z)
	return Vector3(a.x, g if g > World.VOID + 1.0 else h.pos.y, a.z)

func _player_throw() -> void:
	var k: Kin = player.kin
	if k == null or player.downed or player.dropping:
		return
	if k.state == "shoulder":
		k.throw_to(_ground_aim(player))
	elif k.state in ["active", "flying"]:
		k.recall()
	elif k.state == "fainted" and hud:
		hud.toast("%s is resting" % k.rec.get("name", "Your kin"), Color("a2a8bb"))

func _separate() -> void:
	var bodies: Array = []
	for h in hunters:
		if h.hittable() and h.grap.is_empty(): bodies.append(h)
	for mb in mobs:
		if not mb.dead: bodies.append(mb)
	for k in kins:
		if k.state in ["active", "wild", "dazed", "returning"] and not k.dead: bodies.append(k)
	for i in bodies.size():
		var a: Ent = bodies[i]
		for j in range(i + 1, bodies.size()):
			var b: Ent = bodies[j]
			if absf(a.pos.y - b.pos.y) > 1.0:
				continue
			var d := Vector2(b.pos.x - a.pos.x, b.pos.z - a.pos.z)
			var mind := a.r + b.r
			var l := d.length()
			if l < mind and l > 0.0001:
				var push := d / l * (mind - l) * 0.5
				var wa := 1.0 / a.mass(); var wb := 1.0 / b.mass()
				var tot := wa + wb
				var pa := -push * (wa / tot) * 2.0
				var pb := push * (wb / tot) * 2.0
				# bodies push each other around, but never off an edge
				if world.occupy(a.pos.x + pa.x, a.pos.z + pa.y, a.r, a.pos.y, a.grounded) == 0.0:
					a.pos.x += pa.x; a.pos.z += pa.y
				if world.occupy(b.pos.x + pb.x, b.pos.z + pb.y, b.r, b.pos.y, b.grounded) == 0.0:
					b.pos.x += pb.x; b.pos.z += pb.y

func _update_pads(dt: float) -> void:
	for pd in world.pads:
		pd["cd"] = maxf(0.0, pd["cd"] - dt)
		for h in hunters:
			if h.out or h.downed or h.fly_t > 0.0 or h.pad.size() > 0 or h.remote or h.vel.y > 0.5:
				continue
			var p: Vector3 = pd["pos"]
			if Vector2(h.pos.x - p.x, h.pos.z - p.z).length() < 0.8 and h.pos.y - p.y < 0.4 and h.pos.y - p.y > -0.3:
				h.pad_launch(pd["land"])
				sfx("jump", h.pos, -2.0, 0.8)
				fx.burst(h.pos + Vector3(0, 0.3, 0), Color("8fe3c8"), 16, 5.0, 0.5, 2.0)
		for k in kins:
			if k.state == "active" and Vector2(k.pos.x - pd["pos"].x, k.pos.z - pd["pos"].z).length() < 0.7:
				k.state = "returning"

func _update_interact(dt: float) -> void:
	for h in hunters:
		if h.out or h.extracted or h.downed or h.dropping:
			continue
		var want: bool = h.inp.get("interact", false)
		if not want:
			h.swap_hold = false
		var best := {}
		# 1. revive a downed teammate
		for o in hunters:
			if o != h and o.team == h.team and o.downed and not o.out and h.flat_dist(o) < 1.8:
				best = {"kind": "revive", "ent": o, "label": "Hold F to revive %s" % o.pname}
				break
		# 2. catch a dazed wild kin
		if best.is_empty():
			for k in kins:
				if k.state == "dazed" and not k.dead and h.flat_dist(k) < 1.9:
					best = {"kind": "catch", "ent": k, "label": "Hold F to catch the %s" % Data.KIN[k.species]["name"]}
					break
		# 3. swap to a weapon on the ground
		if best.is_empty():
			var bd := 1.5
			for wp in wpicks:
				var d: float = h.flat_dist(wp["pos"])
				if d < bd and absf(h.pos.y - float(wp["pos"].y)) < 1.2:
					bd = d
					var r: Dictionary = Data.RARITY[int(wp["rar"])]
					var nm: String = Data.weapon_stats(String(wp["wid"]), int(wp["rar"]))["name"]
					var extra := "  (+%d%% damage)" % int(round((float(r["dmg"]) - 1.0) * 100.0)) if int(wp["rar"]) > 0 else ""
					best = {"kind": "weapon", "wp": wp, "label": "Press %s to take %s%s" % [Settings.key_cap("interact"), nm, extra], "col": r["color"]}
		# 4. open a chest
		if best.is_empty():
			for c in chests:
				if not c["open"] and h.flat_dist(c["pos"]) < 1.6:
					best = {"kind": "chest", "chest": c, "label": ["Hold F to open", "Hold F to open the rare chest", "Hold F to open the vault"][int(c.get("tier", 0))]}
					break
		# 4. pray at a shrine
		if best.is_empty():
			for sh in shrines:
				if not sh["used"] and h.flat_dist(sh["pos"]) < 1.8:
					best = {"kind": "shrine", "shrine": sh, "label": "Hold F to pray: full heal and +25% damage"}
					break
		if h == player:
			interact = best
		if best.is_empty() or not want:
			continue
		match best["kind"]:
			"weapon":
				if not h.swap_hold:
					h.swap_hold = true
					_take_weapon(h, best["wp"])
			"revive":
				var o: Hunter = best["ent"]
				if o.remote:
					_rev_out[o.nid] = float(_rev_out.get(o.nid, 0.0)) + dt / Data.MATCH["revive_time"] * (1.3 if h.hero == "sage" else 1.0)
					o.revive += dt / Data.MATCH["revive_time"] * (1.3 if h.hero == "sage" else 1.0)
				else:
					o.revive += dt / Data.MATCH["revive_time"] * (1.3 if h.hero == "sage" else 1.0)
					if o.revive >= 1.0:
						revive_hunter(o, h)
			"catch":
				var k: Kin = best["ent"]
				k.catch_prog += dt / 1.3
				if k.catch_prog >= 1.0:
					_catch(h, k)
			"chest":
				var c: Dictionary = best["chest"]
				c["prog"] += dt / (0.7 + 0.4 * int(c.get("tier", 0)))
				if c["prog"] >= 1.0:
					_open_chest(h, c)
			"shrine":
				var sh: Dictionary = best["shrine"]
				sh["prog"] += dt / 1.2
				if sh["prog"] >= 1.0:
					_use_shrine(h, sh)

func _catch(h: Hunter, k: Kin) -> void:
	if net_on and not is_host:
		if k.catch_prog < 5.0:
			k.catch_prog = 5.0
			net_event(["catch", k.nid, h.nid])
		return
	if net_on:
		net_event(["caught", k.nid, h.nid, k.rec])
	k.dead = true
	k.visible = false
	var rec: Dictionary = k.rec.duplicate(true)
	rec["trust"] = 20.0
	rec["memory"] = []
	h.caught.append(rec)
	sfx("catch", k.pos, 0.0)
	fx.burst(k.pos + Vector3(0, 0.5, 0), Data.KIN[k.species]["color"], 26, 4.0, 0.7)
	fx.ring(k.pos, 1.5, Color("fff2a0"), 0.4)
	if h == player:
		add_feed("You caught a %s! Extract to keep it." % Data.KIN[k.species]["name"])
		if player.kin and player.kin.state != "fainted":
			player.kin.bark("caught")

func _open_chest(h: Hunter, c: Dictionary, from_net := false) -> void:
	if c["open"]:
		return
	c["open"] = true
	if net_on and not from_net:
		net_event(["chest", chests.find(c), h.nid if h else ""])
	var t := int(c.get("tier", 0))
	if h == player:
		tut_flag = tut_flag or tut_step == 6
	var lid: Node3D = c["node"].get_node("Body/Lid")
	lid.rotation.x = -1.1
	lid.position.y = 0.62
	lid.position.z = 0.2
	var beacon: Node3D = c["node"].get_node_or_null("Beacon")
	if beacon: beacon.visible = false
	sfx("pickup", c["pos"], 0.0, 0.8 - t * 0.1)
	var cc: Array = Models.CHEST_COLS[t]
	fx.burst(c["pos"] + Vector3(0, 0.6, 0), cc[1], 20 + t * 10, 4.0 + t, 0.6)
	if t >= 1:
		fx.ring(c["pos"], 2.0 + t, Color(cc[1], 0.9), 0.4)
	var n_gems: int = [randi_range(4, 6), randi_range(7, 9), randi_range(11, 14)][t]
	for i in n_gems:
		drop("gem", c["pos"] + Vector3(0, 0.8, 0), int(round((3 + t) * float(T["loot"]))))
	var seeds_n: int = [1 if randf() < 0.6 else 0, 1, 2][t]
	for i in seeds_n:
		drop("seed", c["pos"] + Vector3(0, 0.8, 0), randi_range(1, 2), Data.pick_seed())
	if not from_net and randf() < [0.25, 0.6, 1.0][t]:
		var keys: Array = Data.WEAPONS.keys()
		var a := randf() * TAU
		spawn_weapon(String(keys[randi() % keys.size()]), Data.roll_rarity(rng, t), c["pos"] + Vector3(cos(a) * 1.1, 0, sin(a) * 1.1))
	if h and not h.remote and h.tonics < 3 and randf() < [0.35, 0.7, 1.0][t]:
		h.tonics += 1
		if h == player: hud.toast("+1 tonic", Color("8ff0a0"))

func _use_shrine(h: Hunter, sh: Dictionary, from_net := false) -> void:
	if sh["used"]:
		return
	sh["used"] = true
	if net_on and not from_net:
		net_event(["shr", shrines.find(sh), h.nid if h else ""])
	var n: Node3D = sh["node"]
	n.get_node("Crystal").visible = false
	n.get_node("Ring").visible = false
	sfx("heal", sh["pos"], 0.0, 1.2)
	fx.burst(sh["pos"] + Vector3(0, 1.6, 0), Color("8fe3c8"), 30, 5.0, 0.8, -2.0)
	fx.ring(sh["pos"], 4.0, Color("8fe3c8"), 0.5)
	if h and not h.remote:
		h.hp = h.max_hp
		h.bless_t = 45.0
		if h.kin and not h.kin.dead:
			h.kin.hp = h.kin.max_hp
		if h == player:
			hud.toast("Blessed: +25% damage for 45s", Color("8fe3c8"))

## Midway through, the Warden wakes on the heart island and guards it until someone brings it down.
const TUT := ["Steer with WASD to choose where you land", "Walk around with WASD", "Press Shift to dash",
	"Press Space to jump. Hold Space in the air to glide", "Hold left click to shoot. Defeat the monsters",
	"Right click to throw %s at a monster", "Stand by the chest and hold F to open it", "An exit opened. Stand inside it to go home"]

# ---- training area
## [id, what to do, the action whose key it uses ("" for none)]
const TRAIN := [["move", "Walk around", "up"], ["dash", "Dash", "dash"], ["glide", "Jump, then hold it in the air to glide", "jump"],
	["shoot", "Shoot a target dummy", "fire"], ["ability", "Use your hero ability", "signature"], ["ult", "Use your ultimate (it charges fast here)", "ultimate"],
	["throw", "Throw your kin at a dummy", "throw"], ["kinskill", "Use your kin's skill", "kin_skill"], ["tonic", "Drink a tonic to heal", "tonic"],
	["ledge", "Dash off an edge and float back up", ""]]
var train := {}
var train_t := 0.0

func _update_training(dt: float) -> void:
	if player == null:
		return
	train_t += dt
	if player.downed and train_t > 2.0:
		revive_hunter(player, null)
	var was_ult: bool = train.get("_ult_full", false)
	# everything recharges quickly here
	player.ult = minf(1.0, player.ult + dt / 6.0)
	player.sig_cd = maxf(0.0, player.sig_cd - dt * 2.0)
	if player.kin: player.kin.skill_cd = maxf(0.0, player.kin.skill_cd - dt * 2.0)
	if player.tonics < 1: player.tonics = 3
	if not train.has("tonic") and player.hp >= player.max_hp and train_t > 1.0:
		player.hp = player.max_hp * 0.7     # a scratch, so the tonic has something to heal
	if player.inp["move"].length() > 0.1:
		train["_moved"] = float(train.get("_moved", 0.0)) + Vector2(player.pos.x - player.prev.x, player.pos.z - player.prev.z).length()
	var marks := {
		"move": float(train.get("_moved", 0.0)) > 4.0,
		"dash": player.roll_t > 0.0,
		"glide": player.gliding and not player.dropping,
		"shoot": player.dmg_done > 0.0,
		"ability": player.sig_cd > 0.0,
		"ult": was_ult and player.ult < 0.5,
		"throw": player.kin != null and player.kin.st_throws > 0,
		"kinskill": player.kin != null and player.kin.skill_cd > 0.0,
		"tonic": player.tonics < int(train.get("_tonics", player.tonics)),
		"ledge": player.grap.size() > 0,
	}
	train["_ult_full"] = player.ult >= 0.99
	train["_tonics"] = player.tonics
	for k in marks:
		if marks[k] and not train.has(k):
			train[k] = true
			Sfx.play("unlock", null, -8.0)
			var left := TRAIN.filter(func(t): return not train.has(t[0])).size()
			if hud: hud.toast(("Done: %s" % _train_label(k)) if left > 0 else "Training complete. Press Esc to head home whenever you like", Color("8ff0a0"))
			if left == 0:
				Save.d["tutorial"]["training"] = true
	# keep a few target dummies around you
	var alive := mobs.filter(func(x): return not x.dead)
	if alive.size() < 4 and int(train_t * 10.0) % 20 == 0:
		var at := world.random_ground(world.island_of(player.pos.x, player.pos.z))
		if Vector2(at.x - player.pos.x, at.z - player.pos.z).length() > 3.0:
			spawn_mob(["skitter", "spitter", "brute"][randi() % 3], at)

func _train_label(k: String) -> String:
	for t in TRAIN:
		if t[0] == k: return t[1]
	return k

## The first match is a guided one: no rival hunters, gentle damage, and each step waits for you.
func _update_tutorial(dt: float) -> void:
	if player == null or player.extracted:
		return
	if tut_step < 0:
		tut_step = 0
	# getting knocked down here isn't the end: you get back up after a moment
	if player.downed:
		tut_down_t += dt
		if tut_down_t > 3.0:
			tut_down_t = 0.0
			revive_hunter(player, null)
	var kname: String = player.kin.rec.get("name", "your kin") if player.kin else "your kin"
	var done := false
	match tut_step:
		0: done = not player.dropping
		1:
			if player.inp["move"].length() > 0.1:
				tut_moved += Vector2(player.pos.x - player.prev.x, player.pos.z - player.prev.z).length()
			done = tut_moved > 6.0
		2: done = player.roll_t > 0.0
		3:
			tut_flag = tut_flag or player.gliding
			done = tut_flag and player.grounded
		4: done = tut_kills >= 2
		5: done = player.kin == null or player.kin.st_throws > tut_throws0
		6: done = tut_flag
		7: done = false
	if tut_wait > 0.0:
		tut_wait -= dt
		return
	if done:
		tut_step += 1
		tut_flag = false
		tut_wait = 0.6
		sfx("pickup", null, -4.0, 1.3)
		_tut_enter(tut_step)
	if tut_step < TUT.size():
		var txt: String = TUT[tut_step]
		tut_text = txt % kname if txt.contains("%s") else txt

func _tut_enter(step_i: int) -> void:
	match step_i:
		4:
			tut_kills = 0
			for k in 2:
				var at := _tut_spot(5.5, k * 0.6)
				if at != Vector3.INF: spawn_mob("skitter", at)
		5:
			if player.kin:
				tut_throws0 = player.kin.st_throws
				if player.kin.state in ["active", "flying"]:
					player.kin.recall()
			var at := _tut_spot(5.0, 0.0)
			if at != Vector3.INF: spawn_mob("spitter", at)
		6:
			var at := _tut_spot(3.5, 1.0)
			if at != Vector3.INF:
				var n := Models.chest(1)
				n.position = at
				add_child(n)
				chests.append({"pos": at, "open": false, "prog": 0.0, "node": n, "tier": 1})
				ping(at, Color("dfe8f2"))
		7:
			var at := _tut_spot(5.0, -1.0)
			if at == Vector3.INF: at = player.pos
			var n := Models.portal(Color("8fe3c8"))
			n.position = at
			add_child(n)
			portals.append({"pos": at, "open_at": time, "open": false, "node": n})
			ping(at, Color("8fe3c8"))

var _tut_last := -1
## Test driver: plays the tutorial by itself so the whole flow can be checked headless.
func _tut_drive() -> void:
	if tut_step != _tut_last:
		print("TUT step ", tut_step, " t=", snapped(time, 0.1))
		_tut_last = tut_step
	var p := player
	p.inp["move"] = Vector2.ZERO
	p.inp["fire"] = false
	p.inp["glide"] = false
	p.inp["interact"] = false
	var goto := func(at: Vector3):
		var d := Vector2(at.x - p.pos.x, at.z - p.pos.z)
		p.inp["move"] = d.normalized() if d.length() > 0.5 else Vector2.ZERO
	match tut_step:
		1: p.inp["move"] = Vector2(1, 0) if int(time) % 4 < 2 else Vector2(-1, 0)
		2: p.inp["dash"] = true
		3:
			if p.grounded and not tut_flag: p.inp["jump"] = true
			p.inp["glide"] = true
		4, 5:
			var best: Ent = null; var bd := 1e9
			for mb in mobs:
				if not mb.dead and p.flat_dist(mb) < bd: bd = p.flat_dist(mb); best = mb
			if best:
				p.inp["aim"] = best.pos + Vector3(0, 0.9, 0)
				if bd > 4.0: goto.call(best.pos)
				if tut_step == 4: p.inp["fire"] = true
				elif p.kin and p.kin.state == "shoulder": p.kin.throw_to(best.pos)
		6:
			for c in chests:
				if not c["open"] and p.flat_dist(c["pos"]) < 12.0:
					goto.call(c["pos"]); p.inp["interact"] = true; break
		7:
			if portals.size() > 0: goto.call(portals[portals.size() - 1]["pos"])

## Open ground a given distance from the player on the same island.
func _tut_spot(dist: float, ang0: float) -> Vector3:
	var isl := world.island_of(player.pos.x, player.pos.z)
	for i in 24:
		var a := ang0 + i * 0.52
		for d in [dist, dist * 0.7, dist * 0.5]:
			var x: float = player.pos.x + cos(a) * d; var z: float = player.pos.z + sin(a) * d
			if world.island_of(x, z) == isl and not world.is_block(x, z) and world.edge_dist(int(x), int(z), 2) >= 2:
				return Vector3(floor(x) + 0.5, world.ground_at(x, z), floor(z) + 0.5)
	return Vector3.INF

# ------------------------------------------------------------------ hero zones
func add_zone(kind_s: String, at: Vector3, radius: float, dur: float, team_i: int, owner: Hunter, from_net := false) -> void:
	var col: Color = Data.HEROES[owner.hero]["color"] if owner else Color.WHITE
	var n := Node3D.new()
	add_child(n)
	n.position = at
	match kind_s:
		"dome":
			var mi := MeshInstance3D.new(); mi.mesh = Models.sphere(radius, 24)
			mi.material_override = Models.glow_mat(Color(col, 0.16))
			mi.scale = Vector3(1, 0.75, 1)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			n.add_child(mi)
		"sanctuary", "well":
			var ring := MeshInstance3D.new(); ring.mesh = Models.flat_quad(radius * 2.0)
			ring.material_override = Models.ring_mat(Color(col if kind_s == "sanctuary" else Color("b06ae0"), 0.9), 0.06)
			ring.position.y = 0.08
			n.add_child(ring)
	zones.append({"kind": kind_s, "pos": at, "r": radius, "t": 0.0, "dur": dur, "team": team_i, "owner": owner, "node": n, "tick": 0.0})
	if kind_s == "well":
		sfx("warn", at, -2.0, 1.4)
	if net_on and not from_net and owner:
		net_event(["zone", kind_s, _r(at.x), _r(at.y), _r(at.z), radius, dur, team_i, owner.nid])

func _dome_blocks(s: Dictionary, p: Vector3) -> bool:
	for z in zones:
		if z["kind"] != "dome" or z["team"] == s["team"]:
			continue
		var c: Vector3 = z["pos"]
		if Vector2(p.x - c.x, p.z - c.z).length() < z["r"] and Vector2(s["start"].x - c.x, s["start"].z - c.z).length() > z["r"]:
			fx.burst(p, Color(Data.HEROES["halo"]["color"], 0.8), 6, 2.0, 0.25, 0.0, 0.7)
			return true
	return false

func _update_zones(dt: float) -> void:
	for z in zones.duplicate():
		z["t"] += dt
		z["tick"] -= dt
		var n: Node3D = z["node"]
		var k: float = z["t"] / z["dur"]
		n.scale = Vector3.ONE * minf(1.0, z["t"] * 6.0) * (1.0 if k < 0.9 else (1.0 - k) * 10.0)
		var owner: Hunter = z["owner"]
		var mine: bool = owner != null and not owner.remote
		var c: Vector3 = z["pos"]
		if z["tick"] <= 0.0:
			z["tick"] = 0.25
			match String(z["kind"]):
				"sanctuary", "dome":
					# heal your own hunter and kin when standing inside a friendly area
					var amt := 12.0 * 0.25 if z["kind"] == "sanctuary" else (4.0 * 0.25 if owner and owner.hero == "halo" else 0.0)
					if amt > 0.0:
						for h in hunters:
							if h.team == z["team"] and not h.remote and not h.downed and not h.out and h.flat_dist(c) < z["r"]:
								h.hp = minf(h.max_hp, h.hp + amt)
								if h.kin and h.kin.state == "active" and h.kin.flat_dist(c) < z["r"]:
									h.kin.hp = minf(h.kin.max_hp, h.kin.hp + amt)
						if z["kind"] == "sanctuary":
							fx.burst(c + Vector3(randf_range(-2, 2), 0.3, randf_range(-2, 2)), Color("9ee2a0"), 3, 1.5, 0.6, -2.0, 0.8)
				"well":
					fx.burst(c + Vector3(0, 0.5, 0), Color("b06ae0"), 8, -3.0, 0.4, 0.0, 0.8)
					if mine:
						for f in foes_of(z["team"]):
							var rel := Vector2(c.x - f.pos.x, c.z - f.pos.z)
							if rel.length() < z["r"] and rel.length() > 0.4:
								f.hurt(1.0, owner, {"kb": rel.normalized() * 4.5, "slow": 0.5, "src": "abil"})
		if z["t"] >= z["dur"]:
			if z["kind"] == "well" and mine:
				Abil._blast(owner, c, z["r"] * 0.6, 26.0, 7.0, Color("b06ae0"), 5.0)
			n.queue_free()
			zones.erase(z)

func _update_events() -> void:
	if opts.get("tutorial", false) or opts.get("training", false):
		return
	if warden_done or time < length * 0.4 or world.heart_spot == Vector3.INF:
		return
	warden_done = true
	if not net_on or is_host:
		var w := spawn_mob("warden", world.heart_spot + Vector3(0, 0, 1.5))
		w.st = "idle"
		if opts.get("watch_heart", false) and player:
			var wp := world.heart_spot + Vector3(0, 0, 5.0)
			player.teleport(Vector3(wp.x, world.ground_at(wp.x, wp.z), wp.z))
	sfx("warn", null, 0.0, 0.6)
	ping(world.heart_spot, Color("c9a0ff"))
	if player and not player.out:
		add_feed("The Warden has woken on the center island")
		hud.toast("The Warden wakes", Color("c9a0ff"))

func _update_portals(dt: float) -> void:
	for p in portals:
		var n: Node3D = p["node"]
		if not p["open"] and time >= p["open_at"]:
			p["open"] = true
			n.get_node("Disc").visible = true
			n.get_node("Beam").emitting = true
			sfx("portal", p["pos"], 0.0)
			if player and not player.out:
				add_feed("An exit opened %s" % direction_word(player.pos, p["pos"]))
				ping(p["pos"], Color("8fe3c8"))
		if p["open"]:
			n.get_node("Disc").rotation.y += dt * 2.0
	for h in hunters:
		if h.out or h.extracted or h.downed:
			continue
		var inside := false
		for p in portals:
			if p["open"] and h.flat_dist(p["pos"]) < 1.3 and absf(h.pos.y - p["pos"].y) < 1.0:
				inside = true
				break
		if inside:
			h.extract_prog += dt / Data.MATCH["extract_time"]
			if h.extract_prog >= 1.0:
				_extract(h)
		else:
			h.extract_prog = maxf(0.0, h.extract_prog - dt)

func _extract(h: Hunter) -> void:
	h.extracted = true
	cancel_abilities(h)
	if net_on and not h.remote:
		net_event(["ext", h.nid])
	sfx("portal", h.pos, 0.0, 1.3)
	fx.burst(h.pos + Vector3(0, 1.0, 0), Color("8fe3c8"), 30, 5.0, 0.8, -4.0)
	add_feed("%s extracted" % h.pname)
	if h.kin:
		h.kin.visible = false
	if h == player:
		if h.kin and h.kin.state != "fainted":
			h.kin.bark("extract")
		result = {"extracted": true, "why": "extracted"}
		_end_soon(1.6)
	_check_last()

func _update_rules(_dt: float) -> void:
	var left := length - time
	if left < 30.0 and not collapse_warned:
		collapse_warned = true
		add_feed("The islands are falling! Get to an exit!")
		sfx("warn", null, 0.0)
	if left <= 0.0:
		for h in hunters:
			if not h.out and not h.extracted:
				eliminate(h, null, "abyss", true)
		if not over and result.is_empty():
			result = {"extracted": false, "why": "abyss"}
			_end_soon(1.5)
	if player and player.extracted == false and player.out == false:
		var alive := hunters.filter(func(x): return not x.out and not x.extracted)
		var rival := alive.any(func(x): return x.team != player.team)
		if not rival and portals.all(func(p): return p["open"]) and hud:
			pass

func _end_soon(after: float) -> void:
	if result.get("ending", false):
		return
	result["ending"] = true
	get_tree().create_timer(after).timeout.connect(_finish)

func _finish() -> void:
	if over:
		return
	over = true
	if Overlay.is_open():
		if Overlay.closed.is_connected(_on_menu_closed):
			Overlay.closed.disconnect(_on_menu_closed)
		Overlay.close()
	if opts.get("training", false):
		# nothing from the training area carries over
		Game.goto("home")
		return
	var r := result.duplicate()
	r["time"] = time
	r["tier"] = tier
	if opts.get("tutorial", false):
		Save.d["tutorial"]["match"] = true
		r["tutorial"] = true
	if player:
		r["gems"] = player.gems
		r["lost_gems"] = player.lost_gems
		r["seeds"] = player.seeds.duplicate()
		r["caught"] = player.caught.duplicate(true)
		r["kills"] = player.kills
		r["knocks"] = player.knocks
		r["damage"] = int(player.dmg_done)
		r["tonics"] = maxi(0, player.tonics - player.free_tonics)
		if player.kin:
			r["kin_events"] = player.kin.events.duplicate(true)
			r["kin_trust"] = player.kin.trust
			var k: Kin = player.kin
			r["kin_stats"] = {"hits": k.st_hits, "kos": k.st_kos, "throws": k.st_throws, "skills": k.st_skills,
				"revives": k.events.filter(func(e): return e["kind"] == "revived").size(), "caught": player.caught.size(),
				"won": 1 if result.get("extracted", false) else 0}
	var placed := 1
	for h in hunters:
		if h.extracted and h != player:
			placed += 0
	r["placed"] = placed
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if net_on:
		Net.end_match()
	Game.finish_match(r)

# ------------------------------------------------------------------ online
static func _r(v: float) -> float:
	return snappedf(v, 0.01)

func net_event(e: Array) -> void:
	if net_on:
		Net.event(e)

func net_fx(e: Array) -> void:
	if net_on:
		Net.event(["fx"] + e)

func _spawn_net_hunters(spots: Array, names: Array) -> void:
	var nd: Dictionary = opts["net"]
	var roster: Array = nd["roster"]
	var squad := int(nd.get("squad", 1))
	var team_slots := {}
	for r in roster:
		var t := int(r["team"])
		var base: Vector3 = spots[t % spots.size()]
		var slot := int(team_slots.get(t, 0))
		team_slots[t] = slot + 1
		var at := base + Vector3(slot * 1.1, 0, 0)
		if world.is_void(at.x, at.z) or world.is_block(at.x, at.z):
			at = base
		at.y = world.ground_at(at.x, at.z)
		var peer := String(r["peer"])
		var krec: Dictionary = r.get("kin", {})
		if krec.is_empty():
			krec = Save.new_kin("cindle")
		if peer == Net.me:
			var rec: Dictionary = Save.active_kin()
			player = make_hunter("P" + peer, t, String(r["cls"]), String(r["name"]), "local", rec, at, my_kit())
			player.tonics = int(Save.d["items"].get("tonic", 0))
			_apply_home_perks(player)
			if player.kin:
				_apply_treat(player.kin)
			_start_drop(player, at)
		else:
			var h := make_hunter("P" + peer, t, String(r["cls"]), String(r["name"]), "remote", krec, at, {"hero": r.get("hero", ""), "weapon": r.get("weapon", ""), "perk": ""})
			h.remote = true
			if h.kin:
				h.kin.remote = true
	if not is_host:
		return
	# the host fills the remaining squads and seats with bots
	var n_teams := int(nd.get("teams", 4))
	for t in n_teams:
		var have := int(team_slots.get(t, 0))
		for s in range(have, squad):
			var base: Vector3 = spots[t % spots.size()]
			var at := base + Vector3(s * 1.1, 0, 0.8)
			if world.is_void(at.x, at.z) or world.is_block(at.x, at.z):
				at = base
			at.y = world.ground_at(at.x, at.z)
			var h := make_hunter(next_id("b"), t, "", names.pop_back() if names.size() > 0 else "Bot", "bot", bot_kin_record(), at, bot_kit())
			h.ai = bot_brain.new_mind(rng, float(opts.get("bot_skill", 0.6)))
			h.tonics = 1
			_start_drop(h, at)

## A hit on something another game owns goes to its owner.
func net_send_hit(target: Ent, dmg: float, by: Ent, o: Dictionary) -> bool:
	if not net_on:
		return false
	var kb: Vector2 = o.get("kb", Vector2.ZERO)
	Net.hit(target.nid, [_r(dmg), _r(kb.x), _r(kb.y), _r(float(o.get("lift", -1.0))), 1 if o.get("crit", false) else 0,
		_r(float(o.get("stun", 0.0))), _r(float(o.get("burn", 0.0))), _r(float(o.get("slow", 0.0))), _r(float(o.get("root", 0.0))),
		by.nid if by else "", String(o.get("src", ""))])
	return true

func _flags(h: Hunter) -> int:
	var f := 0
	if h.downed: f |= 1
	if h.out: f |= 2
	if h.extracted: f |= 4
	if h.cloak_t > 0.0: f |= 8
	if h.roll_t > 0.0: f |= 16
	if h.grounded: f |= 32
	if h.fortify_t > 0.0: f |= 64
	if h.reload_t > 0.0: f |= 128
	if h.gliding: f |= 256
	if h.dropping: f |= 512
	if h.riding: f |= 1024
	return f

const KIN_STATES := ["shoulder", "flying", "flying_home", "active", "returning", "fainted", "reviving", "wild", "dazed"]
const MOB_STATES := ["idle", "chase", "windup", "lunge", "recover"]

func _ser(e: Ent) -> Array:
	if e is Hunter:
		var h: Hunter = e
		return ["h", h.nid, _r(h.pos.x), _r(h.pos.y), _r(h.pos.z), _r(h.vel.x), _r(h.vel.y), _r(h.vel.z), _r(h.face), _r(h.hp), h.max_hp, _flags(h),
			_r(h.down_hp), _r(h.revive), h.team, h.cls, h.pname, _r(h.shield), _r(h.extract_prog), h.kills, h.knocks, int(h.dmg_done)]
	if e is Kin:
		var k: Kin = e
		return ["k", k.nid, _r(k.pos.x), _r(k.pos.y), _r(k.pos.z), _r(k.face), _r(k.hp), _r(k.max_hp), KIN_STATES.find(k.state), k.species,
			k.owner_h.nid if k.owner_h else "", int(k.rec.get("level", 1)), String(k.rec.get("name", "")), _r(k.catch_prog), _r(k.vel.x), _r(k.vel.z)]
	var mb: Mob = e
	return ["m", mb.nid, _r(mb.pos.x), _r(mb.pos.y), _r(mb.pos.z), _r(mb.face), _r(mb.hp), _r(mb.max_hp), MOB_STATES.find(mb.st), mb.mkind,
		_r(mb.atk_dir.x), _r(mb.atk_dir.y), _r(mb.st_t), _r(mb.vel.x), _r(mb.vel.z)]

## Snapshot of what this game owns: its player (mine=true), or the host's world (mine=false).
func net_snapshot(mine: bool) -> Array:
	var out: Array = []
	if mine:
		if player:
			out.append(_ser(player))
			if player.kin and not player.kin.dead:
				out.append(_ser(player.kin))
		return out
	for h in hunters:
		if not h.remote and h != player:
			out.append(_ser(h))
			if h.kin and not h.kin.dead: out.append(_ser(h.kin))
	for k in kins:
		if k.is_wild() and not k.dead: out.append(_ser(k))
	for mb in mobs:
		if not mb.dead: out.append(_ser(mb))
	return out

func net_receive(topic: String, data, from: String) -> void:
	if typeof(data) != TYPE_ARRAY:
		return
	match topic:
		"st": _net_state(data, from)
		"hit": for x in data: _net_hit_in(x)
		"ev": for x in data: _net_ev(x, from)

func _net_state(data: Array, from: String) -> void:
	var t_host := -1.0
	for it in data:
		if typeof(it) == TYPE_DICTIONARY:
			t_host = float(it.get("t", -1.0))
			continue
		if typeof(it) != TYPE_ARRAY or it.size() < 3:
			continue
		var nid := String(it[1])
		if Net.owns(nid):
			continue
		var e: Ent = ents_by_id.get(nid, null)
		if e == null:
			e = _net_make(it)
			if e == null:
				continue
		_net_apply(e, it)
	if t_host >= 0.0 and from == Net.host and absf(t_host - time) > 0.5:
		time = t_host

func _net_make(it: Array) -> Ent:
	var nid := String(it[1])
	match String(it[0]):
		"h":
			var h := make_hunter(nid, int(it[14]), String(it[15]), String(it[16]), "remote", {}, Vector3(it[2], it[3], it[4]))
			h.remote = true
			return h
		"k":
			var owner: Hunter = ents_by_id.get(String(it[10]), null)
			var rec := {"species": String(it[9]), "level": int(it[11]), "name": String(it[12]), "traits": Data.KIN[String(it[9])]["traits"].duplicate(), "trust": 50.0}
			var k := Kin.new()
			k.init_kin(self, nid, rec["species"], rec, owner)
			add_child(k)
			k.teleport(Vector3(it[2], it[3], it[4]))
			k.remote = true
			if owner == null:
				k.state = "wild"
			kins.append(k)
			ents_by_id[nid] = k
			if owner and owner.kin == null:
				owner.kin = k
			_net_seen_rec[nid] = rec
			return k
		"m":
			var mb := Mob.new()
			mb.init_mob(self, nid, String(it[9]), Vector3(it[2], it[3], it[4]))
			add_child(mb)
			mb.remote = true
			mobs.append(mb)
			ents_by_id[nid] = mb
			return mb
	return null

func _net_apply(e: Ent, it: Array) -> void:
	e.net_pos = Vector3(it[2], it[3], it[4])
	e.net_t = time
	match String(it[0]):
		"h":
			var h: Hunter = e
			h.net_vel = Vector3(it[5], it[6], it[7])
			h.face = it[8]; h.hp = it[9]; h.max_hp = it[10]
			var f := int(it[11])
			h.downed = f & 1 != 0
			if f & 2 != 0 and not h.out:
				h.out = true
			if f & 4 != 0 and not h.extracted:
				h.extracted = true
			h.cloak_t = 0.3 if f & 8 != 0 else 0.0
			h.roll_t = 0.05 if f & 16 != 0 else 0.0
			h.grounded = f & 32 != 0
			h.fortify_t = 0.3 if f & 64 != 0 else 0.0
			h.gliding = f & 256 != 0
			h.dropping = f & 512 != 0
			h.riding = f & 1024 != 0
			h.down_hp = it[12]; h.revive = maxf(h.revive if h.revive > float(it[13]) and _rev_out.has(h.nid) else 0.0, float(it[13]))
			h.shield = it[17]; h.extract_prog = it[18]
			h.kills = int(it[19]); h.knocks = int(it[20]); h.dmg_done = float(it[21])
		"k":
			var k: Kin = e
			k.face = it[5]; k.hp = it[6]; k.max_hp = it[7]
			var st: int = int(it[8])
			if st >= 0 and st < KIN_STATES.size():
				k.state = KIN_STATES[st]
			k.catch_prog = maxf(k.catch_prog, float(it[13])) if k.catch_prog >= 5.0 else float(it[13])
			k.net_vel = Vector3(it[14], 0, it[15])
			k.dead = false
		"m":
			var mb: Mob = e
			mb.face = it[5]; mb.hp = it[6]; mb.max_hp = it[7]
			var st: int = int(it[8])
			if st >= 0 and st < MOB_STATES.size():
				mb.st = MOB_STATES[st]
			mb.atk_dir = Vector2(it[10], it[11])
			mb.st_t = it[12]
			mb.net_vel = Vector3(it[13], 0, it[14])

func _net_hit_in(x) -> void:
	if typeof(x) != TYPE_ARRAY or x.size() < 12:
		return
	var nid := String(x[0])
	if not Net.owns(nid):
		return
	var e: Ent = ents_by_id.get(nid, null)
	if e == null or e.dead:
		return
	var by: Ent = ents_by_id.get(String(x[10]), null)
	var o := {"src": String(x[11]), "crit": int(x[5]) == 1}
	if absf(float(x[2])) + absf(float(x[3])) > 0.0: o["kb"] = Vector2(x[2], x[3])
	if float(x[4]) >= 0.0: o["lift"] = float(x[4])
	if float(x[6]) > 0.0: o["stun"] = float(x[6])
	if float(x[7]) > 0.0: o["burn"] = float(x[7])
	if float(x[8]) > 0.0: o["slow"] = float(x[8])
	if float(x[9]) > 0.0: o["root"] = float(x[9])
	e.hurt(float(x[1]), by, o)

func _net_ev(x, from: String) -> void:
	if typeof(x) != TYPE_ARRAY or x.size() < 1:
		return
	var who: Ent = null
	match String(x[0]):
		"s":
			var col := Color.html(String(x[8]))
			var ex := {"cos": true}
			if float(x[9]) > 0.0: ex["boom"] = float(x[9])
			if int(x[11]) == 1: ex["mob"] = true
			var fake := Ent.new(); fake.team = int(x[10]); fake.remote = true
			spawn_shot(fake, Vector3(x[1], x[2], x[3]), Vector2(x[4], x[5]), 0.0, float(x[6]), float(x[7]), col, ex)
			fake.free()
		"fx":
			match String(x[1]):
				"ring": fx.ring(Vector3(x[2], x[3], x[4]), float(x[5]), Color.html(String(x[6])), 0.35)
				"bolt": fx.bolt(Vector3(x[2], x[3], x[4]), Vector3(x[5], x[6], x[7]), Color.html(String(x[8])))
				"cone": fx.cone(Vector3(x[2], x[3], x[4]), Vector2(x[5], x[6]), 5.0, Color.html(String(x[7])))
		"knock":
			who = ents_by_id.get(String(x[1]), null)
			if who is Hunter and not who.downed:
				var by: Ent = ents_by_id.get(String(x[2]), null)
				who.downed = true
				sfx("knock", who.pos, 0.0)
				add_feed("%s knocked %s" % [by.pname, who.pname] if by is Hunter else "%s went down" % who.pname)
				if by == player:
					player.knocks += 1
					_reward_moment(who.pos)
					if player.hero == "nyx":
						player.sig_cd = 0.0
				_check_team(player.team if player else -9)
		"out":
			who = ents_by_id.get(String(x[1]), null)
			if who is Hunter and not who.out:
				var by: Ent = ents_by_id.get(String(x[2]), null)
				who.out = true
				if by == player:
					player.kills += 1
				add_feed("%s is out" % who.pname if String(x[3]) != "abyss" else "%s fell into the abyss" % who.pname)
				if who.kin:
					who.kin.dead = true
					who.kin.visible = false
				_check_last()
		"up":
			who = ents_by_id.get(String(x[1]), null)
			if who is Hunter:
				who.downed = false
				who.revive = 0.0
				sfx("revive", who.pos, 0.0)
				_rev_out.erase(who.nid)
		"ext":
			who = ents_by_id.get(String(x[1]), null)
			if who is Hunter and not who.extracted:
				who.extracted = true
				add_feed("%s extracted" % who.pname)
				if who.kin: who.kin.visible = false
				_check_last()
		"heal":
			who = ents_by_id.get(String(x[1]), null)
			if who is Hunter and not who.remote:
				who.heal(float(x[2]))
		"rev":
			who = ents_by_id.get(String(x[1]), null)
			if who is Hunter and not who.remote and who.downed:
				who.revive += float(x[2])
				if who.revive >= 1.0:
					revive_hunter(who, null)
		"mobdead":
			who = ents_by_id.get(String(x[1]), null)
			if who is Mob and not who.dead:
				who.dead = true
				who._cancel_tele()
				fx.burst(who.pos + Vector3(0, 0.6, 0), who.md["color"], 22, 5.0, 0.6)
				sfx("kill", who.pos, -6.0, 1.3)
		"drop":
			if not is_host:
				drop(String(x[2]), Vector3(x[5], x[6], x[7]), int(x[3]), String(x[4]), String(x[1]), Vector3(x[8], x[9], x[10]))
		"take", "gone":
			for p in pickups:
				if p["id"] == String(x[1]):
					p["node"].queue_free()
					pickups.erase(p)
					break
			if String(x[0]) == "take" and is_host:
				net_event(["gone", String(x[1])])
		"brk":
			var bi := int(x[1])
			if bi >= 0 and bi < breaks.size():
				_break(breaks[bi], ents_by_id.get(String(x[2]), null), true)
		"wdrop":
			var seen := false
			for wp in wpicks:
				if wp["id"] == String(x[1]): seen = true
			if not seen:
				spawn_weapon(String(x[2]), int(x[3]), Vector3(x[4], x[5], x[6]), String(x[1]), false)
		"wtake":
			for wp in wpicks:
				if wp["id"] == String(x[1]):
					_take_weapon(ents_by_id.get(String(x[2]), null), wp, true)
					break
			var wh: Ent = ents_by_id.get(String(x[2]), null)
			if wh is Hunter and wh.remote and x.size() > 4:
				(wh as Hunter).equip(String(x[3]), int(x[4]))
		"zone":
			var zo: Ent = ents_by_id.get(String(x[8]), null)
			if zo is Hunter:
				add_zone(String(x[1]), Vector3(x[2], x[3], x[4]), float(x[5]), float(x[6]), int(x[7]), zo, true)
		"shr":
			var si := int(x[1])
			if si >= 0 and si < shrines.size():
				_use_shrine(ents_by_id.get(String(x[2]), null), shrines[si], true)
		"chest":
			var i := int(x[1])
			if i >= 0 and i < chests.size():
				_open_chest(ents_by_id.get(String(x[2]), null), chests[i], true)
		"spill":
			if is_host:
				var at := Vector3(x[1], x[2], x[3])
				if not world.is_void(at.x, at.z):
					var gems := int(x[4])
					var n := mini(10, int(ceil(gems / 5.0)))
					for i in n:
						drop("gem", at + Vector3(0, 0.5, 0), maxi(1, gems / maxi(1, n)))
					for s in x[5]:
						drop("seed", at + Vector3(0, 0.5, 0), int(x[5][s]), s)
					for rec in x[6]:
						spawn_wild(rec, at, true)
		"catch":
			if is_host:
				var k: Kin = ents_by_id.get(String(x[1]), null)
				var h: Hunter = ents_by_id.get(String(x[2]), null)
				if k and h and not k.dead and k.state == "dazed":
					_catch(h, k)
		"caught":
			var k: Kin = ents_by_id.get(String(x[1]), null)
			if k:
				k.dead = true
				k.visible = false
			if player and String(x[2]) == player.nid and typeof(x[3]) == TYPE_DICTIONARY:
				var rec: Dictionary = x[3]
				player.caught.append(rec)
				sfx("catch", player.pos, 0.0)
				add_feed("You caught a %s! Extract to keep it." % Data.KIN.get(String(rec.get("species", "cindle")), Data.KIN["cindle"])["name"])

func _process_net_revives() -> void:
	if _rev_out.is_empty():
		return
	for nid in _rev_out:
		if float(_rev_out[nid]) > 0.0:
			net_event(["rev", nid, _r(_rev_out[nid])])
			_rev_out[nid] = 0.0

# ------------------------------------------------------------------ first-time tips
var _tip_t := 0.0

func _tip(key: String, text: String) -> void:
	var seen: Dictionary = Save.d["tutorial"]
	if seen.get(key, false) or hud == null:
		return
	seen[key] = true
	hud.tip(text)

func _tips() -> void:
	if player == null or player.out or player.riding or opts.get("autoplay", false) or not Settings.get_v("tips"):
		return
	_tip_t += get_process_delta_time()
	if _tip_t < 1.0:
		return
	if player.dropping or opts.get("tutorial", false):
		return
	_tip("move", "WASD to move, aim with the mouse, hold left click to shoot. Shift dashes, Space jumps. Hold Space in the air to glide.")
	if _tip_t > 14.0:
		_tip("ability", "E uses %s's ability, %s. R fires your ultimate once it charges, and dealing damage charges it faster." % [Data.HEROES[player.hero]["name"], Data.ABIL[Abil.e_id(player)]["name"]])
	if player.ult >= 1.0:
		_tip("ult", "Your ultimate, %s, is ready. Press R." % Data.ABIL[Abil.r_id(player)]["name"])
	var k: Kin = player.kin
	if k == null:
		return
	if _tip_t > 9.0:
		var near_foe := false
		for f in foes_of(player.team):
			if player.flat_dist(f) < 9.0:
				near_foe = true; break
		if near_foe:
			_tip("throw", "Right click throws %s at the cursor. A kin that hits a foe stuns it, and your shots crit stunned foes." % k.rec.get("name", "your kin"))
	if k.state == "active":
		_tip("skill", "Q makes %s use %s. Right click again calls it back to your shoulder, where it gives you %s." % [k.rec.get("name", "your kin"), Data.KIN_SKILLS[k.sp["skill"]]["name"], Data.SHOULDER[k.sp["shoulder"]]["name"]])
	if not interact.is_empty() and interact["kind"] == "catch":
		_tip("catch", "Hold F to catch it. Caught kin only come home if you extract.")
	if portals.any(func(p): return p["open"]):
		_tip("exit", "Exits are open. Stand in one for 3 seconds to leave with everything you carry.")
	if player.downed:
		_tip("down", "You're down. Your kin will try to pick you up if it trusts you enough.")

# ------------------------------------------------------------------ aim indicators
func _build_aim() -> void:
	aim_line = MeshInstance3D.new()
	aim_line.mesh = Models.box(0.05, 0.02, 1.0)
	aim_line.material_override = Models.glow_mat(Color(1, 1, 1, 0.22))
	aim_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(aim_line)
	aim_ring = MeshInstance3D.new()
	aim_ring.mesh = Models.flat_quad(1.2)
	aim_ring.material_override = Models.ring_mat(Color(1, 0.95, 0.8, 0.55), 0.18)
	aim_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(aim_ring)
	muzzle_light = OmniLight3D.new()
	muzzle_light.light_color = Color("ffd9a0")
	muzzle_light.omni_range = 4.0
	muzzle_light.light_energy = 0.0
	add_child(muzzle_light)

func _update_aim(alpha: float) -> void:
	if aim_line == null:
		return
	var p := player
	var show := p != null and not p.out and not p.extracted and not p.downed and not paused
	aim_line.visible = show
	aim_ring.visible = false
	muzzle_light.light_energy = 0.0
	if not show:
		return
	var at := p.prev.lerp(p.pos, alpha)
	var aim: Vector3 = p.inp["aim"]
	var d := Vector2(aim.x - at.x, aim.z - at.z)
	var dist := minf(d.length(), float(p.wpn["range"]))
	if dist > 0.6:
		var dir := d.normalized()
		var y := at.y + 0.95 * float(p.cdat["scale"])
		var a := Vector3(at.x + dir.x * 0.6, y, at.z + dir.y * 0.6)
		var b := Vector3(at.x + dir.x * dist, y, at.z + dir.y * dist)
		aim_line.global_position = (a + b) * 0.5
		if a.distance_to(b) < 0.05:
			aim_line.visible = false
			return
		aim_line.look_at(b, Vector3.UP)
		aim_line.scale = Vector3(1, 1, a.distance_to(b))
	else:
		aim_line.visible = false
	# where your kin would land if you threw it now
	var k: Kin = p.kin
	if k and k.state == "shoulder" and k.settle >= 0.35:
		var t := Vector2(aim.x - at.x, aim.z - at.z)
		if t.length() > 9.0:
			t = t.normalized() * 9.0
		var g := world.ground_at(at.x + t.x, at.z + t.y)
		if g > World.VOID + 1.0:
			aim_ring.visible = true
			aim_ring.global_position = Vector3(at.x + t.x, g + 0.06, at.z + t.y)
			var col: Color = Data.KIN[k.species]["color"]
			aim_ring.material_override.set_shader_parameter("color", Color(col, 0.6))
	if p.muzzle_t > 0.0:
		var dir2 := p.aim_dir()
		muzzle_light.global_position = Vector3(at.x + dir2.x * 0.8, at.y + 1.0, at.z + dir2.y * 0.8)
		muzzle_light.light_energy = 2.2
