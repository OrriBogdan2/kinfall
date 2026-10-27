class_name Hunter
extends Ent
## A player or bot hunter: movement, weapon, dash, jump, ledge grab, class signature, downed state.

const JUMP_V := 10.8
const DASH_SPEED := 19.0
const DASH_TIME := 0.17
const DASH_REGEN := 2.2
const LEDGE_REACH := 3.4
const LEDGE_CD := 5.0
const GLIDE_FALL := 2.3
const GLIDE_SPEED := 7.4
const GLIDE_TIME := 3.2
const DROP_FALL := 5.0
const DROP_SPEED := 9.0

var pname := "Hunter"
var cls := "medium"
var cdat: Dictionary = {}
var wid := "repeater"
var wpn: Dictionary = {}
var ctrl := "bot"             # local | bot | remote
var inp := {"move": Vector2.ZERO, "aim": Vector3.ZERO, "fire": false, "dash": false, "jump": false,
	"throw": false, "skill": false, "sig": false, "interact": false, "reload": false, "tonic": false, "glide": false}
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
var grap: Dictionary = {}
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
var dropping := false         # gliding down from the sky at the start of a match
var bless_t := 0.0

func init_hunter(match_node: Node, id: String, team_id: int, class_id: String, name_txt: String, control: String) -> void:
	setup(match_node, id)
	kind = "hunter"
	team = team_id
	cls = class_id
	cdat = Data.CLASSES[cls]
	wid = cdat["weapon"]
	wpn = Data.WEAPONS[wid]
	pname = name_txt
	ctrl = control
	max_hp = cdat["hp"]; hp = max_hp
	base_speed = cdat["speed"]
	dashes = max_dashes()
	ammo = wpn["mag"]
	r = 0.38 * float(cdat["scale"])
	set_model(Models.hunter(cls, Data.TEAM_COLORS[team % Data.TEAM_COLORS.size()], wid))

func max_dashes() -> float:
	return float(cdat["dashes"]) + (1.0 if shoulder() == "updraft" else 0.0)

## The shoulder passive is active once the kin has settled on your shoulder.
func shoulder() -> String:
	if kin and not kin.dead and kin.state == "shoulder" and kin.settle >= 1.0:
		return Data.KIN[kin.species]["shoulder"]
	return ""

func mass() -> float:
	return float(cdat.get("mass", 1.0)) * (2.0 if shoulder() == "bedrock" else 1.0)

func hittable() -> bool:
	return not dead and not out and not extracted

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
	var d := dmg
	if ctrl == "local" and m.opts.get("tutorial", false):
		d *= 0.35
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
	regen_wait = 4.0
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
	if downed or stun_t > 0.0 or grap.size() > 0 or pad.size() > 0 or out:
		return
	if grounded or coyote > 0.0:
		vel.y = JUMP_V
		grounded = false
		coyote = 0.0
		m.sfx("jump", pos, -6.0)
		return
	jump_buf = 0.12

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
	return not (reload_t > 0.0 or roll_t > 0.0 or downed or out or stun_t > 0.0 or grap.size() > 0 or gliding)

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
	if sp == "kindle": extra["burn"] = 4.0
	if sp == "briar": extra["slow"] = 0.7
	m.spawn_shot(self, start, Vector2(cos(a), sin(a)) * spd, wpn["dmg"] * m.dmg_mult(self), life, wpn["size"], wpn["color"], extra)
	m.sfx(wpn["sfx"], pos, -2.0 if is_local() else -6.0)
	if ammo <= 0:
		start_reload()

func start_reload() -> void:
	if reload_t > 0.0 or ammo >= int(wpn["mag"]) or downed:
		return
	reload_t = float(wpn["reload"]) * (0.8 if shoulder() == "charge" else 1.0)
	m.sfx("reload", pos, -8.0)

