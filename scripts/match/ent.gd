class_name Ent
extends Node3D
## Base for everything that moves and takes damage: hunters, kin and monsters.
## The simulation writes `pos`; the visual node is moved toward it every rendered frame.

const GRAV := 30.0

var m: Node = null          # the Match
var nid := ""
var team := -1
var kind := ""
var pos := Vector3.ZERO
var prev := Vector3.ZERO
var vel := Vector3.ZERO
var r := 0.4
var hp := 100.0
var max_hp := 100.0
var grounded := true
var dead := false
var face := 0.0             # yaw the model looks toward
var model: Node3D = null
var mats: Array = []
var flash_t := 0.0
var freeze_t := 0.0         # visual hit-pause
var burn_t := 0.0
var burn_dps := 0.0
var burn_by: Ent = null
var slow_t := 0.0
var root_t := 0.0
var stun_t := 0.0
var guard_t := 0.0          # taking less damage for a moment (Rock Guard)
var guard_k := 0.0
var marks := {}             # combo setups on this body: status -> {by, owner, until}
var squash := 0.0           # landing / hit squash for the model
var remote := false         # driven by another player's game
var last_hit_by: Ent = null
var net_pos := Vector3.ZERO
var net_vel := Vector3.ZERO
var net_t := -1.0
var net_seen := 0.0

func setup(match_node: Node, id: String) -> void:
	m = match_node
	nid = id

func set_model(n: Node3D) -> void:
	if model:
		model.queue_free()
	model = n
	add_child(n)
	mats = n.get_meta("mats", [])

func teleport(p: Vector3) -> void:
	pos = p
	prev = p
	position = p

func ground() -> float:
	return m.world.ground_at(pos.x, pos.z)

## The height shots and blasts aim at to hit this body. (A hunter who has dropped below an
## island's lip is hit through the balloon floating at ground level above them.)
func hit_y() -> float:
	return pos.y

func over_void() -> bool:
	return m.world.is_void(pos.x, pos.z)

func flat_dist(o) -> float:
	var p: Vector3 = o.pos if o is Ent else o
	return Vector2(p.x - pos.x, p.z - pos.z).length()

func dir_to(o) -> Vector2:
	var p: Vector3 = o.pos if o is Ent else o
	return Vector2(p.x - pos.x, p.z - pos.z).normalized()

func alive() -> bool:
	return not dead

func hittable() -> bool:
	return not dead

## Generic damage. opts: kb (Vector2 impulse), lift, crit, src ("shot","kin","mob","boom","fall"), burn, slow, root
func hurt(dmg: float, by: Ent, opts := {}) -> float:
	if dead or dmg <= 0.0:
		return 0.0
	if remote:
		# someone else's game owns this body: show the hit here, let the owner apply it
		if m.net_send_hit(self, dmg, by, opts):
			flash_t = 0.12
			freeze_t = 0.04
			m.on_damage(self, by, dmg, opts)
			return dmg
		return 0.0
	# a combo: a status your partner (or you) set up pays off on this hit
	if by and not opts.has("combo") and not marks.is_empty():
		dmg = Combos.payoff(self, by, dmg, opts)
	if guard_t > 0.0:
		dmg *= 1.0 - guard_k
	var d := _mitigate(dmg, by, opts)
	if d <= 0.0:
		return 0.0
	hp -= d
	last_hit_by = by
	flash_t = 0.12
	freeze_t = 0.05 if d >= 10.0 else 0.03
	squash = 0.1
	if opts.has("kb"):
		impulse(opts["kb"], opts.get("lift", -1.0))
	if opts.get("burn", 0.0) > 0.0:
		burn_t = maxf(burn_t, 3.0); burn_dps = maxf(burn_dps, float(opts["burn"])); burn_by = by
	if opts.get("slow", 0.0) > 0.0:
		slow_t = maxf(slow_t, float(opts["slow"]))
	if opts.get("root", 0.0) > 0.0:
		root_t = maxf(root_t, float(opts["root"]))
	if opts.get("stun", 0.0) > 0.0:
		stun_t = maxf(stun_t, float(opts["stun"]))
	for st in ["stun", "root", "slow", "burn"]:
		if float(opts.get(st, 0.0)) > 0.0:
			CombatBus.status_applied.emit(self, st, by, float(opts[st]))
	m.on_damage(self, by, d, opts)
	# kin learn from fighting: count the hits and knockouts they land for their owner
	if opts.get("src", "") == "kin":
		var kn = by.kin if by is Hunter and by.kin else (by if by is Kin else null)
		if kn:
			kn.st_hits += 1
			if hp <= 0.0: kn.st_kos += 1
	if hp <= 0.0:
		_on_zero(by, opts)
	return d

