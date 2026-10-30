class_name Mob
extends Ent
## Monsters. Each attack is telegraphed on the ground before it lands.

var mkind := "skitter"
var md: Dictionary = {}
var st := "idle"            # idle | chase | windup | lunge | recover
var st_t := 0.0
var tgt: Ent = null
var camp := Vector3.ZERO
var atk_dir := Vector2.ZERO
var atk_at := Vector3.ZERO
var tele: Node3D = null
var cd := 0.0
var wander := Vector3.INF
var lunge_hit := {}
var anim := 0.0
var dmg_mult := 1.0
var calm_t := 0.0
var death_t := 0.0
## Stagger, as in Supervive: elites and bosses open short "staggerable" windows (a purple ring),
## always while winding up a slam. Land an ability in one (not a regular shot) and it takes a big
## hit, is stunned for a few seconds, takes extra damage the whole time, and the ability that did
## it comes straight back off cooldown.
const STAGGER_DMG := 2.5
var stag_open := 0.0
var stag_next := 0.0
var stagger_t := 0.0
var stag_ring: MeshInstance3D = null
var stag_stars: Node3D = null           # a treasure kin slips away if nobody hurts it for a while

func init_mob(match_node: Node, id: String, k: String, at: Vector3, tier := 1.0) -> void:
	setup(match_node, id)
	kind = "mob"
	team = -2
	mkind = k
	md = Data.MOBS[k]
	max_hp = float(md["hp"]) * tier
	hp = max_hp
	dmg_mult = 1.0 + (tier - 1.0) * 0.6
	r = md["r"]
	camp = at
	cd = randf_range(0.5, 1.5)
	set_model(Models.mob(k))
	teleport(at)
	if md.get("stag", false):
		stag_next = randf_range(3.0, 7.0)
		stag_ring = MeshInstance3D.new(); stag_ring.mesh = Models.flat_quad(r * 2.0 + 1.4)
		stag_ring.material_override = Models.ring_mat(Color("c47aff"), 0.12)
		stag_ring.position.y = 0.06; stag_ring.visible = false
		add_child(stag_ring)
		stag_stars = Node3D.new(); stag_stars.visible = false
		stag_stars.position.y = 1.2 + r
		for i in 3:
			Models.part(stag_stars, Models.sphere(0.09, 8), Models.toon(Color("fff27a"), false, 1.4), Vector3(cos(TAU * i / 3.0) * 0.45, 0, sin(TAU * i / 3.0) * 0.45))
		add_child(stag_stars)

func mass() -> float:
	if mkind == "sentinel": return 50.0
	return 6.0 if mkind == "warden" else (3.0 if mkind == "brute" else 1.0)

func _on_zero(by: Ent, opts: Dictionary) -> void:
	die()
	_cancel_tele()
	m.on_mob_dead(self, by, opts)

func _cancel_tele() -> void:
	if tele:
		m.fx.end_telegraph(tele)
		tele = null

func hurt(d: float, by: Ent, opts := {}) -> float:
	if not remote and not dead and d > 0.0:
		if stagger_t > 0.0:
			d *= STAGGER_DMG
		elif stag_open > 0.0 and opts.has("ab"):
			d += max_hp * (0.08 if mkind == "warden" else 0.2)
			_stagger(by, opts)
	var dealt := super.hurt(d, by, opts)
	if dealt > 0.0: calm_t = 0.0
	if dealt > 0.0 and by and not dead:
		var real: Ent = by
		if by is Kin and by.state != "active" and by.owner_h:
			real = by.owner_h
		if tgt == null or randf() < 0.4:
			tgt = real
			if st == "idle":
				st = "chase"
	return dealt

func _stagger(by: Ent, opts: Dictionary) -> void:
	stagger_t = 2.2 if mkind == "warden" else 3.0
	stun_t = maxf(stun_t, stagger_t)
	stag_open = 0.0
	stag_next = randf_range(10.0, 14.0)
	_cancel_tele()
	st = "recover"; st_t = stagger_t
	m.on_stagger(self, by, String(opts.get("ab", "")))

