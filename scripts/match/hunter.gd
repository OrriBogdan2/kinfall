class_name Hunter
extends Ent
## A player or bot hunter: movement, weapon, dash, jump, ledge grab, class signature, downed state.

const JUMP_V := 10.8
const DASH_SPEED := 19.0
const DASH_TIME := 0.17
const DASH_REGEN := 2.2
const LEDGE_REACH := 2.8
const LEDGE_CD := 1.2
const FLOAT_SPEED := 9.0
const GLIDE_FALL := 1.7
const GLIDE_SPEED := 9.6
const GLIDE_TIME := 6.0
const DROP_FALL := 5.0
const DROP_SPEED := 9.0
const REGEN := 7.0            # health per second once you've gone a while without getting hit

var pname := "Hunter"
var cls := "medium"
var cdat: Dictionary = {}
var wid := "repeater"
var wpn: Dictionary = {}
var ctrl := "bot"             # local | bot | remote
var inp := {"move": Vector2.ZERO, "aim": Vector3.ZERO, "fire": false, "dash": false, "jump": false,
	"throw": false, "skill": false, "sig": false, "interact": false, "reload": false, "tonic": false, "glide": false, "ult": false}
var base_speed := 5.4
var ammo := 12
var reload_t := 0.0
var fire_cd := 0.0
var dashes := 2.0
var roll_t := 0.0
var roll_dir := Vector2.ZERO
var inv_t := 0.0
var coyote := 0.0
var jump_buf := 0.0
var fly_t := 0.0
var mantle_cd := 0.0
var grap_cd := 0.0
var grap: Dictionary = {}       # floating back up a ledge
var push_t := 0.0
var last_gy := 0.0             # ground height where you last stood
var pad: Dictionary = {}        # jump-pad flight along a fixed arc
var kb_t := -9.0
var sig_cd := 0.0
var cloak_t := 0.0
var haste_t := 0.0
var fortify_t := 0.0
var shield := 0.0
var shield_t := 0.0
var recoil := 0.0
var walk_ph := 0.0
var downed := false
var down_hp := 0.0
var revive := 0.0
var out := false
var extracted := false
var extract_prog := 0.0
var kin: Ent = null
var gems := 0
var lost_gems := 0
var free_tonics := 0          # the guild forge's tonic: used first, never taken home
var seeds := {}
var caught: Array = []        # kin records caught this match
var kills := 0
var knocks := 0
var dmg_done := 0.0
var tonics := 0
var ai: Dictionary = {}
var muzzle_t := 0.0
var regen_wait := 0.0
var land_t := 0.0
var ghost_t := 0.0
var step_t := 0.0
var gliding := false
var glide_fuel := 1.0
var glide_max := GLIDE_TIME
var glide_cd := 0.0
var glide_k := 0.0             # how far the glider is unfolded, for the model
var wind_t := 0.0
var hero := "sage"
var perk := ""
var ult := 0.0                # 0..1, R is ready at 1
var crit_t := 0.0             # shots crit while this runs (Blink)
var charge: Dictionary = {}   # Ram
var acts: Array = []          # queued ability pieces, see Abil.tick
var acts_tele: Node3D = null
var idle_fire := 0.0
var dropping := false         # gliding down from the sky at the start of a match
var riding := false           # aboard the skyship, waiting to jump
var bless_t := 0.0
var lives := 1                # comes back this many times minus one before it's really out

const DEFAULT_HERO := {"light": "veil", "medium": "sage", "heavy": "bastion"}

func init_hunter(match_node: Node, id: String, team_id: int, class_id: String, name_txt: String, control: String, kit := {}) -> void:
	setup(match_node, id)
	kind = "hunter"
	team = team_id
	hero = String(kit.get("hero", ""))
	if not Data.HEROES.has(hero):
		hero = DEFAULT_HERO.get(class_id, "sage")
	cls = Data.HEROES[hero]["cls"]
	cdat = Data.CLASSES[cls]
	wid = String(kit.get("weapon", ""))
	if not cdat["weapons"].has(wid):
		wid = Data.HEROES[hero]["weapon"]
	wpn = Data.WEAPONS[wid]
	perk = String(kit.get("perk", ""))
	pname = name_txt
	ctrl = control
	max_hp = cdat["hp"] + (15 if perk == "toughskin" else 0); hp = max_hp
	if perk == "featherfall": glide_max = GLIDE_TIME * 1.6
	base_speed = cdat["speed"]
	dashes = max_dashes()
	ammo = wpn["mag"]
	r = 0.38 * float(cdat["scale"])
	set_model(Models.hunter(cls, Data.TEAM_COLORS[team % Data.TEAM_COLORS.size()], wid, hero))

