class_name Match
extends Node3D
## One PvPvE extraction match: islands, hunters and their kin, monsters, wild kin, chests and exits.
## The simulation runs at a fixed 60 steps per second; visuals interpolate between steps.

const DT := 1.0 / 60.0

var opts := {}
var world: World
var skytrain: SkyTrain = null   # the loop train, on maps that have one
var fx: Fx
var cam: CamRig
var hud: Node = null
var env: WorldEnvironment
var hunters: Array = []
var kins: Array = []
var mobs: Array = []
var shots: Array = []
var pickups: Array = []     # {pos, vel, kind:"gem"|"seed"|"tonic", v, key, node, t}
var boxes: Array = []       # deathboxes, see Life
var beacons: Array = []     # revive beacons, see Life
var chests: Array = []      # {pos, open, prog, node, tier}
var shrines: Array = []     # {pos, used, prog, node}
var breaks: Array = []      # {i, pos, kind, hp, node, dead}
var ring_n := 0
var pellet_hits := {}        # shotgun volley + target -> slugs landed
var air_rings: Array = []   # {pos, dir, node, cd: {hunter nid: time}}
var wpicks: Array = []      # found weapons on the ground {id, pos, wid, rar, node}
var wdrop_n := 0
var warden_done := false
var meteor_at := -1.0       # when the meteor shower starts
var meteor_end := -1.0
var meteor_next := 0.0
var meteors: Array = []     # {at, t, tele}
var glimmer_done := false
# ---- tutorial
var tut_step := -1
var tut_text := ""
var tut_moved := 0.0
var tut_kills := 0
var tut_flag := false
var tut_down_t := 0.0
var tut_wait := 0.0
var tut_throws0 := 0
var exits: Exits = null     # the ways out: skiff docks, rift hatches, outpost uplinks (see Exits)
var lairs: Lairs = null     # boss lairs: sealed arenas, their bosses and Rare Eggs (see Lairs)
var truce: Truce = null     # emotes and truces between squads (see Truce)
var skydrop: DropSquad = null  # the planning phase before the ship sets off, drop leaders and formations (see DropSquad)
var spawn_plan: SpawnPlan = null   # which of the map's candidate spawns are live this match (see SpawnPlan)
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
var duel: Duel = null
var shot_n := 0          # the duel room: you and one sparring bot (opts "duel")
var slowmo := 0.0
var slow_k := 0.35
var killcam_text := ""
var cam_style := ""
var swing_hits := {}
var aim_y := 0.0
## Shots and ability projectiles bend up or down to the height of what you aimed at, so you can
## hit someone a terrace or two above or below. Further than this and the cliff takes it.
const AIM_DY_MAX := 2.6
var hitstop := 0.0
var aim_line: MeshInstance3D
var aim_ring: MeshInstance3D
var muzzle_light: OmniLight3D
var collapse_warned := false
var rng := RandomNumberGenerator.new()
var pending_input := {"base": false, "dash": false, "jump": false, "sig": false, "reload": false, "tonic": false, "kit": false, "throw": false, "skill": false, "ult": false, "sec": false, "gear1": false, "gear2": false, "swap": false}
var zones: Array = []      # hero areas: dome, sanctuary, well
var fields: Fields = null  # patches made by kin abilities (Thorn Patch)
var verbs: Verbs = null    # walls, reflect windows, tethers, traps, bridges and yanks left by abilities
var _later: Array = []     # [due time, Callable]: delayed ability steps, on match time (not wall-clock timers)

## Run cb after `delay` seconds of match time: delayed effects, echoes, landing blasts. Unlike a
## SceneTree timer it pauses with the match, keeps step with headless sims and dies with the match.
func later(delay: float, cb: Callable) -> void:
	_later.append([time + maxf(0.0, delay), cb])

func _run_later() -> void:
	if _later.is_empty():
		return
	var due: Array = []
	for it in _later:
		if float(it[0]) <= time: due.append(it)
	for it in due:
		_later.erase(it)
		(it[1] as Callable).call()
var _bond_cb: Callable
var _combo_cb: Callable
var player_lost: Array = []  # your kin left behind when you went down: {uid, kin, holder}
var tracked: Array = []      # your kin a rival in this match is holding: {kin, holder}
var track_t := 8.0
var kstat := {"kin_ab": 0, "auto": 0, "combo": 0, "ult": 0, "swap": 0, "left": 0}   # counts for tests
var bot_brain := Bot.new()
var seed_val := 0
var length := 360.0
var net_on := false
var tier := 0
var T: Dictionary = {}
var bot_diff := "medium"         # how good the bot hunters are this run (Data.BOT_DIFF)
var bot_cfg: Dictionary = {}
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
	length = float(o.get("length", Data.MATCH["length"] * (1.7 if big else 1.0)))
	tier = clampi(int(o.get("tier", 0)), 0, Data.TIERS.size() - 1)
	T = Data.TIERS[tier]
	bot_diff = String(o.get("bot_diff", Settings.get_v("bot_diff")))
	if not Data.BOT_DIFF.has(bot_diff):
		bot_diff = Data.auto_bot_diff(tier, int(Save.d.get("extracts", 0)), o.get("tutorial", false) or o.get("training", false))
	bot_cfg = Data.BOT_DIFF[bot_diff]
	_build_env()
	Sfx.play_music("hollow" if tier >= 2 else "match")
	Sfx.play_ambience("match")
	world = World.new()
	world.name = "World"
	world.biome = T["biome"].duplicate()
	world.clouds = T["clouds"]
	add_child(world)
	# real expeditions are on a hand-made map, and so is the tutorial (a small calm one); training keeps a generated one
	var layout := {}
	if big and not o.get("procedural", false):
		layout = World.load_layout(String(o.get("map", World.layout_for_tier(tier))))
	elif o.get("tutorial", false):
		layout = World.load_layout("tutorial")
	if not layout.is_empty():
		world.generate_authored(layout, seed_val)
	else:
		world.generate(seed_val, World.BIG_SIZE if big else 64, World.BIG_ISLANDS if big else 7)
	world.build_meshes()
	fx = Fx.new(); fx.name = "Fx"; add_child(fx)
	fields = Fields.new(self)
	verbs = Verbs.new(self)
	if world.layout_id != "" and not o.get("tutorial", false):
		biomes = BiomeRun.new(self)
		if biomes.active():
			biomes.decorate()
			biomes.place_hazards()
		else:
			biomes.free_up(); biomes = null
	# the combat systems listen to hits and statuses: bond meter and combos
	_bond_cb = func(a, t, amt, tags): Bond.on_hit(a, t, amt, tags)
	_combo_cb = func(t, st, by, dur): Combos.record(t, st, by, dur)
	CombatBus.hit_landed.connect(_bond_cb)
	CombatBus.status_applied.connect(_combo_cb)
	cam = CamRig.new(); cam.name = "Cam"; add_child(cam)
	cam.lead = float(Settings.get_v("cam_lead"))
	cam_style = String(Settings.get_v("cam_style"))
	cam.use_style(cam_style)
	_build_shot_pool()
	if o.has("net"):
		net_on = true
		is_host = Net.me == String(o["net"]["host"])
		Net.begin_match("kf-" + String(o["net"]["mid"]), String(o["net"]["host"]), self)
	_spawn_pads_and_exits()
	_spawn_hunters()
	if not opts.get("tutorial", false) and not opts.get("duel", false):
		_spawn_mobs()        # the tutorial brings its own monsters, one step at a time
	if not opts.get("duel", false):
		_spawn_chests()
	if not world.train_route.is_empty() and not opts.get("duel", false):
		skytrain = SkyTrain.new()
		skytrain.name = "SkyTrain"
		add_child(skytrain)
		skytrain.setup(self)
	Life.place_beacons(self)
	_spawn_breakables()
	for rg in world.rings:
		var rn := Models.air_ring()
		rn.position = rg["pos"]
		rn.rotation.y = atan2(float(rg["dir"].x), float(rg["dir"].y))
		add_child(rn)
		air_rings.append({"pos": rg["pos"], "dir": rg["dir"], "node": rn, "cd": {}})
	if o.get("break_demo", false) and player and not breaks.is_empty():
		# test: stand by some breakables with two found weapons on the ground
		var b0: Vector3 = breaks[0]["pos"]
		for b in breaks:
			if b["kind"] == "barrel": b0 = b["pos"]; break
		player.teleport(b0 + Vector3(2.2, 0, 0.6))
		spawn_weapon("sniper", 3, b0 + Vector3(1.6, 0, 1.8), "", false)
		spawn_weapon("smg", 4, b0 + Vector3(3.0, 0, 1.6), "", false)
	if not opts.get("duel", false):
		_spawn_wild()
	if not (opts.get("duel", false) or opts.get("tutorial", false) or opts.get("training", false)):
		# the map is fixed; what's out on it this time isn't (rare kin, vaults, item caches, boss lairs)
		spawn_plan = SpawnPlan.new(self)
		spawn_plan.build(layout)
		if lairs: lairs.plug_into(spawn_plan)     # which boss lairs are live this match
		spawn_plan.roll(seed_val)
		spawn_plan.spawn_all()
	if lairs: lairs.ensure_live()
	skydrop = DropSquad.new(self)
	skydrop.setup()
	var Hud = load("res://scripts/ui/hud.gd")
	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.setup(self)
	if player and player.dropping:
		hud.toast("Steer to choose where you land", Color("f3eee2"))
	if skydrop.planning and player:
		hud.open_map(true)
	if player:
		cam.snap(player.pos)
	if opts.get("duel", false) and player:
		duel = Duel.new()
		duel.setup(self)
		duel.attach_keys()
		hud.toast("Duel room  ·  B sets up the bot  ·  X resets", Color("f3eee2"))
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
	var sky: Color = T["sky"]
	var amb: Color = T["ambient"]
	var cl: Array = T["clouds"]
	env.environment = Look.environment({"top": sky.darkened(0.2), "mid": sky.lerp(amb, 0.35), "horizon": (cl[1] as Color).lerp(T["sun"], 0.5).lightened(0.15),
		"below": cl[0], "ambient": amb, "ambient_energy": 0.5, "fog": (cl[1] as Color).lightened(0.12).lerp(Color("4a5aa8"), 0.35), "sun_col": T["sun"]})
	add_child(env)
	var sun := Look.lights(self, T["sun"], 1.0, Vector3(-55, -35, 0), 60.0)
	sun.shadow_opacity = 0.8

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

func _spawn_pads_and_exits() -> void:
	for pd in world.pads:
		var n := Models.jump_pad(Color("8fe3c8"))
		n.position = pd["pos"]
		n.rotation.y = atan2(-(pd["land"].x - pd["pos"].x), -(pd["land"].z - pd["pos"].z))
		add_child(n)
		pd["node"] = n
		# where it goes: a sign over the pad, and the flight path and landing ring when you're close
		var to_role: String = world.islands[pd["to"]]["role"] if pd["to"] < world.islands.size() else ""
		var lbl := Label3D.new()
		var to_name: String = String(world.islands[pd["to"]].get("name", "")) if pd["to"] < world.islands.size() else ""
		lbl.text = "to " + (to_name if to_name != "" else String({"heart": "the Heart", "camp": "the monster camp", "nest": "the kin nest", "grove": "the grove", "shrine": "the shrine"}.get(to_role, "the next island")))
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
	exits = Exits.new()
	exits.setup(self)
	truce = Truce.new(self)
	lairs = Lairs.new()
	lairs.setup(self)

func make_hunter(id: String, team: int, cls: String, pname: String, ctrl: String, kin_rec: Dictionary, at: Vector3, kit := {}, kin_rec2 := {}) -> Hunter:
	var h := Hunter.new()
	if cls == "" or not Data.CLASSES.has(cls):
		cls = ["light", "medium", "heavy"][rng.randi_range(0, 2)]
	if String(kit.get("weapon", "")) == "?":
		kit = kit.duplicate()
		var pool: Array = Data.CLASSES[cls]["weapons"]
		kit["weapon"] = pool[rng.randi_range(0, pool.size() - 1)]
	h.init_hunter(self, id, team, cls, pname, ctrl, kit)
	h.lives = 99 if (opts.get("tutorial", false) or opts.get("training", false)) else int(T.get("lives", 2))
	if opts.get("tutorial", false) or opts.get("training", false) or opts.get("duel", false) or opts.get("sandbox", false) or opts.get("unlocked", false):
		h.unlock_all()        # practice modes (and the sim's scripted player) start with the whole kit
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
	if TWO_KIN and not kin_rec2.is_empty() and not kin_rec.is_empty():
		# (retired) everyone brought two kin: the second waited on the bench until you swapped
		var k2 := Kin.new()
		k2.init_kin(self, id + "k2", kin_rec2["species"], kin_rec2, h)
		add_child(k2)
		k2.teleport(at)
		k2.bench()
		kins.append(k2)
		ents_by_id[k2.nid] = k2
		h.kin2 = k2
	return h

## Who B would take you to: the teammate nearest the cursor on screen (alive, standing, not out).
func base_target(h: Hunter) -> Hunter:
	var mates: Array = hunters.filter(func(o): return o != h and o.team == h.team and not o.out and not o.downed and not o.extracted and not o.dropping and not o.riding)
	if mates.is_empty():
		return null
	if h != player or mates.size() == 1:
		return mates[0]
	var mp := get_viewport().get_mouse_position()
	var best: Hunter = mates[0]; var bd := 1e9
	for o in mates:
		var sp := cam.unproject_position(o.pos) if not cam.is_position_behind(o.pos) else Vector2(1e6, 1e6)
		var d := sp.distance_to(mp)
		if d < bd: bd = d; best = o
	return best

## How high the player is over the ground under them (over the abyss: over the last ground they stood on).
func player_altitude() -> float:
	if player == null:
		return 0.0
	var g := world.ground_at(player.pos.x, player.pos.z) if not world.is_void(player.pos.x, player.pos.z) else player.last_gy
	return maxf(0.0, player.pos.y - g)

## One kin per expedition: a short, readable kit. Flip back on to bring a benched second kin again.
const TWO_KIN := false

func my_kit() -> Dictionary:
	return {"weapon": String(opts.get("weapon", Save.d.get("weapon", ""))), "perk": ""}

func bot_kit() -> Dictionary:
	# the weapon is picked once the bot's class is known (see make_hunter): any of its class's
	return {"weapon": "?", "perk": ""}

func bot_kin_record() -> Dictionary:
	var sp: String = Data.common_kin()[rng.randi_range(0, Data.common_kin().size() - 1)]
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
	# more squads than islands: share the bigger islands, still as far apart as possible
	if spots.size() < n_teams:
		var rest: Array = world.spawns.filter(func(q): return not spots.has(q))
		while spots.size() < n_teams and rest.size() > 0:
			var best := 0; var bd := -1.0
			for i in rest.size():
				var dmin := 1e9
				for q in spots: dmin = minf(dmin, Vector2(rest[i].x - q.x, rest[i].z - q.z).length())
				if dmin > bd: bd = dmin; best = i
			spots.append(rest[best]); rest.remove_at(best)
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
	var total := int(opts.get("total", 999))
	var made := 0
	for t in n_teams:
		var base: Vector3 = spots[t % spots.size()] if spots.size() > 0 else world.random_ground()
		for s in squad:
			if made >= total and not (t == 0 and s == 0):
				break
			made += 1
			var at := base
			if s > 0:
				for _k in 30:
					var q := base + Vector3(rng.randf_range(-1.6, 1.6), 0, rng.randf_range(-1.6, 1.6))
					if not world.is_void(q.x, q.z) and not world.is_block(q.x, q.z) and absf(world.ground_at(q.x, q.z) - base.y) < 0.3:
						at = Vector3(q.x, world.ground_at(q.x, q.z), q.z); break
			if t == 0 and s == 0 and not opts.get("spectate", false):
				var rec: Dictionary = Save.active_kin()
				var rec2: Dictionary = Save.second_kin()
				if opts.has("demo_kin"):
					var ids: Array = Data.common_kin()
					var sp0 := String(opts["demo_kin"])
					rec = Save.new_kin(sp0 if Data.KIN.has(sp0) else "cindle")
					rec["name"] = Data.KIN[rec["species"]]["name"]
					rec["trust"] = 95.0
					rec2 = Save.new_kin(String(ids[(ids.find(rec["species"]) + 1) % ids.size()]))
				player = make_hunter("p0", 0, String(opts.get("cls", Data.class_of_save())), Save.d.get("name", "Hunter"), "bot" if opts.get("autoplay", false) else "local", rec, at, my_kit(), rec2)
				if opts.get("autoplay", false):
					player.ai = bot_brain.new_mind(rng, 0.7)
				if "--at-stairs" in OS.get_cmdline_user_args() and not world.stairs.is_empty():
					# test: start beside a flight of stairs
					var si: int = world.stairs.keys()[0]
					var sd: Vector2i = world.stairs[si]
					at = Vector3(si % world.w + 0.5 - sd.x * 1.5, 0, si / world.w + 0.5 - sd.y * 1.5)
					at.y = world.ground_at(at.x, at.z)
				player.teleport(at)
				player.tonics = int(Save.d["items"].get("tonic", 0)) + 2; player.free_tonics = 2     # everyone sets out with a couple
				if not opts.get("tutorial", false) and not opts.get("training", false):
					player.rift_keys = int(Save.d["items"].get("rift_key", 0))     # your Rift Keys come with you (and go in your box if you die)
				_apply_home_perks(player)
				_apply_armory_kit(player)
				if player.kin:
					_apply_treat(player.kin)
				_start_drop(player, at)
				continue
			var bk := bot_kit()
			var bname: String = names.pop_back() if names.size() > 0 else "Bot"
			var brec := bot_kin_record()
			# a rival who's holding one of your lost kin may be out here with it
			var held := _held_for_match(t)
			if not held.is_empty():
				bname = String(held["holder"])
				brec = (held["rec"] as Dictionary).duplicate(true)
			var h := make_hunter(next_id("b"), t, "", bname, "bot", brec, at, bk, bot_kin_record() if rng.randf() < 0.6 else {})
			if not held.is_empty() and h.kin:
				(h.kin as Kin).lost_uid = String(brec.get("uid", ""))
				(h.kin as Kin).lost_from = "you"
				tracked.append({"kin": h.kin, "holder": h})
			h.ai = bot_brain.new_mind(rng, float(opts.get("bot_skill", bot_cfg["skill"])), bot_cfg)
			h.tonics = 3
			# rivals carry a little treasure: worth taking from their box
			if rng.randf() < 0.35 + 0.15 * tier:
				h.pack.append(Loot.valuable(Loot.roll_valuable(rng, mini(tier, 2))))
			if rng.randf() < 0.2: h.rift_keys = 1     # now and then a rival brings a key (and knows where the hatches are)
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
	h.teleport(at + off + Vector3(0, 26.0, 0))
	h.dropping = true
	h.diving = true
	h.drop_from = Vector2(at.x + off.x, at.z + off.z)
	h.grounded = false
	h.gliding = true
	h.glide_k = 1.0
	h.ai["land"] = at

# ---- the skyship
const SHIP_Y := 40.0
const SHIP_SPEED := 11.0
var big := false
var ship := {}
var biomes: BiomeRun = null     # biome regions on an authored map (spawn tables, rarity, mutations, traps)

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

## When a bot aboard should jump to come down on a spot: as the ship passes nearest it.
func plan_jump(h: Hunter, at: Vector3) -> void:
	if ship.is_empty() or not ship.has("a"):
		return
	h.ai["land"] = at
	var a: Vector3 = ship["a"]; var b: Vector3 = ship["b"]
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var k := clampf(Vector2(at.x - a.x, at.z - a.z).dot(ab) / ab.length_squared(), 0.04, 0.97)
	h.ai["jump_at"] = clampf(k * float(ship["dur"]) - 2.2 + randf_range(-0.5, 0.5), maxf(0.6, time + 0.2), float(ship["ride"]) - 0.5)

## Off the ship. A squadmate waiting on the drop leader can't jump by themselves (force: they're
## jumping with the leader, or the ship has reached the end of its run).
func ship_jump(h: Hunter, force := false) -> void:
	if not h.riding:
		return
	if not force and skydrop and skydrop.waits(h):
		if h == player and hud:
			hud.toast_small("%s leads the drop  ·  %s to go solo" % [skydrop.leader(h.team).pname, Settings.key_cap("separate")], Color("ffd27a"))
		return
	h.riding = false
	var off := Vector3(rng.randf_range(-0.8, 0.8), 0, rng.randf_range(-0.8, 0.8))
	h.teleport(ship_pos() + Vector3(0, -1.5, 0) + off)
	h.dropping = true
	h.diving = true
	h.drop_from = Vector2(h.pos.x, h.pos.z)
	h.gliding = true
	h.glide_k = 1.0
	h.grounded = false
	h.vel = ship["dir"] * 3.0
	if h == player:
		sfx("whoosh", null, -2.0)
		if hud and not force:
			hud.toast("Steer with %s%s%s%s  ·  %s opens your glider early" % [Settings.key_cap("up"), Settings.key_cap("left"), Settings.key_cap("down"), Settings.key_cap("right"), Settings.key_cap("jump")], Color("cfeaff"))
		elif hud:
			hud.toast("Gliding in formation  ·  %s to break away" % Settings.key_cap("separate"), Color("cfeaff"))
	if skydrop and skydrop.is_lead(h):
		skydrop.on_lead_jump(h)

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
		if h.riding and h.remote and is_host and time > float(ship["ride"]) + 6.0:
			# someone who dropped connection aboard: stop counting them as still in the match
			h.riding = false
			eliminate(h, null, "left", true)
			continue
		if not h.riding or h.remote:
			continue
		var auto: bool = h.ctrl == "bot" or opts.get("autoplay", false)
		var lead: Hunter = skydrop.leader(h.team) if skydrop else null
		if lead and lead != h and lead.remote and not h.drop_solo and not lead.riding and lead.dropping:
			# online: the leader jumped on their own machine; join them
			ship_jump(h, true)
			h.drop_follow = lead
			h.drop_slot = skydrop._free_slot(lead)
			continue
		if skydrop and skydrop.waits(h):
			continue          # jumps with the leader
		if done or (auto and time >= float(h.ai.get("jump_at", 0.0))):
			ship_jump(h, done)
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
		h.free_tonics += 1

## What you took from the armory: the weapon in your hands and the gloves you wear (at risk: die and
## they're in your deathbox like everything else), and your backpack's size.
func _apply_armory_kit(h: Hunter) -> void:
	if opts.get("training", false) or opts.get("tutorial", false) or opts.get("duel", false):
		return
	h.pack_cap = Econ.pack_cap()
	for it in opts.get("kit_items", []):
		match String(it.get("t", "")):
			"weapon": Loot.equip(h, it)
			"glove":
				if Gear.ALL.has(String(it["id"])):
					h.gear[Gear.slot_of(String(it["id"]))] = {"id": it["id"], "rar": int(it["rar"])}
	h.refresh_gear()

func _apply_treat(k: Kin) -> void:
	match String(Save.d.get("treat", "")):
		"treat_power": k.power *= 1.25
		"treat_hardy": k.max_hp *= 1.4; k.hp = k.max_hp
		"treat_calm": k.trust = minf(100.0, k.trust + 12.0)

func _spawn_mobs() -> void:
	if net_on and not is_host:
		return
	for c in world.camp_spots:
		var p: Vector3 = c["pos"]
		var comp: Array
		match String(c.get("kind", "normal")):
			"heavy": comp = ["brute", "spitter", "skitter", "sentinel"]
			"light":
				var lr := rng.randf()
				comp = ["skitter", "skitter"] if lr < 0.4 else (["spitter", "skitter"] if lr < 0.7 else ["bomber", "skitter"])
			_:
				var nr := rng.randf()
				if nr < 0.15 * tier + 0.2:
					comp = ["brute", "skitter", "bomber"]
				elif nr < 0.5:
					comp = ["skitter", "bomber", "spitter"]
				elif nr < 0.75:
					comp = ["sentinel", "skitter", "skitter"]
				else:
					comp = ["spitter", "skitter", "bomber"]
		# a camp in a biome region spawns from that region's table instead
		var bcomp: Array = biomes.camp_comp(c) if biomes else []
		if not bcomp.is_empty(): comp = bcomp
		for kk in comp:
			var q := p
			for _t in 20:
				var cand := p + Vector3(rng.randf_range(-1.8, 1.8), 0, rng.randf_range(-1.8, 1.8))
				if not world.is_void(cand.x, cand.z) and not world.is_block(cand.x, cand.z):
					q = Vector3(cand.x, world.ground_at(cand.x, cand.z), cand.z); break
			var smb := spawn_mob(kk, q)
			if biomes: biomes.dress(smb)

func spawn_mob(kk: String, at: Vector3) -> Mob:
	at = _clear_spot(at)
	var mb := Mob.new()
	mb.init_mob(self, next_id("m"), kk, at, float(T.get("mob", 1.0)) if not T.is_empty() else 1.0)
	add_child(mb)
	mobs.append(mb)
	ents_by_id[mb.nid] = mb
	return mb

