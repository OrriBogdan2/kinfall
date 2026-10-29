class_name Hunter
extends Ent
## A player or bot hunter: movement, weapon, dash, jump, ledge grab, class signature, downed state.

const JUMP_V := 10.8
const DASH_SPEED := 19.0
const DASH_TIME := 0.17
const DASH_REGEN := 2.2
const LEDGE_REACH := 2.8
const LEDGE_CD := 1.2
const FLOAT_SPEED := 12.0
const GLIDE_FALL := 1.7
const GLIDE_SPEED := 8.4
const GLIDE_TIME := 6.0
const GLIDE_DRAG := 1.6         # speed lost per second while gliding (more when going fast)
const GLIDE_MAX := 15.0
const DROP_FALL := 7.5
const DROP_SPEED := 5.0
const DROP_ZONE := 7.0       # how far from where you jumped you can steer on the way down, like Supervive
const REGEN := 7.0            # health per second once you've gone a while without getting hit
## Armor: a layer over health that soaks hits first and comes back on its own, fast, once you've
## been out of the fight for a few seconds. Health only regenerates once armor is full.
const ARMOR := {"light": 40.0, "medium": 50.0, "heavy": 65.0}
const ARMOR_WAIT := 4.0
const ARMOR_REGEN := 22.0

var pname := "Hunter"
var cls := "medium"
var cdat: Dictionary = {}
var wid := "repeater"
var wpn: Dictionary = {}
var ctrl := "bot"             # local | bot | remote
var inp := {"move": Vector2.ZERO, "aim": Vector3.ZERO, "fire": false, "dash": false, "jump": false,
	"throw": false, "skill": false, "sig": false, "interact": false, "reload": false, "tonic": false, "glide": false, "ult": false,
	"sec": false, "sec_hold": false, "crouch": false, "gear1": false, "gear2": false, "swap": false}
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
var anim: HunterAnim = null     # the procedural animation for the model
var downed := false
var down_hp := 0.0
var revive := 0.0
var out := false
var extracted := false
var extract_prog := 0.0
var kin: Ent = null             # the active kin: its abilities are on Q and V, its ultimate on R
var kin2: Ent = null            # the benched kin, swapped in with X
var swap_cd := 0.0
var fuse: Dictionary = {}       # a kin fused onto you as armor (bond ultimate): {def, t}
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
var armor := 0.0
var max_armor := 50.0
var armor_wait := 0.0
var bloom := 0.0              # extra spread from moving, jumping and dashing
var crouch := false           # slower, steadier aim, and much harder to spot
var crouch_k := 0.0
var sec_cd := 0.0             # right-click ability
var sec_ch := 3               # its charges, for heroes that have them
var sec_ch_t := 0.0
var satchel := {}             # Pyra's thrown charge, waiting to be set off
var bshield_on := false       # Bastion's Brightshield is up
var bshield_t := 0.0
var reveal_t := 0.0           # seen through bushes and around walls for a moment after firing or getting hit
var wall_touch_t := 0.0       # touching a wall in the air: a jump kicks off it
var wall_n := Vector2.ZERO
var wall_kicks := 1
var wslam_t := 0.0
var wallstun := 0.0           # how long the next wall slam stuns (Haymaker makes it longer)
var land_t := 0.0
var ghost_t := 0.0
var step_t := 0.0
var gliding := false
var glide_fuel := 1.0          # shown as glider heat: 1 = cool, 0 = overheated
var shot_down := false         # knocked out of an overheated glide: stunned when you land
var below_lip := false         # dropped below the nearest island's edge, over the abyss
var lip_y := 0.0               # that edge's height: where your balloon floats
var heat_burn := 0.0
var in_current := false        # riding a wind road or an updraft: the glider doesn't heat up
var glide_max := GLIDE_TIME
var glide_cd := 0.0
var glide_k := 0.0             # how far the glider is unfolded, for the model
var wind_t := 0.0
var hero := "sage"
var perk := ""
var ult := 0.0                # the bond meter, 0..1: R calls your kin's bond ultimate at 1
var crit_t := 0.0             # shots crit while this runs (Blink)
var charge: Dictionary = {}   # Ram
var acts: Array = []          # queued ability pieces, see Abil.tick
var acts_tele: Node3D = null
var idle_fire := 0.0
var dropping := false         # gliding down from the sky at the start of a match
var drop_from := Vector2.INF  # where the drop started; you can only steer within DROP_ZONE of it
var riding := false           # aboard the skyship, waiting to jump
var bless_t := 0.0
var wrar := 0                 # rarity of the weapon in hand, 0 for the one you brought
var swap_hold := false
var dash_at := -9.0           # when the last dash started, for perfect dodges
var dodged := false        # F has to be let go between weapon swaps
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
	wpn = Data.weapon_stats(wid, 0)
	perk = String(kit.get("perk", ""))
	pname = name_txt
	ctrl = control
	if control != "local":
		bot_look = {"gender": randi() % 2, "body": randi() % 3, "detail": randi() % Models.LOOK_DETAILS.size(), "face": randi() % Models.LOOK_FACES.size(), "skin": randi() % Models.LOOK_SKIN.size(),
			"hair": randi() % Models.LOOK_HAIRS.size(), "hair_col": randi() % 6}
	max_hp = cdat["hp"] + (15 if perk == "toughskin" else 0); hp = max_hp
	max_armor = float(ARMOR.get(cls, 50.0)); armor = max_armor; base_armor = max_armor
	if perk == "featherfall": glide_max = GLIDE_TIME * 1.6
	base_speed = cdat["speed"]
	runner = AbilityRunner.new(self)
	dodge_def = Content.class_dodge(cls)
	_kit_from_weapon()
	dashes = max_dashes()
	ammo = wpn["mag"]
	r = 0.38 * float(cdat["scale"])
	set_model(Models.hunter(cls, Data.TEAM_COLORS[team % Data.TEAM_COLORS.size()], wid, hero, Save.d.get("look", {}) if ctrl == "local" else bot_look))