func max_dashes() -> float:
	return float(cdat["dashes"]) + (1.0 if shoulder() == "updraft" else 0.0) + (1.0 if perk == "secondwind" else 0.0)

## The shoulder passive is active once the kin has settled on your shoulder.
func shoulder() -> String:
	if kin and not kin.dead and kin.state == "shoulder" and kin.settle >= 1.0:
		return Data.KIN[kin.species]["shoulder"]
	return ""

func mass() -> float:
	return float(cdat.get("mass", 1.0)) * (2.0 if shoulder() == "bedrock" else 1.0)

func hittable() -> bool:
	return not dead and not out and not extracted and not riding

func targetable() -> bool:
	return hittable() and not downed and cloak_t <= 0.0 and not dropping

func is_local() -> bool:
	return ctrl == "local"

func aim_dir() -> Vector2:
	var d := Vector2(inp["aim"].x - pos.x, inp["aim"].z - pos.z)
	return d.normalized() if d.length() > 0.05 else Vector2(sin(face), cos(face)) * -1.0

# ------------------------------------------------------------------ damage
func _mitigate(dmg: float, by: Ent, opts: Dictionary) -> float:
	if (inv_t > 0.0 or dropping) and opts.get("src", "") != "fall":
		return 0.0
	if ctrl == "local" and Game.god:
		return 0.0
	var d := dmg
	if ctrl == "local" and m.opts.get("tutorial", false):
		d *= 0.35
	if hero == "bastion" and hp > max_hp * 0.5:
		d *= 0.9
	if shoulder() == "bedrock":
		d *= 0.85
	if downed:
		down_hp -= d
		flash_t = 0.1
		if down_hp <= 0.0 and not remote:
			m.eliminate(self, by, "finished")
		return 0.0
	if shield > 0.0:
		var a := minf(shield, d)
		shield -= a; d -= a
		if d <= 0.0:
			flash_t = 0.06
			m.fx.number(pos + Vector3(0, 1.6, 0), a, Color("cfe8ff"), false)
			return 0.0
	regen_wait = 5.0
	if gliding and d > 0.0:
		gliding = false
		glide_cd = 0.8
		m.fx.burst(pos + Vector3(0, 1.6, 0), Color("f3eee2"), 10, 3.0, 0.4, 8.0)
	if extract_prog > 0.0:
		extract_prog = 0.0
	return d

func impulse(kbv: Vector2, lift := -1.0) -> void:
	if fortify_t > 0.0:
		return
	var k := kbv * (0.5 if shoulder() == "bedrock" else 1.0)
	if k.length() / mass() > 4.0:
		kb_t = m.time
	super.impulse(k, lift)

func _on_zero(by: Ent, opts: Dictionary) -> void:
	if remote or downed:
		return
	m.knock(self, by, opts)

# ------------------------------------------------------------------ actions
func do_jump() -> void:
	if downed or stun_t > 0.0 or grap.size() > 0 or out:
		return
	if pad.size() > 0:
		# press jump mid-flight off a jump pad and the glider opens, keeping the launch's speed
		if float(pad["t"]) > 0.12 and can_glide():
			pad = {}
			vel.y = minf(vel.y, 2.0)
			_open_glider()
		return
	if grounded or coyote > 0.0:
		vel.y = JUMP_V
		grounded = false
		coyote = 0.0
		m.sfx("jump", pos, -6.0)
		return
	# already in the air: a second press opens the glider straight away, rising or falling
	if not gliding and can_glide():
		_open_glider()
		return
	jump_buf = 0.12

func can_glide() -> bool:
	return not grounded and roll_t <= 0.0 and fly_t <= 0.0 and glide_cd <= 0.0 and not downed and stun_t <= 0.0 \
		and m.time - kb_t > 0.4 and glide_fuel > 0.15 and not dropping and charge.is_empty()

func _open_glider() -> void:
	gliding = true
	grounded = false
	m.sfx("glide", pos, -4.0)
	m.fx.burst(pos + Vector3(0, 1.7, 0), Color("f3eee2"), 8, 2.0, 0.35, 0.0)