## Gunfire and explosions you can't see show up on the minimap as sound pings.
var sound_pings: Array = []    # {pos, t, kind, key}
func note_sound(by, at: Vector3, kind: String) -> void:
	if player == null or player.out:
		return
	if by is Ent and (by as Ent).team == player.team:
		return
	var d := Vector2(at.x - player.pos.x, at.z - player.pos.z).length()
	if d > 48.0 or (by is Hunter and not (by as Hunter).unseen and d < 20.0):
		return
	var key: String = (by as Ent).nid if by is Ent else str(at.snapped(Vector3(4, 4, 4)))
	for sp in sound_pings:
		if sp["key"] == key and time - float(sp["t"]) < 0.7:
			return
	sound_pings.append({"pos": at, "t": time, "kind": kind, "key": key})
	if sound_pings.size() > 40:
		sound_pings.pop_front()

## The menu's "I'm stuck": hop to the nearest open ground (not a way out of falling).
func unstick() -> void:
	if player == null or player.out or player.downed or player.dropping or player.riding:
		return
	if world.is_void(player.pos.x, player.pos.z) and not player.grounded:
		return
	var p := world.free_spot_near(player.pos, [], 1.0, 0.5)
	player.teleport(Vector3(p.x, world.ground_at(p.x, p.z), p.z))
	player.vel = Vector3.ZERO

## Room for something new to appear: off rocks and walls, not boxed in, and not inside another
## monster or kin. Spots the map already placed stay put when they're fine.
func _clear_spot(at: Vector3) -> Vector3:
	if world == null or world.is_void(at.x, at.z):
		return at
	var near: Array = []
	for mb in mobs:
		if not mb.dead and mb.flat_dist(at) < 3.0: near.append(mb.pos)
	for k in kins:
		if not k.dead and Vector2(k.pos.x - at.x, k.pos.z - at.z).length() < 3.0: near.append(k.pos)
	var p := world.free_spot_near(at, near, 1.1, 0.42, 6.0)
	return Vector3(p.x, maxf(p.y, world.ground_at(p.x, p.z)), p.z)

func _spawn_chests() -> void:
	for cs in world.chest_spots:
		add_chest(cs["pos"], int(cs["tier"]))
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

func add_chest(p: Vector3, t: int) -> Dictionary:
	var n := Models.chest(t)
	n.position = p
	n.rotation.y = rng.randf() * TAU
	add_child(n)
	var c := {"pos": p, "open": false, "prog": 0.0, "node": n, "tier": t}
	chests.append(c)
	return c

func _spawn_breakables() -> void:
	for b in world.break_spots:
		_add_break(String(b["kind"]), b["pos"])
	if opts.get("training", false) and player:
		# something to smash and something to pick up right where you start
		for t in [[Vector3(-2.0, 0, 1.2), "crate"], [Vector3(-2.6, 0, 2.2), "pot"], [Vector3(2.2, 0, 1.0), "weapon"]]:
			var q: Vector3 = player.pos + t[0]
			if world.is_void(q.x, q.z) or world.is_block(q.x, q.z):
				continue
			q.y = world.ground_at(q.x, q.z)
			if t[1] == "weapon": spawn_weapon("sniper", 2, q, "", false)
			else: _add_break(t[1], q)
		# a glove rack: a row of gloves to try (actives go in your Q slot, passives in the other)
		var gi := 0
		for gid in ["blink", "quake", "bubble", "grapple", "frost", "power_core"]:
			var q2: Vector3 = player.pos + Vector3(-4.5 + gi * 1.8, 0, -2.6)
			gi += 1
			if world.is_void(q2.x, q2.z) or world.is_block(q2.x, q2.z):
				continue
			q2.y = world.ground_at(q2.x, q2.z)
			spawn_gear(gid, 2, q2)
		# the way into the duel room: a glowing pad next to where you start
		if not opts.get("duel", false):
			for off in [Vector3(3.6, 0, 2.6), Vector3(-3.6, 0, 2.6), Vector3(3.6, 0, -1.0), Vector3(0, 0, 4.0)]:
				var dq: Vector3 = player.pos + off
				if world.is_void(dq.x, dq.z) or world.is_block(dq.x, dq.z):
					continue
				dq.y = world.ground_at(dq.x, dq.z)
				duel_pad = dq
				var pad := Models.jump_pad(Color("ff8a7a"))
				pad.position = dq
				add_child(pad)
				var lbl := Label3D.new()
				lbl.text = "DUEL ROOM\n%s to enter" % Settings.key_cap("interact")
				lbl.font = UI.big; lbl.font_size = 40; lbl.pixel_size = 0.01; lbl.outline_size = 12
				lbl.modulate = Color("ffb0a0"); lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED; lbl.no_depth_test = true
				lbl.position = dq + Vector3(0, 2.0, 0)
				add_child(lbl)
				break
	# the weapons lying in the open are the same for everyone in an online match
	var wr := RandomNumberGenerator.new(); wr.seed = seed_val * 31 + 7
	var keys: Array = Data.weapon_ids()
	for i in world.weapon_spots.size():
		var wk0 := String(keys[wr.randi() % keys.size()])
		var wr0 := Data.roll_rarity(wr, 1 if tier >= 2 else 0)
		var wsp: Vector3 = world.weapon_spots[i]
		spawn_weapon(wk0, wr0, wsp, "ws%d" % i, false, -1, Loot.weapon(wk0, wr0, Loot.roll_element(wr, world.biome_at(wsp.x, wsp.z))))

func _add_break(kind_s: String, at: Vector3) -> void:
	var n := Models.breakable(kind_s)
	n.position = at
	n.rotation.y = rng.randf() * TAU
	add_child(n)
	breaks.append({"i": breaks.size(), "pos": at, "kind": kind_s, "hp": BREAK_HP[kind_s], "node": n, "dead": false})

func spawn_weapon(w: String, rar: int, at: Vector3, id := "", send := true, ammo := -1, item := {}) -> void:
	if id == "":
		wdrop_n += 1
		id = "w%s_%d" % [player.nid if player else "x", wdrop_n]
	var n := Models.weapon_drop(w, rar)
	n.position = at
	add_child(n)
	var wp := {"id": id, "pos": at, "wid": w, "rar": rar, "node": n, "ammo": ammo}
	if not item.is_empty():
		wp["item"] = item
		if String(item.get("el", "")) != "":
			_element_motes(n, Loot.ELEMENTS[String(item["el"])]["col"], String(item.get("uq", "")) != "")
	wpicks.append(wp)
	if net_on and send:
		net_event(["wdrop", id, w, rar, _r(at.x), _r(at.y), _r(at.z), ammo, String(item.get("el", "")), String(item.get("uq", ""))])

## A found weapon with an element (or a named one) glows its colour, so you can spot it from afar.
func _element_motes(n: Node3D, col: Color, unique: bool) -> void:
	var p := CPUParticles3D.new()
	p.amount = 18 if unique else 10
	p.lifetime = 1.2
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.45
	p.direction = Vector3.UP; p.spread = 25.0
	p.initial_velocity_min = 0.4; p.initial_velocity_max = 1.1
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.05; p.scale_amount_max = 0.11
	var sm := SphereMesh.new(); sm.radius = 0.5; sm.height = 1.0; sm.radial_segments = 6; sm.rings = 3
	p.mesh = sm
	p.material_override = Models.glow_mat(Color(col, 0.9))
	p.position = Vector3(0, 0.7, 0)
	n.add_child(p)

## Treasure on the ground: a valuable for the backpack.
func spawn_val(item: Dictionary, at: Vector3) -> void:
	wdrop_n += 1
	var vd: Dictionary = Loot.VALUABLES.get(String(item.get("id", "")), {})
	var n := Models.gear_drop(vd.get("col", Color("ffd36a")), int(vd.get("rar", 1)))
	n.position = at
	add_child(n)
	if String(item.get("id", "")) == "soul_ember":
		_element_motes(n, Color("9ff0e0"), true)
	wpicks.append({"id": "v%d" % wdrop_n, "pos": at, "val": String(item.get("id", "")), "item": item, "rar": int(vd.get("rar", 1)), "node": n, "wid": "", "ammo": -1})

## A weapon found at a spot: the region's element sometimes, and now and then a named unique.
func found_weapon(at: Vector3, wid: String, rar: int, unique_chance := 0.0) -> Dictionary:
	if unique_chance > 0.0 and rng.randf() < unique_chance:
		return Loot.weapon("", 0, "", Loot.roll_unique(rng))
	return Loot.weapon(wid, rar, Loot.roll_element(rng, world.biome_at(at.x, at.z)))

# ------------------------------------------------------------------ gear
var gpads: Array = []        # pocket jump pads {pos, t, node}
var smokes: Array = []       # smoke clouds {pos, r, t, node}
var plats: Array = []        # emergency platforms {tiles, t, node}

func spawn_gear(gid: String, rar: int, at: Vector3) -> void:
	wdrop_n += 1
	var n := Models.gear_drop(Gear.ALL[gid]["col"], rar)
	n.position = at
	add_child(n)
	wpicks.append({"id": "g%d" % wdrop_n, "pos": at, "gear": gid, "rar": rar, "node": n, "wid": "", "ammo": -1})

func _take_gear(h: Hunter, wp: Dictionary) -> void:
	wpicks.erase(wp)
	(wp["node"] as Node3D).queue_free()
	var slot := Gear.slot_of(String(wp["gear"]))      # actives go in the Q slot, passives in the other
	var old: Dictionary = h.gear[slot]
	h.gear[slot] = {"id": wp["gear"], "rar": int(wp["rar"])}
	h.gear_cd[slot] = 0.0
	h.refresh_gear()
	if not old.is_empty():
		var ba := randf() * TAU
		spawn_gear(String(old["id"]), int(old["rar"]), Vector3(h.pos.x + cos(ba) * 0.9, h.ground(), h.pos.z + sin(ba) * 0.9))
	var col: Color = Gear.ALL[wp["gear"]]["col"]
	sfx("pickup", h.pos, 0.0, 0.9)
	fx.ring(h.pos, 1.4, col, 0.35)
	if h == player and hud:
		var g: Dictionary = Gear.ALL[wp["gear"]]
		hud.toast("%s  ·  %s%s" % [g["name"], Gear.stat_text(wp["gear"], int(wp["rar"])), ("  ·  " + Settings.key_cap("gear1")) if Gear.active(wp["gear"]) else "  ·  passive"], col)

## Fire the active on a gear slot.
func use_gear(h: Hunter, slot: int) -> void:
	var g: Dictionary = h.gear[slot]
	if g.is_empty() or h.downed or h.out or h.riding or h.dropping or float(h.gear_cd[slot]) > 0.0:
		return
	var gid: String = g["id"]
	if not Gear.active(gid):
		return
	var gd: Dictionary = Gear.ALL[gid]
	h.gear_cd[slot] = Gear.cd_of(gid, int(g.get("rar", 1))) * h.rank_cd_k("gear")
	var col: Color = gd["col"]
	h.reveal_t = maxf(h.reveal_t, 0.6)
	if h == player:
		h._ab_feedback("gear0", "cast")
	if gd.has("effects"):
		# newer gloves are built from the same effect blocks as abilities, scaled by rarity
		Effects.run(Gear.effects_of(gid, int(g.get("rar", 1))), h, {"slot": "gear", "ability": gid, "level": h.ability_level("gear")})
		sfx("skill", h.pos, -4.0, 1.0)
		return
	match gid:
		"jump_pad":
			var d := h.aim_dir()
			var at := Vector3(h.pos.x + d.x * 1.6, h.pos.y, h.pos.z + d.y * 1.6)
			if world.is_void(at.x, at.z) or world.is_block(at.x, at.z):
				at = h.pos
			at.y = world.ground_at(at.x, at.z) if not world.is_void(at.x, at.z) else h.pos.y
			var n := Models.gear_pad(col)
			n.position = at
			add_child(n)
			gpads.append({"pos": at, "t": 20.0, "node": n, "cd": {}})
			sfx("throw", h.pos, -2.0, 1.2)
		"gust_fan":
			var d := h.aim_dir()
			h.vel = Vector3(d.x * 9.0, 13.0, d.y * 9.0)
			h.grounded = false
			h.glide_cd = 0.0
			h.shot_down = false
			h.glide_fuel = minf(1.0, h.glide_fuel + 0.35)
			fx.burst(h.pos + Vector3(0, 0.4, 0), col, 20, 5.0, 0.5, -2.0, 1.0)
			sfx("glide", h.pos, 0.0, 1.5)
		"platform":
			var tiles: Array = []
			var y := h.pos.y - 0.1
			if not h.grounded and h.over_void():
				y = maxf(h.lip_y - 0.2, h.pos.y - 0.4) if h.below_lip else h.pos.y - 0.4
			var lv := int(round(y / World.LEVEL))
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var tx := int(floor(h.pos.x)) + dx; var tz := int(floor(h.pos.z)) + dz
					if world.inb(tx, tz) and world.kind[world.idx(tx, tz)] == World.T_VOID:
						var i := world.idx(tx, tz)
						tiles.append([i, int(world.level[i])])
						world.kind[i] = World.T_GROUND
						world.level[i] = clampi(lv, 0, 255)
			var n := Models.gear_platform(col)
			n.position = Vector3(floor(h.pos.x) + 0.5, lv * World.LEVEL, floor(h.pos.z) + 0.5)
			add_child(n)
			plats.append({"tiles": tiles, "t": 8.0, "node": n})
			if h.pos.y < lv * World.LEVEL:
				h.pos.y = lv * World.LEVEL + 0.05
				h.vel.y = 0.0
			h.glide_fuel = 1.0
			h.shot_down = false
			sfx("shield", h.pos, 0.0, 0.8)
		"smoke":
			var n := Models.gear_smoke()
			n.position = h.pos
			add_child(n)
			smokes.append({"pos": h.pos, "r": 3.6, "t": 8.0, "node": n})
			sfx("cloak", h.pos, 0.0, 0.7)
		"medkit":
			h.heal(40.0)
			h.armor = minf(h.max_armor, h.armor + 20.0)
			fx.burst(h.pos + Vector3(0, 1.0, 0), col, 16, 3.0, 0.6, -3.0)
			sfx("heal", h.pos, -2.0, 1.1)
		"scanner":
			for o in hunters:
				if o.team != h.team and not o.out and o.flat_dist(h) < 26.0:
					o.reveal_t = maxf(o.reveal_t, 3.0)
			fx.ring(h.pos, 26.0, Color(col, 0.6), 0.8)
			sfx("ping", h.pos, 0.0, 0.8)
		"shock":
			Abil._blast(h, h.pos, 3.4, 12.0, 13.0, col, 5.0, "gear")
			shake(0.3, h.pos)
		"rocket":
			# straight up: a column of thrust that also cools your glider, so you can keep going
			var d := h.aim_dir()
			h.vel = Vector3(h.vel.x * 0.5 + d.x * 2.0, 17.0, h.vel.z * 0.5 + d.y * 2.0)
			h.grounded = false
			h.glide_cd = 0.0
			h.shot_down = false
			h.roll_t = 0.0
			h.glide_fuel = minf(1.0, h.glide_fuel + 0.5)
			fx.burst(h.pos + Vector3(0, 0.2, 0), col, 26, 6.0, 0.5, -1.0, 1.2, Vector3.DOWN, 30.0)
			sfx("glide", h.pos, 0.0, 0.7)
		"skyhook":
			# hook a point toward the cursor and swing up to it: onto a ledge above you if there is
			# one there, otherwise straight up into the air
			var d := h.aim_dir()
			var aim: Vector3 = h.inp.get("aim", h.pos)
			var reach := clampf(Vector2(aim.x - h.pos.x, aim.z - h.pos.z).length(), 2.0, 9.0)
			var tx := h.pos.x + d.x * reach; var tz := h.pos.z + d.y * reach
			var gy := world.ground_at(tx, tz)
			var to := Vector3(h.pos.x + d.x * 3.0, h.pos.y + 8.0, h.pos.z + d.y * 3.0)
			if gy > World.VOID + 1.0 and not world.is_block(tx, tz) and gy > h.pos.y - 1.0:
				to = Vector3(tx, gy + 1.2, tz)
			h.launch_to(to, 0.55)
			h.glide_cd = 0.0
			fx.bolt(h.pos + Vector3(0, 1.2, 0), to, Color(col, 0.9))
			sfx("throw", h.pos, -2.0, 0.7)
		"hover":
			# a second jump in the air (or a big hop on the ground) and the glider ready right after
			h.vel.y = maxf(h.vel.y, 11.0)
			h.grounded = false
			h.glide_cd = 0.0
			h.roll_t = 0.0
			fx.ring(h.pos, 1.2, col, 0.3)
			fx.burst(h.pos, col, 14, 3.0, 0.4, 2.0, 1.0, Vector3.DOWN, 50.0)
			sfx("jump", h.pos, -2.0, 1.3)

func _update_gear_fx(dt: float) -> void:
	for gp in gpads.duplicate():
		gp["t"] = float(gp["t"]) - dt
		if float(gp["t"]) <= 0.0:
			(gp["node"] as Node3D).queue_free(); gpads.erase(gp); continue
		var top: Node3D = (gp["node"] as Node3D).get_node_or_null("Top")
		if top: top.scale = Vector3.ONE * (1.0 + sin(time * 6.0) * 0.06)
		for h in hunters:
			if h.out or h.downed or h.remote or not h.grounded:
				continue
			if h.flat_dist(gp["pos"]) < 0.8 and absf(h.pos.y - float(gp["pos"].y)) < 0.6 and float(gp["cd"].get(h.nid, -9.0)) < time:
				gp["cd"][h.nid] = time + 1.0
				var hv := Vector2(h.vel.x, h.vel.z)
				var d: Vector2 = hv.normalized() if hv.length() > 0.5 else h.aim_dir()
				h.vel = Vector3(d.x * maxf(hv.length(), 6.0), 17.0, d.y * maxf(hv.length(), 6.0))
				h.grounded = false
				h.glide_cd = 0.0
				fx.burst(gp["pos"] + Vector3(0, 0.3, 0), Color("8ff0c8"), 16, 5.0, 0.4, -2.0)
				sfx("jump", h.pos, -2.0, 0.8)
	for sm in smokes.duplicate():
		sm["t"] = float(sm["t"]) - dt
		var n: Node3D = sm["node"]
		n.scale = Vector3.ONE * clampf(float(sm["t"]), 0.0, 1.0)
		if float(sm["t"]) <= 0.0:
			n.queue_free(); smokes.erase(sm)
	for pl in plats.duplicate():
		pl["t"] = float(pl["t"]) - dt
		var n: Node3D = pl["node"]
		if float(pl["t"]) < 1.5:
			n.visible = int(time * 8.0) % 2 == 0
		if float(pl["t"]) <= 0.0:
			for tv in pl["tiles"]:
				world.kind[int(tv[0])] = World.T_VOID
				world.level[int(tv[0])] = int(tv[1])
			n.queue_free(); plats.erase(pl)

## Inside a smoke cloud?
func in_smoke(p: Vector3) -> bool:
	for sm in smokes:
		if Vector2(p.x - sm["pos"].x, p.z - sm["pos"].z).length() < float(sm["r"]):
			return true
	return false

func _take_weapon(h: Hunter, wp: Dictionary, from_net := false, keep_old := false) -> void:
	if wp.has("gear"):
		_take_gear(h, wp)
		return
	if wp.has("val"):
		return
	wpicks.erase(wp)
	(wp["node"] as Node3D).queue_free()
	if from_net:
		return
	if net_on:
		net_event(["wtake", wp["id"], h.nid, wp["wid"], wp["rar"]])
	var old_it := Loot.of_hand(h)
	var old_ammo := h.ammo if h.reload_t <= 0.0 else 0
	Loot.equip(h, Pack.ground_item(wp), int(wp.get("ammo", -1)))
	if not keep_old:
		# the old one is put down where you stand (with the backpack, the player's goes in it instead)
		var ba := randf() * TAU
		var back := Vector3(cos(ba), 0, sin(ba)) * 0.9
		spawn_weapon(String(old_it["wid"]), int(old_it["rar"]), Vector3(h.pos.x + back.x, h.ground(), h.pos.z + back.z), "", true, old_ammo, old_it if Loot.keepable(old_it) else {})
	var col: Color = Data.RARITY[int(wp["rar"])]["color"]
	sfx("reload", h.pos, 0.0, 0.8)
	fx.ring(h.pos, 1.4, col, 0.35)
	fx.burst(h.pos + Vector3(0, 0.9, 0), col, 14, 3.0, 0.5)
	if h == player:
		train["_weapon"] = true
		var r: Dictionary = Data.RARITY[int(wp["rar"])]
		hud.toast("%s  ·  +%d%% damage" % [h.wpn["name"], int(round((float(r["dmg"]) - 1.0) * 100.0))] if int(wp["rar"]) > 0 else String(h.wpn["name"]), col)

## What pressing interact on a ground item will do, for the prompt.
func _pickup_label(h: Hunter, wp: Dictionary) -> String:
	var it := Pack.ground_item(wp)
	var k := Settings.key_cap("interact")
	var nm := Loot.name_of(it)
	var fill := "%d/%d" % [h.pack.size(), h.pack_cap]
	var into_hand := false
	match String(it.get("t", "")):
		"weapon": into_hand = Loot.value(it) > Loot.value(Loot.of_hand(h)) or not Pack.wants(h, it)
		"glove":
			var cur: Dictionary = h.gear[Gear.slot_of(String(it["id"]))]
			into_hand = cur.is_empty() or Loot.value(it) > Loot.value({"t": "glove", "id": cur["id"], "rar": cur["rar"]}) or not Pack.wants(h, it)
	if opts.get("training", false):
		return "Press %s to take %s  ·  %s" % [k, nm, Loot.sub_of(it)]
	if into_hand:
		var old := Loot.of_hand(h) if String(it["t"]) == "weapon" else {}
		var to_pack := ("  ·  yours goes in your pack (%s)" % fill) if Loot.keepable(old) else ""
		return "Press %s to equip %s  ·  %s%s" % [k, nm, Loot.sub_of(it), to_pack]
	if Pack.room(h):
		return "Press %s to pack %s  (%s)  ·  %s" % [k, nm, fill, Loot.sub_of(it)]
	return "Backpack full (%s)  ·  %s to swap something out for %s" % [fill, k, nm]

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
			if wp.has("val"):
				continue
			if wp.has("gear"):
				if (h.gear[0].is_empty() or h.gear[1].is_empty()) and h.flat_dist(wp["pos"]) < 1.4 and absf(h.pos.y - float(wp["pos"].y)) < 1.0:
					_take_gear(h, wp)
					break
				continue
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
	if by == player:
		train["_smash"] = true
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
			if randf() < 0.4:
				drop("armor", at + Vector3(0, 0.5, 0), 25)
			if not from_net and randf() < 0.16:
				var keys: Array = Data.weapon_ids()
				spawn_weapon(String(keys[randi() % keys.size()]), Data.roll_rarity(rng), at)
		"barrel":
			_barrel_boom(at, by, from_net)

## An exploding barrel: hurts and throws everyone nearby, its breaker included.
func _barrel_boom(at: Vector3, by: Ent, from_net := false) -> void:
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
			# every peer sees the same chain, so only the one that set it off rolls for loot
			if from_net: _break(b, by, true)
			else: hit_break(b, 30.0, by)

## Air rings: anyone flying through one gets thrown forward along their own heading, the glider
## pops open and gets a little fuel back, so a chain of rings carries you across a long gap.
func _update_rings(dt: float) -> void:
	if player and not player.out and int(time * 4.0) % 4 == 0:
		for rg in air_rings:
			if player.pos.distance_to(rg["pos"]) < 9.0:
				_tip("rings", "Glowing rings in the air between islands: jump off the edge, glide (hold %s) and fly through them for a burst of speed. Fast gliders barely sink." % Settings.key_cap("jump"))
				break
	for rg in air_rings:
		# rings stand straight up facing along the route; they don't spin
		for h in hunters:
			if h.remote or h.grounded or h.out or h.downed or h.riding or not h.pad.is_empty():
				continue
			var c: Vector3 = rg["pos"]
			var body: Vector3 = h.pos + Vector3(0, 0.8, 0)
			if body.distance_to(c) > 1.6:
				continue
			if float(rg["cd"].get(h.nid, -9.0)) > time:
				continue
			rg["cd"][h.nid] = time + 3.0
			ring_n += 1
			h.add_stat("rings")
			var hv := Vector2(h.vel.x, h.vel.z)
			var rd: Vector2 = rg["dir"]
			var d: Vector2 = hv.normalized() if hv.length() > 1.0 else rd
			if absf(d.dot(rd)) > 0.5:
				d = rd if d.dot(rd) > 0.0 else -rd    # line up with the ring
			var spd := minf(maxf(hv.length(), Hunter.GLIDE_SPEED) + 4.0, Hunter.GLIDE_MAX)
			h.vel.x = d.x * spd; h.vel.z = d.y * spd
			h.vel.y = maxf(h.vel.y, 2.0)
			h.glide_fuel = minf(1.0, h.glide_fuel + 0.35)
			if not h.gliding and not h.dropping:
				h.glide_cd = 0.0
				h.gliding = true
			fx.ring(c, 1.6, Color("8fe3ff"), 0.3)
			fx.burst(c, Color("cff6ff"), 14, 4.0, 0.35, 0.0)
			sfx("whoosh", c, -2.0 if h == player else -10.0, 1.3)
			if h == player:
				cam.punch(0.05)

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
			var nrm := d / l if l > 0.0001 else Vector2(1, 0)
			var push := nrm * (mind - l)
			if world.occupy(e.pos.x + push.x, e.pos.z + push.y, e.r, e.pos.y, e.grounded) == 0.0:
				e.pos.x += push.x; e.pos.z += push.y