## Opens and closes stagger windows. Runs on whoever owns the monster.
func _tick_stagger(dt: float) -> void:
	if stagger_t > 0.0:
		stagger_t -= dt
		return
	if stag_open > 0.0:
		stag_open -= dt
		return
	if st == "idle":
		return
	stag_next -= dt
	if stag_next <= 0.0:
		stag_open = 3.0
		stag_next = randf_range(9.0, 13.0)
		m.on_stag_open(self)

## Readability: only a couple of monsters press the attack on any one target at a time. The rest
## hang back at a distance, circling and waiting for a gap, so a fight is one or two clear threats
## instead of a swarm. Bosses always engage.
const MAX_ENGAGED := 2
var engaged := false
## Hooks for rarer monsters (biomes, mutations): 0 common up to the top rarity in Data.RARITY, and
## a list of mutations, each an icon id or {icon, name}. The HUD tints the bar frame and shows them.
var rarity := 0
var mutations: Array = []

func _engaged_on(t: Ent) -> int:
	var n := 0
	for mb in m.mobs:
		if mb != self and not mb.dead and mb.engaged and mb.tgt == t:
			n += 1
	return n

func _find_target() -> Ent:
	var best: Ent = null; var bd := 7.5 if st == "idle" else 11.0
	for h in m.hunters:
		if not h.targetable():
			continue
		var d := flat_dist(h)
		if d > 2.6 and h.reveal_t <= 0.0 and (m.world.in_bush(h.pos.x, h.pos.z) or m.in_smoke(h.pos)):
			continue        # hiding in the grass
		if d < bd and absf(h.pos.y - pos.y) < 2.5:
			bd = d; best = h
	for k in m.kins:
		if k.is_wild() or k.state != "active":
			continue
		var d := flat_dist(k)
		if d < bd * 0.8:
			bd = d; best = k
	return best