## Swap to a found weapon for the rest of the expedition.
func equip(w: String, rar: int, with_ammo := -1) -> void:
	wid = w; wrar = rar
	wpn = Data.weapon_stats(w, rar)
	_kit_from_weapon()
	ammo = int(wpn["mag"]) if with_ammo < 0 else mini(with_ammo, int(wpn["mag"])); reload_t = 0.0; fire_cd = 0.25
	if ammo <= 0 and not remote: start_reload()
	var gun: Node3D = model.find_child("Gun", true, false) if model else null
	if gun:
		for ch in gun.get_children():
			if ch.name != "Muzzle":
				ch.queue_free()
		var acc: Color = Data.RARITY[rar]["color"] if rar > 0 else Data.TEAM_COLORS[team % Data.TEAM_COLORS.size()]
		Models.gun_parts(gun, w, Models.toon(Color("4a4d5c")), Models.toon(Color("2b2a33")), Models.toon(acc, true, 0.45 if rar > 0 else 0.0))

func max_dashes() -> float:
	var base := float(dodge_def.charges) if dodge_def else float(cdat["dashes"])
	return base + (1.0 if shoulder() == "updraft" else 0.0) + (1.0 if perk == "secondwind" else 0.0)

func dash_regen() -> float:
	return dodge_def.cooldown if dodge_def else DASH_REGEN

## The weapon's utility goes on right click (heroes without one keep their own secondary for now).
func _kit_from_weapon() -> void:
	if runner == null:
		return
	var wd := Content.weapon(wid)
	runner.set_slot("utility", Content.ability(wd.utility) if wd and wd.utility != "" else null)

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
		# dashing through an attack right as it lands: a perfect dodge
		if not dropping and not dodged and m.time - dash_at < 0.22 and by != null and by.team != team and dmg >= 4.0:
			dodged = true
			dashes = minf(max_dashes(), dashes + 0.6)
			crit_t = maxf(crit_t, 1.5)
			m.on_perfect_dodge(self)
		return 0.0
	if ctrl == "local" and Game.god:
		return 0.0
	reveal_t = maxf(reveal_t, 1.0)
	if opts.has("wallstun"):
		wallstun = float(opts["wallstun"])
	if bshield_on and by != null and opts.get("src", "") not in ["fall", "burn", "wall"]:
		var to := Vector2(by.pos.x - pos.x, by.pos.z - pos.z)
		if to.length() > 0.2 and to.normalized().dot(aim_dir()) > 0.3:
			m.fx.burst(pos + Vector3(to.normalized().x * 0.6, 1.0, to.normalized().y * 0.6), Color("fff6c0"), 6, 2.5, 0.25)
			m.sfx("shield", pos, -10.0, 1.6)
			return 0.0
	# getting hit while gliding heats the glider up; an overheated glider gets shot right down
	if gliding and not dropping and opts.get("src", "") not in ["fall", "burn", "heat"]:
		if glide_fuel <= 0.001 or below_lip:
			_shot_down()
			if by is Hunter: (by as Hunter).add_stat("spikes")
			elif by is Kin and (by as Kin).owner_h: (by as Kin).owner_h.add_stat("spikes")
		else:
			glide_fuel = maxf(0.0, glide_fuel - (0.12 + dmg * 0.008))
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
	armor_wait = ARMOR_WAIT
	if armor > 0.0 and opts.get("src", "") not in ["fall", "burn"]:
		var a := minf(armor, d)
		armor -= a; d -= a
		var ao := opts.duplicate(); ao["armor"] = true
		m.on_damage(self, by, a, ao)
		if armor <= 0.0:
			m.on_armor_break(self, by)
		if d <= 0.0:
			flash_t = 0.05
			if opts.has("kb"): impulse(opts["kb"] * 0.7, opts.get("lift", -1.0))
			return 0.0
	if gliding and d > 0.0:
		gliding = false
		glide_cd = 0.8
		m.fx.burst(pos + Vector3(0, 1.6, 0), Color("f3eee2"), 10, 3.0, 0.4, 8.0)
	# only another hunter's damage (or their kin's) knocks you out of extracting, not monsters
	if extract_prog > 0.0 and d > 0.0 and by != null and not (by is Mob):
		var src: Ent = by
		if by is Kin and (by as Kin).owner_h: src = (by as Kin).owner_h
		if src is Hunter and src.team != team:
			extract_prog = 0.0
			if is_local() and m.hud: m.hud.toast("Extraction interrupted", Color("ff9a8a"))
	return d

func hit_y() -> float:
	return lip_y if below_lip else pos.y

## Over the abyss and below the lip of the nearest island? Ground level is the lowest land close by.
func update_lip() -> void:
	below_lip = false
	if grounded or downed or out or riding or dropping or not over_void():
		return
	var ref := INF
	for r in [1.5, 3.0, 5.0, 7.5]:
		for i in 12:
			var a := TAU * i / 12.0
			var x: float = pos.x + cos(a) * r; var z: float = pos.z + sin(a) * r
			if not m.world.is_void(x, z):
				ref = minf(ref, m.world.ground_at(x, z))
		if ref < INF:
			break
	if ref == INF:
		ref = last_gy
	lip_y = ref
	below_lip = pos.y < ref - 0.5