func do_dash() -> void:
	if downed or stun_t > 0.0 or root_t > 0.0 or out or dashes < 1.0 or roll_t > 0.0 or grap.size() > 0 or pad.size() > 0:
		return
	var d: Vector2 = inp["move"]
	if d.length() < 0.1:
		d = aim_dir()
	roll_dir = d.normalized()
	dashes -= 1.0
	roll_t = DASH_TIME
	inv_t = maxf(inv_t, 0.14)
	fly_t = 0.0
	m.sfx("dash", pos, -4.0)
	m.fx.dash_trail(self)

func can_fire() -> bool:
	return not (reload_t > 0.0 or roll_t > 0.0 or downed or out or stun_t > 0.0 or grap.size() > 0 or gliding or charge.size() > 0)

func fire() -> void:
	if not can_fire() or fire_cd > 0.0:
		return
	if ammo <= 0:
		start_reload()
		return
	if cloak_t > 0.0:
		cloak_t = 0.0
		m.sfx("cloak", pos, -8.0)
	var rate: float = wpn["rate"] * (0.8 if shoulder() == "charge" else 1.0)
	fire_cd = rate
	idle_fire = 0.0
	ammo -= 1
	recoil = 1.0
	muzzle_t = 0.05
	var dir := aim_dir()
	var a := atan2(dir.y, dir.x) + randf_range(-1.0, 1.0) * float(wpn["spread"])
	var shot_y := pos.y + 0.95 * float(cdat["scale"])
	var start := Vector3(pos.x + cos(a) * 0.6, shot_y, pos.z + sin(a) * 0.6)
	var spd: float = wpn["speed"]
	var life: float = float(wpn["range"]) / spd
	var extra := {"kb": wpn["kb"]}
	if wpn.has("boom"):
		var aim: Vector3 = inp["aim"]
		var dist := clampf(Vector2(aim.x - pos.x, aim.z - pos.z).length(), 1.5, wpn["range"])
		life = dist / spd
		extra["boom"] = wpn["boom"]; extra["boom_kb"] = wpn["boom_kb"]
	var sp := shoulder()
	if crit_t > 0.0 or (hero == "veil" and cloak_t > 0.0):
		extra["crit"] = true
	if hero == "kestrel":
		extra["far"] = 9.0
	if hero == "pyra" and extra.has("boom_kb"):
		extra["boom_kb"] = float(extra["boom_kb"]) * 1.2
	if sp == "kindle": extra["burn"] = 4.0
	if sp == "briar": extra["slow"] = 0.7
	m.spawn_shot(self, start, Vector2(cos(a), sin(a)) * spd, wpn["dmg"] * m.dmg_mult(self), life, wpn["size"], wpn["color"], extra)
	m.sfx(wpn["sfx"], pos, -2.0 if is_local() else -6.0)
	if ammo <= 0:
		start_reload()

func start_reload() -> void:
	if reload_t > 0.0 or ammo >= int(wpn["mag"]) or downed:
		return
	reload_t = float(wpn["reload"]) * (0.8 if shoulder() == "charge" else 1.0) * (0.7 if perk == "quickhands" else 1.0)
	m.sfx("reload", pos, -8.0)

func use_signature() -> void:
	Abil.use_e(self)

func _old_signature() -> void:
	match cdat["sig"]:
		"cloak":
			cloak_t = 3.0; haste_t = 3.0
			m.sfx("cloak", pos, -2.0)
			m.fx.burst(pos + Vector3(0, 0.8, 0), Color("c9bcff"), 18, 4.0)
		"mend":
			m.sfx("heal", pos, 0.0)
			m.fx.ring(pos, 5.0, Color("9ee2a0"), 0.45)
			for o in m.hunters:
				if o.team == team and not o.out and o.flat_dist(self) < 5.0:
					if o.downed:
						o.revive = minf(0.95, o.revive + 0.5)
					else:
						o.heal(35.0)
				if o.team == team and o.kin and o.kin.state == "active" and o.kin.flat_dist(self) < 5.0:
					o.kin.hp = minf(o.kin.max_hp, o.kin.hp + 35.0)
		"fortify":
			shield = maxf(shield, 60.0); shield_t = 5.0; fortify_t = 5.0
			m.sfx("shield", pos, 0.0)
			m.fx.ring(pos, 1.6, Color("e6dbc4"), 0.3)