func _spawn_wild() -> void:
	if net_on and not is_host:
		return
	for p in world.wild_spots:
		var sp: String = Data.common_kin()[rng.randi_range(0, Data.common_kin().size() - 1)]
		var rec := Save.new_kin(sp)
		rec["level"] = rng.randi_range(T["kin_lvl"][0], T["kin_lvl"][1])
		Evo.simulate(rec, rng)
		rec["shimmer"] = rng.randf() < 1.0 / 25.0   # a rare colour you'll want to catch
		spawn_wild(rec, p)

func spawn_wild(rec: Dictionary, at: Vector3, dazed := false) -> Kin:
	at = _clear_spot(at)
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

## Where the mouse points, at the right height: on a foe under the cursor at that foe's height,
## otherwise on the ground under the cursor. Aiming on your own height made shots at someone a
## terrace above (or below) drift sideways past them, because the camera looks down at an angle.
func _mouse_aim() -> Vector3:
	var base_y := player.pos.y + 0.95
	var mp := get_viewport().get_mouse_position()
	var best: Ent = null
	var bd := 52.0
	for e in foes_of(player.team):
		if e.dead or not e.visible:
			continue
		if absf(e.pos.y - player.pos.y) > World.LEVEL * 3.0:
			continue
		var sp := cam.unproject_position(e.pos + Vector3(0, 0.8, 0))
		var d := sp.distance_to(mp)
		if d < bd:
			bd = d; best = e
	if best:
		var q := cam.mouse_on_plane(best.pos.y + 0.95)
		aim_y = best.pos.y
		return Vector3(q.x, base_y, q.z)
	aim_y = player.pos.y
	var p := cam.mouse_on_plane(base_y)
	for _i in 2:
		var g := world.ground_at(p.x, p.z)
		if g <= World.VOID + 1.0 or absf(g - player.pos.y) > World.LEVEL * 3.0:
			break
		p = cam.mouse_on_plane(g + 0.95)
		aim_y = g
	return Vector3(p.x, base_y, p.z)

## How much grip the ground has here (ice patches in a frost region make it slippery).
func ground_grip(p: Vector3) -> float:
	return biomes.grip(p) if biomes else 1.0

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
	if h == null: return 1.0
	var bot_k := float((h.ai.get("diff", {}) as Dictionary).get("dmg", 1.0)) if h.ctrl == "bot" and h != player else 1.0
	return bot_k * (0.5 if h.weak_t > 0.0 else 1.0) * (1.25 if h.bless_t > 0.0 else 1.0) * (1.0 + h.gear_stat("dmg")) * h.fuse_mod("dmg") * (Life.R["sickness_dmg"] if h.sick_t > 0.0 else 1.0)

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

## Squad members' colours on the map and their pings (in squad order).
const MATE_COLS := [Color("ffd23f"), Color("5fd0ff"), Color("8ff0a0"), Color("ff9be8"), Color("ffa25f")]
func mate_col(h: Hunter) -> Color:
	var i := 0
	for x in hunters:
		if x == h: break
		if x.team == h.team: i += 1
	return MATE_COLS[i % MATE_COLS.size()]

const SQUAD_PING_T := 45.0
## A squad ping: one per hunter (a new one moves it), seen by their squad on the map, the minimap and
## as a marker in the world; it lasts a while or until its owner takes it down.
func squad_ping(h: Hunter, p: Vector3, from_net := false) -> void:
	if h == null:
		return
	if not world.is_void(p.x, p.z):
		p.y = world.ground_at(p.x, p.z)
	else:
		p.y = 0.0
	unping(h, true)
	pings.append({"pos": p, "col": mate_col(h), "t": 0.0, "by": h, "team": h.team, "life": SQUAD_PING_T})
	if player and h.team == player.team:
		sfx("ping", null, -6.0, 1.15)
	if net_on and not from_net:
		net_event(["sping", h.nid, p.x, p.y, p.z])
	if skydrop:
		skydrop.on_ping(h, p)
	if not from_net:
		for b in hunters:
			if b != h and b.team == h.team and b.ctrl == "bot" and not b.remote and not b.out:
				b.ai["ping_goal"] = {"pos": p, "until": time + 30.0, "by": h}

func unping(h: Hunter, quiet := false, from_net := false) -> void:
	for pg in pings.duplicate():
		if pg.get("by") == h:
			pings.erase(pg)
			for b in hunters:
				if b.ctrl == "bot" and b.ai.has("ping_goal") and (b.ai["ping_goal"] as Dictionary).get("by") == h:
					b.ai.erase("ping_goal")
	if not quiet and net_on and not from_net:
		net_event(["unping", h.nid])

func my_ping() -> Dictionary:
	for pg in pings:
		if player and pg.get("by") == player: return pg
	return {}

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
	if truce: truce.on_damage(target, by, d)
	var tags: Array = o.get("tags", [])
	if tags.is_empty():
		tags = [String(o.get("src", "primary")) if o.get("src", "") != "" else "primary"]
	if o.get("stun", 0.0) > 0.0: tags = tags + ["stun"]
	CombatBus.hit_landed.emit(by, target, d, tags)
	var crit: bool = o.get("crit", false)
	var src: String = o.get("src", "")
	var credit: Ent = by
	if by is Kin and by.owner_h:
		credit = by.owner_h
	if target is Hunter and target != credit:
		(target as Hunter).dmg_taken += d
	if credit is Hunter and target != credit:
		credit.dmg_done += d
		if o.has("leech") and target.team != credit.team and not credit.remote:
			credit.heal(d * float(o["leech"]))     # a Void weapon drains what it deals
		if not credit.remote and target.team != credit.team and src != "burn":
			credit.ult = minf(1.0, credit.ult + d / 320.0 * (1.3 if credit.perk_n("overcharge") > 0 else 1.0))
		if not credit.remote and target.team != credit.team and not (target is Hunter and (target as Hunter).downed):
			credit.gain_xp(d * (0.6 if target is Hunter else 0.35))
			var lv: int = credit.armor_gain(d * (1.0 if target is Hunter else 0.33))
			if lv >= 0:
				_armor_up(credit)
				if "--simtest" in OS.get_cmdline_user_args(): print("ARMOR %s -> %s" % [credit.pname, Hunter.ARMOR_TIERS[lv][0]])
	var mine := credit == player or (target == player)
	var armor_hit: bool = o.get("armor", false) or (target is Hunter and (target as Hunter).armor > 0.5)
	var col := Color("fff4d6")
	if armor_hit: col = Color("7ac8ff")
	if crit: col = Color("ffd23f") if not armor_hit else Color("b0e4ff")
	if target == player: col = Color("ff6a5a")
	elif target is Kin and target.owner_h == player: col = Color("ffa08a")
	# only numbers that involve you: other fights nearby don't spray digits over yours
	if mine:
		fx.number(target.pos + Vector3(0, 1.5 if target is Hunter else 1.0, 0), d, col, crit)
	# impact: a short freeze on heavy hits you deal or take (scaled by the hit, never on chip damage)
	if mine and src != "burn":
		var kbv: Vector2 = o.get("kb", Vector2.ZERO) if o.get("kb", null) is Vector2 else Vector2.ZERO
		if d >= 18.0 or kbv.length() >= 7.0 or o.get("stun", 0.0) > 0.0:
			freeze_frame(clampf(0.025 + d * 0.0011 + kbv.length() * 0.003, 0.03, 0.075))
	if credit == player and target != player and src != "burn":
		sfx("crit" if crit else "hit", target.pos, -4.0 if crit else -6.0, 1.25 if armor_hit else randf_range(0.92, 1.08))
		if hud: hud.hitmarker(crit, armor_hit)
	if target == player and by and hud:
		hud.hurt_from(by.pos)
	if target == player:
		sfx("hurt", null, -4.0)
		cam.add_trauma(clampf(d / 40.0, 0.12, 0.45))
		if hud: hud.hurt_flash(d)
	fx.burst(target.pos + Vector3(0, 0.8, 0), Color("fff2d0") if not crit else Color("ffd23f"), 6 if d < 10 else 12, 3.5, 0.3, 8.0, 0.7)

## Cancels anything a hunter had going: a sword charge, a sniper wind-up.
func cancel_abilities(h: Hunter) -> void:
	h.charge = {}
	h.warm_t = 0.0
	h.mel_hold = 0.0
	h.strike_at_end = {}

const KNOCK_HEAL := 0.10     # of the knocker's max health, only for whoever landed the knock
func knock(h: Hunter, by: Ent, _o: Dictionary) -> void:
	if h.downed or h.out:
		return
	cancel_abilities(h)
	h.downed = true
	h.downs += 1
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
		# the Supervive 1.0 knock reward: a small heal and a dash back
		if not credit.downed and credit.team != h.team:
			var healed := minf(credit.max_hp - credit.hp, credit.max_hp * KNOCK_HEAL)
			credit.hp += healed
			if healed > 0.5: fx.word(credit.pos + Vector3(0, 2.1, 0), "+%d" % int(round(healed)), Color("7fe08a"), false)
			if credit.armor_gain(Hunter.ARMOR_KNOCK_XP) >= 0: _armor_up(credit)
			credit.gain_xp(90.0)
			credit.dashes = minf(credit.max_dashes(), floorf(credit.dashes) + 1.0)
			credit.ex_cd = 0.0 if credit.max_dashes() <= 1.0 else credit.ex_cd
		add_feed("%s knocked %s" % [credit.pname, h.pname])
		if credit == player:
			_reward_moment(h.pos)
			if player.kin and player.kin.state != "fainted":
				player.kin.bark("kill")
	else:
		add_feed("%s went down" % h.pname)
	sfx("knock", h.pos, 0.0)
	fx.burst(h.pos + Vector3(0, 0.8, 0), Data.TEAM_COLORS[h.team % Data.TEAM_COLORS.size()], 24, 5.0, 0.6)
	if net_on and not h.remote:
		net_event(["knock", h.nid, credit.nid if credit else ""])
	if h == player:
		cam.add_trauma(0.6)
		if h.kin and h.kin.state != "fainted":
			h.kin.bark("owner_down")
	_check_team(h.team)

func freeze_frame(t: float) -> void:
	hitstop = maxf(hitstop, t)

## Armor went up a tier: a coloured ring for everyone to see, and a callout for you.
func _armor_up(h: Hunter) -> void:
	var col := h.armor_col()
	fx.ring(h.pos, 2.4, Color(col, 0.9), 0.45)
	fx.burst(h.pos + Vector3(0, 1.0, 0), col, 14, 3.5, 0.5)
	if h == player:
		sfx("revive", null, -6.0)
		if hud: hud.toast("Armor upgraded  ·  %s" % String(Hunter.ARMOR_TIERS[h.armor_tier][0]), col)

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
	var col: Color = h.accent()
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
		if x.kin2 and not x.kin2.dead and x.kin2.hp > 0.0:
			return
	for x in members:
		if not x.remote:
			eliminate(x, x.last_hit_by, "team wiped")
	_team_gone(team)

## The whole team is down or dead with nobody to bring them back: everyone's dead for good.
func _team_gone(team: int) -> void:
	if Life.team_alive(self, team):
		return
	for x in hunters:
		if x.team == team and x.out and not x.remote:
			Life.make_gone(self, x)

func revive_hunter(h: Hunter, by: Ent) -> void:
	if h.remote:
		return
	if net_on:
		net_event(["up", h.nid])
	h.downed = false
	h.hp = h.max_hp * Life.R["revive_hp"]
	h.armor = 0.0
	h.revive = 0.0
	h.inv_t = 1.5
	sfx("revive", h.pos, 0.0)
	fx.ring(h.pos, 1.8, Color("9ee2a0"), 0.4)
	add_feed("%s is back up" % h.pname)
	if by is Hunter and by != h:
		(by as Hunter).revives += 1

func eliminate(h: Hunter, by: Ent, why: String, final := false) -> void:
	if h.out:
		return
	h.deaths += 1
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
	h.set_meta("died_why", why)
	h.set_meta("died_at", time)
	var waiting := false
	if not net_on and not h.remote:
		# everything they carried goes into a deathbox where they fell. While a teammate is still
		# in the fight they can bring them back at it (or at a revive beacon)
		var bx := Life.drop_box(self, h, why)
		h.lost_gems = h.gems
		h.gems = 0; h.seeds = {}; h.caught = []
		Life.kin_on_death(self, h, bx)
		waiting = Life.team_alive(self, h.team) and not opts.get("training", false) and not opts.get("tutorial", false)
		if not waiting:
			Life.make_gone(self, h)
	elif net_on and not is_host and not h.remote:
		net_event(["spill", _r(h.pos.x), _r(h.pos.y), _r(h.pos.z), h.gems, h.seeds, h.caught])
	elif not world.is_void(h.pos.x, h.pos.z) and not h.remote:
		var n := mini(10, int(ceil(h.gems / 5.0)))
		for i in n:
			drop("gem", h.pos + Vector3(0, 0.5, 0), maxi(1, h.gems / maxi(1, n)))
		for s in h.seeds:
			drop("seed", h.pos + Vector3(0, 0.5, 0), int(h.seeds[s]), s)
		for rec in h.caught:
			spawn_wild(rec, h.pos, true)
	if net_on:
		h.lost_gems = h.gems
		h.gems = 0; h.seeds = {}; h.caught = []
		# the kin they brought are left behind, dazed, for anyone to collect
		_leave_kin(h)
		h.gone = true
	if h == player:
		if not waiting:
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
	h.armor = h.max_armor
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
	if teams.size() <= 1 and exits:
		exits.on_last_team()

func on_fell(e: Ent) -> void:
	if e is Hunter and opts.get("autoplay", false):
		print("FELL ", e.pname, " hist=", e.get_meta("hist", []))
	if e is Hunter:
		if e.out:
			return
		sfx("fall", e.pos, 0.0)
		if duel and e == duel.bot:
			# knocked off the island in the duel room: that's a knock, then a fresh round
			duel.stats["knocks"] = int(duel.stats["knocks"]) + 1
			duel.round_n += 1
			hud.toast("Off the edge! Round to you", Color("8fe3c8"))
			duel.reset()
			return
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
		player.add_stat("mobs")
	if biomes: biomes.on_mob_dead(mb)
	if lairs: lairs.on_mob_dead(mb, credit)
	var big_mob: bool = mb.mkind in ["brute", "warden"] or mb.md.get("boss", false)
	sfx("die_big" if big_mob else "die_small", mb.pos, -5.0, randf_range(0.9, 1.15))
	if credit == player: sfx("kill", null, -12.0, 1.4)
	fx.burst(mb.pos + Vector3(0, 0.6, 0), mb.md["color"], 22, 5.0, 0.6)
	if not world.is_void(mb.pos.x, mb.pos.z) and not _o.get("self", false):
		for i in int(mb.md["gems"]):
			drop("gem", mb.pos + Vector3(0, 0.6, 0), int(round(3 * float(T["loot"]))))
		if mb.md.get("stag", false) and rng.randf() < 0.6:
			drop("armor", mb.pos + Vector3(0, 0.6, 0), 25)
		if mb.mkind in ["brute", "warden", "sentinel"] and rng.randf() < (1.0 if mb.mkind == "warden" else 0.4):
			spawn_gear(Gear.roll(rng), Data.roll_rarity(rng, 2 if mb.mkind == "warden" else 0), mb.pos + Vector3(0.8, 0, 0.4))
		if mb.mkind == "warden":
			# the Warden guards the best things: a weapon (sometimes a named one), treasure, maybe a Soul Ember
			var wkeys: Array = Data.weapon_ids()
			var wit := found_weapon(mb.pos, String(wkeys[randi() % wkeys.size()]), Data.roll_rarity(rng, 2), 0.2)
			spawn_weapon(String(wit["wid"]), int(wit["rar"]), mb.pos + Vector3(-0.8, 0, 0.4), "", true, -1, wit)
			spawn_val(Loot.valuable(Loot.roll_valuable(rng, 2)), mb.pos + Vector3(0, 0, -0.9))
			if rng.randf() < 0.5:
				spawn_val(Loot.valuable("soul_ember"), mb.pos + Vector3(0.9, 0, -0.6))
		elif mb.mkind == "brute" and rng.randf() < 0.25:
			spawn_val(Loot.valuable(Loot.roll_valuable(rng, 0 if tier == 0 else 1)), mb.pos + Vector3(0, 0, -0.8))
		if mb.mkind == "glimmer":
			var keys: Array = Data.weapon_ids()
			var git := found_weapon(mb.pos, String(keys[randi() % keys.size()]), Data.roll_rarity(rng, 1))
			spawn_weapon(String(git["wid"]), int(git["rar"]), mb.pos, "", true, -1, git)
			if credit is Hunter: add_feed("%s caught the Glimmerkin's treasure" % credit.pname)
		if rng.randf() < (0.35 if mb.mkind == "brute" else 0.12):
			drop("seed", mb.pos + Vector3(0, 0.6, 0), 1, Data.pick_seed())
		# a Rift Key: always from the Warden, sometimes from an elite (one that can be staggered, or a rare one)
		if exits and not exits.list.is_empty() and (mb.mkind == "warden" or ((mb.md.get("stag", false) or mb.rarity >= 3) and mb.mkind != "glimmer" and rng.randf() < 0.06)):
			exits.drop_key(mb.pos)
	# the big ones are worth a perk to whoever brought them down
	if mb.mkind in ["warden", "brute"] and credit is Hunter and not (credit as Hunter).remote and (mb.mkind == "warden" or rng.randf() < 0.5):
		offer_perks(credit as Hunter, "boss" if mb.mkind == "warden" else "brute")
	if credit == player and player.kin and randf() < 0.15:
		player.kin.bark("kill")

func on_kin_faint(k: Kin) -> void:
	if k.owner_h == player:
		add_feed("%s fainted" % k.rec.get("name", "Your kin"))
		if player.kin2 and (player.kin2 as Kin).hp > 0.0 and hud:
			hud.toast("%s fainted  ·  %s swaps in %s" % [k.rec.get("name", "Your kin"), Settings.key_cap("swap_kin"), (player.kin2 as Kin).rec.get("name", "your other kin")], Color("ffb0a0"))
	elif k.owner_h and k.owner_h.ctrl == "bot" and k.owner_h.kin == k and k.owner_h.kin2 and (k.owner_h.kin2 as Kin).hp > 0.0:
		k.owner_h.get_tree().create_timer(0.6, false).timeout.connect(func(): if is_instance_valid(k.owner_h): k.owner_h.swap_kin())
	_check_team(k.team)

# ------------------------------------------------------------------ kin combat events
## A kin used an ability: its name pops up over it so you can read the fight.
func on_kin_ability(k: Kin, def: AbilityDef, auto: bool) -> void:
	kstat["kin_ab"] += 1
	if auto: kstat["auto"] += 1
	if k.owner_h == null or k.unseen:
		return
	if player and k.flat_dist(player) < 20.0:
		fx.word(k.pos + Vector3(0, 1.3 + k.r, 0), def.display_name, def.color.lerp(Color.WHITE, 0.25), false)
	if k.owner_h == player:
		player.add_stat("kin_abilities")
		if auto and hud and not train.has("_auto_told"):
			train["_auto_told"] = true

func on_kin_swap(h: Hunter, now_k: Kin, _was: Kin) -> void:
	kstat["swap"] += 1
	fx.burst(h.pos + Vector3(0, 1.5, 0), now_k.sp["color"], 18, 3.5, 0.5)
	fx.ring(h.pos, 1.4, now_k.sp["color"], 0.3)
	sfx("swap", h.pos, -4.0)
	if h == player:
		train["_swapped"] = true
		if hud: hud.toast("%s is out" % now_k.rec.get("name", Data.KIN[now_k.species]["name"]), now_k.sp["color"])

func on_bond_ready(h: Hunter) -> void:
	if h != player:
		return
	sfx("bond", null, -3.0)
	fx.word(h.pos + Vector3(0, 2.3, 0), "BOND READY", Color("ffd23f"), true)
	var ud := Ultimate.def_for(h.kin) if h.kin else null
	if hud and ud:
		hud.toast("Bond full!  %s: %s" % [Settings.key_cap("ultimate"), ud.display_name], Color("ffd23f"))

func on_ult(h: Hunter, k: Kin, u: UltimateDef) -> void:
	kstat["ult"] += 1
	sfx("ult", h.pos, 0.0)
	shake(0.55, h.pos)
	fx.word((k.pos if u.form == "giant" else h.pos) + Vector3(0, 2.4, 0), u.display_name.to_upper(), u.color, true)
	if h.team != (player.team if player else -1) and player and h.flat_dist(player) < 22.0:
		add_feed("%s's %s used %s" % [h.pname, k.rec.get("name", "kin"), u.display_name])
	if h == player:
		player.add_stat("ults")
		_slow(0.35, 0.4)
		cam.punch(0.14)
		if hud:
			hud.flash(u.color, 0.25)

func on_combo(target: Ent, own: Node, c: Dictionary) -> void:
	kstat["combo"] += 1
	var col := Color(String(c.get("color", "#ffd23f")))
	fx.word(target.pos + Vector3(0, 1.9, 0), String(c.get("label", "COMBO")), col, true)
	fx.ring(target.pos, 1.3, col, 0.3)
	sfx("combo", target.pos, -2.0)
	if own == player:
		player.add_stat("combos")
		if hud and int(player.stats.get("combos", 0)) == 1:
			hud.toast("%s!  %s" % [String(c.get("name", "Combo")), String(c.get("desc", ""))], col)

# ------------------------------------------------------------------ lost kin
## A rival holding one of your lost kin turns up in some expeditions (one per match at most).
func _held_for_match(team_i: int) -> Dictionary:
	if opts.get("training", false) or opts.get("tutorial", false) or team_i == 0 or not tracked.is_empty() or net_on:
		return {}
	for L in Save.d.get("lost_kin", []):
		if String(L.get("where", "")) == "rival" and rng.randf() < 0.5:
			return {"holder": String(L["holder"]), "rec": L["rec"]}
	return {}

## Your bond lets you feel where a lost kin is: a ping now and then while a rival here carries it.
func _update_tracking(dt: float) -> void:
	if tracked.is_empty() or player == null or player.out:
		return
	track_t -= dt
	if track_t > 0.0:
		return
	track_t = 22.0
	for tr in tracked:
		var k: Kin = tr["kin"]
		var h: Hunter = tr["holder"]
		if k.dead or h.out:
			continue
		var at: Vector3 = k.pos if k.state != "bench" else h.pos
		ping(at, Color("ffd23f"))
		note_sound(null, at, "kin")
		add_feed("You sense %s %s. %s has it." % [k.rec.get("name", "your kin"), direction_word(player.pos, at), h.pname])

## Kin left behind where a hunter went down. They wait, dazed, for someone to collect them.
func _leave_kin(h: Hunter) -> void:
	for kk in [h.kin, h.kin2]:
		if kk == null:
			continue
		_leave_one_kin(h, kk)

## One kin left behind where it was, dazed, for anyone to capture.
func _leave_one_kin(h: Hunter, k: Kin) -> void:
	if true:
		giant_free(k)
		var at: Vector3 = k.pos if k.state in ["active", "fainted", "returning", "reviving"] else h.pos
		var bx := Life.box_of(self, h)
		if k.state == "away" and not bx.is_empty() and bx["pos"] != Vector3.INF:
			at = bx["pos"]
		var leave: bool = not h.remote and not opts.get("training", false) and not opts.get("tutorial", false)
		if leave:
			if world.is_void(at.x, at.z):
				# it flutters to the nearest solid ground
				at = world.free_spot_near(at, [], 1.0, 0.4, 40.0)
			if not world.is_void(at.x, at.z):
				var rec: Dictionary = k.rec.duplicate(true)
				var w := spawn_wild(rec, at + Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6)), true)
				# whose it really is: yours (even if a rival was carrying it), or the hunter who brought it
				w.lost_from = "you" if (h == player or k.lost_from == "you") else h.pname
				w.lost_uid = String(rec.get("uid", ""))
				w.lost_owner = h
				w.dazed_t = 1e9
				kstat["left"] += 1
				if h == player:
					player_lost.append({"uid": w.lost_uid, "kin": w, "holder": null, "rec": rec})
					add_feed("%s was left behind" % rec.get("name", "Your kin"))
				elif k.lost_from == "you" and player and not player.out:
					add_feed("%s dropped %s! Catch it and extract to bring it home." % [h.pname, rec.get("name", "your kin")])
					ping(w.pos, Color("ffd23f"))
		k.dead = true
		k.visible = false

func giant_free(k: Kin) -> bool:
	if not k.giant.is_empty(): k._shrink()
	if k.state == "fused": k._unfuse()
	return true