## Below the lip of an island, a balloon on a string floats at ground level above you: that's
## what everyone aims at. It glows purple while you glide, when a hit would knock you down.
var balloon: Node3D
func _render_balloon() -> void:
	var show := below_lip and not out and not extracted and visible
	if not show:
		if balloon: balloon.visible = false
		return
	if balloon == null:
		balloon = Node3D.new()
		balloon.top_level = true
		add_child(balloon)
		Models.part(balloon, Models.sphere(0.34), Models.toon(Color("ff3a4a"), true, 0.35), Vector3(0, 0.36, 0), Vector3(1.0, 1.15, 1.0), Vector3.ZERO, "Ball")
		Models.part(balloon, Models.cyl(0.03, 0.06, 0.1), Models.toon(Color("c02030")), Vector3(0, -0.02, 0))
		var aura := Models.part(balloon, Models.sphere(0.5), Models.glow_mat(Color(0.75, 0.35, 1.0, 0.4)), Vector3(0, 0.36, 0), Vector3.ONE, Vector3.ZERO, "Aura")
		aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var string := Models.part(balloon, Models.cyl(0.012, 0.012, 1.0, 4), Models.toon(Color(0.95, 0.95, 0.95), false), Vector3.ZERO, Vector3.ONE, Vector3.ZERO, "String")
		string.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	balloon.visible = true
	var top := Vector3(position.x, lip_y + 1.0, position.z)
	balloon.global_position = top + Vector3(0, sin(m.time * 3.0) * 0.06, 0)
	var aura: Node3D = balloon.get_node("Aura")
	aura.visible = gliding
	aura.scale = Vector3.ONE * (1.0 + 0.08 * sin(m.time * 9.0))
	var string: Node3D = balloon.get_node("String")
	var from_y := position.y + 1.6
	var len := maxf(0.1, balloon.global_position.y - from_y)
	string.position = Vector3(0, -len * 0.5, 0)
	string.scale = Vector3(1, len, 1)

func _shot_down() -> void:
	gliding = false
	glide_cd = 2.5
	shot_down = true
	vel = Vector3(vel.x * 0.3, minf(vel.y, -6.0), vel.z * 0.3)
	m.fx.burst(pos + Vector3(0, 1.8, 0), Color("ff9a5a"), 14, 3.0, 0.45, 6.0, 0.8)
	m.sfx("knock", pos, -2.0, 1.3)
	if ctrl == "local" and m.hud:
		m.hud.toast_small("GLIDER SHOT DOWN", Color("ff9a5a"))

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
		if not pad.get("ledge", false) and float(pad["t"]) > 0.12 and can_glide():
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
	# against a wall in the air: kick off it
	if wall_touch_t > 0.0 and wall_kicks > 0 and wall_n.length() > 0.1:
		wall_kicks -= 1
		wall_touch_t = 0.0
		var hv0 := Vector2(vel.x, vel.z)
		var out := wall_n * 7.5 + hv0.slide(wall_n) * 0.6
		vel = Vector3(out.x, JUMP_V * 0.9, out.y)
		gliding = false
		m.fx.burst(pos + Vector3(wall_n.x * -0.3, 0.8, wall_n.y * -0.3), Color("e6dccb"), 8, 2.5, 0.3)
		m.sfx("jump", pos, -4.0, 1.3)
		return
	# already in the air: a second press opens the glider straight away, rising or falling,
	# unless you're about to land, where it buffers a jump instead
	var near_ground := vel.y < 0.0 and pos.y - ground() < 0.9 and not over_void()
	if not gliding and can_glide() and not near_ground:
		_open_glider()
		return
	jump_buf = 0.12

## Fast gliders barely sink; a slow one drifts steadily down.
static func glide_fall(speed: float) -> float:
	return lerpf(2.2, 0.35, clampf((speed - 4.0) / 9.0, 0.0, 1.0))

func can_glide() -> bool:
	return not grounded and roll_t <= 0.0 and fly_t <= 0.0 and glide_cd <= 0.0 and not downed and stun_t <= 0.0 \
		and m.time - kb_t > 0.4 and glide_fuel > 0.15 and not dropping and charge.is_empty()

func _open_glider() -> void:
	gliding = true
	grounded = false
	# unfolding catches the air: a slow start gets carried up to cruising speed
	var hv := Vector2(vel.x, vel.z)
	if hv.length() < GLIDE_SPEED and not dropping:
		var mvv: Vector2 = inp.get("move", Vector2.ZERO)
		var dirv := mvv.normalized() if mvv.length() > 0.1 else (hv.normalized() if hv.length() > 0.3 else aim_dir())
		hv = dirv * GLIDE_SPEED
		vel.x = hv.x; vel.z = hv.y
	m.sfx("glide", pos, -4.0)
	m.fx.burst(pos + Vector3(0, 1.7, 0), Color("f3eee2"), 8, 2.0, 0.35, 0.0)

## The class's dodge (Shift), as described by its ability data: a dash, plus anything else in its
## effect list (the heavy class's charge shoves people).
func do_dash() -> void:
	if downed or stun_t > 0.0 or root_t > 0.0 or out or dashes < 1.0 or roll_t > 0.0 or grap.size() > 0 or pad.size() > 0:
		return
	dashes -= 1.0
	var effs: Array = dodge_def.effects if dodge_def else [{"type": "dash", "speed": DASH_SPEED, "time": DASH_TIME, "invuln": 0.14}]
	Effects.run(effs, self, {"slot": "dodge", "ability": dodge_def.id if dodge_def else "dash"})
	CombatBus.ability_used.emit(self, dodge_def.id if dodge_def else "dash", "dodge")