func heal(n: float) -> void:
	if downed or out:
		return
	if remote:
		m.net_event(["heal", nid, n])
		return
	var before := hp
	hp = minf(max_hp, hp + n)
	if hp - before > 1.0:
		m.fx.number(pos + Vector3(0, 1.6, 0), hp - before, Color("8ff0a0"), false, "+")

func use_tonic() -> void:
	if tonics <= 0 or downed or hp >= max_hp:
		return
	tonics -= 1
	free_tonics = maxi(0, free_tonics - 1)
	heal(45.0)
	m.sfx("heal", pos, -2.0)

func launch_to(target: Vector3, t: float) -> void:
	vel.x = (target.x - pos.x) / t
	vel.z = (target.z - pos.z) / t
	vel.y = (target.y - pos.y) / t + 0.5 * GRAV * t
	grounded = false
	fly_t = t + 0.3
	roll_t = 0.0

# ------------------------------------------------------------------ simulation
func sim(dt: float) -> void:
	prev = pos
	if out or extracted:
		return
	if riding:
		# aboard the skyship: you go where it goes until you jump
		if remote:
			net_follow(dt)
		else:
			pos = m.ship_pos() + Vector3(0, -1.2, 0)
			prev = pos
			vel = Vector3.ZERO
			if ctrl == "local" and inp["jump"]:
				m.ship_jump(self)
			inp["jump"] = false
		return
	tick_status(dt)
	for k in ["inv_t", "fire_cd", "coyote", "jump_buf", "mantle_cd", "grap_cd", "sig_cd", "cloak_t", "haste_t", "fortify_t", "recoil", "muzzle_t", "regen_wait", "land_t", "glide_cd", "bless_t", "crit_t"]:
		set(k, maxf(0.0, get(k) - dt))
	if shield_t > 0.0:
		shield_t -= dt
		if shield_t <= 0.0: shield = 0.0
	if reload_t > 0.0:
		reload_t -= dt
		if reload_t <= 0.0:
			ammo = wpn["mag"]
	if dashes < max_dashes():
		dashes = minf(max_dashes(), dashes + dt / DASH_REGEN)
	if shoulder() == "spring" and not downed:
		hp = minf(max_hp, hp + 3.0 * dt)
	# out of the fight for a few seconds, you patch yourself up
	if not downed and regen_wait <= 0.0 and hp < max_hp and not remote:
		hp = minf(max_hp, hp + REGEN * dt)
	if remote:
		net_follow(dt)
		return
	if not downed and not dropping:
		ult = minf(1.0, ult + dt / 110.0 * (1.3 if perk == "overcharge" else 1.0))
	if not downed:
		Abil.tick(self, dt)
	# reload by itself once you stop shooting for a moment
	idle_fire += dt
	if idle_fire > 1.3 and ammo < int(wpn["mag"]) and reload_t <= 0.0 and not inp["fire"]:
		start_reload()
	if downed:
		down_hp -= Data.MATCH["bleed"] * dt
		if down_hp <= 0.0:
			m.eliminate(self, last_hit_by, "bled out")
			return
	# inputs
	if inp["dash"]: do_dash()
	if inp["jump"]: do_jump()
	if inp["sig"]: use_signature()
	if inp["reload"]: start_reload()
	if inp["tonic"]: use_tonic()
	if inp["ult"]: Abil.use_r(self)
	if inp["fire"]: fire()
	inp["dash"] = false; inp["jump"] = false; inp["sig"] = false; inp["reload"] = false; inp["tonic"] = false; inp["ult"] = false
	_physics(dt)
	var ad := aim_dir()
	var want := atan2(-ad.x, -ad.y)
	if roll_t > 0.0:
		want = atan2(-roll_dir.x, -roll_dir.y)
	face = lerp_angle(face, want, minf(1.0, dt * 20.0))

func pad_launch(to: Vector3) -> void:
	var d := Vector2(to.x - pos.x, to.z - pos.z).length()
	pad = {"from": pos, "to": to, "t": 0.0, "dur": clampf(d / 12.0, 0.7, 1.5), "h": maxf(pos.y, to.y) - pos.y + 2.5 + d * 0.12}
	roll_t = 0.0
	grap = {}
	grounded = false