func use_signature() -> void:
	if sig_cd > 0.0 or downed or out:
		return
	sig_cd = Data.SIGS[cdat["sig"]]["cd"]
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
	tick_status(dt)
	for k in ["inv_t", "fire_cd", "coyote", "jump_buf", "mantle_cd", "grap_cd", "sig_cd", "cloak_t", "haste_t", "fortify_t", "recoil", "muzzle_t", "regen_wait", "land_t", "glide_cd", "bless_t"]:
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
	if remote:
		net_follow(dt)
		return
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
	if inp["fire"]: fire()
	inp["dash"] = false; inp["jump"] = false; inp["sig"] = false; inp["reload"] = false; inp["tonic"] = false
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
	if roll_t > 0.0:
		roll_t -= dt
		hv = roll_dir * DASH_SPEED
		if roll_t <= 0.0:
			hv = roll_dir * spd * 1.1
	elif fly_t > 0.0:
		fly_t -= dt
	elif gliding:
		var gs := DROP_SPEED if dropping else GLIDE_SPEED
		var gw := mv * gs
		if mv.length() < 0.1:
			gw = hv.normalized() * minf(cur, gs * 0.6) if cur > 0.1 else Vector2.ZERO
		hv += (gw - hv) * (1.0 - exp(-3.2 * dt))
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
	_try_ledge_grab()
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
		and m.time - kb_t > 0.6 and glide_fuel > 0.0
	var want: bool = inp.get("glide", false)
	if gliding:
		if not want or not can:
			gliding = false
			if glide_fuel <= 0.0:
				glide_cd = 0.5
		else:
			glide_fuel = maxf(0.0, glide_fuel - dt / glide_max)
	elif want and can and vel.y < 0.0 and glide_fuel > 0.15:
		gliding = true
		m.sfx("glide", pos, -4.0)
		m.fx.burst(pos + Vector3(0, 1.7, 0), Color("f3eee2"), 8, 2.0, 0.35, 0.0)

# ledge grab: slip or get nudged off an edge and a grapple pulls you back. Big knockbacks still kill.
func _try_ledge_grab() -> void:
	if gliding or grounded or fly_t > 0.0 or grap.size() > 0 or vel.y >= 0.0 or stun_t > 0.0 or downed or grap_cd > 0.0 or not over_void():
		return
	if m.time - kb_t < 1.2 and Vector2(vel.x, vel.z).length() > 9.5:
		return
	var best := {}; var bd := 1e9
	var w: World = m.world
	for z in range(int(floor(pos.z - LEDGE_REACH)), int(floor(pos.z + LEDGE_REACH)) + 1):
		for x in range(int(floor(pos.x - LEDGE_REACH)), int(floor(pos.x + LEDGE_REACH)) + 1):
			if not w.inb(x, z) or w.kind[w.idx(x, z)] != World.T_GROUND:
				continue
			var gz := w.level[w.idx(x, z)] * World.LEVEL
			var dz := gz - pos.y
			if dz < 0.2 or dz > 7.5:
				continue
			var ex := clampf(pos.x, x + 0.06, x + 0.94); var ez := clampf(pos.z, z + 0.06, z + 0.94)
			var d := Vector2(ex - pos.x, ez - pos.z).length()
			if d < bd and d < LEDGE_REACH:
				bd = d
				best = {"x": x, "z": z, "gz": gz, "ex": ex, "ez": ez}
	if best.is_empty():
		return
	var cx: float = best["x"] + 0.5; var cz: float = best["z"] + 0.5
	var a := atan2(cz - best["ez"], cx - best["ex"])
	var land := Vector3(cx, best["gz"], cz)
	for k in [1.25, 0.9]:
		var lx: float = best["ex"] + cos(a) * k; var lz: float = best["ez"] + sin(a) * k
		if absf(w.ground_at(lx, lz) - best["gz"]) < 0.1 and not w.is_block(lx, lz):
			land = Vector3(lx, best["gz"], lz); break
	if w.is_block(land.x, land.z):
		return
	grap = {"ex": best["ex"], "ez": best["ez"], "gz": best["gz"], "land": land, "t": 0.0}
	grap_cd = LEDGE_CD
	vel = Vector3.ZERO
	m.sfx("grab", pos, -2.0)
	m.on_ledge_grab(self)

func _grapple(dt: float) -> void:
	grap["t"] += dt
	var tz: float = grap["gz"] + 0.8
	var to := Vector3(grap["ex"], tz, grap["ez"]) - pos
	var step := 22.0 * dt
	if stun_t > 0.0 and grap["t"] > 0.05:
		grap = {}
		return
	if to.length() <= step or grap["t"] > 0.7:
		pos = Vector3(grap["ex"], maxf(pos.y, tz), grap["ez"])
		var land: Vector3 = grap["land"]
		grap = {}
		# hop onto the ledge along a fixed arc so it always lands
		pad = {"from": pos, "to": land, "t": 0.0, "dur": 0.22, "h": 0.4}
		return
	pos += to.normalized() * step
	vel = Vector3.ZERO
	grounded = false

# ------------------------------------------------------------------ visuals
func render(delta: float, alpha: float) -> void:
	super.render(delta, alpha)
	visible = not out and not extracted
	if not model:
		return
	model.rotation.y = face
	var rig: Node3D = model.get_node("Rig")
	var torso: Node3D = rig.get_node("Torso")
	var legs: Node3D = rig.get_node("Legs")
	var hv := Vector2(vel.x, vel.z)
	var spd := hv.length()
	walk_ph += delta * spd * 2.2
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