var roll_speed := DASH_SPEED
var wedged_t := 0.0

## True only when there's no direction at all you could step: really stuck, not just walking into a wall.
func _boxed_in() -> bool:
	for i in 8:
		var a := TAU * i / 8.0
		if m.world.occupy(pos.x + cos(a) * 0.2, pos.z + sin(a) * 0.2, r, pos.y, false) == 0.0:
			return false
	return true
var shove := {}                # the heavy charge: who it already hit, and how hard it shoves

func dash_with(e: Dictionary) -> void:
	var d: Vector2 = inp["move"]
	if d.length() < 0.1:
		d = aim_dir()
	roll_dir = d.normalized()
	roll_speed = float(e.get("speed", DASH_SPEED))
	roll_t = float(e.get("time", DASH_TIME))
	inv_t = maxf(inv_t, float(e.get("invuln", 0.14)))
	shove = {"hit": {}, "kb": float(e.get("shove_kb", 9.0)), "dmg": float(e.get("shove_dmg", 0.0))} if e.get("shove", false) else {}
	if not shove.is_empty():
		fortify_t = maxf(fortify_t, roll_t + 0.1)     # nothing knocks you back mid-charge
	dash_at = m.time
	dodged = false
	fly_t = 0.0
	m.sfx("dash", pos, -4.0, 0.8 if not shove.is_empty() else 1.0)
	m.fx.dash_trail(self)

func _shove_along() -> void:
	for f in m.foes_of(team):
		if shove["hit"].has(f.nid) or flat_dist(f) > r + f.r + 0.35 or absf(f.pos.y - pos.y) > 1.4:
			continue
		shove["hit"][f.nid] = true
		var side := Vector2(f.pos.x - pos.x, f.pos.z - pos.z).normalized()
		var push := (roll_dir * 0.7 + side * 0.5).normalized() * float(shove["kb"])
		f.hurt(maxf(0.1, float(shove["dmg"])) * m.dmg_mult(self), self, {"kb": push, "lift": 2.5, "src": "abil", "ab": "dodge", "tags": ["dodge"]})
		m.shake(0.25, f.pos)

func can_fire() -> bool:
	return not (drink_t > 0.0 or reload_t > 0.0 or roll_t > 0.0 or downed or out or stun_t > 0.0 or grap.size() > 0 or gliding or charge.size() > 0)

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
	reveal_t = maxf(reveal_t, 1.2)
	ammo -= 1
	recoil = 1.0
	muzzle_t = 0.05
	var dir := aim_dir()
	var a := atan2(dir.y, dir.x) + randf_range(-1.0, 1.0) * (float(wpn["spread"]) * (1.0 + bloom * 1.6) + bloom * 0.025)
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
	if not fuse.is_empty():
		# a fused kin changes every shot: burning, slowing, bursting or arcing to another foe
		var fs: Dictionary = (fuse["def"] as UltimateDef).shots
		if fs.has("burn"): extra["burn"] = maxf(float(extra.get("burn", 0.0)), float(fs["burn"]))
		if fs.has("slow"): extra["slow"] = maxf(float(extra.get("slow", 0.0)), float(fs["slow"]))
		if fs.has("boom") and not extra.has("boom"):
			extra["boom"] = float(fs["boom"]); extra["boom_kb"] = 4.0; extra["boom_small"] = true
		if int(fs.get("chain", 0)) > 0:
			extra["fx_hit"] = [{"type": "chain", "count": int(fs["chain"]), "first": 5.0, "dmg": float(wpn["dmg"]) * 0.5, "color": "#fff27a", "skip_here": true}]
			extra["fx_ctx"] = {"slot": "ult", "ability": "fuse"}
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
	use_kin_ability("k1")

## Is a kin with you and able to fight? (The bond meter only fills while one is.)
func has_kin_ready() -> bool:
	return kin != null and (kin as Kin).ready_to_fight()

func _ground_aim() -> Vector3:
	var a: Vector3 = inp["aim"]
	var g: float = m.world.ground_at(a.x, a.z)
	return Vector3(a.x, g if g > World.VOID + 1.0 else pos.y, a.z)

## Q and V: your active kin's abilities, aimed at the cursor.
func use_kin_ability(slot: String) -> void:
	var k: Kin = kin
	if k == null or downed or dropping or riding:
		return
	if not k.ready_to_fight():
		if is_local() and m.hud:
			m.hud.toast("%s is resting%s" % [k.rec.get("name", "Your kin"), ("  ·  %s swaps in %s" % [Settings.key_cap("swap_kin"), (kin2 as Kin).rec.get("name", "your other kin")]) if kin2 and (kin2 as Kin).hp > 0.0 else ""], Color("a2a8bb"))
		return
	k.use_ability(slot, _ground_aim())

## R: the bond ultimate, once fighting together has filled the meter.
func use_ultimate() -> void:
	if not Ultimate.cast(self) and is_local() and m.hud and ult >= 1.0 and kin and not (kin as Kin).ready_to_fight():
		m.hud.toast("Your kin has to be with you", Color("a2a8bb"))