func _pad_fly(dt: float) -> void:
	pad["t"] += dt
	var k := clampf(pad["t"] / pad["dur"], 0.0, 1.0)
	var a: Vector3 = pad["from"]; var b: Vector3 = pad["to"]
	var y := lerpf(a.y, b.y, k) + 4.0 * float(pad["h"]) * k * (1.0 - k)
	var np := Vector3(lerpf(a.x, b.x, k), y, lerpf(a.z, b.z, k))
	vel = (np - pos) / maxf(dt, 0.0001)
	pos = np
	if k >= 1.0:
		pos = b
		vel = Vector3(vel.x, 0.0, vel.z).limit_length(base_speed)
		grounded = true
		pad = {}
		squash = 0.3
		m.fx.dust(pos, 8)
		m.sfx("land", pos, -8.0)

func _physics(dt: float) -> void:
	if pad.size() > 0:
		_pad_fly(dt)
		return
	if grap.size() > 0:
		_grapple(dt)
		return
	var mv: Vector2 = inp["move"] if stun_t <= 0.0 and root_t <= 0.0 else Vector2.ZERO
	var spd := base_speed * (1.35 if haste_t > 0.0 else 1.0) * (0.45 if downed else 1.0) * (0.65 if slow_t > 0.0 else 1.0) * (0.88 if reload_t > 0.0 else 1.0)
	var hv := Vector2(vel.x, vel.z)
	var cur := hv.length()
	if charge.size() > 0:
		charge["t"] -= dt
		hv = charge["dir"] * 21.0
		Abil.charge_hits(self)
		if charge["t"] <= 0.0:
			hv = charge["dir"] * spd
			charge = {}
		if int(m.time * 30.0) % 2 == 0:
			m.fx.dust(pos, 2)
	elif roll_t > 0.0:
		roll_t -= dt
		hv = roll_dir * DASH_SPEED
		if roll_t <= 0.0:
			hv = roll_dir * spd * 1.1
	elif fly_t > 0.0:
		fly_t -= dt
	elif gliding:
		# the glider keeps the speed you opened it with and bleeds it off slowly, like Supervive's
		var gs := DROP_SPEED if dropping else GLIDE_SPEED
		var gw := mv * maxf(gs, minf(cur, gs * 1.6))
		if mv.length() < 0.1:
			gw = hv.normalized() * minf(cur, gs * 0.7) if cur > 0.1 else Vector2.ZERO
		hv += (gw - hv) * (1.0 - exp(-(1.6 if cur > gs else 2.6) * dt))
	else:
		var wish := mv * spd
		var over := cur > spd * 1.15
		var k := (2.6 if over else 16.0) if grounded else (1.5 if over else 3.5)
		hv += (wish - hv) * (1.0 - exp(-k * dt))
	vel.x = hv.x; vel.z = hv.y
	_update_glide(dt)
	if gliding:
		vel.y = lerpf(vel.y, -(DROP_FALL if dropping else GLIDE_FALL), 1.0 - exp(-7.0 * dt))
	elif not grounded:
		vel.y -= GRAV * (1.3 if vel.y < 0.0 and fly_t <= 0.0 else 1.0) * dt
	var guard := grounded and roll_t <= 0.0 and hv.length() <= spd * 1.25
	# horizontal with walls; mantle onto ledges you run or fall into
	var nx := pos.x + vel.x * dt
	var b1: float = m.world.occupy(nx, pos.z, r, pos.y, guard)
	if b1 == 0.0: pos.x = nx
	elif b1 > 0.0 or b1 == -1.0: vel.x = 0.0 if b1 == -1.0 else vel.x * -0.1
	var nz := pos.z + vel.z * dt
	var b2: float = m.world.occupy(pos.x, nz, r, pos.y, guard)
	if b2 == 0.0: pos.z = nz
	elif b2 > 0.0 or b2 == -1.0: vel.z = 0.0 if b2 == -1.0 else vel.z * -0.1
	var blk := maxf(b1, b2)
	if not grounded and blk > 0.0 and blk < pos.y + 2.4 and mantle_cd <= 0.0 and blk - pos.y < World.BLOCK_H - 0.1:
		vel.y = sqrt(2.0 * GRAV * (blk - pos.y + 0.3))
		mantle_cd = 0.45
	var g := ground()
	if grounded and g < pos.y - 0.05:
		grounded = false
		vel.y = minf(vel.y, 0.0)
		coyote = 0.12
	if not grounded:
		var fv := vel.y
		pos.y += vel.y * dt
		if g > World.VOID + 1.0 and vel.y <= 0.0 and pos.y <= g and pos.y > g - 1.25:
			pos.y = g
			vel.y = 0.0
			grounded = true
			fly_t = 0.0
			if gliding:
				gliding = false
				m.fx.dust(pos, 5)
			if dropping:
				dropping = false
				m.on_drop_landed(self)
			if fv < -11.0 or cur > spd * 1.3:
				m.fx.dust(pos, 6)
				squash = 0.35
				land_t = 0.2
				m.sfx("land", pos, -10.0)
			if jump_buf > 0.0:
				jump_buf = 0.0
				vel.y = JUMP_V
				grounded = false
	else:
		pos.y = g
	if grounded:
		last_gy = pos.y
	_try_ledge_grab(dt)
	if pos.y < -14.0:
		fall_out()

