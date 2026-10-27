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
var chests: Array = []      # {pos, open, prog, node}
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
var hitstop := 0.0
var aim_line: MeshInstance3D
var aim_ring: MeshInstance3D
var muzzle_light: OmniLight3D
var collapse_warned := false
var rng := RandomNumberGenerator.new()
var pending_input := {"dash": false, "jump": false, "sig": false, "reload": false, "tonic": false, "throw": false, "skill": false}
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
	length = float(o.get("length", Data.MATCH["length"]))
	tier = clampi(int(o.get("tier", 0)), 0, Data.TIERS.size() - 1)
	T = Data.TIERS[tier]
	_build_env()
	world = World.new()
	world.name = "World"
	world.biome = T["biome"].duplicate()
	world.clouds = T["clouds"]
	add_child(world)
	world.generate(seed_val, 64, 7)
	world.build_meshes()
	fx = Fx.new(); fx.name = "Fx"; add_child(fx)
	cam = CamRig.new(); cam.name = "Cam"; add_child(cam)
	cam.lead = float(Save.d["settings"].get("cam_lead", 1.0))
	_build_shot_pool()
	if o.has("net"):
		net_on = true
		is_host = Net.me == String(o["net"]["host"])
		Net.begin_match("kf-" + String(o["net"]["mid"]), String(o["net"]["host"]), self)
	_spawn_pads_and_portals()
	_spawn_hunters()
	_spawn_mobs()
	_spawn_chests()
	_spawn_wild()
	var Hud = load("res://scripts/ui/hud.gd")
	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.setup(self)
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
	var open_at := float(Data.MATCH["portal_open"]) * length / float(Data.MATCH["length"])
	for i in world.portal_spots.size():
		var n := Models.portal(Color("8fe3c8"))
		n.position = world.portal_spots[i]
		add_child(n)
		portals.append({"pos": world.portal_spots[i], "open_at": open_at + i * 35.0, "open": false, "node": n})

func make_hunter(id: String, team: int, cls: String, pname: String, ctrl: String, kin_rec: Dictionary, at: Vector3) -> Hunter:
	var h := Hunter.new()
	h.init_hunter(self, id, team, cls, pname, ctrl)
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

func bot_kin_record() -> Dictionary:
	var sp: String = Data.KIN.keys()[rng.randi_range(0, Data.KIN.size() - 1)]
	var rec := Save.new_kin(sp)
	rec["trust"] = rng.randf_range(40, 80)
	rec["level"] = rng.randi_range(1, 4)
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
				player = make_hunter("p0", 0, Save.d.get("cls", "medium"), Save.d.get("name", "Hunter"), "bot" if opts.get("autoplay", false) else "local", rec, at)
				if opts.get("autoplay", false):
					player.ai = bot_brain.new_mind(rng, 0.7)
				player.teleport(at)
				player.tonics = int(Save.d["items"].get("tonic", 0))
				if Save.has_building("workshop"):
					player.glide_max = Hunter.GLIDE_TIME * 1.5
				if player.kin:
					_apply_treat(player.kin)
				continue
			var cls: String = ["light", "medium", "heavy"][rng.randi_range(0, 2)]
			var h := make_hunter(next_id("b"), t, cls, names.pop_back() if names.size() > 0 else "Bot", "bot", bot_kin_record(), at)
			h.ai = bot_brain.new_mind(rng, float(opts.get("bot_skill", 0.6)))
			h.tonics = 1

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
		var central: bool = c["island"] == 0
		var comp: Array
		if (central and rng.randf() < 0.6) or rng.randf() < 0.15 * tier:
			comp = ["brute", "skitter", "skitter"]
		elif rng.randf() < 0.5:
			comp = ["skitter", "skitter", "spitter"]
		else:
			comp = ["spitter", "skitter"]
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
	for p in world.chest_spots:
		var n := Models.chest()
		n.position = p
		n.rotation.y = rng.randf() * TAU
		add_child(n)
		chests.append({"pos": p, "open": false, "prog": 0.0, "node": n})

func _spawn_wild() -> void:
	if net_on and not is_host:
		return
	for p in world.wild_spots:
		var sp: String = Data.KIN.keys()[rng.randi_range(0, Data.KIN.size() - 1)]
		var rec := Save.new_kin(sp)
		rec["level"] = rng.randi_range(T["kin_lvl"][0], T["kin_lvl"][1])
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

func dmg_mult(_h: Hunter) -> float:
	return 1.0

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