## Gives a hunter one of their kin back (out of a deathbox, or caught back up): it hops on your
## shoulder, or onto the bench if you already have one out.
func give_kin(h: Hunter, rec: Dictionary) -> Kin:
	var k := Kin.new()
	k.init_kin(self, next_id(h.nid + "k"), rec["species"], rec, h)
	add_child(k)
	k.teleport(h.pos + Vector3(0, 1.5, 0))
	kins.append(k)
	ents_by_id[k.nid] = k
	if h.kin == null or (h.kin as Kin).dead:
		h.kin = k
	else:
		h.kin2 = k
		k.bench()
	for L in player_lost.duplicate():
		if String(L["uid"]) == String(rec.get("uid", "")):
			player_lost.erase(L)
	return k

## A rival just took one of your kin: they're marked, and you're faster running them down.
func kin_stolen(thief: Hunter, rec: Dictionary) -> void:
	if player == null:
		return
	player.chase = thief
	ping(thief.pos, Color("ffd23f"))
	if hud:
		hud.toast("%s took %s! Chase them down: they're marked, and you're faster heading their way" % [thief.pname, rec.get("name", "your kin")], Color("ffd23f"))

## Who has one of your kin right now (a rival still in the match), or null.
func kin_thief() -> Hunter:
	for L in player_lost:
		var hh = L.get("holder")
		if hh is Hunter and (hh as Hunter).team != player.team and not (hh as Hunter).out and not (hh as Hunter).extracted:
			return hh
	return null

func _tick_chase() -> void:
	if player == null:
		return
	var th := kin_thief()
	player.chase = th
	if th:
		# the thief can't hide: always visible, and pinged on the map every few seconds
		th.reveal_t = maxf(th.reveal_t, 0.5)
		if int(time * 60.0) % 240 == 0:
			pings.append({"pos": th.pos, "col": Color("ffd23f"), "t": 0.0})

## Where each of your lost kin ends up when the match is over.
func _resolve_lost() -> Array:
	var out: Array = []
	for L in player_lost:
		var w: Kin = L["kin"]
		var holder = L.get("holder")
		if w == null:
			# still in your deathbox (nobody looted it): it ends up at the Ransom House
			var fate0 := "ransom"; var who0 := ""
			if holder is Hunter:
				var hh0: Hunter = holder
				if hh0 == player: fate0 = "self"
				elif hh0.team == player.team: fate0 = "squad" if not hh0.out else "ransom"; who0 = hh0.pname
				elif not hh0.out: fate0 = "rival"; who0 = hh0.pname
			out.append({"uid": L["uid"], "fate": fate0, "holder": who0, "rec": L["rec"]})
			continue
		var fate := "ransom"
		var who := ""
		if holder is Hunter:
			var hh: Hunter = holder
			if hh == player:
				fate = "self"
			elif hh.team == player.team:
				fate = "squad" if not hh.out else "ransom"
				who = hh.pname
			elif not hh.out:
				fate = "rival"; who = hh.pname
		elif not w.dead:
			# nobody grabbed it before the match ended for you: maybe someone close by will
			var best: Hunter = null; var bd := 26.0
			for o in hunters:
				if o.out or o == player: continue
				var d: float = o.flat_dist(w)
				if d < bd: bd = d; best = o
			if best and rng.randf() < 0.75 * (1.0 - bd / 26.0) + 0.15:
				if best.team == player.team:
					fate = "squad"
				else:
					fate = "rival"
				who = best.pname
		out.append({"uid": L["uid"], "fate": fate, "holder": who, "rec": L["rec"]})
	return out


func on_wild_dazed(k: Kin) -> void:
	if player and k.flat_dist(player) < 10.0:
		add_feed("The wild %s is dazed. Hold %s to catch it!" % [Data.KIN[k.species]["name"], Settings.key_cap("interact")])

## A monster's stagger window opened.
func on_stag_open(mb: Mob) -> void:
	if player and not player.out and player.flat_dist(mb) < 14.0:
		sfx("warn", mb.pos, -10.0, 1.5)
		_tip("stagger", "A purple ring means %s can be staggered. Hit it with an ability (%s, %s or %s) for a big hit, a long stun and your cooldown back." % [mb.md["name"], Settings.key_cap("signature"), Settings.key_cap("ultimate"), Settings.key_cap("gear1")])

## Someone landed an ability in a stagger window. Runs where the monster lives (the host online).
var stag_n := 0

func on_stagger(mb: Mob, by: Ent, ab: String) -> void:
	stag_n += 1
	var sc: Ent = (by as Kin).owner_h if by is Kin and (by as Kin).owner_h else by
	if sc is Hunter: (sc as Hunter).add_stat("staggers")
	fx.ring(mb.pos, mb.r + 1.8, Color("c47aff"), 0.4)
	fx.burst(mb.pos + Vector3(0, 1.0, 0), Color("e0b0ff"), 30, 6.0, 0.6, 2.0, 1.2)
	fx.flash(mb.pos + Vector3(0, 1.0, 0), Color("e0b0ff"), 1.4, 0.1)
	sfx("crit", mb.pos, 2.0, 0.7)
	sfx("boom", mb.pos, -4.0, 1.6)
	shake(0.45, mb.pos)
	freeze_frame(0.08)
	var hunter: Hunter = by as Hunter if by is Hunter else (by.owner_h if by is Kin else null)
	if net_on:
		net_event(["stg", mb.nid, hunter.nid if hunter else "", ab])
	_stagger_reward(mb, hunter, ab)

func _stagger_reward(mb: Mob, hunter: Hunter, ab: String) -> void:
	if hunter == null or hunter.remote:
		return
	if ab == "e":
		hunter.sig_cd = 0.0
	elif ab in ["kin", "k1", "k2"] and hunter.kin:
		(hunter.kin as Kin).runner.reset()
	if hunter == player:
		var what: String = {"e": "Cooldown back", "kin": (player.kin.rec.get("name", "Your kin") if player.kin else "Your kin") + "'s abilities are ready again"}.get("kin" if ab in ["k1", "k2"] else ab, "")
		hud.toast("Staggered %s!%s" % [mb.md["name"], ("  " + what) if what != "" else ""], Color("e0b0ff"))
		train["_stagger"] = true

## Someone's armor just shattered: a clear sound and burst so the attacker knows to push.
func on_armor_break(h: Hunter, by: Ent) -> void:
	fx.burst(h.pos + Vector3(0, 1.0, 0), Color("7ac8ff"), 22, 5.0, 0.5, 6.0, 1.0)
	fx.ring(h.pos, 1.4, Color("7ac8ff"), 0.3)
	sfx("shield", h.pos, 0.0, 1.6)
	var credit: Ent = by.owner_h if by is Kin and by.owner_h else by
	if credit == player and hud:
		hud.toast_small("ARMOR BROKEN", Color("7ac8ff"))
		hud.hitmarker(true, true)
	elif h == player and hud:
		hud.toast_small("Armor down", Color("7ac8ff"))

## Knocked into a wall: stunned for a moment, which is the whole point of knockback near walls.
func on_wall_slam(e: Ent, st: float) -> void:
	fx.burst(e.pos + Vector3(0, 0.9, 0), Color("e6dccb"), 16, 4.0, 0.4)
	fx.ring(e.pos, 1.2, Color("fff27a"), 0.3)
	sfx("knock", e.pos, -2.0, 1.2)
	shake(0.35, e.pos)
	var sc: Ent = e.last_hit_by
	if sc is Kin and (sc as Kin).owner_h: sc = (sc as Kin).owner_h
	if sc is Hunter and sc != e: (sc as Hunter).add_stat("slams")
	if e == player and hud: hud.toast_small("WALL SLAM", Color("fff27a"))
	elif player and e.last_hit_by == player and hud: hud.toast_small("WALL SLAM  ·  stunned %.1fs" % st, Color("fff27a"))

## Sight. Each hunter sees a cone in front of them (where they aim) out to VIEW_RANGE, plus a
## small circle all around; a team shares what its members see. Walls and high ground block
## sight, tall grass hides you from anyone outside it, and crouching shrinks both distances.
## Firing or getting hit gives you away to anyone with a clear line, whichever way they face.
const VIEW_RANGE := 24.0
const VIEW_COS := 0.6          # about 106 degrees wide
const NEAR_SENSE := 3.2

func can_see(team_i: int, target: Hunter) -> bool:
	if target.team == team_i or target.downed:
		return true
	return sees(team_i, target.pos, target.crouch, target.reveal_t > 0.0)

func sees(team_i: int, p: Vector3, crouched := false, revealed := false) -> bool:
	var in_grass := world.in_bush(p.x, p.z) or in_smoke(p)
	var near := 1.6 if crouched else NEAR_SENSE
	var rng := VIEW_RANGE + 2.0 if revealed else (14.0 if crouched else VIEW_RANGE)
	for h in hunters:
		if h.team != team_i or h.out or h.extracted or h.riding:
			continue
		var rel := Vector2(p.x - h.pos.x, p.z - h.pos.z)
		var d := rel.length()
		if d < near:
			return true
		# sneaking (Ctrl) slows you but lets you see further, as in Supervive
		if d > rng * (1.25 if h.crouch else 1.0) or (in_grass and not revealed):
			continue
		if not revealed and rel.normalized().dot(h.aim_dir()) < VIEW_COS:
			continue
		if world.los(h.pos, p, h.pos.y + 1.1) or world.los(h.pos, p + Vector3(0, 0.6, 0), h.pos.y + 1.6):
			return true
	return false

var _vis_t := 0.0
var crouch_on := false
var _perk_keys_down := {}
var _vis_tex_done := false
func _update_vision() -> void:
	# the dimming outside your view cone, drawn by the toon shaders
	var looking := player != null and not player.out and not player.extracted and not player.dropping and not player.riding
	if looking and not _vis_tex_done:
		_vis_tex_done = true
		RenderingServer.global_shader_parameter_set("vis_blocks", world.vis_texture())
		RenderingServer.global_shader_parameter_set("vis_size", Vector2(world.w, world.h))
	RenderingServer.global_shader_parameter_set("vis_on", 1.0 if looking else 0.0)
	if looking:
		RenderingServer.global_shader_parameter_set("vis_focus", player.model.global_position if player.model else player.pos)
		RenderingServer.global_shader_parameter_set("vis_dir", player.aim_dir())
		RenderingServer.global_shader_parameter_set("vis_range", (14.0 if player.crouch else VIEW_RANGE) * (1.25 if player.crouch else 1.0))
		# teammates light up what they see too (up to three)
		var n := 0
		for h in hunters:
			if n >= 3: break
			if h == player or h.team != player.team or h.out or h.extracted or h.riding or h.dropping:
				continue
			var ad: Vector2 = h.aim_dir()
			RenderingServer.global_shader_parameter_set("vis_ally%d" % n, Vector4(h.pos.x, h.pos.z, ad.x, ad.y))
			n += 1
		RenderingServer.global_shader_parameter_set("vis_allies", float(n))
	_vis_t -= get_process_delta_time()
	if _vis_t > 0.0:
		return
	_vis_t = 0.05
	for h in hunters:
		h.unseen = looking and h != player and not can_see(player.team, h)
	for k in kins:
		var o: Hunter = k.owner_h
		k.unseen = looking and o != null and o.team != player.team and k.state != "shoulder" and not sees(player.team, k.pos)

func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set("vis_on", 0.0)
	if biomes: biomes.free_up()
	if duel:
		duel.teardown()
	if _bond_cb.is_valid() and CombatBus.hit_landed.is_connected(_bond_cb):
		CombatBus.hit_landed.disconnect(_bond_cb)
	if _combo_cb.is_valid() and CombatBus.status_applied.is_connected(_combo_cb):
		CombatBus.status_applied.disconnect(_combo_cb)

func on_perfect_dodge(h: Hunter) -> void:
	fx.ring(h.pos, 1.3, Color("9af0ff"), 0.3)
	fx.burst(h.pos + Vector3(0, 0.9, 0), Color("cff6ff"), 12, 3.5, 0.4)
	sfx("dash", h.pos, -2.0, 1.4)
	if h == player:
		_slow(0.25, 0.4)
		hud.toast("Perfect dodge!  Next shots crit", Color("9af0ff"))

## Catching a ledge just happens, the way Supervive pulls you up a lip: no message, just a
## quick pull-up with a puff and a grab sound.
func on_ledge_grab(_h: Hunter) -> void:
	pass

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
		"armor": n = Models.armor_shard()
		"key": n = ExitModels.rift_key()
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
		if skytrain:
			var dk := skytrain.deck_y(pos, 0.6)
			if dk > World.VOID + 1.0 and (g < dk or g > pos.y + 0.9): g = dk
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
		"gem": h.gems += int(round(float(p["v"]) * (1.0 + 0.25 * h.perk_n("scavenger"))))
		"seed": h.seeds[p["key"]] = int(h.seeds.get(p["key"], 0)) + int(p["v"])
		"tonic":
			h.tonics = mini(5, h.tonics + 1)
			if h == player: hud.toast("+1 tonic", Color("8ff0a0"))
		"armor":
			h.armor_kits = mini(3, h.armor_kits + 1)
			if h == player: hud.toast_small("+1 armor kit", Color("dfe9f7"))
		"key":
			h.rift_keys += 1
			if h == player:
				hud.toast("+1 Rift Key: opens any rift hatch, quietly, any time", ExitModels.HATCH)
				sfx("unlock", null, -6.0, 1.2)
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
	if mi and extra.get("melee", false):
		mi = null          # a melee strike is invisible; the swing has its own effect
	if mi:
		mi.visible = true
		# readability: what can hurt you is the brightest, hottest thing on screen; your own and your
		# team's shots are smaller and dimmer so they never hide an incoming one
		var vis_col := col
		var vis_size := size * 2.0
		if player and by.team != player.team:
			vis_col = col.lerp(Color("ff5a3a"), 0.35)
			vis_col.a = 1.0
			vis_size *= 1.3
		elif player:
			vis_col = Color(col, 0.5)
			vis_size *= 0.85
		mi.material_override.set_shader_parameter("color", vis_col)
		mi.scale = Vector3.ONE * vis_size
		mi.global_position = at
	if not extra.has("dy") and not extra.get("mob", false) and not extra.get("cos", false) and not extra.get("melee", false):
		var src: Hunter = by as Hunter if by is Hunter else ((by as Kin).owner_h as Hunter if by is Kin and (by as Kin).owner_h else null)
		if src and src.inp.has("aim_y"):
			var dyv: float = float(src.inp["aim_y"]) - src.pos.y
			if absf(dyv) > 0.3 and absf(dyv) <= AIM_DY_MAX:
				var aimp: Vector3 = src.inp["aim"]
				extra = extra.duplicate()
				extra["dy"] = dyv
				extra["dyd"] = maxf(1.0, Vector2(aimp.x - at.x, aimp.z - at.z).length())
				extra["y0"] = at.y
				extra["gmax"] = maxf(src.pos.y, float(src.inp["aim_y"]))
	var team := by.team
	if duel and not extra.get("cos", false):
		duel.note_shot(by)
	shot_n += 1
	var sd := {"sid": shot_n, "pos": at, "vel": v2, "dmg": dmg, "team": team, "by": by, "life": life, "life0": life, "r": size, "col": col, "x": extra, "node": mi, "prev": at, "start": at}
	if extra.has("deco") or extra.get("rope", false):
		sd["deco"] = _make_deco(String(extra.get("deco", "")), col, size, extra.get("rope", false))
	shots.append(sd)
	if net_on and not extra.get("cos", false) and not extra.get("melee", false) and not by.remote:
		net_event(["s", _r(at.x), _r(at.y), _r(at.z), _r(v2.x), _r(v2.y), snappedf(life, 0.01), snappedf(size, 0.01), col.to_html(false), float(extra.get("boom", 0.0)), team, 1 if extra.get("mob", false) else 0])
	if by is Hunter and not extra.get("melee", false):
		fx.flash(at, col.lightened(0.4), 0.22, 0.05)
		note_sound(by, at, "shot")

func _update_shots(dt: float) -> void:
	for s in shots.duplicate():
		s["life"] -= dt
		var p: Vector3 = s["pos"]
		s["prev"] = p
		var v: Vector2 = s["vel"]
		var sx0: Dictionary = s["x"]
		if sx0.has("decel"):
			# slugs slow down and stop
			var sp0 := v.length()
			var sp1 := maxf(0.0, sp0 - float(sx0["decel"]) * dt)
			if sp1 <= 0.5:
				_shot_end(s, p, null)
				continue
			v = v * (sp1 / sp0)
			s["vel"] = v
		var step := Vector3(v.x, 0, v.y) * dt
		var n := int(ceil(step.length() / 0.25))
		var hit := false
		var sx: Dictionary = s["x"]
		for i in n:
			p += step / n
			if sx.has("lob"):
				var tr0 := Vector2(p.x - (s["start"] as Vector3).x, p.z - (s["start"] as Vector3).z).length()
				var tot := float(s["life0"]) * (s["vel"] as Vector2).length()
				p.y = (s["start"] as Vector3).y + sin(clampf(tr0 / maxf(0.1, tot), 0.0, 1.0) * PI) * float(sx["lob"])
			elif sx.has("dy"):
				# climbing or dipping toward the height you aimed at
				var trav := Vector2(p.x - (s["start"] as Vector3).x, p.z - (s["start"] as Vector3).z).length()
				p.y = float(sx["y0"]) + float(sx["dy"]) * clampf(trav / float(sx["dyd"]), 0.0, 1.0)
			# domes stop shots fired at them from outside
			if _dome_blocks(s, p):
				_shot_end(s, p, null)
				hit = true; break
			# terrain and rocks
			var gp := world.ground_at(p.x, p.z)
			var over_ok: bool = sx.has("dy") and gp <= float(sx["gmax"]) + 0.05
			if world.is_block(p.x, p.z) and gp + World.BLOCK_H > p.y or (gp > p.y and not over_ok):
				if int(sx.get("bounce", 0)) > 0:
					# ricochet: flip whichever way took it into the wall and keep going
					var back := p - step / n
					var bv: Vector2 = s["vel"]
					var gx := world.ground_at(p.x, back.z)
					if (world.is_block(p.x, back.z) and gx + World.BLOCK_H > p.y) or gx > p.y: bv.x = -bv.x
					else: bv.y = -bv.y
					s["vel"] = bv
					sx["bounce"] = int(sx["bounce"]) - 1
					if sx.has("hitset"): sx["hitset"] = {}
					fx.burst(back, s["col"], 6, 3.0, 0.2, 2.0)
					sfx("click", back, -6.0, 1.6)
					p = back
					s["pos"] = p
					hit = true; break
				_shot_end(s, p, null, "wall")
				hit = true; break
			var vr: String = verbs.shot_check(s, p) if verbs else ""
			if vr == "end":
				_shot_end(s, p, null, "wall")
				hit = true; break
			elif vr == "bounce":
				p = s["pos"]
				hit = true; break
			var bh := _shot_break(s, p)
			if not bh.is_empty():
				if not s["x"].get("cos", false) and not s["x"].has("boom") and not s["x"].get("mob", false):
					hit_break(bh, float(s["dmg"]), s["by"])
				_shot_end(s, p, null)
				hit = true; break
			for e in _shot_targets(s):
				if Vector2(e.pos.x - p.x, e.pos.z - p.z).length() < e.r + s["r"] + 0.08 and shot_height_ok(e, p.y):
					if sx.has("hitset"):
						# piercing / boomerang shots hit each thing once per pass and fly on
						var key: int = e.get_instance_id()
						if (sx["hitset"] as Dictionary).has(key):
							continue
						sx["hitset"][key] = true
						_shot_hit(s, p, e)
						if not sx.get("pierce", false) and not sx.get("return", false):
							_shot_end(s, p, e, "hit")
							hit = true; break
						continue
					_shot_end(s, p, e, "hit")
					hit = true; break
			if hit:
				break
		if hit:
			continue
		s["pos"] = p
		if sx.get("return", false) and is_instance_valid(s["by"]):
			if sx.get("back", false):
				# a boomerang homes back on whoever threw it and is caught there
				var by: Ent = s["by"]
				var to := Vector2(by.pos.x - p.x, by.pos.z - p.z)
				if to.length() < 0.9:
					_shot_end(s, p, null, "caught")
					continue
				s["vel"] = to.normalized() * (s["vel"] as Vector2).length()
				var pp: Vector3 = s["pos"]
				pp.y = lerpf(p.y, by.pos.y + 0.95, 0.2)
				s["pos"] = pp
			elif s["life"] <= 0.0:
				sx["back"] = true
				sx["hitset"] = {}
				s["life"] = float(s["life0"]) * 1.6
				sfx("whoosh", p, -6.0, 1.5)
				continue
		if s["life"] <= 0.0:
			_shot_end(s, p, null, "expire")

## Shots fly level, so a target one terrace above or below still gets hit. Two terraces up and the
## shot goes under them into the cliff; two down and it sails over their head.
func shot_height_ok(e: Ent, y: float) -> bool:
	var top: float = 1.5 if e is Hunter else maxf(0.9, e.r * 2.2)
	var fy := e.hit_y()
	# someone hopping is still standing on their terrace, as far as shots are concerned
	var g := e.ground()
	if g > World.VOID + 1.0 and fy > g:
		fy = maxf(g, fy - 1.2)
	return y > fy - 0.45 and y < fy + top + 0.9

func _shot_break(s: Dictionary, p: Vector3) -> Dictionary:
	for b in breaks:
		if not b["dead"] and absf(p.y - (float(b["pos"].y) + 0.4)) < 0.75 and Vector2(b["pos"].x - p.x, b["pos"].z - p.z).length() < 0.36 + float(s["r"]):
			return b
	return {}

func _shot_targets(s: Dictionary) -> Array:
	var x: Dictionary = s["x"]
	var out: Array = []
	if x.has("lob"):
		return out       # a lobbed shell sails over everyone and comes down where it was aimed
	if x.get("cos", false):
		# a remote shooter's bullet stops on whatever it visibly hits; the owner reports the damage
		for h in hunters:
			if h.team != s["team"] and h.hittable(): out.append(h)
		for mb in mobs:
			if not mb.dead and not x.get("mob", false): out.append(mb)
		return out
	if x.get("mob", false):
		for h in hunters:
			if h.hittable() and not h.downed and h.phase_t <= 0.0: out.append(h)
		for k in kins:
			if not k.is_wild() and k.hittable(): out.append(k)
		return out
	for h in hunters:
		if h.team != s["team"] and h.hittable() and h.phase_t <= 0.0: out.append(h)
	for k in kins:
		if k.team != s["team"] and k.hittable(): out.append(k)
	for mb in mobs:
		if not mb.dead: out.append(mb)
	return out

func _shot_end(s: Dictionary, at: Vector3, e: Ent, why := "") -> void:
	shots.erase(s)
	if s.has("deco") and is_instance_valid(s["deco"]):
		(s["deco"] as Node3D).queue_free()
	# data-driven abilities: effects that go off where the shot ends, on what it hit, or on the wall
	# that stopped it
	var fxx: Dictionary = s["x"]
	if not fxx.get("cos", false) and is_instance_valid(s["by"]) and not s["by"].dead:
		var c2: Dictionary = (fxx.get("fx_ctx", {}) as Dictionary).duplicate()
		c2["at"] = at
		c2["end"] = why
		c2["dir"] = (s["vel"] as Vector2).normalized()
		if e: c2["target"] = e
		if e and fxx.has("fx_hit"):
			Effects.run(fxx["fx_hit"], s["by"], c2)
		if why == "wall" and fxx.has("fx_wall"):
			Effects.run(fxx["fx_wall"], s["by"], c2)
		if fxx.has("fx_end"):
			Effects.run(fxx["fx_end"], s["by"], c2)
	if s["node"]:
		s["node"].visible = false
	if fxx.has("hitset"):
		if e == null: fx.burst(at, s["col"], 5, 2.0, 0.25, 6.0, 0.6)
		return        # piercing shots already dealt their hits on the way
	_shot_apply(s, at, e)

## A piercing or boomerang shot passing through something: its on-hit effects and damage, then on.
func _shot_hit(s: Dictionary, at: Vector3, e: Ent) -> void:
	var fxx: Dictionary = s["x"]
	if not fxx.get("cos", false) and is_instance_valid(s["by"]) and fxx.has("fx_hit"):
		var c2: Dictionary = (fxx.get("fx_ctx", {}) as Dictionary).duplicate()
		c2["at"] = at; c2["target"] = e; c2["end"] = "hit"
		Effects.run(fxx["fx_hit"], s["by"], c2)
	_shot_apply(s, at, e)

