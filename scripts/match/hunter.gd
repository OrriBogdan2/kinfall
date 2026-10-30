class_name Hunter
extends Ent
## A player or bot hunter: movement, weapon, dash, jump, ledge grab, class signature, downed state.

# Weightier vertical movement: stronger gravity, a quicker jump to the same height (about two and a
# half terraces), falls that speed up and carry the speed you ran off the edge with.
# Supervive feel (see docs/SUPERVIVE_FEEL.md): heavy, snappy arcs, near-instant ground control,
# momentum that carries in the air and in the glider.
const H_GRAV := 30.0
const FALL_MULT := 1.0
const TERMINAL := 9.0           # (was 10, reached in 0.33s) falls now ease into this speed: ~6m in the first second
const FALL_EASE := 3.2           # how quickly a fall approaches TERMINAL (1/s); rising still uses H_GRAV
const GLIDE_CATCH := 16.0        # opening the glider mid-fall brakes you to its sink rate at this rate, no snap
const JUMP_V := 9.0           # about 1.35 up: one terrace easily; higher ledges you mantle
const GROUND_ACCEL := 70.0
const GROUND_DECEL := 90.0
const GROUND_OVERSPEED := 30.0   # how fast dash or pad speed bleeds off on the ground
const AIR_ACCEL := 22.0
const AIR_DECEL := 3.0
const AIR_OVERSPEED := 3.0
const GLIDE_ACCEL := 10.0
const GLIDE_DECEL := 2.0
const GLIDE_OVERSPEED := 1.2
const GLIDE_GRAV := 14.0
const GLIDE_ENGAGE := 0.15       # hold Space this long in the air before the glider opens
const ABYSS_LIFT := 45.0         # opening the glider below ground level: strong lift...
const ABYSS_LIFT_MAX := 16.0
const ABYSS_BRAKE_DIST := 2.5    # ...that brakes near ground level (let go just before to keep the height)
const ABYSS_BRAKE := 60.0
const MANTLE_REACH := 1.5        # near a jump's apex, ledges this far above you pop you up
const MANTLE_REACH_ABYSS := 12.0 # [footage] falling players spring back onto an island even from a second deep
const MANTLE_RISE := 14.0        # [footage] a deep mantle returns to the top in ~0.8s
const EX_DASH_CD := 12.5         # the long dash: in the air, or with the short one on cooldown
const DASH_CARRY_GROUND := 0.15   # (was 0.35) out of a dash you stop almost dead: snappy, no slide
const DASH_CARRY_AIR := 0.3      # (was 0.75, which slid you ~15m+ in the air)
const SPIKE_STUN := 0.7         # [wiki] stun when a spiked glider hits the ground (docs/EXPEDITION_SPEC.md)
const SPIKE_DMG := 8.0
const DASH_SPEED := 23.0
const DASH_TIME := 0.15
const DASH_REGEN := 2.2
const LEDGE_REACH := 2.8
const LEDGE_CD := 0.45
const FLOAT_SPEED := 12.0
const GLIDE_FALL := 1.7
const GLIDE_SPEED := 5.0       # [footage] about run speed
const GLIDE_TIME := 14.0       # [footage] ~14s of level glide before the heat ring turns hot
const GLIDE_DRAG := 1.6         # speed lost per second while gliding (more when going fast)
const GLIDE_MAX := 15.0
# The opening drop, battle-royale style: a fast skydive you steer freely, then the glider opens by
# itself near the ground (or earlier on jump) for a slower, floatier last stretch.
const DIVE_FALL := 11.0
const DIVE_SPEED := 10.0
const DROP_FALL := 4.2
const DROP_SPEED := 7.0
const DEPLOY_H := 8.0         # the glider opens by itself this high above the ground
## Armor, as in Supervive: it takes a flat share off every hit (ARMOR_DR) for as long as it has
## durability left; what gets through hurts your health and wears the durability down by the same
## amount. Neither comes back on its own: tonics (1) heal, armor kits (2) repair.
const ARMOR_DR := 0.2
const ARMOR_DUR := 2.2        # durability as a multiple of max health
const ARMOR_WAIT := 4.0
const KIT_TIME := 1.6
const CONSUME_VULN := 1.2     # you take this much more damage while drinking or repairing