## Hold jump while falling to open the glider. It folds when you land, run out, dash, or get hit.
func _update_glide(dt: float) -> void:
	if dropping:
		# the opening drop: the glider stays open until you land, or until you sink below the islands
		gliding = not grounded
		if pos.y < -1.5:
			dropping = false
			glide_fuel = 1.0
		return
	if grounded:
		glide_fuel = minf(1.0, glide_fuel + dt / 1.2)
	var can: bool = not grounded and roll_t <= 0.0 and fly_t <= 0.0 and glide_cd <= 0.0 and not downed and stun_t <= 0.0 \
		and m.time - kb_t > 0.4 and glide_fuel > 0.0 and pad.is_empty()
	var want: bool = inp.get("glide", false)
	if gliding:
		if not want or not can:
			gliding = false
			if glide_fuel <= 0.0:
				glide_cd = 0.5
		else:
			glide_fuel = maxf(0.0, glide_fuel - dt / glide_max)
	elif want and can and vel.y < 1.5 and glide_fuel > 0.15:
		gliding = true
		m.sfx("glide", pos, -4.0)
		m.fx.burst(pos + Vector3(0, 1.7, 0), Color("f3eee2"), 8, 2.0, 0.35, 0.0)

# Ledge float: touch the side of any ground above you while you're still alive and you float
# back up onto it, the way Supervive does it. Walking into a step up a few terraces high does
# the same after a short push. Getting launched hard still carries you past the edge.
func _try_ledge_grab(dt: float) -> void:
	if grap.size() > 0 or pad.size() > 0 or fly_t > 0.0 or downed or charge.size() > 0 or dropping or pos.y < -12.0 or (grounded and stun_t > 0.0):
		push_t = 0.0
		return
	var w: World = m.world
	var mv: Vector2 = inp["move"]
	var reach := 0.0
	var max_rise := 12.0
	if grounded:
		# a wall of ground in front of you: lean on it for a moment and you go up
		if mv.length() < 0.5 or grap_cd > 0.0:
			push_t = 0.0
			return
		var probe := Vector2(pos.x, pos.z) + mv.normalized() * (r + 0.35)
		var g2 := w.ground_at(probe.x, probe.y)
		if w.is_block(probe.x, probe.y) or g2 <= pos.y + World.STEP or g2 - pos.y > World.LEVEL * 4.0 + 0.05:
			push_t = 0.0
			return
		push_t += dt
		if push_t < 0.2:
			return
		reach = r + 0.6
		max_rise = World.LEVEL * 4.0 + 0.1
	else:
		push_t = 0.0
		# a hard launch carries you a moment before you can catch anything
		if vel.y > 1.0 or grap_cd > 0.0 or (m.time - kb_t < 0.3 and Vector2(vel.x, vel.z).length() > 8.0):
			return
		reach = LEDGE_REACH if over_void() else r + 0.45
	var void_here := over_void()
	var best := {}; var bd := 1e9
	for z in range(int(floor(pos.z - reach)), int(floor(pos.z + reach)) + 1):
		for x in range(int(floor(pos.x - reach)), int(floor(pos.x + reach)) + 1):
			if not w.inb(x, z) or w.kind[w.idx(x, z)] != World.T_GROUND:
				continue
			var gz := w.level[w.idx(x, z)] * World.LEVEL
			var dz := gz - pos.y
			if dz < (0.05 if not grounded and over_void() else World.STEP + 0.05) or dz > max_rise:
				continue
			var ex := clampf(pos.x, x + 0.06, x + 0.94); var ez := clampf(pos.z, z + 0.06, z + 0.94)
			var d := Vector2(ex - pos.x, ez - pos.z).length()
			var toward := Vector2(ex - pos.x, ez - pos.z)
			if grounded and toward.dot(mv) <= 0.0:
				continue
			if not grounded and not void_here:
				# off the void, only a wall you're heading into and that rises above where you last stood:
				# hopping down a terrace must not float you back up it
				if gz <= last_gy + World.STEP or (toward.dot(mv) <= 0.0 and toward.dot(Vector2(vel.x, vel.z)) <= 0.0):
					continue
			if d < bd and d < reach:
				bd = d
				best = {"x": x, "z": z, "gz": gz, "ex": ex, "ez": ez}
	if best.is_empty():
		return
	var cx: float = best["x"] + 0.5; var cz: float = best["z"] + 0.5
	var a := atan2(cz - best["ez"], cx - best["ex"])
	var land := Vector3(cx, best["gz"], cz)
	for k in [1.25, 0.9, 0.6]:
		var lx: float = best["ex"] + cos(a) * k; var lz: float = best["ez"] + sin(a) * k
		if absf(w.ground_at(lx, lz) - best["gz"]) < 0.1 and not w.is_block(lx, lz):
			land = Vector3(lx, best["gz"], lz); break
	if w.is_block(land.x, land.z):
		return
	grap = {"ex": best["ex"], "ez": best["ez"], "gz": best["gz"], "land": land, "t": 0.0, "fx": 0.0}
	grap_cd = LEDGE_CD
	push_t = 0.0
	gliding = false
	roll_t = 0.0
	vel = Vector3.ZERO
	m.sfx("grab", pos, -2.0)
	m.on_ledge_grab(self)