func knock(h: Hunter, by: Ent, _o: Dictionary) -> void:
	if h.downed or h.out:
		return
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
	slowmo = 0.16
	freeze_frame(0.07)
	cam.add_trauma(0.35)
	sfx("kill", null, -2.0)

func _check_team(team: int) -> void:
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

func eliminate(h: Hunter, by: Ent, why: String) -> void:
	if h.out:
		return
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
	_check_last()

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
			e.teleport(world.spawns[0] if world.spawns.size() > 0 else world.random_ground())
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
	return bool(opts.get("god", false))

func on_mob_dead(mb: Mob, by: Ent, _o: Dictionary) -> void:
	if net_on:
		net_event(["mobdead", mb.nid, by.nid if by else ""])
	var credit: Ent = by
	if by is Kin and by.owner_h:
		credit = by.owner_h
	sfx("kill", mb.pos, -6.0, 1.3)
	fx.burst(mb.pos + Vector3(0, 0.6, 0), mb.md["color"], 22, 5.0, 0.6)
	if not world.is_void(mb.pos.x, mb.pos.z):
		for i in int(mb.md["gems"]):
			drop("gem", mb.pos + Vector3(0, 0.6, 0), int(round(3 * float(T["loot"]))))
		if rng.randf() < (0.35 if mb.mkind == "brute" else 0.12):
			drop("seed", mb.pos + Vector3(0, 0.6, 0), 1, Data.CROPS.keys()[rng.randi_range(0, Data.CROPS.size() - 1)])
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
	if h == player and hud:
		hud.toast("Ledge grab", Color("cfe6c0"))

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
		"gem": h.gems += int(p["v"])
		"seed": h.seeds[p["key"]] = int(h.seeds.get(p["key"], 0)) + int(p["v"])
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
	shots.append({"pos": at, "vel": v2, "dmg": dmg, "team": team, "by": by, "life": life, "r": size, "col": col, "x": extra, "node": mi, "prev": at})
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
			# terrain and rocks
			if world.is_block(p.x, p.z) and world.ground_at(p.x, p.z) + World.BLOCK_H > p.y or world.ground_at(p.x, p.z) > p.y:
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
	var dir: Vector2 = (s["vel"] as Vector2).normalized()
	var o := {"src": "shot", "crit": crit}
	if float(x.get("kb", 0.0)) > 0.0:
		o["kb"] = dir * float(x["kb"])
	if x.has("burn"): o["burn"] = x["burn"]
	if x.has("slow"): o["slow"] = x["slow"]
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
		d *= 0.35
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
	if player and not player.out:
		cam.follow(player.prev.lerp(player.pos, alpha), delta, true)
	elif player:
		cam.follow(cam.focus, delta, false)
	_update_aim(alpha)
	for pd in world.pads:
		var top: Node3D = pd["node"].get_node("Top")
		top.scale = Vector3.ONE * (1.0 + sin(time * 5.0) * 0.06)
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
	for a in [["dash", "dash"], ["jump", "jump"], ["signature", "sig"], ["reload", "reload"], ["tonic", "tonic"], ["throw", "throw"], ["kin_skill", "skill"]]:
		if Input.is_action_just_pressed(a[0]):
			pending_input[a[1]] = true

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu") and not over:
		paused = not paused
		hud.set_paused(paused)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_HIDDEN