func sim(dt: float) -> void:
	prev = pos
	if dead:
		return
	tick_status(dt)
	if remote:
		st_t -= dt
		net_follow(dt)
		_net_telegraph()
		return
	cd -= dt
	st_t -= dt
	if md.get("stag", false):
		_tick_stagger(dt)
	if md.get("flee", false):
		calm_t += dt
		if calm_t > 30.0:
			m.on_mob_escaped(self)
			return
	var spd: float = md["speed"] * (0.55 if slow_t > 0.0 else 1.0)
	if root_t > 0.0 or stun_t > 0.0:
		spd = 0.0
		if stun_t > 0.0 and st == "windup":
			# a stun interrupts the attack
			_cancel_tele(); st = "recover"; st_t = 0.4
	var wish := Vector2.ZERO
	match st:
		"idle":
			if randf() < dt * 2.0:
				tgt = _find_target()
				if tgt:
					st = "chase"
			if wander == Vector3.INF or flat_dist(wander) < 0.4 or randf() < dt * 0.2:
				var a := randf() * TAU
				var q := camp + Vector3(cos(a), 0, sin(a)) * randf_range(0.5, 3.0)
				if not m.world.is_void(q.x, q.z) and not m.world.is_block(q.x, q.z):
					wander = q
			if wander != Vector3.INF:
				wish = dir_to(wander) * spd * 0.3
		"chase":
			if tgt == null or tgt.dead or not tgt.hittable() or (tgt is Hunter and not tgt.targetable()) or flat_dist(camp) > 13.0:
				tgt = _find_target()
				engaged = false
				if tgt == null:
					st = "idle"
					wish = dir_to(camp) * spd
			if tgt and md.get("flee", false):
				# treasure kin run from whoever is closest, zig-zagging a little
				var away := -dir_to(tgt)
				wish = away.rotated(sin(m.time * 3.0 + float(nid.hash() % 7)) * 0.7) * spd
				if flat_dist(tgt) > 12.0: tgt = null; st = "idle"
			elif tgt:
				var d := flat_dist(tgt)
				if not engaged:
					engaged = mkind in ["warden", "sentinel"] or _engaged_on(tgt) < MAX_ENGAGED
				var want: float = md["range"] * (0.85 if mkind != "spitter" else 0.9)
				if mkind == "sentinel": want = 1e9
				if not engaged:
					# waiting its turn: keep a few steps off and circle, never attacking
					var hold := maxf(4.5, float(md["range"]) + 2.5)
					var to_t := dir_to(tgt)
					var side := Vector2(-to_t.y, to_t.x) * (1.0 if int(nid.hash()) % 2 == 0 else -1.0)
					wish = (to_t * clampf(d - hold, -1.0, 1.0) + side * 0.45) * spd * 0.6
				elif d > want:
					wish = dir_to(tgt) * spd
				elif mkind == "spitter" and d < 3.0:
					wish = -dir_to(tgt) * spd
				if engaged and d <= md["range"] + tgt.r and cd <= 0.0 and m.world.los(pos, tgt.pos, pos.y + 0.8) and not m.opts.get("training", false):
					_begin_attack()
		"windup":
			if tgt and md["attack"] in ["lunge", "spit", "volley"]:
				# track the target a little during the windup, then commit
				if st_t > float(md["windup"]) * 0.4:
					atk_dir = atk_dir.slerp(dir_to(tgt), dt * 4.0)
					if tele:
						m.fx.aim_telegraph(tele, pos, atk_dir)
			if tele:
				m.fx.telegraph_progress(tele, 1.0 - st_t / float(md["windup"]))
			if st_t <= 0.0:
				_strike()
		"lunge":
			vel.x = atk_dir.x * 12.0; vel.z = atk_dir.y * 12.0
			for e in m.foes_of(team):
				if lunge_hit.has(e.nid): continue
				if flat_dist(e) < e.r + r + 0.3 and absf(e.pos.y - pos.y) < 1.2:
					lunge_hit[e.nid] = true
					e.hurt(md["dmg"] * dmg_mult, self, {"kb": atk_dir * 4.0, "src": "mob"})
			if st_t <= 0.0:
				st = "recover"; st_t = 0.45
				vel.x *= 0.2; vel.z *= 0.2
		"recover":
			if st_t <= 0.0:
				st = "chase"
	if st != "lunge":
		var hv := Vector2(vel.x, vel.z)
		var k := 10.0 if hv.length() <= spd * 1.3 else 2.5
		hv += (wish - hv) * (1.0 - exp(-k * dt))
		var ahead := Vector2(pos.x, pos.z) + hv.normalized() * (r + 0.3)
		if grounded and hv.length() <= spd * 1.3 and m.world.is_void(ahead.x, ahead.y):
			hv = Vector2.ZERO
		vel.x = hv.x; vel.z = hv.y
	var pre_v := Vector2(vel.x, vel.z).length()
	if slide(dt) and m.time - kb_time < 0.6 and pre_v > 7.5 and mass() < 10.0:
		# knocked into a wall or rock: stunned
		kb_time = -9.0
		stun_t = maxf(stun_t, 1.0)
		if st == "windup": _cancel_tele(); st = "recover"; st_t = 1.0
		m.on_wall_slam(self, 1.0)
		hurt(10.0, last_hit_by, {"src": "wall"})
	body_vertical(dt)
	var look := atk_dir if st in ["windup", "lunge"] else Vector2(vel.x, vel.z)
	if look.length() > 0.2:
		face = lerp_angle(face, atan2(-look.x, -look.y), minf(1.0, dt * 10.0))

func _begin_attack() -> void:
	st = "windup"
	st_t = md["windup"]
	atk_dir = dir_to(tgt)
	match md["attack"]:
		"lunge":
			tele = m.fx.telegraph_rect(pos, atk_dir, 2.6, 0.8, Color("ff6a4a"))
		"spit":
			tele = m.fx.telegraph_rect(pos, atk_dir, 8.0, 0.45, Color("ffb04a"))
		"slam":
			atk_at = pos + Vector3(atk_dir.x, 0, atk_dir.y) * 0.9
			tele = m.fx.telegraph_circle(atk_at, float(md.get("slam_r", 2.3)), Color("ff4a3a"))
			if md.get("stag", false) and stagger_t <= 0.0:
				if stag_open <= 0.0: m.on_stag_open(self)
				stag_open = maxf(stag_open, float(md["windup"]) + 0.15)
		"fuse":
			atk_at = pos
			tele = m.fx.telegraph_circle(atk_at, float(md.get("slam_r", 2.3)), Color("ff8a2a"))
		"volley":
			tele = m.fx.telegraph_rect(pos, atk_dir, 10.0, 1.1, Color("6ad8ff"))
	# each kind has its own call as it winds up, instead of the same alarm for everyone
	m.sfx("v_" + mkind, pos, -9.0 if mkind != "warden" else -3.0, randf_range(0.9, 1.12))