## Floating up the side: rise to the lip, drift onto it, then a small hop onto the top.
func _grapple(dt: float) -> void:
	grap["t"] += dt
	var tz: float = grap["gz"] + 0.5
	var rise := clampf(tz - pos.y, -FLOAT_SPEED * dt, FLOAT_SPEED * dt)
	pos.y += rise
	var hd := Vector2(grap["ex"] - pos.x, grap["ez"] - pos.z)
	var hs := 7.0 * dt
	if hd.length() <= hs: pos.x = grap["ex"]; pos.z = grap["ez"]
	else:
		var hn := hd.normalized() * hs
		pos.x += hn.x; pos.z += hn.y
	vel = Vector3.ZERO
	grounded = false
	grap["fx"] -= dt
	if grap["fx"] <= 0.0:
		grap["fx"] = 0.07
		m.fx.burst(pos + Vector3(0, 0.6, 0), Color("cfeaff"), 2, 1.2, 0.35, 0.0)
	if (absf(tz - pos.y) < 0.02 and hd.length() < 0.05) or grap["t"] > 2.0:
		pos = Vector3(grap["ex"], maxf(pos.y, tz), grap["ez"])
		var land: Vector3 = grap["land"]
		grap = {}
		pad = {"from": pos, "to": land, "t": 0.0, "dur": 0.22, "h": 0.4}