var pname := "Hunter"
var cls := "medium"
var cdat: Dictionary = {}
var wid := "rifle"
var wpn: Dictionary = {}
var ctrl := "bot"             # local | bot | remote
var inp := {"move": Vector2.ZERO, "aim": Vector3.ZERO, "fire": false, "dash": false, "jump": false,
	"throw": false, "skill": false, "sig": false, "interact": false, "reload": false, "tonic": false, "kit": false, "glide": false, "ult": false,
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
var gone := false              # dead for good: no box revive, no beacon (see Life)
var sick_t := 0.0              # resurrection sickness after a beacon revive: -25% damage
var stolen_carry := false      # carrying someone else's kin: it struggles, slowing you a little
var chase: Hunter = null       # whoever has your kin: you run faster toward them
var box_t := 0.0               # holding interact at a deathbox
var hurt_at := -9.0            # last time a hit landed (channels like a box revive break on it)
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
var perk := ""                  # (old single home perk; perks are now found in the run, see perks)
var perks: Array = []           # perks picked up this expedition, one entry per stack
var ult := 0.0                # the bond meter, 0..1: R calls your kin's bond ultimate at 1
var crit_t := 0.0             # shots crit while this runs (Blink)
var charge: Dictionary = {}   # Ram
var idle_fire := 0.0
var dropping := false         # gliding down from the sky at the start of a match
var drop_from := Vector2.INF  # where the drop started
var diving := false           # the skydive part of the drop, before the glider opens
var riding := false           # aboard the skyship, waiting to jump
var bless_t := 0.0
var wrar := 0                 # rarity of the weapon in hand, 0 for the one you brought
var swap_hold := false
var dash_at := -9.0           # when the last dash started, for perfect dodges
var dodged := false        # F has to be let go between weapon swaps
var lives := 1                # comes back this many times minus one before it's really out


func init_hunter(match_node: Node, id: String, team_id: int, class_id: String, name_txt: String, control: String, kit := {}) -> void:
	setup(match_node, id)
	kind = "hunter"
	team = team_id
	cls = class_id if Data.CLASSES.has(class_id) else "medium"
	cdat = Data.CLASSES[cls]
	wid = Data.weapon_for(cls, String(kit.get("weapon", "")))
	wpn = Data.weapon_stats(wid, 0)
	perk = ""
	pname = name_txt
	ctrl = control
	if control != "local":
		bot_look = Models.random_look()
	max_hp = cdat["hp"]; hp = max_hp
	max_armor = round(max_hp * ARMOR_DUR); armor = max_armor; base_armor = max_armor
	glide_max = GLIDE_TIME * float(cdat.get("glide_cap", 1.0))
	base_speed = cdat["speed"]
	runner = AbilityRunner.new(self)
	dodge_def = Content.class_dodge(cls)
	_kit_from_weapon()
	dashes = max_dashes()
	ammo = wpn["mag"]
	r = float(cdat.get("hit_r", 0.38 * float(cdat["scale"])))
	set_model(Models.hunter(cls, Data.TEAM_COLORS[team % Data.TEAM_COLORS.size()], wid, "", Save.d.get("look", {}) if ctrl == "local" else bot_look))

## Swap to a found weapon for the rest of the expedition.
func equip(w: String, rar: int, with_ammo := -1) -> void:
	wid = w; wrar = rar
	wpn = Data.weapon_stats(w, rar)
	_kit_from_weapon()
	wbloom = 0.0; warm_t = 0.0; spin = 0.0; spun_t = 0.0; sus_n = 0; mel_hold = 0.0; strike_at_end = {}
	ammo = int(wpn["mag"]) if with_ammo < 0 else mini(with_ammo, int(wpn["mag"])); reload_t = 0.0; fire_cd = 0.25
	if ammo <= 0 and not remote: start_reload()
	var gun: Node3D = model.find_child("Gun", true, false) if model else null
	if gun:
		for ch in gun.get_children():
			if ch.name != "Muzzle":
				ch.queue_free()
		var acc: Color = Data.RARITY[rar]["color"] if rar > 0 else Data.TEAM_COLORS[team % Data.TEAM_COLORS.size()]
		Models.gun_parts(gun, w, Models.toon(Color("4a4d5c")), Models.toon(Color("2b2a33")), Models.toon(acc, true, 0.45 if rar > 0 else 0.0))

## Chasing down whoever took your kin: 18% faster heading their way. Carrying a stolen kin: 8% slower.
func _chase_mod(mv: Vector2) -> float:
	var k := 0.92 if stolen_carry else 1.0
	if chase and not chase.out and not chase.extracted and mv.length() > 0.1 and mv.normalized().dot(dir_to(chase)) > 0.5:
		k *= 1.18
	return k

## The colour that marks this hunter's effects (from their class).
func accent() -> Color:
	return cdat.get("color", Color.WHITE) if not cdat.is_empty() else Color.WHITE

func max_dashes() -> float:
	var base := float(dodge_def.charges) if dodge_def else float(cdat["dashes"])
	return base + (1.0 if shoulder() == "updraft" else 0.0) + float(perk_n("secondwind"))

func dash_regen() -> float:
	return dodge_def.cooldown if dodge_def else DASH_REGEN

## Right click is always your weapon's ability, as left click is its attack.
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
	hurt_at = m.time
	if base_t > 0.0 and dmg > 0.0:
		cancel_base("you took damage")
	if opts.has("wallstun"):
		wallstun = float(opts["wallstun"])
	# Getting hit while gliding, as in Supervive: a hit does NOT knock you out of the air by itself
	# and you take normal damage. What it does is drain the glider at double the usual rate. Only
	# when the glider runs dry are you spiked (stunned, plummeting, a 0.7s stun when you land; over
	# the abyss that's a fall). Monsters drain it but can't spike you.
	var spiked := false
	if gliding and not dropping and dmg > 0.0 and opts.get("src", "") not in ["fall", "burn", "heat"]:
		var was := glide_fuel
		# a knock's worth of damage (250 of 1,050) would burn 30% of the glider; hits drain it 2x
		glide_fuel = maxf(0.0, glide_fuel - 2.0 * dmg * (0.30 / 34.5) / float(cdat.get("glide_cap", 1.0)))
		hit_heat_t = 1.0
		if is_local() and m.hud and m.hud.has_method("glider_hit"):
			m.hud.glider_hit(was - glide_fuel)
		if opts.get("src", "") == "mob" or by is Mob:
			glide_fuel = maxf(glide_fuel, 0.02)      # monsters can't spike
		elif was <= 0.001 or glide_fuel <= 0.001:
			spiked = true
			_shot_down()
			# spiking someone cools your own glider
			if by is Hunter and (by as Hunter).gliding: (by as Hunter).glide_fuel = minf(1.0, (by as Hunter).glide_fuel + 0.5)
			if by is Hunter: (by as Hunter).add_stat("spikes")
			elif by is Kin and (by as Kin).owner_h: (by as Kin).owner_h.add_stat("spikes")
	var d := dmg
	if ctrl == "local" and m.opts.get("tutorial", false):
		d *= 0.35
	if shoulder() == "bedrock":
		d *= 0.85
	if downed:
		# a wisp can't be shot: it's lost to stomps, an execute, or bleeding out
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
	if drink_t > 0.0 or kit_t > 0.0:
		d *= CONSUME_VULN
	if armor > 0.0 and opts.get("src", "") not in ["fall", "burn", "heat"]:
		d *= 1.0 - ARMOR_DR
		armor = maxf(0.0, armor - d)
		if armor <= 0.0:
			m.on_armor_break(self, by)
	if gliding and d > 0.0:
		m.fx.burst(pos + Vector3(0, 1.6, 0), Color("ffb070"), 6, 2.5, 0.3, 6.0)    # the glider takes the heat
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
## what everyone aims at. It glows purple once your glider is overheated, when the next hit
## knocks you out of the sky.
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
	aura.visible = gliding and glide_fuel <= 0.001
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
	stun_t = maxf(stun_t, 0.35)
	vel = Vector3(vel.x * 0.3, minf(vel.y, -6.0), vel.z * 0.3)
	m.fx.burst(pos + Vector3(0, 1.8, 0), Color("ff9a5a"), 14, 3.0, 0.45, 6.0, 0.8)
	m.sfx("knock", pos, -2.0, 1.3)
	if ctrl == "local" and m.hud:
		m.hud.toast_small("GLIDER SHOT DOWN", Color("ff9a5a"))

## Knockback is a clean, predictable shove: it sets your speed along its direction (it doesn't
## stack with whatever you were doing), you slide for a fixed moment without control, and it never
## pops you into the air unless the attack says so.
var knock_t := 0.0
var knock_steer := 0.3         # how much WASD bends a knockback (the attack decides: 0.3 to 0.5)
func impulse(kbv: Vector2, lift := -1.0) -> void:
	if fortify_t > 0.0:
		return
	var k := kbv * (0.5 if shoulder() == "bedrock" else 1.0)
	var s := k.length() / mass()
	if s < 0.05:
		return
	if s > 4.0:
		kb_t = m.time
	var dir := k / k.length()
	var hv := Vector2(vel.x, vel.z)
	var along := hv.dot(dir)
	hv += dir * (maxf(along, s) - along)
	vel.x = hv.x; vel.z = hv.y
	if s > 2.5:
		knock_t = clampf(0.1 + s * 0.02, 0.12, 0.35)
	if lift >= 0.0:
		vel.y = maxf(vel.y, minf(9.0, lift / mass()))
		grounded = false

func _on_zero(by: Ent, opts: Dictionary) -> void:
	if remote or downed:
		return
	m.knock(self, by, opts)

# ------------------------------------------------------------------ actions
func do_jump() -> void:
	if downed or stun_t > 0.0 or grap.size() > 0 or out:
		return
	if dropping and diving:
		_deploy()
		return
	if pad.size() > 0:
		# press jump mid-flight off a jump pad and the glider opens, keeping the launch's speed
		if not pad.get("ledge", false) and float(pad["t"]) > 0.12 and can_glide():
			pad = {}
			vel.y = minf(vel.y, 2.0)
			_open_glider()
		return
	if roll_t > 0.0 and grounded and move_kind == "dash":
		# jump out of a dash: the dash ends and you keep about half its speed into the jump
		var keep := roll_dir * roll_speed * DASH_JUMP_CARRY
		roll_t = 0.0
		vel.x = keep.x; vel.z = keep.y
	if grounded or coyote > 0.0:
		vel.y = JUMP_V
		grounded = false
		coyote = 0.0
		m.sfx("jump", pos, -6.0)
		return
	# against a wall in the air: kick off it
	var mvk: Vector2 = inp.get("move", Vector2.ZERO)
	if wall_touch_t > 0.0 and wall_kicks > 0 and wall_n.length() > 0.1 and mvk.length() > 0.3 and mvk.normalized().dot(wall_n) > 0.4:
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

## A glider sinks at one steady rate, whatever your speed, so every glide reads the same.
const GLIDE_SINK := 2.2
static func glide_fall(_speed: float) -> float:
	return GLIDE_SINK

## Momentum-preserving acceleration (the Supervive feel): under the wanted speed, move toward it;
## over it (a dash, a pad, a knockback) bleed the extra off slowly while still steering.
static func accel2(cur: Vector2, wish: Vector2, accel: float, decel: float, over_decel: float, dt: float) -> Vector2:
	var mx := wish.length()
	if mx < 0.001:
		return cur.move_toward(Vector2.ZERO, decel * dt)
	var cs := cur.length()
	if cs > mx:
		var wd := wish / mx
		# steering back against your momentum brakes it properly
		var against := maxf(0.0, -(cur / cs).dot(wd))
		var ns := maxf(cs - (over_decel + accel * against) * dt, mx)
		var turn := clampf(accel * dt / cs, 0.0, 1.0)
		var d := (cur / cs).lerp(wd, turn)
		if d.length_squared() < 0.0001: d = wd
		return d.normalized() * ns
	return cur.move_toward(wish, accel * dt)

func can_glide() -> bool:
	return not grounded and roll_t <= 0.0 and fly_t <= 0.0 and glide_cd <= 0.0 and not downed and stun_t <= 0.0 \
		and m.time - kb_t > 0.4 and glide_fuel > 0.15 and not dropping and charge.is_empty()

func _open_glider() -> void:
	gliding = true
	grounded = false
	# unfolding catches the air: a slow start gets carried up to cruising speed
	var hv := Vector2(vel.x, vel.z)
	if hv.length() < GLIDE_SPEED and not dropping:
		# half the gap up front, the rest comes from the glide's own acceleration: no speed snap
		var mvv: Vector2 = inp.get("move", Vector2.ZERO)
		var dirv := mvv.normalized() if mvv.length() > 0.1 else (hv.normalized() if hv.length() > 0.3 else aim_dir())
		hv = hv.lerp(dirv * GLIDE_SPEED, 0.5)
		vel.x = hv.x; vel.z = hv.y
	_glider_sfx("open")
	m.fx.burst(pos + Vector3(0, 1.7, 0), Color("f3eee2"), 8, 2.0, 0.35, 0.0)

## The glider's open/close sound for this hunter's glider skin (quieter, and positional, for everyone else).
func _glider_sfx(which: String) -> void:
	var skin := "classic"
	if model and model.has_node("Rig/Torso/Glider"):
		skin = String(model.get_node("Rig/Torso/Glider").get_meta("skin", "classic"))
	var vol := (-3.0 if is_local() else -9.0) if which == "open" else (-8.0 if is_local() else -14.0)
	Sfx.play_stream(Gliders.sound(skin, which), pos, vol)

## The class's dodge (Shift), as described by its ability data: a dash, plus anything else in its
## effect list (the heavy class's charge shoves people).
## Shift, as in Supervive: a short dash, and a long one (its own, longer cooldown) when you're in
## the air or the short one is still recharging.
var ex_cd := 0.0
var used := {}                  # slot -> times you pressed it and it went off (the tutorial reads this)
var hit_heat_t := 0.0           # a moment after being hit while gliding, the glider heats twice as fast
var ex_next := false
var dash_is_ex := false
var dash_held := 0.0
## Movement chains (Supervive): Shift during a glove rush cancels it into the dash; during a dash
## or a ledge climb it's buffered and fires the moment that ends; off a jump pad (after the first
## beat of the launch) it breaks the pad flight into a dash. Jump out of a ground dash keeps half
## its speed. Dash in the air and keep holding glide and the glider opens again as the dash ends.
## B: base to a teammate (Supervive's recall-to-ally). A 3s channel where you stand still and can't
## attack; moving, attacking or taking any damage cancels it. Everyone sees the channel ring on you
## and a marker on the teammate. You arrive beside them weakened for 3s: half damage, and the crowd
## control, healing and shields you apply are halved.
const BASE_TIME := 3.0
const BASE_CD := 40.0
const WEAK_TIME := 3.0
var base_t := 0.0
var base_to: Hunter = null
var base_cd := 0.0
var weak_t := 0.0
var dash_buf := 0.0

func start_base(to: Hunter) -> void:
	if to == null:
		if is_local() and m.hud: m.hud.toast_small("No teammate to base to", Color("a2a8bb"))
		_ab_feedback("base", "deny")
		return
	if base_cd > 0.0 or downed or out or dropping or riding or not grounded or base_t > 0.0:
		_ab_feedback("base", "deny")
		return
	base_t = BASE_TIME
	base_to = to
	_ab_feedback("base", "cast")
	m.sfx("portal", pos, -6.0, 1.2)
	if is_local() and m.hud: m.hud.toast_small("Basing to %s  ·  hold still" % to.pname, Color("8fe3c8"))

func cancel_base(why := "") -> void:
	if base_t <= 0.0:
		return
	base_t = 0.0
	base_to = null
	base_cd = 4.0          # a short lockout after an interrupted channel
	m.sfx("warn", pos, -10.0, 0.8)
	if is_local() and m.hud and why != "": m.hud.toast_small("Base interrupted: " + why, Color("ff9a8a"))

func _tick_base(dt: float) -> void:
	if base_t <= 0.0:
		return
	var o := base_to
	if o == null or not is_instance_valid(o) or o.out or o.downed or o.extracted or downed or out:
		cancel_base("your teammate can't take you")
		return
	var mv: Vector2 = inp.get("move", Vector2.ZERO)
	if mv.length() > 0.2 or inp.get("fire", false) or inp["dash"] or inp["jump"] or inp["sig"] or inp["sec"] or inp["ult"] or inp.get("gear1", false) or inp.get("throw", false):
		cancel_base("you moved")
		return
	base_t -= dt
	if base_t <= 0.0:
		base_t = 0.0
		base_to = null
		var at := o.pos
		for i in 12:
			var a := TAU * i / 12.0
			var q := o.pos + Vector3(cos(a) * 1.3, 0, sin(a) * 1.3)
			if not m.world.is_void(q.x, q.z) and not m.world.is_block(q.x, q.z) and absf(m.world.ground_at(q.x, q.z) - o.pos.y) < 0.6:
				at = Vector3(q.x, m.world.ground_at(q.x, q.z), q.z); break
		m.fx.ring(pos, 1.6, Color("8fe3c8"), 0.4)
		teleport(at)
		vel = Vector3.ZERO
		weak_t = WEAK_TIME
		base_cd = BASE_CD
		m.fx.ring(at, 1.8, Color("8fe3c8"), 0.45)
		m.sfx("portal", at, -2.0, 1.5)
		if is_local() and m.hud: m.hud.toast_small("Recall weakness: half damage and effects for 3s", Color("ffb36a"))
var air_peak := 0.0              # the highest point of this time in the air (for skyfall landings)
const SKYFALL_H := 8.0           # drop at least this far, fast, onto rivals and you land a skyfall

## Height pays off: come down hard from 8m+ (not gliding gently, not the opening drop) and the
## landing slams everyone close: damage that grows with the height and a pop into the air.
func _skyfall(drop: float, fall_v: float) -> void:
	if drop < SKYFALL_H or fall_v > -6.0 or dropping or downed or remote:
		return
	var k := clampf((drop - SKYFALL_H) / 16.0, 0.0, 1.0)
	var any := false
	for f in m.foes_of(team):
		if flat_dist(f) < 2.4 + f.r and absf(f.pos.y - pos.y) < 2.0:
			any = true
	m.fx.dust(pos, 10)
	if not any:
		return
	Abil._blast(self, pos, 2.4, 10.0 + 16.0 * k, 7.0, Color("ffd27a"), 7.0, "skyfall")
	m.fx.word(pos + Vector3(0, 2.2, 0), "SKYFALL", Color("ffd27a"), true)
	m.shake(0.45, pos)
	add_stat("skyfalls")
var move_kind := "dash"          # what the current roll is: "dash" (Shift) or "rush" (an ability or glove)
const DASH_BUFFER := 0.18
const DASH_JUMP_CARRY := 0.55

func do_dash() -> void:
	if downed or stun_t > 0.0 or root_t > 0.0 or out:
		return
	if roll_t > 0.0 and move_kind == "rush":
		roll_t = 0.0            # a glove/ability rush cancels straight into the dash
	elif pad.size() > 0 and not pad.get("ledge", false) and float(pad.get("t", 0.0)) > 0.12:
		pad = {}                # break out of a jump pad's flight
	elif roll_t > 0.0 or grap.size() > 0 or pad.size() > 0:
		dash_buf = DASH_BUFFER  # pressed a hair early: fire it as soon as this movement ends
		return
	var use_ex := not grounded or dashes < 1.0
	if use_ex:
		if ex_cd > 0.0:
			_ab_feedback("dash", "deny")
			return
		ex_cd = float(cdat.get("ex_cd", EX_DASH_CD))
		ex_next = true
		gliding = false
	else:
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
	move_kind = String(e.get("kind", "dash"))
	dash_is_ex = ex_next
	dash_held = 0.0
	if ex_next:
		# the long dash: the class's own distance and time (light 7m, medium 6m, heavy 5m)
		ex_next = false
		roll_t = float(cdat.get("ex_time", roll_t * 1.45))
		roll_speed = float(cdat.get("ex_dist", roll_speed * roll_t)) / roll_t
		vel.y = maxf(vel.y, 0.0)
	inv_t = maxf(inv_t, float(e.get("invuln", 0.14)))
	shove = {"hit": {}, "kb": float(e.get("shove_kb", 9.0)), "dmg": float(e.get("shove_dmg", 0.0))} if e.get("shove", false) else {}
	if not shove.is_empty():
		fortify_t = maxf(fortify_t, roll_t + 0.1)     # nothing knocks you back mid-charge
	dash_at = m.time
	dodged = false
	fly_t = 0.0
	if wpn.get("bloom_dash_reset", false): wbloom = 0.0
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

const SWAY := [0.0, 0.6, -0.4, 1.0, -0.8, 0.3, -1.0, 0.5]
var shot_n := 0
var safe_pos := Vector3.INF    # the last solid ground you stood on, well away from any edge

## Weapon state that builds up while you fire (Supervive-style): per-shot bloom, a sniper's
## wind-up, a minigun's spin, a rifle's sustained-fire falloff, and a sword's charge.
var wbloom := 0.0              # extra spread in degrees from firing; recovers once you stop
var warm_t := 0.0              # sniper wind-up left; the shot goes when it runs out
var spin := 0.0                # minigun spin, 0 to 1; it only fires fully spun
var spun_t := 0.0              # how long the minigun has been firing (it tightens up)
var sus_n := 0                 # rounds in the current string of fire
var mel_hold := 0.0            # how long the attack key has been held with a sword
var fire_was := false
var swing_buf := 0.0           # a tap that came in mid-swing, played as soon as the swing ends
var lunge_n := 0               # lunges in a row; each one in a short window goes 25% less far
var lunge_at := -9.0
var strike_at_end := {}        # a charged lunge's hit, which lands where the lunge ends

## Called every frame with the attack key's state; decides what that means for this weapon.
func trigger(dt: float) -> void:
	var held: bool = inp["fire"]
	if wpn.get("melee", false):
		swing_buf = maxf(0.0, swing_buf - dt)
		if swing_buf > 0.0 and fire_cd <= 0.0 and can_fire():
			swing_buf = 0.0
			fire()
		if ctrl != "local" or not wpn.has("charge_time"):
			if held: fire()
			return
		# tap for the combo, hold to charge
		var ct := float(wpn["charge_time"])
		var pressed := held and not fire_was
		fire_was = held
		if held:
			if not can_fire() or fire_cd > 0.0:
				if pressed: swing_buf = 0.3     # tapped mid-swing: it plays when this one ends
				return
			mel_hold += dt
			if mel_hold >= ct + 0.35:
				# held well past full: it goes off by itself, and keeps charging the next one
				_charged_attack()
		else:
			if mel_hold >= ct and can_fire():
				_charged_attack()
			elif mel_hold > 0.0:
				if fire_cd > 0.0: swing_buf = 0.3
				else: fire()
			mel_hold = 0.0
		return
	if wpn.has("spin_up"):
		if held and can_fire() and ammo > 0:
			spin = minf(1.0, spin + dt / float(wpn["spin_up"]))
			if spin >= 1.0:
				spun_t += dt
				fire()
		else:
			spin = maxf(0.0, spin - dt / 0.5)
			spun_t = 0.0
			if held and ammo <= 0: start_reload()
		return
	if held:
		fire()

func charge_k() -> float:
	if not wpn.get("melee", false) or not wpn.has("charge_time") or mel_hold <= 0.12:
		return 0.0
	return clampf(mel_hold / float(wpn["charge_time"]), 0.0, 1.0)

func _fire_slow() -> float:
	var firing: bool = fire_cd > 0.0 or warm_t > 0.0 or (spin > 0.0 and inp["fire"]) or charge_k() > 0.0
	if not firing:
		return 1.0
	return float(wpn.get("fire_slow", 1.0 if wpn.get("melee", false) else 0.8))

func fire() -> void:
	if not can_fire() or fire_cd > 0.0 or warm_t > 0.0:
		return
	if wpn.get("melee", false):
		_swing()
		return
	if ammo <= 0:
		start_reload()
		return
	if cloak_t > 0.0:
		cloak_t = 0.0
		m.sfx("cloak", pos, -8.0)
	idle_fire = 0.0
	reveal_t = maxf(reveal_t, 1.2)
	if float(wpn.get("warmup", 0.0)) > 0.0:
		# the sniper winds up with its laser showing, then fires
		warm_t = float(wpn["warmup"])
		fire_cd = 0.0
		m.sfx("charge", pos, -6.0 if is_local() else -12.0, 1.3)
		return
	_release()

## The round actually leaving the gun (straight away, or once a wind-up ends).
func _release() -> void:
	var rate: float = wpn["rate"] * (0.8 if shoulder() == "charge" else 1.0)
	fire_cd = rate
	idle_fire = 0.0
	ammo -= 1
	recoil = 1.0
	muzzle_t = 0.05
	burst_left = int(wpn.get("burst", 1)) - 1
	burst_t = float(wpn.get("burst_gap", 0.07))
	_emit_shot()
	if ammo <= 0 and burst_left <= 0:
		start_reload()

func _tick_weapon(dt: float) -> void:
	if warm_t > 0.0:
		warm_t -= dt
		if not can_fire() or ammo <= 0:
			warm_t = 0.0
		elif warm_t <= 0.0:
			warm_t = 0.0
			_release()
	# per-shot bloom recovers once you've stopped firing for a beat
	if wbloom > 0.0 and idle_fire > float(wpn["rate"]) + 0.2:
		wbloom = maxf(0.0, wbloom - float(wpn.get("bloom_recover", 20.0)) * dt)
	if idle_fire > 0.35 or reload_t > 0.0:
		sus_n = 0
	if not strike_at_end.is_empty():
		if roll_t > 0.0 and not downed and stun_t <= 0.0:
			# the lunge curves to follow your aim
			roll_dir = roll_dir.slerp(aim_dir(), minf(1.0, dt * 6.0)).normalized()
		else:
			var st: Dictionary = strike_at_end
			strike_at_end = {}
			if not downed and stun_t <= 0.0:
				_strike(float(st["dmg"]), float(st["reach"]), float(st["arc"]), float(st["kb"]), st)

## Burst weapons fire the rest of their burst on a short timer (see sim).
var burst_left := 0
var burst_t := 0.0
func _tick_burst(dt: float) -> void:
	if burst_left <= 0:
		return
	burst_t -= dt
	if burst_t > 0.0:
		return
	if ammo <= 0 or not can_fire():
		burst_left = 0
		return
	burst_left -= 1
	burst_t = float(wpn.get("burst_gap", 0.07))
	ammo -= 1
	recoil = 1.0
	muzzle_t = 0.05
	_emit_shot()
	if ammo <= 0 and burst_left <= 0:
		start_reload()

## Melee: a wedge in front of you, a short step into it, and a combo whose last hit lands hardest.
## Swing again within the combo window to keep it going. Hold to charge a heavier attack instead.
var combo_i := 0
var swing_at := -9.0
var swing_t := 0.0             # for the swing animation, counts down
var swing_n := 0
func _swing() -> void:
	var cd: Array = wpn.get("combo_dmg", [])
	var cn: int = cd.size() if cd.size() > 0 else (wpn.get("combo", [1.0]) as Array).size()
	if m.time - swing_at > float(wpn["rate"]) + float(wpn.get("combo_reset", 0.6)):
		combo_i = 0
	var step := combo_i % cn
	var dmg: float = float(cd[step]) if cd.size() > 0 else float(wpn["dmg"]) * float((wpn.get("combo", [1.0]) as Array)[step])
	var last: bool = step == cn - 1
	combo_i += 1
	swing_at = m.time
	fire_cd = float(wpn["rate"]) * (1.35 if last else 1.0)
	# a basic swing never moves you: you keep walking control (fire_slow), and gap-closers live on
	# right click (and in a deliberate held charge where a weapon has one)
	_strike(dmg, float(wpn["range"]), float(wpn.get("arc", 100.0)), float(wpn["kb"]) * (1.5 if last else 1.0), {"heavy": last})

## A step forward with the swing. Lunges close together get 25% shorter each time.
func _lunge(dist: float) -> void:
	if dist <= 0.0 or not grounded:
		return
	if m.time - lunge_at > 1.2:
		lunge_n = 0
	var k := pow(0.75, lunge_n)
	lunge_n += 1
	lunge_at = m.time
	# the speed that covers about dist before ground friction takes it back (it bleeds off slower
	# while you're holding a direction)
	var d2 := aim_dir()
	var moving := (inp["move"] as Vector2).length() > 0.1
	var want := sqrt(2.0 * (GROUND_OVERSPEED if moving else GROUND_DECEL) * dist * k + (base_speed * base_speed if moving else 0.0))
	var hv := Vector2(vel.x, vel.z)
	var along := hv.dot(d2)
	hv += d2 * (maxf(along, want) - along)
	vel.x = hv.x; vel.z = hv.y

func _charged_attack() -> void:
	mel_hold = 0.0
	combo_i = 0
	swing_at = m.time
	fire_cd = float(wpn["rate"]) * 1.8
	var st := {"dmg": float(wpn.get("charged_dmg", float(wpn["dmg"]) * 2.5)), "reach": float(wpn.get("charged_reach", float(wpn["range"]) * (0.85 if wpn.has("charged_lunge") else 1.0))),
		"arc": float(wpn.get("charged_arc", float(wpn.get("arc", 100.0)) * (0.5 if wpn.has("charged_lunge") else 1.0))), "kb": float(wpn.get("charged_kb", float(wpn["kb"]) * 2.0)),
		"stun": float(wpn.get("charged_stun", 0.0)), "heavy": true, "charged": true}
	if wpn.has("charged_lunge"):
		# a lunging stab: you travel, and the hit lands where the lunge ends (charged lunges don't decay)
		var t := 0.2
		roll_dir = aim_dir()
		roll_t = t
		roll_speed = float(wpn["charged_lunge"]) / t
		dash_is_ex = false
		shove = {}
		strike_at_end = st
		m.fx.dash_trail(self)
		m.sfx("dash", pos, -4.0, 0.7)
	else:
		_strike(float(st["dmg"]), float(st["reach"]), float(st["arc"]), float(st["kb"]), st)
		m.shake(0.35, pos)

func _strike(dmg: float, reach: float, arc_deg: float, kb: float, o := {}) -> void:
	idle_fire = 0.0
	reveal_t = maxf(reveal_t, 1.2)
	if cloak_t > 0.0:
		cloak_t = 0.0
	swing_t = 0.18
	swing_n += 1
	var dir := aim_dir()
	var heavy: bool = o.get("heavy", false)
	var arc := deg_to_rad(arc_deg)
	var a0 := atan2(dir.y, dir.x)
	var y := pos.y + 0.95 * float(cdat["scale"])
	var extra := {"kb": kb, "swing": "%s_%d" % [nid, swing_n], "melee": true, "kbi": float(wpn.get("kb_influence", 0.3))}
	if wpn.has("tip_bonus"):
		extra["tip"] = [reach * 0.7, float(wpn["tip_bonus"])]
	if float(o.get("stun", 0.0)) > 0.0: extra["stun"] = float(o["stun"])
	if crit_t > 0.0: extra["crit"] = true
	var sp := shoulder()
	if sp == "kindle": extra["burn"] = 4.0
	if sp == "briar": extra["slow"] = 0.7
	# the swing is a fan of very short, invisible strikes, so walls and terraces block it like shots
	var rays := 9 if arc_deg > 130.0 else 7
	for i in rays:
		var aa := a0 - arc * 0.5 + arc * float(i) / float(rays - 1)
		var st := Vector3(pos.x + cos(aa) * 0.25, y, pos.z + sin(aa) * 0.25)
		m.spawn_shot(self, st, Vector2(cos(aa), sin(aa)) * 40.0, dmg * m.dmg_mult(self), maxf(0.02, (reach - 0.25) / 40.0), 0.22, wpn["color"], extra)
	m.fx.slash(Vector3(pos.x, y - 0.15, pos.z), a0, arc, reach, wpn["color"], heavy)
	m.sfx(wpn["sfx"], pos, -4.0 if not o.get("charged", false) else 0.0, (0.8 if heavy else 1.15) + randf() * 0.1)

func _emit_shot() -> void:
	var dir := aim_dir()
	# no dice rolls: every shot goes where you aim. Fast guns sway in a fixed, learnable pattern,
	# wider as per-shot bloom builds up
	shot_n += 1
	var spread: float = float(wpn["spread"])
	var rng_add := 0.0
	if wpn.has("tighten_from_deg"):
		var tk := clampf(spun_t / float(wpn.get("tighten_time", 1.5)), 0.0, 1.0)
		spread = deg_to_rad(lerpf(float(wpn["tighten_from_deg"]), rad_to_deg(float(wpn["spread"])), tk))
		rng_add = float(wpn.get("spun_range", 0.0)) * tk
	var pel := int(wpn.get("pellets", 1))
	if pel <= 1:
		spread += deg_to_rad(wbloom)
	var a: float = atan2(dir.y, dir.x) + spread * 0.45 * float(SWAY[shot_n % SWAY.size()])
	var shot_y := pos.y + 0.95 * float(cdat["scale"])
	var start := Vector3(pos.x + cos(a) * 0.6, shot_y, pos.z + sin(a) * 0.6)
	var spd: float = wpn["speed"]
	var rng: float = float(wpn["range"]) + rng_add
	var life: float = rng / spd
	var dmg: float = float(wpn["dmg"]) * m.dmg_mult(self)
	if wpn.has("sustain_loss"):
		dmg *= 1.0 - float(wpn["sustain_loss"]) * minf(1.0, float(sus_n) / float(wpn.get("sustain_rounds", 10)))
	sus_n += 1
	var extra := {"kb": wpn["kb"]}
	if wpn.has("decel"):
		# slugs slow down and stop at the weapon's range: v^2 = 2 a d
		extra["decel"] = float(wpn["decel"])
		spd = sqrt(2.0 * float(wpn["decel"]) * rng)
		life = spd / float(wpn["decel"]) + 0.05
	if wpn.has("close_mult"):
		extra["near"] = [float(wpn["close_mult"]), rng * 0.5]
	if wpn.has("far_mult"):
		extra["farf"] = [rng * float(wpn.get("far_start", 0.6)), float(wpn["far_mult"]), rng]
	if wpn.has("boom"):
		var aim: Vector3 = inp["aim"]
		var dist := clampf(Vector2(aim.x - pos.x, aim.z - pos.z).length(), 1.5, rng)
		life = dist / spd
		extra["boom"] = wpn["boom"]; extra["boom_kb"] = wpn["boom_kb"]
	var sp := shoulder()
	if crit_t > 0.0:
		extra["crit"] = true
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
	if pel > 1:
		# a shotgun throws the same fixed fan every time, wider with each shot in a row. However
		# few slugs land, the first one on a target still does a good share of the whole volley
		var fan: float = deg_to_rad(float(wpn.get("fan_deg", 23.0)) + wbloom) if wpn.has("fan_deg") else float(wpn.get("fan", 0.4))
		extra["pg"] = "%s_%d" % [nid, shot_n]
		extra["pn"] = pel
		extra["pf"] = float(wpn.get("pellet_floor", 1.0 / pel))
		for i in pel:
			var pa := a - fan * 0.5 + fan * float(i) / float(pel - 1)
			m.spawn_shot(self, Vector3(pos.x + cos(pa) * 0.6, shot_y, pos.z + sin(pa) * 0.6), Vector2(cos(pa), sin(pa)) * spd, dmg, life, wpn["size"], wpn["color"], extra)
	else:
		m.spawn_shot(self, start, Vector2(cos(a), sin(a)) * spd, dmg, life, wpn["size"], wpn["color"], extra)
	if wpn.has("bloom_deg"):
		wbloom = minf(float(wpn.get("bloom_max_deg", 6.0)), wbloom + float(wpn["bloom_deg"]))
	m.sfx(wpn["sfx"], pos, -2.0 if is_local() else -6.0)

func start_reload() -> void:
	if reload_t > 0.0 or ammo >= int(wpn["mag"]) or downed or wpn.get("melee", false):
		return
	reload_t = float(wpn["reload"]) * (0.8 if shoulder() == "charge" else 1.0) * (0.7 if perk_n("quickhands") > 0 else 1.0)
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
		_ab_feedback(slot, "deny")
		if is_local() and m.hud:
			m.hud.toast("%s is resting%s" % [k.rec.get("name", "Your kin"), ("  ·  %s swaps in %s" % [Settings.key_cap("swap_kin"), (kin2 as Kin).rec.get("name", "your other kin")]) if kin2 and (kin2 as Kin).hp > 0.0 else ""], Color("a2a8bb"))
		return
	if k.use_ability(slot, _ground_aim()) or k.pend_slot == slot:
		used[slot] = int(used.get(slot, 0)) + 1
		_ab_feedback(slot, "cast")
		if is_local():
			# tie the button to what happened: a flash line from you to the kin doing it, if it's away
			if k.flat_dist(self) > 2.5 and k.state != "shoulder":
				m.fx.bolt(pos + Vector3(0, 1.2, 0), k.pos + Vector3(0, 0.6, 0), Color(k.runner.def_of(slot).color, 0.8))
			m.fx.ring(k.pos, 1.3, k.runner.def_of(slot).color, 0.3)
	else:
		_ab_feedback(slot, "deny")

## R: the bond ultimate, once fighting together has filled the meter.
func use_ultimate() -> void:
	if Ultimate.cast(self):
		_ab_feedback("r", "cast")
		return
	_ab_feedback("r", "deny")
	if is_local() and m.hud and ult >= 1.0 and kin and not (kin as Kin).ready_to_fight():
		m.hud.toast("Your kin has to be with you", Color("a2a8bb"))

## Tells the HUD a button press landed ("cast": the slot pops) or didn't ("deny": it shakes red
## with a soft buzz), so a press on cooldown never just silently does nothing.
func _ab_feedback(slot: String, kind: String) -> void:
	if not is_local() or m.hud == null or not m.hud.has_method("ability_feedback"):
		return
	m.hud.ability_feedback(slot, kind)
	if kind == "deny":
		m.sfx("warn", null, -16.0, 1.6)
	else:
		m.sfx("skill", null, -9.0, 1.15)

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

## 1: heal. One key for both consumables: a tonic when you're hurt, otherwise an armor kit when
## your armor is down. Pressing it with nothing to fix (or nothing to use) buzzes.
func use_heal() -> void:
	if drink_t > 0.0 or kit_t > 0.0:
		return
	if tonics > 0 and hp < max_hp - 0.5:
		use_tonic()
	elif armor_kits > 0 and armor < max_armor - 0.5:
		use_kit()
	else:
		_ab_feedback("tonic", "deny")
		return
	_ab_feedback("tonic", "cast")

## Repairing armor with a kit: the same kind of short channel as a tonic.
var armor_kits := 1
var finish_t := 0.0             # holding interact over a downed enemy (until the stomp commits)
var stomp: Dictionary = {}      # committed stomp on an enemy wisp: {o, t, hits} (see Life)
var kit_t := 0.0
func use_kit() -> void:
	if armor_kits <= 0 or downed or armor >= max_armor - 0.5 or kit_t > 0.0 or drink_t > 0.0 or gliding or not grounded:
		return
	kit_t = KIT_TIME
	m.sfx("build", pos, -6.0, 1.3)

func _tick_kit(dt: float) -> void:
	if kit_t <= 0.0:
		return
	if downed or stun_t > 0.0 or roll_t > 0.0 or gliding or out:
		kit_t = 0.0
		return
	kit_t -= dt
	if kit_t <= 0.0:
		kit_t = 0.0
		armor_kits -= 1
		armor = max_armor
		m.sfx("shield", pos, -2.0, 1.2)
		m.fx.burst(pos + Vector3(0, 1.2, 0), Color("dfe9f7"), 16, 2.5, 0.5, -3.0)

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
			heal(max_hp * 0.4 * (1.4 if perk_n("remedy") > 0 else 1.0))
			m.sfx("heal", pos, -2.0)
			m.fx.burst(pos + Vector3(0, 1.2, 0), Color("8ff0a0"), 14, 2.5, 0.5, -3.0)

func launch_to(target: Vector3, t: float) -> void:
	vel.x = (target.x - pos.x) / t
	vel.z = (target.z - pos.z) / t
	vel.y = (target.y - pos.y) / t + 0.5 * H_GRAV * t
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
	if grounded:
		air_peak = pos.y
	for k in ["base_cd", "weak_t", "dash_buf", "hit_heat_t", "ex_cd", "reveal_t", "inv_t", "fire_cd", "coyote", "jump_buf", "mantle_cd", "grap_cd", "sig_cd", "cloak_t", "haste_t", "fortify_t", "recoil", "muzzle_t", "regen_wait", "land_t", "glide_cd", "bless_t", "crit_t", "sick_t"]:
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
	armor_wait = maxf(0.0, armor_wait - dt)
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
	# reload by itself once you stop shooting for a moment
	idle_fire += dt
	if idle_fire > 1.3 and ammo < int(wpn["mag"]) and reload_t <= 0.0 and not inp["fire"]:
		start_reload()
	if downed:
		# your other kin comes out of the satchel to pick you up if the active one can't
		if kin and (kin as Kin).state == "fainted" and kin2 and (kin2 as Kin).hp > 0.0:
			swap_kin(true)
		# a wisp doesn't bleed out: it's lost to enemy stomps, a finish, or more damage
		if down_hp <= 0.0:
			m.eliminate(self, last_hit_by, "finished")
			return
	# mid-stomp you're committed: none of your own buttons do anything until it ends
	if not stomp.is_empty():
		for kk in ["dash", "jump", "sig", "skill", "sec", "ult", "swap", "reload", "tonic", "kit", "gear1", "gear2", "fire", "throw"]:
			inp[kk] = false
		inp["move"] = Vector2.ZERO
	# inputs
	_tick_base(dt)
	if base_t > 0.0:
		inp["fire"] = false        # channeling: no attacks while you base
	if inp["dash"]: do_dash()
	if dash_buf > 0.0 and roll_t <= 0.0 and grap.is_empty() and pad.is_empty() and not inp["dash"]:
		dash_buf = 0.0
		do_dash()
	if inp["jump"]: do_jump()
	if runner:
		runner.rate = 1.0 + gear_stat("cdr")
		runner.tick(dt)
	var cdr := gear_stat("cdr")
	if cdr > 0.0:
		sig_cd = maxf(0.0, sig_cd - dt * cdr)
	for gi in 2:
		gear_cd[gi] = maxf(0.0, float(gear_cd[gi]) - dt)
		if inp.get("gear%d" % (gi + 1), false):
			if (gear[gi] as Dictionary).is_empty() or float(gear_cd[gi]) > 0.0 or not Gear.active(String(gear[gi].get("id", ""))):
				_ab_feedback("gear%d" % gi, "deny")
			else:
				m.use_gear(self, gi)
	if inp["sig"]: use_kin_ability("k1")
	# (a kin's second ability and mid-fight kin swaps are retired from the kit; bots don't press them)
	if inp["sec"] and runner and runner.has_slot("utility"):
		if runner.use("utility"):
			used["utility"] = int(used.get("utility", 0)) + 1
			_ab_feedback("sec", "cast")
		else:
			_ab_feedback("sec", "deny")
	if inp["reload"]: start_reload()
	if inp["tonic"]: use_heal()
	if inp.get("kit", false): use_kit()
	_tick_drink(dt)
	_tick_kit(dt)
	_tick_burst(dt)
	_tick_weapon(dt)
	swing_t = maxf(0.0, swing_t - dt)
	if inp["ult"]: use_ultimate()
	trigger(dt)
	inp["dash"] = false; inp["jump"] = false; inp["sig"] = false; inp["reload"] = false; inp["tonic"] = false; inp["kit"] = false; inp["ult"] = false; inp["sec"] = false; inp["gear1"] = false; inp["gear2"] = false
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
	var np: Vector3
	if pad.has("face"):
		np = _mantle_point(k)
	else:
		var y := lerpf(a.y, b.y, k) + 4.0 * float(pad["h"]) * k * (1.0 - k)
		np = Vector3(lerpf(a.x, b.x, k), y, lerpf(a.z, b.z, k))
	vel = (np - pos) / maxf(dt, 0.0001)
	pos = np
	if k >= 1.0:
		pos = b
		var ledge: bool = pad.get("ledge", false)
		var hvel := Vector2(vel.x, vel.z)
		if ledge and hvel.length() > 0.01:
			# out of a mantle you keep running in the same direction, no stop
			hvel = hvel.normalized() * float(pad.get("carry", base_speed))
		vel = Vector3(hvel.x, 0.0, hvel.y).limit_length(base_speed * 1.3)
		grounded = true
		pad = {}
		squash = 0.12 if ledge else 0.3
		m.fx.dust(pos, 3 if ledge else 8)
		m.sfx("land", pos, -12.0 if ledge else -8.0)

## Where a mantle has you at progress k (0..1): up the face with an ease-out (a quick pull that
## slows near the top), then over the lip with a small hop and an ease-in-out onto the top. The
## height never drops below the lip while you're over the cliff, so you can't sink into it.
func _mantle_point(k: float) -> Vector3:
	var a: Vector3 = pad["from"]; var f: Vector3 = pad["face"]; var b: Vector3 = pad["to"]
	var lip: float = pad["lip"]
	var sp: float = pad["split"]
	if k < sp:
		var u := k / maxf(0.001, sp)
		var e := 1.0 - (1.0 - u) * (1.0 - u)
		var hz := clampf(u * 3.0, 0.0, 1.0)          # snap against the wall in the first third
		return Vector3(lerpf(a.x, f.x, hz), lerpf(a.y, lip, e), lerpf(a.z, f.z, hz))
	var u2 := (k - sp) / maxf(0.001, 1.0 - sp)
	var e2 := u2 * u2 * (3.0 - 2.0 * u2)
	return Vector3(lerpf(f.x, b.x, e2), lerpf(lip, b.y, e2) + 0.22 * sin(u2 * PI), lerpf(f.z, b.z, e2))

## How far through the climbing part of a mantle you are (0 when not mantling), for the animation.
func mantle_k() -> float:
	if pad.is_empty() or not pad.has("face"):
		return 0.0
	var k := clampf(float(pad["t"]) / float(pad["dur"]), 0.0, 1.0)
	return 1.0 if k < float(pad["split"]) + 0.15 else 0.0

func _physics(dt: float) -> void:
	if pad.size() > 0:
		_pad_fly(dt)
		return
	if grap.size() > 0:
		_grapple(dt)
		return
	var mv: Vector2 = inp["move"] if stun_t <= 0.0 and root_t <= 0.0 else Vector2.ZERO
	var spd := base_speed * (1.35 if haste_t > 0.0 else 1.0) * (0.4 * (Life.R["stomp_slow"] if get_meta("stomped", false) else 1.0) if downed else 1.0) * (0.65 if slow_t > 0.0 else 1.0) * (0.88 if reload_t > 0.0 else 1.0) * _fire_slow() * (0.45 if drink_t > 0.0 or kit_t > 0.0 else 1.0) * (0.55 if crouch else 1.0) * (1.0 + gear_stat("speed")) * fuse_mod("speed") * _chase_mod(mv)
	var hv := Vector2(vel.x, vel.z)
	var cur := hv.length()
	if roll_t > 0.0:
		roll_t -= dt
		# the "hold for the long dash" option: keep Shift down and the short dash stretches into
		# the long one, which then goes on its own cooldown
		if inp.get("dash_hold", false) and not dash_is_ex and ex_cd <= 0.0:
			dash_held += dt
			if dash_held >= 0.12:
				dash_is_ex = true
				ex_cd = float(cdat.get("ex_cd", EX_DASH_CD))
				roll_t += 0.08
				roll_speed *= 1.2
		hv = roll_dir * roll_speed
		if not shove.is_empty():
			_shove_along()
		if roll_t <= 0.0:
			# out of a dash you keep some of its speed: a little on the ground, most in the air
			hv = roll_dir * roll_speed * (DASH_CARRY_GROUND if grounded else DASH_CARRY_AIR)
	elif fly_t > 0.0:
		fly_t -= dt
	elif knock_t > 0.0:
		knock_t -= dt
		hv = hv.move_toward(Vector2.ZERO, 6.0 * dt)
		# directional influence: hold a key to bend the knockback, never to cancel it
		if mv.length() > 0.1:
			var spd0 := hv.length()
			hv = (hv + mv * spd0 * knock_steer * 4.0 * dt).limit_length(spd0)
	elif gliding:
		# the glider keeps the speed you bring into it (a dash or a pad into a glide carries) and
		# drifts on when you let go of the keys
		var gs := (DIVE_SPEED if diving else DROP_SPEED) if dropping else (GLIDE_SPEED * 0.6 if glide_fuel <= 0.001 else GLIDE_SPEED) * (1.0 + gear_stat("glide_speed"))
		hv = accel2(hv, mv * gs, GLIDE_ACCEL, GLIDE_DECEL, GLIDE_OVERSPEED, dt)
		if dropping:
			# the drop goes where you point and stops when you let go: no fixed heading to circle on
			hv = Vector2(vel.x, vel.z).lerp(mv * gs, 1.0 - exp(-(3.0 if diving else 4.0) * dt))
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
		# near-instant on the ground; in the air you steer well but momentum carries
		if grounded:
			hv = accel2(hv, mv * spd, GROUND_ACCEL, GROUND_DECEL, GROUND_OVERSPEED, dt)
		else:
			hv = accel2(hv, mv * spd, AIR_ACCEL, AIR_DECEL, AIR_OVERSPEED, dt)
	vel.x = hv.x; vel.z = hv.y
	update_lip()
	_update_glide(dt)
	if gliding and in_current:
		pass   # the current sets the height
	elif gliding and not dropping and below_lip and glide_fuel > 0.001:
		# below ground level over the abyss the glider lifts you hard, then brakes near the top.
		# Let go just before ground level to carry the lift up as height (feathering)
		var depth := lip_y - pos.y
		if depth > ABYSS_BRAKE_DIST:
			vel.y = minf(vel.y + ABYSS_LIFT * dt, ABYSS_LIFT_MAX)
		else:
			vel.y = move_toward(vel.y, maxf(depth * 2.0, 1.0), ABYSS_BRAKE * dt)
	elif gliding:
		var sink := (DIVE_FALL if diving else DROP_FALL) if dropping else (3.0 if glide_fuel <= 0.001 else glide_fall(Vector2(vel.x, vel.z).length()))
		if dropping:
			vel.y = lerpf(vel.y, -sink, 1.0 - exp(-4.0 * dt))
		else:
			if vel.y < -sink:
				vel.y = move_toward(vel.y, -sink, GLIDE_CATCH * dt)    # the canopy catches you over a beat
			else:
				vel.y = maxf(vel.y - GLIDE_GRAV * dt, -sink)
			# [footage] over the abyss a glider holds at island level instead of sinking below it,
			# so you can cross until the heat runs out
			if over_void() and glide_fuel > 0.001 and vel.y < 0.0 and pos.y + vel.y * dt < lip_y:
				vel.y = minf(0.0, (lip_y - pos.y) / dt)
	elif roll_t > 0.0 and not grounded and not dropping:
		vel.y = 0.0          # a dash in the air holds your height for its length
	elif not grounded:
		if vel.y > 0.0 or fly_t > 0.0:
			vel.y -= H_GRAV * dt          # rising: the same snappy jump arc
			vel.y = maxf(vel.y, -TERMINAL)
		else:
			# falling: speed builds smoothly and eases into terminal instead of hitting it in a third
			# of a second, so drops off edges and into the abyss read as one flowing motion
			vel.y = lerpf(vel.y, -TERMINAL, 1.0 - exp(-FALL_EASE * dt))
	# walking can't take you off an edge, except as a wisp: a downed player can drift off a ledge on
	# purpose to escape a stomp, and catch the cliff on the way down (see _try_ledge_grab)
	var guard := grounded and roll_t <= 0.0 and hv.length() <= spd * 1.25 and not (downed and ctrl == "local")
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
		# walking into a single terrace steps you up it smoothly, no hop
		step_vis -= step_up - pos.y
		pos.y = step_up
		prev.y = pos.y
		var fw := mv.normalized() * spd * dt
		if m.world.occupy(pos.x + fw.x, pos.z + fw.y, r, pos.y, guard) == 0.0:
			pos.x += fw.x; pos.z += fw.y
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
		vel.y = sqrt(2.0 * H_GRAV * (blk - pos.y + 0.3))
		mantle_cd = 0.45
	var g := ground()
	if grounded and g < pos.y - 0.05:
		grounded = false
		vel.y = minf(vel.y, 0.0)
		coyote = 0.12
	if not grounded:
		var fv := vel.y
		pos.y += vel.y * dt
		air_peak = maxf(air_peak, pos.y)
		if g > World.VOID + 1.0 and vel.y <= 0.0 and pos.y <= g and pos.y > g - 1.25:
			pos.y = g
			vel.y = 0.0
			grounded = true
			fly_t = 0.0
			_skyfall(air_peak - g, fv)
			air_peak = g
			if gliding:
				gliding = false
				m.fx.dust(pos, 5)
			if dropping:
				dropping = false
				diving = false
				m.on_drop_landed(self)
			if shot_down:
				# spiked onto the ground [wiki]: a 0.7s stun and a little extra damage
				shot_down = false
				stun_t = maxf(stun_t, SPIKE_STUN)
				hurt(SPIKE_DMG, last_hit_by, {"src": "fall"})
				m.fx.dust(pos, 12)
				m.fx.ring(pos + Vector3(0, 0.05, 0), 1.6, Color(1.0, 0.6, 0.4, 0.6), 0.3)
				if is_local(): m.shake(0.25, pos)
			if fv < -11.0 or cur > spd * 1.3:
				m.fx.dust(pos, 6)
				squash = 0.15
				land_t = 0.2
				m.sfx("land", pos, -10.0)
			if fv < -17.0:
				# a long drop lands hard: a thud, a ring of dust and a short stagger
				m.fx.dust(pos, 12)
				m.fx.ring(pos + Vector3(0, 0.05, 0), 1.4, Color(1, 1, 1, 0.5), 0.3)
				squash = 0.25
				land_t = 0.32
				if is_local(): m.shake(0.18, pos)
			if jump_buf > 0.0:
				jump_buf = 0.0
				vel.y = JUMP_V
				grounded = false
	else:
		pos.y = g
	if grounded:
		last_gy = pos.y
		if int(m.time * 10.0) != int((m.time - dt) * 10.0) and not dropping:
			var w: World = m.world
			if not (w.is_void(pos.x + 1.4, pos.z) or w.is_void(pos.x - 1.4, pos.z) or w.is_void(pos.x, pos.z + 1.4) or w.is_void(pos.x, pos.z - 1.4)):
				safe_pos = pos
	_try_ledge_grab(dt)
	if pos.y < last_gy - 24.0 or pos.y < -40.0:
		fall_out()

## The skydive ends: the glider snaps open and the fall slows right down.
func _deploy() -> void:
	if not diving:
		return
	diving = false
	glide_k = 0.0
	vel.y = maxf(vel.y, -3.0)
	m.sfx("glide", pos, -2.0)
	m.fx.burst(pos + Vector3(0, 1.7, 0), Color("f3eee2"), 12, 3.0, 0.4, 0.0)

## Hold jump while falling to open the glider. It folds when you land, run out, dash, or get hit.
var air_t := 0.0                # time since you left the ground
func _update_glide(dt: float) -> void:
	air_t = 0.0 if grounded else air_t + dt
	if dropping:
		# the opening drop: the glider stays open until you land, or until you sink below the islands
		gliding = not grounded
		if diving:
			var void_below: bool = m.world.is_void(pos.x, pos.z)
			var above: float = pos.y - (World.VOID if void_below else m.world.ground_at(pos.x, pos.z))
			if (not void_below and above < DEPLOY_H) or (void_below and pos.y < 7.0):
				_deploy()
		if pos.y < -1.5:
			dropping = false
			diving = false
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
			_glider_sfx("close")
			if glide_fuel <= 0.0:
				glide_cd = 0.5
		elif not in_current:
			# heat builds faster while the glider is lifting you out of the abyss
			var hk := (4.0 if below_lip and lip_y - pos.y > 0.3 and vel.y > 0.0 else 1.0) * (2.0 if hit_heat_t > 0.0 else 1.0)     # [footage] ~1s of lift burns a quarter
			glide_fuel = maxf(0.0, glide_fuel - dt * hk / (glide_max * (1.0 + gear_stat("heat"))))
		if not dropping:
			stats["glide_t"] = float(stats.get("glide_t", 0.0)) + dt
	elif want and can and air_t >= GLIDE_ENGAGE and glide_fuel > 0.15 and not gliding:
		# hold Space in the air and the glider opens a beat after you leave the ground
		gliding = true
		if below_lip:
			m.fx.burst(pos + Vector3(0, 1.2, 0), Color("cfeaff"), 12, 3.5, 0.4, -2.0, 0.8)
			m.sfx("glide", pos, -2.0, 1.4)
			add_stat("feathers")
		_glider_sfx("open")
		m.fx.burst(pos + Vector3(0, 1.7, 0), Color("f3eee2"), 8, 2.0, 0.35, 0.0)

# Ledge float: touch the side of any ground above you while you're still alive and you float
# back up onto it, the way Supervive does it. Walking into a step up a few terraces high does
# the same after a short push. Getting launched hard still carries you past the edge.
func _try_ledge_grab(dt: float) -> void:
	if grap.size() > 0 or pad.size() > 0 or fly_t > 0.0 or charge.size() > 0 or dropping or shot_down or pos.y < last_gy - 14.0 or (grounded and stun_t > 0.0):
		push_t = 0.0
		return
	var w: World = m.world
	var mv: Vector2 = inp["move"]
	var reach := 0.0
	var max_rise := MANTLE_REACH
	if grounded:
		# as in Supervive, walking into a wall doesn't climb it: jump, and you mantle at the top.
		# Bots still lean their way up so their paths work.
		if mv.length() < 0.5 or grap_cd > 0.0 or ctrl == "local":
			push_t = 0.0
			return
		var probe := Vector2(pos.x, pos.z) + mv.normalized() * (r + 0.35)
		var g2 := w.ground_at(probe.x, probe.y)
		if w.is_block(probe.x, probe.y) or g2 <= pos.y + World.STEP or g2 - pos.y > World.LEVEL * 2.0 + 0.05:
			push_t = 0.0
			return
		push_t += dt
		if push_t < 0.08:
			return
		reach = r + 0.6
		max_rise = World.LEVEL * 2.0 + 0.1
	else:
		push_t = 0.0
		# a hard launch carries you a moment before you can catch anything
		if vel.y > 2.0 or grap_cd > 0.0 or (m.time - kb_t < 0.3 and Vector2(vel.x, vel.z).length() > 8.0):
			return
		# no magnet: you have to be below the edge, right up against the cliff, and pushing into it
		if mv.length() < 0.3:
			return
		reach = r + 0.4
	var void_here := over_void()
	if not grounded and void_here and last_gy - pos.y > 0.3:
		max_rise = MANTLE_REACH_ABYSS      # deep in the abyss, any island wall you touch springs you back up
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
	# Supervive-style mantle: no hang and no stop, one quick fluid vault from wherever you touched
	# the cliff up and over onto the top, carrying your run on the far side
	var rise: float = float(best["gz"]) - pos.y
	var hv0 := Vector2(vel.x, vel.z)
	var dir_in := Vector2(cos(a), sin(a))
	var carry := clampf(hv0.dot(dir_in), 0.0, base_speed * 1.3)
	var over := Vector3(land.x + dir_in.x * carry * 0.12, land.y, land.z + dir_in.y * carry * 0.12)
	if not w.is_block(over.x, over.z) and absf(w.ground_at(over.x, over.z) - land.y) < 0.1:
		land = over
	# the climb goes in two parts so the body never cuts through the cliff's corner: first straight
	# up the face (held just outside the wall), then forward over the lip once you're above it
	var face := Vector3(float(best["ex"]) - dir_in.x * (r + 0.05), pos.y, float(best["ez"]) - dir_in.y * (r + 0.05))
	if w.is_block(face.x, face.z) or w.ground_at(face.x, face.z) > pos.y + 0.05:
		face = Vector3(pos.x, pos.y, pos.z)
	var up_t := clampf(rise / MANTLE_RISE, 0.16, 0.85) * (1.35 if downed else 1.0)
	var over_t := 0.2 * (1.3 if downed else 1.0)
	pad = {"from": pos, "face": face, "lip": float(best["gz"]) + 0.14, "to": land, "t": 0.0, "dur": up_t + over_t, "split": up_t / (up_t + over_t),
		"ledge": true, "carry": maxf(carry, base_speed * 0.8)}
	grap = {}
	grap_cd = LEDGE_CD
	push_t = 0.0
	gliding = false
	roll_t = 0.0
	m.sfx("grab", pos, -8.0, 1.2)
	m.fx.burst(pos + Vector3(0, 0.6, 0), Color("cfeaff"), 6, 2.0, 0.3, 0.0)
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
	for pk in perks:
		t += float((Data.PERKS.get(pk, {}).get("stats", {}) as Dictionary).get(k, 0.0))
	return t

## How many stacks of a perk you've picked up this run.
func perk_n(id: String) -> int:
	return perks.count(id)

## Can this perk still be offered to you (not at its stack limit)?
func perk_open(id: String) -> bool:
	return perk_n(id) < int(Data.PERKS.get(id, {}).get("max", 1))

## Takes a perk for the rest of the expedition. Stats that are worked out once (health, glider,
## dash charges, armor) are updated on the spot.
func add_perk(id: String) -> void:
	if not Data.PERKS.has(id) or not perk_open(id):
		return
	perks.append(id)
	match id:
		"toughskin":
			max_hp += 15.0; hp = minf(max_hp, hp + 15.0)
		"featherfall":
			glide_max *= 1.6
		"secondwind":
			dashes = minf(max_dashes(), dashes + 1.0)
	refresh_gear()

func add_stat(k: String, n := 1) -> void:
	stats[k] = int(stats.get(k, 0)) + n
var unseen := false           # hidden from the local player (in a bush, or behind a wall)

var step_vis := 0.0            # eases the model up a terrace you just stepped onto
## The sniper's aiming laser while it winds up, and the minigun's barrels spinning.
var laser: MeshInstance3D
func _render_weapon_fx(delta: float) -> void:
	var on := warm_t > 0.0 and visible and not unseen
	if on and laser == null:
		laser = MeshInstance3D.new()
		var bm := BoxMesh.new(); bm.size = Vector3(0.04, 0.04, 1.0)
		laser.mesh = bm
		laser.material_override = Models.glow_mat(Color(wpn["color"], 0.7))
		laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		laser.top_level = true
		add_child(laser)
	if laser:
		laser.visible = on
		if on:
			var k := 1.0 - warm_t / maxf(0.01, float(wpn.get("warmup", 0.6)))
			var d := aim_dir()
			var y := position.y + 0.95 * float(cdat["scale"])
			var ln := float(wpn["range"])
			var a := Vector3(position.x + d.x * 0.6, y, position.z + d.y * 0.6)
			laser.global_transform = Transform3D(Basis.looking_at(Vector3(d.x, 0, d.y), Vector3.UP), a + Vector3(d.x, 0, d.y) * ln * 0.5)
			laser.scale = Vector3(lerpf(2.5, 0.6, k), lerpf(2.5, 0.6, k), ln)
			(laser.material_override as ShaderMaterial).set_shader_parameter("color", Color(wpn["color"], lerpf(0.25, 0.9, k)))
	if spin > 0.0 and model:
		var br: Node3D = model.find_child("Barrels", true, false)
		if br: br.rotation.z += delta * spin * 40.0

func render(delta: float, alpha: float) -> void:
	super.render(delta, alpha)
	if absf(step_vis) > 0.001:
		position.y += step_vis
		step_vis = lerpf(step_vis, 0.0, 1.0 - exp(-16.0 * delta))
	visible = not out and not extracted and not riding and not unseen
	if not model:
		return
	model.rotation.y = face
	if remote:
		update_lip()
	_render_balloon()
	_render_weapon_fx(delta)
	var rig: Node3D = model.get_node("Rig")
	var torso: Node3D = rig.get_node("Torso")
	if anim == null or anim.model != model:
		anim = HunterAnim.new(model)
	var hv := Vector2(vel.x, vel.z)
	var spd := hv.length()
	crouch_k = move_toward(crouch_k, 1.0 if crouch else 0.0, delta * 8.0)
	anim.update(delta, {"vel": vel, "face": face, "grounded": grounded and pad.is_empty(), "gliding": gliding and not diving, "rolling": roll_t > 0.0,
		"crouch": crouch_k, "downed": downed, "ledge": grap.size() > 0 or mantle_k() > 0.0, "stomp": (fmod(float(stomp["t"]), Life.R["stomp_cycle"]) / Life.R["stomp_cycle"]) if not stomp.is_empty() else -1.0, "reload": (1.0 - reload_t / maxf(0.1, float(wpn["reload"]))) if reload_t > 0.0 else -1.0, "drink": (1.0 - drink_t / DRINK_TIME) if drink_t > 0.0 else -1.0,
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
		# skydiving: flat out, belly to the ground, tipped toward where you steer
		rig.rotation.x = lerpf(rig.rotation.x, -1.15 if diving else 0.0, delta * (5.0 if diving else 10.0))
	glide_k = move_toward(glide_k, 1.0 if gliding and not diving else 0.0, delta * (7.0 if gliding else 9.0))
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
	if wpn.get("melee", false):
		# a swing sweeps the weapon across in front of you, alternating sides each hit
		var sk := swing_t / 0.18
		var side := 1.0 if swing_n % 2 == 0 else -1.0
		gun.rotation.y = side * lerpf(-1.3, 1.3, sk) if swing_t > 0.0 else lerpf(gun.rotation.y, 0.0, minf(1.0, delta * 10.0))
		gun.position.z = -0.18
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