func _shot_apply(s: Dictionary, at: Vector3, e: Ent) -> void:
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
	if x.has("swing"):
		# one swing hits each thing once, however many of its strikes reach it
		var key := "%s|%s" % [x["swing"], e.nid if e.nid != "" else str(e.get_instance_id())]
		if swing_hits.has(key):
			return
		swing_hits[key] = time
		if swing_hits.size() > 200:
			swing_hits.clear()
		fx.burst(at + Vector3(0, 0.3, 0), s["col"], 8, 3.5, 0.25, 4.0)
		sfx("hit", at, -4.0, 0.8)
	var crit := false
	if e.stun_t > 0.0 and not x.get("mob", false):
		dmg *= 1.5
		crit = true
	if x.get("crit", false) and not crit:
		dmg *= 1.5
		crit = true
	var trav := Vector2(at.x - s["start"].x, at.z - s["start"].z).length()
	if x.has("far") and trav > float(x["far"]):
		dmg *= 1.25
	if x.has("near"):
		# a sniper round needs room: half damage point-blank, full from half its range
		dmg *= lerpf(float(x["near"][0]), 1.0, clampf(trav / maxf(0.1, float(x["near"][1])), 0.0, 1.0))
	if x.has("farf") and trav > float(x["farf"][0]):
		dmg *= lerpf(1.0, float(x["farf"][1]), clampf((trav - float(x["farf"][0])) / maxf(0.1, float(x["farf"][2]) - float(x["farf"][0])), 0.0, 1.0))
	if x.has("tip") and trav + 0.25 >= float(x["tip"][0]):
		# the blade's sweet spot
		dmg *= 1.0 + float(x["tip"][1])
		fx.burst(at + Vector3(0, 0.4, 0), Color("fff6c0"), 10, 4.5, 0.3, 4.0)
	if x.has("pg"):
		# a shotgun volley: the first slug on someone does a fixed share of the whole volley,
		# the rest split what's left, so landing every slug still adds up to the full volley
		var pk := "%s|%s" % [x["pg"], e.nid if e.nid != "" else str(e.get_instance_id())]
		var n: int = int(pellet_hits.get(pk, 0))
		pellet_hits[pk] = n + 1
		if pellet_hits.size() > 300:
			pellet_hits.clear()
		var total: float = dmg * float(x["pn"])
		dmg = total * float(x["pf"]) if n == 0 else total * (1.0 - float(x["pf"])) / maxf(1.0, float(x["pn"]) - 1.0)
	var dir: Vector2 = (s["vel"] as Vector2).normalized()
	var o := {"src": "shot", "crit": crit}
	if float(x.get("kb", 0.0)) > 0.0:
		o["kb"] = dir * float(x["kb"])
	if x.has("burn"): o["burn"] = x["burn"]
	if x.has("slow"): o["slow"] = x["slow"]
	if x.has("root"): o["root"] = x["root"]
	if x.has("stun"): o["stun"] = x["stun"]
	if x.has("leech"): o["leech"] = x["leech"]
	if x.has("kbi"): o["kbi"] = x["kbi"]
	if x.has("blight"): o["blight"] = x["blight"]
	if x.has("wallstun"): o["wallstun"] = x["wallstun"]
	if x.has("ab"): o["ab"] = x["ab"]
	if x.get("hook", false) and by:
		# drag it back toward whoever threw the hook
		var back := Vector2(by.pos.x - e.pos.x, by.pos.z - e.pos.z)
		o["kb"] = back.normalized() * clampf(back.length() * 2.2, 6.0, 15.0)
		o["lift"] = 3.0
		o["slow"] = 2.0
		fx.bolt(by.pos + Vector3(0, 0.95, 0), e.pos + Vector3(0, 0.8, 0), Color("e0b05a"))
		net_fx(["bolt", _r(by.pos.x), _r(by.pos.y + 0.95), _r(by.pos.z), _r(e.pos.x), _r(e.pos.y + 0.8), _r(e.pos.z), "e0b05a"])
	if x.get("bolas", false):
		# a second foe close by gets tangled too, and both are stunned
		for f in foes_of(int(s["team"])):
			if f != e and f.flat_dist(e) < 2.2 and absf(f.pos.y - e.pos.y) < 1.5:
				o["stun"] = 1.0
				f.hurt(dmg, by, o.duplicate())
				fx.bolt(e.pos + Vector3(0, 0.8, 0), f.pos + Vector3(0, 0.8, 0), Color("d8c9b0"))
				break
	e.hurt(dmg, by, o)
	if x.get("blinkto", false) and by is Hunter and not by.remote and not by.downed:
		# Shadow Knife: appear behind whoever it hit
		var back := Vector2(e.pos.x - by.pos.x, e.pos.z - by.pos.z).normalized()
		var to := Vector3(e.pos.x + back.x * 1.1, 0, e.pos.z + back.y * 1.1)
		if not world.is_void(to.x, to.z) and not world.is_block(to.x, to.z):
			fx.ghost(by.position, by.face, (by as Hunter).accent(), float((by as Hunter).cdat["scale"]))
			by.teleport(Vector3(to.x, world.ground_at(to.x, to.z), to.z))
			by.vel = Vector3.ZERO
			(by as Hunter).crit_t = maxf((by as Hunter).crit_t, 1.5)
			sfx("cloak", by.pos, -2.0, 1.6)

## Shapes that ride on top of an ability's shot so it reads as what it is: a spinning disc, a hook
## with its rope back to the thrower, a glowing orb.
func _make_deco(kind_s: String, col: Color, size: float, rope: bool) -> Node3D:
	var n := Node3D.new()
	n.top_level = true
	match kind_s:
		"disc":
			var d := Models.part(n, Models.cyl(size * 2.6, size * 2.6, 0.06, 18), Models.toon(col, true, 0.9), Vector3.ZERO)
			d.name = "Spin"
			Models.part(d, Models.box(size * 5.0, 0.08, 0.1), Models.glow_mat(Color(col.lightened(0.5), 0.9)), Vector3.ZERO)
		"hook":
			var hk := Models.part(n, Models.box(0.12, 0.12, 0.5), Models.toon(Color("d8c9a8"), true, 0.4), Vector3.ZERO)
			hk.name = "Spin"
			for sx in [-1.0, 1.0]:
				Models.part(hk, Models.box(0.08, 0.08, 0.32), Models.toon(col, true, 0.8), Vector3(sx * 0.12, 0, -0.22), Vector3.ONE, Vector3(0, sx * 0.7, 0))
		"orb":
			var o := Models.part(n, Models.sphere(size * 1.6, 12), Models.glow_mat(Color(col, 0.75)), Vector3.ZERO)
			o.name = "Spin"
			Models.part(n, Models.sphere(size * 2.6, 12), Models.glow_mat(Color(col, 0.18)), Vector3.ZERO)
	if rope:
		var r := MeshInstance3D.new()
		r.mesh = Models.box(0.05, 0.05, 1.0)
		r.material_override = Models.glow_mat(Color(col.lightened(0.2), 0.85))
		r.name = "Rope"
		r.top_level = true
		r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(r)
	add_child(n)
	return n

func _render_deco(s: Dictionary, alpha: float) -> void:
	var n: Node3D = s["deco"]
	if not is_instance_valid(n):
		return
	var at := (s["prev"] as Vector3).lerp(s["pos"], alpha)
	n.global_position = at
	var v: Vector2 = s["vel"]
	var sp := n.get_node_or_null("Spin") as Node3D
	if sp:
		if String((s["x"] as Dictionary).get("deco", "")) == "disc":
			sp.rotation.y = time * 22.0
		elif v.length() > 0.5:
			sp.rotation.y = atan2(-v.x, -v.y)
	var rope := n.get_node_or_null("Rope") as MeshInstance3D
	var by = s["by"]
	if rope and is_instance_valid(by) and by is Node3D:
		var a: Vector3 = (by as Node3D).position + Vector3(0, 0.95 if by is Hunter else 0.5, 0)
		if a.distance_to(at) > 0.1:
			rope.global_position = (a + at) * 0.5
			rope.look_at(at, Vector3.UP if absf((at - a).normalized().y) < 0.95 else Vector3.RIGHT)
			rope.scale = Vector3(1, 1, a.distance_to(at))

func _boom(s: Dictionary, at: Vector3) -> void:
	var x: Dictionary = s["x"]
	var radius: float = x["boom"]
	fx.ring(at, radius, Color("ffb070"), 0.3)
	fx.burst(at, Color("ffb070"), 26, 6.0, 0.5, 6.0, 1.3)
	var small: bool = x.get("boom_small", false)
	fx.flash(at, Color("ffd9a0"), radius * 0.45, 0.08)
	sfx("boom", at, 0.0 if not small else -9.0, 1.0 if not small else 1.5)
	shake(0.45 if not small else 0.08, at)
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
			var o := {"src": "boom", "kb": dir * float(x.get("boom_kb", 8.0)) * f, "lift": (7.0 if not small else 1.5) * f}
			if x.has("ab"): o["ab"] = x["ab"]
			if x.has("burn"): o["burn"] = x["burn"]
			if x.has("slow"): o["slow"] = x["slow"]
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
	_update_vision()
	if world.wall_mat:
		var fp := player.model.global_position + Vector3(0, 0.8, 0) if player and player.model and not player.out else Vector3(0, -999, 0)
		world.wall_mat.set_shader_parameter("focus", fp)
	for e in hunters: e.render(delta, alpha)
	for e in kins:
		e.render(delta, alpha)
		if e.unseen or (e.owner_h and (e.owner_h as Hunter).unseen and e.state == "shoulder"):
			e.visible = false
	for e in mobs: e.render(delta, alpha)
	if verbs: verbs.render(alpha)
	for s in shots:
		if s.has("deco"):
			_render_deco(s, alpha)
		if s["node"]:
			var mi: MeshInstance3D = s["node"]
			mi.global_position = (s["prev"] as Vector3).lerp(s["pos"], alpha)
			var v: Vector2 = s["vel"]
			if v.length() > 1.0:
				mi.look_at(mi.global_position + Vector3(v.x, 0, v.y), Vector3.UP)
				var r: float = s["r"]
				mi.scale = Vector3(r * 2.0, r * 2.0, r * 2.0 + v.length() * 0.025)
	cam.follow_mode = String(Settings.get_v("cam_follow"))
	var sty := String(Settings.get_v("cam_style"))
	if sty != cam_style:
		cam_style = sty
		cam.use_style(sty)
	if player and player.riding:
		# aboard the skyship: a low view from just behind and above it, looking ahead along its
		# course over the islands, like riding the bus in a battle royale
		var sd: Vector3 = ship.get("dir", Vector3.FORWARD)
		cam.yaw_to = atan2(-sd.x, -sd.z)
		cam.chase_to = 1.0
		cam.top_to = 0.0
		cam.zoom_to = 56.0 / cam.dist
		if time < 0.5:
			# boarding: start already behind the ship rather than swinging through it
			cam.chase = 1.0; cam.yaw = cam.yaw_to; cam.zoom = cam.zoom_to
		var fp := ship_pos() + sd * 27.0
		cam.follow(Vector3(fp.x, (SHIP_Y - 11.0) / 0.6, fp.z), delta, false)
	elif player and not player.out and not player.downed:
		cam.chase_to = 0.0
		cam.yaw_to = 0.0
		if player.dropping:
			# the drop: looking down over your shoulder, pulled back while you're high up
			var gy: float = world.ground_at(player.pos.x, player.pos.z) if not world.is_void(player.pos.x, player.pos.z) else 0.0
			var hk := clampf((player.pos.y - gy) / SHIP_Y, 0.0, 1.0)
			cam.zoom_to = lerpf(1.05, 1.7, hk)
			cam.top_to = clampf(hk * 0.7, 0.0, 0.6)
		else:
			# high in the air or out over the abyss the camera pulls back so you can see where you'll land
			# the camera only eases back while gliding, so jumps and falls never change the framing
			# sneaking (Ctrl) pulls the camera well back for a wide look around [Supervive]
			cam.zoom_to = 1.25 if player.gliding else (1.45 if player.crouch and player.grounded else 1.0)
			# high up, the camera pulls back with your altitude so you can still read the ground
			var alt := player_altitude()
			if alt > 4.0:
				cam.zoom_to *= 1.0 + clampf((alt - 4.0) / 24.0, 0.0, 0.7)
			cam.top_to = 0.0
		cam.follow(player.prev.lerp(player.pos, alpha), delta, not player.dropping)
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
		# dead and waiting on your team: after a moment, watch a teammate who's still in it
		var mate := spectating()
		if mate:
			foc = mate.prev.lerp(mate.pos, alpha)
			cam.zoom_to = 1.0
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
		if p["t"] > float(p.get("life", 4.0)): pings.erase(p)
	for f in feed.duplicate():
		f["t"] += delta
		if f["t"] > 6.0: feed.erase(f)

func _gather_input() -> void:
	if player == null or player.out or opts.get("tut_test", false):
		return       # (the tutorial test drives the player itself)
	var mv := Vector2(Input.get_axis("left", "right"), Input.get_axis("up", "down"))
	if mv.length() > 1.0:
		mv = mv.normalized()
	# the camera only turns during the skyship ride and the drop after it: keys stay screen-relative
	if absf(cam.yaw) > 0.001:
		mv = mv.rotated(-cam.yaw)
	player.inp["move"] = mv
	# dropping in without steering over the abyss: drift toward the nearest island so letting go
	# of the keys never drops you into the void
	if player.dropping and mv.length() < 0.1 and world.is_void(player.pos.x, player.pos.z):
		var best := Vector3.INF; var bd := 1e9
		for sp in world.spawns + world.portal_spots:
			var d := Vector2(sp.x - player.pos.x, sp.z - player.pos.z).length()
			if d < bd: bd = d; best = sp
		if best != Vector3.INF and bd > 0.8:
			player.inp["move"] = Vector2(best.x - player.pos.x, best.z - player.pos.z).normalized()
	player.inp["aim"] = _mouse_aim()
	player.inp["aim_y"] = aim_y      # the height of whatever you're pointing at (shots climb or dip to it)
	player.inp["fire"] = Input.is_action_pressed("fire") and not paused and not (hud and hud.mouse_on_ui())
	var map_up: bool = hud != null and hud.map_open()      # the map takes the mouse buttons
	if paused:
		player.inp["move"] = Vector2.ZERO
	player.inp["interact"] = Input.is_action_pressed("interact")
	if lairs and not lairs.puzzle_of(player).is_empty():
		var pad := Input.get_connected_joypads().size() > 0 and (Input.is_joy_button_pressed(0, JOY_BUTTON_A) or Input.is_joy_button_pressed(0, JOY_BUTTON_X))
		player.inp["interact"] = player.inp["interact"] or (player.inp["fire"] and not (hud and hud.mouse_on_ui())) or pad
		player.inp["fire"] = false
	# hold Space or Mouse 5 (Mouse 4 works too) in the air to glide; the mouse buttons never jump
	player.inp["glide"] = (Input.is_action_pressed("jump") or Input.is_action_pressed("glide")) and not paused
	player.inp["dash_hold"] = Input.is_action_pressed("dash") and bool(Settings.get_v("dash_hold"))
	var quick: bool = Settings.get_v("cast_on_press")
	player.inp["sec_hold"] = Input.is_action_pressed("secondary") and not paused
	# crouch: hold by default, or tap to toggle (the web version defaults to toggle, so you never
	# hold Ctrl while pressing W, which closes the browser tab)
	if Settings.get_v("crouch_toggle"):
		if Input.is_action_just_pressed("crouch") and not paused:
			crouch_on = not crouch_on
		if Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("dash"):
			crouch_on = false
	else:
		crouch_on = Input.is_action_pressed("crouch") and not paused
	player.inp["crouch"] = crouch_on
	if not perk_offer.is_empty() and not paused:
		for pi in 3:
			if Input.is_physical_key_pressed(KEY_1 + pi) and not _perk_keys_down.has(pi):
				_perk_keys_down[pi] = true
				choose_perk(pi)
			elif not Input.is_physical_key_pressed(KEY_1 + pi):
				_perk_keys_down.erase(pi)
	# the kit: Q glove, E kin ability, C throw kin, R bond, 1 heal (the second kin ability, kin swap
	# and the separate armor-kit key are retired)
	if Input.is_action_just_pressed("base") and not paused and duel == null:
		pending_input["base"] = true
	var slot_of := {"dash": "dash", "secondary": "sec", "gear1": "gear", "signature": "kin", "ultimate": "ult"}
	for a in [["dash", "dash"], ["jump", "jump"], ["signature", "sig"], ["reload", "reload"], ["tonic", "tonic"], ["throw", "throw"], ["ultimate", "ult"], ["secondary", "sec"], ["gear1", "gear1"]]:
		if a[0] == "tonic" and (not perk_offer.is_empty() or not _perk_keys_down.is_empty()):
			continue       # 1, 2 and 3 pick a perk while a choice is open
		if map_up and a[0] in ["secondary", "throw"]:
			continue       # right click takes your ping down while the map is up
		if a[0] == "secondary" and aim_hold != "" and aim_hold != "secondary" and Input.is_action_just_pressed("secondary"):
			aim_hold = ""          # right click while aiming something else cancels the cast
			continue
		if slot_of.has(a[0]) and player and Input.is_action_just_pressed(a[0]) and not paused:
			var sl: String = slot_of[a[0]]
			if Input.is_key_pressed(KEY_ALT) and player.can_level(sl) and int(player.slot_lv[sl]) > 0:
				player.level_slot(sl)       # Alt + key: put a point into it
				continue
			if int(player.slot_lv[sl]) == 0:
				pending_input[a[1]] = true      # locked: the press unlocks it if you have a point
				continue
		var aimable: bool = a[0] in ["signature", "ultimate", "gear1", "secondary"] and not quick
		if a[0] == "secondary" and player.runner and player.runner.def_of("utility") and not player.runner.def_of("utility").charge.is_empty():
			aimable = false       # a charge-up starts on the press and fires on the release
		if a[0] == "gear1" and (player.gear[0] as Dictionary).is_empty():
			aimable = false
		if aimable:
			# hold to see where it will land, let go to cast it
			if Input.is_action_just_pressed(a[0]) and not paused:
				aim_hold = a[0]
			if aim_hold == a[0] and not Input.is_action_pressed(a[0]):
				aim_hold = ""
				pending_input[a[1]] = true
			continue
		if Input.is_action_just_pressed(a[0]):
			pending_input[a[1]] = true