func step(dt: float) -> void:
	if over:
		return
	time += dt
	if opts.get("glide_demo", false) and player:
		if time < 0.05:
			player.teleport(player.pos + Vector3(0, 6, 0)); player.grounded = false
		player.inp["glide"] = true
		player.inp["move"] = Vector2(1, 0.3).normalized()
	if player and not player.out:
		for k in ["dash", "jump", "sig", "reload", "tonic"]:
			if pending_input[k]:
				player.inp[k] = true
				pending_input[k] = false
		if pending_input["throw"]:
			pending_input["throw"] = false
			_player_throw()
		if pending_input["skill"]:
			pending_input["skill"] = false
			if player.kin and not player.downed:
				player.kin.command_skill(_ground_aim(player))
	for h in hunters:
		if h.ctrl == "bot" and not h.remote and not h.out and not h.extracted:
			bot_brain.think(self, h, dt)
	for h in hunters: h.sim(dt)
	if opts.get("autoplay", false) and int(time * 60.0) % 15 == 0:
		for h in hunters:
			var hist: Array = h.get_meta("hist", [])
			hist.append("%.1f:(%.1f,%.1f,%.1f) v(%.1f,%.1f,%.1f) g%d f%.2f r%.2f gr%d void%d %s" % [time, h.pos.x, h.pos.y, h.pos.z, h.vel.x, h.vel.y, h.vel.z, int(h.grounded), h.fly_t, h.roll_t, int(h.grap.size() > 0), int(h.over_void()), String(h.ai.get("goal_kind", ""))])
			if hist.size() > 10: hist.pop_front()
			h.set_meta("hist", hist)
	for k in kins: k.sim(dt)
	for mb in mobs: mb.sim(dt)
	_separate()
	_update_shots(dt)
	_update_pickups(dt)
	_update_pads(dt)
	_update_interact(dt)
	_update_portals(dt)
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
	if k == null or player.downed:
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
		if h.out or h.extracted or h.downed:
			continue
		var want: bool = h.inp.get("interact", false)
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
		# 3. open a chest
		if best.is_empty():
			for c in chests:
				if not c["open"] and h.flat_dist(c["pos"]) < 1.6:
					best = {"kind": "chest", "chest": c, "label": "Hold F to open"}
					break
		if h == player:
			interact = best
		if best.is_empty() or not want:
			continue
		match best["kind"]:
			"revive":
				var o: Hunter = best["ent"]
				if o.remote:
					_rev_out[o.nid] = float(_rev_out.get(o.nid, 0.0)) + dt / Data.MATCH["revive_time"]
					o.revive += dt / Data.MATCH["revive_time"]
				else:
					o.revive += dt / Data.MATCH["revive_time"]
					if o.revive >= 1.0:
						revive_hunter(o, h)
			"catch":
				var k: Kin = best["ent"]
				k.catch_prog += dt / 1.3
				if k.catch_prog >= 1.0:
					_catch(h, k)
			"chest":
				var c: Dictionary = best["chest"]
				c["prog"] += dt / 0.7
				if c["prog"] >= 1.0:
					_open_chest(h, c)

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
	var lid: Node3D = c["node"].get_node("Lid")
	lid.rotation.x = -1.1
	lid.position.y = 0.62
	lid.position.z = 0.2
	sfx("pickup", c["pos"], 0.0, 0.8)
	fx.burst(c["pos"] + Vector3(0, 0.6, 0), Color("f2c84a"), 20, 4.0, 0.6)
	for i in randi_range(4, 7):
		drop("gem", c["pos"] + Vector3(0, 0.8, 0), int(round(3 * float(T["loot"]))))
	if randf() < 0.65:
		drop("seed", c["pos"] + Vector3(0, 0.8, 0), randi_range(1, 2), Data.CROPS.keys()[randi_range(0, Data.CROPS.size() - 1)])
	if h and not h.remote and h.tonics < 3 and randf() < 0.4:
		h.tonics += 1
		if h == player: hud.toast("+1 tonic", Color("8ff0a0"))

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
				eliminate(h, null, "abyss")
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
	var r := result.duplicate()
	r["time"] = time
	r["tier"] = tier
	if player:
		r["gems"] = player.gems
		r["lost_gems"] = player.lost_gems
		r["seeds"] = player.seeds.duplicate()
		r["caught"] = player.caught.duplicate(true)
		r["kills"] = player.kills
		r["knocks"] = player.knocks
		r["damage"] = int(player.dmg_done)
		r["tonics"] = player.tonics
		if player.kin:
			r["kin_events"] = player.kin.events.duplicate(true)
			r["kin_trust"] = player.kin.trust
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
			player = make_hunter("P" + peer, t, String(r["cls"]), String(r["name"]), "local", rec, at)
			player.tonics = int(Save.d["items"].get("tonic", 0))
			if Save.has_building("workshop"):
				player.glide_max = Hunter.GLIDE_TIME * 1.5
			if player.kin:
				_apply_treat(player.kin)
		else:
			var h := make_hunter("P" + peer, t, String(r["cls"]), String(r["name"]), "remote", krec, at)
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
			var cls: String = ["light", "medium", "heavy"][randi_range(0, 2)]
			var h := make_hunter(next_id("b"), t, cls, names.pop_back() if names.size() > 0 else "Bot", "bot", bot_kin_record(), at)
			h.ai = bot_brain.new_mind(rng, float(opts.get("bot_skill", 0.6)))
			h.tonics = 1

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
	if player == null or player.out or opts.get("autoplay", false):
		return
	_tip_t += get_process_delta_time()
	if _tip_t < 1.0:
		return
	_tip("move", "WASD to move, aim with the mouse, hold left click to shoot. Shift dashes, Space jumps. Hold Space in the air to glide.")
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