func _strike() -> void:
	_cancel_tele()
	cd = md["cd"] * randf_range(0.85, 1.15)
	match md["attack"]:
		"lunge":
			st = "lunge"; st_t = 0.2; lunge_hit = {}
		"spit":
			st = "recover"; st_t = 0.5
			m.spawn_shot(self, pos + Vector3(atk_dir.x * 0.6, 0.8, atk_dir.y * 0.6), atk_dir * 8.5, md["dmg"] * dmg_mult, 8.5 / 8.5, 0.32, Color("b6ff6a"), {"mob": true, "kb": 2.0})
			m.sfx("thump", pos, -8.0, 1.4)
		"volley":
			st = "recover"; st_t = 0.6
			for k in [-0.2, 0.0, 0.2]:
				var d := atk_dir.rotated(k)
				m.spawn_shot(self, pos + Vector3(d.x * 0.6, 1.0, d.y * 0.6), d * 9.5, md["dmg"] * dmg_mult, 10.5 / 9.5, 0.28, Color("8ae8ff"), {"mob": true, "kb": 2.5})
			m.sfx("rifle", pos, -6.0, 1.5)
		"fuse":
			# a puffbomb goes off and takes itself with it
			var rad := float(md.get("slam_r", 2.3))
			m.fx.ring(atk_at, rad, Color("ffb070"), 0.35)
			m.net_fx(["ring", m._r(atk_at.x), m._r(atk_at.y), m._r(atk_at.z), rad, "ffb070"])
			m.fx.burst(atk_at + Vector3(0, 0.5, 0), Color("ffb070"), 28, 6.5, 0.55, 6.0, 1.3)
			m.shake(0.5, atk_at)
			m.sfx("boom", atk_at, 0.0, 1.1)
			for e in m.foes_of(team):
				var to := Vector2(e.pos.x - atk_at.x, e.pos.z - atk_at.z)
				if to.length() < rad + e.r and absf(e.pos.y - pos.y) < 1.6:
					e.hurt(md["dmg"] * dmg_mult, self, {"kb": to.normalized() * 9.5, "lift": 6.5, "src": "mob"})
			hp = 0.0
			_on_zero(null, {"self": true})
			return
		"slam":
			st = "recover"; st_t = 0.8
			m.fx.ring(atk_at, float(md.get("slam_r", 2.3)), Color("ffb090"), 0.3)
			m.net_fx(["ring", m._r(atk_at.x), m._r(atk_at.y), m._r(atk_at.z), float(md.get("slam_r", 2.3)), "ffb090"])
			m.fx.dust(atk_at, 16)
			m.shake(0.4, atk_at)
			m.sfx("boom", atk_at, -2.0, 0.8)
			for e in m.foes_of(team):
				var to := Vector2(e.pos.x - atk_at.x, e.pos.z - atk_at.z)
				if to.length() < float(md.get("slam_r", 2.3)) + e.r and absf(e.pos.y - pos.y) < 1.5:
					e.hurt(md["dmg"] * dmg_mult, self, {"kb": to.normalized() * 7.0, "lift": 5.0, "src": "mob"})