func _mitigate(dmg: float, _by: Ent, _opts: Dictionary) -> float:
	return dmg

func _on_zero(_by: Ent, _opts: Dictionary) -> void:
	die()

func die() -> void:
	dead = true

func mass() -> float:
	return 1.0

var kb_time := -9.0

func impulse(kb: Vector2, lift := -1.0) -> void:
	var ms := mass()
	if kb.length() / ms > 4.0 and m: kb_time = m.time
	vel.x += kb.x / ms
	vel.z += kb.y / ms
	var s := kb.length() / ms
	if lift >= 0.0 or s > 6.0:
		var up := lift / ms if lift >= 0.0 else s * 0.45
		vel.y = maxf(vel.y, minf(9.0, up))
		grounded = false

## Gravity and landing for bodies that don't need hunter physics.
func body_vertical(dt: float) -> void:
	var g := ground()
	if grounded and g < pos.y - 0.05:
		grounded = false
		vel.y = minf(vel.y, 0.0)
	if not grounded:
		vel.y -= GRAV * dt
		pos.y += vel.y * dt
		if g > World.VOID + 1.0 and vel.y <= 0.0 and pos.y <= g and pos.y > g - 1.2:
			pos.y = g
			vel.y = 0.0
			grounded = true
			squash = 0.2
	else:
		pos.y = g
	if pos.y < -14.0:
		fall_out()

func fall_out() -> void:
	m.on_fell(self)

## Horizontal move with walls and rocks; returns true if it bumped something.
func slide(dt: float, guard := false) -> bool:
	var bumped := false
	var nx := pos.x + vel.x * dt
	var b1: float = m.world.occupy(nx, pos.z, r, pos.y, guard)
	if b1 == 0.0:
		pos.x = nx
	else:
		vel.x *= -0.1; bumped = true
	var nz := pos.z + vel.z * dt
	var b2: float = m.world.occupy(pos.x, nz, r, pos.y, guard)
	if b2 == 0.0:
		pos.z = nz
	else:
		vel.z *= -0.1; bumped = true
	return bumped

func tick_status(dt: float) -> void:
	if flash_t > 0.0: flash_t -= dt
	if freeze_t > 0.0: freeze_t -= dt
	if slow_t > 0.0: slow_t -= dt
	if root_t > 0.0: root_t -= dt
	if stun_t > 0.0: stun_t -= dt
	if guard_t > 0.0: guard_t -= dt
	if burn_t > 0.0 and not dead:
		burn_t -= dt
		if not remote:
			hp -= burn_dps * dt
			if int(burn_t * 4.0) != int((burn_t + dt) * 4.0):
				m.fx.number(pos + Vector3(0, 1.4, 0), burn_dps * 0.25, Color("ff9a4a"), false)
			if hp <= 0.0:
				_on_zero(burn_by, {"src": "burn"})

## Proxies glide toward the last position their owner reported.
func net_follow(dt: float) -> void:
	prev = pos
	if net_t < 0.0:
		return
	var age := clampf(m.time - net_t, 0.0, 0.25)
	var tgt := net_pos + net_vel * age
	if pos.distance_to(tgt) > 4.0:
		pos = tgt
	else:
		pos = pos.lerp(tgt, 1.0 - exp(-14.0 * dt))
	vel = net_vel

## Called every rendered frame. alpha blends between the last two simulation steps.
func render(delta: float, alpha: float) -> void:
	if freeze_t <= 0.0:
		position = prev.lerp(pos, alpha)
	squash = maxf(0.0, squash - delta * 2.5)
	var f := clampf(flash_t / 0.12, 0.0, 1.0)
	for mt in mats:
		mt.set_shader_parameter("flash", f)