func _unhandled_input(event: InputEvent) -> void:
	if hud and hud.map_open() and (event.is_action_pressed("menu") or event.is_action_pressed("map")):
		hud.close_map()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("map") and hud and player and not over and not Overlay.is_open() and hud.map_allowed():
		hud.open_map(false)
		get_viewport().set_input_as_handled()
		return
	if skydrop and player and not player.out and not paused:
		if event.is_action_pressed("pass_lead") and skydrop.pass_lead(player):
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("separate") and skydrop.separate(player):
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("menu") and hud and (hud.swap_open() or hud.pack_open()):
		hud.close_swap(); hud.close_pack()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("menu") and not over and not result.get("ending", false) and not Overlay.is_open():
		Overlay.open_pause("match")
	elif event.is_action_pressed("inventory") and hud and player and not player.out and not opts.get("training", false):
		hud.toggle_pack()

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
	if skydrop and skydrop.planning:
		# planning the drop: the ship waits at the edge of the map and the match clock waits with it
		# (keys pressed meanwhile don't carry over: a Space now must not jump you off at the edge)
		for k in pending_input: pending_input[k] = false
		skydrop.tick_plan(dt)
		if String(opts.get("map_demo", "")) == "plan" and player and skydrop.clock > 1.2 and not has_meta("map_demo_done"):
			# test: your ping on a vault, beside the bots' picks
			set_meta("map_demo_done", true)
			var vs: Array = spawn_plan.active_of("vault") if spawn_plan else []
			squad_ping(player, vs[0]["pos"] if not vs.is_empty() else world.spawns[0])
		_update_ship(dt)
		if net_on:
			Net.tick(dt)
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
	if opts.get("life_demo", false) and player and time < 0.05 and not beacons.is_empty():
		# test: stand by a revive beacon with a teammate's deathbox next to it
		var bc: Vector3 = beacons[0]["pos"]
		player.teleport(world.free_spot_near(bc + Vector3(-3.0, 0, 2.5), [bc], 1.5, 0.4, 8.0))
		for x in hunters:
			if x.team == player.team and x != player:
				x.teleport(world.free_spot_near(bc + Vector3(-1.5, 0, 3.0), [bc, player.pos], 1.2, 0.4, 8.0))
				x.gems = 60
				x.ctrl = "idle"
				eliminate(x, null, "knocked out")
				break
	if (opts.get("pack_demo", false) or opts.get("bag_demo", false)) and player and time > 1.0 and not has_meta("pack_demo_done") and hud:
		# test: a full backpack. pack_demo picks up treasure (the swap window); bag_demo opens the backpack
		set_meta("pack_demo_done", true)
		player.pack_cap = 6
		var gk: Array = Gear.ALL.keys()
		player.pack = [Loot.weapon("smg", 2, "venom"), Loot.valuable("sky_pearl"), Loot.glove(String(gk[1 % gk.size()]), 2), Loot.weapon("shotgun", 1), Loot.valuable("old_coin"), Loot.valuable("kin_idol")]
		Loot.equip(player, Loot.weapon("", 0, "", "thunderclap"))
		player.gear[Gear.slot_of(String(gk[0]))] = {"id": String(gk[0]), "rar": 3}
		player.refresh_gear()
		var pat := world.free_spot_near(player.pos + Vector3(1.0, 0, 0.6), [player.pos], 0.6)
		spawn_val(Loot.valuable("crown_shard"), Vector3(pat.x, world.ground_at(pat.x, pat.z), pat.z))
		var pat2 := world.free_spot_near(player.pos + Vector3(-1.4, 0, 1.0), [player.pos, pat], 0.6)
		var fw := Loot.weapon("sniper", 3, "frost")
		spawn_weapon("sniper", 3, Vector3(pat2.x, world.ground_at(pat2.x, pat2.z), pat2.z), "", false, -1, fw)
		if opts.get("pack_demo", false):
			Pack.take_ground(self, player, wpicks[wpicks.size() - 2])
		else:
			hud.toggle_pack()
	if opts.get("mates_demo", false) and player:
		# test: the squad UI. One teammate gets knocked, one dies into a deathbox, and the first is
		# picked back up a few seconds later (frames under the minimap and the ally alerts up top)
		var mates: Array = hunters.filter(func(x): return x.team == player.team and x != player)
		if time < 0.05:
			for i in mates.size():
				var x: Hunter = mates[i]
				x.ctrl = "idle"
				x.teleport(world.free_spot_near(player.pos + Vector3(-4.0 + 3.0 * i, 0, -3.0 + 1.5 * i), [player.pos], 1.2, 0.4, 10.0))
		if mates.size() >= 3:
			if time > 1.0 and time < 1.1 and not mates[0].downed: knock(mates[0], null, {})
			if mates[0].downed and not opts.has("mates_revive") or (opts.has("mates_revive") and time < float(opts.get("mates_revive", 0.0))): mates[0].revive = 0.0
			if time > 1.6 and time < 1.7 and not mates[1].out: eliminate(mates[1], null, "knocked out")
			if time > 1.2: mates[2].hp = mates[2].max_hp * 0.4; mates[2].armor = mates[2].max_armor * 0.5; mates[2].slow_t = 2.0
			if opts.has("mates_revive") and time > float(opts["mates_revive"]) and mates[0].downed:
				revive_hunter(mates[0], player)
			# test: an enemy standing on the knocked teammate (the stomp signal), kept alive for the shot
			if opts.get("stomp_demo", false) and mates[0].downed and time > 1.3:
				mates[0].down_hp = maxf(mates[0].down_hp, 55.0)
				for e in hunters:
					if e.team != player.team and not e.out:
						e.ctrl = "idle"
						e.teleport(mates[0].pos + Vector3(0.4, 0, 0.2))
						break
			# test: walk up to the dead teammate's deathbox and open the loot window
			if opts.get("loot_demo", false) and time > 2.0 and not has_meta("loot_demo_done") and hud:
				set_meta("loot_demo_done", true)
				var lb: Dictionary = Life.box_of(self, mates[1])
				if not lb.is_empty():
					var ids: Array = Gear.ALL.keys()
					if ids.size() > 1:
						(lb["gear"] as Array).append({"id": String(ids[0]), "rar": 3})
						(lb["gear"] as Array).append({"id": String(ids[1]), "rar": 1})
					lb["weapon"] = Loot.weapon("sniper", 2, "frost")
					lb["pack"] = [Loot.valuable("crown_shard"), Loot.weapon("smg", 3, "venom"), Loot.valuable("old_coin"), Loot.valuable("soul_ember")]
					player.pack = [Loot.valuable("sky_pearl"), Loot.weapon("shotgun", 1), Loot.valuable("kin_idol"), Loot.weapon("rifle", 2), Loot.valuable("old_coin")]
					lb["gems"] = int(lb.get("gems", 0)) + 25
					lb["empty"] = false
					player.teleport(lb["pos"] + Vector3(0.8, 0, 0.6))
					hud.open_loot(lb)
	if opts.get("ledge_demo", false) and player and time < 0.05:
		# test: start just off the edge of your island, a few metres below the lip
		var p0 := player.pos
		for i in 60:
			var q := p0 + Vector3(0.5 * i, 0, 0)
			if world.is_void(q.x, q.z):
				player.teleport(Vector3(q.x + 1.0, player.pos.y - 4.0, q.z)); player.grounded = false
				break
	if opts.has("aim_demo") and player:
		if opts.has("glove") and (player.gear[0] as Dictionary).is_empty():
			player.gear[0] = {"id": String(opts["glove"]), "rar": 2}
		aim_hold = String(opts["aim_demo"])
		player.inp["aim"] = player.pos + Vector3(4.0, 0, -3.0)
	if opts.get("sandbox_demo", false) and player:
		# test hook: lob the utility at the nearest dummy, then dodge
		var tgt: Ent = null; var bd := 1e9
		for mb in mobs:
			if not mb.dead and player.flat_dist(mb) < bd: bd = player.flat_dist(mb); tgt = mb
		if tgt: player.inp["aim"] = tgt.pos + Vector3(0, 0.95, 0)
		if time > 0.8 and time - DT <= 0.8: pending_input["sec"] = true
		if time > 2.6 and time - DT <= 2.6: pending_input["dash"] = true
		if time > 1.6: player.inp["fire"] = true
	if "--kin-lineup" in OS.get_cmdline_user_args() and player and not train.has("_lineup"):
		# test: every species in a row in front of you, glowing as if out in a fight
		train["_lineup"] = true
		var i := 0
		for spid in Data.KIN.keys():
			var q := player.pos + Vector3(-3.0 + i * 1.3, 0, -2.2)
			var w := spawn_wild(Save.new_kin(spid), q)
			w.home = q
			w.set_meta("lineup", true)
			i += 1
		cam.zoom_to = 0.55
	if opts.get("kin_demo", false) and player:
		# test hook: throw the kin at the nearest dummy, use Q, then V, then the bond ultimate, then swap
		var tgt: Ent = null; var bd := 1e9
		for mb in mobs:
			if not mb.dead and player.flat_dist(mb) < bd: bd = player.flat_dist(mb); tgt = mb
		if tgt: player.inp["aim"] = tgt.pos + Vector3(0, 0.95, 0)
		var tick := func(at_t: float) -> bool:
			if time > at_t and not train.has("_demo_%d" % int(at_t * 10.0)):
				train["_demo_%d" % int(at_t * 10.0)] = true
				return true
			return false
		if tick.call(0.6): pending_input["throw"] = true
		if tick.call(1.6): pending_input["sig"] = true
		if tick.call(3.4): pending_input["skill"] = true
		if tick.call(5.2): player.ult = 1.0; pending_input["ult"] = true
		if tick.call(11.0): pending_input["swap"] = true
		if time > 1.0: player.inp["fire"] = true
	if opts.get("cone_demo", false) and player:
		player.inp["aim"] = player.pos + Vector3(4.0, 0.95, -5.0)
		player.inp["crouch"] = opts.get("crouch_demo", false)
	if opts.get("wall_behind", false) and player and time < 0.05:
		for wi in world.walls:
			var wx: int = int(wi) % world.w; var wz: int = int(wi) / world.w
			var gi := world.idx(wx, wz - 1)
			if world.kind[gi] == World.T_GROUND and world.walls.has(world.idx(wx + 1, wz)) and world.walls.has(world.idx(wx - 1, wz)):
				player.teleport(Vector3(wx + 0.5, world.ground_at(wx + 0.5, wz - 0.5), wz - 0.5))
				break
	if opts.get("wall_demo", false) and player and time < 0.05:
		# stand in grass right beside a wall, with a rival hiding in grass nearby
		var spot := Vector3.INF; var rival_spot := Vector3.INF
		for bi in world.bush:
			var bx: int = int(bi) % world.w; var bz: int = int(bi) / world.w
			var near_wall := false
			for dz in range(-2, 3):
				for dx in range(-2, 3):
					if world.walls.has(world.idx(bx + dx, bz + dz)): near_wall = true
			var p3 := Vector3(bx + 0.5, world.ground_at(bx + 0.5, bz + 0.5), bz + 0.5)
			if near_wall and spot == Vector3.INF:
				spot = p3
			elif spot != Vector3.INF and rival_spot == Vector3.INF and p3.distance_to(spot) > 3.0 and p3.distance_to(spot) < 9.0:
				rival_spot = p3
		if spot != Vector3.INF:
			player.teleport(spot)
			for h in hunters:
				if h.team != player.team:
					h.teleport(rival_spot if rival_spot != Vector3.INF else spot + Vector3(4, 0, 0))
					break
	if opts.get("ring_demo", false) and player and time < 0.05 and not air_rings.is_empty():
		var rg: Dictionary = air_rings[0]
		var rd: Vector2 = rg["dir"]
		player.teleport(rg["pos"] - Vector3(rd.x, 0, rd.y) * 5.0 + Vector3(0, -0.6, 0))
		player.grounded = false; player.gliding = true
		player.vel = Vector3(rd.x, 0, rd.y) * 9.6
	if opts.get("ring_demo", false) and player and player.gliding:
		player.inp["glide"] = true
		player.inp["move"] = Vector2(player.vel.x, player.vel.z).normalized()
	if String(opts.get("map_demo", "")) == "mid" and player and hud and time > 0.6 and not has_meta("map_demo_done"):
		# test: the map mid-match, with a few spawns scouted (found, empty and taken) and squad pings
		set_meta("map_demo_done", true)
		var n_k := 0
		for cnd in (spawn_plan.cands if spawn_plan else []):
			if cnd["cat"] in ["rare_kin", "cache"] and n_k < 6 and (n_k % 2 == 0 or cnd["active"]):
				cnd["known"][player.team] = true; n_k += 1
		for cnd in (spawn_plan.active_of("vault").slice(0, 1) if spawn_plan else []):
			if cnd["ref"] is Dictionary: cnd["ref"]["open"] = true
		for x in hunters:
			if x.team == player.team and x != player:
				squad_ping(x, world.free_spot_near(x.pos + Vector3(14, 0, -6), [], 1.0, 0.5, 12.0)); break
		squad_ping(player, player.pos + Vector3(-20, 0, 12))
		hud.open_map(false)
	if opts.has("drop_demo") and player and not ship.is_empty():
		# test: skip ahead to the middle of the ride, the leader jumps and steers; the squad follows
		var follow: bool = String(opts["drop_demo"]) == "follow"     # (a squadmate leads, you follow)
		if not has_meta("drop_demo_t"):
			set_meta("drop_demo_t", true)
			time = float(ship["dur"]) * 0.5 - 2.0
			if follow and skydrop: skydrop.pass_lead(player)
		if player.riding and time > float(ship["dur"]) * 0.5 - 1.0:
			if follow:
				var ld := skydrop.leader(player.team)
				if ld and ld.riding: ship_jump(ld)
			else:
				ship_jump(player)
		if player.dropping:
			player.inp["move"] = Vector2(0.8, -0.6).normalized() if fmod(time, 6.0) < 3.0 else Vector2(0.3, 1.0).normalized()
	if opts.get("truce_demo", false) and truce:
		truce.demo()
	if opts.has("exit_demo") and exits and player and not player.dropping:
		exits.demo(String(opts["exit_demo"]))
	if opts.get("glide_demo", false) and player:
		if time < 0.05:
			player.teleport(player.pos + Vector3(0, 6, 0)); player.grounded = false
		player.inp["glide"] = true
		player.inp["move"] = Vector2(1, 0.3).normalized()
	if player and not player.out:
		if pending_input["base"]:
			pending_input["base"] = false
			player.start_base(base_target(player))
		for k in ["dash", "jump", "sig", "reload", "tonic", "kit", "ult", "sec", "gear1", "gear2", "skill", "swap"]:
			if pending_input[k]:
				player.inp[k] = true
				pending_input[k] = false
		if pending_input["throw"]:
			pending_input["throw"] = false
			_player_throw()
	for h in hunters:
		if h.ctrl == "bot" and not h.remote and not h.out and not h.extracted:
			bot_brain.think(self, h, dt)
	if skytrain: skytrain.tick(dt)
	if opts.has("train_demo") and skytrain and player:
		_train_demo()
	if duel:
		duel.after_think()
		duel.tick(dt)
	for h in hunters: h.sim(dt)
	if opts.get("autoplay", false) and int(time * 60.0) % 15 == 0:
		for h in hunters:
			var hist: Array = h.get_meta("hist", [])
			hist.append("%.1f:(%.1f,%.1f,%.1f) v(%.1f,%.1f,%.1f) g%d f%.2f r%.2f gr%d void%d gl%d fuel%.1f kb%.1f dn%d st%.1f cd%.1f %s" % [time, h.pos.x, h.pos.y, h.pos.z, h.vel.x, h.vel.y, h.vel.z, int(h.grounded), h.fly_t, h.roll_t, int(h.grap.size() > 0), int(h.over_void()), int(h.gliding), h.glide_fuel, time - h.kb_t, int(h.downed), h.stun_t, h.grap_cd, String(h.ai.get("goal_kind", ""))])
			if hist.size() > 10: hist.pop_front()
			h.set_meta("hist", hist)
	if skydrop: skydrop.tick(dt)
	for k in kins: k.sim(dt)
	for mb in mobs: mb.sim(dt)
	_separate()
	_collide_breaks()
	_update_rings(dt)
	_update_shots(dt)
	_update_pickups(dt)
	_update_wpicks(dt)
	_update_gear_fx(dt)
	_update_pads(dt)
	if not ship.is_empty() and not ship.get("gone", false):
		_update_ship(dt)
	_update_interact(dt)
	if opts.get("perk_demo", false) and player and time > 0.5 and time - dt <= 0.5:
		# test: a couple of perks already taken and a choice open
		player.add_perk("keen"); player.add_perk("keen"); player.add_perk("toughskin")
		offer_perks(player, "shrine")
		if hud: hud.ability_feedback("sec", "deny")
	Life.tick_wisps(self, dt)
	Life.tick_stomps(self, dt)
	_tick_chase()
	if not net_on:
		Life.tick_beacons(self, dt)
		_watch_death()
	_update_dex(dt)
	if exits: exits.tick(dt)
	if lairs:
		lairs.bot_pickups()
		lairs.tick(dt)
		if opts.has("lair_demo") and player and not player.dropping:
			lairs.demo(String(opts["lair_demo"]))
	if truce: truce.tick(dt)
	if spawn_plan: spawn_plan.tick(dt)
	_update_events()
	_update_zones(dt)
	fields.tick(dt)
	verbs.tick(dt)
	_run_later()
	if biomes: biomes.tick(dt)
	_update_tracking(dt)
	if opts.get("tutorial", false):
		if opts.get("tut_test", false):
			_tut_drive()
		_update_tutorial(dt)
	if opts.get("training", false) and duel == null:
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
	if k == null or player.downed or player.dropping or player.riding:
		return
	if k.state == "shoulder":
		if k.throw_cd > 0.0:
			return
		k.throw_to(_ground_aim(player))
	elif k.state in ["active", "flying", "returning"]:
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

var _dex_t := 0.0
var _shimmer_told := {}

## Wild kin you get a look at go in the Kindex. A shimmer gets called out.
func _update_dex(dt: float) -> void:
	_dex_t -= dt
	if _dex_t > 0.0 or player == null or player.out or opts.get("autoplay", false):
		return
	_dex_t = 1.0
	for k in kins:
		if k.is_wild() and not k.dead and player.flat_dist(k) < 11.0:
			Care.dex_mark(k.species, "seen")
			if k.rec.get("shimmer", false) and not _shimmer_told.has(k.nid):
				_shimmer_told[k.nid] = true
				hud.toast("A shimmering %s! Its colours are rare" % Data.KIN[k.species]["name"], Color("fff6c0"))
				sfx("unlock", k.pos, -6.0, 1.3)

func _update_interact(dt: float) -> void:
	for h in hunters:
		if h.out or h.extracted or h.downed or h.dropping:
			continue
		if not h.stomp.is_empty():
			if h == player:
				var so: Hunter = h.stomp["o"]
				interact = {"kind": "stomping", "label": "Stomping %s  ·  locked in" % so.pname, "col": Color("ff8a6a")}
			continue
		var want: bool = h.inp.get("interact", false)
		if not want:
			h.swap_hold = false
		var best := {}
		# 1. wisps, as in Supervive: standing on a downed teammate revives them and standing on a
		# downed enemy stomps them (both in Life.tick_wisps); holding interact executes them
		for o in hunters:
			if o == h or not o.downed or o.out or h.flat_dist(o) > Life.R["revive_radius"]:
				continue
			if o.team == h.team:
				if o.remote:
					_rev_out[o.nid] = float(_rev_out.get(o.nid, 0.0)) + dt / Life.R["revive_time"]
					o.revive += dt / Life.R["revive_time"]
				if h == player and best.is_empty():
					# your own revive bar, so you know it's working (and when it's blocked)
					if o.get_meta("stomped", false):
						best = {"kind": "revive", "ent": o, "label": "An enemy is standing on %s: revive blocked. Knock them off!" % o.pname, "col": Color("ff6a5a")}
					else:
						best = {"kind": "revive", "ent": o, "label": "Reviving %s  ·  stay in the ring" % o.pname, "col": Color("9ee2a0")}
			elif not o.remote:
				best = {"kind": "finish", "ent": o, "label": "Hold %s to stomp %s  (you'll be locked in)" % [Settings.key_cap("interact"), o.pname], "col": Color("ff8a6a")}
		if not want or best.get("kind", "") != "finish":
			h.finish_t = 0.0
		# 1b. deathboxes: bring a teammate back while their soul is there, or take everything
		if best.is_empty():
			for b in boxes:
				if h.flat_dist(b["pos"]) > 1.5 or absf(h.pos.y - float(b["pos"].y)) > 1.4:
					continue
				var o: Hunter = b["owner"]
				if o.team == h.team and o != h and Life.soul_here(self, b) and not o.remote:
					best = {"kind": "boxrev", "box": b, "label": "Hold %s to bring %s back" % [Settings.key_cap("interact"), o.pname], "col": Color("9ee2a0")}
					break
				if not b["empty"]:
					var whose: String = "your box" if o == h else o.pname + "'s box"
					var open_now: bool = h == player and hud != null and hud.loot_is(b)
					var lt := ("Press %s again to smart loot  ·  click items to take them" % Settings.key_cap("interact")) if open_now else ("Press %s to open %s  ·  twice to smart loot" % [Settings.key_cap("interact"), whose])
					best = {"kind": "loot", "box": b, "label": lt if h == player else "Hold %s to loot %s" % [Settings.key_cap("interact"), whose], "col": Life.box_color(b)}
					break
		if best.get("kind", "") not in ["boxrev", "loot"] or not want:
			h.box_t = 0.0
		if not want:
			h.set_meta("loot_hold", false)
		# 2. catch a dazed wild kin (not in training: practice kin go home with nobody)
		if best.is_empty() and not opts.get("training", false):
			for k in kins:
				if k.state == "dazed" and not k.dead and h.flat_dist(k) < 1.9:
					best = {"kind": "catch", "ent": k, "label": ("Hold %s to capture %s" % [Settings.key_cap("interact"), k.rec.get("name", "the kin")]) if k.lost_from != "" else ("Hold " + Settings.key_cap("interact") + " to catch the %s" % Data.KIN[k.species]["name"])}
					break
		# 3. swap to a weapon on the ground
		if best.is_empty():
			var bd := 1.5
			for wp in wpicks:
				var d: float = h.flat_dist(wp["pos"])
				if d < bd and absf(h.pos.y - float(wp["pos"].y)) < 1.2 and h == player:
					# the player: equip it if it's better, else into the backpack (full: choose what to drop)
					bd = d
					best = {"kind": "weapon", "wp": wp, "label": _pickup_label(h, wp), "col": Loot.col_of(Pack.ground_item(wp))}
				elif d < bd and absf(h.pos.y - float(wp["pos"].y)) < 1.2 and wp.has("val"):
					continue
				elif d < bd and absf(h.pos.y - float(wp["pos"].y)) < 1.2 and wp.has("gear"):
					bd = d
					var gd: Dictionary = Gear.ALL[wp["gear"]]
					var rn: String = String(Data.RARITY[int(wp["rar"])]["name"]) + " " if int(wp["rar"]) > 1 else ""
					var gslot := Gear.slot_of(String(wp["gear"]))
					var cur: Dictionary = h.gear[gslot]
					var swap_txt := ("  ·  replaces " + String(Gear.ALL[String(cur["id"])]["name"])) if not cur.is_empty() and Gear.ALL.has(String(cur["id"])) else ""
					best = {"kind": "weapon", "wp": wp, "label": "Press %s to take %s%s  (%s glove%s: %s)%s" % [Settings.key_cap("interact"), rn, gd["name"], "active" if gslot == 0 else "passive", ("  ·  " + Settings.key_cap("gear1")) if gslot == 0 else "", Gear.stat_text(wp["gear"], int(wp["rar"])), swap_txt], "col": gd["col"]}
				elif d < bd and absf(h.pos.y - float(wp["pos"].y)) < 1.2:
					bd = d
					var r: Dictionary = Data.RARITY[int(wp["rar"])]
					var nm: String = Data.weapon_stats(String(wp["wid"]), int(wp["rar"]))["name"]
					var extra := "  (+%d%% damage)" % int(round((float(r["dmg"]) - 1.0) * 100.0)) if int(wp["rar"]) > 0 else ""
					best = {"kind": "weapon", "wp": wp, "label": "Press %s to take %s%s" % [Settings.key_cap("interact"), nm, extra], "col": r["color"]}
		# 4. open a chest
		if best.is_empty():
			for c in chests:
				if not c["open"] and h.flat_dist(c["pos"]) < 1.6:
					best = {"kind": "chest", "chest": c, "label": ["Hold " + Settings.key_cap("interact") + " to open", "Hold " + Settings.key_cap("interact") + " to open the rare chest", "Hold " + Settings.key_cap("interact") + " to open the vault"][int(c.get("tier", 0))]}
					break
		# 4. pray at a shrine
		if best.is_empty():
			for sh in shrines:
				if not sh["used"] and h.flat_dist(sh["pos"]) < 1.8:
					best = {"kind": "shrine", "shrine": sh, "label": "Hold " + Settings.key_cap("interact") + " to pray: heal, a blessing and a perk"}
					break
		# 5. the exits: call a skiff, unlock a hatch, start an uplink
		if exits:
			# (using an exit beats picking up a weapon or opening a chest that happens to be there)
			var ex := exits.interact_for(h)
			if best.is_empty() or (ex.has("act") and String(best.get("kind", "")) in ["weapon", "chest", "shrine"]): best = ex
		# 6. the lairs: work a gate's dial, light a rune
		if lairs:
			var lx := lairs.interact_for(h)
			if not lx.is_empty() and (best.is_empty() or not String(best.get("kind", "")) in ["revive", "finish", "boxrev", "loot", "catch", "exit"]): best = lx
		if h == player:
			interact = best
		if best.is_empty() or not want:
			continue
		match best["kind"]:
			"weapon":
				if not h.swap_hold:
					h.swap_hold = true
					if h == player and not opts.get("training", false):
						Pack.take_ground(self, h, best["wp"])
					else:
						_take_weapon(h, best["wp"])
			"finish":
				# a short hold commits you to the stomp (Life.start_stomp): no cancelling after that
				var o: Hunter = best["ent"]
				h.finish_t += dt
				if h.finish_t >= Life.R["stomp_commit"]:
					Life.start_stomp(self, h, o)
			"loot" when h == player and hud:
				# press to open the box's loot window; press again (with it open) to smart loot
				if not bool(h.get_meta("loot_hold", false)):
					h.set_meta("loot_hold", true)
					var b0: Dictionary = best["box"]
					if hud.loot_is(b0):
						var got := Life.smart_loot(self, h, b0)
						hud.toast_small(("Smart looted %d thing%s" % [got, "" if got == 1 else "s"]) if got > 0 else "Nothing here beats what you've got", Color("ffd36a"))
						if b0["empty"] or got > 0: hud.close_loot()
					else:
						hud.open_loot(b0)
			"boxrev", "loot":
				var b: Dictionary = best["box"]
				# taking a hit breaks the channel
				if time - h.hurt_at < 0.1:
					h.box_t = 0.0
				h.box_t += dt
				var need: float = Life.R["box_revive_time"] if best["kind"] == "boxrev" else Life.R["loot_time"]
				if best["kind"] == "boxrev":
					# everyone can see a deathbox revive going up (and who's doing it)
					b["rev_prog"] = h.box_t / need
					b["rev_by"] = h
					b["rev_at"] = time
				if h.box_t >= need:
					h.box_t = 0.0
					if best["kind"] == "boxrev": Life.box_revive(self, b, h)
					else: Life.loot_box(self, h, b)
			"catch":
				var k: Kin = best["ent"]
				# capturing someone's lost kin takes longer than catching a wild one
				k.catch_prog += dt / (float(T.get("capture_time", 3.0)) if k.lost_from != "" else 1.3)
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
			"exit":
				exits.hold(h, best, dt)
			"lair":
				lairs.hold(h, best, dt)