## X: swap which of your two kin is out. The benched one rests in your satchel.
func swap_kin(force := false) -> void:
	if kin2 == null or riding or out or (not force and (swap_cd > 0.0 or downed)):
		return
	var a: Kin = kin
	var b: Kin = kin2
	if b.dead or (a and a.state == "fused"):
		return
	if a: a.bench()
	b.unbench()
	kin = b
	kin2 = a
	swap_cd = float(Content.rules("kin_ai").get("swap_cooldown", 3.0))
	m.on_kin_swap(self, b, a)

## A bonus from a kin fused onto you (armor ultimate): dmg, speed.
func fuse_mod(k: String) -> float:
	if fuse.is_empty():
		return 1.0
	return float((fuse["def"] as UltimateDef).owner_mods.get(k, 1.0))

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

## Drinking a tonic takes a moment: you slow down, lower your gun and drink. Dashing, getting
## stunned or going down spills it (you keep the tonic). It heals when you finish.
const DRINK_TIME := 1.1
var drink_t := 0.0
func use_tonic() -> void:
	if tonics <= 0 or downed or hp >= max_hp or drink_t > 0.0 or gliding or not grounded:
		return
	drink_t = DRINK_TIME
	m.sfx("pickup", pos, -6.0, 0.7)

func _tick_drink(dt: float) -> void:
	if drink_t <= 0.0:
		return
	if downed or stun_t > 0.0 or roll_t > 0.0 or gliding or out:
		drink_t = 0.0
		return
	drink_t -= dt
	if drink_t <= 0.0:
		drink_t = 0.0
		if tonics > 0:
			tonics -= 1
			free_tonics = maxi(0, free_tonics - 1)
			heal(45.0)
			m.sfx("heal", pos, -2.0)
			m.fx.burst(pos + Vector3(0, 1.2, 0), Color("8ff0a0"), 14, 2.5, 0.5, -3.0)

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
			for k in ["jump", "dash", "sig", "reload", "tonic", "ult", "fire", "skill", "swap"]:
				inp[k] = false
		return
	tick_status(dt)
	for k in ["reveal_t", "inv_t", "fire_cd", "coyote", "jump_buf", "mantle_cd", "grap_cd", "sig_cd", "cloak_t", "haste_t", "fortify_t", "recoil", "muzzle_t", "regen_wait", "land_t", "glide_cd", "bless_t", "crit_t"]:
		set(k, maxf(0.0, get(k) - dt))
	if shield_t > 0.0:
		shield_t -= dt
		if shield_t <= 0.0: shield = 0.0
	if reload_t > 0.0:
		reload_t -= dt
		if reload_t <= 0.0:
			ammo = wpn["mag"]
	if dashes < max_dashes():
		dashes = minf(max_dashes(), dashes + dt / dash_regen())
	if shoulder() == "spring" and not downed:
		hp = minf(max_hp, hp + 3.0 * dt)
	# out of the fight for a few seconds, armor snaps back, then you patch yourself up
	armor_wait = maxf(0.0, armor_wait - dt)
	if not downed and not remote and armor_wait <= 0.0 and armor < max_armor:
		armor = minf(max_armor, armor + ARMOR_REGEN * dt)
	elif not downed and regen_wait <= 0.0 and hp < max_hp and not remote:
		hp = minf(max_hp, hp + REGEN * dt)
	# shots spread more while you move, jump or have just dashed, and settle when you stand still
	if not remote:
		crouch = bool(inp.get("crouch", false)) and grounded and not downed and roll_t <= 0.0 and not gliding and not dropping and not riding and charge.is_empty()
	var want_bloom := -0.3 if crouch else 0.0
	if not grounded: want_bloom = 1.0
	elif Vector2(vel.x, vel.z).length() > 1.5 and not crouch: want_bloom = 0.45
	if roll_t > 0.0: want_bloom = 1.4
	bloom = lerpf(bloom, want_bloom, 1.0 - exp(-(10.0 if want_bloom > bloom else 4.0) * dt))
	if remote:
		net_follow(dt)
		return
	if not downed and not dropping:
		Bond.passive(self, dt)
	swap_cd = maxf(0.0, swap_cd - dt)
	if not fuse.is_empty():
		fuse["t"] = float(fuse["t"]) - dt
	if not downed:
		Abil.tick(self, dt)
	# reload by itself once you stop shooting for a moment
	idle_fire += dt
	if idle_fire > 1.3 and ammo < int(wpn["mag"]) and reload_t <= 0.0 and not inp["fire"]:
		start_reload()
	if downed:
		# your other kin comes out of the satchel to pick you up if the active one can't
		if kin and (kin as Kin).state == "fainted" and kin2 and (kin2 as Kin).hp > 0.0:
			swap_kin(true)
		down_hp -= Data.MATCH["bleed"] * dt
		if down_hp <= 0.0:
			m.eliminate(self, last_hit_by, "bled out")
			return
	# inputs
	if inp["dash"]: do_dash()
	if inp["jump"]: do_jump()
	if runner:
		runner.rate = 1.0 + gear_stat("cdr")
		runner.tick(dt)
	var cdr := gear_stat("cdr")
	if cdr > 0.0:
		sig_cd = maxf(0.0, sig_cd - dt * cdr)
		sec_cd = maxf(0.0, sec_cd - dt * cdr)
	for gi in 2:
		gear_cd[gi] = maxf(0.0, float(gear_cd[gi]) - dt)
		if inp.get("gear%d" % (gi + 1), false):
			m.use_gear(self, gi)
	if inp["sig"]: use_kin_ability("k1")
	if inp["skill"]: use_kin_ability("k2")
	if inp["swap"]: swap_kin()
	if inp["sec"]:
		if runner and runner.has_slot("utility"): runner.use("utility")
		else: Abil.use_s(self)
	Abil.tick_s(self, dt)
	if inp["reload"]: start_reload()
	if inp["tonic"]: use_tonic()
	_tick_drink(dt)
	if inp["ult"]: use_ultimate()
	if inp["fire"]: fire()
	inp["dash"] = false; inp["jump"] = false; inp["sig"] = false; inp["reload"] = false; inp["tonic"] = false; inp["ult"] = false; inp["sec"] = false; inp["gear1"] = false; inp["gear2"] = false
	inp["skill"] = false; inp["swap"] = false
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
	var spd := base_speed * (1.35 if haste_t > 0.0 else 1.0) * (0.45 if downed else 1.0) * (0.65 if slow_t > 0.0 else 1.0) * (0.88 if reload_t > 0.0 else 1.0) * (0.45 if drink_t > 0.0 else 1.0) * (0.6 if bshield_on else 1.0) * (0.55 if crouch else 1.0) * (1.0 + gear_stat("speed")) * fuse_mod("speed")
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
		hv = roll_dir * roll_speed
		if not shove.is_empty():
			_shove_along()
		if roll_t <= 0.0:
			hv = roll_dir * spd * 1.1
	elif fly_t > 0.0:
		fly_t -= dt
	elif gliding:
		# the glider keeps the speed you bring into it and bleeds it off slowly; steering turns
		# you without slowing you down. Speed is what keeps you up (see the fall below).
		var gs := DROP_SPEED if dropping else (GLIDE_SPEED * 0.6 if glide_fuel <= 0.001 else GLIDE_SPEED) * (1.0 + gear_stat("glide_speed"))
		var head := hv.normalized() if cur > 0.3 else mv
		# steering hard against your heading works as an air brake
		var brake := 0.0
		if mv.length() > 0.1 and head.length() > 0.1:
			brake = clampf(-head.dot(mv.normalized()) + 0.3, 0.0, 1.3) * 7.0
		var drag := GLIDE_DRAG + maxf(0.0, cur - gs) * 0.25
		var keep := maxf(gs * 0.6, cur - (drag + brake) * dt) if cur > gs * 0.6 else gs * 0.6
		if dropping: keep = gs
		keep = minf(keep, GLIDE_MAX)
		if mv.length() > 0.1:
			head = head.slerp(mv.normalized(), 1.0 - exp(-3.2 * dt)) if head.length() > 0.1 else mv.normalized()
		hv = head * keep
		# wind roads carry you along (either way), updrafts lift you
		in_current = false
		if not dropping:
			var wd: Dictionary = m.world.wind_at(pos)
			if not wd.is_empty():
				in_current = true
				var wdir: Vector3 = wd["dir"]
				var w2 := Vector2(wdir.x, wdir.z).normalized()
				if hv.dot(w2) < 0.0: w2 = -w2
				hv = hv.lerp(w2 * 14.0, 1.0 - exp(-2.5 * dt))
				vel.y = lerpf(vel.y, clampf((float(wd["y"]) - pos.y) * 2.5, -3.0, 6.0), 1.0 - exp(-4.0 * dt))
			var up: Dictionary = m.world.updraft_at(pos)
			if not up.is_empty():
				in_current = true
				vel.y = move_toward(vel.y, 9.0, 30.0 * dt)
	else:
		var wish := mv * spd
		var over := cur > spd * 1.15
		var k := (2.6 if over else 16.0) if grounded else (1.5 if over else 3.5)
		hv += (wish - hv) * (1.0 - exp(-k * dt))
	if dropping and drop_from != Vector2.INF:
		# the drop only lets you pick a spot near where you jumped: steering pushes against the edge of a small circle
		var rel := Vector2(pos.x, pos.z) - drop_from
		var nxt := rel + hv * dt
		if nxt.length() > DROP_ZONE:
			var nrm := nxt.normalized()
			hv -= nrm * maxf(0.0, hv.dot(nrm))
	vel.x = hv.x; vel.z = hv.y
	update_lip()
	_update_glide(dt)
	if gliding and in_current:
		pass   # the current sets the height
	elif gliding:
		var sink := DROP_FALL if dropping else (3.0 if glide_fuel <= 0.001 else glide_fall(Vector2(vel.x, vel.z).length()))
		vel.y = lerpf(vel.y, -sink, 1.0 - exp(-4.0 * dt))
	elif not grounded:
		vel.y -= GRAV * (1.3 if vel.y < 0.0 and fly_t <= 0.0 else 1.0) * dt
	var guard := grounded and roll_t <= 0.0 and hv.length() <= spd * 1.25
	# horizontal with walls; mantle onto ledges you run or fall into
	var x0 := pos.x; var z0 := pos.z
	var pre_v := Vector2(vel.x, vel.z)
	var step_up := 0.0
	var nx := pos.x + vel.x * dt
	var b1: float = m.world.occupy(nx, pos.z, r, pos.y, guard)
	if b1 == 0.0: pos.x = nx
	elif grounded and b1 > 0.0 and b1 - pos.y <= World.LEVEL + 0.05: step_up = b1
	elif b1 > 0.0 or b1 == -1.0: vel.x = 0.0 if b1 == -1.0 else vel.x * -0.1
	var nz := pos.z + vel.z * dt
	var b2: float = m.world.occupy(pos.x, nz, r, pos.y, guard)
	if b2 == 0.0: pos.z = nz
	elif grounded and b2 > 0.0 and b2 - pos.y <= World.LEVEL + 0.05: step_up = maxf(step_up, b2)
	elif b2 > 0.0 or b2 == -1.0: vel.z = 0.0 if b2 == -1.0 else vel.z * -0.1
	if step_up > 0.0 and mv.length() > 0.3:
		# walking into a single terrace hops you up it instead of stopping you dead
		vel.y = sqrt(2.0 * GRAV * (step_up - pos.y + 0.18))
		grounded = false
		coyote = 0.0
	elif step_up == 0.0 and (b1 > 0.0 or b2 > 0.0) and hv.length() > 1.0:
		# caught on a corner: slip sideways around it rather than sticking
		var moved := Vector2(pos.x - x0, pos.z - z0).length()
		var want := hv.length() * dt
		if moved < want * 0.35:
			var dn := hv.normalized()
			for side in [Vector2(-dn.y, dn.x), Vector2(dn.y, -dn.x)]:
				var tx: float = pos.x + (side.x * 0.8 + dn.x * 0.4) * want
				var tz: float = pos.z + (side.y * 0.8 + dn.y * 0.4) * want
				if m.world.occupy(tx, tz, r, pos.y, guard) == 0.0:
					pos.x = tx; pos.z = tz
					break
	# a safety net: pushing to move for a second without going anywhere means something has us
	# wedged, so step out to the nearest open ground
	if grounded and mv.length() > 0.3 and stun_t <= 0.0 and root_t <= 0.0 and not remote and grap.is_empty():
		if Vector2(pos.x - x0, pos.z - z0).length() < 0.004 and _boxed_in():
			wedged_t += dt
			if wedged_t > 0.9:
				wedged_t = 0.0
				var free: Vector3 = m.world.free_spot_near(pos, [], 1.0, r, 2.5)
				if free.distance_to(pos) > 0.05 and absf(free.y - pos.y) < 1.0:
					pos = Vector3(free.x, free.y, free.z)
					m.fx.dust(pos, 4)
		else:
			wedged_t = 0.0
	var blk := maxf(b1, b2)
	if (b1 > 0.0 or b2 > 0.0) and blk > pos.y + 0.6:
		# against a wall: in the air you can kick off it; knocked into it hard, you're stunned
		if not grounded:
			wall_touch_t = 0.2
			wall_n = Vector2(-signf(pre_v.x) if b1 > 0.0 else 0.0, -signf(pre_v.y) if b2 > 0.0 else 0.0).normalized()
		if m.time - kb_t < 0.6 and pre_v.length() > 8.0 and wslam_t <= 0.0 and not remote:
			wslam_t = 1.2
			var st := maxf(0.9, wallstun)
			wallstun = 0.0
			stun_t = maxf(stun_t, st)
			m.on_wall_slam(self, st)
			hurt(10.0, last_hit_by, {"src": "wall"})
	if grounded:
		wall_kicks = 2 if cls == "light" else 1
	wall_touch_t = maxf(0.0, wall_touch_t - dt)
	wslam_t = maxf(0.0, wslam_t - dt)
	if not grounded and not dropping and blk > 0.0 and blk < pos.y + 2.4 and mantle_cd <= 0.0 and blk - pos.y < World.BLOCK_H - 0.1:
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
			if shot_down:
				shot_down = false
				stun_t = maxf(stun_t, 1.0)
				m.fx.dust(pos, 8)
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
	if grounded:
		shot_down = false
	# an overheated glider scorches you while it stays open
	if gliding and not dropping and glide_fuel <= 0.001 and not downed:
		heat_burn += dt * 4.0
		if heat_burn >= 2.0:
			heat_burn -= 2.0
			hurt(2.0, null, {"src": "heat"})
	# an overheated glider stays open (slow and sinking) until you land or get hit again
	var can: bool = not grounded and roll_t <= 0.0 and fly_t <= 0.0 and glide_cd <= 0.0 and not downed and stun_t <= 0.0 \
		and m.time - kb_t > 0.4 and (glide_fuel > 0.0 or gliding) and pad.is_empty() and not shot_down
	var want: bool = inp.get("glide", false)
	if gliding:
		if not want or not can:
			gliding = false
			if glide_fuel <= 0.0:
				glide_cd = 0.5
		elif not in_current:
			glide_fuel = maxf(0.0, glide_fuel - dt / (glide_max * (1.0 + gear_stat("heat"))))
		if not dropping:
			stats["glide_t"] = float(stats.get("glide_t", 0.0)) + dt
	elif want and can and vel.y < 1.5 and glide_fuel > 0.15 and not gliding:
		gliding = true
		if below_lip:
			# feathering: snapping the glider open below the lip catches an updraft back up to it
			vel.y = clampf(sqrt(2.0 * GRAV * maxf(0.2, lip_y - pos.y + 0.9)), 4.0, 15.0)
			glide_fuel = maxf(0.0, glide_fuel - 0.2)
			m.fx.burst(pos + Vector3(0, 1.2, 0), Color("cfeaff"), 12, 3.5, 0.4, -2.0, 0.8)
			m.sfx("glide", pos, -2.0, 1.4)
			add_stat("feathers")
		m.sfx("glide", pos, -4.0)
		m.fx.burst(pos + Vector3(0, 1.7, 0), Color("f3eee2"), 8, 2.0, 0.35, 0.0)

