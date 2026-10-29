class_name JumpPad
extends Area3D
## Launches anything that walks on. Keeps the hunter's horizontal momentum;
## dashing into it carries the dash speed plus a small boost.

@export var launch_up := 17.0      ## [est]
@export var forward_boost := 2.0   ## [est] extra push in the hunter's travel direction
@export var arm_delay := 0.0       ## Supervive consumable pads arm after 2s


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if arm_delay > 0.0:
		return
	if body.has_method("launch"):
		var v: Vector3 = body.velocity
		var flat := Vector3(v.x, 0.0, v.z)
		var push := flat.normalized() * forward_boost if flat.length() > 0.5 else Vector3.ZERO
		body.launch(Vector3.UP * launch_up + push)


func _process(delta: float) -> void:
	arm_delay = maxf(arm_delay - delta, 0.0)