func _catch(h: Hunter, k: Kin) -> void:
	if opts.get("training", false):
		return
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
	if k.lost_from != "":
		# someone's lost kin: it keeps who it is, and we remember who has it now
		rec["lost_from"] = k.lost_from
		rec["prev_trust"] = float(k.rec.get("trust", 50.0))
		for L in player_lost:
			if L["kin"] == k: L["holder"] = h
		if k.lost_from == "you" and h == player:
			add_feed("You got %s back! Extract to bring it home." % rec.get("name", "your kin"))
		elif k.lost_owner is Hunter and (k.lost_owner as Hunter).team != h.team:
			h.stolen_carry = true
			if k.lost_from == "you":
				kin_stolen(h, rec)
	else:
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
		tut_flag = tut_flag or tut_id() == "chest"
	var lid: Node3D = c["node"].get_node("Body/Lid")
	if lid.has_meta("hinged"):
		# the lid springs open on its hinge
		create_tween().tween_property(lid, "rotation:x", 1.9, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
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
	if t >= 1 and h and not h.remote:
		offer_perks(h, "chest")
	var n_gems: int = [randi_range(4, 6), randi_range(7, 9), randi_range(11, 14)][t]
	var n_pick := pickups.size(); var n_w := wpicks.size()
	# a crate on the sky train pops its loot gently, so it lands on the car and rides along
	var soft = Vector3(randf_range(-0.8, 0.8), 4.5, randf_range(-0.8, 0.8)) if c.has("ride") else null
	for i in n_gems:
		drop("gem", c["pos"] + Vector3(0, 0.8, 0), int(round((3 + t) * float(T["loot"]))), "", "", soft)
	var seeds_n: int = [1 if randf() < 0.6 else 0, 1, 2][t]
	for i in seeds_n:
		drop("seed", c["pos"] + Vector3(0, 0.8, 0), randi_range(1, 2), Data.pick_seed(), "", soft)
	if not from_net and randf() < [0.25, 0.6, 1.0][t]:
		var keys: Array = Data.weapon_ids()
		var a := randf() * TAU
		var wk: String = biomes.weapon_at(c["pos"], keys) if biomes else String(keys[randi() % keys.size()])
		var wrc := mini(Data.RARITY.size() - 1, Data.roll_rarity(rng, maxi(0, t - 1) + (biomes.rarity_bonus_at(c["pos"]) if biomes else 0)))
		var wit := found_weapon(c["pos"], wk, wrc, [0.0, 0.02, 0.08][t])
		spawn_weapon(String(wit["wid"]), int(wit["rar"]), c["pos"] + Vector3(cos(a) * 1.1, 0, sin(a) * 1.1), "", true, -1, wit)
	if not from_net and randf() < [0.3, 0.7, 1.0][t]:
		# treasure for the backpack; the vault sometimes holds a Soul Ember
		var a3 := randf() * TAU
		spawn_val(Loot.valuable(Loot.roll_valuable(rng, t)), c["pos"] + Vector3(cos(a3) * 1.0, 0, sin(a3) * 1.0))
		if t == 2 and rng.randf() < 0.3:
			spawn_val(Loot.valuable("soul_ember"), c["pos"] + Vector3(-cos(a3) * 1.0, 0, -sin(a3) * 1.0))
	if not from_net and randf() < [0.35, 0.65, 1.0][t]:
		var a2 := randf() * TAU
		spawn_gear(Gear.roll(rng), Data.roll_rarity(rng, t), c["pos"] + Vector3(cos(a2) * 1.2, 0, sin(a2) * 1.2))
	# vaults sometimes hold a Rift Key
	if not from_net and exits and not exits.list.is_empty() and t == 2 and rng.randf() < 0.35:
		exits.drop_key(c["pos"])
	if h and not h.remote and h.tonics < 5 and randf() < [0.35, 0.7, 1.0][t]:
		h.tonics += 1
		if h == player: hud.toast("+1 tonic", Color("8ff0a0"))
	if c.has("ride"):
		for i in range(n_pick, pickups.size()): pickups[i]["ride"] = int(c["ride"])
		for i in range(n_w, wpicks.size()):
			# weapons and gear land on the deck, close to the crate
			var wp: Dictionary = wpicks[i]
			var off := Vector3(randf_range(-0.7, 0.7), 0.0, randf_range(-1.2, 1.2))
			var t3: Transform3D = skytrain.cur[int(c["ride"])]
			wp["pos"] = t3 * off; wp["ride"] = int(c["ride"])
			(wp["node"] as Node3D).position = wp["pos"]

# ------------------------------------------------------------------ perks found on the run
var perk_offer: Dictionary = {}    # the local player's open choice: {ids, src}
var perk_queue: Array = []         # more offers waiting behind it

## Three perks to choose one from (fewer if you've maxed most). Bots just take one.
func offer_perks(h: Hunter, src: String) -> void:
	var pool: Array = Data.PERKS.keys().filter(func(k): return h.perk_open(k))
	if pool.is_empty():
		return
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = pool[i]; pool[i] = pool[j]; pool[j] = tmp
	var picks: Array = pool.slice(0, mini(3, pool.size()))
	if h != player:
		h.add_perk(String(picks[0]))
		return
	if not perk_offer.is_empty():
		perk_queue.append({"src": src})
		return
	perk_offer = {"ids": picks, "src": src}
	sfx("unlock", null, -4.0, 1.1)
	if hud: hud.toast("Pick a perk: %s" % " / ".join(PackedStringArray(["1", "2", "3"].slice(0, picks.size()))), Color("ffd23f"))

## Takes perk i (0..2) of the open offer.
func choose_perk(i: int) -> void:
	if perk_offer.is_empty() or i < 0 or i >= (perk_offer["ids"] as Array).size():
		return
	var id: String = perk_offer["ids"][i]
	player.add_perk(id)
	var pd: Dictionary = Data.PERKS[id]
	fx.word(player.pos + Vector3(0, 2.4, 0), String(pd["name"]).to_upper(), pd["col"], true)
	fx.burst(player.pos + Vector3(0, 1.4, 0), pd["col"], 18, 3.5, 0.5, -2.0)
	sfx("bond", null, -6.0, 1.2)
	perk_offer = {}
	if not perk_queue.is_empty():
		var nx: Dictionary = perk_queue.pop_front()
		offer_perks(player, String(nx["src"]))

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
		h.bless_t = 20.0
		if h.kin and not h.kin.dead:
			h.kin.hp = h.kin.max_hp
		if h == player:
			hud.toast("Healed and blessed: +25% damage for 20s", Color("8fe3c8"))
		offer_perks(h, "shrine")

## Midway through, the Warden wakes on the heart island and guards it until someone brings it down.
## The guided first match. [id, text]: %K is the key for that step, %s your kin's name, %A an
## ability's name. Steps a kit can't do (no right-click ability, no kin) are skipped.
const TUT := [
	["land", "Steer with %K to choose where you land"],
	["move", "Walk around with %K"],
	["dash", "Press %K to dash"],
	["glide", "Press %K to jump, then hold Mouse 5 (or Space) in the air to glide. Mouse 5 is the easy way"],
	["exdash", "Jump, then press %K in the air for a long dash"],
	["shoot", "%W"],
	["utility", "Press %K: %A"],
	["kin1", "Press %K: %s uses %A"],
	["throw", "Press %K to throw %s at the monster"],
	["chest", "Walk to the chest and hold %K to open it"],
	["goexit", "Follow the marker to the outpost: its uplink calls you a way home"],
	["uplink", "Hold %K at the uplink mast to start it"],
	["defend", "Hold the outpost: stay in the yard while the uplink charges"],
	["extract", "The lift is open. Step into the light to head home"]]
const TUT_KEYS := {"land": "move", "move": "move", "dash": "dash", "glide": "jump", "exdash": "dash", "utility": "secondary",
	"kin1": "signature", "throw": "throw", "chest": "interact", "uplink": "interact"}
var tut_target := Vector3.INF    # where the HUD points (a world marker, an edge arrow and the distance)
var tut_label := ""
var tut_used0 := {}

# ---- training area
## [id, what to do, the action whose key it uses ("" for none)]
const TRAIN := [["move", "Walk around", "up"], ["dash", "Dash", "dash"], ["glide", "Jump, then hold Mouse 5 or Space in the air to glide", "jump"],
	["shoot", "Shoot a target dummy", "fire"], ["ability", "Use your kin's ability", "signature"], ["ult", "Fill the bond meter and use your bond ultimate", "ultimate"],
	["secondary", "Use your weapon ability (right click)", "secondary"], ["glove", "Use your glove (pick one up from the rack first)", "gear1"],
	["crouch", "Sneak: slower, steadier aim, harder to spot", "crouch"],
	["throw", "Throw your kin at a dummy", "throw"], ["combo", "Land a combo: shoot a foe your kin just stunned or rooted", "fire"], ["tonic", "Heal (tonic, or armor kit when health is full)", "tonic"],
	["stagger", "Stagger a big dummy: hit it with an ability while it has a purple ring", "signature"],
	["smash", "Break a crate or pot", "fire"], ["weapon", "Take a found weapon off the ground", "interact"],
	["ledge", "Dash off an edge and float back up", ""]]
var train := {}
var train_t := 0.0

var duel_pad := Vector3.INF

## The training pad that takes you to the duel room.
static func duel_opts() -> Dictionary:
	return {"training": true, "duel": true, "teams": 1, "squad": 1, "tier": 0, "length": 1e9, "seed": 5151, "no_drop": true}

func _update_training(dt: float) -> void:
	if player == null:
		return
	if duel_pad != Vector3.INF and player.flat_dist(duel_pad) < 1.3 and not player.downed:
		if Input.is_action_just_pressed("interact") and not paused:
			Game.start_match(duel_opts())
			return
	train_t += dt
	if player.downed and train_t > 2.0:
		revive_hunter(player, null)
	var was_ult: bool = train.get("_ult_full", false)
	# everything recharges quickly here
	player.ult = minf(1.0, player.ult + dt / 6.0)
	player.sig_cd = maxf(0.0, player.sig_cd - dt * 2.0)
	for kk in [player.kin, player.kin2]:
		if kk: (kk as Kin).runner.tick(dt * 2.0)
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
		"ability": player.kin != null and (player.kin as Kin).runner.has_slot("k1") and not (player.kin as Kin).runner.is_ready("k1"),
		"glove": float(player.gear_cd[0]) > 0.0,
		"combo": int(player.stats.get("combos", 0)) > 0,
		"crouch": player.crouch,
		"secondary": player.runner != null and player.runner.has_slot("utility") and not player.runner.is_ready("utility"),
		"ult": was_ult and player.ult < 0.5,
		"throw": player.kin != null and player.kin.st_throws > 0,
		"tonic": player.tonics < int(train.get("_tonics", player.tonics)),
		"ledge": player.grap.size() > 0 or player.mantle_k() > 0.0,
		"smash": train.get("_smash", false),
		"stagger": train.get("_stagger", false),
		"weapon": train.get("_weapon", false),
	}
	train["_ult_full"] = player.ult >= 0.99
	train["_tonics"] = player.tonics
	for k in marks:
		if marks[k] and not train.has(k):
			train[k] = true
			Sfx.play("unlock", null, -8.0)
			var left := train_rows().filter(func(t): return not train.has(t[0])).size()
			if hud: hud.toast(("Done: %s" % _train_label(k)) if left > 0 else "Training complete. Press Esc to head home whenever you like", Color("8ff0a0"))
			if left == 0:
				Save.d["tutorial"]["training"] = true
	# keep a few target dummies around you
	var alive := mobs.filter(func(x): return not x.dead)
	if alive.size() < 4 and int(train_t * 10.0) % 20 == 0:
		var at := world.random_ground(world.island_of(player.pos.x, player.pos.z))
		if Vector2(at.x - player.pos.x, at.z - player.pos.z).length() > 3.0:
			spawn_mob(["skitter", "spitter", "brute", "sentinel"][randi() % 4], at)

## The checklist for this hero: the secondary step only shows for heroes that have one.
func train_rows() -> Array:
	return TRAIN.filter(func(t): return t[0] != "secondary" or (player != null and player.runner != null and player.runner.has_slot("utility")))

func _train_label(k: String) -> String:
	for t in TRAIN:
		if t[0] == k: return t[1]
	return k

func tut_id() -> String:
	return String(TUT[tut_step][0]) if tut_step >= 0 and tut_step < TUT.size() else ""

## Whether this hunter's kit has the thing a step teaches.
func _tut_applies(id: String) -> bool:
	match id:
		"utility": return player.runner != null and player.runner.has_slot("utility")
		"kin1": return player.kin != null and player.kin.runner != null and player.kin.runner.has_slot("k1")
		"throw": return player.kin != null
	return true

## The first match is a guided one: no rival hunters, no monster camps, gentle damage, and each
## step waits for you. Monsters only turn up when a step needs one.
func _update_tutorial(dt: float) -> void:
	if player == null or player.extracted:
		return
	if tut_step < 0:
		tut_step = 0
		_tut_enter(0)
	# getting knocked down here isn't the end: you get back up after a moment
	if player.downed:
		tut_down_t += dt
		if tut_down_t > 3.0:
			tut_down_t = 0.0
			revive_hunter(player, null)
	var kname: String = player.kin.rec.get("name", "your kin") if player.kin else "your kin"
	var id := tut_id()
	var done := false
	match id:
		"land": done = not player.dropping
		"move":
			if player.inp["move"].length() > 0.1:
				tut_moved += Vector2(player.pos.x - player.prev.x, player.pos.z - player.prev.z).length()
			done = tut_moved > 6.0
		"dash":
			tut_flag = tut_flag or player.roll_t > 0.0
			done = tut_flag
		"glide":
			tut_flag = tut_flag or player.gliding
			done = tut_flag and player.grounded
		"exdash":
			tut_flag = tut_flag or (player.roll_t > 0.0 and player.dash_is_ex)
			done = tut_flag and player.grounded
		"shoot":
			done = tut_kills >= 1
			_tut_keep_foe("skitter")
		"utility": done = int(player.used.get("utility", 0)) > int(tut_used0.get("utility", 0))
		"kin1":
			done = player.kin == null or player.kin.state == "fainted" or int(player.used.get("k1", 0)) > int(tut_used0.get("k1", 0))
		"throw":
			done = player.kin == null or player.kin.state == "fainted" or player.kin.st_throws > tut_throws0
			_tut_keep_foe("spitter")
		"chest": done = tut_flag
		"goexit":
			var o := _tut_outpost()
			done = not o.is_empty() and exits.in_yard(o, player)
		"uplink":
			var o2 := _tut_outpost()
			done = o2.is_empty() or o2["state"] != "idle"
		"defend":
			var o3 := _tut_outpost()
			done = o3.is_empty() or o3["state"] == "open"
		"extract": done = false
	# the marker follows whatever this step is about
	_tut_point(id)
	if tut_wait > 0.0:
		tut_wait -= dt
		return
	if done:
		tut_step += 1
		if tut_step == 1:
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--tut-from="): tut_step = int(a.substr(11))     # test: skip ahead after landing
		while tut_step < TUT.size() and not _tut_applies(tut_id()):
			tut_step += 1
		tut_flag = false
		tut_wait = 0.6
		sfx("pickup", null, -4.0, 1.3)
		if hud: hud.toast("Nice!", Color("8ff0a0"))
		_tut_enter(tut_step)
	if tut_step < TUT.size():
		tut_text = _tut_line(tut_id(), kname)

## The words for a step, with the player's own keys, kin name and ability names filled in.
func _tut_line(id: String, kname: String) -> String:
	var txt := ""
	for row in TUT:
		if row[0] == id: txt = String(row[1])
	if txt == "%W":
		if player.wpn.get("melee", false):
			txt = "Click %K to swing. Hold it to charge a heavy hit. Beat the monster"
		else:
			txt = "Aim with the mouse and hold %K to shoot. Beat the monster"
		txt = txt.replace("%K", Settings.key_cap("fire"))
	var key := ""
	if id == "land" or id == "move":
		key = "%s%s%s%s" % [Settings.key_cap("up"), Settings.key_cap("left"), Settings.key_cap("down"), Settings.key_cap("right")]
	elif TUT_KEYS.has(id):
		key = Settings.key_cap(TUT_KEYS[id])
	txt = txt.replace("%K", key)
	var an := ""
	if id == "utility" and player.runner and player.runner.has_slot("utility"):
		an = player.runner.def_of("utility").display_name
	elif id == "kin1" and player.kin and player.kin.runner and player.kin.runner.has_slot("k1"):
		an = player.kin.runner.def_of("k1").display_name
	txt = txt.replace("%A", an)
	return txt.replace("%s", kname)

## Where the HUD marker points for this step.
func _tut_point(id: String) -> void:
	tut_target = Vector3.INF
	tut_label = ""
	match id:
		"shoot", "throw", "kin1":
			var best: Ent = null; var bd := 1e9
			for mb in mobs:
				if not mb.dead and player.flat_dist(mb) < bd: bd = player.flat_dist(mb); best = mb
			if best and bd > 6.0:
				tut_target = best.pos; tut_label = "Monster"
		"chest":
			for c in chests:
				if not c["open"] and c.get("tut", false):
					tut_target = c["pos"]; tut_label = "Chest"
		"goexit", "uplink", "defend", "extract":
			var o := _tut_outpost()
			if not o.is_empty():
				tut_target = o["pos"]
				tut_label = {"goexit": "Outpost", "uplink": "Uplink", "defend": "Outpost", "extract": "Lift"}[id]

## Keeps exactly one monster around for a step that needs a target (if it fell off, another comes).
func _tut_keep_foe(kind: String) -> void:
	if mobs.any(func(x): return not x.dead):
		return
	if int(time * 4.0) % 4 != 0:
		return
	var at := _tut_spot(5.5, randf() * TAU)
	if at != Vector3.INF:
		spawn_mob(kind, at)

func _tut_enter(step_i: int) -> void:
	var id := String(TUT[step_i][0]) if step_i < TUT.size() else ""
	tut_used0 = player.used.duplicate()
	match id:
		"shoot":
			tut_kills = 0
			var at := _tut_spot(5.5, 0.0)
			if at != Vector3.INF: spawn_mob("skitter", at)
		"kin1":
			var at := _tut_spot(5.0, 0.8)
			if at != Vector3.INF and not mobs.any(func(x): return not x.dead): spawn_mob("skitter", at)
		"throw":
			if player.kin:
				tut_throws0 = player.kin.st_throws
				if player.kin.state in ["active", "flying"]:
					player.kin.recall()
			if not mobs.any(func(x): return not x.dead):
				var at := _tut_spot(5.0, 0.0)
				if at != Vector3.INF: spawn_mob("spitter", at)
		"chest":
			# whatever is left from the fight wanders off, so the rest is calm
			for mb in mobs:
				if not mb.dead: mb.dead = true; mb.visible = false
			var at := _tut_spot(4.5, 1.0)
			if at != Vector3.INF:
				var n := Models.chest(1)
				n.position = at
				add_child(n)
				chests.append({"pos": at, "open": false, "prog": 0.0, "node": n, "tier": 1, "tut": true})
				ping(at, Color("dfe8f2"))
		"goexit":
			# the map's outpost (one is made close by if the map has none): the marker leads there
			var o := _tut_outpost()
			if not o.is_empty():
				ping(o["pos"], ExitModels.UPLINK)
			if hud: hud.toast("Time to head home. Follow the marker to the outpost", ExitModels.UPLINK)
		"uplink":
			if hud: hud.toast("Starting the uplink draws monsters to the outpost", ExitModels.UPLINK)
		"defend":
			if hud: hud.toast("Stay inside the walls. A rival hunter in the yard would stall it", ExitModels.UPLINK)
		"extract":
			if hud: hud.toast("The lift is open!", ExitModels.UPLINK)

## The tutorial's way out: the map's outpost, or (on a map without one) one made a short walk away.
func _tut_outpost() -> Dictionary:
	if exits == null:
		return {}
	var outs := exits.of_kind("outpost")
	if not outs.is_empty():
		return outs[0]
	if player == null:
		return {}
	var at := _tut_spot(14.0, -1.0)
	if at == Vector3.INF: at = _tut_spot(8.0, -1.0)
	if at == Vector3.INF: return {}
	exits._add_outpost({"pos": at, "walled": false}, true)
	exits.list[-1]["i"] = exits.list.size() - 1
	return exits.list[-1]

var _tut_last := -1
## Test driver: plays the tutorial by itself so the whole flow can be checked headless.
func _tut_drive() -> void:
	if tut_step != _tut_last:
		print("TUT step ", tut_step, " ", tut_id(), " t=", snapped(time, 0.1), " mobs=", mobs.filter(func(x): return not x.dead).size())
		_tut_last = tut_step
	var p := player
	p.inp["move"] = Vector2.ZERO
	p.inp["fire"] = false
	p.inp["glide"] = false
	p.inp["interact"] = false
	var goto := func(at: Vector3):
		var d := Vector2(at.x - p.pos.x, at.z - p.pos.z)
		p.inp["move"] = d.normalized() if d.length() > 0.5 else Vector2.ZERO
	var near_mob := func() -> Ent:
		var best: Ent = null; var bd := 1e9
		for mb in mobs:
			if not mb.dead and p.flat_dist(mb) < bd: bd = p.flat_dist(mb); best = mb
		return best
	if "--tut-debug" in OS.get_cmdline_user_args() and int(time * 60.0) % 120 == 0:
		var nm: Ent = near_mob.call()
		print("  dbg p=", p.pos.snapped(Vector3.ONE * 0.1), " gr=", p.grounded, " glide=", p.gliding, " mob=", (nm.pos.snapped(Vector3.ONE * 0.1) if nm else null), " hp=", (nm.hp if nm else 0.0), " wpn=", p.wid, " ammo=", p.get("ammo"), " kin=", (p.kin.state if p.kin else "-"))
	match tut_id():
		"move": p.inp["move"] = Vector2(1, 0) if int(time) % 4 < 2 else Vector2(-1, 0)
		"dash": p.inp["dash"] = true
		"glide":
			if p.grounded and not tut_flag: p.inp["jump"] = true
			p.inp["glide"] = true
		"exdash":
			if p.grounded and not tut_flag: p.inp["jump"] = true
			elif not p.grounded and not tut_flag and p.vel.y < 0.0: p.inp["dash"] = true
		"utility":
			p.inp["sec"] = true
		"shoot", "kin1", "throw":
			var best: Ent = near_mob.call()
			if best:
				p.inp["aim"] = best.pos + Vector3(0, 0.9, 0)
				if p.flat_dist(best) > 3.0: goto.call(best.pos)
				if tut_id() == "shoot": p.inp["fire"] = true
				elif tut_id() == "kin1": p.inp["sig"] = true
				elif p.kin and p.kin.state == "shoulder": p.kin.throw_to(best.pos)
			elif tut_id() == "kin1":
				p.inp["sig"] = true
		"chest":
			for c in chests:
				if not c["open"] and c.get("tut", false):
					goto.call(c["pos"]); p.inp["interact"] = true; break
		"goexit", "uplink", "defend", "extract":
			var o := _tut_outpost()
			if o.is_empty():
				return
			var c: Vector3 = o["pos"]
			match tut_id():
				"goexit":
					# go there the way a bot would: over the bridges, or jump and glide across a gap
					var mv := bot_brain._path_dir(self, p, c)
					if p.ai.has("cross"):
						var L: Dictionary = p.ai["cross"]
						var land: Vector3 = L["land"]
						var tol := Vector2(land.x - p.pos.x, land.z - p.pos.z)
						if p.grounded and world.island_of(p.pos.x, p.pos.z) == int(L["to"]):
							p.ai.erase("cross")
						elif not p.grounded:
							mv = tol.normalized()
							p.inp["glide"] = tol.length() > 1.6 or world.is_void(p.pos.x, p.pos.z)
						elif p.flat_dist(L["take"]) < 1.3:
							mv = tol.normalized()
							p.inp["jump"] = true
					p.inp["move"] = mv
					p.inp["aim"] = p.pos + Vector3(mv.x, 0.9, mv.y) * 3.0
				"uplink":
					goto.call(c)
					p.inp["interact"] = p.flat_dist(c) < 1.4
				"defend":
					goto.call(c + Vector3(1.2, 0, 1.2))
					var best: Ent = near_mob.call()
					if best and p.flat_dist(best) < 8.0:
						p.inp["aim"] = best.pos + Vector3(0, 0.9, 0)
						p.inp["fire"] = true
				"extract":
					goto.call(c)

## Test hook (--train-demo): ride the sky train from a stop; "--train-demo=track" stands you on the
## track ahead of the engine instead, "--train-demo=view" watches it from a pier.
func _train_demo() -> void:
	var mode := String(opts["train_demo"]) if opts["train_demo"] is String else "ride"
	var st := skytrain
	if time < DT * 1.5 and mode != "watch":
		cam.zoom_to = 0.8
		if mode == "track":
			# a stretch of open track ahead, level with the islands (not down under a bridge)
			var ps := st.head_s + 20.0
			while ps < st.head_s + 120.0 and not (world.train_at(ps).y > -0.01 and world.train_at(ps - 6.0).y > -0.01 and world.is_void(world.train_at(ps).x, world.train_at(ps).z)):
				ps += 1.0
			opts["train_pin"] = world.train_at(ps)
			player.teleport(opts["train_pin"])
		elif mode == "view":
			var t: Transform3D = st.cur[2]
			player.teleport(world.free_spot_near(t.origin - t.basis.x * 4.0, [], 1.0, 0.4, 6.0))
		else:
			var t2: Transform3D = st.cur[2]
			player.teleport(t2.origin + Vector3(0, 0.05, 0))
		player.grounded = true
	if mode == "track" and not player.downed and not player.out:
		# stand on the rails (pinned there: the track has no floor of its own) and wait for the engine
		player.pos = opts["train_pin"]; player.vel = Vector3.ZERO; player.grounded = true
		player.inp["move"] = Vector2.ZERO
	if int(time * 60.0) % 60 == 0:
		var t3: Transform3D = st.cur[2]
		print("TRAIN t=%.1f head=%.1f v=%.1f player=(%.1f,%.2f,%.1f) car2=(%.1f,%.2f,%.1f) grounded=%d hp=%.0f downed=%d out=%d" % [time, st.head_s, st.head_v, player.pos.x, player.pos.y, player.pos.z, t3.origin.x, t3.origin.y, t3.origin.z, int(player.grounded), player.hp, int(player.downed), int(player.out)])

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
	var col: Color = owner.accent() if owner else Color.WHITE
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
			fx.burst(p, Color(Color("f2d47a"), 0.8), 6, 2.0, 0.25, 0.0, 0.7)
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
					var amt := 12.0 * 0.25 if z["kind"] == "sanctuary" else 0.0
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
	_update_meteors()
	if not glimmer_done and time > length * 0.5 and (not net_on or is_host):
		glimmer_done = true
		_spawn_glimmer()
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

# ---- mid-match events
## A meteor shower partway through: falling stars hit the ground where hunters are, knock them
## around and leave gems behind.
func _update_meteors() -> void:
	var dt := DT
	for mt in meteors.duplicate():
		mt["t"] = float(mt["t"]) - dt
		fx.telegraph_progress(mt["tele"], 1.0 - float(mt["t"]) / 1.5)
		if float(mt["t"]) <= 0.0:
			meteors.erase(mt)
			fx.end_telegraph(mt["tele"])
			_meteor_hit(mt["at"])
	if not big or (net_on and not is_host):
		return
	if meteor_at < 0.0:
		meteor_at = length * 0.24 if not opts.get("meteor_test", false) else 1.5
		meteor_end = meteor_at + 16.0
	if time < meteor_at or time > meteor_end:
		return
	if time - dt < meteor_at:
		_announce("A meteor shower is coming down. Stars leave gems where they land", Color("ffcf8a"))
		if net_on: net_event(["anc", "meteor", 0, 0, 0])
	meteor_next -= dt
	if meteor_next > 0.0:
		return
	meteor_next = 0.35
	var alive: Array = []
	for h in hunters:
		if not h.out and not h.extracted and not h.riding: alive.append(h)
	if alive.is_empty():
		return
	var h: Hunter = alive[rng.randi() % alive.size()]
	for _t in 10:
		var a := rng.randf() * TAU
		var q := h.pos + Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, 7.0)
		if not world.is_void(q.x, q.z) and not world.is_block(q.x, q.z):
			var at := Vector3(q.x, world.ground_at(q.x, q.z), q.z)
			_meteor_start(at)
			if net_on: net_event(["met", _r(at.x), _r(at.y), _r(at.z)])
			break

func _meteor_start(at: Vector3) -> void:
	meteors.append({"at": at, "t": 1.5, "tele": fx.telegraph_circle(at, 1.7, Color("ffb04a"))})

func _meteor_hit(at: Vector3) -> void:
	fx.bolt(at + Vector3(2.5, 14.0, -3.0), at, Color("ffd9a0"))
	fx.ring(at, 1.7, Color("ffb070"), 0.3)
	fx.burst(at + Vector3(0, 0.3, 0), Color("ffcf8a"), 22, 6.0, 0.5, 6.0, 1.2)
	fx.dust(at, 10)
	sfx("boom", at, -3.0, 1.3)
	shake(0.35, at)
	for e in hunters + mobs + kins:
		if e.remote or not e.hittable() or (e is Hunter and (e as Hunter).riding):
			continue
		var to := Vector2(e.pos.x - at.x, e.pos.z - at.z)
		if to.length() < 1.7 + e.r and absf(e.pos.y - at.y) < 1.6:
			e.hurt(14.0, null, {"src": "boom", "kb": to.normalized() * 6.0, "lift": 5.0})
	if not net_on or is_host:
		for b in breaks:
			if not b["dead"] and Vector2(b["pos"].x - at.x, b["pos"].z - at.z).length() < 1.9:
				hit_break(b, 30.0, null)
	if rng.randf() < 0.6:
		drop("gem", at + Vector3(0, 0.6, 0), maxi(1, int(round(3 * float(T["loot"])))))

func _announce(text: String, col: Color) -> void:
	sfx("warn", null, -2.0, 0.8)
	add_feed(text)
	if hud and player and not player.out:
		hud.toast(text, col)