func render(delta: float, alpha: float) -> void:
	super.render(delta, alpha)
	visible = not dead
	if stag_ring:
		stag_ring.visible = stag_open > 0.0 and stagger_t <= 0.0
		if stag_ring.visible:
			var pul := 1.0 + sin(m.time * 10.0) * 0.08
			stag_ring.scale = Vector3(pul, 1.0, pul)
		stag_stars.visible = stagger_t > 0.0
		if stag_stars.visible:
			stag_stars.rotation.y += delta * 5.0
	if not model:
		return
	if dead:
		# a death pop: swell, flatten and blink out
		death_t += delta
		visible = death_t < 0.32
		if visible:
			var dk := death_t / 0.32
			var bd: Node3D = model.get_node("Body")
			var w := 1.0 + sin(minf(dk * 1.6, 1.0) * PI) * 0.35
			bd.scale = Vector3(w + dk * 0.3, maxf(0.05, 1.0 - dk * dk), w + dk * 0.3)
			for mt in mats:
				mt.set_shader_parameter("flash", 1.0 - dk * 0.5)
		return
	model.rotation.y = face
	var spd := Vector2(vel.x, vel.z).length()
	var moving := spd > 0.3
	anim += delta * (2.0 + minf(spd, 6.0) * 1.8 if moving else 2.0)
	var body: Node3D = model.get_node("Body")
	var wind := 0.0
	if st == "windup":
		wind = 1.0 - st_t / float(md["windup"])
	# shared body language: lean back and gather while winding up, shiver as it is about to go,
	# throw the weight forward on the attack, recoil when hit
	var shiver := sin(m.time * 60.0) * 0.03 * maxf(0.0, wind - 0.6) * 2.5
	var hurt_k := clampf(flash_t / 0.12, 0.0, 1.0)
	var lean := wind * 0.22 + hurt_k * 0.25
	if st == "lunge": lean = -0.45
	elif st == "recover" and stagger_t <= 0.0: lean = lerpf(body.rotation.x, -0.15, 0.5)
	if stagger_t > 0.0: lean = 0.2 + sin(m.time * 3.0) * 0.1
	body.rotation.x = lerpf(body.rotation.x, lean, 1.0 - exp(-16.0 * delta))
	body.rotation.z = shiver + (sin(m.time * 2.5) * 0.12 if stagger_t > 0.0 else 0.0)
	var gather := wind * 0.12
	if model.has_meta("anim"):
		_pack_anim(delta, moving, spd, wind)
		var sq0 := squash
		body.scale = Vector3(1.0 + sq0 * 0.3 + gather * 0.5, 1.0 - sq0 * 0.35 - gather * 0.5, 1.0 + sq0 * 0.3 + gather * 0.5)
		return
	match mkind:
		"skitter":
			body.position.y = absf(sin(anim)) * 0.05 * float(moving) - gather * 0.3
			for i in 3:
				for sx in [-1, 1]:
					var lg := body.get_node_or_null("Leg%d%d" % [i, sx]) as Node3D
					if lg == null: continue
					# tripod gait: legs 0 and 2 on one side move with leg 1 on the other
					var ph := anim * 1.6 + (PI if (i % 2 == 0) == (sx > 0) else 0.0)
					var mv := 1.0 if moving else 0.15
					lg.rotation.y = sin(ph) * 0.45 * mv
					lg.rotation.z = maxf(0.0, cos(ph)) * 0.35 * sx * mv - wind * 0.3 * sx
			var jaw := 0.25 + wind * 0.5 + (0.6 if st == "lunge" else 0.0) + sin(m.time * 7.0) * 0.06
			for jn in ["JawL", "JawR"]:
				var j := body.get_node_or_null(jn) as Node3D
				if j: j.rotation.y = jaw * (1.0 if jn == "JawL" else -1.0)
		"spitter":
			var bulb: Node3D = body.get_node("Bulb")
			bulb.scale = Vector3(1.0 - wind * 0.15, 0.9 + wind * 0.4, 1.0 - wind * 0.15) * (1.0 + sin(anim) * 0.03)
			bulb.rotation.x = -wind * 0.5 + (0.5 if st == "recover" else 0.0) * 0.5
			body.rotation.y = sin(m.time * 1.3) * 0.05
		"bomber":
			var sw := 1.0 + wind * 0.45 + sin(anim * (1.0 + wind * 6.0)) * 0.04 * (1.0 + wind * 3.0)
			body.get_node("Puff").scale = Vector3.ONE * sw
			body.position.y = absf(sin(anim)) * 0.1
		"glimmer":
			body.position.y = absf(sin(anim * 1.3)) * 0.16
			body.rotation.y += delta * 2.0
		"sentinel":
			var cr: Node3D = body.get_node("Crystal")
			cr.rotation.y += delta * (1.5 + wind * 10.0)
			cr.position.y = 1.25 + sin(anim * 0.6) * 0.08 + wind * 0.25
		"brute", "warden":
			var tor := body.get_node_or_null("Torso") as Node3D
			var ll := body.get_node_or_null("LegL") as Node3D
			var lr := body.get_node_or_null("LegR") as Node3D
			var al := tor.get_node_or_null("ArmL") as Node3D if tor else null
			var ar := tor.get_node_or_null("ArmR") as Node3D if tor else null
			var ph2 := anim * 0.9
			var mv := 1.0 if moving else 0.0
			var stride := sin(ph2) * 0.5 * mv
			if ll: ll.rotation.x = stride - wind * 0.3
			if lr: lr.rotation.x = -stride + wind * 0.2
			body.position.y = absf(cos(ph2)) * 0.06 * mv - wind * 0.1
			var arm_x := 0.0
			if st == "windup": arm_x = wind * 2.7                    # both fists up overhead
			elif st == "recover" and stagger_t <= 0.0 and st_t > 0.35: arm_x = 0.9   # slammed down in front
			if al: al.rotation.x = lerpf(al.rotation.x, arm_x - stride * 0.6, 1.0 - exp(-(30.0 if st == "recover" else 12.0) * delta))
			if ar: ar.rotation.x = lerpf(ar.rotation.x, arm_x + stride * 0.6, 1.0 - exp(-(30.0 if st == "recover" else 12.0) * delta))
			if al: al.rotation.z = -0.15 - wind * 0.2
			if ar: ar.rotation.z = 0.15 + wind * 0.2
			if tor:
				tor.rotation.y = sin(ph2) * 0.12 * mv
				tor.rotation.x = -0.12 * mv + wind * 0.15
	var sq := squash
	body.scale = Vector3(1.0 + sq * 0.3 + gather, 1.0 - sq * 0.35 - gather, 1.0 + sq * 0.3 + gather)