# ------------------------------------------------------------------ visuals
func render(delta: float, alpha: float) -> void:
	super.render(delta, alpha)
	visible = not out and not extracted and not riding
	if not model:
		return
	model.rotation.y = face
	var rig: Node3D = model.get_node("Rig")
	var torso: Node3D = rig.get_node("Torso")
	var legs: Node3D = rig.get_node("Legs")
	var hv := Vector2(vel.x, vel.z)
	var spd := hv.length()
	var ph0 := walk_ph
	walk_ph += delta * spd * 2.2
	if grounded and spd > 1.0 and int(walk_ph / PI) != int(ph0 / PI) and not downed:
		Sfx.step(pos, -14.0 if is_local() else -20.0)
	var sw := sin(walk_ph) * clampf(spd / 5.0, 0.0, 1.0) * 0.6 if grounded else 0.35
	legs.get_node("LegL").rotation.x = sw
	legs.get_node("LegR").rotation.x = -sw
	# lean into movement relative to facing
	var fwd := Vector2(-sin(face), -cos(face))
	var right := Vector2(cos(face), -sin(face))
	var lean_f := clampf(hv.dot(fwd) / 12.0, -0.3, 0.3)
	var lean_s := clampf(hv.dot(right) / 12.0, -0.25, 0.25)
	torso.rotation.x = -lean_f - recoil * 0.12
	torso.rotation.z = -lean_s
	var bob := absf(sin(walk_ph)) * 0.05 * clampf(spd / 5.0, 0.0, 1.0) if grounded else 0.0
	torso.position.y = 0.42 + bob
	var sq := squash
	var stretch := 0.0
	var tc: Color = Data.TEAM_COLORS[team % Data.TEAM_COLORS.size()]
	if roll_t > 0.0:
		stretch = 0.3
		torso.rotation.x = -0.55          # dive forward into the dash
		legs.get_node("LegL").rotation.x = 0.9
		legs.get_node("LegR").rotation.x = 0.5
		ghost_t -= delta
		if ghost_t <= 0.0 and model.visible:
			ghost_t = 0.028
			m.fx.ghost(position, face, tc, float(cdat["scale"]))
	elif gliding:
		# while dropping in, a ring on the ground shows where you'll land
		if dropping and is_local():
			step_t -= delta
			if step_t <= 0.0:
				step_t = 0.22
				var gy: float = m.world.ground_at(pos.x, pos.z)
				if gy > World.VOID + 1.0:
					m.fx.ring(Vector3(pos.x, gy, pos.z), 1.1, Color(1, 1, 1, 0.7), 0.25)
		# hang under the glider, legs trailing
		torso.rotation.x = -0.35
		torso.rotation.z = -lean_s * 1.6
		legs.get_node("LegL").rotation.x = 0.5 + sin(m.time * 6.0) * 0.12
		legs.get_node("LegR").rotation.x = 0.7 - sin(m.time * 6.0) * 0.12
		wind_t -= delta
		if wind_t <= 0.0:
			wind_t = 0.09
			m.fx.burst(pos + Vector3(randf_range(-0.8, 0.8), 1.9, randf_range(-0.4, 0.4)), Color(1, 1, 1, 0.5), 2, 1.0, 0.4, -1.0, 0.7, Vector3(-vel.x, 0, -vel.z).normalized(), 20.0)
	elif not grounded and pad.is_empty():
		# tuck the legs in the air
		legs.get_node("LegL").rotation.x = -0.6
		legs.get_node("LegR").rotation.x = 0.4
		stretch = clampf(vel.y / 30.0, -0.1, 0.18)
	# a flinch when hit
	if flash_t > 0.0:
		torso.rotation.x += flash_t * 2.5
	# little puffs of dust while running
	if grounded and spd > 4.0 and not downed:
		step_t -= delta
		if step_t <= 0.0:
			step_t = 0.32
			m.fx.dust(pos, 2)
	rig.scale = Vector3(1.0 + sq * 0.35 - stretch * 0.3, 1.0 - sq * 0.4 + stretch * 0.15, 1.0 + sq * 0.35 + stretch * 0.5)
	if downed:
		rig.rotation.x = lerpf(rig.rotation.x, -1.35, delta * 8.0)
		rig.position.y = 0.15
	else:
		rig.rotation.x = lerpf(rig.rotation.x, 0.0, delta * 10.0)
		rig.position.y = 0.0
	glide_k = move_toward(glide_k, 1.0 if gliding else 0.0, delta * (7.0 if gliding else 9.0))
	var gl: Node3D = torso.get_node("Glider")
	gl.visible = glide_k > 0.02
	if gl.visible:
		var ek := 1.0 - pow(1.0 - glide_k, 3.0)
		gl.scale = Vector3(ek * (1.0 + sin(m.time * 9.0) * 0.02), ek, ek)
		gl.rotation.x = 0.35 * ek - 0.1
	var halo := torso.get_node_or_null("Halo")
	if halo:
		halo.rotation.y += delta * 2.0
		halo.position.y = 1.26 + sin(m.time * 3.0) * 0.03
	var gun: Node3D = torso.get_node("Gun")
	gun.position.z = -0.18 + recoil * 0.08
	gun.visible = not downed
	# cloaked: allies see a shimmer, enemies see nothing unless very close
	var lp: Ent = m.local_player()
	var see := true
	if cloak_t > 0.0:
		if lp and lp.team != team:
			see = lp.flat_dist(self) < 2.2 and int(m.time * 10.0) % 3 == 0
		else:
			see = int(m.time * 14.0) % 3 != 0
	model.visible = see
	var ring := model.get_node("TeamRing") as MeshInstance3D
	ring.visible = not downed
