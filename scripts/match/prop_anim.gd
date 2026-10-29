class_name PropAnim
extends Node
## Idle motion for a prop: spins and bobs its parent node, so crystals float and portals turn.

var spin := 0.0
var bob := 0.0
var bob_rate := 1.6
var base_y := 0.0
var t := randf() * TAU

static func on(n: Node3D, spin_rate: float, bob_amp := 0.0, rate := 1.6) -> void:
	var a := PropAnim.new()
	a.spin = spin_rate; a.bob = bob_amp; a.bob_rate = rate
	a.base_y = n.position.y
	n.add_child(a)

func _process(dt: float) -> void:
	var p := get_parent() as Node3D
	if p == null or not p.is_visible_in_tree():
		return
	t += dt
	p.rotation.y += spin * dt
	if bob != 0.0:
		p.position.y = base_y + sin(t * bob_rate) * bob
