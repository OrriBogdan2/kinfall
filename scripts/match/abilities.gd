class_name Abil
## Shared ability helpers used by gear and areas.

## A burst around a point that knocks foes away from it.
static func _blast(h: Hunter, at: Vector3, radius: float, dmg: float, kb: float, col: Color, lift := 4.0, ab := "e") -> void:
	var m: Match = h.m
	m.fx.ring(at, radius, col, 0.3)
	m.fx.burst(at + Vector3(0, 0.4, 0), col, 24, 6.0, 0.5, 6.0, 1.2)
	m.net_fx(["ring", m._r(at.x), m._r(at.y), m._r(at.z), radius, col.to_html(false)])
	m.sfx("boom", at, -2.0)
	m.note_sound(h, at, "boom")
	for f in m.foes_of(h.team):
		var rel := Vector2(f.pos.x - at.x, f.pos.z - at.z)
		if rel.length() < radius + f.r and absf(f.pos.y - at.y) < 2.0:
			var dir := rel.normalized() if rel.length() > 0.05 else Vector2(1, 0)
			f.hurt(dmg * m.dmg_mult(h), h, {"kb": dir * kb, "lift": lift, "src": "abil", "ab": ab})