## Monsters dressed in pack models play the model's own clips: idle, walk or run by speed; while
## winding up, the attack clip is scrubbed up to the frame its blow lands on, then plays on from
## there as the attack goes off. Off-screen ones stop animating.
func _pack_anim(delta: float, moving: bool, spd: float, wind: float) -> void:
	var ap: AnimationPlayer = model.get_meta("anim")
	var C: Dictionary = model.get_meta("clips")
	var cam = m.get("cam")
	var far := cam != null and Vector2(pos.x - cam.focus.x, pos.z - cam.focus.z).length() > 30.0
	ap.active = not far
	if far:
		return
	var atk := String(C["attack"])
	if st == "windup":
		if ap.current_animation != atk:
			ap.play(atk, 0.12)
		ap.speed_scale = 0.0
		ap.seek(ap.get_animation(atk).length * float(C["hit"]) * clampf(wind, 0.0, 1.0), true)
		return
	if ap.current_animation == atk and ap.is_playing() and ap.current_animation_position < ap.current_animation_length - 0.05:
		ap.speed_scale = 1.4      # the blow and the follow-through
		return
	var want := String(C["idle"])
	var rate := 1.0
	if stagger_t > 0.0:
		rate = 0.35
	elif moving:
		want = String(C["run"]) if spd > 3.6 else String(C["walk"])
		rate = clampf(spd / (4.5 if spd > 3.6 else 2.2), 0.6, 1.7)
	if ap.current_animation != want:
		ap.play(want, 0.2)
	ap.speed_scale = rate

## Telegraphs on proxies follow the host's attack state.
func _net_telegraph() -> void:
	if st == "windup":
		if tele == null:
			match md["attack"]:
				"lunge": tele = m.fx.telegraph_rect(pos, atk_dir, 2.6, 0.8, Color("ff6a4a"))
				"spit": tele = m.fx.telegraph_rect(pos, atk_dir, 8.0, 0.45, Color("ffb04a"))
				"slam": tele = m.fx.telegraph_circle(pos + Vector3(atk_dir.x, 0, atk_dir.y) * 0.9, float(md.get("slam_r", 2.3)), Color("ff4a3a"))
				"fuse": tele = m.fx.telegraph_circle(pos, float(md.get("slam_r", 2.3)), Color("ff8a2a"))
				"volley": tele = m.fx.telegraph_rect(pos, atk_dir, 10.0, 1.1, Color("6ad8ff"))
		elif md["attack"] in ["lunge", "spit", "volley"]:
			m.fx.aim_telegraph(tele, pos, atk_dir)
		if tele:
			m.fx.telegraph_progress(tele, 1.0 - st_t / float(md["windup"]))
	elif tele:
		_cancel_tele()