# Ledge float: touch the side of any ground above you while you're still alive and you float
# back up onto it, the way Supervive does it. Walking into a step up a few terraces high does
# the same after a short push. Getting launched hard still carries you past the edge.
func _try_ledge_grab(dt: float) -> void:
	if grap.size() > 0 or pad.size() > 0 or fly_t > 0.0 or downed or charge.size() > 0 or dropping or shot_down or pos.y < -12.0 or (grounded and stun_t > 0.0):
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
		# no magnet: you have to be below the edge, right up against the cliff, and pushing into it
		if mv.length() < 0.3:
			return
		reach = r + 0.4
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
			if not grounded and (toward.length() > 0.01 and toward.normalized().dot(mv.normalized()) < 0.35):
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
	var hs := 11.0 * dt
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
		pad = {"from": pos, "to": land, "t": 0.0, "dur": 0.22, "h": 0.4, "ledge": true}

# ------------------------------------------------------------------ visuals
var bot_look: Dictionary = {}  # how a bot hunter looks (random)
var runner: AbilityRunner     # weapon utility now; kin abilities later
var dodge_def: AbilityDef     # the class's dodge
var stats := {}                # this match's counts for challenges (the local player's)
var gear: Array = [{}, {}]     # two slots of found gear: {id, rar}
var gear_cd: Array = [0.0, 0.0]