## A treasure kin appears on a random outer island and runs. Bring it down for a pile of gems
## and a good weapon before it slips away.
func _spawn_glimmer() -> void:
	if world.islands.size() < 2:
		return
	var ii := rng.randi_range(1, world.islands.size() - 1)
	var at := world.random_ground(ii)
	spawn_mob("glimmer", at)
	ping(at, Color("ffd25a"))
	_announce("A Glimmerkin appeared %s. Catch it before it escapes" % (direction_word(player.pos, at) if player else ""), Color("ffd25a"))
	if net_on: net_event(["anc", "glimmer", _r(at.x), _r(at.y), _r(at.z)])

func on_mob_escaped(mb: Mob) -> void:
	mb.hp = 0.0
	mb.dead = true
	mb._cancel_tele()
	fx.burst(mb.pos + Vector3(0, 0.6, 0), Color("fff4c0"), 24, 4.0, 0.7, -4.0)
	if net_on: net_event(["mobdead", mb.nid, ""])
	if player and player.flat_dist(mb) < 25.0:
		add_feed("The Glimmerkin got away")

## Out: how (skiff, hatch, uplink) and where, for the results screen.
func _extract(h: Hunter, how := "", where := "") -> void:
	if h.extracted:
		return
	h.extracted = true
	h.downed = false
	if not h.stomp.is_empty(): Life.end_stomp(self, h, "extract")
	cancel_abilities(h)
	if net_on and not h.remote:
		net_event(["ext", h.nid])
	var col: Color = {"skiff": ExitModels.DOCK, "hatch": ExitModels.HATCH, "uplink": ExitModels.UPLINK}.get(how, Color("8fe3c8"))
	sfx("portal", h.pos, -4.0 if how == "hatch" else 0.0, 1.3)
	fx.burst(h.pos + Vector3(0, 1.0, 0), col, 30, 5.0, 0.8, -4.0)
	add_feed("%s extracted" % h.pname)
	if h.kin:
		h.kin.visible = false
	if h == player:
		if h.kin and h.kin.state != "fainted":
			h.kin.bark("extract")
		result = {"extracted": true, "why": "extracted", "how": how, "where": where}
		_end_soon(1.6)
		if opts.get("tut_test", false):
			print("TUT DONE extracted by %s at %s, t=%.1f" % [how, where, time])
			get_tree().create_timer(0.5).timeout.connect(func(): get_tree().quit())
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

## You're dead but your team's still in it: you wait (and watch) for a box or beacon revive.
## Once nobody's left to bring you back, the expedition's over for you.
func _watch_death() -> void:
	for b in boxes:
		var n: Node3D = b["node"]
		if n:
			var soul: Node3D = n.get_node_or_null("Soul")
			if soul: soul.visible = Life.soul_here(self, b)
	if player == null or not player.out or result.get("ending", false) or over:
		return
	if player.gone or not Life.team_alive(self, player.team):
		var mate: Hunter = null
		for x in hunters:
			if x.team == player.team and x.extracted: mate = x
		if mate and not player.gone:
			# a teammate made it out: your kin went with them
			player.gone = true
			add_feed("Your kin went home with %s" % mate.pname)
		Life.make_gone(self, player)
		result = {"extracted": false, "why": String(player.get_meta("died_why", "team wiped"))}
		_end_soon(2.2)

## The teammate the camera follows while you're dead, or null.
func spectating() -> Hunter:
	if player == null or not player.out or player.gone or time - float(player.get_meta("died_at", time)) < 2.5:
		return null
	for x in hunters:
		if x.team == player.team and x != player and not x.out and not x.extracted:
			return x
	return null

## Leave while dead and waiting on your team.
func give_up() -> void:
	if player and player.out and not result.get("ending", false):
		Life.make_gone(self, player)
		result = {"extracted": false, "why": String(player.get_meta("died_why", "knocked out"))}
		_end_soon(0.5)

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
		r["taken"] = int(player.dmg_taken)
		r["downs"] = player.downs
		r["deaths"] = player.deaths
		r["revives"] = player.revives
		r["armor_tier"] = player.armor_tier
		r["tonics"] = maxi(0, player.tonics - player.free_tonics)
		if not opts.get("tutorial", false):
			r["rift_keys"] = player.rift_keys if result.get("extracted", false) else 0
		r["stats"] = player.stats.duplicate()
		# weapons, gloves and treasure: home to the armory if you made it out, else what stayed behind
		if result.get("extracted", false):
			r["haul"] = Pack.haul(player)
		else:
			var lb := Life.box_of(self, player)
			r["lost_items"] = Pack._box_things(lb).map(func(c): return c["it"]) if not lb.is_empty() else Pack.haul(player)
		# what each kin you brought did, for its memories and growth
		r["kin_runs"] = []
		for kk in [player.kin, player.kin2]:
			if kk == null: continue
			var k: Kin = kk
			r["kin_runs"].append({"uid": String(k.rec.get("uid", "")), "events": k.events.duplicate(true), "trust": k.trust,
				"stats": {"hits": k.st_hits, "kos": k.st_kos, "throws": k.st_throws, "skills": k.st_skills,
				"revives": k.events.filter(func(e): return e["kind"] == "revived").size(), "caught": player.caught.size(),
				"won": 1 if result.get("extracted", false) else 0}})
		if player.kin:
			var k0: Kin = player.kin
			r["kin_events"] = k0.events.duplicate(true)
			r["kin_trust"] = k0.trust
		if not player_lost.is_empty() and not result.get("extracted", false):
			r["lost_kin"] = _resolve_lost()
		r["rivals"] = hunters.filter(func(x): return x.ctrl == "bot" and x.team != player.team).map(func(x): return x.pname)
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
			player.tonics = int(Save.d["items"].get("tonic", 0)) + 2; player.free_tonics = 2     # everyone sets out with a couple
			_apply_home_perks(player)
			if player.kin:
				_apply_treat(player.kin)
			_start_drop(player, at)
		else:
			var h := make_hunter("P" + peer, t, String(r["cls"]), String(r["name"]), "remote", krec, at, {"weapon": r.get("weapon", ""), "perk": ""})
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
			h.ai = bot_brain.new_mind(rng, float(opts.get("bot_skill", bot_cfg["skill"])), bot_cfg)
			h.tonics = 3
			_start_drop(h, at)

## A hit on something another game owns goes to its owner.
func net_send_hit(target: Ent, dmg: float, by: Ent, o: Dictionary) -> bool:
	if not net_on:
		return false
	var kb: Vector2 = o.get("kb", Vector2.ZERO)
	Net.hit(target.nid, [_r(dmg), _r(kb.x), _r(kb.y), _r(float(o.get("lift", -1.0))), 1 if o.get("crit", false) else 0,
		_r(float(o.get("stun", 0.0))), _r(float(o.get("burn", 0.0))), _r(float(o.get("slow", 0.0))), _r(float(o.get("root", 0.0))),
		by.nid if by else "", String(o.get("src", "")), String(o.get("ab", ""))])
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
	if h.reveal_t > 0.0: f |= 4096
	if h.crouch: f |= 8192
	if h.diving: f |= 16384
	return f

const KIN_STATES := ["shoulder", "flying", "flying_home", "active", "returning", "fainted", "reviving", "wild", "dazed"]
const MOB_STATES := ["idle", "chase", "windup", "lunge", "recover"]

func _ser(e: Ent) -> Array:
	if e is Hunter:
		var h: Hunter = e
		return ["h", h.nid, _r(h.pos.x), _r(h.pos.y), _r(h.pos.z), _r(h.vel.x), _r(h.vel.y), _r(h.vel.z), _r(h.face), _r(h.hp), h.max_hp, _flags(h),
			_r(h.down_hp), _r(h.revive), h.team, h.cls, h.pname, _r(h.shield), _r(h.extract_prog), h.kills, h.knocks, int(h.dmg_done), _r(h.armor), h.max_armor]
	if e is Kin:
		var k: Kin = e
		return ["k", k.nid, _r(k.pos.x), _r(k.pos.y), _r(k.pos.z), _r(k.face), _r(k.hp), _r(k.max_hp), KIN_STATES.find(k.state), k.species,
			k.owner_h.nid if k.owner_h else "", int(k.rec.get("level", 1)), String(k.rec.get("name", "")), _r(k.catch_prog), _r(k.vel.x), _r(k.vel.z),
			1 if k.rec.get("shimmer", false) else 0, String(k.rec.get("acc", ""))]
	var mb: Mob = e
	return ["m", mb.nid, _r(mb.pos.x), _r(mb.pos.y), _r(mb.pos.z), _r(mb.face), _r(mb.hp), _r(mb.max_hp), MOB_STATES.find(mb.st), mb.mkind,
		_r(mb.atk_dir.x), _r(mb.atk_dir.y), _r(mb.st_t), _r(mb.vel.x), _r(mb.vel.z), _r(mb.stag_open), _r(mb.stagger_t)]

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
			if it.size() > 17:
				rec["shimmer"] = int(it[16]) == 1
				rec["acc"] = String(it[17])
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
			h.diving = f & 16384 != 0
			if f & 4096 != 0: h.reveal_t = maxf(h.reveal_t, 0.3)
			h.crouch = f & 8192 != 0
			h.down_hp = it[12]; h.revive = maxf(h.revive if h.revive > float(it[13]) and _rev_out.has(h.nid) else 0.0, float(it[13]))
			h.shield = it[17]; h.extract_prog = it[18]
			h.kills = int(it[19]); h.knocks = int(it[20]); h.dmg_done = float(it[21])
			if it.size() > 23:
				h.armor = float(it[22]); h.max_armor = float(it[23])
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
			if it.size() > 16:
				mb.stag_open = float(it[15]); mb.stagger_t = float(it[16])

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
	if x.size() > 12 and String(x[12]) != "": o["ab"] = String(x[12])
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
		"xc":
			if exits: exits.net_in(x)
		"emo":
			var eh: Hunter = ents_by_id.get(String(x[1]), null) as Hunter
			if truce and eh: truce.emote(eh, String(x[2]), true)
		"sping":
			var ph: Hunter = ents_by_id.get(String(x[1]), null) as Hunter
			if ph: squad_ping(ph, Vector3(x[2], x[3], x[4]), true)
		"unping":
			var uh: Hunter = ents_by_id.get(String(x[1]), null) as Hunter
			if uh: unping(uh, true, true)
		"lead":
			var lh: Hunter = ents_by_id.get(String(x[1]), null) as Hunter
			var lt: Hunter = ents_by_id.get(String(x[2]), null) as Hunter
			if skydrop and lh and lt: skydrop.pass_lead(lh, lt, true)
		"dsep":
			var sh: Hunter = ents_by_id.get(String(x[1]), null) as Hunter
			if skydrop and sh: skydrop.separate(sh, true)
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
		"met":
			_meteor_start(Vector3(x[1], x[2], x[3]))
		"stg":
			var smb: Ent = ents_by_id.get(String(x[1]), null)
			if smb is Mob:
				(smb as Mob).stagger_t = 2.2 if (smb as Mob).mkind == "warden" else 3.0
				(smb as Mob).stag_open = 0.0
				fx.ring(smb.pos, smb.r + 1.8, Color("c47aff"), 0.4)
				fx.burst(smb.pos + Vector3(0, 1.0, 0), Color("e0b0ff"), 30, 6.0, 0.6, 2.0, 1.2)
				sfx("crit", smb.pos, 2.0, 0.7)
				_stagger_reward(smb, ents_by_id.get(String(x[2]), null) as Hunter, String(x[3]))
		"anc":
			if String(x[1]) == "meteor":
				_announce("A meteor shower is coming down. Stars leave gems where they land", Color("ffcf8a"))
				return
			var aat := Vector3(x[2], x[3], x[4])
			ping(aat, Color("ffd25a"))
			_announce("A Glimmerkin appeared %s. Catch it before it escapes" % (direction_word(player.pos, aat) if player else ""), Color("ffd25a"))
		"brk":
			var bi := int(x[1])
			if bi >= 0 and bi < breaks.size():
				_break(breaks[bi], ents_by_id.get(String(x[2]), null), true)
		"wdrop":
			var seen := false
			for wp in wpicks:
				if wp["id"] == String(x[1]): seen = true
			if not seen:
				var nit := {}
				if x.size() > 9 and (String(x[8]) != "" or String(x[9]) != ""):
					nit = Loot.weapon(String(x[2]), int(x[3]), String(x[8]), String(x[9]))
				spawn_weapon(String(x[2]), int(x[3]), Vector3(x[4], x[5], x[6]), String(x[1]), false, int(x[7]) if x.size() > 7 else -1, nit)
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
		_tip("ability", "%s is your kin's ability. Fighting together fills the bond meter, and %s calls your kin's bond ultimate." % [Settings.key_cap("signature"), Settings.key_cap("ultimate")])
	if player.ult >= 1.0 and player.kin:
		var ud := Ultimate.def_for(player.kin)
		if ud: _tip("ult", "Your bond is full. %s calls %s." % [Settings.key_cap("ultimate"), ud.display_name])
	var k: Kin = player.kin
	if k == null:
		return
	if _tip_t > 9.0:
		var near_foe := false
		for f in foes_of(player.team):
			if player.flat_dist(f) < 9.0:
				near_foe = true; break
		if near_foe:
			_tip("throw", (Settings.key_cap("throw") + " throws %s at the cursor. A kin that hits a foe stuns it, and your shots crit stunned foes.") % k.rec.get("name", "your kin"))
	if k.state == "active":
		var a1 := k.runner.def_of("k1")
		var a2 := k.runner.def_of("k2")
		_tip("skill", "%s uses %s's %s. Stun or root a foe with your kin, then shoot it for a combo. %s throws it, and again calls it back to your shoulder." % [Settings.key_cap("signature"), k.rec.get("name", "your kin"), a1.display_name if a1 else "ability", Settings.key_cap("throw")])
	if not interact.is_empty() and interact["kind"] == "catch":
		_tip("catch", "Hold " + Settings.key_cap("interact") + " to catch it. Caught kin only come home if you extract.")
	if exits and not interact.is_empty() and interact["kind"] == "exit":
		match String(interact["x"]["kind"]):
			"dock": _tip("exit_dock", "Skiff docks: call the skiff at the horn beacon, survive the monsters it draws until it ties up, then stand on its deck before it leaves.")
			"hatch": _tip("exit_hatch", "Rift hatches open instantly and quietly with a Rift Key. Keys are rare loot (vaults, bosses, elites) and drop in your deathbox if you go down.")
			"outpost": _tip("exit_uplink", "Outposts: start the uplink and hold the yard while it charges. A rival standing in it stalls the charge. When it's done, step into the lift.")
	if player.downed:
		_tip("down", "You're down. Your kin will try to pick you up if it trusts you enough.")

# ------------------------------------------------------------------ aim indicators
# ---- ability previews: hold E, R or Q to see the reach and where it lands
var aim_hold := ""
var ind_range: MeshInstance3D
var ind_area: MeshInstance3D
var ind_fill: MeshInstance3D
var ind_line: MeshInstance3D
var ind_fan: MeshInstance3D
var ind_wall: MeshInstance3D
## [shape, reach, size]: self (around you), dash (where you'll end up), line (length, width),
## area (a circle at the cursor within reach), cone (length, cosine of the half angle)
const AIM := {
	"cloak": ["self", 0.0, 1.2], "mend": ["self", 0.0, 5.0], "fortify": ["self", 0.0, 1.6], "dome": ["self", 0.0, 3.6],
	"blink": ["dash", 6.0, 0.8], "rocketjump": ["dash", 7.0, 2.4], "tether": ["line", 14.0, 0.35], "hook": ["line", 9.0, 0.45],
	"ram": ["line", 6.0, 1.3], "vanish": ["self", 0.0, 1.2], "dance": ["self", 0.0, 9.0], "skypierce": ["line", 26.0, 1.8],
	"sanctuary": ["self", 0.0, 4.2], "anchor": ["dash", 10.0, 3.6], "barrage": ["area", 11.0, 3.0], "bulwark": ["self", 0.0, 4.0],
	"quake": ["cone", 8.0, 0.55], "well": ["area", 10.0, 4.5],
	"fireball": ["area", 9.0, 1.9], "wave": ["cone", 5.0, 0.55], "snare": ["area", 9.0, 2.2], "chain": ["area", 9.0, 1.2],
	"slam": ["area", 7.0, 2.0], "gust": ["self", 0.0, 2.8],
}

func _build_indicators() -> void:
	var mk := func(mesh: Mesh, mat: Material) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh; mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		return mi
	ind_range = mk.call(Models.flat_quad(2.0), Models.ring_mat(Color(1, 1, 1, 0.35), 0.015))
	ind_area = mk.call(Models.flat_quad(2.0), Models.ring_mat(Color(1, 1, 1, 0.9), 0.06))
	ind_fill = mk.call(Models.cyl(1.0, 1.0, 0.01, 40), Models.glow_mat(Color(1, 1, 1, 0.14)))
	ind_line = mk.call(Models.box(1.0, 0.01, 1.0), Models.glow_mat(Color(1, 1, 1, 0.22)))
	ind_fan = mk.call(ArrayMesh.new(), Models.glow_mat(Color(1, 1, 1, 0.2)))
	ind_wall = mk.call(Models.box(1.0, 0.02, 1.0), Models.glow_mat(Color(1, 1, 1, 0.9)))

func _fan_mesh(length: float, cos_half: float) -> ArrayMesh:
	var half := acos(clampf(cos_half, -1.0, 1.0))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 20
	for i in n:
		var a0 := -half + 2.0 * half * i / n
		var a1 := -half + 2.0 * half * (i + 1) / n
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(sin(a1), 0, -cos(a1)) * length)
		st.add_vertex(Vector3(sin(a0), 0, -cos(a0)) * length)
	var am := ArrayMesh.new()
	st.commit(am)
	return am

func _update_indicators(alpha: float) -> void:
	if ind_range == null:
		_build_indicators()
	for n in [ind_range, ind_area, ind_fill, ind_line, ind_fan, ind_wall]: n.visible = false
	var p := player
	if p == null or p.out or p.downed or paused or (aim_hold == "" and p.charge_frac() < 0.0):
		return
	var id := ""
	var col := Color.WHITE
	var spec: Array = []
	var from_kin := false
	if p.charge_frac() >= 0.0:
		# a charge-up: the lane grows as you hold
		var ud: AbilityDef = p.runner.def_of("utility")
		var sp0: Array = ud.aim_spec()
		spec = ["line", lerpf(float(sp0[1]) * 0.5, float(sp0[1]), p.charge_frac()), float(sp0[2]) * (1.0 + p.charge_frac())]
		col = ud.color.lerp(Color.WHITE, 0.4 * p.charge_frac())
	match aim_hold if spec.is_empty() else "":
		"secondary":
			var ud2: AbilityDef = p.runner.def_of("utility") if p.runner else null
			if ud2 == null: return
			spec = ud2.aim_spec(); col = ud2.color
		"gear1":
			var g0: Dictionary = p.gear[0]
			if g0.is_empty(): return
			var gdf := Gear.def_of(String(g0["id"]))
			spec = gdf.aim_spec(); col = gdf.color
		"signature", "kin_skill":
			if p.kin == null: return
			var kd: AbilityDef = (p.kin as Kin).runner.def_of("k1" if aim_hold == "signature" else "k2")
			if kd == null: return
			spec = kd.aim_spec(); col = kd.color
			from_kin = kd.from == "kin" and (p.kin as Kin).state == "active"
		"ultimate":
			var ud := Ultimate.def_for(p.kin) if p.kin else null
			if ud == null: return
			col = ud.color
			spec = ["self", 0.0, 3.5]
	if spec.is_empty():
		return
	var at := p.prev.lerp(p.pos, alpha)
	if from_kin:
		at = (p.kin as Kin).prev.lerp((p.kin as Kin).pos, alpha)
	var aim: Vector3 = p.inp["aim"]
	var d := Vector2(aim.x - at.x, aim.z - at.z)
	var dir := d.normalized() if d.length() > 0.1 else p.aim_dir()
	var reach: float = spec[1]
	var size: float = spec[2]
	var gy := at.y + 0.07
	var set_col := func(mi: MeshInstance3D, a: float) -> void:
		var mat = mi.material_override
		if mat is ShaderMaterial:
			mat.set_shader_parameter("color", Color(col, a))
	match String(spec[0]):
		"self":
			ind_area.visible = true; ind_fill.visible = true
			ind_area.global_position = Vector3(at.x, gy, at.z); ind_area.scale = Vector3.ONE * size
			ind_fill.global_position = Vector3(at.x, gy, at.z); ind_fill.scale = Vector3(size, 1, size)
		"area", "dash":
			var dist := minf(d.length(), reach)
			var c2 := Vector2(at.x, at.z) + dir * dist
			var g := world.ground_at(c2.x, c2.y)
			var cy: float = (g if g > World.VOID + 1.0 else at.y) + 0.07
			ind_range.visible = true
			ind_range.global_position = Vector3(at.x, gy, at.z); ind_range.scale = Vector3.ONE * reach
			ind_area.visible = true; ind_fill.visible = true
			ind_area.global_position = Vector3(c2.x, cy, c2.y); ind_area.scale = Vector3.ONE * size
			ind_fill.global_position = Vector3(c2.x, cy, c2.y); ind_fill.scale = Vector3(size, 1, size)
		"line":
			ind_line.visible = true
			var mid := Vector2(at.x, at.z) + dir * reach * 0.5
			ind_line.global_position = Vector3(mid.x, gy, mid.y)
			ind_line.rotation = Vector3(0, atan2(-dir.x, -dir.y), 0)
			ind_line.scale = Vector3(size, 1, reach)
			# and a tick across its far end so the length reads
			ind_wall.visible = true
			var tip := Vector2(at.x, at.z) + dir * reach
			ind_wall.global_position = Vector3(tip.x, gy + 0.01, tip.y)
			ind_wall.rotation = Vector3(0, atan2(-dir.x, -dir.y), 0)
			ind_wall.scale = Vector3(maxf(size * 1.8, 0.9), 1, 0.12)
		"wall":
			# the wall's own footprint, across your aim, where it will stand
			var front := spec.size() > 3 and String(spec[3]) == "front"
			var dist2 := reach if front else minf(d.length(), reach)
			var wd := dir
			if from_kin:
				var od := Vector2(aim.x - p.pos.x, aim.z - p.pos.z)
				if od.length() > 0.3: wd = od.normalized()
			var c3 := Vector2(at.x, at.z) + dir * dist2
			var g3 := world.ground_at(c3.x, c3.y)
			var cy3: float = (g3 if g3 > World.VOID + 1.0 else at.y) + 0.08
			if not front:
				ind_range.visible = true
				ind_range.global_position = Vector3(at.x, gy, at.z); ind_range.scale = Vector3.ONE * reach
			ind_wall.visible = true
			ind_wall.global_position = Vector3(c3.x, cy3, c3.y)
			ind_wall.rotation = Vector3(0, atan2(-wd.x, -wd.y), 0)
			ind_wall.scale = Vector3(size, 1, 0.55)
			ind_line.visible = true
			ind_line.global_position = Vector3(c3.x, cy3 - 0.01, c3.y) + Vector3(wd.x, 0, wd.y) * 0.5
			ind_line.rotation = Vector3(0, atan2(-wd.x, -wd.y), 0)
			ind_line.scale = Vector3(size, 1, 1.0)
		"cone":
			ind_fan.mesh = _fan_mesh(reach, size)
			ind_fan.visible = true
			ind_fan.global_position = Vector3(at.x, gy, at.z)
			ind_fan.rotation = Vector3(0, atan2(-dir.x, -dir.y), 0)
	for mi in [ind_range, ind_area, ind_fill, ind_line, ind_fan, ind_wall]:
		set_col.call(mi, 0.35 if mi == ind_range else (0.9 if mi in [ind_area, ind_wall] else 0.22))

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
	_update_indicators(alpha)
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
	elif k and k.state == "active" and k.runner.is_ready("k1") and k.ready_to_fight():
		# your kin's ability lands at the cursor, as far as it can reach from the kin: a faint ring
		# shows where it would go (clamped to its reach) so cursor distance reads as range
		var kd: AbilityDef = k.runner.def_of("k1")
		if kd:
			var spec: Array = kd.aim_spec()
			if String(spec[0]) == "area":
				var from_p: Vector3 = k.pos if kd.from == "kin" else at
				var t2 := Vector2(aim.x - from_p.x, aim.z - from_p.z)
				var reach := float(spec[1])
				var clamped := t2.length() > reach
				if clamped:
					t2 = t2.normalized() * reach
				var g2 := world.ground_at(from_p.x + t2.x, from_p.z + t2.y)
				if g2 > World.VOID + 1.0:
					aim_ring.visible = true
					aim_ring.global_position = Vector3(from_p.x + t2.x, g2 + 0.06, from_p.z + t2.y)
					aim_ring.scale = Vector3.ONE * maxf(0.6, float(spec[2]) / 0.6)
					aim_ring.material_override.set_shader_parameter("color", Color(kd.color, 0.35 if clamped else 0.22))
	if not (k and k.state == "active"):
		aim_ring.scale = Vector3.ONE
	if p.muzzle_t > 0.0:
		var dir2 := p.aim_dir()
		muzzle_light.global_position = Vector3(at.x + dir2.x * 0.8, at.y + 1.0, at.z + dir2.y * 0.8)
		muzzle_light.light_energy = 2.2