var base_armor := 50.0
func refresh_gear() -> void:
	max_armor = base_armor + gear_stat("armor")
	armor = minf(armor, max_armor)

func gear_stat(k: String) -> float:
	var t := 0.0
	for g in gear:
		if not g.is_empty():
			t += float(Gear.ALL[g["id"]]["stats"].get(k, 0.0)) * Gear.mult(int(g["rar"]))
	return t

func add_stat(k: String, n := 1) -> void:
	stats[k] = int(stats.get(k, 0)) + n
var unseen := false           # hidden from the local player (in a bush, or behind a wall)

func render(delta: float, alpha: float) -> void:
	super.render(delta, alpha)
	visible = not out and not extracted and not riding and not unseen
	if not model:
		return
	model.rotation.y = face
	var bs: Node3D = model.get_node_or_null("BShield")
	if remote:
		update_lip()
	_render_balloon()
	if bshield_on and bs == null:
		bs = Models.part(model, Models.sphere(0.7, 18), Models.glow_mat(Color(1.0, 0.95, 0.75, 0.45)), Vector3(0, 0.9, -0.65), Vector3(1.0, 1.15, 0.22), Vector3.ZERO, "BShield")
		bs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if bs: bs.visible = bshield_on
	var rig: Node3D = model.get_node("Rig")
	var torso: Node3D = rig.get_node("Torso")
	if anim == null or anim.model != model:
		anim = HunterAnim.new(model)
	var hv := Vector2(vel.x, vel.z)
	var spd := hv.length()
	crouch_k = move_toward(crouch_k, 1.0 if crouch else 0.0, delta * 8.0)
	anim.update(delta, {"vel": vel, "face": face, "grounded": grounded and pad.is_empty(), "gliding": gliding, "rolling": roll_t > 0.0,
		"crouch": crouch_k, "downed": downed, "ledge": grap.size() > 0, "reload": (1.0 - reload_t / maxf(0.1, float(wpn["reload"]))) if reload_t > 0.0 else -1.0, "drink": (1.0 - drink_t / DRINK_TIME) if drink_t > 0.0 else -1.0,
		"recoil": recoil, "flash": clampf(flash_t / 0.12, 0.0, 1.0), "fired": idle_fire})
	if anim.stepped and not downed and not crouch:
		Sfx.step(pos, -14.0 if is_local() else -20.0)
	var sq := squash
	var stretch := 0.0
	var tc: Color = Data.TEAM_COLORS[team % Data.TEAM_COLORS.size()]
	if roll_t > 0.0:
		stretch = 0.25
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
				# and the circle you can still steer within
				if drop_from != Vector2.INF:
					var zy: float = m.world.ground_at(drop_from.x, drop_from.y)
					m.fx.ring(Vector3(drop_from.x, maxf(zy, 0.0) + 0.1, drop_from.y), DROP_ZONE + 0.8, Color(0.75, 0.95, 1.0, 0.35), 0.3)
		wind_t -= delta
		if wind_t <= 0.0:
			wind_t = 0.09
			m.fx.burst(pos + Vector3(randf_range(-0.8, 0.8), 1.9, randf_range(-0.4, 0.4)), Color(1, 1, 1, 0.5), 2, 1.0, 0.4, -1.0, 0.7, Vector3(-vel.x, 0, -vel.z).normalized(), 20.0)
	elif not grounded and pad.is_empty():
		stretch = clampf(vel.y / 30.0, -0.1, 0.18)
	# little puffs of dust while running, and a kick of dust when you turn hard
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
	glide_k = move_toward(glide_k, 1.0 if gliding else 0.0, delta * (7.0 if gliding else 9.0))
	var gl: Node3D = torso.get_node("Glider")
	gl.visible = glide_k > 0.02
	if gl.visible:
		var gk := glide_k - 1.0
		var ek := 1.0 + 2.7 * gk * gk * gk + 1.7 * gk * gk      # pops open with a little overshoot
		gl.scale = Vector3(ek * (1.0 + sin(m.time * 9.0) * 0.02), ek, ek)
		gl.rotation.x = 0.35 * ek - 0.1
	var halo := torso.get_node_or_null("Halo")
	if halo:
		halo.rotation.y += delta * 2.0
		halo.position.y = 1.26 + sin(m.time * 3.0) * 0.03
	var gun: Node3D = torso.get_node("Aim/Gun")
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
